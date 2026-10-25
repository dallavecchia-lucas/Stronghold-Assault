class_name AATurret
extends StaticBody3D
## Autonomous anti-aircraft launcher on a roof mount (LevelBuilder.AA_TURRETS). Nobody crews it or
## takes it over: it turns to the nearest enemy aircraft it can see within RANGE, locks on
## (LOCK_TIME) and fires a homing missile at it every RELOAD while it keeps it. Sky Talons on a
## strafe run or a bomb strike are fair game. It can be destroyed (a bomb, a bison's shell or a
## strafe run that walks over it), and it is rebuilt REPAIR_TIME later.

const RANGE := 45.0
const LOCK_TIME := 1.2
const RELOAD := 3.0
const MISSILE_DAMAGE := 18.0
const TURN_RATE := 2.5
const REPAIR_TIME := 75.0
## Where its missiles leave from, above the mount.
const HEAD := 2.6

var station_name := "AA Turret"
var station_kind := "aa"
var team := GameConfig.TEAM_DEFENDER
var max_hp := 150.0
var hp := 150.0
var target_radius := 0.8
## The aircraft it is on, and missiles fired so far.
var target: Node3D = null
var fired := 0

var _yaw: Node3D
var _lock := 0.0
var _reload := 0.0
var _retarget := 0.0
var _repair := 0.0
var _smoke: CPUParticles3D


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
	_yaw = Node3D.new()
	add_child(_yaw)
	_yaw.add_child(Props.instance(Props.SENTINEL_SPIRE, 3.0))
	_smoke = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(0.12, 0.12, 0.12, 0.55)
	q.material = sm
	_smoke.mesh = q
	_smoke.amount = 14
	_smoke.lifetime = 3.0
	_smoke.direction = Vector3.UP
	_smoke.initial_velocity_min = 1.0
	_smoke.initial_velocity_max = 2.2
	_smoke.gravity = Vector3(0, 0.5, 0)
	_smoke.scale_amount_max = 2.5
	_smoke.emitting = false
	_smoke.position.y = 1.5
	add_child(_smoke)


func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.4


func get_approach_point() -> Vector3:
	return Combat.wall_approach(global_position)


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		target = null
		_repair = REPAIR_TIME
		_smoke.emitting = true
		_yaw.rotation.x = 0.35  # knocked askew
		Combat.spawn_explosion(self, global_position + Vector3.UP * 1.5, 3.0)


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		_repair -= delta
		if _repair <= 0.0:
			hp = max_hp
			_smoke.emitting = false
			_yaw.rotation.x = 0.0
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
		return
	var to := target.global_position - global_position
	_yaw.rotation.y = rotate_toward(_yaw.rotation.y, atan2(-to.x, -to.z), TURN_RATE * delta)
	_lock += delta
	if _lock >= LOCK_TIME and _reload <= 0.0:
		_fire()


func _fire() -> void:
	_reload = RELOAD
	fired += 1
	var head := global_position + Vector3.UP * HEAD
	var m := HomingMissile.new()
	m.team = team
	m.damage = MISSILE_DAMAGE
	m.size = 1.2
	get_tree().current_scene.add_child(m)
	m.launch(head, (target.global_position - head).normalized() + Vector3.UP * 0.6, target)
	SmokeCloud.wisp(self, head, 1.5)


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
