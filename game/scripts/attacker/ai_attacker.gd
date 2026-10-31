class_name AIAttacker
extends Node
## CPU commander for the attacking army. Builds up waves at a spawn point (the side's Forward
## Helipad while it holds it, else the map's edge), then sends them at the gate on that side; once a
## gate falls everyone pushes for the keep. A helipad the defenders sabotaged is retaken by the
## ground units nearest it (_retake_bases). It never goes after the defenders' infiltrators: it
## doesn't know they are there (their low profile, Combat.low_profile), unless its giraffes' pings
## reveal them (_giraffe_pings). Its lionesses hunt the defenders out on the field (_lioness_hunts). Its dogs
## heal; it can't see the defenders' mines any more than a player can, but one going off under its army
## tells it a minefield is there: the dogs near the blast sweep for mines until they find no more (_dog_modes).
## Its Serpent Snipers snipe from the trees in reach of the gate they go for, and lie in wait round bushes where
## the army saw the defenders out on the field (_serpent_skills).
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
## Dogs this close to a mine that went off (m, flat) switch to minesweeping; a sweeping dog that has had no
## mine to dig for SWEEP_IDLE seconds goes back to healing.
const SWEEP_CALL := 40.0
const SWEEP_IDLE := 20.0
## Serpent Snipers go up a tree this far off their way at most (m, flat), one with the gate nearest them in their
## rifle's reach from up there (with a little to spare) and no closer to it than NEST_CLEAR (not under the wall).
const NEST_LOOK := 30.0
const NEST_CLEAR := 25.0
## Where the army saw a defender out on the field in the last TRAP_MEMORY seconds, within TRAP_CALL of a snake
## (m, flat), the snake coils round the free bush nearest the spot (within TRAP_LOOK of it) and lies in wait.
const TRAP_MEMORY := 45.0
const TRAP_CALL := 40.0
const TRAP_LOOK := 10.0
## A snake up a tree with nothing to shoot for NEST_IDLE seconds, or round a bush with nothing come by for
## TRAP_IDLE, comes down (uncoils) and goes on; it rests SKILL_REST seconds before it climbs or coils again.
const NEST_IDLE := 20.0
const TRAP_IDLE := 40.0
const SKILL_REST := 45.0

## Helipad -> ids of the units sent to retake it.
var _retakers := {}
## Mine blasts it has seen so far, and how long each sweeping dog (id) has had no mine to dig (s).
var _blasts_seen := GroundMine.blasts
var _sweep_idle := {}
## Seconds of thinking so far, and where the army saw defenders out on the field: [where, when], the last
## TRAP_MEMORY seconds of them.
var _clock := 0.0
var _sightings: Array = []
## Serpent Sniper id -> seconds up its tree or round its bush with nothing to do, and seconds before it may climb
## or coil again.
var _skill_idle := {}
var _skill_rest := {}


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
	_serpent_skills()
	_dog_modes()


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
		"serpent": 0 if _wave < 3 else mini(1 + (_wave - 3) / 2, 3),
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


## Serpent Snipers: one with a tree near it (NEST_LOOK) from which the gate nearest it is in its rifle's reach
## climbs it and snipes from the crown. Otherwise, where the army saw a defender out on the field lately near one,
## it coils round the free bush nearest the spot and lies in wait. Up there with nothing to shoot for NEST_IDLE, or
## round its bush with nothing come by for TRAP_IDLE, it comes down (uncoils) and goes on with the army, and rests
## (SKILL_REST) before it climbs or coils again. One squeezing its prey is left to it.
func _serpent_skills() -> void:
	_clock += 1.0
	_note_sightings()
	for u in commander.units.values():
		if not (u.has_nest() or u.has_trap()) or not u.is_controllable() or u.unit_id in _staging:
			continue
		var id: int = u.unit_id
		if u.in_tree() or u.in_bush():
			var busy: bool = u.skill_dir() != 0 or u.is_constricting() or Combat.is_valid_target(u.target)
			_skill_idle[id] = 0.0 if busy else _skill_idle.get(id, 0.0) + 1.0
			if _skill_idle[id] >= (NEST_IDLE if u.in_tree() else TRAP_IDLE):
				_skill_idle.erase(id)
				_skill_rest[id] = SKILL_REST
				_send_on([id])  # it climbs down (uncoils) first
			continue
		_skill_rest[id] = _skill_rest.get(id, 0.0) - 1.0
		if _skill_rest[id] > 0.0 or u.order.type in ["nest", "trap"]:
			continue
		var tree := _nest_tree(u) if u.has_nest() else null
		if tree:
			commander.submit({"type": "nest", "units": [id], "pos": tree.trunk_centre()})
			continue
		var bush := _trap_bush(u) if u.has_trap() else null
		if bush:
			commander.submit({"type": "trap", "units": [id], "pos": bush.global_position})


