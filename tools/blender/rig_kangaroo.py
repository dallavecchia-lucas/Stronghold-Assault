"""Rig and animate the Kangaroo Commando. The Meshy export comes with an auto-rig (SmartRigArmature)
and no clips, standing crouched as a kangaroo does before a hop: body level, tail out behind, long
hind feet flat on the ground and the short forelimbs hanging under the chest.

The auto-rig's weights are kept for the body, head, tail and hind legs: its bones are rebuilt in the
same places with clean names (hips, spine, chest, thigh_L ...) and their weights carried over. Its
arm chains are no good: they sit in the side-mounted SMGs, and the real forelimbs hang lower, skinned
to finger tips and to the hind feet's toes. They are replaced by upperarm / forearm / paw chains down
the forelimbs, re-skinned along them. All the gear rides rigidly on one bone each: the SMGs (with
their magazines and stocks) on the chest, the gun on the back on the spine, the supply pack and its
two ammo boxes on the hips, the goggles on the head. `muzzle_L` / `muzzle_R` mark the SMGs' muzzles
(their Y axis out of the barrel) and `grenade` the right paw's grip, where the flash grenade sits
(no weights). The model is scaled to HEIGHT with its origin between the hind feet.

Clips (FPS frames per second):
  Idle   the crouched stance: breathing, the head looking round, ears up, the tail resting on the
         ground and swaying, the forepaws held up in front of the chest.
  Hop    one hop of a kangaroo at speed, authored travelling at HOP_SPEED (UnitTypes anim_ref_speed):
         both feet land together ahead of the hips and sweep back under the body planted (IK), the
         hips sinking as the legs fold; they push off from the toes, the legs stretched out behind,
         then fold up and swing forward through a long flight, and reach down for the next landing.
         The tail swings against the legs (down as they push back, up as they swing forward), the
         body pitches up into the push and down into the landing, the head stays level and the
         forepaws ride tucked in at the chest.
  Throw  (not looped) the flash grenade: the kangaroo rears up on its hind feet like a boxer, its
         tail reaching back to prop it, forepaws up in a guard and bouncing on its toes; leans back
         winding up, the right paw cocked beside its ear, then snaps forward through the throw (the
         grenade leaves the paw THROW_RELEASE seconds in), follows through and drops back down onto
         the crouch.

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_kangaroo.py -- \\
      --input assets_src/units/kangaroo_commando/kangaroo_commando_rigged_meshy.glb \\
      --output game/assets/units/kangaroo_commando/kangaroo_commando_rigged.glb [--preview DIR]

--preview renders the rest pose, every clip (the hop travelling at its speed) into DIR as PNG frames.
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
HEIGHT = 2.0  # meters, ear tips to toes, as for the earlier files

# Positions below are in the Meshy export as imported: front -Y, up +Z, the kangaroo's left +X, feet
# at z 0, 1.7 m tall. Model moves and scales the mesh into the game frame (origin between the hind
# feet, HEIGHT tall); place() does the same to a point.
#
# Auto-rig bones -> new bones (their weights are summed). Meshy names the bones by number.
GROUPS = {
    "hips": ["Bone_000", "Bone_001"],
    "spine": ["Bone_004", "Bone_003"],
    "chest": ["Bone_002"],
    "neck": ["Bone_032"],
    "head": ["Bone_031", "Bone_030"],
    "thigh_L": ["Bone_014"], "shin_L": ["Bone_013"], "foot_L": ["Bone_012"], "toe_L": ["Bone_011", "Bone_010"],
    "thigh_R": ["Bone_009"], "shin_R": ["Bone_008"], "foot_R": ["Bone_007"], "toe_R": ["Bone_006", "Bone_005"],
    "tail_1": ["Bone_019"], "tail_2": ["Bone_018"], "tail_3": ["Bone_017"], "tail_4": ["Bone_016"],
    "tail_5": ["Bone_015"],
}
# The auto-rig's arm chains (shoulder, arm, forearm, hand, palm and four fingers a side): what they
# hold that isn't forelimb goes to the chest.
OLD_ARMS = ["Bone_%03d" % k for k in list(range(20, 25)) + list(range(25, 30)) + list(range(33, 62))]
# Old joints the new bones run between: an auto-rig bone's head, or "<bone>.tail".
SKELETON = [
    ("hips", None, "Bone_000", "Bone_004"),
    ("spine", "hips", "Bone_004", "Bone_002"),
    ("chest", "spine", "Bone_002", "Bone_032"),
    ("neck", "chest", "Bone_032", "Bone_031"),
    ("head", "neck", "Bone_031", "Bone_030.tail"),
    ("thigh_L", "hips", "Bone_014", "Bone_013"),
    ("shin_L", "thigh_L", "Bone_013", "Bone_012"),
    ("foot_L", "shin_L", "Bone_012", "Bone_011"),
    ("toe_L", "foot_L", "Bone_011", "Bone_010.tail"),
    ("thigh_R", "hips", "Bone_009", "Bone_008"),
    ("shin_R", "thigh_R", "Bone_008", "Bone_007"),
    ("foot_R", "shin_R", "Bone_007", "Bone_006"),
    ("toe_R", "foot_R", "Bone_006", "Bone_005.tail"),
    ("tail_1", "hips", "Bone_019", "Bone_018"),
    ("tail_2", "tail_1", "Bone_018", "Bone_017"),
    ("tail_3", "tail_2", "Bone_017", "Bone_016"),
    ("tail_4", "tail_3", "Bone_016", "Bone_015"),
    ("tail_5", "tail_4", "Bone_015", "Bone_015.tail"),
]
TAIL = ["tail_1", "tail_2", "tail_3", "tail_4", "tail_5"]
LEG = {s: ("thigh_" + s, "shin_" + s, "foot_" + s, "toe_" + s) for s in "LR"}
ARM = {s: ("upperarm_" + s, "forearm_" + s, "paw_" + s) for s in "LR"}
# The left forelimb's joints (the right one mirrors it): shoulder (inside the chest, above the
# armpit), elbow, wrist and the tips of the curled fingers. The forelimb hangs under the chest.
FORELIMB = [(0.205, -0.765, 0.90), (0.200, -0.755, 0.63), (0.160, -0.725, 0.455), (0.140, -0.645, 0.355)]
# Around the forelimb below the chest it is all forelimb; up its upper bone, inside the chest, it
# fades into the chest by ARMPIT_Z.
LIMB_R = (0.085, 0.13)
ARMPIT_Z = (0.74, 0.86)
# The left ear's base and tip (the right one mirrors it): above EAR_Z[0] (and out past EAR_X, within
# EAR_Y) the head blends into the ear, all ear past EAR_Z[1].
EAR = [(0.125, -1.22, 1.495), (0.30, -1.24, 1.69)]
EAR_X = 0.07
EAR_Y = (-1.34, -1.12)
EAR_Z = (1.49, 1.555)
# Gear pieces by where they sit: on the head (goggles) in front of HEAD_Y, the SMGs (and their
# magazines and stocks) out past SMG_X in front of SMG_Y; on the back, the pack and its boxes behind
# PACK_Y ride the hips, the gun in front of it and its mount the spine.
HEAD_Y = -1.1
SMG_X = 0.3
SMG_Y = -0.35
PACK_Y = -0.25


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
    return Vector((p[0] if side == "L" else -p[0], p[1], p[2]))


# ---------------------------------------------------------------- load and rebuild

class Model:
    """The export moved to its game frame: origin between the hind feet, HEIGHT tall, front -Y."""

    def __init__(self, path):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        junk = bpy.data.objects.get("Icosphere")  # stray helper mesh in the Meshy export
        if junk:
            bpy.data.objects.remove(junk, do_unlink=True)
        self.mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
        old = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
        self.joints = {}
        for b in old.data.bones:
            self.joints[b.name] = old.matrix_world @ b.head_local
            self.joints[b.name + ".tail"] = old.matrix_world @ b.tail_local
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
        feet = co[co[:, 2] < lo + 0.1 * (hi - lo)]
        c = feet.mean(axis=0)
        self.shift = Vector((c[0], c[1], lo))

    def place(self, p) -> Vector:
        """A point in the export's frame, moved and scaled like the mesh."""
        return (Vector(p) - self.shift) * self.scale

    def move_mesh(self):
        me = self.mesh.data
        co = np.array([v.co for v in me.vertices])
        co = (co - np.array(self.shift)) * self.scale
        me.vertices.foreach_set("co", co.ravel())
        me.update()


