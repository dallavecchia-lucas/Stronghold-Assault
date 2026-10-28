extends Node3D
## Staged checks of the Infiltrator Squad and the Forward Helipad Bases on the real map, in the south
## field:
##
##   profile   a lone infiltrator and a Flame Trooper (a decoy) stand in reach of three Bear Riflemen:
##             the riflemen shoot the decoy and leave the infiltrator alone (low profile)
##   ordered   ordered to attack the infiltrator, they do
##   camo      under adaptive camo the order lapses, shots pass through her, a fresh order is
##             refused; a bomb's blast (area damage) still hurts her
##   bow       she looses silent arrows at a rifleman
##   op        an Infiltrator Squad is bought and sent on a sabotage operation against the South
##             Helipad, past four riflemen standing on the straight way there: it walks round them,
##             sabotages the helipad (45 s; the attackers can't spawn there any more and lose its
##             supply) and comes home, restocking its kit in the fortress
##   view      the player takes command of it and puts the camo on: the camera's vignette, the
##             troopers as ever on the defender's side, not shown at all on the attacker's
##   retake    three riflemen stand by the helipad and retake it
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/infiltrator_showcase.tscn -- --test
##   godot --path game --fixed-fps 30 res://scenes/dev/infiltrator_showcase.tscn   # to watch it
##
## --test prints what happens and checks it at the end (INFILTRATOR SHOWCASE PASS / FAIL).
## The garrison's posts and the AA turrets hold fire.

const SOLO_AT := Vector3(20.0, 0.0, 104.0)
const DECOY_AT := Vector3(-5.0, 0.0, 104.0)
const RIFLE_AT := Vector3(8.0, 0.0, 120.0)
## Riflemen standing on the straight way from the south gate to the South Helipad.
const WATCH_AT := Vector3(-22.0, 0.0, 100.0)
## Phases, and the longest each may take (s).
const PHASES := ["profile", "ordered", "camo", "bow", "op", "view", "retake", "end"]
const TIMEOUT := {"profile": 6.0, "ordered": 2.5, "camo": 5.0, "bow": 7.0, "op": 260.0, "view": 3.0, "retake": 30.0}

var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var dc: DefenderController
var cam: Camera3D
var solo: InfiltratorTrooper
var decoy: FlameTrooper
var riflemen: Array = []
var watchers: Array = []
var squad: InfiltratorSquad
var pad: AttackerBase
var test := false
var phase := ""
var t := -1.0
var _phase_t := 0.0
var _checks: Array[String] = []
var _failed := false
var _flags := {}
## Op: the closest the leader came to a watcher out in the field, and how close the straight way
## from the gate passes them.
var _route_clear := INF
var _line_clear := INF
var _plans: Array[String] = []
var _income_held := 0.0


func _ready() -> void:
	seed(11)
	test = "--test" in OS.get_cmdline_user_args()
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	for s in level.stations + level.aa_turrets:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	add_child(commander)
	pad = level.bases.filter(func(b): return b.side == "south")[0]
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# The navmesh's first iteration lands a few frames after the bake.
	for k in 10:
		await get_tree().physics_frame
	t = 0.0
	_enter("profile")


func _log(text: String) -> void:
	print("INFIL t=%.1f %s" % [t, text])


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
	_log(("check ok: " if ok else "CHECK FAILED: ") + what)


