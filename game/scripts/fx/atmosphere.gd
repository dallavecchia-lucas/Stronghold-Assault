class_name Atmosphere
extends Node
## A map's light and air: the sky, the sun, the haze, and how the camera renders it all.
##
## The sky is drawn by a shader: deep blue overhead paling to a bright haze at the horizon, the haze over the
## far land below it (the colour of the fog, so the land fades into the sky), a warm glow round the sun and its
## blooming disk. The sun is warm, its shadows soft (they harden where they touch) over four cascades. ACES tone
## mapping with a broad bloom: what is brighter than white (the sun, fire, muzzle flashes, explosions) glows.
## Ambient occlusion darkens the creases, screen-space indirect light bounces colour (and a blast's glare) onto
## what is round it, and volumetric fog fills the air: the sun's shafts through the canopy, a halo round every
## fire and blast. The fog thins as the camera climbs, so the strategy view stays clear.
##
## Ray-traced (GameConfig.lighting, the default; Forward+), on top of that:
## - Global illumination (SDFGI): the scene is kept as a signed distance field round the camera and rays are
##   marched through it, so light bounces: sunlit ground lights the walls and the undersides of things, the
##   canopy shuts the sky out of the forest floor, the tunnels and gun decks darken inside, and every blast's
##   and fire's light bounces off what is round it. The fog is lit by the bounced light too. Only the map's
##   scenery is in the field: units, the garrison, shells, effects (anything that moves) are lit by it but kept
##   out of it, so they leave no ghosts behind.
## - Contact shadows (ContactShadows): a ray marched toward the sun from every pixel through the depth buffer,
##   the crisp shadow where things meet the ground that the shadow maps blur.
## - Volumetric clouds: ray-marched through a layer of 3D noise a kilometre up, each step lit by a few more
##   steps toward the sun: cumulus with dark bellies and bright tops, lined silver against the sun, fading into
##   the haze at the horizon (at half resolution).
## - Reflections ray-marched in screen space (the rivers, the lake, wet and shiny metal), the rest from the
##   distance field; softer, finer shadow filtering.
## Standard lighting keeps the rest (and flat, painted clouds).
##
## Atmosphere.build(level, jungle) adds the WorldEnvironment and the sun to `level` (as its own children: the
## showcases look for them there) and itself, to keep the fog right for the camera.

