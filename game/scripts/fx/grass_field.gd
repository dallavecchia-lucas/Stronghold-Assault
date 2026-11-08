class_name GrassField
extends MultiMeshInstance3D
## Grass: blades standing on the ground round the camera, where the ground is grass.
##
## A grid of GRID x GRID clumps, CELL apart, moves with the camera a cell at a time; the vertex shader places
## each clump in its world cell (a hash of the cell picks its spot, its turn, its size, so the grass stays put as
## the grid moves), its blades spread over the cell so the field has no tufts, on the ground's height (a height
## map on the Jungle Keep, the flat field on the classic map), and only where the ground is grass: not on the
## tracks worn up the lanes, the bare patches, the scree, the banks and the water, the rock, or under a helipad's
## deck. Where the grass gives out it thins blade by blade, the last ones shorter. The blades sway in gusts of
## wind, lighter toward the tip, drier where the ground's grass is sun-dried, a few dead and straw-coloured, the
## light shining through them and a sheen on them. They thin away toward the grid's edge (the ground's texture
## carries on), and the field is hidden once the camera is high enough that blades would be specks. The CPU only
## moves the grid; on the GPU only the clumps in the field and in sight are worked out, the rest fold to nothing
## at once.

## Clumps a side, metres between them, how far out they fade. Half as many with the standard lighting; `-- --grass=0.3`
## thins the field further (for renders on a software GPU): fewer clumps over the same ground, farther apart.
const GRID := 170
const CELL := 0.55
const FADE := [26.0, 44.0]
## Blades a clump.
const BLADES := 40
## Hidden above this height over the ground (m).
const MAX_VIEW_HEIGHT := 34.0

const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;

uniform vec2 center = vec2(0.0);
uniform float cell = 0.55;
uniform int grid = 170;
uniform vec2 fade = vec2(26.0, 44.0);
uniform float blade_height = 0.42;
uniform vec3 root_color = vec3(0.065, 0.1, 0.028);
uniform vec3 tip_color = vec3(0.11, 0.18, 0.045);
uniform vec3 dry_color = vec3(0.2, 0.19, 0.07);
uniform vec3 dead_color = vec3(0.3, 0.25, 0.14);
uniform vec2 wind = vec2(0.8, 0.45);
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
// The Jungle Keep: its heights and its splat (g: grass) over the square at map_origin, map_size across.
uniform bool jungle = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform float map_size = 1.0;
uniform float water_y = -10000.0;
// The classic field: its tracks (from xz, to xz) and the mountain's half width.
uniform vec4 lanes[4];
uniform int lane_count = 0;
uniform float mountain_half = 0.0;
// No grass under these (centre xz, half size xz; yaw in lots_yaw).
uniform vec4 lots[8];
uniform float lots_yaw[8];
uniform int lot_count = 0;

varying float v_t;
varying vec3 v_col;
varying float v_dry;
varying float v_dead;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float lane_distance(vec2 p) {
	float d = 1e9;
	for (int i = 0; i < 4; i++) {
		if (i >= lane_count) {
			break;
		}
		vec2 a = lanes[i].xy;
		vec2 b = lanes[i].zw;
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
		d = min(d, length(p - (a + ab * t)));
	}
	return d;
}

float ground_height(vec2 p) {
	if (!jungle) {
		return 0.0;
	}
	return texture(height_map, (p - map_origin) / map_size).r;
}

