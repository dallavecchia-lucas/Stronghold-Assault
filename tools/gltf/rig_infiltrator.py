"""Rig and animate the Infiltrator (the Infiltrator Squad's trooper): the Harpy Vanguard in her
training kit, with a recurve bow. No Blender: numpy on the glTF itself.

Input: the garrison's processed Harpy Vanguard (game/assets/defenders/harpy_vanguard/
harpy_vanguard.glb: 1.7 m, origin between the feet, Meshy's Mixamo-style auto-rig in a T-pose with
Idle and Running clips, which are dropped). The mesh and its skin weights stay as they are.

The bones are renamed to the squad troopers' names (pelvis, spine_1, spine_2, chest, neck, head,
clavicle_L, upperarm_L, forearm_L, hand_L, thigh_L, shin_L, foot_L, toe_L ... the fingers
thumb_1_L, index_2_R ...), so TrooperRig bends the spine onto the aim as it does every trooper's.
Two marker bones (no weights) carry the bow: `bow`, a child of hand_L at the grip, its Y axis up the
bow and Z toward the target; `nock`, a child of hand_R where the arrow's nock sits on the drawn string.
The game builds the bow, string and arrows on them (InfiltratorTrooper).

Archer's stance, in every clip: side-on, the chest turned CHEST_YAW off the way she faces (the hips
take HIP_TURN of it), the head turned back to look down the arrow; the left arm out on the aim with
the bow, the string drawn to the right side of the chin (ANCHOR), the elbow back at shoulder height.
The arms are solved by IK every frame on targets that ride the chest, so they stay on the aim. The
rest pose is this stance too.

Clips (FPS frames per second; the last key repeats the first, which the game drops):
  Idle        breathing, a slow weight shift and a look round, the feet planted.
  Walk_<dir>  eight directions, one cycle of WALK_PERIOD each, all in step so the game blends them by
              direction (SquadTrooper): <dir> is where she goes relative to where she faces (F, FR, R,
              BR, B, BL, L, FL), at the squad troopers' clip speeds (FORWARD_SPEED ahead, BACK_SPEED
              back, SIDE_SPEED to the side). Feet planted by IK (heel strike and roll over the toes
              going forward, toes first going back, a wider stance to the side), the hips riding as
              high as the planted legs allow, swaying over the standing foot and turning with the
              stride while the chest stays steady on the aim.

  python3 tools/gltf/rig_infiltrator.py \\
      --input game/assets/defenders/harpy_vanguard/harpy_vanguard.glb \\
      --output game/assets/defenders/harpy_vanguard/infiltrator_rigged.glb [--preview DIR]

--preview renders the rest pose and frames of each clip into DIR as PNGs (a plain numpy rasterizer).
"""
import argparse
import io
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import (accessor, add_accessor, axis_angle, compact, mat_to_quat, quat_to_mat, read_glb,  # noqa: E402
                     rotation, set_trs, translation, trs, write_glb)

FPS = 30
# The squad troopers' clip speeds (m/s, SquadTrooper.CLIP_*), every clip a cycle of WALK_PERIOD.
FORWARD_SPEED = 2.3
BACK_SPEED = 1.6
SIDE_SPEED = 1.1
WALK_PERIOD = 20 / FPS  # a whole number of frames
DUTY = 0.58  # share of the cycle each foot is on the ground
SWING = 1.0 - DUTY
SWING_MID = {"L": 0.0, "R": 0.5}  # middle of each foot's swing, as a share of the cycle
IDLE_PERIOD = 4.0
CROUCH = 0.06  # knees a little bent: the hips this much under the straight-legged rest
STRAIGHT = 0.985  # how straight a planted leg may get (share of its full length)
LIFT = 0.13  # foot clearance mid-swing going forward (m)
STRIKE = math.radians(14.0)  # toes up at heel strike
PUSH = math.radians(30.0)  # heel up rolling over the toes at lift-off
HEEL_OFF = 0.32  # last share of the stance in which the heel peels off
WIDEN = 0.07  # extra half-width of the stance walking sideways (m)
SWAY = 0.03  # hips over the standing foot (m)
YAW = math.radians(5.0)  # hips turning with the stride
ROLL = math.radians(2.5)  # the swinging side's hip dropping
# The archer's stance: how far the chest turns to the right off where she faces (her left shoulder
# toward the target), the hips' share of it, and how the spine shares the rest out.
CHEST_YAW = math.radians(-78.0)
HIP_TURN = math.radians(-18.0)
TWIST = {"spine_1": 0.3, "spine_2": 0.4, "chest": 0.3}
COUNTER = {"neck": 0.45, "head": 0.55}
HEAD_CANT = math.radians(8.0)  # the head leans toward the string
# Where the string hand anchors, from the head joint once the head looks ahead (m): her right, down,
# forward. The arrow runs from there straight ahead; the bow hand is on that line at ARM_REACH of
# the full arm, GRIP past the wrist.
ANCHOR = np.array([-0.085, -0.06, 0.06])
ARM_REACH = 0.965
GRIP = 0.07
NOCK = 0.085  # the string fingers, past the right wrist
# Finger curls (degrees, per joint from the knuckle out): the bow hand round the grip, the string hand
# hooked on the string.
GRIP_CURL = {"thumb": (10, 25, 20), "index": (55, 80, 50), "middle": (60, 85, 55), "ring": (60, 85, 55), "pinky": (65, 85, 55)}
DRAW_CURL = {"thumb": (15, 30, 25), "index": (30, 60, 35), "middle": (30, 65, 35), "ring": (35, 65, 40), "pinky": (65, 85, 60)}
# Where each clip goes: name -> point on the unit circle (x right, y ahead).
DIRECTIONS = {
    "F": (0.0, 1.0), "FR": (0.7071, 0.7071), "R": (1.0, 0.0), "BR": (0.7071, -0.7071),
    "B": (0.0, -1.0), "BL": (-0.7071, -0.7071), "L": (-1.0, 0.0), "FL": (-0.7071, 0.7071),
}
# Model axes (glTF): +X her left, +Y up, +Z her front.
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

