class_name BaseView
extends Control
## The defender's tactical view of the base (DefenderHUD, top right by the minimap), north up like the minimap:
##   the four rectangles round it   each side's guns (its gun deck's and its roof's), filled to their health together and
##                                  coloured by it; a red count of the attackers close to that side; the gate (south, east,
##                                  west) a notch on the stronghold's face, by its health (crossed when broken)
##   the ring inside it             the player's garrison spawn: a dot on the ring at the side it is on (Y moves it)
##   the circle in the middle       what the soldiers it spawns go for: B (BASE: guns, decks, then the field) or F (FIELD,
##                                  straight out) (U switches)
## Click a side to move the spawn there, the middle to switch BASE / FIELD (with the mouse free).
## DefenderHUD sets `sides`, `spawn_side`, `priority` and the rest every few frames.

signal side_pressed(side: String)
signal centre_pressed

const FONT := 11
const BAND := 0.17  # the rectangles' depth, a share of the view's side
const CORE := 0.28  # where the stronghold's square starts, a share of the side
const KEYS_H := 16.0

## side -> {"guns": health 0..1 (-1: none), "alive": n, "total": n, "crewed": n, "near": attackers close, "gate": health
## 0..1 (-1: no gate)}
var sides := {}
var spawn_side := "south"
## Garrison.Priority: 0 BASE, 1 FIELD.
var priority := 0
## Soldiers out per spawn round on each side (the player's and the others' controls), for the tooltip.
var spawn_counts := {}
var summary_text := ""

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## The square the base is drawn in (the strip of keys under it).
func _square() -> Rect2:
	var s := minf(size.x, size.y - KEYS_H)
	return Rect2(Vector2((size.x - s) * 0.5, 0.0), Vector2(s, s))


## The rectangle of `side` in the square `q`.
func _side_rect(q: Rect2, side: String) -> Rect2:
	var s := q.size.x
	var band := s * BAND
	var lo := s * CORE
	var span := s - 2.0 * lo
	match side:
		"north":
			return Rect2(q.position + Vector2(lo, s * 0.04), Vector2(span, band))
		"south":
			return Rect2(q.position + Vector2(lo, s * 0.96 - band), Vector2(span, band))
		"west":
			return Rect2(q.position + Vector2(s * 0.04, lo), Vector2(band, span))
		_:
			return Rect2(q.position + Vector2(s * 0.96 - band, lo), Vector2(band, span))


static func _dir(side: String) -> Vector2:
	return {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}.get(side, Vector2.DOWN)


static func health_color(f: float) -> Color:
	return UIKit.DANGER if f <= 0.35 else UIKit.WARN if f <= 0.7 else UIKit.GOOD