def read_weights(mesh):
    """Per vertex {auto-rig bone: weight}."""
    names = {g.index: g.name for g in mesh.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups if g.weight > 0.0} for v in mesh.data.vertices]


def classify(co, pieces):
    """{piece index: bone} for the gear: every piece but the body (the largest) rides one bone."""
    out = {}
    for k, p in enumerate(pieces[1:], 1):
        c = co[p].mean(axis=0)
        if c[1] < HEAD_Y:
            out[k] = "head"
        elif abs(c[0]) > SMG_X and c[1] < SMG_Y:
            out[k] = "chest"  # an SMG: the gun, its magazine or its stock
        elif c[1] > PACK_Y:
            out[k] = "hips"  # the supply pack, its ammo boxes and straps
        else:
            out[k] = "spine"  # the gun on the back, its sight and its mount
    return out


def smg_muzzles(co, pieces, kinds):
    """{side: (muzzle point, barrel direction)} of the two SMGs (export frame): each side's biggest
    chest piece is the gun; its muzzle is the middle of its front end, its barrel its long axis."""
    out = {}
    for side, sx in (("L", 1.0), ("R", -1.0)):
        guns = [pieces[k] for k, b in kinds.items() if b == "chest" and co[pieces[k]].mean(axis=0)[0] * sx > SMG_X]
        gun = co[max(guns, key=len)]
        m = gun.mean(axis=0)
        _, _, vt = np.linalg.svd(gun - m)
        d = vt[0] if vt[0][1] < 0 else -vt[0]  # pointing forward (-Y)
        t = (gun - m) @ d
        tip = gun[t > t.max() - 0.03].mean(axis=0)
        out[side] = (Vector(tip), Vector(d).normalized())
    return out


