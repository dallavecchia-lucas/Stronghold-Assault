extends Node3D
## Staged run of a Flame Squad on the real map (media/flame_squad_showcase.mp4):
##   solo    (video only) a lone Flame Trooper walks, strafes with the gun on its aim and burns:
##           the flame reaches 6 m ahead
##   drive   the squad, bought with N, driven out of the south spawn hall like a player would
##           (this node is its pilot, with a SquadPilot for the walking): up the narrow spawn ramp
##           and through the gate tunnel in file, out through the blast door into a wedge and
##           across the south field to the forest east of the lane, round the trees on its way
##   fight   Night Ops Chimps rush it out of the trees; it burns them as they come in reach
##   tree    at the edge of the forest the player sweeps the flame across a trunk: a quick sweep
##           isn't enough (the heat drains away again); held on it, the canopy catches after 8 s
##   auto    the player goes back to a rifleman on the south deck. Left to itself on its CLEAR
##           order, the squad clears the forest from the trees nearest the base outwards, each
##           trooper burning a tree of its own, and the burnt trees fall about 30 s later; with the
##           forest done it walks on to the next one
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/flame_squad_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
##       res://scenes/dev/flame_squad_showcase.tscn -- --video --snap=20,95 --snap-out=/tmp/flame
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie flame.avi \
##       --fixed-fps 30 res://scenes/dev/flame_squad_showcase.tscn -- --video > flame.log
##   python3 tools/video/cut_showcase.py flame.avi flame.log media/flame_squad_showcase.mp4
##
## --test prints what the squad does and checks it at the end (FLAME SHOWCASE PASS / FAIL); with
## --hall the squad is handed its CLEAR order as soon as it is bought (it walks out of the spawn hall
## and the gate tunnel to the forest on its own), and only the clearing is checked. So does
## --video, the showcase video: the lone trooper first, then the run with cameras cut in, captions
## and the keys the player presses. Most of the clearing plays AUTO_VIDEO times faster; the run
## prints the frames to keep and speed up for cutting the recording, and draws only those.
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times (seconds since
## the start). --video renders with FXAA instead of the project's MSAA. Video-only: the work lights in the hall and the tunnel, the ruler under the lone
## trooper's flame. The garrison's posts and the AA turrets hold fire; the Gunner Squad is left out
## (the Flame Squad deploys in its hall).

## Waypoints of the drive (world): the spawn hall's ramp, the junction, the gate tunnel, the open
## ground, the field, and the edge of the forest (LevelBuilder.FORESTS[0]) facing the trees.
const RAMP_FOOT := Vector3(3.2, 0.0, 58.4)
const RAMP_TOP := Vector3(4.2, 2.7, 64.6)
const JUNCTION := Vector3(4.3, 2.7, 67.9)
const TUNNEL_BEND := Vector3(-3.9, 0.0, 69.6)
const GATE_INSIDE := Vector3(-4.0, 0.0, 76.0)
const OUTSIDE := Vector3(-4.0, 0.0, 87.0)
const OPEN := Vector3(-3.0, 0.0, 96.0)
const FIELD := Vector3(14.0, 0.0, 108.0)
const EDGE := Vector3(32.3, 0.0, 122.6)
## The tree the player burns (the nearest to this), and the Chimps that rush the squad: [x, z].
const DEMO_TREE := Vector3(34.4, 0.0, 126.9)
const CHIMPS := [[24.0, 150.0], [27.0, 153.0], [21.0, 154.0], [30.0, 151.0]]
## The forest it clears (LevelBuilder.FORESTS[0]).
const GROVE := Vector3(42.0, 0.0, 140.0)
## The rifleman the player goes back to: south deck (LevelBuilder.RIFLE_POSTS[0]).
const RIFLEMAN := 4
## How long the squad is left to clear the forest (s), and how long a run may take at most.
const AUTO_TIME := 150.0
const MAX_TIME := 340.0
## Work lights (video-only) along the way out: spawn hall, ramp, junction, tunnel.
const WORK_LIGHTS := [Vector3(-4.0, 3.6, 58.2), Vector3(3.5, 3.6, 58.6), Vector3(4.3, 5.0, 62.5), Vector3(4.3, 5.4, 67.0),
		Vector3(0.0, 4.2, 68.4), Vector3(-4.0, 2.4, 71.0), Vector3(-4.0, 2.4, 75.5)]
## The video's lone trooper: where it starts (facing south), and how long its shots run (s).
const SOLO_AT := Vector3(22.0, 0.0, 94.0)
const SOLO_LENGTH := 12.5
## The clearing in the video: [from, to, how many times faster] (s into the auto phase), then the
## closing shot (s, played as it comes).
const AUTO_VIDEO := [[0.0, 16.0, 1], [16.0, 37.5, 4], [37.5, 47.0, 1], [47.0, 112.0, 4], [112.0, 150.0, 6]]
const OUTRO := 6.5
## Fixed cameras' labels.
const CAM_LABELS := {"hall": "CAM 03 · SPAWN HALL", "tunnel": "CAM 09 · GATE TUNNEL", "gate": "CAM 11 · SOUTH GATE"}

var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var dc: DefenderController
var squad: FlameSquad
var route: SquadPilot
var cam: Camera3D
var test := false
var video := false
var from_hall := false
var t := -1.0
var phase := "setup"
var phase_t := 0.0
var demo: ForestTree
var chimps: Array = []
var solo: FlameTrooper

var _step := 0
var _step_t := 0.0
var _sweep_peak := 0.0
var _sweep_left := -1.0
var _held_from := -1.0
var _demo_caught := -1.0
## Per tree set alight on the CLEAR order: [tree, when, distance from the base]; and per tree that
## has fallen, seconds from catching fire to lying on the ground.
var _ignitions: Array = []
var _falls: Array[float] = []
var _caught_at := {}
var _standing_min := INF
var _regrew := false
var _stuck := {}
var _last_pos := {}
var _worst_stuck := 0.0
var _left_gate := false
var _chimps_burnt := 0
var _log_cd := 0.0
var _checks: Array[String] = []
var _failed := false

# The video: frames drawn so far (the recording's frame numbers), the speed of the stretch being
# recorded and where it began, the shot on screen and what its camera does.
var _frame := -1
var _speed := 1
var _fast_from := 0
var _shot := ""
var _shot_t := 0.0
var _look := Vector3.ZERO
var _crane := Vector3.ZERO
var _work: FlameTrooper
var _work_tree: ForestTree
var _faller: ForestTree
var _fall_done := false
var _hall_done := false
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false
var _ruler: Node3D
var _title: Label
var _sub: Label
var _label: Label
var _rec: Label
var _badge: PanelContainer
var _badge_text: Label
var _badge_t := 0.0
var _fast_mark: Control
var _fade: ColorRect


func _ready() -> void:
	seed(7)  # the same run every time
	var args := OS.get_cmdline_user_args()
	test = "--test" in args
	video = "--video" in args
	from_hall = "--hall" in args
	for arg in args:
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(s): return float(s))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	if video:
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
		# FXAA instead of the project's MSAA: as smooth at this size, in half the time on a software
		# renderer.
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the garrison's posts and the AA turrets hold fire; the Gunner Squad's hall is
	# the Flame Squad's.
	for s in level.stations + level.aa_turrets:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
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
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	for tr in ForestTree.all:
		tr.ignited.connect(_on_ignited)
		tr.fell.connect(_on_fell)
	if video:
		cam.current = true
		_build_lights()
		_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _build_lights() -> void:
	for p in WORK_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.86, 0.68)
		l.light_energy = 1.8
		l.omni_range = 9.0
		l.position = p
		add_child(l)


