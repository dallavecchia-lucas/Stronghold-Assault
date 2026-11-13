extends Node3D
## The stronghold's guns in motion, each on a stage of its own: a stretch of gun deck (the platform and the parapet,
## as LevelBuilder builds them) or of roof, with targets driven past below it. The guns are the game's own (MountedGun,
## AATurret, ArtilleryStation) with their rigs (TurretRig), doing what they do in a match:
##
##   sentry   the Orbital Sentry Gun, uncrewed and parked. A garrison soldier climbs into its seat: the radar dome runs
##            up and the gun starts to sweep. Targets come: it swings onto each (the seat riding the turret), runs its
##            barrels up and fires, cases flying; a long fight heats the barrels till they glow and smoke. It is
##            knocked out (the barrel drops), and repaired.
##   cannon   the Arctic Sentinel Cannon, the same way: its sensor head finds the target before the gun gets there,
##            every round drives the barrel back into the mantlet and throws a case, and its shells fly out and burst
##            where they land; a target over one of its own legs shows the barrel held clear of it.
##   bastion  the Sentinel Bastion, a flak gun that runs itself: sensor head and camera scanning, then both on the
##            target; its four barrels fire in turn, shells bursting by a drone overhead and by targets on the ground.
##   spire    the Sentinel Spire: searching, then onto a drone, a missile out of each cell in turn, the cells reloaded.
##   roof     the cannon on the south roof (the same gun, fired from a spotter's view): its crew lays it on a group far
##            out, the barrel raised for the range, and drops shells on it, then on a nearer one, the barrel lower.
##
##   godot --path game res://scenes/dev/turret_showcase.tscn [-- --gun=sentry]         # to watch it (all five in a row)
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/turret_showcase.tscn -- --test
##                                                         # prints and checks: TURRET SHOWCASE PASS / FAIL
##   godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/turret_showcase.tscn -- --gun=cannon \
##       --snap=9.2,14 --snap-out=/tmp/cannon                                           # just those frames
##   godot --path game --resolution 1280x720 --write-movie sentry.avi --fixed-fps 30 \
##       res://scenes/dev/turret_showcase.tscn -- --gun=sentry --video                  # its clip, then quits
##   python3 tools/video/cut_showcase.py ...   (or ffmpeg -i sentry.avi -c:v libx264 -crf 20 -pix_fmt yuv420p sentry.mp4)

const GUNS := ["sentry", "cannon", "bastion", "spire", "roof"]
## How far apart the stages stand (m), how high a deck and a roof are, and how long each gun's show runs (s).
const SPACING := 60.0
const DECK := 8.05
const ROOF := 15.05
const LENGTH := {"sentry": 44.0, "cannon": 42.0, "bastion": 36.0, "spire": 36.0, "roof": 28.0}

## A target on the field: a walking crate of a machine the guns take for an attacker.
class Dummy extends StaticBody3D:
	var team := GameConfig.TEAM_ATTACKER
	var hp := 200.0
	var target_radius := 0.6
	var velocity := Vector3.ZERO
	var camouflaged := false
	var dead_at := -1.0
	var hits := 0
	var _mat: StandardMaterial3D
	var _age := 0.0

	func _ready() -> void:
		add_to_group("damageable")
		add_to_group("attacker_units")
		collision_layer = GameConfig.LAYER_ATTACKERS
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.3, 1.9, 1.3)
		shape.shape = box
		shape.position.y = 0.95
		add_child(shape)
		_mat = Mats.flat(Color(0.5, 0.2, 0.12), 0.4, 0.6)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.5, 0.2)
		_mat.emission_energy_multiplier = 0.0
		add_child(Mats.box_mesh(Vector3(1.1, 1.0, 1.4), Vector3(0, 0.9, 0), _mat))
		add_child(Mats.box_mesh(Vector3(0.7, 0.5, 0.7), Vector3(0, 1.6, 0.1), _mat))
		for x in [-0.45, 0.45]:
			add_child(Mats.box_mesh(Vector3(0.25, 0.5, 0.9), Vector3(x, 0.25, 0), Mats.flat(Color(0.12, 0.12, 0.13), 0.5, 0.6)))

	func is_alive() -> bool:
		return hp > 0.0

	func is_flying() -> bool:
		return false

	func is_submerged() -> bool:
		return false

	func flash_spot() -> Vector3:
		return Vector3.INF

	func get_aim_point() -> Vector3:
		return global_position + Vector3.UP * 1.0

	func take_damage(amount: float, from_team: int) -> void:
		if hp <= 0.0 or from_team == team:
			return
		hp -= amount
		hits += 1
		_mat.emission_energy_multiplier = 2.5
		if hp <= 0.0:
			dead_at = _age
			remove_from_group("attacker_units")
			collision_layer = 0
			Combat.spawn_explosion(self, global_position + Vector3.UP, 2.5)
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector3(1.0, 0.25, 1.0), 0.25)
			tw.tween_interval(2.5)
			tw.tween_callback(queue_free)

	func _physics_process(delta: float) -> void:
		_age += delta
		_mat.emission_energy_multiplier = move_toward(_mat.emission_energy_multiplier, 0.0, delta * 10.0)
		if hp > 0.0:
			global_position += velocity * delta
			if velocity.length() > 0.1:
				rotation.y = atan2(velocity.x, velocity.z)


