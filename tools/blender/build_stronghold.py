"""Procedural brutalist stronghold, built from the side-view schematic (Note 17 Oct 2026).

Run headless:
  blender -b --python tools/blender/build_stronghold.py -- \
      --output game/assets/stronghold/stronghold.glb [--preview /path/to/renders_dir]
  (or: python3 tools/blender/build_stronghold.py -- ... with the `bpy` pip package)

The profile is traced from the sketch in pixel coordinates (PX_SCALE meters per pixel) and
extruded along the ridge into MODULES bays, one hot-air vent / roof hatch (exit A) /
gun-deck door (exit B) per bay, and a ground tunnel (exit C) in the bays listed in C_BAYS.
Interior (ramps, stair shafts, spawn hall) is carved with booleans and is walkable.

Axes: length along Blender X, front (downhill, -Y) to cliff (+Y), Z up. Exported as glTF
(+Y up, front +Z). Empties mark exits, spawn and weapon mounts for the game to hook into:
  EXIT_A_n, EXIT_B_n, EXIT_C_n, SPAWN_n, MOUNT_AA_n_k (roof), MOUNT_GUN_n_k (gun deck),
  VENT_FX_n (hot air plume origin). Placeholder weapons sit on every mount.
"""
import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

PX_SCALE = 0.035          # meters per sketch pixel
PX_ORIGIN = (280.0, 770.0)  # sketch pixel of (front, ground)
MODULES = 5
BAY = 12.0                # bay length (m)
END_CHAMFER = 6.0         # how much longer the front is than the back at each end
C_BAYS = (0, 2, 4)        # bays with a ground tunnel exit
SHAFT_LEN = 5.0           # stair shaft length along the ridge
RAMP_W = 4.0              # corridor width along the ridge
DOOR_W = 1.4
HATCH_LEN = 1.8


def P(px, py):
    """Sketch pixel -> (depth, height) in meters."""
    return ((px - PX_ORIGIN[0]) * PX_SCALE, (PX_ORIGIN[1] - py) * PX_SCALE)


# --- profile (sketch pixels) ---
BODY = [(350, 770), (275, 670), (370, 680), (450, 540), (615, 540), (615, 425),
        (485, 340), (694, 340), (1000, 762)]
SLAB = [(640, 95), (1078, 762), (1000, 762), (633, 262)]
RAMP_C = [(240, 772), (465, 772), (690, 540), (615, 548), (370, 690), (240, 690)]
RAMP_NO_C = [(380, 772), (465, 772), (690, 540), (615, 548), (380, 690)]
BRANCH = [(570, 660), (630, 610), (755, 705), (710, 772)]
SPAWN_HALL = [(720, 772), (850, 600), (960, 772)]
SHAFT = [(628, 368), (690, 368), (690, 548), (628, 548)]
DOOR_B = [(600, 482), (640, 482), (640, 541), (600, 541)]
HATCH = [(630, 320), (656, 320), (656, 372), (630, 372)]
VENT = [(585, 262), (670, 262), (670, 300), (585, 300)]  # hood cantilevered off the slab, over the hatch
DECK_Z = P(0, 540)[1]
ROOF_Z = P(0, 340)[1]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="", help="directory for preview renders")
    return p.parse_args(argv)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, rough=0.9, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def prism(name, poly_px, x0, x1, material=None, px=True):
    """Extrude a 2D (depth, height) polygon along X from x0 to x1."""
    pts = [P(*p) for p in poly_px] if px else poly_px
    bm = bmesh.new()
    a = [bm.verts.new((x0, d, z)) for d, z in pts]
    b = [bm.verts.new((x1, d, z)) for d, z in pts]
    bm.faces.new(a)
    bm.faces.new(b)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    return ob


def box(name, center, size, material=None):
    ob = prism(name, [(center[1] - size[1] / 2, center[2] - size[2] / 2),
                      (center[1] + size[1] / 2, center[2] - size[2] / 2),
                      (center[1] + size[1] / 2, center[2] + size[2] / 2),
                      (center[1] - size[1] / 2, center[2] + size[2] / 2)],
               center[0] - size[0] / 2, center[0] + size[0] / 2, material, px=False)
    return ob


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def boolean(target, cutter, op="DIFFERENCE"):
    m = target.modifiers.new("bool", "BOOLEAN")
    m.operation = op
    m.solver = "EXACT"
    m.object = cutter
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def bay_center(i):
    return (i - (MODULES - 1) / 2) * BAY


