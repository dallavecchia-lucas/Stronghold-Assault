"""Rig and animate the Armored Lioness. No Blender: numpy on the glTF itself, like rig_infiltrator.py.

Input: the processed Meshy auto-rig (game/assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb:
1.6 m to the top of the gear, origin between the paws, front +Z, Meshy's Walk and a held Idle). Its rig is
no good for her: the flamethrower rig on her back is skinned mostly to the head and the tail (the auto-rig
took the turret for her ears: their bones end inside it), the neck has no bone and the hind legs' joints
sit in the flanks. So this keeps the mesh (her hind legs stay mid-stride in the bind pose, as modelled)
and builds a new skeleton along the lioness, skinned by region like the giraffe's (rig_giraffe.py):
the torso in three bones (pelvis, body, chest), the neck, the head and the jaw; each leg in four
(fore: upperarm, forearm, forepaw, foretoes; hind: thigh, shin, hindfoot, hindtoes), a cat walking on
its toes; and the tail in five.

The gear stays on. The flamethrower rig on her back (the turret, its two barrels, the twin fuel tanks
and their hoses) rides rigidly on the body bone; small pieces elsewhere (knee and hock guards, pouches,
the plates over the shoulders, the pieces on the face) ride rigidly where they sit; big ones (straps)
bend with the skin under them. `nozzle_1` (the lower barrel's claw nozzle) and `nozzle_2` (the upper
barrel's mouth) mark where the flames come out, their Y axis out of the barrel, no weights; the game
lights the fire blast there (LionessRig).

Clips (FPS frames per second; looped clips end on a copy of their first frame, which the game drops):
  Idle    standing square: breathing, slow weight shifts, the head looking round, the tail swishing
          and its tip curling, the ears flicking.
  Walk    a cat's walk, authored travelling at WALK_SPEED (UnitTypes anim_ref_speed): a lateral
          sequence, each fore paw lifting just after the hind paw on its side lands. Paws planted by IK
          while down; the fore paws peel off the ground and fold back at the wrist through the swing,
          the hind paws roll over their toes. The shoulders and hips ride as high as the planted legs
          allow and roll over the side that is down, the head bobs a little with each fore step, held
          level, the tail sways low.
  Run     a cat's gallop (rotary), authored at RUN_SPEED (UnitTypes anim_run_speed): the hind paws land
          one after the other, push off into a stretched-out flight, the fore paws reach far ahead,
          land one after the other and the back gathers the hind legs under it for the next stride.
  Sneak   the stalk, authored at SNEAK_SPEED (UnitTypes anim_sneak_speed): belly low over the ground,
          shoulder blades high, the head low, level and still, eyes on the prey, each paw lifted high
          and set down slowly in front; the tail held low, its tip twitching.
  Pounce  (not looped, POUNCE_TIME long) the pounce: she sinks back onto her haunches and wiggles her
          rump, springs (POUNCE_LAUNCH seconds in) and flies stretched out, fore paws reaching for the
          prey, claws out, mouth open, and lands on it at POUNCE_LAND (the game moves her along the
          arc in between: UnitTypes pounce_*), the fore legs taking the blow.
  Strike  (not looped, STRIKE_TIME long) one blow of her melee attack: she rocks back, rears up off her
          fore paws and swipes down with the right paw (it lands STRIKE_HIT seconds in), biting as the
          head lunges in after it, then drops back onto all fours.

  python3 tools/gltf/rig_lioness.py \\
      --input game/assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb \\
      --output game/assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb [--preview DIR]

The input may be the output of an earlier run (the rig is rebuilt from the mesh each time).
--preview renders the rest pose and frames of every clip into DIR as PNGs (rig_infiltrator's plain numpy
rasterizer), the walking clips travelling at their speeds over a grid on the ground.
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import (accessor, add_accessor, axis_angle, compact, mat_to_quat, quat_to_mat, read_glb,  # noqa: E402
                     rotation, set_trs, translation, trs, write_glb)
from rig_infiltrator import (Pose, Rig, aim_frame, hermite, lowpass, project, rasterize, smooth,  # noqa: E402
                             two_bone, unit, wave)

FPS = 30
# Model axes (glTF): +X her left, +Y up, +Z her front.
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])
RAD = math.pi / 180

# ---------------------------------------------------------------- the skeleton (model frame, meters)
# Measured on the mesh: the torso's spine, the neck and the head along the middle of the body; the
# legs' joints from slices across each leg (the left ones; the right fore leg mirrors the left, a little
# further out). Fore leg: shoulder, elbow, wrist, the ball of the paw, the toe tips. Hind leg: hip,
# stifle, hock, the ball of the paw, the toe tips. The right hind leg stands back in the bind pose (she
# was modelled mid-stride): its joints lie along it, with the left hind leg's bone lengths.
SPINE = [(0.0, 0.90, -0.62), (0.0, 0.86, -0.15), (0.0, 0.84, 0.30), (0.0, 0.86, 0.74)]  # rump .. withers
NECK = [(0.0, 0.86, 0.74), (0.0, 0.90, 0.95)]
HEAD_TIP = (0.0, 0.80, 1.36)
JAW = [(0.0, 0.755, 1.09), (0.0, 0.645, 1.31)]
TAIL = [(0.0, 0.95, -0.64), (0.0, 0.77, -0.825), (0.0, 0.54, -0.90), (0.0, 0.36, -1.05), (0.0, 0.37, -1.20),
        (0.0, 0.40, -1.34)]
FORE_LEG = {"L": [(0.19, 0.74, 0.76), (0.215, 0.48, 0.47), (0.19, 0.17, 0.51), (0.19, 0.04, 0.575), (0.19, 0.02, 0.665)],
            "R": [(-0.20, 0.74, 0.76), (-0.225, 0.48, 0.47), (-0.20, 0.17, 0.51), (-0.20, 0.04, 0.575), (-0.20, 0.02, 0.665)]}
HIND_LEG_L = [(0.17, 0.82, -0.52), (0.17, 0.51, -0.40), (0.135, 0.25, -0.53), (0.15, 0.04, -0.365), (0.15, 0.02, -0.27)]
# The right hind leg: its hip, then which way each bone runs from the joint before (along the leg as it
# stands back), and the toes ahead of the ball.
HIND_LEG_R_HIP = (-0.17, 0.82, -0.52)
HIND_LEG_R_AIM = [(-0.17, 0.52, -0.62), (-0.15, 0.28, -0.80), (-0.15, 0.04, -0.76)]
HIND_TOES_R = (0.0, -0.02, 0.095)
# The jaw: head vertices behind JAW_Z[0] stay with the head, in front of JAW_Z[1] they are all jaw if
# below the mouth (JAW_Y[0], blending up to JAW_Y[1]).
JAW_Z = (1.07, 1.15)
JAW_Y = (0.712, 0.742)
# Flamethrower nozzles: the mouth of each barrel (measured on the gear), the flame leaving along +Z.
NOZZLES = {"nozzle_1": (-0.004, 1.385, 1.0), "nozzle_2": (-0.083, 1.462, 0.775)}
# Gear on her back: pieces of the mesh (other than the body) centred above this, within GEAR_HALF_X of the
# middle, ride the body bone.
GEAR_Y = 1.14
GEAR_HALF_X = 0.34
# A piece smaller than this (m) rides rigidly where it sits; bigger ones bend with the skin under them.
RIGID_SIZE = 0.16
# How high up the shoulder (fore) and the haunch (hind) a leg's pull reaches (m): it fades out from there
# down 0.26 m, and below LEG_TOP - 0.42 everything near a leg is all leg.
LEG_TOP = {"F": 0.74, "H": 0.84}

LEG_NAMES = {"F": ("upperarm", "forearm", "forepaw", "foretoes"), "H": ("thigh", "shin", "hindfoot", "hindtoes")}
TAIL_BONES = ["tail_%d" % (k + 1) for k in range(len(TAIL) - 1)]


def v3(p):
    return np.asarray(p, dtype=float)


def hind_leg_r():
    """The right hind leg's joints: along HIND_LEG_R_AIM with the left hind leg's bone lengths."""
    left = [v3(p) for p in HIND_LEG_L]
    joints = [v3(HIND_LEG_R_HIP)]
    for k, aim in enumerate(HIND_LEG_R_AIM):
        length = np.linalg.norm(left[k + 1] - left[k])
        joints.append(joints[-1] + unit(v3(aim) - joints[-1]) * length)
    joints.append(joints[-1] + v3(HIND_TOES_R))
    return joints


def leg_joints(kind, side):
    if kind == "F":
        return [v3(p) for p in FORE_LEG[side]]
    return [v3(p) for p in HIND_LEG_L] if side == "L" else hind_leg_r()


def bone_list():
    """(name, parent, head, tail) for every bone, parents first."""
    out = [("body", None, SPINE[1], SPINE[2]),
           ("chest", "body", SPINE[2], SPINE[3]),
           ("pelvis", "body", SPINE[1], SPINE[0]),
           ("neck", "chest", NECK[0], NECK[1]),
           ("head", "neck", NECK[1], HEAD_TIP),
           ("jaw", "head", JAW[0], JAW[1])]
    for k, name in enumerate(TAIL_BONES):
        out.append((name, "pelvis" if k == 0 else TAIL_BONES[k - 1], TAIL[k], TAIL[k + 1]))
    for side in "LR":
        for kind, parent in (("F", "chest"), ("H", "pelvis")):
            j = leg_joints(kind, side)
            names = ["%s_%s" % (n, side) for n in LEG_NAMES[kind]]
            for k, name in enumerate(names):
                out.append((name, parent if k == 0 else names[k - 1], j[k], j[k + 1]))
    for name, at in NOZZLES.items():
        out.append((name, "body", at, v3(at) + Z * 0.1))
    return out


def rest_frame(head, tail):
    """A bone's rest matrix: at its head, Y along it, Z toward her left (or her front for a bone
    running across her)."""
    y = unit(v3(tail) - v3(head))
    pole = X if abs(np.dot(y, X)) < 0.9 else Z
    return translation(v3(head)) @ rotation(aim_frame(y, pole))


# ---------------------------------------------------------------- mesh pieces and skin weights

def pieces(pos, tris):
    """Connected pieces, counting vertices at the same spot as joined (the export splits the mesh along
    its UV seams). Largest first: the lioness herself, then the gear."""
    key = np.round(pos * 1e5).astype(np.int64)
    _, spot = np.unique(key, axis=0, return_inverse=True)
    spot = spot.ravel()
    root = np.arange(spot.max() + 1)

    def find(a):
        while root[a] != a:
            root[a] = root[root[a]]
            a = root[a]
        return a

    for t in tris:
        a = find(spot[t[0]])
        for b in (spot[t[1]], spot[t[2]]):
            b = find(b)
            if a != b:
                root[b] = a
    groups = {}
    for i in range(len(pos)):
        groups.setdefault(find(spot[i]), []).append(i)
    return sorted((np.array(g) for g in groups.values()), key=len, reverse=True)


def chain_weights(p, joints, names, blend):
    """Weights along a chain of bones (joints[i] -> joints[i + 1] is names[i]) for a point, from where
    it projects onto the chain: 1 inside a bone, blending into the next over `blend` m either side of
    each joint. Also the distance from the chain."""
    best = None
    s0 = 0.0
    lengths = []
    for i in range(len(joints) - 1):
        a, b = joints[i], joints[i + 1]
        ab = b - a
        length = float(np.linalg.norm(ab))
        lengths.append(length)
        t = min(max(float(np.dot(p - a, ab)) / (length * length), 0.0), 1.0)
        d = float(np.linalg.norm(a + ab * t - p))
        if best is None or d < best[0]:
            best = (d, s0 + length * t)
        s0 += length
    s = best[1]
    w = {}
    s0 = 0.0
    for i, name in enumerate(names):
        lo, hi = s0, s0 + lengths[i]
        win = 1.0
        if i > 0:
            win = min(win, smooth(lo - blend, lo + blend, s))
        if i < len(names) - 1:
            win = min(win, 1.0 - smooth(hi - blend, hi + blend, s))
        if win > 0.0:
            w[name] = win
        s0 = hi
    return w, best[0]


def mix(a, b, t):
    """Blends two weight dicts: t = 0 gives a, 1 gives b."""
    out = {}
    for k, v in a.items():
        out[k] = out.get(k, 0.0) + v * (1 - t)
    for k, v in b.items():
        out[k] = out.get(k, 0.0) + v * t
    return out


def torso_weights(q):
    """The torso, neck, head and jaw, by where a point projects onto the spine and the neck; the skull
    is all head (it blends into the neck only behind it)."""
    joints = [v3(SPINE[0]), v3(SPINE[1]), v3(SPINE[2]), v3(SPINE[3]), v3(NECK[1]), v3(HEAD_TIP)]
    w, _ = chain_weights(q, joints, ["pelvis", "body", "chest", "neck", "head"], 0.12)
    if w.get("head", 0.0) > 0.0 or w.get("neck", 0.0) > 0.0:
        w = mix(w, {"head": 1.0}, smooth(NECK[1][2] - 0.06, NECK[1][2] + 0.02, q[2]) * smooth(0.55, 0.62, q[1]))
    if w.get("head", 0.0) > 0.0:
        jaw = smooth(JAW_Z[0], JAW_Z[1], q[2]) * smooth(JAW_Y[1], JAW_Y[0], q[1])
        if jaw > 0.0:
            w = mix(w, {"jaw": 1.0}, jaw * w["head"])
    return w


def body_weights(q):
    """Skin weights for a point on the lioness."""
    best = None
    for side in "LR":
        for kind in "FH":
            names = ["%s_%s" % (n, side) for n in LEG_NAMES[kind]]
            w, d = chain_weights(q, leg_joints(kind, side), names, 0.05)
            if best is None or d < best[1]:
                best = (w, d, kind)
    # The tail hangs off the rump behind the hind legs, its tuft out behind: whatever is nearer it than any leg.
    if q[2] < -0.6 and q[1] < 0.98:
        w, d = chain_weights(q, [v3(p) for p in TAIL], TAIL_BONES, 0.05)
        if d < best[1] and d < 0.09:
            return mix(torso_weights(q), w, smooth(-0.6, -0.68, q[2]))
    # Legs: below the belly all leg (however thick the leg is there); up the shoulder and the haunch the
    # leg's pull fades into the torso, so the skin there stretches as the leg swings.
    top = LEG_TOP[best[2]]
    pull = max(smooth(0.22, 0.11, best[1]) * smooth(top, top - 0.26, q[1]), smooth(top - 0.3, top - 0.42, q[1]))
    if pull > 0.0:
        return mix(torso_weights(q), best[0], pull)
    return torso_weights(q)


def skin_weights(pos, parts):
    """The lioness by body_weights; the flamethrower rig on her back on the body bone; small gear rigid
    where it sits, big gear with the skin under it."""
    weights = [None] * len(pos)
    for i in parts[0]:
        weights[i] = body_weights(pos[i])
    counts = {"back": 0, "rigid": 0, "skin": 0}
    for piece in parts[1:]:
        p = pos[piece]
        c = p.mean(axis=0)
        size = float((p.max(axis=0) - p.min(axis=0)).max())
        if c[1] > GEAR_Y and abs(c[0]) < GEAR_HALF_X:
            kind, w = "back", {"body": 1.0}
        elif size < RIGID_SIZE:
            kind, w = "rigid", body_weights(c)
        else:
            kind, w = "skin", None
        counts[kind] += len(piece)
        for i in piece:
            weights[i] = w if w is not None else body_weights(pos[i])
    print("gear vertices: " + ", ".join(f"{k} {n}" for k, n in counts.items()))
    return weights


def pack_weights(weights, joint_index):
    """The four strongest influences per vertex (glTF carries four), normalized."""
    joints = np.zeros((len(weights), 4), np.uint8)
    values = np.zeros((len(weights), 4), np.float32)
    for i, w in enumerate(weights):
        top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        total = sum(x for _, x in top)
        for k, (name, x) in enumerate(top):
            joints[i, k] = joint_index[name]
            values[i, k] = x / total
    return joints, values


# ---------------------------------------------------------------- building the new glTF

def rebuild(js, binary):
    """Swaps the auto-rig for the new skeleton: the mesh node and the bones under one Armature node, the
    skin's joints and inverse bind matrices, the vertices' joints and weights. Returns the bone names."""
    mesh_node = next(n for n in js["nodes"] if "skin" in n)
    prim = js["meshes"][mesh_node["mesh"]]["primitives"][0]
    pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    tris = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    parts = pieces(pos, tris)
    print(f"mesh: {len(pos)} vertices, {len(tris)} triangles, {len(parts)} pieces (the body {len(parts[0])})")
    weights = skin_weights(pos, parts)

    bones = bone_list()
    world = {}
    nodes = [{"name": "Armature", "children": [1, 2]}, {"name": mesh_node.get("name", "lioness"), "mesh": mesh_node["mesh"], "skin": 0}]
    index = {}
    for name, parent, head, tail in bones:
        world[name] = rest_frame(head, tail)
        local = world[name] if parent is None else np.linalg.inv(world[parent]) @ world[name]
        node = {"name": name}
        set_trs(node, local)
        index[name] = len(nodes)
        nodes.append(node)
        if parent is not None:
            nodes[index[parent]].setdefault("children", []).append(index[name])
    js["nodes"] = nodes
    js["scenes"] = [{"name": "Scene", "nodes": [0]}]
    js["scene"] = 0
    joint_names = [b[0] for b in bones]
    joint_index = {name: k for k, name in enumerate(joint_names)}
    ibm = np.array([np.linalg.inv(world[name]).T.reshape(16) for name in joint_names])
    js["skins"] = [{"name": "Armature", "joints": [index[n] for n in joint_names], "skeleton": index["body"],
                    "inverseBindMatrices": add_accessor(js, binary, ibm, "MAT4")}]
    jw, ww = pack_weights(weights, joint_index)
    binary += b"\0" * (-len(binary) % 4)
    view = {"buffer": 0, "byteOffset": len(binary), "byteLength": jw.nbytes}
    binary += jw.tobytes()
    js["bufferViews"].append(view)
    js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5121, "count": len(jw), "type": "VEC4"})
    prim["attributes"]["JOINTS_0"] = len(js["accessors"]) - 1
    prim["attributes"]["WEIGHTS_0"] = add_accessor(js, binary, ww, "VEC4")
    js["animations"] = []
    return joint_names


# ---------------------------------------------------------------- legs

# Gaits: the ground speed each clip is authored for (m/s), seconds per stride (a whole number of
# frames), the share of the stride each paw is down, where in the stride each paw is in the middle of
# its swing, how far ahead of where it stands each pair's stance is centred (m), how much lower than
# standing the body rides (m) and how high the paws lift (share of LIFT). Her legs are nearly straight
# standing (the hind ones most): a planted paw only sweeps about 0.7 m under her, so the strides are
# short and quick for her size, and she walks a little crouched.
GAITS = {
    # A lateral sequence: each fore paw lifts just after the hind paw on its side lands.
    "walk": {"speed": 1.7, "period": 20 / FPS, "duty": 0.62, "mid": {"LH": 0.0, "LF": 0.26, "RH": 0.5, "RF": 0.76},
             "reach": {"F": 0.07, "H": 0.05}, "low": 0.04, "lift": 1.0},
    # The stalk: belly low, long careful steps, three paws down most of the time.
    "sneak": {"speed": 2.2, "period": 22 / FPS, "duty": 0.7, "mid": {"LH": 0.0, "LF": 0.24, "RH": 0.5, "RF": 0.74},
              "reach": {"F": 0.25, "H": 0.12}, "low": 0.2, "lift": 1.2},
    # A rotary gallop: the hind paws land left then right and push off into a stretched-out flight, the
    # fore paws land right then left and the back gathers the hind legs under it in a short flight.
    "run": {"speed": 6.0, "period": 14 / FPS, "duty": 0.26, "mid": {"RF": 0.62, "LF": 0.70, "LH": 0.12, "RH": 0.20},
            "reach": {"F": 0.2, "H": 0.12}, "low": 0.06, "lift": 1.6},
}
WALK_SPEED = GAITS["walk"]["speed"]
RUN_SPEED = GAITS["run"]["speed"]
SNEAK_SPEED = GAITS["sneak"]["speed"]
LIFT = {"F": 0.15, "H": 0.12}  # paw clearance mid-swing at a walk (m)
FOLD = {"F": 105.0, "H": 40.0}  # how far the paw folds back at the wrist / hock mid-swing (degrees)
HEEL_OFF = 0.3  # last share of the stance in which the paw peels off the ground
PEEL = {"F": 32.0, "H": 26.0}  # how far the wrist / hock has lifted over the toes by lift-off (degrees)
STRAIGHT = 0.985  # how straight a planted leg may get (share of its full length)
# Where each paw stands (the ball of the foot, on the ground) in the standing pose, and the line up
# from the ball to the wrist (fore) or the hock (hind): degrees back from upright.
STAND_Z = {"F": 0.575, "H": -0.47}
STAND_LEAN = {"F": 27.0, "H": 38.0}
# Bend: elbows bend back, stifles forward (the IK's pole), with a little outward splay.
BEND = {"F": -Z, "H": Z}


def rot_x(a):
    return axis_angle(X, a)


def rot_y(a):
    return axis_angle(Y, a)


def rot_z(a):
    return axis_angle(Z, a)


def aim_bone(pose, name, head, tail, pole=X):
    """Poses a bone so it runs from `head` toward `tail`, twisting as little as it can about it."""
    r = pose.rig.rest(name)[:3, :3]
    q = aim_frame(unit(tail - head), pole) @ aim_frame(unit(r @ Y), pole).T
    pose.place(name, translation(head) @ rotation(q @ r))


class Legs:
    """The four legs at rest, where their paws stand, and the IK that poses them. A leg's top two bones
    reach for the wrist (fore) or hock (hind) by 2-bone IK; the paw runs from there to the ball of the
    foot, and the toes lie flat ahead of it (or curl with the paw in the air)."""

    def __init__(self, pose):
        self.pose = pose
        self.info = {}
        rig = pose.rig
        for side in "LR":
            for kind in "FH":
                names = tuple("%s_%s" % (n, side) for n in LEG_NAMES[kind])
                j = [rig.rest(b)[:3, 3].copy() for b in names] + [leg_joints(kind, side)[4]]
                l1, l2, l3, l4 = (float(np.linalg.norm(j[k + 1] - j[k])) for k in range(4))
                # The line up from the ball to the wrist or hock, leaning back from upright (a +X turn
                # tilts a line forward).
                lean = STAND_LEAN[kind] * RAD
                up = np.array([0.0, math.cos(lean), -math.sin(lean)])
                self.info[side + kind] = {
                    "kind": kind, "side": side, "bones": names, "l": (l1, l2, l3, l4),
                    "ball": np.array([j[3][0], 0.04, STAND_Z[kind]]), "m0": up * l3,
                    "toe": unit(leg_joints(kind, "L")[4] - leg_joints(kind, "L")[3]) * l4,
                    "top": j[0], "out": 1.0 if side == "L" else -1.0,
                }

    def solve(self, leg, ball, angle, toe=0.0, splay=0.0):
        """Poses the leg: the ball of the paw at `ball`, the paw turned `angle` (rad, + lifts the wrist or
        hock forward over the ball and folds the paw back) from standing, the toes turned `toe` from
        lying flat (+ curls them under). Returns how far the paw missed (m)."""
        i = self.info[leg]
        p = self.pose
        b0, b1, b2, b3 = i["bones"]
        l1, l2, l3, l4 = i["l"]
        m = rot_x(angle) @ i["m0"]
        wrist = ball + m
        a = p.head(b0)
        pole = unit(BEND[i["kind"]] + X * i["out"] * (0.15 + splay))
        knee, end = two_bone(a, l1, l2, wrist, pole)
        aim_bone(p, b0, a, knee)
        aim_bone(p, b1, knee, end)
        paw = end - m
        aim_bone(p, b2, end, paw)
        aim_bone(p, b3, paw, paw + rot_x(toe) @ i["toe"])
        return float(np.linalg.norm(end - wrist))

    def reach(self, leg, ball, angle, top):
        """Highest the leg's top joint can be above `top` and still put the paw at `ball`."""
        i = self.info[leg]
        wrist = ball + rot_x(angle) @ i["m0"]
        full = (i["l"][0] + i["l"][1]) * STRAIGHT
        flat = math.hypot(top[0] - wrist[0], top[2] - wrist[2])
        return wrist[1] + math.sqrt(max(full * full - flat * flat, 0.0)) - top[1]


