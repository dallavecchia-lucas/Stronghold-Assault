"""Rig and animate the Bison Field Gun: two bisons with an artillery gun slung between them. The
Meshy export comes without a rig, so this builds one.

The mesh is scaled to the in-game height and its origin put in the middle of the eight stance spots
(under the leg pivots). Each bison is skinned with region-based weights like the War Elephant
(rig_elephant.py): legs and tail as bone chains, the head, neck and the three torso bones blended
along the body. Their bones are prefixed L_ (the bison on the pair's left, +X, walking a little
ahead) and R_. A leg runs from a pivot high in the body (the shoulder blade or the pelvis swings
with it) to the elbow (stifle), the knee (hock), the fetlock and the hoof. The export has both
bisons mid-stride, so their legs are first stood the way they stand at mid-stance and the rig is
bound in that pose (repose). Two looping clips are baked:

  Walk  both bisons walk the elephant's lateral-sequence walk (hind left, fore left, hind right,
        fore right, a quarter cycle apart), the right one R_PHASE of a cycle behind the left one
        so they don't step in lockstep. Inverse kinematics keeps each hoof planted while it is on
        the ground: it lands flat, and its heel peels off at the end of the stance so it rolls
        over the toe. In the swing the knee (hock) folds and the hoof flips back. Each body rides
        over its legs, sways over the side whose feet are down and turns with the stride; the
        heads nod with every step and the tails swing.
  Idle  breathing, weight shifts, slow head swings and tail swishes; the hooves stand square.

The gun rides on `carriage`: each frame it takes the rigid pose that best fits where the sockets
on the bisons' flanks have gone, and the fins between the platform and the flanks blend from it
into each bison's body. `muzzle` marks the barrel tip (no weights).

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_bison_gun.py -- \\
      --input assets_src/units/semi_futuristic_pair/semi_futuristic_pair_meshy.glb \\
      --output game/assets/units/semi_futuristic_pair/semi_futuristic_pair_rigged.glb \\
      [--preview DIR]

--preview renders the walk travelling at REF_SPEED and the idle into DIR (PNG frames).
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_rigged_humanoid import shrink_textures  # noqa: E402
from rig_elephant import (Pose, _finish, _start, aim_frame, chain_weights, hermite, lowpass, mix,  # noqa: E402
                          parts, smooth, two_bone, wave)

FPS = 30
HEIGHT = 2.4  # meters, as for the static model (the tops of the gun sights)

# All positions below are in the static model's frame (process_meshy_model.py --height 2.4
# --pivot bbox): front -Y, up +Z, the pair's left +X. load() moves the model so the middle of the
# stance spots is at the origin; P() shifts a position the same way.
#
# Per bison: the spine (rump, middle of the trunk, chest, root of the neck, poll, nose), the tail's
# joints, where the torso bones blend along y (chest -> body, body -> pelvis), where the neck and
# head take over (chest -> neck, neck -> head; below `throat` only in front of the brisket), and the
# legs. A leg, from the top: pivot, elbow (stifle), knee (hock), fetlock and the tip of the hoof.
# The two bisons aren't quite alike: R stands about 0.45 m further back, its head stretched out.
BISONS = {
    "L": {
        "spine": [(1.27, 1.40, 1.25), (1.36, 0.45, 1.15), (1.39, -0.15, 1.25), (1.42, -0.55, 1.32),
                  (1.45, -0.75, 1.25), (1.50, -1.25, 0.85)],
        "tail": [(1.28, 1.47, 1.32), (1.20, 1.57, 1.04), (1.15, 1.70, 0.76)],
        "torso_y": (-0.20, 0.25, 0.75, 1.15),
        "neck_y": (-0.50, -0.65, -0.72, -0.88),
        "throat": 0.95,
        "legs": {
            "FL": [(1.66, -0.17, 1.12), (1.68, 0.21, 0.66), (1.68, 0.26, 0.39), (1.66, 0.36, 0.155), (1.68, 0.18, 0.0)],
            "FR": [(1.14, -0.17, 1.12), (1.12, -0.40, 0.58), (1.14, -0.59, 0.37), (1.155, -0.72, 0.16), (1.18, -0.91, 0.0)],
            "HL": [(1.50, 1.25, 1.15), (1.45, 1.13, 0.72), (1.49, 1.25, 0.43), (1.54, 1.04, 0.19), (1.58, 0.81, 0.0)],
            "HR": [(1.12, 1.25, 1.15), (1.10, 1.37, 0.72), (1.10, 1.60, 0.47), (1.105, 1.68, 0.19), (1.12, 1.54, 0.0)],
        },
    },
    "R": {
        "spine": [(-1.46, 1.92, 1.25), (-1.42, 0.85, 1.15), (-1.40, 0.15, 1.25), (-1.40, -0.26, 1.32),
                  (-1.38, -0.46, 1.25), (-1.37, -0.97, 0.88)],
        "tail": [(-1.45, 1.98, 1.33), (-1.46, 2.05, 1.02), (-1.47, 2.12, 0.70)],
        "torso_y": (0.10, 0.55, 1.20, 1.60),
        "neck_y": (-0.22, -0.36, -0.44, -0.60),
        "throat": 0.95,
        "legs": {
            "FL": [(-1.17, -0.05, 1.12), (-1.17, 0.12, 0.60), (-1.16, 0.02, 0.39), (-1.18, 0.24, 0.23), (-1.21, 0.355, 0.06)],
            "FR": [(-1.65, -0.05, 1.12), (-1.65, 0.10, 0.64), (-1.65, 0.06, 0.37), (-1.66, -0.01, 0.15), (-1.67, -0.19, 0.0)],
            "HL": [(-1.20, 1.83, 1.15), (-1.20, 1.66, 0.70), (-1.20, 1.74, 0.38), (-1.175, 1.51, 0.19), (-1.18, 1.30, 0.0)],
            "HR": [(-1.58, 1.83, 1.15), (-1.57, 1.99, 0.72), (-1.57, 2.19, 0.47), (-1.58, 2.27, 0.19), (-1.59, 2.13, 0.0)],
        },
    },
}
FRONT_BONES = ("upperarm", "forearm", "forecannon", "forehoof")
HIND_BONES = ("thigh", "shin", "hindcannon", "hindhoof")
LEG_R = (0.12, 0.24)  # around a leg below the body it is all leg, fading out to the torso by here (m)
UPPER_R = (0.12, 0.42)  # the same around the upper bone, inside the body
# The gun: its carriage's middle and the barrel's tip. Fins reach from the platform's edge to the
# bisons' flanks, where they plug into sockets; the fins blend from the carriage into the flank.
CARRIAGE = (0.0, 0.45, 1.38)
MUZZLE = (0.0, -2.37, 2.06)
FIN_X = (0.62, 0.90)
SOCKETS = [(0.92, 0.50, 1.30), (0.92, 0.77, 1.30)]  # on the L bison; mirrored for R


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


def leg_bones(b, leg):
    names = FRONT_BONES if leg[0] == "F" else HIND_BONES
    return ["%s_%s_%s" % (b, n, leg[1]) for n in names]


# ---------------------------------------------------------------- mesh

def load(path):
    """Imports the Meshy export and puts it in the static model's frame, then moves it back so the
    middle of the stance spots is at the origin: the pair turns about its legs, not about the
    bounding box, which the gun barrel stretches far ahead."""
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
    co = (co - [(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, lo[2]]) * (HEIGHT / (hi[2] - lo[2]))
    pivots = [leg[0] for b in BISONS.values() for leg in b["legs"].values()]
    SHIFT = Vector((0.0, sum(p[1] for p in pivots) / len(pivots), 0.0))
    co -= np.array(SHIFT)
    mesh.data.vertices.foreach_set("co", co.ravel())
    mesh.data.update()
    return mesh


def classify(mesh, pieces):
    """The two bisons are the largest pieces, L on +X. Of the rest, the two that reach out to the
    flanks are the fins; everything else is the gun on its carriage."""
    kinds = []
    for k, piece in enumerate(pieces):
        xs = [mesh.data.vertices[i].co.x for i in piece]
        if k < 2:
            kinds.append((piece, "L" if sum(xs) > 0 else "R"))
        elif max(abs(x) for x in xs) > FIN_X[1] - 0.1:
            kinds.append((piece, "fin"))
        else:
            kinds.append((piece, "carriage"))
    return kinds


# ---------------------------------------------------------------- armature

def build_armature():
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

    for b, d in BISONS.items():
        rump, middle, chest, neck, poll, nose = (P(p) for p in d["spine"])
        bone(b + "_body", None, middle, chest)
        bone(b + "_chest", b + "_body", chest, neck, True)
        bone(b + "_neck", b + "_chest", neck, poll, True)
        bone(b + "_head", b + "_neck", poll, nose, True)
        bone(b + "_pelvis", b + "_body", middle, rump)
        tail = [P(p) for p in d["tail"]]
        for i in range(len(tail) - 1):
            bone("%s_tail_%d" % (b, i + 1), b + "_pelvis" if i == 0 else "%s_tail_%d" % (b, i), tail[i], tail[i + 1], i > 0)
        for leg, joints in d["legs"].items():
            names = leg_bones(b, leg)
            j = [P(p) for p in joints]
            bone(names[0], b + ("_chest" if leg[0] == "F" else "_pelvis"), j[0], j[1])
            for k in range(1, 4):
                bone(names[k], names[k - 1], j[k], j[k + 1], True)
    c = P(CARRIAGE)
    bone("carriage", None, c, c + Vector((0, -0.5, 0)))
    m = P(MUZZLE)
    bone("muzzle", "carriage", m, m + Vector((0, -0.3, 0)), deform=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ---------------------------------------------------------------- skinning

def torso_weights(b, q):
    """Head, neck and the three torso bones of bison b, by position along its body (static frame)."""
    d = BISONS[b]
    y = q.y
    t, n = d["torso_y"], d["neck_y"]
    if y < t[1]:
        w = mix({b + "_chest": 1.0}, {b + "_body": 1.0}, smooth(t[0], t[1], y))
    else:
        w = mix({b + "_body": 1.0}, {b + "_pelvis": 1.0}, smooth(t[2], t[3], y))
    # The head hangs low in front of the brisket: under the throat it only starts further forward.
    if y < n[0] and (q.z > d["throat"] or y < n[2]):
        neck = mix({b + "_neck": 1.0}, {b + "_head": 1.0}, smooth(n[2], n[3], y))
        w = mix(w, neck, smooth(n[0], n[1], y))
    return w


def segment_distance(p, a, b):
    ab = b - a
    t = min(max((p - a).dot(ab) / ab.length_squared, 0.0), 1.0)
    return (a + ab * t - p).length


def leg_weights(b, leg, q):
    """(pull, weights) of one leg for a point (static frame). The pull is 1 on the leg below the
    body. Up the upper bone (shoulder or thigh, inside the body) and around it, it fades out
    slowly, so the skin there slides with the leg like a shoulder blade over the ribs and
    stretches gradually instead of folding over. Past the fetlock (along the cannon) it is hoof."""
    j = [Vector(p) for p in BISONS[b]["legs"][leg]]
    low = min(segment_distance(q, j[i], j[i + 1]) for i in range(1, 4))
    pull = smooth(LEG_R[1], LEG_R[0], low) * smooth(j[1].z + 0.12, j[1].z - 0.02, q.z)
    up = segment_distance(q, j[0], j[1])
    along = (q.z - j[1].z) / (j[0].z - j[1].z)  # 0 at the elbow, 1 at the pivot
    pull = max(pull, smooth(UPPER_R[1], UPPER_R[0], up) * (1.0 - 0.6 * smooth(0.0, 1.0, along)))
    if pull <= 0.0:
        return 0.0, None
    names = leg_bones(b, leg)
    w, _ = chain_weights(q, j[:4], names[:3], 0.06)
    down = (j[3] - j[2]).normalized()
    return pull, mix(w, {names[3]: 1.0}, smooth(-0.025, 0.025, (q - j[3]).dot(down)))


def leg_pulls(b, q):
    """[(pull, weights)] of the legs reaching point q (static frame), their pulls summing to 1 at
    most: legs close together (the brisket between the front legs) share a point."""
    pulls = [p for p in (leg_weights(b, leg, q) for leg in BISONS[b]["legs"]) if p[0] > 0.0]
    total = sum(p for p, _ in pulls)
    if total > 1.0:
        pulls = [(p / total, lw) for p, lw in pulls]
    return pulls


def body_weights(b, q):
    """Skin weights for a point on bison b (static frame)."""
    w = torso_weights(b, q)
    tail = [Vector(p) for p in BISONS[b]["tail"]]
    if q.y > tail[0].y - 0.05:
        names = ["%s_tail_%d" % (b, i + 1) for i in range(len(tail) - 1)]
        tw, dist = chain_weights(q, tail, names, 0.1)
        # Down the tail away from its root, so the rump it hangs against stays put.
        along = (q - tail[0]).dot((tail[-1] - tail[0]).normalized())
        share = smooth(0.11, 0.07, dist) * smooth(0.04, 0.16, along)
        if share > 0.0:
            return mix(w, tw, share)
    pulls = leg_pulls(b, q)
    total = sum(p for p, _ in pulls)
    out = {k: v * (1.0 - total) for k, v in w.items()}
    for p, lw in pulls:
        for k, v in lw.items():
            out[k] = out.get(k, 0.0) + v * p
    return out


def skin(mesh, arm, kinds):
    weights = [None] * len(mesh.data.vertices)
    for piece, kind in kinds:
        for i in piece:
            q = mesh.data.vertices[i].co + SHIFT
            if kind in BISONS:
                weights[i] = body_weights(kind, q)
            elif kind == "fin":
                weights[i] = mix({"carriage": 1.0}, torso_weights("L" if q.x > 0 else "R", q),
                                 smooth(FIN_X[0], FIN_X[1], abs(q.x)))
            else:
                weights[i] = {"carriage": 1.0}
    groups = {}
    for i, w in enumerate(weights):
        # glTF carries four influences per vertex: keep the strongest.
        w = dict(sorted(w.items(), key=lambda kv: -kv[1])[:4])
        weights[i] = w
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


# ---------------------------------------------------------------- legs

WALK_PERIOD = 0.9  # seconds per cycle in the clip
REF_SPEED = 1.85  # ground speed the walk is authored for (m/s): UnitTypes anim_ref_speed
DUTY = 0.58  # share of the cycle each hoof is on the ground
SWING = 1.0 - DUTY
SWEEP = REF_SPEED * WALK_PERIOD * DUTY  # how far a planted hoof travels back under the body
# Middle of each leg's swing as a share of the cycle: a lateral-sequence walk, a quarter apart.
SWING_MID = {"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}
R_PHASE = 0.38  # the right bison's walk runs this share of a cycle behind the left one's
# Each girdle's pivot, high in the body: the shoulder blade swings with the leg in front, the
# pelvis tilts with it behind. At mid-stance, and in the rest pose, a hoof stands with its fetlock
# SPOT behind the pivot and the leg BENT of its full length from the pivot to the fetlock.
PIVOT_Z = {"F": 1.5, "H": 1.45}
SPOT = {"F": 0.1, "H": 0.0}
BENT = {"F": 0.985, "H": 0.955}
LIFT = {"F": 0.12, "H": 0.10}  # fetlock clearance at mid-swing (m)
HOOF_FOLD = {"F": 65.0, "H": 50.0}  # how far the hoof flips back mid-swing (degrees)
HEEL_OFF = 0.3  # last share of the stance in which the heel peels off, rolling over the toe
HEEL_ANGLE = {"F": 26.0, "H": 22.0}
STRAIGHT = 0.99  # how straight a planted leg may get (share of its length)
SWAY = 0.025  # weight over the planted side (m)
YAW = 1.6  # shoulders and hips turning with the stride (degrees)
IDLE_PERIOD = 5.0
HINGE = Vector((1, 0, 0))  # the knees bend about X: also the bones' twist reference
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
RAD = math.pi / 180


def turn_x(angle, v):
    return Matrix.Rotation(angle, 3, "X") @ v


class Leg:
    """One leg's measurements, where its hoof goes in the walk, and the IK that poses it.

    Planted, a front leg's knee is straight, so the forearm and the cannon stand as one column
    under the elbow, and a hind leg's cannon stays parallel to its thigh (stifle and hock bend
    alike): that leaves two lengths to solve between the pivot and the fetlock. Swinging, the
    upper bone turns from where it left the ground to where it lands, and the knee (hock) folds
    to carry the hoof along its path."""

    def __init__(self, b, name):
        pivot, elbow, knee, fetlock, toe = (P(p) for p in BISONS[b]["legs"][name])
        self.b, self.name, self.kind = b, name, name[0]
        self.bones = leg_bones(b, name)
        self.l1, self.l2, self.l3 = (elbow - pivot).length, (knee - elbow).length, (fetlock - knee).length
        self.pivot, self.fetlock0 = pivot, fetlock
        self.hoof = fetlock - toe
        self.tilt = 0.0  # turns the hoof as it is at rest to standing flat (set_flat)
        self.flat = self.hoof.copy()  # toe -> fetlock standing flat
        # Elbows bend back, stifles forward.
        self.pole = Vector((0, 1, 0)) if self.kind == "F" else Vector((0, -1, 0))
        self.out = 1.0 if name[1] == "L" else -1.0  # the side the hoof swings out to
        self.lifted = toe.z > 0.03

    def set_flat(self, other):
        """A hoof off the ground at rest stands flat like the other one of its pair."""
        if self.lifted:
            a0 = math.atan2(self.hoof.z, self.hoof.y)
            a1 = math.atan2(other.hoof.z, other.hoof.y)
            self.tilt = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        self.flat = turn_x(self.tilt, self.hoof)
        # Where the toe stands at mid-stance: the fetlock SPOT behind the pivot, on its own track.
        self.spot = Vector((self.fetlock0.x - self.flat.x, self.pivot.y + SPOT[self.kind] - self.flat.y, 0.0))

    def fetlock(self, toe, pitch):
        """Where the fetlock is for the toe at `toe`, the heel up by `pitch` (rolling over the toe)."""
        return toe + turn_x(pitch, self.flat)

    def stance(self, u, sweep):
        """(toe, hoof pitch) u of the way through the stance."""
        toe = self.spot + Vector((0, -sweep / 2 + sweep * u, 0))
        return toe, math.radians(HEEL_ANGLE[self.kind]) * smooth(1 - HEEL_OFF, 1.0, u) ** 1.5

    def foot(self, t, delay, sweep):
        """(fetlock, hoof pitch, swing) at time t of the walk, delay being the bison's phase. swing
        is None planted, else (u, fold, lift-off fetlock, touch-down fetlock): u of the way through
        it, the hoof folded by `fold` (0..1)."""
        phase = (t / WALK_PERIOD - SWING_MID[self.name] - delay + SWING / 2) % 1.0  # 0 at lift-off
        if phase >= SWING:
            toe, pitch = self.stance((phase - SWING) / DUTY, sweep)
            return self.fetlock(toe, pitch), pitch, None
        u = phase / SWING
        t0, p0 = self.stance(1.0, sweep)  # lift-off
        t1, _ = self.stance(0.0, sweep)  # touch-down
        w0, w1 = self.fetlock(t0, p0), self.fetlock(t1, 0.0)
        v = sweep * SWING / DUTY  # the ground's travel during the swing, in the same units
        # Leaves the ground easing out of the backward drift, lands moving with the ground.
        y = hermite(w0.y, w1.y, 0.35 * v, v, u)
        z = (1 - u) * w0.z + u * w1.z + LIFT[self.kind] * math.sin(math.pi * u ** 0.85) ** 1.2
        x = (1 - u) * w0.x + u * w1.x + self.out * 0.02 * math.sin(math.pi * u)  # swings out a little
        fold = math.sin(math.pi * min(u / 0.85, 1.0)) ** 1.3
        pitch = p0 * (1 - smooth(0.0, 0.3, u)) + math.radians(HOOF_FOLD[self.kind]) * fold
        return Vector((x, y, z)), pitch, (u, fold, w0, w1)

    def planted(self, a, fetlock):
        """(elbow, knee, fetlock) of the planted leg for the pivot at a (stifle, hock and fetlock for a
        hind leg). The fetlock falls short if the leg can't reach."""
        if self.kind == "F":
            elbow, end = two_bone(a, self.l1, self.l2 + self.l3, fetlock, self.pole)
            return elbow, elbow + (end - elbow).normalized() * self.l2, end
        mid, end = two_bone(a, self.l1 + self.l3, self.l2, fetlock, self.pole)
        thigh = (mid - a).normalized()
        hock = a + thigh * self.l1 + (end - mid).normalized() * self.l2
        return a + thigh * self.l1, hock, end

    def swinging(self, a, fetlock, swing):
        """(elbow, knee, fetlock) of the swinging leg. The upper bone turns from its angle at lift-off
        to the one it lands with, keeping up with the stance at both ends (it first swings on
        back a little, then reaches past and settles); the knee folds forward, the hock back, to
        carry the hoof along its path."""
        u, _, f0, f1 = swing
        e0, e1 = self.planted(a, f0)[0], self.planted(a, f1)[0]
        a0 = math.atan2((e0 - a).z, (e0 - a).y)
        a1 = math.atan2((e1 - a).z, (e1 - a).y)
        rate = (a0 - a1) * SWING / DUTY  # the stance's turn, in the swing's time
        elbow = a + turn_x(hermite(0.0, a1 - a0, 0.35 * rate, rate, u), e0 - a)
        knee, end = two_bone(elbow, self.l2, self.l3, fetlock, -self.pole)
        return elbow, knee, end

    def solve(self, pose, fetlock, pitch, swing=None):
        """Poses the leg's bones to put the fetlock at `fetlock`, the hoof pitched by `pitch`."""
        up, lo, cn, hf = self.bones
        a = pose.head(up)
        elbow, knee, low = self.planted(a, fetlock) if swing is None else self.swinging(a, fetlock, swing)
        for name, h, t in ((up, a, elbow), (lo, elbow, knee), (cn, knee, low)):
            r = pose.rest[name]
            rest_y = r.to_3x3() @ Vector((0, 1, 0))
            q = aim_frame((t - h).normalized(), HINGE) @ aim_frame(rest_y, HINGE).inverted()
            pose.place(name, Matrix.Translation(h) @ (q @ r.to_3x3()).to_4x4())
        r = pose.rest[hf]
        pose.place(hf, Matrix.Translation(low) @ turn_x(self.tilt + pitch, r.to_3x3()).to_4x4())
        return (low - fetlock).length

    def reach(self, fetlock, pivot):
        """Highest the pivot can be above its rest height, at pivot's x and y, and still reach
        `fetlock` planted."""
        full = (self.l1 + self.l2 + self.l3) * STRAIGHT
        flat = (pivot.xy - fetlock.xy).length
        return fetlock.z + math.sqrt(max(full * full - flat * flat, 0.0)) - self.pivot.z


