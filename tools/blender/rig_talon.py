"""Flight clips for the Sky Talon (the armored hawk). Meshy's SmartRig poses it standing, its wings
hanging folded along its flanks, and comes with no clips.

The body keeps Meshy's rig and weights. Each wing is re-skinned onto two new bones: wing_L / wing_R
(the inner wing, hinged at the shoulder) and hand_L / hand_R (the outer wing and its long feathers,
hinged at the wrist); the old wing bones are removed. The box strapped to the left wing rides
rigidly on wing_L, like a pod. Flying, the body levels out, the legs tuck back under the tail and
each wing lifts out to the side, its hand sweeping forward so the feathers point out along the span.

Two looping clips, both in the same flight pose so the game can crossfade between them:

  Glide  wings held out with a slight dihedral, flexing a little in the air; the tail steers and the
         head looks around and down at the ground.
  Flap   one wing beat: up with the hand tucked in, a powerful downstroke fully spread, the hand
         lagging behind the arm and the body lifting with each stroke.

Run headless (Blender 5.2, or the bpy 5.2 pip package):
  python tools/blender/rig_talon.py -- \\
      --input assets_src/units/sky_talon_battalion/sky_talon_battalion_rigged_meshy.glb \\
      --output game/assets/units/sky_talon_battalion/sky_talon_battalion_rigged.glb \\
      [--preview DIR]

--preview renders the flight pose from all round and both clips into DIR (PNG frames).
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

FPS = 30
HEIGHT = 2.1  # meters, standing, as for the other Sky Talon files

# Positions below are in the Meshy export as imported: front -Y, up +Z, the hawk's left +X,
# feet at z 0, 1.7 m tall. The export scales the armature object to HEIGHT, so the bones and
# the clips stay in these units.
HIPS = "Bone_000"  # the rig's root
CHEST = "Bone_002"
NECK = "Bone_022"
HEAD = "Bone_021"
TAIL = ["Bone_007", "Bone_006"]
# hip, knee, ankle (the tarsus), foot
LEG = {"L": ["Bone_012", "Bone_011", "Bone_010", "Bone_009"],
       "R": ["Bone_017", "Bone_016", "Bone_015", "Bone_014"]}
# toe chains, root first: the back toe, then the three front ones
TOES = {"L": [["Bone_031", "Bone_030", "Bone_029"], ["Bone_034", "Bone_033", "Bone_032"],
              ["Bone_037", "Bone_036", "Bone_035"], ["Bone_040", "Bone_039", "Bone_038"]],
        "R": [["Bone_043", "Bone_042", "Bone_041"], ["Bone_046", "Bone_045", "Bone_044"],
              ["Bone_052", "Bone_051", "Bone_050"], ["Bone_049", "Bone_048", "Bone_047"]]}
# Meshy's wing bones (shoulder, forearm, hand and four feather chains): replaced.
OLD_WING = {"L": ["Bone_025", "Bone_024", "Bone_023"] + ["Bone_%03d" % k for k in range(53, 65)],
            "R": ["Bone_028", "Bone_027", "Bone_026"] + ["Bone_%03d" % k for k in range(65, 77)]}

# Left wing (the right one mirrors it). The folded wing hangs along the flank as a panel whose
# outer face points out and up (NORMAL); its feathers run back and down (FEATHERS).
SHOULDER = (0.34, -0.25, 1.17)
WRIST = (0.66, -0.55, 0.92)
TIP = (0.95, 0.95, 0.30)
NORMAL = (0.835, -0.01, 0.55)
FEATHERS = (0.293, 0.854, -0.429)
# The box on the left wing: every part of the mesh above BOX_Z and out past BOX_X on that side.
BOX_Z = 0.9
BOX_X = 0.55

# Flight pose (degrees).
LIFT = 57.0  # turns the hanging wing up level: its outer face then points up
DIHEDRAL = 6.0  # and on up a little more, as hawks soar
SWEEP = 52.0  # the hand swings forward, so the feathers point out along the span
# Folded, the wings look smaller than they are: spread, the inner wing and the hand grow by these
# factors, for a hawk's span (about twice its length).
WING_GROW = 1.1
HAND_GROW = 1.35
BODY_PITCH = 8.0  # the body levels out (nose down)
TAIL_LIFT = 26.0  # the tail comes up in line with the body

GLIDE_PERIOD = 6.0
FLAP_PERIOD = 0.8  # seconds per wing beat
FLAP_UP = 40.0  # wing elevation at the top of the beat (degrees above the glide)
FLAP_DOWN = 28.0  # and at the bottom (below it)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    p.add_argument("--tex", type=int, default=2048)
    p.add_argument("--orm-tex", type=int, default=1024)
    return p.parse_args(argv)


def mirror(p, side):
    return Vector((p[0] if side == "L" else -p[0], p[1], p[2]))


def axis(a, side):
    """The axis for the right side's mirror image of a rotation about `a` on the left."""
    return mirror(a, side) * (1.0 if side == "L" else -1.0)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    junk = bpy.data.objects.get("Icosphere")  # stray helper mesh in the Meshy export
    if junk:
        bpy.data.objects.remove(junk, do_unlink=True)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    return arm, mesh


