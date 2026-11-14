class_name CreditsBanner
extends Control
## The trapezoid at the top centre of the attacker's HUD (AttackerHUD): spawn credits on the left (the income and the
## army's size under them), the air vents destroyed out of the total on the right (every one of them down wins the match),
## and under it a narrower strip: the match clock (the defenders win when it runs out), the gates' health, the folding
## bridges left (click: drop one) and the outposts held (click: look at the next). Hover any of them for more.

signal bridges_pressed
signal outposts_pressed

const WIDTH := 400.0
const HEIGHT := 50.0
const STRIP_W := 380.0
const STRIP_H := 22.0
const FILL := Color(0.06, 0.07, 0.09, 0.86)
const EDGE := Color(0.42, 0.48, 0.58, 0.7)
const CAPTION := Color(0.7, 0.75, 0.85)
const SMALL := 11

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
## Folding bridges left (<0: none on this map), and the outposts.
var bridges_left := -1
var outposts_held := 0
var outposts_total := 0
var outposts_tip := ""
## The credits flash red for a moment after a unit couldn't be paid for.
var short_flash := 0.0

## [Rect2, tooltip, signal name or ""] for the parts of the strip, as last drawn.
var _regions: Array = []


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT + STRIP_H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	short_flash = maxf(short_flash - delta, 0.0)
	queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	for r in _regions:
		if (r[0] as Rect2).has_point(at_position):
			return r[1]
	if at_position.y < HEIGHT:
		if at_position.x < size.x * 0.5:
			return "Spawn credits: units are paid for when they go on the production line\n+%.1f a second · army %d of %d (%d on the line)" \
					% [income, army, army_cap, queued]
		return "Air vents on the roofs: destroy all %d to win" % vents_total
	return ""


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for r in _regions:
		if (r[0] as Rect2).has_point(mb.position) and r[2] != "":
			emit_signal(r[2])
			accept_event()


func _draw() -> void:
	_regions.clear()
	var font := get_theme_default_font()
	var w := size.x
	var slant := 28.0
	var top := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - slant, HEIGHT), Vector2(slant, HEIGHT)])
	draw_colored_polygon(top, FILL)
	var outline := top.duplicate()
	outline.append(top[0])
	draw_polyline(outline, EDGE, 1.0, true)
	var mid := w * 0.5
	draw_line(Vector2(mid, 7), Vector2(mid, HEIGHT - 7), EDGE, 1.0)

	# Spawn credits.
	_caption(font, Vector2(slant, 3), mid - slant, "SPAWN CREDITS")
	var col := UIKit.DANGER.lerp(UIKit.WARN, 1.0 - short_flash / 0.6) if short_flash > 0.0 else UIKit.WARN
	_big(font, Vector2(slant, 34), mid - slant, str(credits), col)
	var army_text := "ARMY %d/%d" % [army, army_cap] if queued == 0 else "ARMY %d+%d/%d" % [army, queued, army_cap]
	_caption(font, Vector2(slant, 36), mid - slant, "+%.1f/s  ·  %s" % [income, army_text],
			UIKit.DANGER if army + queued >= army_cap else CAPTION)

	# Vents destroyed / total.
	_caption(font, Vector2(mid, 3), w * 0.5 - slant, "VENTS DESTROYED")
	_big(font, Vector2(mid, 34), w * 0.5 - slant, "%d / %d" % [vents_down, vents_total],
			UIKit.GOOD if vents_down >= vents_total and vents_total > 0 else Color.WHITE)
	_caption(font, Vector2(mid, 36), w * 0.5 - slant, "all %d for victory" % vents_total)

	# The strip: the clock, the gates, the bridges and the outposts.
	var sx := (w - STRIP_W) * 0.5
	var strip := PackedVector2Array([Vector2(sx, HEIGHT), Vector2(sx + STRIP_W, HEIGHT),
			Vector2(sx + STRIP_W - 12, HEIGHT + STRIP_H), Vector2(sx + 12, HEIGHT + STRIP_H)])
	draw_colored_polygon(strip, FILL)
	draw_polyline(PackedVector2Array([strip[1], strip[2], strip[3], strip[0]]), EDGE, 1.0, true)
	var y := HEIGHT + 15.0
	var x := sx + 18.0
	if time_left >= 0.0:
		var t := int(ceil(time_left))
		draw_string(font, Vector2(x, y + 1), "%d:%02d" % [t / 60, t % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				UIKit.DANGER if time_left < 60.0 else Color.WHITE)
		_regions.append([Rect2(x, HEIGHT, 44, STRIP_H), "Time left: the defenders win when it runs out", ""])
		x += 50.0
	for g in gates:
		var hp: float = g[1]
		var gate_col := UIKit.GOOD if hp <= 0.0 else UIKit.DANGER if g[2] else UIKit.WARN
		draw_string(font, Vector2(x, y), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, CAPTION)
		var bar := Rect2(x + 10, HEIGHT + 8, 34, 7)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		if hp <= 0.0:
			draw_string(font, Vector2(bar.position.x, y), "OPEN", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, gate_col)
		else:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), gate_col)
		_regions.append([Rect2(x, HEIGHT, 48, STRIP_H), "%s gate: %s" % [g[0], "OPEN (broken): infiltrators can go in" if hp <= 0.0
				else "%d%%%s" % [roundi(hp * 100.0), " · under attack" if g[2] else ""]], ""])
		x += 52.0
	x += 4.0
	if bridges_left >= 0:
		HudGlyph.draw(self, "bridge", Rect2(x, HEIGHT + 3, 16, 16), Color(0.85, 0.92, 1.0), 1.4)
		draw_string(font, Vector2(x + 19, y), "×%d" % bridges_left, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Color.WHITE if bridges_left > 0 else UIKit.DANGER)
		_regions.append([Rect2(x, HEIGHT, 44, STRIP_H), "Folding bridges left: %d · click (or Shift+B) to drop one across a river" % bridges_left,
				"bridges_pressed"])
		x += 48.0
	if outposts_total > 0:
		HudGlyph.draw(self, "outpost", Rect2(x, HEIGHT + 3, 16, 16), Color(0.85, 0.92, 1.0), 1.4)
		draw_string(font, Vector2(x + 19, y), "%d/%d" % [outposts_held, outposts_total], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL,
				Color.WHITE if outposts_held == outposts_total else UIKit.WARN)
		_regions.append([Rect2(x, HEIGHT, 48, STRIP_H), outposts_tip, "outposts_pressed"])


func _caption(font: Font, at: Vector2, width: float, text: String, col := CAPTION) -> void:
	draw_string(font, Vector2(at.x, at.y + 11), text, HORIZONTAL_ALIGNMENT_CENTER, width, SMALL, col)


func _big(font: Font, at: Vector2, width: float, text: String, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 20, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 20, col)
