extends Node3D
## Staged shots of the War Elephant on the real map, for recording with Movie Maker:
##
##   godot --path game --resolution 1280x720 --write-movie walk.avi --fixed-fps 30 \
##       res://scenes/dev/elephant_showcase.tscn -- --shot=walk
##
## Shots: walk (one elephant walking, the camera circling it), flak (drones fly in, the cannons
## swing up and shoot them down), missiles (the RTS view: five elephants, two drones, the player
## aims salvos and only as many elephants fire as each kill takes). Each quits when it is over.
## The defenders have no aircraft yet, so TargetDrones stand in for them.

const LENGTH := {"walk": 15.0, "flak": 15.5, "missiles": 16.0}
## Where the shots take place: the open lane in front of the south gate.
const SPOT := Vector3(-8, 0, 152)

var shot := "walk"
var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var hero: AttackerUnit
var elephants: Array = []
var drones: Array[TargetDrone] = []
var t := -1.0
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO  # move start, move end (seconds)
## Camera keys: [time, azimuth (deg, 0 = in front of the hero, 90 = its left), distance,
## height, look height]
var _keys := []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.get_slice("=", 1)
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the garrison holds its fire (the mortar would shell the elephants).
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	cam.position = SPOT + Vector3(0, 30, 40)
	cam.look_at(SPOT)
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	t = 0.0
	match shot:
		"walk":
			# Walks away from the mountain, its sunlit side to the camera, the mountain behind.
			hero = _elephant(SPOT + Vector3(0, 0, -26), PI)
			commander.submit({"type": "move", "units": [hero.unit_id], "pos": SPOT + Vector3(0, 0, 34), "attack": false})
			_keys = [[0.0, 90.0, 13.0, 2.6, 1.8], [4.5, 90.0, 11.0, 2.2, 1.8], [8.5, 40.0, 10.0, 2.0, 1.6],
					[11.5, 22.0, 7.5, 1.3, 1.2], [15.0, -10.0, 8.5, 1.6, 1.4]]
		"flak":
			hero = _elephant(SPOT)
			_elephant(SPOT + Vector3(-8, 0, 7))
			for k in 3:
				var d := _drone(150.0, SPOT + Vector3(-12 + k * 12, 0, -62 - absf(k - 1) * 8))
				d.heading = Vector3(0, 0, 1)
				d.speed = 9.0
		"missiles":
			for k in 5:
				elephants.append(_elephant(SPOT + Vector3((k % 3) * 6 - 6, 0, (k / 3) * 7)))
			# Just outside the cannons' reach, well inside the missiles'.
			var a := _drone(400.0, SPOT + Vector3(4, 0, -32))
			a.radius = 3.0
			a.speed = 3.0
			var b := _drone(220.0, SPOT + Vector3(-8, 0, -34))
			b.radius = 3.0
			b.speed = -3.0
			controller = AttackerController.new()
			controller.level = level
			controller.commander = commander
			add_child(controller)
			# Looking west: the elephants on the left, the drones on the right.
			var rig := controller.camera_rig
			rig.edge_scroll = false
			rig.focus(SPOT + Vector3(0, 0, -17))
			rig.rotation.y = PI * 0.5
			rig.pitch = deg_to_rad(-45.0)
			rig._target_zoom = 40.0
			rig.zoom = 40.0
			_build_cursor()


func _elephant(pos: Vector3, facing := 0.0) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "elephant", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = facing  # 0 faces the mountain (north)
	return u


func _drone(hp: float, centre: Vector3) -> TargetDrone:
	var d := TargetDrone.new()
	d.hp = hp
	d.centre = centre
	d.radius = 0.001
	add_child(d)
	d.global_position = centre + Vector3.UP * d.height
	drones.append(d)
	return d


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	match shot:
		"walk":
			_follow(hero)
		"flak":
			_flak_step()
		"missiles":
			_missile_step()
	if t > LENGTH[shot]:
		get_tree().quit()


## Camera circling the hero, from the keys.
func _follow(u: Node3D) -> void:
	var k := 0
	while k < _keys.size() - 2 and t > _keys[k + 1][0]:
		k += 1
	var a: Array = _keys[k]
	var b: Array = _keys[k + 1]
	var w := smoothstep(a[0], b[0], t)
	var az := deg_to_rad(lerpf(a[1], b[1], w))
	var front := -u.global_basis.z
	var p := u.global_position + front.rotated(Vector3.UP, az) * lerpf(a[2], b[2], w)
	p.y += lerpf(a[3], b[3], w)
	cam.global_position = p
	cam.look_at(u.global_position + Vector3.UP * lerpf(a[4], b[4], w))


