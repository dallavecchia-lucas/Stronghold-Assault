class_name DroneSwarm
extends Node
## Five drones (DefenderDrone) that work as one. A swarm has ONE focus, a single attacker, and every drone of it
## shoots that one until it is dead (or can't be got at any more), then it picks the next: it never splits up. Each
## drone still obeys its own fuel rule (DefenderDrone.must_return), so a swarm thins out as drones go home to
## recharge one by one, and they rejoin the fight as soon as they are full again, so a focus is not forgotten
## just because every drone happens to be on its dock.
##
## WHOM IT PICKS is where the annoyance is. A swarm goes for the target that hurts the attacker most and costs
## it least (_score):
##   - units the army leans on and can least afford to lose: the Wolf Medic, the Giraffe (its eyes: without
##     it the fog closes in), the artillery, the snakes, the kangaroos (PREY);
##   - units that can't do anything about drones, over the bears and the AA, which are the only things that can;
##     and, among those, ones that have no bear or AA unit guarding them (GUARD_RADIUS);
##   - helpless ones: no attacker attacks while it swims or rides a raft, so they just get shot (HELPLESS: four times
##     as good a target). A bear diving under the water is the exception: it is undetectable to a drone, never
##     picked, dropped the moment it dives, and its body is not in the way of the drones' rounds;
##   - ones already hurt, ones near where it was sent, ones no other swarm is on.
## and it hangs back, STANDOFF out and HOVER_HEIGHT up, on the side of its target that keeps its drones furthest
## out of the reach of the bears and AA about (_choose_angle), re-checked as they move.
##
## CALLED to a spot (DroneBay.call_swarm) it flies there and takes the best target round it (ANCHOR_RADIUS) for
## CALL_HOLD seconds. Arrived with nothing to shoot (or done with what there was), it looks round for LOOK_AROUND
## seconds, then stands down: every drone goes home, docks and stays there, the call forgotten. A swarm on its docks
## is nothing, not busy and not holding anything: it can be called again, and seeks on its own meanwhile. A call that
## never gets a drone off the dock lapses after LAUNCH_GRACE seconds the same way. With no call and nothing to do
## for IDLE_RETURN seconds the drones go home too.


const SIZE := 5
## How far out from the target the drones hang (m) and how high above its feet, and the angle between
## neighbours on that ring (rad).
const STANDOFF := 26.0
const HOVER_HEIGHT := 12.0
const SLOT_ANGLE := 0.42
const THINK_EVERY := 0.5
const ANGLE_EVERY := 1.2
## Seconds a called swarm holds the spot, and how far from it it looks for something to shoot.
const CALL_HOLD := 25.0
const ANCHOR_RADIUS := 80.0
## On its own a swarm looks this far from the middle of the map (flat): about the fortress's own size.
const SEEK_RADIUS := LevelBuilder.MOUNTAIN_HALF * 2.0
const IDLE_RETURN := 12.0
## A called swarm that has arrived and finds nothing to shoot stands down after this long (s).
const LOOK_AROUND := 5.0
## A call with no drone off its dock after this long (s) lapses.
const LAUNCH_GRACE := 3.0
## Seconds its drones can stand off its target without a line to it before it picks another for a while.
const UNSEEN_LIMIT := 4.0
const BAN_TIME := 12.0
## A bear or AA unit this close to a target (flat, m) is taken to guard it.
const GUARD_RADIUS := 32.0
## A swarm whose target has this share of its health left or less is not taken off it by a call.
const COMMITTED_HP := 0.35
## How much better a target is that is swimming or riding a raft: nothing swimming or riding attacks, so it can't hit back
## (a swimming bear can still dive out of sight: see _pick_focus).
const HELPLESS := 4.0
## A swarm is already on a caller's spot when its target is this close to it (m).
const COVER_RADIUS := 45.0
## How much each kind of unit is worth going after (1: an average one). Bears, rhinos and elephants are low:
## they are the ones that shoot back.
const PREY := {
	"medic": 3.0, "giraffe": 2.6, "mule": 2.2, "bison_gun": 2.0, "serpent": 1.9, "kangaroo": 1.7,
	"chimp": 1.4, "lioness": 1.2, "breacher": 1.2, "hippo": 1.0, "talon": 0.6,
	"rifleman": 0.5, "rhino": 0.3, "elephant": 0.25,
}

