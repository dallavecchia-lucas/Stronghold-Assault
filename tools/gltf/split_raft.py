"""Tow raft prep: the Meshy "industrial amphibious" platform (assets_src/structures/tow_platform, through
tools/gltf/process_prop.py) cut into the pieces TowPlatform folds, unfolds, inflates and takes apart.

The raft is a deck on six float drums (three down each side), railings along its sides, a control box and a
hose coil on the deck. Its parts are separate pieces of the Meshy mesh, and they go into pieces of their own:

  Float_<S><L|R>  a float drum with its straps (S: F front, M middle, R rear section; L at -z, R at +z)
  Deck_<S>        the deck's section S: its frame and plate, cut across at x = +-CUT (every triangle that crosses
                  a cut clipped exactly at it, like tools/gltf/fold_bridge.py does, so the sections meet edge to
                  edge when it is unfolded)
  Top_<S>         what stands on that section's deck (railings, the box, the hose), cut the same way

The vertices come out in metres at the game's size (LENGTH long), in the raft's own frame: x along it (+x its
front, toward the carrier), y up from the floats' bottoms, z across it, its middle at x = z = 0. Every piece
keeps that frame (no node transforms): TowPlatform works the hinges and pivots out from DECK_TOP, CUT and each
float's bounds (it prints them). The texture is kept as it is.

Its input is process_prop.py's output (one mesh: the pieces are told apart by how its parts are connected):

  python3 tools/gltf/process_prop.py --input assets_src/structures/tow_platform/tow_platform_meshy.glb \\
      --output /tmp/tow_platform.glb
  python3 tools/gltf/split_raft.py --input /tmp/tow_platform.glb \\
      --output game/assets/structures/tow_platform/tow_platform.glb [--preview out.png]

--preview draws the pieces pulled apart (each float out from under the deck, the sections apart along it).
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fold_bridge import clip  # noqa: E402
from gltf_io import accessor, add_accessor, compact, read_glb, trs, write_glb  # noqa: E402

## The raft's length in the game (m: TowPlatform.LENGTH).
LENGTH = 6.0
## The cuts across the deck (m either side of its middle): in the gaps between the float drums.
CUT = 0.89
## A float drum: wholly under this height (m) and this far out from the middle (its centre).
FLOAT_TOP = 0.72
FLOAT_OUT = 0.85
## On the deck: wholly over this height (m).
TOP_FROM = 0.9
SECTIONS = {"R": (-math.inf, -CUT), "M": (-CUT, CUT), "F": (CUT, math.inf)}


def gather(js, binary):
    """Every triangle of the scene in its own frame: positions, normals, UVs (per vertex) and index triples."""
    nodes = js["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world(i):
        return (world(parent[i]) if i in parent else np.eye(4)) @ trs(nodes[i])

    pos, nrm, uv, tris = [], [], [], []
    base = 0
    material = 0
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        m = world(i)
        for prim in js["meshes"][n["mesh"]]["primitives"]:
            p = accessor(js, binary, prim["attributes"]["POSITION"]).astype(np.float64)
            q = accessor(js, binary, prim["attributes"]["NORMAL"]).astype(np.float64)
            pos.append(p @ m[:3, :3].T + m[:3, 3])
            nq = q @ np.linalg.inv(m[:3, :3])
            nrm.append(nq / np.maximum(np.linalg.norm(nq, axis=1, keepdims=True), 1e-12))
            uv.append(accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(np.float64))
            tris.append(accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(np.int64) + base)
            base += len(p)
            material = prim.get("material", 0)
    return np.concatenate(pos), np.concatenate(nrm), np.concatenate(uv), np.concatenate(tris), material


def components(pos, tris):
    """The connected piece each triangle belongs to (vertices welded by position)."""
    _, inv = np.unique(np.round(pos, 4), axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    parent = np.arange(inv.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for t in tris:
        a = find(inv[t[0]])
        for v in t[1:]:
            b = find(inv[v])
            if a != b:
                parent[b] = a
    return np.array([find(inv[t[0]]) for t in tris])


def section_of(x):
    return next(s for s, (lo, hi) in SECTIONS.items() if lo <= x < hi)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    args = p.parse_args()
    js, binary = read_glb(args.input)
    pos, nrm, uv, tris, material = gather(js, binary)
    # Metres at the game's size, the floats' bottoms at y = 0, its middle at x = z = 0.
    lo, hi = pos.min(0), pos.max(0)
    scale = LENGTH / (hi[0] - lo[0])
    pos = (pos - np.array([(lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5])) * scale

    comp = components(pos, tris)
    groups = {}  # piece name -> triangle indices (into tris)
    kinds = {"float": 0, "deck": 0, "top": 0}
    for c in np.unique(comp):
        sel = np.nonzero(comp == c)[0]
        v = pos[tris[sel].reshape(-1)]
        cmin, cmax = v.min(0), v.max(0)
        centre = (cmin + cmax) * 0.5
        if cmax[1] <= FLOAT_TOP and abs(centre[2]) >= FLOAT_OUT:
            name = "Float_%s%s" % (section_of(centre[0]), "L" if centre[2] < 0 else "R")
            kinds["float"] += len(sel)
        elif cmin[1] >= TOP_FROM:
            name = "Top"
            kinds["top"] += len(sel)
        else:
            name = "Deck"
            kinds["deck"] += len(sel)
        groups.setdefault(name, []).extend(sel.tolist())
    print("triangles:", kinds)

    attrs = {"POSITION": pos, "NORMAL": nrm, "TEXCOORD_0": uv}
    pieces = {}  # name -> (positions, normals, uvs, index array)
    for name, sel in sorted(groups.items()):
        if name.startswith("Float"):
            pieces[name] = subset(attrs, tris[sel].tolist())
            continue
        for s, (a, b) in SECTIONS.items():
            local = {k: v.copy() for k, v in attrs.items()}
            kept = tris[sel].tolist()
            if a > -math.inf:
                kept = clip(kept, local, lambda x, a=a: x - a)
            if b < math.inf:
                kept = clip(kept, local, lambda x, b=b: b - x)
            if kept:
                pieces["%s_%s" % (name, s)] = subset(local, kept)

    deck = np.concatenate([pieces["Deck_" + s][0] for s in SECTIONS])
    top = np.concatenate([pieces["Top_" + s][0] for s in SECTIONS])
    print(f"deck: y {deck[:, 1].min():.3f}..{deck[:, 1].max():.3f}, top of the plate {np.percentile(deck[:, 1], 99):.3f};"
          f" on it up to {top[:, 1].max():.3f} m; x {deck[:, 0].min():.2f}..{deck[:, 0].max():.2f},"
          f" z {deck[:, 2].min():.2f}..{deck[:, 2].max():.2f}")
    for name, (v, _, _, idx) in pieces.items():
        print(f"  {name:9s} {len(idx) // 3:5d} tris  x {v[:, 0].min():+.2f}..{v[:, 0].max():+.2f}"
              f"  y {v[:, 1].min():.2f}..{v[:, 1].max():.2f}  z {v[:, 2].min():+.2f}..{v[:, 2].max():+.2f}")

    # The pieces as meshes of their own, under one root, sharing the material.
    meshes, nodes = [], []
    order = ["Deck_R", "Deck_M", "Deck_F", "Top_R", "Top_M", "Top_F"] + sorted(n for n in pieces if n.startswith("Float"))
    for name in order:
        v, n, t, idx = pieces[name]
        a_pos = add_accessor(js, binary, v, "VEC3", with_bounds=True)
        a_nrm = add_accessor(js, binary, n, "VEC3")
        a_uv = add_accessor(js, binary, t, "VEC2")
        arr = np.ascontiguousarray(idx.astype(np.uint32))
        binary += b"\0" * (-len(binary) % 4)
        js["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes, "target": 34963})
        binary += arr.tobytes()
        js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5125, "count": int(arr.size), "type": "SCALAR"})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
                "indices": len(js["accessors"]) - 1, "material": material}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    js["meshes"] = meshes
    js["nodes"] = [{"name": "TowPlatform", "children": list(range(1, len(nodes) + 1))}] + nodes
    js["scenes"] = [{"nodes": [0]}]
    js["scene"] = 0
    js.pop("skins", None)
    js.pop("animations", None)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/process_prop.py, tools/gltf/split_raft.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(nodes)} pieces")
    if args.preview:
        render_preview(args.output, args.preview)


def subset(attrs, kept):
    """The vertices `kept` (index triples into attrs) use, re-indexed: (positions, normals, uvs, indices)."""
    kept = np.array(kept, dtype=np.int64)
    used = np.unique(kept)
    remap = -np.ones(len(attrs["POSITION"]), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return attrs["POSITION"][used], attrs["NORMAL"][used], attrs["TEXCOORD_0"][used], remap[kept].reshape(-1)


def render_preview(path, out):
    """The pieces pulled apart, from above its front left and from below its rear right."""
    from PIL import Image, ImageDraw
    from rig_infiltrator import rasterize
    from rig_sniper import load_textured
    js, binary = read_glb(path)
    tex = load_textured(js, binary, js["meshes"][0]["primitives"][0])
    W, H = 520, 360
    sheet = Image.new("RGB", (W * 2, H))
    for k, eye in enumerate((np.array([7.0, 6.0, -8.0]), np.array([-7.0, -3.5, 8.0]))):
        img = np.ones((H, W, 3), np.float32) * np.array([0.6, 0.7, 0.8], np.float32)
        zb = np.full((H, W), np.inf, np.float32)
        for n in js["nodes"]:
            if "mesh" not in n:
                continue
            prim = js["meshes"][n["mesh"]]["primitives"][0]
            v = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
            name = n["name"]
            sec = name[6] if name.startswith("Float") else name[-1]
            shift = np.array([{"R": -0.8, "M": 0.0, "F": 0.8}[sec], 0.0, 0.0])
            if name.startswith("Float"):
                shift += np.array([0.0, -0.5, 0.6 * np.sign(v[:, 2].mean())])
            elif name.startswith("Top"):
                shift[1] += 0.5
            rasterize(img, zb, v + shift, accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int),
                      accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float), tex, eye, np.array([0.0, 0.6, 0.0]))
        pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
        ImageDraw.Draw(pil).text((4, 4), "pieces pulled apart", fill=(0, 0, 0))
        sheet.paste(pil, (k * W, 0))
    sheet.save(out)
    print(f"preview {out}")


if __name__ == "__main__":
    main()
