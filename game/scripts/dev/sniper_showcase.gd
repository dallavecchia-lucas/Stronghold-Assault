extends Node3D
## Staged run of the Sniper on the real map, in the south field (media/sniper_showcase.mp4): her scope,
## her tags and her thermal sight as the defending player uses them (her own camera and HUD, this node
## working the keys and the mouse as her pilot), and her rounds and their tags as the attacking player
## sees them (the RTS view).
##
##   intro      she stands, the Eclipse Longshot shouldered, the ghillie cape over her (her Idle clip)
##   drive      a Sniper bought (K), the player takes her (F1) and walks her up, third person over her
##              shoulder
##   scope      RMB: the scope comes up to her eye, 8x; the wheel to 12x and back; LMB on a Bear Rifleman
##              74 m out: one round, and he drops; R reloads
##   tags       five rounds into five sturdy attackers (a lioness among them): each is tagged, the panel's
##              five slots fill; a sixth hit (a bison) tags nothing while all five are out and does 140; the
##              giraffe she tagged first takes a second round and dies, its tag is free again, and the bison
##              is tagged: it takes 20% more (168)
##   rts_tags   the RTS view: an aim icon over each tagged unit; the attacking player box-selects two
##              lionesses and presses F: the tagged one can't sneak, the other does (a bush over her)
##   thermal    the scope on the forest west of the lane, chimps in among its trees, unseen; T: the land
##              goes dark and cold, the trees see-through, the chimps white-hot; she tags two; 15 s on it
##              goes off, and T is refused while it recharges (a minute)
##   rts_trail  the RTS view from the side of her line of fire: each round's long tracer and the white trail
##              it leaves, hanging 1 s, then fading (one in slow motion)
##   idle       the player leaves her (takes a rifleman post): she holds her ground, passes over two chimps
##              in the forest east of the lane (closer, but in among the trees), picks a ram out in the open
##              and stays on it, even when a kangaroo comes closer, until it falls, tagging only it; then
##              the kangaroo
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/sniper_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie sniper.avi \
##       --fixed-fps 30 res://scenes/dev/sniper_showcase.tscn -- --video > sniper.log
##   python3 tools/video/cut_showcase.py sniper.avi sniper.log media/sniper_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times (seconds of the run).
## --test prints what she does and checks it at the end (SNIPER SHOWCASE PASS / FAIL).
## --video cuts in the cameras (round her standing, else her own view or the RTS view), plays the waits
## faster and one round in slow motion, printing the frames for tools/video/cut_showcase.py and drawing
## only the frames it keeps.
## The garrison's posts and the AA turrets hold fire; the attackers in the field are targets and don't
## fight back (they stand out of their reach).

## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "intro"], [5.0, "drive"], [10.0, "scope"], [21.0, "tags"], [37.0, "rts_tags"],
		[46.0, "thermal"], [67.0, "rts_trail"], [80.0, "idle"], [97.0, "outro"], [99.0, "end"]]
## She is bought into the field here and walked up to SNIPER_AT, looking south down the lane.
const SNIPER_START := Vector3(6.0, 0.0, 99.0)
const SNIPER_AT := Vector3(6.0, 0.0, 104.0)
const BEAR_AT := Vector3(6.0, 0.0, 178.0)
## The tag run: [unit type, where], in the order she shoots them; then the lioness she doesn't tag.
const TAG_RUN := [["giraffe", Vector3(-14.0, 0.0, 172.0)], ["breacher", Vector3(-4.0, 0.0, 176.0)],
		["hippo", Vector3(10.0, 0.0, 182.0)], ["lioness", Vector3(18.0, 0.0, 170.0)],
		["rhino", Vector3(-22.0, 0.0, 184.0)], ["bison_gun", Vector3(2.0, 0.0, 188.0)]]
const OTHER_LIONESS := Vector3(22.0, 0.0, 172.0)
## Chimps in among the trees of the forest west of the lane (LevelBuilder.FORESTS[1]).
const CHIMPS_WEST := [Vector3(-48.0, 0.0, 146.0), Vector3(-38.0, 0.0, 157.0), Vector3(-43.0, 0.0, 152.5)]
## Left alone: chimps in the forest east of the lane (closer to her than the ram), the ram in the open,
## and the kangaroo that comes up closer than the ram while she shoots it.
const CHIMPS_EAST := [Vector3(30.0, 0.0, 132.0), Vector3(33.0, 0.0, 138.0)]
const RAM_AT := Vector3(-8.0, 0.0, 150.0)
const KANGAROO_AT := Vector3(14.0, 0.0, 140.0)
## Video: cameras other than her own view, as [phase, from, to (phase seconds), shot].
const SHOTS := [["intro", 0.0, 5.0, "orbit"], ["rts_tags", 0.0, 99.0, "rts"], ["rts_trail", 0.0, 99.0, "rts"],
		["idle", 0.0, 99.0, "rts"], ["outro", 0.0, 99.0, "orbit"]]
