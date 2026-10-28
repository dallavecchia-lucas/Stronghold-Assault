"""Rig and animate the Savanna Signal Scout (the giraffe). The Meshy export comes with an auto-rig
(SmartRigArmature) and no clips, standing square with its neck up. Its auto-rig is no good for
walking (the antennas on its back got bone chains, the neck has gaps in it), so this builds a new
skeleton along the giraffe and skins it with region-based weights like the War Elephant's: the four
legs (upper, lower and cannon bones: the cannon runs from the knee or hock down through the hoof),
the neck in three bones, the head, the tail and the torso in three blended along the body.

The gear stays on: what sits on the head (helmet, goggles) rides it rigidly, the plates and pouches
along the neck bend with it, everything on the back rides the torso where it sits. The radar dish
on its mast (the dish, its feed arm and strut) rides a `dish` bone of its own that turns it about
the mast, so it can sweep while the giraffe pings. The model is scaled to HEIGHT (to the tip of the
tallest antenna) with its origin in the middle of the four hooves.

Clips (FPS frames per second):
  Walk  a giraffe's walk, authored travelling at REF_SPEED (UnitTypes anim_ref_speed): a lateral
        sequence close to a pace, each fore leg swinging just after the hind one on its side, so the
        body rolls over the side on the ground. Inverse kinematics keeps each hoof planted while it
        is down; it rolls over its toe at the end of the stance and the cannon folds back under the
        knee (forelegs) or hock (hind legs) through the swing. The neck pumps forward and back with
        every step, the head staying level, and the tail swishes.
  Idle  standing square: breathing, slow weight shifts, the neck and head looking round the field
        (a scout keeping watch), the tail swishing.
  Ping  (not looped, PING_TIME long) the sonar ping: it stretches its neck up tall, the dish sweeps
        right round its mast and back, and the pulse goes out PING_RELEASE seconds in (the game sends
        it then); then it settles back down.

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_giraffe.py -- \\
      --input assets_src/units/savanna_signal_scout/savanna_signal_scout_rigged_meshy.glb \\
      --output game/assets/units/savanna_signal_scout/savanna_signal_scout_rigged.glb [--preview DIR]

--preview renders the rest pose, the walk travelling at REF_SPEED (side-on and from an RTS camera's
height), the ping and the idle into DIR as PNG frames.
"""
import argparse
import math
import os
import sys

import bpy
import bmesh  # after bpy: the bpy pip module only provides it once bpy is loaded
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_rigged_humanoid import shrink_textures  # noqa: E402
from rig_elephant import (Pose, _finish, _start, aim_frame, chain_weights, hermite, lowpass, mix,  # noqa: E402
                          parts, smooth, two_bone, wave)

FPS = 30
HEIGHT = 4.5  # meters, hooves to the tip of the tallest antenna, as for the static model

# Positions below are in the Meshy export as imported: front -Y, up +Z, the giraffe's left +X, hooves
# at z 0, 1.7 m to the antenna tip. The giraffe's midline is at x = MID_X. Model moves and scales the
# mesh into the game frame; place() does the same to a point.
MID_X = -0.103
# Left legs (the right ones mirror them about the midline), from the auto-rig's joints: shoulder,
# elbow, knee (the carpus), fetlock, and where the hoof stands; hip, stifle, hock, fetlock, hoof.
FORE_LEG = [(-0.030, -0.136, 0.794), (-0.030, -0.103, 0.574), (-0.035, -0.096, 0.309), (-0.026, -0.096, 0.043),
            (-0.026, -0.118, 0.0)]
HIND_LEG = [(-0.030, 0.329, 0.780), (-0.030, 0.322, 0.501), (-0.030, 0.388, 0.322), (-0.015, 0.375, 0.050),
            (-0.015, 0.358, 0.0)]
