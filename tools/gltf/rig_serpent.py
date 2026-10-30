"""Rig and animate the Serpent Sniper. No Blender: numpy on the glTF itself, like rig_lioness.py.

Input: the serpent (game/assets/units/serpent_sniper/serpent_sniper_rigged.glb: 0.9 m to the top of the
rifle's scope, front +Z, lying in an S on the ground, a 5 m anaconda in a helmet and a vest with an
anti-materiel rifle strapped along the front half of its back). Meshy's rig is no good for coiling: the
helmet is skinned to a bone in the rifle's barrel and nearly a metre of the body to a single bone. So this
keeps the mesh and builds a new skeleton along the snake: `head` (its origin HEAD_PIVOT behind the snout,
where the helmet ends) and SPINE_BONES spine bones evenly down the body to the tail tip, one chain (head ->
spine_01 -> ... -> spine_NN). Every bone's Y axis runs along the body toward the next bone (to the tail)
and its Z axis out of its back; the game lays the bones along curves (SerpentRig), so the snake can wind
round a tree trunk, a bush or its prey. The body bends smoothly: each vertex of the skin (and of the gear
that hugs it: the vest, the neck plate, the straps) is weighted between the two bones either side of where
it lies along the body. The helmet and the goggles ride rigidly on the head.

The rifle rides rigidly on its own bone, `rifle` (a child of the spine bone under its receiver, its Y axis
up the barrel and Z up), with the sling band round the handguard and the sling's two straps; `muzzle` (a
child of it, no weights) marks the barrel's tip, its Y axis out of the barrel, and `snout` (a child of the
head) the tip of the snout. The game moves the rifle off the snake's back when it coils round a bush and
lays it in the grass (SerpentRig).

Clips (FPS frames per second; looped clips end on a copy of their first frame, which the game drops):
  Slither  lateral undulation, authored travelling at SLITHER_SPEED (UnitTypes anim_ref_speed): a wave runs
           down the body from the shoulders to the tail, SLITHER_WAVE long, the rear half swinging
           SLITHER_AMP either side while the front (the gun) stays straight and level.
  Idle     lying still, the rear of the body in a loose curve, breathing (the back rising and falling a
           little), the tail tip curling slowly, the head and rifle steady on the aim.

  python3 tools/gltf/rig_serpent.py \\
      --input game/assets/units/serpent_sniper/serpent_sniper_rigged.glb \\
      --output game/assets/units/serpent_sniper/serpent_sniper_rigged.glb [--preview DIR]

The input may be the output of an earlier run (the rig is rebuilt from the mesh each time). --preview
renders the rest pose, frames of each clip and two test poses that the game's skills make (wound round a
trunk, coiled flat on the ground) into DIR as PNGs, with rig_infiltrator's numpy rasterizer.
"""
import argparse
import io
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, add_accessor, compact, mat_to_quat, quat_to_mat, read_glb, set_trs, trs, write_glb  # noqa: E402
from rig_infiltrator import project, rasterize, unit  # noqa: E402
from rig_lioness import pack_weights, pieces  # noqa: E402

FPS = 30
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

# ---------------------------------------------------------------- the body (model frame, meters)
# The middle of the body from the tip of the snout to the tip of the tail, as it lies in the mesh: the head
# measured on slices across it, the rest from the joints of Meshy's auto-rig (which ran down the middle).
GUIDE = [(0.505, 0.425, 1.890), (0.505, 0.428, 1.690), (0.485, 0.415, 1.500), (0.449, 0.383, 1.308),
         (0.441, 0.314, 1.104), (0.458, 0.255, 0.936), (0.493, 0.208, 0.736), (0.522, 0.172, 0.548),
         (0.539, 0.148, 0.379), (0.545, 0.148, 0.136), (0.504, 0.160, -0.122), (0.354, 0.160, -0.334),
         (0.157, 0.160, -0.464), (-0.002, 0.160, -0.544), (-0.248, 0.148, -0.523), (-0.509, 0.148, -0.499),
         (-0.713, 0.137, -0.619), (-0.847, 0.113, -0.835), (-0.828, 0.101, -1.099), (-0.753, 0.089, -1.343),
         (-0.707, 0.066, -1.631), (-0.583, 0.054, -1.888), (-0.515, 0.028, -2.037)]
