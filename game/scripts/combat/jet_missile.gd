class_name JetMissile
extends HomingMissile
## One missile of the Fighter Jet's salvo (DefenderJet): an unguided rocket. It leaves its pylon along where the jet's
## nose pointed at that moment (so missiles fired through a manoeuvre each go their own way: see DefenderJet), carrying the
## jet's own speed, its motor takes it up to TOP_SPEED, and after the burn it coasts on, gravity bending its path.
## It bursts on the first thing it meets (the ground, a structure, an attacker) for `damage` within `splash`: no great
## blow, the strength is in the numbers. Looks and smokes like the other missiles (HomingMissile).

const MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS
## The kick out of the pylon (m/s, on top of the jet's speed), the motor's acceleration and burn time, the top speed.
const PUSH := 35.0
const MOTOR := 300.0
const BURN := 1.8
const TOP_SPEED_JET := 270.0
## Seconds it flies at the most before it bursts in the air (a kilometre or so out).
const FLIGHT := 4.6


## Leaves its pylon at `from`, along `dir`, with the jet's velocity `carry`.
func fire(from: Vector3, dir: Vector3, carry: Vector3) -> void:
	team = GameConfig.TEAM_DEFENDER
	global_position = from
	_vel = carry + dir.normalized() * PUSH
	_face()


func _physics_process(delta: float) -> void:
	_age += delta
	var dir := _vel.normalized()
	if _age < BURN:
		_vel = dir * minf(_vel.length() + MOTOR * delta, TOP_SPEED_JET)
	else:
		_vel.y -= JetBomb.gravity() * delta
	var step := _vel * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step, MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_blast()
		return
	global_position += step
	_face()
	if _age > FLIGHT:
		_blast()
		return
	var tail := global_position - _vel.normalized() * 0.62 * size
	var fx := FX.of(self)
	if _age < BURN:
		fx.flare(tail, Color(4.5, 2.4, 0.9), 0.55 * size, 0.75 * size, 0.05, 0, 1.0)
	_flame.power = 1.6 if _age < BURN else 0.0
	_trail_cd -= delta
	if _trail_cd <= 0.0:
		_trail_cd = 0.03
		_puff(tail, _vel.normalized())
