extends Node3D
## Bear Riflemen in the water on the Jungle Keep's main river (the bridge showcase's stretch of it), on the real
## map: the swim (a dog paddle, its head out of the water, its LMG slung across its back: tools/gltf/swim_bear.py)
## and the dive (AttackerUnit.start_dive: F out swimming), with a defender rifleman on the north bank.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/bear_showcase.tscn -- --test
##       prints and checks: BEAR SHOWCASE PASS / FAIL
##   godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/bear_showcase.tscn -- --shots=DIR [--only=a,b]
##       the same run, with stills (.png) in DIR on the way (--only: just those, and it stops after the last):
##   bear_swim         close by it out in the river: its head over the water, its fore paws churning it
##   bear_swim_side    from its side: the body low in the water, the gun on its back
##   bear_swim_back    from behind and above: the LMG slung across its backpack
##   bear_shot_at      the rifleman on the bank firing at it (it can't fire back out there)
##   bear_dive         F: it goes under, the water closing over it
##   bear_under        under the water, from close by: its silhouette, all the attacking player sees of it
##   bear_under_rts    the RTS view: the silhouette under the water, the rifleman on the bank not firing
##   bear_under_defender  the same view on the defender's side: nothing there
##   bear_hit_under    a round fired into the water where it is: it hits it
##   bear_up           up again after 10 s, the rifleman firing again
##   godot --path game --resolution 1280x720 --write-movie bear.avi --fixed-fps 30 res://scenes/dev/bear_showcase.tscn -- --video
##       the swim and the dive as a video.
##
## The checks: no dive on dry land; out in the water it plays its Swim clip, its gun slung on its back (the muzzle
## up over its head), its head out of the water; the rifleman picks it out and hits it; F (the attacker's key) dives
## it: down under its swim depth, the Dive clip, its silhouette on the attacking player's screen (nothing and no
## health bar on the defender's), the rifleman loses sight of it (no line of sight, no target, no more hits while
## it is under), but a round fired into the water where it is hits it; it is up again after 10 s, the Swim clip,
## the rifleman hits it again; no dive again until the cooldown is over; a second bear the CPU's way: shot at out
## swimming, it dives (AIAttacker._bear_dives); on the north bank it runs with its gun in its hands again.

## The river (main) here: where the bears set off on the south bank, where they go on the north bank.
const SOUTH := Vector3(-322.0, 0.0, 506.0)
const NORTH := Vector3(-322.0, 0.0, 424.0)
## The defender rifleman at the top of the north bank (3.6 m over the water), in reach of the river's middle.
const GUARD_AT := Vector3(-323.0, 0.0, 432.0)

var test := false
var video := false
var shots_dir := ""
var only: Array = []
var _only_given := false
var level: JungleLevel
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var bear: AttackerUnit
var bear2: AttackerUnit
var guard: DefenderSoldier
var _failed := false
var _acts := 0
var _caption: Label
var _keycap: Label


