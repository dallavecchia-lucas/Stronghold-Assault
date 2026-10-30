class_name Props
extends RefCounted
## Loads static prop models (scenery, turrets) scaled to a real height in meters.
## Prop .glb files are expected with their pivot at the bottom center.

const TREES := [
	"res://assets/environment/birch_tree/birch_tree.glb",
	"res://assets/environment/silver_birch/silver_birch.glb",
	"res://assets/environment/white_birch_majesty/white_birch_majesty.glb",
	"res://assets/environment/majestic_oak/majestic_oak.glb",
	"res://assets/environment/solitary_evergreen/solitary_evergreen.glb",
]
## The trees' trunks as modelled, for a Serpent Sniper winding up one (ForestTree.trunk_centre): where the foot of
## the trunk stands off the model's middle (x, z) and how thick it is there, as shares of the tree's height, and
## how high up it the snake lies out (a share of its height): on top of the crown, just under its highest leaves,
## the front laid out over them.
const TRUNKS := {
	"res://assets/environment/birch_tree/birch_tree.glb": [-0.016, -0.014, 0.0145, 0.93],
	"res://assets/environment/silver_birch/silver_birch.glb": [0.02, 0.005, 0.0095, 0.93],
	"res://assets/environment/white_birch_majesty/white_birch_majesty.glb": [0.004, 0.0025, 0.0125, 0.93],
	"res://assets/environment/majestic_oak/majestic_oak.glb": [0.025, 0.005, 0.0375, 0.95],
	"res://assets/environment/solitary_evergreen/solitary_evergreen.glb": [-0.009, 0.0, 0.011, 0.86],
}
const ROCKS := [
	"res://assets/environment/mossy_berry_rock/mossy_berry_rock.glb",
	"res://assets/environment/mossy_mountain_garden/mossy_mountain_garden.glb",
]
const BUSHES := [
	"res://assets/environment/meadow_garden/meadow_garden.glb",
	"res://assets/environment/berry_woodland_miniature/berry_woodland_miniature.glb",
	"res://assets/environment/wild_meadow_tangle/wild_meadow_tangle.glb",
	"res://assets/environment/meadow_tuft/meadow_tuft.glb",
]
const ORBITAL_SENTRY_GUN := "res://assets/defenses/orbital_sentry_gun/orbital_sentry_gun.glb"
const SENTINEL_BASTION := "res://assets/defenses/sentinel_bastion/sentinel_bastion.glb"
const ARCTIC_SENTINEL_CANNON := "res://assets/defenses/arctic_sentinel_cannon/arctic_sentinel_cannon.glb"
const SENTINEL_SPIRE := "res://assets/defenses/sentinel_spire/sentinel_spire.glb"

## Yaw that turns each turret's barrel to -Z (the Meshy exports face different ways).
const FACING := {
	ORBITAL_SENTRY_GUN: -PI * 0.5,
	SENTINEL_BASTION: PI,
	ARCTIC_SENTINEL_CANNON: -PI * 0.5,
	SENTINEL_SPIRE: PI,
}

static var _scenes := {}
static var _sizes := {}


## Instance of `path` scaled uniformly to `height`, facing -Z.
static func instance(path: String, height: float) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var root := Node3D.new()
	var m := (_scenes[path] as PackedScene).instantiate() as Node3D
	m.rotation.y = FACING.get(path, 0.0)
	root.add_child(m)
	if not _sizes.has(path):
		_sizes[path] = local_aabb(m).size
	m.scale = Vector3.ONE * (height / maxf(_sizes[path].y, 0.001))
	return root


## Footprint (x/z extent) of `path` once scaled to `height`.
static func footprint(path: String, height: float) -> Vector2:
	var s: Vector3 = _sizes[path] * (height / maxf(_sizes[path].y, 0.001))
	return Vector2(s.x, s.z)


## Combined mesh bounds relative to `root`; works before the node enters the tree.
static func local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
