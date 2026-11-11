class_name TransportHelo
extends CharacterBody3D
## The attackers' transport helicopter (the Heavy Lift Helicopter, HeavyLiftRig): HeloCargo.FLEET_SIZE of them stand by the
## main base (HeloFleet), and each takes up to HeloCargo.CAPACITY spaces of units from the base to a helipad the attackers
## hold (an outpost: AttackerBase), see HeloCargo for what each unit takes.
##
## A trip: units sent to board (AttackerCommander "helo_board") walk to the ramp at its tail and go in (reserve, take_aboard);
## the attacking player sends it to ONE helipad they hold ("helo_fly": dispatch) and it is committed to that trip: it spins
## its rotors up, climbs, flies there and sets down on the helipad's pad itself (AttackerBase.landing_point). It unloads its
## hold one unit every HeloCargo.UNLOAD_TIME s in the order they went in (a queue), each put down on the ground next to the
## camp (AttackerBase.drop_spot: the deck is solid); then it goes straight home again and sets down where it started.
##
## The helipad lost (the defenders take it: no longer `controlled`):
##   on the way there, it turns back and brings its units home, where they get out by the main spawn point (home_drop);
##   while it is on the pad, unloading or mending, it is caught there: it loses CAPTURE_DAMAGE of its full health and lifts off
##   at once with whatever is still aboard, and brings that home. Too hurt to take that, it is destroyed there with them
##   (and the helipad is lost all the same).
##
## It is tough (MAX_HP) but not invulnerable. A helicopter hurt stays on the ground where it landed (at the outpost or at
## the base) and mends there (REPAIR_SECONDS from nothing to full); it takes off again only once it is recovered. It shows
## its hurt: grey smoke from its engines at GREY_SMOKE_AT of its health, black at BLACK_SMOKE_AT, a column of fire straight
## up at FIRE_AT (damage_stage). Destroyed, it takes everything aboard with it, and HeloFleet has a new one at the base
## HeloCargo.REPLACE_TIME s later.
##
## Who can hurt it: it is "damageable" with a body of its own, so whatever the defending player aims, fires or drops at it
## lands (the fighter jet's bombs and missiles, the tank's shells and guns, rifles, snipers, an AA squad's missiles when
## the player locks them on; blasts near it too). But it is NOT in "air_units" or "attacker_units", the groups every
## defender looks its targets up in: nothing on its own (an idle post, squad, tank or jet, the AA turrets, the drones)
## ever picks it out, and the player's AA lock-on (AASquad) adds it by hand. Stray rounds and blasts meant for something else
## still reach it, as they would anything standing there.
##
## A landed or parked helicopter's underside is clear: its body is a box 3 m up, so rounds fired at the units round it go
## under, and the army's own shots at the defenders don't stop on it.
##
## step() does the work; _physics_process calls it unless `manual` (the showcase steps it by hand at a fixed rate).

signal state_changed(helo: TransportHelo)
## One unit out of the hold.
signal unloaded(helo: TransportHelo, unit: AttackerUnit)
## Destroyed (its cargo is lost with it).
signal destroyed(helo: TransportHelo)
## The helipad of its trip was lost and it turned for home with what is aboard; `on_pad`: it was caught on the pad
## (unloading or mending) and took CAPTURE_DAMAGE lifting off.
signal trip_aborted(helo: TransportHelo, on_pad: bool)

enum State { PARKED, SPOOL, CLIMB, CRUISE, DESCEND, UNLOAD, REPAIR }

