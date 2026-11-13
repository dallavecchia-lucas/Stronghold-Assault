class_name GarrisonSoldier
extends DefenderSoldier
## One soldier of the garrison (Garrison): the defenders' basic foot soldier, spawned deep inside the stronghold and
## run by the CPU only. The garrison hands it a job and it walks there on the navmesh: up the stair shafts to the gun
## decks (the climbing links' routes, like the infiltrating attackers'), through the gates (the door opens for it, as
## for the squads: Structure.hold_open) and out round the base. There it holds:
##   GUN    it sits in the gun's seat (MountedGun.crew_spot: the sentry gun's and the cannon's side seats, the mortar's
##          too), seated by its SeatRig with its rifle put away, turning with the gun; the gun fires, it doesn't.
##   DECK   it holds its spot on a gun deck, behind the parapet, and fights with its rifle.
##   FIELD  it holds its spot in the perimeter round the base and fights with its rifle.
## It fights like a Bear Rifleman (DefenderSoldier.AI_SIGHT / AI_RANGE): an attacker in reach on its way stops it
## until it is gone; then it walks on. It never moves on from its spot by itself: the garrison may send a deck
## soldier over to a gun whose crew fell. Dead, it is gone (the garrison's spawns make up the numbers).

signal died(soldier: GarrisonSoldier)

enum Job { NONE, GUN, DECK, FIELD }

## The spawned soldiers all carry the Shadowline (Idle and Running clips, the rifle on its `rifle` bone).
const MODEL := "res://assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel_armed.glb"
const RUN_SPEED := 4.5
## Along a climbing route: up or down a stair or a ladder, and along its flat parts.
const CLIMB_SPEED := 2.2
const ROUTE_SPEED := 3.2
const ACCEL := 14.0
const TURN_RATE := 8.0
## Ledges it steps up onto (m), and higher ones where the navmesh says the ground ahead is higher (SquadTrooper).
const STEP_HEIGHT := 0.45
const TALL_STEP := 0.75
## Seated in a gun: the soldier's feet origin this far under the seat pan's top (its hips 0.9 m up, sat on the pan), and
## this far back from the pan's middle toward the backrest.
const SEAT_DROP := 0.8
const SEAT_BACK := 0.1
## Within this (flat, m) of a standing gate it holds the door open.
const GATE_REACH := 5.0
## Within this of its spot (flat, m; and this high) it has arrived; the last bit it glides into the exact spot.
const ARRIVE := 0.7
const ARRIVE_HIGH := 1.6
## No headway for this long (s): a fresh path from where it stands.
const STUCK_TIME := 2.0
## A path ending further than this (m) from the spot: the spot can't be reached (across the river, say).
const UNREACHABLE := 2.5

var garrison: Node = null
var job := Job.NONE
## The gun it crews or walks to (MountedGun / ArtilleryStation).
var gun: Node3D = null
## Its deck or field slot (Garrison's index), -1: none.
var slot := -1
## Where it is going and which way it faces there.
var goal := Vector3.ZERO
var facing := Vector3.FORWARD
var arrived := false
## The spawn's side and priority it came out with, and when (Garrison.clock): the stats.
var spawn_side := ""
var priority := 0
var spawned_at := 0.0
var assigned_at := 0.0
var arrived_at := -1.0
## Targets its paths couldn't reach (Garrison keys: "gun<id>", "deck<i>", "field<i>"): never handed them again.
var avoid := {}

## Every garrison soldier's rounds so far, and the longest shot among them (m): the showcase checks nothing is sniped.
static var shots := 0
static var longest_shot := 0.0

var _agent: NavigationAgent3D
var _route: Array[Vector3] = []
var _gates: Array = []
var _want := Vector3.ZERO
var _check_reach := false
var _stuck_t := 0.0
var _stuck_at := Vector3.ZERO
var _fighting := false
var _seat_rig: SeatRig
var _rifle: Node3D


func _init() -> void:
	first_person = false
	model_path = MODEL
	station_name = "Garrison soldier"


