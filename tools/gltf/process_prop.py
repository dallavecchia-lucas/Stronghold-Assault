"""Static prop prep without glTF-Transform: puts the pivot at the bottom centre and shrinks the
textures, the same steps as the README's `npx @gltf-transform/cli center / resize / jpeg` chain
(Props scales the model to height at load time).

Only for simple Meshy exports: one scene, unskinned meshes, embedded images. The pivot goes into
the root nodes' transforms (the vertex data is untouched); every image is resized to fit --size and
re-encoded as JPEG (--quality), PNGs with alpha stay PNG.

  python3 tools/gltf/process_prop.py --input assets_src/<...>_meshy.glb --output game/assets/<...>.glb
"""
import argparse
import io
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, read_glb, trs, write_glb  # noqa: E402


def world_bounds(js, binary):
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)

    def walk(i, parent):
        nonlocal lo, hi
        node = js["nodes"][i]
        m = parent @ trs(node)
        if "mesh" in node:
            for prim in js["meshes"][node["mesh"]]["primitives"]:
                p = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
                p = p @ m[:3, :3].T + m[:3, 3]
                lo, hi = np.minimum(lo, p.min(0)), np.maximum(hi, p.max(0))
        for c in node.get("children", []):
            walk(c, m)

    for root in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4))
    return lo, hi


def shrink_images(js, binary, size, quality):
    """Re-encodes every embedded image (fitting `size`) into a fresh binary chunk."""
    out = bytearray()
    image_views = {im["bufferView"] for im in js.get("images", []) if "bufferView" in im}
    for k, view in enumerate(js["bufferViews"]):
        start = view.get("byteOffset", 0)
        data = bytes(binary[start:start + view["byteLength"]])
        if k in image_views:
            img = Image.open(io.BytesIO(data))
            if max(img.size) > size:
                img = img.resize((size * img.size[0] // max(img.size), size * img.size[1] // max(img.size)), Image.LANCZOS)
            buf = io.BytesIO()
            if img.mode in ("RGBA", "LA") and np.asarray(img)[..., -1].min() < 255:
                img.save(buf, "PNG", optimize=True)
                mime = "image/png"
            else:
                img.convert("RGB").save(buf, "JPEG", quality=quality, optimize=True)
                mime = "image/jpeg"
            data = buf.getvalue()
            for im in js["images"]:
                if im.get("bufferView") == k:
                    im["mimeType"] = mime
        out += b"\0" * (-len(out) % 4)
        view["byteOffset"] = len(out)
        view["byteLength"] = len(data)
        out += data
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--quality", type=int, default=85)
    args = p.parse_args()
    js, binary = read_glb(args.input)
    lo, hi = world_bounds(js, binary)
    shift = np.array([-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5])
    for root in js["scenes"][js.get("scene", 0)]["nodes"]:
        node = js["nodes"][root]
        m = trs(node)
        m[:3, 3] += shift
        for k in ("translation", "rotation", "scale"):
            node.pop(k, None)
        node["matrix"] = [float(v) for v in m.T.reshape(-1)]
    binary = shrink_images(js, binary, args.size, args.quality)
    js.setdefault("asset", {})["generator"] = "tools/gltf/process_prop.py"
    write_glb(args.output, js, binary)
    lo2, hi2 = world_bounds(js, binary)
    print(f"{args.output}: bounds {np.round(lo2, 4)} .. {np.round(hi2, 4)}")


if __name__ == "__main__":
    main()
