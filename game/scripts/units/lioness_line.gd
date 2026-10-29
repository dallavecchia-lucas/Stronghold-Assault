class_name LionessLine
extends RefCounted
## Lionesses moved together (AttackerCommander._move) form up in firing lines as they go, like the line
## infantry of the American Revolution and Napoleon's wars: abreast in a rank of up to PER_RANK, facing
## the way they go, and more ranks of up to PER_RANK one behind another, each centred on the line's
## middle.
##
## They don't stop to form up. The line's middle sets off from the back of the group and advances at
## PACE of its slowest lioness's speed (slower while they sneak), never more than LEAD ahead of the
## lioness furthest behind her spot. Each lioness makes for her spot in it, running to catch up where
## she is behind it and holding back where she is ahead (only stepping sideways into her file, so
## nobody turns back), and they come into line on the way. At the end each stands on her spot, facing
## the way the line went (AttackerUnit._line_step).
##
## A lioness given another order leaves the line; one fighting (on an attack-move) falls out of step
## and catches up after. The attacking player turns lines off and on (AttackerCommander.line_formation).

const PER_RANK := 8
## Between neighbours' middles in a rank, and between ranks (m): wide enough that lionesses standing
## near their spots never crowd each other's avoidance.
const FILE_GAP := 2.4
const RANK_GAP := 3.6
const PACE := 0.85
const LEAD := 2.0
## Speed a lioness puts on per metre she is off her spot (m/s per m), on top of the pace.
const CATCH := 1.5
## Within this of her spot (m) she just marches with the line; once it has arrived, she slows onto her
## spot (m/s per m off it) and stands within ON_SPOT of it.
const IN_STEP := 0.25
const SETTLE := 3.0
const ON_SPOT := 0.3

var members: Array = []
## Lioness -> her spot: Vector2(right of the line's middle, behind its front rank).
var slots := {}
var start := Vector3.ZERO
var dest := Vector3.ZERO
var dir := Vector3.FORWARD
var right := Vector3.RIGHT
var length := 0.0
## How far the front rank's middle has come from `start` along `dir`.
var progress := 0.0
## m/s the line marches at, as of the last update.
var pace := 0.0


## Spots for `count` lionesses, rank by rank from the front, each rank centred.
static func spots(count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for r in ceili(float(count) / PER_RANK):
		var n := mini(PER_RANK, count - r * PER_RANK)
		for k in n:
			out.append(Vector2((k - (n - 1) * 0.5) * FILE_GAP, r * RANK_GAP))
	return out


## A line for `units` going to `to`: the front rank's middle ends there.
static func make(units: Array, to: Vector3) -> LionessLine:
	var line := LionessLine.new()
	var c := Vector3.ZERO
	for u in units:
		c += u.global_position
	c /= units.size()
	var way := Vector3(to.x - c.x, 0.0, to.z - c.z)
	if way.length() < 1.0:
		way = -units[0].global_basis.z  # barely moving: they face the way the first one faces
		way.y = 0.0
	line.dir = way.normalized()
	line.right = line.dir.cross(Vector3.UP).normalized()
	line.dest = to
	line.length = line.dir.dot(to - c)
	line.start = to - line.dir * line.length
	# The lionesses furthest ahead take the front rank, each rank handed out left to right as they
	# stand, so nobody crosses another's path.
	var free := spots(units.size())
	var queue := units.duplicate()
	queue.sort_custom(func(a, b): return line.dir.dot(a.global_position) > line.dir.dot(b.global_position))
	var k := 0
	while k < queue.size():
		var rank := queue.slice(k, k + PER_RANK)
		var places := free.slice(k, k + PER_RANK)
		rank.sort_custom(func(a, b): return line.right.dot(a.global_position) < line.right.dot(b.global_position))
		places.sort_custom(func(a, b): return a.x < b.x)
		for i in rank.size():
			line.slots[rank[i]] = places[i]
		k += PER_RANK
	line.members = units.duplicate()
	line.progress = INF
	for u in units:
		line.progress = minf(line.progress, line.own(u))
	line.progress = minf(line.progress, line.length)
	return line


## How deep the line is, front rank to back (m).
func depth() -> float:
	return (ceili(float(slots.size()) / PER_RANK) - 1) * RANK_GAP


## How far along the line a lioness has come: where the front's middle would be if she stood on her spot.
func own(u: Node3D) -> float:
	return dir.dot(u.global_position - start) + slots[u].y


## The line's middle marches on (once a physics frame, AttackerCommander). False once nobody is in it.
func update(delta: float) -> bool:
	members = members.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.order.get("line") == self)
	if members.is_empty():
		return false
	var slowest := INF
	var behind := INF
	for u in members:
		slowest = minf(slowest, u.top_speed())
		if not u.is_engaged():
			behind = minf(behind, own(u))
	pace = slowest * PACE
	var p := progress + pace * delta
	if behind < INF:
		p = minf(p, behind + LEAD)
	progress = minf(maxf(progress, p), length)
	return true


## True once the line's middle has come to its end.
func arrived() -> bool:
	return progress >= length - 0.01


## Where `u` should be now: her spot as the line stands, or level with where she is if she is ahead of
## it (she only steps sideways into her file).
func spot(u: Node3D) -> Vector3:
	var s: Vector2 = slots[u]
	var along := progress - s.y
	along = maxf(along, minf(dir.dot(u.global_position - start), length - s.y))
	return start + dir * along + right * s.x


## Where `u` ends up.
func final_spot(u: Node3D) -> Vector3:
	var s: Vector2 = slots[u]
	return dest - dir * s.y + right * s.x


## How fast `u` goes to make up `off` (m off her spot): the pace, and more the further off she is; once
## the line has arrived, slowing onto her spot.
func speed_for(u: Node3D, off: float) -> float:
	if arrived():
		return clampf(SETTLE * off, 0.0, u.top_speed())
	return clampf(pace + CATCH * maxf(off - IN_STEP, 0.0), 0.0, u.top_speed())
