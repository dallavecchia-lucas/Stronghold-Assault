class_name TurretRig
extends "res://scripts/vehicles/vehicle_rig.gd"
## The visual side of one of the stronghold's guns (the Orbital Sentry Gun, the Arctic Sentinel Cannon, the Sentinel
## Bastion and the Sentinel Spire): loads its model and moves its parts, each on its own. The models come from
## tools/gltf/rig_turrets.py (see that script for the parts): the base stays put, the `turret` turns on its ring with
## whatever rides it (the crew's seat, the drum), the `gun` (the Spire's `pod`) elevates on its trunnion, and on top of
## those every rig works what its own gun has (barrels that spin up, a barrel that recoils, missile cells, sensor
## heads, a radar dome).
##
## The rig faces -Z at rest, like the gun it hangs under (the model's front is +Z; it is turned about here). Whoever
## owns it holds the aim and hands it over every tick (set_aim: the traverse and the elevation the gun's own logic
## works with, rad, left and up positive). The rig shows them as far as the gun can really go: it will not lay its
## barrel through its own legs or the floor it stands on (min_pitch), whatever the aim asks.
##
## What the rig does on its own:
##   sensors  a sensor head (`sensor` pans, `optic` tilts) scans its arc while the gun is `powered` and nothing is
##            `watch`ed, and holds the watched point when one is (it gets there before the gun does: a light head on
##            fast servos); a radar `dome` turns while the gun is powered and runs down when it is not.
##   wrecked  knocked out, the gun's elevating gear lets go: the barrel drops onto its stop and bounces there, the
##            turret is left askew on its ring, the sensors hang their heads and the dome runs down. Repaired, it all
##            comes back up.
##   kick     each rig's recoil goes through `_kick`: the gun jumps on its trunnion and the turret rocks on its ring
##            (damped springs), the model shakes.

const Casings := preload("res://scripts/turrets/turret_casings.gd")
## Each gun's rig, by its model (create()).
const RIGS := {
	"res://assets/defenses/orbital_sentry_gun/orbital_sentry_gun.glb": "res://scripts/turrets/sentry_gun_rig.gd",
	"res://assets/defenses/arctic_sentinel_cannon/arctic_sentinel_cannon.glb": "res://scripts/turrets/cannon_rig.gd",
	"res://assets/defenses/sentinel_bastion/sentinel_bastion.glb": "res://scripts/turrets/bastion_rig.gd",
	"res://assets/defenses/sentinel_spire/sentinel_spire.glb": "res://scripts/turrets/spire_rig.gd",
}

## The sensor head's servos: how fast it turns and nods (rad/s) and picks up speed (rad/s²), how far it nods (rad).
const SENSOR_RATE := 4.0
const SENSOR_ACCEL := 22.0
const SENSOR_TILT_MIN := deg_to_rad(-38.0)
const SENSOR_TILT_MAX := deg_to_rad(32.0)
## Scanning: how far it sweeps either way (rad) and how long a sweep takes (s); where it looks, a little down (rad).
const SCAN_ARC := deg_to_rad(70.0)
const SCAN_PERIOD := 9.0
const SCAN_TILT := deg_to_rad(-9.0)
## The radar dome (rad/s), and how fast it runs up and down (rad/s²).
const DOME_RATE := TAU * 0.55
const DOME_ACCEL := 2.2
## Knocked out: how far the turret is left leaning on its ring (rad), the spring that drops the barrel onto its stop
## (1/s², 1/s), where the sensors hang (rad).
const WRECK_LEAN := deg_to_rad(4.5)
const DROOP_SPRING := 38.0
const DROOP_DAMP := 5.0
const WRECK_TILT := deg_to_rad(-34.0)

## How tall the gun stands (m); 0: as modelled (model_height()).
var height := 0.0
## Running (crewed, or it runs itself): the sensors scan and the dome turns. Off: they stop where they rest.
var powered := true
## Knocked out (see the top).
var wrecked := false
## 0..1: how hot the barrels are (the owner's heat): they glow, and smoke when it is high.
var heat := 0.0
## The world point the sensors hold; INF: nothing, they scan.
var watch := Vector3.INF

## The aim as the owner holds it (set_aim), and as the rig shows it (shown_pitch: held off the legs and the floor).
var yaw := 0.0
var pitch := 0.0
var shown_pitch := 0.0