## Hit points, and the seconds a landed helicopter takes to mend from nothing to full.
const MAX_HP := 6000.0
const REPAIR_SECONDS := 120.0
## Caught on a helipad as the defenders take it: it loses this share of its full health and lifts off at once.
const CAPTURE_DAMAGE := 0.2
## Seconds the rotors take to come up to speed before it lifts off.
const SPOOL_TIME := 6.0
## Flying: cruising speed and the acceleration it gets up to it and brakes with (m/s, m/s²), how fast it climbs and sets
## down (m/s), how fast it turns (rad/s).
const CRUISE_SPEED := 45.0
const ACCEL := 6.0
const CLIMB_SPEED := 14.0
const DESCEND_SPEED := 10.0
const TURN_RATE := 0.7
## It cruises this far over the highest ground, treetops or helipad deck on its way (m), and never lower than MIN_CRUISE.
## Anywhere near the mountain it goes over the top (OVER_MOUNTAIN); its routes keep well clear of it anyway.
const CLEARANCE := 55.0
const MIN_CRUISE := 70.0
const OVER_MOUNTAIN := 160.0
## How close (flat, m) to the spot it is going to counts as over it.
const ARRIVE := 3.0
## The ramp is this far behind its middle (m): the tail of a 64 m helicopter.
const RAMP_BACK := 34.0
## Its body for rounds and blasts: a box (m) with its middle BODY_LIFT up, and the radius (m) a blast reaches it from its middle.
const BODY := Vector3(10.0, 8.0, 56.0)
const BODY_LIFT := 7.0
const HURT_TIME := 0.5
## Units it brings home stand about the main spawn point this far apart (m).
const HOME_SPACING := 3.4
## Its hurt, as a share of its health: grey smoke at or below GREY_SMOKE_AT, black at or below BLACK_SMOKE_AT, and fire
## straight up out of it at or below FIRE_AT.
const GREY_SMOKE_AT := 0.6
const BLACK_SMOKE_AT := 0.4
const FIRE_AT := 0.1
## Where the smoke and fire come out, in its own frame (+Z its nose): the engines on the hump, by the rear rotor's mast.
const ENGINES := [Vector3(-2.4, 13.0, -13.0), Vector3(2.4, 13.0, -13.0)]
## Puffs a second from each engine (grey, black), and tongues of flame a second.
const GREY_RATE := 7.0
const BLACK_RATE := 12.0
const FIRE_RATE := 30.0
## The wreck burns this long before it is gone (s).
const WRECK_TIME := 25.0
const RING_COLOR := Color(0.3, 1.0, 0.4)
const RING_RADIUS := 38.0

var team := GameConfig.TEAM_ATTACKER
var hp := MAX_HP
var max_hp := MAX_HP
## How far a blast reaches it from its middle (Combat.damage_area).
var target_radius := 24.0
## Which of the fleet's helicopters it is (0, 1), and its name.
var slot := 0
var display_name := "Helo 1"
var state := State.PARKED
## Where it stands by the base (the ground under it) and the way it faces: where it comes home to.
var home_position := Vector3.ZERO
var home_yaw := 0.0
## Where the units it brings home get out (the main spawn point; INF: at its ramp).
var home_drop := Vector3.INF
## The units aboard, in the order they went in (the order they come out in).
var cargo: Array = []
## The helipad it is sent to (its short name); true while it is on its way out or at the outpost, false heading home or at home.
var dest_name := ""
var out_leg := false
## Selected by the attacking player (the ring on the ground, its health bar).
var selected := false:
	set(v):
		selected = v
		if _ring:
			_ring.visible = v
## A showcase steps it by hand (step), and may leave the model out.
var manual := false
var with_rig := true
var rig: HeavyLiftRig
## Units it has put down at the outpost on this trip.
var unloaded_count := 0
## Showcase totals.
var stats := {"trips": 0, "units_flown": 0, "units_lost": 0, "units_returned": 0, "turned_back": 0}

var _reserved: Array = []
## The helipad of this trip (an AttackerBase, or a stand-in with the same members).
var _dest: Object = null
var _goal := Vector3.ZERO
var _goal_yaw := 0.0
var _unload_spots: Array[Vector3] = []
var _unload_k := 0
var _cruise_y := 0.0
var _speed := 0.0
## The way it is flying (flat), and the way it was going when it turned back (it carries on, braking, as it climbs).
var _dir := Vector3.ZERO
var _coast := Vector3.ZERO
var _t := 0.0
var _unload_t := 0.0
var _hurt := 0.0
var _dead := false
var _label_cd := 0.0
var _smoke_acc := 0.0
var _fire_acc := 0.0
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _label: Label3D
var _ring: MeshInstance3D
var _smoke: WreckSmoke
var _fire_light: OmniLight3D


## Names it and stands it at its parking spot (before it enters the tree).
func setup(index: int, at: Vector3, yaw: float) -> void:
	slot = index
	display_name = "Helo %d" % (index + 1)
	name = "TransportHelo%d" % (index + 1)
	home_position = at
	home_yaw = yaw
	position = at
	rotation.y = yaw


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("transport_helos")
	collision_layer = GameConfig.LAYER_ATTACKERS
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY
	shape.shape = box
	shape.position.y = BODY_LIFT
	add_child(shape)
	if with_rig:
		rig = HeavyLiftRig.new()
		add_child(rig)
	_build_marks()