def paw_at(legs, leg, t, name):
    """(ball, paw angle, toe angle, planted) for a leg at time t of a gait. In the stance the ball slides
    back under the body at the gait's speed and the wrist or hock peels up over the toes at the end; in
    the swing the paw folds back, lifts and reaches forward for the next touch-down."""
    g = GAITS[name]
    period, duty = g["period"], g["duty"]
    i = legs.info[leg]
    kind = i["kind"]
    swing = 1.0 - duty
    sweep = g["speed"] * period * duty
    centre = i["ball"] + Z * g["reach"][kind]
    phase = (t / period - g["mid"][leg] + swing / 2) % 1.0  # 0 at lift-off

    def stance(u):
        ball = centre + Z * sweep * (0.5 - u)
        peel = smooth(1.0 - HEEL_OFF, 1.0, u) ** 1.5
        return ball, PEEL[kind] * RAD * peel

    if phase >= swing:
        b, a = stance((phase - swing) / duty)
        return b, a, 0.0, True
    u = phase / swing
    b0, a0 = stance(1.0)
    b1, _ = stance(0.0)
    v = sweep * swing / duty
    z = hermite(b0[2], b1[2], -0.35 * v, -v, u)
    lift = LIFT[kind] * g["lift"]
    y = b0[1] + (b1[1] - b0[1]) * u + lift * math.sin(math.pi * u ** 0.85) ** 1.2
    x = b0[0] + i["out"] * 0.015 * math.sin(math.pi * u)
    fold = FOLD[kind] * RAD * math.sin(math.pi * min(u / 0.75, 1.0)) ** 1.5
    # Reaching for the touch-down the paw opens up again.
    reach = -8.0 * RAD * smooth(0.6, 0.95, u) * smooth(1.0, 0.97, u)
    angle = a0 * (1 - smooth(0.0, 0.3, u)) + fold + reach
    # The toes leave the ground last and come down flat: in between they turn with the paw, curling.
    toe = (angle + 15.0 * RAD) * smooth(0.0, 0.25, u) * smooth(1.0, 0.8, u)
    return np.array([x, y, z]), angle, toe, False


