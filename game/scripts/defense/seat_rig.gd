class_name SeatRig
extends SkeletonModifier3D
## Sits a Mixamo-rigged soldier down (the Cyber Orc Sentinel in a gun's crew seat: GarrisonSoldier), on top of
## whatever clip plays: the thighs swing forward level, the shins hang straight down from the knees, the back leans
## in a little toward the controls. The arms keep the clip's grip out in front (the rifle is put away while seated).
## Turns are given in the model's frame (front +Z, up +Y) and applied to each bone in its parent's frame, like
## TrooperRig's spine.

const THIGHS := ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]
const SHINS := ["mixamorig_LeftLeg", "mixamorig_RightLeg"]
const SPINE := "mixamorig_Spine1"
## The thighs forward (rad, about the model's left-right axis), the knees bent back down, the lean forward, and how far
## the knees part (each thigh turned out about the up axis).
const THIGH := -PI * 0.5
const KNEE := PI * 0.5
const LEAN := deg_to_rad(10.0)
const SPLAY := deg_to_rad(9.0)

## Standing up out of the seat, the soldier stays a moment; 0..1 how seated it is.
var amount := 1.0

var _thighs: Array[int] = []
var _shins: Array[int] = []
var _spine := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or amount <= 0.0:
		return
	if _thighs.is_empty():
		for b in THIGHS:
			_thighs.append(skel.find_bone(b))
		for b in SHINS:
			_shins.append(skel.find_bone(b))
		_spine = skel.find_bone(SPINE)
	for k in _thighs.size():
		var out := SPLAY if k == 0 else -SPLAY  # the left thigh (+X) out to the left, the right one to the right
		_turn(skel, _thighs[k], Basis(Vector3.UP, out * amount) * Basis(Vector3.RIGHT, THIGH * amount))
		_turn(skel, _shins[k], Basis(Vector3.RIGHT, KNEE * amount))
	if _spine >= 0:
		_turn(skel, _spine, Basis(Vector3.RIGHT, LEAN * amount))


## Turns `bone` by `turn` (given in the skeleton's frame) about its own origin.
static func _turn(skel: Skeleton3D, bone: int, turn: Basis) -> void:
	if bone < 0:
		return
	var parent := skel.get_bone_global_pose(skel.get_bone_parent(bone)).basis.orthonormalized()
	var global := skel.get_bone_global_pose(bone).basis.orthonormalized()
	# The bone's new frame in the skeleton's: turned as a whole; back into its parent's.
	var local := parent.inverse() * (turn * global)
	skel.set_bone_pose_rotation(bone, local.get_rotation_quaternion().normalized())
