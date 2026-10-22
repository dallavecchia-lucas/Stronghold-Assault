class_name GunnerRig
extends TrooperRig
## Poses the Heavy Gunner's minigun once TrooperRig has bent the spine onto the aim: the barrel
## cluster spins and the gun kicks back on every round. Bone names come from
## tools/blender/rig_heavy_gunner.py.

const RECOIL := 0.035

## Barrel spin (rad/s).
var spin_speed := 0.0

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


func _find_bones(skel: Skeleton3D) -> void:
	_gun = skel.find_bone("gun")
	_barrels = skel.find_bone("barrels")
	_muzzle = skel.find_bone("muzzle")


func _pose_weapon(skel: Skeleton3D, delta: float) -> void:
	_kick = move_toward(_kick, 0.0, RECOIL * 8.0 * delta)
	var rest := skel.get_bone_rest(_gun)
	skel.set_bone_pose_position(_gun, rest.origin - rest.basis.y.normalized() * _kick)
	_spin = wrapf(_spin + spin_speed * delta, 0.0, TAU)
	var brest := skel.get_bone_rest(_barrels)
	skel.set_bone_pose_rotation(_barrels, (brest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, _spin)).normalized())
	_muzzle_xf = skel.global_transform * skel.get_bone_global_pose(_muzzle)