# The head bone's origin, this far down the body from the snout (m): the back of the helmet.
HEAD_PIVOT = 0.55
SPINE_BONES = 40
# Gear (every piece of the mesh but the snake's skin): pieces centred above RIFLE_Y, within RIFLE_HALF_X of the
# rifle's line (RIFLE_X), narrower than RIFLE_WIDE and in front of the helmet (RIFLE_Z) belong to the rifle (the
# scope, the magazine, the stock's pads, the sling band and its straps); so does the long piece that is its
# barrel, receiver and stock. Pieces from HEADGEAR_Z forward are the helmet's and the goggles'. The rest (the
# vest, the neck plate, the straps round the belly) bends with the body.
RIFLE_X = 0.47
RIFLE_HALF_X = 0.16
RIFLE_Y = 0.355
RIFLE_WIDE = 0.2
RIFLE_Z = 1.3
HEADGEAR_Z = 1.3
# The rifle's bone: on the barrel's line over the receiver (this far forward, model z), parented to the spine
# bone nearest RIFLE_MOUNT down the body.
RIFLE_ORIGIN_Z = 0.3
RIFLE_MOUNT = 1.6

# ---------------------------------------------------------------- clips
SLITHER_SPEED = 2.4  # m/s along the ground (UnitTypes anim_ref_speed)
SLITHER_WAVE = 2.4  # wavelength of the undulation along the body (m)
SLITHER_AMP = 0.2  # how far the rear swings either side (m)
GUN_LENGTH = 2.3  # the front this far down the body carries the rifle: it stays straight (m)
IDLE_TIME = 3.0
BREATH = 0.012  # the back rises and falls this much breathing (m)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


# ---------------------------------------------------------------- curves

def catmull_rom(points, step):
    """A smooth curve through `points`, sampled every `step` m or so: (samples, arc length of each)."""
    p = np.asarray(points, dtype=float)
    p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        n = max(int(np.linalg.norm(p[i + 1] - p[i]) / step * 4), 4)
        for u in np.linspace(0.0, 1.0, n, endpoint=False):
            u2, u3 = u * u, u * u * u
            out.append(0.5 * (2 * p[i] + (-p[i - 1] + p[i + 1]) * u + (2 * p[i - 1] - 5 * p[i] + 4 * p[i + 1] - p[i + 2]) * u2
                              + (-p[i - 1] + 3 * p[i] - 3 * p[i + 1] + p[i + 2]) * u3))
    out.append(p[-2])
    return resample(np.array(out), step)


def resample(poly, step):
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    ss = np.linspace(0.0, s[-1], max(int(round(s[-1] / step)), 1) + 1)
    return np.stack([np.interp(ss, s, poly[:, k]) for k in range(3)], 1), ss


def resample_with(poly, ups, step):
    """resample(), carrying an up vector per point along."""
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    curve, ss = resample(poly, step)
    return curve, ss, np.stack([np.interp(ss, s, ups[:, k]) for k in range(3)], 1)


def at(curve, arcs, s):
    """Point of a sampled curve at arc length s (clamped to its ends)."""
    return np.array([np.interp(s, arcs, curve[:, k]) for k in range(3)])


def project_arc(pts, curve, arcs):
    """Arc length along the curve of the point on it nearest each of `pts`, and the distance to it."""
    a, b = curve[:-1], curve[1:]
    ab = b - a
    ll = np.maximum((ab * ab).sum(1), 1e-12)
    best_s = np.zeros(len(pts))
    best_d = np.full(len(pts), np.inf)
    for i in range(len(a)):
        u = np.clip(((pts - a[i]) @ ab[i]) / ll[i], 0.0, 1.0)
        d = np.linalg.norm(pts - (a[i] + np.outer(u, ab[i])), axis=1)
        m = d < best_d
        best_d[m] = d[m]
        best_s[m] = arcs[i] + u[m] * (arcs[i + 1] - arcs[i])
    return best_s, best_d


