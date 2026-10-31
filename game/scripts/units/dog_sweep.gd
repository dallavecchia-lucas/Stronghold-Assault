class_name DogSweep
extends RefCounted
## Minesweeping, the Wolf Medic's second mode (AttackerUnit dog_mode "sweep"). The defenders' mines
## (GroundMine) are hidden from the attacking player, but a dog's nose finds every one within sweep_range of
## it. It walks up to one, digs it out and disarms it (disarm_time seconds), then goes for the next:
##
## - It never steps near a live mine to get to another. It only goes for a mine it can reach by a way that
##   keeps clear of every other mine (no nearer than SAFE; and of that one too, until the last step in to
##   dig), over open ground (the navmesh), and dig from a spot CLEAR of them. So a mine inside a minefield is
##   out of its reach until the ones round it are cleared, and the field is cleared from the outside in.
## - Of the mines it can reach, it takes the outer rim of the minefield first: the field is peeled in rings
##   (its convex hull, then the hull of what is left, and so on: _rings), a ring further in costs RIM_WEIGHT
##   metres of walk more; then the nearest.
## - Dogs sweeping together share the field out: a mine one dog has taken (GroundMine.sweeper) the others
##   leave to it, and their dig spots keep SPOT_ROOM apart.
##
## plan() finds a dog its next mine, the spot to dig it from and the way there (a grid search, CELL square,
## eight ways, round the mines and off the navmesh); blocked() tells whether the way a dog is on still keeps
## clear of every mine (another may have landed on it since).

const CELL := 0.5
## A mine goes off within GroundMine.TRIGGER_RADIUS of a body: about 2.05 m from a dog's middle (it is 0.55 m
## round). No point of a dog's way comes closer than SAFE to a live mine, but to the one it digs out; a dog
## that already stands closer than that (sent there) never goes any closer.
const SAFE := 2.1
## The spots dogs dig from keep CLEAR from every other mine, and so do the middles of the cells the grid
## lets them through: anywhere in such a cell is more than SAFE from it (with room for the dog to cut a
## corner by WAYPOINT).
const CLEAR := 2.6
## A dog takes the next point of its way once it is this close to it (m).
const WAYPOINT := 0.12
## The dog digs a mine out standing this far from it (m), facing it: its fore paws scrape over it.
const DIG_REACH := 0.8
## Ways round a mine it may dig it from.
const SIDES := 16
## Mines this close together (m, flat) are one minefield.
const FIELD_GAP := 7.0
## The outer rim first: a mine a ring further in costs this many metres of walk more.
const RIM_WEIGHT := 10.0
## Two dogs' dig spots keep this far apart (m).
const SPOT_ROOM := 1.6
## The grid reaches this far past the dog and the mines it found (m).
const MARGIN := 5.0
## Grid steps: the four straight ones (cost 2), then the four diagonal ones (cost 3).
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const DIRT := Color(0.36, 0.27, 0.17)

## Open ground: grid cell (CELL, on the world's grid) -> on the navmesh, as of navigation map iteration
## _walk_iter (a forest burnt down rebakes it).
static var _walk := {}
static var _walk_iter := -1
static var _dirt_mesh: BoxMesh


