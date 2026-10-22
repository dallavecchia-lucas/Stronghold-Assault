extends Node3D
## Staged video of a Breaching Ram assault on the real map, for recording with Movie Maker:
##
##   godot --path game --resolution 1280x720 --write-movie ram_raid.avi --fixed-fps 30 \
##       res://scenes/dev/ram_raid_showcase.tscn
##
## The breach: three big horn sheep ram the south gate down with a pack of Chimps behind them.
## The raid: rams and Chimps pour in and fight the garrison inside the stronghold on their own
## (AttackerUnit raiders). A few extra defenders stand inside the bay to meet them.
## Everything in here is video-only: the interior cameras, their lights and the extra defenders
## are not part of the game. The garrison's mortar and machine guns hold fire.

## Seconds of the raid recorded after the gate falls, before the fade out.
const RAID_LENGTH := 54.0
## How long each interior shot holds before the director cuts (seconds).
const CUT_EVERY := Vector2(3.2, 4.6)
const GATE_SIDE := "south"
## Lead-in shots: [end time, name].
const BREACH_SHOTS := [[3.2, "crane"], [6.0, "track"], [INF, "gate"]]
## Interior cameras: [label, position, default look at]. Each pans to follow the action.
const INTERIOR_CAMS := [
	["CAM 01 · GATE TUNNEL", Vector3(-4.0, 2.2, 70.6), Vector3(-4.0, 1.2, 80.0)],
	["CAM 02 · RAMP JUNCTION", Vector3(4.6, 4.5, 66.4), Vector3(-3.0, 1.2, 68.0)],
	["CAM 03 · SPAWN HALL", Vector3(-6.0, 4.0, 58.0), Vector3(4.0, 0.8, 58.5)],
	["CAM 04 · STAIR SHAFT", Vector3(4.8, 9.6, 63.2), Vector3(4.8, 8.0, 70.0)],
	["CAM 05 · GUN DECK WEST", Vector3(-20.0, 10.2, 73.0), Vector3(0.0, 8.6, 71.0)],
	["CAM 06 · GUN DECK EAST", Vector3(20.0, 10.2, 73.0), Vector3(0.0, 8.6, 71.0)],
	["CAM 07 · CORE CORRIDOR", Vector3(1.0, 2.6, 34.0), Vector3(0.0, 1.0, 50.0)],
	["CAM 08 · REACTOR HALL", Vector3(0.0, 4.5, 13.0), Vector3(0.0, 2.5, 0.0)],
]
## Extra defenders inside the bay, met by the raid (snapped onto the navmesh).
const INSIDE_GUARDS := [Vector3(2.0, 2.8, 67.6), Vector3(-1.5, 1.6, 68.0), Vector3(-4.0, 0.0, 70.5),
		Vector3(0.0, 0.0, 58.0), Vector3(-4.0, 0.0, 57.0), Vector3(3.5, 0.0, 56.0),
		Vector3(1.0, 8.05, 70.6), Vector3(0.0, 0.0, 32.0), Vector3(4.0, 0.0, 9.0), Vector3(-4.0, 0.0, 9.0)]
## Work lights along the way in (video-only), and the alarm lights that start once the gate falls.
const WORK_LIGHTS := [Vector3(-4.0, 2.4, 73.0), Vector3(0.0, 4.6, 68.0), Vector3(4.5, 4.8, 66.0),
		Vector3(0.0, 4.5, 58.0), Vector3(2.0, 9.5, 64.0), Vector3(0.0, 3.0, 40.0), Vector3(0.0, 3.0, 24.0)]

var level: LevelBuilder
var commander: AttackerCommander
var cam: Camera3D
var gate: Structure
var rams: Array = []
var chimps: Array = []
var guards: Array = []
var t := -1.0
var phase := "breach"
var breach_t := 0.0
var _alarms: Array[OmniLight3D] = []
var _slowmo_done := false
var _slowmo_left := 0.0

# Director state.
var _shot := ""
var _shot_left := 0.0
var _hero: Node3D
var _fixed := -1
var _look := Vector3.ZERO
var _chase_pos := Vector3.ZERO
var _chase_side := 1.0
var _flip := false