const SKY_SHADER := """
shader_type sky;
render_mode use_half_res_pass;
uniform vec4 zenith : source_color = vec4(0.24, 0.42, 0.7, 1.0);
uniform vec4 horizon : source_color = vec4(0.72, 0.75, 0.76, 1.0);
uniform vec4 haze : source_color = vec4(0.62, 0.64, 0.62, 1.0);
uniform vec4 ground : source_color = vec4(0.36, 0.34, 0.29, 1.0);
uniform float sun_disk_scale = 3.0;
uniform float cloud_cover = 0.44;
// The flat clouds (standard lighting).
uniform float cloud_scale = 0.55;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
// The volumetric clouds (ray-traced lighting): the layer they fill (m up), how thick they are (per m), the noise
// they are shaped and eroded by.
uniform bool volumetric = false;
uniform float cloud_bottom = 900.0;
uniform float cloud_top = 2300.0;
uniform float cloud_density = 0.026;
uniform sampler3D cloud_shape : filter_linear, repeat_enable;
uniform sampler3D cloud_detail : filter_linear, repeat_enable;

float clouds_at(vec2 uv) {
	return texture(cloud_noise, uv * 0.35).r * 0.6 + texture(cloud_noise, uv * 1.1 + vec2(0.3)).r * 0.3
			+ texture(cloud_noise, uv * 3.3 + vec2(0.7)).r * 0.1;
}

// How thick the cloud is at `p` (per m): big shapes, rounded at the base and thinning at the top, their edges
// eaten away by the detail noise.
float cloud_at(vec3 p, bool detail) {
	float h = clamp((p.y - cloud_bottom) / (cloud_top - cloud_bottom), 0.0, 1.0);
	float profile = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.4, 1.0, h));
	float thr = 0.66 - cloud_cover * 0.3;
	float d = (texture(cloud_shape, p / 4200.0).r * profile - thr) / (1.0 - thr);
	if (detail) {
		d -= texture(cloud_detail, p / 1100.0).r * 0.16;
	}
	return max(d, 0.0) * cloud_density;
}

// How much light scatters toward the eye at angle cos `c` off the light (Henyey-Greenstein).
float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5) / (4.0 * PI);
}

// Marches the view ray `d` through the cloud layer: each step's light is the sun's, dimmed by the cloud between
// it and the sun (a few steps toward it), plus the sky's; the march stops once nothing gets through. Returns the
// light it gathered (premultiplied) and how much of the sky behind it is hidden.
vec4 march_clouds(vec3 d, vec3 sun_dir, vec3 sun, vec2 uv) {
	if (d.y < 0.03) {
		return vec4(0.0);
	}
	float t0 = cloud_bottom / d.y;
	float t1 = min(cloud_top / d.y, t0 + 5000.0);
	float dt = (t1 - t0) / 22.0;
	float mu = dot(d, sun_dir);
	// A softer forward lobe than real droplets' (the eye adapts; a camera's sky would clip): the clouds round the
	// sun get about three times the light, not eight, so they glow there instead of blowing out flat white.
	float phase = (hg(mu, 0.5) * 0.55 + hg(mu, -0.15) * 0.45) * 0.8 * 4.0 * PI;
	vec3 sky_light = mix(horizon.rgb, zenith.rgb, 0.45);
	float dither = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453) * 0.7;
	float trans = 1.0;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 22; i++) {
		vec3 p = d * (t0 + (float(i) + dither) * dt);
		float rho = cloud_at(p, true);
		if (rho > 0.00001) {
			float od = 0.0;
			for (int j = 1; j <= 3; j++) {
				od += cloud_at(p + sun_dir * (float(j) * 150.0), false) * 150.0;
			}
			float h = clamp((p.y - cloud_bottom) / (cloud_top - cloud_bottom), 0.0, 1.0);
			// Beer's law toward the sun, darkened a little where the cloud is thin (the "powder" look).
			float powder = 0.6 + 0.4 * (1.0 - exp(-od * 2.0 - 0.15));
			vec3 lit = sun * exp(-od) * powder * phase + sky_light * (0.35 + 0.65 * h);
			float a = exp(-rho * dt);
			acc += trans * (1.0 - a) * lit;
			trans *= a;
			if (trans < 0.02) {
				break;
			}
		}
	}
	float cov = 1.0 - trans;
	// Far off, the haze takes them.
	float far = 1.0 - exp(-t0 / 14000.0);
	vec3 c = mix(acc, horizon.rgb * cov, far * 0.85);
	return vec4(c, cov) * smoothstep(0.03, 0.16, d.y);
}

void sky() {
	vec3 d = EYEDIR;
	if (AT_HALF_RES_PASS) {
		if (volumetric && LIGHT0_ENABLED) {
			vec4 c = march_clouds(d, LIGHT0_DIRECTION, LIGHT0_COLOR * LIGHT0_ENERGY, SCREEN_UV);
			COLOR = c.rgb;
			ALPHA = c.a;
		} else {
			COLOR = vec3(0.0);
			ALPHA = 0.0;
		}
	} else {
		float h = d.y;
		// Deep blue overhead, paling to the haze at the horizon; below it, the haze over the far land.
		vec3 col = mix(horizon.rgb, zenith.rgb, pow(clamp(h, 0.0, 1.0), 0.5));
		vec3 below = mix(haze.rgb, ground.rgb, smoothstep(0.0, 0.4, -h));
		col = mix(col, below, smoothstep(0.0, -0.03, h));
		float disk = 0.0;
		vec3 sun = vec3(0.0);
		if (LIGHT0_ENABLED) {
			sun = LIGHT0_COLOR * LIGHT0_ENERGY;
			float sd = dot(d, LIGHT0_DIRECTION);
			float s = max(sd, 0.0);
			float up = smoothstep(-0.25, 0.05, h);
			// The air glows round the sun: a broad warm halo and a tight bright one; the horizon warms toward it.
			col += sun * (pow(s, 6.0) * 0.16 + pow(s, 48.0) * 0.45) * up;
			col *= mix(vec3(1.0), vec3(1.12, 1.0, 0.86), pow(s, 3.0) * (1.0 - clamp(h * 2.0, 0.0, 1.0)) * 0.6);
			float r = max(LIGHT0_SIZE * 0.5, 0.0045) * sun_disk_scale;
			disk = 1.0 - smoothstep(r * 0.8, r, acos(clamp(sd, -1.0, 1.0)));
			if (!volumetric && h > 0.0) {
				// Flat clouds on a plane overhead: lit from the sun's side, shadowed under, fading into the haze.
				vec2 uv = d.xz / (h + 0.18) * cloud_scale;
				float n = clouds_at(uv);
				float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n) * smoothstep(0.0, 0.16, h);
				vec2 toward = normalize(LIGHT0_DIRECTION.xz + vec2(0.0001)) * 0.035;
				float shade = clamp(0.62 + (n - clouds_at(uv + toward)) * 4.5, 0.25, 1.0);
				vec3 lit = (vec3(0.55) + LIGHT0_COLOR * 0.45) * LIGHT0_ENERGY * 0.82 + horizon.rgb * 0.15;
				vec3 dark = mix(horizon.rgb, zenith.rgb, 0.5) * 0.68;
				vec3 cloud = mix(dark, lit, shade);
				cloud += sun * pow(s, 10.0) * (1.0 - smoothstep(0.0, 0.6, cov)) * 1.2;
				col = mix(col, cloud, cov * 0.92);
				disk *= 1.0 - cov;
			}
		}
		if (volumetric) {
			col = col * (1.0 - HALF_RES_COLOR.a) + HALF_RES_COLOR.rgb;
			disk *= 1.0 - HALF_RES_COLOR.a;
		}
		// The sun's disk only where the sky itself is seen: in the reflections (the radiance map) the sun's own light
		// already makes its glint, and a disk thirty times the sky's brightness there would be mirrored a second
		// time by every glossy, wet or watery surface, a white-hot speck the bloom swells into a ball.
		COLOR = col + (AT_CUBEMAP_PASS ? vec3(0.0) : sun * disk * 30.0);
	}
}
"""