## Remembers where the army sees defenders out on the field now (the soldiers and troopers a snake strikes,
## SerpentTrap.PREY, on the ground outside the mountain), forgetting what it saw over TRAP_MEMORY ago.
func _note_sightings() -> void:
	_sightings = _sightings.filter(func(s): return _clock - s[1] <= TRAP_MEMORY)
	for d in level.get_tree().get_nodes_in_group("defender_targets"):
		if not d.is_alive() or d.get("station_kind") not in SerpentTrap.PREY or Combat.low_profile(d) or not AttackerVision.sees_node(d):
			continue
		var p: Vector3 = d.global_position
		if p.y < 2.0 and Vector2(p.x, p.z).length() > LevelBuilder.FACE_DIST + 4.0:
			_sightings.append([p, _clock])


## The tree for `u` to snipe from: standing and free, within NEST_LOOK of it, the standing gate nearest it in its
## rifle's reach from up there and no closer to it than NEST_CLEAR; the nearest such, or null.
func _nest_tree(u: AttackerUnit) -> ForestTree:
	var gate := _nearest_gate(u.global_position)
	if gate == null:
		return null
	var reach: float = u.stats.range * u.stats.nest_range * 0.85
	var best: ForestTree = null
	var best_d := NEST_LOOK
	for tree in ForestTree.standing:
		if not tree.nest_free(u):
			continue
		var foot := tree.trunk_centre()
		var to_gate := _flat_dist(foot, gate.global_position)
		var d := _flat_dist(foot, u.global_position)
		if to_gate <= reach and to_gate >= NEST_CLEAR and d < best_d:
			best_d = d
			best = tree
	return best


## The bush for `u` to lie in wait round: the free one nearest where the army last saw a defender out on the
## field within TRAP_CALL of it (no further than TRAP_LOOK from the spot), or null.
func _trap_bush(u: AttackerUnit) -> Bush:
	for k in range(_sightings.size() - 1, -1, -1):
		var at: Vector3 = _sightings[k][0]
		if _flat_dist(at, u.global_position) > TRAP_CALL:
			continue
		var bush := Bush.nearest(at, TRAP_LOOK, u)
		if bush:
			return bush
	return null


## Dogs heal. A mine going off under the army (the CPU sees that much): the dogs within SWEEP_CALL of it switch
## to minesweeping; a sweeping dog with no mine to dig for SWEEP_IDLE seconds goes back to healing.
func _dog_modes() -> void:
	var blast := GroundMine.blasts > _blasts_seen
	_blasts_seen = GroundMine.blasts
	var at := GroundMine.last_blast
	for u in commander.units.values():
		if not u.has_dog_modes() or not u.is_controllable():
			continue
		if u.dog_mode == "heal":
			if blast and Vector2(u.global_position.x - at.x, u.global_position.z - at.z).length() < SWEEP_CALL:
				commander.submit({"type": "dog_mode", "units": [u.unit_id], "mode": "sweep"})
				_sweep_idle[u.unit_id] = 0.0
			continue
		_sweep_idle[u.unit_id] = 0.0 if u.sweep_mine != null else _sweep_idle.get(u.unit_id, 0.0) + 1.0
		if _sweep_idle[u.unit_id] >= SWEEP_IDLE:
			commander.submit({"type": "dog_mode", "units": [u.unit_id], "mode": "heal"})
			_sweep_idle.erase(u.unit_id)


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
			if id in sent or id in _staging or u.is_flying() or not u.is_controllable() or u.in_tree() or u.in_bush():
				continue
			cands.append([b.edge_distance(u.global_position), id])
		cands.sort_custom(func(x, y): return x[0] < y[0])
		var more: Array = cands.slice(0, RETAKERS - sent.size()).map(func(c): return c[1])
		if not more.is_empty():
			commander.submit({"type": "move", "units": more, "pos": b.spawn_point, "attack": true})
		_retakers[b] = sent + more


## Units with nothing to do look for the next objective.
func _reassign_idle() -> void:
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
	if not idle.is_empty():
		_send_on(idle)


## Sends `ids` on to the next objective: the keep once a gate is down, else the standing gate nearest each.
func _send_on(ids: Array) -> void:
	if level.gates.values().any(func(g): return not g.is_alive()):
		_push_keep(ids)
		return
	var by_gate := {}
	for id in ids:
		var u: AttackerUnit = commander.units[id]
		var best := _nearest_gate(u.global_position)
		if best:
			if not by_gate.has(best):
				by_gate[best] = []
			by_gate[best].append(id)
	for g in by_gate:
		commander.submit({"type": "attack", "units": by_gate[g], "target": g.get_path()})


## The standing gate nearest `p`, or null.
func _nearest_gate(p: Vector3) -> Structure:
	var best: Structure = null
	var best_d := INF
	for g in level.gates.values():
		if g.is_alive() and p.distance_to(g.global_position) < best_d:
			best_d = p.distance_to(g.global_position)
			best = g
	return best


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
