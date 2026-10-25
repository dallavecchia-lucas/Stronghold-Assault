class_name FireFX
extends Node3D
## Fire and smoke puffs for the whole scene: the flamethrowers' jets (FlameTrooper) and burning
## trees (ForestTree). Two MultiMeshes (one draw each): flame, glowing and added onto what is
## behind it, and smoke, dark and see-through. A puff is a billboard that flies off at a velocity
## (slowed by drag, lifted by its heat), grows, turns and runs down a colour ramp as it ages: a
## flame puff from white-hot through orange to a dull red and out, a smoke puff from thick to gone.
##
## Puffs are moved by hand rather than with CPUParticles3D (see SmokeCloud).

const FIRE_MAX := 1600
const SMOKE_MAX := 700
## The flame's colour over a puff's life (HDR: the hot core blooms).
const FIRE_RAMP := [
	[0.0, Color(2.2, 1.9, 1.3, 0.7)],
	[0.12, Color(2.2, 1.3, 0.45, 0.75)],
	[0.45, Color(1.6, 0.55, 0.12, 0.6)],
	[0.78, Color(0.75, 0.17, 0.04, 0.32)],
	[1.0, Color(0.25, 0.05, 0.02, 0.0)],
]
const SMOKE_RAMP := [
	[0.0, Color(0.16, 0.14, 0.13, 0.0)],
	[0.12, Color(0.17, 0.15, 0.14, 0.6)],
	[0.6, Color(0.28, 0.27, 0.26, 0.42)],
	[1.0, Color(0.42, 0.41, 0.4, 0.0)],
]

const SHADER := """
shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
varying vec4 tint;
varying float seed;
void vertex() {
	// Billboard: the quad faces the camera, turned by its own angle and scaled with the instance.
	float a = INSTANCE_CUSTOM.x;
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy * s;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	tint = COLOR;
	seed = INSTANCE_CUSTOM.y;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// A soft ball broken up by noise, so the puffs don't read as discs.
	float n = texture(noise, UV * 0.55 + vec2(seed, seed * 1.7)).r;
	float a = smoothstep(1.0, 0.15, r + (n - 0.5) * %s);
	ALBEDO = tint.rgb;
	ALPHA = clamp(tint.a * a, 0.0, 1.0);
}
"""

static var _inst: FireFX = null

var _fire := _Puffs.new(FIRE_MAX)
var _smoke := _Puffs.new(SMOKE_MAX)
var _fire_mm: MultiMesh
var _smoke_mm: MultiMesh
## Things burning after the flame has left them: node -> [seconds left, damage a second, team].
var _alight := {}


## The scene's FireFX (made on first use).
static func of(ctx: Node) -> FireFX:
	if _inst == null or not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = FireFX.new()
		_inst.name = "FireFX"
		var root := ctx.get_tree().current_scene
		(root if root else ctx.get_tree().root).add_child(_inst)
	return _inst


## Sets `who` (something damageable) burning for `seconds`, `dps` a second from `team`; while
## the flame stays on it, it keeps topping that up. True if it wasn't burning already.
func set_alight(who: Node3D, seconds: float, dps: float, team: int) -> bool:
	var fresh := not _alight.has(who)
	_alight[who] = [seconds, dps, team]
	return fresh


func is_alight(who: Node3D) -> bool:
	return _alight.has(who)


## A flame puff at `pos` flying off at `vel`, living `life` seconds and growing from `size0` to
## `size1` (m); `rise` lifts it (m/s²), `drag` slows it (1/s).
func flame(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, rise := 2.0, drag := 1.5) -> void:
	_fire.add(pos, vel, life, size0, size1, rise, drag)


func smoke(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, rise := 0.6, drag := 0.6) -> void:
	_smoke.add(pos, vel, life, size0, size1, rise, drag)


func _ready() -> void:
	top_level = true
	_fire_mm = _multimesh(FIRE_MAX)
	_smoke_mm = _multimesh(SMOKE_MAX)
	_layer(_fire_mm, _material("blend_add", 1.1))
	_layer(_smoke_mm, _material("blend_mix", 0.9))