## How thick the volumetric fog is with the camera on the ground, and the share of it left once the camera is
## FOG_THIN_HEIGHT (m) up.
const FOG_THIN_HEIGHT := 40.0
const FOG_HIGH := 0.2

var env: Environment
var sun: DirectionalLight3D
var contact_shadows: ContactShadows
var fog_density := 0.004
## The ray-traced lighting is on (GameConfig.lighting, on a renderer that has it).
var raytraced := false

var _level: Node
var _gi := false
var _pending: Array = []  # GeometryInstance3Ds added since the last frame (some may be gone already)

static var _clouds: NoiseTexture2D
static var _cloud_shape: NoiseTexture3D
static var _cloud_detail: NoiseTexture3D


## Lights `level`: the Jungle Keep's (`jungle`) or the classic field's.
static func build(level: Node3D, jungle: bool) -> Atmosphere:
	var a := Atmosphere.new()
	a.name = "Atmosphere"
	a._build(level, jungle)
	level.add_child(a)
	return a


func _build(level: Node3D, jungle: bool) -> void:
	_level = level
	var method := RenderingServer.get_current_rendering_method()
	raytraced = GameConfig.lighting != "standard" and method != "gl_compatibility"
	_gi = raytraced and method == "forward_plus"

	var sky_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("cloud_noise", _cloud_noise())
	sky_mat.set_shader_parameter("volumetric", raytraced)
	if raytraced:
		sky_mat.set_shader_parameter("cloud_shape", _cloud_shape_noise())
		sky_mat.set_shader_parameter("cloud_detail", _cloud_detail_noise())
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
	if jungle or raytraced:
		# Reflections ray-marched through the depth buffer: the rivers and the lake mirror the forest and the sky,
		# metal and wet stone catch what is round them.
		env.ssr_enabled = true
		env.ssr_max_steps = 64 if raytraced else 48
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.25
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
	env.fog_density = 0.00045 if jungle else 0.0015
	env.fog_sun_scatter = 0.3
	env.fog_aerial_perspective = 0.35 if jungle else 0.6
	env.fog_sky_affect = 0.2 if jungle else 0.4
	# The air itself: sun shafts, and a halo round every fire, flash and blast (Forward+).
	env.volumetric_fog_enabled = true
	fog_density = 0.0036 if jungle else 0.0035
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.93)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	if _gi:
		_global_illumination(jungle)
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
	# Finer filtering of the soft shadows (the sun's and the blasts' lights'), set for every map (soft low is the
	# default).
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH if raytraced else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if raytraced else RenderingServer.SHADOW_QUALITY_SOFT_LOW)

	if raytraced:
		# Toward the sun: the light shines down its -Z.
		contact_shadows = ContactShadows.new(sun.basis.z)
		level.add_child(contact_shadows)


