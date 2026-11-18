class_name MenuBackdrop
extends Node3D
## The title screen's 3D backdrop: the Earth seen from high orbit with a war raging on it, an alien
## mothership circling it, and the game's 3D title swivelling in front of the camera (MainMenu builds
## the 2D menu over it).
##
## The Earth holds still. Its war is in the red areas of its texture (conflict_earth, a Meshy model):
##   * those areas burn: an additive pass over the globe that flickers the red of the texture into
##     glowing fire, brighter on the night side;
##   * the hotspots (the red areas' clusters, found in the texture when the menu opens) flash with
##     explosions that throw a shockwave ring across the ground;
##   * missiles arc between hotspots, a glowing head with a fading trail, each ending in a flash.
## The mothership (stonebound_ark) circles on a tilted orbit, passing in front of the globe and
## behind it, its engines glowing red and a red light sweeping the clouds under it.

const EARTH_SCENE := "res://assets/menu/conflict_earth/conflict_earth.glb"
const ARK_SCENE := "res://assets/menu/stonebound_ark/stonebound_ark.glb"
const LOGO_SCENE := "res://assets/menu/title_logo/title_logo.glb"

## Radius of the globe in the scene (the model is about a unit across).
const EARTH_RADIUS := 3.0
## The globe's own turn (it never moves): the hotspots face the camera, a little to its left.
const EARTH_YAW := -18.0
const EARTH_TILT := 14.0
## Where the camera sits and what it looks at: the globe right of centre, room on the left for the menu.
const CAMERA_POS := Vector3(-3.6, 0.9, 16.5)
const CAMERA_TARGET := Vector3(-3.9, 0.35, 0.0)
const CAMERA_FOV := 38.0
## Toward the sun: low on the left and a little behind the globe, so the right of the disc is in night.
const SUN_DIR := Vector3(-0.85, 0.32, -0.12)

## The mothership: its orbit's radius, how long a lap takes (s), the orbit's tilt, its length.
const ARK_ORBIT := 4.9
const ARK_PERIOD := 95.0
const ARK_LENGTH := 1.5
## Where on its lap the menu finds it: just come round the globe's right limb, about to cross in front.
const ARK_START := 0.04

## The logo, in the camera's frame: its centre and width in the canvas's pixels (over MainMenu's
## menu column, whatever the window's shape), how far in front of the camera, and its swivel.
const LOGO_CENTER := Vector2(345.0, 212.0)
const LOGO_WIDTH := 560.0
const LOGO_DEPTH := 3.0
const LOGO_SWIVEL := 9.0  ## degrees each side
const LOGO_SWIVEL_PERIOD := 7.5  ## seconds a full swing

## Hotspots: how red a texel must be, how far apart clusters are (model units), how many to keep.
const HOT_CLUSTER := 0.075
const MAX_HOTSPOTS := 14

var camera: Camera3D
var earth: Node3D
var ark: Node3D
var logo_pivot: Node3D
## Each hotspot: {pos (world, on the ground), normal, weight, next (s until its next blast)}.
var hotspots: Array[Dictionary] = []

var _time := 0.0
var _sun_dir := SUN_DIR.normalized()
var _logo: Node3D
var _logo_light: DirectionalLight3D
var _ark_lights: Array[OmniLight3D] = []
var _ark_glows: Array[MeshInstance3D] = []
var _blasts: Array[Dictionary] = []  ## {flash, ring, age, life, size}
var _missiles: Array[Dictionary] = []  ## {a, b, t, dur, height}
var _missile_wait := 1.2
var _trails: ImmediateMesh
var _trail_inst: MeshInstance3D
var _flash_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _quad: QuadMesh


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_earth()
	_build_ark()
	_build_logo()
	_build_fx()
	_find_hotspots()
	# A few blasts already going when the menu opens.
	for h in hotspots:
		h.next = randf_range(0.1, 3.5)


## Where the mothership is (its centre, bow and stern, world space), and whether it is in sight (in
## front of the camera and not behind the globe). MainMenu's tracking reticle uses it.
func ark_on_screen() -> Dictionary:
	var p := ark.global_position
	var visible := not camera.is_position_behind(p) and not _behind_earth(p)
	var fwd := -ark.global_basis.z * ARK_LENGTH * 0.5
	return {"pos": p, "bow": p + fwd, "stern": p - fwd, "visible": visible,
		"distance": camera.global_position.distance_to(p)}


