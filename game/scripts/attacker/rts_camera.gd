class_name RTSCamera
extends Node3D
## Top-down strategy camera: WASD / arrows / screen edges to pan, Q/E or middle mouse
## to rotate, wheel to zoom.

const EDGE_MARGIN := 6.0

var camera: Camera3D
var bounds := 120.0
var zoom := 38.0
var min_zoom := 15.0
var max_zoom := 180.0
var pitch := deg_to_rad(-58.0)
var edge_scroll := true

var _target_zoom := 38.0
var _rotating := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 900.0
	camera.fov = 55.0
	add_child(camera)
	_target_zoom = zoom
	_apply()


func _process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if edge_scroll and input == Vector2.ZERO and DisplayServer.window_is_focused() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		var m := get_viewport().get_mouse_position()
		var size := get_viewport().get_visible_rect().size
		if m.x >= 0 and m.y >= 0 and m.x <= size.x and m.y <= size.y:
			if m.x < EDGE_MARGIN: input.x = -1
			elif m.x > size.x - EDGE_MARGIN: input.x = 1
			if m.y < EDGE_MARGIN: input.y = -1
			elif m.y > size.y - EDGE_MARGIN: input.y = 1
	var speed := 15.0 + zoom * 0.9
	var move := Basis(Vector3.UP, rotation.y) * Vector3(input.x, 0, input.y) * speed * delta
	position += move
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	# Ride up over the mountain, and keep the camera itself (behind the rig) out of the rock.
	var lift := maxf(_ground_height(global_position), _ground_height(camera.global_position) - camera.position.y + 4.0)
	position.y = lerpf(position.y, lift, minf(delta * 3.0, 1.0))
	var turn := Input.get_axis("cam_rotate_right", "cam_rotate_left")
	rotation.y += turn * delta * 1.8
	zoom = lerpf(zoom, _target_zoom, delta * 10.0)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = maxf(_target_zoom * 0.88, min_zoom)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = minf(_target_zoom * 1.12, max_zoom)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = event.pressed
	elif event is InputEventMouseMotion and _rotating:
		rotation.y -= event.relative.x * 0.006


## Terrain height (the mountain included) under a point.
func _ground_height(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(hit.position.y, 0.0) if not hit.is_empty() else 0.0


func focus(point: Vector3) -> void:
	position = Vector3(point.x, 0, point.z)


func _apply() -> void:
	camera.position = Vector3(0, -sin(pitch) * zoom, cos(pitch) * zoom)
	camera.rotation = Vector3(pitch, 0, 0)
