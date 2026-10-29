extends Node3D
## Staged run of the Armored Lioness on the real map, in the south field: her skills used the way a
## player uses them (the RTS view, this node working the mouse and keys), and a look through a
## defender's eyes.
##
##   intro     she stands, breathing and looking round (her Idle clip)
##   walk      a lone lioness walks (her Walk clip: staged at her walking pace), then runs (her gallop)
##   line      eighteen are box-selected and sent up the field: they converge into firing lines as they
##             go, 8 abreast, a second line of 8 behind and the last 2 behind that, and stand facing the
##             way they went; T turns lines off (sent on, they go as a pack), T turns them back on
##   sneak     three, F: a bush over each on the attacker's side, their Sneak clip; they leave a Flame
##             Trooper within their reach alone; RMB on a trooper up the field: they stalk up to it and
##             pounce (their sneak ends as they spring), then maul it (the Strike clip)
##   defender  the defender's side: through a rifleman's eyes two sneaking lionesses stalk up, 70%
##             see-through, no shadows or health bars (a third, not sneaking, beside them as she always
##             looks); they pounce on the rifleman next to him, and show again
##   blast     two lionesses, G: the flamethrowers on their backs burn a cone in front of them; sent off
##             to the side they turn and go, the cone turning with them, and the troopers in it burn
##   break     a sneaking lioness lights hers (G): the sneak is over
##   trees     one burns the edge of the forest east of the lane: no tree catches fire
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/lioness_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie lioness.avi \
##       --fixed-fps 30 res://scenes/dev/lioness_showcase.tscn -- --video > lioness.log
##   python3 tools/video/cut_showcase.py lioness.avi lioness.log media/lioness_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times.
## --test prints what the lionesses do and checks it at the end (LIONESS SHOWCASE PASS / FAIL).
## --video cuts in the cameras (SHOTS): round the lioness standing, beside the walker and the runner,
## low in front of the lines as they come up, beside the stalkers and (in slow motion) the pounce, by
## the flamethrowers and at the forest's edge; the RTS view for the player's hands, the rifleman's own
## eyes for the defender's side. Waits are cut (printing the frames for tools/video/cut_showcase.py,
## drawing only the frames it keeps).
## The garrison's posts and the AA turrets hold fire; the troopers and riflemen in the field are prey
## and don't fight back.

## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [4.0, "walk"], [13.0, "line"], [37.0, "sneak"], [53.0, "defender"],
		[63.0, "blast"], [75.0, "break"], [80.0, "trees"], [89.0, "outro"], [91.0, "end"]]
## The lone walker: walking pace, when she breaks into her run, and her way across the lane.
const WALK_FROM := Vector3(-15.0, 0.0, 190.0)
const WALK_TO := Vector3(15.0, 0.0, 158.0)
const WALK_RUN_AT := 4.6
## The eighteen of the line: scattered round LINE_AT, sent to LINE_TO, then (lines off) on to PACK_TO.
const LINE_AT := Vector3(-4.0, 0.0, 186.0)
const LINE_SPREAD := Vector2(13.0, 8.0)
const LINE_COUNT := 18
const LINE_TO := Vector3(2.0, 0.0, 146.0)
const PACK_TO := Vector3(2.0, 0.0, 128.0)
## The three stalkers, the trooper standing in their reach as they go by, and the prey up the field.
const STALK_AT := [Vector3(-4.5, 0.0, 124.0), Vector3(0.0, 0.0, 125.0), Vector3(4.5, 0.0, 124.0)]
const STALK_TO := Vector3(0.0, 0.0, 115.5)
const NEAR_TROOPER := Vector3(3.9, 0.0, 119.5)
const PREY_AT := [Vector3(-3.0, 0.0, 101.0), Vector3(1.5, 0.0, 99.0), Vector3(6.0, 0.0, 102.0)]
## The defender's side: the rifleman whose eyes we see through, the one beside him they pounce on, where
## the two sneaking lionesses and the one that isn't come from.
const EYES_AT := Vector3(-9.0, 0.0, 112.0)
const BAIT_AT := Vector3(-6.0, 0.0, 113.0)
const GHOSTS_AT := [Vector3(-12.5, 0.0, 128.5), Vector3(-5.5, 0.0, 129.5)]
const GHOSTS_TO := Vector3(-8.0, 0.0, 121.5)
const PLAIN_AT := Vector3(-15.5, 0.0, 121.0)
## The fire blast: two lionesses, the troopers in front of them, and where they are sent (to the side).
const BLAST_AT := [Vector3(-6.0, 0.0, 120.0), Vector3(-1.5, 0.0, 120.0)]
const BURN_AT := [Vector3(-9.0, 0.0, 114.0), Vector3(-5.0, 0.0, 113.0), Vector3(-1.0, 0.0, 113.5), Vector3(3.0, 0.0, 114.5)]
const BLAST_TO := Vector3(12.0, 0.0, 116.0)
## The sneak broken by the fire blast, and the forest's edge (FORESTS[0], east of the lane).
const BREAK_AT := Vector3(-14.0, 0.0, 124.0)
## Where she stands to burn the forest's edge is picked on the run (_tree_spot), round here.
const TREES_NEAR := Vector3(21.0, 0.0, 140.0)
const FIELD_ZOOM := 34.0
const LINE_ZOOM := 38.0
const CLOSE_ZOOM := 24.0
const BREAK_ZOOM := 17.0
## Video: cameras other than the RTS view, as [phase, from, to (phase seconds), shot].
const SHOTS := [["intro", 0.0, 4.0, "orbit"], ["walk", 0.0, 9.0, "walker"], ["line", 9.0, 13.0, "front"],
		["sneak", 4.4, 7.4, "stalk"], ["sneak", 8.8, 12.6, "pounce"], ["blast", 3.0, 8.5, "flames"],
		["trees", 2.5, 8.5, "forest"], ["outro", 0.0, 2.0, "forest"]]
