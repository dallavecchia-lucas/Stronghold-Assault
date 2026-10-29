extends Node3D
## Staged run of the Wolf Medic on the real map, in the south field, the way the attacking player uses it
## (the RTS view, this node working the mouse and keys):
##
##   intro   a dog stands (its idle)
##   heal    a dog (healing, its mode as it comes) is sent up to four hurt units: it takes the first two it
##           comes to, healing them on the move, beams and crosses over them. A badly hurt chimp runs up
##           right next to it: it sticks to the two it took. The kangaroo is full: it takes the chimp. The
##           ram it heals walks off out of its reach: it lets it go and takes the next. A second dog
##           comes up: it takes the other two (no unit is healed by two)
##   hidden  a minefield the AA Squads laid across the lane: the defender sees it, the attacking player
##           doesn't (the mines aren't drawn on their side), and a rifleman walking across it is blown up
##   sweep   four dogs are box-selected, T (minesweeping), RMB beyond the field: on their way they sniff the
##           mines out and dig them out one by one, the field's outer rim first and working inwards, never across
##           a live mine, and walk on once it is clear; the mine being dug out shows to the player (with a ring
##           filling round it)
##   through riflemen walk across the cleared field
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/dog_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie dog.avi \
##       --fixed-fps 30 res://scenes/dev/dog_showcase.tscn -- --video > dog.log
##   python3 tools/video/cut_showcase.py dog.avi dog.log media/dog_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times.
## --test prints what the dogs do and checks it at the end (DOG SHOWCASE PASS / FAIL).
## --video cuts in the cameras (SHOTS: round the dog standing, low across the minefield on the defender's
## side, close by the first dog digging); the RTS view for the rest. The sweep plays 4x faster once the
## first mines are out (printing the frames for tools/video/cut_showcase.py, drawing only the frames it
## keeps). Outside --test the hidden mines are marked for the viewer (red marks: the player never
## sees them) and a counter shows how many are left.
## The garrison's posts and the AA turrets hold fire.

## The run: [phase, seconds] (-1: the sweep, until the field is clear and SWEEP_TAIL more, at most SWEEP_MAX).
const PHASES := [["intro", 3.0], ["heal", 27.0], ["hidden", 13.0], ["sweep", -1.0], ["through", 11.0], ["outro", 2.0]]
const SWEEP_TAIL := 3.0
const SWEEP_MAX := 170.0
## The healing: the spot the dog is sent to, where it comes from, the hurt units round the spot [type, offset,
## hp] (the first two on its way in; the ram is the one that walks off), the chimp that runs up next to it,
## the second dog's way in and the unit only it reaches.
const HEAL_AT := Vector3(2.0, 0.0, 172.0)
const DOG_FROM := Vector3(0.0, 0.0, 16.0)
const DOG_STOP := Vector3(0.0, 0.0, 1.0)
const HURT := [["breacher", Vector3(2.4, 0.0, 4.0), 150.0], ["kangaroo", Vector3(-2.2, 0.0, 3.5), 24.0],
		["hippo", Vector3(5.0, 0.0, -4.0), 880.0], ["rhino", Vector3(-5.5, 0.0, -4.5), 1400.0]]
