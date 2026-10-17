"""Scale-check video of the stronghold: a first-person walk through bay 1 plus wide corner shots
of each room, with the defender models placed around it.

Run headless (renders with Workbench, so it works without a GPU):
  blender -b --python tools/blender/stronghold_walkthrough.py -- \
      --frames /tmp/walk_frames --video /tmp/stronghold_walkthrough.mp4 [--res 1280x720] [--every 1]
  (or: python3 tools/blender/stronghold_walkthrough.py -- ... with the `bpy` pip package)

The stronghold is rebuilt from build_stronghold.py, so the video always matches the script.
"""
import argparse
import math
import os
import subprocess
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_stronghold as B  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFENDERS = ["armored_sentinel", "harpy_vanguard", "crimson_warden",
             "grey_veil_warden", "heavy_gunner", "cyber_orc_sentinel"]
FPS = 24
EYE = 1.6         # camera height above the floor in first person
WALK = 2.0        # m/s
STAIR_WALK = 1.3  # m/s, horizontal speed on stairs
CLIMB = 0.9       # m/s up the ladder
FPS_LENS = 18     # ~90 degree horizontal FOV

# stair heights, derived the same way build_stronghold.stairs() does
LOWER = round((B.DECK_Z - B.JUNCTION_Z) / 2 / B.RISER)
UPPER = round((B.TOP_LANDING_Z - B.DECK_Z) / 2 / B.RISER)
Z_WL1 = B.JUNCTION_Z + LOWER * B.RISER
Z_EL2 = Z_WL1 + LOWER * B.RISER
Z_WL3 = Z_EL2 + UPPER * B.RISER
Z_TOP = Z_WL3 + UPPER * B.RISER
X_EAST = B.DOOR_X[0]
X_F1_END = X_EAST - LOWER * B.TREAD
X_F3_END = X_EAST - UPPER * B.TREAD
D_FRONT = (B.SHAFT_D[0] + (B.SHAFT_D[0] + B.SHAFT_D[1]) / 2) / 2
D_BACK = ((B.SHAFT_D[0] + B.SHAFT_D[1]) / 2 + B.SHAFT_D[1]) / 2


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--frames", required=True)
    p.add_argument("--video", required=True)
    p.add_argument("--res", default="1280x720")
    p.add_argument("--every", type=int, default=1, help="render every Nth frame (quick tests)")
    p.add_argument("--aa", default="5", help="Workbench anti-aliasing samples: OFF, FXAA, 5, 8, 11, 16, 32")
    p.add_argument("--no-shadows", action="store_true")
    p.add_argument("--start", type=int, default=0, help="first frame to render (default: all)")
    p.add_argument("--end", type=int, default=0, help="last frame to render (default: all)")
    return p.parse_args(argv)


def A(bay, x, d, z):
    return Vector((B.bay_center(bay) + x, d, z))


def ramp_floor(x):
    """Floor height of the tunnel ramp at bay-relative x."""
    t = (x - B.RAMP_FLAT_TO) / (B.JUNCTION_X[0] - B.RAMP_FLAT_TO)
    return B.JUNCTION_Z * min(max(t, 0.0), 1.0)


def f1_floor(x):
    return B.JUNCTION_Z + (X_EAST - x) / B.TREAD * B.RISER


def f2_floor(x):
    return Z_WL1 + (x - X_F1_END) / B.TREAD * B.RISER


def f3_floor(x):
    return Z_EL2 + (X_EAST - x) / B.TREAD * B.RISER


def heading(v):
    """Camera yaw that looks along the horizontal direction of v (0 = looking +Y)."""
    return math.atan2(-v.x, v.y)


# --- characters -------------------------------------------------------------------------------

def import_defenders():
    """Import each defender once into a hidden collection (Idle looping); returns name -> root."""
    lib = bpy.data.collections.new("DefenderLibrary")
    bpy.context.scene.collection.children.link(lib)
    layer = bpy.context.view_layer.layer_collection.children[lib.name]
    out = {}
    for name in DEFENDERS:
        coll = bpy.data.collections.new(name)
        lib.children.link(coll)
        bpy.context.view_layer.active_layer_collection = layer.children[coll.name]
        before = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "game/assets/defenders", name, name + ".glb"))
        new_actions = [a for a in bpy.data.actions if a not in before]
        for ob in list(coll.objects):
            if ob.name.startswith("Icosphere"):  # bone-shape widget the glTF importer adds
                bpy.data.objects.remove(ob, do_unlink=True)
        root = next(o for o in coll.objects if o.parent is None)
        idle = next((a for a in new_actions if "idle" in a.name.lower()), None)
        if root.animation_data:
            for t in root.animation_data.nla_tracks:
                t.mute = True
        if idle:
            ad = root.animation_data_create()
            ad.action = None
            strip = ad.nla_tracks.new().strips.new("idle", int(idle.frame_range[0]), idle)
            strip.repeat = 200
        out[name] = root
    layer.exclude = True
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection
    return out


