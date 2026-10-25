extends Node3D
## Staged run of the Sky Talon's two skills on the real map, aimed the way a player aims them (the
## RTS view, this node working the mouse and keys), against the south face:
##
##   aa            a talon sent over the face: the roof's AA turrets lock on and shoot it down
##   bison         a bison is selected, G, LMB on one AA turret: its shell takes it out from beyond
##                 the turrets' reach
##   bomb_solo     one talon is selected, G, LMB on the other AA turret: it slants in along the face,
##                 drops its bomb on it and breaks away (the turret fires at it until it goes)
##   bomb_group    three talons are box-selected, G, LMB on the mortar: their bombs land round it
##                 along the roof, apart
##   strafe_solo   one talon, F, LMB pressed on a rifleman on the gun deck and dragged along the deck:
##                 it comes in from the field and strafes down the deck
##   strafe_group  three talons, F, LMB pressed on the other rifleman and dragged up the mountain:
##                 three parallel lanes across the face; they climb over the deck and the roof as
##                 they fire and break away from the mountain
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/talon_strike_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie strike.avi \
##       --fixed-fps 30 res://scenes/dev/talon_strike_showcase.tscn -- --video > strike.log
##   python3 tools/video/cut_showcase.py strike.avi strike.log media/talon_strike_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times.
## --test prints what happens and checks it at the end (TALON STRIKE PASS / FAIL), and that no
## talon on a run ever goes into the ground or the stronghold.
## --video draws the run for the video: a third of the frames while the talons wait for their
## targets to be in reach and fly round into position (played at triple speed), and none between
## the end of a strike and the next (cut), as tools/video/cut_showcase.py puts it together.
## The garrison's posts hold fire; the AA turrets don't, and stay down once destroyed.

## Where the talons circle while they wait (out of the turrets' reach; once both turrets are down,
## closer in), the bison and the decoy.
const SOLO_AT := Vector3(-5.0, 0.0, 135.0)
const GROUP_AT := Vector3(30.0, 0.0, 140.0)
const SOLO_NEAR := Vector3(-14.0, 0.0, 118.0)
const GROUP_NEAR := Vector3(12.0, 0.0, 120.0)
const BISON_AT := Vector3(-30.0, 0.0, 135.0)
const DECOY_FROM := Vector3(35.0, 16.0, 112.0)
const DECOY_TO := Vector3(0.0, 0.0, 76.0)
const SOLDIER_W := "Soldier_south_2"
const SOLDIER_E := "Soldier_south_4"
const FIELD_ZOOM := 80.0
## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [3.0, "aa"], [19.0, "bison"], [30.0, "bomb_solo"], [58.0, "bomb_group"],
		[86.0, "strafe_solo"], [114.0, "strafe_group"], [152.0, "outro"], [155.0, "end"]]
## Rendered frames while it plays faster (--video).
const FAST := 3

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var solo: AttackerUnit
var group: Array = []
var bison: AttackerUnit
var decoy: AttackerUnit
var turret_w: AATurret
var turret_e: AATurret
var mortar: Node3D
var soldier_w: Node3D
var soldier_e: Node3D
var t := -1.0
var phase := ""
var test := false
var video := false
var _phase_t := 0.0
var _steps := {}
var _checks: Array[String] = []
var _failed := false
## This phase's strike: the talons on it, their aims, impacts and bombs.
var _strikers: Array = []
var _lanes: Array = []
var _spots: Array[Vector3] = []
var _impacts := {}  # talon -> [positions]
var _bombs: Array = []  # [spot it was aimed at, where it burst]
var _hp_before := {}
var _fired_at := -1.0
## No talon on a run goes into the ground or the stronghold: lowest clearance seen, and the last
## body position of each.
var _lowest := INF
var _through := 0
var _last_body := {}
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
var _cursor_on = null
var _pan_from := Vector3.ZERO
var _pan_to := Vector3.ZERO
var _pan_t := Vector2.ZERO
var _follow := false
var _caption: Label
var _keycap: Label
var _status: Label
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false
var _frame := -1
## --video: "show", "fast" or "cut", and the frame the fast stretch or the cut began on.
var _speed := "show"
var _speed_from := 0


