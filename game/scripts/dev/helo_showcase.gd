extends Node3D
## The attackers' transport helicopters (TransportHelo, HeloFleet, HeloCargo) on a plain field with a stand-in for an outpost:
## the hold (50 spaces, what each unit takes), boarding through the commander's commands, a trip (one outpost, landing on its
## pad, units put down next to the camp a quarter of a second apart in the order they went in, then home), the outpost lost on
## the way (it brings them home) or while it is on the pad (a fifth of its health and away, or destroyed), a hurt helicopter
## staying put till it is mended and the smoke and fire its hurt shows, a helicopter destroyed (everything aboard lost, a new
## one 500 s later), and who can hurt it (the player's rounds and blasts can; nothing idle ever picks it out).
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/helo_showcase.tscn -- --test   # HELO SHOWCASE PASS / FAIL
##   godot --path game res://scenes/dev/helo_showcase.tscn                                       # watch a helicopter ferry units
##
## --test steps the fleet and the helicopters by hand at a fixed 1/30 s, so it doesn't depend on the frame rate. The units are
## real ones (they need the models: run `git lfs pull`); they are put at the ramp by hand, since the floor has no navmesh to
## walk on.

const DT := 1.0 / 30.0
## The main spawn point of the Jungle Keep, and a stand-in outpost at the Quarry: its pad, on a deck 22 m up (the Outpost's
## height), and the first spot on the ground beside the camp where a helicopter's units are put down.
const MAIN := Vector3(0.0, 0.0, 610.0)
const OUTPOST_PAD := Vector3(-383.0, 22.0, -40.0)
const OUTPOST_DROP := Vector3(-330.0, 0.0, -40.0)


## A stand-in for a helipad the attackers hold: what a helicopter reads of one.
class FakeBase:
	extends Node3D
	var controlled := true
	var short_name := "Quarry"
	var display_name := "Quarry Helipad"
	var landing := Vector3.ZERO
	var landing_heading := PI * 0.5
	var drop := Vector3.ZERO

	func landing_point() -> Vector3:
		return landing

	func landing_yaw() -> float:
		return landing_heading

	## Rows of DROP_SPACING going out from `drop`, like AttackerBase.drop_spot.
	func drop_spot(index: int, count: int) -> Vector3:
		var cols := maxi(ceili(sqrt(float(maxi(count, 1)))), 1)
		var row := floori(float(index) / float(cols))
		return drop + Vector3(float(row) * AttackerBase.DROP_SPACING, 0.0, float(index - row * cols) * AttackerBase.DROP_SPACING)


## A flyer the garrison's anti-air can lock onto (it is in "air_units"), to show the turret does look.
class FakeAir:
	extends Node3D
	var team := GameConfig.TEAM_ATTACKER
	var hp := 100.0

	func _ready() -> void:
		add_to_group("air_units")

	func is_alive() -> bool:
		return hp > 0.0

	func get_aim_point() -> Vector3:
		return global_position

	func take_damage(amount: float, _from_team: int) -> void:
		hp -= amount


var commander: AttackerCommander
var fleet: HeloFleet
var base: FakeBase
var units_root: Node3D
var checks := 0
var fails := 0
var _clock := 0.0
var _demo_cam: Camera3D


func _ready() -> void:
	var test := OS.get_cmdline_user_args().has("--test")
	_floor()
	_world(test)
	if test:
		await get_tree().physics_frame
		await get_tree().physics_frame
		await _run_tests()
		print("HELO SHOWCASE %s (%d checks, %d failed)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
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
	box.size = Vector3(2400.0, 2.0, 2400.0)
	shape.shape = box
	shape.position.y = -1.0
	body.add_child(shape)
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400.0, 2400.0)
	mesh.mesh = plane
	mesh.material_override = Mats.flat(Color(0.3, 0.38, 0.25))
	add_child(mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)


## A commander (so units spawn and die as in a match), the stand-in outpost as spawn point 1, and the fleet by the main base.
func _world(manual: bool) -> void:
	units_root = Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.supply = 1.0e7
	var points: Array[Vector3] = [MAIN, OUTPOST_DROP]
	commander.spawn_points = points
	base = FakeBase.new()
	base.landing = OUTPOST_PAD
	base.drop = OUTPOST_DROP
	add_child(base)
	base.position = OUTPOST_PAD
	commander.spawn_bases = [null, base]
	add_child(commander)
	_new_fleet(manual)


func _new_fleet(manual := true) -> void:
	if fleet != null:
		fleet.queue_free()
	fleet = HeloFleet.new()
	fleet.manual = manual
	fleet.with_rig = not manual
	fleet.base_position = MAIN
	add_child(fleet)
	commander.fleet = fleet


## Starts over: no units, a fresh fleet, the outpost held.
func _reset() -> void:
	for u in commander.units.values():
		if is_instance_valid(u):
			u.queue_free()
	commander.units.clear()
	base.controlled = true
	_new_fleet()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _unit(type_id: String, at := Vector3.ZERO) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units.get(id)
	u.global_position = (at if at != Vector3.ZERO else MAIN) + Vector3(0.0, 0.2, 0.0)
	return u