def place(lib, name, loc, face):
    """Linked copy of a defender standing at loc, facing the horizontal direction `face`."""
    src = lib[name]
    mapping = {}

    def rec(o, parent):
        c = o.copy()
        bpy.context.scene.collection.objects.link(c)
        mapping[o] = c
        if parent:
            c.parent = parent
            c.matrix_parent_inverse = o.matrix_parent_inverse.copy()
        for ch in o.children:
            rec(ch, c)

    rec(src, None)
    for c in mapping.values():
        for m in c.modifiers:
            if m.type == "ARMATURE" and m.object in mapping:
                m.object = mapping[m.object]
    root = mapping[src]
    root.location = loc
    root.rotation_mode = "XYZ"
    root.rotation_euler = (0, 0, math.atan2(face[0], -face[1]))  # models face -Y
    return root


def populate(lib):
    W, X, D, F = (-1, 0), (1, 0), (0, 1), (0, -1)  # facing -x, +x, +d (cliff), -d (front)
    spots = [
        # bay 1: along the first-person route (kept clear of the camera path)
        ("armored_sentinel", A(0, -5.1, -3.0, 0), F),
        ("cyber_orc_sentinel", A(0, -2.0, -4.2, 0), (-1, -1)),
        ("grey_veil_warden", A(0, -3.0, 3.5, 0), F),
        ("cyber_orc_sentinel", A(0, 0.5, 11.0, ramp_floor(0.5)), X),
        ("armored_sentinel", A(0, 4.0, 9.0, B.JUNCTION_Z), W),
        ("harpy_vanguard", A(0, 2.0, 8.8, B.DECK_Z), F),
        ("crimson_warden", A(0, -2.0, 8.8, B.DECK_Z), F),
        ("heavy_gunner", A(0, 2.4, 10.6, B.ROOF_Z), F),
        ("grey_veil_warden", A(0, -4.6, 10.0, B.ROOF_Z), F),
        # bay 2: one on every flight and landing (cutaway shot)
        ("crimson_warden", A(1, 2.3, D_FRONT, f1_floor(2.3)), W),
        ("harpy_vanguard", A(1, -1.1, 13.5, Z_WL1), X),
        ("heavy_gunner", A(1, 1.6, D_BACK, f2_floor(1.6)), X),
        ("grey_veil_warden", A(1, 4.8, 14.3, Z_EL2), F),
        ("cyber_orc_sentinel", A(1, 2.6, D_FRONT, f3_floor(2.6)), W),
        ("armored_sentinel", A(1, 4.8, 14.3, Z_TOP), F),
        ("armored_sentinel", A(1, -4.6, 8.6, B.DECK_Z), F),
        ("harpy_vanguard", A(1, -4.6, 10.0, B.ROOF_Z), F),
        # bay 3: tunnel ramp (corner shot)
        ("heavy_gunner", A(2, -4.0, 6.5, 0), D),
        ("crimson_warden", A(2, 0.0, 10.8, ramp_floor(0.0)), X),
        ("harpy_vanguard", A(2, 2.0, 9.4, ramp_floor(2.0)), W),
        ("grey_veil_warden", A(2, 4.5, 11.0, B.JUNCTION_Z), W),
        # spawn hall line-up, all six side by side
    ] + [(n, Vector((-27.4 + 1.2 * k, 20.3, 0)), (-1, -1)) for k, n in enumerate(DEFENDERS)]
    for name, loc, face in spots:
        place(lib, name, loc, face)


# --- camera track -----------------------------------------------------------------------------

