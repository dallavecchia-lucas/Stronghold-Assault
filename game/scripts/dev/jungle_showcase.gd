extends Node3D
## The Jungle Keep map (JungleLevel): checks its navmesh, and takes stills round it.
##
##   godot --path game --headless res://scenes/dev/jungle_showcase.tscn
##       checks: JUNGLE SHOWCASE PASS / FAIL
##   godot --path game --resolution 1600x900 res://scenes/dev/jungle_showcase.tscn -- --shots=DIR [--only=a,b]
##       the checks, then the stills (.png) in DIR:
##   map_top          the whole map from straight above (no haze)
##   map_oblique      over the citadel looking north across the map
##   keep_clearing    the stronghold in its clearing, the jungle closing in
##   rts_view         the RTS camera over the south gate
##   rts_river        the RTS camera over the river and the middle bridge, the jungle either side
##   citadel          the Mobile Command Citadel, the main spawn, with the army for scale
##   bridge_main      the middle bridge over the river, an elephant crossing
##   east_bridge      the east river's bridge, toward the Outpost
##   outpost          the Outpost helipad, units by its deck
##   quarry           the Quarry helipad below the benches
##   prison_cliff     the prison on its plateau, the cliff in front
##   prison_close     the prison's walls and towers, a soldier at the gate for scale
##   lake             the north-west river's lake
##   jungle_floor     on the track to the Quarry, in the jungle at eye height
##   canopy           over the canopy, the emergent giants above it
##
## The checks: a path on the navmesh from the main spawn to every gate, and from each helipad to the gate
## facing it; every path keeps out of the water (it crosses on the bridges); the main spawn's to the south
## gate goes over the middle bridge.

const SHOTS := {
	"map_top": [Vector3(0, 2100, 1), Vector3(0, 0, 0), 46.0],
	"map_oblique": [Vector3(0, 380, 980), Vector3(0, 0, -150), 50.0],
	"keep_clearing": [Vector3(210, 120, 330), Vector3(0, 10, 0), 50.0],
	"rts_view": [Vector3(10, 0, 130), Vector3(0, 0, 0), 55.0],
	"rts_river": [Vector3(-40, 0, 455), Vector3(0, 0, 0), 55.0],
	"citadel": [Vector3(-55, 14, 600), Vector3(0, 6, 690), 52.0],
	"bridge_main": [Vector3(-14, 7, 534), Vector3(0, 3, 482), 58.0],
	"east_bridge": [Vector3(318, 7, 2), Vector3(372, 3, -10), 58.0],
	"outpost": [Vector3(505, 13, 10), Vector3(560, 4, -40), 55.0],
	"quarry": [Vector3(-398, 26, 8), Vector3(-505, 6, -40), 60.0],
	"prison_cliff": [Vector3(70, 100, -360), Vector3(-20, 22, -610), 50.0],
	"prison_close": [Vector3(55, 34, -575), Vector3(-20, 38, -650), 58.0],
	"lake": [Vector3(-585, 9, 205), Vector3(-660, 0, 300), 62.0],
	"jungle_floor": [Vector3(-464, 0, 215), Vector3(-454, 6, 130), 68.0],
	"canopy": [Vector3(200, 62, -260), Vector3(320, 30, -400), 60.0],
}

var level: JungleLevel
var commander: AttackerCommander
var cam: Camera3D
var shots_dir := ""
var only: Array = []
var _failed := false


