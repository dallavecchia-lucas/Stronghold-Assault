class_name AttackerHUD
extends Control
## The attacking player's RTS HUD (AttackerController builds it), laid out after the first-draft sketch:
##
##   top left     the production line: a thumbnail for each run of one unit type waiting, its count under it (×N), the
##                front one's build bar; click one to take a unit of it off the line (Shift: the whole run), credits back.
##                The spawn point the units come out at is picked over it (Tab cycles).
##   top centre   spawn credits | air vents destroyed / total (every one of them down wins), the match clock and the gates
##                under it (CreditsBanner)
##   top right    the minimap (Minimap); the transport helicopters' panel (HeloPanel) under it
##   bottom bar   the selection's skills: a tile per key (F G R O P Space) for what that key does for the selection right now
##                (AttackerController.skill_key: the same order of who goes first), its ready count and cooldown; click
##                one for its key. The mode switches (T) under them.
##                · the selected unit's mugshot: its portrait, health, how many, and what they are doing (click: the
##                next type in the selection; Ctrl+click: select only that type; RMB: look at them)
##                · every unit's thumbnail with its production hotkey (click: build one; RMB: take one off the line)
##                · unit groups 1-9 · bridges available, outposts held · the warnings, central command's squid on
##                screen while one is up
##
## The portraits are rendered from the units' own models (UnitPortraits).

const MARGIN := 12.0
const SKILL_SIZE := 66.0
const UNIT_SIZE := 30.0
const GROUP_SIZE := 52.0
const LINE_SIZE := 60.0
const LINE_SHOWN := 6
const MUG_SIZE := 148.0
const MINIMAP := 256.0
const SQUID_SIZE := 96.0
const WARN_SHOWN := 3
## The squid talks this long after a warning; a warning stays on the list this long.
const WARN_LIVE := 7.0
const WARN_KEEP := 40.0
const GROUPS := 9
const CAPTION := Color(0.7, 0.75, 0.85)

## The skills on keys, each key's in the order the key tries them (AttackerController.skill_key):
## [key label, keycode, [[name, glyph (HudGlyph), has (method), ready (method; "": any not crossing or constricting,
## "riders": riders aboard), cooldown (field), cooldown length (stat), aiming mode (AttackerController._aiming)], ...]].
const SKILLS := [
	["F", KEY_F, [
		["Cluster bombing", "reticle", "has_cluster_bomb", "cluster_ready", "cluster_cd", "cluster_cooldown", "cluster"],
		["Strafe run", "strafe", "has_strafe", "strafe_ready", "strafe_cd", "strafe_cooldown", "strafe"],
		["Sneak", "eye", "has_sneak", "sneak_ready", "sneak_cd", "sneak_cooldown", ""],
		["Sniper nest", "tree", "has_nest", "", "", "", "nest"],
		["Dive", "wave", "has_dive", "dive_ready", "dive_cd", "dive_cooldown", ""],
	]],
	["G", KEY_G, [
		["Bombardment", "reticle", "has_bombard", "bombard_ready", "bombard_cd", "bombard_cooldown", "bombard"],
		["Bomb strike", "reticle", "has_bomb", "bomb_ready", "bomb_cd", "bomb_cooldown", "bomb"],
		["Fire blast", "flame", "has_blast", "blast_ready", "blast_cd", "blast_cooldown", ""],
		["Bush trap", "bush", "has_trap", "", "", "", "trap"],
	]],
	["R", KEY_R, [
		["Smoke screen", "cloud", "has_smoke", "smoke_ready", "smoke_cd", "smoke_cooldown", "smoke"],
		["Flash grenade", "burst", "has_flash", "flash_ready", "flash_cd", "flash_cooldown", "flash"],
	]],
	["O", KEY_O, [
		["Missiles", "missile", "has_missiles", "missiles_ready", "missile_cd", "missile_cooldown", "missile"],
	]],
	["P", KEY_P, [
		["Ping", "rings", "has_ping", "ping_ready", "ping_cd", "ping_cooldown", ""],
	]],
	["Space", KEY_SPACE, [
		["Ram", "ram", "has_ram", "ram_ready", "ram_cd", "ram_cooldown", ""],
		["Riders off", "unload", "can_carry", "riders", "", "", ""],
	]],
]

