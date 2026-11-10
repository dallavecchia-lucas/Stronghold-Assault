class_name DefenderDrone
extends Node3D
## One drone of a DroneSwarm: the defenders' small ducted-fan gunship (DroneRig). It never goes far from the
## fortress and, left alive, goes home to recharge. Low damage, but it keeps at it.
##
## FUEL (a full tank is 1.0). All of it lives in the three static helpers below, so the swarm, the bay and the
## tests price a trip the same way the drone does:
##   - Flying costs TRAVEL_COST (a third of a tank) for every FORTRESS_SIZE metres actually flown, in any
##     direction. (Charging by distance from the fortress instead would let a drone circle for ever for nothing.)
##   - Standing still, shooting included, costs HOVER_BURN: 5% of a tank every 10 s. Moving never costs less than
##     that either.
##   - The way home is always priced from where it is: it turns back the moment its tank is down to RETURN_FLOOR
##     (50%), or the fuel the flight home would take is RETURN_SHARE (half) of what it has left, whichever comes
##     first. Close to the fortress that is the 50% mark; out at the end of its leash the second rule pulls it
##     back much sooner, and one that has hovered over a fight until even the short way home costs half of
##     what is left goes home too. It lands with at least as much fuel as the trip cost, never stranded.
## It lands on a dock on the roofs (DroneBay), recharges and mends (RECHARGE_TIME from empty), and leaves again
## once it is nearly full (LAUNCH_FUEL), so it never takes off just to turn round.
##
## HURT: only anti-air damage hurts it (the elephants' flak and missiles, the rhinos' guns, and the bears' rifles
## through Combat.fire_at_air), because it sits in "air_units" for them to find but not in "damageable" (blasts,
## strays and everyone else's rounds never reach it; it has no body to hit either). Docked, nothing can.

signal died(drone: DefenderDrone)

enum State { DOCKED, FLYING, RETURNING }

## The size of the defender fortress (m): the mountain's footprint, the yardstick of the fuel cost.
const FORTRESS_SIZE := LevelBuilder.MOUNTAIN_HALF * 2.0
## Fuel (of a full tank) per FORTRESS_SIZE metres flown, and per metre.
const TRAVEL_COST := 1.0 / 3.0
const FUEL_PER_M := TRAVEL_COST / FORTRESS_SIZE
## Fuel a second standing still: 5% every 10 s.
const HOVER_BURN := 0.05 / 10.0
## It turns back at this much fuel, or when the way home costs RETURN_SHARE of the fuel it has.
const RETURN_FLOOR := 0.5
const RETURN_SHARE := 0.5
## A trip is only worth starting if it arrives this far above its own turning-back point.
const ARRIVAL_MARGIN := 0.1
## Seconds from empty to full (fuel and repairs), and the fuel it needs to leave the dock.
const RECHARGE_TIME := 18.0
const LAUNCH_FUEL := 0.95
## Below this it can't be sent on any sortie worth the name (it would be due home on arrival): it is recharging.
const MIN_SORTIE := RETURN_FLOOR + ARRIVAL_MARGIN + 0.05

const MAX_HP := 70.0
## How near a round has to pass its middle to hit (m).
const HIT_RADIUS := 1.1
const SPEED := 20.0
const ACCEL := 16.0
## Reach of its twin guns (m) and the two-round burst they fire: each round hits for DAMAGE.
const RANGE := 34.0
const DAMAGE := 0.9
const SHOT_INTERVAL := 0.65
const SPREAD := 0.05
## It touches down this close to its dock (m).
const LAND_REACH := 0.5
const SIGHT_EVERY := 0.25
const HOME_EVERY := 0.25

var team := GameConfig.TEAM_DEFENDER
var max_hp := MAX_HP
var hp := MAX_HP
var hit_radius := HIT_RADIUS
var target_radius := 0.0
var fuel := 1.0
var state := State.DOCKED
var bay: DroneBay = null
var swarm = null
## Its place in its swarm (0 to 4): which spot of the ring round the target is its own.
var index := 0
## The dock it sits on or is heading for (DroneBay); -1 while it is flying out.
var home_slot := -1
var goal := Vector3.ZERO
## Whom its guns are on.
var target: Node3D = null
var velocity := Vector3.ZERO
## Stepped by hand (tests) instead of by the engine.
var manual := false
## Totals (the autotest and the tests read them).
var shots := 0
var burnt := 0.0

