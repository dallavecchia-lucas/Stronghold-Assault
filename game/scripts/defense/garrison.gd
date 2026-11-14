class_name Garrison
extends Node3D
## The defenders' garrison: basic foot soldiers (GarrisonSoldier) spawned for the whole match, deep inside the
## stronghold, and sent where they are needed.
##
## Spawns. The base has four spawn points, one deep inside each side (in the corridor that runs from that side's spawn
## hall in toward the core). There are four spawn controls, one per defending player; each spawns one soldier every
## SPAWN_INTERVAL at the side it is on, on its own timer. By default each control is on its own side (south, east,
## north, west), so four soldiers come out at once, one on each side. A player moves their control to another side to
## answer pressure there: that side then spawns two at a time and the side they left none (move_spawn). Each control
## also has its own priority (set_priority), for the soldiers it spawns from then on:
##   BASE  (the default) guns first, then the gun decks, then the field.
##   FIELD straight out to the field.
## Two controls on one side are independent: one can spawn for the base while the other spawns for the field.
##
## Jobs, handed out as each soldier comes out (_dispatch):
##   GUN   every gun the defenders can take over (every gun deck's sentry guns and cannons, and the mortar) needs a crew
##         to fire on its own (MountedGun.needs_crew). A soldier claims the unclaimed gun nearest it along the navmesh,
##         wherever it is, on its own side or not, walks there and sits in its seat. A crew lost: a soldier holding
##         that side's deck steps over to the gun (_audit), or the next soldier out takes it.
##   DECK  DECK_GAPS.size() spots on each gun deck, in the gaps between the guns, clear of the rifle posts and the
##         guns' seats: soldiers on the decks, but never a crowd.
##   FIELD a perimeter round the base (_build_field): spots in loose, staggered rows round the mountain, FIELD_SPACING
##         apart, jittered. They are taken cheapest first: the cost is how far out the row is, plus FIELD_LATERAL of how
##         far round the base the spot is from the nearest gate. So the perimeter starts as a loose band in front of the
##         gates, and as more soldiers come out it grows outward and round the base. Soldiers stay where they are put:
##         the new ones go to its outer edge (or fill a gap a fallen one left).

signal changed

enum Priority { BASE, FIELD }
const PRIORITY_NAMES := ["BASE", "FIELD"]

const SPAWN_INTERVAL := 6.0
## The four controls' sides at the start (control k: player k).
const SIDE_ORDER := ["south", "east", "north", "west"]
const OPPOSITE := {"south": "north", "north": "south", "east": "west", "west": "east"}
## How far in from the spawn hall's marker (SPAWN_<face>3) toward the core the side's spawn point lies (m), and how far
## apart soldiers coming out at once on one side stand.
const SPAWN_DEPTH := 8.0
const SPAWN_SPREAD := 1.2
## Alive at once at most: past this, a control's turn passes without a soldier.
const MAX_ALIVE := 320
## The gaps between a deck's fourteen guns (0-12, west to east along the face) that get a garrison soldier: the end bays'
## middles and the gaps between the bays (8 a deck). The middles of bays 3-5 are left to the rifle posts
## (LevelBuilder.RIFLE_POSTS); within a bay the two guns' seats face each other across its middle.
const DECK_GAPS := [0, 1, 3, 5, 7, 9, 11, 12]
## Deck spots sit this far toward the parapet from the guns' mounts.
const DECK_OUT := 0.8
## The perimeter: the first row this far out from the mountain's footprint (LevelBuilder.base_distance), the rows
## FIELD_ROW apart, FIELD_ROWS of them; spots FIELD_SPACING apart along a row, jittered up to FIELD_JITTER.
const FIELD_FIRST := 10.0
const FIELD_ROW := 5.0
const FIELD_ROWS := 16
const FIELD_SPACING := 5.0
const FIELD_JITTER := 1.4
const FIELD_LATERAL := 0.3
## A soldier going out takes, of the next FIELD_WINDOW free spots in that order, the one it gets to soonest.
const FIELD_WINDOW := 12
## Spots kept this far off the attackers' helipads.
const FIELD_BASE_CLEAR := 8.0
## A field spot more than this (flat, m) off the navmesh is unusable (water, a rock, a trunk).
const FIELD_NAV_SLACK := 1.5
## How often the jobs are looked over (s), and how far a deck soldier walks to take over a gun that lost its crew.
const AUDIT_EVERY := 0.5
## How far from a gun's middle its crew walks to beside the seat (m): clear of the navmesh block round a deck gun or a
## roof turret (1.4 m across), round the mortar (2.6 m).
const SEAT_CLEAR_GUN := 1.4
const DECK_TO_GUN := 45.0
const NAV_LAYERS := 1 | LevelBuilder.NAV_INFILTRATORS | LevelBuilder.NAV_SQUAD

