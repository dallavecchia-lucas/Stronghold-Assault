"""Rig and animate the Missile Trooper, the AA Squad's defender: the Armored Sentinel with a
six-missile pod on its left shoulder. The Meshy export comes with a Mixamo-style auto-rig in a
T-pose and a Running clip; the AA Squad walks any way while facing its aim, like the Gunner Squad,
so it gets the Heavy Gunner's eight walk clips instead (same speeds and timing, so the game blends
them the same way: SquadTrooper).

The auto-rig's skin weights are kept for the body: its bones are rebuilt in the same places with
the Heavy Gunner's clean names (pelvis, spine_1, thigh_L ...) and their weights carried over. The
pod is re-skinned rigidly: its housing follows `launcher` (a child of the chest, which the game
swings onto the aim), each missile follows its own `missile_<k>` bone (a child of `launcher`,
its head at the missile's nose and its Y axis along the tube) so the game can hide a missile once
it has left its tube and bring it back when the tube is reloaded. The mount the pod sits on stays
on the chest. The cables from the pod to the hip lose their pull from the left leg, so they hang
from the pod and the hips instead of riding the knee. The model is scaled to HEIGHT with its origin
under the hips.

Clips (FPS frames per second, keyed bones only; launcher and missiles are left to the game):
  Idle        breathing, a slow weight shift and a look around, the feet planted, arms at the sides.
  Walk_<dir>  eight directions, as rig_heavy_gunner.py: one cycle of WALK_PERIOD each, all in step,
              feet planted by IK; both arms swing against the legs.

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_missile_trooper.py -- \\
      --input assets_src/defenders/armored_sentinel/armored_sentinel_meshy.glb \\
      --output game/assets/defenders/armored_sentinel/missile_trooper_rigged.glb [--preview DIR]

--preview renders each clip (the walks travelling at their speed) into DIR as PNG frames.
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
from rig_elephant import Pose, _finish, _start, aim_frame, two_bone, wave  # noqa: E402
from rig_heavy_gunner import (  # noqa: E402
    ARM_SWING, DIRECTIONS, FPS, IDLE_PERIOD, LEG_BONES, RAD, ROLL, SWAY, WALK_PERIOD, YAW, Legs, X, Y, Z,
    apply_weights, hip_heights, pieces_of, read_weights, render_preview, stance, walk_params)

HEIGHT = 1.95  # meters, top of the helmet
# Extra half-width of the stance walking sideways (m): the Sentinel's feet sit closer together than
# the Heavy Gunner's, and would brush past each other.
SIDE_WIDEN = 0.1
# Knees a little bent: the hips sit this much lower than the straight-legged rest (the Sentinel's
# legs are bent at rest already, so less than the Heavy Gunner's).
CROUCH = 0.02
# Arms hang this far out from straight down (share of their reach to the side) and this straight.
ARM_OUT = 0.16
ARM_REACH = 0.94

# Auto-rig bones -> new bones (their weights are summed). Fingers go with the hand.
GROUPS = {
    "pelvis": ["mixamorig:Hips"],
    "spine_1": ["mixamorig:Spine"], "spine_2": ["mixamorig:Spine1"], "chest": ["mixamorig:Spine2"],
    "neck": ["mixamorig:Neck"], "head": ["mixamorig:Head", "mixamorig:HeadTop_End", "headfront"],
    "clavicle_L": ["mixamorig:LeftShoulder"], "upperarm_L": ["mixamorig:LeftArm"],
    "forearm_L": ["mixamorig:LeftForeArm"], "hand_L": ["mixamorig:LeftHand", "Bone_052"],
    "clavicle_R": ["mixamorig:RightShoulder"], "upperarm_R": ["mixamorig:RightArm"],
    "forearm_R": ["mixamorig:RightForeArm"], "hand_R": ["mixamorig:RightHand", "Bone_053"],
    "thigh_L": ["mixamorig:LeftUpLeg"], "shin_L": ["mixamorig:LeftLeg"], "foot_L": ["mixamorig:LeftFoot"],
    "toe_L": ["mixamorig:LeftToeBase", "mixamorig:LeftToe_End"],
    "thigh_R": ["mixamorig:RightUpLeg"], "shin_R": ["mixamorig:RightLeg"], "foot_R": ["mixamorig:RightFoot"],
    "toe_R": ["mixamorig:RightToeBase", "mixamorig:RightToe_End"],
    # The pod and the cables hanging from it.
    "launcher": ["Bone_017", "Bone_016", "Bone_033", "Bone_032", "Bone_035", "Bone_034"],
}
# The cable over the right shoulder and down the upper arm.
EXTRA = {"Bone_021": "clavicle_R", "Bone_020": "upperarm_R", "Bone_019": "upperarm_R", "Bone_018": "upperarm_R"}
POD_BONES = ("Bone_017", "Bone_016")
CABLE_BONES = ("Bone_034", "Bone_035", "Bone_033", "Bone_032")
# New bones: (name, parent, head joint, tail joint). A joint is an auto-rig bone's head; toes get
# their tail laid flat out in front (see build_armature).
SKELETON = [
    ("pelvis", None, "mixamorig:Hips", "mixamorig:Spine"),
    ("spine_1", "pelvis", "mixamorig:Spine", "mixamorig:Spine1"),
    ("spine_2", "spine_1", "mixamorig:Spine1", "mixamorig:Spine2"),
    ("chest", "spine_2", "mixamorig:Spine2", "mixamorig:Neck"),
    ("neck", "chest", "mixamorig:Neck", "mixamorig:Head"),
    ("head", "neck", "mixamorig:Head", "mixamorig:HeadTop_End"),
    ("clavicle_L", "chest", "mixamorig:LeftShoulder", "mixamorig:LeftArm"),
    ("upperarm_L", "clavicle_L", "mixamorig:LeftArm", "mixamorig:LeftForeArm"),
    ("forearm_L", "upperarm_L", "mixamorig:LeftForeArm", "mixamorig:LeftHand"),
    ("hand_L", "forearm_L", "mixamorig:LeftHand", "mixamorig:LeftHandMiddle1"),
    ("clavicle_R", "chest", "mixamorig:RightShoulder", "mixamorig:RightArm"),
    ("upperarm_R", "clavicle_R", "mixamorig:RightArm", "mixamorig:RightForeArm"),
    ("forearm_R", "upperarm_R", "mixamorig:RightForeArm", "mixamorig:RightHand"),
    ("hand_R", "forearm_R", "mixamorig:RightHand", "mixamorig:RightHandMiddle1"),
    ("thigh_L", "pelvis", "mixamorig:LeftUpLeg", "mixamorig:LeftLeg"),
    ("shin_L", "thigh_L", "mixamorig:LeftLeg", "mixamorig:LeftFoot"),
    ("foot_L", "shin_L", "mixamorig:LeftFoot", "mixamorig:LeftToeBase"),
    ("toe_L", "foot_L", "mixamorig:LeftToeBase", None),
    ("thigh_R", "pelvis", "mixamorig:RightUpLeg", "mixamorig:RightLeg"),
    ("shin_R", "thigh_R", "mixamorig:RightLeg", "mixamorig:RightFoot"),
    ("foot_R", "shin_R", "mixamorig:RightFoot", "mixamorig:RightToeBase"),
    ("toe_R", "foot_R", "mixamorig:RightToeBase", None),
]
MISSILES = 6
# The pod swings about the top of the mount it sits on (export meters).
POD_PIVOT = (0.35, 0.14, 1.37)
ARMS = ["clavicle_L", "upperarm_L", "forearm_L", "hand_L", "clavicle_R", "upperarm_R", "forearm_R", "hand_R"]
ANIMATED = ["pelvis", "spine_1", "spine_2", "chest", "neck", "head"] + ARMS + \
    [b for bones in LEG_BONES.values() for b in bones]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


def new_bone(old):
    """The new bone an auto-rig bone's weights go to."""
    if old in EXTRA:
        return EXTRA[old]
    for name, olds in GROUPS.items():
        if old in olds:
            return name
    for side, prefix in (("L", "mixamorig:LeftHand"), ("R", "mixamorig:RightHand")):
        if old.startswith(prefix):  # the fingers
            return "hand_" + side
    raise KeyError(old)