## Slow motion: [phase, from, to, time scale].
const SLOWMO := [["rts_trail", 5.6, 6.3, 0.25]]
## Played faster: [phase, from, to, every k-th frame kept].
const FAST := [["thermal", 10.0, 17.6, 3], ["idle", 4.0, 14.0, 2]]
## Left out: [phase, from, to].
const CUTS := [["tags", 7.9, 9.0], ["thermal", 19.4, 21.0]]

var level: LevelBuilder
var commander: AttackerCommander
var controller: AttackerController
var defender: DefenderController
var armory: DefenderArmory
var sniper: Sniper
var cam: Camera3D
var t := -1.0
var phase := ""
var test := false
var video := false
var bear: AttackerUnit
var marks: Array = []
var lioness2: AttackerUnit
var chimps: Array = []
var ram: AttackerUnit
var kangaroo: AttackerUnit
var _phase_t := 0.0
var _steps := {}
var _checks: Array[String] = []
var _failed := false
var _marks := {}
var _trails: Array = []
## The pilot's hands on the keys and the mouse (pilot_input): the scope up, where to look, a click.
var _scope := false
var _look = null
var _look_rate := 1.2
var _walk_to = null
var _click := false
var _cursor: Control
var _cursor_from := Vector2.ZERO
var _cursor_to := Vector2.ZERO
var _cursor_t := Vector2.ZERO
var _caption: Label
var _keycap: Label
var _status: Label
## Video: names over what the RTS view is about (her, small and far off; the chimps under the trees).
var _her_name: Label
var _chimps_name: Label
var _key_t := 0.0
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
	GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
	level = LevelBuilder.new()
	add_child(level)
	level.build()
	# Staged: the Gunner Squad sits this one out, the posts and the AA turrets hold fire.
	for s in level.stations.filter(func(s): return s is GunnerSquad):
		level.stations.erase(s)
		s.queue_free()
	for s in level.stations + level.aa_turrets:
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
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
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# The baked navmesh reaches the navigation map some frames after the bake: wait for it.
	var map := get_world_3d().navigation_map
	while NavigationServer3D.map_get_closest_point(map, SNIPER_AT).distance_to(SNIPER_AT) > 2.0:
		await get_tree().physics_frame
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	controller.visible = false
	var rig := controller.camera_rig
	rig.edge_scroll = false
	# The keys' help on the RTS panel would cover the field: off for the showcase.
	for l in controller.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("LMB select"):
			l.visible = false
	armory = DefenderArmory.new()
	armory.level = level
	armory.credits = DefenderArmory.SNIPER_COST
	add_child(armory)
	defender = DefenderController.new()
	defender.level = level
	defender.armory = armory
	add_child(defender)
	defender.visible = false
	sniper = defender.buy_squad("sniper") as Sniper
	_check(sniper != null and armory.squads == [sniper] and sniper.troopers.size() == 1 and sniper.max_hp == SniperTrooper.MAX_HP,
			"buy: K buys a Sniper for %d credits: one marksman on the roster" % DefenderArmory.SNIPER_COST)
	sniper.pilot = self
	await get_tree().physics_frame
	_place_sniper(SNIPER_START, SNIPER_AT + Vector3(0.0, 0.0, 10.0))
	cam.current = true
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))


