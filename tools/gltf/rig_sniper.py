"""Rig and animate the Sniper: the Grey Veil Warden in her ghillie cape with the Eclipse Longshot
shouldered. No Blender: numpy on the glTF itself, like tools/gltf/rig_infiltrator.py (whose helpers it
uses).

Input: the garrison's processed Grey Veil Warden (game/assets/defenders/grey_veil_warden/
grey_veil_warden.glb: 1.7 m, origin between the feet, Meshy's Mixamo-style auto-rig in a T-pose with
Idle and Running clips, which are dropped) and the processed rifle (eclipse_longshot.glb, from
tools/gltf/process_rifle.py: muzzle +Z, origin at the pistol grip, marker nodes `eye`, `butt`,
`support`). The mesh and its skin weights stay as they are.

The bones are renamed to the squad troopers' names (pelvis, spine_1 ... hand_R, the fingers
index_1_R ...), so TrooperRig bends the spine onto the aim as it does every trooper's. One marker bone
(no weights) carries the rifle: `rifle`, a child of the chest, at the rifle's own frame (Z out of the
muzzle, Y up, origin at the pistol grip). The game hangs the rifle model on it (SniperTrooper).

A rifleman's standing stance, in every clip: bladed (the chest turned CHEST_YAW to her right, the hips
HIP_TURN of it), the butt in the right shoulder pocket (POCKET, from the shoulder joint; the shoulder
shrugged up SHRUG), the rifle level and straight ahead; the head down on the stock, the neck and head
pitched and canted until the right eye (EYE, on the face) lies on the scope's axis; the right hand on
the pistol grip (the index finger along the trigger), the left under the fore-end at the rifle's
`support` marker. The arms are solved by IK every frame onto targets that ride the chest, so the rifle
and the hands stay together wherever the chest goes. The rest pose is this stance too.

Clips (FPS frames per second; the last key repeats the first, which the game drops):
  Idle        breathing (the rifle rising and falling a little with it), a slow weight shift, the
              feet planted. The eye never leaves the scope.
  Walk_<dir>  eight directions, one cycle of WALK_PERIOD each, all in step so the game blends them by
              direction (SquadTrooper): <dir> is where she goes relative to where she faces (F, FR, R,
              BR, B, BL, L, FL), at the squad troopers' clip speeds. The legs walk like the
              Infiltrator's (feet planted by IK, the hips riding as high as the planted legs allow)
              while the chest, the head and the rifle stay steady on the aim.

  python3 tools/gltf/rig_sniper.py \\
      --input game/assets/defenders/grey_veil_warden/grey_veil_warden.glb \\
      --rifle game/assets/defenders/grey_veil_warden/eclipse_longshot.glb \\
      --output game/assets/defenders/grey_veil_warden/sniper_rigged.glb [--preview DIR]

--preview renders the rest pose and frames of each clip into DIR as PNGs (a plain numpy rasterizer),
the rifle in her hands.
"""
import argparse
import io
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, add_accessor, compact, read_glb, rotation, set_trs, translation, trs, write_glb  # noqa: E402
from rig_infiltrator import (CROUCH, DIRECTIONS, FINGERS, FPS, WALK_PERIOD, X, Y, Z, Legs, Pose, Rig,  # noqa: E402
                             add_marker, frame_from, hip_heights, place_chain, rasterize, rename_bones, rot_x,
                             rot_y, skinned_vertices, two_bone, unit, walk_params, wave, write_clips)
import rig_infiltrator  # noqa: E402