RENAME = {
    "Hips": "pelvis", "Spine": "spine_1", "Spine1": "spine_2", "Spine2": "chest", "Neck": "neck", "Head": "head",
    "HeadTop_End": "head_end", "headfront": "head_front",
    "LeftShoulder": "clavicle_L", "LeftArm": "upperarm_L", "LeftForeArm": "forearm_L", "LeftHand": "hand_L",
    "RightShoulder": "clavicle_R", "RightArm": "upperarm_R", "RightForeArm": "forearm_R", "RightHand": "hand_R",
    "LeftUpLeg": "thigh_L", "LeftLeg": "shin_L", "LeftFoot": "foot_L", "LeftToeBase": "toe_L", "LeftToe_End": "toe_end_L",
    "RightUpLeg": "thigh_R", "RightLeg": "shin_R", "RightFoot": "foot_R", "RightToeBase": "toe_R", "RightToe_End": "toe_end_R",
}
FINGERS = ("thumb", "index", "middle", "ring", "pinky")
LEG_BONES = {s: ("thigh_" + s, "shin_" + s, "foot_" + s, "toe_" + s) for s in "LR"}
ANIMATED = ["pelvis", "spine_1", "spine_2", "chest", "neck", "head", "clavicle_L", "upperarm_L", "forearm_L", "hand_L",
            "clavicle_R", "upperarm_R", "forearm_R", "hand_R"] + [b for bones in LEG_BONES.values() for b in bones]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


def clean_name(name):
    name = name.split(":")[-1]
    if name in RENAME:
        return RENAME[name]
    for side, prefix in (("L", "LeftHand"), ("R", "RightHand")):
        if name.startswith(prefix):
            rest = name[len(prefix):]
            for f in FINGERS:
                if rest.lower().startswith(f):
                    return "%s_%s_%s" % (f, rest[len(f):], side)
    return name


# ---------------------------------------------------------------- skeleton and pose

class Rig:
    """The skeleton's nodes as they lie at rest (the export's T-pose)."""

    def __init__(self, js):
        self.js = js
        self.nodes = js["nodes"]
        self.index = {n.get("name", ""): i for i, n in enumerate(self.nodes)}
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.local = {i: trs(n) for i, n in enumerate(self.nodes)}
        self._rest = {}

    def rest(self, name):
        """Rest matrix in model space."""
        if name not in self._rest:
            i = self.index[name]
            p = self.parent.get(i)
            self._rest[name] = (self.rest(self.nodes[p]["name"]) if p is not None else np.eye(4)) @ self.local[i]
        return self._rest[name]


