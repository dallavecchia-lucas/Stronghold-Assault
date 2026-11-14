class_name AttackerHUD
extends Control
## The attacking player's RTS HUD (AttackerController builds it), after the paper sketch made lean: small islands, each on
## screen only while it has something to show, no text under FONT px.
##
##   top centre    spawn credits | air vents destroyed / total; under it the clock, the gates, the bridges left (click: drop
##                 one) and the outposts held (click: look at the next) (CreditsBanner)
##   top left      the production line, while anything is on it: a thumbnail for each run of one type with ×N, the front
##                 one's build bar; click one to take a unit off (Shift: the run), credits back
##   top right     the minimap (Minimap); the transport helicopters under it (HeloPanel)
##   bottom left   the command card, for what is selected:
##                   units        their own skills, a tile each, then the mugshot (portrait, health, how many, what they are
##                                doing). Click a tile to use that skill; its key's badge is lit on the tile the key fires now
##                                (several skills share a key: AttackerController.skill_key goes down the key's list)
##                   the base     (Backspace: the army's one base, the Mobile Command Citadel) the units to build, with
##                                their keys and costs
##                   a helicopter its mugshot
##                   nothing      a one-line hint
##   bottom right  the unit groups there are, and the warnings while they are fresh, central command's squid with them
##
## The portraits are rendered from the units' own models (UnitPortraits).

const MARGIN := 10.0
## The smallest text anywhere on it (px).
const FONT := 11
const TILE := 48.0
const MUG := 76.0
const INFO_W := 190.0
const LINE_TILE := 44.0
const LINE_SHOWN := 8
const GROUP_TILE := 40.0
const MINIMAP := 200.0
const SQUID := 64.0
const WARN_W := 320.0
const WARN_SHOWN := 3
## The squid talks this long after a warning; a warning stays on screen this long.
const WARN_LIVE := 6.0
const WARN_KEEP := 14.0
const GROUPS := 9
const SKILL_COLS := 5
const BASE_COLS := 7
const CAPTION := Color(0.7, 0.75, 0.85)
## The army's one base.
const BASE_NAME := "Mobile Command Citadel"

## Every skill a unit can have: [id, name, glyph (HudGlyph), key, keycode, has, ready, cooldown (field), cooldown (stat)].
## The skills on one key are in the order the key tries them (AttackerController.skill_key). has: a method, or
## "stat:<flag>" for a flag in the unit's stats. ready: a method; "" any not crossing or constricting; "riders": riders
## aboard; "mode": a mode switch (its state: AttackerController.mode_state). The id is the controller's (use_skill) and the
## aim mode's where it is aimed.
const SKILLS := [
	["cluster", "Cluster bombing", "reticle", "F", KEY_F, "has_cluster_bomb", "cluster_ready", "cluster_cd", "cluster_cooldown"],
	["strafe", "Strafe run", "strafe", "F", KEY_F, "has_strafe", "strafe_ready", "strafe_cd", "strafe_cooldown"],
	["sneak", "Sneak", "eye", "F", KEY_F, "has_sneak", "sneak_ready", "sneak_cd", "sneak_cooldown"],
	["nest", "Sniper nest", "tree", "F", KEY_F, "has_nest", "", "", ""],
	["dive", "Dive", "wave", "F", KEY_F, "has_dive", "dive_ready", "dive_cd", "dive_cooldown"],
	["bombard", "Bombardment", "reticle", "G", KEY_G, "has_bombard", "bombard_ready", "bombard_cd", "bombard_cooldown"],
	["bomb", "Bomb strike", "reticle", "G", KEY_G, "has_bomb", "bomb_ready", "bomb_cd", "bomb_cooldown"],
	["blast", "Fire blast", "flame", "G", KEY_G, "has_blast", "blast_ready", "blast_cd", "blast_cooldown"],
	["trap", "Bush trap", "bush", "G", KEY_G, "has_trap", "", "", ""],
	["smoke", "Smoke screen", "cloud", "R", KEY_R, "has_smoke", "smoke_ready", "smoke_cd", "smoke_cooldown"],
	["flash", "Flash grenade", "burst", "R", KEY_R, "has_flash", "flash_ready", "flash_cd", "flash_cooldown"],
	["missile", "Missiles", "missile", "O", KEY_O, "has_missiles", "missiles_ready", "missile_cd", "missile_cooldown"],
	["ping", "Ping", "rings", "P", KEY_P, "has_ping", "ping_ready", "ping_cd", "ping_cooldown"],
	["ram", "Ram", "ram", "Space", KEY_SPACE, "has_ram", "ram_ready", "ram_cd", "ram_cooldown"],
	["unload", "Riders off", "unload", "Space", KEY_SPACE, "can_carry", "riders", "", ""],
	["lines", "Firing lines", "lines", "T", KEY_T, "stat:line", "mode", "", ""],
	["dogs", "Healing / minesweeping", "cross", "T", KEY_T, "has_dog_modes", "mode", "", ""],
	["guns", "Set up / pack the guns", "gun", "T", KEY_T, "has_setup", "mode", "", ""],
	["scout", "Scout formation", "ring", "T", KEY_T, "stat:scouts", "mode", "", ""],
]
## A mode's state (AttackerController.mode_state), short enough for a tile.
const MODE_SHORT := {"HEALING": "HEAL", "MINESWEEPING": "SWEEP", "SETTING UP": "SETUP", "DISARMING": "PACK"}

