class_name AttackerUnit
extends CharacterBody3D
## One attacking soldier or siege machine. Driven entirely by its current order:
##   {"type": "idle"}
##   {"type": "move", "pos": Vector3}          walk there, ignore enemies
##   {"type": "attack_move", "pos": Vector3}   walk there, fight anything in range
##   {"type": "attack", "target": Node3D}      chase and destroy a specific target

signal died(unit: AttackerUnit)

const BEAR_MODEL := "res://assets/units/cyber_bear_commando/cyber_bear_commando.glb"
static var _bear_scene: PackedScene

var unit_id := 0
var type_id := "rifleman"
var stats: Dictionary
var team := GameConfig.TEAM_ATTACKER
var hp := 100.0
var order := {"type": "idle"}
var target: Node3D = null
var selected := false:
	set(v):
		selected = v
		if _ring:
			_ring.visible = v
		_update_hp_bar()

var _agent: NavigationAgent3D
var _model: Node3D
var _ring: MeshInstance3D
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _fire_cd := 0.0
var _retarget_cd := 0.0
var _anim_t := 0.0
var _recoil := 0.0
var _desired_velocity := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(p_type: String, p_id: int) -> void:
	type_id = p_type
	unit_id = p_id
	stats = UnitTypes.DATA[p_type]
	hp = stats.hp
	name = "Unit%d" % p_id


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("attacker_units")
	collision_layer = GameConfig.LAYER_ATTACKERS
	# Attackers don't collide with each other; avoidance keeps them apart instead.
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS
	floor_snap_length = 0.5

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = stats.radius
	cap.height = maxf(stats.height, stats.radius * 2.0 + 0.1)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)

	_agent = NavigationAgent3D.new()
	_agent.radius = stats.radius + 0.2
	_agent.height = stats.height
	_agent.max_speed = stats.speed
	_agent.path_desired_distance = 1.0
	_agent.target_desired_distance = 1.5
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 6.0
	_agent.max_neighbors = 8
	_agent.time_horizon_agents = 1.0
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)

	_build_model()
	_build_ring()
	_build_hp_bar()
	_retarget_cd = randf() * 0.3


# ---------------------------------------------------------------- orders

func set_order(o: Dictionary) -> void:
	order = o
	if o.type == "attack":
		target = o.target
	elif o.type == "move":
		target = null
	if o.has("pos"):
		_agent.target_position = o.pos


func is_idle() -> bool:
	return order.type == "idle" and not Combat.is_valid_target(target)


# ---------------------------------------------------------------- combat

func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * stats.height * 0.6


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	_update_hp_bar()
	if hp <= 0.0:
		_die()


func _die() -> void:
	hp = 0.0
	remove_from_group("damageable")
	remove_from_group("attacker_units")
	collision_layer = 0
	collision_mask = GameConfig.LAYER_WORLD
	_agent.avoidance_enabled = false
	_ring.visible = false
	_hp_bar.visible = false
	died.emit(self)
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", -PI * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(3.0)
	tw.tween_property(_model, "position:y", -2.0, 2.0)
	tw.tween_callback(queue_free)


func _range_to(t: Node3D) -> float:
	var r = t.get("target_radius")
	return global_position.distance_to(t.global_position) - (r if r != null else 0.0)


func _in_range(t: Node3D) -> bool:
	return _range_to(t) <= stats.range


func _eye() -> Vector3:
	return global_position + Vector3.UP * stats.height * 0.8


func _update_target() -> void:
	if order.type == "attack":
		if Combat.is_valid_target(order.target):
			target = order.target
			return
		order = {"type": "idle"}
	if order.type == "move":
		target = null
		return
	if Combat.is_valid_target(target) and _in_range(target) and (target.is_in_group("structures") or Combat.has_line_of_sight(self, _eye(), Combat.aim_point(target), target)):
		return
	target = _find_enemy()


func _find_enemy() -> Node3D:
	var best: Node3D = null
	if not stats.structures_only:
		var candidates := []
		for d in get_tree().get_nodes_in_group("defender_targets"):
			if d.is_alive():
				var dist := global_position.distance_to(d.global_position)
				if dist <= stats.range:
					candidates.append([dist, d])
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		for c in candidates.slice(0, 3):
			if Combat.has_line_of_sight(self, _eye(), Combat.aim_point(c[1]), c[1]):
				return c[1]
	var best_d := INF
	for s in get_tree().get_nodes_in_group("structures"):
		if s.is_alive() and s.team != team:
			var d := _range_to(s)
			if d <= stats.range + 2.0 and d < best_d:
				best_d = d
				best = s
	return best


func _fire_at(t: Node3D) -> void:
	_fire_cd = stats.fire_interval * randf_range(0.9, 1.15)
	_recoil = 1.0
	if stats.model == "ram":
		t.take_damage(stats.damage * stats.structure_mult, team)
		Combat.spawn_impact(self, global_position + (t.global_position - global_position).normalized() * 2.5 + Vector3.UP, true)
		return
	Combat.fire_hitscan(self, _eye(), Combat.aim_point(t), stats.spread, stats.damage, team,
			stats.structure_mult, [get_rid()])


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		if not is_on_floor():
			velocity.y -= _gravity * delta
			move_and_slide()
		return
	_fire_cd -= delta
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.3
		_update_target()

	var move_to = null
	if Combat.is_valid_target(target) and _in_range(target):
		_face(target.global_position, delta)
		if _fire_cd <= 0.0:
			_fire_at(target)
	elif order.type == "move" or order.type == "attack_move":
		move_to = order.pos
	elif order.type == "attack" and Combat.is_valid_target(target):
		move_to = target.global_position

	_desired_velocity = Vector3.ZERO
	if move_to != null:
		if _agent.target_position.distance_to(move_to) > 1.5:
			_agent.target_position = move_to
		if _agent.is_navigation_finished():
			if order.type != "attack":
				order = {"type": "idle"}
		else:
			var next := _agent.get_next_path_position()
			var dir := next - global_position
			dir.y = 0.0
			if dir.length_squared() > 0.0001:
				_desired_velocity = dir.normalized() * stats.speed
	_agent.velocity = _desired_velocity


