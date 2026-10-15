"""Turn a raw Meshy export into a game-ready GLB for Godot.

Run headless:
  blender -b --python tools/blender/process_meshy_model.py -- \
      --input assets_src/units/foo/foo_meshy.glb \
      --output game/assets/units/foo/foo.glb \
      [--height 1.9] [--tex 2048] [--orm-tex 1024]

Steps:
  * puts the origin at the feet (centered between the lowest vertices)
  * optionally rescales the model to a target height in meters
  * downsizes textures (base color/normal to --tex, metal/rough to --orm-tex)
  * exports GLB (+Y up, model front +Z, which is Godot's model-front convention)
"""
import argparse
import sys

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--height", type=float, default=0.0, help="target height in meters (0 = keep)")
    p.add_argument("--tex", type=int, default=2048, help="max size for base color / normal maps")
    p.add_argument("--orm-tex", type=int, default=1024, help="max size for metallic/roughness maps")
    return p.parse_args(argv)


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.input)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("no mesh found in " + args.input)

    # Bake object transforms into the mesh data so the origin math below is in world space.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    verts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    min_z = min(v.z for v in verts)
    max_z = max(v.z for v in verts)
    height = max_z - min_z

    # Center horizontally on the feet rather than the bounding box, so backpacks/weapons
    # sticking out don't shift the pivot.
    feet = [v for v in verts if v.z < min_z + height * 0.1]
    center = sum(feet, Vector()) / len(feet)
    offset = Vector((-center.x, -center.y, -min_z))
    scale = args.height / height if args.height > 0 else 1.0

    for o in meshes:
        for v in o.data.vertices:
            v.co = (v.co + offset) * scale
        o.data.update()

    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        limit = args.orm_tex if "metallic" in img.name.lower() or "rough" in img.name.lower() else args.tex
        w, h = img.size
        if max(w, h) > limit:
            f = limit / max(w, h)
            img.scale(int(w * f), int(h * f))
            img.pack()
        print(f"texture {img.name}: {tuple(img.size)}")

    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_image_format="AUTO",
        use_selection=False,
    )
    print(f"exported {args.output}: height {height * scale:.2f} m, {sum(len(o.data.polygons) for o in meshes)} faces")


main()