func _physics_process(delta: float) -> void:
	if not manual:
		step(delta)


# ---------------------------------------------------------------- a target

func is_alive() -> bool:
	return hp > 0.0 and not _dead


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * BODY_LIFT


func take_damage(amount: float, from_team: int) -> void:
	if not is_alive() or from_team == team or amount <= 0.0:
		return
	hp -= amount
	_hurt = HURT_TIME
	_refresh_marks()
	if hp <= 0.0:
		hp = 0.0
		_destroy()


## Shot down (or blown up where it stands): the hold and everything in it is lost, the wreck burns and is gone.
func _destroy() -> void:
	var grounded := _on_ground()
	_dead = true
	var lost := 0
	for u in cargo.duplicate():
		if is_instance_valid(u):
			u.perish()
			lost += 1
	cargo.clear()
	_reserved.clear()
	stats.units_lost += lost
	remove_from_group("damageable")
	remove_from_group("transport_helos")
	collision_layer = 0
	selected = false
	if rig:
		rig.stop()
	_refresh_marks()
	destroyed.emit(self)
	# Out of the sky it falls to what is under it: the ground, or the deck it was coming down onto.
	var floor_y := LevelBuilder.ground_height(global_position)
	if Vector2(global_position.x - _goal.x, global_position.z - _goal.z).length() < 40.0:
		floor_y = maxf(floor_y, _goal.y)
	var height := 0.0 if grounded else global_position.y - floor_y
	Combat.spawn_explosion(self, global_position + Vector3.UP * BODY_LIFT, 18.0, height > 1.0)
	var tw := create_tween()
	if height > 1.0:
		# Spinning down, then a great fireball where it lands.
		var fall := clampf(sqrt(2.0 * height / 9.8) * 1.4, 1.5, 7.0)
		tw.set_parallel(true)
		tw.tween_property(self, "global_position:y", floor_y, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "rotation:y", rotation.y + 5.0, fall)
		tw.tween_property(self, "rotation:z", 0.9, fall)
		tw.set_parallel(false)
		tw.tween_callback(func(): Combat.spawn_explosion(self, global_position + Vector3.UP * 4.0, 22.0))
	tw.tween_interval(WRECK_TIME)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- the hold

## Open to the units walking up to it: standing on the ground at the base, not committed to a trip.
func can_board() -> bool:
	return is_alive() and state == State.PARKED


func spaces_used() -> int:
	var n := 0
	for u in cargo:
		if is_instance_valid(u):
			n += HeloCargo.spaces(u.type_id)
	return n


## Spaces kept for the units on their way to board.
func spaces_reserved() -> int:
	_purge_reserved()
	var n := 0
	for u in _reserved:
		n += HeloCargo.spaces(u.type_id)
	return n


func spaces_free() -> int:
	return HeloCargo.CAPACITY - spaces_used() - spaces_reserved()


## The types of what is aboard, in order.
func cargo_types() -> Array:
	var out := []
	for u in cargo:
		if is_instance_valid(u):
			out.append(u.type_id)
	return out


## Keeps `u` a place if there is room (the units sent to board each have one; a unit counts once). False: it doesn't fit,
## or the hold is shut.
func reserve(u: AttackerUnit) -> bool:
	if not can_board() or not is_instance_valid(u):
		return false
	_purge_reserved()
	if u in _reserved:
		return true
	if not HeloCargo.fits(spaces_used() + spaces_reserved(), u.type_id):
		return false
	_reserved.append(u)
	return true


## Gives up the place kept for `u`.
func release(u: AttackerUnit) -> void:
	_reserved.erase(u)


## True if `u` may walk in: it has a place kept and the hold is open.
func accepts(u: AttackerUnit) -> bool:
	return can_board() and u in _reserved


## `u` is at the ramp: in it goes, out of the world until it is unloaded.
func take_aboard(u: AttackerUnit) -> void:
	if not accepts(u):
		return
	_reserved.erase(u)
	cargo.append(u)
	u.stow(self)
	_refresh_marks()


## The reservations of units that have since been given other orders, or have died.
func _purge_reserved() -> void:
	_reserved = _reserved.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.order.type == "helo" \
			and u.order.get("helo") == self)


