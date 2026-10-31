class_name Bush
extends Node3D
## A bush of the ground cover (LevelBuilder): for looks only, nothing collides with it. A Serpent Sniper can
## coil round one and lie in wait (its bush trap: SerpentTrap); one snake to a bush.

## Every bush on the map.
static var all: Array[Bush] = []

## Half its footprint (m), and how tall it is.
var radius := 0.5
var height := 0.8
## Out in the open, where a snake can get at it (not under a helipad's deck, not up against the mountain).
var usable := true
## The Serpent Sniper coiled round it, or on its way to it.
var coiled_by: Node = null


## `model` null: a proxy, drawn by a shared MultiMesh batch (JungleFlora).
func setup(model: Node3D, footprint: Vector2, h: float, yaw: float) -> void:
	radius = maxf(footprint.x, footprint.y) * 0.5
	height = h
	if model:
		model.rotation.y = yaw
		add_child(model)


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## A snake may coil round it: usable, and no other snake's.
func trap_free(snake: Node) -> bool:
	return usable and (coiled_by == null or coiled_by == snake or not is_instance_valid(coiled_by))


## The usable bush nearest `p` (flat) within `reach` of its edge that `snake` may coil round, or null.
static func nearest(p: Vector3, reach: float, snake: Node = null) -> Bush:
	var best: Bush = null
	var best_d := INF
	for b in all:
		if not b.trap_free(snake):
			continue
		var d := Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() - b.radius
		if d <= reach and d < best_d:
			best_d = d
			best = b
	return best
