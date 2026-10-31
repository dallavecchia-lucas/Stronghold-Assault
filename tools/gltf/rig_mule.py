"""Rig and animate the Mule Artillery: six donkeys in harness towing a tracked siege gun. No Blender: numpy on
the glTF itself, like rig_lioness.py.

Input: the processed static model (game/assets/units/cyber_mule_artillery/cyber_mule_artillery.glb: 2.2 m to
the top of the gun, 9.9 m long, origin in the middle of it on the ground, front +Z, one mesh, no rig). The
mesh stays as it is; the rig is built from its pieces (the connected parts of the mesh):

  The donkeys: the six largest pieces, in three pairs (lead, swing and wheel pair, from the front), each
  donkey one piece. Each gets a body bone, a neck and a head (the ears, two small pieces over the head,
  ride the head; the saddle pads on the withers the body), and a two-bone leg for every leg it has. A leg is
  a group of the donkey's vertices below LEG_CUT, joined by edges below it: the fore legs are the two
  frontmost groups, the rest are hind legs (the swing and wheel donkeys were generated with three groups
  behind their fore legs; each one swings as a leg of its own). A leg hangs from a hip (or shoulder) at
  HIP_Y right over where it leaves the belly, its knee halfway down and its hoof at the bottom.
  The harness: the traces along the donkeys' flanks and between the pairs and the bars across each pair,
  blended between the bodies of the donkeys they run between (the last traces into the gun's hitch).
  The gun: the tracked chassis with its hitch (`root`), the turret on it (`turret`: everything standing on
  the chassis deck, from TURRET_FLOOR up), turning about Y through TURRET_PIVOT; the cradle (`cradle`: the
  mantlet, the trunnion hubs, the recuperators and the barrel, every piece round the barrel's axis),
  elevating about X through TRUNNION; and the front of the barrel (`tube`), which slides back into the
  cradle on a shot. `muzzle` (no weights) marks the barrel's tip.

The game turns the turret onto its aim and kicks the tube back when it fires (MuleGun); the clips never key
those two. The clips key the cradle's elevation and the donkeys.

Clips (FPS frames per second; looped clips end on a copy of their first frame, which the game drops):
  Walk   the donkeys pull the gun, authored at WALK_SPEED (UnitTypes anim_ref_speed): each walks a lateral
         sequence (a hind hoof, the fore hoof on its side, then the other side), hooves planted by IK while
         down, the body low in the collar and leaning into it, bobbing twice a stride, the head nodding
         with the fore legs. Each donkey keeps a step of its own (DONKEY_PHASE).
  Idle   standing hitched, the gun packed: breathing, weight shifts, heads looking about.
  Setup  (not looped, SETUP_TIME long) the gun set up: the team halts and the heads come up, the barrel
         rises out of its travel position to ELEV (the donkeys watching it go up), overshoots a little and
         settles, and the donkeys drop their heads to graze. The game plays it backwards to pack the gun up.
  Armed  the gun set up, the barrel up at ELEV: the donkeys graze (cropping, chewing, breathing). It starts
         where Setup ends.

  python3 tools/gltf/rig_mule.py \\
      --input game/assets/units/cyber_mule_artillery/cyber_mule_artillery.glb \\
      --output game/assets/units/cyber_mule_artillery/cyber_mule_artillery_rigged.glb [--preview DIR]

--preview renders the rest pose and frames of every clip into DIR as PNGs (rig_infiltrator's plain numpy
rasterizer): the Walk travelling at its speed over a grid on the ground (planted hooves stay put on it), the
Setup and Armed side on and from an RTS camera's height, and the set-up gun traversed round (MuleGun).
"""
import argparse
import io
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import (accessor, add_accessor, axis_angle, compact, mat_to_quat, quat_to_mat, read_glb,  # noqa: E402
                     rotation, set_trs, translation, trs, write_glb)
from rig_infiltrator import Pose, Rig, aim_frame, place_chain, project, rasterize, smooth, two_bone, unit  # noqa: E402

FPS = 30
# Model axes (glTF): +X the team's left, +Y up, +Z its front.
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])
RAD = math.pi / 180

# ---------------------------------------------------------------- the gun (model frame, meters)
# Pieces centred behind GUN_Z belong to the gun (the chassis, the turret), unless they ride the cradle.
GUN_Z = -1.25
# The turret: gun pieces wholly above the chassis deck, turning about Y through TURRET_PIVOT (the middle of
# its hull, so the barrel's breech end, which drops below the hull as the barrel goes up, stays over the deck
# whichever way the turret faces).
TURRET_FLOOR = 0.88
TURRET_PIVOT = (0.0, 0.88, -3.6)
# The cradle: pieces centred within BARREL_R of the barrel's axis (x, y) and above TURRET_FLOOR, and the two
# trunnion hubs on the mantlet's sides, elevating about X through TRUNNION (the hubs' middle). The tube: the
# barrel's pieces from TUBE_Z forward, which slide back into the cradle on a shot.
BARREL_AXIS = (0.0, 1.655)
BARREL_R = 0.42
TRUNNION = (0.0, 1.655, -3.15)
HUB_X = (0.3, 0.65)
TUBE_Z = 0.68
MUZZLE = (0.0, 1.655, 4.95)
# The barrel's elevation set up (radians) and how far past it the barrel swings before it settles.
ELEV = 40.0 * RAD
OVERSHOOT = 1.6 * RAD