var which := ""
var video := false
var testing := false
var t := 0.0
var cam: Camera3D

var _snaps: Array = []
var _snap_out := "/tmp/turret"
## Per gun on show: {name, origin (the gun's foot, world), station, rig, beat (the next of its beats), dummies, crew}.
var _sets: Array = []
var _focus := 0
var _log: Array = []
var _checks := 0
var _failed := 0
var _watch := {}


func _ready() -> void:
	seed(11)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gun="):
			which = arg.get_slice("=", 1)
		elif arg == "--video":
			video = true
		elif arg == "--test":
			testing = true
		elif arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	_build_world()
	var names := GUNS if which == "" else [which]
	for k in names.size():
		_sets.append(_build_set(names[k], Vector3((k - (names.size() - 1) * 0.5) * SPACING, 0.0, 0.0)))
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_frame(0.0)


# ------------------------------------------------------------------------------------------------- the stage

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68)
	sky_mat.sky_horizon_color = Color(0.74, 0.74, 0.7)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.42)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.16)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.66, 0.7)
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(148.0), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.collision_layer = GameConfig.LAYER_WORLD
	ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	gs.shape = plane
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	gm.mesh = pm
	gm.material_override = Mats.ground()
	ground.add_child(gm)
	add_child(ground)


## A solid block: its mesh and its body.
func _block(size: Vector3, centre: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.position = centre
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.add_child(Mats.box_mesh(size, Vector3.ZERO, mat))
	add_child(body)


## One gun's stage at `at` (its wall's foot, the field out along +Z) and the gun on it.
func _build_set(gun: String, at: Vector3) -> Dictionary:
	var deck: bool = gun in ["sentry", "cannon"]
	var top := DECK if deck else ROOF
	var concrete := Mats.stone()
	var dark := Mats.dark_stone()
	# The wall, its top the deck (or the roof), its face at z = 0.
	_block(Vector3(26.0, top, 16.0), at + Vector3(0, top * 0.5, -8.0), dark)
	var foot := at + Vector3(0, top, 0)
	var set := {"name": gun, "beat": 0, "dummies": [], "t0": 0.0}
	var station: Node3D
	if deck:
		# The parapet along the edge, and the gun's platform against its inside face, just over its top.
		var inside := -0.4
		_block(Vector3(26.0, 1.1, 0.4), at + Vector3(0, top + 0.55, -0.2), concrete)
		var depth := LevelBuilder.DECK_PLATFORM_DEPTH
		var h := LevelBuilder.DECK_PLATFORM_H
		_block(Vector3(6.4, h, depth), at + Vector3(0, top + h * 0.5, inside - depth * 0.5), concrete)
		var mg := MountedGun.new()
		mg.kind = gun
		mg.model_path = Props.ORBITAL_SENTRY_GUN if gun == "sentry" else Props.ARCTIC_SENTINEL_CANNON
		mg.model_height = LevelBuilder.DECK_GUN_HEIGHT
		mg.pivot_height = 1.5
		mg.needs_crew = true
		var back: float = LevelBuilder.DECK_PARAPET_IN - float(LevelBuilder.DECK_GUN_OUT[gun])
		foot = at + Vector3(0, top + h, inside - back)
		mg.transform = Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), foot)
		add_child(mg)
		station = mg
	else:
		# A kerb along the roof's edge.
		_block(Vector3(26.0, 0.25, 0.3), at + Vector3(0, top + 0.125, -0.15), concrete)
		foot = at + Vector3(0, top, -2.4)
		var xf := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), foot)
		if gun == "bastion":
			var b := MountedGun.new()
			b.kind = "bastion"
			b.model_path = Props.SENTINEL_BASTION
			b.model_height = LevelBuilder.ROOF_BASTION_HEIGHT
			b.pivot_height = 1.5
			b.transform = xf
			add_child(b)
			station = b
		elif gun == "spire":
			var aa := AATurret.new()
			aa.transform = xf
			add_child(aa)
			station = aa
		else:
			var art := ArtilleryStation.new()
			art.needs_crew = true
			art.transform = xf
			add_child(art)
			station = art
	set.station = station
	set.rig = station.rig()
	set.origin = foot
	set.at = at
	if station.get("needs_crew"):
		# Its crew waits on the seat's side (the sentry gun's seat is on its left, the cannon's on its right).
		set.crew = _crew_for(station, foot + Vector3(2.6 if gun == "sentry" else -2.6, 0.0, -0.6))
	return set


