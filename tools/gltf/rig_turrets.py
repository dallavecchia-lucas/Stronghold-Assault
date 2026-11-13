"""Turret prep: the stronghold's four Meshy guns cut into the moving parts the game animates, on numpy alone
(no Blender), the way tools/gltf/rig_vehicles.py cuts the machines.

  sentry   the Orbital Sentry Gun on the gun decks (assets_src/defenses/orbital_sentry_gun): a ten-barrelled
           gatling in a yoke on a round base, a crew seat on its left, an ammunition drum on its right and a
           radar dome on top.
  cannon   the Arctic Sentinel Cannon on the gun decks, and the mortar on the south roof
           (assets_src/defenses/arctic_sentinel_cannon): a long gun in a mantlet on four outrigger legs, a crew
           seat on its right and a sensor head on top.
  bastion  the Sentinel Bastion on the roofs (assets_src/defenses/sentinel_bastion): a four-barrelled rotary
           cannon that runs itself, a sensor head on top, an ammunition drum on its right and a camera on an
           arm on its left.
  spire    the Sentinel Spire on the roofs (assets_src/defenses/sentinel_spire): a four-cell missile pod
           between two tall arms.

Every model comes out HEIGHT tall in metres, its front +Z, up +Y, its origin on the ground under the middle of
its bounds (where tools/gltf/process_prop.py put it, so a gun stands where it stood). The parts are whole pieces
of the Meshy mesh (it comes apart into a hundred or so). Each part is a node at its pivot whose axes say how it
moves, so the game only has to turn it about one of them (TurretRig and the rigs under game/scripts/turrets):

  spinners turn about local +Y: `turret` (the traverse ring: everything above the base, the seat with it),
      `barrels` (the gatlings' barrel clusters, local +Y along the bore), `dome`, `drum`, `sensor` (the heads);
  hinges turn about local +X, a positive angle raising the muzzle (or the lens): `gun` (the elevating mass, on
      its trunnion), `pod` (the missile pod), `optic`;
  sliders move along local +Z: `barrel` (the cannon's, +Z out of the muzzle: it recoils along -Z);
  markers are empty nodes, local +Z out of the barrel: `muzzle`, `eject` (where the cases leave), `seat` (the
      middle of the seat pan's top, +Z the way the one sitting in it faces), `cell_<k>` (the missile cells),
      `vent` (the pod's back blast), `lens` (the sensors' eye).

The rest (`Body`) is what stays put: the base ring or the legs.

  python3 tools/gltf/rig_turrets.py --turret sentry \\
      --input assets_src/defenses/orbital_sentry_gun/orbital_sentry_gun_meshy.glb \\
      --output game/assets/defenses/orbital_sentry_gun/orbital_sentry_gun.glb [--preview out.png]

--preview draws the parts in colours of their own, at rest and at the ends of their travel.
"""
import argparse
import io
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, axis_angle, quat_to_mat, read_glb  # noqa: E402
from rig_vehicles import Model, X, Y, Z, frame, unit, write  # noqa: E402
from split_raft import gather  # noqa: E402

## How tall each model comes out (m): what the game stands it at (LevelBuilder.DECK_GUN_HEIGHT,
## ROOF_BASTION_HEIGHT, AATurret.HEIGHT). TurretRig scales it for any other height (the mortar's).
HEIGHT = {"sentry": 2.2, "cannon": 2.2, "bastion": 2.0, "spire": 3.0}
## The yaw (about +Y) that turns each Meshy export's front to +Z.
SOURCE_YAW = {"sentry": math.pi / 2, "cannon": math.pi / 2, "bastion": 0.0, "spire": 0.0}
NAMES = {"sentry": "OrbitalSentryGun", "cannon": "ArcticSentinelCannon", "bastion": "SentinelBastion",
         "spire": "SentinelSpire"}


