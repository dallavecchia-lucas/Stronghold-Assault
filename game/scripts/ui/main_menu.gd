extends Control
## Title screen: pick a side and difficulty, then start an offline match vs the CPU.
##
## Behind the menu, the Earth from orbit with a war on it and an alien mothership circling
## (MenuBackdrop, which also swivels the 3D title). Over it, a feed-from-orbit overlay: scanlines and
## vignette, corner brackets, telemetry, and a reticle that tracks the mothership.

const ACCENT := Color(1.0, 0.42, 0.18)
const COOL := Color(0.45, 0.78, 1.0)
const TEXT := Color(0.9, 0.93, 1.0)
const DIM := Color(0.55, 0.64, 0.78)
const MENU_LEFT := 110.0
const MENU_TOP := 392.0
const MENU_WIDTH := 470.0

var backdrop: MenuBackdrop
var _font_bold: Font
var _font: Font
var _fade: ColorRect
var _items: Array[Control] = []
var _reticle: Control
var _reticle_label: Label
var _reticle_alpha := 0.0
var _clock: Label
var _live: Label
var _threat: Label
var _zones: Label
var _time := 0.0
var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Engine.time_scale = 1.0

	if GameConfig.autotest != "" or GameConfig.sim != "":
		_start(GameConfig.PlayerSide.ATTACKER if GameConfig.autotest == "attacker" else GameConfig.PlayerSide.DEFENDER)
		return

	_font_bold = load("res://assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf")
	_font = load("res://assets/fonts/jetbrains_mono/JetBrainsMono-Medium.ttf")

	backdrop = MenuBackdrop.new()
	add_child(backdrop)

	_build_overlay()
	_build_menu()
	_build_hud()

	_fade = UIKit.full_rect(ColorRect.new()) as ColorRect
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_intro_items()


func _process(delta: float) -> void:
	if backdrop == null:
		return
	_time += delta
	_update_reticle(delta)
	_clock.text = "UTC %s" % Time.get_time_string_from_system(true)
	_live.modulate.a = 1.0 if fmod(_time, 1.2) < 0.75 else 0.15
	_threat.modulate.a = 0.55 + 0.45 * absf(sin(_time * 2.4))
	_zones.text = "CONFLICT ZONES ACTIVE   %02d" % backdrop.hotspots.size()


# --- menu ---------------------------------------------------------------------------------------------

