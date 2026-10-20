class_name HippoSmoke
extends RefCounted
## Aiming the Hippo's smoke screen. The hippo fires three grenades at once into a cone pointed at
## the cursor; they land side by side on an arc across the cone's tip, smoke_spacing apart, so
## their pillars join into one curtain. The arc sits at the cursor's distance, kept between
## smoke_min_range and smoke_range.

const GRENADES := 3


## The ready hippo that fires when the player aims at `target`: the closest one.
static func pick(hippos: Array, target: Vector3) -> AttackerUnit:
	var best: AttackerUnit = null
	for h in hippos:
		if best == null or _flat(h.global_position, target) < _flat(best.global_position, target):
			best = h
	return best


## {"dir": flat unit vector, "dist": arc radius, "half": half angle of the arc the grenades
## land on, "points": the grenades' ground points, left to right}
static func solve(hippo: Node3D, target: Vector3) -> Dictionary:
	var s: Dictionary = hippo.stats
	var to := target - hippo.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else -hippo.global_basis.z
	var dist := clampf(to.length(), s.smoke_min_range, s.smoke_range)
	var half: float = s.smoke_spacing * (GRENADES - 1) * 0.5 / dist
	var space := hippo.get_world_3d().direct_space_state
	var points: Array[Vector3] = []
	for i in GRENADES:
		var a := lerpf(-half, half, float(i) / (GRENADES - 1))
		points.append(_ground(space, hippo.global_position + dir.rotated(Vector3.UP, a) * dist))
	return {"dir": dir, "dist": dist, "half": half, "points": points}


## Draws the aim cone: its outline from the hippo, the band at its tip where the curtain will
## stand (filled), and a dashed line to each grenade's landing point.
static func draw_preview(im: ImmediateMesh, hippo: Node3D, aim: Dictionary, fill: Material, line: Material) -> void:
	var o := hippo.global_position
	var y := o.y + 0.3
	var r: float = hippo.stats.smoke_radius
	var near: float = aim.dist - r
	var far: float = aim.dist + r
	# The band reaches one cloud radius past the outer grenades on either side.
	var half: float = aim.half + r / aim.dist
	var segs := 16
	var at := func(a: float, d: float) -> Vector3:
		var p: Vector3 = o + (aim.dir as Vector3).rotated(Vector3.UP, a) * d
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
	var start := Vector3(o.x, y, o.z)
	for a in [-half, half]:
		im.surface_add_vertex(start)
		im.surface_add_vertex(at.call(a, far))
	for k in segs:
		im.surface_add_vertex(at.call(lerpf(-half, half, float(k) / segs), far))
		im.surface_add_vertex(at.call(lerpf(-half, half, float(k + 1) / segs), far))
	for p in aim.points:
		var end: Vector3 = p + Vector3.UP * 0.3
		var dashes := int(start.distance_to(end) / 1.5)
		for k in dashes:
			im.surface_add_vertex(start.lerp(end, float(k) / dashes))
			im.surface_add_vertex(start.lerp(end, (k + 0.5) / dashes))
	im.surface_end()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), GameConfig.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return Vector3(p.x, hit.position.y if not hit.is_empty() else 0.0, p.z)
