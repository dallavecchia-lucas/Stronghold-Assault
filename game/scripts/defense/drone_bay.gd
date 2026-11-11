class_name DroneBay
extends Node
## The defenders' drone hangar: the landing docks on the fortress roofs and MAX_SWARMS swarms of five drones
## (DroneSwarm, DefenderDrone). It takes the calls for the swarms and keeps the books.
##
## SIX SWARMS, no more, no fewer: they are the bay's slots from the first second and are never added or lost. A
## drone that is shot down is rebuilt in the hangar (DroneSwarm: one at a time per swarm, every swarm at once), and
## rebuilding takes DefenderDrone.REBUILD_TIME, as long as filling an empty tank: always longer than refuelling a drone
## that came home. So refilling beats rebuilding, a lost drone is lost for most of a match, and a swarm that was shot
## to pieces is a damaged swarm, the last to be called, not a dead one and not a slot held for ever. All six start
## whole (INITIAL_SWARMS); a bay set up with fewer fills the rest from empty at the rebuild pace.
##
## DOCKS: SLOTS_PER_MOUNT pads on a ring round each AA turret mount on the roofs. A drone claims the free dock
## nearest to it when it turns for home, so it lands on the face it is working near rather than flying through
## the mountain to its own, and gives it up when it takes off.
##
## CALLS: any defender can call a swarm to where it stands: the human with a key (DefenderController), and
## the garrison, the squads and the posts on their own when attackers close in on them (_auto_call), through
## the same call_swarm(). The answer is a swarm that can get there: its drones price the trip like they price
## every trip (DefenderDrone.can_reach), so a caller too far out can't get one. A swarm already on the caller's
## spot isn't called twice, a spot isn't called again for CALL_COOLDOWN seconds, and a swarm that is within a few
## rounds of killing its target isn't pulled off it. THE FRESHEST SWARM ALWAYS GETS THE CALL: of the swarms that
## aren't busy and can get there, the one in the best shape (DroneSwarm.freshness: its drones' fuel and health,
## the ones shot down counting for nothing). A damaged or half-empty swarm is only called once the fresh ones are
## spent, out on a target or recharging. The garrison's own calls (auto) only ever take swarms that aren't busy:
## a swarm keeps the target it is on, only a player can re-task one. A swarm that was called to nothing comes home
## and docks (DroneSwarm), and is not busy again: it can be called again.

signal swarm_launched(swarm: DroneSwarm)

const MAX_SWARMS := 6
const INITIAL_SWARMS := 6
const SLOTS_PER_MOUNT := 5
const DOCK_RING := 3.2
const DOCK_RISE := 2.2
const CALL_COOLDOWN := 20.0
## A spot this close to one called not long ago is taken to be the same (m).
const CALL_NEAR := 25.0
const AUTO_CALL_EVERY := 2.0
## A defender with an attacker this close (flat, m) calls for drones on its own.
const PRESSURE_RADIUS := 40.0
const HUNTER_EVERY := 0.4

var level: LevelBuilder = null
## The middle of the map, where swarms look from.
var centre := Vector3.ZERO
var swarms: Array = []
## The attackers that can hurt drones (bears, AA units), as of the last scan: {"unit", "pos", "reach"}.
var hunters: Array = []
## The bodies of the attackers under the water (diving bears), as of the last scan: drones can't see them, and
## their rounds pass through.
var submerged: Array[RID] = []
## How many swarms the bay has (MAX_SWARMS), how many of them start with all five drones (the others start empty
## and fill up, one drone every DefenderDrone.REBUILD_TIME), and whether defenders call for drones on their own.
var slots := MAX_SWARMS
var initial_swarms := INITIAL_SWARMS
var auto_calls := true
## Stepped by hand (tests).
var manual := false
var stats := {"drones_built": 0, "drones_lost": 0, "calls": 0, "calls_refused": 0, "auto_calls": 0}

var _docks: Array = []
var _owner: Array = []
var _next_number := 1
var _hunter_cd := 0.0
var _auto_cd := 0.0
var _recent: Array = []
var _announced := false
var _clock := 0.0


func _ready() -> void:
	if _docks.is_empty():
		_make_docks()
	for k in slots:
		_add_swarm(k < initial_swarms)


