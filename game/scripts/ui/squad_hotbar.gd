class_name SquadHotbar
extends Control
## The defender's roster of bought squads and machines (DefenderArmory), bottom centre: a slot per squad with
## its key (F1-F6 takes command of it, Ctrl+F<n> changes its auto order), its troopers' health, its
## auto order and what it is doing, the one the player drives outlined; then the buy slots (B: an
## AA Squad, N: a Flame Squad, M: an Infiltrator Squad, K: a Sniper, J: the Fighter Jet, H: the Hover Tank)
## with the credits. With a lot of slots they narrow to fit the screen.

const SLOT := Vector2(112, 58)
const GAP := 4.0
const BOTTOM := 40.0
const DIM := Color(0.6, 0.64, 0.7)
## The buy slots: [key, label, kind (DefenderArmory.COSTS)].
const BUYS := [["B", "BUY AA", "aa"], ["N", "BUY FLAME", "flame"], ["M", "BUY INFIL", "infiltrator"], ["K", "BUY SNIPER", "sniper"],
		["J", "BUY JET", "jet"], ["H", "BUY TANK", "tank"]]
## The narrowest a slot gets, and the room left at the screen's sides.
const SLOT_MIN := 84.0
const SIDE := 16.0

var armory: DefenderArmory
## The station the player drives (to outline its slot).
var current = null
var keys: Array = []

var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_clock += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	if armory == null:
		return
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var n := armory.squads.size() + BUYS.size()
	var slot := Vector2(clampf((view.x - SIDE * 2.0 - (n - 1) * GAP) / n, SLOT_MIN, SLOT.x), SLOT.y)
	var width := n * slot.x + (n - 1) * GAP
	var origin := Vector2((view.x - width) * 0.5, view.y - BOTTOM - SLOT.y)
	for i in armory.squads.size():
		_draw_squad(Rect2(origin + Vector2(i * (slot.x + GAP), 0), slot), i, armory.squads[i], font)
	for k in BUYS.size():
		_draw_buy(Rect2(origin + Vector2((armory.squads.size() + k) * (slot.x + GAP), 0), slot), BUYS[k], font)


func _draw_squad(r: Rect2, i: int, s, font: Font) -> void:
	var driving: bool = s == current
	draw_style_box(UIKit.panel_style(Color(0.1, 0.16, 0.24, 0.88) if driving else UIKit.PANEL_BG), r)
	if driving:
		draw_rect(r.grow(1.0), UIKit.ACCENT, false, 2.0)
	elif s.alert():
		draw_rect(r.grow(1.0), Color(1.0, 0.3, 0.22, 0.6 + 0.4 * sin(_clock * 11.0)), false, 2.0)
	var key: String = keys[i] if i < keys.size() else ""
	draw_string(font, r.position + Vector2(7, 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ACCENT)
	draw_string(font, r.position + Vector2(30, 16), s.roster_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	# Health: a pip a trooper, the leader first (a squad of one, or a machine, gets one wide bar).
	var health: Array = s.pips()
	var w: float = DefenderSquad.SIZE * 18.0 / s.squad_size
	for k in s.squad_size:
		var pip := Rect2(r.position + Vector2(7 + k * w, 23), Vector2(w - 3.0, 7))
		draw_rect(pip, Color(0, 0, 0, 0.55))
		if k < health.size():
			var f: float = health[k]
			var c := UIKit.GOOD if f > 0.6 else (UIKit.WARN if f > 0.3 else UIKit.DANGER)
			draw_rect(Rect2(pip.position, Vector2(pip.size.x * f, pip.size.y)), c)
	draw_string(font, r.position + Vector2(7, 44), s.order_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, s.order_color())
	# What it is doing, after the order's name (a longer name, like BOMB RUN, pushes it along).
	var after := maxf(52.0, 7.0 + font.get_string_size(s.order_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6.0)
	draw_string(font, r.position + Vector2(after, 44), s.doing(driving), HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x - after - 4.0), 10, DIM)


## A buy slot: [key, label, kind].
func _draw_buy(r: Rect2, buy: Array, font: Font) -> void:
	var ok := armory.can_buy(buy[2])
	draw_style_box(UIKit.panel_style(Color(0.08, 0.14, 0.1, 0.85) if ok else UIKit.PANEL_BG), r)
	draw_string(font, r.position + Vector2(7, 16), buy[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ACCENT)
	draw_string(font, r.position + Vector2(22, 16), buy[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD if ok else DIM)
	var full := armory.squads.size() >= DefenderArmory.MAX_SQUADS
	var cost := "ROSTER FULL" if full else "%d cr" % DefenderArmory.COSTS[buy[2]]
	draw_string(font, r.position + Vector2(7, 32), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	draw_string(font, r.position + Vector2(7, 49), "%d CREDITS" % int(armory.credits), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.WARN)
