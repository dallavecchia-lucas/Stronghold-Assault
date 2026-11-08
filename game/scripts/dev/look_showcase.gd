extends Node3D
## Stills of how the maps look (the ground, the stronghold, the water, the light) from where players see them:
## standing in the field, from the gun decks, from the RTS camera, close up.
##
##   godot --path game --resolution 1600x900 res://scenes/dev/look_showcase.tscn -- --shots=DIR [--jungle] [--only=a,b]
##
## Each view is drawn for FRAMES frames (`--frames=N`) before it is saved (the GI, the fog and the reflections
## settle), and nothing is drawn in between. The classic field's views first; `--jungle` takes the Jungle Keep's instead.
## `--lighting=standard` (GameConfig) for the standard lighting. `--no-msaa` for a software GPU (lavapipe), which
## leaves the depth texture the water reads empty when it is multisampled. To see what draws what:
## `--env-off=ssr,sdfgi,ssil,ssao,volumetric_fog,glow` switches environment effects off, `--hide=Water,...` hides
## nodes by name, `--probe=x,y` prints the meshes along that pixel's ray.

## [camera, looking at, fov, the camera's height is over the ground, the target's is (default: as the camera's)]
const CLASSIC := {
	"field": [Vector3(8, 1.7, 165), Vector3(0, 8, 84), 68.0],
	"rts": [Vector3(6, 34, 150), Vector3(0, 0, 112), 55.0],
	"bunker": [Vector3(16, 2.2, 104), Vector3(-4, 7.5, 84), 66.0],
	"mountain": [Vector3(150, 46, 170), Vector3(10, 28, 20), 55.0],
	"ground": [Vector3(6, 1.6, 130), Vector3(9, 0, 122), 70.0],
	"track": [Vector3(0.6, 1.5, 150), Vector3(-0.5, 0, 128), 66.0],
	"deck": [Vector3(-8, 8.9, 82.5), Vector3(-30, 1, 150), 70.0],
	"gate": [Vector3(6, 1.8, 93), Vector3(0, 3.0, 80.5), 62.0],
}
const JUNGLE := {
	"river": [Vector3(-30, -0.7, 482), Vector3(90, -1.6, 468), 62.0],
	"river_low": [Vector3(-6, 1.0, 510), Vector3(40, -1.8, 470), 66.0, true, false],
	"bank": [Vector3(10, 2.5, 516), Vector3(13, -1.8, 503), 66.0, true, false],
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
## Environment effects switched off (`--env-off=sdfgi,ssr,ssil,ssao,volumetric_fog,glow`), to see what each does.
var env_off := []
## A pixel (`--probe=x,y`) whose meshes along its ray are printed, nearest first, before the first view is taken.
var probe := Vector2(-1, -1)
## Nodes hidden by name (`--hide=Water,ContactShadows`), to see what each draws.
var hide := []


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
		elif arg == "--no-msaa":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		elif arg.begins_with("--env-off="):
			env_off = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--hide="):
			hide = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--probe="):
			var xy := arg.get_slice("=", 1).split(",")
			probe = Vector2(xy[0].to_float(), xy[1].to_float())
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
	for name in hide:
		for c in level.find_children(name, "", true, false):
			if c is Node3D:
				(c as Node3D).visible = false
	for we in level.find_children("*", "WorldEnvironment", true, false):
		for k in env_off:
			(we as WorldEnvironment).environment.set("%s_enabled" % k, false)
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
		if v.size() < 5 or v[4]:
			at.y += LevelBuilder.ground_height(at)
	cam.fov = v[2]
	cam.global_position = from
	cam.look_at(at)
	if probe.x >= 0.0 and _frame == 1:
		_probe()
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


func _probe() -> void:
	var o := cam.project_ray_origin(probe)
	var d := cam.project_ray_normal(probe)
	var hits := []
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var box := m.global_transform * m.get_aabb()
		var p = box.intersects_ray(o, d)
		if p != null and o.distance_to(p) < 150.0:
			hits.append([o.distance_to(p), m])
	for mmi in level.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		if not (mmi as Node3D).is_visible_in_tree() or mm == null or mm.mesh == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
			continue
		var local := mm.mesh.get_aabb()
		for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
			var box := (mmi as Node3D).global_transform * mm.get_instance_transform(i) * local
			var p = box.intersects_ray(o, d)
			if p != null and o.distance_to(p) < 150.0:
				hits.append([o.distance_to(p), mmi, i])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	for h in hits.slice(0, 16):
		if h[1] is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = h[1]
			var mesh := mmi.multimesh.mesh
			var mats := []
			for s in mesh.get_surface_count():
				var mat: Material = mmi.material_override if mmi.material_override else mesh.surface_get_material(s)
				mats.append(_describe(mat))
			print("PROBE %.1f m %s #%d (%s) %s" % [h[0], mmi.get_path(), h[2], mesh.resource_path, mats])
			continue
		var m: MeshInstance3D = h[1]
		var mats := []
		for s in m.mesh.get_surface_count():
			mats.append(_describe(m.get_active_material(s)))
		print("PROBE %.1f m %s (%s) %s" % [h[0], m.get_path(), m.mesh.resource_path, mats])


func _describe(mat: Material) -> String:
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		return "%s transparency=%d rough=%.3f normal=%s" % [b.resource_name, b.transparency, b.roughness, b.normal_enabled]
	return str(mat)

