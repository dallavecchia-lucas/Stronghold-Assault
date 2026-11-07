class_name Atmosphere
extends Node
## A map's light and air: the sky, the sun, the haze, and how the camera renders it all.
##
## The sky is drawn by a shader: deep blue overhead paling to a bright haze at the horizon, the haze over the
## far land below it (the colour of the fog, so the land fades into the sky), a warm glow round the sun and its
## blooming disk, and clouds lit from the sun's side, shadowed underneath, thinning toward the horizon. The sun
## is warm, its shadows soft (they harden where they touch) over four cascades. ACES tone mapping with a broad
## bloom: what is brighter than white (the sun, fire, muzzle flashes, explosions) glows. Ambient occlusion
## darkens the creases, screen-space indirect light bounces colour (and a blast's glare) onto what is round it,
## and volumetric fog fills the air: the sun's shafts through the canopy, a halo round every fire and blast. The
## fog thins as the camera climbs, so the strategy view stays clear.
##
## Atmosphere.build(level, jungle) adds the WorldEnvironment and the sun to `level` (as its own children: the
## showcases look for them there) and itself, to keep the fog right for the camera.

const SKY_SHADER := """
shader_type sky;
uniform vec4 zenith : source_color = vec4(0.24, 0.42, 0.7, 1.0);
uniform vec4 horizon : source_color = vec4(0.72, 0.75, 0.76, 1.0);
uniform vec4 haze : source_color = vec4(0.62, 0.64, 0.62, 1.0);
uniform vec4 ground : source_color = vec4(0.36, 0.34, 0.29, 1.0);
uniform float sun_disk_scale = 3.0;
uniform float cloud_cover = 0.42;
uniform float cloud_scale = 0.55;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

float clouds_at(vec2 uv) {
	return texture(cloud_noise, uv * 0.35).r * 0.6 + texture(cloud_noise, uv * 1.1 + vec2(0.3)).r * 0.3
			+ texture(cloud_noise, uv * 3.3 + vec2(0.7)).r * 0.1;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	// Deep blue overhead, paling to the haze at the horizon; below it, the haze over the far land.
	vec3 col = mix(horizon.rgb, zenith.rgb, pow(clamp(h, 0.0, 1.0), 0.5));
	vec3 below = mix(haze.rgb, ground.rgb, smoothstep(0.0, 0.4, -h));
	col = mix(col, below, smoothstep(0.0, -0.03, h));
	if (LIGHT0_ENABLED) {
		vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
		float sd = dot(d, LIGHT0_DIRECTION);
		float s = max(sd, 0.0);
		float up = smoothstep(-0.25, 0.05, h);
		// The air glows round the sun: a broad warm halo and a tight bright one; the horizon warms toward it.
		col += sun * (pow(s, 6.0) * 0.16 + pow(s, 48.0) * 0.45) * up;
		col *= mix(vec3(1.0), vec3(1.12, 1.0, 0.86), pow(s, 3.0) * (1.0 - clamp(h * 2.0, 0.0, 1.0)) * 0.6);
		float r = max(LIGHT0_SIZE * 0.5, 0.0045) * sun_disk_scale;
		float disk = 1.0 - smoothstep(r * 0.8, r, acos(clamp(sd, -1.0, 1.0)));
		if (h > 0.0) {
			// Clouds on a plane overhead: lit from the sun's side, shadowed under, fading into the haze.
			vec2 uv = d.xz / (h + 0.18) * cloud_scale;
			float n = clouds_at(uv);
			float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n) * smoothstep(0.0, 0.16, h);
			vec2 toward = normalize(LIGHT0_DIRECTION.xz + vec2(0.0001)) * 0.035;
			float shade = clamp(0.62 + (n - clouds_at(uv + toward)) * 4.5, 0.25, 1.0);
			vec3 lit = (vec3(0.55) + LIGHT0_COLOR * 0.45) * LIGHT0_ENERGY * 0.82 + horizon.rgb * 0.15;
			vec3 dark = mix(horizon.rgb, zenith.rgb, 0.5) * 0.68;
			vec3 cloud = mix(dark, lit, shade);
			// Their thin edges shine where the sun is behind them.
			cloud += sun * pow(s, 10.0) * (1.0 - smoothstep(0.0, 0.6, cov)) * 1.2;
			col = mix(col, cloud, cov * 0.92);
			disk *= 1.0 - cov;
		}
		col += sun * disk * 30.0;
	}
	COLOR = col;
}
"""

