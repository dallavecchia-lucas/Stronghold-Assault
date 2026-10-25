class_name AttackerUnit
extends CharacterBody3D
## One attacking unit. Driven entirely by its current order:
##   {"type": "idle"}
##   {"type": "move", "pos": Vector3}          go there, ignore enemies
##   {"type": "attack_move", "pos": Vector3}   go there, fight anything in range
##   {"type": "attack", "target": Node3D}      chase and destroy a specific target
##   {"type": "raid"}                          raider inside the stronghold, on its own (_raid_target)
## Behaviour differences per unit come from UnitTypes role (infantry, melee, artillery,
## healer, flying, anti_air).

signal died(unit: AttackerUnit)

const HEAL_COLOR := Color(0.35, 1.0, 0.45)
const AA_COLOR := Color(1.0, 0.9, 0.4)
## How close to a broken gate an order has to land to send infiltrators in.
const BREACH_REACH := 12.0
## Collision radius of infiltrators (the navmesh is baked for 0.5 m).
const INSIDE_RADIUS := 0.35
## Ledges infiltrators step up onto (the step between the stronghold's corridors and halls).
const STEP_HEIGHT := 0.4
## How far past its own radius a ramming unit runs enemy soldiers over.
const TRAMPLE_REACH := 0.7
## Seconds before a ram can run over the same soldier again.
const TRAMPLE_REPEAT := 1.0
## A raiding ram rams a soldier it hunts once it is this close (m), if its ram is ready.
const RAID_RAM_REACH := 16.0
## raid_keep raiders turn aside for defenders this close (m); the others don't hold them up.
const RAID_DETOUR := 18.0

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
## Seconds until the smoke screen can be used again.
var smoke_cd := 0.0
## Seconds until the missile salvo can be fired again.
var missile_cd := 0.0
## Seconds of firing the guns have built up toward overheat_time.
var heat := 0.0
## Seconds until the ram can be used again.
var ram_cd := 0.0
## Seconds until the bombardment can be fired again.
var bombard_cd := 0.0
## Gate this ram is charging (RamCharge), and its slot across the doorway.
var charge_gate: Structure = null:
	set(g):
		charge_gate = g
		if _agent:
			# Chargers run straight for their slots: avoidance would jam them in the doorway.
			_agent.avoidance_enabled = g == null and is_alive() and not is_flying()
var charge_slot := 0
## Raider inside the stronghold: fights on its own and takes no more orders.
var raiding := false
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
var _turrets: ElephantTurrets  # set when the model carries flak cannons (stats.flak)
var _next_gun := 0
## Missile salvo under way: tubes still to fire, and at what.
var _salvo: Array[int] = []
var _salvo_target: Node3D
var _salvo_target_id := 0
var _salvo_cd := 0.0
var _cluster_left := 0.0
var _cluster_cd_shot := 0.0
var _cluster_aim := Vector3.ZERO
var _overheat_left := 0.0
## Bombardment under way: where the shell goes, seconds left standing (laying the gun, then
## holding after the shot), and whether it has fired.
var _bombard_aim := Vector3.ZERO
var _bombard_left := 0.0
var _bombard_fired := false
## The model's muzzle bone (bombardment), when it has one.
var _muzzle_skel: Skeleton3D
var _muzzle_bone := -1
var _ram_left := 0.0
var _charge_pos := Vector3.ZERO
## Soldiers run over during this ram: instance id -> msec, so each is hit once per pass.
var _trampled := {}
var _dust_cd := 0.0
var _butt := 0.0
var _wisp_cd := 0.0
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _fire_cd := 0.0
var _retarget_cd := 0.0
## False while the target is a buried structure out of sight: keep closing in instead of firing.
var _sees_target := true
var _anim_t := 0.0
## Navigation link being crossed (LevelBuilder): points still to climb or walk through.
var _route: Array[Vector3] = []
var _route_breach_in := false
var _in_forest := false
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


## Chimps and breaching rams are the only units that get inside the stronghold.
func fits_inside() -> bool:
	return stats.get("infiltrator", false)


## Raiders inside the stronghold are on their own.
func is_controllable() -> bool:
	return is_alive() and not raiding


## Medics, rhinos, elephants and bisons never shoot at what they are ordered to attack.
func has_basic_attack() -> bool:
	return role != "healer" and role != "anti_air" and role != "siege"


