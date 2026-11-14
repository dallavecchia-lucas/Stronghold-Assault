class_name CannonShell
extends Node3D
## A round from the Arctic Sentinel Cannon (the gun decks' cannons and the one on the south roof: the same gun). It
## leaves along the barrel at SPEED and flies dead straight for its first STRAIGHT m: a near target is hit where the
## barrel points. Past that gravity takes it, so for more range the barrel has to be raised, more and more; the
## longest shot is with it near 45 degrees (about MAX_RANGE over level ground), and raised past that the shell only
## climbs higher and comes down nearer. It bursts on the first thing it meets (the ground, a wall, an enemy): `damage`
## to what it hits and `splash` to everything within `radius`.

## How fast it flies (m/s), how far it flies straight (m), and what pulls it down after (m/s²).
const SPEED := 55.0
const STRAIGHT := 30.0
const GRAVITY := 14.0
const LIFETIME := 12.0
## The longest shot over level ground (m): the straight run and the lob after it, the barrel at 45 degrees.
const MAX_RANGE := STRAIGHT * 0.7071 + SPEED * SPEED / GRAVITY
## The highest the barrel is worth raising (rad).
const BEST := PI * 0.25

var team := GameConfig.TEAM_DEFENDER
var damage := 55.0
var splash := 30.0
var radius := 3.0
var structure_mult := 1.0
var size := 0.16
## Bodies it passes (the gun that fired it).
var exclude: Array[RID] = []

var velocity := Vector3.ZERO
var _flown := 0.0
var _age := 0.0
var _body: Node3D


## How high (m) over the muzzle a shell fired at `elevation` (rad) is when it is `dist` m out across the ground.
static func height_at(dist: float, elevation: float) -> float:
	var c := cos(elevation)
	var y := dist * tan(elevation)
	var flat := STRAIGHT * c
	if dist > flat:
		var t := (dist - flat) / (SPEED * c)
		y -= 0.5 * GRAVITY * t * t
	return y


## The elevation (rad) that drops a shell on a point `dist` m out across the ground and `dy` m above the muzzle: the
## flat shot, as low as reaches it. BEST when it is out of reach (the shell falls short).
static func elevation_for(dist: float, dy: float) -> float:
	if height_at(dist, BEST) < dy:
		return BEST
	var lo := -1.35
	var hi := BEST
	for _i in 28:
		var mid := (lo + hi) * 0.5
		if height_at(dist, mid) < dy:
			lo = mid
		else:
			hi = mid
	return hi


## How long (s) a shell takes to a point `dist` m out across the ground, fired at `elevation`.
static func flight_time(dist: float, elevation: float) -> float:
	return dist / (SPEED * maxf(cos(elevation), 0.05))


## Out of the muzzle at `from`, along `dir`.
func launch(from: Vector3, dir: Vector3) -> void:
	velocity = dir.normalized() * SPEED
	global_position = from
	_face()


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var hot := Mats.glow(Color(1.0, 0.62, 0.25), 3.5)
	var casing := Mats.cylinder_mesh(size * 0.5, size * 2.6, Vector3.ZERO, hot, 8)
	casing.rotation.x = PI * 0.5
	_body.add_child(casing)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	if _flown >= STRAIGHT:
		velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	_flown += from.distance_to(to)
	var mask := GameConfig.LAYER_ALL_SOLID
	mask &= ~(GameConfig.LAYER_DEFENDERS if team == GameConfig.TEAM_DEFENDER else GameConfig.LAYER_ATTACKERS)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var d = Combat.find_damageable(hit.collider)
		if d and d.team != team and d.is_alive():
			d.take_damage(damage * (structure_mult if d.is_in_group("structures") else 1.0), team)
		Combat.explode(self, hit.position, radius, splash, team, structure_mult)
		queue_free()
		return
	global_position = to
	_face()


func _face() -> void:
	if _body and velocity.length_squared() > 0.01 and absf(velocity.normalized().y) < 0.999:
		_body.look_at(global_position + velocity, Vector3.UP)