const CHIMP_FROM := Vector3(-15.0, 0.0, -2.0)
const CHIMP_TO := Vector3(0.3, 0.0, 0.8)
const CHIMP_HP := 15.0
const WALK_OFF := Vector3(13.0, 0.0, 16.0)
const DOG2_FROM := Vector3(-16.0, 0.0, 12.0)
const DOG2_STOP := Vector3(1.0, 0.0, -5.0)
const LATE := ["bison_gun", Vector3(7.5, 0.0, -9.0), 450.0]
## The minefield: mines no closer than MINE_SPACING over an ellipse round FIELD_AT (half its width and depth),
## up to MINES of them; the rifleman who walks into it; the pack of dogs and where they are sent.
const FIELD_AT := Vector3(0.0, 0.0, 124.0)
const FIELD_HALF := Vector2(12.0, 7.5)
const MINE_SPACING := 3.3
const MINES := 26
const WALKER := [Vector3(-3.0, 0.0, 142.0), Vector3(-3.0, 0.0, 104.0)]
const PACK_AT := [Vector3(-6.0, 0.0, 153.0), Vector3(-2.0, 0.0, 152.0), Vector3(2.0, 0.0, 152.5), Vector3(6.0, 0.0, 153.5)]
const PACK_TO := Vector3(0.0, 0.0, 109.0)
const THROUGH_X := [-9.0, -5.5, -2.0, 1.5, 5.0, 8.5]
## Video: the marks on the hidden mines (m across, half).
const GHOST_R := 0.55
## A dog's body is in a mine's trigger this close to it (m, flat): GroundMine.TRIGGER_RADIUS and its radius.
const TRIGGER_REACH := 2.05
const HEAL_ZOOM := 22.0
const FIELD_ZOOM := 36.0
const DIG_ZOOM := 15.0
## Video: cameras other than the RTS view, as [phase, from, to (phase seconds), shot].
const SHOTS := [["intro", 0.0, 3.0, "dog"], ["hidden", 3.0, 7.0, "field_low"], ["sweep", 14.5, 19.0, "dig"]]
## Played faster: [phase, from, to, every k-th frame kept].
const FAST := [["sweep", 26.0, 999.0, 4]]
## Left out: [phase, from, to].
const CUTS := [["heal", 24.5, 27.5]]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var dog: AttackerUnit
var dog2: AttackerUnit
var hurt: Array = []
var chimp: AttackerUnit
var late: AttackerUnit
var walker: AttackerUnit
var pack: Array = []
var through: Array = []
var field: Array = []
var t := -1.0
var phase := ""
var test := false
var video := false
var _phase_i := -1
var _phase_t := 0.0
var _steps := {}
var _checks: Array[String] = []
var _failed := false
var _hp_mark := {}
var _sweep_done := -1.0
var _blasts_mark := 0
## The sweep, watched: each dog's mine as it takes it [time, dog, mine, its ring then], digs started
## (dog -> time), how long each dig took, how close a dog came to a live mine not its own.
var _picks: Array = []
var _held := {}
var _dig_from := {}
var _dig_times: Array[float] = []
## Where the mines were, in the order they were disarmed.
var _disarmed_at: Array[Vector3] = []
var _closest := INF
var _seen_dug := 0
var _seen_hidden := 0
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
var _cursor_on = null
var _pan_from := Vector3.ZERO
var _pan_to := Vector3.ZERO
var _pan_t := Vector2.ZERO
var _follow: AttackerUnit = null
var _caption: Label
var _keycap: Label
var _status: Label
var _legend: Label
var _ghosts: MeshInstance3D
var _ghost_mesh: ImmediateMesh
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false
var _frame := -1
var _shot := ""
var _fast := 1
var _fast_from := 0
var _cutting := false
var _cut_from := 0


func _ready() -> void:
	seed(11)  # the same run every time
	test = "--test" in OS.get_cmdline_user_args()
	video = "--video" in OS.get_cmdline_user_args()
	if video:
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# Staged: the Gunner Squad sits this one out, the posts and the AA turrets hold fire.
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
	for s in level.stations:
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		s.process_mode = Node.PROCESS_MODE_DISABLED
	for a in level.aa_turrets:
		a.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		a.process_mode = Node.PROCESS_MODE_DISABLED
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
	rig.rotation.y = 0.0  # looking north, up the lane at the south face
	rig.pitch = deg_to_rad(-50.0)
	rig._target_zoom = HEAL_ZOOM
	rig.zoom = HEAL_ZOOM
	rig.focus(HEAL_AT + Vector3(0, 0, 6))
	_pan_from = rig.position
	_pan_to = rig.position
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	_ghost_mesh = ImmediateMesh.new()
	_ghosts = MeshInstance3D.new()
	_ghosts.mesh = _ghost_mesh
	var mark := Mats.unshaded(Color(1.0, 0.2, 0.15, 0.6), true).duplicate() as StandardMaterial3D
	mark.cull_mode = BaseMaterial3D.CULL_DISABLED  # the discs face up or down alike
	_ghosts.material_override = mark
	_ghosts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghosts.visible = false
	add_child(_ghosts)
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	dog = _spawn("medic", HEAL_AT + DOG_FROM, 0.0)
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))


func _spawn(type_id: String, pos: Vector3, yaw: float) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = yaw
	return u


func _hurt(type_id: String, pos: Vector3, hp: float) -> AttackerUnit:
	var u := _spawn(type_id, pos, PI)
	u.take_damage(u.stats.hp - hp, GameConfig.TEAM_DEFENDER)
	return u


func _process(delta: float) -> void:
	_frame += 1
	if t < 0.0:
		return
	t += delta
	_phase_t += delta
	if _phase_i < 0 or _phase_over():
		_phase_i += 1
		if _phase_i >= PHASES.size():
			_finish()
			return
		phase = PHASES[_phase_i][0]
		_phase_t = 0.0
		_steps.clear()
	match phase:
		"intro":
			_say("Wolf Medic", "No basic attack, no passive: two modes, one always on (T switches)")
		"heal":
			_heal_step()
		"hidden":
			_hidden_step()
		"sweep":
			_sweep_step()
		"through":
			_through_step()
		"outro":
			_say("", "")
	_watch_sweep()
	_update_cursor()
	_update_pan()
	_update_status()
	_draw_ghosts()
	if video:
		_direct()
	if not _snaps.is_empty():
		_snap()