func has_cluster_bomb() -> bool:
	return stats.has("cluster_cooldown")


func cluster_ready() -> bool:
	return has_cluster_bomb() and cluster_cd <= 0.0


func has_smoke() -> bool:
	return stats.has("smoke_cooldown")


func smoke_ready() -> bool:
	return has_smoke() and smoke_cd <= 0.0


func is_overheated() -> bool:
	return _overheat_left > 0.0


func has_missiles() -> bool:
	return stats.has("missile_cooldown")


func missiles_ready() -> bool:
	return has_missiles() and missile_cd <= 0.0 and is_alive()


## Damage of one salvo if every missile hits.
func salvo_damage() -> float:
	return stats.missile_count * stats.missile_damage


func in_missile_range(t: Node3D) -> bool:
	var d := t.global_position - global_position
	return Vector2(d.x, d.z).length() <= stats.missile_range


func has_bombard() -> bool:
	return stats.has("bombard_cooldown")


func bombard_ready() -> bool:
	return has_bombard() and bombard_cd <= 0.0 and is_alive()


## Standing still to lay the gun or after the shot.
func is_bombarding() -> bool:
	return _bombard_left > 0.0


func has_ram() -> bool:
	return stats.has("ram_cooldown")


func ram_ready() -> bool:
	return has_ram() and ram_cd <= 0.0 and is_alive()


func is_ramming() -> bool:
	return _ram_left > 0.0


func ram_left() -> float:
	return _ram_left


## How far the ram still carries it: a charge at a gate further than this can't make it in time.
func ram_reach() -> float:
	return _ram_left * stats.speed * stats.ram_speed


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
	if fits_inside():
		# Slimmer than the navmesh's agent radius, so paths hugging the stronghold's inside
		# corners don't snag on them.
		cap.radius = minf(stats.radius, INSIDE_RADIUS)
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
	if fits_inside():
		_agent.navigation_layers |= LevelBuilder.NAV_INFILTRATORS
		_agent.link_reached.connect(_on_link_reached)
	add_child(_agent)

	_build_model()
	_build_ring()
	_build_hp_bar()
	_retarget_cd = randf() * 0.3


# ---------------------------------------------------------------- orders

func set_order(o: Dictionary) -> void:
	if raiding:
		return
	charge_gate = null  # a new order calls off a charge (RamCharge hands slots out after this)
	# Only infiltrators can reach the keep: the rest close in on the nearest broken gate.
	if o.type == "attack" and o.target.get("buried") and not fits_inside():
		var gate := _nearest_breach()
		o = {"type": "attack_move", "pos": gate.start_position} if gate else {"type": "idle"}
	# Medics and rhinos don't attack: follow the attack to its target instead.
	if not has_basic_attack() and o.type == "attack":
		o = {"type": "attack_move", "pos": _approach(o.target)}
	# Infiltrators sent to a broken gate go in: raiders as far as the tunnel (then they are on
	# their own), the others on to the keep.
	if fits_inside() and o.has("pos"):
		var breach := _breach_near(o.pos)
		if breach:
			var keep := _keep()
			if stats.get("raider", false) or keep == null:
				o = {"type": "move", "pos": breach.end_position}
			else:
				o = {"type": "attack", "target": keep}
	order = o
	if o.type == "attack":
		target = o.target
	elif o.type == "move":
		target = null
	if o.has("pos") and not is_flying():
		_agent.target_position = o.pos


func is_idle() -> bool:
	return not raiding and order.type == "idle" and not Combat.is_valid_target(target)


## Open breach link whose outside end is near `pos`, or null.
func _breach_near(pos: Vector3) -> NavigationLink3D:
	for link in get_tree().get_nodes_in_group("breaches"):
		if link.enabled and pos.distance_to(link.start_position) <= BREACH_REACH:
			return link
	return null


func _nearest_breach() -> NavigationLink3D:
	var best: NavigationLink3D = null
	for link in get_tree().get_nodes_in_group("breaches"):
		if link.enabled and (best == null or global_position.distance_to(link.start_position) < global_position.distance_to(best.start_position)):
			best = link
	return best


