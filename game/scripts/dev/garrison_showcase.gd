extends Node3D
## The garrison (Garrison, GarrisonSoldier) on the real map, with nobody attacking: the four spawns put out a soldier
## each every 6 s, the soldiers crew the guns, fill the gun decks and go out to form the perimeter. It prints how long
## each step takes and, with --shots, takes stills along the way.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/garrison_showcase.tscn -- --until=240
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/garrison_showcase.tscn -- --scenario=south --until=300
##   godot --path game --rendering-driver opengl3 --resolution 1600x900 --fixed-fps 30 \
##       res://scenes/dev/garrison_showcase.tscn -- --shots=/tmp/garrison --at=20,60,120,240 [--map=classic]
##       [--views=overview,south_deck,...] (see _view), or --plan=11:spawn_corridor+south_deck,75:north_deck,...
##
## Scenarios (--scenario=):
##   default  one spawn on each side, all BASE (the start of a match).
##   south    all four players move their spawns to the south side (four come out there at once, none elsewhere): the
##            guns on the far (north) side get crews from soldiers spawned at the south.
##   mixed    the defaults, but the east spawn's player sets FIELD and a second player moves onto the south, set to
##            FIELD, while the south's own stays on BASE.
## --until=t runs that long (s of game time) and quits; --test checks the order of things and prints PASS / FAIL.

var level: LevelBuilder
var garrison: Garrison
var cam: Camera3D
var scenario := "default"
var until := 240.0
var until_set := false
var shots_dir := ""
var shot_times: Array = []
var view_names: Array = ["overview", "south_field", "south_deck", "south_gate"]
## --plan: time -> its views (else view_names at every --at time).
var _plan := {}
var test := false
var _last_print := -1.0
var _snapping := false
var _started := false
var _fails := 0
## --attack=t: at t, ATTACK_WAVE Bear Riflemen come at the south gate (attack-move), to see the garrison fight.
const ATTACK_WAVE := 16
var attack_at := -1.0
var _attackers: Node3D
var _wave: Array = []
var _deaths_before := 0


func _ready() -> void:
	# It runs while the rest is paused for a set of stills (all of a set's views show the same moment).
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.get_slice("=", 1)
		elif arg.begins_with("--until="):
			until = arg.get_slice("=", 1).to_float()
			until_set = true
		elif arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--at="):
			shot_times = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--views="):
			view_names = Array(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--plan="):
			# t:view+view,t:view...: each time its own views.
			for part in arg.get_slice("=", 1).split(","):
				var t := part.get_slice(":", 0).to_float()
				shot_times.append(t)
				_plan[t] = Array(part.get_slice(":", 1).split("+"))
		elif arg.begins_with("--attack="):
			attack_at = arg.get_slice("=", 1).to_float()
		elif arg == "--test":
			test = true
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
		if not shot_times.is_empty():
			until = maxf(until, shot_times.max() + 0.5) if until_set else shot_times.max() + 0.5
	level = JungleLevel.new() if GameConfig.map == "jungle" else LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build()
	FX.of(self)
	_attackers = Node3D.new()
	_attackers.name = "Attackers"
	add_child(_attackers)
	# Paused with the rest for a set of stills (this node runs on).
	for c in get_children():
		c.process_mode = Node.PROCESS_MODE_PAUSABLE
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	_plain_sky()
	if shots_dir != "":
		_stills_setup()
	print("GARRISON map=%s scenario=%s until=%.0f" % [GameConfig.map, scenario, until])
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


## Mesa's software GL can't compile the game's sky shader: a plain procedural sky in its place (MachinesShowcase).
func _plain_sky() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.46, 0.74)
	sky_mat.sky_horizon_color = Color(0.74, 0.8, 0.86)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	for we in level.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env:
			env.background_mode = Environment.BG_SKY
			env.sky = sky


