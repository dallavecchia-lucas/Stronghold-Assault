class_name JungleLevel
extends LevelBuilder
## The Jungle Keep map (JungleLayout): the stronghold in a clearing in a 1.6 km jungle, the rivers and
## their truss bridges, the ridges, the prison on its plateau behind the cliff, the Quarry and Outpost
## helipads, and the Mobile Command Citadel at the south edge, the attackers' main spawn. The stronghold
## itself (gates, keep, posts, AA turrets, climbs) is the classic map's (LevelBuilder).
##
## Everything is at its real size: the prison fortress PRISON_HEIGHT tall (a cell block's windows
## about 3 m apart), the citadel CITADEL_HEIGHT (its hull modules two storeys), the helipads' decks big
## enough for a transport helicopter (AttackerBase), the emergent trees 40-56 m, the canopy 24-38 m.
##
## The navmesh is baked in NAV_TILE squares (the map is far too big for one bake): the static colliders
## are parsed once, the ground (JungleTerrain.nav_faces, the water cut out) added, and every tile baked
## on the worker threads with a border so the tiles meet edge to edge. A burnt tree that falls rebakes
## only its tile.

const PRISON_MODEL := "res://assets/structures/violet_fortress/violet_fortress.glb"
const CITADEL_MODEL := "res://assets/structures/mobile_command_citadel/mobile_command_citadel.glb"
## Real heights (m, to the top of the highest mast): the prison's central watchtower, the citadel's dishes.
const PRISON_HEIGHT := 42.0
const CITADEL_HEIGHT := 19.5
## The prison faces the Keep; the citadel's long arm points at it.
const PRISON_YAW := 0.0
const CITADEL_YAW := PI * 0.5
## Units spawned at the main spawn appear this far in front (north) of the citadel's middle.
const SPAWN_AHEAD := 52.0
const NAV_TILE := 200.0
const NAV_BORDER := 3.0
## Tiles round the stronghold bake only up to its roofs (the mountain above is out of reach); the rest
## up to the ridges' tops.
const NAV_LOW_TOP := 20.0
const NAV_HIGH_TOP := 70.0
const NAV_FLOOR := -10.0
## Bakes on the worker threads at once.
const NAV_PARALLEL := 4

var ground: JungleTerrain
var flora: JungleFlora
var prison: Node3D
var citadel: Node3D
var bridges: Array[TrussBridge] = []

var _nav_template: NavigationMesh
var _tiles := {}  # Vector2i -> NavigationRegion3D
var _dirty := {}  # Vector2i -> true, waiting for a rebake
var _queue: Array[Vector2i] = []
var _running := 0
var _source: NavigationMeshSourceGeometryData3D
var _bake_t0 := 0
var _baked := {}  # Vector2i -> NavigationMesh, the first bake's tiles until they are all done


func build() -> void:
	map_half = JungleLayout.MAP_HALF
	jungle = true
	tiles_level = self
	edge_spawns = {"south": 0, "east": 0, "west": 0}
	_build_all()
	terrain = ground


func _build_all() -> void:
	_build_environment()
	# The region is the parse root for the static colliders; the tiles (_tiles) carry the navmesh.
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Static"
	nav_region.enabled = false
	nav_region.navigation_mesh = NavigationMesh.new()
	add_child(nav_region)
	_nav_template = _make_nav_template()

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


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.46, 0.66)
	sky_mat.sky_horizon_color = Color(0.68, 0.73, 0.72)
	# Below the horizon the sky is the haze over the far jungle, so the land fades into it.
	sky_mat.ground_horizon_color = Color(0.66, 0.71, 0.7)
	sky_mat.ground_bottom_color = Color(0.5, 0.56, 0.52)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.0
	# The rivers and the lake mirror the jungle and the sky (Forward+).
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	# Humid haze: the far jungle fades blue-grey.
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.71, 0.7)
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.35
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(35.0), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _build_ground() -> void:
	ground = JungleTerrain.new()
	ground.name = "Terrain"
	add_child(ground)
	ground.build()
	terrain = ground
	# Past the terrain's edge, flat land under the haze to the horizon.
	var skirt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60000, 60000)
	skirt.mesh = pm
	skirt.material_override = Mats.flat(Color(0.1, 0.13, 0.07), 0.0, 1.0)
	skirt.position.y = -0.3
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)


# ---------------------------------------------------------------- the sites

## The helipads: the Quarry west of the Keep, the Outpost east of it, across the east river.
func _build_bases() -> void:
	for entry in [["west", "Quarry", JungleLayout.QUARRY], ["east", "Outpost", JungleLayout.OUTPOST]]:
		var at: Vector2 = entry[2]
		var base := AttackerBase.new()
		base.setup(entry[0], entry[1])
		base.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, ground.height_at(at.x, at.y), at.y))
		# Units it spawns come out on the side facing the Keep.
		var toward := -signf(at.x)
		base.spawn_point = base.position + Vector3(toward * (AttackerBase.SIZE.x * 0.5 + AttackerBase.SPAWN_OUT), 0, 0)
		nav_region.add_child(base)
		bases.append(base)


