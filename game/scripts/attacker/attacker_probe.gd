class_name AttackerProbe
extends Node
## A scripted attacker that plays one known shortcut as well as it can be played, against the CPU garrison, for balance
## regression (docs/balance/BALANCE_PLAN.md, section 2.2 and Phase 0): `--autotest=rush` or `--autotest=battery`.
## A balance patch that lets one of these win early has reopened the shortcut.
##   "rush"     nothing but Breaching Rams. They gather GROUP at a time, charge the gate and go for the Keep.
##   "battery"  MULES Mule Artillery first, shelling the gate from as far off as their guns reach (on the classic field:
##              from the flag they spawn at), then rams as in a rush.
## It attacks one lane: east on the classic field, west on the Jungle Keep (no river between the Quarry and the west
## gate). Neither comes past the Gunner Squad's hall, which is on the south way in.
## Like the CPU attacker it only uses AttackerCommander.submit(); its income is a player's (no difficulty multiplier).

const GROUP := 6
const MULES := 3
## Rams ram once the gate is within this share of how far a ram's surge carries them (as AIAttacker._ram_gates).
const RAM_REACH := 0.6
## A mule sets up once the gate is within this share of its gun's reach (as AIAttacker.GUN_SPARE).
const GUN_SPARE := 0.95

var commander: AttackerCommander
var level: LevelBuilder
var plan := "rush"
var side := "east"

var _cd := 1.0
var _mules := 0
## Unit id -> what it was last sent at ("gate", "keep").
var _sent := {}


func _ready() -> void:
	side = "west" if LevelBuilder.jungle else "east"


func _process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = 1.0
	_think()


func _think() -> void:
	var at := _spawn_index()
	if plan == "battery" and _mules < MULES:
		while _mules < MULES and commander.can_afford("mule"):
			if commander.submit({"type": "spawn", "unit": "mule", "spawn": at}) == 0:
				break
			_mules += 1
	else:
		while commander.can_afford("breacher"):
			if commander.submit({"type": "spawn", "unit": "breacher", "spawn": at}) == 0:
				break

	var gate: Structure = level.gates[side]
	var gate_up := gate.is_alive()
	var waiting := []
	var to_keep := []
	var charge := []
	for id in commander.units:
		var u: AttackerUnit = commander.units[id]
		if not u.is_controllable():
			continue
		if u.has_setup():
			_mule(u, gate, gate_up)
		elif not gate_up:
			if _sent.get(id) != "keep" or u.is_idle():
				_sent[id] = "keep"
				to_keep.append(id)
		elif _sent.get(id) != "gate":
			waiting.append(id)
		elif u.ram_ready() and u.global_position.distance_to(gate.get_approach_point()) \
				<= u.stats.ram_duration * u.stats.speed * u.stats.ram_speed * RAM_REACH:
			charge.append(id)
	if gate_up and waiting.size() >= GROUP:
		for id in waiting:
			_sent[id] = "gate"
		commander.submit({"type": "attack", "units": waiting, "target": gate.get_path()})
	if not charge.is_empty():
		commander.submit({"type": "ram", "units": charge})
		commander.submit({"type": "attack", "units": charge, "target": gate.get_path()})
	if not to_keep.is_empty():
		commander.submit({"type": "attack", "units": to_keep, "target": level.keep.get_path()})


## A Mule Artillery: it walks at the gate until its gun reaches it, sets up there and shells the gate whenever it has
## reloaded. With the gate down it has nothing left to do.
func _mule(u: AttackerUnit, gate: Structure, gate_up: bool) -> void:
	if not gate_up or u.setting_up() or u.packing_up():
		return
	var id: int = u.unit_id
	var flat := Vector2(u.global_position.x - gate.global_position.x, u.global_position.z - gate.global_position.z).length()
	if u.is_packed():
		if flat <= u.stats.bombard_range * GUN_SPARE:
			commander.submit({"type": "setup", "units": [id], "on": true})
		elif _sent.get(id) != "gate":
			_sent[id] = "gate"
			commander.submit({"type": "attack", "units": [id], "target": gate.get_path()})
	elif u.is_armed() and u.bombard_ready():
		commander.submit({"type": "bombard", "units": [id], "pos": gate.global_position})


## Where its units spawn: the lane's Forward Helipad while the attackers hold it, else the map's edge. The battery on the
## classic field always uses the edge flag: that is the shortcut it tests (the gate is in the mules' reach from there, and
## the flag is out of the mortar's).
func _spawn_index() -> int:
	if plan != "battery" or LevelBuilder.jungle:
		for k in commander.spawn_bases.size():
			var b = commander.spawn_bases[k]
			if b != null and b.side == side and commander.spawn_open(k):
				return k
	return level.edge_spawns.get(side, 0)