func _start() -> void:
	for k in 6:
		await get_tree().physics_frame
	garrison = Garrison.new()
	garrison.name = "Garrison"
	garrison.level = level
	garrison.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(garrison)
	match scenario:
		"south":
			for p in 4:
				garrison.move_spawn(p, "south")
		"mixed":
			garrison.set_priority(1, Garrison.Priority.FIELD)  # the east spawn's player: FIELD
			garrison.move_spawn(3, "south")  # the west's player joins the south ...
			garrison.set_priority(3, Garrison.Priority.FIELD)  # ... spawning for the field
	while not garrison.set_up:
		await get_tree().physics_frame
	var spawns := []
	for side in Garrison.SIDE_ORDER:
		spawns.append("%s=%d" % [side, garrison.spawns_at(side)])
	print("GARRISON start: guns=%d deck_slots=%d field_slots=%d spawns %s" % [garrison.guns.size(),
			garrison.deck_slots.size(), garrison.field_slots.size(), " ".join(spawns)])
	for side in Garrison.SIDE_ORDER:
		var far := []
		for g in garrison.guns:
			far.append(garrison.path_length(garrison._spawn_pos[side], garrison._gun_goals[g]))
		var reach := far.filter(func(d): return d < INF)
		for i in far.size():
			if far[i] == INF and side == "south":
				var g = garrison.guns[i]
				var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, garrison._spawn_pos[side], garrison._gun_goals[g], true, Garrison.NAV_LAYERS)
				print("GARRISON   unreachable: %s at %s goal %s path ends %s" % [g.name, g.global_position, garrison._gun_goals[g],
						path[-1] if not path.is_empty() else "nowhere"])
		print("GARRISON paths from the %s spawn: %d/%d guns reachable, %.0f-%.0f m" % [side, reach.size(), far.size(),
				reach.min() if not reach.is_empty() else -1.0, reach.max() if not reach.is_empty() else -1.0])
	if "--probe" in OS.get_cmdline_user_args():
		await _probe()
		get_tree().quit()
		return
	_started = true


