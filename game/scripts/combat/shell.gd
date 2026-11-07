class_name Shell
extends Node3D
## Artillery shell flying a fixed ballistic arc to a target point, then exploding.

var team := GameConfig.TEAM_DEFENDER
var damage := 150.0
var radius := 7.0
var structure_mult := 0.5
## Radius of the shell (m).
var size := 0.25
## Seconds between the smoke puffs it leaves behind (0: no trail).
var trail := 0.0

var _from: Vector3
var _to: Vector3
var _flight_time := 2.0
var _t := 0.0
var _arc := 10.0
var _trail_cd := 0.0
var _body: Node3D


func launch(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var dist := from.distance_to(to)
	_flight_time = clampf(dist / 45.0, 1.2, 3.5)
	_arc = dist * 0.3
	global_position = from


func _ready() -> void:
	# A dark shell, nose first along its flight, a hot glow at its base and a faint wake of heat behind it.
	_body = Node3D.new()
	add_child(_body)
	var dark := Mats.flat(Color(0.15, 0.15, 0.14), 0.6, 0.45)
	var casing := Mats.cylinder_mesh(size * 0.55, size * 2.4, Vector3.ZERO, dark, 10)
	casing.rotation.x = PI * 0.5
	_body.add_child(casing)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = size * 0.55
	cone.height = size * 1.1
	cone.radial_segments = 10
	nose.mesh = cone
	nose.material_override = dark
	nose.rotation.x = -PI * 0.5
	nose.position.z = -size * 1.75
	_body.add_child(nose)


func _physics_process(delta: float) -> void:
	_t += delta / _flight_time
	if _t >= 1.0:
		Combat.explode(self, _to, radius, damage, team, structure_mult)
		queue_free()
		return
	var p := _from.lerp(_to, _t) + Vector3.UP * _arc * 4.0 * _t * (1.0 - _t)
	var vel := (p - global_position) / maxf(delta, 0.0001)
	global_position = p
	if vel.length_squared() > 0.01:
		_body.global_basis = Basis.looking_at(vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)
	var fx := FX.of(self)
	# The glow at its base, smeared along its flight like a tracer.
	fx.spark(p, vel, 0.06, size * 0.9, size * 4.0, Color(5.0, 2.4, 0.8), 0.0, 0.0, FX.NO_FLOOR, 0.02, 0.0, 2)
	_trail_cd -= delta
	if _trail_cd <= 0.0:
		if trail > 0.0:
			_trail_cd = trail
			fx.smoke(p, vel * 0.04, randf_range(1.4, 2.2), size * 1.2, size * 5.0, Color(0.5, 0.49, 0.47, 0.5), 0.3, 1.5, 0.0, 0.6)
		else:
			_trail_cd = 0.05
			fx.smoke(p, vel * 0.04, randf_range(0.6, 0.9), size * 0.8, size * 2.6, Color(0.6, 0.59, 0.57, 0.18), 0.3, 1.5, 0.0, 0.6)