## Slow motion: [phase, from, to, time scale].
const SLOWMO := [["sneak", 9.6, 11.6, 0.4]]
## Played faster: [phase, from, to, every k-th frame kept].
const FAST := [["line", 13.5, 18.5, 2], ["line", 21.0, 23.5, 2]]
## Left out: [phase, from, to].
const CUTS := [["line", 23.5, 24.0], ["sneak", 14.5, 16.0], ["defender", 8.6, 10.0], ["blast", 9.5, 12.0],
		["break", 3.5, 5.0], ["trees", 8.5, 9.0]]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var defender: DefenderController
var cam: Camera3D
var t := -1.0
var phase := ""
var test := false
var video := false
var walker: AttackerUnit
var pride: Array = []
var stalkers: Array = []
var ghosts: Array = []
var plain: AttackerUnit
var blasters: Array = []
var breaker: AttackerUnit
var burner: AttackerUnit
var near_trooper: FlameTrooper
var prey: Array = []
var burn: Array = []
var eyes: DefenderSoldier
var bait: DefenderSoldier
var _phase_t := 0.0
var _steps := {}
var _checks: Array[String] = []
var _failed := false
var _clips := {}
var _pounces: Array = []  # [time, lioness, prey, prey hp]
var _blasts: Array = []  # [time, lioness, blast, its stats]
var _samples := {}
var _marks := {}
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
var _cursor_on = null
var _pan_from := Vector3.ZERO
var _pan_to := Vector3.ZERO
var _pan_t := Vector2.ZERO
var _caption: Label
var _keycap: Label
var _status: Label
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false
var _frame := -1
var _shot := ""
var _fast := 1
var _fast_from := 0
var _cutting := false
var _cut_from := 0
## The RTS view follows this (a point, or null).
var _follow = null


func _ready() -> void:
	seed(11)  # the same run every time
	test = "--test" in OS.get_cmdline_user_args()
	video = "--video" in OS.get_cmdline_user_args()
	if video:
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# Staged: the Gunner Squad sits this one out, the posts and the AA turrets hold fire.
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
	for s in level.stations + level.aa_turrets:
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		s.process_mode = Node.PROCESS_MODE_DISABLED
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
	rig.rotation.y = 0.0  # looking north, up the field at the south face
	rig.pitch = deg_to_rad(-50.0)
	rig._target_zoom = FIELD_ZOOM
	rig.zoom = FIELD_ZOOM
	rig.focus(WALK_FROM + Vector3(8, 0, -8))
	_pan_from = rig.position
	_pan_to = rig.position
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	_build_overlay()
	# The keys' help on the RTS panel would cover the field: off for the showcase.
	for l in controller.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("LMB select"):
			l.visible = false
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# The baked navmesh reaches the navigation map some frames after the bake (the map iterates on a
	# thread: how many frames depends on how busy the machine is). Wait for it, or the first orders
	# find no path.
	var map := get_world_3d().navigation_map
	while NavigationServer3D.map_get_closest_point(map, WALK_FROM).distance_to(WALK_FROM) > 2.0:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	walker = _spawn(WALK_FROM, PI * 0.75)
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))


func _spawn(pos: Vector3, yaw: float) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "lioness", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = yaw
	u.pounced.connect(func(p): _pounces.append([t, u, p, p.hp]))
	u.blasted.connect(func(b): _blasts.append([t, u, b, b.stats]))
	return u


## Units and troopers off the field once their part is played (fewer to draw).
func _retire(list: Array) -> void:
	for u in list:
		if not is_instance_valid(u):
			continue
		if u is AttackerUnit:
			commander.units.erase(u.unit_id)
		u.queue_free()


func _process(delta: float) -> void:
	_frame += 1
	if t < 0.0:
		return
	t += delta
	var k := 0
	while k < SCRIPT.size() - 1 and t >= SCRIPT[k + 1][0]:
		k += 1
	if SCRIPT[k][1] != phase:
		phase = SCRIPT[k][1]
		_phase_t = 0.0
		_steps.clear()
		if phase == "end":
			_finish()
			return
	_phase_t += delta
	for u in commander.units.values():
		var ap: AnimationPlayer = u.get("_anim")
		if ap:
			_clips[ap.current_animation] = true
	match phase:
		"intro":
			_say("Armored Lioness", "A melee hunter: claws and teeth, a sneak and a pounce, two flamethrowers on her back")
		"walk":
			_walk_step()
		"line":
			_line_step()
		"sneak":
			_sneak_step()
		"defender":
			_defender_step()
		"blast":
			_blast_step()
		"break":
			_break_step()
		"trees":
			_trees_step()
		"outro":
			_say("", "")
	_update_cursor()
	_update_pan()
	_update_status()
	if video:
		_direct()
	if not _snaps.is_empty():
		_snap()


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%04.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- phases