# The torso's spine (rump -> withers) and the neck from the withers up to the poll, then the head to
# the muzzle (along the middle of the neck's slices).
SPINE = [(0.42, 0.79), (0.14, 0.78), (-0.03, 0.80), (-0.13, 0.84)]  # (y, z): pelvis, body, chest
NECK = [(-0.13, 0.84), (-0.19, 1.00), (-0.25, 1.15), (-0.31, 1.31)]
HEAD_TIP = (-0.55, 1.28)
TAIL = [(0.43, 0.78), (0.455, 0.647), (0.445, 0.48), (0.435, 0.34), (0.43, 0.19)]
# Torso blends: chest -> body over BODY_Y[0..1], body -> pelvis over BODY_Y[2..3].
BODY_Y = (-0.02, 0.06, 0.2, 0.3)
# Gear: pieces mostly weighted to this auto-rig bone are the radar dish and its arm and strut.
DISH_BONE = "Bone_023"
# The dish's frame stands on a strut down the flank: up to DISH_FOOT[0] it stays with the body, from
# DISH_FOOT[1] up it turns with the dish, and bends in between.
DISH_FOOT = (0.86, 0.95)
# Head gear (helmet, goggles, earpieces) sits in front of HEAD_Y and above HEAD_Z.
HEAD_Y = -0.3
HEAD_Z = 1.22
# A piece of gear smaller than this (m, export frame) rides rigidly where it sits; bigger ones (the
# plates along the neck, straps round the body) bend with the skin under them.
RIGID_SIZE = 0.12


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


def mirror(p, side):
    return Vector((p[0] if side == "L" else 2 * MID_X - p[0], p[1], p[2]))


def mid(yz):
    return Vector((MID_X, yz[0], yz[1]))


# ---------------------------------------------------------------- load

class Model:
    """The export moved to its game frame: origin between the four hooves, HEIGHT tall, front -Y."""

    def __init__(self, path):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        junk = bpy.data.objects.get("Icosphere")  # stray helper mesh in the Meshy export
        if junk:
            bpy.data.objects.remove(junk, do_unlink=True)
        self.mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
        old = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
        mw = self.mesh.matrix_world.copy()
        self.mesh.parent = None
        self.mesh.matrix_world = mw
        for m in list(self.mesh.modifiers):
            self.mesh.modifiers.remove(m)
        bpy.data.objects.remove(old, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        self.mesh.select_set(True)
        bpy.context.view_layer.objects.active = self.mesh
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        co = np.array([v.co for v in self.mesh.data.vertices])
        lo, hi = co[:, 2].min(), co[:, 2].max()
        self.scale = HEIGHT / (hi - lo)
        hooves = [mirror(leg[4], s) for leg in (FORE_LEG, HIND_LEG) for s in "LR"]
        c = sum(hooves, Vector()) / 4
        self.shift = Vector((c.x, c.y, lo))

    def place(self, p) -> Vector:
        """A point in the export's frame, moved and scaled like the mesh."""
        return (Vector(p) - self.shift) * self.scale

    def move_mesh(self):
        me = self.mesh.data
        co = np.array([v.co for v in me.vertices])
        co = (co - np.array(self.shift)) * self.scale
        me.vertices.foreach_set("co", co.ravel())
        me.update()


def add_rings(mesh):
    """The legs are long tubes with few vertex rings: slice in more round each joint so they bend
    smoothly. Cuts only the faces inside each leg's column (export frame)."""
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    cuts = []
    for side in "LR":
        for leg in (FORE_LEG, HIND_LEG):
            c = mirror(leg[2], side)
            heights = [leg[k][2] + d for k in (1, 2, 3) for d in (-0.03, 0.0, 0.03)]
            cuts.append((c - Vector((0.07, 0.09, 0.4)), c + Vector((0.07, 0.09, 0.32)), heights))
    for lo, hi, heights in cuts:
        for z in heights:
            faces = [f for f in bm.faces if all(lo.x <= v.co.x <= hi.x and lo.y <= v.co.y <= hi.y
                                                and lo.z <= v.co.z <= hi.z for v in f.verts)]
            edges = {e for f in faces for e in f.edges}
            verts = {v for f in faces for v in f.verts}
            bmesh.ops.bisect_plane(bm, geom=list(verts) + list(edges) + faces,
                                   plane_co=(0, 0, z), plane_no=(0, 0, 1))
    bm.to_mesh(mesh.data)
    bm.free()
    mesh.data.update()


# ---------------------------------------------------------------- skinning (export frame)

LEG_NAMES = {"F": ("upperarm", "forearm", "forecannon"), "H": ("thigh", "shin", "hindcannon")}
NECK_BONES = ["neck_1", "neck_2", "neck_3"]
TAIL_BONES = ["tail_%d" % (i + 1) for i in range(len(TAIL) - 1)]


def leg_joints(kind, side):
    leg = FORE_LEG if kind == "F" else HIND_LEG
    return [mirror(leg[k], side) for k in (0, 1, 2, 4)]


def torso_weights(q):
    """The three torso bones, by where a point sits along the body; in front of the withers the
    neck and head take over (by where it projects onto the neck)."""
    y = q.y
    if y < BODY_Y[1]:
        w = mix({"chest": 1.0}, {"body": 1.0}, smooth(BODY_Y[0], BODY_Y[1], y))
    else:
        w = mix({"body": 1.0}, {"pelvis": 1.0}, smooth(BODY_Y[2], BODY_Y[3], y))
    if y < -0.04 and q.z > 0.72:
        joints = [mid(SPINE[2])] + [mid(p) for p in NECK] + [mid(HEAD_TIP)]
        nw, _ = chain_weights(q, joints, ["chest"] + NECK_BONES + ["head"], 0.045)
        w = mix(w, nw, smooth(-0.04, -0.12, y))
    return w


def body_weights(q):
    """Skin weights for a point on the giraffe (export frame)."""
    best = None
    for side in "LR":
        for kind in "FH":
            names = ["%s_%s" % (n, side) for n in LEG_NAMES[kind]]
            w, d = chain_weights(q, leg_joints(kind, side), names, 0.035)
            if best is None or d < best[1]:
                best = (w, d)
    # tail: the thin switch hanging off the rump down between the hocks, its tuft at the end; whatever
    # is nearer it than any leg
    if q.y > 0.38 and q.z < 0.8:
        w, d = chain_weights(q, [mid(p) for p in TAIL], TAIL_BONES, 0.03)
        if d < best[1] and d < 0.08:
            return mix(torso_weights(q), w, smooth(0.8, 0.7, q.z))
    # legs: the nearest leg below the belly is all leg; up on the shoulder and thigh its pull fades
    # into the torso so the skin there stretches as the leg swings.
    pull = smooth(0.13, 0.07, best[1]) * smooth(0.74, 0.54, q.z)
    if pull > 0.0:
        return mix(torso_weights(q), best[0], pull)
    return torso_weights(q)


def read_weights(mesh):
    names = {g.index: g.name for g in mesh.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups if g.weight > 0.0} for v in mesh.data.vertices]


