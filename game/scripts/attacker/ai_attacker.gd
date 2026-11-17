class_name AIAttacker
extends Node
## CPU commander for the attacking army. Builds up waves at its one base (the Mobile Command Citadel: nothing spawns at
## the Forward Helipads, its outposts), then sends them at the gate on a side it picks; once a
## gate falls everyone pushes for the air vents on the roofs. A helipad the defenders sabotaged is retaken by the
## ground units nearest it (_retake_bases): it sees for the army. It never goes after the defenders' infiltrators: it
## doesn't know they are there (their low profile, Combat.low_profile), unless its giraffes' pings
## reveal them (_giraffe_pings). Its bears dive when they are shot at out swimming (_bear_dives). Its lionesses
## hunt the defenders out on the field (_lioness_hunts). Its dogs heal; it can't see the defenders' mines any more
## than a player can, but one going off under its army tells it a minefield is there: the dogs near the blast sweep
## for mines until they find no more (_dog_modes).
## Its Serpent Snipers snipe from the trees in reach of the gate they go for, and lie in wait round bushes where
## the army saw the defenders out on the field (_serpent_skills). Its Mule Artillery set their guns up as soon as
## the stronghold is in reach and shell it whenever they have reloaded (_mule_guns).
## On the Jungle Keep it keeps a bridge standing on each way to the stronghold that crosses a river (BRIDGE_SPOTS:
## over the main river in front of the citadel, over the east river by the Outpost), dropping another when one is
## brought down while it has any left (_bridges); its move orders ferry the riders across on its hippos and
## elephants like a player's do. Defenders on one of its bridges (the alarm): the ground units nearest it go and
## fight them (_bridge_alarms).
## Uses the same command interface as the human RTS player.

var commander: AttackerCommander
var level: LevelBuilder
## The defenders' drones: only bears and AA units can hurt them, so its waves carry more of both while swarms
## are up (_plan_wave), or the army would have no answer at all.
var drones: DroneBay

## How it plays (the balance simulator's `--atk=`: SimDirector): DEFAULT_POLICY with a named POLICIES entry or a JSON file's
## keys laid over it. The default is the CPU attacker as it always played.
##   income_mult       its war chest against a player's (AttackerCommander.START_CREDITS, and any income); null: the
##                     difficulty's
##   first_wave_delay  seconds before it spawns anything
##   sides             which gate a wave goes for: "random", "south" / "east" / "west", "rotate" (each in turn), "stick" (one
##                     picked at random and kept until it falls), "weakest" (the standing gate with the least health; a
##                     random one while all are whole)
##   split             a wave's infantry splits over this many gates at once (multi-front): 1, 2 or 3
##   wave_scale        every count of a wave times this (rounded; a type in the wave keeps at least one)
##   waves             its own waves instead of the built-in mix: [{type: count}, ...], wave k taking entry k and waves past
##                     the end the last one, each count growing by `growth` of itself a wave past the end
##   growth            see `waves`
##   drone_answer      more bears and rhinos while drone swarms are up (the built-in answer to drones)
##   launch_at         the army gathers at the base until this many units stand ready (wave after wave planned and
##                     spawned meanwhile) before any of it sets off; 0: each wave sets off as soon as it is out
##   regroup           a wave first gathers this far (m, flat) from the middle of the map on its side, in the woods out of
##                     the defenders' reach, and goes in only once it is together (regroup_ready of its ground units within
##                     REGROUP_REACH of the spot) or regroup_wait seconds after it set off; 0: straight in
##   regroup_ready     see `regroup`
##   regroup_wait      see `regroup`
##   standoff          its Mule Artillery and Bison Field Guns work on their own from the moment they are out, from firing
##                     spots just outside the stronghold's guns' reach (_artillery); its giraffes walk with them (spotters)
##   bison_fire        its Bison Field Guns shell what is in their reach (_gun_target); otherwise they never fire
##   shell_vents       its artillery shells the air vents in its reach too (after the guns and the defenders it sees)
##   siege             the massed army (launch_at, or the unit cap) waits at the base while its artillery shells the guns on
##                     the face it goes for, until siege_guns or fewer of them are left or it has waited `siege` seconds;
##                     0: no wait
##   siege_guns        see `siege`
##   rhino_cluster     its rhinos cluster-bomb the defenders on the ground they see in their reach
##   talon_soldiers    its talons' bombs go for the guns, then the defenders they see, never the gates
##   smoke             its hippos lay smoke screens between themselves and the deck guns in reach of them
##   missiles          its elephants fire missile salvos at the defenders' aircraft in reach (the jet before drones)
##   escort            while it waits for its artillery (`siege`), the massed army stands guard by the guns out in the woods
##                     (ESCORT_BACK behind them) instead of at the base: the defenders' tank and jet find them escorted;
##                     and the guns keep to the base until the army has massed, then go out with it
##   artillery_keep    every wave makes good the Mule Artillery lost, to keep this many (0: the waves' own count)
##   vents_from        from this many seconds into the match, its artillery goes for the air vents first (a vent in its
##                     reach, else a safe firing spot for one), the guns only when no vent can be had; 0: never by the clock
##   vents_breach      ... and so from the moment a gate falls
##   (`sides` "guns": the standing gate whose face has the fewest live deck guns, the nearest to the base of those while
##                     they are even)
const DEFAULT_POLICY := {"income_mult": null, "first_wave_delay": 15.0, "sides": "random", "split": 1, "wave_scale": 1.0,
		"waves": [], "growth": 0.0, "drone_answer": true, "launch_at": 0, "regroup": 0.0, "regroup_ready": 0.7,
		"regroup_wait": 150.0, "standoff": false, "bison_fire": false, "shell_vents": false, "siege": 0.0, "siege_guns": 2,
		"rhino_cluster": false, "talon_soldiers": false, "smoke": false, "missiles": false, "escort": false,
		"artillery_keep": 0, "vents_from": 0.0, "vents_breach": false}