class Turret(Model):
    """A Meshy gun in the game's frame (see the top): Model's pieces, picked by their bounds."""

    def __init__(self, js, binary, yaw, height):
        pos, nrm, uv, tris, self.material = gather(js, binary)
        c, s = math.cos(yaw), math.sin(yaw)
        rot = np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])
        pos, nrm = pos @ rot.T, nrm @ rot.T
        lo, hi = pos.min(0), pos.max(0)
        self.scale = height / (hi[1] - lo[1])
        pos = (pos - np.array([(lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5])) * self.scale
        self._index(pos, nrm, uv, tris)

    def free(self, comps):
        """Those of `comps` no part has taken yet."""
        taken = {c for o, c in zip(self.owner, self.tri_comp) if o != ""}
        return set(comps) - taken

    def grab(self, name, pred):
        """Gives part `name` every piece nobody has yet whose bounds pass pred(lo, hi, ctr, size)."""
        comps = self.free(self.pick(pred))
        self.take(name, comps)
        return comps

    def axis(self, comps):
        """The long axis of pieces `comps` (a barrel, a missile pod): a point on it and its direction, +Z-ward."""
        pts = np.array([self.pos[i] for t, c in zip(self.tris, self.tri_comp) if c in comps for i in t])
        _, _, vt = np.linalg.svd(pts - pts.mean(0), full_matrices=False)
        return pts.mean(0), vt[0] * (1.0 if vt[0][2] > 0 else -1.0)

    def level(self, parts, pivot, elevation):
        """Turns parts `parts` about the left-right axis through `pivot` so what was modelled raised `elevation`
        (rad) lies level, its bore along +Z: every gun comes out level, whatever Meshy posed it at."""
        rot = axis_angle(X, elevation)
        seen = set()
        for tri, owner in zip(self.tris, self.owner):
            if owner not in parts:
                continue
            for i in tri:
                if i not in seen:
                    seen.add(i)
                    self.pos[i] = pivot + rot @ (self.pos[i] - pivot)
                    self.nrm[i] = rot @ self.nrm[i]

    def centre(self, comps):
        lo, hi = self.bounds(comps)
        return (lo + hi) * 0.5


def near(c, x, y, z, r):
    return abs(c[0] - x) < r and abs(c[1] - y) < r and abs(c[2] - z) < r


def seat_dir(face):
    """A seat marker's +Z: the way the one sitting in it faces."""
    return unit(face)


# ------------------------------------------------------------------------------------------- the turrets
# Each returns the nodes (name, parent, pivot, rotation) in build order and the markers (name, parent, position,
# +Z direction). The numbers are read off the model in the game's frame at HEIGHT (+X is the gun's left).

def sentry(m):
    nodes, marks = [], []
    # The traverse ring's middle: the stacked discs of the base (the model's bounds reach out to the seat on one
    # side and the drum on the other, so its origin is not on it).
    ax, az = -0.16, -0.20
    # The bore: the ten barrels' middle; the trunnion on it, between the front of the yoke's cheeks.
    bore_x, bore_y = -0.137, 1.19
    trunnion = np.array([bore_x, bore_y, 0.0])
    barrels = m.grab("barrels", lambda lo, hi, c, sz: c[2] > 0.6 and abs(c[0] - bore_x) < 0.2 and 1.0 < c[1] < 1.4)
    # The elevating mass: the receiver's housing with its sight, the collar the barrels turn in, the two tubes
    # beside it, the saddles and the ram under it.
    m.grab("gun", lambda lo, hi, c, sz: abs(c[0] + 0.12) < 0.25 and c[2] > -0.15 and c[1] > 0.85 and hi[2] < 0.62)
    m.grab("dome", lambda lo, hi, c, sz: c[1] > 1.7 and sz[0] > 0.6)
    drum = m.grab("drum", lambda lo, hi, c, sz: near(c, -1.44, 0.64, -0.30, 0.06))
    # What stays put: the base ring with its feet, braces and discs (low, within the ring).
    base = m.pick(lambda lo, hi, c, sz: hi[1] <= 0.58 and math.hypot(c[0] - ax, c[2] - az) < 0.9)
    m.take("turret", m.free(set(m.info) - base))
    blo, bhi = m.bounds(barrels)
    dlo, dhi = m.bounds(drum)
    dome = m.part_points("dome")
    nodes += [("turret", "", np.array([ax, 0.57, az]), frame(y=Y)),
              ("gun", "turret", trunnion, frame(x=-X)),
              ("barrels", "gun", np.array([bore_x, bore_y, blo[2]]), frame(y=Z, hint=Y)),
              ("dome", "turret", np.array([(dome.min(0)[0] + dome.max(0)[0]) * 0.5, dome.min(0)[1],
                                           (dome.min(0)[2] + dome.max(0)[2]) * 0.5]), frame(y=Y)),
              ("drum", "turret", (dlo + dhi) * 0.5, frame(y=Z, hint=Y))]
    # The barrel at the top of the cluster fires.
    marks += [("muzzle", "gun", np.array([bore_x, bore_y + 0.11, bhi[2]]), Z),
              ("eject", "gun", np.array([bore_x - 0.2, 0.98, 0.3]), unit([-0.75, -0.25, 0.6])),
              ("seat", "turret", np.array([1.188, 0.638, -0.396]), -X)]
    return nodes, marks


def cannon(m):
    nodes, marks = [], []
    # The traverse ring: the middle of the turret's foot on the hull (and of the four legs).
    ax, az = 0.14, -0.26
    barrel = m.grab("barrel", lambda lo, hi, c, sz: c[2] > 1.0 and sz[2] > 1.2)
    point, bore = m.axis(barrel)
    elevation = math.atan2(bore[1], bore[2])
    # The trunnion: where the bore's line runs through the middle of the two bearing housings on the turret's sides.
    housings = m.pick(lambda lo, hi, c, sz: abs(abs(c[0] - ax) - 0.59) < 0.08 and 0.9 < c[1] < 1.15 and sz[1] > 0.6)
    tz = m.centre(housings)[2]
    trunnion = point + bore * ((tz - point[2]) / bore[2])
    # The elevating mass: the mantlet and the sight box on its top, the barrel in it.
    m.grab("gun", lambda lo, hi, c, sz: abs(c[0] - ax) < 0.1 and c[1] > 1.1 and -0.3 < c[2] < 0.3 and hi[1] <= 1.75)
    # The sensor head on the roof: two radomes either side of a cluster of optics, on a round foot (it stays).
    head = m.pick(lambda lo, hi, c, sz: c[1] > 1.8 and c[2] < -0.4)
    foot = m.pick(lambda lo, hi, c, sz: 1.6 < c[1] < 1.75 and c[2] < -0.5 and sz[1] < 0.25)
    m.take("optic", head)
    # What stays put: the hull, its four legs and feet, and the power unit beside the left legs.
    base = m.pick(lambda lo, hi, c, sz: (c[1] < 0.5 and c[0] > -0.8) or c[0] > 1.0)
    m.take("turret", m.free(set(m.info) - base))
    m.level({"gun", "barrel"}, trunnion, elevation)
    b = m.part_points("barrel")
    g = m.part_points("gun")
    flo, fhi = m.bounds(foot)
    o = m.part_points("optic")
    pan = np.array([(flo[0] + fhi[0]) * 0.5, fhi[1], (flo[2] + fhi[2]) * 0.5])
    tilt = np.array([pan[0], (o.min(0)[1] + o.max(0)[1]) * 0.5, pan[2]])
    nodes += [("turret", "", np.array([ax, 0.46, az]), frame(y=Y)),
              ("gun", "turret", trunnion, frame(x=-X)),
              ("barrel", "gun", np.array([trunnion[0], trunnion[1], b.min(0)[2]]), np.eye(3)),
              ("sensor", "turret", pan, frame(y=Y)),
              ("optic", "sensor", tilt, frame(x=-X))]
    marks += [("muzzle", "barrel", np.array([trunnion[0], trunnion[1], b.max(0)[2]]), Z),
              # The spent case drops out under the mantlet's front, forward and to the right.
              ("eject", "gun", np.array([trunnion[0] - 0.1, g.min(0)[1] + 0.12, g.max(0)[2] - 0.2]), unit([-0.55, -0.2, 0.8])),
              ("lens", "optic", np.array([pan[0], tilt[1], o.max(0)[2]]), Z),
              ("seat", "turret", np.array([-1.155, 0.451, -0.473]), X)]
    print(f"  the barrel was modelled raised {math.degrees(elevation):.1f} deg; levelled")
    return nodes, marks


def bastion(m):
    nodes, marks = [], []
    ax, az = -0.065, -0.30
    bore_x, bore_y = -0.07, 1.07
    trunnion = np.array([bore_x, bore_y, -0.2])
    # The four barrels with their jackets, clamp and the plates between their roots, turning in the collar.
    collar = m.pick(lambda lo, hi, c, sz: abs(c[0] - bore_x) < 0.1 and abs(c[1] - 1.08) < 0.1 and -0.05 < lo[2] and hi[2] < 0.25
                    and sz[1] > 0.4)
    barrels = m.free(m.pick(lambda lo, hi, c, sz: abs(c[0] - bore_x) < 0.2 and 0.85 < c[1] < 1.3 and c[2] > 0.1)) - collar
    m.take("barrels", barrels)
    m.take("gun", collar | m.pick(lambda lo, hi, c, sz: abs(c[0] - bore_x) < 0.1 and sz[1] > 0.85 and hi[1] > 1.45 and c[2] > -0.5))
    # The sensor head on the roof: a neck on a round foot (the foot stays), and on it the optics between two radomes.
    neck = m.pick(lambda lo, hi, c, sz: 1.44 < lo[1] < 1.5 and hi[1] < 1.8 and c[2] < -0.8 and sz[0] < 0.25 and sz[2] < 0.4)
    m.take("sensor", neck)
    m.grab("optic", lambda lo, hi, c, sz: lo[1] >= 1.40 and c[2] < -0.6 and abs(c[0] - ax) < 0.7)
    # The camera on its mast, out on the left.
    cam = m.grab("camera", lambda lo, hi, c, sz: c[0] > 1.0 and lo[1] > 1.28)
    drum = m.grab("drum", lambda lo, hi, c, sz: c[0] < -1.1 and c[1] < 0.6 and sz[2] < 0.25)
    base = m.pick(lambda lo, hi, c, sz: hi[1] <= 0.49 and math.hypot(c[0] - ax, c[2] - az) < 0.85)
    m.take("turret", m.free(set(m.info) - base))
    blo, bhi = m.bounds(barrels)
    foot = m.pick(lambda lo, hi, c, sz: 1.3 < lo[1] < 1.36 and c[2] < -0.8 and sz[0] > 0.4)
    flo, fhi = m.bounds(foot)
    o = m.part_points("optic")
    pan = np.array([(flo[0] + fhi[0]) * 0.5, fhi[1], (flo[2] + fhi[2]) * 0.5])
    tilt = np.array([pan[0], 1.72, pan[2]])
    clo, chi = m.bounds(cam)
    dlo, dhi = m.bounds(drum)
    nodes += [("turret", "", np.array([ax, 0.48, az]), frame(y=Y)),
              ("gun", "turret", trunnion, frame(x=-X)),
              ("barrels", "gun", np.array([bore_x, bore_y, blo[2]]), frame(y=Z, hint=Y)),
              ("sensor", "turret", pan, frame(y=Y)),
              ("optic", "sensor", tilt, frame(x=-X)),
              ("camera", "turret", np.array([(clo[0] + chi[0]) * 0.5, clo[1], (clo[2] + chi[2]) * 0.5 + 0.03]), frame(y=Y)),
              ("drum", "turret", (dlo + dhi) * 0.5, frame(y=Z, hint=Y))]
    marks += [("muzzle", "gun", np.array([bore_x, bore_y + 0.11, bhi[2]]), Z),
              ("eject", "gun", np.array([bore_x - 0.2, 0.9, 0.05]), unit([-0.75, -0.25, 0.6])),
              ("lens", "optic", np.array([pan[0], tilt[1] + 0.05, o.max(0)[2]]), Z),
              ("eye", "camera", np.array([(clo[0] + chi[0]) * 0.5, (clo[1] + chi[1]) * 0.5, chi[2]]), Z)]
    return nodes, marks


def spire(m):
    nodes, marks = [], []
    # The pod: the launch box with its four cells, the body between the arms and the vent block behind them.
    pod = m.pick(lambda lo, hi, c, sz: abs(c[0]) < 0.36 and lo[1] > 0.9)
    # The trunnion: the middle of the bearing boxes on the outsides of the arms.
    bearings = m.pick(lambda lo, hi, c, sz: abs(abs(c[0]) - 0.75) < 0.05 and 1.5 < c[1] < 1.62 and sz[0] > 0.45)
    trunnion = m.centre(bearings) * np.array([0.0, 1.0, 1.0])
    cells = sorted(m.pick(lambda lo, hi, c, sz: c[2] > 0.95 and sz[0] < 0.2 and sz[2] < 0.2 and 0.18 < sz[1] < 0.3 and c[1] > 2.1),
                   key=lambda k: (-round(m.info[k]["ctr"][1], 1), -m.info[k]["ctr"][0]))
    # The bore: square to the face the cells open in (its upper row sits back from its lower one).
    rise = (m.info[cells[0]]["ctr"] + m.info[cells[1]]["ctr"] - m.info[cells[2]]["ctr"] - m.info[cells[3]]["ctr"]) * 0.5
    elevation = math.atan2(-rise[2], rise[1])
    vent_block = max(pod, key=lambda k: m.info[k]["n"])
    m.take("pod", pod)
    base = m.pick(lambda lo, hi, c, sz: lo[1] < 0.69)
    m.take("turret", m.free(set(m.info) - base))
    level = axis_angle(X, elevation)
    spots = [trunnion + level @ (m.info[k]["ctr"] - trunnion) for k in cells]
    vent = trunnion + level @ (m.info[vent_block]["ctr"] - trunnion)
    m.level({"pod"}, trunnion, elevation)
    p = m.part_points("pod")
    nodes += [("turret", "", np.array([0.0, 0.69, 0.0]), frame(y=Y)),
              ("pod", "turret", trunnion, frame(x=-X))]
    # The cells, upper left first: each missile leaves along the pod's bore.
    for k, at in enumerate(spots):
        marks.append((f"cell_{k + 1}", "pod", np.array([at[0], at[1], p.max(0)[2] - 0.02]), Z))
    marks.append(("vent", "pod", np.array([0.0, vent[1], p.min(0)[2]]), -Z))
    print(f"  the pod was modelled raised {math.degrees(elevation):.1f} deg; levelled")
    return nodes, marks


BUILD = {"sentry": sentry, "cannon": cannon, "bastion": bastion, "spire": spire}
## How each part moves (see the top), for the preview and for whoever reads the model.
KIND = {"turret": "spin", "barrels": "spin", "dome": "spin", "drum": "spin", "sensor": "spin", "camera": "spin",
        "gun": "hinge", "pod": "hinge", "optic": "hinge", "barrel": "slide"}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--turret", required=True, choices=sorted(BUILD))
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--preview", default="")
    args = p.parse_args()
    js, binary = read_glb(args.input)
    m = Turret(js, binary, SOURCE_YAW[args.turret], HEIGHT[args.turret])
    nodes, marks = BUILD[args.turret](m)
    allp = np.array(m.pos)
    print(f"{args.turret}: {HEIGHT[args.turret]} m tall, bounds {np.round(allp.min(0), 2)} .. {np.round(allp.max(0), 2)}")
    body = m.part_points("")
    print(f"  {'Body':9s} {len(body) // 3:5d} tris  extent {np.round(body.min(0), 2)} .. {np.round(body.max(0), 2)}")
    for name, parent, pivot, _ in nodes:
        pts = m.part_points(name)
        ext = f"extent {np.round(pts.min(0), 2)} .. {np.round(pts.max(0), 2)}" if len(pts) else "(a pivot)"
        print(f"  {name:9s} {len(pts) // 3:5d} tris  in {parent or 'Body':7s} pivot {np.round(pivot, 3)}  {ext}")
    for name, parent, pt, d in marks:
        print(f"  {name:9s} marker in {parent or 'Body':7s} at {np.round(pt, 3)} toward {np.round(d, 2)}")
    write(js, binary, m, nodes, marks, NAMES[args.turret], args.size, args.output, "tools/gltf/rig_turrets.py")
    print(f"wrote {args.output}")
    if args.preview:
        render_preview(args.output, args.preview, args.turret)


# --------------------------------------------------------------------------------------------- preview

## The poses the preview draws each turret in: part -> how far it is moved (rad, or m for a slider).
POSES = {
    "sentry": [{"turret": 0.9, "gun": math.radians(-40.0), "barrels": 0.3, "dome": 0.8, "drum": 0.6},
               {"turret": -0.9, "gun": math.radians(50.0), "barrels": 0.3, "dome": 0.8}],
    "cannon": [{"turret": 0.9, "gun": math.radians(-30.0), "barrel": -0.4, "sensor": -1.2, "optic": -0.4},
               {"turret": -0.9, "gun": math.radians(50.0), "sensor": 1.0, "optic": 0.4}],
    "bastion": [{"turret": 0.9, "gun": math.radians(-30.0), "barrels": 0.4, "sensor": -1.2, "optic": -0.4, "drum": 0.6,
                 "camera": 1.2},
                {"turret": -0.9, "gun": math.radians(50.0), "sensor": 1.0, "optic": 0.4, "camera": -1.2}],
    "spire": [{"turret": 0.9, "pod": math.radians(10.0)}, {"turret": -0.9, "pod": math.radians(55.0)}],
}


def scene_meshes(path, pose):
    """Every mesh node's triangles in the model's frame with the parts moved as `pose` says, and the markers."""
    js, binary = read_glb(path)
    out, marks = [], {}

    def walk(i, parent):
        n = js["nodes"][i]
        lm = np.eye(4)
        lm[:3, :3] = quat_to_mat(n.get("rotation", [0, 0, 0, 1]))
        lm[:3, 3] = n.get("translation", [0, 0, 0])
        name = n.get("name", "")
        kind = KIND.get(name.rstrip("0123456789").rstrip("_"))
        v = pose.get(name, 0.0)
        if kind and v:
            mv = np.eye(4)
            if kind == "slide":
                mv[:3, 3] = Z * v
            else:
                mv[:3, :3] = axis_angle(Y if kind == "spin" else X, v)
            lm = lm @ mv
        w = parent @ lm
        if "mesh" in n:
            prim = js["meshes"][n["mesh"]]["primitives"][0]
            p = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
            out.append((name, p @ w[:3, :3].T + w[:3, 3], accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int),
                        accessor(js, binary, prim["attributes"]["TEXCOORD_0"]).astype(float)))
        elif i != js["scenes"][0]["nodes"][0] and not n.get("children"):
            marks[name] = (w[:3, 3].copy(), w[:3, 2].copy())
        for c in n.get("children", []):
            walk(c, w)

    walk(js["scenes"][0]["nodes"][0], np.eye(4))
    return js, binary, out, marks


