class_name AttackerUnit
extends CharacterBody3D
## One attacking unit. Driven entirely by its current order:
##   {"type": "idle"}
##   {"type": "move", "pos": Vector3}          go there, ignore enemies
##   {"type": "attack_move", "pos": Vector3}   go there, fight anything in range
##   {"type": "attack", "target": Node3D}      chase and destroy a specific target
## Behaviour differences per unit come from UnitTypes role (infantry, siege,
## artillery, healer, flying, anti_air).

signal died(unit: AttackerUnit)

const HEAL_COLOR := Color(0.35, 1.0, 0.45)
const AA_COLOR := Color(1.0, 0.9, 0.4)

static var _scenes := {}

var unit_id := 0
var type_id := "rifleman"
var stats: Dictionary
var role := "infantry"
var team := GameConfig.TEAM_ATTACKER
var hp := 100.0
var order := {"type": "idle"}
var target: Node3D = null
## Set by the commander for units that were moved together; rhinos sharing one aim as a formation.
var formation_id := 0
## Seconds until the cluster bombing ability can be used again.
var cluster_cd := 0.0
var selected := false:
	set(v):
		selected = v
		if _ring:
			_ring.visible = v
		if _aa_ring:
			_aa_ring.visible = v
		_update_hp_bar()

var _agent: NavigationAgent3D
var _model: Node3D
var _anim: AnimationPlayer  # set when the model is rigged and carries clips
var _ring: MeshInstance3D
var _aa_ring: MeshInstance3D
var _aa_lock: Node3D = null
var _cluster_left := 0.0
var _cluster_cd_shot := 0.0
var _cluster_aim := Vector3.ZERO
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _fire_cd := 0.0
var _retarget_cd := 0.0
## False while the target is a buried structure out of sight: keep closing in instead of firing.
var _sees_target := true
var _anim_t := 0.0
var _recoil := 0.0
var _desired_velocity := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(p_type: String, p_id: int) -> void:
	type_id = p_type
	unit_id = p_id
	stats = UnitTypes.DATA[p_type]
	role = stats.role
	hp = stats.hp
	name = "Unit%d" % p_id


func is_flying() -> bool:
	return role == "flying"


## Small enough for the stronghold's tunnels (2.8 m high) and inner passages (2 m wide).
func fits_inside() -> bool:
	return not is_flying() and stats.radius <= 0.8 and stats.height <= 2.6


## Medics and rhinos never shoot at what they are ordered to attack.
func has_basic_attack() -> bool:
	return role != "healer" and role != "anti_air"


func has_cluster_bomb() -> bool:
	return stats.has("cluster_cooldown")


func cluster_ready() -> bool:
	return has_cluster_bomb() and cluster_cd <= 0.0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("attacker_units")
	if is_flying():
		add_to_group("air_units")
	collision_layer = GameConfig.LAYER_ATTACKERS
	# Attackers don't collide with each other; avoidance keeps them apart instead.
	# Flyers don't collide with anything.
	collision_mask = 0 if is_flying() else GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS
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
	_agent.avoidance_enabled = not is_flying()
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
	# Medics and rhinos don't attack: follow the attack to its target instead.
	if not has_basic_attack() and o.type == "attack":
		o = {"type": "attack_move", "pos": o.target.global_position}
	order = o
	if o.type == "attack":
		target = o.target
	elif o.type == "move":
		target = null
	if o.has("pos") and not is_flying():
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