func _spawn(type_id: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = at + Vector3.UP * 0.2
	u.rotation.y = atan2(at.x - SNIPER_AT.x, at.z - SNIPER_AT.z)  # facing her
	return u


## Puts her down at `at`, facing `face` (between shots).
func _place_sniper(at: Vector3, face: Vector3) -> void:
	var it := sniper.leader
	it.global_position = at + Vector3.UP * 0.1
	it.velocity = Vector3.ZERO
	var d := face - at
	it.rotation.y = atan2(-d.x, -d.z)
	sniper.heading = it.rotation.y
	sniper.cam_yaw = it.rotation.y
	sniper.cam_pitch = deg_to_rad(-6.0)
	sniper.hold_at = it.global_position


## Units off the field once their part is played (fewer to draw).
func _retire(list: Array) -> void:
	for u in list:
		if not is_instance_valid(u):
			continue
		commander.units.erase(u.unit_id)
		u.queue_free()


# ---------------------------------------------------------------- the pilot

## Her keys and mouse, as a player works them: the scope up (RMB), turning to look at `_look`, walking for
## `_walk_to`, a click (LMB) for one frame.
func pilot_input(s: DefenderSquad, delta: float) -> void:
	s.input.move = Vector2.ZERO
	s.input.aim = _scope
	s.input.hustle = false
	s.input.fire = _click
	_click = false
	if _walk_to != null:
		var d: Vector3 = _walk_to - s.leader.global_position
		d.y = 0.0
		if d.length() > 0.4:
			var local := Basis(Vector3.UP, -s.cam_yaw) * d.normalized()
			s.input.move = Vector2(local.x, local.z) * clampf(d.length() / 2.0, 0.35, 1.0)
		else:
			_walk_to = null
	if _look != null:
		s.look_toward(_look, _look_rate, delta)


## Looks through the scope at `u` (its middle).
func _aim_at(u, rate := 1.2) -> void:
	if not is_instance_valid(u):
		return
	_look = Combat.aim_point(u)
	_look_rate = rate


## The scope is up and dead on what she looks at.
func _on_target() -> bool:
	if _look == null or not sniper.scope_view():
		return false
	var c := sniper.get_camera()
	return (-c.global_basis.z).angle_to(_look - c.global_position) < deg_to_rad(0.15)


## LMB once she is on target and a round is chambered (at `at` phase seconds, or as soon after as that is).
func _fire_at(at: float, step: String) -> bool:
	if _phase_t < at or _steps.has(step):
		return false
	if not _on_target() or not (sniper.leader as SniperTrooper).ready_to_fire():
		return false
	_steps[step] = true
	_click = true
	if _shot != "rts":
		_key("LMB")
	return true


# ---------------------------------------------------------------- the run

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
		print("SNIPER t=%.1f phase %s" % [t, phase])
		if phase == "end":
			_finish()
			return
	_phase_t += delta
	_key_t = maxf(_key_t - delta, 0.0)
	_keycap.visible = _key_t > 0.0
	_trails = _trails.filter(func(s): return is_instance_valid(s))
	for n in get_tree().current_scene.get_children():
		if n is SniperTrail and not n in _trails:
			_trails.append(n)
	match phase:
		"intro":
			_say("Sniper", "One marksman, not a squad: the Grey Veil Warden and her Eclipse Longshot")
		"drive":
			_drive_step()
		"scope":
			_scope_step()
		"tags":
			_tags_step()
		"rts_tags":
			_rts_tags_step()
		"thermal":
			_thermal_step()
		"rts_trail":
			_trail_step()
		"idle":
			_idle_step()
		"outro":
			_say("Sniper", "Scope · tags · thermal vision · she holds where you leave her")
	_update_cursor()
	_update_status()
	if video:
		_direct()
		_update_names()
	elif phase in ["intro", "outro"]:
		_place_cam("orbit")
	if not _snaps.is_empty():
		_snap()


## The player takes her (F1) and walks her up, third person over her shoulder.
func _drive_step() -> void:
	if _once("take"):
		defender.select_squad(0, true)
		_check(defender.current == sniper and sniper.get_camera().current, "drive: F1 takes command of her: her own camera")
		# The field fills once she is the player's (left to herself she would pick them off).
		bear = _spawn("rifleman", BEAR_AT)
		for k in TAG_RUN.size():
			marks.append(_spawn(TAG_RUN[k][0], TAG_RUN[k][1]))
		lioness2 = _spawn("lioness", OTHER_LIONESS)
		_say("K · Sniper  (220 credits)", "On the roster like a squad · third person over her shoulder")
		_key("F1")
		_walk_to = SNIPER_AT
		_look = SNIPER_AT + Vector3(-2.0, 1.6, 40.0)
		_look_rate = 0.8
	if _phase_at(4.6, "there"):
		var it := sniper.leader
		_check(_flat(it.global_position, SNIPER_AT) < 1.0, "drive: WASD walks her up (%.1f m off the spot)" % _flat(it.global_position, SNIPER_AT))
		_check(sniper.get_camera().fov > 40.0 and not sniper.scope_view(), "drive: no scope up: the third-person view")


## RMB: the scope; the wheel; LMB on a Bear Rifleman; R.
func _scope_step() -> void:
	var c := sniper.get_camera()
	if _once("look"):
		_aim_at(bear, 0.9)
		_say("RMB · The scope", "")
	if _phase_at(0.8, "rmb"):
		_scope = true
		_key("RMB")
	if _phase_at(1.4, "up"):
		var mask_ok := c.cull_mask & SniperTrooper.BODY_LAYER == 0
		_check(sniper.scope_view() and absf(c.fov - sniper.scope_fov()) < 0.05 and absf(sniper.scope_fov() - 8.95) < 0.1,
				"scope: RMB brings the scope to her eye in %.2f s: %.1f deg, 8x" % [Sniper.SCOPE_IN, c.fov])
		_check(mask_ok and c.global_position.distance_to((sniper.leader as SniperTrooper).eye_point()) < 0.01,
				"scope: first person from her eye behind the scope, her own body left out of the view")
		_check(not defender.get("_crosshair").visible, "scope: the scope's reticle, not the crosshair")
		_say("RMB · The scope: first person, 8x", "The wheel steps through 4x · 8x · 12x")
	if _phase_at(2.6, "wheel_up"):
		sniper.set_zoom(2)
		_key("WHEEL")
	if _phase_at(3.6, "zoomed"):
		_check(absf(c.fov - sniper.scope_fov()) < 0.05 and absf(sniper.scope_fov() - 6.0) < 0.1, "scope: wheel up: 12x (%.1f deg)" % c.fov)
	if _phase_at(4.2, "wheel_down"):
		sniper.set_zoom(1)
		_key("WHEEL")
		_marks.bear_hp = bear.hp
	if _fire_at(4.8, "fire"):
		_say("LMB · One round: 140 damage", "Then she works the bolt · five rounds a magazine")
		_marks.fired_at = _phase_t
	if _phase_at(5.6, "dropped"):
		_check(_steps.has("fire") and not bear.is_alive(), "scope: LMB through the scope: the round goes where the reticle is, the bear drops (%d hp)" % _marks.get("bear_hp", 0))
		_check(not _trails.is_empty(), "scope: the round leaves its tracer and trail")
		_check((sniper.leader as SniperTrooper).ammo == SniperTrooper.MAG - 1, "scope: four rounds left in the magazine")
	if _phase_at(7.0, "reload"):
		(sniper.leader as SniperTrooper).reload()
		_key("R")
		_say("R · Reload", "")
	if _phase_at(10.4, "reloaded"):
		_check((sniper.leader as SniperTrooper).ammo == SniperTrooper.MAG, "scope: R: a fresh magazine in %.1f s" % SniperTrooper.RELOAD_TIME)


## Five tags; a sixth hit tags nothing; one dies, a tag is free, the sixth is tagged.
func _tags_step() -> void:
	var it := sniper.leader as SniperTrooper
	if _once("start"):
		_say("Every attacker she hits is tagged for 20 s", "Up to five at a time: the panel's slots")
		_aim_at(marks[0])
	var times := [1.0, 2.6, 4.2, 5.8, 7.4]
	for k in 5:
		_fire_at(times[k], "tag%d" % k)
		if _phase_at(times[k] + 0.15, "check%d" % k):
			_check(marks[k].tag_left(sniper) > Sniper.TAG_TIME - 0.5 and sniper.tagged().size() == k + 1,
					"tags: %s hit: tagged for 20 s (%d/5)" % [marks[k].stats.name, sniper.tagged().size()])
			_check(marks[k].get("_tag_icon").visible, "tags: an aim icon over the %s" % marks[k].stats.name)
			if k < 4:
				_aim_at(marks[k + 1])
	if _phase_at(7.6, "all_out"):
		_say("All five tags out", "A sixth hit tags nothing, until one of hers dies or runs out")
		_check(it.reloading(), "tags: five rounds, the magazine is empty: she reloads")
		_aim_at(marks[5])
		_marks.bison_hp = marks[5].hp
	if _fire_at(10.2, "sixth"):
		pass
	if _phase_at(10.4, "sixth_check"):
		var bison: AttackerUnit = marks[5]
		_check(_steps.has("sixth") and not bison.is_tagged() and sniper.stats.untagged == 1 and sniper.tagged().size() == 5,
				"tags: a sixth unit hit with all five out: no tag (%d/5)" % sniper.tagged().size())
		_check(is_equal_approx(_marks.bison_hp - bison.hp, Sniper.DAMAGE), "tags: untagged, it takes the round's 140 (%.0f)" % (_marks.bison_hp - bison.hp))
		_marks.bison_hp = bison.hp
		_say("The giraffe she tagged first: a second round", "Tagged, it takes 20% more, and dies: its tag is free again")
		_aim_at(marks[0])
	if _fire_at(11.9, "giraffe"):
		pass
	if _phase_at(12.1, "giraffe_check"):
		_check(not marks[0].is_alive() and sniper.tagged().size() == 4, "tags: the giraffe dies: four tags out (%d/5)" % sniper.tagged().size())
		_aim_at(marks[5])
	if _fire_at(13.6, "bison"):
		pass
	if _phase_at(13.8, "bison_check"):
		var bison: AttackerUnit = marks[5]
		_check(bison.is_tagged() and sniper.tagged().size() == 5, "tags: then the bison is tagged (%d/5)" % sniper.tagged().size())
		# The round that tags it lands before the tag: the next one, and every defender's, hits 20% harder.
		_check(is_equal_approx(_marks.bison_hp - bison.hp, Sniper.DAMAGE), "tags: the round that tags it does 140 (%.0f)" % (_marks.bison_hp - bison.hp))
		var before := bison.hp
		bison.take_damage(50.0, GameConfig.TEAM_DEFENDER)
		_check(is_equal_approx(before - bison.hp, 60.0), "tags: tagged, it takes 20%% more from any defender (50 -> %.0f)" % (before - bison.hp))
		_marks.bison_hp = bison.hp
		_say("Tagged: defenders hit it 20% harder", "")
	if _phase_at(14.6, "refresh"):
		# Hit again, a tag she has out starts its 20 s over.
		var u: AttackerUnit = marks[1]
		_check(u.tag_left(sniper) < Sniper.TAG_TIME - 9.0, "tags: the ram's tag is running down (%.1f s left)" % u.tag_left(sniper))
		sniper.tag(u)
		_check(u.tag_left(sniper) > Sniper.TAG_TIME - 0.1 and sniper.tagged().size() == 5, "tags: hit again, its 20 s start over")


## The RTS view: the aim icons; two lionesses, F: the tagged one can't sneak.
func _rts_tags_step() -> void:
	var rig := controller.camera_rig
	var lioness: AttackerUnit = marks[3]
	if _once("start"):
		_scope = false
		GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
		rig.rotation.y = 0.0  # looking north, past the tagged units at the stronghold
		rig.pitch = deg_to_rad(-52.0)
		rig.focus(Vector3(-1.0, 0.0, 186.0))
		rig.zoom = 36.0
		rig._target_zoom = 36.0
		controller._set_selection([])
		_say("RTS view · Tagged: an aim icon over the unit", "The attacker sees it as the defender does")
		var shown := marks.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.is_tagged())
		_check(shown.size() == 5 and shown.all(func(u): return u.get("_tag_icon").visible), "rts: the five tagged units' aim icons show on the attacker's side too")
		_check(not lioness2.is_tagged() and not lioness2.get("_tag_icon").visible, "rts: no icon over the lioness she didn't tag")
	if _phase_at(3.2, "select"):
		_say("A tagged lioness can't sneak", "Two lionesses, F: only the one not tagged sneaks")
		_move_cursor(_group_rect([lioness, lioness2]).position, 3.2, 3.8)
	if _phase_at(3.9, "press"):
		_mouse(MOUSE_BUTTON_LEFT, true)
	if _phase_t > 3.9 and _phase_t < 4.5:
		_move_cursor(_group_rect([lioness, lioness2]).end, 3.9, 4.5)
		_mouse_motion()
	if _phase_at(4.5, "release"):
		_mouse(MOUSE_BUTTON_LEFT, false)
		_check(controller.selected.size() == 2, "rts: the two lionesses box-selected (%d)" % controller.selected.size())
	if _phase_at(5.2, "f"):
		_key_rts(AttackerController.CLUSTER_KEY)
		_key("F")
		_check(not lioness.is_sneaking() and not lioness.sneak_ready() and lioness.sneak_cd <= 0.0,
				"rts: F: the tagged lioness doesn't sneak (her sneak is ready otherwise)")
		_check(lioness2.is_sneaking(), "rts: F: the other one sneaks")
	if _phase_at(5.6, "panel"):
		_check(lioness2.get("_bush").visible and not lioness.get("_bush").visible, "rts: a bush over the one sneaking only")
		var text: String = controller.get("_selection_label").text
		_check(text.contains("1 tagged: can't sneak") and text.contains("Tagged by a sniper 1"), "rts: the panel says why: %s" % text.replace("\n", " | "))