func _flak_step() -> void:
	# Drones fly in from the mountain, then circle over the elephants. A straggler follows.
	if t > 5.5 and drones.size() == 3:
		var late := _drone(150.0, SPOT + Vector3(6, 0, -66))
		late.heading = Vector3(0, 0, 1)
		late.speed = 9.0
	for d in drones:
		if is_instance_valid(d) and d.heading != Vector3.ZERO:
			var off := d.global_position - SPOT
			off.y = 0.0
			if off.length() < 19.0:
				d.heading = Vector3.ZERO
				d.centre = SPOT
				d.radius = off.length()
				d.angle = atan2(off.z, off.x)
				d.speed = 8.0 if off.x >= 0.0 else -8.0
	# Low behind the hero looking up past its guns as the drones come in; cut to beside it,
	# looking up at the barrels; cut to both elephants from the sunlit side.
	var shots := [[0.0, Vector3(-5.5, 1.5, 7.5), Vector3(2.0, 7.0, -14.0)],
			[5.5, Vector3(-5.5, 1.5, 7.5), Vector3(2.0, 7.0, -14.0)],
			[5.501, Vector3(-9.5, 1.3, -3.0), Vector3(0.0, 6.0, -3.0)],
			[10.5, Vector3(-9.0, 1.4, -1.0), Vector3(0.0, 6.5, -1.0)],
			[10.501, Vector3(11.0, 1.7, 9.0), Vector3(-4.0, 5.0, 1.0)],
			[15.5, Vector3(12.5, 2.0, 10.5), Vector3(-4.0, 5.5, 1.0)]]
	var k := 0
	while k < shots.size() - 2 and t > shots[k + 1][0]:
		k += 1
	var w := smoothstep(shots[k][0], shots[k + 1][0], t)
	cam.global_position = SPOT + (shots[k][1] as Vector3).lerp(shots[k + 1][1], w)
	cam.look_at(SPOT + (shots[k][2] as Vector3).lerp(shots[k + 1][2], w))


func _missile_step() -> void:
	if t > 1.0 and controller.selected.is_empty():
		controller._set_selection(elephants.duplicate())
	if t > 2.0 and controller._aiming == "" and t < 2.5:
		_key(AttackerController.MISSILE_KEY)
		_move_cursor(_screen(drones[0]), 2.2, 4.0)
	if t > 5.0 and t - get_process_delta_time() <= 5.0:
		_click()
	if t > 5.6 and t - get_process_delta_time() <= 5.6 and is_instance_valid(drones[1]):
		_move_cursor(_screen(drones[1]), 5.6, 7.2)
	if t > 8.0 and t - get_process_delta_time() <= 8.0:
		_click()
	if t > 9.5 and t - get_process_delta_time() <= 9.5:
		_move_cursor(get_viewport().get_visible_rect().size * Vector2(0.62, 0.62), 9.5, 10.5)
	# Keep the cursor on its drone while it flies.
	var pos := _cursor_from.lerp(_cursor_to, smoothstep(_cursor_t.x, _cursor_t.y, t))
	if t > 4.0 and t < 5.6 and is_instance_valid(drones[0]):
		pos = _screen(drones[0])
	elif t > 7.2 and t < 9.5 and is_instance_valid(drones[1]):
		pos = _screen(drones[1])
	get_viewport().warp_mouse(pos)
	_cursor.position = pos


func _screen(n: Node3D) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(Combat.aim_point(n))


func _move_cursor(to: Vector2, start: float, end: float) -> void:
	_cursor_from = _cursor.position
	_cursor_to = to
	_cursor_t = Vector2(start, end)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _cursor.position
	controller._unhandled_input(ev)


## Movie Maker doesn't record the system cursor: draw one.
func _build_cursor() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_cursor)
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 17), Vector2(10, 26),
			Vector2(14, 24), Vector2(10, 15), Vector2(17, 15)])
	arrow.color = Color.WHITE
	var outline := Line2D.new()
	outline.points = arrow.polygon
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.BLACK
	_cursor.add_child(arrow)
	_cursor.add_child(outline)
	_cursor.position = get_viewport().get_visible_rect().size * 0.5
	_cursor_from = _cursor.position
	_cursor_to = _cursor.position
