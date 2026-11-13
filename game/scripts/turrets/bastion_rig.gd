class_name BastionRig
extends "res://scripts/turrets/gatling_rig.gd"
## The Sentinel Bastion on the roofs (tools/gltf/rig_turrets.py `bastion`): a four-barrelled rotary cannon that runs
## itself. The turret turns on its base ring; the receiver elevates in its yoke and the barrels spin (GatlingRig); the
## sensor head on its roof scans, and holds whatever the gun is on (TurretRig); the drum on its right is pulled round
## by the belt. Out on its left an arm carries a camera on a mast (`camera`): its own eye, which looks about on its own
## while the gun has nothing, and swings onto the target when it has, a beat behind the sensor head.

const MODEL := "res://assets/defenses/sentinel_bastion/sentinel_bastion.glb"
## As low as the barrels go before they meet the roof the gun stands on, and as high (rad).
const DEPRESSION := deg_to_rad(-33.0)
const ELEVATION := deg_to_rad(56.0)
## The camera: how far it turns either way (rad), how fast (rad/s, rad/s²).
const CAMERA_ARC := deg_to_rad(150.0)
const CAMERA_RATE := 2.2
const CAMERA_ACCEL := 9.0

var _cam := 0.0
var _cam_v := 0.0
var _cam_t := 0.0
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


func _case_size() -> Vector2:
	return Vector2(0.022, 0.11)


func _setup() -> void:
	super()
	_cam_t = randf() * 10.0


func _animate(delta: float) -> void:
	super(delta)
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
