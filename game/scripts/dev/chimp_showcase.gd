extends Node3D
## Night Ops Chimps swinging through the Jungle Keep's trees (AttackerUnit._swing_tick, the Swing clip baked by
## tools/gltf/swing_chimp.py), on the real map: a chimp sent from the forest south of the Keep out into its clearing,
## and another sent a little way into the forest, where it stops.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/chimp_showcase.tscn -- --test
##       prints and checks: CHIMP SHOWCASE PASS / FAIL
##   godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/chimp_showcase.tscn -- --shots=DIR [--only=a,b]
##       the same run, with stills (.png) in DIR on the way (--only: just those, and it stops after the last):
##   chimp_standing    the chimp standing in the forest, on the ground
##   chimp_leap        sent off: leaping up into the trees
##   chimp_swing       swinging through them, from its side
##   chimp_swing_front from ahead of it: hanging from a hold, the other hand reaching on
##   chimp_drop        out of the trees: dropping back down to the ground
##   chimp_run         in the clearing: running on the ground, slower
##
## The checks: standing in the forest it is on the ground; sent off through it, it goes up into the trees within a
## second (lifted CANOPY_LOW m and more), plays its Swing clip and goes at its forest speed; up there its hitbox is
## up with it (a round aimed at it there hits it) and so is where the defenders aim; out of the trees it drops back
## down, plays its Running clip and goes at its speed on open ground; the second chimp, stopped in the forest, comes
## down to the ground.

## Where to look for the way: from the forest between the Keep's clearing (JungleLayout.CLEARING_R, the jungle
## closing in CLEARING_EDGE further out) and the main river south of it, north into the clearing.
const FROM_Z := [400.0, 380.0, 360.0]
const TO_Z := 220.0
const XS := [-100.0, 100.0, -150.0, 150.0, -60.0, 60.0, -200.0, 200.0]

var test := false
var shots_dir := ""
var only: Array = []
var _only_given := false
var level: JungleLevel
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var _failed := false
var _acts := 0


