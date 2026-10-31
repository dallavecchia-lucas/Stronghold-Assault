class_name AttackerCommander
extends Node
## Authoritative state of the attacking army: supply, spawning and orders.
##
## Every attacker action (from the RTS player or the CPU) goes through submit() as a
## plain Dictionary. Keeping commands serializable means online play can later just
## send these over the network to whoever runs the match.
##
##   {"type": "spawn", "unit": "rifleman", "spawn": 0}   a forward helipad's spawn point only while
##               the attackers hold it (spawn_open)
##   {"type": "move", "units": [ids], "pos": Vector3, "attack": bool}
##   {"type": "attack", "units": [ids], "target": NodePath}   rams ramming at a ground gate charge
##               it, as many as fit in front of its doorway; the rest call their ram off (RamCharge)
##   {"type": "cluster", "units": [ids], "pos": Vector3}   rhinos bomb around pos (RhinoAim)
##   {"type": "bombard", "units": [ids], "pos": Vector3}   bisons each fire a shell round pos,
##               up on the gun decks and roofs too (RhinoAim.bombard); so do Mule Artillery with
##               their guns set up
##   {"type": "setup", "units": [ids], "on": bool}   Mule Artillery set their guns up (on) or pack
##               them up (AttackerUnit.set_gun): setup_time each way; they can't move unless packed
##   {"type": "strafe", "units": [ids], "pos": Vector3, "dir": Vector3}   talons strafe parallel
##               lanes centred round pos, flying along dir (TalonAim.strafe)
##   {"type": "bomb", "units": [ids], "pos": Vector3}   talons each drop a bomb round pos
##               (TalonAim.bombs)
##   {"type": "smoke", "units": [ids], "pos": Vector3}   the ready hippo closest to pos lays a
##                                                     smoke screen toward it (HippoSmoke)
##   {"type": "flash", "units": [ids], "pos": Vector3}   kangaroos each throw a flash grenade round
##               pos, up on the gun decks and roofs too (KangarooFlash.spots)
##   {"type": "missile", "units": [ids], "target": NodePath}   elephants fire missile salvos at
##               an enemy flyer, only as many as the kill takes (ElephantMissiles)
##   {"type": "ram", "units": [ids]}   breaching rams surge forward (AttackerUnit.start_ram)
##   {"type": "ping", "units": [ids]}   giraffes ping from their dishes (AttackerUnit.start_ping)
##   {"type": "sneak", "units": [ids]}   lionesses sneak (AttackerUnit.start_sneak); an attack order
##               while it lasts makes them pounce
##   {"type": "blast", "units": [ids]}   lionesses light their fire blast (AttackerUnit.start_blast)
##   {"type": "line", "on": bool}   lionesses moved together form up in firing lines, or don't
##               (line_formation)
##   {"type": "nest", "units": [ids], "pos": Vector3}   Serpent Snipers climb trees to snipe from: the tree
##               nearest pos for the snake nearest it, the free ones round it for the others (SerpentNest.assign)
##   {"type": "trap", "units": [ids], "pos": Vector3}   Serpent Snipers coil round bushes to lie in wait: the
##               bush nearest pos and the free ones round it likewise (SerpentTrap.assign)
##   {"type": "dog_mode", "units": [ids], "mode": "heal" | "sweep"}   Wolf Medics switch to healing or
##               to minesweeping (AttackerUnit.set_dog_mode)
##   {"type": "scout", "units": [ids]}   toggle scout formation: the rhinos in the selection
##                                       ring the rest of it so their anti-air covers the mass
##
## Lionesses moved together (two or more) form up in firing lines as they go (LionessLine), up to 8
## abreast and more ranks behind, while line_formation is on; the other units moved with them gather
## behind the lines.
##
## It also hands out the kangaroos' supplies (their passive): each kangaroo resupplies the units
## nearest it whose skills are cooling down, up to resupply_units of them, and no unit takes
## supplies from two kangaroos (_update_resupply). The healing dogs' patients likewise: each heals up
## to heal_units hurt units near it, keeps them until they are full or out of its reach, and no unit
## takes two dogs' healing (_update_heal).
##
## Every Forward Helipad Base the attackers hold (AttackerBase) adds AttackerBase.INCOME to the
## supply coming in (income_rate).