func _start() -> void:
	# The navmesh's first iteration lands a few frames after the bake.
	for k in 10:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	level.stations[RIFLEMAN].process_mode = Node.PROCESS_MODE_INHERIT
	demo = _nearest_tree(DEMO_TREE)
	t = 0.0
	if video:
		RenderingServer.render_loop_enabled = _snaps.is_empty()
		print("VIDEO START frame %d" % (_frame + 1))
		_spawn_solo()
		_next("solo")
	else:
		_deploy()
		_next("auto" if from_hall else "drive")


## Buys the squad (N) and takes command of it (F1). It deploys in the south spawn hall.
func _deploy() -> void:
	armory = DefenderArmory.new()
	armory.level = level
	armory.credits = DefenderArmory.FLAME_COST
	# The halls go east, west, south in turn: this one is the third.
	armory._bought = 2
	add_child(armory)
	dc = DefenderController.new()
	dc.level = level
	dc.armory = armory
	add_child(dc)
	squad = dc.buy_squad("flame") as FlameSquad
	route = SquadPilot.new([
		{"hold": 1.6, "look": RAMP_FOOT + Vector3(2.0, 1.6, 0.0)},
		{"to": RAMP_FOOT},
		{"to": RAMP_TOP},
		{"to": JUNCTION},
		{"to": TUNNEL_BEND},
		{"to": GATE_INSIDE},
		{"to": OUTSIDE},
		{"to": OPEN},
		{"to": FIELD},
		{"to": EDGE, "hold": 0.6, "look": EDGE + Vector3(-4.0, 1.6, 30.0)},
	])
	squad.pilot = self
	dc.select_squad(0, true)
	if video:
		# The list of posts is for playing; the video's HUD keeps to the squad.
		dc._list.get_parent().visible = false
	_log("start: %s deployed, %d credits left" % [squad.station_name, int(armory.credits)])


func _spawn_solo() -> void:
	solo = FlameTrooper.new()
	add_child(solo)
	solo.global_position = SOLO_AT
	solo.rotation.y = PI  # facing south, away from the mountain
	solo.aim_point = SOLO_AT + Vector3(0.0, 1.0, 30.0)
	solo.following = true
	solo.goal = SOLO_AT


# ---------------------------------------------------------------- the player

## The squad's pilot while the player drives it: the SquadPilot walks the route; the fight and the
## tree are played here.
func pilot_input(s: DefenderSquad, delta: float) -> void:
	match phase:
		"drive":
			route.pilot_input(s, delta)
		"fight":
			_fight_input(s, delta)
		"tree":
			_tree_input(s, delta)
		_:
			s.input.move = Vector2.ZERO
			s.input.fire = false
	if s.input.fire and video and _badge_t < 0.3:
		_press("LMB  ·  flame")


