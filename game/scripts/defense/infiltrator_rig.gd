class_name InfiltratorRig
extends TrooperRig
## Poses the Infiltrator once TrooperRig has turned the spine onto the aim: the bow rides the left
## hand and the string fingers the right (the clips hold the bow out on the aim and the string drawn
## to the cheek), so only the two need finding: `bow` (the grip; Y up the bow, Z toward the target)
## and `nock` (where the arrow's nock sits on the string). Bone names come from
## tools/rig/rig_infiltrator.py.

## Called once the bow and the string hand are posed, every frame (the trooper strings the bow).
var on_posed := Callable()

var _bow := -1
var _nock := -1
var _bow_xf := Transform3D.IDENTITY
var _nock_xf := Transform3D.IDENTITY
var _posed := false


## World transform of the bow's grip as of the last frame.
func bow() -> Transform3D:
	return _bow_xf


## World transform of the string fingers as of the last frame.
func nock() -> Transform3D:
	return _nock_xf


## True once the bones have been posed at least once.
func posed() -> bool:
	return _posed


func _find_bones(skel: Skeleton3D) -> void:
	_bow = skel.find_bone("bow")
	_nock = skel.find_bone("nock")


func _pose_weapon(skel: Skeleton3D, _delta: float) -> void:
	if _bow < 0 or _nock < 0:
		return
	_bow_xf = skel.global_transform * skel.get_bone_global_pose(_bow)
	_nock_xf = skel.global_transform * skel.get_bone_global_pose(_nock)
	_posed = true
	if on_posed.is_valid():
		on_posed.call()