func _draw() -> void:
	var font := get_theme_default_font()
	var q := _square()
	var s := q.size.x
	var c := q.get_center()
	# The stronghold.
	var core := Rect2(q.position + Vector2(s * CORE, s * CORE), Vector2(s, s) * (1.0 - 2.0 * CORE))
	draw_rect(core, Color(0.2, 0.2, 0.22, 0.95))
	draw_rect(core, Color(0.5, 0.52, 0.56, 0.8), false, 1.0)
	for side in ["north", "east", "south", "west"]:
		var r := _side_rect(q, side)
		var d: Dictionary = sides.get(side, {})
		var f: float = d.get("guns", -1.0)
		draw_rect(r, Color(0, 0, 0, 0.55))
		if f >= 0.0:
			var col := health_color(f)
			var fill := r
			if side in ["north", "south"]:
				fill.size.x *= f
			else:
				fill.position.y += r.size.y * (1.0 - f)
				fill.size.y *= f
			draw_rect(fill, Color(col, 0.85))
		draw_rect(r, Color(0.6, 0.65, 0.72, 0.8), false, 1.0)
		draw_string(font, r.get_center() + Vector2(-4, 4), side.left(1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT,
				Color(1, 1, 1, 0.95))
		# Attackers close to that side.
		var near: int = d.get("near", 0)
		if near > 0:
			var at := r.get_center() + _dir(side) * (s * BAND * 0.5 + 8.0)
			var blink := 0.6 + 0.4 * sin(_t * 8.0)
			draw_circle(at, 7.0, Color(UIKit.DANGER, blink))
			draw_string(font, at + Vector2(-7, 4), str(near), HORIZONTAL_ALIGNMENT_CENTER, 14, FONT, Color.WHITE)
		# The gate: a notch on the stronghold's face.
		var g: float = d.get("gate", -1.0)
		if g > -1.0:
			var dir := _dir(side)
			var mid := c + dir * core.size.x * 0.5
			var across := Vector2(dir.y, dir.x) * s * 0.06
			if g <= 0.0:
				draw_line(mid - across - dir * 3.0, mid + across + dir * 3.0, UIKit.DANGER, 2.0, true)
				draw_line(mid + across - dir * 3.0, mid - across + dir * 3.0, UIKit.DANGER, 2.0, true)
			else:
				draw_line(mid - across, mid + across, health_color(g), 4.0, true)
	# The spawn: a ring, a dot on it toward the player's side.
	var ring := core.size.x * 0.32
	draw_arc(c, ring, 0.0, TAU, 32, Color(UIKit.ACCENT, 0.6), 1.5, true)
	draw_circle(c + _dir(spawn_side) * ring, 5.0, UIKit.ACCENT)
	draw_arc(c + _dir(spawn_side) * ring, 7.0, 0.0, TAU, 16, Color(1, 1, 1, 0.8), 1.0, true)
	# BASE or FIELD.
	var field := priority == 1
	draw_circle(c, core.size.x * 0.17, UIKit.WARN if field else UIKit.ACCENT)
	draw_string(font, c + Vector2(-8, 4), "F" if field else "B", HORIZONTAL_ALIGNMENT_CENTER, 16, FONT, Color(0.05, 0.05, 0.08))
	# The keys.
	draw_string(font, Vector2(0, size.y - 3.0), "Y spawn · U base/field", HORIZONTAL_ALIGNMENT_CENTER, size.x, FONT,
			Color(0.75, 0.8, 0.9))


func _get_tooltip(at_position: Vector2) -> String:
	var q := _square()
	var c := q.get_center()
	if at_position.distance_to(c) < q.size.x * (1.0 - 2.0 * CORE) * 0.25:
		return "Your soldiers: %s (U to switch)\n%s" % ["FIELD: straight out to the field" if priority == 1
				else "BASE: the guns, then the decks, then the field", summary_text]
	for side in ["north", "east", "south", "west"]:
		if _side_rect(q, side).grow(4.0).has_point(at_position):
			var d: Dictionary = sides.get(side, {})
			var lines := PackedStringArray(["%s side" % side.capitalize()])
			if d.get("total", 0) > 0:
				lines.append("Guns %d/%d standing, %d%% health · %d crewed" % [d.alive, d.total, roundi(d.guns * 100.0), d.crewed])
			var g: float = d.get("gate", -1.0)
			if g > -1.0:
				lines.append("Gate: %s" % ("BROKEN" if g <= 0.0 else "%d%%" % roundi(g * 100.0)))
			if d.get("near", 0) > 0:
				lines.append("%d attackers close" % d.near)
			lines.append("Spawning %d a round here%s" % [spawn_counts.get(side, 0), " (your spawn)" if side == spawn_side else ""])
			lines.append("Click: move your spawn here (Y cycles)")
			return "\n".join(lines)
	return ""


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var q := _square()
	if mb.position.distance_to(q.get_center()) < q.size.x * (1.0 - 2.0 * CORE) * 0.25:
		centre_pressed.emit()
		accept_event()
		return
	for side in ["north", "east", "south", "west"]:
		if _side_rect(q, side).grow(4.0).has_point(mb.position):
			side_pressed.emit(side)
			accept_event()
			return
