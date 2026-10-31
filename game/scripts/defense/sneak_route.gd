class_name SneakRoute
extends RefCounted
## Routes over the open field round the stronghold that keep as far from the attackers as they can
## while still heading for where they go: an Infiltrator Squad's sabotage operations
## (InfiltratorSquad). A* on a grid of CELL-meter cells over the map (AStarGrid2D), every cell
## costing more the closer attackers are to it (THREAT_WEIGHT at an attacker, fading out at
## THREAT_RADIUS), so the route swings wide of them and goes straight where nobody is. The squad
## replans every few seconds as they move.
##
## Cells off the navmesh (the mountain, the helipads, rocks) are solid. The grid is laid out once per
## navmesh (rebaked when burnt trees fall): the troopers' own navmesh pathing goes round whatever it
## misses between cells.

const CELL := 5.0
## An attacker weighs on the cells within THREAT_RADIUS of it: entering one costs up to
## THREAT_WEIGHT times more next to it, fading out with distance (squared). Flyers count
## FLYER_SHARE as much (they see far, but move fast and high).
const THREAT_RADIUS := 45.0
const THREAT_WEIGHT := 14.0
const FLYER_SHARE := 0.4

static var _grid: AStarGrid2D
static var _iteration := -1
static var _n := 0
static var _origin := Vector2.ZERO


## How hard attackers press on `p`: 0 with none within THREAT_RADIUS, about 1 next to one (more
## with several).
static func threat_at(p: Vector3, units: Array) -> float:
	var t := 0.0
	for u in units:
		var d := Vector2(u.global_position.x - p.x, u.global_position.z - p.z).length()
		if d < THREAT_RADIUS:
			var f := 1.0 - d / THREAT_RADIUS
			t += f * f * (FLYER_SHARE if u.is_in_group("air_units") else 1.0)
	return t


## The attackers that count: alive, on the map.
static func attackers(ctx: Node) -> Array:
	return ctx.get_tree().get_nodes_in_group("attacker_units").filter(func(u): return u.is_alive())


## A route from `from` to `to` over the field, avoiding `units`: world points (on the ground), the
## first near `from`, the last `to`. Empty if the navmesh isn't up or there is no way there.
static func plan(world: World3D, from: Vector3, to: Vector3, units: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not _lay_out(world):
		return out
	_grid.fill_weight_scale_region(_grid.region, 1.0)
	var r := int(ceil(THREAT_RADIUS / CELL))
	for u in units:
		var p: Vector3 = u.global_position
		var c := _cell(p)
		var share := FLYER_SHARE if u.is_in_group("air_units") else 1.0
		for i in range(maxi(c.x - r, 0), mini(c.x + r + 1, _n)):
			for j in range(maxi(c.y - r, 0), mini(c.y + r + 1, _n)):
				var at := _centre(Vector2i(i, j))
				var d := Vector2(at.x - p.x, at.z - p.z).length()
				if d >= THREAT_RADIUS:
					continue
				var f := 1.0 - d / THREAT_RADIUS
				var id := Vector2i(i, j)
				_grid.set_point_weight_scale(id, _grid.get_point_weight_scale(id) + THREAT_WEIGHT * share * f * f)
	var a := _open_near(_cell(from))
	var b := _open_near(_cell(to))
	if a.x < 0 or b.x < 0:
		return out
	var ids := _grid.get_id_path(a, b)
	if ids.is_empty():
		return out
	for k in range(1, ids.size() - 1):
		out.append(_centre(ids[k]))
	out.append(Vector3(to.x, LevelBuilder.ground_height(to), to.z))
	return out


## The grid over the map: cells the navmesh covers at ground level, outside the mountain. Laid out
## again when the navmesh changes. False until the navmesh is up.
static func _lay_out(world: World3D) -> bool:
	var map := world.navigation_map
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if iteration <= 0:
		return false
	if _grid != null and iteration == _iteration:
		return true
	_iteration = iteration
	_n = int(ceil(LevelBuilder.map_half * 2.0 / CELL))
	_origin = Vector2(-LevelBuilder.map_half, -LevelBuilder.map_half)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _n, _n)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for i in _n:
		for j in _n:
			var c := _centre(Vector2i(i, j))
			var solid := LevelBuilder.base_distance(c) <= 1.0
			if not solid:
				var p := NavigationServer3D.map_get_closest_point(map, c + Vector3.UP * 0.5)
				solid = Vector2(p.x - c.x, p.z - c.z).length() > CELL * 0.5 or LevelBuilder.above_ground(p) > 1.5
			_grid.set_point_solid(Vector2i(i, j), solid)
	return true


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - _origin.x) / CELL)), 0, _n - 1),
			clampi(int(floor((p.z - _origin.y) / CELL)), 0, _n - 1))


static func _centre(c: Vector2i) -> Vector3:
	var p := Vector3(_origin.x + (c.x + 0.5) * CELL, 0.0, _origin.y + (c.y + 0.5) * CELL)
	p.y = LevelBuilder.ground_height(p)
	return p


## The open cell nearest `c` (itself if it is open), within a few cells; (-1, -1) if none.
static func _open_near(c: Vector2i) -> Vector2i:
	if not _grid.is_point_solid(c):
		return c
	for ring in range(1, 5):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for i in range(c.x - ring, c.x + ring + 1):
			for j in range(c.y - ring, c.y + ring + 1):
				var k := Vector2i(i, j)
				if not _grid.is_in_boundsv(k) or _grid.is_point_solid(k):
					continue
				var d := Vector2(k - c).length()
				if d < best_d:
					best_d = d
					best = k
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)