func _process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	_clock += delta
	_hunter_cd -= delta
	if _hunter_cd <= 0.0:
		_hunter_cd = HUNTER_EVERY
		_scan_hunters()
	_auto_cd -= delta
	if _auto_cd <= 0.0:
		_auto_cd = AUTO_CALL_EVERY
		if auto_calls:
			_auto_call()
	if not _announced:
		for s in swarms:
			if s.airborne_count() > 0:
				_announced = true
				swarm_launched.emit(s)
				break


# ---------------------------------------------------------------- swarms

## Adds one of the bay's swarm slots: with all five drones on the docks, or empty, to be filled by the hangar.
func _add_swarm(full: bool) -> DroneSwarm:
	var sw := DroneSwarm.new()
	sw.name = "Swarm%d" % _next_number
	sw.number = _next_number
	_next_number += 1
	sw.bay = self
	sw.centre = centre
	sw.manual = manual
	add_child(sw)
	swarms.append(sw)
	if full:
		for k in DroneSwarm.SIZE:
			make_drone(sw)
	return sw


## The hangar builds a drone for `sw` (the lowest free place in the ring) on the free dock nearest it, full of fuel
## and mended. False if there is no free place or no free dock (it tries again next frame).
func make_drone(sw: DroneSwarm) -> bool:
	var index := sw.free_index()
	if index < 0 or _docks.is_empty():
		return false
	var d := DefenderDrone.new()
	d.name = "Drone%d_%d" % [sw.number, index]
	d.bay = self
	d.index = index
	var near := sw.centroid() if not sw.drones.is_empty() else _roomiest_mount()
	d.home_slot = claim_dock(near, d)
	if d.home_slot < 0:
		d.free()
		return false
	add_child(d)
	d.global_position = dock_pos(d.home_slot)
	sw.add_drone(d)
	stats.drones_built += 1
	return true


func airborne_count() -> int:
	var n := 0
	for s in swarms:
		n += s.airborne_count()
	return n


func ready_count() -> int:
	var n := 0
	for s in swarms:
		n += s.ready_count()
	return n


func alive_count() -> int:
	var n := 0
	for s in swarms:
		n += s.alive_count()
	return n


## Swarms with at least one drone (the CPU attacker reads it: an empty swarm is no threat yet).
func live_swarms() -> int:
	var n := 0
	for sw in swarms:
		if sw.alive_count() > 0:
			n += 1
	return n


## One line for the defender's HUD.
func status_text() -> String:
	return "DRONES  %d/%d · %d aloft · %d ready" % [alive_count(), swarms.size() * DroneSwarm.SIZE, airborne_count(), ready_count()]


# ---------------------------------------------------------------- docks

## Lays the docks out on rings round each of `mounts` (world positions): SLOTS_PER_MOUNT to a mount.
func set_docks(mounts: Array) -> void:
	_docks.clear()
	_owner.clear()
	for m in mounts:
		for k in SLOTS_PER_MOUNT:
			var a := TAU * float(k) / float(SLOTS_PER_MOUNT) + 0.3
			_docks.append(m + Vector3(cos(a) * DOCK_RING, DOCK_RISE, sin(a) * DOCK_RING))
			_owner.append(null)


func _make_docks() -> void:
	var mounts: Array = []
	if level != null:
		for t in level.aa_turrets:
			mounts.append(t.global_position)
	if mounts.is_empty():
		mounts.append(Vector3(0.0, 16.0, 0.0))
	set_docks(mounts)


func dock_count() -> int:
	return _docks.size()


func dock_pos(slot: int) -> Vector3:
	return _docks[slot]


func _free(slot: int) -> bool:
	var o = _owner[slot]
	return o == null or not is_instance_valid(o)


## The dock nearest `near` that nobody has claimed, claimed for `drone`; -1 if there is none.
func claim_dock(near: Vector3, drone: Node) -> int:
	var best := -1
	var best_d := INF
	for i in _docks.size():
		if not _free(i):
			continue
		var d := near.distance_to(_docks[i])
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_owner[best] = drone
	return best


func release_dock(slot: int) -> void:
	if slot >= 0 and slot < _owner.size():
		_owner[slot] = null


