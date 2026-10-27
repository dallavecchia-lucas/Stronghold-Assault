extends Node3D
## Staged run of the Kangaroo Commando on the real map, its skills used the way a player uses them
## (the RTS view, this node working the mouse and keys) against the south face:
##
##   hop     a lone kangaroo bounds across the south field
##   flash   three kangaroos are box-selected, R, the cursor on the gate machine gun on the gun deck,
##           LMB: they rear up and throw, their grenades spread along the deck, and the bangs blind
##           the gunners and riflemen there
##   screen  the defender's side: on the deck rifleman a kangaroo flashes, the screen goes white
##   supply  a kangaroo hops up to five units whose skills are cooling down: ammo boxes over the
##           three nearest, their cooldowns running faster; a second kangaroo takes the other two
##           (the cut never stacks)
##   smg     the three shoot a rifleman out in front of the face, rearing their chests up to level
##           the side SMGs on it, the guns firing in turn
##   storm   the south gate falls and the three go in: on their own inside, they hunt the
##           defenders and flash them
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/kangaroo_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie kangaroo.avi \
##       --fixed-fps 30 res://scenes/dev/kangaroo_showcase.tscn -- --video > kangaroo.log
##   python3 tools/video/cut_showcase.py kangaroo.avi kangaroo.log media/kangaroo_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times.
## --test prints what the kangaroos do and checks it at the end (KANGAROO SHOWCASE PASS / FAIL).
## --video cuts in the cameras (SHOTS): beside the hopper (a stretch of it in slow motion), close by a
## kangaroo rearing up to throw, along the gun deck as the grenades go off, through the rifleman's own
## eyes as the flash whites them out, close by the SMGs, and for the storm in the gate tunnel, at the
## foot of the ramp, in the spawn hall, on the stairs and on the gun deck (where the raid gets to each
## when it does: the run is the same every time); the RTS view for the player's hands. Waits are cut
## and the long walks sped up (printing the frames for tools/video/cut_showcase.py, drawing only the
## frames it keeps); work lights light the bay (video only, like the cameras).
## The garrison's posts hold fire until the storm; the AA turrets hold fire throughout.

## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [2.0, "hop"], [11.0, "flash"], [29.0, "screen"], [40.0, "supply"],
		[54.0, "smg"], [61.0, "storm"], [93.0, "outro"], [95.0, "end"]]
## The lone hopper's run, down the south attack lane (kept clear of trees and rocks).
const HOP_FROM := Vector3(-17.0, 0.0, 162.0)
const HOP_TO := Vector3(17.0, 0.0, 112.0)
## The three that flash the gun deck, shoot it up and storm the gate (within a throw of the deck).
const TRIO_AT := [Vector3(-11.0, 0.0, 89.0), Vector3(-3.0, 0.0, 91.0), Vector3(5.0, 0.0, 89.0)]
## The supply run: five units whose skills cool down round SUPPLY_AT, one more out of reach, and the
## two kangaroos that come up to them.
const SUPPLY_AT := Vector3(2.0, 0.0, 138.0)
const SUPPLY_GROUP := [["rhino", Vector3(-3.5, 0.0, 0.0)], ["rhino", Vector3(3.5, 0.0, 1.0)],
		["hippo", Vector3(0.0, 0.0, 5.0)], ["bison_gun", Vector3(-5.5, 0.0, 7.5)], ["breacher", Vector3(5.0, 0.0, 7.5)],
		["rhino", Vector3(-15.0, 0.0, -1.0)]]