func _phase_over() -> bool:
	var length: float = PHASES[_phase_i][1]
	if length >= 0.0:
		return _phase_t >= length
	if _sweep_done >= 0.0 and t >= _sweep_done + SWEEP_TAIL:
		return true
	return _phase_t >= SWEEP_MAX


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- phases

## A dog sent up to four hurt units heals the first two it comes to, sticks with them (a chimp hurt worse
## runs up next to it: it waits), takes the chimp once the kangaroo is full, lets the rifleman go when he
## walks off out of its reach and takes the next; a second dog takes the other two.
func _heal_step() -> void:
	if _once("start"):
		_say("Healing", "It heals up to 2 hurt units near it at once, a little at a time, even on the move")
		for h in HURT:
			hurt.append(_hurt(h[0], HEAL_AT + h[1], h[2]))
		chimp = _hurt("chimp", HEAL_AT + CHIMP_FROM, CHIMP_HP)
	var ram: AttackerUnit = hurt[0]
	var kangaroo: AttackerUnit = hurt[1]
	if _phase_at(0.4, "select"):
		_move_cursor(_screen(dog.global_position + Vector3.UP), 0.4, 1.0)
	if _phase_at(1.1, "click"):
		_click()
		_check(controller.selected == [dog], "heal: the dog is selected")
	if _phase_at(1.3, "aim"):
		_move_cursor(_screen(HEAL_AT + DOG_STOP), 1.3, 2.0)
	if _phase_at(2.1, "order"):
		_right_click(false)
		_keycap_show("RMB")
	if _phase_at(2.8, "key_off"):
		_keycap.visible = false
	if _phase_at(3.4, "first_two"):
		print("DOG heal: patients %s" % [dog.patients.map(func(u): return u.type_id)])
		_check(dog.heals() and dog.dog_mode == "heal", "heal: a new dog comes healing")
		_check(dog.patients.size() == 2 and ram in dog.patients and kangaroo in dog.patients,
				"heal: it takes the first two it comes to, on the move (%s)" % [dog.patients.map(func(u): return u.type_id)])
		_check(ram.get("_heal_icon").visible and kangaroo.get("_heal_icon").visible, "heal: a cross over each unit it heals")
		_check(dog.get("_beams").all(func(b): return b.visible), "heal: a beam to each")
		_hp_mark[kangaroo] = kangaroo.hp
	if _phase_at(3.8, "chimp"):
		commander.submit({"type": "move", "units": [chimp.unit_id], "pos": HEAL_AT + CHIMP_TO, "attack": false})
	if _phase_at(4.4, "rate"):
		var gained: float = kangaroo.hp - _hp_mark[kangaroo]
		print("DOG heal: the kangaroo gained %.1f HP in 1 s" % gained)
		_check(absf(gained - dog.stats.heal_rate) < 0.6, "heal: %.0f HP/s each (%.1f)" % [dog.stats.heal_rate, gained])
		_say("Committed", "A chimp hurt worse runs up next to it: it sticks with the two it took...")
	if _phase_at(7.0, "chimp_waits"):
		var d := _flat(chimp.global_position, dog.global_position)
		print("DOG heal: chimp %.1f m from the dog, hp %.0f, patients %s" % [d, chimp.hp, dog.patients.map(func(u): return u.type_id)])
		print("DOG heal: dog at %s, chimp at %s" % [(dog.global_position - HEAL_AT).snapped(Vector3.ONE * 0.1), (chimp.global_position - HEAL_AT).snapped(Vector3.ONE * 0.1)])
		_check(d < 3.5 and chimp.hp == CHIMP_HP and chimp.medic == null, "heal: the chimp next to it (%.1f m) waits, unhealed" % d)
		_check(ram in dog.patients and kangaroo in dog.patients, "heal: it stays on its two")
	if kangaroo.hp >= kangaroo.stats.hp and _once("kangaroo_full"):
		_mark("kangaroo full")
		_say("Committed", "...until one is full: then it takes the next")
	if _phase_at(9.0, "next"):
		print("DOG heal: patients %s" % [dog.patients.map(func(u): return u.type_id)])
		_check(kangaroo.hp >= kangaroo.stats.hp and not kangaroo in dog.patients, "heal: the kangaroo full, let go")
		_check(chimp in dog.patients and chimp.hp > CHIMP_HP, "heal: it takes the chimp next (%.0f HP)" % chimp.hp)
	if _phase_at(9.6, "walk_off"):
		_say("Out of reach", "The ram it heals walks off: it lets it go and takes the next")
		commander.submit({"type": "move", "units": [ram.unit_id], "pos": HEAL_AT + WALK_OFF, "attack": false})
	if _phase_at(12.2, "gone"):
		print("DOG heal: ram %.1f m off, hp %.0f; patients %s" % [_flat(ram.global_position, dog.global_position), ram.hp,
				dog.patients.map(func(u): return u.type_id)])
		_check(not ram in dog.patients and ram.hp < ram.stats.hp, "heal: the ram out of reach is let go, not yet full (%.0f HP)" % ram.hp)
		_check(dog.patients.size() == 2 and dog.patients.any(func(u): return u.type_id in ["hippo", "rhino"]), "heal: it takes the next (%s)" % [dog.patients.map(func(u): return u.type_id)])
		_check(not ram.get("_heal_icon").visible, "heal: no cross over it any more")
	if _phase_at(12.5, "dog2"):
		_say("Two dogs", "A second dog comes up: it takes the others. No unit is healed by two")
		late = _hurt(LATE[0], HEAL_AT + LATE[1], LATE[2])
		dog2 = _spawn("medic", HEAL_AT + DOG2_FROM, -PI * 0.25)
		commander.submit({"type": "move", "units": [dog2.unit_id], "pos": HEAL_AT + DOG2_STOP, "attack": false})
		_pan(HEAL_AT + Vector3(0, 0, 2), 12.5, 14.0)
	if _phase_at(18.5, "two_dogs"):
		var a: Array = dog.patients
		var b: Array = dog2.patients
		print("DOG heal: dog 1 %s, dog 2 %s" % [a.map(func(u): return u.type_id), b.map(func(u): return u.type_id)])
		_check(a.size() == 2 and b.size() == 2, "heal: each dog heals two (%d, %d)" % [a.size(), b.size()])
		_check(not a.any(func(u): return u in b), "heal: none healed by both")
		_check(late in b, "heal: the second dog takes the bison it alone reaches")
		var healed := commander.units.values().filter(func(u): return u.medic != null)
		_check(healed.size() == 4 and healed.all(func(u): return u.get("_heal_icon").visible), "heal: four crosses (%d)" % healed.size())
	if _phase_at(19.5, "deselect"):
		controller._set_selection([])
		_say("", "")


