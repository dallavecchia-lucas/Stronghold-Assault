"""Put a gun in a Meshy character's hands: the garrison's riflemen (the Shadowline assault rifle) and the
Bear Riflemen (the Prototype C heavy LMG). No Blender: numpy on the glTF itself, like
tools/gltf/rig_sniper.py (whose stance and hand frames it follows, much simplified).

Input: a processed Meshy character with its Mixamo-style auto-rig (mixamorig:* bones) and its Idle and
Running clips, and the gun from tools/gltf/process_rifle.py (muzzle +Z, Y up, origin at the pistol grip,
marker nodes `butt` and `support`). The mesh, its skin weights and the bone names stay as they are, and
so do the clips' legs, hips, spine and head: only the arms (and the fingers) are re-keyed.

The carry, in every clip: the butt in the right shoulder pocket (POCKET from the shoulder joint, scaled
to the character's height), the gun straight ahead and tipped muzzle-down by PITCH for the clip (level
enough to fire from at rest, lower at a run); the right hand on the pistol grip, the left at the gun's
`support` marker (on a vertical foregrip: --support-grip, else cradling it from below). The gun's place
is fixed in the chest's frame (Spine2, as the clip's mean chest lies) so it rides the chest's sway and
bob; the arms are solved by two-bone IK onto it every frame.

One marker bone (no weights) carries the gun: `rifle`, a child of Spine2, keyed in each clip. The game
hangs the gun model on it (a BoneAttachment3D: DefenderSoldier, AttackerUnit).

  python3 tools/gltf/arm_rifle.py --input game/assets/defenders/harpy_vanguard/harpy_vanguard.glb \\
      --gun game/assets/weapons/shadowline_rifle.glb --output game/assets/defenders/harpy_vanguard/harpy_vanguard_armed.glb \\
      [--preview out.png]
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, add_accessor, compact, mat_to_quat, quat_to_mat, read_glb, rotation, set_trs, translation, trs, write_glb  # noqa: E402
from rig_infiltrator import Pose, Rig, X, Y, Z, add_marker, frame_from, place_chain, two_bone, unit  # noqa: E402
import rig_infiltrator  # noqa: E402

FPS = 30.0
P = "mixamorig:"
CHEST = P + "Spine2"
# The butt this far from the right shoulder joint (toward the middle, down, forward) for a 1.7 m body.
POCKET = np.array([0.08, -0.03, 0.08])
REF_HEIGHT = 1.7
# Muzzle down (rad) per clip, and how far the gun turns in across the body (to her left, rad).
PITCH = {"Idle": math.radians(9.0), "Running": math.radians(24.0)}
CANT_IN = math.radians(6.0)
# The trigger hand in the gun's frame (X her left, Y up, Z out of the muzzle), for a 1.7 m body: the wrist
# behind the grip and to its right, the hand running forward and down GRIP_RAKE, the palm on the grip.
GRIP_WRIST = np.array([-0.026, -0.004, -0.07])
GRIP_RAKE = math.radians(26.0)
# The support hand from the `support` marker: on a vertical foregrip like the trigger hand, mirrored;
# else cradling the fore-end from below and its left.
FOREGRIP_WRIST = np.array([0.026, -0.004, -0.07])
CRADLE_WRIST = np.array([0.045, -0.035, -0.03])
HANDLE_WRIST = np.array([0.05, 0.03, -0.02])
SIDE_WRIST = np.array([0.055, -0.035, -0.05])
TRIGGER_CURL = {"Thumb": (25, 30, 20), "Index": (18, 32, 20), "Middle": (65, 85, 55), "Ring": (68, 85, 55), "Pinky": (70, 85, 55)}
GRIP_CURL = {"Thumb": (25, 30, 20), "Index": (60, 80, 50), "Middle": (65, 85, 55), "Ring": (68, 85, 55), "Pinky": (70, 85, 55)}
CRADLE_CURL = {"Thumb": (10, 15, 10), "Index": (35, 55, 35), "Middle": (38, 58, 35), "Ring": (40, 60, 38), "Pinky": (45, 60, 40)}
# Elbows (model space): the trigger arm's out to her right and down, the support arm's down and in.
POLES = {"R": unit(-X * 0.8 - Y * 0.6 - Z * 0.1), "L": unit(-Y + X * 0.4 - Z * 0.1)}
SIDES = {"R": "Right", "L": "Left"}
# How much of the chest's turning (its sway and twist through a clip) the gun takes on.
FOLLOW = 0.35


def blend(a, b, w):
    """Rotation (scaled as b is) w of the way from a's orientation to b's."""
    s = np.linalg.norm(b[:3, :3], axis=0)
    qa = mat_to_quat(a / np.linalg.norm(a, axis=0))
    qb = mat_to_quat(b / s)
    if np.dot(qa, qb) < 0:
        qb = -qb
    q = qa * (1 - w) + qb * w
    return quat_to_mat(q / np.linalg.norm(q)) * s


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--gun", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--support", choices=("cradle", "grip", "handle", "side"), default="cradle",
                   help="how the support hand holds the gun at its `support` marker (or `handle`)")
    p.add_argument("--chest-yaw", type=float, default=0.0,
                   help="degrees the chest turns to her right (bladed, the left shoulder forward); re-keys the spine")
    p.add_argument("--pole-l", default="", help="x,y,z: which way the left elbow points (model space)")
    p.add_argument("--fit", action="store_true", help="search the butt's place and the cant for the hands' reach")
    p.add_argument("--pocket", default="", help="x,y,z: the butt from the right shoulder joint (1.7 m body), instead of POCKET")
    p.add_argument("--cant", type=float, default=math.degrees(CANT_IN), help="degrees the gun turns in across the body")
    p.add_argument("--pitch", default="", help="Idle,Running: muzzle down (degrees), instead of PITCH")
    p.add_argument("--preview", default="")
    return p.parse_args()


def gun_markers(path):
    js, _ = read_glb(path)
    return {n["name"]: trs(n)[:3, 3].copy() for n in js["nodes"] if n.get("name") in ("muzzle", "eye", "butt", "support", "handle")}


def bone(side, part):
    return P + SIDES[side] + part


# ---------------------------------------------------------------- the clips as they are

def sample_clip(js, binary, anim):
    """The clip's local matrices per frame (30 fps, keys on the frame grid): {node: [4x4 per frame]}."""
    length = 0.0
    chans = []
    for ch in anim["channels"]:
        s = anim["samplers"][ch["sampler"]]
        t = accessor(js, binary, s["input"]).astype(float).reshape(-1)
        v = accessor(js, binary, s["output"]).astype(float)
        length = max(length, float(t[-1]))
        chans.append((ch["target"]["node"], ch["target"]["path"], t, v))
    n = int(round(length * FPS)) + 1
    times = np.arange(n) / FPS
    parts = {}
    for node, path, t, v in chans:
        k = np.clip(np.searchsorted(t, times - 1e-4), 0, len(t) - 1)
        parts.setdefault(node, {})[path] = v[k]
    out = {}
    for node, p in parts.items():
        base = trs(js["nodes"][node])
        mats = []
        for f in range(n):
            m = np.eye(4)
            r = quat_to_mat(p["rotation"][f]) if "rotation" in p else base[:3, :3] / np.linalg.norm(base[:3, :3], axis=0)
            sc = p["scale"][f] if "scale" in p else np.linalg.norm(base[:3, :3], axis=0)
            m[:3, :3] = r * sc
            m[:3, 3] = p["translation"][f] if "translation" in p else base[:3, 3]
            mats.append(m)
        out[node] = mats
    return out, n


