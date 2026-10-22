class_name TrooperRig
extends SkeletonModifier3D
## Poses a squad trooper's upper body after its walk / idle clips: the spine bends and turns onto
## the aim. Subclasses pose the weapon on top (_pose_weapon). Bone names come from
## tools/blender/rig_heavy_gunner.py and rig_missile_trooper.py, which share the body's; the
## models' front is +Z and their left +X.

## Share of the aim each spine bone takes, from the hips up.
const SPINE := {"spine_1": 0.3, "spine_2": 0.35, "chest": 0.35}

## Aim on top of the clip (rad): pitch up (+) and turn to the left (+).
var pitch := 0.0
var twist := 0.0

var _spine: Array[int] = []
var _shares: Array[float] = []


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _spine.is_empty():
		for b in SPINE:
			_spine.append(skel.find_bone(b))
			_shares.append(SPINE[b])
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
	_pose_weapon(skel, delta)


## Looks up the weapon's bones (once, before the first pose).
func _find_bones(_skel: Skeleton3D) -> void:
	pass


## Poses the weapon once the spine is on the aim.
func _pose_weapon(_skel: Skeleton3D, _delta: float) -> void:
	pass
