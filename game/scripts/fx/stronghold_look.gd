class_name StrongholdLook
extends RefCounted
## The stronghold's materials (the mountain and the bunkers dug into it, stronghold.glb, and the gates' blast
## doors): photoscanned rock, concrete and steel (CC0, Poly Haven: see README) in place of the model's flat
## colours, picked by the model's material names. The model has no UVs: every texture is projected from the
## three axes in world space, each projection in a right-handed frame so its normal map lights the right way.
##
## - Rock: the mountain. Scanned rock face up close, a scanned cliff (aerial) over it at fifty metres for the
##   big shapes, cracks and colour; faint strata; grass and soil settling on the ledges and flat tops, moss in
##   the crevices (thicker in the jungle).
## - Concrete: board-formed walls (their pour lines level) and worn slab decks, rain streaks run down the walls
##   from every ledge, grime and splashed earth at their foot, patches of weathering; moss and algae in the
##   jungle. ConcreteDark is the same, darker.
## - Metal: worn steel plate. HatchOrange: hazard-orange paint flaking off rust; the door frames striped in
##   yellow and black.

const ROCK_MACRO := "res://assets/textures/stronghold/aerial_rocks_02_%s.jpg"
const WALL := "res://assets/textures/stronghold/concrete_layers_02_%s.jpg"
const DECK := "res://assets/textures/stronghold/dirty_concrete_%s.jpg"
const STEEL := "res://assets/textures/stronghold/metal_plate_02_%s.jpg"
const PAINT := "res://assets/textures/stronghold/rusty_metal_02_%s.jpg"

## Shared by the stronghold's shaders: the three projections and their frames.
const TRIPLANAR := """
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Where `p` falls in each projection (scaled by `s`), and how much each counts on a surface facing `n`.
void tri_frames(vec3 p, vec3 n, float s, out vec2 ux, out vec2 uy, out vec2 uz, out vec3 bw, out vec3 sg) {
	sg = vec3(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
	ux = vec2(-sg.x * p.z, -p.y) * s;
	uy = vec2(p.x, sg.y * p.z) * s;
	uz = vec2(sg.z * p.x, -p.y) * s;
	bw = pow(abs(n), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
}

// The three projections' normal-map tilts (xy, -1..1) turned into the world's frame and blended.
vec3 tri_detail(vec2 nx, vec2 ny, vec2 nz, vec3 bw, vec3 sg) {
	return (vec3(0.0, 0.0, -sg.x) * nx.x + vec3(0.0, 1.0, 0.0) * nx.y) * bw.x
			+ (vec3(1.0, 0.0, 0.0) * ny.x + vec3(0.0, 0.0, -sg.y) * ny.y) * bw.y
			+ (vec3(sg.z, 0.0, 0.0) * nz.x + vec3(0.0, 1.0, 0.0) * nz.y) * bw.z;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
"""

