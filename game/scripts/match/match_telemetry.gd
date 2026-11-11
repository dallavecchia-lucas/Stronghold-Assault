class_name MatchTelemetry
extends Node
## Records one match for balance work (docs/balance/BALANCE_PLAN.md, Phase 0): a sample of the state every SAMPLE_EVERY
## seconds of game time, the events that decide it (spawns, deaths, posts knocked out, gates down, the Keep's first hit,
## helipads lost and retaken) and the result. finish() writes it all as JSON to GameConfig.telemetry_path (if one was
## given) and prints a one-line summary, `BOTMATCH ...`, that tools/balance/run_matches.py reads.

const SAMPLE_EVERY := 5.0

var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var drones: DroneBay

## Seconds of game time since the match started.
var clock := 0.0
var samples: Array = []
var events: Array = []
## Supply spent on units, and the cost of the units lost; units spawned and lost, by type.
var supply_spent := 0.0
var supply_lost := 0.0
var spawned := {}
var lost := {}
## When the first gate fell (and which), and when the Keep was first hit; -1: never.
var gate_time := -1.0
var gate_side := ""
var keep_first_hit := -1.0
var posts_down := 0

var _sample_cd := 0.0
var _done := false


func _ready() -> void:
	commander.unit_spawned.connect(_on_spawned)
	commander.unit_died.connect(_on_died)
	for s in level.gates:
		level.gates[s].destroyed.connect(_on_gate_down.bind(s))
	level.keep.damaged.connect(_on_keep_damaged)
	for st in level.stations:
		st.became_unavailable.connect(_on_post_down)
	for b in level.bases:
		b.sabotaged.connect(func(base): _event("pad_lost", {"pad": base.display_name}))
		b.retaken.connect(func(base): _event("pad_retaken", {"pad": base.display_name}))
	if armory:
		armory.squad_bought.connect(func(s): _event("bought", {"what": s.station_name}))
		armory.squad_lost.connect(func(s): _event("squad_lost", {"what": s.station_name}))
	_sample()


func _process(delta: float) -> void:
	if _done:
		return
	clock += delta
	_sample_cd -= delta
	if _sample_cd <= 0.0:
		_sample_cd = SAMPLE_EVERY
		_sample()


func _event(kind: String, more := {}) -> void:
	var e := {"t": snappedf(clock, 0.1), "e": kind}
	e.merge(more)
	events.append(e)


func _on_spawned(u: AttackerUnit) -> void:
	var cost: float = UnitTypes.DATA[u.type_id].cost
	supply_spent += cost
	spawned[u.type_id] = spawned.get(u.type_id, 0) + 1
	_event("spawn", {"unit": u.type_id})


func _on_died(u: AttackerUnit) -> void:
	var cost: float = UnitTypes.DATA[u.type_id].cost
	supply_lost += cost
	lost[u.type_id] = lost.get(u.type_id, 0) + 1
	var p := u.global_position
	_event("death", {"unit": u.type_id, "inside": u.raiding, "at": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]})


func _on_gate_down(_gate, gate_name: String) -> void:
	if gate_time < 0.0:
		gate_time = clock
		gate_side = gate_name
	_event("gate_down", {"gate": gate_name})


func _on_keep_damaged(_keep) -> void:
	if keep_first_hit < 0.0:
		keep_first_hit = clock
		_event("keep_first_hit")


func _on_post_down(station) -> void:
	posts_down += 1
	_event("post_down", {"post": station.station_name})


func _sample() -> void:
	var by_type := {}
	var inside := 0
	for u in commander.units.values():
		if not is_instance_valid(u):
			continue
		by_type[u.type_id] = by_type.get(u.type_id, 0) + 1
		if u.raiding:
			inside += 1
	var gates := {}
	for s in level.gates:
		gates[s] = snappedf(level.gates[s].hp, 1.0)
	var posts_up := 0
	for st in level.stations:
		if st.can_possess():
			posts_up += 1
	var aa_up := 0
	for t in level.aa_turrets:
		if t.is_alive():
			aa_up += 1
	var row := {
		"t": snappedf(clock, 0.1), "supply": snappedf(commander.supply, 1.0), "income": snappedf(commander.income_rate(), 0.01),
		"units": commander.units.size(), "by_type": by_type, "inside": inside, "gates": gates,
		"keep": snappedf(level.keep.hp, 1.0), "posts_up": posts_up, "aa_up": aa_up,
	}
	if drones:
		row["drones"] = drones.alive_count()
		row["drones_aloft"] = drones.airborne_count()
	if armory:
		row["credits"] = snappedf(armory.credits, 1.0)
		row["roster"] = armory.squads.size()
	samples.append(row)


## The match is over (`winner`: "attacker", "defender", or "none" for an autotest stopped early): the last sample, the
## summary line, and the file.
func finish(winner: String) -> Dictionary:
	if _done:
		return {}
	_done = true
	_sample()
	var summary := {
		"winner": winner, "length": snappedf(clock, 0.1), "mode": GameConfig.autotest, "map": GameConfig.map,
		"seed": GameConfig.seed_value, "difficulty": GameConfig.difficulty, "match_time": level.match_time(),
		"drones": GameConfig.drones, "gate_time": snappedf(gate_time, 0.1), "gate_side": gate_side,
		"keep_first_hit": snappedf(keep_first_hit, 0.1), "keep_hp": snappedf(level.keep.hp, 1.0),
		"supply_spent": supply_spent, "supply_lost": supply_lost, "spawned": spawned, "lost": lost, "posts_down": posts_down,
	}
	print("BOTMATCH %s" % JSON.stringify(summary))
	if GameConfig.telemetry_path != "":
		var f := FileAccess.open(GameConfig.telemetry_path, FileAccess.WRITE)
		if f == null:
			push_error("MatchTelemetry: can't write %s" % GameConfig.telemetry_path)
		else:
			f.store_string(JSON.stringify({"summary": summary, "samples": samples, "events": events}, "\t"))
			f.close()
	return summary
