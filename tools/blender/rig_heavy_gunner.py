"""Rig and animate the Heavy Gunner, the minigun defender. The Meshy export comes with an auto-rig
(SmartRigArmature) but no clips, and its minigun is skinned to the left arm and thigh.

The auto-rig's skin weights are kept for the body: its bones are rebuilt in the same places with
clean names (pelvis, spine_1, thigh_L ...) and their weights carried over. The minigun is re-skinned
rigidly: the receiver, the ammo drum and the hand on it follow `gun` (a child of the chest), and the
barrel cluster with its clamps spins on `barrels`, whose Y axis runs down the barrels. `muzzle` marks
the barrel tips (no weights). The ammo belt loses its pull from the left leg so it hangs from the
hips instead of riding the knee. The model is scaled to HEIGHT and its origin put under the hips.

Combat stance: the export holds the minigun about 34 degrees off to its left. Every clip twists the
torso that far to the right and the neck back, so the barrels point straight down the trooper's
front (-Y here, +Z in Godot) and it looks where it shoots.

Clips (FPS frames per second, keyed bones only; gun, barrels and the left arm are left to the game):
  Idle        breathing, a slow weight shift and a look around, the feet planted.
  Walk_<dir>  eight directions, one cycle of WALK_PERIOD each, all in step (the left foot mid-swing
              at the start) so the game blends them by direction (HeavyGunner). <dir> is where the
              trooper goes, relative to where it faces: F, FR, R, BR, B, BL, L, FL. The game puts
              them on a unit circle; the clip at (x, y) walks x * SIDE_SPEED to the right and
              y * FORWARD_SPEED (or BACK_SPEED) ahead. Feet are planted by IK: heel strike and
              roll over the toes going forward, toes first going back, a wider stance to the side.
              The hips ride as high as the planted legs allow, sway over the standing foot and turn
              with each step while the chest stays steady on the gun; the free right arm swings.

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_heavy_gunner.py -- \\
      --input assets_src/defenders/heavy_gunner/heavy_gunner_meshy.glb \\
      --output game/assets/defenders/heavy_gunner/heavy_gunner_rigged.glb [--preview DIR]

--preview renders each clip (the walks travelling at their speed) into DIR as PNG frames.
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_rigged_humanoid import shrink_textures  # noqa: E402
from rig_elephant import Pose, _finish, _start, aim_frame, hermite, lowpass, smooth, two_bone, wave  # noqa: E402

FPS = 30
HEIGHT = 2.25  # meters, top of the support arm

# Natural ground speeds of the walk clips (m/s); the game's HeavyGunner uses the same numbers.
FORWARD_SPEED = 2.3
BACK_SPEED = 1.6
SIDE_SPEED = 1.1
WALK_PERIOD = 0.8  # seconds per cycle (two steps)
DUTY = 0.56  # share of the cycle each foot is on the ground
SWING = 1.0 - DUTY
SWING_MID = {"L": 0.0, "R": 0.5}  # middle of each foot's swing, as a share of the cycle
IDLE_PERIOD = 4.0
CROUCH = 0.05  # knees a little bent: the hips sit this much lower than the straight-legged rest
STRAIGHT = 0.985  # how straight a planted leg may get (share of its full length)
LIFT = 0.17  # foot clearance mid-swing walking forward (m)
STRIKE = math.radians(14.0)  # toes up at heel strike
PUSH = math.radians(34.0)  # heel up when rolling over the toes at lift-off
HEEL_OFF = 0.32  # last share of the stance in which the heel peels off
WIDEN = 0.04  # extra half-width of the stance walking sideways (m)
SWAY = 0.035  # hips over the standing foot (m)
YAW = math.radians(5.0)  # hips turning with the stride
ROLL = math.radians(2.5)  # the swinging side's hip dropping
ARM_SWING = math.radians(11.0)
# Where each clip goes: name -> point on the unit circle (x right, y ahead).
DIRECTIONS = {
    "F": (0.0, 1.0), "FR": (0.7071, 0.7071), "R": (1.0, 0.0), "BR": (0.7071, -0.7071),
    "B": (0.0, -1.0), "BL": (-0.7071, -0.7071), "L": (-1.0, 0.0), "FL": (-0.7071, 0.7071),
}

# Auto-rig bones -> new bones (their weights are summed). Meshy names the bones by number.
GROUPS = {
    "pelvis": ["Bone_000", "Bone_002", "Bone_001"],
    "spine_1": ["Bone_007"], "spine_2": ["Bone_006"], "chest": ["Bone_005", "Bone_004", "Bone_003"],
    "neck": ["Bone_023"], "head": ["Bone_022"],
    "clavicle_L": ["Bone_027"], "upperarm_L": ["Bone_026"], "forearm_L": ["Bone_025"], "hand_L": ["Bone_024"],
    "clavicle_R": ["Bone_033"], "upperarm_R": ["Bone_032"], "forearm_R": ["Bone_031"],
    "hand_R": ["Bone_030", "Bone_029", "Bone_028"],
    "thigh_L": ["Bone_014"], "shin_L": ["Bone_013"], "foot_L": ["Bone_012", "Bone_011"],
    "toe_L": ["Bone_010", "Bone_009", "Bone_008"],
    "thigh_R": ["Bone_021"], "shin_R": ["Bone_020"], "foot_R": ["Bone_019", "Bone_018"],
    "toe_R": ["Bone_017", "Bone_016", "Bone_015"],
}
# New bones: name -> (parent, head joint, tail joint). A joint is an auto-rig bone's head, or
# "<bone>.tail"; toes get their tail laid flat out in front (see build_armature).
SKELETON = [
    ("pelvis", None, "Bone_000", "Bone_007"),
    ("spine_1", "pelvis", "Bone_007", "Bone_006"),
    ("spine_2", "spine_1", "Bone_006", "Bone_005"),
    ("chest", "spine_2", "Bone_005", "Bone_023"),
    ("neck", "chest", "Bone_023", "Bone_022"),
    ("head", "neck", "Bone_022", "Bone_022.tail"),
    ("clavicle_L", "chest", "Bone_027", "Bone_026"),
    ("upperarm_L", "clavicle_L", "Bone_026", "Bone_025"),
    ("forearm_L", "upperarm_L", "Bone_025", "Bone_024"),
    ("hand_L", "forearm_L", "Bone_024", "Bone_024.tail"),
    ("clavicle_R", "chest", "Bone_033", "Bone_032"),
    ("upperarm_R", "clavicle_R", "Bone_032", "Bone_031"),
    ("forearm_R", "upperarm_R", "Bone_031", "Bone_030"),
    ("hand_R", "forearm_R", "Bone_030", "Bone_028.tail"),
    ("thigh_L", "pelvis", "Bone_014", "Bone_013"),
    ("shin_L", "thigh_L", "Bone_013", "Bone_012"),
    ("foot_L", "shin_L", "Bone_012", "Bone_011"),
    ("toe_L", "foot_L", "Bone_011", None),
    ("thigh_R", "pelvis", "Bone_021", "Bone_020"),
    ("shin_R", "thigh_R", "Bone_020", "Bone_019"),
    ("foot_R", "shin_R", "Bone_019", "Bone_018"),
    ("toe_R", "foot_R", "Bone_018", None),
]
LEG_BONES = {s: ("thigh_" + s, "shin_" + s, "foot_" + s, "toe_" + s) for s in "LR"}
# Share of the combat twist taken by each spine bone, and of the neck's counter-twist.
TWIST = {"spine_1": 0.3, "spine_2": 0.4, "chest": 0.3}
COUNTER_TWIST = {"neck": 0.5, "head": 0.5}

# Gun parts, measured along the barrel axis (t, from the middle of the barrel cluster, in the
# export's meters) and out from it (r). The receiver's back end sits beside the left hip, so only
# loose pieces the auto-rig hung on the left arm count as gun back there; of the body mesh only
# the hand on the receiver does.
GUN_T = (-0.70, 0.56)  # receiver back to barrel tips
GUN_R = 0.17
HAND_T = -0.42  # body mesh vertices in front of this (and within GUN_R) are the hand on the gun
ARM_BONES = ("Bone_024", "Bone_025", "Bone_026", "Bone_027")
COLLAR_T = -0.02  # where the barrels leave the receiver: everything in front of it spins
SPIN_R = 0.07


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


# ---------------------------------------------------------------- mesh and weights

def pieces_of(mesh):
    """Connected pieces, counting vertices at the same spot as joined (the export splits the mesh
    along its UV seams). Largest first: the trooper, then the gear."""
    n = len(mesh.data.vertices)
    root = list(range(n))

    def find(a):
        while root[a] != a:
            root[a] = root[root[a]]
            a = root[a]
        return a

    def join(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            root[ra] = rb

    seen = {}
    for v in mesh.data.vertices:
        k = tuple(round(c * 1e4) for c in v.co)
        if k in seen:
            join(v.index, seen[k])
        else:
            seen[k] = v.index
    for e in mesh.data.edges:
        join(e.vertices[0], e.vertices[1])
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return sorted(groups.values(), key=len, reverse=True)


def barrel_axis(co, pieces):
    """(centre, direction) of the barrel cluster: the long thin pieces lying along the gun, whose
    front ends reach its muzzle. The barrels ring the axis, so their mean sits on it."""
    guess = np.array([0.56, -0.83, 0.0])
    guess /= np.linalg.norm(guess)
    long = []
    for p in pieces[1:]:
        c = co[p]
        m = c.mean(axis=0)
        if len(p) < 8 or m[2] < 0.8:
            continue
        _, _, vt = np.linalg.svd(c - m)
        ext = (c - m) @ vt[0]
        if ext.max() - ext.min() > 0.4 and abs(vt[0] @ guess) > 0.97:
            long.append(p)
    front = max(float((co[p] @ guess).max()) for p in long)
    barrels = [p for p in long if (co[p] @ guess).max() > front - 0.15]
    pts = np.concatenate([co[p] for p in barrels])
    centre = pts.mean(axis=0)
    _, _, vt = np.linalg.svd(pts - centre)
    d = vt[0] if vt[0] @ guess > 0 else -vt[0]
    return centre, d / np.linalg.norm(d), barrels


def read_weights(mesh):
    """Per vertex {auto-rig bone: weight}."""
    names = {g.index: g.name for g in mesh.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups if g.weight > 0.0} for v in mesh.data.vertices]


def reweight(mesh, pieces, centre, axis, barrels):
    """New weights for every vertex: the body's carried over from the auto-rig, the gun rigid."""
    old = read_weights(mesh)
    to_new = {o: n for n, olds in GROUPS.items() for o in olds}
    co = np.array([v.co for v in mesh.data.vertices])
    rel = co - centre
    t = rel @ axis
    r = np.linalg.norm(rel - np.outer(t, axis), axis=1)
    in_gun = np.zeros(len(co), bool)
    body = pieces[0]
    in_gun[body] = (t[body] > HAND_T) & (t[body] < GUN_T[1]) & (r[body] < GUN_R)
    spin = np.zeros(len(co), bool)
    for p in barrels:
        spin[p] = True
    for p in pieces[1:]:
        m = rel[p].mean(axis=0)
        mt = m @ axis
        mr = np.linalg.norm(m - mt * axis)
        if mt > COLLAR_T and mr < SPIN_R:
            spin[p] = True
        elif GUN_T[0] < mt < GUN_T[1] and mr < GUN_R:
            total = {}
            for i in p:
                for o, x in old[i].items():
                    total[o] = total.get(o, 0.0) + x
            if max(total, key=total.get) in ARM_BONES:  # not the leg brace's hip joint
                in_gun[p] = True
    # The ammo drum hangs under the receiver: the biggest loose piece around the axis' back half.
    drum = max((p for p in pieces[1:] if np.median(r[p]) < 0.2 and np.median(t[p]) < -0.1),
               key=lambda p: np.ptp(co[p], axis=0).prod())
    in_gun[drum] = True
    # Belt links: small pieces behind the gun, beside and behind the left hip.
    belt = np.zeros(len(co), bool)
    for p in pieces[1:]:
        c = co[p]
        m = c.mean(axis=0)
        size = np.ptp(c, axis=0)
        strut = abs(m[0] - 0.09) < 0.06 and abs(m[1] - 0.33) < 0.04  # the leg brace's rods
        if 20 <= len(p) <= 27 and size.max() < 0.13 and m[1] > 0.12 and -0.1 < m[0] < 0.45 \
                and 0.3 < m[2] < 1.2 and not strut:
            belt[p] = True
    weights = []
    for i, w in enumerate(old):
        if spin[i]:
            weights.append({"barrels": 1.0})
            continue
        if in_gun[i]:
            weights.append({"gun": 1.0})
            continue
        nw = {}
        for o, x in w.items():
            name = to_new[o]
            if belt[i] and name in ("thigh_L", "shin_L", "foot_L", "toe_L"):
                name = "pelvis"
            nw[name] = nw.get(name, 0.0) + x
        weights.append(nw or {"pelvis": 1.0})
    print(f"gun: {int(in_gun.sum())} verts rigid, {int(spin.sum())} spinning, belt {int(belt.sum())}")
    return weights