def empty(name, loc, parent, size=0.5):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    e.location = loc
    bpy.context.collection.objects.link(e)
    e.parent = parent
    return e


def end_cutters(total_len, depth_max):
    """Two huge boxes that trim the ends so the front is longer than the back."""
    cutters = []
    for side in (-1, 1):
        n = Vector((side * depth_max, END_CHAMFER, 0)).normalized()
        on_plane = Vector((side * (total_len / 2 + END_CHAMFER), 0, 0))
        c = box("endcut", (0, 0, 0), (60, 300, 300))
        c.rotation_euler.z = math.atan2(n.y, n.x)
        c.location = on_plane + n * 30
        bpy.context.view_layer.update()
        cutters.append(c)
    return cutters


def stairs(cx, material):
    """Switchback stair in a shaft centred at x = cx: two flights side by side in depth."""
    d0, z_top = P(628, 368)
    d1, z_bot = P(690, 548)
    half = (d1 - d0) / 2
    rise_total = (z_top - 0.2) - z_bot
    landing = 0.9
    run = SHAFT_LEN - 2 * landing
    steps_per = 14
    h = rise_total / (2 * steps_per)
    t = run / steps_per
    x_start = cx - SHAFT_LEN / 2 + landing
    parts = []
    # flight 1: back half (cliff side), climbing +X
    for k in range(steps_per):
        top = z_bot + h * (k + 1)
        parts.append(box("step", (x_start + t * (k + 0.5), d0 + half * 1.5, (z_bot + top) / 2),
                         (t, half, top - z_bot)))
    mid_z = z_bot + h * steps_per
    parts.append(box("landing", (cx + SHAFT_LEN / 2 - landing / 2, (d0 + d1) / 2, (z_bot + mid_z) / 2),
                     (landing, d1 - d0, mid_z - z_bot)))
    # flight 2: front half, climbing -X, built on a sloped stringer block
    for k in range(steps_per):
        top = mid_z + h * (k + 1)
        x = cx + SHAFT_LEN / 2 - landing - t * (k + 0.5)
        parts.append(box("step", (x, d0 + half * 0.5, (z_bot + top) / 2), (t, half, top - z_bot)))
    top_landing_z = mid_z + h * steps_per
    parts.append(box("landing", (cx - SHAFT_LEN / 2 + landing / 2, d0 + half * 0.5,
                                 (z_bot + top_landing_z) / 2), (landing, half, top_landing_z - z_bot)))
    ob = join(parts, "Stairs")
    ob.data.materials.clear()
    ob.data.materials.append(material)
    return ob, top_landing_z


def placeholder_aa(name, loc, m_metal):
    base = box(name, (loc[0], loc[1], loc[2] + 0.35), (1.6, 1.6, 0.7), m_metal)
    turret = box("t", (loc[0], loc[1], loc[2] + 1.1), (1.2, 1.0, 0.8), m_metal)
    b1 = box("b", (loc[0] - 0.25, loc[1] - 1.2, loc[2] + 1.6), (0.15, 2.2, 0.15), m_metal)
    b2 = box("b", (loc[0] + 0.25, loc[1] - 1.2, loc[2] + 1.6), (0.15, 2.2, 0.15), m_metal)
    for b in (b1, b2):
        b.rotation_euler.x = math.radians(-35)
    return join([base, turret, b1, b2], name)


def placeholder_gun(name, loc, m_metal):
    base = box(name, (loc[0], loc[1], loc[2] + 0.5), (1.4, 1.4, 1.0), m_metal)
    shield = box("s", (loc[0], loc[1] - 0.8, loc[2] + 1.1), (1.6, 0.15, 1.0), m_metal)
    barrel = box("b", (loc[0], loc[1] - 2.0, loc[2] + 1.2), (0.25, 2.6, 0.25), m_metal)
    return join([base, shield, barrel], name)