const POLICIES := {
	"default": {},
	# A player's income rather than the difficulty's, otherwise as ever.
	"even": {"income_mult": 1.0},
	# Everything at one gate until it falls.
	"stick": {"income_mult": 1.0, "sides": "stick"},
	# Two gates at once, the stronghold's garrison split.
	"split": {"income_mult": 1.0, "sides": "rotate", "split": 2},
	# Cheap, early and often: bears, kangaroos, chimps and rams, no heavies.
	"rush": {"income_mult": 1.0, "first_wave_delay": 5.0, "sides": "stick", "growth": 0.15,
			"waves": [{"rifleman": 4, "kangaroo": 1}, {"rifleman": 4, "kangaroo": 2, "breacher": 1, "medic": 1},
				{"rifleman": 5, "kangaroo": 2, "breacher": 2, "chimp": 2, "medic": 1}]},
	# Guns: mules and bisons shelling the decks, the roofs and the vents, behind a screen.
	"siege": {"income_mult": 1.0, "sides": "stick", "growth": 0.1,
			"waves": [{"rifleman": 4, "medic": 1, "giraffe": 1}, {"rifleman": 4, "bison_gun": 1, "medic": 1, "giraffe": 1},
				{"rifleman": 5, "mule": 1, "bison_gun": 1, "rhino": 1, "medic": 1, "giraffe": 1, "breacher": 1},
				{"rifleman": 5, "mule": 2, "bison_gun": 1, "rhino": 1, "elephant": 1, "medic": 2, "giraffe": 1, "breacher": 2}]},
	# The stock waves, but massed: the army gathers at the base until it is 30 strong, then forms up in the woods off the
	# gate it goes for and goes in together.
	"mass": {"income_mult": 1.0, "sides": "stick", "launch_at": 30, "regroup": 320.0},
	# Massed, with its guns doing the work first: the artillery shells the deck guns from outside their reach while the army
	# waits at the base, then the army goes in where the guns are down; every skill used. A mix without dead weight.
	"siege_mass": {"income_mult": 1.0, "first_wave_delay": 5.0, "sides": "guns", "launch_at": 36, "regroup": 290.0,
			"standoff": true, "bison_fire": true, "shell_vents": true, "siege": 540.0, "siege_guns": 4,
			"rhino_cluster": true, "talon_soldiers": true, "smoke": true, "missiles": true, "drone_answer": false, "escort": true, "artillery_keep": 4,
			"vents_from": 1080.0, "vents_breach": true,
			"waves": [{"mule": 2, "giraffe": 1}, {"rifleman": 6, "hippo": 1, "serpent": 1, "kangaroo": 1, "medic": 1},
				{"mule": 2, "rifleman": 4, "breacher": 2, "chimp": 2},
				{"rifleman": 6, "hippo": 1, "serpent": 1, "rhino": 1, "kangaroo": 1, "elephant": 1},
				{"rifleman": 6, "serpent": 1, "breacher": 1, "chimp": 2, "hippo": 1, "medic": 1}]},
	# Massed and on two sides at once.
	"mass_split": {"income_mult": 1.0, "sides": "rotate", "split": 2, "launch_at": 40, "regroup": 320.0},
	# The air: talons at the vents over the walls, elephants under them against the defenders' aircraft.
	"air": {"income_mult": 1.0, "sides": "rotate", "growth": 0.1,
			"waves": [{"rifleman": 3, "talon": 2, "medic": 1}, {"rifleman": 3, "talon": 4, "giraffe": 1},
				{"rifleman": 4, "talon": 5, "elephant": 1, "medic": 1}, {"rifleman": 4, "talon": 6, "elephant": 1, "medic": 1, "breacher": 1}]},
}
var policy := DEFAULT_POLICY.duplicate(true)

var _think_cd := 2.0
var _wave := 0
var _pending: Array[String] = []
var _staging: Array[int] = []
var _wave_side := "south"
var _stick_side := ""
var _first_wave_delay := 15.0
## Waves forming up in the woods before they go in (the policy's `regroup`): {side, ids, at, since}.
var _groups: Array = []
## A wave's ground units within this (m, flat) of its spot count as there.
const REGROUP_REACH := 30.0
## Told to whoever listens (the telemetry): a wave has set off.
signal wave_launched(wave: int, side: String, ids: Array)

## The gates a wave can go for (the stronghold's south, east and west faces).
const GATE_SIDES := ["south", "east", "west"]
## A flash grenade lands where it is thrown: kangaroos throw with little of their reach to spare (the
## infantry's stand in front of a gun deck is just inside it).
const FLASH_SPARE := 0.97
## Units sent to retake a sabotaged helipad: as many as RETAKERS of the nearest ground units.
const RETAKERS := 3
## A bear swimming that was hurt this long ago (s) or less dives.
const DIVE_HURT := 1.5
## Giraffes this close to the middle of the map (m, flat) are out on the field: they ping.
const PING_FIELD := 150.0
## Lionesses go after defenders on the ground this close to them (m, flat).
const HUNT_RANGE := 32.0
## Dogs this close to a mine that went off (m, flat) switch to minesweeping; a sweeping dog that has had no
## mine to dig for SWEEP_IDLE seconds goes back to healing.
const SWEEP_CALL := 40.0
const SWEEP_IDLE := 20.0
## Serpent Snipers go up a tree this far off their way at most (m, flat), one with the gate nearest them in their
## rifle's reach from up there (with a little to spare) and no closer to it than NEST_CLEAR (not under the wall).
const NEST_LOOK := 30.0
const NEST_CLEAR := 25.0
## Where the army saw a defender out on the field in the last TRAP_MEMORY seconds, within TRAP_CALL of a snake
## (m, flat), the snake coils round the free bush nearest the spot (within TRAP_LOOK of it) and lies in wait.
const TRAP_MEMORY := 45.0
const TRAP_CALL := 40.0
const TRAP_LOOK := 10.0
## A snake up a tree with nothing to shoot for NEST_IDLE seconds, or round a bush with nothing come by for
## TRAP_IDLE, comes down (uncoils) and goes on; it rests SKILL_REST seconds before it climbs or coils again.
const NEST_IDLE := 20.0
const TRAP_IDLE := 40.0
const SKILL_REST := 45.0
## Mule Artillery aim at targets within GUN_SPARE of their reach; one with nothing in reach for GUN_IDLE
## seconds disarms and goes on with the army.
const GUN_SPARE := 0.95
const GUN_IDLE := 20.0

## Helipad -> ids of the units sent to retake it.
var _retakers := {}
## Mine blasts it has seen so far, and how long each sweeping dog (id) has had no mine to dig (s).
var _blasts_seen := GroundMine.blasts
var _sweep_idle := {}
## Seconds of thinking so far, and where the army saw defenders out on the field: [where, when], the last
## TRAP_MEMORY seconds of them.
var _clock := 0.0
var _sightings: Array = []
## Serpent Sniper id -> seconds up its tree or round its bush with nothing to do, and seconds before it may climb
## or coil again.
var _skill_idle := {}
var _skill_rest := {}
## Mule Artillery id -> seconds armed with nothing in reach.
var _gun_idle := {}
## Artillery and spotters working on their own (the policy's `standoff`), and where each was last sent.
var _guns: Array = []
## When the massed army began waiting for the siege (_siege_waiting); -1: it isn't.
var _siege_from := -1.0
var _gun_goal := {}
## Firing spots: this much of a gun's reach out from what it shells, and this far (m, flat) outside every live gun's reach.
const STANDOFF_REACH := 0.88
const GUN_MARGIN := 6.0
## A spotter keeps this far ahead of its gun (m, toward the middle), and is sent again once its gun is this far off.
const SPOT_AHEAD := 6.0
const SPOT_SLACK := 8.0
## Artillery goes to a firing spot for a gun this far off at most (m, flat): it is slow, the other faces are too far.
const ROAM := 100.0
## The escort: each gun is guarded by its share of the army from this far behind it (m); a guard moves once its spot has
## moved further than ESCORT_SLACK.
const ESCORT_BACK := 22.0
const ESCORT_SLACK := 15.0
## Where each gun's guard was last sent (gun id -> spot), and the army's size then.
var _escort_at := {}
var _escort_n := 0
## The artillery has gone out with the army once (`escort`): from then on it works on its own.
var _left_base := false
## Artillery this close to the middle of the map (m, flat) is in the siege: there it keeps to the guns within ROAM.
const SIEGE_BAND := 250.0
## The siege (the policy's `siege`) waits only while it has at least this many guns (Mule Artillery, Bison Field Guns).
const SIEGE_MIN_GUNS := 2

