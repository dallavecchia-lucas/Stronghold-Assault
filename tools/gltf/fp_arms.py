"""First-person arms: cuts a rigged character (one from tools/gltf/arm_rifle.py) down to the parts of its
arms that hold the gun, for the view model. No Blender: numpy on the glTF itself.

A triangle stays when each of its vertices is weighted mostly (over --keep) to the arm bones from
--from down (ForeArm: the forearms, the hands and the fingers; Arm: the upper arms too). The skeleton,
its `rifle` bone and the clips stay as they are, so the game poses the arms with the character's own
Idle clip and lines them up with the first-person gun by the `rifle` bone (DefenderSoldier).

  python3 tools/gltf/fp_arms.py --input game/assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel_armed.glb \\
      --output game/assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel_fp_arms.glb
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, compact, read_glb, write_glb  # noqa: E402

P = "mixamorig:"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--from", dest="start", choices=("Arm", "ForeArm"), default="ForeArm")
    p.add_argument("--keep", type=float, default=0.5)
    p.add_argument("--upper", type=float, default=0.0,
                   help="with --from ForeArm: also keep the upper arm this far (m, at rest) above the elbow")
    args = p.parse_args()
    js, binary = read_glb(args.input)
    nodes = js["nodes"]
    skin = js["skins"][0]
    names = [nodes[j].get("name", "") for j in skin["joints"]]
    parts = ["ForeArm", "Hand"] if args.start == "ForeArm" else ["Arm", "ForeArm", "Hand"]
    arm = np.array([any(n.startswith(P + side + part) for side in ("Left", "Right") for part in parts) for n in names])
    node = next(n for n in nodes if "skin" in n)
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    joints = accessor(js, binary, prim["attributes"]["JOINTS_0"]).astype(int)
    weights = accessor(js, binary, prim["attributes"]["WEIGHTS_0"]).astype(float)
    if weights.max() > 1.5:
        weights /= 255.0 if weights.max() <= 255 else 65535.0
    share = (weights * arm[joints]).sum(1) / np.maximum(weights.sum(1), 1e-9)
    if args.upper > 0.0:
        # The upper arm near the elbow too (the shoulder pads stay out of the view).
        ibm = accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4).transpose(0, 2, 1)
        pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
        upper = np.array([any(n == P + side + "Arm" for side in ("Left", "Right")) for n in names])
        near = np.zeros(len(pos), bool)
        for side in ("Left", "Right"):
            k = names.index(P + side + "ForeArm")
            elbow = np.linalg.inv(ibm[k])[:3, 3]
            near |= np.linalg.norm(pos - elbow, axis=1) < args.upper
        share = np.where(near, share + (weights * upper[joints]).sum(1) / np.maximum(weights.sum(1), 1e-9), share)
    idx = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(np.uint32)
    kept = idx[(share[idx] > args.keep).all(1)]
    data = np.ascontiguousarray(kept.reshape(-1))
    binary += b"\0" * (-len(binary) % 4)
    js["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": data.nbytes, "target": 34963})
    binary += data.tobytes()
    js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5125, "count": int(data.size), "type": "SCALAR"})
    prim["indices"] = len(js["accessors"]) - 1
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/fp_arms.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(kept)} of {len(idx)} triangles")


if __name__ == "__main__":
    main()