def frames_along(curve, arcs, ups, bone_arcs):
    """A bone frame at each of bone_arcs along a curve: the origin on it, Y toward the next bone (the last
    keeps the one before's), Z the curve's up made square to Y. `ups` are per sample (or one for all)."""
    pts = [at(curve, arcs, s) for s in bone_arcs]
    out = []
    for k, p in enumerate(pts):
        y = unit(pts[k + 1] - p) if k + 1 < len(pts) else unit(p - pts[k - 1])
        u = at(ups, arcs, bone_arcs[k]) if np.ndim(ups) == 2 else np.asarray(ups, dtype=float)
        z = unit(u - y * np.dot(u, y))
        m = np.eye(4)
        m[:3, :3] = np.column_stack([np.cross(y, z), y, z])
        m[:3, 3] = p
        out.append(m)
    return out


# ---------------------------------------------------------------- the skeleton

class Body:
    """The snake as it lies in the mesh: its middle line, the bones along it and how far the body reaches
    round it."""

    def __init__(self, pos, skin):
        self.curve, self.arcs = catmull_rom(GUIDE, 0.01)
        self.length = float(self.arcs[-1])
        step = (self.length - HEAD_PIVOT) / SPINE_BONES
        self.bone_arcs = [HEAD_PIVOT + k * step for k in range(SPINE_BONES + 1)]
        self.names = ["head"] + ["spine_%02d" % (k + 1) for k in range(SPINE_BONES)]
        self.rest = frames_along(self.curve, self.arcs, Y, self.bone_arcs)
        s, d = project_arc(pos[skin], self.curve, self.arcs)
        # How thick the body is down its length: the reach of the skin round the middle line, every 0.1 m.
        self.radius = []
        for s0 in np.arange(0.0, self.length, 0.1):
            m = (s >= s0) & (s < s0 + 0.1)
            self.radius.append((round(float(s0), 2), round(float(np.percentile(d[m], 75)), 3) if m.sum() > 3 else None))


def classify(pos, parts):
    """Which piece of the mesh goes where: "skin" (the snake, bending along the body), "gear" (bending with
    it too), "rifle" or "headgear" (rigid)."""
    kind = {}
    for k, idx in enumerate(parts):
        p = pos[idx]
        c = p.mean(0)
        size = p.max(0) - p.min(0)
        if k == 0:
            kind[k] = "skin"
        elif size[2] > 1.5 and size[0] < 0.25:
            kind[k] = "rifle"  # the barrel, the receiver and the stock in one piece
        elif c[1] >= RIFLE_Y and abs(c[0] - RIFLE_X) <= RIFLE_HALF_X and size[0] <= RIFLE_WIDE and c[2] < RIFLE_Z:
            kind[k] = "rifle"
        elif c[2] >= HEADGEAR_Z:
            kind[k] = "headgear"
        else:
            kind[k] = "gear"
    return kind


def skin_weights(pos, parts, kind, body):
    """Per vertex {bone: weight}: the skin and the gear on it between the bones either side along the body
    (all head from the snout back to its origin), the rifle and the headgear rigidly."""
    weights = [None] * len(pos)
    bend = [i for k, idx in enumerate(parts) if kind[k] in ("skin", "gear") for i in idx]
    s, _ = project_arc(pos[bend], body.curve, body.arcs)
    arcs = np.array(body.bone_arcs)
    for i, si in zip(bend, s):
        if si <= arcs[0]:
            weights[i] = {"head": 1.0}
            continue
        k = min(int(np.searchsorted(arcs, si)) - 1, len(arcs) - 2)
        u = float(np.clip((si - arcs[k]) / (arcs[k + 1] - arcs[k]), 0.0, 1.0))
        weights[i] = {body.names[k]: 1.0 - u, body.names[k + 1]: u} if u > 1e-4 else {body.names[k]: 1.0}
    for k, idx in enumerate(parts):
        if kind[k] in ("rifle", "headgear"):
            for i in idx:
                weights[i] = {"rifle" if kind[k] == "rifle" else "head": 1.0}
    return weights