## The scope on the forest: nothing; T: thermal vision; two chimps tagged; it runs out and recharges.
func _thermal_step() -> void:
	var it := sniper.leader as SniperTrooper
	var thermal: SniperThermal = sniper.get("_thermal")
	if _once("start"):
		controller._set_selection([])
		GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
		# Tagged while she sneaks (all five of the Sniper's tags are out: another tagger's), the sneak is over.
		var sneaking := lioness2.is_sneaking()
		lioness2.tag(self, 5.0)
		_check(sneaking and not lioness2.is_sneaking() and lioness2.is_tagged(), "tags: a lioness tagged while she sneaks shows again: the sneak is over")
		_retire([lioness2])
		for p in CHIMPS_WEST:
			chimps.append(_spawn("chimp", p))
		_scope = true
		_look = Vector3(-43.0, 1.4, 152.0)
		_look_rate = 1.0
		_say("Chimps in the forest west of the lane", "In among the trunks and the leaves: hard to make out")
		for c in chimps:
			_check(LevelBuilder.in_forest(c.global_position), "thermal: a chimp in among the forest's trees (%s)" % c.global_position.snapped(Vector3.ONE * 0.1))
	if _phase_at(3.0, "t"):
		_check(sniper.toggle_thermal(), "thermal: T switches it on")
		_key("T")
		_say("T · Thermal vision: the attackers glow white-hot", "The trees turn see-through: 15 s of it, then a minute to recharge")
	if _phase_at(3.3, "on"):
		var c := sniper.get_camera()
		_check(thermal.showing() and c.environment != null and c.environment.adjustment_saturation == 0.0,
				"thermal: her view goes thermal (grey through the sight's palette)")
		var hot: Material = thermal.get("_hot")
		_check(chimps.all(func(u): return u.model_meshes().all(func(mi): return mi.material_override == hot)), "thermal: every attacker glows white-hot")
		var trees := ForestTree.standing.filter(func(tr): return tr.grove == 1)
		var see := trees.filter(func(tr): return tr.find_children("*", "MeshInstance3D", true, false).all(
				func(mi): return mi.material_override == thermal.get("_foliage")))
		_check(not trees.is_empty() and see.size() == trees.size(), "thermal: the forest's trees turn see-through (%d/%d)" % [see.size(), trees.size()])
		_aim_at(chimps[2], 0.8)
	if _fire_at(5.0, "chimp1"):
		pass
	if _phase_at(5.3, "chimp1_check"):
		_check(chimps[2].is_tagged(), "thermal: a chimp in the forest, hit and tagged")
		_aim_at(chimps[0], 0.8)
	if _fire_at(6.8, "chimp2"):
		pass
	if _phase_at(7.1, "chimp2_check"):
		_check(chimps[0].is_tagged(), "thermal: and another")
		_look = Vector3(-43.0, 1.4, 152.0)
	if _phase_at(9.0, "running"):
		_check(absf(sniper.thermal_left - (Sniper.THERMAL_TIME - 6.0)) < 0.1, "thermal: running down (%.1f s left)" % sniper.thermal_left)
	if _phase_at(18.2, "off"):
		var c := sniper.get_camera()
		_check(sniper.thermal_left == 0.0 and absf(sniper.thermal_cd - (Sniper.THERMAL_RECHARGE - 0.2)) < 0.1, "thermal: off after 15 s, recharging (%.1f s)" % sniper.thermal_cd)
		_check(not thermal.showing() and c.environment == null, "thermal: her view as ever")
		_check(chimps.all(func(u): return u.model_meshes().all(func(mi): return mi.material_override == null)), "thermal: the attackers as ever")
		var trees := ForestTree.standing.filter(func(tr): return tr.grove == 1)
		_check(trees.all(func(tr): return tr.find_children("*", "MeshInstance3D", true, false).all(func(mi): return mi.material_override == null)),
				"thermal: the trees as ever")
		_say("Thermal off: a minute to recharge", "")
	if _phase_at(18.8, "refused"):
		_check(not sniper.toggle_thermal() and sniper.thermal_left == 0.0, "thermal: T while it recharges: refused")
		_key("T")


