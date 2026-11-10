class_name JetBomb
extends Node3D
## A bomb dropped by the defenders' Fighter Jet (DefenderJet), falling the way a real one does. It leaves the bay with the
## jet's own velocity, so it carries on forward as it falls (the faster and higher the jet, the farther ahead it lands),
## gravity pulls it down and the air drags at it (the faster it goes the harder, up to TERMINAL speed), and its nose
## swings round into the airflow as it falls. It bursts where it meets the ground, the mountain, a structure or an
## attacker, for `damage` within `radius`.
##
## predict() flies the same fall ahead of time, with the same step(), so the jet's aim preview shows where a bomb let go
## this instant would land.

## How fast a bomb falls at the most, in still air (m/s): where the drag balances its weight.
const TERMINAL := 210.0
## What a bomb bursts on: the ground, structures and attackers.
const MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS
## How fast the nose swings round into the airflow (1/s).
const WEATHERVANE := 2.2
## predict(): the step (s) it flies in, and how long it flies at the most (s).
const PREDICT_STEP := 0.1
const PREDICT_TIME := 16.0
## Above this height (m) nothing is high enough to be hit, so the preview skips its ray checks.
const CLEAR_ABOVE := 140.0

## Went off at `at`.
signal burst(at: Vector3)

var team := GameConfig.TEAM_DEFENDER
var damage := 380.0
var radius := 11.0
var structure_mult := 1.0

var velocity := Vector3.ZERO
var _nose := Vector3.DOWN
var _trail_cd := 0.0
var _gone := false


static func gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity"))


## The bomb's acceleration at velocity `v`: gravity, and drag against the way it moves (quadratic: it tops out at TERMINAL).
static func accel(v: Vector3) -> Vector3:
	var g := gravity()
	return Vector3(0.0, -g, 0.0) - v * v.length() * (g / (TERMINAL * TERMINAL))


## One step of its fall: where it is and how fast it goes after `dt` seconds (the midpoint method, so a long step and a
## short one end up in the same place). Returns [position, velocity].
static func step(p: Vector3, v: Vector3, dt: float) -> Array:
	var vm := v + accel(v) * (dt * 0.5)
	return [p + vm * dt, v + accel(vm) * dt]


## Where a bomb let go at `from` with velocity `vel` would burst, flown ahead in PREDICT_STEP steps: a Dictionary of
## `impact` (the point), `normal` (of the surface), `points` (its path, the release point first), `time` (s until it
## lands) and `hit` (false: it never met anything, and the impact is wherever it was when the preview gave up).
static func predict(space: PhysicsDirectSpaceState3D, from: Vector3, vel: Vector3) -> Dictionary:
	var p := from
	var v := vel
	var points := PackedVector3Array([from])
	var t := 0.0
	while t < PREDICT_TIME:
		var s := step(p, v, PREDICT_STEP)
		var q: Vector3 = s[0]
		t += PREDICT_STEP
		if minf(p.y, q.y) < CLEAR_ABOVE:
			var ray := PhysicsRayQueryParameters3D.create(p, q, MASK)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				var d := p.distance_to(q)
				var f := p.distance_to(hit.position) / maxf(d, 0.001)
				points.append(hit.position)
				return {"impact": hit.position, "normal": hit.normal, "points": points, "time": t - PREDICT_STEP * (1.0 - f), "hit": true}
		points.append(q)
		p = q
		v = s[1]
		if p.y < -60.0:
			break
	return {"impact": p, "normal": Vector3.UP, "points": points, "time": t, "hit": false}


## Lets go of the bomb at `from`, with the jet's velocity `vel` and its nose along `nose`.
func drop(from: Vector3, vel: Vector3, nose: Vector3) -> void:
	global_position = from
	velocity = vel
	_nose = nose.normalized()
	_face()


func _ready() -> void:
	# A fat olive casing with a yellow band, a blunt nose, and four fins on the tail: along -Z, nose first.
	var olive := Mats.flat(Color(0.2, 0.23, 0.15), 0.3, 0.55)
	var band := Mats.flat(Color(0.85, 0.7, 0.15), 0.1, 0.6)
	var body := Mats.cylinder_mesh(0.26, 2.2, Vector3.ZERO, olive, 12)
	body.rotation.x = PI * 0.5
	add_child(body)
	var stripe := Mats.cylinder_mesh(0.265, 0.18, Vector3(0, 0, -0.55), band, 12)
	stripe.rotation.x = PI * 0.5
	add_child(stripe)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.26
	cone.height = 0.62
	cone.radial_segments = 12
	nose.mesh = cone
	nose.material_override = olive
	nose.rotation.x = -PI * 0.5
	nose.position.z = -1.4
	add_child(nose)
	for k in 4:
		var fin := Mats.box_mesh(Vector3(0.03, 0.62, 0.55), Vector3.ZERO, olive)
		fin.position = Vector3(0, 0, 1.0)
		fin.rotation.z = k * PI * 0.5
		fin.position += fin.basis.y * 0.28
		add_child(fin)


func _physics_process(delta: float) -> void:
	if _gone:
		return
	var s := step(global_position, velocity, delta)
	var q: Vector3 = s[0]
	var ray := PhysicsRayQueryParameters3D.create(global_position, q, MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		_gone = true
		global_position = hit.position
		burst.emit(hit.position)
		Combat.explode(self, hit.position, radius, damage, team, structure_mult)
		queue_free()
		return
	global_position = q
	velocity = s[1]
	if velocity.y < -400.0 or global_position.y < -80.0:
		# Fell through a hole in the world: nothing left to hurt.
		queue_free()
		return
	_face(delta)
	_trail_cd -= delta
	if _trail_cd <= 0.0:
		_trail_cd = 0.07
		SmokeCloud.wisp(self, global_position, 0.45)


## The nose swings round into the airflow: toward the way it is going (a bomb let go starts with the jet's attitude).
func _face(delta := 0.0) -> void:
	if delta > 0.0 and velocity.length_squared() > 1.0:
		_nose = _nose.slerp(velocity.normalized(), 1.0 - exp(-WEATHERVANE * delta))
	var up := Vector3.UP if absf(_nose.y) < 0.98 else Vector3.RIGHT
	global_basis = Basis.looking_at(_nose, up)
