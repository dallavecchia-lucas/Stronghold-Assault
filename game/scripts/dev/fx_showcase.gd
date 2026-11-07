extends Node3D
## The light and the effects (FX, Atmosphere) on the classic field (`--jungle`: the Jungle Keep), on a loop
## a camera circles: blasts from a grenade's to a heavy shell's, an air burst, flak, a field gun firing a shell
## over, a line of riflemen firing tracers into the ground, a rocket diving in, a salvo of shells landing, and
## a knocked-out gun burning.
##
##   godot --path game res://scenes/dev/fx_showcase.tscn                        # to watch it
##   godot --path game --resolution 1600x900 res://scenes/dev/fx_showcase.tscn -- --shots=DIR
##                                                                                # its stills, then quits
##   godot --path game --headless res://scenes/dev/fx_showcase.tscn -- --test    # FX SHOWCASE PASS / FAIL

## Where it all happens (the south field, clear of the mountain), and how long the loop runs.
const FIELD := Vector3(0.0, 0.0, 120.0)
const LOOP := 26.0
## [seconds into the loop, what]
const BEATS := [
	[1.0, "grenade"],
	[2.6, "mine"],
	[4.6, "heavy"],
	[7.6, "air"],
	[9.6, "flak"],
	[11.6, "cannon"],
	[13.6, "rifles"],
	[16.6, "rocket"],
	[18.6, "salvo"],
	[19.0, "burning"],
]
## Stills for --shots: [name, seconds in].
const SHOTS := [
	["grenade", 1.12], ["heavy_flash", 4.68], ["heavy_fireball", 4.95], ["heavy_smoke", 6.6], ["air_burst", 7.85],
	["flak", 9.75], ["cannon", 11.65], ["rifles", 14.3], ["rocket", 17.0], ["salvo", 21.4], ["burning", 24.0],
]

var level: LevelBuilder
var cam: Camera3D
var fx: FX
var shots_dir := ""
var testing := false
var _t := -1.0
var _loop := 0
var _beat := 0
var _shot := 0
var _yaw := 0.4
var _rifles := 0
var _rifle_cd := 0.0
var _salvo := 0
var _salvo_cd := 0.0
var _wreck: WreckSmoke
var _failed := false


