class_name HeavyLiftRig
extends VehicleRig
## The attackers' Heavy Lift Helicopter (assets_src/units/heavy_lift_helicopter, cut by tools/gltf/rig_vehicles.py):
## an immense tandem lifter, 64 m long, 18 m to the rear rotor's hub, that carries war elephants. Its two rotors turn
## opposite ways (rotor_F, low over the cockpit, and rotor_R on the hump, 42 m across), the ducted fan in the tail
## (tail_fan) with them; each shows a blur disc over its blades as it comes up to speed. start() spools the rotors up
## over SPOOL seconds, stop() lets them run down.
##
## It flies like a tandem: both rotor discs tilt the way it is to go (the cyclic: forward to fly on, back to stop,
## sideways to slide), and opposite ways across to turn it (the front one toward the turn, the rear one away). The
## body follows slowly: nose down accelerating, nose up braking, a little roll into its slides.
##
## carry() hangs a load (a war elephant) on a cable under the sling hook; the load swings like a pendulum against the
## helicopter's acceleration and settles.

const MODEL := "res://assets/units/heavy_lift_helicopter/heavy_lift_helicopter.glb"
## Rotor speed at full power (rev/s) and the tail fan's; seconds to spool up from rest.
const ROTOR_RATE := 2.2
const FAN_RATE := 5.0
const SPOOL := 8.0
## Cyclic: the most a disc tilts (rad), and how fast (rad/s); the acceleration (m/s²) that tilts it fully.
const CYCLIC := deg_to_rad(7.0)
const CYCLIC_RATE := deg_to_rad(12.0)
const FULL_ACCEL := 2.5
## The body's lean (rad per m/s² of acceleration; most), and how slowly it follows (s).
const LEAN := 0.025
const LEAN_MAX := deg_to_rad(9.0)
const LEAN_LAG := 1.4
## The load's swing: damping (1/s) and the most it swings (rad).
const SWING_DAMP := 0.9
const SWING_MAX := deg_to_rad(35.0)

## Inputs (when not following its motion): the cyclic (-1..1 in its frame: x left, y forward) and the turn (-1..1, left +).
var cyclic := Vector2.ZERO
var turn := 0.0

var _power := 0.0
var _target := 0.0
var _angle := {"rotor_F": 0.0, "rotor_R": 0.0, "tail_fan": 0.0}
var _tilt := {"rotor_F": Vector2.ZERO, "rotor_R": Vector2.ZERO}
var _discs := {}
var _lean := Vector2.ZERO
var _cargo: Node3D
var _cable: MeshInstance3D
var _load: Node3D
var _cable_len := 0.0
var _swing := Vector2.ZERO
var _swing_v := Vector2.ZERO


func _model_path() -> String:
	return MODEL


func _build() -> void:
	for name in ["rotor_F", "rotor_R", "tail_fan"]:
		var d := add_blur(name, Color(0.1, 0.11, 0.1, 0.13 if name != "tail_fan" else 0.45))
		if d:
			_discs[name] = d


## Spools the rotors up to flying speed.
func start() -> void:
	_target = 1.0


## Lets the rotors run down.
func stop() -> void:
	_target = 0.0


## Rotor power as of now (0: still, 1: flying speed).
func rotor_power() -> float:
	return _power


## A rotor's angle (rad) and its disc's tilt (rad about its X, Z) as of now.
func rotor_angle(name: String) -> float:
	return _angle.get(name, 0.0)


func disc_tilt(name: String) -> Vector2:
	return _tilt.get(name, Vector2.ZERO)


