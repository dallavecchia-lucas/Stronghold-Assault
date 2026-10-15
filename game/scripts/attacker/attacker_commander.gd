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

signal unit_spawned(unit: AttackerUnit)
signal unit_died(unit: AttackerUnit)

const UNIT_CAP := 60
const BASE_INCOME := 9.0

var supply := 200.0
var income := BASE_INCOME
var units := {}  # id -> AttackerUnit
var spawn_points: Array[Vector3] = []
var units_root: Node3D

var _next_id := 1


func _process(delta: float) -> void:
	supply += income * delta


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
	var list := _resolve(ids)
	var offsets := formation_offsets(list.size(), 2.2)
	for i in list.size():
		list[i].set_order({"type": "attack_move" if attack else "move", "pos": pos + offsets[i]})


func _attack(ids: Array, target_path: NodePath) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if not Combat.is_valid_target(target):
		return
	for u in _resolve(ids):
		u.set_order({"type": "attack", "target": target})


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
