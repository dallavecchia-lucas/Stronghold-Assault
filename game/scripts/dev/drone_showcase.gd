extends Node3D
## The defenders' drones on a plain field (a floor, a ring of roof docks, a few attackers): the fuel rules, the
## six-swarm cap, one focus per swarm, calls, and which attackers can touch a drone.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/drone_showcase.tscn -- --test   # DRONE SHOWCASE PASS / FAIL
##   godot --path game res://scenes/dev/drone_showcase.tscn                                       # watch two swarms work
##
## --test steps the bay, the swarms and the drones by hand at a fixed 1/30 s, so it doesn't depend on the frame rate.

const DT := 1.0 / 30.0
## Eight roof mounts round a fortress 40 m out, 16 m up.
const MOUNTS := 8

var bay: DroneBay
var checks := 0
var fails := 0
var _next_id := 1


func _ready() -> void:
	var test := OS.get_cmdline_user_args().has("--test")
	_floor()
	if test:
		await get_tree().physics_frame
		await get_tree().physics_frame
		await _run_tests()
		print("DRONE SHOWCASE %s (%d checks, %d failed)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
		get_tree().quit(1 if fails > 0 else 0)
	else:
		_demo()


func _check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if ok:
		print("  ok    %s" % name)
	else:
		fails += 1
		print("  FAIL  %s %s" % [name, detail])


# ---------------------------------------------------------------- the world

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(900.0, 2.0, 900.0)
	shape.shape = box
	shape.position.y = -1.0
	body.add_child(shape)
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900.0, 900.0)
	mesh.mesh = plane
	mesh.material_override = Mats.flat(Color(0.3, 0.38, 0.25))
	add_child(mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)


func _new_bay(swarms: int, manual := true) -> void:
	if bay != null:
		bay.queue_free()
		for u in get_tree().get_nodes_in_group("attacker_units"):
			u.queue_free()
		await get_tree().process_frame
	bay = DroneBay.new()
	bay.manual = manual
	bay.auto_calls = manual == false
	bay.initial_swarms = swarms
	var mounts: Array = []
	for k in MOUNTS:
		var a := TAU * float(k) / float(MOUNTS)
		mounts.append(Vector3(cos(a) * 40.0, 16.0, sin(a) * 40.0))
	bay.set_docks(mounts)
	add_child(bay)


func _attacker(type_id: String, at: Vector3) -> AttackerUnit:
	var u := AttackerUnit.new()
	u.setup(type_id, _next_id)
	_next_id += 1
	u.position = at + Vector3(0.0, 0.2, 0.0)
	add_child(u)
	return u


## Steps the bay, its swarms and its drones by hand for `seconds`; `each` is called after every step.
func _run(seconds: float, each := Callable()) -> void:
	for i in int(seconds / DT):
		bay.step(DT)
		for s in bay.swarms.duplicate():
			s.step(DT)
		for c in bay.get_children():
			if c is DefenderDrone:
				c.step(DT)
		if each.is_valid():
			each.call()


func _step_drone(d: DefenderDrone, seconds: float) -> void:
	for i in int(seconds / DT):
		d.step(DT)


func _kill(d: DefenderDrone) -> void:
	if d.state == DefenderDrone.State.DOCKED:
		d.launch(d.global_position + Vector3(0.0, 4.0, 0.0))
	d.take_damage(9999.0, GameConfig.TEAM_ATTACKER)


# ---------------------------------------------------------------- the tests

func _run_tests() -> void:
	_test_fuel_rules()
	await _new_bay(0)
	_test_flight_and_fuel()
	await _new_bay(0)
	_test_cap()
	await _new_bay(0)
	await _test_focus()
	await _new_bay(0)
	await _test_hunters()
	await _new_bay(2)
	_test_calls()
	await _new_bay(1)
	_test_stand_down()
	await _new_bay(0)
	await _test_auto_calls()


