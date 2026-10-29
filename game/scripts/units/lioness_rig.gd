class_name LionessRig
extends SkeletonModifier3D
## Keeps where the Armored Lioness's two flamethrower nozzles are (the barrels on her back), after her
## clips: the fire blast comes out of them (LionessBlast). Bone names come from tools/gltf/rig_lioness.py;
## each nozzle's Y axis points out of its barrel.

const NOZZLES := ["nozzle_1", "nozzle_2"]

var _bones: Array[int] = []
var _xf: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _posed := false


## World transform of nozzle k (0 the lower barrel's claw, 1 the upper barrel) as of the last frame.
func nozzle(k: int) -> Transform3D:
	return _xf[k]


## False until the skeleton has been posed once (the transforms above are still unset).
func posed() -> bool:
	return _posed


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _bones.is_empty():
		for b in NOZZLES:
			_bones.append(skel.find_bone(b))
	for k in _bones.size():
		_xf[k] = skel.global_transform * skel.get_bone_global_pose(_bones[k])
	_posed = true