const SUPPLIER_STOPS := [Vector3(0.0, 0.0, 2.5), Vector3(0.0, 0.0, 9.5)]
## Defenders inside the bay the raid meets (snapped onto the floor), the deck riflemen besides.
const INSIDE_GUARDS := [Vector3(2.0, 2.8, 67.6), Vector3(0.0, 0.0, 58.0)]
## A defender out in front of the face for the SMGs (the deck's riflemen hide behind its parapet).
const SMG_TARGET := Vector3(9.0, 0.0, 83.0)
const FIELD_ZOOM := 34.0
const FACE_ZOOM := 30.0
const SUPPLY_ZOOM := 24.0
## Video: cameras other than the RTS view, as [phase, from, to (phase seconds), shot]. The screen
## phase is seen through the rifleman's eyes.
const SHOTS := [["intro", 0.0, 2.0, "trio"], ["hop", 0.0, 9.0, "hop"], ["flash", 7.0, 8.9, "throw"],
		["flash", 8.9, 11.4, "deck"], ["smg", 0.4, 5.0, "smg"], ["storm", 3.6, 5.2, "tunnel"],
		["storm", 5.2, 10.6, "ramp"], ["storm", 10.6, 16.5, "hall"], ["storm", 16.5, 19.6, "stairs"],
		["storm", 19.6, 24.6, "deck_east"], ["storm", 24.6, 30.0, "deck_west"], ["outro", 0.0, 2.0, "deck_west"]]
## Slow motion: [phase, from, to, time scale].
const SLOWMO := [["hop", 3.0, 5.2, 0.35], ["flash", 7.0, 8.6, 0.5]]
## Played faster: [phase, from, to, every k-th frame kept]; left out: [phase, from, to].
const FAST := [["storm", 16.5, 30.0, 2]]
const CUTS := [["flash", 13.5, 18.0], ["screen", 0.0, 0.5], ["screen", 7.5, 11.0], ["supply", 12.5, 14.0],
		["smg", 5.5, 7.0], ["storm", 30.0, 32.0]]
## Work lights in the bay the raid goes through (video only).
const WORK_LIGHTS := [Vector3(-4.0, 2.4, 73.0), Vector3(0.0, 4.6, 68.0), Vector3(4.5, 4.8, 66.0),
		Vector3(0.0, 4.5, 58.0), Vector3(2.0, 9.5, 64.0)]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var hopper: AttackerUnit
var trio: Array = []
var group: Array = []
var suppliers: Array = []
var guards: Array = []
var gate: Structure
var mg: Node3D
var deck: Array = []
var defender: DefenderController
var cam: Camera3D
var t := -1.0
var phase := ""
var test := false
var video := false
var _phase_t := 0.0
var _steps := {}
var _checks: Array[String] = []
var _failed := false
var _bangs: Array = []  # [time, position, thrower raiding]
var _raid_flashes := 0
var _raid_blinded := {}
var _hop_samples := 0
var _hop_ok := 0
var _cd_mark := {}
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
var _cursor_on = null
var _pan_from := Vector3.ZERO
var _pan_to := Vector3.ZERO
var _pan_t := Vector2.ZERO
var _caption: Label
var _keycap: Label
var _status: Label
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
	seed(7)  # the same run every time
	test = "--test" in OS.get_cmdline_user_args()
	video = "--video" in OS.get_cmdline_user_args()
	if video:
		RenderingServer.render_loop_enabled = false  # nothing to see while the level loads
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	gate = level.gates["south"]
	# Staged: the Gunner Squad sits this one out, the posts hold fire until the storm.
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
	for s in level.stations:
		# Held, but still there to aim at and shoot (disabled bodies leave the physics space).
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		s.process_mode = Node.PROCESS_MODE_DISABLED
		match String(s.name):
			"MG_south": mg = s
			"Soldier_south_2", "Soldier_south_4": deck.append(s)
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
	rig.rotation.y = 0.0  # looking north, at the south face
	rig.pitch = deg_to_rad(-48.0)
	rig._target_zoom = FIELD_ZOOM
	rig.zoom = FIELD_ZOOM
	rig.focus(HOP_FROM + Vector3(10, 0, -6))
	_pan_from = rig.position
	_pan_to = rig.position
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	if video:
		for p in WORK_LIGHTS:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.86, 0.68)
			l.light_energy = 1.6
			l.omni_range = 11.0
			l.position = p
			add_child(l)
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	hopper = _spawn("kangaroo", HOP_FROM, PI * 0.5)
	for p in TRIO_AT:
		trio.append(_spawn("kangaroo", p, 0.0))
	for u in trio:
		u.flash_thrown.connect(_on_thrown.bind(u))
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))