# ---------------------------------------------------------------- the donkeys
ROWS = ("lead", "swing", "wheel")
# Legs: the donkey's vertices below LEG_CUT, joined by edges below it, make a leg (groups of fewer than
# LEG_MIN vertices are bits of the belly); fore legs are within FORE_SPAN of the frontmost group. A leg hangs
# from HIP_Y over where it leaves the belly; its upper bone pulls on the belly's skin up to LEG_TOP.
LEG_CUT = 0.28
LEG_MIN = 8
FORE_SPAN = 0.12
HIP_Y = 0.5
KNEE_BAND = (0.09, 0.19)
LEG_TOP = 0.42
# The neck runs from the withers (WITHERS_BACK behind the nose, at WITHERS_Y) to the poll (just under the
# top of the head, measured), the head from the poll to the nose (NOSE_Y). Below THROAT_Y the head and neck
# give way to the chest.
WITHERS_BACK = 0.70
WITHERS_Y = 0.62
POLL_DROP = 0.09
NOSE_Y = 0.58
THROAT_Y = (0.40, 0.48)
# The body bone: in the middle of the barrel, at BODY_Y.
BODY_Y = 0.52
# Small pieces (ears, saddle pads) ride what they sit on; bigger ones (the traces, the bars) are harness.
SMALL = 0.35

# ---------------------------------------------------------------- clips
WALK_SPEED = 1.0  # m/s (UnitTypes anim_ref_speed)
WALK_FRAMES = 18  # one stride
WALK_PERIOD = WALK_FRAMES / FPS
DUTY = 0.66  # share of the stride each hoof is down
LIFT = 0.06  # hoof clearance mid-swing (m)
WALK_LOW = 0.02  # the bodies ride at least this much lower walking than standing, low in the collar (m)
WALK_LEAN = 3.0 * RAD  # leaning into the collar
STRAIGHT = 0.985  # how straight a leg may get (share of its length)
STAND_BEND = 0.975  # standing, the legs a touch short of straight
# Lateral sequence: where in the stride each leg is in the middle of its swing (fore legs by side; hind legs
# from the rearmost forward, alternating).
FORE_MID = {"L": 0.25, "R": 0.75}
HIND_MID = (0.0, 0.5, 0.08)
# Each donkey's step, a share of the stride, so the team doesn't walk in lockstep.
DONKEY_PHASE = {"lead_L": 0.0, "lead_R": 0.47, "swing_L": 0.29, "swing_R": 0.78, "wheel_L": 0.61, "wheel_R": 0.13}
IDLE_FRAMES = 120
SETUP_TIME = 7.0  # UnitTypes setup_time: the clip is authored at it
SETUP_FRAMES = int(SETUP_TIME * FPS)
ARMED_FRAMES = 120
# Grazing, the gun set up: the neck and the head pitched down (radians).
GRAZE_NECK = -38.0 * RAD
GRAZE_HEAD = -18.0 * RAD


def v3(p):
    return np.asarray(p, dtype=float)


def rot_x(a):
    return axis_angle(X, a)


def rot_y(a):
    return axis_angle(Y, a)


def rot_z(a):
    return axis_angle(Z, a)


def rest_frame(head, tail):
    """A bone's rest matrix: at its head, Y along it, Z toward the team's left (or its front for a bone
    running across it)."""
    y = unit(v3(tail) - v3(head))
    pole = X if abs(np.dot(y, X)) < 0.9 else Z
    return translation(v3(head)) @ rotation(aim_frame(y, pole))


def ease(u):
    """Smootherstep on 0-1."""
    u = min(max(u, 0.0), 1.0)
    return u * u * u * (u * (u * 6 - 15) + 10)


def span(u, a, b):
    """0 before a, 1 after b, eased in between."""
    return ease((u - a) / (b - a))


def cyc(t, period, n=1, phase=0.0):
    """A sine with a whole number of cycles over the loop (seamless)."""
    return math.sin(2 * math.pi * (n * t / period + phase))


# ---------------------------------------------------------------- mesh pieces

def pieces(pos, tris):
    """Connected pieces, counting vertices at the same spot as joined (the export splits the mesh along its
    UV seams). Returns the welded spot of each vertex and the pieces (vertex index arrays)."""
    key = np.round(pos * 1e5).astype(np.int64)
    _, spot = np.unique(key, axis=0, return_inverse=True)
    spot = spot.ravel()
    root = np.arange(spot.max() + 1)

    def find(a):
        while root[a] != a:
            root[a] = root[root[a]]
            a = root[a]
        return a

    for t in tris:
        a = find(spot[t[0]])
        for b in (spot[t[1]], spot[t[2]]):
            b = find(b)
            if a != b:
                root[b] = a
    groups = {}
    for i in range(len(pos)):
        groups.setdefault(find(spot[i]), []).append(i)
    return spot, sorted((np.array(g) for g in groups.values()), key=len, reverse=True)


class Leg:
    def __init__(self, verts, hoof, top, knee, fore):
        self.verts = verts
        self.fore = fore
        self.hoof = hoof  # the bottom of the hoof (rest)
        self.hip = v3((top[0], HIP_Y, top[2]))
        self.knee = knee
        self.l1 = float(np.linalg.norm(knee - self.hip))
        self.l2 = float(np.linalg.norm(hoof - knee))
        self.ground = float(hoof[1])
        # Knees bend: the fore legs' forward, the hind legs' back (the IK's pole).
        self.bend = Z if fore else -Z
        self.side = ""
        self.mid = 0.0  # where in the stride the hoof is mid-swing
        self.name = ""