def classify(mesh, co, pieces):
    """{piece index: "dish" | "head" | "rigid" | "skin"} for the gear (every piece but the body)."""
    old = read_weights(mesh)
    out = {}
    for k, p in enumerate(pieces[1:], 1):
        share = sum(old[i].get(DISH_BONE, 0.0) / max(sum(old[i].values()), 1e-6) for i in p) / len(p)
        c = co[p].mean(axis=0)
        size = (co[p].max(axis=0) - co[p].min(axis=0)).max()
        if share > 0.6 and c[0] > MID_X:
            out[k] = "dish"
        elif c[1] < HEAD_Y and c[2] > HEAD_Z:
            out[k] = "head"
        elif size < RIGID_SIZE:
            out[k] = "rigid"
        else:
            out[k] = "skin"
    return out


def dish_pivot(co, pieces, kinds):
    """The dish turns about the upright through the middle of its disc (the biggest piece of it), from
    where its frame leaves the strut (DISH_FOOT)."""
    disc = max((pieces[k] for k, kind in kinds.items() if kind == "dish"), key=len)
    c = co[disc].mean(axis=0)
    return Vector((c[0], c[1], DISH_FOOT[1]))


def skin_weights(mesh, co, pieces, kinds):
    """The giraffe's own skin by body_weights; the gear follows the torso, neck and head only (the
    straps and cables hanging down its flanks must not swing with the legs)."""
    weights = [None] * len(co)
    for i in pieces[0]:
        weights[i] = body_weights(Vector(co[i]))
    for k, kind in kinds.items():
        c = Vector(co[pieces[k]].mean(axis=0))
        if kind == "head":
            w = {"head": 1.0}
        elif kind == "rigid":
            w = torso_weights(c)
        for i in pieces[k]:
            q = Vector(co[i])
            if kind == "dish":
                weights[i] = mix(torso_weights(q), {"dish": 1.0}, smooth(DISH_FOOT[0], DISH_FOOT[1], q.z))
            else:
                weights[i] = torso_weights(q) if kind == "skin" else w
    counts = {kind: sum(len(pieces[k]) for k, x in kinds.items() if x == kind) for kind in ("dish", "head", "rigid", "skin")}
    print("gear vertices: " + ", ".join(f"{k} {n}" for k, n in counts.items()))
    return weights


