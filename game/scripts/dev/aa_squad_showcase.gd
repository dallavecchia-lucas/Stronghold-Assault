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
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie aa.avi \
##       --fixed-fps 30 res://scenes/dev/aa_squad_showcase.tscn -- --video
##
## All three print what the squads do and check it at the end (AA SHOWCASE PASS / FAIL); --shots
## also saves a captioned screenshot at each moment worth seeing into DIR (drawing only those
## frames). --video is the showcase video, for recording with Movie Maker: a lone Missile Trooper
## first (walk, strafe, rockets), then the run with cameras cut in, captions and the buttons the
## player presses. It prints the frame the video starts on (VIDEO START) and the frames to play
## FAST times faster (FAST: the wait for the mines' cooldown at the perimeter), for cutting the
## recording; with --snap=t1,t2,.. --snap-out=prefix it draws and saves only the frames at those
## video times. The garrison's posts hold fire.

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
## The video's lone Missile Trooper: where it starts (facing south), and where its rockets land.
const SOLO_AT := Vector3(24.0, 0.0, 100.0)
const SOLO_TARGET := Vector3(30.0, 0.0, 138.0)
## Its cameras: [offset of the camera, offset of the point it looks at] from the trooper.
const SOLO_CAMS := {
	"solo_side": [Vector3(4.2, 1.35, 1.4), Vector3(0.0, 1.3, 0.6)],
	"solo_front": [Vector3(2.6, 1.55, 4.4), Vector3(0.0, 1.3, 0.0)],
	"solo_launch": [Vector3(2.6, 2.3, -4.6), Vector3(-0.5, 4.0, 16.0)],
	"solo_pod": [Vector3(1.3, 2.15, 1.9), Vector3(0.45, 1.95, 0.15)],
}
## The video's timing (s): the lone trooper; the title over the squads before the aircraft come;
## the minefield; the closing shot. The wait at the perimeter plays FAST times faster.
const SOLO_LENGTH := 11.5
const VIDEO_SETUP := 4.5
const VIDEO_MINES := 12.5
const OUTRO := 5.0
const FAST := 4

var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var dc: DefenderController
var aa: Array[AASquad] = []
var cam: Camera3D
var shots_dir := ""
var video := false
var t := -1.0
var phase := "setup"
var phase_t := 0.0
var checks := {}

var _step := 0
var _talons: Array = []
var _talon_i := 0
var _lock_started := -1.0
var _air_done := -1.0
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

# The video: its clock, the frames drawn so far (the recording's frame numbers), the lone
# trooper, the shot on screen and what its camera follows.
var vt := 0.0
var _frame := -1
var solo: MissileTrooper
var _solo_fired := 0
var _cut := ""
var _cut_t := 0.0
var _look := Vector3.ZERO
var _travel := Vector3.FORWARD
var _travel_yaw := 0.0
var _follow: Node3D
var _followed := false
var _follow_held := false
var _follow_at := Vector3.ZERO
var _follow_dir := Vector3.ZERO
var _strike_at := Vector3.ZERO
var _pilot_aim := false
var _pilot_fire := false
var _fast := false
var _fast_from := 0
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false
var _badge: PanelContainer
var _badge_text: Label
var _badge_t := 0.0
var _fast_mark: Control
var _fade: ColorRect


func _ready() -> void:
	seed(7)  # the same run every time
	var args := OS.get_cmdline_user_args()
	video = "--video" in args
	for arg in args:
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(s): return float(s))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
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
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		RenderingServer.render_loop_enabled = false
		_build_overlay()
	elif video:
		cam.current = true
		cam.global_position = SOLO_AT + SOLO_CAMS.solo_side[0]
		cam.look_at(SOLO_AT + SOLO_CAMS.solo_side[1])
		RenderingServer.render_loop_enabled = _snaps.is_empty()
		_build_overlay()
		# The seeking missiles, for the camera that rides behind one.
		child_entered_tree.connect(_on_child)
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# The navmesh's first iteration lands a few frames after the bake.
	for k in 10:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	level.stations[RIFLEMAN].process_mode = Node.PROCESS_MODE_INHERIT
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))
		_spawn_solo()
		phase = "solo"
	else:
		_deploy()


## Buys the three squads and sends them out into the south field, AA 1 in the player's hands.
func _deploy() -> void:
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
	if video:
		# The list of posts is for playing; the video's HUD keeps to the squads.
		dc._list.get_parent().visible = false
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
		"solo":
			_solo_step()
		"setup":
			if phase_t > (VIDEO_SETUP if video else 1.5):
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
			if video:
				if phase_t > OUTRO:
					_finish()
			elif phase_t > 0.5 and _shot_queue.is_empty() and not _saving:
				_finish()
	_watch(delta)
	_shots_tick()