## Looks at the nearest Chimp and burns once it is in reach.
func _fight_input(s: DefenderSquad, delta: float) -> void:
	s.input.move = Vector2.ZERO
	s.input.fire = false
	var near: Node3D = null
	for c in chimps:
		if Combat.is_valid_target(c) and (near == null or _flat(c.global_position, s.leader.global_position) < _flat(near.global_position, s.leader.global_position)):
			near = c
	if near == null:
		s.look_toward(demo.aim_point(), 1.5, delta)
		return
	s.look_toward(Combat.aim_point(near), 3.0, delta)
	s.input.fire = _flat(near.global_position, s.leader.global_position) < FlameTrooper.REACH + 1.5


## A quick sweep across the trunk, a wait while the heat drains, then the flame held on it until
## the canopy catches.
func _tree_input(s: DefenderSquad, delta: float) -> void:
	s.input.move = Vector2.ZERO
	s.input.fire = false
	_step_t += delta
	var trunk := demo.aim_point()
	var across := (trunk - s.leader.global_position).cross(Vector3.UP).normalized()
	match _step:
		0:  # onto the left of the trunk
			s.look_toward(trunk - across * 2.6, 2.0, delta)
			if _step_t > 1.6:
				_step_next()
		1:  # the sweep: across the trunk and off it
			s.look_toward(trunk + across * 2.6, 0.8, delta)
			s.input.fire = _step_t < 1.6
			_sweep_peak = maxf(_sweep_peak, demo.heat)
			if _step_t > 1.8:
				_step_next()
		2:  # the heat drains away
			s.look_toward(trunk + across * 1.5, 1.0, delta)
			if _step_t > 2.6:
				_sweep_left = demo.heat
				_log("sweep: heat peaked at %.2f s, %.2f s left 2.6 s later" % [_sweep_peak, _sweep_left])
				_step_next()
		3:  # back onto the trunk and hold it there
			s.look_toward(trunk, 2.4, delta)
			var on: bool = (s.leader as FlameTrooper).flame_tree == demo
			s.input.fire = _step_t > 0.8
			if on and _held_from < 0.0:
				_held_from = t
			if not demo.is_standing():
				_demo_caught = t
				_log("held: the canopy caught %.1f s after the flame went onto the trunk" % (t - _held_from))
				_step_next()
		4:  # watch it go up
			s.look_toward(trunk + Vector3.UP * demo.height * 0.4, 0.8, delta)
			if _step_t > 3.5:
				_next("auto")


func _step_next() -> void:
	_step += 1
	_step_t = 0.0


# ---------------------------------------------------------------- the run

func _physics_process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	phase_t += delta
	match phase:
		"solo":
			_solo_step()
		"drive":
			if route.done:
				_next("fight")
				for c in CHIMPS:
					chimps.append(_spawn("chimp", Vector3(c[0], 0.2, c[1]), squad.leader.global_position))
		"fight":
			if chimps.all(func(c): return not Combat.is_valid_target(c)) and phase_t > 2.0:
				_chimps_burnt = chimps.size()
				_next("tree")
			elif phase_t > 25.0:
				_next("tree")
		"auto":
			if phase_t > AUTO_TIME:
				if video:
					_next("outro")
				else:
					_finish()
					return
		"outro":
			if phase_t > OUTRO:
				_finish()
				return
	if t > MAX_TIME:
		_finish()
		return
	_watch(delta)


## The video's opening: a lone Flame Trooper walks south, strafes with the gun on its aim, then
## burns: a short burst and a long one, the flame 6 m ahead.
func _solo_step() -> void:
	if phase_t < 4.0:
		solo.pace = Vector3(0.0, 0.0, 2.1)
		solo.goal = SOLO_AT + solo.pace * phase_t
		solo.aim_point = solo.global_position + Vector3(0.0, 1.0, 30.0)
	elif phase_t < 7.6:
		solo.pace = Vector3(1.1, 0.0, 0.0)
		solo.goal = SOLO_AT + Vector3(0.0, 0.0, 8.4) + solo.pace * (phase_t - 4.0)
		var swing := sin(clampf((phase_t - 4.2) / 3.2, 0.0, 1.0) * PI) * 0.5
		solo.aim_point = solo.global_position + Vector3(-sin(swing) * 30.0, 1.0, cos(swing) * 30.0)
	else:
		solo.pace = Vector3.ZERO
		solo.aim_point = solo.global_position + Vector3(0.0, 0.85, 30.0)
		var u := phase_t - 7.6
		solo.trigger = (u > 0.6 and u < 1.1) or (u > 1.8 and u < 4.6)
		if _ruler == null:
			_build_ruler()
	if phase_t > SOLO_LENGTH:
		solo.queue_free()
		solo = null
		_ruler.queue_free()
		_deploy()
		_next("drive")
		_press("N  ·  buy a Flame Squad")


## A line on the ground under the lone trooper's flame, 6 m out from the nozzle (video-only).
func _build_ruler() -> void:
	_ruler = Node3D.new()
	add_child(_ruler)
	var from := solo.nozzle().origin
	from.y = 0.03
	var dir := Vector3(0.0, 0.0, 1.0)
	var mat := Mats.unshaded(Color(1.0, 0.95, 0.75, 0.85))
	_ruler.add_child(Mats.box_mesh(Vector3(0.05, 0.01, FlameTrooper.REACH), from + dir * FlameTrooper.REACH * 0.5, mat))
	for k in range(int(FlameTrooper.REACH) + 1):
		var w := 0.6 if k == 0 or k == int(FlameTrooper.REACH) else 0.25
		_ruler.add_child(Mats.box_mesh(Vector3(w, 0.01, 0.05), from + dir * k, mat))
	var label := Label3D.new()
	label.text = "6 m"
	label.font_size = 64
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1.0, 0.95, 0.75)
	label.position = from + dir * FlameTrooper.REACH + Vector3(0.5, 0.35, 0.0)
	_ruler.add_child(label)