func _ready() -> void:
	seed(11)
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
		RenderingServer.render_loop_enabled = false  # nothing to see while the map loads
	GameConfig.map = "jungle"
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	level = JungleLevel.new()
	add_child(level)
	level.build()
	# Staged: the posts and the AA turrets hold fire.
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
	cam.near = 0.05
	cam.far = 3000.0
	add_child(cam)
	_build_overlay()
	for l in controller.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("LMB select"):
			l.visible = false
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	RenderingServer.render_loop_enabled = video
	await _frames(10)
	# The swim links go into the navigation map on its own thread: until they are in, a path ends on the bank.
	var linked := await _until(func(): return RiverCrossing.reaches(self, SOUTH, NORTH, 1 | RiverCrossing.NAV_SWIMMERS), 30.0)
	if not linked:
		print("CHECK FAILED: no swim path over the river")
		_failed = true
	if video:
		_light_video()
		await _video_run()
		RenderingServer.render_loop_enabled = true
		get_tree().quit()
		return
	await _swim_and_dive()
	_check(_acts == 1, "the whole run ran to the end (%d)" % _acts)
	print("BEAR SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------- the run

func _swim_and_dive() -> void:
	bear = _unit("rifleman", SOUTH)
	bear2 = _unit("rifleman", SOUTH + Vector3(12.0, 0.0, 1.0))
	# Tough enough to be shot at the whole way over, and slower in the water than they are (the river is narrow
	# here: the whole dive out in it, and some swimming after).
	for b in [bear, bear2]:
		b.stats = b.stats.duplicate()
		b.stats.hp = 500.0
		b.hp = 500.0
		b.stats.swim_speed = 1.5
	guard = _guard(GUARD_AT, SOUTH)
	_check(LevelBuilder.ground_height(GUARD_AT) > JungleLayout.WATER_Y + 1.0,
			"the rifleman stands up on the bank (%.1f m over the water)" % (LevelBuilder.ground_height(GUARD_AT) - JungleLayout.WATER_Y))
	await _frames(20)
	_check(commander.submit({"type": "dive", "units": _ids([bear, bear2])}) == 0 and not bear.is_submerged(),
			"no dive on dry land")
	commander.submit({"type": "move", "units": [bear.unit_id], "pos": NORTH, "attack": false})
	commander.submit({"type": "move", "units": [bear2.unit_id], "pos": NORTH + Vector3(12, 0, 0), "attack": false})
	# Out in the deep water.
	var ok := await _until(func(): return _deep(bear) and _deep(bear2) and bear.global_position.z < 488.0, 60.0)
	_check(ok, "both bears swim out into the river (z %.0f)" % bear.global_position.z)
	await _frames(40)
	var head := _bone(bear, "mixamorig_Head")
	var top := _bone(bear, "mixamorig_HeadTop_End")
	var muzzle: Vector3 = bear._gun_muzzle.global_position
	_check(bear._anim.current_animation == "Swim", "out in the water it swims (its Swim clip: %s)" % bear._anim.current_animation)
	_check(muzzle.y > head.y + 0.2, "its gun slung on its back, the muzzle up over its head (%.2f over the head)" % (muzzle.y - head.y))
	_check(head.y > JungleLayout.WATER_Y + 0.1 and top.y > JungleLayout.WATER_Y + 0.25,
			"its head out of the water (%.2f m, the top %.2f m over it)" % [head.y - JungleLayout.WATER_Y, top.y - JungleLayout.WATER_Y])
	if shots_dir != "":
		await _shot_at("bear_swim", bear, Vector3(1.8, 1.9, -3.0), Vector3(0.0, 0.85, -0.3), 50.0)
		await _shot_at("bear_swim_side", bear, Vector3(3.8, 1.6, -0.4), Vector3(0.0, 0.8, -0.2), 46.0)
		await _shot_at("bear_swim_back", bear, Vector3(-1.6, 2.6, 3.4), Vector3(0.0, 0.7, -0.4), 50.0)
	# The CPU's way: a bear shot at out swimming dives.
	var ai := AIAttacker.new()
	ai.commander = commander
	bear2.take_damage(5.0, GameConfig.TEAM_DEFENDER)
	ai._bear_dives()
	_check(bear2.is_submerged() and not bear.is_submerged(), "the CPU's bear shot at out swimming dives (and the other one doesn't)")
	ai.free()
	# The rifleman on the bank is let loose once it is in his reach: he picks the bear out and hits it.
	await _until(func(): return guard.global_position.distance_to(bear.global_position) < DefenderSoldier.AI_RANGE - 3.0, 20.0)
	guard.set_process(true)
	guard.set_physics_process(true)
	var hp0 := bear.hp
	ok = await _until(func(): return bear.hp < hp0, 15.0)
	_check(ok and guard._target == bear, "the rifleman on the bank picks it out and hits it (%d hp off)" % int(hp0 - bear.hp))
	if shots_dir != "":
		await _until(func(): return guard._fire_cd > DefenderSoldier.AI_FIRE_INTERVAL * 0.75, 2.0)
		# Over the rifleman's shoulder at it.
		var to := bear.global_position - guard.global_position
		to.y = 0.0
		var d := to.normalized()
		var side := d.cross(Vector3.UP)
		await _shoot("bear_shot_at", guard.global_position - d * 3.0 + side * 0.9 + Vector3.UP * 2.0, bear.global_position + Vector3(0, 0.3, 0), 42.0)
	# F (the attacker's key, the bear selected): it dives.
	_select([bear])
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.pressed = true
	controller._unhandled_input(ev)
	_check(bear.is_submerged() and bear.dive_cd > 0.0, "F: it dives")
	if shots_dir != "":
		await _frames(10)
		await _shot_at("bear_dive", bear, Vector3(2.6, 1.4, -4.0), Vector3(0.0, 0.2, -0.6), 50.0)
	await _frames(int(1.6 * 60))
	var under: float = JungleLayout.WATER_Y - bear.global_position.y
	_check(under > bear.stats.swim_sink + 1.0, "down under the water (its feet %.1f m under, %.1f deeper than it swims)" % [under, under - bear.stats.swim_sink])
	_check(bear._anim.current_animation == "Dive", "the Dive stroke (%s)" % bear._anim.current_animation)
	_check(bear.silhouetted() and bear.model_meshes().all(func(mi): return mi.material_overlay != null),
			"the attacking player sees its silhouette")
	var eye := guard.global_position + Vector3.UP * 1.6
	_check(not Combat.has_line_of_sight(guard, eye, Combat.aim_point(bear), bear), "the rifleman has no line of sight to it")
	await _frames(60)
	_check(guard._target != bear, "and has lost it (%s)" % (guard._target.stats.name if guard._target else "no target"))
	if shots_dir != "":
		await _shot_at("bear_under", bear, Vector3(2.4, 3.6, -4.2), Vector3(0.0, 0.0, -0.6), 52.0)
		await _rts_shot("bear_under_rts")
		GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
		await _frames(2)
		await _rts_shot("bear_under_defender", false)
		GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
		await _frames(2)
	# On the defender's side nothing shows: no silhouette, no health bar.
	GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
	await _frames(2)
	_check(bear.hidden_under() and not bear.silhouetted() and not bear._hp_bar.visible and bear.model_meshes().all(func(mi): return mi.material_overlay == null),
			"on the defender's side nothing shows of it (no silhouette, no health bar)")
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	await _frames(2)
	# Nobody shoots at it down there, but a round fired into the water where it is hits it.
	var hp1 := bear.hp
	await _frames(120)
	_check(is_equal_approx(bear.hp, hp1), "no rounds aimed at it while it is under (%d hp)" % int(bear.hp))
	var above := bear.global_position + Vector3(1.5, 5.0, 0.8)
	var hit := Combat.fire_hitscan(guard, above, bear.global_position + Vector3.UP * 0.4, 0.0, 20.0, GameConfig.TEAM_DEFENDER)
	_check(bear.hp < hp1 - 19.0, "a round fired into the water where it is hits it (%d hp off: %s)" % [int(hp1 - bear.hp), hit])
	if shots_dir != "" and (only.is_empty() or "bear_hit_under" in only):
		# Rounds into the water where it is, the moment they are fired (their tracers fade fast).
		# From the side of their way, a stream of rounds from the bank into the water over it, some in the air.
		var mid := (guard.global_position + bear.global_position) * 0.5
		var along := (bear.global_position - guard.global_position)
		along.y = 0.0
		var across := along.normalized().cross(Vector3.UP)
		cam.fov = 58.0
		cam.current = true
		_labels(false)
		controller.visible = false
		cam.global_position = mid + across * 22.0 + Vector3.UP * 7.0
		cam.look_at(mid.lerp(bear.global_position, 0.25))
		for k in 8:
			Combat.fire_hitscan(guard, guard.global_position + Vector3(0.1 * (k % 3), 1.6, 0.0), bear.global_position + Vector3(0.25 * (k % 4) - 0.4, 0.4, 0.0), 0.0, 0.5, GameConfig.TEAM_DEFENDER, 1.0, [guard.get_rid()])
			await get_tree().process_frame
		await _snap("bear_hit_under", 1)
	# Up again after dive_time s: the Swim clip, the rifleman hits it again.
	ok = await _until(func(): return not bear.is_submerged(), bear.stats.dive_time + 1.0)
	_check(ok, "up again after %.0f s" % bear.stats.dive_time)
	await _frames(int(1.6 * 60))
	_check(bear._anim.current_animation == "Swim" and not bear.silhouetted() and _bone(bear, "mixamorig_Head").y > JungleLayout.WATER_Y,
			"swimming at the surface again, its head out (%s)" % bear._anim.current_animation)
	_check(commander.submit({"type": "dive", "units": [bear.unit_id]}) == 0 and bear.dive_cd > 0.0,
			"no dive again until the cooldown is over (%.0f s)" % bear.dive_cd)
	var hp2 := bear.hp
	ok = await _until(func(): return bear.hp < hp2, 8.0)
	_check(ok, "the rifleman hits it again (%d hp off)" % int(hp2 - bear.hp))
	if shots_dir != "":
		await _shot_at("bear_up", bear, Vector3(2.6, 1.0, -4.2), Vector3(0.0, 0.8, -0.4), 50.0)
	# Over on the north bank, its gun in its hands again.
	guard.set_process(false)
	guard.set_physics_process(false)
	ok = await _until(func(): return not bear.is_swimming() and bear.global_position.z < 450.0 and bear._anim.current_animation in ["Running", "Idle"], 60.0)
	await _frames(40)
	var m2: Vector3 = bear._gun_muzzle.global_position
	_check(ok and m2.y < _bone(bear, "mixamorig_Head").y, "on the north bank its gun is in its hands again (%s)" % bear._anim.current_animation)
	_acts += 1


# ---------------------------------------------------------------- the video

## The camera's place by the bear (in its frame, turned with it) and where it looks, eased toward each frame;
## the video's steps move them (_to).
var _eye := Vector3(2.4, 1.9, -3.8)
var _at := Vector3(0.0, 0.9, -0.5)
var _look := Vector3.ZERO


func _process(_delta: float) -> void:
	if video and is_instance_valid(bear):
		var b := Basis(Vector3.UP, bear.global_rotation.y)
		var want := bear.global_position + b * _eye
		cam.global_position = cam.global_position.lerp(want, 0.07) if cam.global_position.distance_to(want) < 25.0 else want
		var look := bear.global_position + b * _at
		_look = _look.lerp(look, 0.1) if _look.distance_to(look) < 25.0 else look
		cam.look_at(_look)


## Over `frames` frames the camera goes to `eye`, looking at `at` (both by the bear, in its frame).
func _to(eye: Vector3, at: Vector3, frames: int) -> void:
	var e0 := _eye
	var a0 := _at
	for f in frames:
		var k := smoothstep(0.0, 1.0, (f + 1.0) / frames)
		_eye = e0.lerp(eye, k)
		_at = a0.lerp(at, k)
		await get_tree().process_frame


func _hold(frames: int) -> void:
	for f in frames:
		await get_tree().process_frame


## Close by a bear running down the bank and swimming out; shot at from the north bank; F, the dive, seen from
## over the water (its silhouette); a few rounds into the water where it is; up again.
func _video_run() -> void:
	bear = _unit("rifleman", SOUTH)
	bear.stats = bear.stats.duplicate()
	bear.stats.hp = 900.0
	bear.hp = 900.0
	bear.stats.swim_speed = 1.6
	guard = _guard(GUARD_AT, SOUTH)
	cam.current = true
	cam.fov = 50.0
	await _frames(10)
	commander.submit({"type": "move", "units": [bear.unit_id], "pos": NORTH, "attack": false})
	_say("Bear Rifleman", "swims like a bear: a dog paddle, its head up, its LMG slung across its back")
	await _hold(30)
	await _until(func(): return _deep(bear), 30.0)
	await _to(Vector3(1.9, 1.8, -3.0), Vector3(0.0, 0.85, -0.3), 75)
	await _to(Vector3(3.8, 1.6, -0.4), Vector3(0.0, 0.8, -0.2), 60)
	_say("Shot at", "out in the water it can't fire back")
	guard.set_process(true)
	guard.set_physics_process(true)
	await _to(Vector3(3.4, 1.8, -4.6), Vector3(0.0, 0.6, -0.6), 60)
	_say("F: dive", "under the water for %.0f s, out of the defenders' sight" % bear.stats.dive_time)
	_keycap.text = "F"
	_keycap.visible = true
	_select([bear])
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.pressed = true
	controller._unhandled_input(ev)
	await _hold(25)
	_keycap.visible = false
	await _to(Vector3(4.2, 6.2, -6.4), Vector3(0.0, -0.6, -0.8), 70)
	_say("Under the water", "the attacking player sees its silhouette · the rifleman has lost it")
	await _hold(80)
	_say("Under the water", "but a round that goes in where it is still hits it")
	for k in 4:
		Combat.fire_hitscan(guard, guard.global_position + Vector3(0.2 * k, 1.6, 0.0), bear.global_position + Vector3(0.4 * k - 0.6, 0.5, 0.0),
				0.0, 8.0, GameConfig.TEAM_DEFENDER, 1.0, [guard.get_rid()])
		await _hold(12)
	await _until(func(): return not bear.is_submerged(), 6.0)
	_say("Up again", "after %.0f s: in sight, and shot at, again" % bear.stats.dive_time)
	await _to(Vector3(2.2, 1.8, -3.4), Vector3(0.0, 0.85, -0.4), 75)
	await _hold(60)
	_say("", "")


func _light_video() -> void:
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	for sun: DirectionalLight3D in level.find_children("*", "DirectionalLight3D", false, false):
		sun.directional_shadow_max_distance = 120.0
	for mmi: MultiMeshInstance3D in get_tree().get_nodes_in_group("flora_batches"):
		if mmi.visibility_range_end > 400.0 or mmi.visibility_range_end == 0.0:
			mmi.visibility_range_end = 400.0
			mmi.visibility_range_end_margin = 40.0
	cam.far = 700.0
	_labels(false)
	controller.visible = false


# ---------------------------------------------------------------- helpers

func _unit(type: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = Vector3(at.x, LevelBuilder.ground_height(at) + 0.3, at.z)
	u.rotation.y = 0.0
	if shots_dir != "":
		for mi: MeshInstance3D in u.find_children("*", "MeshInstance3D", true, false):
			mi.custom_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	return u


## A rifleman of the garrison standing on the bank, looking toward `look` (he doesn't fight until let loose).
func _guard(p: Vector3, look: Vector3) -> DefenderSoldier:
	var s := DefenderSoldier.new()
	s.model_path = LevelBuilder.DEFENDER_MODELS[1]
	s.station_name = "Field rifleman"
	var at := Vector3(p.x, LevelBuilder.ground_height(p) + 0.1, p.z)
	var to := look - at
	s.transform = Transform3D(Basis.looking_at(Vector3(to.x, 0.0, to.z)), at)
	add_child(s)
	if shots_dir != "":
		# Stills: its skinned model's bounds go with it (they are left behind while nothing is drawn), and the
		# undergrowth round it is cleared for the view over its shoulder.
		for mi: MeshInstance3D in s.find_children("*", "MeshInstance3D", true, false):
			mi.custom_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		if JungleFlora.current:
			JungleFlora.current.clear_footprint(Transform3D(Basis.IDENTITY, at + Vector3(0, 0, -3)), Vector2(5.0, 6.0))
	s.became_unavailable.connect(func(_st): s.set("_respawn_cd", 1e9))
	s.set_process(false)
	s.set_physics_process(false)
	return s


## Out in the deep water, swimming.
func _deep(u: AttackerUnit) -> bool:
	return u.is_swimming() and u.in_water() and RiverCrossing.ground(Vector2(u.global_position.x, u.global_position.z)) < JungleLayout.WATER_Y - 2.5


## A bone of a unit's model (world; named as Godot imports them: mixamorig_Head).
func _bone(u: AttackerUnit, name: String) -> Vector3:
	for skel: Skeleton3D in u._model.find_children("*", "Skeleton3D", true, false):
		var b := skel.find_bone(name)
		if b >= 0:
			return (skel.global_transform * skel.get_bone_global_pose(b)).origin
	return Vector3.INF


func _select(list: Array) -> void:
	controller._set_selection(list.duplicate())


## Waits (physics frames) until `cond` holds, `seconds` at most; true if it did.
func _until(cond: Callable, seconds: float) -> bool:
	for k in int(seconds * 60.0):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _ids(list: Array) -> Array:
	return list.map(func(u): return u.unit_id)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("check ok: " if ok else "CHECK FAILED: ") + what)
	_failed = _failed or not ok


## A still of `node`: the camera at `eye`, looking at `at` (both in its own frame, turned with it).
func _shot_at(name: String, node: Node3D, eye: Vector3, at: Vector3, fov: float) -> void:
	var b := Basis(Vector3.UP, node.global_rotation.y)
	await _shoot(name, node.global_position + b * eye, node.global_position + b * at, fov)


func _shoot(name: String, eye: Vector3, at: Vector3, fov: float) -> void:
	if not only.is_empty() and name not in only:
		return
	_labels(false)
	controller.visible = false
	cam.current = true
	cam.fov = fov
	cam.global_position = eye
	cam.look_at(at)
	await _snap(name)


## The RTS view over the bear: the commander's camera, the HUD up.
func _rts_shot(name: String, hud := true) -> void:
	if not only.is_empty() and name not in only:
		return
	var rig := controller.camera_rig
	_labels(true)
	cam.current = false
	rig.camera.current = true
	controller.visible = hud
	# From the east, over the river (the banks' trees out of the way).
	rig.rotation.y = 1.45
	rig.pitch = deg_to_rad(-56.0)
	rig.zoom = 28.0
	rig._target_zoom = 28.0
	rig.focus(bear.global_position)
	_select([bear])
	await _frames(3)
	await _snap(name)
	rig.camera.current = false
	cam.current = true


func _snap(name: String, settle := 3) -> void:
	RenderingServer.render_loop_enabled = true
	var t0 := Time.get_ticks_msec()
	for k in settle:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))
	print("shot: %s (%d ms)" % [name, Time.get_ticks_msec() - t0])
	RenderingServer.render_loop_enabled = video
	only.erase(name)
	if only.is_empty() and _only_given:
		print("BEAR SHOWCASE stills done")
		RenderingServer.render_loop_enabled = true
		get_tree().quit()


## The map's names over its sites (the RTS view's): off for the views from close by.
func _labels(on: bool) -> void:
	for l: Label3D in level.find_children("*", "Label3D", true, false):
		l.visible = on


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