## A lone lioness walks across the lane (staged at her walking pace), then breaks into her run.
func _walk_step() -> void:
	if not is_instance_valid(walker):
		return
	if _once("go"):
		_say("The walk", "Paws planted, the fore paws folding back at the wrist, the head low and level")
		walker.stats = walker.stats.duplicate()
		walker.stats.speed = walker.stats.anim_ref_speed
		commander.submit({"type": "move", "units": [walker.unit_id], "pos": WALK_TO, "attack": false})
		_pan(WALK_FROM.lerp(WALK_TO, 0.35), 0.0, 8.0)
	var spd := Vector2(walker.velocity.x, walker.velocity.z).length()
	var ap: AnimationPlayer = walker.get("_anim")
	if _phase_t > 1.0 and _phase_t < WALK_RUN_AT:
		_sample("walk", ap.current_animation == "Walk" and absf(ap.speed_scale - spd / walker.stats.anim_ref_speed) < 0.15)
	if _phase_at(WALK_RUN_AT, "run"):
		_say("The run", "At full speed she gallops")
		walker.stats.speed = UnitTypes.DATA.lioness.speed
		walker.get("_agent").max_speed = walker.stats.speed
	if _phase_t > WALK_RUN_AT + 0.8 and _phase_t < 8.6:
		_sample("run", ap.current_animation == "Run" and spd > 5.0)
	if _phase_at(8.8, "check"):
		_check(_rate("walk") > 0.95, "walk: her Walk clip at her walking pace, matched to her speed (%d%% of %d frames)" % [_rate("walk") * 100.0, _samples.walk[1]])
		_check(_rate("run") > 0.95, "run: her Run clip (the gallop) at full speed (%d%% of %d frames)" % [_rate("run") * 100.0, _samples.run[1]])
		_check(_clips.has("Idle"), "idle: her Idle clip standing")


## Eighteen box-selected and sent up the field: firing lines as they go, 8 abreast, more behind; T turns
## lines off and they go as a pack; T turns them back on.
func _line_step() -> void:
	var rig := controller.camera_rig
	if _once("spawn"):
		_retire([walker])
		_say("Firing lines", "Lionesses moved together converge into lines as they go: 8 abreast, more lines behind")
		for i in LINE_COUNT:
			var p := LINE_AT + Vector3(randf_range(-1.0, 1.0) * LINE_SPREAD.x, 0.0, randf_range(-1.0, 1.0) * LINE_SPREAD.y)
			pride.append(_spawn(p, randf_range(-0.6, 0.6)))
		controller._set_selection([])
		_pan(LINE_AT + Vector3(0, 0, -6), 0.0, 1.0)
		rig._target_zoom = LINE_ZOOM
	if _phase_at(1.3, "select"):
		_move_cursor(_group_rect(pride).position, 1.3, 2.1)
	if _phase_at(2.2, "press"):
		_mouse(MOUSE_BUTTON_LEFT, true)
	if _phase_t > 2.2 and _phase_t < 3.0:
		_move_cursor(_group_rect(pride).end, 2.2, 3.0)
		_mouse_motion()
	if _phase_at(3.0, "release"):
		_mouse(MOUSE_BUTTON_LEFT, false)
		_check(controller.selected.size() == LINE_COUNT, "line: %d lionesses box-selected (%d)" % [LINE_COUNT, controller.selected.size()])
	if _phase_at(3.4, "aim"):
		_move_cursor(_screen(LINE_TO), 3.4, 4.2)
	if _phase_at(4.3, "order"):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_keycap.text = "RMB"
		_keycap.visible = true
		var lines := commander.lines.filter(func(l): return l.members.size() == LINE_COUNT)
		_check(lines.size() == 1, "line: the move order made one line of all %d" % LINE_COUNT)
		_marks.line = lines[0] if not lines.is_empty() else null
	if _phase_at(5.0, "key_off"):
		_keycap.visible = false
	var line: LionessLine = _marks.get("line")
	_follow = line.start + line.dir * (line.progress - 7.0) if line and _phase_t > 4.3 and _phase_t < 14.0 else null
	# The front shot (video): the selection rings off while it lasts.
	if video and _phase_at(9.0, "unselect"):
		controller._set_selection([])
	if video and _phase_at(13.0, "reselect"):
		controller._set_selection(pride)
	# Halfway up: they are coming into line on the way, not gathering first.
	if line and _phase_at(9.0, "midway"):
		var depth := _rank_depths(line)
		print("LIONESS line midway: progress %.1f/%.1f m, rank spreads %s m" % [line.progress, line.length, depth.map(func(d): return snappedf(d, 0.1))])
		_check(line.progress > 5.0 and line.progress < line.length - 2.0, "line: under way, %.0f of %.0f m" % [line.progress, line.length])
		_check(depth.max() < 2.5, "line: halfway there each rank already stands abreast (spread %.1f m along the way)" % depth.max())
	if line and _phase_at(13.4, "arrived"):
		var ranks := _ranks(line)
		print("LIONESS line ranks: %s" % [ranks.map(func(r): return r.size())])
		_check(ranks.map(func(r): return r.size()) == [8, 8, 2], "line: 8 abreast, a second line of 8, the last 2 behind (%s)" % [ranks.map(func(r): return r.size())])
		var spots := pride.map(func(u): return _flat(u.global_position, line.final_spot(u)))
		_check(spots.max() < 1.2, "line: every lioness on her spot (worst %.1f m off)" % spots.max())
		var facing := pride.filter(func(u): return (-u.global_basis.z).dot(line.dir) > 0.94).size()
		_check(facing == LINE_COUNT, "line: all facing the way the line went (%d/%d)" % [facing, LINE_COUNT])
		_check(pride.all(func(u): return u.order.type == "idle"), "line: and they have stopped")
	if _phase_at(14.5, "toggle"):
		_key(AttackerController.SCOUT_KEY)
		_keycap.text = "T"
		_keycap.visible = true
		_say("Firing lines off", "T (or the toggle on the panel) turns them off: sent on, they go as a pack")
		_check(not commander.line_formation, "line: T turns firing lines off")
	if _phase_at(15.3, "key_off2"):
		_check(controller.get("_line_button").visible and controller.get("_line_button").text.contains("OFF"), "line: the panel's toggle says OFF")
		_keycap.visible = false
		_move_cursor(_screen(PACK_TO), 15.3, 16.0)
	if _phase_at(16.2, "pack"):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_check(pride.all(func(u): return not u.order.has("line")), "line: lines off, the order makes no line")
		_pan(PACK_TO + Vector3(0, 0, 6), 16.2, 21.0)
	if _phase_at(22.0, "pack_check"):
		var behind: float = pride.map(func(u): return u.global_position.z).max() - pride.map(func(u): return u.global_position.z).min()
		print("LIONESS pack: %.1f m deep" % behind)
		_check(behind < 12.0, "line: as a pack they gather round the spot instead (%.1f m deep)" % behind)
	if _phase_at(23.0, "toggle_on"):
		_key(AttackerController.SCOUT_KEY)
		_keycap.text = "T"
		_keycap.visible = true
		_check(commander.line_formation, "line: T again turns them back on")