## The RTS view from the side of her line of fire: the tracers and the white trails.
func _trail_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_retire(chimps)
		GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
		rig.rotation.y = PI * 0.5  # looking west across her line of fire
		rig.pitch = deg_to_rad(-42.0)
		rig.focus(Vector3(10.0, 0.0, 142.0))
		rig.zoom = 50.0
		rig._target_zoom = 50.0
		_say("RTS view · Her rounds", "A long tracer, and a white trail that hangs 1 s, then fades")
		_aim_at(marks[2])
	_fire_at(1.5, "one")
	if _steps.has("one") and not _marks.has("trail"):
		for tr in _trails:
			if tr.age < 0.1:
				_marks.trail = tr
				_marks.length = tr.from.distance_to(tr.to)
	# The trail's own clock: `held` counts from the moment it is whole (the tracer home).
	if _marks.has("trail"):
		var s = _marks.trail
		if is_instance_valid(s):
			_marks.last_held = s.held
			if s.held < 0.0:
				_marks.flight = s.age
			if s.held > 0.9 and _once("held"):
				_check(is_equal_approx(s.get("_trail_mat").albedo_color.a, SniperTrail.TRAIL_ALPHA),
						"trail: the white trail hangs whole along its path for 1 s (%.0f m, the tracer home in %.2f s)" % [_marks.length, _marks.get("flight", 0.0)])
			if s.held > 1.3 and _once("fading"):
				_check(s.get("_trail_mat").albedo_color.a < SniperTrail.TRAIL_ALPHA * 0.6, "trail: then it fades")
		elif _once("gone"):
			_check(_marks.get("last_held", 0.0) >= SniperTrail.HOLD + SniperTrail.FADE - 0.05,
					"trail: and is gone %.1f s after the round landed" % (SniperTrail.HOLD + SniperTrail.FADE))
	if _phase_at(4.0, "two_look"):
		_aim_at(marks[4])
	if _fire_at(5.6, "two"):
		_say("In slow motion", "")
	if _phase_at(7.6, "three_look"):
		_say("RTS view · Her rounds", "A long tracer, and a white trail that hangs 1 s, then fades")
		_aim_at(marks[1])
	if _fire_at(9.0, "three"):
		pass


