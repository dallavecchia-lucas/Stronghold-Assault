extends Node3D
## Staged run of the Serpent Sniper on the real map, in the south field: its skills used the way a player uses
## them (the RTS view, this node working the mouse and keys), and a look through a defender's eyes.
##
##   intro     it lies still, breathing (its Idle clip)
##   slither   it slithers across the lane (its Slither clip: staged at its clip's pace)
##   fire      RMB on a Flame Trooper: slow, heavy rounds from the rifle on its back (one every 4 s, 95 each)
##   nest      F, LMB on a lone tree: it goes up to it and climbs it, winding up the trunk (8 s), and lies out
##             on top of the crown, rifle out over the field; the tree-and-rifle icon; up there it sees and shoots
##             further: a trooper beyond its reach on the ground, out of its sight in the fog, it now sees and
##             shoots; RMB on the ground: it climbs down (8 s), then goes
##   trap      G, LMB on a bush: it pushes its rifle in under the bush and coils round it (8 s); the grass-
##             and-snake icon; a Flame Trooper walking past comes within its reach: it strikes, winds round it and
##             squeezes, 15 s, the trooper's health running down steadily to nothing; an order meanwhile changes
##             nothing; then it goes back round its bush; RMB on the ground: it uncoils (8 s), picks its rifle up
##             and goes
##   defender  the defender's side: through a rifleman's eyes a snake coiled round a bush is 70% see-through, no
##             shadow, no health bar, no icon
##   rescue    a trooper walks into another snake's trap; two riflemen shoot the snake dead before the 15 s are
##             up, and the trooper goes free with the health it has left, and walks on
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/serpent_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie serpent.avi \
##       --fixed-fps 30 res://scenes/dev/serpent_showcase.tscn -- --video > serpent.log
##   python3 tools/video/cut_showcase.py serpent.avi serpent.log media/serpent_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times; --from=phase starts there;
## --bare-tree hides the nest tree's crown and stands a plain trunk in for it (to check the climb).
## --test prints what the snakes do and checks it at the end (SERPENT SHOWCASE PASS / FAIL).
## --video cuts in the cameras (SHOTS): round the snake lying still, beside it slithering, behind it firing, the
## whole tree as it climbs, over its head on top of the crown, low by the bush as it coils, side-on to the strike
## and close by the squeeze; the RTS view for the player's hands, the rifleman's own eyes for the defender's
## side. Waits are cut (printing the frames for tools/video/cut_showcase.py, drawing only the frames it keeps).
## The garrison's posts and the AA turrets hold fire; the troopers in the field don't fight back (the
## riflemen of the rescue do).

## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [4.0, "slither"], [10.0, "fire"], [22.0, "nest"], [62.0, "trap"], [108.0, "defender"],
		[118.0, "rescue"], [136.0, "outro"], [138.0, "end"]]
## The lone snake: lying still, slithering across the lane, firing at a trooper.
const INTRO_AT := Vector3(-12.0, 0.0, 172.0)
const SLITHER_TO := Vector3(10.0, 0.0, 166.0)
const FIRE_AT := Vector3(10.0, 0.0, 166.0)
const TARGET_AT := Vector3(-14.0, 0.0, 148.0)
## The nest: a lone tree near here, the snake starting this far from it on the lane's side, the trooper it
## can't reach from the ground (out on the lane, this far from the tree), and where it is sent after.
const NEST_NEAR := Vector3(26.0, 0.0, 128.0)
const NEST_START := 10.0
const NEST_SHOT := 62.0
## The trap: a bush near here, the snake starting this far from it, and when a trooper sets off past it (phase
## seconds, once it is coiled: it walks into the strike as the video slows down for it).
const TRAP_NEAR := Vector3(-16.0, 0.0, 118.0)
const TRAP_START := 9.0
const PREY_AT := 14.3
## The defender's side, and the rescue: bushes near these.
const EYES_NEAR := Vector3(14.0, 0.0, 104.0)
const RESCUE_NEAR := Vector3(-24.0, 0.0, 146.0)
const FIELD_ZOOM := 30.0
const CLOSE_ZOOM := 18.0
const RANGE_ZOOM := 70.0
## Video: cameras other than the RTS view, as [phase, from, to (phase seconds), shot].
const SHOTS := [["intro", 0.0, 4.0, "orbit"], ["slither", 0.0, 6.0, "beside"], ["fire", 3.0, 12.0, "behind"],
		["nest", 4.6, 16.5, "climb"], ["nest", 16.5, 22.0, "perch"], ["nest", 29.0, 38.0, "climb"],
		["trap", 5.0, 15.0, "coil"], ["trap", 16.0, 21.0, "strike"], ["trap", 21.0, 32.6, "squeeze"],
		["trap", 37.2, 45.0, "coil"], ["rescue", 2.0, 16.0, "rescue"]]
## Slow motion: [phase, from, to, time scale].
const SLOWMO := [["trap", 16.4, 18.6, 0.35]]
## Played faster: [phase, from, to, every k-th frame kept].
const FAST := [["nest", 8.0, 15.5, 2], ["nest", 30.0, 37.5, 2], ["trap", 6.0, 12.5, 2], ["trap", 22.0, 30.5, 3],
		["trap", 38.0, 44.0, 2]]