const ROCK_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2DArray layer_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_orh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float rock_layer = 6.0;
uniform float grass_layer = 3.0;
uniform float soil_layer = 4.0;
uniform vec3 rock_tint = vec3(1.0);
uniform vec3 grass_tint = vec3(1.0);
uniform float moss = 0.3;
uniform float rock_tile = 6.0;
uniform float macro_tile = 48.0;
%TRIPLANAR%
void fragment() {
	vec3 N = normalize(wnrm);
	vec2 ux;
	vec2 uy;
	vec2 uz;
	vec3 bw;
	vec3 sg;
	tri_frames(wpos, N, 1.0 / rock_tile, ux, uy, uz, bw, sg);
	float m1 = texture(macro_noise, wpos.xz * 0.004 + vec2(wpos.y * 0.003)).r;
	float m3 = texture(macro_noise, wpos.xz * 0.05 + vec2(0.0, wpos.y * 0.05)).r;
	// Scanned rock face, close up.
	vec3 ra = texture(layer_albedo, vec3(ux, rock_layer)).rgb * bw.x + texture(layer_albedo, vec3(uy, rock_layer)).rgb * bw.y
			+ texture(layer_albedo, vec3(uz, rock_layer)).rgb * bw.z;
	vec3 ro = texture(layer_orh, vec3(ux, rock_layer)).rgb * bw.x + texture(layer_orh, vec3(uy, rock_layer)).rgb * bw.y
			+ texture(layer_orh, vec3(uz, rock_layer)).rgb * bw.z;
	vec3 rdet = tri_detail(texture(layer_normal, vec3(ux, rock_layer)).rg * 2.0 - 1.0,
			texture(layer_normal, vec3(uy, rock_layer)).rg * 2.0 - 1.0, texture(layer_normal, vec3(uz, rock_layer)).rg * 2.0 - 1.0, bw, sg);
	// The cliff's big shapes over it.
	float k = rock_tile / macro_tile;
	vec3 ma = texture(macro_albedo, ux * k).rgb * bw.x + texture(macro_albedo, uy * k).rgb * bw.y + texture(macro_albedo, uz * k).rgb * bw.z;
	vec3 mdet = tri_detail(texture(macro_normal, ux * k).rg * 2.0 - 1.0, texture(macro_normal, uy * k).rg * 2.0 - 1.0,
			texture(macro_normal, uz * k).rg * 2.0 - 1.0, bw, sg);
	vec3 rock = ra * rock_tint * mix(vec3(1.0), ma / max(vec3(luma(ma)), vec3(0.02)) * 0.35 + vec3(luma(ma) / 0.18) * 0.65, 0.55);
	// Faint strata.
	rock *= 0.93 + 0.14 * (0.5 + 0.5 * sin(wpos.y * 1.9 + m1 * 9.0 + m3 * 2.0));
	rock *= mix(0.85, 1.1, m1);
	float rough = ro.g;
	float ao = ro.r;
	// Moss in the crevices and on what faces up.
	float mossy = moss * smoothstep(0.35, 0.75, (1.0 - ao) * 0.7 + N.y * 0.45 + (m3 - 0.5) * 0.6);
	rock = mix(rock, vec3(0.05, 0.075, 0.025) * (0.6 + 0.8 * luma(ra) / 0.25), mossy);
	// Grass and soil settled on the ledges and flat tops, blended by height.
	float flat_up = smoothstep(0.62, 0.85, N.y + (m3 - 0.5) * 0.25);
	vec3 col = rock;
	vec3 det = rdet * 1.25 + mdet * 0.9;
	if (flat_up > 0.002) {
		vec2 gu = wpos.xz / 2.6;
		float soil = smoothstep(0.38, 0.62, m1);
		vec4 g = mix(vec4(texture(layer_albedo, vec3(gu, grass_layer)).rgb * grass_tint, texture(layer_orh, vec3(gu, grass_layer)).b),
				vec4(texture(layer_albedo, vec3(gu, soil_layer)).rgb, texture(layer_orh, vec3(gu, soil_layer)).b), soil);
		vec2 gn = mix(texture(layer_normal, vec3(gu, grass_layer)).rg, texture(layer_normal, vec3(gu, soil_layer)).rg, soil) * 2.0 - 1.0;
		float gw = smoothstep(0.0, 0.25, g.a + flat_up * 1.3 - ro.b - 0.55);
		col = mix(col, g.rgb, gw);
		det = mix(det, vec3(gn.x, 0.0, -gn.y), gw);
		rough = mix(rough, 0.9, gw);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	AO = mix(1.0, ao, 0.9);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(N + det), 0.0)).xyz);
}
"""

const CONCRETE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_orh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D deck_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D deck_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D deck_orh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float wall_tile = 2.6;
uniform float deck_tile = 3.2;
uniform float moss = 0.0;
uniform float ground_y = 0.0;
%TRIPLANAR%
void fragment() {
	vec3 N = normalize(wnrm);
	vec2 ux;
	vec2 uy;
	vec2 uz;
	vec3 bw;
	vec3 sg;
	tri_frames(wpos, N, 1.0 / wall_tile, ux, uy, uz, bw, sg);
	vec2 ud = uy * wall_tile / deck_tile;
	// Board-formed walls, slab decks.
	vec3 col = texture(wall_albedo, ux).rgb * bw.x + texture(deck_albedo, ud).rgb * bw.y + texture(wall_albedo, uz).rgb * bw.z;
	vec3 o = texture(wall_orh, ux).rgb * bw.x + texture(deck_orh, ud).rgb * bw.y + texture(wall_orh, uz).rgb * bw.z;
	vec3 det = tri_detail(texture(wall_normal, ux).rg * 2.0 - 1.0, texture(deck_normal, ud).rg * 2.0 - 1.0,
			texture(wall_normal, uz).rg * 2.0 - 1.0, bw, sg);
	col *= tint;
	float m1 = texture(macro_noise, (wpos.xz + wpos.y) * 0.02).r;
	float m2 = texture(macro_noise, (wpos.xz - wpos.y) * 0.09 + vec2(0.3, 0.6)).r;
	// Patches of weathering.
	col *= mix(0.8, 1.08, m1) * mix(0.94, 1.04, m2);
	float wall = 1.0 - bw.y;
	// Rain streaks run down the walls.
	float streak = texture(macro_noise, vec2((wpos.x + wpos.z) * 0.45, wpos.y * 0.015)).r;
	float streaks = smoothstep(0.52, 0.78, streak + (m2 - 0.5) * 0.2) * wall;
	col *= 1.0 - streaks * 0.34;
	// Grime and splashed earth at the foot.
	float foot = 1.0 - smoothstep(0.0, 2.4, wpos.y - ground_y + (m2 - 0.5) * 0.8);
	col = mix(col, col * vec3(0.58, 0.5, 0.4), foot * 0.75);
	float rough = mix(o.g, 0.97, streaks * 0.3);
	// Moss on what faces up, green algae down the streaks (the jungle).
	float mossy = moss * max(smoothstep(0.55, 0.8, N.y * 0.7 + m2 * 0.5), streaks * 0.6 + foot * 0.4) * smoothstep(0.35, 0.6, m1 + m2 * 0.3);
	col = mix(col, vec3(0.06, 0.085, 0.03) * (0.6 + luma(col) * 2.0), mossy * 0.8);
	ALBEDO = col;
	ROUGHNESS = rough;
	AO = mix(1.0, o.r, 0.9);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(N + det * 1.1), 0.0)).xyz);
}
"""

