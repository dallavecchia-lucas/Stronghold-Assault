class_name VentPlume
extends Node3D
## Hot air rising off a rooftop air vent while `emitting`: pale, thin puffs that shoot up fast and
## spread as they cool, leaning on the wind. Drawn by the scene's FX.

## Puffs a second.
var rate := 5.0
var emitting := true

var _acc := 0.0


func _process(delta: float) -> void:
	if not emitting:
		return
	var fx := FX.of(self)
	var at := global_position
	_acc += delta * rate
	while _acc >= 1.0:
		_acc -= 1.0
		var jitter := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
		var tone := randf_range(0.72, 0.85)
		fx.smoke(at + jitter * 0.9, Vector3(jitter.x * 0.3, randf_range(3.5, 5.0), jitter.z * 0.3),
				randf_range(2.0, 3.0), 0.8, randf_range(3.0, 4.2), Color(tone, tone, tone * 1.02, 0.18),
				0.4, 0.6, 1.2, 0.9)
