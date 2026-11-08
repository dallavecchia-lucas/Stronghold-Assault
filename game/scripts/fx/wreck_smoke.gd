class_name WreckSmoke
extends Node3D
## Smoke pouring off something knocked out while `emitting` (a wrecked gun or turret): thick dark puffs rising
## and leaning on the wind, a tongue of flame and an ember now and then, and a dull flickering glow under it all.
## Drawn by the scene's FX.

## How big the fire is (1: a gun's).
var size := 1.0
## Puffs a second.
var rate := 7.0
var emitting := false:
	set(v):
		emitting = v
		if _light:
			_light.visible = v

var _acc := 0.0
var _flick := 0.0
var _light: OmniLight3D


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.18)
	_light.omni_range = 5.0 * size
	_light.light_energy = 0.0
	_light.visible = emitting
	add_child(_light)


func _process(delta: float) -> void:
	if not emitting:
		return
	var fx := FX.of(self)
	var at := global_position
	_acc += delta * rate
	while _acc >= 1.0:
		_acc -= 1.0
		var jitter := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1))
		var tone := randf_range(0.07, 0.13)
		fx.smoke(at + jitter * 0.3 * size, Vector3(jitter.x * 0.4, randf_range(1.6, 2.6), jitter.z * 0.4) * size,
				randf_range(3.0, 4.5), 0.5 * size, randf_range(2.2, 3.2) * size, Color(tone, tone * 0.96, tone * 0.92, 0.75),
				0.4, 0.6, 1.2, 0.9)
		if randf() < 0.35:
			fx.flame(at + jitter * 0.25 * size, Vector3(0.0, randf_range(1.2, 2.2), 0.0) * size, randf_range(0.35, 0.6),
					0.25 * size, 0.7 * size, 1.5, 1.2, 0.85, 0.5, 0.5)
		if randf() < 0.15:
			fx.spark(at, (Vector3.UP + jitter * 0.5).normalized() * randf_range(2.0, 4.0), randf_range(0.8, 1.5), 0.025, 0.04,
					Color(3.0, 1.1, 0.25), 1.0, 1.5, FX.NO_FLOOR, 0.02, 0.6)
	_flick = lerpf(_flick, randf(), 0.3)
	_light.light_energy = (0.8 + 0.9 * _flick) * size