func _spawn(type_id: String, pos: Vector3, yaw: float) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos + Vector3.UP * 0.2
	u.rotation.y = yaw
	return u


func _on_thrown(g: FlashGrenade, spot: Vector3, u: AttackerUnit) -> void:
	var raiding := u.raiding
	print("KANGAROO %s %s throws at %s (%.0f m)%s" % [phase, u.name, spot.snapped(Vector3.ONE * 0.1), _flat(u.global_position, spot),
			" raiding" if raiding else ""])
	g.went_off.connect(func(at: Vector3):
		_bangs.append([t, at, raiding])
		var caught := []
		for d in get_tree().get_nodes_in_group("defender_targets"):
			if FlashGrenade.is_blind(d):
				caught.append(String(d.name))
				if raiding:
					_raid_blinded[d] = true
		print("KANGAROO %s bang at %s: blinded %s" % [phase, at.snapped(Vector3.ONE * 0.1), caught]))
	if raiding:
		_raid_flashes += 1


func _process(delta: float) -> void:
	_frame += 1
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
	match phase:
		"intro":
			_say("Kangaroo Commando", "Fast, two side-mounted SMGs, flash grenades, and it carries the supplies")
		"hop":
			_hop_step()
		"flash":
			_flash_step()
		"screen":
			_screen_step()
		"supply":
			_supply_step()
		"smg":
			_smg_step()
		"storm":
			_storm_step()
		"outro":
			_say("", "")
	_update_cursor()
	_update_pan()
	_update_status()
	if video:
		_direct()
	if not _snaps.is_empty():
		_snap()


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%04.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- phases

## A lone kangaroo bounds across the field: the Hop clip plays, about as fast whatever the speed.
func _hop_step() -> void:
	if _once("go"):
		_say("The hop", "Both feet together, the tail swinging against the legs")
		commander.submit({"type": "move", "units": [hopper.unit_id], "pos": HOP_TO, "attack": false})
		_pan(Vector3(0.0, 0.0, HOP_FROM.z - 4.0), 0.0, 7.0)
	var spd := Vector2(hopper.velocity.x, hopper.velocity.z).length()
	if spd > 6.0:
		_hop_samples += 1
		var ap: AnimationPlayer = hopper.get("_anim")
		if ap.current_animation == "Hop" and ap.speed_scale >= 0.8 and ap.speed_scale <= 1.3:
			_hop_ok += 1
	if _phase_at(8.5, "check"):
		_check(_hop_samples > 60 and _hop_ok >= _hop_samples - 2, "hop: Hop clip at 0.8-1.3x on %d/%d frames at speed" % [_hop_ok, _hop_samples])
		print("KANGAROO hop: %.1f m covered" % _flat(hopper.global_position, HOP_FROM))