class Pose:
    """Bone poses for one frame, relative to the rest pose, like a Blender pose: by a local rotation
    (FK) or by where the bone should end up in model space (IK). world() is model space."""

    def __init__(self, rig):
        self.rig = rig
        self.basis = {}
        self._world = {}

    def reset(self):
        self.basis = {}
        self._world = {}

    def parent_world(self, name):
        p = self.rig.parent.get(self.rig.index[name])
        return self.world(self.rig.nodes[p]["name"]) if p is not None else np.eye(4)

    def world(self, name):
        if name not in self._world:
            self._world[name] = self.parent_world(name) @ self.rig.local[self.rig.index[name]] @ self.basis.get(name, np.eye(4))
        return self._world[name]

    def head(self, name):
        return self.world(name)[:3, 3].copy()

    def local(self, name):
        """The node's local matrix in this pose (what the clip keys)."""
        return self.rig.local[self.rig.index[name]] @ self.basis.get(name, np.eye(4))

    def turn(self, name, axis, angle):
        """Adds a rotation about a model-space axis (as the bone lies at rest) at the bone's head."""
        r = self.rig.rest(name)[:3, :3]
        q = axis_angle(r.T @ np.asarray(axis, dtype=float), angle)
        b = self.basis.get(name, np.eye(4)).copy()
        b[:3, :3] = q @ b[:3, :3]
        self.basis[name] = b
        self._world = {}

    def move(self, name, offset):
        """Moves a root bone by a model-space offset."""
        r = self.rig.rest(name)[:3, :3]
        b = self.basis.get(name, np.eye(4)).copy()
        b[:3, 3] += r.T @ np.asarray(offset, dtype=float)
        self.basis[name] = b
        self._world = {}

    def place(self, name, m):
        """Poses the bone so it ends up at model-space matrix m."""
        carried = self.parent_world(name) @ self.rig.local[self.rig.index[name]]
        self.basis[name] = np.linalg.inv(carried) @ m
        self._world = {}


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def aim_frame(y, pole):
    """Rotation whose Y axis is y and whose Z axis leans toward pole."""
    z = unit(pole - y * np.dot(pole, y))
    return np.column_stack([np.cross(y, z), y, z])


