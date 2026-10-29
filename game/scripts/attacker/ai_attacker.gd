class_name AIAttacker
extends Node
## CPU commander for the attacking army. Builds up waves at a spawn point (the side's Forward
## Helipad while it holds it, else the map's edge), then sends them at the gate on that side; once a
## gate falls everyone pushes for the keep. A helipad the defenders sabotaged is retaken by the
## ground units nearest it (_retake_bases). It never goes after the defenders' infiltrators: it
## doesn't know they are there (their low profile, Combat.low_profile), unless its giraffes' pings
## reveal them (_giraffe_pings). Its lionesses hunt the defenders out on the field (_lioness_hunts).
## Uses the same command interface as the human RTS player.

var commander: AttackerCommander
var level: LevelBuilder

var _think_cd := 2.0
var _wave := 0
var _pending: Array[String] = []
var _staging: Array[int] = []
var _wave_spawn := 0
var _wave_side := "south"
var _first_wave_delay := 15.0

const SPAWN_SIDES := ["south", "east", "west"]
## A flash grenade lands where it is thrown: kangaroos throw with little of their reach to spare (the
## infantry's stand in front of a gun deck is just inside it).
const FLASH_SPARE := 0.97
## Units sent to retake a sabotaged helipad: as many as RETAKERS of the nearest ground units.
const RETAKERS := 3
## Giraffes this close to the middle of the map (m, flat) are out on the field: they ping.
const PING_FIELD := 150.0
## Lionesses go after defenders on the ground this close to them (m, flat).
const HUNT_RANGE := 32.0

## Helipad -> ids of the units sent to retake it.
var _retakers := {}


func _process(delta: float) -> void:
	_first_wave_delay -= delta
	_think_cd -= delta
	if _think_cd > 0.0 or _first_wave_delay > 0.0:
		return
	_think_cd = 1.0
	_think()


func _think() -> void:
	if _pending.is_empty() and _staging.is_empty():
		_plan_wave()

	while not _pending.is_empty() and commander.can_afford(_pending[0]):
		var at := _spawn_for(_wave_spawn)
		var id := commander.submit({"type": "spawn", "unit": _pending[0], "spawn": at})
		if id == 0:
			break
		_pending.pop_front()
		_staging.append(id)
		# Off the map's edge the wave gathers a way down its lane; at a helipad, right there.
		var rally: Vector3 = commander.spawn_points[_wave_spawn] * 0.72 if at == _wave_spawn else commander.spawn_points[at]
		commander.submit({"type": "move", "units": [id], "pos": rally, "attack": true})

	if _pending.is_empty() and not _staging.is_empty():
		_launch_wave()

	_retake_bases()
	_reassign_idle()
	_ram_gates()
	_talon_strikes()
	_kangaroo_flashes()
	_giraffe_pings()
	_lioness_hunts()


func _plan_wave() -> void:
	_wave += 1
	_wave_spawn = randi() % SPAWN_SIDES.size()
	_wave_side = SPAWN_SIDES[_wave_spawn]
	# Wave mix grows over time: infantry core, then flyers, heavies and artillery.
	var counts := {
		"breacher": 1 if _wave >= 2 and (_wave % 2 == 0 or _wave > 5) else 0,
		"mule": 1 if _wave >= 3 and _wave % 2 == 1 else 0,
		"elephant": 0 if _wave < 3 else (1 if _wave < 7 else 2),
		"medic": 1 if _wave < 5 else 2,
		"rifleman": mini(3 + _wave, 10),
		"kangaroo": mini(1 + _wave / 2, 5),
		"talon": 0 if _wave < 2 else mini(_wave - 1, 4),
		"chimp": 0 if _wave < 3 else mini(1 + _wave / 3, 4),
		"giraffe": 1 if _wave >= 2 else 0,
		"lioness": 0 if _wave < 2 else mini(1 + _wave / 2, 6),
	}
	# Interleave so a partly-spawned wave is still a sensible mix.
	var remaining := true
	while remaining:
		remaining = false
		for type_id in counts:
			if counts[type_id] > 0:
				_pending.append(type_id)
				counts[type_id] -= 1
				remaining = true


func _launch_wave() -> void:
	var gate: Structure = level.gates[_wave_side]
	var ids := _staging.duplicate()
	_staging.clear()
	if gate.is_alive():
		var infantry := []
		var siege := []
		var artillery := []
		for id in ids:
			var u = commander.units.get(id)
			if u == null:
				continue
			if u.has_ram():
				siege.append(id)
			elif u.role == "artillery":
				artillery.append(id)
			else:
				infantry.append(id)
		# Infantry, medics and flyers push up to the gate and suppress the walls, rams go
		# for the gate, artillery shells it from range.
		var out: Vector3 = LevelBuilder.SIDES[_wave_side].dir
		commander.submit({"type": "move", "units": infantry, "pos": out * (LevelBuilder.FACE_DIST + 14.0), "attack": true})
		commander.submit({"type": "attack", "units": siege + artillery, "target": gate.get_path()})
	else:
		_push_keep(ids)


