class_name Minimap
extends Control
## The attacking player's minimap (AttackerHUD, top right): the whole map, north up (-z up, +x right).
##
## The land is drawn once when the match starts, from the map's own data rather than a render: on the Jungle Keep the
## ground's heights (JungleTerrain, hill-shaded), the rivers and the lake, the forest and the clearing; on the classic field
## its groves (LevelBuilder.FORESTS). Over it, live:
##   the fog of war   dark beyond what the army sees (AttackerVision's viewers), redrawn a few times a second
##   the stronghold   the mountain, its air vents (destroyed ones crossed out) and its gates (by health; open when down)
##   the helipads     held (green), sabotaged (red, blinking) or being retaken (amber), and the spawn point the HUD's
##                    production comes out at (a ring)
##   bridges          cyan across the rivers, red while their alarm goes off
##   units            the army (green; white when selected, the transport helicopters as white squares), and the
##                    defenders it sees (red)
##   pings            rings where a warning came from (flash())
##   the camera       its view on the ground (white outline)
## LMB (or drag) moves the camera there; RMB sends the selected units there (attack-move; Ctrl+RMB: move).

const RES := 256
const FOG_RES := 128
const FOG_EVERY := 0.2
const FOG_ALPHA := 150
const OWN := Color(0.35, 1.0, 0.5)
const ENEMY := Color(1.0, 0.3, 0.25)
const WATER := Color(0.13, 0.28, 0.42)
const FOREST := Color(0.12, 0.24, 0.12)
const GRASS := Color(0.33, 0.42, 0.2)
const ROCK := Color(0.42, 0.4, 0.38)
const PING_TIME := 2.5

var controller: AttackerController
var level: LevelBuilder

var _base: ImageTexture
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_bytes := PackedByteArray()
var _fog_cd := 0.0
var _dragging := false
## [position, colour, seconds left]
var _pings: Array = []
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_base()
	_fog_bytes.resize(FOG_RES * FOG_RES * 4)
	for k in FOG_RES * FOG_RES:
		_fog_bytes[k * 4] = 4
		_fog_bytes[k * 4 + 1] = 6
		_fog_bytes[k * 4 + 2] = 12
		_fog_bytes[k * 4 + 3] = FOG_ALPHA
	_fog_img = Image.create_from_data(FOG_RES, FOG_RES, false, Image.FORMAT_RGBA8, _fog_bytes)
	_fog_tex = ImageTexture.create_from_image(_fog_img)


## A ring flashing at `pos` for a moment (a warning's place).
func flash(pos: Vector3, col: Color) -> void:
	_pings.append([pos, col, PING_TIME])


func _process(delta: float) -> void:
	_t += delta
	for p in _pings:
		p[2] -= delta
	_pings = _pings.filter(func(p): return p[2] > 0.0)
	_fog_cd -= delta
	if _fog_cd <= 0.0:
		_fog_cd = FOG_EVERY
		_update_fog()
	queue_redraw()


# ---------------------------------------------------------------- the land

func _build_base() -> void:
	var half := LevelBuilder.map_half
	var cell := 2.0 * half / RES
	var img := Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	var terrain: Object = LevelBuilder.terrain if LevelBuilder.jungle else null
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	if terrain:
		for j in RES:
			var z := -half + (j + 0.5) * cell
			for i in RES:
				heights[j * RES + i] = terrain.height_at(-half + (i + 0.5) * cell, z)
	for j in RES:
		var z := -half + (j + 0.5) * cell
		for i in RES:
			var x := -half + (i + 0.5) * cell
			var h := heights[j * RES + i]
			var col := _ground(Vector2(x, z), h)
			if terrain and h >= JungleLayout.WATER_Y + 0.15:
				# Hill shading, the light from the north-west.
				var hl := heights[j * RES + maxi(i - 1, 0)]
				var hr := heights[j * RES + mini(i + 1, RES - 1)]
				var hu := heights[maxi(j - 1, 0) * RES + i]
				var hd := heights[mini(j + 1, RES - 1) * RES + i]
				var shade := clampf(1.0 + ((hl - hr) + (hu - hd)) / cell * 0.55, 0.55, 1.45)
				col = Color(col.r * shade, col.g * shade, col.b * shade).lightened(clampf(h / 120.0, 0.0, 0.25))
			img.set_pixel(i, j, col)
	_base = ImageTexture.create_from_image(img)


