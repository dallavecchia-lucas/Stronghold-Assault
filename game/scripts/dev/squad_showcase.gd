extends Node3D
## Staged video of the Gunner Squad on the real map, for recording with Movie Maker:
##
##   godot --path game --resolution 1280x720 --write-movie squad.avi --fixed-fps 30 \
##       res://scenes/dev/squad_showcase.tscn
##
## A lone Heavy Gunner shows its walk, strafe and minigun first. Then the squad, driven from the
## south spawn hall like a player would (SquadPilot): up the narrow spawn ramp and through the
## gate tunnel in file, out through the blast door (it opens for them) into a wedge, through a
## stand of birches and rocks, and into a fight with two attacking waves, one ahead and one
## on the flank, all five firing where the leader aims. `--test` runs it headless at speed and
## prints what the squad does instead; `--snap=t1,t2,.. --snap-out=prefix` saves single frames.
## Video-only: the grove in front of the gate, the work lights inside and the staged attackers;
## the garrison's other posts hold fire.

## Waypoints of the drive (world): the spawn hall, the ramp, the junction, the gate tunnel, the
## open ground and the grove.
const RAMP_FOOT := Vector3(3.2, 0.0, 58.4)
const RAMP_TOP := Vector3(4.2, 2.7, 64.6)
const JUNCTION := Vector3(4.3, 2.7, 67.9)
const TUNNEL_BEND := Vector3(-3.9, 0.0, 69.6)
const GATE_INSIDE := Vector3(-4.0, 0.0, 76.0)
const OUTSIDE := Vector3(-4.0, 0.0, 87.0)
const OPEN := Vector3(-4.5, 0.0, 95.0)
const GROVE := [Vector3(-1.5, 0.0, 104.0), Vector3(2.5, 0.0, 113.0), Vector3(-1.0, 0.0, 121.0)]
const STAND := Vector3(-2.0, 0.0, 131.0)
## The grove (video-only): birches (their crowns clear the troopers and the camera) and rocks in
## front of the south gate, at least SPACING apart.
const GROVE_RECT := Rect2(-14.0, 99.0, 26.0, 21.0)
const GROVE_TREES := 15
const GROVE_ROCKS := 6
const GROVE_SPACING := 4.6
const BIRCHES := [0, 1, 2]  # Props.TREES
## The attacking waves: [unit, x, z]. The first comes on from far ahead as the squad leaves the
## grove (it reaches rifle range about when the squad is set and firing), the second round its
## right flank once the fight is on.
const WAVE := [["rifleman", -10.0, 184.0], ["rifleman", -5.0, 182.0], ["rifleman", 0.0, 183.0], ["rifleman", 5.0, 185.0],
		["rifleman", -8.0, 190.0], ["rifleman", 3.0, 191.0], ["kangaroo", -14.0, 196.0], ["kangaroo", 10.0, 195.0],
		["rifleman", -2.0, 196.0], ["rifleman", 8.0, 197.0]]
const FLANK := [["rifleman", 46.0, 128.0], ["rifleman", 49.0, 133.0], ["rifleman", 47.0, 138.0], ["rifleman", 52.0, 126.0],
		["kangaroo", 55.0, 131.0], ["rifleman", 54.0, 140.0], ["rifleman", 58.0, 134.0], ["kangaroo", 60.0, 127.0]]
## Work lights (video-only) along the way out: spawn hall, ramp, junction, tunnel.
const WORK_LIGHTS := [Vector3(-4.0, 3.6, 58.2), Vector3(3.5, 3.6, 58.6), Vector3(4.3, 5.0, 62.5), Vector3(4.3, 5.4, 67.0),
		Vector3(0.0, 4.2, 68.4), Vector3(-4.0, 2.4, 71.0), Vector3(-4.0, 2.4, 75.5)]