func _push_keep(ids: Array) -> void:
	# The keep is deep inside the mountain and only infiltrators can get to it. Chimps that make it
	# in go raiding on their own (AttackerUnit._raid_target).
	# Flyers circle over the breached side's gun deck, big units hold in front of that face
	# (off to one side, clear of the tunnel), both picking off the defenders on it.
	var inside := []
	var flyers := []
	var big := []
	for id in ids:
		var u = commander.units.get(id)
		if u == null:
			continue
		if u.fits_inside():
			inside.append(id)
		elif u.is_flying():
			flyers.append(id)
		else:
			big.append(id)
	var out: Vector3 = LevelBuilder.SIDES[_breached_side()].dir
	if not inside.is_empty():
		commander.submit({"type": "attack", "units": inside, "target": level.keep.get_path()})
	if not flyers.is_empty():
		commander.submit({"type": "move", "units": flyers, "pos": out * (LevelBuilder.FACE_DIST - 8.0), "attack": true})
	if not big.is_empty():
		var hold := out * (LevelBuilder.FACE_DIST + 16.0) + out.cross(Vector3.UP) * 14.0
		commander.submit({"type": "move", "units": big, "pos": hold, "attack": true})


func _breached_side() -> String:
	for side in level.gates:
		if not level.gates[side].is_alive():
			return side
	return _wave_side


## Rams closing in on a gate ram it once it is within reach of the charge.
func _ram_gates() -> void:
	var by_gate := {}
	for u in commander.units.values():
		if not u.ram_ready() or u.order.type != "attack" or not RamCharge.is_gate(u.order.target):
			continue
		var gate: Structure = u.order.target
		var reach: float = u.stats.ram_duration * u.stats.speed * u.stats.ram_speed * 0.6
		if u.global_position.distance_to(gate.get_approach_point()) <= reach:
			if not by_gate.has(gate):
				by_gate[gate] = []
			by_gate[gate].append(u.unit_id)
	for gate in by_gate:
		commander.submit({"type": "ram", "units": by_gate[gate]})
		commander.submit({"type": "attack", "units": by_gate[gate], "target": gate.get_path()})


## Talons strike whatever is in their reach: bombs on the AA turrets first, then the machines and
## the gates; strafe runs (along the face, next to the mountain) on the defenders.
func _talon_strikes() -> void:
	for u in commander.units.values():
		if not u.has_bomb() or not u.is_alive() or u.on_run():
			continue
		if u.bomb_ready():
			var t := _in_reach(u, u.stats.bomb_range, func(d): return d.get("station_kind") == "aa")
			if t == null:
				t = _in_reach(u, u.stats.bomb_range, func(d): return d.get("station_kind") in ["mg", "artillery"] or d in level.gates.values())
			if t:
				commander.submit({"type": "bomb", "units": [u.unit_id], "pos": t.global_position})
				continue
		if u.strafe_ready():
			var t := _in_reach(u, u.stats.strafe_range, func(d): return not d.is_in_group("structures") and d.get("station_kind") not in ["aa", "mg", "artillery"])
			if t:
				var to: Vector3 = t.global_position - u.global_position
				var dir := Vector3(to.x, 0.0, to.z).normalized()
				var out := Vector3(t.global_position.x, 0.0, t.global_position.z)
				if out.length() < LevelBuilder.FACE_DIST + 10.0:
					var along := out.normalized().cross(Vector3.UP)
					dir = along if along.dot(dir) >= 0.0 else -along
				commander.submit({"type": "strafe", "units": [u.unit_id], "pos": t.global_position, "dir": dir})


## Kangaroos throw flash grenades at the defenders in their reach: the gun decks' riflemen and
## machine guns, the mortar, squads out in the field (not ones blinded already or with a grenade on
## its way). The ready ones in reach of the same defender throw together, their flashes spread round
## it (KangarooFlash.spots). Raiders throw on their own.
func _kangaroo_flashes() -> void:
	var ready := commander.units.values().filter(func(u): return u.flash_ready() and not u.raiding)
	while not ready.is_empty():
		var u: AttackerUnit = ready.pop_front()
		var unflashed := func(d): return d.get("station_kind") in ["soldier", "mg", "artillery"] and not FlashGrenade.is_blind(d) \
				and not FlashGrenade.coming(level, d.global_position, u.stats.flash_radius * 0.6)
		var t := _in_reach(u, u.stats.flash_range, unflashed, FLASH_SPARE)
		if t == null:
			continue
		var group := [u]
		for o in ready.duplicate():
			if Vector2(o.global_position.x - t.global_position.x, o.global_position.z - t.global_position.z).length() < o.stats.flash_range * FLASH_SPARE:
				group.append(o)
				ready.erase(o)
		commander.submit({"type": "flash", "units": group.map(func(k): return k.unit_id), "pos": t.global_position})