func heal(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(hp + amount, stats.hp)
	_update_hp_bar()


func _die() -> void:
	hp = 0.0
	remove_from_group("damageable")
	remove_from_group("attacker_units")
	remove_from_group("air_units")
	_cluster_left = 0.0
	collision_layer = 0
	collision_mask = GameConfig.LAYER_WORLD
	_agent.avoidance_enabled = false
	_ring.visible = false
	if _aa_ring:
		_aa_ring.visible = false
	_hp_bar.visible = false
	died.emit(self)
	var tw := create_tween()
	tw.tween_property(_model, "rotation:z", PI * 0.5, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(3.0)
	tw.tween_property(_model, "position:y", -stats.height, 2.0)
	tw.tween_callback(queue_free)


func _range_to(t: Node3D) -> float:
	var r = t.get("target_radius")
	return global_position.distance_to(t.global_position) - (r if r != null else 0.0)


func _in_range(t: Node3D) -> bool:
	var d := _range_to(t)
	return d <= stats.range and d >= stats.get("min_range", 0.0)


func _eye() -> Vector3:
	return global_position + Vector3.UP * stats.height * 0.8


func _can_see(t: Node3D) -> bool:
	if t.get("buried"):
		return not is_flying() and Combat.has_line_of_sight(self, _eye(), Combat.aim_point(t), t)
	if role == "artillery" or t.is_in_group("structures"):
		return true  # shells arc over walls; buildings are big enough to always hit
	return Combat.has_line_of_sight(self, _eye(), Combat.aim_point(t), t)


func _update_target() -> void:
	if not has_basic_attack():
		target = null
		return
	if order.type == "attack":
		if Combat.is_valid_target(order.target):
			target = order.target
			return
		order = {"type": "idle"}
	if order.type == "move":
		target = null
		return
	if Combat.is_valid_target(target) and _in_range(target) and _can_see(target):
		return
	target = _find_enemy()


func _find_enemy() -> Node3D:
	if role != "siege":
		var candidates := []
		for d in get_tree().get_nodes_in_group("defender_targets"):
			if d.is_alive() and _in_range(d):
				candidates.append([global_position.distance_to(d.global_position), d])
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		for c in candidates.slice(0, 3):
			if _can_see(c[1]):
				return c[1]
	var best: Node3D = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("structures"):
		if s.is_alive() and s.team != team:
			var d := _range_to(s)
			if d <= stats.range + 2.0 and d >= stats.get("min_range", 0.0) and d < best_d and _can_see(s):
				best_d = d
				best = s
	return best


func _fire_at(t: Node3D) -> void:
	_fire_cd = stats.fire_interval * randf_range(0.9, 1.15)
	_recoil = 1.0
	match role:
		"siege":
			t.take_damage(stats.damage * stats.structure_mult, team)
			Combat.spawn_impact(self, global_position + (t.global_position - global_position).normalized() * 2.5 + Vector3.UP, true)
		"artillery":
			var aim := Combat.aim_point(t)
			var scatter: float = global_position.distance_to(aim) * stats.spread
			aim += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * scatter
			var shell := Shell.new()
			shell.team = team
			shell.damage = stats.damage
			shell.radius = stats.splash
			shell.structure_mult = stats.structure_mult
			get_tree().current_scene.add_child(shell)
			var muzzle: Vector3 = global_position - global_basis.z * 3.5 + Vector3.UP * stats.height
			shell.launch(muzzle, aim)
			Combat.spawn_explosion(self, muzzle, 0.8)
		_:
			Combat.fire_hitscan(self, _eye(), Combat.aim_point(t), stats.spread, stats.damage, team,
					stats.structure_mult, [get_rid()])


## Medic: patch up the most hurt ally in range.
func _heal_tick() -> void:
	_fire_cd = stats.fire_interval
	var best: AttackerUnit = null
	var worst := 0.999
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if u == self:
			continue
		var ratio: float = u.hp / u.stats.hp
		if ratio < worst and global_position.distance_to(u.global_position) <= stats.range:
			worst = ratio
			best = u
	if best:
		best.heal(stats.heal_rate * stats.fire_interval)
		Combat.spawn_tracer(self, _eye(), Combat.aim_point(best), HEAL_COLOR)


## Rhino passive: stay locked on one enemy flyer until it dies or leaves aa_range, then pick
## the nearest one in range.
func _aa_tick() -> void:
	_fire_cd = stats.fire_interval
	if not (Combat.is_valid_target(_aa_lock) and _in_aa_range(_aa_lock)):
		_aa_lock = null
		var best_d := INF
		for a in get_tree().get_nodes_in_group("air_units"):
			if a.team != team and a.is_alive() and _in_aa_range(a):
				var d := global_position.distance_to(a.global_position)
				if d < best_d:
					best_d = d
					_aa_lock = a
	if _aa_lock:
		_aa_lock.take_damage(stats.aa_dps * stats.fire_interval, team)
		Combat.spawn_tracer(self, _eye(), Combat.aim_point(_aa_lock), AA_COLOR)


func _in_aa_range(a: Node3D) -> bool:
	var d := a.global_position - global_position
	return Vector2(d.x, d.z).length() <= stats.aa_range


## Rhino active: bomb a ground point for cluster_duration seconds. False while on cooldown.
func start_cluster(aim: Vector3) -> bool:
	if not cluster_ready() or not is_alive():
		return false
	cluster_cd = stats.cluster_cooldown
	_cluster_left = stats.cluster_duration
	_cluster_cd_shot = 0.0
	_cluster_aim = aim
	return true


func is_bombing() -> bool:
	return _cluster_left > 0.0


func _cluster_tick(delta: float) -> void:
	_cluster_left -= delta
	_cluster_cd_shot -= delta
	while _cluster_cd_shot <= 0.0 and _cluster_left > 0.0:
		_cluster_cd_shot += stats.cluster_interval
		var spread: float = stats.cluster_spread * sqrt(randf())
		var a := randf() * TAU
		var shell := Shell.new()
		shell.team = team
		shell.damage = stats.cluster_damage
		shell.radius = stats.cluster_splash
		shell.structure_mult = stats.structure_mult
		get_tree().current_scene.add_child(shell)
		var muzzle: Vector3 = global_position + Vector3.UP * (stats.height + 0.4) + global_basis.z * 0.6
		shell.launch(muzzle, _cluster_aim + Vector3(cos(a), 0.0, sin(a)) * spread)
		Combat.spawn_explosion(self, muzzle, 0.5)
		_recoil = 1.0


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		if not is_on_floor():
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y -= _gravity * delta
			move_and_slide()
		return
	_fire_cd -= delta
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.3
		_update_target()
		_sees_target = not (Combat.is_valid_target(target) and target.get("buried")) or _can_see(target)

	var move_to = null
	if role == "healer":
		if _fire_cd <= 0.0:
			_heal_tick()
	if has_cluster_bomb():
		cluster_cd = maxf(cluster_cd - delta, 0.0)
		if _cluster_left > 0.0:
			_cluster_tick(delta)
	if stats.has("aa_dps") and _fire_cd <= 0.0:
		_aa_tick()
	if Combat.is_valid_target(target) and _in_range(target) and _sees_target:
		_face(target.global_position, delta)
		if _fire_cd <= 0.0:
			_fire_at(target)
	elif order.type == "move" or order.type == "attack_move":
		move_to = order.pos
	elif order.type == "attack" and Combat.is_valid_target(target):
		move_to = target.global_position

	if is_flying():
		_fly(move_to, delta)
		return

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


## Flyers go in a straight line at cruising height and hover when they arrive.
func _fly(move_to, delta: float) -> void:
	var want := Vector3.ZERO
	if move_to != null:
		var to: Vector3 = move_to - global_position
		to.y = 0.0
		if to.length() > 2.0:
			want = to.normalized() * stats.speed
		elif order.type != "attack":
			order = {"type": "idle"}
	velocity.x = lerpf(velocity.x, want.x, delta * 2.0)
	velocity.z = lerpf(velocity.z, want.z, delta * 2.0)
	velocity.y = clampf((_ground_height() + UnitTypes.FLY_HEIGHT - global_position.y) * 1.5, -6.0, 6.0)
	global_position += velocity * delta
	if want.length() > 0.3 and not Combat.is_valid_target(target):
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 4.0 * delta)


## Height of the terrain (the mountain included) under a flyer, so it cruises over the peak.
func _ground_height() -> float:
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(hit.position.y, 0.0) if not hit.is_empty() else 0.0


func _on_velocity_computed(safe: Vector3) -> void:
	if hp <= 0.0 or is_flying():
		return
	var dt := get_physics_process_delta_time()
	if stats.get("steer", false):
		_steer(safe, dt)
	else:
		velocity.x = safe.x
		velocity.z = safe.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * dt
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z)
	if not stats.get("steer", false) and flat.length() > 0.3 and not (Combat.is_valid_target(target) and _in_range(target)):
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 8.0 * dt)


