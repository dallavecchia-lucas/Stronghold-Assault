extends Node3D
## The garrison (Garrison, GarrisonSoldier) on the real map, with nobody attacking: the four spawns put out a soldier
## each every 6 s, the soldiers crew the guns, fill the gun decks and go out to form the perimeter. It prints how long
## each step takes and, with --shots, takes stills along the way.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/garrison_showcase.tscn -- --until=240
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/garrison_showcase.tscn -- --scenario=south --until=300
##   godot --path game --rendering-driver opengl3 --resolution 1600x900 --fixed-fps 30 \
##       res://scenes/dev/garrison_showcase.tscn -- --shots=/tmp/garrison --at=20,60,120,240
##       [--views=overview,south_deck,...] (see _view), or --plan=11:spawn_corridor+south_deck,75:north_deck,...
##
## Scenarios (--scenario=):
##   default  one spawn on each side, all BASE (the start of a match).
##   south    all four players move their spawns to the south side (four come out there at once, none elsewhere): the
##            guns on the far (north) side get crews from soldiers spawned at the south.
##   mixed    the defaults, but the east spawn's player sets FIELD and a second player moves onto the south, set to
##            FIELD, while the south's own stays on BASE.
## --until=t runs that long (s of game time) and quits; --test checks the order of things and prints PASS / FAIL.
## --film=view:from:to films one view (see _view) from `from` to `to` s of game time, for --write-movie: nothing is
## drawn before `from` (the run up to it goes at the simulation's pace), and it prints the frames to keep for
## tools/video/cut_showcase.py (VIDEO START / END). With --attack= before it, that is the gun decks at work:
##   godot --path game --resolution 960x540 --write-movie decks.avi --fixed-fps 30 res://scenes/dev/garrison_showcase.tscn \
##       -- --attack=78 --film=south_deck_front:80:90 --lighting=standard > decks.log

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
## A line of fire that meets something within this of the face's front (m, out from it) hit the stronghold: the rock's foot
## is 2.2 m out.
const WALL_ZONE := 3.0
## Down to this depression (degrees) every deck gun's shot, straight out or 20 degrees either side, lands on the field.
const CLEAR_TO := 30
## --attack=t: at t, ATTACK_WAVE Bear Riflemen come at the south gate (attack-move), to see the garrison fight.
const ATTACK_WAVE := 16
var attack_at := -1.0
## --film: the view filmed, from when to when (s of game time), and the movie's frame count as it goes.
var _film := ""
var _film_from := 0.0
var _film_to := 0.0
var _film_on := false
var _frame := 0
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
		elif arg.begins_with("--film="):
			var parts := arg.get_slice("=", 1).split(":")
			_film = parts[0]
			_film_from = parts[1].to_float()
			_film_to = parts[2].to_float()
			until = _film_to
		elif arg == "--test":
			test = true
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
		if not shot_times.is_empty():
			until = maxf(until, shot_times.max() + 0.5) if until_set else shot_times.max() + 0.5
	level = JungleLevel.new()
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
	if _film != "":
		RenderingServer.render_loop_enabled = false  # nothing to see until the film starts
		_stills_setup()
		var v: Array = _view(_film)
		_look(v[0], v[1])
	print("GARRISON scenario=%s until=%.0f" % [scenario, until])
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


## --probe: every deck gun's lines of fire (_fire_lines): at each depression, how many land on the field and how many hit
## the parapet or the rock under the deck.
func _probe() -> void:
	var lines := _fire_lines()
	var by_pitch := {}
	for r in lines:
		var row: Dictionary = by_pitch.get(r.pitch, {"field": 0, "parapet": 0, "rock": 0})
		row[r.what] += 1
		by_pitch[r.pitch] = row
	for pitch in by_pitch:
		var row: Dictionary = by_pitch[pitch]
		print("PROBE pitch -%d: field %d, parapet %d, rock %d (of %d)" % [pitch, row.field, row.parapet, row.rock,
				row.field + row.parapet + row.rock])
	var straight := lines.filter(func(r): return r.yaw == 0 and r.clear)
	var nearest := 1e9
	for r in straight:
		nearest = minf(nearest, r.out)
	print("PROBE straight out, the steepest clear shot lands %.1f m past the face's front" % nearest)

