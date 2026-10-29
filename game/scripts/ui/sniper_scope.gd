class_name SniperScope
extends Control
## The Sniper's scope (Sniper: RMB), over the whole screen while it is up and under the defender's panels:
## black all round the lens, the lens darkening toward its rim, and a duplex reticle (heavy posts in from
## the rim, fine lines with mil dots in the middle, a red dot dead centre, where the round goes). Either
## side of the lens, the magnification and the range to what the reticle is on. Drawn in the sight's own
## colours while the thermal sight is on (the reticle light, so it shows on the dark).

## The lens: its radius (share of the screen's height).
const LENS := 0.46
const MASK_SHADER := """
shader_type canvas_item;
uniform float radius = 0.46;
uniform float aspect = 1.78;
uniform float strength = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float r = length(p);
	float outside = smoothstep(radius - 0.003, radius + 0.002, r);
	float rim = smoothstep(radius * 0.62, radius, r) * 0.55;
	COLOR = vec4(0.0, 0.0, 0.0, max(outside, rim) * strength);
}
"""
const INK := Color(0.03, 0.03, 0.03)
const THERMAL_INK := Color(0.6, 1.0, 0.6)
const DOT := Color(1.0, 0.15, 0.1)

var sniper: Sniper

var _mask: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask = ColorRect.new()
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = MASK_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mask.material = _mat
	_mask.show_behind_parent = true  # under the reticle drawn here
	add_child(_mask)


func _process(_delta: float) -> void:
	if not visible or sniper == null:
		return
	var view := get_viewport_rect().size
	_mat.set_shader_parameter("aspect", view.x / maxf(view.y, 1.0))
	_mat.set_shader_parameter("radius", LENS)
	# It comes on as the scope reaches her eye.
	modulate.a = smoothstep(0.45, 1.0, sniper.scope_fraction())
	queue_redraw()


func _draw() -> void:
	if sniper == null:
		return
	var view := get_viewport_rect().size
	var c := view * 0.5
	var r := view.y * LENS
	var thermal: bool = sniper.thermal_left > 0.0
	var ink := THERMAL_INK if thermal else INK
	var inner := r * 0.32
	# Heavy posts in from the rim, then fine lines to the middle.
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]:
		draw_line(c + d * r, c + d * inner, ink, 6.0)
		draw_line(c + d * inner, c + d * 3.0, ink, 1.5)
		for k in range(1, 5):
			draw_circle(c + d * inner * k / 5.0, 2.0, ink)
	draw_circle(c, 2.6, DOT)
	var font := get_theme_default_font()
	var zoom := "%dx" % int(Sniper.ZOOMS[sniper.zoom])
	var range_text := "RNG %d m" % roundi(sniper.scope_range()) if sniper.scope_range() < INF else "RNG ---"
	var dim := Color(0.85, 0.9, 0.95)
	draw_string(font, c + Vector2(-r - 110.0, 7.0), zoom, HORIZONTAL_ALIGNMENT_RIGHT, 90, 20, dim)
	draw_string(font, c + Vector2(r + 20.0, 7.0), range_text, HORIZONTAL_ALIGNMENT_LEFT, 140, 20, dim)
	if thermal:
		draw_string(font, c + Vector2(r + 20.0, 37.0), "THERMAL  %ds" % ceili(sniper.thermal_left),
				HORIZONTAL_ALIGNMENT_LEFT, 160, 18, Color(1.0, 0.75, 0.3))