## The lone trooper for the animation shots, out east of the lane, and how long they run (s).
const SOLO_FROM := Vector3(24.0, 0.0, 96.0)
const SOLO_LENGTH := 10.5
## Fixed cameras' labels.
const CAM_LABELS := {"hall": "CAM 03 · SPAWN HALL", "tunnel": "CAM 09 · GATE TUNNEL", "gate": "CAM 11 · SOUTH GATE"}

var level: LevelBuilder
var commander: AttackerCommander
var squad: GunnerSquad
var pilot: SquadPilot
var solo: HeavyGunner
var cam: Camera3D
var dc: DefenderController
var t := -1.0
var phase := "solo"
var test := false
var wave: Array = []
## The first wave's units (wave holds both).
var _front: Array = []
var _phase_t := 0.0
var _shot := ""
var _shot_t := 0.0
var _crane := Vector3.ZERO
var _look := Vector3.ZERO
var _log_cd := 0.0
var _last_pos := {}
var _stuck := {}
var _modes := {}
var _alive := 0
var _lost := 0
var _side_done := false
var _overheated := false
var _flanked := false
var _end_t := 0.0
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false

# Overlay.
var _title: Label
var _sub: Label
var _label: Label
var _rec: Label
var _fade: ColorRect
var _overlay: CanvasLayer


func _ready() -> void:
	test = "--test" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(s): return float(s))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	_build_grove()
	level.rebake_navigation()  # the grove goes into the navmesh too
	squad = level.stations.filter(func(s): return s is GunnerSquad)[0]
	# A staged scene: the guns, the mortar and the riflemen hold fire; the squad does the fighting.
	for s in level.stations:
		if s != squad:
			s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	cam.global_position = SOLO_FROM + Vector3(6, 2, -4)
	cam.look_at(SOLO_FROM + Vector3.UP)
	if not test:
		_build_lights()
		_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _build_grove() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < GROVE_TREES + GROVE_ROCKS and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(GROVE_RECT.position.x, GROVE_RECT.end.x), 0.0,
				rng.randf_range(GROVE_RECT.position.y, GROVE_RECT.end.y))
		if placed.any(func(q): return q.distance_to(p) < GROVE_SPACING):
			continue
		placed.append(p)
		if placed.size() <= GROVE_TREES:
			_birch(p, rng)
		else:
			level._rock(p, rng)


## A tree like LevelBuilder's, always a birch: tall and bare-trunked below the crown.
func _birch(p: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(10.0, 12.5)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.position = p
	var cs := CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.4
	trunk.height = h * 0.5
	cs.shape = trunk
	cs.position.y = h * 0.25
	body.add_child(cs)
	var model := Props.instance(Props.TREES[BIRCHES[rng.randi() % BIRCHES.size()]], h)
	model.rotation.y = rng.randf() * TAU
	body.add_child(model)
	level.nav_region.add_child(body)


func _build_lights() -> void:
	for p in WORK_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.86, 0.68)
		l.light_energy = 1.8
		l.omni_range = 9.0
		l.position = p
		add_child(l)


func _start() -> void:
	# The navmesh's first iteration lands a few frames after the bake.
	for k in 10:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	pilot = SquadPilot.new([
		{"hold": 1.6, "look": RAMP_FOOT + Vector3(2.0, 1.6, 0.0)},
		{"to": RAMP_FOOT},
		{"to": RAMP_TOP},
		{"to": JUNCTION},
		{"to": TUNNEL_BEND},
		{"to": GATE_INSIDE},
		{"to": OUTSIDE},
		{"to": OPEN, "hold": 1.2},
		{"to": GROVE[0]},
		{"to": GROVE[1]},
		{"to": GROVE[2]},
		{"to": STAND, "hold": 0.5},
		{"fire": true, "hold": 7.0, "look": STAND + Vector3(0, 1.5, 40)},
		{"strafe": Vector2(0.8, 0.0), "fire": true, "hold": 2.5, "look": STAND + Vector3(25, 1.5, 25)},
		{"fire": true, "aim": true, "hold": 3.0, "clear": 8.0, "look": STAND + Vector3(30, 1.5, 20)},
		{"hold": 4.0, "look": STAND + Vector3(20, 1.8, 30)},
	])
	squad.pilot = pilot
	if test:
		squad.possess()
		phase = "squad"
	else:
		_spawn_solo()
		_cut("solo_side")
	t = 0.0


