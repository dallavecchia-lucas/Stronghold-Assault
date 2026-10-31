class_name DefenderSoldier
extends CharacterBody3D
## Garrison soldier. Holds position and shoots on its own until the defending player
## takes control of it, at which point it becomes a first-person character.

signal became_unavailable(station)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const JUMP_VELOCITY := 4.8
const MAG_SIZE := 30
const RELOAD_TIME := 1.8
const PLAYER_DAMAGE := 26.0
const PLAYER_FIRE_INTERVAL := 0.11
const AI_RANGE := 50.0
const AI_DAMAGE := 11.0
const AI_FIRE_INTERVAL := 0.6
const RESPAWN_TIME := 15.0
## Where the first-person Shadowline rifle's grip sits in front of the camera. Aimed, it is put away
## and its smart scope's view (RifleScope) fills the screen instead, a little zoomed in (SCOPE_FOV).
## The plain view model's are the others.
const VIEW_HIP := Vector3(0.13, -0.2, -0.25)
const VIEW_AIM := Vector3(0.13, -0.32, -0.2)
const SCOPE_FOV := 58.0
const PLAIN_HIP := Vector3(0.22, -0.22, -0.45)
const PLAIN_AIM := Vector3(0.0, -0.16, -0.38)

var station_name := "Soldier"
var station_kind := "soldier"
var team := GameConfig.TEAM_DEFENDER
var max_hp := 150.0
var hp := 150.0
var target_radius := 0.0
var possessed := false
var post_transform: Transform3D

var ammo := MAG_SIZE
var _reloading := 0.0
var _fire_cd := 0.0
var _retarget_cd := 0.0
var _respawn_cd := 0.0
var _target: Node3D
var _pitch := 0.0
var _kick := 0.0
## Knocked off its feet (run over by a ram): flies until it lands, no control meanwhile.
var _tossed := false
## Held in a Serpent Sniper's coils last frame (it struggles).
var _was_held := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _head: Node3D
var _camera: Camera3D
var _body: Node3D
## Rigged character model (empty = placeholder capsule). Clips: "Idle", "Running".
var model_path := ""
var _anim: AnimationPlayer
const ANIM_IDLE := "Idle"
const ANIM_RUN := "Running"
var _viewmodel: Node3D
var _muzzle: Node3D
## The muzzle of the rifle in the body's hands (HeldGun), when the model carries one.
var _body_muzzle: Node3D
## First-person arms (the model's own, cut down: tools/gltf/fp_arms.py), posed by its Idle clip and
## lined up every frame so its `rifle` bone lies on the view model's gun.
var _view_gun: Node3D
var _view_arms: Node3D
var _view_skel: Skeleton3D
var _view_rifle := -1
## The rifle's smart scope's view, when the model carries the Shadowline.
var _scope: RifleScope
var _view_hip := PLAIN_HIP
var _view_aim := PLAIN_AIM
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS | GameConfig.LAYER_DEFENDERS
	post_transform = global_transform

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	_shape.shape = cap
	_shape.position.y = 0.9
	add_child(_shape)

	_body = Node3D.new()
	add_child(_body)
	if model_path != "":
		var m := (load(model_path) as PackedScene).instantiate() as Node3D
		m.rotation.y = PI  # model front is +Z, soldiers look down -Z
		_body.add_child(m)
		var players := m.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_anim = players[0]
			for clip in [ANIM_IDLE, ANIM_RUN]:
				if _anim.has_animation(clip):
					_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			_play(ANIM_IDLE)
			if _anim.is_playing():
				_anim.seek(randf() * _anim.current_animation_length)
		_body_muzzle = HeldGun.attach(m, HeldGun.SHADOWLINE_RIFLE)
	else:
		_build_placeholder_body()

	_head = Node3D.new()
	_head.position.y = 1.6
	add_child(_head)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 800.0
	_head.add_child(_camera)

	_viewmodel = Node3D.new()
	_camera.add_child(_viewmodel)
	if _body_muzzle:
		# The Shadowline assault rifle the body carries, held out in front: its origin is the pistol
		# grip, its muzzle +Z (turned to look down -Z with the camera).
		_view_hip = VIEW_HIP
		_view_aim = VIEW_AIM
		var gun := HeldGun.instance(HeldGun.SHADOWLINE_RIFLE)
		gun.rotation = Vector3(0.0, PI, 0.0)
		_viewmodel.add_child(gun)
		for mi in gun.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle = gun.find_child("muzzle", true, false) as Node3D
		_view_gun = gun
		_build_view_arms()
		_scope = RifleScope.new()
		add_child(_scope)
	else:
		var gun_mat := Mats.flat(Color(0.12, 0.12, 0.13), 0.7, 0.35)
		_viewmodel.add_child(Mats.box_mesh(Vector3(0.07, 0.11, 0.6), Vector3.ZERO, gun_mat))
		_viewmodel.add_child(Mats.box_mesh(Vector3(0.05, 0.16, 0.08), Vector3(0, -0.1, 0.08), gun_mat))
		_viewmodel.add_child(Mats.box_mesh(Vector3(0.06, 0.06, 0.22), Vector3(0, 0.07, -0.05), Mats.flat(Color(0.25, 0.28, 0.32), 0.5, 0.5)))
		for c in _viewmodel.get_children():
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle = Node3D.new()
		_muzzle.position = Vector3(0, 0, -0.32)
		_viewmodel.add_child(_muzzle)
	_viewmodel.position = _view_hip
	_viewmodel.visible = false


