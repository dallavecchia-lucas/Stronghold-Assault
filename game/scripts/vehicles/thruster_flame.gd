class_name ThrusterFlame
extends Node3D
## A jet of flame out of a nozzle: hang it on an exhaust marker (it points along the marker's +Z). A cone of glow,
## added onto what is behind it, white-hot at the nozzle and running out to the flame's colour and nothing at its tip,
## brightest down its middle; it flickers, and its length and brightness follow `power` (0: out, 1: full; above 1, an
## afterburner: longer, and its colour runs from `color` toward `burner_color`). A light of the flame's colour goes
## with it when `light_range` is set.

## The flame at full power: its length and its radius at the nozzle (m).
@export var length := 2.0
@export var radius := 0.4
## Its colour (HDR: above 1 blooms) and the afterburner's.
@export var color := Color(0.5, 0.8, 2.4)
@export var burner_color := Color(2.4, 1.1, 0.4)
## Light thrown round the nozzle at full power (m; 0: none).
@export var light_range := 0.0
## 0: out, 1: full thrust, up to 2: afterburner.
var power := 0.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.5, 0.8, 2.4, 1.0);
uniform float strength = 1.0;
uniform float seed = 0.0;
varying float along;
void vertex() {
	// The cone runs along its own Y from the nozzle (-0.5, its wide end) to the tip (+0.5): 1 at the nozzle, 0 at the tip.
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
}
void fragment() {
	float core = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float flick = 0.85 + 0.15 * sin(TIME * 47.0 + seed * 13.0) * sin(TIME * 31.0 + seed * 7.0 + UV.y * 9.0);
	float fade = pow(along, 1.4);
	vec3 hot = mix(tint.rgb, vec3(2.4, 2.3, 2.1), pow(along, 5.0));
	ALBEDO = hot * core * fade * flick * strength;
	ALPHA = clamp(core * fade * strength, 0.0, 1.0);
}
"""

static var _shader: Shader

var _cone: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _flicker := 0.0


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_cone = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 16
	c.rings = 4
	c.cap_top = false
	c.cap_bottom = false
	_cone.mesh = c
	_cone.rotation.x = PI * 0.5  # its Y (nozzle to tip) along the marker's +Z
	_cone.position.z = 0.5
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_cone.material_override = _mat
	var holder := Node3D.new()
	holder.name = "Cone"
	add_child(holder)
	holder.add_child(_cone)
	if light_range > 0.0:
		_light = OmniLight3D.new()
		_light.shadow_enabled = false
		_light.omni_range = light_range
		_light.position.z = length * 0.3
		add_child(_light)
	_apply()


func _process(delta: float) -> void:
	_flicker = randf_range(0.92, 1.08) if Engine.get_frames_drawn() % 2 == 0 else _flicker
	_apply()


func _apply() -> void:
	var p := clampf(power, 0.0, 2.0)
	var burner := clampf(p - 1.0, 0.0, 1.0)
	var on := minf(p, 1.0)
	var holder := get_node("Cone") as Node3D
	holder.visible = p > 0.01
	var len := length * (0.35 + 0.65 * on + 0.8 * burner) * (_flicker if _flicker > 0.0 else 1.0)
	var r := radius * (0.7 + 0.3 * on + 0.15 * burner)
	holder.scale = Vector3(r, r, len)
	var col := color.lerp(burner_color, burner)
	_mat.set_shader_parameter("tint", col)
	_mat.set_shader_parameter("strength", 0.25 + 0.75 * on + 0.4 * burner)
	if _light:
		_light.visible = p > 0.01
		_light.light_color = Color(col.r, col.g, col.b).clamp(Color(0, 0, 0), Color(1, 1, 1))
		_light.light_energy = (0.6 + 1.2 * on + 1.5 * burner) * (_flicker if _flicker > 0.0 else 1.0)
		_light.omni_range = light_range * (0.6 + 0.4 * on + 0.4 * burner)
