extends Node3D
## One offline match: builds the level, puts the human on their chosen side and the
## CPU on the other, and decides the winner.
##
## Attacker wins by destroying every air vent on the roofs. Defender wins by holding until time runs out.

var level: LevelBuilder
var commander: AttackerCommander
var ui: MatchUI
var player_controller: Node
var ai_attacker: AIAttacker
## The attackers' fog of war.
var vision: AttackerVision
## The defenders' credits and bought squads (the human defender's; the CPU defender buys none).
var armory: DefenderArmory
## The defenders' drone swarms (the CPU defender has them too); null with --drones=off.
var drones: DroneBay
## The attackers' transport helicopters, standing by the main base.
var fleet: HeloFleet
var time_left := 600.0
var started := false
var finished := false

var _autotest_t := 0.0


func _ready() -> void:
	level = JungleLevel.new() if GameConfig.map == "jungle" else LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build()
	time_left = level.match_time()
	# The effects engine, made now so its shaders are compiled before the first shot.
	FX.of(self)

	var units_root := Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.name = "AttackerCommander"
	commander.units_root = units_root
	commander.level = level
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	add_child(commander)
	vision = AttackerVision.new()
	vision.name = "AttackerVision"
	vision.commander = commander
	vision.hide_enemies = GameConfig.player_side == GameConfig.PlayerSide.ATTACKER
	add_child(vision)

	ui = MatchUI.new()
	ui.level = level
	ui.match_node = self
	add_child(ui)

	# The two transport helicopters by the main base (they join the match with the controllers, once the navmesh is in).
	fleet = HeloFleet.new()
	fleet.name = "HeloFleet"
	fleet.base_position = level.spawn_points[0]
	fleet.helo_added.connect(_on_helo_added)
	fleet.helo_lost.connect(_on_helo_lost)
	commander.fleet = fleet

	if GameConfig.drones:
		drones = DroneBay.new()
		drones.name = "DroneBay"
		drones.level = level
		drones.swarm_launched.connect(func(_s): ui.alert("Defender drones are up: only bears and AA units can touch them", UIKit.WARN))

	if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER:
		armory = DefenderArmory.new()
		armory.name = "DefenderArmory"
		armory.level = level
		var dc := DefenderController.new()
		dc.level = level
		dc.armory = armory
		dc.drones = drones
		player_controller = dc
		ai_attacker = AIAttacker.new()
		ai_attacker.commander = commander
		ai_attacker.level = level
		ai_attacker.drones = drones
		commander.income = AttackerCommander.BASE_INCOME * GameConfig.ai_income_mult()
	else:
		var ac := AttackerController.new()
		ac.level = level
		ac.commander = commander
		player_controller = ac
	ui.resumed.connect(player_controller.restore_mouse)

	level.vents_destroyed.connect(func(): _end(GameConfig.TEAM_ATTACKER))

	# Nothing moves until the navmesh is ready.
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	started = true
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	if armory:
		add_child(armory)
	if drones:
		add_child(drones)
	add_child(fleet)
	add_child(player_controller)
	if ai_attacker:
		add_child(ai_attacker)
	var side_text := "Hold the stronghold!" if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER else "Break through and destroy the Keep!"
	ui.alert(side_text, UIKit.ACCENT)
	if GameConfig.autotest != "":
		_autotest_setup()


func _process(delta: float) -> void:
	if not started or finished:
		return
	time_left -= delta
	if time_left <= 0.0:
		_end(GameConfig.TEAM_DEFENDER)
	if GameConfig.autotest != "":
		_autotest_step(delta)


## A transport helicopter stands at the base (the start, or a replacement): the defender hears when it lifts off.
func _on_helo_added(h: TransportHelo) -> void:
	h.state_changed.connect(_on_helo_state)
	h.trip_aborted.connect(_on_helo_turned_back)


## A loaded helicopter lifting off for a helipad: the defending player is told where, and with how many (they can shoot it down).
func _on_helo_state(h: TransportHelo) -> void:
	if h.state != TransportHelo.State.CLIMB or not h.out_leg:
		return
	if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER:
		ui.alert("Enemy transport helicopter lifting off for %s with %d units aboard" % [h.dest_name, h.cargo.size()], UIKit.WARN)