func _keep() -> Structure:
	for s in get_tree().get_nodes_in_group("structures"):
		if s.buried and s.is_alive():
			return s
	return null


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
	_bombard_left = 0.0
	end_ram()
	_route.clear()
	_end_salvo()
	if _turrets:
		_turrets.target = null
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
	if role == "melee":
		return true  # within arm's reach
	if t.get("buried"):
		return not is_flying() and Combat.has_line_of_sight(self, _eye(), Combat.aim_point(t), t)
	if role == "artillery" or t.is_in_group("structures"):
		return true  # shells arc over walls; buildings are big enough to always hit
	return Combat.has_line_of_sight(self, _eye(), Combat.aim_point(t), t)


func _update_target() -> void:
	if not has_basic_attack():
		target = null
		return
	if raiding:
		target = _raid_target()
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


## Raider: the nearest defender in the stronghold (the gun decks, the roofs, the player's soldier
## wherever they are). With all of them down, the nearest machine: the gate machine guns on the
## decks and the mortar on the roof. raid_keep raiders only fight the defenders near them and
## otherwise go for the keep. Sticks to its pick until something it prefers shows up.
func _raid_target() -> Node3D:
	var soldiers := []
	var machines := []
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if not d.is_alive():
			continue
		match d.get("station_kind"):
			"soldier": soldiers.append(d)
			"mg", "artillery": machines.append(d)
	if stats.get("raid_keep", false):
		# Only the defenders it runs into on the way: the rest of the time it makes for the keep.
		soldiers = soldiers.filter(func(d): return global_position.distance_to(d.global_position) <= RAID_DETOUR)
		var keep := _keep()
		machines = [keep] if keep else []
	var pool := soldiers if not soldiers.is_empty() else machines
	if target in pool:
		return target
	var best: Node3D = null
	var best_d := INF
	for d in pool:
		var dist := global_position.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _start_raid() -> void:
	raiding = true
	selected = false
	formation_id = 0
	order = {"type": "raid"}
	target = _raid_target()


