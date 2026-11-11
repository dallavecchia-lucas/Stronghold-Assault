class_name TankRound
extends Node3D
## A round from the Hover Tank's main gun (DefenderTank): a shell that bursts on the first thing it meets (the ground, a structure,
## an attacker) for `damage` within `radius`. It flies dead straight for its first STRAIGHT_RANGE metres (a target inside that is hit
## where the crosshair is, nothing to allow for); past that gravity takes it (real weight: 0.9 m under the line at 300 m, 4 m at 420,
## 14 m at 600), so against a distant target the barrel has to be aimed above it. It is drawn as a bright shell with a short tracer
## streak behind it (TRAIL_LENGTH m, glowing at the shell and fading to nothing at its tail), like a real tank round's, not a line
## along its whole flight.

## How fast it flies (m/s), how far (m) it flies straight before gravity starts to bend it, how much of real gravity then pulls at it,
## and how long it flies at the most (s).
const SPEED := 240.0
const STRAIGHT_RANGE := 200.0
const GRAVITY_SCALE := 1.0
const LIFETIME := 5.5
## Its tracer: a streak of this length (m) and width at the shell (m), orange-hot (HDR, so it glows).
const TRAIL_LENGTH := 14.0
const TRAIL_RADIUS := 0.24
const TRAIL_COLOR := Color(4.8, 2.0, 0.5)
const MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS

## Went off at `at`.
signal burst(at: Vector3)

var team := GameConfig.TEAM_DEFENDER
var damage := 220.0
var radius := 7.0
var structure_mult := 0.8

var velocity := Vector3.ZERO
var _age := 0.0
var _flown := 0.0
var _body: Node3D


## How far (m) under the line of the barrel a shell has dropped at `dist` m out (0 inside STRAIGHT_RANGE): what a target that far off
## has to be aimed above.
static func drop_at(dist: float) -> float:
	if dist <= STRAIGHT_RANGE:
		return 0.0
	var t := (dist - STRAIGHT_RANGE) / SPEED
	return 0.5 * JetBomb.gravity() * GRAVITY_SCALE * t * t


## How high (m) a shell leaving the muzzle at `elevation` (rad, up +) is over the muzzle's height when it is `dist` m out across the
## ground: straight for STRAIGHT_RANGE m along its path, then falling.
static func height_at(dist: float, elevation: float) -> float:
	var c := cos(elevation)
	var y := dist * tan(elevation)
	var flat_straight := STRAIGHT_RANGE * c
	if dist > flat_straight:
		var t := (dist - flat_straight) / (SPEED * c)
		y -= 0.5 * JetBomb.gravity() * GRAVITY_SCALE * t * t
	return y


## The elevation (rad) that sends a shell through a point `dist` m out across the ground and `dy` m above the muzzle.
static func elevation_for(dist: float, dy: float) -> float:
	var lo := -0.6
	var hi := 0.6
	for k in 40:
		var mid := (lo + hi) * 0.5
		if height_at(dist, mid) < dy:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## How far out across level ground (m) a shell leaving a muzzle `h` m up at `elevation` comes down.
static func landing(h: float, elevation: float) -> float:
	var d := 10.0
	while d < 4000.0 and height_at(d, elevation) > -h:
		d += 10.0
	var lo := d - 10.0
	var hi := d
	for k in 30:
		var mid := (lo + hi) * 0.5
		if height_at(mid, elevation) > -h:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


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
	# The tracer: a streak glowing out of the base of the shell and fading to nothing behind it (the shell flies along -Z, so the
	# streak points along +Z).
	var streak := ThrusterFlame.new()
	streak.length = TRAIL_LENGTH
	streak.radius = TRAIL_RADIUS
	streak.color = TRAIL_COLOR
	streak.burner_color = TRAIL_COLOR
	streak.power = 1.0
	streak.position.z = 0.4
	add_child(streak)


func _physics_process(delta: float) -> void:
	_age += delta
	var speed := velocity.length()
	var step := speed * delta
	# Straight for STRAIGHT_RANGE metres; gravity pulls at it for the part of this step that lies beyond.
	var pulled := clampf((_flown + step - STRAIGHT_RANGE) / maxf(speed, 1.0), 0.0, delta)
	velocity.y -= JetBomb.gravity() * GRAVITY_SCALE * pulled
	var q := global_position + velocity * delta
	var ray := PhysicsRayQueryParameters3D.create(global_position, q, MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		global_position = hit.position
		burst.emit(hit.position)
		Combat.explode(self, hit.position, radius, damage, team, structure_mult)
		queue_free()
		return
	# The shell's bright head (the tracer streak behind it is its own child, drawn along it).
	FX.of(self).flare(q, Color(5.5, 2.8, 1.0), 0.7, 1.2, 0.06, 0, 2.0)
	global_position = q
	_flown += step
	_face()
	if _age > LIFETIME:
		queue_free()


func _face() -> void:
	if velocity.length_squared() > 1.0:
		var d := velocity.normalized()
		global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT)