var level: LevelBuilder
## The human defender's player number (their control); -1: nobody (the CPU defends).
var local_player := 0
## {player, side, priority, cd} per control.
var controls: Array = []
## Seconds since the garrison started (the first soldiers come out at 0).
var clock := 0.0
## The navmesh answers and the spots are worked out (_try_setup): the spawns are running.
var set_up := false
var soldiers: Array[GarrisonSoldier] = []
## The guns that need a crew, and the side each is on.
var guns: Array = []
var gun_side := {}
## gun -> the soldier that claimed it (on its way or at it).
var claims := {}
## {pos, side, facing, holder}
var deck_slots: Array = []
## {pos, facing, cost, row, holder, bad, checked}
var field_slots: Array = []
## What happened when (s on `clock`; -1: not yet): see _stat_tick and report().
var stats := {}
## One entry per soldier that got where it was sent: {side, job, to_side, travel, at, spawned}.
var arrivals: Array = []

var _field_order: Array = []
## gun -> where its crew walks to (its spot with the gun at rest, on the navmesh).
var _gun_goals := {}
## gate side -> the ground just outside it.
var _exits := {}
var _spawn_pos := {}
var _cost := {}
var _audit_cd := 0.0
var _serial := 0
var _map: RID


func _ready() -> void:
	_map = get_world_3d().navigation_map
	for k in SIDE_ORDER.size():
		controls.append({"player": k, "side": SIDE_ORDER[k], "priority": Priority.BASE, "cd": 0.0})
	# The guns fall silent at once: they fire on their own again as the crews get to them.
	for s in level.stations:
		if s.station_kind == "mg":
			guns.append(s)
			gun_side[s] = side_of(s.global_position)
			s.needs_crew = true
			s.crew = null
	stats = {"spawned": 0, "deaths": 0, "all_guns_claimed": -1.0, "all_guns_manned": -1.0, "deck_full": -1.0,
			"first_field_job": -1.0, "first_base_field_job": -1.0, "first_outside": -1.0, "skipped": 0,
			"side_guns_manned": {}, "gun_manned": {}}


## The navigation map takes a few frames after the bake to answer queries (its sync runs on its own): the spawn points,
## the crews' spots, the deck and the field are worked out, and the clock starts, once it does.
func _try_setup() -> bool:
	var probe := level.marker("SPAWN_S%d" % LevelBuilder.GATE_BAY).global_position + Vector3.UP * 0.5
	if NavigationServer3D.map_get_iteration_id(_map) == 0 or LevelBuilder.nav_closest(_map, probe).distance_to(probe) > 3.0:
		return false
	for side in LevelBuilder.SIDES:
		var marker := level.marker("SPAWN_%s%d" % [LevelBuilder.SIDES[side].face, LevelBuilder.GATE_BAY])
		var inward: Vector3 = -LevelBuilder.SIDES[side].dir
		_spawn_pos[side] = LevelBuilder.nav_closest(_map, marker.global_position + inward * SPAWN_DEPTH + Vector3.UP * 0.5)
		_cost[side] = {}
	for side in level.gates:
		_exits[side] = LevelBuilder.nav_closest(_map, level.gates[side].global_position + LevelBuilder.SIDES[side].dir * 4.0)
	for g in guns:
		_gun_goals[g] = _beside_seat(g)
	_build_deck_slots()
	_build_field()
	set_up = true
	return true


# ---------------------------------------------------------------- the spawn controls

