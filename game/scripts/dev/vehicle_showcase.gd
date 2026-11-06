extends Node3D
## The machines' rigs at work, on a plain field (no match): the defenders' Iron Vanguard hover tank, Defender drone
## and Defender fighter jet, and the attackers' Heavy Lift Helicopter, each flown or driven along a scripted path by
## moving its rig about; the rigs animate their parts off that motion (VehicleRig follow_motion).
##
##   tank   (0-12 s)  hovers, speeds off and stops (the thrusters gimbal, the boosters burn, the hull sits back and
##                    dips), turns, swings its turret onto a target, elevates and fires twice (recoil).
##   drone  (12-22 s) hovers, its pods up and its fans spinning; flies off (the pods tilt forward), turns, brakes
##                    (they tilt back) and hovers again.
##   jet    (22-32 s) a low pass: rolls into a hard turn (ailerons, stabilators pulling, rudders), rolls out and
##                    climbs away on afterburner.
##   helo   (32-56 s) one helicopter spools its rotors up on the ground beside a war elephant, for scale; a second
##                    flies by with an elephant on its sling, speeds up and stops: the load swings and settles.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/vehicle_showcase.tscn -- --test   # VEHICLE SHOWCASE PASS / FAIL
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
##       res://scenes/dev/vehicle_showcase.tscn -- --snap=6,9.6,15,26,40,50 --snap-out=/tmp/vehicles
##
## --cam=tank|drone|jet|helo|lift keeps the camera on one of them the whole time (default: each in its turn).

const END := 56.0
const TANK_AT := Vector3(0, 0, 0)
const DRONE_AT := Vector3(-70, 7, 20)
const HELO_AT := Vector3(110, 0, 60)
const LIFT_AT := Vector3(60, 42, -260)
const TARGET := Vector3(30, 9.5, 46)
const ELEPHANT := "res://assets/units/war_elephant_sentinel/war_elephant_sentinel_rigged.glb"

var t := 0.0
var cam: Camera3D
var tank: HoverTankRig
var drone: DroneRig
var jet: FighterJetRig
var helo: HeavyLiftRig
var lift: HeavyLiftRig
var _test := false
var _cam_only := ""
var _snaps: Array = []
var _snap_out := "/tmp/vehicles"
var _snapping := false
## Motion state: [speed (m/s), heading (rad, 0 = +Z), pitch (rad), bank (rad)] per vehicle.
var _tank := [0.0, 0.0]
var _drone := [0.0, 0.0]
var _jet := [110.0, 0.0, 0.0, 0.0]
var _lift := [0.0, 0.0]
var _fired := 0
## What the test saw: the largest value of each thing (see _watch).
var _seen := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--test":
			_test = true
		elif arg.begins_with("--cam="):
			_cam_only = arg.get_slice("=", 1)
		elif arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	_build_world()
	tank = HoverTankRig.new()
	add_child(tank)
	tank.position = TANK_AT
	drone = DroneRig.new()
	add_child(drone)
	drone.position = DRONE_AT
	jet = FighterJetRig.new()
	add_child(jet)
	jet.position = Vector3(-60, 60, -700)
	helo = HeavyLiftRig.new()
	add_child(helo)
	helo.position = HELO_AT
	helo.rotation.y = deg_to_rad(-30.0)
	var standing := _elephant()
	add_child(standing)
	standing.position = HELO_AT + Vector3(-34, 0, 18)
	standing.rotation.y = deg_to_rad(70.0)
	lift = HeavyLiftRig.new()
	add_child(lift)
	lift.position = LIFT_AT
	lift.start()
	lift.carry(_elephant(), 16.0, 3.7)
	# The tank's target: a bunker on a rock, above the gun.
	add_child(Mats.box_mesh(Vector3(9, 8, 9), TARGET - Vector3(0, 5.5, 0), Mats.rock()))
	add_child(Mats.box_mesh(Vector3(3, 3, 3), TARGET, Mats.flat(Color(0.6, 0.15, 0.1))))
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 3000.0
	add_child(cam)
	cam.current = true


func _elephant() -> Node3D:
	var e := (load(ELEPHANT) as PackedScene).instantiate() as Node3D
	var anim := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation("Idle"):
		anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		anim.play("Idle")
	return e


