class_name FieldManual
extends Control
## The Field Manual, the game's tutorial: two books on a desk, one for each side (FieldManualData).
##
##   The Host     FM 1-01, the attackers' field manual: a cloth-bound book on a walnut desk under a warm lamp. A
##                spread for every beast: on the left its plate (the video, printed as a photograph and mounted
##                with corners), the figures and its particulars, a soldier's note in pencil; on the right its
##                chapter: what it is for and its employment, a paragraph a skill, each pointing at its figure.
##   The Garrison TM 30-90, the defenders' standing orders: a ring binder on a steel desk under a strip light.
##                Typed on the Keep's own forms: the photograph clipped on, the particulars in the form's boxes,
##                the duties numbered, a note at the foot.
## Both open on a title page and their contents. The other book lies under the open one, its edge showing: click
## it (or Tab) to open that one instead. The pages turn (the old page is caught and turned over the new one).
##
## Two ways in: its own scene from the main menu (scenes/field_manual.tscn, `standalone`: closing it goes back to the
## menu), or over the paused match from the pause menu (FieldManual.open_over: closing it frees it).
## Keys: left / right turn the page, up / down the figure, Home the contents, Tab the other book, Esc closes.
## The look (paper, ink, type, furniture) is FieldManualStyle's.

signal closed

const PAGE := Vector2(720, 820)
const BOOK := Vector2(1440, 820)
## Room round the book on the desk, in the book's own units: the stage is scaled so this much fits the screen.
const DESK_ROOM := Vector2(1700, 930)
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TURN_TIME := 0.62
const SOUNDS := ["res://assets/audio/manual_page_1.ogg", "res://assets/audio/manual_page_2.ogg",
		"res://assets/audio/manual_page_3.ogg"]
const BOOK_SOUND := "res://assets/audio/manual_book.ogg"
const TAP_SOUND := "res://assets/audio/manual_tap.ogg"
## Justified, but the last line of a paragraph (and a one-line paragraph) is left alone.
const JUSTIFY := TextServer.JUSTIFICATION_KASHIDA | TextServer.JUSTIFICATION_WORD_BOUND \
		| TextServer.JUSTIFICATION_TRIM_EDGE_SPACES | TextServer.JUSTIFICATION_SKIP_LAST_LINE
## Skills that have no key of their own: what to call them instead.
const NOT_KEYS := {"basic": "weapon", "passive": "passive", "duty": "duty", "mode": "mode", "fog": "fog of war",
		"danger": "danger", "alarm": "alarm", "auto": "automatic", "warning": "warning", "heat": "heat", "crew": "crew",
		"reload": "reload", "caution": "caution", "fuel": "fuel", "aim high": "aim high", "hold": "hold"}
const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI",
		"XVII", "XVIII", "XIX", "XX"]

## The manual's own scene (from the main menu): closing it goes back to the menu.
@export var standalone := false
## Which book is open: the Host's (the attackers') or the Garrison's.
var attacker := false

var _data: Dictionary
var _pal: Dictionary
## 0: the title page and the contents; k: chapter k - 1.
var _spread := 0
var _clips: Array = []
var _clip := 0
var _leaving := false
var _busy := false

var _desk: ColorRect
var _lamp: ColorRect
var _stage: Control
var _book: Control
var _peek: Peek
var _pages: Control
var _left: Control
var _right: Control
var _edges: FieldManualStyle.PageEdges
var _dog_l: FieldManualStyle.DogEar
var _dog_r: FieldManualStyle.DogEar
var _video: VideoStreamPlayer
var _photo_mat: ShaderMaterial
var _figs: RichTextLabel
var _missing: Label
var _back: Label
var _hint: Label
var _turn: TurnOverlay
var _fade: ColorRect
var _sfx: AudioStreamPlayer
var _fit_gen := 0
var _papers: Array[ShaderMaterial] = []


## Opens the manual over `parent` (the paused match's HUD), at the given side's book. It runs while the game is
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
	if standalone:
		attacker = GameConfig.player_side == GameConfig.PlayerSide.ATTACKER
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = false
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -5.0
	add_child(_sfx)
	_desk = UIKit.full_rect(ColorRect.new()) as ColorRect
	_desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desk)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_lamp = UIKit.full_rect(ColorRect.new()) as ColorRect
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lamp)
	_back = Label.new()
	_back.mouse_filter = Control.MOUSE_FILTER_STOP
	_back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_back.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	_back.mouse_entered.connect(func(): _back.modulate.a = 1.0)
	_back.mouse_exited.connect(func(): _back.modulate.a = 0.6)
	_back.modulate.a = 0.6
	add_child(_back)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_hint)
	_turn = TurnOverlay.new()
	_turn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn.visible = false
	add_child(_turn)
	_fade = UIKit.full_rect(ColorRect.new()) as ColorRect
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	get_viewport().size_changed.connect(_layout)
	_open_book(attacker)
	_layout()
	_arrive()


