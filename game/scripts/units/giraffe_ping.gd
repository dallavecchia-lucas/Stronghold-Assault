class_name GiraffePing
extends Node3D
## One sonar ping from a giraffe's dish (AttackerUnit.start_ping): a pulse spreading out from where it
## stood at `speed` m/s to `radius` m (flat). Every defender soldier and squad trooper the pulse
## reaches is marked by a red blur where it stood the moment the pulse got to it, like a contact on a
## sonar screen: the blur stays there and fades over `mark` seconds, it doesn't follow the defender.
## Infiltrators under adaptive camo get a blur like everyone; one caught out of camo is revealed too
## (InfiltratorTrooper.reveal): attackers can pick her out and go after her on their own until she
## puts the camo on or slips back into the fog of war.
##
## The ring and the blurs are the attacker's radar: they show on the attacker's side only (the human
## attacker's screen), over the fog of war.

signal marked(target: Node3D, at: Vector3)

const COLOR := Color(1.0, 0.16, 0.12)
const RING_COLOR := Color(0.45, 1.0, 0.6)
## Blur size (m across) and how far off the real spot it may sit (sonar is not that precise).
const BLUR_SIZE := 3.4
const BLUR_JITTER := 0.8

static var _blur_tex: ImageTexture
static var _ring_mesh: TorusMesh

var team := GameConfig.TEAM_ATTACKER
var radius := 60.0
var speed := 40.0
var mark := 7.0
## How far the pulse has spread (m).
var reach := 0.0
## Defenders the pulse has reached (instance id -> true), and how many.
var _hit := {}
var hits := 0
var revealed := 0
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _fade := 0.0


## Shown on the attacker's side only.
static func shown() -> bool:
	return GameConfig.player_side == GameConfig.PlayerSide.ATTACKER


func _ready() -> void:
	top_level = true
	if shown():
		if _ring_mesh == null:
			_ring_mesh = TorusMesh.new()
			_ring_mesh.inner_radius = 0.975
			_ring_mesh.outer_radius = 1.0
			_ring_mesh.rings = 96
			_ring_mesh.ring_segments = 4
		_ring = MeshInstance3D.new()
		_ring.mesh = _ring_mesh
		_ring_mat = Mats.unshaded(RING_COLOR, true).duplicate()  # its own: it fades out
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.render_priority = 10
		_ring.material_override = _ring_mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.position.y = 0.4
		_ring.scale = Vector3(0.01, 0.02, 0.01)
		add_child(_ring)


func _physics_process(delta: float) -> void:
	if reach >= radius:
		_fade += delta
		if _ring:
			_ring_mat.albedo_color.a = maxf(1.0 - _fade / 0.4, 0.0)
		if _fade > 0.4:
			queue_free()
		return
	reach = minf(reach + speed * delta, radius)
	if _ring:
		_ring.scale = Vector3(reach, 0.02 * reach, reach)
		_ring_mat.albedo_color.a = lerpf(0.9, 0.35, reach / radius)
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if not (d is DefenderSoldier or d is SquadTrooper) or d.team == team or not d.is_alive():
			continue
		var id: int = d.get_instance_id()
		if _hit.has(id):
			continue
		var to: Vector3 = d.global_position - global_position
		if Vector2(to.x, to.z).length() > reach:
			continue
		_hit[id] = true
		hits += 1
		if d is InfiltratorTrooper and d.reveal():
			revealed += 1
		var at: Vector3 = d.global_position
		if shown():
			blur(self, at)
		marked.emit(d, at)


## A red blur over `at`, fading out over `mark` seconds where it is.
func blur(ctx: Node, at: Vector3) -> void:
	var s := Sprite3D.new()
	s.texture = _blur_texture()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 20
	s.pixel_size = BLUR_SIZE / s.texture.get_width()
	s.modulate = COLOR
	ctx.get_tree().current_scene.add_child(s)
	var a := randf() * TAU
	s.global_position = at + Vector3(cos(a), 0.0, sin(a)) * BLUR_JITTER * sqrt(randf()) + Vector3.UP * 1.2
	s.add_to_group("ping_blurs")
	# A blip: flares up as the pulse gets there, then dims away.
	s.scale = Vector3.ONE * 0.4
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 1.15, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector3.ONE, 0.3)
	tw.parallel().tween_property(s, "modulate:a", 0.8, 0.3)
	tw.tween_property(s, "modulate:a", 0.0, maxf(mark - 0.48, 0.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)


## A soft round red blot, brightest in the middle, smudged so it reads as a sonar contact and not a
## unit (white: the sprite tints it).
static func _blur_texture() -> ImageTexture:
	if _blur_tex:
		return _blur_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blobs := []
	for k in 5:
		blobs.append([Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18)), rng.randf_range(0.28, 0.45)])
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var a := 0.0
			for b in blobs:
				var d: float = (p - b[0]).length() / b[1]
				a = maxf(a, exp(-d * d * 2.2))
			var core := exp(-p.length_squared() * 9.0)
			a = clampf(a * 0.75 + core * 0.5, 0.0, 1.0) * clampf((1.0 - p.length()) * 4.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.85 + 0.15 * core, 0.85 + 0.15 * core, a))
	_blur_tex = ImageTexture.create_from_image(img)
	return _blur_tex