func _spawn_solo() -> void:
	solo = HeavyGunner.new()
	add_child(solo)
	solo.global_position = SOLO_FROM
	solo.rotation.y = PI  # facing south, away from the mountain
	solo.aim_point = SOLO_FROM + Vector3(0, 1.4, 40)
	solo.following = true
	solo.goal = SOLO_FROM + Vector3(0, 0, 9)


# ---------------------------------------------------------------- the action

func _physics_process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	_phase_t += delta
	match phase:
		"solo":
			_solo_step()
		"squad":
			_squad_step()
	if test:
		_diagnose(delta)


func _solo_step() -> void:
	# Walk ahead, strafe left while aiming ahead, then fire.
	if _phase_t > 4.2 and _phase_t < 7.6:
		solo.goal = SOLO_FROM + Vector3(-5.5, 0, 9)
		solo.aim_point = SOLO_FROM + Vector3(0, 1.4, 50)
	if _phase_t > 7.6:
		solo.trigger = true
		solo.aim_point = SOLO_FROM + Vector3(-3, 1.0, 45)
	if _phase_t > SOLO_LENGTH:
		solo.queue_free()
		solo = null
		phase = "squad"
		_phase_t = 0.0
		# The player takes over the squad: the defender HUD, the squad's camera and its pilot.
		dc = DefenderController.new()
		dc.level = level
		level.stations = [squad]
		add_child(dc)
		_cut("tps")


func _squad_step() -> void:
	# The first wave comes on as the squad clears the grove, the second once the fight is on.
	if wave.is_empty() and pilot.leg >= 11:
		_front = _attack(WAVE, STAND + Vector3(0, 0, 18))
	if not _flanked and (pilot.leg >= 13 or (pilot.leg == 12 and pilot.leg_t > 3.0)):
		_flanked = true
		_attack(FLANK, STAND + Vector3(16, 0, 4))
	if test:
		if pilot.done or t > 150.0:
			_report()
			get_tree().quit()
		return
	if pilot.done:
		_end_t += get_physics_process_delta_time()
		if _end_t > 2.0:
			get_tree().quit()


# ---------------------------------------------------------------- the director

func _process(delta: float) -> void:
	if t < 0.0 or test:
		return
	_shot_t += delta
	if phase == "solo":
		_solo_shots()
	else:
		_squad_shots()
	_update_camera(delta)
	_update_overlay()
	if not _snaps.is_empty():
		_snap()


## --snap=t1,t2,..: draws only the frames at those times and saves them (--snap-out=prefix), for
## checking shots without recording the whole video.
func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		print("SNAP %.1f %s" % [at, _shot])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


func _solo_shots() -> void:
	if _phase_t > 4.2 and _shot == "solo_side":
		_cut("solo_front")
	elif _phase_t > 7.6 and _shot == "solo_front":
		_cut("solo_gun")