func _multimesh(n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = n
	mm.visible_instance_count = 0
	return mm


func _layer(mm: MultiMesh, mat: Material) -> void:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Puffs are placed in world space anywhere on the map.
	mi.custom_aabb = AABB(Vector3(-600, -50, -600), Vector3(1200, 300, 1200))
	add_child(mi)


func _material(blend: String, breakup: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADER % [blend, breakup]
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = noise
	mat.set_shader_parameter("noise", tex)
	return mat


func _physics_process(delta: float) -> void:
	for who in _alight.keys():
		var e: Array = _alight[who]
		if not is_instance_valid(who) or not who.is_alive() or e[0] <= 0.0:
			_alight.erase(who)
			continue
		e[0] -= delta
		who.take_damage(e[1] * delta, e[2])
		if randf() < delta * 22.0:
			var at := Combat.aim_point(who) + Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.4), randf_range(-0.4, 0.4))
			flame(at, Vector3(0.0, randf_range(1.5, 3.0), 0.0), randf_range(0.3, 0.55), 0.3, 0.8)


func _process(delta: float) -> void:
	_fire.step(delta)
	_smoke.step(delta)
	_fire.draw(_fire_mm, FIRE_RAMP)
	_smoke.draw(_smoke_mm, SMOKE_RAMP)


static func _ramp(ramp: Array, u: float) -> Color:
	for k in range(1, ramp.size()):
		if u <= ramp[k][0]:
			var a: Array = ramp[k - 1]
			var b: Array = ramp[k]
			return (a[1] as Color).lerp(b[1], (u - a[0]) / maxf(b[0] - a[0], 0.0001))
	return ramp[-1][1]


## A pool of puffs: the oldest is reused once it is full.
class _Puffs:
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var size0 := PackedFloat32Array()
	var size1 := PackedFloat32Array()
	var rise := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var spin := PackedFloat32Array()
	var angle := PackedFloat32Array()
	var seed_ := PackedFloat32Array()
	var count := 0
	var cap := 0
	var _buf := PackedFloat32Array()

	func _init(n: int) -> void:
		cap = n
		for arr in [pos, vel]:
			arr.resize(n)
		for arr in [age, life, size0, size1, rise, drag, spin, angle, seed_]:
			arr.resize(n)
		_buf.resize(n * 20)

	func add(p: Vector3, v: Vector3, l: float, s0: float, s1: float, r: float, d: float) -> void:
		var i := count
		if count < cap:
			count += 1
		else:
			i = randi() % cap
		pos[i] = p
		vel[i] = v
		age[i] = 0.0
		life[i] = maxf(l, 0.05)
		size0[i] = s0
		size1[i] = s1
		rise[i] = r
		drag[i] = d
		spin[i] = randf_range(-1.5, 1.5)
		angle[i] = randf() * TAU
		seed_[i] = randf()

	func step(dt: float) -> void:
		var i := 0
		while i < count:
			age[i] += dt
			if age[i] >= life[i]:
				_remove(i)
				continue
			var v := vel[i]
			v *= maxf(1.0 - drag[i] * dt, 0.0)
			v.y += rise[i] * dt
			vel[i] = v
			pos[i] += v * dt
			angle[i] += spin[i] * dt
			i += 1

	func _remove(i: int) -> void:
		count -= 1
		if i != count:
			pos[i] = pos[count]
			vel[i] = vel[count]
			age[i] = age[count]
			life[i] = life[count]
			size0[i] = size0[count]
			size1[i] = size1[count]
			rise[i] = rise[count]
			drag[i] = drag[count]
			spin[i] = spin[count]
			angle[i] = angle[count]
			seed_[i] = seed_[count]

	## Into the MultiMesh's buffer: per puff its transform (rows of a scaled basis and the origin),
	## colour and custom data (angle, noise seed).
	func draw(mm: MultiMesh, ramp: Array) -> void:
		for i in count:
			var u := age[i] / life[i]
			# Puffs swell fast at first, then slowly.
			var s := lerpf(size0[i], size1[i], 1.0 - pow(1.0 - u, 2.2))
			var c := FireFX._ramp(ramp, u)
			var p := pos[i]
			var k := i * 20
			_buf[k] = s
			_buf[k + 1] = 0.0
			_buf[k + 2] = 0.0
			_buf[k + 3] = p.x
			_buf[k + 4] = 0.0
			_buf[k + 5] = s
			_buf[k + 6] = 0.0
			_buf[k + 7] = p.y
			_buf[k + 8] = 0.0
			_buf[k + 9] = 0.0
			_buf[k + 10] = s
			_buf[k + 11] = p.z
			_buf[k + 12] = c.r
			_buf[k + 13] = c.g
			_buf[k + 14] = c.b
			_buf[k + 15] = c.a
			_buf[k + 16] = angle[i]
			_buf[k + 17] = seed_[i]
		mm.buffer = _buf
		mm.visible_instance_count = count
