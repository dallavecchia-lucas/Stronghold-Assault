extends Node3D
## Staged shots for the Field Manual's clips of the units no showcase films: the Combat Rhino, the Hippo Heavy
## Gunner, the Heavy Lift Helicopter and the defenders' drones, on the showcase field (LevelBuilder), in front of
## the south face. Each shot quits when it is over. Record one with Movie Maker:
##
##   godot --path game --rendering-driver opengl3 --resolution 960x540 --write-movie rhino.avi --fixed-fps 30 \
##       res://scenes/dev/tutorial_shots.tscn -- --shot=rhino_cluster
##
## Shots:
##   rhino_cluster  the RTS view: three rhinos are box-selected, F, the cursor onto the south gun deck, LMB; their
##                  bombs walk over the deck for 8 s
##   rhino_aa       three rhinos under drones flying in over the field: each locks on to one and hammers it
##   hippo_guns     two hippos open up on a knot of Flame Troopers: the spray lands round them, the guns overheat
##   hippo_smoke    the RTS view: a hippo is clicked, R, the cone toward the face, LMB; the curtain goes up
##   heli           a Heavy Lift Helicopter takes bears and an elephant aboard, flies them to the south helipad and
##                  sets them down beside the camp (the dull stretches played faster)
##   drones         a swarm called onto a knot of attackers launches off the roof, dives on them and shoots; the
##                  bears among them shoot back
## The garrison's posts hold fire, so nothing on the face shoots back.
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times, for checking a shot's framing.

const LENGTH := {"rhino_cluster": 15.0, "rhino_aa": 13.0, "hippo_guns": 13.0, "hippo_smoke": 17.0, "heli": 29.0,
		"drones": 16.0}
## The open lane in front of the south gate.
const SPOT := Vector3(-8, 0, 152)

var shot := "rhino_cluster"
var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var t := -1.0
var units: Array = []
var targets: Array = []
var drones: Array = []
var helo: TransportHelo
var fleet: HeloFleet
var bay: DroneBay
var _steps := {}
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
var _cursor_on = null
## The camera's last place and aim, eased toward the shot's (cinematic shots).
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.get_slice("=", 1)
		elif arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	if not LENGTH.has(shot):
		push_error("tutorial_shots: no shot %s (%s)" % [shot, ", ".join(LENGTH.keys())])
		get_tree().quit(1)
		return
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.level = level
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 1200.0
	add_child(cam)
	cam.current = true
	cam.position = SPOT + Vector3(0, 30, 40)
	cam.look_at(SPOT)
	if shot in ["rhino_cluster", "hippo_smoke"]:
		controller = AttackerController.new()
		controller.level = level
		controller.commander = commander
		add_child(controller)
		controller.camera_rig.edge_scroll = false
		_build_cursor()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	t = 0.0
	# The helipads' names float over them for the RTS view; a close camera has no use for them.
	for base in level.bases:
		var lab = base.get("_label")
		if lab:
			lab.visible = controller != null
	match shot:
		"rhino_cluster":
			for x in [-7.0, 0.0, 7.0]:
				units.append(_spawn("rhino", Vector3(x, 0, 116 + absf(x) * 0.4)))
			_rts(Vector3(0, 0, 97), -50.0, 50.0)
		"rhino_aa":
			for p in [Vector3(-6, 0, 2), Vector3(3, 0, -3), Vector3(8, 0, 5)]:
				units.append(_spawn("rhino", SPOT + p))
			for k in 3:
				var d := _drone(260.0, SPOT + Vector3(-14 + k * 14, 0, -58 - absf(k - 1) * 10))
				d.heading = Vector3(0, 0, 1)
				d.speed = 8.0
			_cam_pos = SPOT + Vector3(-12, 1.6, 14)
			_cam_look = SPOT + Vector3(2, 6, -12)
		"hippo_guns":
			units.append(_spawn("hippo", SPOT + Vector3(-3, 0, 4)))
			units.append(_spawn("hippo", SPOT + Vector3(5, 0, 7)))
			for k in 4:
				var tr := FlameTrooper.new()
				_trooper(tr, SPOT + Vector3(-6 + k * 4.5, 0, -18 - (k % 2) * 3.0), SPOT)
				targets.append(tr)
			_cam_pos = SPOT + Vector3(-11, 3.6, 12)
			_cam_look = SPOT + Vector3(0, 1.0, -8)
		"hippo_smoke":
			units.append(_spawn("hippo", Vector3(-2, 0, 138)))
			_rts(Vector3(-2, 0, 122), -34.0, 40.0)
		"heli":
			fleet = HeloFleet.new()
			fleet.base_position = level.spawn_points[0]
			commander.fleet = fleet
			add_child(fleet)
			helo = fleet.helo_at(0)
			var ramp := helo.ramp_point()
			var out := ramp - helo.global_position
			out.y = 0.0
			out = out.normalized()
			for k in 8:
				units.append(_spawn("rifleman", ramp + out * (6.0 + (k / 4) * 2.5) + out.cross(Vector3.UP) * ((k % 4) - 1.5) * 2.2))
			units.append(_spawn("elephant", ramp + out * 13.0))
			commander.submit({"type": "helo_board", "units": units.map(func(u): return u.unit_id), "helo": 0})
			_cam_pos = helo.global_position + out * 34.0 + out.cross(Vector3.UP) * 22.0 + Vector3.UP * 4.0
			_cam_look = helo.global_position + Vector3.UP * 5.0
		"drones":
			bay = DroneBay.new()
			bay.level = level
			bay.auto_calls = false
			add_child(bay)
			var at := SPOT + Vector3(0, 0, -16)
			for p in [["kangaroo", Vector3(-4, 0, 0)], ["medic", Vector3(2, 0, 2)], ["giraffe", Vector3(6, 0, -3)],
					["rifleman", Vector3(-1, 0, 6)], ["rifleman", Vector3(4, 0, 7)]]:
				units.append(_spawn(p[0], at + p[1]))
			_cam_pos = SPOT + Vector3(-14, 2.0, 16)
			_cam_look = at + Vector3(0, 8, -20)


