class_name UIKit
extends RefCounted
## Small helpers for building HUD widgets in code with a consistent look.

const PANEL_BG := Color(0.06, 0.07, 0.09, 0.78)
const ACCENT := Color(0.35, 0.7, 1.0)
const DANGER := Color(1.0, 0.35, 0.28)
const GOOD := Color(0.4, 0.95, 0.5)
const WARN := Color(1.0, 0.8, 0.25)


static func panel_style(bg := PANEL_BG, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func panel(bg := PANEL_BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p


static func label(text := "", size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func button(text: String, size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var normal := panel_style(Color(0.14, 0.16, 0.2, 0.92))
	var hover := panel_style(Color(0.2, 0.3, 0.42, 0.95))
	var pressed := panel_style(Color(0.25, 0.45, 0.65, 0.95))
	var disabled := panel_style(Color(0.1, 0.1, 0.12, 0.7))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func bar(width: float, height: float, fill: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(width, height)
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


static func set_bar_color(pb: ProgressBar, color: Color) -> void:
	var fg := pb.get_theme_stylebox("fill") as StyleBoxFlat
	if fg and fg.bg_color != color:
		fg = fg.duplicate()
		fg.bg_color = color
		pb.add_theme_stylebox_override("fill", fg)


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c
