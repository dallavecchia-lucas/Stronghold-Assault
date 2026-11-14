class_name BastionRig
extends "res://scripts/turrets/turret_rig.gd"
## The Sentinel Bastion on the roofs (tools/gltf/rig_turrets.py `bastion`): a four-barrelled flak gun that runs itself.
## The turret turns on its base ring; the gun elevates in its yoke, high enough for aircraft overhead; the sensor head
## on its roof scans, and holds whatever the gun is on (TurretRig). Out on its left an arm carries a camera on a mast
## (`camera`): its own eye, which looks about on its own while the gun has nothing, and swings onto the target when it
## has, a beat behind the sensor head.
##
## Its barrels do not turn: they fire one after another. fire_round() is the next barrel going off: the flash is at that
## barrel's muzzle (muzzle()), the four of them are driven back RECOIL together in their collar and run out again
## before the next shot, the gun jumps on its trunnion and the turret rocks, a case is thrown out under the receiver and
## the belt pulls the drum on its right round a step. Shell after shell the barrels warm, and in a long fight they glow.

const MODEL := "res://assets/defenses/sentinel_bastion/sentinel_bastion.glb"
## As low as the barrels go before they meet the roof the gun stands on, and as high (rad).
const DEPRESSION := deg_to_rad(-33.0)
const ELEVATION := deg_to_rad(78.0)
## Where each barrel's muzzle is off the top one's (the `muzzle` marker), across and up the cluster (m at the model's
## height): top, right, bottom, left.
const BARRELS := [Vector2(0.0, 0.0), Vector2(0.08, -0.11), Vector2(0.0, -0.215), Vector2(-0.07, -0.11)]
## A shot: how far the barrels go back (m) and how long out and back takes (s); the gun's jump and the turret's rock (rad).
const RECOIL := 0.16
const RECOIL_TIME := 0.05
const RUN_OUT_TIME := 0.24
const JUMP := deg_to_rad(0.7)
const ROCK := deg_to_rad(0.45)
const DRUM_STEP := deg_to_rad(18.0)
const CASE_SPEED := 2.8
## What a shell warms the barrels by, and how fast they cool (1/s).
const ROUND_HEAT := 0.03
const COOLING := 0.05
## The camera: how far it turns either way (rad), how fast (rad/s, rad/s²).
const CAMERA_ARC := deg_to_rad(150.0)
const CAMERA_RATE := 2.2
const CAMERA_ACCEL := 9.0

## Shells fired so far, and how hot the barrels have fired themselves (0..1).
var rounds := 0
var barrel_heat := 0.0

var _barrel := 0
var _since_round := INF
var _drum := 0.0
var _drum_to := 0.0
var _cam := 0.0
var _cam_v := 0.0
var _cam_goal := 0.0
var _cam_dwell := 0.0


func _model_path() -> String:
	return MODEL


func model_height() -> float:
	return 2.0


func min_pitch(_at_yaw: float) -> float:
	return DEPRESSION


func max_pitch() -> float:
	return ELEVATION


func _setup() -> void:
	_glowing(["barrels"])
	_cases(10, 0.03, 0.16)


## The muzzle of the barrel that fires next (world, +Z out of it).
func muzzle() -> Transform3D:
	var xf := spot("muzzle")
	var off: Vector2 = BARRELS[_barrel]
	var k := model.scale.x
	return Transform3D(xf.basis, xf.origin + (xf.basis.x * off.x + xf.basis.y * off.y) * k)


## How far back the barrels are (m), `t` s after a shot.
static func recoil_at(t: float) -> float:
	if t < 0.0 or t >= RECOIL_TIME + RUN_OUT_TIME:
		return 0.0
	if t < RECOIL_TIME:
		return RECOIL * (1.0 - pow(1.0 - t / RECOIL_TIME, 2.0))
	var k := (t - RECOIL_TIME) / RUN_OUT_TIME
	return RECOIL * (1.0 - k * k * (3.0 - 2.0 * k))


## The next barrel goes off (see the top). Ask muzzle() first: after this it is the barrel after's.
func fire_round() -> void:
	rounds += 1
	_since_round = 0.0
	_barrel = (_barrel + 1) % BARRELS.size()
	barrel_heat = minf(barrel_heat + ROUND_HEAT, 1.0)
	_kick(JUMP, ROCK)
	_drum_to += DRUM_STEP
	_eject(CASE_SPEED)


func _animate(delta: float) -> void:
	if _since_round < RECOIL_TIME + RUN_OUT_TIME + 0.1:
		_since_round += delta
		# The barrels' node has its Y along the bore: back is down it.
		var rest := rest_of("barrels")
		var b := part("barrels")
		if b:
			b.position = rest.origin - rest.basis.y * recoil_at(_since_round)
	if has_part("drum") and absf(_drum_to - _drum) > 0.0005:
		_drum = lerpf(_drum, _drum_to, 1.0 - exp(-delta * 18.0))
		spin("drum", _drum)
	barrel_heat = maxf(barrel_heat - COOLING * delta, 0.0)
	_set_glow(smoothstep(0.35, 1.0, maxf(heat, barrel_heat)))
	if not has_part("camera"):
		return
	var goal := _cam_goal
	if wrecked:
		goal = _cam
	elif not powered:
		goal = 0.0
	elif watch.is_finite():
		# Onto the target: the way to it in the turret's frame.
		var cam: Node3D = _parts["camera"]
		var frame := (cam.get_parent() as Node3D).global_transform * Transform3D(_rest["camera"].basis, _rest["camera"].origin)
		var local := frame.affine_inverse() * watch
		goal = clampf(atan2(local.x, local.z), -CAMERA_ARC, CAMERA_ARC)
	else:
		# Looking about: it picks a way to look, holds it a moment, picks another.
		_cam_dwell -= delta
		if _cam_dwell <= 0.0:
			_cam_dwell = randf_range(1.2, 3.4)
			_cam_goal = randf_range(-CAMERA_ARC, CAMERA_ARC) * randf_range(0.3, 1.0)
		goal = _cam_goal
	var c := slew(_cam, _cam_v, goal, CAMERA_RATE, CAMERA_ACCEL, delta)
	_cam = c.x
	_cam_v = c.y
	spin("camera", _cam)
