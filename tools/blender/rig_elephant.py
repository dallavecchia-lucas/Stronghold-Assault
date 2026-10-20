"""Rig and animate the War Elephant. The Meshy export comes without a rig, so this builds one.

The mesh is scaled to the in-game height, its origin put in the middle of the four feet, and
skinned with region-based weights (legs, trunk, ears and tail as bone chains, the head and the
three torso bones blended along the body). Two looping clips are baked:

  Walk  a lateral-sequence walk like the Wolf Medic's (hind left, fore left, hind right, fore
        right, a quarter cycle apart). Inverse kinematics keeps each foot planted while it is
        on the ground. The body vaults over the straight legs (two dips per cycle) and rocks
        side to side, the head nods with every step, the ears flop, the tail swings, and the
        trunk swings from the base with follow-through down its length while its tip curls.
  Idle  breathing, weight shifts, a slow trunk sway and curl, ear flaps and tail swishes.

The equipment is skinned rigidly to bones the clips leave at rest and the game drives itself:
gun_L / gun_R (the flak cannons; they swing up at aircraft), launcher (the missile pods) and
radar (the dish). Marker bones carry no weights: gun_L_muzzle / gun_R_muzzle at the barrel tips
and tube_1..tube_8 at the mouth of each missile tube, pointing along it.

Run headless:
  blender -b --python tools/blender/rig_elephant.py -- \\
      --input assets_src/units/war_elephant_sentinel/war_elephant_sentinel_meshy.glb \\
      --output game/assets/units/war_elephant_sentinel/war_elephant_sentinel_rigged.glb \\
      [--preview DIR]

--preview renders the walk travelling at REF_SPEED and the idle into DIR (PNG frames).
"""
import argparse
import math
import os
import sys

import bpy
import bmesh  # after bpy: the bpy pip module only provides it once bpy is loaded
import numpy as np
from mathutils import Matrix, Quaternion, Vector

FPS = 30
HEIGHT = 3.8  # meters, as for the static model

# All positions below are in the static model's frame (process_meshy_model.py --height 3.8
# --pivot bbox): front -Y, up +Z, the elephant's left +X, front feet at y ~0, hind feet at
# y ~2.36. load() moves the model so the middle of the four feet is at the origin; P() shifts
# a position the same way.

# Bone chains: joints from the root down.
TRUNK = [(0, -1.62, 1.52), (0, -1.62, 1.25), (0, -1.62, 1.00), (0, -1.61, 0.76),
         (0, -1.58, 0.56), (0, -1.49, 0.42), (0, -1.36, 0.36), (0, -1.21, 0.37)]
TAIL = [(0, 2.70, 2.00), (0, 2.80, 1.62), (0, 2.82, 1.25), (0, 2.78, 0.92)]
# shoulder (the scapula swings too, so the pivot sits high), elbow, wrist, sole
FRONT_LEG = [(0.44, -0.12, 1.85), (0.44, -0.07, 0.98), (0.43, -0.04, 0.36), (0.43, -0.02, 0.0)]
# hip, knee, ankle, sole
HIND_LEG = [(0.37, 2.18, 1.85), (0.37, 2.25, 0.98), (0.36, 2.31, 0.36), (0.36, 2.35, 0.0)]
# Ear flap: the line it hinges on (bottom, top) and a point out on the flap.
EAR_HINGE = [(0.43, -0.86, 1.72), (0.46, -0.72, 2.66)]
EAR_TIP = (0.90, -0.28, 2.35)
GUN_PIVOT = (1.22, 0.10, 1.93)
GUN_MUZZLE = (1.22, -2.88, 1.93)
# The missile pods hinge at the back of their cradle.
LAUNCHER_PIVOT = (0, 2.35, 2.62)

# Torso: chest in front, pelvis behind, body (the root) between them.
BODY_Y = (0.2, 0.7, 1.6, 2.1)  # chest -> body blend, body -> pelvis blend
NECK_Y = (-0.25, -0.5, -0.6, -0.85)  # chest -> neck blend, neck -> head blend


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


SHIFT = Vector()


def P(p) -> Vector:
    """A position in the static model's frame, moved like the mesh."""
    return Vector(p) - SHIFT


def mirror(p, side):
    return (p[0] if side == "L" else -p[0], p[1], p[2])


