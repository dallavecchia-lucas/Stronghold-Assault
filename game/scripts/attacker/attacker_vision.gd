class_name AttackerVision
extends Node
## The attackers' fog of war. Each attacking unit sees round itself as far as its sight
## (UnitTypes), the giraffe furthest; a Forward Helipad the attackers hold sees round its deck
## (BASE_SIGHT). Beyond that it is fog: the stronghold and the land are known, but not who stands
## there.
##
## In fog the defenders' soldiers and squad troopers can't be picked out: attackers never go after
## one on their own (AttackerUnit._find_enemy) and the attacking player can't order an attack on one
## (AttackerController). On the attacker's side (hide_enemies) they aren't drawn at all, and
## FogOverlay dims the land outside sight. The emplacements (gate guns, mortar, AA turrets) stay
## drawn: they are part of the stronghold. Raiders inside it hunt as ever: they are in among them.
##
## One per match (Match), for the CPU attacker too: a ping's reveal lasts while the infiltrator stays
## in sight (InfiltratorTrooper.revealed). With none (the showcases), everything is in sight.

## How far a Forward Helipad the attackers hold sees (m).
const BASE_SIGHT := 26.0
## Seconds between updates of who sees what.
const EVERY := 0.1
## A defender this far inside the edge of sight already shows (m): its body is in it.
const BODY := 0.6

static var instance: AttackerVision

var commander: AttackerCommander
## The attacker's side is the human player's: defenders in fog aren't drawn.
var hide_enemies := false
## [Vector3 position, sight] of every unit and building that sees, as of the last update.
var viewers: Array = []

var _cd := 0.0
## Defender instance id -> in sight, as of the last update.
var _seen := {}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = EVERY
	refresh()


## Recounts who sees and who is seen now.
func refresh() -> void:
	viewers.clear()
	for u in commander.units.values():
		if is_instance_valid(u) and u.is_alive():
			viewers.append([u.global_position, u.sight()])
	for b in get_tree().get_nodes_in_group("attacker_bases"):
		if b.controlled:
			viewers.append([b.global_position, BASE_SIGHT])
	_seen.clear()
	for d in get_tree().get_nodes_in_group("defender_targets"):
		var seen := _in_sight(d.global_position, BODY)
		_seen[d.get_instance_id()] = seen
		if hide_enemies and _hides(d):
			d.visible = seen


## True if the attackers see `p` (flat distance).
func in_sight(p: Vector3) -> bool:
	return _in_sight(p, 0.0)


func _in_sight(p: Vector3, margin: float) -> bool:
	for v in viewers:
		var at: Vector3 = v[0]
		var r: float = v[1] + margin
		if (at.x - p.x) * (at.x - p.x) + (at.z - p.z) * (at.z - p.z) <= r * r:
			return true
	return false


## The ones fog hides: soldiers and squad troopers, not the emplacements.
static func _hides(d: Node) -> bool:
	return d is DefenderSoldier or d is SquadTrooper


## True if the attackers see `p`; everything is in sight without fog of war.
static func sees(p: Vector3) -> bool:
	return instance == null or instance.in_sight(p)


## True if the attackers can pick out `t`: in sight, or something fog doesn't hide (a building, an
## emplacement).
static func sees_node(t: Node3D) -> bool:
	if instance == null or not _hides(t):
		return true
	var seen = instance._seen.get(t.get_instance_id())
	return seen if seen != null else instance._in_sight(t.global_position, BODY)