## A garrison soldier standing by `station`, told off to crew it (it climbs into the seat when `board` says).
func _crew_for(station: Node3D, at: Vector3) -> GarrisonSoldier:
	var s := GarrisonSoldier.new()
	s.position = at
	add_child(s)
	s.gun = station
	station.crew = s
	s.rotation.y = PI
	s.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _board(set: Dictionary) -> void:
	var s: GarrisonSoldier = set.crew
	s.process_mode = Node.PROCESS_MODE_INHERIT
	s.job = GarrisonSoldier.Job.GUN
	s.arrived = true


## A target on the field in front of set `set`: `x` along the wall and `z` out from it (m), walking `velocity`.
func _dummy(set: Dictionary, x: float, z: float, hp: float, velocity := Vector3.ZERO) -> Dummy:
	var d := Dummy.new()
	d.hp = hp
	d.velocity = velocity
	d.position = set.at + Vector3(x, 0.0, z)
	add_child(d)
	set.dummies.append(d)
	return d


func _drone(set: Dictionary, radius: float, height: float, speed: float, angle: float, hp: float) -> TargetDrone:
	var d := TargetDrone.new()
	d.team = GameConfig.TEAM_ATTACKER
	d.centre = set.origin + Vector3(0, 0, 6.0)
	d.radius = radius
	d.height = height
	d.speed = speed
	d.angle = angle
	d.hp = hp
	add_child(d)
	set.dummies.append(d)
	return d


# ------------------------------------------------------------------------------------------------- the shows
# Each gun's beats: [seconds in, what]. _do works them.

const BEATS := {
	"sentry": [[1.5, "board"], [7.5, "walker"], [14.0, "close"], [20.5, "pack"], [33.0, "wreck"], [38.0, "repair"]],
	"cannon": [[1.5, "board"], [7.5, "walker"], [15.5, "over_leg"], [23.5, "pair"], [32.0, "wreck"], [37.0, "repair"]],
	"bastion": [[5.0, "drone"], [12.0, "walker"], [17.0, "pack"], [27.0, "wreck"], [31.5, "repair"]],
	"spire": [[5.0, "drone"], [17.0, "drone2"], [27.5, "wreck"], [32.0, "repair"]],
	"roof": [[1.5, "board"], [6.0, "group"], [17.0, "group2"]],
}