IDLE_PERIOD = 4.0
# The stance: how far the chest turns to her right off where she faces (her left shoulder toward the
# target), the hips' share of it, and how the spine shares the rest out; the spine leans a little
# forward, into the rifle.
CHEST_YAW = math.radians(-50.0)
HIP_TURN = math.radians(-20.0)
TWIST = {"spine_1": 0.3, "spine_2": 0.4, "chest": 0.3}
SPINE_PITCH = math.radians(4.0)
# The neck and head turn back to look down the rifle (their shares of -CHEST_YAW). Then the cheek weld,
# solved at the reference (Stance.reference): the spine leans her over the stock, the neck juts the
# head forward and the head nods back level, and the two cant it onto the stock (the neck NECK_SHARE
# of it), until the eye lies on the scope's axis with the face looking GAZE down the scope.
COUNTER = {"neck": 0.45, "head": 0.55}
NECK_SHARE = 0.6
GAZE = math.radians(-8.0)
# How readily the solve takes up the gap with the neck's nod, the head's, the cant and the spine's lean.
STEP_WEIGHTS = (1.0, 1.0, 0.6, 0.7)
# The right eye, at rest (model space, m): the camera looks out of it through the scope.
EYE = np.array([-0.045, 1.55, 0.11])
# The butt goes into the shoulder pocket: this far from the right shoulder joint, at rest (toward the
# middle, up, forward), the shoulder shrugged up by SHRUG first.
POCKET = np.array([0.07, 0.02, 0.07])
SHRUG = math.radians(12.0)
# The trigger hand, in the rifle's frame (X her left, Y up, Z out of the muzzle; the origin is the top of
# the pistol grip, under the web of the thumb): the wrist behind the grip and to its right, the hand
# running forward and down GRIP_RAKE (square to the raked grip), the palm against the grip's right side.
GRIP_WRIST = np.array([-0.024, -0.004, -0.068])
GRIP_RAKE = math.radians(26.0)
# The support hand under the fore-end (from the rifle's `support` marker): the wrist below it and to
# its left, the palm up, the fingers across under it to the right.
SUPPORT_WRIST = np.array([0.045, -0.03, -0.03])
# Finger curls (degrees, per joint from the knuckle out).
TRIGGER_CURL = {"thumb": (25, 30, 20), "index": (18, 32, 20), "middle": (65, 85, 55), "ring": (68, 85, 55), "pinky": (70, 85, 55)}
SUPPORT_CURL = {"thumb": (10, 15, 10), "index": (35, 55, 35), "middle": (38, 58, 35), "ring": (40, 60, 38), "pinky": (45, 60, 40)}
ANIMATED = rig_infiltrator.ANIMATED


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--rifle", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


def rifle_markers(path):
    """The rifle's marker nodes (process_rifle.py), by name: their positions in its frame."""
    js, _ = read_glb(path)
    out = {}
    for n in js["nodes"]:
        if n.get("name") in ("muzzle", "eye", "butt", "support", "scope"):
            out[n["name"]] = trs(n)[:3, 3].copy()
    return out


def turn_world(pose, name, axis, angle):
    """Turns a bone about a model-space axis through its head, as it lies now (on top of its pose)."""
    carried = (pose.parent_world(name) @ pose.rig.local[pose.rig.index[name]])[:3, :3]
    b = pose.basis.get(name, np.eye(4)).copy()
    b[:3, :3] = carried.T @ rig_infiltrator.axis_angle(axis, angle) @ carried @ b[:3, :3]
    pose.basis[name] = b
    pose._world = {}


# ---------------------------------------------------------------- the rifleman's upper body

