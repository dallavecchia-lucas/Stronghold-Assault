class_name FX
extends Node3D
## The scene's visual effects: explosions, muzzle flashes and blasts, bullet impacts, tracers, flak, fire
## and smoke, the lights they throw, the scorch marks they leave and the camera shake.
##
## Particles live in a few MultiMeshes, one draw call each, and move on the GPU: a particle is written
## once, when it is spawned (where, how fast, when, how long it lives, how it grows), and the vertex
## shader works out where it is from its age: launched, dragged toward the wind and pulled by gravity or
## lifted by its heat, all in closed form. Thousands cost the CPU nothing from frame to frame. Each layer
## is a ring: once it is full the oldest particle is reused.
##   SMOKE  billowing puffs, lit: the sun, the sky and the blasts' lights fall on them, they glow from the
##          fire inside for their first moments, and they fade softly where they meet the ground
##   FIRE   fireballs and flames: white-hot through yellow and orange to dull red as they cool, turning to
##          soot (premultiplied: glowing and sooty at once)
##   SPARK  streaks stretched along their motion: sparks, embers, shrapnel, tracers, the flame out of a muzzle
##   FLARE  glows and star-shaped flashes that bloom
##   WARP   heat haze and shock waves bending the scene behind them (Forward+ and Mobile)
## Besides those: chunks of debris flung out on arcs trailing smoke and fire (moved here, there are few),
## pooled flickering lights, scorch marks burnt into the ground, and the camera shake.
##
## FX.of(node) is the scene's (made on first use; Match makes it as the level loads, so its shaders are
## compiled before the first shot).

enum { SMOKE, FIRE, SPARK, FLARE, WARP }
## Particles each layer holds.
const CAPS := [6144, 3072, 3072, 512, 96]
## The order the layers are drawn in (Material.render_priority): the warp first, as it bends the opaque scene
## copied behind it, then the smoke, the fire glowing through it, the sparks and the flares on top.
const PRIORITY := [2, 3, 4, 5, 1]
const MAX_LIGHTS := 16
## Lights casting shadows at once (the biggest blasts').
const MAX_SHADOWED := 2
const MAX_DEBRIS := 128
const MAX_SCORCH := 48
## How long a scorch mark stays (s), the last SCORCH_FADE of it fading out.
const SCORCH_LIFE := 45.0
const SCORCH_FADE := 10.0
## The wind the smoke drifts on (m/s).
const WIND := Vector3(0.55, 0.0, 0.25)
## A spark with no ground under it (fits the GLES3 renderer's half floats).
const NO_FLOOR := -60000.0
## Where particles can be: the layers are never culled.
const WORLD_AABB := AABB(Vector3(-6000, -1000, -6000), Vector3(12000, 4000, 12000))
## The heat colours: a fire puff's colour as it cools.
const FIRE_GLOW := Color(1.0, 0.42, 0.13)

## Shared by every layer: the clock, the wind, the noise the puffs are broken up with, and the motion.
const SIM := """
uniform float fx_time = 0.0;
uniform vec3 fx_wind = vec3(0.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float fx_hash(vec3 p) {
	vec3 q = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419)) * 17.0;
	return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

// Where a particle is `a` seconds after it was launched from p0 at v0: pulled up or down at `ay` (m/s2),
// dragged toward the wind at rate k (1/s).
vec3 fx_pos(vec3 p0, vec3 v0, float ay, float k, float a) {
	vec3 acc = vec3(0.0, ay, 0.0);
	if (k < 0.02) {
		return p0 + v0 * a + 0.5 * acc * a * a;
	}
	vec3 term = acc / k + fx_wind;
	return p0 + term * a + (v0 - term) * (1.0 - exp(-k * a)) / k;
}

vec3 fx_vel(vec3 v0, float ay, float k, float a) {
	vec3 acc = vec3(0.0, ay, 0.0);
	if (k < 0.02) {
		return v0 + acc * a;
	}
	vec3 term = acc / k + fx_wind;
	return term + (v0 - term) * exp(-k * a);
}

// A camera-facing quad's corner `q` round view-space point `vp`, drawn `pull` metres nearer the camera
// along its line of sight (its size and place on screen kept) so the ground doesn't cut it in half.
vec3 fx_billboard(vec3 vp, vec2 q, float pull) {
	float d = length(vp);
	float f = max(d - pull, min(d, 0.4)) / max(d, 0.0001);
	return (vp + vec3(q, 0.0)) * f;
}

// How far into the scene the opaque surface behind this pixel is (m).
float fx_scene_depth(float depth, vec2 screen_uv, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}
"""

## Per particle (a MultiMesh instance's transform, read back in the shader as columns):
##   MODEL_MATRIX[0] = (vel.x, birth time, vertical pull)   [1] = (vel.y, life, size at birth)
##   MODEL_MATRIX[2] = (vel.z, drag, size at death)          [3] = where it was launched
## and its colour and custom data, which each layer reads its own way.
const UNPACK := """
	vec3 A = MODEL_MATRIX[0].xyz;
	vec3 B = MODEL_MATRIX[1].xyz;
	vec3 C = MODEL_MATRIX[2].xyz;
	vec3 P0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = vec3(A.x, B.x, C.x);
	float age = fx_time - A.y;
	float u = age / max(B.y, 0.0001);
	bool alive = B.y > 0.0 && age >= 0.0 && u < 1.0;
"""