def build():
    m_conc = mat("Concrete", (0.46, 0.45, 0.43), 0.95)
    m_dark = mat("ConcreteDark", (0.25, 0.25, 0.25), 0.95)
    m_metal = mat("Metal", (0.18, 0.19, 0.2), 0.5, 0.8)
    m_hatch = mat("HatchOrange", (0.8, 0.35, 0.08), 0.6, 0.3)
    m_rock = mat("Rock", (0.3, 0.28, 0.25), 1.0)

    total = MODULES * BAY
    root = bpy.data.objects.new("Stronghold", None)
    bpy.context.collection.objects.link(root)

    body = prism("Body", BODY, -total / 2 - END_CHAMFER - 2, total / 2 + END_CHAMFER + 2, m_conc)
    slab = prism("Slab", SLAB, -total / 2 - END_CHAMFER - 2, total / 2 + END_CHAMFER + 2, m_dark)
    depth_max = P(1078, 0)[0]
    for ob in (body, slab):
        for c in end_cutters(total, depth_max):
            boolean(ob, c)

    # spawn hall runs along the whole ridge
    boolean(body, prism("hall", SPAWN_HALL, -total / 2 + 1.0, total / 2 - 1.0))

    stair_objs = []
    for i in range(MODULES):
        cx = bay_center(i)
        ramp = RAMP_C if i in C_BAYS else RAMP_NO_C
        boolean(body, prism("ramp", ramp, cx - RAMP_W / 2, cx + RAMP_W / 2))
        boolean(body, prism("branch", BRANCH, cx - RAMP_W / 2, cx + RAMP_W / 2))
        boolean(body, prism("shaft", SHAFT, cx - SHAFT_LEN / 2, cx + SHAFT_LEN / 2))
        boolean(body, prism("door", DOOR_B, cx - SHAFT_LEN / 2 + 0.3, cx - SHAFT_LEN / 2 + 0.3 + DOOR_W))
        boolean(body, prism("hatch", HATCH, cx - SHAFT_LEN / 2 + 0.2, cx - SHAFT_LEN / 2 + 0.2 + HATCH_LEN))
        st, _ = stairs(cx, m_conc)
        st.name = f"Stairs_{i + 1}"
        stair_objs.append(st)

    # brutalist dressing: bevels so edges catch light
    for ob in [body, slab] + stair_objs:
        bv = ob.modifiers.new("bevel", "BEVEL")
        bv.width = 0.06
        bv.segments = 1
        bv.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=bv.name)
        ob.parent = root

    # vents (hood on two fins above the hatch), hatch lids, rooftop parapet, gun-deck parapet
    for i in range(MODULES):
        cx = bay_center(i)
        hood = prism(f"Vent_{i + 1}", VENT, cx - 2.2, cx + 2.2, m_dark)
        d0, _ = P(585, 0)
        d1, _ = P(670, 0)
        fins = []
        for s in (-1, 1):
            fins.append(box("fin", (cx + s * 2.0, (d0 + d1) / 2 + 0.6, (ROOF_Z + P(0, 300)[1]) / 2),
                            (0.4, d1 - d0 - 1.2, P(0, 300)[1] - ROOF_Z), m_dark))
        grille = [box("grille", (cx - 1.8 + 0.45 * k, (d0 + d1) / 2, P(0, 262)[1] + 0.15),
                      (0.12, d1 - d0 - 0.4, 0.3), m_metal) for k in range(9)]
        vent = join([hood] + fins + grille, f"Vent_{i + 1}")
        vent.parent = root
        hd0, hz = P(630, 340)
        hd1, _ = P(656, 340)
        hx = cx - SHAFT_LEN / 2 + 0.2 + HATCH_LEN / 2
        lid = box(f"HatchLid_{i + 1}", (hx, (hd0 + hd1) / 2 - 0.6, hz + 0.05), (HATCH_LEN, 0.1, 0.9), m_hatch)
        lid.parent = root
        dx = cx - SHAFT_LEN / 2 + 0.3 + DOOR_W / 2
        door = box(f"DoorFrame_{i + 1}", (dx, P(615, 0)[0] - 0.05, DECK_Z + 2.15), (DOOR_W + 0.4, 0.15, 0.25), m_hatch)
        door.parent = root

    # parapets
    fr, _ = P(485, 340)
    back, _ = P(694, 340)
    para_r = box("RoofParapet", (0, fr + 0.25, ROOF_Z + 0.5), (total - 2, 0.5, 1.0), m_conc)
    gd, _ = P(450, 540)
    para_g = box("DeckParapet", (0, gd + 0.25, DECK_Z + 0.55), (total - 2, 0.5, 1.1), m_conc)
    for ob in (para_r, para_g):
        ob.parent = root

    # cliff behind the slab (separate mesh): a noisy sheet parallel to the slab's back face
    import random
    random.seed(7)
    foot = Vector(P(1078, 762))
    up = (Vector(P(640, 95)) - foot).normalized()
    into = Vector((up.y, -up.x))
    bm = bmesh.new()
    nu, nx = 24, 60
    grid = []
    for iu in range(nu + 1):
        row = []
        for ix in range(nx + 1):
            x = -(total / 2 + 30) + (total + 60) * ix / nx
            u = 40.0 * iu / nu
            off = 0.4 + (random.uniform(0, 1.2) if 0 < iu else 0)
            d, z = foot + up * u + into * off
            row.append(bm.verts.new((x, d, max(z, 0.0))))
        grid.append(row)
    for iu in range(nu):
        for ix in range(nx):
            bm.faces.new((grid[iu][ix], grid[iu][ix + 1], grid[iu + 1][ix + 1], grid[iu + 1][ix]))
    me = bpy.data.meshes.new("Cliff")
    bm.to_mesh(me)
    bm.free()
    cliff = bpy.data.objects.new("Cliff", me)
    bpy.context.collection.objects.link(cliff)
    me.materials.append(m_rock)
    cliff.parent = root

    # markers + placeholder weapons
    for i in range(MODULES):
        cx = bay_center(i)
        e = empty(f"EXIT_A_{i + 1}", (cx - SHAFT_LEN / 2 + 0.2 + HATCH_LEN / 2, P(643, 0)[0], ROOF_Z), root)
        empty(f"EXIT_B_{i + 1}", (cx - SHAFT_LEN / 2 + 0.3 + DOOR_W / 2, P(605, 0)[0], DECK_Z), root)
        if i in C_BAYS:
            empty(f"EXIT_C_{i + 1}", (cx, P(300, 0)[0], 0.0), root)
        empty(f"SPAWN_{i + 1}", (cx, P(850, 0)[0], 0.0), root)
        empty(f"VENT_FX_{i + 1}", (cx, P(678, 0)[0], P(0, 262)[1] + 0.3), root)
        for k, off in enumerate((-3.5, 3.5)):
            loc = (cx + off, P(540, 0)[0], ROOF_Z)
            empty(f"MOUNT_AA_{i + 1}_{k + 1}", loc, root)
            placeholder_aa(f"PH_AA_{i + 1}_{k + 1}", loc, m_metal).parent = root
        for k, off in enumerate((-3.0, 3.0)):
            loc = (cx + off, P(500, 0)[0], DECK_Z)
            empty(f"MOUNT_GUN_{i + 1}_{k + 1}", loc, root)
            placeholder_gun(f"PH_GUN_{i + 1}_{k + 1}", loc, m_metal).parent = root

    for ob in bpy.data.objects:
        if ob.type == "MESH":
            for p in ob.data.polygons:
                p.use_smooth = False
    return root


