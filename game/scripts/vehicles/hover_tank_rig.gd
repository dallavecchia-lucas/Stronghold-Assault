class_name HoverTankRig
extends VehicleRig
## The defenders' Iron Vanguard hover tank (assets_src/defenders/iron_vanguard, cut by tools/gltf/rig_vehicles.py):
## 10 m long with its gun forward, 6 m wide. It rides HOVER over the ground on four hover thrusters under the hull
## (thruster_FL/FR/RL/RR), their blue jets (jet_*) pushing down. The thrusters gimbal: they lean the jets back to
## speed it up, forward to brake, out to the side to slide it, and opposite ways front and rear to turn it; the two
## rear vents (booster_L/R) burn with the forward push. The hull rides the air: it bobs, sits back on its tail as it
## speeds up, dips its nose braking and rolls out of its turns.
##
## The turret turns onto the aim (aim(), traverse TRAVERSE) and the gun elevates onto it (ELEVATE, between DEPRESSION
## and ELEVATION); fire() kicks the barrel back into the gun (RECOIL), and it runs out again. muzzle() is where the
## shell leaves. Like MuleGun, aimed() says when it is on the aim.

const MODEL := "res://assets/defenders/iron_vanguard/iron_vanguard.glb"
## Ride height over the ground (m) and its bob (m).
const HOVER := 0.7
const BOB := 0.06
## Turret traverse and gun elevation rates (rad/s), the gun's limits (rad).
const TRAVERSE := deg_to_rad(40.0)
const ELEVATE := deg_to_rad(25.0)
const DEPRESSION := deg_to_rad(-8.0)
const ELEVATION := deg_to_rad(28.0)
## How close to its aim (rad) the gun must be to fire.
const AIMED := deg_to_rad(1.5)
## The barrel's kick on a shot (m) and how fast it runs out again (m/s).
const RECOIL := 0.8
const RUN_OUT := 1.6
## Thruster gimbal: the most it leans (rad) and how fast (rad/s); the rig's acceleration that leans it all the way.
const GIMBAL := deg_to_rad(22.0)
const GIMBAL_RATE := deg_to_rad(90.0)
const FULL_ACCEL := 4.0
## How the hull rides its acceleration (rad per m/s²; most).
const PITCH_PER_ACCEL := 0.012
const ROLL_PER_ACCEL := 0.012
const TILT_MAX := deg_to_rad(5.0)

const PADS := ["FL", "FR", "RL", "RR"]

## Inputs (when not following its motion): the push (-1..1 in its own frame: x left, z forward), the turn (-1..1,
## left +) and the hover thrusters' power (0..1).
var drive := Vector2.ZERO
var turn := 0.0
var lift := 0.7

var _aim := Vector3.INF
var _yaw := 0.0
var _pitch := 0.0
var _kick := 0.0
var _gimbal := {}
var _tilt := Vector2.ZERO
var _jets: Array[ThrusterFlame] = []
var _boosters: Array[ThrusterFlame] = []
## The turret's pivot in the model's frame and the gun's trunnion in the turret's.
var _turret_pivot := Vector3.ZERO
var _gun_pivot := Vector3.ZERO
var _recoil_dir := Vector3.BACK


func _model_path() -> String:
	return MODEL


func _build() -> void:
	model.position.y = HOVER
	for pad in PADS:
		var f := ThrusterFlame.new()
		f.length = 1.3
		f.radius = 0.42
		f.color = Color(0.35, 0.9, 2.8)
		f.light_range = 3.5
		var jet := part("jet_" + pad)
		if jet:
			jet.add_child(f)
		_jets.append(f)
	for side in ["L", "R"]:
		var f := ThrusterFlame.new()
		f.length = 2.2
		f.radius = 0.28
		f.color = Color(0.4, 1.0, 2.8)
		var b := part("booster_" + side)
		if b:
			b.add_child(f)
		_boosters.append(f)
	_turret_pivot = rest_of("turret").origin
	# The trunnion in the turret's frame, and the way the barrel kicks (back along it, in the gun's frame).
	_gun_pivot = rest_of("gun").origin
	if has_part("muzzle"):
		_recoil_dir = -(rest_of("barrel").basis * rest_of("muzzle").basis.z).normalized()


## Turns the turret and the gun onto `point` (world).
func aim(point: Vector3) -> void:
	_aim = point


## Turns the turret back to the front and the gun level.
func stow() -> void:
	_aim = Vector3.INF