def rifle_frames(pos, parts, kind):
    """The rifle's bone (on the barrel's line over the receiver, Y up the barrel) and its muzzle's, from the
    barrel: a line fitted through the long piece forward of the receiver."""
    long_piece = next(idx for k, idx in enumerate(parts) if kind[k] == "rifle")
    r = pos[long_piece]
    barrel = r[r[:, 2] > 1.0]
    c0 = barrel.mean(0)
    d = np.linalg.svd(barrel - c0)[2][0]
    d = d * np.sign(d[2])
    z = unit(Y - d * np.dot(Y, d))
    basis = np.column_stack([np.cross(d, z), d, z])
    rifle = np.eye(4)
    rifle[:3, :3] = basis
    rifle[:3, 3] = c0 + d * (RIFLE_ORIGIN_Z - c0[2]) / d[2]
    muzzle = rifle.copy()
    muzzle[:3, 3] = c0 + d * ((r - c0) @ d).max()
    return rifle, muzzle


def rebuild(js, binary):
    """Swaps the auto-rig for the new skeleton: the mesh node and the bones under one Armature node, the
    skin's joints and inverse bind matrices, the vertices' joints and weights."""
    mesh_node = next(n for n in js["nodes"] if "skin" in n)
    prim = js["meshes"][mesh_node["mesh"]]["primitives"][0]
    pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    tris = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    parts = pieces(pos, tris)
    kind = classify(pos, parts)
    body = Body(pos, parts[0])
    counts = {v: sum(len(parts[k]) for k in kind if kind[k] == v) for v in ("skin", "gear", "rifle", "headgear")}
    print(f"mesh: {len(pos)} vertices in {len(parts)} pieces: " + ", ".join(f"{v} {n}" for v, n in counts.items()))
    print(f"body: {body.length:.2f} m snout to tail, {SPINE_BONES} spine bones {body.bone_arcs[1] - body.bone_arcs[0]:.3f} m apart")
    print("body radius every 0.1 m from the snout: " + " ".join(f"{r}" for _, r in body.radius))
    weights = skin_weights(pos, parts, kind, body)
    rifle, muzzle = rifle_frames(pos, parts, kind)
    mount = body.names[int(np.argmin([abs(a - RIFLE_MOUNT) for a in body.bone_arcs]))]
    snout = body.rest[0].copy()
    snout[:3, 3] = body.curve[0]
    world = dict(zip(body.names, body.rest))
    world.update({"rifle": rifle, "muzzle": muzzle, "snout": snout})
    bones = [(n, body.names[k - 1] if k > 0 else None) for k, n in enumerate(body.names)]
    bones += [("rifle", mount), ("muzzle", "rifle"), ("snout", "head")]
    nodes = [{"name": "Armature", "children": [1, 2]}, {"name": mesh_node.get("name", "serpent"), "mesh": mesh_node["mesh"], "skin": 0}]
    index = {}
    for name, parent in bones:
        local = world[name] if parent is None else np.linalg.inv(world[parent]) @ world[name]
        node = {"name": name}
        set_trs(node, local)
        index[name] = len(nodes)
        nodes.append(node)
        if parent is not None:
            nodes[index[parent]].setdefault("children", []).append(index[name])
    js["nodes"] = nodes
    js["scenes"] = [{"name": "Scene", "nodes": [0]}]
    js["scene"] = 0
    joint_names = [b[0] for b in bones]
    joint_index = {name: k for k, name in enumerate(joint_names)}
    ibm = np.array([np.linalg.inv(world[name]).T.reshape(16) for name in joint_names])
    js["skins"] = [{"name": "Armature", "joints": [index[n] for n in joint_names], "skeleton": index["head"],
                    "inverseBindMatrices": add_accessor(js, binary, ibm, "MAT4")}]
    jw, ww = pack_weights(weights, joint_index)
    binary += b"\0" * (-len(binary) % 4)
    view = {"buffer": 0, "byteOffset": len(binary), "byteLength": jw.nbytes}
    binary += jw.tobytes()
    js["bufferViews"].append(view)
    js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5121, "count": len(jw), "type": "VEC4"})
    prim["attributes"]["JOINTS_0"] = len(js["accessors"]) - 1
    prim["attributes"]["WEIGHTS_0"] = add_accessor(js, binary, ww, "VEC4")
    js["animations"] = []
    print(f"rifle on {mount}: barrel {np.round(rifle[:3, 1], 3)}, muzzle at {np.round(muzzle[:3, 3], 3)}")
    return body