## The foot of the ramp at its tail, on the ground, where units walk to.
func ramp_point() -> Vector3:
	var p := global_position - global_basis.z * RAMP_BACK
	p.y = LevelBuilder.ground_height(p)
	return p


# ---------------------------------------------------------------- a trip

## True if it can be sent to `base` (a helipad the attackers hold, AttackerBase) now: on the ground at the base, mended, with
## something in the hold.
func can_dispatch(base: Object) -> bool:
	return is_alive() and state == State.PARKED and hp >= max_hp - 0.01 and not cargo.is_empty() \
			and base != null and is_instance_valid(base) and base.controlled


## Sends it to `base`: the one place it goes this trip. Nobody else gets on. False if it can't go.
func dispatch(base: Object) -> bool:
	if not can_dispatch(base):
		return false
	_reserved.clear()
	_dest = base
	dest_name = base.short_name
	unloaded_count = 0
	stats.trips += 1
	stats.units_flown += cargo.size()
	_begin_leg(base.landing_point(), base.landing_yaw(), true)
	return true


## Spins up on the ground for a leg to `goal` (where it sets down) and `yaw`.
func _begin_leg(goal: Vector3, yaw: float, out: bool) -> void:
	_goal = goal
	_goal_yaw = yaw
	out_leg = out
	_cruise_y = cruise_altitude(global_position, goal)
	_speed = 0.0
	_coast = Vector3.ZERO
	_set_state(State.SPOOL)


## Turns for home now: straight into the climb back to cruising height, turning as it goes. Off a pad it lifts straight off;
## in the air it carries on the way it was going for a moment, braking.
func _head_home(off_pad: bool) -> void:
	_goal = home_position
	_goal_yaw = home_yaw
	out_leg = false
	# Cruising height is reckoned from what is under it (the pad's deck, or the ground under it in the air), not from how high
	# it happens to be.
	var from := global_position
	if not off_pad:
		from.y = LevelBuilder.ground_height(global_position)
	_cruise_y = cruise_altitude(from, home_position)
	_coast = Vector3.ZERO if off_pad else _dir * _speed
	_speed = 0.0
	_set_state(State.CLIMB)


## True while the helipad of this trip is still the attackers'.
func _dest_held() -> bool:
	return _dest != null and is_instance_valid(_dest) and _dest.controlled


## The helipad of this trip has been lost: what it does depends on where it is.
func _destination_lost() -> void:
	out_leg = false
	stats.turned_back += 1
	match state:
		State.UNLOAD, State.REPAIR:
			# Caught on the pad as it falls: hit as it goes, it lifts off at once with whatever is still aboard. Too hurt to take
			# it, it is destroyed there, and what is left aboard with it.
			take_damage(max_hp * CAPTURE_DAMAGE, GameConfig.TEAM_DEFENDER)
			if _dead:
				return
			_head_home(true)
			trip_aborted.emit(self, true)
		State.SPOOL:
			# Still spinning up at the base: it never left. Its units get out again.
			_start_unload()
			trip_aborted.emit(self, false)
		_:
			# On the way (climbing, flying, setting down): it turns back and brings them home.
			_head_home(false)
			trip_aborted.emit(self, false)


## How high to cruise between two spots: CLEARANCE over the highest ground or treetops along the way (and over either end,
## a helipad's deck included).
static func cruise_altitude(a: Vector3, b: Vector3) -> float:
	var top := maxf(a.y, b.y)
	for k in 17:
		var p := a.lerp(b, float(k) / 16.0)
		top = maxf(top, maxf(LevelBuilder.ground_height(p), 0.0))
		if LevelBuilder.jungle and JungleFlora.in_jungle(p):
			top = maxf(top, maxf(LevelBuilder.ground_height(p), 0.0) + LevelBuilder.CANOPY_TOP)
		if LevelBuilder.base_distance(p) < 20.0:
			top = maxf(top, OVER_MOUNTAIN - CLEARANCE)
	return maxf(top + CLEARANCE, MIN_CRUISE)


func _set_state(s: State) -> void:
	state = s
	_t = 0.0
	if rig:
		if s == State.PARKED or s == State.REPAIR:
			rig.stop()
		else:
			rig.start()
	state_changed.emit(self)