## Smoke: colour = albedo and opacity; custom = (spin, how much it pales as it thins, fire glow, -).
const SMOKE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float softness = 1.6;
varying vec4 v_col;
varying vec4 v_data;
varying vec2 v_rot;
varying vec2 v_q;
varying float v_pale;
varying float v_size;
void vertex() {
	%UNPACK%
	v_q = VERTEX.xy * 2.0;
	if (!alive) {
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		float seed = fx_hash(P0 + vec3(A.y * 1.37));
		vec3 wp = fx_pos(P0, v0, A.z, C.y, age);
		float s = mix(B.z, C.z, 1.0 - pow(1.0 - u, 2.2));
		float ang = seed * 6.2831853 + INSTANCE_CUSTOM.x * age;
		vec2 cs = vec2(cos(ang), sin(ang));
		vec2 q = VERTEX.xy * s;
		q = vec2(q.x * cs.x - q.y * cs.y, q.x * cs.y + q.y * cs.x);
		VERTEX = fx_billboard((VIEW_MATRIX * vec4(wp, 1.0)).xyz, q, s * 0.3);
		v_rot = cs;
		v_data = vec4(u, seed, age, INSTANCE_CUSTOM.z);
		v_col = COLOR;
		v_pale = INSTANCE_CUSTOM.y;
		v_size = s;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	vec2 p = v_q;
	float r2 = dot(p, p);
	float u = v_data.x;
	float seed = v_data.y;
	vec2 nuv = p * 0.21 + vec2(seed * 5.31, seed * 2.17) + vec2(0.0, -u * 0.12);
	float n1 = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, nuv * 2.6 + vec2(0.31, 0.77)).r;
	float n = n1 * 0.62 + n2 * 0.38;
	// A ball broken up by the noise, eaten away as it ages.
	float dens = (1.0 - sqrt(r2)) * 1.35 + (n - 0.5) * 1.5 - u * 0.25;
	float fade = smoothstep(0.0, 0.05, u) * (1.0 - smoothstep(0.35, 1.0, u));
	float alpha = smoothstep(0.0, 0.5, dens) * fade * v_col.a;
	float scene = fx_scene_depth(texture(depth_tex, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX);
	alpha *= clamp((scene + VERTEX.z) / clamp(v_size * 0.35, 0.05, softness), 0.0, 1.0);
	ALPHA = clamp(alpha, 0.0, 1.0);
	// Billows: a ball's normal bumped by the noise, turned with the puff, so the light models it.
	float gx = texture(noise_tex, nuv + vec2(0.02, 0.0)).r - n1;
	float gy = texture(noise_tex, nuv + vec2(0.0, 0.02)).r - n1;
	vec2 nxy = p * 0.8 - vec2(gx, gy) * 14.0;
	nxy = vec2(nxy.x * v_rot.x - nxy.y * v_rot.y, nxy.x * v_rot.y + nxy.y * v_rot.x);
	NORMAL = normalize(vec3(nxy, sqrt(max(1.0 - r2, 0.0)) + 0.25));
	vec3 alb = v_col.rgb * (0.8 + 0.4 * n);
	ALBEDO = mix(alb, alb * 1.9 + vec3(0.04), clamp(u * v_pale, 0.0, 1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Lit from inside by the fire for its first moments.
	EMISSION = vec3(1.0, 0.36, 0.08) * v_data.w * exp(-v_data.z * 3.2) * smoothstep(0.15, 0.9, dens);
}
void light() {
	// Light wraps round a puff, and shines through its edges when it is behind it.
	float wrap = max((dot(NORMAL, LIGHT) + 0.55) / 1.55, 0.0);
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 8.0) * 0.5;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (wrap + back) / PI;
}
"""

## Fire: colour = tint (times the heat colour) and the heat at birth (1: white-hot); custom = (spin, soot, -, -).
const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float softness = 0.8;
varying vec4 v_col;
varying vec4 v_data;
varying vec2 v_q;
varying float v_size;
// Glowing matter's colour as it cools (HDR: the hot core blooms).
vec3 blackbody(float h) {
	vec3 c = vec3(0.45, 0.04, 0.005) * smoothstep(0.0, 0.18, h);
	c = mix(c, vec3(1.5, 0.36, 0.05), smoothstep(0.12, 0.42, h));
	c = mix(c, vec3(3.0, 1.35, 0.3), smoothstep(0.38, 0.7, h));
	return mix(c, vec3(4.8, 3.6, 2.2), smoothstep(0.66, 1.0, h));
}
void vertex() {
	%UNPACK%
	v_q = VERTEX.xy * 2.0;
	if (!alive) {
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		float seed = fx_hash(P0 + vec3(A.y * 1.37));
		vec3 wp = fx_pos(P0, v0, A.z, C.y, age);
		float s = mix(B.z, C.z, 1.0 - pow(1.0 - u, 2.0));
		float ang = seed * 6.2831853 + INSTANCE_CUSTOM.x * age;
		vec2 cs = vec2(cos(ang), sin(ang));
		vec2 q = VERTEX.xy * s;
		q = vec2(q.x * cs.x - q.y * cs.y, q.x * cs.y + q.y * cs.x);
		VERTEX = fx_billboard((VIEW_MATRIX * vec4(wp, 1.0)).xyz, q, s * 0.4);
		v_data = vec4(u, seed, age, INSTANCE_CUSTOM.y);
		v_col = COLOR;
		v_size = s;
	}
}
void fragment() {
	vec2 p = v_q;
	float r = length(p);
	float u = v_data.x;
	float seed = v_data.y;
	float age = v_data.z;
	// Licks of flame: the noise rolls up through the puff.
	vec2 nuv = p * 0.25 + vec2(seed * 3.7, seed * 1.9);
	float n1 = texture(noise_tex, nuv - vec2(0.0, age * 0.45)).r;
	float n2 = texture(noise_tex, nuv * 2.4 + vec2(0.5, -age * 1.1)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float dens = (1.0 - r) * 1.55 + (n - 0.5) * 1.9 - u * 0.75;
	float mask = smoothstep(0.0, 0.3, dens);
	// Hottest in its dense core, cooling as it ages; what has cooled goes to soot.
	float heat = v_col.a * pow(1.0 - u, 1.25) * (0.5 + 0.85 * clamp(dens, 0.0, 1.0));
	float soot = v_data.w * smoothstep(0.3, 0.95, u) * (1.0 - smoothstep(0.25, 0.55, heat));
	float a = mask * (1.0 - smoothstep(0.82, 1.0, u));
	float scene = fx_scene_depth(texture(depth_tex, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX);
	a *= clamp((scene + VERTEX.z) / clamp(v_size * 0.3, 0.05, softness), 0.0, 1.0);
	vec3 fire = blackbody(heat) * v_col.rgb;
	ALBEDO = (fire * (1.0 - soot) + vec3(0.035, 0.03, 0.027) * soot) * a;
	ALPHA = clamp(a * (soot * 0.85 + clamp(heat, 0.0, 1.0) * 0.45), 0.0, 1.0);
}
"""

## Sparks: colour = HDR colour; custom = (the ground it stops on, shape: 0 spark, 1 flame tongue, 2 tracer,
## seconds of motion it is smeared over, how far it cools to red). Its sizes are its width and least length.
const SPARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
varying vec4 v_col;
varying vec4 v_data;
varying vec2 v_q;
varying float v_dim;
void vertex() {
	%UNPACK%
	v_q = vec2(VERTEX.x * 2.0, VERTEX.y + 0.5);
	if (!alive) {
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		vec3 wp = fx_pos(P0, v0, A.z, C.y, age);
		vec3 vel = fx_vel(v0, A.z, C.y, age);
		// Down on the ground it lies there, sliding to a stop.
		if (wp.y < INSTANCE_CUSTOM.x) {
			wp.y = INSTANCE_CUSTOM.x;
			vel.y = 0.0;
		}
		vec3 vp = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
		vec3 vv = (VIEW_MATRIX * vec4(vel, 0.0)).xyz;
		float speed = length(vv);
		// Smeared back along its motion, never further back than where it came from.
		float len = min(C.z + speed * INSTANCE_CUSTOM.z, length(v0) * age + B.z);
		vec3 dir = speed > 0.001 ? vv / speed : vec3(0.0, 1.0, 0.0);
		vec3 side = cross(dir, normalize(vp));
		float sl = length(side);
		side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
		// At least a pixel wide however far off, dimmer for it.
		float px = 2.0 * max(-vp.z, 0.05) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
		float w = max(B.z, px * 1.25);
		v_dim = B.z / w;
		VERTEX = vp + side * VERTEX.x * w + dir * (VERTEX.y - 0.5) * len;
		v_col = COLOR;
		v_data = vec4(u, INSTANCE_CUSTOM.y, fx_hash(P0 + vec3(A.y * 1.37)), INSTANCE_CUSTOM.w);
	}
}
void fragment() {
	float x = v_q.x;
	float t = v_q.y;
	float u = v_data.x;
	int shape = int(v_data.y + 0.5);
	vec3 col = v_col.rgb;
	float I;
	if (shape == 1) {
		// A tongue of flame: fat in its middle, ragged at its edges.
		float prof = sqrt(max(sin(3.14159 * t), 0.0)) * (0.55 + 0.45 * t);
		float n = texture(noise_tex, vec2(x * 0.15 + v_data.z, t * 0.35 - u * 0.8)).r;
		I = smoothstep(1.0, 0.25, abs(x) / max(prof, 0.001) + (n - 0.5) * 0.9) * (0.6 + 0.4 * t);
	} else {
		// A hot head and a fading tail.
		float core = max(1.0 - x * x, 0.0);
		I = pow(core, 3.0) * pow(t, 1.6) + pow(core, 14.0) * t * 0.6;
		if (shape == 2) {
			float head = smoothstep(0.78, 1.0, t) * pow(core, 6.0);
			col = mix(col, vec3(max(col.r, max(col.g, col.b))), head * 0.7);
			I += head;
		}
	}
	col = mix(col, col * vec3(0.85, 0.32, 0.1), clamp(u * v_data.w, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(I * (1.0 - smoothstep(0.55, 1.0, u)) * v_dim, 0.0, 1.0);
}
"""

## Flares: colour = HDR colour; custom = (shape: 0 glow, 1 star, 2 ring, how fast it fades, its turn, -).
const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
varying vec4 v_col;
varying vec4 v_data;
varying vec2 v_q;
void vertex() {
	%UNPACK%
	v_q = VERTEX.xy * 2.0;
	if (!alive) {
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		vec3 wp = fx_pos(P0, v0, A.z, C.y, age);
		float s = mix(B.z, C.z, 1.0 - pow(1.0 - u, 3.0));
		vec2 cs = vec2(cos(INSTANCE_CUSTOM.z), sin(INSTANCE_CUSTOM.z));
		vec2 q = VERTEX.xy * s;
		q = vec2(q.x * cs.x - q.y * cs.y, q.x * cs.y + q.y * cs.x);
		VERTEX = fx_billboard((VIEW_MATRIX * vec4(wp, 1.0)).xyz, q, s * 0.5);
		v_col = COLOR;
		v_data = vec4(u, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, 0.0);
	}
}
void fragment() {
	vec2 p = v_q;
	float r = length(p);
	int shape = int(v_data.y + 0.5);
	float g;
	if (shape == 1) {
		float a = atan(p.y, p.x);
		float rays = pow(abs(cos(a * 3.0)), 28.0) + 0.55 * pow(abs(cos(a * 2.0 + 0.8)), 50.0);
		g = rays * pow(max(1.0 - r, 0.0), 2.0) * 1.3 + exp(-r * r * 26.0) * 1.4;
	} else if (shape == 2) {
		g = exp(-pow((r - 0.8) / 0.08, 2.0)) * 0.9;
	} else {
		g = exp(-r * r * 6.5) * 0.75 + exp(-r * r * 38.0) * 1.2;
	}
	g *= 1.0 - smoothstep(0.88, 1.0, r);
	ALBEDO = v_col.rgb;
	ALPHA = clamp(g * pow(max(1.0 - v_data.x, 0.0), v_data.z), 0.0, 1.0);
}
"""

## Warp: custom = (mode: 0 shock bubble, 1 shock ring flat on the ground, 2 heat haze, strength, -, -).
const WARP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
varying vec4 v_data;
varying vec2 v_q;
varying float v_seed;
varying float v_scale;
void vertex() {
	%UNPACK%
	v_q = VERTEX.xy * 2.0;
	if (!alive) {
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		vec3 wp = fx_pos(P0, v0, A.z, C.y, age);
		float s = mix(B.z, C.z, 1.0 - pow(1.0 - u, 2.0));
		int mode = int(INSTANCE_CUSTOM.x + 0.5);
		vec3 vp = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
		if (mode == 1) {
			VERTEX = (VIEW_MATRIX * vec4(wp + vec3(VERTEX.x, 0.0, VERTEX.y) * s, 1.0)).xyz;
		} else {
			VERTEX = fx_billboard(vp, VERTEX.xy * s, s * 0.3);
		}
		// Bent as much as it looks big: a far blast's ring barely ripples the view.
		v_scale = clamp(s / max(-vp.z, 1.0), 0.0, 1.0);
		v_seed = fx_hash(P0 + vec3(A.y * 1.37));
		v_data = vec4(u, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, age);
	}
}
void fragment() {
	vec2 p = v_q;
	float r = length(p);
	float u = v_data.x;
	int mode = int(v_data.y + 0.5);
	float m;
	if (mode == 2) {
		m = (1.0 - smoothstep(0.2, 1.0, r)) * smoothstep(0.0, 0.15, u) * (1.0 - u);
	} else {
		m = exp(-pow((r - 0.78) / 0.13, 2.0)) * (1.0 - u) * (1.0 - smoothstep(0.92, 1.0, r));
	}
	vec2 nuv = p * 0.3 + vec2(v_seed * 4.1, v_seed * 2.3 - v_data.w * (mode == 2 ? 0.35 : 0.0));
	vec2 off = vec2(texture(noise_tex, nuv).r, texture(noise_tex, nuv + vec2(0.37, 0.61)).r) - 0.5;
	off *= v_data.z * m * v_scale;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = clamp(m * 4.0, 0.0, 1.0);
}
"""

## Debris: lit chunks, glowing while hot (instance colour: rgb its colour, alpha its heat).
const DEBRIS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying vec4 v_col;
void vertex() {
	v_col = COLOR;
}
void fragment() {
	ALBEDO = v_col.rgb;
	ROUGHNESS = 0.9;
	EMISSION = vec3(2.8, 0.9, 0.22) * v_col.a;
}
"""

static var _inst: FX = null
static var _noise: NoiseTexture2D
static var _shaders := {}
static var _scorch_albedo: ImageTexture
static var _scorch_glow: ImageTexture
static var _chunk_mesh: ArrayMesh

var _time := 0.0
var _mm: Array[MultiMesh] = []
var _mats: Array[ShaderMaterial] = []
var _next := PackedInt32Array([0, 0, 0, 0, 0])
## Forward+ and Mobile: the warp layer and shadowed lights; the Compatibility renderer does without.
var _rich := true
var _lights: Array = []  # of _Light
var _debris: Array = []  # of _Chunk
var _deb_mm: MultiMesh
var _deb_next := 0
var _scorch: Array = []  # [Decal, age]
var _trauma := 0.0
var _shake_dist := 30.0
var _shake_cam: Camera3D
var _shake_written := Vector2.ZERO
var _shake_applied := Vector2.ZERO
var _shake_noise := FastNoiseLite.new()


## The scene's FX (made on first use).
static func of(ctx: Node) -> FX:
	if _inst == null or not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = FX.new()
		_inst.name = "FX"
		var root := ctx.get_tree().current_scene
		(root if root else ctx.get_tree().root).add_child(_inst)
	return _inst


func _init() -> void:
	top_level = true
	_rich = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var codes := [SMOKE_SHADER, FIRE_SHADER, SPARK_SHADER, FLARE_SHADER, WARP_SHADER]
	for layer in CAPS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mm.mesh = quad
		mm.set("custom_aabb", WORLD_AABB)
		mm.instance_count = CAPS[layer]
		# Written one particle at a time from now on: the renderer keeps a copy here to patch (made now, at load,
		# rather than fetched back from the GPU at the first shot).
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))
		var mat := ShaderMaterial.new()
		mat.shader = _shader(codes[layer])
		mat.render_priority = PRIORITY[layer]
		mat.set_shader_parameter("noise_tex", noise_texture())
		var mi := MultiMeshInstance3D.new()
		mi.name = ["Smoke", "Fire", "Sparks", "Flares", "Warp"][layer]
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = WORLD_AABB
		mi.visible = layer != WARP or _rich
		add_child(mi)
		_mm.append(mm)
		_mats.append(mat)
	_mats[SMOKE].set_shader_parameter("fx_wind", WIND)
	_mats[FIRE].set_shader_parameter("fx_wind", WIND * 0.5)

	_deb_mm = MultiMesh.new()
	_deb_mm.transform_format = MultiMesh.TRANSFORM_3D
	_deb_mm.use_colors = true
	_deb_mm.mesh = _chunk()
	_deb_mm.set("custom_aabb", WORLD_AABB)
	_deb_mm.instance_count = MAX_DEBRIS
	_deb_mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	var dmat := ShaderMaterial.new()
	dmat.shader = _shader(DEBRIS_SHADER)
	var dmi := MultiMeshInstance3D.new()
	dmi.name = "Debris"
	dmi.multimesh = _deb_mm
	dmi.material_override = dmat
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.custom_aabb = WORLD_AABB
	add_child(dmi)

	_shake_noise.frequency = 0.5
	_shake_noise.seed = 4242
	# Made now rather than at the first blast's scorch mark (a hitch mid-fight).
	_scorch_texture(false)


func _exit_tree() -> void:
	_release_shake()


func _process(delta: float) -> void:
	_time += delta
	for m in _mats:
		m.set_shader_parameter("fx_time", _time)
	_update_lights(delta)
	_update_debris(delta)
	_update_scorch(delta)
	_update_shake(delta)


# ================================================================ the recipes

## A blast of `radius` (m) at `pos`: a flash and its light, a fireball rolling up into a column of smoke
## lit from inside, sparks, embers and burning debris trailing smoke, and the camera shaken. On (or just
## over) the ground it also throws dust out in a ring and dirt up in columns, ripples the air with its shock
## wave and leaves a scorch mark. `ground_y`: the ground's height under it (NAN: a ray looks for it); `air`:
## it went off in the air (an aircraft, a flak shell).
func blast(pos: Vector3, radius: float, ground_y := NAN, air := false, shake_camera := true) -> void:
	var r := maxf(radius, 0.3)
	# What flies out (sparks, debris) goes no faster than a heavy shell's, however big the blast.
	var rv := minf(r, 9.0)
	var gy := ground_y
	if is_nan(gy) and not air:
		gy = _ground_y(pos, r * 0.8 + 1.5)
	var grounded := not air and not is_nan(gy) and pos.y - gy < r * 0.6 + 0.6
	var floor_y := gy if not is_nan(gy) else NO_FLOOR
	var center := pos
	if grounded:
		center.y = maxf(pos.y, gy + r * 0.12)

	# The flash: a white-hot glow that blooms, a star of light, and the light it throws round.
	flare(center, Color(9.0, 7.0, 4.6), r * 1.3, r * 3.0, 0.09 + r * 0.012, 0, 2.5)
	flare(center, Color(5.0, 3.4, 1.8), r * 1.8, r * 4.0, 0.06 + r * 0.006, 1, 2.0)
	light(center + Vector3.UP * r * 0.35, Color(1.0, 0.86, 0.62), Color(1.0, 0.42, 0.12),
			minf(4.0 + r * 1.4, 30.0), r * 4.5 + 4.0, 0.45 + r * 0.16, minf(10.0 + r * 3.0, 60.0), 0.35, r >= 4.0)

	# The fireball: puffs flung out that stop fast, rise on their heat and cool from white through orange to soot.
	var n_fire := clampi(int(7 + r * 1.6), 7, 26)
	var fire_life := 0.75 + r * 0.045
	for i in n_fire:
		var d := _rand_dir(grounded)
		flame(center + d * r * randf_range(0.0, 0.2), d * r * randf_range(2.6, 5.2), randf_range(0.5, 0.95) * fire_life,
				r * randf_range(0.3, 0.5), r * randf_range(0.85, 1.3), r * 0.55 + 1.0, randf_range(3.6, 5.4),
				randf_range(0.95, 1.15), 0.55, randf_range(0.5, 0.85), randf_range(0.0, 0.05))
	# Tongues of flame licking up out of it a moment later.
	for i in n_fire >> 1:
		var d := _rand_dir(true)
		flame(center + d * r * randf_range(0.2, 0.6), d * r * randf_range(0.8, 2.0) + Vector3.UP * r * 0.8,
				randf_range(0.3, 0.6) * fire_life, r * 0.15, r * randf_range(0.35, 0.6), r * 0.8, 2.5,
				randf_range(0.7, 0.95), 0.5, 0.6, randf_range(0.05, 0.25))

	# The smoke: dark, swelling out of the fireball, glowing from the fire inside at first, then rising on the wind.
	var n_smoke := clampi(int(8 + r * 2.4), 8, 36)
	var smoke_life := minf(0.85 + r * 0.06, 6.0)
	for i in n_smoke:
		var d := _rand_dir(grounded)
		var tone := randf_range(0.035, 0.09)
		smoke(center + d * r * randf_range(0.0, 0.35), d * r * randf_range(1.0, 2.8) + Vector3.UP * r * randf_range(0.3, 1.1),
				randf_range(2.6, 4.6) * smoke_life, r * randf_range(0.5, 0.7), r * randf_range(1.5, 2.3),
				Color(tone * 1.08, tone, tone * 0.9, randf_range(0.75, 0.92)), r * 0.12 + 0.35, randf_range(1.5, 2.4),
				randf_range(2.5, 4.5), 0.55, randf_range(0.03, 0.2))
	# A big one's column climbs on.
	if r >= 4.0:
		for i in 5:
			var tone := randf_range(0.05, 0.09)
			smoke(center + Vector3.UP * r * 0.3, Vector3.UP * r * randf_range(1.6, 2.6) + _rand_dir() * r * 0.4,
					randf_range(3.5, 5.0) * smoke_life, r * 0.6, r * randf_range(1.7, 2.4), Color(tone, tone * 0.96, tone * 0.9, 0.85),
					r * 0.2, 1.2, 3.0, 0.6, randf_range(0.1, 0.3))

	if grounded:
		var ground := Vector3(pos.x, gy, pos.z)
		# Dust driven out along the ground in a ring.
		var n_dust := clampi(int(8 + r * 1.3), 8, 18)
		var a0 := randf() * TAU
		for i in n_dust:
			var a := a0 + TAU * (i + randf_range(-0.45, 0.45)) / n_dust
			var out := Vector3(cos(a), 0.0, sin(a))
			var tone := randf_range(0.8, 1.2)
			smoke(ground + out * r * randf_range(0.2, 0.5) + Vector3.UP * r * 0.15,
					out * r * randf_range(2.4, 4.6) + Vector3.UP * r * randf_range(0.1, 0.4), randf_range(2.4, 4.2) * smoke_life,
					r * 0.45, r * randf_range(1.2, 1.7), Color(0.2 * tone, 0.165 * tone, 0.12 * tone, 0.38), 0.15,
					randf_range(3.0, 4.0), 0.0, 0.5, randf_range(0.02, 0.1))
		# Dirt thrown up in dark columns that fall back.
		for i in clampi(int(r * 1.1), 3, 12):
			var d := (Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.45 + Vector3.UP).normalized()
			var sp := rv * randf_range(2.8, 4.8) + 2.5
			for k in 3:
				var f := 1.0 - k * 0.22
				smoke(ground + Vector3.UP * r * 0.1, d * sp * f, randf_range(1.3, 2.0) * (0.8 + r * 0.04), r * 0.18 * f,
						r * randf_range(0.45, 0.7), Color(0.12, 0.095, 0.07, 0.85), -9.0, 1.0, 0.0, 0.4, randf_range(0.0, 0.04))
		# The shock wave racing out over the ground, and the mark it leaves.
		warp(ground + Vector3.UP * 0.25, r * 0.4, r * 5.0, 0.3 + r * 0.02, 1, 0.05)
		if r >= 1.2:
			scorch(ground, r)
	else:
		warp(center, r * 0.5, r * 4.0, 0.25 + r * 0.015, 0, 0.05)
	# Heat haze over the fire.
	warp(center + Vector3.UP * r * 0.6, r * 1.2, r * 2.4, 1.4 + r * 0.05, 2, 0.02, Vector3.UP * 1.5, 0.0, 0.15)

	# Sparks and shrapnel, and embers drifting up on the heat.
	var n_spark := clampi(int(14 + r * 5.0), 14, 64)
	var spark_life := 0.8 + rv * 0.03
	for i in n_spark:
		var d := _rand_dir(grounded)
		if grounded:
			d = (d + Vector3.UP * 0.35).normalized()
		var hot := randf_range(0.8, 1.2)
		spark(center + d * r * 0.15, d * randf_range(0.4, 1.0) * (rv * 7.0 + 10.0), randf_range(0.35, 1.1) * spark_life,
				0.035 + rv * 0.008, 0.1 + rv * 0.03, Color(5.0 * hot, 2.5 * hot, 0.8 * hot), -9.8, randf_range(0.5, 1.4),
				floor_y, 0.03, 1.0, 0, randf_range(0.0, 0.03))
	for i in int(n_spark / 3.0):
		var d := _rand_dir(true)
		spark(center + d * r * randf_range(0.2, 0.6), d * rv * randf_range(0.6, 1.6) + Vector3.UP * r * 0.5,
				randf_range(1.2, 2.6), 0.03 + rv * 0.004, 0.05, Color(3.0, 1.1, 0.25), 1.2, 2.2, NO_FLOOR, 0.015, 0.6, 0,
				randf_range(0.05, 0.4))

	# Burning debris flung out on arcs, trailing smoke.
	if r >= 2.0:
		var land_y := gy if not is_nan(gy) else _ground_y(center, 400.0)
		for i in clampi(int(r * 1.3), 3, 14):
			var d := _rand_dir(grounded)
			if grounded:
				d = (d + Vector3.UP * 0.6).normalized()
			var v := d * (rv * randf_range(1.8, 3.6) + 4.0)
			var tone := randf_range(0.09, 0.17)
			debris(center + d * r * 0.2, v, clampf(r * randf_range(0.04, 0.09), 0.08, 1.4), randf_range(2.5, 4.5),
					Color(tone * 1.1, tone, tone * 0.9), randf_range(0.6, 1.2) if randf() < 0.5 else 0.0,
					randf_range(0.5, 1.3) * (0.7 + rv * 0.04), land_y if not is_nan(land_y) else center.y - 200.0)

	if shake_camera:
		shake(center, r)


## A gun's muzzle flash at `pos`, the barrel pointing along `dir` (zero: a star of flame all round): tongues of
## flame jetting out, a star of them round the muzzle, a blink of light and a wisp of smoke. `size` 1: a rifle's.
func muzzle_flash(pos: Vector3, dir: Vector3, size := 1.0, with_light := true, with_smoke := true) -> void:
	var s := size
	if dir.length_squared() < 0.0001:
		flare(pos, Color(7.0, 4.6, 2.2), 0.25 * s, 0.6 * s, 0.05, 1, 1.5)
		flare(pos, Color(4.0, 2.2, 0.9), 0.4 * s, 0.9 * s, 0.07, 0, 2.0)
	else:
		var d := dir.normalized()
		for k in 3:
			spark(pos + d * 0.05 * s, d * randf_range(9.0, 16.0) * s, randf_range(0.04, 0.065), randf_range(0.1, 0.16) * s,
					randf_range(0.28, 0.5) * s, Color(5.0, 3.0, 1.2), 0.0, 6.0, NO_FLOOR, 0.0, 0.4, 1)
		var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := side.cross(d)
		var a0 := randf() * TAU
		for k in 4:
			var a := a0 + k * TAU / 4.0
			var o := side * cos(a) + up * sin(a)
			spark(pos, (o * 0.8 + d * 0.6).normalized() * randf_range(4.0, 7.0) * s, randf_range(0.03, 0.05), 0.06 * s,
					0.16 * s, Color(4.0, 2.2, 0.8), 0.0, 6.0, NO_FLOOR, 0.0, 0.4, 1)
		flare(pos + d * 0.08 * s, Color(6.0, 4.0, 2.0), 0.22 * s, 0.5 * s, 0.045, 1, 1.5)
	if with_light:
		light(pos, Color(1.0, 0.78, 0.45), Color(1.0, 0.55, 0.25), 2.2 * s + 0.6, 4.0 + 3.0 * s, 0.07, 1.5 * s, 0.0)
	if with_smoke:
		var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
		smoke(pos + d * 0.15 * s, d * 1.5 + Vector3.UP * 0.3, randf_range(0.7, 1.1), 0.12 * s, 0.5 * s,
				Color(0.55, 0.54, 0.52, 0.28), 0.4, 3.0, 0.0, 0.6)


## A cannon, a mortar or a launcher going off at `pos` toward `dir`: a gout of flame and a flash, a ring of smoke
## blown out round the muzzle, unburnt powder sparking, the air rippling, the ground's dust shaken. `size` 1: a
## field gun's.
func muzzle_blast(pos: Vector3, dir: Vector3, size := 1.0) -> void:
	var s := maxf(size, 0.3)
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(d)
	flare(pos, Color(8.0, 5.5, 3.0), 0.6 * s, 1.8 * s, 0.07, 0, 2.0)
	flare(pos + d * 0.3 * s, Color(5.0, 3.0, 1.4), 0.8 * s, 2.2 * s, 0.05, 1, 1.5)
	light(pos + d * 0.5 * s, Color(1.0, 0.8, 0.5), Color(1.0, 0.5, 0.2), 5.0 * s + 2.0, 6.0 + 5.0 * s, 0.14, 5.0 * s, 0.2)
	for k in 5:
		flame(pos + d * 0.2 * s, (d + _rand_dir() * 0.18) * randf_range(10.0, 22.0) * s, randf_range(0.12, 0.22),
				0.3 * s, randf_range(0.8, 1.2) * s, 0.0, 7.0, 1.0, 0.6, 0.4)
	var a0 := randf() * TAU
	for k in 6:
		var a := a0 + k * TAU / 6.0
		var o := side * cos(a) + up * sin(a)
		spark(pos, (o + d * 0.4).normalized() * randf_range(5.0, 9.0) * s, randf_range(0.05, 0.08), 0.14 * s, 0.35 * s,
				Color(4.5, 2.4, 0.9), 0.0, 6.0, NO_FLOOR, 0.0, 0.4, 1)
	# The smoke ring blown out round the muzzle, and the cloud pushed out ahead of it.
	for k in 8:
		var a := a0 + k * TAU / 8.0
		var o := side * cos(a) + up * sin(a)
		smoke(pos + o * 0.2 * s, (o * 4.0 + d * 2.0) * s, randf_range(1.5, 2.6), 0.4 * s, randf_range(1.4, 2.0) * s,
				Color(0.42, 0.41, 0.39, 0.5), 0.3, 3.0, 1.5, 0.5)
	for k in 3:
		smoke(pos + d * (0.6 + k * 0.5) * s, d * randf_range(5.0, 10.0) * s, randf_range(1.8, 2.8), 0.5 * s,
				randf_range(1.6, 2.4) * s, Color(0.38, 0.37, 0.35, 0.55), 0.3, 2.6, 2.0, 0.5)
	for k in 8:
		spark(pos, _cone(d, 0.35) * randf_range(14.0, 30.0), randf_range(0.15, 0.4), 0.03, 0.08, Color(4.5, 2.5, 0.9),
				-9.8, 1.0, NO_FLOOR, 0.025)
	warp(pos + d * 0.5 * s, 0.3 * s, 2.6 * s, 0.18, 0, 0.04)
	shake(pos, s * 0.6)


## A round striking at `pos` on a surface facing `normal` (zero: unknown): sparks off it and a puff of its dust;
## `hurt`: it struck someone, a brighter spark.
func impact(pos: Vector3, normal: Vector3, hurt: bool, size := 1.0) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.ZERO
	var s := size
	var floor_y := pos.y - 0.02 if n.y > 0.5 else NO_FLOOR
	if hurt:
		flare(pos, Color(6.0, 4.2, 2.4), 0.12 * s, 0.4 * s, 0.06, 1, 1.5)
		for k in 7:
			spark(pos, _cone(n, 0.9) * randf_range(5.0, 12.0), randf_range(0.12, 0.3), 0.025, 0.06, Color(5.0, 3.0, 1.2),
					-9.8, 1.0, floor_y, 0.02)
		smoke(pos, n * 1.2 + Vector3.UP * 0.4, randf_range(0.5, 0.8), 0.1 * s, 0.45 * s, Color(0.3, 0.28, 0.26, 0.4), 0.3, 3.0)
	else:
		flare(pos + n * 0.03, Color(4.0, 2.8, 1.6), 0.08 * s, 0.25 * s, 0.04, 0, 2.0)
		for k in randi_range(3, 6):
			spark(pos + n * 0.02, _cone(n, 0.75) * randf_range(4.0, 11.0), randf_range(0.1, 0.28), 0.02, 0.05,
					Color(4.5, 2.6, 1.0), -9.8, 1.2, floor_y, 0.02)
		var tone := randf_range(0.9, 1.1)
		smoke(pos + n * 0.1, n * 1.6 + _rand_dir() * 0.4, randf_range(0.6, 1.1), 0.08 * s, 0.6 * s,
				Color(0.42 * tone, 0.38 * tone, 0.32 * tone, 0.45), 0.2, 3.5, 0.0, 0.4)
		if n.y > 0.6:
			for k in 2:
				smoke(pos, (Vector3.UP + _rand_dir() * 0.35) * randf_range(2.0, 3.2), randf_range(0.5, 0.8), 0.06 * s,
						0.3 * s, Color(0.2, 0.16, 0.12, 0.7), -9.0, 1.0, 0.0, 0.3)


## A round's tracer from `from` to `to` at `speed` (m/s): a glowing streak with a white-hot head.
func tracer(from: Vector3, to: Vector3, color: Color, width := 0.035, speed := 350.0) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var d := (to - from) / dist
	spark(from, d * speed, dist / speed, width * 1.4, minf(dist * 0.5, 4.0), Color(color.r * 7.0, color.g * 7.0, color.b * 7.0),
			0.0, 0.0, NO_FLOOR, 0.0, 0.0, 2)


## A flak shell bursting at `pos`: a flash, a black puff, shrapnel.
func flak_burst(pos: Vector3) -> void:
	flare(pos, Color(8.0, 6.0, 3.5), 0.5, 2.4, 0.08, 0, 2.5)
	flare(pos, Color(5.0, 3.0, 1.5), 0.8, 3.0, 0.05, 1, 2.0)
	light(pos, Color(1.0, 0.8, 0.5), Color(1.0, 0.45, 0.15), 5.0, 14.0, 0.25, 8.0)
	for k in 4:
		flame(pos + _rand_dir() * 0.3, _rand_dir() * randf_range(4.0, 8.0), randf_range(0.18, 0.3), 0.3, 1.2, 0.5, 6.0,
				1.0, 0.55, 0.9)
	for k in 6:
		smoke(pos + _rand_dir() * 0.4, _rand_dir() * randf_range(1.5, 3.5), randf_range(2.0, 3.0), 0.5, randf_range(1.8, 2.8),
				Color(0.05, 0.048, 0.045, 0.92), 0.12, 2.2, 3.0, 0.5)
	for k in 16:
		spark(pos, _rand_dir() * randf_range(25.0, 45.0), randf_range(0.12, 0.3), 0.025, 0.1, Color(4.5, 2.6, 1.0), -9.8, 1.0,
				NO_FLOOR, 0.025)
	warp(pos, 0.3, 3.2, 0.2, 0, 0.04)


## A small puff of smoke that rises and thins in a second or so (a hot gun, a launch, a bomb's wake).
func puff(pos: Vector3, size: float, color := Color(0.6, 0.6, 0.6, 0.5), vel := Vector3(0.0, 1.4, 0.0), life := 1.2) -> void:
	smoke(pos, vel + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25)), life * randf_range(0.85, 1.15),
			size * 0.45, size * 2.0, color, 0.3, 1.2, 0.0, 0.5)