## The recoil's springs: the gun's jump on its trunnion (rad) and the turret's rock on its ring (rad about its own X
## and Z), each with its rate.
var _jump := 0.0
var _jump_v := 0.0
var _rock := Vector2.ZERO
var _rock_v := Vector2.ZERO
## How far back the gun sits in its cradle (m) and its rate (a gatling's hammering).
var _back := 0.0
var _back_v := 0.0
## Knocked out: the barrel's drop below the aim (rad, a spring onto the stop) and the turret's lean (0..1).
var _droop := 0.0
var _droop_v := 0.0
var _lean := 0.0
var _lean_dir := Vector2(1.0, 0.4)
## The sensor head (pan, tilt) with its rates, and its scan's clock.
var _pan := 0.0
var _pan_v := 0.0
var _tilt := 0.0
var _tilt_v := 0.0
var _scan_t := 0.0
var _dome := 0.0
var _dome_v := 0.0
var _casings: Casings
var _glow: Array[StandardMaterial3D] = []
## What the parts were last posed from (one number: nothing moved, nothing is posed again).
var _posed := NAN
var _glow_shown := -1.0


## The rig of the gun whose model is `path`, `p_height` tall (0: as modelled). Null when `path` is no turret's.
static func create(path: String, p_height := 0.0) -> TurretRig:
	if not RIGS.has(path):
		return null
	var rig: TurretRig = (load(RIGS[path]) as GDScript).new()
	rig.height = p_height
	return rig


## How tall the model was cut (m: tools/gltf/rig_turrets.py HEIGHT). Each rig says.
func model_height() -> float:
	return 2.0


## The part that elevates (the Spire's is its pod).
func _gun_part() -> String:
	return "gun"


## The lowest the gun can really be laid with its turret at `at_yaw` (rad): clear of its own legs, of the floor and of
## the parapet it stands behind. Each rig says.
func min_pitch(_at_yaw: float) -> float:
	return -PI


## The highest.
func max_pitch() -> float:
	return PI * 0.5


func _build() -> void:
	follow_motion = false
	# The model's front is +Z: turned about, the rig faces -Z like the gun it hangs under.
	model.rotation.y = PI
	if height > 0.0:
		model.scale = Vector3.ONE * (height / model_height())
	_scan_t = randf() * SCAN_PERIOD
	_dome = randf() * TAU
	_lean_dir = Vector2.from_angle(randf() * TAU)
	shown_pitch = pitch
	_setup()
	_pose()


## Hook for the rigs: called once the model is in (flames, blurs, materials).
func _setup() -> void:
	pass


## Hook for the rigs: every frame, before the parts are posed.
func _animate(_delta: float) -> void:
	pass