var controller: AttackerController
var commander: AttackerCommander
var level: LevelBuilder

## Built by _ready for the controller.
var select_rect: Panel
var status_label: Label
var alarm_banner: Button
var aim_label: Label
var help_panel: Control
var minimap: Minimap
var portraits: UnitPortraits

var _banner: CreditsBanner
var _line_panel: Control
var _line_head: Label
var _line_slots: Array[HudSlot] = []
var _card: Control
var _hint: Label
var _skills_grid: GridContainer
var _skill_slots: Array[HudSlot] = []
var _base_box: Control
var _base_slots := {}  # type_id -> HudSlot
var _mug: HudSlot
var _mug_name: Label
var _mug_hp: ProgressBar
var _mug_hp_text: Label
var _base_text: Label
var _right: Control
var _groups_row: Control
var _group_slots: Array[HudSlot] = []
var _warn_row: Control
var _warn_labels: Array[Label] = []
## [text, colour, place (Vector3.INF: none), when (_clock)], the newest first.
var _warnings: Array = []
var _squid: CommandSquid
## The unit type the mugshot shows (one of the selection's).
var _focus_type := ""
var _outpost_next := 0
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
	_build_card()
	_build_right()
	_build_overlays()


# ---------------------------------------------------------------- building

## A panel pinned to a corner of the screen by `preset`, MARGIN in, that grows out of the corner with what it holds (and
## shrinks back: its offsets stay a point, the minimum size does the rest).
func _island(preset: int) -> PanelContainer:
	var p := UIKit.panel()
	p.set_anchors_preset(preset)
	var right := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var bottom := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	var x := -MARGIN if right else MARGIN
	var y := -MARGIN if bottom else MARGIN
	p.offset_left = x
	p.offset_right = x
	p.offset_top = y
	p.offset_bottom = y
	add_child(p)
	return p


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
	_banner.bridges_pressed.connect(controller.toggle_bridge)
	_banner.outposts_pressed.connect(_look_at_next_outpost)
	add_child(_banner)


