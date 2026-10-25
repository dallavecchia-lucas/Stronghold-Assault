extends Node3D
## Staged run of the Bison Field Gun's bombardment on the real map, aimed the way a player aims it
## (the RTS view, this node working the mouse and keys): bisons out in the south field shell the
## south face's gun deck and roof from beyond the rifles' reach.
##
##   single   one bison is selected, G, the cursor on the gate machine gun on the gun deck, LMB;
##            after its reload (cut short here), the same bison onto the mortar on the roof
##   group    four bisons are box-selected, G: their shells cluster round the cursor along the deck
##            instead of piling onto one spot, then (reloaded) round the mortar on the roof
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/bison_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie bison.avi \
##       --fixed-fps 30 res://scenes/dev/bison_showcase.tscn
##
## --test prints where the shells land and what they hit, and checks it at the end (BISON
## SHOWCASE PASS / FAIL). The garrison's posts hold fire, and their machines don't get repaired.

## The bisons: the lone one, then the group, out in the south field. Their shells fly 60-75 m.
const SOLO_AT := Vector3(-14.0, 0.0, 142.0)
const GROUP_AT := [Vector3(4.0, 0.0, 136.0), Vector3(10.0, 0.0, 136.0), Vector3(7.0, 0.0, 142.0),
		Vector3(13.0, 0.0, 142.0)]
## The south deck's riflemen the group aims between (LevelBuilder.RIFLE_POSTS: south bays 2 and 4).
const DECK_SOLDIERS := ["Soldier_south_2", "Soldier_south_4"]
## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [2.5, "solo_deck"], [15.0, "solo_roof"], [27.5, "group_deck"],
		[40.0, "group_roof"], [52.5, "outro"], [55.0, "end"]]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var solo: AttackerUnit
var group: Array = []
var mg: Node3D
var mortar: Node3D
var deck_soldiers: Array = []
var t := -1.0
var phase := ""
var test := false
var _phase_t := 0.0
var _steps := {}
var _hp_before := {}
var _checks: Array[String] = []
var _failed := false
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
## Cursor follows this world point (when set) instead of moving on its own.
var _cursor_on = null
var _pan_from := Vector3.ZERO
var _pan_to := Vector3.ZERO
var _pan_t := Vector2.ZERO
var _caption: Label
var _keycap: Label
var _status: Label


func _ready() -> void:
	test = "--test" in OS.get_cmdline_user_args()
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the garrison holds its fire (the mortar would shell the bisons).
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
	for s in level.stations:
		match String(s.name):
			"MG_south": mg = s
			"Artillery": mortar = s
		if String(s.name) in DECK_SOLDIERS:
			deck_soldiers.append(s)
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	var rig := controller.camera_rig
	rig.edge_scroll = false
	rig.rotation.y = 0.0  # looking north, at the south face
	rig.pitch = deg_to_rad(-50.0)
	rig._target_zoom = 46.0
	rig.zoom = 46.0
	rig.focus(SOLO_AT + Vector3(10, 0, -12))
	_pan_from = rig.position
	_pan_to = rig.position
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	solo = _bison(SOLO_AT)
	for p in GROUP_AT:
		group.append(_bison(p))
	for n in [mg, mortar] + deck_soldiers:
		print("BISON %s at %s, %.0f m from the lone bison" % [n.name, n.global_position, _flat(n.global_position, SOLO_AT)])
	t = 0.0


