extends Node3D
## Stills of the attackers' transport helicopters on the real Jungle Keep: the two standing by the citadel, one on the
## Outpost's pad with its units put down beside the camp, one on the Quarry's (a standard pad: it overhangs the deck),
## one cruising over the jungle, and one flying at each step of its hurt (unhurt, grey smoke at 60%, black at 40%, fire at 10%).
##
##   godot --path game --rendering-driver opengl3 --fixed-fps 30 res://scenes/dev/helo_shots.tscn -- --out=/some/dir --lighting=standard
##
## The helicopters are posed by hand (no trip is flown); the flying ones are moved along a line so their smoke trails.

var level: JungleLevel
var fleet: HeloFleet
var cam: Camera3D
var out_dir := "user://helo_shots"
var _flyer: TransportHelo
var _fly_dir := Vector3.ZERO
var _next_id := 1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if OS.get_cmdline_user_args().has("--field"):
		await _field_shots()
		get_tree().quit()
		return
	level = JungleLevel.new()
	level.name = "Level"
	add_child(level)
	level.build()
	FX.of(self)
	fleet = HeloFleet.new()
	fleet.manual = true
	fleet.base_position = level.spawn_points[0]
	add_child(fleet)
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	await _frames(10)
	await _shots()
	print("HELO SHOTS done -> %s" % out_dir)
	get_tree().quit()


func _process(delta: float) -> void:
	if _flyer != null and is_instance_valid(_flyer):
		_flyer.global_position += _fly_dir * TransportHelo.CRUISE_SPEED * delta
		cam.global_position = _flyer.global_position - _fly_dir * 75.0 + Vector3(0, 20, 0) + _fly_dir.cross(Vector3.UP) * 55.0
		cam.look_at(_flyer.global_position + Vector3(0, 8, 0))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(file: String) -> void:
	print("HELO SHOTS taking %s" % file)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, file]
	get_viewport().get_texture().get_image().save_png(path)
	print("HELO SHOTS saved %s" % path)


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)


func _spin(h: TransportHelo) -> void:
	if h.rig:
		h.rig.start()
		h.rig.set("_power", 1.0)


func _unit(type_id: String, at: Vector3) -> AttackerUnit:
	var u := AttackerUnit.new()
	u.setup(type_id, _next_id)
	_next_id += 1
	add_child(u)
	u.global_position = at + Vector3(0, 0.2, 0)
	return u


func _shots() -> void:
	var a := fleet.helo_at(0)
	var b := fleet.helo_at(1)
	var main: Vector3 = level.spawn_points[0]
	# 1. Both standing by the citadel, rotors still.
	_look(main + Vector3(0, 70, -170), main + Vector3(0, 0, 10))
	await _frames(4)
	await _snap("01_base_both")
	_look(a.global_position + Vector3(-60, 22, -45), a.global_position + Vector3(0, 8, 0))
	await _frames(10)
	await _snap("02_base_close")
	print("HELO SHOTS staging the Outpost")
	# 2. On the Outpost's pad, its units put down beside the camp.
	var outpost: AttackerBase = level.bases[1]
	a.global_position = outpost.landing_point()
	a.rotation.y = outpost.landing_yaw()
	_spin(a)
	var types := ["elephant", "rifleman", "rifleman", "rhino", "giraffe", "kangaroo", "medic", "hippo", "rifleman", "lioness",
			"chimp", "rifleman"]
	for k in types.size():
		_unit(types[k], outpost.drop_spot(k, types.size()))
	var pad := outpost.landing_point()
	var out := outpost.lane_dir()
	_look(pad + out * 230.0 + Vector3(0, 110, 120), pad + out * 60.0)
	await _frames(4)
	await _snap("03_outpost_pad")
	_look(outpost.spawn_point + out * 70.0 + Vector3(0, 45, 60), outpost.spawn_point + out * 8.0)
	await _frames(10)
	await _snap("04_outpost_units")
	# 3. On the Quarry's standard pad: it overhangs the deck.
	var quarry: AttackerBase = level.bases[0]
	b.global_position = quarry.landing_point()
	b.rotation.y = quarry.landing_yaw()
	_spin(b)
	_look(quarry.landing_point() + Vector3(90, 55, 80), quarry.landing_point())
	await _frames(4)
	await _snap("05_quarry_pad")
	# 4. Cruising over the jungle, then flying at each step of its hurt.
	b.global_position = Vector3(-200, 90, 420)
	b.rotation.y = PI * 0.5
	_fly_dir = Vector3(1, 0, 0)
	_flyer = b
	_spin(b)
	await _frames(12)
	await _snap("06_cruising")
	for step in [[1.0, "07_flying_100pct"], [0.6, "08_flying_60pct_grey_smoke"], [0.4, "09_flying_40pct_black_smoke"],
			[0.1, "10_flying_10pct_fire"]]:
		b.hp = TransportHelo.MAX_HP * float(step[0])
		b.global_position = Vector3(-200, 90, 420)
		await _frames(24)
		await _snap(step[1])
	_flyer = null
	# 5. The same steps parked at the base (it smokes while it mends).
	a.global_position = a.home_position
	a.rotation.y = a.home_yaw
	a.rig.stop()
	a.hp = TransportHelo.MAX_HP * 0.08
	_look(a.global_position + Vector3(-70, 30, -60), a.global_position + Vector3(0, 10, 0))
	await _frames(24)
	await _snap("11_base_10pct_fire")


## The hurt steps flown over a plain field (no map to build: quick), --field.
func _field_shots() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	ground.mesh = plane
	ground.material_override = Mats.flat(Color(0.32, 0.42, 0.24))
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	add_child(env)
	FX.of(self)
	cam = Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	var h := TransportHelo.new()
	h.manual = true
	h.setup(0, Vector3.ZERO, PI * 0.5)
	add_child(h)
	await _frames(5)
	_flyer = h
	_fly_dir = Vector3(1, 0, 0)
	_spin(h)
	for step in [[1.0, "07_flying_100pct"], [0.6, "08_flying_60pct_grey_smoke"], [0.4, "09_flying_40pct_black_smoke"],
			[0.1, "10_flying_10pct_fire"]]:
		h.hp = TransportHelo.MAX_HP * float(step[0])
		h.global_position = Vector3(-300, 60, 0)
		await _frames(75)
		await _snap(step[1])
	_flyer = null
	h.global_position = Vector3.ZERO
	h.rotation.y = PI * 0.5
	h.hp = TransportHelo.MAX_HP * 0.08
	h.rig.stop()
	_look(Vector3(-60, 25, -55), Vector3(0, 9, 0))
	await _frames(75)
	await _snap("11_landed_10pct_fire")
