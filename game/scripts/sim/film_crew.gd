extends Node
## The film crew of a simulated match (`--film=<dir>`, with `--sim=`): it watches the CPU-vs-CPU match for moments worth
## seeing, and films the best of them. Nothing is drawn while nothing is filmed (RenderingServer.render_loop_enabled off),
## so the match runs about as fast as headless; for a moment the drawing goes on, a camera is put on the action (low,
## three-quarter, pushing in and drifting round it, tracking its subject) and every frame is saved as a JPEG while the
## match advances exactly 1/30 s a frame (Engine.time_scale), so the clip plays at true speed at 30 fps. Then the drawing
## goes off again and the match runs on. tools/film_cut.py turns the frames into .mp4s and an index.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <variant> --resolution 1280x720 --fixed-fps 10 -- \
##       --sim=m.json --atk=mass --def=default --seed=1 --sim-ticks=30 --lighting=standard --no-msaa \
##       --film=/tmp/stronghold-balance/clips/run1 [--film-clips=10] [--film-gap=45] [--film-len=8] [--film-tag=rigged]
##
## Each clip is a folder <dir>/<name>/ of frames (00000.jpg ...) and a meta.json; <dir>/moments.json lists them all.

## Seconds of game time between two clips (a rare moment, priority >= RARE, waits only a quarter of it).
var gap := 45.0
var max_clips := 10
## Seconds a clip lasts (some kinds scale it).
var clip_len := 8.0
## No clip before this many seconds of match.
var start_after := 25.0
var tag := ""
var out_dir := ""
var jpg_quality := 0.9
## Frames a second of the clips (the match advances 1/fps s a frame while filming).
var fps := 30.0
## Frames drawn with the world all but frozen before a clip's first saved frame (shadows, exposure, the TAA settle).
const WARMUP := 5
const RARE := 60
## Priorities of the moments: rare ones win.
const PRIO := {"vent_down": 100, "gate_down": 100, "raider_inside": 95, "ram_charge": 85, "gate_hit": 70,
		"helipad_sabotaged": 70, "jet_bomb_run": 65, "bridge_fallen": 60, "talon_bomb_run": 58, "bridge_drop": 55,
		"drone_swarm": 48, "artillery": 46, "elephant_swim": 44, "raft_crossing": 40, "swim_crossing": 38,
		"flame_burning": 36, "bridge_crossing": 42, "firefight": 30, "squad_lost": 26}
## Clips of one kind already filmed lower its priority by this much each, for variety.
const REPEAT_PENALTY := 18
const POLL := 1.0

var sim: Node
var match_node: Node
var level: LevelBuilder
var commander: AttackerCommander
var cam: Camera3D
var clips: Array = []
var counts := {}
var queued: Array = []

var _poll_cd := 2.0
var _last_end := -INF
var _base_dt := 0.0
var _shot := {}
var _frame := 0
var _gate_hp := {}
var _jet_bombs := {}
var _flame_trees := {}
var _wall0 := 0
## `--film-bench`: at the first moment, frames are timed with the costly features turned off one after another.
var bench := false
var _benching := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--film-clips="):
			max_clips = v.to_int()
		elif arg.begins_with("--film-gap="):
			gap = v.to_float()
		elif arg.begins_with("--film-len="):
			clip_len = v.to_float()
		elif arg.begins_with("--film-start="):
			start_after = v.to_float()
		elif arg.begins_with("--film-tag="):
			tag = v
		elif arg.begins_with("--film-fps="):
			fps = maxf(v.to_float(), 1.0)
		elif arg == "--film-bench":
			bench = true
		elif arg == "--no-msaa":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	DirAccess.make_dir_recursive_absolute(out_dir)
	match_node = sim.match_node
	level = sim.level
	commander = sim.commander
	if match_node.ui:
		match_node.ui.visible = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 1200.0
	add_child(cam)
	cam.current = true
	commander.bridge_ordered.connect(func(b): _offer("bridge_drop", b, "an airdropped bridge unfolds over the river"))
	commander.bridge_fallen.connect(func(b): _offer("bridge_fallen", b, "a bridge is brought down"))
	for side in level.gates:
		_gate_hp[side] = level.gates[side].hp
	RenderingServer.frame_post_draw.connect(_on_drawn)
	print("FILM crew ready -> %s (clips %d, gap %.0f s, %.0f s each)" % [out_dir, max_clips, gap, clip_len])