func _spawn(type_id: String, pos: Vector3, facing := 0.0) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
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


## A Flame Trooper standing at `at`, facing `face` (it doesn't fight back).
func _trooper(tr: SquadTrooper, at: Vector3, face: Vector3) -> void:
	add_child(tr)
	tr.global_position = at + Vector3.UP * 0.1
	tr.aim_point = face + Vector3.UP
	tr.following = true
	tr.goal = at


func _rts(focus: Vector3, pitch_deg: float, zoom: float) -> void:
	var rig := controller.camera_rig
	rig.rotation.y = 0.0  # looking north, at the south face
	rig.pitch = deg_to_rad(pitch_deg)
	rig._target_zoom = zoom
	rig.zoom = zoom
	rig.focus(focus)


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta / maxf(Engine.time_scale, 0.001)
	match shot:
		"rhino_cluster":
			_rhino_cluster()
		"rhino_aa":
			_rhino_aa()
		"hippo_guns":
			_hippo_guns()
		"hippo_smoke":
			_hippo_smoke()
		"heli":
			_heli()
		"drones":
			_drones()
	if _cursor:
		_update_cursor()
	if not _snaps.is_empty():
		_snap()
	if t > LENGTH[shot]:
		Engine.time_scale = 1.0
		get_tree().quit()


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%04.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- shots

func _rhino_cluster() -> void:
	var r := _group_rect(units)
	if _at(0.8, "box"):
		_move_cursor(r.position, 0.8, 1.6)
	if _at(1.7, "press"):
		_mouse(MOUSE_BUTTON_LEFT, true)
	if t > 1.7 and t < 2.5:
		_move_cursor(r.end, 1.7, 2.5)
		_motion()
	if _at(2.5, "release"):
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _at(3.2, "key"):
		_key(AttackerController.CLUSTER_KEY)
	var aim := _station("MG_south").global_position + Vector3(4.0, 0.0, 0.0)
	if _at(3.6, "aim"):
		_move_cursor(_screen(aim), 3.6, 5.2)
	if t > 5.2 and t < 5.8:
		_cursor_on = aim
	if _at(5.8, "fire"):
		_cursor_on = null
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _at(6.6, "away"):
		_move_cursor(get_viewport().get_visible_rect().size * Vector2(0.84, 0.8), 6.6, 7.6)


