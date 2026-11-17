class_name SimDirector
extends Node
## The balance simulator (`--sim=out.json`): the CPU plays both sides of a whole match, the AIAttacker against the
## AIDefender, each by its policy (`--atk=`, `--def=`), and the match is written up as JSON for tools/balance to read:
## who won and when, a sample of both sides every GameConfig.sim_sample seconds (the `timeline`) and what happened when
## (the `events`). Nothing is drawn for it: run it with `--headless --fixed-fps 30`, which plays every frame as a thirtieth
## of a second however long it took to work out, so the match runs as fast as the machine allows and plays the same
## as it would at 30 frames a second. A coarser match is a faster one: `--fixed-fps 10` with `--sim-ticks=30` (30 physics
## ticks a second instead of 60) plays about three times as fast.
##
##   godot --path game --headless --fixed-fps 30 -- --sim=/tmp/m.json --atk=even --def=default --seed=7
##
## Match makes one when GameConfig.sim is set, in place of the human's controller (Match._ready), and hands it the
## winner at the end (finish).

## A line is printed every this many samples, so a watcher sees the match go by.
const PRINT_EVERY := 6
## Attackers this close to the middle of the map (flat, m) are "at the walls", and this close "in the clearing".
const AT_WALLS := 115.0
const IN_CLEARING := 150.0

var match_node: Node
var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var ai_attacker: AIAttacker
var ai_defender: AIDefender

var timeline: Array = []
var events: Array = []
## Seconds of the match played.
var clock := 0.0

var _sample_cd := 0.0
var _samples := 0
var _t0_msec := 0
var _frames := 0
## Running totals for the telemetry: what the attackers spent and lost (credits and heads, by type), what fell.
var _atk := {"spent": 0.0, "spawned": 0, "lost": 0, "lost_value": 0.0, "spawned_by": {}, "lost_by": {}, "waves": 0,
		"bridges_dropped": 0, "bridges_fallen": 0, "inside": 0, "died_crossing": 0,
		"deaths_at": {"0-100": 0, "100-150": 0, "150-250": 0, "250-420": 0, "420+": 0}}
var _def := {"squad_troopers_lost": 0, "squads_lost": 0, "guns_lost": 0, "aa_lost": 0, "posts_lost": 0, "gates_lost": 0,
		"gates_rebuilt": 0, "helipads_sabotaged": 0, "helipads_retaken": 0}
var _first := {}
var _trees0 := 0
var _raiders := {}
## Seconds of real time spent in the frames' process, physics and navigation steps since the last printed line (the
## engine's own monitors, summed a frame at a time): where the machine's time goes.
var _perf := {"process": 0.0, "physics": 0.0, "nav": 0.0, "frames": 0, "wall0": 0}
## The film crew (`--film=<dir>`, scripts/sim/film_crew.gd): films the match's best moments; null otherwise.
var film: Node


## The two CPUs, made before the match starts (Match._ready): Match adds them once the navmesh is in.
func setup(m: Node) -> void:
	match_node = m
	if GameConfig.sim_ticks > 0:
		Engine.physics_ticks_per_second = GameConfig.sim_ticks
	Engine.max_physics_steps_per_frame = 32
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--film="):
			# Nothing is drawn until there is something to film (the level's build and the navmesh included).
			RenderingServer.render_loop_enabled = false
			film = preload("res://scripts/sim/film_crew.gd").new()
			film.name = "FilmCrew"
			film.sim = self
			film.out_dir = arg.get_slice("=", 1)
	level = m.level
	commander = m.commander
	armory = DefenderArmory.new()
	armory.name = "DefenderArmory"
	armory.level = level
	m.armory = armory

	ai_attacker = AIAttacker.new()
	ai_attacker.name = "AIAttacker"
	ai_attacker.commander = commander
	ai_attacker.level = level
	ai_attacker.drones = m.drones
	ai_attacker.set_policy(load_policy(GameConfig.atk_policy, AIAttacker.POLICIES))
	m.ai_attacker = ai_attacker
	var mult = ai_attacker.policy.income_mult
	var chest := GameConfig.ai_income_mult() if mult == null else float(mult)
	commander.supply = AttackerCommander.START_CREDITS * chest
	commander.income = AttackerCommander.BASE_INCOME * chest

	ai_defender = AIDefender.new()
	ai_defender.name = "AIDefender"
	ai_defender.level = level
	ai_defender.armory = armory
	ai_defender.commander = commander
	ai_defender.set_policy(load_policy(GameConfig.def_policy, AIDefender.POLICIES))