## Three of them, F: the bush over each, the Sneak clip; they leave a trooper in reach alone; RMB on a
## trooper up the field: they stalk up and pounce (the sneak ends), then maul it.
func _sneak_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_keycap.visible = false
		_retire(pride)
		pride.clear()
		for p in STALK_AT:
			stalkers.append(_spawn(p, 0.0))
		near_trooper = FlameTrooper.new()
		_trooper(near_trooper, NEAR_TROOPER, NEAR_TROOPER + Vector3(0, 1, 10))
		for p in PREY_AT:
			var tr := FlameTrooper.new()
			_trooper(tr, p, p + Vector3(0, 1, 10))
			prey.append(tr)
		controller._set_selection([])
		_say("Sneak", "F: 10 s of stalking (50 s cooldown). On your screen a bush marks her")
		_pan(STALK_AT[1] + Vector3(0, 0, -1), 0.0, 1.0)
		rig._target_zoom = CLOSE_ZOOM
	if _phase_at(1.0, "select"):
		_move_cursor(_group_rect(stalkers).position, 1.0, 1.6)
	if _phase_at(1.7, "press"):
		_mouse(MOUSE_BUTTON_LEFT, true)
	if _phase_t > 1.7 and _phase_t < 2.3:
		_move_cursor(_group_rect(stalkers).end, 1.7, 2.3)
		_mouse_motion()
	if _phase_at(2.3, "release"):
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _phase_at(2.8, "f"):
		_key(AttackerController.CLUSTER_KEY)
		_keycap.text = "F"
		_keycap.visible = true
		_check(stalkers.all(func(u): return u.is_sneaking()), "sneak: F, and the three sneak")
		_check(stalkers.all(func(u): return absf(u.sneak_cd - 50.0) < 0.1 and absf(u.sneak_left() - 10.0) < 0.1), "sneak: 10 s of it, 50 s before the next")
	if _phase_at(3.0, "bush"):
		_check(stalkers.all(func(u): return u.get("_bush").visible and not u.ghosted()), "sneak: on the attacker's side each looks as ever, a bush over her")
	if _phase_at(3.4, "walk_on"):
		_keycap.visible = false
		# Up past the trooper standing in their reach: sneaking, they pick no fight with it.
		_move_cursor(_screen(STALK_TO), 3.4, 4.1)
		_marks.near_hp = near_trooper.hp
	if _phase_at(4.2, "stalk"):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_pan(STALK_TO + Vector3(0, 0, -5), 4.2, 9.0)
	if _phase_t > 4.6 and _phase_t < 7.4:
		for u in stalkers:
			var spd := Vector2(u.velocity.x, u.velocity.z).length()
			if spd > 0.5:
				var ok: bool = u.get("_anim").current_animation == "Sneak" and spd <= u.stats.sneak_speed + 0.05
				_sample("stalk", ok)
				if not ok and test:
					print("LIONESS stalk sample off: %s clip %s speed %.2f" % [u.name, u.get("_anim").current_animation, spd])
	if _phase_at(7.4, "stalked"):
		_check(_rate("stalk") > 0.97, "sneak: they stalk, the Sneak clip, no faster than %.1f m/s (%d%%)" % [stalkers[1].stats.sneak_speed, _rate("stalk") * 100.0])
		_check(is_equal_approx(near_trooper.hp, _marks.near_hp), "sneak: they left the trooper in their reach alone (hp %d/%d)" % [near_trooper.hp, near_trooper.max_hp])
		_say("The pounce", "Sneaking, an attack order (RMB on a defender): she stalks up and springs on it")
		_move_cursor(_screen(Combat.aim_point(prey[1])), 7.4, 8.0)
	if _phase_t > 8.0 and _phase_t < 8.2:
		_cursor_on = Combat.aim_point(prey[1])
	if _phase_at(8.2, "attack"):
		_cursor_on = null
		_marks.prey_hp = prey[1].hp
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_keycap.text = "RMB"
		_keycap.visible = true
		_check(stalkers.all(func(u): return u.order.type == "attack" and u.order.target == prey[1]), "pounce: RMB on the trooper, an attack order for the three")
		print("LIONESS attack order at %.1f m, %.1f s of sneak left" % [_flat(stalkers[1].global_position, prey[1].global_position), stalkers[1].sneak_left()])
	if _phase_at(8.8, "key_off"):
		_keycap.visible = false
	if _phase_at(14.2, "check"):
		var springs := _pounces.filter(func(p): return p[2] == prey[1])
		print("LIONESS pounces: %s" % [springs.map(func(p): return "%s at %.1f s" % [p[1].name, p[0]])])
		_check(springs.size() == 3, "pounce: all three pounced (%d)" % springs.size())
		_check(springs.all(func(p): return not p[1].is_sneaking()), "pounce: springing ended their sneak (no bush, seen as ever)")
		_check(_clips.has("Pounce"), "pounce: the Pounce clip")
		_check(not Combat.is_valid_target(prey[1]) or prey[1].hp < _marks.prey_hp - 150.0, "pounce: the trooper took the pounces (%d -> %d)" % [_marks.prey_hp, prey[1].hp])
		_check(_clips.has("Strike"), "melee: then they maul it, the Strike clip")


