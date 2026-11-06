class_name FighterJetRig
extends VehicleRig
## The defenders' Defender fighter jet (assets_src/defenders/defender_fighter_jet, cut by tools/gltf/rig_vehicles.py):
## 18 m long, 20 m span. Its control surfaces work the way a pilot's stick and pedals would move them:
##   roll: the ailerons opposite ways (the one on the rising wing's side down), helped by the stabilators;
##   pitch: the all-moving stabilators together (trailing edges up to pull the nose up), and the nozzles vector;
##   yaw: the two rudders on the canted fins together;
##   flaps: down at low speed, for take-off and landing.
## The two engines' flames (exhaust_L/R) follow the throttle and light the afterburners above it.
##
## Following its own motion (VehicleRig follow_motion) the pilot's inputs are read off how the jet is turning: its
## pitch, roll and yaw rates against the most it does (PITCH_RATE, ROLL_RATE, YAW_RATE), the throttle off its speed and
## acceleration, the flaps off its speed. Otherwise set the inputs below.

const MODEL := "res://assets/defenders/defender_fighter_jet/defender_fighter_jet.glb"
## The most each surface moves (rad) and how fast the actuators drive them (rad/s).
const AILERON := deg_to_rad(22.0)
const FLAP := deg_to_rad(35.0)
const STABILATOR := deg_to_rad(20.0)
const RUDDER := deg_to_rad(25.0)
const NOZZLE := deg_to_rad(12.0)
const SERVO := deg_to_rad(110.0)
## The turn rates (rad/s) that take a full stick.
const PITCH_RATE := 0.7
const ROLL_RATE := 3.0
const YAW_RATE := 0.35
## Speeds (m/s): flaps fully down below FLAPS_FULL, up above FLAPS_UP; cruise at CRUISE (the throttle's middle).
const FLAPS_FULL := 70.0
const FLAPS_UP := 110.0
const CRUISE := 160.0

## The pilot's inputs (-1..1): pitch up, roll right, yaw left; throttle 0..1, afterburner 0..1, flaps 0..1.
var pitch_input := 0.0
var roll_input := 0.0
var yaw_input := 0.0
var throttle := 0.6
var afterburner := 0.0
var flaps := 0.0

var _surf := {}
var _flames: Array[ThrusterFlame] = []


func _model_path() -> String:
	return MODEL


func _build() -> void:
	for side in ["L", "R"]:
		var f := ThrusterFlame.new()
		f.length = 6.0
		f.radius = 0.62
		f.color = Color(0.9, 0.9, 2.6)
		f.burner_color = Color(2.6, 1.3, 0.5)
		f.light_range = 14.0
		var ex := part("exhaust_" + side)
		if ex:
			ex.add_child(f)
		_flames.append(f)


func _process(delta: float) -> void:
	_track(delta)
	if follow_motion:
		_read_motion()
	var p := clampf(pitch_input, -1.0, 1.0)
	var r := clampf(roll_input, -1.0, 1.0)
	var y := clampf(yaw_input, -1.0, 1.0)
	var want := {
		"aileron_L": r * AILERON, "aileron_R": -r * AILERON,
		"flap_L": flaps * FLAP, "flap_R": flaps * FLAP,
		"stabilator_L": (-p + r * 0.35) * STABILATOR, "stabilator_R": (-p - r * 0.35) * STABILATOR,
		"rudder_L": y * RUDDER, "rudder_R": y * RUDDER,
		"nozzle_L": (-p + r * 0.3) * NOZZLE, "nozzle_R": (-p - r * 0.3) * NOZZLE,
	}
	for name in want:
		_surf[name] = servo(_surf.get(name, 0.0), want[name], SERVO, delta)
		hinge(name, _surf[name])
	for f in _flames:
		f.power = clampf(throttle, 0.0, 1.0) + clampf(afterburner, 0.0, 1.0)


## A surface's angle as of now (rad).
func surface(name: String) -> float:
	return _surf.get(name, 0.0)


func _read_motion() -> void:
	pitch_input = clampf(-local_spin.x / PITCH_RATE, -1.0, 1.0)
	roll_input = clampf(local_spin.z / ROLL_RATE, -1.0, 1.0)
	# The rudders coordinate the turn and kill the sideslip.
	yaw_input = clampf(local_spin.y / YAW_RATE * 0.5 - local_velocity.x * 0.04, -1.0, 1.0)
	var speed := -local_velocity.z if local_velocity.z < 0.0 else local_velocity.z
	throttle = clampf(0.35 + 0.45 * speed / CRUISE + local_accel.z * 0.05, 0.15, 1.0)
	afterburner = clampf((local_accel.z - 4.0) * 0.2 + (speed - CRUISE * 1.4) * 0.02, 0.0, 1.0)
	flaps = clampf((FLAPS_UP - speed) / (FLAPS_UP - FLAPS_FULL), 0.0, 1.0) if speed > 1.0 else 0.0
