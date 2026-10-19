class_name MountedGun
extends StaticBody3D
## Heavy machine gun emplacement on the walls. Faces its node's -Z axis at rest.
## Crew-operated by AI unless the defending player takes it over.

signal became_unavailable(station)

const YAW_LIMIT := deg_to_rad(75.0)
const PITCH_MIN := deg_to_rad(-40.0)
const PITCH_MAX := deg_to_rad(50.0)  # high enough to shoot down flyers
const PLAYER_DAMAGE := 17.0
const PLAYER_FIRE_INTERVAL := 0.075
const AI_DAMAGE := 8.0
const AI_FIRE_INTERVAL := 0.16
const AI_RANGE := 60.0
const HEAT_PER_SHOT := 0.032
const REPAIR_TIME := 25.0

## Turret model shown while the AI crews the gun (empty = sandbags + gunner capsule).
## The player always sees the simple first-person gun instead, so the model never blocks the view.
var model_path := ""
var station_name := "Machine Gun"
var station_kind := "mg"
var team := GameConfig.TEAM_DEFENDER
var max_hp := 300.0
var hp := 300.0
var target_radius := 0.5
var possessed := false
var heat := 0.0
var overheated := false

var _yaw := 0.0
var _pitch := 0.0
var _fire_cd := 0.0
var _retarget_cd := 0.0
var _repair_cd := 0.0
var _target: Node3D
var _shake := 0.0

var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D
var _muzzle: Node3D
var _gunner: Node3D
var _viewmodel: Node3D
var _turret: Node3D
var _smoke: CPUParticles3D


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.6, 1.4)
	shape.shape = box
	shape.position.y = 0.8
	add_child(shape)

	var metal := Mats.flat(Color(0.16, 0.17, 0.18), 0.8, 0.35)
	if model_path == "":
		var sand := Mats.flat(Color(0.55, 0.5, 0.38), 0.0, 1.0)
		# Sandbag horseshoe in front of the gun.
		for i in 5:
			var a := lerpf(-1.1, 1.1, i / 4.0)
			var bag := Mats.box_mesh(Vector3(0.9, 0.45, 0.45), Vector3(sin(a) * 1.1, 0.22, -cos(a) * 1.1), sand)
			bag.rotation.y = -a
			add_child(bag)
		add_child(Mats.cylinder_mesh(0.08, 1.1, Vector3(0, 0.55, 0), metal, 8))

	_yaw_pivot = Node3D.new()
	_yaw_pivot.position.y = 1.15
	add_child(_yaw_pivot)
	_pitch_pivot = Node3D.new()
	_yaw_pivot.add_child(_pitch_pivot)
	_viewmodel = Node3D.new()
	_pitch_pivot.add_child(_viewmodel)
	_viewmodel.add_child(Mats.box_mesh(Vector3(0.18, 0.2, 0.7), Vector3(0, 0, 0.05), metal))
	var barrel := Mats.cylinder_mesh(0.05, 1.1, Vector3(0, 0.02, -0.85), metal, 8)
	barrel.rotation.x = PI * 0.5
	_viewmodel.add_child(barrel)
	_viewmodel.add_child(Mats.box_mesh(Vector3(0.05, 0.12, 0.05), Vector3(0, 0.15, -0.6), metal))  # front sight
	for x in [-0.12, 0.12]:
		_viewmodel.add_child(Mats.box_mesh(Vector3(0.04, 0.14, 0.04), Vector3(x, -0.05, 0.45), metal))  # grips
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -1.42)
	_pitch_pivot.add_child(_muzzle)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0.42, 1.25)
	_camera.near = 0.05
	_camera.fov = 70.0
	_camera.far = 800.0
	_pitch_pivot.add_child(_camera)

	_gunner = Node3D.new()
	_gunner.position = Vector3(0, 0, 0.9)
	_yaw_pivot.add_child(_gunner)
	if model_path == "":
		var gm := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.4
		gm.mesh = cm
		gm.material_override = Mats.flat(Color(0.18, 0.28, 0.5), 0.1, 0.8)
		gm.position.y = -0.45
		_gunner.add_child(gm)
	else:
		# The turret swivels with the yaw pivot; its base sits on the walkway.
		_turret = Props.instance(model_path, 2.0)
		_turret.position.y = -_yaw_pivot.position.y
		_yaw_pivot.add_child(_turret)
		_viewmodel.visible = false

	_smoke = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(0.15, 0.15, 0.15, 0.5)
	q.material = sm
	_smoke.mesh = q
	_smoke.amount = 12
	_smoke.lifetime = 2.5
	_smoke.direction = Vector3.UP
	_smoke.initial_velocity_min = 1.0
	_smoke.initial_velocity_max = 2.0
	_smoke.gravity = Vector3(0, 0.5, 0)
	_smoke.scale_amount_max = 2.0
	_smoke.emitting = false
	_smoke.position.y = 1.0
	add_child(_smoke)


# ---------------------------------------------------------------- station interface