## How thick the volumetric fog is with the camera on the ground, and the share of it left once the camera is
## FOG_THIN_HEIGHT (m) up.
const FOG_THIN_HEIGHT := 40.0
const FOG_HIGH := 0.2

var env: Environment
var sun: DirectionalLight3D
var fog_density := 0.004

static var _clouds: NoiseTexture2D


## Lights `level`: the Jungle Keep's (`jungle`) or the classic field's.
static func build(level: Node3D, jungle: bool) -> Atmosphere:
	var a := Atmosphere.new()
	a.name = "Atmosphere"
	a._build(level, jungle)
	level.add_child(a)
	return a


func _build(level: Node3D, jungle: bool) -> void:
	var sky_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("cloud_noise", _cloud_noise())
	if jungle:
		sky_mat.set_shader_parameter("zenith", Color(0.22, 0.42, 0.7))
		sky_mat.set_shader_parameter("horizon", Color(0.68, 0.74, 0.76))
		# Below the horizon the sky is the haze over the far forest, so the land fades into it.
		sky_mat.set_shader_parameter("haze", Color(0.66, 0.71, 0.7))
		sky_mat.set_shader_parameter("ground", Color(0.5, 0.56, 0.52))
		sky_mat.set_shader_parameter("cloud_cover", 0.46)
	else:
		sky_mat.set_shader_parameter("zenith", Color(0.24, 0.42, 0.7))
		sky_mat.set_shader_parameter("horizon", Color(0.72, 0.75, 0.76))
		sky_mat.set_shader_parameter("haze", Color(0.62, 0.64, 0.62))
		sky_mat.set_shader_parameter("ground", Color(0.36, 0.34, 0.29))
		sky_mat.set_shader_parameter("cloud_cover", 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65 if jungle else 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# ACES: rich mid-tones, highlights (fire, flashes, the sun) rolling off to white instead of clipping.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 8.0
	# Ambient occlusion in the creases, and light bounced off what is lit onto what is round it.
	env.ssao_enabled = true
	env.ssao_radius = 2.0 if jungle else 1.5
	env.ssao_intensity = 2.0 if jungle else 1.6
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.1
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0
	if jungle:
		# The rivers and the lake mirror the forest and the sky (Forward+).
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 2.0
	# Bloom: wide and soft, only from what is brighter than white.
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.0
	for k in 7:
		env.set_glow_level(k, [0.0, 0.25, 0.6, 0.85, 0.9, 0.6, 0.3][k])
	# Haze: the distance fades into the sky's colour, glowing toward the sun.
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.71, 0.7) if jungle else Color(0.66, 0.69, 0.72)
	env.fog_density = 0.00045 if jungle else 0.0022
	env.fog_sun_scatter = 0.3
	env.fog_aerial_perspective = 0.35 if jungle else 0.6
	env.fog_sky_affect = 0.2 if jungle else 0.4
	# The air itself: sun shafts, and a halo round every fire, flash and blast (Forward+).
	env.volumetric_fog_enabled = true
	fog_density = 0.0045 if jungle else 0.0035
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.93)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	level.add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.65 if jungle else 1.6
	sun.rotation = Vector3(deg_to_rad(-48.0 if jungle else -44.0), deg_to_rad(35.0), 0)
	# Soft shadows that harden where they touch (the sun's disk is about half a degree across).
	sun.light_angular_distance = 0.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_max_distance = 420.0 if jungle else 320.0
	sun.directional_shadow_blend_splits = true
	sun.light_volumetric_fog_energy = 1.2
	level.add_child(sun)


## The volumetric fog follows the camera's height over the ground: thick down among the trees, thin from above.
func _process(_delta: float) -> void:
	if env == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var high := clampf((p.y - LevelBuilder.ground_height(p) - 4.0) / FOG_THIN_HEIGHT, 0.0, 1.0)
	var want := fog_density * lerpf(1.0, FOG_HIGH, high)
	env.volumetric_fog_density = lerpf(env.volumetric_fog_density, want, 0.1)


## The noise the clouds are drawn from (tiling).
static func _cloud_noise() -> NoiseTexture2D:
	if _clouds == null:
		var n := FastNoiseLite.new()
		n.seed = 99
		n.frequency = 0.008
		n.fractal_octaves = 5
		_clouds = NoiseTexture2D.new()
		_clouds.width = 512
		_clouds.height = 512
		_clouds.seamless = true
		_clouds.noise = n
	return _clouds
