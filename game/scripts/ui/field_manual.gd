class_name FieldManual
extends Control
## The Field Manual, the game's tutorial: every unit on both sides, what it is for and its skills, with video of
## it in action. The pages are FieldManualData's; the videos are clips cut from the showcase videos in media/
## (tools/video/cut_tutorial_clips.py).
##
## Two ways in: its own scene from the main menu (scenes/field_manual.tscn, `standalone`: closing it goes back
## to the menu), or over the paused match from the pause menu (FieldManual.open_over: closing it frees it).
##
## On the left the side's units; on the right the open one's video (its clips play in turn, round and round),
## what it is and its skills. Clicking a skill plays the clip that shows it.
## Keys: up / down the unit, left / right the clip, Tab the other side, Esc closes.

signal closed

const ACCENT := Color(1.0, 0.42, 0.18)
const COOL := Color(0.45, 0.78, 1.0)
const TEXT := Color(0.9, 0.93, 1.0)
const DIM := Color(0.55, 0.64, 0.78)
const CARD := Color(0.03, 0.06, 0.1, 0.78)
const VIDEO_SIZE := Vector2(640, 360)
const MENU_SCENE := "res://scenes/main_menu.tscn"

## The manual's own scene (from the main menu): opaque, and closing it goes back to the menu.
@export var standalone := false
## Which side's pages are open: the attackers' or the defenders'.
var attacker := false

var _font: Font
var _font_bold: Font
var _pages: Array = []
var _page := 0
var _clips: Array = []
var _clip := 0
var _leaving := false

var _tabs: Array[Button] = []
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _unit_buttons: Array[Button] = []
var _video: VideoStreamPlayer
var _no_video: Label
var _progress: ColorRect
var _caption: Label
var _chips: HBoxContainer
var _name: Label
var _role: Label
var _meta: GridContainer
var _about: Label
var _skills: GridContainer
var _skills_scroll: ScrollContainer
var _cards: Array = []  # [PanelContainer, clip id]
var _fade: ColorRect


## Opens the manual over `parent` (the paused match's HUD), on the given side's pages. It runs while the game is
## paused, and frees itself when closed.
static func open_over(parent: Node, attacker_side: bool) -> FieldManual:
	var m := FieldManual.new()
	m.attacker = attacker_side
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(m)
	return m


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font_bold = load("res://assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf")
	_font = load("res://assets/fonts/jetbrains_mono/JetBrainsMono-Medium.ttf")
	if standalone:
		attacker = GameConfig.player_side == GameConfig.PlayerSide.ATTACKER
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = false
	_build()
	_show_side(attacker)
	if standalone:
		_fade = UIKit.full_rect(ColorRect.new()) as ColorRect
		_fade.color = Color.BLACK
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fade)
		create_tween().tween_property(_fade, "color:a", 0.0, 0.5)


func _process(_delta: float) -> void:
	if _video == null or _progress == null:
		return
	var length := _video.get_stream_length() if _video.stream != null else 0.0
	var f := clampf(_video.stream_position / length, 0.0, 1.0) if length > 0.0 else 0.0
	_progress.size.x = (_progress.get_parent() as Control).size.x * f


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed():
		return
	if event.is_action("ui_cancel") or event.is_action("pause"):
		close()
	elif event.is_action("ui_up"):
		_open_page(posmod(_page - 1, _pages.size()))
	elif event.is_action("ui_down"):
		_open_page(posmod(_page + 1, _pages.size()))
	elif event.is_action("ui_left"):
		_play(_clip - 1)
	elif event.is_action("ui_right"):
		_play(_clip + 1)
	elif event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
		_show_side(not attacker)
	else:
		return
	get_viewport().set_input_as_handled()


func close() -> void:
	if _leaving:
		return
	_leaving = true
	_video.stop()
	if standalone:
		_fade.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, 0.35)
		tw.tween_callback(func(): get_tree().change_scene_to_file(MENU_SCENE))
		return
	closed.emit()
	queue_free()


# --- pages --------------------------------------------------------------------------------------------

func _show_side(attacker_side: bool) -> void:
	attacker = attacker_side
	_tabs[0].set_pressed_no_signal(not attacker)
	_tabs[1].set_pressed_no_signal(attacker)
	_pages = FieldManualData.pages(attacker)
	for b in _unit_buttons:
		b.queue_free()
	_unit_buttons.clear()
	for i in _pages.size():
		var b := _unit_button(_pages[i], i == 0)
		b.pressed.connect(_open_page.bind(i))
		_list.add_child(b)
		_unit_buttons.append(b)
	_list_scroll.scroll_vertical = 0
	_open_page(0)