def make_legs():
    legs = {b: {name: Leg(b, name) for name in d["legs"]} for b, d in BISONS.items()}
    for b, ls in legs.items():
        for name, leg in ls.items():
            leg.set_flat(ls[name[0] + ("R" if name[1] == "L" else "L")])
    return legs


# ---------------------------------------------------------------- rest pose

def welded(mesh, piece):
    """The piece with the vertices the export split along its UV seams joined: (positions, the
    welded index of each of the piece's vertices, neighbour lists)."""
    co = np.array([list(mesh.data.vertices[i].co) for i in piece])
    _, first, inv = np.unique(np.round(co * 1e5).astype(np.int64), axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    local = {v: k for k, v in enumerate(piece)}
    nbrs = [set() for _ in first]
    for poly in mesh.data.polygons:
        if poly.vertices[0] not in local:
            continue
        vs = [inv[local[v]] for v in poly.vertices]
        for a, c in zip(vs, vs[1:] + vs[:1]):
            if a != c:
                nbrs[a].add(c)
                nbrs[c].add(a)
    return co[first], inv, [sorted(n) for n in nbrs]


def arap(rest, guess, free, nbrs, iterations=15):
    """As-rigid-as-possible deformation (Sorkine and Alexa 2007, uniform weights): moves the `free`
    vertices so that every vertex's neighbourhood keeps its rest shape as well as it can, the
    others held where `guess` has them."""
    n = len(rest)
    slot = -np.ones(n, dtype=int)
    slot[free] = np.arange(len(free))
    ii = np.array([i for i in range(n) for _ in nbrs[i]])
    jj = np.array([j for i in range(n) for j in nbrs[i]])
    lap = np.zeros((len(free), len(free)))
    for a, i in enumerate(free):
        lap[a, a] = len(nbrs[i])
        for j in nbrs[i]:
            if slot[j] >= 0:
                lap[a, slot[j]] -= 1.0
    inverse = np.linalg.inv(lap)
    e0 = rest[ii] - rest[jj]
    starts = slot[ii] >= 0  # edges out of a free vertex
    held = slot[jj] < 0
    cur = guess.copy()
    for _ in range(iterations):
        # Each vertex's best rotation of its rest neighbourhood onto the current one...
        cov = np.zeros((n, 3, 3))
        np.add.at(cov, ii, e0[:, :, None] * (cur[ii] - cur[jj])[:, None, :])
        u, _, vt = np.linalg.svd(cov)
        flip = np.linalg.det(np.transpose(vt, (0, 2, 1)) @ np.transpose(u, (0, 2, 1))) < 0
        vt[flip, 2] *= -1
        rot = np.transpose(vt, (0, 2, 1)) @ np.transpose(u, (0, 2, 1))
        # ...then the positions that best fit those rotations.
        term = 0.5 * np.einsum("kab,kb->ka", rot[ii] + rot[jj], e0)
        term[held] += cur[jj[held]]
        rhs = np.zeros((len(free), 3))
        np.add.at(rhs, slot[ii[starts]], term[starts])
        cur[free] = inverse @ rhs
    return cur


def repose(mesh, kinds):
    """Stands the legs in the pose the rig is bound in, the one each leg has at mid-stance: the
    hoof flat on its spot, the leg BENT of its length under a pivot at PIVOT_Z (its upper bone
    takes the length that needs). The export has both bisons mid-stride, the left one's front
    legs at the two ends of a long stride; bound like that, the walk would drag the skin over its
    shoulders twice as far, and the two bisons' legs wouldn't match. The legs move with their
    bones, skinned as below (the upper bone turns about its own head), then the skin where they
    join the body is relaxed as rigidly as possible. BISONS gets the legs' new joints."""
    arm = build_armature()
    pose = Pose(arm)
    legs = make_legs()
    joints = {}
    for b, ls in legs.items():
        for name, leg in ls.items():
            up, lo, cn, hf = leg.bones
            pivot = Vector((leg.pivot.x, leg.pivot.y, PIVOT_Z[leg.kind]))
            fetlock = leg.fetlock(leg.spot, 0.0)
            leg.l1 = (pivot - fetlock).length / BENT[leg.kind] - leg.l2 - leg.l3
            elbow, knee, low = leg.planted(pivot, fetlock)
            heads = {up: pose.rest[up].translation, lo: elbow, cn: knee}
            for n, tail in ((up, elbow), (lo, knee), (cn, low)):
                r = pose.rest[n]
                rest_y = r.to_3x3() @ Vector((0, 1, 0))
                q = aim_frame((tail - heads[n]).normalized(), HINGE) @ aim_frame(rest_y, HINGE).inverted()
                pose.place(n, Matrix.Translation(heads[n]) @ (q @ r.to_3x3()).to_4x4())
            r = pose.rest[hf]
            pose.place(hf, Matrix.Translation(low) @ turn_x(leg.tilt, r.to_3x3()).to_4x4())
            joints[b, name] = [pivot, elbow, knee, low, low - leg.flat]
    for piece, b in kinds:
        if b not in BISONS:
            continue
        rest, inv, nbrs = welded(mesh, piece)
        guess = np.empty_like(rest)
        free = []
        for k, p in enumerate(rest):
            q = Vector(p) + SHIFT
            w = body_weights(b, q)
            total = sum(w.values())
            guess[k] = list(deform(pose, {name: x / total for name, x in w.items()}, Vector(p)))
            if 0.0 < sum(x for x, _ in leg_pulls(b, q)) < 0.999:
                free.append(k)
        new = arap(rest, guess, np.array(free), nbrs)
        for k, i in enumerate(piece):
            mesh.data.vertices[i].co = new[inv[k]]
    mesh.data.update()
    for (b, name), js in joints.items():
        BISONS[b]["legs"][name] = [tuple(p + SHIFT) for p in js]
    data = arm.data
    bpy.data.objects.remove(arm)
    bpy.data.armatures.remove(data)


# ---------------------------------------------------------------- posing

TAIL_BONES = {b: ["%s_tail_%d" % (b, i + 1) for i in range(len(d["tail"]) - 1)] for b, d in BISONS.items()}
ANIMATED = ["carriage"] + [b + "_" + n for b in BISONS for n in ("body", "chest", "neck", "head", "pelvis")] + \
    [n for b in BISONS for n in TAIL_BONES[b]] + [n for b, d in BISONS.items() for leg in d["legs"] for n in leg_bones(b, leg)]


def deform(pose, weights, p):
    """Where point p (armature space) goes with the bones posed, skinned with `weights`."""
    out = Vector()
    for name, w in weights.items():
        out += w * (pose.world(name) @ pose.rest[name].inverted() @ p)
    return out


def sockets():
    """The four sockets the fins plug into: (armature-space point, normalized torso weights)."""
    out = []
    for b, side in (("L", 1), ("R", -1)):
        for x, y, z in SOCKETS:
            q = Vector((x * side, y, z))
            w = torso_weights(b, q)
            total = sum(w.values())
            out.append((q - SHIFT, {k: v / total for k, v in w.items()}))
    return out


def carry(pose, socks):
    """Poses the carriage rigidly where it best fits the sockets, each moved with its bison's body.
    The fins take up what is left over."""
    rest = np.array([list(p) for p, _ in socks])
    now = np.array([list(deform(pose, w, p)) for p, w in socks])
    cr, cn = rest.mean(axis=0), now.mean(axis=0)
    u, _, vt = np.linalg.svd((rest - cr).T @ (now - cn))
    d = np.sign(np.linalg.det(vt.T @ u.T))
    rot = vt.T @ np.diag([1.0, 1.0, d]) @ u.T
    m = Matrix(rot.tolist()).to_4x4()
    m.translation = Vector((cn - rot @ cr).tolist())
    pose.place("carriage", m @ pose.rest["carriage"])


def girdle_heights(legs, ts, sway, delay):
    """How high each girdle of one bison rides each frame (above its rest height) and how much it
    rolls: no higher than at rest, where the legs keep a little bend at mid-stance, and low enough
    for the planted legs to reach, so the body rides over them (two dips per cycle). A hoof just
    off the ground, or about to land, has to be reachable too."""
    out = {}
    for girdle in "FH":
        left, right = legs[girdle + "L"], legs[girdle + "R"]
        width = left.pivot.x - right.pivot.x
        rise, roll = [], []
        for k, t in enumerate(ts):
            r = {}
            for leg in (left, right):
                phase = (t / WALK_PERIOD - SWING_MID[leg.name] - delay + SWING / 2) % 1.0
                if not 0.3 * SWING < phase < 0.8 * SWING:
                    fetlock, _, _ = leg.foot(t, delay, SWEEP)
                    r[leg] = min(leg.reach(fetlock, leg.pivot + Vector((sway[k], 0, 0))), 0.0)
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
        out[girdle] = ([s - over - 0.005 for s in smooth_rise], lowpass(roll, 2))
    return out


def ride(pose, b, legs, front, hind, roll_f, roll_h, sway):
    """Moves and turns bison b's body for its girdles to ride at `front` and `hind` (above their
    rest heights), rolled by roll_f and roll_h."""
    y_front, y_hind = legs["FL"].pivot.y, legs["HL"].pivot.y
    y_body = pose.rest[b + "_body"].translation.y
    slope = (hind - front) / (y_hind - y_front)
    pose.move(b + "_body", (sway, 0, front + (y_body - y_front) * slope))
    pose.turn(b + "_body", X, math.atan(slope))
    pose.turn(b + "_body", Y, -(roll_f + roll_h) / 2)
    pose.turn(b + "_chest", Y, -(roll_f - roll_h) / 2)
    pose.turn(b + "_pelvis", Y, -(roll_h - roll_f) / 2)


def bake_walk(arm, pose, legs):
    frames = int(round(WALK_PERIOD * FPS))
    ts = [f / FPS for f in range(frames + 1)]
    T = WALK_PERIOD
    socks = sockets()
    plan = {}
    for b in BISONS:
        delay = R_PHASE if b == "R" else 0.0
        # Weight shifts over the side whose feet are down (left around 0.625, when the right legs
        # swing), and the shoulders and hips turn with each leg reaching forward.
        sway = [SWAY * math.cos(2 * math.pi * (t / T - 0.625 - delay)) for t in ts]
        g = girdle_heights(legs[b], ts[:-1], sway[:-1], delay)
        plan[b] = (delay, sway, {k: (v[0] + v[0][:1], v[1] + v[1][:1]) for k, v in g.items()})  # close the loop
    worst, lowest = 0.0, 9.0
    _start(arm, "Walk")
    for f, t in enumerate(ts):
        pose.reset()
        for b, (delay, sway, g) in plan.items():
            ride(pose, b, legs[b], g["F"][0][f], g["H"][0][f], g["F"][1][f], g["H"][1][f], sway[f])
            pose.turn(b + "_chest", Z, -YAW * RAD * wave(t, T, 1, delay))
            pose.turn(b + "_pelvis", Z, -YAW * RAD * wave(t, T, 1, delay - 0.25))
            # The head nods down as each front hoof lands and sways against the shoulders.
            pose.turn(b + "_neck", X, 1.5 * RAD * wave(t, T, 2, 0.12 + 2 * delay))
            pose.turn(b + "_head", X, 3.0 * RAD * wave(t, T, 2, 0.2 + 2 * delay))
            pose.turn(b + "_head", Z, 2.5 * RAD * wave(t, T, 1, 0.1 + delay))
            for i, name in enumerate(TAIL_BONES[b]):
                pose.turn(name, Y, 9 * RAD * wave(t, T, 1, 0.3 + 0.12 * i + delay))
            for leg in legs[b].values():
                fetlock, pitch, swing = leg.foot(t, delay, SWEEP)
                worst = max(worst, leg.solve(pose, fetlock, pitch, swing))
                if swing and 0.1 < swing[0] < 0.9:
                    lowest = min(lowest, toe_height(pose, leg))
        carry(pose, socks)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    rides = ["%s %+.3f..%+.3f" % (b + k, min(v[0]), max(v[0])) for b, (_, _, g) in plan.items() for k, v in g.items()]
    print(f"walk: {frames} frames at {REF_SPEED} m/s, stride {REF_SPEED * WALK_PERIOD:.2f} m, sweep {SWEEP:.2f} m, "
          f"girdles ride {', '.join(rides)} m, worst hoof miss {worst * 100:.1f} cm, lowest toe {lowest * 100:.1f} cm")


def toe_height(pose, leg):
    """Height of the hoof's tip (its bone's tail) as posed."""
    hf = leg.bones[3]
    return (pose.world(hf) @ pose.rest[hf].inverted() @ pose.tail[hf]).z


def bake_idle(arm, pose, legs):
    frames = int(round(IDLE_PERIOD * FPS))
    T = IDLE_PERIOD
    socks = sockets()
    _start(arm, "Idle")
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        for b, ph in (("L", 0.0), ("R", 0.43)):
            ls = legs[b]
            # Breathing, and a slow shift of weight from side to side.
            breath = -0.01 + 0.006 * wave(t, T, 2, 2 * ph)
            ride(pose, b, ls, breath, breath, 0.0, 0.0, 0.018 * wave(t, T, 1, 0.1 + ph))
            pose.turn(b + "_body", Y, -0.7 * RAD * wave(t, T, 1, 0.1 + ph))
            pose.turn(b + "_chest", X, 0.5 * RAD * wave(t, T, 2, 0.3 + 2 * ph))
            # The head swings slowly to one side and back, nodding now and then.
            pose.turn(b + "_neck", Z, 5.0 * RAD * wave(t, T, 1, 0.35 + ph))
            pose.turn(b + "_head", Z, 4.0 * RAD * wave(t, T, 1, 0.45 + ph))
            pose.turn(b + "_head", X, 2.5 * RAD * wave(t, T, 2, 0.6 + 2 * ph) + 1.5 * RAD * wave(t, T, 3, 0.2 + 3 * ph))
            # Tail swishes, twice a loop.
            for i, name in enumerate(TAIL_BONES[b]):
                swish = wave(t, T, 2, 0.1 + 0.08 * i + 2 * ph)
                pose.turn(name, Y, 14 * RAD * swish)
                pose.turn(name, X, -4 * RAD * abs(swish))
            for leg in ls.values():
                leg.solve(pose, leg.fetlock(leg.spot, 0.0), 0.0)
        carry(pose, socks)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    print(f"idle: {frames} frames")


# ---------------------------------------------------------------- preview

def render_preview(arm, out_dir):
    """Walk (travelling at REF_SPEED, two cycles) and idle, from the side, three quarters and the
    front, tracked by the camera."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"  # clay: the armor textures are dark
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
            bpy.ops.mesh.primitive_cube_add(size=0.06, location=(i * 1.0, j * 1.0, 0.03))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 35
    arm.animation_data_create()
    for clip, cycles, speed, view in (("Walk", 2, REF_SPEED, (8.5, 0.8, 2.4)), ("Walk", 1, REF_SPEED, (6.5, -6.5, 3.2)),
                                      ("Walk", 1, REF_SPEED, (0.0, -9.0, 2.2)), ("Idle", 1, 0.0, (6.5, -6.5, 3.0))):
        action = bpy.data.actions[clip]
        arm.animation_data.action = action
        length = int(round((WALK_PERIOD if clip == "Walk" else IDLE_PERIOD) * FPS))
        tag = "%s_%d_%d" % (clip.lower(), int(view[0]), int(view[1]))
        for k in range(length * cycles):
            sc.frame_set(k % length)
            y = -speed * k / FPS
            arm.location = (0, y, 0)
            cam.location = (view[0], y + view[1], view[2])
            cam.rotation_euler = (Vector((0, y - 0.3, 1.1)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(out_dir, "%s_%04d.png" % (tag, k))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    arm.location = (0, 0, 0)


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    mesh = load(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    kinds = classify(mesh, parts(mesh))
    repose(mesh, kinds)
    arm = build_armature()
    skin(mesh, arm, kinds)
    pose = Pose(arm)
    legs = make_legs()
    for b, ls in legs.items():
        for leg in ls.values():
            print(f"{leg.b}_{leg.name}: {leg.l1:.2f} + {leg.l2:.2f} + {leg.l3:.2f} m")
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
    print(f"exported {args.output}: {len(arm.data.bones)} bones, walk at {REF_SPEED} m/s, "
          f"clips {[a.name for a in bpy.data.actions]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
