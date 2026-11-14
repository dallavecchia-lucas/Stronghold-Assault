class_name MatchUI
extends CanvasLayer
## HUD shared by both sides: vent/gate status, match timer, alert feed, pause menu
## and the end-of-match screen. The attacking player's own HUD (AttackerHUD) shows the vents, gates and clock itself and
## takes the alerts on its warnings panel (attach_attacker_hud).

signal resumed

var level: LevelBuilder
var match_node: Node

var _timer_label: Label
var _top: Control
## Where the alerts go instead of the feed at the top (the attacker's warnings panel): (text, colour, place).
var _alert_sink := Callable()
var _vent_bar: ProgressBar
var _vent_label: Label
var _gate_bars := {}
var _alerts: VBoxContainer
var _pause_panel: Control
var _end_panel: Control
var _end_title: Label
var _end_sub: Label
var _alert_cooldowns := {}
var _clock := 0.0


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS

	var top := UIKit.panel()
	_top = top
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.position.y = 8
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)

	var vent_box := VBoxContainer.new()
	_vent_label = UIKit.label("AIR VENTS", 12, Color(0.75, 0.8, 0.9))
	vent_box.add_child(_vent_label)
	_vent_bar = UIKit.bar(180, 12, UIKit.ACCENT)
	vent_box.add_child(_vent_bar)
	row.add_child(vent_box)

	for side in level.gates:
		var gb := VBoxContainer.new()
		gb.add_child(UIKit.label("%s GATE" % side.to_upper(), 12, Color(0.75, 0.8, 0.9)))
		var bar := UIKit.bar(110, 10, UIKit.WARN)
		gb.add_child(bar)
		row.add_child(gb)
		_gate_bars[side] = bar
		var gate: Structure = level.gates[side]
		gate.damaged.connect(func(_g): _alert_once("gate_" + side, "%s Gate under attack!" % side.capitalize(), UIKit.WARN, gate.global_position))
		gate.destroyed.connect(func(_g): alert("%s Gate has been breached! Rebuilt in %d min" % [side.capitalize(), int(gate.rebuild_time / 60.0)], UIKit.DANGER, gate.global_position))
		gate.rebuilt.connect(func(_g): alert("%s Gate rebuilt" % side.capitalize(), UIKit.GOOD, gate.global_position))
	for v in level.vents:
		v.damaged.connect(func(_v): _alert_once("vents", "The air vents are under attack!", UIKit.DANGER, v.global_position))
		v.destroyed.connect(func(_v): alert("%s destroyed! %d left" % [v.display_name, level.vents_left()], UIKit.DANGER, v.global_position))
	# The helipads: good news for one side is bad news for the other.
	var defending := GameConfig.player_side == GameConfig.PlayerSide.DEFENDER
	for b in level.bases:
		b.sabotaged.connect(func(_b): alert("%s sabotaged!%s" % [b.display_name, "" if defending else " Retake it"],
				UIKit.GOOD if defending else UIKit.DANGER, b.global_position))
		b.retaken.connect(func(_b): alert("%s retaken by the attackers" % b.display_name, UIKit.WARN if defending else UIKit.GOOD, b.global_position))

	_timer_label = UIKit.label("10:00", 26)
	_timer_label.custom_minimum_size.x = 90
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_timer_label)

	_alerts = VBoxContainer.new()
	_alerts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alerts.position.y = 74
	_alerts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alerts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_alerts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alerts)

	_build_pause()
	_build_end()


func _process(delta: float) -> void:
	if not get_tree().paused:
		_clock += delta
	if not is_instance_valid(level):
		return
	var vent_hp := 0.0
	for v in level.vents:
		vent_hp += v.hp
	_vent_bar.value = vent_hp / maxf(level.vents.size() * LevelBuilder.VENT_HP, 1.0)
	_vent_label.text = "AIR VENTS  %d/%d" % [level.vents_left(), level.vents.size()]
	for side in _gate_bars:
		var g: Structure = level.gates[side]
		_gate_bars[side].value = g.hp / g.max_hp
		UIKit.set_bar_color(_gate_bars[side], UIKit.DANGER if g.recently_damaged(1.0) else UIKit.WARN)
	var t: float = maxf(match_node.time_left, 0.0)
	_timer_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60]


## The attacking player's HUD takes over: the status bar at the top goes (it shows the vents, the gates and the clock
## itself) and the alerts go to `sink` (text, colour, place) instead of the feed.
func attach_attacker_hud(sink: Callable) -> void:
	_alert_sink = sink
	_top.visible = false


## An alert in the feed at the top; `at`: where it happened (the attacker's warnings panel rings it on the minimap).
func alert(text: String, color := Color.WHITE, at := Vector3.INF) -> void:
	if _alert_sink.is_valid():
		_alert_sink.call(text, color, at)
		return
	var l := UIKit.label(text, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alerts.add_child(l)
	if _alerts.get_child_count() > 4:
		_alerts.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _alert_once(key: String, text: String, color: Color, at := Vector3.INF) -> void:
	if _clock - float(_alert_cooldowns.get(key, -100.0)) < 10.0:
		return
	_alert_cooldowns[key] = _clock
	alert(text, color, at)


# ---------------------------------------------------------------- pause / end

func _build_pause() -> void:
	_pause_panel = UIKit.full_rect(ColorRect.new())
	(_pause_panel as ColorRect).color = Color(0, 0, 0, 0.55)
	_pause_panel.visible = false
	add_child(_pause_panel)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	_pause_panel.add_child(box)
	var title := UIKit.label("PAUSED", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := UIKit.button("Resume", 22)
	resume.custom_minimum_size = Vector2(260, 48)
	resume.pressed.connect(set_paused.bind(false))
	box.add_child(resume)
	var quit := UIKit.button("Quit to Menu", 22)
	quit.custom_minimum_size = Vector2(260, 48)
	quit.pressed.connect(_quit_to_menu)
	box.add_child(quit)


func _build_end() -> void:
	_end_panel = UIKit.full_rect(ColorRect.new())
	(_end_panel as ColorRect).color = Color(0, 0, 0, 0.6)
	_end_panel.visible = false
	add_child(_end_panel)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	_end_panel.add_child(box)
	_end_title = UIKit.label("", 56)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_sub = UIKit.label("", 22, Color(0.85, 0.85, 0.9))
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_sub)
	var again := UIKit.button("Play Again", 22)
	again.custom_minimum_size = Vector2(260, 48)
	again.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	box.add_child(again)
	var menu := UIKit.button("Main Menu", 22)
	menu.custom_minimum_size = Vector2(260, 48)
	menu.pressed.connect(_quit_to_menu)
	box.add_child(menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _end_panel.visible:
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(p: bool) -> void:
	get_tree().paused = p
	_pause_panel.visible = p
	if p:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		resumed.emit()


func show_end(title: String, subtitle: String, won: bool) -> void:
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", UIKit.GOOD if won else UIKit.DANGER)
	_end_sub.text = subtitle
	_end_panel.visible = true
	_pause_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
