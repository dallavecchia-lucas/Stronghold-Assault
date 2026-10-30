class_name LevelBuilder
extends Node3D
## Builds the map: open field around the mountain stronghold (four bunker faces dug into
## one mountain, see tools/blender/build_stronghold.py), blast-door gates on three faces,
## the keep (reactor) in the core hall under the peak, defender posts on the gun decks and
## roofs and the Gunner Squad's in the south spawn hall, forests, attacker spawn points and the
## attackers' Forward Helipad Bases out by the lanes (AttackerBase: forward spawn points while they
## hold them).
## Everything static lives under the navigation region so it gets baked into the navmesh.
##
## Only infiltrators (UnitTypes) get inside. The gate tunnels stay plugged on the navmesh
## (LAYER_NAV_BLOCK) and a navigation link on NAV_INFILTRATORS opens through each gate once it
## falls; the Gunner Squad has links of its own through every gate (NAV_SQUAD). The stair shafts
## and ladders are too tight for the navmesh, so every bay has two more links: junction -> gun
## deck and gun deck -> roof. Each link carries the "route" its units climb along
## (AttackerUnit._follow_route).

signal navigation_ready

const MAP_HALF := 200.0
const STRONGHOLD := "res://assets/stronghold/stronghold.glb"
## stronghold.glb has face S's front at z = 0 and its core 78 m behind it; this puts the core
## at the map center.
const STRONGHOLD_OFFSET := Vector3(0, 0, 78)
## Map center to the foot of the rock below each face, and half the mountain's footprint.
const FACE_DIST := 80.0
const MOUNTAIN_HALF := 86.0
const GATE_HP := 1500.0
const KEEP_HP := 4000.0
## Blast door filling an exit C tunnel portal (between the concrete jambs, under the lintel).
const DOOR_SIZE := Vector3(3.0, 2.8, 0.4)
## Bay whose ground tunnel is the side's gate; every other tunnel is welded shut.
const GATE_BAY := 3

## Defender garrison models, one per rifle post (rigged, with Idle/Running clips; the Heavy Gunner
## walks instead of running).
const DEFENDER_MODELS := [
	"res://assets/defenders/armored_sentinel/armored_sentinel.glb",
	"res://assets/defenders/harpy_vanguard/harpy_vanguard.glb",
	"res://assets/defenders/crimson_warden/crimson_warden.glb",
	"res://assets/defenders/grey_veil_warden/grey_veil_warden.glb",
	"res://assets/defenders/heavy_gunner/heavy_gunner_rigged.glb",
	"res://assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel.glb",
]

## side name -> outward direction and the bunker face (stronghold.glb node suffix) on that side
const SIDES := {
	"south": {"dir": Vector3(0, 0, 1), "face": "S", "gate": true},
	"north": {"dir": Vector3(0, 0, -1), "face": "N", "gate": false},
	"east": {"dir": Vector3(1, 0, 0), "face": "E", "gate": true},
	"west": {"dir": Vector3(-1, 0, 0), "face": "W", "gate": true},
}
## Rifle posts on the gun decks: [side, bay].
const RIFLE_POSTS := [["south", 2], ["south", 4], ["east", 2], ["west", 4], ["north", 3], ["east", 4]]
const MORTAR_MOUNT := "MOUNT_AA_S3_1"
## Roof mounts that carry autonomous AA turrets (AATurret): two on every face, over bays 2 and 4.
const AA_TURRETS := ["S2_2", "S4_2", "E2_2", "E4_2", "W2_2", "W4_2", "N2_2", "N4_2"]
## Navigation layer bit for the links only infiltrators may take.
const NAV_INFILTRATORS := 2
## Navigation layer bit for the links through the gates the defenders' Gunner Squad takes, and how
## far out and in from the door they reach (the edges of the hole the plug leaves in the navmesh).
const NAV_SQUAD := 4
const SALLY_OUT := 1.5
const SALLY_IN := 1.3
## The Gunner Squad's post: in the south spawn hall, this far along it from SPAWN_S3 (toward the
## bay's spawn ramp, which it faces). Bought AA Squads deploy in the gate halls too (DefenderArmory).
const SQUAD_POST_OFFSET := Vector3(-3.0, 0.0, 0.15)
## Stair shaft and ladder in every bay, as [x along the bay, depth behind the front, floor height]
## (tools/blender/build_stronghold.py). DECK_ROUTE: junction -> switchback stair -> deck landing
## -> door B onto the gun deck. ROOF_ROUTE: gun deck -> door B -> upper flights -> top landing ->
## ladder through hatch A -> roof.
const DECK_ROUTE := [[4.8, 13.55, 2.8], [4.1, 12.875, 2.8], [-0.4, 12.875, 5.425], [-1.1, 13.55, 5.425],
		[-0.4, 14.225, 5.425], [4.1, 14.225, 8.05], [4.8, 13.2, 8.05], [4.8, 12.0, 8.05], [4.8, 10.9, 8.05]]