## The player leaves her: she holds her ground and picks one target outside the forests, and stays on it.
func _idle_step() -> void:
	var rig := controller.camera_rig
	if _once("start"):
		_scope = false
		_retire(marks + [bear])
		for p in CHIMPS_EAST:
			chimps.append(_spawn("chimp", p))
		chimps = chimps.filter(func(c): return is_instance_valid(c))
		ram = _spawn("breacher", RAM_AT)
		var post := level.stations.find_custom(func(s): return s is DefenderSoldier)
		defender.select_station(post, true)
		_shot = ""  # the rifleman's camera took the screen: the video's shot goes back on
		_check(not sniper.possessed and sniper.hold_at.distance_to(sniper.leader.global_position) < 0.01, "idle: the player takes a rifleman: she holds where she was left")
		rig.rotation.y = 0.0  # from the south: her far side, the ram near, the forest east of the lane right
		rig.pitch = deg_to_rad(-55.0)
		rig.focus(Vector3(6.0, 0.0, 131.5))
		rig.zoom = 72.0
		rig._target_zoom = 72.0
		_say("Left alone · She holds where you left her", "One target at a time, never one in among a forest's trees")
		_marks.hold = sniper.hold_at
	if _phase_at(1.5, "picked"):
		var nearest_chimp: float = chimps.map(func(c): return _flat(c.global_position, SNIPER_AT)).min()
		_check(sniper.target == ram, "idle: she picks the ram out in the open (%.0f m), not the chimps in the forest (%.0f m, closer)" % [_flat(RAM_AT, SNIPER_AT), nearest_chimp])
	if _phase_at(3.0, "kangaroo"):
		kangaroo = _spawn("kangaroo", KANGAROO_AT)
		_say("She stays on her pick until it falls", "Even with another closer: she tags only it")
	if ram and _phase_t > 3.5 and ram.is_alive():
		if sniper.target != ram:
			_marks.switched = true
		if sniper.tagged().any(func(u): return u != ram):
			_marks.other_tag = true
	if ram and not ram.is_alive() and _once("ram_down"):
		_marks.ram_down = _phase_t
		print("SNIPER idle: the ram fell at %.1f s, %d rounds, %d hits" % [_phase_t, sniper.stats.rounds, sniper.stats.hits])
		_check(not _marks.has("switched"), "idle: she stayed on the ram, the kangaroo closer, until it fell")
		_check(not _marks.has("other_tag") and not kangaroo.is_tagged() and chimps.all(func(c): return not c.is_tagged()), "idle: she tagged only the ram")
	if _marks.has("ram_down") and _phase_t > _marks.ram_down + 0.7 and _once("next"):
		_check(sniper.target == kangaroo, "idle: then she picks the kangaroo")
	if _phase_at(16.5, "end_check"):
		_check(_marks.has("ram_down"), "idle: the ram fell")
		_check(not is_instance_valid(kangaroo) or not kangaroo.is_alive(), "idle: and the kangaroo")
		_check(sniper.leader.global_position.distance_to(_marks.hold) < 0.8, "idle: all the while she held her ground (%.2f m off)" % sniper.leader.global_position.distance_to(_marks.hold))


