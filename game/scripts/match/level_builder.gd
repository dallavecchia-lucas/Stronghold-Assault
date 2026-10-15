class_name LevelBuilder
extends Node3D
## Builds the test map: open field, square stronghold with three gates, the keep,
## defender posts and attacker spawn points. Everything static lives under the
## navigation region so it gets baked into the navmesh.

signal navigation_ready

const MAP_HALF := 120.0
const FORT_HALF := 30.0
const WALL_H := 7.0
const WALL_T := 2.5
const GATE_W := 8.0
const GATE_H := 6.0
const GATE_HP := 1500.0
const KEEP_HP := 4000.0

## side name -> {"dir": outward Vector3, "along_x": bool}
const SIDES := {
	"south": {"dir": Vector3(0, 0, 1), "along_x": true, "gate": true},
	"north": {"dir": Vector3(0, 0, -1), "along_x": true, "gate": false},
	"east": {"dir": Vector3(1, 0, 0), "along_x": false, "gate": true},
	"west": {"dir": Vector3(-1, 0, 0), "along_x": false, "gate": true},
}

var nav_region: NavigationRegion3D
var keep: Structure
var gates := {}  # side -> Structure
var stations := []  # possessable defender stations, in hotkey order
var spawn_points: Array[Vector3] = []
var spawn_names: Array[String] = []

var _baking := false
var _rebake_queued := false
var _first_bake_done := false


func build() -> void:
	_build_environment()
	nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES
	nm.cell_size = 0.4
	nm.cell_height = 0.2
	nm.agent_radius = 0.8
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 40.0
	nm.filter_baking_aabb = AABB(Vector3(-MAP_HALF, -2, -MAP_HALF), Vector3(MAP_HALF * 2, 30, MAP_HALF * 2))
	nav_region.navigation_mesh = nm
	nav_region.bake_finished.connect(_on_bake_finished)
	add_child(nav_region)

	_build_ground()
	for side in SIDES:
		_build_wall(side)
	_build_towers()
	_build_keep()
	_build_scenery()
	_build_spawns()
	_build_stations()
	rebake_navigation()


func rebake_navigation() -> void:
	if _baking:
		_rebake_queued = true
		return
	_baking = true
	nav_region.bake_navigation_mesh(true)


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


## Position on a wall: `t` along the wall, `off` outward from the wall center line.
func _wall_point(side: String, t: float, off: float, y: float) -> Vector3:
	var s: Dictionary = SIDES[side]
	var line := FORT_HALF + off
	if s.along_x:
		return Vector3(t, y, line * s.dir.z)
	return Vector3(line * s.dir.x, y, t)


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
	sun.directional_shadow_max_distance = 220.0
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


func _build_wall(side: String) -> void:
	var s: Dictionary = SIDES[side]
	var stone := Mats.stone()
	var half_len := FORT_HALF + WALL_T * 0.5
	var segments := [[-half_len, half_len]]
	if s.gate:
		segments = [[-half_len, -GATE_W * 0.5], [GATE_W * 0.5, half_len]]
	for seg in segments:
		var length: float = seg[1] - seg[0]
		var mid: float = (seg[0] + seg[1]) * 0.5
		var size := Vector3(length, WALL_H, WALL_T) if s.along_x else Vector3(WALL_T, WALL_H, length)
		_box(size, _wall_point(side, mid, 0.0, WALL_H * 0.5), stone).name = "Wall_%s" % side

	if s.gate:
		var lintel_h := WALL_H - GATE_H
		var lsize := Vector3(GATE_W, lintel_h, WALL_T) if s.along_x else Vector3(WALL_T, lintel_h, GATE_W)
		_box(lsize, _wall_point(side, 0.0, 0.0, GATE_H + lintel_h * 0.5), stone)
		_build_gate(side)

	# Battlements on the outer edge, with a gap where the gun sits above the gate.
	var t := -half_len + 1.0
	while t < half_len - 0.5:
		if not (s.gate and absf(t) < 2.6):
			var msize := Vector3(1.2, 1.2, 0.8) if s.along_x else Vector3(0.8, 1.2, 1.2)
			_box(msize, _wall_point(side, t, WALL_T * 0.5 - 0.4, WALL_H + 0.6), stone)
		t += 2.4

	# Ramp up to the walkway on the inner side.
	var rise := WALL_H
	var run := 16.0
	var slope_len := sqrt(rise * rise + run * run)
	var angle := atan2(rise, run)
	var rsize := Vector3(slope_len, 0.5, 3.0) if s.along_x else Vector3(3.0, 0.5, slope_len)
	var rrot := Vector3(0, 0, angle) if s.along_x else Vector3(-angle, 0, 0)
	_box(rsize, _wall_point(side, 16.0, -(WALL_T * 0.5 + 1.5), rise * 0.5 - 0.2), stone, rrot)