# ---------------------------------------------------------------- the pod

class Pod:
    """The pod's pieces: the mount it sits on, its housing and the six missiles (each a body and
    a nose cone, with small fins). Pieces are told apart by the auto-rig's weights (the pod hangs
    on Bone_017 / Bone_016) and their shape: missile bodies are the long thin pieces lying along
    the tubes; the mount is the box under the housing."""

    def __init__(self, mesh, pieces, weights):
        co = np.array([v.co for v in mesh.data.vertices])
        self.co = co
        pod = []
        for p in pieces[1:]:
            total = {}
            for i in p:
                for o, x in weights[i].items():
                    total[o] = total.get(o, 0.0) + x
            if sum(total.get(b, 0.0) for b in POD_BONES) / sum(total.values()) > 0.5:
                pod.append(p)
        bodies = []
        for p in pod:
            c = co[p]
            _, s, vt = np.linalg.svd(c - c.mean(axis=0))
            spread = s / math.sqrt(len(p))
            ext = (c - c.mean(axis=0)) @ vt[0]
            if 0.18 < ext.max() - ext.min() < 0.3 and spread[1] < 0.04 and 40 <= len(p) <= 80:
                bodies.append(p)
        assert len(bodies) == MISSILES, f"found {len(bodies)} missile bodies"
        axis = np.zeros(3)
        for p in bodies:
            c = co[p]
            _, _, vt = np.linalg.svd(c - c.mean(axis=0))
            axis += vt[0] if vt[0][1] < 0 else -vt[0]  # forward is -Y
        self.axis = axis / np.linalg.norm(axis)
        # Top row first, outer column first in each row.
        centres = [co[p].mean(axis=0) for p in bodies]
        order = sorted(range(MISSILES), key=lambda k: (-round(centres[k][2] / 0.035), -centres[k][0]))
        self.bodies = [bodies[k] for k in order]
        self.centres = [centres[k] for k in order]
        # Everything else in front of the housing goes with the missile whose line it is on.
        self.missiles = [list(p) for p in self.bodies]
        housing_front = min(float(co[p][:, 1].min()) for p in pod if len(p) > 300) if any(len(p) > 300 for p in pod) else 0.03
        self.housing, self.mount = [], []
        for p in pod:
            if any(p is b for b in self.bodies):
                continue
            m = co[p].mean(axis=0)
            if m[1] < housing_front - 0.01 and len(p) < 120:
                k = min(range(MISSILES), key=lambda k: self._off_line(m, k))
                self.missiles[k].extend(p)
            elif m[2] < POD_PIVOT[2]:
                self.mount.extend(p)
            else:
                self.housing.extend(p)
        self.tips = []
        for k in range(MISSILES):
            c = co[self.missiles[k]]
            along = (c - self.centres[k]) @ self.axis
            self.tips.append(self.centres[k] + self.axis * along.max())
        print(f"pod: {len(pod)} pieces, housing {len(self.housing)} verts, mount {len(self.mount)}, "
              f"missiles {[len(m) for m in self.missiles]} verts, axis {np.round(self.axis, 2)}")

    def _off_line(self, p, k):
        d = p - self.centres[k]
        return float(np.linalg.norm(d - self.axis * (d @ self.axis)))