func _physics_process(delta: float) -> void:
	t += delta
	_move_tank(delta)
	_move_drone(delta)
	_move_jet(delta)
	_move_helos(delta)
	_camera()
	_watch()
	if t >= END:
		_finish()
	if not _snaps.is_empty():
		_snap()


# ------------------------------------------------------------------------------------------------- motions

func _move_tank(delta: float) -> void:
	var acc := 0.0
	var yaw_rate := 0.0
	if t > 2.0 and t < 5.0:
		acc = 4.0
	elif t >= 5.0 and t < 8.0:
		acc = -4.0 if _tank[0] > 0.0 else 0.0
	if t > 7.5 and t < 9.0:
		yaw_rate = 0.5
	_tank[0] = maxf(_tank[0] + acc * delta, 0.0)
	_tank[1] += yaw_rate * delta
	tank.rotation.y = _tank[1]
	tank.position += Vector3(sin(_tank[1]), 0, cos(_tank[1])) * _tank[0] * delta
	if t > 6.0:
		tank.aim(TARGET)
	for at in [9.6, 11.2]:
		if t >= at and _fired < [9.6, 11.2].find(at) + 1:
			tank.fire()
			_fired += 1
			Combat.spawn_muzzle_light(self, tank.muzzle().origin)


func _move_drone(delta: float) -> void:
	var acc := 0.0
	var yaw_rate := 0.0
	if t > 13.5 and t < 17.0:
		acc = 5.0
	if t > 16.0 and t < 18.5:
		yaw_rate = 0.7
	if t > 18.5 and t < 22.0:
		acc = -6.0 if _drone[0] > 0.0 else 0.0
	_drone[0] = maxf(_drone[0] + acc * delta, 0.0)
	_drone[1] += yaw_rate * delta
	drone.rotation.y = _drone[1]
	drone.position += Vector3(sin(_drone[1]), 0, cos(_drone[1])) * _drone[0] * delta
	if t > 12.0 and t < 13.5:
		drone.position.y += delta * 1.2


func _move_jet(delta: float) -> void:
	# Straight and level, then a hard turn to the left (rolled in at about 90°/s), rolled out, and a climb.
	var turn := 0.0
	var want_bank := 0.0
	if t > 25.0 and t < 29.0:
		want_bank = deg_to_rad(-68.0)  # left wing down (roll left)
	var bank: float = move_toward(_jet[3], want_bank, deg_to_rad(90.0) * delta)
	_jet[3] = bank
	turn = -tan(bank) * 9.8 / _jet[0]  # coordinated: left bank turns it left (+heading)
	_jet[1] += turn * delta
	var want_pitch := deg_to_rad(18.0) if t > 29.5 else 0.0
	_jet[2] = move_toward(_jet[2], want_pitch, deg_to_rad(20.0) * delta)
	if t > 29.5:
		_jet[0] += 12.0 * delta
	var heading: float = _jet[1]
	var pitch: float = _jet[2]
	var fwd := Vector3(sin(heading) * cos(pitch), sin(pitch), cos(heading) * cos(pitch))
	jet.position += fwd * _jet[0] * delta
	# Body frame: +Z forward, banked about it (roll right +).
	var b := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, bank)
	jet.basis = b
	if t < 22.0:
		# Wait off stage until its pass.
		jet.position = Vector3(-60, 60, -700)
		_jet = [110.0, 0.0, 0.0, 0.0]


func _move_helos(delta: float) -> void:
	if t > 33.0:
		helo.start()
	# The lifter: from a hover, it speeds up along +Z, cruises and stops.
	var acc := 0.0
	if t > 44.0 and t < 49.0:
		acc = 2.5
	elif t >= 50.5 and _lift[0] > 0.0:
		acc = -3.0
	_lift[0] = maxf(_lift[0] + acc * delta, 0.0)
	lift.position += Vector3(0, 0, _lift[0] * delta)
	if t < 40.0:
		lift.position = LIFT_AT


# ------------------------------------------------------------------------------------------------- camera

