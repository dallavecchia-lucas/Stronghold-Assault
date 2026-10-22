class_name AAHud
extends Control
## The AA Squad's sights while the player drives it (AASquad): a mark on every enemy aircraft in
## lock range, the lock-on box closing in on the one being tracked (LOCKED once the crosshair has
## stayed on it for AASquad.LOCK_TIME), the squad's pods (a pip per missile), its mines and its auto
## order (above the weapon panel), and a line under the crosshair when the squad can't fire.

const LOCKING := Color(1.0, 0.8, 0.25)
const LOCKED := Color(1.0, 0.3, 0.22)
const MARK := Color(1.0, 1.0, 1.0, 0.6)
const PIP := Color(0.85, 0.9, 1.0)
const EMPTY := Color(0.2, 0.22, 0.26, 0.9)
## Status block, above the weapon panel (bottom right).
const BLOCK := Vector2(250, 118)
const BLOCK_MARGIN := Vector2(16, 150)

var squad: AASquad


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if squad == null or squad.leader == null:
		return
	var cam := squad.get_camera()
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var centre := view * 0.5
	var eye := cam.global_position
	for a in get_tree().get_nodes_in_group("air_units"):
		if a.team == squad.team or not a.is_alive() or a == squad.lock_target:
			continue
		var at := Combat.aim_point(a)
		if cam.is_position_behind(at) or Vector2(at.x - eye.x, at.z - eye.z).length() > AASquad.LOCK_RANGE:
			continue
		var p := cam.unproject_position(at)
		_diamond(p, 8.0, MARK, 1.5)
	var t := squad.lock_target
	if Combat.is_valid_target(t) and not cam.is_position_behind(Combat.aim_point(t)):
		var p := cam.unproject_position(Combat.aim_point(t))
		var f := squad.lock_fraction()
		var col := LOCKED if squad.locked else LOCKING
		var half := lerpf(48.0, 18.0, f)
		if squad.locked:
			half += 3.0 * sin(Time.get_ticks_msec() / 70.0)  # locked: the box throbs
		_brackets(p, half, col)
		draw_arc(p, half + 9.0, -PI * 0.5, -PI * 0.5 + TAU * f, 40, col, 3.0, true)
		var text := "LOCKED · LMB FIRE" if squad.locked else "LOCKING %.1fs" % (AASquad.LOCK_TIME - squad.lock_progress)
		draw_string_outline(font, p + Vector2(-110, half + 30), text, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, p + Vector2(-110, half + 30), text, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, col)
		if squad.locked:
			draw_dashed_line(centre, p, Color(col, 0.5), 1.5, 6.0)
	var note := squad.notice()
	if squad.mine_aiming:
		note = "MINES · LMB throw · RMB or F cancel"
	if note != "":
		var at := centre + Vector2(-240, 64)
		draw_string_outline(font, at, note, HORIZONTAL_ALIGNMENT_CENTER, 480, 16, 5, Color(0, 0, 0, 0.85))
		draw_string(font, at, note, HORIZONTAL_ALIGNMENT_CENTER, 480, 16, UIKit.WARN if not squad.mine_aiming else AASquad.MINE_LINE)
	_draw_block(view, font)


## Pods, mines and the auto order, in a panel above the weapon panel.
func _draw_block(view: Vector2, font: Font) -> void:
	var origin := view - BLOCK_MARGIN - BLOCK
	draw_style_box(UIKit.panel_style(), Rect2(origin, BLOCK))
	draw_string(font, origin + Vector2(12, 20), "PODS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85))
	var order: Array = [squad.leader]
	for tr in squad.troopers:
		if tr != squad.leader:
			order.append(tr)
	for k in DefenderSquad.SIZE:
		for j in MissileTrooper.TUBES:
			var r := Rect2(origin + Vector2(64 + j * 11, 9 + k * 10), Vector2(8, 7))
			var full := k < order.size() and j < (order[k] as MissileTrooper).loaded()
			draw_rect(r, PIP if full else EMPTY)
	var mines := "MINES READY  [F]" if squad.mine_cd <= 0.0 else "MINES  %ds" % ceili(squad.mine_cd)
	draw_string(font, origin + Vector2(12, 82), mines, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			AASquad.MINE_LINE if squad.mine_cd <= 0.0 else Color(0.75, 0.78, 0.82))
	draw_string(font, origin + Vector2(150, 82), "%d down" % squad.mines.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85))
	draw_string(font, origin + Vector2(12, 104), "AUTO ORDER  %s  [V]" % AASquad.ORDER_NAMES[squad.order], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.ACCENT)


func _diamond(p: Vector2, r: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
	draw_polyline(pts, col, w, true)


## Corner brackets of a box `half` out from `p`.
func _brackets(p: Vector2, half: float, col: Color) -> void:
	var l := half * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := p + Vector2(sx, sy) * half
			draw_line(c, c - Vector2(sx * l, 0), col, 2.5)
			draw_line(c, c - Vector2(0, sy * l), col, 2.5)