var controller: AttackerController
var commander: AttackerCommander
var level: LevelBuilder

## Built by _ready for the controller (the old HUD's widgets keep their jobs: the showcases read some of them).
var select_rect: Panel
var status_label: Label
var line_button: Button
var dog_button: Button
var gun_button: Button
var scout_button: Button
var bridge_button: Button
var alarm_banner: Button
var aim_label: Label
var help_panel: Control
var spawn_buttons: Array[Button] = []
var minimap: Minimap
var portraits: UnitPortraits

var _banner: CreditsBanner
var _line_panel: Control
var _line_shown := -1
var _line_boxes: Array[Control] = []
var _line_slots: Array[HudSlot] = []
var _line_counts: Array[Label] = []
var _line_idle: Label
var _line_more: Label
var _skill_slots: Array[HudSlot] = []
var _skill_none: Label
var _mug_box: Control
var _mug: HudSlot
var _mug_name: Label
var _mug_hp: ProgressBar
var _mug_hp_text: Label
var _unit_slots := {}  # type_id -> HudSlot
var _group_slots: Array[HudSlot] = []
var _bridge_icon: HudSlot
var _outpost_icon: HudSlot
var _outpost_label: Label
var _outpost_next := 0
var _warn_labels: Array[Label] = []
## [text, colour, place (Vector3.INF: none), when (_clock)], the newest first.
var _warnings: Array = []
var _squid: CommandSquid
## The unit type the mugshot shows (one of the selection's).
var _focus_type := ""
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portraits = UnitPortraits.new()
	add_child(portraits)
	_build_select_rect()
	_build_banner()
	_build_production_line()
	_build_minimap()
	_build_bottom()
	_build_overlays()


# ---------------------------------------------------------------- building

func _build_select_rect() -> void:
	select_rect = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 1.0, 0.4, 0.12)
	sb.border_color = Color(0.3, 1.0, 0.4, 0.9)
	sb.set_border_width_all(1)
	select_rect.add_theme_stylebox_override("panel", sb)
	select_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	select_rect.visible = false
	add_child(select_rect)


func _build_banner() -> void:
	_banner = CreditsBanner.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_banner)


func _build_production_line() -> void:
	var panel := UIKit.panel()
	panel.position = Vector2(MARGIN, MARGIN)
	add_child(panel)
	_line_panel = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(UIKit.label("PRODUCTION", 12, CAPTION))
	col.add_child(UIKit.label("SPAWN AT  [Tab]", 10, CAPTION))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	var group := ButtonGroup.new()
	for i in level.spawn_names.size():
		var b := UIKit.button(level.spawn_names[i], 12)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(62, 24)
		b.pressed.connect(controller.set_spawn_point.bind(i))
		if i < level.spawn_bases.size() and level.spawn_bases[i] != null:
			b.tooltip_text = "%s: a forward spawn point while you hold it" % level.spawn_bases[i].display_name
		else:
			b.tooltip_text = "%s: your main spawn point" % level.spawn_names[i]
		grid.add_child(b)
		spawn_buttons.append(b)
	col.add_child(grid)
	_line_idle = UIKit.label("Nothing in production:\npress a unit's key, or\nclick its thumbnail below", 11, Color(CAPTION, 0.75))
	col.add_child(_line_idle)
	for k in LINE_SHOWN:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(LINE_SIZE, LINE_SIZE)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.clicked.connect(_on_line_clicked.bind(k))
		box.add_child(slot)
		var n := UIKit.label("", 13)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(n)
		box.visible = false
		col.add_child(box)
		_line_boxes.append(box)
		_line_slots.append(slot)
		_line_counts.append(n)
	_line_more = UIKit.label("", 11, CAPTION)
	_line_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_line_more)


