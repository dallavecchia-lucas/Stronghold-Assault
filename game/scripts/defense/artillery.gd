class_name ArtilleryStation
extends StaticBody3D
## Courtyard mortar. When possessed the player gets a spotter view over the battlefield,
## moves it with WASD and clicks on the ground to call in shells.

signal became_unavailable(station)

const RELOAD_TIME := 3.5
const AI_RELOAD_TIME := 8.0
const MIN_RANGE := 20.0
const MAX_RANGE := 150.0
const SHELL_DAMAGE := 150.0
const SHELL_RADIUS := 7.0
const AI_ERROR := 5.0
const REPAIR_TIME := 30.0

## Where the spotter view starts (and returns to), looking away from the map center.
var spotter_home := Vector3(0, 0, 45)
var station_name := "Artillery"
var station_kind := "artillery"
var team := GameConfig.TEAM_DEFENDER
var max_hp := 400.0
var hp := 400.0
var target_radius := 1.0
var possessed := false
var map_half := 120.0

var _reload := 0.0
var _repair_cd := 0.0
var _barrel_pivot: Node3D
var _muzzle: Node3D
var _spotter: Node3D
var _camera: Camera3D
var _spot_zoom := 70.0
var _reticle: MeshInstance3D
var _aim_point := Vector3.ZERO
var _aim_valid := false


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.6, 2.6)
	shape.shape = box
	shape.position.y = 0.8
	add_child(shape)

	add_child(Mats.cylinder_mesh(1.9, 0.35, Vector3(0, 0.17, 0), Mats.dark_stone(), 16))
	_barrel_pivot = Node3D.new()
	_barrel_pivot.position.y = 0.7
	add_child(_barrel_pivot)
	# The whole cannon turns toward the target; shells still leave from the muzzle below.
	var cannon := Props.instance(Props.ARCTIC_SENTINEL_CANNON, 1.9)
	cannon.position.y = 0.35 - _barrel_pivot.position.y
	_barrel_pivot.add_child(cannon)
	var tilt := Node3D.new()
	tilt.rotation.x = deg_to_rad(50.0)
	_barrel_pivot.add_child(tilt)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 2.2, 0)
	tilt.add_child(_muzzle)

	# Spotter camera rig lives at the top level so it can roam the map.
	_spotter = Node3D.new()
	_spotter.top_level = true
	add_child(_spotter)
	_camera = Camera3D.new()
	_camera.far = 900.0
	_camera.fov = 60.0
	_spotter.add_child(_camera)
	_reset_spotter()

	_reticle = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = SHELL_RADIUS - 0.4
	t.outer_radius = SHELL_RADIUS
	t.rings = 48
	t.ring_segments = 4
	_reticle.mesh = t
	_reticle.scale.y = 0.1
	_reticle.top_level = true
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.visible = false
	add_child(_reticle)


func _reset_spotter() -> void:
	# Look out over the approach in front of the station by default.
	_spotter.global_position = spotter_home
	_spotter.rotation.y = PI
	_apply_spotter()


func _apply_spotter() -> void:
	_camera.position = Vector3(0, _spot_zoom * 0.85, _spot_zoom * 0.55)
	_camera.rotation = Vector3(-deg_to_rad(57.0), 0, 0)


# ---------------------------------------------------------------- station interface

func can_possess() -> bool:
	return hp > 0.0


func possess() -> void:
	possessed = true
	_camera.current = true
	_reticle.visible = true


func unpossess() -> void:
	possessed = false
	_camera.current = false
	_reticle.visible = false


func wants_captured_mouse() -> bool:
	return false


func get_station_position() -> Vector3:
	return global_position


func get_camera() -> Camera3D:
	return _camera


func get_hud_info() -> Dictionary:
	var status := "READY" if _reload <= 0.0 else "RELOADING %.1fs" % _reload
	if possessed and not _aim_valid:
		status += "  ·  OUT OF RANGE"
	return {"weapon": "Mortar", "status": status, "hp": hp / max_hp,
			"hint": "WASD move view · Q/E rotate · Wheel zoom · LMB fire on target (range %d-%d m)" % [MIN_RANGE, MAX_RANGE]}


