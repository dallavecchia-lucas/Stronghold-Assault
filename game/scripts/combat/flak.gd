class_name Flak
extends RefCounted
## Flak from the War Elephant's cannons: a shell streaks out of the muzzle and bursts close to
## the aircraft in a flash and a black puff. The damage lands with the burst.

const SHELL_SPEED := 160.0
## Bursts land around the aircraft, not dead on it.
const SCATTER := 1.6
const PUFF := Color(0.1, 0.1, 0.1, 0.85)

static var _flash_mat: StandardMaterial3D
static var _streak_mat: StandardMaterial3D


static func fire(shooter: Node3D, muzzle: Vector3, target: Node3D, damage: float, team: int) -> void:
	var burst := Combat.aim_point(target) + _scatter()
	var root := shooter.get_tree().current_scene
	var flight := muzzle.distance_to(burst) / SHELL_SPEED
	_streak(root, muzzle, burst, flight)
	_flash(root, muzzle, 0.5, 0.08)
	SmokeCloud.wisp(shooter, muzzle, 1.0)
	shooter.get_tree().create_timer(flight, false).timeout.connect(func():
		if not is_instance_valid(root):
			return  # the match ended while the shell was in the air
		if Combat.is_valid_target(target):
			target.take_damage(damage, team)
		burst_at(root, burst))


## Flash and a black puff that swells and drifts away.
static func burst_at(root: Node, pos: Vector3) -> void:
	_flash(root, pos, 1.1, 0.14)
	for k in 2:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 1.4
		mi.mesh = quad
		var mat := SmokeCloud.puff_material(PUFF)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.global_position = pos + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4))
		mi.scale = Vector3.ONE * 0.4
		var life := randf_range(1.4, 2.0)
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "scale", Vector3.ONE * randf_range(1.6, 2.1), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(mi, "scale", Vector3.ONE * 2.6, life).set_delay(0.25)
		tw.tween_property(mi, "global_position", mi.global_position + Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(-0.6, 0.6)), life + 0.25)
		tw.tween_property(mat, "albedo_color:a", 0.0, life).set_delay(0.25).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)


## The shell: a glowing streak from the muzzle to where it bursts.
static func _streak(root: Node, from: Vector3, to: Vector3, flight: float) -> void:
	if _streak_mat == null:
		_streak_mat = StandardMaterial3D.new()
		_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_streak_mat.albedo_color = Color(1.0, 0.85, 0.55)
		_streak_mat.emission_enabled = true
		_streak_mat.emission = Color(1.0, 0.65, 0.25)
		_streak_mat.emission_energy_multiplier = 6.0
	var dir := (to - from).normalized()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 2.2)
	mi.mesh = box
	mi.material_override = _streak_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), from + dir * 1.1)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to - dir * 1.1, flight)
	tw.tween_callback(mi.queue_free)


static func _flash(root: Node, pos: Vector3, size: float, time: float) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.82, 0.45)
		_flash_mat.emission_enabled = true
		_flash_mat.emission = Color(1.0, 0.6, 0.2)
		_flash_mat.emission_energy_multiplier = 8.0
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	s.radial_segments = 8
	s.rings = 4
	mi.mesh = s
	mi.material_override = _flash_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.1, time)
	tw.tween_callback(mi.queue_free)


static func _scatter() -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	return v.normalized() * SCATTER * randf_range(0.4, 1.0)
