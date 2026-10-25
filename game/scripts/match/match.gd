extends Node3D
## One offline match: builds the level, puts the human on their chosen side and the
## CPU on the other, and decides the winner.
##
## Attacker wins by destroying the keep. Defender wins by holding until time runs out.

var level: LevelBuilder
var commander: AttackerCommander
var ui: MatchUI
var player_controller: Node
var ai_attacker: AIAttacker
## The defenders' credits and bought squads (the human defender's; the CPU defender buys none).
var armory: DefenderArmory
var time_left := 600.0
var started := false
var finished := false

var _autotest_t := 0.0


func _ready() -> void:
	time_left = GameConfig.match_duration
	level = LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build()

	var units_root := Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.name = "AttackerCommander"
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	add_child(commander)

	ui = MatchUI.new()
	ui.level = level
	ui.match_node = self
	add_child(ui)

	if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER:
		armory = DefenderArmory.new()
		armory.name = "DefenderArmory"
		armory.level = level
		var dc := DefenderController.new()
		dc.level = level
		dc.armory = armory
		player_controller = dc
		ai_attacker = AIAttacker.new()
		ai_attacker.commander = commander
		ai_attacker.level = level
		commander.income = AttackerCommander.BASE_INCOME * GameConfig.ai_income_mult()
	else:
		var ac := AttackerController.new()
		ac.level = level
		ac.commander = commander
		player_controller = ac
	ui.resumed.connect(player_controller.restore_mouse)

	level.keep.destroyed.connect(func(_k): _end(GameConfig.TEAM_ATTACKER))

	# Nothing moves until the navmesh is ready.
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	started = true
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	if armory:
		add_child(armory)
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
			# Buy two AA Squads and a Flame Squad early, drive them now and then and swap their orders.
			if step == 2:
				armory.credits += DefenderArmory.AA_COST + DefenderArmory.FLAME_COST
				dc.buy_squad()
				dc.buy_squad()
				dc.buy_squad("flame")
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
			for t in [UnitTypes.ORDER[step % UnitTypes.ORDER.size()], "rifleman", "kangaroo", "medic"]:
				ac.spawn(t)
			var ids := commander.units.keys()
			var gate: Structure = level.gates.values()[step % 3]
			if gate.is_alive():
				commander.submit({"type": "ram", "units": ids})
				commander.submit({"type": "attack", "units": ids, "target": gate.get_path()})
			else:
				commander.submit({"type": "attack", "units": ids, "target": level.keep.get_path()})
			commander.submit({"type": "smoke", "units": ids, "pos": gate.global_position})
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
	print("AUTOTEST report t=%.0f units=%d supply=%d keep=%d gates=%s" % [
			_autotest_t, commander.units.size(), commander.supply, level.keep.hp, ", ".join(gates)])
	if armory:
		for s in armory.squads:
			var extra := "mines_down=%d" % (s as AASquad).mines.size() if s is AASquad else "trees_burnt=%d" % (s as FlameSquad).burnt.size()
			print("AUTOTEST %s alive=%d order=%s plan=%s %s stats=%s" % [s.station_name, s.troopers.size(),
					s.order_name(), s.get("plan"), extra, s.get("stats")])
