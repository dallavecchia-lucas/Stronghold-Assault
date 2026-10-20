class_name ElephantTurrets
extends SkeletonModifier3D
## Poses the War Elephant's equipment after its walk / idle clips have posed the body: the two
## flak cannons swing round and up at the aircraft they are shooting (and kick back on every
## shot), the missile pods lift for a salvo and the radar dish turns. Bone names come from
## tools/blender/rig_elephant.py; the model's front is +Z.

const GUNS := ["gun_L", "gun_R"]
## Turn rates (rad/s) of the cannons.
const YAW_RATE := deg_to_rad(170.0)
const PITCH_RATE := deg_to_rad(120.0)
## While engaged the barrels always point up at the sky: at least this high, and higher when a
## barrel swings in over the elephant's back so it clears the pods.
const MIN_ELEVATION := deg_to_rad(18.0)
const ACROSS_ELEVATION := deg_to_rad(60.0)
const MAX_ELEVATION := deg_to_rad(86.0)
## How close (rad) a cannon has to be to its aim before it may fire.
const AIMED := deg_to_rad(7.0)
const RECOIL := 0.3
const POD_RAISE := deg_to_rad(18.0)

## The aircraft the cannons track; null stows them, level and facing forward.
var target: Node3D = null
## True while the pods should be up for a salvo.
var raised := false
## Radar dish speed (rad/s).
var radar_speed := 0.9

var _guns: Array[int] = []
var _muzzle_bones: Array[int] = []
var _yaw: Array[float] = [0.0, 0.0]
var _pitch: Array[float] = [0.0, 0.0]
var _want: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _kick: Array[float] = [0.0, 0.0]
var _muzzles: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _launcher := -1
var _raise := 0.0
var _tube_bones: Array[int] = []
var _tubes: Array[Transform3D] = []
var _radar := -1
var _spin := 0.0
## Body axes (front, up, left) in the frame of the cannons' parent bone and of the body bone.
var _gun_axes: Array[Vector3] = []
var _body_axes: Array[Vector3] = []


## World position of a cannon's muzzle (0 left, 1 right), as of the last frame.
func muzzle(i: int) -> Vector3:
	return _muzzles[i]


## True when the cannon is on its target and may fire.
func aimed(i: int) -> bool:
	return is_instance_valid(target) and absf(angle_difference(_yaw[i], _want[i].x)) < AIMED \
			and absf(_pitch[i] - _want[i].y) < AIMED


## The cannon kicks back along its barrel and runs out again.
func kick(i: int) -> void:
	_kick[i] = RECOIL


func tube_count() -> int:
	return _tube_bones.size()


## World transform of a missile tube's mouth; basis.y points out along the tube.
func tube(k: int) -> Transform3D:
	return _tubes[k]


## True once the pods are up and the salvo can leave.
func pods_up() -> bool:
	return _raise >= 1.0


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _guns.is_empty():
		_find_bones(skel)
	var to_skel := skel.global_transform.affine_inverse()
	for i in _guns.size():
		_aim(skel, i, to_skel, delta)
	if _launcher >= 0:
		_raise = move_toward(_raise, 1.0 if raised else 0.0, delta * 2.2)
		var rest := skel.get_bone_rest(_launcher)
		var lift := Basis(_body_axes[2], -POD_RAISE * smoothstep(0.0, 1.0, _raise))
		skel.set_bone_pose_rotation(_launcher, (lift * rest.basis).get_rotation_quaternion())
	if _radar >= 0:
		_spin = wrapf(_spin + radar_speed * delta, 0.0, TAU)
		var rest := skel.get_bone_rest(_radar)
		skel.set_bone_pose_rotation(_radar, (Basis(_body_axes[1], _spin) * rest.basis).get_rotation_quaternion())
	var xf := skel.global_transform
	for i in _guns.size():
		_muzzles[i] = xf * skel.get_bone_global_pose(_muzzle_bones[i]).origin
	for k in _tube_bones.size():
		_tubes[k] = xf * skel.get_bone_global_pose(_tube_bones[k])


func _find_bones(skel: Skeleton3D) -> void:
	for g in GUNS:
		_guns.append(skel.find_bone(g))
		_muzzle_bones.append(skel.find_bone(g + "_muzzle"))
	_launcher = skel.find_bone("launcher")
	_radar = skel.find_bone("radar")
	var k := 1
	while skel.find_bone("tube_%d" % k) >= 0:
		_tube_bones.append(skel.find_bone("tube_%d" % k))
		k += 1
	_tubes.resize(_tube_bones.size())
	_gun_axes = _axes(skel, skel.get_bone_parent(_guns[0]))
	_body_axes = _axes(skel, skel.find_bone("body"))


## The model's front, up and left as seen from a bone's rest frame.
static func _axes(skel: Skeleton3D, bone: int) -> Array[Vector3]:
	var inv := skel.get_bone_global_rest(bone).basis.inverse()
	return [inv * Vector3(0, 0, 1), inv * Vector3.UP, inv * Vector3.RIGHT]


## Turns cannon i toward the target (yaw about the body's up axis, then elevation), at a
## limited rate, from where the clip left its parent.
func _aim(skel: Skeleton3D, i: int, to_skel: Transform3D, delta: float) -> void:
	var bone := _guns[i]
	var front := _gun_axes[0]
	var up := _gun_axes[1]
	var left := _gun_axes[2]
	var rest := skel.get_bone_rest(bone)
	var want := Vector2.ZERO
	if target != null and is_instance_valid(target):
		var frame := skel.get_bone_global_pose(skel.get_bone_parent(bone))
		var d := frame.basis.inverse() * (to_skel * Combat.aim_point(target) - (frame * rest).origin)
		var yaw := atan2(d.dot(left), d.dot(front))
		var pitch := atan2(d.dot(up), Vector2(d.dot(left), d.dot(front)).length())
		# How far the barrel points in across the back (gun_L sits on the left, +X).
		var across := clampf(-sin(yaw) * (1.0 if i == 0 else -1.0), 0.0, 1.0)
		want = Vector2(yaw, clampf(pitch, lerpf(MIN_ELEVATION, ACROSS_ELEVATION, across), MAX_ELEVATION))
	_want[i] = want
	_yaw[i] = wrapf(rotate_toward(_yaw[i], want.x, YAW_RATE * delta), -PI, PI)
	_pitch[i] = move_toward(_pitch[i], want.y, PITCH_RATE * delta)
	_kick[i] = move_toward(_kick[i], 0.0, RECOIL * 5.0 * delta)
	var b := Basis(up, _yaw[i]) * Basis(left, -_pitch[i]) * rest.basis
	skel.set_bone_pose_rotation(bone, b.get_rotation_quaternion())
	skel.set_bone_pose_position(bone, rest.origin - b.y * _kick[i])
