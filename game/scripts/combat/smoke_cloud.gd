class_name SmokeCloud
extends Node3D
## One ball of smoke from a smoke grenade burst. Blocks line of sight (see blocks()) while it
## lasts: it swells to full size in GROW_TIME, holds, then thins out over the last FADE_TIME
## seconds of its duration.
##
## Drawn as a few billboard puffs moved by hand rather than with CPUParticles3D, whose puffs
## spawned mid-match can render as black discs.

const GROW_TIME := 0.8
const FADE_TIME := 4.0
const PUFFS := 9
const COLOR := Color(0.8, 0.8, 0.78)
const ALPHA := 0.9

## Every cloud currently in the world, for line of sight checks.
static var clouds: Array[SmokeCloud] = []
static var _puff_tex: GradientTexture2D

var radius := 3.5
var duration := 30.0

var _age := 0.0
var _mat: StandardMaterial3D
## [MeshInstance3D, resting offset, drift velocity, size]
var _puffs := []


## True if the segment passes through any smoke thick enough to hide behind.
static func blocks(from: Vector3, to: Vector3) -> bool:
	for c in clouds:
		var r := c.blocking_radius()
		if r <= 0.0:
			continue
		var p := Geometry3D.get_closest_point_to_segment(c.global_position, from, to)
		if p.distance_squared_to(c.global_position) < r * r:
			return true
	return false


## A small puff that rises and fades in about a second (overheating guns). Blocks nothing. Drawn on
## render `layers` (a camera can leave it out).
static func wisp(ctx: Node, pos: Vector3, size := 0.8, layers := 1) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	mi.mesh = quad
	mi.layers = layers
	var mat := puff_material(Color(0.55, 0.55, 0.55, 0.7))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ctx.get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "global_position", pos + Vector3(randf_range(-0.3, 0.3), 1.6, randf_range(-0.3, 0.3)), 1.1)
	tw.tween_property(mi, "scale", Vector3.ONE * 2.2, 1.1)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(mi.queue_free)


## Unshaded so a thick screen reads the same from the gun decks as from above.
static func puff_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = color
	m.albedo_texture = puff_texture()
	return m


## The soft round puff every smoke quad is drawn with (white, fading out to the edge).
static func puff_texture() -> GradientTexture2D:
	if _puff_tex == null:
		_puff_tex = _puff_texture()
	return _puff_tex


func blocking_radius() -> float:
	return radius * _density()


## 0..1: swelling at first, full while it holds, thinning out at the end.
func _density() -> float:
	var grow := clampf(_age / GROW_TIME, 0.0, 1.0)
	var fade := clampf((duration - _age) / FADE_TIME, 0.0, 1.0)
	return minf(grow, fade)


func _enter_tree() -> void:
	clouds.append(self)


func _exit_tree() -> void:
	clouds.erase(self)


func _ready() -> void:
	_mat = puff_material(Color(COLOR, 0.0))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 1.8
	for i in PUFFS:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# One puff in the middle, the rest spread through the ball.
		var off := Vector3.ZERO if i == 0 else _random_in_sphere() * radius * 0.55
		var drift := Vector3(randf_range(-1, 1), randf_range(0.0, 0.6), randf_range(-1, 1)) * 0.06
		_puffs.append([mi, off, drift, randf_range(0.75, 1.0)])
	_update_puffs()


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	_update_puffs()


func _update_puffs() -> void:
	var d := _density()
	_mat.albedo_color.a = ALPHA * d
	# Puffs burst out of the middle, then drift slowly; they spread out a little as they thin.
	var burst := 1.0 - pow(1.0 - clampf(_age / GROW_TIME, 0.0, 1.0), 3.0)
	var spread := 1.0 + (1.0 - d) * 0.4 * float(_age > GROW_TIME)
	for p in _puffs:
		var mi: MeshInstance3D = p[0]
		mi.position = p[1] * burst * spread + p[2] * _age
		mi.scale = Vector3.ONE * p[3] * lerpf(0.35, 1.0, burst)


static func _random_in_sphere() -> Vector3:
	while true:
		var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if v.length_squared() <= 1.0:
			return v
	return Vector3.ZERO


## Soft round puff so the quads don't show square edges.
static func _puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t
