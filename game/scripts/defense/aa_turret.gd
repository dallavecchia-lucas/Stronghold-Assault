class_name AATurret
extends StaticBody3D
## Autonomous anti-aircraft launcher on a roof mount (the Sentinel Spire, LevelBuilder._build_mounts). Nobody crews it or
## takes it over: it turns to the nearest enemy aircraft it can see within RANGE, locks on
## (LOCK_TIME) and fires a homing missile at it every RELOAD while it keeps it. Sky Talons on a
## strafe run or a bomb strike are fair game. It can be destroyed (a bomb, a bison's shell or a
## strafe run that walks over it), and it is rebuilt REPAIR_TIME later.
##
## Its model is shown by a SpireRig: the arms turn on the base ring and the missile pod elevates between them, both
## laid by servos (TurretRig.slew). With nothing in the sky it searches: it turns steadily round with its pod at
## SEARCH_PITCH. On an aircraft it swings onto it and lays the pod LOFT above it, and each missile leaves from one of
## the pod's four cells, along the pod, with the cell's flash and the back blast out of the vent behind
## (SpireRig.launch). Knocked out, the arms are left askew and the pod drops.

const RANGE := 45.0
const LOCK_TIME := 1.2
const RELOAD := 3.0
const MISSILE_DAMAGE := 18.0
const TURN_RATE := 2.5
const REPAIR_TIME := 360.0  # 6 minutes
## Where it looks from, above the mount.
const HEAD := 2.6
## How tall its model stands (m), and where the pod's trunnion is above the mount.
const HEIGHT := 3.0
const TRUNNION := 1.57
## The laying servos (rad/s²), and the pod's elevation rate (rad/s).
const TURN_ACCEL := 9.0
const ELEVATE_RATE := 1.6
## Searching: how fast it turns round (rad/s) and where it holds its pod (rad).
const SEARCH_RATE := 0.5
const SEARCH_PITCH := deg_to_rad(28.0)
## On a target: the pod is laid this far above it (rad; the missile climbs out and turns in), and within this of it in
## traverse the missile may go (rad).
const LOFT := deg_to_rad(14.0)
const ON_TARGET := deg_to_rad(16.0)

var station_name := "AA Turret"
var station_kind := "aa"
var team := GameConfig.TEAM_DEFENDER
var max_hp := 150.0
var hp := 150.0
var target_radius := 0.8
## The aircraft it is on, and missiles fired so far.
var target: Node3D = null
var fired := 0

var _rig: SpireRig
## The aim: the traverse and the pod's elevation (rad), with the servos' rates.
var _yaw := 0.0
var _yaw_rate := 0.0
var _pitch := SEARCH_PITCH
var _pitch_rate := 0.0
var _lock := 0.0
var _reload := 0.0
var _retarget := 0.0
var _repair := 0.0
var _smoke: WreckSmoke


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.8, 1.8)
	shape.shape = box
	shape.position.y = 1.4
	add_child(shape)
	_yaw = randf_range(-PI, PI)
	_rig = TurretRig.create(Props.SENTINEL_SPIRE, HEIGHT) as SpireRig
	_rig.set_aim(_yaw, _pitch)
	add_child(_rig)
	# Knocked out, it smokes and smoulders until it is repaired.
	_smoke = WreckSmoke.new()
	_smoke.position.y = 1.5
	add_child(_smoke)


func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.4


func get_approach_point() -> Vector3:
	return Combat.wall_approach(global_position)


## The model's rig: for whoever wants to watch its parts.
func rig() -> TurretRig:
	return _rig


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		target = null
		_repair = REPAIR_TIME
		_smoke.emitting = true
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_rig.wrecked = true  # knocked askew, the pod dropped
		Combat.spawn_explosion(self, global_position + Vector3.UP * 1.5, 3.0)


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		_repair -= delta
		if _repair <= 0.0:
			hp = max_hp
			_smoke.emitting = false
			_rig.wrecked = false
		return
	_reload -= delta
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.3
		var t := _find()
		if t != target:
			target = t
			_lock = 0.0
	if not Combat.is_valid_target(target):
		target = null
		_lock = 0.0
		# Searching: it turns steadily round, its pod held ready.
		_yaw_rate = move_toward(_yaw_rate, SEARCH_RATE, TURN_ACCEL * 0.3 * delta)
		_yaw = wrapf(_yaw + _yaw_rate * delta, -PI, PI)
		_elevate(SEARCH_PITCH, delta)
		_rig.set_aim(_yaw, _pitch)
		return
	# Onto the aircraft: the arms swing round the short way, the pod is laid above it.
	var local := to_local(Combat.aim_point(target)) - Vector3.UP * TRUNNION
	var bearing := atan2(-local.x, -local.z)
	var y := TurretRig.slew(_yaw, _yaw_rate, _yaw + wrapf(bearing - _yaw, -PI, PI), TURN_RATE, TURN_ACCEL, delta)
	_yaw = wrapf(y.x, -PI, PI)
	_yaw_rate = y.y
	_elevate(atan2(local.y, Vector2(local.x, local.z).length()) + LOFT, delta)
	_rig.set_aim(_yaw, _pitch)
	_lock += delta
	# It fires once locked and swung onto it (and anyway a moment later: the missile turns in by itself).
	var on := absf(wrapf(bearing - _yaw, -PI, PI)) < ON_TARGET
	if _reload <= 0.0 and ((_lock >= LOCK_TIME and on) or _lock >= LOCK_TIME + 0.8):
		_fire()


## Lays the pod toward `to` (rad), as far as it goes.
func _elevate(to: float, delta: float) -> void:
	var p := TurretRig.slew(_pitch, _pitch_rate, clampf(to, _rig.min_pitch(_yaw), _rig.max_pitch()), ELEVATE_RATE, TURN_ACCEL, delta)
	_pitch = p.x
	_pitch_rate = p.y


func _fire() -> void:
	_reload = RELOAD
	fired += 1
	# The next loaded cell's missile: out of its mouth along the pod, then it turns in on the aircraft.
	var cell := _rig.launch()
	var m := HomingMissile.new()
	m.team = team
	m.damage = MISSILE_DAMAGE
	m.size = 1.2
	get_tree().current_scene.add_child(m)
	m.launch(cell.origin + cell.basis.z * 0.35, cell.basis.z, target)


## The nearest enemy aircraft within RANGE it can see.
func _find() -> Node3D:
	var head := global_position + Vector3.UP * HEAD
	var best: Node3D = null
	var best_d := RANGE
	for a in get_tree().get_nodes_in_group("air_units"):
		if a.team == team or not a.is_alive():
			continue
		var d := head.distance_to(Combat.aim_point(a))
		if d < best_d and Combat.has_line_of_sight(self, head, Combat.aim_point(a), a):
			best_d = d
			best = a
	return best