class Donkey:
    """One donkey: its vertices, legs and the joints of its neck and head, measured on the mesh."""

    def __init__(self, name, verts, pos, tris, spot):
        self.name = name
        self.verts = verts
        p = pos[verts]
        lo, hi = p.min(axis=0), p.max(axis=0)
        self.lo, self.hi = lo, hi
        self.cx = float((lo[0] + hi[0]) / 2)
        self.nose_z = float(hi[2])
        self.tail_z = float(lo[2])
        self.legs = self._legs(pos, tris, spot)
        head = p[p[:, 2] > self.nose_z - 0.55]
        top = head[np.argmax(head[:, 1])]
        self.poll = v3((self.cx, top[1] - POLL_DROP, top[2]))
        self.withers = v3((self.cx, WITHERS_Y, self.nose_z - WITHERS_BACK))
        self.nose = v3((self.cx, NOSE_Y, self.nose_z))
        self.body = v3((self.cx, BODY_Y, (self.tail_z + self.withers[2]) / 2))

    def _legs(self, pos, tris, spot):
        """Groups of the donkey's vertices below LEG_CUT joined by edges below it, frontmost first."""
        vset = set(self.verts.tolist())
        low = {i for i in vset if pos[i, 1] < LEG_CUT}
        root = {}

        def find(a):
            while root.setdefault(a, a) != a:
                root[a] = root[root[a]]
                a = root[a]
            return a

        for t in tris:
            if t[0] not in vset:
                continue
            for k in range(3):
                a, b = t[k], t[(k + 1) % 3]
                if a in low:
                    find(spot[a])
                if a in low and b in low:
                    root[find(spot[a])] = find(spot[b])
        groups = {}
        for i in low:
            groups.setdefault(find(spot[i]), []).append(i)
        groups = [np.array(g) for g in groups.values() if len(g) >= LEG_MIN]
        groups.sort(key=lambda g: -pos[g, 2].mean())
        front = pos[groups[0], 2].mean()
        legs = []
        for g in groups:
            q = pos[g]
            hoof = q[q[:, 1] < q[:, 1].min() + 0.04].mean(axis=0)
            top = q[q[:, 1] > q[:, 1].max() - 0.05].mean(axis=0)
            band = q[(q[:, 1] > KNEE_BAND[0]) & (q[:, 1] < KNEE_BAND[1])]
            mid = (KNEE_BAND[0] + KNEE_BAND[1]) / 2
            if len(band):
                knee = band.mean(axis=0)
            else:
                knee = hoof + (top - hoof) * (mid - hoof[1]) / max(top[1] - hoof[1], 1e-3)
            knee = v3((knee[0], mid, knee[2]))
            legs.append(Leg(g, hoof, top, knee, front - q[:, 2].mean() < FORE_SPAN))
        fore = sorted([leg for leg in legs if leg.fore], key=lambda leg: -leg.hip[0])
        for leg, side in zip(fore, "LR"):
            leg.side = side
            leg.mid = FORE_MID[side]
        hind = sorted([leg for leg in legs if not leg.fore], key=lambda leg: leg.hip[2])
        for k, leg in enumerate(hind):
            leg.mid = HIND_MID[k % len(HIND_MID)]
        for k, leg in enumerate(legs):
            leg.name = "%s_leg%d" % (self.name, k + 1)
        return legs

    def bones(self):
        """(name, parent, rest matrix) for the donkey's bones, parents first."""
        n = self.name
        out = [(n + "_body", "root", translation(self.body)),
               (n + "_neck", n + "_body", rest_frame(self.withers, self.poll)),
               (n + "_head", n + "_neck", rest_frame(self.poll, self.nose))]
        for leg in self.legs:
            out.append((leg.name + "_up", n + "_body", rest_frame(leg.hip, leg.knee)))
            out.append((leg.name + "_lo", leg.name + "_up", rest_frame(leg.knee, leg.hoof)))
        return out

    # -------------------------------------------------- skin weights

    def head_neck(self, q):
        """How much a point on the donkey goes with its head and with its neck (the rest is body)."""
        throat = smooth(THROAT_Y[0], THROAT_Y[1], q[1])
        head = smooth(self.poll[2] - 0.1, self.poll[2] - 0.02, q[2]) * throat
        neck = smooth(self.withers[2] - 0.07, self.withers[2] + 0.07, q[2]) * throat * (1.0 - head)
        return head, neck

    def upper(self, q):
        """Weights for a point on the donkey away from its legs: the head, the neck or the body (blended)."""
        n = self.name
        head, neck = self.head_neck(q)
        w = {n + "_body": 1.0 - head - neck}
        if head > 0.0:
            w[n + "_head"] = head
        if neck > 0.0:
            w[n + "_neck"] = neck
        return w

    def weights(self, i, q):
        n = self.name
        for leg in self.legs:
            if i in leg.member:
                # Down the leg: the upper bone above the knee, the lower below it; its top blends into the body.
                lo = smooth(leg.knee[1] + 0.03, leg.knee[1] - 0.03, q[1])
                w = {leg.name + "_lo": lo, leg.name + "_up": 1.0 - lo}
                pull = smooth(LEG_TOP, LEG_CUT - 0.02, q[1])
                if pull < 1.0:
                    w = mix({n + "_body": 1.0}, w, pull)
                return w
        w = self.upper(q)
        # The belly over a leg: the leg's pull fades out from the cut up to LEG_TOP.
        if q[1] < LEG_TOP:
            best = min(self.legs, key=lambda leg: np.hypot(q[0] - leg.hip[0], q[2] - leg.hip[2]))
            near = smooth(0.13, 0.06, np.hypot(q[0] - best.hip[0], q[2] - best.hip[2]))
            pull = near * smooth(LEG_TOP, LEG_CUT - 0.02, q[1])
            if pull > 0.0:
                w = mix(w, {best.name + "_up": 1.0}, pull)
        return w

    def ride(self, c):
        """The bone a small piece centred at c rides (an ear rides the head, a saddle pad the body)."""
        head, neck = self.head_neck(c)
        if head >= 0.5:
            return {self.name + "_head": 1.0}
        if neck >= 0.5:
            return {self.name + "_neck": 1.0}
        return {self.name + "_body": 1.0}

    def flat_distance(self, q):
        """How far q lies from the donkey's footprint (0 over it)."""
        dx = max(self.lo[0] - q[0], 0.0, q[0] - self.hi[0])
        dz = max(self.tail_z - q[2], 0.0, q[2] - self.nose_z)
        return math.hypot(dx, dz)


