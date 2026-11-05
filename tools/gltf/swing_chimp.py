"""The Night Ops Chimp's Swing clip: swinging hand over hand through the trees (brachiation), baked into its
rigged model beside Idle and Running. No Blender: numpy on the glTF itself, with tools/gltf/rig_infiltrator.py's
rig and pose helpers, like tools/gltf/swim_bear.py.

In a forest a chimp goes faster than on open ground (UnitTypes forest_speed) because it travels up in the trees,
swinging from branch to branch. AttackerUnit lifts it up into them (the clip's holds HOLD_Y over its origin, the
game puts them under the canopy) and plays this clip at SPEED (m/s: the chimp's forest speed) or near it.

One loop is two swings, the left hand's then the right's (the right holds its axe and grips the branch with it):
each hand takes a hold STRIDE ahead of the one before, HOLD_X out to its side, and the body swings forward under
it like a pendulum (lowest under the hold, leaning toward it), the free hand swinging down past its side and
reaching on for the next; it lets go a little past the bottom of the swing and flies on to the next hold (CONTACT of each
swing on the branch). The holds are fixed in the world: in the clip they slide back at SPEED. The legs hang, knees
bent, swinging behind on the catch and forward on the release; the head keeps looking ahead.

The fingers and the axe's bones keep the Running clip's first frame. The clip loops (the last frame a copy of the
first, as the game expects of baked loops).

  python3 tools/gltf/swing_chimp.py --input game/assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb \\
      --output game/assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb [--preview out.png]

Run again on its own output it replaces the clip it baked before.
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arm_rifle import sample_clip, set_frame  # noqa: E402
from gltf_io import add_accessor, axis_angle, compact, mat_to_quat, read_glb, rotation, translation, write_glb  # noqa: E402
from rig_infiltrator import Pose, Rig, X, Y, Z, place_chain, two_bone, unit  # noqa: E402

FPS = 30.0
P = "mixamorig:"
SIDES = {"L": "Left", "R": "Right"}
NAME = "Swing"
## Its speed through the trees (m/s: UnitTypes chimp speed * forest_speed), a loop (two swings, s) and how much of
## each swing a hand is on its branch.
SPEED = 8.8
LOOP = 0.8
CONTACT = 0.45
## The holds: how high over the unit's origin (m) and how far out to the side of the middle.
HOLD_X = 0.12
HOLD_Y = 2.45
## The shoulders lag behind the root at the catch and run ahead of it at the release (m, the most either way).
SURGE = 0.2
## The body leans toward the hold this share of the arm's swing; it rolls (the hand's shoulder up) and turns (the
## hand's shoulder ahead) toward the hand on the branch (deg).
LEAN = 0.35
ROLL = 9.0
TWIST = 14.0
## In flight the body carries on up off the release this share of the swing's rise (and comes down onto the catch
## likewise), a low hop from branch to branch.
FLING = 0.2
## The arm on the branch is this share of its full reach (the elbow a little soft).
STRAIGHT = 0.985
## Wrist to the middle of the grip (m, along the hand).
GRIP = 0.09
## Hips (deg, forward negative about +X): the legs swinging with the body, and the knees' bend (least, most).
THIGH = (-14.0, 20.0)
KNEE = (14.0, 46.0)

STRIDE = SPEED * LOOP * 0.5


def bone(side, part):
    return P + SIDES[side] + part


class Swinger:
    def __init__(self, rig, base):
        self.rig = rig
        self.base = base  # the Running clip's first frame (fingers, the axe)
        self.len = {}
        for s in "LR":
            up, lo, ha = bone(s, "Arm"), bone(s, "ForeArm"), bone(s, "Hand")
            self.len[s] = (np.linalg.norm(rig.rest(lo)[:3, 3] - rig.rest(up)[:3, 3]),
                           np.linalg.norm(rig.rest(ha)[:3, 3] - rig.rest(lo)[:3, 3]))
        self.reach = {s: (sum(self.len[s]) * STRAIGHT + GRIP) for s in "LR"}
        rest_sh = (rig.rest(bone("L", "Arm"))[:3, 3] + rig.rest(bone("R", "Arm"))[:3, 3]) * 0.5
        self.sh_half = (rig.rest(bone("L", "Arm"))[0, 3] - rig.rest(bone("R", "Arm"))[0, 3]) * 0.5
        self.hips_to_sh = rest_sh - rig.rest(P + "Hips")[:3, 3]

    # ---------------------------------------------------------------- the way the body goes

    def hold(self, h, u):
        """Where the hand of swing h (0 left, 1 right) holds at phase u of that swing (root frame)."""
        side = 1.0 if h == 0 else -1.0
        z = STRIDE * CONTACT * 0.5 - STRIDE * u
        return np.array([side * HOLD_X, HOLD_Y, z])

    def surge(self, u):
        if u <= CONTACT:
            return SURGE * math.cos(math.pi * u / CONTACT)
        return -SURGE * math.cos(math.pi * (u - CONTACT) / (1.0 - CONTACT))

    def contact_shoulders(self, h, u):
        """The shoulders' middle (y, z) while hand h is on its branch: right under its reach of the hold."""
        side = 1.0 if h == 0 else -1.0
        hold = self.hold(h, u)
        z = self.surge(u)
        sh = np.array([side * self.sh_half, 0.0, z])  # this hand's shoulder (x), its height to find
        flat = np.hypot(hold[0] - sh[0], hold[2] - z)
        r = self.reach["L" if h == 0 else "R"]
        y = hold[1] - math.sqrt(max(r * r - flat * flat, 0.04))
        return y, z

    def shoulders(self, h, u):
        """The shoulders' middle (y, z) at phase u of swing h, flying between holds after CONTACT."""
        if u <= CONTACT:
            return self.contact_shoulders(h, u)
        # In flight: a smooth way from letting go to the next catch, its slopes those of the swings either side
        # (tamed a little: the release flings it up, the catch drops it).
        y0, z0 = self.contact_shoulders(h, CONTACT)
        y1, z1 = self.contact_shoulders(1 - h, 0.0)
        e = 1e-3
        m0 = (y0 - self.contact_shoulders(h, CONTACT - e)[0]) / e
        m1 = (self.contact_shoulders(1 - h, e)[0] - y1) / e
        span = 1.0 - CONTACT
        s = (u - CONTACT) / span
        s2, s3 = s * s, s * s * s
        y = (2 * s3 - 3 * s2 + 1) * y0 + (s3 - 2 * s2 + s) * m0 * span * FLING + (-2 * s3 + 3 * s2) * y1 + (s3 - s2) * m1 * span * FLING
        return y, self.surge(u)

    def arm_angle(self, h, u):
        """How far the hand on the branch is ahead of its shoulder (rad, from straight up), or between the last swing's
        release and the next one's catch."""
        def at(hh, uu):
            hold = self.hold(hh, uu)
            y, z = self.contact_shoulders(hh, uu)
            return math.atan2(hold[2] - z, hold[1] - y)
        if u <= CONTACT:
            return at(h, u)
        a0, a1 = at(h, CONTACT), at(1 - h, 0.0)
        s = (u - CONTACT) / (1.0 - CONTACT)
        return a0 + (a1 - a0) * (0.5 - 0.5 * math.cos(math.pi * s))

    def which(self, h, u):
        """-1..1: toward the left hand (1) or the right (-1) for roll and twist, easing over at the catches."""
        side = 1.0 if h == 0 else -1.0
        if u <= CONTACT:
            return side
        s = (u - CONTACT) / (1.0 - CONTACT)
        return side * math.cos(math.pi * s)

    # ---------------------------------------------------------------- the pose

    def pose(self, pose, t):
        """The pose t (0..1) into the loop."""
        rig = self.rig
        pose.reset()
        set_frame(pose, rig, self.base, 0)
        for b in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"] + [SIDES[s] + p for s in "LR" for p in
                                                                      ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot")]:
            pose.basis.pop(P + b, None)
        pose._world = {}
        h = 0 if t < 0.5 else 1
        u = (t % 0.5) * 2.0
        y, z = self.shoulders(h, u)
        theta = self.arm_angle(h, u)
        w = self.which(h, u)
        # The body: leaning toward the hold, rolled and turned toward the hand on it.
        lean = LEAN * theta
        body = axis_angle(Y, -math.radians(TWIST) * w) @ axis_angle(Z, -math.radians(ROLL) * w) @ axis_angle(X, lean)
        rest = rig.rest(P + "Hips")
        hips = rest.copy()
        hips[:3, :3] = body @ rest[:3, :3]
        hips[:3, 3] = np.array([0.0, y, z]) - body @ self.hips_to_sh
        pose.place(P + "Hips", hips)
        # A little more curl down the back and the neck, the head up and level looking ahead.
        for b in ("Spine", "Spine1", "Spine2"):
            pose.turn(P + b, X, math.radians(4.0) - lean * 0.12)
        pose.turn(P + "Neck", X, -lean * 0.45 - math.radians(8.0))
        pose.turn(P + "Head", X, -lean * 0.25 - math.radians(6.0))
        # Put the shoulders' middle where it goes (the spine moved it a little).
        for _ in range(2):
            sh = (pose.head(bone("L", "Arm")) + pose.head(bone("R", "Arm"))) * 0.5
            err = np.array([0.0, y, z]) - sh
            hips[:3, 3] += err
            pose.place(P + "Hips", hips)
        # Arms: the one on the branch to its hold, the free one round from behind and on to its next hold.
        for s, hh in (("L", 0), ("R", 1)):
            side = 1.0 if s == "L" else -1.0
            up, lo = bone(s, "Arm"), bone(s, "ForeArm")
            # The collarbone up as the arm goes up over the head.
            pose.turn(bone(s, "Shoulder"), Z, side * math.radians(18.0))
            sh = pose.head(up)
            on = (hh == h and u <= CONTACT)
            if on:
                grip = self.hold(hh, u)
            else:
                grip = self.free_hand(s, hh, h, u, sh)
            d = unit(grip - sh)
            wrist = grip - d * GRIP
            l1, l2 = self.len[s]
            pole = unit(np.array([side * 0.85, -0.35, -0.4]))
            elbow, end = two_bone(sh, l1, l2, wrist, pole)
            place_chain(pose, up, lo, sh, elbow, end, pole)
            # The hand hooked over the branch, or open reaching for the next.
            pose.turn(bone(s, "Hand"), X, math.radians(-25.0 if on else -10.0))
        # Legs: hanging, swinging behind on the catch and forward on the release, knees bent.
        a = 2 * math.pi * u
        for s in "LR":
            side = 1.0 if s == "L" else -1.0
            sway = math.sin(a - 0.6)
            pose.turn(bone(s, "UpLeg"), X, math.radians(THIGH[0] + THIGH[1] * sway) - lean * 0.6)
            pose.turn(bone(s, "UpLeg"), Z, side * math.radians(3.0))
            pose.turn(bone(s, "Leg"), X, math.radians(KNEE[0] + (KNEE[1] - KNEE[0]) * (0.5 + 0.5 * math.sin(a + 0.9))))
            pose.turn(bone(s, "Foot"), X, math.radians(20.0))

    def free_hand(self, s, hh, h, u, sh):
        """The free hand of side s (swing hh): from where it let go, down by its side and forward, on to its next
        hold (root frame, as the body carries it)."""
        # Phase since it let go, over the whole time until its next catch.
        if hh == h:
            since = u - CONTACT  # this swing's release was at CONTACT
        else:
            since = (1.0 - CONTACT) + u
        span = (1.0 - CONTACT) + 1.0
        f = min(max(since / span, 0.0), 1.0)
        side = 1.0 if s == "L" else -1.0
        let_go = self.hold(hh, CONTACT) - self.at_shoulder(hh, CONTACT, s)
        catch = self.hold(hh, 0.0) - self.at_shoulder(hh, 0.0, s)
        # Around: swinging down by its side, then forward and up for the next branch.
        p0 = let_go
        p3 = catch
        p1 = np.array([side * 0.3, -0.5, -0.25])
        p2 = np.array([side * 0.32, -0.2, 0.5])
        g = (1 - f) ** 3 * p0 + 3 * (1 - f) ** 2 * f * p1 + 3 * (1 - f) * f * f * p2 + f ** 3 * p3
        return sh + g

    def at_shoulder(self, hh, u, s):
        """Shoulder s's position (root frame) at the catch or release of swing hh (no lean: near enough)."""
        side = 1.0 if s == "L" else -1.0
        y, z = self.contact_shoulders(hh, u)
        return np.array([side * self.sh_half, y, z])