func _build_minimap() -> void:
	var frame := UIKit.panel()
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame.grow_vertical = Control.GROW_DIRECTION_END
	frame.offset_left = -MARGIN
	frame.offset_right = -MARGIN
	frame.offset_top = MARGIN
	frame.offset_bottom = MARGIN
	add_child(frame)
	minimap = Minimap.new()
	minimap.controller = controller
	minimap.level = level
	minimap.custom_minimum_size = Vector2(MINIMAP, MINIMAP)
	minimap.tooltip_text = "LMB: look there (drag to pan) · RMB: send the selection there (Ctrl+RMB: move without stopping to fight)"
	frame.add_child(minimap)


## Where the transport helicopters' panel goes: under the minimap.
func helo_panel_top() -> float:
	return MARGIN + MINIMAP + 12.0 + 12.0


func _build_bottom() -> void:
	var bar := UIKit.panel()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = MARGIN
	bar.offset_right = -MARGIN
	bar.offset_top = -MARGIN
	bar.offset_bottom = -MARGIN
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	row.add_child(_build_skills())
	row.add_child(VSeparator.new())
	row.add_child(_build_mugshot())
	row.add_child(VSeparator.new())
	row.add_child(_build_unit_grid())
	row.add_child(VSeparator.new())
	row.add_child(_build_right())


func _build_skills() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 4 * SKILL_SIZE + 3 * 6
	box.add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("SKILLS", 12, CAPTION))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(UIKit.label("F1 controls", 11, Color(CAPTION, 0.6)))
	box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for k in SKILLS.size():
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(SKILL_SIZE, SKILL_SIZE)
		slot.clicked.connect(_on_skill_clicked.bind(k))
		slot.visible = false
		grid.add_child(slot)
		_skill_slots.append(slot)
	_skill_none = UIKit.label("", 12, Color(CAPTION, 0.75))
	_skill_none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_skill_none)
	# The mode switches (T and their buttons), for the units that have them.
	var toggles := HFlowContainer.new()
	toggles.add_theme_constant_override("h_separation", 4)
	toggles.add_theme_constant_override("v_separation", 4)
	box.add_child(toggles)
	line_button = _toggle(toggles, "Lionesses moved together converge into firing lines, 8 abreast, more lines behind", controller.toggle_lines)
	dog_button = _toggle(toggles, "Healing: each dog heals up to 2 hurt units near it until they are full\nMinesweeping: each dog sniffs out the mines round it and digs them out, the minefield's outer rim first", controller.toggle_dog_mode)
	gun_button = _toggle(toggles, "Set the guns up (%d s): armed, they fire (G) but can't move\nDisarm them (%d s) to move again" \
			% [UnitTypes.DATA.mule.setup_time, UnitTypes.DATA.mule.setup_time], controller.toggle_guns)
	scout_button = _toggle(toggles, "Scout formation: the selected rhinos ring the rest of the selection so their anti-air covers it", controller.toggle_scout)
	return box


func _toggle(parent: Control, tip: String, action: Callable) -> Button:
	var b := UIKit.button("", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(action)
	b.visible = false
	parent.add_child(b)
	return b


func _build_mugshot() -> Control:
	_mug_box = HBoxContainer.new()
	_mug_box.add_theme_constant_override("separation", 8)
	_mug = HudSlot.new()
	_mug.custom_minimum_size = Vector2(MUG_SIZE, MUG_SIZE)
	_mug.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_mug.clicked.connect(_on_mug_clicked)
	_mug_box.add_child(_mug)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 210
	info.add_theme_constant_override("separation", 3)
	_mug_name = UIKit.label("", 15)
	_mug_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_mug_name)
	_mug_hp = UIKit.bar(210, 8, UIKit.GOOD)
	info.add_child(_mug_hp)
	_mug_hp_text = UIKit.label("", 11, CAPTION)
	info.add_child(_mug_hp_text)
	status_label = UIKit.label("", 11, Color(0.8, 0.85, 0.9))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 210
	status_label.max_lines_visible = 8
	status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(status_label)
	_mug_box.add_child(info)
	return _mug_box