def apply_weights(mesh, weights):
    """Writes the weights, the four strongest per vertex (glTF carries four influences)."""
    mesh.vertex_groups.clear()
    groups = {}
    for i, w in enumerate(weights):
        w = dict(sorted(w.items(), key=lambda kv: -kv[1])[:4])
        total = sum(w.values())
        for name, x in w.items():
            if x / total > 0.001:
                if name not in groups:
                    groups[name] = mesh.vertex_groups.new(name=name)
                groups[name].add([i], x / total, "REPLACE")


# ---------------------------------------------------------------- armature

def build_armature(model, pivot):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, parent, head, tail, connect=False):
        b = eb.new(name)
        b.head, b.tail = model.place(head), model.place(tail)
        b.align_roll(Vector((1, 0, 0)))  # every bone's Z axis toward the giraffe's left
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("body", None, mid(SPINE[1]), mid(SPINE[2]))
    bone("chest", "body", mid(SPINE[2]), mid(SPINE[3]), True)
    bone("pelvis", "body", mid(SPINE[1]), mid(SPINE[0]))
    parent = "chest"
    for i, name in enumerate(NECK_BONES):
        bone(name, parent, mid(NECK[i]), mid(NECK[i + 1]), True)
        parent = name
    bone("head", parent, mid(NECK[-1]), mid(HEAD_TIP), True)
    for i, name in enumerate(TAIL_BONES):
        bone(name, "pelvis" if i == 0 else TAIL_BONES[i - 1], mid(TAIL[i]), mid(TAIL[i + 1]), i > 0)
    for side in "LR":
        for kind, parent in (("F", "chest"), ("H", "pelvis")):
            j = leg_joints(kind, side)
            names = ["%s_%s" % (n, side) for n in LEG_NAMES[kind]]
            bone(names[0], parent, j[0], j[1])
            bone(names[1], names[0], j[1], j[2], True)
            bone(names[2], names[1], j[2], j[3], True)
    bone("dish", "body", pivot, pivot + Vector((0, 0, 0.1)))
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bind(mesh, arm):
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mesh.parent = arm


# ---------------------------------------------------------------- legs

X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
RAD = math.pi / 180
# A turn about +X carries back -> up -> front -> down: it pitches the nose down, lifts the tail and
# swings a hanging cannon back.

WALK_PERIOD = 1.0  # seconds per stride in the clip
REF_SPEED = 3.0  # ground speed the walk is authored for (m/s): UnitTypes anim_ref_speed
DUTY = 0.6  # share of the stride each hoof is on the ground
SWING = 1.0 - DUTY
SWEEP = REF_SPEED * WALK_PERIOD * DUTY  # how far a planted hoof travels back under the body
# Middle of each leg's swing as a share of the stride: a lateral sequence close to a pace, each fore
# leg just after the hind leg on its side.
SWING_MID = {"LH": 0.0, "LF": 0.09, "RH": 0.5, "RF": 0.59}
LIFT = {"F": 0.34, "H": 0.26}  # hoof clearance mid-swing (m)
FOLD = {"F": 92.0, "H": 58.0}  # how far the cannon folds back mid-swing (degrees)
ROLL = {"F": 22.0, "H": 18.0}  # how far it rolls over the toe by lift-off (degrees)
LEAN = 0.85  # how far the cannon leans along the leg on the ground (share of the leg's own lean)
HEEL_OFF = 0.3  # last share of the stance in which the hoof rolls over its toe
TOE = 0.12  # toe edge ahead of where the hoof stands (m)
STRAIGHT = 0.995  # how straight a leg on the ground may get (share of its full length)
IDLE_PERIOD = 6.0
PING_TIME = 2.2  # seconds: the whole ping clip
PING_RELEASE = 0.8  # seconds into it: the pulse goes out (UnitTypes ping_release)