## A SimDirector event (SimDirector._event): the ones worth a clip are offered.
func on_event(type: String, more: Dictionary) -> void:
	match type:
		"gate_down":
			_offer("gate_down", level.gates.get(more.side), "the %s gate falls" % more.side)
		"vent_down":
			for v in level.vents:
				if v.display_name == more.vent:
					_offer("vent_down", v, "%s destroyed, %d left" % [more.vent, more.left])
		"helipad_sabotaged":
			for b in level.bases:
				if b.display_name == more.base:
					_offer("helipad_sabotaged", b, "infiltrators sabotage %s" % more.base)
		"raider_inside":
			for u in commander.units.values():
				if u.raiding:
					_offer("raider_inside", u, "a %s raids inside the stronghold" % u.stats.name)
					break


func _offer(kind: String, subject, desc: String, prio := -1, extra := {}) -> void:
	if subject == null or not is_instance_valid(subject):
		return
	var m := {"kind": kind, "subject": subject, "desc": desc, "t": sim.clock,
			"prio": (PRIO.get(kind, 20) if prio < 0 else prio) - REPEAT_PENALTY * int(counts.get(kind, 0))}
	m.merge(extra)
	queued.append(m)


func _process(delta: float) -> void:
	if match_node.finished:
		return
	if _benching:
		return
	if not _shot.is_empty():
		_film_step()
		return
	if Engine.time_scale == 1.0:
		_base_dt = delta
	_poll_cd -= delta
	if _poll_cd > 0.0:
		return
	_poll_cd = POLL
	_poll()
	queued = queued.filter(func(m): return sim.clock - m.t < 3.0 and is_instance_valid(m.subject))
	if clips.size() >= max_clips or sim.clock < start_after or queued.is_empty():
		return
	queued.sort_custom(func(a, b): return a.prio > b.prio)
	var best: Dictionary = queued[0]
	var wait := gap * (0.25 if best.prio >= RARE else 1.0)
	if sim.clock - _last_end < wait or best.prio < 15:
		return
	queued.clear()
	_start(best)