## The helipad of a helicopter's trip was lost: it turned for home with what was aboard (`on_pad`: caught on the pad as it
## fell, and hit lifting off).
func _on_helo_turned_back(h: TransportHelo, on_pad: bool) -> void:
	if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER:
		ui.alert("Enemy transport helicopter driven off %s, hit" % h.dest_name if on_pad
				else "Enemy transport helicopter turning back from %s" % h.dest_name, UIKit.GOOD)
	elif on_pad:
		ui.alert("%s hit lifting off %s as it fell · bringing %d units home" % [h.display_name, h.dest_name, h.cargo.size()], UIKit.DANGER)
	else:
		ui.alert("%s turning back: %s was lost · bringing %d units home" % [h.display_name, h.dest_name, h.cargo.size()], UIKit.WARN)


## A transport helicopter went down: what was aboard went with it, and a new one is HeloCargo.REPLACE_TIME s away.
func _on_helo_lost(h: TransportHelo) -> void:
	var lost: int = h.stats.units_lost
	if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER:
		ui.alert("%s shot down%s" % [h.display_name, " with %d units aboard" % lost if lost > 0 else ""], UIKit.GOOD)
	else:
		ui.alert("%s destroyed%s · a new one in %d s" % [h.display_name, ", %d units lost" % lost if lost > 0 else "",
				int(HeloCargo.REPLACE_TIME)], UIKit.DANGER)


func _end(winner: int) -> void:
	if finished:
		return
	finished = true
	var player_team := GameConfig.TEAM_DEFENDER if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER else GameConfig.TEAM_ATTACKER
	var won := winner == player_team
	var title := "VICTORY" if won else "DEFEAT"
	var sub := "The Keep has fallen." if winner == GameConfig.TEAM_ATTACKER else "The stronghold held!"
	print("MATCH OVER: winner=%s time_left=%.0f" % ["attacker" if winner == GameConfig.TEAM_ATTACKER else "defender", time_left])
	if GameConfig.autotest != "":
		_autotest_report()
		get_tree().quit()
		return
	ui.show_end(title, sub, won)


# ---------------------------------------------------------------- automated smoke test
# Runs a scripted match at high speed so the whole game loop can be checked headless.

var _autotest_events := 0
var _autotest_shot := false


func _autotest_setup() -> void:
	Engine.time_scale = 1.0 if GameConfig.screenshot_path != "" else 4.0
	print("AUTOTEST start side=%s" % GameConfig.autotest)
	if player_controller is AttackerController:
		commander.supply = 2000.0


func _autotest_step(delta: float) -> void:
	_autotest_t += delta
	var step := int(_autotest_t / 3.0)
	if step > _autotest_events:
		_autotest_events = step
		if player_controller is DefenderController:
			var dc: DefenderController = player_controller
			# Buy an AA Squad, a Flame Squad, an Infiltrator Squad, a Sniper, the Fighter Jet and the Hover Tank early
			# (the roster's six slots), drive them now and then and swap their orders (the infiltrators' next order
			# sends them on a sabotage operation). Nobody flies the jet when it is taken over: it holds its course.
			if step == 2:
				armory.credits += DefenderArmory.AA_COST + DefenderArmory.FLAME_COST + DefenderArmory.INFILTRATOR_COST \
						+ DefenderArmory.SNIPER_COST + DefenderArmory.JET_COST + DefenderArmory.TANK_COST
				dc.buy_squad()
				dc.buy_squad("flame")
				dc.buy_squad("infiltrator")
				dc.buy_squad("sniper")
				dc.buy_squad("jet")
				dc.buy_squad("tank")
			if step % 7 == 5:
				for s in armory.squads:
					s.cycle_order()
			if step % 4 == 0:
				dc.select_most_threatened()
			elif step % 4 == 2 and not armory.squads.is_empty():
				dc.select_squad(step % armory.squads.size())
			else:
				dc.select_station(step % dc.stations.size())
			if step % 2 == 0:
				Input.action_press("fire")
			else:
				Input.action_release("fire")
		elif player_controller is AttackerController:
			var ac: AttackerController = player_controller
			ac.set_spawn_point(step % 3)
			for t in [UnitTypes.ORDER[step % UnitTypes.ORDER.size()], "rifleman", "kangaroo", "medic", "giraffe"]:
				ac.spawn(t)
			var ids := commander.units.keys()
			commander.submit({"type": "ping", "units": ids})
			var gate: Structure = level.gates.values()[step % 3]
			if gate.is_alive():
				commander.submit({"type": "ram", "units": ids})
				commander.submit({"type": "attack", "units": ids, "target": gate.get_path()})
			else:
				var vent := level.nearest_vent(gate.global_position)
				if vent:
					commander.submit({"type": "attack", "units": ids, "target": vent.get_path()})
			commander.submit({"type": "smoke", "units": ids, "pos": gate.global_position})
			# Flash grenades onto the gate's machine gun (the first three posts are the gate guns).
			commander.submit({"type": "flash", "units": ids, "pos": level.stations[step % 3].global_position})
			# A few units board the first transport helicopter now and then, and it flies them to a helipad.
			if step % 5 == 2:
				commander.submit({"type": "helo_board", "units": ids.slice(0, 6), "helo": 0})
			elif step % 5 == 4:
				# (The helipads come last in the spawn list on both maps.)
				commander.submit({"type": "helo_fly", "helo": 0, "spawn": commander.spawn_bases.size() - 1 - step % 2})
			# Serpent Snipers up the tree nearest the gate, or round the bush nearest it, by turns.
			if step % 4 == 1:
				var tree := SerpentNest.tree_near(gate.global_position, 120.0)
				if tree:
					commander.submit({"type": "nest", "units": ids, "pos": tree.trunk_centre()})
			elif step % 4 == 3:
				var bush := Bush.nearest(gate.global_position, 120.0)
				if bush:
					commander.submit({"type": "trap", "units": ids, "pos": bush.global_position})
	if GameConfig.screenshot_path != "" and not _autotest_shot and _autotest_t > GameConfig.autotest_duration * 0.8:
		_autotest_shot = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(GameConfig.screenshot_path)
		print("AUTOTEST screenshot saved")
	if _autotest_t > GameConfig.autotest_duration:
		_autotest_report()
		get_tree().quit()
		set_process(false)