class Legs:
    """Rest measurements of the four legs and the IK that poses them. A leg's top two bones reach
    for the knee (fore) or hock (hind) by 2-bone IK; the cannon hangs from there, pitched about X."""

    def __init__(self, pose):
        self.pose = pose
        self.info = {}
        for side in "LR":
            for kind in "FH":
                names = tuple("%s_%s" % (n, side) for n in LEG_NAMES[kind])
                a, k, w = (pose.rest[b].translation for b in names)
                self.info[side + kind] = {
                    "kind": kind, "bones": names,
                    "l1": (k - a).length, "l2": (w - k).length,
                    "wrist": w.copy(), "sole": pose.tail[names[2]].copy(), "top": a.copy(),
                    # elbows bend back, stifles forward
                    "pole": Vector((0, 1, 0)) if kind == "F" else Vector((0, -1, 0)),
                }

    def foot(self, leg, t):
        """(knee or hock target, cannon pitch) for a leg at time t in the walk."""
        i = self.info[leg]
        kind = i["kind"]
        phase = (t / WALK_PERIOD - SWING_MID[leg] + SWING / 2) % 1.0  # 0 at lift-off
        if phase >= SWING:
            return self._stance(i, (phase - SWING) / DUTY)
        u = phase / SWING
        w0, b0 = self._stance(i, 1.0)  # lift-off
        w1, b1 = self._stance(i, 0.0)  # touch-down
        v = SWEEP * SWING / DUTY
        y = hermite(w0.y, w1.y, 0.35 * v, v, u)
        z = (1 - u) * w0.z + u * w1.z + LIFT[kind] * math.sin(math.pi * u ** 0.85) ** 1.2
        x = w0.x + (0.04 if w0.x > 0 else -0.04) * math.sin(math.pi * u)  # swings out a little
        fold = math.radians(FOLD[kind]) * math.sin(math.pi * min(u / 0.8, 1.0)) ** 1.5
        pitch = b0 + (b1 - b0) * smooth(0.0, 1.0, u) + fold
        return Vector((x, y, z)), pitch

    def _stance(self, i, u):
        """Planted hoof u of the way through the stance: the cannon leans along the leg (from the hoof
        up to the shoulder or hip), and the hoof rolls over its toe at the end."""
        sole = i["sole"] + Vector((0, -SWEEP / 2 + SWEEP * u, 0))
        toe = sole + Vector((0, -TOE, 0))
        lean = math.atan2(i["top"].y - sole.y, i["top"].z - sole.z) - math.atan2(i["top"].y - i["sole"].y, i["top"].z - i["sole"].z)
        pitch = -LEAN * lean + math.radians(ROLL[i["kind"]]) * smooth(1 - HEEL_OFF, 1.0, u) ** 1.5
        w = toe + Matrix.Rotation(pitch, 3, "X") @ (i["wrist"] - i["sole"] + Vector((0, TOE, 0)))
        return w, pitch

    def solve(self, leg, wrist, pitch):
        """Poses the leg's three bones to put the knee or hock at `wrist`, the cannon pitched back."""
        i = self.info[leg]
        up, lo, ft = i["bones"]
        p = self.pose
        a = p.head(up)
        knee, end = two_bone(a, i["l1"], i["l2"], wrist, i["pole"])
        for name, h, t in ((up, a, knee), (lo, knee, end)):
            r = p.rest[name]
            rest_y = r.to_3x3() @ Vector((0, 1, 0))
            q = aim_frame((t - h).normalized(), i["pole"]) @ aim_frame(rest_y, i["pole"]).inverted()
            p.place(name, Matrix.Translation(h) @ (q @ r.to_3x3()).to_4x4())
        r = p.rest[ft]
        p.place(ft, Matrix.Translation(end) @ (Matrix.Rotation(pitch, 3, "X") @ r.to_3x3()).to_4x4())
        return (end - wrist).length

    def reach(self, leg, wrist, joint):
        """Highest the leg's top joint can be above `joint` (rest) and still reach `wrist`."""
        i = self.info[leg]
        full = (i["l1"] + i["l2"]) * STRAIGHT
        flat = Vector((joint.x - wrist.x, joint.y - wrist.y)).length
        return wrist.z + math.sqrt(max(full * full - flat * flat, 0.0)) - joint.z

    def stand(self):
        """Every leg on its rest stance."""
        for leg, info in self.info.items():
            self.solve(leg, info["wrist"], 0.0)