## The cheap looks at the battlefield, once a game second.
func _poll() -> void:
	var cells := {}
	for u in commander.units.values():
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var p: Vector3 = u.global_position
		if u.raiding:
			_offer("raider_inside", u, "a %s raids inside the stronghold" % u.stats.name)
		if u.is_ramming():
			_offer("ram_charge", u, "a Breaching Ram charges the gate (%s)" % _place(p))
		if u.on_run() and u.has_bomb():
			_offer("talon_bomb_run", u, "a Sky Talon dives on a bomb run")
		if u.is_bombarding():
			_offer("artillery", u, "a %s fires on the stronghold" % u.stats.name)
		if u.is_swimming() and u.in_water():
			if u.type_id == "elephant":
				_offer("elephant_swim", u, "a War Elephant swims the river")
			else:
				_offer("swim_crossing", u, "a %s swims the river" % u.stats.name)
		elif u.is_riding() and u.in_water():
			_offer("raft_crossing", u, "a %s rides a raft across the river" % u.stats.name)
		for b in commander.bridges:
			if is_instance_valid(b) and b.global_position.distance_to(p) < 30.0 and not u.is_flying():
				_offer("bridge_crossing", u, "a %s crosses an airdropped bridge" % u.stats.name)
				break
		var hot: bool = u.get("_since_hurt") < 2.0 or (u.target != null and is_instance_valid(u.target))
		if hot and not u.is_flying():
			var key := Vector2i(floori(p.x / 35.0), floori(p.z / 35.0))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(u)
	var best: Array = []
	for k in cells:
		if cells[k].size() > best.size():
			best = cells[k]
	if best.size() >= 5:
		# The unit nearest the middle of the fight carries the camera.
		var c := Vector3.ZERO
		for u in best:
			c += u.global_position
		c /= best.size()
		best.sort_custom(func(a, b): return a.global_position.distance_to(c) < b.global_position.distance_to(c))
		_offer("firefight", best[0], "%d attackers in a firefight" % best.size(), PRIO.firefight + mini(best.size(), 25))
	for side in level.gates:
		var g: Structure = level.gates[side]
		if g.hp < float(_gate_hp[side]) - 300.0 and g.hp > 0.0:
			_offer("gate_hit", g, "the %s gate under fire (%d hp)" % [side, int(g.hp)])
		_gate_hp[side] = g.hp
	var armory: DefenderArmory = sim.armory
	for s in armory.squads:
		if not is_instance_valid(s):
			continue
		var kind := AIDefender.kind_of(s)
		if s is DefenderJet:
			var was: int = _jet_bombs.get(s.get_instance_id(), s.bombs)
			if s.bombs < was or s.salvo_left > 0:
				_offer("jet_bomb_run", s, "the Fighter Jet makes a bomb run")
			_jet_bombs[s.get_instance_id()] = s.bombs
		elif s is FlameSquad:
			var n: int = s.stats.get("trees", 0)
			if n > int(_flame_trees.get(s.get_instance_id(), n)) and s.leader:
				_offer("flame_burning", s.leader, "the Flame Squad burns the forest")
			_flame_trees[s.get_instance_id()] = n
	var drones: DroneBay = match_node.drones
	if drones:
		for sw in drones.swarms:
			if is_instance_valid(sw) and sw.focus != null and is_instance_valid(sw.focus) and sw.airborne_count() >= 3:
				_offer("drone_swarm", sw.focus, "a drone swarm (%d up) dives on a %s" % [sw.airborne_count(),
						sw.focus.stats.name if sw.focus is AttackerUnit else sw.focus.name])
				break


# --- filming ---------------------------------------------------------------------------------------------------------

## Distance, height above the subject, aim height, push-in and orbit (degrees over the clip), clip length factor, by kind.
func _style(kind: String) -> Dictionary:
	match kind:
		"bridge_drop", "bridge_fallen":
			return {"d": 55.0, "h": 9.0, "aim": 4.0, "push": 0.15, "orbit": 14.0, "len": 1.3}
		"gate_down", "gate_hit", "vent_down":
			return {"d": 32.0, "h": 7.0, "aim": 5.0, "push": 0.2, "orbit": 12.0, "len": 1.0}
		"ram_charge":
			return {"d": 16.0, "h": 3.0, "aim": 1.5, "push": 0.1, "orbit": 10.0, "len": 0.8}
		"talon_bomb_run", "jet_bomb_run":
			return {"d": 40.0, "h": 4.0, "aim": 0.0, "push": 0.0, "orbit": 0.0, "len": 0.8, "flyer": true}
		"drone_swarm":
			return {"d": 20.0, "h": 4.0, "aim": 3.0, "push": 0.15, "orbit": 15.0, "len": 0.9}
		"artillery":
			return {"d": 14.0, "h": 3.0, "aim": 1.5, "push": 0.15, "orbit": 18.0, "len": 0.9}
		"elephant_swim", "swim_crossing", "raft_crossing", "bridge_crossing":
			return {"d": 20.0, "h": 3.5, "aim": 1.5, "push": 0.15, "orbit": 12.0, "len": 1.0}
		"flame_burning":
			return {"d": 24.0, "h": 4.5, "aim": 2.0, "push": 0.15, "orbit": 15.0, "len": 0.9}
		_:
			return {"d": 22.0, "h": 4.0, "aim": 1.5, "push": 0.2, "orbit": 12.0, "len": 1.0}


func _pos(n) -> Vector3:
	return n.global_position if is_instance_valid(n) else Vector3.INF


