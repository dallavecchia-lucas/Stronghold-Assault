class_name DroneBay
extends Node
## The defenders' drone hangar: the landing docks on the fortress roofs and up to MAX_SWARMS swarms of five drones
## (DroneSwarm, DefenderDrone). It builds the swarms, takes the calls for them and keeps the books.
##
## THE CAP: at most MAX_SWARMS swarms are alive at once, and a swarm only counts as gone when all five of its
## drones are dead. Drones lost one at a time are never replaced, so a swarm that is down to its last drone still
## holds its place; only when a whole swarm is wiped out does a place free up, and the next swarm is built
## BUILD_TIME seconds later (the timer only runs while there's a place free). The match starts with
## INITIAL_SWARMS; the rest are built one after another.
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
## rounds of killing its target isn't pulled off it.

signal swarm_launched(swarm: DroneSwarm)
signal swarm_lost(swarm: DroneSwarm)

const MAX_SWARMS := 6
const INITIAL_SWARMS := 2
const BUILD_TIME := 45.0
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
## Swarms alive at the start, and whether defenders call for drones on their own.
var initial_swarms := INITIAL_SWARMS
var auto_calls := true
## Stepped by hand (tests).
var manual := false
var stats := {"swarms_built": 0, "swarms_lost": 0, "drones_lost": 0, "calls": 0, "calls_refused": 0, "auto_calls": 0}

var _docks: Array = []
var _owner: Array = []
var _next_number := 1
var _build_cd := BUILD_TIME
var _hunter_cd := 0.0
var _auto_cd := 0.0
var _recent: Array = []
var _announced := false
var _clock := 0.0


func _ready() -> void:
	if _docks.is_empty():
		_make_docks()
	for k in initial_swarms:
		build_swarm()


func _process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	_clock += delta
	if swarms.size() < MAX_SWARMS:
		_build_cd -= delta
		if _build_cd <= 0.0:
			_build_cd = BUILD_TIME
			build_swarm()
	else:
		_build_cd = BUILD_TIME
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

## Builds a swarm on the docks (null if MAX_SWARMS are alive already).
func build_swarm() -> DroneSwarm:
	if swarms.size() >= MAX_SWARMS or _docks.is_empty():
		return null
	var s := DroneSwarm.new()
	s.name = "Swarm%d" % _next_number
	s.number = _next_number
	_next_number += 1
	s.bay = self
	s.centre = centre
	s.manual = manual
	add_child(s)
	var near := _roomiest_mount()
	for k in DroneSwarm.SIZE:
		var d := DefenderDrone.new()
		d.name = "Drone%d_%d" % [s.number, k]
		d.bay = self
		d.index = k
		d.home_slot = claim_dock(near, d)
		if d.home_slot < 0:
			d.free()
			break
		add_child(d)
		d.global_position = dock_pos(d.home_slot)
		s.add_drone(d)
	if s.drones.is_empty():
		s.free()
		return null
	swarms.append(s)
	s.wiped_out.connect(_on_swarm_wiped)
	stats.swarms_built += 1
	return s


func _on_swarm_wiped(s: DroneSwarm) -> void:
	swarms.erase(s)
	stats.swarms_lost += 1
	# A place has come free: the next swarm is built a full BUILD_TIME from now.
	_build_cd = BUILD_TIME
	swarm_lost.emit(s)
	s.queue_free()


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


## One line for the defender's HUD.
func status_text() -> String:
	return "DRONES  %d/%d swarms · %d aloft · %d ready" % [swarms.size(), MAX_SWARMS, airborne_count(), ready_count()]


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
	if swarms.is_empty():
		return _refused("no swarm has been built yet", auto)
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
		if s.ready_count() > 0 or s.airborne_count() > 0:
			can_fly = true
		var q: int = s.call_quality(point)
		if q <= 0:
			continue
		could_go = true
		if s.committed():
			continue
		# The most drones able to go, the idle swarms before the busy ones, the nearest first.
		var busy: bool = s.busy()
		var gap: float = s.centroid().distance_to(point)
		var score: float = float(q) * 10.0 - (8.0 if busy else 0.0) - gap * 0.02
		if score > best_score:
			best_score = score
			best = s
	if best == null:
		if not can_fly:
			return _refused("every drone is recharging", auto)
		return _refused("out of the drones' reach" if not could_go else "every swarm is about to make a kill", auto)
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
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if u.is_alive() and u.hunts_drones() and not u.is_crossing():
			var reach: float = float(u.stats.get("aa_range", u.stats.get("range", 30.0)))
			hunters.append({"unit": u, "pos": u.global_position, "reach": reach})


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