def girdles(legs, ts, sway):
    """How high the shoulders and hips ride each frame, and how much each pair rolls: as high as the
    planted legs allow when nearly straight, so the body vaults over them."""
    out = {}
    for girdle in "FH":
        left, right = "L" + girdle, "R" + girdle
        joint = {s: legs.pose.rest[legs.info[s]["bones"][0]].translation for s in (left, right)}
        width = joint[left].x - joint[right].x
        rise, roll = [], []
        for k, t in enumerate(ts):
            r = {}
            for s in (left, right):
                phase = (t / WALK_PERIOD - SWING_MID[s] + SWING / 2) % 1.0
                if not 0.3 * SWING < phase < 0.8 * SWING:
                    wrist, _ = legs.foot(s, t)
                    r[s] = legs.reach(s, wrist, joint[s] + Vector((sway[k], 0, 0)))
            if len(r) == 2:
                tilt = max(min((r[left] - r[right]) / width, 3 * RAD), -3 * RAD)
                rise.append(min(r[left] - tilt * width / 2, r[right] + tilt * width / 2))
                roll.append(tilt)
            else:
                rise.append(next(iter(r.values())))
                roll.append(-2.0 * RAD if right in r else 2.0 * RAD)  # the swinging side sags
        smooth_rise = lowpass(rise, 4)
        over = max(s - r for s, r in zip(smooth_rise, rise))
        out[girdle] = ([s - over - 0.01 for s in smooth_rise], lowpass(roll, 2))
    return out


# ---------------------------------------------------------------- clips

def deform_bones(arm):
    return [b.name for b in arm.data.bones]


def neck(pose, pitch, yaw, head_pitch=0.0):
    """Bends the neck: pitch (radians, nose down positive) and yaw (to its left positive) shared out
    along it, more at the base; the head pitches on its own too, and holds the yaw it was given."""
    for k, (name, share) in enumerate(zip(NECK_BONES, (0.45, 0.33, 0.22))):
        pose.turn(name, X, pitch * share)
        pose.turn(name, Z, yaw * share)
    pose.turn("head", X, head_pitch)


def tail(pose, t, period, amp, harmonic=1):
    for i, name in enumerate(TAIL_BONES):
        pose.turn(name, Y, amp * (0.6 + 0.4 * i) * RAD * wave(t, period, harmonic, 0.1 + 0.12 * i))


