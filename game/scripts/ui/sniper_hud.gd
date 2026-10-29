class_name SniperHud
extends Control
## The Sniper's panel while the player drives her (Sniper), above the weapon panel: her tags (a slot for
## each of the five she can keep out, each running down its 20 s), the thermal sight (on, recharging or
## ready) and the scope's zoom; and a line low under the crosshair now and then (a tag, the thermal
## sight), clear of what the scope is on.

const BLOCK := Vector2(270, 112)
const BLOCK_MARGIN := Vector2(16, 150)
const EMPTY := Color(0.2, 0.22, 0.26, 0.9)
const DIM := Color(0.7, 0.75, 0.85)
const THERMAL := Color(1.0, 0.6, 0.15)

var sniper: Sniper


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible and sniper != null:
		queue_redraw()


func _draw() -> void:
	if sniper == null or sniper.leader == null:
		return
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var origin := view - BLOCK_MARGIN - BLOCK
	draw_style_box(UIKit.panel_style(), Rect2(origin, BLOCK))
	# Tags: one slot each, filled with what is left of its time.
	var tags: Array = sniper.tagged()
	var full := tags.size() >= Sniper.TAG_LIMIT
	draw_string(font, origin + Vector2(12, 21), "TAGS %d/%d" % [tags.size(), Sniper.TAG_LIMIT], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Sniper.SCOPE_COLOR if full else DIM)
	tags.sort_custom(func(a, b): return a.tag_left(sniper) > b.tag_left(sniper))
	for k in Sniper.TAG_LIMIT:
		var r := Rect2(origin + Vector2(92 + k * 34, 11), Vector2(30, 10))
		draw_rect(r, EMPTY)
		if k < tags.size():
			var f: float = tags[k].tag_left(sniper) / Sniper.TAG_TIME
			draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Sniper.SCOPE_COLOR)
	# The thermal sight.
	var text := "THERMAL READY  [T]"
	var col := THERMAL
	if sniper.thermal_left > 0.0:
		text = "THERMAL ON  %ds" % ceili(sniper.thermal_left)
		_bar(origin + Vector2(150, 37), sniper.thermal_left / Sniper.THERMAL_TIME, col)
	elif sniper.thermal_cd > 0.0:
		text = "THERMAL  %ds" % ceili(sniper.thermal_cd)
		col = DIM
		_bar(origin + Vector2(150, 37), 1.0 - sniper.thermal_cd / Sniper.THERMAL_RECHARGE, DIM)
	draw_string(font, origin + Vector2(12, 46), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	var scope := "SCOPE %dx  [RMB · wheel]" % int(Sniper.ZOOMS[sniper.zoom])
	draw_string(font, origin + Vector2(12, 72), scope, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.ACCENT if sniper.scope_view() else DIM)
	draw_string(font, origin + Vector2(12, 98), "LEFT ALONE: HOLDS HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	var n := sniper.notice()
	if n != "":
		var w := font.get_string_size(n, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
		draw_string(font, Vector2((view.x - w) * 0.5, view.y * (0.5 + SniperScope.LENS * 0.6)), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.WARN)


func _bar(at: Vector2, f: float, color: Color, width := 100.0) -> void:
	draw_rect(Rect2(at, Vector2(width, 6)), EMPTY)
	draw_rect(Rect2(at, Vector2(width * clampf(f, 0.0, 1.0), 6)), color)