# ================================================================ the particles

## A puff of smoke: launched from `pos` at `vel`, living `life` s, swelling from `size0` to `size1` (m); `color`
## its albedo (alpha: how thick); `rise` lifts it (m/s², negative pulls it down), `drag` slows it (1/s) toward the
## wind; `glow` lights it orange from inside for its first moments; `pale` how much it pales as it thins.
func smoke(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, color := Color(0.2, 0.19, 0.18, 0.8),
		rise := 0.5, drag := 1.0, glow := 0.0, pale := 1.0, delay := 0.0) -> void:
	_emit(SMOKE, pos, vel, life, size0, size1, rise, drag, color, Color(randf_range(-0.6, 0.6), pale, glow, 0.0), delay)


## A puff of flame: `heat` at birth (1: white-hot) cooling as it lives; `tint` scales its glow (a jet of many
## puffs wants less); `soot` how much of it turns to soot as it cools.
func flame(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, rise := 2.0, drag := 1.5, heat := 1.0,
		tint := 0.42, soot := 0.25, delay := 0.0) -> void:
	_emit(FIRE, pos, vel, life, size0, size1, rise, drag, Color(tint, tint, tint, heat),
			Color(randf_range(-1.2, 1.2), soot, 0.0, 0.0), delay)


## A streak: `width` and least `length` (m), smeared over `stretch` s of its motion, HDR `color` cooling to red by
## `cool`; it stops on `floor_y`. `shape` 0 spark, 1 tongue of flame, 2 tracer.
func spark(pos: Vector3, vel: Vector3, life: float, width: float, length: float, color: Color, gravity := -9.8,
		drag := 0.8, floor_y := NO_FLOOR, stretch := 0.03, cool := 1.0, shape := 0, delay := 0.0) -> void:
	_emit(SPARK, pos, vel, life, width, length, gravity, drag, color, Color(floor_y, float(shape), stretch, cool), delay)


