extends Node3D
## Folding bridges, swimmers and riders on the Jungle Keep's main river (FoldingBridge, RiverCrossing,
## AttackerCommander's ferry), west of the citadel's way north, on the real map.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/bridge_showcase.tscn -- --test
##       prints and checks: BRIDGE SHOWCASE PASS / FAIL
##   godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/bridge_showcase.tscn -- --shots=DIR [--only=a,b]
##       the same run, with stills (.png) in DIR on the way (--only: just those, and it stops after the last):
##   swim_bears        bears and a Serpent Sniper swimming across, only their heads and backs over the water
##   swim_carriers     a hippo and an elephant swimming across, two riders on each one's back
##   riders_close      close by the hippo: a kangaroo and a chimp riding on its back across the river
##   riders_elephant   close by the elephant: a lioness and a Wolf Medic on its back
##   left_behind       the giraffe and the rhino left on the south bank (they can't swim or ride), a kangaroo
##                     with no seat left beside them, the eagles flying over
##   preview           the RTS view: the cyan preview across the river under the cursor
##   preview_bad       red where it can't go (the river too wide where the lake's outlet comes in)
##   drop_fall         it comes down out of the sky folded
##   drop_thrusters    the thrusters braking it
##   drop_unfold       unfolding in the hover
##   bridge_down       down across the river
##   bridge_crossing   the giraffe, the rhino, a Bison Field Gun and the Mule Artillery crossing it
##   alarm             defenders on it: the red lights flashing along its railings, the alarm on the RTS HUD
##   under_fire        shells bursting on it: no alarm, its health barely down
##   godot --path game --resolution 1280x720 --write-movie bridge.avi --fixed-fps 30 res://scenes/dev/bridge_showcase.tscn -- --video
##       the drop as a video: the RTS view, Shift+B, the preview following the cursor along the river, the click; then
##       down by the river it comes out of the sky folded, the thrusters light, it hovers and unfolds and comes down
##       onto the banks; the RTS view again, one bridge fewer left.
##
## The checks: 30 bridges and no more; no bridge on dry land, across the lake's outlet where it is too wide, or on top
## of another; with no bridge the giraffe, the rhino, the bison and the mule can't get across and go only to the
## south bank; the bears, the snake, the hippo and the elephant swim over (no shot fired nor skill used while in the
## water); the kangaroos, the chimp, the lioness and the dog hop onto the hippo and the elephant, two each, the one
## left over stays behind, and the riders get off on the north bank and go to their spots; the eagles fly over; the
## bridge comes down where its preview showed it, the navmesh and the wall at the water's edge open over it, and the
## four that can't swim or ride walk over it; a defender on it sets the alarm off until it is off it again; shots
## and shells on it set no alarm off and take ARMOR off every hit; brought down, the bridge sinks, the chimp on it
## drowns, the bear on it swims to the bank, and the way over is gone again.

## The river (main) here: where the army stands on its south bank, where it goes on the north bank.
const SOUTH := Vector3(-322.0, 0.0, 509.0)
const NORTH := Vector3(-322.0, 0.0, 420.0)
const LEFT_AT := Vector3(-298.0, 0.0, 512.0)
const EAGLES_AT := Vector3(-345.0, 0.0, 518.0)
## Where the bridge goes, and the four that can't swim or ride walk over it to.
const BRIDGE_AT := Vector3(-200.0, 0.0, 462.0)
const HEAVY_AT := Vector3(-206.0, 0.0, 518.0)
const OVER_TO := Vector3(-202.0, 0.0, 408.0)
## Where it can't go: the lake's outlet coming into the river (too wide), and dry land.
const WIDE_AT := Vector3(-590.0, 0.0, 488.0)
const DRY_AT := Vector3(-200.0, 0.0, 300.0)
## Defenders on the north bank who cross it (the alarm).
const TROOPERS_AT := [Vector3(-205.0, 0.0, 412.0), Vector3(-198.0, 0.0, 410.0)]
const TROOPERS_TO := Vector3(-201.0, 0.0, 520.0)
## A defender standing on the north bank in the bears' rifles' reach (they hold fire while swimming).
const DUMMY_AT := Vector3(-326.0, 0.0, 431.0)

## Stills: [camera, look at, fov]; the ones with a node name follow it.
const SHOT_CAMS := {
	"swim_bears": [Vector3(-305.0, 2.0, 448.0), Vector3(-322.0, -1.5, 462.0), 50.0],
	"swim_carriers": [Vector3(-300.0, 4.5, 445.0), Vector3(-322.0, -0.5, 466.0), 52.0],
	"bridge_down": [Vector3(-150.0, 26.0, 515.0), Vector3(-200.0, 0.0, 462.0), 55.0],
	"bridge_crossing": [Vector3(-170.0, 9.0, 486.0), Vector3(-201.0, 2.5, 462.0), 55.0],
	"alarm": [Vector3(-178.0, 6.0, 482.0), Vector3(-200.0, 3.0, 462.0), 58.0],
	"under_fire": [Vector3(-162.0, 12.0, 497.0), Vector3(-200.0, 2.0, 462.0), 55.0],
}

