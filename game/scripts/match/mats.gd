class_name Mats
extends RefCounted
## Cached placeholder materials so the level looks decent before real art arrives.

static var _cache := {}


static func _noise_tex(freq: float, seed_val: int, dark: Color, light: Color, as_normal := false) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = freq
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = 6.0
	else:
		var g := Gradient.new()
		g.set_color(0, dark)
		g.set_color(1, light)
		tex.color_ramp = g
	return tex


static func _textured(key: String, dark: Color, light: Color, freq: float, uv_scale: float, roughness := 0.95) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(freq, key.hash(), dark, light)
	m.normal_enabled = true
	m.normal_texture = _noise_tex(freq * 2.0, key.hash() + 1, Color.BLACK, Color.WHITE, true)
	m.normal_scale = 0.6
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


static func ground() -> StandardMaterial3D:
	return _textured("ground", Color(0.22, 0.24, 0.14), Color(0.42, 0.40, 0.26), 0.02, 0.03)


static func stone() -> StandardMaterial3D:
	return _textured("stone", Color(0.36, 0.34, 0.31), Color(0.62, 0.59, 0.53), 0.03, 0.12)


static func dark_stone() -> StandardMaterial3D:
	return _textured("dark_stone", Color(0.18, 0.18, 0.2), Color(0.38, 0.37, 0.4), 0.03, 0.12)


static func wood() -> StandardMaterial3D:
	return _textured("wood", Color(0.22, 0.13, 0.07), Color(0.45, 0.29, 0.15), 0.08, 0.2)


static func rock() -> StandardMaterial3D:
	return _textured("rock", Color(0.25, 0.25, 0.25), Color(0.5, 0.49, 0.47), 0.05, 0.2)


static func flat(color: Color, metallic := 0.0, roughness := 0.7) -> StandardMaterial3D:
	var key := "flat_%s_%s_%s" % [color.to_html(), metallic, roughness]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		_cache[key] = m
	return _cache[key]


static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var key := "glow_%s_%s" % [color.to_html(), energy]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_cache[key] = m
	return _cache[key]


static func unshaded(color: Color, no_depth := false) -> StandardMaterial3D:
	var key := "unshaded_%s_%s" % [color.to_html(), no_depth]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = no_depth
		_cache[key] = m
	return _cache[key]


## Helper: a MeshInstance3D box with a material, positioned locally.
static func box_mesh(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	return mi


static func cylinder_mesh(radius: float, height: float, pos: Vector3, mat: Material, segments := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	return mi
