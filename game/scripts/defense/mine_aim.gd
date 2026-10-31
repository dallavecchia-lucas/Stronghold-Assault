class_name MineAim
extends RefCounted
## Aiming the AA Squad's mines, like the Hippo's smoke screen (HippoSmoke): a cone from the squad
## toward the aim point, and at its tip a band, BAND_WIDTH across and twice BAND_DEPTH deep, that
## the mines land in. They are scattered sparsely over it: no two closer than SPACING, each on open
## ground (on the navmesh, not on a rock or up a tree). The band sits at the aim's distance, kept
## between MIN_RANGE and MAX_RANGE.

const MIN_RANGE := 9.0
const MAX_RANGE := 24.0
const BAND_DEPTH := 4.0
const BAND_WIDTH := 18.0
const SPACING := 3.2


## {"dir": flat unit vector, "dist": distance to the middle of the band, "half": half angle of
## the band, "points": up to `count` ground points for the mines}. The same `seed` scatters them
## the same way, so the preview shows where they will land.
static func solve(from: Vector3, toward: Vector3, count: int, world: World3D, seed: int) -> Dictionary:
	var to := toward - from
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var dist := clampf(to.length(), MIN_RANGE, MAX_RANGE)
	var half := atan2(BAND_WIDTH * 0.5, dist)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var map := world.navigation_map
	var space := world.direct_space_state
	var points: Array[Vector3] = []
	for k in count * 40:
		if points.size() >= count:
			break
		var a := rng.randf_range(-half, half)
		var d := rng.randf_range(dist - BAND_DEPTH, dist + BAND_DEPTH)
		var p := from + dir.rotated(Vector3.UP, a) * d
		if points.any(func(q): return _flat(q, p) < SPACING):
			continue
		var c := LevelBuilder.nav_closest(map, p + Vector3.UP * 0.5)
		if _flat(c, p) > 1.0 or absf(c.y - from.y) > 4.0:
			continue
		points.append(_ground(space, c))
	return {"dir": dir, "dist": dist, "half": half, "points": points}


## Draws the cone from `from`: its outline, the band at its tip where the mines land (filled) and
## a ring with a cross on each mine's spot.
static func draw_preview(im: ImmediateMesh, from: Vector3, aim: Dictionary, fill: Material, line: Material) -> void:
	var y := from.y + 0.3
	var near: float = aim.dist - BAND_DEPTH
	var far: float = aim.dist + BAND_DEPTH
	var half: float = aim.half
	var segs := 16
	var at := func(a: float, d: float) -> Vector3:
		var p: Vector3 = from + (aim.dir as Vector3).rotated(Vector3.UP, a) * d
		p.y = y
		return p
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill)
	for k in segs:
		var a0 := lerpf(-half, half, float(k) / segs)
		var a1 := lerpf(-half, half, float(k + 1) / segs)
		var n0: Vector3 = at.call(a0, near)
		var n1: Vector3 = at.call(a1, near)
		var f0: Vector3 = at.call(a0, far)
		var f1: Vector3 = at.call(a1, far)
		for v in [n0, f1, f0, n0, n1, f1]:
			im.surface_add_vertex(v)
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_LINES, line)
	var start := Vector3(from.x, y, from.z)
	for a in [-half, half]:
		im.surface_add_vertex(start)
		im.surface_add_vertex(at.call(a, far))
	for d in [near, far]:
		for k in segs:
			im.surface_add_vertex(at.call(lerpf(-half, half, float(k) / segs), d))
			im.surface_add_vertex(at.call(lerpf(-half, half, float(k + 1) / segs), d))
	for p in aim.points:
		var c: Vector3 = p + Vector3.UP * 0.3
		RhinoAim.dashed_circle(im, c, 0.9, 10)
		for d in [Vector3(0.5, 0, 0), Vector3(0, 0, 0.5)]:
			im.surface_add_vertex(c - d)
			im.surface_add_vertex(c + d)
	im.surface_end()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The ground under `p` (the navmesh floats a little above it).
static func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 2.5, GameConfig.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else p