func _open_page(i: int) -> void:
	_page = i
	for j in _unit_buttons.size():
		_unit_buttons[j].set_pressed_no_signal(j == i)
	_scroll_to(_unit_buttons[i])
	var p: Dictionary = _pages[i]
	_name.text = String(p.name).to_upper()
	_role.text = p.role
	_about.text = p.about
	for c in _meta.get_children():
		c.queue_free()
	for m in p.meta:
		_meta.add_child(_label(String(m[0]).to_upper(), 12, DIM, _font))
		_meta.add_child(_label(m[1], 14, TEXT, _font_bold))

	for c in _cards:
		c[0].queue_free()
	_cards.clear()
	for s in p.skills:
		var card := _skill_card(s)
		_skills.add_child(card)
		_cards.append([card, s.get("clip", "")])
	_skills_scroll.scroll_vertical = 0

	_clips = p.clips
	for c in _chips.get_children():
		c.queue_free()
	for k in _clips.size():
		var chip := _chip(str(k + 1))
		chip.pressed.connect(_play.bind(k))
		_chips.add_child(chip)
	_play(0)


## Brings the open unit's button into view in the list, once the list has been laid out.
func _scroll_to(b: Button) -> void:
	await get_tree().process_frame
	if is_instance_valid(b) and b.is_inside_tree():
		_list_scroll.ensure_control_visible(b)


## Plays the open page's clip `i` (wrapping round); when it ends, the next one plays.
func _play(i: int) -> void:
	if _clips.is_empty():
		return
	_clip = posmod(i, _clips.size())
	var id: String = _clips[_clip][0]
	var path := FieldManualData.clip_path(id)
	var stream: VideoStream = load(path) if ResourceLoader.exists(path) else null
	_video.stop()
	_video.stream = stream
	_no_video.visible = stream == null
	if stream != null:
		_video.play()
	_caption.text = _clips[_clip][1]
	for k in _chips.get_child_count():
		(_chips.get_child(k) as Button).set_pressed_no_signal(k == _clip)
	for c in _cards:
		_light_card(c[0], c[1] == id)


func _play_id(id: String) -> void:
	for k in _clips.size():
		if _clips[k][0] == id:
			_play(k)
			return


func _on_video_finished() -> void:
	_play(_clip + 1)


# --- building -----------------------------------------------------------------------------------------

