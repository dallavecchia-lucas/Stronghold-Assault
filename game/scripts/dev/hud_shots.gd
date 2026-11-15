extends Node
## Stills of a player's HUD in a real match on the Jungle Keep, so a change to it can be looked at without playing.
##
##   attacker (AttackerHUD)  an army in front of the south gate with a mixed selection (its skills on the card), units on the
##                           production line, groups saved and a warning up: 1_selection; the base selected (Backspace) with
##                           its production: 2_base; nothing selected, the HUD at its leanest: 3_idle
##   defender (DefenderHUD)  three squads and the Fighter Jet bought (the credits left buy the rest), attackers at the south
##                           gate, the south guns and gate hurt: on a south deck gun, 1_gun; driving the AA Squad, 2_aa_squad;
##                           flying the jet, 3_jet
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 --resolution 1600x900 \
##       res://scenes/dev/hud_shots.tscn -- --out=/some/dir --lighting=standard [--side=defender]
##
## The 3D view is off while the navmesh is baked and the portraits are rendered (on software GL a frame of the forest takes
## seconds), and on for the stills.

const ARMY := ["rhino", "rhino", "lioness", "lioness", "lioness", "rifleman", "rifleman", "rifleman", "rifleman", "kangaroo",
		"kangaroo", "medic", "giraffe"]
const LINE := ["elephant", "rifleman", "rifleman", "rifleman", "hippo", "talon", "talon", "chimp"]
## Frames to wait at most for the portraits to be rendered.
const PORTRAIT_WAIT := 400

var out_dir := "user://hud_shots"
var side := "attacker"
var game: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--side="):
			side = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameConfig.player_side = GameConfig.PlayerSide.DEFENDER if side == "defender" else GameConfig.PlayerSide.ATTACKER
	get_viewport().disable_3d = true
	game = (load("res://scenes/match.tscn") as PackedScene).instantiate()
	add_child(game)
	var frames := 0
	while not game.started:
		await get_tree().process_frame
		frames += 1
		if frames % 100 == 0:
			print("HUD SHOTS waiting for the navmesh, frame %d" % frames)
	print("HUD SHOTS match started")
	if side == "defender":
		await _defender_shots()
	else:
		await _attacker_shots()
	print("HUD SHOTS done -> %s" % out_dir)
	get_tree().quit()


## An army of `types` 45 m out in front of the south gate (attack-moving nowhere: they stand).
func _army(types: Array) -> Array:
	var cmd: AttackerCommander = game.commander
	var level: LevelBuilder = game.level
	var front: Vector3 = level.gates["south"].global_position + Vector3(0, 0, 45)
	var army := []
	for i in types.size():
		var id := cmd.submit({"type": "spawn", "unit": types[i]})
		if id == 0:
			continue
		var u: AttackerUnit = cmd.units[id]
		var at := front + Vector3((i % 5 - 2) * 4.0, 0.0, (i / 5) * 4.0)
		at.y = LevelBuilder.ground_height(at) + 0.2
		u.global_position = at
		army.append(u)
	return army


func _wait_portraits(key: String) -> void:
	var waited := 0
	while UnitPortraits.get_texture(key, "mug") == null and waited < PORTRAIT_WAIT:
		await get_tree().process_frame
		waited += 1
	print("HUD SHOTS portraits after %d frames" % waited)


func _attacker_shots() -> void:
	var ac: AttackerController = game.player_controller
	var cmd: AttackerCommander = game.commander
	var level: LevelBuilder = game.level
	cmd.supply = 4000.0
	var gate: Structure = level.gates["south"]
	var front := gate.global_position + Vector3(0, 0, 45)
	var army := _army(ARMY)
	ac.groups[0] = army.filter(func(u): return u.type_id == "rhino")
	ac.groups[1] = army.filter(func(u): return u.type_id == "lioness")
	ac.groups[2] = army.filter(func(u): return u.type_id == "rifleman")
	ac.groups[4] = army.duplicate()
	ac.camera_rig.focus(front + Vector3(0, 0, 8))
	await _wait_portraits(UnitTypes.ORDER[-1])

	# A mixed selection, the production line, a warning.
	for t in LINE:
		ac.spawn(t)
	ac.recall_group(4)
	ac.warn("South Gate under attack!", UIKit.WARN, gate.global_position)
	await _snap("1_selection")

	# The base: its production.
	for t in LINE:
		ac.spawn(t)
	ac.select_base()
	await _snap("2_base")

	# Nothing selected, the line done, the warnings gone: the HUD at its leanest.
	ac.recall_group(8)
	ac.camera_rig.focus(front + Vector3(0, 0, 8))
	cmd.production.clear()
	ac.hud.set("_warnings", [])
	await _snap("3_idle")


func _defender_shots() -> void:
	var dc: DefenderController = game.player_controller
	var armory: DefenderArmory = game.armory
	var level: LevelBuilder = game.level
	armory.credits = 350.0 + 300.0 + 280.0 + 600.0 + 700.0
	for kind in ["aa", "flame", "infiltrator", "jet"]:
		dc.buy_squad(kind)
	# The south gate and some of its guns hurt.
	var gate: Structure = level.gates["south"]
	gate.hp = gate.max_hp * 0.55
	var hurt := 0
	for s in level.stations:
		if s is MountedGun and DefenderHUD.side_of(s.global_position) == "south" and hurt < 5:
			s.hp = s.max_hp * 0.35
			hurt += 1
	await _wait_portraits("d_tank")
	# Let the garrison take some guns and the HUD settle; then attackers at the south gate (now, so they still stand).
	for i in 200:
		await get_tree().process_frame
	_army(["rhino", "rhino", "elephant", "hippo", "hippo", "lioness", "giraffe", "rifleman"])

	# On a south deck gun.
	var gun := -1
	for i in dc.stations.size():
		var st = dc.stations[i]
		if st is MountedGun and DefenderHUD.side_of(st.global_position) == "south" and st.can_possess() and st.kind == "sentry":
			gun = i
			break
	dc.select_station(maxi(gun, 0), true)
	await _snap("1_gun")

	dc.select_squad(0, true)
	await _snap("2_aa_squad")

	dc.select_squad(3, true)
	await _snap("3_jet")


## Turns the 3D view on for a few frames (the camera settles, the panels catch up) and saves a still.
func _snap(file: String) -> void:
	get_viewport().disable_3d = false
	for i in 6:
		await get_tree().process_frame
	# The post's keys show for a few seconds after taking it: the frames above are slow on software GL.
	if game.player_controller is DefenderController:
		game.player_controller.hud.on_switched()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, file]
	get_viewport().get_texture().get_image().save_png(path)
	get_viewport().disable_3d = true
	print("HUD SHOTS saved %s" % path)