def two_bone(a, l1, l2, target, pole):
    """2-bone IK: (joint, end) for a chain of lengths l1, l2 from a toward target, bending toward
    pole. end is target unless it is out of reach."""
    d = target - a
    dist = min(max(np.linalg.norm(d), abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = unit(d)
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    side = unit(pole - dn * np.dot(pole, dn))
    joint = a + (dn * cos_a + side * math.sqrt(max(0.0, 1 - cos_a * cos_a))) * l1
    return joint, a + dn * dist


def frame_from(local_a, local_b, world_a, world_b):
    """Rotation taking local axis a to world_a, and local axis b (as near as it can) to world_b."""
    def basis(a, b):
        a = unit(a)
        b = unit(b - a * np.dot(b, a))
        return np.column_stack([a, b, np.cross(a, b)])
    return basis(world_a, world_b) @ basis(local_a, local_b).T


def place_chain(pose, upper, lower, root, joint, end, pole):
    """Points two bones from root through joint to end, twisting them toward pole."""
    for name, h, t in ((upper, root, joint), (lower, joint, end)):
        r = pose.rig.rest(name)[:3, :3]
        rest_y = r @ Y
        q = aim_frame(unit(t - h), pole) @ aim_frame(unit(rest_y), pole).T
        pose.place(name, translation(h) @ rotation(q @ r))


def wave(t, period, harmonic=1, phase=0.0):
    return math.sin(2 * math.pi * (harmonic * t / period - phase))


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lowpass(values, harmonics):
    """Keeps the first few harmonics of one loop of samples (stays seamless)."""
    f = np.fft.rfft(np.array(values))
    f[harmonics + 1:] = 0
    return list(np.fft.irfft(f, len(values)))


def hermite(p0, p1, m0, m1, u):
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1


def rot_x(a):
    return axis_angle(X, a)


def rot_y(a):
    return axis_angle(Y, a)


# ---------------------------------------------------------------- legs

class Legs:
    """Rest measurements of both legs, the foot paths of a walk and the IK that poses them."""

    def __init__(self, pose, verts):
        self.pose = pose
        self.info = {}
        for s in "LR":
            th, sh, ft, toe = LEG_BONES[s]
            hip, knee, ankle, ball = (pose.rig.rest(b)[:3, 3].copy() for b in (th, sh, ft, toe))
            # The sole: heel and toe tips from the vertices near the ground under this foot.
            near = verts[(verts[:, 1] < 0.1) & (np.abs(verts[:, 0] - ankle[0]) < 0.15)]
            self.info[s] = {
                "bones": (th, sh, ft, toe), "l1": np.linalg.norm(knee - hip), "l2": np.linalg.norm(ankle - knee),
                "hip": hip, "ankle": ankle, "ball": np.array([ball[0], 0.0, ball[2]]),
                "heel": np.array([ankle[0], 0.0, float(near[:, 2].min())]),
                "tip": np.array([ankle[0], 0.0, float(near[:, 2].max())]),
                "side": 1.0 if s == "L" else -1.0,
            }

    def stance_foot(self, s, u, walk):
        """(ankle, foot pitch, toe bend) u of the way through the stance."""
        i = self.info[s]
        d, sweep, fwd = walk["d"], walk["sweep"], walk["fwd"]
        ground = np.array([i["ankle"][0] + i["side"] * walk["widen"], 0.0, i["ankle"][2]]) + d * sweep * (0.5 - u)
        ahead, behind = max(fwd, 0.0), max(-fwd, 0.0)
        strike = smooth(0.18, 0.0, u)
        peel = smooth(1.0 - HEEL_OFF, 1.0, u) ** 1.5
        pitch = -STRIKE * ahead * strike + PUSH * ahead * peel + STRIKE * behind * strike - STRIKE * behind * peel
        if pitch > 0.0:
            pivot = i["ball"] if ahead >= behind else i["tip"]
        else:
            pivot = i["heel"]
        toe = -pitch if pitch > 0.0 and pivot is i["ball"] else 0.0
        return self._ankle(i, ground, pitch, pivot), pitch, toe

    @staticmethod
    def _ankle(i, ground, pitch, pivot):
        """Ankle position for the foot standing on `ground` (the spot under its ankle at rest), pitched
        about `pivot` (heel, ball or toe tip, at rest). Positive pitch: the heel up."""
        foot0 = np.array([i["ankle"][0], 0.0, i["ankle"][2]])
        rel = np.array([0.0, i["ankle"][1], 0.0]) - (pivot - foot0)
        return ground + (pivot - foot0) + rot_x(pitch) @ rel

    def foot(self, s, t, walk):
        """(ankle, foot pitch, toe bend) at time t of the walk."""
        phase = (t / WALK_PERIOD - SWING_MID[s] + SWING / 2) % 1.0  # 0 at lift-off
        if phase >= SWING:
            return self.stance_foot(s, (phase - SWING) / DUTY, walk)
        u = phase / SWING
        a0, p0, t0 = self.stance_foot(s, 1.0, walk)  # lift-off
        a1, p1, _ = self.stance_foot(s, 0.0, walk)  # touch-down
        d = walk["d"]
        v = walk["sweep"] * SWING / DUTY
        along = hermite(np.dot(a0, d), np.dot(a1, d), -0.35 * v, -v, u)
        base = a0 + (a1 - a0) * u
        pos = base + d * (along - np.dot(base, d))
        pos[1] += walk["lift"] * math.sin(math.pi * u ** 0.85) ** 1.2
        pos[0] += self.info[s]["side"] * 0.02 * math.sin(math.pi * u)
        pitch = p0 + (p1 - p0) * smooth(0.0, 0.65, u) - math.radians(8.0) * walk["ahead"] * math.sin(math.pi * u)
        toe = t0 * smooth(0.45, 0.0, u)
        return pos, pitch, toe

    def reach(self, s, ankle, hip):
        """Highest the hip joint can be above its rest height and still reach `ankle`."""
        i = self.info[s]
        full = (i["l1"] + i["l2"]) * STRAIGHT
        flat = math.hypot(hip[0] - ankle[0], hip[2] - ankle[2])
        return ankle[1] + math.sqrt(max(full * full - flat * flat, 0.0)) - hip[1]

    def solve(self, s, ankle, pitch, toe, pole):
        """Poses the leg to put the ankle at `ankle`, the foot pitched and the toes bent."""
        i = self.info[s]
        th, sh, ft, tb = i["bones"]
        p = self.pose
        a = p.head(th)
        knee, end = two_bone(a, i["l1"], i["l2"], ankle, pole)
        place_chain(p, th, sh, a, knee, end, pole)
        r = p.rig.rest(ft)[:3, :3]
        p.place(ft, translation(end) @ rotation(rot_x(pitch) @ r))
        if toe:
            p.turn(tb, X, toe)
        return float(np.linalg.norm(end - ankle))


def walk_params(direction):
    bx, by = DIRECTIONS[direction]
    v = np.array([-bx * SIDE_SPEED, 0.0, by * (FORWARD_SPEED if by >= 0 else BACK_SPEED)])
    speed = float(np.linalg.norm(v))
    d = v / speed
    fwd = float(d[2])
    return {
        "d": d, "speed": speed, "fwd": fwd, "ahead": max(fwd, 0.0),
        "sweep": speed * WALK_PERIOD * DUTY,
        "widen": WIDEN * abs(d[0]),
        "lift": LIFT * (0.75 + 0.25 * max(fwd, 0.0)),
    }


def hip_heights(legs, walk, ts, sway):
    """How high the hips ride each frame: as high as the planted legs allow when nearly straight (two
    dips per cycle). A foot just off the ground, or about to land, has to be reachable too."""
    out = []
    for k, t in enumerate(ts):
        r = []
        for s in "LR":
            phase = (t / WALK_PERIOD - SWING_MID[s] + SWING / 2) % 1.0
            if not 0.3 * SWING < phase < 0.75 * SWING:
                ankle, _, _ = legs.foot(s, t, walk)
                hip = legs.info[s]["hip"] + np.array([sway[k], 0.0, 0.0])
                r.append(legs.reach(s, ankle, hip))
        out.append(min(r))
    smooth_rise = lowpass(out, 4)
    over = max(a - b for a, b in zip(smooth_rise, out))
    return [a - over for a in smooth_rise]


# ---------------------------------------------------------------- the archer's upper body

def stance(pose, yaw=0.0, roll=0.0, look=0.0):
    """The archer's stance on top of the hips' own turn and roll: the spine turns the chest CHEST_YAW
    off the front (cancelling what the hips turn), and levels it; the neck turns the head back to look
    ahead (and `look` further), canted toward the string."""
    spine = CHEST_YAW - HIP_TURN - yaw
    for name, share in TWIST.items():
        pose.turn(name, Y, spine * share)
    pose.turn("spine_1", Z, -roll * 0.6)
    pose.turn("spine_2", Z, -roll * 0.4)
    for name, share in COUNTER.items():
        pose.turn(name, Y, (-CHEST_YAW + look) * share)
    pose.turn("head", Z, -HEAD_CANT)


class Arms:
    """The archer's arms. At the reference stance it works out where the hands go: the string hand's
    fingers at the anchor by the chin, the bow hand on the line straight ahead from there at ARM_REACH
    of the left arm. Those (and the hands' turn) are kept in the chest's frame, so every frame the
    arms are solved onto them wherever the chest has gone."""

    def __init__(self, pose):
        rig = pose.rig
        self.pose = pose
        self.len = {}
        for s in "LR":
            up, lo, ha = ("upperarm_" + s, "forearm_" + s, "hand_" + s)
            self.len[s] = (np.linalg.norm(rig.rest(lo)[:3, 3] - rig.rest(up)[:3, 3]),
                           np.linalg.norm(rig.rest(ha)[:3, 3] - rig.rest(lo)[:3, 3]))
        # Palms face down in the T-pose: each hand's palm as a local axis.
        self.palm = {s: rig.rest("hand_" + s)[:3, :3].T @ -Y for s in "LR"}

    def reference(self):
        """From the pose as it stands (the reference stance): the targets in the chest's frame."""
        p = self.pose
        chest = p.world("chest")
        anchor = p.head("head") + ANCHOR
        shoulder = p.head("upperarm_L")
        l1, l2 = self.len["L"]
        reach = (l1 + l2) * ARM_REACH
        d = anchor - shoulder
        along = float(np.dot(d, Z))
        perp2 = float(np.dot(d, d)) - along * along
        if perp2 > reach * reach:
            raise SystemExit("the bow arm can't reach the arrow's line: turn the chest further (CHEST_YAW)")
        wrist_l = anchor + Z * (-along + math.sqrt(reach * reach - perp2))
        grip = wrist_l + Z * GRIP
        hand_l = frame_from(Y, self.palm["L"], Z, -X)  # fingers ahead, palm to her right
        draw_dir = unit(Z + X * 0.12)
        hand_r = frame_from(Y, self.palm["R"], draw_dir, X)  # fingers on the string, palm to her face
        wrist_r = anchor - draw_dir * NOCK
        inv = np.linalg.inv(chest)
        self.targets = {
            "L": inv @ translation(wrist_l) @ rotation(hand_l),
            "R": inv @ translation(wrist_r) @ rotation(hand_r),
        }
        bow = rotation(frame_from(Y, Z, Y, Z))
        self.markers = {"bow": inv @ translation(grip) @ bow, "nock": inv @ translation(anchor) @ bow}
        # Elbows: the bow arm's down and out, the string arm's back at shoulder height.
        poles = {"L": unit(X * 0.6 - Y), "R": unit(-Z - X * 0.35 - Y * 0.15)}
        self.poles = {s: chest[:3, :3].T @ poles[s] for s in "LR"}
        print(f"stance: draw {np.linalg.norm(grip - anchor):.2f} m, grip {np.round(grip, 3)}, anchor {np.round(anchor, 3)}")

    def solve(self):
        p = self.pose
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

    def curl_fingers(self):
        """The bow hand round the grip, the string hand hooked on the string (about each finger's curl
        axis at rest: from its length toward the palm)."""
        p = self.pose
        rig = p.rig
        for s, curls in (("L", GRIP_CURL), ("R", DRAW_CURL)):
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


# ---------------------------------------------------------------- clips

class Baker:
    def __init__(self, rig, verts, joints):
        self.rig = rig
        self.joint_set = set(joints)
        self.pose = Pose(rig)
        self.legs = Legs(self.pose, verts)
        self.arms = Arms(self.pose)
        self.clips = {}
        self.fingers = {}

    def upper(self, yaw=0.0, roll=0.0, lean=0.0, look=0.0, breathe=0.0):
        p = self.pose
        stance(p, yaw, roll, look)
        p.turn("spine_1", X, -lean * 0.5)
        p.turn("chest", X, breathe)
        p.turn("head", X, -breathe * 0.8)

    def reference(self):
        """The rest pose: crouched a little in the stance, feet where they stand, the hands set."""
        p = self.pose
        p.reset()
        p.move("pelvis", (0.0, -CROUCH, 0.0))
        p.turn("pelvis", Y, HIP_TURN)
        self.upper()
        self.arms.reference()
        self.arms.solve()
        self.arms.curl_fingers()
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
        """Keys this frame: every animated bone's local (rotation, and the pelvis' translation)."""
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
        sway = [SWAY * (0.4 + 0.6 * abs(fwd)) * -math.cos(2 * math.pi * t / T) for t in ts]
        rise = hip_heights(self.legs, walk, ts, sway)
        rise = [min(x, 0.0) - CROUCH for x in rise]
        keys = []
        worst, closest = 0.0, 9.0
        for f, t in enumerate(ts):
            p = self.pose
            p.reset()
            self._with_fingers()
            yaw = -YAW * abs(fwd) * wave(t, T) * (1 if fwd >= 0 else -1)
            roll = ROLL * (0.3 + 0.7 * abs(fwd)) * math.cos(2 * math.pi * t / T)
            lean = math.radians(4.0 * max(fwd, 0.0) - 3.0 * max(-fwd, 0.0))
            p.move("pelvis", (sway[f], rise[f], 0.0))
            p.turn("pelvis", Y, HIP_TURN + yaw)
            p.turn("pelvis", Z, roll)
            p.turn("pelvis", X, lean)
            p.turn("pelvis", Z, math.radians(2.5) * side)  # leaning into a sidestep
            self.upper(yaw, roll, lean, breathe=math.radians(1.0) * wave(t, T, 2, 0.3))
            pole = rot_y(HIP_TURN * 0.4 + yaw) @ Z
            ankles = {}
            for s in "LR":
                ankle, pitch, toe = self.legs.foot(s, t, walk)
                worst = max(worst, self.legs.solve(s, ankle, pitch, toe, pole))
                ankles[s] = ankle
            closest = min(closest, math.hypot(*(ankles["L"] - ankles["R"])[[0, 2]]))
            self.arms.solve()
            keys.append(self._frame())
        keys.append(keys[0])
        self.clips["Walk_" + direction] = keys
        print(f"Walk_{direction}: {walk['speed']:.2f} m/s, sweep {walk['sweep']:.2f} m, hips {min(rise):+.3f}..{max(rise):+.3f} m, "
              f"feet at least {closest:.2f} m apart, worst miss {worst * 100:.1f} cm")

    def bake_idle(self):
        frames = int(round(IDLE_PERIOD * FPS))
        T = IDLE_PERIOD
        keys = []
        for f in range(frames):
            t = f / FPS
            p = self.pose
            p.reset()
            self._with_fingers()
            sway = 0.012 * wave(t, T)
            p.move("pelvis", (sway, -CROUCH - 0.006 * (1 + wave(t, T, 2, 0.25)), 0.0))
            yaw = math.radians(1.5) * wave(t, T, 1, 0.2)
            p.turn("pelvis", Y, HIP_TURN + yaw)
            p.turn("pelvis", Z, math.radians(1.2) * wave(t, T))
            self.upper(yaw, math.radians(1.2) * wave(t, T), look=math.radians(4.0) * wave(t, T, 1, 0.1),
                       breathe=math.radians(1.6) * wave(t, T, 2))
            self._planted_feet()
            self.arms.solve()
            keys.append(self._frame())
        keys.append(keys[0])
        self.clips["Idle"] = keys
        print(f"Idle: {IDLE_PERIOD:.1f} s")


# ---------------------------------------------------------------- writing it out

def rename_bones(js):
    for n in js["nodes"]:
        if "name" in n:
            n["name"] = clean_name(n["name"])


def add_marker(js, parent_name, name, local):
    """A bone with no weights under `parent_name`, at `local` in its frame; joins the skin."""
    nodes = js["nodes"]
    parent = next(i for i, n in enumerate(nodes) if n.get("name") == parent_name)
    node = {"name": name}
    set_trs(node, local)
    nodes.append(node)
    k = len(nodes) - 1
    nodes[parent].setdefault("children", []).append(k)
    return k


def write_clips(js, binary, rig, clips):
    js["animations"] = []
    idx = {n["name"]: i for i, n in enumerate(js["nodes"]) if "name" in n}
    for name, keys in clips.items():
        times = np.arange(len(keys), dtype=np.float32) / FPS
        tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
        anim = {"name": name, "channels": [], "samplers": []}
        for bone in ANIMATED:
            quats = []
            prev = None
            for k in keys:
                q = mat_to_quat(k[bone][:3, :3])
                if prev is not None and np.dot(q, prev) < 0:
                    q = -q  # the short way round
                quats.append(q)
                prev = q
            out = add_accessor(js, binary, np.array(quats), "VEC4")
            anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
            anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "rotation"}})
            if bone == "pelvis":
                pos = np.array([k[bone][:3, 3] for k in keys])
                out = add_accessor(js, binary, pos, "VEC3")
                anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
                anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "translation"}})
        js["animations"].append(anim)


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    rename_bones(js)
    rig = Rig(js)
    skin = js["skins"][0]
    mesh_node = next(n for n in js["nodes"] if "skin" in n)
    prim = js["meshes"][mesh_node["mesh"]]["primitives"][0]
    verts = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)

    baker = Baker(rig, verts, skin["joints"])
    baker.reference()
    # Markers on the hands, from where the reference put the grip and the anchor.
    pose = baker.pose
    chest = pose.world("chest")
    markers = {}
    for name, parent in (("bow", "hand_L"), ("nock", "hand_R")):
        world = chest @ baker.arms.markers[name]
        markers[name] = (parent, np.linalg.inv(pose.world(parent)) @ world)
    for d in DIRECTIONS:
        baker.bake_walk(d)
    baker.bake_idle()

    # The stance is the rest pose: every joint's node transform as the reference left it.
    for name, local in baker.rest_locals.items():
        set_trs(js["nodes"][rig.index[name]], local)
    ibm = accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4)
    ibm = list(ibm)
    for name, (parent, local) in markers.items():
        k = add_marker(js, parent, name, local)
        skin["joints"].append(k)
        # Bind matrix: where the marker would be in the bind pose (the T-pose), from its parent's.
        pidx = skin["joints"].index(rig.index[parent])
        parent_bind = np.linalg.inv(ibm[pidx].T)
        ibm.append(np.linalg.inv(parent_bind @ local).T)
    skin["inverseBindMatrices"] = add_accessor(js, binary, np.array(ibm).reshape(-1, 16), "MAT4")
    write_clips(js, binary, rig, baker.clips)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/rig_infiltrator.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(skin['joints'])} joints, clips {list(baker.clips)}")
    if args.preview:
        render_preview(args.output, args.preview)


