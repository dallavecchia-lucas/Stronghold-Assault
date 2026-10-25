class_name FlameRig
extends TrooperRig
## Poses the Flame Trooper once TrooperRig has turned the spine onto the aim: the gun rides the
## right hand, which rides the chest (the clips leave the right arm alone), so only the nozzle needs
## finding, where the flame comes out. Bone names come from tools/blender/rig_flame_trooper.py.

var _nozzle := -1
var _nozzle_xf := Transform3D.IDENTITY


## World transform of the nozzle as of the last frame; basis.y points out along the barrel.
func nozzle() -> Transform3D:
	return _nozzle_xf


func _find_bones(skel: Skeleton3D) -> void:
	_nozzle = skel.find_bone("nozzle")


func _pose_weapon(skel: Skeleton3D, _delta: float) -> void:
	_nozzle_xf = skel.global_transform * skel.get_bone_global_pose(_nozzle)