# ---------------------------------------------------------------- clips

def rest_heights(body):
    """How high the middle of the body rides at each arc as it lies in the mesh (the head held up a little)."""
    return lambda s: float(np.interp(s, body.arcs, body.curve[:, 1]))


def lay_out(body, lateral, lift=lambda s: 0.0):
    """A pose on the ground, heading +Z, its middle at the origin: each point of the body `lateral(s)` m to
    the side of the line (+X its left) and as high as it lies in the mesh (plus lift(s)). The arcs along it
    stay those of the body, so it neither stretches nor shrinks."""
    height = rest_heights(body)
    ss = np.arange(0.0, body.length + 0.005, 0.01)
    x = np.array([lateral(s) for s in ss])
    y = np.array([height(s) + lift(s) for s in ss])
    dx, dy = np.gradient(x, ss), np.gradient(y, ss)
    dz = np.sqrt(np.maximum(1.0 - dx * dx - dy * dy, 0.04))
    z = -np.concatenate([[0.0], np.cumsum(0.5 * (dz[1:] + dz[:-1]) * np.diff(ss))])
    z -= np.interp(body.length * 0.5, ss, z)
    return np.stack([x, y, z], 1), ss


def gun_share(s):
    """0 along the front that carries the rifle, rising to 1 a metre behind it."""
    t = min(max((s - GUN_LENGTH) / 1.0, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def bake(body, pose_at, frames):
    """Keys for every bone of the chain, `frames` frames of the pose that pose_at(t) lays out (plus a copy of
    the first, for a seamless loop): each bone's local transform."""
    keys = []
    for f in range(frames + 1):
        curve, arcs = pose_at((f % frames) / FPS)
        fr = frames_along(curve, arcs, Y, body.bone_arcs)
        glob = dict(zip(body.names, fr))
        local = {}
        for k, n in enumerate(body.names):
            local[n] = glob[n] if k == 0 else np.linalg.inv(glob[body.names[k - 1]]) @ glob[n]
        keys.append(local)
    return keys


def slither(body, t):
    period = SLITHER_WAVE / SLITHER_SPEED
    return lay_out(body, lambda s: SLITHER_AMP * (0.06 + 0.94 * gun_share(s)) * math.sin(2 * math.pi * (s / SLITHER_WAVE - t / period)))


def idle(body, t):
    w = 2 * math.pi * t / IDLE_TIME

    def lateral(s):
        rear = gun_share(s)
        curl = max(s - (body.length - 1.0), 0.0)  # the last metre of the tail curls slowly
        return rear * (0.3 * math.sin(math.pi * min(max((s - GUN_LENGTH) / (body.length - GUN_LENGTH), 0.0), 1.0))
                       + 0.025 * math.sin(w - 1.6 * s)) + 0.12 * curl * curl * math.sin(w * 2.0 + 0.7)

    return lay_out(body, lateral, lambda s: BREATH * (0.5 + 0.5 * math.sin(w)) * min(s / 0.8, 1.0) * (1.0 - 0.6 * gun_share(s)))


def write_clips(js, binary, clips, names):
    """Every bone's rotation and translation, one key a frame."""
    js["animations"] = []
    idx = {n["name"]: i for i, n in enumerate(js["nodes"]) if "name" in n}
    for clip, keys in clips.items():
        times = np.arange(len(keys), dtype=np.float32) / FPS
        tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
        anim = {"name": clip, "channels": [], "samplers": []}
        for bone in names:
            quats = []
            prev = None
            for k in keys:
                q = mat_to_quat(k[bone][:3, :3])
                if prev is not None and np.dot(q, prev) < 0:
                    q = -q  # the short way round
                quats.append(q)
                prev = q
            for path, data in (("rotation", np.array(quats)), ("translation", np.array([k[bone][:3, 3] for k in keys]))):
                out = add_accessor(js, binary, data, "VEC4" if path == "rotation" else "VEC3")
                anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
                anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": path}})
        js["animations"].append(anim)


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    body = rebuild(js, binary)
    slither_frames = int(round(SLITHER_WAVE / SLITHER_SPEED * FPS))
    clips = {"Slither": bake(body, lambda t: slither(body, t), slither_frames),
             "Idle": bake(body, lambda t: idle(body, t), int(IDLE_TIME * FPS))}
    write_clips(js, binary, clips, body.names)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/rig_serpent.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(body.names) + 3} bones, clips {list(clips)} ({slither_frames} and {int(IDLE_TIME * FPS)} frames)")
    if args.preview:
        render_preview(args.output, args.preview, body)


# ---------------------------------------------------------------- preview

def posed(js, binary, locals_=None, clip=None, frame=0):
    """The mesh posed by a clip's frame, or by local transforms {node name: 4x4} (else the rest pose); its
    triangles, UVs and every node's model-space matrix by name."""
    nodes = js["nodes"]
    local = {i: trs(n) for i, n in enumerate(nodes)}
    if clip is not None:
        anim = next(a for a in js["animations"] if a["name"] == clip)
        for ch in anim["channels"]:
            vals = accessor(js, binary, anim["samplers"][ch["sampler"]]["output"]).astype(float)
            i = ch["target"]["node"]
            m = local[i].copy()
            if ch["target"]["path"] == "rotation":
                m[:3, :3] = quat_to_mat(vals[min(frame, len(vals) - 1)])
            else:
                m[:3, 3] = vals[min(frame, len(vals) - 1)]
            local[i] = m
    if locals_:
        for i, n in enumerate(nodes):
            if n.get("name") in locals_:
                local[i] = locals_[n["name"]]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    world = {}

    def w(i):
        if i not in world:
            world[i] = (w(parent[i]) if i in parent else np.eye(4)) @ local[i]
        return world[i]

    skin = js["skins"][0]
    ibm = accessor(js, binary, skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4).transpose(0, 2, 1)
    mats = np.array([w(j) @ ibm[k] for k, j in enumerate(skin["joints"])])
    node = next(n for n in nodes if "skin" in n)
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    joints = accessor(js, binary, prim["attributes"]["JOINTS_0"]).astype(int)
    weights = accessor(js, binary, prim["attributes"]["WEIGHTS_0"]).astype(float)
    hom = np.concatenate([pos, np.ones((len(pos), 1))], 1)
    out = np.zeros((len(pos), 3))
    for k in range(4):
        out += weights[:, k:k + 1] * np.einsum("nij,nj->ni", mats[joints[:, k]], hom)[:, :3]
    idx = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    uv = accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)
    return out, idx, uv, {n["name"]: w(i) for i, n in enumerate(nodes) if "name" in n}