func _build_gate(side: String) -> void:
	var s: Dictionary = SIDES[side]
	var gate := Structure.new()
	gate.setup("%s Gate" % side.capitalize(), GATE_HP, GATE_W * 0.5)
	gate.name = "Gate_%s" % side
	gate.position = _wall_point(side, 0.0, 0.0, GATE_H * 0.5)
	var size := Vector3(GATE_W, GATE_H, 1.2) if s.along_x else Vector3(1.2, GATE_H, GATE_W)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	gate.add_child(cs)
	var visual := Node3D.new()
	gate.add_child(visual)
	visual.add_child(Mats.box_mesh(size, Vector3.ZERO, Mats.wood()))
	var iron := Mats.flat(Color(0.18, 0.18, 0.2), 0.8, 0.4)
	for y in [-1.8, 0.0, 1.8]:
		var band := Vector3(GATE_W, 0.25, 1.35) if s.along_x else Vector3(1.35, 0.25, GATE_W)
		visual.add_child(Mats.box_mesh(band, Vector3(0, y, 0), iron))
	gate.visual = visual
	gate.visual_half_height = GATE_H * 0.5
	gate.destroyed.connect(func(_g): rebake_navigation())
	nav_region.add_child(gate)
	gates[side] = gate


func _build_towers() -> void:
	var stone := Mats.stone()
	for x in [-1, 1]:
		for z in [-1, 1]:
			var p := Vector3(x * FORT_HALF, 0, z * FORT_HALF)
			_box(Vector3(6.5, 11, 6.5), p + Vector3(0, 5.5, 0), stone)
			for i in 4:
				var a := i * PI * 0.5
				var o := Vector3(sin(a), 0, cos(a)) * 2.7
				_box(Vector3(1.4, 1.3, 1.4), p + o + Vector3(0, 11.65, 0), stone)
			var roof := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 4.0
			cone.height = 4.0
			cone.radial_segments = 4
			roof.mesh = cone
			roof.material_override = Mats.flat(Color(0.45, 0.16, 0.12), 0.0, 0.8)
			roof.position = p + Vector3(0, 13.8, 0)
			roof.rotation.y = PI * 0.25
			add_child(roof)


func _build_keep() -> void:
	keep = Structure.new()
	keep.setup("The Keep", KEEP_HP, 7.0)
	keep.name = "Keep"
	keep.position = Vector3(0, 5, 0)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, 10, 12)
	cs.shape = shape
	keep.add_child(cs)
	var visual := Node3D.new()
	keep.add_child(visual)
	visual.add_child(Mats.box_mesh(Vector3(12, 10, 12), Vector3.ZERO, Mats.dark_stone()))
	visual.add_child(Mats.box_mesh(Vector3(8, 4, 8), Vector3(0, 7, 0), Mats.dark_stone()))
	var crystal := MeshInstance3D.new()
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 1.4
	prism.height = 4.0
	prism.radial_segments = 6
	crystal.mesh = prism
	crystal.material_override = Mats.glow(Color(0.3, 0.7, 1.0), 4.0)
	crystal.position = Vector3(0, 11, 0)
	visual.add_child(crystal)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.7, 1.0)
	light.light_energy = 3.0
	light.omni_range = 18.0
	light.position = Vector3(0, 11, 0)
	visual.add_child(light)
	var banner_mat := Mats.flat(Color(0.15, 0.3, 0.65), 0.0, 0.9)
	for i in 4:
		var a := i * PI * 0.5
		var b := Mats.box_mesh(Vector3(2.0, 5.0, 0.1), Vector3(sin(a) * 6.06, 1.0, cos(a) * 6.06), banner_mat)
		b.rotation.y = a
		visual.add_child(b)
	keep.visual = visual
	keep.visual_half_height = 5.0
	nav_region.add_child(keep)


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var lanes := []
	for side in gates:
		var out: Vector3 = SIDES[side].dir
		lanes.append([out * FORT_HALF, out * MAP_HALF])
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var p := Vector3(rng.randf_range(-MAP_HALF + 5, MAP_HALF - 5), 0, rng.randf_range(-MAP_HALF + 5, MAP_HALF - 5))
		if absf(p.x) < FORT_HALF + 14 and absf(p.z) < FORT_HALF + 14:
			continue
		var blocked := false
		for lane in lanes:
			if _dist_to_segment(p, lane[0], lane[1]) < 14.0:
				blocked = true
				break
		if blocked:
			continue
		if rng.randf() < 0.55:
			_tree(p, rng)
		else:
			_rock(p, rng)
		placed += 1


