class_name CommandSquid
extends Control
## Central command's squid, the attacking army's commander, on the HUD's warning panel (AttackerHUD): it comes up on
## screen while a warning is up (talking: its tentacles sway, its headset's light blinks) and fades away once the
## warnings are old. Drawn with CanvasItem primitives, like the HUD's glyphs.

const BODY := Color(0.6, 0.38, 0.82)
const BELLY := Color(0.78, 0.55, 0.92)
const FADE := 0.6

## Talking: a warning is up.
var talking := false
## The colour of the warning it is giving (the panel's frame).
var tone := UIKit.WARN

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func _process(delta: float) -> void:
	_t += delta
	modulate.a = move_toward(modulate.a, 1.0 if talking else 0.0, delta / FADE)
	if modulate.a > 0.0:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := UIKit.panel_style(Color(0.08, 0.06, 0.12, 0.92), 6)
	sb.border_color = Color(tone, 0.85)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	var s := minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, size.y * 0.42)
	var sway := 1.0 if talking else 0.25
	# Tentacles: eight, swaying out from under the mantle.
	for k in 8:
		var f := (k - 3.5) / 3.5
		var pts := PackedVector2Array()
		var root := c + Vector2(f * s * 0.13, s * 0.12)
		for i in 9:
			var t := i / 8.0
			var wave := sin(_t * 4.0 + k * 0.9 + t * 4.0) * s * 0.05 * t * sway
			pts.append(root + Vector2(f * s * 0.2 * t + wave, t * s * 0.36))
		draw_polyline(pts, BODY.darkened(0.1 * (k % 2)), maxf(2.0, s * 0.045 * (1.0 - 0.5 * absf(f))), true)
	# The mantle: a rounded cone, the fins at its top.
	var mantle := PackedVector2Array()
	for i in 25:
		var th := PI * i / 24.0
		mantle.append(c + Vector2(-cos(th) * s * 0.2, -sin(th) * s * 0.36 * (0.6 + 0.4 * sin(th)) + s * 0.12))
	draw_colored_polygon(mantle, BODY)
	var top := c + Vector2(0, -s * 0.26)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(-s * 0.2, s * 0.06), top + Vector2(-s * 0.06, s * 0.1)]), BODY.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(s * 0.2, s * 0.06), top + Vector2(s * 0.06, s * 0.1)]), BODY.darkened(0.15))
	draw_circle(c + Vector2(0, s * 0.02), s * 0.1, BELLY)
	# Eyes, looking about.
	var look := Vector2(sin(_t * 0.7) * 0.4, 0.1) * s * 0.03
	for side in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(side * s * 0.09, s * 0.02)
		draw_circle(e, s * 0.055, Color(0.97, 0.97, 1.0))
		draw_circle(e + look, s * 0.03, Color(0.05, 0.04, 0.1))
	# The commander's headset: a band over the mantle, the mic at the side, its light blinking while it talks.
	draw_arc(c + Vector2(0, -s * 0.02), s * 0.22, PI * 1.05, PI * 1.95, 18, Color(0.15, 0.16, 0.2), maxf(2.0, s * 0.03), true)
	var ear := c + Vector2(s * 0.21, s * 0.0)
	draw_circle(ear, s * 0.04, Color(0.15, 0.16, 0.2))
	draw_line(ear, ear + Vector2(-s * 0.06, s * 0.14), Color(0.15, 0.16, 0.2), maxf(1.5, s * 0.02), true)
	var lit := talking and fmod(_t * 2.5, 1.0) < 0.5
	draw_circle(ear + Vector2(-s * 0.06, s * 0.14), s * 0.022, UIKit.DANGER if lit else Color(0.3, 0.1, 0.1))
	var font := get_theme_default_font()
	var fs := clampi(int(s * 0.11), 8, 13)
	draw_string(font, Vector2(0, size.y - 5.0), "COMMAND", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0.85, 0.8, 0.95))