def forelimb_weights(q, side):
    """(pull, weights) of one forelimb for a point (export frame): all forelimb below the chest, fading
    into the chest up the upper arm; along the limb, upperarm -> forearm -> paw."""
    j = [mirror(p, side) for p in FORELIMB]
    w, dist = chain_weights(q, j, list(ARM[side]), 0.05)
    pull = smooth(LIMB_R[1], LIMB_R[0], dist) * smooth(ARMPIT_Z[1], ARMPIT_Z[0], q.z)
    return pull, w


def reweight(model, pieces, kinds):
    """New weights for every vertex: the body's carried over from the auto-rig (old arm bones going
    to the chest), the forelimbs re-skinned along their new chains, the gear rigid."""
    mesh = model.mesh
    old = read_weights(mesh)
    to_new = {o: n for n, olds in GROUPS.items() for o in olds}
    weights = [None] * len(old)
    for k, bone in kinds.items():
        for i in pieces[k]:
            weights[i] = {bone: 1.0}
    limb = 0
    for i in pieces[0]:
        nw = {}
        for o, x in old[i].items():
            name = to_new.get(o, "chest")
            nw[name] = nw.get(name, 0.0) + x
        q = Vector(mesh.data.vertices[i].co)
        side = "L" if q.x > 0 else "R"
        pull, lw = forelimb_weights(q, side)
        if pull > 0.0:
            limb += 1
            total = sum(nw.values())
            nw = mix({n: x / total for n, x in nw.items()}, lw, pull)
        if abs(q.x) > EAR_X and EAR_Y[0] < q.y < EAR_Y[1] and q.z > EAR_Z[0]:
            total = sum(nw.values())
            nw = mix({n: x / total for n, x in nw.items()}, {"ear_" + side: 1.0}, smooth(EAR_Z[0], EAR_Z[1], q.z))
        weights[i] = nw
    print(f"forelimbs: {limb} vertices re-skinned; gear: "
          + ", ".join(f"{b} {sum(len(pieces[k]) for k, kb in kinds.items() if kb == b)}" for b in ("head", "chest", "spine", "hips")))
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


