class_name RhinoAim
extends RefCounted
## Where each rhino in a group drops its cluster bombs when the player aims at one point.
## Every rhino can only bomb inside its own aim zone (cluster_range around it, on the ground).
##
##   In formation (all rhinos came from the same group move): the formation keeps its shape.
##     Every rhino fires the same way, along the line from the centre rhino to the cursor,
##     so the bombs land in a copy of the formation.
##   Scattered: each rhino aims at the cursor as best its zone allows. Rhinos that can reach
##     the cursor take neighbouring spots around it instead of piling onto the same one (cluster(),
##     which the AA Squad's rocket strike uses too).


## Returns one aim point per rhino, in the same order.
static func solve(rhinos: Array, target: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if rhinos.is_empty():
		return out
	if in_formation(rhinos):
		out = _formation(rhinos, target)
	else:
		out = _scattered(rhinos, target)
	var space: PhysicsDirectSpaceState3D = rhinos[0].get_world_3d().direct_space_state
	for i in out.size():
		out[i] = _ground(space, out[i])
	return out


static func in_formation(rhinos: Array) -> bool:
	if rhinos.size() < 2:
		return false
	var fid: int = rhinos[0].formation_id
	return fid != 0 and rhinos.all(func(r): return r.formation_id == fid)


static func _formation(rhinos: Array, target: Vector3) -> Array[Vector3]:
	var centroid := Vector3.ZERO
	for r in rhinos:
		centroid += r.global_position
	centroid /= rhinos.size()
	var centre: Node3D = rhinos[0]
	for r in rhinos:
		if _flat(r.global_position, centroid) < _flat(centre.global_position, centroid):
			centre = r
	var to := target - centre.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else -centre.global_basis.z
	var out: Array[Vector3] = []
	for r in rhinos:
		var reach := minf(to.length(), r.stats.cluster_range)
		out.append(r.global_position + dir * reach)
	return out


static func _scattered(rhinos: Array, target: Vector3) -> Array[Vector3]:
	var at: Array[Vector3] = []
	var reach: Array[float] = []
	for r in rhinos:
		at.append(r.global_position)
		reach.append(r.stats.cluster_range)
	return cluster(at, reach, rhinos[0].stats.cluster_spread * 1.6, target)


## One spot around `target` for each shooter (standing at `at`, reaching `reach` over the ground):
## as close to it as the shooter's reach allows, and `spacing` clear of the others, so they cluster
## round it instead of piling onto one spot. Same order as `at`.
static func cluster(at: Array[Vector3], reach: Array[float], spacing: float, target: Vector3) -> Array[Vector3]:
	# Spots around the cursor, nearest first: the cursor, then hexagonal rings. Each ring is gone
	# round every other spot first, so a few shooters spread evenly round the cursor.
	var spots: Array[Vector3] = [target]
	for ring in range(1, 5):
		var n := 6 * ring
		for k in n:
			var a := TAU * ((k * 2) % n + (k * 2) / n) / float(n)
			spots.append(target + Vector3(cos(a), 0.0, sin(a)) * spacing * ring)
	# Most constrained shooters (farthest from the cursor relative to their reach) pick first.
	var order := range(at.size())
	order.sort_custom(func(a, b): return reach[a] - _flat(at[a], target) < reach[b] - _flat(at[b], target))
	var out: Array[Vector3] = []
	out.resize(at.size())
	var placed: Array[Vector3] = []
	for i in order:
		var best := clamp_to_zone(at[i], reach[i], target)
		if _crowded(best, placed, spacing):
			for s in spots:
				if _flat(s, at[i]) <= reach[i] and not _crowded(s, placed, spacing):
					best = s
					break
		placed.append(best)
		out[i] = best
	return out


static func clamp_to_zone(centre: Vector3, reach: float, p: Vector3) -> Vector3:
	var d := p - centre
	d.y = 0.0
	if d.length() <= reach:
		return p
	var q := centre + d.normalized() * reach
	q.y = p.y
	return q


static func _crowded(p: Vector3, placed: Array[Vector3], spacing: float) -> bool:
	for q in placed:
		if _flat(p, q) < spacing * 0.9:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), GameConfig.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return Vector3(p.x, hit.position.y if not hit.is_empty() else 0.0, p.z)


## Adds a dashed ground circle to an ImmediateMesh that is already in PRIMITIVE_LINES mode.
static func dashed_circle(im: ImmediateMesh, centre: Vector3, radius: float, dashes := 32) -> void:
	for k in dashes:
		var a0 := TAU * k / dashes
		var a1 := a0 + TAU * 0.55 / dashes
		im.surface_add_vertex(centre + Vector3(cos(a0), 0.0, sin(a0)) * radius)
		im.surface_add_vertex(centre + Vector3(cos(a1), 0.0, sin(a1)) * radius)
