class_name AttackerController
extends CanvasLayer
## Human RTS commander: camera, selection, orders, spawning and the RTS HUD.
## Turns mouse/keyboard input into commands for the AttackerCommander.
##
## LMB click/drag: select · Shift adds · RMB: attack-move / attack target
## Ctrl+RMB: move without stopping to fight · Ctrl+1-5 assign group · 1-5 recall
## Z X C V B N M: spawn units · Tab: cycle spawn point

const DRAG_THRESHOLD := 6.0

var level: LevelBuilder
var commander: AttackerCommander
var camera_rig: RTSCamera
var selected: Array = []
var groups := {}
var spawn_index := 0

var _drag_start := Vector2.ZERO
var _mouse_down := false
var _dragging := false
var _select_rect: Panel
var _supply_label: Label
var _count_label: Label
var _selection_label: Label
var _spawn_buttons := {}
var _spawn_point_buttons: Array[Button] = []
var _marker: MeshInstance3D


func _ready() -> void:
	layer = 2
	camera_rig = RTSCamera.new()
	camera_rig.bounds = LevelBuilder.MAP_HALF
	level.add_child(camera_rig)
	camera_rig.camera.current = true
	camera_rig.focus(commander.spawn_points[0] * 0.65)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	commander.unit_died.connect(func(u): selected.erase(u))
	_build_marker()
	_build_hud()


func restore_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_drag_start = event.position
			elif _mouse_down:
				_mouse_down = false
				if _dragging:
					_box_select(Rect2(_drag_start, Vector2.ZERO).expand(event.position), event.shift_pressed)
				else:
					_click_select(event.position, event.shift_pressed)
				_dragging = false
				_select_rect.visible = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_order(event.position, event.ctrl_pressed)
	elif event is InputEventMouseMotion and _mouse_down:
		if not _dragging and event.position.distance_to(_drag_start) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			var r := Rect2(_drag_start, Vector2.ZERO).expand(event.position)
			_select_rect.position = r.position
			_select_rect.size = r.size
			_select_rect.visible = true
	elif event is InputEventKey and event.pressed and not event.echo:
		for type_id in UnitTypes.ORDER:
			if event.physical_keycode == UnitTypes.DATA[type_id].hotkey:
				spawn(type_id)
				return
		if event.is_action_pressed("spawn_cycle"):
			set_spawn_point((spawn_index + 1) % commander.spawn_points.size())
			return
		for i in 5:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				if event.ctrl_pressed:
					groups[i] = selected.duplicate()
				else:
					_set_selection(groups.get(i, []).filter(func(u): return is_instance_valid(u) and u.is_alive()))
				return


func _ray(screen_pos: Vector2, mask: int) -> Dictionary:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return cam.get_world_3d().direct_space_state.intersect_ray(q)


func _click_select(pos: Vector2, add: bool) -> void:
	var hit := _ray(pos, GameConfig.LAYER_ATTACKERS)
	var u = Combat.find_damageable(hit.collider) if not hit.is_empty() else null
	var list := selected.duplicate() if add else []
	if u is AttackerUnit and u.is_alive():
		if u in list:
			list.erase(u)
		else:
			list.append(u)
	_set_selection(list)


func _box_select(rect: Rect2, add: bool) -> void:
	var cam := camera_rig.camera
	var list := selected.duplicate() if add else []
	for u in commander.units.values():
		var p: Vector3 = u.global_position + Vector3.UP
		if cam.is_position_behind(p):
			continue
		if rect.has_point(cam.unproject_position(p)) and not u in list:
			list.append(u)
	_set_selection(list)


func _set_selection(list: Array) -> void:
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	selected = list
	for u in selected:
		u.selected = true


func _issue_order(pos: Vector2, force_move: bool) -> void:
	selected = selected.filter(func(u): return is_instance_valid(u) and u.is_alive())
	if selected.is_empty():
		return
	var ids := selected.map(func(u): return u.unit_id)
	var hit := _ray(pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS)
	if hit.is_empty():
		return
	var target = Combat.find_damageable(hit.collider)
	if target and target.team != GameConfig.TEAM_ATTACKER and target.is_alive() and not force_move:
		commander.submit({"type": "attack", "units": ids, "target": target.get_path()})
		_ping(target.global_position, UIKit.DANGER)
	else:
		commander.submit({"type": "move", "units": ids, "pos": hit.position, "attack": not force_move})
		_ping(hit.position, UIKit.GOOD if force_move else UIKit.WARN)