def reweight(mesh, pieces, weights, pod):
    """New weights for every vertex: the body's carried over from the auto-rig, the pod rigid, the
    cables off the leg."""
    rigid = {}
    for i in pod.housing:
        rigid[i] = "launcher"
    for i in pod.mount:
        rigid[i] = "chest"
    for k, m in enumerate(pod.missiles):
        for i in m:
            rigid[i] = "missile_%d" % k
    cable = np.zeros(len(weights), bool)
    for p in pieces[1:]:
        total = {}
        for i in p:
            for o, x in weights[i].items():
                total[o] = total.get(o, 0.0) + x
        if sum(total.get(b, 0.0) for b in CABLE_BONES) / sum(total.values()) > 0.05:
            cable[p] = True
    out = []
    for i, w in enumerate(weights):
        if i in rigid:
            out.append({rigid[i]: 1.0})
            continue
        nw = {}
        for o, x in w.items():
            name = new_bone(o)
            if cable[i] and name in ("thigh_L", "shin_L", "foot_L", "toe_L"):
                name = "pelvis"
            nw[name] = nw.get(name, 0.0) + x
        out.append(nw or {"pelvis": 1.0})
    print(f"rigid: {len(rigid)} verts, cables off the leg: {int(cable.sum())} verts")
    return out


# ---------------------------------------------------------------- load and rebuild