# ---------------------------------------------------------------- preview

def skinned_vertices(js, binary, clip=None, frame=0):
    """The mesh's vertices posed by a clip's frame (or the rest pose), and its triangles and UVs."""
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
                m[:3, :3] = quat_to_mat(vals[frame])
            elif ch["target"]["path"] == "translation":
                m[:3, 3] = vals[frame]
            local[i] = m
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    world = {}

    def w(i):
        if i not in world:
            world[i] = (w(parent[i]) if i in parent else np.eye(4)) @ local[i]
        return world[i]

    skin = js["skins"][0]
    ibm = accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4).transpose(0, 2, 1)
    mats = np.array([w(j) @ ibm[k] for k, j in enumerate(skin["joints"])])
    node = next(n for n in nodes if "skin" in n)
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    joints = accessor(js, binary, prim["attributes"]["JOINTS_0"]).astype(int)
    weights = accessor(js, binary, prim["attributes"]["WEIGHTS_0"]).astype(float)
    if weights.max() > 1.5:
        weights /= 255.0 if weights.max() <= 255 else 65535.0
    hom = np.concatenate([pos, np.ones((len(pos), 1))], 1)
    out = np.zeros((len(pos), 3))
    for k in range(4):
        m = mats[joints[:, k]]
        out += weights[:, k:k + 1] * np.einsum("nij,nj->ni", m, hom)[:, :3]
    idx = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    uv = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)
    markers = {n["name"]: w(i)[:3, 3] for i, n in enumerate(nodes) if n.get("name") in ("bow", "nock")}
    bow = next((w(i) for i, n in enumerate(nodes) if n.get("name") == "bow"), None)
    return out, idx, uv, markers, bow