class Stance:
    """Where the rifle goes and how the head and the arms hold it. At the reference stance it puts the
    rifle's butt into the shoulder pocket, level and straight ahead, solves the head down onto it and
    keeps the rifle and the hands' targets in the chest's frame, so every frame the arms are solved
    onto them wherever the chest has gone."""

    def __init__(self, pose, marks):
        rig = pose.rig
        self.pose = pose
        self.marks = marks
        self.len = {}
        for s in "LR":
            up, lo, ha = ("upperarm_" + s, "forearm_" + s, "hand_" + s)
            self.len[s] = (np.linalg.norm(rig.rest(lo)[:3, 3] - rig.rest(up)[:3, 3]),
                           np.linalg.norm(rig.rest(ha)[:3, 3] - rig.rest(lo)[:3, 3]))
        # Palms face down in the T-pose: each hand's palm as a local axis.
        self.palm = {s: rig.rest("hand_" + s)[:3, :3].T @ -Y for s in "LR"}
        self.eye_local = np.linalg.inv(rig.rest("head")) @ np.append(EYE, 1.0)
        shoulder = rig.rest("upperarm_R")[:3, 3]
        self.pocket_local = np.linalg.inv(rig.rest("clavicle_R")) @ np.append(shoulder + POCKET, 1.0)
        # Solved at the reference: the neck's and the head's nods, their cant, and how far the spine
        # leans her over the stock.
        self.bend = np.zeros(4)

    def eye(self):
        return (self.pose.world("head") @ self.eye_local)[:3]

    def gaze(self):
        """The way the face looks (what was +Z at rest)."""
        return self.pose.world("head")[:3, :3] @ (np.linalg.inv(self.pose.rig.rest("head"))[:3, :3] @ Z)

    def pocket(self):
        return (self.pose.world("clavicle_R") @ self.pocket_local)[:3]

    def lean_over(self, angle):
        """The spine leans her to the right (about the way she aims), over the stock."""
        for name in ("spine_1", "spine_2"):
            turn_world(self.pose, name, Z, angle * 0.5)

    def bend_head(self, neck_nod, head_nod, cant):
        """The neck and head turn back to look ahead (their shares of -CHEST_YAW), then cant to her right
        about the way the face looks (shared out) and nod about its left-right axis (about the model's
        axes: once turned back, the face looks straight ahead)."""
        p = self.pose
        for name, nod, share in (("neck", neck_nod, NECK_SHARE), ("head", head_nod, 1.0 - NECK_SHARE)):
            turn_world(p, name, Y, -CHEST_YAW * COUNTER[name])
            turn_world(p, name, Z, cant * share)
            turn_world(p, name, X, nod)

    def place_rifle(self):
        """The rifle's butt in the shoulder pocket, the rifle level, straight ahead (+Z) and upright."""
        self.rifle = translation(self.pocket() - self.marks["butt"])

    def reference(self):
        """From the pose as it stands (the reference stance, not yet leaned over the stock nor the head
        bent): solves the cheek weld, the spine's lean, the neck's and head's nods and their cant, so
        that, the rifle's butt in the shoulder pocket, the eye lies on the scope's axis (about the
        rifle's `eye` mark) with the face looking GAZE down the scope; then the hands' targets. Each step is the smallest change that
        closes the gap (weighted by STEP_WEIGHTS), so they share it out."""
        p = self.pose
        joints = ("spine_1", "spine_2", "neck", "head")
        base = {n: p.basis.get(n, np.eye(4)).copy() for n in joints}

        def bend(x):
            for n in joints:
                p.basis[n] = base[n].copy()
            p._world = {}
            self.lean_over(x[3])
            self.place_rifle()
            self.bend_head(x[0], x[1], x[2])

        def miss(x):
            bend(x)
            want = (self.rifle @ np.append(self.marks["eye"], 1.0))[:3]
            g = self.gaze()
            return np.append((self.eye() - want)[:2], math.asin(max(-1.0, min(1.0, g[1]))) - GAZE)

        w = np.array(STEP_WEIGHTS)
        x = np.zeros(4)
        for _ in range(60):
            f = miss(x)
            if np.linalg.norm(f) < 1e-6:
                break
            jac = np.zeros((3, 4))
            for k in range(4):
                dx = np.zeros(4)
                dx[k] = 1e-5
                jac[:, k] = (miss(x + dx) - f) / 1e-5
            js = jac * w
            x -= w * (js.T @ np.linalg.solve(js @ js.T, f))
        f = miss(x)
        self.bend = x.copy()
        ahead = float(self.eye()[2] - (self.rifle @ np.append(self.marks["eye"], 1.0))[2])
        print(f"stance: neck nod {math.degrees(x[0]):.1f} deg, head nod {math.degrees(x[1]):.1f} deg, cant "
              f"{math.degrees(x[2]):.1f} deg, spine lean {math.degrees(x[3]):.1f} deg; eye off the scope's axis "
              f"{np.linalg.norm(f[:2]) * 1000:.1f} mm, {ahead * 100:+.1f} cm ahead of its mark; pocket {np.round(self.pocket(), 3)}; "
              f"face looks {np.round(self.gaze(), 2)}")
        # Leaned, the head unbent again: solve() bends it, every frame.
        for n in joints:
            p.basis[n] = base[n].copy()
        p._world = {}
        self.lean_over(x[3])
        chest = p.world("chest")
        inv = np.linalg.inv(chest)
        self.rifle_local = inv @ self.rifle
        rifle_rot = self.rifle[:3, :3]
        # The trigger hand: fingers forward and down square to the grip, the palm to her left.
        fingers_r = rifle_rot @ unit(Z * math.cos(GRIP_RAKE) - Y * math.sin(GRIP_RAKE))
        hand_r = frame_from(Y, self.palm["R"], fingers_r, rifle_rot @ X)
        wrist_r = (self.rifle @ np.append(GRIP_WRIST, 1.0))[:3]
        # The support hand: palm up, the fingers across under the fore-end to her right (and a little
        # forward), wrapping up its far side.
        fingers_l = rifle_rot @ unit(-X * 0.85 + Z * 0.5)
        hand_l = frame_from(Y, self.palm["L"], fingers_l, rifle_rot @ unit(Y - X * 0.25))
        wrist_l = (self.rifle @ np.append(self.marks["support"] + SUPPORT_WRIST, 1.0))[:3]
        self.targets = {"R": inv @ translation(wrist_r) @ rotation(hand_r), "L": inv @ translation(wrist_l) @ rotation(hand_l)}
        # Elbows: the trigger arm's out to her right and down, the support arm's down under the rifle.
        poles = {"R": unit(-X * 0.8 - Y * 0.55 - Z * 0.1), "L": unit(-Y + X * 0.35)}
        self.poles = {s: chest[:3, :3].T @ poles[s] for s in "LR"}
        for s in "LR":
            up = p.head("upperarm_" + s)
            reach = np.linalg.norm((chest @ self.targets[s])[:3, 3] - up)
            print(f"  arm {s}: shoulder to wrist {reach:.3f} m of {sum(self.len[s]):.3f} m")

    def solve(self):
        """Leaned over the stock, the head bent onto it, the arms onto the rifle."""
        p = self.pose
        self.lean_over(self.bend[3])
        self.bend_head(*self.bend[:3])
        chest = p.world("chest")
        for s in "LR":
            target = chest @ self.targets[s]
            up, lo, ha = ("upperarm_" + s, "forearm_" + s, "hand_" + s)
            a = p.head(up)
            l1, l2 = self.len[s]
            pole = chest[:3, :3] @ self.poles[s]
            elbow, end = two_bone(a, l1, l2, target[:3, 3], pole)
            place_chain(p, up, lo, a, elbow, end, pole)
            p.place(ha, translation(end) @ rotation(target[:3, :3]))

    def rifle_world(self):
        return self.pose.world("chest") @ self.rifle_local

    def curl_fingers(self):
        """The trigger hand round the grip (the index along the trigger), the support hand cradling the
        fore-end (about each finger's curl axis at rest: from its length toward the palm)."""
        p = self.pose
        rig = p.rig
        for s, curls in (("R", TRIGGER_CURL), ("L", SUPPORT_CURL)):
            palm_world = -Y
            for f, angles in curls.items():
                for k, a in enumerate(angles):
                    name = "%s_%d_%s" % (f, k + 1, s)
                    if name not in rig.index:
                        continue
                    along = rig.rest(name)[:3, :3] @ Y
                    axis = np.cross(along, palm_world)
                    if f == "thumb":
                        axis = np.cross(along, unit(palm_world - X * (1 if s == "L" else -1)))
                    if np.linalg.norm(axis) < 1e-6:
                        continue
                    p.turn(name, unit(axis), math.radians(a))


