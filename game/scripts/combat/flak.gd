class_name Flak
extends RefCounted
## Flak from the War Elephant's cannons: a shell streaks out of the muzzle and bursts close to
## the aircraft in a flash and a black puff. The damage lands with the burst.

const SHELL_SPEED := 160.0
## Bursts land around the aircraft, not dead on it.
const SCATTER := 1.6
const PUFF := Color(0.1, 0.1, 0.1, 0.85)


static func fire(shooter: Node3D, muzzle: Vector3, target: Node3D, damage: float, team: int) -> void:
	var burst := Combat.aim_point(target) + _scatter()
	var root := shooter.get_tree().current_scene
	var flight := muzzle.distance_to(burst) / SHELL_SPEED
	var fx := FX.of(shooter)
	# The shell: a glowing streak out to where it bursts, out of a flash at the muzzle.
	fx.tracer(muzzle, burst, Color(1.0, 0.7, 0.35), 0.06, SHELL_SPEED)
	fx.muzzle_flash(muzzle, burst - muzzle, 1.6, false)
	shooter.get_tree().create_timer(flight, false).timeout.connect(func():
		if not is_instance_valid(root):
			return  # the match ended while the shell was in the air
		if Combat.is_valid_target(target):
			target.take_damage(damage, team)
		burst_at(root, burst))


## A flash, a black puff that swells and drifts away, shrapnel.
static func burst_at(root: Node, pos: Vector3) -> void:
	FX.of(root).flak_burst(pos)


static func _scatter() -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	return v.normalized() * SCATTER * randf_range(0.4, 1.0)
