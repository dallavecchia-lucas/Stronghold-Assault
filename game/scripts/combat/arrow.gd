class_name Arrow
extends Node3D
## An Infiltrator's arrow (InfiltratorTrooper): loosed from the bow on a shallow arc, it hurts the
## first attacker in its way. Silent: no tracer, no muzzle flash, no light, no flash where it lands,
## so the attacking player only sees their units' health running down. One that misses sticks where
## it lands and goes after STICK_TIME.

const GRAVITY := 9.8
## Gone if it is still flying after LIFE seconds.
const LIFE := 2.5
const STICK_TIME := 4.0
## What stops it: the ground, walls and buildings, and the attackers. It flies through defenders.
const MASK := GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS
const LENGTH := 0.78

var team := GameConfig.TEAM_DEFENDER
var damage := 34.0
var exclude: Array[RID] = []
## Called with the unit it hit.
var on_hit := Callable()

var _vel := Vector3.ZERO
var _t := 0.0
var _stuck := false

static var _shaft_mesh: BoxMesh
static var _fletch_mesh: BoxMesh


## Looses it from `from` at `to`, `speed` m/s, aimed up over the drop so it comes down on the aim.
func launch(from: Vector3, to: Vector3, speed: float) -> void:
	global_position = from
	var d := to - from
	var t := maxf(d.length() / speed, 0.01)
	_vel = (d + Vector3.UP * 0.5 * GRAVITY * t * t) / t
	_orient()


func _ready() -> void:
	if _shaft_mesh == null:
		_shaft_mesh = BoxMesh.new()
		_shaft_mesh.size = Vector3(0.012, 0.012, LENGTH)
		_shaft_mesh.material = Mats.flat(Color(0.16, 0.13, 0.1), 0.0, 0.8)
		_fletch_mesh = BoxMesh.new()
		_fletch_mesh.size = Vector3(0.05, 0.05, 0.12)
		_fletch_mesh.material = Mats.flat(Color(0.12, 0.14, 0.11), 0.0, 0.9)
	var shaft := MeshInstance3D.new()
	shaft.mesh = _shaft_mesh
	shaft.position.z = LENGTH * 0.5
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)
	var fletch := MeshInstance3D.new()
	fletch.mesh = _fletch_mesh
	fletch.position.z = LENGTH - 0.08
	fletch.rotation.z = PI * 0.25
	fletch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fletch)


## The head leads (-Z along the flight); the shaft trails behind it.
func _orient() -> void:
	if _vel.length() < 0.01:
		return
	var up := Vector3.UP if absf(_vel.normalized().y) < 0.98 else Vector3.FORWARD
	global_basis = Basis.looking_at(_vel, up)


func _physics_process(delta: float) -> void:
	if _stuck:
		return
	_t += delta
	if _t > LIFE:
		queue_free()
		return
	var from := global_position
	_vel.y -= GRAVITY * delta
	var to := from + _vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		_orient()
		return
	var d = Combat.find_damageable(hit.collider)
	if d and d.team != team and d.is_alive():
		d.take_damage(damage, team)
		if on_hit.is_valid():
			on_hit.call(d)
		queue_free()
		return
	# Missed: it sticks in the ground (or the wall) and goes after a while.
	global_position = hit.position - _vel.normalized() * 0.3
	_stuck = true
	get_tree().create_timer(STICK_TIME, false).timeout.connect(queue_free)