func _ready() -> void:
	super._ready()
	add_to_group("garrison")
	# Garrison soldiers, squads and the guns don't block each other (the rounds pass through them too: Combat).
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS | GameConfig.LAYER_WATER_EDGE
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	_agent.height = 1.8
	_agent.max_speed = RUN_SPEED
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.path_height_offset = 0.4
	_agent.avoidance_enabled = false
	# The whole way, however many polygons it crosses: the agent's default search gives up after 4096 and hands back a
	# path that stops short (the stronghold's dense interior, out to the far side's roof).
	_agent.path_search_max_polygons = 0
	# The ground, the climbing links (stairs and ladders, and a fallen gate's breach) and the squads' links through the gates.
	_agent.navigation_layers = 1 | LevelBuilder.NAV_INFILTRATORS | LevelBuilder.NAV_SQUAD
	_agent.link_reached.connect(_on_link_reached)
	add_child(_agent)
	_stuck_at = global_position
	# Seated at a gun: the legs bent by the rig, the rifle (hung on the `rifle` bone, HeldGun) put away.
	var skels := _body.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_seat_rig = SeatRig.new()
		_seat_rig.active = false
		skels[0].add_child(_seat_rig)
	for a in _body.find_children("*", "BoneAttachment3D", true, false):
		if (a as BoneAttachment3D).bone_name == "rifle":
			_rifle = a


## Sends it to `to` (world), to face `face` there, for `new_job` (the garrison's call).
func send(new_job: Job, to: Vector3, face: Vector3, now: float) -> void:
	job = new_job
	goal = to
	facing = face
	arrived = false
	arrived_at = -1.0
	assigned_at = now
	# Halfway up a stair or a ladder it climbs on to the end first (the route), then makes for the new spot.
	_agent.target_position = to
	_check_reach = true
	_stuck_t = 0.0
	_stuck_at = global_position
	_body.visible = true
	_sit(false)


func is_walking() -> bool:
	return not arrived and job != Job.NONE


func _engage(delta: float) -> void:
	var cd := _fire_cd
	super._engage(delta)
	if _fire_cd > cd and Combat.is_valid_target(_target):
		shots += 1
		longest_shot = maxf(longest_shot, global_position.distance_to(_target.global_position))


# ---------------------------------------------------------------- damage

func _die() -> void:
	hp = 0.0
	_body.visible = false
	_shape.set_deferred("disabled", true)
	remove_from_group("damageable")
	remove_from_group("defender_targets")
	remove_from_group("garrison")
	Combat.spawn_impact(self, get_aim_point(), true)
	died.emit(self)
	queue_free()


## Never taken over by the player.
func can_possess() -> bool:
	return false


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	if _tossed:
		velocity.y -= _gravity * delta
		move_and_slide()
		_tossed = not (is_on_floor() and velocity.y <= 0.0)
		if not _tossed and not arrived:
			_agent.target_position = goal  # thrown off its way: a fresh path
		return
	if SerpentTrap.is_held(self):
		_was_held = true
		velocity = Vector3.ZERO
		var t := Time.get_ticks_msec() * 0.001
		_body.rotation = Vector3(sin(t * 7.3) * 0.03, 0.0, sin(t * 11.0) * 0.035)
		return
	if _was_held:
		_was_held = false
		_body.rotation = Vector3.ZERO
	_fire_cd -= delta
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			ammo = MAG_SIZE
	if not _route.is_empty():
		_follow_route(delta)
		return
	if job == Job.GUN and arrived:
		_crew(delta)
		return
	_open_gates()
	# An attacker in sight stops it where it stands (on its way too) until it is gone.
	_fighting = false
	if not FlashGrenade.is_blind(self):
		_retarget_cd -= delta
		if _retarget_cd <= 0.0:
			_retarget_cd = 0.4 + randf() * 0.2
			_target = _find_target()
		_fighting = Combat.is_valid_target(_target)
		# On its way it stops only for what it can hit; one it only sees, further off, it keeps an eye on as it goes.
		if _fighting and not arrived and global_position.distance_squared_to(_target.global_position) > AI_RANGE * AI_RANGE:
			_fighting = false
	if _fighting or arrived or job == Job.NONE:
		_hold(delta)
	else:
		_walk(delta)


## At its gun: sat in the gun's seat (or, a gun with none, stood behind it), turned with the gun; the gun does the
## shooting.
func _crew(_delta: float) -> void:
	velocity = Vector3.ZERO
	if not is_instance_valid(gun):
		return
	var spot: Transform3D = gun.crew_spot()
	if gun.has_method("has_seat") and gun.has_seat():
		_sit(true)
		global_transform = Transform3D(spot.basis, spot.origin + spot.basis.z * SEAT_BACK - Vector3.UP * SEAT_DROP)
	else:
		global_transform = spot
	# Taken over, the player's view sits on the machine gun: the crew is out of it.
	_body.visible = not (gun.possessed and gun.station_kind == "mg")


## Seated (the SeatRig bends it into the seat, the rifle put away) or on its feet.
func _sit(on: bool) -> void:
	if _seat_rig:
		_seat_rig.active = on
	if _rifle:
		_rifle.visible = not on