## Box-select the three, R, the cursor on the gate machine gun, LMB: they rear up and throw, the
## grenades spread along the deck, and the bangs blind whoever is up there.
func _flash_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_say("Flash grenade", "Three kangaroos, R, then LMB on the gun deck: they stand up like boxers and throw")
		controller._set_selection([])
		_pan(_centre(trio) + Vector3(0, 0, 4), 0.0, 1.0)
		rig._target_zoom = FIELD_ZOOM
	if _phase_at(1.2, "select"):
		_move_cursor(_group_rect(trio).position, 1.2, 1.8)
	if _phase_at(1.9, "press"):
		_mouse_button(true)
	if _phase_t > 1.9 and _phase_t < 2.6:
		_move_cursor(_group_rect(trio).end, 1.9, 2.6)
		_mouse_motion()
	if _phase_at(2.6, "release"):
		_mouse_button(false)
	if _phase_at(3.2, "key"):
		_key(AttackerController.SMOKE_KEY)
		_keycap.text = "R"
		_keycap.visible = true
		_check(controller.get("_aiming") == "flash", "flash: R aims the kangaroos' flash grenades (%s)" % controller.get("_aiming"))
	if _phase_at(3.9, "pan"):
		_keycap.visible = false
		_pan(Vector3(mg.global_position.x, 0.0, mg.global_position.z + 9.0), 3.9, 5.6)
		rig._target_zoom = FACE_ZOOM
	# The cursor on the machine gun over the parapet: the grenades go to its feet on the deck.
	var over := Combat.aim_point(mg) + Vector3.UP * 0.2
	if _phase_at(4.4, "aim"):
		_move_cursor(_screen(over), 4.4, 6.2)
	if _phase_t > 6.2 and _phase_t < 7.0:
		_cursor_on = over
	if _phase_at(7.0, "fire"):
		_cursor_on = null
		var spots := KangarooFlash.spots(trio, mg.global_position)
		for i in trio.size():
			print("KANGAROO flash: %s -> %s (%.0f m)" % [trio[i].name, spots[i].snapped(Vector3.ONE * 0.1), _flat(trio[i].global_position, spots[i])])
		_check_spread(spots, trio[0].stats.flash_radius * KangarooFlash.SPACING, mg.global_position)
		get_viewport().warp_mouse(_cursor.position)
		_mouse_button(true)
		_keycap.text = "LMB"
		_keycap.visible = true
	if _phase_at(7.6, "throwing"):
		_keycap.visible = false
		var up := trio.filter(func(u): return u.is_throwing() and u.get("_anim").current_animation == "Throw")
		_check(up.size() == trio.size(), "flash: %d/%d kangaroos rear up and throw (Throw clip)" % [up.size(), trio.size()])
		_check(trio.all(func(u): return u.flash_cd > 25.0), "flash: 30 s cooldown started")
	if _phase_at(10.6, "blind"):
		var lit := _bangs.filter(func(b): return b[0] > t - 3.0).size()
		_check(lit == trio.size(), "flash: %d/%d grenades went off" % [lit, trio.size()])
		var blind := ([mg] + deck).filter(func(d): return FlashGrenade.is_blind(d))
		_check(blind.size() == 3, "flash: the deck's machine gun and both riflemen blinded (%s)" % [blind.map(func(d): return String(d.name))])
		_check(not trio.any(func(u): return u.is_throwing()), "flash: back down in the crouch")
	if _phase_at(13.0, "clear"):
		var blind := ([mg] + deck).filter(func(d): return FlashGrenade.is_blind(d))
		_check(blind.is_empty(), "flash: the blindness wore off after 2 s (%d still blind)" % blind.size())
		_move_cursor(get_viewport().get_visible_rect().size * Vector2(0.8, 0.85), 13.0, 14.0)