## The dog's next mine: {"mine": GroundMine, "spot": where it digs from, "path": the way there (points,
## the spot last)}, or {} if it finds none it can get to.
static func plan(dog: AttackerUnit) -> Dictionary:
	var here := dog.global_position
	var live: Array = GroundMine.all.filter(func(m): return m.is_laid())
	var found: Array = live.filter(func(m): return _flat(m.spot(), here) <= dog.stats.sweep_range \
			and (m.sweeper == null or m.sweeper == dog or not is_instance_valid(m.sweeper) or not m.sweeper.is_alive()))
	if found.is_empty():
		return {}
	var map := dog.get_world_3d().navigation_map
	var iter := NavigationServer3D.map_get_iteration_id(map)
	if iter != _walk_iter:
		_walk.clear()
		_walk_iter = iter
	# The grid: round the dog and the mines it found, on the world's grid of cells.
	var lo := Vector2(here.x, here.z)
	var hi := lo
	for m in found:
		var p: Vector3 = m.spot()
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var c0 := Vector2i(floori((lo.x - MARGIN) / CELL), floori((lo.y - MARGIN) / CELL))
	var c1 := Vector2i(ceili((hi.x + MARGIN) / CELL), ceili((hi.y + MARGIN) / CELL))
	var w := c1.x - c0.x + 1
	var h := c1.y - c0.y + 1
	var grid := {"c0": c0, "w": w, "h": h, "map": map, "y": here.y}
	# Cells too close to a live mine: within CLEAR of it, and closer than the dog stands now.
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	for m in live:
		var p: Vector3 = m.spot()
		var r := minf(CLEAR, _flat(p, here) - 0.05)
		if r <= 0.0:
			continue
		for y in range(maxi(floori((p.z - r) / CELL) - c0.y, 0), mini(ceili((p.z + r) / CELL) - c0.y, h - 1) + 1):
			for x in range(maxi(floori((p.x - r) / CELL) - c0.x, 0), mini(ceili((p.x + r) / CELL) - c0.x, w - 1) + 1):
				if Vector2((c0.x + x) * CELL - p.x, (c0.y + y) * CELL - p.z).length() < r:
					blocked[y * w + x] = 1
	grid.blocked = blocked
	var cost := _search(grid, here)
	var taken := _taken_spots(dog)
	var rings := _rings(live)
	var best := {}
	var best_score := INF
	var reach := CLEAR + CELL * 1.5 + CLEAR
	for m in found:
		var near := live.filter(func(o): return o != m and _flat(o.spot(), m.spot()) < reach)
		var side := _best_side(grid, cost, m, near, taken)
		if side.is_empty():
			continue
		var score: float = side.cost + RIM_WEIGHT * rings.get(m, 0)
		if score < best_score:
			best_score = score
			best = side
			best.mine = m
	if best.is_empty():
		return {}
	var path := _path(grid, cost, best.entry)
	path.append(best.entry_at)
	path.append(best.spot)
	return {"mine": best.mine, "spot": best.spot, "path": path}


## True if the way left (`path`, to dig `target` out) comes too close to a live mine other than `target`:
## within SAFE of it, and closer than the dog stands now. A way plan() has just found never does.
static func blocked(dog: AttackerUnit, path: Array[Vector3], target: GroundMine) -> bool:
	var at := dog.global_position
	var pts: Array[Vector3] = [at]
	pts.append_array(path)
	for m in GroundMine.all:
		if m == target or not m.is_laid():
			continue
		var p: Vector3 = m.spot()
		var r := minf(SAFE, _flat(p, at) - 0.05)
		for k in pts.size() - 1:
			if _segment_dist(p, pts[k], pts[k + 1]) < r:
				return true
	return false


