class_name SmokeGrenade
extends Node3D
## Smoke grenade from the Hippo's smoke screen. Arcs to a point high above where it was aimed,
## bursts (stage 1), then drops straight down and bursts twice more on the way to the ground,
## leaving a tall pillar of SmokeCloud balls.

const FALL_SPEED := 12.0

var cloud_radius := 3.5
var cloud_duration := 30.0

var _from: Vector3
var _top: Vector3
## Heights above the ground point where each stage bursts, top first.
var _stages: Array[float] = []
var _ground_y := 0.0
var _flight_time := 1.5
var _arc := 6.0
var _t := 0.0
var _falling := false


## `ground` is the point on the ground the pillar stands on; it tops out `height` above it.
func launch(from: Vector3, ground: Vector3, height: float) -> void:
	_from = from
	_ground_y = ground.y
	_top = ground + Vector3.UP * height
	# Balls overlap a little so the pillar has no gaps, the last one sits on the ground.
	var low := cloud_radius * 0.5
	_stages = [height, lerpf(height, low, 0.5), low]
	var dist := from.distance_to(_top)
	_flight_time = clampf(dist / 22.0, 0.9, 2.0)
	_arc = dist * 0.25
	global_position = from


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.09
	m.bottom_radius = 0.09
	m.height = 0.3
	mi.mesh = m
	mi.material_override = Mats.flat(Color(0.3, 0.42, 0.3), 0.4, 0.6)
	mi.rotation.x = PI * 0.5
	add_child(mi)


func _physics_process(delta: float) -> void:
	if not _falling:
		_t += delta / _flight_time
		if _t < 1.0:
			global_position = _from.lerp(_top, _t) + Vector3.UP * _arc * 4.0 * _t * (1.0 - _t)
			return
		global_position = _top
		_falling = true
	while not _stages.is_empty() and global_position.y <= _ground_y + _stages[0] + 0.01:
		_burst()
		_stages.pop_front()
	if _stages.is_empty():
		queue_free()
		return
	global_position.y -= FALL_SPEED * delta


func _burst() -> void:
	var c := SmokeCloud.new()
	c.radius = cloud_radius
	c.duration = cloud_duration
	c.position = position
	get_parent().add_child(c)
	Combat.spawn_impact(self, global_position, true)