## True once the gun is on its aim.
func aimed() -> bool:
	if _aim == Vector3.INF:
		return false
	var want := _want()
	return absf(angle_difference(_yaw, want.x)) < AIMED and absf(_pitch - want.y) < AIMED


## The barrel kicks back and runs out again.
func fire() -> void:
	_kick = RECOIL


## The muzzle's world transform as of now; basis.z points out of the barrel.
func muzzle() -> Transform3D:
	return marker("muzzle")


## The turret's yaw (rad, left +) and the gun's elevation (rad, up +) as of now.
func turret_yaw() -> float:
	return _yaw


func gun_elevation() -> float:
	return _pitch


## A hover thruster's gimbal as of now (rad: about its X, about its Z).
func gimbal(pad: String) -> Vector2:
	return _gimbal.get(pad, Vector2.ZERO)


func _process(delta: float) -> void:
	_track(delta, 0.3)
	if follow_motion:
		drive = Vector2(clampf(local_accel.x / FULL_ACCEL, -1.0, 1.0), clampf(local_accel.z / FULL_ACCEL, -1.0, 1.0))
		# Cruising, it keeps pushing a little against the drag.
		drive.y = clampf(drive.y + local_velocity.z * 0.04, -1.0, 1.0)
		turn = clampf(local_spin.y * 1.5, -1.0, 1.0)
		lift = clampf(0.65 + absf(local_accel.y) * 0.1 + drive.length() * 0.2, 0.0, 1.0)
	# The hull on its air cushion.
	var want_tilt := Vector2(clampf(-local_accel.z * PITCH_PER_ACCEL, -TILT_MAX, TILT_MAX),
			clampf(local_accel.x * ROLL_PER_ACCEL + local_spin.y * local_velocity.z * 0.01, -TILT_MAX, TILT_MAX))
	_tilt = _tilt.lerp(want_tilt, 1.0 - exp(-delta * 2.5))
	model.position.y = HOVER + sin(_age * 1.6) * BOB + sin(_age * 2.9) * BOB * 0.3
	model.rotation = Vector3(_tilt.x + sin(_age * 1.3) * 0.006, 0.0, _tilt.y + sin(_age * 1.1) * 0.006)
	# Thrusters: lean each jet against where the hull is to go. A jet points down its pad's -Y; leaning the pad about
	# its X by +a swings the jet back (-Z), about its Z by +b swings it to the left (+X).
	for i in PADS.size():
		var pad: String = PADS[i]
		var front := 1.0 if pad.begins_with("F") else -1.0
		var push := Vector2(drive.y, -drive.x - turn * front * 0.8)
		var want := Vector2(clampf(push.x, -1.0, 1.0), clampf(push.y, -1.0, 1.0)) * GIMBAL
		var g: Vector2 = _gimbal.get(pad, Vector2.ZERO)
		g = Vector2(servo(g.x, want.x, GIMBAL_RATE, delta), servo(g.y, want.y, GIMBAL_RATE, delta))
		_gimbal[pad] = g
		spin("thruster_" + pad, 0.0, g)
		_jets[i].power = clampf(lift + 0.15 * sin(_age * 9.0 + i * 1.7), 0.0, 1.0)
	for f in _boosters:
		f.power = clampf(drive.y * 1.2, 0.0, 1.0)
	# Turret and gun.
	var want := _want()
	_yaw = wrapf(rotate_toward(_yaw, want.x, TRAVERSE * delta), -PI, PI)
	_pitch = move_toward(_pitch, want.y, ELEVATE * delta)
	spin("turret", _yaw)
	hinge("gun", _pitch)
	_kick = move_toward(_kick, 0.0, RUN_OUT * delta)
	slide("barrel", _recoil_dir * _kick)


## The turret yaw and gun elevation that put the barrel on the aim (or the front, stowed).
func _want() -> Vector2:
	if _aim == Vector3.INF:
		return Vector2.ZERO
	var local := model.global_transform.affine_inverse() * _aim
	var d := local - _turret_pivot
	var yaw := atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.5 else _yaw
	var from := _turret_pivot + Basis(Vector3.UP, yaw) * _gun_pivot
	var flat := Vector2(local.x - from.x, local.z - from.z).length()
	var pitch := clampf(atan2(local.y - from.y, maxf(flat, 0.1)), DEPRESSION, ELEVATION)
	return Vector2(yaw, pitch)