func _build_production_line() -> void:
	_line_panel = _island(Control.PRESET_TOP_LEFT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_line_panel.add_child(col)
	_line_head = UIKit.label("", FONT, CAPTION)
	col.add_child(_line_head)
	for k in LINE_SHOWN:
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(LINE_TILE, LINE_TILE)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.clicked.connect(_on_line_clicked.bind(k))
		col.add_child(slot)
		_line_slots.append(slot)
	_line_panel.visible = false


func _build_minimap() -> void:
	var frame := _island(Control.PRESET_TOP_RIGHT)
	var sb := UIKit.panel_style(UIKit.PANEL_BG, 4)
	sb.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	minimap = Minimap.new()
	minimap.controller = controller
	minimap.level = level
	minimap.custom_minimum_size = Vector2(MINIMAP, MINIMAP)
	minimap.tooltip_text = "LMB: look there (drag to pan) · RMB: send the selection there (Ctrl+RMB: move without stopping to fight)"
	frame.add_child(minimap)


## Where the transport helicopters' panel goes: under the minimap.
func helo_panel_top() -> float:
	return MARGIN + MINIMAP + 6.0 + 6.0


func _build_card() -> void:
	_card = _island(Control.PRESET_BOTTOM_LEFT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_card.add_child(row)

	# The selected units' skills.
	_skills_grid = GridContainer.new()
	_skills_grid.columns = SKILL_COLS
	_skills_grid.add_theme_constant_override("h_separation", 4)
	_skills_grid.add_theme_constant_override("v_separation", 4)
	_skills_grid.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_skills_grid)
	for k in SKILLS.size():
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(TILE, TILE)
		slot.glyph = SKILLS[k][2]
		slot.key_text = SKILLS[k][3]
		slot.clicked.connect(_on_skill_clicked.bind(k))
		slot.visible = false
		_skills_grid.add_child(slot)
		_skill_slots.append(slot)

	# The base's production: the units to build.
	_base_box = VBoxContainer.new()
	_base_box.add_theme_constant_override("separation", 4)
	_base_box.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_base_box)
	var grid := GridContainer.new()
	grid.columns = BASE_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_base_box.add_child(grid)
	for type_id in UnitTypes.ORDER:
		var d: Dictionary = UnitTypes.DATA[type_id]
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(TILE, TILE)
		slot.key_text = OS.get_keycode_string(d.hotkey)
		slot.corner_text = str(d.cost)
		slot.initials = UnitPortraits.initials(type_id)
		slot.tint = UnitPortraits.role_tint(type_id)
		slot.tooltip_text = "%s  [%s]\n%d credits · %d HP · %s · %.1f s to build\nLMB: build one (Shift: five) · RMB: take one off the line" \
				% [d.name, slot.key_text, d.cost, int(d.hp), d.role, UnitTypes.build_time(type_id)]
		slot.clicked.connect(_on_unit_clicked.bind(type_id))
		grid.add_child(slot)
		_base_slots[type_id] = slot

	# The mugshot and what goes with it.
	_mug = HudSlot.new()
	_mug.custom_minimum_size = Vector2(MUG, MUG)
	_mug.size_flags_vertical = Control.SIZE_SHRINK_END
	_mug.clicked.connect(_on_mug_clicked)
	row.add_child(_mug)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = INFO_W
	info.add_theme_constant_override("separation", 2)
	info.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(info)
	_mug_name = UIKit.label("", 13)
	_mug_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_mug_name)
	_mug_hp = UIKit.bar(INFO_W, 6, UIKit.GOOD)
	info.add_child(_mug_hp)
	_mug_hp_text = UIKit.label("", FONT, CAPTION)
	info.add_child(_mug_hp_text)
	status_label = UIKit.label("", FONT, Color(0.82, 0.86, 0.92))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = INFO_W
	status_label.max_lines_visible = 3
	status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(status_label)
	_base_text = UIKit.label("", FONT, Color(0.82, 0.86, 0.92))
	_base_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_base_text.custom_minimum_size.x = INFO_W
	info.add_child(_base_text)

	_hint = UIKit.label("Backspace: your base and its production · F1: the keys", FONT, Color(CAPTION, 0.8))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = MARGIN + 4.0
	_hint.offset_right = MARGIN + 4.0
	_hint.offset_top = -MARGIN
	_hint.offset_bottom = -MARGIN
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


func _build_right() -> void:
	_right = _island(Control.PRESET_BOTTOM_RIGHT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_right.add_child(col)
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 4)
	groups.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(groups)
	_groups_row = groups
	for i in GROUPS:
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(GROUP_TILE, GROUP_TILE)
		slot.key_text = str(i + 1)
		slot.clicked.connect(_on_group_clicked.bind(i))
		slot.visible = false
		groups.add_child(slot)
		_group_slots.append(slot)
	var warn := HBoxContainer.new()
	warn.add_theme_constant_override("separation", 6)
	col.add_child(warn)
	_warn_row = warn
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = WARN_W
	list.add_theme_constant_override("separation", 1)
	list.alignment = BoxContainer.ALIGNMENT_END
	warn.add_child(list)
	for k in WARN_SHOWN:
		var l := UIKit.label("", 13 if k == 0 else FONT)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = WARN_W
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.gui_input.connect(_on_warning_input.bind(k))
		list.add_child(l)
		_warn_labels.append(l)
	_squid = CommandSquid.new()
	_squid.custom_minimum_size = Vector2(SQUID, SQUID)
	_squid.size_flags_vertical = Control.SIZE_SHRINK_END
	warn.add_child(_squid)


