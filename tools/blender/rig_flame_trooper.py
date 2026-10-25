"""Rig and animate the Flame Trooper, the Flame Squad's defender: the Crimson Warden, twin fuel
tanks on her back and a flame gun at her right hip. The Meshy export comes with a Mixamo-style
auto-rig and a Running clip; the Flame Squad walks any way while facing its aim, like the Gunner
Squad, so it gets the Heavy Gunner's eight walk clips instead (same speeds and timing, so the game
blends them the same way: SquadTrooper).

The auto-rig's skin weights are kept for the body: its bones are rebuilt in the same places with
the Heavy Gunner's clean names (pelvis, spine_1, thigh_L ...) and their weights carried over. The
gun is re-skinned rigidly onto `gun` (a child of the right hand, which holds it); `nozzle` marks the
muzzle, its Y axis out along the barrel (no weights: the game lights the flame there). The tank pack
rides the chest rigidly, and the hose from the tanks to the gun loses its pull from the legs, so it
hangs from the hips instead of riding the knees. The model is scaled to HEIGHT with its origin under
the hips.

Combat stance: the export holds the gun about 29 degrees off to its right. Every clip twists the
torso that far to the left and the neck back (like the Heavy Gunner's), so the nozzle points down
the trooper's front (-Y here, +Z in Godot) and it looks where it burns. The right arm holding the
gun is left to the chest; the free left arm swings. The export stands with its feet off-centre:
the clips plant them evenly either side of the hips.

Clips (FPS frames per second, keyed bones only; the right arm and the gun are left to the chest):
  Idle        breathing, a slow weight shift and a look around, the feet planted.
  Walk_<dir>  eight directions, as rig_heavy_gunner.py: one cycle of WALK_PERIOD each, all in step,
              feet planted by IK; the left arm swings against the legs.

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_flame_trooper.py -- \\
      --input assets_src/defenders/crimson_warden/crimson_warden_meshy.glb \\
      --output game/assets/defenders/crimson_warden/flame_trooper_rigged.glb [--preview DIR]

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
from rig_elephant import Pose, _finish, _start, wave  # noqa: E402
from rig_heavy_gunner import (  # noqa: E402
    ARM_SWING, DIRECTIONS, FPS, IDLE_PERIOD, LEG_BONES, RAD, ROLL, SWAY, WALK_PERIOD, YAW, Legs, X, Y, Z,
    apply_weights, hip_heights, pieces_of, read_weights, render_preview, stance, walk_params)
from rig_missile_trooper import Arms, Model  # noqa: E402

# Knees a little bent: the hips sit this much lower than the straight-legged rest.
CROUCH = 0.03
# Extra half-width of the stance walking sideways (m).
SIDE_WIDEN = 0.1

# Auto-rig bones -> new bones (their weights are summed). Fingers go with the hand. The right foot's
# chain is offset by one: Bone_007 is the ankle, Bone_006 the ball of the foot, and the auto-rig's
# RightFoot / RightToeBase lie out along the toes.
GROUPS = {
    "pelvis": ["mixamorig:Hips"],
    "spine_1": ["mixamorig:Spine"], "spine_2": ["mixamorig:Spine1"], "chest": ["mixamorig:Spine2"],
    "neck": ["mixamorig:Neck"], "head": ["mixamorig:Head", "mixamorig:HeadTop_End", "headfront"],
    "clavicle_L": ["mixamorig:LeftShoulder"], "upperarm_L": ["mixamorig:LeftArm"],
    "forearm_L": ["mixamorig:LeftForeArm"], "hand_L": ["mixamorig:LeftHand"],
    "clavicle_R": ["mixamorig:RightShoulder"], "upperarm_R": ["mixamorig:RightArm"],
    "forearm_R": ["mixamorig:RightForeArm"], "hand_R": ["mixamorig:RightHand"],
    "thigh_L": ["mixamorig:LeftUpLeg"], "shin_L": ["mixamorig:LeftLeg"], "foot_L": ["mixamorig:LeftFoot"],
    "toe_L": ["mixamorig:LeftToeBase", "mixamorig:LeftToe_End"],
    "thigh_R": ["mixamorig:RightUpLeg"], "shin_R": ["mixamorig:RightLeg"], "foot_R": ["Bone_007"],
    "toe_R": ["Bone_006", "mixamorig:RightFoot", "mixamorig:RightToeBase", "mixamorig:RightToe_End"],
}
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
    ("shin_R", "thigh_R", "mixamorig:RightLeg", "Bone_007"),
    ("foot_R", "shin_R", "Bone_007", "Bone_006"),
    ("toe_R", "foot_R", "Bone_006", None),
]
LEG_NAMES = ("thigh_L", "shin_L", "foot_L", "toe_L", "thigh_R", "shin_R", "foot_R", "toe_R")
# The gun: the right hand's vertices (the auto-rig hangs the gun on the fingers) lying along the
# barrel, ahead of the grip. Measured along the barrel axis (t, from the middle of the barrel, in
# the export's meters) and out from it (r).
GUN_T = (-0.25, 0.25)
GUN_R = 0.15
# The tank pack: loose pieces this far behind the hips (export meters, +Y is back) and above them.
PACK_BEHIND = 0.2
PACK_ABOVE = 0.9
# The free left arm swings this much more than the Heavy Gunner's.
LEFT_SWING = 1.3
# Neither the right arm (on the gun) nor the clavicles are keyed: they ride the chest.
ANIMATED = ["pelvis", "spine_1", "spine_2", "chest", "neck", "head", "upperarm_L", "forearm_L", "hand_L"] + \
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
    for name, olds in GROUPS.items():
        if old in olds:
            return name
    for side, prefix in (("L", "mixamorig:LeftHand"), ("R", "mixamorig:RightHand")):
        if old.startswith(prefix):  # the fingers
            return "hand_" + side
    raise KeyError(old)


def dominant(w):
    return max(w, key=w.get) if w else ""


# ---------------------------------------------------------------- the gun

class Gun:
    """The flame gun: the right hand's vertices ahead of the grip, along the barrel. Its axis is
    the barrel's (forward, toward the muzzle); its tip, the muzzle."""

    def __init__(self, co, pieces, weights):
        hose = np.array(pieces[1])  # the gun and its hose are one piece
        ahead = [i for i in hose if dominant(weights[i]).startswith("mixamorig:RightHand") and co[i, 1] < -0.12]
        c = co[ahead]
        self.centre = c.mean(axis=0)
        _, _, vt = np.linalg.svd(c - self.centre)
        self.axis = vt[0] if vt[0][1] < 0 else -vt[0]  # forward is -Y
        rel = co - self.centre
        t = rel @ self.axis
        r = np.linalg.norm(rel - np.outer(t, self.axis), axis=1)
        hand = np.array([dominant(w).startswith("mixamorig:RightHand") for w in weights])
        self.verts = np.where(hand & (t > GUN_T[0]) & (t < GUN_T[1]) & (r < GUN_R))[0]
        self.tip = self.centre + self.axis * float(t[self.verts].max())
        print(f"gun: {len(self.verts)} verts, axis {np.round(self.axis, 3)}, tip {np.round(self.tip, 3)}, "
              f"{math.degrees(math.atan2(-self.axis[0], -self.axis[1])):.1f} deg right of the front, "
              f"{math.degrees(math.asin(self.axis[2])):.1f} deg up")


