class_name FireFX
extends Node3D
## Fire and smoke for the whole scene: the flamethrowers' jets (FlameTrooper, LionessBlast) and burning
## trees (ForestTree), and what is left burning after the flame has passed (set_alight). The puffs are the
## scene's FX: flame puffs glowing white-hot through orange to a dull red and soot as they cool, smoke puffs
## billowing, lit by the sun and the fire, thinning out as they rise.

## How hot a flame puff burns (times the heat colours: a jet of many overlapping puffs wants less than a
## fireball), and how much of it turns to soot as it cools.
const FLAME_TINT := 0.42
const FLAME_SOOT := 0.25
## A smoke puff's colour and thickness, how much it pales as it thins.
const SMOKE_COLOR := Color(0.16, 0.145, 0.135, 0.6)
const SMOKE_PALE := 1.3

static var _inst: FireFX = null

## Things burning after the flame has left them: node -> [seconds left, damage a second, team].
var _alight := {}


## The scene's FireFX (made on first use).
static func of(ctx: Node) -> FireFX:
	if _inst == null or not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = FireFX.new()
		_inst.name = "FireFX"
		var root := ctx.get_tree().current_scene
		(root if root else ctx.get_tree().root).add_child(_inst)
	return _inst


## Sets `who` (something damageable) burning for `seconds`, `dps` a second from `team`; while
## the flame stays on it, it keeps topping that up. True if it wasn't burning already.
func set_alight(who: Node3D, seconds: float, dps: float, team: int) -> bool:
	var fresh := not _alight.has(who)
	_alight[who] = [seconds, dps, team]
	return fresh


func is_alight(who: Node3D) -> bool:
	return _alight.has(who)


## A flame puff at `pos` flying off at `vel`, living `life` seconds and growing from `size0` to
## `size1` (m); `rise` lifts it (m/s²), `drag` slows it (1/s).
func flame(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, rise := 2.0, drag := 1.5) -> void:
	FX.of(self).flame(pos, vel, life, size0, size1, rise, drag, randf_range(0.95, 1.1), FLAME_TINT, FLAME_SOOT)


func smoke(pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, rise := 0.6, drag := 0.6) -> void:
	var tone := randf_range(0.85, 1.15)
	FX.of(self).smoke(pos, vel, life, size0, size1, Color(SMOKE_COLOR.r * tone, SMOKE_COLOR.g * tone, SMOKE_COLOR.b * tone,
			SMOKE_COLOR.a), rise, drag, 0.6, SMOKE_PALE)


func _ready() -> void:
	top_level = true


func _physics_process(delta: float) -> void:
	for who in _alight.keys():
		var e: Array = _alight[who]
		if not is_instance_valid(who) or not who.is_alive() or e[0] <= 0.0:
			_alight.erase(who)
			continue
		e[0] -= delta
		who.take_damage(e[1] * delta, e[2])
		if randf() < delta * 22.0:
			var at := Combat.aim_point(who) + Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.4), randf_range(-0.4, 0.4))
			flame(at, Vector3(0.0, randf_range(1.5, 3.0), 0.0), randf_range(0.3, 0.55), 0.3, 0.8)