func _autotest_report() -> void:
	var gates := []
	for side in level.gates:
		gates.append("%s=%d" % [side, level.gates[side].hp])
	print("AUTOTEST report t=%.0f units=%d supply=%d vents=%d gates=%s" % [
			_autotest_t, commander.units.size(), commander.supply, level.vents_left(), ", ".join(gates)])
	if armory:
		for s in armory.squads:
			if s is DefenderMachine:
				print("AUTOTEST %s alive=%s hp=%d order=%s stats=%s" % [s.station_name, s.is_alive(), int(s.hp), s.order_name(), s.stats])
				continue
			var extra := ""
			if s is AASquad:
				extra = "mines_down=%d" % (s as AASquad).mines.size()
			elif s is FlameSquad:
				extra = "trees_burnt=%d" % (s as FlameSquad).burnt.size()
			elif s is InfiltratorSquad:
				var arrows := 0
				for t in s.troopers:
					arrows += (t as InfiltratorTrooper).stats.arrows
				extra = "kits=%d camo=%.0f arrows=%d" % [(s as InfiltratorSquad).kits, (s as InfiltratorSquad).camo_left, arrows]
			elif s is Sniper:
				extra = "tagged=%d" % (s as Sniper).tagged().size()
			print("AUTOTEST %s alive=%d order=%s plan=%s %s stats=%s" % [s.station_name, s.troopers.size(),
					s.order_name(), s.get("plan"), extra, s.get("stats")])
	if drones:
		print("AUTOTEST drones swarms=%d drones=%d aloft=%d ready=%d stats=%s" % [drones.swarms.size(), drones.alive_count(),
				drones.airborne_count(), drones.ready_count(), drones.stats])
	for b in level.bases:
		print("AUTOTEST %s controlled=%s capture=%.1f" % [b.display_name, b.controlled, b.capture])
	if fleet:
		for i in fleet.slots.size():
			var h := fleet.helo_at(i)
			if h:
				print("AUTOTEST %s %s hp=%d aboard=%d/%d stats=%s" % [h.display_name, h.status_text(), int(h.hp), h.spaces_used(),
						HeloCargo.CAPACITY, h.stats])
			else:
				print("AUTOTEST Helo %d down, a new one in %d s" % [i + 1, int(fleet.replace_in[i])])
	var dogs := commander.units.values().filter(func(u): return u.has_dog_modes())
	print("AUTOTEST dogs healing=%d sweeping=%d mine_blasts=%d mines_disarmed=%d" % [dogs.filter(func(u): return u.dog_mode == "heal").size(),
			dogs.filter(func(u): return u.dog_mode == "sweep").size(), GroundMine.blasts, GroundMine.disarms])