func _start(m: Dictionary) -> void:
	var st := _style(m.kind)
	var at := _pos(m.subject)
	# The camera's side: three-quarter, looking from the keep's side outward at attackers (the forest behind them) or
	# from outside toward the keep at the stronghold's things; the clearest of 16 bearings near that.
	var out := Vector3(at.x, 0.0, at.z).normalized()
	if out == Vector3.ZERO:
		out = Vector3.BACK
	var keep_thing: bool = m.kind in ["gate_down", "gate_hit", "vent_down", "ram_charge", "raider_inside", "artillery"]
	var pref := (-out if not keep_thing else out).rotated(Vector3.UP, deg_to_rad(35.0))
	var best_az := 0.0
	var best_score := -INF
	for i in 16:
		var az := atan2(pref.x, pref.z) + TAU * i / 16.0
		var score := -absf(angle_difference(az, atan2(pref.x, pref.z))) * 3.0 - _blocked(at, az, st.d, st.h) * 10.0
		if score > best_score:
			best_score = score
			best_az = az
	var name_ := "%02dm%02d_%s_%s" % [int(sim.clock) / 60, int(sim.clock) % 60, _place(at).replace(" ", "_"), m.kind]
	var dir := out_dir.path_join(name_)
	DirAccess.make_dir_recursive_absolute(dir)
	_shot = {"m": m, "st": st, "az": best_az, "dir": dir, "name": name_, "pivot": at, "look": at + Vector3(0, st.aim, 0),
			"t0": sim.clock, "len": clip_len * st.len, "frames": 0, "wall0": Time.get_ticks_msec(), "blocked": _blocked(at, best_az, st.d, st.h),
			"place": _place(at), "in_shot": _in_shot(at), "at": [snappedf(at.x, 0.1), snappedf(at.z, 0.1)],
			"last": at, "orbit_sign": 1.0 if randf() < 0.5 else -1.0}
	_frame = -WARMUP
	# Floating labels (the helos' cargo, names) are the players' HUD, not the scene's.
	for n in get_tree().root.find_children("*", "Label3D", true, false):
		n.visible = false
	counts[m.kind] = int(counts.get(m.kind, 0)) + 1
	RenderingServer.render_loop_enabled = true
	Engine.time_scale = 0.001
	_place_camera(0.0)
	if bench:
		bench = false
		_run_bench()
	print("FILM %6.1f start %s: %s (prio %d, blocked %.1f)" % [sim.clock, name_, m.desc, m.prio, _shot.blocked])


## How much of the view from bearing `az` at `d` m and `h` m up is in the way (terrain, tree trunks, crowns).
func _blocked(at: Vector3, az: float, d: float, h: float) -> float:
	var c := at + Vector3(sin(az), 0.0, cos(az)) * d
	c.y = maxf(LevelBuilder.ground_height(c) + 1.5, at.y + h)
	var bad := 0.0
	for i in range(1, 10):
		var p := c.lerp(at + Vector3(0, 1.5, 0), i / 10.0)
		if LevelBuilder.ground_height(p) > p.y - 0.3:
			bad += 1.0
	for tr in ForestTree.standing:
		if not is_instance_valid(tr):
			continue
		var tp: Vector3 = tr.global_position
		if absf(tp.x - c.x) > d + 10.0 or absf(tp.z - c.z) > d + 10.0:
			continue
		var flat := Vector2(tp.x, tp.z)
		var a := Vector2(c.x, c.z)
		var b := Vector2(at.x, at.z)
		var q := Geometry2D.get_closest_point_to_segment(flat, a, b)
		var dd := q.distance_to(flat)
		if flat.distance_to(a) < 9.0:
			bad += 3.0  # the camera in (or under) a crown
		elif dd < 2.5 and flat.distance_to(b) > 4.0:
			bad += 1.0
	return bad