def girdles(legs, ts, name, sway):
    """How high the shoulders and hips ride each frame (m, from the gait's crouch) and how far each pair
    rolls: no higher than that, and low enough that the planted legs reach their paws (None: no paw of
    the pair down)."""
    low = GAITS[name]["low"]
    out = {}
    for girdle in "FH":
        left, right = "L" + girdle, "R" + girdle
        top = {s: legs.info[s]["top"] for s in (left, right)}
        width = top[left][0] - top[right][0]
        rise, roll = [], []
        for k, t in enumerate(ts):
            r = {}
            for s in (left, right):
                ball, angle, _, planted = paw_at(legs, s, t, name)
                if planted:
                    r[s] = legs.reach(s, ball, angle, top[s] + np.array([sway[k], -low, 0.0]))
            if len(r) == 2:
                tilt = max(min((r[left] - r[right]) / width, 3 * RAD), -3 * RAD)
                rise.append(min(r[left] - tilt * width / 2, r[right] + tilt * width / 2, 0.0))
                roll.append(tilt)
            elif len(r) == 1:
                rise.append(min(next(iter(r.values())), 0.0))
                roll.append(-2.0 * RAD if right in r else 2.0 * RAD)  # the swinging side sags
            else:
                rise.append(None)  # in the air
                roll.append(0.0)
        out[girdle] = (rise, roll)
    return out