def rasterize(img, zbuf, pts, idx, uv, tex, eye, target, fov=35.0):
    """Draws triangles into img (H, W, 3) with a z-buffer, textured, lit from above-front."""
    from_ = np.asarray(eye, float)
    f = unit(np.asarray(target, float) - from_)
    r = unit(np.cross(f, Y))
    u = np.cross(r, f)
    rel = pts - from_
    cx, cy, cz = rel @ r, rel @ u, rel @ f
    h, w = zbuf.shape
    k = (w * 0.5) / math.tan(math.radians(fov) * 0.5)
    with np.errstate(divide="ignore", invalid="ignore"):
        sx = w * 0.5 + cx / cz * k
        sy = h * 0.5 - cy / cz * k
    tri = pts[idx]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    shade = 0.45 + 0.55 * np.abs(n @ unit([0.3, 0.8, 0.5]))
    for t in range(len(idx)):
        i0, i1, i2 = idx[t]
        if min(cz[i0], cz[i1], cz[i2]) < 0.05:
            continue
        xs_, ys_ = (sx[i0], sx[i1], sx[i2]), (sy[i0], sy[i1], sy[i2])
        x0, x1 = max(int(min(xs_)), 0), min(int(max(xs_)) + 1, w - 1)
        y0, y1 = max(int(min(ys_)), 0), min(int(max(ys_)) + 1, h - 1)
        if x0 > x1 or y0 > y1:
            continue
        den = (ys_[1] - ys_[2]) * (xs_[0] - xs_[2]) + (xs_[2] - xs_[1]) * (ys_[0] - ys_[2])
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a = ((ys_[1] - ys_[2]) * (gx - xs_[2]) + (xs_[2] - xs_[1]) * (gy - ys_[2])) / den
        b = ((ys_[2] - ys_[0]) * (gx - xs_[2]) + (xs_[0] - xs_[2]) * (gy - ys_[2])) / den
        c = 1 - a - b
        m = (a >= 0) & (b >= 0) & (c >= 0)
        z = a * cz[i0] + b * cz[i1] + c * cz[i2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        m &= z < sub
        if not m.any():
            continue
        sub[m] = z[m]
        tu = (a * uv[i0, 0] + b * uv[i1, 0] + c * uv[i2, 0]) % 1.0
        tv = (a * uv[i0, 1] + b * uv[i1, 1] + c * uv[i2, 1]) % 1.0
        th, tw = tex.shape[:2]
        col = tex[(tv * (th - 1)).astype(int), (tu * (tw - 1)).astype(int)]
        img[y0:y1 + 1, x0:x1 + 1][m] = col[m] * shade[t]
    return sx, sy, cz


def render_preview(path, out_dir):
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    js, binary = read_glb(path)
    mat = js["materials"][0]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    tex = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((512, 512)), dtype=np.float32) / 255.0
    shots = [(None, [0])] + [("Idle", [0, 60])] + [("Walk_" + d, [0, 5, 10, 15]) for d in ("F", "R", "B", "FL")]
    views = {"front": (np.array([0.0, 1.1, 3.4]), np.array([0.0, 0.95, 0.0])),
             "side": (np.array([3.4, 1.1, 0.4]), np.array([0.0, 0.95, 0.2])),
             "back": (np.array([-1.2, 1.7, -2.6]), np.array([0.0, 1.2, 0.3]))}
    for clip, frames in shots:
        row = []
        for f in frames:
            pts, idx, uv, markers, bow = skinned_vertices(js, binary, clip, f)
            for vname, (eye, target) in views.items():
                img = np.ones((300, 220, 3), np.float32) * np.array([0.55, 0.65, 0.75], np.float32)
                zb = np.full((300, 220), np.inf, np.float32)
                rasterize(img, zb, pts, idx, uv, tex, eye, target)
                pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
                dr = ImageDraw.Draw(pil)
                # The bow (its two tips) and the string to the nock.
                if bow is not None:
                    tips = [bow[:3, :3] @ np.array([0.0, s * 0.66, -0.15]) + bow[:3, 3] for s in (1, -1)]
                    pts2 = np.array(tips + [markers["nock"], markers["bow"]])
                    sx, sy, cz = project(pts2, eye, target, 220, 300)
                    dr.line([(sx[0], sy[0]), (sx[3], sy[3]), (sx[1], sy[1])], fill=(30, 30, 30), width=2)
                    dr.line([(sx[0], sy[0]), (sx[2], sy[2]), (sx[1], sy[1])], fill=(230, 230, 220), width=1)
                dr.text((4, 4), f"{clip or 'rest'} {f} {vname}", fill=(0, 0, 0))
                row.append(pil)
        sheet = Image.new("RGB", (220 * len(row), 300))
        for k, p in enumerate(row):
            sheet.paste(p, (220 * k, 0))
        sheet.save(os.path.join(out_dir, f"{clip or 'rest'}.png"))
    print(f"preview in {out_dir}")


def project(pts, eye, target, w, h, fov=35.0):
    f = unit(np.asarray(target, float) - eye)
    r = unit(np.cross(f, Y))
    u = np.cross(r, f)
    rel = pts - eye
    cx, cy, cz = rel @ r, rel @ u, rel @ f
    k = (w * 0.5) / math.tan(math.radians(fov) * 0.5)
    return w * 0.5 + cx / cz * k, h * 0.5 - cy / cz * k, cz


if __name__ == "__main__":
    main()