func _do(set: Dictionary, what: String) -> void:
	var gun: String = set.name
	_note(set, what)
	match what:
		"board":
			_board(set)
		"walker":
			# One comes in across the front, out on the field.
			_dummy(set, -16.0, 40.0, 150.0, Vector3(2.2, 0, -0.5))
		"close":
			# One right under the wall: the gun has to be laid steeply down.
			_dummy(set, 9.0, 17.0, 160.0, Vector3(-0.8, 0, 0))
		"over_leg":
			# Near, and off to the side one of the cannon's front legs lies on.
			_dummy(set, 9.5, 21.0, 150.0)
		"pair":
			_dummy(set, -22.0, 38.0, 110.0, Vector3(1.5, 0, 0))
			_dummy(set, 14.0, 44.0, 110.0, Vector3(-1.0, 0, -0.5))
		"pack":
			# A crowd of them: a long fight, the barrels heat.
			for k in 5:
				_dummy(set, -18.0 + k * 9.0, 34.0 + (k % 2) * 8.0, 75.0, Vector3(0.4 - 0.2 * k, 0, -0.6))
		"drone":
			_drone(set, 26.0, 13.0, 9.0, 2.2, 50.0 if gun == "spire" else 130.0)
		"drone2":
			_drone(set, 20.0, 20.0, -11.0, 5.2, 50.0)
		"group", "group2":
			# The first far out (the barrel raised for the range), the second nearer (the barrel lower).
			var x := -60.0 if what == "group" else 30.0
			var z := 125.0 if what == "group" else 50.0
			for k in 4:
				_dummy(set, x + (k % 2) * 2.4, z + (k / 2) * 2.4, 160.0)
		"wreck":
			set.station.take_damage(100000.0, GameConfig.TEAM_ATTACKER)
		"repair":
			set.station.set("_repair_cd" if set.station is MountedGun or set.station is ArtilleryStation else "_repair", 0.0)


func _physics_process(delta: float) -> void:
	t += delta
	for set in _sets:
		var beats: Array = BEATS[set.name]
		while set.beat < beats.size() and t >= float(beats[set.beat][0]):
			_do(set, beats[set.beat][1])
			set.beat += 1
		if testing:
			_observe(set)
	var length := 0.0
	for set in _sets:
		length = maxf(length, float(LENGTH[set.name]))
	if t >= length:
		if testing:
			_finish_test()
		elif video:
			get_tree().quit()
		else:
			get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	_frame(t)
	if not _snaps.is_empty():
		_snap()


# ------------------------------------------------------------------------------------------------- the camera
# Each gun's shots: [from (s), to (s), [distance, bearing (deg, 0: in front of the gun, 90: on its right, 180: behind
# it), height over the gun's foot, the height looked at] at the start, the same at the end, field of view].

const SHOTS := {
	"sentry": [
		[0.0, 7.5, [6.8, -38.0, 2.2, 1.1], [5.4, -62.0, 1.9, 1.1], 46.0],
		[7.5, 14.0, [5.2, 34.0, 1.7, 1.2], [4.6, 18.0, 1.5, 1.2], 44.0],
		[14.0, 20.5, [4.4, 95.0, 2.3, 1.1], [4.4, 120.0, 2.6, 1.0], 48.0],
		[20.5, 27.0, [3.4, 28.0, 1.5, 1.25], [3.0, -6.0, 1.4, 1.25], 42.0],
		[27.0, 33.0, [6.5, 200.0, 3.4, 1.0], [6.0, 172.0, 3.2, 1.0], 55.0],
		[33.0, 44.0, [5.6, 48.0, 2.0, 1.1], [5.0, 24.0, 1.7, 1.1], 46.0],
	],
	"cannon": [
		[0.0, 7.5, [8.0, 42.0, 2.5, 1.1], [6.6, 66.0, 2.1, 1.1], 46.0],
		[7.5, 15.5, [6.2, 152.0, 2.6, 1.3], [5.4, 128.0, 2.2, 1.3], 46.0],
		[15.5, 23.5, [5.6, -78.0, 1.6, 1.0], [5.4, -98.0, 1.9, 1.0], 46.0],
		[23.5, 32.0, [7.5, 196.0, 3.6, 1.2], [7.0, 164.0, 3.4, 1.2], 56.0],
		[32.0, 42.0, [6.8, 46.0, 2.2, 1.1], [6.0, 22.0, 1.9, 1.1], 46.0],
	],
	"bastion": [
		[0.0, 5.0, [6.2, 40.0, 2.4, 1.2], [5.2, 64.0, 2.1, 1.2], 46.0],
		[5.0, 11.5, [4.8, -30.0, 1.9, 1.3], [4.4, -12.0, 1.7, 1.3], 44.0],
		[11.5, 17.0, [4.6, 100.0, 2.2, 1.1], [4.6, 124.0, 2.5, 1.1], 48.0],
		[17.0, 27.0, [3.6, 30.0, 1.6, 1.2], [5.6, 190.0, 3.2, 1.1], 46.0],
		[27.0, 36.0, [5.6, 44.0, 2.2, 1.1], [5.0, 20.0, 1.9, 1.1], 46.0],
	],
	"spire": [
		[0.0, 5.0, [8.0, 36.0, 3.0, 1.7], [6.8, 58.0, 2.8, 1.7], 46.0],
		[5.0, 11.0, [7.6, 58.0, 3.4, 2.1], [6.6, 96.0, 3.0, 2.1], 52.0],
		[11.0, 17.0, [5.4, 28.0, 2.6, 1.9], [5.0, 8.0, 2.4, 1.9], 44.0],
		[17.0, 27.5, [7.4, 200.0, 4.2, 2.0], [6.4, 132.0, 3.2, 1.9], 54.0],
		[27.5, 36.0, [7.2, 42.0, 2.9, 1.6], [6.4, 20.0, 2.6, 1.6], 46.0],
	],
	"roof": [
		[0.0, 6.0, [7.6, 44.0, 2.6, 1.2], [6.6, 62.0, 2.3, 1.2], 46.0],
		[6.0, 17.0, [6.4, 40.0, 2.0, 1.5], [6.0, 16.0, 1.8, 1.6], 48.0],
		[17.0, 28.0, [8.6, 205.0, 4.2, 1.6], [8.0, 170.0, 3.8, 1.6], 56.0],
	],
}


