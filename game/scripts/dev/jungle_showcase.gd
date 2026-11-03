extends Node3D
## The Jungle Keep map (JungleLevel): checks its navmesh, and takes stills round it.
##
##   godot --path game --headless res://scenes/dev/jungle_showcase.tscn
##       checks: JUNGLE SHOWCASE PASS / FAIL
##   godot --path game --resolution 1600x900 res://scenes/dev/jungle_showcase.tscn -- --shots=DIR [--only=a,b]
##       the checks, then the stills (.png) in DIR:
##   map_top          the whole map from straight above (no haze)
##   map_oblique      over the citadel looking north across the map
##   keep_clearing    the stronghold in its clearing, the forest closing in
##   rts_view         the RTS camera over the south gate
##   rts_river        the RTS camera over the river, the army wading across, the forest either side
##   citadel          the Mobile Command Citadel, the main spawn, the army in front of it
##   citadel_scale    close by its hull, a War Elephant and a Night Ops Chimp beside it for scale
##   ford             on the river's south bank, an elephant and riflemen wading across
##   outpost          the Outpost helipad, units by its deck
##   quarry           the Quarry helipad below the benches
##   prison_cliff     the prison on its plateau, the cliff in front
##   prison_close     the prison's walls and towers, a soldier at the gate for scale
##   lake             the north-west river's lake
##   forest_floor     in the forest at eye height (the open spot nearest FOREST_AT)
##   canopy           over the forest canopy
##   fps_deck_south   first person: the garrison's rifleman (the Cyber Orc Sentinel, Shadowline in hand)
##   fps_deck_east    on the south and the east gun decks, and on the south and the west roofs,
##   fps_roof_south   looking out over the clearing at the treeline
##   fps_roof_west
##
## The checks: a path on the navmesh from the main spawn to every gate, and from each helipad to the gate
## facing it; none of them through the lake (the rivers they wade); the main spawn's to the south gate
## goes about straight there (no detour: the river is a ford all along).

const SHOTS := {
	"map_top": [Vector3(0, 2100, 1), Vector3(0, 0, 0), 46.0],
	"map_oblique": [Vector3(0, 380, 980), Vector3(0, 0, -150), 50.0],
	"keep_clearing": [Vector3(210, 120, 330), Vector3(0, 10, 0), 50.0],
	"rts_view": [Vector3(10, 0, 130), Vector3(0, 0, 0), 55.0],
	"rts_river": [Vector3(-40, 0, 455), Vector3(0, 0, 0), 55.0],
	"citadel": [Vector3(-95, 16, 545), Vector3(0, 20, 680), 58.0],
	"citadel_scale": [Vector3(-46, 2.0, 597), Vector3(-6, 15, 646), 62.0],
	"ford": [Vector3(-26, 2.6, 516), Vector3(4, -1.0, 480), 58.0],
	"outpost": [Vector3(522, 13, 2), Vector3(562, 4, -40), 56.0],
	"quarry": [Vector3(-398, 26, 8), Vector3(-505, 6, -40), 60.0],
	"prison_cliff": [Vector3(70, 100, -360), Vector3(-20, 22, -610), 50.0],
	"prison_close": [Vector3(55, 34, -575), Vector3(-20, 38, -650), 58.0],
	"lake": [Vector3(-590, 13, 200), Vector3(-675, 4, 320), 62.0],
	"forest_floor": [Vector3(-420, 0, 230), Vector3(-430, 6, 150), 68.0],
	"canopy": [Vector3(200, 62, -260), Vector3(320, 30, -400), 60.0],
	"fps_deck_south": [],
	"fps_deck_east": [],
	"fps_roof_south": [],
	"fps_roof_west": [],
}
## Where the elephant and the chimp stand by the citadel's hull (x, z), and the ford's crossing (x).
const BESIDE_CITADEL := [Vector2(-16, 622), Vector2(-9, 621)]
const FORD_X := 0.0

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
	cam.far = 30000.0
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
	var length := 0.0
	for k in range(1, p.size()):
		length += p[k].distance_to(p[k - 1])
	var straight := Vector2(main.x - front["south"].x, main.z - front["south"].z).length()
	_check(length < straight * 1.15, "the main spawn's way to the south gate goes straight across the river (%d m, %d m as the crow flies)" % [int(length), int(straight)])


func _check_path(what: String, from: Vector3, to: Vector3) -> void:
	var p := _path(from, to)
	var reached := not p.is_empty() and p[-1].distance_to(to) < 3.0
	var length := 0.0
	var deep := 0
	var wading := 0
	for k in p.size():
		if k > 0:
			length += p[k].distance_to(p[k - 1])
			# Points along the leg, every 2 m: none in the lake; some wading across the rivers.
			var steps := int(p[k].distance_to(p[k - 1]) / 2.0)
			for s in steps:
				var q := p[k - 1].lerp(p[k], float(s) / maxf(steps, 1))
				if level.ground.deep(q.x, q.z):
					deep += 1
				elif level.ground.wet(q.x, q.z):
					wading += 1
	_check(reached and deep == 0, "%s: %d m on the navmesh, %d m of it wading, none in deep water (%d)" % [what, int(length), wading * 2, deep])