var bay: DroneBay = null
var number := 1
## The map's middle, for seeking.
var centre := Vector3.ZERO
## Its living drones.
var drones: Array = []
## The one attacker every drone of it is shooting.
var focus: Node3D = null
## The spot it was called to (INF: none) and the seconds it still holds it.
var anchor := Vector3.INF
var anchor_t := 0.0
## Stepped by hand (tests).
var manual := false
## Attackers it has picked as its focus (for the autotest and the tests).
var picks := 0

var _clock := 0.0
var _timers: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var _think_cd := 0.0
var _angle := 0.0
var _angle_cd := 0.0
var _angle_set := false
var _idle := 0.0
var _unseen := 0.0
var _banned := {}


func add_drone(d: DefenderDrone) -> void:
	d.swarm = self
	d.manual = manual
	d.died.connect(_on_drone_died)
	drones.append(d)


func _on_drone_died(d: DefenderDrone) -> void:
	drones.erase(d)
	if bay != null:
		bay.stats.drones_lost += 1
	if drones.is_empty():
		# Nobody left to send: what it was on and any call it held are forgotten (the hangar rebuilds it).
		focus = null
		_forget_call()


func _physics_process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	_clock += delta
	_rebuild_tick(delta)
	if drones.is_empty():
		return
	anchor_t = maxf(anchor_t - delta, 0.0)
	if anchor_t <= 0.0:
		anchor = Vector3.INF
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_EVERY
		_think()
	_steer()


# ---------------------------------------------------------------- the hangar

## The hangar rebuilds every missing drone at once: each empty place in the ring has a timer of its own, started
## when its drone was lost, and DefenderDrone.REBUILD_TIME later a new one stands full and mended on a dock. So a
## swarm that was shot to pieces is whole again after one REBUILD_TIME, not five, but every single rebuild is still
## slower than refuelling a drone that comes home (refuels run side by side too, each drone on its own dock).
func _rebuild_tick(delta: float) -> void:
	for i in SIZE:
		if bay == null or _place_taken(i):
			_timers[i] = 0.0
			continue
		_timers[i] = minf(_timers[i] + delta, DefenderDrone.REBUILD_TIME)
		if _timers[i] >= DefenderDrone.REBUILD_TIME and bay.make_drone(self, i):
			_timers[i] = 0.0


func _place_taken(i: int) -> bool:
	for d in drones:
		if d.index == i:
			return true
	return false


## Seconds until the next drone is finished (0: nothing is missing).
func rebuild_left() -> float:
	var left := 0.0
	for i in SIZE:
		if not _place_taken(i):
			var t: float = DefenderDrone.REBUILD_TIME - _timers[i]
			left = t if left == 0.0 else minf(left, t)
	return left


## The lowest place in the ring no living drone has (-1: all five are filled).
func free_index() -> int:
	for i in SIZE:
		var taken := false
		for d in drones:
			if d.index == i:
				taken = true
				break
		if not taken:
			return i
	return -1


## How good a shape the swarm is in, 0 to 1: the fuel times the health of each drone it has, over the five it
## should have. A full swarm with full tanks is 1; one with two drones shot down is at most 0.6; an empty one is 0.
## The freshest swarm gets every call (DroneBay.call_swarm).
func freshness() -> float:
	var sum := 0.0
	for d in drones:
		sum += clampf(float(d.fuel), 0.0, 1.0) * clampf(float(d.hp) / float(d.max_hp), 0.0, 1.0)
	return sum / float(SIZE)