## A glow (`shape` 0), a star (1) or a ring (2) of HDR `color` growing from `size0` to `size1`, fading at `fade`.
func flare(pos: Vector3, color: Color, size0: float, size1: float, life: float, shape := 0, fade := 2.0, delay := 0.0,
		vel := Vector3.ZERO) -> void:
	_emit(FLARE, pos, vel, life, size0, size1, 0.0, 0.0, color, Color(float(shape), fade, randf() * TAU, 0.0), delay)


## The air bent: a shock bubble (`mode` 0), a shock ring along the ground (1) or heat haze (2).
func warp(pos: Vector3, size0: float, size1: float, life: float, mode := 0, strength := 0.04, vel := Vector3.ZERO,
		rise := 0.0, delay := 0.0) -> void:
	if not _rich:
		return
	_emit(WARP, pos, vel, life, size0, size1, rise, 0.0, Color.WHITE, Color(float(mode), strength, 0.0, 0.0), delay)


func _emit(layer: int, pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, accel_y: float, drag: float,
		color: Color, custom: Color, delay := 0.0) -> void:
	var i := _next[layer]
	_next[layer] = (i + 1) % int(CAPS[layer])
	var mm := _mm[layer]
	mm.set_instance_transform(i, Transform3D(Basis(Vector3(vel.x, _time + delay, accel_y), Vector3(vel.y, life, size0),
			Vector3(vel.z, drag, size1)), pos))
	mm.set_instance_color(i, color)
	mm.set_instance_custom_data(i, custom)