def mix(a, b, t):
    """Blends two weight dicts: t = 0 gives a, 1 gives b."""
    out = {}
    for k, v in a.items():
        out[k] = out.get(k, 0.0) + v * (1 - t)
    for k, v in b.items():
        out[k] = out.get(k, 0.0) + v * t
    return {k: v for k, v in out.items() if v > 1e-6}


class Team:
    """The model's pieces sorted out: the six donkeys, the harness, and the gun's parts."""

    def __init__(self, pos, tris):
        self.pos = pos
        spot, parts = pieces(pos, tris)
        self.parts = parts
        big = [p for p in parts[:12] if pos[p, 2].mean() > GUN_Z and pos[p, 1].max() < 1.1][:6]
        assert len(big) == 6, "expected six donkeys"
        big.sort(key=lambda p: -pos[p, 2].mean())
        self.donkeys = []
        for row in range(3):
            pair = sorted(big[2 * row:2 * row + 2], key=lambda p: -pos[p, 0].mean())
            for side, p in zip("LR", pair):
                self.donkeys.append(Donkey("%s_%s" % (ROWS[row], side), p, pos, tris, spot))
        for d in self.donkeys:
            for leg in d.legs:
                leg.member = set(leg.verts.tolist())
        donkey_verts = set(np.concatenate([d.verts for d in self.donkeys]).tolist())
        self.kind = {}
        self.rest = [p for p in parts if p[0] not in donkey_verts]
        for p in self.rest:
            self.kind[id(p)] = self.classify(p)

    def classify(self, p):
        q = self.pos[p]
        lo, hi = q.min(axis=0), q.max(axis=0)
        c = (lo + hi) / 2
        axis_d = math.hypot(c[0] - BARREL_AXIS[0], c[1] - BARREL_AXIS[1])
        hub = abs(c[1] - TRUNNION[1]) < 0.05 and abs(c[2] - TRUNNION[2]) < 0.05 and HUB_X[0] < abs(c[0]) < HUB_X[1]
        if lo[1] > TURRET_FLOOR and (axis_d < BARREL_R or hub) and (c[2] > TURRET_PIVOT[2] or hub):
            return "tube" if lo[2] > TUBE_Z else "cradle"
        if c[2] < GUN_Z:
            return "turret" if lo[1] > TURRET_FLOOR else "root"
        if float((hi - lo).max()) < SMALL:
            return "small"
        return "harness"

    def weights(self):
        pos = self.pos
        weights = [None] * len(pos)
        for d in self.donkeys:
            for i in d.verts:
                weights[i] = d.weights(i, pos[i])
        counts = {}
        for p in self.rest:
            kind = self.kind[id(p)]
            counts[kind] = counts.get(kind, 0) + len(p)
            if kind in ("root", "turret", "cradle", "tube"):
                for i in p:
                    weights[i] = {kind: 1.0}
            elif kind == "small":
                c = (pos[p].min(axis=0) + pos[p].max(axis=0)) / 2
                d = min(self.donkeys, key=lambda d: d.flat_distance(c))
                w = d.ride(c)
                for i in p:
                    weights[i] = w
            else:
                for i in p:
                    weights[i] = self.harness(pos[i])
        print("pieces: " + ", ".join(f"{k} {n}" for k, n in sorted(counts.items())) + " vertices")
        return weights

    def harness(self, q):
        """A point on the harness: over a donkey it goes with the donkey's skin there (the reins with the head);
        between donkeys it is blended between the two whose footprints are nearest it (the gun's chassis takes
        the place of one behind the wheel pair), by how near each is."""
        near = sorted(((d.flat_distance(q), k) for k, d in enumerate(self.donkeys)))[:2]
        near = [(dist, self.donkeys[k].upper(q)) for dist, k in near]
        gun = max(q[2] - (GUN_Z - 0.3), 0.0) if q[2] < self.donkeys[-1].tail_z else 9.0
        near = sorted(near + [(gun, {"root": 1.0})], key=lambda e: e[0])[:2]
        (d0, w0), (d1, w1) = near
        return mix(w0, w1, d0 / max(d0 + d1, 1e-6))