func _build_spawns() -> void:
	var at := JungleLayout.MAIN_SPAWN
	spawn_points.append(Vector3(at.x, 0.0, at.y - SPAWN_AHEAD))
	spawn_names.append("Main")
	spawn_bases.append(null)
	for b in bases:
		spawn_points.append(b.spawn_point)
		spawn_names.append(b.short_name)
		spawn_bases.append(b)


func rally_point(idx: int) -> Vector3:
	if spawn_bases[idx] != null:
		return spawn_points[idx]
	# Out in front of the citadel, short of the river.
	return spawn_points[idx] + Vector3(0, 0, -30)


## The army walks a long way here (550-650 m from the citadel to a gate): the defenders hold for
## JUNGLE_TIME rather than the classic map's ten minutes.
const JUNGLE_TIME := 900.0


func match_time() -> float:
	return maxf(GameConfig.match_duration, JUNGLE_TIME) if GameConfig.autotest == "" else GameConfig.match_duration


func camera_home() -> Vector3:
	return spawn_points[0] + Vector3(0, 0, -40)


func _build_scenery() -> void:
	_build_prison()
	_build_citadel()
	_build_bridges()
	_build_rocks()
	flora = JungleFlora.new()
	flora.name = "Flora"
	flora.level = self
	flora.terrain = ground
	add_child(flora)
	flora.build()


## A static prop at its real height on the ground at `at`, with box colliders (centre, size, local).
func _prop(path: String, h: float, at: Vector2, yaw: float, sink: float, boxes: Array) -> Node3D:
	var model := Props.instance(path, h)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector3(at.x, ground.height_at(at.x, at.y) - sink, at.y)
	body.rotation.y = yaw
	body.add_child(model)
	for b in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b[1]
		cs.shape = shape
		cs.position = b[0]
		body.add_child(cs)
	nav_region.add_child(body)
	return body


## The prison: a concrete fortress on the plateau, its cell blocks round a yard, watchtowers at the
## corners and a taller one over the gate. Solid to the navmesh (units walk round it).
func _build_prison() -> void:
	Props.aspect(PRISON_MODEL)
	var fp := Props.footprint(PRISON_MODEL, PRISON_HEIGHT)
	prison = _prop(PRISON_MODEL, PRISON_HEIGHT, JungleLayout.PRISON, PRISON_YAW, 1.5,
			[[Vector3(0, 8, 0), Vector3(fp.x * 0.92, 16, fp.y * 0.92)]])
	prison.name = "Prison"
	_label(prison, "PRISON", PRISON_HEIGHT + 6.0)


## The Mobile Command Citadel: the attackers' deployed headquarters at the south edge, its hull modules
## in a cross on their outriggers. The main spawn is in front of it.
func _build_citadel() -> void:
	Props.aspect(CITADEL_MODEL)
	var fp := Props.footprint(CITADEL_MODEL, CITADEL_HEIGHT)
	# Two boxes along the cross's arms.
	citadel = _prop(CITADEL_MODEL, CITADEL_HEIGHT, JungleLayout.MAIN_SPAWN, CITADEL_YAW, 0.2,
			[[Vector3(0, 5, 0), Vector3(fp.x * 0.95, 10, fp.y * 0.34)], [Vector3(0, 5, 0), Vector3(fp.x * 0.34, 10, fp.y * 0.95)]])
	citadel.name = "MobileCommandCitadel"
	_label(citadel, "MOBILE COMMAND CITADEL", CITADEL_HEIGHT + 5.0)