func step(delta: float) -> void:
	if _dead:
		return
	_hurt = maxf(_hurt - delta, 0.0)
	_t += delta
	if out_leg and not _dest_held():
		_destination_lost()
		if _dead:
			return
	match state:
		State.PARKED:
			_repair(delta)
		State.SPOOL:
			if _t >= SPOOL_TIME:
				_set_state(State.CLIMB)
		State.CLIMB:
			_turn_toward(_heading_to(_goal), delta)
			global_position.y = move_toward(global_position.y, _cruise_y, CLIMB_SPEED * delta)
			if _coast != Vector3.ZERO:
				global_position += _coast * delta
				_coast = _coast.move_toward(Vector3.ZERO, ACCEL * delta)
			if absf(global_position.y - _cruise_y) < 0.05 and _coast == Vector3.ZERO:
				_set_state(State.CRUISE)
		State.CRUISE:
			_cruise(delta)
		State.DESCEND:
			_descend(delta)
		State.UNLOAD:
			_repair(delta)
			_unload(delta)
		State.REPAIR:
			_repair(delta)
			if hp >= max_hp - 0.01:
				_begin_leg(home_position, home_yaw, false)


## The yaw that points its nose at `p` (flat); its own if it is right over it.
func _heading_to(p: Vector3) -> float:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.5:
		return rotation.y
	return atan2(d.x, d.z)


func _turn_toward(yaw: float, delta: float) -> void:
	rotation.y = rotate_toward(rotation.y, yaw, TURN_RATE * delta)


## Flat flight toward the spot it is to set down over, braking to stop over it.
func _cruise(delta: float) -> void:
	var to := Vector2(_goal.x - global_position.x, _goal.z - global_position.z)
	var dist := to.length()
	if dist <= ARRIVE:
		_speed = 0.0
		_set_state(State.DESCEND)
		return
	var dir := to / dist
	_dir = Vector3(dir.x, 0.0, dir.y)
	_turn_toward(atan2(dir.x, dir.y), delta)
	# Brake so as to stop over the spot: v² = 2 a d.
	var want := minf(CRUISE_SPEED, sqrt(2.0 * ACCEL * dist))
	_speed = move_toward(_speed, want, ACCEL * delta)
	var move := minf(_speed * delta, dist)
	global_position += _dir * move


## Sets down: settles over the spot, turns onto the heading it lands on and comes down.
func _descend(delta: float) -> void:
	var p := Vector2(global_position.x, global_position.z).move_toward(Vector2(_goal.x, _goal.z), 4.0 * delta)
	global_position.x = p.x
	global_position.z = p.y
	_turn_toward(_goal_yaw, delta)
	var rate := clampf((global_position.y - _goal.y) * 0.5, 2.0, DESCEND_SPEED)
	global_position.y = move_toward(global_position.y, _goal.y, rate * delta)
	if global_position.y <= _goal.y + 0.01:
		global_position.y = _goal.y
		_land()


## Down: on the outpost's pad it unloads; at the base it unloads whatever it brought back, else it stands.
func _land() -> void:
	_speed = 0.0
	if not out_leg:
		rotation.y = _goal_yaw
	if out_leg or not cargo.is_empty():
		_start_unload()
	else:
		_set_state(State.PARKED)


## On the ground, mending or not, spinning up or not.
func _on_ground() -> bool:
	return state == State.PARKED or state == State.SPOOL or state == State.UNLOAD or state == State.REPAIR


# ---------------------------------------------------------------- unloading and mending

## Opens up: where each unit aboard is put down, worked out now. At the outpost, on the ground next to the camp
## (AttackerBase.drop_spot); back at the base, about the main spawn point.
func _start_unload() -> void:
	_unload_t = 0.0
	_unload_k = 0
	_unload_spots.clear()
	var n := cargo.size()
	if out_leg and _dest != null and is_instance_valid(_dest):
		for k in n:
			_unload_spots.append(_dest.drop_spot(k, n))
	else:
		var centre := home_drop if home_drop != Vector3.INF else ramp_point()
		var offsets := AttackerCommander.formation_offsets(n, HOME_SPACING)
		for k in n:
			var p: Vector3 = centre + offsets[k]
			p.y = LevelBuilder.ground_height(p)
			_unload_spots.append(p)
	_set_state(State.UNLOAD)


