extends Node3D
## Stills of the infantry's guns (HeldGun) on the real map:
##   1 defender_fps       the garrison's Cyber Orc Sentinel taken over on its deck, the Shadowline assault
##                        rifle in first person, Bear Riflemen out in the field below
##   2 defender_infantry  Cyber Orc Sentinels with the Shadowline lined up in the south field
##   3 bear_infantry      a squad of Bear Riflemen with the Prototype C heavy LMG
##
##   godot --path game --rendering-driver opengl3 --resolution 1600x900 \
##       res://scenes/dev/weapons_showcase.tscn -- --shots=DIR [--aim]
##
## --aim takes the first-person shot aimed down the scope. Without --shots it only checks that every
## model carries its gun (WEAPONS SHOWCASE PASS / FAIL) and quits.

## Where the lineups stand (south field), and where the bears the rifleman looks out at stand.
const DEFENDERS_AT := Vector3(-14.0, 0.0, 118.0)
const BEARS_AT := Vector3(14.0, 0.0, 118.0)
## How far out from the rifleman's post the bears it looks at stand.
const FIELD_OUT := 38.0

var level: LevelBuilder
var commander: AttackerCommander
var cam: Camera3D
var shots_dir := ""
var aim := false
var defenders: Array[DefenderSoldier] = []
var bears: Array[AttackerUnit] = []
var fps_soldier: DefenderSoldier
var field_at := Vector3.ZERO
var _failed := false


func _ready() -> void:
	seed(3)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg == "--aim":
			aim = true
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
	add_child(commander)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	for k in 10:
		await get_tree().physics_frame
	# Cyber Orc Sentinels with the rifle, side by side, facing the camera (+Z).
	var model: String = LevelBuilder.DEFENDER_MODELS.filter(func(p): return p.ends_with("_armed.glb"))[0]
	for k in 3:
		var s := DefenderSoldier.new()
		s.model_path = model
		s.station_name = "Showcase %d" % k
		add_child(s)
		s.global_position = DEFENDERS_AT + Vector3((k - 1.0) * 1.7, 0.05, absf(k - 1.0) * -0.5)
		s.rotation.y = PI - (k - 1.0) * 0.15
		s.process_mode = Node.PROCESS_MODE_DISABLED
		defenders.append(s)
	# Bear Riflemen: a squad in the field for the lineup, and a few further out for the rifleman to see.
	for k in 4:
		var u := _bear(BEARS_AT + Vector3((k - 1.5) * 2.2, 0.0, absf(k - 1.5) * -0.6))
		u.rotation.y = PI - (k - 1.5) * 0.15
	# The armed rifleman's post: bears out in the field in front of it, facing the stronghold.
	fps_soldier = _armed_station()
	var out := -fps_soldier.global_basis.z
	out.y = 0.0
	out = out.normalized()
	field_at = fps_soldier.global_position + out * FIELD_OUT
	field_at.y = 0.0
	var side := out.cross(Vector3.UP)
	for k in 5:
		var u := _bear(field_at + side * (k - 2.0) * 3.2 + out * (k % 2) * 2.5)
		u.rotation.y = atan2(out.x, out.z)  # facing the stronghold
	for k in 30:
		await get_tree().physics_frame
	_check_guns()
	if shots_dir == "":
		print("WEAPONS SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
		get_tree().quit(1 if _failed else 0)
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	await _shot_fps()
	await _shot_lineup("defender_infantry", DEFENDERS_AT + Vector3(-1.2, 1.25, 6.4), DEFENDERS_AT + Vector3(0.0, 0.95, 0.0))
	# The bears turn to face the garrison's lineup (to their west): the camera stands off their right (gun) side.
	await _shot_lineup("bear_infantry", BEARS_AT + Vector3(-5.0, 1.55, -6.2), BEARS_AT + Vector3(0.6, 1.15, -0.3))
	get_tree().quit()


func _bear(at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "rifleman", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = at + Vector3.UP * 0.2
	bears.append(u)
	return u


func _check_guns() -> void:
	_check(fps_soldier != null, "a garrison post has the Cyber Orc Sentinel")
	for s in level.stations:
		if s is DefenderSoldier and s != fps_soldier:
			_check(s.find_children("*", "BoneAttachment3D", true, false).is_empty(), "%s carries no rifle model" % s.name)
	for s in defenders:
		_check(s.find_children("*", "BoneAttachment3D", true, false).size() == 1, "%s holds its rifle" % s.model_path.get_file())
	for u in bears:
		_check(u.find_children("*", "BoneAttachment3D", true, false).size() == 1, "the Bear Rifleman holds its LMG")


func _check(ok: bool, what: String) -> void:
	print(("check ok: " if ok else "CHECK FAILED: ") + what)
	_failed = _failed or not ok


## The garrison's rifleman with the Shadowline (the Cyber Orc Sentinel).
func _armed_station() -> DefenderSoldier:
	for s in level.stations:
		if s is DefenderSoldier and (s as DefenderSoldier).model_path.ends_with("_armed.glb"):
			return s
	return null


## The armed rifleman, taken over, looking out at the bears in the field.
func _shot_fps() -> void:
	var soldier := fps_soldier
	soldier.process_mode = Node.PROCESS_MODE_INHERIT
	soldier.possess()
	var to := field_at + Vector3.UP * 1.0 - soldier.global_position
	soldier.rotation.y = atan2(-to.x, -to.z)
	var head := soldier.get_camera().get_parent() as Node3D
	var eye := soldier.global_position + Vector3.UP * 1.6
	head.rotation.x = atan2((field_at + Vector3.UP * 1.0 - eye).y, Vector2(to.x, to.z).length())
	if aim:
		Input.action_press("aim")
	for k in 40:
		await get_tree().process_frame
	await _save("defender_fps")
	Input.action_release("aim")
	soldier.unpossess()
	soldier.process_mode = Node.PROCESS_MODE_DISABLED


func _shot_lineup(label: String, from: Vector3, at: Vector3) -> void:
	cam.current = true
	cam.global_position = from
	cam.look_at(at)
	for k in 10:
		await get_tree().process_frame
	await _save(label)


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shots_dir, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot %s" % path)