## The defender's side: through a rifleman's eyes, two sneaking lionesses stalk up see-through (a third,
## not sneaking, as she always looks); they pounce on the rifleman next to him and show again.
func _defender_step() -> void:
	if _once("start"):
		_retire(stalkers + prey + [near_trooper])
		eyes = _guard(EYES_AT, GHOSTS_TO)
		bait = _guard(BAIT_AT, GHOSTS_TO)
		level.stations.append(eyes)
		GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
		for p in GHOSTS_AT:
			ghosts.append(_spawn(p, 0.0))
		plain = _spawn(PLAIN_AT, PI * 0.15)
		for u in ghosts:
			u.start_sneak()
		commander.submit({"type": "move", "units": _ids(ghosts), "pos": GHOSTS_TO, "attack": false})
		defender = DefenderController.new()
		defender.level = level
		add_child(defender)
		defender.select_station(level.stations.find(eyes), true)
		# He looks out up the field at them.
		var to := (GHOSTS_AT[0] + GHOSTS_AT[1]) * 0.5 - EYES_AT
		eyes.rotation.y = atan2(-to.x, -to.z) + 0.12
		eyes.get_camera().get_parent().rotation.x = deg_to_rad(-5.0)
		controller.visible = false
		_say("The defender's side", "Sneaking, she is 70% see-through to the defender: no shadow, no health bar. On the right, one not sneaking")
	if _phase_at(0.3, "look"):
		_check(ghosts.all(func(u): return u.ghosted() and not u.get("_bush").visible), "defender: sneaking lionesses are see-through on the defender's side, no bush")
		var mats := []
		for u in ghosts:
			for g in u.get("_ghosts"):
				mats.append(g[0].get_surface_override_material(g[1]))
		_check(not mats.is_empty() and mats.all(func(m): return m != null and is_equal_approx(m.albedo_color.a, 0.3) and m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA), "defender: drawn 30% opaque (70% see-through)")
		_check(ghosts.all(func(u): return u.get("_ghosts").all(func(g): return g[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)), "defender: no shadow")
		_check(not plain.ghosted() and plain.get("_ghosts")[0][0].get_surface_override_material(0) == null, "defender: the one not sneaking looks as ever")
	if _phase_at(1.0, "hurt"):
		ghosts[0].take_damage(20.0, GameConfig.TEAM_DEFENDER)
		_check(not ghosts[0].get("_hp_bar").visible, "defender: no health bar over a sneaking lioness, hurt or not")
	if _phase_at(5.0, "attack"):
		commander.submit({"type": "attack", "units": _ids(ghosts), "target": bait.get_path()})
		_say("The defender's side", "Ordered to attack, they pounce: springing, they show again")
		print("LIONESS ghosts attack at %.1f m, %.1f s of sneak left" % [_flat(ghosts[0].global_position, bait.global_position), ghosts[0].sneak_left()])
	if _phase_at(8.0, "check"):
		var springs := _pounces.filter(func(p): return p[2] == bait)
		_check(springs.size() == 2, "defender: they pounced on the rifleman beside him (%d)" % springs.size())
		_check(ghosts.all(func(u): return not u.ghosted() and u.get("_ghosts")[0][0].get_surface_override_material(0) == null), "defender: pouncing, they show again")
	if _phase_at(8.6, "back"):
		defender.current.unpossess()
		defender.queue_free()
		defender = null
		GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
		controller.visible = true
		controller.camera_rig.camera.current = true
		controller.restore_mouse()
		_retire(ghosts + [plain])
		for d in [eyes, bait]:
			level.stations.erase(d)
			d.queue_free()


## Two lionesses, G: a cone of flame in front of them; sent off to the side they turn and go, the cone
## turning with them; the troopers in it burn.
func _blast_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		for p in BLAST_AT:
			blasters.append(_spawn(p, 0.0))
		for p in BURN_AT:
			var tr := FlameTrooper.new()
			_trooper(tr, p, p + Vector3(0, 1, 10))
			burn.append(tr)
		controller._set_selection([])
		_pan(BLAST_AT[0].lerp(BLAST_AT[1], 0.5) + Vector3(0, 0, -1), 0.0, 1.0)
		rig._target_zoom = CLOSE_ZOOM
		_say("Fire blast", "G: the flamethrowers on her back burn a cone ahead for 3 s (45 s cooldown)")
	if _phase_at(0.9, "select"):
		_move_cursor(_group_rect(blasters).position, 0.9, 1.5)
	if _phase_at(1.6, "press"):
		_mouse(MOUSE_BUTTON_LEFT, true)
	if _phase_t > 1.6 and _phase_t < 2.1:
		_move_cursor(_group_rect(blasters).end, 1.6, 2.1)
		_mouse_motion()
	if _phase_at(2.1, "release"):
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _phase_at(2.6, "g"):
		_marks.burn_hp = burn.map(func(b): return b.hp)
		_key(AttackerController.BOMBARD_KEY)
		_keycap.text = "G"
		_keycap.visible = true
		_check(blasters.all(func(u): return u.is_blasting()), "blast: G, and both light their flamethrowers")
		_check(blasters.all(func(u): return absf(u.blast_cd - 45.0) < 0.1), "blast: 45 s before the next")
	if _phase_at(3.2, "aim"):
		_keycap.visible = false
		_say("Fire blast", "She can move while it burns: the cone always points where her face looks")
		_move_cursor(_screen(BLAST_TO), 3.2, 3.6)
	if _phase_at(3.7, "move"):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_marks.turn_from = (-blasters[0].global_basis.z)
	if _phase_t > 3.0 and _phase_t < 5.5:
		var u: AttackerUnit = blasters[0]
		if u.is_blasting():
			var b: LionessBlast = u.get("_blast")
			var face := -u.global_basis.z
			var d := b.direction()
			_sample("cone", Vector2(face.x, face.z).normalized().dot(Vector2(d.x, d.z).normalized()) > 0.999)
	if _phase_at(5.4, "moved"):
		var u: AttackerUnit = blasters[0]
		var turned: float = rad_to_deg(Vector2(_marks.turn_from.x, _marks.turn_from.z).angle_to(Vector2(-u.global_basis.z.x, -u.global_basis.z.z)))
		_check(absf(turned) > 40.0 and Vector2(u.velocity.x, u.velocity.z).length() > 1.0, "blast: she turned (%.0f deg) and moves while it burns" % turned)
		_check(_rate("cone") > 0.97, "blast: the cone points where she faces all the while (%d%%)" % [_rate("cone") * 100.0])
	if _phase_at(6.2, "out"):
		_check(blasters.all(func(u): return not u.is_blasting()), "blast: out after 3 s")
		var hurt := 0
		for i in burn.size():
			if not Combat.is_valid_target(burn[i]) or burn[i].hp < _marks.burn_hp[i] - 20.0:
				hurt += 1
		var dealt: float = _blasts.filter(func(b): return b[1] in blasters).map(func(b): return b[3].damage).reduce(func(a, x): return a + x, 0.0)
		print("LIONESS blast: %d/%d troopers burnt, %.0f damage" % [hurt, burn.size(), dealt])
		_check(hurt >= 3, "blast: the troopers in the cone burn (%d/%d)" % [hurt, burn.size()])


## A sneaking lioness lights her flamethrowers: the sneak is over.
func _break_step() -> void:
	if _once("start"):
		_retire(blasters + burn)
		breaker = _spawn(BREAK_AT, 0.0)
		controller._set_selection([breaker])
		_pan(BREAK_AT + Vector3(0, 0, -1), 0.0, 0.8)
		controller.camera_rig._target_zoom = BREAK_ZOOM
		_say("Fire blast while sneaking", "Lighting the flamethrowers gives her away: the sneak is over")
	if _phase_at(0.8, "f"):
		_key(AttackerController.CLUSTER_KEY)
		_keycap.text = "F"
		_keycap.visible = true
	if _phase_at(2.0, "g"):
		_check(breaker.is_sneaking() and breaker.get("_bush").visible, "break: sneaking (F), the bush over her")
		_key(AttackerController.BOMBARD_KEY)
		_keycap.text = "G"
		_check(breaker.is_blasting() and not breaker.is_sneaking(), "break: G lights the flamethrowers and ends the sneak")
		_check(breaker.sneak_cd > 45.0, "break: the sneak's cooldown runs on")
	if _phase_at(2.2, "bush"):
		_check(not breaker.get("_bush").visible, "break: the bush is gone")
	if _phase_at(2.6, "key_off"):
		_keycap.visible = false


## One burns the edge of the forest: no tree catches fire.
func _trees_step() -> void:
	if _once("start"):
		_retire([breaker])
		var spot := _tree_spot()
		burner = _spawn(spot, -PI * 0.5)  # facing east, at the trees
		_marks.tree_spot = spot
		controller._set_selection([burner])
		_pan(spot + Vector3(4, 0, 0), 0.0, 1.0)
		controller.camera_rig._target_zoom = CLOSE_ZOOM
		_say("No forest fires", "Her flames never set trees alight, unlike the Flame Squads'")
		_marks.trees = ForestTree.standing.filter(func(tr): return _flat(tr.global_position, spot) < 11.0)
	if _phase_at(1.2, "g"):
		_key(AttackerController.BOMBARD_KEY)
		_keycap.text = "G"
		_keycap.visible = true
	if _phase_at(1.8, "key_off"):
		_keycap.visible = false
	if burner.is_blasting() and _marks.has("trees"):
		var b: LionessBlast = burner.get("_blast")
		var lit := 0
		for tr in _marks.trees:
			if b.covers(tr.aim_point()):
				lit += 1
		_marks.covered = maxi(_marks.get("covered", 0), lit)
	if _phase_at(8.0, "check"):
		var trees: Array = _marks.trees
		_check(_marks.get("covered", 0) >= 2, "trees: the flames played on %d trees at the forest's edge" % _marks.get("covered", 0))
		_check(trees.all(func(tr): return tr.is_standing() and tr.heat == 0.0), "trees: none heated, none caught fire (%d standing)" % trees.filter(func(tr): return tr.is_standing()).size())


## Open ground at the forest's edge, facing east, with the most trees inside the cone ahead (near
## TREES_NEAR, clear of the trunks).
func _tree_spot() -> Vector3:
	var best := TREES_NEAR
	var best_n := -1
	var reach: float = UnitTypes.DATA.lioness.blast_range
	var half: float = UnitTypes.DATA.lioness.blast_angle
	for dz in range(-12, 13):
		for dx in range(-4, 7):
			var p := TREES_NEAR + Vector3(dx, 0.0, dz)
			var nozzle := p + Vector3(1.2, 0.0, 0.0)
			var n := 0
			var clear := true
			for tr in ForestTree.standing:
				if _flat(tr.global_position, p) < 2.3:
					clear = false
					break
				var to := Vector2(tr.global_position.x - nozzle.x, tr.global_position.z - nozzle.z)
				if to.length() < reach - 0.5 and absf(Vector2(1, 0).angle_to(to)) < half * 0.9:
					n += 1
			if clear and n > best_n:
				best_n = n
				best = p
	return best


# ---------------------------------------------------------------- the field

func _trooper(tr: SquadTrooper, at: Vector3, face: Vector3) -> void:
	add_child(tr)
	tr.global_position = at + Vector3.UP * 0.1
	tr.aim_point = face
	tr.following = true
	tr.goal = at


## A rifleman standing in the field, looking toward `look` (he doesn't fight).
func _guard(p: Vector3, look: Vector3) -> DefenderSoldier:
	var s := DefenderSoldier.new()
	s.model_path = LevelBuilder.DEFENDER_MODELS[1]
	s.station_name = "Field rifleman"
	var to := look - p
	s.transform = Transform3D(Basis.looking_at(Vector3(to.x, 0.0, to.z)), p + Vector3.UP * 0.1)
	add_child(s)
	s.became_unavailable.connect(func(_st): s.set("_respawn_cd", 1e9))
	s.set_process(false)
	s.set_physics_process(false)
	return s


# ---------------------------------------------------------------- checks

func _sample(what: String, ok: bool) -> void:
	var s: Array = _samples.get(what, [0, 0])
	_samples[what] = [s[0] + (1 if ok else 0), s[1] + 1]


func _rate(what: String) -> float:
	var s: Array = _samples.get(what, [0, 0])
	return float(s[0]) / maxf(s[1], 1.0)


## The lionesses of a line, rank by rank (front first), by their spots.
func _ranks(line: LionessLine) -> Array:
	var by := {}
	for u in pride:
		var r := int(round(line.slots[u].y / LionessLine.RANK_GAP))
		if not by.has(r):
			by[r] = []
		by[r].append(u)
	var out := []
	for r in range(by.size()):
		out.append(by.get(r, []))
	return out


## How far apart along the way each rank's lionesses are now (m).
func _rank_depths(line: LionessLine) -> Array:
	return _ranks(line).map(func(r):
		var along: Array = r.map(func(u): return line.dir.dot(u.global_position))
		return along.max() - along.min())


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	for c in _checks:
		print("LIONESS CHECK ", c)
	print("LIONESS SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame])
		if _cutting:
			print("CUT frames %d-%d" % [_cut_from, _frame])
		print("VIDEO END frame %d" % _frame)
	get_tree().quit(1 if _failed and test else 0)


# ---------------------------------------------------------------- video

## Video: the camera for this moment (SHOTS, else the RTS view; the rifleman's eyes on the defender's
## side), slow motion, and the frames to speed up or leave out (only the frames the video keeps are drawn).
func _direct() -> void:
	var shot := "eyes" if phase == "defender" and defender != null else "rts"
	for sh in SHOTS:
		if _within(sh):
			shot = sh[3]
	if shot != _shot:
		_shot = shot
		for b in level.bases:
			b.get("_label").visible = shot == "rts"
		_cursor.visible = shot == "rts"
		_keycap.visible = _keycap.visible and shot == "rts"
		controller.visible = shot == "rts"
		if shot == "rts":
			controller.camera_rig.camera.current = true
		elif shot != "eyes":
			cam.current = true
	if shot not in ["rts", "eyes"]:
		_place_cam(shot)
	var scale := 1.0
	for sl in SLOWMO:
		if _within(sl):
			scale = sl[3]
	Engine.time_scale = scale
	var fast := 1
	for f in FAST:
		if _within(f):
			fast = f[3]
	if fast != _fast:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame - 1])
		_fast = fast
		_fast_from = _frame
	var cutting := CUTS.any(func(c): return _within(c))
	if cutting != _cutting:
		if _cutting:
			print("CUT frames %d-%d" % [_cut_from, _frame - 1])
		_cutting = cutting
		_cut_from = _frame
	RenderingServer.render_loop_enabled = not cutting and (_frame - _fast_from) % _fast == 0