## Giraffes out on the field ping whenever they can: the CPU doesn't know where the defenders' squads
## are any more than a player would, so it sweeps the ground in front of its army.
func _giraffe_pings() -> void:
	var ids := []
	for u in commander.units.values():
		if u.ping_ready() and not u.raiding and Vector2(u.global_position.x, u.global_position.z).length() < PING_FIELD:
			ids.append(u.unit_id)
	if not ids.is_empty():
		commander.submit({"type": "ping", "units": ids})


## Lionesses hunt the defenders on the ground the army sees within HUNT_RANGE (squads out on the field,
## riflemen off the walls; the walls' posts are out of their reach): a lioness whose sneak is ready
## sneaks up and pounces, the others run in to maul them; close enough, she lights her fire blast.
func _lioness_hunts() -> void:
	for u in commander.units.values():
		if not u.has_sneak() or not u.is_controllable() or u.is_pouncing():
			continue
		var on_ground := func(d): return d.get("station_kind") in ["soldier", "infiltrator"] \
				and absf(d.global_position.y - u.global_position.y) < AttackerUnit.POUNCE_RISE
		var prey := _in_reach(u, HUNT_RANGE, on_ground, 1.0)
		if prey == null:
			continue
		var dist := Vector2(prey.global_position.x - u.global_position.x, prey.global_position.z - u.global_position.z).length()
		if u.blast_ready() and dist < u.stats.blast_range * 0.8:
			commander.submit({"type": "blast", "units": [u.unit_id]})
		if u.order.type == "attack" and u.order.target == prey:
			continue
		if u.sneak_ready() and dist > u.stats.pounce_range * 0.6:
			commander.submit({"type": "sneak", "units": [u.unit_id]})
		commander.submit({"type": "attack", "units": [u.unit_id], "target": prey.get_path()})


## The nearest live defender `pick` takes (or gate) within `reach` of `u` (flat), with room to spare
## (within `spare` of it). Only what the army sees: the CPU plays by the fog of war (AttackerVision).
func _in_reach(u: AttackerUnit, reach: float, pick: Callable, spare := 0.85) -> Node3D:
	var best: Node3D = null
	var best_d := reach * spare
	for d in level.get_tree().get_nodes_in_group("damageable"):
		if d.team == u.team or not d.is_alive() or Combat.low_profile(d) or not AttackerVision.sees_node(d) or not pick.call(d):
			continue
		var dist := Vector2(d.global_position.x - u.global_position.x, d.global_position.z - u.global_position.z).length()
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Where a wave from spawn point `edge` (0-2, the map's edge) spawns: the helipad on its side while
## the attackers hold it.
func _spawn_for(edge: int) -> int:
	var side: String = SPAWN_SIDES[edge]
	for k in commander.spawn_bases.size():
		var b = commander.spawn_bases[k]
		if b != null and b.side == side and commander.spawn_open(k):
			return k
	return edge


## Sabotaged helipads: the ground units nearest each (not raiding, not a wave about to set off) go
## and stand by it until it is retaken.
func _retake_bases() -> void:
	for b in level.bases:
		if b.controlled:
			_retakers.erase(b)
			continue
		var sent: Array = _retakers.get(b, []).filter(func(id): return commander.units.has(id) and commander.units[id].is_controllable())
		if sent.size() >= RETAKERS:
			_retakers[b] = sent
			continue
		var cands := []
		for id in commander.units:
			var u: AttackerUnit = commander.units[id]
			if id in sent or id in _staging or u.is_flying() or not u.is_controllable():
				continue
			cands.append([b.edge_distance(u.global_position), id])
		cands.sort_custom(func(x, y): return x[0] < y[0])
		var more: Array = cands.slice(0, RETAKERS - sent.size()).map(func(c): return c[1])
		if not more.is_empty():
			commander.submit({"type": "move", "units": more, "pos": b.spawn_point, "attack": true})
		_retakers[b] = sent + more


## Units with nothing to do look for the next objective.
func _reassign_idle() -> void:
	var breached := level.gates.values().any(func(g): return not g.is_alive())
	var idle := []
	var retaking := []
	for ids in _retakers.values():
		retaking += ids
	for id in commander.units:
		if id in _staging or id in retaking:
			continue
		var u: AttackerUnit = commander.units[id]
		if u.is_idle():
			idle.append(id)
	if idle.is_empty():
		return
	if breached:
		_push_keep(idle)
		return
	# No breach yet: hit the nearest standing gate.
	var by_gate := {}
	for id in idle:
		var u: AttackerUnit = commander.units[id]
		var best: Structure = null
		var best_d := INF
		for g in level.gates.values():
			if g.is_alive():
				var d := u.global_position.distance_to(g.global_position)
				if d < best_d:
					best_d = d
					best = g
		if best:
			if not by_gate.has(best):
				by_gate[best] = []
			by_gate[best].append(id)
	for g in by_gate:
		commander.submit({"type": "attack", "units": by_gate[g], "target": g.get_path()})
