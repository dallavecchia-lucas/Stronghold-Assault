class_name RiverCrossing
extends RefCounted
## Getting across the Jungle Keep's water (JungleTerrain: too deep to wade, an invisible wall along its edge).
##
## Three ways over it, besides flying:
##   - Swimming. Bears, snakes, hippos and elephants (UnitTypes swim_*) swim across the rivers and the lake. The
##     water is no part of the navmesh: links (NavigationLink3D on NAV_SWIMMERS, which only the swimmers' agents
##     carry) cross it every LINK_EVERY m along every river and a few times over the lake, from a little way up one
##     bank to the other. A swimmer whose path takes one swims straight across (AttackerUnit, swim_route()): down
##     the bank, its feet sinking to swim_sink under the surface out in the deep water, up the far bank. A swim
##     costs SWIM_COST times its length, so a bridge close by is taken instead.
##   - Riding. Every hippo and elephant carries a pontoon raft (TowPlatform, UnitTypes tows and pack), folded up till
##     riders come for it, then tows it; the other units, but the
##     ones too big or awkward to (UnitTypes no_ride), climb onto it, two at most, or a Combat Rhino or a giraffe on
##     its own (UnitTypes ride_alone), and get off on the far side (AttackerCommander's ferry, AttackerUnit board /
##     riders).
##   - The bridges the attackers drop across the rivers (FoldingBridge): everyone walks over, the defenders too.
## Swimming or riding, a unit can't attack or use its skills: it is completely vulnerable. But a bear can dive under
## the water (AttackerUnit.start_dive): out of the defenders' sight, though a round that goes in where it is hits it.

## Navigation layer bit of the swim links (LevelBuilder has 1, 2 and 4).
const NAV_SWIMMERS := 8
## A swim link every this far along each river (m), and their cost per metre against walking.
const LINK_EVERY := 14.0
const SWIM_COST := 2.5
## Each end of a link is this far up the bank from the water's edge (m), where the navmesh is; it may sit up to
## SNAP_SLACK off it.
const LAND_IN := 3.5
const SNAP_SLACK := 2.5
## Ground this far over the water is dry (the water's edge, JungleTerrain.EDGE_UP).
const DRY := 0.25
## Water wider than twice this across a river (m) is the lake or a confluence: no link there.
const MAX_HALF := 45.0
## Chords across the lake: this many, at even angles through its middle.
const LAKE_CHORDS := 8
## A swim that would cross more than this much dry land on its way (m): no link (a spit between two rivers).
const MAX_DRY_RUN := 8.0
## A unit sent somewhere it can walk to rides anyway if its way on foot is this much longer than the way across
## the water (a far bridge): RIDE_DETOUR times it, plus RIDE_SLACK m.
const RIDE_DETOUR := 1.6
const RIDE_SLACK := 80.0

static var links: Array[NavigationLink3D] = []
static var _ring_mesh: TorusMesh
static var _ring_mat: StandardMaterial3D
static var _puff_mat: StandardMaterial3D


static func active() -> bool:
	return LevelBuilder.jungle and JungleTerrain.current != null


static func ground(p: Vector2) -> float:
	return JungleTerrain.current.height_at(p.x, p.y)


## True where the ground is under water.
static func wet(p: Vector3) -> bool:
	return active() and JungleTerrain.current.height_at(p.x, p.z) < JungleLayout.WATER_Y


## True if `p` is in the water deep enough to swim (its feet more than `depth` under the surface).
static func swimming_at(p: Vector3, depth := 0.4) -> bool:
	return active() and p.y < JungleLayout.WATER_Y - depth and JungleTerrain.current.height_at(p.x, p.z) < p.y + 0.3