def fill_flight(rise, period, frames):
    """Frames with no paw down on a girdle (galloping) ride a smooth arc between the frames either side."""
    n = len(rise)
    known = [k for k in range(n) if rise[k] is not None]
    if len(known) == n:
        return rise
    out = list(rise)
    for k in range(n):
        if out[k] is None:
            a = max((j for j in known if j < k), default=known[-1] - n)
            b = min((j for j in known if j > k), default=known[0] + n)
            u = (k - a) / (b - a)
            ra, rb = rise[a % n], rise[b % n]
            out[k] = ra + (rb - ra) * u + 0.06 * math.sin(math.pi * u)
    return out


# ---------------------------------------------------------------- the rest of her

def neck(pose, pitch, yaw, head_pitch=0.0, head_yaw=0.0):
    """Bends the neck: pitch (rad, + nose down) and yaw (+ to her left); the head turns on its own too."""
    pose.turn("neck", X, pitch)
    pose.turn("neck", Y, yaw)
    pose.turn("head", X, head_pitch)
    pose.turn("head", Y, head_yaw)


def tail(pose, t, period, amp, harmonic=1, lift=0.0, curl=0.0):
    """Swishes the tail (amp: degrees at the root, growing toward the tip, each bone lagging the one
    before), lifted (rad, + up) and its tip curled up (rad)."""
    for k, name in enumerate(TAIL_BONES):
        pose.turn(name, Y, amp * (0.5 + 0.35 * k) * RAD * wave(t, period, harmonic, 0.1 + 0.11 * k))
    # A +X turn lifts a bone running back and down (and the tuft running back).
    pose.turn(TAIL_BONES[0], X, lift)
    pose.turn(TAIL_BONES[-2], X, curl * 0.5)
    pose.turn(TAIL_BONES[-1], X, curl)


