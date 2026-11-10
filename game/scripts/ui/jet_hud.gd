class_name JetHud
extends Control
## The Fighter Jet's sights and panel while the player flies it (DefenderJet), over the chase camera:
##   - the nose cross: where the nose points (where the missiles go, flying straight);
##   - the aim ring: where the mouse is steering it (the jet banks and turns onto it);
##   - the bomb mark: where a bomb let go this instant would land (the same forecast as the ground preview), with the
##     distance, kept on the screen's edge with an arrow when it is off it;
##   - a block on the left: speed, height, the boost, the bombs in the bay, the missile salvo;
##   - a line mid-screen for a warning (PULL UP, TURN BACK) or what has just happened (CRASHED, SHOT DOWN).

const BLOCK := Vector2(250, 150)
const BLOCK_MARGIN := Vector2(16, 16)
const EMPTY := Color(0.2, 0.22, 0.26, 0.9)
const DIM := Color(0.7, 0.75, 0.85)
const NOSE := Color(0.55, 1.0, 0.7)
const AIM := Color(0.6, 0.85, 1.0)
const BOMB := Color(1.0, 0.6, 0.2)
const FAR := 900.0

var jet: DefenderJet


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible and jet != null:
		queue_redraw()


func _draw() -> void:
	if jet == null:
		return
	var cam := jet.get_camera()
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	if cam != null and jet.is_alive():
		_sights(cam, font, view)
	_panel(font, view)
	var text := jet.warning if jet.warning != "" else jet.notice()
	if text != "":
		var col := UIKit.DANGER if (jet.warning != "" or not jet.is_alive()) else UIKit.WARN
		if jet.warning == "TURN BACK":
			text = "TURN BACK  %d" % ceili(jet.out_left)
		var size := 30 if jet.warning != "" or not jet.is_alive() else 20
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
		var blink := 1.0 if jet.warning == "" else (0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.016))
		var at := Vector2((view.x - w) * 0.5, view.y * 0.3)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.85))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.r, col.g, col.b, blink))


## The nose cross, the aim ring and the bomb mark.
func _sights(cam: Camera3D, font: Font, view: Vector2) -> void:
	var here := jet.global_position
	var nose_at := here + jet.forward() * FAR
	if not cam.is_position_behind(nose_at):
		_cross(cam.unproject_position(nose_at), NOSE)
	var aim_at := here + jet.aim_dir() * FAR
	if not cam.is_position_behind(aim_at):
		draw_arc(cam.unproject_position(aim_at), 26.0, 0.0, TAU, 40, AIM, 1.6, true)
	var f := jet.bomb_forecast
	if f.is_empty():
		return
	var impact: Vector3 = f.impact
	var col := BOMB if jet.bombs > 0 else Color(0.6, 0.6, 0.6, 0.8)
	var dist := here.distance_to(impact)
	var label := "%d m" % int(dist) if jet.bombs > 0 else "NO BOMBS"
	var margin := 40.0
	if cam.is_position_behind(impact):
		return
	var p := cam.unproject_position(impact)
	var inside := Rect2(Vector2(margin, margin), view - Vector2(margin, margin) * 2.0).has_point(p)
	if inside:
		_diamond(p, 14.0, col)
		_text(font, p + Vector2(22, 6), label, 16, col)
	else:
		var c := view * 0.5
		var edge := Vector2(clampf(p.x, margin, view.x - margin), clampf(p.y, margin, view.y - margin))
		var away := (p - c).normalized()
		_diamond(edge, 11.0, col)
		draw_line(edge + away * 16.0, edge + away * 30.0, col, 3.0, true)
		_text(font, edge + Vector2(-30, -18), label, 14, col)


func _cross(at: Vector2, col: Color) -> void:
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(at + d * 5.0, at + d * 13.0, Color(0, 0, 0, 0.6), 4.0, true)
		draw_line(at + d * 5.0, at + d * 13.0, col, 2.0, true)
	draw_circle(at, 1.6, col)


## Text with a dark outline, so it reads over the land.
func _text(font: Font, at: Vector2, text: String, size: int, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _diamond(at: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0), at + Vector2(0, -r)])
	draw_polyline(pts, Color(0, 0, 0, 0.7), 5.0, true)
	draw_polyline(pts, col, 2.5, true)
	draw_circle(at, 2.4, col)


## Speed, height, boost, bombs, missiles.
func _panel(font: Font, view: Vector2) -> void:
	var origin := Vector2(BLOCK_MARGIN.x, view.y - BLOCK_MARGIN.y - BLOCK.y)
	draw_style_box(UIKit.panel_style(), Rect2(origin, BLOCK))
	draw_string(font, origin + Vector2(12, 24), "SPEED  %d m/s" % int(jet.speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, origin + Vector2(12, 46), "HEIGHT %d m" % int(maxf(jet.altitude(), 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			UIKit.DANGER if jet.warning == "PULL UP" else Color.WHITE)
	# The boost.
	var boost_col := UIKit.DANGER if jet.boost <= 0.0 else (UIKit.WARN if jet.boosting else UIKit.ACCENT)
	draw_string(font, origin + Vector2(12, 72), "BOOST [Shift]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, boost_col if jet.boosting else DIM)
	_bar(origin + Vector2(124, 63), jet.boost, boost_col, 114.0)
	# The bombs in the bay: a pip each.
	draw_string(font, origin + Vector2(12, 98), "BOMBS [LMB]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	for k in DefenderJet.BOMBS:
		var r := Rect2(origin + Vector2(124 + k * 29, 88), Vector2(25, 11))
		draw_rect(r, EMPTY)
		if k < jet.bombs:
			draw_rect(r, BOMB)
	# The missile salvo: the missiles left in it, or the reload.
	var ready := jet.salvo_left == 0 and jet.salvo_cd <= 0.0
	draw_string(font, origin + Vector2(12, 124), "MISSILES [RMB]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD if ready else DIM)
	if jet.salvo_left > 0:
		_bar(origin + Vector2(124, 115), float(jet.salvo_left) / DefenderJet.SALVO, UIKit.WARN, 114.0)
	elif jet.salvo_cd > 0.0:
		_bar(origin + Vector2(124, 115), 1.0 - jet.salvo_cd / DefenderJet.SALVO_RELOAD, DIM, 114.0)
	else:
		_bar(origin + Vector2(124, 115), 1.0, UIKit.GOOD, 114.0)


func _bar(at: Vector2, f: float, color: Color, width := 100.0) -> void:
	draw_rect(Rect2(at, Vector2(width, 10)), EMPTY)
	draw_rect(Rect2(at, Vector2(width * clampf(f, 0.0, 1.0), 10)), color)