## `name`'s policy: an entry of `named`, or a JSON file of overrides (a path ending in .json), which may itself start
## from a named one with {"base": name}.
static func load_policy(name: String, named: Dictionary) -> Dictionary:
	if name.ends_with(".json"):
		var text := FileAccess.get_file_as_string(name)
		var data = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			push_error("SimDirector: no policy in %s" % name)
			return {}
		var out: Dictionary = (named.get(String(data.get("base", "default")), {}) as Dictionary).duplicate(true)
		for k in data:
			if k != "base":
				out[k] = data[k]
		return out
	if not named.has(name):
		push_error("SimDirector: no policy called '%s' (there are: %s)" % [name, ", ".join(named.keys())])
		return {}
	return (named[name] as Dictionary).duplicate(true)


func _ready() -> void:
	ai_defender.garrison = match_node.garrison
	add_child(ai_defender)
	if film:
		add_child(film)
	_t0_msec = Time.get_ticks_msec()
	_trees0 = ForestTree.standing.size()
	commander.unit_spawned.connect(_on_unit_spawned)
	commander.unit_died.connect(_on_unit_died)
	commander.bridge_ordered.connect(func(_b): _atk.bridges_dropped += 1)
	commander.bridge_fallen.connect(func(b): _atk.bridges_fallen += 1; _event("bridge_fallen", {"at": _xz(b.global_position)}))
	ai_attacker.wave_launched.connect(func(wave, side, ids): _atk.waves = wave; _event("wave", {"wave": wave, "side": side, "units": ids.size()}))
	armory.squad_bought.connect(func(s): _event("squad_bought", {"kind": AIDefender.kind_of(s)}))
	armory.squad_lost.connect(func(s): _def.squads_lost += 1; _event("squad_lost", {"kind": AIDefender.kind_of(s)}))
	for side in level.gates:
		var gate: Structure = level.gates[side]
		gate.destroyed.connect(func(_g): _def.gates_lost += 1; _event("gate_down", {"side": side}))
		gate.rebuilt.connect(func(_g): _def.gates_rebuilt += 1; _event("gate_rebuilt", {"side": side}))
	for v in level.vents:
		v.destroyed.connect(func(_v): _event("vent_down", {"vent": v.display_name, "left": level.vents_left()}))
	for b in level.bases:
		b.sabotaged.connect(func(_b): _def.helipads_sabotaged += 1; _event("helipad_sabotaged", {"base": b.display_name}))
		b.retaken.connect(func(_b): _def.helipads_retaken += 1; _event("helipad_retaken", {"base": b.display_name}))
	print("SIM start atk=%s def=%s seed=%d time=%.0f label=%s" % [GameConfig.atk_policy, GameConfig.def_policy,
			GameConfig.sim_seed, match_node.time_left, GameConfig.sim_label])


func _process(delta: float) -> void:
	if match_node.finished:
		return
	clock += delta
	_frames += 1
	_perf.process += Performance.get_monitor(Performance.TIME_PROCESS)
	_perf.physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_perf.nav += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)
	_perf.frames += 1
	_sample_cd -= delta
	if _sample_cd <= 0.0:
		_sample_cd += GameConfig.sim_sample
		_sample()


func _on_unit_spawned(u: AttackerUnit) -> void:
	_atk.spawned += 1
	_atk.spent += float(u.stats.cost)
	_atk.spawned_by[u.type_id] = int(_atk.spawned_by.get(u.type_id, 0)) + 1


func _on_unit_died(u: AttackerUnit) -> void:
	_atk.lost += 1
	_atk.lost_value += float(u.stats.cost)
	_atk.lost_by[u.type_id] = int(_atk.lost_by.get(u.type_id, 0)) + 1
	if u.has_bombard():
		_event("artillery_down", {"unit": u.type_id, "at": _xz(u.global_position)})
	# Where it fell: how far from the keep (the walls, the clearing, the forest, the river, its own bank).
	var d := Vector2(u.global_position.x, u.global_position.z).length()
	var band := "0-100" if d < 100.0 else ("100-150" if d < 150.0 else ("150-250" if d < 250.0 else ("250-420" if d < 420.0 else "420+")))
	_atk.deaths_at[band] += 1
	if u.is_crossing():
		_atk.died_crossing += 1


func _event(type: String, more := {}) -> void:
	var e := {"t": snappedf(clock, 0.1), "type": type}
	e.merge(more)
	events.append(e)
	if not _first.has(type):
		_first[type] = e.t
	print("SIM %6.1f %s %s" % [clock, type, JSON.stringify(more)])
	if film:
		film.on_event(type, more)