def bake(js, binary, rig, swinger):
    """Keys every joint of the skin (rotation, translation, scale)."""
    n = int(round(LOOP * FPS)) + 1
    pose = Pose(rig)
    joints = [rig.nodes[j]["name"] for j in js["skins"][0]["joints"]]
    keys = {b: [] for b in joints}
    for f in range(n):
        swinger.pose(pose, (f % (n - 1)) / (n - 1))
        for b in keys:
            keys[b].append(pose.local(b))
    times = np.arange(n, dtype=np.float32) / FPS
    tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
    anim = {"name": NAME, "channels": [], "samplers": []}

    def channel(node, path, data, kind):
        anim["samplers"].append({"input": tin, "output": add_accessor(js, binary, np.array(data, dtype=np.float32), kind),
                                 "interpolation": "LINEAR"})
        anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": node, "path": path}})

    for b, mats in keys.items():
        quats = []
        prev = None
        for m in mats:
            q = mat_to_quat(m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0))
            if prev is not None and np.dot(q, prev) < 0:
                q = -q
            quats.append(q)
            prev = q
        node = rig.index[b]
        channel(node, "rotation", quats, "VEC4")
        channel(node, "translation", [m[:3, 3] for m in mats], "VEC3")
        channel(node, "scale", [np.linalg.norm(m[:3, :3], axis=0) for m in mats], "VEC3")
    js["animations"].append(anim)
    return n


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    args = p.parse_args()
    js, binary = read_glb(args.input)
    js["animations"] = [a for a in js["animations"] if a["name"] != NAME]
    rig = Rig(js)
    running = next(a for a in js["animations"] if a["name"] == "Running")
    base = sample_clip(js, binary, running)[0]
    swinger = Swinger(rig, base)
    n = bake(js, binary, rig, swinger)
    print(f"{NAME}: {n} frames ({LOOP} s), {STRIDE:.2f} m a swing at {SPEED} m/s, holds {HOLD_Y} m up;"
          f" reach {swinger.reach['L']:.2f} m")
    pose = Pose(rig)
    for t in (0.0, CONTACT * 0.25, CONTACT * 0.5, CONTACT * 0.5 + 0.25):
        swinger.pose(pose, t)
        print(f"   t {t:.2f}: hips {np.round(pose.head(P + 'Hips'), 2)}, left hand {np.round(pose.head(bone('L', 'Hand')), 2)},"
              f" toes {np.round(pose.head(bone('L', 'ToeBase')), 2)}")
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/swing_chimp.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}")
    if args.preview:
        render_preview(args.output, args.preview, swinger)


