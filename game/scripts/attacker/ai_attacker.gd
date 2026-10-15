class_name AIAttacker
extends Node
## CPU commander for the attacking army. Builds up waves at a spawn point, then sends
## them at the gate on that side; once a gate falls everyone pushes for the keep.
## Uses the same command interface as the human RTS player.

var commander: AttackerCommander
var level: LevelBuilder

var _think_cd := 2.0
var _wave := 0
var _pending: Array[String] = []
var _staging: Array[int] = []
var _wave_spawn := 0
var _wave_side := "south"
var _first_wave_delay := 15.0

const SPAWN_SIDES := ["south", "east", "west"]


func _process(delta: float) -> void:
	_first_wave_delay -= delta
	_think_cd -= delta
	if _think_cd > 0.0 or _first_wave_delay > 0.0:
		return
	_think_cd = 1.0
	_think()


func _think() -> void:
	if _pending.is_empty() and _staging.is_empty():
		_plan_wave()

	while not _pending.is_empty() and commander.can_afford(_pending[0]):
		var id := commander.submit({"type": "spawn", "unit": _pending[0], "spawn": _wave_spawn})
		if id == 0:
			break
		_pending.pop_front()
		_staging.append(id)
		var rally: Vector3 = commander.spawn_points[_wave_spawn] * 0.72
		commander.submit({"type": "move", "units": [id], "pos": rally, "attack": true})

	if _pending.is_empty() and not _staging.is_empty():
		_launch_wave()

	_reassign_idle()


func _plan_wave() -> void:
	_wave += 1
	_wave_spawn = randi() % SPAWN_SIDES.size()
	_wave_side = SPAWN_SIDES[_wave_spawn]
	var riflemen := mini(4 + _wave * 2, 16)
	var heavies := mini(_wave / 2, 5)
	var rams := 1 if _wave >= 2 and (_wave % 2 == 0 or _wave > 5) else 0
	for i in rams:
		_pending.append("breacher")
	for i in riflemen:
		_pending.append("rifleman")
		if i % 3 == 1 and heavies > 0:
			_pending.append("heavy")
			heavies -= 1


func _launch_wave() -> void:
	var gate: Structure = level.gates[_wave_side]
	var ids := _staging.duplicate()
	_staging.clear()
	if gate.is_alive():
		var infantry := []
		var siege := []
		for id in ids:
			var u = commander.units.get(id)
			if u == null:
				continue
			if u.stats.structures_only:
				siege.append(id)
			else:
				infantry.append(id)
		# Infantry fight their way up to the gate and suppress the walls; rams go for the gate.
		var out: Vector3 = LevelBuilder.SIDES[_wave_side].dir
		commander.submit({"type": "move", "units": infantry, "pos": out * (LevelBuilder.FORT_HALF + 14.0), "attack": true})
		commander.submit({"type": "attack", "units": siege, "target": gate.get_path()})
	else:
		_push_keep(ids)


func _push_keep(ids: Array) -> void:
	commander.submit({"type": "attack", "units": ids, "target": level.keep.get_path()})


## Units with nothing to do look for the next objective.
func _reassign_idle() -> void:
	var breached := level.gates.values().any(func(g): return not g.is_alive())
	var idle := []
	for id in commander.units:
		if id in _staging:
			continue
		var u: AttackerUnit = commander.units[id]
		if u.is_idle():
			idle.append(id)
	if idle.is_empty():
		return
	if breached:
		_push_keep(idle)
		return
	# No breach yet: hit the nearest standing gate.
	var by_gate := {}
	for id in idle:
		var u: AttackerUnit = commander.units[id]
		var best: Structure = null
		var best_d := INF
		for g in level.gates.values():
			if g.is_alive():
				var d := u.global_position.distance_to(g.global_position)
				if d < best_d:
					best_d = d
					best = g
		if best:
			if not by_gate.has(best):
				by_gate[best] = []
			by_gate[best].append(id)
	for g in by_gate:
		commander.submit({"type": "attack", "units": by_gate[g], "target": g.get_path()})
