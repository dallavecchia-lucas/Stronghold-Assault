class_name CannonRig
extends "res://scripts/turrets/turret_rig.gd"
## The Arctic Sentinel Cannon on the gun decks, and the mortar on the south roof (tools/gltf/rig_turrets.py `cannon`): a
## long gun in a mantlet on a hull with four outrigger legs. The hull and its legs stay put; the turret turns on the
## hull and carries the crew's seat and console on its right (seat()) and a sensor head on its roof, which scans and
## holds the target (TurretRig); the mantlet elevates on its trunnion between the two bearing housings; the barrel
## slides in the mantlet.
##
## fire() works the gun like a real one: the round drives the barrel back RECOIL into the mantlet in RECOIL_TIME, hard
## at first and braking on its buffer; it holds a moment (HOLD), and the recuperator runs it out again over RUN_OUT_TIME,
## slowly, easing into battery. The muzzle jumps and settles, the turret rocks back on its ring, and the whole carriage
## is shoved back on its legs and shakes for a moment. As the barrel runs out the breech opens and throws the spent
## case out under the mantlet, and the muzzle brake's ports blow smoke out to both sides.
##
## It cannot be laid through its own carriage: between the front legs the barrel goes down to DEPRESSION, over a leg
## only to OVER_LEG (min_pitch).

const MODEL := "res://assets/defenses/arctic_sentinel_cannon/arctic_sentinel_cannon.glb"
## The barrel's travel (m, at the model's height) and its times (s).
const RECOIL := 0.4
const RECOIL_TIME := 0.075
const HOLD := 0.06
const RUN_OUT_TIME := 0.85
## The muzzle's jump and the turret's rock (rad); how far the carriage is shoved back (m) and how long it shakes (s).
const JUMP := deg_to_rad(1.5)
const ROCK := deg_to_rad(1.3)
const SHOVE := 0.035
const SHAKE_TIME := 0.3
## When the breech throws the case (s after the shot), and how fast (m/s).
const CASE_AT := 0.34
const CASE_SPEED := 2.2
## The lowest the barrel goes between the legs and over one, where the front legs lie (rad either side of straight
## ahead) and how wide a leg is to the barrel (rad); the highest it goes.
const DEPRESSION := deg_to_rad(-29.0)
const OVER_LEG := deg_to_rad(-13.0)
const LEG_AT := deg_to_rad(23.0)
const LEG_WIDTH := deg_to_rad(11.0)
const LEG_EDGE := deg_to_rad(9.0)
const ELEVATION := deg_to_rad(78.0)

## Rounds fired so far.
var rounds := 0

var _since_shot := INF
var _case_due := false
var _shove := 0.0
var _shove_v := 0.0
var _shake := 0.0
var _settled := true


func _model_path() -> String:
	return MODEL


func model_height() -> float:
	return 2.2


func min_pitch(at_yaw: float) -> float:
	var off := absf(absf(wrapf(at_yaw, -PI, PI)) - LEG_AT)
	return lerpf(OVER_LEG, DEPRESSION, smoothstep(LEG_WIDTH, LEG_WIDTH + LEG_EDGE, off))


func max_pitch() -> float:
	return ELEVATION


func _setup() -> void:
	_glowing(["barrel"])
	_cases(4, 0.05, 0.34)


## How far back the barrel is (m), `t` s after a shot.
static func recoil_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < RECOIL_TIME:
		var k := t / RECOIL_TIME
		return RECOIL * (1.0 - pow(1.0 - k, 3.0))
	t -= RECOIL_TIME
	if t < HOLD:
		return RECOIL
	t -= HOLD
	if t < RUN_OUT_TIME:
		var k := t / RUN_OUT_TIME
		return RECOIL * (1.0 - k * k * (3.0 - 2.0 * k))
	return 0.0


## Back in battery (the last round's recoil is over).
func in_battery() -> bool:
	return _since_shot >= RECOIL_TIME + HOLD + RUN_OUT_TIME


## The gun goes off (see the top).
func fire() -> void:
	rounds += 1
	_since_shot = 0.0
	_settled = false
	_case_due = true
	_kick(JUMP, ROCK)
	_shove_v += SHOVE * 40.0
	_shake = SHAKE_TIME
	if is_visible_in_tree():
		# The muzzle brake: the blast out of its ports, to both sides.
		var at := muzzle()
		for side in [-1.0, 1.0]:
			SmokeCloud.wisp(self, at.origin - at.basis.z * 0.12 + at.basis.x * side * 0.4, 0.55)


func _animate(delta: float) -> void:
	_set_glow(smoothstep(0.5, 1.0, heat))
	if _settled:
		return
	_since_shot += delta
	slide("barrel", Vector3(0.0, 0.0, recoil_at(_since_shot)))
	if _case_due and _since_shot >= CASE_AT:
		_case_due = false
		_eject(CASE_SPEED)
	# The carriage on its legs: shoved back along the shot, it springs forward again and shakes.
	var steps := spring_steps(delta)
	var h := spring_span(delta) / steps
	for _i in steps:
		_shove_v += (-_shove * 420.0 - _shove_v * 24.0) * h
		_shove += _shove_v * h
	_shake = maxf(_shake - delta, 0.0)
	# (The model is turned about: its own +Z is the rig's -Z, the way the gun faces.)
	var back := Vector3(sin(yaw), 0.0, cos(yaw)) * _shove
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.006 * (_shake / SHAKE_TIME)
	model.position = back + jitter
	if in_battery() and _shake <= 0.0 and absf(_shove) < 1e-5 and absf(_shove_v) < 1e-4:
		# Back in battery and still: nothing more to move until the next round.
		_settled = true
		_shove = 0.0
		_shove_v = 0.0
		model.position = Vector3.ZERO
		slide("barrel", Vector3.ZERO)
