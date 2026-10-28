class_name InfiltratorHud
extends Control
## The Infiltrator Squad's panel while the player drives it (InfiltratorSquad), above the weapon
## panel: each trooper's draw, the adaptive camo, the sabotage kit (and the work under way) and the
## squad's auto order; and, while the camo is on, a vignette round the squad's camera (the troopers
## themselves look as ever on the defender's side).

const BLOCK := Vector2(270, 112)
const BLOCK_MARGIN := Vector2(16, 150)
const EMPTY := Color(0.2, 0.22, 0.26, 0.9)
const DIM := Color(0.7, 0.75, 0.85)
## The vignette: how far in from the edges it reaches (share of the screen) and its tint.
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 1.0;
uniform vec4 tint : source_color = vec4(0.02, 0.1, 0.09, 1.0);
void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.25, 1.0);
	float v = smoothstep(0.32, 0.78, length(d));
	COLOR = vec4(tint.rgb, v * 0.88 * strength);
}
"""

var squad: InfiltratorSquad

var _vignette: ColorRect
var _fade := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_vignette.material = mat
	_vignette.visible = false
	_vignette.show_behind_parent = true  # under the panel drawn here
	add_child(_vignette)


func _process(delta: float) -> void:
	if not visible or squad == null:
		return
	# The vignette eases in as the camo goes on and out as it wears off.
	_fade = move_toward(_fade, 1.0 if squad.camo_left > 0.0 else 0.0, delta * 3.0)
	_vignette.visible = _fade > 0.0
	if _vignette.visible:
		var pulse := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.003)
		(_vignette.material as ShaderMaterial).set_shader_parameter("strength", _fade * pulse)
	queue_redraw()


## How strong the camo vignette is right now (0: none).
func vignette() -> float:
	return _fade if _vignette.visible else 0.0


func _draw() -> void:
	if squad == null or squad.leader == null:
		return
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var origin := view - BLOCK_MARGIN - BLOCK
	draw_style_box(UIKit.panel_style(), Rect2(origin, BLOCK))
	# The draw of each trooper's bow, the leader first.
	draw_string(font, origin + Vector2(12, 20), "BOWS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	var order: Array = [squad.leader]
	for t in squad.troopers:
		if t != squad.leader:
			order.append(t)
	for k in DefenderSquad.SIZE:
		var r := Rect2(origin + Vector2(92 + k * 34, 10), Vector2(30, 9))
		draw_rect(r, EMPTY)
		if k < order.size():
			var it: InfiltratorTrooper = order[k]
			draw_rect(Rect2(r.position, Vector2(r.size.x * it.draw, r.size.y)), InfiltratorSquad.CAMO_COLOR if it.draw >= 1.0 else DIM)
	# Adaptive camo.
	var camo := "CAMO READY  [Q]"
	var camo_col := InfiltratorSquad.CAMO_COLOR
	if squad.camo_left > 0.0:
		camo = "CAMO ON  %ds" % ceili(squad.camo_left)
		_bar(origin + Vector2(150, 33), squad.camo_left / InfiltratorSquad.CAMO_TIME, camo_col)
	elif squad.camo_cd > 0.0:
		camo = "CAMO  %ds" % ceili(squad.camo_cd)
		camo_col = DIM
	draw_string(font, origin + Vector2(12, 42), camo, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, camo_col)
	# Sabotage.
	var text := "SABOTAGE KIT READY"
	var col := DIM
	if squad.sabotaging != null:
		text = "SABOTAGING %s  %d%%" % [squad.sabotaging.short_name.to_upper(), int(squad.sabotaging.sabotage_fraction() * 100.0)]
		col = UIKit.WARN
		_bar(origin + Vector2(12, 70), squad.sabotaging.sabotage_fraction(), col, BLOCK.x - 24)
	elif squad.kits <= 0:
		text = "KIT USED · RESTOCK IN THE FORTRESS"
		col = UIKit.DANGER
	else:
		var near: Array = squad.nearest_base()
		if near[0] != null and near[1] <= AttackerBase.SABOTAGE_REACH:
			text = "%s IN REACH · F SABOTAGE" % near[0].short_name.to_upper()
			col = UIKit.GOOD
		elif near[0] != null:
			text = "SABOTAGE KIT · %s %dm" % [near[0].short_name.to_upper(), int(near[1])]
	draw_string(font, origin + Vector2(12, 64), text, HORIZONTAL_ALIGNMENT_LEFT, BLOCK.x - 24, 14, col)
	draw_string(font, origin + Vector2(12, 98), "AUTO ORDER  %s  [V]" % squad.order_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.ACCENT)
	var n := squad.notice()
	if n != "":
		var w := font.get_string_size(n, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
		draw_string(font, Vector2((view.x - w) * 0.5, view.y * 0.5 + 64), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.WARN)


func _bar(at: Vector2, f: float, color: Color, width := 100.0) -> void:
	draw_rect(Rect2(at, Vector2(width, 6)), EMPTY)
	draw_rect(Rect2(at, Vector2(width * clampf(f, 0.0, 1.0), 6)), color)