def test_pose(body, curve, arcs, ups, front):
    """Local transforms laying the chain along a curve that runs tail to snout, the snout at arc `front` of it
    (the way the game's SerpentRig does), the rifle riding its bone."""
    fr = frames_along(curve, arcs, ups, [front - a for a in body.bone_arcs])
    glob = dict(zip(body.names, fr))
    return {n: glob[n] if k == 0 else np.linalg.inv(glob[body.names[k - 1]]) @ glob[n] for k, n in enumerate(body.names)}


def trunk_coil(body, radius, turns_up):
    """The body wound up round a vertical trunk of `radius` at the origin (the snake's radius out from it), the
    front straight up it, the rest coiling down round it: tail first along the curve, snout last."""
    r = radius + 0.15
    rear = body.length - GUN_LENGTH
    pitch = rear / turns_up
    climb = math.sqrt(max(pitch * pitch - (2 * math.pi * r) ** 2, 0.01)) if pitch > 2 * math.pi * r else 0.6
    pts, ups = [], []
    for u in np.linspace(0.0, 1.0, 120):
        a = 2 * math.pi * turns_up * u
        pts.append((r * math.cos(a), 0.4 + climb * turns_up * u, r * math.sin(a)))
        ups.append((math.cos(a), 0.0, math.sin(a)))
    top = np.array(pts[-1])
    for h in np.linspace(0.05, GUN_LENGTH + 0.2, 40):
        pts.append(top + Y * h)
        ups.append(ups[-1])
    return resample_with(np.array(pts), np.array(ups), 0.01)