func _fire_at(t: Node3D) -> void:
	_fire_cd = stats.fire_interval * randf_range(0.9, 1.15)
	_recoil = 1.0
	match role:
		"melee":
			var mult: float = stats.structure_mult if t.is_in_group("structures") else 1.0
			t.take_damage(stats.damage * mult, team)
			var to := t.global_position - global_position
			to.y = 0.0
			Combat.spawn_impact(self, global_position + to.normalized() * (stats.radius + 0.5) + Vector3.UP * stats.height * 0.6, true)
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
			var aim := Combat.aim_point(t)
			if stats.has("suppress_radius"):
				# Spray: aim somewhere around the target, so neighbours catch rounds too.
				var r: float = stats.suppress_radius * sqrt(randf())
				var a := randf() * TAU
				aim += Vector3(cos(a) * r, randf_range(-0.4, 0.4) * stats.suppress_radius, sin(a) * r)
			# Shotguns fire a blast of pellets, each on its own line within the cone.
			for _pellet in stats.get("pellets", 1):
				Combat.fire_hitscan(self, _eye(), aim, stats.spread, stats.damage, team,
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


## Rhino and elephant passive: stay locked on one enemy flyer until it dies or leaves aa_range,
## then pick the nearest one in range.
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
	if _turrets:
		_turrets.target = _aa_lock
		_turrets.radar_speed = 4.0 if _aa_lock else 0.9
		if _aa_lock:
			_fire_flak()
	elif _aa_lock:
		_aa_lock.take_damage(stats.aa_dps * stats.fire_interval, team)
		Combat.spawn_tracer(self, _eye(), Combat.aim_point(_aa_lock), AA_COLOR)


## Elephant: the flak cannons take turns, each firing only once it is on target.
func _fire_flak() -> void:
	for gun in [_next_gun, 1 - _next_gun]:
		if _turrets.aimed(gun):
			_next_gun = 1 - gun
			_turrets.kick(gun)
			Flak.fire(self, _turrets.muzzle(gun), _aa_lock, stats.aa_dps * stats.fire_interval, team)
			return


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


## Bison active: stand still, lay the gun on `aim` and fire one heavy shell at it, then carry on
## with the order. `aim` should be within bombard_range (RhinoAim.bombard). False while reloading.
func start_bombard(aim: Vector3) -> bool:
	if not bombard_ready():
		return false
	bombard_cd = stats.bombard_cooldown
	_bombard_aim = aim
	_bombard_left = stats.bombard_aim_time + stats.bombard_hold
	_bombard_fired = false
	return true


func _bombard_tick(delta: float) -> void:
	_bombard_left -= delta
	if not _bombard_fired and _bombard_left <= stats.bombard_hold:
		_bombard_fired = true
		_fire_bombard()


func _fire_bombard() -> void:
	var to := _bombard_aim - global_position
	var scatter: float = Vector2(to.x, to.z).length() * stats.bombard_spread * sqrt(randf())
	var a := randf() * TAU
	var shell := Shell.new()
	shell.team = team
	shell.damage = stats.bombard_damage
	shell.radius = stats.bombard_splash
	shell.structure_mult = stats.structure_mult
	shell.size = 0.4
	shell.trail = 0.04
	get_tree().current_scene.add_child(shell)
	var muzzle := muzzle_position()
	shell.launch(muzzle, _bombard_aim + Vector3(cos(a), 0.0, sin(a)) * scatter)
	Combat.spawn_explosion(self, muzzle, 1.6)
	SmokeCloud.wisp(self, muzzle, 2.0)
	_recoil = 1.0


## Tip of the barrel: the model's muzzle bone, or a guess in front of the unit.
func muzzle_position() -> Vector3:
	if _muzzle_skel:
		return _muzzle_skel.global_transform * _muzzle_skel.get_bone_global_pose(_muzzle_bone).origin
	return global_position - global_basis.z * 3.0 + Vector3.UP * stats.height


## Hippo active: three smoke grenades into the cone toward `toward` (HippoSmoke). False while
## on cooldown.
func start_smoke(toward: Vector3) -> bool:
	if not smoke_ready() or not is_alive():
		return false
	smoke_cd = stats.smoke_cooldown
	var aim := HippoSmoke.solve(self, toward)
	var muzzle: Vector3 = global_position + Vector3.UP * (stats.height + 0.3)
	for p in aim.points:
		var g := SmokeGrenade.new()
		g.cloud_radius = stats.smoke_radius
		g.cloud_duration = stats.smoke_duration
		get_tree().current_scene.add_child(g)
		g.launch(muzzle, p, stats.smoke_height)
	Combat.spawn_explosion(self, muzzle, 0.5)
	_recoil = 1.0
	return true


## Elephant active: a salvo of homing missiles at one enemy flyer. The pods lift, then the
## missiles leave one tube at a time, alternating pods. False while reloading or out of range.
func start_missiles(t: Node3D) -> bool:
	if not missiles_ready() or not Combat.is_valid_target(t) or not in_missile_range(t):
		return false
	missile_cd = stats.missile_cooldown
	_salvo_target = t
	_salvo_target_id = t.get_instance_id()
	_salvo.clear()
	for k in stats.missile_count:
		_salvo.append(k)
	_salvo_cd = 0.0
	ElephantMissiles.commit(_salvo_target_id, salvo_damage())
	if _turrets:
		_turrets.raised = true
	return true


func _salvo_tick(delta: float) -> void:
	if not Combat.is_valid_target(_salvo_target):
		_end_salvo()  # already down: the rest stay in their tubes
		return
	if _turrets and not _turrets.pods_up():
		return
	_salvo_cd -= delta
	while _salvo_cd <= 0.0 and not _salvo.is_empty():
		_salvo_cd += stats.missile_interval
		_launch_missile(_salvo.pop_front())
	if _salvo.is_empty():
		_end_salvo()


func _launch_missile(k: int) -> void:
	var from: Vector3 = global_position + Vector3.UP * stats.height
	var dir := (Vector3.UP - global_basis.z).normalized()
	if _turrets and _turrets.tube_count() > 0:
		# Tubes are numbered pod by pod: alternate between the two pods.
		var half := maxi(_turrets.tube_count() / 2, 1)
		var tube := _turrets.tube(((k % 2) * half + k / 2) % _turrets.tube_count())
		from = tube.origin
		dir = tube.basis.y.normalized()
	var m := HomingMissile.new()
	m.team = team
	m.damage = stats.missile_damage
	m.on_spent = ElephantMissiles.release.bind(_salvo_target_id, stats.missile_damage)
	get_tree().current_scene.add_child(m)
	m.launch(from, dir, _salvo_target)
	SmokeCloud.wisp(self, from, 1.4)


## Missiles left in the tubes are no longer on their way; the pods come down.
func _end_salvo() -> void:
	if not _salvo.is_empty():
		ElephantMissiles.release(_salvo_target_id, _salvo.size() * stats.missile_damage)
		_salvo.clear()
	if _turrets:
		_turrets.raised = false


## Guns heat up while firing and cool at the same rate while resting. Past overheat_time they
## go silent for overheat_cooldown seconds and come back cold.
func _heat_tick(delta: float, firing: bool) -> void:
	if _overheat_left > 0.0:
		_overheat_left -= delta
		if _overheat_left <= 0.0:
			heat = 0.0
		# Smoke wisps off the gun mounts while they cool.
		_wisp_cd -= delta
		if _wisp_cd <= 0.0:
			_wisp_cd = 0.15
			var side: Vector3 = global_basis.x * stats.radius * 0.4 * (1.0 if randf() < 0.5 else -1.0)
			SmokeCloud.wisp(self, global_position + Vector3.UP * stats.height * 0.95 + side)
	elif firing:
		heat += delta
		if heat >= stats.overheat_time:
			_overheat_left = stats.overheat_cooldown
	else:
		heat = maxf(heat - delta, 0.0)


## Breaching Ram active: a surge of speed for ram_duration seconds. False while on cooldown.
func start_ram() -> bool:
	if not ram_ready():
		return false
	ram_cd = stats.ram_cooldown
	_ram_left = stats.ram_duration
	_trampled.clear()
	_agent.max_speed = _speed()
	return true


func end_ram() -> void:
	_ram_left = 0.0
	charge_gate = null
	if _agent:
		_agent.max_speed = _speed()


## Raiding ram: rams the soldier it hunts once it is close and in sight.
func _raid_ram() -> void:
	if not ram_ready() or not _is_soldier(target) or not _sees_target:
		return
	var to := target.global_position - global_position
	if absf(to.y) < stats.height and to.length() <= RAID_RAM_REACH:
		start_ram()


func _is_soldier(t: Node3D) -> bool:
	return Combat.is_valid_target(t) and t.get("station_kind") == "soldier"


## Charge `gate` from `slot` across its doorway (RamCharge.allocate).
func charge(gate: Structure, slot: int) -> void:
	charge_gate = gate
	charge_slot = slot
	_charge_pos = RamCharge.slot_position(gate, slot, stats.ram_gate_slots)


func _ram_tick(delta: float) -> void:
	_ram_left -= delta
	if _ram_left <= 0.0:
		end_ram()
		return
	if charge_gate:
		if not RamCharge.is_gate(charge_gate):
			charge_gate = null  # already down: keep running
		elif _range_to(charge_gate) <= RamCharge.REACH:
			_slam()
			return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < stats.speed:
		return  # only a running ram knocks anyone over
	_trample(flat.normalized())
	_dust_cd -= delta
	if _dust_cd <= 0.0:
		_dust_cd = 0.08
		SmokeCloud.wisp(self, global_position + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.4, 0.4)), 0.9)


