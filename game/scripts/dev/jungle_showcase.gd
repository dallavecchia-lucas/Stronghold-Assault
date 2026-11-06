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
##   rts_river        the RTS camera over the river, the army held on its south bank, the forest either side
##   citadel          the Mobile Command Citadel, the main spawn, the army in front of it
##   citadel_scale    close by its hull, a War Elephant and a Night Ops Chimp beside it for scale
##   river            on the river's south bank, an elephant, riflemen and a giraffe at the water's edge
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
##   fps_scope_south  the same on the south gun deck through the rifle's smart scope (RMB) at the treeline
##
## The checks: the water can't be crossed on foot (no ford; the swim links and the bridges are bridge_showcase's). On the navmesh the main spawn has no
## way to any gate (its paths end on the river's south bank), nor the Outpost helipad to the east gate
## (the east river is in the way); the Quarry helipad has one to the west gate; none of them goes into the
## water. And with no navmesh to keep it out, a walker driven straight at the water stops at its edge
## (JungleTerrain's water's edge wall).

const SHOTS := {
	"map_top": [Vector3(0, 2100, 1), Vector3(0, 0, 0), 46.0],
	"map_oblique": [Vector3(0, 380, 980), Vector3(0, 0, -150), 50.0],
	"keep_clearing": [Vector3(210, 120, 330), Vector3(0, 10, 0), 50.0],
	"rts_view": [Vector3(10, 0, 130), Vector3(0, 0, 0), 55.0],
	"rts_river": [Vector3(-40, 0, 455), Vector3(0, 0, 0), 55.0],
	"citadel": [Vector3(86, 28, 772), Vector3(0, 16, 690), 72.0],
	"citadel_scale": [Vector3(100, 2.2, 728), Vector3(56, 14, 692), 64.0],
	"river": [Vector3(-24, 0, 522), Vector3(8, -1.0, 470), 62.0, true],
	"outpost": [Vector3(395, 70, 150), Vector3(600, 12, -40), 58.0],
	"quarry": [Vector3(-398, 26, 8), Vector3(-505, 6, -40), 60.0],
	"prison_cliff": [Vector3(70, 100, -360), Vector3(-20, 22, -610), 50.0],
	"prison_close": [Vector3(55, 34, -575), Vector3(-20, 38, -650), 58.0],
	"lake": [Vector3(-590, 13, 200), Vector3(-675, 4, 320), 62.0],
	"forest_floor": [Vector3(-420, 0, 230), Vector3(-430, 6, 150), 68.0, true],
	"canopy": [Vector3(200, 62, -260), Vector3(320, 30, -400), 60.0],
	"fps_deck_south": [],
	"fps_deck_east": [],
	"fps_roof_south": [],
	"fps_roof_west": [],
	"fps_scope_south": [],
}
## Where the elephant and the chimp stand by the citadel's hull (x, z: by the tip of its east arm, on the
## sunny side), and where the army stands on the river's south bank (x).
const BESIDE_CITADEL := [Vector2(73, 706), Vector2(70, 699)]
const BANK_X := 0.0

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
	await _check_water_edge()
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
	var river_z: float = JungleLayout.river_crossing("main", main.x)[0].y
	for side in front:
		var p := _path(main, front[side])
		var end := p[-1] if not p.is_empty() else main
		_check(end.distance_to(front[side]) > 50.0 and end.z > river_z and _wet_points(p) == 0,
				"main spawn -> %s gate: no way across the river (the path ends on the south bank, %d m short, none of it in the water)"
				% [side, int(end.distance_to(front[side]))])
	for b in level.bases:
		var side: String = b.side
		var p := _path(b.spawn_point, front[side])
		var end := p[-1] if not p.is_empty() else b.spawn_point
		var reached := end.distance_to(front[side]) < 3.0
		# The Outpost is across the east river from the Keep; the Quarry is on the Keep's side of every river.
		var cut: bool = b.spawn_point.x > JungleLayout.river_crossing("east", b.spawn_point.z)[0].x
		_check(reached != cut and _wet_points(p) == 0, "%s -> %s gate: %s, none of it in the water" % [b.display_name, side,
				("no way across the east river (%d m short)" % int(end.distance_to(front[side]))) if cut else "%d m on the navmesh" % int(_length(p))])


func _length(p: PackedVector3Array) -> float:
	var length := 0.0
	for k in range(1, p.size()):
		length += p[k].distance_to(p[k - 1])
	return length


## How many points along `p`, every 2 m, are in the water.
func _wet_points(p: PackedVector3Array) -> int:
	var wet := 0
	for k in range(1, p.size()):
		var steps := maxi(int(p[k].distance_to(p[k - 1]) / 2.0), 1)
		for s in steps:
			var q := p[k - 1].lerp(p[k], float(s) / steps)
			if level.ground.wet(q.x, q.z):
				wet += 1
	return wet