func _next(p: String) -> void:
	phase = p
	phase_t = 0.0
	_step = 0
	_step_t = 0.0
	_log("phase %s" % p)
	if p == "auto":
		# The player goes back to a rifleman: the squad is on its own, on CLEAR.
		dc.select_station(RIFLEMAN, true)
		_press("%d  ·  back to the rifleman · the squad is on its own" % (RIFLEMAN + 1))
		_standing_min = ForestTree.standing.size()


func _on_ignited(tree: ForestTree) -> void:
	_caught_at[tree] = t
	if phase == "auto":
		_ignitions.append([tree, t, LevelBuilder.base_distance(tree.global_position)])
		_log("tree caught at (%.1f, %.1f), %.1f m from the base (%d so far)" % [tree.global_position.x, tree.global_position.z,
				LevelBuilder.base_distance(tree.global_position), _ignitions.size()])


func _on_fell(tree: ForestTree) -> void:
	if _caught_at.has(tree):
		_falls.append(t - _caught_at[tree])


## What the squad does, for the log and the checks.
func _watch(delta: float) -> void:
	if not is_instance_valid(squad) or squad.leader == null:
		return
	if squad.leader.global_position.z > 90.0:
		_left_gate = true
	var n := ForestTree.standing.size()
	if n > _standing_min:
		_regrew = true
	_standing_min = minf(_standing_min, n)
	# A trooper that means to walk and gets nowhere is stuck.
	for tr in squad.troopers:
		var p: Vector3 = tr.global_position
		var want: bool = tr.following and _flat(tr.goal, p) > 1.5
		if want and _last_pos.has(tr) and _flat(_last_pos[tr], p) < 0.25 * delta:
			_stuck[tr] = _stuck.get(tr, 0.0) + delta
			_worst_stuck = maxf(_worst_stuck, _stuck[tr])
		else:
			_stuck[tr] = 0.0
		_last_pos[tr] = p
	_log_cd -= delta
	if _log_cd > 0.0:
		return
	_log_cd = 2.0
	var lp := squad.leader.global_position
	var burning := squad.troopers.filter(func(x): return x.flaming).size()
	_log("%-5s plan %-4s leader (%6.1f, %5.1f, %6.1f) %s jobs %d free %d flaming %d burnt %d standing %d" % [phase,
			squad.plan, lp.x, lp.y, lp.z, SquadFormation.MODE_NAMES[squad.formation.mode], squad.jobs.size(),
			squad.free.size(), burning, squad.burnt.size(), n])