# ================================================================ lights

class _Light:
	var node: OmniLight3D
	var age := 0.0
	var life := 0.0
	var peak := 0.0
	var flash := 0.0
	var reach := 0.0
	var hot := Color.WHITE
	var cool := Color.WHITE
	var flicker := 0.0
	var wobble := 0.0
	var now := 0.0

	func lit() -> bool:
		return age < life


## A burst of light at `pos`: `energy` at its height and `flash` more for its first instant, dying away over
## `life` s while it turns from `hot` to `cool` and flickers by `flicker` (0-1). Once MAX_LIGHTS are lit the
## faintest is taken over.
func light(pos: Vector3, hot: Color, cool: Color, energy: float, reach: float, life: float, flash := 0.0,
		flicker := 0.3, shadow := false) -> void:
	var slot: _Light = null
	var faintest: _Light = null
	var shadowed := 0
	for l in _lights:
		var e := l as _Light
		if not e.lit():
			if slot == null:
				slot = e
			continue
		if e.node.shadow_enabled:
			shadowed += 1
		if faintest == null or e.now < faintest.now:
			faintest = e
	if slot == null:
		if _lights.size() < MAX_LIGHTS:
			slot = _Light.new()
			slot.node = OmniLight3D.new()
			slot.node.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			slot.node.light_volumetric_fog_energy = 2.5
			slot.node.light_specular = 0.6
			slot.node.visible = false
			add_child(slot.node)
			_lights.append(slot)
		else:
			slot = faintest
			if slot.node.shadow_enabled:
				shadowed -= 1
	slot.age = 0.0
	slot.life = maxf(life, 0.02)
	slot.peak = energy
	slot.flash = flash
	slot.reach = reach
	slot.hot = hot
	slot.cool = cool
	slot.flicker = flicker
	slot.wobble = 0.0
	slot.now = energy + flash
	slot.node.shadow_enabled = shadow and _rich and shadowed < MAX_SHADOWED
	slot.node.position = pos
	slot.node.light_color = hot
	slot.node.light_energy = slot.now
	slot.node.omni_range = reach * 0.75
	slot.node.visible = true


