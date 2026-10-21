class_name Combat
extends RefCounted
## Shared combat helpers: hitscan shots, explosions and their visual effects.
##
## Anything that can be hurt is in the "damageable" group and exposes:
##   var team: int
##   func take_damage(amount: float, from_team: int) -> void
##   func is_alive() -> bool

const ATTACKER_TRACER := Color(1.0, 0.55, 0.15)
const DEFENDER_TRACER := Color(0.45, 0.85, 1.0)
const BULLET_SPEED := 350.0
## How far out from the stronghold attackers stand to go after a post on its decks or roofs.
const WALL_APPROACH := 15.0

static var _tracer_mats := {}
static var _flash_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D


## Walks up from a physics collider to the node that can take damage.
static func find_damageable(collider: Object) -> Node:
	var n := collider as Node
	while n:
		if n.is_in_group("damageable"):
			return n
		n = n.get_parent()
	return null


static func is_valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and t.is_alive()


## Point to aim at on a target (center mass for characters, center for buildings).
static func aim_point(t: Node3D) -> Vector3:
	if t.has_method("get_aim_point"):
		return t.get_aim_point()
	return t.global_position + Vector3.UP


## Ground out in front of a post on the stronghold's gun decks or roofs (the mountain is centered
## on the map), where attackers outside walk to when they go after it.
static func wall_approach(post: Vector3) -> Vector3:
	var out := Vector3(post.x, 0.0, post.z).normalized()
	return Vector3(post.x, 0.0, post.z) + out * WALL_APPROACH


## True if nothing static blocks the line between two points (ignores `target` itself).
## Smoke screens block it too.
static func has_line_of_sight(ctx: Node3D, from: Vector3, to: Vector3, target: Object = null) -> bool:
	if SmokeCloud.blocks(from, to):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := ctx.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == target


## Fires an instant shot and applies damage to whatever it hits first.
## `visual_from` lets the tracer start at a gun muzzle while the ray starts at the camera.
static func fire_hitscan(shooter: Node3D, from: Vector3, aim_at: Vector3, spread: float, damage: float,
		team: int, structure_mult := 1.0, exclude: Array[RID] = [], visual_from = null, tracer_width := 0.035) -> Dictionary:
	var dir := (aim_at - from).normalized()
	if spread > 0.0:
		dir = apply_spread(dir, spread)
	var to := from + dir * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConfig.LAYER_ALL_SOLID, exclude)
	var hit := shooter.get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	var hurt := false
	if not hit.is_empty():
		end = hit.position
		var d = find_damageable(hit.collider)
		if d and d.team != team and d.is_alive():
			var mult := structure_mult if d.is_in_group("structures") else 1.0
			d.take_damage(damage * mult, team)
			hurt = true
		spawn_impact(shooter, end, hurt)
	var start: Vector3 = visual_from if visual_from != null else from
	spawn_tracer(shooter, start, end, ATTACKER_TRACER if team == GameConfig.TEAM_ATTACKER else DEFENDER_TRACER, tracer_width)
	return {"position": end, "hit": hurt}


static func apply_spread(dir: Vector3, spread: float) -> Vector3:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	var r := spread * sqrt(randf())
	var a := randf() * TAU
	return (basis * Vector3(cos(a) * r, sin(a) * r, -1.0)).normalized()


## Area damage with linear falloff (never below 30% inside the radius).
static func explode(ctx: Node, pos: Vector3, radius: float, damage: float, team: int, structure_mult := 1.0) -> void:
	if damage > 0.0:
		for d in ctx.get_tree().get_nodes_in_group("damageable"):
			if d.team == team or not d.is_alive():
				continue
			var dist := pos.distance_to(aim_point(d))
			var r: float = radius + float(d.get("target_radius") if d.get("target_radius") != null else 0.0)
			if dist > r:
				continue
			var falloff := clampf(1.0 - dist / r, 0.3, 1.0)
			var mult := structure_mult if d.is_in_group("structures") else 1.0
			d.take_damage(damage * falloff * mult, team)
	spawn_explosion(ctx, pos, radius)


# ---------------------------------------------------------------- visual effects

static func _scene_root(ctx: Node) -> Node:
	var root := ctx.get_tree().current_scene
	return root if root else ctx.get_tree().root


static func _tracer_material(color: Color) -> StandardMaterial3D:
	if not _tracer_mats.has(color):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 4.0
		_tracer_mats[color] = m
	return _tracer_mats[color]


static func spawn_tracer(ctx: Node, from: Vector3, to: Vector3, color: Color, width := 0.035) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var seg := minf(length * 0.5, 3.0)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, seg)
	mi.mesh = mesh
	mi.material_override = _tracer_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene_root(ctx).add_child(mi)
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), from + dir * seg * 0.5)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to - dir * seg * 0.5, length / BULLET_SPEED)
	tw.tween_callback(mi.queue_free)


static func _flash_material() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_color = Color(1.0, 0.75, 0.35, 0.9)
		_flash_mat.emission_enabled = true
		_flash_mat.emission = Color(1.0, 0.6, 0.2)
		_flash_mat.emission_energy_multiplier = 6.0
	return _flash_mat


static func _smoke_material() -> StandardMaterial3D:
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_color = Color(0.35, 0.33, 0.3, 0.7)
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return _smoke_mat


static func spawn_impact(ctx: Node, pos: Vector3, hurt: bool) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12 if hurt else 0.07
	s.height = s.radius * 2.0
	s.radial_segments = 6
	s.rings = 3
	mi.mesh = s
	mi.material_override = _flash_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene_root(ctx).add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.12)
	tw.tween_callback(mi.queue_free)


## Short-lived point light for muzzle flashes (used sparingly: player weapons only).
static func spawn_muzzle_light(ctx: Node, pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 2.5
	l.omni_range = 5.0
	_scene_root(ctx).add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.05)
	tw.tween_callback(l.queue_free)


static func spawn_explosion(ctx: Node, pos: Vector3, radius: float) -> void:
	var root := _scene_root(ctx)
	var fireball := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	fireball.mesh = s
	fireball.material_override = _flash_material()
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fireball)
	fireball.global_position = pos
	fireball.scale = Vector3.ONE * radius * 0.2
	var tw := fireball.create_tween()
	tw.tween_property(fireball, "scale", Vector3.ONE * radius * 0.7, 0.18)
	tw.tween_property(fireball, "scale", Vector3.ONE * 0.05, 0.25)
	tw.tween_callback(fireball.queue_free)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 8.0
	light.omni_range = radius * 3.0
	root.add_child(light)
	light.global_position = pos + Vector3.UP
	var tl := light.create_tween()
	tl.tween_property(light, "light_energy", 0.0, 0.5)
	tl.tween_callback(light.queue_free)

	var smoke := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	quad.material = _smoke_material()
	smoke.mesh = quad
	smoke.amount = 18
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.lifetime = 2.2
	smoke.direction = Vector3.UP
	smoke.spread = 60.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = radius * 0.9
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.damping_min = 1.5
	smoke.damping_max = 2.5
	smoke.scale_amount_min = radius * 0.4
	smoke.scale_amount_max = radius * 0.8
	var fade := Gradient.new()
	fade.set_color(0, Color(0.4, 0.37, 0.33, 0.8))
	fade.set_color(1, Color(0.4, 0.37, 0.33, 0.0))
	smoke.color_ramp = fade
	root.add_child(smoke)
	smoke.global_position = pos
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)