func _label(parent: Node3D, text: String, y: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 26
	l.outline_size = 8
	l.modulate = Color(0.9, 0.92, 1.0)
	l.position = Vector3(0, y, 0)
	l.no_depth_test = true
	parent.add_child(l)


func _build_bridges() -> void:
	for b in JungleLayout.bridges():
		var c: Vector2 = b[0]
		var along: Vector2 = b[1]
		var br := TrussBridge.new()
		br.setup(b[2], b[3])
		br.transform = Transform3D(Basis(Vector3.UP, atan2(-along.y, along.x)), Vector3(c.x, 0.0, c.y))
		nav_region.add_child(br)
		bridges.append(br)


## Boulders: along the foot and the top of the cliff, on the quarry's floor, on the banks and out in
## the jungle (with collision, like the classic map's rocks).
func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var a := JungleLayout.CLIFF_A
	var b := JungleLayout.CLIFF_B
	for k in 26:
		var t := rng.randf()
		var p := a.lerp(b, t) + Vector2(rng.randf_range(-6, 6), rng.randf_range(4.0, 14.0))
		_boulder(p, rng.randf_range(4.0, 9.0), rng)
	for k in 14:
		var p := a.lerp(b, rng.randf()) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-12.0, -4.0))
		_boulder(p, rng.randf_range(3.0, 6.0), rng)
	var qc: Vector2 = JungleLayout.QUARRY_CUT[0]
	for k in 12:
		var p := qc + Vector2(rng.randf_range(-35, 25), rng.randf_range(-45, 45))
		if JungleLayout.ellipse_d(p, qc, JungleLayout.QUARRY_CUT[1]) < 0.3:
			_boulder(p, rng.randf_range(1.5, 4.0), rng)
	var placed := 0
	var tries := 0
	while placed < 220 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(-780, 780), rng.randf_range(-780, 780))
		if p.length() < JungleLayout.CLEARING_R + 20.0 or ground.track_distance(p.x, p.y) < 8.0:
			continue
		var h := ground.height_at(p.x, p.y)
		if h < JungleLayout.WATER_Y + 0.6 or _near_site(p):
			continue
		_boulder(p, rng.randf_range(1.2, 3.5), rng)
		placed += 1


func _near_site(p: Vector2) -> bool:
	for f in JungleLayout.FLATTEN:
		if p.distance_to(f[0]) < f[1]:
			return true
	if p.distance_to(JungleLayout.PRISON) < 90.0:
		return true
	for b in JungleLayout.bridges():
		if p.distance_to(b[0]) < b[2] * 0.5 + 20.0:
			return true
	return false


func _boulder(p: Vector2, h: float, rng: RandomNumberGenerator) -> void:
	var path: String = Props.ROCKS[rng.randi() % Props.ROCKS.size()]
	var model := Props.instance(path, h)
	var fp := Props.footprint(path, h)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector3(p.x, ground.height_at(p.x, p.y) - h * 0.15, p.y)
	body.rotation.y = rng.randf() * TAU
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = minf(fp.x, fp.y) * 0.4
	shape.height = h * 0.8
	cs.shape = shape
	cs.position.y = h * 0.4
	body.add_child(cs)
	body.add_child(model)
	nav_region.add_child(body)


# ---------------------------------------------------------------- the navmesh, in tiles

func _make_nav_template() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_NAV_BLOCK
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nm.edge_max_error = 1.0
	nm.border_size = NAV_BORDER
	# Big open regions merged into few polygons (navmesh queries go over every polygon on the map).
	nm.region_min_size = 8.0
	nm.region_merge_size = 400.0
	return nm


func _tile_rect(t: Vector2i) -> Rect2:
	return Rect2(-map_half + t.x * NAV_TILE, -map_half + t.y * NAV_TILE, NAV_TILE, NAV_TILE)


func _tile_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x + map_half) / NAV_TILE), 0, _tiles_across() - 1),
			clampi(floori((p.z + map_half) / NAV_TILE), 0, _tiles_across() - 1))


func _tiles_across() -> int:
	return int(map_half * 2.0 / NAV_TILE)


## The tile itself first, then its neighbours.
const _TILE_ORDER: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]


## The navmesh point closest to `p` (LevelBuilder.nav_closest): in the tile under it, or a neighbouring
## tile whose edge is nearer than what that found.
func tile_closest(map: RID, p: Vector3) -> Vector3:
	var home := _tile_of(p)
	var best := Vector3.INF
	var best_d := INF
	for off in _TILE_ORDER:
		var t := home + off
		if not _tiles.has(t) or (_tiles[t] as NavigationRegion3D).navigation_mesh == null:
			continue
		if t != home:
			var r := _tile_rect(t)
			var edge := Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0)).length()
			if edge >= best_d:
				continue
		var q := NavigationServer3D.region_get_closest_point((_tiles[t] as NavigationRegion3D).get_rid(), p)
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best if best != Vector3.INF else NavigationServer3D.map_get_closest_point(map, p)


## The tiles round `a` and `b` (the box over both, NAV_TILE * 0.25 bigger), for LevelBuilder.nav_path.
func tiles_round(a: Vector3, b: Vector3) -> Array[RID]:
	var m := NAV_TILE * 0.25
	var t0 := _tile_of(Vector3(minf(a.x, b.x) - m, 0, minf(a.z, b.z) - m))
	var t1 := _tile_of(Vector3(maxf(a.x, b.x) + m, 0, maxf(a.z, b.z) + m))
	var out: Array[RID] = []
	for j in range(t0.y, t1.y + 1):
		for i in range(t0.x, t1.x + 1):
			out.append((_tiles[Vector2i(i, j)] as NavigationRegion3D).get_rid())
	return out