## For every gun on the gun decks, the line of fire from its muzzle straight out and 20 degrees either
## side, level and at every 5 degrees down to its lowest aim (MountedGun.PITCH_MIN): where it first meets the world.
## clear: it gets past the stronghold, rather than meeting the parapet, the deck or the rock under it (anything within
## WALL_ZONE of the face's front; further out it is the field, or the scenery out on it: a tree, a rock).
func _fire_lines() -> Array:
	var out := []
	var space := get_world_3d().direct_space_state
	for g in garrison.guns:
		if not (g is MountedGun) or not (g.kind in ["sentry", "cannon"]):
			continue
		var side := Garrison.side_of(g.global_position)
		var face_dir: Vector3 = LevelBuilder.SIDES[side].dir
		var pivot: Vector3 = g.to_global(Vector3(0.0, g.pivot_height, 0.0))
		var reach := 2.0 if g.kind == "cannon" else 1.42
		for yaw in [-20, 0, 20]:
			var pitch := 0
			while pitch <= int(rad_to_deg(-MountedGun.PITCH_MIN)):
				var dir: Vector3 = g.global_basis * (Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch)) * Vector3.FORWARD)
				var from: Vector3 = pivot + dir * reach
				var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, GameConfig.LAYER_WORLD)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					var p: Vector3 = hit.position
					var past := p.dot(face_dir) - LevelBuilder.FACE_DIST
					var on_field := past > WALL_ZONE
					# What it hit, if not the field: the parapet (or the deck, at or above the deck's height) or the rock
					# below the deck.
					var deck_y: float = g.global_position.y - LevelBuilder.DECK_PLATFORM_H
					var what := "field" if on_field else ("parapet" if p.y > deck_y - 0.3 else "rock")
					out.append({"gun": String(g.name), "yaw": yaw, "pitch": pitch, "clear": on_field, "out": past, "y": p.y,
							"along": p.dot(face_dir.cross(Vector3.UP)), "from": from, "to": p, "what": what})
				pitch += 5
	return out


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
	if _film != "" and not _film_on and t >= _film_from:
		_film_on = true
		RenderingServer.render_loop_enabled = true
		print("VIDEO START frame %d" % (_frame + 1))  # (this tick's frame is the first drawn; the next is sure to be)
	if shots_dir != "" and not shot_times.is_empty():
		RenderingServer.render_loop_enabled = t >= shot_times[0] - 0.1
		if t >= shot_times[0] and not _snapping:
			_snap_set(shot_times.pop_front())
	if t >= until and not _snapping:
		_finish()


func _process(_delta: float) -> void:
	_frame += 1


func _finish() -> void:
	_started = false
	if _film != "":
		print("VIDEO END frame %d" % (_frame - 1))
	print("GARRISON report (t=%.1f)" % garrison.clock)
	if not _wave.is_empty():
		var left := _wave.filter(func(u): return is_instance_valid(u) and u.is_alive()).size()
		print("GARRISON   attack: %d of %d Bear Riflemen left, %d garrison soldiers lost; garrison rounds %d, longest shot %.1f m" % [
				left, _wave.size(), garrison.stats.deaths - _deaths_before, GarrisonSoldier.shots, GarrisonSoldier.longest_shot])
	for line in garrison.report().split("\n"):
		print("GARRISON   " + line)
	_travel_report()
	_stragglers()
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


## Whatever is still without its soldier, and where that soldier is (to see why).
func _stragglers() -> void:
	for g in garrison.guns:
		if g.is_manned():
			continue
		var c = garrison.claims.get(g)
		if c == null or not is_instance_valid(c):
			print("GARRISON   unmanned %s: nobody coming" % g.name)
			continue
		print("GARRISON   unmanned %s at %s: %s at %s goal %s arrived=%s route=%d since %.1f s" % [g.name, g.global_position,
				c.name, c.global_position, c.goal, c.arrived, c.get("_route").size(), garrison.clock - c.assigned_at])
	for i in garrison.deck_slots.size():
		var d: Dictionary = garrison.deck_slots[i]
		var h = d.holder
		if h != null and is_instance_valid(h) and h.arrived:
			continue
		print("GARRISON   deck spot %d (%s) at %s: %s" % [i, d.side, d.pos, "nobody" if h == null or not is_instance_valid(h) else
				"%s at %s since %.1f s" % [h.name, h.global_position, garrison.clock - h.assigned_at]])


