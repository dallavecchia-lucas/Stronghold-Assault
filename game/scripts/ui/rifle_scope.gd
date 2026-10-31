class_name RifleScope
extends CanvasLayer
## The Shadowline rifle's smart scope (DefenderSoldier, RMB): no looking down the sight, the scope sends
## its picture to the visor. The soldier's camera zooms in a little; over it, this:
##
##   the feed     the picture graded cool and a little darker, fine scan lines, a slow bright band
##                rolling down, a cyan-edged vignette, faint grain and colour fringing toward the edges
##   reticle      a thin ring open where the posts cross it, a bezel of fine ticks, three arc segments
##                turning round it, posts with stadia ticks stopping short of a red aim dot; they spread
##                when the rifle fires, and red lock corners close on a hostile under the dot
##   track        (top left) a compass ring turning with the heading, a red delta spinning inside it,
##                the heading and elevation
##   uplink       (bottom left) signal bars, the link strength, the magazine
##   range        (right) a 0-800 m laser-rangefinder scale, a red sweep running up and down it and a
##                marker on the range to whatever is under the dot
##
## All drawn in code (thin lines with a soft glow, JetBrains Mono for the readouts). When it opens, the
## panels slide in from the corners, the ring settles, the text types out and a scan beam runs down.
## `amount` (0..1) fades it all in and out; the soldier feeds it the readouts every frame.