func _camera() -> void:
	var who := _cam_only
	if who == "":
		who = "tank" if t < 12.0 else "drone" if t < 22.0 else "jet" if t < 32.0 else "helo" if t < 41.0 else "lift"
	match who:
		"tank":
			var p := tank.global_position
			_look(p + Vector3(-13, 5.5, 9) + Vector3(0, 0, minf(p.z, 20.0) * 0.2), p + Vector3(0, 2.0, 2))
		"drone":
			var p := drone.global_position
			_look(p + Vector3(-3.6, 1.3, 1.6).rotated(Vector3.UP, _drone[1] * 0.6), p + Vector3(0, 0.35, 0))
		"jet":
			var p := jet.global_position
			var back := -jet.basis.z
			_look(p + back * 38.0 + Vector3.UP * 9.0 + Vector3(jet.basis.x.x, 0, jet.basis.x.z) * 12.0, p + jet.basis.z * 6.0)
		"helo":
			var p := helo.global_position
			_look(p + Vector3(-62, 7, 52), p + Vector3(-12, 8, 6))
		"lift":
			var p := lift.global_position
			_look(p + Vector3(-110, -12, 40), p + Vector3(0, -12, 4))


func _look(from: Vector3, at: Vector3) -> void:
	cam.position = from
	cam.look_at(at)


# --------------------------------------------------------------------------------------------- the test

func _watch() -> void:
	_max("tank_gimbal", absf(tank.gimbal("FL").x))
	_max("tank_yaw", absf(tank.turret_yaw()))
	_max("tank_elev", tank.gun_elevation())
	_max("tank_recoil", (tank.part("barrel").position - tank.rest_of("barrel").origin).length())
	_max("drone_tilt", drone.pod_tilt(0))
	_max("drone_fan", drone.fan_rate())
	_max("jet_aileron", absf(jet.surface("aileron_L")))
	_max("jet_stab", -jet.surface("stabilator_L"))
	_max("jet_rudder", absf(jet.surface("rudder_L")))
	_max("jet_burner", jet.afterburner)
	_max("helo_power", helo.rotor_power())
	_max("helo_turned", absf(helo.rotor_angle("rotor_F")))
	_max("lift_tilt", lift.disc_tilt("rotor_F").x)
	_max("lift_swing", absf(lift.swing().x))
	if t > 22.0 and t < 22.5:
		_seen["drone_back"] = drone.pod_tilt(0)
	if t > 31.9 and t < 32.0:
		_seen["tank_aimed"] = 1.0 if tank.aimed() else 0.0
	if t > END - 0.1:
		_seen["swing_end"] = absf(lift.swing().x)


func _max(key: String, v: float) -> void:
	_seen[key] = maxf(_seen.get(key, -INF), v)


func _finish() -> void:
	if not _test:
		get_tree().quit()
		return
	var checks := [
		["tank thrusters gimbal", _seen.tank_gimbal > deg_to_rad(10.0)],
		["tank turret traverses onto the target", _seen.tank_yaw > deg_to_rad(20.0) and _seen.tank_aimed > 0.5],
		["tank gun elevates", _seen.tank_elev > deg_to_rad(1.0)],
		["tank barrel recoils", _seen.tank_recoil > 0.5],
		["drone pods tilt forward to fly", _seen.drone_tilt > deg_to_rad(45.0)],
		["drone pods back up hovering", absf(_seen.drone_back) < deg_to_rad(10.0)],
		["drone fans spin up", _seen.drone_fan > 5.0],
		["jet ailerons roll it", _seen.jet_aileron > deg_to_rad(10.0)],
		["jet stabilators pull in the turn", _seen.jet_stab > deg_to_rad(5.0)],
		["jet rudders move", _seen.jet_rudder > deg_to_rad(2.0)],
		["jet afterburners light in the climb", _seen.jet_burner > 0.3],
		["helicopter spools up", _seen.helo_power > 0.95 and _seen.helo_turned > 1.0],
		["lifter tilts its discs forward", _seen.lift_tilt > deg_to_rad(3.0)],
		["the elephant swings and settles", _seen.lift_swing > deg_to_rad(4.0) and _seen.swing_end < _seen.lift_swing],
	]
	var ok := true
	for c in checks:
		print("  %s %s" % ["ok  " if c[1] else "FAIL", c[0]])
		ok = ok and c[1]
	print(_seen)
	print("VEHICLE SHOWCASE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.5
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%04.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ------------------------------------------------------------------------------------------------- world

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.47, 0.68)
	sky_mat.sky_horizon_color = Color(0.72, 0.72, 0.68)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.42)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.16)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.66, 0.7)
	env.fog_density = 0.0008
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.3
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	ground.mesh = pm
	ground.material_override = Mats.ground()
	add_child(ground)