# Overlay.
var _label: Label
var _rec: Label
var _title: Label
var _fade: ColorRect


func _ready() -> void:
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	gate = level.gates[GATE_SIDE]
	# Staged before the Gunner Squad held the south spawn hall the raid goes through: it sits
	# this one out.
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
	# A staged scene: the mortar and machine guns hold fire, the riflemen fight.
	for s in level.stations:
		if not s is DefenderSoldier:
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
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(6, 7, 130)
	cam.look_at(gate.global_position)
	_build_lights()
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	# Softened up by the guns outside: three slams finish it.
	gate.hp = gate.max_hp * 0.66
	gate.destroyed.connect(_on_gate_down, CONNECT_ONE_SHOT)
	for k in 3:
		rams.append(_spawn("breacher", Vector3(-7.0 + k * 3.0, 0, 112.0 + absf(k - 1) * 1.5)))
	for k in 6:
		chimps.append(_spawn("chimp", Vector3(-10.0 + (k % 3) * 3.0 + (k / 3) * 1.5, 0, 119.0 + (k / 3) * 3.0)))
	for p in INSIDE_GUARDS:
		_guard(p)
	for st in level.stations:
		if st is DefenderSoldier:
			st.became_unavailable.connect(func(_x): st.set("_respawn_cd", 1e9))
	_hero = rams[1]
	t = 0.0
	_cut("crane")


func _spawn(type_id: String, pos: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = 0.0  # facing the mountain
	return u


func _guard(p: Vector3) -> void:
	var s := DefenderSoldier.new()
	s.model_path = LevelBuilder.DEFENDER_MODELS[guards.size() % LevelBuilder.DEFENDER_MODELS.size()]
	s.station_name = "Guard"
	# Stood on the floor under `p`.
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else p
	# Facing the way in (the gate tunnel), so they meet the raid head on.
	var to := Vector3(-4.0, at.y, 82.0) - at
	s.transform = Transform3D(Basis.looking_at(to if to.length() > 1.0 else Vector3.BACK), at + Vector3.UP * 0.1)
	add_child(s)
	# Staged: the fallen stay down.
	s.became_unavailable.connect(func(_st): s.set("_respawn_cd", 1e9))
	guards.append(s)


func _build_lights() -> void:
	for p in WORK_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.86, 0.68)
		l.light_energy = 1.6
		l.omni_range = 11.0
		l.shadow_enabled = false
		l.position = p
		add_child(l)
		var a := OmniLight3D.new()
		a.light_color = Color(1.0, 0.12, 0.08)
		a.light_energy = 0.0
		a.omni_range = 9.0
		a.position = p + Vector3(0.6, -0.3, 0.0)
		add_child(a)
		_alarms.append(a)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	# Letterbox.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -64.0
		bar.offset_bottom = 64.0 if top else 0.0
		root.add_child(bar)
	_label = _text(root, 22, Vector2(36, 84))
	_rec = _text(root, 22, Vector2(0, 84))
	_rec.anchor_left = 1.0
	_rec.anchor_right = 1.0
	_rec.offset_left = -150.0
	_rec.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_title = _text(root, 40, Vector2(0, 0))
	_title.anchor_top = 1.0
	_title.anchor_bottom = 1.0
	_title.anchor_right = 1.0
	_title.offset_top = -170.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)


