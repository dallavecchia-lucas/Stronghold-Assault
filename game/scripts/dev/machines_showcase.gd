extends Node3D
## The defenders' two machines on the real map (the Jungle Keep): the Fighter Jet (DefenderJet) and the Hover Tank
## (DefenderTank), bought, taken over and played the way a player does: their own chase cameras and panels, this node
## working the keys and the mouse as their pilot (DefenderMachine.pilot).
##
##   buy        J buys the Fighter Jet, H the Hover Tank: on the roster (F1, F2), their prices out of the credits
##   cruise     the jet in the air in its chase camera: Shift, the boost (afterburners, the field of view widens, the
##              speed climbs and the boost runs down, then comes back)
##   bomb       a bombing run on a knot of attackers in the clearing: the ring and arc of the bomb preview on the ground
##              follow the jet as it flies, the bomb is let go when the preview is on them; checked: the bomb lands where
##              the preview said, and kills what it falls on
##   salvo      the missile barrage twice: flying straight, the whole salvo leaves along one line (a tight cluster);
##              through a hard turn each missile leaves along where the nose is then, and they scatter
##   crash      the jet flown into the ground: lost for good (the roster loses it); another is shot down
##   idle       the jet left alone: it circles the spot where it was left, gunship style, and stays passive; an elephant just
##              out of reach is ignored; when one locks on to it it bombs it (setup, run, the bomb where the forecast says,
##              breaks away), flies back to where it was left and circles again until the next one attacks
##   drive      the tank driven off, turning onto the way it goes, stopped by the mountain's wall
##   guns       the main gun on a knot of attackers (the shell, the blast, the recoil), the machine guns after it
##   idle       the player leaves the tank (takes the jet): it holds its ground and shoots what comes in reach
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/machines_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
##       res://scenes/dev/machines_showcase.tscn -- --snap=12,24 --snap-out=/tmp/machines/shot
##
## --test prints each check and the result (MACHINES SHOWCASE PASS / FAIL). --snap=t1,t2,.. --snap-out=prefix draws and
## saves only the frames at those times (seconds of the run); the run prints the time of each step (`MACHINES t=...`).
## The garrison's posts and the AA turrets hold fire; the attackers staged as targets stand where they are.

const JET_START := Vector3(140.0, 112.0, -700.0)
## The knot of attackers the bombing run goes for, and the tank's.
const BOMB_TARGET := Vector3(140.0, 0.0, 170.0)
const TANK_AT := Vector3(0.0, 0.0, 128.0)
const TANK_TARGET := Vector3(-6.0, 0.0, 196.0)

var level: JungleLevel
var commander: AttackerCommander
var defender: DefenderController
var armory: DefenderArmory
var jet: DefenderJet
var tank: DefenderTank
var cam: Camera3D
var t := -1.0
var test := false
var _snaps: Array = []
var _snap_out := "/tmp/machines/shot"
var _snapping := false
var _checks: Array[String] = []
var _failed := false
## The pilot's hands (pilot_input): the jet's steering and triggers, the tank's keys.
var _steer = null  # Vector2 (heading, pitch) to hold, or null
var _steer_to = null  # Vector3 to steer toward, or null
var _boost := false
var _brake := false
var _bomb := false
var _missiles := false
var _drop_on = null  # Vector3: let a bomb go when the preview is on it
var _move := Vector2.ZERO
var _fire := false
var _mgs := false
var _look = null
var _caption: Label
var _targets: Array = []
## A spectator's camera for the stills (the HUD hidden): fixed at `_spec_at`, or riding with the jet at `_spec_rel`.
var _spec := false
var _spec_at := Vector3.ZERO
var _spec_rel = null
var _spec_look := Vector3.ZERO
var _orbit_ring: MeshInstance3D
## What the riding spectator follows: this node, else the jet.
var _spec_node: Node3D = null
## A tag on the jet in the overview, where it is a few pixels (the showcase's overlay, like the circle).
var _jet_tag: Label
## --only=jet|tank|idle: just that machine's part of the run (idle: just the jet left alone).
var _only := ""


func _ready() -> void:
	seed(11)
	test = "--test" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			_only = arg.get_slice("=", 1)
	if not _snaps.is_empty():
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
		# Stills on a machine with no GPU (software GL): a lighter picture, or each takes minutes.
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	GameConfig.map = "jungle"
	GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
	level = JungleLevel.new()
	level.name = "Level"
	add_child(level)
	level.build()
	# Staged: the Gunner Squad sits this one out, the posts and the AA turrets hold fire.
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
	for s in level.stations + level.aa_turrets:
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	cam = Camera3D.new()
	cam.far = 5000.0
	add_child(cam)
	cam.current = true
	_plain_sky()
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


## The game's own sky is a shader the compatibility renderer on a software GL driver (Mesa's llvmpipe, a machine with
## no GPU) can't compile, which leaves a blank white sky in the stills: there, a plain procedural sky in its place.
func _plain_sky() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.46, 0.74)
	sky_mat.sky_horizon_color = Color(0.74, 0.8, 0.86)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	for we in level.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env:
			env.background_mode = Environment.BG_SKY
			env.sky = sky


