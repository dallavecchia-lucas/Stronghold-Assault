extends Node
## Stills of the attacking player's HUD (AttackerHUD) in a real match on the Jungle Keep, so a change to it
## can be looked at without playing: an army in front of the south gate with a mixed selection (its skills on the card),
## units on the production line, groups saved and a warning up; then the base selected (Backspace) with its production;
## then nothing selected, the HUD at its leanest.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 --resolution 1600x900 \
##       res://scenes/dev/hud_shots.tscn -- --out=/some/dir --lighting=standard
##
## Writes 1_selection.png, 2_base.png and 3_idle.png to --out (user://hud_shots by default).

const ARMY := ["rhino", "rhino", "lioness", "lioness", "lioness", "rifleman", "rifleman", "rifleman", "rifleman", "kangaroo",
		"kangaroo", "medic", "giraffe"]
const LINE := ["elephant", "rifleman", "rifleman", "rifleman", "hippo", "talon", "talon", "chimp"]
## Frames to wait at most for the unit portraits to be rendered.
const PORTRAIT_WAIT := 400

var out_dir := "user://hud_shots"
var game: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	game = (load("res://scenes/match.tscn") as PackedScene).instantiate()
	add_child(game)
	var frames := 0
	while not game.started:
		await get_tree().process_frame
		frames += 1
		if frames % 20 == 0:
			print("HUD SHOTS waiting for the navmesh, frame %d (%.1f s a frame)" % [frames, get_process_delta_time()])
	print("HUD SHOTS match started")
	await _shots()
	print("HUD SHOTS done -> %s" % out_dir)
	get_tree().quit()


func _shots() -> void:
	var ac: AttackerController = game.player_controller
	var cmd: AttackerCommander = game.commander
	var level: LevelBuilder = game.level
	cmd.supply = 4000.0
	# The army, 45 m out in front of the south gate.
	var gate: Structure = level.gates["south"]
	var front := gate.global_position + Vector3(0, 0, 45)
	var army := []
	for i in ARMY.size():
		var id := cmd.submit({"type": "spawn", "unit": ARMY[i], "spawn": 0})
		var u: AttackerUnit = cmd.units[id]
		var at := front + Vector3((i % 5 - 2) * 4.0, 0.0, (i / 5) * 4.0)
		at.y = LevelBuilder.ground_height(at) + 0.2
		u.global_position = at
		army.append(u)
	ac.groups[0] = army.filter(func(u): return u.type_id == "rhino")
	ac.groups[1] = army.filter(func(u): return u.type_id == "lioness")
	ac.groups[2] = army.filter(func(u): return u.type_id == "rifleman")
	ac.groups[4] = army.duplicate()
	ac.camera_rig.focus(front + Vector3(0, 0, 8))
	var waited := 0
	while UnitPortraits.get_texture(UnitTypes.ORDER[-1], "mug") == null and waited < PORTRAIT_WAIT:
		await get_tree().process_frame
		waited += 1
		if waited % 20 == 0:
			print("HUD SHOTS rendering the portraits, frame %d" % waited)
	print("HUD SHOTS portraits after %d frames" % waited)

	# A mixed selection, the production line, a warning.
	for t in LINE:
		ac.spawn(t)
	ac.recall_group(4)
	ac.warn("South Gate under attack!", UIKit.WARN, gate.global_position)
	await _frames(4)
	await _snap("1_selection")

	# The base: its production.
	for t in LINE:
		ac.spawn(t)
	ac.select_base(0, true)
	await _frames(4)
	await _snap("2_base")

	# Nothing selected, the line done, the warnings gone: the HUD at its leanest.
	ac.recall_group(8)
	ac.camera_rig.focus(front + Vector3(0, 0, 8))
	cmd.production.clear()
	ac.hud.set("_warnings", [])
	await _frames(4)
	await _snap("3_idle")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, file]
	get_viewport().get_texture().get_image().save_png(path)
	print("HUD SHOTS saved %s" % path)