signal unit_spawned(unit: AttackerUnit)
signal unit_died(unit: AttackerUnit)

const UNIT_CAP := 60
const BASE_INCOME := 12.0
## How far outside the edge of the mass scouting rhinos keep.
const SCOUT_MARGIN := 5.0
## Seconds between handing out the kangaroos' supplies.
const RESUPPLY_EVERY := 0.25

var supply := 250.0
var income := BASE_INCOME
var units := {}  # id -> AttackerUnit
var spawn_points: Array[Vector3] = []
## Per spawn point: the AttackerBase it belongs to, or null (always open). LevelBuilder.spawn_bases;
## left empty, every spawn point is open.
var spawn_bases: Array = []
var units_root: Node3D

var _next_id := 1
var _next_formation := 1
## Scout formations: [{"rhinos": [ids], "escorts": [ids]}]
var scout_groups: Array = []
## Lionesses moved together form up in firing lines (the attacking player's toggle), and the lines
## marching now.
var line_formation := true
var lines: Array[LionessLine] = []
var _scout_cd := 0.0
var _resupply_cd := 0.0


func _physics_process(delta: float) -> void:
	lines = lines.filter(func(l): return l.update(delta))


func _process(delta: float) -> void:
	supply += income_rate() * delta
	_scout_cd -= delta
	if _scout_cd <= 0.0:
		_scout_cd = 0.5
		_update_scouts()
	_resupply_cd -= delta
	if _resupply_cd <= 0.0:
		_resupply_cd = RESUPPLY_EVERY
		_update_resupply()
		_update_heal()


## Supply a second: the commander's own income and every helipad the attackers hold.
func income_rate() -> float:
	var rate := income
	for b in spawn_bases:
		if b != null and b.controlled:
			rate += AttackerBase.INCOME
	return rate


## False for a forward helipad's spawn point while the attackers don't hold it.
func spawn_open(idx: int) -> bool:
	if idx < 0 or idx >= spawn_bases.size() or spawn_bases[idx] == null:
		return true
	return spawn_bases[idx].controlled


func can_afford(type_id: String) -> bool:
	return supply >= UnitTypes.DATA[type_id].cost and units.size() < UNIT_CAP


## Applies a command. Returns the new unit id for spawns, 0 otherwise / on failure.
func submit(cmd: Dictionary) -> int:
	match cmd.get("type", ""):
		"spawn":
			return _spawn(cmd.unit, cmd.get("spawn", 0))
		"move":
			_move(cmd.units, cmd.pos, cmd.get("attack", true))
		"attack":
			_attack(cmd.units, cmd.target)
		"cluster":
			_cluster(cmd.units, cmd.pos)
		"bombard":
			_bombard(cmd.units, cmd.pos)
		"setup":
			for u in _resolve(cmd.units):
				u.set_gun(cmd.get("on", true))
		"strafe":
			_strafe(cmd.units, cmd.pos, cmd.dir)
		"bomb":
			_bomb(cmd.units, cmd.pos)
		"smoke":
			_smoke(cmd.units, cmd.pos)
		"flash":
			_flash(cmd.units, cmd.pos)
		"missile":
			_missiles(cmd.units, cmd.target)
		"ram":
			for u in _resolve(cmd.units):
				u.start_ram()
		"ping":
			for u in _resolve(cmd.units):
				if not u.raiding:
					u.start_ping()
		"sneak":
			for u in _resolve(cmd.units):
				u.start_sneak()
		"blast":
			for u in _resolve(cmd.units):
				u.start_blast()
		"nest":
			for pick in SerpentNest.assign(_resolve(cmd.units).filter(func(u): return u.has_nest() and u.is_controllable()), cmd.pos):
				pick[0].set_order({"type": "nest", "tree": pick[1]})
		"trap":
			for pick in SerpentTrap.assign(_resolve(cmd.units).filter(func(u): return u.has_trap() and u.is_controllable()), cmd.pos):
				pick[0].set_order({"type": "trap", "bush": pick[1]})
		"line":
			line_formation = cmd.get("on", not line_formation)
		"dog_mode":
			for u in _resolve(cmd.units):
				u.set_dog_mode(cmd.get("mode", "heal"))
		"scout":
			_toggle_scout(cmd.units)
	return 0