def apply_weights(mesh, weights):
    mesh.vertex_groups.clear()
    groups = {}
    for i, w in enumerate(weights):
        total = sum(w.values())
        for name, x in w.items():
            if x / total > 0.001:
                if name not in groups:
                    groups[name] = mesh.vertex_groups.new(name=name)
                groups[name].add([i], x / total, "REPLACE")


# ---------------------------------------------------------------- load and rebuild

class Model:
    """The export moved to its game frame: origin under the hips, HEIGHT tall, front -Y."""

    def __init__(self, path):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        junk = bpy.data.objects.get("Icosphere")
        if junk:
            bpy.data.objects.remove(junk, do_unlink=True)
        self.mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
        old = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
        self.joints = {}
        for b in old.data.bones:
            self.joints[b.name] = old.matrix_world @ b.head_local
            self.joints[b.name + ".tail"] = old.matrix_world @ b.tail_local
        mw = self.mesh.matrix_world.copy()
        self.mesh.parent = None
        self.mesh.matrix_world = mw
        for m in list(self.mesh.modifiers):
            self.mesh.modifiers.remove(m)
        bpy.data.objects.remove(old, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        self.mesh.select_set(True)
        bpy.context.view_layer.objects.active = self.mesh
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        co = np.array([v.co for v in self.mesh.data.vertices])
        self.scale = HEIGHT / (co[:, 2].max() - co[:, 2].min())
        hips = self.joints["Bone_000"]
        self.shift = Vector((hips.x, hips.y, co[:, 2].min()))

    def place(self, p) -> Vector:
        """A point in the export's frame, moved and scaled like the mesh."""
        return (Vector(p) - self.shift) * self.scale

    def move_mesh(self):
        me = self.mesh.data
        co = np.array([v.co for v in me.vertices])
        co = (co - np.array(self.shift)) * self.scale
        me.vertices.foreach_set("co", co.ravel())
        me.update()


def build_armature(model, centre, axis):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, parent, head, tail, deform=True):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
        b.use_deform = deform
        return b

    j = model.joints
    for name, parent, head, tail in SKELETON:
        h = model.place(j[head])
        if tail is None:  # toes: flat out in front of the ball of the foot
            t = h + Vector((0, -0.16, 0))
        else:
            t = model.place(j[tail])
        bone(name, parent, h, t)
    a = Vector(axis)  # directions only scale, they don't shift

    def on_axis(tt):
        return model.place(Vector(centre) + a * tt)

    bone("gun", "chest", on_axis(-0.25), on_axis(-0.25) + a * 0.3)
    bone("barrels", "gun", on_axis(COLLAR_T), on_axis(GUN_T[1]))
    bone("muzzle", "gun", on_axis(GUN_T[1] + 0.03), on_axis(GUN_T[1] + 0.03) + a * 0.1, deform=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = model.mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    model.mesh.parent = arm
    return arm


# ---------------------------------------------------------------- walking

class Legs:
    """Rest measurements of both legs, the foot paths of a walk and the IK that poses them."""

    def __init__(self, pose, model):
        self.pose = pose
        self.info = {}
        co = np.array([v.co for v in model.mesh.data.vertices])
        for s in "LR":
            th, sh, ft, toe = LEG_BONES[s]
            hip, knee, ankle = (pose.rest[b].translation.copy() for b in (th, sh, ft))
            ball = pose.rest[toe].translation.copy()
            # The boot's sole: heel and toe tips from the vertices near the ground under this foot.
            near = co[(co[:, 2] < 0.12) & (np.abs(co[:, 0] - ankle.x) < 0.2)]
            self.info[s] = {
                "bones": (th, sh, ft, toe), "l1": (knee - hip).length, "l2": (ankle - knee).length,
                "hip": hip, "ankle": ankle, "ball": Vector((ball.x, ball.y, 0.0)),
                "heel": Vector((ankle.x, float(near[:, 1].max()), 0.0)),
                "tip": Vector((ankle.x, float(near[:, 1].min()), 0.0)),
                "side": 1.0 if s == "L" else -1.0,
            }

    @staticmethod
    def clip(direction):
        """(unit direction of travel, speed, forward share) of a walk clip; front is -Y, right -X."""
        bx, by = DIRECTIONS[direction]
        v = Vector((-bx * SIDE_SPEED, -by * (FORWARD_SPEED if by >= 0 else BACK_SPEED), 0.0))
        d = v.normalized()
        return d, v.length, -d.y

    def stance_foot(self, s, u, walk):
        """(ankle, foot pitch, toe bend) u of the way through the stance."""
        i = self.info[s]
        d, sweep, fwd = walk["d"], walk["sweep"], walk["fwd"]
        ground = Vector((i["ankle"].x + i["side"] * walk["widen"], i["ankle"].y, 0.0)) + d * sweep * (0.5 - u)
        ahead, behind = max(fwd, 0.0), max(-fwd, 0.0)
        # Going forward: heel strike, flat, heel peels off and the foot rolls over the toes.
        # Going back: toes first, flat, then the toes lift and it rocks back onto the heel.
        strike = smooth(0.18, 0.0, u)
        peel = smooth(1.0 - HEEL_OFF, 1.0, u) ** 1.5
        pitch = -STRIKE * ahead * strike + PUSH * ahead * peel + STRIKE * behind * strike - STRIKE * behind * peel
        if pitch > 0.0:
            pivot = i["ball"] if ahead >= behind else i["tip"]
        else:
            pivot = i["heel"]
        toe = -pitch if pitch > 0.0 and pivot is i["ball"] else 0.0
        return self._ankle(i, ground, pitch, pivot), pitch, toe

    def _ankle(self, i, ground, pitch, pivot):
        """Ankle position for the foot standing on `ground` (the spot under its ankle at rest),
        pitched about `pivot` (heel, ball or toe tip, at rest)."""
        foot0 = Vector((i["ankle"].x, i["ankle"].y, 0.0))
        rel = Vector((0.0, 0.0, i["ankle"].z)) - (pivot - foot0)
        return ground + (pivot - foot0) + Matrix.Rotation(pitch, 3, "X") @ rel

    def foot(self, s, t, walk):
        """(ankle, foot pitch, toe bend) at time t of the walk."""
        phase = (t / WALK_PERIOD - SWING_MID[s] + SWING / 2) % 1.0  # 0 at lift-off
        if phase >= SWING:
            return self.stance_foot(s, (phase - SWING) / DUTY, walk)
        u = phase / SWING
        a0, p0, t0 = self.stance_foot(s, 1.0, walk)  # lift-off
        a1, p1, _ = self.stance_foot(s, 0.0, walk)  # touch-down
        d = walk["d"]
        v = walk["sweep"] * SWING / DUTY  # the ground's travel during the swing
        # Along the way of travel it leaves the ground easing out of the backward drift and lands
        # moving with the ground; across it, it swings out a little from the other foot.
        along = hermite(a0.dot(d), a1.dot(d), -0.35 * v, -v, u)
        base = a0.lerp(a1, u)
        pos = base + d * (along - base.dot(d))
        pos.z += walk["lift"] * math.sin(math.pi * u ** 0.85) ** 1.2
        pos.x += self.info[s]["side"] * 0.025 * math.sin(math.pi * u)
        pitch = p0 + (p1 - p0) * smooth(0.0, 0.65, u) - math.radians(8.0) * walk["ahead"] * math.sin(math.pi * u)
        toe = t0 * smooth(0.45, 0.0, u)
        return pos, pitch, toe

    def reach(self, s, ankle, hip):
        """Highest the hip joint can be above its rest height and still reach `ankle`."""
        i = self.info[s]
        full = (i["l1"] + i["l2"]) * STRAIGHT
        flat = Vector((hip.x - ankle.x, hip.y - ankle.y)).length
        return ankle.z + math.sqrt(max(full * full - flat * flat, 0.0)) - hip.z

    def solve(self, s, ankle, pitch, toe, pole):
        """Poses the leg to put the ankle at `ankle`, the foot pitched and the toes bent."""
        i = self.info[s]
        th, sh, ft, tb = i["bones"]
        p = self.pose
        a = p.head(th)
        knee, end = two_bone(a, i["l1"], i["l2"], ankle, pole)
        for name, h, t in ((th, a, knee), (sh, knee, end)):
            r = p.rest[name]
            rest_y = r.to_3x3() @ Vector((0, 1, 0))
            q = aim_frame((t - h).normalized(), pole) @ aim_frame(rest_y, pole).inverted()
            p.place(name, Matrix.Translation(h) @ (q @ r.to_3x3()).to_4x4())
        r = p.rest[ft]
        p.place(ft, Matrix.Translation(end) @ (Matrix.Rotation(pitch, 3, "X") @ r.to_3x3()).to_4x4())
        if toe:
            p.turn(tb, (1, 0, 0), toe)
        return (end - ankle).length


ANIMATED = ["pelvis", "spine_1", "spine_2", "chest", "neck", "head", "clavicle_R", "upperarm_R", "forearm_R",
            "hand_R"] + [b for bones in LEG_BONES.values() for b in bones]
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
RAD = math.pi / 180


def stance(pose, twist, yaw=0.0, roll=0.0):
    """Combat stance on top of the hips' own turn and roll: the spine turns the chest onto the gun
    (cancelling the hips' turn) and levels it, the neck turns the head back to look down the gun."""
    for name, share in TWIST.items():
        pose.turn(name, Z, twist * share - yaw * share)
    pose.turn("spine_1", Y, -roll * 0.6)
    pose.turn("spine_2", Y, -roll * 0.4)
    for name, share in COUNTER_TWIST.items():
        pose.turn(name, Z, -twist * share)


def walk_params(direction):
    d, speed, fwd = Legs.clip(direction)
    side = abs(d.x)
    return {
        "d": d, "speed": speed, "fwd": fwd, "ahead": max(fwd, 0.0),
        "sweep": speed * WALK_PERIOD * DUTY,
        "widen": WIDEN * side,
        "lift": LIFT * (0.75 + 0.25 * max(fwd, 0.0)),
    }


def hip_heights(legs, walk, ts, sway):
    """How high the hips ride each frame: as high as the planted legs allow when nearly straight,
    so the body vaults over them (two dips per cycle). A foot just off the ground, or about to land,
    has to be reachable too."""
    out = []
    for k, t in enumerate(ts):
        r = []
        for s in "LR":
            phase = (t / WALK_PERIOD - SWING_MID[s] + SWING / 2) % 1.0
            if not 0.3 * SWING < phase < 0.75 * SWING:
                ankle, _, _ = legs.foot(s, t, walk)
                hip = legs.info[s]["hip"] + Vector((sway[k], 0, 0))
                r.append(legs.reach(s, ankle, hip))
        out.append(min(r))
    smooth_rise = lowpass(out, 4)
    over = max(s - r for s, r in zip(smooth_rise, out))
    return [s - over for s in smooth_rise]


def bake_walk(arm, pose, legs, direction, twist):
    walk = walk_params(direction)
    frames = int(round(WALK_PERIOD * FPS))
    T = WALK_PERIOD
    ts = [f / FPS for f in range(frames)]
    fwd, side = walk["fwd"], walk["d"].x
    # Weight over the standing foot: the right one is down at the start (the left mid-swing).
    sway = [SWAY * (0.4 + 0.6 * abs(fwd)) * -math.cos(2 * math.pi * t / T) for t in ts]
    rise = hip_heights(legs, walk, ts, sway)
    rise = [min(x, 0.0) - CROUCH for x in rise]
    rise.append(rise[0])
    sway.append(sway[0])
    ts.append(T)
    _start(arm, "Walk_" + direction)
    worst, closest = 0.0, 9.0
    for f, t in enumerate(ts):
        pose.reset()
        yaw = -YAW * abs(fwd) * wave(t, T, phase=0.0) * (1 if fwd >= 0 else -1)
        roll = ROLL * (0.3 + 0.7 * abs(fwd)) * math.cos(2 * math.pi * t / T)
        # Leaning into the walk; a dip and a little nod as each foot lands.
        lean = (4.0 * max(fwd, 0.0) - 3.0 * max(-fwd, 0.0)) * RAD
        pose.move("pelvis", (sway[f], 0, rise[f]))
        pose.turn("pelvis", Z, yaw)
        pose.turn("pelvis", Y, roll)
        pose.turn("pelvis", X, lean)
        pose.turn("pelvis", Y, -2.5 * RAD * side)  # leaning into a sidestep
        stance(pose, twist, yaw, roll)
        pose.turn("spine_1", X, -lean * 0.5)
        pose.turn("chest", X, 1.2 * RAD * wave(t, T, 2, 0.3))
        pose.turn("head", X, -1.0 * RAD * wave(t, T, 2, 0.3))
        # The free arm swings against the right leg (forward as the left leg reaches out).
        swing = ARM_SWING * (0.25 + 0.75 * abs(fwd)) * wave(t, T, phase=0.0) * (1 if fwd >= 0 else -1)
        pose.turn("upperarm_R", X, -swing)
        pose.turn("forearm_R", X, -(6.0 * RAD + 0.4 * max(swing, 0.0)))
        pose_q = Matrix.Rotation(yaw, 3, "Z")
        pole = pose_q @ Vector((0, -1, 0))
        ankles = {}
        for s in "LR":
            ankle, pitch, toe = legs.foot(s, t, walk)
            worst = max(worst, legs.solve(s, ankle, pitch, toe, pole))
            ankles[s] = ankle
        closest = min(closest, (ankles["L"].xy - ankles["R"].xy).length)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    print(f"Walk_{direction}: {walk['speed']:.2f} m/s, sweep {walk['sweep']:.2f} m, hips {min(rise):+.3f}..{max(rise):+.3f} m, "
          f"feet at least {closest:.2f} m apart, worst miss {worst * 100:.1f} cm")


def bake_idle(arm, pose, legs, twist):
    frames = int(round(IDLE_PERIOD * FPS))
    T = IDLE_PERIOD
    _start(arm, "Idle")
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        shift = 0.018 * wave(t, T, 1, 0.1)
        roll = 0.8 * RAD * wave(t, T, 1, 0.1)
        pose.move("pelvis", (shift, 0, -CROUCH - 0.008 + 0.006 * wave(t, T, 2)))
        pose.turn("pelvis", Y, roll)
        stance(pose, twist, 0.0, roll)
        pose.turn("chest", X, -1.0 * RAD * wave(t, T, 2, 0.25))  # breathing
        pose.turn("head", Z, 5.0 * RAD * wave(t, T, 1, 0.35))
        pose.turn("head", X, 1.5 * RAD * wave(t, T, 1, 0.6))
        pose.turn("upperarm_R", X, 2.0 * RAD * wave(t, T, 1, 0.2))
        pose.turn("forearm_R", X, -6.0 * RAD)
        pole = Vector((0, -1, 0))
        for s, i in legs.info.items():
            legs.solve(s, i["ankle"], 0.0, 0.0, pole)
        pose.key(arm, f, ANIMATED)
    _finish(arm)
    print(f"Idle: {frames} frames")


# ---------------------------------------------------------------- preview

def render_preview(arm, out_dir):
    """Each clip from the side and from three quarters, the walks travelling at their speed."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"  # clay: the armor textures are nearly black
    sc.display.shading.single_color = (0.75, 0.72, 0.68)
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 640, 640
    sc.render.fps = FPS
    sc.render.image_settings.file_format = "PNG"
    ground = bpy.data.materials.new("ground")
    ground.diffuse_color = (0.42, 0.4, 0.3, 1)
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    bpy.context.object.data.materials.append(ground)
    for i in range(-15, 16):
        for j in range(-15, 16):
            bpy.ops.mesh.primitive_cube_add(size=0.05, location=(i * 1.0, j * 1.0, 0.025))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 40
    arm.animation_data_create()
    clips = ["Idle"] + ["Walk_" + d for d in DIRECTIONS]
    for clip in clips:
        action = bpy.data.actions[clip]
        arm.animation_data.action = action
        length = int(round((IDLE_PERIOD if clip == "Idle" else WALK_PERIOD) * FPS))
        v = Vector((0, 0, 0))
        if clip != "Idle":
            d, speed, _ = Legs.clip(clip[5:])
            v = d * speed
        for view, off in (("side", Vector((5.5, 0.0, 1.4))), ("q", Vector((3.5, -4.5, 1.8)))):
            for k in range(length):
                sc.frame_set(k)
                p = v * (k / FPS)
                arm.location = p
                cam.location = p + off
                cam.rotation_euler = (p + Vector((0, 0, 1.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
                sc.render.filepath = os.path.join(out_dir, "%s_%s_%03d.png" % (clip, view, k))
                bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    arm.location = (0, 0, 0)


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    model = Model(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    co = np.array([v.co for v in model.mesh.data.vertices])
    pieces = pieces_of(model.mesh)
    centre, axis, barrels = barrel_axis(co, pieces)
    weights = reweight(model.mesh, pieces, centre, axis, barrels)
    twist = -math.atan2(axis[0], -axis[1])  # turns the barrels onto the front (-Y)
    model.move_mesh()
    apply_weights(model.mesh, weights)
    arm = build_armature(model, centre, axis)
    pose = Pose(arm)
    legs = Legs(pose, model)
    for d in DIRECTIONS:
        bake_walk(arm, pose, legs, d, twist)
    bake_idle(arm, pose, legs, twist)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    print(f"exported {args.output}: {len(arm.data.bones)} bones, scale {model.scale:.3f}, "
          f"stance twist {math.degrees(twist):.1f} deg, clips {[a.name for a in bpy.data.actions]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
