class_name TankRound
extends Node3D
## A round from the Hover Tank's main gun (DefenderTank): a shell that flies a gentle arc and bursts on the first thing it meets
## (the ground, a structure, an attacker) for `damage` within `radius`. Gravity pulls at it all the way (GRAVITY_SCALE of
## real weight): near it hardly matters, but far off it drops well under the line of the barrel (a metre and a half at 200 m,
## 3 m at 300, 12 m at 600), so against a distant target the barrel has to be aimed above it, and a tracer, which glows all
## the way and leaves a trail that lingers along the arc, shows the player where the shot is going to adjust.

## How fast it flies (m/s), how much of gravity it feels, and how long it flies at the most (s).
const SPEED := 240.0
const GRAVITY_SCALE := 0.4
const LIFETIME := 4.5
## Its tracer's trail: a glowing dot every TRAIL_STEP metres along the flight, lingering TRAIL_LIFE seconds, cooling red.
const TRAIL_STEP := 1.2
const TRAIL_LIFE := 1.5
const TRAIL_COLOR := Color(4.0, 1.9, 0.5)
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


## How far (m) a shell flying level at the muzzle velocity has dropped after covering `dist` m (what a target `dist` m off has
## to be aimed above).
static func drop_at(dist: float) -> float:
	var t := dist / SPEED
	return 0.5 * JetBomb.gravity() * GRAVITY_SCALE * t * t


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
	# The tracer: a bright streak at the head, and a trail of glowing dots left along the arc, which cool and fade.
	fx.spark(q, velocity, 0.05, 0.6, 4.0, Color(7.0, 3.6, 1.2), 0.0, 0.0, FX.NO_FLOOR, 0.02, 0.0, 2)
	fx.flare(q, Color(5.0, 2.6, 0.9), 0.55, 1.0, 0.07, 0, 2.0)
	var seg := q - global_position
	var dots := maxi(int(seg.length() / TRAIL_STEP), 1)
	for k in dots:
		fx.spark(global_position + seg * (float(k) / dots), seg.normalized() * 0.4, TRAIL_LIFE, 0.42, 1.3, TRAIL_COLOR, 0.0, 0.0,
				FX.NO_FLOOR, 0.0, 1.0, 0)
	global_position = q
	_face()
	if _age > LIFETIME:
		queue_free()


func _face() -> void:
	if velocity.length_squared() > 1.0:
		var d := velocity.normalized()
		global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT)
