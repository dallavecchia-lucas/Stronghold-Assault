class_name FlashGrenade
extends Node3D
## A Kangaroo Commando's flash grenade. Lobbed from the paw onto a spot, it lands, skips on a little
## and goes off FUSE seconds later in a blinding white flash. Every defender within `radius` that has
## the bang in sight is blinded for `blind` seconds (is_blind): left to the AI, a blinded post or
## trooper can't fight. The defending player's screen goes white if it caught the post they are on
## (the "flash_watchers" group, DefenderController.on_flash). It does no damage.

signal went_off(at: Vector3)

## Seconds from landing to the bang.
const FUSE := 0.4
## How far it skips on along the throw after landing (m), and how long that takes.
const SKIP := 0.35
const SKIP_TIME := 0.22
## A defender sees the bang from this far above its aim point (its eyes).
const EYE_UP := 0.4
## The flash fills the air round it: what sees this far over the grenade sees the flash (over a low
## wall like the gun decks' parapets, but not from a floor below).
const GLARE_UP := 1.2

var team := GameConfig.TEAM_ATTACKER
var radius := 9.0
var blind := 2.0
## Where it was thrown to.
var spot := Vector3.ZERO

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _rest := Vector3.ZERO
var _arc := 3.0
var _flight := 1.0
var _t := 0.0
var _landed := -1.0
var _spin := Vector3.RIGHT
var _body: Node3D


## Lobs it from `from` onto `to`, peaking `arc` above the straight line between them.
func launch(from: Vector3, to: Vector3, arc: float) -> void:
	_from = from
	_to = to
	spot = to
	_arc = arc
	_flight = clampf(from.distance_to(to) / 17.0, 0.5, 1.4)
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z)
	along = along.normalized() if along.length() > 0.1 else Vector3.FORWARD
	_spin = along.cross(Vector3.UP).normalized()
	# It skips on along the throw, but not off a deck's edge or into a wall.
	_rest = RhinoAim.settle(get_world_3d().direct_space_state, to + along * SKIP, to.y)
	if absf(_rest.y - to.y) > 0.3:
		_rest = to
	global_position = from


## True if a bang at `at` is within `radius` of `eye` and nothing solid stands between the eye and
## its glare (GLARE_UP over it).
static func sees(ctx: Node3D, at: Vector3, eye: Vector3, radius: float) -> bool:
	if at.distance_to(eye) > radius:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, at + Vector3.UP * GLARE_UP, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	return ctx.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Blinds `n` for `seconds`, on top of any flash it is still blinded by.
static func blind_node(n: Node, seconds: float) -> void:
	n.set_meta("flashed", int(n.get_meta("flashed", 0)) + 1)
	n.get_tree().create_timer(seconds, false).timeout.connect(func():
		if is_instance_valid(n):
			n.set_meta("flashed", int(n.get_meta("flashed", 1)) - 1))


static func is_blind(n: Node) -> bool:
	return n != null and int(n.get_meta("flashed", 0)) > 0


## True if a flash grenade is already on its way to within `reach` of `at`: in the air, or about to
## leave a kangaroo's paw (so kangaroos don't all flash the same defender).
static func coming(ctx: Node, at: Vector3, reach: float) -> bool:
	for g in ctx.get_tree().get_nodes_in_group("flash_grenades"):
		if g.spot.distance_to(at) < reach:
			return true
	for u in ctx.get_tree().get_nodes_in_group("attacker_units"):
		if u.flash_spot().distance_to(at) < reach:
			return true
	return false


func _ready() -> void:
	add_to_group("flash_grenades")
	# A flashbang: a stubby canister with a bright fuse head.
	_body = Node3D.new()
	add_child(_body)
	_body.add_child(Mats.cylinder_mesh(0.055, 0.15, Vector3.ZERO, Mats.flat(Color(0.25, 0.3, 0.2), 0.3, 0.6), 10))
	_body.add_child(Mats.cylinder_mesh(0.035, 0.05, Vector3(0, 0.09, 0), Mats.flat(Color(0.75, 0.75, 0.72), 0.8, 0.3), 8))


func _physics_process(delta: float) -> void:
	_t += delta
	if _landed < 0.0:
		var u := minf(_t / _flight, 1.0)
		global_position = _from.lerp(_to, u) + Vector3.UP * _arc * 4.0 * u * (1.0 - u)
		_body.rotate(_spin, delta * 14.0)
		if u >= 1.0:
			_landed = _t
		return
	var s := minf((_t - _landed) / SKIP_TIME, 1.0)
	global_position = _to.lerp(_rest, s) + Vector3.UP * (0.05 + 0.16 * sin(PI * s))
	_body.rotate(_spin, delta * 8.0 * (1.0 - s))
	if _t - _landed >= FUSE:
		_bang()


func _bang() -> void:
	var at := global_position + Vector3.UP * 0.15
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if d.team != team and d.is_alive() and sees(self, at, Combat.aim_point(d) + Vector3.UP * EYE_UP, radius):
			blind_node(d, blind)
	get_tree().call_group("flash_watchers", "on_flash", at, radius, blind)
	_flash(at)
	went_off.emit(at)
	queue_free()


## The bang: a white-hot ball, light washing over everything round it, sparks and a puff of smoke.
func _flash(at: Vector3) -> void:
	var root := get_tree().current_scene
	var ball := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	ball.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * 0.2
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * 2.6, 0.07)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ball.queue_free)

	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.97, 1.0)
	light.light_energy = 26.0
	light.omni_range = radius * 1.8
	root.add_child(light)
	light.global_position = at + Vector3.UP * 0.8
	var tl := light.create_tween()
	tl.tween_property(light, "light_energy", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tl.tween_callback(light.queue_free)

	var sparks := CPUParticles3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	dot.radial_segments = 4
	dot.rings = 2
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.95, 0.75)
	dot.material = spark_mat
	sparks.mesh = dot
	sparks.amount = 28
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = 0.45
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.initial_velocity_min = 5.0
	sparks.initial_velocity_max = 11.0
	sparks.gravity = Vector3(0, -9.8, 0)
	root.add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)
	for k in 3:
		SmokeCloud.wisp(self, at + Vector3(randf_range(-0.5, 0.5), 0.3 * k, randf_range(-0.5, 0.5)), 1.6)