func spawn(type_id: String) -> void:
	commander.submit({"type": "spawn", "unit": type_id, "spawn": spawn_index})


func set_spawn_point(i: int) -> void:
	spawn_index = i
	for k in _spawn_point_buttons.size():
		_spawn_point_buttons[k].button_pressed = k == i


# ---------------------------------------------------------------- visuals / HUD

func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.2
	t.outer_radius = 1.5
	t.ring_segments = 4
	_marker.mesh = t
	_marker.scale.y = 0.2
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	level.add_child(_marker)


func _ping(pos: Vector3, color: Color) -> void:
	_marker.global_position = pos + Vector3.UP * 0.1
	_marker.material_override = Mats.unshaded(color)
	_marker.visible = true
	_marker.scale = Vector3(1.4, 0.2, 1.4)
	var tw := _marker.create_tween()
	tw.tween_property(_marker, "scale", Vector3(0.4, 0.2, 0.4), 0.35)
	tw.tween_callback(func(): _marker.visible = false)


func _build_hud() -> void:
	var root := UIKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_select_rect = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 1.0, 0.4, 0.12)
	sb.border_color = Color(0.3, 1.0, 0.4, 0.9)
	sb.set_border_width_all(1)
	_select_rect.add_theme_stylebox_override("panel", sb)
	_select_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_rect.visible = false
	root.add_child(_select_rect)

	var bottom := UIKit.panel()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 12
	root.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bottom.add_child(row)

	var info := VBoxContainer.new()
	_supply_label = UIKit.label("", 26, UIKit.WARN)
	_count_label = UIKit.label("", 14, Color(0.8, 0.85, 0.9))
	_selection_label = UIKit.label("", 14, Color(0.8, 0.85, 0.9))
	info.add_child(_supply_label)
	info.add_child(_count_label)
	info.add_child(_selection_label)
	info.custom_minimum_size.x = 150
	row.add_child(info)

	for type_id in UnitTypes.ORDER:
		var d: Dictionary = UnitTypes.DATA[type_id]
		var key := OS.get_keycode_string(d.hotkey)
		var b := UIKit.button("%s\n%d  [%s]" % [d.name, d.cost, key], 14)
		b.custom_minimum_size = Vector2(132, 60)
		b.tooltip_text = "%s · %d HP · %s" % [d.name, int(d.hp), d.role]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spawn.bind(type_id))
		row.add_child(b)
		_spawn_buttons[type_id] = b

	var sp := VBoxContainer.new()
	sp.add_child(UIKit.label("SPAWN AT  [Tab]", 12, Color(0.7, 0.75, 0.85)))
	var sp_row := HBoxContainer.new()
	var bg := ButtonGroup.new()
	for i in level.spawn_names.size():
		var b := UIKit.button(level.spawn_names[i], 15)
		b.toggle_mode = true
		b.button_group = bg
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 34)
		b.pressed.connect(set_spawn_point.bind(i))
		sp_row.add_child(b)
		_spawn_point_buttons.append(b)
	sp.add_child(sp_row)
	row.add_child(sp)
	set_spawn_point(0)

	var help := UIKit.label("LMB select/drag · RMB attack-move / attack · Ctrl+RMB move · Ctrl+1-5 group · WASD/Q/E/wheel camera",
			13, Color(0.85, 0.85, 0.85, 0.75))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position = Vector2(14, help.position.y - 112)
	root.add_child(help)


func _process(_delta: float) -> void:
	_supply_label.text = "Supply %d" % int(commander.supply)
	_count_label.text = "Army %d / %d   (+%.0f/s)" % [commander.units.size(), AttackerCommander.UNIT_CAP, commander.income]
	_selection_label.text = "Selected %d" % selected.size()
	for type_id in _spawn_buttons:
		_spawn_buttons[type_id].disabled = not commander.can_afford(type_id)