func _next(p: String) -> void:
	phase = p
	phase_t = 0.0
	_step = 0
	_log("phase %s" % p)


func _finish() -> void:
	_report()
	if video:
		print("VIDEO END frame %d" % _frame)
	get_tree().quit()


## The video's opening: a lone Missile Trooper walks south, strafes with the pod on its aim (up
## into the sky and back down), then fires three rockets at a spot downrange and reloads.
func _solo_step() -> void:
	if phase_t < 4.0:
		solo.pace = Vector3(0.0, 0.0, 2.1)
		solo.goal = SOLO_AT + solo.pace * phase_t
		solo.aim_point = solo.global_position + Vector3(0.0, 1.4, 40.0)
	elif phase_t < 7.4:
		solo.pace = Vector3(1.2, 0.0, 0.0)
		solo.goal = SOLO_AT + Vector3(0.0, 0.0, 8.4) + solo.pace * (phase_t - 4.0)
		var up := sin(clampf((phase_t - 4.3) / 2.8, 0.0, 1.0) * PI) * deg_to_rad(50.0)
		solo.aim_point = solo.global_position + Vector3(0.0, 1.4, 0.0) + Vector3(0.0, sin(up), cos(up)) * 40.0
	else:
		solo.pace = Vector3.ZERO
		solo.aim_point = SOLO_TARGET + Vector3.UP
		# Up over the spot, as the squad does: the rockets climb before they dive.
		solo.pod_target = SOLO_TARGET + Vector3.UP * maxf(_flat(solo.global_position, SOLO_TARGET) * 0.9, 8.0) \
				if phase_t < 9.0 else Vector3.INF
		while _solo_fired < 3 and phase_t > 8.0 + _solo_fired * AASquad.STRIKE_STAGGER:
			var a := _solo_fired * 2.1
			var off := Vector3(cos(a), 0.0, sin(a)) * (1.8 if _solo_fired > 0 else 0.0)
			solo.launch_rocket(_ground_at(SOLO_TARGET + off), AASquad.STRIKE_DAMAGE, AASquad.STRIKE_SPLASH)
			_solo_fired += 1
	if phase_t > SOLO_LENGTH:
		solo.queue_free()
		solo = null
		_deploy()
		_next("setup")


func _spawn_solo() -> void:
	solo = MissileTrooper.new()
	add_child(solo)
	solo.global_position = SOLO_AT + Vector3.UP * 0.2
	solo.rotation.y = PI  # facing south, away from the mountain
	solo.aim_point = SOLO_AT + Vector3(0.0, 1.4, 40.0)
	solo.following = true
	solo.goal = SOLO_AT


func _air_step() -> void:
	var s := aa[0]
	if _talon_i >= _talons.size() and _air_done < 0.0:
		_air_done = phase_t
	# The video stays on the last one going down a moment longer.
	if (_air_done >= 0.0 and phase_t >= _air_done + (1.6 if video else 0.0)) or phase_t > 28.0:
		checks["air_kills"] = _talons.filter(func(u): return _down(u)).size()
		_ground = _wave(GROUND, Vector3.ZERO, false)
		_next("ground")
		return
	if _talon_i >= _talons.size():
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
		_strike_at = at
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
		_press("F")
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
		if phase_t > (VIDEO_MINES if video else 19.0):
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
			_press("F2")
			_shot("hotbar_f2", 1.0, "HOTBAR · F2", "takes command of AA Squad 2 (its auto order: GUARD)")
		1:
			if phase_t > 2.5:
				_step = 2
				checks["f2_drives_aa2"] = dc.current == aa[1] and aa[1].possessed and not aa[0].possessed
				dc.cycle_squad_order(0)
				_press("Ctrl + F1")
				checks["ctrl_f1_guard"] = aa[0].order == AASquad.Order.GUARD
				_shot("hotbar_ctrl_f1", 0.3, "HOTBAR · Ctrl+F1", "AA Squad 1's auto order is now GUARD, set from wherever you are")
		2:
			if phase_t > 4.2:
				_step = 3
				dc.select_squad(2)
				_press("F3")
				_shot("hotbar_f3", 1.0, "HOTBAR · F3", "takes command of AA Squad 3")
		3:
			if phase_t > 6.5:
				_step = 4
				checks["f3_drives_aa3"] = dc.current == aa[2] and aa[2].possessed and not aa[1].possessed
				dc.cycle_squad_order(0)
				checks["ctrl_f1_mines"] = aa[0].order == AASquad.Order.MINES
				dc.select_squad(0)
				_press("Ctrl + F1    F1")
				_shot("hotbar_f1", 1.0, "HOTBAR · F1", "back on AA Squad 1 (its order MINES again)")
		4:
			if phase_t > 8.0:
				_step = 5
				checks["f1_drives_aa1"] = dc.current == aa[0] and aa[0].possessed and not aa[2].possessed
				_press("W A S D")
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
			_press(str(RIFLEMAN + 1))
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