func _on_velocity_computed(safe: Vector3) -> void:
	if hp <= 0.0:
		return
	var dt := get_physics_process_delta_time()
	velocity.x = safe.x
	velocity.z = safe.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * dt
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3 and not (Combat.is_valid_target(target) and _in_range(target)):
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 8.0 * dt)


func _face(point: Vector3, delta: float) -> void:
	var d := point - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 10.0 * delta)


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	# Procedural animation until the model is rigged: bob while walking, kick when firing.
	var spd := Vector2(velocity.x, velocity.z).length()
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	if spd > 0.3:
		_anim_t += delta * spd * 2.2
		_model.position.y = absf(sin(_anim_t)) * 0.08 * stats.scale
		_model.rotation.z = sin(_anim_t) * 0.06
	else:
		_model.position.y = lerpf(_model.position.y, 0.0, delta * 8.0)
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 8.0)
	_model.rotation.x = _recoil * 0.08
	if _hp_bar.visible:
		_hp_bar.global_position = global_position + Vector3.UP * (stats.height + 0.5)
		var cam := get_viewport().get_camera_3d()
		if cam:
			_hp_bar.global_basis = cam.global_basis


# ---------------------------------------------------------------- visuals

func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	if stats.model == "bear":
		if _bear_scene == null:
			_bear_scene = load(BEAR_MODEL)
		var bear := _bear_scene.instantiate() as Node3D
		bear.scale = Vector3.ONE * stats.scale
		bear.rotation.y = PI  # model front is +Z, units look down -Z
		_model.add_child(bear)
		# Carried weapon placeholder until weapons get modeled.
		var gun_len := 1.2 if type_id == "heavy" else 0.9
		var gun := Mats.box_mesh(Vector3(0.12, 0.16, gun_len), Vector3(0.35, 1.15, -0.45) * stats.scale,
				Mats.flat(Color(0.12, 0.12, 0.13), 0.6, 0.4))
		_model.add_child(gun)
	else:
		_build_ram()


func _build_ram() -> void:
	var wood := Mats.wood()
	var iron := Mats.flat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
	_model.add_child(Mats.box_mesh(Vector3(2.2, 0.5, 3.6), Vector3(0, 0.7, 0), wood))
	# roof
	var roof := Mats.box_mesh(Vector3(2.4, 0.15, 3.8), Vector3(0, 2.2, 0), wood)
	_model.add_child(roof)
	for x in [-1.0, 1.0]:
		for z in [-1.5, 1.5]:
			_model.add_child(Mats.box_mesh(Vector3(0.15, 1.5, 0.15), Vector3(x, 1.45, z), wood))
			var wheel := Mats.cylinder_mesh(0.45, 0.2, Vector3(x * 1.15, 0.45, z * 0.8), iron)
			wheel.rotation.z = PI * 0.5
			_model.add_child(wheel)
	var log := Mats.cylinder_mesh(0.28, 4.6, Vector3(0, 1.4, -0.6), wood)
	log.rotation.x = PI * 0.5
	_model.add_child(log)
	_model.add_child(_ram_head(iron))


func _ram_head(mat: Material) -> MeshInstance3D:
	var head := Mats.cylinder_mesh(0.36, 0.5, Vector3(0, 1.4, -2.9), mat)
	head.rotation.x = PI * 0.5
	return head


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = stats.radius + 0.25
	t.outer_radius = stats.radius + 0.4
	t.rings = 24
	t.ring_segments = 4
	_ring.mesh = t
	_ring.material_override = Mats.unshaded(Color(0.3, 1.0, 0.4))
	_ring.position.y = 0.06
	_ring.scale.y = 0.2
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func _build_hp_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.top_level = true
	add_child(_hp_bar)
	var w := 1.2 * maxf(stats.scale, 1.0) * (1.6 if stats.model == "ram" else 1.0)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, 0.14)
	bg.mesh = q
	bg.material_override = Mats.unshaded(Color(0, 0, 0, 0.6))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(w, 0.1)
	_hp_fill.mesh = qf
	_hp_fill.position.z = 0.01
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(_hp_fill)
	_hp_bar.visible = false


func _update_hp_bar() -> void:
	if not _hp_bar:
		return
	var ratio := clampf(hp / stats.hp, 0.0, 1.0)
	_hp_bar.visible = hp > 0.0 and (selected or ratio < 1.0)
	_hp_fill.scale.x = maxf(ratio, 0.001)
	_hp_fill.material_override = Mats.unshaded(Color(1.0, 0.25, 0.2) if ratio < 0.35 else Color(0.95, 0.8, 0.2) if ratio < 0.7 else Color(0.3, 1.0, 0.4))

