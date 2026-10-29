class_name SniperRig
extends TrooperRig
## Poses the Sniper once TrooperRig has turned the spine onto the aim. Her clips hold the rifle shouldered
## (the butt in the shoulder, the head down on the stock, the hands on it), and the rifle rides the chest,
## so only its bone needs finding: `rifle` (the rifle's own frame: Z out of the muzzle, Y up, the origin
## at the pistol grip). Bone names come from tools/gltf/rig_sniper.py.

## Called once the rifle's bone is posed, every frame (the trooper hangs the rifle on it).
var on_posed := Callable()

var _rifle := -1
var _rifle_xf := Transform3D.IDENTITY
var _posed := false


## World transform of the rifle as of the last frame.
func rifle() -> Transform3D:
	return _rifle_xf


## True once the bones have been posed at least once.
func posed() -> bool:
	return _posed


func _find_bones(skel: Skeleton3D) -> void:
	_rifle = skel.find_bone("rifle")


func _pose_weapon(skel: Skeleton3D, _delta: float) -> void:
	if _rifle < 0:
		return
	_rifle_xf = skel.global_transform * skel.get_bone_global_pose(_rifle)
	_posed = true
	if on_posed.is_valid():
		on_posed.call()