func _frame(at: float) -> void:
	if _sets.is_empty():
		return
	if not video and which == "" and _snaps.is_empty():
		# All five in a row: from out over the field, panning along them.
		var span := (_sets.size() - 1) * SPACING
		cam.global_position = Vector3(sin(at * 0.08) * span * 0.35, 20.0, 46.0)
		cam.look_at(Vector3(sin(at * 0.08) * span * 0.35, 9.0, 0.0), Vector3.UP)
		return
	var set: Dictionary = _sets[_focus]
	var shots: Array = SHOTS[set.name]
	var shot: Array = shots[shots.size() - 1]
	for s in shots:
		if at < float(s[1]):
			shot = s
			break
	var k := clampf(inverse_lerp(float(shot[0]), float(shot[1]), at), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k) * 0.6 + k * 0.4
	var a: Array = shot[2]
	var b: Array = shot[3]
	var dist := lerpf(a[0], b[0], k)
	var bearing := deg_to_rad(lerpf(a[1], b[1], k))
	var origin: Vector3 = set.origin
	# The gun faces +Z here, so its right is world -X.
	var eye := origin + Vector3(-sin(bearing) * dist, lerpf(a[2], b[2], k), cos(bearing) * dist)
	cam.fov = float(shot[4])
	cam.global_position = eye
	cam.look_at(origin + Vector3.UP * lerpf(a[3], b[3], k), Vector3.UP)


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.4
	if t >= _snaps[0]:
		var at: float = _snaps[0]
		_snaps.pop_front()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.2f.png" % [_snap_out, at])
		if _snaps.is_empty():
			get_tree().quit()


# ------------------------------------------------------------------------------------------------- the test

func _note(set: Dictionary, what: String) -> void:
	print("%6.2f  %-8s %s" % [t, set.name, what])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


