class_name SquadHud
extends Control
## Squad panel (Gunner Squad, AA Squads), bottom left while the player drives the squad: its
## formation, each trooper's health, and a small map turned with the camera (up is where the
## player looks) showing the troopers, the spot each follower is making for, and attackers close by.

const SIZE := Vector2(250, 300)
const MAP := 120.0  # map radius (px)
const MAP_RANGE := 16.0  # meters to the map's edge
const LEADER := Color(0.35, 0.7, 1.0)
const FOLLOWER := Color(0.85, 0.9, 1.0)
const ENEMY := Color(1.0, 0.35, 0.28)

var squad: DefenderSquad

var _flash := ""
var _flash_t := 0.0


## A line across the top of the panel for a few seconds (the lead changing hands).
func flash(text: String) -> void:
	_flash = text
	_flash_t = 3.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 16.0
	offset_right = 16.0 + SIZE.x
	offset_top = -16.0 - SIZE.y
	offset_bottom = -16.0


func _process(delta: float) -> void:
	_flash_t = maxf(_flash_t - delta, 0.0)
	if visible:
		queue_redraw()


func _draw() -> void:
	if squad == null:
		return
	draw_style_box(UIKit.panel_style(), Rect2(Vector2.ZERO, SIZE))
	var font := get_theme_default_font()
	var mode: String = SquadFormation.MODE_NAMES[squad.formation.mode]
	draw_string(font, Vector2(12, 24), squad.hud_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.85))
	draw_string(font, Vector2(12, 46), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.ACCENT)
	if _flash_t > 0.0:
		var a := clampf(_flash_t / 0.5, 0.0, 1.0) * (0.6 + 0.4 * absf(sin(_flash_t * 6.0)))
		draw_rect(Rect2(Vector2(0, -30), Vector2(SIZE.x, 24)), Color(0.45, 0.05, 0.03, 0.85 * a))
		draw_string(font, Vector2(10, -13), _flash, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 20, 12, Color(1, 0.92, 0.85, a))
	# Health pips, the leader first.
	var order: Array = [squad.leader] if squad.leader else []
	for t in squad.troopers:
		if t != squad.leader:
			order.append(t)
	for k in DefenderSquad.SIZE:
		var r := Rect2(Vector2(126 + k * 23, 30), Vector2(18, 16))
		draw_rect(r, Color(0, 0, 0, 0.55))
		if k < order.size():
			var t: SquadTrooper = order[k]
			var f := clampf(t.hp / t.max_hp, 0.0, 1.0)
			var c := UIKit.GOOD if f > 0.6 else (UIKit.WARN if f > 0.3 else UIKit.DANGER)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * (1.0 - f)), Vector2(r.size.x, r.size.y * f)), c)
			if t == squad.leader:
				draw_rect(r.grow(2.0), LEADER, false, 2.0)
	# Map, centered on the leader and turned so the camera looks up the page.
	var centre := Vector2(SIZE.x * 0.5, 64 + MAP + 4)
	draw_circle(centre, MAP, Color(0.1, 0.14, 0.18, 0.8))
	draw_arc(centre, MAP, 0, TAU, 48, Color(0.35, 0.45, 0.55, 0.8), 1.5)
	draw_arc(centre, MAP * 0.5, 0, TAU, 32, Color(0.35, 0.45, 0.55, 0.35), 1.0)
	if squad.leader == null:
		return
	var origin := squad.leader.global_position
	var yaw := squad.cam_yaw
	var to_map := func(p: Vector3) -> Vector2:
		var d := Vector2(p.x - origin.x, p.z - origin.z).rotated(yaw)
		return centre + d * (MAP / MAP_RANGE)
	# The way the squad faces.
	var fwd := Basis(Vector3.UP, squad.heading) * Vector3(0, 0, -4.0)
	draw_line(centre, to_map.call(origin + fwd), Color(0.35, 0.7, 1.0, 0.5), 2.0)
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var p: Vector2 = to_map.call(u.global_position)
		if p.distance_to(centre) < MAP - 4:
			draw_circle(p, 4.0, ENEMY)
	for t in squad.goals:
		if not is_instance_valid(t):
			continue
		var g: Vector2 = to_map.call(squad.goals[t])
		var at: Vector2 = to_map.call(t.global_position)
		if g.distance_to(centre) < MAP and at.distance_to(centre) < MAP:
			draw_line(at, g, Color(1, 1, 1, 0.25), 1.0)
			draw_arc(g, 5.0, 0, TAU, 12, Color(1, 1, 1, 0.6), 1.5)
	for t in squad.troopers:
		var p: Vector2 = to_map.call(t.global_position)
		if p.distance_to(centre) > MAP:
			continue
		var look := Vector2(-sin(t.rotation.y), -cos(t.rotation.y)).rotated(yaw)
		var col := LEADER if t == squad.leader else FOLLOWER
		draw_circle(p, 6.0 if t == squad.leader else 5.0, col)
		draw_line(p, p + look * 10.0, col, 2.0)
