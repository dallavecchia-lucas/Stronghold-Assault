"""Procedural slither + idle animations for the rigged Serpent Sniper (Meshy SmartRig).

A lateral-undulation wave travels from head to tail: every spine bone bends around the
world up axis by  amp(s) * sin(2*pi*(t/period) - 2*pi*waves*s/length),  where s is the
distance from the head. The amplitude is kept low near the head so the rifle stays aimed
and grows toward the tail. Both clips loop seamlessly.

Run headless:
  blender -b --python tools/blender/animate_serpent.py -- \
      --input assets_src/units/serpent_sniper/serpent_sniper_rigged_meshy.glb \
      --output game/assets/units/serpent_sniper/serpent_sniper_rigged.glb \
      [--preview /path/to/frames_dir]

The output is turned to face forward (model front +Z in glTF, -Y in Blender) and scaled to
the in-game height, with clips "slither" and "idle". The --preview option renders the
slither clip with the snake travelling at the matching ground speed.
"""
import argparse
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30
SLITHER_PERIOD = 1.2  # seconds per wave cycle
IDLE_PERIOD = 3.0
WAVES_ON_BODY = 1.4  # how many full waves fit along the body
ROTATE_Z = 59.5  # degrees: turns the mean head direction while slithering (-149.5) to -Y
TARGET_HEIGHT = 0.9

# head -> tail spine order (the rig branches at Bone_000 in the middle of the body)
HEAD_CHAIN = ["Bone_019", "Bone_020", "Bone_021", "Bone_022", "Bone_023", "Bone_024",
              "Bone_002", "Bone_003", "Bone_004", "Bone_005", "Bone_006", "Bone_001"]
TAIL_CHAIN = ["Bone_016", "Bone_015", "Bone_014", "Bone_013", "Bone_012", "Bone_011",
              "Bone_010", "Bone_009", "Bone_008", "Bone_007"]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args(argv)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    junk = bpy.data.objects.get("Icosphere")  # stray helper mesh in the Meshy export
    if junk:
        bpy.data.objects.remove(junk, do_unlink=True)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    return arm, mesh


def orient_and_scale(arm, mesh):
    """Bake the turn + scale into the armature rest pose and the mesh."""
    verts_z = [(mesh.matrix_world @ v.co).z for v in mesh.data.vertices]
    scale = TARGET_HEIGHT / (max(verts_z) - min(verts_z))
    arm.rotation_mode = "XYZ"  # the glTF importer uses quaternions, which ignore rotation_euler
    arm.rotation_euler = (0, 0, math.radians(ROTATE_Z))
    arm.scale = (scale, scale, scale)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return scale


# Whole spine head -> tail. Bone_000 is the rig root, sitting between the two chains.
SPINE = HEAD_CHAIN + ["Bone_000"] + TAIL_CHAIN


def spine(arm):
    """[(bone, midpoint distance from head)] in head->tail order, plus body length."""
    out = []
    s = 0.0
    for name in SPINE:
        length = arm.data.bones[name].length
        out.append((name, s + length * 0.5))
        s += length
    return out, s


def up_axis_local(arm, name):
    """World up expressed in the bone's local rest frame."""
    m = (arm.matrix_world @ arm.data.bones[name].matrix_local).to_3x3()
    return (m.inverted() @ Vector((0, 0, 1))).normalized()


def bake(arm, action_name, period, amp_head, amp_tail, waves, quiet_front=0.3):
    """Each body segment turns away from its rest direction by
         H(s, t) = A(s) * sin(2*pi*t/period - 2*pi*waves*s/L)
    (a heading wave travelling head -> tail). A(s) stays at amp_head over the front of the
    body (head + rifle) and ramps up to amp_tail toward the tail. A bone's own rotation is
    its segment's heading minus its parent's, so the head keeps pointing forward instead
    of whipping around the mid-body root."""
    bones, length = spine(arm)
    s_of = dict(bones)
    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action
    frames = int(round(period * FPS))

    def amp(u):
        k = min(max((u - quiet_front) / (1.0 - quiet_front), 0.0), 1.0)
        k = k * k * (3 - 2 * k)
        return amp_head + (amp_tail - amp_head) * k

    def heading(name, t):
        u = s_of[name] / length
        return math.radians(amp(u)) * math.sin(2 * math.pi * t / period - 2 * math.pi * waves * u)

    for f in range(frames + 1):
        t = f / FPS
        for name in SPINE:
            b = arm.data.bones[name]
            parent = b.parent.name if b.parent and b.parent.name in s_of else None
            angle = heading(name, t) - (heading(parent, t) if parent else 0.0)
            pb = arm.pose.bones[name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion(up_axis_local(arm, name), angle)
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)
    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    track = arm.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, 1, action)
    arm.animation_data.action = None
    return length, frames


def render_preview(arm, mesh, out_dir, body_length):
    """Slither clip travelling forward at the speed the wave implies."""
    sc = bpy.context.scene
    action = bpy.data.actions["slither"]
    arm.animation_data.action = action
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    cycles = 3
    frames = int(SLITHER_PERIOD * FPS) * cycles
    speed = (body_length / WAVES_ON_BODY) / SLITHER_PERIOD * 0.55  # some slip, like a real snake
    sc.frame_start, sc.frame_end = 1, frames
    # loop the action over the clip
    for fc in action.fcurves:
        fc.modifiers.new("CYCLES")
    arm.location = (0, 0, 0)
    arm.keyframe_insert("location", frame=1)
    arm.location = (0, -speed * frames / FPS, 0)
    arm.keyframe_insert("location", frame=frames)
    for fc in arm.animation_data.action.fcurves:
        if fc.data_path == "location":
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"

    ground_mat = bpy.data.materials.new("ground")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.35, 0.33, 0.25, 1)
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, -8, 0))
    bpy.context.object.data.materials.append(ground_mat)
    # grid of markers so the forward motion reads
    for i in range(-6, 7):
        for j in range(-12, 4):
            bpy.ops.mesh.primitive_cube_add(size=0.06, location=(i * 1.0, j * 1.0, 0.03))

    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x = 960
    sc.render.resolution_y = 540
    sc.render.fps = FPS
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 40
    # follow camera: raised side view, tracking the snake
    for f in (1, frames):
        sc.frame_set(f)
        y = arm.location.y
        cam.location = (6.5, y - 1.8, 4.2)
        cam.rotation_euler = (Vector((0, y - 0.6, 0.35)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.keyframe_insert("location", frame=f)
        cam.keyframe_insert("rotation_euler", frame=f)
    for fc in cam.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    sc.render.filepath = out_dir.rstrip("/") + "/f_"
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(animation=True)
    print(f"preview: {frames} frames, ground speed {speed:.2f} m/s")


def main():
    args = parse_args()
    arm, mesh = load(args.input)
    scale = orient_and_scale(arm, mesh)
    bpy.context.scene.render.fps = FPS
    length, frames = bake(arm, "slither", SLITHER_PERIOD, amp_head=3.0, amp_tail=30.0, waves=WAVES_ON_BODY)
    bake(arm, "idle", IDLE_PERIOD, amp_head=0.5, amp_tail=8.0, waves=0.8)
    # rest pose back on the armature before export
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=False,
    )
    speed = (length / WAVES_ON_BODY) / SLITHER_PERIOD
    print(f"exported {args.output}: scale {scale:.3f}, body length {length:.2f} m, "
          f"slither {frames} frames, no-slip wave speed {speed:.2f} m/s")
    if args.preview:
        render_preview(arm, mesh, args.preview, length)


main()