def reweight(co, pieces, weights, gun):
    """New weights for every vertex: the body's carried over from the auto-rig, the gun and the
    tank pack rigid, the hose off the legs."""
    rigid = {int(i): "gun" for i in gun.verts}
    pack = 0
    for p in pieces[2:]:
        m = co[p].mean(axis=0)
        if m[1] > PACK_BEHIND and m[2] > PACK_ABOVE:
            for i in p:
                rigid.setdefault(i, "chest")
            pack += len(p)
    hose = set(pieces[1])
    out = []
    for i, w in enumerate(weights):
        if i in rigid:
            out.append({rigid[i]: 1.0})
            continue
        nw = {}
        for o, x in w.items():
            name = new_bone(o)
            if i in hose and name in LEG_NAMES:
                name = "pelvis"
            nw[name] = nw.get(name, 0.0) + x
        out.append(nw or {"pelvis": 1.0})
    print(f"rigid: gun {len(gun.verts)} verts, pack {pack} verts; hose off the legs: {len(hose)} verts")
    return out


def build_armature(model, gun):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, parent, head, tail, deform=True):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.roll = 0.0
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
        return b

    j = model.joints
    for name, parent, head, tail in SKELETON:
        h = model.place(j[head])
        t = h + Vector((0, -0.16, 0)) if tail is None else model.place(j[tail])  # toes: flat out in front
        bone(name, parent, h, t)
    a = Vector(gun.axis)  # directions only scale, they don't shift
    grip = model.place(Vector(gun.centre) + a * GUN_T[0])
    bone("gun", "hand_R", grip, grip + a * 0.3)
    tip = model.place(gun.tip) + a * 0.02
    bone("nozzle", "gun", tip, tip + a * 0.1, deform=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = model.mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    model.mesh.parent = arm
    return arm


def centre_feet(legs):
    """Plants the feet evenly either side of the hips (the export stands with its left foot out)."""
    half = (legs.info["L"]["ankle"].x - legs.info["R"]["ankle"].x) * 0.5
    for s, i in legs.info.items():
        dx = i["side"] * half - i["ankle"].x
        for k in ("ankle", "ball", "heel", "tip"):
            i[k] = i[k] + Vector((dx, 0.0, 0.0))
    print(f"feet planted {half:.3f} m either side of the hips")


# ---------------------------------------------------------------- clips

def bake_walk(arm, pose, legs, arms, direction, twist):
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
        stance(pose, twist, yaw, roll)  # the chest turns the gun onto the front, steady on it
        pose.turn("spine_1", X, -lean * 0.5)
        pose.turn("chest", X, 1.2 * RAD * wave(t, T, 2, 0.3))
        pose.turn("head", X, -1.0 * RAD * wave(t, T, 2, 0.3))
        # The free left arm swings against the left leg (back as the left leg reaches out).
        swing = ARM_SWING * LEFT_SWING * (0.25 + 0.75 * abs(fwd)) * wave(t, T, phase=0.0) * (1 if fwd >= 0 else -1)
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


def bake_idle(arm, pose, legs, arms, twist):
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
        stance(pose, twist, 0.0, roll)
        pose.turn("chest", X, -1.0 * RAD * wave(t, T, 2, 0.25))  # breathing
        pose.turn("head", Z, 6.0 * RAD * wave(t, T, 1, 0.35))
        pose.turn("head", X, 1.5 * RAD * wave(t, T, 1, 0.6))
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
    co = np.array([v.co for v in model.mesh.data.vertices])
    pieces = pieces_of(model.mesh)
    weights = read_weights(model.mesh)
    gun = Gun(co, pieces, weights)
    new_weights = reweight(co, pieces, weights, gun)
    twist = -math.atan2(gun.axis[0], -gun.axis[1])  # turns the barrel onto the front (-Y)
    model.move_mesh()
    apply_weights(model.mesh, new_weights)
    arm = build_armature(model, gun)
    pose = Pose(arm)
    legs = Legs(pose, model)
    centre_feet(legs)
    arms = Arms(pose)
    for d in DIRECTIONS:
        bake_walk(arm, pose, legs, arms, d, twist)
    bake_idle(arm, pose, legs, arms, twist)
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
          f"stance twist {math.degrees(twist):.1f} deg, clips {[a.name for a in bpy.data.actions]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