class Baker:
    def __init__(self, rig, names):
        self.rig = rig
        self.names = names
        self.pose = Pose(rig)
        self.legs = Legs(self.pose)
        self.clips = {}
        self.worst = {}

    def key(self):
        return {n: self.pose.local(n) for n in self.names}

    def torso(self, rise_f, rise_h, sway=0.0, roll_f=0.0, roll_h=0.0, yaw=0.0, flex=0.0, pitch=0.0, lift=0.0):
        """The body rides at the shoulders' and hips' heights (m from standing), pitched to fit them; the
        chest and pelvis roll on their own; `flex` arches the back (+, gathering the legs under it) or
        stretches it (-) about the body bone; `pitch` (+ nose down) tilts her as a whole about the hips."""
        p = self.pose
        zf = self.legs.info["LF"]["top"][2]
        zh = self.legs.info["LH"]["top"][2]
        zb = SPINE[1][2]
        slope = (rise_f - rise_h) / (zf - zh)
        p.move("body", (sway, rise_h + (zb - zh) * slope + lift, 0.0))
        p.turn("body", X, -math.atan(slope) + pitch)
        p.turn("body", Z, (roll_f + roll_h) / 2)
        p.turn("chest", Z, (roll_f - roll_h) / 2)
        p.turn("pelvis", Z, (roll_h - roll_f) / 2)
        p.turn("body", Y, yaw)
        # Arching: the chest tips nose down and the pelvis rump down (a +X turn lifts a bone running back).
        p.turn("chest", X, flex)
        p.turn("pelvis", X, -flex)

    def locomotion(self, name, kind_gait):
        gt = GAITS[kind_gait]
        speed, period = gt["speed"], gt["period"]
        frames = int(round(period * FPS))
        ts = [f / FPS for f in range(frames)]
        low = gt["low"]
        if kind_gait == "walk":
            sway = [0.018 * math.cos(2 * math.pi * (t / period - 0.55)) for t in ts]
        elif kind_gait == "sneak":
            sway = [0.012 * math.cos(2 * math.pi * (t / period - 0.55)) for t in ts]
        else:
            sway = [0.0 for t in ts]
        g = girdles(self.legs, ts, kind_gait, sway)
        ride = {}
        for girdle in "FH":
            raw = g[girdle][0]
            smooth_rise = lowpass(fill_flight(raw, period, frames), 5)
            # Smoothing must not lift a planted leg past its reach: drop the curve by its worst overshoot.
            over = max([a - b for a, b in zip(smooth_rise, raw) if b is not None] + [0.0])
            ride[girdle] = [x - over - low for x in smooth_rise]
        rf, rh = ride["F"], ride["H"]
        roll_f, roll_h = lowpass(g["F"][1], 2), lowpass(g["H"][1], 2)
        keys = []
        worst = 0.0
        for f, t in enumerate(ts):
            p = self.pose
            p.reset()
            if kind_gait == "run":
                # The back arches as the hind legs swing in under it (the gathered flight) and stretches
                # out as they push off (the extended flight).
                flex = 7.0 * RAD * math.cos(2 * math.pi * (t / period - 0.36))
                self.torso(rf[f], rh[f], flex=flex)
                head_bob = 5.0 * RAD * wave(t, period, 1, 0.1)
                neck(p, 4.0 * RAD + head_bob, 0.0, -head_bob * 0.8 - 4.0 * RAD)
                tail(p, t, period, 2.0, lift=-0.25 + 0.12 * wave(t, period, 1, 0.3), curl=0.5)
            elif kind_gait == "walk":
                self.torso(rf[f], rh[f], sway[f], -roll_f[f], -roll_h[f], yaw=-1.5 * RAD * wave(t, period, 1, 0.3))
                p.turn("chest", Y, 2.0 * RAD * wave(t, period, 1, 0.05))
                p.turn("pelvis", Y, -2.0 * RAD * wave(t, period, 1, -0.2))
                bob = wave(t, period, 2, 0.12)
                neck(p, 6.0 * RAD + 3.0 * RAD * bob, -2.0 * RAD * wave(t, period, 1, 0.55), -6.0 * RAD - 2.5 * RAD * bob)
                tail(p, t, period, 7.0, lift=0.05, curl=0.6)
            else:
                # Stalking: low and level, the shoulder blades rolling high over each fore step, the
                # head low, still and level with the prey.
                self.torso(rf[f], rh[f], sway[f], -roll_f[f] * 0.6, -roll_h[f] * 0.6, pitch=2.0 * RAD)
                p.turn("chest", Y, 1.5 * RAD * wave(t, period, 1, 0.05))
                neck(p, 14.0 * RAD + 1.0 * RAD * wave(t, period, 2, 0.1), 0.0, -18.0 * RAD - 1.0 * RAD * wave(t, period, 2, 0.1))
                tail(p, t, period, 2.0, lift=-0.18, curl=0.3 + 0.3 * wave(t, period / 2, 1))
            for leg in self.legs.info:
                ball, angle, toe, planted = paw_at(self.legs, leg, t, kind_gait)
                miss = self.legs.solve(leg, ball, angle, toe, 0.05 if kind_gait == "sneak" else 0.0)
                if planted:
                    worst = max(worst, miss)
            keys.append(self.key())
        keys.append(keys[0])
        self.clips[name] = keys
        self.worst[name] = worst
        lo, hi = min(min(rf), min(rh)), max(max(rf), max(rh))
        print(f"{name}: {frames} frames, {speed:.1f} m/s, stride {speed * period:.2f} m, shoulders/hips ride "
              f"{lo:+.3f}..{hi:+.3f} m, worst planted paw miss {worst * 100:.1f} cm")

    def stand(self, crouch=0.0, gather=0.0, spread=0.0):
        """Every paw where it stands (`gather` draws the hind paws forward, m)."""
        for leg, i in self.legs.info.items():
            ball = i["ball"].copy()
            if i["kind"] == "H":
                ball[2] += gather
            ball[0] += i["out"] * spread
            self.legs.solve(leg, ball, 0.0)

    def idle(self):
        T = 4.0
        frames = int(round(T * FPS))
        keys = []
        for f in range(frames):
            t = f / FPS
            p = self.pose
            p.reset()
            breathe = wave(t, T, 3, 0.1)
            self.torso(-0.004 + 0.005 * breathe, -0.006 + 0.004 * breathe, 0.012 * wave(t, T, 1, 0.1),
                       roll_f=-0.6 * RAD * wave(t, T, 1, 0.1), roll_h=-0.6 * RAD * wave(t, T, 1, 0.1))
            p.turn("chest", X, -0.8 * RAD * breathe)
            # A slow look round: out to her left, back, to her right, a glance down, home.
            u = t / T
            yaw = 22 * RAD * math.sin(2 * math.pi * u) * smooth(0.0, 0.1, u) * smooth(1.0, 0.85, u)
            pitch = 5 * RAD * max(math.sin(2 * math.pi * (2 * u - 0.15)), 0.0) ** 2
            neck(p, 4 * RAD + pitch, yaw * 0.6, -4 * RAD + 2 * RAD * wave(t, T, 2, 0.3), yaw * 0.4)
            p.turn("jaw", X, 2.0 * RAD * (1 + breathe))
            tail(p, t, T, 9.0, 2, lift=0.05, curl=0.7 + 0.3 * wave(t, T, 3, 0.2))
            self.stand()
            keys.append(self.key())
        keys.append(keys[0])
        self.clips["Idle"] = keys
        print(f"Idle: {frames} frames")

    def pounce(self):
        frames = int(round(POUNCE_TIME * FPS))
        keys = []
        for f in range(frames + 1):
            t = f / FPS
            p = self.pose
            p.reset()
            # Sinking back onto her haunches (0 .. crouch), the spring, the flight, the landing.
            crouch = smooth(0.0, 0.25, t) * smooth(POUNCE_LAUNCH + 0.08, POUNCE_LAUNCH - 0.02, t)
            air = smooth(POUNCE_LAUNCH - 0.04, POUNCE_LAUNCH + 0.1, t) * smooth(POUNCE_LAND + 0.02, POUNCE_LAND - 0.12, t)
            land = smooth(POUNCE_LAND - 0.06, POUNCE_LAND + 0.06, t) * smooth(POUNCE_TIME, POUNCE_LAND + 0.15, t)
            wiggle = math.sin(2 * math.pi * t / 0.14) * smooth(0.08, 0.2, t) * smooth(POUNCE_LAUNCH, POUNCE_LAUNCH - 0.08, t)
            # Crouched: the rump lowest, gathered over the hind paws; flying: stretched out, nose up a
            # little at the start of the arc and down onto the prey at its end; landing: the front takes
            # the blow.
            arc = (t - POUNCE_LAUNCH) / (POUNCE_LAND - POUNCE_LAUNCH)
            self.torso(-0.2 * crouch - 0.12 * land, -0.3 * crouch - 0.02 * land,
                       flex=7 * RAD * crouch - 10 * RAD * air + 4 * RAD * land,
                       pitch=(-10 * RAD + 22 * RAD * min(max(arc, 0.0), 1.0)) * air + 6 * RAD * land)
            p.turn("pelvis", Y, 7 * RAD * wiggle)
            neck(p, (16 * RAD) * crouch - 12 * RAD * air + 6 * RAD * land, 0.0,
                 -18 * RAD * crouch + 4 * RAD * air - 4 * RAD * land)
            p.turn("jaw", X, 28 * RAD * smooth(POUNCE_LAUNCH, POUNCE_LAND - 0.1, t) * smooth(POUNCE_TIME, POUNCE_LAND + 0.1, t))
            tail(p, t, 0.5, 4.0, lift=0.25 * crouch - 0.1 * air, curl=1.0 * crouch + 0.2)
            for leg, i in self.legs.info.items():
                stand = i["ball"].copy()
                if i["kind"] == "F":
                    # Reaching out ahead for the prey in the air, claws spread; down first on landing.
                    ball = stand + Z * (0.72 * air + 0.05 * crouch) + Y * (0.34 * air) + X * i["out"] * 0.06 * air
                    angle = -30 * RAD * air + 20 * RAD * crouch
                    toe = -25 * RAD * air
                else:
                    # Gathered under her crouching, they push off and trail out behind in the air, then
                    # swing back in under her as she lands.
                    ball = stand + Z * (0.14 * crouch - 0.62 * air + 0.05 * land) + Y * (0.24 * air)
                    angle = -10 * RAD * crouch + 70 * RAD * air
                    toe = 30 * RAD * air
                self.legs.solve(leg, ball, angle, toe)
            keys.append(self.key())
        self.clips["Pounce"] = keys
        print(f"Pounce: {frames} frames, springs at {POUNCE_LAUNCH:.2f} s, lands at {POUNCE_LAND:.2f} s")

    def strike(self):
        frames = int(round(STRIKE_TIME * FPS))
        keys = []
        for f in range(frames + 1):
            t = f / FPS
            p = self.pose
            p.reset()
            # Rocking back and rearing up off the fore paws, the swipe down, settling back.
            rear = smooth(0.0, STRIKE_HIT - 0.08, t) * smooth(STRIKE_HIT + 0.04, STRIKE_HIT - 0.04, t)
            lunge = smooth(STRIKE_HIT - 0.1, STRIKE_HIT, t) * smooth(STRIKE_TIME, STRIKE_HIT + 0.12, t)
            self.torso(0.06 * rear - 0.06 * lunge, -0.05 * rear - 0.02 * lunge, pitch=-12 * RAD * rear + 5 * RAD * lunge,
                       flex=-3 * RAD * rear + 3 * RAD * lunge, lift=0.0)
            p.turn("body", Z, -3 * RAD * rear)
            neck(p, -10 * RAD * rear + 14 * RAD * lunge, -6 * RAD * lunge, 6 * RAD * rear - 8 * RAD * lunge, -4 * RAD * lunge)
            p.turn("jaw", X, 30 * RAD * smooth(STRIKE_HIT - 0.15, STRIKE_HIT - 0.02, t) * smooth(STRIKE_TIME - 0.05, STRIKE_HIT + 0.12, t))
            tail(p, t, STRIKE_TIME, 6.0, lift=0.15 * rear, curl=0.6)
            for leg, i in self.legs.info.items():
                ball = i["ball"].copy()
                angle = 0.0
                toe = 0.0
                if leg == "RF":
                    # The right paw: up and cocked back by her chest, then a swipe down and out ahead.
                    up = smooth(0.02, STRIKE_HIT - 0.1, t) * smooth(STRIKE_HIT, STRIKE_HIT - 0.07, t)
                    swipe = smooth(STRIKE_HIT - 0.1, STRIKE_HIT, t) * smooth(STRIKE_TIME - 0.05, STRIKE_HIT + 0.1, t)
                    ball = ball + Y * (0.5 * up + 0.05 * swipe) + Z * (0.2 * up + 0.42 * swipe) + X * (0.06 * up)
                    angle = 85 * RAD * up - 35 * RAD * swipe
                    toe = -30 * RAD * (up + swipe)
                elif leg == "LF":
                    ball = ball + Y * (0.08 * rear) + Z * (0.05 * rear)
                    angle = 25 * RAD * rear
                elif i["kind"] == "H":
                    ball[2] += 0.06 * rear
                self.legs.solve(leg, ball, angle, toe)
            keys.append(self.key())
        self.clips["Strike"] = keys
        print(f"Strike: {frames} frames, the blow lands at {STRIKE_HIT:.2f} s")