## Vehicle-style movement (snakes): turn toward the wanted direction at a limited rate and
## only ever move the way the head points, slowing down while the turn is sharp.
func _steer(want: Vector3, dt: float) -> void:
	var flat := Vector2(want.x, want.z)
	if flat.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	rotation.y = rotate_toward(rotation.y, atan2(-want.x, -want.z), stats.get("turn_rate", 3.0) * dt)
	var fwd := Vector2(-sin(rotation.y), -cos(rotation.y))
	var along := maxf(fwd.dot(flat.normalized()), 0.0)
	var spd := flat.length() * along * along
	velocity.x = fwd.x * spd
	velocity.z = fwd.y * spd


func _face(point: Vector3, delta: float) -> void:
	var d := point - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), (3.0 if stats.radius > 1.0 else 10.0) * delta)


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	# Procedural animation until models are rigged.
	var spd := Vector2(velocity.x, velocity.z).length()
	var moving := spd > 0.3
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	if moving:
		_anim_t += delta * spd
	if _anim:
		# Rigged model: play its clips, matching the move cycle to ground speed.
		var clip: String = stats.anim_move if moving else stats.anim_idle
		if _anim.current_animation != clip:
			_anim.play(clip, 0.25)
		_anim.speed_scale = clampf(spd / stats.anim_ref_speed, 0.6, 2.0) if moving else 1.0
	match stats.anim:
		"hop":
			var hop := absf(sin(_anim_t * 1.2)) if moving else 0.0
			# Weights capped at 1: a long frame (e.g. a navmesh rebake) would overshoot and blow up.
			_model.position.y = lerpf(_model.position.y, hop * 0.45, minf(delta * 15.0, 1.0))
			_model.rotation.x = lerpf(_model.rotation.x, -hop * 0.15, minf(delta * 10.0, 1.0))
		"stomp":
			_model.position.y = absf(sin(_anim_t * 1.6)) * 0.06 if moving else lerpf(_model.position.y, 0.0, delta * 5.0)
			_model.rotation.z = sin(_anim_t * 1.6) * 0.025 if moving else lerpf(_model.rotation.z, 0.0, delta * 5.0)
		"hover":
			_anim_t += delta * 2.0
			_model.position.y = sin(_anim_t) * 0.3
			_model.rotation.x = -clampf(spd / stats.speed, 0.0, 1.0) * 0.25
		"roll":
			_model.position.y = randf_range(0.0, 0.02) if moving else 0.0
		"rigged":
			pass
		_:
			_model.position.y = absf(sin(_anim_t * 2.2)) * 0.08 if moving else lerpf(_model.position.y, 0.0, delta * 8.0)
			_model.rotation.z = sin(_anim_t * 2.2) * 0.06 if moving else lerpf(_model.rotation.z, 0.0, delta * 8.0)
	if stats.anim not in ["hop", "hover", "rigged"]:
		_model.rotation.x = _recoil * (0.08 if stats.radius < 1.0 else 0.015)
	if _hp_bar.visible:
		_hp_bar.global_position = global_position + Vector3.UP * (stats.height + 0.5)
		var cam := get_viewport().get_camera_3d()
		if cam:
			_hp_bar.global_basis = cam.global_basis


