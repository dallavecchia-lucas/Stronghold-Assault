class_name SquadFormation
extends RefCounted
## Where a Gunner Squad's followers stand around their leader (GunnerSquad).
##
## In the open they hold a wedge with the leader in its middle: two troopers out ahead to either
## side, two wider and behind, so every gun has a clear line forward. Every spot is checked against
## the navmesh before it is handed out: inside a tree, a rock or a wall it slides to the nearest
## free ground, and it has to be reachable from the leader without a detour (not on the far side of
## a wall or up on another floor) and clear of the other spots. When that fails the wedge squeezes
## in from the sides, and in passages too tight for any wedge the squad files along the way the
## leader came: two abreast where the passage is wide enough, else in single file. Wider shapes
## come back only once they have fitted for a moment, so the squad doesn't flicker between them at
## a tunnel mouth. In a column the troopers keep their order down the trail (the one furthest along
## it goes first) instead of trading places for shorter walks: in a tunnel nobody can get past.

enum Mode { WEDGE, SQUEEZED, PAIRS, FILE }
const MODE_NAMES := ["WEDGE", "SQUEEZED", "PAIRS", "FILE"]

## Wedge spots, x to the right and y ahead of the leader (m). Fewer followers take the first ones.
const WEDGE: Array[Vector2] = [Vector2(-2.3, 1.3), Vector2(2.3, 1.3), Vector2(-4.4, -1.8), Vector2(4.4, -1.8)]
## How far the wedge may squeeze in from the sides before the squad files instead.
const SQUEEZE: Array[float] = [0.72, 0.5]
## Columns along the leader's trail: first trooper this far back, then this far apart (m), and
## pairs side by side this far either side of the trail.
const TRAIL_FIRST := 2.5
const TRAIL_SPACING := 2.4
const PAIR_HALF := 0.95
## Single file staggers a little to either side where there is room.
const STAGGER := 0.35
## How far a spot may slide to reach free ground, how close two troopers may stand, and how much
## room a pair needs beyond its spot (m).
const SNAP := 0.85
const MIN_GAP := 1.3
const PAIR_ROOM := 0.35
## A spot is out of reach if the way there from the leader is longer than this times the straight
## line, plus DETOUR_SLACK (m).
const DETOUR := 1.5
const DETOUR_SLACK := 1.5
## Leader positions recorded this far apart, up to TRAIL_LENGTH of them (m).
const TRAIL_STEP := 0.35
const TRAIL_LENGTH := 30.0
## Seconds a wider shape has to keep fitting before the squad spreads out into it.
const WIDEN_DELAY := 0.6
## In a column, a trooper this much further along the trail than the one ahead of it takes its place.
const ORDER_SLACK := 0.8

var nav_map: RID
var nav_layers := 1
var mode := Mode.WEDGE
## The spots handed out last were a column (PAIRS or FILE) along the trail.
var column := false
var _column_shape := Mode.FILE
## Leader positions, newest first.
var trail: Array[Vector3] = []

var _wider := Mode.WEDGE
var _wider_t := 0.0
var _assign: Array[int] = []
var _heading := 0.0


## Records the leader's position on its trail. A sharp turn back drops the old trail: behind the
## leader is now the other way.
func record(leader: Vector3, velocity: Vector3) -> void:
	if trail.size() >= 2 and velocity.length() > 0.4:
		var last := trail[0] - trail[1]
		if Vector2(last.x, last.z).normalized().dot(Vector2(velocity.x, velocity.z).normalized()) < -0.5:
			trail.resize(1)
	if trail.is_empty() or trail[0].distance_to(leader) >= TRAIL_STEP:
		trail.push_front(leader)
		var total := 0.0
		for i in range(1, trail.size()):
			total += trail[i].distance_to(trail[i - 1])
			if total > TRAIL_LENGTH:
				trail.resize(i + 1)
				break


## Spots for `followers` (their positions, in a stable order) around the leader facing `heading`
## (yaw, 0 = -Z). Returns one world position per follower, in the same order. Call a few times a
## second; between calls the squad carries the spots along with the leader.
func solve(leader: Vector3, heading: float, followers: Array, delta: float) -> Array[Vector3]:
	var n := followers.size()
	var out: Array[Vector3] = []
	if n == 0:
		return out
	_heading = heading
	var start := NavigationServer3D.map_get_closest_point(nav_map, leader + Vector3.UP * 0.5)
	var shapes := [Mode.WEDGE, Mode.SQUEEZED, Mode.SQUEEZED, Mode.PAIRS, Mode.FILE]
	var squeeze := [1.0, SQUEEZE[0], SQUEEZE[1], 0.0, 0.0]
	var found := Mode.FILE
	var spots: Array[Vector3] = []
	for k in shapes.size():
		var m: Mode = shapes[k]
		var s := _shape(m, squeeze[k], leader, start, heading, n)
		if s.size() == n:
			found = m
			spots = s
			break
	if spots.is_empty():
		spots = _file(leader, start, n, false)
	var shape := found
	# Narrower shapes take over at once; wider ones once they have fitted for WIDEN_DELAY.
	if found > mode:
		mode = found
		_wider_t = 0.0
	elif found < mode:
		if found != _wider:
			_wider = found
			_wider_t = 0.0
		_wider_t += delta
		if _wider_t >= WIDEN_DELAY:
			mode = found
			_wider_t = 0.0
		else:
			var keep := _shape(mode, squeeze[shapes.find(mode)], leader, start, heading, n)
			if keep.size() == n:
				spots = keep
				shape = mode
			elif mode >= Mode.PAIRS:
				# Still a column until it has widened: down the trail as the leader walked it.
				spots = _file(leader, start, n, false)
				shape = Mode.FILE
	else:
		_wider_t = 0.0
	var was_column := column
	column = shape >= Mode.PAIRS
	if column:
		_column_shape = shape
		return _column_assigned(spots, followers, leader, shape, was_column)
	return _assigned(spots, followers)