## On its spot (or stopped to fight): it fights like a post (DefenderSoldier._ai_update), and otherwise turns to face out.
func _hold(delta: float) -> void:
	if arrived and not _fighting:
		var to := goal - global_position
		to.y = 0.0
		if to.length() > 0.05:
			# The last few tens of centimetres into the exact spot.
			global_position += to.limit_length(RUN_SPEED * 0.5 * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), minf(delta * 4.0, 1.0))
	velocity.x = move_toward(velocity.x, 0.0, delta * 20.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 20.0)
	if _fighting:
		_engage(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
		move_and_slide()
	elif velocity.length_squared() > 0.01:
		move_and_slide()


func _walk(delta: float) -> void:
	var next := _agent.get_next_path_position()
	if not _route.is_empty():
		return  # just reached a climbing link (_on_link_reached)
	if _check_reach:
		_check_reach = false
		var end := _agent.get_final_position()
		if end.distance_to(goal) > UNREACHABLE:
			if garrison:
				garrison.unreachable(self)
			return
	var to_goal := goal - global_position
	if Vector2(to_goal.x, to_goal.z).length() < ARRIVE and absf(to_goal.y) < ARRIVE_HIGH:
		_arrive()
		return
	var to := next - global_position
	to.y = 0.0
	_want = to.normalized() * RUN_SPEED if to.length() > 0.05 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(_want, ACCEL * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	if is_on_wall() and _want.length() > 0.5:
		if _step_up(_want.normalized() * 0.3):
			velocity.x = flat.x
			velocity.z = flat.z
	if flat.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(TURN_RATE * delta, 1.0))
	# Caught on something: a fresh path from where it stands.
	_stuck_t += delta
	if _stuck_t >= STUCK_TIME:
		if global_position.distance_to(_stuck_at) < RUN_SPEED * STUCK_TIME * 0.15:
			_agent.target_position = goal + Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05))
		_stuck_t = 0.0
		_stuck_at = global_position


func _arrive() -> void:
	arrived = true
	velocity = Vector3(0.0, velocity.y, 0.0)
	if garrison:
		garrison.arrived(self)


## move_and_slide stops dead at a ledge (the step between the stronghold's halls and ramps): step up onto it if it is
## low enough and there is room (SquadTrooper._step_up).
func _step_up(motion: Vector3) -> bool:
	for h: float in [STEP_HEIGHT, TALL_STEP]:
		var up: Vector3 = Vector3.UP * h
		if test_move(global_transform, up) or test_move(global_transform.translated(up), motion):
			continue
		if h > STEP_HEIGHT:
			var map := get_world_3d().navigation_map
			var here := LevelBuilder.nav_closest(map, global_position + Vector3.UP * 0.5)
			var at := global_position + motion * 1.5 + up
			var there := LevelBuilder.nav_closest(map, at)
			if Vector2(there.x - at.x, there.z - at.z).length() > 0.35 or there.y < here.y + 0.2:
				return false
		global_position += up + motion
		apply_floor_snap()
		return true
	return false


func _open_gates() -> void:
	if _gates.is_empty() and garrison:
		_gates = garrison.gates()
	for g in _gates:
		if not is_instance_valid(g) or not g.is_alive():
			continue
		var d: Vector3 = g.global_position - global_position
		if Vector2(d.x, d.z).length() < GATE_REACH:
			g.hold_open()


## A climbing link (a stair shaft, a ladder, a fallen gate's breach): its route, walked straight through.
func _on_link_reached(details: Dictionary) -> void:
	var link := details.get("owner") as NavigationLink3D
	if link == null or not link.has_meta("route") or not _route.is_empty():
		return
	var route: Array[Vector3] = link.get_meta("route").duplicate()
	var entry: Vector3 = details.link_entry_position
	if entry.distance_to(route[0]) > entry.distance_to(route[-1]):
		route.reverse()
	_route = route


## Moves straight from point to point, through the stair steps and ladder rungs: no collisions.
func _follow_route(delta: float) -> void:
	var next := _route[0]
	var to := next - global_position
	var climbing := absf(to.y) > Vector2(to.x, to.z).length()
	var step := (CLIMB_SPEED if climbing else ROUTE_SPEED) * delta
	if to.length() <= step:
		_route.pop_front()
		global_position = next
		if _route.is_empty():
			velocity = Vector3.ZERO
		return
	velocity = to.normalized() * (CLIMB_SPEED if climbing else ROUTE_SPEED)
	global_position += velocity * delta
	if not climbing:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(10.0 * delta, 1.0))
