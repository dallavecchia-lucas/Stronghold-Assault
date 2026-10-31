class_name SerpentPath
extends RefCounted
## A way for a Serpent Sniper's body to lie along (SerpentRig): a polyline in world space with the way the
## snake's back faces at every point, measured by arc length from its first point. The skills build theirs
## out of pieces (SerpentNest, SerpentTrap): the body as it lay, curves joining one heading to the next
## (bezier), coils round a vertical axis (helix).

var points := PackedVector3Array()
var ups := PackedVector3Array()
var arcs := PackedFloat32Array()


static func from(p: PackedVector3Array, u: PackedVector3Array) -> SerpentPath:
	var path := SerpentPath.new()
	for k in p.size():
		path.add(p[k], u[k])
	return path


func add(p: Vector3, up: Vector3) -> void:
	if not points.is_empty():
		var d := p.distance_to(points[-1])
		if d < 0.002:
			return
		arcs.append(arcs[-1] + d)
	else:
		arcs.append(0.0)
	points.append(p)
	ups.append(up)


func length() -> float:
	return arcs[-1] if not arcs.is_empty() else 0.0


func end() -> Vector3:
	return points[-1]


## Index of the segment arc `s` falls in (clamped to the ends).
func _seg(s: float) -> int:
	var lo := 0
	var hi := arcs.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if arcs[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


## The point at arc s; off either end, on along the end segment.
func at(s: float) -> Vector3:
	if points.size() == 1:
		return points[0]
	var k := _seg(s)
	var seg := arcs[k + 1] - arcs[k]
	return points[k].lerp(points[k + 1], (s - arcs[k]) / seg) if seg > 0.0 else points[k]


func up_at(s: float) -> Vector3:
	if ups.size() == 1:
		return ups[0]
	var k := _seg(s)
	var seg := arcs[k + 1] - arcs[k]
	var u := clampf((s - arcs[k]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
	return ups[k].lerp(ups[k + 1], u).normalized()


## The way the path runs at arc s (toward its end).
func tangent_at(s: float) -> Vector3:
	var k := _seg(s)
	return (points[k + 1] - points[k]).normalized() if points.size() > 1 else Vector3.FORWARD


## A copy from its start up to arc s (cut there).
func head(s: float) -> SerpentPath:
	var out := SerpentPath.new()
	for k in points.size():
		if arcs[k] >= s:
			break
		out.add(points[k], ups[k])
	out.add(at(s), up_at(s))
	return out


## On from its end along `other` (which starts where it ends).
func extend(other: SerpentPath) -> void:
	for k in other.points.size():
		add(other.points[k], other.ups[k])


## A smooth curve from its end (heading `t0`) to `p1`, arriving heading `t1`: a cubic Bezier whose handles
## reach `reach` of the way, the up turning from the end's up to `u1` on the way.
func bezier(t0: Vector3, p1: Vector3, t1: Vector3, u1: Vector3, reach := 0.35, step := 0.08) -> void:
	var p0 := end()
	var u0 := ups[-1]
	var d := p0.distance_to(p1)
	var c0 := p0 + t0.normalized() * d * reach
	var c1 := p1 - t1.normalized() * d * reach
	var n := maxi(ceili(d / step), 2)
	for i in range(1, n + 1):
		var t := float(i) / n
		var a := 1.0 - t
		var p := c0 * (3.0 * a * a * t) + c1 * (3.0 * a * t * t) + p0 * (a * a * a) + p1 * (t * t * t)
		add(p, u0.slerp(u1, t * t * (3.0 - 2.0 * t)))


## A coil round the vertical axis through `centre`: from the angle `a0` (rad round from +X toward +Z) on
## round by `turn` (signed: + toward +Z), its radius going from r0 to r1 and its height from y0 to y1 (world),
## the snake's back facing out from the axis by `out` (0: straight up, 1: straight out), every `step` m.
func helix(centre: Vector3, a0: float, turn: float, r0: float, r1: float, y0: float, y1: float, out := 1.0, step := 0.08) -> void:
	var arc := absf(turn) * (r0 + r1) * 0.5
	var n := maxi(ceili(sqrt(arc * arc + (y1 - y0) * (y1 - y0)) / step), 2)
	for i in n + 1:
		var t := float(i) / n
		var a := a0 + turn * t
		var radial := Vector3(cos(a), 0.0, sin(a))
		var r := lerpf(r0, r1, t)
		add(Vector3(centre.x, 0.0, centre.z) + radial * r + Vector3.UP * lerpf(y0, y1, t), Vector3.UP.slerp(radial, out))


## Turned by `angle` round the vertical axis through `pivot` (points and ups).
func turned(pivot: Vector3, angle: float) -> SerpentPath:
	if absf(angle) < 0.0001:
		return self
	var out := SerpentPath.new()
	var b := Basis(Vector3.UP, angle)
	for k in points.size():
		out.add(pivot + b * (points[k] - pivot), b * ups[k])
	return out
