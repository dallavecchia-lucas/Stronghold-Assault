class_name GroundMaterial
extends RefCounted
## The ground's material on both maps: photoscanned ground (CC0, Poly Haven: see README) laid where it belongs.
##
## Eight layers, each a colour, a normal map and its ambient occlusion, roughness and height, in three texture
## arrays (assets/textures/terrain, one slice a layer): jungle leaf litter, mossy mud and leaves, grass, dark
## grass, bare earth, wet mud, rock, river pebbles. Where a layer lies comes from the map (the jungle's splat:
## the clearing's grass, the banks, the quarry; the classic field's worn tracks up the attack lanes and the
## scree at the mountain's foot), from the slope (rock on the steep faces, projected from three sides so it
## never stretches), from the water (wet and glossy at its edge, pebbles and mud under it with the light's
## caustics playing over them) and from large-scale noise (moss, bare patches, dry and lush grass).
##
## Layers meet by their heights: the grass grows up between the stones and the mud fills the dips, rather than
## the two fading into each other. Every layer is sampled twice at offsets that change with a slow noise, so
## its tiles never repeat in rows; its normals are turned into the world's frame (each projection with its own
## right-handed frame) and added onto the ground's.

const ALBEDO := "res://assets/textures/terrain/terrain_albedo.jpg"
const NORMAL := "res://assets/textures/terrain/terrain_normal.jpg"
const ORH := "res://assets/textures/terrain/terrain_orh.jpg"
const CAUSTICS := "res://assets/textures/water/water_caustics.png"

enum { LITTER, MOSSY, GRASS, GRASS_DARK, DIRT, MUD, ROCK, PEBBLES }
## How many metres a layer's texture covers (about its real size, a little larger for the small ones).
const TILE := [3.2, 2.4, 2.4, 2.6, 3.4, 2.4, 4.5, 2.4]
## Each layer's colour (times its photo, linear) and how strong its normal map is (alpha).
const JUNGLE_TINT := [
	Color(0.86, 0.84, 0.78, 1.0), Color(0.92, 1.0, 0.86, 1.0), Color(0.72, 0.95, 0.6, 1.0), Color(0.95, 1.12, 0.85, 1.0),
	Color(0.92, 0.88, 0.84, 1.1), Color(0.85, 0.82, 0.78, 1.0), Color(0.88, 0.87, 0.85, 1.35), Color(0.82, 0.82, 0.8, 1.2),
]
const CLASSIC_TINT := [
	Color(0.9, 0.88, 0.82, 1.0), Color(0.95, 1.0, 0.88, 1.0), Color(0.88, 1.0, 0.72, 1.0), Color(1.0, 1.08, 0.86, 1.0),
	Color(1.0, 0.95, 0.9, 1.1), Color(0.9, 0.86, 0.8, 1.0), Color(0.95, 0.92, 0.88, 1.35), Color(0.9, 0.88, 0.85, 1.2),
]

const SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray layer_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_orh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D caustics : filter_linear_mipmap, repeat_enable;
uniform sampler2D splat : filter_linear, repeat_disable;
// 0: the Jungle Keep (its splat), 1: the classic field (its tracks and the mountain's foot).
uniform int map_kind = 0;
uniform vec2 map_origin = vec2(0.0);
uniform float map_size = 1.0;
uniform float water_y = -10000.0;
uniform float tile[8];
uniform vec4 tint[8];
// The classic field's worn tracks (from xz, to xz) and the mountain's half width.
uniform vec4 lanes[4];
uniform int lane_count = 0;
uniform float mountain_half = 0.0;
// How far apart (in height) two layers blend: smaller, crisper.
uniform float blend_depth = 0.16;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// A layer sampled at `uv` (its tile's units) without its tiles showing: two samples at offsets picked by a
// slow noise `k`, crossfaded where the noise moves between them. Returns its colour (rgb) and height (a);
// `nrm` its normal (xy, -1..1) and `ar` its ambient occlusion and roughness.
vec4 layer(int i, vec2 uv, vec2 dx, vec2 dy, float k, out vec2 nrm, out vec2 ar) {
	float l = k * 8.0;
	float ia = floor(l);
	float f = fract(l);
	vec3 a = vec3(uv + sin(vec2(3.0, 7.0) * ia), float(i));
	vec3 b = vec3(uv + sin(vec2(3.0, 7.0) * (ia + 1.0)), float(i));
	vec3 ca = textureGrad(layer_albedo, a, dx, dy).rgb;
	vec3 cb = textureGrad(layer_albedo, b, dx, dy).rgb;
	float t = smoothstep(0.2, 0.8, f - 0.1 * dot(ca - cb, vec3(1.0)));
	vec3 oa = textureGrad(layer_orh, a, dx, dy).rgb;
	vec3 ob = textureGrad(layer_orh, b, dx, dy).rgb;
	vec2 na = textureGrad(layer_normal, a, dx, dy).rg;
	vec2 nb = textureGrad(layer_normal, b, dx, dy).rg;
	nrm = mix(na, nb, t) * 2.0 - 1.0;
	vec3 o = mix(oa, ob, t);
	ar = o.rg;
	return vec4(mix(ca, cb, t) * tint[i].rgb, o.b);
}