## The defender's side: the player on the deck rifleman; a kangaroo flashes the post and the screen goes
## white for flash_blind seconds, then clears.
func _screen_step() -> void:
	var soldier: DefenderSoldier = deck[0]
	if _once("start"):
		defender = DefenderController.new()
		defender.level = level
		add_child(defender)
		defender.select_station(level.stations.find(soldier), true)
		var k: AttackerUnit = trio[0]
		k.flash_cd = 0.0
		commander.submit({"type": "flash", "units": [k.unit_id], "pos": soldier.global_position})
		# The rifleman looks down at the kangaroo below.
		var to: Vector3 = k.global_position - soldier.global_position
		soldier.rotation.y = atan2(-to.x, -to.z)
		soldier.get_camera().get_parent().rotation.x = atan2(to.y + 1.0, Vector2(to.x, to.z).length())
		_say("The defender's side", "On the rifleman a kangaroo flashes: the screen goes full white for 2 s")
	if defender == null or _bangs.is_empty() or _bangs[-1][0] < t - _phase_t:
		return
	var since: float = t - _bangs[-1][0]
	var white := defender.whiteout()
	if _once("bang"):
		print("KANGAROO screen: bang %.1f m from the rifleman, whiteout %.2f" % [_bangs[-1][1].distance_to(soldier.global_position), white])
		_check(white == 1.0, "screen: the defender's screen goes full white (%.2f)" % white)
	if since > 1.9 and _once("held"):
		_check(white == 1.0, "screen: still full white 1.9 s on (%.2f)" % white)
	if since > 2.0 + DefenderController.FLASH_FADE + 0.2 and _once("cleared"):
		_check(white == 0.0, "screen: clear again after %.1f s (%.2f)" % [2.0 + DefenderController.FLASH_FADE, white])
	if since > 2.0 + DefenderController.FLASH_FADE + 1.4 and _once("back"):
		defender.current.unpossess()
		defender.queue_free()
		defender = null
		controller.camera_rig.camera.current = true
		controller.restore_mouse()


## A kangaroo hops up to five units whose skills are cooling down: the three nearest get its supplies
## (an ammo box over each), their cooldowns running resupply_cdr shorter. A second kangaroo takes the
## other two; none gets more than one kangaroo's cut.
func _supply_step() -> void:
	if _once("start"):
		_say("Supplies", "Each kangaroo resupplies up to 3 units near it: their skills come back 15% sooner")
		for g in SUPPLY_GROUP:
			var u := _spawn(g[0], SUPPLY_AT + g[1], 0.0)
			u.set(_skill_cd(u), 40.0)
			group.append(u)
		for k in 2:
			suppliers.append(_spawn("kangaroo", SUPPLY_AT + Vector3(-14.0 + 4.0 * k, 0.0, 16.0 + 3.0 * k), PI * 0.5))
		_pan(SUPPLY_AT + Vector3(0, 0, 6), 0.0, 1.5)
		controller.camera_rig._target_zoom = SUPPLY_ZOOM
	if _phase_at(1.0, "first"):
		commander.submit({"type": "move", "units": [suppliers[0].unit_id], "pos": SUPPLY_AT + SUPPLIER_STOPS[0], "attack": false})
	if _phase_at(5.0, "count1"):
		var fed := group.filter(func(u): return u.resupply > 0.0)
		print("KANGAROO supply: one kangaroo resupplies %s" % [fed.map(func(u): return u.type_id)])
		_check(fed.size() == 3, "supply: one kangaroo resupplies 3 of the 5 (%d)" % fed.size())
		_check(fed.all(func(u): return u.get("_supply_icon").visible), "supply: an ammo box over each of them")
		_check(not group[-1].get("_supply_icon").visible, "supply: none over the unit out of reach")
		for u in group:
			_cd_mark[u] = _cooldown(u)
	if _phase_at(6.0, "rate"):
		var fed: Array = group.filter(func(u): return u.resupply > 0.0)
		var out: Array = group.filter(func(u): return u.resupply == 0.0)
		var fast: float = _cd_mark[fed[0]] - _cooldown(fed[0])
		var slow: float = _cd_mark[out[0]] - _cooldown(out[0])
		print("KANGAROO supply: a second's cooldown: resupplied %.3f s, not %.3f s" % [fast, slow])
		_check(absf(fast - 1.0 / 0.85) < 0.05 and absf(slow - 1.0) < 0.05, "supply: cooldowns run 1/0.85 as fast (%.3f vs %.3f)" % [fast, slow])
		commander.submit({"type": "move", "units": [suppliers[1].unit_id], "pos": SUPPLY_AT + SUPPLIER_STOPS[1], "attack": false})
	if _phase_at(10.5, "count2"):
		var fed := group.filter(func(u): return u.resupply > 0.0)
		print("KANGAROO supply: two kangaroos resupply %s" % [fed.map(func(u): return u.type_id)])
		_check(fed.size() == 5, "supply: two kangaroos resupply all 5 in reach (%d)" % fed.size())
		_check(group.all(func(u): return u.resupply <= 0.15 + 1e-6), "supply: it never stacks (most %.2f)" % group.map(func(u): return u.resupply).max())
		_check(not suppliers.any(func(k): return k.resupply > 0.0), "supply: kangaroos with nothing cooling down aren't resupplied")