## The two lionesses' state on the right while the attacking player tries their sneak (the RTS panel's
## own lines run off the edge of a 720p frame).
func _update_status() -> void:
	_status.visible = phase == "rts_tags" and is_instance_valid(lioness2) and is_instance_valid(marks[3])
	if not _status.visible:
		return
	var lines := []
	for pair in [["Left lioness", marks[3]], ["Right lioness", lioness2]]:
		var u: AttackerUnit = pair[1]
		var state := "sneak ready [F]"
		if u.is_tagged():
			state = "tagged %ds · can't sneak" % ceili(u.tag_left(sniper))
		elif u.is_sneaking():
			state = "sneaking %ds" % ceili(u.sneak_left())
		lines.append("%s  ·  %s" % [pair[0], state])
	_status.text = "\n".join(lines)


## Video, the RTS view: her name over her, and over the chimps the forest hides while she is left alone.
func _update_names() -> void:
	var rts := _shot == "rts" and sniper.leader != null
	_name_over(_her_name, sniper.leader.global_position + Vector3.UP * 2.4 if rts and phase in ["rts_trail", "idle"] else null)
	var hidden := chimps.filter(func(c): return is_instance_valid(c) and c.is_alive())
	var over = null
	if rts and phase == "idle" and not hidden.is_empty():
		over = Vector3.ZERO
		for c in hidden:
			over += c.global_position / hidden.size()
		over += Vector3.UP * 2.0
	_name_over(_chimps_name, over)