## Left out: [phase, from, to].
const CUTS := [["fire", 0.0, 2.0], ["nest", 38.0, 40.0], ["trap", 45.0, 46.0], ["rescue", 16.0, 18.0]]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var defender: DefenderController
var vision: AttackerVision
var cam: Camera3D
var t := -1.0
var phase := ""
var test := false
var video := false
var snake: AttackerUnit
var nester: AttackerUnit
var trapper: AttackerUnit
var ghost: AttackerUnit
var rescuer: AttackerUnit
var tree: ForestTree
var bush: Bush
var target: FlameTrooper
var far: FlameTrooper
var prey: FlameTrooper
var eyes: DefenderSoldier
var shooters: Array = []
var _phase_t := 0.0
var _steps := {}
var _checks: Array[String] = []
var _failed := false
var _clips := {}
var _samples := {}
var _marks := {}
var _shots: Array = []  # [time, shooter, target, its hp before]
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
var _from := 0.0
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
	seed(7)  # the same run every time
	test = "--test" in OS.get_cmdline_user_args()
	video = "--video" in OS.get_cmdline_user_args()
	if video:
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
		elif arg.begins_with("--from="):
			for sc in SCRIPT:
				if sc[1] == arg.get_slice("=", 1):
					_from = sc[0]
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
	# The fog of war: what the snakes see (up a tree, further).
	vision = AttackerVision.new()
	vision.commander = commander
	vision.hide_enemies = true
	add_child(vision)
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	var rig := controller.camera_rig
	rig.edge_scroll = false
	rig.rotation.y = 0.0  # looking north, up the field at the south face
	rig.pitch = deg_to_rad(-52.0)
	rig._target_zoom = FIELD_ZOOM
	rig.zoom = FIELD_ZOOM
	rig.focus(INTRO_AT + Vector3(4, 0, -4))
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
	# The baked navmesh reaches the navigation map some frames after the bake: wait for it, or the first
	# orders find no path.
	var map := get_world_3d().navigation_map
	while NavigationServer3D.map_get_closest_point(map, INTRO_AT).distance_to(INTRO_AT) > 2.0:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	if _from == 0.0:
		snake = _spawn(INTRO_AT, -PI * 0.42)
	t = _from
	if video:
		print("VIDEO START frame %d" % (_frame + 1))


func _spawn(pos: Vector3, yaw: float) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "serpent", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = yaw
	u.nested.connect(func(tr): _marks["nested_%d" % u.unit_id] = t)
	u.coiled.connect(func(b): _marks["coiled_%d" % u.unit_id] = t)
	u.struck.connect(func(p): _marks["struck_%d" % u.unit_id] = [t, p, p.hp])
	u.crushed.connect(func(p): _marks["crushed_%d" % u.unit_id] = [t, p])
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
			_say("Serpent Sniper", "An anaconda in a helmet, with an anti-materiel rifle strapped along its back")
		"slither":
			_slither_step()
		"fire":
			_fire_step()
		"nest":
			_nest_step()
		"trap":
			_trap_step()
		"defender":
			_defender_step()
		"rescue":
			_rescue_step()
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
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- phases

## It slithers across the lane (staged at its clip's pace).
func _slither_step() -> void:
	if _once("go"):
		_say("Slither", "Lateral undulation: a wave runs down its body, the front with the rifle held straight")
		snake.stats = snake.stats.duplicate()
		snake.stats.speed = snake.stats.anim_ref_speed
		commander.submit({"type": "move", "units": [snake.unit_id], "pos": SLITHER_TO, "attack": false})
		_pan(INTRO_AT.lerp(SLITHER_TO, 0.5), 0.0, 5.0)
	var spd := Vector2(snake.velocity.x, snake.velocity.z).length()
	var ap: AnimationPlayer = snake.get("_anim")
	if _phase_t > 1.5 and _phase_t < 5.5 and spd > 0.5:
		_sample("slither", ap.current_animation == "Slither" and absf(ap.speed_scale - clampf(spd / snake.stats.anim_ref_speed, 0.6, 2.0)) < 0.15)
	if _phase_at(5.8, "check"):
		_check(_rate("slither") > 0.95, "slither: its Slither clip, matched to its speed (%d%% of %d frames)" % [_rate("slither") * 100.0, _samples.get("slither", [0, 0])[1]])
		_check(_clips.has("Idle"), "idle: its Idle clip lying still")


## RMB on a trooper: slow, heavy rounds.
func _fire_step() -> void:
	if _once("start"):
		snake.stats.speed = UnitTypes.DATA.serpent.speed
		snake.global_position = FIRE_AT + Vector3.UP * 0.1
		snake.rotation.y = atan2(-(TARGET_AT - FIRE_AT).x, -(TARGET_AT - FIRE_AT).z) + 0.5
		target = FlameTrooper.new()
		_trooper(target, TARGET_AT, FIRE_AT)
		controller._set_selection([snake])
		_pan(FIRE_AT.lerp(TARGET_AT, 0.5), 0.0, 1.0)
		_say("The rifle", "Slow to fire, hard hitting: %d a round, one every %d s, out to %d m" % [UnitTypes.DATA.serpent.damage, UnitTypes.DATA.serpent.fire_interval, UnitTypes.DATA.serpent.range])
		_marks.target_hp = target.hp
	if _phase_at(1.0, "aim"):
		_move_cursor(_screen(Combat.aim_point(target)), 1.0, 1.8)
	if _phase_t > 1.8 and _phase_t < 2.0:
		_cursor_on = Combat.aim_point(target)
	if _phase_at(2.0, "attack"):
		_cursor_on = null
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_keycap.text = "RMB"
		_keycap.visible = true
		_check(snake.order.type == "attack" and snake.order.target == target, "fire: RMB on the trooper, an attack order")
	if _phase_at(2.6, "key_off"):
		_keycap.visible = false
	_watch_hits(snake, target)
	if _phase_at(11.8, "check"):
		var hits := _shots.filter(func(s): return s[1] == snake and s[2] == target)
		print("SERPENT rounds at the trooper: %s" % [hits.map(func(s): return "%.1f s: %d" % [s[0], s[3] - s[4]])])
		_check(hits.size() >= 2 and hits.size() <= 3, "fire: slow, 2-3 rounds in %.0f s (%d)" % [9.8, hits.size()])
		var gaps := []
		for i in range(1, hits.size()):
			gaps.append(hits[i][0] - hits[i - 1][0])
		_check(not gaps.is_empty() and gaps.min() >= UnitTypes.DATA.serpent.fire_interval * 0.88, "fire: a round every %.0f s or so (%s)" % [UnitTypes.DATA.serpent.fire_interval, gaps.map(func(g): return snappedf(g, 0.1))])
		_check(hits.all(func(s): return absf(s[3] - s[4] - UnitTypes.DATA.serpent.damage) < 1.0), "fire: %d a hit" % UnitTypes.DATA.serpent.damage)


