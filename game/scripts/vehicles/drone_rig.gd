class_name DroneRig
extends "res://scripts/vehicles/vehicle_rig.gd"
## The defenders' Defender drone (assets_src/defenders/defender_drone, cut by tools/gltf/rig_vehicles.py): a small
## gunship, 1.8 m long and 2.4 m across its two wing-tip ducted fans. Each fan pod tilts about the wing (pod_L/R: up
## for the hover, forward to fly) and its fan spins in the duct (fan_L/R), a blur disc showing over the blades at
## speed. It flies like a tilt-rotor: hovering, the pods stand up; picking up speed they tilt forward (all the way
## by CRUISE); braking, they tilt back; turning on the spot, one tilts forward and the other back. The two rear
## engines (exhaust_L/R) burn with the forward push. muzzle_L/R are the twin guns' muzzles.
##
## Following its own motion (VehicleRig follow_motion) all this comes off how it moves; it also leans into its
## acceleration and bobs a little on the air when it hovers. Otherwise set the inputs below.

## The scripts this one uses, by path (they work before the editor has rescanned the project's classes).
const Flame := preload("res://scripts/vehicles/thruster_flame.gd")
const MODEL := "res://assets/defenders/defender_drone/defender_drone.glb"
## Pod tilt (rad): its range (forward +) and how fast the pods turn (rad/s).
const TILT_MAX := deg_to_rad(80.0)
const TILT_BACK := deg_to_rad(-25.0)
const TILT_RATE := deg_to_rad(140.0)
## The speed (m/s) at which the pods are fully forward.
const CRUISE := 22.0
## The fans' spin (rev/s) idling and at full power (on screen: the blur disc does the rest).
const FAN_IDLE := 2.0
const FAN_FULL := 7.0
## How far the body leans into its acceleration (rad per m/s²) and the most it leans.
const LEAN := 0.035
const LEAN_MAX := deg_to_rad(18.0)

## Inputs: the pods' tilt (0 up .. 1 fully forward, below 0 back), the turn (-1..1, left +) and power (0..1).
var tilt := 0.0
var turn := 0.0
var power := 0.5

var _tilt := [0.0, 0.0]
var _spin := [0.0, 0.0]
var _rate := 0.0
var _discs: Array[MeshInstance3D] = []
var _flames: Array[Flame] = []
var _lean := Vector2.ZERO


func _model_path() -> String:
	return MODEL


func _build() -> void:
	for side in ["L", "R"]:
		_discs.append(add_blur("fan_" + side, Color(0.08, 0.08, 0.09, 0.4)))
		var f := Flame.new()
		f.length = 0.45
		f.radius = 0.045
		f.color = Color(0.5, 1.2, 2.6)
		var ex := part("exhaust_" + side)
		if ex:
			ex.add_child(f)
		_flames.append(f)


func _process(delta: float) -> void:
	_track(delta, 0.25)
	if follow_motion:
		_read_motion(delta)
	var want := [tilt * TILT_MAX + turn * 0.35, tilt * TILT_MAX - turn * 0.35]
	if tilt < 0.0:
		want = [-tilt * TILT_BACK + turn * 0.35, -tilt * TILT_BACK - turn * 0.35]
	_rate = move_toward(_rate, lerpf(FAN_IDLE, FAN_FULL, clampf(power, 0.0, 1.0)), delta * 4.0)
	for i in 2:
		var side: String = ["L", "R"][i]
		_tilt[i] = servo(_tilt[i], clampf(want[i], TILT_BACK, TILT_MAX), TILT_RATE, delta)
		hinge("pod_" + side, _tilt[i])
		# The two fans turn opposite ways (their torques cancel).
		_spin[i] = wrapf(_spin[i] + TAU * _rate * delta * (1.0 if i == 0 else -1.0), -PI, PI)
		spin("fan_" + side, _spin[i])
		if _discs[i]:
			set_blur(_discs[i], (_rate - FAN_IDLE * 0.5) / FAN_FULL)
		_flames[i].power = clampf(0.3 + tilt * 0.8 * power, 0.0, 1.0)


## A pod's tilt as of now (rad, forward +; 0 left, 1 right), and the fans' spin rate (rev/s).
func pod_tilt(i: int) -> float:
	return _tilt[i]


func fan_rate() -> float:
	return _rate


func _read_motion(delta: float) -> void:
	var fwd := local_velocity.z
	var brake := clampf(-local_accel.z * 0.08, 0.0, 1.0) if fwd > 1.0 else 0.0
	tilt = clampf(fwd / CRUISE, -0.6, 1.0) - brake * 0.8
	turn = clampf(local_spin.y * 0.6, -1.0, 1.0)
	power = clampf(0.45 + absf(local_accel.y) * 0.08 + absf(fwd) / CRUISE * 0.35 + absf(local_accel.z) * 0.03, 0.3, 1.0)
	# Lean into the acceleration (nose down speeding up, into the turn), bob on the air when hovering.
	var want := Vector2(clampf(local_accel.z * LEAN, -LEAN_MAX, LEAN_MAX), clampf(-local_accel.x * LEAN, -LEAN_MAX, LEAN_MAX))
	_lean = _lean.lerp(want, 1.0 - exp(-delta * 3.0))
	var hover := 1.0 - clampf(local_velocity.length() / 4.0, 0.0, 1.0)
	model.rotation = Vector3(_lean.x + sin(_age * 2.3) * 0.03 * hover, 0.0, _lean.y + sin(_age * 1.7) * 0.025 * hover)
	model.position.y = sin(_age * 1.9) * 0.04 * hover
