class_name TalonBomb
extends Node3D
## Bomb dropped by a Sky Talon (its bomb strike): it falls from the talon's belly with the talon's
## speed, nose down along its fall, and bursts on the spot it was aimed at for `damage` within
## `radius`.

var team := GameConfig.TEAM_ATTACKER
var damage := 260.0
var radius := 7.0
var structure_mult := 1.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _fall := 1.0
var _t := 0.0
var _trail_cd := 0.0


## Falls from `from` onto `to`: across at the speed that gets it there while gravity pulls it down.
func drop(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	_fall = sqrt(2.0 * maxf(from.y - to.y, 1.0) / g)
	global_position = from


func _ready() -> void:
	var dark := Mats.flat(Color(0.14, 0.15, 0.16), 0.7, 0.4)
	var body := Mats.cylinder_mesh(0.16, 0.9, Vector3.ZERO, dark, 10)
	add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.3
	nose.mesh = cone
	nose.material_override = dark
	nose.position.y = -0.6
	nose.rotation.x = PI
	add_child(nose)
	for k in 4:
		var fin := Mats.box_mesh(Vector3(0.02, 0.22, 0.26), Vector3.ZERO, dark)
		fin.position = Vector3(0, 0.42, 0)
		fin.rotation.y = k * PI * 0.5
		fin.position += fin.basis.z * 0.12
		add_child(fin)


func _physics_process(delta: float) -> void:
	_t += delta
	var u := minf(_t / _fall, 1.0)
	var flat := _from.lerp(_to, u)
	var drop_y := _from.y + (_to.y - _from.y) * u * u  # constant pull: the height falls as t^2
	var p := Vector3(flat.x, drop_y, flat.z)
	var vel := p - global_position
	global_position = p
	if vel.length_squared() > 1e-6:
		# The model's length runs along +Y: point it down along the fall.
		var down := -vel.normalized()
		var side := down.cross(Vector3.FORWARD if absf(down.z) < 0.9 else Vector3.RIGHT).normalized()
		global_basis = Basis(side, down, side.cross(down)).orthonormalized()
	_trail_cd -= delta
	if _trail_cd <= 0.0:
		_trail_cd = 0.06
		SmokeCloud.wisp(self, global_position, 0.5)
	if u >= 1.0:
		Combat.explode(self, _to, radius, damage, team, structure_mult)
		queue_free()