func _within(r: Array) -> bool:
	return r[0] == phase and _phase_t >= r[1] and _phase_t < r[2]


## Where the video's camera is for `shot`, following the action.
func _place_cam(shot: String) -> void:
	var at := Vector3.ZERO
	var look := Vector3.ZERO
	match shot:
		"orbit":
			var p := walker.global_position
			var a := 0.9 + _phase_t * 0.22
			at = p + Vector3(sin(a) * 4.0, 1.25, cos(a) * 4.0)
			look = p + Vector3(0.0, 0.75, 0.0)
		"walker":
			# Beside her, a little ahead.
			var p := walker.global_position
			var fwd := -walker.global_basis.z
			var right := fwd.cross(Vector3.UP).normalized()
			at = p + right * 5.0 + fwd * 1.2 + Vector3.UP * 1.1
			look = p + fwd * 0.5 + Vector3.UP * 0.7
		"front":
			# Low, ahead of the lines and off to one side, as they come up.
			var line: LionessLine = _marks.get("line")
			var front := line.start + line.dir * line.progress
			at = front + line.dir * 12.0 - line.right * 9.0 + Vector3.UP * 1.6
			look = front - line.dir * 2.5 + Vector3.UP * 0.6
		"stalk":
			var u: AttackerUnit = stalkers[0]
			var fwd := -u.global_basis.z
			var right := fwd.cross(Vector3.UP).normalized()
			at = u.global_position - right * 5.0 + fwd * 4.0 + Vector3.UP * 1.0
			look = u.global_position + fwd * 1.0 + Vector3.UP * 0.5
		"pounce":
			# Side-on to the leap, the prey on the left, the stalkers springing from the right.
			var p: Vector3 = PREY_AT[1]
			at = p + Vector3(-14.5, 2.0, 7.0)
			look = p + Vector3(0.0, 0.9, 6.5)
		"flames":
			var c: Vector3 = _centre(blasters.filter(func(u): return is_instance_valid(u)))
			at = c + Vector3(-9.0, 3.0, 6.0)
			look = c + Vector3(0.0, 0.8, -3.0)
		"forest":
			# From the open lane, the lioness in front, the trees beyond her.
			var p: Vector3 = _marks.get("tree_spot", TREES_NEAR)
			at = p + Vector3(-8.0, 2.2, 5.0)
			look = p + Vector3(3.5, 1.3, 0.0)
	cam.global_position = at
	cam.look_at(look)