const ROOF_ROUTE := [[4.8, 10.9, 8.05], [4.8, 12.0, 8.05], [4.8, 13.2, 8.05], [4.1, 12.875, 8.05],
		[0.8, 12.875, 9.975], [0.1, 13.55, 9.975], [0.8, 14.225, 9.975], [4.1, 14.225, 11.9],
		[4.75, 12.7, 11.9], [4.75, 12.7, 15.05], [4.75, 11.0, 15.05]]
## Door B's marker (EXIT_B_*) in those coordinates.
const DOOR_B := Vector3(4.8, 11.125, 8.05)
## The roofs are clear of the rock only this far either side of a face's middle (CUT_HALF): the
## end bays' hatches open into the mountain.
const ROOF_EXPOSED_HALF := 27.0
## Forest groves as [center x, center z, radius]: off the attack lanes, dense with trees.
const FORESTS := [[42.0, 140.0, 16.0], [-44.0, 150.0, 18.0], [135.0, 125.0, 24.0], [-130.0, 120.0, 22.0],
		[145.0, -50.0, 20.0], [-140.0, -55.0, 20.0], [110.0, -140.0, 24.0], [-120.0, -135.0, 22.0]]
## The attackers' Forward Helipad Bases (AttackerBase), one by each attack lane: [side, centre x,
## centre z]. Each lies along its lane, its middle 54 m off it, clear of the forests and of the AA
## Squads' perimeter (AASquad.perimeter_spots); trees and rocks are kept off its lot (BASE_LOT_MARGIN
## round the deck).
const BASES := [["south", -54.0, 114.0], ["east", 118.0, 54.0], ["west", -118.0, 54.0]]
const BASE_LOT_MARGIN := 4.0
## Ground per tree in a grove (m²), and the closest two grove trees stand.
const FOREST_AREA_PER_TREE := 45.0
const FOREST_TREE_SPACING := 4.5
## Inside a grove, a spot is forest while a tree still stands this close to it (m): burnt down, the
## ground is open (ForestTree).
const FOREST_NEAR := 8.0
## Once a burnt tree has fallen the navmesh is rebaked without it, this long after the first of a
## run of them (s), so trees falling one after another make one rebake.
const REBAKE_DELAY := 6.0

var nav_region: NavigationRegion3D
var keep: Structure
var gates := {}  # side -> Structure
var stations := []  # possessable defender stations, in hotkey order
var aa_turrets := []  # autonomous, nobody takes them over
var spawn_points: Array[Vector3] = []
var spawn_names: Array[String] = []
## Per spawn point: the AttackerBase it belongs to (a forward helipad: open only while the attackers
## hold it), or null (the flags at the map's edge, always open).
var spawn_bases: Array = []
var bases: Array[AttackerBase] = []
var _stronghold: Node3D

var _baking := false
var _rebake_queued := false
var _first_bake_done := false
var _clearing := false


func build() -> void:
	_build_environment()
	nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_NAV_BLOCK
	# Fine cells and a slim agent so the 2 m passages inside the bunker stay walkable.
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	# Up to the bunker roofs; the mountain above is unreachable anyway.
	nm.filter_baking_aabb = AABB(Vector3(-MAP_HALF, -2, -MAP_HALF), Vector3(MAP_HALF * 2, 22, MAP_HALF * 2))
	nav_region.navigation_mesh = nm
	nav_region.bake_finished.connect(_on_bake_finished)
	add_child(nav_region)

	_build_ground()
	_build_stronghold()
	for side in SIDES:
		if SIDES[side].gate:
			_build_gate(side)
	_seal_tunnels()
	_build_climbs()
	_build_keep()
	_build_bases()
	_build_scenery()
	_build_spawns()
	_build_mounts(_build_stations() + _build_aa_turrets())
	rebake_navigation()