func control_of(player: int) -> Dictionary:
	for c in controls:
		if c.player == player:
			return c
	return {}


## Moves `player`'s spawn control to `side` (its timer runs on: its next soldier comes out there).
func move_spawn(player: int, side: String) -> void:
	var c := control_of(player)
	if c.is_empty() or not LevelBuilder.SIDES.has(side):
		return
	c.side = side
	changed.emit()


## Moves `player`'s control to the next side round the base (south, east, north, west); returns the side.
func cycle_spawn(player: int) -> String:
	var c := control_of(player)
	if c.is_empty():
		return ""
	move_spawn(player, SIDE_ORDER[(SIDE_ORDER.find(c.side) + 1) % SIDE_ORDER.size()])
	return c.side


func set_priority(player: int, p: int) -> void:
	var c := control_of(player)
	if c.is_empty():
		return
	c.priority = p
	changed.emit()


## BASE <-> FIELD for `player`'s control; returns the new priority.
func toggle_priority(player: int) -> int:
	var c := control_of(player)
	if c.is_empty():
		return Priority.BASE
	set_priority(player, Priority.FIELD if c.priority == Priority.BASE else Priority.BASE)
	return c.priority


## How many soldiers come out at `side` each time.
func spawns_at(side: String) -> int:
	return controls.filter(func(c): return c.side == side).size()


func gates() -> Array:
	return level.gates.values()


## The side (south, east, north, west) whose face `p` is out from.
static func side_of(p: Vector3) -> String:
	var best := ""
	var best_d := -INF
	for side in LevelBuilder.SIDES:
		var d: float = p.dot(LevelBuilder.SIDES[side].dir)
		if d > best_d:
			best_d = d
			best = side
	return best


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if not set_up and not _try_setup():
		return
	clock += delta
	for c in controls:
		c.cd -= delta
		if c.cd <= 0.0:
			c.cd += SPAWN_INTERVAL
			_spawn(c)
	_audit_cd -= delta
	if _audit_cd <= 0.0:
		_audit_cd = AUDIT_EVERY
		_audit()
		_stat_tick()


func _spawn(c: Dictionary) -> void:
	if soldiers.size() >= MAX_ALIVE:
		stats.skipped += 1
		return
	var side: String = c.side
	var here := controls.filter(func(o): return o.side == side)
	var k := here.find(c)
	var out: Vector3 = LevelBuilder.SIDES[side].dir
	var along := out.cross(Vector3.UP)
	var s := GarrisonSoldier.new()
	_serial += 1
	s.name = "Garrison_%d" % _serial
	s.garrison = self
	s.spawn_side = side
	s.priority = c.priority
	s.spawned_at = clock
	s.transform = Transform3D(Basis.looking_at(out), _spawn_pos[side] + along * (k - (here.size() - 1) * 0.5) * SPAWN_SPREAD)
	add_child(s)
	s.died.connect(_on_died)
	soldiers.append(s)
	stats.spawned += 1
	_dispatch(s, true)


## Hands `s` its job: by its priority, a gun, a deck spot or a field spot, the nearest (along the navmesh from its
## spawn when `fresh`, else straight from where it stands) of the first kind with one free.
func _dispatch(s: GarrisonSoldier, fresh: bool) -> void:
	var order := [GarrisonSoldier.Job.GUN, GarrisonSoldier.Job.DECK, GarrisonSoldier.Job.FIELD]
	if s.priority == Priority.FIELD:
		order = [GarrisonSoldier.Job.FIELD, GarrisonSoldier.Job.DECK, GarrisonSoldier.Job.GUN]
	for job in order:
		if _try_job(s, job, fresh):
			return
	s.job = GarrisonSoldier.Job.NONE