## The queue: a unit out every UNLOAD_TIME s, the first in the first out.
func _unload(delta: float) -> void:
	_unload_t += delta
	while _unload_t >= HeloCargo.UNLOAD_TIME and not cargo.is_empty():
		_unload_t -= HeloCargo.UNLOAD_TIME
		_unload_one()
	if not cargo.is_empty():
		return
	if not out_leg:
		# Home with what it brought back: done, it stands (and mends, if it has to).
		_set_state(State.PARKED)
	elif hp >= max_hp - 0.01:
		# Unhurt, it goes straight home.
		_begin_leg(home_position, home_yaw, false)
	else:
		# Hurt, it stays on the pad till it is recovered.
		_set_state(State.REPAIR)


func _unload_one() -> void:
	var u = cargo.pop_front()
	if not is_instance_valid(u):
		return
	var spot: Vector3 = _unload_spots[_unload_k] if _unload_k < _unload_spots.size() else ramp_point()
	_unload_k += 1
	var away := spot - global_position
	u.unstow(spot + Vector3.UP * 0.2, atan2(-away.x, -away.z))
	if out_leg:
		unloaded_count += 1
	else:
		stats.units_returned += 1
	unloaded.emit(self, u)
	_refresh_marks()


## A landed helicopter mends: nothing flying does.
func _repair(delta: float) -> void:
	if hp < max_hp:
		hp = minf(max_hp, hp + max_hp / REPAIR_SECONDS * delta)
		_refresh_marks()


## Mended, 0..1.
func health() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


## How its hurt shows: 0 none, 1 grey smoke (at or below GREY_SMOKE_AT), 2 black smoke (BLACK_SMOKE_AT), 3 fire (FIRE_AT).
func damage_stage() -> int:
	if _dead:
		return 0
	var f := health()
	if f <= FIRE_AT:
		return 3
	if f <= BLACK_SMOKE_AT:
		return 2
	if f <= GREY_SMOKE_AT:
		return 1
	return 0


## On the ground, mending or not (parked, unloading, waiting to be mended).
func is_landed() -> bool:
	return state == State.PARKED or state == State.UNLOAD or state == State.REPAIR


## What it is doing, for the panel and the label over it.
func status_text() -> String:
	if _dead:
		return "DESTROYED"
	var mended := "%d%%" % int(health() * 100.0)
	var bringing := "BRINGING %d HOME" % cargo.size() if not cargo.is_empty() else "RETURNING TO BASE"
	match state:
		State.PARKED:
			return "AT BASE" if hp >= max_hp - 0.01 else "AT BASE · MENDING %s" % mended
		State.SPOOL:
			return "SPINNING UP"
		State.CLIMB:
			return "TAKING OFF" if out_leg or cargo.is_empty() else "TURNING BACK · " + bringing
		State.CRUISE:
			return "FLYING TO %s" % dest_name.to_upper() if out_leg else bringing
		State.DESCEND:
			return "LANDING AT %s" % dest_name.to_upper() if out_leg else "LANDING AT BASE"
		State.UNLOAD:
			return "UNLOADING AT %s · %d LEFT" % [dest_name.to_upper() if out_leg else "BASE", cargo.size()]
		State.REPAIR:
			return "MENDING AT %s · %s" % [dest_name.to_upper(), mended]
	return ""


# ---------------------------------------------------------------- what shows

func _build_marks() -> void:
	# The wreck's fire, once it is destroyed.
	_smoke = WreckSmoke.new()
	_smoke.size = 3.0
	_smoke.rate = 12.0
	_smoke.position = Vector3(0.0, BODY_LIFT + 2.0, -6.0)
	add_child(_smoke)
	# The engines' fire, at the last of its health.
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.18)
	_fire_light.omni_range = 18.0
	var left: Vector3 = ENGINES[0]
	var right: Vector3 = ENGINES[1]
	_fire_light.position = (left + right) * 0.5 + Vector3.UP * 2.0
	_fire_light.visible = false
	add_child(_fire_light)
	# The health bar over it, facing the camera.
	_bar = Node3D.new()
	_bar.top_level = true
	_bar.visible = false
	add_child(_bar)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(22.0, 1.3)
	bg.mesh = q
	bg.material_override = Mats.unshaded(Color(0, 0, 0, 0.6))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(22.0, 0.9)
	_bar_fill.mesh = qf
	_bar_fill.position.z = 0.01
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.add_child(_bar_fill)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 24
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.85, 0.7)
	_label.position = Vector3(0.0, 31.0, 0.0)
	add_child(_label)
	# The selection ring on the ground (or the deck) under it.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	RhinoAim.dashed_circle(im, Vector3.ZERO, RING_RADIUS, 64)
	im.surface_end()
	_ring = MeshInstance3D.new()
	_ring.mesh = im
	_ring.material_override = Mats.unshaded(RING_COLOR)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.top_level = true
	_ring.visible = selected
	add_child(_ring)
	_refresh_marks()