func _name_over(l: Label, at) -> void:
	l.visible = at != null and controller.camera_rig.camera.is_position_in_frustum(at)
	if l.visible:
		l.reset_size()
		l.position = _screen(at) - Vector2(l.size.x * 0.5, l.size.y)


# ---------------------------------------------------------------- checks

func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok
	if test:
		print("SNIPER CHECK ", ("ok    " if ok else "FAIL  ") + what)


func _finish() -> void:
	print("SNIPER stats %s" % [sniper.stats])
	for c in _checks:
		print("SNIPER CHECK ", c)
	print("SNIPER SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		if _fast > 1:
			print("FAST %d frames %d-%d" % [_fast, _fast_from, _frame])
		if _cutting:
			print("CUT frames %d-%d" % [_cut_from, _frame])
		print("VIDEO END frame %d" % _frame)
	get_tree().quit(1 if _failed and test else 0)


func _once(step: String) -> bool:
	if _steps.has(step):
		return false
	_steps[step] = true
	return true


func _phase_at(at: float, step: String) -> bool:
	return _phase_t >= at and _once(step)


# ---------------------------------------------------------------- video

## Video: the camera for this moment (SHOTS, else her own view), slow motion, and the frames to speed up
## or leave out (only the frames the video keeps are drawn).
func _direct() -> void:
	var shot := "def"
	for sh in SHOTS:
		if _within(sh):
			shot = sh[3]
	if shot != _shot:
		_shot = shot
		_show(shot)
	if shot == "orbit":
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


## Which view is on screen: "def" (her own camera and the defender's HUD), "rts" (the attacker's camera
## and HUD) or "orbit" (a camera round her, no HUD).
func _show(shot: String) -> void:
	defender.visible = shot == "def"
	sniper.set_hud_visible(shot == "def")
	controller.visible = shot == "rts"
	_cursor.visible = shot == "rts"
	for b in level.bases:
		b.get("_label").visible = shot == "rts"
	match shot:
		"def":
			sniper.get_camera().current = true
		"rts":
			controller.camera_rig.camera.current = true
		"orbit":
			cam.current = true


func _within(r: Array) -> bool:
	return r[0] == phase and _phase_t >= r[1] and _phase_t < r[2]


## Where the video's camera is for `shot`, following her: round her from her front-left to her left side
## (the intro), or on her right (the outro), a little above her rifle.
func _place_cam(shot: String) -> void:
	if shot != "orbit" or sniper.leader == null:
		return
	var it := sniper.leader
	var p := it.global_position
	var fwd := -it.global_basis.z
	var left := Vector3.UP.cross(fwd).normalized()
	var a := lerpf(0.55, 1.35, _phase_t / 5.0) if phase == "intro" else lerpf(-0.6, -0.95, _phase_t / 2.0)
	cam.global_position = p + (fwd * cos(a) + left * sin(a)) * 3.1 + Vector3.UP * 1.65
	cam.look_at(p + Vector3.UP * 1.25 + fwd * 0.3)


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.05
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [_snap_out, at])
		print("snap %.1f (%s)" % [at, phase])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- the attacking player's hands

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
	_cursor.position = pos


func _key_rts(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	controller._unhandled_input(ev)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
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


func _key(text: String) -> void:
	_keycap.text = text
	_key_t = 1.4


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
	_keycap.position = Vector2(40, 400)  # under the posts panel
	_keycap.visible = false
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_keycap)
	_status = UIKit.label("", 17, Color(1.0, 0.95, 0.75))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector2(_status.position.x - 16, 130)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	layer.add_child(_status)
	_her_name = _name_label("SNIPER", layer)
	_chimps_name = _name_label("2 chimps under the trees", layer)
	# Movie Maker doesn't record the system cursor: draw one (the RTS view's).
	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
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


func _name_label(text: String, layer: CanvasLayer) -> Label:
	var l := UIKit.label(text, 17, Color(0.8, 0.92, 1.0))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	layer.add_child(l)
	return l


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