## Enemy soldiers in the ram's way lose health and are tossed out of it, off to the side they
## stood on.
func _trample(fwd: Vector3) -> void:
	var now := Time.get_ticks_msec()
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if d.team == team or not d.is_alive() or not d.has_method("toss"):
			continue
		var id: int = d.get_instance_id()
		if now - _trampled.get(id, -100000) < TRAMPLE_REPEAT * 1000.0:
			continue
		var to: Vector3 = d.global_position - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if absf(to.y) > stats.height or flat.length() > stats.radius + TRAMPLE_REACH or flat.dot(fwd) < 0.0:
			continue
		_trampled[id] = now
		# Out of the way, to the side it stood on (either side if dead ahead).
		var side := flat - fwd * flat.dot(fwd)
		if side.length() < 0.05:
			side = fwd.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		var away := (fwd * 0.6 + side.normalized()).normalized()
		d.take_damage(stats.ram_trample_damage, team)
		d.toss(away * stats.ram_toss + Vector3.UP * stats.ram_toss * 0.6)
		Combat.spawn_impact(self, Combat.aim_point(d), true)
		_butt = 0.6


## The one hit a charge buys: the ram is spent, and the sheep goes back to its shotgun.
func _slam() -> void:
	var gate := charge_gate
	var hit_at: Vector3 = global_position + (gate.global_position - global_position).normalized() * (stats.radius + 0.4) + Vector3.UP * stats.height * 0.5
	gate.take_damage(stats.ram_gate_damage, team)
	Combat.spawn_explosion(self, hit_at, 2.5)
	end_ram()
	_butt = 1.0
	_fire_cd = maxf(_fire_cd, 0.6)


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
		if stats.has("forest_speed"):
			_in_forest = LevelBuilder.in_forest(global_position)
			_agent.max_speed = _speed()
	if not _route.is_empty():
		_follow_route(delta)
		return

	var move_to = null
	if role == "healer":
		if _fire_cd <= 0.0:
			_heal_tick()
	if has_cluster_bomb():
		cluster_cd = maxf(cluster_cd - delta, 0.0)
		if _cluster_left > 0.0:
			_cluster_tick(delta)
	if has_smoke():
		smoke_cd = maxf(smoke_cd - delta, 0.0)
	if has_missiles():
		missile_cd = maxf(missile_cd - delta, 0.0)
		if not _salvo.is_empty():
			_salvo_tick(delta)
	if has_ram():
		ram_cd = maxf(ram_cd - delta, 0.0)
		if _ram_left > 0.0:
			_ram_tick(delta)
	if has_bombard():
		bombard_cd = maxf(bombard_cd - delta, 0.0)
		if _bombard_left > 0.0:
			_bombard_tick(delta)
	if stats.has("aa_dps") and _fire_cd <= 0.0:
		_aa_tick()
	if raiding and has_ram():
		_raid_ram()
	# A charging ram doesn't stop to shoot: it runs for its slot in front of the gate, or, raiding,
	# into the soldier it hunts.
	var running_over := raiding and is_ramming() and _is_soldier(target)
	var engaged := charge_gate == null and not running_over and Combat.is_valid_target(target) and _in_range(target) and _sees_target
	if stats.has("overheat_time"):
		_heat_tick(delta, engaged and not is_overheated())
	if is_bombarding():
		_face(_bombard_aim, delta)  # stands still while it lays the gun and fires
	elif engaged:
		_face(target.global_position, delta)
		if _fire_cd <= 0.0 and not is_overheated():
			_fire_at(target)
	elif charge_gate:
		move_to = _charge_pos
	elif order.type == "move" or order.type == "attack_move":
		move_to = order.pos
	elif running_over:
		move_to = target.global_position
	elif (order.type == "attack" or order.type == "raid") and Combat.is_valid_target(target):
		move_to = _approach(target)

	if is_flying():
		_fly(move_to, delta)
		return

	_desired_velocity = Vector3.ZERO
	if move_to != null:
		if _agent.target_position.distance_to(move_to) > 1.5:
			_agent.target_position = move_to
		if _agent.is_navigation_finished():
			if order.type != "attack" and order.type != "raid":
				order = {"type": "idle"}
			elif role == "melee" or charge_gate or running_over:
				# Close the last stretch to the target straight on.
				var dir: Vector3 = move_to - global_position
				dir.y = 0.0
				if dir.length_squared() > 0.01:
					_desired_velocity = dir.normalized() * _speed()
		else:
			var next := _agent.get_next_path_position()
			if not _route.is_empty():
				return  # just reached a link (_on_link_reached)
			var dir := next - global_position
			dir.y = 0.0
			if dir.length_squared() > 0.0001:
				_desired_velocity = dir.normalized() * _speed()
	if _agent.avoidance_enabled:
		_agent.velocity = _desired_velocity
	else:
		_on_velocity_computed(_desired_velocity)  # charging: no avoidance pass to wait for


