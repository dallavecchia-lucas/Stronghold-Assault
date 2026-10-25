class_name FlameTrooper
extends SquadTrooper
## One trooper of a Flame Squad (FlameSquad): the Crimson Warden, twin fuel tanks on her back and a
## flame gun at her right hip. Walks and aims like every squad trooper (SquadTrooper); the squad says
## when to burn (trigger).
##
## The flame: a jet out of the nozzle toward the aim, REACH ahead of the trooper (less where a wall,
## the ground or a trunk stops it). Attackers in it burn (DPS, and keep burning AFTERBURN seconds
## once out of it: FireFX.set_alight); a tree it plays on heats up (ForestTree.scorch) and catches
## once the flame has been held on it long enough. Burning runs the tanks' pressure down; it comes
## back while the trigger is off. Run dry, the gun vents for VENT_TIME before it lights again.
##
## The rigged model's clips come from tools/blender/rig_flame_trooper.py.

const MODEL := "res://assets/defenders/crimson_warden/flame_trooper_rigged.glb"
const MAX_HP := 340.0
const PITCH_MIN := deg_to_rad(-30.0)
const PITCH_MAX := deg_to_rad(42.0)
## How high the gun is held (m): the body bends to bring it level with what it burns.
const GUN_HEIGHT := 0.75
## How far ahead the flame goes (m), and how wide it is at the nozzle and at its tip.
const REACH := 6.0
const WIDTH_NOZZLE := 0.15
const WIDTH_TIP := 0.85
## Damage a second to an attacker in the flame; once out of it, it burns on for AFTERBURN seconds
## at AFTERBURN_DPS.
const DPS := 90.0
const AFTERBURN := 2.5
const AFTERBURN_DPS := 14.0
## Pressure: seconds of flame from full, seconds to come back from empty; run dry, the gun vents.
const PRESSURE_TIME := 14.0
const RECOVER_TIME := 6.0
const VENT_TIME := 2.0
## The flame bends this far off the barrel toward the aim (rad); further off it, it won't light.
const AIM_BEND := deg_to_rad(22.0)
const AIM_TOLERANCE := deg_to_rad(40.0)
## A squad mate this close to the flame holds the trooper's fire (m).
const FRIENDLY_CLEARANCE := 0.8
## Flame puffs a second, and how long one takes to reach the tip (s).
const PUFF_RATE := 130.0
const PUFF_LIFE := 0.36
const PUFF_DRAG := 1.4
## Layers that stop the flame (trees are world).
const STOP_MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES

var trigger := false
## Damage is DPS times this (the squad turns it down while nobody drives it).
var damage_scale := 1.0
## 0..1: how much flame is left in the tanks.
var pressure := 1.0
## Burning this frame, where the flame stops, and the tree it is heating (null: none).
var flaming := false
var flame_end := Vector3.ZERO
var flame_tree: ForestTree = null
## Seconds of flame this trooper has held on trees, and attackers it has set alight (the
## showcase checks them).
var stats := {"flame": 0.0, "on_trees": 0.0, "alight": 0}

var _vent := 0.0
var _gun_tilt := 0.0
var _emit := 0.0
var _splash := 0.0
var _light: OmniLight3D
var _flicker := 0.0


func _init() -> void:
	max_hp = MAX_HP
	hp = MAX_HP


func _model_path() -> String:
	return MODEL


func _new_rig() -> TrooperRig:
	return FlameRig.new()


func _build_weapon() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.22)
	_light.omni_range = 8.0
	_light.light_energy = 0.0
	_light.top_level = true
	_light.visible = false
	add_child(_light)
	# How far below level the barrel points in the clips (the gun is held at the hip, nose down).
	var g := _skel.get_bone_global_rest(_skel.find_bone("nozzle")).basis.y.normalized()
	_gun_tilt = asin(clampf(g.y, -1.0, 1.0))