func _build_unit_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 2)
	for type_id in UnitTypes.ORDER:
		var d: Dictionary = UnitTypes.DATA[type_id]
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(UNIT_SIZE, UNIT_SIZE)
		slot.key_text = OS.get_keycode_string(d.hotkey)
		slot.initials = UnitPortraits.initials(type_id)
		slot.tint = UnitPortraits.role_tint(type_id)
		slot.tooltip_text = "%s  [%s]\n%d credits · %d HP · %s · %.1f s to build\nLMB: build one (Shift: five) · RMB: take one off the line" \
				% [d.name, slot.key_text, d.cost, int(d.hp), d.role, UnitTypes.build_time(type_id)]
		slot.clicked.connect(_on_unit_clicked.bind(type_id))
		grid.add_child(slot)
		_unit_slots[type_id] = slot
	return grid


func _build_right() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 5)
	col.add_child(UIKit.label("UNIT GROUPS   Ctrl+1-9 (or Ctrl+click) save · 1-9 select · twice: look", 11, CAPTION))
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 6)
	col.add_child(groups)
	for i in GROUPS:
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(GROUP_SIZE, GROUP_SIZE)
		slot.key_text = str(i + 1)
		slot.clicked.connect(_on_group_clicked.bind(i))
		groups.add_child(slot)
		_group_slots.append(slot)

	var counters := HBoxContainer.new()
	counters.add_theme_constant_override("separation", 6)
	col.add_child(counters)
	_bridge_icon = _icon("bridge", "Folding bridges: airdrop one across a river (Shift+B), everyone can cross it, the defenders too")
	counters.add_child(_bridge_icon)
	bridge_button = UIKit.button("", 13)
	bridge_button.toggle_mode = true
	bridge_button.focus_mode = Control.FOCUS_NONE
	bridge_button.custom_minimum_size.y = 28
	bridge_button.tooltip_text = "Airdrop a folding bridge across a river: everyone can cross it (the defenders too: its alarm goes off)\nBears, snakes, hippos and elephants swim; the rest but the Mule Artillery and bisons ride across on the rafts hippos and elephants tow (2 each, or a rhino or a giraffe alone)"
	bridge_button.pressed.connect(controller.toggle_bridge)
	counters.add_child(bridge_button)
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	counters.add_child(gap)
	_outpost_icon = _icon("outpost", "")
	_outpost_icon.clicked.connect(_on_outpost_clicked)
	counters.add_child(_outpost_icon)
	_outpost_label = UIKit.label("", 14)
	counters.add_child(_outpost_label)

	var warn_row := HBoxContainer.new()
	warn_row.add_theme_constant_override("separation", 8)
	warn_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(warn_row)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	warn_row.add_child(list)
	for k in WARN_SHOWN:
		var l := UIKit.label("", 15 if k == 0 else 12)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.gui_input.connect(_on_warning_input.bind(k))
		list.add_child(l)
		_warn_labels.append(l)
	_squid = CommandSquid.new()
	_squid.custom_minimum_size = Vector2(SQUID_SIZE, SQUID_SIZE)
	_squid.size_flags_vertical = Control.SIZE_SHRINK_END
	warn_row.add_child(_squid)
	return col


func _icon(kind: String, tip: String) -> HudSlot:
	var s := HudSlot.new()
	s.custom_minimum_size = Vector2(28, 28)
	s.glyph = kind
	s.tint = Color(0.1, 0.12, 0.15, 0.9)
	s.tooltip_text = tip
	return s