## Where to walk to reach `t`. A gate from outside its doorway (its middle is closest to the
## tunnel's navmesh). A post on the decks or roofs from the ground in front of it, unless this
## is an infiltrator that can get up there: a raider, or anyone while a gate is down.
func _approach(t: Node3D) -> Vector3:
	if not t.has_method("get_approach_point"):
		return t.global_position
	if t.get("station_kind") != null and (raiding or (fits_inside() and _nearest_breach() != null)):
		return t.global_position
	return t.get_approach_point()


func _speed() -> float:
	return stats.speed * (stats.forest_speed if _in_forest else 1.0) * (stats.ram_speed if _ram_left > 0.0 else 1.0)


## Infiltrators cross the stronghold's navigation links along the route each one carries:
## climbing a stair shaft or ladder, or slipping in through a broken gate.
func _on_link_reached(details: Dictionary) -> void:
	var link := details.get("owner") as NavigationLink3D
	if link == null or not link.has_meta("route") or not _route.is_empty():
		return
	var route: Array[Vector3] = link.get_meta("route").duplicate()
	var entry: Vector3 = details.link_entry_position
	var forward := entry.distance_to(route[0]) <= entry.distance_to(route[-1])
	if not forward:
		route.reverse()
	_route = route
	_route_breach_in = forward and link.has_meta("breach")