def upper_body(pose, yaw=0.0, roll=0.0, lean=0.0, breathe=0.0):
    """The stance on top of the hips' own turn, roll and pitch: the spine turns the chest CHEST_YAW off
    the front (cancelling what the hips turn), levels it and leans it a little to the right and
    forward. The neck and head turn back and bend onto the stock after (Stance.bend_head)."""
    spine = CHEST_YAW - HIP_TURN - yaw
    for name, share in TWIST.items():
        pose.turn(name, Y, spine * share)
    pose.turn("spine_1", Z, -roll * 0.6)
    pose.turn("spine_2", Z, -roll * 0.4)
    pose.turn("spine_1", X, -lean * 0.5 + SPINE_PITCH * 0.5)
    pose.turn("spine_2", X, SPINE_PITCH * 0.5)
    pose.turn("chest", X, breathe)
    pose.turn("clavicle_R", Z, -SHRUG)
    pose.turn("head", X, -breathe)


# ---------------------------------------------------------------- clips

class Baker:
    def __init__(self, rig, verts, joints, marks):
        self.rig = rig
        self.joint_set = set(joints)
        self.pose = Pose(rig)
        self.legs = Legs(self.pose, verts)
        self.stance = Stance(self.pose, marks)
        self.clips = {}
        self.fingers = {}

    def reference(self):
        """The rest pose: crouched a little in the stance, feet where they stand, the rifle shouldered."""
        p = self.pose
        p.reset()
        p.move("pelvis", (0.0, -CROUCH, 0.0))
        p.turn("pelvis", Y, HIP_TURN)
        upper_body(p)
        self.stance.reference()
        self.stance.solve()
        self.stance.curl_fingers()
        self._planted_feet()
        names = [n["name"] for n in self.rig.nodes if n.get("name") in self.rig.index]
        self.rest_locals = {n: p.local(n) for n in names if self.rig.index[n] in self.joint_set}
        self.fingers = {n: p.basis[n].copy() for n in p.basis if n.split("_")[0] in FINGERS}

    def _planted_feet(self):
        p = self.pose
        pole = rot_y(HIP_TURN * 0.4) @ Z
        for s in "LR":
            i = self.legs.info[s]
            self.legs.solve(s, i["ankle"].copy(), 0.0, 0.0, pole)

    def _frame(self):
        p = self.pose
        return {n: p.local(n) for n in ANIMATED}

    def _with_fingers(self):
        for n, b in self.fingers.items():
            self.pose.basis[n] = b.copy()
        self.pose._world = {}

    def bake_walk(self, direction):
        walk = walk_params(direction)
        frames = int(round(WALK_PERIOD * FPS))
        T = WALK_PERIOD
        ts = [f / FPS for f in range(frames)]
        fwd, side = walk["fwd"], walk["d"][0]
        sway = [rig_infiltrator.SWAY * (0.4 + 0.6 * abs(fwd)) * -math.cos(2 * math.pi * t / T) for t in ts]
        rise = hip_heights(self.legs, walk, ts, sway)
        rise = [min(x, 0.0) - CROUCH for x in rise]
        keys = []
        worst, drift = 0.0, 0.0
        rifle0 = None
        for f, t in enumerate(ts):
            p = self.pose
            p.reset()
            self._with_fingers()
            yaw = -rig_infiltrator.YAW * abs(fwd) * wave(t, T) * (1 if fwd >= 0 else -1)
            roll = rig_infiltrator.ROLL * (0.3 + 0.7 * abs(fwd)) * math.cos(2 * math.pi * t / T)
            lean = math.radians(3.0 * max(fwd, 0.0) - 2.0 * max(-fwd, 0.0))
            p.move("pelvis", (sway[f], rise[f], 0.0))
            p.turn("pelvis", Y, HIP_TURN + yaw)
            p.turn("pelvis", Z, roll)
            p.turn("pelvis", X, lean)
            p.turn("pelvis", Z, math.radians(2.0) * side)  # leaning into a sidestep
            upper_body(p, yaw, roll, lean, breathe=math.radians(0.6) * wave(t, T, 2, 0.3))
            pole = rot_y(HIP_TURN * 0.4 + yaw) @ Z
            for s in "LR":
                ankle, pitch, toe = self.legs.foot(s, t, walk)
                worst = max(worst, self.legs.solve(s, ankle, pitch, toe, pole))
            self.stance.solve()
            muzzle = self.stance.rifle_world()[:3, 2]
            rifle0 = muzzle if rifle0 is None else rifle0
            drift = max(drift, math.degrees(math.acos(min(1.0, float(np.dot(muzzle, rifle0))))))
            keys.append(self._frame())
        keys.append(keys[0])
        self.clips["Walk_" + direction] = keys
        print(f"Walk_{direction}: {walk['speed']:.2f} m/s, hips {min(rise):+.3f}..{max(rise):+.3f} m, "
              f"rifle swings {drift:.1f} deg, worst foot miss {worst * 100:.1f} cm")

    def bake_idle(self):
        frames = int(round(IDLE_PERIOD * FPS))
        T = IDLE_PERIOD
        keys = []
        for f in range(frames):
            t = f / FPS
            p = self.pose
            p.reset()
            self._with_fingers()
            sway = 0.01 * wave(t, T)
            p.move("pelvis", (sway, -CROUCH - 0.005 * (1 + wave(t, T, 2, 0.25)), 0.0))
            yaw = math.radians(1.0) * wave(t, T, 1, 0.2)
            p.turn("pelvis", Y, HIP_TURN + yaw)
            p.turn("pelvis", Z, math.radians(1.0) * wave(t, T))
            upper_body(p, yaw, math.radians(1.0) * wave(t, T), breathe=math.radians(1.2) * wave(t, T, 2))
            self._planted_feet()
            self.stance.solve()
            keys.append(self._frame())
        keys.append(keys[0])
        self.clips["Idle"] = keys
        print(f"Idle: {IDLE_PERIOD:.1f} s")