func _test_fuel_rules() -> void:
	print("fuel rules")
	var fortress := DefenderDrone.FORTRESS_SIZE
	_check("a third of a tank per fortress size flown", is_equal_approx(DefenderDrone.trip_cost(fortress), 1.0 / 3.0))
	_check("hovering burns 5% in 10 s", is_equal_approx(DefenderDrone.HOVER_BURN * 10.0, 0.05))
	_check("at 50% fuel it turns, wherever it is", DefenderDrone.must_return(0.5, 0.0))
	_check("full tank at the dock stays out", not DefenderDrone.must_return(1.0, 0.0))
	_check("full tank 200 m out stays out", not DefenderDrone.must_return(1.0, 200.0))
	_check("full tank 260 m out (the way home costs half) turns", DefenderDrone.must_return(1.0, 260.0))
	# 0.6 fuel: the way home costs half of it (0.3) at 0.3 / FUEL_PER_M = about 155 m.
	_check("0.6 fuel, 150 m out: stays", not DefenderDrone.must_return(0.6, 150.0))
	_check("0.6 fuel, 156 m out: the way home is half what's left, turns", DefenderDrone.must_return(0.6, 156.0))
	_check("a trip is only worth it with margin: 100 m yes", DefenderDrone.can_reach(1.0, Vector3.ZERO, Vector3(100, 0, 0), 100.0))
	_check("a trip is only worth it with margin: 200 m no", not DefenderDrone.can_reach(1.0, Vector3.ZERO, Vector3(200, 0, 0), 200.0))
	_check("a half-empty tank can't be sent anywhere", not DefenderDrone.can_reach(0.5, Vector3.ZERO, Vector3(10, 0, 0), 10.0))


func _test_flight_and_fuel() -> void:
	print("one drone: out, hovering, home, recharge")
	var s := bay.build_swarm()
	var d := s.drones[0] as DefenderDrone
	var start := d.global_position
	var goal := Vector3(100.0, 12.0, 0.0)
	_check("a built drone sits docked with a full tank", d.state == DefenderDrone.State.DOCKED and is_equal_approx(d.fuel, 1.0))
	_check("a docked drone isn't in air_units (nothing can target it)", not d.is_in_group("air_units"))
	_check("it can take off", d.launch(goal))
	_check("airborne it is in air_units", d.is_in_group("air_units"))
	_check("airborne it is NOT damageable (blasts and strays can't reach it)", not d.is_in_group("damageable"))
	var t := 0.0
	while d.global_position.distance_to(goal) > 0.3 and t < 40.0:
		d.step(DT)
		t += DT
	var expect := DefenderDrone.trip_cost(start.distance_to(goal))
	_check("flying out costs the distance flown", absf((1.0 - d.fuel) - expect) < 0.02,
			"(used %.3f, expected about %.3f)" % [1.0 - d.fuel, expect])
	var before := d.fuel
	_step_drone(d, 10.0)
	_check("10 s hovering costs 5%", absf((before - d.fuel) - 0.05) < 0.006, "(used %.4f)" % (before - d.fuel))
	var guard := 0.0
	while d.state == DefenderDrone.State.FLYING and guard < 600.0:
		d.step(DT)
		guard += DT
	_check("it turns for home by itself", d.state == DefenderDrone.State.RETURNING)
	_check("near the fortress it turns at the 50% mark", absf(d.fuel - 0.5) < 0.02, "(fuel %.3f)" % d.fuel)
	_check("a returning drone isn't hunting", d.target == null)
	guard = 0.0
	while d.state != DefenderDrone.State.DOCKED and guard < 60.0:
		d.step(DT)
		guard += DT
	_check("it lands", d.state == DefenderDrone.State.DOCKED)
	_check("it lands with fuel to spare, never stranded", d.fuel > 0.25, "(fuel %.3f)" % d.fuel)
	_check("landed, it is out of air_units again", not d.is_in_group("air_units"))
	_check("it isn't ready on a half tank", not d.is_ready())
	guard = 0.0
	while not d.is_ready() and guard < 60.0:
		d.step(DT)
		guard += DT
	_check("recharged within RECHARGE_TIME", d.is_ready() and guard <= DefenderDrone.RECHARGE_TIME, "(took %.1f s)" % guard)

	# Out at the end of its leash the second rule turns it back well before the 50% mark.
	var far := s.drones[1] as DefenderDrone
	far.launch(Vector3(200.0, 12.0, 0.0))
	guard = 0.0
	while far.state == DefenderDrone.State.FLYING and guard < 600.0:
		far.step(DT)
		guard += DT
	_check("far out it turns back sooner, with more than 50% left", far.state == DefenderDrone.State.RETURNING and far.fuel > 0.55,
			"(fuel %.3f)" % far.fuel)
	var way_home := DefenderDrone.trip_cost(far.global_position.distance_to(far.dock_position()))
	_check("... when the way home costs about half of what it had left", way_home > far.fuel * 0.42 and way_home < far.fuel * 0.58,
			"(way home %.3f of %.3f)" % [way_home, far.fuel])
	guard = 0.0
	while far.state != DefenderDrone.State.DOCKED and guard < 90.0:
		far.step(DT)
		guard += DT
	_check("the far one lands too, with fuel to spare", far.state == DefenderDrone.State.DOCKED and far.fuel > 0.2, "(fuel %.3f)" % far.fuel)


