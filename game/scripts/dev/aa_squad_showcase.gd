extends Node3D
## Staged run of the AA Squads on the real map: three bought squads out in the south field, the
## first driven like a player would (this node is its pilot). The run, in phases:
##   air      two Sky Talons cross in front of AA 1: it holds RMB on each, close but not dead on,
##            until the lock closes (3 s), then fires seeking missiles and brings it down
##   ground   a group of attackers ahead: RMB shows each trooper's spot, LMB fires the strike
##   mines    F, a cone ahead, LMB: the mines land over the band; attackers walk into them
##   hotbar   F2, F3, F1 through the roster, and Ctrl+F1 swapping AA 1's auto order and back;
##            then AA 1 walks on further out
##   auto     the player goes back to a rifleman on the south deck: AA 1 (MINES) lays mines where
##            it was left and walks back to the base laying them on its way, then along the
##            perimeter; AA 3 (MINES) lays them along the perimeter; AA 2 (GUARD) holds its ground,
##            shoots down a Sky Talon and leaves the attackers walking past alone
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/aa_squad_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
##       res://scenes/dev/aa_squad_showcase.tscn -- --shots=DIR
##
## Both print what the squads do and check it at the end (AA SHOWCASE PASS / FAIL); --shots also
## saves a captioned screenshot at each moment worth seeing into DIR (drawing only those frames).
## The garrison's posts hold fire.

const AA1_AT := Vector3(-4.0, 0.0, 152.0)
const AA2_AT := Vector3(20.0, 0.0, 114.0)
const AA3_AT := Vector3(-30.0, 0.0, 108.0)
## Where the player walks AA 1 before handing it back.
const AA1_OUT := Vector3(16.0, 0.0, 176.0)
## The rifleman the player goes back to: south deck (LevelBuilder.RIFLE_POSTS[0]).
const RIFLEMAN := 4
const GROUND := [["rifleman", -6.0, 192.0], ["rifleman", -2.5, 190.5], ["rifleman", 1.5, 192.5], ["kangaroo", -4.5, 195.5],
		["rifleman", 0.5, 196.0], ["kangaroo", 3.5, 190.0], ["rifleman", -7.5, 194.5], ["rifleman", 4.0, 195.0]]
const WALKERS := [["rifleman", -9.0, 196.0], ["rifleman", -4.0, 198.0], ["rifleman", 1.0, 196.5], ["kangaroo", -6.0, 199.0]]
const PASSERS := [["rifleman", 48.0, 194.0], ["rifleman", 52.0, 196.0], ["kangaroo", 50.0, 199.0], ["rifleman", 46.0, 199.0]]

var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var dc: DefenderController
var aa: Array[AASquad] = []
var cam: Camera3D
var shots_dir := ""
var t := -1.0
var phase := "setup"
var phase_t := 0.0
var checks := {}

var _step := 0
var _talons: Array = []
var _talon_i := 0
var _lock_started := -1.0
var _ground: Array = []
var _rockets_before := 0
var _walkers: Array = []
var _passers: Array = []
var _mine_point := Vector3.ZERO
var _mines_before := 0
var _blasts_before := 0
var _talon_c: AttackerUnit
var _released_at := -1.0
var _aa1_throws := 0
var _aa1_throw_kinds: Array[String] = []
var _aa1_dist: Array[float] = []
var _aa2_post := Vector3.ZERO
var _aa2_drift := 0.0
var _aa2_strikes := 0
var _log_cd := 0.0
var _shot_queue: Array = []
var _shot_n := 0
var _saving := false
var _view := "-"
var _title: Label
var _sub: Label
var _hotbar: SquadHotbar


