extends Node3D
## The Infiltrator Squad's showcase video (media/infiltrator_showcase.mp4): its attack and skills,
## seen from the defender's side (the squad's third-person camera, the way a player drives it) and
## from the attacker's (the RTS view), on the real map in the south field.
##
##   intro     the squad walks out across the field
##   bow       LMB: arrows at a group of Bear Riflemen; the RTS view: no tracer, no flash, only
##             their health bars running down
##   camo      Q: adaptive camo, the defender's vignette; the RTS view: the troopers all but
##             invisible, and a bison's shell (area damage) still hurting them
##   sabotage  F next to the South Helipad: 45 s (sped up); the RTS view: the helipad lost, its
##             spawn button greyed out
##   retake    the RTS view: three riflemen stand by it and retake it
##   op        idle mode: a second squad sent on a sabotage operation (V / Ctrl+F) walks from its hall
##             round the riflemen standing on the straight way (its planned route drawn), to the
##             helipad, and starts the sabotage
##
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie infil.avi \
##       --fixed-fps 30 res://scenes/dev/infiltrator_video.tscn > infil.log
##   python3 tools/video/cut_showcase.py infil.avi infil.log media/infiltrator_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times (seconds of the
## run, as the log's phase lines give them), then quits. The garrison's posts and the AA turrets hold
## fire.

const HERO_AT := Vector3(10.0, 0.0, 100.0)
const FIELD := Vector3(10.0, 0.0, 112.0)
const RIFLE_AT := Vector3(12.0, 0.0, 127.0)
const BISON_AT := Vector3(52.0, 0.0, 150.0)
## Riflemen standing on the straight way from the south gate to the South Helipad (the op).
const WATCH_AT := Vector3(-22.0, 0.0, 100.0)
const ROUTE_COLOR := Color(0.35, 0.9, 0.75)

var level: LevelBuilder
var commander: AttackerCommander
var armory: DefenderArmory
var dc: DefenderController
var ac: AttackerController
var cam: Camera3D
var hero: InfiltratorSquad
var sneak: InfiltratorSquad
var pad: AttackerBase
var riflemen: Array = []
var phase := ""
var t := -1.0
var shot := ""

var _phase_t := 0.0
var _frame := -1
var _fast := 1
var _fast_from := 0
var _move_to := Vector3.INF
var _look := Vector3.INF
var _fire := false
var _marks := {}
var _caption: Label
var _keycap: Label
var _key_t := 0.0
var _route_mesh: ImmediateMesh
var _route_mi: MeshInstance3D
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false


func _ready() -> void:
	seed(5)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	for s in level.stations + level.aa_turrets:
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	add_child(commander)
	pad = level.bases.filter(func(b): return b.side == "south")[0]
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	_route_mesh = ImmediateMesh.new()
	_route_mi = MeshInstance3D.new()
	_route_mi.mesh = _route_mesh
	_route_mi.material_override = Mats.unshaded(ROUTE_COLOR, true)
	_route_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_route_mi.visible = false
	add_child(_route_mi)
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	for k in 10:
		await get_tree().physics_frame
	ac = AttackerController.new()
	ac.level = level
	ac.commander = commander
	add_child(ac)
	ac.camera_rig.edge_scroll = false
	# The RTS help text would sit over the middle of a 720p frame.
	for l in ac.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("LMB select"):
			l.visible = false
	armory = DefenderArmory.new()
	armory.level = level
	armory.credits = DefenderArmory.INFILTRATOR_COST * 2
	add_child(armory)
	dc = DefenderController.new()
	dc.level = level
	dc.armory = armory
	add_child(dc)
	# Both squads deploy in the south spawn hall (the halls go east, west, south in turn).
	armory._bought = 2
	hero = dc.buy_squad("infiltrator") as InfiltratorSquad
	armory._bought = 2
	sneak = dc.buy_squad("infiltrator") as InfiltratorSquad
	hero.pilot = self
	dc.select_squad(0, true)
	for k in 6:
		riflemen.append(_spawn("rifleman", RIFLE_AT + Vector3((k % 3) * 2.6 - 2.6, 0.0, (k / 3) * 2.6)))
	for k in 5:
		_spawn("rifleman", WATCH_AT + Vector3((k % 3) * 3.0 - 3.0, 0.0, (k / 3) * 3.0 - 1.5))
	await get_tree().physics_frame
	_teleport(hero, HERO_AT, FIELD)
	t = 0.0
	_enter("intro")
	RenderingServer.render_loop_enabled = _snaps.is_empty()
	print("VIDEO START frame %d" % (_frame + 1))