## Keeps what each gun did, as it goes, for _finish_test.
func _observe(set: Dictionary) -> void:
	var rig: TurretRig = set.rig
	var w: Dictionary = _watch.get(set.name, {})
	if w.is_empty():
		w = {"yaw_lo": 0.0, "yaw_hi": 0.0, "pitch_lo": 0.0, "pitch_hi": 0.0, "body": rig.part("Body").global_transform,
				"body_moved": 0.0, "seat_moved": 0.0, "spin": 0.0, "first_round_spin": -1.0, "recoil": 0.0, "droop": 0.0,
				"watch_from": -1.0, "sensor_lag": -1.0, "dome": 0.0, "low_over_leg": 0.0, "powered_at": -1.0,
				"wrecked": false, "back_up": false, "error": 0.0, "cells_empty": 0, "on_stop": INF, "spin_wrecked": INF,
				"heat": 0.0, "flak_recoil": 0.0, "flak_barrels": {}}
		if rig.has_seat():
			w.seat = rig.seat().origin
		_watch[set.name] = w
	w.yaw_lo = minf(w.yaw_lo, rig.yaw)
	w.yaw_hi = maxf(w.yaw_hi, rig.yaw)
	w.pitch_lo = minf(w.pitch_lo, rig.shown_pitch)
	w.pitch_hi = maxf(w.pitch_hi, rig.shown_pitch)
	var body: Transform3D = rig.part("Body").global_transform
	w.body_moved = maxf(w.body_moved, body.basis.get_rotation_quaternion().angle_to((w.body as Transform3D).basis.get_rotation_quaternion()))
	if rig.has_seat():
		w.seat_moved = maxf(w.seat_moved, rig.seat().origin.distance_to(w.seat))
	w.error = maxf(w.error, rig.aim_error())
	if rig.powered and w.powered_at < 0.0:
		w.powered_at = t
	if rig.wrecked:
		w.wrecked = true
		w.droop = maxf(w.droop, rig.get("_droop"))
		# How far off its stop the barrel lies (it falls there and stays).
		w.on_stop = absf(rig.shown_pitch - float(rig.get("_droop")) - rig.min_pitch(rig.yaw))
		if rig is GatlingRig:
			w.spin_wrecked = (rig as GatlingRig).spin_rate
	elif w.wrecked and float(rig.get("_droop")) < 0.01:
		w.back_up = true
	if rig is GatlingRig:
		var g := rig as GatlingRig
		w.spin = maxf(w.spin, g.spin_rate)
		w.heat = maxf(w.heat, g.barrel_heat)
		if g.rounds > 0 and w.first_round_spin < 0.0:
			w.first_round_spin = g.spin_rate
	if rig is BastionRig:
		var b := rig as BastionRig
		w.flak_recoil = maxf(w.flak_recoil, rig.part("barrels").position.distance_to(rig.rest_of("barrels").origin))
		w.flak_barrels[b.get("_barrel")] = true
		w.heat = maxf(w.heat, b.barrel_heat)
	if rig is CannonRig:
		w.recoil = maxf(w.recoil, rig.part("barrel").position.distance_to(rig.rest_of("barrel").origin))
		# How low the barrel was shown while the turret stood over a front leg.
		if absf(absf(rig.yaw) - CannonRig.LEG_AT) < deg_to_rad(4.0):
			w.low_over_leg = minf(w.low_over_leg, rig.shown_pitch)
	if rig is SpireRig:
		w.cells_empty = maxi(w.cells_empty, SpireRig.CELLS - (rig as SpireRig).loaded())
	if rig.has_part("dome"):
		w.dome = maxf(w.dome, absf(rig.get("_dome_v")))
	if rig.has_part("sensor") and w.sensor_lag < 0.0 and rig.watch.is_finite():
		# The first target: how long the sensor head takes to get onto it.
		if w.watch_from < 0.0:
			w.watch_from = t
		if rig.sensors_on(0.08):
			w.sensor_lag = t - float(w.watch_from)