func _place_camera(dt: float) -> void:
	var st: Dictionary = _shot.st
	var k := clampf((sim.clock - _shot.t0) / maxf(_shot.len, 0.1), 0.0, 1.0)
	var p := _pos(_shot.m.subject)
	if p == Vector3.INF:
		p = _shot.last
	_shot.last = p
	var flyer: bool = st.get("flyer", false)
	var w := 1.0 - exp(-2.5 * dt) if dt > 0.0 else 1.0
	if not flyer:
		_shot.pivot = _shot.pivot.lerp(p, w)
	_shot.look = _shot.look.lerp(p + Vector3(0, st.aim, 0), 1.0 - exp(-4.0 * dt) if dt > 0.0 else 1.0)
	var az: float = _shot.az + deg_to_rad(st.orbit) * k * _shot.orbit_sign
	var d: float = st.d * (1.0 - st.push * k)
	var pivot: Vector3 = _shot.pivot
	var c := pivot + Vector3(sin(az), 0.0, cos(az)) * d
	c.y = maxf(LevelBuilder.ground_height(c) + 1.5, pivot.y + st.h)
	cam.global_position = c
	if c.distance_to(_shot.look) > 0.5:
		cam.look_at(_shot.look, Vector3.UP)


func _film_step() -> void:
	if _frame == 0:
		Engine.time_scale = (1.0 / fps) / maxf(_base_dt, 0.001)
		_shot.t0 = sim.clock
	_place_camera(1.0 / fps if _frame > 0 else 0.0)
	if _frame >= 0 and sim.clock - _shot.t0 >= _shot.len:
		_stop()
		return
	_frame += 1


func _on_drawn() -> void:
	if _shot.is_empty() or _frame <= 0:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(_shot.dir.path_join("%05d.jpg" % (_frame - 1)), jpg_quality)
	_shot.frames += 1