def build_armature(model, muzzles):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, parent, head, tail, deform=True):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.align_roll(Vector((1, 0, 0)))  # every bone's Z axis toward the kangaroo's left
        if parent:
            b.parent = eb[parent]
        b.use_deform = deform
        return b

    for name, parent, a, b in SKELETON:
        bone(name, parent, model.place(model.joints[a]), model.place(model.joints[b]))
    for side in "LR":
        j = [model.place(mirror(p, side)) for p in FORELIMB]
        names = ARM[side]
        bone(names[0], "chest", j[0], j[1])
        bone(names[1], names[0], j[1], j[2])
        bone(names[2], names[1], j[2], j[3])
        tip, d = muzzles[side]
        m = model.place(tip)
        bone("muzzle_" + side, "chest", m, m + d * 0.15, deform=False)
        bone("ear_" + side, "head", model.place(mirror(EAR[0], side)), model.place(mirror(EAR[1], side)))
    # The grenade sits in the right paw's grip, between the palm and the curled fingers.
    w, p = (model.place(mirror(FORELIMB[k], "R")) for k in (2, 3))
    grip = w.lerp(p, 0.55) + Vector((0.0, -0.035, 0.0))
    bone("grenade", "paw_R", grip, grip + (p - w).normalized() * 0.08, deform=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bind(mesh, arm):
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mesh.parent = arm


# ---------------------------------------------------------------- posing

X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
RAD = math.pi / 180
HINGE = Vector((1, 0, 0))  # legs and forelimbs fold about X: also the bones' twist reference
# A turn about +X carries back -> up -> front -> down: it pitches the nose down, lifts the tail,
# tips an ear forward and swings a hanging forelimb back.


def turn_x(angle, v):
    return Matrix.Rotation(angle, 3, "X") @ v


def tilt(pose, name, deg):
    """Turns a bone about X by `deg` degrees (see above)."""
    pose.turn(name, X, deg * RAD)


def aim_bone(pose, name, head, tail):
    """Poses a bone to run from `head` toward `tail` (armature space), keeping its twist about X."""
    r = pose.rest[name]
    rest_y = r.to_3x3() @ Vector((0, 1, 0))
    q = aim_frame((tail - head).normalized(), HINGE) @ aim_frame(rest_y, HINGE).inverted()
    pose.place(name, Matrix.Translation(head) @ (q @ r.to_3x3()).to_4x4())


def ease(e0, e1, x):
    """0 before e0, 1 after e1, easing in and out between (smooth's hermite)."""
    return smooth(e0, e1, x) if e1 > e0 else float(x >= e1)


class HindLeg:
    """One hind leg's measurements and the IK that poses it. The foot goes by its ball (where foot
    and toes meet: what it rolls over) and two pitches: the foot's, heel up from level, and the
    toes', tip down to the front, both in degrees in the armature's frame. Thigh and shin reach the
    ankle that leaves, the knee bending forward."""

    def __init__(self, pose, side):
        self.bones = LEG[side]
        hip, knee, ankle, ball = (pose.rest[b].translation.copy() for b in self.bones)
        self.l1, self.l2 = (knee - hip).length, (ankle - knee).length
        self.ball0 = ball
        self.foot_v = ankle - ball  # ball -> ankle at rest: back and up
        self.toe_v = pose.tail[self.bones[3]] - ball  # ball -> toe tip at rest: forward, a little down
        self.foot0 = math.degrees(math.atan2(self.foot_v.z, self.foot_v.y))
        self.toe0 = math.degrees(math.atan2(-self.toe_v.z, -self.toe_v.y))
        self.pole = Vector((0.08 if side == "L" else -0.08, -1.0, 0.0)).normalized()

    def ankle(self, ball, foot):
        return ball + turn_x((foot - self.foot0) * RAD, self.foot_v)

    def reach(self, pose, ball, foot):
        """Length (m) the leg has to spare reaching that ball: negative if it can't."""
        return self.l1 + self.l2 - (self.ankle(ball, foot) - pose.head(self.bones[0])).length

    def solve(self, pose, ball, foot, toe):
        """Poses the leg with the ball at `ball`, the foot pitched `foot` degrees heel up and the toes
        `toe` degrees tip down. Returns how far from `ball` it ended up (out of reach)."""
        thigh, shin, fb, tb = self.bones
        hip = pose.head(thigh)
        fv = turn_x((foot - self.foot0) * RAD, self.foot_v)
        knee, end = two_bone(hip, self.l1, self.l2, ball + fv, self.pole)
        aim_bone(pose, thigh, hip, knee)
        aim_bone(pose, shin, knee, end)
        got = end - fv
        aim_bone(pose, fb, end, got)
        aim_bone(pose, tb, got, got + turn_x((toe - self.toe0) * RAD, self.toe_v))
        return (got - ball).length


def lowest(pose, names):
    """Lowest point (z) along the bones (their heads and tails, posed)."""
    out = 9.0
    for n in names:
        w = pose.world(n)
        out = min(out, w.translation.z, (w @ pose.rest[n].inverted() @ pose.tail[n]).z)
    return out


def animated(arm):
    return [b.name for b in arm.data.bones if b.use_deform]


# ---------------------------------------------------------------- hop

HOP_SPEED = 7.2  # m/s: the ground speed the hop is authored for (UnitTypes anim_ref_speed)
HOP_PERIOD = 16.0 / FPS  # seconds per hop (whole frames): kangaroos hop at about the same rate whatever their speed
HOP_DUTY = 0.27  # share of the hop the feet are on the ground
GRAVITY = 9.81
HOP_SWEEP = HOP_SPEED * HOP_PERIOD * HOP_DUTY  # how far the planted feet travel back under the body
HOP_LAND = 0.62  # the balls of the feet land this far ahead of the hip joints (m)
HOP_RISE = 0.02  # hips at touchdown and take-off, above their rest height (m)
HOP_FOOT = (34.0, 22.0, 72.0)  # foot pitch at touchdown, mid-stance and take-off (degrees heel up)
HOP_TUCK = 2.0  # foot pitch with the leg folded mid-flight
HOP_LIFT = 0.42  # how high the balls of the feet ride mid-flight (m)
HOP_PITCH = 7.0  # body pitch, nose up into the push and down into the landing (degrees)
HOP_TAIL = (12.0, 9.0, 7.0, 6.0, 5.0)  # tail swing, base to tip (degrees)
HOP_TAIL_HOLD = (10.0, 2.0, 6.0, 4.0, 2.0)  # and how far the tail is held up throughout
HOP_TAIL_LAG = 0.06  # share of a hop the swing takes to run down each tail bone


def hop_hips(u):
    """(height above rest, pitch nose up in degrees) of the hips u of the way through a hop, u = 0
    at touchdown: they sink as the legs fold under the landing, then fly a ballistic arc."""
    ts, tf = HOP_PERIOD * HOP_DUTY, HOP_PERIOD * (1.0 - HOP_DUTY)
    v_up = GRAVITY * tf / 2.0
    if u < HOP_DUTY:
        # Falling at v_up at touchdown, rising at v_up at take-off, lowest between.
        z = HOP_RISE - v_up * ts / math.pi * math.sin(math.pi * u / HOP_DUTY)
    else:
        t = (u - HOP_DUTY) * HOP_PERIOD
        z = HOP_RISE + v_up * t - 0.5 * GRAVITY * t * t
    return z, HOP_PITCH * math.cos(2 * math.pi * (u - HOP_DUTY))


def hop_foot(leg, hip_y, u):
    """(ball, foot pitch, toe pitch) u of the way through a hop. Planted, the ball travels back at the
    ground's speed while the heel sinks and rises again, rolling up onto the toes to push off. In
    the air the leg folds up and swings forward, and reaches down to land moving with the ground."""
    y_land = hip_y - HOP_LAND
    y_off = y_land + HOP_SWEEP
    z0 = leg.ball0.z
    f_land, f_mid, f_off = HOP_FOOT
    if u < HOP_DUTY:
        s = u / HOP_DUTY
        foot = f_land + (f_mid - f_land) * ease(0.0, 0.4, s) + (f_off - f_mid) * ease(0.4, 1.0, s) ** 1.3
        return Vector((leg.ball0.x, y_land + HOP_SWEEP * s, z0)), foot, leg.toe0
    s = (u - HOP_DUTY) / (1.0 - HOP_DUTY)
    v = HOP_SWEEP * (1.0 - HOP_DUTY) / HOP_DUTY  # the ground's travel, per flight
    y = hermite(y_off, y_land, 0.45 * v, v, s)
    z = z0 + HOP_LIFT * math.sin(math.pi * s) ** 0.9
    foot = f_off + (HOP_TUCK - f_off) * ease(0.0, 0.45, s) + (f_land - HOP_TUCK) * ease(0.5, 1.0, s)
    # The toes trail as the foot leaves, straighten out with it in the air and spread to land.
    toe = leg.toe0 + (foot - 6.0 - leg.toe0) * math.sin(math.pi * s) ** 0.7
    return Vector((leg.ball0.x, y, z)), foot, toe


def pose_hop(pose, legs, u):
    z, pitch = hop_hips(u)
    pose.move("hips", (0, 0, z))
    tilt(pose, "hips", -pitch)
    # The back arches into the push and the head stays level.
    arch = 2.5 * math.cos(2 * math.pi * (u - HOP_DUTY - 0.05))
    tilt(pose, "spine", -arch)
    tilt(pose, "neck", 0.5 * (pitch + arch) - 2.0)
    tilt(pose, "head", 0.5 * (pitch + arch) + 1.5 * math.sin(2 * math.pi * (u - 0.1)) + 2.0)
    # Ears laid back and fluttering.
    for side, ph in (("L", 0.0), ("R", 0.07)):
        tilt(pose, "ear_" + side, -24.0 - 4.0 * math.sin(2 * math.pi * (u - 0.15 - ph)))
    # Tail: down as the legs push back, up as they swing forward, the swing running down it.
    for k, name in enumerate(TAIL):
        tilt(pose, name, HOP_TAIL_HOLD[k] + HOP_TAIL[k] * math.cos(2 * math.pi * (u - HOP_DUTY - 0.5 - k * HOP_TAIL_LAG)))
    # Forepaws tucked in at the chest, riding with each bound.
    for side in "LR":
        upper, fore, paw = ARM[side]
        tilt(pose, upper, -32.0 - 5.0 * math.sin(2 * math.pi * (u - 0.25)))
        tilt(pose, fore, -72.0 + 6.0 * math.sin(2 * math.pi * (u - 0.3)))
        tilt(pose, paw, -20.0)
    keep_tail_up(pose, TAIL_FLOOR["hop"])
    worst = 0.0
    hip_y = pose.head(legs["L"].bones[0]).y
    for leg in legs.values():
        ball, foot, toe = hop_foot(leg, hip_y, u)
        worst = max(worst, leg.solve(pose, ball, foot, toe))
    return worst


def bake_hop(arm, pose, legs):
    frames = int(round(HOP_PERIOD * FPS))
    names = animated(arm)
    worst, low_tail, low_ball = 0.0, 9.0, 9.0
    _start(arm, "Hop")
    for f in range(frames + 1):
        u = (f / frames) % 1.0
        pose.reset()
        worst = max(worst, pose_hop(pose, legs, u))
        low_tail = min(low_tail, lowest(pose, TAIL))
        if u > HOP_DUTY + 0.05:
            low_ball = min(low_ball, min(pose.world(leg.bones[3]).translation.z for leg in legs.values()))
        pose.key(arm, f, names)
    _finish(arm)
    print(f"hop: {frames} frames at {HOP_SPEED} m/s, stride {HOP_SPEED * HOP_PERIOD:.2f} m, sweep {HOP_SWEEP:.2f} m, "
          f"hips {hop_hips(HOP_DUTY / 2)[0]:+.3f}..{hop_hips(HOP_DUTY + (1 - HOP_DUTY) / 2)[0]:+.3f} m, "
          f"worst foot miss {worst * 100:.1f} cm, lowest tail {low_tail * 100:.0f} cm, lowest ball in the air {low_ball * 100:.0f} cm")


# ---------------------------------------------------------------- idle

IDLE_PERIOD = 6.0


def crouch_paws(pose, side, lift=1.0):
    """Forepaws held up in front of the chest (lift 1) rather than hanging (0)."""
    upper, fore, paw = ARM[side]
    tilt(pose, upper, -22.0 * lift)
    tilt(pose, fore, -58.0 * lift)
    tilt(pose, paw, -18.0 * lift)


def stand(pose, legs):
    """Feet planted flat where they stand at rest."""
    worst = 0.0
    for leg in legs.values():
        worst = max(worst, leg.solve(pose, leg.ball0, leg.foot0, leg.toe0))
    return worst


def bake_idle(arm, pose, legs):
    frames = int(round(IDLE_PERIOD * FPS))
    names = animated(arm)
    T = IDLE_PERIOD
    _start(arm, "Idle")
    worst = 0.0
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        breath = math.sin(2 * math.pi * 3 * t / T)
        pose.move("hips", (0, 0, -0.012 + 0.006 * breath))
        tilt(pose, "hips", 0.8 * wave(t, T, 1, 0.2))
        tilt(pose, "spine", -1.2 * breath)
        # The head looks round slowly, then quickly the other way, and nods.
        look = 24.0 * lowpass([wave(k / FPS, T, 1, 0.1) + 0.45 * wave(k / FPS, T, 2, 0.3) for k in range(frames)], 3)[f % frames]
        pose.turn("neck", Z, 0.4 * look * RAD)
        pose.turn("head", Z, 0.6 * look * RAD)
        tilt(pose, "head", 5.0 * wave(t, T, 2, 0.15) - 3.0)
        # Ears up, turning to listen and flicking now and then.
        for side, ph in (("L", 0.0), ("R", 0.37)):
            flick = math.exp(-((((t / T + ph) % 0.5) - 0.18) / 0.025) ** 2)
            pose.turn("ear_" + side, Z, (12.0 * wave(t, T, 1, 0.25 + ph) + (1 if side == "L" else -1) * 6.0) * RAD)
            tilt(pose, "ear_" + side, -6.0 - 18.0 * flick)
        # The tail lies along the ground, its tip curling and swaying.
        for k, name in enumerate(TAIL):
            pose.turn(name, Z, (2.0 + 2.5 * k) * wave(t, T, 1, 0.05 * k) * RAD)
            tilt(pose, name, (-9.0, -3.0, 4.0, 8.0, 8.0)[k] + 1.5 * k * wave(t, T, 2, 0.4 + 0.06 * k))
        keep_tail_up(pose, TAIL_FLOOR["idle"])
        for side, ph in (("L", 0.0), ("R", 0.5)):
            crouch_paws(pose, side, 0.8 + 0.1 * wave(t, T, 1, ph))
        worst = max(worst, stand(pose, legs))
        pose.key(arm, f, names)
    _finish(arm)
    print(f"idle: {frames} frames, worst foot miss {worst * 100:.1f} cm, lowest tail {lowest(pose, TAIL) * 100:.0f} cm")


# ---------------------------------------------------------------- throw

# The flash grenade, in seconds into the clip. The kangaroo rears up on its hind feet and tail like a
# boxer (by GUARD), forepaws up; leans back, winding the chest to the right with the right paw cocked
# back behind its head (COCK); snaps forward through the throw, the grenade leaving the paw at
# THROW_RELEASE (UnitTypes flash_release), and follows through (FOLLOW); then drops back down onto
# the crouch, done at THROW_END (flash_time).
THROW_GUARD = 0.40
THROW_COCK = 0.84
THROW_RELEASE = 0.95
THROW_FOLLOW = 1.10
THROW_END = 1.62
UPRIGHT = 62.0  # how far the hips rear up (degrees, nose up); the back straightens the rest
UP_HIPS = 0.10  # and how much they rise, as far as the legs reach (m)
UP_HEEL = 30.0  # standing tall, up on the balls of the feet a little (foot pitch, degrees)
# Keys: (time, values). Body: (up 0..1, lean forward of upright, twist to the left), degrees.
THROW_BODY = [(0.0, (0, 0, 0)), (THROW_GUARD, (1, 0, 0)), (0.55, (1, 0, 0)), (THROW_COCK, (1, -10, -16)),
              (THROW_RELEASE, (1, 20, 13)), (THROW_FOLLOW, (1, 28, 9)), (THROW_END, (0, 0, 0))]
# Forelimbs: (upper arm, forearm, paw) tilts in the chest's frame, degrees. Crouched, the paws are
# held at the chest (crouch_paws); reared up, a boxer's guard. The right one cocks back behind the
# head, whips over and through; the left one points the way, then pulls back into the guard.
CROUCH_ARM = (-17.6, -46.4, -14.4)
GUARD_ARM = (52.0, -95.0, -10.0)
THROW_ARM = {
    "R": [(0.0, CROUCH_ARM), (THROW_GUARD, GUARD_ARM), (0.55, GUARD_ARM), (THROW_COCK, (-93.0, -125.0, -30.0)),
          (THROW_RELEASE, (-78.0, -25.0, -10.0)), (THROW_FOLLOW, (-6.0, -15.0, 0.0)), (THROW_END, CROUCH_ARM)],
    "L": [(0.0, CROUCH_ARM), (THROW_GUARD, GUARD_ARM), (0.55, GUARD_ARM), (THROW_COCK, (2.0, -20.0, 0.0)),
          (THROW_RELEASE, (40.0, -90.0, -10.0)), (THROW_FOLLOW, GUARD_ARM), (THROW_END, CROUCH_ARM)],
}
TAIL_PROP = (70.0, 4.0, -24.0, 13.0, 5.0)  # reared up, the tail reaches back and down to prop it, its end along the ground
TAIL_FLOOR = {"hop": 0.13, "throw": 0.075, "idle": 0.075}  # lowest the tail's bones come (m)


def keyed(keys, t):
    """Values at time t between (time, values) keys, easing in and out of each."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            w = smooth(t0, t1, t)
            return tuple(x + (y - x) * w for x, y in zip(a, b))
    return keys[-1][1]


def keep_tail_up(pose, floor):
    """Lifts the tail at its root until no bone of it comes lower than `floor`."""
    for _ in range(20):
        if lowest(pose, TAIL) >= floor:
            return
        tilt(pose, TAIL[0], 1.5)


def fit_hips(pose, legs, feet):
    """Lowers the hips until each leg reaches its foot: feet[side] = (ball, foot pitch)."""
    for _ in range(4):
        short = max(-legs[s].reach(pose, *feet[s]) for s in legs)
        if short <= 0.002:
            return
        pose.move("hips", (0, 0, -short - 0.004))


def bake_throw(arm, pose, legs):
    frames = int(round(THROW_END * FPS))
    names = animated(arm)
    _start(arm, "Throw")
    worst, low_tail = 0.0, 9.0
    for f in range(frames + 1):
        t = f / FPS
        up, lean, twist = keyed(THROW_BODY, t)
        # A boxer's bounce on the toes in the guard.
        bounce = math.sin(2 * math.pi * (t - THROW_GUARD) / 0.3) * smooth(0.36, 0.44, t) * (1.0 - smooth(0.6, THROW_COCK, t))
        pose.reset()
        pose.move("hips", (0, 0, UP_HIPS * up + 0.015 * bounce))
        tilt(pose, "hips", -UPRIGHT * up + 0.7 * lean)
        tilt(pose, "spine", -6.0 * up + 0.3 * lean)
        tilt(pose, "chest", -4.0 * up)
        pose.turn("spine", Y, 0.4 * twist * RAD)
        pose.turn("chest", Y, 0.6 * twist * RAD)
        # The head stays on the target: level, facing ahead against the twist.
        rear = (UPRIGHT + 10.0) * up - lean
        tilt(pose, "neck", 0.45 * rear)
        tilt(pose, "head", 0.45 * rear + 4.0 * up)
        pose.turn("neck", Y, -0.5 * twist * RAD)
        pose.turn("head", Y, -0.4 * twist * RAD)
        for side in "LR":
            tilt(pose, "ear_" + side, -6.0 - 8.0 * up)
            for name, deg in zip(ARM[side], keyed(THROW_ARM[side], t)):
                tilt(pose, name, deg)
        for k, name in enumerate(TAIL):
            tilt(pose, name, TAIL_PROP[k] * up)
        keep_tail_up(pose, TAIL_FLOOR["throw"])
        feet = {s: (leg.ball0, leg.foot0 + (UP_HEEL - leg.foot0) * up) for s, leg in legs.items()}
        fit_hips(pose, legs, feet)
        for s, leg in legs.items():
            worst = max(worst, leg.solve(pose, *feet[s], leg.toe0))
        low_tail = min(low_tail, lowest(pose, TAIL))
        pose.key(arm, f, names)
    _finish(arm)
    print(f"throw: {frames} frames, release at {THROW_RELEASE:.2f} s, worst foot miss {worst * 100:.1f} cm, "
          f"lowest tail {low_tail * 100:.0f} cm")


# ---------------------------------------------------------------- preview

def render_preview(arm, out_dir):
    """The rest pose from all round; the hop travelling at HOP_SPEED from the side and three quarters
    (two hops, tracked by the camera); the throw from the right front and from an RTS camera's
    height; the idle every few frames."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"  # clay: the camouflage textures are dark
    sc.display.shading.single_color = (0.78, 0.74, 0.68)
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 800, 600
    sc.render.image_settings.file_format = "PNG"
    ground = bpy.data.materials.new("ground")
    ground.diffuse_color = (0.35, 0.42, 0.3, 1)
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, -25, 0))
    bpy.context.object.data.materials.append(ground)
    for j in range(-60, 10):
        for x in (1.2, -1.2):
            bpy.ops.mesh.primitive_cube_add(size=0.06, location=(x, j * 0.5, 0.03))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50

    def shoot(path, at, d, dist):
        cam.location = at + Vector(d).normalized() * dist
        cam.rotation_euler = (at - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)

    arm.animation_data_create()
    centre = Vector((0, 0.2, 1.0))
    for name, d in (("side", (1, 0, 0.12)), ("front", (0, -1, 0.15)), ("persp", (0.8, -0.9, 0.5)), ("back", (-0.6, 1, 0.4))):
        shoot(os.path.join(out_dir, "rest_%s.png" % name), centre, d, 6.5)
    hop = int(round(HOP_PERIOD * FPS))
    arm.animation_data.action = bpy.data.actions["Hop"]
    for view, d in (("side", (1, 0, 0.08)), ("persp", (0.75, -0.75, 0.35))):
        for k in range(hop * 2):
            sc.frame_set(k % hop)
            y = -HOP_SPEED * k / FPS
            arm.location = (0, y, 0)
            shoot(os.path.join(out_dir, "hop_%s_%04d.png" % (view, k)), Vector((0, y + 0.1, 1.2)), d, 6.5)
    arm.location = (0, 0, 0)
    for clip, step, view, d, h, dist in (("Throw", 2, "right", (-0.8, -0.75, 0.15), 1.6, 7.0),
                                         ("Throw", 4, "rts", (-0.5, 0.75, 1.0), 1.2, 9.0),
                                         ("Idle", 10, "persp", (0.75, -0.75, 0.35), 1.0, 6.0)):
        arm.animation_data.action = bpy.data.actions[clip]
        length = int(round((THROW_END if clip == "Throw" else IDLE_PERIOD) * FPS))
        for k in range(0, length + 1, step):
            sc.frame_set(k)
            shoot(os.path.join(out_dir, "%s_%s_%04d.png" % (clip.lower(), view, k)), Vector((0, 0.1, h)), d, dist)
    arm.animation_data.action = None


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    model = Model(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    mesh = model.mesh
    pieces = parts(mesh)
    co = np.array([v.co for v in mesh.data.vertices])
    kinds = classify(co, pieces)
    muzzles = smg_muzzles(co, pieces, kinds)
    weights = reweight(model, pieces, kinds)
    model.move_mesh()
    arm = build_armature(model, muzzles)
    apply_weights(mesh, weights)
    bind(mesh, arm)
    pose = Pose(arm)
    legs = {s: HindLeg(pose, s) for s in "LR"}
    for s, leg in legs.items():
        print(f"leg {s}: thigh {leg.l1:.3f} + shin {leg.l2:.3f} m, foot {leg.foot0:.1f} deg, toes {leg.toe0:.1f} deg")
    bake_idle(arm, pose, legs)
    bake_hop(arm, pose, legs)
    bake_throw(arm, pose, legs)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    g = arm.data.bones["grenade"].head_local
    print(f"exported {args.output}: scale {model.scale:.3f}, {len(arm.data.bones)} bones, "
          f"clips {[a.name for a in bpy.data.actions]}, grenade at rest {tuple(round(x, 3) for x in g)}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