# The spine's shares of --chest-yaw.
TWIST = {P + "Spine": 0.3, P + "Spine1": 0.35, P + "Spine2": 0.35}
CHEST_YAW = 0.0


def set_frame(pose, rig, frames, f):
    pose.reset()
    for node, mats in frames.items():
        name = rig.nodes[node].get("name")
        if name:
            pose.basis[name] = np.linalg.inv(rig.local[node]) @ mats[f]
    if CHEST_YAW:
        # Bladed: the chest turned to her right, the left shoulder forward (the first-person arms).
        for name, share in TWIST.items():
            pose.turn(name, Y, CHEST_YAW * share)


# ---------------------------------------------------------------- the carry

class Carry:
    def __init__(self, rig, marks, support_grip, height, pocket=POCKET, cant=CANT_IN):
        self.pocket = pocket
        self.cant = cant
        self.rig = rig
        self.marks = marks
        self.support_grip = support_grip
        self.k = height / REF_HEIGHT
        self.len = {}
        for s in "LR":
            up, lo, ha = bone(s, "Arm"), bone(s, "ForeArm"), bone(s, "Hand")
            self.len[s] = (np.linalg.norm(rig.rest(lo)[:3, 3] - rig.rest(up)[:3, 3]),
                           np.linalg.norm(rig.rest(ha)[:3, 3] - rig.rest(lo)[:3, 3]))
        # Palms face down in the T-pose: each hand's palm as a local axis.
        self.palm = {s: rig.rest(bone(s, "Hand"))[:3, :3].T @ -Y for s in "LR"}

    def place(self, pose, pitch):
        """The gun (model space) for the pose as it stands, and its frame in the chest's."""
        shoulder = pose.head(bone("R", "Arm"))
        chest = pose.world(CHEST)
        s = np.linalg.norm(chest[:3, :3], axis=0).mean()
        # The gun's bone takes on the chest's scale (a rig scaled as a whole): the gun is that much bigger.
        rot = rig_infiltrator.axis_angle(Y, self.cant) @ rig_infiltrator.axis_angle(X, pitch)
        butt = shoulder + self.pocket * self.k
        gun = translation(butt - rot @ self.marks["butt"] * s) @ rotation(rot * s)
        local = np.linalg.inv(chest) @ gun
        local[:3, :3] /= np.linalg.norm(local[:3, :3], axis=0)
        return local

    def hands(self, gun):
        """The wrists' targets (model space) for the gun at `gun` (scaled as its bone is)."""
        r = gun[:3, :3] / np.linalg.norm(gun[:3, :3], axis=0)

        def at(mark, offset):
            return (gun @ np.append(mark, 1.0))[:3] + r @ (offset * self.k)

        fingers_r = r @ unit(Z * math.cos(GRIP_RAKE) - Y * math.sin(GRIP_RAKE))
        hand_r = frame_from(Y, self.palm["R"], fingers_r, r @ X)
        wrist_r = at(np.zeros(3), GRIP_WRIST)
        if self.support_grip == "grip":
            hand_l = frame_from(Y, self.palm["L"], fingers_r, r @ -X)
            wrist_l = at(self.marks["support"], FOREGRIP_WRIST)
        elif self.support_grip == "side":
            # On the fore-end's left side: the palm against it, the fingers up and over the top.
            hand_l = frame_from(Y, self.palm["L"], r @ unit(Z * 0.45 + Y * 0.75 - X * 0.3), r @ -X)
            wrist_l = at(self.marks["support"], SIDE_WRIST)
        elif self.support_grip == "handle":
            # Over the carry handle: palm down on it, the fingers across it to her right, wrapping under.
            hand_l = frame_from(Y, self.palm["L"], r @ unit(-X + Z * 0.35), r @ -Y)
            wrist_l = at(self.marks["handle"], HANDLE_WRIST)
        else:
            sup = self.marks["support"]
            fingers_l = r @ unit(-X * 0.85 + Z * 0.5)
            hand_l = frame_from(Y, self.palm["L"], fingers_l, r @ unit(Y - X * 0.25))
            wrist_l = at(sup, CRADLE_WRIST)
        return {"R": translation(wrist_r) @ rotation(hand_r), "L": translation(wrist_l) @ rotation(hand_l)}

    def solve(self, pose, gun):
        reach = {}
        for s, target in self.hands(gun).items():
            up, lo, ha = bone(s, "Arm"), bone(s, "ForeArm"), bone(s, "Hand")
            a = pose.head(up)
            l1, l2 = self.len[s]
            elbow, end = two_bone(a, l1, l2, target[:3, 3], POLES[s])
            place_chain(pose, up, lo, a, elbow, end, POLES[s])
            pose.place(ha, translation(end) @ rotation(target[:3, :3]))
            reach[s] = np.linalg.norm(target[:3, 3] - a) / (l1 + l2)
        self.curl(pose)
        return reach

    def curl(self, pose):
        rig = self.rig
        for s, curls in (("R", TRIGGER_CURL), ("L", {"grip": GRIP_CURL, "handle": GRIP_CURL, "side": CRADLE_CURL}.get(self.support_grip, CRADLE_CURL))):
            for f, angles in curls.items():
                for k, a in enumerate(angles):
                    name = bone(s, "Hand%s%d" % (f, k + 1))
                    if name not in rig.index:
                        continue
                    along = rig.rest(name)[:3, :3] @ Y
                    palm = -Y if f != "Thumb" else unit(-Y - X * (1 if s == "L" else -1))
                    axis = np.cross(along, palm)
                    if np.linalg.norm(axis) < 1e-6:
                        continue
                    pose.turn(name, unit(axis), math.radians(a))


