class_name TankRound
extends Node3D
## A round from the Hover Tank's main gun (DefenderTank): a fast shell that flies nearly flat (a little drop at range) and
## bursts on the first thing it meets (the ground, a structure, an attacker) for `damage` within `radius`.

## How fast it flies (m/s), how much of gravity it feels (a flat-shooting gun), and how long it flies at the most (s).
const SPEED := 320.0
const GRAVITY_SCALE := 0.18
const LIFETIME := 3.5
const MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS

## Went off at `at`.
signal burst(at: Vector3)

var team := GameConfig.TEAM_DEFENDER
var damage := 220.0
var radius := 7.0
var structure_mult := 0.8

var velocity := Vector3.ZERO
var _age := 0.0
var _body: Node3D


## Leaves the muzzle at `from` along `dir`.
func fire(from: Vector3, dir: Vector3) -> void:
	global_position = from
	velocity = dir.normalized() * SPEED
	_face()


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var dark := Mats.flat(Color(0.18, 0.18, 0.17), 0.6, 0.4)
	var casing := Mats.cylinder_mesh(0.11, 0.9, Vector3.ZERO, dark, 8)
	casing.rotation.x = PI * 0.5
	_body.add_child(casing)


func _physics_process(delta: float) -> void:
	_age += delta
	velocity.y -= JetBomb.gravity() * GRAVITY_SCALE * delta
	var q := global_position + velocity * delta
	var ray := PhysicsRayQueryParameters3D.create(global_position, q, MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		global_position = hit.position
		burst.emit(hit.position)
		Combat.explode(self, hit.position, radius, damage, team, structure_mult)
		queue_free()
		return
	var fx := FX.of(self)
	# A hot streak along the flight, smeared back like a tracer.
	fx.spark(q, velocity, 0.05, 0.2, 1.4, Color(5.0, 2.4, 0.8), 0.0, 0.0, FX.NO_FLOOR, 0.02, 0.0, 2)
	global_position = q
	_face()
	if _age > LIFETIME:
		queue_free()


func _face() -> void:
	if velocity.length_squared() > 1.0:
		var d := velocity.normalized()
		global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT)
