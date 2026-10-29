class_name SniperThermal
extends Node
## The Sniper's thermal sight (Sniper: T). While it is on and her camera is the one on screen, the land
## goes dark and cold (THERMAL: grey, at a low exposure, through an iron-bow palette from black through
## violet and red to yellow-white), every attacker glows white-hot (HOT on its model's meshes, hottest
## where it faces the camera) and the standing trees turn see-through and cold (FOLIAGE), so attackers
## stand out even in among the trees of a forest. It only changes how things look, on her screen: what
## it overrode goes back as it was the moment it is off (or another camera takes over the screen).

## Heat of an attacker's body (past white at the sight's exposure, so it blooms), and how much cooler its
## outline is than where it faces the camera.
const HEAT := 4.2
const RIM := 0.5
const HOT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float heat = 4.2;
uniform float rim = 0.5;
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = vec3(heat * mix(rim, 1.0, facing));
}
"""
## How often it looks for attackers that have come since and trees that have caught fire (s).
const SCAN := 0.2

## The Sniper's camera: the sight shows only while it is the one on screen.
var camera: Camera3D
## The sight is switched on (the Sniper's call); showing() says whether it shows right now.
var on := false

var _showing := false
var _env: Environment
var _hot: ShaderMaterial
var _foliage: StandardMaterial3D
## MeshInstance3D -> the material_override it had before.
var _overridden := {}
var _trees := {}
var _scan_cd := 0.0


func set_on(v: bool) -> void:
	on = v


## True while the land, the attackers and the trees look the thermal way.
func showing() -> bool:
	return _showing


func _process(delta: float) -> void:
	var want := on and camera != null and camera.is_inside_tree() and camera.current
	if want != _showing:
		_showing = want
		if want:
			_start()
		else:
			_stop()
	if not _showing:
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN
		_scan()


func _exit_tree() -> void:
	if _showing:
		_stop()


func _start() -> void:
	if _env == null:
		_build()
	camera.environment = _env
	_scan()


func _stop() -> void:
	_showing = false
	if camera and is_instance_valid(camera):
		camera.environment = null
	for mi in _overridden:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = _overridden[mi]
	_overridden.clear()
	_trees.clear()


## Attackers that have come since glow too; trees that have caught fire since are themselves again (they
## burn hot).
func _scan() -> void:
	for u in get_tree().get_nodes_in_group("attacker_units"):
		for mi in u.model_meshes():
			if not _overridden.has(mi):
				_overridden[mi] = mi.material_override
				mi.material_override = _hot
	for t in ForestTree.standing:
		if not _trees.has(t):
			_trees[t] = true
			for mi in t.find_children("*", "MeshInstance3D", true, false):
				if not _overridden.has(mi):
					_overridden[mi] = mi.material_override
					mi.material_override = _foliage
	for t in _trees.keys():
		if not is_instance_valid(t) or not t.is_standing():
			_trees.erase(t)
			if is_instance_valid(t):
				for mi in t.find_children("*", "MeshInstance3D", true, false):
					if _overridden.has(mi):
						mi.material_override = _overridden[mi]
						_overridden.erase(mi)


func _build() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.02, 0.03)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.6, 0.6)
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 0.3
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.03, 0.03, 0.05)
	_env.fog_density = 0.004
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.0
	_env.adjustment_contrast = 1.1
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.42, 0.62, 0.8, 0.92, 1.0])
	g.colors = PackedColorArray([Color(0.01, 0.01, 0.04), Color(0.1, 0.03, 0.22), Color(0.42, 0.06, 0.42),
			Color(0.85, 0.15, 0.2), Color(1.0, 0.55, 0.05), Color(1.0, 0.86, 0.3), Color(1.0, 1.0, 0.92)])
	var lut := GradientTexture1D.new()
	lut.gradient = g
	lut.width = 256
	_env.adjustment_color_correction = lut
	_hot = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = HOT_SHADER
	_hot.shader = sh
	_hot.set_shader_parameter("heat", HEAT)
	_hot.set_shader_parameter("rim", RIM)
	_foliage = StandardMaterial3D.new()
	_foliage.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foliage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foliage.albedo_color = Color(0.95, 0.95, 1.0, 0.26)
	_foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
	_foliage.disable_receive_shadows = true