## The gun is held at the hip: the body bends to point it at the aim from there (the pitch from the
## chest would aim it into the ground at anything close).
func _spine_pitch(_pitch: float) -> float:
	var d := aim_point - (global_position + Vector3.UP * GUN_HEIGHT)
	var pitch := atan2(d.y, maxf(Vector2(d.x, d.z).length(), 1.5))
	return clampf(pitch - _gun_tilt, PITCH_MIN, PITCH_MAX)


func _weapon_down() -> void:
	trigger = false
	flaming = false
	_release_tree()
	_light.visible = false


func venting() -> bool:
	return _vent > 0.0


func nozzle() -> Transform3D:
	return (_rig as FlameRig).nozzle()


## Which way the flame goes: toward the aim (_aim_way), bent at most AIM_BEND off the barrel.
func flame_dir() -> Vector3:
	var barrel := nozzle().basis.y.normalized()
	var want := _aim_way()
	var off := barrel.angle_to(want)
	if off <= AIM_BEND or off < 0.001:
		return want
	return barrel.slerp(want, AIM_BEND / off).normalized()


## The way to the aim from the nozzle. Looking the way the camera looks (aim_parallel), the
## camera's heading, rising or falling to the aim.
func _aim_way() -> Vector3:
	var to := aim_point - nozzle().origin
	if not aim_parallel:
		return to.normalized()
	var flat := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized() * maxf(Vector2(to.x, to.z).length(), 1.5)
	return (flat + Vector3.UP * to.y).normalized()


func _weapon_tick(delta: float) -> void:
	if _vent > 0.0:
		_vent -= delta
	var on := trigger and _vent <= 0.0 and pressure > 0.0 and _line_clear()
	if on:
		pressure -= delta / PRESSURE_TIME
		if pressure <= 0.0:
			pressure = 0.0
			_vent = VENT_TIME
		_burn(delta)
	else:
		if not trigger or _vent > 0.0:
			pressure = minf(pressure + delta / RECOVER_TIME, 1.0)
		if flaming:
			_release_tree()
		flaming = false
	_light.visible = flaming
	if _vent > 0.0 and randf() < delta * 10.0:
		SmokeCloud.wisp(self, nozzle().origin, 0.6)


## True if the barrel is about on the aim and no squad mate stands in the flame.
func _line_clear() -> bool:
	var xf := nozzle()
	var from := xf.origin
	if xf.basis.y.normalized().angle_to(_aim_way()) > AIM_TOLERANCE:
		return false
	var dir := flame_dir()
	for g in get_tree().get_nodes_in_group("troopers"):
		if g == self:
			continue
		var p: Vector3 = g.global_position + Vector3.UP * HEIGHT * 0.5
		var t := clampf((p - from).dot(dir), 0.0, REACH)
		if (from + dir * t).distance_to(p) < FRIENDLY_CLEARANCE + RADIUS:
			return false
	return true


## The flame this physics frame: where it stops, the tree it heats, the attackers it burns, and
## its puffs and light.
func _burn(delta: float) -> void:
	flaming = true
	stats.flame += delta
	var from := nozzle().origin
	var dir := flame_dir()
	var reach := REACH
	var tree: ForestTree = null
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH, STOP_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		reach = from.distance_to(hit.position)
		tree = hit.collider as ForestTree
	# The jet is wider than the ray: a trunk it brushes counts too.
	if tree == null:
		var near := _trunk_in_flame(from, dir, reach)
		if near[0] != null:
			tree = near[0]
			reach = near[1]
	flame_end = from + dir * reach
	if tree != flame_tree:
		_release_tree()
		flame_tree = tree
	if tree != null and tree.is_standing():
		stats.on_trees += delta
		tree.scorch(delta, flame_end)
	_hurt(from, dir, reach, delta)
	_puffs(from, dir, reach, tree, delta)


