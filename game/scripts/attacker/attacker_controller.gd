class_name AttackerController
extends CanvasLayer
## Human RTS commander: camera, selection, orders, spawning and the RTS HUD.
## Turns mouse/keyboard input into commands for the AttackerCommander.
##
## LMB click/drag: select · Shift adds · RMB: attack-move / attack target
## Ctrl+RMB: move without stopping to fight · Ctrl+1-5 assign group · 1-5 recall
## Z X C V B N M G H J K L Y U I: spawn units · Tab: cycle spawn point
## F: aim the selected rhinos' cluster bombing (LMB fire, RMB/F cancel) · T: scout formation
## R: aim a selected hippo's smoke screen (LMB fire, RMB/R cancel)

const DRAG_THRESHOLD := 6.0
const CLUSTER_KEY := KEY_F
const SCOUT_KEY := KEY_T
const SMOKE_KEY := KEY_R
const SMOKE_FILL := Color(0.2, 0.9, 0.6, 0.35)
const SMOKE_LINE := Color(0.3, 1.0, 0.7)

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
## Ability aim mode: "" (off), "cluster" (rhinos) or "smoke" (hippos).
## Cluster: preview of every rhino's aim zone and where its bombs will land.
## Smoke: the firing hippo's aim cone, with the band where the curtain will stand.
var _aiming := ""
var _aim_preview: MeshInstance3D
var _aim_mesh: ImmediateMesh
var _smoke_preview: MeshInstance3D
var _smoke_mesh: ImmediateMesh


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
	_build_aim_preview()
	_build_smoke_preview()
	_build_hud()


func restore_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _aiming != "" and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _aiming == "cluster":
				_fire_cluster(event.position)
			else:
				_fire_smoke(event.position)
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_set_aiming("")
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
		if event.physical_keycode == CLUSTER_KEY:
			_set_aiming("cluster" if _aiming != "cluster" and not _ready_rhinos().is_empty() else "")
			return
		if event.physical_keycode == SMOKE_KEY:
			_set_aiming("smoke" if _aiming != "smoke" and not _ready_hippos().is_empty() else "")
			return
		if event.physical_keycode == SCOUT_KEY:
			_alive_selection()
			commander.submit({"type": "scout", "units": selected.map(func(u): return u.unit_id)})
			return
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


func _alive_selection() -> void:
	selected = selected.filter(func(u): return is_instance_valid(u) and u.is_alive())


func _issue_order(pos: Vector2, force_move: bool) -> void:
	_alive_selection()
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


# ---------------------------------------------------------------- rhino cluster bombing

func _ready_rhinos() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.cluster_ready())


func _set_aiming(mode: String) -> void:
	_aiming = mode
	_aim_preview.visible = mode == "cluster"
	_smoke_preview.visible = mode == "smoke"