func _build_overlays() -> void:
	# Defenders on a bridge: a banner under the top bar while the alarm goes off (click it to look).
	alarm_banner = UIKit.button("", 16)
	alarm_banner.focus_mode = Control.FOCUS_NONE
	alarm_banner.add_theme_color_override("font_color", Color.WHITE)
	var alarm_style := UIKit.panel_style(Color(0.7, 0.06, 0.04, 0.88))
	for st in ["normal", "hover", "pressed"]:
		alarm_banner.add_theme_stylebox_override(st, alarm_style)
	alarm_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	alarm_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	alarm_banner.position.y += CreditsBanner.HEIGHT + CreditsBanner.STRIP_H + 8.0
	alarm_banner.visible = false
	add_child(alarm_banner)

	# The keys, F1 to show.
	help_panel = UIKit.panel(Color(0.04, 0.05, 0.07, 0.94))
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	help_panel.visible = false
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help_panel)
	help_panel.add_child(UIKit.label(AttackerController.HELP, 13, Color(0.88, 0.88, 0.9)))

	aim_label = UIKit.label("", 15, AttackerController.MISSILE_LINE)
	aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_label.visible = false
	add_child(aim_label)


# ---------------------------------------------------------------- warnings

## A warning (the newest on top) with the squid on screen; `at`: where it happened (a ring on the minimap, and clicking it
## looks there).
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
		controller.use_skill(SKILLS[k][0])


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
	if controller.base_selected:
		controller.camera_rig.focus(commander.spawn_points[0])
		return
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


func _look_at_next_outpost() -> void:
	if level.bases.is_empty():
		return
	_outpost_next = (_outpost_next + 1) % level.bases.size()
	controller.camera_rig.focus(level.bases[_outpost_next].global_position)


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	_clock += delta
	var sel := _selection()
	_update_banner()
	_update_line()
	_update_card(sel)
	_update_right(sel)


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
	_banner.bridges_left = commander.bridges_left if RiverCrossing.active() else -1
	var held := level.bases.filter(func(b): return b.controlled)
	_banner.outposts_held = held.size()
	_banner.outposts_total = level.bases.size()
	var lines := PackedStringArray(["Outposts (the helipads): each one you hold sees round itself, and the transport helicopters land there"])
	for b in level.bases:
		lines.append("%s: %s" % [b.display_name, "held" if b.controlled else "SABOTAGED (no vision): stand ground units by it to retake it"])
	lines.append("Click: look at the next one")
	_banner.outposts_tip = "\n".join(lines)


func _update_line() -> void:
	var runs := production_runs()
	_line_panel.visible = not runs.is_empty()
	if runs.is_empty():
		return
	var more := 0
	for k in range(LINE_SHOWN, runs.size()):
		more += runs[k][1]
	_line_head.text = "BUILDING" + ("  +%d" % more if more > 0 else "")
	for k in LINE_SHOWN:
		var slot := _line_slots[k]
		slot.visible = k < runs.size()
		if not slot.visible:
			continue
		var t: String = runs[k][0]
		slot.texture = _thumb(t)
		slot.initials = UnitPortraits.initials(t)
		slot.tint = UnitPortraits.role_tint(t)
		slot.corner_text = "×%d" % runs[k][1]
		slot.progress = commander.build_progress() if k == 0 else -1.0
		slot.active = k == 0
		var tip := "%s ×%d on the line" % [UnitTypes.DATA[t].name, runs[k][1]]
		if k == 0:
			tip += " · the next one in %.1f s" % commander.build_left
			if commander.units.size() >= AttackerCommander.UNIT_CAP and commander.build_left <= 0.0:
				tip += " (waiting: the army is full)"
		slot.tooltip_text = tip + "\nClick: take one off (Shift+click: all %d), credits back" % runs[k][1]
		slot.queue_redraw()