## The minefield across the lane: the defender sees it, the attacking player doesn't; a rifleman walking
## across it is blown up all the same.
func _hidden_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_say("The AA Squads' mines", "Hidden from you: they aren't drawn on the attacker's side")
		_lay_field()
		for p in PACK_AT:
			var u := _spawn("medic", p, 0.0)
			u.mine_disarmed.connect(_on_disarmed.bind(u))
			pack.append(u)
		walker = _spawn("rifleman", WALKER[0], 0.0)
		_pan(FIELD_AT + Vector3(0, 0, 9), 0.0, 2.0)
		rig._target_zoom = FIELD_ZOOM
	if _phase_at(2.0, "hidden"):
		var shown := field.filter(func(m): return m.get("_body").visible).size()
		_check(shown == 0, "hidden: on the attacker's side no mine is drawn (%d/%d)" % [shown, field.size()])
	if _phase_at(3.0, "defender"):
		GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
		_say("The defender's side", "The defender sees every mine")
	if _phase_at(4.0, "seen"):
		var shown := field.filter(func(m): return m.get("_body").visible).size()
		_check(shown == field.size(), "hidden: the defender sees them all (%d/%d)" % [shown, field.size()])
	if _phase_at(7.0, "attacker"):
		GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
		_say("The attacker's side", "You don't: the same field, as you see it")
	if _phase_at(8.0, "walk"):
		_say("They still go off", "A rifleman walking across it")
		_blasts_mark = GroundMine.blasts
		commander.submit({"type": "move", "units": [walker.unit_id], "pos": WALKER[1], "attack": false})
	if _phase_at(12.5, "blown"):
		var went := GroundMine.blasts - _blasts_mark
		print("DOG hidden: %d mine(s) went off, the rifleman %s" % [went, "dead" if not walker.is_alive() else "alive (%.0f)" % walker.hp])
		_check(went >= 1 and not walker.is_alive(), "hidden: a hidden mine goes off under the rifleman (%d)" % went)
		field = field.filter(func(m): return is_instance_valid(m) and m.is_laid())