func _update_lights(dt: float) -> void:
	for l in _lights:
		var e := l as _Light
		if not e.lit():
			continue
		e.age += dt
		if not e.lit():
			e.node.visible = false
			e.node.shadow_enabled = false
			e.now = 0.0
			continue
		var u := e.age / e.life
		e.wobble = lerpf(e.wobble, randf_range(-1.0, 1.0), 0.35)
		e.now = (e.peak * pow(1.0 - u, 1.6) + e.flash * exp(-e.age / 0.05)) * (1.0 + e.flicker * e.wobble * 0.5)
		e.node.light_energy = maxf(e.now, 0.0)
		e.node.light_color = e.hot.lerp(e.cool, clampf(u * 2.5, 0.0, 1.0))
		e.node.omni_range = e.reach * (0.75 + 0.25 * minf(e.age / 0.08, 1.0))


# ================================================================ debris

class _Chunk:
	var index := 0
	var active := false
	var resting := false
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var axis := Vector3.UP
	var ang := 0.0
	var spin := 0.0
	var age := 0.0
	var life := 0.0
	var floor_y := 0.0
	var size := 0.2
	var dims := Vector3.ONE
	var tint := Color.BLACK
	var heat := 0.0
	var trail := 0.0
	var trail_cd := 0.0


## A chunk of debris of `size` (m) flung from `pos` at `vel`, lying where it lands on `floor_y` until `life` s are
## up; `heat` how hot it glows (cooling), `trail` how long it trails smoke (s).
func debris(pos: Vector3, vel: Vector3, size: float, life: float, tint: Color, heat: float, trail: float, floor_y: float) -> void:
	var c: _Chunk = null
	for x in _debris:
		if not (x as _Chunk).active:
			c = x
			break
	if c == null:
		if _debris.size() < MAX_DEBRIS:
			c = _Chunk.new()
			c.index = _debris.size()
			_debris.append(c)
		else:
			c = _debris[_deb_next]
			_deb_next = (_deb_next + 1) % MAX_DEBRIS
	c.active = true
	c.resting = false
	c.pos = pos
	c.vel = vel
	c.axis = _rand_dir()
	c.ang = randf() * TAU
	c.spin = randf_range(-14.0, 14.0)
	c.age = 0.0
	c.life = life
	c.floor_y = floor_y
	c.size = size
	c.dims = Vector3(randf_range(0.6, 1.4), randf_range(0.5, 1.1), randf_range(0.6, 1.4)) * size
	c.tint = tint
	c.heat = heat
	c.trail = trail
	c.trail_cd = 0.0