func can_possess() -> bool:
	return hp > 0.0


func possess() -> void:
	possessed = true
	_camera.current = true
	_gunner.visible = false
	_show_turret(false)


func unpossess() -> void:
	possessed = false
	_camera.current = false
	_camera.fov = 70.0
	_gunner.visible = hp > 0.0
	_show_turret(true)


func _show_turret(show: bool) -> void:
	if _turret:
		_turret.visible = show
		_viewmodel.visible = not show


func wants_captured_mouse() -> bool:
	return true


func get_station_position() -> Vector3:
	return global_position


func get_camera() -> Camera3D:
	return _camera


func get_hud_info() -> Dictionary:
	var status := "OVERHEATED" if overheated else "HEAT %d%%" % int(heat * 100.0)
	return {"weapon": "Heavy MG", "status": status, "heat": heat, "hp": hp / max_hp,
			"hint": "Mouse aim · LMB fire · RMB zoom · watch the heat"}


# ---------------------------------------------------------------- damage

func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if possessed:
		_shake = 0.3
	if hp <= 0.0:
		hp = 0.0
		_repair_cd = REPAIR_TIME
		_gunner.visible = false
		_smoke.emitting = true
		Combat.spawn_explosion(self, global_position + Vector3.UP, 2.0)
		became_unavailable.emit(self)


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		_repair_cd -= delta
		if _repair_cd <= 0.0:
			hp = max_hp
			heat = 0.0
			overheated = false
			_smoke.emitting = false
			_gunner.visible = not possessed
		return
	_fire_cd -= delta
	var firing := false
	if possessed:
		var zoom := Input.is_action_pressed("aim")
		_camera.fov = lerpf(_camera.fov, 40.0 if zoom else 70.0, delta * 10.0)
		if Input.is_action_pressed("fire"):
			firing = _try_fire(true)
	else:
		firing = _ai_update(delta)
	heat = maxf(heat - delta * (0.22 if firing else 0.4), 0.0)
	if overheated and heat < 0.35:
		overheated = false
	_shake = maxf(_shake - delta, 0.0)
	_camera.h_offset = randf_range(-1, 1) * _shake * 0.05
	_camera.v_offset = randf_range(-1, 1) * _shake * 0.05
	_apply_aim()


func _unhandled_input(event: InputEvent) -> void:
	if not possessed or hp <= 0.0 or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameConfig.mouse_sensitivity * 0.8 * (_camera.fov / 70.0)
		_yaw = clampf(_yaw - event.relative.x * sens, -YAW_LIMIT, YAW_LIMIT)
		_pitch = clampf(_pitch - event.relative.y * sens, PITCH_MIN, PITCH_MAX)


func _apply_aim() -> void:
	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch


func _try_fire(player: bool) -> bool:
	if overheated or _fire_cd > 0.0:
		return false
	_fire_cd = PLAYER_FIRE_INTERVAL if player else AI_FIRE_INTERVAL
	heat += HEAT_PER_SHOT
	if heat >= 1.0:
		overheated = true
	var muzzle := _muzzle.global_position
	if player:
		var from := _camera.global_position
		Combat.fire_hitscan(self, from, from - _camera.global_basis.z * 100.0, 0.012, PLAYER_DAMAGE, team, 0.3, [get_rid()], muzzle)
		Combat.spawn_muzzle_light(self, muzzle)
		_shake = maxf(_shake, 0.12)
	else:
		Combat.fire_hitscan(self, muzzle, muzzle - _pitch_pivot.global_basis.z * 100.0, 0.035, AI_DAMAGE, team, 0.3, [get_rid()])
	return true


## AI crew: track the nearest attacker in the firing arc and shoot in bursts.
func _ai_update(delta: float) -> bool:
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.4
		_target = _find_target()
	if not Combat.is_valid_target(_target):
		return false
	var ang := _angles_to(Combat.aim_point(_target))
	_yaw = move_toward(_yaw, clampf(ang.x, -YAW_LIMIT, YAW_LIMIT), delta * 1.8)
	_pitch = move_toward(_pitch, clampf(ang.y, PITCH_MIN, PITCH_MAX), delta * 1.8)
	if absf(ang.x - _yaw) < 0.06 and absf(ang.y - _pitch) < 0.06 and heat < 0.8:
		return _try_fire(false)
	return false


## Returns (yaw, pitch) needed to point the barrel at a world position.
func _angles_to(point: Vector3) -> Vector2:
	var local := to_local(point) - _yaw_pivot.position
	var yaw := atan2(-local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	return Vector2(yaw, pitch)


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := AI_RANGE
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var d := global_position.distance_to(u.global_position)
		if d >= best_d:
			continue
		var ang := _angles_to(Combat.aim_point(u))
		if absf(ang.x) > YAW_LIMIT or ang.y < PITCH_MIN or ang.y > PITCH_MAX:
			continue
		if Combat.has_line_of_sight(self, _muzzle.global_position, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best