class Track:
    def __init__(self):
        self.frames = []  # dicts: pos, yaw, pitch, label, lens, shot

    def _add(self, pos, yaw, pitch, label, lens=FPS_LENS, shot="fps"):
        self.frames.append(dict(pos=pos.copy(), yaw=yaw, pitch=pitch, label=label, lens=lens, shot=shot))

    def walk(self, pts, label, speed=WALK, ahead=1.6, pitch_gain=0.6):
        segs = [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
        lens = [(b - a).length for a, b in segs]
        total = sum(lens)

        def at(s):
            for (a, b), l in zip(segs, lens):
                if s <= l:
                    return a.lerp(b, s / l) if l else a.copy()
                s -= l
            a, b = segs[-1]
            return b + (b - a).normalized() * s  # past the end: keep looking the same way

        n = max(1, round(total / speed * FPS))
        for k in range(1, n + 1):
            s = total * k / n
            p, q = at(s), at(s + ahead)
            v = q - p
            pitch = math.atan2(v.z, math.hypot(v.x, v.y)) * pitch_gain
            self._add(p + Vector((0, 0, EYE)), heading(v), pitch, label)

    def look(self, seconds, label, yaw=None, pitch=None, turn=None):
        """Turn in place: to an absolute yaw (shortest way round) or by a relative `turn`."""
        last = self.frames[-1]
        y0, p0 = last["yaw"], last["pitch"]
        y1 = y0
        if yaw is not None:
            y1 = y0 + (yaw - y0 + math.pi) % (2 * math.pi) - math.pi
        if turn is not None:
            y1 = y0 + turn
        p1 = p0 if pitch is None else pitch
        n = max(1, round(seconds * FPS))
        for k in range(1, n + 1):
            t = k / n
            t = t * t * (3 - 2 * t)
            self._add(last["pos"], y0 + (y1 - y0) * t, p0 + (p1 - p0) * t, label)

    def climb(self, z_feet, label, pitch=0.7):
        last = self.frames[-1]
        start = last["pos"].copy()
        end = Vector((start.x, start.y, z_feet + EYE))
        n = max(1, round((end.z - start.z) / CLIMB * FPS))
        for k in range(1, n + 1):
            self._add(start.lerp(end, k / n), last["yaw"], pitch, label)

    def static(self, loc, target, seconds, label, lens=16, shot="corner", dolly=0.8):
        loc, target = Vector(loc), Vector(target)
        fwd = (target - loc).normalized()
        n = round(seconds * FPS)
        for k in range(n):
            p = loc + fwd * dolly * (k / n)
            v = target - p
            self._add(p, heading(v), math.atan2(v.z, math.hypot(v.x, v.y)), label, lens, shot)


def smooth(frames, key, window=9):
    """Moving average of yaw/pitch inside each run of first-person frames (yaw unwrapped)."""
    vals = [f[key] for f in frames]
    if key == "yaw":
        for i in range(1, len(vals)):
            while vals[i] - vals[i - 1] > math.pi:
                vals[i] -= 2 * math.pi
            while vals[i] - vals[i - 1] < -math.pi:
                vals[i] += 2 * math.pi
    out = []
    for i, f in enumerate(frames):
        if f["shot"] != "fps":
            out.append(vals[i])
            continue
        lo, hi = max(0, i - window), min(len(frames), i + window + 1)
        js = [j for j in range(lo, hi) if frames[j]["shot"] == "fps"]
        out.append(sum(vals[j] for j in js) / len(js))
    for f, v in zip(frames, out):
        f[key] = v


def build_track():
    t = Track()
    W_ = math.pi / 2                     # looking -x
    FRONT, BACK = math.pi, 0.0           # looking out (-d), toward the cliff (+d)
    bay = 0
    tw = B.TUNNEL_X[1] - B.TUNNEL_X[0]
    t.static(A(bay, -13, -15, 4.5), A(bay, -2, 4, 4.5), 4.0,
             f"Exterior: defenders 1.65-1.71 m tall, tunnel C {tw:.1f} x {B.TUNNEL_H:.1f} m",
             lens=20, shot="exterior", dolly=2.0)
    fps = lambda s: f"FPS: {s}"
    t.frames.append(dict(pos=A(bay, -4.0, -14, EYE), yaw=BACK, pitch=0.0,
                         label=fps(f"eye height {EYE} m, approaching exit C"), lens=FPS_LENS, shot="fps"))
    t.walk([A(bay, -4.0, -14, 0), A(bay, -4.0, 9.2, 0), A(bay, -3.0, 10.0, 0), A(bay, B.RAMP_FLAT_TO, 10.0, 0)],
           fps(f"tunnel C, {tw:.1f} x {B.TUNNEL_H:.1f} m"))
    slope = math.degrees(math.atan2(B.JUNCTION_Z, B.JUNCTION_X[0] - B.RAMP_FLAT_TO))
    t.walk([A(bay, B.RAMP_FLAT_TO, 10.0, 0), A(bay, 3.5, 10.0, B.JUNCTION_Z), A(bay, 4.5, 10.6, B.JUNCTION_Z),
            A(bay, 4.8, 11.8, B.JUNCTION_Z), A(bay, 4.6, D_FRONT, B.JUNCTION_Z), A(bay, X_EAST, D_FRONT, B.JUNCTION_Z)],
           fps(f"ramp to junction, {slope:.0f} deg, {B.RAMP_D[1] - B.RAMP_D[0]:.1f} m wide"))
    sw = (B.SHAFT_D[1] - B.SHAFT_D[0]) / 2
    stair = fps(f"stairs, flights {sw:.2f} m wide, {B.RISER * 100:.1f} cm risers")
    t.walk([A(bay, X_EAST, D_FRONT, B.JUNCTION_Z), A(bay, X_F1_END, D_FRONT, Z_WL1), A(bay, -1.1, 13.1, Z_WL1),
            A(bay, -1.1, 14.0, Z_WL1), A(bay, X_F1_END, D_BACK, Z_WL1), A(bay, X_EAST, D_BACK, Z_EL2),
            A(bay, 4.8, 13.9, Z_EL2), A(bay, 4.8, 12.4, Z_EL2)], stair, speed=STAIR_WALK)
    dw = B.DOOR_X[1] - B.DOOR_X[0]
    t.walk([A(bay, 4.8, 12.4, Z_EL2), A(bay, 4.8, 10.4, Z_EL2)], fps(f"door B ({dw:.1f} x {B.DOOR_H:.1f} m) to the gun deck"))
    deck = fps("gun deck under the roof overhang")
    t.look(1.0, deck, yaw=FRONT, pitch=0.0)
    t.look(2.0, deck, yaw=W_ + 0.2)
    t.look(3.0, deck, turn=math.pi - 0.4)
    t.look(1.5, deck, yaw=BACK)
    t.walk([A(bay, 4.8, 10.4, Z_EL2), A(bay, 4.8, 12.4, Z_EL2), A(bay, 4.6, D_FRONT, Z_EL2), A(bay, X_EAST, D_FRONT, Z_EL2)],
           stair)
    t.walk([A(bay, X_EAST, D_FRONT, Z_EL2), A(bay, X_F3_END, D_FRONT, Z_WL3), A(bay, 0.1, 13.1, Z_WL3),
            A(bay, 0.1, 14.0, Z_WL3), A(bay, X_F3_END, D_BACK, Z_WL3), A(bay, X_EAST, D_BACK, Z_TOP),
            A(bay, 4.75, 13.9, Z_TOP), A(bay, 4.75, 12.7, Z_TOP)], stair, speed=STAIR_WALK)
    lad = fps(f"ladder up through hatch A ({B.ROOF_Z - Z_TOP:.1f} m)")
    t.look(1.2, lad, yaw=FRONT, pitch=0.9)
    t.climb(B.ROOF_Z, lad, pitch=0.75)
    roof = fps("rooftop, under the vent hood")
    t.look(0.8, roof, pitch=0.0)
    t.walk([A(bay, 4.75, 12.7, B.ROOF_Z), A(bay, 4.75, 10.4, B.ROOF_Z)], roof)
    t.look(2.0, roof, turn=-math.pi / 2 - 0.3)
    t.look(3.5, roof, turn=math.pi + 0.6)
    t.look(1.5, roof, turn=-math.pi / 2 + 0.3, pitch=0.25)

    sx = sum(B.SHAFT_X) / 2
    t.static(A(1, sx, 2.5, 8.8), A(1, sx, 13.6, 7.3), 5.5,
             f"Cutaway: bay 2 stair shaft ({B.SHAFT_X[1] - B.SHAFT_X[0]:.1f} x {B.SHAFT_D[1] - B.SHAFT_D[0]:.1f} m)",
             lens=16, shot="cutaway", dolly=1.0)
    t.static(A(2, -5.3, 8.65, 2.7), A(2, 3.5, 11.3, 2.0), 4.5, "Corner: tunnel ramp and junction, bay 3")
    t.static((-28.6, 17.7, 2.3), (-21.0, 20.6, 1.0), 4.5,
             "Corner: spawn hall, line-up of all six defenders")
    t.static((-32.5, 9.5, 10.0), (-10, 8.5, 8.6), 4.5, "Corner: gun deck")
    t.static((-32.4, 12.0, 17.0), (-12, 9.0, 15.0), 4.5, "Corner: rooftop (anti-air placeholders, vent hoods)")
    smooth(t.frames, "yaw")
    smooth(t.frames, "pitch")
    return t.frames


# --- scene ------------------------------------------------------------------------------------

def setup_render(res, aa="5", shadows=True):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.display.render_aa = aa
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_shadows = shadows
    sh.shadow_intensity = 0.35
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sc.display.light_direction = (0.45, -0.55, 0.7)
    world = bpy.data.worlds.new("w")
    world.color = (0.55, 0.62, 0.72)
    sc.world = world
    r = sc.render
    r.use_stamp = True
    for attr in dir(r):
        if attr.startswith("use_stamp_"):
            setattr(r, attr, False)
    r.use_stamp_marker = True
    r.stamp_font_size = 22
    r.stamp_background = (0, 0, 0, 0.6)
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, -0.005))
    ground = bpy.context.active_object
    ground.name = "Ground"
    ground.data.materials.append(B.mat("Ground", (0.36, 0.33, 0.27)))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.clip_start = 0.05
    cam.data.clip_end = 1000
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def setup_cutaway(stronghold):
    """Boolean that removes everything in front of the bay 2 stair shaft (render only in that shot)."""
    cx = B.bay_center(1)
    d_cut = B.SHAFT_D[0] + 0.05
    cut = B.box("cutaway", (cx + 1.85, (d_cut - 60) / 2, 15), (8.8, 60 + d_cut, 50))
    cut.hide_render = True
    cut.hide_viewport = True
    mods = []
    for ob in stronghold.children_recursive:
        if ob.type == "MESH" and ob is not cut:
            m = ob.modifiers.new("cutaway", "BOOLEAN")
            m.object = cut
            m.solver = "EXACT"
            mods.append(m)
    return mods