def flat_coil(body, radius):
    """The body coiled flat round a bush of `radius` at the origin, the second turn on top of the first."""
    r = radius + 0.15
    pts = []
    turns = body.length / (2 * math.pi * r)
    for u in np.linspace(0.0, 1.0, 200):
        a = 2 * math.pi * turns * u
        pts.append((r * math.cos(a), 0.15 + 0.26 * max(u * turns - 0.85, 0.0), r * math.sin(a)))
    return resample_with(np.array(pts), np.tile(Y, (len(pts), 1)), 0.01)


def render_preview(path, out_dir, body):
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    js, binary = read_glb(path)
    mat = js["materials"][0]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    tex = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((512, 512)), dtype=np.float32) / 255.0
    lengths = {a["name"]: int(accessor(js, binary, a["samplers"][0]["input"]).shape[0]) for a in js["animations"]}
    W, H = 300, 230
    views = {"side": (np.array([5.5, 1.4, 0.0]), np.array([0.0, 0.3, 0.0])),
             "rts": (np.array([4.0, 6.0, -4.0]), np.array([0.0, 0.2, 0.0]))}
    shots = [("rest", None, None, [0])] + [(c, c, None, sorted(set(np.linspace(0, lengths[c] - 1, 6).round().astype(int))))
                                           for c in lengths]
    curve, arcs, ups = trunk_coil(body, 0.12, 1.4)
    shots.append(("trunk", None, test_pose(body, curve, arcs, ups, arcs[-1]), [0]))
    curve, arcs, ups = flat_coil(body, 0.45)
    shots.append(("coil", None, test_pose(body, curve, arcs, ups, arcs[-1]), [0]))
    for name, clip, locals_, frames in shots:
        tiles = []
        for f in frames:
            pts, idx, uv, nodes = posed(js, binary, locals_, clip, f)
            travel = SLITHER_SPEED * f / FPS if clip == "Slither" else 0.0
            pts = pts + Z * travel
            vs = views if name not in ("trunk",) else {"side": (np.array([4.2, 2.4, 0.0]), np.array([0.0, 1.7, 0.0])),
                                                         "rts": (np.array([3.0, 6.0, -3.0]), np.array([0.0, 1.5, 0.0]))}
            for vname, (eye, target) in vs.items():
                eye_t, target_t = eye + Z * travel, target + Z * travel
                img = np.ones((H, W, 3), np.float32) * np.array([0.6, 0.7, 0.8], np.float32)
                zb = np.full((H, W), np.inf, np.float32)
                rasterize(img, zb, pts, idx, uv, tex, eye_t, target_t)
                pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
                dr = ImageDraw.Draw(pil)
                for zk in np.arange(math.floor(travel - 4), travel + 4, 0.5):
                    seg = np.array([[-1.5, 0, zk], [1.5, 0, zk]])
                    sx, sy, cz = project(seg, eye_t, target_t, W, H)
                    if (cz > 0.1).all():
                        dr.line([(sx[0], sy[0]), (sx[1], sy[1])], fill=(70, 95, 70))
                mz = nodes["muzzle"]
                tip = mz[:3, 3] + Z * travel
                s = np.array([tip, tip + mz[:3, :3] @ Y * 0.8])
                sx, sy, cz = project(s, eye_t, target_t, W, H)
                if (cz > 0.1).all():
                    dr.line([(sx[0], sy[0]), (sx[1], sy[1])], fill=(255, 120, 0), width=2)
                dr.text((4, 4), f"{name} {f} {vname}", fill=(0, 0, 0))
                tiles.append(pil)
        cols = 2 * min(len(frames), 3)
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (W * cols, H * rows))
        for k, p in enumerate(tiles):
            sheet.paste(p, (W * (k % cols), H * (k // cols)))
        sheet.save(os.path.join(out_dir, f"{name}.png"))
    print(f"preview in {out_dir}")


if __name__ == "__main__":
    main()
