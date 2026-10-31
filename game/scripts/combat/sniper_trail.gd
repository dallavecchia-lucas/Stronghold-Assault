class_name SniperTrail
extends Node3D
## A Sniper's round (SniperTrooper.shoot) as everyone sees it: a long, bright tracer streaks from the
## muzzle to where the round landed at SPEED, and the white trail it leaves along its path hangs there for
## HOLD seconds once it is home, spreading a little like a vapour trail, then fades out over FADE. Both are
## strips turned to face whichever camera is looking (the scope, the RTS view), soft at the edges, never
## wider on its screen than MAX_PIXELS (from the scope, just behind the muzzle, they are a fine line running
## out to the target instead of a wall across the magnified view) and never narrower than their MIN_PIXELS
## (from the RTS camera, high over the field, they still read). A trail alone (trail()) follows a round whose
## tracer is drawn by something else (Combat.spawn_tracer, the Serpent Sniper's rifle), at that tracer's speed.

const SPEED := 520.0
## Longer than a frame's flight at 30 fps, so the streak never jumps.
const TRACER_LENGTH := 18.0
const TRACER_WIDTH := 0.45
const TRACER_COLOR := Color(2.2, 2.7, 3.2)  # past white: it blooms
const TRAIL_WIDTH := 0.45
## How fast the trail spreads as it hangs (m of width a second), and how opaque it is.
const TRAIL_SPREAD := 0.2
const TRAIL_ALPHA := 0.85
const HOLD := 1.0
const FADE := 0.6
const MAX_PIXELS := 10.0
const TRACER_MIN_PIXELS := 6.0
const TRAIL_MIN_PIXELS := 5.0
## Pieces each strip is drawn in (each its own width).
const PIECES := 16

var from := Vector3.ZERO
var to := Vector3.ZERO
## How fast the round flies (m/s), how long its tracer is (m) and whether this draws it.
var speed := SPEED
var tracer_length := TRACER_LENGTH
var with_tracer := true
## Seconds since the round left the muzzle, and since the trail was whole (-1: not yet).
var age := 0.0
var held := -1.0

var _length := 0.0
var _dir := Vector3.FORWARD
var _tracer: ImmediateMesh
var _trail: ImmediateMesh
var _trail_mat: StandardMaterial3D

static var _tracer_mat: StandardMaterial3D
static var _streak_tex: GradientTexture2D
static var _band_tex: GradientTexture2D


## A round from `p_from` that landed at `p_to`.
static func fire(ctx: Node, p_from: Vector3, p_to: Vector3) -> SniperTrail:
	var s := SniperTrail.new()
	s.from = p_from
	s.to = p_to
	ctx.get_tree().current_scene.add_child(s)
	return s


## Only the white trail of a round from `p_from` that landed at `p_to`, flying at `p_speed` behind a tracer
## drawn by something else.
static func trail(ctx: Node, p_from: Vector3, p_to: Vector3, p_speed: float) -> SniperTrail:
	var s := SniperTrail.new()
	s.from = p_from
	s.to = p_to
	s.speed = p_speed
	s.tracer_length = 0.0
	s.with_tracer = false
	ctx.get_tree().current_scene.add_child(s)
	return s


func _ready() -> void:
	_length = from.distance_to(to)
	_dir = (to - from) / maxf(_length, 0.001)
	if _tracer_mat == null:
		_tracer_mat = StandardMaterial3D.new()
		_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tracer_mat.albedo_color = TRACER_COLOR
		_tracer_mat.albedo_texture = _streak_texture()
		_tracer_mat.disable_receive_shadows = true
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.albedo_color = Color(1.0, 1.0, 1.0, TRAIL_ALPHA)
	_trail_mat.albedo_texture = _band_texture()
	_trail_mat.disable_receive_shadows = true
	_trail = _strip(_trail_mat)
	_tracer = _strip(_tracer_mat)
	_place()


func _strip(mat: Material) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	return im


func _process(delta: float) -> void:
	age += delta
	if held >= 0.0:
		held += delta
		_trail_mat.albedo_color.a = TRAIL_ALPHA * clampf(1.0 - (held - HOLD) / FADE, 0.0, 1.0)
		if held >= HOLD + FADE:
			queue_free()
			return
	elif tail() >= _length:
		held = 0.0
	_place()


## How far along the path the tracer's head and tail are (m from the muzzle).
func head() -> float:
	return minf(age * speed, _length)


func tail() -> float:
	return clampf(age * speed - tracer_length, 0.0, _length)


## The tracer from its tail to its head, the trail from the muzzle up to the tracer's tail, each turned to
## face the camera.
func _place() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else from - _dir * 10.0 + Vector3.UP
	# A pixel on that camera's screen, as metres a metre away from it.
	var px := 2.0 * tan(deg_to_rad(cam.fov if cam else 55.0) * 0.5) / get_viewport().get_visible_rect().size.y
	if with_tracer:
		_lay(_tracer, tail(), head(), TRACER_WIDTH, eye, px * TRACER_MIN_PIXELS, px * MAX_PIXELS)
	_lay(_trail, 0.0, tail(), TRAIL_WIDTH + TRAIL_SPREAD * age, eye, px * TRAIL_MIN_PIXELS, px * MAX_PIXELS)


## Lays strip `im` along the path from `a` to `b` (m from the muzzle), `width` across (kept between `lo`
## and `hi` times its distance from `eye`), its face to `eye`. U runs along it (0 to 1), V across.
func _lay(im: ImmediateMesh, a: float, b: float, width: float, eye: Vector3, lo: float, hi: float) -> void:
	im.clear_surfaces()
	if b - a <= 0.05:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in PIECES + 1:
		var u := float(k) / PIECES
		var p := from + _dir * lerpf(a, b, u)
		var n := eye - p
		var dist := n.length()
		n -= _dir * n.dot(_dir)
		var side := _dir.cross(n).normalized() if n.length() > 0.001 else _dir.cross(Vector3.UP).normalized()
		var half := clampf(width, lo * dist, hi * dist) * 0.5
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(p + side * half)
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(p - side * half)
	im.surface_end()


## The tracer's look: brightest down its middle, fading to its ends and edges.
static func _streak_texture() -> GradientTexture2D:
	if _streak_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_streak_tex = GradientTexture2D.new()
		_streak_tex.gradient = g
		_streak_tex.fill = GradientTexture2D.FILL_RADIAL
		_streak_tex.fill_from = Vector2(0.5, 0.5)
		_streak_tex.fill_to = Vector2(1.0, 0.5)
		_streak_tex.width = 64
		_streak_tex.height = 16
	return _streak_tex


## The trail's look: solid down its middle, soft at its edges, even along it.
static func _band_texture() -> GradientTexture2D:
	if _band_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_band_tex = GradientTexture2D.new()
		_band_tex.gradient = g
		_band_tex.fill_from = Vector2(0.0, 0.0)
		_band_tex.fill_to = Vector2(0.0, 1.0)
		_band_tex.width = 4
		_band_tex.height = 32
	return _band_tex