func _check(ok: bool, what: String) -> void:
	print("GARRISON CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _checks() -> void:
	var st := garrison.stats
	var all_base := scenario != "mixed"  # with half the spawns on FIELD the base fills slowly
	if all_base:
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
		if all_base:
			_check(g.is_manned(), "%s crewed" % g.name)
		if g.is_manned() and g.crew != null and g.has_method("has_seat") and g.has_seat():
			var gap: float = g.crew.global_position.distance_to((g.crew_spot() as Transform3D).origin)
			_check(gap < 1.2, "%s's crew sits in its seat" % g.name)
	# The deck guns stand just over the parapet: nothing they fire meets the parapet, and down to CLEAR_TO degrees every
	# shot gets past the rock under the deck too (steeper, straight down the face, it meets the rock).
	var lines := _fire_lines()
	var parapet := lines.filter(func(r): return r.what == "parapet")
	var rock := lines.filter(func(r): return r.what == "rock" and r.pitch <= CLEAR_TO)
	_check(not lines.is_empty() and parapet.is_empty(), "no deck gun's shot meets the parapet, level to %d degrees down (%d lines)" % [
			int(rad_to_deg(-MountedGun.PITCH_MIN)), lines.size()])
	_check(rock.is_empty(), "every deck gun's shot clears the rock under the deck down to %d degrees%s" % [CLEAR_TO,
			"" if rock.is_empty() else " (%s yaw %d pitch -%d hits it)" % [rock[0].gun, rock[0].yaw, rock[0].pitch]])
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
		if v.is_empty():
			print("GARRISON shot %s: nothing to see" % name)
			continue
		_show_fire(name == "fire_lines")
		_look(v[0], v[1])
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_t%03d_%s.png" % [shots_dir, scenario, int(at), name]
		get_viewport().get_texture().get_image().save_png(path)
		print("GARRISON shot %s" % path)
	RenderingServer.render_loop_enabled = false
	get_tree().paused = false
	_snapping = false


## The south deck guns' lines of fire straight out at 20, 30 and 40 degrees down, from the muzzle to where each lands,
## drawn as thin bright rods for the fire_lines still (green: it lands on the field; red: it meets the stronghold).
var _fire_rods: Array[Node3D] = []


func _show_fire(on: bool) -> void:
	if on and _fire_rods.is_empty():
		for r in _fire_lines():
			if r.yaw != 0 or not (r.pitch in [20, 30, 40]) or not String(r.gun).begins_with("MG_S"):
				continue
			var rod := Mats.box_mesh(Vector3(0.09, 0.09, r.from.distance_to(r.to)), Vector3.ZERO,
					Mats.unshaded(Color(0.25, 1.0, 0.35) if r.clear else Color(1.0, 0.2, 0.15)))
			add_child(rod)
			rod.look_at_from_position((r.from + r.to) * 0.5, r.to)
			_fire_rods.append(rod)
	for rod in _fire_rods:
		rod.visible = on


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)


## [eye, look-at] of a still (--views=): the south face's middle is at x = 0, its front at z = 78 (seven bays from
## x = -42 to 42, their middles 12 m apart), its gun deck 8 m up at z of about 70, its roof 15 m up; the gate is at
## x = -4. The other faces are the same turned round the middle.
func _view(name: String) -> Array:
	match name:
		"fire_lines":
			# The south deck's lines of fire (_show_fire), seen from out in front and to the east, the face in profile.
			return [Vector3(34, 17, 100), Vector3(-8, 6.5, 76)]
		"overview":
			return [Vector3(175, 120, 250), Vector3(-5, 0, 45)]
		"overview_high":
			return [Vector3(0, 300, 330), Vector3(0, 0, 30)]
		"south_field":
			return [Vector3(38, 20, 138), Vector3(-6, 0, 101)]
		"south_field_wide":
			return [Vector3(95, 55, 205), Vector3(-5, 0, 100)]
		"south_deck":
			return [Vector3(-44.5, 12.5, 74.5), Vector3(-14, 8.4, 69.5)]
		"deck_bay":
			# Bay 3 of the south deck (its middle at x = -12): the sentry gun at -15 and the cannon at -9, their seats
			# facing each other across the bay, seen from the deck's back wall.
			return [Vector3(-4.5, 12.2, 66.6), Vector3(-12.5, 8.7, 70.8)]
		"deck_ramp":
			# Bay 3's platform from the walkway behind it: the ramp up its middle between the two guns' seats.
			return [Vector3(-7.0, 12.6, 66.6), Vector3(-12.0, 8.9, 71.0)]
		"deck_bay_front":
			return [Vector3(-6, 13.5, 83), Vector3(-12, 8.9, 70.5)]
		"roof":
			return [Vector3(-27, 22.5, 82), Vector3(-10, 15.5, 68.5)]
		"face_front":
			return [Vector3(0, 26, 150), Vector3(0, 9, 72)]
		"south_deck_front":
			return [Vector3(-12, 15, 92), Vector3(-4, 8.8, 70)]
		"south_gate":
			return [Vector3(16, 6, 104), Vector3(-4, 1.5, 80)]
		"east_field":
			return [Vector3(138, 20, -38), Vector3(101, 0, 6)]
		"north_deck":
			return [Vector3(44.5, 12.5, -74.5), Vector3(14, 8.4, -69.5)]
		"west_deck":
			return [Vector3(-74.5, 12.5, -44.5), Vector3(-69.5, 8.4, -14)]
		"spawn_corridor":
			# Down the corridor from the core toward the south spawn hall: the south spawn point is about 8 m in.
			return [Vector3(0.9, 2.6, 38), Vector3(0, 1.0, 58)]
	return [Vector3(0, 200, 300), Vector3.ZERO]