# Pounce: the whole clip; when she springs and when she lands (the game flies her between them).
POUNCE_TIME = 1.2
POUNCE_LAUNCH = 0.38
POUNCE_LAND = 0.86
# Strike: the whole clip, and when the blow lands.
STRIKE_TIME = 0.72
STRIKE_HIT = 0.36


# ---------------------------------------------------------------- clips

def write_clips(js, binary, clips, names):
    """Every bone's rotation, the body's translation too, one key a frame."""
    js["animations"] = []
    idx = {n["name"]: i for i, n in enumerate(js["nodes"]) if "name" in n}
    for clip, keys in clips.items():
        times = np.arange(len(keys), dtype=np.float32) / FPS
        tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
        anim = {"name": clip, "channels": [], "samplers": []}
        for bone in names:
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
            if bone == "body":
                out = add_accessor(js, binary, np.array([k[bone][:3, 3] for k in keys]), "VEC3")
                anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
                anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "translation"}})
        js["animations"].append(anim)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    names = rebuild(js, binary)
    baker = Baker(Rig(js), names)
    for leg, i in sorted(baker.legs.info.items()):
        print(f"leg {leg}: " + " + ".join(f"{x:.3f}" for x in i["l"]) + " m")
    baker.idle()
    baker.locomotion("Walk", "walk")
    baker.locomotion("Run", "run")
    baker.locomotion("Sneak", "sneak")
    baker.pounce()
    baker.strike()
    write_clips(js, binary, baker.clips, names)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/rig_lioness.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(names)} bones, clips {list(baker.clips)}")
    if args.preview:
        render_preview(args.output, args.preview)