# ---------------------------------------------------------------- mesh

def load(path):
    """Imports the Meshy export and puts it in the static model's frame, then moves it so the
    middle of the four feet is at the origin (the unit turns about its middle, not its front
    legs; the gun barrels make the bounding box run far ahead of the body)."""
    global SHIFT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = np.array([v.co for v in mesh.data.vertices])
    lo, hi = co.min(axis=0), co.max(axis=0)
    scale = HEIGHT / (hi[2] - lo[2])
    co = (co - [(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, lo[2]]) * scale
    feet = co[co[:, 2] < 0.15]
    mid_y = (feet[:, 1].min() + feet[:, 1].max()) * 0.5
    centres = [feet[(np.sign(feet[:, 0]) == sx) & ((feet[:, 1] < mid_y) == front)].mean(axis=0)
               for sx in (1, -1) for front in (True, False)]
    c = np.mean(centres, axis=0)
    SHIFT = Vector((c[0], c[1], 0.0))
    co -= [c[0], c[1], 0.0]
    mesh.data.vertices.foreach_set("co", co.ravel())
    mesh.data.update()
    return mesh


def add_rings(mesh):
    """The trunk and legs are long tubes with few vertex rings; slice in more so they bend
    smoothly. Cuts only faces inside each region."""
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    trunk_lo, trunk_hi = P((-0.24, -1.9, 0.3)), P((0.24, -1.35, 1.62))
    cuts = [(trunk_lo, trunk_hi, [1.40, 1.12, 0.88, 0.64])]
    for side in "LR":
        for leg in (FRONT_LEG, HIND_LEG):
            c = P(mirror(leg[2], side))
            cuts.append((c - Vector((0.42, 0.42, 1.0)), c + Vector((0.42, 0.42, 0.62)),
                         [0.16, 0.28, 0.46, 0.62, 0.78, 0.9]))
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


def parts(mesh):
    """Connected pieces, counting vertices at the same spot as joined (the export splits the
    mesh along its UV seams). Largest first: the animal itself, then the equipment."""
    n = len(mesh.data.vertices)
    root = list(range(n))

    def find(a):
        while root[a] != a:
            root[a] = root[root[a]]
            a = root[a]
        return a

    def join(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            root[ra] = rb

    seen = {}
    for v in mesh.data.vertices:
        k = tuple(round(c * 1e4) for c in v.co)
        if k in seen:
            join(v.index, seen[k])
        else:
            seen[k] = v.index
    for e in mesh.data.edges:
        join(e.vertices[0], e.vertices[1])
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return sorted(groups.values(), key=len, reverse=True)


def classify(mesh, piece):
    co = [mesh.data.vertices[i].co for i in piece]
    lo = Vector([min(c[k] for c in co) for k in range(3)])
    hi = Vector([max(c[k] for c in co) for k in range(3)])
    c = (lo + hi) * 0.5 + SHIFT  # static model frame
    if abs(c.x) > 1.02 and 1.3 < c.z < 2.25 and c.y < 0.9:
        return "gun_L" if c.x > 0 else "gun_R"
    if lo.z > 2.4 and c.y > 0.75 and abs(c.x) > 0.45:
        return "launcher"
    if lo.z > 2.95 and abs(c.y) < 0.6 and abs(c.x) < 0.5:
        return "radar"
    return "gear"


# ---------------------------------------------------------------- armature

def tubes(mesh, pieces):
    """The eight missile tubes: [(mouth, direction)], left pod first, top row first. Each
    tube is one long box; its axis is the box's long side, its mouth the front end."""
    out = []
    for piece, kind in pieces:
        if kind != "launcher":
            continue
        co = np.array([mesh.data.vertices[i].co for i in piece])
        size = co.max(axis=0) - co.min(axis=0)
        if size[1] < 1.2:
            continue  # cradle and straps
        c = co.mean(axis=0)
        _, _, vt = np.linalg.svd(co - c)
        d = Vector(vt[0]).normalized()
        if d.y > 0:
            d = -d  # point forward (-Y) and up
        t = (co - c) @ np.array(d)
        out.append((Vector(c) + d * float(t.max()), d))
    out.sort(key=lambda m: (m[0].x < 0, -round(m[0].z, 1), -abs(m[0].x)))
    return out


def radar_axis(mesh, pieces):
    """The dish turns about the middle of the post it sits on."""
    co = np.array([mesh.data.vertices[i].co for piece, kind in pieces if kind == "radar" for i in piece])
    lo, hi = co.min(axis=0), co.max(axis=0)
    mid = (lo + hi) * 0.5
    for piece, kind in pieces:
        post = np.array([mesh.data.vertices[i].co for i in piece])
        plo, phi = post.min(axis=0), post.max(axis=0)
        if kind == "gear" and abs(phi[2] - lo[2]) < 0.15 and (plo[:2] < mid[:2]).all() and (mid[:2] < phi[:2]).all():
            return Vector(((plo[0] + phi[0]) * 0.5, (plo[1] + phi[1]) * 0.5, lo[2]))
    return Vector((mid[0], mid[1], lo[2]))


def build_armature(mesh, pieces):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, parent, head, tail, connect=False, deform=True):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        b.use_deform = deform
        return b

    bone("body", None, P((0, 1.17, 1.80)), P((0, 0.45, 1.85)))
    bone("chest", "body", P((0, 0.45, 1.85)), P((0, -0.25, 2.05)), True)
    bone("neck", "chest", P((0, -0.25, 2.05)), P((0, -0.65, 2.25)), True)
    bone("head", "neck", P((0, -0.65, 2.25)), P((0, -1.45, 2.15)), True)
    bone("pelvis", "body", P((0, 1.17, 1.80)), P((0, 2.25, 1.95)))
    for i in range(len(TRUNK) - 1):
        bone("trunk_%d" % (i + 1), "head" if i == 0 else "trunk_%d" % i, P(TRUNK[i]), P(TRUNK[i + 1]), i > 0)
    for i in range(len(TAIL) - 1):
        bone("tail_%d" % (i + 1), "pelvis" if i == 0 else "tail_%d" % i, P(TAIL[i]), P(TAIL[i + 1]), i > 0)
    for side in "LR":
        hinge = P(mirror(EAR_HINGE[0], side)).lerp(P(mirror(EAR_HINGE[1], side)), 0.5)
        bone("ear_" + side, "head", hinge, P(mirror(EAR_TIP, side)))
        for names, leg, parent in ((("upperarm", "forearm", "forefoot"), FRONT_LEG, "chest"),
                                   (("thigh", "shin", "hindfoot"), HIND_LEG, "pelvis")):
            j = [P(mirror(p, side)) for p in leg]
            bone("%s_%s" % (names[0], side), parent, j[0], j[1])
            bone("%s_%s" % (names[1], side), "%s_%s" % (names[0], side), j[1], j[2], True)
            bone("%s_%s" % (names[2], side), "%s_%s" % (names[1], side), j[2], j[3], True)
        pivot = P(mirror(GUN_PIVOT, side))
        bone("gun_" + side, "chest", pivot, pivot + Vector((0, -0.5, 0)))
        muzzle = P(mirror(GUN_MUZZLE, side))
        bone("gun_%s_muzzle" % side, "gun_" + side, muzzle, muzzle + Vector((0, -0.3, 0)), deform=False)
    marks = tubes(mesh, pieces)
    pivot = P(LAUNCHER_PIVOT)
    bone("launcher", "body", pivot, pivot + marks[0][1] * 0.5)
    for i, (mouth, d) in enumerate(marks):
        bone("tube_%d" % (i + 1), "launcher", mouth, mouth + d * 0.3, deform=False)
    axis = radar_axis(mesh, pieces)
    bone("radar", "body", axis, axis + Vector((0, 0, 0.4)))
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm, len(marks)


# ---------------------------------------------------------------- skinning

def smooth(e0, e1, x):
    """0 at e0, 1 at e1, smooth in between (either direction)."""
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def chain_weights(p, joints, names, blend):
    """Weights along a chain of bones (joints[i] -> joints[i+1] is names[i]) for a point,
    from where it projects onto the chain: 1 inside a bone, blending into the next one over
    `blend` meters either side of each joint."""
    best = None
    s0 = 0.0
    for i in range(len(joints) - 1):
        a, b = joints[i], joints[i + 1]
        ab = b - a
        t = min(max((p - a).dot(ab) / ab.length_squared, 0.0), 1.0)
        d = (a + ab * t - p).length
        if best is None or d < best[0]:
            best = (d, s0 + ab.length * t)
        s0 += ab.length
    s = best[1]
    w = {}
    s0 = 0.0
    lengths = [(joints[i + 1] - joints[i]).length for i in range(len(joints) - 1)]
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
    """Head, neck and the three torso bones, by position along the body (static frame)."""
    y = q.y
    if y < BODY_Y[1]:
        w = mix({"chest": 1.0}, {"body": 1.0}, smooth(BODY_Y[0], BODY_Y[1], y))
    else:
        w = mix({"body": 1.0}, {"pelvis": 1.0}, smooth(BODY_Y[2], BODY_Y[3], y))
    if y < NECK_Y[0] and (q.z > 1.45 or y < -0.75):
        neck = mix({"neck": 1.0}, {"head": 1.0}, smooth(NECK_Y[2], NECK_Y[3], y))
        w = mix(w, neck, smooth(NECK_Y[0], NECK_Y[1], y))
    return w


def ear_weights(q, side):
    """Weight of the ear flap bone for a point (static frame), 0 if it isn't on the flap."""
    s = 1 if side == "L" else -1
    lo, hi = Vector(mirror(EAR_HINGE[0], side)), Vector(mirror(EAR_HINGE[1], side))
    if not (1.6 < q.z < 3.0 and q.y < 0.2 and q.x * s > 0.47):
        return 0.0
    along = Vector((0.61 * s, 0.79, 0.0))  # the flap sweeps back and out from its hinge
    normal = Vector((0.79 * s, -0.61, 0.0))
    h = lo.lerp(hi, min(max((q.z - lo.z) / (hi.z - lo.z), 0.0), 1.0))
    u = (q - h).dot(along)
    v = (q - h).dot(normal)
    if u < 0.0 or abs(v) > 0.16:
        return 0.0
    return smooth(0.04, 0.28, u)


def body_weights(q):
    """Skin weights for a point on the animal (static frame)."""
    for side in "LR":
        we = ear_weights(q, side)
        if we > 0.0:
            return mix(torso_weights(q), {"ear_" + side: 1.0}, we)
    # trunk (the tusks beside its root belong to the head)
    if abs(q.x) < 0.215 and q.y < -1.36 and q.z < 1.6:
        joints = [Vector(j) for j in TRUNK]
        names = ["trunk_%d" % (i + 1) for i in range(len(TRUNK) - 1)]
        w, _ = chain_weights(q, joints, names, 0.1)
        return mix(torso_weights(q), w, smooth(1.62, 1.42, q.z))
    # tail
    if q.y > 2.6 and abs(q.x) < 0.17 and q.z < 2.02:
        joints = [Vector(j) for j in TAIL]
        names = ["tail_%d" % (i + 1) for i in range(len(TAIL) - 1)]
        w, d = chain_weights(q, joints, names, 0.12)
        if d < 0.16:
            return mix(torso_weights(q), w, smooth(2.62, 2.74, q.y) * smooth(2.05, 1.85, q.z))
    # legs: the column below the belly (radius ~0.3 m) is all leg. Above it, and on the belly
    # and flanks around the leg's top, the leg's pull fades out gradually so the skin there
    # stretches as the leg swings instead of folding over.
    for side in "LR":
        for names, leg in ((("upperarm", "forearm", "forefoot"), FRONT_LEG),
                           (("thigh", "shin", "hindfoot"), HIND_LEG)):
            d = (q.xy - Vector(mirror(leg[2], side)).xy).length
            pull = smooth(0.62, 0.32, d) * smooth(1.5, 0.75, q.z)
            if pull > 0.0:
                joints = [Vector(mirror(p, side)) for p in leg]
                w, _ = chain_weights(q, joints, ["%s_%s" % (n, side) for n in names], 0.14)
                return mix(torso_weights(q), w, pull)
    return torso_weights(q)


def skin(mesh, arm, pieces):
    weights = [None] * len(mesh.data.vertices)
    body_piece = pieces[0][0]
    for i in body_piece:
        weights[i] = body_weights(mesh.data.vertices[i].co + SHIFT)
    for piece, kind in pieces[1:]:
        if kind == "gear":
            # Rigid: the whole piece follows the torso or head where it sits.
            c = sum((mesh.data.vertices[i].co for i in piece), Vector()) / len(piece) + SHIFT
            w = torso_weights(c)
        else:
            w = {kind: 1.0}
        for i in piece:
            weights[i] = w
    groups = {}
    for i, w in enumerate(weights):
        total = sum(w.values())
        for name, x in w.items():
            if x / total > 0.001:
                if name not in groups:
                    groups[name] = mesh.vertex_groups.new(name=name)
                groups[name].add([i], x / total, "REPLACE")
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mesh.parent = arm
    return weights


# ---------------------------------------------------------------- posing

class Pose:
    """Bone poses for one frame. Bones are posed either by a local rotation (FK) or by where
    they should end up in armature space (IK); world() is armature space."""

    def __init__(self, arm):
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        self.tail = {b.name: b.tail_local.copy() for b in arm.data.bones}
        self.parent = {b.name: b.parent.name if b.parent else None for b in arm.data.bones}
        self.basis = {}
        self._world = {}

    def reset(self):
        self.basis = {}
        self._world = {}

    def _carried(self, name):
        """Where the bone sits with no pose of its own: its rest pose carried by its parent."""
        p = self.parent[name]
        if p is None:
            return self.rest[name]
        return self.world(p) @ self.rest[p].inverted() @ self.rest[name]

    def world(self, name):
        if name not in self._world:
            self._world[name] = self._carried(name) @ self.basis.get(name, Matrix.Identity(4))
        return self._world[name]

    def turn(self, name, axis, angle):
        """Adds a rotation about an armature axis (as the bone lies at rest) at the bone's head."""
        local = (self.rest[name].to_3x3().inverted() @ Vector(axis)).normalized()
        q = Quaternion(local, angle)
        b = self.basis.get(name, Matrix.Identity(4))
        self.basis[name] = Matrix.Translation(b.translation) @ (q.to_matrix().to_4x4() @ b.to_3x3().to_4x4())
        self._world = {}

    def move(self, name, offset):
        """Moves a root bone by an armature-space offset."""
        b = self.basis.get(name, Matrix.Identity(4))
        local = self.rest[name].to_3x3().inverted() @ Vector(offset)
        self.basis[name] = Matrix.Translation(b.translation + local) @ b.to_3x3().to_4x4()
        self._world = {}

    def place(self, name, m):
        """Poses the bone so it ends up at armature-space matrix m."""
        self.basis[name] = self._carried(name).inverted() @ m
        self._world = {}

    def head(self, name):
        return self.world(name).translation.copy()

    def key(self, arm, frame, names):
        for name in names:
            b = self.basis.get(name, Matrix.Identity(4))
            pb = arm.pose.bones[name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = b.to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if self.parent[name] is None:
                pb.location = b.translation
                pb.keyframe_insert("location", frame=frame)


def aim_frame(y, pole):
    """Rotation whose Y axis is y and whose Z axis leans toward pole."""
    z = (pole - y * pole.dot(y)).normalized()
    return Matrix((y.cross(z), y, z)).transposed()


def two_bone(a, l1, l2, target, pole):
    """2-bone IK: (knee, end) for a chain of lengths l1, l2 from a toward target, the knee
    bending toward pole. end is target unless it is out of reach."""
    d = target - a
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = d.normalized()
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    side = (pole - dn * pole.dot(dn)).normalized()
    knee = a + (dn * cos_a + side * math.sqrt(max(0.0, 1 - cos_a * cos_a))) * l1
    return knee, a + dn * dist


# ---------------------------------------------------------------- animation

WALK_PERIOD = 1.0  # seconds per cycle in the clip
REF_SPEED = 2.2  # ground speed the walk is authored for (m/s): UnitTypes anim_ref_speed
DUTY = 0.6  # share of the cycle each foot is on the ground
SWING = 1.0 - DUTY
SWEEP = REF_SPEED * WALK_PERIOD * DUTY  # how far a planted foot travels back under the body
# Middle of each leg's swing as a share of the cycle: a lateral-sequence walk, a quarter apart.
SWING_MID = {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75}
LEGS = {
    "LF": ("upperarm_L", "forearm_L", "forefoot_L"),
    "RF": ("upperarm_R", "forearm_R", "forefoot_R"),
    "LH": ("thigh_L", "shin_L", "hindfoot_L"),
    "RH": ("thigh_R", "shin_R", "hindfoot_R"),
}
LIFT = {"F": 0.25, "H": 0.2}  # foot clearance at mid-swing (m)
FLEX = {"F": 55.0, "H": 35.0}  # how far the foot folds back mid-swing (degrees)
HEEL_OFF = 0.3  # last share of the stance in which the heel peels off, rolling over the toe
HEEL_ANGLE = {"F": 24.0, "H": 18.0}
TOE = 0.2  # toe edge ahead of the sole's centre (m)
STRAIGHT = 0.992  # how straight a leg in stance may get (share of its full length)
IDLE_PERIOD = 4.0


def wave(t, period, harmonic=1, phase=0.0):
    return math.sin(2 * math.pi * (harmonic * t / period - phase))


def lowpass(values, harmonics):
    """Keeps the first few harmonics of one loop of samples (stays seamless)."""
    f = np.fft.rfft(np.array(values))
    f[harmonics + 1:] = 0
    return list(np.fft.irfft(f, len(values)))


def hermite(p0, p1, m0, m1, u):
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1


class Legs:
    """Rest measurements of the four legs and the IK that poses them."""

    def __init__(self, pose):
        self.pose = pose
        self.info = {}
        for leg, (up, lo, ft) in LEGS.items():
            a, k, w = (pose.rest[b].translation for b in (up, lo, ft))
            self.info[leg] = {
                "kind": leg[1], "bones": (up, lo, ft),
                "l1": (k - a).length, "l2": (w - k).length,
                "wrist": w.copy(), "sole": pose.tail[ft].copy(),
                # elbows bend back, knees forward
                "pole": Vector((0, 1, 0)) if leg[1] == "F" else Vector((0, -1, 0)),
            }

    def foot(self, leg, t):
        """(wrist target, foot pitch) for a leg at time t in the walk."""
        i = self.info[leg]
        kind = i["kind"]
        phase = (t / WALK_PERIOD - SWING_MID[leg] + SWING / 2) % 1.0  # 0 at lift-off
        if phase >= SWING:
            return self._stance(i, (phase - SWING) / DUTY)
        u = phase / SWING
        w0, b0 = self._stance(i, 1.0)  # lift-off
        w1, _ = self._stance(i, 0.0)  # touch-down
        v = SWEEP * SWING / DUTY  # the ground's travel during the swing, in the same units
        # Leaves the ground easing out of the backward drift, lands moving with the ground.
        y = hermite(w0.y, w1.y, 0.35 * v, v, u)
        z = (1 - u) * w0.z + u * w1.z + LIFT[kind] * math.sin(math.pi * u ** 0.85) ** 1.2
        x = w0.x + (0.035 if w0.x > 0 else -0.035) * math.sin(math.pi * u)  # swings out a little
        fold = math.radians(FLEX[kind]) * math.sin(math.pi * min(u / 0.8, 1.0)) ** 1.5
        pitch = b0 * (1 - smooth(0.0, 0.25, u)) + fold
        return Vector((x, y, z)), pitch

    def _stance(self, i, u):
        """Planted foot u of the way through the stance: rolls over its toe at the end."""
        sole = i["sole"] + Vector((0, -SWEEP / 2 + SWEEP * u, 0))
        toe = sole + Vector((0, -TOE, 0))
        pitch = math.radians(HEEL_ANGLE[i["kind"]]) * smooth(1 - HEEL_OFF, 1.0, u) ** 1.5
        w = toe + Matrix.Rotation(pitch, 3, "X") @ (i["wrist"] - i["sole"] + Vector((0, TOE, 0)))
        return w, pitch

    def solve(self, leg, wrist, pitch):
        """Poses the leg's three bones to put the wrist at `wrist`, the foot pitched back."""
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


TRUNK_BONES = ["trunk_%d" % (i + 1) for i in range(len(TRUNK) - 1)]
TAIL_BONES = ["tail_%d" % (i + 1) for i in range(len(TAIL) - 1)]
ANIMATED = ["body", "chest", "pelvis", "neck", "head", "ear_L", "ear_R"] + TRUNK_BONES + TAIL_BONES + \
    [b for bones in LEGS.values() for b in bones]
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
RAD = math.pi / 180


def flap(pose, side, angle):
    """Opens an ear flap by `angle` (radians) about its hinge."""
    lo, hi = P(mirror(EAR_HINGE[0], side)), P(mirror(EAR_HINGE[1], side))
    pose.turn("ear_" + side, hi - lo, -angle if side == "L" else angle)


def trunk(pose, sway, swing, curl):
    """Trunk pose. sway(i), swing(i), curl(i) give each segment's angle (radians): sideways,
    forward/back, and curling the tip in toward the mouth (positive) or out."""
    for i, name in enumerate(TRUNK_BONES):
        pose.turn(name, Y, sway(i))
        pose.turn(name, X, swing(i) + curl(i))


def girdles(legs, ts, sway):
    """How high the shoulders and hips ride each frame, and how much each pair rolls: as high
    as the planted legs allow when nearly straight, so the body vaults over them. A foot
    just off the ground, or about to land, has to be reachable too."""
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
                # The swinging side sags a little.
                roll.append(-1.5 * RAD if right in r else 1.5 * RAD)
        smooth_rise = lowpass(rise, 4)
        over = max(s - r for s, r in zip(smooth_rise, rise))
        out[girdle] = ([s - over - 0.01 for s in smooth_rise], lowpass(roll, 2))
    return out


def bake_walk(arm, pose, legs):
    frames = int(round(WALK_PERIOD * FPS))
    ts = [f / FPS for f in range(frames + 1)]
    T = WALK_PERIOD
    # Weight shifts over the side whose feet are down (left around 0.625, when the right
    # legs swing), and the shoulders and hips turn with each leg reaching forward.
    sway = [0.055 * math.cos(2 * math.pi * (t / T - 0.625)) for t in ts]
    g = girdles(legs, ts[:-1], sway[:-1])
    g = {k: (v[0] + v[0][:1], v[1] + v[1][:1]) for k, v in g.items()}  # close the loop
    y_front = pose.rest["upperarm_L"].translation.y
    y_hind = pose.rest["thigh_L"].translation.y
    y_body = pose.rest["body"].translation.y
    worst = 0.0
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
        pose.turn("chest", Z, -1.6 * RAD * wave(t, T))
        pose.turn("pelvis", Z, -1.6 * RAD * wave(t, T, phase=-0.25))
        # Head nods down as each front foot lands and sways against the shoulders.
        pose.turn("neck", X, 2.0 * RAD * wave(t, T, 2, 0.12))
        pose.turn("head", X, 2.5 * RAD * wave(t, T, 2, 0.2))
        pose.turn("head", Z, 2.5 * RAD * wave(t, T, 1, 0.1))
        # Trunk: swings side to side once per stride and back and forth with every step,
        # each segment a little behind the one above it, while the tip curls and uncurls.
        n = len(TRUNK_BONES)
        trunk(pose,
              lambda i: 8.0 * RAD * (0.55 + 0.45 * i / (n - 1)) * wave(t, T, 1, 0.15 + 0.07 * i),
              lambda i: 3.5 * RAD * wave(t, T, 2, 0.3 + 0.06 * i),
              # mostly uncurling: the tip is curled in at rest already
              lambda i: -12.0 * RAD * smooth(2.5, n - 1, i) * (0.35 + 0.65 * wave(t, T, 1, 0.45)))
        for side, lag in (("L", 0.0), ("R", 0.5)):
            flap(pose, side, (6 + 6 * wave(t, T, 2, 0.25 + lag * 0.5)) * RAD)
        for i, name in enumerate(TAIL_BONES):
            pose.turn(name, Y, 11 * RAD * wave(t, T, 1, 0.3 + 0.12 * i))
        for leg in LEGS:
            wrist, pitch = legs.foot(leg, t)
            worst = max(worst, legs.solve(leg, wrist, pitch))
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    lo = min(min(g["F"][0]), min(g["H"][0]))
    hi = max(max(g["F"][0]), max(g["H"][0]))
    print(f"walk: {frames} frames, stride {REF_SPEED * WALK_PERIOD:.2f} m, sweep {SWEEP:.2f} m, "
          f"girdles ride {lo:+.3f}..{hi:+.3f} m, worst foot miss {worst * 100:.1f} cm")


def bake_idle(arm, pose, legs):
    frames = int(round(IDLE_PERIOD * FPS))
    T = IDLE_PERIOD
    _start(arm, "Idle")
    n = len(TRUNK_BONES)
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        # Breathing, and a slow shift of weight from side to side.
        pose.move("body", (0.03 * wave(t, T, 1, 0.1), 0, -0.025 + 0.012 * wave(t, T, 2)))
        pose.turn("body", Y, -0.8 * RAD * wave(t, T, 1, 0.1))
        pose.turn("body", X, 0.4 * RAD * wave(t, T, 2, 0.2))
        pose.turn("neck", X, 1.5 * RAD * wave(t, T, 2, 0.3))
        pose.turn("head", Z, 3.0 * RAD * wave(t, T, 1, 0.35))
        pose.turn("head", X, 1.5 * RAD * wave(t, T, 1, 0.6))
        trunk(pose,
              lambda i: 6.0 * RAD * (0.5 + 0.5 * i / (n - 1)) * wave(t, T, 1, 0.08 * i),
              lambda i: 2.0 * RAD * wave(t, T, 2, 0.2 + 0.05 * i),
              lambda i: 14.0 * RAD * smooth(2.5, n - 1, i) * (0.35 + 0.65 * wave(t, T, 1, 0.55)))
        # Two lazy ear flaps per loop.
        for side, lag in (("L", 0.0), ("R", 0.04)):
            open_ = max(wave(t, T, 2, lag), 0.0) ** 2
            flap(pose, side, (4 + 22 * open_) * RAD)
        for i, name in enumerate(TAIL_BONES):
            pose.turn(name, Y, 9 * RAD * wave(t, T, 2, 0.1 + 0.1 * i))
        for leg, info in legs.info.items():
            legs.solve(leg, info["wrist"], 0.0)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    print(f"idle: {frames} frames")


def _start(arm, name):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action


def _finish(arm):
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0, 0, 0)


# ---------------------------------------------------------------- preview

def render_preview(arm, out_dir):
    """Walk (travelling at REF_SPEED, two cycles) and idle, side-on, tracked by the camera."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"  # clay: the armor textures are nearly black
    sc.display.shading.single_color = (0.75, 0.72, 0.68)
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    sc.render.fps = FPS
    sc.render.image_settings.file_format = "PNG"
    ground = bpy.data.materials.new("ground")
    ground.diffuse_color = (0.42, 0.4, 0.3, 1)
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, -20, 0))
    bpy.context.object.data.materials.append(ground)
    for i in range(-6, 7):
        for j in range(-45, 8):
            bpy.ops.mesh.primitive_cube_add(size=0.08, location=(i * 1.0, j * 1.0, 0.04))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 35
    arm.animation_data_create()
    for clip, cycles, speed, view in (("Walk", 2, REF_SPEED, (9.0, 2.5, 3.2)), ("Walk", 1, REF_SPEED, (6.0, -7.0, 2.6)),
                                      ("Idle", 1, 0.0, (7.0, -6.5, 3.0))):
        action = bpy.data.actions[clip]
        arm.animation_data.action = action
        length = int(round((WALK_PERIOD if clip == "Walk" else IDLE_PERIOD) * FPS))
        tag = "%s_%d" % (clip.lower(), int(view[1]))
        for k in range(length * cycles):
            sc.frame_set(k % length)
            y = -speed * k / FPS
            arm.location = (0, y, 0)
            cam.location = (view[0], y + view[1], view[2])
            cam.rotation_euler = (Vector((0, y - 0.8, 1.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(out_dir, "%s_%04d.png" % (tag, k))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    arm.location = (0, 0, 0)


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from process_rigged_humanoid import shrink_textures

    mesh = load(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    add_rings(mesh)
    pieces = parts(mesh)
    kinds = [(pieces[0], "body")] + [(p, classify(mesh, p)) for p in pieces[1:]]
    arm, n_tubes = build_armature(mesh, kinds)
    skin(mesh, arm, kinds)
    pose = Pose(arm)
    legs = Legs(pose)
    bake_walk(arm, pose, legs)
    bake_idle(arm, pose, legs)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    print(f"exported {args.output}: {len(arm.data.bones)} bones, {n_tubes} missile tubes, "
          f"walk at {REF_SPEED} m/s, clips {[a.name for a in bpy.data.actions]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