func rebake_navigation() -> void:
	if _baking:
		_rebake_queued = true
		return
	_baking = true
	nav_region.bake_navigation_mesh(true)


## Something that blocked the way is gone (a burnt tree has fallen): rebake the navmesh soon,
## once for a run of them.
func clear_obstacle() -> void:
	if _clearing:
		return
	_clearing = true
	get_tree().create_timer(REBAKE_DELAY, false).timeout.connect(func():
		_clearing = false
		rebake_navigation())


func _on_bake_finished() -> void:
	_baking = false
	if _rebake_queued:
		_rebake_queued = false
		rebake_navigation()
	elif not _first_bake_done:
		_first_bake_done = true
		navigation_ready.emit()


# ---------------------------------------------------------------- helpers

## Static box with collision, parented to the navigation region.
func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation = rot
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(Mats.box_mesh(size, Vector3.ZERO, mat))
	(parent if parent else nav_region).add_child(body)
	return body


# ---------------------------------------------------------------- build steps

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.47, 0.68)
	sky_mat.sky_horizon_color = Color(0.72, 0.72, 0.68)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.42)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.16)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.66, 0.7)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.3
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _build_ground() -> void:
	var size := MAP_HALF * 2.0 + 40.0
	var ground := _box(Vector3(size, 2.0, size), Vector3(0, -1.0, 0), Mats.ground())
	ground.name = "Ground"
	# Visual-only skirt so the horizon isn't a hard edge.
	var skirt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	skirt.mesh = pm
	skirt.material_override = Mats.ground()
	skirt.position.y = -0.05
	add_child(skirt)


func _build_stronghold() -> void:
	_stronghold = (load(STRONGHOLD) as PackedScene).instantiate() as Node3D
	_stronghold.position = STRONGHOLD_OFFSET
	nav_region.add_child(_stronghold)
	# Placeholder weapons on the mounts make way for turret models (_build_mounts).
	for n in _stronghold.find_children("PH_*", "", true, false):
		n.free()
	# The keep brings its own collision for the reactor.
	for mi in _stronghold.find_children("*", "MeshInstance3D", true, false):
		if not mi.name.begins_with("Reactor"):
			_add_collision(mi)


## Static trimesh collision for one of the stronghold's meshes.
func _add_collision(mi: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)


func _marker(marker_name: String) -> Node3D:
	return _stronghold.find_child(marker_name, true, false) as Node3D


## Index into FORESTS of the grove `p` stands in, or -1.
static func grove_at(p: Vector3) -> int:
	for k in FORESTS.size():
		var f: Array = FORESTS[k]
		if Vector2(p.x - f[0], p.z - f[1]).length() <= f[2]:
			return k
	return -1


## True if `p` stands in forest: inside one of the groves, with trees still standing round it.
static func in_forest(p: Vector3) -> bool:
	if grove_at(p) < 0:
		return false
	for t in ForestTree.standing:
		if Vector2(p.x - t.global_position.x, p.z - t.global_position.z).length() <= FOREST_NEAR:
			return true
	return false


## How far `p` is from the base: from the mountain's footprint, flat (0 on or inside it).
static func base_distance(p: Vector3) -> float:
	return Vector2(maxf(absf(p.x) - MOUNTAIN_HALF, 0.0), maxf(absf(p.z) - MOUNTAIN_HALF, 0.0)).length()


## Link for infiltrators only, along `route` (world points, walked or climbed in order).
func _route_link(route: Array[Vector3]) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.navigation_layers = NAV_INFILTRATORS
	link.start_position = route[0]
	link.end_position = route[-1]
	link.set_meta("route", route)
	add_child(link)
	return link


## Steel door with hazard stripes, centered on `parent`, facing out along its +Z.
func _blast_door(parent: Node3D, stripe_color: Color) -> void:
	parent.add_child(Mats.box_mesh(DOOR_SIZE, Vector3.ZERO, Mats.flat(Color(0.2, 0.21, 0.22), 0.8, 0.4)))
	var stripe := Mats.flat(stripe_color, 0.3, 0.6)
	for y in [-0.9, 0.0, 0.9]:
		parent.add_child(Mats.box_mesh(Vector3(DOOR_SIZE.x, 0.18, DOOR_SIZE.z + 0.08), Vector3(0, y, 0), stripe))


