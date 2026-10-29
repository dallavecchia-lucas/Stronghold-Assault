class_name LionessBlast
extends Node3D
## The Armored Lioness's fire blast (UnitTypes blast_*): the two flamethrowers on her back burn a cone
## ahead of her for blast_duration seconds. The cone always points where her face looks: she can move
## meanwhile, and it turns with her. It is wide (blast_angle either side, out to blast_range) and low,
## the flames leaving the barrels over her head and rolling forward onto the ground.
##
## Defenders in the cone (in sight of the barrels: walls, the ground and trunks stop it) burn,
## blast_dps, and keep burning blast_afterburn seconds after (FireFX.set_alight). It never sets
## vegetation alight: the flames lick round the trees they meet and go out (it never scorches a
## ForestTree, unlike the Flame Squads' jets).
##
## Puffs go through FireFX like the Flame Troopers' jets.

## Flame puffs a second per nozzle, how long one lives (s) and its drag (1/s).
const PUFF_RATE := 95.0
const PUFF_LIFE := 0.5
const PUFF_DRAG := 1.6
## The cone is lower than it is wide: the flames spread this share of blast_angle up and down.
const FLAT := 0.32
## The cone's middle dips this far below level (rad), so it reaches the ground at its tip.
const DIP := deg_to_rad(7.0)
## Defenders this much above or below the barrels' line at their distance (rad) are out of it.
const REACH_UP := deg_to_rad(16.0)
## What stops the flames (trees are on the world layer).
const STOP_MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES

var unit: AttackerUnit
## Seconds of flame left.
var left := 0.0
## Defenders set alight and damage dealt (the showcase checks them).
var stats := {"alight": 0, "damage": 0.0}

var _emit := 0.0
var _light: OmniLight3D
var _flicker := 0.0


func _ready() -> void:
	top_level = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.22)
	_light.omni_range = 11.0
	_light.light_energy = 0.0
	add_child(_light)


## The way the cone points: where she faces, dipping a little toward the ground.
func direction() -> Vector3:
	var fwd := -unit.global_basis.z
	fwd.y = 0.0
	return (fwd.normalized() * cos(DIP) + Vector3.DOWN * sin(DIP)).normalized()


## True if `p` is inside the cone (flat angle and distance, and not too far above or below it).
func covers(p: Vector3) -> bool:
	return _inside(unit.nozzle(0).origin, p)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(unit) or not unit.is_alive() or left <= 0.0:
		queue_free()
		return
	left -= delta
	_burn(delta)
	_puffs(delta)


## Defenders in the cone burn, and keep burning a moment after.
func _burn(delta: float) -> void:
	var from := unit.nozzle(0).origin
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if d.team == unit.team or not d.is_alive():
			continue
		var p := Combat.aim_point(d)
		if not _inside(from, p) or not Combat.has_line_of_sight(unit, from, p, d):
			continue
		var dmg: float = unit.stats.blast_dps * delta
		d.take_damage(dmg, unit.team)
		stats.damage += dmg
		if FireFX.of(self).set_alight(d, unit.stats.blast_afterburn, unit.stats.blast_afterburn_dps, unit.team):
			stats.alight += 1


## Inside the cone from `from`: within blast_range and blast_angle of where it points (flat), and
## within REACH_UP of its middle line up or down.
func _inside(from: Vector3, p: Vector3) -> bool:
	var to := p - from
	var flat := Vector2(to.x, to.z)
	var dist := flat.length()
	if dist > unit.stats.blast_range:
		return false
	var d := direction()
	if dist > 0.5 and absf(Vector2(d.x, d.z).angle_to(flat)) > unit.stats.blast_angle:
		return false
	var level := from.y - tan(DIP) * dist
	return absf(atan2(p.y - level, maxf(dist, 0.5))) <= REACH_UP


## The flames: puffs from each nozzle spread over the cone, slowing as they go and reaching its tip as
## they burn out (sooner where a wall or the ground stops them, splashing there); the light flickers.
func _puffs(delta: float) -> void:
	var fx := FireFX.of(self)
	var d := direction()
	var basis := Basis.looking_at(d, Vector3.UP)
	var reach: float = unit.stats.blast_range
	var angle: float = unit.stats.blast_angle
	# The cone's middle stops at a wall or the ground ahead (not at a lone trunk: the flames go round it).
	var from0 := unit.nozzle(0).origin
	var q := PhysicsRayQueryParameters3D.create(from0, from0 + d * reach, STOP_MASK, [unit.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var stop := reach
	if not hit.is_empty() and not hit.collider is ForestTree:
		stop = from0.distance_to(hit.position)
	# Moving with her, the flames keep up.
	var carry := Vector3(unit.velocity.x, 0.0, unit.velocity.z)
	_emit += delta * PUFF_RATE
	while _emit >= 1.0:
		_emit -= 1.0
		for k in 2:
			var xf := unit.nozzle(k)
			var a := randf_range(-1.0, 1.0)
			var b := randf_range(-1.0, 1.0)
			var way := (basis * Vector3(tan(angle * a), tan(angle * FLAT * b), -1.0)).normalized()
			var go := stop * randf_range(0.75, 1.0)
			var life := PUFF_LIFE * randf_range(0.8, 1.15)
			# Speed for a puff to cover `go` in its life, slowed by drag the whole way.
			var v0 := go * PUFF_DRAG / (1.0 - exp(-PUFF_DRAG * life))
			var at := xf.origin + way * randf_range(0.0, 0.5)
			fx.flame(at, way * v0 + carry, life, randf_range(0.18, 0.3), 0.7 + go * 0.22 + randf_range(0.0, 0.5), 0.9, PUFF_DRAG)
	if stop < reach - 0.1 and randf() < delta * 30.0:
		var end := from0 + d * stop
		fx.flame(end - d * 0.3, Vector3(randf_range(-2.0, 2.0), randf_range(1.5, 3.5), randf_range(-2.0, 2.0)), randf_range(0.3, 0.55), 0.4, randf_range(1.0, 1.6), 1.5, 1.5)
	if randf() < delta * 5.0:
		fx.smoke(from0 + d * stop * 0.8 + Vector3.UP * 0.6, Vector3(0.0, 1.6, 0.0) + d * 1.5 + carry, randf_range(1.2, 2.0), 0.5, 2.0)
	_flicker = lerpf(_flicker, randf(), 0.4)
	_light.global_position = from0 + d * stop * 0.5 + Vector3.UP * 0.3
	_light.light_energy = 3.0 + 2.0 * _flicker