## The ground under `p`.
func _ground_at(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 20.0, GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


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
	# The video shows the buttons as they go down.
	if sq.input.aim and not _pilot_aim:
		_press("hold RMB")
	if sq.input.fire and not _pilot_fire:
		_press("LMB")
	_pilot_aim = sq.input.aim
	_pilot_fire = sq.input.fire


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
		var at := s.get_station_position()
		_log("  %s at (%.0f, %.0f) alive %d, order %s, plan %s, %d mines down, %s" % [s.station_name, at.x, at.z,
				s.troopers.size(), AASquad.ORDER_NAMES[s.order], s.plan, s.mines.size(), s.stats])


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


# ---------------------------------------------------------------- the video

func _process(delta: float) -> void:
	_frame += 1
	if not video or t < 0.0:
		return
	vt += delta
	_cut_t += delta
	_track(delta)
	_cut_to(_pick_shot())
	_update_camera(delta)
	_update_overlay(delta)
	_fast_forward()
	if not _snaps.is_empty():
		_snap()


## The shot for this moment of the run: the player's own view (tps, or fps on the rifleman) or
## one of the cameras over the field.
func _pick_shot() -> String:
	match phase:
		"solo":
			return "solo_side" if phase_t < 4.0 else ("solo_front" if phase_t < 7.4 else ("solo_launch" if phase_t < 10.0 else "solo_pod"))
		"setup":
			return "establish" if phase_t < 2.6 else "tps"
		"air":
			# The first lock in the player's view; the second from beside the pods, then riding
			# behind a missile.
			if checks.has("lock_time_2"):
				return "missile" if _followed else "pods"
			if _talon_i == 1 and _lock_started >= 0.0 and t - _lock_started > 1.5:
				return "pods"
			return "tps"
		"ground":
			if phase_t < 4.5:
				return "tps"
			if phase_t < 5.6:
				return "pod"
			return "impact" if phase_t < 9.0 else "tps"
		"mines":
			if phase_t < 2.5:
				return "tps"
			return "throw" if phase_t < 5.0 else "field"
		"hotbar":
			if _step < 5 or phase_t < 11.0:
				return "tps"
			return "walk_side" if phase_t < 16.0 else "walk_front"
		"auto":
			if phase_t < 1.4:
				return "fps"
			if phase_t < 4.2:
				return "aa1"
			if phase_t < 8.8:
				return "aa2"
			if phase_t < 11.0:
				return "fps"
			if phase_t < 17.5:
				return "path"
			return "overview" if phase_t < 20.5 else "perimeter"
		"done":
			return "outro"
	return _cut


func _cut_to(shot: String) -> void:
	if shot == _cut:
		return
	_cut = shot
	_cut_t = 0.0
	# Seen from outside the squad nobody steps in front of the camera's nose: no dithering.
	SquadTrooper.set_close_fade(_player_view())
	cam.fov = {"solo_side": 46.0, "solo_front": 46.0, "solo_launch": 50.0, "solo_pod": 40.0, "establish": 50.0,
			"missile": 60.0, "impact": 48.0, "field": 52.0, "walk_side": 48.0, "walk_front": 46.0}.get(shot, 55.0)


func _player_view() -> bool:
	return _cut == "tps" or _cut == "fps"


## The way AA 1's leader walks, smoothed (for the cameras that track it).
func _track(delta: float) -> void:
	if aa.is_empty() or aa[0].leader == null:
		return
	var v := aa[0].leader.velocity
	if Vector2(v.x, v.z).length() > 0.5:
		_travel_yaw = lerp_angle(_travel_yaw, atan2(v.x, v.z), minf(delta * 1.5, 1.0))
		_travel = Vector3(sin(_travel_yaw), 0.0, cos(_travel_yaw))


func _update_camera(delta: float) -> void:
	# The player's view, or this camera; the HUD only with the player's view.
	var player := _player_view()
	if player and dc and dc.current:
		dc.current.get_camera().current = true
	else:
		cam.current = true
	if dc:
		dc.visible = player
		for s in aa:
			s.set_hud_visible(player)
	if _hotbar:
		_hotbar.visible = not player and armory != null and phase in ["setup", "auto", "done"]
		_hotbar.current = dc.current if dc else null
	if player:
		return
	var w := minf(delta * 3.0, 1.0)
	var pos := cam.global_position
	var look := _look
	match _cut:
		"solo_side", "solo_front", "solo_launch", "solo_pod":
			if not is_instance_valid(solo):
				return
			pos = solo.global_position + SOLO_CAMS[_cut][0]
			look = solo.global_position + SOLO_CAMS[_cut][1]
		"establish":
			# A slow crane over AA 1, the other two squads out past it.
			var c := _squad_centre(aa[0])
			pos = c + Vector3(lerpf(8.0, -4.0, smoothstep(0.0, 2.6, _cut_t)), 3.4, 9.5)
			look = c + Vector3(0.0, 1.4, -4.0)
			w = 1.0
		"pods":
			# Low behind the squad, past the pods up at the aircraft.
			var c := _squad_centre(aa[0])
			var tal = _talons[mini(_talon_i, _talons.size() - 1)]
			var at := Combat.aim_point(tal) if not _down(tal) else _look
			var dir := _flat_dir(at - c)
			pos = c - dir * 4.0 + Vector3.UP.cross(dir) * 2.2 + Vector3.UP * 1.1
			look = c + Vector3.UP * 1.8 + (at - c - Vector3.UP * 1.8) * 0.3
		"missile":
			# Riding behind the missile until it closes in, then holding back with the aircraft
			# in view as the volley hits.
			w = 1.0
			var tal = _talons[1]
			var aim := Combat.aim_point(tal) if is_instance_valid(tal) else _follow_at
			if is_instance_valid(_follow) and not _follow_held:
				var d := -_follow.global_basis.z
				_follow_dir = d if _follow_dir == Vector3.ZERO else _follow_dir.lerp(d, minf(delta * 6.0, 1.0)).normalized()
				_follow_at = _follow.global_position
				pos = _follow_at - _follow_dir * 4.5 + Vector3.UP * 0.9
				look = _follow_at + _follow_dir * 10.0
				_follow_held = _follow_at.distance_to(aim) < 12.0
			else:
				pos = cam.global_position + (cam.global_position - aim).normalized() * delta * 2.0
				look = _look.lerp(aim, minf(delta * 4.0, 1.0))
		"pod":
			var l := aa[0].leader
			if l:
				pos = l.global_position + l.global_basis * Vector3(-2.2, 2.6, -2.4)
				look = l.global_position + l.global_basis * Vector3(-0.3, 1.9, 0.2)
		"impact":
			# Low beside the spots, the rockets coming down from the squad's side.
			var dir := _flat_dir(_strike_at - _squad_centre(aa[0]))
			pos = _strike_at + dir.cross(Vector3.UP) * 16.0 - dir * 5.0 + Vector3.UP * 2.5
			look = _strike_at + Vector3.UP * 1.5 - dir
		"throw":
			# Beside the squad on its throwing-arm side.
			var c := _squad_centre(aa[0])
			var fwd := _flat_dir(_mine_point - c)
			pos = c + fwd.cross(Vector3.UP) * 10.0 - fwd + Vector3.UP * 2.2
			look = c + fwd * 5.5 + Vector3.UP * 0.8
		"field":
			# Low behind the minefield, the walkers coming on into it.
			var fwd := _flat_dir(_mine_point - AA1_AT)
			var right := fwd.cross(Vector3.UP)
			pos = _mine_point - fwd * 8.0 + right * 7.0 + Vector3.UP * 1.5
			look = _mine_point + fwd * 8.0 - right + Vector3.UP * 0.5
		"walk_side":
			var c := _squad_centre(aa[0])
			pos = c + Vector3.UP.cross(_travel) * 9.0 + Vector3.UP * 1.8 - _travel
			look = c + _travel * 1.5 + Vector3.UP * 1.1
		"walk_front":
			var c := _squad_centre(aa[0])
			pos = c + _travel * 10.0 + Vector3.UP.cross(_travel) * 4.0 + Vector3.UP * 1.2
			look = c + Vector3.UP * 1.3
		"aa1":
			# Side on to the throw: the squad, and where its mines come down.
			var c := _squad_centre(aa[0])
			var d := _flat_dir(aa[0]._face_at - c)
			pos = c + d * 7.0 + Vector3.UP.cross(d) * 15.0 + Vector3.UP * 7.0
			look = c + d * 7.0
		"aa2":
			var c := _squad_centre(aa[1])
			pos = c + Vector3(-12.0, 3.5, 9.0)
			look = c + Vector3(8.0, 6.0, 2.0)
		"path":
			# Beside AA 1 walking home, looking back along the path it mines.
			var c := _squad_centre(aa[0])
			pos = c + Vector3.UP.cross(_travel) * 12.0 + Vector3.UP * 5.5 - _travel
			look = c - _travel * 5.0 + Vector3.UP * 0.3
		"overview":
			# High over AA 1 coming in, the mines along the perimeter ahead of it.
			var c := _squad_centre(aa[0])
			pos = c + Vector3(-6.0, 18.0, 24.0)
			look = c + Vector3(0.0, 0.0, -6.0)
		"perimeter":
			var c := _squad_centre(aa[0])
			pos = c + Vector3(-10.0, 9.5, 16.0)
			look = c + Vector3(0.0, 0.0, 4.0)
		"outro":
			# An arc round AA 1, the stronghold behind it.
			var c := _squad_centre(aa[0])
			var a := -0.6 + _cut_t * 0.2
			pos = c + Vector3(sin(a) * 11.0, 2.4, cos(a) * 11.0)
			look = c + Vector3.UP * 2.2
	if _cut_t == 0.0:
		w = 1.0
	cam.global_position = cam.global_position.lerp(pos, w)
	_look = _look.lerp(look, w) if _cut != "missile" else look
	if not cam.global_position.is_equal_approx(_look):
		cam.look_at(_look)


static func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.01 else Vector3.FORWARD


## The first seeking missile off the pods at the second Sky Talon: the camera rides behind it.
func _on_child(n: Node) -> void:
	if n is HomingMissile and not _followed and phase == "air" and _talon_i == 1 and aa[0].locked:
		_follow = n
		_followed = true


## AA 1 walking to its spot at the perimeter and waiting there for its mines to come ready plays
## FAST times faster (the frames to drop are printed, the video shows it).
func _fast_forward() -> void:
	var want := false
	if phase == "auto":
		var s := aa[0]
		var walking := s._spot != Vector3.INF and _flat(s.leader.global_position, s._spot) > AASquad.SPOT_REACH + 2.0
		want = phase_t > 20.5 and not checks.has("aa1_perimeter_throw_t") and s.stats.throws == _aa1_throws \
				and (s.mine_cd > 1.2 or walking)
	if want == _fast:
		return
	_fast = want
	if _fast:
		_fast_from = _frame
	else:
		print("FAST %d frames %d-%d" % [FAST, _fast_from, _frame - 1])


## A button the player presses, shown at the bottom of the video for a moment.
func _press(text: String) -> void:
	if not video:
		return
	_badge_text.text = text
	_badge_t = 1.4


func _caption() -> Array:
	match phase:
		"solo":
			return ["MISSILE TROOPER", ["a six-missile pod on the left shoulder",
					"strafing: the legs step sideways, the pod stays on the aim",
					"rockets: the pod swings up over the spot, they dive onto it",
					"empty tubes reload one at a time"][0 if phase_t < 4.0 else (1 if phase_t < 7.4 else (2 if phase_t < 10.0 else 3))]]
		"setup":
			return ["AA SQUAD", "five Missile Troopers · bought with credits (B), a hotbar key each" if phase_t < 2.6
					else "you drive the trooper in the middle, the other four follow your lead"]
		"air":
			if _cut == "missile":
				return ["AIR · missiles away", "they home in on the locked aircraft"]
			if _cut == "pods":
				return ["AIR · the pods follow the lock", "every trooper's pod swings onto the aircraft"]
			if _talon_i == 0 and not checks.has("lock_time_1"):
				return ["AIR · hold RMB close to an aircraft", "3 s to lock on: keep the aim near it, it needn't be dead on"]
			if _talon_i == 0:
				return ["LOCKED · LMB", "seeking missiles from the pods: as many as the kill takes"]
			return ["AIR · the next one", "lock on again: the box closes in over 3 s"]
		"ground":
			if phase_t < 1.5:
				return ["GROUND · rocket strike", "aim at enemy ground units"]
			if phase_t < 4.5:
				return ["GROUND · RMB shows where the rockets land", "a spot per trooper round the aim: clustered, never on top of each other"]
			if phase_t < 5.6:
				return ["GROUND · LMB fires", "up to three rockets from every pod"]
			return ["GROUND · impact", "each trooper's rockets dive onto its own spot"]
		"mines":
			if phase_t < 2.5:
				return ["MINES · F aims the throw", "a cone ahead like the Hippo's smoke: the mines land sparsely over the band"]
			if phase_t < 5.0:
				return ["MINES · LMB throws", "two from every trooper, then 15 s to the next throw"]
			return ["MINES · armed once they land", "they go off under enemy ground units; aircraft pass over"]
		"hotbar":
			if phase_t < 2.5:
				return ["HOTBAR · F2", "takes command of AA Squad 2 (its auto order: GUARD)"]
			if phase_t < 4.2:
				return ["HOTBAR · Ctrl+F1", "sets AA Squad 1's auto order from anywhere: now GUARD"]
			if phase_t < 6.5:
				return ["HOTBAR · F3", "AA Squad 3, laying mines along the base perimeter"]
			if phase_t < 8.0:
				return ["HOTBAR · Ctrl+F1, F1", "AA Squad 1 back on MINES, and back in command of it"]
			return ["THIRD PERSON · moves like the Gunner Squad", "the wedge follows your lead, the pods track your aim"]
		"auto":
			if phase_t < 1.4:
				return ["AUTO · back on a rifleman", "each AA Squad carries on with its own auto order"]
			if phase_t < 4.2:
				return ["AUTO · AA 1 on MINES", "handed back out in the field: it lays mines right there"]
			if phase_t < 8.8:
				return ["AUTO · AA 2 on GUARD", "holds its post and shoots down aircraft in range, never ground units"]
			if phase_t < 11.0:
				return ["AUTO · the hotbar shows what each squad is doing", "AA 1 heading back to base, AA 2 holding, AA 3 at the perimeter"]
			if phase_t < 17.5:
				return ["AUTO · AA 1 heads back to base", "laying mines on the path behind it as they come ready"]
			if _fast or phase_t < 20.5:
				return ["AUTO · at the base: mines along the perimeter", "outside the gates, where the fewest are"]
			return ["AUTO · AA 1's next mines", "along the perimeter, as soon as they're ready again"]
		"done":
			return ["AA SQUAD", "B buys one · F1–F6 takes command · Ctrl+F1–F6 sets its auto order"]
	return ["", ""]


func _update_overlay(delta: float) -> void:
	var a := 1.0 - clampf(vt / 0.8, 0.0, 1.0)
	match phase:
		"solo":
			a = maxf(a, clampf((phase_t - SOLO_LENGTH + 0.35) / 0.35, 0.0, 1.0))
		"setup":
			a = 1.0 - clampf(phase_t / 0.35, 0.0, 1.0)
		"done":
			a = clampf((phase_t - OUTRO + 1.5) / 1.5, 0.0, 1.0)
	_fade.color.a = a
	var cap := _caption()
	_title.text = cap[0]
	_sub.text = cap[1]
	_badge_t -= delta
	_badge.visible = _badge_t > 0.0
	_badge.modulate.a = clampf(_badge_t / 0.3, 0.0, 1.0)
	_fast_mark.visible = _fast


## --snap=t1,t2,..: draws only the frames at those video times and saves them (--snap-out=prefix),
## for checking shots without recording the whole video.
func _snap() -> void:
	RenderingServer.render_loop_enabled = vt >= _snaps[0] - 0.05
	if vt >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		print("SNAP %.1f %s %s %.1f" % [at, _cut, phase, phase_t])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- overlay

func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	_title = _text(root, 34 if video else 30)
	_title.anchor_right = 1.0
	_title.offset_top = 28.0 if video else 70.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _text(root, 20 if video else 19)
	_sub.anchor_right = 1.0
	_sub.offset_top = 74.0 if video else 110.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hotbar = SquadHotbar.new()
	_hotbar.visible = false
	_hotbar.keys = DefenderController.ROSTER_KEYS.map(func(k): return OS.get_keycode_string(k))
	root.add_child(_hotbar)
	if not video:
		return
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
	_fast_mark.draw_string_outline(font, Vector2(54, 31), "%d×" % FAST, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 7, Color.BLACK)
	_fast_mark.draw_string(font, Vector2(54, 31), "%d×" % FAST, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)


func _text(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.94))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
