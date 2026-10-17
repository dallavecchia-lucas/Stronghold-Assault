"""Prepare a rigged Meshy humanoid (Mixamo-style skeleton) for Godot.

Keeps the clips that come with the export (e.g. "Running"), adds a looping "Idle" built from
the rest pose (arms lowered from the T-pose, gentle breathing and head sway) when the rig
has Mixamo arm bones, shrinks textures and exports a GLB with every clip.

Run headless:
  blender -b --python tools/blender/process_rigged_humanoid.py -- \
      --input assets_src/defenders/foo/foo_meshy.glb \
      --output game/assets/defenders/foo/foo.glb [--tex 2048] [--orm-tex 1024]
"""
import argparse
import math
import sys

import bpy
from mathutils import Quaternion, Vector

FPS = 30
IDLE_SECONDS = 3.0


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


def metal_rough_images():
    found = set()
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                for link in node.outputs["Color"].links:
                    if link.to_node.type in {"SEPRGB", "SEPARATE_COLOR"}:
                        found.add(node.image)
    return found


def shrink_textures(tex, orm_tex):
    orm = metal_rough_images()
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        limit = orm_tex if img in orm else tex
        w, h = img.size
        if max(w, h) > limit:
            f = limit / max(w, h)
            img.scale(int(w * f), int(h * f))
            img.pack()


def local_rotation(arm, bone_name, world_quat):
    """Turn a rotation expressed in armature space into the bone's pose-space rotation."""
    rest = arm.data.bones[bone_name].matrix_local.to_quaternion()
    return rest.inverted() @ world_quat @ rest


def bake_idle(arm):
    bones = arm.data.bones
    needed = ["mixamorig:LeftArm", "mixamorig:RightArm", "mixamorig:Spine2", "mixamorig:Head"]
    if not all(n in bones for n in needed):
        print("no Mixamo arms: skipping Idle")
        return False
    action = bpy.data.actions.new("Idle")
    action.use_fake_user = True
    previous = arm.animation_data.action if arm.animation_data else None
    arm.animation_data_create()
    arm.animation_data.action = action

    # arms: from the T-pose direction down to the sides, slightly forward and out
    arm_drop = {}
    for side, name in ((1.0, "mixamorig:LeftArm"), (-1.0, "mixamorig:RightArm")):
        b = bones[name]
        rest_dir = (b.tail_local - b.head_local).normalized()
        sx = 1.0 if rest_dir.x >= 0 else -1.0
        target = Vector((0.22 * sx, -0.08, -0.97)).normalized()
        arm_drop[name] = rest_dir.rotation_difference(target)
    forearm_bend = {}
    for name in ("mixamorig:LeftForeArm", "mixamorig:RightForeArm"):
        if name in bones:
            forearm_bend[name] = Quaternion(Vector((1, 0, 0)), math.radians(-12))

    frames = int(IDLE_SECONDS * FPS)
    for f in range(frames + 1):
        t = f / FPS
        breath = math.sin(2 * math.pi * t / IDLE_SECONDS)
        poses = dict(arm_drop)
        for name, q in forearm_bend.items():
            poses[name] = q
        poses["mixamorig:Spine2"] = Quaternion(Vector((1, 0, 0)), math.radians(1.5 * breath))
        poses["mixamorig:Head"] = Quaternion(Vector((0, 0, 1)), math.radians(5.0 * math.sin(2 * math.pi * t / IDLE_SECONDS + 1.0)))
        for name, world_q in poses.items():
            pb = arm.pose.bones[name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = local_rotation(arm, name, world_q)
            pb.keyframe_insert("rotation_quaternion", frame=f)
    arm.animation_data.action = previous
    return True


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.input)
    junk = bpy.data.objects.get("Icosphere")
    if junk:
        bpy.data.objects.remove(junk, do_unlink=True)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    bake_idle(arm)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    print("exported", args.output, "clips:", [a.name for a in bpy.data.actions])


if __name__ == "__main__":
    main()
