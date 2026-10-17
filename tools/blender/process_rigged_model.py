"""Prepare any rigged Meshy model (Mixamo humanoid or Meshy SmartRig / animal rig) for Godot.

- scales the whole armature object to a target height and puts the feet at the origin
  (kept as an object transform, so clips that move the hips stay correct)
- renames clips (--rename "Armature|Unreal Take|baselayer=Walk")
- adds a looping "Idle": baked arms-down/breathing for Mixamo rigs, or a held rest pose
- shrinks textures and exports every clip

Run headless:
  blender -b --python tools/blender/process_rigged_model.py -- \
      --input assets_src/units/foo/foo_rigged_meshy.glb --output game/assets/units/foo/foo_rigged.glb \
      [--height 1.9] [--pivot feet|bbox] [--idle auto|mixamo|rest|none] [--rename OLD=NEW ...]
"""
import argparse
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_rigged_humanoid import bake_idle, shrink_textures  # noqa: E402

FPS = 30


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--height", type=float, default=0.0)
    p.add_argument("--pivot", choices=["feet", "bbox"], default="feet")
    p.add_argument("--idle", choices=["auto", "mixamo", "rest", "none"], default="auto")
    p.add_argument("--rename", action="append", default=[])
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


def rest_points(arm, meshes):
    """World-space vertices of the meshes in the armature's rest pose."""
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        e = o.evaluated_get(dg)
        m = e.to_mesh()
        pts += [o.matrix_world @ v.co for v in m.vertices]
        e.to_mesh_clear()
    arm.data.pose_position = "POSE"
    return pts


def fit(arm, meshes, height, pivot):
    pts = rest_points(arm, meshes)
    min_z = min(p.z for p in pts)
    h = max(p.z for p in pts) - min_z
    if height > 0:
        arm.scale = arm.scale * (height / h)
        bpy.context.view_layer.update()
        pts = rest_points(arm, meshes)
        min_z = min(p.z for p in pts)
    if pivot == "bbox":
        cx = (min(p.x for p in pts) + max(p.x for p in pts)) * 0.5
        cy = (min(p.y for p in pts) + max(p.y for p in pts)) * 0.5
    else:
        h = max(p.z for p in pts) - min_z
        feet = [p for p in pts if p.z < min_z + h * 0.1]
        c = sum(feet, Vector()) / len(feet)
        cx, cy = c.x, c.y
    arm.location -= Vector((cx, cy, min_z))
    bpy.context.view_layer.update()
    pts = rest_points(arm, meshes)
    return [round(min(p[i] for p in pts), 2) for i in range(3)], [round(max(p[i] for p in pts), 2) for i in range(3)]


def rest_idle(arm, seconds=1.0):
    action = bpy.data.actions.new("Idle")
    action.use_fake_user = True
    previous = arm.animation_data.action if arm.animation_data else None
    arm.animation_data_create()
    arm.animation_data.action = action
    for f in (0, int(seconds * FPS)):
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.scale = (1, 1, 1)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    arm.animation_data.action = previous


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.input)
    junk = bpy.data.objects.get("Icosphere")
    if junk:
        bpy.data.objects.remove(junk, do_unlink=True)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.context.scene.render.fps = FPS
    for spec in args.rename:
        old, new = spec.split("=", 1)
        if old in bpy.data.actions:
            bpy.data.actions[old].name = new
    shrink_textures(args.tex, args.orm_tex)
    bounds = fit(arm, meshes, args.height, args.pivot)
    mode = args.idle
    if mode == "auto":
        mode = "mixamo" if "mixamorig:LeftArm" in arm.data.bones else "rest"
    if mode == "mixamo":
        bake_idle(arm)
    elif mode == "rest":
        rest_idle(arm)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    print("exported", args.output, "bounds", bounds, "clips", [a.name for a in bpy.data.actions], "idle", mode)


main()