## Where it keeps a bridge standing (the river nearest each, within BRIDGE_NEAR of it), trying BRIDGE_SHIFT m up and
## down the river where one can't go just there; and the ground units it sends at defenders on a bridge (up to
## ALARM_UNITS, within ALARM_REACH), once every ALARM_EVERY s a bridge.
const BRIDGE_SPOTS := [Vector3(-70, 0, 478), Vector3(70, 0, 478), Vector3(372, 0, -60), Vector3(370, 0, 90)]
const BRIDGE_NEAR := 60.0
const BRIDGE_SHIFT := [0.0, 18.0, -18.0, 36.0, -36.0, 54.0, -54.0]
const ALARM_UNITS := 5
const ALARM_REACH := 180.0
const ALARM_EVERY := 6.0
var _alarm_sent := {}


## Lays `overrides` over the default policy (unknown keys are kept: a subclass may read its own).
func set_policy(overrides: Dictionary) -> void:
	policy = DEFAULT_POLICY.duplicate(true)
	for k in overrides:
		policy[k] = overrides[k]
	_first_wave_delay = float(policy.first_wave_delay)


## The wave now being gathered or last sent (1 for the first).
func wave_number() -> int:
	return _wave


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
		var id := commander.submit({"type": "spawn", "unit": _pending[0]})
		if id == 0:
			break
		_pending.pop_front()
		var fresh: AttackerUnit = commander.units.get(id)
		if policy.standoff and fresh != null and ((fresh.has_bombard() and not fresh.is_flying()) or fresh.has_ping()):
			_guns.append(id)  # it works on its own (_artillery)
			continue
		_staging.append(id)
		# The wave gathers a way out in front of the base.
		commander.submit({"type": "move", "units": [id], "pos": level.rally_point(0), "attack": true})

	# The army at its cap: what is still waiting to be spawned is dropped (it couldn't come out).
	var at_cap := commander.units.size() >= AttackerCommander.UNIT_CAP - 2
	if not _staging.is_empty() and at_cap:
		_pending.clear()
	if _pending.is_empty() and not _staging.is_empty():
		# Massing (the policy's `launch_at`): another wave is planned onto this one until the army is big enough. At the
		# cap, half of it goes (the rest of the army is out there already); fewer wait for the army out there to thin.
		# With the policy's `siege`, it waits (and grows to the cap) while its artillery shells the guns first.
		var mass := int(policy.launch_at)
		if _siege_waiting():
			if not at_cap:
				_plan_wave()
		elif mass <= 0 or _staging.size() >= mass or (at_cap and _staging.size() >= mass / 2):
			_launch_wave()
		elif not at_cap:
			_plan_wave()

	_escort_tick()
	_regroup_tick()
	_retake_bases()
	_reassign_idle()
	_ram_gates()
	_talon_strikes()
	_kangaroo_flashes()
	_giraffe_pings()
	_bear_dives()
	_lioness_hunts()
	_serpent_skills()
	_dog_modes()
	if policy.standoff:
		_artillery()
	else:
		_mule_guns()
		if policy.bison_fire:
			_bison_guns()
	if policy.rhino_cluster:
		_rhino_clusters()
	if policy.smoke:
		_hippo_smoke()
	if policy.missiles:
		_elephant_missiles()
	_bridges()
	_bridge_alarms()


## Keeps a bridge standing at each of BRIDGE_SPOTS while it has any left: one dropped a think at most.
func _bridges() -> void:
	if not RiverCrossing.active() or commander.bridges_left <= 0:
		return
	for spot: Vector3 in BRIDGE_SPOTS:
		var standing := commander.bridges.any(func(b): return is_instance_valid(b) \
				and Vector2(b.global_position.x - spot.x, b.global_position.z - spot.z).length() < BRIDGE_NEAR)
		if standing:
			continue
		var river := RiverCrossing.nearest_river(Vector2(spot.x, spot.z))
		if river.is_empty():
			continue
		for shift in BRIDGE_SHIFT:
			var at: Vector2 = river.point + river.dir * shift
			if commander.submit({"type": "bridge", "pos": Vector3(at.x, 0.0, at.y)}) != 0:
				return
		return


## Defenders on one of its bridges: the nearest ground units that fight go for them.
func _bridge_alarms() -> void:
	for b in commander.bridges:
		if not is_instance_valid(b) or not b.alarm_on or b.intruders.is_empty():
			continue
		if _clock - float(_alarm_sent.get(b.bridge_id, -INF)) < ALARM_EVERY:
			continue
		_alarm_sent[b.bridge_id] = _clock
		var near := []
		for u in commander.units.values():
			if u.is_controllable() and not u.is_flying() and u.has_basic_attack() and not u.is_crossing() \
					and u.global_position.distance_to(b.global_position) < ALARM_REACH:
				near.append([u.global_position.distance_to(b.global_position), u.unit_id])
		near.sort_custom(func(a, c): return a[0] < c[0])
		if not near.is_empty():
			commander.submit({"type": "move", "units": near.slice(0, ALARM_UNITS).map(func(e): return e[1]),
					"pos": b.intruders[0].global_position, "attack": true})


## Which gate wave `_wave` goes for, by the policy's `sides`.
func _pick_side() -> String:
	# The faces still worth a gate: a standing gate with air vents left over it.
	var standing := GATE_SIDES.filter(func(s): return level.gates[s].is_alive() and _face_vents(s) > 0)
	var any: String = GATE_SIDES[randi() % GATE_SIDES.size()]
	# A gate down is the way in: the policies that pick their gate go through it while it is open and its face still has
	# vents; once they are all down, on to the next face.
	var open := _open_breach()
	if String(policy.sides) in ["stick", "guns", "weakest"] and open != "":
		return open
	match String(policy.sides):
		"south", "east", "west":
			return policy.sides
		"rotate":
			return GATE_SIDES[(_wave - 1) % GATE_SIDES.size()]
		"stick":
			if _stick_side == "" or not (_stick_side in standing):
				_stick_side = any if standing.is_empty() else standing[randi() % standing.size()]
			return _stick_side
		"guns":
			var fewest := ""
			for side in standing:
				if fewest == "" or _face_guns(side) < _face_guns(fewest) \
						or (_face_guns(side) == _face_guns(fewest) and _gate_to_base(side) < _gate_to_base(fewest)):
					fewest = side
			if fewest != "":
				return fewest
		"weakest":
			var best := ""
			for s in standing:
				if best == "" or level.gates[s].hp < level.gates[best].hp:
					best = s
			if best != "" and level.gates[best].hp < level.gates[best].max_hp:
				return best
	return any


## The policy's own wave `_wave` (its `waves`), or {} with none.
func _policy_wave() -> Dictionary:
	var waves: Array = policy.waves
	if waves.is_empty():
		return {}
	var k := mini(_wave - 1, waves.size() - 1)
	var past := maxi(_wave - waves.size(), 0)
	var out := {}
	for type_id in waves[k]:
		if UnitTypes.DATA.has(type_id):
			out[type_id] = int(round(float(waves[k][type_id]) * (1.0 + float(policy.growth) * past)))
	return out