## Blast door on the side's gate tunnel (exit C of the middle bay).
func _build_gate(side: String) -> void:
	var exit := _marker("EXIT_C_%s%d" % [SIDES[side].face, GATE_BAY])
	var gate := Structure.new()
	gate.setup("%s Gate" % side.capitalize(), GATE_HP, 2.5)
	gate.name = "Gate_%s" % side
	gate.transform = Transform3D(exit.global_basis, exit.global_position + Vector3.UP * DOOR_SIZE.y * 0.5)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = DOOR_SIZE + Vector3(0.2, 0.2, 0.0)
	cs.shape = shape
	gate.add_child(cs)
	var visual := Node3D.new()
	gate.add_child(visual)
	_blast_door(visual, Color(0.8, 0.35, 0.08))
	gate.visual = visual
	gate.visual_half_height = DOOR_SIZE.y * 0.5
	nav_region.add_child(gate)
	gates[side] = gate

	# The tunnel stays plugged on the navmesh after the gate falls (nothing collides with the
	# plug): only infiltrators go in, over the breach link it opens.
	_nav_plug(gate.transform, DOOR_SIZE + Vector3(0.2, 0.2, 0.6))
	var out := exit.global_basis.z
	var breach := _route_link([exit.global_position + out * 3.0, exit.global_position - out * 3.5])
	breach.enabled = false
	breach.set_meta("breach", true)
	breach.add_to_group("breaches")
	gate.destroyed.connect(func(_g): breach.enabled = true)
	# The Gunner Squad goes out and back in whether the gate stands or not (the door opens for it,
	# Structure.hold_open): a link of its own, on a layer only the squad's troopers path on. It
	# spans just the gap the plug leaves in the navmesh, so a trooper in the doorway is never sent
	# back down the tunnel to find its end.
	var sally := NavigationLink3D.new()
	sally.navigation_layers = NAV_SQUAD
	sally.start_position = exit.global_position + out * SALLY_OUT
	sally.end_position = exit.global_position - out * SALLY_IN
	add_child(sally)


## Every tunnel that isn't a gate gets a door that can't be broken.
func _seal_tunnels() -> void:
	var gate_exits := []
	for side in gates:
		gate_exits.append("EXIT_C_%s%d" % [SIDES[side].face, GATE_BAY])
	for exit in _stronghold.find_children("EXIT_C_*", "", true, false):
		if String(exit.name) in gate_exits:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = GameConfig.LAYER_WORLD
		body.collision_mask = 0
		body.transform = Transform3D(exit.global_basis, exit.global_position + Vector3.UP * DOOR_SIZE.y * 0.5)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = DOOR_SIZE + Vector3(0.2, 0.2, 0.0)
		cs.shape = shape
		body.add_child(cs)
		_blast_door(body, Color(0.12, 0.12, 0.13))
		nav_region.add_child(body)


## Box that only the navmesh sees (LAYER_NAV_BLOCK), centered on `xf`.
func _nav_plug(xf: Transform3D, size: Vector3) -> void:
	var plug := StaticBody3D.new()
	plug.collision_layer = GameConfig.LAYER_NAV_BLOCK
	plug.collision_mask = 0
	plug.transform = xf
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	plug.add_child(cs)
	nav_region.add_child(plug)


## Climbing links in every bay: junction -> gun deck and gun deck -> roof.
func _build_climbs() -> void:
	for door in _stronghold.find_children("EXIT_B_*", "", true, false):
		_route_link(_bay_route(door, DECK_ROUTE))
		var roof := _bay_route(door, ROOF_ROUTE)
		if absf(roof[-1].dot(door.global_basis.x)) <= ROOF_EXPOSED_HALF:
			_route_link(roof)