func _process(delta: float) -> void:
	_time += delta
	_update_logo()
	_update_ark()
	_update_hotspots(delta)
	_update_blasts(delta)
	_update_missiles(delta)


# --- scene ------------------------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _sky_shader()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.11, 0.13, 0.2)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	sun.light_cull_mask = 1
	add_child(sun)
	sun.look_at_from_position(_sun_dir * 20.0, Vector3.ZERO, Vector3.UP)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = 0.05
	camera.far = 200.0
	add_child(camera)
	camera.look_at_from_position(CAMERA_POS, CAMERA_TARGET, Vector3.UP)
	camera.current = true


func _build_earth() -> void:
	earth = Node3D.new()
	earth.name = "Earth"
	add_child(earth)
	earth.rotation_degrees = Vector3(EARTH_TILT, EARTH_YAW, 0.0)
	var model := (load(EARTH_SCENE) as PackedScene).instantiate() as Node3D
	earth.add_child(model)
	var mi := _first_mesh(model)
	var aabb := _model_aabb(model, mi)
	var size := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	model.scale = Vector3.ONE * (2.0 * EARTH_RADIUS / size)
	model.position = -(aabb.position + aabb.size * 0.5) * model.scale.x

	# The war: the texture's red areas, burning. An additive pass drawn over the globe.
	var mat := mi.get_active_material(0)
	var base := mat as BaseMaterial3D
	if base:
		var fire := ShaderMaterial.new()
		fire.shader = _fire_shader()
		fire.set_shader_parameter("albedo_tex", base.albedo_texture)
		fire.set_shader_parameter("sun_dir", _sun_dir)
		base = base.duplicate() as BaseMaterial3D
		base.roughness = 0.75
		base.metallic_specular = 0.35
		base.next_pass = fire
		mi.set_surface_override_material(0, base)

	# The atmosphere: a haze over the disc's edge and a halo around it, blue on the sunlit side.
	var haze := MeshInstance3D.new()
	var shell := SphereMesh.new()
	shell.radius = EARTH_RADIUS * 1.012
	shell.height = shell.radius * 2.0
	shell.radial_segments = 96
	shell.rings = 48
	haze.mesh = shell
	var haze_mat := ShaderMaterial.new()
	haze_mat.shader = _haze_shader()
	haze_mat.set_shader_parameter("sun_dir", _sun_dir)
	haze.material_override = haze_mat
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)

	# The halo beyond the limb: drawn on the inside of a wider shell, from how close each line of
	# sight passes to the globe (so it hugs the outline exactly, wherever the globe sits on screen).
	var halo := MeshInstance3D.new()
	var outer := SphereMesh.new()
	outer.radius = EARTH_RADIUS * 1.3
	outer.height = outer.radius * 2.0
	outer.radial_segments = 64
	outer.rings = 32
	halo.mesh = outer
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = _halo_shader()
	halo_mat.set_shader_parameter("radius", EARTH_RADIUS)
	halo_mat.set_shader_parameter("outer", EARTH_RADIUS * 1.3)
	halo_mat.set_shader_parameter("sun_dir", _sun_dir)
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)