## The river nearest `p` (flat): {name, point (Vector2, on its centreline), dir (Vector2, along it), dist (m),
## width (m)}; empty off the Jungle Keep.
static func nearest_river(p: Vector2) -> Dictionary:
	if not active():
		return {}
	var best := {}
	var best_d := INF
	for r in JungleLayout.RIVERS:
		var c := JungleLayout.river_curve(r[0])
		for i in c.size() - 1:
			var a := c[i]
			var b := c[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var q := a + ab * t
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = {"name": r[0], "point": q, "dir": ab.normalized(), "dist": d, "width": r[1]}
	return best


## Where the water ends either side of `c` across the line through it along `n` (unit): [the edge on the -n side,
## the edge on the +n side], each where the ground first rises DRY over the water. Empty if `c` is dry, or the
## water reaches further than `max_half` either way.
static func water_span(c: Vector2, n: Vector2, max_half := MAX_HALF) -> Array:
	var dry := JungleLayout.WATER_Y + DRY
	if ground(c) >= dry:
		return []
	var out := []
	for s in [-1.0, 1.0]:
		var t := 0.0
		while ground(c + n * s * t) < dry:
			t += 1.0
			if t > max_half:
				return []
		# Bisect onto the edge (to a few cm).
		var lo := t - 1.0
		var hi := t
		for k in 6:
			var m := (lo + hi) * 0.5
			if ground(c + n * s * m) < dry:
				lo = m
			else:
				hi = m
		out.append(c + n * s * hi)
	return out


## Builds the swim links once the navmesh is in the map (JungleLevel): across every river every LINK_EVERY m, and
## LAKE_CHORDS times across the lake.
static func build_links(level: Node3D) -> void:
	for l in links:
		if is_instance_valid(l):
			l.queue_free()
	links.clear()
	var map := level.get_world_3d().navigation_map
	var t0 := Time.get_ticks_msec()
	for r in JungleLayout.RIVERS:
		var c := JungleLayout.river_curve(r[0])
		var run := LINK_EVERY * 0.5
		for i in c.size() - 1:
			var seg := c[i + 1] - c[i]
			var seg_len := seg.length()
			var along := run
			while along < seg_len:
				var p := c[i] + seg * (along / seg_len)
				var d := seg / seg_len
				_try_link(level, map, p, Vector2(-d.y, d.x), MAX_HALF)
				along += LINK_EVERY
			run = along - seg_len
	var lake_c: Vector2 = JungleLayout.LAKE[0]
	var lake_r: Vector2 = JungleLayout.LAKE[1]
	for k in LAKE_CHORDS:
		var a := PI * k / LAKE_CHORDS
		_try_link(level, map, lake_c, Vector2(cos(a), sin(a)), maxf(lake_r.x, lake_r.y) * 1.3)
	print("RiverCrossing: %d swim links in %d ms" % [links.size(), Time.get_ticks_msec() - t0])


static func _try_link(level: Node3D, map: RID, p: Vector2, n: Vector2, max_half: float) -> void:
	var span := water_span(p, n, max_half)
	if span.is_empty():
		return
	var ends: Array[Vector3] = []
	for k in 2:
		var edge: Vector2 = span[k]
		var out := n * (-1.0 if k == 0 else 1.0)
		var land := edge + out * LAND_IN
		var want := Vector3(land.x, ground(land) + 0.3, land.y)
		var snap := LevelBuilder.nav_closest(map, want)
		if Vector2(snap.x - want.x, snap.z - want.z).length() > SNAP_SLACK or absf(snap.y - want.y) > 2.0:
			return
		ends.append(snap)
	# No long stretch of dry land on the way (a spit between two rivers, an island).
	var a := Vector2(ends[0].x, ends[0].z)
	var b := Vector2(ends[1].x, ends[1].z)
	var steps := maxi(int(a.distance_to(b) / 2.0), 1)
	var dry_run := 0.0
	var wet_seen := false
	for s in range(1, steps):
		var q := a.lerp(b, float(s) / steps)
		if ground(q) >= JungleLayout.WATER_Y + DRY:
			if wet_seen:
				dry_run += a.distance_to(b) / steps
		else:
			if dry_run > MAX_DRY_RUN:
				return
			dry_run = 0.0
			wet_seen = true
	var link := NavigationLink3D.new()
	link.name = "SwimLink%d" % links.size()
	link.navigation_layers = NAV_SWIMMERS
	link.bidirectional = true
	link.travel_cost = SWIM_COST
	link.start_position = ends[0]
	link.end_position = ends[1]
	link.set_meta("swim", true)
	level.add_child(link)
	links.append(link)


## The way a swimmer takes across a swim link from `from` to `to`: every 2 m along the line, on the ground where it
## is above swim depth (down the bank and up the far one), floating with its feet `sink` m under the surface where
## the water is deeper.
static func swim_route(from: Vector3, to: Vector3, sink: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var n := maxi(int(flat / 2.0), 1)
	var swim_y := JungleLayout.WATER_Y - sink
	for k in range(1, n + 1):
		var p := from.lerp(to, float(k) / n)
		if k < n:
			p.y = maxf(ground(Vector2(p.x, p.z)), swim_y)
		out.append(p)
	return out


## True if `u` (a unit that rides) should ride across the water to get to `pos`: it can't walk there (no bridge on
## its way), but a swimmer could, or its way on foot is far longer (RIDE_DETOUR) than the way across.
static func needs_ride(u: Node3D, pos: Vector3) -> bool:
	if not active():
		return false
	var map := u.get_world_3d().navigation_map
	var goal := LevelBuilder.nav_closest(map, pos)
	var from := LevelBuilder.nav_closest(map, u.global_position)
	var land := NavigationServer3D.map_get_path(map, from, goal, true, 1)
	var swim := NavigationServer3D.map_get_path(map, from, goal, true, 1 | NAV_SWIMMERS)
	if swim.is_empty() or _flat(swim[-1], goal) > 4.0:
		return false
	if land.is_empty() or _flat(land[-1], goal) > 4.0:
		return true
	return path_length(land) > path_length(swim) * RIDE_DETOUR + RIDE_SLACK


## True if walking (or swimming, with `layers` carrying NAV_SWIMMERS) from `a` gets to within `slack` m of `b`.
static func reaches(ctx: Node3D, a: Vector3, b: Vector3, layers := 1, slack := 4.0) -> bool:
	var map := ctx.get_world_3d().navigation_map
	var goal := LevelBuilder.nav_closest(map, b)
	var path := NavigationServer3D.map_get_path(map, LevelBuilder.nav_closest(map, a), goal, true, layers)
	return not path.is_empty() and _flat(path[-1], goal) <= slack


static func path_length(path: PackedVector3Array) -> float:
	var d := 0.0
	for i in path.size() - 1:
		d += path[i].distance_to(path[i + 1])
	return d


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- effects

## A ring of ripples spreading out over the water from `at` (a swimmer's wake), `size` m across to start.
static func ripple(ctx: Node, at: Vector3, size: float) -> void:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.86
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 3
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.albedo_color = Color(0.85, 0.9, 0.88, 0.55)
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root := ctx.get_tree().current_scene if ctx.get_tree().current_scene else ctx.get_tree().root
	root.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(size, 0.05, size)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(size * 2.6, 0.05, size * 2.6), 1.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, 1.6)
	tw.chain().tween_callback(mi.queue_free)


## Spray thrown up off the water at `at`, `size` m across.
static func splash(ctx: Node, at: Vector3, size: float) -> void:
	if _puff_mat == null:
		_puff_mat = StandardMaterial3D.new()
		_puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_puff_mat.vertex_color_use_as_albedo = true
		_puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_puff_mat.albedo_texture = SmokeCloud.puff_texture()
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9) * maxf(size * 0.5, 0.6)
	q.material = _puff_mat
	p.mesh = q
	p.amount = 24
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.4
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.0, 0)
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.97, 0.97, 0.8))
	g.set_color(1, Color(0.9, 0.93, 0.95, 0.0))
	p.color_ramp = g
	var root := ctx.get_tree().current_scene if ctx.get_tree().current_scene else ctx.get_tree().root
	root.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	ripple(ctx, at + Vector3.UP * 0.03, size)