## F, LMB on a tree: it climbs it, perches, sees and shoots further; RMB on the ground: it climbs down and goes.
func _nest_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_retire([snake, target])
		tree = _pick_tree(NEST_NEAR)
		var foot := tree.trunk_centre()
		if "--bare-tree" in OS.get_cmdline_user_args():
			# Checking the climb: the crown hidden, a plain trunk where the snake winds round it.
			tree.get("_model").visible = false
			for y in range(0, int(tree.height * 2.0)):
				var r := tree.trunk_radius(y * 0.5 + 0.25)
				add_child(Mats.cylinder_mesh(r, 0.5, foot + Vector3.UP * (y * 0.5 + 0.25), Mats.flat(Color(0.75, 0.72, 0.65)), 12))
		var out := Vector3(-signf(foot.x) if absf(foot.x) > 1.0 else -1.0, 0.0, 0.25).normalized()
		_marks.nest_start = foot + out * NEST_START
		nester = _spawn(_marks.nest_start, atan2(out.x, out.z))
		# A trooper out on the lane beyond its reach and sight on the ground, within them up the tree.
		var lane_z: float = foot.z + sqrt(maxf(NEST_SHOT * NEST_SHOT - foot.x * foot.x, 1.0))
		far = FlameTrooper.new()
		_trooper(far, Vector3(0.0, 0.0, lane_z), foot)
		controller._set_selection([])
		_pan(foot + out * 4.0, 0.0, 1.0)
		rig._target_zoom = FIELD_ZOOM
		_say("Sniper nest", "F, then click a tree: it climbs it (%d s) and lies out on top of the crown, rifle over the field" % UnitTypes.DATA.serpent.nest_time)
		print("SERPENT nest tree at %s, %.1f m tall, trunk %.2f m, perch %.1f m; trooper on the lane %.0f m off" % [foot, tree.height, tree.trunk_r, tree.perch, _flat(foot, far.global_position)])
	if _phase_at(0.5, "fog"):
		vision.refresh()
		_check(not AttackerVision.sees_node(far) and _flat(nester.global_position, far.global_position) > nester.sight(), "nest: on the ground the trooper %.0f m off is in the fog (sight %.0f m)" % [_flat(nester.global_position, far.global_position), nester.sight()])
	if _phase_at(1.0, "select"):
		_move_cursor(_screen(nester.global_position + Vector3.UP * 0.5), 1.0, 1.6)
	if _phase_at(1.7, "click"):
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
		_check(controller.selected == [nester], "nest: the snake clicked and selected")
	if _phase_at(2.2, "f"):
		_key(AttackerController.CLUSTER_KEY)
		_keycap.text = "F"
		_keycap.visible = true
		_check(controller.get("_aiming") == "nest", "nest: F aims the sniper nest")
		_move_cursor(_screen(tree.trunk_centre() + Vector3.UP * tree.height * 0.62), 2.3, 3.1)
	if _phase_at(3.3, "lmb"):
		_check(controller.get("_tree_under").call(_cursor.position) == tree, "nest: the tree under the cursor is picked out")
		_mouse(MOUSE_BUTTON_LEFT, true)
		_keycap.text = "LMB"
		_check(nester.order.type == "nest" and nester.order.tree == tree and tree.nest_by == nester, "nest: LMB on the tree, it is sent up it")
		_check(controller.get("_aiming") == "", "nest: and the aim is done")
	if _phase_at(3.9, "key_off"):
		_keycap.visible = false
	if nester.in_tree() and not _marks.has("climb_from"):
		_marks.climb_from = t
		print("SERPENT climbing from %.1f s" % t)
	if nester.in_tree() and nester.skill_dir() > 0 and not nester.is_perched():
		_sample("icon_off", not nester.get("_nest_icon").visible)
	if _marks.has("nested_%d" % nester.unit_id) and not _marks.has("perched"):
		_marks.perched = true
		var took: float = _marks["nested_%d" % nester.unit_id] - _marks.climb_from
		print("SERPENT perched after %.2f s, sight %.0f m, reach %.0f m, at %s" % [took, nester.sight(), nester.reach(), nester.global_position])
		_check(absf(took - UnitTypes.DATA.serpent.nest_time) < 0.15, "nest: the climb took %.1f s (%d)" % [took, UnitTypes.DATA.serpent.nest_time])
		_check(_rate("icon_off") == 1.0, "nest: no icon on the way up")
		_say("On top of the tree", "It sees %d%% further (%d m) and its rifle reaches %d%% further (%d m)" % [roundi((UnitTypes.DATA.serpent.nest_sight - 1.0) * 100.0), nester.sight(), roundi((UnitTypes.DATA.serpent.nest_range - 1.0) * 100.0), nester.reach()])
	if _marks.has("perched") and _once("perched_checks"):
		_check(is_equal_approx(nester.sight(), UnitTypes.DATA.serpent.sight * UnitTypes.DATA.serpent.nest_sight), "nest: perched, it sees %.0f m" % nester.sight())
		_check(is_equal_approx(nester.reach(), UnitTypes.DATA.serpent.range * UnitTypes.DATA.serpent.nest_range), "nest: perched, its rifle reaches %.0f m" % nester.reach())
		_check(nester.global_position.y > tree.perch * 0.8, "nest: on top of the crown (%.1f m up)" % nester.global_position.y)
		_marks.far_hp = far.hp
		rig._target_zoom = RANGE_ZOOM
		_pan(tree.trunk_centre().lerp(far.global_position, 0.45), _phase_t, _phase_t + 2.0)
	if _marks.has("perched") and nester.is_perched():
		_sample("icon_on", nester.get("_nest_icon").visible)
	_watch_hits(nester, far)
	if _phase_at(27.5, "far"):
		vision.refresh()
		var hits := _shots.filter(func(s): return s[1] == nester and s[2] == far)
		print("SERPENT from the tree: %d rounds at the trooper %.0f m off" % [hits.size(), _flat(tree.trunk_centre(), far.global_position)])
		_check(_marks.has("perched"), "nest: perched")
		_check(_rate("icon_on") > 0.98, "nest: perched, the tree-and-rifle icon over it (attacker's side)")
		_check(AttackerVision.sees_node(far), "nest: up the tree it sees the trooper in the fog")
		_check(not hits.is_empty(), "nest: and shoots it from up there (%d rounds)" % hits.size())
		_say("Climbing down", "Any order to go anywhere: it climbs down first (%d s), then goes" % UnitTypes.DATA.serpent.nest_time)
		rig._target_zoom = FIELD_ZOOM
		_pan(tree.trunk_centre() + Vector3(0, 0, 4), _phase_t, _phase_t + 1.5)
		_marks.go_to = tree.trunk_centre() + Vector3(-8.0 * signf(tree.trunk_centre().x), 0.0, 10.0)
	if _phase_at(29.0, "aim_down"):
		_move_cursor(_screen(_marks.go_to), 29.0, 29.6)
	if _phase_at(29.7, "go"):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_keycap.text = "RMB"
		_keycap.visible = true
		_marks.down_from = t
		_check(nester.in_tree() and nester.skill_dir() < 0, "nest: RMB on the ground, it starts climbing down")
		_check(nester.order.type == "nest" and nester.get("_after") != null and nester.get("_after").type == "attack_move", "nest: the move order waits till it is down")
	if _phase_at(30.3, "key_off2"):
		_keycap.visible = false
	if _marks.has("down_from") and not nester.in_tree() and not _marks.has("down_at"):
		_marks.down_at = t
		var took: float = t - _marks.down_from
		print("SERPENT down after %.2f s" % took)
		_check(absf(took - UnitTypes.DATA.serpent.nest_time) < 0.15, "nest: climbing down took %.1f s (%d)" % [took, UnitTypes.DATA.serpent.nest_time])
		_check(not nester.get("_nest_icon").visible and is_equal_approx(nester.sight(), UnitTypes.DATA.serpent.sight), "nest: down, no icon, and it sees as far as ever")
		_check(tree.nest_by == null, "nest: the tree is free again")
	if _phase_at(39.5, "went"):
		_check(_marks.has("down_at") and nester.order.type in ["attack_move", "idle"] and _flat(nester.global_position, _marks.go_to) < _flat(tree.trunk_centre(), _marks.go_to) - 3.0, "nest: then it goes where it was sent (%.1f m to go)" % _flat(nester.global_position, _marks.go_to))


