class_name DefenderController
extends CanvasLayer
## Human defender: jumps between stations (number keys / Tab) and shows the FPS HUD.
## Stations are duck-typed nodes with possess(), unpossess(), can_possess(),
## wants_captured_mouse(), get_hud_info(), get_station_position(), station_name and
## a became_unavailable signal.

const THREAT_RADIUS := 45.0
const SWITCH_FADE := 0.18

var level: LevelBuilder
var stations := []
var current = null

var _overview_cam: Camera3D
var _fade: ColorRect
var _crosshair: Control
var _list: VBoxContainer
var _rows := []
var _weapon_label: Label
var _status_label: Label
var _hint_label: Label
var _hp_bar: ProgressBar
var _heat_bar: ProgressBar
var _prompt: Label
var _threat := {}
var _threat_cd := 0.0
var _switching := false


func _ready() -> void:
	layer = 2
	stations = level.stations
	for s in stations:
		s.became_unavailable.connect(_on_station_unavailable)

	_overview_cam = Camera3D.new()
	_overview_cam.far = 900.0
	level.add_child(_overview_cam)
	_overview_cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-55.0), 0, 0)), Vector3(0, 85, 70))

	_build_hud()
	select_station(0, true)


# ---------------------------------------------------------------- switching

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	for i in mini(stations.size(), 10):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select_station(i)
			return
	if event.is_action_pressed("station_next"):
		select_most_threatened()
	elif event is InputEventMouseButton and event.pressed and current != null \
			and current.wants_captured_mouse() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func select_station(i: int, instant := false) -> void:
	if i < 0 or i >= stations.size() or _switching:
		return
	var s = stations[i]
	if s == current:
		return
	if not s.can_possess():
		_flash_prompt("%s is down" % s.station_name)
		return
	if instant:
		_possess(s)
		return
	_switching = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, SWITCH_FADE)
	tw.tween_callback(_possess.bind(s))
	tw.tween_property(_fade, "color:a", 0.0, SWITCH_FADE)
	tw.tween_callback(func(): _switching = false)


## Tab: jump to the available station with the most attackers nearby (skipping the
## current one), so the player can react to wherever the pressure is.
func select_most_threatened() -> void:
	_refresh_threat()
	var best := -1
	var best_score := -1
	var start := stations.find(current)
	for k in stations.size():
		var i := (start + 1 + k) % stations.size()
		var s = stations[i]
		if s == current or not s.can_possess():
			continue
		var score: int = _threat.get(s, 0)
		if score > best_score:
			best_score = score
			best = i
	if best >= 0:
		select_station(best)


func restore_mouse() -> void:
	if current != null and current.wants_captured_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _possess(s) -> void:
	if current != null:
		current.unpossess()
	current = s
	s.possess()
	restore_mouse()
	_prompt.visible = false
	_crosshair.visible = s.wants_captured_mouse()


func _on_station_unavailable(s) -> void:
	if s != current:
		return
	current.unpossess()
	current = null
	_overview_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_crosshair.visible = false
	_prompt.text = "%s is down!  Pick another post (1-%d) or press Tab" % [s.station_name, mini(stations.size(), 10)]
	_prompt.visible = true


func _flash_prompt(text: String) -> void:
	if current == null:
		return
	_prompt.text = text
	_prompt.visible = true
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func(): _prompt.visible = current == null)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var root := UIKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = Control.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)
	for r in [Rect2(-12, -1, 8, 2), Rect2(4, -1, 8, 2), Rect2(-1, -12, 2, 8), Rect2(-1, 4, 2, 8), Rect2(-1, -1, 2, 2)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.85)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.add_child(c)

	var list_panel := UIKit.panel()
	list_panel.position = Vector2(12, 90)
	root.add_child(list_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	list_panel.add_child(_list)
	_list.add_child(UIKit.label("POSTS  ·  Tab = hottest", 13, Color(0.7, 0.75, 0.85)))
	for i in stations.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var key := UIKit.label(str((i + 1) % 10) if i < 10 else " ", 15, UIKit.ACCENT)
		key.custom_minimum_size.x = 14
		var name_l := UIKit.label(stations[i].station_name, 15)
		name_l.custom_minimum_size.x = 210
		var hp := UIKit.bar(60, 8, UIKit.GOOD)
		hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var threat := UIKit.label("", 14, UIKit.DANGER)
		threat.custom_minimum_size.x = 64
		row.add_child(key)
		row.add_child(name_l)
		row.add_child(hp)
		row.add_child(threat)
		_list.add_child(row)
		_rows.append({"name": name_l, "hp": hp, "threat": threat})

	var weapon_panel := UIKit.panel()
	weapon_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	weapon_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	weapon_panel.position -= Vector2(16, 16)
	root.add_child(weapon_panel)
	var wbox := VBoxContainer.new()
	weapon_panel.add_child(wbox)
	_weapon_label = UIKit.label("", 15, Color(0.75, 0.8, 0.9))
	_status_label = UIKit.label("", 28)
	_heat_bar = UIKit.bar(220, 8, UIKit.WARN)
	wbox.add_child(_weapon_label)
	wbox.add_child(_status_label)
	wbox.add_child(_heat_bar)
	wbox.add_child(UIKit.label("HEALTH", 11, Color(0.7, 0.75, 0.85)))
	_hp_bar = UIKit.bar(220, 10, UIKit.GOOD)
	wbox.add_child(_hp_bar)

	_hint_label = UIKit.label("", 14, Color(0.85, 0.85, 0.85, 0.8))
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.position.y -= 14
	root.add_child(_hint_label)

	_prompt = UIKit.label("", 26, UIKit.WARN)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 60
	_prompt.visible = false
	root.add_child(_prompt)

	_fade = UIKit.full_rect(ColorRect.new()) as ColorRect
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


func _refresh_threat() -> void:
	_threat.clear()
	var units := get_tree().get_nodes_in_group("attacker_units")
	for s in stations:
		var n := 0
		var p: Vector3 = s.get_station_position()
		for u in units:
			if u.global_position.distance_squared_to(p) < THREAT_RADIUS * THREAT_RADIUS:
				n += 1
		_threat[s] = n


func _process(delta: float) -> void:
	_threat_cd -= delta
	if _threat_cd <= 0.0:
		_threat_cd = 0.25
		_refresh_threat()
	for i in stations.size():
		var s = stations[i]
		var row: Dictionary = _rows[i]
		var alive: bool = s.can_possess()
		row.hp.value = s.hp / s.max_hp
		var n: int = _threat.get(s, 0)
		row.threat.text = ("%d near" % n) if n > 0 else ""
		var col := UIKit.ACCENT if s == current else (Color(0.5, 0.5, 0.5) if not alive else Color.WHITE)
		row.name.add_theme_color_override("font_color", col)

	if current != null:
		var info: Dictionary = current.get_hud_info()
		_weapon_label.text = "%s  ·  %s" % [current.station_name, info.weapon]
		_status_label.text = info.status
		_hint_label.text = info.hint
		_hp_bar.value = info.hp
		_heat_bar.visible = info.has("heat")
		if info.has("heat"):
			_heat_bar.value = info.heat
			UIKit.set_bar_color(_heat_bar, UIKit.DANGER if info.heat > 0.75 else UIKit.WARN)
	else:
		_weapon_label.text = "No post"
		_status_label.text = "—"
		_hint_label.text = "Number keys or Tab to take over a post"
		_heat_bar.visible = false
