class_name SerpentNest
extends RefCounted
## A Serpent Sniper's climb up a tree to its sniper nest (AttackerUnit, UnitTypes nest_*): where its body lies
## at each point of the climb, from on the ground at the foot of the trunk (progress 0) to perched in the crown
## (1), for SerpentRig. The front that carries the rifle (down to SerpentRig.SHOULDER) keeps its shape, held
## out from the shoulder (the rig's boom); the shoulder leads the rest of the body up its own way (way):
##   rearing up  the shoulder slides up to the foot of the trunk while the snout slides up the bark, the front
##               rising from the ground to upright against the trunk, belly to the bark
##   climbing    the shoulder winds up the trunk (CLIMB_PITCH above level), the body following it round and up
##               in a coil, the front upright along the bark above it
##   lying out   on top of the crown (ForestTree.perch) it winds round the trunk once more nearly level, the
##               rest of the body coiling round below it, and lays the front out level over the leaves, its back
##               up: toward the stronghold, or as near as the coil comes
## Climbing down is the same run backward. Perched, the nest turns round the trunk as the unit aims (yaw) and
## the front tips up or down onto what it shoots at (pitch).

## The middle of the body is this far out from the bark (m).
const BODY_R := 0.17
## How steeply the shoulder winds up the trunk (rad above level).
const CLIMB_PITCH := deg_to_rad(58.0)
## The front starts upright the bend onto the trunk this far up it (m).
const BEND_UP := 0.7
## The last of the climb winds round the trunk nearly level, rising this much (m), by between these many turns.
const COIL_RISE := 0.45
const COIL_TURNS := [0.6, 1.6]
## The front tips this far at most onto what it aims at (rad).
const MAX_PITCH := deg_to_rad(28.0)
## Several snakes sent at a tree take the free trees nearest it, no further than this from it (m).
const SPREAD := 25.0

var tree: ForestTree
## The trunk's foot (world).
var axis := Vector3.ZERO
## The shoulder's way: the body behind it as it lay on the ground, then up the trunk to the nest.
var way: SerpentPath
## Perched: turned this far round the trunk from the way it lay out (rad), and the front tipped up (+) or down.
var yaw := 0.0
var pitch := 0.0

## Arcs along `way`: the shoulder on the ground (progress 0), at the trunk's foot, where the last coil starts and
## where it ends (perched).
var _u0 := 0.0
var _u_foot := 0.0
var _u_coil := 0.0
var _u_end := 0.0
## Rearing up: the front's way and back as it lay, and the axis it tips up about.
var _fwd0 := Vector3.FORWARD
var _up0 := Vector3.UP
var _tip_axis := Vector3.RIGHT
var _tip_max := 0.0
var _snout_r := 0.2
var _heading := 0.0


## The climb up `p_tree` from `body` (SerpentRig.body_path: tail first, the snout last, as it lies now) on the
## ground at height `ground`, winding round the trunk `sign` (+1 or -1: toward +Z from +X, or back).
func _init(p_tree: ForestTree, body: SerpentPath, ground: float, sign := 1.0) -> void:
	tree = p_tree
	axis = tree.trunk_centre()
	axis.y = ground
	var length := body.length()
	way = body.head(length - SerpentRig.SHOULDER)
	_u0 = way.length()
	var start := way.end()
	_fwd0 = (body.end() - start).normalized()
	_up0 = (Vector3.UP - _fwd0 * Vector3.UP.dot(_fwd0)).normalized()
	_tip_axis = _fwd0.cross(Vector3.UP).normalized()
	_tip_max = _fwd0.angle_to(Vector3.UP)
	_snout_r = tree.trunk_radius(1.0) + 0.12
	var out := _flat(start - axis)
	out = out.normalized() if out.length() > 0.05 else -_flat(_fwd0).normalized()
	var a0 := atan2(out.z, out.x)
	var foot_r := tree.trunk_radius(0.0) + BODY_R
	# Along the ground to the foot of the trunk.
	var foot := axis + out * (foot_r + 0.35) + Vector3.UP * (start.y - axis.y)
	var n := maxi(ceili(start.distance_to(foot) / 0.1), 1)
	for i in range(1, n + 1):
		way.add(start.lerp(foot, float(i) / n), Vector3.UP)
	_u_foot = way.length()
	# The bend up onto the trunk, then winding up it.
	var climb_r := tree.trunk_radius(tree.perch * 0.5) + BODY_R
	var a1 := a0 + sign * 0.45
	var radial := Vector3(cos(a1), 0.0, sin(a1))
	var tangent := Vector3(-sin(a1), 0.0, cos(a1)) * sign
	var rise := tan(CLIMB_PITCH)
	var lift := (tangent + Vector3.UP * rise).normalized()
	way.bezier(-out, axis + radial * climb_r + Vector3.UP * BEND_UP, lift, radial, 0.4)
	var top := maxf(tree.perch - COIL_RISE, BEND_UP + 0.5)
	var coil_r := tree.trunk_radius(tree.perch) + BODY_R
	var turn := sign * (top - BEND_UP) / (rise * (climb_r + coil_r) * 0.5)
	way.helix(axis, a1, turn, climb_r, coil_r, axis.y + BEND_UP, axis.y + top)
	_u_coil = way.length()
	# Round once more nearly level, ending with the front laid out toward the stronghold (or near it).
	var a2 := a1 + turn
	var want := _flat(-axis).normalized()
	var best := COIL_TURNS[0]
	var best_dot := -INF
	for k in 65:
		var t: float = lerpf(COIL_TURNS[0], COIL_TURNS[1], k / 64.0)
		var a := a2 + sign * t * TAU
		var d := Vector3(-sin(a), 0.0, cos(a)) * sign
		if d.dot(want) > best_dot:
			best_dot = d.dot(want)
			best = t
	way.helix(axis, a2, sign * best * TAU, coil_r, coil_r, axis.y + top, axis.y + tree.perch)
	_u_end = way.length()
	var lay := _flat(way.tangent_at(_u_end - 0.05)).normalized()
	_heading = atan2(-lay.x, -lay.z)


