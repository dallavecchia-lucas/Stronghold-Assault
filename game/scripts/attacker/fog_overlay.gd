class_name FogOverlay
extends MeshInstance3D
## The fog of war on the attacking player's screen (AttackerVision): a full-screen pass that finds
## the ground (or rock, or deck) under every pixel from the depth buffer and darkens it beyond what
## the army sees, the edge of sight softening over EDGE metres. Drawn before every other
## see-through thing, so health bars, rings, aim previews and ping marks stay bright over it.

## Most viewers the shader takes (AttackerCommander.UNIT_CAP, and the helipads).
const MAX_VIEWERS := 64
const EDGE := 5.0
const SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 viewers[64];
uniform int count = 0;
uniform float edge = 5.0;
uniform vec3 tint : source_color = vec3(0.03, 0.04, 0.06);
uniform float dim = 0.68;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	bool sky = depth >= 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	bool sky = depth <= 0.0;
#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	world.xyz /= world.w;
	float seen = 0.0;
	for (int i = 0; i < count; i++) {
		float d = distance(world.xz, viewers[i].xy);
		seen = max(seen, 1.0 - smoothstep(viewers[i].z - edge, viewers[i].z, d));
	}
	if (sky) {
		seen = 1.0;
	}
	ALBEDO = tint;
	ALPHA = (1.0 - seen) * dim;
}
"""

static var _shader: Shader

var vision: AttackerVision

var _mat: ShaderMaterial
var _data := PackedVector4Array()


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mesh = q
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	_mat.set_shader_parameter("edge", EDGE)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0  # it covers the screen wherever it is
	_data.resize(MAX_VIEWERS)


func _process(_delta: float) -> void:
	var n := mini(vision.viewers.size(), MAX_VIEWERS)
	for i in n:
		var v: Array = vision.viewers[i]
		var at: Vector3 = v[0]
		_data[i] = Vector4(at.x, at.z, v[1], 0.0)
	_mat.set_shader_parameter("viewers", _data)
	_mat.set_shader_parameter("count", n)