## SDFGI: light bounced off the scenery, the sky shut out where the scenery covers it, rays marched through a
## distance field of it kept round the camera in cascades out to a few hundred metres.
func _global_illumination(jungle: bool) -> void:
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 5 if jungle else 4
	env.sdfgi_min_cell_size = 0.3 if jungle else 0.2
	# The maps are wide and low: half the cells up and down.
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT if jungle else Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.15
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1
	# The fog is lit by the bounced light too.
	env.volumetric_fog_gi_inject = 1.0
	# More rays per probe, settling in a third of a second, the lights (blasts, fires) caught every other frame.
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_2_FRAMES)


func _ready() -> void:
	if _gi:
		# Whatever moves is lit by the GI but kept out of its distance field (see _classify).
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_pending.append(node)


## The map's own scenery (under the level, not skinned, not something that can be hurt but its gates and keep)
## stays in the GI's distance field; anything else (units, the garrison, the guns, shells, effects, the bridges)
## is lit by it only: the field isn't redrawn when they move, so in it they would leave dark ghosts behind. What
## casts no shadow (the undergrowth, the water, the far land) is lit by it only too: too thin or too far to
## matter to the light, and the field is rebuilt round the camera as it moves, so less in it is quicker.
func _classify(g: GeometryInstance3D) -> void:
	if g.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
		return
	if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		g.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		return
	var n := g.get_parent()
	while n != null:
		if n == _level:
			return
		if n is Skeleton3D or (n.is_in_group("damageable") and not n.is_in_group("structures")):
			break
		n = n.get_parent()
	g.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		for g in _pending:
			if is_instance_valid(g) and (g as Node).is_inside_tree():
				_classify(g as GeometryInstance3D)
		_pending.clear()
	# The volumetric fog follows the camera's height over the ground: thick down among the trees, thin from above.
	if env == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var high := clampf((p.y - LevelBuilder.ground_height(p) - 4.0) / FOG_THIN_HEIGHT, 0.0, 1.0)
	var want := fog_density * lerpf(1.0, FOG_HIGH, high)
	env.volumetric_fog_density = lerpf(env.volumetric_fog_density, want, 0.1)


## The noise the flat clouds are drawn from (tiling).
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


## The volumetric clouds' big shapes: a tiling block of rolling noise, about three clouds across.
static func _cloud_shape_noise() -> NoiseTexture3D:
	if _cloud_shape == null:
		var n := FastNoiseLite.new()
		n.seed = 314
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.045
		n.fractal_octaves = 4
		_cloud_shape = NoiseTexture3D.new()
		_cloud_shape.width = 64
		_cloud_shape.height = 64
		_cloud_shape.depth = 64
		_cloud_shape.seamless = true
		_cloud_shape.noise = n
	return _cloud_shape


## What eats their edges into billows: cellular noise (the distance to the nearest cell's centre).
static func _cloud_detail_noise() -> NoiseTexture3D:
	if _cloud_detail == null:
		var n := FastNoiseLite.new()
		n.seed = 2718
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.frequency = 0.125
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		_cloud_detail = NoiseTexture3D.new()
		_cloud_detail.width = 32
		_cloud_detail.height = 32
		_cloud_detail.depth = 32
		_cloud_detail.seamless = true
		_cloud_detail.noise = n
	return _cloud_detail