func _start() -> void:
	for k in 6:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	armory = DefenderArmory.new()
	armory.level = level
	armory.credits = float(DefenderArmory.JET_COST + DefenderArmory.TANK_COST) + 30.0
	armory.income = 0.0
	add_child(armory)
	defender = DefenderController.new()
	defender.level = level
	defender.armory = armory
	add_child(defender)
	t = 0.0
	await _run()


# ---------------------------------------------------------------- the run

func _run() -> void:
	await _buy()
	if _only in ["", "jet"]:
		await _jet_cruise()
		await _jet_bomb()
		await _jet_salvos()
		await _jet_down()
	if _only in ["", "jet", "idle"]:
		await _jet_idle()
	if _only in ["", "tank"]:
		await _tank_drive()
		await _tank_guns()
		await _tank_idle()
	_finish()


func _buy() -> void:
	_say("Buying: J the Fighter Jet, H the Hover Tank", 3.0)
	var before := armory.credits
	jet = defender.buy_squad("jet") as DefenderJet
	tank = defender.buy_squad("tank") as DefenderTank
	_check(jet != null and tank != null and armory.squads == [jet, tank], "buy: J and H put a Fighter Jet and a Hover Tank on the roster")
	_check(is_equal_approx(before - armory.credits, float(DefenderArmory.JET_COST + DefenderArmory.TANK_COST)),
			"buy: they cost %d and %d credits" % [DefenderArmory.JET_COST, DefenderArmory.TANK_COST])
	jet.pilot = self
	tank.pilot = self
	_check(jet.is_alive() and jet.altitude() > 80.0 and absf(jet.speed - DefenderJet.CRUISE) < 1.0,
			"jet: scrambled at height, already at cruising speed (%.0f m/s, %.0f m up)" % [jet.speed, jet.altitude()])
	_check(is_equal_approx(tank.global_position.y, 0.0) or tank.global_position.y > -2.0, "tank: deployed on the ground outside its gate")
	await _wait(0.5)
	defender.select_squad(0, true)
	await _wait(2.5)
	_check(jet.possessed and jet.get_camera().current, "jet: F1 takes command, its chase camera comes up")


func _jet_cruise() -> void:
	jet.stage(Vector3(-60.0, 140.0, 520.0), PI, 0.0, DefenderJet.CRUISE)  # over the south field, heading north
	_steer = Vector2(PI, 0.0)
	await _wait(1.5)
	_say("Fighter Jet: mouse steers, Shift boosts the afterburners", 4.0)
	_check(absf(jet.speed - DefenderJet.CRUISE) < 6.0, "cruise: holds %.0f m/s" % DefenderJet.CRUISE)
	var fov0 := jet.get_camera().fov
	_boost = true
	await _wait(2.5)
	var boosted := jet.speed
	var fov1 := jet.get_camera().fov
	var boost_left := jet.boost
	_check(boosted > DefenderJet.CRUISE + 50.0 and jet.boosting, "boost: the afterburners take it to %.0f m/s" % boosted)
	_check(fov1 > fov0 + 6.0, "boost: the camera pulls back and the field of view widens (%.0f to %.0f)" % [fov0, fov1])
	_check(boost_left < 0.5, "boost: it runs down (%.0f%% left after 2.5 s)" % (boost_left * 100.0))
	_boost = false
	await _wait(5.0)
	_check(jet.boost > boost_left + 0.3, "boost: it comes back once let go (%.0f%%)" % (jet.boost * 100.0))
	# A hard turn to the right and back: banks into it.
	_steer = Vector2(PI - 1.4, 0.0)
	await _wait(0.6)
	var banked := jet.bank
	await _wait(1.0)
	_check(banked > deg_to_rad(40.0), "turn: banks into it (%.0f°, right wing down)" % rad_to_deg(banked))
	_steer = null
	_steer_to = null