## G, LMB on a bush: it sets its rifle down, coils round it; a trooper comes past: it strikes and squeezes it
## to death in 15 s, nothing calling that off, then goes back round its bush; RMB: it uncoils and goes.
func _trap_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_retire([nester, far])
		bush = _pick_bush(TRAP_NEAR, [])
		var at := bush.global_position
		var out := Vector3(1.0, 0.0, 0.35).normalized()
		trapper = _spawn(at + out * TRAP_START, atan2(out.x, out.z))
		controller._set_selection([])
		_pan(at + out * 3.0, 0.0, 1.0)
		rig._target_zoom = CLOSE_ZOOM
		_say("Bush trap", "G, then click a bush: it hides its rifle in the bush and coils round it (%d s)" % UnitTypes.DATA.serpent.trap_time)
		print("SERPENT trap bush at %s, %.2f m across, %.2f m tall" % [at, bush.radius * 2.0, bush.height])
	if _phase_at(1.0, "select"):
		_move_cursor(_screen(trapper.global_position + Vector3.UP * 0.5), 1.0, 1.6)
	if _phase_at(1.7, "click"):
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _phase_at(2.2, "g"):
		_key(AttackerController.BOMBARD_KEY)
		_keycap.text = "G"
		_keycap.visible = true
		_check(controller.get("_aiming") == "trap", "trap: G aims the bush trap")
		_move_cursor(_screen(bush.global_position), 2.3, 3.0)
	if _phase_at(3.2, "lmb"):
		_mouse(MOUSE_BUTTON_LEFT, true)
		_keycap.text = "LMB"
		_check(trapper.order.type == "trap" and trapper.order.bush == bush and bush.coiled_by == trapper, "trap: LMB on the bush, it is sent round it")
	if _phase_at(3.8, "key_off"):
		_keycap.visible = false
	if trapper.in_bush() and not _marks.has("coil_from"):
		_marks.coil_from = t
	if trapper.in_bush() and trapper.skill_dir() > 0:
		_sample("trap_icon_off", not trapper.get("_bush").visible)
		if trapper.skill_progress() > 0.3:
			_sample("rifle_down", (trapper.serpent_rig() as SerpentRig).rifle_w >= 1.0)
	var coiled_at = _marks.get("coiled_%d" % trapper.unit_id)
	if coiled_at != null and not _marks.has("coiled"):
		_marks.coiled = true
		var took: float = coiled_at - _marks.coil_from
		print("SERPENT coiled after %.2f s (phase %.1f s)" % [took, _phase_t])
		_check(absf(took - UnitTypes.DATA.serpent.trap_time) < 0.15, "trap: coiling round the bush took %.1f s (%d)" % [took, UnitTypes.DATA.serpent.trap_time])
		_check(_rate("trap_icon_off") == 1.0, "trap: no icon until it is all coiled")
		_check(_rate("rifle_down") == 1.0, "trap: its rifle lies hidden in the bush")
		_say("Lying in wait", "Coiled, it never shoots. A defender who comes within %d m of the bush, it strikes" % UnitTypes.DATA.serpent.trap_reach)
	if _marks.has("coiled") and _once("coiled_checks"):
		_check(trapper.is_coiled() and trapper.get("_bush").visible and not trapper.ghosted(), "trap: coiled, the grass-and-snake icon over it, as ever on the attacker's side")
	if _marks.has("coiled") and _phase_t >= PREY_AT and _once("prey"):
		# A trooper walks past the bush.
		var at := bush.global_position
		prey = FlameTrooper.new()
		var from := at + Vector3(-12.0, 0.0, -3.0)
		_trooper(prey, from, at)
		prey.goal = at + Vector3(12.0, 0.0, 3.6)
		_marks.prey_hp0 = prey.hp
		_marks.decoy = FlameTrooper.new()
		_trooper(_marks.decoy, at + Vector3(3.0, 0.0, 9.0), at)  # standing in sight, out of its reach
		_marks.decoy_hp = _marks.decoy.hp
	if _marks.has("coiled") and trapper.is_coiled() and is_instance_valid(_marks.get("decoy")):
		_sample("no_shooting", is_equal_approx(_marks.decoy.hp, _marks.decoy_hp))
	var struck = _marks.get("struck_%d" % trapper.unit_id)
	if struck != null and not _marks.has("strike_checks"):
		_marks.strike_checks = true
		_marks.strike_t = struck[0]
		_marks.held_at = prey.global_position
		var d := _flat(prey.global_position, bush.global_position)
		print("SERPENT struck at %.1f s (phase %.1f s), the trooper %.1f m from the bush, %d hp" % [struck[0], _phase_t, d, struck[2]])
		_check(struck[1] == prey and d <= UnitTypes.DATA.serpent.trap_reach + 0.3, "trap: it struck the trooper as it came within %d m (%.1f m)" % [UnitTypes.DATA.serpent.trap_reach, d])
		_check(_rate("no_shooting") == 1.0, "trap: coiled, it never shot the trooper in sight beyond its reach")
		_check(not trapper.ghosted() and not trapper.get("_bush").visible, "trap: striking, it shows (no icon)")
		_say("The strike", "It winds round its prey and squeezes: %d s, its health running down to nothing" % UnitTypes.DATA.serpent.squeeze_time)
	if _marks.has("strike_t") and Combat.is_valid_target(prey):
		var s: float = t - _marks.strike_t
		var want: float = _marks.prey_hp0 * (1.0 - s / UnitTypes.DATA.serpent.squeeze_time)
		if s > 0.2 and s < UnitTypes.DATA.serpent.squeeze_time - 0.2:
			_sample("drain", absf(prey.hp - want) < 6.0)
			_sample("held", _flat(prey.global_position, _marks.held_at) < 0.05 and SerpentTrap.is_held(prey))
	if _marks.has("strike_t") and not _marks.has("order_tried") and t > _marks.strike_t + 6.0:
		_marks.order_tried = true
		controller._set_selection([trapper])
		_move_cursor(_screen(bush.global_position + Vector3(-6, 0, 6)), _phase_t, _phase_t + 0.5)
	if _marks.has("order_tried") and not _marks.has("order_given") and t > _marks.strike_t + 6.7:
		_marks.order_given = true
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_keycap.text = "RMB"
		_keycap.visible = true
		_check(trapper.is_constricting() and trapper.get("_after") == null and trapper.order.type == "trap", "trap: an order while it squeezes changes nothing")
	if _marks.has("order_given") and t > _marks.strike_t + 7.4:
		_keycap.visible = false
	var crushed = _marks.get("crushed_%d" % trapper.unit_id)
	if crushed != null and not _marks.has("crush_checks"):
		_marks.crush_checks = true
		var took: float = crushed[0] - _marks.strike_t
		print("SERPENT the trooper died %.2f s after the strike" % took)
		_check(absf(took - UnitTypes.DATA.serpent.squeeze_time) < 0.1, "trap: the trooper died %.1f s after the strike (%d)" % [took, UnitTypes.DATA.serpent.squeeze_time])
		_check(_rate("drain") > 0.97, "trap: its health ran down steadily (%d%%)" % [_rate("drain") * 100.0])
		_check(_rate("held") == 1.0, "trap: held, it never moved")
		_say("Back round its bush", "Its prey dead, it lets go and coils round the bush again")
	if crushed != null and trapper.is_coiled() and not _marks.has("recoiled"):
		_marks.recoiled = t
		_check(true, "trap: then it is coiled round its bush again")
	if _marks.has("recoiled") and _once("uncoil_order"):
		_marks.uncoil_go = bush.global_position + Vector3(-10.0, 0.0, 6.0)
		_move_cursor(_screen(_marks.uncoil_go), _phase_t + 1.0, _phase_t + 1.6)
		_marks.uncoil_order_at = _phase_t + 1.8
	if _marks.has("uncoil_order_at") and _phase_t >= _marks.uncoil_order_at and _once("uncoil_rmb"):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_keycap.text = "RMB"
		_keycap.visible = true
		_marks.uncoil_from = t
		_say("Uncoiling", "Any order uncoils it (%d s) and it picks its rifle up before it goes" % UnitTypes.DATA.serpent.trap_time)
		_check(trapper.skill_dir() < 0 and trapper.get("_after") != null, "trap: RMB on the ground, it uncoils")
	if _marks.has("uncoil_from") and t > _marks.uncoil_from + 0.6:
		_keycap.visible = false
	if _marks.has("uncoil_from") and not trapper.in_bush() and not _marks.has("uncoiled"):
		_marks.uncoiled = true
		var took: float = t - _marks.uncoil_from
		print("SERPENT uncoiled after %.2f s" % took)
		_check(absf(took - UnitTypes.DATA.serpent.trap_time) < 0.15, "trap: uncoiling took %.1f s (%d)" % [took, UnitTypes.DATA.serpent.trap_time])
		_check(is_zero_approx((trapper.serpent_rig() as SerpentRig).rifle_w), "trap: its rifle is back on its back")
		_check(bush.coiled_by == null, "trap: the bush is free again")