class Model:
    """The export moved to its game frame: origin under the hips, HEIGHT tall, front -Y."""

    def __init__(self, path):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        junk = bpy.data.objects.get("Icosphere")
        if junk:
            bpy.data.objects.remove(junk, do_unlink=True)
        for a in list(bpy.data.actions):  # the export's Running clip
            bpy.data.actions.remove(a)
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
        self.scale = HEIGHT / (co[:, 2].max() - co[:, 2].min())
        hips = self.joints["mixamorig:Hips"]
        self.shift = Vector((hips.x, hips.y, co[:, 2].min()))

    def place(self, p) -> Vector:
        """A point in the export's frame, moved and scaled like the mesh."""
        return (Vector(p) - self.shift) * self.scale

    def move_mesh(self):
        me = self.mesh.data
        co = np.array([v.co for v in me.vertices])
        co = (co - np.array(self.shift)) * self.scale
        me.vertices.foreach_set("co", co.ravel())
        me.update()


def build_armature(model, pod):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, parent, head, tail):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
        return b

    j = model.joints
    for name, parent, head, tail in SKELETON:
        h = model.place(j[head])
        t = h + Vector((0, -0.16, 0)) if tail is None else model.place(j[tail])  # toes: flat out in front
        bone(name, parent, h, t)
    axis = Vector(pod.axis)  # directions only scale, they don't shift
    pivot = model.place(POD_PIVOT)
    bone("launcher", "chest", pivot, pivot + axis * 0.25)
    for k in range(MISSILES):
        tip = model.place(pod.tips[k])
        bone("missile_%d" % k, "launcher", tip, tip + axis * 0.1)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = model.mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    model.mesh.parent = arm
    return arm


# ---------------------------------------------------------------- arms

class Arms:
    """The arms, T-posed in the export, hung at the sides by IK: the hand straight down from the
    shoulder (a little out to the side and swung forward or back), the elbow bending back."""

    def __init__(self, pose):
        self.pose = pose
        self.info = {}
        for s in "LR":
            up, lo, hand = "upperarm_" + s, "forearm_" + s, "hand_" + s
            sh, el, wr = (pose.rest[b].translation.copy() for b in (up, lo, hand))
            self.info[s] = {"bones": (up, lo), "l1": (el - sh).length, "l2": (wr - el).length,
                            "side": 1.0 if s == "L" else -1.0}

    def hang(self, s, swing, bend=0.0):
        """Hangs the arm `swing` radians forward of straight down (negative: back), the elbow
        bent `bend` more than at rest."""
        i = self.info[s]
        up, lo = i["bones"]
        p = self.pose
        a = p.head(up)
        reach = (i["l1"] + i["l2"]) * (ARM_REACH - bend)
        d = Vector((i["side"] * ARM_OUT, -math.sin(swing), -math.cos(swing))).normalized()
        pole = Vector((i["side"] * 0.35, 1.0, -0.3)).normalized()  # elbows back and a little out
        elbow, wrist = two_bone(a, i["l1"], i["l2"], a + d * reach, pole)
        for name, h, t in ((up, a, elbow), (lo, elbow, wrist)):
            r = p.rest[name]
            rest_y = r.to_3x3() @ Vector((0, 1, 0))
            q = aim_frame((t - h).normalized(), pole) @ aim_frame(rest_y, pole).inverted()
            p.place(name, Matrix.Translation(h) @ (q @ r.to_3x3()).to_4x4())


# ---------------------------------------------------------------- clips

