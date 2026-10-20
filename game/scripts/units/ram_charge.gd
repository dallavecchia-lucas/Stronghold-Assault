class_name RamCharge
extends RefCounted
## Breaching Rams charging a gate. Ordered at a ground gate while their ram is on, they line up
## side by side across its doorway and slam into it, each once, for ram_gate_damage. Only
## ram_gate_slots fit in front of a doorway at a time: the rams nearest to it that can still get
## there before their ram runs out take the free slots (rams already charging it keep theirs), and
## the rest call their ram off.

## How close to the gate's surface a charging ram has to get to slam into it.
const REACH := 1.5
## Distance between neighbouring slots across the doorway (LevelBuilder.DOOR_SIZE is 3 m wide).
const SLOT_SPACING := 1.0


## Ground gates only: the keep is inside the mountain, out of reach of a charge.
static func is_gate(t: Node) -> bool:
	return t is Structure and not t.buried and t.is_alive()


## Where the ram in `slot` runs to: in front of the doorway, slots spread across it.
static func slot_position(gate: Structure, slot: int, slots: int) -> Vector3:
	return gate.get_approach_point() + gate.global_basis.x * (slot - (slots - 1) * 0.5) * SLOT_SPACING


## The rams out of `rams` that charge `gate`, as [ram, slot] pairs.
static func allocate(rams: Array, gate: Structure) -> Array:
	var ramming := rams.filter(func(u): return u.is_ramming())
	if ramming.is_empty() or not is_gate(gate):
		return []
	var slots: int = ramming[0].stats.ram_gate_slots
	var free := range(slots)
	for u in gate.get_tree().get_nodes_in_group("attacker_units"):
		if u.charge_gate == gate and not u in rams:
			free.erase(u.charge_slot)
	var mid := gate.get_approach_point()
	var in_time := ramming.filter(func(u): return _flat(u.global_position, mid) <= u.ram_reach())
	in_time.sort_custom(func(a, b): return _flat(a.global_position, mid) < _flat(b.global_position, mid))
	var chosen := in_time.slice(0, free.size())
	# Left to right across the doorway, so the chosen rams don't cross paths to their slots.
	var across := gate.global_basis.x
	chosen.sort_custom(func(a, b): return a.global_position.dot(across) < b.global_position.dot(across))
	var out := []
	var first := (free.size() - chosen.size()) / 2  # the middle slots when there are spare ones
	for i in chosen.size():
		out.append([chosen[i], free[first + i]])
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