func _ready() -> void:
	test = "--test" in OS.get_cmdline_user_args()
	video = "--video" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	if video:
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the guns, the mortar and the riflemen hold fire.
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
		match String(s.name):
			"Artillery": mortar = s
			SOLDIER_W: soldier_w = s
			SOLDIER_E: soldier_e = s
	for a in level.aa_turrets:
		match String(a.name):
			"AA_S2_2": turret_w = a
			"AA_S4_2": turret_e = a
			_: a.process_mode = Node.PROCESS_MODE_DISABLED  # only the south face's are in it
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	var rig := controller.camera_rig
	rig.edge_scroll = false
	rig.rotation.y = 0.0  # looking north, at the south face
	rig.pitch = deg_to_rad(-52.0)
	rig._target_zoom = FIELD_ZOOM
	rig.zoom = FIELD_ZOOM
	rig.focus(Vector3(0.0, 0.0, 112.0))
	_pan_from = rig.position
	_pan_to = rig.position
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	seed(11)  # the same run every time, however long the navmesh took to bake
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	solo = _talon(SOLO_AT + Vector3(0.0, UnitTypes.FLY_HEIGHT, 14.0), SOLO_AT)
	for k in 3:
		group.append(_talon(GROUP_AT + Vector3(-6.0 + k * 6.0, UnitTypes.FLY_HEIGHT, 14.0 + k * 3.0), GROUP_AT))
	var id := commander.submit({"type": "spawn", "unit": "bison_gun", "spawn": 0})
	bison = commander.units[id]
	bison.global_position = BISON_AT + Vector3.UP * 0.2
	bison.rotation.y = 0.0
	for n in [turret_w, turret_e, mortar, soldier_w, soldier_e]:
		print("STRIKE %s at %s" % [n.name, n.global_position])
	if video:
		print("VIDEO START frame %d" % (_frame + 1))
	t = 0.0


