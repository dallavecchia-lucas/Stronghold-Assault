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


## Walks up from a physics collider to the node that can take damage. A collider kept elsewhere in the tree (a
## bridge's body is under the navigation region, to be baked into the navmesh) names it in its "damageable" meta.
static func find_damageable(collider: Object) -> Node:
	var n := collider as Node
	while n:
		if n.is_in_group("damageable"):
			return n
		if n.has_meta("damageable"):
			var d = n.get_meta("damageable")
			return d if is_instance_valid(d) and d.is_in_group("damageable") else null
		n = n.get_parent()
	return null


static func is_valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and t.is_alive()


## A live target that basic attacks can pick: not an infiltrator under adaptive camo
## (InfiltratorTrooper.camouflaged). Area damage doesn't ask.
static func targetable(t) -> bool:
	return is_valid_target(t) and not t.get("camouflaged")


## Low profile (InfiltratorTrooper): attackers never pick it out on their own, only when ordered to
## attack it.
static func low_profile(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var v = t.get("low_profile")
	return v is bool and v


## The aircraft a defender the PLAYER is driving may lock onto: every flyer in "air_units" (all the garrison's own anti-air ever
## looks up) and the attackers' transport helicopters (TransportHelo), which nothing on its own ever targets: idle posts,
## squads, machines and drones, and the AA turrets, never go after one. Going after a helicopter is the player's choice.
static func aircraft_for_player(ctx: Node) -> Array:
	var out: Array = []
	out.append_array(ctx.get_tree().get_nodes_in_group("air_units"))
	out.append_array(ctx.get_tree().get_nodes_in_group("transport_helos"))
	return out


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
## Smoke screens block it too, and the murky water over a bear diving under it (AttackerUnit.is_submerged):
## nobody picks it out down there, though a round that goes in where it is still hits it.
static func has_line_of_sight(ctx: Node3D, from: Vector3, to: Vector3, target: Object = null) -> bool:
	if target != null and is_instance_valid(target) and target.has_method("is_submerged") and target.is_submerged():
		return false
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
	# The defenders' rounds pass through their own people (the garrison stands in rows round the base, in front of
	# the guns and of each other); the attackers' stop on whatever body they meet.
	var mask := GameConfig.LAYER_ALL_SOLID
	if team == GameConfig.TEAM_DEFENDER:
		mask &= ~GameConfig.LAYER_DEFENDERS
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
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
		spawn_impact(shooter, end, hurt, hit.normal)
	var start: Vector3 = visual_from if visual_from != null else from
	spawn_tracer(shooter, start, end, ATTACKER_TRACER if team == GameConfig.TEAM_ATTACKER else DEFENDER_TRACER, tracer_width)
	return {"position": end, "hit": hurt}


## A shot at an aircraft that has no body to collide with (the defenders' drones: only AA damage and the bears
## can hurt them, so nothing else's rounds or blasts reach them). The round flies off `spread` wide of the aim
## and hits if it passes within the target's hit_radius of its aim point with no wall or hill in the way.
## Returns whether it hit.
static func fire_at_air(shooter: Node3D, from: Vector3, target: Node3D, spread: float, damage: float,
		team: int, visual_from = null, tracer_width := 0.035) -> bool:
	var aim := aim_point(target)
	var dir := (aim - from).normalized()
	if spread > 0.0:
		dir = apply_spread(dir, spread)
	var reach := from.distance_to(aim)
	# Where the round passes the target: the closest point of its line to the aim point.
	var along := clampf((aim - from).dot(dir), 0.0, reach + 2.0)
	var closest := from + dir * along
	var radius := 1.0
	var r = target.get("hit_radius")
	if r != null:
		radius = float(r)
	var hit := closest.distance_to(aim) <= radius
	var end := closest if hit else from + dir * (reach + 30.0)
	var q := PhysicsRayQueryParameters3D.create(from, end, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var wall := shooter.get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		hit = false
		end = wall.position
		spawn_impact(shooter, end, false, wall.normal)
	elif hit:
		target.take_damage(damage, team)
		spawn_impact(shooter, end, true)
	var start: Vector3 = visual_from if visual_from != null else from
	spawn_tracer(shooter, start, end, ATTACKER_TRACER if team == GameConfig.TEAM_ATTACKER else DEFENDER_TRACER, tracer_width)
	return hit


static func apply_spread(dir: Vector3, spread: float) -> Vector3:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	var r := spread * sqrt(randf())
	var a := randf() * TAU
	return (basis * Vector3(cos(a) * r, sin(a) * r, -1.0)).normalized()


## Area damage with linear falloff (never below 30% inside the radius).
static func explode(ctx: Node, pos: Vector3, radius: float, damage: float, team: int, structure_mult := 1.0) -> void:
	damage_area(ctx, pos, radius, damage, team, structure_mult)
	spawn_explosion(ctx, pos, radius)


## explode() without the blast: the damage only.
static func damage_area(ctx: Node, pos: Vector3, radius: float, damage: float, team: int, structure_mult := 1.0) -> void:
	if damage <= 0.0:
		return
	for d in ctx.get_tree().get_nodes_in_group("damageable"):
		if d.team == team or not d.is_alive():
			continue
		# Something long (a bridge) says how far the blast is from it.
		var dist: float = d.blast_distance(pos) if d.has_method("blast_distance") else pos.distance_to(aim_point(d))
		var r: float = radius + float(d.get("target_radius") if d.get("target_radius") != null else 0.0)
		if dist > r:
			continue
		var falloff := clampf(1.0 - dist / r, 0.3, 1.0)
		var mult := structure_mult if d.is_in_group("structures") else 1.0
		d.take_damage(damage * falloff * mult, team)


# ---------------------------------------------------------------- visual effects
# All drawn by the scene's FX (scripts/fx/fx.gd).

static var _smoke_mat: StandardMaterial3D


static func _scene_root(ctx: Node) -> Node:
	var root := ctx.get_tree().current_scene
	return root if root else ctx.get_tree().root


## Billboard smoke for CPUParticles3D (the intro's burning city).
static func _smoke_material() -> StandardMaterial3D:
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_color = Color(0.35, 0.33, 0.3, 0.7)
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.albedo_texture = SmokeCloud.puff_texture()
	return _smoke_mat


static func spawn_tracer(ctx: Node, from: Vector3, to: Vector3, color: Color, width := 0.035) -> void:
	FX.of(ctx).tracer(from, to, color, width, BULLET_SPEED)


## A round striking at `pos`: sparks and a puff of dust off the surface facing `normal` (zero: unknown), a
## brighter spark when it `hurt` someone.
static func spawn_impact(ctx: Node, pos: Vector3, hurt: bool, normal := Vector3.ZERO) -> void:
	FX.of(ctx).impact(pos, normal, hurt)


## A gun's muzzle flash at `pos`, the barrel along `dir` (zero: a star all round); `size` 1: a rifle's.
static func spawn_muzzle_flash(ctx: Node, pos: Vector3, dir: Vector3, size := 1.0, with_light := false) -> void:
	FX.of(ctx).muzzle_flash(pos, dir, size, with_light)


## A cannon, mortar or launcher going off at `pos` toward `dir`; `size` 1: a field gun's.
static func spawn_muzzle_blast(ctx: Node, pos: Vector3, dir: Vector3, size := 1.0) -> void:
	FX.of(ctx).muzzle_blast(pos, dir, size)


## Short-lived light for muzzle flashes (used sparingly: player weapons only).
static func spawn_muzzle_light(ctx: Node, pos: Vector3) -> void:
	FX.of(ctx).light(pos, Color(1.0, 0.78, 0.45), Color(1.0, 0.55, 0.25), 2.6, 6.0, 0.07, 2.0, 0.0)


## A blast of `radius` at `pos` (FX.blast): fireball, smoke, sparks, debris, its light, dust and a scorch mark
## on the ground, the camera shaken. `air`: it went off in the air.
static func spawn_explosion(ctx: Node, pos: Vector3, radius: float, air := false) -> void:
	FX.of(ctx).blast(pos, radius, NAN, air)
