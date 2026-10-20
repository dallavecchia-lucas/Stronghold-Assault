class_name TargetDrone
extends Node3D
## Enemy flying target for trying out anti-air while the defenders have no aircraft of their
## own: an alien drone that flies circles (or straight passes) and goes down in flames when
## destroyed. Takes damage like any other flyer ("damageable" and "air_units" groups).

var team := GameConfig.TEAM_DEFENDER
var hp := 110.0
var target_radius := 0.0
var velocity := Vector3.ZERO
## Flies circles of `radius` around `centre` at `speed` m/s (negative turns the other way), or,
## with `heading` set, flies straight that way.
var centre := Vector3.ZERO
var radius := 20.0
var speed := 8.0
var angle := 0.0
var height := UnitTypes.FLY_HEIGHT
var heading := Vector3.ZERO

var _age := 0.0
var _falling := false
var _spin := 0.0
var _rotors: Array[Node3D] = []
var _hull_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("air_units")
	_build()
	if heading == Vector3.ZERO:
		global_position = _orbit_point()


func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	_hull_mat.emission_energy_multiplier = 1.4
	if hp <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	_age += delta
	for r in _rotors:
		r.rotation.y += delta * 40.0
	_hull_mat.emission_energy_multiplier = move_toward(_hull_mat.emission_energy_multiplier, 0.0, delta * 14.0)
	if _falling:
		velocity.y -= 9.8 * delta
		global_position += velocity * delta
		_spin += delta * 6.0
		rotation = Vector3(0.6, _spin, 0.4)
		if global_position.y <= 0.5:
			Combat.spawn_explosion(self, global_position, 4.0)
			queue_free()
		return
	var before := global_position
	if heading != Vector3.ZERO:
		global_position += heading.normalized() * absf(speed) * delta
		global_position.y = height
	else:
		angle += speed / radius * delta
		global_position = _orbit_point()
	global_position.y += sin(_age * 1.7) * 0.4
	velocity = (global_position - before) / delta
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5:
		rotation.y = atan2(-flat.x, -flat.z)
		rotation.z = -0.25 * signf(speed) if heading == Vector3.ZERO else 0.0


func _orbit_point() -> Vector3:
	return centre + Vector3(cos(angle) * radius, height, sin(angle) * radius)


func _die() -> void:
	remove_from_group("damageable")
	remove_from_group("air_units")
	_falling = true
	velocity = velocity * 0.6 + Vector3.UP * 2.0
	Combat.spawn_explosion(self, global_position, 3.0)


## A dark saucer with a glowing red eye and four rotors.
func _build() -> void:
	_hull_mat = StandardMaterial3D.new()
	_hull_mat.albedo_color = Color(0.22, 0.2, 0.26)
	_hull_mat.metallic = 0.7
	_hull_mat.roughness = 0.35
	_hull_mat.emission_enabled = true
	_hull_mat.emission = Color(1.0, 0.3, 0.2)
	_hull_mat.emission_energy_multiplier = 0.0
	var hull := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 0.8
	hull.mesh = s
	hull.material_override = _hull_mat
	add_child(hull)
	var eye := Mats.cylinder_mesh(0.28, 0.12, Vector3(0, -0.05, -0.95), Mats.glow(Color(1.0, 0.15, 0.1), 5.0))
	eye.rotation.x = PI * 0.5
	add_child(eye)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var arm := Mats.box_mesh(Vector3(0.18, 0.1, 1.1), dir * 1.2, _hull_mat)
		arm.rotation.y = atan2(dir.x, dir.z)
		add_child(arm)
		var rotor := Node3D.new()
		rotor.position = dir * 1.8 + Vector3.UP * 0.15
		add_child(rotor)
		rotor.add_child(Mats.box_mesh(Vector3(1.3, 0.03, 0.14), Vector3.ZERO, Mats.flat(Color(0.1, 0.1, 0.12))))
		rotor.add_child(Mats.box_mesh(Vector3(0.14, 0.03, 1.3), Vector3.ZERO, Mats.flat(Color(0.1, 0.1, 0.12))))
		_rotors.append(rotor)
