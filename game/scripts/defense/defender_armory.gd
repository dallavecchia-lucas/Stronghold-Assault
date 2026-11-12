class_name DefenderArmory
extends Node
## The defenders' war chest: credits that come in over time and buy squads: AA Squads (AASquad),
## Flame Squads (FlameSquad), Infiltrator Squads (InfiltratorSquad) and Snipers (Sniper: one marksman,
## on the roster like a squad), and the two machines (DefenderMachine): the Fighter Jet (DefenderJet) and the
## Hover Tank (DefenderTank). A bought squad deploys in a gate spawn hall (east, west and south in
## turn, behind the Gunner Squad in the south one), joins the roster (the hotbar: DefenderController)
## and sets out on its auto order. It leaves the roster when all its troopers are down (a machine, when it
## is destroyed). The jet scrambles into the air in front of the gate hall's face, the tank deploys on the
## ground outside the gate: a hover tank is too broad for the halls' ramps.

signal squad_bought(squad)
signal squad_lost(squad)

const START_CREDITS := 400.0
const INCOME := 6.0
const AA_COST := 350
const FLAME_COST := 300
const INFILTRATOR_COST := 280
const SNIPER_COST := 220
const JET_COST := 600
const TANK_COST := 450
## What each kind costs.
const COSTS := {"aa": AA_COST, "flame": FLAME_COST, "infiltrator": INFILTRATOR_COST, "sniper": SNIPER_COST,
		"jet": JET_COST, "tank": TANK_COST}
## How far in front of its gate the tank deploys (m).
const TANK_OUTSIDE := 30.0
## One per hotbar key (F1-F6).
const MAX_SQUADS := 6
## Spawn halls the squads deploy in, in turn, and where in each hall (SPAWN_<face>3's frame, like
## LevelBuilder.SQUAD_POST_OFFSET: along the hall, facing its spawn ramp).
const HALLS := ["E", "W", "S"]
const POST_OFFSETS := {"E": Vector3(-3.0, 0.0, 0.15), "W": Vector3(-3.0, 0.0, 0.15), "S": Vector3(-6.5, 0.0, 0.15)}

var level: LevelBuilder
var credits := START_CREDITS
var income := INCOME
## Squads and machines on the roster, in hotbar order.
var squads: Array = []

var _bought := 0
## Squads bought of each kind (they are numbered by kind: AA Squad 2, Flame Squad 1).
var _numbers := {"aa": 0, "flame": 0, "infiltrator": 0, "sniper": 0, "jet": 0, "tank": 0}


func _process(delta: float) -> void:
	credits += income * delta


func can_buy(kind := "aa") -> bool:
	return credits >= COSTS[kind] and squads.size() < MAX_SQUADS


## Buys a squad of `kind` ("aa", "flame", "infiltrator", "sniper") or a machine ("jet", "tank") and deploys it; null if
## there aren't the credits or the roster is full.
func buy(kind := "aa"):
	if not can_buy(kind):
		return null
	credits -= COSTS[kind]
	_bought += 1
	_numbers[kind] += 1
	var hall: String = HALLS[(_bought - 1) % HALLS.size()]
	if kind == "jet" or kind == "tank":
		return _deploy_machine(kind, hall)
	var squad: DefenderSquad
	match kind:
		"flame":
			squad = FlameSquad.new()
		"infiltrator":
			squad = InfiltratorSquad.new()
		"sniper":
			squad = Sniper.new()
		_:
			squad = AASquad.new()
	squad.setup(_numbers[kind])
	squad.name = {"flame": "FlameSquad%d", "infiltrator": "InfiltratorSquad%d", "sniper": "Sniper%d"}.get(kind, "AASquad%d") % _numbers[kind]
	squad.home = level.squad_post(hall, POST_OFFSETS[hall])
	squad.gates = level.gates.values()
	squad.wiped_out.connect(_on_wiped_out)
	level.add_child(squad)
	squads.append(squad)
	squad_bought.emit(squad)
	return squad


func _deploy_machine(kind: String, hall: String) -> DefenderMachine:
	var m: DefenderMachine = DefenderJet.new() if kind == "jet" else DefenderTank.new()
	m.setup(_numbers[kind])
	m.name = ("FighterJet%d" if kind == "jet" else "HoverTank%d") % _numbers[kind]
	m.home = level.squad_post(hall, POST_OFFSETS[hall])
	if kind == "tank":
		# On the ground outside the hall's gate, facing out.
		var side: String = LevelBuilder.SIDES.keys().filter(func(k): return LevelBuilder.SIDES[k].face == hall)[0]
		var out: Vector3 = LevelBuilder.SIDES[side].dir
		var gate: Structure = level.gates.get(side)
		var at: Vector3 = (gate.global_position if gate else m.home.origin) + out * TANK_OUTSIDE
		m.home = Transform3D(Basis.looking_at(out, Vector3.UP), Vector3(at.x, 0.0, at.z))
	m.gates = level.gates.values()
	m.map_half = LevelBuilder.map_half
	m.loiter_centre = Vector3.ZERO
	m.wiped_out.connect(_on_wiped_out)
	level.add_child(m)
	squads.append(m)
	squad_bought.emit(m)
	return m


func _on_wiped_out(squad) -> void:
	squads.erase(squad)
	squad_lost.emit(squad)
	# The fallen troopers finish going down before the squad goes.
	get_tree().create_timer(8.0).timeout.connect(squad.queue_free)
