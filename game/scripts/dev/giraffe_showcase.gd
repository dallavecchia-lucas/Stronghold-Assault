extends Node3D
## Staged checks of the Giraffe (the Savanna Signal Scout), the fog of war and the ping, on the real
## map in the south field, from the attacker's side:
##
##   walk      a giraffe walks up from the west (its Walk clip); a Flame Trooper stands 25 m from a
##             Bear Rifleman whose sight is cut to 15 m, in the fog of war: it isn't drawn, the
##             rifleman leaves it alone though it is in range, and an order to attack it is refused
##   spot      the giraffe comes within its sight (the furthest of any unit): the trooper shows and
##             the rifleman shoots it (the army sees what any of it sees)
##   ping      three riflemen next to an infiltrator out of camo leave her alone (low profile); the
##             giraffe pings (it stands, its Ping clip): the pulse marks her and an infiltrator under
##             camo with red blurs, not a Flame Trooper beyond its reach; the blurs stay where they
##             were marked when the camo'd one walks off; she is revealed (the one under camo isn't)
##             and the riflemen go after her on their own
##   camo      she puts the camo on: revealed no more, they lose her
##   fogback   pinged again and revealed, she slips into the fog of war: her low profile is back
##   radar     the radar icon over a revealed infiltrator shows on the defender's side only
##   break     an Infiltrator Squad under camo looses arrows: the first one breaks the camo
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/giraffe_showcase.tscn -- --test
##   godot --path game --fixed-fps 30 res://scenes/dev/giraffe_showcase.tscn   # to watch it
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times.
## --video prints the frames to keep for tools/video/cut_showcase.py (the squad's camera in the
## mountain is cut) and frames the field closer:
##
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie giraffe.avi \
##       --fixed-fps 30 res://scenes/dev/giraffe_showcase.tscn -- --video > giraffe.log
##   python3 tools/video/cut_showcase.py giraffe.avi giraffe.log media/giraffe_showcase.mp4
## --test prints what happens and checks it at the end (GIRAFFE SHOWCASE PASS / FAIL). The garrison's
## posts and the AA turrets hold fire.

const Z := 118.0
const GIRAFFE_FROM := Vector3(-80.0, 0.0, Z)
const GIRAFFE_WAIT := Vector3(-62.0, 0.0, Z)
const GIRAFFE_SPOT := Vector3(-30.0, 0.0, Z)
const SPOTTER_AT := Vector3(0.0, 0.0, Z)
const TROOPER_AT := Vector3(25.0, 0.0, Z)
const RIFLE_AT := Vector3(-5.0, 0.0, Z)
const OPEN_AT := Vector3(18.0, 0.0, Z - 5.0)
const CAMO_AT := Vector3(20.0, 0.0, Z + 6.0)
const FAR_AT := Vector3(42.0, 0.0, Z)
## Out of everyone's sight (the east helipad's too).
const FOG_AT := Vector3(75.0, 0.0, 98.0)
const PHASES := ["walk", "spot", "ping", "camo", "fogback", "radar", "break", "end"]
const TIMEOUT := {"walk": 7.0, "spot": 10.0, "ping": 6.5, "camo": 2.5, "fogback": 4.0, "radar": 0.5, "break": 12.0}


## Holds the trigger down for the squad (DefenderSquad.pilot).
class Trigger:
	func pilot_input(squad: DefenderSquad, _delta: float) -> void:
		squad.input.move = Vector2.ZERO
		squad.input.fire = true
		squad.input.aim = false
		squad.input.hustle = false


var level: LevelBuilder
var commander: AttackerCommander
var vision: AttackerVision
var cam: Camera3D
var giraffe: AttackerUnit
var spotter: AttackerUnit
var riflemen: Array = []
var fogged: FlameTrooper
var open: InfiltratorTrooper
var camod: InfiltratorTrooper
var far: FlameTrooper
var squad: InfiltratorSquad
var test := false
var video := false
var _frame := -1
var phase := ""
var t := -1.0
var _phase_t := 0.0
var _checks: Array[String] = []
var _failed := false
var _flags := {}
## Ping: who it marked and where, the blurs it left, and the clips seen.
var _marks := {}
var _blurs: Array = []
var _clips := {}
var _hp_at := 0.0
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false


func _ready() -> void:
	seed(5)
	test = "--test" in OS.get_cmdline_user_args()
	video = "--video" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			_snaps = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--snap-out="):
			_snap_out = arg.get_slice("=", 1)
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
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
	vision = AttackerVision.new()
	vision.commander = commander
	vision.hide_enemies = true
	add_child(vision)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	var fog := FogOverlay.new()
	fog.vision = vision
	cam.add_child(fog)
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# The navmesh's first iteration lands a few frames after the bake.
	for k in 10:
		await get_tree().physics_frame
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))
	_enter("walk")


func _log(text: String) -> void:
	print("GIRAFFE t=%.1f %s" % [t, text])


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
	_log(("check ok: " if ok else "CHECK FAILED: ") + what)


