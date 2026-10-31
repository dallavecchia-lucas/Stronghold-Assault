class_name MuleGun
extends SkeletonModifier3D
## Poses the Mule Artillery's gun after its clips (which only raise and lower the barrel: Setup, Armed): the
## turret traverses onto the aim at `traverse` rad/s (or back to the front once it is stowed), and the
## barrel's tube kicks back into its cradle on a shot and runs out again. It keeps where the muzzle and the
## turret are. Bone names come from tools/gltf/rig_mule.py; the gun's bones keep the model's axes (front +Z,
## up +Y), so the turret turns about its Y and the tube slides along its Z.

## How far the tube kicks back on a shot (m), and how fast it runs out again (m/s).
const RECOIL := 0.7
const RUN_OUT := 0.55
## How close to its aim (rad) the turret has to be before the gun may fire.
const AIMED := deg_to_rad(1.5)
## Aims nearer the turret's pivot than this (m, flat) don't turn it.
const NEAR := 0.5

## Turn rate (rad/s): UnitTypes traverse.
var traverse := 0.7

var _turret := -1
var _tube := -1
var _muzzle := -1
var _tube_rest := Vector3.ZERO
## The turret's pivot in the skeleton's frame.
var _pivot := Vector3.ZERO
## The world point the turret turns onto (INF: the front).
var _aim := Vector3.INF
var _yaw := 0.0
var _kick := 0.0
var _muzzle_xf := Transform3D.IDENTITY
var _turret_xf := Transform3D.IDENTITY
var _posed := false


## Turns the turret onto `point` (world).
func aim(point: Vector3) -> void:
	_aim = point


## Turns the turret back to the front (to pack the gun up).
func stow() -> void:
	_aim = Vector3.INF


## True once the turret is on its aim.
func aimed() -> bool:
	return _posed and _aim != Vector3.INF and absf(angle_difference(_yaw, _yaw_to(_aim))) < AIMED


## The turret's yaw off the team's front (rad, toward its left +).
func yaw() -> float:
	return _yaw


## The tube kicks back along the barrel, then runs out again.
func kick() -> void:
	_kick = RECOIL


## World transform of the muzzle as of the last frame; basis.z points out of the barrel.
func muzzle() -> Transform3D:
	return _muzzle_xf


## World position of the turret's pivot (on the chassis deck) as of the last frame.
func turret_position() -> Vector3:
	return _turret_xf.origin


## False until the skeleton has been posed once (the transforms above are still unset).
func posed() -> bool:
	return _posed


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _turret < 0:
		_turret = skel.find_bone("turret")
		_tube = skel.find_bone("tube")
		_muzzle = skel.find_bone("muzzle")
		if _turret < 0 or _tube < 0 or _muzzle < 0:
			push_warning("MuleGun: the model has no turret, tube or muzzle bone")
			active = false
			return
		_tube_rest = skel.get_bone_rest(_tube).origin
		_pivot = skel.get_bone_global_rest(_turret).origin
	var want := 0.0 if _aim == Vector3.INF else _yaw_to(_aim)
	_yaw = wrapf(rotate_toward(_yaw, want, traverse * delta), -PI, PI)
	_kick = move_toward(_kick, 0.0, RUN_OUT * delta)
	skel.set_bone_pose_rotation(_turret, Quaternion(Vector3.UP, _yaw))
	skel.set_bone_pose_position(_tube, _tube_rest + Vector3(0.0, 0.0, -_kick))
	_muzzle_xf = skel.global_transform * skel.get_bone_global_pose(_muzzle)
	_turret_xf = skel.global_transform * skel.get_bone_global_pose(_turret)
	_posed = true


## The turret's yaw that points the barrel at `point` (world): about the turret's pivot, in the model's frame.
func _yaw_to(point: Vector3) -> float:
	var skel := get_skeleton()
	if skel == null or _turret < 0:
		return _yaw
	var d := skel.global_transform.affine_inverse() * point - _pivot
	if Vector2(d.x, d.z).length() < NEAR:
		return _yaw
	return atan2(d.x, d.z)