func _ready() -> void:
	seed(7)  # the same run every time
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the garrison's posts hold fire.
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 900.0
	add_child(cam)
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		RenderingServer.render_loop_enabled = false
		_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# The navmesh's first iteration lands a few frames after the bake.
	for k in 10:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	level.stations[RIFLEMAN].process_mode = Node.PROCESS_MODE_INHERIT
	armory = DefenderArmory.new()
	armory.level = level
	armory.credits = DefenderArmory.AA_COST * 3
	add_child(armory)
	dc = DefenderController.new()
	dc.level = level
	dc.armory = armory
	add_child(dc)
	for k in 3:
		aa.append(dc.buy_squad())
	# Out in the south field (they deployed in the spawn halls): AA 1 and AA 2 facing south, AA 3
	# by the perimeter.
	_place(aa[0], AA1_AT, PI)
	_place(aa[1], AA2_AT, PI)
	_place(aa[2], AA3_AT, PI)
	aa[1].set_order(AASquad.Order.GUARD)
	aa[0].pilot = self
	dc.select_squad(0, true)
	if _hotbar:
		_hotbar.armory = armory
	t = 0.0
	_log("start: roster %s, %d credits left" % [aa.map(func(s): return s.station_name), int(armory.credits)])


## Moves a squad's troopers to `at` in a wedge facing `yaw`, as if it had walked there.
func _place(s: AASquad, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var spots := [Vector2.ZERO] + Array(SquadFormation.WEDGE)
	for i in s.troopers.size():
		var o: Vector2 = spots[i]
		var tr := s.troopers[i]
		tr.global_position = at + b * Vector3(o.x, 0.0, -o.y) + Vector3.UP * 0.2
		tr.rotation.y = yaw
		tr.velocity = Vector3.ZERO
	s.leader = s.troopers[0]
	for tr in s.troopers:
		tr.set_leader(tr == s.leader)
	s.heading = yaw
	s.cam_yaw = yaw
	s.formation.trail.clear()
	s.guard_post = at
	s.plan = "return"


# ---------------------------------------------------------------- the run

func _physics_process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	phase_t += delta
	match phase:
		"setup":
			if t > 1.5:
				_next("air")
				_talons = [_spawn("talon", Vector3(-58.0, UnitTypes.FLY_HEIGHT, 192.0), Vector3(70.0, UnitTypes.FLY_HEIGHT, 192.0)),
						_spawn("talon", Vector3(72.0, UnitTypes.FLY_HEIGHT, 200.0), Vector3(-80.0, UnitTypes.FLY_HEIGHT, 200.0))]
		"air":
			_air_step()
		"ground":
			_ground_step()
		"mines":
			_mines_step()
		"hotbar":
			_hotbar_step()
		"auto":
			_auto_step()
		"done":
			if phase_t > 0.5 and _shot_queue.is_empty() and not _saving:
				_report()
				get_tree().quit()
	_watch(delta)
	_shots_tick()


func _next(p: String) -> void:
	phase = p
	phase_t = 0.0
	_step = 0
	_log("phase %s" % p)


func _air_step() -> void:
	var s := aa[0]
	if _talon_i >= _talons.size() or phase_t > 28.0:
		checks["air_kills"] = _talons.filter(func(u): return _down(u)).size()
		_ground = _wave(GROUND, Vector3.ZERO, false)
		_next("ground")
		return
	var target: AttackerUnit = _talons[_talon_i]
	if _down(target):
		_log("talon %d down (missiles fired so far %d)" % [_talon_i + 1, s.stats.missiles])
		_shot("air_%d_down" % (_talon_i + 1), 0.25, "AIR · the missiles bring it down", "")
		_talon_i += 1
		_lock_started = -1.0
		return
	if s.lock_target == target and _lock_started < 0.0:
		_lock_started = t
		_shot("air_%d_locking" % (_talon_i + 1), 1.6, "AIR · hold RMB close to an aircraft",
				"3 s to lock on, the aim following it closely (it needn't be dead on)")
	if s.locked and _lock_started >= 0.0 and not checks.has("lock_time_%d" % (_talon_i + 1)):
		checks["lock_time_%d" % (_talon_i + 1)] = t - _lock_started
		_log("locked on talon %d after %.2f s" % [_talon_i + 1, t - _lock_started])
		_shot("air_%d_locked" % (_talon_i + 1), 0.05, "AIR · LOCKED", "LMB launches seeking missiles: as many as the kill takes")
		_shot("air_%d_missiles" % (_talon_i + 1), 0.6, "AIR · seeking missiles", "from the shoulder pods, onto the locked aircraft")


func _ground_step() -> void:
	var s := aa[0]
	if _step == 0 and phase_t > 1.6:
		_step = 1
		_shot("ground_preview", 2.3, "GROUND · aim at them: RMB shows where the rockets land",
				"each trooper gets a spot of its own round the aim, clustered and not on top of each other")
	elif _step == 1 and phase_t > 4.3:
		# What the strike is about to do (LMB goes down at 4.45 s).
		_step = 2
		var shooters := s.troopers.filter(func(x): return s._free_tubes(x) > 0)
		var at := s.strike_point()
		var spots := s.strike_spots(shooters, at)
		var gaps := []
		for i in spots.size():
			for j in range(i + 1, spots.size()):
				gaps.append(_flat(spots[i], spots[j]))
		checks["strike_min_gap"] = gaps.min() if not gaps.is_empty() else 0.0
		checks["strike_max_off"] = spots.map(func(p): return _flat(p, at)).max()
		_rockets_before = s.stats.rockets
		_log("strike at (%.1f, %.1f), %.1f m out: %d spots %.1f..%.1f m apart, at most %.1f m from the aim" % [at.x, at.z,
				_flat(at, s.leader.global_position), spots.size(), gaps.min(), gaps.max(), checks.strike_max_off])
		_shot("ground_rockets", 0.85, "GROUND · LMB: rocket strike", "up to three rockets from every pod")
		_shot("ground_pod", 0.5, "POD · the rockets leave their tubes", "the pod swings up over the spot; empty tubes reload one at a time", "pod")
		_shot("ground_impact", 1.75, "GROUND · impact", "")
	elif _step == 2 and phase_t > 10.0:
		checks["strike_rockets"] = s.stats.rockets - _rockets_before
		checks["strike_kills"] = _ground.filter(func(u): return _down(u)).size()
		_log("strike: %d rockets, %d of %d attackers down" % [checks.strike_rockets, checks.strike_kills, _ground.size()])
		_clear(_ground)
		_mine_point = aa[0].leader.global_position + Vector3(0.0, 0.0, 17.0)
		_next("mines")


func _mines_step() -> void:
	var s := aa[0]
	if _step == 0:
		_step = 1
		s.toggle_mine_aim()
		_shot("mines_aim", 1.8, "MINES · F aims the throw", "a cone like the hippo's smoke: the mines land sparsely over the green band")
	elif _step == 1 and phase_t > 2.4:
		# LMB goes down now (pilot_input).
		_step = 2
		_mines_before = s.stats.mines
		_shot("mines_throw", 0.6, "MINES · LMB throws", "two from every trooper")
		_shot("mines_down", 3.3, "MINES · down and armed", "they blink once armed and go off under enemy ground units")
	elif _step == 2 and phase_t > 5.0:
		_step = 3
		checks["mines_thrown"] = s.stats.mines - _mines_before
		checks["mine_cooldown"] = s.mine_cd
		_log("mines: %d thrown, ready again in %.1f s, %d of AA 1's on the field" % [checks.mines_thrown, s.mine_cd, s.mines.size()])
		_blasts_before = GroundMine.blasts
		_walkers = _wave(WALKERS, Vector3(-4.0, 0.0, 120.0), true)
	elif _step == 3:
		if GroundMine.blasts > _blasts_before and not checks.has("mine_blast_t"):
			checks["mine_blast_t"] = phase_t
			_shot("mines_blast", 0.1, "MINES · an attacker walks onto one", "")
		if phase_t > 19.0:
			checks["mine_blasts"] = GroundMine.blasts - _blasts_before
			checks["walker_kills"] = _walkers.filter(func(u): return _down(u)).size()
			_log("minefield: %d mines went off, %d of %d walkers down" % [checks.mine_blasts, checks.walker_kills, _walkers.size()])
			_clear(_walkers)
			_next("hotbar")


func _hotbar_step() -> void:
	match _step:
		0:
			_step = 1
			dc.select_squad(1)
			_shot("hotbar_f2", 1.0, "HOTBAR · F2", "takes command of AA Squad 2 (its auto order: GUARD)")
		1:
			if phase_t > 2.5:
				_step = 2
				checks["f2_drives_aa2"] = dc.current == aa[1] and aa[1].possessed and not aa[0].possessed
				dc.cycle_squad_order(0)
				checks["ctrl_f1_guard"] = aa[0].order == AASquad.Order.GUARD
				_shot("hotbar_ctrl_f1", 0.3, "HOTBAR · Ctrl+F1", "AA Squad 1's auto order is now GUARD, set from wherever you are")
		2:
			if phase_t > 4.2:
				_step = 3
				dc.select_squad(2)
				_shot("hotbar_f3", 1.0, "HOTBAR · F3", "takes command of AA Squad 3")
		3:
			if phase_t > 6.5:
				_step = 4
				checks["f3_drives_aa3"] = dc.current == aa[2] and aa[2].possessed and not aa[1].possessed
				dc.cycle_squad_order(0)
				checks["ctrl_f1_mines"] = aa[0].order == AASquad.Order.MINES
				dc.select_squad(0)
				_shot("hotbar_f1", 1.0, "HOTBAR · F1", "back on AA Squad 1 (its order MINES again)")
		4:
			if phase_t > 8.0:
				_step = 5
				checks["f1_drives_aa1"] = dc.current == aa[0] and aa[0].possessed and not aa[2].possessed
				_shot("drive_out", 6.0, "THIRD PERSON · the AA Squad moves like the Gunner Squad",
						"WASD with the formation following, the pods tracking the aim")
		5:
			# AA 1 walks on further out (pilot_input), then the player hands it back.
			if phase_t > 21.0 or _flat(aa[0].leader.global_position, AA1_OUT) < 1.5:
				_log("AA 1 walked out to (%.1f, %.1f)" % [aa[0].leader.global_position.x, aa[0].leader.global_position.z])
				_next("auto")


func _auto_step() -> void:
	var s1 := aa[0]
	var s2 := aa[1]
	match _step:
		0:
			_step = 1
			_aa1_throws = s1.stats.throws
			_aa2_post = s2.leader.global_position
			_aa2_strikes = s2.stats.strikes
			dc.select_station(RIFLEMAN)
			_released_at = t
			_talon_c = _spawn("talon", Vector3(118.0, UnitTypes.FLY_HEIGHT, 150.0), Vector3(-90.0, UnitTypes.FLY_HEIGHT, 112.0))
			_passers = _wave(PASSERS, Vector3(110.0, 0.0, 96.0), true)
			_shot("auto_soldier", 1.3, "AUTO · back on a rifleman (1-9)", "the AA Squads carry on with their auto orders (hotbar)")
			_shot("auto_aa1_here", 1.25, "AUTO · AA 1 (MINES)", "handed back out in the field: it lays mines where it is", "aa1")
		1:
			if phase_t > 0.6:
				_step = 2
				# The rifleman looks out over the south field.
				var soldier: DefenderSoldier = level.stations[RIFLEMAN]
				soldier._pitch = deg_to_rad(-9.0)
				soldier._head.rotation.x = soldier._pitch
				soldier.rotation.y += deg_to_rad(8.0)
		2:
			if s2.lock_target == _talon_c and s2.lock_progress > 1.6 and not checks.has("guard_lock_shot"):
				checks["guard_lock_shot"] = true
				_shot("auto_aa2_locking", 0.0, "AUTO · AA 2 (GUARD) locks on", "auto squads shoot down any aircraft in range, never ground units", "aa2")
			if s2.stats.missiles > 0 and not checks.has("guard_missile_shot"):
				checks["guard_missile_shot"] = true
				_shot("auto_aa2_missiles", 0.5, "AUTO · AA 2 (GUARD) fires", "3 s after it locked on, from where it stands", "aa2")
			if _down(_talon_c) and not checks.has("guard_kill_t"):
				checks["guard_kill_t"] = phase_t
				_log("talon C down %.1f s into the auto phase (missiles: AA 1 %d, AA 2 %d, AA 3 %d)" % [phase_t,
						s1.stats.missiles, s2.stats.missiles, aa[2].stats.missiles])
			if s1.stats.throws > _aa1_throws:
				# Which of the order's throws: where it was handed back, on the way, or at the base.
				_aa1_throws = s1.stats.throws
				var kind := "here" if phase_t < 1.5 else ("path" if s1.plan == "return" else "perimeter")
				_aa1_throw_kinds.append(kind)
				if not checks.has("aa1_%s_throw_t" % kind):
					checks["aa1_%s_throw_t" % kind] = phase_t
				_log("AA 1 laid mines (%s) %.1f s in, %.1f m from the perimeter" % [kind, phase_t, _to_perimeter(s1)])
				if kind == "path" and not checks.has("path_shot"):
					checks["path_shot"] = true
					_shot("auto_aa1_path", 1.0, "AUTO · AA 1 (MINES) heads back to base", "laying mines on the path behind it as they come ready", "aa1")
				elif kind == "perimeter" and not checks.has("perimeter_shot"):
					checks["perimeter_shot"] = true
					_shot("auto_perimeter", 1.1, "AUTO · at the base: mines along the perimeter", "outside the gate, where the fewest are", "perimeter")
			if s1.plan == "perimeter" and not checks.has("aa1_at_base_t"):
				checks["aa1_at_base_t"] = phase_t
				_log("AA 1 at the perimeter %.1f s in" % phase_t)
			if phase_t > 70.0 or (checks.has("aa1_perimeter_throw_t") and phase_t > checks.aa1_perimeter_throw_t + 3.0):
				_next("done")


## Spawns a unit at `from` and sends it to `to` without stopping to fight.
func _spawn(type: String, from: Vector3, to: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = from
	if _flat(from, to) > 0.5:
		u.look_at(Vector3(to.x, from.y, to.z))
	commander.submit({"type": "move", "units": [id], "pos": to, "attack": false})
	return u


## A group of attackers ([unit, x, z]): walking to `to`, or (walk false) standing where they are.
func _wave(list: Array, to: Vector3, walk: bool) -> Array:
	var out := []
	for w in list:
		var from := Vector3(w[1], 0.2, w[2])
		var u := _spawn(w[0], from, to if walk else from)
		u.rotation.y = 0.0  # facing the stronghold
		out.append(u)
	return out


## Dead (and maybe already gone from the tree).
static func _down(u) -> bool:
	return not is_instance_valid(u) or not u.is_alive()


## Takes what is left of a staged group off the field.
func _clear(list: Array) -> void:
	for u in list:
		if not _down(u):
			u.take_damage(u.hp + 1.0, GameConfig.TEAM_DEFENDER)


func _centroid(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in list:
		c += u.global_position
	return c / maxf(list.size(), 1)


func _to_perimeter(s: AASquad) -> float:
	return _flat(s.leader.global_position, s._nearest_perimeter(s.leader.global_position)) if s.leader else -1.0


# ---------------------------------------------------------------- piloting AA 1

## Plays AA 1 like a player would (AASquad.pilot), phase by phase.
func pilot_input(s: DefenderSquad, delta: float) -> void:
	var sq := s as AASquad
	sq.input.move = Vector2.ZERO
	sq.input.fire = false
	sq.input.aim = false
	sq.input.hustle = false
	match phase:
		"air":
			if _talon_i < _talons.size() and not _down(_talons[_talon_i]):
				var target: AttackerUnit = _talons[_talon_i]
				# Close to it but not dead on: a little ahead of it and below.
				var at := Combat.aim_point(target) + target.velocity.normalized() * 1.2 + Vector3.DOWN * 0.8
				sq.look_toward(at, 2.6, delta)
				sq.input.aim = phase_t > 0.5
				sq.input.fire = sq.locked
		"ground":
			var alive := _ground.filter(func(u): return not _down(u))
			if _step < 2 and not alive.is_empty():
				# Onto the ground in the middle of them.
				sq.look_toward(_centroid(alive) * Vector3(1, 0, 1), 2.0, delta)
			sq.input.aim = phase_t > 1.5 and phase_t < 5.0
			sq.input.fire = phase_t > 4.45 and phase_t < 4.6
		"mines":
			sq.look_toward(_mine_point + Vector3.UP * 0.2, 2.0, delta)
			sq.input.fire = _step == 2 and phase_t < 2.55
		"hotbar":
			if _step >= 5:
				_drive_to(sq, AA1_OUT, delta)
			else:
				sq.look_toward(sq.leader.global_position + Vector3(0, 2.4, 30), 1.5, delta)


## Walks the squad's leader toward `to` (keys relative to the camera), looking where it goes.
func _drive_to(sq: AASquad, to: Vector3, delta: float) -> void:
	var d := to - sq.leader.global_position
	d.y = 0.0
	if d.length() < 1.0:
		return
	var dir := d.normalized()
	sq.look_toward(sq.leader.global_position + dir * 12.0 + Vector3.UP * 1.8, 1.8, delta)
	var fwd := Vector3(-sin(sq.cam_yaw), 0.0, -cos(sq.cam_yaw))
	var right := Vector3(cos(sq.cam_yaw), 0.0, -sin(sq.cam_yaw))
	sq.input.move = Vector2(dir.dot(right), -dir.dot(fwd))


# ---------------------------------------------------------------- checks

func _watch(delta: float) -> void:
	if phase != "auto" or _released_at < 0.0:
		return
	var s1 := aa[0]
	var s2 := aa[1]
	if s2.leader:
		_aa2_drift = maxf(_aa2_drift, _flat(s2.leader.global_position, _aa2_post))
	_log_cd -= delta
	if _log_cd > 0.0:
		return
	_log_cd = 2.0
	_aa1_dist.append(_to_perimeter(s1))
	_log("  auto %4.1fs  AA1 %-9s %5.1f m to the perimeter, %2d mines down, %d throws | AA2 drift %.1f m, lock %s, missiles %d, strikes %d | AA3 %s, %d mines down" % [
			phase_t, s1.plan, _aa1_dist[-1], s1.mines.size(), s1.stats.throws, _aa2_drift,
			"%.1f s" % s2.lock_progress if s2.lock_target else "-", s2.stats.missiles, s2.stats.strikes, aa[2].plan, aa[2].mines.size()])


func _report() -> void:
	var s1 := aa[0]
	var s2 := aa[1]
	var s3 := aa[2]
	checks["aa1_throws"] = _aa1_throw_kinds
	checks["aa1_walked_back_m"] = _aa1_dist[0] - _aa1_dist.min() if _aa1_dist.size() > 1 else 0.0
	checks["aa2_drift"] = _aa2_drift
	checks["aa2_strikes_in_auto"] = s2.stats.strikes - _aa2_strikes
	checks["aa3_throws"] = s3.stats.throws
	var ok: bool = checks.get("lock_time_1", 0.0) >= AASquad.LOCK_TIME - 0.05 \
			and checks.get("lock_time_2", 0.0) >= AASquad.LOCK_TIME - 0.05 and checks.get("air_kills", 0) == 2 \
			and checks.get("strike_min_gap", 0.0) >= AASquad.STRIKE_SPACING * 0.85 and checks.get("strike_kills", 0) >= 4 \
			and checks.get("mines_thrown", 0) >= 8 and checks.get("mine_blasts", 0) >= 1 \
			and checks.get("f2_drives_aa2", false) and checks.get("f3_drives_aa3", false) and checks.get("f1_drives_aa1", false) \
			and checks.get("ctrl_f1_guard", false) and checks.get("ctrl_f1_mines", false) \
			and checks.has("aa1_here_throw_t") and checks.has("aa1_path_throw_t") and checks.aa1_walked_back_m > 10.0 \
			and checks.has("aa1_perimeter_throw_t") and checks.aa2_drift < 3.0 and checks.aa2_strikes_in_auto == 0 \
			and checks.has("guard_kill_t") and s3.plan == "perimeter" and s3.stats.throws >= 2
	_log("AA SHOWCASE %s %s" % ["PASS" if ok else "FAIL", checks])
	for s in aa:
		_log("  %s alive %d, order %s, plan %s, %d mines down, %s" % [s.station_name, s.troopers.size(),
				AASquad.ORDER_NAMES[s.order], s.plan, s.mines.size(), s.stats])


func _log(text: String) -> void:
	print("[%5.1f] %s" % [maxf(t, 0.0), text])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- screenshots

## Saves a captioned screenshot `delay` seconds from now. `view`: "" the player's own view, else
## one of the staged cameras of the auto phase (aa1, aa2, perimeter).
func _shot(label: String, delay: float, title: String, sub: String, view := "") -> void:
	if shots_dir == "":
		return
	_shot_queue.append({"at": t + delay, "label": label, "title": title, "sub": sub, "view": view})
	_shot_queue.sort_custom(func(a, b): return a.at < b.at)


func _shots_tick() -> void:
	if shots_dir == "" or _saving:
		return
	if _shot_queue.is_empty():
		RenderingServer.render_loop_enabled = false
		return
	var next: Dictionary = _shot_queue[0]
	# Draw the frames just before the shot, so it comes out settled.
	RenderingServer.render_loop_enabled = t >= next.at - 0.15
	if t >= next.at - 0.15:
		_set_view(next.view)
	if t >= next.at:
		_shot_queue.pop_front()
		_save(next)


func _save(s: Dictionary) -> void:
	_saving = true
	_title.text = s.title
	_sub.text = s.sub
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_shot_n += 1
	var path := "%s/%02d_%s.png" % [shots_dir, _shot_n, s.label]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s t=%.1f" % [path, t])
	_saving = false


## The player's own view (with the defender HUD), or a staged camera over the field (with the
## hotbar only).
func _set_view(v: String) -> void:
	if v != _view:
		_view = v
		cam.current = v != ""
		dc.visible = v == ""
		_hotbar.visible = v != ""
		if v == "" and dc.current and dc.current.has_method("get_camera"):
			dc.current.get_camera().current = true
	match v:
		"aa1":
			var c := _squad_centre(aa[0])
			cam.global_position = c + Vector3(-11.0, 7.0, 11.0)
			cam.look_at(c + Vector3(0.0, 0.0, -2.0))
		"aa2":
			var c := _squad_centre(aa[1])
			cam.global_position = c + Vector3(-12.0, 3.5, 9.0)
			cam.look_at(c + Vector3(8.0, 6.0, 2.0))
		"pod":
			var l := aa[0].leader
			cam.global_position = l.global_position + l.global_basis * Vector3(-2.2, 2.6, -2.4)
			cam.look_at(l.global_position + l.global_basis * Vector3(-0.3, 1.9, 0.2))
		"perimeter":
			var c := _squad_centre(aa[0])
			cam.global_position = c + Vector3(-14.0, 14.0, 22.0)
			cam.look_at(c + Vector3(0.0, 0.0, 7.0))


func _squad_centre(s: AASquad) -> Vector3:
	if s.troopers.is_empty():
		return s.home.origin
	var c := Vector3.ZERO
	for tr in s.troopers:
		c += tr.global_position
	return c / s.troopers.size()


func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	_title = _text(root, 30)
	_title.anchor_right = 1.0
	_title.offset_top = 70.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _text(root, 19)
	_sub.anchor_right = 1.0
	_sub.offset_top = 110.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hotbar = SquadHotbar.new()
	_hotbar.visible = false
	_hotbar.keys = DefenderController.ROSTER_KEYS.map(func(k): return OS.get_keycode_string(k))
	root.add_child(_hotbar)


func _text(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.94))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