var _rig: DroneRig
var _exclude: Array[RID] = []
var _shot_cd := 0.0
var _sight_cd := 0.0
var _has_line := false
var _home_cd := 0.0
var _home_pos := Vector3.ZERO
var _fog_cd := 0.0
var _falling := false
var _fall_t := 0.0


## Fuel the flight of `distance` metres takes.
static func trip_cost(distance: float) -> float:
	return distance * FUEL_PER_M


## True when a drone with `fuel` left, `home_distance` metres from its dock, has to turn for home.
static func must_return(fuel: float, home_distance: float) -> bool:
	return fuel <= RETURN_FLOOR or trip_cost(home_distance) >= fuel * RETURN_SHARE


## True when a drone with `fuel` can fly from `from` to `to` (which is `home_from_to` metres from a dock) and
## still be `margin` above its turning-back point there, i.e. the trip is worth making.
static func can_reach(fuel: float, from: Vector3, to: Vector3, home_from_to: float, margin := ARRIVAL_MARGIN) -> bool:
	var left := fuel - trip_cost(from.distance_to(to))
	return not must_return(left - margin, home_from_to)


func _ready() -> void:
	add_to_group("drones")
	_rig = DroneRig.new()
	# The model's front is +Z; the drone flies along its -Z.
	_rig.rotation.y = PI
	add_child(_rig)


func _physics_process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	if _falling:
		_fall(delta)
		return
	_fog(delta)
	if state == State.DOCKED:
		_charge(delta)
		return
	var moved := _move(delta)
	var use := maxf(moved * FUEL_PER_M, HOVER_BURN * delta)
	fuel = maxf(fuel - use, 0.0)
	burnt += use
	if fuel <= 0.0:
		# The turning-back rule leaves a margin, so this should never happen: out of fuel it drops.
		hp = 0.0
		_die()
		return
	_face(delta)
	if state == State.FLYING:
		_home_tick(delta)
		_sight_tick(delta)
		_fire_tick(delta)
	elif global_position.distance_to(dock_position()) <= LAND_REACH:
		_land()


# ---------------------------------------------------------------- state

func is_alive() -> bool:
	return hp > 0.0 and not _falling


func get_aim_point() -> Vector3:
	return global_position


func is_airborne() -> bool:
	return state != State.DOCKED and not _falling


## Sitting on its dock with a full enough tank and mended: ready to fly.
func is_ready() -> bool:
	return state == State.DOCKED and not _falling and fuel >= LAUNCH_FUEL and hp >= max_hp * 0.9


## Its guns have a clear line to its target in reach (as of the last check).
func has_line() -> bool:
	return _has_line


## Where it lands: its dock's spot, or the nearest dock's while it hasn't picked one.
func dock_position() -> Vector3:
	if bay != null and home_slot >= 0:
		return bay.dock_pos(home_slot)
	return _home_pos


## True when the way home from where it is already says turn back (the fuel rule, from its dock if docked).
func due_home() -> bool:
	return must_return(fuel, global_position.distance_to(dock_position()))


## Takes off for `to`. False unless it is ready. `early`: a call doesn't wait for it to fill up (95%): any mended
## drone on its dock goes, as long as the caller has priced the trip (can_reach), so a swarm that came home from a
## short sortie can be called again at once.
func launch(to: Vector3, early := false) -> bool:
	if not (is_ready() or (early and state == State.DOCKED and not _falling and hp >= max_hp * 0.5)):
		return false
	_home_pos = dock_position()
	if bay != null and home_slot >= 0:
		bay.release_dock(home_slot)
	home_slot = -1
	state = State.FLYING
	goal = to
	_home_cd = 0.0
	_set_airborne(true)
	return true


## A drone on its way home turns round for `to` instead, if it is not going home because it must (the fuel rule):
## a swarm that stood down finding nothing, called out again. False if it can't, or has to go on home.
func redirect(to: Vector3) -> bool:
	if state != State.RETURNING or _falling or due_home():
		return false
	if bay != null and home_slot >= 0:
		_home_pos = dock_position()
		bay.release_dock(home_slot)
	home_slot = -1
	state = State.FLYING
	goal = to
	_home_cd = 0.0
	return true


## Turns for the nearest free dock to recharge.
func return_home() -> void:
	if state != State.FLYING or _falling:
		return
	state = State.RETURNING
	target = null
	_has_line = false
	if bay != null:
		home_slot = bay.claim_dock(global_position, self)
	goal = dock_position()


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team or state == State.DOCKED or _falling:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_die()


func _land() -> void:
	state = State.DOCKED
	velocity = Vector3.ZERO
	global_position = dock_position()
	target = null
	_has_line = false
	_set_airborne(false)
	# Facing out from the fortress.
	rotation.y = atan2(-global_position.x, -global_position.z)


