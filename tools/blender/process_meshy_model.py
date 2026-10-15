"""Turn a raw Meshy export into a game-ready GLB for Godot.

Run headless:
  blender -b --python tools/blender/process_meshy_model.py -- \
      --input assets_src/units/foo/foo_meshy.glb \
      --output game/assets/units/foo/foo.glb \
      [--height 1.9] [--rotate-z 90] [--pivot feet|bbox] [--tex 2048] [--orm-tex 1024]

Steps:
  * optionally turns the model (--rotate-z, degrees) so its front faces Blender -Y
  * puts the origin at the feet (centered between the lowest vertices)
  * optionally rescales the model to a target height in meters
  * downsizes textures (base color/normal to --tex, metal/rough to --orm-tex)
  * exports GLB (+Y up, model front +Z, which is Godot's model-front convention)
"""
import argparse
import math
import sys

import bpy
from mathutils import Matrix, Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--height", type=float, default=0.0, help="target height in meters (0 = keep)")
    p.add_argument("--rotate-z", type=float, default=0.0, help="turn the model around the up axis (degrees)")
    p.add_argument("--pivot", choices=["feet", "bbox"], default="feet",
                   help="horizontal pivot: between the lowest vertices, or the bounding-box center (long vehicles)")
    p.add_argument("--tex", type=int, default=2048, help="max size for base color / normal maps")
    p.add_argument("--orm-tex", type=int, default=1024, help="max size for metallic/roughness maps")
    return p.parse_args(argv)


def _metal_rough_images():
    """Images feeding metallic/roughness (the glTF importer routes them through a Separate Color node).
    Meshy exports don't always name their images, so detect by how they're wired."""
    found = set()
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type != "TEX_IMAGE" or node.image is None:
                continue
            for link in node.outputs["Color"].links:
                if link.to_node.type in {"SEPRGB", "SEPARATE_COLOR"}:
                    found.add(node.image)
    return found


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

    if args.rotate_z:
        rot = Matrix.Rotation(math.radians(args.rotate_z), 4, "Z")
        for o in meshes:
            o.data.transform(rot)
            o.data.update()

    verts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    min_z = min(v.z for v in verts)
    max_z = max(v.z for v in verts)
    height = max_z - min_z

    # Center horizontally on the feet rather than the bounding box, so backpacks/weapons
    # sticking out don't shift the pivot.
    if args.pivot == "bbox":
        center = Vector(((min(v.x for v in verts) + max(v.x for v in verts)) * 0.5,
                         (min(v.y for v in verts) + max(v.y for v in verts)) * 0.5, 0.0))
    else:
        feet = [v for v in verts if v.z < min_z + height * 0.1]
        center = sum(feet, Vector()) / len(feet)
    offset = Vector((-center.x, -center.y, -min_z))
    scale = args.height / height if args.height > 0 else 1.0

    for o in meshes:
        for v in o.data.vertices:
            v.co = (v.co + offset) * scale
        o.data.update()

    orm_images = _metal_rough_images()
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        limit = args.orm_tex if img in orm_images else args.tex
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
