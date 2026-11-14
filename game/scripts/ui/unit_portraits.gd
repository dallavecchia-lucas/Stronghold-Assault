class_name UnitPortraits
extends Node
## Portraits of the attacker unit types for the RTS HUD (AttackerHUD), rendered from the units' own models when the match
## starts, so a new unit type gets its pictures with no art to make:
##   "thumb"  the whole unit, three-quarters front (the production grid, the production line, the groups)
##   "mug"    its head and shoulders (the selected unit's mugshot)
## One SubViewport with a world of its own and a studio light renders them, one a frame; each picture is read back into an
## ImageTexture (get_texture) and the viewport is freed once they are all done. Until a picture is in, and with no
## renderer at all (--headless), get_texture() returns null and the HUD draws the unit's initials (initials()) instead.
##
## Framing comes from the model's bounding box (the models face +Z, their feet at the origin). The mug aims at where the
## head usually is, high on the front of the box (MUG_AT); MUG_TUNE puts it right for the units built otherwise.

signal portrait_ready(type_id: String, kind: String)

const SIZE := 160
const FOV := 26.0
## The camera's bearing round from straight ahead and down onto the unit (rad): the face and a flank show.
const THUMB_YAW := 0.55
const THUMB_PITCH := 0.22
const MUG_YAW := 0.35
const MUG_PITCH := 0.1
## How much of the bounding sphere the thumb shows (under 1 crops the box's empty corners).
const THUMB_FILL := 0.84
## The head, as fractions of the bounding box: (up its height, back from its front along its depth).
const MUG_AT := Vector2(0.8, 0.18)
## How far round the head the mug shows, as a fraction of the box's height (or width, if wider).
const MUG_FRAME := 0.3
## Per unit type: {"at": Vector2 like MUG_AT, "frame": float like MUG_FRAME}. The snake is long and low, its head at the
## front of the box.
const MUG_TUNE := {
	"serpent": {"at": Vector2(0.6, 0.06), "frame": 1.0},
}

static var _textures := {}  # "type_id:kind" -> Texture2D

var _vp: SubViewport
var _cam: Camera3D
var _jobs: Array = []


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
		for kind in ["thumb", "mug"]:
			if not _textures.has(type_id + ":" + kind):
				_jobs.append([type_id, kind])
	if _jobs.is_empty():
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.8)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam = Camera3D.new()
	_cam.environment = env
	_cam.fov = FOV
	_cam.near = 0.05
	_vp.add_child(_cam)
	# A warm key light from the camera's side, high, and a cool rim light from behind.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.95, 0.88)
	key.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(40.0), 0.0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(190.0), 0.0)
	_vp.add_child(rim)
	_run()


func _run() -> void:
	# The match's first frames go to its own shaders: start a moment later.
	await get_tree().process_frame
	while not _jobs.is_empty():
		var job: Array = _jobs.pop_front()
		var model := _instance(job[0])
		if model == null:
			continue
		_vp.add_child(model)
		_pose(model, job[0])
		_frame(model, job[0], job[1])
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_vp):
			return
		var img := _vp.get_texture().get_image()
		model.queue_free()
		if img != null and not img.is_empty():
			_textures[job[0] + ":" + job[1]] = ImageTexture.create_from_image(img)
			portrait_ready.emit(job[0], job[1])
		await get_tree().process_frame
	_vp.queue_free()
	_vp = null


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


## Stands it in the first frame of its idle clip (the talon in its glide).
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
		anim.pause()


## Puts the camera on the whole model ("thumb") or its head ("mug").
func _frame(m: Node3D, type_id: String, kind: String) -> void:
	var box := _bounds(m)
	var at := box.get_center()
	var radius := box.size.length() * 0.5 * THUMB_FILL
	var yaw := THUMB_YAW
	var pitch := THUMB_PITCH
	if kind == "mug":
		var tune: Dictionary = MUG_TUNE.get(type_id, {})
		var f: Vector2 = tune.get("at", MUG_AT)
		at = Vector3(at.x, box.position.y + box.size.y * f.x, box.end.z - box.size.z * f.y)
		radius = maxf(box.size.y, box.size.x) * float(tune.get("frame", MUG_FRAME))
		yaw = MUG_YAW
		pitch = MUG_PITCH
	radius = maxf(radius, 0.2)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var dist := radius / sin(deg_to_rad(FOV) * 0.5)
	_cam.position = at + dir * dist
	_cam.look_at(at, Vector3.UP)
	_cam.far = dist + box.size.length() * 2.0 + 10.0


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