## Bay coordinates (DECK_ROUTE / ROOF_ROUTE) to world points, via the bay's door B marker.
func _bay_route(door: Node3D, points: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in points:
		out.append(door.global_transform * Vector3(p[0] - DOOR_B.x, p[2] - DOOR_B.z, DOOR_B.y - p[1]))
	return out


## The keep is the reactor in the core hall under the peak. Attackers have to get inside
## the mountain to hit it (Structure.buried).
func _build_keep() -> void:
	var reactor := _marker("Reactor") as MeshInstance3D
	keep = Structure.new()
	keep.setup("The Keep", KEEP_HP, 5.0)
	keep.buried = true
	keep.name = "Keep"
	keep.position = reactor.global_position
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 4.0
	shape.height = 7.0
	cs.shape = shape
	keep.add_child(cs)
	var visual := Node3D.new()
	keep.add_child(visual)
	nav_region.add_child(keep)
	reactor.reparent(visual)
	var band := _marker("ReactorBand") as MeshInstance3D
	band.reparent(visual)
	band.material_override = Mats.glow(Color(1.0, 0.45, 0.1), 3.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 3.0
	light.omni_range = 22.0
	light.position = Vector3(0, 4.0, 0)
	visual.add_child(light)
	keep.visual = visual
	keep.visual_half_height = 3.5


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var lanes := []
	for side in gates:
		var out: Vector3 = SIDES[side].dir
		lanes.append([out * FACE_DIST, out * MAP_HALF])
	_build_forests(rng, lanes)
	var placed := 0
	var tries := 0
	while placed < 100 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-MAP_HALF + 5, MAP_HALF - 5), 0, rng.randf_range(-MAP_HALF + 5, MAP_HALF - 5))
		if _off_limits(p, lanes) or grove_at(p) >= 0:
			continue
		# A spot on a helipad's lot draws the same numbers but puts nothing down, so the rest of the
		# scatter lands where it always has.
		var lot := _on_base_lot(p)
		if rng.randf() < 0.55:
			_tree(p, rng, 0.0, Props.TREES, lot)
		else:
			_rock(p, rng, lot)
		placed += 1
	_build_ground_cover(rng)


## Clear of the mountain and the attack lanes.
func _off_limits(p: Vector3, lanes: Array) -> bool:
	if absf(p.x) < MOUNTAIN_HALF + 4 and absf(p.z) < MOUNTAIN_HALF + 4:
		return true
	for lane in lanes:
		if _dist_to_segment(p, lane[0], lane[1]) < 18.0:
			return true
	return false


## Trees packed into every grove, never closer than FOREST_TREE_SPACING.
func _build_forests(rng: RandomNumberGenerator, lanes: Array) -> void:
	for f in FORESTS:
		var centre := Vector3(f[0], 0, f[1])
		var r: float = f[2]
		var want := int(PI * r * r / FOREST_AREA_PER_TREE)
		var trees: Array[Vector3] = []
		for k in want * 20:
			if trees.size() >= want:
				break
			var a := rng.randf() * TAU
			var p := centre + Vector3(cos(a), 0, sin(a)) * r * sqrt(rng.randf())
			if _off_limits(p, lanes) or trees.any(func(t): return t.distance_to(p) < FOREST_TREE_SPACING):
				continue
			trees.append(p)
			_tree(p, rng)


## A tree that burns (ForestTree), `h` tall (random if 0), one of `models` (Props paths). `skip`:
## draw its numbers from `rng` but put nothing down (null).
func _tree(p: Vector3, rng: RandomNumberGenerator, h := 0.0, models: Array = Props.TREES, skip := false) -> ForestTree:
	if h <= 0.0:
		h = rng.randf_range(6.0, 11.0)
	var path: String = models[rng.randi() % models.size()]
	var yaw := rng.randf() * TAU
	if skip:
		return null
	var model := Props.instance(path, h)
	model.rotation.y = yaw
	var fp := Props.footprint(path, h)
	var tree := ForestTree.new()
	tree.position = p
	tree.setup(h, model, maxf(fp.x, fp.y) * 0.5, grove_at(p))
	var trunk: Array = Props.TRUNKS.get(path, [0.0, 0.0, 0.015, 0.5])
	tree.trunk_offset = Basis(Vector3.UP, yaw) * Vector3(trunk[0], 0.0, trunk[1]) * h
	tree.trunk_r = trunk[2] * h
	tree.perch = trunk[3] * h
	nav_region.add_child(tree)
	return tree