func _rhino_aa() -> void:
	# The drones come in from the mountain and circle over the rhinos once they are close.
	for d in drones:
		if is_instance_valid(d) and d.heading != Vector3.ZERO:
			var off: Vector3 = d.global_position - SPOT
			off.y = 0.0
			if off.length() < 12.0:
				d.heading = Vector3.ZERO
				d.centre = SPOT
				d.radius = maxf(off.length(), 6.0)
				d.angle = atan2(off.z, off.x)
				d.speed = 7.0 if off.x >= 0.0 else -7.0
	# Low behind the rhinos looking up past them as the drones come in; then beside them, up at the sky.
	if t < 6.5:
		_ease_cam(SPOT + Vector3(-12, 1.6, 14), SPOT + Vector3(2, 6, -12), 0.5)
	else:
		_ease_cam(SPOT + Vector3(13, 1.4, 6), SPOT + Vector3(-2, 7.5, -2), 1.2)


func _hippo_guns() -> void:
	if _at(0.6, "attack"):
		for k in units.size():
			commander.submit({"type": "attack", "units": [units[k].unit_id], "target": targets[k * 2].get_path()})
	# Two troopers down, the hippos take the others.
	for k in units.size():
		var u: AttackerUnit = units[k]
		if is_instance_valid(u) and u.order.get("type", "") != "attack":
			for tr in targets:
				if is_instance_valid(tr) and tr.is_alive():
					commander.submit({"type": "attack", "units": [u.unit_id], "target": tr.get_path()})
					break
	# Over the first hippo's shoulder, the troopers ahead of it; then from the open field to the east, raised, the
	# guns and the spray landing round the troopers in one view.
	if t < 6.5:
		_ease_cam(SPOT + Vector3(-11, 3.6, 12), SPOT + Vector3(0, 1.0, -8), 0.6)
	else:
		_ease_cam(SPOT + Vector3(24, 8.0, -7), SPOT + Vector3(-1, 0.5, -7), 1.0)


func _hippo_smoke() -> void:
	var hippo: AttackerUnit = units[0]
	if _at(0.8, "select"):
		_move_cursor(_screen(hippo.global_position + Vector3.UP * 1.2), 0.8, 1.8)
	if _at(2.0, "click"):
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _at(2.8, "key"):
		_key(AttackerController.SMOKE_KEY)
	var aim := hippo.global_position + Vector3(0, 0, -24)
	if _at(3.2, "aim"):
		_move_cursor(_screen(aim), 3.2, 4.8)
	if t > 4.8 and t < 5.6:
		_cursor_on = aim
		_motion()
	if _at(5.6, "fire"):
		_cursor_on = null
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
	if _at(6.4, "away"):
		_move_cursor(get_viewport().get_visible_rect().size * Vector2(0.86, 0.82), 6.4, 7.4)