## The shots, in order: the player's own view (tps) in the spawn hall; the hall camera as the
## squad files into the spawn ramp; the player's view again down the tunnel ramp; the tunnel
## camera by the blast door as the file comes down the tunnel; the gate camera outside as the
## door opens and the squad comes out and fans into a wedge; a chase camera behind it into the grove; the player's view through the
## trees and into the fight; a low camera beside the firing line; the player's view as the flank
## wave comes in; an arc round the squad at the end.
func _squad_shots() -> void:
	var leg := pilot.leg
	var l := squad.leader.global_position
	match _shot:
		"tps":
			if leg == 1 and l.x > -0.5:
				_cut("hall")
			elif (leg == 5 or leg == 6) and l.z > 71.0 and l.z < 76.0:
				_cut("tunnel")
			elif leg >= 12 and _shot_t > 5.0 and not _side_done:
				_side_done = true
				_cut("side")
			elif leg >= 15:
				_cut("orbit")
		"hall":
			if leg >= 4:
				_cut("tps")
		"tunnel":
			if l.z > 75.3:
				_cut("gate")
		"gate":
			if leg >= 8 and _shot_t > 2.5:
				_cut("chase")
		"chase":
			if leg >= 10:
				_cut("tps")
		"side":
			if _shot_t > 6.0:
				_cut("tps")


func _cut(shot: String) -> void:
	_shot = shot
	_shot_t = 0.0
	var tps := shot == "tps"
	if squad.possessed:
		squad.get_camera().current = tps
	if not tps:
		cam.current = true
	squad.set_hud_visible(tps)
	# Seen from outside the squad nobody steps in front of the camera's nose: no dithering.
	HeavyGunner.set_close_fade(tps)
	if dc:
		dc.visible = tps
	match shot:
		"hall":
			cam.fov = 50.0
			cam.global_position = Vector3(-4.5, 3.0, 57.3)
			_look = _centroid()
		"tunnel":
			cam.fov = 60.0
			cam.global_position = Vector3(-5.1, 2.35, 77.6)
			_look = _centroid()
		"gate":
			cam.fov = 52.0
			cam.global_position = Vector3(-12.5, 2.6, 92.5)
			_look = level.gates.south.global_position
		"chase":
			cam.fov = 55.0
			_crane = _chase_goal()
			cam.global_position = _crane
			_look = _centroid() + Vector3.UP
		"side":
			cam.fov = 46.0
			cam.global_position = _centroid() + Vector3(-13.0, 1.3, 6.5)
			_look = _centroid() + Vector3(1.0, 1.1, 2.0)
		"orbit":
			cam.fov = 50.0
			_look = _centroid() + Vector3.UP
		"solo_side", "solo_front", "solo_gun":
			cam.fov = 40.0 if shot == "solo_gun" else 46.0
	if not tps:
		cam.look_at(_look)


## Behind the squad (the way it faces) and above it, below the birch crowns; pulled in where the
## mountain is in the way (troopers still coming out of the gate).
func _chase_goal() -> Vector3:
	var from := _centroid() + Vector3.UP * 1.5
	var want := _centroid() + Basis(Vector3.UP, squad.heading) * Vector3(1.5, 3.0, 10.0)
	var ball := SphereShape3D.new()
	ball.radius = 0.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = want - from
	q.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES
	var frac := get_world_3d().direct_space_state.cast_motion(q)
	return from + (want - from) * (frac[0] if frac.size() > 0 else 1.0)


func _update_camera(delta: float) -> void:
	var w := minf(delta * 3.0, 1.0)
	match _shot:
		"hall", "tunnel", "gate":
			_look = _look.lerp(_centroid() + Vector3.UP * 0.6, w)
			cam.look_at(_look)
		"chase":
			_crane = _crane.lerp(_chase_goal(), minf(delta * 1.2, 1.0))
			cam.global_position = _crane
			_look = _look.lerp(_centroid() + Vector3.UP, w)
			cam.look_at(_look)
		"side":
			_look = _look.lerp(_centroid() + Vector3(1.0, 1.1, 2.0), w * 0.5)
			cam.look_at(_look)
		"orbit":
			# An arc over the open ground south of the squad, clear of the grove.
			var c := _centroid()
			var a := -0.9 + _shot_t * 0.32
			cam.global_position = c + Vector3(sin(a) * 14.0, 3.6, cos(a) * 14.0)
			_look = _look.lerp(c + Vector3.UP * 1.0, w)
			cam.look_at(_look)
		"solo_side":
			if is_instance_valid(solo):
				var p := solo.global_position
				cam.global_position = cam.global_position.lerp(p + Vector3(-4.2, 1.3, 1.6), w)
				cam.look_at(p + Vector3(0, 1.2, 0.6))
		"solo_front":
			if is_instance_valid(solo):
				var p := solo.global_position
				cam.global_position = cam.global_position.lerp(p + Vector3(2.6, 1.5, 5.0), w)
				cam.look_at(p + Vector3(0, 1.1, 0))
		"solo_gun":
			if is_instance_valid(solo):
				var p := solo.global_position
				cam.global_position = cam.global_position.lerp(p + Vector3(-2.4, 1.2, 2.2), w)
				cam.look_at(p + Vector3(-0.4, 1.0, 1.2))