## The land's colour at (x, z), its height `h`: water, the stronghold's rock, forest or open ground.
func _ground(p: Vector2, h: float) -> Color:
	if absf(p.x) <= LevelBuilder.MOUNTAIN_HALF and absf(p.y) <= LevelBuilder.MOUNTAIN_HALF:
		return ROCK.darkened(0.25 if maxf(absf(p.x), absf(p.y)) < LevelBuilder.MOUNTAIN_HALF * 0.55 else 0.0)
	if LevelBuilder.jungle:
		if h < JungleLayout.WATER_Y + 0.15:
			var depth := clampf((JungleLayout.WATER_Y - h) / 4.0, 0.0, 1.0)
			return WATER.lightened(0.25 * (1.0 - depth))
		var open := p.length() < JungleLayout.CLEARING_R + JungleLayout.CLEARING_EDGE * 0.4
		for f in JungleLayout.FLATTEN:
			if p.distance_to(f[0]) < f[1] * 0.85:
				open = true
		return GRASS if open else FOREST
	for f in LevelBuilder.FORESTS:
		if p.distance_to(Vector2(f[0], f[1])) <= f[2]:
			return FOREST
	return GRASS


# ---------------------------------------------------------------- the fog

func _update_fog() -> void:
	var vision := AttackerVision.instance
	if vision == null:
		return
	var half := LevelBuilder.map_half
	var cell := 2.0 * half / FOG_RES
	for k in FOG_RES * FOG_RES:
		_fog_bytes[k * 4 + 3] = FOG_ALPHA
	for v in vision.viewers:
		var at: Vector3 = v[0]
		var r: float = v[1]
		var i0 := clampi(int((at.x - r + half) / cell), 0, FOG_RES - 1)
		var i1 := clampi(int((at.x + r + half) / cell), 0, FOG_RES - 1)
		var j0 := clampi(int((at.z - r + half) / cell), 0, FOG_RES - 1)
		var j1 := clampi(int((at.z + r + half) / cell), 0, FOG_RES - 1)
		for j in range(j0, j1 + 1):
			var dz := -half + (j + 0.5) * cell - at.z
			for i in range(i0, i1 + 1):
				var dx := -half + (i + 0.5) * cell - at.x
				if dx * dx + dz * dz <= r * r:
					_fog_bytes[(j * FOG_RES + i) * 4 + 3] = 0
	_fog_img.set_data(FOG_RES, FOG_RES, false, Image.FORMAT_RGBA8, _fog_bytes)
	_fog_tex.update(_fog_img)


# ---------------------------------------------------------------- drawing

func to_map(p: Vector3) -> Vector2:
	var half := LevelBuilder.map_half
	return Vector2((p.x + half) / (2.0 * half) * size.x, (p.z + half) / (2.0 * half) * size.y)


func to_world(v: Vector2) -> Vector3:
	var half := LevelBuilder.map_half
	var p := Vector3(v.x / size.x * 2.0 * half - half, 0.0, v.y / size.y * 2.0 * half - half)
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	p.y = LevelBuilder.ground_height(p)
	return p


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _base:
		draw_texture_rect(_base, r, false)
	if AttackerVision.instance and _fog_tex:
		draw_texture_rect(_fog_tex, r, false)
	var px := size.x / (2.0 * LevelBuilder.map_half)  # minimap pixels a metre
	var blink := fmod(_t * 2.0, 1.0) < 0.5
	_draw_stronghold(px)
	_draw_bases(px, blink)
	_draw_bridges(px, blink)
	_draw_spawn()
	_draw_units()
	for p in _pings:
		var k: float = p[2] / PING_TIME
		var at := to_map(p[0])
		var col: Color = p[1]
		draw_arc(at, 4.0 + (1.0 - fmod(k * 3.0, 1.0)) * 16.0, 0.0, TAU, 24, Color(col, k), 2.0, true)
	_draw_view()
	draw_rect(r.grow(-0.5), Color(0.5, 0.56, 0.66, 0.9), false, 1.0)


func _draw_stronghold(px: float) -> void:
	var mh := LevelBuilder.MOUNTAIN_HALF
	draw_rect(Rect2(to_map(Vector3(-mh, 0, -mh)), Vector2(2.0 * mh, 2.0 * mh) * px), Color(0.1, 0.1, 0.12, 0.9), false, 1.0)
	for v in level.vents:
		var at := to_map(v.global_position)
		if v.is_alive():
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -3), at + Vector2(3, 0), at + Vector2(0, 3), at + Vector2(-3, 0)]),
					UIKit.WARN.lerp(UIKit.DANGER, 1.0 - v.hp / v.max_hp))
		else:
			draw_line(at + Vector2(-2.5, -2.5), at + Vector2(2.5, 2.5), Color(0.15, 0.15, 0.15), 1.5)
			draw_line(at + Vector2(-2.5, 2.5), at + Vector2(2.5, -2.5), Color(0.15, 0.15, 0.15), 1.5)
	for side in level.gates:
		var g: Structure = level.gates[side]
		var at := to_map(g.global_position)
		var col := UIKit.GOOD if not g.is_alive() else UIKit.DANGER if g.recently_damaged(1.0) else UIKit.WARN
		draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), col, g.is_alive())