func _build_menu() -> void:
	# A shade down the left so the menu reads over the globe and the stars.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 900
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.01, 0.03, 0.82))
	grad.set_color(1, Color(0.0, 0.01, 0.03, 0.0))
	grad.add_point(0.55, Color(0.0, 0.01, 0.03, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)

	var box := VBoxContainer.new()
	box.position = Vector2(MENU_LEFT, MENU_TOP)
	box.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	box.add_child(_section("SELECT DEPLOYMENT"))
	var defend := _menu_button("DEFEND THE STRONGHOLD", "First person  ·  switch between posts", true)
	defend.pressed.connect(_start.bind(GameConfig.PlayerSide.DEFENDER))
	box.add_child(defend)
	var attack := _menu_button("LEAD THE ASSAULT", "Command the siege army", true)
	attack.pressed.connect(_start.bind(GameConfig.PlayerSide.ATTACKER))
	box.add_child(attack)

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	box.add_child(_section("MISSION PARAMETERS"))
	box.add_child(_cycler("CPU DIFFICULTY", GameConfig.DIFFICULTY_NAMES, GameConfig.difficulty,
		func(i): GameConfig.difficulty = i, ""))
	box.add_child(_cycler("LIGHTING", GameConfig.LIGHTING_NAMES, maxi(GameConfig.LIGHTING.find(GameConfig.lighting), 0),
		func(i): GameConfig.lighting = GameConfig.LIGHTING[i],
		"Ray-traced: global illumination, ray-traced contact shadows, volumetric clouds and reflections.\nStandard: lighter on the GPU."))

	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 6
	box.add_child(gap2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var intro := _menu_button("WATCH INTRO", "", false)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.pressed.connect(_leave.bind("res://scenes/intro.tscn"))
	row.add_child(intro)
	var quit := _menu_button("QUIT", "", false)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)
	box.add_child(row)

	for c in box.get_children():
		_items.append(c)
	defend.grab_focus.call_deferred()

	var foot := _label("STRONGHOLD ASSAULT  ·  OFFLINE SKIRMISH VS CPU", 13, Color(DIM, 0.75), _font)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(MENU_LEFT, -48)
	add_child(foot)
	var keys := _label("↑ ↓  SELECT     ← →  CHANGE     ENTER  CONFIRM", 12, Color(DIM, 0.45), _font)
	keys.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	keys.position = Vector2(MENU_LEFT, -28)
	add_child(keys)


func _section(text: String) -> Control:
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
	return row


func _style(bg: Color, edge: Color, edge_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.border_width_left = edge_w
	sb.border_width_bottom = 1
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_right = 2
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	return sb


## A menu entry: a title and an optional caption, a bar down its left that lights up and an arrow
## that slides in when it is pointed at or focused.
func _menu_button(title: String, caption: String, big: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 66 if big else 44)
	b.focus_mode = Control.FOCUS_ALL
	var idle := _style(Color(0.02, 0.04, 0.07, 0.55), Color(COOL, 0.35), 2)
	idle.border_color = Color(COOL, 0.35)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", idle)
	b.add_theme_stylebox_override("pressed", idle)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# The highlight: a warm wash fading out to the right, drawn under the text.
	var wash := TextureRect.new()
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(wash)
	var g := Gradient.new()
	g.set_color(0, Color(ACCENT, 0.42))
	g.set_color(1, Color(ACCENT, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 2
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.modulate.a = 0.0
	b.add_child(wash)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.offset_right = 4
	bar.modulate.a = 0.0
	b.add_child(bar)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 16)
	b.add_child(margin)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	margin.add_child(hb)
	var arrow := _label("▶", 14 if big else 11, ACCENT, _font_bold)
	arrow.modulate.a = 0.0
	arrow.custom_minimum_size.x = 0
	hb.add_child(arrow)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)
	var t := _label(title, 24 if big else 16, TEXT, _font_bold)
	col.add_child(t)
	if caption != "":
		col.add_child(_label(caption, 13, DIM, _font))

	var lit := func(on: bool) -> void:
		var tw := b.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(wash, "modulate:a", 1.0 if on else 0.0, 0.18)
		tw.tween_property(bar, "modulate:a", 1.0 if on else 0.0, 0.18)
		tw.tween_property(arrow, "modulate:a", 1.0 if on else 0.0, 0.18)
		tw.tween_method(func(v): margin.add_theme_constant_override("margin_left", int(v)),
			float(margin.get_theme_constant("margin_left")), 30.0 if on else 22.0, 0.18)
		t.add_theme_color_override("font_color", Color(1.0, 0.92, 0.85) if on else TEXT)
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(lit.bind(true))
	b.focus_exited.connect(lit.bind(false))
	b.button_down.connect(func(): wash.modulate.a = 1.6)
	return b


## A setting: its name on the left, its value on the right between arrows. Clicking (or Enter) steps
## to the next value; left and right step either way.
func _cycler(title: String, names: Array, current: int, on_change: Callable, tip: String) -> Button:
	var b := _menu_button(title, "", false)
	b.tooltip_text = tip
	var hb := b.get_child(2).get_child(0) as HBoxContainer
	var value := _label("", 16, ACCENT, _font_bold)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(value)
	var state := {"i": current}
	var show := func() -> void:
		value.text = "◀  %s  ▶" % String(names[state.i]).to_upper()
	show.call()
	var step := func(d: int) -> void:
		state.i = posmod(state.i + d, names.size())
		on_change.call(state.i)
		show.call()
		var tw := value.create_tween()
		value.modulate = Color(1.6, 1.6, 1.6)
		tw.tween_property(value, "modulate", Color.WHITE, 0.25)
	b.pressed.connect(step.bind(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event())
	return b


func _intro_items() -> void:
	for i in _items.size():
		var c := _items[i]
		c.modulate.a = 0.0
		var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.9 + i * 0.07)
		tw.tween_property(c, "modulate:a", 1.0, 0.5)


# --- overlay & hud ------------------------------------------------------------------------------------

func _build_overlay() -> void:
	var fx := UIKit.full_rect(ColorRect.new()) as ColorRect
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type canvas_item;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = (uv - 0.5) * vec2(1.3, 1.0);
	float vig = smoothstep(0.42, 1.0, length(c) * 1.2);
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 2.0);
	float roll = smoothstep(0.0, 0.04, fract(uv.y * 0.6 - TIME * 0.05)) * (1.0 - smoothstep(0.04, 0.12, fract(uv.y * 0.6 - TIME * 0.05)));
	float grain = hash(FRAGCOORD.xy + fract(TIME) * 100.0);
	vec3 col = mix(vec3(0.0), vec3(0.55, 0.75, 1.0), grain * 0.35 + roll * 0.6);
	COLOR = vec4(col, vig * 0.85 + scan * 0.05 + grain * 0.025 + roll * 0.025);
}
"""
	m.shader = s
	fx.material = m
	add_child(fx)


func _build_hud() -> void:
	var frame := HudFrame.new()
	UIKit.full_rect(frame)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	# Top right: the feed.
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-380, 44)
	top.custom_minimum_size.x = 330
	top.add_theme_constant_override("separation", 2)
	add_child(top)
	var r1 := HBoxContainer.new()
	r1.alignment = BoxContainer.ALIGNMENT_END
	r1.add_theme_constant_override("separation", 14)
	r1.add_child(_label("ORBITAL FEED  ·  SAT-07", 14, Color(COOL, 0.9), _font_bold))
	_live = _label("● LIVE", 14, Color(1.0, 0.25, 0.2), _font_bold)
	r1.add_child(_live)
	top.add_child(r1)
	_clock = _label("", 13, Color(DIM, 0.8), _font)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_clock)
	var alt := _label("ALT 35,786 KM  ·  GEO-SYNC  ·  IR/VIS", 13, Color(DIM, 0.6), _font)
	alt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(alt)

	# Bottom right: the situation.
	var bot := VBoxContainer.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bot.position = Vector2(-420, -110)
	bot.custom_minimum_size.x = 370
	bot.add_theme_constant_override("separation", 2)
	add_child(bot)
	_zones = _label("", 14, Color(1.0, 0.55, 0.35), _font_bold)
	_zones.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot.add_child(_zones)
	_threat = _label("GLOBAL THREAT LEVEL   CRITICAL", 14, Color(1.0, 0.3, 0.25), _font_bold)
	_threat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot.add_child(_threat)
	var ufo := _label("UNIDENTIFIED VESSEL IN HIGH ORBIT", 13, Color(DIM, 0.7), _font)
	ufo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot.add_child(ufo)

	# The reticle that follows the mothership.
	_reticle = Reticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.size = Vector2(120, 70)
	_reticle.modulate.a = 0.0
	add_child(_reticle)
	_reticle_label = _label("", 11, Color(1.0, 0.4, 0.3), _font_bold)
	_reticle_label.position = Vector2(0, 76)
	_reticle.add_child(_reticle_label)


func _update_reticle(delta: float) -> void:
	var info := backdrop.ark_on_screen()
	var p: Vector2 = backdrop.camera.unproject_position(info.pos)
	var view := get_viewport_rect().size
	var on := bool(info.visible) and Rect2(Vector2.ZERO, view).grow(-30).has_point(p)
	_reticle_alpha = move_toward(_reticle_alpha, 1.0 if on else 0.0, delta * 2.5)
	_reticle.modulate.a = _reticle_alpha * (0.8 + 0.2 * sin(_time * 9.0))
	# The box fits the hull as it appears (its length on screen), a little loose.
	var cam := backdrop.camera
	var span := cam.unproject_position(info.bow).distance_to(cam.unproject_position(info.stern))
	var w := clampf(span * 1.1, 70.0, 320.0)
	_reticle.size = Vector2(w, maxf(w * 0.45, 46.0))
	_reticle.position = p - _reticle.size * 0.5
	# The label under the box, or tucked to its left near the right edge of the screen.
	var left := p.x + 170.0 > view.x
	_reticle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
	_reticle_label.position = Vector2(_reticle.size.x - _reticle_label.size.x if left else 0.0, _reticle.size.y + 6)
	var km := (float(info.distance)) * 6371.0 / MenuBackdrop.EARTH_RADIUS
	_reticle_label.text = "UNKNOWN CONTACT\nRANGE %s KM" % _thousands(int(km))


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


# --- leaving ------------------------------------------------------------------------------------------

func _start(side: GameConfig.PlayerSide) -> void:
	GameConfig.player_side = side
	if _fade == null:
		get_tree().change_scene_to_file.call_deferred("res://scenes/match.tscn")
		return
	_leave("res://scenes/match.tscn")


func _leave(scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene))


## Corner brackets and a faint centre cross, like the frame of a camera feed.
class HudFrame:
	extends Control

	func _draw() -> void:
		var c := Color(0.45, 0.78, 1.0, 0.35)
		var m := 26.0
		var l := 46.0
		var r := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
			var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), c, 2.0)
			draw_line(corner, corner + Vector2(0, l * sy), c, 2.0)
		# Range ticks along the bottom edge.
		var y := r.end.y - 4.0
		for i in 41:
			var x := lerpf(size.x * 0.5 - 200.0, size.x * 0.5 + 200.0, i / 40.0)
			draw_line(Vector2(x, y), Vector2(x, y - (8.0 if i % 5 == 0 else 4.0)), Color(c, 0.25), 1.0)


## Brackets around the tracked mothership.
class Reticle:
	extends Control

	func _draw() -> void:
		var c := Color(1.0, 0.32, 0.25, 0.9)
		var l := minf(size.x, size.y) * 0.28
		var r := Rect2(Vector2.ZERO, size)
		for corner in [r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]:
			var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
			var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), c, 1.5)
			draw_line(corner, corner + Vector2(0, l * sy), c, 1.5)
		draw_circle(size * 0.5, 2.0, c)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