def fit(arm, mesh):
    """Scales the armature object to HEIGHT with the feet at the origin (as process_rigged_model.py
    did for the earlier file), keeping the bones in the export's units."""
    pts = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    min_z = min(p.z for p in pts)
    s = HEIGHT / (max(p.z for p in pts) - min_z)
    feet = [p for p in pts if p.z < min_z + 0.17]
    c = sum(feet, Vector()) / len(feet)
    arm.scale = (s, s, s)
    arm.location = (-c.x * s, -c.y * s, -min_z * s)
    bpy.context.view_layer.update()
    return s


# ---------------------------------------------------------------- skinning

def pieces(mesh):
    """Loose parts of the mesh (the export splits vertices along UV seams: weld them first)."""
    me = mesh.data
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def join(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[a] = b

    seen = {}
    for v in me.vertices:
        k = tuple(round(x, 4) for x in v.co)
        if k in seen:
            join(v.index, seen[k])
        else:
            seen[k] = v.index
    for e in me.edges:
        join(e.vertices[0], e.vertices[1])
    return np.array([find(i) for i in range(n)])


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def wing_weights(p, side):
    """(chest, wing, hand) weights of a wing vertex. The panel blends into the chest along the
    shoulder, and from the inner wing into the hand past the wrist, further out more of it."""
    s = mirror(SHOULDER, side)
    w = mirror(WRIST, side)
    f = mirror(FEATHERS, side).normalized()
    out = abs(p.x) - abs(s.x)  # how far out from the flank
    chest = 1.0 - smooth(0.0, 0.14, out)
    along = (p - w).dot(f)  # past the wrist, along the feathers
    hand = smooth(-0.15, 0.35, along) * smooth(0.05, 0.4, out)
    rest = 1.0 - chest
    return chest, rest * (1.0 - hand), rest * hand


def build_wings(arm, mesh):
    """Replaces Meshy's wing bones with wing_L/R and hand_L/R and re-skins the wings onto them."""
    me = mesh.data
    groups = {g.index: g.name for g in mesh.vertex_groups}
    old = {b: side for side, names in OLD_WING.items() for b in names}
    roots = pieces(mesh)
    co = np.array([v.co for v in me.vertices])
    # the box: whole loose parts high up on the left wing
    box_roots = set()
    for r in np.unique(roots):
        m = roots == r
        if co[m, 2].min() > BOX_Z and co[m, 0].mean() > BOX_X:
            box_roots.add(r)

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for side in "LR":
        wing = eb.new("wing_" + side)
        wing.head, wing.tail = mirror(SHOULDER, side), mirror(WRIST, side)
        wing.parent = eb[CHEST]
        hand = eb.new("hand_" + side)
        hand.head, hand.tail = mirror(WRIST, side), mirror(TIP, side)
        hand.parent = wing
        for name in OLD_WING[side]:
            eb.remove(eb[name])
    bpy.ops.object.mode_set(mode="OBJECT")

    vg = {name: mesh.vertex_groups.new(name=name) for name in ("wing_L", "hand_L", "wing_R", "hand_R")}
    chest = mesh.vertex_groups[CHEST]
    n_wing = n_box = 0
    for v in me.vertices:
        if not v.groups:
            continue
        top = max(v.groups, key=lambda g: g.weight)
        side = old.get(groups[top.group])
        if side is None:
            continue
        for g in list(v.groups):
            mesh.vertex_groups[g.group].remove([v.index])
        if roots[v.index] in box_roots:
            vg["wing_L"].add([v.index], 1.0, "REPLACE")
            n_box += 1
            continue
        n_wing += 1
        for group, wt in zip((chest, vg["wing_" + side], vg["hand_" + side]), wing_weights(v.co, side)):
            if wt > 0.001:
                group.add([v.index], wt, "REPLACE")
    for names in OLD_WING.values():
        for name in names:
            g = mesh.vertex_groups.get(name)
            if g:
                mesh.vertex_groups.remove(g)
    print(f"wings: {n_wing} vertices re-skinned, {n_box} on the box")


# ---------------------------------------------------------------- posing

class Pose:
    """Bone poses for one frame, built from rotations about armature axes (as the bones lie at
    rest) at each bone's head."""

    def __init__(self, arm):
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        self.parent = {b.name: b.parent.name if b.parent else None for b in arm.data.bones}
        self.basis = {}
        self.scale = {}

    def reset(self):
        self.basis = {}
        self.scale = {}

    def grow(self, name, factor):
        """Scales the bone (and what hangs off it) about its head."""
        self.scale[name] = factor

    def turn(self, name, axis, angle):
        """Adds a rotation of `angle` degrees about an armature axis (as the bone lies at rest)."""
        local = (self.rest[name].to_3x3().inverted() @ Vector(axis)).normalized()
        q = Quaternion(local, math.radians(angle))
        b = self.basis.get(name, Matrix.Identity(4))
        self.basis[name] = Matrix.Translation(b.translation) @ (q.to_matrix().to_4x4() @ b.to_3x3().to_4x4())

    def move(self, name, offset):
        """Moves a root bone by an armature-space offset."""
        b = self.basis.get(name, Matrix.Identity(4))
        local = self.rest[name].to_3x3().inverted() @ Vector(offset)
        self.basis[name] = Matrix.Translation(b.translation + local) @ b.to_3x3().to_4x4()

    def key(self, arm, frame, names):
        for name in names:
            b = self.basis.get(name, Matrix.Identity(4))
            pb = arm.pose.bones[name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = b.to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if self.parent[name] is None:
                pb.location = b.translation
                pb.keyframe_insert("location", frame=frame)
            if name in self.scale:
                pb.scale = (self.scale[name],) * 3
                pb.keyframe_insert("scale", frame=frame)


def wave(t, period, harmonic=1, phase=0.0):
    return math.sin(2 * math.pi * (harmonic * t / period - phase))


X = (1, 0, 0)
Y = (0, 1, 0)
Z = (0, 0, 1)


def flight_body(pose, bob=0.0, tail=0.0, tail_yaw=0.0, look=(0.0, 0.0)):
    """The body levelled out, the tail in line and the legs tucked back under it."""
    pose.turn(HIPS, X, BODY_PITCH)
    pose.move(HIPS, (0, 0, bob))
    pose.turn(TAIL[0], X, TAIL_LIFT + tail)
    pose.turn(TAIL[0], Z, tail_yaw)
    pose.turn(TAIL[1], X, tail * 0.6)
    pose.turn(NECK, X, -BODY_PITCH * 0.5 + look[1] * 0.4)
    pose.turn(NECK, Z, look[0] * 0.4)
    pose.turn(HEAD, X, -BODY_PITCH * 0.5 + look[1] * 0.6)
    pose.turn(HEAD, Z, look[0] * 0.6)
    for side in "LR":
        hip, knee, ankle = LEG[side][:3]
        pose.turn(hip, X, 100.0)  # the thigh swings back under the tail
        pose.turn(knee, X, -35.0)
        pose.turn(ankle, X, 45.0)  # the feet trail behind
        for chain in TOES[side]:
            for k, bone in enumerate(chain):
                pose.turn(bone, X, 25.0 if k else 15.0)  # the talons curl


def flight_wing(pose, side, elevation=0.0, sweep=0.0, bend=0.0, twist=0.0):
    """One wing spread: lifted level about the shoulder (plus elevation degrees up), the hand swept
    forward (less sweep tucks it back in), bent up at the wrist and twisted about the span
    (leading edge down)."""
    n = Vector(NORMAL)
    hinge = Vector((0, -1, 0))  # along the body: lifting about it turns the outer face up
    span = Vector(Y).cross(n)  # the way the folded panel hangs: out along the span once lifted
    pose.turn("wing_" + side, axis(hinge, side), LIFT + DIHEDRAL + elevation)
    pose.turn("wing_" + side, axis(span, side), twist)
    pose.turn("hand_" + side, axis(-n, side), SWEEP + sweep)
    pose.turn("hand_" + side, axis(hinge, side), bend)
    pose.grow("wing_" + side, WING_GROW)
    pose.grow("hand_" + side, HAND_GROW / WING_GROW)  # it inherits the inner wing's


def _start(arm, name):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action
    return action


def _finish(arm):
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)


def animated(arm):
    names = [HIPS, NECK, HEAD] + TAIL + ["wing_L", "hand_L", "wing_R", "hand_R"]
    for side in "LR":
        names += LEG[side] + [b for chain in TOES[side] for b in chain]
    return names


def bake_glide(arm, pose):
    _start(arm, "Glide")
    frames = int(round(GLIDE_PERIOD * FPS))
    names = animated(arm)
    for f in range(frames + 1):
        t = f / FPS
        pose.reset()
        look = (22.0 * wave(t, GLIDE_PERIOD, 1, 0.1), 10.0 * wave(t, GLIDE_PERIOD, 2) - 6.0)
        flight_body(pose, bob=0.01 * wave(t, GLIDE_PERIOD, 2), tail=3.0 * wave(t, GLIDE_PERIOD, 3),
                    tail_yaw=5.0 * wave(t, GLIDE_PERIOD, 1, 0.3), look=look)
        for side, ph in (("L", 0.0), ("R", 0.5)):
            flight_wing(pose, side, elevation=1.5 * wave(t, GLIDE_PERIOD, 2, ph),
                        sweep=2.0 * wave(t, GLIDE_PERIOD, 3, ph), bend=2.5 * wave(t, GLIDE_PERIOD, 4, ph))
        pose.key(arm, f, names)
    _finish(arm)
    print(f"glide: {frames} frames")


def bake_flap(arm, pose):
    """u = 0 is the middle of the upstroke: the wings rise to the top at u = 0.25, beat down through
    the glide at u = 0.5 to the bottom at u = 0.75 and come back up."""
    _start(arm, "Flap")
    frames = int(round(FLAP_PERIOD * FPS))
    names = animated(arm)
    up_mid = (FLAP_UP - FLAP_DOWN) * 0.5
    up_amp = (FLAP_UP + FLAP_DOWN) * 0.5
    for f in range(frames + 1):
        u = f / frames
        c, s = math.cos(2 * math.pi * u), math.sin(2 * math.pi * u)
        tuck = ((1 + c) * 0.5) ** 2  # the hand folds in on the upstroke
        pose.reset()
        flight_body(pose, bob=-0.035 * s, tail=4.0 * math.sin(2 * math.pi * (u - 0.15)))
        for side in "LR":
            flight_wing(pose, side, elevation=up_mid * (1 - c) + up_amp * s - up_mid,
                        sweep=-30.0 * tuck, bend=-16.0 * c, twist=-8.0 * c)
        pose.key(arm, f, names)
    _finish(arm)
    print(f"flap: {frames} frames")


# ---------------------------------------------------------------- preview

def render_preview(arm, out_dir):
    """The glide pose from all round, then both clips from above and behind."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"  # clay: the textures are nearly black
    sc.display.shading.single_color = (0.75, 0.72, 0.68)
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    sc.render.image_settings.file_format = "PNG"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 6.0
    centre = Vector((0, 0, 1.3))

    def shoot(path, d):
        cam.location = centre + Vector(d).normalized() * 12
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)

    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions["Glide"]
    sc.frame_set(0)
    for name, d in (("front", (0, -1, 0.15)), ("side", (1, 0, 0.1)), ("top", (0, 0.001, 1)),
                    ("below", (0, 0.001, -1)), ("persp", (0.8, -0.9, 0.7))):
        shoot(os.path.join(out_dir, "pose_%s.png" % name), d)
    for clip, period, step in (("Flap", FLAP_PERIOD, 1), ("Glide", GLIDE_PERIOD, 6)):
        arm.animation_data.action = bpy.data.actions[clip]
        for k in range(0, int(round(period * FPS)), step):
            sc.frame_set(k)
            shoot(os.path.join(out_dir, "%s_%04d.png" % (clip.lower(), k)), (0.5, 1.0, 0.45))
    arm.animation_data.action = None


# ---------------------------------------------------------------- main

def main():
    args = parse_args()
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from process_rigged_humanoid import shrink_textures

    arm, mesh = load(args.input)
    bpy.context.scene.render.fps = FPS
    shrink_textures(args.tex, args.orm_tex)
    build_wings(arm, mesh)
    scale = fit(arm, mesh)
    pose = Pose(arm)
    bake_glide(arm, pose)
    bake_flap(arm, pose)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    print(f"exported {args.output}: scale {scale:.3f}, {len(arm.data.bones)} bones, "
          f"clips {[a.name for a in bpy.data.actions]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        render_preview(arm, args.preview)


if __name__ == "__main__":
    main()
