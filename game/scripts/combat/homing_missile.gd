class_name HomingMissile
extends Node3D
## Missile from the War Elephant's pods. Leaves its tube straight along it, then turns onto its
## target (harder the longer it flies) while picking up speed, and hits it for `damage`. If the
## target is gone it flies on for a moment and bursts. Leaves a smoke trail.

const BOOST := 0.3  # seconds straight out of the tube
const START_SPEED := 16.0
const TOP_SPEED := 75.0
const ACCEL := 90.0
## Turn rate (rad/s) at launch; it grows the longer the missile flies.
const TURN := 3.0
const HIT_RADIUS := 1.3
const LIFETIME := 8.0
const TRAIL := Color(0.86, 0.85, 0.82, 0.7)

static var _meshes := {}

var team := GameConfig.TEAM_ATTACKER
var damage := 18.0
var target: Node3D
## Called once when the missile is spent, whether it hit or not.
var on_spent := Callable()

var _vel := Vector3.ZERO
var _age := 0.0
var _lost := 0.0
var _trail_cd := 0.0
var _flame: MeshInstance3D


func launch(from: Vector3, dir: Vector3, t: Node3D) -> void:
	target = t
	_vel = dir.normalized() * START_SPEED
	global_position = from
	_face()


func _ready() -> void:
	_build()


func _physics_process(delta: float) -> void:
	_age += delta
	var tracking := Combat.is_valid_target(target)
	var dir := _vel.normalized()
	if tracking and _age > BOOST:
		var want := (Combat.aim_point(target) - global_position).normalized()
		var angle := dir.angle_to(want)
		if angle > 0.0001:
			dir = dir.slerp(want, minf(TURN * (1.0 + _age * 2.0) * delta / angle, 1.0))
	_vel = dir * minf(_vel.length() + ACCEL * delta, TOP_SPEED)
	var step := _vel * delta
	if tracking:
		var aim := Combat.aim_point(target)
		var p := Geometry3D.get_closest_point_to_segment(aim, global_position, global_position + step)
		if p.distance_to(aim) < HIT_RADIUS:
			global_position = p
			target.take_damage(damage, team)
			_burst(1.8)
			return
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step,
			GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_burst(1.4)
		return
	global_position += step
	_face()
	if not tracking:
		_lost += delta
	if _lost > 0.35 or _age > LIFETIME:
		_burst(1.0)
		return
	_flame.scale = Vector3.ONE * randf_range(0.8, 1.25)
	_trail_cd -= delta
	if _trail_cd <= 0.0:
		_trail_cd = 0.035
		_puff(global_position - dir * 0.6)


func _burst(size: float) -> void:
	Combat.spawn_explosion(self, global_position, size)
	if on_spent.is_valid():
		on_spent.call()
	queue_free()


func _face() -> void:
	if _vel.length_squared() > 0.01:
		var up := Vector3.UP if absf(_vel.normalized().y) < 0.99 else Vector3.FORWARD
		global_basis = Basis.looking_at(_vel, up)


## Smoke left behind: swells and fades.
func _puff(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("puff")
	var mat := SmokeCloud.puff_material(TRAIL)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.5
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * randf_range(2.0, 2.8), 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "global_position", pos + Vector3(randf_range(-0.2, 0.2), 0.4, randf_range(-0.2, 0.2)), 1.1)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.1).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Body along -Z (the way it flies): white casing, red nose, four fins and a flame at the tail.
func _build() -> void:
	var casing := Mats.flat(Color(0.85, 0.86, 0.84), 0.3, 0.5)
	var body := MeshInstance3D.new()
	body.mesh = _mesh("body")
	body.material_override = casing
	body.rotation.x = PI * 0.5
	add_child(body)
	var nose := MeshInstance3D.new()
	nose.mesh = _mesh("nose")
	nose.material_override = Mats.flat(Color(0.75, 0.12, 0.08), 0.2, 0.5)
	nose.rotation.x = -PI * 0.5
	nose.position.z = -0.6
	add_child(nose)
	for k in 2:  # each plate makes two opposite fins
		var fin := MeshInstance3D.new()
		fin.mesh = _mesh("fin")
		fin.material_override = casing
		fin.rotation.z = k * PI * 0.5
		fin.position.z = 0.38
		add_child(fin)
	_flame = MeshInstance3D.new()
	_flame.mesh = _mesh("flame")
	_flame.material_override = Mats.glow(Color(1.0, 0.6, 0.2), 6.0)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position.z = 0.62
	add_child(_flame)


static func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		match kind:
			"body":
				var c := CylinderMesh.new()
				c.top_radius = 0.075
				c.bottom_radius = 0.075
				c.height = 1.0
				c.radial_segments = 8
				_meshes[kind] = c
			"nose":
				var c := CylinderMesh.new()
				c.top_radius = 0.0
				c.bottom_radius = 0.075
				c.height = 0.22
				c.radial_segments = 8
				_meshes[kind] = c
			"fin":
				var b := BoxMesh.new()
				b.size = Vector3(0.02, 0.32, 0.22)
				_meshes[kind] = b
			"flame":
				var s := SphereMesh.new()
				s.radius = 0.11
				s.height = 0.45
				s.radial_segments = 8
				s.rings = 4
				_meshes[kind] = s
			"puff":
				var quad := QuadMesh.new()
				quad.size = Vector2.ONE * 0.6
				_meshes[kind] = quad
	return _meshes[kind]