# ---------------------------------------------------------------- visuals

func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	if stats.model == "ram":
		_build_ram()
		return
	if not _scenes.has(stats.model):
		_scenes[stats.model] = load(stats.model)
	var m := (_scenes[stats.model] as PackedScene).instantiate() as Node3D
	m.rotation.y = PI  # model front is +Z, units look down -Z
	_model.add_child(m)
	var players := m.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty() and stats.has("anim_move"):
		_anim = players[0]
		for clip in [stats.anim_move, stats.anim_idle]:
			var a := _anim.get_animation(clip)
			if not a.has_meta("looped"):
				# Baked loops end on a copy of the first frame: drop it so the wrap is seamless.
				a.length -= 1.0 / 30.0
				a.loop_mode = Animation.LOOP_LINEAR
				a.set_meta("looped", true)
		_anim.play(stats.anim_idle)
		_anim.seek(randf() * _anim.current_animation_length)  # don't move in lockstep
	if stats.get("carry_gun", false):
		# Carried weapon placeholder until weapons get modeled.
		_model.add_child(Mats.box_mesh(Vector3(0.12, 0.16, 0.9), Vector3(0.35, 1.15, -0.45),
				Mats.flat(Color(0.12, 0.12, 0.13), 0.6, 0.4)))


func _build_ram() -> void:
	var wood := Mats.wood()
	var iron := Mats.flat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
	_model.add_child(Mats.box_mesh(Vector3(2.2, 0.5, 3.6), Vector3(0, 0.7, 0), wood))
	_model.add_child(Mats.box_mesh(Vector3(2.4, 0.15, 3.8), Vector3(0, 2.2, 0), wood))  # roof
	for x in [-1.0, 1.0]:
		for z in [-1.5, 1.5]:
			_model.add_child(Mats.box_mesh(Vector3(0.15, 1.5, 0.15), Vector3(x, 1.45, z), wood))
			var wheel := Mats.cylinder_mesh(0.45, 0.2, Vector3(x * 1.15, 0.45, z * 0.8), iron)
			wheel.rotation.z = PI * 0.5
			_model.add_child(wheel)
	var log := Mats.cylinder_mesh(0.28, 4.6, Vector3(0, 1.4, -0.6), wood)
	log.rotation.x = PI * 0.5
	_model.add_child(log)
	var head := Mats.cylinder_mesh(0.36, 0.5, Vector3(0, 1.4, -2.9), iron)
	head.rotation.x = PI * 0.5
	_model.add_child(head)


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
	if stats.has("aa_range"):
		# Dashed circle showing how far the anti-air passive reaches.
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		RhinoAim.dashed_circle(im, Vector3.UP * 0.15, stats.aa_range, 48)
		im.surface_end()
		_aa_ring = MeshInstance3D.new()
		_aa_ring.mesh = im
		_aa_ring.material_override = Mats.unshaded(Color(0.55, 0.75, 1.0, 0.8))
		_aa_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aa_ring.visible = false
		add_child(_aa_ring)


func _build_hp_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.top_level = true
	add_child(_hp_bar)
	var w := clampf(stats.radius * 2.2, 1.2, 3.0)
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