## How far back along the trail slot `slot` of the column is (m), and how far to the side of it.
func slot_back(slot: int) -> float:
	return TRAIL_FIRST + float(slot / 2 if _column_shape == Mode.PAIRS else slot) * TRAIL_SPACING


func slot_side(slot: int) -> float:
	if _column_shape != Mode.PAIRS:
		return 0.0
	return PAIR_HALF if slot % 2 == 0 else -PAIR_HALF


## Follower i's slot (index into the spots handed out last).
func slot_of(i: int) -> int:
	return _assign[i] if i < _assign.size() else i


## [point, sideways unit vector] `dist` meters back along the trail from the leader.
func along(dist: float, leader: Vector3) -> Array:
	return _along(dist, leader)


## Where `p` is on the way the leader came: [meters back along the trail to the point on it nearest
## p, how far off the trail p is (flat)]. Only parts of it within a step of p's height count (not
## the ramp beside it); none: [INF, INF].
func locate(p: Vector3, leader: Vector3) -> Array:
	var best_back := INF
	var best_off := INF
	var back := 0.0
	var a := leader
	for b in trail:
		var ab := b - a
		var flat2 := ab.x * ab.x + ab.z * ab.z
		var u := 0.0
		if flat2 > 0.000001:
			u = clampf(((p.x - a.x) * ab.x + (p.z - a.z) * ab.z) / flat2, 0.0, 1.0)
		var q := a + ab * u
		var seg := a.distance_to(b)
		var off := _flat(p, q)
		if off < best_off and absf(p.y - q.y) < 0.5:
			best_off = off
			best_back = back + seg * u
		back += seg
		a = b
	return [best_back, best_off]


## The spots of one shape, or fewer than n if it doesn't fit.
func _shape(m: Mode, squeeze: float, leader: Vector3, start: Vector3, heading: float, n: int) -> Array[Vector3]:
	match m:
		Mode.WEDGE, Mode.SQUEEZED:
			return _wedge(leader, start, heading, n, squeeze)
		Mode.PAIRS:
			return _pairs(leader, start, n)
	return _file(leader, start, n, true)