def draw(meshes, marks, tex, view, colours, width, height, bounds):
    """An orthographic picture of `meshes` seen from `view` (the way to the eye): textured, or each part in the
    colour `colours` gives it; the markers as little arrows."""
    from PIL import Image, ImageDraw
    f = -unit(view)
    r = unit(np.cross(f, Y))
    u = np.cross(r, f)
    lo, hi = bounds
    c = (lo + hi) * 0.5
    corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]) - c
    k = min(width / (np.abs(corners @ r).max() * 2), height / (np.abs(corners @ u).max() * 2)) * 0.96
    img = np.ones((height, width, 3), np.float32) * np.array([0.78, 0.82, 0.86], np.float32)
    zb = np.full((height, width), np.inf, np.float32)
    light = unit([0.3, 0.8, 0.5])
    for name, pts, idx, uv in meshes:
        rel = pts - c
        sx, sy, sz = width / 2 + (rel @ r) * k, height / 2 - (rel @ u) * k, rel @ f
        tri = pts[idx]
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        shade = 0.45 + 0.55 * np.abs(n @ light)
        flat = colours.get(name) if colours else None
        for t in range(len(idx)):
            i0, i1, i2 = idx[t]
            xs, ys = (sx[i0], sx[i1], sx[i2]), (sy[i0], sy[i1], sy[i2])
            x0, x1 = max(int(min(xs)), 0), min(int(max(xs)) + 1, width - 1)
            y0, y1 = max(int(min(ys)), 0), min(int(max(ys)) + 1, height - 1)
            if x0 > x1 or y0 > y1:
                continue
            den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(den) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            a = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
            b = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
            g = 1 - a - b
            ok = (a >= 0) & (b >= 0) & (g >= 0)
            z = a * sz[i0] + b * sz[i1] + g * sz[i2]
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            ok &= z < sub
            if not ok.any():
                continue
            sub[ok] = z[ok]
            if flat is None:
                tu = (a * uv[i0, 0] + b * uv[i1, 0] + g * uv[i2, 0]) % 1.0
                tv = (a * uv[i0, 1] + b * uv[i1, 1] + g * uv[i2, 1]) % 1.0
                col = tex[(tv * (tex.shape[0] - 1)).astype(int), (tu * (tex.shape[1] - 1)).astype(int)]
                img[y0:y1 + 1, x0:x1 + 1][ok] = col[ok] * shade[t]
            else:
                img[y0:y1 + 1, x0:x1 + 1][ok] = flat * shade[t]
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    dr = ImageDraw.Draw(pil)
    for name, (at, toward) in marks.items():
        a, b = at - c, at + toward * 0.3 - c
        pa = (width / 2 + (a @ r) * k, height / 2 - (a @ u) * k)
        pb = (width / 2 + (b @ r) * k, height / 2 - (b @ u) * k)
        dr.line([pa, pb], fill=(255, 0, 0), width=2)
        dr.ellipse([pa[0] - 3, pa[1] - 3, pa[0] + 3, pa[1] + 3], fill=(255, 220, 0), outline=(0, 0, 0))
        dr.text((pa[0] + 5, pa[1] - 5), name, fill=(120, 0, 0))
    return pil


