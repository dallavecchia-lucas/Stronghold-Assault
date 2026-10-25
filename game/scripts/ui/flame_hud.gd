class_name FlameHud
extends Control
## The Flame Squad's panel while the player drives it (FlameSquad), above the weapon panel: each
## trooper's pressure, how close the tree under the leader's flame is to catching (it has to be
## held on it for ForestTree.IGNITE_TIME), and the squad's auto order.

const BLOCK := Vector2(250, 96)
const BLOCK_MARGIN := Vector2(16, 150)
const EMPTY := Color(0.2, 0.22, 0.26, 0.9)
const VENT := Color(0.7, 0.72, 0.76)

var squad: FlameSquad


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if squad == null or squad.leader == null:
		return
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var origin := view - BLOCK_MARGIN - BLOCK
	draw_style_box(UIKit.panel_style(), Rect2(origin, BLOCK))
	draw_string(font, origin + Vector2(12, 20), "PRESSURE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85))
	var order: Array = [squad.leader]
	for t in squad.troopers:
		if t != squad.leader:
			order.append(t)
	for k in DefenderSquad.SIZE:
		var r := Rect2(origin + Vector2(92 + k * 30, 10), Vector2(26, 9))
		draw_rect(r, EMPTY)
		if k < order.size():
			var ft: FlameTrooper = order[k]
			draw_rect(Rect2(r.position, Vector2(r.size.x * ft.pressure, r.size.y)), VENT if ft.venting() else FlameSquad.FLAME_COLOR)
	var lead := squad.leader as FlameTrooper
	var tree := lead.flame_tree
	var text := "FLAME 6 m · HOLD IT ON A TRUNK"
	var col := Color(0.75, 0.78, 0.82)
	if tree != null and is_instance_valid(tree) and tree.is_standing():
		var f := tree.heat_fraction()
		text = "TREE CATCHING  %d%%" % int(f * 100.0)
		col = FlameSquad.FLAME_COLOR
		var bar := Rect2(origin + Vector2(12, 50), Vector2(BLOCK.x - 24, 6))
		draw_rect(bar, EMPTY)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
	draw_string(font, origin + Vector2(12, 42), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	draw_string(font, origin + Vector2(12, 82), "AUTO ORDER  %s  [V]" % FlameSquad.ORDER_NAMES[squad.order], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.ACCENT)
