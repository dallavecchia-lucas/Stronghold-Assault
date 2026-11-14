class_name HudSlot
extends Control
## One square tile of the attacker's HUD (AttackerHUD): a unit's portrait (UnitPortraits; its initials until the portrait
## is in), or a skill's glyph (HudGlyph), with
##   key_text      a key badge at the bottom (the hotkey)
##   corner_text   a count at the top right
##   center_text   big in the middle, over everything (a cooldown's seconds)
##   cooldown      the share of a cooldown still to run: a dark sweep, clockwise from twelve o'clock
##   progress      a bar along the bottom (0 to 1; below 0 none): a unit being built
##   disabled      dimmed (can't afford it, nothing ready)
##   active        lit border (aiming this skill, the focused group)
##   empty         an empty slot: no picture, a dashed look
## The owner sets these each frame and calls queue_redraw(). Clicks come out as `clicked` (LMB and RMB, double clicks
## and modifiers on the event).

signal clicked(event: InputEventMouseButton)

const BG := Color(0.13, 0.15, 0.19, 0.95)
const EMPTY_BG := Color(0.05, 0.06, 0.08, 0.7)
const BORDER := Color(0.42, 0.48, 0.58, 0.8)
const HOVER := Color(0.75, 0.85, 1.0)

var texture: Texture2D
var glyph := ""
var glyph_color := Color(0.92, 0.96, 1.0)
var initials := ""
var tint := BG
var key_text := ""
var corner_text := ""
var center_text := ""
var cooldown := 0.0
var progress := -1.0
var disabled := false
var active := false
var empty := false
var accent := UIKit.ACCENT

var _hover := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		clicked.emit(mb)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var inner := r.grow(-2.0)
	var font := get_theme_default_font()
	draw_rect(r, EMPTY_BG if empty else tint)
	if not empty:
		if texture:
			draw_texture_rect(texture, inner, false)
		elif glyph != "":
			HudGlyph.draw(self, glyph, inner.grow(-inner.size.x * 0.16), glyph_color if not disabled else Color(0.6, 0.62, 0.68),
					maxf(1.4, size.x / 30.0))
		elif initials != "":
			_text(font, Vector2(0.0, size.y * 0.5), initials, int(size.y * 0.34), Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, true)
	if disabled:
		draw_rect(r, Color(0, 0, 0, 0.55))
	if cooldown > 0.0:
		_sweep(r.get_center(), r.size.length() * 0.5, clampf(cooldown, 0.0, 1.0))
	if progress >= 0.0:
		var bar := Rect2(inner.position.x, inner.end.y - 5.0, inner.size.x, 5.0)
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), accent)
	var border := accent if active else HOVER if _hover and not empty else BORDER
	if empty:
		border = Color(BORDER, 0.35)
	draw_rect(r.grow(-0.5), border, false, 2.0 if active else 1.0)
	var fs := clampi(int(size.y * 0.24), 9, 15)
	if corner_text != "":
		_text(font, Vector2(size.x - 3.0, 2.0), corner_text, fs, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	if center_text != "":
		_text(font, Vector2(0.0, size.y * 0.5), center_text, clampi(int(size.y * 0.3), 10, 22), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	if key_text != "":
		var ks := clampi(int(size.y * 0.26), 9, 14)
		var tw := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
		var badge := Rect2(Vector2((size.x - tw) * 0.5 - 3.0, size.y - ks - 4.0), Vector2(tw + 6.0, ks + 3.0))
		if progress >= 0.0:
			badge.position.y -= 5.0
		draw_rect(badge, Color(0.02, 0.03, 0.05, 0.85))
		draw_rect(badge, Color(accent, 0.6), false, 1.0)
		_text(font, Vector2(badge.position.x, badge.position.y + 1.0), key_text, ks, UIKit.WARN if not disabled else Color(0.7, 0.7, 0.7),
				HORIZONTAL_ALIGNMENT_CENTER, false, badge.size.x)


## The remaining share `frac` of a cooldown: a dark pie from twelve o'clock round clockwise (the tile clips it square).
func _sweep(c: Vector2, radius: float, frac: float) -> void:
	var pts := PackedVector2Array([c])
	var steps := maxi(int(48 * frac), 2)
	for k in steps + 1:
		pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * frac * k / steps) * radius)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.62))


## Text with a dark outline. `at` is its top edge (`middle`: its vertical middle); with `align` centre or right it is set
## in `width` (the tile's width by default) from at.x, right: ending at at.x.
func _text(font: Font, at: Vector2, text: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, middle := false,
		width := -1.0) -> void:
	var base := at.y + font.get_ascent(fs)
	if middle:
		base = at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var x := at.x
	var w := width
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		w = at.x
		x = 0.0
	elif align == HORIZONTAL_ALIGNMENT_CENTER and w < 0.0:
		w = size.x
	draw_string_outline(font, Vector2(x, base), text, align, w, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(x, base), text, align, w, fs, col)
