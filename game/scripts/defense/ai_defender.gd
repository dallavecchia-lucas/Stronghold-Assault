class_name AIDefender
extends Node
## CPU commander for the defenders, the AIAttacker's opposite number: it spends the defenders' credits (DefenderArmory),
## gives the bought squads their auto orders, posts the Sniper and steers the garrison's spawn (Garrison). It drives
## nothing in first person: every post, squad and machine fights the way it does when the player has left it alone, so
## it is a defender who plays the whole match from the roster, never taking a gun.
##
## It exists for the balance simulator (SimDirector, `--sim=`): with it the CPU can play both sides of a match. The
## offline game still has no CPU buying squads against a human attacker.
##
## How it plays is its policy (`--def=`): DEFAULT_POLICY with a named POLICIES entry or a JSON file's keys laid over it.
##   build            what it buys, in order: "aa", "flame", "infiltrator", "sniper", "jet", "tank"
##   rebuy            with the list bought, it starts over at `rebuy_from` whenever the roster has room again (a squad
##                    lost): false stops at the end of the list
##   rebuy_from       where in `build` it starts over
##   reserve          credits it never spends
##   buy_after        seconds into the match before it buys anything
##   orders           the auto order each kind is given when bought: aa "MINES" / "GUARD", flame "CLEAR" / "GUARD",
##                    infiltrator "OP" (sabotage the helipads, one after another) / "HOLD"
##   sniper_post      where a Sniper holds: "gate" (out in front of her hall's gate, to one side of it) or "hall"
##   controls         how many of the garrison's four spawn controls it steers (the rest stay on their own sides, BASE)
##   spawn_priority   [[seconds, "BASE" | "FIELD"], ...]: what its controls' soldiers go for from then on
##   reinforce        its first control moves to the side with the most attackers close to it
##   reinforce_min    ... once that many are within REINFORCE_RANGE of the stronghold on that side

const DEFAULT_POLICY := {
	"build": ["sniper", "flame", "aa", "tank", "flame", "jet"],
	"rebuy": true, "rebuy_from": 0, "reserve": 0.0, "buy_after": 0.0,
	"orders": {"aa": "MINES", "flame": "CLEAR", "infiltrator": "OP"},
	"sniper_post": "gate",
	"controls": 1, "spawn_priority": [[0.0, "BASE"]],
	"reinforce": true, "reinforce_min": 6,
}
const POLICIES := {
	"default": {},
	# Buys nothing: the stronghold's own guns, garrison and drones (what the CPU defender has in the offline game).
	"passive": {"build": [], "reinforce": false},
	# Everything behind the walls: guns and mines, the garrison on the base.
	"turtle": {"build": ["aa", "sniper", "aa", "sniper", "tank", "tank"], "orders": {"aa": "MINES", "flame": "GUARD"}},
	# Out into the woodland: flame squads burning the forest back, the garrison sent out to the field early.
	"clear": {"build": ["flame", "flame", "sniper", "flame", "tank", "aa"], "spawn_priority": [[0.0, "BASE"], [150.0, "FIELD"]]},
	# The machines: the tank and the jet as soon as they can be paid for.
	"armor": {"build": ["tank", "jet", "tank", "aa", "sniper", "tank"]},
	# Deep raids on the attackers' outposts.
	"raid": {"build": ["infiltrator", "sniper", "infiltrator", "flame", "tank", "aa"]},
}
## Attackers this close to the middle of the map (flat, m) press on the side they are on.
const REINFORCE_RANGE := 170.0
## It moves its spawn at most this often (s), and only for a side with this many more attackers than where it is.
const REINFORCE_EVERY := 20.0
const REINFORCE_MARGIN := 3
## A Sniper's post out in front of her gate: this far out from the door and this far along the face (m).
const SNIPER_OUT := 9.0
const SNIPER_ALONG := 11.0

var level: LevelBuilder
var armory: DefenderArmory
var garrison: Garrison
var commander: AttackerCommander
var policy := DEFAULT_POLICY.duplicate(true)
## What it has bought so far, and credits spent.
var bought: Array[String] = []
var spent := 0.0
## Squads it has lost (wiped out, or a machine destroyed), by kind.
var lost := {}

var _clock := 0.0
var _think_cd := 1.0
var _next := 0
var _reinforce_cd := 0.0
var _op_turn := 0


## Lays `overrides` over the default policy.
func set_policy(overrides: Dictionary) -> void:
	policy = DEFAULT_POLICY.duplicate(true)
	for k in overrides:
		policy[k] = overrides[k]


func _ready() -> void:
	if armory:
		armory.squad_lost.connect(func(s): lost[kind_of(s)] = int(lost.get(kind_of(s), 0)) + 1)