## Spawns `list` ([unit, x, z]) and sends it at `pos`, fighting on the way.
## Spawns a wave and sends it at `pos`; returns its units.
func _attack(list: Array, pos: Vector3) -> Array:
	var ids := []
	var units := []
	for w in list:
		var id := commander.submit({"type": "spawn", "unit": w[0], "spawn": 0})
		var u: AttackerUnit = commander.units[id]
		u.global_position = Vector3(w[1], 0.2, w[2])
		u.look_at(Vector3(pos.x, 0.2, pos.z))
		units.append(u)
		ids.append(id)
	wave.append_array(units)
	commander.submit({"type": "move", "units": ids, "pos": pos, "attack": true})
	return units


## Middle of the squad (feet).
func _centroid() -> Vector3:
	var c := Vector3.ZERO
	for tr in squad.troopers:
		c += tr.global_position
	return c / maxf(squad.troopers.size(), 1.0) if not squad.troopers.is_empty() else squad.home.origin


# ---------------------------------------------------------------- test mode

func _diagnose(delta: float) -> void:
	if phase != "squad" or squad.leader == null:
		return
	var mode: String = SquadFormation.MODE_NAMES[squad.formation.mode]
	_modes[mode] = _modes.get(mode, 0.0) + delta
	_lost += maxi(_alive - squad.troopers.size(), 0)
	_alive = squad.troopers.size()
	_log_cd -= delta
	if _log_cd > 0.0:
		return
	_log_cd = 1.0
	var parts := []
	for tr in squad.troopers:
		if tr == squad.leader:
			continue
		var gap: float = Vector2(tr.goal.x - tr.global_position.x, tr.goal.z - tr.global_position.z).length()
		var moved: float = tr.global_position.distance_to(_last_pos.get(tr, tr.global_position))
		_last_pos[tr] = tr.global_position
		_stuck[tr] = _stuck.get(tr, 0.0) + 1.0 if gap > 1.5 and moved < 0.15 else 0.0
		parts.append("%.1f%s" % [gap, "!" if _stuck[tr] >= 2.0 else ""])
		if (_stuck[tr] >= 2.0 and int(_stuck[tr]) % 3 == 2) or (gap > 3.0 and t > 9.5 and t < 14.0):
			var ag: NavigationAgent3D = tr.get("_agent")
			print("   follower %s at %s goal %s next %s fin=%s wall=%s n=%s v=%s want=%s floor=%s" % [tr.name,
					tr.global_position.snapped(Vector3.ONE * 0.1), tr.goal.snapped(Vector3.ONE * 0.1),
					ag.get_next_path_position().snapped(Vector3.ONE * 0.1), ag.is_navigation_finished(), tr.is_on_wall(),
					tr.get_wall_normal().snapped(Vector3.ONE * 0.01), tr.velocity.snapped(Vector3.ONE * 0.01),
					ag.velocity.snapped(Vector3.ONE * 0.01), tr.is_on_floor()])
	var l := squad.leader.global_position
	var foes := wave.filter(func(u): return is_instance_valid(u) and u.is_alive()).size()
	print("t=%5.1f leg=%2d %-8s leader=(%.1f, %.1f, %.1f) v=%.2f hp=%d/%d heat=%.2f%s gaps=[%s] alive=%d foes=%d gate=%.2f" % [
			t, pilot.leg, mode, l.x, l.y, l.z, squad.leader.velocity.length(), squad.leader.hp, squad.hp,
			squad.leader.heat, "!" if squad.leader.overheated() else "", ", ".join(parts), squad.troopers.size(), foes,
			level.gates.south.opened])
	if squad.leader.velocity.length() < 0.1 and pilot.current().has("to"):
		var ld := squad.leader
		print("   stuck? move=%s wall=%s n=%s floor=%s ceil=%s path=%s i=%d" % [squad.input.move, ld.is_on_wall(),
				ld.get_wall_normal().snapped(Vector3.ONE * 0.01), ld.is_on_floor(), ld.is_on_ceiling(),
				Array(pilot.get("_path")).map(func(p): return p.snapped(Vector3.ONE * 0.1)), pilot.get("_path_i")])