func _try_job(s: GarrisonSoldier, job: int, fresh: bool) -> bool:
	match job:
		GarrisonSoldier.Job.GUN:
			var best = null
			var best_c := INF
			for g in guns:
				if not g.is_alive() or _claimant(g) != null or s.avoid.has("gun%d" % g.get_instance_id()):
					continue
				var c := _job_cost(s, fresh, "gun%d" % g.get_instance_id(), _gun_goal(g))
				if c < best_c:
					best_c = c
					best = g
			if best == null:
				return false
			_give_gun(s, best)
			return true
		GarrisonSoldier.Job.DECK:
			var best := -1
			var best_c := INF
			for i in deck_slots.size():
				if _holds(deck_slots[i]) != null or s.avoid.has("deck%d" % i):
					continue
				var c := _job_cost(s, fresh, "deck%d" % i, deck_slots[i].pos)
				if c < best_c:
					best_c = c
					best = i
			if best < 0:
				return false
			var d: Dictionary = deck_slots[best]
			d.holder = s
			s.slot = best
			s.send(GarrisonSoldier.Job.DECK, d.pos, d.facing, clock)
			return true
		GarrisonSoldier.Job.FIELD:
			# The next FIELD_WINDOW free spots, cheapest first (round all the gates, about as far out): the one it gets
			# out to soonest is its own.
			var window := []
			for i in _field_order:
				var f: Dictionary = field_slots[i]
				if f.bad or _holds(f) != null:
					continue
				if not f.checked and not _check_field(f):
					continue
				window.append(i)
				if window.size() >= FIELD_WINDOW:
					break
			if window.is_empty():
				return false
			var best: int = window[0]
			var best_c := INF
			for i in window:
				var c := _walk_out(s, fresh, field_slots[i].pos)
				if c < best_c:
					best_c = c
					best = i
			var f: Dictionary = field_slots[best]
			f.holder = s
			s.slot = best
			s.send(GarrisonSoldier.Job.FIELD, f.pos, f.facing, clock)
			if stats.first_field_job < 0.0:
				stats.first_field_job = clock
			if s.priority == Priority.BASE and stats.first_base_field_job < 0.0:
				stats.first_base_field_job = clock
			return true
	return false


## Roughly how far `s` walks out to `to` in the field: to the gate that gets it there soonest (along the navmesh from
## its spawn, worked out once per side and gate) and on from there in a straight line.
func _walk_out(s: GarrisonSoldier, fresh: bool, to: Vector3) -> float:
	var from: Vector3 = _spawn_pos[s.spawn_side] if fresh else s.global_position
	if not fresh and LevelBuilder.base_distance(from) > 0.0:
		return from.distance_to(to)
	var best := INF
	for side in _exits:
		var exit: Vector3 = _exits[side]
		var inside: float = _job_cost(s, true, "exit_" + side, exit) if fresh else from.distance_to(exit)
		best = minf(best, inside + Vector2(exit.x - to.x, exit.z - to.z).length())
	return best


func _give_gun(s: GarrisonSoldier, g) -> void:
	claims[g] = s
	s.gun = g
	s.slot = -1
	var spot: Transform3D = g.crew_spot()
	s.send(GarrisonSoldier.Job.GUN, _gun_goal(g), -spot.basis.z, clock)


func _gun_goal(g) -> Vector3:
	return _gun_goals[g]


## Where a gun's crew walks to: up the ramp beside a gun-deck gun's seat, or the floor beside the mortar's seat, out past the
## box that keeps the navmesh off the gun (whose top the bake makes a little platform of, right under a seat): from there
## it steps into the seat (GarrisonSoldier._crew).
func _beside_seat(g) -> Vector3:
	# A gun-deck gun on its bay's platform: up the ramp between the bay's two guns (MountedGun.crew_stand).
	var stand = g.get("crew_stand")
	if stand != null and stand != Vector3.INF:
		return LevelBuilder.nav_closest(_map, stand + Vector3.UP * 0.3)
	var seat: Vector3 = (g.crew_spot() as Transform3D).origin
	var base: Vector3 = g.global_position
	var out := Vector3(seat.x - base.x, 0.0, seat.z - base.z)
	var clear := SEAT_CLEAR_GUN
	if out.length() < 0.01:
		out = g.global_basis.z
	var beside := base + out.normalized() * maxf(out.length(), clear) + Vector3.UP * 0.3
	return LevelBuilder.nav_closest(_map, beside)