func _wedge(leader: Vector3, start: Vector3, heading: float, n: int, squeeze: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var basis := Basis(Vector3.UP, heading)
	for i in n:
		var o := WEDGE[i]
		var want := leader + basis * Vector3(o.x * squeeze, 0.0, -o.y)
		var p = _spot(want, leader, start, out, 0.0)
		if p == null:
			return out
		out.append(p)
	return out


func _pairs(leader: Vector3, start: Vector3, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var at := _along(TRAIL_FIRST + float(i / 2) * TRAIL_SPACING, leader)
		var side := at[1] as Vector3
		var want: Vector3 = at[0] + side * (PAIR_HALF if i % 2 == 0 else -PAIR_HALF)
		var p = _spot(want, leader, start, out, PAIR_ROOM, side)
		if p == null:
			return out
		out.append(p)
	return out


## Single file down the trail. `strict` means each spot must check out (for choosing the shape);
## otherwise the trail points are used as they are (the leader walked there).
func _file(leader: Vector3, start: Vector3, n: int, strict: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var at := _along(TRAIL_FIRST + float(i) * TRAIL_SPACING, leader)
		var side := at[1] as Vector3
		var base: Vector3 = at[0]
		var p = _spot(base + side * (STAGGER if i % 2 == 0 else -STAGGER), leader, start, out, 0.1, side)
		if p == null:
			p = _spot(base, leader, start, out, 0.0)
		if p == null:
			if strict:
				return out
			p = base
		out.append(p)
	return out


## [point, sideways unit vector] `dist` meters back along the leader's trail. Past its end the
## trail runs on straight back the way the leader came.
func _along(dist: float, leader: Vector3) -> Array:
	var pts: Array[Vector3] = [leader]
	pts.append_array(trail)
	var left := dist
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		if left <= seg:
			var dir := (b - a) / seg
			return [a + dir * left, _side(dir)]
		left -= seg
	var tail := pts[-1]
	var back := Basis(Vector3.UP, _heading) * Vector3.BACK  # behind the way the squad faces
	if pts.size() >= 2:
		var run := pts[-1] - pts[-2]
		run.y = 0.0
		if run.length() > 0.01:
			back = run.normalized()
	return [tail + back * left, _side(back)]


static func _side(dir: Vector3) -> Vector3:
	var s := Vector3(dir.z, 0.0, -dir.x)
	return s.normalized() if s.length() > 0.001 else Vector3.RIGHT


## The free ground nearest `want`, or null if there is none close by, it can't be reached from the
## leader without a detour, or it crowds another spot. `room` asks for that much clear ground beyond
## the spot along `side` (both ways).
func _spot(want: Vector3, leader: Vector3, start: Vector3, taken: Array[Vector3], room: float, side := Vector3.ZERO):
	var c := NavigationServer3D.map_get_closest_point(nav_map, want + Vector3.UP * 0.5)
	if _flat(c, want) > SNAP or absf(c.y - start.y) > 1.6:
		return null
	if room > 0.0:
		for s in [side, -side]:
			var probe: Vector3 = c + s * room
			var pc := NavigationServer3D.map_get_closest_point(nav_map, probe + Vector3.UP * 0.5)
			if _flat(pc, probe) > 0.12:
				return null
	if _flat(c, leader) < MIN_GAP:
		return null
	for t in taken:
		if _flat(c, t) < MIN_GAP:
			return null
	var path := NavigationServer3D.map_get_path(nav_map, start, c, true, nav_layers)
	if path.is_empty() or path[-1].distance_to(c) > 0.4:
		return null
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	if length > _flat(start, c) * DETOUR + DETOUR_SLACK:
		return null
	return Vector3(c.x, leader.y, c.z)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Column spots go out in trail order: the follower furthest along the trail takes the slot nearest
## the leader, and the order only changes when one gets clearly ahead of the one before it. Side by
## side (PAIRS), each of a pair takes the side it is already on.
func _column_assigned(spots: Array[Vector3], followers: Array, leader: Vector3, shape: Mode, keep_order: bool) -> Array[Vector3]:
	var n := spots.size()
	var key := []
	for p in followers:
		var at := locate(p, leader)
		key.append(at[0] if at[0] < INF else 1000.0 + _flat(p, leader))
	var order := range(n)
	if keep_order and _assign.size() == n:
		order.sort_custom(func(a, b): return _assign[a] < _assign[b])
	else:
		order.sort_custom(func(a, b): return key[a] < key[b])
	for pass_i in n:
		for j in n - 1:
			if key[order[j + 1]] + ORDER_SLACK < key[order[j]]:
				var x = order[j]
				order[j] = order[j + 1]
				order[j + 1] = x
	_assign.resize(n)
	for k in n:
		_assign[order[k]] = k
	if shape == Mode.PAIRS:
		for k in range(0, n - 1, 2):
			var a: int = order[k]
			var b: int = order[k + 1]
			var at := _along(TRAIL_FIRST + float(k / 2) * TRAIL_SPACING, leader)
			var side := at[1] as Vector3
			# Slot k is on the +side.
			if (followers[b] - at[0]).dot(side) > (followers[a] - at[0]).dot(side):
				_assign[a] = k + 1
				_assign[b] = k
	var out: Array[Vector3] = []
	for i in n:
		out.append(spots[_assign[i]])
	return out


## Hands the spots out so the troopers have the least walking to do (and don't swap sides for
## nothing): every pairing is tried, and the current one stays unless another is clearly shorter.
## In a column, the nearest trooper takes the spot nearest the leader.
func _assigned(spots: Array[Vector3], followers: Array) -> Array[Vector3]:
	var n := spots.size()
	if _assign.size() != n:
		_assign.clear()
		for i in n:
			_assign.append(i)
	var best: Array = _assign.duplicate()
	var best_cost := _cost(spots, followers, _assign)
	var keep_cost := best_cost
	for perm in _perms(n):
		var c := _cost(spots, followers, perm)
		if c < best_cost:
			best_cost = c
			best = perm
	if best_cost < keep_cost * 0.85:
		_assign.assign(best)
	var out: Array[Vector3] = []
	for i in n:
		out.append(spots[_assign[i]])
	return out


static func _cost(spots: Array[Vector3], followers: Array, perm: Array) -> float:
	var c := 0.0
	for i in perm.size():
		c += _flat(followers[i], spots[perm[i]]) ** 2
	return c


static var _perm_cache := {}


static func _perms(n: int) -> Array:
	if _perm_cache.has(n):
		return _perm_cache[n]
	var out := []
	_permute([], range(n), out)
	_perm_cache[n] = out
	return out


static func _permute(prefix: Array, rest: Array, out: Array) -> void:
	if rest.is_empty():
		out.append(prefix)
		return
	for i in rest.size():
		var r := rest.duplicate()
		var x = r.pop_at(i)
		_permute(prefix + [x], r, out)