func _bison(pos: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "bison_gun", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = 0.0  # faces the mountain (north)
	return u


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	var k := 0
	while k < SCRIPT.size() - 1 and t >= SCRIPT[k + 1][0]:
		k += 1
	if SCRIPT[k][1] != phase:
		phase = SCRIPT[k][1]
		_phase_t = 0.0
		_steps.clear()
		if phase == "end":
			_finish()
			return
	_phase_t += delta
	match phase:
		"intro":
			_say("Bison Field Gun · Bombardment", "One heavy shell every 40 s, up to 80 m: onto the gun decks and roofs")
		"solo_deck":
			_bombard_step([solo], solo, Combat.aim_point(mg) - Vector3.UP * 1.2, "One bison → the gate machine gun on the gun deck", mg, false)
		"solo_roof":
			_bombard_step([solo], solo, mortar.global_position, "40 s later: the same bison → the mortar on the roof", mortar, true)
		"group_deck":
			_bombard_step(group, null, _deck_aim(), "Four bisons → the gun deck: the shells spread along it", null, false)
		"group_roof":
			_bombard_step(group, null, mortar.global_position + Vector3(-4.0, 0.0, 0.0), "40 s later: the four → the roof", null, true)
		"outro":
			_say("", "")
	_update_cursor()
	_update_pan(delta)
	_update_status()


## One bombardment the way the player does it: select (click the lone bison, or drag a box round
## the group), G, pan the view up to the face, the cursor onto `aim`, LMB; then watch the shells
## land. `reload` cuts the reload short first (the clip skips the 40 s wait).
func _bombard_step(units: Array, click: AttackerUnit, aim: Vector3, caption: String, watch: Node3D, reload: bool) -> void:
	var rig := controller.camera_rig
	var centre := Vector3.ZERO
	for u in units:
		centre += u.global_position
	centre /= units.size()
	if _once("start"):
		_say(caption, "")
		if reload:
			for u in units:
				u.bombard_cd = 0.0
		controller._set_selection([])
		_pan(centre + Vector3(0, 0, -10), 0.0, 1.0)
		_cursor_on = null
	if _phase_at(1.2, "select"):
		if click:
			_move_cursor(_screen(click.global_position + Vector3.UP), 1.2, 2.0)
		else:
			var r := _group_rect(units)
			_move_cursor(r.position, 1.2, 1.8)
	if click == null and _phase_at(1.9, "press"):
		_mouse_button(true)
	if click == null and _phase_t > 1.9 and _phase_t < 2.6:
		var r := _group_rect(units)
		_move_cursor(r.end, 1.9, 2.6)
		_mouse_motion()
	if _phase_at(2.6, "release"):
		if click:
			_mouse_button(true)
		_mouse_button(false)
	if _phase_at(3.2, "key"):
		_key(AttackerController.BOMBARD_KEY)
		_keycap.text = "G"
		_keycap.visible = true
	if _phase_at(3.9, "pan"):
		_keycap.visible = false
		_pan(Vector3(aim.x, 0.0, aim.z + 20.0), 3.9, 6.0)
	if _phase_at(4.6, "aim"):
		_cursor_on = null
		_move_cursor(_screen(aim), 4.6, 6.4)
	if _phase_t > 6.4 and _phase_t < 7.2:
		_cursor_on = aim  # keep it on the target while the view settles
	if _phase_at(7.2, "fire"):
		_cursor_on = null
		_mouse_click_fire()
		_keycap.text = "LMB"
		_keycap.visible = true
		for n in [mg, mortar] + deck_soldiers:
			_hp_before[n] = n.hp
		var aims := RhinoAim.bombard(units, aim)
		for i in units.size():
			print("BISON %s: %s -> aim %s (%.0f m)" % [phase, units[i].name, aims[i], _flat(aims[i], units[i].global_position)])
		_check_spread(aims, units[0].stats.bombard_splash * RhinoAim.BOMBARD_SPACING, aim)
	if _phase_at(7.9, "keyoff"):
		_keycap.visible = false
	if _phase_at(9.0, "away"):
		_move_cursor(get_viewport().get_visible_rect().size * Vector2(0.8, 0.85), 9.0, 10.0)
	if _phase_at(11.2, "result"):
		_report(watch)


## Halfway between the two riflemen on the south deck: the group's shells spread along the deck
## to them.
func _deck_aim() -> Vector3:
	return (deck_soldiers[0].global_position + deck_soldiers[1].global_position) * 0.5


func _check_spread(aims: Array[Vector3], spacing: float, target: Vector3) -> void:
	for i in aims.size():
		for j in range(i + 1, aims.size()):
			_check(_flat(aims[i], aims[j]) >= spacing * 0.9, "%s: shells %d and %d %.1f m apart (>= %.1f)" % [phase, i, j, _flat(aims[i], aims[j]), spacing * 0.9])
	var up := aims.filter(func(p): return absf(p.y - target.y) < 1.0).size()
	_check(up == aims.size(), "%s: %d/%d shells on the target's level (y %.1f)" % [phase, up, aims.size(), target.y])


func _report(watch: Node3D) -> void:
	for n in _hp_before:
		if n.hp < _hp_before[n]:
			print("BISON %s: %s %.0f -> %.0f HP" % [phase, n.name, _hp_before[n], n.hp])
	match phase:
		"solo_deck", "solo_roof":
			_check(watch.hp < _hp_before[watch], "%s: %s hit (%.0f -> %.0f)" % [phase, watch.name, _hp_before[watch], watch.hp])
		"group_deck":
			var hit := deck_soldiers.filter(func(s): return s.hp < _hp_before[s]).size()
			_check(hit == deck_soldiers.size(), "%s: %d/%d deck riflemen hit" % [phase, hit, deck_soldiers.size()])
		"group_roof":
			_check(mortar.hp < _hp_before[mortar] or not mortar.is_alive(), "%s: mortar hit" % phase)


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	for c in _checks:
		print("BISON CHECK ", c)
	print("BISON SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit()


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _screen(p: Vector3) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(p)


func _group_rect(units: Array) -> Rect2:
	var r := Rect2(_screen(units[0].global_position + Vector3.UP), Vector2.ZERO)
	for u in units:
		r = r.expand(_screen(u.global_position + Vector3.UP))
	return r.grow(48.0)


func _move_cursor(to: Vector2, start: float, end: float) -> void:
	_cursor_from = _cursor.position
	_cursor_to = to
	_cursor_t = Vector2(start, end)


func _update_cursor() -> void:
	var pos := _cursor_from.lerp(_cursor_to, smoothstep(_cursor_t.x, _cursor_t.y, _phase_t))
	if _cursor_on != null:
		pos = _screen(_cursor_on)
		_cursor_from = pos
		_cursor_to = pos
	get_viewport().warp_mouse(pos)
	_cursor.position = pos


## Pans the view (as with WASD) to `to` between `start` and `end` (phase seconds).
func _pan(to: Vector3, start: float, end: float) -> void:
	_pan_from = controller.camera_rig.position
	_pan_to = to
	_pan_t = Vector2(start, end)


func _update_pan(_delta: float) -> void:
	var rig := controller.camera_rig
	var w := smoothstep(_pan_t.x, _pan_t.y, _phase_t) if _pan_t.y > _pan_t.x else 1.0
	var p := _pan_from.lerp(_pan_to, w)
	rig.position.x = p.x
	rig.position.z = p.z


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _mouse_button(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _mouse_motion() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _mouse_click_fire() -> void:
	get_viewport().warp_mouse(_cursor.position)
	_mouse_button(true)


# ---------------------------------------------------------------- overlay

func _say(title: String, sub: String) -> void:
	_caption.text = title if sub == "" else "%s\n%s" % [title, sub]
	_caption.visible = title != ""


func _update_status() -> void:
	var lines := []
	for n in [mg, mortar] + deck_soldiers:
		var label: String = n.station_name if n.get("station_name") else String(n.name)
		lines.append("%s  %d / %d" % [label, int(n.hp), int(n.max_hp)])
	_status.text = "\n".join(lines)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_caption = UIKit.label("", 22, Color.WHITE)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y = 64
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_caption)
	_keycap = UIKit.label("", 30, Color(1.0, 0.85, 0.3))
	_keycap.add_theme_color_override("font_outline_color", Color.BLACK)
	_keycap.add_theme_constant_override("outline_size", 8)
	_keycap.position = Vector2(40, 300)
	_keycap.visible = false
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_keycap)
	_status = UIKit.label("", 15, Color(1.0, 0.75, 0.65))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 64)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)
	# Movie Maker doesn't record the system cursor: draw one.
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


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
