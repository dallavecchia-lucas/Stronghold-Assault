class_name MuzzleFlash
extends Node3D
## A muzzle flash kept on a gun, for the guns that blink one on every round and want it on render layers of
## their own (a sniper's scope mustn't see her own flash a metre in front of it): a star of flame facing the
## camera and two crossed tongues of it jetting out along -Z, the way the barrel points. Added onto what is
## behind it, HDR, so it blooms. Its owner shows and hides it; place() puts it on the muzzle, turned and
## sized afresh for the next round. (FX.muzzle_flash is the fire-and-forget kind.)

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.24, 1.0);
uniform float energy = 6.0;
uniform float roll = 0.0;
uniform float star = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying vec2 q;
void vertex() {
	q = VERTEX.xy * 2.0;
	if (star > 0.5) {
		// The star faces the camera, its size kept.
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
		vec2 cs = vec2(cos(roll), sin(roll));
		VERTEX.xy = vec2(VERTEX.x * cs.x - VERTEX.y * cs.y, VERTEX.x * cs.y + VERTEX.y * cs.x);
	}
}
void fragment() {
	float r = length(q);
	float g;
	if (star > 0.5) {
		float a = atan(q.y, q.x);
		float rays = pow(abs(cos(a * 2.5)), 10.0) * pow(max(1.0 - r, 0.0), 1.5);
		g = rays * 1.2 + exp(-r * r * 9.0) * 1.3;
	} else {
		// A tongue of flame from the muzzle (q.y -1) to its tip (+1), faded where it is seen edge-on.
		float t = q.y * 0.5 + 0.5;
		float prof = sqrt(max(sin(3.14159 * t), 0.0)) * (1.0 - 0.45 * t);
		float n = texture(noise_tex, vec2(q.x * 0.2 + roll, t * 0.4 + roll * 0.37)).r;
		g = smoothstep(1.0, 0.2, abs(q.x) / max(prof, 0.001) + (n - 0.5) * 0.9) * (1.0 - 0.6 * t);
		g *= smoothstep(0.05, 0.45, abs(dot(NORMAL, VIEW)));
	}
	g *= 1.0 - smoothstep(0.9, 1.0, star > 0.5 ? r : 0.0);
	vec3 hot = mix(tint.rgb, vec3(1.0, 0.95, 0.85), clamp(g - 0.6, 0.0, 1.0));
	ALBEDO = hot * energy;
	ALPHA = clamp(g, 0.0, 1.0);
}
"""

static var _shader: Shader

## The star's size and the jet's length at scale 1 (m).
var size := 0.35
var length := 0.6

var _mats: Array[ShaderMaterial] = []
var _meshes: Array[MeshInstance3D] = []


func _init(p_size := 0.35, p_length := 0.6, color := Color(1.0, 0.6, 0.24), energy := 6.0) -> void:
	size = p_size
	length = p_length
	top_level = true
	visible = false
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	# The star, then the two tongues: quads standing along -Z, one flat and one on edge.
	for k in 3:
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("tint", color)
		mat.set_shader_parameter("energy", energy)
		mat.set_shader_parameter("star", 1.0 if k == 0 else 0.0)
		mat.set_shader_parameter("noise_tex", FX.noise_texture())
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if k == 0:
			mi.scale = Vector3.ONE * size
		else:
			var side := Vector3.RIGHT if k == 1 else Vector3.UP
			var flat := Vector3.UP if k == 1 else Vector3.LEFT
			mi.transform = Transform3D(Basis(side * size * 0.9, Vector3.FORWARD * length, flat), Vector3.FORWARD * length * 0.5)
		add_child(mi)
		_mats.append(mat)
		_meshes.append(mi)


## Draws it on these render layers only.
func set_layers(layers: int) -> void:
	for mi in _meshes:
		mi.layers = layers


## Puts it on the muzzle at `at`, the barrel along `dir`, turned and sized afresh (times `scale_k`).
func place(at: Vector3, dir: Vector3, scale_k := 1.0) -> void:
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(d, up).rotated(d, randf() * TAU)
	global_transform = Transform3D(b * Basis.from_scale(Vector3.ONE * scale_k * randf_range(0.8, 1.2)), at)
	var roll := randf() * TAU
	for m in _mats:
		m.set_shader_parameter("roll", roll)