func _process(delta: float) -> void:
	if _dead:
		return
	if _bar.visible:
		_bar.global_position = global_position + Vector3.UP * 27.0
		var cam := get_viewport().get_camera_3d()
		if cam:
			_bar.global_basis = cam.global_basis
	if _ring.visible:
		var under := global_position.y if _on_ground() else LevelBuilder.ground_height(global_position)
		_ring.global_position = Vector3(global_position.x, under + 0.3, global_position.z)
	_damage_fx(delta)
	_label_cd -= delta
	if _label_cd <= 0.0:
		_label_cd = 0.25
		_label.text = "%s · %d/%d\n%s" % [display_name.to_upper(), spaces_used(), HeloCargo.CAPACITY, status_text()]


## Its hurt, out of its engines: grey smoke, then black, then fire leaping straight up with the black smoke over it. The puffs
## are left in the air where they came out, so a helicopter flying hurt trails them.
func _damage_fx(delta: float) -> void:
	var stage := damage_stage()
	_fire_light.visible = stage >= 3
	if stage == 0:
		_smoke_acc = 0.0
		_fire_acc = 0.0
		return
	var fx := FX.of(self)
	_smoke_acc += delta * (GREY_RATE if stage == 1 else BLACK_RATE)
	while _smoke_acc >= 1.0:
		_smoke_acc -= 1.0
		for e in ENGINES:
			var engine: Vector3 = e
			var at: Vector3 = global_transform * engine
			var j := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			if stage == 1:
				var tone := randf_range(0.5, 0.62)
				fx.smoke(at + j * 0.5, Vector3(j.x * 0.6, randf_range(2.0, 3.0), j.z * 0.6), randf_range(3.0, 4.5), 1.0,
						randf_range(4.0, 5.5), Color(tone, tone, tone * 1.02, 0.5), 0.5, 0.6, 0.0, 1.0)
			else:
				var dark := randf_range(0.04, 0.09)
				fx.smoke(at + j * 0.5, Vector3(j.x * 0.6, randf_range(2.5, 3.5), j.z * 0.6), randf_range(4.0, 6.0), 1.4,
						randf_range(5.5, 7.5), Color(dark, dark * 0.96, dark * 0.92, 0.85), 0.5, 0.6, 0.6 if stage >= 3 else 0.0, 0.9)
	if stage < 3:
		return
	_fire_acc += delta * FIRE_RATE
	while _fire_acc >= 1.0:
		_fire_acc -= 1.0
		var engine: Vector3 = ENGINES[randi() % ENGINES.size()]
		var at: Vector3 = global_transform * engine
		fx.flame(at + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)),
				Vector3(randf_range(-0.3, 0.3), randf_range(8.0, 12.0), randf_range(-0.3, 0.3)), randf_range(0.45, 0.75), 1.0,
				randf_range(2.2, 3.2), 1.0, 0.3, 1.0, 0.55, 0.35)
	_fire_light.light_energy = randf_range(2.0, 3.5)


## The health bar's colour and the wreck's fire follow its health.
func _refresh_marks() -> void:
	if _bar == null:
		return
	var ratio := health()
	_bar.visible = _dead == false and (selected or ratio < 1.0)
	_bar_fill.scale.x = maxf(ratio, 0.001)
	var color := Color(0.3, 1.0, 0.4)
	if ratio <= FIRE_AT:
		color = Color(1.0, 0.2, 0.15)
	elif ratio <= BLACK_SMOKE_AT:
		color = Color(1.0, 0.5, 0.15)
	elif ratio <= GREY_SMOKE_AT:
		color = Color(0.95, 0.8, 0.2)
	_bar_fill.material_override = Mats.unshaded(color)
	_smoke.emitting = _dead
	if _dead:
		_fire_light.visible = false
