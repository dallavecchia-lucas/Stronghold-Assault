"""Folding bridge prep: the Meshy "Military Loading Ramp" cut into the three sections it folds in.

The model is a bridge deck with railings, ramp flaps at both ends and a hydraulic joint under the deck at
each end of its middle span. It is cut through those joints (at x = +-CUT of its length) into the middle
span ("Deck") and the two end spans ("WingL" at -x, "WingR" at +x), every triangle that crosses a cut
clipped exactly at it (positions, normals and UVs interpolated), so the pieces meet edge to edge when
unfolded. FoldingBridge hinges the wings at the cuts: folded, the left one lies upside down on top of the
deck and the right one under it (a Z-fold).

The vertices come out in metres at the bridge's reference size (REF_LENGTH long, WIDTH wide, the height
scaled by HEIGHT_SCALE), with the deck's flat top at y = 0 and its middle at the origin, x along the
bridge; every section keeps that same frame (their nodes have no transform). Textures are fitted to
--size and re-encoded as JPEG like tools/gltf/process_prop.py does.

  python3 tools/gltf/fold_bridge.py --input assets_src/structures/folding_bridge/folding_bridge_meshy.glb \
      --output game/assets/structures/folding_bridge/folding_bridge.glb
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, add_accessor, read_glb, write_glb  # noqa: E402
from process_prop import shrink_images  # noqa: E402

## The cuts, as a fraction of the model's length either side of its middle: through the hydraulic joints.
CUT = 0.209
## The flat top of the deck in the model (its own units, y up).
DECK_TOP = 0.0256
## The bridge's size at its reference length (m): FoldingBridge stretches it along x to fit a river.
REF_LENGTH = 72.0
WIDTH = 10.9
HEIGHT_SCALE = 34.0


def clip(tris, attrs, keep):
    """Clips triangles (n, 3) of vertex indices against the half-space keep(x) >= 0, where keep is
    linear in x. attrs: dict name -> (count, k) vertex arrays; new vertices are appended to them.
    Returns the kept triangles (lists of new index triples)."""
    pos = attrs["POSITION"]
    out = []
    cache = {}

    def lerp_vertex(a, b):
        key = (min(a, b), max(a, b))
        if key in cache:
            return cache[key]
        da, db = keep(attrs["POSITION"][a][0]), keep(attrs["POSITION"][b][0])
        t = da / (da - db)
        for name in attrs:
            attrs[name] = np.vstack([attrs[name], attrs[name][a] + (attrs[name][b] - attrs[name][a]) * t])
        k = len(attrs["POSITION"]) - 1
        cache[key] = k
        return k

    for tri in tris:
        d = [keep(pos[i][0]) for i in tri]
        inside = [v >= 0.0 for v in d]
        if all(inside):
            out.append(list(tri))
            continue
        if not any(inside):
            continue
        # Sutherland-Hodgman on the triangle's loop.
        poly = []
        for j in range(3):
            a, b = tri[j], tri[(j + 1) % 3]
            ia, ib = d[j] >= 0.0, d[(j + 1) % 3] >= 0.0
            if ia:
                poly.append(a)
            if ia != ib:
                poly.append(lerp_vertex(a, b))
                pos = attrs["POSITION"]
        for j in range(1, len(poly) - 1):
            out.append([poly[0], poly[j], poly[j + 1]])
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--quality", type=int, default=85)
    args = p.parse_args()
    js, binary = read_glb(args.input)
    prim = js["meshes"][0]["primitives"][0]
    attrs = {name: accessor(js, binary, prim["attributes"][name]).astype(np.float64) for name in ("POSITION", "NORMAL", "TEXCOORD_0")}
    tris = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(np.int64)
    pos = attrs["POSITION"]
    lo, hi = pos.min(0), pos.max(0)
    mid = (lo + hi) * 0.5
    half = (hi[0] - lo[0]) * 0.5
    # Centred, the deck's top at 0.
    attrs["POSITION"] = pos - np.array([mid[0], DECK_TOP, mid[2]])
    cut = CUT * half * 2.0
    sections = {
        "WingL": [lambda x: -cut - x],
        "Deck": [lambda x: x + cut, lambda x: cut - x],
        "WingR": [lambda x: x - cut],
    }
    scale = np.array([REF_LENGTH / (half * 2.0), HEIGHT_SCALE, WIDTH / (hi[2] - lo[2])])
    meshes = []
    nodes = []
    material = prim.get("material", 0)
    for name, planes in sections.items():
        local = {k: v.copy() for k, v in attrs.items()}
        kept = [list(t) for t in tris]
        for plane in planes:
            kept = clip(kept, local, plane)
        kept = np.array(kept, dtype=np.int64)
        used = np.unique(kept)
        remap = -np.ones(len(local["POSITION"]), dtype=np.int64)
        remap[used] = np.arange(len(used))
        v = local["POSITION"][used] * scale
        n = local["NORMAL"][used] / scale
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        uv = local["TEXCOORD_0"][used]
        idx = remap[kept].reshape(-1)
        a_pos = add_accessor(js, binary, v, "VEC3", with_bounds=True)
        a_nrm = add_accessor(js, binary, n, "VEC3")
        a_uv = add_accessor(js, binary, uv, "VEC2")
        # Indices as uint32.
        arr = np.ascontiguousarray(idx.astype(np.uint32))
        binary += b"\0" * (-len(binary) % 4)
        js["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes, "target": 34963})
        binary += arr.tobytes()
        js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5125, "count": int(arr.size), "type": "SCALAR"})
        a_idx = len(js["accessors"]) - 1
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
                "indices": a_idx, "material": material}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
        print(f"{name}: {len(kept)} triangles, x {v[:, 0].min():.2f}..{v[:, 0].max():.2f}, y {v[:, 1].min():.2f}..{v[:, 1].max():.2f},"
              f" z {v[:, 2].min():.2f}..{v[:, 2].max():.2f} m")
    js["meshes"] = meshes
    js["nodes"] = [{"name": "FoldingBridge", "children": [1, 2, 3]}] + nodes
    js["scenes"] = [{"nodes": [0]}]
    js["scene"] = 0
    # The old primitive's accessors and views are dropped by rebuilding the binary from the ones still used.
    from gltf_io import compact  # noqa: E402
    binary = compact(js, binary)
    binary = shrink_images(js, binary, args.size, args.quality)
    js.setdefault("asset", {})["generator"] = "tools/gltf/fold_bridge.py"
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    write_glb(args.output, js, binary)
    print(f"{args.output}: cut at x = +-{cut * scale[0]:.2f} m")


if __name__ == "__main__":
    main()