func _report() -> void:
	var kills := wave.filter(func(u): return not is_instance_valid(u) or not u.is_alive()).size()
	print("SHOWCASE done t=%.1f modes=%s alive=%d lost=%d wave_killed=%d/%d" % [t, _modes, squad.troopers.size(), _lost,
			kills, wave.size()])


# ---------------------------------------------------------------- overlay

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 10
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)
	_title = _text(root, 34)
	_title.anchor_top = 0.0
	_title.anchor_right = 1.0
	_title.offset_top = 28.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _text(root, 20)
	_sub.anchor_right = 1.0
	_sub.offset_top = 74.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label = _text(root, 20)
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 28.0
	_label.offset_top = -52.0
	_rec = _text(root, 20)
	_rec.anchor_left = 1.0
	_rec.anchor_right = 1.0
	_rec.anchor_top = 1.0
	_rec.anchor_bottom = 1.0
	_rec.offset_left = -120.0
	_rec.offset_top = -52.0
	_rec.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)


func _update_overlay() -> void:
	var a := 1.0 - clampf(t / 0.8, 0.0, 1.0)
	if pilot.done:
		a = maxf(a, clampf(_end_t / 1.6, 0.0, 1.0))
	_fade.color.a = a
	var title := ""
	var sub := ""
	if phase == "solo":
		title = "HEAVY GUNNER"
		sub = ["walk cycle · eight directions blended", "strafing: legs step sideways, the gun stays on aim",
				"minigun: the barrels spin up, then it fires"][0 if _phase_t < 4.2 else (1 if _phase_t < 7.6 else 2)]
	else:
		var leg := pilot.leg
		if leg <= 1:
			title = "GUNNER SQUAD"
			sub = "you drive the trooper in the middle · the other four follow your lead"
		elif _shot == "hall" or _shot == "tunnel":
			sub = "tight passages: the wedge squeezes, then files in behind you"
		elif leg <= 6:
			sub = "blast doors open for the squad"
		elif leg <= 8 and (_shot == "gate" or _shot == "tps"):
			sub = "out in the open they spread back into a wedge"
		elif leg <= 11:
			sub = "around trees and rocks: the wedge bends to fit, then re-forms"
		elif leg <= 14 and _front.any(func(u): return is_instance_valid(u) and u.is_alive()):
			sub = "all five aim and fire wherever you aim"
		elif leg <= 14 and not _overheated:
			_overheated = squad.leader != null and squad.leader.overheated()
			sub = "swing your aim and the whole squad swings with you"
		elif leg <= 14:
			sub = "hold the trigger too long and the miniguns overheat"
		else:
			title = "GUNNER SQUAD"
			sub = "press G to take command"
	_title.text = title
	_sub.text = sub
	_label.text = CAM_LABELS.get(_shot, "")
	_rec.text = "● REC" if CAM_LABELS.has(_shot) and fmod(t, 1.0) < 0.6 else ""


func _text(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