func _finish() -> void:
	_check(_left_gate, "the squad came out of the south gate")
	if not from_hall:
		_check(_chimps_burnt == CHIMPS.size(), "fight: burnt the %d Chimps that rushed it (%d)" % [CHIMPS.size(), _chimps_burnt])
		_check(_sweep_peak > 0.3 and _sweep_peak < 2.0 and _sweep_left < _sweep_peak * 0.35,
				"tree: a quick sweep doesn't do it (heat %.2f s, %.2f s left after 2.6 s)" % [_sweep_peak, _sweep_left])
		var held := _demo_caught - _held_from
		_check(_demo_caught > 0.0 and held > 7.5 and held < 9.5, "tree: held on the trunk, the canopy catches (%.1f s)" % held)
	_check(_ignitions.size() >= 12, "auto: the squad burns the forest on its own (%d trees)" % _ignitions.size())
	if _ignitions.size() >= 10:
		var first := 0.0
		var last := 0.0
		for k in 5:
			first += _ignitions[k][2] / 5.0
			last += _ignitions[_ignitions.size() - 1 - k][2] / 5.0
		_check(first < last, "auto: from the base outwards (first five %.1f m out, last five %.1f m)" % [first, last])
	var groves := {}
	for e in _ignitions:
		groves[(e[0] as ForestTree).grove] = true
	_check(not groves.has(-1), "auto: only forest trees (groves %s)" % [groves.keys()])
	var fmin := INF
	var fmax := 0.0
	for f in _falls:
		fmin = minf(fmin, f)
		fmax = maxf(fmax, f)
	_check(_falls.size() >= 5 and fmin > 27.0 and fmax < 33.5,
			"burnt trees fall about 30 s after catching (%d fell, %.1f to %.1f s)" % [_falls.size(), fmin, fmax])
	_check(not _regrew, "burnt trees don't grow back")
	_check(_worst_stuck < 4.0, "no trooper stuck (longest %.1f s)" % _worst_stuck)
	for c in _checks:
		print("FLAME CHECK ", c)
	print("FLAME SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		if _speed > 1:
			print("FAST %d frames %d-%d" % [_speed, _fast_from, _frame])
		print("VIDEO END frame %d" % _frame)
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _log(text: String) -> void:
	if test or video:
		print("FLAME %6.1f s %s" % [t, text])


# ---------------------------------------------------------------- the director

func _process(delta: float) -> void:
	_frame += 1
	if t < 0.0:
		if video:
			OS.delay_msec(40)  # fewer blank frames in the recording while the navmesh bakes
		return
	if not video:
		return
	_shot_t += delta
	_shots()
	_update_camera(delta)
	_update_overlay(delta)
	_record()
	if not _snaps.is_empty():
		_snap()


## How much faster the video plays this moment of the run.
func _auto_speed() -> int:
	if phase != "auto":
		return 1
	for r in AUTO_VIDEO:
		if phase_t >= r[0] and phase_t < r[1]:
			return r[2]
	return 1


## Keeps every frame of a stretch played as it comes, and every k-th of one played k times faster
## (only those are drawn); prints the fast stretches for tools/video/cut_showcase.py.
func _record() -> void:
	var speed := _auto_speed()
	if speed != _speed:
		if _speed > 1:
			print("FAST %d frames %d-%d" % [_speed, _fast_from, _frame - 1])
		_speed = speed
		_fast_from = _frame
	if _snaps.is_empty():
		RenderingServer.render_loop_enabled = _speed == 1 or (_frame - _fast_from) % _speed == 0


## --snap=t1,t2,..: draws only the frames at those times and saves them (--snap-out=prefix), for
## checking shots without recording the whole video.
func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		print("SNAP %.1f %s %s %.1f" % [at, _shot, phase, phase_t])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


## The shots, in order: the lone trooper from the side, the front and low by its flame; the
## player's own view (tps) in the spawn hall; the hall camera as the squad files into the ramp; the
## player's view again up the ramp; the tunnel camera by the blast door; the gate camera outside as
## the squad comes out into a wedge; a chase camera behind it across the field; the player's view
## at the forest's edge; a low camera beside the squad as the Chimps come in; the player's view for
## the sweep across the trunk; a low camera by the trunk as it catches. Left alone: a wide look over
## the forest as the troopers spread out; close by one at work; the forest from high up (faster);
## close by the first trees as they fall; the forest from high up again; following the squad to the
## next forest; a crane over the cleared forest.
func _shots() -> void:
	match phase:
		"solo":
			var want := "solo_side" if phase_t < 4.0 else ("solo_front" if phase_t < 7.6 else "solo_flame")
			if _shot != want:
				_cut(want)
		"drive":
			var leg := route.leg
			var l := squad.leader.global_position
			match _shot:
				"solo_flame", "":
					_cut("tps")
				"tps":
					if not _hall_done and leg == 1 and l.x > -2.0:
						_hall_done = true
						_cut("hall")
					elif (leg == 5 or leg == 6) and l.z > 71.0 and l.z < 76.0:
						_cut("tunnel")
				"hall":
					if leg >= 4:
						_cut("tps")
				"tunnel":
					if l.z > 75.3:
						_cut("gate")
				"gate":
					if leg >= 8 and _shot_t > 2.0:
						_cut("chase")
				"chase":
					if leg >= 9 and _flat(l, EDGE) < 9.0:
						_cut("tps")
		"fight":
			if _shot == "tps" and phase_t > 1.6:
				_cut("side")
		"tree":
			if _shot != "tps" and _shot != "trunk":
				_cut("tps")
			elif _shot == "tps" and _step == 3 and _held_from > 0.0 and t - _held_from > 4.5:
				_cut("trunk")
		"auto":
			var want := "spread"
			if phase_t >= 112.0:
				want = "next"
			elif phase_t >= 47.0 or (phase_t >= 37.5 and _fall_done):
				want = "grove"
			elif phase_t >= 37.5:
				want = "fall"
			elif phase_t >= 16.0:
				want = "grove"
			elif phase_t >= 7.0:
				want = "work"
			if _shot != want:
				_cut(want)
		"outro":
			if _shot != "outro":
				_cut("outro")


func _cut(shot: String) -> void:
	_shot = shot
	_shot_t = 0.0
	var tps := shot == "tps"
	if is_instance_valid(squad) and squad.possessed:
		squad.get_camera().current = tps
	if not tps:
		cam.current = true
	if is_instance_valid(squad):
		squad.set_hud_visible(tps)
	# Seen from outside the squad nobody steps in front of the camera's nose: no dithering.
	SquadTrooper.set_close_fade(tps)
	if dc:
		dc.visible = tps
	match shot:
		"solo_side", "solo_front", "solo_flame":
			cam.fov = 42.0 if shot == "solo_flame" else 46.0
		"hall":
			cam.fov = 50.0
			cam.global_position = Vector3(-4.5, 3.0, 57.3)
			_look = _centroid()
		"tunnel":
			cam.fov = 60.0
			cam.global_position = Vector3(-5.1, 2.35, 77.6)
			_look = _centroid()
		"gate":
			cam.fov = 52.0
			cam.global_position = Vector3(-12.5, 2.6, 92.5)
			_look = level.gates.south.global_position
		"chase":
			cam.fov = 55.0
			_crane = _chase_goal()
			cam.global_position = _crane
			_look = _centroid() + Vector3.UP
		"side":
			cam.fov = 48.0
			_look = _centroid() + Vector3(-1.5, 1.0, 5.0)
			cam.global_position = _find_view(_look, Vector3(1.0, 0.0, 0.3), 9.0, 1.5, PI * 0.5)
		"trunk":
			cam.fov = 50.0
			var tp := demo.global_position
			var toward := Vector3(squad.leader.global_position.x - tp.x, 0.0, squad.leader.global_position.z - tp.z).normalized()
			_look = tp + toward * 1.5 + Vector3.UP * 2.0
			cam.global_position = _find_view(tp + Vector3.UP * demo.height * 0.45, toward.rotated(Vector3.UP, 0.6), 11.0, 1.8,
					PI * 0.45, squad.leader.global_position + Vector3.UP, demo)
		"spread":
			cam.fov = 50.0
			cam.global_position = GROVE + Vector3(-12.0, 11.0, -30.0)
			_look = GROVE + Vector3(2.0, 1.0, -8.0)
		"work":
			cam.fov = 46.0
			_pick_worker()
		"grove":
			cam.fov = 50.0
			_look = GROVE + Vector3(0.0, 1.0, 2.0)
		"fall":
			cam.fov = 48.0
			_pick_faller()
		"next":
			cam.fov = 55.0
			_crane = _centroid() + Vector3(-16.0, 22.0, -18.0)
			cam.global_position = _crane
			_look = _centroid()
		"outro":
			cam.fov = 50.0
			_look = GROVE + Vector3(0.0, 1.0, 0.0)
	_update_camera(0.0)
	if not tps:
		cam.look_at(_look)


func _update_camera(delta: float) -> void:
	var w := minf(delta * 3.0, 1.0)
	match _shot:
		"solo_side":
			if is_instance_valid(solo):
				var p := solo.global_position
				cam.global_position = cam.global_position.lerp(p + Vector3(-4.4, 1.3, 1.8), w if _shot_t > 0.1 else 1.0)
				cam.look_at(p + Vector3(0.0, 1.1, 0.8))
		"solo_front":
			if is_instance_valid(solo):
				var p := solo.global_position
				cam.global_position = cam.global_position.lerp(p + Vector3(2.8, 1.5, 5.2), w if _shot_t > 0.1 else 1.0)
				cam.look_at(p + Vector3(0.0, 1.0, 0.0))
		"solo_flame":
			if is_instance_valid(solo):
				var p := solo.global_position
				cam.global_position = p + Vector3(-6.8, 1.6, 3.4)
				cam.look_at(p + Vector3(0.0, 0.9, 3.2))
		"hall", "tunnel", "gate":
			_look = _look.lerp(_centroid() + Vector3.UP * 0.6, w)
			cam.look_at(_look)
		"chase":
			_crane = _crane.lerp(_chase_goal(), minf(delta * 1.2, 1.0))
			cam.global_position = _crane
			_look = _look.lerp(_centroid() + Vector3.UP, w)
			cam.look_at(_look)
		"side":
			_look = _look.lerp(_centroid() + Vector3(-1.5, 1.0, 5.0), w * 0.5)
			cam.look_at(_look)
		"trunk":
			var up := demo.height * 0.55 if not demo.is_standing() else 1.6
			var want := demo.global_position + Vector3.UP * up
			_look = _look.lerp(want, w * 0.5)
			cam.look_at(_look)
		"work":
			if _work:
				var tp := _work_tree.global_position
				var wp := _work.global_position if is_instance_valid(_work) else tp
				var up := 1.3 if _work_tree.is_standing() else minf(_work_tree.height * 0.35, 3.2)
				_look = _look.lerp(wp.lerp(tp, 0.55) + Vector3.UP * up, w * 0.4 if _shot_t > 0.1 else 1.0)
				cam.look_at(_look)
		"grove":
			# High over the base side of the forest, looking out over it, slowly swinging round.
			var a := -0.35 + phase_t * 0.006
			cam.global_position = GROVE + Vector3(sin(a) * 40.0, 24.0, -cos(a) * 40.0)
			cam.look_at(_look)
		"fall":
			if _faller:
				var d := _faller._fall_axis.cross(Vector3.UP)
				cam.look_at(_faller.global_position + d * 3.0 + Vector3.UP * 2.4)
		"next":
			_crane = _crane.lerp(_centroid() + Vector3(-16.0, 22.0, -18.0), minf(delta * 0.6, 1.0))
			cam.global_position = _crane
			_look = _look.lerp(_centroid(), minf(delta * 0.8, 1.0))
			cam.look_at(_look)
		"outro":
			var u := clampf(_shot_t / OUTRO, 0.0, 1.0)
			cam.global_position = GROVE + Vector3(-24.0, 5.0, -26.0).lerp(Vector3(-30.0, 15.0, -34.0), u)
			cam.look_at(_look)


## Behind the squad (the way it faces) and above it; pulled in where the mountain is in the way.
func _chase_goal() -> Vector3:
	var from := _centroid() + Vector3.UP * 1.5
	var want := _centroid() + Basis(Vector3.UP, squad.heading) * Vector3(1.5, 3.2, 10.0)
	var ball := SphereShape3D.new()
	ball.radius = 0.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = want - from
	q.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES
	var frac := get_world_3d().direct_space_state.cast_motion(q)
	return from + (want - from) * (frac[0] if frac.size() > 0 else 1.0)


## A trooper at work on a tree that won't catch for a few seconds yet, and a camera low beside it
## with both in view.
func _pick_worker() -> void:
	_work = null
	var best := -1.0
	for tr in squad.jobs:
		var tree: ForestTree = squad.jobs[tr]
		var left := ForestTree.IGNITE_TIME - tree.heat
		if (tr as FlameTrooper).flaming and left > 2.5 and (best < 0.0 or left < best):
			best = left
			_work = tr
			_work_tree = tree
	if _work == null and not squad.jobs.is_empty():
		_work = squad.jobs.keys()[0]
		_work_tree = squad.jobs[_work]
	if _work:
		var tp := _work_tree.global_position
		var wp := _work.global_position
		var back := Vector3(wp.x - tp.x, 0.0, wp.z - tp.z).normalized()
		_look = wp.lerp(tp, 0.55) + Vector3.UP * 1.3
		cam.global_position = _find_view(_look, back.rotated(Vector3.UP, 1.1), 4.8, 1.3, PI * 0.4, wp + Vector3.UP, _work_tree)


## The burning tree that falls next (at least a second and a half from now).
func _pick_faller() -> void:
	_faller = null
	var soonest := INF
	for tr in ForestTree.all:
		if tr.state != ForestTree.State.BURNING:
			continue
		var left: float = tr._fall_at - ForestTree.TOPPLE_TIME - tr.burn_t
		if left > 1.5 and left < soonest:
			soonest = left
			_faller = tr
	if _faller:
		_faller.fell.connect(func(_tr): get_tree().create_timer(3.0, false).timeout.connect(func(): _fall_done = true), CONNECT_ONE_SHOT)
		# From the side of the way it falls, the trunk and the ground it lands on in view.
		var d := _faller._fall_axis.cross(Vector3.UP)
		var tp := _faller.global_position
		cam.global_position = _find_view(tp + Vector3.UP * 2.4, _faller._fall_axis + d * 0.3, 13.0, 2.4, PI * 0.35,
				tp + d * _faller.height * 0.5 + Vector3.UP * 0.5, _faller)


## A spot for the camera looking at `target` from about `dist` away and `height` up, round it from
## the way `toward` points (up to `spread` either side): the first one clear of anything solid and
## of the trees' crowns, with nothing in the way of `target` (nor of `also`). Trees burnt down (and
## `skip`) don't count.
func _find_view(target: Vector3, toward: Vector3, dist: float, height: float, spread: float,
		also := Vector3.INF, skip: ForestTree = null) -> Vector3:
	var base := atan2(toward.x, toward.z)
	for k in 13:
		var a := base + float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0) * spread / 6.0
		for dd in [dist, dist * 1.3, dist * 0.8]:
			var p := Vector3(target.x + sin(a) * dd, height, target.z + cos(a) * dd)
			if _clear_view(p, target, skip) and (also == Vector3.INF or _clear_view(p, also, skip)):
				return p
	return Vector3(target.x, height, target.z) + Vector3(sin(base), 0.0, cos(base)) * dist