## Four dogs are box-selected, T switches them to minesweeping, RMB in front of the field: they clear it.
func _sweep_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_say("Minesweeping", "Four dogs, T: each sniffs out the mines round it")
		_pan(_centre(pack) + Vector3(0, 0, 4), 0.0, 1.0)
		rig._target_zoom = HEAL_ZOOM + 4.0
		_blasts_mark = GroundMine.blasts
	if _phase_at(1.2, "select"):
		_move_cursor(_group_rect(pack).position, 1.2, 1.8)
	if _phase_at(1.9, "press"):
		_mouse_button(true)
	if _phase_t > 1.9 and _phase_t < 2.6:
		_move_cursor(_group_rect(pack).end, 1.9, 2.6)
		_mouse_motion()
	if _phase_at(2.6, "release"):
		_mouse_button(false)
		_check(controller.selected.size() == pack.size(), "sweep: the four dogs box-selected (%d)" % controller.selected.size())
	if _phase_at(3.3, "key"):
		_key(AttackerController.SCOUT_KEY)
		_keycap_show("T")
		_check(pack.all(func(u): return u.dog_mode == "sweep"), "sweep: T switches them all to minesweeping")
		_check(pack.all(func(u): return u.get("_sweep_ring").visible and not u.get("_heal_ring").visible), "sweep: each shows how far it sniffs mines out")
	if _phase_at(4.0, "aim"):
		_check(controller.get("_dog_button").text.contains("MINESWEEPING"), "sweep: the HUD says so (%s)" % controller.get("_dog_button").text)
		_keycap.visible = false
		_pan(FIELD_AT + Vector3(0, 0, 17), 4.0, 5.5)
		rig._target_zoom = FIELD_ZOOM + 4.0
	if _phase_t > 5.5 and _phase_t < 6.4:
		_cursor_on = null
		_move_cursor(_screen(PACK_TO), 5.5, 6.3)
	if _phase_at(6.4, "order"):
		_right_click(false)
		_keycap_show("RMB")
		_say("Minesweeping", "RMB beyond the field: they find the mines on their way and clear a way through")
		_pan(FIELD_AT + Vector3(0, 0, 10), 6.4, 8.5)
	if _phase_at(7.2, "key_off"):
		_keycap.visible = false
		_move_cursor(get_viewport().get_visible_rect().size * Vector2(0.88, 0.62), 7.2, 8.2)
	# Close in on the first dog to dig, then the whole field.
	if _phase_t > 7.0 and not _steps.has("followed"):
		for u in pack:
			if u.is_digging():
				_steps["followed"] = true
				_follow = u
				_mark("first dig")
				_say("Digging it out", "It digs the mine out and disarms it (6 s): while it digs, the mine shows to you")
				_pan(u.global_position + Vector3(0, 0, 2), _phase_t, _phase_t + 1.5)
				rig._target_zoom = DIG_ZOOM
				break
	if _phase_at(20.0, "wide"):
		_follow = null
		_say("Outer rim first", "Working inwards, never across a live mine: a mine inside the field waits till the ones round it are out")
		_pan(FIELD_AT + Vector3(0, 0, 4), 20.0, 22.0)
		rig._target_zoom = FIELD_ZOOM
	if test and _phase_t > 6.0 and int(_phase_t / 10.0) != int((_phase_t - get_process_delta_time()) / 10.0):
		for u in pack:
			print("DOG sweep +%.0f %s at %s order %s, mine %s%s" % [_phase_t, u.name, u.global_position.snapped(Vector3.ONE * 0.1), u.order.type,
					u.sweep_mine.spot().snapped(Vector3.ONE * 0.1) if u.sweep_mine else "-", " digging" if u.is_digging() else ""])
	if _sweep_done < 0.0 and _phase_t > 6.0 and field.all(func(m): return not is_instance_valid(m) or m.is_disarmed()):
		_sweep_done = t
		_mark("field clear")
		_say("Field cleared", "%d mines dug out and disarmed" % pack.reduce(func(n, u): return n + u.mines_disarmed, 0))
	if _sweep_done >= 0.0 and _once("checks"):
		_sweep_checks()


## Riflemen walk across the cleared field (a plain move: nothing stops them).
func _through_step() -> void:
	if _once("start"):
		_say("The way through", "Riflemen walk across where the field was")
		_blasts_mark = GroundMine.blasts
		for x in THROUGH_X:
			through.append(_spawn("rifleman", Vector3(x, 0.0, 145.0), 0.0))
		controller._set_selection([])
		_pan(FIELD_AT + Vector3(0, 0, 6), 0.0, 1.0)
	if _phase_at(0.6, "go"):
		for u in through:
			commander.submit({"type": "move", "units": [u.unit_id], "pos": Vector3(u.global_position.x, 0.0, 104.0), "attack": false})
	if _phase_at(10.5, "check"):
		var across := through.filter(func(u): return u.is_alive() and u.global_position.z < FIELD_AT.z - FIELD_HALF.y)
		_check(GroundMine.blasts == _blasts_mark and across.size() == through.size(), "through: %d/%d riflemen across, no mine went off" % [across.size(), through.size()])