func _text(parent: Control, size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.position = pos
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- the action

func _process(delta: float) -> void:
	if t < 0.0:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	t += real
	_update_slowmo(real)
	if phase == "breach":
		_breach_step()
	else:
		_raid_step(real)
	_update_camera(real)
	_update_overlay()


func _breach_step() -> void:
	# The Chimps trot up behind the rams; the rams surge at the gate.
	if t > 1.2 and chimps[0].order.type == "idle":
		commander.submit({"type": "move", "units": _ids(chimps), "pos": Vector3(-4.0, 0, 96.0), "attack": false})
		commander.submit({"type": "move", "units": _ids(rams), "pos": Vector3(-4.0, 0, 100.0), "attack": false})
	if t > 2.6 and not rams[0].is_ramming() and rams[0].ram_cd <= 0.0:
		commander.submit({"type": "ram", "units": _ids(rams)})
		commander.submit({"type": "attack", "units": _ids(rams), "target": gate.get_path()})
	# Slow motion as the first ram reaches the door.
	if not _slowmo_done:
		for r in rams:
			if r.charge_gate and r.global_position.distance_to(r.get("_charge_pos")) < 3.5:
				_slowmo_done = true
				_slowmo_left = 1.6
				Engine.time_scale = 0.3
				break
	for k in BREACH_SHOTS.size():
		if t < BREACH_SHOTS[k][0]:
			if _shot != BREACH_SHOTS[k][1]:
				_cut(BREACH_SHOTS[k][1])
			break


func _update_slowmo(real: float) -> void:
	if _slowmo_left > 0.0:
		_slowmo_left -= real
		if _slowmo_left <= 0.0:
			Engine.time_scale = 1.0


func _on_gate_down(_g) -> void:
	phase = "raid"
	breach_t = t
	_shot_left = 1.4  # hold on the blast before going inside
	# Everyone goes in: inside, they are on their own.
	var all: Array = _alive(rams + chimps)
	commander.submit({"type": "move", "units": _ids(all), "pos": gate.get_approach_point(), "attack": false})


func _raid_step(real: float) -> void:
	var since := t - breach_t
	for a in _alarms:
		a.light_energy = 2.2 * maxf(sin(since * 5.0), 0.0)
	# Stragglers still outside the gate: send them in again.
	if int(since * 2.0) != int((since - real) * 2.0):
		var outside := _alive(rams + chimps).filter(func(u): return not u.raiding and u.is_idle())
		if not outside.is_empty():
			commander.submit({"type": "move", "units": _ids(outside), "pos": gate.get_approach_point(), "attack": false})
	_shot_left -= real
	if _shot_left <= 0.0 or (_shot != "gate" and not _alive_node(_hero)):
		_direct()
	if since > RAID_LENGTH or (since > 8.0 and _alive(rams + chimps).is_empty()):
		get_tree().quit()


## Next interior shot: the director picks someone in the thick of it and the camera that
## sees them best, alternating chase shots with the base's own cameras.
func _direct() -> void:
	_shot_left = randf_range(CUT_EVERY.x, CUT_EVERY.y)
	var since := t - breach_t
	if since < 6.0:
		# First in through the door: the tunnel camera looking out.
		_hero = _lead(_alive(rams + chimps))
		_fixed = 0
		_cut("fixed")
		_shot_left = 2.6
		return
	_flip = not _flip
	var pool: Array = _alive(rams) if _flip else _alive(chimps)
	if pool.is_empty():
		pool = _alive(rams + chimps)
	if pool.is_empty():
		return
	_hero = _busiest(pool)
	var best := _best_fixed(_hero)
	# Too tight for a chase camera: it would sit right on the hero's back.
	var tight := _chase_goal().distance_to(_hero.global_position + Vector3.UP * 1.5) < 2.0
	if best >= 0 and (randf() < 0.55 or _shot == "chase" or tight):
		_fixed = best
		_cut("fixed")
	else:
		_chase_side = -_chase_side
		_cut("chase")


func _lead(pool: Array) -> Node3D:
	var best: Node3D = null
	for u in pool:
		if best == null or u.global_position.z < best.global_position.z:
			best = u
	return best


## The unit in a fight (a target in range), deepest inside first.
func _busiest(pool: Array) -> Node3D:
	var fighting := pool.filter(func(u): return Combat.is_valid_target(u.target) and u.global_position.distance_to(u.target.global_position) < 14.0)
	var list := fighting if not fighting.is_empty() else pool
	return list[randi() % list.size()]


func _best_fixed(u: Node3D) -> int:
	var best := -1
	var best_d := 22.0
	for k in INTERIOR_CAMS.size():
		if k == _fixed and _shot == "fixed":
			continue
		var p: Vector3 = INTERIOR_CAMS[k][1]
		var d := p.distance_to(u.global_position)
		if d < best_d and d > 2.5 and _clear(p, Combat.aim_point(u)):
			best_d = d
			best = k
	return best


func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _cut(shot: String) -> void:
	_shot = shot
	match shot:
		"crane":
			cam.fov = 50.0
		"track":
			cam.fov = 55.0
		"gate":
			cam.fov = 52.0
			cam.global_position = gate.global_position + Vector3(8.5, -0.6, 6.5)
			_look = gate.global_position + Vector3(-1.0, -0.4, 4.0)
		"fixed":
			cam.fov = 62.0
			cam.global_position = INTERIOR_CAMS[_fixed][1]
			_look = Combat.aim_point(_hero) if _alive_node(_hero) else INTERIOR_CAMS[_fixed][2]
		"chase":
			cam.fov = 68.0
			_chase_pos = _chase_goal()
			cam.global_position = _chase_pos
			_look = Combat.aim_point(_hero)
	if shot == "fixed" or shot == "chase":
		cam.look_at(_look)


func _update_camera(real: float) -> void:
	var w := minf(real * 4.0, 1.0)
	match _shot:
		"crane":
			# Behind the pack, rising over it toward the mountain.
			var k := clampf(t / 3.2, 0.0, 1.0)
			var s := smoothstep(0.0, 1.0, k)
			cam.global_position = Vector3(lerpf(9.0, 4.0, s), lerpf(2.0, 6.5, s), lerpf(134.0, 127.0, s))
			cam.look_at(Vector3(-4.0, lerpf(3.0, 4.0, s), 79.0))
		"track":
			# Low alongside the middle ram as it charges.
			if _alive_node(rams[1]):
				var r: Node3D = rams[1]
				var goal := r.global_position + Vector3(4.2, 1.0, -1.5)
				cam.global_position = cam.global_position.lerp(goal, w) if t > 3.3 else goal
				cam.look_at(r.global_position + Vector3(0, 0.9, -2.0))
		"gate":
			cam.look_at(_look)
		"fixed":
			if _alive_node(_hero):
				_look = _look.lerp(Combat.aim_point(_hero), minf(real * 2.5, 1.0))
			cam.look_at(_look)
		"chase":
			if _alive_node(_hero):
				_chase_pos = _chase_pos.lerp(_chase_goal(), minf(real * 3.0, 1.0))
				_look = _look.lerp(Combat.aim_point(_hero) + Vector3.UP * 0.2, minf(real * 5.0, 1.0))
			cam.global_position = _chase_pos
			if cam.global_position.distance_to(_look) > 0.2:
				cam.look_at(_look)


## Over the hero's shoulder, pulled in wherever a wall is in the way.
func _chase_goal() -> Vector3:
	var u := _hero
	var back := u.global_basis.z
	var head: Vector3 = u.global_position + Vector3.UP * 1.5
	var want := head + back * 3.4 + u.global_basis.x * 0.9 * _chase_side + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(head, want, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = head + (hit.position - head) * 0.8
	return want


func _update_overlay() -> void:
	# Fade in from black, fade out at the end.
	var a := 1.0 - clampf(t / 0.8, 0.0, 1.0)
	if phase == "raid":
		a = maxf(a, clampf((t - breach_t - (RAID_LENGTH - 1.5)) / 1.5, 0.0, 1.0))
	_fade.color.a = a
	_label.text = ""
	_rec.text = ""
	_title.text = ""
	if phase == "breach":
		if t > 0.6 and t < 3.2:
			_title.text = "BREACHING RAMS + NIGHT OPS CHIMPS"
		elif _shot == "track":
			_title.text = "RAM!"
	elif _shot == "fixed":
		_label.text = INTERIOR_CAMS[_fixed][0]
		_rec.text = "● REC" if fmod(t, 1.0) < 0.6 else ""
	elif _shot == "chase" and _alive_node(_hero):
		_label.text = "%s · RAIDING" % _hero.stats.name.to_upper()
	if phase == "raid" and t - breach_t < 2.0:
		_title.text = "BREACH"


func _alive(list: Array) -> Array:
	return list.filter(func(u): return _alive_node(u))


func _alive_node(u) -> bool:
	return is_instance_valid(u) and u.is_alive()


func _ids(list: Array) -> Array:
	return _alive(list).map(func(u): return u.unit_id)