def fit(carry, rig, pose, js, binary):
    """Searches the butt's place (round the given pocket) and the cant for the gun that both hands reach
    most easily, at the Idle clip's middle frame: the most stretched arm under 0.9 of its length, then
    as near the given pocket as can be."""
    anim = next(a for a in js["animations"] if a["name"] == "Idle")
    frames, n = sample_clip(js, binary, anim)
    set_frame(pose, rig, frames, n // 2)
    base_pocket, base_cant = carry.pocket.copy(), carry.cant
    best = None
    for dx in np.linspace(-0.12, 0.2, 9):
        for dy in np.linspace(-0.25, 0.1, 8):
            for dz in np.linspace(-0.05, 0.2, 6):
                for dc in np.radians([-10, 0, 10, 20, 30]):
                    carry.pocket = base_pocket + np.array([dx, dy, dz])
                    carry.cant = base_cant + dc
                    gun = pose.world(CHEST) @ carry.place(pose, PITCH["Idle"])
                    worst = 0.0
                    for s, target in carry.hands(gun).items():
                        a = pose.head(bone(s, "Arm"))
                        worst = max(worst, np.linalg.norm(target[:3, 3] - a) / sum(carry.len[s]))
                    cost = max(worst - 0.9, 0.0) * 10.0 + np.linalg.norm([dx, dy, dz]) + abs(dc) * 0.3
                    if best is None or cost < best[0]:
                        best = (cost, carry.pocket.copy(), carry.cant, worst)
    _, carry.pocket, carry.cant, worst = best
    print(f"fit: pocket {np.round(carry.pocket, 3)}, cant {math.degrees(carry.cant):.0f} deg, reach {worst:.2f}")


def arm_bones(rig):
    out = []
    for s in "LR":
        for part in ("Arm", "ForeArm", "Hand"):
            out.append(bone(s, part))
        prefix = bone(s, "Hand")
        out += [n for n in rig.index if n.startswith(prefix) and n != prefix]
    return [n for n in out if n in rig.index]


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    marks = gun_markers(args.gun)
    rig = Rig(js)
    pose = Pose(rig)
    height = max(rig.rest(P + "HeadTop_End")[1, 3] if P + "HeadTop_End" in rig.index else 0.0,
                 rig.rest(P + "Head")[1, 3] + 0.1)
    pocket = np.array([float(v) for v in args.pocket.split(",")]) if args.pocket else POCKET
    if args.pitch:
        for clip, v in zip(("Idle", "Running"), args.pitch.split(",")):
            PITCH[clip] = math.radians(float(v))
    carry = Carry(rig, marks, args.support, height, pocket, math.radians(args.cant))
    if args.fit:
        fit(carry, rig, pose, js, binary)
    if args.pole_l:
        POLES["L"] = unit([float(v) for v in args.pole_l.split(",")])
    global CHEST_YAW
    CHEST_YAW = -math.radians(args.chest_yaw)
    arms = arm_bones(rig) + (list(TWIST) if CHEST_YAW else [])
    arm_nodes = {rig.index[n] for n in arms}
    skin = js["skins"][0]

    # The marker bone, at rest where the Idle carry puts it.
    clips = {}
    for anim in js["animations"]:
        frames, n = sample_clip(js, binary, anim)
        name = anim["name"]
        # The gun's place in the chest's frame: from the clip's middle frame.
        set_frame(pose, rig, frames, n // 2)
        local = carry.place(pose, PITCH.get(name, PITCH["Idle"]))
        steady = (pose.world(CHEST) @ local)[:3, :3]
        keys = {b: [] for b in arms}
        locals_ = []
        worst = {"L": 0.0, "R": 0.0}
        for f in range(n):
            set_frame(pose, rig, frames, f)
            chest = pose.world(CHEST)
            gun = chest @ local
            # The gun rides the chest, but turns with only FOLLOW of the chest's sway and twist.
            gun[:3, :3] = blend(steady, gun[:3, :3], FOLLOW)
            locals_.append(np.linalg.inv(chest) @ gun)
            locals_[-1][:3, :3] /= np.linalg.norm(locals_[-1][:3, :3], axis=0)
            reach = carry.solve(pose, gun)
            for s in "LR":
                worst[s] = max(worst[s], reach[s])
            for b in arms:
                keys[b].append(pose.local(b))
        clips[name] = (anim, keys, locals_, n)
        print(f"{name}: {n} frames, reach (of the arm's length) L {worst['L']:.2f} R {worst['R']:.2f}")

    ibm = list(accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4))
    rest_local = clips.get("Idle", next(iter(clips.values())))[2][0]
    k = add_marker(js, CHEST, "rifle", rest_local)
    skin["joints"].append(k)
    pidx = skin["joints"].index(rig.index[CHEST])
    parent_bind = np.linalg.inv(ibm[pidx].T)
    ibm.append(np.linalg.inv(parent_bind @ rest_local).T)
    skin["inverseBindMatrices"] = add_accessor(js, binary, np.array(ibm).reshape(-1, 16), "MAT4")

    for name, (anim, keys, gun_locals, n) in clips.items():
        times = np.arange(n, dtype=np.float32) / FPS
        tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
        # Drop the arms' old rotation keys, then key them (and the marker) afresh.
        keep = [ch for ch in anim["channels"] if not (ch["target"]["node"] in arm_nodes and ch["target"]["path"] == "rotation")]
        samplers = []
        channels = []
        for ch in keep:
            samplers.append(anim["samplers"][ch["sampler"]])
            channels.append({"sampler": len(samplers) - 1, "target": ch["target"]})
        for b, mats in list(keys.items()) + [("rifle", gun_locals)]:
            quats = []
            prev = None
            for m in mats:
                r = m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0)
                q = mat_to_quat(r)
                if prev is not None and np.dot(q, prev) < 0:
                    q = -q
                quats.append(q)
                prev = q
            node = k if b == "rifle" else rig.index[b]
            samplers.append({"input": tin, "output": add_accessor(js, binary, np.array(quats, dtype=np.float32), "VEC4"), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": "rotation"}})
            if b == "rifle":
                pos = np.array([m[:3, 3] for m in mats], dtype=np.float32)
                samplers.append({"input": tin, "output": add_accessor(js, binary, pos, "VEC3"), "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": "translation"}})
        anim["samplers"] = samplers
        anim["channels"] = channels

    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/arm_rifle.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: height {height:.2f} m, {len(skin['joints'])} joints")
    if args.preview:
        render_preview(args.output, args.gun, args.preview)
        render_preview(args.output, args.gun, args.preview.replace(".png", "_close.png"), zoom=2.2)


# ---------------------------------------------------------------- preview

def posed(js, binary, rig, frames, f):
    """The skinned mesh's vertices at frame f of a sampled clip, and the gun bone's matrix."""
    pose = Pose(rig)
    set_frame(pose, rig, frames, f)
    skin = js["skins"][0]
    ibm = accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4).transpose(0, 2, 1)
    mats = np.array([pose.world(rig.nodes[j]["name"]) @ ibm[k] for k, j in enumerate(skin["joints"])])
    node = next(n for n in js["nodes"] if "skin" in n)
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
    return out, idx, uv, pose.world("rifle")