def pack_weights(weights, joint_index):
    """The four strongest influences per vertex (glTF carries four), normalized."""
    joints = np.zeros((len(weights), 4), np.uint8)
    values = np.zeros((len(weights), 4), np.float32)
    for i, w in enumerate(weights):
        top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        total = sum(x for _, x in top)
        for k, (name, x) in enumerate(top):
            joints[i, k] = joint_index[name]
            values[i, k] = x / total
    return joints, values


# ---------------------------------------------------------------- building the new glTF

def bone_list(team):
    """(name, parent, rest matrix in the model frame) for every bone, parents first. The gun's bones keep the
    model's axes (the game turns the turret about its Y and slides the tube along its Z)."""
    out = [("root", None, np.eye(4)),
           ("turret", "root", translation(v3(TURRET_PIVOT))),
           ("cradle", "turret", translation(v3(TRUNNION))),
           ("tube", "cradle", translation(v3((TRUNNION[0], TRUNNION[1], TUBE_Z)))),
           ("muzzle", "tube", translation(v3(MUZZLE)))]
    for d in team.donkeys:
        out += d.bones()
    return out


def rebuild(js, binary):
    """Skins the static mesh to the new skeleton: the mesh node and the bones under one Armature node, the
    skin's joints and inverse bind matrices, the vertices' joints and weights. Returns the team and the bone
    names."""
    mesh_node = next(n for n in js["nodes"] if "mesh" in n)
    assert np.allclose(trs(mesh_node), np.eye(4)), "the mesh node should sit at the origin"
    prim = js["meshes"][mesh_node["mesh"]]["primitives"][0]
    pos = accessor(js, binary, prim["attributes"]["POSITION"]).astype(float)
    tris = accessor(js, binary, prim["indices"]).reshape(-1, 3).astype(int)
    team = Team(pos, tris)
    print(f"mesh: {len(pos)} vertices, {len(tris)} triangles, {len(team.parts)} pieces")
    for d in team.donkeys:
        print(f"donkey {d.name}: {len(d.verts)} vertices, nose z {d.nose_z:+.2f}, legs " + ", ".join(
            f"{'F' if leg.fore else 'H'}{leg.side}@{leg.hip[2] - d.nose_z:+.2f} {leg.l1 + leg.l2:.2f}m" for leg in d.legs))
    weights = team.weights()

    bones = bone_list(team)
    world = {}
    nodes = [{"name": "Armature", "children": [1, 2]},
             {"name": mesh_node.get("name", "mule_artillery"), "mesh": mesh_node["mesh"], "skin": 0}]
    index = {}
    for name, parent, m in bones:
        world[name] = m
        local = m if parent is None else np.linalg.inv(world[parent]) @ m
        node = {"name": name}
        set_trs(node, local)
        index[name] = len(nodes)
        nodes.append(node)
        if parent is not None:
            nodes[index[parent]].setdefault("children", []).append(index[name])
    js["nodes"] = nodes
    js["scenes"] = [{"name": "Scene", "nodes": [0]}]
    js["scene"] = 0
    names = [b[0] for b in bones]
    joint_index = {name: k for k, name in enumerate(names)}
    ibm = np.array([np.linalg.inv(world[name]).T.reshape(16) for name in names])
    js["skins"] = [{"name": "Armature", "joints": [index[n] for n in names], "skeleton": index["root"],
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
    return team, names


# ---------------------------------------------------------------- posing

class Baker:
    def __init__(self, rig, team, names):
        self.rig = rig
        self.team = team
        self.names = names
        self.pose = Pose(rig)
        self.clips = {}
        # How far each donkey's body stands below where it was modelled so that none of its legs is more than
        # STAND_BEND of straight with the hooves under the hips (no lower than modelled: longer legs bend more).
        self.stand = {}
        for d in team.donkeys:
            drops = [(leg.l1 + leg.l2) * STAND_BEND - (HIP_Y - leg.ground) for leg in d.legs]
            self.stand[d.name] = min(min(drops), 0.0)

    def key(self):
        return {n: self.pose.local(n) for n in self.names}

    def body(self, d, rise=0.0, sway=0.0, surge=0.0, pitch=0.0, roll=0.0, yaw=0.0):
        """Poses a donkey's body: up (rise), to its left (sway), ahead (surge), nose down (pitch), rolling onto
        its right side (roll) and turning left (yaw), from where it stands."""
        n = d.name + "_body"
        p = self.pose
        p.turn(n, Y, yaw)
        p.turn(n, Z, roll)
        p.turn(n, X, pitch)
        p.move(n, Y * (self.stand[d.name] + rise) + X * sway + Z * surge)

    def neck(self, d, pitch=0.0, yaw=0.0, head_pitch=0.0, head_yaw=0.0):
        """The neck pitched up (+) or down and turned left (+), the head likewise on it."""
        p = self.pose
        p.turn(d.name + "_neck", Y, yaw)
        p.turn(d.name + "_neck", X, -pitch)
        p.turn(d.name + "_head", Y, head_yaw)
        p.turn(d.name + "_head", X, -head_pitch)

    def leg(self, d, leg, hoof):
        """Points the leg at a hoof position (model frame) by 2-bone IK from where its hip is now."""
        p = self.pose
        hip = p.head(leg.name + "_up")
        to = hoof - hip
        reach = (leg.l1 + leg.l2) * STRAIGHT
        if np.linalg.norm(to) > reach:
            hoof = hip + unit(to) * reach
        knee, end = two_bone(hip, leg.l1, leg.l2, hoof, leg.bend)
        place_chain(p, leg.name + "_up", leg.name + "_lo", hip, knee, end, X)

    def stand_legs(self, d, spread=0.0):
        """Every hoof on the ground under its hip (where the hip stands, not where the body sways to)."""
        for leg in d.legs:
            at = leg.hip + Y * self.stand[d.name]
            self.leg(d, leg, v3((at[0], leg.ground, at[2] + spread * (1 if leg.fore else -1))))

    # -------------------------------------------------- Walk

    def walk(self):
        """One stride of the lateral-sequence walk for every donkey, travelling at WALK_SPEED. Each body rides
        as high as its planted legs allow (they are nearly straight, so it dips as they reach out ahead and
        behind and rises over them: the bob), smoothed to a few harmonics of the stride."""
        rise = {d.name: self._walk_heights(d) for d in self.team.donkeys}
        frames = []
        for f in range(WALK_FRAMES + 1):
            self.pose.reset()
            for d in self.team.donkeys:
                s = self._stride(d, f)
                self._walk_body(d, s, rise[d.name][f % WALK_FRAMES])
                nod = 4.0 * RAD * math.cos(4 * math.pi * (s - FORE_MID["L"] + 0.08))
                self.neck(d, pitch=-7.0 * RAD + nod, head_pitch=-0.6 * nod)
                for leg in d.legs:
                    self.leg(d, leg, self._hoof(leg, s, d))
            frames.append(self.key())
        self.clips["Walk"] = frames

    @staticmethod
    def _stride(d, f):
        """The donkey's share of the way through its stride at frame f."""
        return (f / FPS / WALK_PERIOD + DONKEY_PHASE[d.name]) % 1.0

    def _walk_body(self, d, s, rise):
        """The body walking: low in the collar and leaning into it, swaying and rolling once a stride."""
        self.body(d, rise=rise, sway=0.006 * math.sin(2 * math.pi * s), pitch=WALK_LEAN,
                  roll=1.2 * RAD * math.sin(2 * math.pi * (s - 0.1)))

    def _walk_heights(self, d):
        """The body's rise (from standing) at each frame of the stride: as high as every planted leg reaches
        (STRAIGHT of its length to its hoof), no higher than WALK_LOW under standing; kept to the stride's first
        harmonics, then lowered as far as it takes for the smoothed curve to stay within every frame's reach."""
        raw = []
        for f in range(WALK_FRAMES):
            s = self._stride(d, f)
            self.pose.reset()
            self._walk_body(d, s, 0.0)
            best = -WALK_LOW
            for leg in d.legs:
                hoof = self._hoof(leg, s, d)
                if hoof[1] > leg.ground + 1e-6:
                    continue  # swinging
                hip = self.pose.head(leg.name + "_up")
                flat = math.hypot(hip[0] - hoof[0], hip[2] - hoof[2])
                reach = (leg.l1 + leg.l2) * STRAIGHT
                best = min(best, leg.ground + math.sqrt(max(reach * reach - flat * flat, 0.0)) - hip[1])
            raw.append(best)
        f = np.fft.rfft(np.array(raw))
        f[4:] = 0
        smooth_rise = np.fft.irfft(f, len(raw))
        smooth_rise -= max(float((smooth_rise - np.array(raw)).max()), 0.0)
        return list(smooth_rise)

    def _hoof(self, leg, s, d):
        """Where a hoof is at stride share s: planted and sweeping back under the hip at walking pace for DUTY of
        the stride (the ground moving under the team), then lifted and swung forward."""
        stride = WALK_SPEED * WALK_PERIOD
        sweep = stride * DUTY
        u = (s - leg.mid + (1.0 + DUTY) / 2) % 1.0  # 0 at touch-down, DUTY at lift-off, mid-swing at s = leg.mid
        hip = leg.hip + Y * self.stand[d.name]
        if u < DUTY:
            z = hip[2] + sweep * (0.5 - u / DUTY)
            y = leg.ground
        else:
            w = (u - DUTY) / (1.0 - DUTY)  # through the swing
            z = hip[2] + sweep * (-0.5 + ease(w))
            y = leg.ground + LIFT * math.sin(math.pi * w) ** 1.5
        return v3((hip[0], y, z))

    # -------------------------------------------------- standing clips

    def idle(self):
        """Standing hitched: breathing, weight shifts and the heads looking about, each donkey in its own time."""
        frames = []
        T = IDLE_FRAMES / FPS
        for f in range(IDLE_FRAMES + 1):
            t = f / FPS
            self.pose.reset()
            for k, d in enumerate(self.team.donkeys):
                ph = DONKEY_PHASE[d.name]
                self.body(d, rise=0.004 * cyc(t, T, 4, ph), sway=0.008 * cyc(t, T, 1, ph),
                          roll=-0.6 * RAD * cyc(t, T, 1, ph))
                self.neck(d, pitch=5.0 * RAD * cyc(t, T, 2, ph + 0.2) - 2.0 * RAD * (1 - math.cos(2 * math.pi * t / T)),
                          yaw=14.0 * RAD * cyc(t, T, 1, ph * 2) * (1 if k % 2 else -1),
                          head_pitch=-3.0 * RAD * cyc(t, T, 3, ph), head_yaw=6.0 * RAD * cyc(t, T, 2, ph + 0.3))
                self.stand_legs(d)
            frames.append(self.key())
        self.clips["Idle"] = frames

    def setup(self):
        """The gun set up, over SETUP_TIME: the team halts, heads up; the barrel rises to ELEV, overshoots a
        little and settles while the donkeys watch it go up; they drop their heads to graze."""
        frames = []
        for f in range(SETUP_FRAMES + 1):
            t = f / FPS
            u = t / SETUP_TIME
            self.pose.reset()
            for k, d in enumerate(self.team.donkeys):
                ph = DONKEY_PHASE[d.name]
                lag = 0.04 * k / 5  # the lead pair first, the wheel pair last
                up = span(u, 0.02 + lag, 0.14 + lag) * (1 - span(u, 0.72 + lag * 0.5, 0.94))
                watch = span(u, 0.16 + lag, 0.34 + lag) * (1 - span(u, 0.70 + lag * 0.5, 0.92))
                graze = span(u, 0.74 + lag * 0.5, 0.97)
                side = 1 if d.name.endswith("_L") else -1
                # Breathing: five breaths, none at either end (it starts from Idle's pose and ends on Armed's).
                self.body(d, rise=0.004 * math.sin(2 * math.pi * 5 * t / SETUP_TIME) * (1 if k % 2 else -1),
                          surge=-0.012 * up, pitch=-1.5 * RAD * up)
                # Heads up at the halt; watching, the neck turned out and back toward the gun and up at the rising
                # barrel; then down to graze.
                self.neck(d, pitch=12.0 * RAD * up + 10.0 * RAD * watch + GRAZE_NECK * graze,
                          yaw=24.0 * RAD * side * watch, head_pitch=14.0 * RAD * watch + GRAZE_HEAD * graze,
                          head_yaw=16.0 * RAD * side * watch)
                self.stand_legs(d)
            self.pose.turn("cradle", X, -self._elevation(u))
            frames.append(self.key())
        self.clips["Setup"] = frames

    @staticmethod
    def _elevation(u):
        """The barrel's elevation through the setup (0-1): level until the team has halted, then up to ELEV
        and OVERSHOOT past it, settling back."""
        rise = ELEV * span(u, 0.08, 0.78)
        bump = OVERSHOOT * math.sin(math.pi * min(max((u - 0.72) / 0.18, 0.0), 1.0))
        return rise + bump

    def armed(self):
        """The gun set up: the donkeys grazing, cropping the grass and chewing, breathing; the barrel at ELEV.
        Its first frame is Setup's last."""
        frames = []
        T = ARMED_FRAMES / FPS
        for f in range(ARMED_FRAMES + 1):
            t = f / FPS
            self.pose.reset()
            for k, d in enumerate(self.team.donkeys):
                # Two to four bites a loop each (so they soon crop out of step), none at the loop's ends.
                crop = 5.0 * RAD * math.sin(math.pi * (2 + k % 3) * t / T) ** 2
                self.body(d, rise=0.004 * cyc(t, T, 4, 0.0) * (1 if k % 2 else -1), sway=0.005 * cyc(t, T, 1, 0.0))
                self.neck(d, pitch=GRAZE_NECK - 0.4 * crop, yaw=5.0 * RAD * cyc(t, T, 1, 0.0) * (1 if k % 3 else -1),
                          head_pitch=GRAZE_HEAD - crop, head_yaw=3.0 * RAD * cyc(t, T, 2, 0.0))
                self.stand_legs(d)
            # The heavy barrel settling in its cradle, a hair (a track that never changes could be dropped on import,
            # and the barrel would come down with it).
            self.pose.turn("cradle", X, -ELEV - 0.15 * RAD * cyc(t, T, 1, 0.0))
            frames.append(self.key())
        self.clips["Armed"] = frames


# ---------------------------------------------------------------- clips

def write_clips(js, binary, clips, names):
    """Every bone's rotation, the donkeys' bodies' translation too, one key a frame. The turret, the tube and
    the muzzle are the game's (MuleGun) and are never keyed."""
    js["animations"] = []
    idx = {n["name"]: i for i, n in enumerate(js["nodes"]) if "name" in n}
    keyed = [n for n in names if n not in ("root", "turret", "tube", "muzzle")]
    for clip, keys in clips.items():
        times = np.arange(len(keys), dtype=np.float32) / FPS
        tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
        anim = {"name": clip, "channels": [], "samplers": []}
        for bone in keyed:
            quats = []
            prev = None
            for k in keys:
                q = mat_to_quat(k[bone][:3, :3])
                if prev is not None and np.dot(q, prev) < 0:
                    q = -q  # the short way round
                quats.append(q)
                prev = q
            out = add_accessor(js, binary, np.array(quats), "VEC4")
            anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
            anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "rotation"}})
            if bone.endswith("_body"):
                out = add_accessor(js, binary, np.array([k[bone][:3, 3] for k in keys]), "VEC3")
                anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
                anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "translation"}})
        js["animations"].append(anim)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    if js.get("skins"):
        sys.exit("expected the static model (no skin): " + args.input)
    team, names = rebuild(js, binary)
    baker = Baker(Rig(js), team, names)
    baker.walk()
    baker.idle()
    baker.setup()
    baker.armed()
    write_clips(js, binary, baker.clips, names)
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/rig_mule.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: {len(names)} bones, clips {list(baker.clips)}")
    if args.preview:
        render_preview(args.output, args.preview)