const RETICLE := Color(0.52, 0.94, 1.0)
const FRAME := Color(0.46, 0.62, 1.0)
const ACCENT := Color(1.0, 0.37, 0.31)
const INK := Color(0.84, 0.95, 1.0)
const FONT := "res://assets/fonts/jetbrains_mono/JetBrainsMono-Medium.ttf"
const FONT_BOLD := "res://assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf"
## The range scale's top (m).
const SCALE_MAX := 800.0
## Seconds the boot-in takes.
const BOOT := 0.45
const FEED_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 1.0;
uniform float time_s = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r = length(d * vec2(1.78, 1.0));
	vec3 src = texture(screen_tex, uv).rgb;
	// A touch of colour fringing toward the edges.
	vec2 off = d * 0.004 * r;
	vec3 col = vec3(texture(screen_tex, uv + off).r, src.g, texture(screen_tex, uv - off).b);
	// Graded cool and a little darker, so the lines read over it.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(col, vec3(lum * 0.76, lum * 1.0, lum * 1.12), 0.32) * 0.88 + vec3(0.0, 0.018, 0.03);
	// Fine scan lines (a 3 px period) and a slow bright band rolling down.
	g *= 1.0 - 0.075 * (0.5 + 0.5 * sin(FRAGCOORD.y * 2.0944));
	float band = exp(-pow((fract(time_s * 0.06) * 1.4 - 0.2 - uv.y) * 12.0, 2.0));
	g += vec3(0.015, 0.045, 0.055) * band;
	// A vignette going cyan at the rim, and grain.
	float vig = smoothstep(0.55, 1.25, r);
	g = mix(g, g * 0.35 + vec3(0.0, 0.03, 0.045), vig);
	g *= 1.0 - 0.28 * smoothstep(0.3, 0.5, abs(d.y));
	float n = fract(sin(dot(FRAGCOORD.xy + vec2(time_s * 61.0, time_s * 17.0), vec2(12.9898, 78.233))) * 43758.5453);
	g += (n - 0.5) * 0.028;
	COLOR = vec4(mix(src, g, strength), 1.0);
}
"""

## How far in the scope's view is (0 = off, 1 = full).
var amount := 0.0
## Readouts (DefenderSoldier sets them): range to what is under the dot (m, < 0 for none), heading
## (deg, 0 = north, -Z), elevation (deg), the magazine, reload progress (0 = not reloading), zoom, and
## the name of a hostile under the dot ("" for none).
var range_m := -1.0
var heading := 0.0
var elevation := 0.0
var ammo := 30
var mag := 30
var reload := 0.0
var zoom := 1.0
var target := ""

var _feed: ColorRect
var _hud: Control
var _font: FontVariation
var _bold: Font
var _t := 0.0
var _open := 0.0
var _boot := 1.0
var _kick := 0.0
var _u := 1.0


func _init() -> void:
	layer = 4  # under the match's panels
	_feed = ColorRect.new()
	_feed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FEED_SHADER
	mat.shader = sh
	_feed.material = mat
	add_child(_feed)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_font = FontVariation.new()
	_font.base_font = load(FONT)
	_font.spacing_glyph = 1
	_bold = load(FONT_BOLD)
	visible = false


## A round fired: the posts kick out and settle.
func fired() -> void:
	_kick = 1.0


func _process(delta: float) -> void:
	_t += delta
	_kick = maxf(_kick - delta * 6.0, 0.0)
	if amount <= 0.01:
		_open = 0.0
		visible = false
		return
	visible = true
	_open += delta
	var b := clampf(_open / BOOT, 0.0, 1.0)
	_boot = 1.0 - pow(1.0 - b, 3.0)
	var mat := _feed.material as ShaderMaterial
	mat.set_shader_parameter("strength", amount)
	mat.set_shader_parameter("time_s", _t)
	_hud.modulate.a = amount * (0.35 + 0.65 * _boot)
	_hud.queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw_hud() -> void:
	var size := _hud.size
	_u = size.y / 1080.0
	var u := _u
	var c := size * 0.5
	var m := Vector2(64.0, 56.0) * u
	var slide := 44.0 * u * (1.0 - _boot)
	_glass(m + Vector2(-slide, -slide), Vector2(470.0, 280.0) * u)
	_glass(Vector2(m.x - slide, size.y - m.y + slide), Vector2(500.0, -270.0) * u)
	_glass(Vector2(size.x - m.x + slide, m.y - slide), Vector2(-300.0, size.y - 2.0 * m.y))
	_draw_reticle(c)
	_draw_track(m + Vector2(-slide, -slide))
	_draw_uplink(Vector2(m.x - slide, size.y - m.y + slide))
	_draw_range(Vector2(size.x - m.x + slide, m.y - slide), Vector2(size.x - m.x + slide, size.y - m.y + slide))
	_draw_banner(Vector2(c.x, m.y + 12.0 * u - slide))
	# The boot's scan beam, down the screen.
	if _open < 0.55:
		var y := size.y * clampf(_open / 0.42, 0.0, 1.0)
		var a := 0.5 * (1.0 - _open / 0.55)
		_hud.draw_rect(Rect2(0.0, y - 60.0 * u, size.x, 60.0 * u), Color(RETICLE, a * 0.08))
		_line(Vector2(0.0, y), Vector2(size.x, y), Color(RETICLE, a), 1.2)


func _draw_reticle(c: Vector2) -> void:
	var u := _u
	var r := 200.0 * u * (1.0 + 0.3 * (1.0 - _boot))
	# The ring, open where the posts cross it, and its bezel of fine ticks.
	for q in 4:
		_arc(c, r, deg_to_rad(q * 90.0 + 8.0), deg_to_rad(q * 90.0 + 82.0), Color(RETICLE, 0.5), 1.3)
	for k in 72:
		if k % 18 == 0:
			continue
		var major := k % 3 == 0
		var d := Vector2.from_angle(deg_to_rad(k * 5.0))
		var at := r + 9.0 * u
		_hud.draw_line(c + d * at, c + d * (at + (9.0 if major else 4.0) * u),
				Color(RETICLE, 0.4 if major else 0.16), u, true)
	# Three arc segments turning round it, and two finer ones the other way.
	for k in 3:
		var a0 := _t * 0.35 + k * TAU / 3.0
		_arc(c, r + 30.0 * u, a0, a0 + deg_to_rad(18.0), Color(RETICLE, 0.55), 2.0)
	for k in 2:
		var a0 := -_t * 0.22 + k * PI + 0.6
		_arc(c, r + 40.0 * u, a0, a0 + deg_to_rad(7.0), Color(FRAME, 0.6), 1.0)
	# The posts, stopping short of the middle (further when the rifle kicks), and stubs past the ring.
	var gap := 24.0 * u * (1.0 + 0.8 * _kick)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_line(c + d * gap, c + d * (r - 16.0 * u), Color(RETICLE, 0.95), 1.5)
		_line(c + d * (r + 22.0 * u), c + d * (r + 74.0 * u), Color(RETICLE, 0.45), 1.1)
	# Stadia ticks down the lower post and along the horizontal ones.
	for k in range(1, 7):
		var y := gap + k * 24.0 * u
		var half := (8.0 if k % 2 == 0 else 4.0) * u
		_hud.draw_line(c + Vector2(-half, y), c + Vector2(half, y), Color(RETICLE, 0.6), 1.2 * u, true)
	for k in range(1, 6):
		var x := gap + k * 30.0 * u
		var half := (6.0 if k % 2 == 0 else 3.0) * u
		for side: float in [-1.0, 1.0]:
			_hud.draw_line(c + Vector2(side * x, -half), c + Vector2(side * x, half), Color(RETICLE, 0.45), u, true)
	# The aim dot, in a faint ring.
	_hud.draw_arc(c, 7.0 * u, 0.0, TAU, 24, Color(RETICLE, 0.3), u, true)
	_hud.draw_circle(c, 4.5 * u, Color(ACCENT, 0.25))
	_hud.draw_circle(c, 2.2 * u, ACCENT)
	# Zoom, low on the ring's right.
	var z := c + Vector2.from_angle(deg_to_rad(38.0)) * (r + 52.0 * u)
	_text(z, "×%.1f" % zoom, 15.0, Color(INK, 0.75), HORIZONTAL_ALIGNMENT_LEFT, false, 0.15)
	_text(z + Vector2(0.0, 18.0 * u), "OPTIC", 11.0, Color(INK, 0.55), HORIZONTAL_ALIGNMENT_LEFT, false, 0.2)
	# A hostile under the dot: red corners closing on it, and what it is under the ring.
	if target != "":
		var s := (30.0 + 3.0 * sin(_t * 8.0)) * u
		var l := 11.0 * u
		for dx: float in [-1.0, 1.0]:
			for dy: float in [-1.0, 1.0]:
				var p := c + Vector2(dx, dy) * s
				_line(p, p - Vector2(dx * l, 0.0), ACCENT, 1.8)
				_line(p, p - Vector2(0.0, dy * l), ACCENT, 1.8)
		var y := c.y + r + 104.0 * u
		_text(Vector2(c.x, y), "HOSTILE  ·  " + target.to_upper(), 15.0, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, true)


## The top-left panel: the compass ring and the spinning delta, the heading and elevation.
func _draw_track(p: Vector2) -> void:
	var u := _u
	_panel_corner(p, Vector2(1.0, 1.0), 400.0, 250.0)
	_text(p + Vector2(24.0, 42.0) * u, "TRACK // AZIMUTH", 14.0, Color(INK, 0.75), HORIZONTAL_ALIGNMENT_LEFT, false, 0.05)
	var d := p + Vector2(112.0, 152.0) * u
	# The compass ring: dashes turning with the heading, the cardinal points on it (north in red).
	var turn := -deg_to_rad(heading)
	for k in 36:
		var a0 := turn + k * TAU / 36.0
		_hud.draw_arc(d, 60.0 * u, a0, a0 + TAU / 72.0, 3, Color(FRAME, 0.55 if k % 9 == 0 else 0.25), 1.4 * u, true)
	_hud.draw_arc(d, 42.0 * u, 0.0, TAU, 48, Color(FRAME, 0.15), u, true)
	for k in 4:
		var a := turn + k * PI * 0.5 - PI * 0.5
		var at := d + Vector2.from_angle(a) * 78.0 * u + Vector2(0.0, 5.0 * u)
		_text(at, "NESW"[k], 11.0, ACCENT if k == 0 else Color(INK, 0.45), HORIZONTAL_ALIGNMENT_CENTER, true)
	# The delta, spinning.
	var spin := _t * 0.9
	var tri := PackedVector2Array()
	for k in 3:
		var a := spin + k * TAU / 3.0
		var rr := 36.0 if k == 0 else 23.0
		if k > 0:
			a = spin + (1.0 if k == 1 else -1.0) * deg_to_rad(140.0)
		tri.append(d + Vector2.from_angle(a) * rr * u)
	_hud.draw_colored_polygon(tri, Color(ACCENT, 0.13))
	tri.append(tri[0])
	_poly(tri, ACCENT, 1.7)
	_hud.draw_circle(d, 2.0 * u, Color(ACCENT, 0.9))
	# The readouts.
	var x := p.x + 216.0 * u
	_text(Vector2(x, p.y + 112.0 * u), "HDG", 12.0, Color(INK, 0.62))
	_text(Vector2(x, p.y + 150.0 * u), "%03d°" % int(round(fposmod(heading, 360.0))), 32.0, Color(INK, 0.95), HORIZONTAL_ALIGNMENT_LEFT, true, 0.1)
	_text(Vector2(x, p.y + 186.0 * u), "ELV", 12.0, Color(INK, 0.62))
	_text(Vector2(x, p.y + 214.0 * u), "%+03d°" % int(round(elevation)), 20.0, Color(INK, 0.8), HORIZONTAL_ALIGNMENT_LEFT, true, 0.15)


## The bottom-left panel: signal bars, the link, the magazine.
func _draw_uplink(q: Vector2) -> void:
	var u := _u
	_panel_corner(q, Vector2(1.0, -1.0), 430.0, 240.0)
	_text(q + Vector2(24.0, -196.0) * u, "UPLINK // S-7 SMART SCOPE", 14.0, Color(INK, 0.75), HORIZONTAL_ALIGNMENT_LEFT, false, 0.05)
	# Ten bars rising to the right; now and then the link dips a bar or two.
	var lit := 9
	if fmod(_t, 3.7) < 0.14:
		lit = 7
	elif fmod(_t, 5.3) < 0.2:
		lit = 8
	var base := q.y - 36.0 * u
	var x0 := q.x + 26.0 * u
	for k in 10:
		var hgt := (14.0 + k * 9.0) * u
		var rect := Rect2(x0 + k * 13.0 * u, base - hgt, 5.0 * u, hgt)
		if k < lit:
			var a := 0.95 if k < lit - 1 else 0.55 + 0.4 * sin(_t * 7.0)
			_hud.draw_rect(rect.grow(2.0 * u), Color(ACCENT, 0.12 * a))
			_hud.draw_rect(rect, Color(ACCENT, a))
		else:
			_hud.draw_rect(rect, Color(FRAME, 0.14))
	var link := 94 + lit / 3 + int(2.0 * sin(_t * 0.7))
	var lx := x0 + 148.0 * u
	_text(Vector2(lx, q.y - 116.0 * u), "LINK", 12.0, Color(INK, 0.62))
	_text(Vector2(lx, q.y - 80.0 * u), "%d%%" % link, 26.0, Color(INK, 0.92), HORIZONTAL_ALIGNMENT_LEFT, true, 0.1)
	_text(Vector2(lx, q.y - 44.0 * u), "S/N %d dB" % (38 + lit), 12.0, Color(INK, 0.55))
	# The magazine (red when low; reloading, a progress line under it).
	var ax := q.x + 312.0 * u
	_text(Vector2(ax, q.y - 116.0 * u), "MAG", 12.0, Color(INK, 0.62))
	var low := ammo <= mag / 4
	if reload > 0.0:
		var blink := 0.55 + 0.45 * sin(_t * 10.0)
		_text(Vector2(ax, q.y - 62.0 * u), "RLD", 40.0, Color(ACCENT, blink), HORIZONTAL_ALIGNMENT_LEFT, true)
		var w := 88.0 * u
		_hud.draw_line(Vector2(ax, q.y - 44.0 * u), Vector2(ax + w, q.y - 44.0 * u), Color(FRAME, 0.25), 2.0 * u)
		_line(Vector2(ax, q.y - 44.0 * u), Vector2(ax + w * reload, q.y - 44.0 * u), ACCENT, 2.0)
	else:
		var digits := "%02d" % ammo
		_text(Vector2(ax, q.y - 62.0 * u), digits, 44.0, ACCENT if low else Color(INK, 0.95), HORIZONTAL_ALIGNMENT_LEFT, true, 0.1)
		var dw := _bold.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(44.0 * u))).x
		_text(Vector2(ax + dw + 4.0 * u, q.y - 62.0 * u), "/%d" % mag, 17.0, Color(INK, 0.5), HORIZONTAL_ALIGNMENT_LEFT, false, 0.15)


## The right panel: the rangefinder's scale, its sweep and the range marker.
func _draw_range(tr: Vector2, br: Vector2) -> void:
	var u := _u
	_panel_corner(tr, Vector2(-1.0, 1.0), 320.0, 300.0)
	_panel_corner(br, Vector2(-1.0, -1.0), 320.0, 300.0)
	_text(tr + Vector2(-24.0, 42.0) * u, "RANGE // LRF", 14.0, Color(INK, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, false, 0.05)
	var sx := tr.x - 132.0 * u
	var y0 := tr.y + 96.0 * u
	var y1 := br.y - 96.0 * u
	# The spine with its end caps, and the graduations (a label every 100 m).
	_line(Vector2(sx, y0), Vector2(sx, y1), Color(ACCENT, 0.7), 1.3)
	for y: float in [y0, y1]:
		_line(Vector2(sx - 22.0 * u, y), Vector2(sx + 22.0 * u, y), ACCENT, 2.0)
	for k in range(1, 40):
		var y := lerpf(y1, y0, k / 40.0)
		var major := k % 5 == 0
		_hud.draw_line(Vector2(sx - (14.0 if major else 6.0) * u, y), Vector2(sx - 2.0 * u, y),
				Color(INK, 0.5 if major else 0.2), u, true)
		if major:
			_text(Vector2(sx - 22.0 * u, y + 4.0 * u), str(k * 20), 11.0, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(sx - 30.0 * u, y0 + 4.0 * u), "800", 11.0, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(sx - 30.0 * u, y1 + 4.0 * u), "0", 11.0, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	# The sweep: a red line running up and down the scale, fading lines trailing it.
	var period := 1.7
	for i in range(6, 0, -1):
		var s := 0.5 - 0.5 * cos((_t - i * 0.03) * period)
		var y := lerpf(y1, y0, s)
		_hud.draw_line(Vector2(sx - 26.0 * u, y), Vector2(sx + 26.0 * u, y), Color(ACCENT, 0.28 * (1.0 - i / 7.0)), u, true)
	var ys := lerpf(y1, y0, 0.5 - 0.5 * cos(_t * period))
	_line(Vector2(sx - 34.0 * u, ys), Vector2(sx + 34.0 * u, ys), ACCENT, 1.8)
	_hud.draw_circle(Vector2(sx - 34.0 * u, ys), 2.2 * u, ACCENT)
	_hud.draw_circle(Vector2(sx + 34.0 * u, ys), 2.2 * u, ACCENT)
	# The marker on the range, and its readout (a dim one at the top when nothing returns).
	if range_m >= 0.0:
		var yr := lerpf(y1, y0, clampf(range_m / SCALE_MAX, 0.0, 1.0))
		var chev := PackedVector2Array([Vector2(sx + 6.0 * u, yr), Vector2(sx + 20.0 * u, yr - 8.0 * u), Vector2(sx + 20.0 * u, yr + 8.0 * u)])
		_hud.draw_colored_polygon(chev, RETICLE)
		var box := Rect2(sx + 26.0 * u, yr - 16.0 * u, 86.0 * u, 32.0 * u)
		_hud.draw_rect(box, Color(0.0, 0.05, 0.08, 0.35))
		_hud.draw_rect(box, Color(RETICLE, 0.45), false, u)
		_text(Vector2(box.position.x + 9.0 * u, yr + 8.0 * u), "%d" % int(round(range_m)), 21.0, RETICLE, HORIZONTAL_ALIGNMENT_LEFT, true)
		_text(Vector2(box.end.x - 8.0 * u, yr + 7.0 * u), "M", 11.0, Color(RETICLE, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_text(Vector2(sx + 28.0 * u, y0 + 6.0 * u), "NO RTN", 12.0, Color(INK, 0.5))
	# The rangefinder's status, a red light blinking.
	var foot := br + Vector2(-24.0, -40.0) * u
	_text(foot, "LASER ACTIVE", 12.0, Color(INK, 0.65), HORIZONTAL_ALIGNMENT_RIGHT, false, 0.2)
	var dot_x := foot.x - _font.get_string_size("LASER ACTIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(12.0 * u))).x - 14.0 * u
	if fmod(_t, 1.0) < 0.6:
		_hud.draw_circle(Vector2(dot_x, foot.y - 4.0 * u), 3.0 * u, ACCENT)


## The top banner: the scope's name between two thin rules, a red LIVE light.
func _draw_banner(at: Vector2) -> void:
	var u := _u
	var text := "SHADOWLINE S-7  ·  SMART LINK"
	var fs := 13.0
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs * u))).x
	_text(at + Vector2(0.0, 4.0 * u), text, fs, Color(INK, 0.7), HORIZONTAL_ALIGNMENT_CENTER, false, 0.1)
	var y := at.y
	for side: float in [-1.0, 1.0]:
		var a := at.x + side * (w * 0.5 + 22.0 * u)
		var b := at.x + side * (w * 0.5 + 170.0 * u)
		_fade_line(Vector2(a, y), Vector2(b, y), FRAME, 1.0, 0.55, 0.0)
		_hud.draw_line(Vector2(a, y - 5.0 * u), Vector2(a, y + 5.0 * u), Color(FRAME, 0.7), u, true)
	var live := at.x - w * 0.5 - 196.0 * u
	if fmod(_t, 1.2) < 0.75:
		_hud.draw_circle(Vector2(live, y), 3.2 * u, ACCENT)
	_text(Vector2(live - 10.0 * u, y + 4.0 * u), "LIVE", 11.0, Color(ACCENT, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, true)


## A panel's corner: a strong L at `p` (its arms along `dir`), thin edges running on and fading out,
## a short red tab and a small square in the corner.
func _panel_corner(p: Vector2, dir: Vector2, w: float, h: float) -> void:
	var u := _u
	var arm := 46.0 * u
	_line(p, p + Vector2(dir.x * arm, 0.0), Color(FRAME, 0.95), 2.2)
	_line(p, p + Vector2(0.0, dir.y * arm), Color(FRAME, 0.95), 2.2)
	_fade_line(p + Vector2(dir.x * arm, 0.0), p + Vector2(dir.x * w * u, 0.0), FRAME, 1.0, 0.5, 0.0)
	_fade_line(p + Vector2(0.0, dir.y * arm), p + Vector2(0.0, dir.y * h * u), FRAME, 1.0, 0.5, 0.0)
	var tab := p + Vector2(dir.x * 64.0, dir.y * 7.0) * u
	_line(tab, tab + Vector2(dir.x * 42.0 * u, 0.0), Color(ACCENT, 0.9), 2.4)
	_hud.draw_rect(Rect2(p + Vector2(dir.x * 9.0, dir.y * 9.0) * u - Vector2(2.0, 2.0) * u, Vector2(4.0, 4.0) * u), Color(FRAME, 0.8))


# ---------------------------------------------------------------- primitives

## A dark glass backdrop from `corner` (where it is darkest) across `extent`, fading out.
func _glass(corner: Vector2, extent: Vector2) -> void:
	var dark := Color(0.0, 0.04, 0.07, 0.42)
	var clear := Color(0.0, 0.04, 0.07, 0.0)
	var pts := PackedVector2Array([corner, corner + Vector2(extent.x, 0.0), corner + extent, corner + Vector2(0.0, extent.y)])
	_hud.draw_polygon(pts, PackedColorArray([dark, clear, clear, Color(dark, 0.18)]))


## A line with a soft glow round it (width in 1080p pixels).
func _line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var w := width * _u
	_hud.draw_line(a, b, Color(col, col.a * 0.08), w * 6.0, true)
	_hud.draw_line(a, b, Color(col, col.a * 0.22), w * 2.6, true)
	_hud.draw_line(a, b, col, w, true)


func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, width: float) -> void:
	var w := width * _u
	var n := maxi(int(absf(a1 - a0) * 32.0), 4)
	_hud.draw_arc(c, r, a0, a1, n, Color(col, col.a * 0.08), w * 6.0, true)
	_hud.draw_arc(c, r, a0, a1, n, Color(col, col.a * 0.22), w * 2.6, true)
	_hud.draw_arc(c, r, a0, a1, n, col, w, true)


func _poly(pts: PackedVector2Array, col: Color, width: float) -> void:
	var w := width * _u
	_hud.draw_polyline(pts, Color(col, col.a * 0.08), w * 6.0, true)
	_hud.draw_polyline(pts, Color(col, col.a * 0.22), w * 2.6, true)
	_hud.draw_polyline(pts, col, w, true)


## A thin line fading from alpha a0 to a1 along it.
func _fade_line(a: Vector2, b: Vector2, col: Color, width: float, a0: float, a1: float) -> void:
	var n := 10
	for k in n:
		var p0 := a.lerp(b, float(k) / n)
		var p1 := a.lerp(b, float(k + 1) / n)
		_hud.draw_line(p0, p1, Color(col, lerpf(a0, a1, (k + 0.5) / n)), width * _u, true)


## Text (size in 1080p pixels) at a baseline point; left-aligned text types out as the scope opens
## (`delay` s in), the rest fades in.
func _text(at: Vector2, s: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		bold := false, delay := 0.0) -> void:
	var reveal := clampf((_open - delay) / 0.3, 0.0, 1.0)
	if reveal <= 0.0:
		return
	var font: Font = _bold if bold else _font
	var fs := int(round(size * _u))
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		s = s.substr(0, int(ceil(s.length() * reveal)))
	else:
		col.a *= reveal
	var w := 1200.0 * _u
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	_hud.draw_string(font, Vector2(x, at.y + maxf(_u, 1.0)), s, align, w, fs, Color(0.0, 0.03, 0.06, col.a * 0.6))
	_hud.draw_string(font, Vector2(x, at.y), s, align, w, fs, col)