## The position of the nearest unclaimed dock (any dock if every one is taken).
func nearest_free_dock_pos(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for i in _docks.size():
		if not _free(i):
			continue
		var d := p.distance_to(_docks[i])
		if d < best_d:
			best_d = d
			best = _docks[i]
	return best if best_d < INF else nearest_dock_pos(p)


func nearest_dock_pos(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for dock in _docks:
		var d := p.distance_to(dock)
		if d < best_d:
			best_d = d
			best = dock
	return best


## How far `p` is from the nearest free dock: the way home from there.
func dock_distance(p: Vector3) -> float:
	return p.distance_to(nearest_free_dock_pos(p))


## The first dock of the mount with the most free ones: where a new swarm lands.
func _roomiest_mount() -> Vector3:
	var best := 0
	var best_free := -1
	for m in floori(float(_docks.size()) / float(SLOTS_PER_MOUNT)):
		var open := 0
		for k in SLOTS_PER_MOUNT:
			if _free(m * SLOTS_PER_MOUNT + k):
				open += 1
		if open > best_free:
			best_free = open
			best = m
	return _docks[best * SLOTS_PER_MOUNT]


# ---------------------------------------------------------------- calls

## A defender at `point` calls for a swarm. Returns {"ok": bool, "reason": String, "swarm": DroneSwarm or null}.
## `auto`: the garrison calling on its own (refusals aren't counted).
func call_swarm(point: Vector3, _caller: Node = null, auto := false) -> Dictionary:
	_recent = _recent.filter(func(r): return r[1] > _clock)
	if alive_count() == 0:
		return _refused("no drones: the hangar is rebuilding them", auto)
	for r in _recent:
		if _flat(r[0], point) <= CALL_NEAR:
			return _refused("a swarm is already on its way", auto)
	for s in swarms:
		if s.covers(point):
			return _refused("a swarm is already on it", auto)
	var best: DroneSwarm = null
	var best_score := -INF
	var could_go := false
	var can_fly := false
	for s in swarms:
		if s.fit_count() > 0:
			can_fly = true
		var q: int = s.call_quality(point)
		if q <= 0:
			continue
		could_go = true
		if s.committed() or (auto and s.busy()):
			continue
		# The freshest swarm: idle ones before busy ones (the 10 outweighs any difference in freshness, 0 to 1),
		# then the one in the best shape (fuel and health of its drones, the ones shot down counting for nothing),
		# the nearest only to settle a tie. A damaged swarm comes only when the fresh ones are spent.
		var busy: bool = s.busy()
		var gap: float = s.centroid().distance_to(point)
		var score: float = float(s.freshness()) - (10.0 if busy else 0.0) - gap * 0.00001
		if score > best_score:
			best_score = score
			best = s
	if best == null:
		if not can_fly:
			return _refused("every drone is recharging", auto)
		if not could_go:
			return _refused("out of the drones' reach", auto)
		return _refused("every swarm is busy" if auto else "every swarm is about to make a kill", auto)
	best.assign_call(point)
	_recent.append([point, _clock + CALL_COOLDOWN])
	if auto:
		stats.auto_calls += 1
	else:
		stats.calls += 1
	return {"ok": true, "reason": "", "swarm": best}


func _refused(reason: String, auto: bool) -> Dictionary:
	if not auto:
		stats.calls_refused += 1
	return {"ok": false, "reason": reason, "swarm": null}


## The defenders call for drones on their own: the post, squad or trooper with the most attackers closing in
## on it that no swarm is on yet. (Same call_swarm() a player uses.)
func _auto_call() -> void:
	var attackers := get_tree().get_nodes_in_group("attacker_units")
	if attackers.is_empty():
		return
	var best: Node = null
	var best_n := 0
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if not d.is_alive():
			continue
		var p: Vector3 = d.global_position
		var n := 0
		for a in attackers:
			if a.is_alive() and _flat(a.global_position, p) <= PRESSURE_RADIUS:
				n += 1
		if n > best_n:
			best_n = n
			best = d
	if best != null:
		call_swarm(best.global_position, best, true)


# ---------------------------------------------------------------- the attackers that fight back

func _scan_hunters() -> void:
	hunters.clear()
	submerged.clear()
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if not u.is_alive():
			continue
		if u.is_submerged():
			submerged.append(u.get_rid())
		if u.hunts_drones() and not u.is_crossing():
			var reach: float = float(u.stats.get("aa_range", u.stats.get("range", 30.0)))
			hunters.append({"unit": u, "pos": u.global_position, "reach": reach})


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