## `skip`: draw its numbers from `rng` but put nothing down.
func _rock(p: Vector3, rng: RandomNumberGenerator, skip := false) -> void:
	var path: String = Props.ROCKS[rng.randi() % Props.ROCKS.size()]
	var h := rng.randf_range(1.2, 3.0)
	if skip:
		rng.randf()
		return
	var model := Props.instance(path, h)
	var fp := Props.footprint(path, h)
	var r := minf(fp.x, fp.y) * 0.4
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.position = p
	body.rotation.y = rng.randf() * TAU
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h * 0.8
	cs.shape = shape
	cs.position.y = h * 0.4
	body.add_child(cs)
	body.add_child(model)
	nav_region.add_child(body)


## Visual-only ground cover (Bush); no collision so it never blocks units or the navmesh.
func _build_ground_cover(rng: RandomNumberGenerator) -> void:
	for i in 360:
		var p := Vector3(rng.randf_range(-MAP_HALF, MAP_HALF), 0, rng.randf_range(-MAP_HALF, MAP_HALF))
		if absf(p.x) < MOUNTAIN_HALF - 2 and absf(p.z) < MOUNTAIN_HALF - 2:
			continue
		var path: String = Props.BUSHES[rng.randi() % Props.BUSHES.size()]
		var h := rng.randf_range(0.4, 1.1)
		var bush := Bush.new()
		bush.position = p
		bush.setup(Props.instance(path, h), Props.footprint(path, h), h, rng.randf() * TAU)
		# A snake can't get at the ones under a helipad's deck or up against the mountain.
		bush.usable = not _on_base_lot(p) and base_distance(p) > 3.0
		add_child(bush)


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _build_spawns() -> void:
	for side in ["south", "east", "west"]:
		var out: Vector3 = SIDES[side].dir
		spawn_points.append(out * (MAP_HALF - 12.0))
		spawn_names.append(side.capitalize())
		spawn_bases.append(null)
		# Flag marker so players can see where the attackers come from.
		var pole := Mats.cylinder_mesh(0.12, 8.0, out * (MAP_HALF - 12.0) + Vector3(0, 4, 0) + out.cross(Vector3.UP) * 6.0, Mats.wood(), 6)
		add_child(pole)
		var flag := Mats.box_mesh(Vector3(2.0, 1.2, 0.05), pole.position + Vector3(1.0, 3.2, 0), Mats.flat(Color(0.75, 0.2, 0.15)))
		flag.rotation.y = atan2(out.x, out.z)
		add_child(flag)
	# The helipads come after the flags: spawn points 0-2 stay the map's edge.
	for b in bases:
		spawn_points.append(b.spawn_point)
		spawn_names.append(b.short_name)
		spawn_bases.append(b)


## The Forward Helipad Bases, each lying along its lane; its spawn point on the ground between it and
## the lane.
func _build_bases() -> void:
	for entry in BASES:
		var side: String = entry[0]
		var out: Vector3 = SIDES[side].dir
		var at := Vector3(float(entry[1]), 0.0, float(entry[2]))
		var base := AttackerBase.new()
		base.setup(side)
		# Its length (local x) along the lane.
		base.transform = Transform3D(Basis(Vector3.UP, atan2(-out.z, out.x)), at)
		var to_lane := at - out * at.dot(out)
		base.spawn_point = at - to_lane.normalized() * (AttackerBase.SIZE.y * 0.5 + AttackerBase.SPAWN_OUT)
		nav_region.add_child(base)
		bases.append(base)


## True if `p` is on a helipad's lot (its deck and BASE_LOT_MARGIN round it).
func _on_base_lot(p: Vector3) -> bool:
	for b in bases:
		if b.edge_distance(p) <= BASE_LOT_MARGIN:
			return true
	return false