# ---------------------------------------------------------------- writing it out

def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    rename_bones(js)
    rig = Rig(js)
    skin = js["skins"][0]
    mesh_node = next(n for n in js["nodes"] if "skin" in n)
    prim = js["meshes"][mesh_node["mesh"]]["primitives"][0]
    verts = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    marks = rifle_markers(args.rifle)

    baker = Baker(rig, verts, skin["joints"], marks)
    baker.reference()
    rifle_marker = ("chest", baker.stance.rifle_local)
    for d in DIRECTIONS:
        baker.bake_walk(d)
    baker.bake_idle()

    # The stance is the rest pose: every joint's node transform as the reference left it.
    for name, local in baker.rest_locals.items():
        set_trs(js["nodes"][rig.index[name]], local)
    ibm = list(accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4))
    parent, local = rifle_marker
    k = add_marker(js, parent, "rifle", local)
    skin["joints"].append(k)
    # Bind matrix: where the marker would be in the bind pose (the T-pose), from its parent's.
    pidx = skin["joints"].index(rig.index[parent])
    parent_bind = np.linalg.inv(ibm[pidx].T)
    ibm.append(np.linalg.inv(parent_bind @ local).T)
    skin["inverseBindMatrices"] = add_accessor(js, binary, np.array(ibm).reshape(-1, 16), "MAT4")
    write_clips(js, binary, rig, baker.clips)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/rig_sniper.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(skin['joints'])} joints, clips {list(baker.clips)}")
    if args.preview:
        render_preview(args.output, args.rifle, args.preview)