func _spawn(type_id: String, spawn_idx: int) -> int:
	spawn_idx = clampi(spawn_idx, 0, spawn_points.size() - 1)
	if not UnitTypes.DATA.has(type_id) or not can_afford(type_id) or not spawn_open(spawn_idx):
		return 0
	supply -= UnitTypes.DATA[type_id].cost
	var id := _next_id
	_next_id += 1
	var u := AttackerUnit.new()
	u.setup(type_id, id)
	var base: Vector3 = spawn_points[spawn_idx]
	u.position = base + Vector3(randf_range(-6, 6), 0.2, randf_range(-6, 6))
	# Face the stronghold.
	u.rotation.y = atan2(base.x, base.z)
	units_root.add_child(u)
	units[id] = u
	u.died.connect(_on_unit_died)
	unit_spawned.emit(u)
	return id


func _on_unit_died(u: AttackerUnit) -> void:
	units.erase(u.unit_id)
	unit_died.emit(u)


func _move(ids: Array, pos: Vector3, attack: bool) -> void:
	var list := _resolve(_without_scouts(ids))
	var kind := "attack_move" if attack else "move"
	var fid := _next_formation
	_next_formation += 1
	# Two or more lionesses form up in firing lines; the rest gather behind them.
	var lionesses := list.filter(func(u): return u.stats.get("line", false)) if line_formation else []
	var at := pos
	if lionesses.size() >= 2:
		var line := LionessLine.make(lionesses, pos)
		lines.append(line)
		for u in lionesses:
			u.formation_id = fid
			u.set_order({"type": kind, "pos": line.final_spot(u), "line": line})
		list = list.filter(func(u): return not u in lionesses)
		at = pos - line.dir * (line.depth() + LionessLine.RANK_GAP + 2.0)
	var offsets := formation_offsets(list.size(), 2.2)
	for i in list.size():
		list[i].formation_id = fid
		list[i].set_order({"type": kind, "pos": at + offsets[i]})


func _attack(ids: Array, target_path: NodePath) -> void:
	var target := get_node_or_null(target_path) as Node3D
	# Under adaptive camo an infiltrator can't be picked out, even on orders; nor anyone in the fog
	# of war.
	if not Combat.targetable(target) or not AttackerVision.sees_node(target):
		return
	var list := _resolve(_without_scouts(ids))
	for u in list:
		u.formation_id = 0
		u.set_order({"type": "attack", "target": target})
	# Ordered at by units that shoot, an infiltrator loses her low profile, as if a ping had
	# revealed her.
	if target is InfiltratorTrooper and list.any(func(u): return u.has_basic_attack()):
		target.reveal()
	if RamCharge.is_gate(target):
		for pick in RamCharge.allocate(list, target):
			pick[0].charge(target, pick[1])
		for u in list:
			if u.is_ramming() and u.charge_gate == null:
				u.end_ram()  # no room at the doorway, or too far to make it in time


func _cluster(ids: Array, pos: Vector3) -> void:
	var rhinos := _resolve(ids).filter(func(u): return u.cluster_ready())
	var aims := RhinoAim.solve(rhinos, pos)
	for i in rhinos.size():
		rhinos[i].start_cluster(aims[i])


func _bombard(ids: Array, pos: Vector3) -> void:
	var bisons := _resolve(ids).filter(func(u): return u.bombard_ready())
	var aims := RhinoAim.bombard(bisons, pos)
	for i in bisons.size():
		bisons[i].start_bombard(aims[i])