func _test_cap() -> void:
	print("six swarms at most; a new one only after a whole swarm is dead")
	for i in DroneBay.MAX_SWARMS:
		bay.build_swarm()
	_check("six swarms", bay.swarms.size() == DroneBay.MAX_SWARMS)
	_check("thirty drones", bay.alive_count() == DroneBay.MAX_SWARMS * DroneSwarm.SIZE)
	_check("a seventh can't be built", bay.build_swarm() == null)
	var first: DroneSwarm = bay.swarms[0]
	for k in 4:
		_kill(first.drones[0])
	_check("four of five drones down: the swarm still counts", bay.swarms.size() == DroneBay.MAX_SWARMS and first.alive_count() == 1)
	for i in int(200.0 / DT / 10.0):
		bay.step(DT * 10.0)
	_check("... and nothing replaces them, however long it waits", bay.swarms.size() == DroneBay.MAX_SWARMS and first.alive_count() == 1)
	_kill(first.drones[0])
	_check("the last drone down: the swarm is gone", bay.swarms.size() == DroneBay.MAX_SWARMS - 1)
	for i in int((DroneBay.BUILD_TIME - 1.0) / DT):
		bay.step(DT)
	_check("the place isn't refilled at once", bay.swarms.size() == DroneBay.MAX_SWARMS - 1)
	for i in int(2.0 / DT):
		bay.step(DT)
	_check("BUILD_TIME after the loss a new swarm is built", bay.swarms.size() == DroneBay.MAX_SWARMS)