func _build_ark() -> void:
	ark = Node3D.new()
	ark.name = "Mothership"
	add_child(ark)
	var model := (load(ARK_SCENE) as PackedScene).instantiate() as Node3D
	ark.add_child(model)
	var mi := _first_mesh(model)
	var aabb := _model_aabb(model, mi)
	var s := ARK_LENGTH / aabb.size.x
	model.scale = Vector3.ONE * s
	# The model's prow is its -X end: turn it to face -Z (the ark's forward), centred on its origin.
	model.rotation_degrees.y = -90.0
	model.position = Basis(Vector3.UP, deg_to_rad(-90.0)) * (-(aabb.position + aabb.size * 0.5) * s)
	var base := mi.get_active_material(0) as BaseMaterial3D
	if base:
		base = base.duplicate() as BaseMaterial3D
		base.albedo_color = Color(0.62, 0.6, 0.66)
		base.metallic = 0.55
		base.roughness = 0.5
		base.rim_enabled = true
		base.rim = 0.35
		base.rim_tint = 0.6
		mi.set_surface_override_material(0, base)

	var half := ARK_LENGTH * 0.5
	var radius := aabb.size.z * s * 0.5
	# Engines astern, glowing red-violet; running lights along the hull, slow and red.
	for side in [-1.0, 1.0]:
		_ark_glow(Vector3(side * radius * 0.45, 0.0, half * 1.02), 0.32, Color(1.0, 0.18, 0.12), 6.0)
	_ark_glow(Vector3(0.0, 0.0, half * 1.04), 0.5, Color(0.85, 0.1, 0.3), 3.0)
	_ark_glow(Vector3(0.0, radius * 0.9, -half * 0.55), 0.09, Color(1.0, 0.1, 0.05), 5.0)
	_ark_glow(Vector3(0.0, radius * 0.9, half * 0.2), 0.09, Color(1.0, 0.1, 0.05), 5.0)
	_ark_glow(Vector3(0.0, -radius * 0.7, -half * 0.95), 0.12, Color(1.0, 0.25, 0.1), 6.0)

	# A red light under the hull that sweeps the clouds as the ship passes over them.
	var under := OmniLight3D.new()
	under.light_color = Color(1.0, 0.15, 0.1)
	under.light_energy = 3.0
	under.omni_range = 2.6
	under.omni_attenuation = 1.4
	under.position = Vector3(0.0, -radius * 1.5, 0.0)
	ark.add_child(under)
	_ark_lights.append(under)
	var engine := OmniLight3D.new()
	engine.light_color = Color(1.0, 0.25, 0.2)
	engine.light_energy = 1.5
	engine.omni_range = 1.4
	engine.position = Vector3(0.0, 0.0, half * 1.2)
	ark.add_child(engine)
	_ark_lights.append(engine)


func _ark_glow(pos: Vector3, size: float, color: Color, energy: float) -> void:
	var g := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	g.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _glow_shader()
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("energy", energy)
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = pos
	ark.add_child(g)
	_ark_glows.append(g)


func _build_logo() -> void:
	# The logo rides in front of the camera on its own layer, lit by its own key light.
	logo_pivot = Node3D.new()
	camera.add_child(logo_pivot)
	_logo = (load(LOGO_SCENE) as PackedScene).instantiate() as Node3D
	logo_pivot.add_child(_logo)
	var mi := _first_mesh(_logo)
	var aabb := _model_aabb(_logo, mi)
	var center := aabb.position + aabb.size * 0.5
	_logo.set_meta("width", aabb.size.x)
	_logo.position = -center
	for m in _all_meshes(_logo):
		m.layers = 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var base := m.get_active_material(0) as BaseMaterial3D
		if base:
			base = base.duplicate() as BaseMaterial3D
			base.roughness = 0.55
			base.metallic_specular = 0.4
			m.set_surface_override_material(0, base)
	_logo_light = DirectionalLight3D.new()
	_logo_light.light_cull_mask = 2
	_logo_light.light_energy = 1.7
	_logo_light.light_color = Color(1.0, 0.97, 0.92)
	camera.add_child(_logo_light)
	_logo_light.rotation_degrees = Vector3(-18.0, -24.0, 0.0)
	var fill := DirectionalLight3D.new()
	fill.light_cull_mask = 2
	fill.light_energy = 0.6
	fill.light_color = Color(0.55, 0.7, 1.0)
	camera.add_child(fill)
	fill.rotation_degrees = Vector3(10.0, 150.0, 0.0)
	_place_logo()
	get_viewport().size_changed.connect(_place_logo)


func _place_logo() -> void:
	var view := get_viewport().get_visible_rect().size
	view.y = maxf(view.y, 1.0)
	var aspect := view.x / view.y
	var half_h := LOGO_DEPTH * tan(deg_to_rad(camera.fov) * 0.5)
	var ndc := Vector2(LOGO_CENTER.x / (view.x * 0.5) - 1.0, 1.0 - LOGO_CENTER.y / (view.y * 0.5))
	logo_pivot.position = Vector3(ndc.x * half_h * aspect, ndc.y * half_h, -LOGO_DEPTH)
	logo_pivot.scale = Vector3.ONE * (LOGO_WIDTH / view.y * 2.0 * half_h / float(_logo.get_meta("width")))