# ---------------------------------------------------------------- stills

## The army for scale: a column out in front of the citadel, a War Elephant and a Night Ops Chimp right by
## its hull, an elephant and riflemen wading the river, units by the helipads, a garrison soldier at the
## prison gate.
func _stage_units() -> void:
	var main: Vector3 = level.spawn_points[0]
	var kinds := ["rifleman", "rifleman", "elephant", "rhino", "giraffe", "mule", "hippo", "rifleman", "kangaroo", "lioness"]
	for k in kinds.size():
		_unit(kinds[k], main + Vector3(40.0 + (k % 5 - 2) * 7.0, 0, -int(k / 5) * 9.0 - 6.0), 0.0)
	_unit("elephant", Vector3(BESIDE_CITADEL[0].x, 0, BESIDE_CITADEL[0].y), 0.35)
	_unit("chimp", Vector3(BESIDE_CITADEL[1].x, 0, BESIDE_CITADEL[1].y), 0.6)
	var ford: Vector2 = JungleLayout.river_crossing("main", FORD_X)[0]
	_unit("elephant", Vector3(ford.x, 0, ford.y + 4.0), 0.0)
	_unit("rifleman", Vector3(ford.x - 4.0, 0, ford.y - 4.0), 0.0)
	_unit("rifleman", Vector3(ford.x + 3.5, 0, ford.y - 9.0), 0.0)
	_unit("kangaroo", Vector3(ford.x + 8.0, 0, ford.y + 6.0), 0.0)
	for b in level.bases:
		for k in 4:
			_unit(["rifleman", "rhino", "kangaroo", "giraffe"][k], b.spawn_point + Vector3(0, 0, (k - 1.5) * 6.0), -PI * 0.5 * signf(b.position.x))
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
	if name.begins_with("fps_"):
		await _shot_fps(name)
		return
	cam.current = true
	cam.fov = s[2]
	if name == "forest_floor":
		var at := _open_spot(s[0])
		cam.position = Vector3(at.x, level.ground.height_at(at.x, at.z) + 1.7, at.z)
		cam.look_at(cam.position + (s[1] - s[0]) * Vector3(1, 0, 1) + Vector3.UP * 3.0)
	elif name.begins_with("rts_"):
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
	await _save(name)


func _save(name: String) -> void:
	for k in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])
	# What it took to draw (shadows included): a measure of the map's load on the GPU from there.
	print("shot %s: %.1f M triangles, %d draw calls" % [name, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


## The nearest spot to `want` with no tree's trunk within 7 m and dry ground.
func _open_spot(want: Vector3) -> Vector3:
	for r in range(0, 60, 3):
		for k in 12:
			var a := TAU * k / 12.0
			var p := want + Vector3(cos(a), 0.0, sin(a)) * r
			if ForestTree.near(p, 7.0).is_empty() and not level.ground.wet(p.x, p.z):
				return p
	return want


## Through the eyes of the garrison's rifleman (the Cyber Orc Sentinel with the Shadowline), taken over
## and set down on a gun deck or a roof, looking out at the treeline over the clearing.
func _shot_fps(name: String) -> void:
	var soldier: DefenderSoldier = null
	for st in level.stations:
		if st is DefenderSoldier and (st as DefenderSoldier).model_path.ends_with("_armed.glb"):
			soldier = st
	var face: String = {"fps_deck_south": "south", "fps_deck_east": "east", "fps_roof_south": "south", "fps_roof_west": "west"}[name]
	var out: Vector3 = LevelBuilder.SIDES[face].dir
	var at: Vector3
	if name.begins_with("fps_deck"):
		# A rifle post on that side's gun deck (the east deck's is the soldier's own).
		at = soldier.global_position
		for st in level.stations:
			if st is DefenderSoldier and st != soldier and String(st.name).begins_with("Soldier_%s" % face):
				at = st.global_position
				st.visible = false
				break
	else:
		# Out by the roof's front edge, in front of one of its AA mounts.
		var mount: Node3D = level.aa_turrets.filter(func(t): return String(t.name).begins_with("AA_%s" % LevelBuilder.SIDES[face].face))[0]
		at = mount.global_position + out * 3.0 + Vector3.UP * 0.3
	soldier.process_mode = Node.PROCESS_MODE_INHERIT
	soldier.global_position = at
	soldier.velocity = Vector3.ZERO
	soldier.possess()
	# Facing out over the clearing at the treeline, its trees' middle height.
	var look := Vector3(0, 0, 0) + out * (JungleLayout.CLEARING_R + 60.0)
	look.y = 14.0
	var to := look - soldier.global_position
	soldier.rotation.y = atan2(-to.x, -to.z)
	var pitch := atan2(to.y - 1.6, Vector2(to.x, to.z).length())
	soldier._pitch = pitch
	soldier.get_camera().get_parent().rotation.x = pitch
	for k in 40:
		await get_tree().process_frame
	await _save(name)
	soldier.unpossess()
	soldier.process_mode = Node.PROCESS_MODE_DISABLED
	for st in level.stations:
		if st is DefenderSoldier:
			st.visible = true