func _clear_view(from: Vector3, to: Vector3, skip: ForestTree) -> bool:
	var space := get_world_3d().direct_space_state
	var mask := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS | GameConfig.LAYER_ATTACKERS
	var ball := SphereShape3D.new()
	ball.radius = 0.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.collision_mask = mask
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var seg := to - from
	var ray := PhysicsRayQueryParameters3D.create(from, to - seg.normalized() * 1.0, mask)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.collider != skip:
		return false
	# Crowns have no collision: keep out of them, and see past them.
	var steps := maxi(int(seg.length() / 0.75), 1)
	for tr in ForestTree.all:
		if tr == skip or tr.state == ForestTree.State.FALLEN or _flat(tr.global_position, from) > seg.length() + 12.0:
			continue
		for k in steps:
			var p := from + seg * (float(k) / steps)
			if _flat(p, tr.global_position) < tr.canopy_radius * 0.9 and p.y > tr.height * 0.3:
				return false
	return true


# ---------------------------------------------------------------- overlay

func _caption() -> Array:
	match phase:
		"solo":
			if phase_t < 4.0:
				return ["FLAME TROOPER", "twin fuel tanks, a flame gun at the hip"]
			if phase_t < 7.6:
				return ["FLAME TROOPER", "walks any way, the gun on its aim"]
			return ["FLAME TROOPER", "the flame reaches 6 m ahead"]
		"drive":
			var leg := route.leg
			if leg <= 1 and _shot == "tps":
				return ["FLAME SQUAD", "bought with N · it moves and follows like the Gunner Squad"]
			if _shot == "hall" or _shot == "tunnel":
				return ["", "tight passages: the wedge squeezes, then files in behind you"]
			if leg <= 6:
				return ["", "blast doors open for the squad"]
			if leg <= 7:
				return ["", "out in the open they spread into a wedge"]
			return ["", "on to the forest, round the trees and rocks on the way"]
		"fight":
			return ["", "Chimps rush it out of the trees: all five burn where you aim"]
		"tree":
			if _step <= 2:
				return ["BURNING A TREE", "a quick sweep isn't enough: the heat drains away again"]
			if _step == 3:
				return ["BURNING A TREE", "the flame held on the trunk: 8 s and the canopy catches"]
			return ["BURNING A TREE", "the canopy goes up and the tree is done for"]
		"auto":
			if phase_t < 7.0:
				return ["LEFT TO ITSELF · CLEAR", "it seeks out the forests round the base, the trees nearest the base first"]
			if phase_t < 16.0:
				return ["LEFT TO ITSELF · CLEAR", "each trooper takes a tree of its own and holds the flame on it"]
			if _shot == "fall":
				return ["", "about 30 s after catching, a burnt tree falls"]
			if phase_t < 112.0:
				return ["", "working its way out from the base, tree by tree"]
			return ["", "the forest done, it walks on to the next one"]
		"outro":
			return ["FLAME SQUAD", "burnt forests never grow back · N buys a squad · V: CLEAR / GUARD"]
	return ["", ""]


