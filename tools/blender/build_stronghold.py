"""Procedural brutalist stronghold, built from the side-view schematic (Note 17 Oct 2026).

Run headless:
  blender -b --python tools/blender/build_stronghold.py -- \
      --output game/assets/stronghold/stronghold.glb [--preview /path/to/renders_dir]
  (or: python3 tools/blender/build_stronghold.py -- ... with the `bpy` pip package)

The profile is traced from the sketch in pixel coordinates (PX_SCALE meters per pixel) and
extruded along the ridge into MODULES bays, one hot-air vent / roof hatch (exit A) /
gun-deck door (exit B) per bay, and a ground tunnel (exit C) in the bays listed in C_BAYS.
Interior is carved with booleans and is walkable: tunnel C runs in at ground level and turns
onto a ramp along the ridge up to the junction; from the junction a ramp runs back down into
the spawn hall and a switchback stair climbs to the gun-deck landing (door B) and a top
landing, where a ladder goes up through roof hatch A.

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

# Interior, in meters. x is relative to the bay centre, d is depth from the front.
HEADROOM = 3.0
TUNNEL_X = (-5.5, -2.5)   # exit C tunnel, straight in from the front portal
TUNNEL_D = (-2.0, 8.6)
TUNNEL_H = 2.8
RAMP_D = (8.5, 11.5)      # ramp runs along the ridge from the tunnel up to the junction
RAMP_FLAT_TO = -2.5       # ramp floor is flat up to here, then climbs
JUNCTION_X = (3.5, 5.5)   # "ramp intersection": tunnel ramp, spawn ramp and stair foot meet here
JUNCTION_Z = 2.8
SHAFT_X = (-1.8, 5.5)     # switchback stair shaft behind the gun deck
SHAFT_D = (12.2, 14.9)
SPAWN_RAMP_END_D = 20.5   # spawn ramp runs back and down into the spawn hall
RISER = 0.175
TREAD = 0.3
DOOR_X = (4.1, 5.5)       # exit B, from the deck-level stair landing onto the gun deck
DOOR_H = 2.2
HATCH_X = (4.0, 5.5)      # exit A, over the top landing; a ladder climbs through it
HATCH_D = (12.2, 13.4)


def P(px, py):
    """Sketch pixel -> (depth, height) in meters."""
    return ((px - PX_ORIGIN[0]) * PX_SCALE, (PX_ORIGIN[1] - py) * PX_SCALE)


# --- profile (sketch pixels) ---
BODY = [(350, 770), (275, 670), (370, 680), (450, 540), (615, 540), (615, 425),
        (485, 340), (694, 340), (1000, 762)]
SLAB = [(640, 95), (1078, 762), (1000, 762), (633, 262)]
SPAWN_HALL = [(720, 772), (850, 600), (960, 772)]
VENT = [(585, 230), (670, 230), (670, 262), (585, 262)]  # hood cantilevered off the slab, ~2.7 m over the hatch
DECK_Z = P(0, 540)[1]
ROOF_Z = P(0, 340)[1]
SHAFT_TOP = ROOF_Z - 1.0  # underside of the roof slab
TOP_LANDING_Z = SHAFT_TOP - 2.17


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
    m.diffuse_color = (*color, 1.0)  # viewport / Workbench color
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


def prism_d(name, poly_xz, d0, d1, cx=0.0, material=None):
    """Extrude a 2D (x, height) polygon along depth from d0 to d1, offset by cx along the ridge."""
    ob = prism(name, [(x, z) for x, z in poly_xz], d0, d1, material, px=False)
    # prism() extrudes along X with points in (y, z); swap so the polygon lies in X/Z
    for v in ob.data.vertices:
        v.co.x, v.co.y = v.co.y + cx, v.co.x
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
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


def flight(parts, cx, x_from, x_to, band, z_from, steps):
    """Steps climbing from x_from toward x_to within a depth band, starting on floor z_from."""
    sgn = 1 if x_to > x_from else -1
    for k in range(steps):
        top = z_from + RISER * (k + 1)
        xc = cx + x_from + sgn * TREAD * (k + 0.5)
        parts.append(box("step", (xc, (band[0] + band[1]) / 2, top - 0.25), (TREAD, band[1] - band[0], 0.5)))
    return z_from + RISER * steps


def landing(parts, cx, xs, ds, top):
    parts.append(box("landing", (cx + (xs[0] + xs[1]) / 2, (ds[0] + ds[1]) / 2, top - 0.15),
                     (xs[1] - xs[0], ds[1] - ds[0], 0.3)))


def stairs(cx, m_conc, m_metal):
    """Switchback stair: junction (2.8) -> gun-deck landing (8.05) -> top landing, then a ladder."""
    d0, d1 = SHAFT_D
    dm = (d0 + d1) / 2
    front, back = (d0, dm), (dm, d1)
    east = (DOOR_X[0], SHAFT_X[1])
    lower_steps = round((DECK_Z - JUNCTION_Z) / 2 / RISER)
    upper_steps = round((TOP_LANDING_Z - DECK_Z) / 2 / RISER)
    parts = []
    z = flight(parts, cx, east[0], -1, front, JUNCTION_Z, lower_steps)
    west1 = (SHAFT_X[0], east[0] - lower_steps * TREAD)
    landing(parts, cx, west1, SHAFT_D, z)
    z = flight(parts, cx, west1[1], 1, back, z, lower_steps)
    landing(parts, cx, east, SHAFT_D, z)
    z = flight(parts, cx, east[0], -1, front, z, upper_steps)
    west2 = (east[0] - upper_steps * TREAD - 1.4, east[0] - upper_steps * TREAD)
    landing(parts, cx, west2, SHAFT_D, z)
    z = flight(parts, cx, west2[1], 1, back, z, upper_steps)
    landing(parts, cx, east, SHAFT_D, z)
    ob = join(parts, "Stairs")
    ob.data.materials.clear()
    ob.data.materials.append(m_conc)

    # ladder up through the roof hatch, against the front wall of the shaft
    lx = cx + (HATCH_X[0] + HATCH_X[1]) / 2
    rails = [box("rail", (lx + s * 0.35, d0 + 0.08, (z + ROOF_Z + 1.0) / 2), (0.06, 0.06, ROOF_Z + 1.0 - z), m_metal)
             for s in (-1, 1)]
    rungs = [box("rung", (lx, d0 + 0.1, z + 0.3 * (k + 1)), (0.7, 0.05, 0.05), m_metal)
             for k in range(int((ROOF_Z - z) / 0.3))]
    ladder = join(rails + rungs, "Ladder")
    return ob, ladder, z


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
    ladders = []
    spawn_ramps = []
    jx0, jx1 = JUNCTION_X
    for i in range(MODULES):
        cx = bay_center(i)
        if i in C_BAYS:
            boolean(body, box("tunnel", (cx + sum(TUNNEL_X) / 2, sum(TUNNEL_D) / 2, TUNNEL_H / 2),
                              (TUNNEL_X[1] - TUNNEL_X[0], TUNNEL_D[1] - TUNNEL_D[0], TUNNEL_H)))
            ramp = [(TUNNEL_X[0], 0.0), (RAMP_FLAT_TO, 0.0), (jx0, JUNCTION_Z),
                    (jx0, JUNCTION_Z + HEADROOM), (RAMP_FLAT_TO, HEADROOM), (TUNNEL_X[0], HEADROOM)]
            boolean(body, prism_d("ramp", ramp, *RAMP_D, cx=cx))
            junction_d0 = RAMP_D[0]
        else:
            junction_d0 = RAMP_D[1]
        boolean(body, box("junction", (cx + (jx0 + jx1) / 2, (junction_d0 + SHAFT_D[1]) / 2, JUNCTION_Z + HEADROOM / 2),
                          (jx1 - jx0, SHAFT_D[1] - junction_d0, HEADROOM)))
        boolean(body, box("shaft", (cx + sum(SHAFT_X) / 2, sum(SHAFT_D) / 2, (JUNCTION_Z + SHAFT_TOP) / 2),
                          (SHAFT_X[1] - SHAFT_X[0], SHAFT_D[1] - SHAFT_D[0], SHAFT_TOP - JUNCTION_Z)))
        # spawn ramp: corridor back and down from the junction into the spawn hall
        spawn = [(SHAFT_D[1] - 0.4, JUNCTION_Z), (SHAFT_D[1], JUNCTION_Z), (SPAWN_RAMP_END_D, 0.0),
                 (SPAWN_RAMP_END_D, 4.0), (SHAFT_D[1], JUNCTION_Z + HEADROOM), (SHAFT_D[1] - 0.4, JUNCTION_Z + HEADROOM)]
        boolean(body, prism("spawn_corridor", spawn, cx + jx0, cx + jx1, px=False))
        wedge = prism(f"SpawnRamp_{i + 1}", [(SHAFT_D[1] - 0.4, JUNCTION_Z), (SHAFT_D[1] - 0.4, 0.0),
                                             (SPAWN_RAMP_END_D, 0.0)], cx + jx0, cx + jx1, m_conc, px=False)
        spawn_ramps.append(wedge)
        boolean(body, box("door", (cx + sum(DOOR_X) / 2, (P(615, 0)[0] + SHAFT_D[0]) / 2, DECK_Z + DOOR_H / 2),
                          (DOOR_X[1] - DOOR_X[0], SHAFT_D[0] - P(615, 0)[0] + 0.4, DOOR_H)))
        boolean(body, box("hatch", (cx + sum(HATCH_X) / 2, sum(HATCH_D) / 2, ROOF_Z),
                          (HATCH_X[1] - HATCH_X[0], HATCH_D[1] - HATCH_D[0], 2.4)))
        st, lad, _ = stairs(cx, m_conc, m_metal)
        st.name = f"Stairs_{i + 1}"
        lad.name = f"Ladder_{i + 1}"
        stair_objs.append(st)
        ladders.append(lad)

    # brutalist dressing: bevels so edges catch light
    for ob in ladders:
        ob.parent = root
    for ob in [body, slab] + stair_objs + spawn_ramps:
        bv = ob.modifiers.new("bevel", "BEVEL")
        bv.width = 0.06
        bv.segments = 1
        bv.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=bv.name)
        ob.parent = root

    # vents (hood on two fins, cantilevered off the slab over hatch A), open hatch lids, door B lintels
    for i in range(MODULES):
        cx = bay_center(i)
        vx = cx + sum(HATCH_X) / 2
        hood = prism(f"Vent_{i + 1}", VENT, vx - 1.8, vx + 1.8, m_dark)
        d0, _ = P(585, 0)
        d1, _ = P(670, 0)
        fins = []
        for s in (-1, 1):
            fins.append(box("fin", (vx + s * 1.6, (d0 + d1) / 2 + 0.6, (ROOF_Z + P(0, 262)[1]) / 2),
                            (0.4, d1 - d0 - 1.2, P(0, 262)[1] - ROOF_Z), m_dark))
        grille = [box("grille", (vx - 1.4 + 0.4 * k, (d0 + d1) / 2, P(0, 230)[1] + 0.15),
                      (0.12, d1 - d0 - 0.4, 0.3), m_metal) for k in range(8)]
        vent = join([hood] + fins + grille, f"Vent_{i + 1}")
        vent.parent = root
        lid = box(f"HatchLid_{i + 1}", (vx, HATCH_D[1] + 0.05, ROOF_Z + 0.6),
                  (HATCH_X[1] - HATCH_X[0], 0.1, 1.2), m_hatch)
        lid.parent = root
        door = box(f"DoorFrame_{i + 1}", (cx + sum(DOOR_X) / 2, P(615, 0)[0] - 0.05, DECK_Z + DOOR_H + 0.12),
                   (DOOR_X[1] - DOOR_X[0] + 0.4, 0.15, 0.25), m_hatch)
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
        empty(f"EXIT_A_{i + 1}", (cx + sum(HATCH_X) / 2, sum(HATCH_D) / 2, ROOF_Z), root)
        empty(f"EXIT_B_{i + 1}", (cx + sum(DOOR_X) / 2, P(615, 0)[0] - 0.6, DECK_Z), root)
        if i in C_BAYS:
            empty(f"EXIT_C_{i + 1}", (cx + sum(TUNNEL_X) / 2, -1.0, 0.0), root)
        empty(f"SPAWN_{i + 1}", (cx, P(850, 0)[0], 0.0), root)
        empty(f"VENT_FX_{i + 1}", (cx + sum(HATCH_X) / 2, P(628, 0)[0], P(0, 230)[1] + 0.3), root)
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