## Steps the fleet and its helicopters by hand for `seconds` (or until `until` is true); returns the seconds it took.
func _run(seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		fleet.step(DT)
		for i in fleet.slots.size():
			var h = fleet.slots[i]
			if h != null and is_instance_valid(h):
				h.step(DT)
		t += DT
		_clock += DT
		if until.is_valid() and until.call():
			break
	return t


## Sends `u` to the helicopter's ramp the way the commander does and has it arrive (there is no navmesh to walk on).
func _board(h: TransportHelo, u: AttackerUnit) -> bool:
	if not h.reserve(u):
		return false
	u.set_order({"type": "helo", "helo": h, "pos": h.ramp_point()})
	u.global_position = h.ramp_point() + Vector3(0.0, 0.2, 0.0)
	u._helo_step()
	return u.is_stowed()


## `n` copies of a unit type (for the hold's arithmetic).
func _times(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


func _state(h: TransportHelo, s: TransportHelo.State) -> Callable:
	return func(): return h.state == s


# ---------------------------------------------------------------- the tests

func _run_tests() -> void:
	_test_cargo_table()
	_test_parking()
	await _reset()
	await _test_boarding()
	await _reset()
	await _test_commands()
	await _reset()
	await _test_trip()
	await _reset()
	await _test_mending()
	await _reset()
	await _test_outpost_rules()
	await _reset()
	await _test_caught_on_pad()
	await _reset()
	await _test_damage_looks()
	await _reset()
	await _test_real_pad()
	await _reset()
	await _test_destroyed()
	await _reset()
	await _test_replacement()
	await _reset()
	await _test_who_can_hurt_it()


func _test_cargo_table() -> void:
	print("the hold's arithmetic")
	_check("50 spaces", HeloCargo.CAPACITY == 50)
	_check("a unit is unloaded every quarter of a second", is_equal_approx(HeloCargo.UNLOAD_TIME, 0.25))
	_check("a new helicopter 500 s after one is destroyed", is_equal_approx(HeloCargo.REPLACE_TIME, 500.0))
	_check("two helicopters", HeloCargo.FLEET_SIZE == 2)
	for pair in [["elephant", 5], ["giraffe", 5], ["rhino", 2], ["hippo", 2], ["bison_gun", 10], ["mule", 15]]:
		_check("%s takes %d" % [pair[0], pair[1]], HeloCargo.spaces(pair[0]) == pair[1])
	for id in UnitTypes.ORDER:
		if not HeloCargo.SPACES.has(id):
			_check("%s takes 1 (every other unit)" % id, HeloCargo.spaces(id) == 1)
	_check("the table names only real units", HeloCargo.SPACES.keys().all(func(k): return UnitTypes.DATA.has(k)))
	_check("ten elephants fill the hold exactly", HeloCargo.used(_times("elephant", 10)) == 50 and HeloCargo.fits(45, "elephant")
			and not HeloCargo.fits(46, "elephant"))
	_check("a full hold takes nobody else, however small", not HeloCargo.fits(50, "rifleman"))
	_check("three mules and five bears: 50", HeloCargo.used(_times("mule", 3) + _times("rifleman", 5)) == 50)
	_check("three mules and a bison don't fit (55)", HeloCargo.used(_times("mule", 3) + ["bison_gun"]) == 55
			and not HeloCargo.fits(45, "bison_gun") and HeloCargo.fits(40, "bison_gun"))
	_check("most of each in an empty hold: 10 elephants, 5 bisons, 3 mules, 25 rhinos, 50 bears",
			HeloCargo.most_of("elephant") == 10 and HeloCargo.most_of("bison_gun") == 5 and HeloCargo.most_of("mule") == 3
			and HeloCargo.most_of("rhino") == 25 and HeloCargo.most_of("rifleman") == 50)
	_check("a full hold of bears takes 12.5 s to unload", is_equal_approx(HeloCargo.unload_seconds(50), 12.5))
	_check("it is tough: more than a whole sortie of the jet's bombs and missiles",
			TransportHelo.MAX_HP > DefenderJet.BOMBS * DefenderJet.BOMB_DAMAGE + DefenderJet.SALVO * DefenderJet.MISSILE_DAMAGE)
	_check("... but it can be done: a handful of sorties", TransportHelo.MAX_HP < 8.0 * (DefenderJet.BOMBS * DefenderJet.BOMB_DAMAGE
			+ DefenderJet.SALVO * DefenderJet.MISSILE_DAMAGE))
	_check("mending a wrecked one takes far less than replacing a lost one", TransportHelo.REPAIR_SECONDS < HeloCargo.REPLACE_TIME)


func _test_parking() -> void:
	print("standing by the main base")
	var a := HeloFleet.park_spot(MAIN, 0)
	var b := HeloFleet.park_spot(MAIN, 1)
	_check("one off to each side of the spawn point", a.position.x < MAIN.x and b.position.x > MAIN.x)
	_check("far enough apart that their rotors (46 m across) don't touch", a.position.distance_to(b.position) > 100.0)
	_check("toward the stronghold from the spawn point, not behind the citadel", a.position.z < MAIN.z and b.position.z < MAIN.z)
	# The ramp at the tail faces the field: the nose points away from the stronghold.
	var h := TransportHelo.new()
	h.manual = true
	h.with_rig = false
	h.setup(0, a.position, a.yaw)
	add_child(h)
	_check("the ramp is toward the stronghold from the helicopter", h.ramp_point().z < h.global_position.z)
	_check("the ramp is a tail's length behind its middle", absf(h.ramp_point().distance_to(h.global_position) - TransportHelo.RAMP_BACK) < 0.5)
	h.queue_free()
	var classic := HeloFleet.park_spot(Vector3(0.0, 0.0, LevelBuilder.MAP_HALF - 12.0), 0)
	_check("on the classic field they stand inside the map", absf(classic.position.x) + 32.0 <= LevelBuilder.MAP_HALF
			and absf(classic.position.z) + 32.0 <= LevelBuilder.MAP_HALF)


func _test_boarding() -> void:
	print("going aboard")
	var h := fleet.helo_at(0)
	var other := fleet.helo_at(1)
	_check("two helicopters stand by", h != null and other != null and h != other)
	_check("parked with full health", h.state == TransportHelo.State.PARKED and h.hp == TransportHelo.MAX_HP)
	_check("nothing aboard, 50 spaces free", h.cargo.is_empty() and h.spaces_free() == 50)
	_check("the hold is open at the base", h.can_board())
	_check("it is a target (damageable, own groups)", h.is_in_group("damageable") and h.is_in_group("transport_helos"))
	_check("... but it is in neither group the defenders look their targets up in",
			not h.is_in_group("air_units") and not h.is_in_group("attacker_units"))
	var bear := _unit("rifleman")
	_check("a unit that is not sent has no place", not h.accepts(bear))
	# A place is kept for a unit while its order is to board this one (the commander reserves, then orders, in one go).
	_check("a place is kept for a unit sent to board", h.reserve(bear))
	bear.set_order({"type": "helo", "helo": h, "pos": h.ramp_point()})
	_check("... one space kept, 49 free", h.spaces_reserved() == 1 and h.spaces_free() == 49 and h.accepts(bear))
	_check("reserving again changes nothing", h.reserve(bear) and h.spaces_reserved() == 1)
	bear.set_order({"type": "move", "pos": MAIN + Vector3(10.0, 0.0, 0.0)})
	_check("given another order it loses its place", h.spaces_reserved() == 0 and not h.accepts(bear))
	_check("boards at the ramp", _board(h, bear))
	_check("aboard it is out of the world: dead to everyone", not bear.is_alive() and bear.is_stowed() and not bear.visible)
	_check("... out of every group the defenders look in", not bear.is_in_group("damageable") and not bear.is_in_group("attacker_units"))
	_check("... not thinking", bear.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("... no target, no orders", not Combat.is_valid_target(bear) and not bear.is_controllable())
	_check("... but still counted in the army", commander.units.has(bear.unit_id))
	_check("the hold has it", h.cargo == [bear] and h.spaces_used() == 1)
	var before := bear.global_position
	commander.submit({"type": "move", "units": [bear.unit_id], "pos": MAIN + Vector3(50.0, 0.0, 0.0), "attack": false})
	_check("commands don't reach a unit aboard", bear.order.type == "idle" and bear.global_position == before)
	# The hold fills by spaces.
	var types := ["elephant", "giraffe", "rhino", "hippo", "bison_gun", "mule"]
	var used := 1
	for t in types:
		var u := _unit(t)
		_check("%s boards (%d of 50 used)" % [t, used + HeloCargo.spaces(t)], _board(h, u))
		used += HeloCargo.spaces(t)
	_check("5+5+2+2+10+15 and the bear: 40 spaces", h.spaces_used() == 40 and h.spaces_free() == 10)
	var big := _unit("bison_gun")
	_check("a second bison (10) takes the last spaces", _board(h, big) and h.spaces_free() == 0)
	var late := _unit("rifleman")
	_check("a full hold keeps no place for even a bear", not h.reserve(late) and not _board(h, late))
	_check("the other helicopter has its own hold", other.spaces_used() == 0 and _board(other, late))
	_check("types come out in the order they went in", h.cargo_types() == ["rifleman", "elephant", "giraffe", "rhino", "hippo", "bison_gun", "mule", "bison_gun"])


func _test_commands() -> void:
	print("boarding by command")
	var h := fleet.helo_at(0)
	var ramp := h.ramp_point()
	var bears: Array = []
	for i in 12:
		bears.append(_unit("rifleman", ramp + Vector3(float(i), 0.0, 30.0)))
	var ids := bears.map(func(u): return u.unit_id)
	var placed := commander.submit({"type": "helo_board", "units": ids, "helo": 0})
	_check("12 bears all get places", placed == 12 and h.spaces_reserved() == 12)
	_check("... and are sent to the ramp", bears.all(func(u): return u.order.type == "helo" and u.order.get("helo") == h))
	_check("an empty or missing helicopter gives none", commander.submit({"type": "helo_board", "units": ids, "helo": 5}) == 0)
	for u in bears:
		u.global_position = ramp + Vector3(0.0, 0.2, 0.0)
		u._helo_step()
	_check("at the ramp they go in", h.cargo.size() == 12 and bears.all(func(u): return u.is_stowed()))
	# More than fit: 50 spaces, then the rest wait by the ramp.
	await _reset()
	h = fleet.helo_at(0)
	var crowd: Array = []
	for i in 59:
		crowd.append(_unit("rifleman", h.ramp_point() + Vector3(float(i % 20), 0.0, 30.0 + float(floori(i / 20.0)))))
	var crowd_ids := crowd.map(func(u): return u.unit_id)
	var got := commander.submit({"type": "helo_board", "units": crowd_ids, "helo": 0})
	_check("59 bears: only 50 get places", got == 50 and h.spaces_free() == 0)
	_check("the other 9 are told to wait by the ramp",
			crowd.filter(func(u): return u.order.type == "move").size() == 9)
	var nearest: AttackerUnit = crowd[0]
	_check("the nearest to the ramp are the ones that get on", nearest.order.type == "helo")
	await _reset()
	h = fleet.helo_at(0)
	var mixed := [_unit("elephant"), _unit("elephant"), _unit("mule"), _unit("mule"), _unit("mule"), _unit("rifleman")]
	var mixed_ids := mixed.map(func(u): return u.unit_id)
	var placed_mixed := commander.submit({"type": "helo_board", "units": mixed_ids, "helo": 0})
	_check("two elephants and three mules (55 spaces) don't all fit: 4 or 5 of the 6 go", placed_mixed >= 4 and placed_mixed <= 5,
			"(%d placed)" % placed_mixed)
	_check("the hold is never over-booked", h.spaces_reserved() <= HeloCargo.CAPACITY)


func _test_trip() -> void:
	print("a trip to an outpost")
	var h := fleet.helo_at(0)
	var home := h.global_position
	var types := ["rifleman", "elephant", "kangaroo", "rhino", "medic", "chimp", "giraffe", "lioness", "hippo", "serpent", "rifleman", "breacher"]
	var crew: Array = []
	for t in types:
		var u := _unit(t)
		_check("%s aboard" % t, _board(h, u))
		crew.append(u)
	var aboard := h.spaces_used()
	_check("%d spaces aboard (12 units, the elephant and giraffe 4 over, the rhino and hippo 1 over)" % aboard,
			aboard == 22 and aboard == HeloCargo.used(types))
	_check("it can fly to the held outpost", commander.helo_can_fly(0, 1))
	_check("not to a spawn point that isn't a helipad", not commander.helo_can_fly(0, 0))
	var empty := fleet.helo_at(1)
	_check("an empty helicopter has nowhere to go", not empty.can_dispatch(base) and not commander.helo_can_fly(1, 1))
	_check("the command takes it off", commander.submit({"type": "helo_fly", "helo": 0, "spawn": 1}) == 1)
	_check("it is committed: spinning up", h.state == TransportHelo.State.SPOOL and h.out_leg)
	_check("nobody else gets on once it is going", not h.can_board() and not h.reserve(_unit("rifleman")))
	_check("it can't be sent anywhere else", not h.dispatch(base) and commander.submit({"type": "helo_fly", "helo": 0, "spawn": 1}) == 0)
	var t_off := _run(60.0, _state(h, TransportHelo.State.CRUISE))
	_check("the rotors spin up (%.1f s) and it climbs to cruising height" % t_off, h.state == TransportHelo.State.CRUISE
			and h.global_position.y >= TransportHelo.MIN_CRUISE - 0.1 and t_off >= TransportHelo.SPOOL_TIME)
	_run(3.0)
	var toward := Vector2(OUTPOST_PAD.x - h.global_position.x, OUTPOST_PAD.z - h.global_position.z)
	_check("nose toward the outpost", absf(angle_difference(h.rotation.y, atan2(toward.x, toward.y))) < 0.3)
	var t_land := _run(150.0, _state(h, TransportHelo.State.UNLOAD))
	var landed_at := _clock
	_check("it sets down by the outpost (%.0f s after it left)" % (t_land + t_off), h.state == TransportHelo.State.UNLOAD)
	_check("... on the pad itself, on the deck 22 m up", is_equal_approx(h.global_position.y, OUTPOST_PAD.y)
			and Vector2(h.global_position.x - OUTPOST_PAD.x, h.global_position.z - OUTPOST_PAD.z).length() < 3.5)
	_check("... its nose along the pad", absf(angle_difference(h.rotation.y, base.landing_heading)) < 0.05)
	_check("nothing unloaded before it is down", h.unloaded_count == 0 and h.cargo.size() == 12)
	# The queue: a unit a quarter of a second, in the order they went in.
	var out_times: Array = []
	var out_ids: Array = []
	var out_at: Array = []
	h.unloaded.connect(func(_helo, u):
		out_times.append(_clock)
		out_ids.append(u.unit_id)
		out_at.append(u.global_position))
	_run(10.0, func(): return h.state != TransportHelo.State.UNLOAD)
	_check("all 12 came out", out_ids.size() == 12 and h.cargo.is_empty())
	var steady := true
	for k in out_times.size():
		var due: float = landed_at + HeloCargo.UNLOAD_TIME * float(k + 1)
		if absf(out_times[k] - due) > DT * 1.5:
			steady = false
	_check("one every 0.25 s: the last at %.2f s (12 units: 3 s)" % (out_times[-1] - landed_at), steady)
	_check("in the order they went in", out_ids == crew.map(func(u): return u.unit_id))
	var placed := true
	for k in out_at.size():
		if out_at[k].distance_to(base.drop_spot(k, 12) + Vector3.UP * 0.2) > 0.05:
			placed = false
	_check("each put down on the ground next to the camp, on a spot of its own (not on the deck)", placed
			and out_at.all(func(p): return absf(p.y - 0.2) < 0.05) and _all_apart(out_at, 3.0))
	_check("back in the world, alive and visible", crew.all(func(u): return u.is_alive() and u.visible and not u.is_stowed()))
	_check("... in the groups the defenders look in", crew.all(func(u): return u.is_in_group("damageable") and u.is_in_group("attacker_units")))
	_check("... thinking again", crew.all(func(u): return u.process_mode != Node.PROCESS_MODE_DISABLED))
	_check("... standing there, theirs to order", crew.all(func(u): return u.order.type == "idle"))
	_check("the helicopter isn't kept: unhurt, it goes straight home", h.state == TransportHelo.State.SPOOL and not h.out_leg)
	var t_home := _run(200.0, _state(h, TransportHelo.State.PARKED))
	_check("it comes home (%.0f s)" % t_home, h.state == TransportHelo.State.PARKED)
	_check("... to the spot it left, the way it stood", h.global_position.distance_to(home) < 0.5)
	_check("... and is open for the next load", h.can_board() and h.cargo.is_empty())
	_check("it kept count: one trip, 12 units flown", h.stats.trips == 1 and h.stats.units_flown == 12)
	# A second trip with a rich load works the same way.
	var elephants: Array = []
	for i in 10:
		var e := _unit("elephant")
		if _board(h, e):
			elephants.append(e)
	_check("ten elephants make a full load", elephants.size() == 10 and h.spaces_free() == 0)
	_check("away again", h.dispatch(base))
	_run(200.0, _state(h, TransportHelo.State.UNLOAD))
	var n_start := _clock
	_run(30.0, func(): return h.cargo.is_empty())
	_check("ten elephants unload in 2.5 s", absf((_clock - n_start) - 2.5) < DT * 2.0, "(%.2f s)" % (_clock - n_start))


func _all_apart(points: Array, gap: float) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			if Vector2(points[i].x - points[j].x, points[i].z - points[j].z).length() < gap:
				return false
	return true


func _test_mending() -> void:
	print("a hurt helicopter stays till it is mended")
	var h := fleet.helo_at(0)
	for i in 3:
		_board(h, _unit("rifleman"))
	_check("away", h.dispatch(base))
	_run(200.0, _state(h, TransportHelo.State.UNLOAD))
	_check("landed at the outpost", h.state == TransportHelo.State.UNLOAD)
	h.take_damage(3000.0, GameConfig.TEAM_DEFENDER)
	_check("half its health gone", absf(h.health() - 0.5) < 0.01)
	_run(10.0, func(): return h.state != TransportHelo.State.UNLOAD)
	_check("unloaded, but hurt: it stays where it landed", h.state == TransportHelo.State.REPAIR and h.cargo.is_empty())
	var stayed := h.global_position
	var t0 := _clock
	_run(55.0)
	_check("55 s on, it is still there, still mending", h.state == TransportHelo.State.REPAIR and h.global_position == stayed and h.health() > 0.9)
	_run(30.0, func(): return h.state != TransportHelo.State.REPAIR)
	_check("recovered after about a minute (%.0f s) and takes off" % (_clock - t0), absf((_clock - t0) - 60.0) < 3.0 and h.state == TransportHelo.State.SPOOL)
	_check("mended in full", h.hp >= TransportHelo.MAX_HP - 0.01)
	_run(200.0, _state(h, TransportHelo.State.PARKED))
	_check("home again", h.state == TransportHelo.State.PARKED)
	# Hurt at the base it doesn't take off either.
	_board(h, _unit("rifleman"))
	h.hp = 1000.0
	_check("hurt at the base: it can load but can't go", h.can_board() and not h.can_dispatch(base) and not h.dispatch(base))
	_run(20.0)
	_check("still can't go 20 s on", not h.can_dispatch(base) and h.hp > 1000.0 and h.state == TransportHelo.State.PARKED)
	_run(100.0, func(): return h.hp >= TransportHelo.MAX_HP - 0.01)
	_check("mended, it can go again", h.can_dispatch(base))
	# A helicopter flying doesn't mend.
	_check("away", h.dispatch(base))
	_run(60.0, _state(h, TransportHelo.State.CRUISE))
	h.take_damage(500.0, GameConfig.TEAM_DEFENDER)
	var hp_air := h.hp
	_run(5.0)
	_check("in the air it doesn't mend", h.hp == hp_air)


func _test_outpost_rules() -> void:
	print("the outpost lost on the way: it brings them home")
	var h := fleet.helo_at(0)
	var home := h.global_position
	var aborted: Array = []
	h.trip_aborted.connect(func(_h, on_pad): aborted.append(on_pad))
	var crew: Array = []
	for i in 6:
		var u := _unit("rifleman")
		_board(h, u)
		crew.append(u)
	base.controlled = false
	_check("a helipad the attackers lost is no destination", not h.can_dispatch(base) and not h.dispatch(base)
			and not commander.helo_can_fly(0, 1) and commander.submit({"type": "helo_fly", "helo": 0, "spawn": 1}) == 0)
	_check("the load stays aboard", h.cargo.size() == 6 and h.state == TransportHelo.State.PARKED)
	base.controlled = true
	_check("held, it can go", commander.helo_can_fly(0, 1))
	_check("away", h.dispatch(base))
	_run(60.0, _state(h, TransportHelo.State.CRUISE))
	_run(4.0)
	var hp_before := h.hp
	var was := h.global_position
	var going := Vector2(OUTPOST_PAD.x - was.x, OUTPOST_PAD.z - was.z).normalized()
	base.controlled = false
	_run(DT * 1.5)
	_check("lost on the way: it turns back at once", not h.out_leg and h.state == TransportHelo.State.CLIMB and aborted == [false])
	_check("... unhurt", h.hp == hp_before)
	_check("... with everyone still aboard", h.cargo.size() == 6 and crew.all(func(u): return u.is_stowed()))
	_run(2.0)
	var on := Vector2(h.global_position.x - was.x, h.global_position.z - was.z)
	_check("... carrying on its way a moment as it brakes, not stopping dead", on.dot(going) > 20.0, "(%.1f m on)" % on.dot(going))
	_run(200.0, _state(h, TransportHelo.State.UNLOAD))
	_check("home, it sets down where it stood and lets them out", h.state == TransportHelo.State.UNLOAD and not h.out_leg
			and h.global_position.distance_to(home) < 0.5)
	_run(10.0, _state(h, TransportHelo.State.PARKED))
	_check("all 6 out by the main spawn point", h.cargo.is_empty() and crew.all(func(u): return u.is_alive()
			and Vector2(u.global_position.x - MAIN.x, u.global_position.z - MAIN.z).length() < 15.0))
	_check("none of them were put down at the outpost", h.unloaded_count == 0 and h.stats.units_returned == 6)
	_check("it stands at the base, open for the next load", h.state == TransportHelo.State.PARKED and h.can_board())
	# Lost while it is still spinning up at the base: it never leaves.
	for i in 2:
		_board(h, _unit("rifleman"))
	base.controlled = true
	_check("away again", h.dispatch(base))
	_run(2.0)
	base.controlled = false
	_run(DT * 1.5)
	_check("lost while it spins up: it never leaves, and they get out again", h.state == TransportHelo.State.UNLOAD
			and not h.out_leg and h.global_position.distance_to(home) < 0.5 and aborted.size() == 2)
	_run(5.0, _state(h, TransportHelo.State.PARKED))
	_check("... and it stands at the base again", h.state == TransportHelo.State.PARKED and h.cargo.is_empty())
	# Lost as it sets down on the pad.
	for i in 2:
		_board(h, _unit("rifleman"))
	base.controlled = true
	_check("away a third time", h.dispatch(base))
	_run(200.0, _state(h, TransportHelo.State.DESCEND))
	_run(2.0)
	base.controlled = false
	_run(DT * 1.5)
	_check("lost as it sets down: it climbs away with them", h.state == TransportHelo.State.CLIMB and h.cargo.size() == 2
			and aborted == [false, false, false])
	_run(30.0, _state(h, TransportHelo.State.CRUISE))
	_check("... back up to an ordinary cruising height (not 55 m over where it was)",
			absf(h.global_position.y - TransportHelo.cruise_altitude(Vector3(h.global_position.x, 0.0, h.global_position.z), h.home_position)) < 0.1,
			"(%.0f m)" % h.global_position.y)
	_run(300.0, _state(h, TransportHelo.State.PARKED))
	_check("... home, they are out", h.cargo.is_empty() and h.global_position.distance_to(home) < 0.5)


func _test_caught_on_pad() -> void:
	print("caught on the pad as the outpost falls")
	var h := fleet.helo_at(0)
	var home := h.global_position
	var aborted: Array = []
	h.trip_aborted.connect(func(_h, on_pad): aborted.append(on_pad))
	var crew: Array = []
	for i in 12:
		var u := _unit("rifleman")
		_board(h, u)
		crew.append(u)
	_check("away", h.dispatch(base))
	_run(200.0, _state(h, TransportHelo.State.UNLOAD))
	_run(10.0, func(): return h.unloaded_count >= 4)
	_check("4 of the 12 put down by the outpost", h.unloaded_count == 4 and h.cargo.size() == 8)
	var pad_y := h.global_position.y
	base.controlled = false
	_run(DT * 1.5)
	_check("the outpost falls as it unloads: it loses a fifth of its health", absf(h.hp - TransportHelo.MAX_HP * 0.8) < 0.01,
			"(hp %.0f)" % h.hp)
	_check("... and lifts off at once, no spinning up first", h.state == TransportHelo.State.CLIMB and h.global_position.y > pad_y
			and aborted == [true])
	_check("... with the other 8 still aboard", h.cargo.size() == 8 and h.unloaded_count == 4)
	_run(300.0, _state(h, TransportHelo.State.PARKED))
	_check("it brings them home and lets them out there", h.state == TransportHelo.State.PARKED and h.cargo.is_empty()
			and h.stats.units_returned == 8 and h.global_position.distance_to(home) < 0.5)
	_check("the 4 put down at the outpost are still there", crew.slice(0, 4).all(func(u): return u.is_alive()
			and Vector2(u.global_position.x - OUTPOST_DROP.x, u.global_position.z - OUTPOST_DROP.z).length() < 15.0))
	_check("the 8 brought back are by the main spawn point", crew.slice(4).all(func(u): return u.is_alive()
			and Vector2(u.global_position.x - MAIN.x, u.global_position.z - MAIN.z).length() < 15.0))
	_check("hurt, it mends at the base", h.hp > TransportHelo.MAX_HP * 0.8 and not h.can_dispatch(base))
	# Too hurt to take the hit: it is destroyed on the pad with what is still aboard.
	_run(200.0, func(): return h.hp >= TransportHelo.MAX_HP - 0.01)
	base.controlled = true
	for i in 10:
		_board(h, _unit("rifleman"))
	_check("mended and loaded, away", h.dispatch(base))
	_run(200.0, _state(h, TransportHelo.State.UNLOAD))
	_run(10.0, func(): return h.unloaded_count >= 3)
	var died := [0]
	commander.unit_died.connect(func(_u): died[0] += 1)
	h.hp = TransportHelo.MAX_HP * 0.15
	base.controlled = false
	_run(DT * 1.5)
	_check("at 15 percent a fifth is too much: destroyed on the pad", not h.is_alive() and fleet.helo_at(0) == null)
	_check("... with the 7 still aboard", died[0] == 7)
	_check("... and the outpost is lost all the same", not base.controlled)
	_check("... it burns where it stood, on the deck", absf(h.global_position.y - pad_y) < 0.01)
	_check("... and a new one is 500 s away", fleet.replace_in[0] > HeloCargo.REPLACE_TIME - 1.0)
	# Caught while it mends on the pad (it had unloaded hurt): the same.
	var h2 := fleet.helo_at(1)
	base.controlled = true
	for i in 2:
		_board(h2, _unit("rifleman"))
	_check("the other one away", h2.dispatch(base))
	_run(200.0, _state(h2, TransportHelo.State.UNLOAD))
	h2.take_damage(2400.0, GameConfig.TEAM_DEFENDER)
	_run(5.0, _state(h2, TransportHelo.State.REPAIR))
	_check("hurt, it stays on the pad mending", h2.state == TransportHelo.State.REPAIR and h2.cargo.is_empty())
	var before := h2.hp
	base.controlled = false
	_run(DT * 1.5)
	_check("caught mending: a fifth off and away", absf(h2.hp - (before - TransportHelo.MAX_HP * 0.2)) < 0.01
			and h2.state == TransportHelo.State.CLIMB)


func _test_damage_looks() -> void:
	print("how its hurt shows")
	var h := fleet.helo_at(0)
	var names := ["nothing", "grey smoke", "black smoke", "fire"]
	for pair in [[1.0, 0], [0.61, 0], [0.6, 1], [0.41, 1], [0.4, 2], [0.11, 2], [0.1, 3], [0.01, 3]]:
		h.hp = TransportHelo.MAX_HP * float(pair[0])
		_check("at %d percent: %s" % [roundi(float(pair[0]) * 100.0), names[pair[1]]], h.damage_stage() == pair[1],
				"(stage %d)" % h.damage_stage())
	h.hp = TransportHelo.MAX_HP * 0.05
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the fire lights it up", h._fire_light.visible)
	h.hp = TransportHelo.MAX_HP
	await get_tree().process_frame
	await get_tree().process_frame
	_check("mended: no fire, no smoke", not h._fire_light.visible and h.damage_stage() == 0)
	h.hp = TransportHelo.MAX_HP * 0.05
	h.take_damage(1.0e9, GameConfig.TEAM_DEFENDER)
	_check("a wreck shows no engine fire of its own (the wreck burns instead)", h.damage_stage() == 0 and not h._fire_light.visible)


func _test_real_pad() -> void:
	print("a real helipad: its pad and the ground beside it")
	for scale in [1.0, JungleLayout.OUTPOST_SCALE]:
		var b := AttackerBase.new()
		b.setup("east", "Outpost")
		b.scale_factor = scale
		b.position = Vector3(700.0, 0.0, -400.0)
		b.spawn_point = b.position + Vector3(-(b.deck_size.x * 0.5 + AttackerBase.SPAWN_OUT), 0.0, 0.0)
		add_child(b)
		_check("it lands on the pad's middle, on the deck (size %.1f)" % scale,
				b.landing_point().is_equal_approx(b.pad_centre()) and absf(b.landing_point().y - b.deck_height) < 0.01)
		_check("... its nose along the pad, as the vehicle showcase's pad check stands it", absf(angle_difference(b.landing_yaw(), PI * 0.5)) < 0.001)
		var spots := []
		for k in 50:
			spots.append(b.drop_spot(k, 50))
		_check("50 units put down on the ground next to the camp: none on or under the deck",
				spots.all(func(p): return b.edge_distance(p) >= AttackerBase.SPAWN_OUT - 0.01 and absf(p.y) < 0.01))
		_check("... close by (within 30 m of the deck), on the spawn point's side",
				spots.all(func(p): return b.edge_distance(p) < 30.0 and p.x < b.position.x))
		_check("... each on a spot of its own", _all_apart(spots, 3.0))
		b.queue_free()
	await get_tree().physics_frame


func _test_destroyed() -> void:
	print("shot down")
	var h := fleet.helo_at(0)
	var other := fleet.helo_at(1)
	var lost := [0]
	var died := [0]
	var signals := [0]
	h.destroyed.connect(func(_h): signals[0] += 1)
	commander.unit_died.connect(func(_u): died[0] += 1)
	fleet.helo_lost.connect(func(_h): lost[0] += 1)
	h.take_damage(1000.0, GameConfig.TEAM_ATTACKER)
	_check("its own side can't hurt it", h.hp == TransportHelo.MAX_HP)
	h.take_damage(1000.0, GameConfig.TEAM_DEFENDER)
	_check("the defenders can", h.hp == TransportHelo.MAX_HP - 1000.0 and h.is_alive())
	var crew: Array = []
	for i in 7:
		var u := _unit("rifleman")
		_board(h, u)
		crew.append(u)
	var walking := _unit("rifleman")
	_check("one more is on its way to board", h.reserve(walking))
	walking.set_order({"type": "helo", "helo": h, "pos": h.ramp_point()})
	var crew_ids := crew.map(func(u): return u.unit_id)
	h.hp = 10.0
	h.take_damage(25.0, GameConfig.TEAM_DEFENDER)
	_check("destroyed", not h.is_alive() and h.hp == 0.0 and signals[0] == 1)
	_check("everything aboard is lost with it: all 7", died[0] == 7 and crew_ids.all(func(id): return not commander.units.has(id)))
	_check("the one still walking is not", walking.is_alive() and commander.units.has(walking.unit_id))
	_check("the fleet knows: slot empty, a new one in 500 s", fleet.helo_at(0) == null and lost[0] == 1 and is_equal_approx(fleet.replace_in[0], 500.0))
	_check("it is no target any more", not h.is_in_group("damageable") and not h.is_in_group("transport_helos") and h.collision_layer == 0)
	h.take_damage(100.0, GameConfig.TEAM_DEFENDER)
	_check("a wreck is destroyed once", signals[0] == 1 and lost[0] == 1)
	_check("the other helicopter flies on", fleet.helo_at(1) == other and other.is_alive())
	_check("the walker can't board a wreck", not h.accepts(walking))
	# Shot down in the air with a load.
	var h2 := fleet.helo_at(1)
	for i in 4:
		_board(h2, _unit("rifleman"))
	h2.dispatch(base)
	_run(80.0, _state(h2, TransportHelo.State.CRUISE))
	var before := died[0]
	h2.take_damage(1.0e9, GameConfig.TEAM_DEFENDER)
	_check("in the air the same: 4 more lost", died[0] == before + 4 and not h2.is_alive())
	_check("both slots are empty and counting down", fleet.alive_count() == 0 and fleet.replace_in[1] > 499.0)


func _test_replacement() -> void:
	print("a new helicopter 500 s later")
	var h := fleet.helo_at(0)
	var spot := h.global_position
	h.take_damage(1.0e9, GameConfig.TEAM_DEFENDER)
	_check("slot empty", fleet.helo_at(0) == null)
	_run(250.0)
	_check("250 s on: still empty, 250 s to go", fleet.helo_at(0) == null and absf(fleet.replace_in[0] - 250.0) < 1.0)
	_run(249.0)
	_check("499 s: still empty", fleet.helo_at(0) == null)
	_run(2.0)
	var fresh := fleet.helo_at(0)
	_check("500 s: a new one", fresh != null and fresh != h and fresh.is_alive())
	_check("... standing where the first did, whole, empty and open", fresh != null and fresh.global_position.distance_to(spot) < 0.5
			and fresh.hp == TransportHelo.MAX_HP and fresh.can_board() and fresh.cargo.is_empty())
	_check("... and the clock is off", is_equal_approx(fleet.replace_in[0], 0.0))
	_check("the other one was never touched", fleet.helo_at(1) != null and fleet.helo_at(1).hp == TransportHelo.MAX_HP)


func _test_who_can_hurt_it() -> void:
	print("who can hurt it")
	var h := fleet.helo_at(0)
	var at := h.global_position
	# Rounds and blasts the player aims land.
	var shot := Combat.fire_hitscan(self, at + Vector3(-120.0, 7.0, 0.0), at + Vector3(0.0, 7.0, 0.0), 0.0, 100.0, GameConfig.TEAM_DEFENDER)
	_check("a round at its body hits it", shot.hit and absf(h.hp - (TransportHelo.MAX_HP - 100.0)) < 0.01, "(hp %.0f)" % h.hp)
	h.hp = TransportHelo.MAX_HP
	var low := Combat.fire_hitscan(self, at + Vector3(-120.0, 1.2, 0.0), at + Vector3(0.0, 1.2, 0.0), 0.0, 100.0, GameConfig.TEAM_DEFENDER)
	_check("a round at a man on the ground beside it passes under its body", not low.hit and h.hp == TransportHelo.MAX_HP)
	var own := Combat.fire_hitscan(self, at + Vector3(-120.0, 7.0, 0.0), at + Vector3(0.0, 7.0, 0.0), 0.0, 100.0, GameConfig.TEAM_ATTACKER)
	_check("its own side's rounds don't hurt it", h.hp == TransportHelo.MAX_HP and not own.hit)
	Combat.damage_area(self, h.get_aim_point(), 10.0, 100.0, GameConfig.TEAM_DEFENDER)
	_check("a blast on it hurts it in full", absf(h.hp - (TransportHelo.MAX_HP - 100.0)) < 0.01)
	h.hp = TransportHelo.MAX_HP
	Combat.damage_area(self, h.get_aim_point() + Vector3(20.0, 0.0, 0.0), 10.0, 100.0, GameConfig.TEAM_DEFENDER)
	var lost := TransportHelo.MAX_HP - h.hp
	_check("... and one 20 m off hurts it less (its body is big): %.0f" % lost, lost > 25.0 and lost < 60.0)
	h.hp = TransportHelo.MAX_HP
	# Nothing idle ever picks it out.
	var turret := AATurret.new()
	add_child(turret)
	turret.global_position = at + Vector3(30.0, 0.0, 0.0)
	var decoy := FakeAir.new()
	add_child(decoy)
	decoy.global_position = at + Vector3(30.0, 12.0, 20.0)
	await get_tree().physics_frame
	_check("the AA turret looks at flyers (it finds the decoy)", turret._find() == decoy)
	decoy.queue_free()
	await get_tree().physics_frame
	_check("... but never picks the helicopter out, in range and in sight", turret._find() == null)
	turret.queue_free()
	var lookups := get_tree().get_nodes_in_group("air_units")
	_check("it is not in air_units (what idle AA squads, the turrets and the drones' counters read)", not lookups.has(h))
	_check("it is not in attacker_units (what idle posts, squads, the tank, the jet and the drones read)",
			not get_tree().get_nodes_in_group("attacker_units").has(h))
	_check("the player's own AA lock-on does list it", Combat.aircraft_for_player(self).has(h))
	_check("... and the list the idle ones use does not", not Combat.aircraft_for_player(self).is_empty() and not lookups.has(h))


# ---------------------------------------------------------------- the demo

## Watch it: ferry units to the stand-in outpost over and over, the camera on the first helicopter.
func _demo() -> void:
	_demo_cam = Camera3D.new()
	_demo_cam.far = 4000.0
	add_child(_demo_cam)
	_demo_cam.current = true
	# The stand-in outpost: a deck 22 m up with the pad on it; its units are put down on the ground beside it.
	add_child(Mats.box_mesh(Vector3(80.0, OUTPOST_PAD.y, 70.0), Vector3(OUTPOST_PAD.x, OUTPOST_PAD.y * 0.5, OUTPOST_PAD.z),
			Mats.flat(Color(0.45, 0.45, 0.48))))
	# The other helicopter starts badly hurt: on fire, then black smoke, then grey, as it mends at the base.
	var hurt := fleet.helo_at(1)
	if hurt:
		hurt.hp = hurt.max_hp * 0.08
	while true:
		var h := fleet.helo_at(0)
		if h != null and h.state == TransportHelo.State.PARKED and h.cargo.is_empty() and h.hp >= h.max_hp - 0.01:
			# The last load is done with (the army can't grow past its 60).
			for old in commander.units.values():
				if is_instance_valid(old) and not old.is_stowed():
					commander.units.erase(old.unit_id)
					old.queue_free()
			for t in ["rifleman", "rifleman", "elephant", "rhino", "kangaroo", "medic", "giraffe", "rifleman"]:
				var u := _unit(t, h.ramp_point())
				h.reserve(u)
				u.set_order({"type": "helo", "helo": h, "pos": h.ramp_point()})
			await get_tree().create_timer(3.0).timeout
			commander.submit({"type": "helo_fly", "helo": 0, "spawn": 1})
		await get_tree().create_timer(1.0).timeout


func _process(_delta: float) -> void:
	if _demo_cam == null or fleet == null:
		return
	var h := fleet.helo_at(0)
	if h == null:
		return
	var eye := h.global_position + Vector3(70.0, 45.0, 90.0)
	_demo_cam.global_position = _demo_cam.global_position.lerp(eye, 0.05)
	_demo_cam.look_at(h.global_position + Vector3(0.0, 10.0, 0.0))
