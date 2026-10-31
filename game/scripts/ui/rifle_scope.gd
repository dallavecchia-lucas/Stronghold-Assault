class_name RifleScope
extends CanvasLayer
## The Shadowline rifle's smart scope (DefenderSoldier, RMB): no looking down the sight, the scope sends
## its picture to the visor. A slight zoom (the soldier's camera), then over the whole screen: a faint
## cyan tint with fine horizontal scan lines, a cyan reticle (a ring, four posts with a gap round the
## middle), blue corner brackets, a red delta turning in the top-left one, a red signal-bar meter in the
## bottom-left one and a red range bar in the right one, a tick running up and down it.
## `amount` (0..1) fades it all in and out.

const CYAN := Color(0.45, 0.85, 0.95)
const BLUE := Color(0.25, 0.32, 0.92)
const RED := Color(0.93, 0.38, 0.33)
const FILTER_SHADER := """
shader_type canvas_item;
uniform float strength = 1.0;
void fragment() {
	// A faint cyan wash, and every third pixel row a touch darker: the scan lines.
	float line = step(mod(FRAGCOORD.y, 3.0), 1.0);
	vec4 tint = vec4(0.35, 0.9, 1.0, 0.07);
	vec4 scan = vec4(0.0, 0.08, 0.1, 0.12);
	COLOR = mix(tint, scan, line);
	COLOR.a *= strength;
}
"""

## How far in the scope's view is (0 = off, 1 = full).
var amount := 0.0

var _filter: ColorRect
var _lines: Control
var _t := 0.0


func _init() -> void:
	layer = 4  # under the match's panels
	_filter = ColorRect.new()
	_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FILTER_SHADER
	mat.shader = sh
	_filter.material = mat
	add_child(_filter)
	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	add_child(_lines)
	visible = false


func _process(delta: float) -> void:
	_t += delta
	visible = amount > 0.01
	if visible:
		(_filter.material as ShaderMaterial).set_shader_parameter("strength", amount)
		_lines.modulate.a = amount
		_lines.queue_redraw()


func _draw_lines() -> void:
	var size := _lines.size
	var h := size.y
	var c := size * 0.5
	var w := maxf(h * 0.004, 2.0)  # the line width
	# The reticle: a faint ring, the four posts stopping short of the middle.
	var r := h * 0.2
	_lines.draw_arc(c, r, 0.0, TAU, 96, Color(CYAN, 0.45), w * 0.8, true)
	var gap := h * 0.05
	var long := h * 0.27
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_lines.draw_line(c + d * gap, c + d * long, CYAN, w, true)
	# The corner brackets: top-left and bottom-left boxes, and one tall one on the right.
	var m := h * 0.06
	var bw := h * 0.26
	var bh := h * 0.3
	var tl := Vector2(m * 1.4, m)
	_bracket(tl, Vector2(bw, bh))
	var bl := Vector2(m * 1.4, h - m)
	_bracket(bl, Vector2(bw, -bh))
	var tr := Vector2(size.x - m * 1.4, m)
	_bracket(tr, Vector2(-bw * 0.95, bh))
	_bracket(Vector2(size.x - m * 1.4, h - m), Vector2(-bw * 0.95, -bh))
	# The delta in the top-left box, turning.
	var dc := tl + Vector2(bw * 0.55, bh * 0.45)
	var ds := h * 0.065
	var pts := PackedVector2Array()
	for k in 4:
		var a := _t * 1.4 + float(k % 3) * TAU / 3.0 - PI * 0.5
		# A tall delta: the tip twice as far out as the base corners.
		var rr := ds * (1.25 if k % 3 == 0 else 0.8)
		pts.append(dc + Vector2(cos(a), sin(a)) * rr)
	_lines.draw_polyline(pts, RED, w, true)
	# The signal bars in the bottom-left box, rising to the right.
	var bars := 6
	for k in bars:
		var x := bl.x + bw * (0.38 + 0.11 * k)
		var top := bl.y - h * 0.02 - h * (0.03 + 0.035 * k)
		_lines.draw_line(Vector2(x, bl.y - h * 0.02), Vector2(x, top), RED, w * 1.1, true)
	# The range bar on the right: a long upright with end caps, a tick running up and down it.
	var rx := size.x - m * 1.4 - bw * 0.42
	var r_top := m + h * 0.05
	var r_bot := h - m - h * 0.08
	var cap := h * 0.06
	_lines.draw_line(Vector2(rx, r_top), Vector2(rx, r_bot), RED, w, true)
	_lines.draw_line(Vector2(rx - cap, r_top), Vector2(rx + cap, r_top), RED, w, true)
	_lines.draw_line(Vector2(rx - cap, r_bot), Vector2(rx + cap, r_bot), RED, w, true)
	var u := 0.5 - 0.5 * cos(_t * 2.2)
	var ty := lerpf(r_bot, r_top, u)
	_lines.draw_line(Vector2(rx - cap * 0.7, ty), Vector2(rx + cap * 0.7, ty), Color(RED, 0.9), w * 1.6, true)


## A corner bracket at `corner`: a line along it `size.x` and one down (or up) `size.y`.
func _bracket(corner: Vector2, size: Vector2) -> void:
	var w := maxf(_lines.size.y * 0.005, 2.0)
	_lines.draw_line(corner, corner + Vector2(size.x, 0.0), BLUE, w, true)
	_lines.draw_line(corner, corner + Vector2(0.0, size.y), BLUE, w, true)