func _ready() -> void:
	seed(5)
	var args := OS.get_cmdline_user_args()
	test = "--test" in args
	for arg in args:
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			only = Array(arg.get_slice("=", 1).split(","))
			_only_given = true
	if not test and shots_dir == "":
		test = DisplayServer.get_name() == "headless"
	if shots_dir != "":
		RenderingServer.render_loop_enabled = false  # nothing to see while the map loads
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
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	RenderingServer.render_loop_enabled = false
	await _frames(10)
	await _through_the_trees()
	await _stopping()
	_check(_acts == 2, "the whole run ran to the end (%d)" % _acts)
	print("CHIMP SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------- the run

## A way from deep in the forest south of the Keep straight out into its clearing, on foot (none over water).
func _way() -> Array:
	for z in FROM_Z:
		for x in XS:
			var from := Vector3(x, 0.0, z)
			var to := Vector3(x, 0.0, TO_Z)
			var forest := true
			for k in 6:
				forest = forest and LevelBuilder.in_forest(from + Vector3(0.0, 0.0, -10.0 * k))
			if forest and not LevelBuilder.in_forest(to) and not RiverCrossing.wet(from) and RiverCrossing.reaches(self, from, to):
				return [from, to]
	return []


func _through_the_trees() -> void:
	var way := _way()
	_check(not way.is_empty(), "a way from the forest out into the Keep's clearing")
	if way.is_empty():
		return
	var chimp := _unit("chimp", way[0])
	await _frames(30)
	_check(not chimp.is_swinging() and chimp.swing_lift() == 0.0 and chimp._anim.current_animation == "Idle",
			"standing in the forest it is on the ground (lifted %.2f m, %s)" % [chimp.swing_lift(), chimp._anim.current_animation])
	if shots_dir != "":
		await _shot_at("chimp_standing", chimp, Vector3(3.5, 1.6, -3.0), Vector3(0, 0.9, 0), 45.0)
	commander.submit({"type": "move", "units": [chimp.unit_id], "pos": way[1], "attack": false})
	# Up into the trees within a second.
	var up_at := -1
	var high := 0.0
	var swung := false
	var forest_speed := 0.0
	var aim_up := INF
	var hit_up := false
	var left_at := -1
	var down_ok := false
	var run_speed := 0.0
	var leap_shot := false
	for frame in 30 * 60:
		await get_tree().physics_frame
		var t := frame / float(Engine.physics_ticks_per_second)
		var flat := Vector2(chimp.velocity.x, chimp.velocity.z).length()
		var in_forest := LevelBuilder.in_forest(chimp.global_position)
		if chimp.is_swinging() and up_at < 0:
			up_at = frame
		if in_forest and chimp.is_swinging():
			high = maxf(high, chimp.swing_lift())
			swung = swung or chimp._anim.current_animation == "Swing"
			forest_speed = maxf(forest_speed, flat)
			if chimp.swing_lift() > 1.5 and not hit_up:
				aim_up = minf(aim_up, chimp.get_aim_point().y - chimp.global_position.y)
				hit_up = _hits(chimp)
		if shots_dir != "":
			if not leap_shot and chimp._aloft > 0.3:
				leap_shot = true
				await _shot_at("chimp_leap", chimp, Vector3(4.0, 2.0, -1.0), Vector3(0, 1.8, 0), 45.0)
			elif not _taken.has("chimp_swing") and chimp.swing_lift() > 1.5 and t > 3.0:
				_taken["chimp_swing"] = true
				await _shot_at("chimp_swing", chimp, Vector3(6.0, chimp.swing_lift() + 1.2, 0.5), Vector3(0, chimp.swing_lift() + 1.5, 0), 45.0)
			elif not _taken.has("chimp_swing_front") and chimp.swing_lift() > 1.5 and t > 4.0:
				_taken["chimp_swing_front"] = true
				await _shot_at("chimp_swing_front", chimp, Vector3(2.5, chimp.swing_lift() + 1.2, -6.0), Vector3(0, chimp.swing_lift() + 1.6, 0), 45.0)
		# Out of the trees for good (not a gap in them: it keeps up through a short one).
		if in_forest:
			left_at = -1
			down_ok = false
			run_speed = 0.0
		elif up_at >= 0 and left_at < 0:
			left_at = frame
		if left_at >= 0:
			if shots_dir != "" and not _taken.has("chimp_drop") and chimp._aloft > 0.2 and chimp._aloft < 0.7:
				_taken["chimp_drop"] = true
				await _shot_at("chimp_drop", chimp, Vector3(5.0, 2.0, -2.0), Vector3(0, 1.6, 0), 45.0)
			if frame - left_at > Engine.physics_ticks_per_second * 1.5 and flat > 0.5:
				down_ok = down_ok or (chimp.swing_lift() == 0.0 and not chimp.is_swinging() and chimp._anim.current_animation == "Running")
				run_speed = maxf(run_speed, flat)
				if shots_dir != "" and not _taken.has("chimp_run"):
					_taken["chimp_run"] = true
					await _shot_at("chimp_run", chimp, Vector3(3.5, 1.4, -3.5), Vector3(0, 0.9, 0), 45.0)
		if left_at >= 0 and frame - left_at > Engine.physics_ticks_per_second * 3:
			break
	var speed: float = chimp.stats.speed
	_check(up_at >= 0 and up_at <= Engine.physics_ticks_per_second, "sent off through the forest it goes up into the trees within a second (%.2f s)" % (up_at / float(Engine.physics_ticks_per_second)))
	_check(high >= AttackerUnit.CANOPY_LOW - chimp.stats.swing_hold - 0.05,
			"up under the canopy (lifted %.1f m: its holds %.1f m over the ground)" % [high, high + chimp.stats.swing_hold])
	_check(swung, "swinging from branch to branch (its Swing clip)")
	_check(absf(forest_speed - speed * chimp.stats.forest_speed) < 1.0,
			"at its forest speed (%.1f m/s, %.1f on open ground)" % [forest_speed, speed])
	_check(aim_up > 2.0, "the defenders aim at it up there (%.1f m over its feet)" % aim_up)
	_check(hit_up, "a round aimed at it up in the trees hits it")
	_check(left_at >= 0, "it came out of the trees")
	_check(down_ok, "out of the trees it drops back down and runs on the ground (its Running clip)")
	_check(run_speed > 0.0 and run_speed < speed + 0.5, "slower out there (%.1f m/s)" % run_speed)
	commander.units.erase(chimp.unit_id)
	chimp.queue_free()
	_acts += 1


## Stopped in the forest, it comes down out of the trees.
func _stopping() -> void:
	var way := _way()
	if way.is_empty():
		return
	var chimp := _unit("chimp", way[0] + Vector3(4.0, 0.0, 0.0))
	await _frames(10)
	commander.submit({"type": "move", "units": [chimp.unit_id], "pos": way[0] + Vector3(4.0, 0.0, -30.0), "attack": false})
	var went_up := await _until(func(): return chimp.is_swinging(), 3.0)
	_check(went_up, "a second chimp sent a little way into the forest goes up into the trees")
	var arrived := await _until(func(): return chimp.order.type == "idle" and Vector2(chimp.velocity.x, chimp.velocity.z).length() < 0.3, 15.0)
	_check(arrived, "it gets there")
	await _frames(30)
	_check(chimp.swing_lift() == 0.0 and not chimp.is_swinging() and chimp._anim.current_animation == "Idle",
			"stopped there it comes down to the ground (lifted %.2f m, %s)" % [chimp.swing_lift(), chimp._anim.current_animation])
	_acts += 1


## True if a round fired across at where the defenders aim at `u` hits it.
func _hits(u: AttackerUnit) -> bool:
	var at := u.get_aim_point()
	var side := u.global_basis.x
	var q := PhysicsRayQueryParameters3D.create(at + side * 6.0, at - side * 6.0, GameConfig.LAYER_ATTACKERS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and Combat.find_damageable(hit.collider) == u


# ---------------------------------------------------------------- helpers

var _taken := {}


func _unit(type: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = Vector3(at.x, LevelBuilder.ground_height(at) + 0.3, at.z)
	u.rotation.y = 0.0
	if shots_dir != "":
		for mi: MeshInstance3D in u.find_children("*", "MeshInstance3D", true, false):
			mi.custom_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	return u


func _until(cond: Callable, seconds: float) -> bool:
	for k in int(seconds * Engine.physics_ticks_per_second):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("check ok: " if ok else "CHECK FAILED: ") + what)
	_failed = _failed or not ok


## A still of `node`: the camera at `eye`, looking at `at` (both in its own frame, turned with it).
func _shot_at(name: String, node: Node3D, eye: Vector3, at: Vector3, fov: float) -> void:
	if not only.is_empty() and name not in only:
		return
	var b := Basis(Vector3.UP, node.global_rotation.y)
	for l: Label3D in level.find_children("*", "Label3D", true, false):
		l.visible = false
	controller.visible = false
	cam.current = true
	cam.fov = fov
	cam.global_position = node.global_position + b * eye
	cam.look_at(node.global_position + b * at)
	RenderingServer.render_loop_enabled = true
	for k in 3:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))
	print("shot: %s" % name)
	RenderingServer.render_loop_enabled = false
	only.erase(name)
	if only.is_empty() and _only_given:
		print("CHIMP SHOWCASE stills done")
		RenderingServer.render_loop_enabled = true
		get_tree().quit()