def bake_walk(arm, pose, legs):
    frames = int(round(WALK_PERIOD * FPS))
    ts = [f / FPS for f in range(frames + 1)]
    T = WALK_PERIOD
    # Weight rolls over the side whose legs are down (the left as the right pair swings, round 0.55).
    sway = [0.07 * math.cos(2 * math.pi * (t / T - 0.55)) for t in ts]
    g = girdles(legs, ts[:-1], sway[:-1])
    g = {k: (v[0] + v[0][:1], v[1] + v[1][:1]) for k, v in g.items()}  # close the loop
    y_front = pose.rest["upperarm_L"].translation.y
    y_hind = pose.rest["thigh_L"].translation.y
    y_body = pose.rest["body"].translation.y
    worst = 0.0
    names = deform_bones(arm)
    _start(arm, "Walk")
    for f, t in enumerate(ts):
        pose.reset()
        front, hind = g["F"][0][f], g["H"][0][f]
        slope = (hind - front) / (y_hind - y_front)
        pose.move("body", (sway[f], 0, front + (y_body - y_front) * slope))
        pose.turn("body", X, math.atan(slope))
        roll_f, roll_h = -g["F"][1][f], -g["H"][1][f]
        pose.turn("body", Y, (roll_f + roll_h) / 2)
        pose.turn("chest", Y, (roll_f - roll_h) / 2)
        pose.turn("pelvis", Y, (roll_h - roll_f) / 2)
        pose.turn("chest", Z, -1.5 * RAD * wave(t, T, 1, 0.05))
        pose.turn("pelvis", Z, -1.5 * RAD * wave(t, T, 1, -0.2))
        # The neck pumps forward and down as each fore leg reaches out, back as it plants; the head
        # counters it so the eyes stay level, and the neck swings a little against the body's roll.
        pump = wave(t, T, 2, 0.08)
        neck(pose, 4.5 * RAD * pump, -2.5 * RAD * wave(t, T, 1, 0.55), -3.5 * RAD * wave(t, T, 2, 0.14))
        tail(pose, t, T, 3.0)
        for leg in legs.info:
            wrist, pitch = legs.foot(leg, t)
            worst = max(worst, legs.solve(leg, wrist, pitch))
        pose.key(arm, f, names)
    _finish(arm)
    lo = min(min(g["F"][0]), min(g["H"][0]))
    hi = max(max(g["F"][0]), max(g["H"][0]))
    print(f"walk: {frames} frames, stride {REF_SPEED * WALK_PERIOD:.2f} m, sweep {SWEEP:.2f} m, "
          f"girdles ride {lo:+.3f}..{hi:+.3f} m, worst hoof miss {worst * 100:.1f} cm")


def look_round(t):
    """Idle: (neck yaw, neck pitch, head pitch) in radians, a slow look round the field: out to the
    left, back, out to the right, a glance down, and back to the front where it started."""
    u = t / IDLE_PERIOD
    yaw = 26 * RAD * math.sin(2 * math.pi * u) * smooth(0.0, 0.12, u) * smooth(1.0, 0.85, u)
    pitch = 6 * RAD * max(math.sin(2 * math.pi * (2 * u - 0.15)), 0.0) ** 2
    return yaw, pitch - 2 * RAD * wave(t, IDLE_PERIOD, 3), 3 * RAD * wave(t, IDLE_PERIOD, 2, 0.3)


def bake_idle(arm, pose, legs):
    frames = int(round(IDLE_PERIOD * FPS))
    T = IDLE_PERIOD
    names = deform_bones(arm)
    _start(arm, "Idle")
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        # Breathing, and a slow shift of weight from side to side.
        pose.move("body", (0.035 * wave(t, T, 1, 0.1), 0, -0.02 + 0.012 * wave(t, T, 3)))
        pose.turn("body", Y, -0.8 * RAD * wave(t, T, 1, 0.1))
        yaw, pitch, head = look_round(t)
        neck(pose, pitch, yaw, head)
        tail(pose, t, T, 4.0, 3)
        legs.stand()
        pose.key(arm, f, names)
    _finish(arm)
    print(f"idle: {frames} frames")


def bake_ping(arm, pose, legs):
    """The ping: the neck stretches up tall and the head lifts, the dish sweeps right round its mast
    and back (out to the left, across to the right, home), and it settles back down."""
    frames = int(round(PING_TIME * FPS))
    names = deform_bones(arm)
    _start(arm, "Ping")
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        up = smooth(0.0, 0.55, t) * smooth(PING_TIME, PING_TIME - 0.6, t)
        pose.move("body", (0, 0, -0.03 * up))
        pose.turn("body", X, -1.5 * RAD * up)  # rears a touch onto its hind legs
        # Straight up: the neck lifts (nose-down negative) and the head tips up to the sky, then a
        # small jolt as the pulse goes out.
        jolt = math.exp(-((t - PING_RELEASE) / 0.08) ** 2)
        neck(pose, -14 * RAD * up - 2.5 * RAD * jolt, 0.0, -12 * RAD * up + 3 * RAD * jolt)
        # The dish: out to the left (positive about Z), across to the right, back home.
        s = smooth(0.15, PING_TIME - 0.35, t)
        pose.turn("dish", Z, 70 * RAD * math.sin(2 * math.pi * s) * smooth(0.0, 0.2, s) * smooth(1.0, 0.8, s))
        tail(pose, t, PING_TIME, 3.0, 2)
        legs.stand()
        pose.key(arm, f, names)
    _finish(arm)
    print(f"ping: {frames} frames, the pulse at {PING_RELEASE:.2f} s")