func _strafe(ids: Array, pos: Vector3, dir: Vector3) -> void:
	var talons := _resolve(ids).filter(func(u): return u.strafe_ready())
	var lanes := TalonAim.strafe(talons, pos, dir)
	for i in talons.size():
		talons[i].start_strafe(lanes[i][0], lanes[i][1])


func _bomb(ids: Array, pos: Vector3) -> void:
	var talons := _resolve(ids).filter(func(u): return u.bomb_ready())
	var spots := TalonAim.bombs(talons, pos)
	for i in talons.size():
		talons[i].start_bomb(spots[i])


func _smoke(ids: Array, pos: Vector3) -> void:
	var hippo := HippoSmoke.pick(_resolve(ids).filter(func(u): return u.smoke_ready()), pos)
	if hippo:
		hippo.start_smoke(pos)


func _missiles(ids: Array, target_path: NodePath) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if not Combat.is_valid_target(target):
		return
	for e in ElephantMissiles.allocate(_resolve(ids).filter(func(u): return u.has_missiles()), target):
		e.start_missiles(target)


func _flash(ids: Array, pos: Vector3) -> void:
	var kangaroos := _resolve(ids).filter(func(u): return u.flash_ready() and not u.raiding)
	var spots := KangarooFlash.spots(kangaroos, pos)
	for i in kangaroos.size():
		kangaroos[i].start_flash(spots[i])


# ---------------------------------------------------------------- kangaroo supplies

## Each kangaroo resupplies the units nearest it whose skills are cooling down (itself aside), up to
## resupply_units of them; the closest pairs go first, and a unit one kangaroo already supplies is
## left to it, so the cut never stacks and the others' supplies go further.
func _update_resupply() -> void:
	var pairs := []
	for k in units.values():
		if not k.is_alive() or not k.resupplies():
			continue
		for u in units.values():
			if u == k or not u.is_alive() or not u.cooling_down():
				continue
			var d: float = k.global_position.distance_to(u.global_position)
			if d <= k.stats.resupply_range:
				pairs.append([d, k, u])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	var load := {}
	var cut := {}
	for p in pairs:
		var k: AttackerUnit = p[1]
		if cut.has(p[2]) or load.get(k, 0) >= k.stats.resupply_units:
			continue
		cut[p[2]] = k.stats.resupply_cdr
		load[k] = load.get(k, 0) + 1
	for u in units.values():
		u.resupply = cut.get(u, 0.0)


# ---------------------------------------------------------------- dogs' healing

## Each healing dog keeps healing the units it took until they are full, fall or leave its reach, then
## takes the hurt units nearest it, up to heal_units of them; the closest pairs go first, and a unit one dog
## already heals is left to it (no stacking).
func _update_heal() -> void:
	var taken := {}
	var dogs := []
	for d in units.values():
		if not d.heals():
			continue
		dogs.append(d)
		d.patients = d.patients.filter(func(u): return d.can_heal(u) and not taken.has(u))
		for u in d.patients:
			taken[u] = d
	var pairs := []
	for d in dogs:
		if d.patients.size() >= d.stats.heal_units:
			continue
		for u in units.values():
			if not taken.has(u) and d.can_heal(u):
				pairs.append([d.global_position.distance_to(u.global_position), d, u])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	for p in pairs:
		var d: AttackerUnit = p[1]
		if taken.has(p[2]) or d.patients.size() >= d.stats.heal_units:
			continue
		d.patients.append(p[2])
		taken[p[2]] = d
	for u in units.values():
		u.medic = taken.get(u)


# ---------------------------------------------------------------- scout formation

func is_scouting(u: AttackerUnit) -> bool:
	return scout_groups.any(func(g): return u.unit_id in g.rhinos)


