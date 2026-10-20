class_name AttackerCommander
extends Node
## Authoritative state of the attacking army: supply, spawning and orders.
##
## Every attacker action (from the RTS player or the CPU) goes through submit() as a
## plain Dictionary. Keeping commands serializable means online play can later just
## send these over the network to whoever runs the match.
##
##   {"type": "spawn", "unit": "rifleman", "spawn": 0}
##   {"type": "move", "units": [ids], "pos": Vector3, "attack": bool}
##   {"type": "attack", "units": [ids], "target": NodePath}
##   {"type": "cluster", "units": [ids], "pos": Vector3}   rhinos bomb around pos (RhinoAim)
##   {"type": "smoke", "units": [ids], "pos": Vector3}   the ready hippo closest to pos lays a
##                                                     smoke screen toward it (HippoSmoke)
##   {"type": "scout", "units": [ids]}   toggle scout formation: the rhinos in the selection
##                                       ring the rest of it so their anti-air covers the mass

signal unit_spawned(unit: AttackerUnit)
signal unit_died(unit: AttackerUnit)

const UNIT_CAP := 60
const BASE_INCOME := 12.0
## How far outside the edge of the mass scouting rhinos keep.
const SCOUT_MARGIN := 5.0

var supply := 250.0
var income := BASE_INCOME
var units := {}  # id -> AttackerUnit
var spawn_points: Array[Vector3] = []
var units_root: Node3D

var _next_id := 1
var _next_formation := 1
## Scout formations: [{"rhinos": [ids], "escorts": [ids]}]
var scout_groups: Array = []
var _scout_cd := 0.0


func _process(delta: float) -> void:
	supply += income * delta
	_scout_cd -= delta
	if _scout_cd <= 0.0:
		_scout_cd = 0.5
		_update_scouts()


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
		"smoke":
			_smoke(cmd.units, cmd.pos)
		"scout":
			_toggle_scout(cmd.units)
	return 0


func _spawn(type_id: String, spawn_idx: int) -> int:
	if not UnitTypes.DATA.has(type_id) or not can_afford(type_id):
		return 0
	supply -= UnitTypes.DATA[type_id].cost
	var id := _next_id
	_next_id += 1
	var u := AttackerUnit.new()
	u.setup(type_id, id)
	var base: Vector3 = spawn_points[clampi(spawn_idx, 0, spawn_points.size() - 1)]
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
	var offsets := formation_offsets(list.size(), 2.2)
	var fid := _next_formation
	_next_formation += 1
	for i in list.size():
		list[i].formation_id = fid
		list[i].set_order({"type": "attack_move" if attack else "move", "pos": pos + offsets[i]})


func _attack(ids: Array, target_path: NodePath) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if not Combat.is_valid_target(target):
		return
	for u in _resolve(_without_scouts(ids)):
		u.formation_id = 0
		u.set_order({"type": "attack", "target": target})


func _cluster(ids: Array, pos: Vector3) -> void:
	var rhinos := _resolve(ids).filter(func(u): return u.cluster_ready())
	var aims := RhinoAim.solve(rhinos, pos)
	for i in rhinos.size():
		rhinos[i].start_cluster(aims[i])


func _smoke(ids: Array, pos: Vector3) -> void:
	var hippo := HippoSmoke.pick(_resolve(ids).filter(func(u): return u.smoke_ready()), pos)
	if hippo:
		hippo.start_smoke(pos)


# ---------------------------------------------------------------- scout formation

func is_scouting(u: AttackerUnit) -> bool:
	return scout_groups.any(func(g): return u.unit_id in g.rhinos)


## Turns scout formation on for the selection, or off if its rhinos are all scouting already.
func _toggle_scout(ids: Array) -> void:
	var list := _resolve(ids)
	var rhinos := list.filter(func(u): return u.role == "anti_air").map(func(u): return u.unit_id)
	var escorts := list.filter(func(u): return u.role != "anti_air").map(func(u): return u.unit_id)
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
