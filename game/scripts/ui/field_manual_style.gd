class_name FieldManualStyle
extends RefCounted
## The look of the Field Manual's two books (FieldManual): their paper, ink, type and furniture.
##
##   host      the Host's FM 1-01: a cloth-bound book on a walnut desk under a warm lamp. Ivory paper, foxed at the
##             edges; EB Garamond (old-style figures, small caps) set like a printed manual, Libre Franklin for
##             the heavy heads; vermilion for the second colour; the plates are photographs mounted with
##             corners; the soldiers' notes in pencil (Reenie Beanie).
##   garrison  the Keep's TM 30-90: a ring binder on a steel desk under a cold strip light. Grey-green form paper
##             printed in green-grey (Overpass, the forms' own face), typed on in blue-black (Courier Prime, each
##             letter struck a little differently), red for the classification; photographs clipped on.
##
## Everything here is drawn in code or by shaders: no image files.

const FONT_DIR := "res://assets/fonts/"

const HOST := {
	"desk_a": Color(0.17, 0.105, 0.065), "desk_b": Color(0.075, 0.045, 0.028), "desk_kind": 0,
	"lamp": Color(1.0, 0.87, 0.68), "lamp_at": Vector2(0.3, 0.12), "lamp_reach": 0.95,
	"cover": Color(0.27, 0.27, 0.16), "cover_edge": Color(0.14, 0.14, 0.08),
	"paper": Color(0.925, 0.886, 0.79), "paper_shade": Color(0.80, 0.72, 0.55), "fox": Color(0.62, 0.44, 0.24),
	"fibers": 0.05, "foxing": 0.32, "mottle": 0.45, "curl": 1.0,
	"ink": Color(0.13, 0.105, 0.085), "ink_soft": Color(0.13, 0.105, 0.085, 0.72), "ink_faint": Color(0.13, 0.105, 0.085, 0.45),
	"accent": Color(0.64, 0.2, 0.11), "pencil": Color(0.28, 0.29, 0.33, 0.88),
	"print_border": Color(0.955, 0.94, 0.9), "mount": Color(0.15, 0.12, 0.09),
	"photo_shadow": Color(0.16, 0.12, 0.09), "photo_light": Color(0.98, 0.93, 0.8),
	"photo_tone": 0.5, "photo_contrast": 1.06, "photo_grain": 0.055, "photo_vignette": 0.42,
	"ribbon": Color(0.52, 0.12, 0.08),
}

const GARRISON := {
	"desk_a": Color(0.13, 0.15, 0.155), "desk_b": Color(0.05, 0.06, 0.065), "desk_kind": 1,
	"lamp": Color(0.86, 0.94, 1.0), "lamp_at": Vector2(0.5, -0.05), "lamp_reach": 1.15,
	"cover": Color(0.09, 0.12, 0.105), "cover_edge": Color(0.03, 0.045, 0.04),
	"paper": Color(0.86, 0.875, 0.83), "paper_shade": Color(0.70, 0.73, 0.67), "fox": Color(0.55, 0.5, 0.36),
	"fibers": 0.025, "foxing": 0.05, "mottle": 0.25, "curl": 0.55,
	"ink": Color(0.11, 0.13, 0.19), "ink_soft": Color(0.11, 0.13, 0.19, 0.75), "ink_faint": Color(0.11, 0.13, 0.19, 0.4),
	"form": Color(0.27, 0.36, 0.31), "form_faint": Color(0.27, 0.36, 0.31, 0.45),
	"accent": Color(0.7, 0.15, 0.11), "pencil": Color(0.72, 0.14, 0.1, 0.85),
	"print_border": Color(0.93, 0.94, 0.92), "mount": Color(0.62, 0.64, 0.66),
	"photo_shadow": Color(0.08, 0.1, 0.12), "photo_light": Color(0.9, 0.94, 0.95),
	"photo_tone": 0.66, "photo_contrast": 1.2, "photo_grain": 0.06, "photo_vignette": 0.3,
	"ribbon": Color(0.7, 0.15, 0.11),
}

static var _fonts := {}