func _finish_test() -> void:
	set_physics_process(false)
	print("\nTURRET SHOWCASE: what each gun did")
	for set in _sets:
		var rig: TurretRig = set.rig
		var w: Dictionary = _watch[set.name]
		var gun: String = set.name
		print("%s: traverse %.0f..%.0f deg, elevation %.0f..%.0f deg" % [gun, rad_to_deg(w.yaw_lo), rad_to_deg(w.yaw_hi),
				rad_to_deg(w.pitch_lo), rad_to_deg(w.pitch_hi)])
		_check(w.body_moved < 0.001, "%s: its base stayed put while the turret turned (%.1f deg of traverse)" % [gun,
				rad_to_deg(w.yaw_hi - w.yaw_lo)])
		_check(w.yaw_hi - w.yaw_lo > deg_to_rad(40.0), "%s: the turret traversed" % gun)
		_check(w.pitch_hi - w.pitch_lo > deg_to_rad(10.0), "%s: the gun elevated on its trunnion" % gun)
		if rig.has_seat():
			_check(w.seat_moved > 0.5, "%s: the crew's seat rode the turret (%.2f m)" % [gun, w.seat_moved])
			var crew: GarrisonSoldier = set.crew
			_check(crew.at_post(), "%s: its crew is in the seat" % gun)
			_check(crew.global_position.distance_to(rig.seat().origin) < 1.2, "%s: the crew sits where the seat is" % gun)
		if rig is GatlingRig:
			var g := rig as GatlingRig
			_check(g.rounds > 20, "%s: fired (%d rounds)" % [gun, g.rounds])
			_check(w.spin > GatlingRig.SPIN * 0.95, "%s: the barrels ran up to speed (%.0f rev/s)" % [gun, w.spin / TAU])
			_check(w.first_round_spin >= GatlingRig.SPIN * GatlingRig.READY - 0.01,
					"%s: no round left before the barrels were turning (%.0f rev/s at the first)" % [gun, w.first_round_spin / TAU])
			_check(w.spin_wrecked < 1.0, "%s: knocked out, the barrels ran down and stopped" % gun)
			_check(w.heat > 0.3, "%s: the barrels heated as they fired (%.2f at their hottest)" % [gun, w.heat])
		if rig is BastionRig:
			var b := rig as BastionRig
			_check(b.rounds > 20, "bastion: fired (%d shells)" % b.rounds)
			_check(w.flak_recoil > BastionRig.RECOIL * 0.8, "bastion: its barrels recoiled in their collar (%.2f m)" % w.flak_recoil)
			_check(w.flak_barrels.size() == 4, "bastion: all four barrels fired in turn")
			_check(w.pitch_hi > deg_to_rad(10.0), "bastion: it elevated onto the drone (%.0f deg)" % rad_to_deg(w.pitch_hi))
		if rig is CannonRig:
			var c := rig as CannonRig
			_check(c.rounds >= 2, "%s: fired (%d rounds)" % [gun, c.rounds])
			var travel: float = CannonRig.RECOIL
			_check(absf(w.recoil - travel) < 0.02, "%s: the barrel recoiled its %.2f m (%.2f)" % [gun, travel, w.recoil])
			_check(c.in_battery(), "%s: the barrel ran out again" % gun)
		if gun == "cannon":
			_check(w.low_over_leg > CannonRig.OVER_LEG - 0.02, "cannon: the barrel was held clear of its leg (%.0f deg over it)"
					% rad_to_deg(w.low_over_leg))
			_check(w.pitch_lo < CannonRig.OVER_LEG - 0.05, "cannon: between its legs it went lower (%.0f deg)" % rad_to_deg(w.pitch_lo))
		if rig.has_part("dome"):
			_check(w.dome > TurretRig.DOME_RATE * 0.9, "%s: the radar dome turned" % gun)
		if rig.has_part("sensor") and gun != "roof":
			_check(w.sensor_lag >= 0.0 and w.sensor_lag < 1.0, "%s: the sensor head was on its target %.2f s after it showed" % [gun,
					w.sensor_lag])
		if rig is SpireRig:
			var s := rig as SpireRig
			_check(s.launched >= 4, "spire: launched (%d missiles)" % s.launched)
			_check(w.cells_empty >= 2, "spire: cells stood empty after their launches (%d at once)" % w.cells_empty)
			_check(set.station.fired == s.launched, "spire: every missile left from a cell")
		if gun == "roof":
			var hit := 0
			for d in set.dummies:
				if not is_instance_valid(d) or d.hp < 160.0:
					hit += 1
			_check(hit >= 6, "roof cannon: its shells landed on the groups (%d of %d hit)" % [hit, set.dummies.size()])
			_check(w.pitch_hi - w.pitch_lo > deg_to_rad(8.0), "roof cannon: the far group took a higher barrel than the near one (%.0f..%.0f deg)"
					% [rad_to_deg(w.pitch_lo), rad_to_deg(w.pitch_hi)])
		else:
			_check(w.wrecked and w.droop > deg_to_rad(3.0) and w.on_stop < deg_to_rad(1.0),
					"%s: knocked out, the barrel dropped onto its stop (%.0f deg down)" % [gun, rad_to_deg(w.droop)])
			_check(w.back_up and not rig.wrecked, "%s: repaired, it came back up" % gun)
			var dead := 0
			for d in set.dummies:
				if not is_instance_valid(d) or not d.is_alive():
					dead += 1
			_check(dead >= 2, "%s: destroyed its targets (%d of %d)" % [gun, dead, set.dummies.size()])
	print("TURRET SHOWCASE %s (%d checks, %d failed)" % ["PASS" if _failed == 0 else "FAIL", _checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