func _spawn(type_id: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = at + Vector3.UP * 0.2
	u.rotation.y = atan2(at.x, at.z)  # facing the stronghold
	return u


## Puts a squad down at `at` in a wedge, facing `face` (between shots).
func _teleport(s: InfiltratorSquad, at: Vector3, face: Vector3) -> void:
	var d := face - at
	var yaw := atan2(-d.x, -d.z)
	var basis := Basis(Vector3.UP, yaw)
	var offsets := [Vector3.ZERO, Vector3(-2.2, 0, 2.0), Vector3(2.2, 0, 2.0), Vector3(-4.4, 0, 4.0), Vector3(4.4, 0, 4.0)]
	var order: Array = [s.leader]
	for tr in s.troopers:
		if tr != s.leader:
			order.append(tr)
	for i in order.size():
		var tr: SquadTrooper = order[i]
		tr.global_position = at + basis * offsets[i] + Vector3.UP * 0.1
		tr.velocity = Vector3.ZERO
		tr.rotation.y = yaw
	s.formation.trail.clear()
	s.heading = yaw
	s.cam_yaw = yaw
	s.cam_pitch = deg_to_rad(-10.0)


## The hero's leader as a player drives it: walk for _move_to, look at _look, hold the trigger.
func pilot_input(s: DefenderSquad, delta: float) -> void:
	s.input.move = Vector2.ZERO
	s.input.fire = _fire
	s.input.aim = _fire
	s.input.hustle = false
	if _move_to != Vector3.INF:
		var d := _move_to - s.leader.global_position
		d.y = 0.0
		if d.length() > 0.8:
			var local := Basis(Vector3.UP, -s.cam_yaw) * d.normalized()
			s.input.move = Vector2(local.x, local.z) * clampf(d.length() / 3.0, 0.3, 1.0)
	if _look != Vector3.INF:
		s.look_toward(_look, 2.2, delta)


# ---------------------------------------------------------------- the run

func _enter(p: String) -> void:
	phase = p
	_phase_t = 0.0
	_marks.clear()
	print("INFIL VIDEO t=%.1f phase %s" % [t, p])
	match p:
		"intro":
			_say("Infiltrator Squad", "Deep infiltration: ambushes and sabotage")
			_move_to = FIELD
			_look = FIELD + Vector3(0.0, 1.5, 30.0)
			_shoot("chase")
		"bow":
			_move_to = Vector3.INF
			_look = RIFLE_AT + Vector3.UP * 1.2
			_say("LMB · Bow", "Five troopers loose an arrow each, then draw the next")
			_shoot("def")
		"camo":
			_fire = false
			_look = RIFLE_AT + Vector3(-8.0, 1.0, 0.0)
			_shoot("def")
		"sabotage":
			hero.camo_left = 0.0
			for tr in hero.troopers:
				(tr as InfiltratorTrooper).set_camo(false, false)
			var side := pad.global_transform * Vector3(0.0, 0.0, AttackerBase.SIZE.y * 0.5 + 2.0)
			_teleport(hero, side + (side - pad.global_position).normalized() * 1.0, pad.global_position)
			_look = pad.global_position + Vector3.UP * 7.0
			_say("F · Sabotage", "Next to an enemy helipad: 45 s to take it out of the attackers' hands")
			_shoot("def")
		"retake":
			_teleport(hero, hero.home.origin, hero.home.origin + hero.home.basis * Vector3.FORWARD)
			for k in 3:
				_spawn("rifleman", pad.spawn_point + Vector3(k * 2.0 - 2.0, 0.0, 0.0))
			_say("RTS · Retaking a helipad", "Ground units stand by it for 15 s")
			_shoot("rts")
			_rts_view(pad.global_position + Vector3(10.0, 0.0, 6.0), 58.0)
		"op":
			# Only the riflemen on the straight way stay: the rest walk off to the map's edge.
			var gone := []
			for u in commander.units.values():
				if u.is_alive() and Vector2(u.global_position.x - WATCH_AT.x, u.global_position.z - WATCH_AT.z).length() > 8.0:
					gone.append(u.unit_id)
			for u in riflemen:
				if is_instance_valid(u) and u.is_alive():
					u.take_damage(10000.0, GameConfig.TEAM_DEFENDER)
			commander.submit({"type": "move", "units": gone, "pos": Vector3(-20.0, 0.0, 192.0), "attack": false})
			sneak.set_order(pad)
			_say("Idle mode · Sabotage operation", "Sent off (V / Ctrl+F), it keeps as far from the attackers as it can, all the way")
			_shoot("rts")
			_rts_view(Vector3(-12.0, 0.0, 96.0), 58.0)
			_route_mi.visible = true
		"end":
			_finish()


func _process(delta: float) -> void:
	_frame += 1
	if t < 0.0 or phase == "end":
		return
	t += delta
	_phase_t += delta
	_key_t = maxf(_key_t - delta, 0.0)
	_keycap.visible = _key_t > 0.0
	match phase:
		"intro":
			if _phase_t > 5.0:
				_enter("bow")
		"bow":
			_bow_step()
		"camo":
			_camo_step()
		"sabotage":
			_sabotage_step()
		"retake":
			_set_fast(3 if _phase_t > 2.0 and not pad.controlled else 1)
			if pad.controlled:
				_once("retaken", func(): _say("RTS · Retaken", "It spawns their units again"))
				if _phase_t > _marks.get("retaken_t", INF) + 2.5:
					_enter("op")
				elif not _marks.has("retaken_t"):
					_marks.retaken_t = _phase_t
		"op":
			_op_step()
	if shot == "chase":
		_chase()
	if not _snaps.is_empty():
		_snap()


func _bow_step() -> void:
	if _phase_t > 1.0:
		_fire = true
		_once("lmb", func(): _key("LMB"))
	if _phase_t > 6.0:
		_once("rts", func():
			_say("RTS view · Silent", "No tracer, no flash: the attackers only see their health running down")
			_shoot("rts")
			_rts_view(RIFLE_AT + Vector3(-1.0, 0.0, -9.0), 30.0)
			ac._set_selection([]))
	if _phase_t > 13.0:
		_enter("camo")


func _camo_step() -> void:
	if _phase_t > 1.0:
		_once("q", func():
			_key("Q")
			hero.start_camo()
			_say("Q · Adaptive camo", "20 s: basic attacks can't target them · the defender's view gets a vignette"))
	if _phase_t > 5.5:
		_once("rts", func():
			_say("RTS view · Camouflaged", "Gone from sight, and shots pass through them")
			_shoot("rts")
			_rts_view(hero.leader.global_position + Vector3(4.0, 0.0, 6.0), 26.0))
	if _phase_t > 7.0:
		_once("bison", func():
			var bison := _spawn("bison_gun", BISON_AT)
			bison.look_at(hero.leader.global_position + Vector3.UP * bison.global_position.y)
			commander.submit({"type": "bombard", "units": [bison.unit_id], "pos": hero.leader.global_position}))
	if _phase_t > 9.5:
		_once("splash", func(): _say("RTS view · Splash still hurts", "Area skills aimed at the right spot hit them all the same"))
	if _phase_t > 14.5:
		_enter("sabotage")


func _sabotage_step() -> void:
	if _phase_t > 1.2:
		_once("f", func():
			_key("F")
			hero.toggle_sabotage())
	var f := pad.sabotage_fraction() if pad.controlled else 1.0
	_set_fast(6 if _phase_t > 6.0 and f < 0.94 else 1)
	if f >= 0.94:
		_once("rts", func():
			_say("RTS view · Helipad sabotaged", "The attackers lose it: no spawning there, no supply, until they retake it")
			_shoot("rts")
			_rts_view(pad.global_position + Vector3(8.0, 0.0, 4.0), 48.0))
	if not pad.controlled:
		_once("lost", func(): _marks.lost_t = _phase_t)
		if _phase_t > _marks.get("lost_t", INF) + 5.0:
			_enter("retake")


func _op_step() -> void:
	_draw_route()
	var sabotaging := sneak.plan == "sabotage"
	_set_fast(1 if _phase_t < 2.5 or sabotaging else 6)
	if sabotaging:
		_once("arrived", func():
			_marks.arrived_t = _phase_t
			_say("Idle mode · At the helipad", "It slipped round the riflemen and starts the sabotage")
			_rts_view(pad.global_position + Vector3(6.0, 0.0, 2.0), 52.0))
		if _phase_t > _marks.get("arrived_t", INF) + 5.0:
			_enter("end")
	elif _phase_t > 2.5 and sneak.leader:
		# Follow the squad across the field.
		var p := sneak.leader.global_position
		var rig := ac.camera_rig
		var want := Vector3(p.x, 0.0, p.z + 6.0)
		rig.position = rig.position.lerp(Vector3(want.x, rig.position.y, want.z), 0.06)
	if _phase_t > 240.0:
		_enter("end")


func _draw_route() -> void:
	_route_mesh.clear_surfaces()
	if sneak.route.size() < 2 or sneak.plan != "approach":
		return
	_route_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var from := sneak.leader.global_position
	for p in sneak.route:
		_route_mesh.surface_add_vertex(from + Vector3.UP * 0.4)
		_route_mesh.surface_add_vertex(p + Vector3.UP * 0.4)
		from = p
	_route_mesh.surface_end()


func _once(key: String, f: Callable) -> void:
	if not _marks.has(key):
		_marks[key] = true
		f.call()


func _finish() -> void:
	if _fast > 1:
		print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame])
	print("VIDEO END frame %d" % _frame)
	print("INFIL VIDEO done: helipad %s, op plan %s" % ["held" if pad.controlled else "lost", sneak.plan])
	get_tree().quit()