func _stop() -> void:
	RenderingServer.render_loop_enabled = false
	Engine.time_scale = 1.0
	_last_end = sim.clock
	var wall := (Time.get_ticks_msec() - int(_shot.wall0)) / 1000.0
	var m: Dictionary = _shot.m
	var meta := {"name": _shot.name, "kind": m.kind, "desc": m.desc, "t": snappedf(_shot.t0, 0.1),
			"clock": "%02d:%02d" % [int(_shot.t0) / 60, int(_shot.t0) % 60], "len": snappedf(_shot.len, 0.1),
			"place": _shot.place, "at": _shot.at, "in_shot": _shot.in_shot, "frames": _shot.frames, "fps": fps, "prio": m.prio,
			"tag": tag, "rigged": tag.contains("rigged"), "blocked": _shot.blocked, "wall_s": snappedf(wall, 0.1),
			"s_per_frame": snappedf(wall / maxf(_shot.frames + WARMUP, 1), 0.01),
			"subject": m.subject.stats.name if is_instance_valid(m.subject) and m.subject is AttackerUnit else (
				String(m.subject.name) if is_instance_valid(m.subject) else "gone"),
			"atk_policy": GameConfig.atk_policy, "def_policy": GameConfig.def_policy, "seed": GameConfig.sim_seed}
	var f := FileAccess.open(_shot.dir.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	clips.append(meta)
	var g := FileAccess.open(out_dir.path_join("moments.json"), FileAccess.WRITE)
	g.store_string(JSON.stringify(clips, "\t"))
	g.close()
	print("FILM %6.1f done %s: %d frames in %.0f s (%.2f s/frame)" % [sim.clock, _shot.name, _shot.frames, wall, meta.s_per_frame])
	_shot = {}


## Where `p` is: by the nearest gate's side, how far out, on the water or inside.
func _place(p: Vector3) -> String:
	var flat := Vector2(p.x, p.z)
	var side := "south"
	var best := -INF
	for s in level.gates:
		var g: Vector3 = level.gates[s].global_position
		var dot := Vector2(g.x, g.z).normalized().dot(flat.normalized())
		if dot > best:
			best = dot
			side = s
	var r := flat.length()
	if r < 80.0:
		return "%s keep" % side
	if level.gates.has(side) and level.gates[side].global_position.distance_to(p) < 35.0:
		return "%s gate" % side
	if RiverCrossing.swimming_at(p, 0.3):
		return "%s river" % side
	return "%s %s %dm" % [side, "clearing" if r < 135.0 else "forest", int(r / 10.0) * 10]


## Who is within 45 m of the shot's middle, by type.
func _in_shot(p: Vector3) -> Dictionary:
	var atk := {}
	for u in commander.units.values():
		if is_instance_valid(u) and u.global_position.distance_to(p) < 45.0:
			atk[u.type_id] = int(atk.get(u.type_id, 0)) + 1
	var defn := 0
	if match_node.garrison:
		for s in match_node.garrison.soldiers:
			if is_instance_valid(s) and s.global_position.distance_to(p) < 45.0:
				defn += 1
	var squads := []
	for s in sim.armory.squads:
		var sp = s.leader.global_position if s.get("leader") and is_instance_valid(s.leader) else (s.global_position if s is Node3D else Vector3.INF)
		if sp != Vector3.INF and sp.distance_to(p) < 60.0:
			squads.append(AIDefender.kind_of(s))
	return {"attackers": atk, "garrison": defn, "squads": squads}


## Times the frames with the costly features turned off one after another (cumulatively), the world frozen, then puts
## everything back. A still of each step is saved next to the clips (bench_<step>.jpg).
func _run_bench() -> void:
	_benching = true
	var vp := get_viewport()
	var env: Environment = null
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		env = we.environment
	var suns: Array = get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	var grass: Array = get_tree().root.find_children("*", "", true, false).filter(func(n): return n is GrassField)
	var keep := {"ssil": env.ssil_enabled, "ssao": env.ssao_enabled, "ssr": env.ssr_enabled, "vol": env.volumetric_fog_enabled,
			"glow": env.glow_enabled, "scale": vp.scaling_3d_scale}
	var sun_keep := suns.map(func(l): return [l.directional_shadow_mode, l.directional_shadow_max_distance, l.shadow_enabled])
	var steps := [
		["base", func(): pass],
		["lod_4", func(): vp.mesh_lod_threshold = 4.0],
		["lod_12", func(): vp.mesh_lod_threshold = 12.0],
		["far_400", func(): cam.far = 400.0],
		["far_250", func(): cam.far = 250.0],
		["shadow_2split_120m", func():
			for l in suns:
				l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				l.directional_shadow_max_distance = 120.0],
		["shadow_ortho_70m", func():
			for l in suns:
				l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				l.directional_shadow_max_distance = 70.0],
		["no_volfog", func(): env.volumetric_fog_enabled = false],
		["scale_0.75", func(): vp.scaling_3d_scale = 0.75],
	]
	var keep_lod := vp.mesh_lod_threshold
	var keep_far := cam.far
	print("FILM bench: %d grass fields, %d suns" % [grass.size(), suns.size()])
	for st in steps:
		st[1].call()
		await RenderingServer.frame_post_draw
		var t := Time.get_ticks_usec()
		var total := 0.0
		for i in 2:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			total += (now - t) / 1e6
			t = now
		vp.get_texture().get_image().save_jpg(out_dir.path_join("bench_%s.jpg" % st[0]), 0.85)
		print("FILM bench %-20s %.2f s/frame" % [st[0], total / 2.0])
	env.ssil_enabled = keep.ssil
	env.ssao_enabled = keep.ssao
	env.ssr_enabled = keep.ssr
	env.volumetric_fog_enabled = keep.vol
	env.glow_enabled = keep.glow
	vp.scaling_3d_scale = keep.scale
	vp.mesh_lod_threshold = keep_lod
	cam.far = keep_far
	for i in suns.size():
		suns[i].directional_shadow_mode = sun_keep[i][0]
		suns[i].directional_shadow_max_distance = sun_keep[i][1]
		suns[i].shadow_enabled = sun_keep[i][2]
	for g in grass:
		g.visible = true
	_benching = false