def export(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_apply=True, export_extras=True)


def preview(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.7, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    sc.collection.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, -0.01))
    ground = bpy.context.active_object
    ground.data.materials.append(mat("Ground", (0.32, 0.3, 0.26)))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    shots = {
        "three_quarter": ((-55, -60, 30), (0, 10, 8)),
        "section": ((-60, 14, 12), (0, 14, 12)),
        "front": ((0, -75, 14), (0, 10, 10)),
        "deck_close": ((-14, -10, 12), (-6, 8, 10)),
        "roof_close": ((-20, -6, 24), (-10, 12, 15)),
    }
    for name, (loc, target) in shots.items():
        cam.location = loc
        d = Vector(target) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 28
        sc.render.filepath = os.path.join(out_dir, f"{name}.png")
        # section view: cut away everything before the middle of bay 1 (it has a C tunnel)
        cut = None
        if name == "section":
            x0 = bay_center(0)
            cut = box("section_cut", (x0 - 100, 0, 0), (200, 400, 400))
            cut.hide_render = True
            for ob in sc.objects:
                if ob.type == "MESH" and ob is not cut and ob.name != "Plane":
                    m = ob.modifiers.new("section", "BOOLEAN")
                    m.object = cut
                    m.solver = "EXACT"
        bpy.ops.render.render(write_still=True)
        if cut:
            for ob in sc.objects:
                if "section" in ob.modifiers:
                    ob.modifiers.remove(ob.modifiers["section"])
            bpy.data.objects.remove(cut, do_unlink=True)


def main():
    args = parse_args()
    reset()
    build()
    export(args.output)
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