## Lays the field: mines no closer than MINE_SPACING over an ellipse across the lane, on open ground.
func _lay_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var map := get_world_3d().navigation_map
	var space := get_world_3d().direct_space_state
	var spots: Array[Vector3] = []
	for k in 4000:
		if spots.size() >= MINES:
			break
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf())
		var p := FIELD_AT + Vector3(cos(a) * FIELD_HALF.x * r, 0.0, sin(a) * FIELD_HALF.y * r)
		if spots.any(func(q): return _flat(q, p) < MINE_SPACING):
			continue
		var c := NavigationServer3D.map_get_closest_point(map, p + Vector3.UP * 0.5)
		if _flat(c, p) > 0.3:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0, GameConfig.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		spots.append(hit.position if not hit.is_empty() else c)
	for p in spots:
		var m := GroundMine.new()
		add_child(m)
		m.lay(p)
		field.append(m)
	print("DOG hidden: %d mines laid" % field.size())


# ---------------------------------------------------------------- watching the sweep

## Every frame of the sweep: each dog's pick of a mine (and its ring among the live mines then), its digs
## and how long they take, and how close any dog comes to a live mine it isn't digging out.
func _watch_sweep() -> void:
	if pack.is_empty():
		return
	var live := field.filter(func(m): return is_instance_valid(m) and m.is_laid())
	for u in pack:
		if not u.is_alive():
			continue
		var m = u.sweep_mine
		var id: int = m.get_instance_id() if m != null else 0
		if m != null and _held.get(u, 0) != id:
			var rings := DogSweep._rings(GroundMine.all.filter(func(x): return x.is_laid()))
			_picks.append([t, u, m.spot(), rings.get(m, -1)])
			if test:
				print("DOG sweep +%.1f %s takes the mine at %s (ring %d, %d live)" % [_phase_t, u.name, m.spot().snapped(Vector3.ONE * 0.1), rings.get(m, -1), live.size()])
		_held[u] = id
		if u.is_digging() and not _dig_from.has(u):
			_dig_from[u] = t - u.dig_progress() * u.stats.disarm_time
		elif not u.is_digging() and _dig_from.has(u):
			_dig_from.erase(u)
		for x in live:
			if x != m:
				var d := _flat(x.spot(), u.global_position)
				if d < _closest:
					_closest = d
					if test and d < DogSweep.CLEAR:
						print("DOG sweep +%.1f %s %.2f m from the mine at %s (%s, digging %s, way %d points)" % [_phase_t, u.name, d,
								x.spot().snapped(Vector3.ONE * 0.1), "its mine at %s" % m.spot().snapped(Vector3.ONE * 0.1) if m else "no mine",
								u.is_digging(), u.get("_sweep_path").size()])
	# What the attacking player sees: the mines being dug out, not the others.
	if GameConfig.player_side != GameConfig.PlayerSide.ATTACKER:
		return
	for x in live:
		if x.dug > 0.0 and x.sweeper != null:
			_seen_dug += 1 if x.get("_body").visible else -1000
		elif x.dug == 0.0:
			_seen_hidden += 1 if not x.get("_body").visible else -1000


func _on_disarmed(m: GroundMine, u: AttackerUnit) -> void:
	_disarmed_at.append(m.spot())
	if _dig_from.has(u):
		_dig_times.append(t - _dig_from[u])
		_dig_from.erase(u)
	if test:
		print("DOG sweep +%.1f %s disarmed the mine at %s (%d left)" % [_phase_t, u.name, m.spot().snapped(Vector3.ONE * 0.1),
				field.filter(func(x): return is_instance_valid(x) and x.is_laid()).size()])


func _sweep_checks() -> void:
	var cleared: int = pack.reduce(func(n, u): return n + u.mines_disarmed, 0)
	var rim := _picks.filter(func(p): return p[3] == 0).size()
	print("DOG sweep: %d mines disarmed in %.0f s, %d picks (%d on the rim then), closest to a live mine not its own %.2f m" % [
			cleared, t - _sweep_started(), _picks.size(), rim, _closest])
	print("DOG sweep: picks by ring %s, digs %s s" % [_picks.map(func(p): return p[3]), _dig_times.map(func(x): return snappedf(x, 0.05))])
	_check(cleared == field.size(), "sweep: every mine dug out and disarmed (%d/%d)" % [cleared, field.size()])
	_check(GroundMine.blasts == _blasts_mark, "sweep: none went off")
	_check(_closest >= TRIGGER_REACH, "sweep: no dog ever came within reach of a live mine but its own (closest %.2f m)" % _closest)
	var deepest: int = _picks.map(func(p): return p[3]).max()
	_check(rim >= _picks.size() * 0.7 and deepest <= 1, "sweep: the outer rim first: %d/%d picks on the edge of what was left, none deeper than the next ring in (%d)" % [rim, _picks.size(), deepest])
	_check(not _dig_times.is_empty() and _dig_times.all(func(x): return absf(x - pack[0].stats.disarm_time) < 0.15),
			"sweep: each dig takes %.0f s" % pack[0].stats.disarm_time)
	_check(pack.all(func(u): return u.mines_disarmed > 0), "sweep: the pack shares the field (%s)" % [pack.map(func(u): return u.mines_disarmed)])
	_check(_seen_dug > 0 and _seen_hidden > 0, "sweep: only the mine being dug out shows to the attacker (%d / %d frames)" % [_seen_dug, _seen_hidden])


func _sweep_started() -> float:
	return _picks[0][0] if not _picks.is_empty() else t


# ---------------------------------------------------------------- checks

func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _mark(what: String) -> void:
	if test:
		print("DOG %s +%.1f: %s" % [phase, _phase_t, what])


func _finish() -> void:
	for c in _checks:
		print("DOG CHECK ", c)
	print("DOG SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame])
		if _cutting:
			print("CUT frames %d-%d" % [_cut_from, _frame])
		print("VIDEO END frame %d" % _frame)
	get_tree().quit()


# ---------------------------------------------------------------- video

## Video: the camera for this moment (SHOTS, else the RTS view), and the frames to speed up or leave out
## (only the frames the video keeps are drawn).
func _direct() -> void:
	var shot := "rts"
	for sh in SHOTS:
		if _within(sh):
			shot = sh[3]
	if shot == "dig" and _follow == null:
		shot = "rts"
	if shot != _shot:
		_shot = shot
		_cursor.visible = shot == "rts"
		_keycap.visible = _keycap.visible and shot == "rts"
		controller.visible = shot == "rts"
		if shot == "rts":
			controller.camera_rig.camera.current = true
		else:
			cam.current = true
	if shot != "rts":
		_place_cam(shot)
	var fast := 1
	for f in FAST:
		if _within(f):
			fast = f[3]
	if fast != _fast:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame - 1])
		_fast = fast
		_fast_from = _frame
	var cutting := CUTS.any(func(c): return _within(c))
	if cutting != _cutting:
		if _cutting:
			print("CUT frames %d-%d" % [_cut_from, _frame - 1])
		_cutting = cutting
		_cut_from = _frame
	RenderingServer.render_loop_enabled = not cutting and (_frame - _fast_from) % _fast == 0


func _within(r: Array) -> bool:
	return r[0] == phase and _phase_t >= r[1] and _phase_t < r[2]


func _place_cam(shot: String) -> void:
	var at := Vector3.ZERO
	var look := Vector3.ZERO
	match shot:
		"dog":
			# Round the dog standing, three quarters in front of it.
			var p := dog.global_position
			var a := 0.9 - _phase_t * 0.12
			at = p + Vector3(sin(a) * 4.2, 1.5, -cos(a) * 4.2)
			look = p + Vector3(0.0, 0.7, 0.0)
		"field_low":
			# Low across the minefield from its south side, the lane and the face beyond.
			at = FIELD_AT + Vector3(-9.0 + _phase_t * 0.6, 2.4, 13.0)
			look = FIELD_AT + Vector3(0.0, 0.0, -2.0)
		"dig":
			# Beside the first dog to dig, above the grass and the scrub, looking down at the hole in front of it.
			var u := _follow
			var fwd := -u.global_basis.z
			var right := u.global_basis.x
			at = u.global_position + right * 3.0 + fwd * 2.2 + Vector3.UP * 2.6
			look = u.global_position + fwd * 0.5 + Vector3.UP * 0.3
	cam.global_position = at
	cam.look_at(look)


## The counter (top right) while the field is out there: mines left, disarmed.
func _update_status() -> void:
	_status.visible = phase in ["hidden", "sweep"] and not field.is_empty() and not test
	if _status.visible:
		var left := field.filter(func(m): return is_instance_valid(m) and m.is_laid()).size()
		var digging := pack.filter(func(u): return u.is_digging()).size()
		_status.text = "Mines left  %d\nDisarmed  %d\nDogs digging  %d" % [left, pack.reduce(func(n, u): return n + u.mines_disarmed, 0), digging]