# ---------------------------------------------------------------- preview

def skinned(js, binary, clip=None, frame=0):
    """The mesh's vertices posed by a clip's frame (or the rest pose), its triangles and UVs."""
    nodes = js["nodes"]
    local = {i: trs(n) for i, n in enumerate(nodes)}
    if clip is not None:
        anim = next(a for a in js["animations"] if a["name"] == clip)
        for ch in anim["channels"]:
            vals = accessor(js, binary, anim["samplers"][ch["sampler"]]["output"]).astype(float)
            i = ch["target"]["node"]
            m = local[i].copy()
            if ch["target"]["path"] == "rotation":
                m[:3, :3] = quat_to_mat(vals[min(frame, len(vals) - 1)])
            else:
                m[:3, 3] = vals[min(frame, len(vals) - 1)]
            local[i] = m
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
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
    hom = np.concatenate([pos, np.ones((len(pos), 1))], 1)
    out = np.zeros((len(pos), 3))
    for k in range(4):
        out += weights[:, k:k + 1] * np.einsum("nij,nj->ni", mats[joints[:, k]], hom)[:, :3]
    idx = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    uv = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)
    nozzles = {n["name"]: w(i) for i, n in enumerate(nodes) if n.get("name", "").startswith("nozzle")}
    return out, idx, uv, nozzles