func _die() -> void:
	if _falling:
		return
	_falling = true
	remove_from_group("air_units")
	remove_from_group("drones")
	if bay != null and home_slot >= 0:
		bay.release_dock(home_slot)
	home_slot = -1
	target = null
	velocity = velocity * 0.6 + Vector3.UP * 2.0
	Combat.spawn_explosion(self, global_position, 2.5, true)
	died.emit(self)


func _fall(delta: float) -> void:
	_fall_t += delta
	velocity.y -= 9.8 * delta
	global_position += velocity * delta
	rotation += Vector3(1.5, 4.0, 2.2) * delta
	if global_position.y <= maxf(LevelBuilder.ground_height(global_position), 0.0) + 0.5 or _fall_t > 5.0:
		Combat.spawn_explosion(self, global_position, 3.5)
		queue_free()


## In "air_units" (what the attackers' anti-air looks for) only while it is in the air.
func _set_airborne(on: bool) -> void:
	if on and not is_in_group("air_units"):
		add_to_group("air_units")
	elif not on and is_in_group("air_units"):
		remove_from_group("air_units")


# ---------------------------------------------------------------- flying

## Flies at its goal (or its dock, going home), slowing to a stop on it. Returns the metres flown.
func _move(delta: float) -> float:
	if state == State.RETURNING:
		goal = dock_position()
	var to := goal - global_position
	var dist := to.length()
	var want := Vector3.ZERO
	if dist > 0.1:
		want = to / dist * minf(SPEED, sqrt(2.0 * ACCEL * dist))
	velocity = velocity.move_toward(want, ACCEL * delta)
	var move := velocity * delta
	if move.length() > dist:
		move = to
		velocity = Vector3.ZERO
	global_position += move
	return move.length()


func _face(delta: float) -> void:
	var look := Vector3.ZERO
	if Combat.is_valid_target(target):
		look = target.global_position - global_position
	elif velocity.length() > 1.0:
		look = velocity
	look.y = 0.0
	if look.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), minf(6.0 * delta, 1.0))


## Prices the way home from here every frame (against the nearest free dock, looked up a few times a second)
## and turns for it when the rule says so.
func _home_tick(delta: float) -> void:
	_home_cd -= delta
	if _home_cd <= 0.0:
		_home_cd = HOME_EVERY
		_home_pos = bay.nearest_free_dock_pos(global_position) if bay != null else Vector3.ZERO
	if must_return(fuel, global_position.distance_to(_home_pos)):
		return_home()


# ---------------------------------------------------------------- dock

func _charge(delta: float) -> void:
	fuel = minf(fuel + delta / RECHARGE_TIME, 1.0)
	hp = minf(hp + max_hp * delta / RECHARGE_TIME, max_hp)


## Where the attackers can't see it they don't see it (their fog of war), on their side of the screen.
func _fog(delta: float) -> void:
	_fog_cd -= delta
	if _fog_cd > 0.0:
		return
	_fog_cd = 0.2
	var vision := AttackerVision.instance
	if vision != null and vision.hide_enemies:
		visible = vision.in_sight(global_position)


# ---------------------------------------------------------------- guns

func _sight_tick(delta: float) -> void:
	_sight_cd -= delta
	if _sight_cd > 0.0:
		return
	_sight_cd = SIGHT_EVERY
	_has_line = false
	if Combat.is_valid_target(target):
		var aim := Combat.aim_point(target)
		_has_line = global_position.distance_to(aim) <= RANGE and Combat.has_line_of_sight(self, global_position, aim, target)


func _fire_tick(delta: float) -> void:
	_shot_cd -= delta
	if _shot_cd > 0.0 or not _has_line or not Combat.is_valid_target(target):
		return
	_shot_cd = SHOT_INTERVAL * randf_range(0.9, 1.15)
	shots += 1
	var aim := Combat.aim_point(target)
	for side in ["muzzle_L", "muzzle_R"]:
		var from := _muzzle(side)
		Combat.fire_hitscan(self, from, aim, SPREAD, DAMAGE, team, 1.0, _exclude)
		Combat.spawn_muzzle_flash(self, from, aim - from, 0.4)


func _muzzle(side: String) -> Vector3:
	if _rig != null and _rig.has_part(side):
		return _rig.marker(side).origin
	return global_position + global_basis * Vector3(0.35 if side == "muzzle_R" else -0.35, -0.2, -0.9)