## Hands the rig the aim (rad): the traverse (left positive) and the elevation.
func set_aim(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch


## Sets the aim and everything that follows it at once (no slewing in: a gun put down already aimed).
func snap() -> void:
	shown_pitch = clampf(pitch, min_pitch(yaw), max_pitch())
	if model:
		_pose()


## A marker's world transform, square and unscaled (a rig stood taller than its model scales its markers too).
func spot(marker_name: String) -> Transform3D:
	var n: Node3D = _parts.get(marker_name)
	if n == null:
		return global_transform
	var xf := n.global_transform
	return Transform3D(xf.basis.orthonormalized(), xf.origin)


## Where the round leaves: the muzzle's world transform, +Z out of the barrel.
func muzzle() -> Transform3D:
	return spot("muzzle")


func has_seat() -> bool:
	return has_part("seat")


## The crew's seat: the middle of the seat pan's top (world), -Z the way the one sitting in it faces, upright. It
## rides the turret.
func seat() -> Transform3D:
	var xf := spot("seat")
	var facing := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	return Transform3D(Basis.looking_at(facing, Vector3.UP), xf.origin)


## How far the barrel as shown is off the aim the owner holds (rad): more than nothing only where the gun cannot go.
func aim_error() -> float:
	return absf(shown_pitch - pitch)


## A round's kick: the gun jumps `jump` rad on its trunnion, the turret rocks back `rock` rad on its ring and the gun
## is driven `back` m into its cradle.
func _kick(jump: float, rock: float, back := 0.0) -> void:
	_jump_v += jump * 24.0
	_rock_v += Vector2(-rock, randf_range(-0.35, 0.35) * rock) * 22.0
	_back_v += back * 60.0


func _process(delta: float) -> void:
	# Out of sight (its owner shows the player's own gun instead), it rests.
	if model == null or not is_visible_in_tree():
		return
	_springs(delta)
	_sensors(delta)
	_animate(delta)
	_pose()
	if _casings:
		_casings.step(delta)


func _springs(delta: float) -> void:
	# The gun's jump and the turret's rock: struck by _kick, they swing back and die away. Stiff springs: they are
	# stepped in SPRING_STEP slices (a long frame stepped whole would throw them off to infinity).
	var steps := spring_steps(delta)
	var h := spring_span(delta) / steps
	for _i in steps:
		_jump_v += (-_jump * 520.0 - _jump_v * 26.0) * h
		_jump += _jump_v * h
		_rock_v += (-_rock * 300.0 - _rock_v * 16.0) * h
		_rock += _rock_v * h
		_back_v += (-_back * 900.0 - _back_v * 42.0) * h
		_back += _back_v * h
	if not is_finite(_jump + _jump_v + _rock.x + _rock.y + _rock_v.x + _rock_v.y + _back + _back_v + _droop + _droop_v):
		_jump = 0.0
		_jump_v = 0.0
		_rock = Vector2.ZERO
		_rock_v = Vector2.ZERO
		_back = 0.0
		_back_v = 0.0
		_droop = 0.0
		_droop_v = 0.0
	# Died away, they are at rest (and the gun is not posed again for a hair's breadth).
	if absf(_jump) < 1e-5 and absf(_jump_v) < 1e-4:
		_jump = 0.0
		_jump_v = 0.0
	if _rock.length_squared() < 1e-10 and _rock_v.length_squared() < 1e-8:
		_rock = Vector2.ZERO
		_rock_v = Vector2.ZERO
	if absf(_back) < 1e-6 and absf(_back_v) < 1e-5:
		_back = 0.0
		_back_v = 0.0
	# The elevation the gun can really reach, followed fast (the stop is a hard one, not a servo).
	var lowest := min_pitch(yaw)
	var want := clampf(pitch, lowest, max_pitch())
	shown_pitch = move_toward(shown_pitch, want, delta * 4.0) if absf(shown_pitch - want) > 0.0005 else want
	# Knocked out: the barrel falls from wherever it was onto its stop and bounces; repaired, it is wound back up.
	if wrecked:
		var fall := shown_pitch - lowest
		for _i in steps:
			_droop_v += ((fall - _droop) * DROOP_SPRING - _droop_v * DROOP_DAMP) * h
			_droop += _droop_v * h
			if _droop > fall:  # on the stop
				_droop = fall
				_droop_v = -_droop_v * 0.35
		_lean = minf(_lean + delta * 6.0, 1.0)
	else:
		_droop = move_toward(_droop, 0.0, delta * 0.5)
		_droop_v = 0.0
		_lean = move_toward(_lean, 0.0, delta * 0.6)


func _sensors(delta: float) -> void:
	if has_part("dome"):
		var rate := DOME_RATE if powered and not wrecked else 0.0
		_dome_v = move_toward(_dome_v, rate, DOME_ACCEL * delta)
		_dome = fposmod(_dome + _dome_v * delta, TAU)
	if not has_part("sensor"):
		return
	var pan := 0.0
	var tilt := SCAN_TILT
	if wrecked:
		pan = _pan
		tilt = WRECK_TILT
	elif not powered:
		tilt = deg_to_rad(-16.0)
	elif watch.is_finite():
		var look := _sensor_angles(watch)
		pan = look.x
		tilt = look.y
	else:
		# Scanning: a slow sweep either way with a dwell at each end, nodding a little as it goes.
		_scan_t += delta
		var s := sin(_scan_t * TAU / SCAN_PERIOD)
		pan = SCAN_ARC * clampf(s * 1.35, -1.0, 1.0)
		tilt = SCAN_TILT + deg_to_rad(5.0) * sin(_scan_t * TAU / (SCAN_PERIOD * 0.37))
	tilt = clampf(tilt, SENSOR_TILT_MIN, SENSOR_TILT_MAX)
	var rate := SENSOR_RATE * (0.35 if wrecked or not powered else 1.0)
	var p := slew(_pan, _pan_v, _pan + wrapf(pan - _pan, -PI, PI), rate, SENSOR_ACCEL, delta)
	_pan = p.x
	_pan_v = p.y
	var t := slew(_tilt, _tilt_v, tilt, rate, SENSOR_ACCEL, delta)
	_tilt = t.x
	_tilt_v = t.y


## The pan and tilt (rad) that point the sensor head at `point` (world), with the turret where it is.
func _sensor_angles(point: Vector3) -> Vector2:
	var head: Node3D = _parts["sensor"]
	var frame := (head.get_parent() as Node3D).global_transform * Transform3D(_rest["sensor"].basis, _rest["sensor"].origin)
	var local := frame.affine_inverse() * point
	if has_part("optic"):
		local -= _rest["optic"].origin
	return Vector2(atan2(local.x, local.z), atan2(local.y, Vector2(local.x, local.z).length()))


## Whether the sensor head is on the point it watches (within `within` rad).
func sensors_on(within := 0.06) -> bool:
	if not has_part("sensor") or not watch.is_finite():
		return false
	var look := _sensor_angles(watch)
	return absf(wrapf(look.x - _pan, -PI, PI)) < within and absf(clampf(look.y, SENSOR_TILT_MIN, SENSOR_TILT_MAX) - _tilt) < within


func _pose() -> void:
	# Most guns stand still most of the time: nothing moved, nothing to do.
	var elevation := shown_pitch - _droop + _jump
	var now := yaw * 1.13 + elevation * 2.31 + _back * 37.0 + _rock.x * 51.0 + _rock.y * 73.0 + _lean * 1.7 + _dome * 0.71 \
			+ _pan * 0.53 + _tilt * 0.37
	if now == _posed:
		return
	_posed = now
	var lean := _lean_dir * (WRECK_LEAN * _lean)
	spin("turret", yaw, _rock + lean)
	var gun := _gun_part()
	if _parts.has(gun):
		# The elevating mass turns about its own X (a positive angle raises the muzzle) and sits back along its bore
		# (its own +Z is the breech end).
		var rest: Transform3D = _rest[gun]
		var basis := rest.basis * Basis(Vector3.RIGHT, elevation)
		(_parts[gun] as Node3D).transform = Transform3D(basis, rest.origin + basis.z * maxf(_back, -0.01))
	if has_part("dome"):
		spin("dome", _dome)
	if has_part("sensor"):
		spin("sensor", _pan)
		if has_part("optic"):
			hinge("optic", _tilt)


## The rig's spent cases (made on first use): `capacity` of them alive at once, each `radius` thick and `length` long.
func _cases(capacity: int, radius: float, length: float) -> Casings:
	if _casings == null:
		_casings = Casings.new()
		_casings.setup(capacity, radius, length)
		add_child(_casings)
	return _casings


## Throws a spent case out of the `eject` port (along its +Z, `speed` m/s), to fall on the floor the gun stands on.
func _eject(speed: float) -> void:
	if _casings == null or not has_part("eject"):
		return
	var port := spot("eject")
	_casings.throw(port, port.basis.z * speed * randf_range(0.8, 1.2) + Vector3.UP * randf_range(0.4, 1.1),
			global_position.y, Vector2(global_position.x, global_position.z))


## Gives the named parts a material of their own that can glow (hot barrels); set_glow lights it.
func _glowing(parts: Array) -> void:
	for part_name in parts:
		var mi := _parts.get(part_name) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null:
				continue
			var mat := base.duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.32, 0.06)
			mat.emission_energy_multiplier = 0.0
			mi.set_surface_override_material(s, mat)
			_glow.append(mat)