def render_preview(path, gun_path, out, zoom=1.0):
    """Front, side and three-quarter views of frames of each clip, the gun on its bone."""
    from PIL import Image, ImageDraw
    from rig_infiltrator import rasterize
    from rig_sniper import load_textured, rifle_mesh
    js, binary = read_glb(path)
    rig = Rig(js)
    node = next(n for n in js["nodes"] if "skin" in n)
    tex = load_textured(js, binary, js["meshes"][node["mesh"]]["primitives"][0])
    gpts, gidx, guv, gtex = rifle_mesh(gun_path)
    anims = {a["name"]: a for a in js["animations"]}
    shots = [("Idle", 0), ("Idle", 45), ("Running", 0), ("Running", 8)]
    views = [np.array([0.9, 0.62, 2.0]), np.array([-2.2, 0.6, 0.2]), np.array([-1.3, 0.75, 1.7])]
    W, H = 260, 340
    sheet = Image.new("RGB", (W * len(views), H * len(shots)))
    sampled = {}
    for r, (clip, f) in enumerate(shots):
        if clip not in sampled:
            sampled[clip] = sample_clip(js, binary, anims[clip])[0]
        pts, idx, uv, g = posed(js, binary, rig, sampled[clip], f)
        h = pts[:, 1].max()
        gp = gpts @ g[:3, :3].T + g[:3, 3]
        for c, e in enumerate(views):
            img = np.ones((H, W, 3), np.float32) * np.array([0.55, 0.65, 0.75], np.float32)
            zb = np.full((H, W), np.inf, np.float32)
            target = np.array([0.0, (0.55 + 0.1 * (zoom - 1.0)) * h, 0.1])
            eye = target + (e * h + np.array([0, 0.1, 0]) - np.array([0.0, 0.55 * h, 0.1])) / zoom
            rasterize(img, zb, pts, idx, uv, tex, eye, target)
            rasterize(img, zb, gp, gidx, guv, gtex, eye, target)
            pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
            ImageDraw.Draw(pil).text((4, 4), f"{clip} {f}", fill=(0, 0, 0))
            sheet.paste(pil, (c * W, r * H))
    sheet.save(out)
    print(f"preview {out}")


if __name__ == "__main__":
    main()