func _plan_wave() -> void:
	_wave += 1
	_wave_side = _pick_side()
	# Wave mix grows over time: infantry core, then flyers, heavies and artillery.
	var counts := _policy_wave()
	if counts.is_empty():
		counts = _builtin_wave()
	# The artillery kept up (the policy's `artillery_keep`): mules lost are made good in the next wave.
	var keep := int(policy.artillery_keep)
	if keep > 0:
		var have := commander.units.values().filter(func(u): return u.type_id == "mule").size() + _pending.count("mule")
		counts["mule"] = maxi(counts.get("mule", 0), keep - have)
	# Drones about: more bears, and Combat Rhinos (their guns are the AA that can follow a swarm about).
	var swarms := drones.live_swarms() if drones != null and policy.drone_answer else 0
	if swarms > 0:
		counts["rifleman"] = mini(counts.get("rifleman", 0) + swarms, 14)
		if swarms >= 3 and _wave >= 2:
			counts["rhino"] = maxi(counts.get("rhino", 0), 1 if swarms < 5 else 2)
	var scale := float(policy.wave_scale)
	if scale != 1.0:
		for type_id in counts:
			if counts[type_id] > 0:
				counts[type_id] = maxi(int(round(counts[type_id] * scale)), 1)
	# Interleave so a partly-spawned wave is still a sensible mix.
	var remaining := true
	while remaining:
		remaining = false
		for type_id in counts:
			if counts[type_id] > 0:
				_pending.append(type_id)
				counts[type_id] -= 1
				remaining = true


## The CPU's own mix for wave `_wave`.
func _builtin_wave() -> Dictionary:
	return {
		"breacher": 1 if _wave >= 2 and (_wave % 2 == 0 or _wave > 5) else 0,
		"mule": 1 if _wave >= 3 and _wave % 2 == 1 else 0,
		"elephant": 0 if _wave < 3 else (1 if _wave < 7 else 2),
		"medic": 1 if _wave < 5 else 2,
		"rifleman": mini(3 + _wave, 10),
		"kangaroo": mini(1 + _wave / 2, 5),
		"talon": 0 if _wave < 2 else mini(_wave - 1, 4),
		"chimp": 0 if _wave < 3 else mini(1 + _wave / 3, 4),
		"giraffe": 1 if _wave >= 2 else 0,
		"lioness": 0 if _wave < 2 else mini(1 + _wave / 2, 6),
		"serpent": 0 if _wave < 3 else mini(1 + (_wave - 3) / 2, 3),
	}


func _launch_wave() -> void:
	var all_ids := _staging.duplicate()
	_staging.clear()
	wave_launched.emit(_wave, _wave_side, all_ids)
	# Multi-front (the policy's `split`): the wave goes for that many gates at once, a share of it each.
	var sides := [_wave_side]
	var k := GATE_SIDES.find(_wave_side)
	for n in range(1, clampi(int(policy.split), 1, GATE_SIDES.size())):
		sides.append(GATE_SIDES[(k + n) % GATE_SIDES.size()])
	for n in sides.size():
		var share := []
		for i in all_ids.size():
			if i % sides.size() == n:
				share.append(all_ids[i])
		_launch_at(sides[n], share)


## Sends `ids` at `side`'s gate (or on at the vents, once it is down); with the policy's `regroup`, to form up in the
## woods off it first.
func _launch_at(side: String, ids: Array) -> void:
	var gate: Structure = level.gates[side]
	if gate.is_alive() and float(policy.regroup) > 0.0 and not ids.is_empty():
		var out: Vector3 = LevelBuilder.SIDES[side].dir
		var at := out * float(policy.regroup)
		_groups.append({"side": side, "ids": ids.duplicate(), "at": at, "since": _clock})
		commander.submit({"type": "move", "units": ids, "pos": at, "attack": true})
		return
	_assault(side, ids)


## The waves forming up in the woods: one that is together (or has waited long enough) goes in.
func _regroup_tick() -> void:
	for g in _groups.duplicate():
		g.ids = g.ids.filter(func(id): return commander.units.has(id))
		var ground := 0
		var there := 0
		for id in g.ids:
			var u: AttackerUnit = commander.units[id]
			if u.is_flying() or u.has_setup():
				continue  # the talons circle over it, the mules are far too slow to wait for
			ground += 1
			if Vector2(u.global_position.x - g.at.x, u.global_position.z - g.at.z).length() < REGROUP_REACH:
				there += 1
		if g.ids.is_empty() or there >= ground * float(policy.regroup_ready) or _clock - g.since >= float(policy.regroup_wait):
			_groups.erase(g)
			if not g.ids.is_empty():
				_assault(g.side, g.ids)


## The ids of every unit forming up with a wave.
func _grouped() -> Array:
	var out := []
	for g in _groups:
		out += g.ids
	return out


## Sends `ids` at `side`'s gate (or on at the vents, once it is down).
func _assault(side: String, ids: Array) -> void:
	var gate: Structure = level.gates[side]
	if gate.is_alive():
		var infantry := []
		var siege := []
		var artillery := []
		var flyers := []
		for id in ids:
			var u = commander.units.get(id)
			if u == null:
				continue
			if u.is_flying() and u.has_basic_attack():
				flyers.append(id)
			elif u.has_ram():
				siege.append(id)
			elif u.role == "artillery" or u.has_setup():
				artillery.append(id)
			else:
				infantry.append(id)
		# Infantry, medics and flyers push up to the gate and suppress the walls, rams go
		# for the gate, artillery shells it from range (the Mule Artillery stop and set their
		# guns up once it is in reach: _mule_guns).
		var out: Vector3 = LevelBuilder.SIDES[side].dir
		commander.submit({"type": "move", "units": infantry, "pos": out * (LevelBuilder.FACE_DIST + 14.0), "attack": true})
		commander.submit({"type": "attack", "units": siege + artillery, "target": gate.get_path()})
		# Gunships skip the gate and go straight for the air vents on that face's roof.
		var vent := level.nearest_vent(out * LevelBuilder.FACE_DIST)
		if vent and not flyers.is_empty():
			commander.submit({"type": "attack", "units": flyers, "target": vent.get_path()})
		elif not flyers.is_empty():
			commander.submit({"type": "move", "units": flyers, "pos": out * (LevelBuilder.FACE_DIST + 14.0), "attack": true})
	else:
		_push_keep(ids)


func _push_keep(ids: Array) -> void:
	# The objective is the air vents on the roofs. Infiltrators that make it in climb up and go
	# for them (AttackerUnit._raid_target), flyers hit them from above, big units hold in front of
	# that face (off to one side, clear of the tunnel), picking off the defenders on it.
	var inside := []
	var flyers := []
	var big := []
	for id in ids:
		var u = commander.units.get(id)
		if u == null:
			continue
		if u.fits_inside():
			inside.append(id)
		elif u.is_flying():
			flyers.append(id)
		else:
			big.append(id)
	var side := _breached_side()
	var out: Vector3 = LevelBuilder.SIDES[side].dir
	var vent := level.nearest_vent(out * LevelBuilder.FACE_DIST)
	if vent == null:
		return
	# Sent to the broken gate itself, they go in (AttackerUnit: an order near an open breach): the raiders hunt the
	# defenders inside, the rams make for the vents. Sent at a vent, they would stand under its face outside.
	var gate: Structure = level.gates[side]
	if not inside.is_empty():
		if not gate.is_alive():
			commander.submit({"type": "move", "units": inside, "pos": gate.global_position + out * 3.0, "attack": true})
		else:
			commander.submit({"type": "attack", "units": inside, "target": vent.get_path()})
	if not flyers.is_empty():
		commander.submit({"type": "attack", "units": flyers, "target": vent.get_path()})
	if not big.is_empty():
		var hold := out * (LevelBuilder.FACE_DIST + 16.0) + out.cross(Vector3.UP) * 14.0
		commander.submit({"type": "move", "units": big, "pos": hold, "attack": true})


func _breached_side() -> String:
	var open := _open_breach()
	return open if open != "" else _wave_side