func _fire_cluster(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var rhinos := _ready_rhinos()
	if hit.is_empty() or rhinos.is_empty():
		return
	commander.submit({"type": "cluster", "units": rhinos.map(func(u): return u.unit_id), "pos": hit.position})
	_ping(hit.position, UIKit.DANGER)


func _build_aim_preview() -> void:
	_aim_mesh = ImmediateMesh.new()
	_aim_preview = MeshInstance3D.new()
	_aim_preview.mesh = _aim_mesh
	_aim_preview.material_override = Mats.unshaded(Color(1.0, 0.55, 0.2), true)
	_aim_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_preview.visible = false
	level.add_child(_aim_preview)


func _update_aim_preview() -> void:
	var rhinos := _ready_rhinos()
	if rhinos.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var hit := _ray(get_viewport().get_mouse_position(), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return
	var aims := RhinoAim.solve(rhinos, hit.position)
	var lift := Vector3.UP * 0.3
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in rhinos.size():
		var r: AttackerUnit = rhinos[i]
		RhinoAim.dashed_circle(_aim_mesh, r.global_position + lift, r.stats.cluster_range, 64)
		RhinoAim.dashed_circle(_aim_mesh, aims[i] + lift, r.stats.cluster_spread, 16)
		_aim_mesh.surface_add_vertex(r.global_position + lift)
		_aim_mesh.surface_add_vertex(aims[i] + lift)
	_aim_mesh.surface_end()


# ---------------------------------------------------------------- hippo smoke screen

func _ready_hippos() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.smoke_ready())


func _fire_smoke(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hippos := _ready_hippos()
	if hit.is_empty() or hippos.is_empty():
		return
	commander.submit({"type": "smoke", "units": hippos.map(func(u): return u.unit_id), "pos": hit.position})
	_ping(hit.position, SMOKE_LINE)


func _build_smoke_preview() -> void:
	_smoke_mesh = ImmediateMesh.new()
	_smoke_preview = MeshInstance3D.new()
	_smoke_preview.mesh = _smoke_mesh
	_smoke_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke_preview.visible = false
	level.add_child(_smoke_preview)


func _update_smoke_preview() -> void:
	var hippos := _ready_hippos()
	if hippos.is_empty():
		_set_aiming("")
		return
	_smoke_mesh.clear_surfaces()
	var hit := _ray(get_viewport().get_mouse_position(), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return
	var hippo := HippoSmoke.pick(hippos, hit.position)
	HippoSmoke.draw_preview(_smoke_mesh, hippo, HippoSmoke.solve(hippo, hit.position),
			Mats.unshaded(SMOKE_FILL, true), Mats.unshaded(SMOKE_LINE, true))


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

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	for type_id in UnitTypes.ORDER:
		var d: Dictionary = UnitTypes.DATA[type_id]
		var key := OS.get_keycode_string(d.hotkey)
		var b := UIKit.button("%s\n%d  [%s]" % [d.name, d.cost, key], 14)
		b.custom_minimum_size = Vector2(132, 50)
		b.tooltip_text = "%s · %d HP · %s" % [d.name, int(d.hp), d.role]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spawn.bind(type_id))
		grid.add_child(b)
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

	var help := UIKit.label("LMB select/drag · RMB attack-move / attack · Ctrl+RMB move · Ctrl+1-5 group · WASD/Q/E/wheel camera\nRhinos: F cluster bombing (LMB fire, RMB cancel) · T scout formation · Hippos: R smoke screen (LMB fire, RMB cancel)",
			13, Color(0.85, 0.85, 0.85, 0.75))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position = Vector2(14, help.position.y - 150)
	root.add_child(help)


func _process(_delta: float) -> void:
	_supply_label.text = "Supply %d" % int(commander.supply)
	_count_label.text = "Army %d / %d   (+%.0f/s)" % [commander.units.size(), AttackerCommander.UNIT_CAP, commander.income]
	_selection_label.text = "Selected %d" % selected.size()
	var rhinos := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_cluster_bomb())
	if not rhinos.is_empty():
		var ready := rhinos.filter(func(u): return u.cluster_ready()).size()
		_selection_label.text += "\nCluster bombs %d/%d [F]" % [ready, rhinos.size()]
		if ready == 0:
			var soonest: float = rhinos.map(func(u): return u.cluster_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
		if rhinos.any(func(u): return commander.is_scouting(u)):
			_selection_label.text += "\nScout formation [T]"
	var hippos := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_smoke())
	if not hippos.is_empty():
		var ready := hippos.filter(func(u): return u.smoke_ready()).size()
		_selection_label.text += "\nSmoke screen %d/%d [R]" % [ready, hippos.size()]
		if ready == 0:
			var soonest: float = hippos.map(func(u): return u.smoke_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
		if hippos.any(func(u): return u.is_overheated()):
			_selection_label.text += "\nGuns overheated"
		else:
			var hottest: float = hippos.map(func(u): return u.heat / u.stats.overheat_time).max()
			_selection_label.text += "\nGuns heat %d%%" % int(hottest * 100.0)
	if _aiming == "cluster":
		_update_aim_preview()
	elif _aiming == "smoke":
		_update_smoke_preview()
	for type_id in _spawn_buttons:
		_spawn_buttons[type_id].disabled = not commander.can_afford(type_id)