## Dirt thrown back from under a digging dog's chest at `from`, flying out `back` (flat) between its
## hind legs.
static func spray(ctx: Node3D, from: Vector3, back: Vector3) -> void:
	if _dirt_mesh == null:
		_dirt_mesh = BoxMesh.new()
		_dirt_mesh.size = Vector3(0.07, 0.05, 0.07)
	var root := ctx.get_tree().current_scene
	for k in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = _dirt_mesh
		mi.material_override = Mats.flat(DIRT.darkened(0.12 * (k % 3)), 0.0, 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var side := back.cross(Vector3.UP) * randf_range(-0.9, 0.9)
		var v := (back * randf_range(2.2, 3.6) + side + Vector3.UP * randf_range(1.6, 2.8))
		var start := from + Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
		var t_end := 2.0 * v.y / 9.8
		mi.global_position = start
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
		var tw := mi.create_tween()
		tw.tween_method(func(t: float): mi.global_position = start + v * t + Vector3.DOWN * 4.9 * t * t, 0.0, t_end, t_end)
		tw.tween_interval(0.6)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(mi.queue_free)
	if randf() < 0.5:
		SmokeCloud.wisp(ctx, from + back * 0.8 + Vector3.UP * 0.2, 0.45)


# ---------------------------------------------------------------- the grid

## Cost of the cheapest way from the dog's cell to every cell it can get to (-1: none): Dial's algorithm,
## 2 a straight step and 3 a diagonal one (no cutting a blocked corner). Cells off the navmesh are blocked as
## they are found.
static func _search(grid: Dictionary, here: Vector3) -> PackedInt32Array:
	var w: int = grid.w
	var h: int = grid.h
	var blocked: PackedByteArray = grid.blocked
	var cost := PackedInt32Array()
	cost.resize(w * h)
	cost.fill(-1)
	var start := _cell(grid, here)
	var si := start.y * w + start.x
	blocked[si] = 0  # where it stands
	cost[si] = 0
	# Buckets by cost (plain arrays: a packed one held in an array is a copy once appended to).
	var buckets: Array = [[si]]
	var c := 0
	while c < buckets.size():
		for i: int in buckets[c]:
			if cost[i] != c:
				continue
			var x := i % w
			var y := i / w
			for s in 8:
				var step: Vector2i = STEPS[s]
				var nx := x + step.x
				var ny := y + step.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if blocked[j]:
					continue
				if s >= 4 and (blocked[y * w + nx] or blocked[ny * w + x]):
					continue
				var nc := c + (3 if s >= 4 else 2)
				if cost[j] >= 0 and cost[j] <= nc:
					continue
				if cost[j] < 0 and not _open(grid, nx, ny):
					blocked[j] = 1
					continue
				cost[j] = nc
				while buckets.size() <= nc:
					buckets.append([])
				buckets[nc].append(j)
		c += 1
	return cost


## The best way round `m` to dig it from: {"spot", "entry" (a cell outside the mine's CLEAR the search got
## to, straight out from the spot), "entry_at" (the point straight out from the spot in that cell), "cost"
## (m of walk)}, or {} if there is none. `near`: the other live mines near enough to be in the way.
static func _best_side(grid: Dictionary, cost: PackedInt32Array, m: GroundMine, near: Array, taken: Array) -> Dictionary:
	var p: Vector3 = m.spot()
	var best := {}
	var out := CLEAR + CELL * 1.5
	for k in SIDES:
		var a := TAU * k / SIDES
		var dir := Vector3(cos(a), 0.0, sin(a))
		var spot := p + dir * DIG_REACH
		var room := true
		for t in taken:
			room = room and _flat(t, spot) >= SPOT_ROOM
		if not room:
			continue
		# Straight in from the entry to the spot: open ground, the spot CLEAR of every other mine and the way in
		# SAFE (and a corner's cut) from them.
		var clear := true
		var r := DIG_REACH
		while r <= out and clear:
			var q := p + dir * r
			clear = _open_at(grid, q)
			for o in near:
				clear = clear and _flat(o.spot(), q) >= (CLEAR if r == DIG_REACH else SAFE + WAYPOINT)
			r += CELL * 0.25
		if not clear:
			continue
		var e := _cell(grid, p + dir * out)
		if e.x < 0 or e.y < 0 or e.x >= grid.w or e.y >= grid.h:
			continue
		var c := cost[e.y * grid.w + e.x]
		if c < 0:
			continue
		var total := c * CELL * 0.5 + (out - DIG_REACH)
		if best.is_empty() or total < best.cost:
			best = {"spot": _ground(grid, spot), "entry": e, "entry_at": _ground(grid, p + dir * out), "cost": total}
	return best


## The way from the dog to `entry` (a cell), straightened where the line between two points stays on open
## cells the search reached.
static func _path(grid: Dictionary, cost: PackedInt32Array, entry: Vector2i) -> Array[Vector3]:
	var w: int = grid.w
	var cells: Array[Vector2i] = [entry]
	var at := entry
	while cost[at.y * w + at.x] > 0:
		var best := at
		var best_c := cost[at.y * w + at.x]
		for s in 8:
			var step: Vector2i = STEPS[s]
			var n := at + step
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= grid.h:
				continue
			var nc := cost[n.y * w + n.x]
			if nc >= 0 and nc + (3 if s >= 4 else 2) == cost[at.y * w + at.x] and nc < best_c:
				best = n
				best_c = nc
		if best == at:
			break
		at = best
		cells.push_front(at)
	var path: Array[Vector3] = []
	var k := 0
	while k < cells.size() - 1:
		var far := k + 1
		for j in range(cells.size() - 1, k + 1, -1):
			if _straight(grid, cost, cells[k], cells[j]):
				far = j
				break
		path.append(_ground(grid, _centre(grid, cells[far])))
		k = far
	return path


## The line from cell a to cell b stays on cells the search reached (sampled an eighth of a cell apart).
static func _straight(grid: Dictionary, cost: PackedInt32Array, a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 8
	for k in range(1, n):
		var f := float(k) / n
		var x := roundi(lerpf(a.x, b.x, f))
		var y := roundi(lerpf(a.y, b.y, f))
		if cost[y * grid.w + x] < 0:
			return false
	return true


static func _cell(grid: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL)) - (grid.c0 as Vector2i)


static func _centre(grid: Dictionary, c: Vector2i) -> Vector3:
	var g: Vector2i = c + (grid.c0 as Vector2i)
	return Vector3(g.x * CELL, grid.y, g.y * CELL)


static func _open(grid: Dictionary, x: int, y: int) -> bool:
	return _walkable(grid.map, x + grid.c0.x, y + grid.c0.y, grid.y)


static func _open_at(grid: Dictionary, p: Vector3) -> bool:
	return _walkable(grid.map, roundi(p.x / CELL), roundi(p.z / CELL), grid.y)


## World grid cell (gx, gy) is on the navmesh (cached until it is rebaked).
static func _walkable(map: RID, gx: int, gy: int, y: float) -> bool:
	var key := Vector2i(gx, gy)
	var v = _walk.get(key)
	if v == null:
		var p := Vector3(gx * CELL, y + 0.5, gy * CELL)
		var c := LevelBuilder.nav_closest(map, p)
		v = Vector2(c.x - p.x, c.z - p.z).length() < CELL * 0.6 and absf(c.y - y) < 3.0
		_walk[key] = v
	return v


## `p` put down on the navmesh (its height there).
static func _ground(grid: Dictionary, p: Vector3) -> Vector3:
	var c := LevelBuilder.nav_closest(grid.map, Vector3(p.x, grid.y + 0.5, p.z))
	return Vector3(p.x, c.y, p.z)


# ---------------------------------------------------------------- the minefields

## Each live mine's ring in its minefield, from the outside in (0 the rim): the mines within FIELD_GAP of
## each other are one field; its convex hull is ring 0, the hull of what is left ring 1, and so on.
static func _rings(live: Array) -> Dictionary:
	var rings := {}
	var field := {}
	for m in live:
		field[m] = m
	var root := func(m):
		while field[m] != m:
			m = field[m]
		return m
	for i in live.size():
		for j in range(i + 1, live.size()):
			if _flat(live[i].spot(), live[j].spot()) <= FIELD_GAP:
				field[root.call(live[i])] = root.call(live[j])
	var fields := {}
	for m in live:
		var r = root.call(m)
		if not fields.has(r):
			fields[r] = []
		fields[r].append(m)
	for f in fields.values():
		var left: Array = f.duplicate()
		var ring := 0
		while not left.is_empty():
			var hull: Array = left
			if left.size() > 3:
				var pts := PackedVector2Array()
				for m in left:
					pts.append(Vector2(m.spot().x, m.spot().z))
				var outline := Geometry2D.convex_hull(pts)
				hull = left.filter(func(m): return outline.has(Vector2(m.spot().x, m.spot().z)))
				if hull.is_empty():
					hull = left
			for m in hull:
				rings[m] = ring
			left = left.filter(func(m): return not m in hull)
			ring += 1
	return rings


## Where the other sweeping dogs dig or are going to dig.
static func _taken_spots(dog: AttackerUnit) -> Array:
	var out := []
	for u in dog.get_tree().get_nodes_in_group("attacker_units"):
		if u != dog and u.has_dog_modes() and u.sweep_mine != null:
			out.append(u.sweep_spot())
	return out


static func _segment_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := 0.0 if ab.length_squared() < 1e-6 else clampf((q - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return q.distance_to(a2 + ab * t)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