## The nearest standing trunk the jet brushes before `reach`: [tree, distance] (tree null: none).
func _trunk_in_flame(from: Vector3, dir: Vector3, reach: float) -> Array:
	var best: ForestTree = null
	var best_t := reach
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.2:
		return [null, reach]
	for tr in ForestTree.standing:
		var rel := Vector2(tr.global_position.x - from.x, tr.global_position.z - from.z)
		if rel.length() > reach + 1.0:
			continue
		var t := rel.dot(flat) / flat.length_squared()
		if t <= 0.0 or t >= best_t:
			continue
		var width := lerpf(WIDTH_NOZZLE, WIDTH_TIP, t / REACH) * 0.5
		var off := (rel - flat * t).length()
		var y := from.y + dir.y * t - tr.global_position.y
		if off < ForestTree.TRUNK_RADIUS + width and y > 0.0 and y < tr.height * 0.5:
			best = tr
			best_t = t
	return [best, best_t]


func _release_tree() -> void:
	flame_tree = null


## Attackers in the jet burn, and keep burning a moment after.
func _hurt(from: Vector3, dir: Vector3, reach: float, delta: float) -> void:
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if not u.is_alive() or u.team == team:
			continue
		var p := Combat.aim_point(u)
		var t := (p - from).dot(dir)
		if t < -0.3 or t > reach + 0.4:
			continue
		var width := lerpf(WIDTH_NOZZLE, WIDTH_TIP, clampf(t / REACH, 0.0, 1.0)) * 0.5
		var r: float = float(u.get("target_radius") if u.get("target_radius") != null else 0.4)
		if (from + dir * clampf(t, 0.0, reach)).distance_to(p) > width + r + 0.3:
			continue
		u.take_damage(DPS * damage_scale * delta, team)
		if FireFX.of(self).set_alight(u, AFTERBURN, AFTERBURN_DPS * damage_scale, team):
			stats.alight += 1


## The jet: puffs that leave the nozzle fast and slow down, reaching the tip as they burn out;
## where something stops the flame, it splashes (up a trunk, licking round it).
func _puffs(from: Vector3, dir: Vector3, reach: float, tree: ForestTree, delta: float) -> void:
	var fx := FireFX.of(self)
	var full := reach >= REACH - 0.05
	# Speed for a puff to cover `reach` in its life, slowed by drag the whole way.
	var v0 := reach * PUFF_DRAG / (1.0 - exp(-PUFF_DRAG * PUFF_LIFE))
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	_emit += delta * PUFF_RATE
	while _emit >= 1.0:
		_emit -= 1.0
		var jitter := basis * Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.05
		var life := PUFF_LIFE * randf_range(0.8, 1.15)
		var at := from + dir * randf_range(0.0, v0 * delta)
		fx.flame(at, (dir + jitter).normalized() * v0 * randf_range(0.92, 1.05), life,
				randf_range(0.12, 0.2), (WIDTH_TIP + 0.25) * reach / REACH + randf_range(0.15, 0.45), 1.2 if full else 0.4, PUFF_DRAG)
	if not full:
		_splash += delta * 26.0
		while _splash >= 1.0:
			_splash -= 1.0
			var up := randf_range(2.5, 4.5) if tree else randf_range(1.0, 2.2)
			var side := basis * Vector3(randf_range(-1, 1), 0.0, 0.0) * (1.4 if tree else 2.2)
			fx.flame(flame_end - dir * 0.3, side + Vector3.UP * up, randf_range(0.3, 0.55), 0.35, randf_range(0.9, 1.4), 1.5, 1.5)
	if randf() < delta * 4.0:
		fx.smoke(flame_end + Vector3.UP * 0.6, Vector3(0.0, 1.4, 0.0) + dir * 1.5, randf_range(1.2, 2.0), 0.4, 1.6)
	_flicker = lerpf(_flicker, randf(), 0.4)
	_light.global_position = from + dir * reach * 0.55 + Vector3.UP * 0.4
	_light.light_energy = 2.2 + 1.6 * _flicker