func _plen(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l


func _probe() -> void:
	var map := get_world_3d().navigation_map
	print("PROBE map regions=%d iteration=%d level-region-map-same=%s" % [NavigationServer3D.map_get_regions(map).size(),
			NavigationServer3D.map_get_iteration_id(map), str(level.nav_region.get_navigation_map() == map)])
	print("PROBE region mesh polys=%d" % (level.nav_region.navigation_mesh.get_polygon_count() if level.nav_region.navigation_mesh else -1))
	var probe_p := Vector3(0, 0.5, 120)
	print("PROBE active=%s region-closest=%s map-closest=%s region-enabled=%s xf=%s" % [NavigationServer3D.map_is_active(map),
			NavigationServer3D.region_get_closest_point(level.nav_region.get_rid(), probe_p),
			NavigationServer3D.map_get_closest_point(map, probe_p), level.nav_region.enabled, level.nav_region.global_transform.origin])
	for k in 30:
		await get_tree().physics_frame
	print("PROBE later iteration=%d map-closest=%s" % [NavigationServer3D.map_get_iteration_id(map), NavigationServer3D.map_get_closest_point(map, probe_p)])
	var L := Garrison.NAV_LAYERS
	var spn: Vector3 = garrison._spawn_pos["south"]
	print("PROBE spawn S nav ", spn, " marker ", level.marker("SPAWN_S3").global_position)
	var gate := level.marker("EXIT_C_S3").global_position
	var out := LevelBuilder.nav_closest(map, gate + Vector3(0, 0.5, 10))
	for layers in [1, L]:
		var p := NavigationServer3D.map_get_path(map, spn, out, true, layers)
		print("PROBE spawn->outside layers=%d n=%d end=%s len=%.1f" % [layers, p.size(), p[-1] if p.size() else Vector3.INF, _plen(p)])
	var g = garrison.guns[0]
	var goal: Vector3 = garrison._gun_goals[g]
	print("PROBE gun ", g.name, " at ", g.global_position, " goal ", goal)
	var p2 := NavigationServer3D.map_get_path(map, spn, goal, true, L)
	print("PROBE spawn->gun n=%d len=%.1f" % [p2.size(), _plen(p2)])
	for q in p2:
		print("PROBE    ", q)
	for l in level.find_children("*", "NavigationLink3D", true, false):
		var a: Vector3 = l.global_position + l.start_position
		var b: Vector3 = l.global_position + l.end_position
		if b.y > 14.0 and absf(a.x) < 12.0 and a.z > 50.0:
			var na := LevelBuilder.nav_closest(map, a)
			var nb := LevelBuilder.nav_closest(map, b)
			print("PROBE roof link %s -> %s ; nav at start %s (%.2f) ; nav at end %s (%.2f) enabled=%s layers=%d" % [a, b, na,
					na.distance_to(a), nb, nb.distance_to(b), l.enabled, l.navigation_layers])
	var mort = garrison.guns.filter(func(x): return x.station_kind == "artillery")[0]
	var goal2: Vector3 = garrison._gun_goals[mort]
	var deck := LevelBuilder.nav_closest(map, Vector3(4.8, 8.6, 67.5))
	var pr := NavigationServer3D.map_get_path(map, deck, goal2, true, L)
	print("PROBE deck->mortar from %s n=%d end=%s" % [deck, pr.size(), pr[-1] if pr.size() else Vector3.INF])
	var roof_pt := LevelBuilder.nav_closest(map, Vector3(4.75, 15.5, 67.0))
	var pr2 := NavigationServer3D.map_get_path(map, roof_pt, goal2, true, L)
	print("PROBE roof %s -> mortar goal n=%d end=%s" % [roof_pt, pr2.size(), pr2[-1] if pr2.size() else Vector3.INF])
	var j := level.marker("EXIT_B_S3").global_position
	print("PROBE EXIT_B_S3 ", j, " nav ", LevelBuilder.nav_closest(map, j + Vector3.UP * 0.3))
	for l in level.find_children("*", "NavigationLink3D", true, false).slice(0, 6):
		print("PROBE link layers=%d enabled=%s %s -> %s" % [l.navigation_layers, l.enabled, l.global_position + l.start_position, l.global_position + l.end_position])


func _physics_process(_delta: float) -> void:
	if not _started or _snapping:
		return
	var t := garrison.clock
	if int(t / 10.0) != int(_last_print / 10.0):
		var g := garrison.summary()
		print("GARRISON t=%5.1f alive=%d guns=%d/%d deck=%d/%d field=%d walking=%d (wall %.0f s)" % [t, g.alive, g.guns,
				g.guns_alive, g.deck, g.deck_total, g.field, g.walking, Time.get_ticks_msec() * 0.001])
	_last_print = t
	if attack_at >= 0.0 and t >= attack_at and _wave.is_empty():
		_send_wave()
	if shots_dir != "" and not shot_times.is_empty():
		RenderingServer.render_loop_enabled = t >= shot_times[0] - 0.1
		if t >= shot_times[0] and not _snapping:
			_snap_set(shot_times.pop_front())
	if t >= until and not _snapping:
		_finish()


func _finish() -> void:
	_started = false
	print("GARRISON report (t=%.1f)" % garrison.clock)
	if not _wave.is_empty():
		var left := _wave.filter(func(u): return is_instance_valid(u) and u.is_alive()).size()
		print("GARRISON   attack: %d of %d Bear Riflemen left, %d garrison soldiers lost; garrison rounds %d, longest shot %.1f m" % [
				left, _wave.size(), garrison.stats.deaths - _deaths_before, GarrisonSoldier.shots, GarrisonSoldier.longest_shot])
	for line in garrison.report().split("\n"):
		print("GARRISON   " + line)
	_travel_report()
	if test:
		_checks()
		print("GARRISON SHOWCASE %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit()


## Spawn-to-gun walks, by where the gun is from the spawn's side: the same side, the next side round, the far side.
func _travel_report() -> void:
	var groups := {"same": [], "adjacent": [], "opposite": []}
	for a in garrison.arrivals:
		if a.job != GarrisonSoldier.Job.GUN or not a.fresh:
			continue
		var rel := "same" if a.to_side == a.side else ("opposite" if Garrison.OPPOSITE[a.side] == a.to_side else "adjacent")
		groups[rel].append(a.travel)
	for rel in groups:
		var v: Array = groups[rel]
		if v.is_empty():
			print("GARRISON   gun walks %-8s none" % rel)
			continue
		var sum := 0.0
		for x in v:
			sum += x
		print("GARRISON   gun walks %-8s n=%d spawn->crewing min=%.1f avg=%.1f max=%.1f s" % [rel, v.size(), v.min(),
				sum / v.size(), v.max()])
	var by_side := {}
	for a in garrison.arrivals:
		if a.job == GarrisonSoldier.Job.FIELD:
			by_side[a.to_side] = by_side.get(a.to_side, 0) + 1
	print("GARRISON   field soldiers by side: %s" % str(by_side))
	var first_field := garrison.arrivals.filter(func(a): return a.job == GarrisonSoldier.Job.FIELD)
	if not first_field.is_empty():
		print("GARRISON   first field soldier in place at t=%.1f (spawned %.1f, walked %.1f s)" % [first_field[0].at,
				first_field[0].spawned, first_field[0].travel])


func _send_wave() -> void:
	var gate: Vector3 = level.gates.south.global_position
	_deaths_before = garrison.stats.deaths
	for k in ATTACK_WAVE:
		var u := AttackerUnit.new()
		u.setup("rifleman", 9000 + k)
		_attackers.add_child(u)
		var at := Vector3(gate.x + (k % 8 - 3.5) * 3.0, 0.0, gate.z + 75.0 + (k / 8) * 4.0)
		at.y = LevelBuilder.ground_height(at) + 0.3
		u.global_position = at
		u.set_order({"type": "attack_move", "pos": gate + Vector3(0, 0, 6)})
		_wave.append(u)
	print("GARRISON t=%.1f attack: %d Bear Riflemen at the south gate" % [garrison.clock, ATTACK_WAVE])


func _check(ok: bool, what: String) -> void:
	print("GARRISON CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _checks() -> void:
	var st := garrison.stats
	_check(st.all_guns_manned > 0.0, "every gun crewed (%.1f s)" % st.all_guns_manned)
	if scenario == "default":
		_check(st.deck_full > 0.0, "every deck spot held (%.1f s)" % st.deck_full)
		_check(st.first_base_field_job >= st.all_guns_claimed, "nobody sent to the field before every gun was claimed")
		_check(st.first_outside > 0.0, "soldiers out on the field (%.1f s)" % st.first_outside)
	if not _wave.is_empty():
		var left := _wave.filter(func(u): return is_instance_valid(u) and u.is_alive()).size()
		_check(left < _wave.size(), "the garrison fought the attack off (%d of %d left)" % [left, _wave.size()])
		_check(GarrisonSoldier.shots > 0 and GarrisonSoldier.longest_shot <= DefenderSoldier.AI_RANGE + 0.5,
				"no garrison round fired from beyond %.0f m (longest %.1f m)" % [DefenderSoldier.AI_RANGE, GarrisonSoldier.longest_shot])
	for g in garrison.guns:
		_check(g.is_manned(), "%s crewed" % g.name)
	var on_deck := garrison.soldiers.filter(func(s): return s.job == GarrisonSoldier.Job.DECK)
	_check(on_deck.size() <= garrison.deck_slots.size(), "the decks hold no more than %d" % garrison.deck_slots.size())
	var field := garrison.soldiers.filter(func(s): return s.job == GarrisonSoldier.Job.FIELD and s.arrived)
	var close := 0
	for a in field:
		for b in field:
			if a != b and a.global_position.distance_to(b.global_position) < 2.0:
				close += 1
	_check(close == 0, "no two field soldiers within 2 m of each other")


# ---------------------------------------------------------------- stills

## Software GL (no GPU): a lighter shadow map, no multisampling, thinner haze, and the helipads' name tags (drawn
## through the mountain) hidden, so the stills show the soldiers.
func _stills_setup() -> void:
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	for we in level.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env:
			env.fog_density *= 0.25
			env.volumetric_fog_enabled = false
	for l in level.find_children("*", "Label3D", true, false):
		(l as Label3D).visible = false


func _snap_set(at: float) -> void:
	_snapping = true
	get_tree().paused = true
	for name in _plan.get(at, view_names):
		var v: Array = _view(name)
		_look(v[0], v[1])
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_t%03d_%s.png" % [shots_dir, scenario, int(at), name]
		get_viewport().get_texture().get_image().save_png(path)
		print("GARRISON shot %s" % path)
	RenderingServer.render_loop_enabled = false
	get_tree().paused = false
	_snapping = false


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)


## [eye, look-at] of a still (--views=): the south face's middle is at x = 0, its front at z = 78, its gun deck 8 m
## up at z of about 70; the gate is at x = -4. The other faces are the same turned round the middle.
func _view(name: String) -> Array:
	match name:
		"overview":
			return [Vector3(175, 120, 250), Vector3(-5, 0, 45)]
		"overview_high":
			return [Vector3(0, 300, 330), Vector3(0, 0, 30)]
		"south_field":
			return [Vector3(38, 20, 138), Vector3(-6, 0, 101)]
		"south_field_wide":
			return [Vector3(95, 55, 205), Vector3(-5, 0, 100)]
		"south_deck":
			return [Vector3(-30.5, 12.5, 74.5), Vector3(-2, 8.4, 69.5)]
		"south_deck_front":
			return [Vector3(-12, 15, 92), Vector3(-4, 8.8, 70)]
		"south_gate":
			return [Vector3(16, 6, 104), Vector3(-4, 1.5, 80)]
		"east_field":
			return [Vector3(138, 20, -38), Vector3(101, 0, 6)]
		"north_deck":
			return [Vector3(30.5, 12.5, -74.5), Vector3(2, 8.4, -69.5)]
		"west_deck":
			return [Vector3(-74.5, 12.5, -30.5), Vector3(-69.5, 8.4, -2)]
		"spawn_corridor":
			# Down the corridor from the core toward the south spawn hall: the south spawn point is about 8 m in.
			return [Vector3(0.9, 2.6, 38), Vector3(0, 1.0, 58)]
	return [Vector3(0, 200, 300), Vector3.ZERO]
