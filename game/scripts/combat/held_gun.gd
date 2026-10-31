class_name HeldGun
## A hand-held gun model hung on a rigged character's `rifle` bone (tools/gltf/arm_rifle.py poses the
## arms round it in every clip). The gun comes from tools/gltf/process_rifle.py: muzzle +Z, Y up, the
## origin at the pistol grip, and a `muzzle` marker node at the muzzle's mouth.

## The garrison riflemen's assault rifle (and the first-person view model's).
const SHADOWLINE_RIFLE := "res://assets/weapons/shadowline_rifle/shadowline_rifle.glb"
## The Bear Riflemen's heavy LMG.
const PROTOTYPE_C_LMG := "res://assets/weapons/prototype_c_lmg/prototype_c_lmg.glb"

static var _scenes := {}


## The gun's model, freshly instanced.
static func instance(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return (_scenes[path] as PackedScene).instantiate() as Node3D


## Hangs the gun on the first skeleton under `model` with a `rifle` bone. Returns the gun's `muzzle`
## marker (follows the gun as the clips move it), or null when the model has no such bone.
static func attach(model: Node3D, path: String) -> Node3D:
	for skel in model.find_children("*", "Skeleton3D", true, false):
		if (skel as Skeleton3D).find_bone("rifle") < 0:
			continue
		var socket := BoneAttachment3D.new()
		socket.bone_name = "rifle"
		skel.add_child(socket)
		var gun := instance(path)
		socket.add_child(gun)
		return gun.find_child("muzzle", true, false) as Node3D
	return null