func _update_overlay(delta: float) -> void:
	var a := 0.0
	if phase == "solo":
		a = 1.0 - clampf(phase_t / 0.8, 0.0, 1.0)
	elif phase == "outro":
		a = clampf((phase_t - OUTRO + 1.5) / 1.5, 0.0, 1.0)
	_fade.color.a = a
	var cap := _caption()
	_title.text = cap[0]
	_sub.text = cap[1]
	_label.text = CAM_LABELS.get(_shot, "")
	_rec.text = "● REC" if CAM_LABELS.has(_shot) and fmod(t, 1.0) < 0.6 else ""
	_badge_t -= delta
	_badge.visible = _badge_t > 0.0
	_badge.modulate.a = clampf(_badge_t / 0.3, 0.0, 1.0)
	_fast_mark.visible = _speed > 1
	_fast_mark.queue_redraw()


## A button the player presses, shown at the bottom of the video for a moment.
func _press(text: String) -> void:
	if not video:
		return
	_badge_text.text = text
	_badge_t = 1.6


func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	_title = _text(root, 34)
	_title.anchor_right = 1.0
	_title.offset_top = 28.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _text(root, 20)
	_sub.anchor_right = 1.0
	_sub.offset_top = 74.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label = _text(root, 20)
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 28.0
	_label.offset_top = -52.0
	_rec = _text(root, 20)
	_rec.anchor_left = 1.0
	_rec.anchor_right = 1.0
	_rec.anchor_top = 1.0
	_rec.anchor_bottom = 1.0
	_rec.offset_left = -120.0
	_rec.offset_top = -52.0
	_rec.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	# The button the player presses, above the hotbar.
	_badge = PanelContainer.new()
	var box := UIKit.panel_style(Color(0.05, 0.06, 0.08, 0.88), 8)
	box.border_color = Color(0.85, 0.9, 1.0, 0.9)
	box.set_border_width_all(2)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	_badge.add_theme_stylebox_override("panel", box)
	_badge.anchor_left = 0.5
	_badge.anchor_right = 0.5
	_badge.anchor_top = 1.0
	_badge.anchor_bottom = 1.0
	_badge.offset_top = -196.0
	_badge.offset_bottom = -152.0
	_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	root.add_child(_badge)
	_badge_text = UIKit.label("", 24, Color(0.97, 0.97, 0.94))
	_badge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_text)
	# Fast forward: two arrows and how much faster, top right.
	_fast_mark = Control.new()
	_fast_mark.anchor_left = 1.0
	_fast_mark.anchor_right = 1.0
	_fast_mark.offset_left = -150.0
	_fast_mark.offset_right = -30.0
	_fast_mark.offset_top = 30.0
	_fast_mark.offset_bottom = 70.0
	_fast_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fast_mark.visible = false
	_fast_mark.draw.connect(_draw_fast_mark)
	root.add_child(_fast_mark)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)