## Hangs `load` on a cable `cable` m long under the sling hook; `hook` is how high its lifting point is over its
## origin (an elephant's back). The load becomes the helicopter's; carry(null) lets it go (and frees it).
func carry(load: Node3D, cable := 14.0, hook := 3.6) -> void:
	if _cargo == null:
		_cargo = Node3D.new()
		_cargo.name = "Cargo"
		# Hung from the hook, in the model's own axes (the marker's are turned to point its +Z down).
		model.add_child(_cargo)
		_cargo.position = rest_of("sling").origin
		_cable = MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.09
		c.bottom_radius = 0.09
		c.height = 1.0
		c.radial_segments = 6
		_cable.mesh = c
		_cable.material_override = Mats.flat(Color(0.12, 0.12, 0.11), 0.6, 0.5)
		_cargo.add_child(_cable)
	if _load and _load != load:
		_load.queue_free()
	_load = load
	_cable_len = cable
	_cable.visible = load != null
	if load:
		if load.get_parent():
			load.get_parent().remove_child(load)
		_cargo.add_child(load)
		load.position = Vector3(0, -cable - hook, 0)
		load.rotation = Vector3.ZERO
	_cable.scale = Vector3(1, cable, 1)
	_cable.position = Vector3(0, -cable * 0.5, 0)
	_swing = Vector2.ZERO
	_swing_v = Vector2.ZERO


## The load's swing (rad about the hook's X, Z) as of now.
func swing() -> Vector2:
	return _swing


func _process(delta: float) -> void:
	_track(delta, 0.4)
	_power = move_toward(_power, _target, delta / SPOOL)
	if follow_motion:
		cyclic = Vector2(clampf(local_accel.x / FULL_ACCEL, -1.0, 1.0),
				clampf(local_accel.z / FULL_ACCEL + local_velocity.z * 0.02, -1.0, 1.0))
		turn = clampf(local_spin.y * 2.5, -1.0, 1.0)
	# The rotors turn opposite ways; the speed eases in (the first turns are slow).
	var rate := ROTOR_RATE * _power * _power * (3.0 - 2.0 * _power)
	_angle["rotor_F"] = wrapf(_angle["rotor_F"] + TAU * rate * delta, -PI, PI)
	_angle["rotor_R"] = wrapf(_angle["rotor_R"] - TAU * rate * delta, -PI, PI)
	_angle["tail_fan"] = wrapf(_angle["tail_fan"] + TAU * FAN_RATE * _power * delta, -PI, PI)
	for name in ["rotor_F", "rotor_R"]:
		var front := 1.0 if name == "rotor_F" else -1.0
		# About X +: the disc's top toward the front; about Z +: toward the right (-X).
		var want := Vector2(cyclic.y, -cyclic.x - turn * front * 0.7).clamp(Vector2(-1, -1), Vector2(1, 1)) * CYCLIC * _power
		var t: Vector2 = _tilt[name]
		_tilt[name] = Vector2(servo(t.x, want.x, CYCLIC_RATE, delta), servo(t.y, want.y, CYCLIC_RATE, delta))
		spin(name, _angle[name], _tilt[name])
	spin("tail_fan", _angle["tail_fan"])
	for name in _discs:
		set_blur(_discs[name], (_power - 0.25) / 0.6)
	# The body follows the discs.
	var want_lean := Vector2(clampf(local_accel.z * LEAN, -LEAN_MAX, LEAN_MAX), clampf(-local_accel.x * LEAN, -LEAN_MAX, LEAN_MAX))
	_lean = _lean.lerp(want_lean, 1.0 - exp(-delta / LEAN_LAG))
	model.rotation = Vector3(_lean.x, 0.0, _lean.y)
	_swing_load(delta)


## The load as a pendulum on its cable, pushed by the helicopter's acceleration (in its frame): speeding up, it
## trails behind; braking, it swings ahead; it settles.
func _swing_load(delta: float) -> void:
	if _load == null or _cable_len <= 0.0:
		return
	var g := 9.8 / _cable_len
	# About X +: the load swings back (-Z); about Z +: to the left (+X).
	var push := Vector2(local_accel.z, -local_accel.x) / _cable_len
	_swing_v += (-g * _swing + push - SWING_DAMP * _swing_v) * delta
	_swing += _swing_v * delta
	_swing = _swing.clamp(Vector2(-SWING_MAX, -SWING_MAX), Vector2(SWING_MAX, SWING_MAX))
	_cargo.rotation = Vector3(_swing.x, 0.0, _swing.y) - model.rotation