## Builds the possessable stations on the bunker's mounts and gun decks; returns the mounts used.
func _build_stations() -> Array:
	var used := []
	# Machine guns on the gun deck above each gate, pushed up to the parapet and raised so
	# they can fire down to within ~5 m of the rock foot (the doorway itself is dead ground).
	for side in ["south", "east", "west"]:
		var mount := _marker("MOUNT_GUN_%s%d_1" % [SIDES[side].face, GATE_BAY])
		used.append(String(mount.name))
		var mg := MountedGun.new()
		mg.model_path = Props.SENTINEL_BASTION if side == "south" else Props.ORBITAL_SENTRY_GUN
		mg.pivot_height = 1.5
		mg.station_name = "MG · %s Gate" % side.capitalize()
		mg.name = "MG_%s" % side
		_place_facing_out(mg, side, mount.global_position + mount.global_basis.z * 0.6)
		add_child(mg)
		stations.append(mg)
		# Raiders on the deck walk around the gun instead of into it.
		_nav_plug(mg.transform.translated_local(Vector3.UP * 0.8), Vector3(1.4, 1.6, 1.4))

	var mortar := _marker(MORTAR_MOUNT)
	used.append(String(mortar.name))
	var art := ArtilleryStation.new()
	art.name = "Artillery"
	art.station_name = "Mortar · South Roof"
	art.map_half = MAP_HALF
	art.spotter_home = SIDES.south.dir * (FACE_DIST + 30.0)
	art.position = mortar.global_position
	add_child(art)
	stations.append(art)
	_nav_plug(art.transform.translated_local(Vector3.UP * 0.8), Vector3(2.6, 1.6, 2.6))

	# Riflemen on the gun decks, between a bay's two gun mounts and up against the parapet.
	for i in RIFLE_POSTS.size():
		var side: String = RIFLE_POSTS[i][0]
		var mount := _marker("MOUNT_GUN_%s%d_1" % [SIDES[side].face, RIFLE_POSTS[i][1]])
		var soldier := DefenderSoldier.new()
		soldier.model_path = DEFENDER_MODELS[i % DEFENDER_MODELS.size()]
		soldier.station_name = "Rifleman · %s Deck" % side.capitalize()
		soldier.name = "Soldier_%s_%d" % [side, RIFLE_POSTS[i][1]]
		var pos := mount.global_position + mount.global_basis.x * 3.0 + mount.global_basis.z * 0.8 + Vector3.UP * 0.1
		_place_facing_out(soldier, side, pos)
		add_child(soldier)
		stations.append(soldier)

	# The Gunner Squad holds the south spawn hall, facing the ramp up to the gate tunnel.
	var squad := GunnerSquad.new()
	squad.name = "GunnerSquad"
	squad.home = squad_post("S", SQUAD_POST_OFFSET)
	squad.gates = gates.values()
	add_child(squad)
	stations.append(squad)
	return used


## The AA turrets on the roofs; returns the mounts used.
func _build_aa_turrets() -> Array:
	var used := []
	for key in AA_TURRETS:
		var mount := _marker("MOUNT_AA_%s" % key)
		used.append(String(mount.name))
		var side: String = SIDES.keys().filter(func(k): return SIDES[k].face == key[0])[0]
		var t := AATurret.new()
		t.name = "AA_%s" % key
		t.station_name = "AA Turret · %s Roof" % side.capitalize()
		_place_facing_out(t, side, mount.global_position)
		add_child(t)
		aa_turrets.append(t)
	return used


## A squad's post in the gate spawn hall of a face ("S", "E", "W"): `offset` from the hall's spawn
## marker, in the marker's frame (x runs along the hall), facing the hall's spawn ramp.
func squad_post(face: String, offset: Vector3) -> Transform3D:
	var post := _marker("SPAWN_%s%d" % [face, GATE_BAY])
	return Transform3D(Basis.looking_at(post.global_basis.x), post.global_transform * offset)


## Turret models on every weapon mount no station uses: guns on the gun decks, launchers on
## the roofs. Unmanned dressing, no collision.
func _build_mounts(used: Array) -> void:
	for mount in _stronghold.find_children("MOUNT_*", "", true, false):
		if String(mount.name) in used:
			continue
		var model: Node3D
		if mount.name.begins_with("MOUNT_GUN"):
			model = Props.instance(Props.ORBITAL_SENTRY_GUN if mount.name.ends_with("_1") else Props.SENTINEL_BASTION, 2.0)
		else:
			model = Props.instance(Props.SENTINEL_SPIRE, 3.0)
		model.transform = Transform3D(Basis.looking_at(mount.global_basis.z), mount.global_position)
		add_child(model)


func _place_facing_out(node: Node3D, side: String, pos: Vector3) -> void:
	var out: Vector3 = SIDES[side].dir
	node.transform = Transform3D(Basis.looking_at(out, Vector3.UP), pos)