# ---------------------------------------------------------------- the command card

func _update_card(sel: Array) -> void:
	var helo := controller.selected_helo
	var base := controller.base_selected
	var helo_on := sel.is_empty() and is_instance_valid(helo) and helo.is_alive()
	_card.visible = base or helo_on or not sel.is_empty()
	_hint.visible = not _card.visible
	if not _card.visible:
		_focus_type = ""
		return
	_skills_grid.visible = not base and not sel.is_empty()
	_base_box.visible = base
	status_label.visible = not base
	_base_text.visible = base
	_mug_hp.visible = not base
	_mug.corner_text = ""
	_mug.texture = null
	_mug.glyph = ""
	if base:
		_update_base()
	elif not sel.is_empty():
		_update_skills(sel)
		_update_mugshot(sel)
	else:
		_mug.initials = "HL"
		_mug.tint = HudSlot.BG
		_mug_name.text = helo.display_name
		_mug_hp.value = helo.health()
		UIKit.set_bar_color(_mug_hp, _health_color(helo.health()))
		_mug_hp_text.text = "%d / %d spaces aboard" % [helo.spaces_used(), HeloCargo.CAPACITY]
		_mug.tooltip_text = ""
	status_label.tooltip_text = status_label.text
	_mug.queue_redraw()


## The base selected: the units to build and what it is.
func _update_base() -> void:
	_mug.glyph = "base"
	_mug.initials = ""
	_mug.tint = Color(0.12, 0.16, 0.14, 0.95)
	_mug.tooltip_text = "Click: look at it"
	_mug_name.text = BASE_NAME
	_mug_hp_text.text = "Your base · +%.1f credits/s" % commander.income_rate()
	var queued := commander.production.size()
	_base_text.text = "Every unit comes out here\n%s" % ("%d on the line" % queued if queued > 0 else "Nothing on the line")
	for type_id in _base_slots:
		var slot: HudSlot = _base_slots[type_id]
		slot.texture = _thumb(type_id)
		slot.disabled = not commander.can_queue(type_id)
		slot.queue_redraw()


## The selection's own skills, a tile each (the scout formation only with other units to ring), lit where its key fires it.
func _update_skills(sel: Array) -> void:
	var has_scouts := sel.any(func(u): return u.stats.get("scouts", false))
	var fires := {}  # key -> the skill id the key uses now
	for k in SKILLS.size():
		var s: Array = SKILLS[k]
		var slot := _skill_slots[k]
		var has: Array = sel.filter(func(u): return _has(u, s[5]))
		if s[0] == "scout" and has.size() == sel.size():
			has = []
		slot.visible = not has.is_empty()
		if has.is_empty():
			continue
		var key: String = s[3]
		if s[6] == "mode":
			var state := controller.mode_state(s[0])
			slot.corner_text = MODE_SHORT.get(state, state)
			slot.cooldown = 0.0
			slot.center_text = ""
			slot.disabled = false
			slot.active = false
			# T: the scout formation first if there are rhinos, else the first of the others.
			if not fires.has(key) and (s[0] == "scout" or not has_scouts):
				fires[key] = s[0]
			slot.tooltip_text = "%s: %s  [T]" % [s[1], state]
		else:
			var ready := has.filter(func(u): return _is_ready(u, s[6])).size()
			var left := 0.0
			var full := 0.0
			if ready == 0 and s[7] != "":
				left = maxf(has.map(func(u): return float(u.get(s[7]))).min(), 0.0)
				full = float(has[0].stats.get(s[8], 0.0))
			slot.corner_text = "%d/%d" % [ready, has.size()] if has.size() > 1 else ""
			slot.cooldown = clampf(left / full, 0.0, 1.0) if full > 0.0 else 0.0
			slot.center_text = "%d" % ceili(left) if left > 0.0 else ""
			slot.disabled = ready == 0
			slot.active = controller.aiming() == s[0]
			if ready > 0 and not fires.has(key):
				fires[key] = s[0]
			slot.tooltip_text = "%s  [%s] · %d of %d ready%s" % [s[1], key, ready, has.size(),
					" · the next in %d s" % ceili(left) if left > 0.0 else ""]
	for k in SKILLS.size():
		var slot := _skill_slots[k]
		if not slot.visible:
			continue
		var s: Array = SKILLS[k]
		slot.key_lit = fires.get(s[3], "") == s[0]
		if not slot.key_lit and fires.has(s[3]):
			slot.tooltip_text += "\n%s uses %s first: click this tile to use this one" % [s[3], _skill_name(fires[s[3]])]
		slot.queue_redraw()