func _build_fx() -> void:
	_quad = QuadMesh.new()
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = _glow_shader()
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = _ring_shader()
	_trails = ImmediateMesh.new()
	_trail_inst = MeshInstance3D.new()
	_trail_inst.mesh = _trails
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.no_depth_test = false
	_trail_inst.material_override = tm
	_trail_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail_inst)


# --- hotspots -----------------------------------------------------------------------------------------

## The red areas of the globe's texture, clustered into hotspots (the triangles whose texels are red).
func _find_hotspots() -> void:
	var mi := _first_mesh(earth)
	var base := mi.get_active_material(0) as BaseMaterial3D
	if base == null or base.albedo_texture == null:
		return
	var img := base.albedo_texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	var points: Array = []  ## [redness, position]
	for t in range(0, idx.size(), 3):
		var uv := (uvs[idx[t]] + uvs[idx[t + 1]] + uvs[idx[t + 2]]) / 3.0
		var c := img.get_pixel(clampi(int(uv.x * w), 0, w), clampi(int(uv.y * h), 0, h))
		var red := c.r - maxf(c.g, c.b)
		if c.r > 0.7 and red > 0.35:
			points.append([red, (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0])
	points.sort_custom(func(a, b): return a[0] > b[0])
	var clusters: Array = []  ## [sum of positions, weight, count]
	for p in points:
		var placed := false
		for c in clusters:
			if (c[0] / c[2]).distance_to(p[1]) < HOT_CLUSTER:
				c[0] += p[1]
				c[1] += p[0]
				c[2] += 1
				placed = true
				break
		if not placed:
			clusters.append([p[1], p[0], 1])
	clusters.sort_custom(func(a, b): return a[1] > b[1])
	var xf := mi.global_transform
	var cam := camera.global_position
	for c in clusters.slice(0, MAX_HOTSPOTS):
		var world: Vector3 = xf * (c[0] / c[2])
		var n := world.normalized()
		var pos := n * EARTH_RADIUS
		# Only the hotspots on the camera's side of the globe get blasts (the far side is never seen).
		if n.dot((cam - pos).normalized()) < 0.12:
			continue
		hotspots.append({"pos": pos, "normal": n, "weight": float(c[1]), "next": 0.0})


func _update_hotspots(delta: float) -> void:
	for h in hotspots:
		h.next -= delta
		if h.next <= 0.0:
			# Bigger hotspots burst more often, sometimes in a quick string.
			var heavy := clampf(h.weight / 6.0, 0.0, 1.0)
			h.next = randf_range(0.5, 4.5) * lerpf(1.3, 0.55, heavy)
			_blast(_jitter(h.normal, 0.04), randf_range(0.1, 0.22) * lerpf(0.8, 1.3, heavy))
			if randf() < 0.3:
				h.next = randf_range(0.12, 0.3)


func _jitter(n: Vector3, amount: float) -> Vector3:
	return (n + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * amount).normalized()


## An explosion on the ground at `n` (unit normal): a flash and a shockwave ring.
func _blast(n: Vector3, size: float, color := Color(1.0, 0.55, 0.2)) -> void:
	var ground := n * EARTH_RADIUS
	var to_cam := (camera.global_position - ground).normalized()
	var flash := MeshInstance3D.new()
	flash.mesh = _quad
	flash.material_override = _flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	# Lifted toward the camera so the globe doesn't cut the glow in half.
	flash.position = ground + to_cam * size * 0.5
	flash.scale = Vector3.ONE * 0.001
	flash.set_instance_shader_parameter("tint_override", color)
	var ring := MeshInstance3D.new()
	ring.mesh = _quad
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	ring.look_at_from_position(ground + n * 0.01, ground + n, up)
	ring.scale = Vector3.ONE * 0.001
	_blasts.append({"flash": flash, "ring": ring, "age": 0.0, "life": randf_range(0.9, 1.4), "size": size})


func _update_blasts(delta: float) -> void:
	for i in range(_blasts.size() - 1, -1, -1):
		var b := _blasts[i]
		b.age += delta
		var k: float = b.age / b.life
		if k >= 1.0:
			b.flash.queue_free()
			b.ring.queue_free()
			_blasts.remove_at(i)
			continue
		# The flash pops in a tenth of its life and dies away; the ring spreads and fades.
		var pop := clampf(k / 0.08, 0.0, 1.0)
		var fade := pow(1.0 - k, 2.2)
		b.flash.scale = Vector3.ONE * b.size * lerpf(0.3, 1.0, pop) * (1.0 + k * 0.8)
		b.flash.set_instance_shader_parameter("fade", fade * (1.4 if k < 0.06 else 0.7))
		b.ring.scale = Vector3.ONE * b.size * (0.3 + 2.2 * sqrt(k))
		b.ring.set_instance_shader_parameter("fade", (1.0 - k) * pop)


# --- missiles -----------------------------------------------------------------------------------------

func _update_missiles(delta: float) -> void:
	_missile_wait -= delta
	if _missile_wait <= 0.0 and hotspots.size() >= 2:
		_missile_wait = randf_range(0.7, 2.6)
		var a: Dictionary = hotspots.pick_random()
		var b: Dictionary = hotspots.pick_random()
		if a != b and (a.normal as Vector3).angle_to(b.normal) < 0.9:
			var span: float = a.normal.angle_to(b.normal)
			_missiles.append({
				"a": a.normal, "b": _jitter(b.normal, 0.03), "t": 0.0,
				"dur": 1.8 + span * 4.0, "height": 0.06 + span * 0.45,
				"color": Color(1.0, 0.35, 0.15) if randf() < 0.65 else Color(1.0, 0.85, 0.5),
			})
	_trails.clear_surfaces()
	var cam := camera.global_position
	var drawing := false
	for i in range(_missiles.size() - 1, -1, -1):
		var m := _missiles[i]
		m.t += delta / m.dur
		if m.t >= 1.0:
			_blast(m.b, 0.26, Color(1.0, 0.7, 0.35))
			_missiles.remove_at(i)
			continue
		if not drawing:
			_trails.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drawing = true
		# The trail: a ribbon facing the camera from the launch (faded) to the head (bright).
		const STEPS := 22
		var tail := maxf(0.0, m.t - 0.45)
		var prev := _arc(m, tail)
		for s in range(1, STEPS + 1):
			var u := lerpf(tail, m.t, float(s) / STEPS)
			var p := _arc(m, u)
			var along := float(s) / STEPS
			var w0 := 0.012 + 0.018 * (along - 1.0 / STEPS)
			var w1 := 0.012 + 0.018 * along
			var dir := (p - prev).normalized()
			var side := dir.cross((cam - p).normalized()).normalized()
			var c0: Color = m.color * Color(1, 1, 1, pow(along - 1.0 / STEPS, 2.0))
			var c1: Color = m.color * Color(1, 1, 1, pow(along, 2.0))
			_quad_strip(prev - side * w0, prev + side * w0, p - side * w1, p + side * w1, c0, c1)
			prev = p
		# The head: a small bright diamond.
		var head := _arc(m, m.t)
		var right := (cam - head).normalized().cross(Vector3.UP).normalized() * 0.05
		var up := (cam - head).normalized().cross(right).normalized() * 0.05
		var hc := Color(2.5, 2.2, 1.6, 1.0)
		for q in [[right, up], [up, -right], [-right, -up], [-up, right]]:
			_trails.surface_set_color(hc)
			_trails.surface_add_vertex(head)
			_trails.surface_set_color(Color(hc, 0.0))
			_trails.surface_add_vertex(head + q[0])
			_trails.surface_set_color(Color(hc, 0.0))
			_trails.surface_add_vertex(head + q[1])
	if drawing:
		_trails.surface_end()


func _arc(m: Dictionary, u: float) -> Vector3:
	var n: Vector3 = (m.a as Vector3).slerp(m.b, u)
	return n * (EARTH_RADIUS + 0.02 + sin(u * PI) * m.height)


func _quad_strip(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, ca: Color, cb: Color) -> void:
	for v in [[a0, ca], [a1, ca], [b1, cb], [a0, ca], [b1, cb], [b0, cb]]:
		_trails.surface_set_color(v[1])
		_trails.surface_add_vertex(v[0])


# --- mothership & logo ----------------------------------------------------------------------------------

func _ark_orbit(phase: float) -> Vector3:
	var a := phase * TAU
	var p := Vector3(cos(a), 0.0, sin(a)) * ARK_ORBIT
	# Tilted so it dips low across the globe's near side (under the fighting) and climbs over its far side.
	return Basis(Vector3.RIGHT, deg_to_rad(15.0)) * Basis(Vector3.FORWARD, deg_to_rad(-8.0)) * p


func _update_ark() -> void:
	var phase := ARK_START + _time / ARK_PERIOD
	var p := _ark_orbit(phase)
	var ahead := _ark_orbit(phase + 0.002)
	var up := p.normalized()
	ark.look_at_from_position(p, ahead, up)
	# Rolled a little toward the globe, and wallowing slowly.
	ark.rotate_object_local(Vector3.FORWARD, deg_to_rad(-12.0 + sin(_time * 0.21) * 3.0))
	ark.rotate_object_local(Vector3.RIGHT, deg_to_rad(sin(_time * 0.17) * 1.5))
	var pulse := 0.75 + 0.25 * sin(_time * 1.3)
	_ark_lights[0].light_energy = 3.0 * pulse
	for i in _ark_glows.size():
		var g := _ark_glows[i]
		var k := pulse if i < 3 else (0.5 + 0.5 * sin(_time * 2.2 + i * 1.7))
		g.set_instance_shader_parameter("fade", k)


func _update_logo() -> void:
	var swing := sin(_time * TAU / LOGO_SWIVEL_PERIOD)
	logo_pivot.rotation = Vector3(
		deg_to_rad(sin(_time * TAU / (LOGO_SWIVEL_PERIOD * 1.7)) * 1.6),
		deg_to_rad(swing * LOGO_SWIVEL),
		deg_to_rad(sin(_time * TAU / (LOGO_SWIVEL_PERIOD * 2.3)) * 0.8))


func _behind_earth(p: Vector3) -> bool:
	# Does the line from the camera to `p` pass through the globe before reaching it?
	var o := camera.global_position
	var d := p - o
	var dist := d.length()
	d /= dist
	var b := o.dot(d)
	var c := o.length_squared() - EARTH_RADIUS * EARTH_RADIUS
	var disc := b * b - c
	if disc < 0.0:
		return false
	var t := -b - sqrt(disc)
	return t > 0.0 and t < dist


## The mesh's bounds in the model's own space (the glTF's nodes carry offsets of their own).
static func _model_aabb(model: Node3D, mi: MeshInstance3D) -> AABB:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != model and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf * mi.get_aabb()


static func _first_mesh(n: Node) -> MeshInstance3D:
	var all := _all_meshes(n)
	return all[0] if not all.is_empty() else null


static func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


# --- shaders ------------------------------------------------------------------------------------------

static func _sky_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type sky;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

vec3 star_layer(vec3 dir, float scale, float density, float size, float t) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float r = hash(cell);
	if (r > density) return vec3(0.0);
	vec3 centre = cell + 0.5 + (vec3(hash(cell + 11.1), hash(cell + 23.7), hash(cell + 37.3)) - 0.5) * 0.6;
	float d = length(p - centre);
	float b = exp(-d * d / (size * size));
	float twinkle = 0.75 + 0.25 * sin(t * (1.0 + r * 40.0) + r * 300.0);
	float temp = hash(cell + 5.5);
	vec3 col = mix(vec3(1.0, 0.78, 0.6), vec3(0.7, 0.82, 1.0), temp);
	return col * b * twinkle * (0.4 + 1.6 * hash(cell + 2.2));
}

