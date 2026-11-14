extends MultiMeshInstance3D
## A gun's spent cases (TurretRig): brass thrown out of its ejection port, tumbling, falling to the floor the gun
## stands on, bouncing there once or twice and lying a moment before it is gone. One multimesh per gun, drawn only
## while it has cases out; past the edge of the floor (a parapet, a roof's edge) they fall on down.

const GRAVITY := 9.8
## How long a case lasts (s), and how long it takes to shrink away at the end.
const LIFE := 2.6
const FADE := 0.35
## How far from the gun the floor reaches (m): past it, a case falls on.
const FLOOR_REACH := 1.9

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _axis: PackedVector3Array
var _spin: PackedFloat32Array
var _angle: PackedFloat32Array
var _age: PackedFloat32Array
var _floor: PackedFloat32Array
var _centre: PackedVector2Array
var _next := 0
var _alive := 0
var _half := 0.05


func setup(capacity: int, radius: float, length: float) -> void:
	top_level = true
	_half = length * 0.5
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 7
	mesh.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.83, 0.6, 0.22)
	brass.metallic = 0.9
	brass.roughness = 0.32
	mesh.material = brass
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 8.0
	_pos.resize(capacity)
	_vel.resize(capacity)
	_axis.resize(capacity)
	_spin.resize(capacity)
	_angle.resize(capacity)
	_age.resize(capacity)
	_floor.resize(capacity)
	_centre.resize(capacity)
	for i in capacity:
		_age[i] = LIFE + 1.0  # (well past it: the array holds single floats)
		_axis[i] = Vector3.UP
	visible = false


func _ready() -> void:
	global_transform = Transform3D.IDENTITY


## A case leaves `port` (world) going `velocity`; the floor it falls to is at `floor_y` round `centre` (x, z).
func throw(port: Transform3D, velocity: Vector3, floor_y: float, centre: Vector2) -> void:
	var i := _next
	_next = (_next + 1) % _pos.size()
	_pos[i] = port.origin
	_vel[i] = velocity
	_axis[i] = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	_spin[i] = randf_range(9.0, 22.0)
	_angle[i] = randf() * TAU
	_age[i] = 0.0
	_floor[i] = floor_y
	_centre[i] = centre
	_alive = _pos.size()
	visible = true
	multimesh.visible_instance_count = _pos.size()


func step(delta: float) -> void:
	if _alive == 0:
		return
	var alive := 0
	for i in _pos.size():
		var age := _age[i]
		if age >= LIFE:
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), _pos[i]))
			continue
		alive += 1
		age += delta
		_age[i] = age
		var v := _vel[i]
		var p := _pos[i]
		v.y -= GRAVITY * delta
		p += v * delta
		var rest := _floor[i] + _half * 0.45
		if p.y < rest and v.y < 0.0 and Vector2(p.x, p.z).distance_to(_centre[i]) < FLOOR_REACH:
			# On the floor: it bounces, losing most of its speed, and its tumbling dies down.
			p.y = rest
			v = Vector3(v.x * 0.55, -v.y * 0.32, v.z * 0.55)
			if v.y < 0.7:
				v.y = 0.0
				v.x *= 0.4
				v.z *= 0.4
			_spin[i] *= 0.45
		_vel[i] = v
		_pos[i] = p
		_angle[i] += _spin[i] * delta
		var k := clampf((LIFE - age) / FADE, 0.0, 1.0)
		multimesh.set_instance_transform(i, Transform3D(Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * k), p))
	_alive = alive
	if alive == 0:
		visible = false
		multimesh.visible_instance_count = 0
