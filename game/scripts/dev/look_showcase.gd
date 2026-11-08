extends Node3D
## Stills of how the maps look (the ground, the stronghold, the water, the light) from where players see them:
## standing in the field, from the gun decks, from the RTS camera, close up.
##
##   godot --path game --resolution 1600x900 res://scenes/dev/look_showcase.tscn -- --shots=DIR [--jungle] [--only=a,b]
##
## Each view is drawn for FRAMES frames (`--frames=N`) before it is saved (the GI, the fog and the reflections
## settle), and nothing is drawn in between. The classic field's views first; `--jungle` takes the Jungle Keep's instead.
## `--lighting=standard` (GameConfig) for the standard lighting.

## [camera, looking at, fov, heights over the ground (camera, target)]
const CLASSIC := {
	"field": [Vector3(34, 1.7, 150), Vector3(0, 7, 84), 68.0],
	"rts": [Vector3(6, 34, 150), Vector3(0, 0, 112), 55.0],
	"bunker": [Vector3(16, 2.2, 104), Vector3(-4, 7.5, 84), 66.0],
	"mountain": [Vector3(150, 46, 170), Vector3(10, 28, 20), 55.0],
	"ground": [Vector3(18, 1.6, 128), Vector3(21, 0, 120), 70.0],
	"deck": [Vector3(-8, 8.9, 82.5), Vector3(-30, 1, 150), 70.0],
}
const JUNGLE := {
	"river": [Vector3(-24, 2.0, 522), Vector3(8, -1.0, 470), 62.0, true],
	"river_low": [Vector3(-6, 1.2, 497), Vector3(30, -1.5, 455), 66.0, true],
	"rts_river": [Vector3(-40, 42, 470), Vector3(-30, 0, 440), 55.0],
	"lake": [Vector3(-590, 13, 200), Vector3(-675, 4, 320), 62.0],
	"keep": [Vector3(210, 120, 330), Vector3(0, 10, 0), 50.0],
	"clearing": [Vector3(60, 1.7, 200), Vector3(10, 8, 110), 66.0, true],
	"forest_floor": [Vector3(-420, 1.7, 230), Vector3(-430, 0.5, 215), 68.0, true],
	"quarry": [Vector3(-398, 26, 8), Vector3(-505, 6, -40), 60.0],
}
const FRAMES := 24

var level: LevelBuilder
var cam: Camera3D
var shots_dir := ""
var views := {}
var _names: Array = []
var _frame := -1
var _frames := FRAMES


func _ready() -> void:
	var jungle := false
	var only := []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
		elif arg == "--jungle":
			jungle = true
		elif arg.begins_with("--only="):
			only = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--frames="):
			_frames = maxi(arg.get_slice("=", 1).to_int(), 1)
	views = JUNGLE if jungle else CLASSIC
	_names = views.keys().filter(func(k): return only.is_empty() or k in only)
	RenderingServer.render_loop_enabled = false
	level = JungleLevel.new() if jungle else LevelBuilder.new()
	add_child(level)
	level.build()
	# A still scene: the garrison holds fire.
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	for t in level.aa_turrets:
		t.process_mode = Node.PROCESS_MODE_DISABLED
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 1600.0
	add_child(cam)
	cam.current = true
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	level.navigation_ready.connect(func(): _frame = 0, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if _frame < 0:
		return
	if _names.is_empty():
		get_tree().quit()
		return
	var v: Array = views[_names[0]]
	var from: Vector3 = v[0]
	var at: Vector3 = v[1]
	if v.size() > 3 and v[3]:
		from.y += LevelBuilder.ground_height(from)
		at.y += LevelBuilder.ground_height(at)
	cam.fov = v[2]
	cam.global_position = from
	cam.look_at(at)
	RenderingServer.render_loop_enabled = true
	_frame += 1
	if _frame == _frames:
		_save(_names[0])
		_names.pop_front()
		_frame = 0


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shots_dir, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot %s" % path)