## The lionesses' state on the panel's right while their skills are shown.
func _update_status() -> void:
	var shown := []
	match phase:
		"sneak":
			shown = stalkers
		"blast":
			shown = blasters
		"break":
			shown = [breaker]
		"trees":
			shown = [burner]
	shown = shown.filter(func(u): return is_instance_valid(u) and u.is_alive())
	_status.visible = not shown.is_empty() or phase == "line"
	if not _status.visible:
		return
	var lines := []
	if phase == "line":
		lines.append("Firing lines  %s" % ("ON" if commander.line_formation else "OFF"))
	for u in shown:
		var state: String = "sneaking %.0f s" % u.sneak_left() if u.is_sneaking() else ("pouncing" if u.is_pouncing() else ("flamethrowers burning" if u.is_blasting() else ""))
		lines.append("%s  %d / %d  %s" % [u.stats.name, int(u.hp), int(u.stats.hp), state])
	_status.text = "\n".join(lines)


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _ids(list: Array) -> Array:
	return list.map(func(u): return u.unit_id)


func _centre(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in list:
		c += u.global_position
	return c / maxf(list.size(), 1)


func _screen(p: Vector3) -> Vector2:
	return controller.camera_rig.camera.unproject_position(p)


func _group_rect(units: Array) -> Rect2:
	var r := Rect2(_screen(units[0].global_position + Vector3.UP), Vector2.ZERO)
	for u in units:
		r = r.expand(_screen(u.global_position + Vector3.UP))
	return r.grow(40.0)


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


## Pans the view (as with WASD) to `to` between `start` and `end` (phase seconds).
func _pan(to: Vector3, start: float, end: float) -> void:
	_pan_from = controller.camera_rig.position
	_pan_to = to
	_pan_t = Vector2(start, end)


func _update_pan() -> void:
	var rig := controller.camera_rig
	var w := smoothstep(_pan_t.x, _pan_t.y, _phase_t) if _pan_t.y > _pan_t.x else 1.0
	var p := _pan_from.lerp(_pan_to, w)
	if _follow != null:
		p = rig.position.lerp(_follow, 0.06)
		_pan_from = p
		_pan_to = p
	rig.position.x = p.x
	rig.position.z = p.z


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _mouse_motion() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _cursor.position
	controller._unhandled_input(ev)


# ---------------------------------------------------------------- overlay

func _say(title: String, sub: String) -> void:
	_caption.text = title if sub == "" else "%s\n%s" % [title, sub]
	_caption.visible = title != ""


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
	_status = UIKit.label("", 15, Color(1.0, 0.95, 0.75))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 120)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
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


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
