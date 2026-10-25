class_name TalonAim
extends RefCounted
## Where each selected Sky Talon strafes or bombs when the player aims once.
##
##   Strafe run: one line on the ground (strafe_length long, centred where the player aims, along
##     the way the player drags). Several talons each fly a lane of their own parallel to it,
##     strafe_lane apart, side by side in the order they are in across it, so their lanes don't
##     cross or overlap. A lane has to lie inside its talon's circle (strafe_range round it): it
##     slides along itself until it does (staying parallel), or in toward the talon if it can't.
##   Bomb strike: like the bisons' shells, the bombs cluster round where the player aims, a few
##     splash radii apart (RhinoAim.cluster), each inside its talon's circle (bomb_range).
##     Against the mountain, a talon bombs flying along its face instead of into it.

const STRAFE_COLOR := Color(1.0, 0.45, 0.2)
const BOMB_COLOR := Color(1.0, 0.75, 0.25)
## Bombs land this many splash radii apart.
const BOMB_SPACING := 1.5


## The way a strafe aimed at `center` goes when the player doesn't drag: from the talons to it.
static func default_dir(talons: Array, center: Vector3) -> Vector3:
	var c := Vector3.ZERO
	for t in talons:
		c += t.global_position
	c /= talons.size()
	var d := center - c
	d.y = 0.0
	return d.normalized() if d.length() > 0.5 else -talons[0].global_basis.z


## One lane [start, end] per talon (same order), along `dir`, centred round `center`.
static func strafe(talons: Array, center: Vector3, dir: Vector3) -> Array:
	var out := []
	if talons.is_empty():
		return out
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var side := dir.cross(Vector3.UP)
	var length: float = talons[0].stats.strafe_length
	var spacing: float = talons[0].stats.strafe_lane
	# Lanes across the line in the order the talons are in across it.
	var order := range(talons.size())
	order.sort_custom(func(i, j): return (talons[i].global_position - center).dot(side) < (talons[j].global_position - center).dot(side))
	out.resize(talons.size())
	var space: PhysicsDirectSpaceState3D = talons[0].get_world_3d().direct_space_state
	for k in order.size():
		var i: int = order[k]
		var t: AttackerUnit = talons[i]
		var mid := center + side * (k - (order.size() - 1) * 0.5) * spacing
		mid = _fit(t.global_position, t.stats.strafe_range, mid, dir, side, length)
		var level := center.y
		out[i] = [RhinoAim.settle(space, mid - dir * length * 0.5, level), RhinoAim.settle(space, mid + dir * length * 0.5, level)]
	return out


## Slides a lane (centred on `mid`) along itself until both its ends are inside the circle of
## `reach` round `at`; if it is too far off to the side for that, in toward `at` too.
static func _fit(at: Vector3, reach: float, mid: Vector3, dir: Vector3, side: Vector3, length: float) -> Vector3:
	var q := mid - at
	var along := q.dot(dir)
	var across := q.dot(side)
	var half := length * 0.5
	var widest := sqrt(maxf(reach * reach - half * half, 0.0))
	across = clampf(across, -widest, widest)
	var room := sqrt(maxf(reach * reach - across * across, 0.0)) - half
	along = clampf(along, -room, room)
	var p := at + dir * along + side * across
	return Vector3(p.x, mid.y, p.z)


## One bomb spot per talon (same order), clustered round `target`, up on the gun decks and roofs too.
static func bombs(talons: Array, target: Vector3) -> Array[Vector3]:
	if talons.is_empty():
		return []
	var at: Array[Vector3] = []
	var reach: Array[float] = []
	for t in talons:
		at.append(t.global_position)
		reach.append(t.stats.bomb_range)
	var space: PhysicsDirectSpaceState3D = talons[0].get_world_3d().direct_space_state
	return RhinoAim.cluster(at, reach, talons[0].stats.bomb_splash * BOMB_SPACING, target, space)


## Which way a talon flies over its bomb spot: straight on from where it is, unless the mountain
## rises just past the spot; then slanting in along the face (the way closer to straight on), so
## it comes in over open ground and has room to pull away.
static func bomb_dir(talon: AttackerUnit, spot: Vector3) -> Vector3:
	var d := spot - talon.global_position
	d.y = 0.0
	d = d.normalized() if d.length() > 0.5 else -talon.global_basis.z
	var space := talon.get_world_3d().direct_space_state
	var past := RhinoAim.settle(space, spot + d * 16.0, spot.y + 40.0)
	if past.y < spot.y + 6.0:
		return d
	var out := Vector3(spot.x, 0.0, spot.z).normalized()
	var along := out.cross(Vector3.UP)
	if along.dot(d) < 0.0:
		along = -along
	return (along * 0.85 - out * 0.5).normalized()


## Each talon's circle, its lane and an arrow at the lane's end showing the way it flies.
## `im` is already in PRIMITIVE_LINES mode.
static func draw_strafe(im: ImmediateMesh, talons: Array, lanes: Array) -> void:
	var lift := Vector3.UP * 0.4
	for i in talons.size():
		var t: AttackerUnit = talons[i]
		var ground := Vector3(t.global_position.x, lanes[i][0].y, t.global_position.z)
		RhinoAim.dashed_circle(im, ground + lift, t.stats.strafe_range, 96)
		var p0: Vector3 = lanes[i][0] + lift
		var p1: Vector3 = lanes[i][1] + lift
		for w in [-0.35, 0.0, 0.35]:
			var side: Vector3 = (p1 - p0).normalized().cross(Vector3.UP) * w
			im.surface_add_vertex(p0 + side)
			im.surface_add_vertex(p1 + side)
		var back := (p0 - p1).normalized() * 3.0
		var across := back.cross(Vector3.UP).normalized() * 1.6
		im.surface_add_vertex(p1)
		im.surface_add_vertex(p1 + back + across)
		im.surface_add_vertex(p1)
		im.surface_add_vertex(p1 + back - across)


## Each talon's circle, its bomb's blast and a line from the talon to it.
static func draw_bombs(im: ImmediateMesh, talons: Array, spots: Array[Vector3]) -> void:
	var lift := Vector3.UP * 0.4
	for i in talons.size():
		var t: AttackerUnit = talons[i]
		var ground := Vector3(t.global_position.x, spots[i].y, t.global_position.z)
		RhinoAim.dashed_circle(im, ground + lift, t.stats.bomb_range, 96)
		RhinoAim.dashed_circle(im, spots[i] + lift, t.stats.bomb_splash, 20)
		im.surface_add_vertex(ground + lift)
		im.surface_add_vertex(spots[i] + lift)