def render_preview(path, out_dir):
    """Rows of frames per clip, side-on and from an RTS camera's height; the walking clips travel at
    their speeds over a fixed grid (planted paws should stay put on it)."""
    import io
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    js, binary = read_glb(path)
    mat = js["materials"][0]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    tex = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((512, 512)), dtype=np.float32) / 255.0
    lengths = {a["name"]: int(accessor(js, binary, a["samplers"][0]["input"]).shape[0]) for a in js["animations"]}
    speeds = {"Walk": WALK_SPEED, "Run": RUN_SPEED, "Sneak": SNEAK_SPEED}
    views = {"side": (np.array([4.2, 0.9, 0.0]), np.array([0.0, 0.62, 0.0])),
             "rts": (np.array([3.4, 4.6, -3.4]), np.array([0.0, 0.5, 0.3]))}
    W, H = 300, 230
    for clip in [None] + [a["name"] for a in js["animations"]]:
        n = lengths.get(clip, 1)
        frames = [0] if clip is None else sorted(set(np.linspace(0, n - 1, 8).round().astype(int)))
        tiles = []
        for f in frames:
            pts, idx, uv, nozzles = skinned(js, binary, clip, f)
            travel = speeds.get(clip, 0.0) * f / FPS
            pts = pts + Z * travel
            for vname, (eye, target) in views.items():
                eye_t, target_t = eye + Z * travel, target + Z * travel
                img = np.ones((H, W, 3), np.float32) * np.array([0.6, 0.7, 0.8], np.float32)
                zb = np.full((H, W), np.inf, np.float32)
                rasterize(img, zb, pts, idx, uv, tex, eye_t, target_t)
                pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
                dr = ImageDraw.Draw(pil)
                for zk in np.arange(math.floor(travel - 4), travel + 4, 0.25):
                    seg = np.array([[-1.2, 0, zk], [1.2, 0, zk]])
                    sx, sy, cz = project(seg, eye_t, target_t, W, H)
                    if (cz > 0.1).all():
                        dr.line([(sx[0], sy[0]), (sx[1], sy[1])], fill=(70, 95, 70) if zk % 1 else (40, 60, 40))
                for nz in nozzles.values():
                    tip = nz[:3, 3] + Z * travel
                    s = np.array([tip, tip + nz[:3, :3] @ Y * 0.6])
                    sx, sy, cz = project(s, eye_t, target_t, W, H)
                    dr.line([(sx[0], sy[0]), (sx[1], sy[1])], fill=(255, 120, 0), width=2)
                dr.text((4, 4), f"{clip or 'rest'} {f}/{n - 1} {vname}", fill=(0, 0, 0))
                tiles.append(pil)
        cols = 2 * min(len(frames), 4)
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (W * cols, H * rows))
        for k, p in enumerate(tiles):
            sheet.paste(p, (W * (k % cols), H * (k // cols)))
        sheet.save(os.path.join(out_dir, f"{clip or 'rest'}.png"))
    print(f"preview in {out_dir}")


if __name__ == "__main__":
    main()