func _build() -> void:
	var bg := UIKit.full_rect(ColorRect.new()) as ColorRect
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform float alpha = 1.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = mix(vec3(0.03, 0.06, 0.1), vec3(0.005, 0.01, 0.02), smoothstep(0.0, 1.1, length((uv - vec2(0.3, 0.2)) * vec2(1.4, 1.0))));
	vec2 g = abs(fract(FRAGCOORD.xy / 48.0) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.02, min(g.x, g.y));
	col += vec3(0.45, 0.78, 1.0) * grid * 0.035;
	col += 0.012 * sin(FRAGCOORD.y * 2.0);
	COLOR = vec4(col, alpha);
}
"""
	m.shader = s
	m.set_shader_parameter("alpha", 1.0 if standalone else 0.95)
	bg.material = m
	add_child(bg)
	var frame := Frame.new()
	UIKit.full_rect(frame)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var margin := MarginContainer.new()
	UIKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# The header: the title, the two sides, back.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(_label("FIELD MANUAL", 30, TEXT, _font_bold))
	titles.add_child(_label("Every unit, what it is for and its skills", 13, DIM, _font))
	head.add_child(titles)
	var gap := Control.new()
	gap.custom_minimum_size.x = 40
	head.add_child(gap)
	for side in ["DEFENDERS", "ATTACKERS"]:
		var tab := _tab(side)
		tab.pressed.connect(_show_side.bind(side == "ATTACKERS"))
		head.add_child(tab)
		_tabs.append(tab)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var back := _tab("◀  BACK")
	back.toggle_mode = false
	back.pressed.connect(close)
	head.add_child(back)
	var line := ColorRect.new()
	line.color = Color(COOL, 0.22)
	line.custom_minimum_size.y = 1
	root.add_child(line)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 26)
	root.add_child(body)

	# Left: the side's units.
	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size.x = 300
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_list_scroll.add_child(_list)

	# Right: the open unit.
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	body.add_child(page)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	page.add_child(top)

	var video_col := VBoxContainer.new()
	video_col.add_theme_constant_override("separation", 6)
	top.add_child(video_col)
	var screen := Panel.new()
	screen.custom_minimum_size = VIDEO_SIZE
	screen.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.border_color = Color(COOL, 0.35)
	sb.set_border_width_all(1)
	screen.add_theme_stylebox_override("panel", sb)
	video_col.add_child(screen)
	_video = VideoStreamPlayer.new()
	UIKit.full_rect(_video)
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_on_video_finished)
	screen.add_child(_video)
	_no_video = _label("VIDEO MISSING\nrun  git lfs pull", 14, DIM, _font_bold)
	UIKit.full_rect(_no_video)
	_no_video.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_video.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_video.visible = false
	screen.add_child(_no_video)
	var track := ColorRect.new()
	track.color = Color(COOL, 0.15)
	track.custom_minimum_size.y = 3
	video_col.add_child(track)
	_progress = ColorRect.new()
	_progress.color = ACCENT
	_progress.size = Vector2(0, 3)
	track.add_child(_progress)
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", 10)
	video_col.add_child(under)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 4)
	under.add_child(_chips)
	_caption = _label("", 13, DIM, _font)
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption.clip_text = true
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	under.add_child(_caption)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	top.add_child(info)
	_name = _label("", 28, TEXT, _font_bold)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name)
	_role = _label("", 14, ACCENT, _font_bold)
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_role)
	_meta = GridContainer.new()
	_meta.columns = 2
	_meta.add_theme_constant_override("h_separation", 16)
	_meta.add_theme_constant_override("v_separation", 3)
	info.add_child(_meta)
	_about = _label("", 14, Color(TEXT, 0.85), _font)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_about)

	page.add_child(_section("SKILLS", "click a skill to see it"))
	_skills_scroll = ScrollContainer.new()
	_skills_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_skills_scroll)
	_skills = GridContainer.new()
	_skills.columns = 2
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills.add_theme_constant_override("h_separation", 10)
	_skills.add_theme_constant_override("v_separation", 10)
	_skills_scroll.add_child(_skills)

	root.add_child(_label("↑ ↓  UNIT     ← →  CLIP     TAB  OTHER SIDE     ESC  BACK", 12, Color(DIM, 0.5), _font))


func _section(text: String, hint: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tick := ColorRect.new()
	tick.color = ACCENT
	tick.custom_minimum_size = Vector2(14, 2)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)
	row.add_child(_label(text, 13, Color(ACCENT, 0.9), _font_bold))
	var line := ColorRect.new()
	line.color = Color(COOL, 0.18)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	row.add_child(_label(hint, 12, Color(DIM, 0.6), _font))
	return row


func _style(bg: Color, edge: Color, left: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.border_width_left = left
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## A toggle in the header (a side) or a plain button (back).
func _tab(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.85))
	b.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.92, 0.85))
	var idle := _style(Color(0.02, 0.04, 0.07, 0.55), Color(COOL, 0.3), 2)
	var on := _style(Color(ACCENT, 0.22), ACCENT, 3)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", _style(Color(COOL, 0.1), Color(COOL, 0.6), 2))
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## A unit in the list: its name and its role under it; lit while its page is open.
func _unit_button(p: Dictionary, overview: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	var idle := _style(Color(0.02, 0.04, 0.07, 0.45), Color(COOL, 0.25), 2)
	var on := _style(Color(ACCENT, 0.2), ACCENT, 4)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", _style(Color(COOL, 0.08), Color(COOL, 0.55), 2))
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	UIKit.full_rect(col)
	col.offset_left = 16
	col.offset_right = -8
	b.add_child(col)
	col.add_child(_label(p.name, 15, ACCENT if overview else TEXT, _font_bold))
	var role := _label(p.role, 11, DIM, _font)
	role.clip_text = true
	role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(role)
	return b


## A clip's number under the video.
func _chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 24)
	b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(COOL, 0.1)
	idle.set_corner_radius_all(2)
	var on := idle.duplicate() as StyleBoxFlat
	on.bg_color = ACCENT
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", idle)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## A skill: its key, its name and what it does. One with a clip plays it when clicked (▶).
func _skill_card(s: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.border_color = Color(COOL, 0.2)
	sb.border_width_left = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var key := PanelContainer.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(COOL, 0.16)
	ks.border_color = Color(COOL, 0.5)
	ks.set_border_width_all(1)
	ks.set_corner_radius_all(3)
	ks.content_margin_left = 7
	ks.content_margin_right = 7
	ks.content_margin_top = 1
	ks.content_margin_bottom = 1
	key.add_theme_stylebox_override("panel", ks)
	key.add_child(_label(s.key, 12, COOL, _font_bold))
	row.add_child(key)
	var title := _label(s.name, 15, TEXT, _font_bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var text := _label(s.text, 13, Color(TEXT, 0.75), _font)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var clip: String = s.get("clip", "")
	if clip != "":
		row.add_child(_label("▶", 13, Color(ACCENT, 0.8), _font_bold))
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Play the clip"
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_play_id(clip))
		card.mouse_entered.connect(func(): sb.bg_color = Color(0.06, 0.1, 0.16, 0.85))
		card.mouse_exited.connect(func(): sb.bg_color = CARD)
	return card


## Lights the card of the skill whose clip is playing.
func _light_card(card: PanelContainer, on: bool) -> void:
	var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_color = ACCENT if on else Color(COOL, 0.2)
	sb.border_width_left = 4 if on else 2


func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## Corner brackets, like the main menu's frame.
class Frame:
	extends Control

	func _draw() -> void:
		var c := Color(0.45, 0.78, 1.0, 0.35)
		var m := 22.0
		var l := 40.0
		var r := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
			var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), c, 2.0)
			draw_line(corner, corner + Vector2(0, l * sy), c, 2.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