func _update_debris(dt: float) -> void:
	for x in _debris:
		var c := x as _Chunk
		if not c.active:
			continue
		c.age += dt
		if c.age >= c.life:
			c.active = false
			_deb_mm.set_instance_transform(c.index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		var heat := c.heat * maxf(1.0 - c.age / 1.6, 0.0)
		if not c.resting:
			c.vel.y -= 12.0 * dt
			c.vel *= 1.0 - 0.12 * dt
			c.pos += c.vel * dt
			c.ang += c.spin * dt
			var bottom := c.floor_y + c.size * 0.3
			if c.pos.y < bottom:
				c.pos.y = bottom
				if c.vel.y > -3.0:
					c.resting = true
					c.vel = Vector3.ZERO
				else:
					c.vel = Vector3(c.vel.x * 0.45, -c.vel.y * 0.32, c.vel.z * 0.45)
					c.spin *= 0.6
					smoke(c.pos, Vector3.UP * 0.8, randf_range(0.8, 1.3), c.size, c.size * 4.0,
							Color(0.3, 0.26, 0.2, 0.5), 0.2, 2.5, 0.0, 0.5)
			if c.age < c.trail:
				c.trail_cd -= dt
				if c.trail_cd <= 0.0:
					c.trail_cd = 0.045
					var left := 1.0 - c.age / c.trail
					var tone := randf_range(0.1, 0.16)
					smoke(c.pos, c.vel * 0.05, randf_range(0.9, 1.8) * (0.6 + left * 0.4), c.size * 0.9, c.size * 3.5 + 0.6,
							Color(tone, tone * 0.96, tone * 0.92, 0.15 + 0.5 * left), 0.4, 1.2, heat * 1.5, 0.8)
					if heat > 0.3 and c.age < c.trail * 0.45:
						flame(c.pos, c.vel * 0.1, randf_range(0.2, 0.35), c.size * 1.2, c.size * 2.4, 1.0, 2.0, 0.9, 0.5, 0.1)
		var shrink := clampf((c.life - c.age) / 0.8, 0.0, 1.0)
		_deb_mm.set_instance_transform(c.index, Transform3D(Basis(c.axis, c.ang) * Basis.from_scale(c.dims * shrink), c.pos))
		_deb_mm.set_instance_color(c.index, Color(c.tint.r, c.tint.g, c.tint.b, heat))


# ================================================================ scorch marks

## A scorch mark burnt into the ground at `pos` by a blast of `radius`: charred, glowing embers in it at first.
func scorch(pos: Vector3, radius: float) -> void:
	var d: Decal = null
	var entry: Array = []
	if _scorch.size() < MAX_SCORCH:
		d = Decal.new()
		d.texture_albedo = _scorch_texture(false)
		d.texture_emission = _scorch_texture(true)
		d.upper_fade = 0.3
		d.lower_fade = 0.5
		d.normal_fade = 0.35
		d.distance_fade_enabled = true
		d.distance_fade_begin = 220.0
		d.distance_fade_length = 60.0
		add_child(d)
		entry = [d, 0.0]
		_scorch.append(entry)
	else:
		for e in _scorch:
			if entry.is_empty() or (e[1] as float) > (entry[1] as float):
				entry = e
		d = entry[0]
	entry[1] = 0.0
	var size := radius * 2.1
	d.size = Vector3(size, clampf(radius * 0.9, 1.0, 4.0), size)
	d.position = pos
	d.rotation = Vector3(0.0, randf() * TAU, 0.0)
	d.modulate = Color(1, 1, 1, randf_range(0.8, 1.0))
	d.emission_energy = 3.0
	d.visible = true


func _update_scorch(dt: float) -> void:
	for e in _scorch:
		var d: Decal = e[0]
		if not d.visible:
			continue
		var age: float = e[1] + dt
		e[1] = age
		if age >= SCORCH_LIFE:
			d.visible = false
			continue
		var cool := maxf(1.0 - age / 4.0, 0.0)
		d.emission_energy = 3.0 * cool * cool
		d.modulate.a = minf(d.modulate.a, clampf((SCORCH_LIFE - age) / SCORCH_FADE, 0.0, 1.0))


# ================================================================ camera shake

## Shakes the camera for a blast of `radius` at `at`: hard close by, barely at all from far off.
func shake(at: Vector3, radius: float) -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(at)
	var add := clampf(radius * 4.0 / (d + 10.0), 0.0, 1.0)
	if add < 0.04:
		return
	_shake_dist = lerpf(_shake_dist, d, add / maxf(_trauma + add, 0.001))
	_trauma = minf(_trauma + add, 1.0)


## The shake rides on the camera's h_offset / v_offset, on top of whatever its owner sets them to.
func _update_shake(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != _shake_cam:
		_release_shake()
		_shake_cam = cam
	if cam == null:
		return
	_trauma = maxf(_trauma - dt * 1.5, 0.0)
	if _trauma <= 0.0 and _shake_applied == Vector2.ZERO:
		return
	var amp := _trauma * _trauma * 0.025 * clampf(_shake_dist, 4.0, 120.0)
	var off := Vector2(_shake_noise.get_noise_2d(_time * 40.0, 0.0), _shake_noise.get_noise_2d(0.0, _time * 40.0 + 100.0)) * amp
	var cur := Vector2(cam.h_offset, cam.v_offset)
	var base := cur - _shake_applied if cur.is_equal_approx(_shake_written) else cur
	cam.h_offset = base.x + off.x
	cam.v_offset = base.y + off.y
	_shake_written = base + off
	_shake_applied = off


func _release_shake() -> void:
	if is_instance_valid(_shake_cam):
		var cur := Vector2(_shake_cam.h_offset, _shake_cam.v_offset)
		if cur.is_equal_approx(_shake_written):
			_shake_cam.h_offset = cur.x - _shake_applied.x
			_shake_cam.v_offset = cur.y - _shake_applied.y
	_shake_cam = null
	_shake_applied = Vector2.ZERO
	_shake_written = Vector2.ZERO


# ================================================================ helpers

## The height of the ground (or what stands on it) under `p`, looking up to `depth` m down; NAN if nothing.
func _ground_y(p: Vector3, depth: float) -> float:
	if not is_inside_tree():
		return NAN
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p - Vector3.UP * depth,
			GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if hit.is_empty() else (hit.position as Vector3).y


static func _rand_dir(up := false) -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	while v.length_squared() > 1.0 or v.length_squared() < 0.0001:
		v = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	v = v.normalized()
	if up:
		v.y = absf(v.y) * 0.85 + 0.15
		v = v.normalized()
	return v


## A random direction round `axis`, `spread` off it (zero axis: any direction).
static func _cone(axis: Vector3, spread: float) -> Vector3:
	if axis.length_squared() < 0.0001:
		return _rand_dir()
	return (axis + _rand_dir() * spread).normalized()


static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var src := code
		# The particle layers get the shared clock, motion and noise ahead of their vertex function.
		if src.contains("%UNPACK%"):
			src = src.replace("%UNPACK%", UNPACK).replace("void vertex()", SIM + "\nvoid vertex()")
		var sh := Shader.new()
		sh.code = src
		_shaders[code] = sh
	return _shaders[code]


## The noise every puff is broken up with (tiling).
static func noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = 1337
		n.frequency = 0.018
		n.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = n
	return _noise


## A rough little rock: an octahedron with its corners pushed about, flat-shaded.
static func _chunk() -> ArrayMesh:
	if _chunk_mesh == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var v: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
		for i in v.size():
			v[i] = v[i] * rng.randf_range(0.65, 1.0) + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		for f in [[0, 4, 2], [2, 4, 1], [1, 4, 3], [3, 4, 0], [2, 5, 0], [1, 5, 2], [3, 5, 1], [0, 5, 3]]:
			for k in f:
				st.set_color(Color.WHITE)
				st.add_vertex(v[k] * 0.5)
		st.generate_normals()
		_chunk_mesh = st.commit()
	return _chunk_mesh


## The scorch mark's charred blotch (or, `glow`, the embers glowing in it).
static func _scorch_texture(glow: bool) -> ImageTexture:
	if _scorch_albedo == null:
		var n := FastNoiseLite.new()
		n.seed = 7
		n.frequency = 0.045
		n.fractal_octaves = 4
		var size := 128
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var hot := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var p := Vector2(x, y) / (size - 1.0) * 2.0 - Vector2.ONE
				var r := p.length()
				var ang := atan2(p.y, p.x)
				var nv := n.get_noise_2d(x, y) * 0.5 + 0.5
				# Rays of soot thrown out round the rim.
				var rays := n.get_noise_2d(cos(ang) * 60.0 + 300.0, sin(ang) * 60.0 + 300.0) * 0.5 + 0.5
				var edge := 0.5 + 0.28 * nv + 0.3 * rays
				var a := 1.0 - smoothstep(edge * 0.45, edge, r)
				var c := Color(0.045, 0.04, 0.035).lerp(Color(0.17, 0.13, 0.09), smoothstep(0.15, 0.85, r / edge))
				img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a * (0.7 + 0.3 * nv), 0.0, 1.0)))
				var ember := clampf((nv - 0.56) * 6.0, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.5, r))
				hot.set_pixel(x, y, Color(ember, ember * 0.4, ember * 0.12, 1.0))
		img.generate_mipmaps()
		hot.generate_mipmaps()
		_scorch_albedo = ImageTexture.create_from_image(img)
		_scorch_glow = ImageTexture.create_from_image(hot)
	return _scorch_glow if glow else _scorch_albedo
