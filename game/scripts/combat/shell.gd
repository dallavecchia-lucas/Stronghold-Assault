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


func launch(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var dist := from.distance_to(to)
	_flight_time = clampf(dist / 45.0, 1.2, 3.5)
	_arc = dist * 0.3
	global_position = from


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	_t += delta / _flight_time
	if _t >= 1.0:
		Combat.explode(self, _to, radius, damage, team, structure_mult)
		queue_free()
		return
	global_position = _from.lerp(_to, _t) + Vector3.UP * _arc * 4.0 * _t * (1.0 - _t)
	if trail > 0.0:
		_trail_cd -= delta
		if _trail_cd <= 0.0:
			_trail_cd = trail
			SmokeCloud.wisp(self, global_position, size * 3.0)
