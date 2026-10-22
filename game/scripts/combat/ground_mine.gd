class_name GroundMine
extends Area3D
## A mine the AA Squad throws (AASquad.throw_mines): lobbed onto its spot, it arms ARM_TIME after
## landing and goes off when an enemy ground unit comes within TRIGGER_RADIUS (aircraft pass over
## it), hurting everything round it (Combat.explode). A flat dark disc on the ground with a small
## light that blinks once it is armed.

const ARM_TIME := 1.2
const TRIGGER_RADIUS := 1.5
const DAMAGE := 160.0
const BLAST_RADIUS := 4.0
## Seconds in the air, and how high the lob goes per meter thrown.
const FLIGHT := 0.75
const ARC := 0.3
const BLINK := 0.9

## Every mine on the field (laid or still in the air), and how many have gone off so far.
static var all: Array[GroundMine] = []
static var blasts := 0

var team := GameConfig.TEAM_DEFENDER

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _flying := true
var _arm := ARM_TIME
var _blink := 0.0
var _body: Node3D
var _light: MeshInstance3D
var _spin := Vector3.ZERO
var _gone := false


## Lobs the mine from `from` (a trooper's hand) onto `to` (on the ground).
func throw(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	global_position = from
	_spin = Vector3(randf_range(-9, 9), randf_range(-4, 4), randf_range(-9, 9))


func is_armed() -> bool:
	return not _flying and _arm <= 0.0


## Ground spot the mine lies on (or is on its way to).
func spot() -> Vector3:
	return _to


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.LAYER_ATTACKERS
	monitoring = false
	monitorable = false
	var cs := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = TRIGGER_RADIUS
	cs.shape = ball
	cs.position.y = 0.7
	add_child(cs)
	body_entered.connect(_on_body_entered)
	_body = Node3D.new()
	add_child(_body)
	var casing := Mats.flat(Color(0.2, 0.23, 0.17), 0.6, 0.55)
	var disc := Mats.cylinder_mesh(0.3, 0.09, Vector3(0, 0.045, 0), casing, 12)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(disc)
	var cap := Mats.cylinder_mesh(0.12, 0.06, Vector3(0, 0.11, 0), Mats.flat(Color(0.12, 0.12, 0.11), 0.7, 0.4), 10)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(cap)
	_light = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.045
	s.height = 0.09
	s.radial_segments = 6
	s.rings = 3
	_light.mesh = s
	_light.material_override = Mats.glow(Color(1.0, 0.18, 0.1), 7.0)
	_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light.position = Vector3(0, 0.15, 0)
	_body.add_child(_light)


func _physics_process(delta: float) -> void:
	if _flying:
		_t += delta / FLIGHT
		if _t < 1.0:
			var arc := _from.distance_to(_to) * ARC
			global_position = _from.lerp(_to, _t) + Vector3.UP * arc * 4.0 * _t * (1.0 - _t)
			_body.rotation += _spin * delta
			return
		_flying = false
		global_position = _to
		_body.rotation = Vector3(0.0, randf() * TAU, 0.0)
		SmokeCloud.wisp(self, _to + Vector3.UP * 0.2, 0.6)
	if _arm > 0.0:
		_arm -= delta
		_light.visible = fmod(_arm, 0.2) < 0.1  # quick flicker while it arms
		if _arm <= 0.0:
			monitoring = true
		return
	_blink += delta
	_light.visible = fmod(_blink, BLINK) < 0.12


func _on_body_entered(body: Node3D) -> void:
	var u = Combat.find_damageable(body)
	if u == null or u.team == team or not u.is_alive():
		return
	if u.has_method("is_flying") and u.is_flying():
		return
	# Out of the physics callback: the blast kills units, which changes their collision layers.
	detonate.call_deferred()


## Goes off: everything within BLAST_RADIUS takes the damage.
func detonate() -> void:
	if _gone:
		return
	_gone = true
	blasts += 1
	set_deferred("monitoring", false)
	Combat.explode(self, global_position + Vector3.UP * 0.3, BLAST_RADIUS, DAMAGE, team)
	queue_free()


## Taken up quietly (its squad has too many down).
func fizzle() -> void:
	if _gone:
		return
	_gone = true
	SmokeCloud.wisp(self, global_position + Vector3.UP * 0.2, 0.5)
	queue_free()
