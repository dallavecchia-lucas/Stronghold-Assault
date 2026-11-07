"""Vehicle prep: the Meshy machines cut into the moving parts the game animates, on numpy alone (no Blender).

  fighter_jet  the defenders' Defender fighter jet (assets_src/defenders/defender_fighter_jet): ailerons, flaps,
               all-moving stabilators, rudders on the canted fins and the two engine nozzles (they vector);
               `exhaust_L/R` on the nozzles for the afterburner flames, `missile_<k>` on the pylons.
  drone        the defenders' Defender drone (assets_src/defenders/defender_drone): the two wing-tip ducted fan
               pods tilt (`pod_L/R`) and the fans spin inside them (`fan_L/R`); `exhaust_L/R` on the two rear
               engines, `muzzle_L/R` on the twin guns.
  hover_tank   the defenders' Iron Vanguard hover tank (assets_src/defenders/iron_vanguard): the turret turns
               (`turret`), the gun elevates (`gun`) and the barrel recoils in it (`barrel`, `muzzle` at its tip);
               the twin machine guns in the sponsons on the hull's sides turn on their mounts (`mg_L/R`,
               `mg_muzzle_<side>1/2` at the barrels' tips);
               four gimballed hover thrusters under the hull (`thruster_FL/FR/RL/RR`, `jet_*` where the thrust
               comes out) and `booster_L/R` on the rear vents.
  helicopter   the attackers' Heavy Lift Helicopter (assets_src/units/heavy_lift_helicopter): a tandem lifter,
               the front rotor (`rotor_F`), the rear one on the hump (`rotor_R`) and the ducted tail fan
               (`tail_fan`).

Every model comes out at its game size in metres, its front +Z, up +Y, its origin on the ground under its
middle (the drone and the jet: under the middle of the fuselage, their lowest point at y = 0). The parts are
pieces of the Meshy mesh: whole pieces where the mesh has them apart (rotor blades, fans, the turret), cut out
of it where it doesn't (an aileron out of its wing, a rudder out of its fin), every triangle across a cut
clipped exactly at it. Each part is a node at its pivot whose axes say how it moves, so the game only has to
turn it about one of them (VehicleRig and the rigs under game/scripts/vehicles):

  hinges (control surfaces, nozzles, the gun, the drone's pods): turn about local +X; a positive angle moves
      the trailing edge down (ailerons, flaps, stabilators), a rudder's trailing edge to the vehicle's left
      (+X), a nozzle's exit down, the gun's muzzle up, a pod's fan tilting forward;
  spinners (rotors, fans, the turret): turn about local +Y (the rotors' and fans' shafts, the turret's ring);
  markers (exhausts, muzzles, jets): empty nodes, local +Z out of the barrel or along the exhaust.

Textures are fitted to --size (default 1024; the helicopter 2048) like tools/gltf/process_prop.py does.

  python3 tools/gltf/rig_vehicles.py --vehicle fighter_jet \\
      --input assets_src/defenders/defender_fighter_jet/defender_fighter_jet_meshy.glb \\
      --output game/assets/defenders/defender_fighter_jet/defender_fighter_jet.glb [--preview out.png]

--preview draws the parts in colours of their own, at rest and deflected.
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, add_accessor, axis_angle, compact, mat_to_quat, read_glb, write_glb  # noqa: E402
from process_prop import shrink_images  # noqa: E402
from split_raft import components, gather  # noqa: E402

## Game sizes (m): the length nose to tail (the tank's with its gun forward, the helicopter's without the
## rotors' sweep). The helicopter is immense: war elephants ride in its hold.
LENGTH = {"fighter_jet": 18.0, "drone": 1.8, "hover_tank": 10.0, "helicopter": 64.0}
## The length the cuts below were measured at (m), where it isn't the game's: the model is cut at this size,
## then scaled to LENGTH.
REF_LENGTH = {"hover_tank": 11.0}
TEX_SIZE = {"helicopter": 2048}
NAMES = {"fighter_jet": "DefenderFighterJet", "drone": "DefenderDrone", "hover_tank": "IronVanguard",
         "helicopter": "HeavyLiftHelicopter"}

X, Y, Z = np.eye(3)


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


class Model:
    """The Meshy mesh in the game's frame: one vertex pool (positions, normals, UVs), triangles each owned
    by a part ("" is the body), the connected piece each triangle came from and those pieces' bounds."""

    def __init__(self, js, binary, length):
        pos, nrm, uv, tris, self.material = gather(js, binary)
        # Meshy's machines face -X: turn them to face +Z (x' = z, z' = -x), up stays +Y.
        pos = np.stack([pos[:, 2], pos[:, 1], -pos[:, 0]], 1)
        nrm = np.stack([nrm[:, 2], nrm[:, 1], -nrm[:, 0]], 1)
        lo, hi = pos.min(0), pos.max(0)
        self.scale = length / (hi[2] - lo[2])
        pos = (pos - np.array([(lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5])) * self.scale
        self.pos, self.nrm, self.uv = list(pos), list(nrm), list(uv)
        self.comp = components(pos, tris)
        self.tris = [list(t) for t in tris]
        self.tri_comp = list(self.comp)
        self.owner = [""] * len(self.tris)
        self.info = {}
        for c in np.unique(self.comp):
            sel = np.nonzero(self.comp == c)[0]
            v = pos[np.unique(tris[sel].reshape(-1))]
            self.info[int(c)] = {"lo": v.min(0), "hi": v.max(0), "ctr": (v.min(0) + v.max(0)) * 0.5,
                                 "size": v.max(0) - v.min(0), "n": len(sel)}

    def pick(self, pred):
        """The pieces whose bounds pass pred(lo, hi, ctr, size) (a set of ids)."""
        return {c for c, i in self.info.items() if pred(i["lo"], i["hi"], i["ctr"], i["size"])}

    def bounds(self, comps):
        lo = np.min([self.info[c]["lo"] for c in comps], 0)
        hi = np.max([self.info[c]["hi"] for c in comps], 0)
        return lo, hi

    def _split_vertex(self, a, b, da, db, cache):
        key = (min(a, b), max(a, b))
        if key not in cache:
            t = da / (da - db)
            self.pos.append(self.pos[a] + (self.pos[b] - self.pos[a]) * t)
            n = self.nrm[a] + (self.nrm[b] - self.nrm[a]) * t
            self.nrm.append(n / max(np.linalg.norm(n), 1e-12))
            self.uv.append(self.uv[a] + (self.uv[b] - self.uv[a]) * t)
            cache[key] = len(self.pos) - 1
        return cache[key]

    def _clip(self, tris, plane, cache):
        """Splits triangles by a plane (normal, point): (those on its positive side, those on its negative)."""
        n, p0 = plane
        inside, outside = [], []
        for tri in tris:
            d = [float(np.dot(n, self.pos[i] - p0)) for i in tri]
            if all(v >= 0 for v in d):
                inside.append(tri)
                continue
            if all(v <= 0 for v in d):
                outside.append(tri)
                continue
            pin, pout = [], []
            for j in range(3):
                a, b = tri[j], tri[(j + 1) % 3]
                da, db = d[j], d[(j + 1) % 3]
                (pin if da >= 0 else pout).append(a)
                if da == 0:
                    pout.append(a)
                if (da > 0 > db) or (da < 0 < db):
                    k = self._split_vertex(a, b, da, db, cache)
                    pin.append(k)
                    pout.append(k)
            for poly, dst in ((pin, inside), (pout, outside)):
                for j in range(1, len(poly) - 1):
                    dst.append([poly[0], poly[j], poly[j + 1]])
        return inside, outside

    def take(self, name, comps, planes=()):
        """Gives part `name` the body's triangles from pieces `comps`, inside all the planes (cut exactly)."""
        idx = [k for k, (o, c) in enumerate(zip(self.owner, self.tri_comp)) if o == "" and c in comps]
        if not idx:
            raise SystemExit(f"{name}: nothing to take")
        tris = [self.tris[k] for k in idx]
        cache = {}
        rest = []
        for plane in planes:
            tris, out = self._clip(tris, plane, cache)
            rest += out
        keep = set(idx)
        self.tris = [t for k, t in enumerate(self.tris) if k not in keep] + tris + rest
        self.owner = [o for k, o in enumerate(self.owner) if k not in keep] + [name] * len(tris) + [""] * len(rest)
        cid = [self.tri_comp[k] for k in idx]
        self.tri_comp = [c for k, c in enumerate(self.tri_comp) if k not in keep] + [cid[0]] * (len(tris) + len(rest))
        if not tris:
            raise SystemExit(f"{name}: the cut left nothing")
        return tris

    def part_points(self, name):
        return np.array([self.pos[i] for t, o in zip(self.tris, self.owner) if o == name for i in t])


def frame(x=None, y=None, hint=None):
    """A rotation whose local X (a hinge) or local Y (a shaft) is the given axis, the other axes as close
    to the vehicle's own as they can be (hint: the axis local Y, or local Z, should lean toward)."""
    if x is not None:
        x = unit(x)
        h = unit(hint if hint is not None else Y)
        y = unit(h - np.dot(h, x) * x)
        return np.stack([x, y, np.cross(x, y)], 1)
    y = unit(y)
    h = unit(hint if hint is not None else Z)
    z = unit(h - np.dot(h, y) * y)
    return np.stack([np.cross(y, z), y, z], 1)


def plane_through(a, b, toward):
    """The vertical-ish plane through the line a-b (and the line's normal in its own plane), facing `toward`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = unit(b - a)
    t = np.asarray(toward, float) - a
    n = unit(t - np.dot(t, d) * d)
    return n, a


def plane(n, p):
    return unit(n), np.asarray(p, float)


# ------------------------------------------------------------------------------------------- the vehicles
# Each returns the nodes: (name, parent, pivot, rotation) in build order (parts) and the markers
# (name, parent, position, +Z direction). The numbers are read off the model in the game's frame.

def fighter_jet(m):
    nodes, marks = [], []
    # The outer wing panels: a root chord from z 0.25 to -4.95 at |x| 4.4, a tip chord from -1.84 to -3.48 at
    # |x| 10. The hinge line runs at 72% of the chord; the flap from the root out to 6.4 m, the aileron on to 9.5.
    for side, s in (("L", 1.0), ("R", -1.0)):
        wing = m.pick(lambda lo, hi, c, sz: sz[0] > 5.0 and sz[1] < 0.6 and c[0] * s > 6.0)
        root = np.array([4.4 * s, 1.73, 0.25 - 0.72 * 5.2])
        tip = np.array([10.0 * s, 1.58, -1.84 - 0.72 * 1.64])
        behind = plane_through(root, tip, [6.0 * s, 1.7, -9.0])
        axis = unit(tip - root) * (-s)  # +angle: trailing edge down
        for name, x0, x1 in (("flap", 4.0, 6.4), ("aileron", 6.4, 9.6)):
            p = m.take(f"{name}_{side}", wing, [behind, plane([s, 0, 0], [x0 * s, 0, 0]), plane([-s, 0, 0], [x1 * s, 0, 0])])
            t = (x0 - 4.4) / 5.6
            nodes.append((f"{name}_{side}", "", root + (tip - root) * max(t, 0.0), frame(x=axis)))
        # The all-moving stabilator, about a spanwise axis at 40% of its chord.
        tail = m.pick(lambda lo, hi, c, sz: sz[1] < 0.1 and sz[0] > 2.0 and c[2] < -6.0 and c[0] * s > 2.5)
        m.take(f"stabilator_{side}", tail)
        nodes.append((f"stabilator_{side}", "", np.array([2.75 * s, 1.42, -7.35]), frame(x=-X)))
        # The canted fin: the rudder is its back 30% above the fuselage (y > 3.05).
        fin = m.pick(lambda lo, hi, c, sz: lo[0] * s > 2.3 and lo[1] > 2.4 and hi[2] < -4.0)
        f_root = np.array([2.82 * s, 3.05, -7.0])
        f_tip = np.array([3.68 * s, 4.6, -7.2])
        rudder = m.take(f"rudder_{side}", fin, [plane_through(f_root, f_tip, [2.9 * s, 3.5, -9.0]),
                                                plane([0, 1, 0], [0, 3.05, 0])])
        nodes.append((f"rudder_{side}", "", f_root, frame(x=unit(f_root - f_tip), hint=[s, 0, 0])))
        # The engine can and its nozzle, hinged at its front; the exhaust at its exit.
        eng = m.pick(lambda lo, hi, c, sz: sz[0] > 1.8 and sz[2] > 2.0 and c[2] < -7.0 and c[0] * s > 1.0 and sz[2] < 3.0)
        m.take(f"nozzle_{side}", eng)
        lo, hi = m.bounds(eng)
        c = (lo + hi) * 0.5
        nodes.append((f"nozzle_{side}", "", np.array([c[0], c[1], hi[2]]), frame(x=-X)))
        marks.append((f"exhaust_{side}", f"nozzle_{side}", np.array([c[0], c[1], lo[2]]), -Z))
        # The missiles on the pylons (two under each wing, inner first).
        rails = sorted(m.pick(lambda lo, hi, c, sz: sz[2] > 2.0 and sz[0] < 0.5 and c[0] * s > 5.0 and c[1] < 1.5),
                       key=lambda k: abs(m.info[k]["ctr"][0]))
        for k, r in enumerate(rails):
            i = m.info[r]
            marks.append((f"missile_{side}{k + 1}", "", np.array([i["ctr"][0], i["ctr"][1], i["hi"][2]]), Z))
    return nodes, marks


def drone(m):
    nodes, marks = [], []
    for side, s in (("L", 1.0), ("R", -1.0)):
        pod = m.pick(lambda lo, hi, c, sz: c[0] * s > 0.6)
        ring = max(pod, key=lambda k: m.info[k]["n"])
        hub = m.info[ring]["ctr"]
        fan = {k for k in pod if k != ring and math.hypot(*(m.info[k]["ctr"][[0, 2]] - hub[[0, 2]])) < 0.18
               and m.info[k]["size"][0] < 0.36}
        m.take(f"fan_{side}", fan)
        m.take(f"pod_{side}", pod - fan)
        nodes.append((f"pod_{side}", "", hub, frame(x=X)))
        nodes.append((f"fan_{side}", f"pod_{side}", hub, frame(y=Y)))
        marks.append((f"downwash_{side}", f"pod_{side}", hub - np.array([0, 0.11, 0]), -Y))
    eng = sorted(m.pick(lambda lo, hi, c, sz: c[2] < -0.8 and sz[2] < 0.11 and sz[0] < 0.12), key=lambda k: m.info[k]["ctr"][0])
    for side, k in (("R", eng[0]), ("L", eng[-1])):
        i = m.info[k]
        marks.append((f"exhaust_{side}", "", np.array([i["ctr"][0], i["ctr"][1], i["lo"][2]]), -Z))
    guns = m.pick(lambda lo, hi, c, sz: c[2] > 0.75 and sz[2] > 0.16 and sz[0] < 0.07)
    for side, s in (("L", 1.0), ("R", -1.0)):
        g = [k for k in guns if m.info[k]["ctr"][0] * s > 0]
        lo, hi = m.bounds(g)
        marks.append((f"muzzle_{side}", "", np.array([(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, hi[2]]), Z))
    return nodes, marks


def hover_tank(m):
    nodes, marks = [], []
    gun = m.pick(lambda lo, hi, c, sz: lo[1] > 2.8 and abs(c[0]) < 0.55 and c[2] > -0.4 and hi[2] > 0.5)
    # The barrel recoils; the short tubes either side of its root stay with the gun's mantlet.
    tubes = {k for k in gun if abs(m.info[k]["ctr"][0]) > 0.2 and m.info[k]["size"][0] < 0.2 and m.info[k]["size"][2] > 0.6}
    barrel = {k for k in gun if m.info[k]["lo"][2] > 0.5} - tubes
    m.take("barrel", barrel)
    m.take("gun", gun - barrel)
    turret = m.pick(lambda lo, hi, c, sz: lo[1] >= 2.58 and max(abs(lo[0]), abs(hi[0])) < 2.0 and c[2] < 0.3 and c[2] > -5.0)
    m.take("turret", turret - gun)
    ring = m.pick(lambda lo, hi, c, sz: sz[0] > 2.5 and sz[1] < 0.3 and abs(sz[0] - sz[2]) < 0.1)
    rc = m.info[min(ring, key=lambda k: abs(m.info[k]["ctr"][2] + 1.6))]["ctr"]
    trunnion = np.array([0.0, 3.33, -0.3])
    blo, bhi = m.bounds(barrel)
    nodes += [("turret", "", np.array([rc[0], rc[1], rc[2]]), frame(y=Y)),
              ("gun", "turret", trunnion, frame(x=-X)),
              ("barrel", "gun", trunnion, frame(x=-X))]
    marks.append(("muzzle", "barrel", np.array([(blo[0] + bhi[0]) * 0.5, (blo[1] + bhi[1]) * 0.5, bhi[2]]), Z))
    # The machine guns: a twin-barrelled gun in a sponson on each side of the hull, its mount 1.3 m up by the
    # front of the side skirt and its barrels reaching forward past it. Each turns on its mount (local Y up);
    # mg_muzzle_<side>1 is the upper barrel's tip, 2 the lower's.
    for side, s in (("L", 1.0), ("R", -1.0)):
        mg = m.pick(lambda lo, hi, c, sz: c[0] * s > 2.85 and 1.2 < c[1] < 1.75 and 0.8 < c[2] < 3.0)
        m.take(f"mg_{side}", mg)
        glo, ghi = m.bounds(mg)
        nodes.append((f"mg_{side}", "", np.array([(glo[0] + ghi[0]) * 0.5, 1.45, 1.24]), frame(y=Y)))
        tips = sorted((k for k in mg if m.info[k]["ctr"][2] > 2.7 and m.info[k]["size"][2] < 0.3), key=lambda k: -m.info[k]["ctr"][1])
        for n, k in enumerate(tips[:2]):
            i = m.info[k]
            marks.append((f"mg_muzzle_{side}{n + 1}", f"mg_{side}", np.array([i["ctr"][0], i["ctr"][1], i["hi"][2]]), Z))
    # The four hover thrusters under the hull: round pads, everything within 0.7 m of a pad's middle below 0.75 m.
    for name, px, pz in (("FL", 1.93, 1.6), ("FR", -1.93, 1.6), ("RL", 1.86, -3.79), ("RR", -1.86, -3.79)):
        pad = m.pick(lambda lo, hi, c, sz: hi[1] < 0.75 and math.hypot(c[0] - px, c[2] - pz) < 0.7 and sz[0] < 1.3)
        m.take(f"thruster_{name}", pad)
        lo, hi = m.bounds(pad)
        c = (lo + hi) * 0.5
        nodes.append((f"thruster_{name}", "", np.array([c[0], hi[1], c[2]]), frame(y=Y)))
        marks.append((f"jet_{name}", f"thruster_{name}", np.array([c[0], lo[1], c[2]]), -Y))
    # The rear vents at the hull's back corners.
    vents = m.pick(lambda lo, hi, c, sz: c[2] < -4.4 and abs(c[0]) > 2.3 and c[1] < 1.5)
    for side, s in (("L", 1.0), ("R", -1.0)):
        lo, hi = m.bounds([k for k in vents if m.info[k]["ctr"][0] * s > 0])
        marks.append((f"booster_{side}", "", np.array([(lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, lo[2]]), -Z))
    return nodes, marks


def helicopter(m):
    nodes, marks = [], []
    body = max(m.info, key=lambda k: m.info[k]["n"])
    # The rear rotor on the hump (its blades at y 16.8) and the front one, lower (12.4). The hubs are the
    # pieces round the shafts: a rotor is every piece up there within its blades' reach of its hub.
    for name, y0, y1, zc, reach in (("rotor_R", 15.2, 99.0, -9.1, 22.5), ("rotor_F", 11.0, 13.6, 15.9, 16.5)):
        hubs = m.pick(lambda lo, hi, c, sz: y0 < c[1] < y1 and abs(c[2] - zc) < 1.2 and sz[0] < 3.2 and sz[2] < 3.2)
        hlo, hhi = m.bounds(hubs)
        hub = (hlo + hhi) * 0.5
        rotor = m.pick(lambda lo, hi, c, sz: y0 < c[1] < y1 and math.hypot(c[0] - hub[0], c[2] - hub[2]) < reach)
        m.take(name, rotor - {body})
        nodes.append((name, "", np.array([hub[0], hhi[1], hub[2]]), frame(y=Y)))
    # The tail fan: its hub and blades (thin across the tail) inside the duct at the end of the boom.
    fan = m.pick(lambda lo, hi, c, sz: c[2] < -25.3 and abs(c[1] - 8.1) < 1.7 and -1.3 < c[0] < 0.2 and sz.max() < 2.3)
    hub = m.info[max(fan, key=lambda k: m.info[k]["size"][0])]["ctr"]
    m.take("tail_fan", fan)
    nodes.append(("tail_fan", "", hub, frame(y=X)))
    return nodes, marks


BUILD = {"fighter_jet": fighter_jet, "drone": drone, "hover_tank": hover_tank, "helicopter": helicopter}


# ----------------------------------------------------------------------------------------------- output

def write(js, binary, m, nodes, marks, root_name, size, out):
    pos, nrm, uv = np.array(m.pos), np.array(m.nrm), np.array(m.uv)
    world = {"": np.eye(4)}
    for name, parent, pivot, rot in nodes:
        w = np.eye(4)
        w[:3, :3] = rot
        w[:3, 3] = pivot
        world[name] = w
    meshes, gl_nodes = [], [{"name": root_name, "children": []}]
    index = {"": 0}

    def add_node(name, parent, node):
        gl_nodes.append(node)
        index[name] = len(gl_nodes) - 1
        gl_nodes[index[parent]].setdefault("children", []).append(index[name])

    def add_mesh(name):
        sel = [t for t, o in zip(m.tris, m.owner) if o == name]
        t = np.array(sel, dtype=np.int64)
        used = np.unique(t)
        remap = -np.ones(len(pos), dtype=np.int64)
        remap[used] = np.arange(len(used))
        inv = np.linalg.inv(world[name])
        p = pos[used] @ inv[:3, :3].T + inv[:3, 3]
        n = nrm[used] @ inv[:3, :3].T
        a_pos = add_accessor(js, binary, p, "VEC3", with_bounds=True)
        a_nrm = add_accessor(js, binary, n, "VEC3")
        a_uv = add_accessor(js, binary, uv[used], "VEC2")
        arr = np.ascontiguousarray(remap[t].reshape(-1).astype(np.uint32))
        binary.extend(b"\0" * (-len(binary) % 4))
        js["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": arr.nbytes, "target": 34963})
        binary.extend(arr.tobytes())
        js["accessors"].append({"bufferView": len(js["bufferViews"]) - 1, "componentType": 5125,
                                "count": int(arr.size), "type": "SCALAR"})
        meshes.append({"name": name or "Body", "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                       "TEXCOORD_0": a_uv}, "indices": len(js["accessors"]) - 1, "material": m.material}]})
        return len(meshes) - 1

    def local(name, parent):
        return np.linalg.inv(world[parent]) @ world[name]

    add_node("Body", "", {"name": "Body", "mesh": add_mesh("")})
    for name, parent, _, _ in nodes:
        lm = local(name, parent)
        add_node(name, parent, {"name": name, "mesh": add_mesh(name), "translation": [float(v) for v in lm[:3, 3]],
                                "rotation": [float(v) for v in mat_to_quat(lm[:3, :3])]})
    for name, parent, p, d in marks:
        w = np.eye(4)
        w[:3, :3] = marker_rotation(d)
        w[:3, 3] = p
        world[name] = w
        lm = local(name, parent)
        add_node(name, parent, {"name": name, "translation": [float(v) for v in lm[:3, 3]],
                                "rotation": [float(v) for v in mat_to_quat(lm[:3, :3])]})
    js["meshes"] = meshes
    js["nodes"] = gl_nodes
    js["scenes"] = [{"nodes": [0]}]
    js["scene"] = 0
    for k in ("skins", "animations"):
        js.pop(k, None)
    binary = compact(js, binary)
    binary = shrink_images(js, binary, size, 85)
    js.setdefault("asset", {})["generator"] = "tools/gltf/rig_vehicles.py"
    write_glb(out, js, binary)


def marker_rotation(d):
    """A marker's rotation: local +Z along d, local +Y as near the vehicle's up (or its front, for d vertical)."""
    z = unit(d)
    h = Y if abs(np.dot(z, Y)) < 0.9 else Z
    y = unit(h - np.dot(h, z) * z)
    return np.stack([np.cross(y, z), y, z], 1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--vehicle", required=True, choices=sorted(BUILD))
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--size", type=int, default=0)
    p.add_argument("--preview", default="")
    args = p.parse_args()
    js, binary = read_glb(args.input)
    m = Model(js, binary, REF_LENGTH.get(args.vehicle, LENGTH[args.vehicle]))
    nodes, marks = BUILD[args.vehicle](m)
    k = LENGTH[args.vehicle] / REF_LENGTH.get(args.vehicle, LENGTH[args.vehicle])
    m.pos = [p * k for p in m.pos]
    nodes = [(n, par, piv * k, rot) for n, par, piv, rot in nodes]
    marks = [(n, par, p * k, d) for n, par, p, d in marks]
    allp = np.array(m.pos)
    print(f"{args.vehicle}: {LENGTH[args.vehicle]} m long, bounds {np.round(allp.min(0), 2)} .. {np.round(allp.max(0), 2)}")
    for name, parent, pivot, _ in nodes:
        pts = m.part_points(name)
        print(f"  {name:13s} {len(pts) // 3:5d} tris  pivot {np.round(pivot, 2)}  extent {np.round(pts.min(0), 2)} .. {np.round(pts.max(0), 2)}")
    for name, parent, pt, d in marks:
        print(f"  {name:13s} marker at {np.round(pt, 2)} toward {np.round(d, 2)}")
    write(js, binary, m, nodes, marks, NAMES[args.vehicle], args.size or TEX_SIZE.get(args.vehicle, 1024), args.output)
    print(f"wrote {args.output}")
    if args.preview:
        render_preview(args.output, args.preview)


# --------------------------------------------------------------------------------------------- preview

POSES = {"mg": 0.4, "aileron": 0.45, "flap": 0.6, "stabilator": -0.35, "rudder": 0.5, "nozzle": 0.25, "pod": 0.9,
         "gun": 0.35, "turret": 0.8, "rotor": 0.5, "fan": 0.6, "tail": 0.6, "thruster": 0.3, "barrel": 0.0}


def scene_meshes(path, posed):
    """Every mesh node's triangles in the model's frame (posed: each part turned by its POSES angle)."""
    js, binary = read_glb(path)
    from gltf_io import quat_to_mat
    out = []

    def walk(i, parent):
        n = js["nodes"][i]
        lm = np.eye(4)
        lm[:3, :3] = quat_to_mat(n.get("rotation", [0, 0, 0, 1]))
        lm[:3, 3] = n.get("translation", [0, 0, 0])
        name = n.get("name", "")
        if posed and "mesh" in n and name != "Body":
            a = POSES.get(name.split("_")[0], 0.0) * (-1 if name.endswith("_R") and name.startswith("aileron") else 1)
            spin = name.startswith(("rotor", "fan", "tail", "turret", "mg"))
            r = np.eye(4)
            r[:3, :3] = axis_angle(Y if spin else X, a)
            lm = lm @ r
        w = parent @ lm
        if "mesh" in n:
            prim = js["meshes"][n["mesh"]]["primitives"][0]
            v = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
            out.append((name, v @ w[:3, :3].T + w[:3, 3], accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int),
                        accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)))
        for c in n.get("children", []):
            walk(c, w)

    walk(js["scenes"][0]["nodes"][0], np.eye(4))
    return js, binary, out


def render_preview(path, out):
    from PIL import Image, ImageDraw
    from rig_infiltrator import rasterize
    from rig_sniper import load_textured
    js, binary, rest = scene_meshes(path, False)
    _, _, posed = scene_meshes(path, True)
    tex = load_textured(js, binary, js["meshes"][0]["primitives"][0])
    allp = np.concatenate([p for _, p, _, _ in rest])
    lo, hi = allp.min(0), allp.max(0)
    c = (lo + hi) * 0.5
    r = np.linalg.norm(hi - lo)
    W, H = 480, 360
    rng = np.random.default_rng(7)
    views = [("rest", rest, [1.0, 0.6, 1.2], True), ("posed", posed, [1.0, 0.6, 1.2], True),
             ("posed, parts", posed, [-1.1, 0.7, -1.0], False), ("posed, from below", posed, [0.8, -0.6, -1.0], True)]
    sheet = Image.new("RGB", (W * 2, H * 2))
    for k, (label, meshes, d, textured) in enumerate(views):
        img = np.ones((H, W, 3), np.float32) * np.array([0.6, 0.7, 0.8], np.float32)
        zb = np.full((H, W), np.inf, np.float32)
        eye = c + unit(d) * r * 1.25
        for name, v, idx, uv in meshes:
            t = tex
            if not textured or name != "Body":
                t = np.ones((2, 2, 3), np.float32) * (np.array([0.55, 0.55, 0.55]) if name == "Body" else rng.random(3) * 0.7 + 0.3)
            if textured and name != "Body":
                t = tex * 0.5 + t.mean((0, 1)) * 0.5
            rasterize(img, zb, v, idx, uv, t, eye, c)
        pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
        ImageDraw.Draw(pil).text((4, 4), label, fill=(0, 0, 0))
        sheet.paste(pil, ((k % 2) * W, (k // 2) * H))
    sheet.save(out)
    print(f"preview {out}")


if __name__ == "__main__":
    main()