# ---------------------------------------------------------------- state

func alive_count() -> int:
	return drones.size()


func airborne_count() -> int:
	var n := 0
	for d in drones:
		if d.is_airborne():
			n += 1
	return n


func ready_count() -> int:
	var n := 0
	for d in drones:
		if d.is_ready():
			n += 1
	return n


## Has a target it is working on, or a spot it was called to and is holding.
func busy() -> bool:
	return (Combat.is_valid_target(focus) and airborne_count() > 0) or anchor != Vector3.INF


## On the point of finishing its target: a call doesn't take it off.
func committed() -> bool:
	if not Combat.is_valid_target(focus) or airborne_count() == 0:
		return false
	var st = focus.get("stats")
	var hp = focus.get("hp")
	if st == null or hp == null:
		return false
	return float(hp) <= float(st.hp) * COMMITTED_HP


## Already on a spot: working on a target near it, or holding it after a call.
func covers(p: Vector3) -> bool:
	if airborne_count() == 0:
		return false
	if Combat.is_valid_target(focus) and _flat(focus.global_position, p) <= COVER_RADIUS:
		return true
	return anchor != Vector3.INF and _flat(anchor, p) <= COVER_RADIUS * 0.5


## Drones with the fuel for a sortie at all (not recharging, not on their way home because they must).
func fit_count() -> int:
	var n := 0
	for d in drones:
		if d.fuel >= DefenderDrone.MIN_SORTIE and not (d.state == DefenderDrone.State.RETURNING and d.due_home()):
			n += 1
	return n


func centroid() -> Vector3:
	if drones.is_empty():
		return centre
	var sum := Vector3.ZERO
	for d in drones:
		sum += d.global_position
	return sum / float(drones.size())


## How many of its drones could be sent to `p`: on their docks (mended), flying, or on their way home without
## having to be, with the fuel to get there and still be worth sending (DefenderDrone.can_reach). 0: the swarm can't
## be called there.
func call_quality(p: Vector3) -> int:
	var spot := Vector3(p.x, p.y + HOVER_HEIGHT, p.z)
	var home := bay.dock_distance(spot) if bay != null else 0.0
	var n := 0
	for d in drones:
		if d.state == DefenderDrone.State.RETURNING and d.due_home():
			continue
		if d.state == DefenderDrone.State.DOCKED and d.hp < d.max_hp * 0.5:
			continue
		if DefenderDrone.can_reach(d.fuel, d.global_position, spot, home):
			n += 1
	return n


## Sends the swarm to `p` (DroneBay.call_swarm has checked it can go): it drops what it was on.
func assign_call(p: Vector3) -> void:
	anchor = p
	anchor_t = CALL_HOLD
	focus = null
	_idle = 0.0
	_think_cd = 0.0


# ---------------------------------------------------------------- thinking

func _think() -> void:
	if not _focus_ok():
		focus = null
		_unseen = 0.0
	if focus == null:
		focus = _pick_focus()
		if focus != null:
			picks += 1
			_angle_set = false
			_unseen = 0.0
	if focus == null:
		var called := anchor != Vector3.INF
		# A called swarm waits only once it has got there; one that was never called has nowhere to be.
		if not called or _arrived():
			_idle += THINK_EVERY
		if _idle >= (LOOK_AROUND if called else IDLE_RETURN):
			_stand_down()
		elif called and CALL_HOLD - anchor_t > LAUNCH_GRACE and airborne_count() == 0:
			_forget_call()  # nobody could leave the dock
	else:
		_idle = 0.0
		_watch_line()
		if focus != null:
			_angle_cd -= THINK_EVERY
			if _angle_cd <= 0.0 or not _angle_set:
				_angle_cd = ANGLE_EVERY
				_choose_angle()
	for id in _banned.keys():
		if _banned[id] <= _clock:
			_banned.erase(id)