## The unit's heading lying out, before it turns to aim (rotation.y).
func heading() -> float:
	return _heading


## How far the shoulder has come along its way at progress `p` (0-1): easing off the ground and into the nest.
func _u(p: float) -> float:
	var e := p * p * (3.0 - 2.0 * p)
	return lerpf(_u0, _u_end, lerpf(p, e, 0.6))


## The body at progress `p`: [the way for SerpentRig.lay, where the snout is along it, the boom (world:
## -Z toward the snout, Y out of the back)], turned round the trunk by yaw.
func pose(p: float) -> Array:
	var u := _u(p)
	var at := way.at(u)
	var fwd: Vector3
	var up: Vector3
	var radial := _flat(at - axis).normalized()
	if u < _u_coil:
		# Rearing up against the trunk: the snout rests on the bark as the shoulder comes up to its foot.
		var reach := maxf(_flat(at - axis).length() - _snout_r, 0.0)
		var tip := clampf(acos(clampf(reach / SerpentRig.SHOULDER, 0.0, 1.0)), 0.0, _tip_max)
		var b := Basis(_tip_axis, tip)
		fwd = b * _fwd0
		up = b * _up0
		if u > _u_foot:
			up = up.slerp(radial, clampf((u - _u_foot) / 0.6, 0.0, 1.0))
	else:
		# Lying out along a bough: from upright on the bark to level, back up.
		var m := clampf((u - _u_coil) / (_u_end - _u_coil), 0.0, 1.0)
		m = m * m * (3.0 - 2.0 * m)
		var along := _flat(way.tangent_at(minf(u, _u_end - 0.05))).normalized()
		fwd = Vector3.UP.slerp(along, m).normalized()
		up = radial.slerp(Vector3.UP, m)
	if pitch != 0.0 and p >= 1.0:
		var side := fwd.cross(up).normalized()
		fwd = fwd.rotated(side, pitch)
		up = up.rotated(side, pitch)
	up = (up - fwd * up.dot(fwd)).normalized()
	var boom := Transform3D(Basis.looking_at(fwd, up), at)
	var path := way
	if yaw != 0.0:
		var turn := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
		path = way.turned(axis, yaw)
		boom = Transform3D(turn.basis * boom.basis, axis + turn.basis * (boom.origin - axis))
	return [path, u + SerpentRig.SHOULDER, boom]


## Where the unit stands with the front held out along `boom` (pose()): the middle of the front, out of the
## trunk (what aims at it and what it sees from).
func anchor(boom: Transform3D) -> Vector3:
	var mid := boom.origin - boom.basis.z * 1.0
	var off := _flat(mid - axis)
	if off.length() < 0.65:
		mid += (off.normalized() if off.length() > 0.01 else Vector3.FORWARD) * (0.65 - off.length())
	return mid


## Turned round the trunk to face `heading` (rotation.y), and the front tipped up by `tip` (clamped).
func aim(heading_now: float, tip: float) -> void:
	yaw = wrapf(heading_now - _heading, -PI, PI)
	pitch = clampf(tip, -MAX_PITCH, MAX_PITCH)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ---------------------------------------------------------------- picking trees

## The standing tree whose crown or trunk the ray from `from` along `dir` passes through, nearest along it, or
## null (the attacking player picking one out: AttackerController).
static func tree_under(from: Vector3, dir: Vector3) -> ForestTree:
	var best: ForestTree = null
	var best_t := INF
	for tree in ForestTree.standing:
		var foot := tree.trunk_centre()
		var crown := foot + Vector3.UP * tree.height * 0.62
		for probe in [[crown, tree.canopy_radius * 0.85], [foot + Vector3.UP * tree.height * 0.25, 0.7]]:
			var t: float = (probe[0] - from).dot(dir)
			if t > 0.0 and t < best_t and (from + dir * t).distance_to(probe[0]) < probe[1]:
				best_t = t
				best = tree
	return best


## The standing tree nearest `at` (flat, from its trunk) within `reach`, or null.
static func tree_near(at: Vector3, reach: float) -> ForestTree:
	var best: ForestTree = null
	var best_d := reach
	for tree in ForestTree.standing:
		var d := _flat(tree.trunk_centre() - at).length()
		if d < best_d:
			best_d = d
			best = tree
	return best


## Trees for `snakes` sent at the tree at `at`: that one for the snake nearest it, and for the others the free
## standing trees nearest it within SPREAD, each to the snake nearest it, a tree to each: [[snake, tree], ...].
static func assign(snakes: Array, at: Vector3) -> Array:
	var first := tree_near(at, 2.0)
	if first == null or snakes.is_empty():
		return []
	var trees := ForestTree.standing.filter(func(t): return _flat(t.trunk_centre() - first.trunk_centre()).length() <= SPREAD \
			and (t.nest_by == null or not is_instance_valid(t.nest_by) or t.nest_by in snakes))
	trees.sort_custom(func(a, b): return _flat(a.trunk_centre() - at).length() < _flat(b.trunk_centre() - at).length())
	var left := snakes.duplicate()
	var out := []
	for tree in trees:
		if left.is_empty():
			break
		var near: AttackerUnit = left[0]
		for u in left:
			if _flat(u.global_position - tree.trunk_centre()).length() < _flat(near.global_position - tree.trunk_centre()).length():
				near = u
		left.erase(near)
		out.append([near, tree])
	return out