# ---------------------------------------------------------------- preview

def skinned(js, binary, clip=None, frame=0, yaw=0.0):
    """The mesh's vertices posed by a clip's frame (or the rest pose) with the turret turned by yaw, its
    triangles and UVs, and the muzzle's model-space matrix."""
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
    ti = next(i for i, n in enumerate(nodes) if n.get("name") == "turret")
    local[ti] = local[ti] @ rotation(rot_y(yaw))
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
    muzzle = w(next(i for i, n in enumerate(nodes) if n.get("name") == "muzzle"))
    return out, idx, uv, muzzle


def render_preview(path, out_dir):
    """Sheets of frames per clip: the Walk side on (travelling over a grid: planted hooves stay put on it) and
    close on the lead pair; the rest side on and from an RTS camera's height; and the set-up gun traversed."""
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    js, binary = read_glb(path)
    mat = js["materials"][0]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    tex = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((1024, 1024)), dtype=np.float32) / 255.0
    lengths = {a["name"]: int(accessor(js, binary, a["samplers"][0]["input"]).shape[0]) for a in js["animations"]}
    W, H = 420, 260
    views = {"side": (v3((13.0, 1.6, 0.0)), v3((0.0, 1.3, 0.0)), 50.0),
             "rts": (v3((-9.0, 11.0, 9.0)), v3((0.0, 0.8, -0.5)), 50.0),
             "lead": (v3((3.2, 0.8, 4.4)), v3((0.0, 0.45, 3.4)), 40.0),
             "hooves": (v3((2.6, 0.35, 0.2)), v3((0.0, 0.25, -0.3)), 45.0)}

    def tile(pts, idx, uv, muzzle, eye, target, fov, label, travel=0.0):
        img = np.ones((H, W, 3), np.float32) * np.array([0.6, 0.7, 0.8], np.float32)
        zb = np.full((H, W), np.inf, np.float32)
        eye_t, target_t = eye + Z * travel, target + Z * travel
        rasterize(img, zb, pts + Z * travel, idx, uv, tex, eye_t, target_t, fov=fov)
        pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
        dr = ImageDraw.Draw(pil)
        for zk in np.arange(math.floor(travel - 8), travel + 8, 0.25):
            seg = np.array([[-1.4, 0, zk], [1.4, 0, zk]])
            sx, sy, cz = project(seg, eye_t, target_t, W, H, fov)
            if (cz > 0.1).all():
                dr.line([(sx[0], sy[0]), (sx[1], sy[1])], fill=(70, 95, 70) if zk % 1 else (40, 60, 40))
        tip = muzzle[:3, 3] + Z * travel
        s = np.array([tip, tip + muzzle[:3, :3] @ Z * 1.5])
        sx, sy, cz = project(s, eye_t, target_t, W, H, fov)
        if (cz > 0.1).all():
            dr.line([(sx[0], sy[0]), (sx[1], sy[1])], fill=(255, 120, 0), width=2)
        dr.text((4, 4), label, fill=(0, 0, 0))
        return pil

    def sheet(name, tiles, cols):
        rows = (len(tiles) + cols - 1) // cols
        out = Image.new("RGB", (W * cols, H * rows))
        for k, p in enumerate(tiles):
            out.paste(p, (W * (k % cols), H * (k // cols)))
        out.save(os.path.join(out_dir, name + ".png"))

    tiles = []
    pts, idx, uv, mz = skinned(js, binary)
    for vname in ("side", "rts", "lead", "hooves"):
        tiles.append(tile(pts, idx, uv, mz, *views[vname], f"rest {vname}"))
    sheet("rest", tiles, 2)
    for clip in [a["name"] for a in js["animations"]]:
        n = lengths[clip]
        tiles = []
        if clip == "Walk":
            for f in range(0, n - 1, 3):
                pts, idx, uv, mz = skinned(js, binary, clip, f)
                travel = WALK_SPEED * f / FPS
                for vname in ("lead", "hooves"):
                    tiles.append(tile(pts, idx, uv, mz, *views[vname], f"{clip} {f}/{n - 1} {vname}", travel))
            sheet(clip, tiles, 4)
            continue
        frames = sorted(set(np.linspace(0, n - 1, 6).round().astype(int)))
        for f in frames:
            pts, idx, uv, mz = skinned(js, binary, clip, f)
            for vname in ("side", "rts"):
                tiles.append(tile(pts, idx, uv, mz, *views[vname], f"{clip} {f}/{n - 1} {vname}"))
        sheet(clip, tiles, 4)
    tiles = []
    for deg in (0, 60, 120, 180, -90, -30):
        pts, idx, uv, mz = skinned(js, binary, "Armed", 0, deg * RAD)
        tiles.append(tile(pts, idx, uv, mz, *views["rts"], f"Armed, turret {deg} deg"))
    sheet("Traverse", tiles, 3)
    print(f"preview in {out_dir}")


if __name__ == "__main__":
    main()