## The armed model's first-person arms: <model>_fp_arms.glb beside <model>_armed.glb.
func _build_view_arms() -> void:
	var path := model_path.replace("_armed.glb", "_fp_arms.glb")
	if not ResourceLoader.exists(path):
		return
	_view_arms = (load(path) as PackedScene).instantiate() as Node3D
	_viewmodel.add_child(_view_arms)
	for mi in _view_arms.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var skels := _view_arms.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_view_skel = skels[0]
		_view_rifle = _view_skel.find_bone("rifle")
	var players := _view_arms.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var a := players[0] as AnimationPlayer
		if a.has_animation(ANIM_IDLE):
			a.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
			a.play(ANIM_IDLE)


## Puts the first-person arms where their hands hold the view model's gun.
func _hold_view_gun() -> void:
	if _view_arms == null or _view_rifle < 0 or not _viewmodel.visible:
		return
	var rel := _view_arms.global_transform.affine_inverse() * _view_skel.global_transform \
			* _view_skel.get_bone_global_pose(_view_rifle)
	_view_arms.transform = _view_gun.transform * rel.affine_inverse()


# ---------------------------------------------------------------- station interface

func can_possess() -> bool:
	return hp > 0.0


func possess() -> void:
	possessed = true
	_camera.current = true
	_body.visible = false
	_viewmodel.visible = true
	_pitch = 0.0
	_head.rotation.x = 0.0


func unpossess() -> void:
	possessed = false
	_camera.current = false
	_body.visible = hp > 0.0
	_viewmodel.visible = false
	_camera.fov = 75.0
	if _scope:
		_scope.amount = 0.0


func wants_captured_mouse() -> bool:
	return true


func get_station_position() -> Vector3:
	return global_position


func get_hud_info() -> Dictionary:
	var status := "RELOADING" if _reloading > 0.0 else "%d / %d" % [ammo, MAG_SIZE]
	return {"weapon": "Rifle", "status": status, "hp": hp / max_hp,
			"hint": "WASD move · Shift sprint · Space jump · LMB fire · RMB aim · R reload"}


func get_camera() -> Camera3D:
	return _camera


# ---------------------------------------------------------------- damage

func is_alive() -> bool:
	return hp > 0.0


func get_approach_point() -> Vector3:
	return Combat.wall_approach(global_position)


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.25


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if possessed:
		_kick += 0.02
	if hp <= 0.0:
		_die()


## Run over: thrown along `v` (m/s), out of control until it lands.
func toss(v: Vector3) -> void:
	if hp <= 0.0 or SerpentTrap.is_held(self):
		return
	velocity = v
	_tossed = true
	if possessed:
		_kick += 0.1


func _die() -> void:
	hp = 0.0
	if _scope:
		_scope.amount = 0.0
	_respawn_cd = RESPAWN_TIME
	_tossed = false
	_body.visible = false
	_shape.set_deferred("disabled", true)
	Combat.spawn_impact(self, get_aim_point(), true)
	became_unavailable.emit(self)


func _respawn() -> void:
	hp = max_hp
	ammo = MAG_SIZE
	global_transform = post_transform
	velocity = Vector3.ZERO
	_shape.set_deferred("disabled", false)
	_body.visible = not possessed


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		_respawn_cd -= delta
		if _respawn_cd <= 0.0:
			_respawn()
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _tossed:
		move_and_slide()
		_tossed = not (is_on_floor() and velocity.y <= 0.0)
		return
	if SerpentTrap.is_held(self):
		# In a Serpent Sniper's coils (SerpentTrap.hold): it can't move or fight, and struggles.
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
	if possessed:
		_player_update(delta)
	else:
		_ai_update(delta)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not possessed or hp <= 0.0 or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameConfig.mouse_sensitivity * (_camera.fov / 75.0)
		rotate_y(-event.relative.x * sens)
		_pitch = clampf(_pitch - event.relative.y * sens, -1.45, 1.45)
		_head.rotation.x = _pitch
	elif event.is_action_pressed("reload"):
		_start_reload()