## A fresh soldier: how far it walks from its side's spawn point to `to` along the navmesh (worked out once per side
## and target; INF: no way there). One already out: straight from where it stands.
func _job_cost(s: GarrisonSoldier, fresh: bool, key: String, to: Vector3) -> float:
	if not fresh:
		return s.global_position.distance_to(to)
	var cache: Dictionary = _cost[s.spawn_side]
	if not cache.has(key):
		cache[key] = path_length(_spawn_pos[s.spawn_side], to)
	return cache[key]


## Length of the navmesh path from `a` to `b` the garrison walks (stairs and gates and all), INF if it ends short.
func path_length(a: Vector3, b: Vector3) -> float:
	# The whole map's query (not LevelBuilder.nav_path's tiles round the ends): the climbing links count.
	var path := NavigationServer3D.map_get_path(_map, a, b, true, NAV_LAYERS)
	if path.is_empty() or path[-1].distance_to(b) > GarrisonSoldier.UNREACHABLE:
		return INF
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	return length


func _claimant(g) -> GarrisonSoldier:
	var s = claims.get(g)
	if s == null or not is_instance_valid(s) or not s.is_alive() or s.gun != g:
		claims.erase(g)
		return null
	return s


func _holds(slot: Dictionary) -> GarrisonSoldier:
	var s = slot.holder
	if s == null or not is_instance_valid(s) or not s.is_alive():
		slot.holder = null
		return null
	return s


## Got where it was sent (GarrisonSoldier._arrive). At a gun it takes it (the gun fires once it is in the seat: seated()).
func arrived(s: GarrisonSoldier) -> void:
	s.arrived_at = clock
	var to_side := ""
	if s.job == GarrisonSoldier.Job.GUN and is_instance_valid(s.gun):
		s.gun.crew = s
		return
	elif s.job == GarrisonSoldier.Job.DECK:
		to_side = deck_slots[s.slot].side
	elif s.job == GarrisonSoldier.Job.FIELD:
		to_side = side_of(s.global_position)
	arrivals.append({"side": s.spawn_side, "job": s.job, "to_side": to_side, "travel": clock - s.assigned_at,
			"at": clock, "spawned": s.spawned_at, "fresh": is_equal_approx(s.assigned_at, s.spawned_at)})


## In its gun's seat (GarrisonSoldier._climb_to_seat): the gun is manned.
func seated(s: GarrisonSoldier) -> void:
	if not is_instance_valid(s.gun):
		return
	arrivals.append({"side": s.spawn_side, "job": s.job, "to_side": gun_side[s.gun], "travel": clock - s.assigned_at,
			"at": clock, "spawned": s.spawned_at, "fresh": is_equal_approx(s.assigned_at, s.spawned_at)})


## Its path can't get it there: the spot is struck off (a field spot) or the target left to others, and it gets another.
func unreachable(s: GarrisonSoldier) -> void:
	match s.job:
		GarrisonSoldier.Job.GUN:
			if is_instance_valid(s.gun):
				s.avoid["gun%d" % s.gun.get_instance_id()] = true
		GarrisonSoldier.Job.DECK:
			s.avoid["deck%d" % s.slot] = true
	match s.job:
		GarrisonSoldier.Job.FIELD:
			field_slots[s.slot].bad = true
			field_slots[s.slot].holder = null
		GarrisonSoldier.Job.DECK:
			_cost[s.spawn_side]["deck%d" % s.slot] = INF
			deck_slots[s.slot].holder = null
		GarrisonSoldier.Job.GUN:
			if is_instance_valid(s.gun):
				_cost[s.spawn_side]["gun%d" % s.gun.get_instance_id()] = INF
				claims.erase(s.gun)
	_release(s)
	_dispatch(s, false)


func _release(s: GarrisonSoldier) -> void:
	if s.job == GarrisonSoldier.Job.GUN and is_instance_valid(s.gun):
		if claims.get(s.gun) == s:
			claims.erase(s.gun)
		if s.gun.crew == s:
			s.gun.crew = null
	elif s.job == GarrisonSoldier.Job.DECK and s.slot >= 0 and deck_slots[s.slot].holder == s:
		deck_slots[s.slot].holder = null
	elif s.job == GarrisonSoldier.Job.FIELD and s.slot >= 0 and field_slots[s.slot].holder == s:
		field_slots[s.slot].holder = null
	s.gun = null
	s.slot = -1
	s.job = GarrisonSoldier.Job.NONE