func _process(delta: float) -> void:
	_clock += delta
	_think_cd -= delta
	if _think_cd > 0.0:
		return
	_think_cd = 1.0
	_buy()
	_infiltrator_ops()
	_spawns()


## "aa", "flame", "infiltrator", "sniper", "jet" or "tank": what `squad` (on the roster) is.
static func kind_of(squad) -> String:
	if squad is AASquad:
		return "aa"
	if squad is FlameSquad:
		return "flame"
	if squad is InfiltratorSquad:
		return "infiltrator"
	if squad is Sniper:
		return "sniper"
	if squad is DefenderJet:
		return "jet"
	if squad is DefenderTank:
		return "tank"
	return "squad"


## Buys the next thing on its list once the credits are there and the roster has room.
func _buy() -> void:
	if armory == null or _clock < float(policy.buy_after):
		return
	var build: Array = policy.build
	if build.is_empty():
		return
	if _next >= build.size():
		if not policy.rebuy:
			return
		_next = clampi(int(policy.rebuy_from), 0, build.size() - 1)
	var kind := String(build[_next])
	if not DefenderArmory.COSTS.has(kind) or armory.credits - DefenderArmory.COSTS[kind] < float(policy.reserve) \
			or not armory.can_buy(kind):
		return
	var squad = armory.buy(kind)
	if squad == null:
		return
	_next += 1
	bought.append(kind)
	spent += DefenderArmory.COSTS[kind]
	_brief(kind, squad)


## A bought squad's orders, by the policy.
func _brief(kind: String, squad) -> void:
	var order := String((policy.orders as Dictionary).get(kind, ""))
	match kind:
		"aa":
			(squad as AASquad).set_order(AASquad.Order.GUARD if order == "GUARD" else AASquad.Order.MINES)
		"flame":
			(squad as FlameSquad).set_order(FlameSquad.Order.GUARD if order == "GUARD" else FlameSquad.Order.CLEAR)
		"sniper":
			if policy.sniper_post == "gate":
				(squad as Sniper).hold_at = _sniper_post(squad)


## Out in front of the gate nearest the Sniper's hall, off to one side of the doorway.
func _sniper_post(squad) -> Vector3:
	var home: Vector3 = squad.home.origin
	var gate: Structure = null
	for g in level.gates.values():
		if gate == null or home.distance_to(g.global_position) < home.distance_to(gate.global_position):
			gate = g
	if gate == null:
		return home
	var out: Vector3 = LevelBuilder.SIDES[Garrison.side_of(gate.global_position)].dir
	var along := out.cross(Vector3.UP)
	var side := 1.0 if (bought.count("sniper") % 2) == 1 else -1.0
	var at := gate.global_position + out * SNIPER_OUT + along * SNIPER_ALONG * side
	return LevelBuilder.nav_closest(get_tree().root.get_world_3d().navigation_map, Vector3(at.x, 0.0, at.z))


## Infiltrator Squads on "OP": one standing by with no operation is sent at the next helipad the attackers hold.
func _infiltrator_ops() -> void:
	if armory == null or String((policy.orders as Dictionary).get("infiltrator", "OP")) != "OP":
		return
	var held := get_tree().get_nodes_in_group("attacker_bases").filter(func(b): return b.controlled)
	if held.is_empty():
		return
	for s in armory.squads:
		if s is InfiltratorSquad and s.op == null and s.sabotaging == null and not s.troopers.is_empty():
			s.set_order(held[_op_turn % held.size()])
			_op_turn += 1


## The garrison: its controls' priority by the clock, and its first control moved to the side under the most pressure.
func _spawns() -> void:
	if garrison == null or not garrison.set_up:
		return
	var n := clampi(int(policy.controls), 0, garrison.controls.size())
	var want := "BASE"
	for step in policy.spawn_priority:
		if _clock >= float(step[0]):
			want = String(step[1])
	var p := Garrison.Priority.FIELD if want == "FIELD" else Garrison.Priority.BASE
	for k in n:
		if garrison.controls[k].priority != p:
			garrison.set_priority(k, p)
	_reinforce_cd -= 1.0
	if n == 0 or not policy.reinforce or _reinforce_cd > 0.0 or commander == null:
		return
	var press := {}
	for u in commander.units.values():
		var at: Vector3 = u.global_position
		if not u.is_alive() or Vector2(at.x, at.z).length() > REINFORCE_RANGE:
			continue
		var side := Garrison.side_of(at)
		press[side] = int(press.get(side, 0)) + 1
	var here: String = garrison.controls[0].side
	var best := here
	for side in press:
		if press[side] > int(press.get(best, 0)):
			best = side
	if best != here and int(press[best]) >= int(policy.reinforce_min) and int(press[best]) >= int(press.get(here, 0)) + REINFORCE_MARGIN:
		garrison.move_spawn(0, best)
		_reinforce_cd = REINFORCE_EVERY