void vertex() {
	int ix = INSTANCE_ID % grid;
	int iz = INSTANCE_ID / grid;
	vec2 origin = floor(center / cell) * cell;
	vec2 cp = origin + (vec2(float(ix), float(iz)) - float(grid) * 0.5) * cell;
	float h1 = hash(cp);
	float h2 = hash(cp + vec2(17.3, 5.1));
	float h3 = hash(cp + vec2(3.7, 29.9));
	float h4 = hash(cp + vec2(41.2, 11.6));
	vec2 p = cp + vec2(h1, h2) * cell;
	float gy = ground_height(p);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(vec3(p.x, gy, p.y) - cam);
	// Only the clumps in the field and in sight are worked out (most of the grid is neither); the rest fold to
	// nothing.
	float reach = cell * 0.62 + 1.0;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p.x, gy + 0.4, p.y, 1.0));
	bool seen = dist < fade.y + reach && clip.w > -reach
			&& abs(clip.x) < clip.w + reach * abs(PROJECTION_MATRIX[0][0])
			&& abs(clip.y) < clip.w + reach * abs(PROJECTION_MATRIX[1][1]);
	float keep = 0.0;
	float m3 = 0.5;
	v_t = UV.y;
	v_dead = COLOR.b;
	v_dry = 0.0;
	v_col = vec3(1.0);
	if (seen) {
		// How much grass there is here: what the ground under it is.
		float m1 = textureLod(macro_noise, p * 0.0035, 0.0).r;
		float m2 = textureLod(macro_noise, p * 0.016 + vec2(0.37, 0.11), 0.0).r;
		m3 = textureLod(macro_noise, p * 0.07 + vec2(0.71, 0.53), 0.0).r;
		float grass = 1.0 - smoothstep(0.66, 0.82, m2 * 0.75 + m3 * 0.25);
		if (jungle) {
			vec2 suv = (p - map_origin) / map_size;
			vec4 s = textureLod(splat, suv, 0.0);
			grass *= smoothstep(0.35, 0.8, s.g) * (1.0 - s.r) * (1.0 - s.a);
			grass *= smoothstep(0.6, 1.4, gy - water_y);
			float e = 1.0;
			float slope = abs(ground_height(p + vec2(e, 0.0)) - ground_height(p - vec2(e, 0.0)))
					+ abs(ground_height(p + vec2(0.0, e)) - ground_height(p - vec2(0.0, e)));
			grass *= 1.0 - smoothstep(0.5, 1.2, slope);
		} else {
			float d = lane_distance(p) + (m3 - 0.5) * 5.0 + (m2 - 0.5) * 6.0;
			grass *= smoothstep(3.5, 9.0, d);
			vec2 q = abs(p) - vec2(mountain_half);
			float foot = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
			grass *= smoothstep(4.0, 10.0, foot + (m3 - 0.5) * 4.0);
		}
		for (int i = 0; i < 8; i++) {
			if (i >= lot_count) {
				break;
			}
			vec2 l = p - lots[i].xy;
			float c = cos(lots_yaw[i]);
			float sn = sin(lots_yaw[i]);
			vec2 lr = vec2(c * l.x - sn * l.y, sn * l.x + c * l.y);
			if (abs(lr.x) < lots[i].z && abs(lr.y) < lots[i].w) {
				grass = 0.0;
			}
		}
		// Thinning toward the edge of the field and where the grass gives out: blade by blade (each has its
		// turn, COLOR.a), the last ones shorter.
		keep = grass * (1.0 - smoothstep(fade.x, fade.y, dist));
		v_dry = smoothstep(0.35, 0.75, m1 * 0.75 + m2 * 0.25);
		// A blade's own shade and hue, and its clump's.
		float shade = mix(0.82, 1.12, COLOR.r) * (0.9 + 0.2 * h4);
		v_col = shade * mix(vec3(1.06, 1.0, 0.86), vec3(0.92, 1.0, 1.1), COLOR.g);
	}
	float turn = COLOR.a;
	if (keep < 0.02 || turn > keep * 1.2) {
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		float size = blade_height * (0.7 + 0.6 * h3) * mix(0.5, 1.0, keep) * mix(0.8, 1.2, m3);
		float yaw = h3 * 6.2831853;
		mat2 rot = mat2(vec2(cos(yaw), sin(yaw)), vec2(-sin(yaw), cos(yaw)));
		// The blade (its root at the origin) turned with its clump, spread over the clump's cell.
		vec3 lv = VERTEX * size;
		lv.xz = rot * lv.xz;
		vec2 root = p + rot * UV2 * cell * 0.62;
		// Gusts sweep across the field; the tips sway most.
		float gust = sin(TIME * 1.3 + dot(root, vec2(0.21, 0.13))) * 0.6 + sin(TIME * 2.7 + dot(root, vec2(-0.47, 0.39))) * 0.3 + 0.5;
		lv.xz += normalize(wind) * gust * 0.16 * UV.y * UV.y * size;
		vec3 world = vec3(root.x, ground_height(root), root.y) + lv;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		vec3 n = NORMAL;
		n.xz = rot * n.xz;
		// Lit as much like the ground as like a blade, so the field shades as one.
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(n, vec3(0.0, 1.0, 0.0), 0.45)), 0.0)).xyz);
	}
}

