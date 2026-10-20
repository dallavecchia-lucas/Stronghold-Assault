class_name ElephantMissiles
extends RefCounted
## The War Elephant's missile salvo, fired at one enemy aircraft the player clicks.
##
## With several elephants selected, only as many fire as it takes to bring the target down,
## counting the damage of missiles already on their way to it; the nearest go first and the
## rest stay ready for another target. If even all of them together can't kill it, they all fire.

## Aircraft are small on screen: anything this close to the cursor (px) can be picked.
const PICK_RADIUS := 56.0
const TARGET_RING := 2.6

## Damage that is on its way to each target but hasn't landed yet: instance id -> damage.
static var _incoming := {}


static func incoming(t: Node3D) -> float:
	return _incoming.get(t.get_instance_id(), 0.0)


static func commit(target_id: int, damage: float) -> void:
	_incoming[target_id] = _incoming.get(target_id, 0.0) + damage


## A missile hit or missed, or never left its tube: its damage is no longer on the way.
static func release(target_id: int, damage: float) -> void:
	var left: float = _incoming.get(target_id, 0.0) - damage
	if left > 0.01:
		_incoming[target_id] = left
	else:
		_incoming.erase(target_id)


## Hit points the target has left once everything already fired at it lands.
static func still_needed(t: Node3D) -> float:
	var hp = t.get("hp")
	return (hp if hp != null else INF) - incoming(t)


## The elephants (out of `elephants`) that fire at `t`: ready, in range, nearest first, only
## as many as the kill takes.
static func allocate(elephants: Array, t: Node3D) -> Array:
	var ready := elephants.filter(func(e): return e.missiles_ready() and e.in_missile_range(t))
	ready.sort_custom(func(a, b): return _flat(a.global_position, t.global_position) < _flat(b.global_position, t.global_position))
	var need := still_needed(t)
	var out := []
	var sent := 0.0
	for e in ready:
		if sent >= need:
			break
		out.append(e)
		sent += e.salvo_damage()
	return out


## The enemy aircraft nearest the cursor on screen, or null.
static func pick(camera: Camera3D, screen_pos: Vector2, team: int) -> Node3D:
	var best: Node3D = null
	var best_d := PICK_RADIUS
	for a in camera.get_tree().get_nodes_in_group("air_units"):
		if a.team == team or not a.is_alive():
			continue
		var p := Combat.aim_point(a)
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = a
	return best


## Aim preview: each ready elephant's missile range on the ground, a ring around the aircraft
## under the cursor with a dashed drop line to the ground, and a line to it from every elephant
## that would fire.
static func draw_preview(im: ImmediateMesh, elephants: Array, target: Node3D, firing: Array) -> void:
	var lift := Vector3.UP * 0.3
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in elephants:
		RhinoAim.dashed_circle(im, e.global_position + lift, e.stats.missile_range, 64)
	if target:
		var c := Combat.aim_point(target)
		for k in 32:
			var a0 := TAU * k / 32.0
			var a1 := TAU * (k + 1) / 32.0
			im.surface_add_vertex(c + Vector3(cos(a0), 0.0, sin(a0)) * TARGET_RING)
			im.surface_add_vertex(c + Vector3(cos(a1), 0.0, sin(a1)) * TARGET_RING)
		var q := PhysicsRayQueryParameters3D.create(c, c + Vector3.DOWN * 200.0, GameConfig.LAYER_WORLD)
		var hit := target.get_world_3d().direct_space_state.intersect_ray(q)
		var ground: Vector3 = hit.position if not hit.is_empty() else Vector3(c.x, 0.0, c.z)
		var dashes := int(c.distance_to(ground) / 1.2)
		for k in dashes:
			im.surface_add_vertex(c.lerp(ground, float(k) / dashes))
			im.surface_add_vertex(c.lerp(ground, (k + 0.5) / dashes))
		for e in firing:
			im.surface_add_vertex(e.global_position + Vector3.UP * e.stats.height)
			im.surface_add_vertex(c)
	im.surface_end()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