float lane_distance(vec2 p) {
	float d = 1e9;
	for (int i = 0; i < 4; i++) {
		if (i >= lane_count) {
			break;
		}
		vec2 a = lanes[i].xy;
		vec2 b = lanes[i].zw;
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
		d = min(d, length(p - (a + ab * t)));
	}
	return d;
}

void fragment() {
	vec3 N = normalize(wnrm);
	float slope = 1.0 - clamp(N.y, 0.0, 1.0);
	float m1 = texture(macro_noise, wpos.xz * 0.0035).r;
	float m2 = texture(macro_noise, wpos.xz * 0.016 + vec2(0.37, 0.11)).r;
	float m3 = texture(macro_noise, wpos.xz * 0.07 + vec2(0.71, 0.53)).r;
	float above = wpos.y - water_y;

	// Where each layer lies.
	float w[8];
	for (int i = 0; i < 8; i++) {
		w[i] = 0.0;
	}
	if (map_kind == 0) {
		vec4 s = texture(splat, (wpos.xz - map_origin) / map_size);
		float moss = smoothstep(0.42, 0.62, m2 * 0.7 + m3 * 0.3);
		w[0] = 1.0 - moss;
		w[1] = moss;
		// The clearing: grass, lusher in some patches, worn to bare earth in others.
		float g = s.g;
		float bare = smoothstep(0.62, 0.74, m1 * 0.55 + m3 * 0.45) * 0.85;
		w[2] = g * (1.0 - bare) * (1.0 - smoothstep(0.35, 0.65, m2));
		w[3] = g * (1.0 - bare) * smoothstep(0.35, 0.65, m2);
		w[4] = g * bare;
		w[0] *= 1.0 - g;
		w[1] *= 1.0 - g;
		// The banks: earth above the water, wet mud at its edge, pebbles and silt under it.
		float shore = s.r;
		float wetband = 1.0 - smoothstep(0.2, 1.6, above);
		for (int i = 0; i < 5; i++) {
			w[i] *= 1.0 - shore;
		}
		w[4] += shore * (1.0 - wetband) * 0.7;
		w[1] += shore * (1.0 - wetband) * 0.3;
		w[5] += shore * wetband;
		float under = 1.0 - smoothstep(-0.6, 0.1, above);
		float peb = smoothstep(0.4, 0.6, m3 * 0.6 + m2 * 0.4);
		w[5] = mix(w[5], 1.0 - peb, under);
		w[7] = mix(w[7], peb, under);
		// Rock on the steep faces and the quarry's benches.
		float rock = max(smoothstep(0.3, 0.48, slope), s.a * smoothstep(0.0, 0.12, slope + 0.04));
		for (int i = 0; i < 8; i++) {
			w[i] *= 1.0 - rock;
		}
		w[6] = rock;
	} else {
		// The classic field: grass, dry in big patches, worn into earth tracks up the attack lanes, scree at the
		// mountain's foot.
		float dry = smoothstep(0.4, 0.7, m1 * 0.7 + m2 * 0.3);
		w[2] = 1.0 - dry;
		w[3] = dry;
		float d = lane_distance(wpos.xz) + (m3 - 0.5) * 5.0 + (m2 - 0.5) * 6.0;
		float track = 1.0 - smoothstep(2.5, 7.5, d);
		float bare = smoothstep(0.66, 0.76, m1 * 0.5 + m3 * 0.5) * 0.8;
		float earth = max(track, bare);
		w[2] *= 1.0 - earth;
		w[3] *= 1.0 - earth;
		w[4] = earth;
		vec2 q = abs(wpos.xz) - vec2(mountain_half);
		float foot = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		float scree = (1.0 - smoothstep(1.0, 7.0, foot + (m3 - 0.5) * 4.0)) * step(0.0, mountain_half - 0.5);
		for (int i = 0; i < 5; i++) {
			w[i] *= 1.0 - scree;
		}
		w[7] = scree * 0.6;
		w[4] += scree * 0.4;
		float rock = smoothstep(0.3, 0.48, slope);
		for (int i = 0; i < 8; i++) {
			w[i] *= 1.0 - rock;
		}
		w[6] = rock;
	}

	// Sample the layers that are there (gradients worked out once, outside the branches).
	vec2 gx = dFdx(wpos.xz);
	vec2 gy = dFdy(wpos.xz);
	vec3 gpx = dFdx(wpos);
	vec3 gpy = dFdy(wpos);
	float k = m3;
	vec3 col[8];
	vec3 det[8];
	vec2 ars[8];
	float hb[8];
	float hmax = -1e9;
	for (int i = 0; i < 8; i++) {
		col[i] = vec3(0.0);
		det[i] = vec3(0.0);
		ars[i] = vec2(1.0);
		hb[i] = -1e9;
		if (w[i] > 0.004) {
			vec2 nrm;
			vec2 ar;
			vec4 c;
			if (i == 6 && slope > 0.12) {
				// Rock on a slope: projected from the three axes (each with a right-handed frame), blended by
				// how squarely the ground faces each.
				vec3 bw = pow(abs(N), vec3(4.0));
				bw /= bw.x + bw.y + bw.z;
				float sx = N.x >= 0.0 ? 1.0 : -1.0;
				float sy = N.y >= 0.0 ? 1.0 : -1.0;
				float sz = N.z >= 0.0 ? 1.0 : -1.0;
				float t = 1.0 / tile[i];
				vec2 n1;
				vec2 a1;
				vec4 c1 = layer(i, vec2(-sx * wpos.z, -wpos.y) * t, vec2(-sx * gpx.z, -gpx.y) * t, vec2(-sx * gpy.z, -gpy.y) * t, k, n1, a1);
				vec2 n2;
				vec2 a2;
				vec4 c2 = layer(i, vec2(wpos.x, sy * wpos.z) * t, vec2(gpx.x, sy * gpx.z) * t, vec2(gpy.x, sy * gpy.z) * t, k, n2, a2);
				vec2 n3;
				vec2 a3;
				vec4 c3 = layer(i, vec2(sz * wpos.x, -wpos.y) * t, vec2(sz * gpx.x, -gpx.y) * t, vec2(sz * gpy.x, -gpy.y) * t, k, n3, a3);
				c = c1 * bw.x + c2 * bw.y + c3 * bw.z;
				ar = a1 * bw.x + a2 * bw.y + a3 * bw.z;
				det[i] = (vec3(0.0, 0.0, -sx) * n1.x + vec3(0.0, 1.0, 0.0) * n1.y) * bw.x
						+ (vec3(1.0, 0.0, 0.0) * n2.x + vec3(0.0, 0.0, -sy) * n2.y) * bw.y
						+ (vec3(sz, 0.0, 0.0) * n3.x + vec3(0.0, 1.0, 0.0) * n3.y) * bw.z;
			} else {
				float t = 1.0 / tile[i];
				c = layer(i, wpos.xz * t, gx * t, gy * t, k, nrm, ar);
				// On the ground the texture's right is +x and its up is -z.
				det[i] = vec3(1.0, 0.0, 0.0) * nrm.x + vec3(0.0, 0.0, -1.0) * nrm.y;
			}
			col[i] = c.rgb;
			ars[i] = ar;
			hb[i] = c.a + w[i] * 1.6;
			hmax = max(hmax, hb[i]);
		}
	}
	// Blend by height: the layer standing highest (by its height and how much of it there is) shows.
	vec3 albedo = vec3(0.0);
	vec3 detail = vec3(0.0);
	vec2 ar_sum = vec2(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 8; i++) {
		float b = max(hb[i] - (hmax - blend_depth), 0.0);
		albedo += col[i] * b;
		detail += det[i] * b * tint[i].a;
		ar_sum += ars[i] * b;
		wsum += b;
	}
	albedo /= max(wsum, 0.0001);
	detail /= max(wsum, 0.0001);
	ar_sum /= max(wsum, 0.0001);

	// Large-scale variation: no two stretches of ground quite the same shade.
	albedo *= mix(0.82, 1.12, m1) * mix(0.93, 1.05, m2);
	float rough = ar_sum.y;
	float ao = ar_sum.x;
	// The water's edge: soaked dark and glossy, the light's caustics on the bed under it.
	float wet = 1.0 - smoothstep(0.0, 1.3, above);
	albedo *= 1.0 - wet * 0.42;
	rough = mix(rough, 0.12, wet * 0.85);
	if (above < 0.0) {
		vec2 cuv = wpos.xz * 0.33;
		float c1 = texture(caustics, cuv + vec2(TIME * 0.031, TIME * 0.017)).r;
		float c2 = texture(caustics, cuv * 1.27 + vec2(-TIME * 0.023, TIME * 0.029) + vec2(0.37, 0.61)).r;
		float caus = min(c1, c2) * exp(above * 0.45);
		albedo *= 1.0 + caus * 2.2;
		detail *= 0.5;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	AO = mix(1.0, ao, 0.85);
	AO_LIGHT_AFFECT = 0.25;
	vec3 n = normalize(N + detail * (1.0 - wet * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
"""

static var _shader: Shader
static var _noise: NoiseTexture2D


## The Jungle Keep's ground: laid out by its `splat` (r the banks, g the clearing's grass, a the quarry's rock)
## over the square at `origin` `size` m across; the water's surface at `water_y`.
static func jungle(splat: Texture2D, origin: Vector2, size: float, water_y: float) -> ShaderMaterial:
	var m := _base(JUNGLE_TINT)
	m.set_shader_parameter("map_kind", 0)
	m.set_shader_parameter("splat", splat)
	m.set_shader_parameter("map_origin", origin)
	m.set_shader_parameter("map_size", size)
	m.set_shader_parameter("water_y", water_y)
	return m


## The classic field's ground: tracks worn up the `lanes` ([from, to] Vector3s, up to four) and scree round the
## foot of the mountain (`mountain_half` m from the middle to its foot).
static func classic(lanes: Array, mountain_half: float) -> ShaderMaterial:
	var m := _base(CLASSIC_TINT)
	m.set_shader_parameter("map_kind", 1)
	var packed: Array[Vector4] = []
	for l in lanes.slice(0, 4):
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		packed.append(Vector4(a.x, a.z, b.x, b.z))
	while packed.size() < 4:
		packed.append(Vector4.ZERO)
	m.set_shader_parameter("lanes", packed)
	m.set_shader_parameter("lane_count", mini(lanes.size(), 4))
	m.set_shader_parameter("mountain_half", mountain_half)
	return m


static func _base(tints: Array) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("layer_albedo", load(ALBEDO))
	m.set_shader_parameter("layer_normal", load(NORMAL))
	m.set_shader_parameter("layer_orh", load(ORH))
	m.set_shader_parameter("caustics", load(CAUSTICS))
	m.set_shader_parameter("macro_noise", macro_noise())
	m.set_shader_parameter("tile", PackedFloat32Array(TILE))
	var t := PackedColorArray()
	for c in tints:
		t.append(c)
	m.set_shader_parameter("tint", t)
	return m


## A slow, tiling noise for the ground's large-scale variation (and the stronghold's).
static func macro_noise() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = 5150
		n.frequency = 0.01
		n.fractal_octaves = 5
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		_noise.noise = n
	return _noise