func _jet_bomb() -> void:
	_targets = _spawn_group(["rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "breacher"], BOMB_TARGET, 5.0)
	# Down to the start of its run, slowed to bomb: level, 110 m up, 85 m/s.
	jet.stage(JET_START, 0.0, 0.0, DefenderJet.MIN_SPEED)
	_steer = Vector2(0.0, 0.0)
	_brake = true
	await _wait(0.8)
	_say("Bomb: the ring on the ground is where it will land: it follows the jet", 6.0)
	_check(jet._ring_mi.visible and not jet.bomb_forecast.is_empty(), "bomb: the preview is drawn on the ground while the jet is flown")
	var f0: Vector3 = jet.bomb_forecast.impact
	await _wait(1.0)
	var f1: Vector3 = jet.bomb_forecast.impact
	_check(f1.distance_to(f0) > 25.0 and f1.z > f0.z, "bomb: the preview follows the jet as it flies (moved %.0f m in a second)" % f1.distance_to(f0))
	print("MACHINES t=%.1f bomb preview over the clearing, the knot of attackers ahead" % t)
	var ahead: bool = jet.bomb_forecast.impact.z < BOMB_TARGET.z
	_check(ahead, "bomb: the forecast lands short of the target to begin with (z %.0f against %.0f): it falls far ahead of the jet" % [jet.bomb_forecast.impact.z, BOMB_TARGET.z])
	var hp0 := _hp_of(_targets)
	_drop_on = BOMB_TARGET
	await _until(func(): return jet.stats.bombs >= 1, 12.0)
	print("MACHINES t=%.1f bomb away" % t)
	_drop_on = null
	# For the stills: the knot from the side, as the jet comes in over it and the bomb lands.
	await _wait(2.4)
	_spectate(BOMB_TARGET + Vector3(-80.0, 16.0, -50.0), BOMB_TARGET + Vector3(0.0, 8.0, -10.0))
	_check(jet.stats.bombs == 1 and jet.bombs == DefenderJet.BOMBS - 1, "bomb: LMB lets one go from the bay (%d of %d left)" % [jet.bombs, DefenderJet.BOMBS])
	await _until(func(): return not jet.bomb_bursts.is_empty(), 10.0)
	print("MACHINES t=%.1f bomb burst" % t)
	await _wait(1.6)
	_spectate_off()
	if not jet.bomb_bursts.is_empty():
		var off := jet.bomb_bursts[0].distance_to(jet.last_drop_forecast.impact)
		_check(off < 4.0, "bomb: it lands where the preview said (%.1f m off)" % off)
		_check(jet.bomb_bursts[0].distance_to(BOMB_TARGET) < 14.0, "bomb: and on the target (%.1f m from it)" % jet.bomb_bursts[0].distance_to(BOMB_TARGET))
	_check(_alive_count(_targets) < _targets.size() and _hp_of(_targets) < hp0 * 0.5, "bomb: it kills what it falls on (%d of %d standing)" % [_alive_count(_targets), _targets.size()])
	# On the next pass (it has flown out over the south edge): level, east along the north side, while the bay refills.
	_brake = false
	jet.stage(Vector3(-400.0, 140.0, -250.0), PI * 0.5, 0.0, DefenderJet.CRUISE)
	_steer = Vector2(PI * 0.5, 0.0)
	await _wait(1.0)
	# The bay refills: one bomb back after BOMB_RECHARGE.
	var gone := jet.bombs
	await _wait(DefenderJet.BOMB_RECHARGE + 0.5)
	_check(jet.is_alive(), "bomb: the jet flies on")
	_check(jet.bombs == gone + 1 or jet.bombs == DefenderJet.BOMBS, "bomb: one comes back every %.0f s" % DefenderJet.BOMB_RECHARGE)


func _jet_salvos() -> void:
	# 1: flying straight and level, nose down a little onto the clearing.
	jet.stage(Vector3(-210.0, 100.0, -420.0), 0.0, deg_to_rad(-10.0), DefenderJet.CRUISE)
	_steer = Vector2(0.0, deg_to_rad(-10.0))
	await _wait(1.3)
	_say("Missile barrage: flying straight, the missiles all go the same way", 5.0)
	var n0 := jet.missile_aims.size()
	_spectate(Vector3.ZERO, Vector3.ZERO, Vector3(10.0, 7.0, -42.0), Vector3(0.0, -4.0, 120.0))
	_missiles = true
	await _wait(0.1)
	await _until(func(): return jet.salvo_left == 0, 4.0)
	print("MACHINES t=%.1f straight salvo away" % t)
	var straight := _aim_spread(jet.missile_aims.slice(n0))
	_check(jet.stats.missiles == DefenderJet.SALVO, "salvo: RMB sends %d missiles" % DefenderJet.SALVO)
	_check(straight < 0.05, "salvo: held straight they all leave along one line (%.1f° apart at the most)" % rad_to_deg(straight))
	# Climb away from the ground while they fly.
	_steer = Vector2(0.0, deg_to_rad(25.0))
	await _wait(3.0)
	_spectate_off()
	await _wait(2.0)
	_check(jet.is_alive(), "salvo: the jet flies on")
	var straight_bursts := jet.missile_bursts.duplicate()
	# The reload.
	_check(jet.salvo_cd > 3.0, "salvo: the pylons reload for %.0f s" % DefenderJet.SALVO_RELOAD)
	# 2: through a hard turn.
	jet.stage(Vector3(-210.0, 100.0, -420.0), 0.0, deg_to_rad(-10.0), DefenderJet.CRUISE)
	jet.salvo_cd = 0.0
	_steer = Vector2(0.0, deg_to_rad(-10.0))
	await _wait(1.0)
	_say("...manoeuvring through the salvo, they scatter over where the nose swept", 5.0)
	var n1 := jet.missile_aims.size()
	_steer = Vector2(0.0 + deg_to_rad(75.0), deg_to_rad(-10.0))  # hard left
	await _wait(0.25)
	_spectate(Vector3.ZERO, Vector3.ZERO, Vector3(-45.0, 55.0, -75.0), Vector3(30.0, -40.0, 70.0))
	_missiles = true
	await _wait(0.1)
	print("MACHINES t=%.1f turning salvo away" % t)
	_steer = Vector2(deg_to_rad(75.0), deg_to_rad(20.0))
	await _until(func(): return jet.salvo_left == 0, 4.0)
	var scattered := _aim_spread(jet.missile_aims.slice(n1))
	await _wait(2.0)
	_spectate_off()
	_check(scattered > 0.35, "salvo: through a turn they scatter (%.0f° between the first and the last)" % rad_to_deg(scattered))
	_check(scattered > straight * 8.0, "salvo: far wider than flying straight (%.0f° against %.1f°)" % [rad_to_deg(scattered), rad_to_deg(straight)])
	await _wait(5.0)
	_check(jet.is_alive() and straight_bursts.size() >= 10 and jet.missile_bursts.size() >= 10, "salvo: the missiles burst (%d in the air or on the ground)" % jet.missile_bursts.size())
	_steer = null
	_steer_to = null
	_aim_free()


func _jet_down() -> void:
	# Flown into the ground: lost for good.
	jet.stage(Vector3(-210.0, 90.0, -300.0), 0.0, deg_to_rad(-35.0), DefenderJet.CRUISE)
	_steer = Vector2(0.0, deg_to_rad(-35.0))
	_say("Crash into the ground and you lose the jet", 4.0)
	var roster := armory.squads.size()
	await _until(func(): return jet.crashed_at != Vector3.INF, 6.0)
	print("MACHINES t=%.1f the jet hits the ground" % t)
	_check(jet.crashed_at != Vector3.INF and not jet.is_alive(), "crash: into the ground it blows up (at %.0f m up)" % jet.crashed_at.y)
	await _wait(1.8)
	print("MACHINES t=%.1f the wreck" % t)
	await _wait(2.2)
	_check(armory.squads.size() == roster - 1 and armory.squads == [tank], "crash: and it is gone for good: off the roster")
	_check(defender.current == null, "crash: the player is back at the overview and picks another post")
	_steer = null
	_steer_to = null
	# A second jet, shot down.
	armory.credits += DefenderArmory.JET_COST
	var j2 := defender.buy_squad("jet") as DefenderJet
	j2.pilot = self
	j2.stage(Vector3(-120.0, 150.0, 300.0), PI, 0.0, DefenderJet.CRUISE)
	defender.select_squad(armory.squads.find(j2), true)
	await _wait(1.0)
	jet = j2
	jet.take_damage(10000.0, GameConfig.TEAM_ATTACKER)
	_check(not jet.is_alive(), "shot down: a jet with no health left is lost")
	await _until(func(): return jet.crashed_at != Vector3.INF, 8.0)
	await _wait(3.8)
	_check(armory.squads == [tank], "shot down: it falls out of the sky, crashes and leaves the roster")
	# The attackers' AA fires on a jet flying low over a War Elephant.
	var e: AttackerUnit = _spawn("elephant", Vector3(0.0, 0.0, 215.0))
	armory.credits += DefenderArmory.JET_COST
	var j3 := defender.buy_squad("jet") as DefenderJet
	j3.pilot = self
	j3.stage(Vector3(0.0, 24.0, 238.0), PI, 0.0, DefenderJet.CRUISE)
	jet = j3
	_steer = Vector2(PI, 0.0)
	await _wait(0.2)
	e._aa_tick()  # its passive, as it runs every fire interval
	var locked: bool = e._aa_lock == jet
	await _wait(1.0)
	_check(locked, "attackers: a War Elephant takes a jet flying low over it for an enemy flyer and locks on (%.0f of %.0f health left)" % [jet.hp, DefenderJet.HP])
	_steer = null
	jet.take_damage(10000.0, GameConfig.TEAM_ATTACKER)
	await _wait(8.0)
	# The field cleared for what comes next.
	_retire([e])
	_retire(_targets)
	_targets = []


func _jet_idle() -> void:
	# A jet of its own, left alone over the clearing: where it was left is the east point of a circle round the Keep.
	armory.credits += DefenderArmory.JET_COST
	var j := defender.buy_squad("jet") as DefenderJet
	jet = j
	var left_at := Vector3(230.0, 150.0, 0.0)
	j.stage(left_at, PI, 0.0, DefenderJet.IDLE_SPEED)  # heading north: the circle's centre is to its west
	# The player is in the tank meanwhile (its panel shows the jet's roster slot).
	defender.select_squad(armory.squads.find(tank), true)
	await _wait(0.5)
	_say("Left alone, the jet circles where it was left, passive, like a gunship", 6.0)
	_check(not j.possessed and j.idle_state == DefenderJet.Idle.ORBIT and j.order_name() == "ORBIT", "idle: left alone it goes into orbit (roster: %s)" % j.order_name())
	_check(j.orbit_centre.distance_to(Vector3.ZERO) < 5.0 and absf(j.orbit_point().distance_to(Vector3(left_at.x, 0.0, left_at.z))) < 5.0,
			"idle: the circle goes through the spot where it was left (centre %s)" % j.orbit_centre)
	# Round the circle: its radius and height, over a lap.
	var worst_r := 0.0
	var low := INF
	var high := 0.0
	var turned := 0.0
	var last_h := j.heading
	var t_end := t + 14.0
	var shot := 0
	_overview(true)  # the whole circle, from over the south field
	while t < t_end:
		await get_tree().physics_frame
		if shot == 0 and t > t_end - 7.0:
			shot = 1
			_spectate(Vector3.ZERO, Vector3.ZERO, Vector3(-60.0, 16.0, -40.0), Vector3(8.0, -6.0, 10.0))  # beside it, banked in the turn
		var r := Vector2(j.global_position.x, j.global_position.z).length()
		worst_r = maxf(worst_r, absf(r - DefenderJet.IDLE_RADIUS))
		low = minf(low, j.altitude())
		high = maxf(high, j.altitude())
		turned += absf(angle_difference(last_h, j.heading))
		last_h = j.heading
	print("MACHINES t=%.1f jet orbiting" % t)
	_check(j.is_alive() and worst_r < 30.0, "idle: it flies the circle (%.0f m round, at most %.0f m off)" % [DefenderJet.IDLE_RADIUS, worst_r])
	_check(low > 100.0 and high < 175.0, "idle: at a steady height (%.0f to %.0f m over the ground)" % [low, high])
	_check(turned > TAU * 0.9, "idle: it goes right round (%.0f° of turn in 14 s)" % rad_to_deg(turned))
	_check(j.stats.bombs == 0 and j.stats.missiles == 0 and j.hp == DefenderJet.HP, "idle: and fires on nothing")
	# An enemy that has not attacked it, 60 m outside the path: ignored.
	var e := _spawn("elephant", Vector3(0.0, 0.0, -300.0))
	e.hp = 150.0
	var riflemen := _spawn_group(["rifleman", "rifleman", "rifleman"], Vector3(60.0, 0.0, 100.0), 6.0)
	_spectate_off()
	await _wait(12.0)
	_check(j.idle_state == DefenderJet.Idle.ORBIT and j.attacker == null and j.stats.bombs == 0, "idle: enemies that have not attacked it are left alone (an elephant 70 m off its path, riflemen inside it)")
	# The elephant moves onto its path: its flak locks on as the jet passes over.
	var anchor0: Vector3 = j.anchor
	e.global_position = Vector3(0.0, 0.2, -DefenderJet.IDLE_RADIUS)
	var provoked := await _until(func(): return j.attacker == e, 14.0)
	print("MACHINES t=%.1f the elephant locks on: the jet goes for it" % t)
	_check(provoked and j.idle_state in [DefenderJet.Idle.SETUP, DefenderJet.Idle.RUN], "idle: attacked, it goes for the attacker (%s)" % DefenderJet.Idle.keys()[j.idle_state])
	_check(j.order_name() == "BOMB RUN", "idle: the roster says BOMB RUN")
	var ran := await _until(func(): return j.idle_state == DefenderJet.Idle.RUN, 14.0)
	_check(ran, "idle: it sets up out at the start of a run")
	print("MACHINES t=%.1f on its bomb run" % t)
	_spectate(Vector3.ZERO, Vector3.ZERO, Vector3(30.0, 45.0, -140.0), Vector3(0.0, -70.0, 300.0))
	await _until(func(): return j.stats.bombs >= 1, 14.0)
	print("MACHINES t=%.1f bomb away" % t)
	# Riding along beside the bomb as it falls, then (it bursts) from the ground beside the attacker.
	_spec_node = j._run_bomb
	_spectate(Vector3.ZERO, Vector3.ZERO, Vector3(16.0, 6.0, -26.0), Vector3(0.0, -8.0, 14.0))
	_check(j.stats.bombs >= 1 and j.idle_state == DefenderJet.Idle.EGRESS, "idle: the bomb goes where the forecast crosses it, and it breaks away")
	await _until(func(): return not j.bomb_bursts.is_empty(), 8.0)
	print("MACHINES t=%.1f bomb burst" % t)
	_spectate(e.global_position + Vector3(75.0, 24.0, 55.0), e.global_position + Vector3(0.0, 14.0, 0.0))
	if not j.bomb_bursts.is_empty():
		_check(j.bomb_bursts.back().distance_to(e.global_position) < 12.0, "idle: and lands on it (%.1f m off)" % j.bomb_bursts.back().distance_to(e.global_position))
	await _wait(1.5)
	_check(not e.is_alive(), "idle: the attacker is destroyed")
	var home := await _until(func(): return j.idle_state == DefenderJet.Idle.RETURN, 8.0)
	print("MACHINES t=%.1f returning" % t)
	_overview(true)
	_check(home and j.attacker == null, "idle: with it destroyed, it heads back to where it was left")
	var near_spot := await _until(func(): return j.idle_state == DefenderJet.Idle.ORBIT, 30.0)
	var back := Vector2(j.global_position.x - anchor0.x, j.global_position.z - anchor0.z).length()
	print("MACHINES t=%.1f back in orbit" % t)
	_check(near_spot and back < 200.0, "idle: and circles there again (%.0f m from the spot where it was left)" % back)
	await _wait(8.0)
	_spectate_off()
	var r2 := Vector2(j.global_position.x, j.global_position.z).length()
	_check(j.is_alive() and absf(r2 - DefenderJet.IDLE_RADIUS) < 30.0, "idle: round the same circle (%.0f m from its centre)" % r2)
	# Attacked again: it goes for the next one. Hurt with nobody locked on: the nearest enemy that could have done it.
	# The south of the circle, 60 m outside its path (out of flak reach, away from the tank at the gate): it never locks on.
	var e2 := _spawn("elephant", Vector3(0.0, 0.2, DefenderJet.IDLE_RADIUS + 60.0))
	e2.hp = 150.0
	await _until(func(): return Vector2(j.global_position.x - e2.global_position.x, j.global_position.z - e2.global_position.z).length() < 110.0, 15.0)
	_check(j.attacker == null and j.idle_state == DefenderJet.Idle.ORBIT, "idle: an anti-aircraft enemy that hasn't fired on it is still left alone")
	j.take_damage(1.0, GameConfig.TEAM_ATTACKER)
	await _wait(0.5)
	_check(j.attacker == e2, "idle: hurt, with nothing locked on, it picks the nearest anti-aircraft enemy to go for")
	var bombs0: int = j.stats.bombs
	var seen_state: int = j.idle_state
	var until := t + 40.0
	while t < until and e2.is_alive():
		await get_tree().physics_frame
		if j.idle_state != seen_state:
			seen_state = j.idle_state
			print("MACHINES t=%.1f   jet is now %s (passes %d, bombs %d, attacker %s, elephant hp %.0f)" % [t, DefenderJet.Idle.keys()[seen_state], j._passes, j.bombs, j.attacker, e2.hp])
	_check(j.stats.bombs > bombs0 and not e2.is_alive(), "idle: it bombs that one too (%d bombs in all)" % j.stats.bombs)
	await _until(func(): return j.idle_state == DefenderJet.Idle.ORBIT, 40.0)
	_check(j.idle_state == DefenderJet.Idle.ORBIT and j.is_alive(), "idle: and goes back to circling (hull %.0f of %.0f)" % [j.hp, DefenderJet.HP])
	_retire(riflemen)
	var bombs1: int = j.stats.bombs
	await _wait(6.0)
	_check(j.idle_state == DefenderJet.Idle.ORBIT and j.attacker == null and j.stats.bombs == bombs1, "idle: and passive again, circling, until the next attack")


func _tank_drive() -> void:
	defender.select_squad(armory.squads.find(tank), true)
	# Into the field, facing south, ready to drive.
	tank.stage(TANK_AT, 0.0)
	await _wait(1.5)
	_say("Hover Tank: WASD to drive (camera-relative), mouse aims the turret", 4.0)
	var start := tank.global_position
	_move = Vector2(0.0, -1.0)  # forward: the way the camera looks
	await _wait(3.0)
	_check(tank.global_position.distance_to(start) > 20.0 and tank.speed > 10.0, "drive: W takes it off (%.0f m/s, %.0f m in 3 s)" % [tank.speed, tank.global_position.distance_to(start)])
	_move = Vector2(1.0, 0.0)  # to the camera's right: the hull turns onto it
	await _wait(3.0)
	var d := angle_difference(0.0, tank.heading)
	_check(absf(d) > deg_to_rad(60.0), "drive: it turns the hull round onto the way it goes (%.0f° from where it faced)" % rad_to_deg(absf(d)))
	_move = Vector2.ZERO
	await _wait(2.0)
	# Into the mountain's wall: stopped.
	tank.stage(Vector3(0.0, 0.0, 120.0), PI)
	await _wait(0.5)
	_move = Vector2(0.0, -1.0)
	await _wait(5.5)
	_check(tank.global_position.z > 70.0 and absf(tank.speed) < 1.0, "drive: the stronghold's wall stops it (z %.0f, after 5.5 s at full speed from z 120)" % tank.global_position.z)
	_move = Vector2.ZERO
	# Over the river: it skims the water.
	tank.stage(Vector3(0.0, 0.0, 428.0), 0.0)
	await _wait(0.5)
	_move = Vector2(0.0, -1.0)
	await _wait(3.5)
	_check(tank.global_position.z > 458.0 and tank.global_position.z < 520.0 and absf(tank.global_position.y - JungleLayout.WATER_Y) < 1.0,
			"drive: it hovers out over the river, skimming the water (z %.0f, %.1f m up)" % [tank.global_position.z, tank.global_position.y])
	_move = Vector2.ZERO


func _tank_guns() -> void:
	tank.stage(TANK_AT, 0.0)
	_targets = _spawn_group(["rifleman", "rifleman", "rifleman", "rifleman", "breacher"], TANK_TARGET, 4.0)
	await _wait(1.5)
	_say("Main gun: LMB once the turret is on the crosshair", 4.0)
	# For the stills: side-on, behind its left shoulder, the recoil and the machine guns' fire.
	_spectate(TANK_AT + Vector3(-13.0, 3.6, -9.0), TANK_AT + Vector3(3.0, 2.6, 10.0))
	_look = Combat.aim_point(_targets[0])
	var hp0 := _hp_of(_targets)
	# The crosshair onto the target, and the turret onto the crosshair.
	await _until(func(): return tank.aim_point.distance_to(_look) < 2.5 and tank.rig.aimed(), 8.0)
	_check(tank.rig.aimed() and tank.aim_point.distance_to(_look) < 2.5, "gun: the crosshair is on the target and the turret swings onto it")
	_fire = true
	await _until(func(): return tank.stats.rounds >= 1, 3.0)
	_fire = false
	print("MACHINES t=%.1f main gun fires" % t)
	await _wait(1.2)
	print("MACHINES shell burst %s target %s tank %s aim %s" % [tank.bursts, TANK_TARGET, tank.global_position, tank.aim_point])
	_check(tank.stats.rounds == 1 and tank.cannon_cd > 1.0, "gun: LMB fires one round, then %.1f s to reload" % DefenderTank.CANNON_RELOAD)
	_check(_hp_of(_targets) < hp0 * 0.7, "gun: the shell blasts the knot of attackers (%d of %d standing)" % [_alive_count(_targets), _targets.size()])
	await _wait(2.5)
	# The machine guns.
	_say("Machine guns: hold RMB", 3.0)
	var hp1 := _hp_of(_targets)
	_mgs = true
	await _wait(2.5)
	print("MACHINES t=%.1f machine guns" % t)
	await _wait(1.0)
	_mgs = false
	_check(tank.stats.mg_rounds > 30, "guns: RMB works the twin machine guns in the sponsons (%d rounds)" % tank.stats.mg_rounds)
	_check(_hp_of(_targets) < hp1, "guns: and they hit what is on the crosshair")
	_look = null
	_spectate_off()


func _tank_idle() -> void:
	# The player leaves it for another post: it holds its ground and fights what comes within reach.
	var rifle := _spawn("rifleman", Vector3(10.0, 0.0, 178.0))
	var ram := _spawn("breacher", Vector3(-16.0, 0.0, 186.0))
	armory.credits += DefenderArmory.JET_COST
	var j4 := defender.buy_squad("jet") as DefenderJet
	j4.pilot = self
	defender.select_squad(armory.squads.find(j4), true)
	jet = j4
	_steer = Vector2(PI * 0.5, 0.0)
	_say("Left alone, the tank holds its ground and fights", 5.0)
	var rounds0: int = tank.stats.rounds
	await _wait(7.0)
	_check(tank.target != null or not is_instance_valid(rifle) or not rifle.is_alive() or not ram.is_alive(), "idle: left alone it picks a target in reach")
	_check(tank.stats.rounds > rounds0, "idle: and fires its main gun on it (%d rounds)" % (tank.stats.rounds - rounds0))
	_check(tank.order_name() == "HOLD" and not tank.possessed, "idle: it holds (roster: %s)" % tank.order_name())
	_steer = null
	_check(armory.squads.has(tank) and tank.roster_label() == "TANK", "roster: the tank keeps its slot (%s, F%d)" % [tank.roster_label(), armory.squads.find(tank) + 1])


# ---------------------------------------------------------------- the pilot

## The machine's keys and mouse, as a player works them.
func pilot_input(m: DefenderMachine, delta: float) -> void:
	if m is DefenderJet:
		var j := m as DefenderJet
		j.input.move = Vector2.ZERO
		j.input.boost = _boost
		j.input.brake = _brake
		j.input.bomb = _bomb
		j.input.missiles = _missiles
		_bomb = false
		_missiles = false
		if _steer_to != null:
			j.steer_toward(_steer_to)
		elif _steer != null:
			j.steer(_steer.x, _steer.y)
		if _drop_on != null and j.bombs > 0 and not j.bomb_forecast.is_empty():
			# The preview is on them: let it go.
			var ahead: float = (_drop_on - j.bomb_forecast.impact).dot(j.forward() * Vector3(1, 0, 1))
			if ahead <= 1.0:
				j.input.bomb = true
	elif m is DefenderTank:
		var k := m as DefenderTank
		k.input.move = _move
		k.input.fire = _fire
		k.input.aim = _mgs
		if _look != null:
			k.look_toward(_look, 1.6, delta)


func _aim_free() -> void:
	_boost = false
	_brake = false
	_drop_on = null


# ---------------------------------------------------------------- staging and checks

func _spawn(type_id: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = at + Vector3.UP * 0.2
	u.rotation.y = randf() * TAU
	return u


func _spawn_group(types: Array, centre: Vector3, spread: float) -> Array:
	var out := []
	for i in types.size():
		var a := TAU * i / types.size()
		out.append(_spawn(types[i], centre + Vector3(cos(a), 0.0, sin(a)) * spread * (0.0 if i == 0 else 1.0)))
	return out


## Units off the field once their part is played.
func _retire(list: Array) -> void:
	for u in list:
		if is_instance_valid(u):
			commander.units.erase(u.unit_id)
			u.queue_free()


func _hp_of(list: Array) -> float:
	var s := 0.0
	for u in list:
		if is_instance_valid(u) and u.is_alive():
			s += u.hp
	return s


func _alive_count(list: Array) -> int:
	return list.filter(func(u): return is_instance_valid(u) and u.is_alive()).size()


## The most any two of `dirs` differ (rad).
func _aim_spread(dirs: Array) -> float:
	var worst := 0.0
	for a in dirs:
		for b in dirs:
			worst = maxf(worst, (a as Vector3).angle_to(b))
	return worst


func _physics_process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	if not _snaps.is_empty():
		_snap()


## The spectator's camera (for the stills): at `from` looking at `at`, the panels hidden. With `rel` it rides along with the
## jet at that offset (world axes), looking at the jet's position plus `look`.
func _spectate(from: Vector3, at: Vector3, rel = null, look := Vector3.ZERO) -> void:
	_spec = true
	_spec_at = at
	_spec_rel = rel
	_spec_look = look
	cam.fov = 55.0
	cam.global_position = from
	cam.look_at(at)
	cam.current = true
	defender.visible = false
	for m in [jet, tank]:
		if is_instance_valid(m):
			m._hud_layer.visible = false


## The spectator high over the south field looking at the whole circle the jet flies when left alone, with the circle drawn in
## (an overlay of the showcase's: the game draws none).
func _overview(on: bool) -> void:
	if on:
		_spectate(Vector3(0.0, 470.0, 330.0), Vector3(0.0, 140.0, -10.0))
		cam.fov = 58.0
		if _orbit_ring == null:
			var ring := TorusMesh.new()
			ring.inner_radius = DefenderJet.IDLE_RADIUS - 1.3
			ring.outer_radius = DefenderJet.IDLE_RADIUS + 1.3
			ring.rings = 96
			ring.ring_segments = 6
			_orbit_ring = MeshInstance3D.new()
			_orbit_ring.mesh = ring
			_orbit_ring.position.y = 150.0
			_orbit_ring.material_override = Mats.unshaded(Color(1.0, 0.85, 0.3, 0.8), false)
			_orbit_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_orbit_ring)
		_orbit_ring.visible = true
	elif _orbit_ring != null:
		_orbit_ring.visible = false


func _spectate_off() -> void:
	if not _spec:
		return
	_overview(false)
	_spec_node = null
	_spec = false
	defender.visible = true
	if defender.current != null:
		defender.current.get_camera().current = true
		defender.current._hud_layer.visible = true


func _process(_delta: float) -> void:
	if _jet_tag != null:
		var show := _spec and _orbit_ring != null and _orbit_ring.visible and is_instance_valid(jet) and not cam.is_position_behind(jet.global_position)
		_jet_tag.visible = show
		if show:
			_jet_tag.position = cam.unproject_position(jet.global_position) + Vector2(-72, -14)
	if _spec and _spec_rel != null:
		var who: Node3D = _spec_node if is_instance_valid(_spec_node) else jet
		if is_instance_valid(who):
			cam.global_position = who.global_position + _spec_rel
			cam.look_at(who.global_position + _spec_look)


func _wait(seconds: float) -> void:
	var until := t + seconds
	while t < until:
		await get_tree().physics_frame


func _until(cond: Callable, timeout: float) -> bool:
	var until := t + timeout
	while not cond.call():
		if t > until:
			return false
		await get_tree().physics_frame
	return true


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok
	if test:
		print("MACHINES CHECK ", ("ok    " if ok else "FAIL  ") + what)


func _finish() -> void:
	print("MACHINES stats jet %s tank %s" % [jet.stats, tank.stats])
	for c in _checks:
		print("MACHINES CHECK ", c)
	print("MACHINES SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed and test else 0)


func _say(text: String, seconds := 3.0) -> void:
	_caption.text = text
	_caption.visible = true
	print("MACHINES t=%.1f %s" % [t, text])
	get_tree().create_timer(seconds).timeout.connect(func(): if _caption.text == text: _caption.visible = false)


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		print("snap %.1f" % at)
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_caption = UIKit.label("", 22, Color.WHITE)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y = 24
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	layer.add_child(_caption)
	_jet_tag = UIKit.label("JET ->", 18, Color(1.0, 0.9, 0.35))
	_jet_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_jet_tag.add_theme_constant_override("outline_size", 6)
	_jet_tag.visible = false
	_jet_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_jet_tag)
