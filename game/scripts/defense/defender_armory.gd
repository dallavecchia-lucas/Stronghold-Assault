class_name DefenderArmory
extends Node
## The defenders' war chest: credits that come in over time and buy AA Squads (AASquad). A bought
## squad deploys in a gate spawn hall (east, west and south in turn, behind the Gunner Squad in the
## south one), joins the roster (the hotbar: DefenderController) and sets out on its auto order. It
## leaves the roster when all its troopers are down.

signal squad_bought(squad: AASquad)
signal squad_lost(squad: AASquad)

const START_CREDITS := 400.0
const INCOME := 6.0
const AA_COST := 350
## One per hotbar key (F1-F6).
const MAX_SQUADS := 6
## Spawn halls the squads deploy in, in turn, and where in each hall (SPAWN_<face>3's frame, like
## LevelBuilder.SQUAD_POST_OFFSET: along the hall, facing its spawn ramp).
const HALLS := ["E", "W", "S"]
const POST_OFFSETS := {"E": Vector3(-3.0, 0.0, 0.15), "W": Vector3(-3.0, 0.0, 0.15), "S": Vector3(-6.5, 0.0, 0.15)}

var level: LevelBuilder
var credits := START_CREDITS
var income := INCOME
## Squads on the roster, in hotbar order.
var squads: Array[AASquad] = []

var _bought := 0


func _process(delta: float) -> void:
	credits += income * delta


func can_buy() -> bool:
	return credits >= AA_COST and squads.size() < MAX_SQUADS


## Buys an AA Squad and deploys it; null if there aren't the credits or the roster is full.
func buy() -> AASquad:
	if not can_buy():
		return null
	credits -= AA_COST
	_bought += 1
	var hall: String = HALLS[(_bought - 1) % HALLS.size()]
	var squad := AASquad.new()
	squad.setup(_bought)
	squad.name = "AASquad%d" % _bought
	squad.home = level.squad_post(hall, POST_OFFSETS[hall])
	squad.gates = level.gates.values()
	squad.wiped_out.connect(_on_wiped_out)
	level.add_child(squad)
	squads.append(squad)
	squad_bought.emit(squad)
	return squad


func _on_wiped_out(squad: AASquad) -> void:
	squads.erase(squad)
	squad_lost.emit(squad)
	# The fallen troopers finish going down before the squad goes.
	get_tree().create_timer(8.0).timeout.connect(squad.queue_free)