void sky() {
	vec3 d = EYEDIR;
	// Nebula: a faint band of dust across the sky, violet and teal.
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 1.0, 0.45))) * 3.2, 2.0));
	float n = fbm(d * 3.0 + vec3(4.1));
	float n2 = fbm(d * 6.0 - vec3(2.7));
	vec3 neb = mix(vec3(0.16, 0.05, 0.22), vec3(0.03, 0.12, 0.2), n2) * smoothstep(0.35, 0.85, n) * (0.25 + band);
	vec3 col = vec3(0.004, 0.006, 0.014) + neb * 0.5;
	col += star_layer(d, 220.0, 0.10, 0.11, TIME) * (0.6 + band);
	col += star_layer(d, 90.0, 0.035, 0.09, TIME * 0.7) * 1.5;
	col += star_layer(d, 30.0, 0.025, 0.06, TIME * 0.5) * 3.0;
	// The sun is off screen to the left: a soft glare toward it.
	float sun = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += vec3(1.0, 0.85, 0.65) * (pow(sun, 24.0) * 0.12 + pow(sun, 400.0) * 1.5);
	COLOR = col;
}
"""
	return s


static func _fire_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 sun_dir;
uniform float intensity = 2.4;

varying vec3 world_n;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	VERTEX += NORMAL * 0.0015;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	// The red of the conflict zones (not the pale pinks of the deserts).
	float red = smoothstep(0.08, 0.42, c.r - max(c.g, c.b)) * smoothstep(0.5, 0.85, c.r);
	// Their white-hot cores.
	float core = smoothstep(0.82, 0.97, c.r) * smoothstep(0.55, 0.85, c.g) * red;
	float n1 = noise(UV * 160.0 + vec2(TIME * 0.6, -TIME * 0.35));
	float n2 = noise(UV * 420.0 - vec2(TIME * 1.4, TIME * 0.9));
	float flicker = 0.6 + 0.4 * sin(TIME * 6.0 + n1 * 14.0 + n2 * 6.0);
	float burn = red * (0.25 + 0.75 * n1 * n2 * 2.0) * flicker;
	float night = 1.0 - smoothstep(-0.3, 0.4, dot(world_n, sun_dir));
	float k = intensity * mix(0.55, 1.6, night);
	ALBEDO = (vec3(1.0, 0.28, 0.06) * burn + vec3(1.0, 0.7, 0.35) * pow(burn, 2.0) + vec3(1.0, 0.85, 0.6) * core * flicker) * k;
}
"""
	return s


