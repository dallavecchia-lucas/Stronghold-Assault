class_name UnitPortraits
extends Node
## Portraits of the attacker unit types for the RTS HUD (AttackerHUD), rendered from the units' own models when the match
## starts, so a new unit type gets its pictures with no art to make:
##   "thumb"  the whole unit, three-quarters front (the production card, the production line, the groups)
##   "mug"    the top of it, round its head (the selected unit's mugshot)
## One SubViewport with a world of its own and a studio light renders each unit in its idle clip, one a frame; the picture
## is read back and cut to what is on it (the opaque pixels), so the framing doesn't hang on the model's bounding box: some
## rigs only take their size once their clip plays. A unit that comes out small is rendered again closer (REFRAME). The
## viewport is freed once they are all done. Until a picture is in, and with no renderer at all (--headless),
## get_texture() returns null and the HUD draws the unit's initials (initials()) instead.

signal portrait_ready(type_id: String)

## The pictures' size (px), and the render's they are cut from.
const SIZE := 160
const RENDER := 384
const FOV := 30.0
## The camera's bearing round from straight ahead and down onto the unit (rad): the face and a flank show (models face +Z).
const YAW := 0.55
const PITCH := 0.2
## The first render frames the bounding sphere this much wider, so a clip's pose can't stick out of it.
const FIRST_FILL := 1.2
## Rendered again closer when the unit takes less than this share of the render's side.
const REFRAME := 0.55
## Room round the unit in the thumb (a share of its larger side).
const PAD := 0.05
## The mug: a square this share of the unit's larger side round its head bone (_head); with no head bone, from the top of
## the unit, centred on the top band's opaque pixels (TOP_BAND of the unit's height).
const MUG_SHARE := 0.55
const TOP_BAND := 0.22
## The mug's middle sits this share of its side under the head, so some neck and shoulders show.
const MUG_DROP := 0.12

static var _textures := {}  # "type_id:kind" -> Texture2D

var _vp: SubViewport
var _cam: Camera3D
var _jobs: Array[String] = []


## The `kind` ("thumb" or "mug") picture of `type_id`; null until it is rendered.
static func get_texture(type_id: String, kind := "thumb") -> Texture2D:
	return _textures.get(type_id + ":" + kind)


## The unit's initials, for its tile until its picture is in ("Bear Rifleman": "BR").
static func initials(type_id: String) -> String:
	var out := ""
	for word in String(UnitTypes.DATA[type_id].name).split(" ", false):
		out += word.left(1).to_upper()
	return out.left(2)


## A colour per role, for the tiles' backgrounds.
static func role_tint(type_id: String) -> Color:
	match String(UnitTypes.DATA[type_id].role):
		"infantry":
			return Color(0.16, 0.2, 0.26, 0.95)
		"melee":
			return Color(0.26, 0.17, 0.15, 0.95)
		"anti_air":
			return Color(0.15, 0.22, 0.27, 0.95)
		"siege":
			return Color(0.25, 0.22, 0.13, 0.95)
		"flying":
			return Color(0.15, 0.2, 0.3, 0.95)
		"healer":
			return Color(0.14, 0.25, 0.17, 0.95)
	return HudSlot.BG


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for type_id in UnitTypes.ORDER:
		if not _textures.has(type_id + ":thumb"):
			_jobs.append(type_id)
	if _jobs.is_empty():
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(RENDER, RENDER)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	_cam = Camera3D.new()
	_cam.environment = env
	_cam.fov = FOV
	_cam.near = 0.05
	_vp.add_child(_cam)
	# A warm key light from the camera's side, high, and a cool rim light from behind.
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.95, 0.88)
	key.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(40.0), 0.0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.2
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(190.0), 0.0)
	_vp.add_child(rim)
	_run()


func _run() -> void:
	# The match's first frames go to its own shaders: start a moment later.
	await get_tree().process_frame
	while not _jobs.is_empty():
		var type_id: String = _jobs.pop_front()
		var model := _instance(type_id)
		if model == null:
			continue
		_vp.add_child(model)
		_pose(model, type_id)
		var box := _bounds(model)
		var at := box.get_center()
		var radius := maxf(box.size.length() * 0.5 * FIRST_FILL, 0.3)
		var img: Image = await _render(at, radius)
		if img == null:
			return
		var used := img.get_used_rect()
		if used.has_area() and maxi(used.size.x, used.size.y) < RENDER * REFRAME:
			# Small on the picture: closer, onto what is there.
			var depth := _cam.global_position.distance_to(at)
			at = _cam.global_position + _cam.project_ray_normal(Vector2(used.get_center())) * depth
			radius *= float(maxi(used.size.x, used.size.y)) / RENDER * 1.15
			img = await _render(at, radius)
			if img == null:
				return
			used = img.get_used_rect()
		if used.size.x >= 4 and used.size.y >= 4:
			# The mug round the head where the rig has a head bone (the top of a unit is often its gear: a quadruped's head
			# is at its front), on this same render.
			var head = _head(model)
			_store(type_id, img, used, _cam.unproject_position(head) if head != null else Vector2.INF)
			portrait_ready.emit(type_id)
		model.queue_free()
		await get_tree().process_frame
	_vp.queue_free()
	_vp = null