## A gate down over a face with air vents still standing ("" with none): the way in to them.
func _open_breach() -> String:
	for side in GATE_SIDES:
		if not level.gates[side].is_alive() and _face_vents(side) > 0:
			return side
	return ""


## The live air vents on `side`'s face.
func _face_vents(side: String) -> int:
	var n := 0
	var face := side.capitalize() + " "
	for v in level.vents:
		if v.is_alive() and String(v.display_name).begins_with(face):
			n += 1
	return n


## The artillery goes for the air vents first (the policy's `vents_from` and `vents_breach`).
func _vents_first() -> bool:
	if not policy.shell_vents:
		return false
	if float(policy.vents_from) > 0.0 and _clock >= float(policy.vents_from):
		return true
	return bool(policy.vents_breach) and level.gates.values().any(func(g): return not g.is_alive())


## Rams closing in on a gate ram it once it is within reach of the charge.
func _ram_gates() -> void:
	var by_gate := {}
	for u in commander.units.values():
		if not u.ram_ready() or u.order.type != "attack" or not RamCharge.is_gate(u.order.target):
			continue
		var gate: Structure = u.order.target
		var reach: float = u.stats.ram_duration * u.stats.speed * u.stats.ram_speed * 0.6
		if u.global_position.distance_to(gate.get_approach_point()) <= reach:
			if not by_gate.has(gate):
				by_gate[gate] = []
			by_gate[gate].append(u.unit_id)
	for gate in by_gate:
		commander.submit({"type": "ram", "units": by_gate[gate]})
		commander.submit({"type": "attack", "units": by_gate[gate], "target": gate.get_path()})


## Talons strike whatever is in their reach: bombs on the AA turrets first, then the machines and
## the gates; strafe runs (along the face, next to the mountain) on the defenders.
func _talon_strikes() -> void:
	for u in commander.units.values():
		if not u.has_bomb() or not u.is_alive() or u.on_run():
			continue
		if u.bomb_ready():
			var t := _in_reach(u, u.stats.bomb_range, func(d): return d.get("station_kind") == "aa")
			if t == null:
				if policy.talon_soldiers:
					t = _in_reach(u, u.stats.bomb_range, func(d): return d.get("station_kind") in ["mg", "artillery"])
					if t == null:
						t = _in_reach(u, u.stats.bomb_range, func(d): return d.get("station_kind") in ["soldier", "squad"])
				else:
					t = _in_reach(u, u.stats.bomb_range, func(d): return d.get("station_kind") in ["mg", "artillery"] or d in level.gates.values())
			if t:
				commander.submit({"type": "bomb", "units": [u.unit_id], "pos": t.global_position})
				continue
		if u.strafe_ready():
			var t := _in_reach(u, u.stats.strafe_range, func(d): return not d.is_in_group("structures") and d.get("station_kind") not in ["aa", "mg", "artillery"])
			if t:
				var to: Vector3 = t.global_position - u.global_position
				var dir := Vector3(to.x, 0.0, to.z).normalized()
				var out := Vector3(t.global_position.x, 0.0, t.global_position.z)
				if out.length() < LevelBuilder.FACE_DIST + 10.0:
					var along := out.normalized().cross(Vector3.UP)
					dir = along if along.dot(dir) >= 0.0 else -along
				commander.submit({"type": "strafe", "units": [u.unit_id], "pos": t.global_position, "dir": dir})


## Kangaroos throw flash grenades at the defenders in their reach: the gun decks' riflemen and
## machine guns, the mortar, squads out in the field (not ones blinded already or with a grenade on
## its way). The ready ones in reach of the same defender throw together, their flashes spread round
## it (KangarooFlash.spots). Raiders throw on their own.
func _kangaroo_flashes() -> void:
	var ready := commander.units.values().filter(func(u): return u.flash_ready() and not u.raiding)
	while not ready.is_empty():
		var u: AttackerUnit = ready.pop_front()
		var unflashed := func(d): return d.get("station_kind") in ["soldier", "mg", "artillery"] and not FlashGrenade.is_blind(d) \
				and not FlashGrenade.coming(level, d.global_position, u.stats.flash_radius * 0.6)
		var t := _in_reach(u, u.stats.flash_range, unflashed, FLASH_SPARE)
		if t == null:
			continue
		var group := [u]
		for o in ready.duplicate():
			if Vector2(o.global_position.x - t.global_position.x, o.global_position.z - t.global_position.z).length() < o.stats.flash_range * FLASH_SPARE:
				group.append(o)
				ready.erase(o)
		commander.submit({"type": "flash", "units": group.map(func(k): return k.unit_id), "pos": t.global_position})


## Giraffes out on the field ping whenever they can: the CPU doesn't know where the defenders' squads
## are any more than a player would, so it sweeps the ground in front of its army.
func _giraffe_pings() -> void:
	var ids := []
	for u in commander.units.values():
		if u.ping_ready() and not u.raiding and Vector2(u.global_position.x, u.global_position.z).length() < PING_FIELD:
			ids.append(u.unit_id)
	if not ids.is_empty():
		commander.submit({"type": "ping", "units": ids})


## Bears out swimming that are shot at dive under the water, out of the defenders' sight.
func _bear_dives() -> void:
	var ids := []
	for u in commander.units.values():
		if u.dive_ready() and u._since_hurt < DIVE_HURT:
			ids.append(u.unit_id)
	if not ids.is_empty():
		commander.submit({"type": "dive", "units": ids})


## Lionesses hunt the defenders on the ground the army sees within HUNT_RANGE (squads out on the field,
## riflemen off the walls; the walls' posts are out of their reach): a lioness whose sneak is ready
## sneaks up and pounces, the others run in to maul them; close enough, she lights her fire blast.
func _lioness_hunts() -> void:
	for u in commander.units.values():
		if not u.has_sneak() or not u.is_controllable() or u.is_pouncing():
			continue
		var on_ground := func(d): return d.get("station_kind") in ["soldier", "infiltrator"] \
				and absf(d.global_position.y - u.global_position.y) < AttackerUnit.POUNCE_RISE
		var prey := _in_reach(u, HUNT_RANGE, on_ground, 1.0)
		if prey == null:
			continue
		var dist := Vector2(prey.global_position.x - u.global_position.x, prey.global_position.z - u.global_position.z).length()
		if u.blast_ready() and dist < u.stats.blast_range * 0.8:
			commander.submit({"type": "blast", "units": [u.unit_id]})
		if u.order.type == "attack" and u.order.target == prey:
			continue
		if u.sneak_ready() and dist > u.stats.pounce_range * 0.6:
			commander.submit({"type": "sneak", "units": [u.unit_id]})
		commander.submit({"type": "attack", "units": [u.unit_id], "target": prey.get_path()})