# ---------------------------------------------------------------- preview

def load_textured(js, binary, prim):
    from PIL import Image
    mat = js["materials"][prim.get("material", 0)]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    return np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((512, 512)), dtype=np.float32) / 255.0


def rifle_mesh(path):
    """The rifle's triangles in its own frame (its root node's matrix applied), UVs and texture."""
    js, binary = read_glb(path)
    node = next(n for n in js["nodes"] if "mesh" in n)
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    m = trs(node)
    pts = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float) @ m[:3, :3].T + m[:3, 3]
    idx = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    uv = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)
    return pts, idx, uv, load_textured(js, binary, prim)


def marker_world(js, binary, clip, frame, name):
    """A node's model-space matrix in a clip's frame (or the rest pose)."""
    nodes = js["nodes"]
    local = {i: trs(n) for i, n in enumerate(nodes)}
    if clip is not None:
        anim = next(a for a in js["animations"] if a["name"] == clip)
        for ch in anim["channels"]:
            s = anim["samplers"][ch["sampler"]]
            vals = accessor(js, binary, s["output"]).astype(float)
            i = ch["target"]["node"]
            m = local[i].copy()
            if ch["target"]["path"] == "rotation":
                m[:3, :3] = rig_infiltrator.quat_to_mat(vals[frame])
            elif ch["target"]["path"] == "translation":
                m[:3, 3] = vals[frame]
            local[i] = m
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    i = next(k for k, n in enumerate(nodes) if n.get("name") == name)
    m = local[i]
    while i in parent:
        i = parent[i]
        m = local[i] @ m
    return m