## The camera on `at` from YAW and PITCH, `radius` round it in view; one frame rendered and read back (null if the viewport
## went meanwhile).
func _render(at: Vector3, radius: float) -> Image:
	var dir := Vector3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH))
	var dist := radius / sin(deg_to_rad(FOV) * 0.5)
	_cam.position = at + dir * dist
	_cam.look_at(at, Vector3.UP)
	_cam.far = dist + radius * 4.0 + 10.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_vp):
		return null
	return _vp.get_texture().get_image()


## Where the head is, in the viewport's world: the first bone whose name ends in "head" ("head", "mixamorig_Head", the lead
## animal's "lead_L_head"); null if the rig has none (the mug stays the top of the unit).
static func _head(m: Node3D):
	for node in m.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower().ends_with("head"):
				return sk.global_transform * sk.get_bone_global_pose(i).origin
	return null


## Cuts the thumb (the whole unit) and the mug out of the render; `used`: where the unit is on it, `head`: where its head
## is on it (Vector2.INF: no head bone, the mug is the top of the unit).
static func _store(type_id: String, img: Image, used: Rect2i, head: Vector2) -> void:
	var big := float(maxi(used.size.x, used.size.y))
	_textures[type_id + ":thumb"] = _square(img, Vector2(used.get_center()), big * (1.0 + 2.0 * PAD))
	var side := big * MUG_SHARE
	var centre := head + Vector2(0.0, side * MUG_DROP)
	if head == Vector2.INF:
		var band := Rect2i(used.position, Vector2i(used.size.x, maxi(int(used.size.y * TOP_BAND), 1)))
		centre = Vector2(_opaque_x(img, band), used.position.y + side * (0.5 - PAD))
	_textures[type_id + ":mug"] = _square(img, centre, side)


## The middle (x) of the opaque pixels in `band` of `img`.
static func _opaque_x(img: Image, band: Rect2i) -> float:
	var sum := 0.0
	var n := 0
	for y in range(band.position.y, band.end.y, 2):
		for x in range(band.position.x, band.end.x, 2):
			if img.get_pixel(x, y).a > 0.5:
				sum += x
				n += 1
	return sum / n if n > 0 else float(band.get_center().x)


## A square `side` px round `centre` of `img` (transparent where it runs off it), scaled to SIZE.
static func _square(img: Image, centre: Vector2, side: float) -> ImageTexture:
	var s := maxi(int(ceil(side)), 8)
	var src := Rect2i(Vector2i(roundi(centre.x - s * 0.5), roundi(centre.y - s * 0.5)), Vector2i(s, s))
	var out := Image.create_empty(s, s, false, img.get_format())
	var clipped := src.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clipped.has_area():
		out.blit_rect(img, clipped, clipped.position - src.position)
	out.resize(SIZE, SIZE, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(out)


## The unit's model (and its hand-held gun), or null if it can't be loaded.
static func _instance(type_id: String) -> Node3D:
	var stats: Dictionary = UnitTypes.DATA[type_id]
	if not ResourceLoader.exists(stats.model):
		return null
	var scene := load(stats.model) as PackedScene
	if scene == null:
		return null
	var m := scene.instantiate() as Node3D
	if m != null and stats.has("gun") and ResourceLoader.exists(stats.gun):
		HeldGun.attach(m, stats.gun)
	return m


## Stands it in its idle clip (the talon in its glide), playing: some rigs only take their size once it plays.
static func _pose(m: Node3D, type_id: String) -> void:
	var stats: Dictionary = UnitTypes.DATA[type_id]
	var players := m.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var anim := players[0] as AnimationPlayer
	var clip: String = stats.get("anim_idle", "Glide" if stats.get("anim", "") == "flight" else "")
	if clip != "" and anim.has_animation(clip):
		anim.play(clip)
		anim.seek(0.0, true)
		anim.advance(0.0)


## The model's bounding box, in its own frame (a man-sized box if it has no meshes).
static func _bounds(m: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in m.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box: AABB = m.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.8, 1.0)) if first else out