void fragment() {
	// Both faces of a blade lit alike (the engine turns a back face's normal away).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 tip = mix(tip_color, dry_color, v_dry * 0.6);
	vec3 col = mix(root_color, tip, smoothstep(0.0, 0.6, v_t)) * v_col;
	col = mix(col, dead_color * (0.8 + 0.4 * v_col.g), v_dead);
	ALBEDO = col;
	// Light through the blades, and the waxy sheen on them.
	BACKLIGHT = col * 0.45;
	ROUGHNESS = mix(0.55, 0.85, v_dead);
	SPECULAR = 0.35;
	// The light gets down to the roots less.
	AO = mix(0.6, 1.0, smoothstep(0.0, 0.45, v_t));
	AO_LIGHT_AFFECT = 0.45;
}
"""

static var _mesh: ArrayMesh

var _mat: ShaderMaterial


## The grass of `level` (the classic field's, or the Jungle Keep's with its `terrain`).
static func build(level: LevelBuilder, terrain: JungleTerrain = null) -> GrassField:
	var g := GrassField.new()
	g.name = "Grass"
	g._setup(level, terrain)
	level.add_child(g)
	return g


func _setup(level: LevelBuilder, terrain: JungleTerrain) -> void:
	# Half as thick with the standard lighting (weaker GPUs).
	var density := 0.5 if GameConfig.lighting == "standard" else 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grass="):
			density = clampf(arg.get_slice("=", 1).to_float(), 0.0, 1.0)
	var grid := int(GRID * sqrt(density))
	var cell := CELL / sqrt(maxf(density, 0.01))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _clump()
	mm.custom_aabb = AABB(Vector3(-5000, -200, -5000), Vector3(10000, 400, 10000))
	mm.instance_count = grid * grid
	visible = grid > 0
	multimesh = mm
	custom_aabb = mm.custom_aabb
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("cell", cell)
	_mat.set_shader_parameter("grid", grid)
	_mat.set_shader_parameter("fade", Vector2(FADE[0], FADE[1]))
	_mat.set_shader_parameter("macro_noise", GroundMaterial.macro_noise())
	if terrain:
		var origin := Vector2(-JungleTerrain.HALF - JungleTerrain.CELL * 0.5, -JungleTerrain.HALF - JungleTerrain.CELL * 0.5)
		var size := JungleTerrain.HALF * 2.0 + JungleTerrain.CELL
		_mat.set_shader_parameter("jungle", true)
		_mat.set_shader_parameter("height_map", ImageTexture.create_from_image(
				Image.create_from_data(terrain.n, terrain.n, false, Image.FORMAT_RF, terrain.heights.to_byte_array())))
		_mat.set_shader_parameter("splat", ImageTexture.create_from_image(terrain.splat))
		_mat.set_shader_parameter("map_origin", origin)
		_mat.set_shader_parameter("map_size", size)
		_mat.set_shader_parameter("water_y", JungleLayout.WATER_Y)
		_mat.set_shader_parameter("blade_height", 0.55)
		_mat.set_shader_parameter("root_color", Vector3(0.042, 0.08, 0.018))
		_mat.set_shader_parameter("tip_color", Vector3(0.075, 0.165, 0.032))
		_mat.set_shader_parameter("dry_color", Vector3(0.14, 0.16, 0.045))
		_mat.set_shader_parameter("dead_color", Vector3(0.22, 0.18, 0.09))
	else:
		var lanes: Array[Vector4] = []
		for side in LevelBuilder.SIDES:
			if LevelBuilder.SIDES[side].gate:
				var out: Vector3 = LevelBuilder.SIDES[side].dir
				var a := out * LevelBuilder.FACE_DIST
				var b := out * LevelBuilder.MAP_HALF
				lanes.append(Vector4(a.x, a.z, b.x, b.z))
		while lanes.size() < 4:
			lanes.append(Vector4.ZERO)
		_mat.set_shader_parameter("lanes", lanes)
		_mat.set_shader_parameter("lane_count", mini(lanes.size(), 4))
		_mat.set_shader_parameter("mountain_half", LevelBuilder.MOUNTAIN_HALF)
	# No grass growing up through the helipads' decks.
	var lots: Array[Vector4] = []
	var yaws := PackedFloat32Array()
	for b: AttackerBase in level.bases.slice(0, 8):
		var p: Vector3 = b.global_position
		lots.append(Vector4(p.x, p.z, b.deck_size.x * 0.5 + 1.5, b.deck_size.y * 0.5 + 1.5))
		yaws.append(b.global_rotation.y)
	_mat.set_shader_parameter("lot_count", lots.size())
	while lots.size() < 8:
		lots.append(Vector4.ZERO)
		yaws.append(0.0)
	_mat.set_shader_parameter("lots", lots)
	_mat.set_shader_parameter("lots_yaw", yaws)
	material_override = _mat


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var high := p.y - LevelBuilder.ground_height(p)
	visible = high < MAX_VIEW_HEIGHT and multimesh.instance_count > 0
	if not visible:
		return
	# The field centred a little ahead of the camera, on the ground it looks at.
	var fwd := -cam.global_basis.z
	var ahead := clampf(high / maxf(-fwd.y, 0.25), 0.0, FADE[0] * 0.6)
	var c := p + Vector3(fwd.x, 0.0, fwd.z).normalized() * ahead
	_mat.set_shader_parameter("center", Vector2(c.x, c.z))


## A clump: BLADES blades, each a tapering strip curving away from its root (at the origin; UV2 is where in the
## clump's cell it stands, in a unit disc) in two segments, for a blade a metre tall (the shader sizes it). UV.x is
## across the blade, UV.y how far up it a point is; COLOR is its shade, its hue, whether it is dead and its turn to
## go where the grass thins. Its normals are rounded across it.
static func _clump() -> ArrayMesh:
	if _mesh:
		return _mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for b in BLADES:
		var r := sqrt(rng.randf())
		var a := rng.randf() * TAU
		var root := Vector2(cos(a) * r, sin(a) * r)
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0.0, sin(yaw))
		var out := Vector3(-side.z, 0.0, side.x)
		var h := rng.randf_range(0.35, 1.0)
		var w := rng.randf_range(0.02, 0.034)
		var bend := rng.randf_range(0.08, 0.45)
		var col := Color(rng.randf(), rng.randf(), 1.0 if rng.randf() < 0.07 else 0.0, rng.randf())
		var first := verts.size()
		for lvl in 3:
			var t := lvl / 2.0
			var c := Vector3.UP * h * t + out * bend * h * t * t
			# Along the blade, and its face square to that.
			var along := (Vector3.UP + out * bend * 2.0 * t).normalized()
			var face := side.cross(along).normalized()
			if lvl < 2:
				var ww := w * (1.0 - t * 0.55)
				for s in [-1.0, 1.0]:
					verts.append(c + side * ww * s)
					normals.append((face + side * s * 0.5).normalized())
					uvs.append(Vector2(0.5 + s * 0.5, t * h))
					uv2s.append(root)
					cols.append(col)
			else:
				verts.append(c)
				normals.append(face)
				uvs.append(Vector2(0.5, h))
				uv2s.append(root)
				cols.append(col)
		idx.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2, first + 2, first + 3, first + 4]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh
