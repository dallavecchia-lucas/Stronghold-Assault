extends Node3D
## Staged run of the Mule Artillery on the real map, worked the way a player works it in the RTS view (this
## node pressing the keys and clicking for the player): a mule out in the south field walks up the lane, super
## slow; T sets its gun up (7 s, and an order to move meanwhile changes nothing); G and a click on the gate
## machine gun on the south gun deck, nearly 100 m off: the turret lays the barrel, the shell goes up out of
## the muzzle and comes down on the gun. G again does nothing until the gun has reloaded (30 s, cut short
## here); then the mortar on the roof; then a spot behind it, out in the field: the turret swings round while
## the team stands. Ordered to move armed, it stays put. T disarms it (7 s), and the order to move given
## meanwhile it carries out once its gun is packed.
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/mule_showcase.tscn -- --test
##   godot --path game --fixed-fps 30 res://scenes/dev/mule_showcase.tscn   # to watch it
##
## --test prints what the mule does and checks it at the end (MULE SHOWCASE PASS / FAIL). The garrison's posts
## hold fire, and their machines don't get repaired.

## Where the mule starts (facing the mountain, north), where it walks to, and where it is sent at the end.
const START := Vector3(6.0, 0.0, 178.0)
const WALK_TO := Vector3(6.0, 0.0, 164.0)
const FINISH := Vector3(-14.0, 0.0, 150.0)
## Where it is ordered to go while its gun is up (nowhere: it stays), and the spot in the field behind it
## that it shells last (the turret swings round to it).
const ASTRAY := Vector3(30.0, 0.0, 150.0)
const BEHIND := Vector3(36.0, 0.0, 196.0)
## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [1.0, "walk"], [13.0, "setup"], [23.0, "fire_mg"], [34.0, "reload"],
		[38.0, "fire_roof"], [49.0, "traverse"], [61.0, "armed_move"], [66.0, "disarm"], [80.0, "end"]]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var mule: AttackerUnit
var mg: Node3D
var mortar: Node3D
var t := -1.0
var phase := ""
var test := false
var _phase_t := 0.0
var _steps := {}
var _hp_before := {}
var _checks: Array[String] = []
var _failed := false
## What the mule did: [time, what].
var _gun_events: Array = []
var _shots: Array = []
var _last_pos := Vector3.ZERO
var _top_speed := 0.0
var _clips := {}
var _mark := Vector3.ZERO
var _yaw_mark := 0.0
var _caption: Label
var _status: Label


func _ready() -> void:
	test = "--test" in OS.get_cmdline_user_args()
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# A staged scene: the garrison holds its fire.
	for s in level.stations:
		s.process_mode = Node.PROCESS_MODE_DISABLED
		match String(s.name):
			"MG_south": mg = s
			"Artillery": mortar = s
	var units_root := Node3D.new()
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.spawn_points = level.spawn_points
	commander.supply = 100000.0
	commander.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(commander)
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	var rig := controller.camera_rig
	rig.edge_scroll = false
	rig.rotation.y = 0.0  # looking north, at the south face
	rig.pitch = deg_to_rad(-48.0)
	rig._target_zoom = 40.0
	rig.zoom = 40.0
	rig.focus(START)
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	var id := commander.submit({"type": "spawn", "unit": "mule", "spawn": 0})
	mule = commander.units[id]
	mule.global_position = START + Vector3.UP * 0.2
	mule.rotation.y = 0.0  # faces the mountain (north)
	mule.gun_set.connect(func(armed): _gun_events.append([t, "armed" if armed else "packed"]))
	mule.shelled.connect(func(shell, spot): _shots.append([t, shell, spot, shell.global_position]))
	_last_pos = mule.global_position
	for n in [mg, mortar]:
		print("MULE %s at %s, %.0f m from the mule" % [n.name, n.global_position, _flat(n.global_position, START)])
	t = 0.0


func _physics_process(delta: float) -> void:
	if t < 0.0 or mule == null or not is_instance_valid(mule):
		return
	var step := _flat(mule.global_position, _last_pos)
	_last_pos = mule.global_position
	if phase == "walk" and _phase_t > 2.0:
		_top_speed = maxf(_top_speed, step / delta)


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	var k := 0
	while k < SCRIPT.size() - 1 and t >= SCRIPT[k + 1][0]:
		k += 1
	if SCRIPT[k][1] != phase:
		phase = SCRIPT[k][1]
		_phase_t = 0.0
		_steps.clear()
		if phase == "end":
			_finish()
			return
	_phase_t += delta
	var anim: AnimationPlayer = mule._anim
	if anim and anim.current_animation != "":
		_clips[phase + ":" + anim.current_animation] = true
	match phase:
		"intro":
			_say("Mule Artillery", "Six donkeys towing a siege gun: super slow, it sets its gun up to fire")
		"walk":
			_walk()
		"setup":
			_setup()
		"fire_mg":
			_fire_at(Combat.aim_point(mg) - Vector3.UP * 1.2, mg, "G, click the gate machine gun on the deck, %.0f m off" % _flat(mg.global_position, mule.global_position))
		"reload":
			_reload()
		"fire_roof":
			_fire_at(mortar.global_position, mortar, "Reloaded (cut short here): G, click the mortar on the roof")
		"traverse":
			_traverse()
		"armed_move":
			_armed_move()
		"disarm":
			_disarm()
	_update_status()


func _walk() -> void:
	if _once("go"):
		_say("Walking", "Selected and sent up the lane: the donkeys pull, at %.1f m/s" % mule.stats.speed)
		controller._set_selection([mule])
		commander.submit({"type": "move", "units": [mule.unit_id], "pos": WALK_TO, "attack": false})
		_mark = mule.global_position
	controller.camera_rig.focus(mule.global_position)
	if _phase_at(11.5, "check"):
		var went := _flat(mule.global_position, _mark)
		print("MULE walk: %.1f m in %.1f s, top speed %.2f m/s" % [went, _phase_t, _top_speed])
		_check(went > 6.0, "walk: it walks (%.1f m in 11.5 s)" % went)
		_check(_top_speed <= mule.stats.speed * 1.1, "walk: super slow, no faster than %.1f m/s (%.2f)" % [mule.stats.speed, _top_speed])
		_check(_clips.has("walk:Walk"), "walk: the Walk clip plays")


func _setup() -> void:
	if _once("key"):
		_say("T: set the gun up", "%d s, and it can't move meanwhile" % mule.stats.setup_time)
		_mark = mule.global_position
		_key(KEY_T)
		_check(mule.setting_up(), "setup: T sets the gun up")
	if _phase_at(1.5, "order"):
		commander.submit({"type": "move", "units": [mule.unit_id], "pos": ASTRAY, "attack": false})
		print("MULE setup: ordered to move while setting up")
	if _phase_at(4.0, "still"):
		_check(_flat(mule.global_position, _mark) < 0.05, "setup: an order to move changes nothing (%.2f m)" % _flat(mule.global_position, _mark))
		_check(_clips.has("setup:Setup"), "setup: the Setup clip plays")
	if _phase_at(9.5, "armed"):
		var armed := _gun_events.filter(func(e): return e[1] == "armed")
		var took: float = armed[0][0] - SCRIPT[2][0] if not armed.is_empty() else -1.0
		print("MULE setup: armed after %.2f s" % took)
		_check(mule.is_armed(), "setup: armed")
		_check(absf(took - mule.stats.setup_time) < 0.15, "setup: took %.2f s (%d)" % [took, mule.stats.setup_time])
		_check(_flat(mule.global_position, _mark) < 0.05, "setup: it stayed where it was")
		_check(_clips.has("setup:Armed"), "setup: then the Armed loop")
		var high := mule.muzzle_position().y - mule.global_position.y
		_check(high > 4.0, "setup: the barrel is up (muzzle %.1f m over the ground)" % high)


## G, a click on `target` (the cursor at `aim` on screen), and the shell coming down on it.
func _fire_at(aim: Vector3, target: Node3D, caption: String) -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_say(caption, "")
		mule.bombard_cd = 0.0  # the reload cut short
		controller._set_selection([mule])
		rig.focus(Vector3(aim.x, 0.0, aim.z + 6.0))
	if _phase_at(2.0, "key"):
		_key(AttackerController.BOMBARD_KEY)
		_check(controller._aiming == "bombard", "%s: G aims the armed gun" % phase)
	if _phase_at(2.6, "click"):
		_hp_before[target] = target.hp
		var shots := _shots.size()
		_click(controller.camera_rig.camera.unproject_position(aim))
		_check(mule.is_bombarding(), "%s: the click lays the gun" % phase)
		_steps["shots"] = shots
	if _phase_at(10.0, "result"):
		var fired := _shots.size() > int(_steps["shots"])
		_check(fired, "%s: it fired" % phase)
		if fired:
			var shot: Array = _shots[-1]
			var from: Vector3 = shot[3]
			print("MULE %s: shell from %s (%.1f m up) at %.1f s, onto %s" % [phase, from, from.y - mule.global_position.y, shot[0], shot[2]])
			_check(from.y - mule.global_position.y > 4.0, "%s: the shell leaves the raised muzzle" % phase)
			_check(_flat(shot[2], aim) < mule.stats.bombard_splash, "%s: aimed at the target (%.1f m off)" % [phase, _flat(shot[2], aim)])
		print("MULE %s: %s %.0f -> %.0f HP" % [phase, target.name, _hp_before[target], target.hp])
		_check(target.hp < _hp_before[target] or not target.is_alive(), "%s: %s hit (%.0f -> %.0f)" % [phase, target.name, _hp_before[target], target.hp])
		_check(mule.bombard_cd > mule.stats.bombard_cooldown - 10.0, "%s: reloading, %.0f s to go" % [phase, mule.bombard_cd])


func _reload() -> void:
	if _once("key"):
		_say("G again: nothing", "One shell every %d s" % mule.stats.bombard_cooldown)
		_steps["shots"] = _shots.size()
		controller._set_aiming("")
		_key(AttackerController.BOMBARD_KEY)
		_check(controller._aiming == "", "reload: G does nothing while the gun reloads (%.0f s)" % mule.bombard_cd)
		_check(not mule.bombard_ready(), "reload: not ready")
	if _phase_at(3.5, "none"):
		_check(_shots.size() == int(_steps["shots"]), "reload: no shell fired")


## A spot in the field behind it, to its right: the turret swings round to it, the team stays as it stands.
func _traverse() -> void:
	if _once("start"):
		_say("A spot behind it", "The turret swings round onto it; the donkeys stay where they stand")
		mule.bombard_cd = 0.0
		_yaw_mark = mule.rotation.y
		_steps["shots"] = _shots.size()
		controller.camera_rig.focus(mule.global_position)
		commander.submit({"type": "bombard", "units": [mule.unit_id], "pos": BEHIND})
	if _phase_at(11.0, "result"):
		var fired := _shots.size() > int(_steps["shots"])
		_check(fired, "traverse: it fired behind itself")
		var gun: MuleGun = mule._gun
		# From the turret's pivot, in the unit's frame; the model (and so the turret's yaw) faces the unit's -Z.
		var to := mule.global_basis.inverse() * (BEHIND - gun.turret_position())
		var want := atan2(-to.x, -to.z)
		print("MULE traverse: turret yaw %.0f deg (the spot %.0f deg off its front)" % [rad_to_deg(gun.yaw()), rad_to_deg(want)])
		_check(absf(angle_difference(gun.yaw(), want)) < deg_to_rad(8.0), "traverse: the turret turned round to it (%.0f deg)" % rad_to_deg(gun.yaw()))
		_check(absf(angle_difference(mule.rotation.y, _yaw_mark)) < 0.01, "traverse: the team didn't turn")


func _armed_move() -> void:
	if _once("order"):
		_say("Ordered to move, armed", "It can't: it stays put")
		_mark = mule.global_position
		commander.submit({"type": "move", "units": [mule.unit_id], "pos": ASTRAY, "attack": true})
	if _phase_at(4.0, "still"):
		_check(_flat(mule.global_position, _mark) < 0.05, "armed: an order to move changes nothing (%.2f m)" % _flat(mule.global_position, _mark))
		_check(mule.is_armed(), "armed: still armed")


func _disarm() -> void:
	if _once("key"):
		_say("T: disarm", "%d s, then it can move: the order given meanwhile it carries out" % mule.stats.setup_time)
		_mark = mule.global_position
		controller._set_selection([mule])
		_key(KEY_T)
		_check(mule.packing_up(), "disarm: T disarms")
	if _phase_at(1.0, "order"):
		commander.submit({"type": "move", "units": [mule.unit_id], "pos": FINISH, "attack": false})
		_check(not mule.bombard_ready(), "disarm: it can't fire disarming")
	if _phase_at(4.0, "still"):
		_check(_flat(mule.global_position, _mark) < 0.05, "disarm: it doesn't move while disarming")
	if _phase_at(7.6, "packed"):
		var packed := _gun_events.filter(func(e): return e[1] == "packed")
		var took: float = packed[0][0] - SCRIPT[8][0] if not packed.is_empty() else -1.0
		print("MULE disarm: packed after %.2f s" % took)
		_check(mule.is_packed(), "disarm: packed")
		_check(absf(took - mule.stats.setup_time) < 0.15, "disarm: took %.2f s (%d)" % [took, mule.stats.setup_time])
		_check(absf(mule._gun.yaw()) < deg_to_rad(2.0), "disarm: the turret is back to the front")
	if _phase_at(13.5, "gone"):
		var closer := _flat(_mark, FINISH) - _flat(mule.global_position, FINISH)
		print("MULE disarm: %.1f m closer to where it was sent" % closer)
		_check(closer > 2.0, "disarm: then it goes where it was sent while disarming (%.1f m)" % closer)
		_check(_clips.has("disarm:Setup") and _clips.has("disarm:Walk"), "disarm: the Setup clip backward, then the Walk")


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	for c in _checks:
		print("MULE CHECK ", c)
	print("MULE SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit()


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _click(at: Vector2) -> void:
	get_viewport().warp_mouse(at)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		controller._unhandled_input(ev)


# ---------------------------------------------------------------- overlay

func _say(title: String, sub: String) -> void:
	_caption.text = title if sub == "" else "%s\n%s" % [title, sub]
	_caption.visible = title != ""


func _update_status() -> void:
	var gun := "packed"
	if mule.is_armed():
		gun = "armed"
	elif mule.setting_up():
		gun = "setting up %.1f s" % mule.setup_left()
	elif mule.packing_up():
		gun = "disarming %.1f s" % mule.setup_left()
	_status.text = "Gun %s\nReload %.0f s\nGate gun %d / %d\nMortar %d / %d" % [gun, mule.bombard_cd,
			int(mg.hp), int(mg.max_hp), int(mortar.hp), int(mortar.max_hp)]


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
	_status = UIKit.label("", 15, Color(1.0, 0.75, 0.65))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 64)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