# ---------------------------------------------------------------- preview

def render_preview(path, out, swinger):
    """Frames of the loop (every third) from its left side, from ahead of it on its left and from behind it above,
    the holds as bars where they are in the world as it goes past them at SPEED."""
    from PIL import Image, ImageDraw
    from rig_infiltrator import rasterize
    from rig_sniper import load_textured
    js, binary = read_glb(path)
    rig = Rig(js)
    node = next(nd for nd in js["nodes"] if "skin" in nd)
    tex = load_textured(js, binary, js["meshes"][node["mesh"]]["primitives"][0])
    frames = sample_clip(js, binary, next(a for a in js["animations"] if a["name"] == NAME))[0]
    n = int(round(LOOP * FPS))
    bar_tex = np.ones((2, 2, 3), np.float32) * np.array([0.4, 0.27, 0.15], np.float32)
    # The holds of a loop and more, fixed in the world (z from where the loop starts).
    holds = [swinger.hold(k % 2, 0.0) + np.array([0.0, 0.0, STRIDE * k]) for k in range(-1, 4)]
    box = np.array([[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6], [0, 4, 5], [0, 5, 1], [3, 2, 6], [3, 6, 7], [0, 3, 7],
                    [0, 7, 4], [1, 5, 6], [1, 6, 2]])
    corner = np.array([[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]], float)
    bars = [corner * np.array([0.4, 0.035, 0.035]) + c for c in holds]
    views = [np.array([3.4, 0.0, 0.2]), np.array([1.8, 0.4, 2.7]), np.array([-1.2, 2.4, -2.5])]
    shown = list(range(0, n + 1, 3))
    W, H = 200, 250
    sheet = Image.new("RGB", (W * len(shown), H * len(views)))
    for c, f in enumerate(shown):
        pts, idx, uv, _ = posed_no_marker(js, binary, rig, frames, f % n)
        travelled = np.array([0.0, 0.0, SPEED * f / FPS])
        for r, e in enumerate(views):
            img = np.ones((H, W, 3), np.float32) * np.array([0.62, 0.72, 0.82], np.float32)
            zb = np.full((H, W), np.inf, np.float32)
            at = np.array([0.0, 1.75, 0.0])
            for b in bars:
                rasterize(img, zb, b - travelled, box, np.zeros((8, 2)), bar_tex, at + e, at, fov=46)
            rasterize(img, zb, pts, idx, uv, tex, at + e, at, fov=46)
            pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
            ImageDraw.Draw(pil).text((4, 4), f"{NAME} {f}", fill=(0, 0, 0))
            sheet.paste(pil, (c * W, r * H))
    sheet.save(out)
    print(f"preview {out}")


def posed_no_marker(js, binary, rig, frames, f):
    """The skinned mesh's vertices at frame f of a sampled clip (arm_rifle.posed without its gun bone)."""
    from gltf_io import accessor
    pose = Pose(rig)
    set_frame(pose, rig, frames, f)
    skin = js["skins"][0]
    ibm = accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4).transpose(0, 2, 1)
    mats = np.array([pose.world(rig.nodes[j]["name"]) @ ibm[k] for k, j in enumerate(skin["joints"])])
    node = next(nd for nd in js["nodes"] if "skin" in nd)
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    joints = accessor(js, binary, prim["attributes"]["JOINTS_0"]).astype(int)
    weights = accessor(js, binary, prim["attributes"]["WEIGHTS_0"]).astype(float)
    if weights.max() > 1.5:
        weights /= 255.0 if weights.max() <= 255 else 65535.0
    hom = np.concatenate([pos, np.ones((len(pos), 1))], 1)
    out = np.zeros((len(pos), 3))
    for k in range(4):
        out += weights[:, k:k + 1] * np.einsum("nij,nj->ni", mats[joints[:, k]], hom)[:, :3]
    idx = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    uv = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)
    return out, idx, uv, None


if __name__ == "__main__":
    main()