func _draw_fast_mark() -> void:
	var col := Color(0.97, 0.97, 0.94)
	for k in 2:
		var x := 8.0 + k * 20.0
		var tri := PackedVector2Array([Vector2(x, 6), Vector2(x + 18, 20), Vector2(x, 34)])
		_fast_mark.draw_colored_polygon(tri, Color.BLACK)
		_fast_mark.draw_polyline(tri + PackedVector2Array([tri[0]]), Color.BLACK, 4.0, true)
		_fast_mark.draw_colored_polygon(tri, col)
	var font := _fast_mark.get_theme_default_font()
	_fast_mark.draw_string_outline(font, Vector2(54, 31), "%d×" % _speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 7, Color.BLACK)
	_fast_mark.draw_string(font, Vector2(54, 31), "%d×" % _speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)


func _text(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.94))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- helpers

func _spawn(type: String, from: Vector3, to: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = from
	u.look_at(Vector3(to.x, from.y, to.z))
	commander.submit({"type": "move", "units": [id], "pos": to, "attack": true})
	return u


func _nearest_tree(p: Vector3) -> ForestTree:
	var best: ForestTree = null
	for tr in ForestTree.standing:
		if best == null or _flat(tr.global_position, p) < _flat(best.global_position, p):
			best = tr
	return best


## Middle of the squad around its leader (a replacement still on its way from the post left out).
func _centroid() -> Vector3:
	if not is_instance_valid(squad) or squad.leader == null:
		return GROVE
	var c := Vector3.ZERO
	var n := 0
	for tr in squad.troopers:
		if tr.global_position.distance_to(squad.leader.global_position) < 20.0:
			c += tr.global_position
			n += 1
	return c / n


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
