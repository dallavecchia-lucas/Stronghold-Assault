class_name ContactShadows
extends MeshInstance3D
## Ray-traced contact shadows from the sun, in screen space: for every pixel a ray is marched from the surface
## toward the sun through the depth buffer, and where something stands in its way the pixel's direct sunlight is
## taken off. The shadow maps are blurry at a distance and miss what is small; this catches it: the dark line
## where a foot, a wheel, a rock, a sandbag or a tree's roots meet the ground, the grass and the clutter shading
## each other, a unit's own creases.
##
## The march is done in the camera's own clip space (the ray's depth runs linearly across the screen toward
## the sun's vanishing point, so it is exact for a straight ray), compared by distance from the camera with a
## thickness, so the far side of a wall doesn't shadow what is behind it. Surfaces facing away from the sun are
## left alone (already dark), and it fades out with distance.
##
## A full-screen quad drawn before every other transparent thing, multiplying the scene's colour: it works with
## MSAA and under the smoke and fire drawn over it. Atmosphere hangs one on the level (Forward+ and Mobile).

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// Toward the sun (world).
uniform vec3 sun_dir = vec3(0.4, 0.75, 0.5);
// How much of a pixel's light the sun is: how dark its contact shadow goes.
uniform float strength = 0.62;
// How deep (m) something in the way is taken to be, and how far the march reaches (pixels at 1080p).
uniform float thickness = 0.5;
uniform float reach = 52.0;
// Beyond this (m) the shadow maps are left to it.
uniform float fade_far = 150.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float ndc_z(float d) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return d * 2.0 - 1.0;
#else
	return d;
#endif
}

// Distance from the camera (m) of what is at clip-space depth z.
float lin(float z, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(0.0, 0.0, z, 1.0);
	return -v.z / v.w;
}

void fragment() {
	float z0 = ndc_z(texture(depth_tex, SCREEN_UV).r);
	vec3 ndc0 = vec3(SCREEN_UV * 2.0 - 1.0, z0);
	vec4 vh = INV_PROJECTION_MATRIX * vec4(ndc0, 1.0);
	vec3 vp = vh.xyz / vh.w;
	float d0 = -vp.z;
	float shade = 0.0;
	float facing = 0.0;
	if (d0 > 0.0 && d0 < fade_far) {
		vec3 sun_v = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
		// The surface's normal from the depth around it, turned to face the camera.
		vec3 n = normalize(cross(dFdx(vp), dFdy(vp)));
		if (dot(n, vp) > 0.0) {
			n = -n;
		}
		facing = smoothstep(0.02, 0.3, dot(n, sun_v));
		if (facing > 0.0) {
			// The sun as a homogeneous point on the screen: toward it the ray runs, its depth changing linearly.
			vec4 L = PROJECTION_MATRIX * vec4(sun_v, 0.0);
			vec2 half_size = VIEWPORT_SIZE * 0.5;
			vec2 dh = (L.xy - ndc0.xy * L.w) * half_size;
			float len = length(dh);
			if (len > 0.00001) {
				vec2 dir = dh / len;
				float dz = (L.z - z0 * L.w) / len;
				// Beyond the sun's vanishing point the ray is at infinity.
				float end = L.w > 0.0 ? len / L.w : 1e9;
				float stride = reach * (VIEWPORT_SIZE.y / 1080.0) / 20.0;
				float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
				float bias = 0.02 + d0 * 0.004;
				float thick = thickness + d0 * 0.012;
				vec2 px = SCREEN_UV * VIEWPORT_SIZE;
				for (int i = 1; i <= 20; i++) {
					float s = (float(i) - jitter) * stride;
					vec2 q = px + dir * s;
					if (s > end || q.x < 0.0 || q.y < 0.0 || q.x >= VIEWPORT_SIZE.x || q.y >= VIEWPORT_SIZE.y) {
						break;
					}
					float ray = lin(z0 + dz * s, INV_PROJECTION_MATRIX);
					float scene = lin(ndc_z(texture(depth_tex, q / VIEWPORT_SIZE).r), INV_PROJECTION_MATRIX);
					float gap = ray - scene;
					if (gap > bias && gap < thick) {
						// Softer the further along the ray the blocker is.
						shade = 1.0 - pow(float(i) / 21.0, 2.0);
						break;
					}
				}
			}
		}
	}
	float k = strength * facing * shade * (1.0 - smoothstep(fade_far * 0.6, fade_far, d0));
	ALBEDO = vec3(1.0 - k);
}
"""

static var _shader: Shader

var _mat: ShaderMaterial


func _init(sun_dir := Vector3(0.4, 0.75, 0.5)) -> void:
	name = "ContactShadows"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mesh = quad
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	# Before every other transparent thing (the smoke, the fire, the water drawn over it).
	_mat.render_priority = -128
	_mat.set_shader_parameter("sun_dir", sun_dir.normalized())
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# It covers the screen wherever the camera is.
	extra_cull_margin = 16384.0
	ignore_occlusion_culling = true


## Points the shadows away from the sun along `dir` (toward the sun, world).
func set_sun(dir: Vector3) -> void:
	_mat.set_shader_parameter("sun_dir", dir.normalized())