# ---------------------------------------------------------------- damage

func is_alive() -> bool:
	return hp > 0.0


func get_approach_point() -> Vector3:
	return Combat.wall_approach(global_position)


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_repair_cd = REPAIR_TIME
		Combat.spawn_explosion(self, global_position + Vector3.UP, 3.0)
		became_unavailable.emit(self)


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		_repair_cd -= delta
		if _repair_cd <= 0.0:
			hp = max_hp
		return
	_reload -= delta
	if possessed:
		_player_update(delta)
	elif _reload <= 0.0 and not FlashGrenade.is_blind(self):
		_ai_fire()


func _unhandled_input(event: InputEvent) -> void:
	if not possessed or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_spot_zoom = maxf(_spot_zoom - 6.0, 25.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_spot_zoom = minf(_spot_zoom + 6.0, 140.0)
		elif event.button_index == MOUSE_BUTTON_LEFT and hp > 0.0:
			_player_fire()
		_apply_spotter()


func _player_update(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var turn := Input.get_axis("cam_rotate_right", "cam_rotate_left")
	_spotter.rotation.y += turn * delta * 1.6
	var p := _spotter.global_position + _spotter.global_basis * Vector3(input.x, 0, input.y) * delta * (20.0 + _spot_zoom * 0.6)
	p.x = clampf(p.x, -map_half, map_half)
	p.z = clampf(p.z, -map_half, map_half)
	_spotter.global_position = p

	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var to := from + _camera.project_ray_normal(mouse) * 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	_aim_point = hit.position
	var dist := Vector2(_aim_point.x - global_position.x, _aim_point.z - global_position.z).length()
	_aim_valid = dist >= MIN_RANGE and dist <= MAX_RANGE
	_reticle.global_position = _aim_point + Vector3.UP * 0.15
	var col := Color(0.3, 1.0, 0.4) if _aim_valid and _reload <= 0.0 else (Color(1.0, 0.8, 0.2) if _aim_valid else Color(1.0, 0.25, 0.2))
	_reticle.material_override = Mats.unshaded(col, true)
	_aim_barrel(_aim_point, delta)


func _aim_barrel(point: Vector3, delta: float) -> void:
	var d := point - global_position
	_barrel_pivot.rotation.y = lerp_angle(_barrel_pivot.rotation.y, atan2(-d.x, -d.z), delta * 4.0)


func _player_fire() -> void:
	if _reload > 0.0 or not _aim_valid:
		return
	_launch(_aim_point, RELOAD_TIME)


func _launch(point: Vector3, reload: float) -> void:
	_reload = reload
	var d := point - global_position
	_barrel_pivot.rotation.y = atan2(-d.x, -d.z)
	var shell := Shell.new()
	shell.team = team
	shell.damage = SHELL_DAMAGE
	shell.radius = SHELL_RADIUS
	get_tree().current_scene.add_child(shell)
	shell.launch(_muzzle.global_position, point)
	Combat.spawn_explosion(self, _muzzle.global_position, 0.8)


## AI: drop a shell on the densest group of attackers in range.
func _ai_fire() -> void:
	var units := get_tree().get_nodes_in_group("attacker_units")
	var best: Node3D = null
	var best_n := 2  # don't waste shells on lone units
	for u in units:
		if u.is_flying():
			continue
		var dist := Vector2(u.global_position.x - global_position.x, u.global_position.z - global_position.z).length()
		if dist < MIN_RANGE or dist > MAX_RANGE:
			continue
		var n := 0
		for o in units:
			if o.global_position.distance_squared_to(u.global_position) < SHELL_RADIUS * SHELL_RADIUS:
				n += 1
		if n > best_n:
			best_n = n
			best = u
	if best == null:
		_reload = 1.0
		return
	var err := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * AI_ERROR
	_launch(best.global_position + err, AI_RELOAD_TIME)