# ---------------------------------------------------------------- preview

def render_preview(arm, out_dir):
    """The rest pose from round about; the walk travelling at REF_SPEED from the side and from an RTS
    camera's height (two strides, tracked by the camera); the ping; the idle every few frames."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"  # clay: easier to read the joints than the coat
    sc.display.shading.single_color = (0.82, 0.74, 0.6)
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 800, 600
    sc.render.image_settings.file_format = "PNG"
    ground = bpy.data.materials.new("ground")
    ground.diffuse_color = (0.4, 0.42, 0.3, 1)
    bpy.ops.mesh.primitive_plane_add(size=120, location=(0, -30, 0))
    bpy.context.object.data.materials.append(ground)
    for j in range(-70, 12):
        for x in (1.5, -1.5):
            bpy.ops.mesh.primitive_cube_add(size=0.08, location=(x, j * 0.5, 0.04))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 45

    def shoot(path, at, d, dist):
        cam.location = at + Vector(d).normalized() * dist
        cam.rotation_euler = (at - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)

    arm.animation_data_create()
    centre = Vector((0, 0, 2.1))
    for name, d in (("side", (1, 0, 0.1)), ("front", (0, -1, 0.15)), ("persp", (0.8, -0.9, 0.5))):
        shoot(os.path.join(out_dir, "rest_%s.png" % name), centre, d, 11.0)
    walk = int(round(WALK_PERIOD * FPS))
    arm.animation_data.action = bpy.data.actions["Walk"]
    for view, d, dist in (("side", (1, 0, 0.08), 8.0), ("rts", (0.6, -0.6, 1.0), 13.0)):
        for k in range(walk * 2):
            sc.frame_set(k % walk)
            y = -REF_SPEED * k / FPS
            arm.location = (0, y, 0)
            shoot(os.path.join(out_dir, "walk_%s_%04d.png" % (view, k)), Vector((0, y, 1.9)), d, dist)
    arm.location = (0, 0, 0)
    for clip, step, view, d, length in (("Ping", 3, "persp", (0.8, -0.7, 0.35), PING_TIME),
                                        ("Idle", 15, "persp", (0.8, -0.7, 0.35), IDLE_PERIOD)):
        arm.animation_data.action = bpy.data.actions[clip]
        for k in range(0, int(round(length * FPS)) + 1, step):
            sc.frame_set(k)
            shoot(os.path.join(out_dir, "%s_%s_%04d.png" % (clip.lower(), view, k)), centre, d, 11.0)
    arm.animation_data.action = None


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    model = Model(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    mesh = model.mesh
    add_rings(mesh)
    pieces = parts(mesh)
    co = np.array([v.co for v in mesh.data.vertices])
    kinds = classify(mesh, co, pieces)
    pivot = dish_pivot(co, pieces, kinds)
    weights = skin_weights(mesh, co, pieces, kinds)
    model.move_mesh()
    arm = build_armature(model, pivot)
    apply_weights(mesh, weights)
    bind(mesh, arm)
    pose = Pose(arm)
    legs = Legs(pose)
    for leg, i in sorted(legs.info.items()):
        print(f"leg {leg}: {i['l1']:.3f} + {i['l2']:.3f} m to the {'knee' if i['kind'] == 'F' else 'hock'}, "
              f"cannon {(i['sole'] - i['wrist']).length:.3f} m")
    bake_walk(arm, pose, legs)
    bake_idle(arm, pose, legs)
    bake_ping(arm, pose, legs)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    d = arm.data.bones["dish"].head_local
    print(f"exported {args.output}: scale {model.scale:.3f}, {len(arm.data.bones)} bones, "
          f"clips {[a.name for a in bpy.data.actions]}, dish pivot {tuple(round(x, 3) for x in d)}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