static func palette(attacker: bool) -> Dictionary:
	return HOST if attacker else GARRISON


# ---------------------------------------------------------------- type

static func _tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


## A variation of one of the families, cached: weight on the variable faces, OpenType features, extra spacing.
static func font(family: String, weight := 400, features: Array = [], spacing := 0) -> Font:
	var key := "%s/%d/%s/%d" % [family, weight, ",".join(features), spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base: FontFile
	match family:
		"serif":
			base = load(FONT_DIR + "eb_garamond/EBGaramond-Variable.ttf")
		"italic":
			base = load(FONT_DIR + "eb_garamond/EBGaramond-Italic-Variable.ttf")
		"gothic":
			base = load(FONT_DIR + "libre_franklin/LibreFranklin-Variable.ttf")
		"hand":
			base = load(FONT_DIR + "reenie_beanie/ReenieBeanie.ttf")
		"typed":
			base = load(FONT_DIR + "courier_prime/CourierPrime-Regular.ttf")
		"typed_bold":
			base = load(FONT_DIR + "courier_prime/CourierPrime-Bold.ttf")
		"typed_italic":
			base = load(FONT_DIR + "courier_prime/CourierPrime-Italic.ttf")
		"form":
			base = load(FONT_DIR + "overpass/Overpass-Variable.ttf")
		"stencil":
			base = load(FONT_DIR + "big_shoulders_stencil/BigShouldersStencilDisplay-Variable.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	if family in ["serif", "italic", "gothic", "form", "stencil"]:
		fv.variation_opentype = {_tag("wght"): weight}
	var feats := {}
	for f in features:
		feats[_tag(f)] = 1
	fv.opentype_features = feats
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


## The body face of a book, its italic, its bold and the face its labels are set in.
static func body(attacker: bool) -> Font:
	return font("serif", 420, ["onum", "liga", "kern"]) if attacker else font("typed")


static func body_italic(attacker: bool) -> Font:
	return font("italic", 420, ["onum", "liga"]) if attacker else font("typed_italic")


static func body_bold(attacker: bool) -> Font:
	return font("serif", 600, ["onum", "liga"]) if attacker else font("typed_bold")


## Small caps, spaced out: the Host's running heads and labels.
static func small_caps(spacing := 2, weight := 480) -> Font:
	return font("serif", weight, ["smcp", "c2sc", "onum"], spacing)


static func label(text: String, f: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A RichTextLabel set up for a book's body text: fits its content, no scrolling, its faces and size.
static func rich(attacker: bool, size: int, color: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = false
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.meta_underlined = false
	r.add_theme_font_override("normal_font", body(attacker))
	r.add_theme_font_override("italics_font", body_italic(attacker))
	r.add_theme_font_override("bold_font", body_bold(attacker))
	r.add_theme_font_override("bold_italics_font", body_italic(attacker))
	for k in ["normal_font_size", "italics_font_size", "bold_font_size", "bold_italics_font_size", "mono_font_size"]:
		r.add_theme_font_size_override(k, size)
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", 2 if attacker else 3)
	return r


# ---------------------------------------------------------------- shaders

const NOISE := """
float hash(vec2 q) {
	q = fract(q * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 q) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise(q);
		q = q * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}
"""

## A page: the paper's colour mottled, its fibres, foxing freckles, the edges aged darker, and the page bending
## down into the spine (spine_side 1: the spine at its right edge, a left-hand page; -1: a right-hand page).
const PAPER := """
shader_type canvas_item;
uniform vec4 paper : source_color;
uniform vec4 shade : source_color;
uniform vec4 fox : source_color;
uniform float fibers = 0.04;
uniform float foxing = 0.25;
uniform float mottle = 0.35;
uniform float curl = 1.0;
uniform float spine_side = 1.0;
uniform vec2 size = vec2(720.0, 820.0);
uniform float seed = 0.0;
// A cup set down on the page once: its centre and radius (page px; radius 0: none), and how dark.
uniform vec3 stain = vec3(0.0);
uniform float stain_amount = 0.0;
varying vec2 p;
void vertex() {
	p = VERTEX;
}
%s
void fragment() {
	vec3 col = paper.rgb;
	float m = fbm(p * 0.005 + seed);
	col = mix(col, shade.rgb, clamp((m - 0.42) * mottle * 2.2, 0.0, 1.0));
	float f = noise(vec2(p.x * 0.33, p.y * 0.03) + seed * 13.0) * noise(vec2(p.x * 0.045, p.y * 0.38) + seed * 7.0);
	col -= (f - 0.22) * fibers;
	col -= (hash(floor(p * 1.5) + seed) - 0.5) * 0.018;
	float fx = fbm(p * 0.05 + seed * 3.1);
	float spot = smoothstep(0.71, 0.79, fx) * smoothstep(0.5, 0.85, fbm(p * 0.0035 + seed * 5.0));
	col = mix(col, fox.rgb, spot * foxing);
	if (stain.z > 0.0) {
		float wob = (fbm(p * 0.02 + seed * 2.0) - 0.5) * 0.16;
		float d = length(p - stain.xy) / stain.z + wob;
		float rim = exp(-pow((d - 1.0) * 16.0, 2.0)) * (0.6 + 0.4 * fbm(p * 0.05 + seed));
		float inside = (1.0 - smoothstep(0.85, 1.0, d)) * 0.22;
		col = mix(col, col * vec3(0.8, 0.67, 0.5), clamp(rim * 0.85 + inside, 0.0, 1.0) * stain_amount);
	}
	float e = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	float ragged = fbm(p * 0.025 + seed * 9.0);
	col = mix(col, shade.rgb * 0.9, (1.0 - smoothstep(0.0, 14.0 + ragged * 30.0, e)) * 0.6);
	float g = spine_side > 0.0 ? size.x - p.x : p.x;
	col *= 1.0 - curl * (0.4 * exp(-g / 24.0) + 0.09 * exp(-g / 130.0));
	float o = spine_side > 0.0 ? p.x : size.x - p.x;
	col *= 1.0 + 0.03 * exp(-o / 80.0);
	COLOR = vec4(col, 1.0);
}
""" % NOISE

## The desk under the book: walnut (kind 0) or brushed steel (kind 1), lit by a pool of lamp light.
const DESK := """
shader_type canvas_item;
uniform vec4 base_a : source_color;
uniform vec4 base_b : source_color;
uniform vec4 lamp : source_color;
uniform vec2 lamp_at = vec2(0.3, 0.1);
uniform float reach = 1.0;
uniform int kind = 0;
uniform float alpha = 1.0;
%s
void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 q = uv * vec2(aspect, 1.0) * 900.0;
	vec3 col;
	if (kind == 0) {
		float warp = fbm(vec2(q.x * 0.0025, q.y * 0.02));
		float grain = sin(q.y * 0.11 + warp * 22.0 + fbm(q * 0.01) * 4.0) * 0.5 + 0.5;
		float fine = noise(vec2(q.x * 0.02, q.y * 1.2));
		col = mix(base_b.rgb, base_a.rgb, grain * 0.7 + fine * 0.3);
		col *= 0.85 + 0.3 * fbm(vec2(q.x * 0.0012, q.y * 0.01) + 4.0);
	} else {
		float brush = noise(vec2(q.x * 0.004, q.y * 1.6)) * 0.6 + noise(vec2(q.x * 0.0011, q.y * 0.7)) * 0.4;
		col = mix(base_b.rgb, base_a.rgb, 0.55 + (brush - 0.5) * 0.5);
		col *= 0.9 + 0.2 * fbm(q * 0.004);
		float scratch = smoothstep(0.985, 1.0, noise(vec2(q.x * 0.3 + q.y * 0.05, q.y * 0.02)));
		col += scratch * 0.04;
	}
	vec2 d = (uv - lamp_at) * vec2(aspect, 1.0);
	float pool = exp(-dot(d, d) / (reach * reach * 0.55));
	col *= mix(vec3(0.28), lamp.rgb * 1.35, pool);
	float vig = smoothstep(1.4, 0.35, length((uv - 0.5) * vec2(aspect, 1.0)));
	col *= mix(0.55, 1.0, vig);
	COLOR = vec4(col, alpha);
}
""" % NOISE

## The lamp's light falling across the book: multiplied over it, bright under the lamp, dimmer away from it.
const LAMP := """
shader_type canvas_item;
render_mode blend_mul;
uniform vec4 lamp : source_color;
uniform vec2 lamp_at = vec2(0.3, 0.1);
uniform float reach = 1.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = (uv - lamp_at) * vec2(aspect, 1.0);
	float pool = exp(-dot(d, d) / (reach * reach * 0.9));
	vec3 l = mix(vec3(0.74, 0.72, 0.7), lamp.rgb * 1.02, pool);
	COLOR = vec4(min(l, vec3(1.0)), 1.0);
}
"""

## A plate: the clip printed as a photograph. Toned toward the book's duotone, a lifted black, grain, vignette.
const PHOTO := """
shader_type canvas_item;
uniform vec4 dark : source_color;
uniform vec4 light : source_color;
uniform float tone = 0.5;
uniform float contrast = 1.05;
uniform float grain = 0.05;
uniform float vignette = 0.4;
uniform float flash = 0.0;
%s
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	l = clamp((l - 0.5) * contrast + 0.5, 0.0, 1.0);
	vec3 duo = mix(dark.rgb, light.rgb, l);
	vec3 col = mix(c.rgb, duo, tone);
	col = mix(dark.rgb * 0.8, light.rgb, col);
	col += (hash(UV * vec2(640.0, 360.0) + fract(TIME * 7.3)) - 0.5) * grain;
	float v = smoothstep(0.95, 0.3, length((UV - 0.5) * vec2(1.25, 1.0)));
	col *= mix(1.0 - vignette, 1.0, v);
	col = mix(col, light.rgb, flash);
	COLOR = vec4(col, 1.0);
}
""" % NOISE

## Ink on paper: rubber stamps and pencil. Multiplied over the page, its coverage eaten away where the stamp
## missed or the lead skipped.
const INK := """
shader_type canvas_item;
render_mode blend_mul;
uniform float erode = 0.3;
uniform float speckle = 0.25;
uniform float seed = 0.0;
varying vec2 lp;
void vertex() {
	lp = VERTEX;
}
%s
void fragment() {
	vec4 c = COLOR;
	float n = fbm(lp * 0.07 + seed);
	float a = c.a * smoothstep(erode - 0.12, erode + 0.12, n) * mix(1.0 - speckle, 1.0, noise(lp * 0.8 + seed * 3.0));
	COLOR = vec4(mix(vec3(1.0), c.rgb, a), 1.0);
}
""" % NOISE

static var _shaders := {}


static func material(code: String, params := {}) -> ShaderMaterial:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[code]
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func paper_material(pal: Dictionary, spine_side: float, size: Vector2, seed: float) -> ShaderMaterial:
	return material(PAPER, {"paper": pal.paper, "shade": pal.paper_shade, "fox": pal.fox, "fibers": pal.fibers,
			"foxing": pal.foxing, "mottle": pal.mottle, "curl": pal.curl, "spine_side": spine_side, "size": size, "seed": seed})


static func photo_material(pal: Dictionary) -> ShaderMaterial:
	return material(PHOTO, {"dark": pal.photo_shadow, "light": pal.photo_light, "tone": pal.photo_tone,
			"contrast": pal.photo_contrast, "grain": pal.photo_grain, "vignette": pal.photo_vignette})


static func ink_material(erode := 0.3, seed := 0.0, speckle := 0.25) -> ShaderMaterial:
	return material(INK, {"erode": erode, "seed": seed, "speckle": speckle})


# ---------------------------------------------------------------- typewriter

## Typed text: every letter struck a little off the line and inked a little differently, as a typewriter does.
## The same letter of the same text always lands the same way.
class TypedInk:
	extends RichTextEffect

	var bbcode := "typed"

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var i: int = fx.range.x
		fx.offset += Vector2((_h(i) - 0.5) * 0.7, (_h(i * 7 + 3) - 0.5) * 1.0)
		fx.color.a *= 0.74 + 0.26 * _h(i * 13 + 5)
		return true

	static func _h(n: int) -> float:
		return fposmod(sin(float(n) * 12.9898 + 78.233) * 43758.5453, 1.0)


# ---------------------------------------------------------------- furniture

## A soft shadow under a rectangle (a photograph, the book): drawn as a few layers, darkest at the middle.
class Shadow:
	extends Control

	var color := Color(0, 0, 0, 0.35)
	var spread := 14.0
	var offset := Vector2(4, 8)

	func _draw() -> void:
		var layers := 7
		for i in layers:
			var g := spread * float(layers - i) / layers
			var c := color
			c.a = color.a / layers * 1.6
			draw_rect(Rect2(offset - Vector2(g, g) * 0.5, size + Vector2(g, g)), c)


## The black paper corners a photograph is mounted with.
class PhotoCorners:
	extends Control

	var color := Color(0.15, 0.12, 0.09)
	var leg := 30.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hi := Color(1, 1, 1, 0.08)
		for k in 4:
			var o := [r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)][k] as Vector2
			var sx := 1.0 if k in [0, 3] else -1.0
			var sy := 1.0 if k in [0, 1] else -1.0
			var pts := PackedVector2Array([o + Vector2(-4 * sx, -4 * sy), o + Vector2((leg + 2) * sx, -4 * sy),
					o + Vector2(-4 * sx, (leg + 2) * sy)])
			draw_colored_polygon(pts, color)
			draw_line(o + Vector2((leg + 2) * sx, -4 * sy), o + Vector2(-4 * sx, (leg + 2) * sy), hi, 1.2, true)


## A steel paper clip over the top edge of a photograph: a gem clip, its wire bent round three times.
class PaperClip:
	extends Control

	func _draw() -> void:
		var pts := PackedVector2Array()
		pts.append(Vector2(7, 58))
		_arc(pts, Vector2(12, 12), 5.0, PI, TAU)
		pts.append(Vector2(17, 74))
		_arc(pts, Vector2(9.5, 74), 7.5, 0.0, PI)
		pts.append(Vector2(2, 9))
		_arc(pts, Vector2(11.5, 9), 9.5, PI, TAU)
		pts.append(Vector2(21, 52))
		draw_polyline(pts, Color(0, 0, 0, 0.22), 4.2, true)
		draw_polyline(pts, Color(0.5, 0.52, 0.56), 2.6, true)
		draw_polyline(pts, Color(0.9, 0.92, 0.95, 0.75), 0.9, true)

	static func _arc(pts: PackedVector2Array, c: Vector2, r: float, from: float, to: float) -> void:
		for i in 13:
			var a := lerpf(from, to, i / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r)


## A dotted leader between a title and its page number.
class Leader:
	extends Control

	var color := Color(0, 0, 0, 0.5)
	var gap := 7.0
	var lift := 6.0

	func _draw() -> void:
		var x := fposmod(-global_position.x, gap)
		while x < size.x:
			draw_circle(Vector2(x, size.y - lift), 1.0, color)
			x += gap


## A ruled line: thick over thin (an engraver's rule), or a plain hairline.
class Rule:
	extends Control

	var color := Color(0, 0, 0, 0.6)
	var double := true

	func _draw() -> void:
		if double:
			draw_rect(Rect2(0, size.y * 0.5 - 2.5, size.x, 2.0), color)
			draw_rect(Rect2(0, size.y * 0.5 + 1.0, size.x, 0.8), color)
		else:
			draw_rect(Rect2(0, size.y * 0.5, size.x, 1.0), color)


## The Host's seal: the Earth drawn as a globe in a ring of lettering.
class Seal:
	extends Control

	var color := Color(0.64, 0.2, 0.11)
	var text := "THE LAST COMMAND  •  THE ARMY OF EARTH  •  "
	var font: Font

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_arc(c, r, 0, TAU, 96, color, 2.2, true)
		draw_arc(c, r - 5.0, 0, TAU, 96, color, 0.9, true)
		draw_arc(c, r * 0.62, 0, TAU, 96, color, 1.6, true)
		var g := r * 0.5
		draw_arc(c, g, 0, TAU, 72, color, 1.4, true)
		for k in [-2, -1, 0, 1, 2]:
			var w := g * cos(asin(clampf(float(k) / 3.0, -1.0, 1.0)))
			var y := c.y + g * float(k) / 3.0
			draw_line(Vector2(c.x - w, y), Vector2(c.x + w, y), color, 1.0, true)
		for k in [0.25, 0.6, 1.0]:
			_ellipse(c, g * k, g, color)
		if font == null:
			return
		var fs := int(r * 0.16)
		var n := text.length()
		for i in n:
			var a := -PI * 0.5 + TAU * float(i) / n
			var p := c + Vector2(cos(a), sin(a)) * (r * 0.81)
			draw_set_transform(p, a + PI * 0.5, Vector2.ONE)
			var ch := text[i]
			var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(-w * 0.5, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, col, 1.0, true)


## The Keep's insignia, as stencilled on its forms: the mountain with its gate, under three bars, in a shield.
class Insignia:
	extends Control

	var color := Color(0.7, 0.15, 0.11)
	var paper := Color.WHITE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var shield := PackedVector2Array([Vector2(w * 0.08, 0), Vector2(w * 0.92, 0), Vector2(w * 0.92, h * 0.62),
				Vector2(w * 0.5, h), Vector2(w * 0.08, h * 0.62), Vector2(w * 0.08, 0)])
		draw_polyline(shield, color, 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.2, h * 0.66), Vector2(w * 0.5, h * 0.25),
				Vector2(w * 0.8, h * 0.66)]), color)
		for k in 3:
			draw_rect(Rect2(w * 0.24, h * (0.08 + k * 0.045), w * 0.52, h * 0.022), color)
		# The gate, cut out of the mountain.
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.45, h * 0.66), Vector2(w * 0.45, h * 0.56),
				Vector2(w * 0.5, h * 0.52), Vector2(w * 0.55, h * 0.56), Vector2(w * 0.55, h * 0.66)]), paper)