## The three shoot a rifleman out in front of the face: they rear their chests up to level the SMGs on
## it, and the guns on either side fire in turn.
func _smg_step() -> void:
	if _once("start"):
		_say("Side-mounted SMGs", "Short bursts, the two guns taking turns, the chest reared up onto the target")
		_pan(_centre(trio) + Vector3(0, 0, -4), 0.0, 1.2)
		controller.camera_rig._target_zoom = FIELD_ZOOM
		_guard(SMG_TARGET)
		_cd_mark[guards[-1]] = guards[-1].hp
		commander.submit({"type": "attack", "units": _ids(trio), "target": guards[-1].get_path()})
	var target: DefenderSoldier = guards[-1]
	if _phase_at(4.0, "check"):
		var u: AttackerUnit = trio[1]
		var right := u.global_basis.x
		var l := u.smg_muzzle(0) - u.global_position
		var r := u.smg_muzzle(1) - u.global_position
		print("KANGAROO smg: muzzles L %s R %s, rear-up %.0f deg" % [l.snapped(Vector3.ONE * 0.01), r.snapped(Vector3.ONE * 0.01), rad_to_deg(u.get("_rig").pitch)])
		_check(l.dot(right) < -0.25 and r.dot(right) > 0.25 and l.y > 0.8 and r.y > 0.8, "smg: one gun on either side of the chest")
		var d: Vector3 = Combat.aim_point(target) - u.call("_eye")
		var want := atan2(d.y, Vector2(d.x, d.z).length()) + KangarooRig.GUN_DROOP
		_check(absf(u.get("_rig").pitch - want) < deg_to_rad(4.0), "smg: rears its chest up to level the guns on the target (%.0f deg, %.0f wanted)" % [rad_to_deg(u.get("_rig").pitch), rad_to_deg(want)])
		_check(target.hp < _cd_mark[target], "smg: the rifleman is hit (%.0f -> %.0f)" % [_cd_mark[target], target.hp])


## The south gate falls; the three go in next to it and, inside, are on their own: they hunt the
## defenders up to the gun deck, throwing flash grenades at them.
func _storm_step() -> void:
	if _once("start"):
		_say("Storming the base", "Like Chimps and Rams they get inside, and there they fight on their own")
		gate.take_damage(gate.hp + 1.0, GameConfig.TEAM_ATTACKER)
		for p in INSIDE_GUARDS:
			_guard(p)
		for s in deck:
			s.process_mode = Node.PROCESS_MODE_INHERIT
			s.became_unavailable.connect(func(_x): s.set("_respawn_cd", 1e9))
		for u in trio:
			u.flash_cd = 0.0
			u.hp = 400.0  # staged: tougher, so the raid lasts
		_pan(gate.get_approach_point() + Vector3(0, 0, 10), 0.0, 1.5)
		controller.camera_rig._target_zoom = FIELD_ZOOM
	if _phase_at(1.5, "order"):
		controller._set_selection(trio.filter(func(u): return u.is_controllable()))
		controller._issue_order(_screen(gate.get_approach_point()), false)
	if test and int(_phase_t / 4.0) != int((_phase_t - get_process_delta_time()) / 4.0):
		for u in trio:
			var tg = u.target
			var desc := "-"
			if Combat.is_valid_target(tg):
				var to: Vector3 = tg.global_position - u.global_position
				desc = "%s %.1f m dy %.1f sees %s" % [tg.name, to.length(), to.y, u.call("_can_see", tg)]
			print("KANGAROO storm +%.0f %s at %s hp %.0f %s target %s flash %.0f" % [_phase_t, u.name, u.global_position.snapped(Vector3.ONE * 0.1),
					u.hp, "raiding" if u.raiding else u.order.type, desc, u.flash_cd])
	if _phase_at(14.0, "inside"):
		var raiders := trio.filter(func(u): return u.raiding)
		_check(raiders.size() == trio.size(), "storm: %d/%d went in and raid on their own" % [raiders.size(), trio.size()])
		_check(controller.selected.is_empty(), "storm: raiders drop out of the selection")
	if _phase_at(30.0, "check"):
		var up := trio.filter(func(u): return u.global_position.y > 6.0)
		print("KANGAROO storm: %d raid flashes, %d defenders blinded by them, %d up on the deck or roof" % [_raid_flashes, _raid_blinded.size(), up.size()])
		_check(_raid_flashes > 0, "storm: raiders throw flash grenades on their own (%d)" % _raid_flashes)
		_check(not _raid_blinded.is_empty(), "storm: their flashes blind defenders (%d)" % _raid_blinded.size())


