"""Small glTF 2.0 (.glb) helpers for the scripts in tools/gltf, which run on numpy alone (no Blender):
reading and writing the container, reading accessors, adding new ones, node transforms and
quaternions. Column vectors throughout: a node's matrix is T @ R @ S."""
import json
import struct

import numpy as np

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
DTYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def read_glb(path):
    data = open(path, "rb").read()
    _, _, length = struct.unpack_from("<III", data, 0)
    off = 12
    js, binary = None, b""
    while off < length:
        size, kind = struct.unpack_from("<II", data, off)
        chunk = data[off + 8:off + 8 + size]
        if kind == JSON_CHUNK:
            js = json.loads(chunk)
        elif kind == BIN_CHUNK:
            binary = bytes(chunk)
        off += 8 + size
    return js, bytearray(binary)


def write_glb(path, js, binary):
    binary = bytes(binary) + b"\0" * (-len(binary) % 4)
    js["buffers"] = [{"byteLength": len(binary)}]
    text = json.dumps(js, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), JSON_CHUNK) + text)
        f.write(struct.pack("<II", len(binary), BIN_CHUNK) + binary)


def accessor(js, binary, index):
    """An accessor's data as a (count, components) array (normalized ints left as they are)."""
    a = js["accessors"][index]
    view = js["bufferViews"][a["bufferView"]]
    n = COMPONENTS[a["type"]]
    dt = np.dtype(DTYPES[a["componentType"]])
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or n * dt.itemsize
    raw = np.frombuffer(bytes(binary), dtype=np.uint8, count=stride * (a["count"] - 1) + n * dt.itemsize, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], n * dt.itemsize), strides=(stride, 1))
    return rows.copy().view(dt).reshape(a["count"], n)


def add_accessor(js, binary, data, kind, with_bounds=False):
    """Appends float32 `data` ((count, n) or (count,)) as a new accessor of `kind`; returns its index."""
    arr = np.ascontiguousarray(np.asarray(data, dtype=np.float32))
    if arr.ndim == 1:
        arr = arr.reshape(-1, 1)
    binary += b"\0" * (-len(binary) % 4)
    view = {"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes}
    binary += arr.tobytes()
    js["bufferViews"].append(view)
    acc = {"bufferView": len(js["bufferViews"]) - 1, "componentType": 5126, "count": int(arr.shape[0]), "type": kind}
    if with_bounds:
        acc["min"] = [float(v) for v in arr.min(0)]
        acc["max"] = [float(v) for v in arr.max(0)]
    js["accessors"].append(acc)
    return len(js["accessors"]) - 1


def compact(js, binary):
    """Drops buffer views and accessors nothing refers to any more; returns the new binary."""
    used_acc = set()
    for mesh in js.get("meshes", []):
        for p in mesh["primitives"]:
            used_acc.update(p["attributes"].values())
            if "indices" in p:
                used_acc.add(p["indices"])
            for t in p.get("targets", []):
                used_acc.update(t.values())
    for skin in js.get("skins", []):
        if "inverseBindMatrices" in skin:
            used_acc.add(skin["inverseBindMatrices"])
    for anim in js.get("animations", []):
        for s in anim["samplers"]:
            used_acc.update((s["input"], s["output"]))
    acc_map = {}
    accessors = []
    for i, a in enumerate(js["accessors"]):
        if i in used_acc:
            acc_map[i] = len(accessors)
            accessors.append(a)
    used_views = {a["bufferView"] for a in accessors if "bufferView" in a}
    used_views.update(im["bufferView"] for im in js.get("images", []) if "bufferView" in im)
    view_map = {}
    views = []
    out = bytearray()
    for i, v in enumerate(js["bufferViews"]):
        if i not in used_views:
            continue
        start = v.get("byteOffset", 0)
        chunk = binary[start:start + v["byteLength"]]
        out += b"\0" * (-len(out) % 4)
        nv = dict(v)
        nv["byteOffset"] = len(out)
        out += chunk
        view_map[i] = len(views)
        views.append(nv)
    for a in accessors:
        a["bufferView"] = view_map[a["bufferView"]]
    for im in js.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = view_map[im["bufferView"]]
    js["accessors"] = accessors
    js["bufferViews"] = views
    for mesh in js.get("meshes", []):
        for p in mesh["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
    for skin in js.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
    for anim in js.get("animations", []):
        for s in anim["samplers"]:
            s["input"] = acc_map[s["input"]]
            s["output"] = acc_map[s["output"]]
    return out


# ---------------------------------------------------------------- transforms

def quat_to_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def mat_to_quat(m):
    """Unit quaternion (x, y, z, w) of a rotation matrix (orthonormalized first)."""
    u, _, vt = np.linalg.svd(m)
    r = u @ vt
    tr = np.trace(r)
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        q = [(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, 0.25 * s]
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
        q = [0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s, (r[2, 1] - r[1, 2]) / s]
    elif r[1, 1] > r[2, 2]:
        s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
        q = [(r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s, (r[0, 2] - r[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
        q = [(r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s, (r[1, 0] - r[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def axis_angle(axis, angle):
    a = np.asarray(axis, dtype=float)
    a = a / np.linalg.norm(a)
    x, y, z = a
    c, s = np.cos(angle), np.sin(angle)
    t = 1 - c
    return np.array([[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
                     [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
                     [t * x * z - s * y, t * y * z + s * x, t * z * z + c]])


def trs(node):
    """A node's local 4x4 matrix."""
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(node.get("rotation", [0, 0, 0, 1])) * np.array(node.get("scale", [1, 1, 1]))
    m[:3, 3] = node.get("translation", [0, 0, 0])
    return m


def set_trs(node, m):
    """Writes a 4x4 (rotation and translation, unit scale) into a node as TRS."""
    node.pop("matrix", None)
    node["translation"] = [float(v) for v in m[:3, 3]]
    node["rotation"] = [float(v) for v in mat_to_quat(m[:3, :3])]
    node.pop("scale", None)


def translation(p):
    m = np.eye(4)
    m[:3, 3] = p
    return m


def rotation(r):
    m = np.eye(4)
    m[:3, :3] = r
    return m