var level: JungleLevel
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var test := false
var video := false
var shots_dir := ""
var bridge: FoldingBridge
## --only=a,b: just those stills (the run stops after the last of them).
var only: Array = []
var _only_given := false

var _failed := false
var _acts := 0
var _cursor: Control
var _caption: Label
var _keycap: Label
var _follow: Node3D
var _cam_from := Vector3.ZERO
var _cam_to := Vector3.ZERO
var _cam_t := Vector2.ZERO
var _cam_clock := 0.0
var _look := Vector3.ZERO
var _look_smooth := Vector3.ZERO
var _frames_shot := 0


func _ready() -> void:
	seed(7)
	var args := OS.get_cmdline_user_args()
	test = "--test" in args
	video = "--video" in args
	for arg in args:
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			only = Array(arg.get_slice("=", 1).split(","))
			_only_given = true
	if not test and not video and shots_dir == "":
		test = DisplayServer.get_name() == "headless"
	if video or shots_dir != "":
		RenderingServer.render_loop_enabled = false  # nothing to see while the map loads (the bake goes faster)
	GameConfig.map = "jungle"
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	level = JungleLevel.new()
	add_child(level)
	level.build()
	# Staged: the posts and the AA turrets hold fire, the Gunner Squad sits it out.
	for s in level.stations + level.aa_turrets:
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.level = level
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	add_child(commander)
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	controller.camera_rig.edge_scroll = false
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 3000.0
	add_child(cam)
	_build_overlay()
	for l in controller.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("LMB select"):
			l.visible = false
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# Stills: only the frames saved are drawn (the rest of the run goes at full speed). The video draws every one.
	RenderingServer.render_loop_enabled = video
	await _frames(10)
	if video:
		_light_video()
		await _deploy_video()
		get_tree().quit()
		return
	_check_stock_and_plans()
	await _act_cross()
	await _act_bridge()
	await _act_alarm()
	if test:
		await _act_board()
	await _act_fall()
	# A script error in an act cuts it short: all four must have run to the end.
	_check(_acts == (5 if test else 4), "all the acts ran to the end (%d)" % _acts)
	print("BRIDGE SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------- act 1: no bridge, across the water

var swimmers: Array = []
var riders: Array = []
var carriers: Array = []
var walkers: Array = []
var eagles: Array = []
var spare: AttackerUnit
var dummy: FlameTrooper


func _act_cross() -> void:
	# Bears and a snake to swim, a hippo and an elephant to carry, the riders, the ones that can do neither, eagles.
	for k in 2:
		swimmers.append(_unit("rifleman", SOUTH + Vector3(-6.0 + k * 4.0, 0, 0)))
	swimmers.append(_unit("serpent", SOUTH + Vector3(6.0, 0, 2.0)))
	carriers.append(_unit("hippo", SOUTH + Vector3(-4.0, 0, 6.0)))
	carriers.append(_unit("elephant", SOUTH + Vector3(5.0, 0, 7.0)))
	for t in ["kangaroo", "chimp", "lioness", "medic", "kangaroo"]:
		riders.append(_unit(t, SOUTH + Vector3(-8.0 + riders.size() * 4.0, 0, 12.0)))
	for t in ["giraffe", "rhino"]:
		walkers.append(_unit(t, LEFT_AT + Vector3(walkers.size() * 6.0, 0, 0)))
	for k in 2:
		eagles.append(_unit("talon", EAGLES_AT + Vector3(k * 5.0, 0, 0)))
	# A defender on the north bank in their reach (not for the stills: the shots' tracers would pile up while
	# nothing is drawn).
	var armed := shots_dir == ""
	if armed:
		dummy = FlameTrooper.new()
		add_child(dummy)
		dummy.global_position = _ground(DUMMY_AT) + Vector3.UP * 0.1
		dummy.aim_point = SOUTH
		dummy.following = true
		dummy.goal = dummy.global_position
	await _frames(30)
	var start_hp := 0.0
	if armed:
		# It stands there and takes it (its body stays in the physics space for the shots to hit).
		dummy.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		dummy.process_mode = Node.PROCESS_MODE_DISABLED
		start_hp = dummy.hp
	var everyone: Array = swimmers + carriers + riders + walkers + eagles
	commander.submit({"type": "move", "units": _ids(everyone), "pos": NORTH, "attack": true})
	await _frames(2)
	var boarding := riders.filter(func(u): return u.order.type == "board")
	_check(boarding.size() == 4, "4 of the 5 riders go to board the hippo and the elephant (2 seats each): %d" % boarding.size())
	spare = null
	for r in riders:
		if r.order.type != "board":
			spare = r
	_check(spare != null, "the one left over has no seat: the %s" % (spare.stats.name if spare else "none"))
	_check(walkers.all(func(u): return u.order.type != "board"), "the giraffe and the rhino don't board (they can't ride)")
	# Swimming and riding: nobody fires or uses a skill; never more than two on a back.
	var shot_while_swimming := false
	var most_aboard := 0
	var swam := {}
	var rode := {}
	var skill_tried := false
	var skills_used := false
	var fire_cd := {}
	for frame in 30 * 150:
		await get_tree().physics_frame
		for u in swimmers + carriers:
			if is_instance_valid(u) and u.is_swimming() and u.in_water():
				swam[u] = true
		for c in carriers:
			most_aboard = maxi(most_aboard, c.riders.size())
		for r in riders:
			if r.is_riding():
				rode[r] = true
		# A shot resets the shooter's fire cooldown: none of them may fire swimming or riding.
		for u in swimmers + carriers + riders:
			if u.is_crossing() and u._fire_cd > float(fire_cd.get(u, 0.0)) + 0.01:
				shot_while_swimming = true
			fire_cd[u] = u._fire_cd
		# In the water the hippo's smoke and the kangaroo's flash are refused.
		if not skill_tried and carriers[0].is_swimming() and carriers[0].in_water() and carriers[0].riders.size() > 0:
			skill_tried = true
			var roo = carriers[0].riders.filter(func(r): return r.type_id == "kangaroo")
			commander.submit({"type": "smoke", "units": [carriers[0].unit_id], "pos": NORTH})
			if not roo.is_empty():
				commander.submit({"type": "flash", "units": [roo[0].unit_id], "pos": NORTH})
			await _frames(2)
			skills_used = carriers[0].smoke_cd > 0.0 or (not roo.is_empty() and roo[0].flash_cd > 0.0)
		if shots_dir != "":
			await _shots_on_the_way(frame)
		var over: Array = swimmers + carriers + riders.filter(func(r): return r != spare) + eagles
		if over.all(func(u): return _flat(u.global_position, NORTH) < 40.0 and not u.is_crossing() and u.global_position.z < 445.0) \
				and riders.all(func(r): return not r.is_riding()) and frame > 120:
			break
	_check(swam.size() == 5, "the bears, the snake, the hippo and the elephant swam across (%d of 5 seen in the water)" % swam.size())
	_check(rode.size() == 4, "4 riders rode across on the carriers' backs: %d" % rode.size())
	_check(most_aboard <= 2, "never more than 2 on a back: %d" % most_aboard)
	if armed:
		_check(not shot_while_swimming, "nobody fired swimming or riding (the defender on the bank in reach)")
	_check(skill_tried and not skills_used, "no skill used out on the water (the hippo's smoke, a riding kangaroo's flash refused)")
	for u in swimmers + carriers + riders.filter(func(r): return r != spare):
		_check(u.global_position.z < 445.0 and not u.is_crossing(), "%s got over to the north bank (z %.0f)" % [u.stats.name, u.global_position.z])
	for u in eagles:
		_check(u.global_position.z < 445.0, "%s flew over (z %.0f)" % [u.stats.name, u.global_position.z])
	_check(spare.global_position.z > 480.0, "the %s with no seat stayed on the south bank (z %.0f)" % [spare.stats.name, spare.global_position.z])
	for u in walkers:
		_check(u.global_position.z > 480.0 and not RiverCrossing.wet(u.global_position), "%s went only as far as the south bank (z %.0f)" % [u.stats.name, u.global_position.z])
	if armed:
		await _frames(120)
		_check(dummy.hp < start_hp, "out of the water they fire at the defender on the bank (%d hp off it)" % int(start_hp - dummy.hp))
		dummy.queue_free()
	else:
		# From over the water, the giraffe and the rhino on the south bank, the eagles gone over.
		cam.fov = 56.0
		var g: Vector3 = walkers[0].global_position
		await _shoot("left_behind", Vector3(g.x + 14.0, JungleLayout.WATER_Y + 4.0, g.z - 30.0), g + Vector3(-4.0, 2.5, 0.0))
	_acts += 1


## The stills on the way across, each once, when there is something to see.
var _taken := {}


func _shots_on_the_way(_frame: int) -> void:
	var bears_in := swimmers.filter(func(u): return u.is_swimming() and u.in_water())
	if not _taken.has("swim_bears") and bears_in.size() >= 3 and bears_in.all(func(u): return _mid_river(u) and _sunny(u)):
		_taken["swim_bears"] = true
		var c: Vector3 = bears_in[0].global_position
		cam.fov = 44.0
		await _shoot("swim_bears", Vector3(c.x + 6.0, JungleLayout.WATER_Y + 1.2, c.z - 6.0), Vector3(c.x - 0.5, JungleLayout.WATER_Y + 0.6, c.z + 1.5))
	var full := carriers.filter(func(c): return c.riders.size() == 2 and c.in_water())
	if not _taken.has("swim_carriers") and full.size() == 2 and full.all(func(u): return _mid_river(u) and _sunny(u)):
		_taken["swim_carriers"] = true
		var c := _centre(full)
		cam.fov = 48.0
		await _shoot("swim_carriers", Vector3(c.x + 10.0, JungleLayout.WATER_Y + 2.6, c.z - 11.0), Vector3(c.x, JungleLayout.WATER_Y + 1.0, c.z))
	if not _taken.has("riders_close") and carriers[0].riders.size() == 2 and _mid_river(carriers[0]) and _sunny(carriers[0]):
		_taken["riders_close"] = true
		await _shot_close("riders_close", carriers[0], Vector3(7.5, 1.8, -5.5), 48.0)
	if not _taken.has("riders_elephant") and carriers[1].riders.size() == 2 and _mid_river(carriers[1]) and _sunny(carriers[1]):
		_taken["riders_elephant"] = true
		await _shot_close("riders_elephant", carriers[1], Vector3(-8.5, 2.6, -6.5), 48.0)


func _centre(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in list:
		c += u.global_position
	return c / maxi(list.size(), 1)


## Past the middle of the river, out of the shade the south bank's trees throw over the water.
func _sunny(u: Node3D) -> bool:
	return u.global_position.z < 457.0


## Out in the deep water (the bed well under its feet).
func _mid_river(u: Node3D) -> bool:
	return u.in_water() and RiverCrossing.ground(Vector2(u.global_position.x, u.global_position.z)) < JungleLayout.WATER_Y - 3.0


# ---------------------------------------------------------------- act 2: the bridge

var heavies: Array = []


func _act_bridge() -> void:
	# The bison and the mule join the giraffe and the rhino on the south bank by the bridge.
	heavies = walkers.duplicate()
	for t in ["bison_gun", "mule"]:
		heavies.append(_unit(t, HEAVY_AT + Vector3(heavies.size() * 7.0 - 10.0, 0, 0)))
	commander.submit({"type": "move", "units": _ids(walkers), "pos": HEAVY_AT + Vector3(6, 0, 4), "attack": false})
	_check(not RiverCrossing.reaches(self, HEAVY_AT, OVER_TO), "no way over on foot before the bridge")
	# The preview, then the drop where it showed.
	if shots_dir != "":
		await _preview_shots()
	var plan := FoldingBridge.plan(BRIDGE_AT)
	_check(plan.ok, "a bridge can go across the river at x %.0f (%s, %.0f m long)" % [BRIDGE_AT.x, plan.reason, plan.length])
	var left := commander.bridges_left
	var id := commander.submit({"type": "bridge", "pos": BRIDGE_AT})
	_check(id != 0 and commander.bridges_left == left - 1, "the bridge is ordered (%d left)" % commander.bridges_left)
	bridge = commander.bridges[-1]
	_check(bridge.global_transform.origin.distance_to(plan.xform.origin) < 0.01, "it comes down where its preview showed it")
	var t0 := bridge.age
	var phases := {}
	while not bridge.is_standing():
		await get_tree().physics_frame
		phases[bridge.state] = true
		if shots_dir != "":
			if bridge.state == FoldingBridge.State.DROPPING and bridge._alt < 150.0 and not _taken.has("drop_fall"):
				_taken["drop_fall"] = true
				# From down by the water, looking up at it coming out of the sky.
				cam.fov = 30.0
				var b := bridge.global_position
				await _shoot("drop_fall", Vector3(b.x + 40.0, JungleLayout.WATER_Y + 6.0, b.z + 8.0), bridge._rig.global_position)
			if bridge.state == FoldingBridge.State.BRAKING and bridge._alt < 50.0 and not _taken.has("drop_thrusters"):
				_taken["drop_thrusters"] = true
				await _shot_close("drop_thrusters", bridge._rig, Vector3(30.0, -12.0, 34.0), 58.0)
			if bridge.state == FoldingBridge.State.UNFOLDING and bridge._fold < 0.55 and not _taken.has("drop_unfold"):
				_taken["drop_unfold"] = true
				await _shot_close("drop_unfold", bridge._rig, Vector3(26.0, -16.0, 52.0), 62.0)
	var took := bridge.age - t0
	var drop := [FoldingBridge.State.DROPPING, FoldingBridge.State.BRAKING, FoldingBridge.State.UNFOLDING, FoldingBridge.State.LANDING]
	_check(drop.all(func(st): return phases.has(st)), "down it came folded, braked on its thrusters, unfolded and came down")
	_check(took > 8.0 and took < 16.0, "the drop took %.1f s" % took)
	# The navmesh takes it in once the tiles under it are rebaked.
	var over := false
	for k in 300:
		await _frames(4)
		if RiverCrossing.reaches(self, HEAVY_AT, OVER_TO):
			over = true
			break
	_check(over, "the way over on foot is there once it is down")
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, LevelBuilder.nav_closest(get_world_3d().navigation_map, _ground(HEAVY_AT)),
			LevelBuilder.nav_closest(get_world_3d().navigation_map, _ground(OVER_TO)), true, 1)
	_check(Array(path).any(func(p): return bridge.carries(p)), "and it goes over the bridge")
	if shots_dir != "":
		await _shot("bridge_down")
	# The four that can't swim or ride walk over it.
	commander.submit({"type": "move", "units": _ids(heavies), "pos": OVER_TO, "attack": false})
	var on_it := {}
	var shot_crossing := false
	for frame in 30 * 200:
		await get_tree().physics_frame
		for u in heavies:
			if bridge.carries(u.global_position):
				on_it[u] = true
		var crossing := heavies.filter(func(u): return bridge.carries(u.global_position))
		if shots_dir != "" and not shot_crossing and on_it.size() >= 3 and crossing.size() >= 2:
			shot_crossing = true
			# From up over the far bank's side, down along the deck at them.
			var c := _centre(crossing)
			var ax := bridge.global_basis.x
			var fwd := ax if ax.dot(OVER_TO - c) > 0.0 else -ax
			cam.fov = 52.0
			await _shoot("bridge_crossing", c + fwd * 16.0 + bridge.global_basis.z * 14.0 + Vector3.UP * 11.0, c + Vector3.UP * 1.0)
		if heavies.all(func(u): return u.global_position.z < 430.0):
			break
	for u in heavies:
		_check(on_it.has(u) and u.global_position.z < 430.0, "%s walked over the bridge to the north bank (z %.0f)" % [u.stats.name, u.global_position.z])
	_acts += 1


func _preview_shots() -> void:
	var rig := controller.camera_rig
	cam.current = false
	rig.camera.current = true
	controller.visible = true
	rig.rotation.y = 0.0
	rig.pitch = deg_to_rad(-55.0)
	rig.zoom = 95.0
	rig._target_zoom = 95.0
	rig.focus(BRIDGE_AT + Vector3(0, 0, 18))
	controller.toggle_bridge()
	await _frames(3)
	_cursor.visible = true
	_set_cursor(rig.camera.unproject_position(_ground(BRIDGE_AT) + Vector3(-6, 0, -4)))
	await _frames(3)
	await _snap("preview")
	rig.focus(WIDE_AT + Vector3(0, 0, 18))
	await _frames(3)
	_set_cursor(rig.camera.unproject_position(_ground(WIDE_AT)))
	await _frames(3)
	await _snap("preview_bad")
	controller.toggle_bridge()
	_cursor.visible = false


# ---------------------------------------------------------------- act 3: defenders on it

func _act_alarm() -> void:
	var alarms: Array = []
	commander.bridge_alarm.connect(func(b, on): alarms.append([b, on]))
	var troopers: Array = []
	for p in TROOPERS_AT:
		var tr := FlameTrooper.new()
		add_child(tr)
		_no_cull(tr)
		tr.global_position = _ground(p) + Vector3.UP * 0.1
		tr.aim_point = TROOPERS_TO
		tr.following = true
		tr.goal = tr.global_position
		troopers.append(tr)
	# The army keeps away: nobody shoots them on the way.
	for u in commander.units.values():
		u.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(20)
	_check(not bridge.alarm_on, "no alarm with nobody on it")
	for tr in troopers:
		tr.goal = TROOPERS_TO + Vector3(randf_range(-2, 2), 0, 0)
	var on := false
	var shot := false
	for frame in 30 * 90:
		await get_tree().physics_frame
		on = on or bridge.alarm_on
		if shots_dir != "" and bridge.alarm_on and not shot and troopers.any(func(t): return absf((bridge.global_transform.affine_inverse() * t.global_position).x) < 8.0):
			shot = true
			await _frames(6)
			# Low by the railing, along the deck at them, the lamps flashing either side.
			var c := _centre(troopers)
			var ax := bridge.global_basis.x
			var ahead := ax if ax.dot(TROOPERS_TO - c) > 0.0 else -ax
			cam.fov = 58.0
			await _shoot("alarm", c + ahead * 13.0 + bridge.global_basis.z * 7.5 + Vector3.UP * 4.5, c + Vector3.UP * 1.2)
		if on and troopers.all(func(t): return t.global_position.z > 500.0):
			break
	_check(on, "the alarm went off with defenders on it")
	await _frames(20)
	_check(not bridge.alarm_on, "and stopped once they were off it")
	_check(alarms.size() >= 2 and alarms[0][1] == true and alarms[-1][1] == false, "the attacking player was warned (%d alarm signals)" % alarms.size())
	for tr in troopers:
		tr.queue_free()
	for u in commander.units.values():
		u.process_mode = Node.PROCESS_MODE_INHERIT
	# Shot at: no alarm, and every hit ARMOR less.
	var hp := bridge.hp
	for k in 10:
		bridge.take_damage(26.0, GameConfig.TEAM_DEFENDER)
	_check(is_equal_approx(hp - bridge.hp, 10.0 * (26.0 - FoldingBridge.ARMOR)), "10 rifle hits take %d off it (%d each)" % [int(hp - bridge.hp), int(26.0 - FoldingBridge.ARMOR)])
	hp = bridge.hp
	for k in 3:
		Combat.explode(self, bridge.global_transform * Vector3(-14.0 + 14.0 * k, 0.5, 0.0), 6.0, 150.0, GameConfig.TEAM_DEFENDER)
	if shots_dir != "":
		await _frames(4)
		await _shot("under_fire")
	await _frames(10)
	_check(bridge.hp < hp, "the shells bursting on it hurt it (%d off)" % int(hp - bridge.hp))
	_check(not bridge.alarm_on, "being shot at sets no alarm off")
	_check(bridge.hp > FoldingBridge.MAX_HP * 0.85, "and it's tough: %d of %d left" % [int(bridge.hp), int(FoldingBridge.MAX_HP)])
	_acts += 1


# ---------------------------------------------------------------- act 4: brought down

## The player's own boarding (RMB a carrier with riders selected: "board"; Space: "unload"), on dry land.
func _act_board() -> void:
	var at := OVER_TO + Vector3(-14.0, 0.0, -8.0)
	var hippo := _unit("hippo", at)
	var chimp := _unit("chimp", at + Vector3(6.0, 0.0, 3.0))
	var roo := _unit("kangaroo", at + Vector3(-6.0, 0.0, 3.0))
	var dog := _unit("medic", at + Vector3(0.0, 0.0, 7.0))
	var giraffe := _unit("giraffe", at + Vector3(3.0, 0.0, 8.0))
	await _frames(20)
	commander.submit({"type": "board", "units": _ids([chimp, roo, dog, giraffe]), "carrier": hippo.get_path()})
	_check(giraffe.order.type != "board", "a giraffe can't board (%s)" % giraffe.order.type)
	var boarding := [chimp, roo, dog].filter(func(u): return u.order.type == "board")
	_check(boarding.size() == 2, "two of the three riders go to board it (2 seats): %d" % boarding.size())
	for k in 30 * 20:
		await get_tree().physics_frame
		if hippo.riders.size() == 2:
			break
	_check(hippo.riders.size() == 2, "they hop onto its back: %d" % hippo.riders.size())
	var rider: AttackerUnit = hippo.riders[0] if not hippo.riders.is_empty() else null
	commander.submit({"type": "move", "units": [hippo.unit_id], "pos": at + Vector3(0, 0, -12.0), "attack": false})
	for k in 30 * 8:
		await get_tree().physics_frame
	_check(hippo.riders.size() == 2, "on dry land they stay on while it walks (no water crossed)")
	_check(rider != null and rider.global_position.distance_to(hippo.seat_transform(0).origin) < 0.5, "riding on its back as it goes")
	commander.submit({"type": "unload", "units": [hippo.unit_id]})
	for k in 30 * 3:
		await get_tree().physics_frame
	_check(hippo.riders.is_empty() and rider != null and not rider.is_riding() and rider.is_on_floor(), "Space: they hop off beside it")
	for u in [hippo, chimp, roo, dog, giraffe]:
		commander.units.erase(u.unit_id)
		u.queue_free()
	_acts += 1


func _act_fall() -> void:
	# A chimp (can't swim) and a bear (can) standing on it.
	var chimp := _unit("chimp", bridge.global_transform * Vector3(-4.0, 0.3, 1.5))
	var bear := _unit("rifleman", bridge.global_transform * Vector3(4.0, 0.3, -1.5))
	for k in 30:
		await get_tree().physics_frame
	_check(bridge.carries(chimp.global_position) and bridge.carries(bear.global_position), "a chimp and a bear stand on the bridge")
	while bridge.is_alive():
		bridge.take_damage(800.0, GameConfig.TEAM_DEFENDER)
	_check(bridge.state == FoldingBridge.State.FALLEN, "brought down")
	_check(not chimp.is_alive(), "the chimp on it drowned")
	var lived := false
	for k in 30 * 60:
		await get_tree().physics_frame
		if bear.is_alive() and not bear.is_swimming() and not RiverCrossing.wet(bear.global_position):
			lived = true
			break
	_check(lived and bear.is_alive(), "the bear on it swam to the bank")
	var gone := false
	for k in 300:
		await _frames(4)
		if not RiverCrossing.reaches(self, HEAVY_AT, OVER_TO):
			gone = true
			break
	_check(gone, "the way over on foot is gone again")
	# The wall at the water's edge is back where the bridge stood.
	var w := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.9
	cs.shape = cap
	cs.position.y = 0.95
	w.add_child(cs)
	w.collision_layer = 0
	w.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_WATER_EDGE
	add_child(w)
	w.global_position = _ground(Vector3(BRIDGE_AT.x, 0, 505.0)) + Vector3.UP * 0.2
	for k in 30 * 12:
		w.velocity = Vector3(0, -9.0 if not w.is_on_floor() else 0.0, -4.0)
		w.move_and_slide()
		await get_tree().physics_frame
	_check(not RiverCrossing.wet(w.global_position), "a walker driven at the water where it stood stops at the water's edge (z %.0f)" % w.global_position.z)
	# Stock: 30 a match, and none once they are gone.
	commander.bridges_left = 0
	_check(commander.submit({"type": "bridge", "pos": BRIDGE_AT}) == 0, "with none left no bridge can be ordered")
	_acts += 1


func _check_stock_and_plans() -> void:
	_check(commander.bridges_left == 30, "30 bridges to start with: %d" % commander.bridges_left)
	var dry := FoldingBridge.plan(DRY_AT)
	_check(not dry.ok, "no bridge on dry land (%s)" % dry.reason)
	var wide := FoldingBridge.plan(WIDE_AT)
	_check(not wide.ok, "none where the lake's outlet comes in (%s)" % wide.reason)
	var ok := FoldingBridge.plan(BRIDGE_AT)
	_check(ok.ok, "one across the river at x %.0f (%.0f m)" % [BRIDGE_AT.x, ok.length])


# ---------------------------------------------------------------- the deployment video

## Every frame of the video is drawn: a smaller shadow map over a shorter reach, and the forest drawn out to
## VIDEO_REACH m (the drop is seen from close by; the haze hides the rest).
const VIDEO_REACH := 520.0


func _light_video() -> void:
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	for sun: DirectionalLight3D in level.find_children("*", "DirectionalLight3D", false, false):
		sun.directional_shadow_max_distance = 220.0
	for mmi: MultiMeshInstance3D in get_tree().get_nodes_in_group("flora_batches"):
		if mmi.visibility_range_end > VIDEO_REACH or mmi.visibility_range_end == 0.0:
			mmi.visibility_range_end = VIDEO_REACH
			mmi.visibility_range_end_margin = 40.0
	cam.far = VIDEO_REACH + 300.0
	controller.camera_rig.camera.far = VIDEO_REACH + 300.0


func _deploy_video() -> void:
	var rig := controller.camera_rig
	rig.camera.current = true
	rig.rotation.y = 0.35
	rig.pitch = deg_to_rad(-52.0)
	rig.zoom = 105.0
	rig._target_zoom = 105.0
	rig.focus(BRIDGE_AT + Vector3(24, 0, 34))
	_say("Folding bridge", "Shift+B: a preview of the bridge follows the cursor, snapped across the river")
	_cursor.visible = true
	_set_cursor(rig.camera.unproject_position(_ground(BRIDGE_AT + Vector3(40, 0, 62))))
	await _frames(20)
	_keycap.text = "Shift + B"
	_keycap.visible = true
	controller.toggle_bridge()
	await _frames(15)
	_keycap.visible = false
	# Along the river from the east, the preview sliding with the cursor, then back to the spot.
	var along := [BRIDGE_AT + Vector3(62, 0, 16), BRIDGE_AT + Vector3(30, 0, -4), BRIDGE_AT + Vector3(-14, 0, 4), BRIDGE_AT]
	var from := _cursor.position
	for p in along:
		var to := rig.camera.unproject_position(_ground(p))
		for f in 28:
			_set_cursor(from.lerp(to, smoothstep(0.0, 1.0, (f + 1) / 28.0)))
			await get_tree().process_frame
		from = to
	await _frames(18)
	_say("Folding bridge", "LMB: it's airdropped there (%d left)" % (commander.bridges_left - 1))
	_keycap.text = "LMB"
	_keycap.visible = true
	_click()
	bridge = commander.bridges[-1] if not commander.bridges.is_empty() else null
	await _frames(14)
	_keycap.visible = false
	_cursor.visible = false
	controller.visible = false
	# Over the water downstream, looking up the river at it: the spans fold about lines along the river.
	_labels(false)
	var river := RiverCrossing.nearest_river(Vector2(bridge.global_position.x, bridge.global_position.z))
	var d: Vector2 = river.dir
	var side := Vector2(-d.y, d.x)
	if side.y < 0.0:
		side = -side  # toward the south bank
	var c := bridge.global_position
	var eye := Vector3(c.x + d.x * 58.0 + side.x * 14.0, JungleLayout.WATER_Y + 7.0, c.z + d.y * 58.0 + side.y * 14.0)
	_say("", "")
	cam.current = true
	cam.fov = 60.0
	cam.global_position = eye
	_look_smooth = bridge._rig.global_position
	while bridge.state == FoldingBridge.State.DROPPING or bridge.state == FoldingBridge.State.BRAKING:
		_look_smooth = _look_smooth.lerp(bridge._rig.global_position, 0.3)
		cam.look_at(_look_smooth)
		if bridge.state == FoldingBridge.State.BRAKING:
			_say("Thrusters", "they light %d m up and brake it to a hover" % int(FoldingBridge.BRAKE_AT))
		await get_tree().process_frame
	_say("Unfolding", "the left span swings up and over, the right one down and round")
	var t := 0.0
	var close := Vector3(c.x + d.x * 44.0 + side.x * 20.0, JungleLayout.WATER_Y + 10.0, c.z + d.y * 44.0 + side.y * 20.0)
	while bridge.state == FoldingBridge.State.UNFOLDING or bridge.state == FoldingBridge.State.LANDING:
		t += get_process_delta_time()
		cam.global_position = eye.lerp(close, smoothstep(0.0, 6.5, t))
		_look_smooth = _look_smooth.lerp(bridge._rig.global_position + Vector3(0, -1.5, 0), 0.12)
		cam.look_at(_look_smooth)
		if bridge.state == FoldingBridge.State.LANDING:
			_say("Down onto the banks", "its ramps' tips on the ground both sides")
		await get_tree().process_frame
	for f in 30:
		_look_smooth = _look_smooth.lerp(bridge.global_position + Vector3(0, -1.0, 0), 0.1)
		cam.look_at(_look_smooth)
		await get_tree().process_frame
	# Up and round to see it all.
	var from_pos := cam.global_position
	var high := Vector3(c.x + d.x * 46.0 + side.x * 48.0, c.y + 30.0, c.z + d.y * 46.0 + side.y * 48.0)
	for f in 60:
		cam.global_position = from_pos.lerp(high, smoothstep(0.0, 1.0, (f + 1) / 60.0))
		_look_smooth = _look_smooth.lerp(bridge.global_position, 0.1)
		cam.look_at(_look_smooth)
		await get_tree().process_frame
	_say("Across", "everyone can cross it now · %d bridges left" % commander.bridges_left)
	await _frames(45)
	# The RTS view again.
	_labels(true)
	rig.rotation.y = 0.35
	rig.zoom = 90.0
	rig._target_zoom = 90.0
	rig.focus(bridge.global_position + Vector3(8, 0, 12))
	rig.camera.current = true
	controller.visible = true
	await _frames(45)


# ---------------------------------------------------------------- helpers

func _unit(type: String, at: Vector3, yaw := 0.0) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = _ground(at) + Vector3.UP * (UnitTypes.FLY_HEIGHT if type == "talon" else 0.3)
	u.rotation.y = yaw
	_no_cull(u)
	return u


## Stills: the run goes on for thousands of frames between two that are drawn, and the renderer's bounds of a
## skinned model can be left behind where it last was drawn (then it is culled wherever it has got to). Bounds of
## their own that go with it.
func _no_cull(node: Node) -> void:
	if shots_dir == "":
		return
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mi.custom_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))