func _talon(pos: Vector3, circle_at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "talon", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos
	u.rotation.y = PI * 0.5
	commander.submit({"type": "move", "units": [id], "pos": circle_at, "attack": false})
	u.strafe_impact.connect(func(at): _impacts.get_or_add(u, []).append(at))
	u.bomb_dropped.connect(_on_bomb)
	return u


func _on_bomb(bomb: TalonBomb, spot: Vector3) -> void:
	var entry := [spot, Vector3.INF]
	_bombs.append(entry)
	bomb.tree_exiting.connect(func(): entry[1] = bomb.global_position)


func _physics_process(_delta: float) -> void:
	if t < 0.0:
		return
	_watch_runs()


func _process(delta: float) -> void:
	_frame += 1
	if t < 0.0:
		return
	t += delta
	var k := 0
	while k < SCRIPT.size() - 1 and t >= SCRIPT[k + 1][0]:
		k += 1
	if SCRIPT[k][1] != phase:
		_end_phase()
		phase = SCRIPT[k][1]
		_phase_t = 0.0
		_steps.clear()
		_follow = false
		if phase == "end":
			_finish()
			return
	_phase_t += delta
	match phase:
		"intro":
			_say("Sky Talon · strafe runs and bomb strikes", "no basic attack: two skills, 90 s cooldown each")
		"aa":
			_aa_step()
		"bison":
			_strike_step([bison], "bombard", turret_w.global_position, Vector3.ZERO,
					"Take the AA down first: a bison shells an AA turret from beyond its reach", turret_w)
		"bomb_solo":
			_strike_step([solo], "bomb", turret_e.global_position, Vector3.ZERO,
					"Bomb strike · one talon → the other AA turret (it fires back)", turret_e)
		"bomb_group":
			_strike_step(group, "bomb", mortar.global_position, Vector3.ZERO,
					"Bomb strike · three talons → the mortar: the bombs land apart along the roof", mortar)
		"strafe_solo":
			_strike_step([solo], "strafe", soldier_w.global_position + Vector3(0.0, 0.0, 1.4), Vector3.RIGHT,
					"Strafe run · one talon down the gun deck: press on the target, drag the way to fly", soldier_w)
		"strafe_group":
			_strike_step(group, "strafe", soldier_e.global_position + Vector3(0.0, 0.0, 1.4), Vector3.FORWARD,
					"Strafe run · three talons, parallel lanes up the face: they climb over the base as they fire", soldier_e)
		"outro":
			_say("", "")
	_update_cursor()
	_update_pan(delta)
	_update_status()
	if video:
		_video_speed()
	if not _snaps.is_empty():
		_snap()


# ---------------------------------------------------------------- the phases

func _aa_step() -> void:
	if _once("start"):
		_say("The roofs' AA turrets lock on to aircraft and fire missiles", "a talon sent over the south face")
		decoy = _talon(DECOY_FROM, DECOY_TO)
		_hp_before[turret_w] = turret_w.fired
		_hp_before[turret_e] = turret_e.fired
	if is_instance_valid(decoy):
		_pan_to_point((decoy.global_position + Vector3(0.0, 0.0, 74.0)) * 0.5 + Vector3(0.0, 0.0, 8.0))


## One strike the way the player does it: select (drag a box round the one or the group),
## the key, the cursor onto the target (for a strafe, press there and drag the way to fly), LMB;
## then the camera follows the run.
func _strike_step(units: Array, skill: String, target: Vector3, drag: Vector3, caption: String, watch: Node3D) -> void:
	var alive := units.filter(func(u): return is_instance_valid(u) and u.is_alive())
	if alive.is_empty():
		return
	if _once("start"):
		_say(caption, "")
		controller._set_selection([])
		_cursor_on = null
		_pan(_centre(alive) + Vector3(0.0, 0.0, -12.0), 0.0, 0.8)  # first onto the ones to select
		controller.camera_rig._target_zoom = FIELD_ZOOM
	# A box dragged round them (round the one too: it is moving), the corner kept on them.
	if _phase_t >= 1.0 and _phase_t < 1.5:
		_move_cursor(_group_rect(alive).position, 1.0, 1.5)
	if _phase_at(1.5, "press"):
		_mouse_button(true)
	if _phase_t > 1.5 and _phase_t < 2.1:
		_move_cursor(_group_rect(alive).end, 1.5, 2.1)
		_mouse_motion()
	if _phase_at(2.1, "release"):
		_mouse_button(false)
	if _phase_at(2.5, "key"):
		print("STRIKE %5.1f s %s: %d of %d selected" % [t, phase, controller.selected.filter(func(u): return u in alive).size(), alive.size()])
		var key := AttackerController.CLUSTER_KEY if skill == "strafe" else AttackerController.BOMBARD_KEY
		_key(key)
		_keycap.text = "F" if skill == "strafe" else "G"
		_keycap.visible = true
	if _phase_at(2.8, "look"):
		_pan(_frame_point(alive, target), 2.8, 3.6)  # then over to the target
	if _phase_at(3.6, "aim"):
		_keycap.visible = false
		_move_cursor(_screen(target), 3.6, 4.8)
	if _phase_t > 4.8 and _phase_t < 5.4:
		_cursor_on = target
	# Fire once every unit has the target within reach (they circle in and out of it).
	var reach: float = alive[0].stats.get(skill + "_range", 0.0) - 6.0
	var in_reach := skill == "bombard" or alive.all(func(u): return _flat(u.global_position, target) <= reach)
	if not _steps.has("fire") and _phase_t > 5.4 and (in_reach or _phase_t > 11.0 or _steps.has("press_t")):
		_cursor_on = target
		if skill != "strafe":
			_fire(units, skill, target)
		else:
			# Press on the target, drag the way to fly, let go.
			if not _steps.has("press_t"):
				_steps.press_t = _phase_t
				_mouse_button(true)
				_keycap.text = "LMB drag"
				_keycap.visible = true
			var held: float = _phase_t - _steps.press_t
			_cursor_on = target + drag * minf(held / 0.8, 1.0) * 14.0
			if held >= 1.0:
				_fire(units, skill, target)
	if _steps.has("fire"):
		if _phase_t - _fired_at > 0.7:
			_keycap.visible = false
			_cursor_on = null
			_follow = true
		if _follow:
			_pan_to_point(_frame_point(alive, target))
	var over := _phase_t - _fired_at > 4.0 if skill == "bombard" else (_phase_t - _fired_at > 1.5 \
			and _strikers.all(func(u): return not is_instance_valid(u) or not u.is_alive() or not u.on_run()))
	if _steps.has("fire") and not _steps.has("report") and over:
		_steps.report = true
		_report(skill, watch)


func _fire(units: Array, skill: String, target: Vector3) -> void:
	_steps.fire = true
	_fired_at = _phase_t
	_impacts.clear()
	_bombs.clear()
	_strikers = units.filter(func(u): return is_instance_valid(u) and u.is_alive())
	for n in [turret_w, turret_e, mortar, soldier_w, soldier_e]:
		_hp_before[n] = n.hp
	if skill == "strafe":
		_mouse_button(false)  # let go: fires
	else:
		_mouse_click_fire()
	_keycap.text = "release" if skill == "strafe" else "LMB"
	_keycap.visible = true
	# What each talon was given to fly (the ones that took it).
	if skill != "bombard":
		_strikers = _strikers.filter(func(u): return u.on_run())
	_lanes = []
	_spots = []
	for u in _strikers:
		if u.is_flying():
			_lanes.append([u._flight.run.a, u._flight.run.b])
			_spots.append(u._flight.run.a)
	var hit := controller._ray(_cursor.position, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	print("STRIKE %5.1f s %s: %s fired by %d at %s (cursor on %s, %.0f m off)" % [t, phase, skill, _strikers.size(), target,
			hit.get("position"), _strikers.map(func(u): return _flat(u.global_position, target)).max()])
	for i in _lanes.size():
		print("STRIKE   %s %d: %s -> %s, run-in %s" % [skill, i, _lanes[i][0], _lanes[i][1], _strikers[i]._flight.run.dir_in])


func _report(skill: String, watch: Node3D) -> void:
	for n in _hp_before:
		if n is Node3D and n.get("hp") != null and n.hp < _hp_before[n]:
			print("STRIKE %s: %s %.0f -> %.0f HP" % [phase, n.name, _hp_before[n], n.hp])
	match skill:
		"bombard":
			_check(not watch.is_alive(), "%s: the AA turret destroyed by the shell" % phase)
		"bomb":
			_check(_bombs.size() == _strikers.size(), "%s: %d bombs for %d talons" % [phase, _bombs.size(), _strikers.size()])
			var worst := 0.0
			for bmb in _bombs:
				worst = maxf(worst, bmb[0].distance_to(bmb[1]) if bmb[1] != Vector3.INF else INF)
			_check(worst < 1.5, "%s: every bomb burst on its spot (worst %.2f m off)" % [phase, worst])
			var spacing: float = _strikers[0].stats.bomb_splash * TalonAim.BOMB_SPACING * 0.9
			for i in _spots.size():
				for j in range(i + 1, _spots.size()):
					_check(_flat(_spots[i], _spots[j]) >= spacing, "%s: bombs %d and %d %.1f m apart" % [phase, i, j, _flat(_spots[i], _spots[j])])
			_check(watch.hp < _hp_before[watch] or not watch.is_alive(), "%s: %s hit" % [phase, watch.name])
			if watch is AATurret:
				_check(not watch.is_alive(), "%s: the AA turret destroyed" % phase)
		"strafe":
			for i in _strikers.size():
				var u = _strikers[i]
				var hits: Array = _impacts.get(u, [])
				var off := 0.0
				for p in hits:
					off = maxf(off, _off_lane(p, _lanes[i]))
				_check(hits.size() >= 12, "%s: talon %d fired %d rounds" % [phase, i, hits.size()])
				_check(off < 3.5, "%s: talon %d's rounds on its lane (worst %.1f m off it)" % [phase, i, off])
			for i in range(1, _lanes.size()):
				var d0: Vector3 = (_lanes[0][1] - _lanes[0][0]).normalized()
				var di: Vector3 = (_lanes[i][1] - _lanes[i][0]).normalized()
				_check(Vector2(d0.x, d0.z).normalized().dot(Vector2(di.x, di.z).normalized()) > 0.999, "%s: lane %d parallel to lane 0" % [phase, i])
			var gaps := []
			for i in _lanes.size():
				for j in range(i + 1, _lanes.size()):
					gaps.append(_off_line((_lanes[i][0] + _lanes[i][1]) * 0.5, _lanes[j]))
			if not gaps.is_empty():
				_check(gaps.min() >= _strikers[0].stats.strafe_lane * 0.9, "%s: lanes %.1f m apart at least" % [phase, gaps.min()])
			_check(watch.hp < _hp_before[watch], "%s: %s hit (%.0f -> %.0f HP)" % [phase, watch.name, _hp_before[watch], maxf(watch.hp, 0.0)])
			for u in _strikers.filter(func(x): return is_instance_valid(x)):
				_check(u.strafe_cd > u.stats.strafe_cooldown - 30.0, "%s: the strafe run on cooldown (%.0f s)" % [phase, u.strafe_cd])


func _end_phase() -> void:
	match phase:
		"aa":
			_check(is_instance_valid(decoy) and not decoy.is_alive() or not is_instance_valid(decoy),
					"aa: the talon over the face shot down")
			_check(turret_w.fired + turret_e.fired > _hp_before[turret_w] + _hp_before[turret_e],
					"aa: the turrets fired %d missiles" % (turret_w.fired + turret_e.fired))
		"bomb_solo":
			_check(is_instance_valid(solo) and solo.is_alive(), "bomb_solo: the talon outlived the turret it bombed (%.0f HP)" % (solo.hp if is_instance_valid(solo) else 0.0))
			# Both turrets down: the talons wait closer in.
			for u in [solo] + group:
				if is_instance_valid(u) and u.is_alive():
					commander.submit({"type": "move", "units": [u.unit_id], "pos": SOLO_NEAR if u == solo else GROUP_NEAR, "attack": false})
	if phase in ["bison", "bomb_solo", "bomb_group", "strafe_solo", "strafe_group"] and not _steps.has("report"):
		_check(false, "%s: the strike was over by the end of the phase" % phase)


## Every step: no talon on a run is in the ground or the stronghold, nor went through it since
## the last step.
func _watch_runs() -> void:
	var space := get_world_3d().direct_space_state
	for u in commander.units.values():
		if not u.is_flying() or not u.is_alive() or not u.on_run():
			_last_body.erase(u)
			continue
		var body: Vector3 = u.global_position + Vector3.UP * TalonFlight.BODY_HEIGHT
		var q := PhysicsRayQueryParameters3D.create(Vector3(body.x, 200.0, body.z), Vector3(body.x, -5.0, body.z), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
		var hit := space.intersect_ray(q)
		var top: float = hit.position.y if not hit.is_empty() else 0.0
		_lowest = minf(_lowest, body.y - top)
		if _last_body.has(u):
			var seg := PhysicsRayQueryParameters3D.create(_last_body[u], body, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
			if not space.intersect_ray(seg).is_empty():
				_through += 1
		_last_body[u] = body


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok
	if test:
		print("STRIKE %5.1f s %s%s" % [t, "ok    " if ok else "FAIL  ", what])


func _finish() -> void:
	_check(_lowest > 1.0 and _through == 0, "no talon on a run went into the ground or the base (lowest %.1f m over it, %d steps through it)" % [_lowest, _through])
	for c in _checks:
		print("STRIKE CHECK ", c)
	print("TALON STRIKE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		_end_speed(_frame)
		print("VIDEO END frame %d" % _frame)
	get_tree().quit()


# ---------------------------------------------------------------- the view

func _centre(units: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in units:
		c += u.global_position
	c /= units.size()
	return Vector3(c.x, 0.0, c.z)


## Between the units and the target, a little toward the target.
func _frame_point(units: Array, target: Vector3) -> Vector3:
	if units.is_empty():
		return target
	var c := Vector3.ZERO
	for u in units:
		c += u.global_position
	c /= units.size()
	var p := c.lerp(target, 0.55)
	return Vector3(p.x, 0.0, p.z + 10.0)


func _pan_to_point(p: Vector3) -> void:
	var rig := controller.camera_rig
	_pan_from = Vector3(rig.position.x, 0.0, rig.position.z).lerp(Vector3(p.x, 0.0, p.z), 0.04)
	_pan_to = _pan_from
	_pan_t = Vector2.ZERO


## --video: a third of the frames while the talons wait for their targets, fly round into position
## and break away (all but the dive), and none once a strike is over (or the decoy is down) until
## the next phase.
func _video_speed() -> void:
	var speed := "show"
	if phase == "aa" and is_instance_valid(decoy) and not decoy.is_alive() and _phase_t > 9.0:
		speed = "cut"
	elif _steps.has("report") or phase == "outro" and _phase_t > 2.0:
		speed = "cut"
	elif phase == "aa" and turret_w.fired + turret_e.fired == 0 and _phase_t > 1.5:
		speed = "fast"  # the decoy on its way in
	elif phase != "aa" and _phase_t > 5.4 and not _steps.has("fire") and not _steps.has("press_t"):
		speed = "fast"
	elif _steps.has("fire") and not _strikers.is_empty() and _strikers.all(func(u):
			return not is_instance_valid(u) or not u.is_alive() or not u.on_run() \
					or u._flight.run.phase != TalonRun.Phase.RUN):
		speed = "fast"  # flying round into position, or breaking away
	if speed != _speed:
		_end_speed(_frame - 1)
		_speed = speed
		_speed_from = _frame
	RenderingServer.render_loop_enabled = speed == "show" or speed == "fast" and (_frame - _speed_from) % FAST == 0


func _end_speed(last: int) -> void:
	if _speed == "fast":
		print("FAST %d frames %d-%d" % [FAST, _speed_from, last])
	elif _speed == "cut":
		print("CUT frames %d-%d" % [_speed_from, last])


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _screen(p: Vector3) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(p)


func _group_rect(units: Array) -> Rect2:
	var r := Rect2(_screen(units[0].global_position + Vector3.UP), Vector2.ZERO)
	for u in units:
		r = r.expand(_screen(u.global_position + Vector3.UP))
	return r.grow(140.0 if units.size() > 1 else 90.0)


func _move_cursor(to: Vector2, start: float, end: float) -> void:
	_cursor_from = _cursor.position
	_cursor_to = to
	_cursor_t = Vector2(start, end)


func _update_cursor() -> void:
	var pos := _cursor_from.lerp(_cursor_to, smoothstep(_cursor_t.x, _cursor_t.y, _phase_t))
	if _cursor_on != null:
		pos = _screen(_cursor_on)
		_cursor_from = pos
		_cursor_to = pos
	get_viewport().warp_mouse(pos)
	_cursor.position = pos


func _pan(to: Vector3, start: float, end: float) -> void:
	_pan_from = controller.camera_rig.position
	_pan_to = to
	_pan_t = Vector2(start, end)


func _update_pan(_delta: float) -> void:
	var rig := controller.camera_rig
	var w := smoothstep(_pan_t.x, _pan_t.y, _phase_t) if _pan_t.y > _pan_t.x else 1.0
	var p := _pan_from.lerp(_pan_to, w)
	rig.position.x = p.x
	rig.position.z = p.z


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _mouse_button(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _mouse_motion() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _mouse_click_fire() -> void:
	get_viewport().warp_mouse(_cursor.position)
	_mouse_button(true)


# ---------------------------------------------------------------- overlay

func _say(title: String, sub: String) -> void:
	var text := title if sub == "" else "%s\n%s" % [title, sub]
	if test and text != _caption.text and title != "":
		print("STRIKE %5.1f s %s" % [t, text.replace("\n", ": ")])
	_caption.text = text
	_caption.visible = title != ""


func _update_status() -> void:
	var lines := []
	for n in [turret_w, turret_e, mortar, soldier_w, soldier_e]:
		var label: String = n.station_name if n.get("station_name") else String(n.name)
		lines.append("%s  %d / %d" % [label, int(maxf(n.hp, 0.0)), int(n.max_hp)])
	_status.text = "\n".join(lines)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_caption = UIKit.label("", 22, Color.WHITE)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y = 64
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_caption)
	_keycap = UIKit.label("", 30, Color(1.0, 0.85, 0.3))
	_keycap.add_theme_color_override("font_outline_color", Color.BLACK)
	_keycap.add_theme_constant_override("outline_size", 8)
	_keycap.position = Vector2(40, 300)
	_keycap.visible = false
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_keycap)
	_status = UIKit.label("", 15, Color(1.0, 0.75, 0.65))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 64)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)
	# Movie Maker doesn't record the system cursor: draw one.
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_cursor)
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 17), Vector2(10, 26),
			Vector2(14, 24), Vector2(10, 15), Vector2(17, 15)])
	arrow.color = Color.WHITE
	var outline := Line2D.new()
	outline.points = arrow.polygon
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.BLACK
	_cursor.add_child(arrow)
	_cursor.add_child(outline)
	_cursor.position = get_viewport().get_visible_rect().size * 0.5
	_cursor_from = _cursor.position
	_cursor_to = _cursor.position


static func _off_lane(p: Vector3, lane: Array) -> float:
	var a := Vector2(lane[0].x, lane[0].z)
	var b := Vector2(lane[1].x, lane[1].z)
	return Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b).distance_to(Vector2(p.x, p.z))


static func _off_line(p: Vector3, lane: Array) -> float:
	var a := Vector2(lane[0].x, lane[0].z)
	var d := (Vector2(lane[1].x, lane[1].z) - a).normalized()
	var q := Vector2(p.x, p.z) - a
	return absf(q.x * d.y - q.y * d.x)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