func _build_overlays() -> void:
	# Defenders on a bridge: a banner under the top bar while the alarm goes off (click it to look).
	alarm_banner = UIKit.button("", 20)
	alarm_banner.focus_mode = Control.FOCUS_NONE
	alarm_banner.add_theme_color_override("font_color", Color.WHITE)
	var alarm_style := UIKit.panel_style(Color(0.7, 0.06, 0.04, 0.88))
	for st in ["normal", "hover", "pressed"]:
		alarm_banner.add_theme_stylebox_override(st, alarm_style)
	alarm_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	alarm_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	alarm_banner.position.y += CreditsBanner.HEIGHT + CreditsBanner.STRIP_H + 14.0
	alarm_banner.visible = false
	add_child(alarm_banner)

	# The keys, F1 to show (the old HUD had them on screen all the time).
	help_panel = UIKit.panel(Color(0.04, 0.05, 0.07, 0.94))
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	help_panel.visible = false
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help_panel)
	var help := UIKit.label(AttackerController.HELP % AttackerBase.INCOME, 13, Color(0.88, 0.88, 0.9))
	help_panel.add_child(help)

	aim_label = UIKit.label("", 15, AttackerController.MISSILE_LINE)
	aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_label.visible = false
	add_child(aim_label)


# ---------------------------------------------------------------- warnings

## A warning on the panel (the newest on top) with the squid on screen; `at`: where it happened (a ring on the minimap,
## and clicking it looks there).
func warn(text: String, col := UIKit.WARN, at := Vector3.INF) -> void:
	_warnings.push_front([text, col, at, _clock])
	if _warnings.size() > 12:
		_warnings.resize(12)
	if at != Vector3.INF:
		minimap.flash(at, col)
	_squid.tone = col


## The credits flash red: a unit couldn't be paid for.
func flash_credits() -> void:
	_banner.short_flash = 0.6


func _on_warning_input(event: InputEvent, k: int) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and k < _warnings.size():
		var at: Vector3 = _warnings[k][2]
		if at != Vector3.INF:
			controller.camera_rig.focus(at)


# ---------------------------------------------------------------- clicks

func _on_skill_clicked(event: InputEventMouseButton, k: int) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		controller.skill_key(SKILLS[k][1])


func _on_unit_clicked(event: InputEventMouseButton, type_id: String) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		controller.cancel_last(type_id)
		return
	for i in (5 if event.shift_pressed else 1):
		controller.spawn(type_id)


func _on_line_clicked(event: InputEventMouseButton, k: int) -> void:
	var runs := production_runs()
	if k >= runs.size():
		return
	var run: Array = runs[k]
	# One off the end of the run (Shift: all of it), from the back so the indices hold.
	for i in (run[1] if event.shift_pressed else 1):
		controller.cancel_production(run[2] - i)


func _on_group_clicked(event: InputEventMouseButton, i: int) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.ctrl_pressed:
		controller.assign_group(i)
	elif event.double_click:
		controller.recall_group(i, false)
		controller.focus_group(i)
	else:
		controller.recall_group(i, event.shift_pressed)


func _on_mug_clicked(event: InputEventMouseButton) -> void:
	var sel := _selection()
	if sel.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		controller.focus_units(sel.filter(func(u): return u.type_id == _focus_type))
	elif event.ctrl_pressed:
		controller.select_type(_focus_type)
	else:
		var types := _types(sel)
		_focus_type = types[(types.find(_focus_type) + 1) % types.size()]