func _on_died(s: GarrisonSoldier) -> void:
	_release(s)
	soldiers.erase(s)
	stats.deaths += 1


## Guns knocked out free their crews; a gun with nobody coming gets the nearest soldier off its own deck.
func _audit() -> void:
	for g in guns:
		var s := _claimant(g)
		if not g.is_alive():
			if s != null:
				_release(s)
				_dispatch(s, false)
			continue
		if s != null:
			continue
		if g.crew != null and not (is_instance_valid(g.crew) and g.crew.is_alive()):
			g.crew = null
		var best: GarrisonSoldier = null
		var best_d := DECK_TO_GUN
		for d in soldiers:
			if d.job != GarrisonSoldier.Job.DECK or deck_slots[d.slot].side != gun_side[g]:
				continue
			if d.avoid.has("gun%d" % g.get_instance_id()):
				continue
			var dist := d.global_position.distance_to(g.global_position)
			if dist < best_d:
				best_d = dist
				best = d
		if best != null:
			_release(best)
			_give_gun(best, g)


func _stat_tick() -> void:
	var claimed := 0
	var manned := 0
	var alive := 0
	var side_total := {}
	var side_manned := {}
	for g in guns:
		if not g.is_alive():
			continue
		alive += 1
		var side: String = gun_side[g]
		side_total[side] = side_total.get(side, 0) + 1
		if _claimant(g) != null:
			claimed += 1
		if g.crew != null and is_instance_valid(g.crew) and g.crew.is_alive() and g.crew.at_post():
			manned += 1
			side_manned[side] = side_manned.get(side, 0) + 1
			if not stats.gun_manned.has(g.name):
				stats.gun_manned[g.name] = clock
	for side in side_total:
		if side_manned.get(side, 0) == side_total[side] and not stats.side_guns_manned.has(side):
			stats.side_guns_manned[side] = clock
	if claimed == alive and stats.all_guns_claimed < 0.0:
		stats.all_guns_claimed = clock
	if manned == alive and stats.all_guns_manned < 0.0:
		stats.all_guns_manned = clock
	if stats.deck_full < 0.0 and deck_slots.all(func(d): return _holds(d) != null and d.holder.arrived):
		stats.deck_full = clock
	if stats.first_outside < 0.0:
		for s in soldiers:
			if s.job == GarrisonSoldier.Job.FIELD and LevelBuilder.base_distance(s.global_position) > 0.5:
				stats.first_outside = clock
				break


## What the HUD shows: crews at their guns, soldiers on the decks and out in the field.
func summary() -> Dictionary:
	var out := {"guns": 0, "guns_alive": 0, "deck": 0, "deck_total": deck_slots.size(), "field": 0, "walking": 0,
			"alive": soldiers.size()}
	for g in guns:
		if g.is_alive():
			out.guns_alive += 1
			if g.crew != null and is_instance_valid(g.crew) and g.crew.is_alive() and g.crew.at_post():
				out.guns += 1
	for s in soldiers:
		if not s.arrived:
			out.walking += 1
		elif s.job == GarrisonSoldier.Job.DECK:
			out.deck += 1
		elif s.job == GarrisonSoldier.Job.FIELD:
			out.field += 1
	return out


# ---------------------------------------------------------------- the decks and the field

## DECK_SLOTS: in the chosen gaps between each deck's guns, a little toward the parapet, facing out.
func _build_deck_slots() -> void:
	for side in LevelBuilder.SIDES:
		var face: String = LevelBuilder.SIDES[side].face
		var mounts := []
		for bay in range(1, 10):
			for k in [1, 2]:
				var m := level.marker("MOUNT_GUN_%s%d_%d" % [face, bay, k])
				if m:
					mounts.append(m)
		var along: Vector3 = (LevelBuilder.SIDES[side].dir as Vector3).cross(Vector3.UP)
		mounts.sort_custom(func(a, b): return a.global_position.dot(along) < b.global_position.dot(along))
		for gap in DECK_GAPS:
			if gap + 1 >= mounts.size():
				continue
			var a: Node3D = mounts[gap]
			var b: Node3D = mounts[gap + 1]
			var p := (a.global_position + b.global_position) * 0.5 + a.global_basis.z * DECK_OUT + Vector3.UP * 0.1
			deck_slots.append({"pos": LevelBuilder.nav_closest(_map, p + Vector3.UP * 0.3), "side": side,
					"facing": LevelBuilder.SIDES[side].dir, "holder": null})