func _guard(p: Vector3) -> void:
	var s := DefenderSoldier.new()
	s.model_path = LevelBuilder.DEFENDER_MODELS[guards.size() % LevelBuilder.DEFENDER_MODELS.size()]
	s.station_name = "Guard"
	s.name = "Guard_%d" % guards.size()
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else p
	var to := Vector3(-4.0, at.y, 82.0) - at
	s.transform = Transform3D(Basis.looking_at(to if to.length() > 1.0 else Vector3.BACK), at + Vector3.UP * 0.1)
	add_child(s)
	s.became_unavailable.connect(func(_st): s.set("_respawn_cd", 1e9))
	guards.append(s)


# ---------------------------------------------------------------- checks

## The cooldown of the unit's skill.
func _skill_cd(u: AttackerUnit) -> String:
	if u.has_cluster_bomb():
		return "cluster_cd"
	if u.has_smoke():
		return "smoke_cd"
	if u.has_bombard():
		return "bombard_cd"
	return "ram_cd"


func _cooldown(u: AttackerUnit) -> float:
	return u.get(_skill_cd(u))


func _check_spread(spots: Array[Vector3], spacing: float, target: Vector3) -> void:
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			_check(_flat(spots[i], spots[j]) >= spacing * 0.9, "flash: grenades %d and %d land %.1f m apart (>= %.1f)" % [i, j, _flat(spots[i], spots[j]), spacing * 0.9])
	var up := spots.filter(func(p): return absf(p.y - target.y) < 1.0).size()
	_check(up == spots.size(), "flash: %d/%d land up on the deck (y %.1f)" % [up, spots.size(), target.y])


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	for c in _checks:
		print("KANGAROO CHECK ", c)
	print("KANGAROO SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame])
		if _cutting:
			print("CUT frames %d-%d" % [_cut_from, _frame])
		print("VIDEO END frame %d" % _frame)
	get_tree().quit()


# ---------------------------------------------------------------- video

## Video: the camera for this moment (SHOTS, else the RTS view), slow motion, and the frames to speed
## up or leave out (only the frames the video keeps are drawn).
func _direct() -> void:
	var shot := "eyes" if phase == "screen" and defender != null else "rts"
	for sh in SHOTS:
		if _within(sh):
			shot = sh[3]
	if shot != _shot:
		_shot = shot
		_cursor.visible = shot == "rts"
		_keycap.visible = _keycap.visible and shot == "rts"
		controller.visible = shot == "rts"
		if shot == "rts":
			controller.camera_rig.camera.current = true
		elif shot != "eyes":
			cam.current = true
	if shot not in ["rts", "eyes"]:
		_place_cam(shot)
	var scale := 1.0
	for sl in SLOWMO:
		if _within(sl):
			scale = sl[3]
	Engine.time_scale = scale
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


## Where the video's camera is for `shot`, following the action.
func _place_cam(shot: String) -> void:
	var at := Vector3.ZERO
	var look := Vector3.ZERO
	match shot:
		"trio":
			var c := _centre(trio)
			at = c + Vector3(9.0 - _phase_t * 0.8, 2.6, 12.0)
			look = c + Vector3(0.0, 1.2, -2.0)
		"hop":
			# Beside it, then (slowed down) three quarters in front of it.
			var p := hopper.global_position
			var fwd := -hopper.global_basis.z
			var right := hopper.global_basis.x
			at = p + right * 8.5 - fwd * 1.5 + Vector3.UP * 1.5
			if _within(SLOWMO[0]):
				at = p + fwd * 5.5 + right * 4.5 + Vector3.UP * 1.3
			look = p + Vector3.UP
		"throw":
			var u: AttackerUnit = trio[1]
			at = u.global_position + Vector3(5.2, 1.7, -1.6)
			look = u.global_position + Vector3(0.0, 1.7, -0.8)
		"deck":
			at = Vector3(-24.0, 10.6, 74.0)
			look = Vector3(2.0, 8.6, 70.6)
		"smg":
			var u: AttackerUnit = trio[2]
			var fwd := -u.global_basis.z
			var right := fwd.cross(Vector3.UP).normalized()
			at = u.global_position + right * 3.8 + fwd * 2.6 + Vector3.UP * 1.4
			look = u.global_position + fwd * 1.6 + Vector3.UP * 1.3
		"tunnel":
			# Inside the gate tunnel, looking out at the broken gate.
			at = Vector3(-4.0, 2.2, 70.6)
			look = Vector3(-4.0, 1.2, 80.0)
		"ramp":
			# Up the ramp behind the first guard, looking down at the tunnel's end.
			at = Vector3(4.6, 4.5, 66.4)
			look = Vector3(-3.0, 1.2, 70.0)
		"hall":
			# The spawn hall, the second guard in front, the steps down from the ramp behind.
			at = Vector3(-6.0, 4.0, 58.0)
			look = Vector3(3.0, 1.2, 60.0)
		"stairs":
			# The foot of the stairs up to the gun deck, looking up the first flight.
			at = Vector3(5.5, 6.0, 65.5)
			look = Vector3(-1.0, 4.5, 65.0)
		"deck_east", "deck_west":
			# On the gun deck, in front of the stair door: east of it, then west.
			at = Vector3(11.0, 10.0, 66.5) if shot == "deck_east" else Vector3(-2.0, 10.0, 66.5)
			look = Vector3(5.0, 8.9, 67.5 if shot == "deck_east" else 68.0)
	cam.global_position = at
	cam.look_at(look)


## The south deck's posts, while the flashes and the storm go on: blinded or not.
func _update_status() -> void:
	_status.visible = phase in ["flash", "screen", "storm"]
	if not _status.visible:
		return
	var lines := []
	for n in [mg] + deck:
		lines.append("%s  %d / %d%s" % [n.station_name, int(n.hp), int(n.max_hp), "  BLINDED" if FlashGrenade.is_blind(n) else ""])
	_status.text = "\n".join(lines)


# ---------------------------------------------------------------- the player's hands

func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


func _ids(list: Array) -> Array:
	return list.map(func(u): return u.unit_id)


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
	return r.grow(48.0)


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


## Pans the view (as with WASD) to `to` between `start` and `end` (phase seconds).
func _pan(to: Vector3, start: float, end: float) -> void:
	_pan_from = controller.camera_rig.position
	_pan_to = to
	_pan_t = Vector2(start, end)


func _update_pan() -> void:
	var rig := controller.camera_rig
	var w := smoothstep(_pan_t.x, _pan_t.y, _phase_t) if _pan_t.y > _pan_t.x else 1.0
	var p := _pan_from.lerp(_pan_to, w)
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
	_status = UIKit.label("", 15, Color(1.0, 0.95, 0.75))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 120)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	layer.add_child(_status)
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
