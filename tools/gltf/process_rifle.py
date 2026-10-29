"""Hand-held weapon prep (the Sniper's Eclipse Longshot): turns a Meshy export so its muzzle points
+Z with its top up (+Y; its right side is then -X, like a character's), scales it to a real length,
puts its origin at the pistol grip and shrinks its textures (as tools/gltf/process_prop.py does). No
Blender: numpy and Pillow on the glTF itself.

Named points on the weapon, given in the export's own frame (--point name=x,y,z), become marker nodes
(no mesh) under its root, in the new frame: the rig that poses the hands round it
(tools/gltf/rig_sniper.py) and the game (SniperTrooper) find them by name. For the Eclipse Longshot:
  muzzle   the muzzle brake's mouth, on the bore
  eye      where the shooter's eye sits, on the scope's axis behind the eyepiece (cheek on the stock)
  butt     the middle of the butt plate (into the shoulder)
  support  under the fore-end, where the support hand holds it
  scope    the eyepiece, on the scope's axis
The origin itself is --grip: the top of the pistol grip, where the web of the trigger hand sits.

  python3 tools/gltf/process_rifle.py \\
      --input assets_src/defenders/grey_veil_warden/eclipse_longshot_meshy.glb \\
      --output game/assets/defenders/grey_veil_warden/eclipse_longshot.glb \\
      --muzzle=-x --length 1.15 --grip 0.225,-0.04,0 \\
      --point muzzle=-0.479,0.022,0 --point eye=0.31,0.116,0 --point butt=0.479,-0.02,0 \\
      --point support=-0.02,-0.045,0 --point scope=0.225,0.116,0
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import axis_angle, set_trs, trs, write_glb, read_glb  # noqa: E402
from process_prop import shrink_images, world_bounds  # noqa: E402

# Yaw (about +Y) that turns the export's muzzle axis to +Z.
YAWS = {"+z": 0.0, "-z": np.pi, "+x": -np.pi * 0.5, "-x": np.pi * 0.5}


def vec(text):
    return np.array([float(v) for v in text.split(",")], dtype=float)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--muzzle", choices=list(YAWS), required=True, help="the export's axis the muzzle points along")
    p.add_argument("--length", type=float, required=True, help="muzzle to butt (m)")
    p.add_argument("--grip", required=True, help="x,y,z of the new origin, in the export's frame")
    p.add_argument("--point", action="append", default=[], help="name=x,y,z in the export's frame")
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--quality", type=int, default=85)
    args = p.parse_args()
    js, binary = read_glb(args.input)
    lo, hi = world_bounds(js, binary)
    axis = {"x": 0, "y": 1, "z": 2}[args.muzzle[1]]
    scale = args.length / (hi[axis] - lo[axis])
    turn = np.eye(4)
    turn[:3, :3] = axis_angle([0.0, 1.0, 0.0], YAWS[args.muzzle])
    # Export frame -> weapon frame: about the grip, turned, scaled.
    m = np.eye(4)
    m[:3, :3] = turn[:3, :3] * scale
    m[:3, 3] = -(m[:3, :3] @ vec(args.grip))
    roots = js["scenes"][js.get("scene", 0)]["nodes"]
    for root in roots:
        node = js["nodes"][root]
        nm = m @ trs(node)
        for k in ("translation", "rotation", "scale"):
            node.pop(k, None)
        node["matrix"] = [float(v) for v in nm.T.reshape(-1)]
    # The markers hang off a root of their own, with no scale, so the game reads them as they are.
    markers = {"name": "markers", "children": []}
    js["nodes"].append(markers)
    marker_root = len(js["nodes"]) - 1
    roots.append(marker_root)
    for entry in args.point:
        name, at = entry.split("=")
        pos = m[:3, :3] @ vec(at) + m[:3, 3]
        node = {"name": name}
        set_trs(node, np.array([[1, 0, 0, pos[0]], [0, 1, 0, pos[1]], [0, 0, 1, pos[2]], [0, 0, 0, 1]], dtype=float))
        js["nodes"].append(node)
        markers["children"].append(len(js["nodes"]) - 1)
        print(f"  {name:8s} {np.round(pos, 4)}")
    binary = shrink_images(js, binary, args.size, args.quality)
    js.setdefault("asset", {})["generator"] = "tools/gltf/process_rifle.py"
    write_glb(args.output, js, binary)
    lo2, hi2 = world_bounds(js, binary)
    print(f"{args.output}: scale {scale:.4f}, bounds {np.round(lo2, 4)} .. {np.round(hi2, 4)}")


if __name__ == "__main__":
    main()