func _ready() -> void:
	seed(5)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			only = Array(arg.get_slice("=", 1).split(","))
	GameConfig.map = "jungle"
	level = JungleLevel.new()
	add_child(level)
	level.build()
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	for t in level.aa_turrets:
		t.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	add_child(commander)
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	for k in 5:
		await get_tree().physics_frame
	_check_paths()
	if shots_dir == "":
		print("JUNGLE SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
		get_tree().quit(1 if _failed else 0)
		return
	_stage_units()
	for k in 20:
		await get_tree().physics_frame
	# A still scene from here on: nothing walks off.
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	for u in commander.units.values():
		u.process_mode = Node.PROCESS_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(shots_dir)
	for name in SHOTS:
		if not only.is_empty() and name not in only:
			continue
		await _shot(name)
	print("JUNGLE SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------- checks

func _check(ok: bool, what: String) -> void:
	print(("check ok: " if ok else "CHECK FAILED: ") + what)
	_failed = _failed or not ok


func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_path(map, from, to, true)


func _check_paths() -> void:
	var front := {}
	for side in level.gates:
		var g: Structure = level.gates[side]
		front[side] = g.global_position + g.global_basis.z * 6.0
	var main: Vector3 = level.spawn_points[0]
	for side in front:
		_check_path("main spawn -> %s gate" % side, main, front[side])
	for b in level.bases:
		var side: String = b.side
		_check_path("%s -> %s gate" % [b.display_name, side], b.spawn_point, front[side])
	var p := _path(main, front["south"])
	var over := false
	var river_z: float = JungleLayout.river_crossing("main", 0.0)[0].y
	for k in range(1, p.size()):
		var a := p[k - 1]
		var b := p[k]
		if (a.z - river_z) * (b.z - river_z) <= 0.0 and a.z != b.z:
			var x := lerpf(a.x, b.x, (river_z - a.z) / (b.z - a.z))
			over = over or absf(x) < 5.0
	_check(over, "the main spawn's way to the south gate crosses the middle bridge")


func _check_path(what: String, from: Vector3, to: Vector3) -> void:
	var p := _path(from, to)
	var reached := not p.is_empty() and p[-1].distance_to(to) < 3.0
	var length := 0.0
	var wet := 0
	for k in p.size():
		if k > 0:
			length += p[k].distance_to(p[k - 1])
			# Points along the leg, every 2 m, none in the water (unless up on a bridge's deck).
			var steps := int(p[k].distance_to(p[k - 1]) / 2.0)
			for s in steps:
				var q := p[k - 1].lerp(p[k], float(s) / maxf(steps, 1))
				if level.ground.wet(q.x, q.z) and q.y < JungleLayout.WATER_Y + 0.5:
					wet += 1
	_check(reached and wet == 0, "%s: %d m on the navmesh, %d points in the water" % [what, int(length), wet])


# ---------------------------------------------------------------- stills

## The army for scale: a column at the citadel, an elephant on the middle bridge, units by the helipads,
## a garrison soldier at the prison gate.
func _stage_units() -> void:
	var main: Vector3 = level.spawn_points[0]
	var kinds := ["rifleman", "rifleman", "elephant", "rhino", "giraffe", "mule", "hippo", "rifleman", "kangaroo", "lioness"]
	for k in kinds.size():
		_unit(kinds[k], main + Vector3((k % 5 - 2) * 7.0, 0, -int(k / 5) * 9.0 - 8.0), PI)
	var bridge: Vector2 = JungleLayout.river_crossing("main", 0.0)[0]
	_unit("elephant", Vector3(bridge.x, 0.1, bridge.y + 6.0), PI)
	_unit("rifleman", Vector3(bridge.x - 2.5, 0.1, bridge.y - 8.0), PI)
	_unit("rifleman", Vector3(bridge.x + 2.5, 0.1, bridge.y - 10.0), PI)
	for b in level.bases:
		for k in 4:
			_unit(["rifleman", "rhino", "kangaroo", "giraffe"][k], b.spawn_point + Vector3(0, 0, (k - 1.5) * 6.0), -PI * 0.5 * signf(b.position.x))
	var east: Vector2 = JungleLayout.river_crossing("east", -10.0)[0]
	_unit("bison_gun", Vector3(east.x + 4.0, 0.1, east.y), -PI * 0.5)
	var gate := JungleLayout.PRISON + Vector2(0, 50)
	var s := DefenderSoldier.new()
	s.model_path = LevelBuilder.DEFENDER_MODELS[0]
	s.station_name = "Prison guard"
	add_child(s)
	s.global_position = Vector3(gate.x, level.ground.height_at(gate.x, gate.y) + 0.1, gate.y)
	s.process_mode = Node.PROCESS_MODE_DISABLED


func _unit(kind: String, at: Vector3, yaw: float) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": kind, "spawn": 0})
	if id == 0:
		return null
	var u: AttackerUnit = commander.units[id]
	at.y = level.ground.height_at(at.x, at.z) + 0.2 if at.y < 0.05 else at.y
	u.global_position = at
	u.rotation.y = yaw
	return u


func _shot(name: String) -> void:
	var s: Array = SHOTS[name]
	var env := (level.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	env.fog_enabled = name != "map_top"
	cam.fov = s[2]
	if name.begins_with("rts_"):
		# The game's RTS camera: pitched 58 degrees down, 90-130 m out (the shot's first point is where it looks).
		var focus: Vector3 = s[0]
		var pitch := deg_to_rad(-58.0)
		var zoom := 90.0 if name == "rts_view" else 130.0
		cam.position = focus + Vector3(0, -sin(pitch) * zoom, cos(pitch) * zoom)
		cam.rotation = Vector3(pitch, 0, 0)
	else:
		var at: Vector3 = s[0]
		# Eye height over the ground where the shot's height is given as 0.
		if at.y == 0.0:
			at.y = level.ground.height_at(at.x, at.z) + 1.7
		cam.position = at
		cam.look_at(s[1])
	for k in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])
	print("shot %s" % name)