func _rifleman(at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "rifleman", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = at + Vector3.UP * 0.2
	return u


func _trooper(t_: SquadTrooper, at: Vector3, face: Vector3) -> void:
	add_child(t_)
	t_.global_position = at + Vector3.UP * 0.1
	t_.aim_point = face
	t_.following = true
	t_.goal = at


func _physics_process(delta: float) -> void:
	if t < 0.0 or phase == "end":
		return
	t += delta
	_phase_t += delta
	_camera()
	match phase:
		"op":
			_watch_op()
	if _phase_t >= TIMEOUT.get(phase, 0.0) or _done():
		_leave(phase)
		_enter(PHASES[PHASES.find(phase) + 1])


## True once the phase has what it waits for (the timed ones run out instead).
func _done() -> bool:
	match phase:
		"op":
			return _flags.get("restocked", false)
		"retake":
			return pad.controlled
	return false


func _enter(p: String) -> void:
	phase = p
	_phase_t = 0.0
	_log("phase %s" % p)
	match p:
		"profile":
			solo = InfiltratorTrooper.new()
			_trooper(solo, SOLO_AT, RIFLE_AT + Vector3.UP)
			decoy = FlameTrooper.new()
			_trooper(decoy, DECOY_AT, RIFLE_AT + Vector3.UP)
			for k in 3:
				riflemen.append(_rifleman(RIFLE_AT + Vector3(k * 2.0 - 2.0, 0.0, 0.0)))
		"ordered":
			commander.submit({"type": "attack", "units": _ids(riflemen), "target": solo.get_path()})
		"camo":
			solo.hp = solo.max_hp
			solo.set_camo(true, false)
		"bow":
			solo.set_camo(false, false)
			solo.hp = solo.max_hp
			solo.trigger = true
		"op":
			_start_op()
		"view":
			dc.select_squad(armory.squads.find(squad), true)
			squad.camo_cd = 0.0
			squad.camo_left = 0.0
			_check(squad.start_camo(), "the player puts the camo on (Q)")
		"retake":
			for k in 3:
				_rifleman(pad.spawn_point + Vector3(k * 2.0 - 2.0, 0.0, 0.0))
		"end":
			_finish()


func _leave(p: String) -> void:
	match p:
		"profile":
			_check(is_equal_approx(solo.hp, solo.max_hp), "low profile: the riflemen never shot the infiltrator (hp %d/%d)" % [solo.hp, solo.max_hp])
			_check(decoy.hp < decoy.max_hp, "the riflemen shot the decoy next to her (hp %d/%d)" % [decoy.hp, decoy.max_hp])
		"ordered":
			_check(solo.hp < solo.max_hp, "ordered to attack her, they do (hp %d/%d)" % [solo.hp, solo.max_hp])
		"camo":
			_check(riflemen.all(func(u): return u.order.type != "attack"), "under camo the attack order lapsed")
			_check(solo.collision_layer == 0, "under camo shots and clicks pass through her")
			commander.submit({"type": "attack", "units": _ids(riflemen), "target": solo.get_path()})
			_check(riflemen.all(func(u): return u.order.type != "attack"), "a fresh order to attack her is refused")
			_check(is_equal_approx(solo.hp, solo.max_hp), "no basic attack hurt her under camo (hp %d/%d)" % [solo.hp, solo.max_hp])
			Combat.damage_area(self, solo.global_position + Vector3.UP, 5.0, 80.0, GameConfig.TEAM_ATTACKER)
			_check(solo.hp < solo.max_hp, "a blast still hurts her under camo (hp %d/%d)" % [solo.hp, solo.max_hp])
		"bow":
			solo.trigger = false
			var hurt := riflemen.filter(func(u): return not is_instance_valid(u) or not u.is_alive() or u.hp < u.stats.hp).size()
			_check(solo.stats.arrows >= 2 and solo.stats.hits >= 1, "the bow: %d arrows, %d hits" % [solo.stats.arrows, solo.stats.hits])
			_check(hurt >= 1, "arrows hurt the riflemen (%d hurt)" % hurt)
		"op":
			_check(_flags.get("sabotaged", false), "the squad sabotaged the South Helipad")
			_check(_flags.get("restocked", false), "it came home and restocked its kit in the fortress")
			_check(_route_clear > _line_clear + 8.0, "its route kept away from the riflemen: %.1f m at the closest (the straight way: %.1f m)" % [_route_clear, _line_clear])
			_log("plans: %s" % " > ".join(_plans))
		"view":
			_check(squad._infil_hud.vignette() > 0.3, "the camera has the camo vignette (%.2f)" % squad._infil_hud.vignette())
			var leader := squad.leader as InfiltratorTrooper
			_check(leader.camouflaged and leader._model.visible and leader._bow_node.visible, "on the defender's side the troopers look as ever")
			GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
			leader.set_camo(true, InfiltratorSquad._camo_hidden())
			_check(not leader._model.visible and not leader._bow_node.visible and not leader._string_mi.visible, "on the attacker's side they don't show at all")
			GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
			leader.set_camo(true, false)
		"retake":
			_check(pad.controlled, "riflemen standing by it retook the helipad")
			_check(commander.spawn_open(level.spawn_bases.find(pad)), "the attackers spawn there again")


func _ids(units: Array) -> Array:
	return units.filter(func(u): return is_instance_valid(u) and u.is_alive()).map(func(u): return u.unit_id)


# ---------------------------------------------------------------- the operation

func _start_op() -> void:
	for u in riflemen:
		if is_instance_valid(u) and u.is_alive():
			u.take_damage(10000.0, GameConfig.TEAM_DEFENDER)
	solo.queue_free()
	decoy.queue_free()
	for k in 4:
		watchers.append(_rifleman(WATCH_AT + Vector3(k % 2 * 3.0 - 1.5, 0.0, k / 2 * 3.0 - 1.5)))
	armory = DefenderArmory.new()
	armory.level = level
	armory.credits = DefenderArmory.INFILTRATOR_COST
	armory._bought = 2  # the halls go east, west, south in turn: this one is the third
	add_child(armory)
	dc = DefenderController.new()
	dc.level = level
	dc.armory = armory
	add_child(dc)
	cam.current = true  # the controller took over a post's camera
	squad = dc.buy_squad("infiltrator") as InfiltratorSquad
	for k in 4:
		if squad.op == pad:
			break
		squad.cycle_order()
	_log("%s deployed, order %s" % [squad.station_name, squad.order_name()])
	_income_held = commander.income_rate()
	# How close the straight way from the gate to the helipad passes the riflemen.
	var gate: Vector3 = level.gates["south"].global_position
	var exit := Vector3(gate.x, 0.0, gate.z + InfiltratorSquad.GATE_OUT)
	var spot := pad.global_position + (exit - pad.global_position).normalized() * 12.0
	for w in watchers:
		var p := Geometry3D.get_closest_point_to_segment(w.global_position, exit, spot)
		_line_clear = minf(_line_clear, Vector2(p.x - w.global_position.x, p.z - w.global_position.z).length())


func _watch_op() -> void:
	if squad == null or squad.leader == null:
		return
	if _plans.is_empty() or _plans[-1] != squad.plan:
		_plans.append(squad.plan)
		_log("plan %s" % squad.plan)
	var here := squad.leader.global_position
	if squad.plan == "approach" and not InfiltratorSquad._in_mountain(here):
		for w in watchers:
			_route_clear = minf(_route_clear, Vector2(here.x - w.global_position.x, here.z - w.global_position.z).length())
	if not pad.controlled and not _flags.get("sabotaged", false):
		_flags.sabotaged = true
		_log("helipad sabotaged")
		var idx := level.spawn_bases.find(pad)
		_check(not commander.spawn_open(idx), "the attackers can't spawn at the sabotaged helipad")
		_check(commander.submit({"type": "spawn", "unit": "rifleman", "spawn": idx}) == 0, "a spawn order there is refused")
		_check(commander.income_rate() < _income_held, "the attackers lost its supply (%.1f/s, was %.1f/s)" % [commander.income_rate(), _income_held])
		_check(squad.kits == 0, "the squad used its kit")
	if _flags.get("sabotaged", false) and squad.kits > 0:
		_flags.restocked = true


# ---------------------------------------------------------------- watching

func _camera() -> void:
	var at := SOLO_AT
	if squad != null and squad.leader != null:
		at = squad.leader.global_position
	elif phase == "retake":
		at = pad.global_position
	if dc != null and dc.current == squad and squad != null:
		return  # the squad's own camera
	cam.global_position = at + Vector3(10.0, 14.0, 22.0)
	cam.look_at(at + Vector3.UP)


func _finish() -> void:
	print("INFIL checks:")
	for c in _checks:
		print("  " + c)
	print("INFILTRATOR SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if test:
		get_tree().quit(1 if _failed else 0)