## Moves straight from point to point, through the stair steps and ladder rungs: no collisions.
func _follow_route(delta: float) -> void:
	var to := _route[0] - global_position
	var climbing := absf(to.y) > Vector2(to.x, to.z).length()
	var speed: float = stats.get("climb_speed", stats.speed * 0.5) if climbing else stats.speed * 0.8
	var step := speed * delta
	if to.length() <= step:
		global_position = _route.pop_front()
		if _route.is_empty():
			velocity = Vector3.ZERO
			if _route_breach_in and stats.get("raider", false):
				_start_raid()
		return
	velocity = to.normalized() * speed
	global_position += velocity * delta
	if not climbing:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(10.0 * delta, 1.0))


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
	if hp <= 0.0 or is_flying() or not _route.is_empty():
		return
	var dt := get_physics_process_delta_time()
	if stats.get("steer", false):
		_steer(safe, dt)
	else:
		velocity.x = safe.x
		velocity.z = safe.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * dt
	move_and_slide()
	if fits_inside() and is_on_wall() and Vector2(safe.x, safe.z).length() > 0.5:
		_step_up(Vector3(safe.x, 0.0, safe.z).normalized() * 0.3)
	var flat := Vector2(velocity.x, velocity.z)
	if not stats.get("steer", false) and flat.length() > 0.3 and not (Combat.is_valid_target(target) and _in_range(target)):
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 8.0 * dt)


## move_and_slide stops dead at a ledge: hop onto it if it is low enough and there is room.
func _step_up(motion: Vector3) -> void:
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up) or test_move(global_transform.translated(up), motion):
		return
	global_position += up + motion


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
	var spd := velocity.length() if not _route.is_empty() else Vector2(velocity.x, velocity.z).length()
	var moving := spd > 0.3
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_butt = maxf(_butt - delta * 3.0, 0.0)
	if moving:
		_anim_t += delta * spd
	if _anim:
		# Rigged model: play its clips, matching the move cycle to ground speed.
		var clip: String = stats.anim_move if moving else stats.anim_idle
		if _anim.current_animation != clip:
			_anim.play(clip, 0.25)
		_anim.speed_scale = clampf(spd / stats.anim_ref_speed, 0.6, 3.0 if is_ramming() else 2.0) if moving else 1.0
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
			if role == "melee":
				_model.position.z = -_recoil * 0.35  # lunge into the blow
			elif has_ram():
				_model.position.z = -sin(_butt * PI) * 0.5  # head-butt
			elif has_bombard():
				_model.position.z = _recoil * 0.25  # the gun kicks the pair back
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
	if has_bombard():
		for skel in m.find_children("*", "Skeleton3D", true, false):
			if skel.find_bone("muzzle") >= 0:
				_muzzle_skel = skel
				_muzzle_bone = skel.find_bone("muzzle")
	if stats.get("flak", false):
		var skeletons := m.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_turrets = ElephantTurrets.new()
			skeletons[0].add_child(_turrets)
	if stats.get("carry_gun", false):
		# Carried weapon placeholder until weapons get modeled.
		_model.add_child(Mats.box_mesh(Vector3(0.12, 0.16, 0.9), Vector3(0.35, 1.15, -0.45),
				Mats.flat(Color(0.12, 0.12, 0.13), 0.6, 0.4)))


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