## A rubber stamp: a ruled box round its words, in one colour; give it an INK material to press it.
class Stamp:
	extends Control

	var text := ""
	var color := Color(0.64, 0.2, 0.11)
	var font: Font
	var font_size := 28

	func _draw() -> void:
		if font == null:
			return
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var r := Rect2(Vector2.ZERO, ts + Vector2(28, 14))
		draw_rect(r, color, false, 3.0)
		draw_rect(r.grow(-5), color, false, 1.2)
		draw_string(font, Vector2(14, 7 + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func box_size() -> Vector2:
		if font == null:
			return Vector2.ZERO
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(28, 14)


## A pencil or grease-pencil stroke: a wobbly line through `points`.
class Stroke:
	extends Control

	var points := PackedVector2Array()
	var color := Color(0.3, 0.3, 0.33, 0.8)
	var width := 2.0
	var seed := 0.0

	func _draw() -> void:
		if points.size() < 2:
			return
		var pts := PackedVector2Array()
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var n := maxi(2, int(a.distance_to(b) / 6.0))
			for k in n:
				var t := float(k) / n
				var wob := sin(t * 9.0 + seed + i * 3.1) * 0.9 + sin(t * 23.0 + seed * 2.0) * 0.4
				pts.append(a.lerp(b, t) + (b - a).orthogonal().normalized() * wob)
		pts.append(points[points.size() - 1])
		draw_polyline(pts, color, width, true)
		draw_polyline(pts, Color(color, color.a * 0.35), width * 2.2, true)


## Three binder rings across the spine of the Keep's orders, on their steel plate, and the holes they go through.
class Rings:
	extends Control

	func _draw() -> void:
		var cx := size.x * 0.5
		draw_rect(Rect2(cx - 9.0, 14.0, 18.0, size.y - 28.0), Color(0.2, 0.21, 0.23))
		draw_rect(Rect2(cx - 9.0, 14.0, 4.0, size.y - 28.0), Color(0.42, 0.44, 0.47))
		draw_rect(Rect2(cx + 6.0, 14.0, 3.0, size.y - 28.0), Color(0.08, 0.08, 0.09))
		for k in 3:
			var y := size.y * (0.16 + 0.34 * k)
			draw_circle(Vector2(cx, y + 24.0), 2.6, Color(0.55, 0.57, 0.6))
			draw_circle(Vector2(cx, y - 24.0), 2.6, Color(0.55, 0.57, 0.6))
			for side in [-1.0, 1.0]:
				var hc := Vector2(cx + side * 30.0, y)
				draw_circle(hc, 8.5, Color(0.08, 0.09, 0.1))
				draw_arc(hc, 8.5, PI * 0.9, PI * 2.1, 16, Color(0, 0, 0, 0.5), 2.0, true)
			var rr := Rect2(cx - 38.0, y - 17.0, 76.0, 34.0)
			_ring(rr, Color(0.06, 0.07, 0.08, 0.6), 9.0, 0.0)
			_ring(rr, Color(0.5, 0.52, 0.55), 6.0, 0.0)
			_ring(rr.grow(-1.5), Color(0.93, 0.95, 0.97, 0.9), 1.4, -0.6)

	func _ring(r: Rect2, c: Color, w: float, lift: float) -> void:
		var pts := PackedVector2Array()
		for i in 41:
			var a := PI + PI * i / 40.0
			pts.append(r.get_center() + Vector2(cos(a) * r.size.x * 0.5, sin(a) * r.size.y * 0.5 + lift))
		draw_polyline(pts, c, w, true)


## The edges of the pages under the open ones: slivers down the outer sides and along the bottom, more of them
## on the side with more pages left to read. Drawn behind the two open pages.
class PageEdges:
	extends Control

	var paper := Color.WHITE
	var left_pages := 4
	var right_pages := 4
	var page := Vector2(720, 820)

	func _draw() -> void:
		for side in [0, 1]:
			var n: int = left_pages if side == 0 else right_pages
			for i in range(n, 0, -1):
				var d := float(i) * 1.5
				var c := paper.darkened(0.07 + 0.04 * (i % 2) + 0.015 * i)
				if side == 0:
					draw_rect(Rect2(-d, d * 0.5, page.x + d - 40.0, page.y), c)
				else:
					draw_rect(Rect2(page.x + 40.0, d * 0.5, page.x + d - 40.0, page.y), c)


## A ribbon bookmark hanging out of the bottom of the spine.
class Ribbon:
	extends Control

	var color := Color(0.5, 0.12, 0.08)

	func _draw() -> void:
		var w := size.x
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w + 2, size.y), Vector2(w * 0.5 + 1, size.y - 9),
				Vector2(1, size.y + 1)])
		draw_colored_polygon(pts, color)
		draw_line(Vector2(w * 0.3, 0), Vector2(w * 0.32, size.y - 6), Color(1, 1, 1, 0.12), 1.0, true)
		draw_line(Vector2(w, 0), Vector2(w + 2, size.y), Color(0, 0, 0, 0.25), 1.0, true)


## The corner of a page curling up under the pointer: a hint that it turns.
class DogEar:
	extends Control

	var paper := Color.WHITE
	var right := true
	var amount := 0.0

	func _draw() -> void:
		if amount <= 0.01:
			return
		var s := 46.0 * amount
		var c := Vector2(size.x, size.y) if right else Vector2(0, size.y)
		var dx := -1.0 if right else 1.0
		var flap := PackedVector2Array([c + Vector2(dx * s, 0), c + Vector2(0, -s), c + Vector2(dx * s, -s)])
		var under := PackedVector2Array([c + Vector2(dx * s, 0), c, c + Vector2(0, -s)])
		draw_colored_polygon(under, Color(0, 0, 0, 0.55 * amount))
		draw_colored_polygon(flap, paper.darkened(0.08))
		draw_line(c + Vector2(dx * s, 0), c + Vector2(0, -s), Color(0, 0, 0, 0.3 * amount), 1.2, true)
