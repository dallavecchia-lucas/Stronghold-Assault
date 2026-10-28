class_name KangarooRig
extends SkeletonModifier3D
## Poses the Kangaroo Commando after its clips: shooting, it rears its chest up onto the aim, so the
## SMGs strapped to its sides point at what it shoots at (up on the gun decks too), and it keeps
## where the SMGs' muzzles and the throwing paw's grenade are. Bone names come from
## tools/blender/rig_kangaroo.py; the model's front is +Z and its left +X.

## Share of the rear-up each bone takes, from the hips up.
const SPINE := {"spine": 0.55, "chest": 0.45}
## The SMGs point this far below the chest's line (rad): it rears up that much more to level them.
const GUN_DROOP := deg_to_rad(13.0)
## Furthest it rears up (rad).
const MAX_PITCH := deg_to_rad(50.0)

## Rear-up on top of the clip (rad, up +).
var pitch := 0.0

var _spine: Array[int] = []
var _shares: Array[float] = []
var _muzzles: Array[int] = []
var _grenade := -1
var _muzzle_xf: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _grenade_xf := Transform3D.IDENTITY
var _posed := false


## World transform of muzzle k (0 the left SMG, 1 the right) as of the last frame; basis.y points out
## of the barrel.
func muzzle(k: int) -> Transform3D:
	return _muzzle_xf[k]


## World position of the grenade in the throwing paw as of the last frame.
func grenade() -> Vector3:
	return _grenade_xf.origin


## False until the skeleton has been posed once (the transforms above are still unset).
func posed() -> bool:
	return _posed


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _spine.is_empty():
		for b in SPINE:
			_spine.append(skel.find_bone(b))
			_shares.append(SPINE[b])
		for b in ["muzzle_L", "muzzle_R"]:
			_muzzles.append(skel.find_bone(b))
		_grenade = skel.find_bone("grenade")
	if absf(pitch) > 0.0001:
		var aim := Basis(Vector3.RIGHT, -pitch).get_rotation_quaternion()
		for k in _spine.size():
			# The same turn, in the frame of each bone's parent: every bone adds its share.
			var bone := _spine[k]
			var parent := skel.get_bone_global_pose(skel.get_bone_parent(bone)).basis.orthonormalized()
			var share := Quaternion.IDENTITY.slerp(aim, _shares[k])
			var local := parent.inverse() * Basis(share) * parent
			skel.set_bone_pose_rotation(bone, (local.get_rotation_quaternion() * skel.get_bone_pose_rotation(bone)).normalized())
	for k in 2:
		_muzzle_xf[k] = skel.global_transform * skel.get_bone_global_pose(_muzzles[k])
	_grenade_xf = skel.global_transform * skel.get_bone_global_pose(_grenade)
	_posed = true