static func _haze_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 sun_dir;
varying vec3 world_n;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float lit = smoothstep(-0.35, 0.6, dot(world_n, sun_dir));
	vec3 day = vec3(0.3, 0.6, 1.0);
	vec3 dusk = vec3(1.0, 0.45, 0.2);
	float edge = smoothstep(-0.35, 0.05, dot(world_n, sun_dir)) * (1.0 - smoothstep(0.05, 0.4, dot(world_n, sun_dir)));
	vec3 col = mix(day, dusk, edge * 0.6);
	ALBEDO = col * (pow(rim, 3.0) * 0.55 + pow(rim, 8.0) * 0.9) * lit + vec3(0.2, 0.45, 1.0) * 0.03 * lit;
}
"""
	return s


static func _halo_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_front, shadows_disabled, fog_disabled;

uniform float radius = 3.0;
uniform float outer = 3.9;
uniform vec3 sun_dir;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 d = normalize(world_pos - cam);
	vec3 closest = cam + d * dot(centre - cam, d);
	float h = length(closest - centre) / radius;
	if (h < 1.0) discard;
	float x = h - 1.0;
	float glow = exp(-x * 45.0) * 0.9 + exp(-x * 10.0) * 0.2;
	glow *= 1.0 - smoothstep(outer / radius * 0.8, outer / radius, h);
	float lit = smoothstep(-0.55, 0.75, dot(normalize(closest - centre), sun_dir));
	ALBEDO = mix(vec3(0.05, 0.1, 0.35), vec3(0.35, 0.65, 1.0), lit) * glow * (0.12 + 1.1 * lit);
}
"""
	return s


static func _glow_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float energy = 3.0;
instance uniform vec4 tint_override : source_color = vec4(0.0);
instance uniform float fade = 1.0;

void vertex() {
	// Billboard, keeping the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = exp(-d * d * 40.0);
	float glow = exp(-d * d * 9.0) * (1.0 - smoothstep(0.7, 1.0, d));
	vec3 c = tint_override.a > 0.0 ? tint_override.rgb : tint.rgb;
	ALBEDO = (c * glow + mix(c, vec3(1.0, 0.95, 0.85), 0.7) * core) * energy * fade;
}
"""
	return s


static func _ring_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float fade = 1.0;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = exp(-pow((d - 0.84) * 12.0, 2.0)) + exp(-d * d * 6.0) * 0.12;
	ALBEDO = vec3(1.0, 0.5, 0.2) * ring * fade * 0.8 * (1.0 - smoothstep(0.95, 1.0, d));
}
"""
	return s