def bake_walk(arm, pose, legs, arms, direction):
    walk = walk_params(direction)
    walk["widen"] = SIDE_WIDEN * abs(walk["d"].x)
    frames = int(round(WALK_PERIOD * FPS))
    T = WALK_PERIOD
    ts = [f / FPS for f in range(frames)]
    fwd, side = walk["fwd"], walk["d"].x
    # Weight over the standing foot: the right one is down at the start (the left mid-swing).
    sway = [SWAY * (0.4 + 0.6 * abs(fwd)) * -math.cos(2 * math.pi * t / T) for t in ts]
    rise = hip_heights(legs, walk, ts, sway)
    rise = [min(x, 0.0) - CROUCH for x in rise]
    rise.append(rise[0])
    sway.append(sway[0])
    ts.append(T)
    _start(arm, "Walk_" + direction)
    worst, closest = 0.0, 9.0
    for f, t in enumerate(ts):
        pose.reset()
        yaw = -YAW * abs(fwd) * wave(t, T, phase=0.0) * (1 if fwd >= 0 else -1)
        roll = ROLL * (0.3 + 0.7 * abs(fwd)) * math.cos(2 * math.pi * t / T)
        lean = (4.0 * max(fwd, 0.0) - 3.0 * max(-fwd, 0.0)) * RAD
        pose.move("pelvis", (sway[f], 0, rise[f]))
        pose.turn("pelvis", Z, yaw)
        pose.turn("pelvis", Y, roll)
        pose.turn("pelvis", X, lean)
        pose.turn("pelvis", Y, -2.5 * RAD * side)  # leaning into a sidestep
        stance(pose, 0.0, yaw, roll)  # the chest stays square to the aim
        pose.turn("spine_1", X, -lean * 0.5)
        pose.turn("chest", X, 1.2 * RAD * wave(t, T, 2, 0.3))
        pose.turn("head", X, -1.0 * RAD * wave(t, T, 2, 0.3))
        # Each arm swings against its leg: the right one forward as the left leg reaches out.
        swing = ARM_SWING * 1.2 * (0.25 + 0.75 * abs(fwd)) * wave(t, T, phase=0.0) * (1 if fwd >= 0 else -1)
        arms.hang("R", swing, 0.04 + 0.05 * max(swing, 0.0) / ARM_SWING)
        arms.hang("L", -swing, 0.04 + 0.05 * max(-swing, 0.0) / ARM_SWING)
        pole = Matrix.Rotation(yaw, 3, "Z") @ Vector((0, -1, 0))
        ankles = {}
        for s in "LR":
            ankle, pitch, toe = legs.foot(s, t, walk)
            worst = max(worst, legs.solve(s, ankle, pitch, toe, pole))
            ankles[s] = ankle
        closest = min(closest, (ankles["L"].xy - ankles["R"].xy).length)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    print(f"Walk_{direction}: {walk['speed']:.2f} m/s, sweep {walk['sweep']:.2f} m, hips {min(rise):+.3f}..{max(rise):+.3f} m, "
          f"feet at least {closest:.2f} m apart, worst miss {worst * 100:.1f} cm")


def bake_idle(arm, pose, legs, arms):
    frames = int(round(IDLE_PERIOD * FPS))
    T = IDLE_PERIOD
    _start(arm, "Idle")
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        shift = 0.018 * wave(t, T, 1, 0.1)
        roll = 0.8 * RAD * wave(t, T, 1, 0.1)
        pose.move("pelvis", (shift, 0, -CROUCH - 0.008 + 0.006 * wave(t, T, 2)))
        pose.turn("pelvis", Y, roll)
        stance(pose, 0.0, 0.0, roll)
        pose.turn("chest", X, -1.0 * RAD * wave(t, T, 2, 0.25))  # breathing
        pose.turn("head", Z, 6.0 * RAD * wave(t, T, 1, 0.35))
        pose.turn("head", X, 1.5 * RAD * wave(t, T, 1, 0.6))
        arms.hang("R", 2.0 * RAD * wave(t, T, 1, 0.2), 0.05)
        arms.hang("L", -2.0 * RAD * wave(t, T, 1, 0.25), 0.05)
        pole = Vector((0, -1, 0))
        for s, i in legs.info.items():
            legs.solve(s, i["ankle"], 0.0, 0.0, pole)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    print(f"Idle: {frames} frames")


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    model = Model(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    pieces = pieces_of(model.mesh)
    weights = read_weights(model.mesh)
    pod = Pod(model.mesh, pieces, weights)
    new_weights = reweight(model.mesh, pieces, weights, pod)
    model.move_mesh()
    apply_weights(model.mesh, new_weights)
    arm = build_armature(model, pod)
    pose = Pose(arm)
    legs = Legs(pose, model)
    arms = Arms(pose)
    for d in DIRECTIONS:
        bake_walk(arm, pose, legs, arms, d)
    bake_idle(arm, pose, legs, arms)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    print(f"exported {args.output}: {len(arm.data.bones)} bones, scale {model.scale:.3f}, "
          f"clips {[a.name for a in bpy.data.actions]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
