class_name CreditsBanner
extends Control
## The trapezoid at the top centre of the attacker's HUD (AttackerHUD): spawn credits on the left (the income and the
## army's size under them), the air vents destroyed out of the total on the right (every one of them down wins the match),
## and under it a narrower strip with the match clock (the defenders win when it runs out) and the gates' health.

const WIDTH := 500.0
const HEIGHT := 66.0
const STRIP_W := 330.0
const STRIP_H := 26.0
const FILL := Color(0.06, 0.07, 0.09, 0.86)
const EDGE := Color(0.42, 0.48, 0.58, 0.7)
const CAPTION := Color(0.7, 0.75, 0.85)

var credits := 0
var income := 0.0
var army := 0
## Units on the production line (they count toward the cap).
var queued := 0
var army_cap := 0
var vents_down := 0
var vents_total := 0
## Seconds left in the match (<0: no clock).
var time_left := -1.0
## [[side letter, health 0..1, under attack now]] per gate.
var gates: Array = []
## The credits flash red for a moment after a unit couldn't be paid for.
var short_flash := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT + STRIP_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	short_flash = maxf(short_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var slant := 34.0
	var top := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - slant, HEIGHT), Vector2(slant, HEIGHT)])
	draw_colored_polygon(top, FILL)
	var outline := top.duplicate()
	outline.append(top[0])
	draw_polyline(outline, EDGE, 1.0, true)
	var mid := w * 0.5
	draw_line(Vector2(mid, 8), Vector2(mid, HEIGHT - 8), EDGE, 1.0)

	# Spawn credits.
	_caption(font, Vector2(slant, 6), mid - slant, "SPAWN CREDITS")
	var col := UIKit.DANGER.lerp(UIKit.WARN, 1.0 - short_flash / 0.6) if short_flash > 0.0 else UIKit.WARN
	_big(font, Vector2(slant, 40), mid - slant, str(credits), col)
	var army_text := "ARMY %d/%d" % [army, army_cap] if queued == 0 else "ARMY %d+%d/%d" % [army, queued, army_cap]
	_caption(font, Vector2(slant, 46), mid - slant, "+%.1f/s  ·  %s" % [income, army_text],
			UIKit.DANGER if army + queued >= army_cap else CAPTION)

	# Vents destroyed / total.
	_caption(font, Vector2(mid, 6), w * 0.5 - slant, "VENTS DESTROYED")
	_big(font, Vector2(mid, 40), w * 0.5 - slant, "%d / %d" % [vents_down, vents_total],
			UIKit.GOOD if vents_down >= vents_total and vents_total > 0 else Color.WHITE)
	_caption(font, Vector2(mid, 46), w * 0.5 - slant, "all %d for victory" % vents_total)

	# The strip: the clock and the gates.
	var sx := (w - STRIP_W) * 0.5
	var strip := PackedVector2Array([Vector2(sx, HEIGHT), Vector2(sx + STRIP_W, HEIGHT),
			Vector2(sx + STRIP_W - 14, HEIGHT + STRIP_H), Vector2(sx + 14, HEIGHT + STRIP_H)])
	draw_colored_polygon(strip, FILL)
	draw_polyline(PackedVector2Array([strip[1], strip[2], strip[3], strip[0]]), EDGE, 1.0, true)
	var x := sx + 22.0
	if time_left >= 0.0:
		var t := int(ceil(time_left))
		var clock := "%d:%02d" % [t / 60, t % 60]
		draw_string(font, Vector2(x, HEIGHT + 19), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				UIKit.DANGER if time_left < 60.0 else Color.WHITE)
		x += 66.0
	for g in gates:
		draw_string(font, Vector2(x, HEIGHT + 17), "%s" % g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CAPTION)
		var bar := Rect2(x + 12, HEIGHT + 9, 52, 8)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		var hp: float = g[1]
		var gate_col := UIKit.GOOD if hp <= 0.0 else UIKit.DANGER if g[2] else UIKit.WARN
		if hp <= 0.0:
			draw_string(font, Vector2(bar.position.x + 2, HEIGHT + 17), "OPEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gate_col)
		else:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), gate_col)
		x += 76.0


func _caption(font: Font, at: Vector2, width: float, text: String, col := CAPTION) -> void:
	draw_string(font, Vector2(at.x, at.y + 11), text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, col)


func _big(font: Font, at: Vector2, width: float, text: String, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 24, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 24, col)