## The book slides up into the light as the screen comes up from black.
func _arrive() -> void:
	_fade.color.a = 1.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_fade, "color:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE)
	var to := _book.position
	_book.position = to + Vector2(0, 60)
	_book.rotation = deg_to_rad(-1.2)
	tw.tween_property(_book, "position", to, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_book, "rotation", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sound(BOOK_SOUND)


func _layout() -> void:
	var vp := get_viewport_rect().size
	var s := minf(vp.x / DESK_ROOM.x, vp.y / DESK_ROOM.y)
	_stage.scale = Vector2(s, s)
	_stage.position = (vp - BOOK * s) * 0.5 + Vector2(-18.0 * s, 0.0)
	_back.position = Vector2(26, 16)
	_hint.position = Vector2(28, vp.y - 30)
	_hint.size = Vector2(vp.x - 56, 24)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_turn_to(_spread + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_turn_to(_spread - 1)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.is_pressed():
		return
	if event.is_action("ui_cancel") or event.is_action("pause"):
		close()
	elif event.is_action("ui_right") or event.is_action("ui_page_down"):
		_turn_to(_spread + 1)
	elif event.is_action("ui_left") or event.is_action("ui_page_up"):
		_turn_to(_spread - 1)
	elif event.is_action("ui_home"):
		_turn_to(0)
	elif event.is_action("ui_up"):
		_play(_clip - 1)
	elif event.is_action("ui_down"):
		_play(_clip + 1)
	elif event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
		_swap_books()
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# A click on the desk, off the books, puts the manual down.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = _stage.get_global_transform().affine_inverse() * (event as InputEventMouseButton).position
		if not Rect2(Vector2(-30, -30), BOOK + Vector2(60, 60)).has_point(p) and not _peek.hovered:
			close()


func close() -> void:
	if _leaving:
		return
	_leaving = true
	if _video:
		_video.stop()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	if standalone:
		tw.tween_callback(func(): get_tree().change_scene_to_file(MENU_SCENE))
		return
	tw.tween_callback(func():
		closed.emit()
		queue_free())


func _sound(path: String) -> void:
	if ResourceLoader.exists(path):
		_sfx.stream = load(path)
		_sfx.pitch_scale = randf_range(0.94, 1.06)
		_sfx.play()


# ---------------------------------------------------------------- the books

## Lays `attacker_side`'s book open on its desk at its title page, the other one under it.
func _open_book(attacker_side: bool) -> void:
	attacker = attacker_side
	_data = FieldManualData.book(attacker)
	_pal = FieldManualStyle.palette(attacker)
	_spread = 0
	_desk.material = FieldManualStyle.material(FieldManualStyle.DESK, {"base_a": _pal.desk_a, "base_b": _pal.desk_b,
			"lamp": _pal.lamp, "lamp_at": _pal.lamp_at, "reach": _pal.lamp_reach, "kind": _pal.desk_kind,
			"alpha": 1.0 if standalone else 0.97})
	_lamp.material = FieldManualStyle.material(FieldManualStyle.LAMP, {"lamp": _pal.lamp, "lamp_at": _pal.lamp_at,
			"reach": _pal.lamp_reach})
	for c in _stage.get_children():
		c.queue_free()
	_peek = Peek.new()
	_peek.attacker = not attacker
	_peek.pressed.connect(_swap_books)
	_stage.add_child(_peek)
	_peek.position = Vector2(BOOK.x - 520, 46)
	_peek.size = Vector2(640, 760)
	_peek.rotation = deg_to_rad(3.5)
	_book = Control.new()
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.size = BOOK
	_book.pivot_offset = BOOK * 0.5
	_stage.add_child(_book)
	_build_binding()
	_pages = Control.new()
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.size = BOOK
	_book.add_child(_pages)
	_build_furniture()
	var hint_font := FieldManualStyle.small_caps(2, 460) if attacker else FieldManualStyle.font("typed")
	var desk_ink := Color(0.93, 0.86, 0.72, 0.5) if attacker else Color(0.82, 0.88, 0.9, 0.45)
	_hint.text = "←  →  turn the page      ↑  ↓  the figures      tab  the other manual      esc  close" if attacker \
			else "<- ->  TURN THE SHEET     UP/DOWN  FIGURES     TAB  THE OTHER MANUAL     ESC  CLOSE"
	_hint.add_theme_font_override("font", hint_font)
	_hint.add_theme_font_size_override("font_size", 15 if attacker else 13)
	_hint.add_theme_color_override("font_color", desk_ink)
	_back.text = "‹  back to the war" if attacker else "< BACK TO THE WAR"
	_back.add_theme_font_override("font", FieldManualStyle.font("italic", 460, ["onum"]) if attacker else FieldManualStyle.font("typed"))
	_back.add_theme_font_size_override("font_size", 20 if attacker else 16)
	_back.add_theme_color_override("font_color", Color(desk_ink, 0.95))
	_build_spread()


## The boards, the page edges, the two sheets of paper and the gutter; the binder's rings or the book's ribbon.
func _build_binding() -> void:
	var shadow := FieldManualStyle.Shadow.new()
	shadow.color = Color(0, 0, 0, 0.6)
	shadow.spread = 46.0
	shadow.offset = Vector2(10, 22)
	shadow.size = BOOK + Vector2(28, 28)
	shadow.position = Vector2(-14, -14)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(shadow)
	var cover := ColorRect.new()
	cover.color = _pal.cover
	cover.position = Vector2(-14, -12)
	cover.size = BOOK + Vector2(28, 26)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(cover)
	var cover_edge := ColorRect.new()
	cover_edge.color = _pal.cover_edge
	cover_edge.position = Vector2(-14, BOOK.y + 8)
	cover_edge.size = Vector2(BOOK.x + 28, 6)
	cover_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(cover_edge)
	_edges = FieldManualStyle.PageEdges.new()
	_edges.paper = _pal.paper
	_edges.page = PAGE
	_edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(_edges)
	_papers.clear()
	for side in [0, 1]:
		var paper := ColorRect.new()
		paper.position = Vector2(PAGE.x * side, 0)
		paper.size = PAGE
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.material = FieldManualStyle.paper_material(_pal, 1.0 if side == 0 else -1.0, PAGE, float(side) * 17.3)
		_papers.append(paper.material)
		_book.add_child(paper)


func _build_furniture() -> void:
	if attacker:
		var ribbon := FieldManualStyle.Ribbon.new()
		ribbon.color = _pal.ribbon
		ribbon.position = Vector2(PAGE.x + 96, PAGE.y - 6)
		ribbon.size = Vector2(16, 46)
		ribbon.rotation = deg_to_rad(-6.0)
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_book.add_child(ribbon)
	else:
		var rings := FieldManualStyle.Rings.new()
		rings.position = Vector2(PAGE.x - 60, 0)
		rings.size = Vector2(120, PAGE.y)
		rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_book.add_child(rings)
	# The page corners: the outer strips turn the page, and curl up under the pointer.
	_dog_l = _corner(false)
	_dog_r = _corner(true)


func _corner(right: bool) -> FieldManualStyle.DogEar:
	var hot := Control.new()
	hot.position = Vector2(PAGE.x * 2.0 - 64.0 if right else 0.0, 90.0)
	hot.size = Vector2(64, PAGE.y - 90.0)
	hot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_book.add_child(hot)
	var ear := FieldManualStyle.DogEar.new()
	ear.paper = _pal.paper
	ear.right = right
	ear.size = hot.size
	ear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hot.add_child(ear)
	var set_amount := func(v: float) -> void:
		ear.amount = v
		ear.queue_redraw()
	var curl := func(on: bool) -> void:
		var tw := ear.create_tween()
		tw.tween_method(set_amount, ear.amount, 1.0 if on and _can_turn(1 if right else -1) else 0.0, 0.18)
	hot.mouse_entered.connect(curl.bind(true))
	hot.mouse_exited.connect(curl.bind(false))
	hot.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_turn_to(_spread + (1 if right else -1)))
	return ear


func _can_turn(dir: int) -> bool:
	var to := _spread + dir
	return to >= 0 and to <= (_data.chapters as Array).size()


## The other book, Tab or a click on its edge: the open one is put away and the other laid open in its place.
func _swap_books() -> void:
	if _busy or _leaving:
		return
	_busy = true
	if _video:
		_video.stop()
	var tw := create_tween()
	tw.tween_property(_book, "position", _book.position + Vector2(-80, 900), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_fade, "color:a", 1.0, 0.34)
	tw.tween_callback(func():
		_open_book(not attacker)
		_layout()
		var to := _book.position
		_book.position = to + Vector2(140, 40)
		_book.rotation = deg_to_rad(3.0)
		var tin := create_tween().set_parallel()
		tin.tween_property(_fade, "color:a", 0.0, 0.4)
		tin.tween_property(_book, "position", to, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tin.tween_property(_book, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tin.chain().tween_callback(func(): _busy = false)
		_sound(BOOK_SOUND))


# ---------------------------------------------------------------- turning the pages

## Turns to spread `to`: the old page is caught as it is and turned over onto the new one.
func _turn_to(to: int) -> void:
	if _busy or _leaving or to == _spread or to < 0 or to > (_data.chapters as Array).size():
		return
	_busy = true
	var dir := 1 if to > _spread else -1
	var img := get_viewport().get_texture().get_image()
	_turn.snap = ImageTexture.create_from_image(img)
	# The canvas (this control's coordinates) onto the picture's pixels.
	_turn.xf = Transform2D().scaled(Vector2(img.get_size()) / get_viewport_rect().size)
	var bx := _book.get_global_transform()
	_turn.left_rect = Rect2(bx * Vector2.ZERO, bx.basis_xform(PAGE))
	_turn.right_rect = Rect2(bx * Vector2(PAGE.x, 0), bx.basis_xform(PAGE))
	_turn.paper = _pal.paper
	_turn.dir = dir
	_turn.u = 0.0
	_turn.size = get_viewport_rect().size
	_turn.visible = true
	_spread = to
	_build_spread()
	_sound(SOUNDS[randi() % SOUNDS.size()])
	var set_u := func(v: float) -> void:
		_turn.u = v
		_turn.queue_redraw()
	var tw := create_tween()
	tw.tween_method(set_u, 0.0, 1.0, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		_turn.visible = false
		_turn.snap = null
		_busy = false)


# ---------------------------------------------------------------- the spreads

func _build_spread() -> void:
	for c in _pages.get_children():
		c.queue_free()
	if _video:
		_video.stop()
	_video = null
	_figs = null
	_missing = null
	_clips = []
	var n := (_data.chapters as Array).size()
	_edges.left_pages = 2 + int(7.0 * _spread / maxf(n, 1))
	_edges.right_pages = 2 + int(7.0 * (n - _spread) / maxf(n, 1))
	_edges.queue_redraw()
	# Every spread is its own two sheets: their own fibres and freckles; now and then a cup was set down on one.
	for side in 2:
		var leaf := _spread * 2 + side
		_papers[side].set_shader_parameter("seed", float(leaf) * 3.71 + (0.0 if attacker else 40.0))
		var cup := attacker and (leaf % 7 == 3 or leaf == 1)
		var rng := RandomNumberGenerator.new()
		rng.seed = leaf * 7919 + 13
		var at := Vector2(rng.randf_range(120, 600), rng.randf_range(560, 760)) if leaf != 1 else Vector2(590, 735)
		_papers[side].set_shader_parameter("stain", Vector3(at.x, at.y, rng.randf_range(62, 84)) if cup else Vector3.ZERO)
		_papers[side].set_shader_parameter("stain_amount", rng.randf_range(0.45, 0.7) if cup else 0.0)
	_left = _page_root(0)
	_right = _page_root(1)
	if _spread == 0:
		if attacker:
			_host_title(_left)
			_host_contents(_right)
		else:
			_garrison_cover(_left)
			_garrison_index(_right)
	else:
		var ch: Dictionary = _data.chapters[_spread - 1]
		_clips = ch.clips
		if attacker:
			_host_plate(_left, ch)
			_host_chapter(_right, ch)
		else:
			_garrison_photo(_left, ch)
			_garrison_order(_right, ch)
		_play(0)


func _page_root(side: int) -> Control:
	var p := Control.new()
	p.position = Vector2(PAGE.x * side, 0)
	p.size = PAGE
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.add_child(p)
	return p


func _put(parent: Control, c: Control, pos: Vector2, width := -1.0) -> Control:
	parent.add_child(c)
	c.position = pos
	if width > 0.0:
		c.size.x = width
		c.custom_minimum_size.x = width
	return c


func _centered(parent: Control, l: Label, y: float, width := PAGE.x) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_put(parent, l, Vector2((PAGE.x - width) * 0.5, y), width)
	return l


func _rule(parent: Control, pos: Vector2, width: float, color: Color, double := false) -> void:
	var r := FieldManualStyle.Rule.new()
	r.color = color
	r.double = double
	r.size = Vector2(width, 8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(parent, r, pos)


func _page_number(parent: Control, n: int, side: int) -> void:
	if attacker:
		var l := FieldManualStyle.label(str(n), FieldManualStyle.font("serif", 440, ["onum"]), 17, _pal.ink_soft)
		_put(parent, l, Vector2(64 if side == 0 else PAGE.x - 104, PAGE.y - 52), 40)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	else:
		_centered(parent, FieldManualStyle.label("- %d -" % n, FieldManualStyle.font("typed"), 15, _pal.ink_soft), PAGE.y - 70)


func _pencil(parent: Control, text: String, pos: Vector2, angle_deg: float, size := 31, underline := true) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = pos
	holder.rotation = deg_to_rad(angle_deg)
	parent.add_child(holder)
	var l := FieldManualStyle.label(text, FieldManualStyle.font("hand"), size, _pal.pencil)
	l.add_theme_constant_override("line_spacing", -10)
	l.material = FieldManualStyle.ink_material(0.18, pos.x * 0.13, 0.35)
	holder.add_child(l)
	if underline:
		var w := FieldManualStyle.font("hand").get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var lines := text.count("\n") + 1
		var st := FieldManualStyle.Stroke.new()
		st.color = Color(_pal.pencil, 0.7)
		st.width = 1.3
		st.seed = pos.y
		var y := lines * size * 0.72 + 8.0
		st.points = PackedVector2Array([Vector2(4, y), Vector2(w * 0.55, y + 2), Vector2(w * 0.95, y - 1)])
		st.size = Vector2(w + 10, y + 10)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(st)


func _stamp(parent: Control, text: String, f: Font, size: int, center: Vector2, angle_deg: float, seed: float) -> void:
	var s := FieldManualStyle.Stamp.new()
	s.text = text
	s.font = f
	s.font_size = size
	s.color = _pal.accent
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := s.box_size()
	s.size = bs + Vector2(4, 4)
	s.pivot_offset = bs * 0.5
	s.position = center - bs * 0.5
	s.rotation = deg_to_rad(angle_deg)
	s.material = FieldManualStyle.ink_material(0.36, seed, 0.3)
	parent.add_child(s)


# ---------------------------------------------------------------- the Host's book

func _host_title(page: Control) -> void:
	var ink: Color = _pal.ink
	_pencil(page, String(_data.owner), Vector2(440, 40), -4.0, 27, false)
	_centered(page, FieldManualStyle.label(_data.code, FieldManualStyle.font("gothic", 760, [], 7), 20, ink), 112)
	_rule(page, Vector2(170, 146), 380, ink, true)
	_centered(page, FieldManualStyle.label(_data.kind, FieldManualStyle.font("gothic", 820, [], 3), 60, ink), 160)
	_rule(page, Vector2(170, 240), 380, ink, true)
	_centered(page, FieldManualStyle.label(_data.subject, FieldManualStyle.font("serif", 520, ["liga"]), 46, ink), 262)
	var sub := FieldManualStyle.label(_data.subtitle, FieldManualStyle.font("italic", 420, ["onum"]), 21, _pal.ink_soft)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_centered(page, sub, 326, 440)
	var seal := FieldManualStyle.Seal.new()
	seal.color = _pal.accent
	seal.font = FieldManualStyle.font("gothic", 700, [], 1)
	seal.size = Vector2(196, 196)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.material = FieldManualStyle.ink_material(0.2, 3.0, 0.2)
	_put(page, seal, Vector2((PAGE.x - 196) * 0.5, 410))
	_centered(page, FieldManualStyle.label(_data.authority, FieldManualStyle.small_caps(1, 500), 17, ink), 652)
	var issue := FieldManualStyle.label(_data.issue, FieldManualStyle.font("italic", 420, ["onum"]), 16, _pal.ink_soft)
	issue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_centered(page, issue, 684, 470)
	_stamp(page, _data.stamp, FieldManualStyle.font("stencil", 800, [], 3), 34, Vector2(556, 578), -11.0, 1.7)


func _host_contents(page: Control) -> void:
	var ink: Color = _pal.ink
	_centered(page, FieldManualStyle.label("Contents", FieldManualStyle.small_caps(6, 520), 26, ink), 70)
	_rule(page, Vector2(290, 112), 140, _pal.accent, false)
	var y := 140.0
	var chapters: Array = _data.chapters
	for k in chapters.size():
		var ch: Dictionary = chapters[k]
		var row := ContentsRow.new()
		row.position = Vector2(76, y)
		row.size = Vector2(PAGE.x - 76 - 70, 33)
		row.pressed.connect(_turn_to.bind(k + 1))
		page.add_child(row)
		var hand := FieldManualStyle.label("☞", FieldManualStyle.font("serif", 400), 20, _pal.accent)
		hand.position = Vector2(-30, 1)
		hand.modulate.a = 0.0
		row.add_child(hand)
		row.hand = hand
		var num := FieldManualStyle.label(ROMAN[k + 1] + ".", FieldManualStyle.small_caps(1, 520), 17, _pal.accent)
		num.position = Vector2(0, 5)
		num.size = Vector2(56, 24)
		row.add_child(num)
		var title := FieldManualStyle.label(String(ch.name), FieldManualStyle.font("serif", 440, ["onum", "liga"]), 21, ink)
		title.position = Vector2(56, 1)
		row.add_child(title)
		var tw := FieldManualStyle.font("serif", 440, ["onum", "liga"]).get_string_size(String(ch.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		var lead := FieldManualStyle.Leader.new()
		lead.color = _pal.ink_faint
		lead.position = Vector2(56 + tw + 8, 0)
		lead.size = Vector2(row.size.x - (56 + tw + 8) - 44, 28)
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lead)
		var pg := FieldManualStyle.label(str(k * 2 + 1), FieldManualStyle.font("serif", 440, ["onum"]), 19, ink)
		pg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pg.position = Vector2(row.size.x - 40, 2)
		pg.size = Vector2(40, 26)
		row.add_child(pg)
		y += 35.0
	var col := FieldManualStyle.label("The plates are reproduced from photographs taken in the field.",
			FieldManualStyle.font("italic", 420, ["onum"]), 15, _pal.ink_soft)
	_centered(page, col, y + 14, 520)


func _host_plate(page: Control, ch: Dictionary) -> void:
	var k := _spread
	_centered(page, FieldManualStyle.label("Plate %s" % ROMAN[k], FieldManualStyle.small_caps(4, 480), 16, _pal.ink_soft), 30)
	# The photograph, mounted a little askew.
	var mount := Control.new()
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.size = Vector2(604, 352)
	mount.position = Vector2((PAGE.x - 604) * 0.5, 76)
	mount.pivot_offset = mount.size * 0.5
	mount.rotation = deg_to_rad(-1.1 if k % 2 == 1 else 0.8)
	page.add_child(mount)
	var sh := FieldManualStyle.Shadow.new()
	sh.color = Color(0.1, 0.07, 0.04, 0.45)
	sh.spread = 12.0
	sh.offset = Vector2(3, 6)
	sh.size = mount.size
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(sh)
	var print_ := ColorRect.new()
	print_.color = _pal.print_border
	print_.size = mount.size
	print_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(print_)
	_add_video(mount, Rect2(14, 14, 576, 324))
	var corners := FieldManualStyle.PhotoCorners.new()
	corners.color = _pal.mount
	corners.size = mount.size
	corners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(corners)
	# The figures and the caption.
	_figs = FieldManualStyle.rich(true, 19, _pal.ink)
	_figs.meta_clicked.connect(_on_meta)
	_put(page, _figs, Vector2(90, 448), PAGE.x - 180)
	# The particulars.
	var py := 548.0
	var head := FieldManualStyle.label("Particulars", FieldManualStyle.small_caps(4, 520), 15, _pal.accent)
	_centered(page, head, py)
	_rule(page, Vector2(196, py + 9), 92, _pal.ink_faint)
	_rule(page, Vector2(432, py + 9), 92, _pal.ink_faint)
	var meta: Array = ch.meta
	var y := py + 32.0
	for m in meta:
		var lab := FieldManualStyle.label(String(m[0]), FieldManualStyle.small_caps(1, 460), 17, _pal.ink_soft)
		_put(page, lab, Vector2(170, y))
		var val := FieldManualStyle.label(String(m[1]), FieldManualStyle.font("serif", 460, ["onum"]), 19, _pal.ink)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(page, val, Vector2(330, y - 2), 220)
		var lw := FieldManualStyle.small_caps(1, 460).get_string_size(String(m[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var vw := FieldManualStyle.font("serif", 460, ["onum"]).get_string_size(String(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var lead := FieldManualStyle.Leader.new()
		lead.color = _pal.ink_faint
		lead.position = Vector2(170 + lw + 8, y)
		lead.size = Vector2(maxf(550 - vw - 10 - (170 + lw + 8), 0), 22)
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(lead)
		y += 29.0
	_page_number(page, k * 2 - 1, 0)
	if ch.has("note"):
		var lines := String(ch.note).count("\n") + 1
		_pencil(page, String(ch.note), Vector2(256 + float(k % 3) * 22.0, 790.0 - lines * 27.0), -3.0 + float(k % 3) * 1.4)


func _host_chapter(page: Control, ch: Dictionary) -> void:
	var k := _spread
	var ink: Color = _pal.ink
	_centered(page, FieldManualStyle.label("%s  ·  %s" % [_data.part, ch.name], FieldManualStyle.small_caps(3, 480), 15, _pal.ink_soft), 30)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(page, col, Vector2(70, 70), PAGE.x - 140)
	var chap := FieldManualStyle.label("Chapter %s" % ROMAN[k], FieldManualStyle.small_caps(4, 520), 16, _pal.accent)
	col.add_child(chap)
	var title := FieldManualStyle.label(String(ch.name), FieldManualStyle.font("serif", 500, ["liga"]), 50, ink)
	col.add_child(title)
	if ch.has("latin"):
		col.add_child(FieldManualStyle.label(String(ch.latin), FieldManualStyle.font("italic", 420), 21, _pal.ink_soft))
	col.add_child(_gap(4))
	col.add_child(FieldManualStyle.label(String(ch.role), FieldManualStyle.small_caps(1, 480), 16, ink))
	col.add_child(_gap(10))
	var orn := FieldManualStyle.label("❧", FieldManualStyle.font("serif", 400), 22, _pal.accent)
	orn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(orn)
	col.add_child(_gap(6))
	var body := FieldManualStyle.rich(true, 19, ink)
	var about: String = ch.about
	body.push_paragraph(HORIZONTAL_ALIGNMENT_FILL, Control.TEXT_DIRECTION_AUTO, "", TextServer.STRUCTURED_TEXT_DEFAULT, JUSTIFY)
	body.push_dropcap(about.left(1), FieldManualStyle.font("serif", 500), 64, Rect2(0, 0, 6, -4), _pal.accent)
	body.add_text(about.substr(1))
	body.pop()
	col.add_child(body)
	col.add_child(_gap(14))
	var sk_head := FieldManualStyle.label(String(_data.skills_heading), FieldManualStyle.small_caps(5, 520), 16, _pal.accent)
	sk_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sk_head)
	col.add_child(_gap(8))
	var skills := FieldManualStyle.rich(true, 18, ink)
	skills.meta_clicked.connect(_on_meta)
	var letters := "abcdefghij"
	var list: Array = ch.skills
	for i in list.size():
		var s: Dictionary = list[i]
		skills.push_paragraph(HORIZONTAL_ALIGNMENT_FILL, Control.TEXT_DIRECTION_AUTO, "", TextServer.STRUCTURED_TEXT_DEFAULT, JUSTIFY)
		skills.push_color(_pal.accent)
		skills.push_font(FieldManualStyle.font("serif", 600, ["onum"]), 18)
		skills.add_text("%s.  " % letters[i])
		skills.pop()
		skills.pop()
		var tag: String = NOT_KEYS.get(String(s.key).to_lower(), "")
		if tag == "":
			_keycap(skills, String(s.key))
			skills.add_text("  ")
		skills.push_italics()
		skills.add_text(String(s.name))
		skills.pop()
		if tag != "":
			skills.add_text(", ")
			skills.push_font(FieldManualStyle.small_caps(1, 460), 18)
			skills.push_color(_pal.ink_soft)
			skills.add_text(tag)
			skills.pop()
			skills.pop()
		skills.add_text(". " + String(s.text))
		var clip: String = s.get("clip", "")
		var fig := _fig_of(clip)
		if fig > 0:
			skills.add_text(" ")
			skills.push_meta("fig:%d" % (fig - 1), RichTextLabel.META_UNDERLINE_ON_HOVER)
			skills.push_color(_pal.accent)
			skills.push_italics()
			skills.add_text("(fig. %d)" % fig)
			skills.pop()
			skills.pop()
			skills.pop()
		skills.pop()
		skills.newline()
		skills.add_text(" ")
		skills.push_font_size(7)
		skills.add_text(" ")
		skills.pop()
		skills.newline()
	col.add_child(skills)
	_page_number(page, k * 2, 1)
	_fit(col, PAGE.y - 70 - 70)


## A key, printed reversed out of the ink like the keys in an instruction plate.
func _keycap(r: RichTextLabel, key: String) -> void:
	var on_paper: Color = _pal.paper
	r.push_bgcolor(_pal.ink if attacker else _pal.form)
	r.push_color(on_paper)
	r.push_font(FieldManualStyle.font("gothic", 700, [], 1), 13 if attacker else 13)
	r.add_text(" %s " % key.to_upper())
	r.pop()
	r.pop()
	r.pop()


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Scales `col` down (widening it to keep its measure) until it fits `max_h`, once its text is laid out: the
## measure is only trusted once it has held still for a couple of frames (the text wraps after it is sized).
func _fit(col: Control, max_h: float) -> void:
	_fit_gen += 1
	var gen := _fit_gen
	var width := col.size.x
	for attempt in 3:
		var last := -1.0
		var steady := 0
		for i in 12:
			await get_tree().process_frame
			if gen != _fit_gen or not is_instance_valid(col):
				return
			var m := col.get_combined_minimum_size().y
			steady = steady + 1 if absf(m - last) < 0.5 else 0
			last = m
			if steady >= 2:
				break
		if last <= max_h + 1.0:
			return
		var s := clampf(col.scale.x * max_h / last, 0.8, 1.0)
		col.scale = Vector2(s, s)
		col.custom_minimum_size.x = width / s
		col.size.x = width / s


# ---------------------------------------------------------------- the Garrison's orders

func _banners(page: Control) -> void:
	var f := FieldManualStyle.font("form", 820, [], 9)
	for y in [16.0, PAGE.y - 40.0]:
		var l := FieldManualStyle.label(String(_data.classification), f, 19, _pal.accent)
		l.material = FieldManualStyle.ink_material(0.12, y, 0.15)
		_centered(page, l, y)


## A form's box: its printed label in the corner, the typed entry under it.
func _form_box(page: Control, rect: Rect2, caption: String, value: String, value_size := 19) -> void:
	var box := FormBox.new()
	box.color = _pal.form
	box.position = rect.position
	box.size = rect.size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(box)
	var cap := FieldManualStyle.label(caption.to_upper(), FieldManualStyle.font("form", 700, [], 2), 10, _pal.form)
	cap.position = Vector2(7, 4)
	box.add_child(cap)
	var v := FieldManualStyle.rich(false, value_size, _pal.ink)
	v.push_customfx(FieldManualStyle.TypedInk.new(), {})
	v.add_text(value)
	v.pop()
	v.position = Vector2(8, 18)
	v.size = Vector2(rect.size.x - 14, rect.size.y - 18)
	box.add_child(v)


func _garrison_cover(page: Control) -> void:
	_banners(page)
	var ins := FieldManualStyle.Insignia.new()
	ins.color = _pal.accent
	ins.paper = _pal.paper
	ins.size = Vector2(124, 150)
	ins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ins.material = FieldManualStyle.ink_material(0.16, 9.0, 0.2)
	_put(page, ins, Vector2((PAGE.x - 124) * 0.5, 84))
	_centered(page, FieldManualStyle.label(_data.code, FieldManualStyle.font("stencil", 760, [], 6), 66, _pal.ink), 250)
	_centered(page, FieldManualStyle.label(String(_data.subject).to_upper(), FieldManualStyle.font("form", 860, [], 4), 46, _pal.ink), 338)
	_centered(page, FieldManualStyle.label(String(_data.kind) + " FOR THE GARRISON", FieldManualStyle.font("form", 720, [], 4), 18, _pal.form), 398)
	var sub := FieldManualStyle.rich(false, 17, _pal.ink)
	sub.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	sub.push_customfx(FieldManualStyle.TypedInk.new(), {})
	sub.add_text(String(_data.subtitle) + ".")
	sub.pop()
	sub.pop()
	_put(page, sub, Vector2(120, 440), PAGE.x - 240)
	_form_box(page, Rect2(110, 540, 500, 96), "Distribution", String(_data.issue), 16)
	var auth := FieldManualStyle.rich(false, 16, _pal.ink)
	auth.push_customfx(FieldManualStyle.TypedInk.new(), {})
	auth.add_text(String(_data.authority) + ".")
	auth.pop()
	_put(page, auth, Vector2(110, 660), 400)
	var sig := FieldManualStyle.Stroke.new()
	sig.color = Color(0.12, 0.16, 0.32, 0.85)
	sig.width = 1.6
	sig.seed = 4.0
	sig.points = PackedVector2Array([Vector2(0, 26), Vector2(14, 4), Vector2(22, 30), Vector2(34, 8), Vector2(44, 28),
			Vector2(70, 12), Vector2(96, 22), Vector2(150, 16)])
	sig.size = Vector2(160, 40)
	sig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(page, sig, Vector2(120, 690))
	_stamp(page, _data.stamp, FieldManualStyle.font("stencil", 820, [], 2), 34, Vector2(500, 712), -8.0, 5.3)


func _garrison_index(page: Control) -> void:
	_banners(page)
	_centered(page, FieldManualStyle.label("INDEX OF ORDERS", FieldManualStyle.font("form", 840, [], 5), 24, _pal.ink), 66)
	_rule(page, Vector2(90, 102), PAGE.x - 180, _pal.form_faint)
	var y := 124.0
	var chapters: Array = _data.chapters
	var typed := FieldManualStyle.font("typed")
	for k in chapters.size():
		var ch: Dictionary = chapters[k]
		var row := ContentsRow.new()
		row.position = Vector2(92, y)
		row.size = Vector2(PAGE.x - 184, 34)
		row.pressed.connect(_turn_to.bind(k + 1))
		page.add_child(row)
		var mark := FieldManualStyle.label(">", FieldManualStyle.font("typed_bold"), 18, _pal.accent)
		mark.position = Vector2(-24, 4)
		mark.modulate.a = 0.0
		row.add_child(mark)
		row.hand = mark
		var no := FieldManualStyle.label("%2d." % (k + 1), FieldManualStyle.font("typed_bold"), 18, _pal.ink)
		no.position = Vector2(0, 4)
		row.add_child(no)
		var title := FieldManualStyle.label(String(ch.name).to_upper(), typed, 18, _pal.ink)
		title.position = Vector2(52, 4)
		row.add_child(title)
		var tw := typed.get_string_size(String(ch.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var lead := FieldManualStyle.Leader.new()
		lead.color = _pal.ink_faint
		lead.gap = 10.8
		lead.position = Vector2(52 + tw + 10, 2)
		lead.size = Vector2(row.size.x - (52 + tw + 10) - 60, 26)
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lead)
		var pg := FieldManualStyle.label("SH. %d" % (k * 2 + 1), typed, 16, _pal.ink_soft)
		pg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pg.position = Vector2(row.size.x - 70, 5)
		pg.size = Vector2(70, 24)
		row.add_child(pg)
		y += 37.0
	var note := FieldManualStyle.rich(false, 15, _pal.ink_soft)
	note.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	note.push_customfx(FieldManualStyle.TypedInk.new(), {})
	note.add_text("Sheets are to be read in order. Report any sheet missing.")
	note.pop()
	note.pop()
	_put(page, note, Vector2(90, y + 16), PAGE.x - 180)


func _garrison_photo(page: Control, ch: Dictionary) -> void:
	var k := _spread
	_banners(page)
	var typed := FieldManualStyle.font("typed")
	_form_box(page, Rect2(64, 54, 190, 50), "Manual", String(_data.code))
	_form_box(page, Rect2(254, 54, 210, 50), "Order No.", str(k))
	_form_box(page, Rect2(464, 54, 192, 50), "Sheet", "1 OF 2")
	# The photograph, glued straight onto the form and clipped.
	var mount := Control.new()
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.size = Vector2(588, 336)
	mount.position = Vector2((PAGE.x - 588) * 0.5, 126)
	page.add_child(mount)
	var sh := FieldManualStyle.Shadow.new()
	sh.color = Color(0.03, 0.05, 0.05, 0.35)
	sh.spread = 8.0
	sh.offset = Vector2(2, 4)
	sh.size = mount.size
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(sh)
	var print_ := ColorRect.new()
	print_.color = _pal.print_border
	print_.size = mount.size
	print_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(print_)
	_add_video(mount, Rect2(6, 6, 576, 324))
	var clip := FieldManualStyle.PaperClip.new()
	clip.size = Vector2(32, 72)
	clip.position = Vector2(40, -34)
	clip.rotation = deg_to_rad(-4.0)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_child(clip)
	_figs = FieldManualStyle.rich(false, 16, _pal.ink)
	_figs.meta_clicked.connect(_on_meta)
	_put(page, _figs, Vector2(66, 474), PAGE.x - 132)
	# The particulars, in the form's boxes.
	var meta: Array = ch.meta
	var y := 574.0
	var cols := 2
	var w := (PAGE.x - 128) / cols
	for i in meta.size():
		var m: Array = meta[i]
		_form_box(page, Rect2(64 + (i % cols) * w, y + (i / cols) * 54, w, 54), String(m[0]), String(m[1]).to_upper(), 17)
	var rows := int(ceil(meta.size() / float(cols)))
	_form_box(page, Rect2(64, y + rows * 54, PAGE.x - 128, 54), "Designation",
			String(ch.get("designation", ch.name)).to_upper(), 16)
	_stamp(page, "IN FORCE", FieldManualStyle.font("stencil", 800, [], 3), 26, Vector2(560, 534), -9.0 + float(k % 3) * 4.0, float(k) * 1.9)
	_page_number(page, k * 2 - 1, 0)


func _garrison_order(page: Control, ch: Dictionary) -> void:
	var k := _spread
	_banners(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(page, col, Vector2(76, 58), PAGE.x - 140)
	col.add_child(FieldManualStyle.label("ORDER %d" % k, FieldManualStyle.font("form", 820, [], 6), 15, _pal.accent))
	var title := FieldManualStyle.label(String(ch.name).to_upper(), FieldManualStyle.font("form", 860, [], 1), 34, _pal.ink)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var role := FieldManualStyle.rich(false, 16, _pal.ink)
	role.push_customfx(FieldManualStyle.TypedInk.new(), {})
	role.add_text(String(ch.role) + ".")
	role.pop()
	col.add_child(role)
	col.add_child(_gap(8))
	var line := FieldManualStyle.Rule.new()
	line.color = _pal.form_faint
	line.double = false
	line.custom_minimum_size = Vector2(0, 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	col.add_child(_gap(8))
	var body := FieldManualStyle.rich(false, 16, _pal.ink)
	body.push_customfx(FieldManualStyle.TypedInk.new(), {})
	body.add_text(String(ch.about))
	body.pop()
	col.add_child(body)
	col.add_child(_gap(14))
	var head := FieldManualStyle.rich(false, 16, _pal.ink)
	head.push_customfx(FieldManualStyle.TypedInk.new(), {})
	head.push_bold()
	head.push_underline()
	head.add_text(String(_data.skills_heading).to_upper())
	head.pop()
	head.pop()
	head.add_text(":")
	head.pop()
	col.add_child(head)
	col.add_child(_gap(6))
	var duties := FieldManualStyle.rich(false, 16, _pal.ink)
	duties.meta_clicked.connect(_on_meta)
	var list: Array = ch.skills
	for i in list.size():
		var s: Dictionary = list[i]
		duties.push_customfx(FieldManualStyle.TypedInk.new(), {})
		duties.add_text("%d.  " % (i + 1))
		duties.push_bold()
		duties.push_underline()
		duties.add_text(String(s.name).to_upper())
		duties.pop()
		duties.pop()
		var tag: String = NOT_KEYS.get(String(s.key).to_lower(), "")
		if tag != "":
			duties.add_text(" (%s)." % tag.to_upper())
		duties.add_text("  ")
		duties.pop()
		if tag == "":
			_keycap(duties, String(s.key))
			duties.add_text("  ")
		duties.push_customfx(FieldManualStyle.TypedInk.new(), {})
		duties.add_text(String(s.text))
		duties.pop()
		var fig := _fig_of(String(s.get("clip", "")))
		if fig > 0:
			duties.add_text(" ")
			duties.push_meta("fig:%d" % (fig - 1), RichTextLabel.META_UNDERLINE_ON_HOVER)
			duties.push_color(_pal.accent)
			duties.add_text("(SEE FIG. %d-%d)" % [k, fig])
			duties.pop()
			duties.pop()
		duties.newline()
		duties.push_font_size(6)
		duties.add_text(" ")
		duties.pop()
		duties.newline()
	col.add_child(duties)
	if ch.has("note"):
		col.add_child(_gap(6))
		var note := NoteBox.new()
		note.color = _pal.form
		note.mark = _pal.pencil
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nt := FieldManualStyle.rich(false, 15, _pal.ink)
		nt.push_customfx(FieldManualStyle.TypedInk.new(), {})
		nt.push_bold()
		nt.add_text("NOTE.  ")
		nt.pop()
		nt.add_text(String(ch.note))
		nt.pop()
		note.add_child(nt)
		col.add_child(note)
	_page_number(page, k * 2, 1)
	_fit(col, PAGE.y - 58 - 84)


# ---------------------------------------------------------------- the plate

func _add_video(mount: Control, rect: Rect2) -> void:
	_video = VideoStreamPlayer.new()
	_video.position = rect.position
	_video.size = rect.size
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo_mat = FieldManualStyle.photo_material(_pal)
	_video.material = _photo_mat
	_video.finished.connect(func(): _play(_clip + 1))
	mount.add_child(_video)
	# A clip that isn't there (its video not pulled from LFS): said so on the print, not left blank.
	var f := FieldManualStyle.font("hand") if attacker else FieldManualStyle.font("typed_bold")
	_missing = FieldManualStyle.label("plate not yet developed" if attacker else "PHOTOGRAPH WITHHELD", f,
			34 if attacker else 20, _pal.pencil if attacker else _pal.accent)
	_missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_missing.position = rect.position
	_missing.size = rect.size
	_missing.rotation = deg_to_rad(-4.0 if attacker else 0.0)
	_missing.pivot_offset = rect.size * 0.5
	_missing.visible = false
	mount.add_child(_missing)


## The figure that is clip `id` (1-based), or 0.
func _fig_of(id: String) -> int:
	for i in _clips.size():
		if _clips[i][0] == id:
			return i + 1
	return 0


func _on_meta(meta: Variant) -> void:
	var s := String(meta)
	if s.begins_with("fig:"):
		_play(int(s.get_slice(":", 1)))
		_sound(TAP_SOUND)


## Plays figure `i` of the open chapter (wrapping round); when it ends, the next one plays.
func _play(i: int) -> void:
	if _video == null or _clips.is_empty():
		return
	_clip = posmod(i, _clips.size())
	var id: String = _clips[_clip][0]
	var path := FieldManualData.clip_path(id)
	var stream: VideoStream = load(path) if ResourceLoader.exists(path) else null
	_video.stop()
	_video.stream = stream
	_video.visible = stream != null
	_missing.visible = stream == null
	if stream != null:
		_video.play()
	_photo_mat.set_shader_parameter("flash", 0.5)
	var tw := create_tween()
	tw.tween_method(func(v: float): _photo_mat.set_shader_parameter("flash", v), 0.5, 0.0, 0.35)
	_caption()


## Under the plate: the figures (the one showing in the second colour) and its caption.
func _caption() -> void:
	if _figs == null:
		return
	_figs.clear()
	var cap: String = _clips[_clip][1]
	_figs.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER if attacker else HORIZONTAL_ALIGNMENT_LEFT)
	if attacker:
		_figs.push_font(FieldManualStyle.small_caps(3, 500), 15)
		_figs.push_color(_pal.ink_soft)
		_figs.add_text("Fig.   ")
		_figs.pop()
		_figs.pop()
		for i in _clips.size():
			if i > 0:
				_figs.push_color(_pal.ink_faint)
				_figs.add_text("  ·  ")
				_figs.pop()
			_figs.push_meta("fig:%d" % i, RichTextLabel.META_UNDERLINE_ON_HOVER)
			_figs.push_color(_pal.accent if i == _clip else _pal.ink_soft)
			_figs.push_font(FieldManualStyle.font("serif", 600 if i == _clip else 440, ["onum"]), 18)
			_figs.add_text(str(i + 1))
			_figs.pop()
			_figs.pop()
			_figs.pop()
		_figs.newline()
		_figs.push_italics()
		_figs.add_text(cap)
		_figs.pop()
	else:
		_figs.push_customfx(FieldManualStyle.TypedInk.new(), {})
		_figs.push_bold()
		_figs.add_text("FIG. %d-%d.  " % [_spread, _clip + 1])
		_figs.pop()
		_figs.add_text(cap.to_upper())
		_figs.pop()
		_figs.newline()
		_figs.push_color(_pal.ink_soft)
		_figs.add_text("FIGURES:  ")
		_figs.pop()
		for i in _clips.size():
			_figs.push_meta("fig:%d" % i, RichTextLabel.META_UNDERLINE_ON_HOVER)
			_figs.push_color(_pal.accent if i == _clip else _pal.ink_soft)
			_figs.add_text("[%d-%d]" % [_spread, i + 1] if i == _clip else " %d-%d " % [_spread, i + 1])
			_figs.pop()
			_figs.pop()
			_figs.add_text("  ")
	_figs.pop()


# ---------------------------------------------------------------- parts

## A line of the contents: the whole row turns to its chapter, a hand pointing at it while the pointer is on it.
class ContentsRow:
	extends Control

	signal pressed
	var hand: Control

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _point(true))
		mouse_exited.connect(func(): _point(false))

	func _point(on: bool) -> void:
		if hand:
			var tw := hand.create_tween()
			tw.tween_property(hand, "modulate:a", 1.0 if on else 0.0, 0.12)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()


## A box ruled on the Keep's forms.
class FormBox:
	extends Control

	var color := Color.BLACK

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), color, false, 1.2)


## The note at the foot of an order: a ruled box, bracketed in grease pencil by somebody who meant it.
class NoteBox:
	extends MarginContainer

	var color := Color.BLACK
	var mark := Color.RED

	func _ready() -> void:
		add_theme_constant_override("margin_left", 12)
		add_theme_constant_override("margin_right", 12)
		add_theme_constant_override("margin_top", 8)
		add_theme_constant_override("margin_bottom", 8)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), color, false, 1.2)
		var x := -12.0
		var pts := PackedVector2Array([Vector2(x + 7, -2), Vector2(x, 2), Vector2(x - 1, size.y * 0.5), Vector2(x + 1, size.y - 2),
				Vector2(x + 8, size.y + 2)])
		draw_polyline(pts, mark, 3.0, true)
		draw_polyline(pts, Color(mark, mark.a * 0.3), 6.0, true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


## The other manual, lying under the open one with its edge showing: it slides out a little under the pointer;
## clicked, it is opened instead.
class Peek:
	extends Control

	signal pressed
	var attacker := false
	var hovered := false
	var _lift := 0.0

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Open the Host's field manual (Tab)" if attacker else "Open the Keep's standing orders (Tab)"
		mouse_entered.connect(func():
			hovered = true
			_slide(1.0))
		mouse_exited.connect(func():
			hovered = false
			_slide(0.0))

	func _slide(to: float) -> void:
		var tw := create_tween()
		tw.tween_method(_set_lift, _lift, to, 0.18)

	func _set_lift(v: float) -> void:
		_lift = v
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _has_point(p: Vector2) -> bool:
		# Only the strip that shows beyond the open book.
		return Rect2(size.x - 116.0, 0, 136.0, size.y).has_point(p)

	func _draw() -> void:
		var off := Vector2(18.0 * _lift, 0)
		var r := Rect2(off, size)
		for i in 6:
			var g := 4.0 + i * 5.0
			draw_rect(r.grow(g * 0.5).grow_individual(0, 0, 0, 0), Color(0, 0, 0, 0.07))
		var pal: Dictionary = FieldManualStyle.palette(attacker)
		draw_rect(r, pal.cover)
		draw_rect(Rect2(r.position + Vector2(r.size.x - 10, 0), Vector2(10, r.size.y)), pal.cover_edge)
		var fx := r.end.x - 70.0
		if attacker:
			# Cloth boards, the title stamped in black on the spine side.
			draw_rect(Rect2(Vector2(fx - 18, r.position.y + 40), Vector2(2, r.size.y - 80)), Color(0, 0, 0, 0.35))
			var f := FieldManualStyle.font("gothic", 800, [], 4)
			_vertical(f, "FM 1-01   ·   THE HOST OF EARTH", 20, Vector2(fx + 18, r.position.y + r.size.y * 0.5), Color(0.08, 0.08, 0.04, 0.85))
		else:
			# The binder: a typed label in the spine pocket, a red band.
			var label_r := Rect2(Vector2(fx - 4, r.position.y + 120), Vector2(46, r.size.y - 240))
			draw_rect(label_r, Color(0.88, 0.89, 0.85))
			draw_rect(Rect2(label_r.position, Vector2(label_r.size.x, 100)), pal.accent)
			draw_rect(label_r, Color(0, 0, 0, 0.4), false, 1.0)
			var f := FieldManualStyle.font("typed_bold")
			_vertical(f, "TM 30-90   STANDING ORDERS", 18, label_r.get_center() + Vector2(0, 50), Color(0.1, 0.12, 0.18))
			_vertical(FieldManualStyle.font("form", 800, [], 3), "SECRET", 15, label_r.position + Vector2(label_r.size.x * 0.5, 50), Color(0.95, 0.92, 0.88))
		if _lift > 0.01:
			draw_rect(r, Color(1, 1, 1, 0.05 * _lift))

	func _vertical(f: Font, text: String, fs: int, center: Vector2, c: Color) -> void:
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(center, PI * 0.5, Vector2.ONE)
		draw_string(f, Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## A page being turned: the old page, caught as it was, lifting off and turning over onto the new spread below.
## `u` goes 0 to 1: the first half the old page's face foreshortens toward the spine, revealing the new page
## under it; the second half its back comes down on the other side, the new page on it showing through.
class TurnOverlay:
	extends Control

	var snap: Texture2D
	## Canvas to the snapshot's pixels.
	var xf := Transform2D.IDENTITY
	var left_rect := Rect2()
	var right_rect := Rect2()
	var paper := Color.WHITE
	var dir := 1
	var u := 0.0

	func _draw() -> void:
		if snap == null:
			return
		var spine := left_rect.end.x
		var w := right_rect.size.x if dir > 0 else left_rect.size.x
		var theta := u * PI
		var e := w * cos(theta)
		var lift := sin(theta) * 26.0
		var top := left_rect.position.y
		var bot := left_rect.end.y
		var s := float(dir)
		# The page on the far side stays as it was until the turned one lands on it.
		var far := left_rect if dir > 0 else right_rect
		var covered := maxf(-e, 0.0)
		if dir > 0:
			_region(Rect2(far.position, Vector2(far.size.x - covered, far.size.y)))
		else:
			_region(Rect2(Vector2(far.position.x + covered, far.position.y), Vector2(far.size.x - covered, far.size.y)))
		var edge := spine + s * e
		if e > 0.0:
			# The face of the turning page, squeezed toward the spine; a shadow cast on the page it uncovers.
			var near := right_rect if dir > 0 else left_rect
			var outer_x := near.end.x if dir > 0 else near.position.x
			var shade := 1.0 - 0.45 * sin(theta * 0.5) ** 2
			var pts := PackedVector2Array([Vector2(spine, top), Vector2(edge, top - lift), Vector2(edge, bot + lift), Vector2(spine, bot)])
			var uvs := PackedVector2Array([_uv(Vector2(spine, top)), _uv(Vector2(outer_x, top)), _uv(Vector2(outer_x, bot)), _uv(Vector2(spine, bot))])
			var cols := PackedColorArray([Color(shade * 0.82, shade * 0.82, shade * 0.82), Color(shade, shade, shade), Color(shade, shade, shade),
					Color(shade * 0.82, shade * 0.82, shade * 0.82)])
			_shadow(edge, s, 60.0 * sin(theta), 0.4 * sin(theta))
			draw_polygon(pts, cols, uvs, snap)
		else:
			# The back coming down: blank paper that the new page shows through as it lands.
			var k := smoothstep(0.5, 1.0, u)
			var a := 1.0 - k
			var b := Color(paper.r, paper.g, paper.b, a)
			var dark := Color(paper.r * 0.7, paper.g * 0.7, paper.b * 0.7, a)
			var pts := PackedVector2Array([Vector2(spine, top), Vector2(edge, top - lift), Vector2(edge, bot + lift), Vector2(spine, bot)])
			draw_polygon(pts, PackedColorArray([dark, b, b, dark]))
			# The curve of it: darker toward the spine as it falls.
			var sh := Color(0, 0, 0, 0.25 * sin(theta))
			draw_polygon(PackedVector2Array([Vector2(spine, top), Vector2(spine + (edge - spine) * 0.35, top - lift * 0.35),
					Vector2(spine + (edge - spine) * 0.35, bot + lift * 0.35), Vector2(spine, bot)]),
					PackedColorArray([sh, Color(0, 0, 0, 0), Color(0, 0, 0, 0), sh]))

	func _uv(p: Vector2) -> Vector2:
		return (xf * p) / snap.get_size()

	func _region(r: Rect2) -> void:
		if r.size.x <= 0.5:
			return
		var a := xf * r.position
		var b := xf * r.end
		draw_texture_rect_region(snap, r, Rect2(a, b - a))

	func _shadow(x: float, s: float, width: float, alpha: float) -> void:
		if width < 1.0:
			return
		var top := left_rect.position.y
		var bot := left_rect.end.y
		var c := Color(0, 0, 0, alpha)
		var z := Color(0, 0, 0, 0)
		draw_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + s * width, top), Vector2(x + s * width, bot), Vector2(x, bot)]),
				PackedColorArray([c, z, z, c]))
