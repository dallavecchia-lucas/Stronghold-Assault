class_name KangarooFlash
extends RefCounted
## Where each selected Kangaroo Commando's flash grenade goes when the player aims once: like the
## bisons' shells, the grenades cluster round the aim, SPACING flash radii apart instead of piling
## onto one spot, each within its kangaroo's throw (flash_range), up on the gun decks and roofs too
## (RhinoAim.cluster).

const COLOR := Color(1.0, 0.95, 0.55)
## Grenades land this many flash radii apart.
const SPACING := 1.5


## One spot per kangaroo (same order), clustered round `target`.
static func spots(kangaroos: Array, target: Vector3) -> Array[Vector3]:
	if kangaroos.is_empty():
		return []
	var at: Array[Vector3] = []
	var reach: Array[float] = []
	for k in kangaroos:
		at.append(k.global_position)
		reach.append(k.stats.flash_range)
	var space: PhysicsDirectSpaceState3D = kangaroos[0].get_world_3d().direct_space_state
	return RhinoAim.cluster(at, reach, kangaroos[0].stats.flash_radius * SPACING, target, space)


## Each kangaroo's throw (its range), the flash where its grenade lands and a line to it. `im` is
## already in PRIMITIVE_LINES mode.
static func draw(im: ImmediateMesh, kangaroos: Array, spots: Array[Vector3]) -> void:
	var lift := Vector3.UP * 0.3
	for i in kangaroos.size():
		var k: AttackerUnit = kangaroos[i]
		RhinoAim.dashed_circle(im, k.global_position + lift, k.stats.flash_range, 72)
		RhinoAim.dashed_circle(im, spots[i] + lift, k.stats.flash_radius, 28)
		im.surface_add_vertex(k.global_position + lift)
		im.surface_add_vertex(spots[i] + lift)
