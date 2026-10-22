class_name MissileTrooper
extends SquadTrooper
## One trooper of an AA Squad (AASquad): the Armored Sentinel with a six-missile pod on its left
## shoulder. Walks and aims like every squad trooper (SquadTrooper); the squad tells it what to
## launch: a seeking missile at an aircraft (launch_missile) or a rocket onto a spot on the ground
## (launch_rocket), and where to throw mines (throw_mine). Each missile or rocket leaves a tube
## empty; the tubes reload one at a time. MissileRig swings the pod onto what it launches at and
## hides the missiles that have left.
##
## The rigged model's clips come from tools/blender/rig_missile_trooper.py.

const MODEL := "res://assets/defenders/armored_sentinel/missile_trooper_rigged.glb"
const MAX_HP := 300.0
const TUBES := MissileRig.TUBES
## Seconds to reload one tube; the pod refills one tube at a time.
const RELOAD_TIME := 2.5
## The spine takes this share of the aim's pitch (the pod tilts for the rest), within these limits.
const SPINE_PITCH := 0.3
const SPINE_PITCH_MIN := deg_to_rad(-10.0)
const SPINE_PITCH_MAX := deg_to_rad(16.0)
## The pod's missiles: smaller than the elephant's. Rockets fly slower and turn lazily at first, so
## they climb before they dive onto their spot.
const MISSILE_SIZE := 0.55
const ROCKET_SPEED := 46.0
const ROCKET_TURN := 0.75
## A mine leaves the hand this far into the throw (s).
const RELEASE := 0.3

## World point the pod points at; INF: wherever the trooper aims.
var pod_target := Vector3.INF

var _full: Array[bool] = []
var _next_tube := 0
var _reload_t := 0.0
## Throws to make: [{"at": seconds from now, "spot": Vector3, "squad": AASquad}], soonest first.
var _throws: Array = []


func _init() -> void:
	max_hp = MAX_HP
	hp = MAX_HP
	for k in TUBES:
		_full.append(true)


func _model_path() -> String:
	return MODEL


func _new_rig() -> TrooperRig:
	return MissileRig.new()


func _spine_pitch(pitch: float) -> float:
	return clampf(pitch * SPINE_PITCH, SPINE_PITCH_MIN, SPINE_PITCH_MAX)


func _weapon_down() -> void:
	_throws.clear()


## Tubes holding a missile.
func loaded() -> int:
	return _full.count(true)


## Launches a seeking missile at `target` from the next loaded tube; `on_spent` is called once it
## has hit or missed. False if the pod is empty.
func launch_missile(target: Node3D, damage: float, on_spent: Callable) -> bool:
	var k := _take_tube()
	if k < 0:
		return false
	var tube := (_rig as MissileRig).tube(k)
	var m := HomingMissile.new()
	m.team = team
	m.damage = damage
	m.size = MISSILE_SIZE
	m.on_spent = on_spent
	get_tree().current_scene.add_child(m)
	m.launch(tube.origin, tube.basis.y, target)
	_launched(tube.origin)
	return true


## Launches a rocket that dives onto `point` and bursts there (`damage` within `splash`). False if
## the pod is empty.
func launch_rocket(point: Vector3, damage: float, splash: float) -> bool:
	var k := _take_tube()
	if k < 0:
		return false
	var tube := (_rig as MissileRig).tube(k)
	var m := HomingMissile.new()
	m.team = team
	m.damage = damage
	m.splash = splash
	m.size = MISSILE_SIZE
	m.top_speed = ROCKET_SPEED
	m.turn_scale = ROCKET_TURN
	get_tree().current_scene.add_child(m)
	m.launch_at(tube.origin, tube.basis.y, point)
	_launched(tube.origin)
	return true


## Throws a mine onto `spot` `delay` seconds from now (an underhand lob); it joins `squad`'s mines.
func throw_mine(spot: Vector3, delay: float, squad_node: Node) -> void:
	_throws.append({"at": delay, "spot": spot, "squad": squad_node, "swung": false})
	_throws.sort_custom(func(a, b): return a.at < b.at)


func _take_tube() -> int:
	for i in TUBES:
		var k := (_next_tube + i) % TUBES
		if _full[k]:
			_full[k] = false
			_next_tube = (k + 1) % TUBES
			return k
	return -1


func _launched(from: Vector3) -> void:
	(_rig as MissileRig).kick()
	SmokeCloud.wisp(self, from, 0.9)
	Combat.spawn_impact(self, from, true)
	if _reload_t <= 0.0:
		_reload_t = RELOAD_TIME


func _weapon_tick(delta: float) -> void:
	var rig := _rig as MissileRig
	rig.target = pod_target if pod_target != Vector3.INF else aim_point
	rig.full = _full
	if loaded() < TUBES:
		_reload_t -= delta
		if _reload_t <= 0.0:
			# The tube that has been empty longest first.
			for i in TUBES:
				var k := (_next_tube + i) % TUBES
				if not _full[k]:
					_full[k] = true
					break
			_reload_t = RELOAD_TIME if loaded() < TUBES else 0.0
	for th in _throws:
		th.at -= delta
		if not th.swung and th.at <= RELEASE:
			th.swung = true
			rig.throw()
	while not _throws.is_empty() and _throws[0].at <= 0.0:
		var th: Dictionary = _throws.pop_front()
		var mine := GroundMine.new()
		mine.team = team
		var squad_node: Node = th.squad
		get_tree().current_scene.add_child(mine)
		mine.throw(_hand(), th.spot)
		if is_instance_valid(squad_node) and squad_node.has_method("add_mine"):
			squad_node.add_mine(mine)


## Where a thrown mine leaves the trooper: by its right hip, a little ahead.
func _hand() -> Vector3:
	return global_transform * Vector3(0.55, 1.0, -0.45)