static func _xz(p: Vector3) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]


## One sample of the match: both sides' purses and forces, the objectives, where the front is.
func _sample() -> void:
	var by_type := {}
	var at_walls := 0
	var in_clearing := 0
	var inside := 0
	var nearest := INF
	var mean := 0.0
	var army_value := 0.0
	var army_hp := 0.0
	for u in commander.units.values():
		by_type[u.type_id] = int(by_type.get(u.type_id, 0)) + 1
		army_value += float(u.stats.cost)
		army_hp += u.hp
		var d := Vector2(u.global_position.x, u.global_position.z).length()
		mean += d
		nearest = minf(nearest, d)
		if d < AT_WALLS:
			at_walls += 1
		if d < IN_CLEARING:
			in_clearing += 1
		if u.raiding:
			inside += 1
			if not _raiders.has(u.unit_id):
				_raiders[u.unit_id] = true
				_atk.inside += 1
				if not _first.has("raider_inside"):
					_event("raider_inside", {"unit": u.type_id})
	var n := commander.units.size()
	var gates := {}
	for side in level.gates:
		gates[side] = int(level.gates[side].hp)
	var vent_hp := 0.0
	for v in level.vents:
		vent_hp += v.hp
	var squads := {}
	var squad_heads := 0
	for s in armory.squads:
		var kind := AIDefender.kind_of(s)
		squads[kind] = int(squads.get(kind, 0)) + 1
		squad_heads += 1 if s is DefenderMachine else (s.troopers.size() as int)
	var guns_alive := 0
	var guns_total := 0
	var aa_alive := 0
	var aa_total := 0
	var posts_alive := 0
	for d in get_tree().get_nodes_in_group("defender_targets"):
		match d.get("station_kind"):
			"mg", "artillery":
				guns_total += 1
				guns_alive += 1 if d.is_alive() else 0
			"aa":
				aa_total += 1
				aa_alive += 1 if d.is_alive() else 0
	for s in level.stations:
		if s.get("station_kind") == "soldier" and s.is_alive():
			posts_alive += 1
	var g: Dictionary = match_node.garrison.summary() if match_node.garrison and match_node.garrison.set_up else {}
	var gs: Dictionary = match_node.garrison.stats if match_node.garrison else {}
	var drones: DroneBay = match_node.drones
	var row := {
		"t": snappedf(clock, 0.1),
		"time_left": snappedf(match_node.time_left, 0.1),
		"atk": {
			"supply": int(commander.supply), "income": snappedf(commander.income_rate(), 0.01), "units": n,
			"army_value": int(army_value), "army_hp": int(army_hp), "by_type": by_type,
			"spent": int(_atk.spent), "spawned": _atk.spawned, "lost": _atk.lost, "lost_value": int(_atk.lost_value),
			"wave": ai_attacker.wave_number(), "at_walls": at_walls, "in_clearing": in_clearing, "inside": inside,
			"nearest": -1.0 if n == 0 else snappedf(nearest, 0.1), "mean_dist": -1.0 if n == 0 else snappedf(mean / n, 0.1),
			"bridges_left": commander.bridges_left, "bridges_up": commander.bridges.size(),
			"helipads": level.bases.filter(func(b): return b.controlled).size(),
			# Where each Mule Artillery and Bison Field Gun is and what it is doing: [type, x, z, order, gun packed, target].
			"artillery": _artillery_rows(),
		},
		"def": {
			"credits": int(armory.credits), "spent": int(ai_defender.spent), "squads": squads, "squad_heads": squad_heads,
			"squads_lost": _def.squads_lost,
			"garrison": int(g.get("alive", 0)), "garrison_field": int(g.get("field", 0)), "garrison_deck": int(g.get("deck", 0)),
			"guns_manned": int(g.get("guns", 0)), "garrison_spawned": int(gs.get("spawned", 0)), "garrison_lost": int(gs.get("deaths", 0)),
			"guns_alive": guns_alive, "guns_total": guns_total, "aa_alive": aa_alive, "aa_total": aa_total, "posts_alive": posts_alive,
			"drones": drones.alive_count() if drones else 0, "drones_aloft": drones.airborne_count() if drones else 0,
			"drones_lost": int(drones.stats.drones_lost) if drones else 0,
			"trees_gone": _trees0 - ForestTree.standing.size(), "mine_blasts": GroundMine.blasts,
			"spawn_side": match_node.garrison.controls[0].side if match_node.garrison and not match_node.garrison.controls.is_empty() else "",
			"cb": ai_defender.cb_stats.duplicate(), "artillery_near": ai_defender.artillery.size(), "shelled": ai_defender.shelled,
			"machines": armory.squads.filter(func(q): return q is DefenderMachine).map(func(q): return [AIDefender.kind_of(q),
					int(q.global_position.x), int(q.global_position.z), q.get("hunt") != null or q.get("attacker") != null]),
		},
		"obj": {"gates": gates, "vents": level.vents_left(), "vent_hp": int(vent_hp)},
	}
	timeline.append(row)
	_samples += 1
	if _samples % PRINT_EVERY == 1:
		var wall := (Time.get_ticks_msec() - _t0_msec) / 1000.0
		var lap := (Time.get_ticks_msec() - int(_perf.wall0)) / 1000.0
		if _perf.frames > 0 and _perf.wall0 > 0:
			print("SIM perf: %.1f game s in %.1f s (x%.2f) | per frame: process %.1f ms, physics %.1f ms (x%d ticks), nav %.1f ms | nodes=%d objects=%d" % [
					GameConfig.sim_sample * PRINT_EVERY, lap, GameConfig.sim_sample * PRINT_EVERY / maxf(lap, 0.001),
					_perf.process / _perf.frames * 1000.0, _perf.physics / _perf.frames * 1000.0,
					Engine.physics_ticks_per_second / maxi(Engine.get_frames_per_second(), 1) if false else 0,
					_perf.nav / _perf.frames * 1000.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
					int(Performance.get_monitor(Performance.OBJECT_COUNT))])
		_perf = {"process": 0.0, "physics": 0.0, "nav": 0.0, "frames": 0, "wall0": Time.get_ticks_msec()}
		print("SIM %6.0f | atk units=%d value=%d lost=%d walls=%d inside=%d supply=%d | def credits=%d squads=%d garrison=%d(-%d) guns=%d/%d | gates=%s vents=%d hp=%d | x%.1f" % [
				clock, n, int(army_value), _atk.lost, at_walls, inside, int(commander.supply), int(armory.credits), armory.squads.size(),
				int(g.get("alive", 0)), int(gs.get("deaths", 0)), guns_alive, guns_total, JSON.stringify(gates), level.vents_left(), int(vent_hp),
				clock / maxf(wall, 0.001)])