func _ready() -> void:
	seed(7)
	var jungle := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg == "--test":
			testing = true
		elif arg == "--jungle":
			jungle = true
	level = JungleLevel.new() if jungle else LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the garrison's posts hold fire.
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	for t in level.aa_turrets:
		t.process_mode = Node.PROCESS_MODE_DISABLED
	fx = FX.of(self)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	_wreck = WreckSmoke.new()
	_wreck.size = 1.2
	add_child(_wreck)
	_wreck.global_position = _field(10.0, 8.0) + Vector3.UP * 0.6
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	level.navigation_ready.connect(func(): _t = 0.0, CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	_frame_camera(delta)
	if _t < 0.0:
		return
	_t += delta
	var loop := int(_t / LOOP)
	if loop != _loop:
		_loop = loop
		_beat = 0
		if testing:
			_finish_test()
			return
	var at := fmod(_t, LOOP)
	while _beat < BEATS.size() and at >= float(BEATS[_beat][0]):
		_do(BEATS[_beat][1])
		_beat += 1
	_tick_rifles(delta)
	_tick_salvo(delta)
	if _wreck.emitting and at > LOOP - 0.5:
		_wreck.emitting = false
	if shots_dir != "" and _shot < SHOTS.size() and _t >= float(SHOTS[_shot][1]):
		_save(SHOTS[_shot][0])
		_shot += 1
		if _shot >= SHOTS.size():
			get_tree().create_timer(0.5).timeout.connect(get_tree().quit)


## The camera circles the field slowly, a little above it.
func _frame_camera(delta: float) -> void:
	_yaw += delta * 0.1
	var center := FIELD + Vector3.UP * 4.0
	var p := center + Vector3(sin(_yaw), 0.0, cos(_yaw)) * 46.0
	p.y = LevelBuilder.ground_height(p) + 14.0
	cam.global_position = p
	cam.look_at(center)


func _do(what: String) -> void:
	match what:
		"grenade":
			fx.blast(_field(-8.0, 4.0), 1.6)
		"mine":
			fx.blast(_field(6.0, -3.0) + Vector3.UP * 0.3, 3.0)
		"heavy":
			fx.blast(_field(0.0, 0.0), 7.0)
		"air":
			fx.blast(FIELD + Vector3(-4.0, 22.0, 2.0), 4.0, NAN, true)
		"flak":
			for k in 5:
				var p := FIELD + Vector3(randf_range(-12.0, 12.0), randf_range(24.0, 32.0), randf_range(-10.0, 10.0))
				get_tree().create_timer(k * 0.22).timeout.connect(func(): Flak.burst_at(self, p))
		"cannon":
			var gun := _field(-20.0, 12.0) + Vector3.UP * 1.6
			var to := _field(8.0, -6.0)
			fx.muzzle_blast(gun, (to - gun).normalized() + Vector3.UP * 0.35, 1.2)
			_shell(gun, to, 5.0, 0.04)
		"rifles":
			_rifles = 24
			_rifle_cd = 0.0
		"rocket":
			var m := HomingMissile.new()
			m.team = GameConfig.TEAM_ATTACKER
			m.damage = 0.0
			m.splash = 3.5
			add_child(m)
			m.launch_at(_field(22.0, 22.0) + Vector3.UP * 2.0, Vector3(-0.3, 1.0, -0.3), _field(-4.0, -8.0))
		"salvo":
			_salvo = 6
			_salvo_cd = 0.0
		"burning":
			_wreck.emitting = true


func _tick_rifles(delta: float) -> void:
	if _rifles <= 0:
		return
	_rifle_cd -= delta
	while _rifles > 0 and _rifle_cd <= 0.0:
		_rifle_cd += 0.07
		_rifles -= 1
		var k := _rifles % 4
		var from := _field(-16.0 + k * 1.6, 16.0 - k * 0.8) + Vector3.UP * 1.4
		var aim := _field(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		Combat.fire_hitscan(self, from, aim, 0.01, 0.0, GameConfig.TEAM_ATTACKER, 1.0, [], from)
		Combat.spawn_muzzle_flash(self, from, aim - from, 1.0, k == 0)


func _tick_salvo(delta: float) -> void:
	if _salvo <= 0:
		return
	_salvo_cd -= delta
	while _salvo > 0 and _salvo_cd <= 0.0:
		_salvo_cd += 0.3
		_salvo -= 1
		_shell(_field(0.0, 70.0) + Vector3.UP * 3.0, _field(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0)), 6.0, 0.0)


## A harmless shell from `from` onto `to`, bursting `radius` wide.
func _shell(from: Vector3, to: Vector3, radius: float, trail: float) -> void:
	var s := Shell.new()
	s.team = GameConfig.TEAM_ATTACKER
	s.damage = 0.0
	s.radius = radius
	s.size = 0.3
	s.trail = trail
	add_child(s)
	s.launch(from, to)


## A point on the ground `x`, `z` m off the field's middle.
func _field(x: float, z: float) -> Vector3:
	var p := FIELD + Vector3(x, 0.0, z)
	p.y = LevelBuilder.ground_height(p)
	return p


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shots_dir, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot %s" % path)


## One loop run headless: every layer drew, the lights and the scorch marks came and went.
func _finish_test() -> void:
	for layer in [FX.SMOKE, FX.FIRE, FX.SPARK, FX.FLARE]:
		_check(fx._next[layer] > 0, "FX layer %d spawned particles" % layer)
	_check(not fx._lights.is_empty(), "blasts lit lights")
	_check(not fx._scorch.is_empty(), "blasts left scorch marks")
	_check(not fx._debris.is_empty(), "blasts threw debris")
	_check(level.atmosphere != null and level.atmosphere.env.volumetric_fog_enabled, "the atmosphere is up")
	print("FX SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("check ok: " if ok else "CHECK FAILED: ") + what)
	_failed = _failed or not ok