func _draw_bases(px: float, blink: bool) -> void:
	for b in level.bases:
		var at := to_map(b.global_position)
		var half := Vector2(maxf(b.deck_size.x * px * 0.5, 4.0), maxf(b.deck_size.y * px * 0.5, 4.0))
		var col := OWN
		if not b.controlled:
			col = UIKit.WARN if b.capture > 0.0 else UIKit.DANGER
			if blink:
				col = col.darkened(0.4)
		draw_rect(Rect2(at - half, half * 2.0), Color(col, 0.35))
		draw_rect(Rect2(at - half, half * 2.0), col, false, 1.5)


func _draw_bridges(px: float, blink: bool) -> void:
	if controller == null:
		return
	for b in controller.commander.bridges:
		if not is_instance_valid(b):
			continue
		var a := to_map(b.global_transform * Vector3(-b.length * 0.5, 0, 0))
		var c := to_map(b.global_transform * Vector3(b.length * 0.5, 0, 0))
		var col := UIKit.DANGER if b.alarm_on and blink else AttackerController.BRIDGE_OK
		if not b.is_standing():
			col = Color(col, 0.45)
		draw_line(a, c, col, maxf(2.5, FoldingBridge.HALF_WIDTH * 2.0 * px), true)


func _draw_spawn() -> void:
	if controller == null:
		return
	var points := controller.commander.spawn_points
	for k in points.size():
		if not controller.commander.spawn_open(k):
			continue
		var at := to_map(points[k])
		if k == controller.spawn_index:
			draw_arc(at, 7.0, 0.0, TAU, 20, Color.WHITE, 2.0, true)
		draw_circle(at, 2.0, Color(1, 1, 1, 0.8))


func _draw_units() -> void:
	# The defenders the army sees: soldiers, squad troopers and the machines (not the stronghold's emplacements).
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if not (d is DefenderSoldier or d is SquadTrooper or d is DefenderMachine):
			continue
		var n := d as Node3D
		if not n.is_visible_in_tree() or not AttackerVision.sees_node(n):
			continue
		if n.has_method("is_alive") and not n.call("is_alive"):
			continue
		draw_rect(Rect2(to_map(n.global_position) - Vector2(1.5, 1.5), Vector2(3, 3)), ENEMY)
	if controller == null:
		return
	for u in controller.commander.units.values():
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var at := to_map(u.global_position)
		var col := Color.WHITE if u.selected else OWN
		if u.is_flying():
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -3), at + Vector2(2.5, 2), at + Vector2(-2.5, 2)]), col)
		else:
			var s := 2.0 if u.stats.radius < 1.0 else 3.0
			draw_rect(Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	var fleet := controller.commander.fleet
	if fleet:
		for i in fleet.slots.size():
			var h := fleet.helo_at(i)
			if h and h.is_alive():
				var at := to_map(h.global_position)
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color(1, 1, 1, 0.9), false, 1.5)
				draw_line(at + Vector2(-2, -2.5), at + Vector2(-2, 2.5), Color.WHITE, 1.0)
				draw_line(at + Vector2(2, -2.5), at + Vector2(2, 2.5), Color.WHITE, 1.0)
				draw_line(at + Vector2(-2, 0), at + Vector2(2, 0), Color.WHITE, 1.0)


## The camera's view on the ground: the screen's corners cast down onto the ground under the camera's focus.
func _draw_view() -> void:
	if controller == null or controller.camera_rig == null or controller.camera_rig.camera == null:
		return
	var cam := controller.camera_rig.camera
	var vs := get_viewport().get_visible_rect().size
	var ground := Plane(Vector3.UP, controller.camera_rig.global_position.y)
	var pts := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var from := cam.project_ray_origin(corner)
		var dir := cam.project_ray_normal(corner)
		var hit = ground.intersects_ray(from, dir)
		var p: Vector3 = hit if hit != null else from + Vector3(dir.x, 0.0, dir.z).normalized() * 1200.0
		pts.append(to_map(p))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.85), 1.0, true)


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if controller == null:
		return
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				controller.camera_rig.focus(to_world(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			controller.order_at(to_world(mb.position), mb.ctrl_pressed)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		controller.camera_rig.focus(to_world((event as InputEventMouseMotion).position))
		accept_event()