## The perimeter's spots: FIELD_ROWS rows round the mountain's footprint (a square with rounded corners at each row's
## distance), staggered and jittered, each costed by how far out its row is and how far round the base it is from the
## nearest gate.
func _build_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var h := LevelBuilder.MOUNTAIN_HALF
	var gate_faces := []
	for side in level.gates:
		gate_faces.append(SIDE_ORDER.find(side))
	for row in FIELD_ROWS:
		var r := FIELD_FIRST + row * FIELD_ROW
		var seg := 2.0 * h + PI * 0.5 * r
		var total := 4.0 * seg
		var n := int(total / FIELD_SPACING)
		var phase := 0.5 if row % 2 == 1 else 0.0
		for k in n:
			var s := (k + phase + rng.randf_range(-0.28, 0.28)) * total / n
			var at := _contour(fposmod(s, total), h, r)
			var radial := rng.randf_range(-FIELD_JITTER, FIELD_JITTER)
			var p: Vector3 = at[0] + at[1] * radial
			var lateral := INF
			for f in gate_faces:
				var gs: float = f * seg + h
				var ds := absf(fposmod(s, total) - gs)
				lateral = minf(lateral, minf(ds, total - ds))
			if level.bases.any(func(b): return b.edge_distance(p) <= FIELD_BASE_CLEAR):
				continue
			field_slots.append({"pos": p, "facing": at[1], "cost": r + radial + FIELD_LATERAL * lateral, "row": row,
					"holder": null, "bad": false, "checked": false})
	_field_order = range(field_slots.size())
	_field_order.sort_custom(func(a, b): return field_slots[a].cost < field_slots[b].cost)


## The point `s` (m) round the rounded square `r` out from a footprint of half-size `h`, and the outward normal there.
## s = 0 is the south side's west end; it runs east along the south, then north up the east side, and so on.
static func _contour(s: float, h: float, r: float) -> Array:
	var seg := 2.0 * h + PI * 0.5 * r
	var k := mini(int(s / seg), 3)
	var u := s - k * seg
	var n: Vector3 = LevelBuilder.SIDES[SIDE_ORDER[k]].dir
	var t := Vector3(n.z, 0.0, -n.x)
	if u < 2.0 * h:
		return [n * (h + r) + t * (u - h), n]
	var a := (u - 2.0 * h) / r
	var normal := n * cos(a) + t * sin(a)
	return [n * h + t * h + normal * r, normal]


## A field spot is checked once, when it is first wanted: on the navmesh (not in the water, under a rock or a helipad).
func _check_field(f: Dictionary) -> bool:
	f.checked = true
	var p: Vector3 = f.pos
	p.y = LevelBuilder.ground_height(p)
	var nav := LevelBuilder.nav_closest(_map, p + Vector3.UP * 0.5)
	if Vector2(nav.x - p.x, nav.z - p.z).length() > FIELD_NAV_SLACK or absf(nav.y - p.y) > 2.0:
		f.bad = true
		return false
	f.pos = nav
	return true


## The numbers the showcase prints.
func report() -> String:
	var lines := []
	lines.append("spawned=%d alive=%d deaths=%d skipped=%d" % [stats.spawned, soldiers.size(), stats.deaths, stats.skipped])
	lines.append("guns=%d deck_slots=%d field_slots=%d" % [guns.size(), deck_slots.size(), field_slots.size()])
	for key in ["all_guns_claimed", "all_guns_manned", "deck_full", "first_field_job", "first_base_field_job", "first_outside"]:
		lines.append("%s=%.1f" % [key, stats[key]])
	lines.append("side_guns_manned=%s" % str(stats.side_guns_manned))
	return "\n".join(lines)