## Turns scout formation on for the selection, or off if its rhinos are all scouting already.
func _toggle_scout(ids: Array) -> void:
	var list := _resolve(ids)
	var rhinos := list.filter(func(u): return u.stats.get("scouts", false)).map(func(u): return u.unit_id)
	var escorts := list.filter(func(u): return not u.stats.get("scouts", false)).map(func(u): return u.unit_id)
	if rhinos.is_empty():
		return
	var all_scouting := rhinos.all(func(id): return is_scouting(units[id]))
	_leave_scouts(rhinos)
	if all_scouting or escorts.is_empty():
		return
	for id in rhinos:
		units[id].formation_id = 0
	scout_groups.append({"rhinos": rhinos, "escorts": escorts})
	_update_scouts()


func _leave_scouts(rhino_ids: Array) -> void:
	for g in scout_groups:
		g.rhinos = g.rhinos.filter(func(id): return not id in rhino_ids)
	scout_groups = scout_groups.filter(func(g): return not g.rhinos.is_empty())


## Scouting rhinos ignore orders given to their whole group (they keep circling the mass);
## ordered without their escorts, they leave the scout formation and obey.
func _without_scouts(ids: Array) -> Array:
	var keep := []
	var leaving := []
	for id in ids:
		var g = null
		for sg in scout_groups:
			if id in sg.rhinos:
				g = sg
		if g == null:
			keep.append(id)
		elif not g.escorts.any(func(e): return e in ids):
			keep.append(id)
			leaving.append(id)
	_leave_scouts(leaving)
	return keep


## Spreads each scouting group's rhinos evenly on a ring just outside its mass of escorts.
func _update_scouts() -> void:
	for g in scout_groups:
		g.rhinos = g.rhinos.filter(func(id): return units.has(id))
		g.escorts = g.escorts.filter(func(id): return units.has(id))
	scout_groups = scout_groups.filter(func(g): return not g.rhinos.is_empty() and not g.escorts.is_empty())
	for g in scout_groups:
		var centre := Vector3.ZERO
		for id in g.escorts:
			centre += units[id].global_position
		centre /= g.escorts.size()
		var mass_r := 0.0
		for id in g.escorts:
			var u: AttackerUnit = units[id]
			mass_r = maxf(mass_r, _flat_dist(u.global_position, centre) + u.stats.radius)
		var ring_r := mass_r + SCOUT_MARGIN
		# Keep each rhino on the side it already is, so they don't cross through the mass:
		# sort by current angle around the mass and spread them evenly from there.
		var rhinos: Array = g.rhinos.map(func(id): return units[id])
		var ang := func(u): return atan2(u.global_position.z - centre.z, u.global_position.x - centre.x)
		rhinos.sort_custom(func(a, b): return ang.call(a) < ang.call(b))
		var n := rhinos.size()
		var best_off := 0.0
		var best_cost := INF
		for k in 12 * n:
			var off := TAU * k / (12.0 * n)
			var cost := 0.0
			for i in n:
				var a := off + TAU * i / n
				cost += _flat_dist(rhinos[i].global_position, centre + Vector3(cos(a), 0, sin(a)) * ring_r)
			if cost < best_cost:
				best_cost = cost
				best_off = off
		for i in n:
			var a := best_off + TAU * i / n
			var slot := centre + Vector3(cos(a), 0, sin(a)) * ring_r
			var u: AttackerUnit = rhinos[i]
			var cur = u.order.get("pos")
			if cur == null or _flat_dist(cur, slot) > 2.0:
				u.set_order({"type": "move", "pos": slot})


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _resolve(ids: Array) -> Array:
	var out := []
	for id in ids:
		var u = units.get(id)
		if u and is_instance_valid(u) and u.is_alive():
			out.append(u)
	return out


## Square-ish grid of offsets centered on the destination so units don't all fight
## for the same spot.
static func formation_offsets(count: int, spacing: float) -> Array[Vector3]:
	var cols := ceili(sqrt(count))
	var rows := ceili(float(count) / maxi(cols, 1))
	var out: Array[Vector3] = []
	for i in count:
		var c := i % cols
		var r := i / cols
		out.append(Vector3((c - (cols - 1) * 0.5) * spacing, 0, (r - (rows - 1) * 0.5) * spacing))
	return out