def render_preview(path, out, turret, width=560, height=440):
    from PIL import Image, ImageDraw
    import colorsys
    js, binary, rest, marks = scene_meshes(path, {})
    mat = js["materials"][js["meshes"][0]["primitives"][0].get("material", 0)]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    tex = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((512, 512)), dtype=np.float32) / 255.0
    names = [n for n, _, _, _ in rest]
    colours = {n: np.array(colorsys.hsv_to_rgb((k * 0.381966) % 1.0, 0.6, 0.95)) for k, n in enumerate(names)}
    colours["Body"] = np.array([0.6, 0.6, 0.6])
    allp = np.concatenate([p for _, p, _, _ in rest])
    reach = np.abs(allp[:, [0, 2]]).max()
    bounds = (np.array([-reach, 0.0, -reach]), np.array([reach, allp[:, 1].max() * 1.12, reach]))
    shots = [("rest", {}, [1.0, 0.7, 1.2], None), ("rest, parts", {}, [1.0, 0.7, 1.2], colours),
             ("rest, parts, from behind", {}, [-1.0, 0.7, -1.2], colours)]
    for k, pose in enumerate(POSES[turret]):
        shots += [(f"pose {k + 1}", pose, [1.0, 0.7, 1.2], None), (f"pose {k + 1}, parts", pose, [1.0, 0.7, 1.2], colours),
                  (f"pose {k + 1}, from its right", pose, [-1.0, 0.1, 0.0], None)]
    sheet = Image.new("RGB", (width * 3, height * (len(shots) // 3)))
    for k, (label, pose, view, cols) in enumerate(shots):
        _, _, meshes, mk = scene_meshes(path, pose)
        pil = draw(meshes, mk if cols else {}, tex, view, cols, width, height, bounds)
        ImageDraw.Draw(pil).text((4, 4), label, fill=(0, 0, 0))
        sheet.paste(pil, ((k % 3) * width, (k // 3) * height))
    sheet.save(out)
    print(f"preview {out}")


if __name__ == "__main__":
    main()