## The defender's side: a snake coiled round a bush, through a rifleman's eyes.
func _defender_step() -> void:
	if _once("start"):
		_lift_fog()
		_retire([trapper, prey, _marks.get("decoy")])
		var b := _pick_bush(EYES_NEAR, [bush])
		var at := b.global_position
		var out := Vector3(-1.0, 0.0, 0.2).normalized()
		ghost = _spawn(at + out * TRAP_START, atan2(out.x, out.z))
		commander.submit({"type": "trap", "units": [ghost.unit_id], "pos": at})
		_marks.ghost_bush = b
		eyes = _guard(at + Vector3(2.0, 0.0, 9.0), at)
		level.stations.append(eyes)
	if not is_instance_valid(ghost):
		return
	if _phase_at(0.1, "coil_now"):
		# Staged: skip ahead to the coil (it takes its 8 s in the trap phase).
		_check(ghost.order.type == "trap", "defender: sent round a bush")
	if ghost.in_bush() and not _marks.has("ghost_fast"):
		_marks.ghost_fast = true
		ghost.set("_skill_p", 0.97)
	if ghost.is_coiled() and _once("look"):
		GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
		defender = DefenderController.new()
		defender.level = level
		add_child(defender)
		defender.select_station(level.stations.find(eyes), true)
		var to: Vector3 = _marks.ghost_bush.global_position - eyes.global_position
		eyes.rotation.y = atan2(-to.x, -to.z)
		eyes.get_camera().get_parent().rotation.x = deg_to_rad(-12.0)
		controller.visible = false
		_say("The defender's side", "Coiled round its bush it is 70% see-through: no shadow, no health bar, no icon")
		_marks.look_at = _phase_t
	if _marks.has("look_at") and _phase_t > _marks.look_at + 0.3 and _once("look_checks"):
		_check(ghost.ghosted() and not ghost.get("_bush").visible, "defender: coiled, it is see-through on the defender's side, no icon")
		var mats := []
		for g in ghost.get("_ghosts"):
			mats.append(g[0].get_surface_override_material(g[1]))
		_check(not mats.is_empty() and mats.all(func(m): return m != null and is_equal_approx(m.albedo_color.a, 0.3) and m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA), "defender: drawn 30% opaque (70% see-through)")
		_check(ghost.get("_ghosts").all(func(g): return g[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "defender: no shadow")
		ghost.take_damage(10.0, GameConfig.TEAM_DEFENDER)
		_check(not ghost.get("_hp_bar").visible, "defender: no health bar, hurt or not")
	if _phase_at(9.6, "back"):
		if defender:
			defender.current.unpossess()
			defender.queue_free()
			defender = null
		GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
		controller.visible = true
		controller.camera_rig.camera.current = true
		controller.restore_mouse()
		level.stations.erase(eyes)
		eyes.queue_free()
		_retire([ghost])


## A trooper caught in another snake's coils; two riflemen shoot the snake dead in time: it goes free.
func _rescue_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_lift_fog()
		var b := _pick_bush(RESCUE_NEAR, [bush, _marks.get("ghost_bush")])
		var at := b.global_position
		_marks.rescue_bush = b
		var out := Vector3(0.3, 0.0, 1.0).normalized()
		rescuer = _spawn(at + out * TRAP_START, atan2(out.x, out.z))
		commander.submit({"type": "trap", "units": [rescuer.unit_id], "pos": at})
		controller._set_selection([])
		_pan(at + Vector3(0, 0, 3), 0.0, 1.0)
		rig._target_zoom = CLOSE_ZOOM + 4.0
		_say("Saved in time", "Killed before its 15 s are up, the snake lets its prey go with what health it has left")
	if not is_instance_valid(rescuer):
		pass
	elif rescuer.in_bush() and not _marks.has("rescue_fast"):
		_marks.rescue_fast = true
		rescuer.set("_skill_p", 0.97)
	if is_instance_valid(rescuer) and rescuer.is_coiled() and _once("prey"):
		var at: Vector3 = _marks.rescue_bush.global_position
		prey = FlameTrooper.new()
		_trooper(prey, at + Vector3(-11.0, 0.0, 2.0), at)
		prey.goal = at + Vector3(12.0, 0.0, -2.4)
		_marks.rescue_goal = prey.goal
	var struck = _marks.get("struck_%d" % rescuer.unit_id) if is_instance_valid(rescuer) else null
	if struck != null and _once("riflemen"):
		_marks.rescue_strike = t
		var at: Vector3 = _marks.rescue_bush.global_position
		# Off to the side, a clear line on the snake (the trooper in its coils would take rounds meant for it).
		for p in [at + Vector3(-1.5, 0.0, -10.0), at + Vector3(2.5, 0.0, -9.0)]:
			var s := _guard(p, at)
			s.set_physics_process(true)  # these fight
			shooters.append(s)
	if _marks.has("rescue_strike") and not _marks.has("freed") and (not is_instance_valid(rescuer) or not rescuer.is_alive()):
		_marks.freed = t
		_marks.freed_hp = prey.hp if Combat.is_valid_target(prey) else 0.0
		_marks.freed_at = prey.global_position
		print("SERPENT the snake was shot dead %.1f s into the squeeze; the trooper has %d hp" % [t - _marks.rescue_strike, _marks.freed_hp])
	if _marks.has("freed") and _once("freed_checks"):
		_check(t - _marks.rescue_strike < UnitTypes.DATA.serpent.squeeze_time, "rescue: the riflemen shot the snake dead within the %d s" % UnitTypes.DATA.serpent.squeeze_time)
		_check(Combat.is_valid_target(prey) and not SerpentTrap.is_held(prey), "rescue: the trooper goes free")
		_check(_marks.freed_hp > 0.0 and _marks.freed_hp < prey.max_hp, "rescue: with the health it had left (%d / %d)" % [_marks.freed_hp, prey.max_hp])
		_check(_marks.rescue_bush.coiled_by == null, "rescue: the bush is free again")
	if _marks.has("freed") and _phase_at(17.5, "walked"):
		_check(Combat.is_valid_target(prey) and _flat(prey.global_position, _marks.freed_at) > 2.0, "rescue: and walks on (%.1f m)" % _flat(prey.global_position, _marks.freed_at))


## The fog of war has had its turn (the nest, the trap): gone for the rest of the run, as in a showcase without
## it, so the defender's side sees its own men and the field doesn't go dark once the last snake is dead.
func _lift_fog() -> void:
	if not is_instance_valid(vision):
		return
	var fog: Node = controller.get("_fog")
	if fog:
		fog.queue_free()
		controller.set("_fog", null)
	vision.queue_free()
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if AttackerVision._hides(d):
			d.visible = true


## A lone standing tree near `near`, tall enough, with room round it.
func _pick_tree(near: Vector3) -> ForestTree:
	var best: ForestTree = null
	var best_d := INF
	for tr in ForestTree.standing:
		var foot := tr.trunk_centre()
		if tr.height < 7.0 or absf(foot.x) < 12.0:
			continue
		var crowded := ForestTree.standing.any(func(o): return o != tr and _flat(o.global_position, tr.global_position) < 7.0)
		if crowded:
			continue
		var d := _flat(foot, near)
		if d < best_d:
			best_d = d
			best = tr
	return best


## A usable bush near `near`, clear of the trees and of the other bushes round it, not one of `used`.
func _pick_bush(near: Vector3, used: Array) -> Bush:
	var best: Bush = null
	var best_d := INF
	for b in Bush.all:
		if not b.usable or b in used or b.radius < 0.35:
			continue
		var p := b.global_position
		if ForestTree.all.any(func(tr): return _flat(tr.global_position, p) < 6.0):
			continue
		if Bush.all.any(func(o): return o != b and _flat(o.global_position, p) < 3.0):
			continue
		var d := _flat(p, near)
		if d < best_d:
			best_d = d
			best = b
	return best


# ---------------------------------------------------------------- the field

func _trooper(tr: SquadTrooper, at: Vector3, face: Vector3) -> void:
	add_child(tr)
	tr.global_position = at + Vector3.UP * 0.1
	tr.aim_point = face + Vector3.UP
	tr.following = true
	tr.goal = at


## A rifleman standing in the field, looking toward `look` (he doesn't fight until let loose).
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


## Rounds from `shooter` landing on `at` (its health going down by about a round's damage).
func _watch_hits(shooter, at) -> void:
	if not is_instance_valid(shooter) or not is_instance_valid(at):
		return
	var key := "hp_%d_%d" % [shooter.get_instance_id(), at.get_instance_id()]
	var was: float = _marks.get(key, at.hp)
	if at.hp < was - 1.0:
		_shots.append([t, shooter, at, was, at.hp])
	_marks[key] = at.hp


# ---------------------------------------------------------------- checks

func _sample(what: String, ok: bool) -> void:
	var s: Array = _samples.get(what, [0, 0])
	_samples[what] = [s[0] + (1 if ok else 0), s[1] + 1]


func _rate(what: String) -> float:
	var s: Array = _samples.get(what, [0, 0])
	return float(s[0]) / maxf(s[1], 1.0)


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	for c in _checks:
		print("SERPENT CHECK ", c)
	print("SERPENT SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
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
			var p := snake.global_position
			var a := 0.6 + _phase_t * 0.2
			at = p + Vector3(sin(a) * 5.5, 1.6, cos(a) * 5.5)
			look = p + Vector3(0.0, 0.35, 0.0)
		"beside":
			var p := snake.global_position
			var fwd := -snake.global_basis.z
			var right := fwd.cross(Vector3.UP).normalized()
			at = p + right * 6.0 + fwd * 1.5 + Vector3.UP * 1.3
			look = p + fwd * 0.8 + Vector3.UP * 0.3
		"behind":
			var p := snake.global_position
			var to := (TARGET_AT - p).normalized()
			at = p - to * 4.5 + to.cross(Vector3.UP) * 2.2 + Vector3.UP * 1.6
			look = p + to * 8.0 + Vector3.UP * 0.6
		"climb":
			# Off to the side the snake came from, the whole tree in view: up the trunk and into the crown.
			var foot := tree.trunk_centre()
			var out := _flat_dir(_marks.nest_start - foot)
			var side := out.cross(Vector3.UP)
			var up := clampf(nester.global_position.y / tree.perch, 0.0, 1.0)
			at = foot + out * 11.0 + side * 5.0 + Vector3.UP * lerpf(1.8, 4.5, up)
			look = foot + Vector3.UP * lerpf(2.2, tree.height * 0.68, up)
		"perch":
			# Above and behind it on top of the crown, looking out over its head along the rifle.
			var foot := tree.trunk_centre()
			var fwd := _flat_dir(-nester.global_basis.z)
			var side := fwd.cross(Vector3.UP)
			at = foot - fwd * 3.0 + side * 3.2 + Vector3.UP * (tree.perch + 3.0)
			look = foot + fwd * 6.0 + Vector3.UP * (tree.perch - 1.5)
		"coil":
			var b := bush.global_position
			var out := _flat_dir(trapper.get("_skill_xf").origin - b) if trapper.in_bush() else Vector3(1, 0, 0.35).normalized()
			at = b + out * 4.5 + out.cross(Vector3.UP) * 2.5 + Vector3.UP * 2.2
			look = b + Vector3.UP * 0.2
		"strike":
			# Side-on to the strike, low.
			var b := bush.global_position
			var p: Vector3 = _marks.get("held_at", b + Vector3(-3, 0, 0))
			var across := _flat_dir(p - b).cross(Vector3.UP)
			at = (b + p) * 0.5 + across * 6.0 + Vector3.UP * 1.4
			look = (b + p) * 0.5 + Vector3.UP * 0.7
		"squeeze":
			var p: Vector3 = _marks.get("held_at", bush.global_position)
			var a := 2.2 + _phase_t * 0.18
			at = p + Vector3(sin(a) * 3.6, 1.9, cos(a) * 3.6)
			look = p + Vector3.UP * 0.9
		"rescue":
			var b: Vector3 = _marks.rescue_bush.global_position
			at = b + Vector3(6.0, 2.6, 5.0)
			look = b + Vector3(-3.0, 0.6, -2.0)
	cam.global_position = at
	cam.look_at(look)


func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.01 else Vector3.FORWARD


## The snakes' state on the panel's right while their skills are shown.
func _update_status() -> void:
	var shown := []
	match phase:
		"nest":
			shown = [nester]
		"trap":
			shown = [trapper]
		"rescue":
			shown = [rescuer]
	shown = shown.filter(func(u): return is_instance_valid(u) and u.is_alive())
	_status.visible = not shown.is_empty()
	if not _status.visible:
		return
	var lines := []
	for u in shown:
		var state := ""
		if u.is_perched():
			state = "perched · sees %d m · reaches %d m" % [u.sight(), u.reach()]
		elif u.in_tree():
			state = "climbing %s %d%%" % ["up" if u.skill_dir() > 0 else "down", roundi(u.skill_progress() * 100.0)]
		elif u.is_constricting():
			state = "constricting %.0f s" % u.squeeze_left()
		elif u.is_coiled():
			state = "coiled, lying in wait"
		elif u.in_bush():
			state = "%s %d%%" % ["coiling" if u.skill_dir() > 0 else "uncoiling", roundi(u.skill_progress() * 100.0)]
		lines.append("%s  %d / %d  %s" % [u.stats.name, int(u.hp), int(u.stats.hp), state])
	if (phase == "trap" or phase == "rescue") and Combat.is_valid_target(prey):
		lines.append("Flame Trooper  %d / %d%s" % [int(prey.hp), int(prey.max_hp), "  held" if SerpentTrap.is_held(prey) else ""])
	_status.text = "\n".join(lines)


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _screen(p: Vector3) -> Vector2:
	return controller.camera_rig.camera.unproject_position(p)


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