## Rebakes every tile (the first time), or the tiles marked dirty since.
func rebake_navigation() -> void:
	if _baking:
		_rebake_queued = true
		return
	if _tiles.is_empty():
		for j in _tiles_across():
			for i in _tiles_across():
				var r := NavigationRegion3D.new()
				r.name = "NavTile_%d_%d" % [i, j]
				add_child(r)
				_tiles[Vector2i(i, j)] = r
				_dirty[Vector2i(i, j)] = true
	if _dirty.is_empty():
		return
	_baking = true
	_bake_t0 = Time.get_ticks_msec()
	# The tiles' edges meet exactly: merge them by their exact positions, not the map's coarse cells.
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(get_world_3d().navigation_map, 0.001)
	# The static colliders (the stronghold, structures, bridges, rocks, tree trunks), then the ground.
	_source = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_nav_template, _source, nav_region)
	var faces := ground.nav_faces(Rect2(-map_half - NAV_TILE * 0.1, -map_half - NAV_TILE * 0.1, map_half * 2.0 + NAV_TILE * 0.2, map_half * 2.0 + NAV_TILE * 0.2))
	_source.add_faces(faces, Transform3D.IDENTITY)
	_queue.clear()
	for t in _dirty:
		_queue.append(t)
	_dirty.clear()
	for k in mini(NAV_PARALLEL, _queue.size()):
		_bake_next()


func _bake_next() -> void:
	if _queue.is_empty():
		if _running == 0:
			_bakes_done()
		return
	var t: Vector2i = _queue.pop_front()
	var rect := _tile_rect(t)
	var nm := _nav_template.duplicate() as NavigationMesh
	var low := rect.intersects(Rect2(-130, -130, 260, 260))
	var top := NAV_LOW_TOP if low else NAV_HIGH_TOP
	nm.filter_baking_aabb = AABB(Vector3(rect.position.x - NAV_BORDER, NAV_FLOOR, rect.position.y - NAV_BORDER),
			Vector3(rect.size.x + NAV_BORDER * 2.0, top - NAV_FLOOR, rect.size.y + NAV_BORDER * 2.0))
	_running += 1
	NavigationServer3D.bake_from_source_geometry_data_async(nm, _source, _tile_baked.bind(t, nm))


func _tile_baked(t: Vector2i, nm: NavigationMesh) -> void:
	_running -= 1
	# The first time, every tile goes into the map at once (one rebuild of the map, not one a tile).
	if _first_bake_done:
		_tiles[t].navigation_mesh = nm
	else:
		_baked[t] = nm
	_bake_next()


func _bakes_done() -> void:
	_baking = false
	_source = null
	if not _baked.is_empty():
		# Built in one go on the main thread while the match loads (on the worker threads it takes many
		# seconds for a map this size); afterwards a rebuilt tile syncs in the background again.
		var map := get_world_3d().navigation_map
		NavigationServer3D.map_set_use_async_iterations(map, false)
		for t in _baked:
			NavigationServer3D.region_set_use_async_iterations(_tiles[t].get_rid(), false)
			_tiles[t].navigation_mesh = _baked[t]
		_baked.clear()
	print("JungleLevel: navmesh tiles baked in %d ms" % (Time.get_ticks_msec() - _bake_t0))
	if _rebake_queued:
		_rebake_queued = false
		rebake_navigation()
	elif not _first_bake_done:
		_first_bake_done = true
		_await_map()


## The navigation server takes the tiles into the map a few frames after they are handed over (big
## regions sync on a thread): navigation_ready waits until every tile is in it (a point in the middle of
## each tile finds the navmesh close by), or MAP_WAIT frames at most.
const MAP_WAIT := 900


func _await_map() -> void:
	var map := get_world_3d().navigation_map
	for frame in MAP_WAIT:
		await get_tree().physics_frame
		var all_in := true
		for t in _tiles:
			var r := _tile_rect(t)
			var c := r.get_center()
			var q := NavigationServer3D.map_get_closest_point(map, Vector3(c.x, ground.height_at(c.x, c.y) + 1.0, c.y))
			if not r.grow(40.0).has_point(Vector2(q.x, q.z)):
				all_in = false
				break
		if all_in:
			print("JungleLevel: navmesh in the map after %d frames" % frame)
			break
	NavigationServer3D.map_set_use_async_iterations(map, true)
	for t in _tiles:
		NavigationServer3D.region_set_use_async_iterations(_tiles[t].get_rid(), true)
	navigation_ready.emit()


## A burnt tree has fallen at `at`: its tile is rebaked (soon, once for a run of them).
func clear_obstacle(at := Vector3.INF) -> void:
	if at == Vector3.INF:
		for t in _tiles:
			_dirty[t] = true
	else:
		_dirty[_tile_of(at)] = true
	super.clear_obstacle(at)