## 0..1: how hot the glowing parts show (dull red, then orange).
func _set_glow(k: float) -> void:
	k = snappedf(clampf(k, 0.0, 1.0), 0.01)
	if k == _glow_shown:
		return
	_glow_shown = k
	for mat in _glow:
		mat.emission_energy_multiplier = 3.2 * k * k
		mat.emission = Color(1.0, 0.18 + 0.3 * k, 0.03 + 0.1 * k)


## The springs' time step: the longest slice they are stepped in (s), and the most slices a frame is cut into (a frame
## longer than that many is taken as that long: the springs lag a hitch rather than blow up in it).
const SPRING_STEP := 1.0 / 120.0
const SPRING_STEPS := 8


## How many slices to step the springs through a frame of `delta` s in.
static func spring_steps(delta: float) -> int:
	return clampi(ceili(delta / SPRING_STEP), 1, SPRING_STEPS)


## How much of a frame of `delta` s the springs are stepped through.
static func spring_span(delta: float) -> float:
	return clampf(delta, 0.0, SPRING_STEP * SPRING_STEPS)


## A servo: moves `angle` (going at `rate`) toward `target`, never faster than `top` (rad/s) and never gaining or
## losing speed quicker than `accel` (rad/s²), so it runs up, runs and brakes to a stop on the target. Returns the new
## (angle, rate).
static func slew(angle: float, rate: float, target: float, top: float, accel: float, delta: float) -> Vector2:
	var err := target - angle
	# The fastest it may be going and still stop on the target.
	var want := clampf(signf(err) * sqrt(2.0 * accel * absf(err)), -top, top)
	rate = move_toward(rate, want, accel * delta)
	var step := rate * delta
	# There within this step (or past it, on a long frame): it stops on the target, never the far side of it.
	if step * err > 0.0 and absf(step) >= absf(err):
		return Vector2(target, 0.0)
	return Vector2(angle + step, rate)