## Walkers driven straight at the water, by physics alone (no navmesh, nothing else in their way: only
## the water's edge wall in their mask, the ground's height set under them), across the main river at
## three places and the east river: each stops at the edge, dry.
func _check_water_edge() -> void:
	var hw := JungleLayout.river_width("main") * 0.5
	var runs := []
	for x in [-300.0, 0.0, 250.0]:
		var c: Vector2 = JungleLayout.river_crossing("main", x)[0]
		runs.append(["main river at x %d" % int(x), Vector3(c.x, 0, c.y + hw + 16.0), Vector3(0, 0, -1)])
	var e: Vector2 = JungleLayout.river_crossing("east", -40.0)[0]
	runs.append(["east river by the Outpost", Vector3(e.x + JungleLayout.river_width("east") * 0.5 + 16.0, 0, e.y), Vector3(-1, 0, 0)])
	for r in runs:
		var w := CharacterBody3D.new()
		w.collision_layer = 0
		w.collision_mask = GameConfig.LAYER_WATER_EDGE
		w.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		w.add_child(cs)
		add_child(w)
		var start: Vector3 = r[1]
		w.global_position = Vector3(start.x, level.ground.height_at(start.x, start.z), start.z)
		var went_in := false
		# 8 s at 6 m/s: far enough to cross twice over.
		for k in 480:
			await get_tree().physics_frame
			var at := w.global_position
			w.global_position.y = level.ground.height_at(at.x, at.z)
			w.velocity = r[2] * 6.0
			w.move_and_slide()
			went_in = went_in or level.ground.wet(w.global_position.x, w.global_position.z)
		var stop := w.global_position
		var ahead: Vector3 = stop + r[2] * 2.0
		_check(not went_in and level.ground.wet(ahead.x, ahead.z), "a walker driven at the %s stops at the water's edge (%d m on, dry)"
				% [r[0], int(Vector2(stop.x - start.x, stop.z - start.z).length())])
		w.queue_free()


# ---------------------------------------------------------------- stills

## The army for scale: a column out in front of the citadel, a War Elephant and a Night Ops Chimp right by
## its hull, an elephant, riflemen, a kangaroo and a giraffe held on the river's south bank, units by the
## helipads, a garrison soldier at the prison gate.
func _stage_units() -> void:
	var main: Vector3 = level.spawn_points[0]
	var kinds := ["rifleman", "rifleman", "elephant", "rhino", "giraffe", "mule", "hippo", "rifleman", "kangaroo", "lioness"]
	for k in kinds.size():
		_unit(kinds[k], main + Vector3(40.0 + (k % 5 - 2) * 7.0, 0, -int(k / 5) * 9.0 - 6.0), 0.0)
	_unit("elephant", Vector3(BESIDE_CITADEL[0].x, 0, BESIDE_CITADEL[0].y), -2.3)
	_unit("chimp", Vector3(BESIDE_CITADEL[1].x, 0, BESIDE_CITADEL[1].y), -2.0)
	# On the bank, the water's edge a few metres in front of them.
	var bank: Vector2 = JungleLayout.river_crossing("main", BANK_X)[0] + Vector2(0, JungleLayout.river_width("main") * 0.5 + 4.0)
	_unit("elephant", Vector3(bank.x + 2.0, 0, bank.y + 6.0), 0.2)
	_unit("rifleman", Vector3(bank.x - 3.0, 0, bank.y + 2.0), 0.1)
	_unit("rifleman", Vector3(bank.x + 6.5, 0, bank.y + 2.5), 0.0)
	_unit("kangaroo", Vector3(bank.x + 10.0, 0, bank.y + 7.0), -0.2)
	_unit("giraffe", Vector3(bank.x - 8.0, 0, bank.y + 9.0), 0.3)
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
	if s.size() > 3:
		# Stood at the open spot nearest the one asked for (no trunk close by), at eye height.
		var at := _open_spot(s[0])
		cam.position = Vector3(at.x, level.ground.height_at(at.x, at.z) + 1.9, at.z)
		cam.look_at(s[1] + (at - s[0]) * Vector3(1, 0, 1) * 0.5)
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
	var face: String = {"fps_deck_south": "south", "fps_deck_east": "east", "fps_roof_south": "south", "fps_roof_west": "west",
			"fps_scope_south": "south"}[name]
	var out: Vector3 = LevelBuilder.SIDES[face].dir
	var at: Vector3
	if name.begins_with("fps_deck") or name == "fps_scope_south":
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
	var scope := name == "fps_scope_south"
	if scope:
		Input.action_press("aim")
	for k in 40:
		await get_tree().process_frame
	await _save(name)
	if scope:
		Input.action_release("aim")
	soldier.unpossess()
	soldier.process_mode = Node.PROCESS_MODE_DISABLED
	for st in level.stations:
		if st is DefenderSoldier:
			st.visible = true