## Worn steel, or (paint) hazard paint flaking off rust, striped on the door frames.
const METAL_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float tile = 1.6;
// 0: steel, 1: hazard paint, 2: hazard stripes.
uniform int finish = 0;
%TRIPLANAR%
void fragment() {
	vec3 N = normalize(wnrm);
	vec2 ux;
	vec2 uy;
	vec2 uz;
	vec3 bw;
	vec3 sg;
	tri_frames(wpos, N, 1.0 / tile, ux, uy, uz, bw, sg);
	vec3 a = texture(albedo_tex, ux).rgb * bw.x + texture(albedo_tex, uy).rgb * bw.y + texture(albedo_tex, uz).rgb * bw.z;
	vec3 o = texture(arm_tex, ux).rgb * bw.x + texture(arm_tex, uy).rgb * bw.y + texture(arm_tex, uz).rgb * bw.z;
	vec3 det = tri_detail(texture(normal_tex, ux).rg * 2.0 - 1.0, texture(normal_tex, uy).rg * 2.0 - 1.0,
			texture(normal_tex, uz).rg * 2.0 - 1.0, bw, sg);
	vec3 col = a * tint;
	float metal = o.b;
	float rough = o.g;
	if (finish > 0) {
		// The scan is white paint over rust: where the paint is, it is hazard orange (or the stripes).
		float paint = smoothstep(0.32, 0.52, luma(a));
		vec3 colour = vec3(0.8, 0.23, 0.02);
		if (finish == 2) {
			float band = fract((wpos.x + wpos.z) * 1.4 + wpos.y * 1.4);
			colour = band < 0.5 ? vec3(0.85, 0.55, 0.01) : vec3(0.025, 0.025, 0.025);
		}
		col = mix(a * vec3(0.95, 0.75, 0.6), colour * (0.75 + 0.5 * luma(a)), paint);
		metal = mix(0.35, 0.0, paint);
		rough = mix(0.75, 0.45, paint);
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	AO = mix(1.0, o.r, 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(N + det), 0.0)).xyz);
}
"""

static var _mats := {}


## Gives the stronghold model under `root` its materials (`jungle`: mossier, damper).
static func apply(root: Node3D, jungle: bool) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src == null:
				continue
			var key := src.resource_name
			if key == "HatchOrange" and String(m.name).begins_with("DoorFrame"):
				key = "HatchStripes"
			var mat := material(key, jungle)
			if mat:
				m.set_surface_override_material(s, mat)


## The material standing in for the model's `key` (Rock, Concrete, ConcreteDark, Metal, HatchOrange,
## HatchStripes); null for any other.
static func material(key: String, jungle: bool) -> ShaderMaterial:
	var cache := "%s_%s" % [key, jungle]
	if _mats.has(cache):
		return _mats[cache]
	var m: ShaderMaterial = null
	match key:
		"Rock":
			m = _shader_material(ROCK_SHADER)
			m.set_shader_parameter("layer_albedo", load(GroundMaterial.ALBEDO))
			m.set_shader_parameter("layer_normal", load(GroundMaterial.NORMAL))
			m.set_shader_parameter("layer_orh", load(GroundMaterial.ORH))
			m.set_shader_parameter("macro_albedo", load(ROCK_MACRO % "albedo"))
			m.set_shader_parameter("macro_normal", load(ROCK_MACRO % "normal"))
			m.set_shader_parameter("macro_noise", GroundMaterial.macro_noise())
			m.set_shader_parameter("rock_layer", float(GroundMaterial.ROCK))
			m.set_shader_parameter("grass_layer", float(GroundMaterial.GRASS_DARK if jungle else GroundMaterial.GRASS))
			m.set_shader_parameter("soil_layer", float(GroundMaterial.MOSSY if jungle else GroundMaterial.DIRT))
			m.set_shader_parameter("rock_tint", Vector3(0.82, 0.8, 0.76) if jungle else Vector3(0.95, 0.9, 0.82))
			m.set_shader_parameter("grass_tint", Vector3(0.8, 1.0, 0.7) if jungle else Vector3(0.95, 1.0, 0.8))
			m.set_shader_parameter("moss", 0.75 if jungle else 0.2)
		"Concrete", "ConcreteDark":
			m = _shader_material(CONCRETE_SHADER)
			for part in ["albedo", "normal", "orh"]:
				m.set_shader_parameter("wall_" + part, load(WALL % part))
				m.set_shader_parameter("deck_" + part, load(DECK % part))
			m.set_shader_parameter("macro_noise", GroundMaterial.macro_noise())
			var t := 0.55 if key == "ConcreteDark" else 0.95
			m.set_shader_parameter("tint", Vector3(t, t * 0.98, t * 0.95))
			m.set_shader_parameter("moss", 0.7 if jungle else 0.1)
		"Metal":
			m = _metal(STEEL, Vector3(0.75, 0.78, 0.82), 1.6, 0)
		"HatchOrange":
			m = _metal(PAINT, Vector3.ONE, 1.2, 1)
		"HatchStripes":
			m = _metal(PAINT, Vector3.ONE, 1.2, 2)
	if m:
		_mats[cache] = m
	return m


static func _metal(path: String, tint: Vector3, tile: float, finish: int) -> ShaderMaterial:
	var m := _shader_material(METAL_SHADER)
	m.set_shader_parameter("albedo_tex", load(path % "albedo"))
	m.set_shader_parameter("normal_tex", load(path % "normal"))
	m.set_shader_parameter("arm_tex", load(path % "arm"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("finish", finish)
	return m


static var _shaders := {}


static func _shader_material(code: String) -> ShaderMaterial:
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code.replace("%TRIPLANAR%", TRIPLANAR)
		_shaders[code] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[code]
	return m