## Serpent Snipers: one with a tree near it (NEST_LOOK) from which the gate nearest it is in its rifle's reach
## climbs it and snipes from the crown. Otherwise, where the army saw a defender out on the field lately near one,
## it coils round the free bush nearest the spot and lies in wait. Up there with nothing to shoot for NEST_IDLE, or
## round its bush with nothing come by for TRAP_IDLE, it comes down (uncoils) and goes on with the army, and rests
## (SKILL_REST) before it climbs or coils again. One squeezing its prey is left to it.
func _serpent_skills() -> void:
	_clock += 1.0
	_note_sightings()
	for u in commander.units.values():
		if not (u.has_nest() or u.has_trap()) or not u.is_controllable() or u.unit_id in _staging:
			continue
		var id: int = u.unit_id
		if u.in_tree() or u.in_bush():
			var busy: bool = u.skill_dir() != 0 or u.is_constricting() or Combat.is_valid_target(u.target)
			_skill_idle[id] = 0.0 if busy else _skill_idle.get(id, 0.0) + 1.0
			if _skill_idle[id] >= (NEST_IDLE if u.in_tree() else TRAP_IDLE):
				_skill_idle.erase(id)
				_skill_rest[id] = SKILL_REST
				_send_on([id])  # it climbs down (uncoils) first
			continue
		_skill_rest[id] = _skill_rest.get(id, 0.0) - 1.0
		if _skill_rest[id] > 0.0 or u.order.type in ["nest", "trap"]:
			continue
		var tree := _nest_tree(u) if u.has_nest() else null
		if tree:
			commander.submit({"type": "nest", "units": [id], "pos": tree.trunk_centre()})
			continue
		var bush := _trap_bush(u) if u.has_trap() else null
		if bush:
			commander.submit({"type": "trap", "units": [id], "pos": bush.global_position})


## Remembers where the army sees defenders out on the field now (the soldiers and troopers a snake strikes,
## SerpentTrap.PREY, on the ground outside the mountain), forgetting what it saw over TRAP_MEMORY ago.
func _note_sightings() -> void:
	_sightings = _sightings.filter(func(s): return _clock - s[1] <= TRAP_MEMORY)
	for d in level.get_tree().get_nodes_in_group("defender_targets"):
		if not d.is_alive() or d.get("station_kind") not in SerpentTrap.PREY or Combat.low_profile(d) or not AttackerVision.sees_node(d):
			continue
		var p: Vector3 = d.global_position
		if LevelBuilder.above_ground(p) < 2.0 and Vector2(p.x, p.z).length() > LevelBuilder.FACE_DIST + 4.0:
			_sightings.append([p, _clock])


## The tree for `u` to snipe from: standing and free, within NEST_LOOK of it, the standing gate nearest it in its
## rifle's reach from up there and no closer to it than NEST_CLEAR; the nearest such, or null.
func _nest_tree(u: AttackerUnit) -> ForestTree:
	var gate := _nearest_gate(u.global_position)
	if gate == null:
		return null
	var reach: float = u.stats.range * u.stats.nest_range * 0.85
	var best: ForestTree = null
	var best_d := NEST_LOOK
	for tree in ForestTree.near(u.global_position, NEST_LOOK + 4.0):
		if not tree.nest_free(u):
			continue
		var foot := tree.trunk_centre()
		var to_gate := _flat_dist(foot, gate.global_position)
		var d := _flat_dist(foot, u.global_position)
		if to_gate <= reach and to_gate >= NEST_CLEAR and d < best_d:
			best_d = d
			best = tree
	return best


## The bush for `u` to lie in wait round: the free one nearest where the army last saw a defender out on the
## field within TRAP_CALL of it (no further than TRAP_LOOK from the spot), or null.
func _trap_bush(u: AttackerUnit) -> Bush:
	for k in range(_sightings.size() - 1, -1, -1):
		var at: Vector3 = _sightings[k][0]
		if _flat_dist(at, u.global_position) > TRAP_CALL:
			continue
		var bush := Bush.nearest(at, TRAP_LOOK, u)
		if bush:
			return bush
	return null


## Dogs heal. A mine going off under the army (the CPU sees that much): the dogs within SWEEP_CALL of it switch
## to minesweeping; a sweeping dog with no mine to dig for SWEEP_IDLE seconds goes back to healing.
func _dog_modes() -> void:
	var blast := GroundMine.blasts > _blasts_seen
	_blasts_seen = GroundMine.blasts
	var at := GroundMine.last_blast
	for u in commander.units.values():
		if not u.has_dog_modes() or not u.is_controllable():
			continue
		if u.dog_mode == "heal":
			if blast and Vector2(u.global_position.x - at.x, u.global_position.z - at.z).length() < SWEEP_CALL:
				commander.submit({"type": "dog_mode", "units": [u.unit_id], "mode": "sweep"})
				_sweep_idle[u.unit_id] = 0.0
			continue
		_sweep_idle[u.unit_id] = 0.0 if u.sweep_mine != null else _sweep_idle.get(u.unit_id, 0.0) + 1.0
		if _sweep_idle[u.unit_id] >= SWEEP_IDLE:
			commander.submit({"type": "dog_mode", "units": [u.unit_id], "mode": "heal"})
			_sweep_idle.erase(u.unit_id)


## Mule Artillery: one with something to shell in its gun's reach stops and sets its gun up (it walks on with the
## wave until then); armed, it shells it whenever it has reloaded: the machines on the decks and roofs (the gate
## guns, the mortar) first, then the defenders the army sees, then the gate, then the AA turrets. Armed with
## nothing in reach for GUN_IDLE seconds, it disarms and goes on with the army (it sets off once disarmed).
func _mule_guns() -> void:
	for u in commander.units.values():
		if not u.has_setup() or not u.is_controllable() or u.unit_id in _staging or u.setting_up() or u.packing_up():
			continue
		var id: int = u.unit_id
		var t := _gun_target(u)
		if u.is_packed():
			if t != null:
				commander.submit({"type": "setup", "units": [id], "on": true})
				_gun_idle[id] = 0.0
			continue
		if t != null:
			_gun_idle[id] = 0.0
			if u.bombard_ready():
				commander.submit({"type": "bombard", "units": [id], "pos": t.global_position})
			continue
		_gun_idle[id] = _gun_idle.get(id, 0.0) + 1.0
		if _gun_idle[id] >= GUN_IDLE:
			_gun_idle.erase(id)
			commander.submit({"type": "setup", "units": [id], "on": false})
			_send_on([id])


## What a Mule Artillery shells: the nearest of the first kind of target in its reach (GUN_SPARE of it) that the
## army sees, in the order _mule_guns gives; null with none.
func _gun_target(u: AttackerUnit) -> Node3D:
	var gates := level.gates.values()
	for pick in [func(d): return d.get("station_kind") in ["mg", "artillery"],
			func(d): return d.get("station_kind") in ["soldier", "sniper"],
			func(d): return policy.shell_vents and d is Structure and d.is_vent,
			func(d): return d in gates,
			func(d): return d.get("station_kind") == "aa"]:
		var t := _in_reach(u, u.stats.bombard_range, pick, GUN_SPARE)
		if t != null:
			return t
	return null


## The nearest live defender `pick` takes (or gate) within `reach` of `u` (flat), with room to spare
## (within `spare` of it). Only what the army sees: the CPU plays by the fog of war (AttackerVision).
func _in_reach(u: AttackerUnit, reach: float, pick: Callable, spare := 0.85) -> Node3D:
	var best: Node3D = null
	var best_d := reach * spare
	for d in level.get_tree().get_nodes_in_group("damageable"):
		if d.team == u.team or not d.is_alive() or Combat.low_profile(d) or not AttackerVision.sees_node(d) or not pick.call(d):
			continue
		var dist := Vector2(d.global_position.x - u.global_position.x, d.global_position.z - u.global_position.z).length()
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Sabotaged helipads: the ground units nearest each (not raiding, not a wave about to set off) go
## and stand by it until it is retaken.
func _retake_bases() -> void:
	for b in level.bases:
		if b.controlled:
			_retakers.erase(b)
			continue
		var sent: Array = _retakers.get(b, []).filter(func(id): return commander.units.has(id) and commander.units[id].is_controllable())
		if sent.size() >= RETAKERS:
			_retakers[b] = sent
			continue
		var cands := []
		for id in commander.units:
			var u: AttackerUnit = commander.units[id]
			if id in sent or id in _staging or id in _guns or u.is_flying() or not u.is_controllable() or u.in_tree() or u.in_bush() \
					or u.has_setup():
				continue  # (the Mule Artillery are far too slow for it)
			cands.append([b.edge_distance(u.global_position), id])
		cands.sort_custom(func(x, y): return x[0] < y[0])
		var more: Array = cands.slice(0, RETAKERS - sent.size()).map(func(c): return c[1])
		if not more.is_empty():
			commander.submit({"type": "move", "units": more, "pos": b.spawn_point, "attack": true})
		_retakers[b] = sent + more