## Each Mule Artillery and Bison Field Gun: [type, x, z, its order, its gun packed, where the order sends it].
func _artillery_rows() -> Array:
	var rows := []
	for u in commander.units.values():
		if not u.has_bombard():
			continue
		var to = u.order.get("pos")
		rows.append([u.type_id, int(u.global_position.x), int(u.global_position.z), String(u.order.type), u.is_packed(),
				[int(to.x), int(to.z)] if to is Vector3 else []])
	return rows


## The match is over (Match._end): writes it up and quits.
func finish(winner: int) -> void:
	_sample()
	var wall := (Time.get_ticks_msec() - _t0_msec) / 1000.0
	var out := {
		"winner": "attacker" if winner == GameConfig.TEAM_ATTACKER else "defender",
		"duration": snappedf(clock, 0.1),
		"time_left": snappedf(match_node.time_left, 0.1),
		"match_time": snappedf(clock + match_node.time_left, 0.1),
		"atk_policy": GameConfig.atk_policy, "def_policy": GameConfig.def_policy,
		"atk_policy_data": ai_attacker.policy, "def_policy_data": ai_defender.policy,
		"seed": GameConfig.sim_seed, "label": GameConfig.sim_label,
		"wall_seconds": snappedf(wall, 0.1), "speed": snappedf(clock / maxf(wall, 0.001), 0.01), "frames": _frames,
		"totals": {"atk": _atk, "def": _def, "def_bought": ai_defender.bought, "def_lost": ai_defender.lost, "first": _first},
		"final": timeline[-1] if not timeline.is_empty() else {},
		"events": events,
		"timeline": timeline,
	}
	var f := FileAccess.open(GameConfig.sim, FileAccess.WRITE)
	if f == null:
		push_error("SimDirector: can't write %s" % GameConfig.sim)
	else:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	print("SIM over winner=%s duration=%.0f time_left=%.0f vents=%d wall=%.0fs x%.1f -> %s" % [out.winner, clock, match_node.time_left,
			level.vents_left(), wall, clock / maxf(wall, 0.001), GameConfig.sim])
	get_tree().quit()