## For the viewer: a dashed red ring on every hidden mine the player can't see (none on the defender's side,
## where they are drawn, nor on the one being dug out, which shows).
func _draw_ghosts() -> void:
	_ghosts.visible = not test and phase in ["hidden", "sweep"] and GameConfig.player_side == GameConfig.PlayerSide.ATTACKER \
			and (phase == "sweep" or _phase_t > 7.0)
	_legend.visible = _ghosts.visible and _shot in ["rts", ""]
	if not _ghosts.visible:
		return
	_ghost_mesh.clear_surfaces()
	var hidden := field.filter(func(m): return is_instance_valid(m) and m.is_laid() and m.dug == 0.0)
	if hidden.is_empty():
		return
	_ghost_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in hidden:
		var c: Vector3 = m.spot() + Vector3.UP * 0.1
		for k in 12:
			var a0 := TAU * k / 12
			var a1 := TAU * (k + 1) / 12
			_ghost_mesh.surface_add_vertex(c)
			_ghost_mesh.surface_add_vertex(c + Vector3(cos(a1), 0.0, sin(a1)) * GHOST_R)
			_ghost_mesh.surface_add_vertex(c + Vector3(cos(a0), 0.0, sin(a0)) * GHOST_R)
	_ghost_mesh.surface_end()
	_ghost_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for m in hidden:
		RhinoAim.dashed_circle(_ghost_mesh, m.spot() + Vector3.UP * 0.12, GHOST_R + 0.15, 10)
	_ghost_mesh.surface_end()


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _centre(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in list:
		c += u.global_position
	return c / list.size()


func _screen(p: Vector3) -> Vector2:
	return controller.camera_rig.camera.unproject_position(p)


func _group_rect(units: Array) -> Rect2:
	var r := Rect2(_screen(units[0].global_position + Vector3.UP), Vector2.ZERO)
	for u in units:
		r = r.expand(_screen(u.global_position + Vector3.UP))
	return r.grow(40.0)


func _move_cursor(to: Vector2, start: float, end: float) -> void:
	_cursor_from = _cursor.position
	_cursor_to = to
	_cursor_t = Vector2(start, end)


func _update_cursor() -> void:
	var pos := _cursor_from.lerp(_cursor_to, smoothstep(_cursor_t.x, _cursor_t.y, _phase_t))
	if _cursor_on != null:
		pos = _screen(_cursor_on)
		_cursor_from = pos
		_cursor_to = pos
	get_viewport().warp_mouse(pos)
	_cursor.position = pos


## Pans the view (as with WASD) to `to` between `start` and `end` (phase seconds); a dog being followed
## keeps the view on it.
func _pan(to: Vector3, start: float, end: float) -> void:
	_pan_from = controller.camera_rig.position
	_pan_to = to
	_pan_t = Vector2(start, end)


func _update_pan() -> void:
	var rig := controller.camera_rig
	var w := smoothstep(_pan_t.x, _pan_t.y, _phase_t) if _pan_t.y > _pan_t.x else 1.0
	var p := _pan_from.lerp(_pan_to, w)
	if _follow != null and w >= 1.0:
		p = p.lerp(_follow.global_position + Vector3(0, 0, 2), minf(get_process_delta_time() * 2.0, 1.0))
		_pan_to = p
		_pan_from = p
	rig.position.x = p.x
	rig.position.z = p.z


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _mouse_button(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _mouse_motion() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _click() -> void:
	_mouse_button(true)
	_mouse_button(false)


func _right_click(ctrl: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.position = _cursor.position
	controller._unhandled_input(ev)


func _keycap_show(text: String) -> void:
	_keycap.text = text
	_keycap.visible = true


# ---------------------------------------------------------------- overlay

func _say(title: String, sub: String) -> void:
	_caption.text = title if sub == "" else "%s\n%s" % [title, sub]
	_caption.visible = title != ""


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
	_keycap = UIKit.label("", 30, Color(1.0, 0.85, 0.3))
	_keycap.add_theme_color_override("font_outline_color", Color.BLACK)
	_keycap.add_theme_constant_override("outline_size", 8)
	_keycap.position = Vector2(40, 300)
	_keycap.visible = false
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_keycap)
	_status = UIKit.label("", 17, Color(1.0, 0.95, 0.75))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 120)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	layer.add_child(_status)
	_legend = UIKit.label("Red marks: the hidden mines, shown for this video only (the player never sees them)", 15, Color(1.0, 0.6, 0.55))
	_legend.add_theme_color_override("font_outline_color", Color.BLACK)
	_legend.add_theme_constant_override("outline_size", 4)
	_legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_legend.position = Vector2(_legend.position.x - 16, 205)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.visible = false
	layer.add_child(_legend)
	# Movie Maker doesn't record the system cursor: draw one.
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_cursor)
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 17), Vector2(10, 26),
			Vector2(14, 24), Vector2(10, 15), Vector2(17, 15)])
	arrow.color = Color.WHITE
	var outline := Line2D.new()
	outline.points = arrow.polygon
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.BLACK
	_cursor.add_child(arrow)
	_cursor.add_child(outline)
	_cursor.position = get_viewport().get_visible_rect().size * 0.5
	_cursor_from = _cursor.position
	_cursor_to = _cursor.position


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
