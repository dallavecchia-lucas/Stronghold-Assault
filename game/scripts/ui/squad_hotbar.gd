class_name SquadHotbar
extends Control
## The defender's roster of bought squads (DefenderArmory), bottom centre: a slot per squad with
## its key (F1-F6 takes command of it, Ctrl+F<n> changes its auto order), its troopers' health, its
## auto order and what it is doing, the one the player drives outlined; then the buy slot (B) with
## the credits.

const SLOT := Vector2(104, 58)
const GAP := 4.0
const BOTTOM := 40.0
const DIM := Color(0.6, 0.64, 0.7)

var armory: DefenderArmory
## The station the player drives (to outline its slot).
var current = null
var keys: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if armory == null:
		return
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var n := armory.squads.size() + 1
	var width := n * SLOT.x + (n - 1) * GAP
	var origin := Vector2((view.x - width) * 0.5, view.y - BOTTOM - SLOT.y)
	for i in armory.squads.size():
		_draw_squad(Rect2(origin + Vector2(i * (SLOT.x + GAP), 0), SLOT), i, armory.squads[i], font)
	_draw_buy(Rect2(origin + Vector2(armory.squads.size() * (SLOT.x + GAP), 0), SLOT), font)


func _draw_squad(r: Rect2, i: int, s: AASquad, font: Font) -> void:
	var driving: bool = s == current
	draw_style_box(UIKit.panel_style(Color(0.1, 0.16, 0.24, 0.88) if driving else UIKit.PANEL_BG), r)
	if driving:
		draw_rect(r.grow(1.0), UIKit.ACCENT, false, 2.0)
	elif s.locked:
		draw_rect(r.grow(1.0), Color(1.0, 0.3, 0.22, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 90.0)), false, 2.0)
	var key: String = keys[i] if i < keys.size() else ""
	draw_string(font, r.position + Vector2(7, 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ACCENT)
	draw_string(font, r.position + Vector2(30, 16), "AA %d" % s.number, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	# Troopers' health, the leader first.
	var order: Array = [s.leader] if s.leader else []
	for t in s.troopers:
		if t != s.leader:
			order.append(t)
	for k in DefenderSquad.SIZE:
		var pip := Rect2(r.position + Vector2(7 + k * 18, 23), Vector2(15, 7))
		draw_rect(pip, Color(0, 0, 0, 0.55))
		if k < order.size():
			var f := clampf(order[k].hp / order[k].max_hp, 0.0, 1.0)
			var c := UIKit.GOOD if f > 0.6 else (UIKit.WARN if f > 0.3 else UIKit.DANGER)
			draw_rect(Rect2(pip.position, Vector2(pip.size.x * f, pip.size.y)), c)
	var order_col := AASquad.MINE_LINE if s.order == AASquad.Order.MINES else UIKit.WARN
	draw_string(font, r.position + Vector2(7, 44), AASquad.ORDER_NAMES[s.order], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, order_col)
	draw_string(font, r.position + Vector2(52, 44), _doing(s, driving), HORIZONTAL_ALIGNMENT_LEFT, int(SLOT.x - 56), 10, DIM)


func _draw_buy(r: Rect2, font: Font) -> void:
	var ok := armory.can_buy()
	draw_style_box(UIKit.panel_style(Color(0.08, 0.14, 0.1, 0.85) if ok else UIKit.PANEL_BG), r)
	draw_string(font, r.position + Vector2(7, 16), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ACCENT)
	draw_string(font, r.position + Vector2(22, 16), "BUY AA", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD if ok else DIM)
	var full := armory.squads.size() >= DefenderArmory.MAX_SQUADS
	var cost := "ROSTER FULL" if full else "%d cr" % DefenderArmory.AA_COST
	draw_string(font, r.position + Vector2(7, 32), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	draw_string(font, r.position + Vector2(7, 49), "%d CREDITS" % int(armory.credits), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.WARN)


## A word on what the squad is up to.
static func _doing(s: AASquad, driving: bool) -> String:
	if s.locked:
		return "LOCKED"
	if s.lock_target != null:
		return "LOCKING"
	if driving:
		return "YOU"
	if s.order == AASquad.Order.GUARD:
		return "HOLDING"
	return {"here": "LAYING", "return": "TO BASE", "perimeter": "PERIMETER"}.get(s.plan, "")