func _tree(p: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(5.0, 9.0)
	var trunk := _box(Vector3(0.6, h * 0.4, 0.6), p + Vector3(0, h * 0.2, 0), Mats.wood())
	for i in 2:
		var leaves := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = h * (0.32 - i * 0.08)
		cone.height = h * 0.55
		cone.radial_segments = 7
		leaves.mesh = cone
		leaves.material_override = Mats.flat(Color(0.16, 0.3 + i * 0.04, 0.14), 0.0, 0.9)
		leaves.position = Vector3(0, h * (0.35 + i * 0.25), 0)
		trunk.add_child(leaves)


func _rock(p: Vector3, rng: RandomNumberGenerator) -> void:
	var s := Vector3(rng.randf_range(1.5, 4.5), rng.randf_range(1.0, 2.8), rng.randf_range(1.5, 4.5))
	_box(s, p + Vector3(0, s.y * 0.4, 0), Mats.rock(), Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _build_spawns() -> void:
	for side in ["south", "east", "west"]:
		var out: Vector3 = SIDES[side].dir
		spawn_points.append(out * (MAP_HALF - 12.0))
		spawn_names.append(side.capitalize())
		# Flag marker so players can see where the attackers come from.
		var pole := Mats.cylinder_mesh(0.12, 8.0, out * (MAP_HALF - 12.0) + Vector3(0, 4, 0) + out.cross(Vector3.UP) * 6.0, Mats.wood(), 6)
		add_child(pole)
		var flag := Mats.box_mesh(Vector3(2.0, 1.2, 0.05), pole.position + Vector3(1.0, 3.2, 0), Mats.flat(Color(0.75, 0.2, 0.15)))
		flag.rotation.y = atan2(out.x, out.z)
		add_child(flag)


func _build_stations() -> void:
	# Machine guns over each gate.
	for side in ["south", "east", "west"]:
		var mg := MountedGun.new()
		mg.station_name = "MG · %s Gate" % side.capitalize()
		mg.name = "MG_%s" % side
		_place_facing_out(mg, side, _wall_point(side, 0.0, 0.0, WALL_H))
		add_child(mg)
		stations.append(mg)

	var art := ArtilleryStation.new()
	art.name = "Artillery"
	art.station_name = "Mortar · Courtyard"
	art.map_half = MAP_HALF
	art.position = Vector3(0, 0, -18)
	add_child(art)
	stations.append(art)

	var posts := [["south", -16.0], ["south", 16.0], ["east", -14.0], ["west", 14.0], ["north", 0.0]]
	for p in posts:
		var soldier := DefenderSoldier.new()
		soldier.station_name = "Rifleman · %s Wall" % p[0].capitalize()
		soldier.name = "Soldier_%s_%d" % [p[0], int(p[1])]
		_place_facing_out(soldier, p[0], _wall_point(p[0], p[1], -0.2, WALL_H + 0.1))
		add_child(soldier)
		stations.append(soldier)


func _place_facing_out(node: Node3D, side: String, pos: Vector3) -> void:
	var out: Vector3 = SIDES[side].dir
	node.transform = Transform3D(Basis.looking_at(out, Vector3.UP), pos)