## Nothing to shoot: every drone goes home to dock, and the swarm forgets the call, so it is free to be called again.
func _stand_down() -> void:
	_forget_call()
	_idle = 0.0
	for d in drones:
		d.return_home()


func _forget_call() -> void:
	anchor = Vector3.INF
	anchor_t = 0.0
	_idle = 0.0


## Any drone of it is on the spot it was sent to.
func _arrived() -> bool:
	for d in drones:
		if d.state == DefenderDrone.State.FLYING and d.global_position.distance_to(d.goal) < 6.0:
			return true
	return false


## Still worth keeping: alive, above the water, not given up on, and where a full-tanked drone could go.
func _focus_ok() -> bool:
	if not Combat.is_valid_target(focus):
		return false
	if focus.has_method("is_submerged") and focus.is_submerged():
		return false
	if _concealed(focus):
		return false
	if _banned.get(focus.get_instance_id(), 0.0) > _clock:
		return false
	return _within_reach(focus.global_position)


## Out of the drones' sight: a sneaking (invisible) lioness, an anaconda coiled in a bush, or anyone in woodland.
func _concealed(u: Node3D) -> bool:
	return (u.has_method("is_sneaking") and u.is_sneaking()) or (u.has_method("is_coiled") and u.is_coiled()) \
			or LevelBuilder.in_forest(u.global_position)


## Could a full-tanked drone off the nearest dock stand off `p` and still be worth sending?
func _within_reach(p: Vector3) -> bool:
	if bay == null:
		return true
	var dock := bay.nearest_dock_pos(p)
	var toward := dock - p
	toward.y = 0.0
	var spot := p + Vector3(0.0, HOVER_HEIGHT, 0.0) + toward.normalized() * STANDOFF
	return DefenderDrone.can_reach(1.0, dock, spot, dock.distance_to(spot))


## Whom to go after next, by _score; null if there is no one it may and can.
func _pick_focus() -> Node3D:
	var anchored := anchor != Vector3.INF
	var ref := anchor if anchored else centre
	var radius := ANCHOR_RADIUS if anchored else SEEK_RADIUS
	var best: Node3D = null
	var best_score := 0.0
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if not u.is_alive() or u.raiding or u.is_submerged() or _concealed(u):
			continue
		if _banned.get(u.get_instance_id(), 0.0) > _clock:
			continue
		var p: Vector3 = u.global_position
		if _flat(p, ref) > radius or not _within_reach(p):
			continue
		var s := _score(u, ref, anchored)
		if s > best_score:
			best_score = s
			best = u
	return best


func _score(u: Node, ref: Vector3, anchored: bool) -> float:
	var w: float = PREY.get(u.type_id, 1.0)
	if u.is_crossing():
		w *= HELPLESS
	var st: Dictionary = u.stats
	var hp_frac: float = clampf(float(u.hp) / float(st.hp), 0.0, 1.0)
	w *= 1.0 + (1.0 - hp_frac) * 0.8
	var pos: Vector3 = u.global_position
	if bay != null:
		var guards := 0
		for h in bay.hunters:
			if h.unit != u and _flat(h.pos, pos) <= GUARD_RADIUS:
				guards += 1
		w /= 1.0 + 0.7 * float(guards)
		var others := 0
		for s in bay.swarms:
			if s != self and s.focus == u:
				others += 1
		w /= 1.0 + 0.6 * float(others)
	w /= 1.0 + _flat(ref, pos) / (60.0 if anchored else 140.0)
	return w


## Counts the seconds its drones have stood off the focus with no clear line to it; past UNSEEN_LIMIT it gives that
## one up for a while (it is inside the mountain, behind a hill, in the smoke).
func _watch_line() -> void:
	var arrived := false
	var seen := false
	for d in drones:
		if d.state == DefenderDrone.State.FLYING and _flat(d.global_position, focus.global_position) <= STANDOFF + 8.0:
			arrived = true
			if d.has_line():
				seen = true
	if seen:
		_unseen = 0.0
	elif arrived:
		_unseen += THINK_EVERY
		if _unseen >= UNSEEN_LIMIT:
			_banned[focus.get_instance_id()] = _clock + BAN_TIME
			focus = null
			_unseen = 0.0


