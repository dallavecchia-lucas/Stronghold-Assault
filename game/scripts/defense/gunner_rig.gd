class_name GunnerRig
extends SkeletonModifier3D
## Poses the Heavy Gunner's upper body and minigun after its walk / idle clips: the spine bends
## and turns to put the barrels on the aim, the barrel cluster spins and the gun kicks back on
## every round. Bone names come from tools/blender/rig_heavy_gunner.py; the model's front is +Z
## and its left +X.

## Share of the aim each spine bone takes, from the hips up.
const SPINE := {"spine_1": 0.3, "spine_2": 0.35, "chest": 0.35}
const RECOIL := 0.035

## Aim on top of the clip (rad): pitch up (+) and turn to the left (+).
var pitch := 0.0
var twist := 0.0
## Barrel spin (rad/s).
var spin_speed := 0.0

var _spine: Array[int] = []
var _shares: Array[float] = []
var _gun := -1
var _barrels := -1
var _muzzle := -1
var _spin := 0.0
var _kick := 0.0
var _muzzle_xf := Transform3D.IDENTITY


## World transform of the barrel tips as of the last frame; basis.y points out of the barrels.
func muzzle() -> Transform3D:
	return _muzzle_xf


## The gun kicks back and runs out again.
func kick() -> void:
	_kick = RECOIL


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _gun < 0:
		_find_bones(skel)
	var turn := Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, -pitch)
	var aim := turn.get_rotation_quaternion()
	for k in _spine.size():
		# The same turn, in the frame of each bone's parent: every bone adds its share.
		var bone := _spine[k]
		var parent := skel.get_bone_global_pose(skel.get_bone_parent(bone)).basis.orthonormalized()
		var share := Quaternion.IDENTITY.slerp(aim, _shares[k])
		var local := parent.inverse() * Basis(share) * parent
		skel.set_bone_pose_rotation(bone, (local.get_rotation_quaternion() * skel.get_bone_pose_rotation(bone)).normalized())
	_kick = move_toward(_kick, 0.0, RECOIL * 8.0 * delta)
	var rest := skel.get_bone_rest(_gun)
	skel.set_bone_pose_position(_gun, rest.origin - rest.basis.y.normalized() * _kick)
	_spin = wrapf(_spin + spin_speed * delta, 0.0, TAU)
	var brest := skel.get_bone_rest(_barrels)
	skel.set_bone_pose_rotation(_barrels, (brest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, _spin)).normalized())
	_muzzle_xf = skel.global_transform * skel.get_bone_global_pose(_muzzle)


func _find_bones(skel: Skeleton3D) -> void:
	for b in SPINE:
		_spine.append(skel.find_bone(b))
		_shares.append(SPINE[b])
	_gun = skel.find_bone("gun")
	_barrels = skel.find_bone("barrels")
	_muzzle = skel.find_bone("muzzle")