func _test_focus() -> void:
	print("one swarm, one focus")
	var medic := _attacker("medic", Vector3(60.0, 0.0, 12.0))
	var roo := _attacker("kangaroo", Vector3(62.0, 0.0, -12.0))
	_attacker("hippo", Vector3(68.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var s := bay.build_swarm()
	var state := {"split": 0, "min_fuel": 1.0, "frames": 0}
	var watch := func():
		state.frames += 1
		for d in s.drones:
			state.min_fuel = minf(state.min_fuel, d.fuel)
			if d.state == DefenderDrone.State.FLYING and d.target != null and d.target != s.focus:
				state.split += 1
	_run(6.0, watch)
	_check("it picked the Wolf Medic (the most worth hitting that can't hit back)", s.focus == medic)
	var aloft := 0
	for d in s.drones:
		if d.state == DefenderDrone.State.FLYING and d.target == medic:
			aloft += 1
	_check("every drone aloft is on that one target", aloft == s.airborne_count() and aloft >= 1, "(%d of %d)" % [aloft, s.airborne_count()])
	var guard := 0.0
	while medic.is_alive() and guard < 120.0:
		_run(5.0, watch)
		guard += 5.0
	_check("the medic goes down to constant low damage", not medic.is_alive(), "(hp %.0f after %.0f s)" % [medic.hp, guard])
	_run(5.0, watch)
	_check("then it picks the next one, the kangaroo (never the hippo while it can)", s.focus == roo, "(focus %s)" % [s.focus])
	_check("it never split its fire", state.split == 0, "(%d drone-frames on another target)" % state.split)
	_check("no drone ran its tank dry", state.min_fuel > 0.2, "(lowest %.3f)" % state.min_fuel)


func _test_hunters() -> void:
	print("who can touch a drone")
	var bear := _attacker("rifleman", Vector3(70.0, 0.0, 0.0))
	var roo := _attacker("kangaroo", Vector3(72.0, 0.0, 3.0))
	var rhino := _attacker("rhino", Vector3(80.0, 0.0, -4.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var s := bay.build_swarm()
	var d := s.drones[0] as DefenderDrone
	d.launch(Vector3(95.0, 12.0, 0.0))
	d.global_position = Vector3(95.0, 12.0, 0.0)
	# Everything below happens inside this one frame: the units' own AI hasn't run.
	bear._update_drone_prey()
	roo._update_drone_prey()
	rhino._update_drone_prey()
	_check("a bear locks onto a drone in sight", bear.is_drone_locked())
	_check("an AA unit locks onto it", rhino.is_drone_locked())
	_check("a kangaroo can't, and doesn't", not roo.is_drone_locked() and not roo.hunts_drones())
	bear.set_order({"type": "move", "pos": Vector3(0.0, 0.0, 120.0)})
	roo.set_order({"type": "move", "pos": Vector3(0.0, 0.0, 120.0)})
	_check("a locked bear takes no orders", bear.order.type == "idle" and bear._held_order != null)
	_check("a free kangaroo does", roo.order.type == "move")
	var hp := d.hp
	Combat.explode(self, d.global_position, 12.0, 900.0, GameConfig.TEAM_ATTACKER)
	_check("a blast doesn't touch it", is_equal_approx(d.hp, hp))
	Combat.fire_hitscan(roo, Vector3(70.0, 2.0, 0.0), d.global_position, 0.0, 50.0, GameConfig.TEAM_ATTACKER)
	_check("a rifle round through it doesn't touch it", is_equal_approx(d.hp, hp))
	d.take_damage(50.0, GameConfig.TEAM_DEFENDER)
	_check("its own side can't hurt it", is_equal_approx(d.hp, hp))
	var hit := Combat.fire_at_air(bear, bear.global_position + Vector3.UP * 1.5, d, 0.0, 8.0, GameConfig.TEAM_ATTACKER)
	_check("a bear's round hits it", hit and is_equal_approx(d.hp, hp - 8.0), "(hp %.1f)" % d.hp)
	rhino._aa_tick()
	_check("an AA unit's guns hurt it", d.hp < hp - 8.0, "(hp %.1f)" % d.hp)
	d.take_damage(9999.0, GameConfig.TEAM_ATTACKER)
	bear._update_drone_prey()
	_check("with the drone down the bear is free", not bear.is_drone_locked())
	_check("... and carries out the order it was given meanwhile", bear.order.type == "move" and bear._held_order == null)
	# A swarm would rather have an unguarded target that can't shoot back.
	bay._scan_hunters()
	var swarm_pick := s._score(roo, Vector3.ZERO, false) > s._score(bear, Vector3.ZERO, false)
	_check("a swarm would rather have the kangaroo than the bear that shoots back", swarm_pick)


func _test_calls() -> void:
	print("calls")
	_check("two swarms to start with", bay.swarms.size() == 2)
	var r := bay.call_swarm(Vector3(100.0, 0.0, 0.0))
	_check("a call 100 m out gets a swarm", r.ok and r.swarm != null)
	r = bay.call_swarm(Vector3(110.0, 0.0, 6.0))
	_check("the same spot isn't called twice", not r.ok, "(%s)" % r.reason)
	r = bay.call_swarm(Vector3(900.0, 0.0, 0.0))
	_check("a spot too far out for the fuel can't be called", not r.ok and r.reason.contains("reach"), "(%s)" % r.reason)
	# Every drone half empty: nothing to send.
	for s in bay.swarms:
		for d in s.drones:
			d.fuel = 0.6
			d.state = DefenderDrone.State.DOCKED
	bay._recent.clear()
	r = bay.call_swarm(Vector3(0.0, 0.0, 100.0))
	_check("with every drone recharging there is none to send", not r.ok and r.reason.contains("recharging"), "(%s)" % r.reason)


func _test_stand_down() -> void:
	print("called to nothing: out, a look round, home, docked, free to be called again")
	var s: DroneSwarm = bay.swarms[0]
	var spot := Vector3(90.0, 0.0, 0.0)
	var r := bay.call_swarm(spot)
	_check("the call is taken", r.ok)
	_run(1.0)
	_check("the swarm is busy while it holds the spot", s.busy())
	_run(4.0)
	_check("it flies out to the spot", s.airborne_count() == s.alive_count(), "(%d aloft of %d)" % [s.airborne_count(), s.alive_count()])
	_check("... and holds the call while it looks round", s.anchor != Vector3.INF)
	_run(30.0)
	var docked := 0
	for d in s.drones:
		if d.state == DefenderDrone.State.DOCKED:
			docked += 1
	_check("with nothing there it came home and docked, all five", docked == DroneSwarm.SIZE, "(%d docked)" % docked)
	_check("a docked swarm is nothing: not busy, no call held, nothing aloft",
			not s.busy() and s.anchor == Vector3.INF and s.airborne_count() == 0)
	_check("... and it still counts as one of the swarms (nothing was lost)", bay.swarms.size() == 1 and s.alive_count() == DroneSwarm.SIZE)
	_check("it didn't return empty-handed on fuel: it used some", s.drones[0].fuel < 1.0 or s.drones[0].burnt > 0.1)
	_run(25.0)
	_check("recharged", s.ready_count() == DroneSwarm.SIZE, "(%d ready)" % s.ready_count())
	r = bay.call_swarm(spot)
	_check("it can be called to the same spot again", r.ok, "(%s)" % r.reason)
	_run(8.0)
	_check("and goes", s.airborne_count() > 0)
	# A call that can't get a drone off the dock lapses and leaves the swarm free.
	for d in s.drones:
		d.fuel = 0.6
		d.state = DefenderDrone.State.DOCKED
		d.global_position = d.dock_position()
	s.anchor = Vector3(0.0, 0.0, 90.0)
	s.anchor_t = DroneSwarm.CALL_HOLD
	_run(DroneSwarm.LAUNCH_GRACE + 2.0)
	_check("a call nobody could answer lapses", s.anchor == Vector3.INF and not s.busy())


func _test_auto_calls() -> void:
	print("the garrison's own calls never take a swarm off its target")
	var roo := _attacker("kangaroo", Vector3(62.0, 0.0, -12.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var s := bay.build_swarm()
	_run(8.0)
	_check("the swarm is on the kangaroo", s.focus == roo and s.busy())
	var far := Vector3(60.0, 0.0, 60.0)
	var r := bay.call_swarm(far, null, true)
	_check("a garrison call can't take the only swarm, busy as it is", not r.ok and r.reason.contains("busy"), "(%s)" % r.reason)
	_check("... and it stayed on its target", s.focus == roo)
	r = bay.call_swarm(far)
	_check("a player's call can", r.ok, "(%s)" % r.reason)


# ---------------------------------------------------------------- watching it

func _demo() -> void:
	_new_bay(2, false)
	await get_tree().process_frame
	_attacker("medic", Vector3(60.0, 0.0, 12.0))
	_attacker("kangaroo", Vector3(62.0, 0.0, -12.0))
	_attacker("hippo", Vector3(68.0, 0.0, 0.0))
	_attacker("giraffe", Vector3(75.0, 0.0, 8.0))
	var cam := Camera3D.new()
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(10.0, 50.0, 120.0)
	cam.look_at(Vector3(50.0, 8.0, 0.0))