# ---------------------------------------------------------------- cameras

## Which view the video shows: "def" (the squad's own camera and the defender's HUD), "rts" (the
## attacker's camera and HUD), "chase" (a camera by the squad, no HUD).
func _shoot(s: String) -> void:
	shot = s
	dc.visible = s == "def"
	hero.set_hud_visible(s == "def")
	ac.visible = s == "rts"
	_route_mi.visible = s == "rts" and phase == "op"
	match s:
		"def":
			hero.get_camera().current = true
		"rts":
			ac.camera_rig.camera.current = true
		"chase":
			cam.current = true
	# The camo shows on the attacker's side only.
	if hero.camo_left > 0.0:
		for tr in hero.troopers:
			(tr as InfiltratorTrooper).set_camo(true, s == "rts")


func _rts_view(at: Vector3, zoom: float) -> void:
	var rig := ac.camera_rig
	rig.focus(at)
	rig.zoom = zoom
	rig.set("_target_zoom", zoom)


func _chase() -> void:
	if hero.leader == null:
		return
	var p := hero.leader.global_position
	cam.global_position = p + Vector3(-5.5, 2.4, -4.5)
	cam.look_at(p + Vector3(0.0, 1.3, 2.0))


func _set_fast(k: int) -> void:
	if k != _fast:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame - 1])
		_fast = k
		_fast_from = _frame
	if _snaps.is_empty():
		RenderingServer.render_loop_enabled = (_frame - _fast_from) % _fast == 0


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%.1f.png" % [_snap_out, at])
		print("snap %.1f (%s, %s)" % [at, phase, shot])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- overlay

func _say(title: String, sub: String) -> void:
	_caption.text = title if sub == "" else "%s\n%s" % [title, sub]
	_caption.visible = title != ""


func _key(text: String) -> void:
	_keycap.text = text
	_key_t = 1.6


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_caption = UIKit.label("", 22, Color.WHITE)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y = 64
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_caption)
	_keycap = UIKit.label("", 34, Color(1.0, 0.85, 0.3))
	_keycap.add_theme_color_override("font_outline_color", Color.BLACK)
	_keycap.add_theme_constant_override("outline_size", 8)
	_keycap.position = Vector2(40, 300)
	_keycap.visible = false
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_keycap)