func _unit(type_id: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type_id, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = at + Vector3.UP * 0.2
	return u


func _trooper(t_: SquadTrooper, at: Vector3, face: Vector3) -> void:
	add_child(t_)
	t_.global_position = at + Vector3.UP * 0.1
	t_.aim_point = face
	t_.following = true
	t_.goal = at


func _physics_process(delta: float) -> void:
	if t < 0.0 or phase == "end":
		return
	t += delta
	_phase_t += delta
	_camera()
	if giraffe and giraffe._anim:
		_clips[giraffe._anim.current_animation] = true
	if phase == "ping" and giraffe.is_pinging():
		_flags.stood = _flags.get("stood", true) and Vector2(giraffe.velocity.x, giraffe.velocity.z).length() < 0.3
	if _phase_t >= TIMEOUT.get(phase, 0.0) or _done():
		_leave(phase)
		_enter(PHASES[PHASES.find(phase) + 1])
	if not _snaps.is_empty():
		_snap()


func _snap() -> void:
	RenderingServer.render_loop_enabled = t >= _snaps[0] - 0.5
	if t >= _snaps[0] and not _snapping:
		_snapping = true
		var at: float = _snaps[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%04.1f.png" % [_snap_out, at])
		_snaps.pop_front()
		_snapping = false
		if _snaps.is_empty():
			get_tree().quit()


func _done() -> bool:
	match phase:
		"break":
			return squad != null and squad.stats.camo_broken > 0 and _phase_t > 1.0
	return false


func _enter(p: String) -> void:
	phase = p
	_phase_t = 0.0
	_log("phase %s" % p)
	match p:
		"walk":
			giraffe = _unit("giraffe", GIRAFFE_FROM)
			giraffe.pinged.connect(_on_pinged)
			commander.submit({"type": "move", "units": [giraffe.unit_id], "pos": GIRAFFE_WAIT, "attack": false})
			spotter = _unit("rifleman", SPOTTER_AT)
			spotter.stats = spotter.stats.duplicate()
			spotter.stats.sight = 15.0
			fogged = FlameTrooper.new()
			_trooper(fogged, TROOPER_AT, SPOTTER_AT + Vector3.UP)
		"spot":
			commander.submit({"type": "move", "units": [giraffe.unit_id], "pos": GIRAFFE_SPOT, "attack": false})
		"ping":
			fogged.take_damage(10000.0, GameConfig.TEAM_ATTACKER)
			open = InfiltratorTrooper.new()
			_trooper(open, OPEN_AT, RIFLE_AT + Vector3.UP)
			camod = InfiltratorTrooper.new()
			_trooper(camod, CAMO_AT, RIFLE_AT + Vector3.UP)
			camod.set_camo(true, InfiltratorSquad._camo_hidden())
			far = FlameTrooper.new()
			_trooper(far, FAR_AT, RIFLE_AT + Vector3.UP)
			for k in 3:
				riflemen.append(_unit("rifleman", RIFLE_AT + Vector3(0.0, 0.0, k * 2.5 - 2.5)))
			_ping_later(2.5)
		"camo":
			open.hp = open.max_hp
			open.set_camo(true, InfiltratorSquad._camo_hidden())
			_hp_at = open.hp
		"fogback":
			open.set_camo(false, InfiltratorSquad._camo_hidden())
			open.hp = open.max_hp
			giraffe.ping_cd = 0.0
			_marks.clear()
			commander.submit({"type": "ping", "units": [giraffe.unit_id]})
		"radar":
			_radar_checks()
		"break":
			if video:
				print("VIDEO END frame %d" % _frame)
			_start_break()
		"end":
			_finish()


func _ping_later(after: float) -> void:
	await get_tree().create_timer(after, false, true).timeout
	_check(is_equal_approx(open.hp, open.max_hp), "low profile: the riflemen left the infiltrator 23 m off alone before the ping (hp %d/%d)" % [open.hp, open.max_hp])
	_check(commander.submit({"type": "ping", "units": [giraffe.unit_id]}) == 0 and giraffe.is_pinging(), "the giraffe pings (P)")


func _on_pinged(p: GiraffePing) -> void:
	_log("ping out from %s" % p.global_position)
	p.marked.connect(func(d, at): _marks[d] = at)


func _leave(p: String) -> void:
	match p:
		"walk":
			_check(_clips.has("Walk"), "the giraffe walks (its Walk clip)")
			_check(giraffe.sight() >= UnitTypes.DATA.values().map(func(d): return d.get("sight", 0.0)).max(), "the giraffe sees furthest of any unit (%d m)" % giraffe.sight())
			_check(not AttackerVision.sees(fogged.global_position), "the trooper 25 m from the rifleman is in the fog of war")
			_check(not fogged.visible, "in the fog the trooper isn't drawn on the attacker's side")
			_check(is_equal_approx(fogged.hp, fogged.max_hp), "the rifleman leaves it alone though it is in range (hp %d/%d)" % [fogged.hp, fogged.max_hp])
			commander.submit({"type": "attack", "units": [spotter.unit_id], "target": fogged.get_path()})
			_check(spotter.order.type != "attack", "an order to attack it is refused")
		"spot":
			_check(AttackerVision.sees(fogged.global_position) and fogged.visible, "the giraffe sees it from %d m: it shows" % giraffe.global_position.distance_to(fogged.global_position))
			_check(fogged.hp < fogged.max_hp, "the rifleman shoots it now the army sees it (hp %d/%d)" % [fogged.hp, fogged.max_hp])
		"ping":
			_check(_clips.has("Ping") and _flags.get("stood", false), "it stood and played its Ping clip")
			_check(_marks.has(open) and _marks.has(camod), "the pulse marked both infiltrators, the one under camo too")
			_check(not _marks.has(far), "not the trooper beyond its reach (%d m)" % giraffe.global_position.distance_to(far.global_position))
			_blurs = get_tree().get_nodes_in_group("ping_blurs")
			_check(_blurs.size() == _marks.size() and _blurs.size() >= 2, "a red blur for each mark (%d)" % _blurs.size())
			_check(open.revealed and not open.low_profile, "the infiltrator out of camo is revealed")
			_check(not camod.revealed and camod.low_profile, "the one under camo isn't")
			_check(open.hp < open.max_hp, "the riflemen went after her on their own (hp %d/%d)" % [open.hp, open.max_hp])
			_check(is_equal_approx(camod.hp, camod.max_hp), "and left the one under camo alone (hp %d/%d)" % [camod.hp, camod.max_hp])
			# The blurs stay where the pulse found them.
			var before: Array = _blurs.map(func(b): return b.global_position)
			camod.global_position += Vector3(6.0, 0.0, 0.0)
			await get_tree().physics_frame
			var still := true
			for k in _blurs.size():
				if is_instance_valid(_blurs[k]) and _blurs[k].global_position.distance_to(before[k]) > 0.01:
					still = false
			var near := false
			for b in _blurs:
				if is_instance_valid(b) and Vector2(b.global_position.x - _marks[camod].x, b.global_position.z - _marks[camod].z).length() < GiraffePing.BLUR_JITTER + 0.1:
					near = true
			_check(still and near, "the blurs stay where she was marked as she walks off")
		"camo":
			_check(not open.revealed and open.low_profile, "under camo she is revealed no more")
			_check(is_equal_approx(open.hp, _hp_at), "and they lost her (hp %d/%d)" % [open.hp, open.max_hp])
		"fogback":
			_check(_flags.get("fog_revealed", false), "pinged again out of camo, she is revealed")
			_check(not open.revealed and open.low_profile, "back in the fog of war her low profile is back")
		"break":
			_check(squad.stats.camo_broken == 1, "an arrow loosed under camo broke it")
			_check(squad.camo_left <= 0.0 and squad.troopers.all(func(x): return not x.camouflaged), "the whole squad is out of camo")
			_check(squad.camo_cd > 0.0, "and it is still cooling down (%ds)" % ceili(squad.camo_cd))


func _process(_delta: float) -> void:
	_frame += 1
	# Fogback: once the second ping revealed her, she slips off into the fog.
	if phase == "fogback" and open.revealed and not _flags.get("fog_revealed", false):
		_flags.fog_revealed = true
		_log("revealed again: off into the fog")
		open.global_position = FOG_AT + Vector3.UP * 0.1
		open.goal = FOG_AT


func _radar_checks() -> void:
	open.global_position = OPEN_AT + Vector3.UP * 0.1
	open.goal = OPEN_AT
	vision.refresh()
	GameConfig.player_side = GameConfig.PlayerSide.DEFENDER
	open.reveal()
	_check(open._radar.visible, "on the defender's side a radar icon hangs over the revealed infiltrator")
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	open._conceal()
	open.reveal()
	_check(open.revealed and not open._radar.visible, "the attacker doesn't see it")
	open._conceal()


func _start_break() -> void:
	var armory := DefenderArmory.new()
	armory.level = level
	armory.credits = DefenderArmory.INFILTRATOR_COST
	add_child(armory)
	var dc := DefenderController.new()
	dc.level = level
	dc.armory = armory
	add_child(dc)
	squad = dc.buy_squad("infiltrator") as InfiltratorSquad
	dc.select_squad(armory.squads.find(squad), true)
	squad.pilot = Trigger.new()
	squad.camo_cd = 0.0
	_check(squad.start_camo() and squad.troopers.all(func(x): return x.camouflaged), "the squad goes under camo")


func _camera() -> void:
	if phase == "break":
		return  # the squad's own camera
	var at := giraffe.global_position.lerp(Vector3(10.0, 0.0, Z), 0.5) if giraffe else Vector3(0, 0, Z)
	cam.global_position = at + (Vector3(0.0, 34.0, 26.0) if video else Vector3(0.0, 55.0, 38.0))
	cam.look_at(at)


func _finish() -> void:
	print("GIRAFFE checks:")
	for c in _checks:
		print("  " + c)
	print("GIRAFFE SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if test or video:
		get_tree().quit(1 if _failed else 0)
