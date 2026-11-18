"""Cuts the strip of pipes or wires out of a Meshy wall-deco model (the stronghold's wall_deco_1-4).

Meshy made each of those a box of panels: one side is the piece wanted, a strip of pipes or wires facing +Z along
the model's front edge, and the rest (side frames, a back plate, loose bars) is extra. This keeps the strip only:
the model's parts (told apart by how its triangles are connected) whose middle lies in front of the cut at z = CUT,
every triangle of them that crosses the cut clipped exactly at it (like tools/gltf/fold_bridge.py); the parts
behind it go. What is left hangs on a wall by its back (the cut, against the wall) with its pipes facing out (+Z),
x along the wall, y up it; the pivot is at the middle of its back. The texture is kept as it is.

Its input is process_prop.py's output; CUT is in its units (the model about a metre across, z from the middle):

  python3 tools/gltf/process_prop.py --input assets_src/stronghold_deco/wall_deco_1/wall_deco_1_meshy.glb \\
      --output /tmp/wall_deco_1.glb
  python3 tools/gltf/chop_strip.py --input /tmp/wall_deco_1.glb --cut 0.19 \\
      --output game/assets/stronghold/deco/wall_deco_1.glb
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import add_accessor, compact, read_glb, write_glb  # noqa: E402
from split_raft import components, gather, subset  # noqa: E402


def clip_z(tris, attrs, cut):
    """Clips triangles (lists of vertex indices) to z >= cut; new vertices are appended to attrs."""
    out = []
    cache = {}

    def between(a, b):
        key = (min(a, b), max(a, b))
        if key not in cache:
            za, zb = attrs["POSITION"][a][2] - cut, attrs["POSITION"][b][2] - cut
            t = za / (za - zb)
            for name in attrs:
                attrs[name] = np.vstack([attrs[name], attrs[name][a] + (attrs[name][b] - attrs[name][a]) * t])
            cache[key] = len(attrs["POSITION"]) - 1
        return cache[key]

    for tri in tris:
        d = [attrs["POSITION"][i][2] - cut for i in tri]
        inside = [v >= 0.0 for v in d]
        if all(inside):
            out.append(list(tri))
            continue
        if not any(inside):
            continue
        poly = []
        for j in range(3):
            a, b = tri[j], tri[(j + 1) % 3]
            if inside[j]:
                poly.append(a)
            if inside[j] != inside[(j + 1) % 3]:
                poly.append(between(a, b))
        for j in range(1, len(poly) - 1):
            out.append([poly[0], poly[j], poly[j + 1]])
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--cut", type=float, required=True, help="keep what lies in front of z = cut")
    args = p.parse_args()
    js, binary = read_glb(args.input)
    pos, nrm, uv, tris, material = gather(js, binary)
    comp = components(pos, tris)
    kept = []
    dropped = 0
    for c in np.unique(comp):
        sel = np.nonzero(comp == c)[0]
        v = pos[tris[sel].reshape(-1)]
        if (v[:, 2].min() + v[:, 2].max()) * 0.5 >= args.cut:
            kept.extend(tris[sel].tolist())
        else:
            dropped += len(sel)
    attrs = {"POSITION": pos, "NORMAL": nrm, "TEXCOORD_0": uv}
    kept = clip_z(kept, attrs, args.cut)
    v, n, t, idx = subset(attrs, kept)
    # The pivot at the middle of its back (the cut).
    lo, hi = v.min(0), v.max(0)
    v = v - np.array([(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, args.cut])
    size = v.max(0) - v.min(0)
    print(f"{os.path.basename(args.output)}: kept {len(idx) // 3} triangles, dropped {dropped};"
          f" {size[0]:.3f} x {size[1]:.3f}, {size[2]:.3f} deep")

    a_pos = add_accessor(js, binary, v, "VEC3", with_bounds=True)
    a_nrm = add_accessor(js, binary, n, "VEC3")
    a_uv = add_accessor(js, binary, t, "VEC2")
    arr = np.ascontiguousarray(idx.astype(np.uint32))
    binary += b"\0" * (-len(binary) % 4)
    js["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes, "target": 34963})
    binary += arr.tobytes()
    js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5125, "count": int(arr.size), "type": "SCALAR"})
    name = os.path.splitext(os.path.basename(args.output))[0]
    js["meshes"] = [{"name": name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
            "indices": len(js["accessors"]) - 1, "material": material}]}]
    js["nodes"] = [{"name": name, "mesh": 0}]
    js["scenes"] = [{"nodes": [0]}]
    js["scene"] = 0
    js.pop("skins", None)
    js.pop("animations", None)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/process_prop.py, tools/gltf/chop_strip.py"
    write_glb(args.output, js, binary)


if __name__ == "__main__":
    main()