func _heli() -> void:
	var aboard := units.filter(func(u): return is_instance_valid(u) and u.aboard_helo != null).size()
	# Everyone aboard: off to the south helipad (the base after the citadel's).
	if not _steps.has("fly") and aboard == units.size():
		_steps["fly"] = true
		_steps["fly_t"] = t
		var pad := _south_pad()
		commander.submit({"type": "helo_fly", "helo": 0, "spawn": pad})
	# The dull stretches go faster: the walk to the ramp, the cruise.
	var state := helo.state if is_instance_valid(helo) else -1
	if state != _steps.get("state", -2):
		_steps["state"] = state
		print("TUTORIAL heli t=%.1f state %s, %d/%d aboard" % [t, TransportHelo.State.keys()[state] if state >= 0 else "-", aboard, units.size()])
	if not _steps.has("fly") and t > 2.0 or state == TransportHelo.State.CRUISE:
		Engine.time_scale = 3.0
	elif state == TransportHelo.State.DESCEND:
		Engine.time_scale = 2.0
	else:
		Engine.time_scale = 1.0
	if not is_instance_valid(helo):
		return
	var h := helo.global_position
	var fwd := -helo.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	if not _steps.has("fly"):
		# Off its flank as the units go aboard.
		_ease_cam(h + side * 30.0 - fwd * 18.0 + Vector3.UP * 5.0, h + Vector3.UP * 4.0, 1.0)
	elif state in [TransportHelo.State.SPOOL, TransportHelo.State.CLIMB]:
		_ease_cam(h + side * 34.0 + fwd * 10.0 + Vector3.UP * 2.0, h + Vector3.UP * 6.0, 0.8)
	elif state == TransportHelo.State.CRUISE:
		_ease_cam(h - fwd * 46.0 + side * 18.0 + Vector3.UP * 10.0, h + fwd * 20.0, 1.5)
	else:
		# Down on the pad and the units put down beside the camp.
		var pad: Vector3 = level.spawn_points[_south_pad()]
		_ease_cam(pad + (pad - h).normalized() * 6.0 + side * 40.0 + Vector3.UP * 14.0, h.lerp(pad, 0.5) + Vector3.UP * 4.0, 1.2)


func _drones() -> void:
	if _at(1.0, "call"):
		var res := bay.call_swarm(units[0].global_position)
		print("TUTORIAL drones call: ", res)
	if t < 7.0:
		_ease_cam(SPOT + Vector3(-14, 2.0, 16), SPOT + Vector3(0, 9, -36), 0.6)
	else:
		_ease_cam(SPOT + Vector3(-12, 3.0, 2), SPOT + Vector3(2, 4, -18), 1.2)


## The helipad nearest the south face (its spawn point index).
func _south_pad() -> int:
	var best := -1
	var best_d := INF
	for i in level.spawn_bases.size():
		if level.spawn_bases[i] != null:
			var d: float = (level.spawn_points[i] as Vector3).distance_to(Vector3(0, 0, 100))
			if d < best_d:
				best_d = d
				best = i
	return best


# ---------------------------------------------------------------- the camera and the player's hands

## Eases the camera toward `pos`, looking at `look`, over about `lag` seconds.
func _ease_cam(pos: Vector3, look: Vector3, lag: float) -> void:
	var w := 1.0 - exp(-get_process_delta_time() / maxf(lag, 0.01))
	_cam_pos = _cam_pos.lerp(pos, w)
	_cam_look = _cam_look.lerp(look, w)
	cam.global_position = _cam_pos
	cam.look_at(_cam_look)


func _station(n: String) -> Node3D:
	for s in level.stations:
		if String(s.name) == n:
			return s
	return level.stations[0]


func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _at(at: float, step: String) -> bool:
	return t >= at and _once(step)


func _screen(p: Vector3) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(p)


func _group_rect(list: Array) -> Rect2:
	var r := Rect2(_screen(list[0].global_position + Vector3.UP), Vector2.ZERO)
	for u in list:
		r = r.expand(_screen(u.global_position + Vector3.UP))
	return r.grow(40.0)


func _move_cursor(to: Vector2, start: float, end: float) -> void:
	_cursor_from = _cursor.position
	_cursor_to = to
	_cursor_t = Vector2(start, end)


func _update_cursor() -> void:
	var pos := _cursor_from.lerp(_cursor_to, smoothstep(_cursor_t.x, _cursor_t.y, t))
	if _cursor_on != null:
		pos = _screen(_cursor_on)
		_cursor_from = pos
		_cursor_to = pos
	get_viewport().warp_mouse(pos)
	_cursor.position = pos


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _mouse(button: MouseButton, pressed: bool) -> void:
	get_viewport().warp_mouse(_cursor.position)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _motion() -> void:
	var ev := InputEventMouseMotion.new()
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