def keyframe(cam, frames, cut_mods):
    sc = bpy.context.scene
    label = None
    cut_on = None
    for i, fr in enumerate(frames):
        n = i + 1
        cam.location = fr["pos"]
        cam.rotation_euler = Euler((math.pi / 2 + fr["pitch"], 0, fr["yaw"]))
        cam.data.lens = fr["lens"]
        cam.keyframe_insert("location", frame=n)
        cam.keyframe_insert("rotation_euler", frame=n)
        cam.data.keyframe_insert("lens", frame=n)
        if fr["label"] != label:
            label = fr["label"]
            assert len(label) < 64, label  # marker names are capped at 63 characters
            sc.timeline_markers.new(label, frame=n)  # stamped on every frame until the next marker
        want_cut = fr["shot"] == "cutaway"
        if want_cut != cut_on:
            cut_on = want_cut
            for m in cut_mods:
                m.show_render = m.show_viewport = want_cut
                m.keyframe_insert("show_render", frame=n)
                m.keyframe_insert("show_viewport", frame=n)
    sc.frame_start, sc.frame_end = 1, len(frames)
    sc.render.fps = FPS


def main():
    args = parse_args()
    res = tuple(int(v) for v in args.res.split("x"))
    B.reset()
    stronghold = B.build()
    lib = import_defenders()
    populate(lib)
    cam = setup_render(res, args.aa, not args.no_shadows)
    cut_mods = setup_cutaway(stronghold)
    frames = build_track()
    keyframe(cam, frames, cut_mods)
    sc = bpy.context.scene
    if args.start:
        sc.frame_start = args.start
    if args.end:
        sc.frame_end = min(args.end, sc.frame_end)
    sc.frame_step = args.every
    os.makedirs(args.frames, exist_ok=True)
    for f in os.listdir(args.frames):
        if f.endswith(".png"):
            os.remove(os.path.join(args.frames, f))
    sc.render.filepath = os.path.join(args.frames, "")
    print(f"WALKTHROUGH {len(frames)} frames ({len(frames) / FPS:.1f} s), rendering {sc.frame_start}-{sc.frame_end}",
          flush=True)
    bpy.ops.render.render(animation=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(max(1, FPS // args.every)),
                    "-pattern_type", "glob", "-i", os.path.join(args.frames, "*.png"), "-c:v", "libx264",
                    "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", args.video], check=True)
    print("WALKTHROUGH wrote", args.video, flush=True)


if __name__ == "__main__":
    main()