func _player_update(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if is_on_floor():
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.x = lerpf(velocity.x, dir.x * speed, delta * 3.0)
		velocity.z = lerpf(velocity.z, dir.z * speed, delta * 3.0)

	var aiming := Input.is_action_pressed("aim")
	if _scope:
		# The smart scope: a slight zoom, the rifle lowered out of sight, the scope's view on the visor.
		_camera.fov = lerpf(_camera.fov, SCOPE_FOV if aiming else 75.0, delta * 12.0)
		_scope.amount = move_toward(_scope.amount, 1.0 if aiming else 0.0, delta * 6.0)
		_viewmodel.visible = _scope.amount < 0.6
		if _scope.amount > 0.0:
			_feed_scope()
	else:
		_camera.fov = lerpf(_camera.fov, 50.0 if aiming else 75.0, delta * 12.0)
	_viewmodel.position = _viewmodel.position.lerp(_view_aim if aiming else _view_hip, delta * 12.0)
	_kick = maxf(_kick - delta * 0.3, 0.0)
	_viewmodel.position.z += _kick

	if Input.is_action_pressed("fire") and _fire_cd <= 0.0 and _reloading <= 0.0:
		if ammo <= 0:
			_start_reload()
		else:
			ammo -= 1
			_fire_cd = PLAYER_FIRE_INTERVAL
			var moving := Vector2(velocity.x, velocity.z).length() > 0.5
			var spread := 0.003 if aiming else (0.02 if moving else 0.01)
			var from := _camera.global_position
			var aim_at := from - _camera.global_basis.z * 100.0
			Combat.fire_hitscan(self, from, aim_at, spread, PLAYER_DAMAGE, team, 0.3, [get_rid()], _muzzle.global_position)
			Combat.spawn_muzzle_light(self, _muzzle.global_position)
			_kick = 0.04
			if _scope:
				_scope.fired()
			# recoil climb
			_pitch = clampf(_pitch + 0.006, -1.45, 1.45)
			_head.rotation.x = _pitch


## The smart scope's readouts: the range to what is under the dot (and whether it is a hostile), the
## heading and elevation, the magazine, the zoom.
func _feed_scope() -> void:
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - _camera.global_basis.z * RifleScope.SCALE_MAX * 1.5,
			GameConfig.LAYER_ALL_SOLID, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_scope.range_m = from.distance_to(hit.position) if not hit.is_empty() else -1.0
	_scope.target = ""
	if not hit.is_empty():
		var d := Combat.find_damageable(hit.collider)
		if d is AttackerUnit and (d as AttackerUnit).team != team:
			_scope.target = str((d as AttackerUnit).stats.get("name", "Hostile"))
	_scope.heading = fposmod(-rad_to_deg(global_rotation.y), 360.0)
	_scope.elevation = rad_to_deg(_pitch)
	_scope.ammo = ammo
	_scope.mag = MAG_SIZE
	_scope.reload = 1.0 - _reloading / RELOAD_TIME if _reloading > 0.0 else 0.0
	_scope.zoom = tan(deg_to_rad(37.5)) / tan(deg_to_rad(_camera.fov * 0.5))


func _start_reload() -> void:
	if _reloading <= 0.0 and ammo < MAG_SIZE:
		_reloading = RELOAD_TIME


func _ai_update(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, delta * 20.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 20.0)
	if FlashGrenade.is_blind(self):
		return  # flashed: can't see to shoot
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.4 + randf() * 0.2
		_target = _find_target()
	if not Combat.is_valid_target(_target):
		return
	var to := _target.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 6.0)
	if _fire_cd <= 0.0 and _reloading <= 0.0:
		_fire_cd = AI_FIRE_INTERVAL * randf_range(0.8, 1.3)
		ammo -= 1
		if ammo <= 0:
			_start_reload()
		var eye := global_position + Vector3.UP * 1.6
		var muzzle = _body_muzzle.global_position if _body_muzzle else null
		Combat.fire_hitscan(self, eye, Combat.aim_point(_target), 0.05, AI_DAMAGE, team, 0.3, [get_rid()], muzzle)
		if _body_muzzle:
			Combat.spawn_impact(self, _body_muzzle.global_position, false)  # muzzle flash


func _find_target() -> Node3D:
	var eye := global_position + Vector3.UP * 1.6
	var best: Node3D = null
	var best_d := AI_RANGE
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var d := global_position.distance_to(u.global_position)
		if d < best_d and Combat.has_line_of_sight(self, eye, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best


func _build_placeholder_body() -> void:
	var uniform := Mats.flat(Color(0.18, 0.28, 0.5), 0.1, 0.8)
	var armor := Mats.flat(Color(0.55, 0.57, 0.6), 0.6, 0.4)
	var torso := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.32
	cm.height = 1.5
	torso.mesh = cm
	torso.material_override = uniform
	torso.position.y = 0.78
	_body.add_child(torso)
	var helmet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.36
	helmet.mesh = sm
	helmet.material_override = armor
	helmet.position.y = 1.62
	_body.add_child(helmet)
	_body.add_child(Mats.box_mesh(Vector3(0.5, 0.4, 0.25), Vector3(0, 1.15, 0.05), armor))
	_body.add_child(Mats.box_mesh(Vector3(0.08, 0.1, 0.8), Vector3(0.22, 1.2, -0.4), Mats.flat(Color(0.1, 0.1, 0.1), 0.5, 0.4)))


func _play(clip: String) -> void:
	if _anim and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.25)


func _process(_delta: float) -> void:
	_hold_view_gun()
	if _anim == null or hp <= 0.0:
		return
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.5:
		_play(ANIM_RUN)
		_anim.speed_scale = clampf(spd / WALK_SPEED, 0.7, 1.6)
	else:
		_play(ANIM_IDLE)
		_anim.speed_scale = 1.0
