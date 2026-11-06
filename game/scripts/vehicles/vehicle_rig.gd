class_name VehicleRig
extends Node3D
## The visual side of a machine (the defenders' jet, drone and hover tank, the attackers' heavy lift
## helicopter): loads its model and moves its parts. The model comes from tools/gltf/rig_vehicles.py: its front +Z,
## up +Y, and every moving part a node at its pivot whose axes say how it moves (see that script):
##   hinges (control surfaces, nozzles, the gun, fan pods) turn about their local X;
##   spinners (rotors, fans, the turret) turn about their local Y;
##   markers (exhausts, muzzles, jets) are empty nodes, their local +Z out of the barrel or along the exhaust.
##
## Whoever owns the rig just moves it (or the node it hangs under) about the world: by default the rig works out how
## it is flying or driving from its own motion (`follow_motion`): its velocity and acceleration in its own frame and
## how fast it is turning, pitching and rolling, and each rig turns that into what its parts do. Set `follow_motion`
## off to drive the inputs by hand (each rig lists its own).

## Read the inputs off the rig's own motion (true), or leave them to the owner (false).
@export var follow_motion := true

var model: Node3D
## The rig's motion in its own frame, smoothed (see _track): velocity (m/s), acceleration (m/s²) and turn rates
## (rad/s about its own X, Y and Z: pitch down, yaw left, roll right positive).
var local_velocity := Vector3.ZERO
var local_accel := Vector3.ZERO
var local_spin := Vector3.ZERO

var _parts := {}
var _rest := {}
var _last_xf := Transform3D.IDENTITY
var _last_velocity := Vector3.ZERO
var _tracked := false
var _age := 0.0


## The model's path (each rig overrides it).
func _model_path() -> String:
	return ""


func _ready() -> void:
	model = (load(_model_path()) as PackedScene).instantiate() as Node3D
	add_child(model)
	_collect(model)
	_build()


## Hook for the rigs: called once the model is in.
func _build() -> void:
	pass


## A part (or marker) of the model by name; null (and a warning) when the model has none.
func part(name: String) -> Node3D:
	if not _parts.has(name):
		push_warning("%s: the model has no %s" % [get_script().get_global_name(), name])
		return null
	return _parts[name]


func has_part(name: String) -> bool:
	return _parts.has(name)


## Turns a hinge `angle` rad from its rest about its local X.
func hinge(name: String, angle: float) -> void:
	var n: Node3D = _parts.get(name)
	if n:
		n.transform = Transform3D(_rest[name].basis * Basis(Vector3.RIGHT, angle), _rest[name].origin)


## Turns a spinner to `angle` rad about its local Y, after tilting its shaft by `tilt` (rad about its local X, Z).
func spin(name: String, angle: float, tilt := Vector2.ZERO) -> void:
	var n: Node3D = _parts.get(name)
	if n:
		var b: Basis = _rest[name].basis * Basis.from_euler(Vector3(tilt.x, 0.0, tilt.y)) * Basis(Vector3.UP, angle)
		n.transform = Transform3D(b, _rest[name].origin)


## Moves a part `offset` from its rest (in its parent's frame).
func slide(name: String, offset: Vector3) -> void:
	var n: Node3D = _parts.get(name)
	if n:
		n.position = _rest[name].origin + offset


## The rest transform of a part in its parent's frame.
func rest_of(name: String) -> Transform3D:
	return _rest.get(name, Transform3D.IDENTITY)


## A part's world transform as of now.
func marker(name: String) -> Transform3D:
	var n: Node3D = _parts.get(name)
	return n.global_transform if n else global_transform


func _collect(n: Node) -> void:
	if n is Node3D and n != model:
		_parts[String(n.name)] = n
		_rest[String(n.name)] = (n as Node3D).transform
	for c in n.get_children():
		_collect(c)


## Works out local_velocity, local_accel and local_spin from how the rig moved since the last frame, smoothed over
## about `smooth` seconds (a frame's jitter in whoever moves it shouldn't shake the surfaces).
func _track(delta: float, smooth := 0.15) -> void:
	_age += delta
	var xf := global_transform
	if not _tracked or delta <= 0.0:
		_last_xf = xf
		_tracked = true
		return
	var v := (xf.origin - _last_xf.origin) / delta
	var acc := (v - _last_velocity) / delta
	_last_velocity = v
	var inv := xf.basis.orthonormalized().inverse()
	var turn := (_last_xf.basis.orthonormalized().inverse() * xf.basis.orthonormalized()).get_euler()
	_last_xf = xf
	var k := 1.0 - exp(-delta / maxf(smooth, 0.001))
	local_velocity = local_velocity.lerp(inv * v, k)
	local_accel = local_accel.lerp(inv * acc, k * 0.5)
	local_spin = local_spin.lerp(turn / delta, k)


## Moves `current` toward `target` at no more than `rate` per second (a servo).
static func servo(current: float, target: float, rate: float, delta: float) -> float:
	return move_toward(current, target, rate * delta)


## A blur disc on a spinner (a rotor, a fan): in its shaft's plane at its blades' height, as wide as they reach. It
## turns with the part (a disc looks the same turned) and tilts with it. Null when the model has no such part.
func add_blur(name: String, color: Color) -> MeshInstance3D:
	var r := _parts.get(name) as MeshInstance3D
	if r == null or r.mesh == null:
		return null
	var box := r.mesh.get_aabb()
	var reach := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
	var d := blur_disc(reach, color)
	d.position.y = box.get_center().y
	r.add_child(d)
	return d


## A see-through disc (a spinning rotor's blur): radius r, in the plane of the shaft's local XZ.
static func blur_disc(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.01
	c.radial_segments = 48
	c.rings = 1
	c.cap_bottom = true
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = m
	mi.set_meta("alpha", color.a)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Sets a blur disc's opacity (0..1 of its colour's alpha).
static func set_blur(disc: MeshInstance3D, opacity: float) -> void:
	var m := disc.material_override as StandardMaterial3D
	m.albedo_color.a = float(disc.get_meta("alpha", 1.0)) * clampf(opacity, 0.0, 1.0)
	disc.visible = opacity > 0.02