## The ground under `p`, or the water's surface over it.
func _floor(p: Vector3) -> float:
	return maxf(LevelBuilder.ground_height(p), JungleLayout.WATER_Y)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, LevelBuilder.ground_height(p), p.z) if p.y == 0.0 else p


func _ids(list: Array) -> Array:
	return list.map(func(u): return u.unit_id)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("check ok: " if ok else "CHECK FAILED: ") + what)
	_failed = _failed or not ok


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A still from SHOT_CAMS (following `follow`'s position by the offset between the camera and the look-at there).
func _shot(name: String, follow: Node3D = null) -> void:
	var c: Array = SHOT_CAMS[name]
	var eye: Vector3 = c[0]
	var at: Vector3 = c[1]
	if not follow:
		eye.y += _floor(eye)
		at.y += _floor(at)
	if follow:
		var off := eye - at
		at = follow.global_position + Vector3.UP * 0.5
		eye = at + off
	cam.fov = c[2]
	await _shoot(name, eye, at)


## A still close by `node`: the camera `off` from it in its own frame.
func _shot_close(name: String, node: Node3D, off: Vector3, fov: float) -> void:
	var at := node.global_position + Vector3.UP * 1.5
	var b := Basis(Vector3.UP, node.global_rotation.y)
	cam.fov = fov
	await _shoot(name, at + b * off, at)


func _shoot(name: String, eye: Vector3, at: Vector3) -> void:
	_labels(false)
	controller.visible = false
	cam.current = true
	cam.global_position = eye
	cam.look_at(at)
	await _snap(name)


func _snap(name: String) -> void:
	if not only.is_empty() and name not in only:
		controller.visible = true
		return
	# A few frames drawn for the view to settle (the shadows, the particles' first puffs).
	RenderingServer.render_loop_enabled = true
	var t0 := Time.get_ticks_msec()
	for k in 3:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join(name + ".png"))
	print("shot: %s (%d ms)" % [name, Time.get_ticks_msec() - t0])
	_labels(true)
	RenderingServer.render_loop_enabled = video
	controller.visible = true
	only.erase(name)
	if only.is_empty() and _only_given:
		print("BRIDGE SHOWCASE stills done")
		RenderingServer.render_loop_enabled = true
		get_tree().quit()


## The map's names over its sites (the RTS view's): off for the views from close by.
func _labels(on: bool) -> void:
	for l: Label3D in level.find_children("*", "Label3D", true, false):
		l.visible = on


func _set_cursor(p: Vector2) -> void:
	_cursor.position = p
	get_viewport().warp_mouse(p)
	var ev := InputEventMouseMotion.new()
	ev.position = p
	controller._unhandled_input(ev)


func _click() -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = _cursor.position
		controller._unhandled_input(ev)


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
	_caption.position.y = 24
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	layer.add_child(_caption)
	_keycap = UIKit.label("", 30, Color(1.0, 0.85, 0.3))
	_keycap.add_theme_color_override("font_outline_color", Color.BLACK)
	_keycap.add_theme_constant_override("outline_size", 8)
	_keycap.position = Vector2(40, 300)
	_keycap.visible = false
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_keycap)
	# Movie Maker doesn't record the system cursor: draw one.
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
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