def render_preview(path, rifle_path, out_dir):
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    js, binary = read_glb(path)
    node = next(n for n in js["nodes"] if "skin" in n)
    tex = load_textured(js, binary, js["meshes"][node["mesh"]]["primitives"][0])
    r_pts, r_idx, r_uv, r_tex = rifle_mesh(rifle_path)
    shots = [(None, [0])] + [("Idle", [0, 60])] + [("Walk_" + d, [0, 5, 10, 15]) for d in ("F", "R", "B")]
    views = {"front": (np.array([0.6, 1.4, 3.0]), np.array([0.0, 1.2, 0.3])),
             "side": (np.array([-3.2, 1.4, 0.6]), np.array([0.0, 1.25, 0.3])),
             "back": (np.array([-0.9, 1.75, -2.4]), np.array([0.0, 1.35, 0.4])),
             "close": (np.array([-0.75, 1.6, 0.35]), np.array([0.0, 1.42, 0.25]))}
    for clip, frames in shots:
        row = []
        for f in frames:
            pts, idx, uv, _, _ = skinned_vertices(js, binary, clip, f)
            rifle = marker_world(js, binary, clip, f, "rifle")
            rp = r_pts @ rifle[:3, :3].T + rifle[:3, 3]
            for vname, (eye, target) in views.items():
                img = np.ones((300, 220, 3), np.float32) * np.array([0.55, 0.65, 0.75], np.float32)
                zb = np.full((300, 220), np.inf, np.float32)
                fov = 35.0 if vname != "close" else 40.0
                rasterize(img, zb, pts, idx, uv, tex, eye, target, fov)
                rasterize(img, zb, rp, r_idx, r_uv, r_tex * 1.5, eye, target, fov)
                pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
                ImageDraw.Draw(pil).text((4, 4), f"{clip or 'rest'} {f} {vname}", fill=(0, 0, 0))
                row.append(pil)
        sheet = Image.new("RGB", (220 * len(row), 300))
        for k, p in enumerate(row):
            sheet.paste(p, (220 * k, 0))
        sheet.save(os.path.join(out_dir, f"{clip or 'rest'}.png"))
    print(f"preview in {out_dir}")


if __name__ == "__main__":
    main()