## True if the skill tile `id` is on the card (the selection has that skill).
func skill_shown(id: String) -> bool:
	for k in SKILLS.size():
		if SKILLS[k][0] == id:
			return _skill_slots[k].visible and _card.visible and _skills_grid.visible
	return false


static func _skill_name(id: String) -> String:
	for s in SKILLS:
		if s[0] == id:
			return s[1]
	return id


static func _has(u: AttackerUnit, has: String) -> bool:
	if has.begins_with("stat:"):
		return bool(u.stats.get(has.substr(5), false))
	return bool(u.call(has))


static func _is_ready(u: AttackerUnit, ready: String) -> bool:
	match ready:
		"":
			return not u.is_constricting() and not u.is_crossing()
		"riders":
			return not u.riders.is_empty()
	return bool(u.call(ready))


func _update_mugshot(sel: Array) -> void:
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
	_mug_name.text = d.name if types.size() == 1 else "%s  +%d %s" % [d.name, types.size() - 1, "type" if types.size() == 2 else "types"]
	var hp := 0.0
	var full := 0.0
	for u in of:
		hp += u.hp
		full += u.stats.hp
	var f := hp / maxf(full, 1.0)
	_mug_hp.value = f
	UIKit.set_bar_color(_mug_hp, _health_color(f))
	if sel.size() == 1:
		_mug_hp_text.text = "%d / %d HP" % [int(hp), int(full)]
	else:
		_mug_hp_text.text = "%d / %d HP · %d selected" % [int(hp), int(full), sel.size()]


static func _health_color(f: float) -> Color:
	return UIKit.DANGER if f <= 0.35 else UIKit.WARN if f <= 0.65 else UIKit.GOOD


# ---------------------------------------------------------------- groups and warnings

func _update_right(sel: Array) -> void:
	var any_group := false
	for i in GROUPS:
		var slot := _group_slots[i]
		var list: Array = controller.groups.get(i, []).filter(func(u): return is_instance_valid(u) and u.is_controllable())
		slot.visible = not list.is_empty()
		if list.is_empty():
			continue
		any_group = true
		var t := _most_type(list)
		slot.texture = _thumb(t)
		slot.initials = UnitPortraits.initials(t)
		slot.tint = UnitPortraits.role_tint(t)
		slot.corner_text = str(list.size())
		slot.active = list.size() == sel.size() and list.all(func(u): return u in sel)
		slot.tooltip_text = "Group %d: %d units, mostly %s\n%d or click: select (Shift: add) · twice or double click: look · Ctrl+click: save the selection here" \
				% [i + 1, list.size(), UnitTypes.DATA[t].name, i + 1]
		slot.queue_redraw()
	_groups_row.visible = any_group
	var fresh := 0
	for k in WARN_SHOWN:
		var l := _warn_labels[k]
		var age := _clock - float(_warnings[k][3]) if k < _warnings.size() else INF
		l.visible = age < WARN_KEEP
		if not l.visible:
			continue
		fresh += 1
		var w: Array = _warnings[k]
		l.text = w[0]
		l.add_theme_color_override("font_color", w[1])
		l.modulate.a = clampf(1.0 - (age - WARN_LIVE) / (WARN_KEEP - WARN_LIVE), 0.3, 1.0)
		l.tooltip_text = "%s\n%d s ago%s" % [w[0], int(age), " · click: look there" if w[2] != Vector3.INF else ""]
	_squid.talking = not _warnings.is_empty() and _clock - float(_warnings[0][3]) < WARN_LIVE
	_warn_row.visible = fresh > 0
	_right.visible = any_group or fresh > 0
