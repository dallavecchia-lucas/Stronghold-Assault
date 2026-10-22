class_name MissileRig
extends TrooperRig
## Poses the Missile Trooper's pod once TrooperRig has turned the spine onto the aim: the pod swings
## round and up at what it launches at (like a turret: it turns about the body's up axis, then
## tilts, and never rolls), kicks back as each missile leaves, and hides the missiles whose tubes
## are empty. A thrown mine swings the right arm. Bone names come from
## tools/blender/rig_missile_trooper.py; the model's front is +Z.

const TUBES := 6
## How far the pod turns off the body's front, and how far it tilts down and up (rad).
const YAW_LIMIT := deg_to_rad(35.0)
const ELEVATION_MIN := deg_to_rad(-8.0)
const ELEVATION_MAX := deg_to_rad(75.0)
## Pod turn rate (rad/s).
const TURN_RATE := deg_to_rad(260.0)
const RECOIL := 0.07
## Underhand throw: seconds for the whole swing, and how far back and forward the arm goes (rad).
const THROW_TIME := 0.55
const THROW_BACK := deg_to_rad(55.0)
const THROW_FORWARD := deg_to_rad(70.0)

## World point the pod points at; INF: straight ahead of the body, a little up.
var target := Vector3.INF
## Which tubes hold a missile.
var full: Array[bool] = []

var _launcher := -1
var _arm := -1
var _missiles: Array[int] = []
var _tubes: Array[Transform3D] = []
var _yaw := 0.0
var _pitch := deg_to_rad(8.0)
var _kick := 0.0
var _throw := 0.0


## World transform of tube k's mouth as of the last frame; basis.y points out along the tube.
func tube(k: int) -> Transform3D:
	return _tubes[k] if k < _tubes.size() else Transform3D.IDENTITY


## The pod jolts back along its tubes and runs out again.
func kick() -> void:
	_kick = RECOIL


## Swings the right arm through an underhand throw.
func throw() -> void:
	_throw = THROW_TIME


func _find_bones(skel: Skeleton3D) -> void:
	_launcher = skel.find_bone("launcher")
	_arm = skel.find_bone("upperarm_R")
	for k in TUBES:
		_missiles.append(skel.find_bone("missile_%d" % k))
	_tubes.resize(TUBES)


func _pose_weapon(skel: Skeleton3D, delta: float) -> void:
	_pose_throw(skel, delta)
	var parent := skel.get_bone_global_pose(skel.get_bone_parent(_launcher))
	parent.basis = parent.basis.orthonormalized()
	var rest := skel.get_bone_rest(_launcher)
	var at_rest := parent * rest
	at_rest.basis = at_rest.basis.orthonormalized()
	# Where the pod should point, as yaw and pitch off the body's front (skeleton space).
	var want := Vector3(0.0, sin(deg_to_rad(8.0)), cos(deg_to_rad(8.0)))
	if target != Vector3.INF:
		var to := skel.global_transform.affine_inverse() * target - at_rest.origin
		if to.length() > 0.5:
			want = to.normalized()
	var yaw := clampf(atan2(want.x, want.z), -YAW_LIMIT, YAW_LIMIT)
	var pitch := clampf(asin(clampf(want.y, -1.0, 1.0)), ELEVATION_MIN, ELEVATION_MAX)
	_yaw = rotate_toward(_yaw, yaw, TURN_RATE * delta)
	_pitch = rotate_toward(_pitch, pitch, TURN_RATE * delta)
	# From the tubes' rest direction: turn about the body's up axis, then tilt about the level axis
	# across the tubes.
	var rest_dir := at_rest.basis.y.normalized()
	var turn := Basis(Vector3.UP, _yaw - atan2(rest_dir.x, rest_dir.z))
	var turned := turn * rest_dir
	var across := Vector3.UP.cross(turned).normalized()
	var tilt := Basis(across, -(_pitch - asin(clampf(rest_dir.y, -1.0, 1.0))))
	var basis := tilt * turn * at_rest.basis
	var local := parent.basis.inverse() * basis
	skel.set_bone_pose_rotation(_launcher, local.get_rotation_quaternion())
	_kick = move_toward(_kick, 0.0, RECOIL * 7.0 * delta)
	skel.set_bone_pose_position(_launcher, rest.origin - (local * Vector3.UP).normalized() * _kick)
	for k in TUBES:
		var gone := k < full.size() and not full[k]
		skel.set_bone_pose_scale(_missiles[k], Vector3.ONE * (0.001 if gone else 1.0))
	for k in TUBES:
		_tubes[k] = skel.global_transform * skel.get_bone_global_pose(_missiles[k])
		_tubes[k].basis = _tubes[k].basis.orthonormalized()


## The underhand throw on top of the clip: the right arm swings back, then forward past the hip.
func _pose_throw(skel: Skeleton3D, delta: float) -> void:
	if _throw <= 0.0:
		return
	_throw = maxf(_throw - delta, 0.0)
	var u := 1.0 - _throw / THROW_TIME
	var swing := -THROW_BACK * sin(PI * minf(u / 0.45, 1.0)) * float(u < 0.45)
	if u >= 0.45:
		swing = THROW_FORWARD * sin(PI * (u - 0.45) / 0.55)
	# About the body's left axis at the shoulder: forward is a turn toward the front (+Z), up.
	var parent := skel.get_bone_global_pose(skel.get_bone_parent(_arm)).basis.orthonormalized()
	var q := Basis(Vector3.RIGHT, -swing)
	var local := parent.inverse() * q * parent
	skel.set_bone_pose_rotation(_arm, (local.get_rotation_quaternion() * skel.get_bone_pose_rotation(_arm)).normalized())