## Units with nothing to do look for the next objective.
func _reassign_idle() -> void:
	var idle := []
	var retaking := _grouped() + _guns
	for ids in _retakers.values():
		retaking += ids
	for id in commander.units:
		if id in _staging or id in retaking:
			continue
		var u: AttackerUnit = commander.units[id]
		if u.is_idle():
			idle.append(id)
	if not idle.is_empty():
		_send_on(idle)


## Sends `ids` on to the next objective: the air vents once a gate is down (over a face with vents left), else the
## standing gate nearest each.
func _send_on(ids: Array) -> void:
	if _open_breach() != "":
		_push_keep(ids)
		return
	var by_gate := {}
	for id in ids:
		var u: AttackerUnit = commander.units[id]
		var best := _nearest_gate(u.global_position)
		if best:
			if not by_gate.has(best):
				by_gate[best] = []
			by_gate[best].append(id)
	for g in by_gate:
		commander.submit({"type": "attack", "units": by_gate[g], "target": g.get_path()})


## The standing gate nearest `p`, or null.
func _nearest_gate(p: Vector3) -> Structure:
	var best: Structure = null
	var best_d := INF
	for g in level.gates.values():
		if g.is_alive() and p.distance_to(g.global_position) < best_d:
			best_d = p.distance_to(g.global_position)
			best = g
	return best


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The siege (the policy's `siege`): true while the massed army waits at the base for its artillery to bring the guns on
## the face it goes for down to siege_guns, at most `siege` seconds from when it was massed.
## The escort (the policy's `escort`): while the siege waits, the army gathering for it guards the artillery: each gun
## gets its share of it (the nearest units, as even as they go), standing ESCORT_BACK behind it, moved along as it moves.
## The guns spread out to shell different deck guns, so one guard at their middle would leave each of them alone.
func _escort_tick() -> void:
	if not policy.escort or _staging.is_empty() or not _siege_waiting():
		return
	var guns := []
	for id in _guns:
		var u = commander.units.get(id)
		if u != null and u.has_bombard():
			guns.append(u)
	if guns.is_empty():
		return
	var spots := {}
	for g: AttackerUnit in guns:
		var back := level.rally_point(0) - g.global_position
		back.y = 0.0
		var at := g.global_position + back.normalized() * ESCORT_BACK
		spots[g.unit_id] = Vector3(at.x, 0.0, at.z)
	var moved := _staging.size() != _escort_n or spots.size() != _escort_at.size()
	for id in spots:
		if not _escort_at.has(id) or _flat_dist(spots[id], _escort_at[id]) >= ESCORT_SLACK:
			moved = true
	if not moved:
		return
	_escort_at = spots
	_escort_n = _staging.size()
	# Even shares: each unit to the nearest gun whose guard isn't full yet.
	var share := ceili(float(_staging.size()) / guns.size())
	var groups := {}
	for id in spots:
		groups[id] = []
	for uid in _staging:
		var u = commander.units.get(uid)
		if u == null:
			continue
		var best = null
		var best_d := INF
		for gid in spots:
			if groups[gid].size() >= share:
				continue
			var d := _flat_dist(u.global_position, spots[gid])
			if d < best_d:
				best_d = d
				best = gid
		if best != null:
			groups[best].append(uid)
	for gid in groups:
		if not groups[gid].is_empty():
			commander.submit({"type": "move", "units": groups[gid], "pos": spots[gid], "attack": true})


## A standing air vent within `u`'s reach (with GUN_SPARE to spare): the objective is still in its work where it is.
func _vent_in_reach(u: AttackerUnit) -> bool:
	for v in level.vents:
		if v.is_alive() and _flat_dist(v.global_position, u.global_position) < u.stats.bombard_range * GUN_SPARE:
			return true
	return false


## The army gathering at the base is big enough to go (the policy's `launch_at`, or the unit cap).
func _massed() -> bool:
	return _staging.size() >= int(policy.launch_at) or commander.units.size() >= AttackerCommander.UNIT_CAP - 2


func _siege_waiting() -> bool:
	var massed := _massed()
	if float(policy.siege) <= 0.0 or not massed or _open_breach() != "":
		return false
	# Too little artillery left to shell the guns down: nothing worth waiting for.
	if _guns.filter(func(id): return commander.units.has(id) and commander.units[id].has_bombard()).size() < SIEGE_MIN_GUNS:
		_siege_from = -1.0
		return false
	if _siege_from < 0.0:
		_siege_from = _clock
	if _face_guns(_wave_side) <= int(policy.siege_guns) or _clock - _siege_from >= float(policy.siege):
		_siege_from = -1.0
		return false
	return true


## The live deck guns (sentries and cannons) on `side`'s face.
func _face_guns(side: String) -> int:
	var n := 0
	for d in level.get_tree().get_nodes_in_group("damageable"):
		if d is MountedGun and d.is_alive() and d.kind != "bastion" and Garrison.side_of(d.global_position) == side:
			n += 1
	return n


## How far `side`'s gate is from the army's base (m, flat).
func _gate_to_base(side: String) -> float:
	return _flat_dist(level.gates[side].global_position, level.rally_point(0))


## The artillery standing off (the policy's `standoff`): each Mule Artillery and Bison Field Gun works on its own, the
## guns first. A deck or roof gun in its reach: it stops (a mule sets its gun up) and shells it whenever it has reloaded.
## None, but a safe firing spot for one within ROAM of it (_standoff_spot): it packs up and goes there. Neither: it
## shells the rest of what _gun_target takes from where it is, and with nothing at all to shell (a mule packing up
## GUN_IDLE seconds after its last target) goes to a safe spot for a vent (`shell_vents`), or holds. Its giraffes walk
## with the nearest gun, a little ahead of it: they see for it (_spot_for_guns).
func _artillery() -> void:
	_guns = _guns.filter(func(id): return commander.units.has(id))
	# With an escort (the policy's `escort`), the guns go out with the army: they keep to the base until it has massed.
	var hold: bool = policy.escort and not _massed() and _open_breach() == ""
	var vents_first := _vents_first()
	if not hold:
		_left_base = true
	for id in _guns:
		var u: AttackerUnit = commander.units[id]
		if not u.is_controllable() or u.setting_up() or u.packing_up():
			continue
		if hold and not _left_base:
			continue
		if not u.has_bombard():
			_spot_for_guns(u)
			continue
		# A Sniper it sees in its reach comes first: she picks the artillery off from out of the guns' reach.
		var t := _in_reach(u, u.stats.bombard_range, func(d): return d.get("station_kind") == "sniper", GUN_SPARE)
		var spot := Vector3.INF
		# The vents first (`vents_from`, `vents_breach`): one in reach, else a safe spot for one; with neither, the guns.
		if t == null and vents_first:
			t = _in_reach(u, u.stats.bombard_range, func(d): return d is Structure and d.is_vent, GUN_SPARE)
			if t == null:
				spot = _standoff_spot(u, true)
		if t == null and spot == Vector3.INF:
			t = _in_reach(u, u.stats.bombard_range, func(d): return d.get("station_kind") in ["mg", "artillery"], GUN_SPARE)
		if t == null and spot == Vector3.INF:
			spot = _standoff_spot(u, false)
			# Out in the siege's band, while a vent is still in its reach, it shifts at most ROAM to another gun; one still out
			# in the woods (on its way in), or with this face's vents done, walks to the nearest spot however far.
			if spot != Vector3.INF and _flat_dist(spot, u.global_position) > ROAM \
					and Vector2(u.global_position.x, u.global_position.z).length() < SIEGE_BAND \
					and _vent_in_reach(u):
				spot = Vector3.INF
			if spot == Vector3.INF:
				t = _gun_target(u)
		if t != null:
			_gun_idle[id] = 0.0
			_gun_goal.erase(id)
			if u.has_setup() and u.is_packed():
				commander.submit({"type": "setup", "units": [id], "on": true})
			elif u.bombard_ready():
				if not u.has_setup() and not u.is_idle():
					commander.submit({"type": "move", "units": [id], "pos": u.global_position, "attack": false})
				commander.submit({"type": "bombard", "units": [id], "pos": t.global_position})
			continue
		_gun_idle[id] = _gun_idle.get(id, 0.0) + 1.0
		if u.has_setup() and not u.is_packed():
			# A gun to go for: it packs up at once; nothing at all: GUN_IDLE seconds after its last target.
			if spot != Vector3.INF or _gun_idle[id] >= GUN_IDLE:
				commander.submit({"type": "setup", "units": [id], "on": false})
			continue
		if spot == Vector3.INF and policy.shell_vents:
			spot = _standoff_spot(u, true)
		if spot == Vector3.INF:
			continue
		if _gun_goal.has(id) and _flat_dist(_gun_goal[id], spot) < SPOT_SLACK and not u.is_idle():
			continue
		_gun_goal[id] = spot
		commander.submit({"type": "move", "units": [id], "pos": spot, "attack": false})


## The nearest firing spot for `u` from which a live deck or roof gun (or with `vents`, a vent) is in its reach and no
## live gun reaches it: straight out from it at STANDOFF_REACH of its reach, GUN_MARGIN outside every live gun's reach (a
## cannon's long shot, a sentry's or bastion's AI_RANGE); INF with none.
func _standoff_spot(u: AttackerUnit, vents: bool) -> Vector3:
	var reach: float = u.stats.bombard_range * STANDOFF_REACH
	var guns := []
	var marks := []
	for d in level.get_tree().get_nodes_in_group("damageable"):
		if d is MountedGun and d.is_alive():
			guns.append([d.global_position, MountedGun.CANNON_RANGE if d.kind == "cannon" else MountedGun.AI_RANGE])
			if not vents:
				marks.append(d.global_position)
	if vents:
		for v in level.vents:
			if v.is_alive():
				marks.append(v.global_position)
	var best := Vector3.INF
	var best_d := INF
	for m: Vector3 in marks:
		var flat := Vector3(m.x, 0.0, m.z)
		if flat.length() < 1.0:
			continue
		var spot := flat + flat.normalized() * reach
		if guns.any(func(g): return _flat_dist(spot, g[0]) < g[1] + GUN_MARGIN):
			continue
		var d := _flat_dist(spot, u.global_position)
		if d < best_d:
			best_d = d
			best = spot
	return best


## A spotter (a giraffe working with the artillery) keeps SPOT_AHEAD in front of the nearest gun, toward the middle.
func _spot_for_guns(u: AttackerUnit) -> void:
	var gun: AttackerUnit = null
	for id in _guns:
		var g: AttackerUnit = commander.units[id]
		if g.has_bombard() and (gun == null or _flat_dist(g.global_position, u.global_position) < _flat_dist(gun.global_position, u.global_position)):
			gun = g
	if gun == null:
		return
	var flat := Vector3(gun.global_position.x, 0.0, gun.global_position.z)
	var spot := flat - flat.normalized() * SPOT_AHEAD
	if _gun_goal.has(u.unit_id) and _flat_dist(_gun_goal[u.unit_id], spot) < SPOT_SLACK:
		return
	_gun_goal[u.unit_id] = spot
	commander.submit({"type": "move", "units": [u.unit_id], "pos": spot, "attack": false})


## Bison Field Guns (the policy's `bison_fire`) shell what is in their reach whenever they have reloaded (_gun_target).
func _bison_guns() -> void:
	for u in commander.units.values():
		if not u.has_bombard() or u.has_setup() or u.is_flying() or not u.bombard_ready():
			continue
		var t := _gun_target(u)
		if t != null:
			commander.submit({"type": "bombard", "units": [u.unit_id], "pos": t.global_position})


## Rhinos (the policy's `rhino_cluster`) cluster-bomb the defenders on the ground they see in their reach.
func _rhino_clusters() -> void:
	for u in commander.units.values():
		if not u.cluster_ready() or not u.is_controllable():
			continue
		var on_ground := func(d): return d.get("station_kind") in ["soldier", "squad"] \
				and absf(d.global_position.y - u.global_position.y) < 3.0
		var t := _in_reach(u, u.stats.cluster_range, on_ground)
		if t != null:
			commander.submit({"type": "cluster", "units": [u.unit_id], "pos": t.global_position})


## Hippos (the policy's `smoke`) lay a smoke screen between themselves and a deck gun in reach of them, halfway to it.
func _hippo_smoke() -> void:
	var grouped := _grouped()
	for u in commander.units.values():
		if not u.smoke_ready() or not u.is_controllable() or u.unit_id in grouped or u.unit_id in _staging:
			continue
		var gun := _in_reach(u, MountedGun.AI_RANGE + 10.0, func(d): return d is MountedGun and d.kind != "bastion", 1.0)
		if gun == null:
			continue
		var to := Vector3(gun.global_position.x - u.global_position.x, 0.0, gun.global_position.z - u.global_position.z)
		var dist := clampf(to.length() * 0.5, u.stats.smoke_min_range + 2.0, u.stats.smoke_range * 0.9)
		commander.submit({"type": "smoke", "units": [u.unit_id], "pos": u.global_position + to.normalized() * dist})


## Elephants (the policy's `missiles`) fire a salvo at the nearest of the defenders' aircraft in their missiles' reach,
## the jet before the drones.
func _elephant_missiles() -> void:
	for u in commander.units.values():
		if not u.has_missiles() or not u.missiles_ready() or not u.is_controllable():
			continue
		var best: Node3D = null
		var best_d := INF
		for a in level.get_tree().get_nodes_in_group("air_units"):
			if a.team == u.team or not a.is_alive():
				continue
			var d: float = u.global_position.distance_to(a.global_position) + (0.0 if a.get("swarm") == null else 1000.0)
			if u.global_position.distance_to(a.global_position) < u.stats.missile_range * 0.9 and d < best_d:
				best_d = d
				best = a
		if best != null:
			commander.submit({"type": "missile", "units": [u.unit_id], "target": best.get_path()})