func _on_outpost_clicked(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT or level.bases.is_empty():
		return
	_outpost_next = (_outpost_next + 1) % level.bases.size()
	controller.camera_rig.focus(level.bases[_outpost_next].global_position)


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	_clock += delta
	var sel := _selection()
	_update_banner()
	_update_line()
	_update_skills(sel)
	_update_mugshot(sel)
	_update_units()
	_update_groups()
	_update_counters()
	_update_warnings()


## The selected units still under orders.
func _selection() -> Array:
	return controller.selected.filter(func(u): return is_instance_valid(u) and u.is_controllable())


## The selection's unit types, in the production order.
static func _types(sel: Array) -> Array:
	var out := []
	for t in UnitTypes.ORDER:
		if sel.any(func(u): return u.type_id == t):
			out.append(t)
	return out


## The type most of `list` are (the first in the production order on a tie).
static func _most_type(list: Array) -> String:
	var best := ""
	var best_n := 0
	for t in UnitTypes.ORDER:
		var n := list.filter(func(u): return u.type_id == t).size()
		if n > best_n:
			best = t
			best_n = n
	return best


## The production line as runs of one type: [[type_id, how many, the index of its last entry]].
func production_runs() -> Array:
	var out := []
	for i in commander.production.size():
		var t: String = commander.production[i].unit
		if not out.is_empty() and out[-1][0] == t:
			out[-1][1] += 1
			out[-1][2] = i
		else:
			out.append([t, 1, i])
	return out


static func _thumb(type_id: String, kind := "thumb") -> Texture2D:
	var tex := UnitPortraits.get_texture(type_id, kind)
	return tex if tex != null else UnitPortraits.get_texture(type_id, "thumb")


func _update_banner() -> void:
	_banner.credits = int(commander.supply)
	_banner.income = commander.income_rate()
	_banner.army = commander.units.size()
	_banner.queued = commander.production.size()
	_banner.army_cap = AttackerCommander.UNIT_CAP
	_banner.vents_total = level.vents.size()
	_banner.vents_down = level.vents.size() - level.vents_left()
	var m: Node = controller.match_ui.match_node if controller.match_ui else null
	_banner.time_left = maxf(float(m.time_left), 0.0) if m != null else -1.0
	_banner.gates = []
	for side in level.gates:
		var g: Structure = level.gates[side]
		_banner.gates.append([String(side).left(1).to_upper(), g.hp / g.max_hp if g.is_alive() else 0.0, g.recently_damaged(1.0)])


func _update_line() -> void:
	var runs := production_runs()
	_line_idle.visible = runs.is_empty()
	var more := 0
	for k in runs.size():
		if k >= LINE_SHOWN:
			more += runs[k][1]
	for k in LINE_SHOWN:
		_line_boxes[k].visible = k < runs.size()
		if k >= runs.size():
			continue
		var t: String = runs[k][0]
		var slot := _line_slots[k]
		slot.texture = _thumb(t)
		slot.initials = UnitPortraits.initials(t)
		slot.tint = UnitPortraits.role_tint(t)
		slot.progress = commander.build_progress() if k == 0 else -1.0
		slot.active = k == 0
		var count := "×%d" % runs[k][1]
		if k == 0:
			if commander.units.size() >= AttackerCommander.UNIT_CAP and commander.build_left <= 0.0:
				count += "  army full"
			else:
				count += "  %.1fs" % commander.build_left
		_line_counts[k].text = count
		slot.tooltip_text = "%s ×%d on the line\nClick: take one off (Shift+click: all %d), credits back" % [UnitTypes.DATA[t].name, runs[k][1], runs[k][1]]
		slot.queue_redraw()
	_line_more.text = "+%d more" % more if more > 0 else ""
	# Fewer runs showing: the panel shrinks back round them (it isn't in a container that would).
	if runs.size() != _line_shown:
		_line_shown = runs.size()
		_line_panel.reset_size()


func _update_skills(sel: Array) -> void:
	var shown := 0
	for k in SKILLS.size():
		var slot := _skill_slots[k]
		var info := _skill_for(SKILLS[k], sel)
		slot.visible = not info.is_empty()
		if info.is_empty():
			continue
		shown += 1
		var ready: int = info.ready
		slot.glyph = info.glyph
		slot.key_text = SKILLS[k][0]
		slot.corner_text = "%d/%d" % [ready, info.total] if info.total > 1 else ""
		slot.cooldown = info.cooldown
		slot.center_text = "%d" % ceili(info.left) if ready == 0 and info.left > 0.0 else ""
		slot.disabled = ready == 0
		slot.active = info.aim != "" and controller.aiming() == info.aim
		var tip := "%s  [%s]\n%d of %d ready" % [info.name, SKILLS[k][0], ready, info.total]
		if ready == 0 and info.left > 0.0:
			tip += " · the next in %d s" % ceili(info.left)
		slot.tooltip_text = tip
		slot.queue_redraw()
	if shown > 0:
		_skill_none.text = ""
	elif sel.is_empty():
		_skill_none.text = "Select units to see their skills"
	else:
		_skill_none.text = "No skills to use: these units fight with their basic attack"
	_skill_none.visible = _skill_none.text != ""


## What key `entry` does for `sel`: the first of its skills some selected unit has ready, else the first one some selected
## unit has (cooling down). {} if none of them has any. {name, glyph, ready, total, cooldown (share left), left (s), aim}.
func _skill_for(entry: Array, sel: Array) -> Dictionary:
	var fallback := {}
	for s in entry[2]:
		var has: Array = sel.filter(func(u): return u.call(s[2]))
		if has.is_empty():
			continue
		var ready := has.filter(func(u): return _is_ready(u, s[3])).size()
		var info := {"name": s[0], "glyph": s[1], "ready": ready, "total": has.size(), "cooldown": 0.0, "left": 0.0, "aim": s[6]}
		if ready == 0 and s[4] != "":
			var left: float = has.map(func(u): return float(u.get(s[4]))).min()
			var full: float = float(has[0].stats.get(s[5], 0.0))
			info.left = maxf(left, 0.0)
			info.cooldown = clampf(left / full, 0.0, 1.0) if full > 0.0 else 0.0
		if ready > 0:
			return info
		if fallback.is_empty():
			fallback = info
	return fallback


static func _is_ready(u: AttackerUnit, ready: String) -> bool:
	match ready:
		"":
			return not u.is_constricting() and not u.is_crossing()
		"riders":
			return not u.riders.is_empty()
	return bool(u.call(ready))


func _update_mugshot(sel: Array) -> void:
	var helo := controller.selected_helo
	_mug.empty = false
	_mug.corner_text = ""
	_mug_hp.visible = true
	_mug_box.tooltip_text = status_label.text
	status_label.tooltip_text = status_label.text
	if sel.is_empty() and is_instance_valid(helo) and helo.is_alive():
		_mug.texture = null
		_mug.initials = "HL"
		_mug.tint = HudSlot.BG
		_mug_name.text = helo.display_name
		_mug_hp.value = helo.health()
		UIKit.set_bar_color(_mug_hp, _health_color(helo.health()))
		_mug_hp_text.text = "%d / %d spaces aboard" % [helo.spaces_used(), HeloCargo.CAPACITY]
		_mug.queue_redraw()
		return
	if sel.is_empty():
		_focus_type = ""
		_mug.empty = true
		_mug.texture = null
		_mug.initials = ""
		_mug_name.text = "No units selected"
		_mug_hp.visible = false
		_mug_hp_text.text = "LMB a unit, or drag a box round some"
		_mug.queue_redraw()
		return
	var types := _types(sel)
	if not _focus_type in types:
		_focus_type = _most_type(sel)
	var of := sel.filter(func(u): return u.type_id == _focus_type)
	var d: Dictionary = UnitTypes.DATA[_focus_type]
	_mug.texture = _thumb(_focus_type, "mug")
	_mug.initials = UnitPortraits.initials(_focus_type)
	_mug.tint = UnitPortraits.role_tint(_focus_type)
	_mug.corner_text = "×%d" % of.size() if of.size() > 1 else ""
	_mug.tooltip_text = "Click: the next type in the selection · Ctrl+click: select only these · RMB: look at them" if types.size() > 1 \
			else "RMB: look at them"
	_mug_name.text = d.name if types.size() == 1 else "%s  (+%d more %s)" % [d.name, types.size() - 1, "type" if types.size() == 2 else "types"]
	var hp := 0.0
	var full := 0.0
	for u in of:
		hp += u.hp
		full += u.stats.hp
	var f := hp / maxf(full, 1.0)
	_mug_hp.value = f
	UIKit.set_bar_color(_mug_hp, _health_color(f))
	if of.size() == 1:
		_mug_hp_text.text = "%d / %d HP · %s" % [int(hp), int(full), d.role]
	else:
		_mug_hp_text.text = "%d units · %d / %d HP · %d selected in all" % [of.size(), int(hp), int(full), sel.size()]
	_mug.queue_redraw()


static func _health_color(f: float) -> Color:
	return UIKit.DANGER if f <= 0.35 else UIKit.WARN if f <= 0.65 else UIKit.GOOD


func _update_units() -> void:
	var queued := {}
	for e in commander.production:
		queued[e.unit] = queued.get(e.unit, 0) + 1
	for type_id in _unit_slots:
		var slot: HudSlot = _unit_slots[type_id]
		slot.texture = _thumb(type_id)
		slot.disabled = not commander.can_queue(type_id)
		slot.corner_text = str(queued[type_id]) if queued.has(type_id) else ""
		slot.queue_redraw()


func _update_groups() -> void:
	var sel := _selection()
	for i in GROUPS:
		var slot := _group_slots[i]
		var list: Array = controller.groups.get(i, []).filter(func(u): return is_instance_valid(u) and u.is_controllable())
		slot.empty = list.is_empty()
		slot.active = not list.is_empty() and list.size() == sel.size() and list.all(func(u): return u in sel)
		if list.is_empty():
			slot.texture = null
			slot.initials = ""
			slot.corner_text = ""
			slot.tooltip_text = "Group %d: empty · Ctrl+%d (or Ctrl+click) saves the selection here" % [i + 1, i + 1]
		else:
			var t := _most_type(list)
			slot.texture = _thumb(t)
			slot.initials = UnitPortraits.initials(t)
			slot.tint = UnitPortraits.role_tint(t)
			slot.corner_text = str(list.size())
			slot.tooltip_text = "Group %d: %d units, mostly %s\n%d or click: select (Shift: add) · twice or double click: look · Ctrl+click: save the selection here" \
					% [i + 1, list.size(), UnitTypes.DATA[t].name, i + 1]
		slot.queue_redraw()


func _update_counters() -> void:
	if RiverCrossing.active():
		bridge_button.text = "×%d  BRIDGES AVAILABLE  [Shift+B]" % commander.bridges_left
		bridge_button.disabled = commander.bridges_left <= 0
	else:
		bridge_button.text = "×0  BRIDGES (no rivers on this map)"
		bridge_button.disabled = true
	var held := level.bases.filter(func(b): return b.controlled)
	_outpost_label.text = "×%d/%d  OUTPOSTS CONTROLLED" % [held.size(), level.bases.size()]
	_outpost_label.add_theme_color_override("font_color", Color.WHITE if held.size() == level.bases.size() else UIKit.WARN)
	var lines := PackedStringArray(["Forward helipads: each one you hold is a spawn point and +%.1f credits/s" % AttackerBase.INCOME])
	for b in level.bases:
		lines.append("%s: %s" % [b.display_name, "held" if b.controlled else "SABOTAGED: stand ground units by it to retake it"])
	lines.append("Click: look at the next one")
	_outpost_icon.tooltip_text = "\n".join(lines)
	_outpost_label.tooltip_text = _outpost_icon.tooltip_text


func _update_warnings() -> void:
	for k in WARN_SHOWN:
		var l := _warn_labels[k]
		if k >= _warnings.size() or _clock - float(_warnings[k][3]) > WARN_KEEP:
			l.text = ""
			l.tooltip_text = ""
			continue
		var w: Array = _warnings[k]
		var age := _clock - float(w[3])
		l.text = w[0]
		l.add_theme_color_override("font_color", w[1])
		l.modulate.a = clampf(1.0 - (age - WARN_LIVE) / (WARN_KEEP - WARN_LIVE), 0.35, 1.0)
		l.tooltip_text = "%s\n%d s ago%s" % [w[0], int(age), " · click: look there" if w[2] != Vector3.INF else ""]
	_squid.talking = not _warnings.is_empty() and _clock - float(_warnings[0][3]) < WARN_LIVE