## Picks the side of the focus the drones hang on: the one with the least bear and AA reach over it, near the
## way they came, and (not to dither) near the side they already hang on.
func _choose_angle() -> void:
	var c: Vector3 = focus.global_position
	var from := centroid()
	var best_a := _angle
	var best_cost := INF
	for k in 16:
		var a := TAU * float(k) / 16.0
		var spot := Vector3(c.x + cos(a) * STANDOFF, c.y, c.z + sin(a) * STANDOFF)
		var cost := _flat(from, spot) / 100.0
		if bay != null:
			for h in bay.hunters:
				var reach: float = float(h.reach) + 4.0
				var d := _flat(h.pos, spot)
				if d < reach:
					cost += (1.0 - d / reach) * 6.0
		if _angle_set:
			cost += absf(angle_difference(_angle, a)) * 0.4
		# A side the drones couldn't be sent to on a full tank would leave the swarm holding a target nobody can reach.
		if bay != null:
			var up := Vector3(spot.x, spot.y + HOVER_HEIGHT, spot.z)
			var dock := bay.nearest_dock_pos(up)
			if not DefenderDrone.can_reach(1.0, dock, up, dock.distance_to(up)):
				cost += 40.0
		if cost < best_cost:
			best_cost = cost
			best_a = a
	_angle = best_a
	_angle_set = true


# ---------------------------------------------------------------- steering

## Sends the ready drones out, puts every flying one on its spot and its guns on the focus.
func _steer() -> void:
	if focus != null and not Combat.is_valid_target(focus):
		focus = null  # freed or dead since the last think
	_dispatch()
	var c := Vector3.ZERO
	if focus != null:
		c = focus.global_position
	for d in drones:
		if d.state != DefenderDrone.State.FLYING:
			continue
		if focus != null:
			d.goal = _spot(c, d.index)
			d.target = focus
		elif anchor != Vector3.INF:
			d.goal = _loiter_spot(d.index)
			d.target = null
		else:
			d.target = null


## Drones that are full again go back out after the focus (or to the spot a call holds, with no focus yet); a
## called swarm doesn't wait for them to fill up, only for the trip to be worth it. Drones on their way home
## without having to be (it stood down) turn round for a new target.
func _dispatch() -> void:
	if focus == null and anchor == Vector3.INF:
		return
	var early := anchor != Vector3.INF
	for d in drones:
		if d.state == DefenderDrone.State.FLYING:
			continue
		var spot := _spot(focus.global_position, d.index) if focus != null else _loiter_spot(d.index)
		var home := bay.dock_distance(spot) if bay != null else 0.0
		if not DefenderDrone.can_reach(d.fuel, d.global_position, spot, home):
			continue
		if d.state == DefenderDrone.State.RETURNING:
			d.redirect(spot)
		else:
			d.launch(spot, early)


## Drone `i`'s spot on the ring round `c`: STANDOFF out, HOVER_HEIGHT up (clear of the canopy where there is one).
func _spot(c: Vector3, i: int) -> Vector3:
	var a := _angle + (float(i) - float(SIZE - 1) * 0.5) * SLOT_ANGLE
	var p := Vector3(c.x + cos(a) * STANDOFF, c.y + HOVER_HEIGHT, c.z + sin(a) * STANDOFF)
	var floor_y := LevelBuilder.flight_floor(p)
	if not is_nan(floor_y):
		p.y = maxf(p.y, floor_y + 3.0)
	return p


func _loiter_spot(i: int) -> Vector3:
	var a := TAU * float(i) / float(SIZE)
	return anchor + Vector3(cos(a) * 8.0, HOVER_HEIGHT, sin(a) * 8.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
