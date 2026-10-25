extends Node3D
## Staged flight of the Sky Talon on the real map: it flies like a hawk, gliding most of the time
## and beating its wings now and then, and never hovers: with nowhere left to go it circles.
##
##   takeoff  one talon lifts off from the south field, beating its wings all the way up
##   cruise   it flies west across the field: long glides, a few wing beats every few seconds
##   circle   at the end of the move it circles the spot, banked into the turn, the centre off its
##            left wing, like a gunship flying a pylon turn
##   attack   ordered at a rifleman on the south gun deck, it circles him and fires down from
##            the ring
##   flock    five talons sent to one spot stack up in rings of their own
##
##   godot --path game --headless --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --test
##   godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie talon.avi \
##       --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --video > talon.log
##   python3 tools/video/cut_showcase.py talon.avi talon.log media/talon_showcase.mp4
##
## --snap=t1,t2,.. --snap-out=prefix draws and saves only the frames at those times.
## --test prints what the talons do and checks it at the end (TALON SHOWCASE PASS / FAIL).
## --video draws only the stretches in VIDEO (the rest is skipped, for a shorter render) and prints
## the frames to keep for tools/video/cut_showcase.py.
## The garrison's posts hold fire, all but the rifleman the talon attacks: he fires back (the
## talon gets the hit points to outlast him).

const TAKEOFF := Vector3(80.0, 0.0, 168.0)
const CIRCLE_AT := Vector3(-62.0, 0.0, 150.0)
const FLOCK_FROM := Vector3(70.0, 16.0, 200.0)
const FLOCK_AT := Vector3(0.0, 0.0, 128.0)
const DECK_SOLDIER := "Soldier_south_2"
## The run, in seconds: [start, phase].
const SCRIPT := [[0.0, "takeoff"], [7.0, "cruise"], [22.0, "circle"], [40.0, "attack"], [62.0, "flock"],
		[82.0, "end"]]
## What the video shows of it (seconds): two bursts of wing beats on the way, one on the ring.
const VIDEO := [[0.3, 5.0], [8.0, 16.5], [23.0, 33.0], [49.0, 57.0], [72.0, 80.0]]

var level: LevelBuilder
var commander: AttackerCommander
var cam: Camera3D
var hero: AttackerUnit
var flock: Array = []
var soldier: Node3D
var t := -1.0
var phase := ""
var test := false
var video := false
var _phase_t := 0.0
## Frames drawn so far, whether the current one is in the video, and where the cut began.
var _frame := -1
var _shown := true
var _cut_from := 0
## Per phase: seconds flown, seconds beating the wings, wing bursts begun, slowest speed, ring
## distance range, most bank, seconds turning right.
var _log := {}
var _was_flapping := false
var _soldier_hp := 0.0
var _checks: Array[String] = []
var _failed := false
var _closest_pair := INF
var _caption: Label
var _snaps: Array = []
var _snap_out := "snap"
var _snapping := false


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
	for s in level.stations:
		if String(s.name) == DECK_SOLDIER:
			soldier = s
		else:
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
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	cam.position = TAKEOFF + Vector3(-6.0, 3.0, 14.0)
	cam.look_at(TAKEOFF + Vector3.UP)
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	commander.process_mode = Node.PROCESS_MODE_INHERIT
	hero = _talon(TAKEOFF + Vector3.UP * 0.2, CIRCLE_AT)
	print("TALON hero ring %.1f m, height %+.1f m" % [hero._flight.ring, hero._flight.height])
	t = 0.0
	if video:
		print("VIDEO START frame %d" % (_frame + 1))


func _talon(pos: Vector3, to: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": "talon", "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = pos
	u.look_at(Vector3(to.x, pos.y, to.z))
	commander.submit({"type": "move", "units": [id], "pos": to, "attack": false})
	return u


func _physics_process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	var k := 0
	while k < SCRIPT.size() - 1 and t >= SCRIPT[k + 1][0]:
		k += 1
	if SCRIPT[k][1] != phase:
		_enter(SCRIPT[k][1])
		if phase == "end":
			_finish()
			return
	_phase_t += delta
	_record(delta)


func _enter(p: String) -> void:
	phase = p
	_phase_t = 0.0
	match phase:
		"takeoff":
			_say("Sky Talon · take-off", "beating its wings all the way up to its cruising height")
		"cruise":
			_say("Cruising", "it glides most of the time and beats its wings now and then")
		"circle":
			_say("Nowhere left to go: it circles", "banked into the turn, the centre off its left wing, like a gunship")
		"attack":
			_soldier_hp = soldier.hp
			hero.hp = hero.stats.hp * 10.0
			commander.submit({"type": "attack", "units": [hero.unit_id], "target": soldier.get_path()})
			_say("Attack: a rifleman on the south gun deck", "it circles him, firing down from the ring")
		"flock":
			for i in 5:
				flock.append(_talon(FLOCK_FROM + Vector3(i * 4.0, 0.0, i * 3.0), FLOCK_AT))
			_say("Five sent to one spot", "each flies a ring of its own, stacked like gunships")


## What the hero (in the flock phase, the flock) does this step, for the checks.
func _record(delta: float) -> void:
	var u := hero
	if not is_instance_valid(u) or not u.is_alive():
		return
	var f: TalonFlight = u._flight
	var e: Dictionary = _log.get_or_add(phase, {"time": 0.0, "flapping": 0.0, "bursts": 0, "slowest": INF,
			"ring_min": INF, "ring_max": 0.0, "bank": 0.0, "right": 0.0, "left_of": 0.0, "climbing": 0.0,
			"climb_flapping": 0.0})
	var flapping := f._beats > 0.0
	var speed := Vector2(u.velocity.x, u.velocity.z).length()
	e.time += delta
	if flapping:
		e.flapping += delta
		if not _was_flapping:
			e.bursts += 1
			if test:
				print("TALON %5.1f s %-8s wing beats" % [t, phase])
	_was_flapping = flapping
	if u.velocity.y > 1.5:
		e.climbing += delta
		if flapping:
			e.climb_flapping += delta
	if _phase_t > 1.0:
		e.slowest = minf(e.slowest, speed)
	# round the middle of its ring (which moves out from the mountain, off the rifleman)
	var center: Vector3 = f._ring[0] if phase in ["circle", "attack"] else Vector3.INF
	if center != Vector3.INF and _phase_t > 12.0:
		var d := _flat(u.global_position, center)
		e.ring_min = minf(e.ring_min, d)
		e.ring_max = maxf(e.ring_max, d)
		e.bank = maxf(e.bank, rad_to_deg(f._bank))
		if f._turn < -0.05:
			e.right += delta
		# The centre is off its left wing: to the left of where it flies.
		var left := -u.global_basis.x
		var to := center - u.global_position
		if Vector2(left.x, left.z).dot(Vector2(to.x, to.z).normalized()) > 0.8:
			e.left_of += delta
	if phase == "flock" and _phase_t > 14.0:
		for i in flock.size():
			for j in range(i + 1, flock.size()):
				_closest_pair = minf(_closest_pair, flock[i].global_position.distance_to(flock[j].global_position))
	if test and int((t - delta) * 2.0) != int(t * 2.0) and int(t * 2.0) % 4 == 0:
		print("TALON %5.1f s %-8s pos (%6.1f, %5.1f, %6.1f) speed %4.1f climb %+4.1f bank %+5.1f° %s %s" % [t, phase,
				u.global_position.x, u.global_position.y, u.global_position.z, speed, u.velocity.y,
				rad_to_deg(f._bank), "FLAP" if flapping else "glide", u.order.type])


func _process(_delta: float) -> void:
	_frame += 1
	if t < 0.0:
		return
	_camera()
	if video:
		_cut()
	if not _snaps.is_empty():
		_snap()


## Draws the frames in VIDEO only; the others are recorded as copies, cut out afterwards.
func _cut() -> void:
	var shown := VIDEO.any(func(r): return t >= r[0] and t < r[1])
	RenderingServer.render_loop_enabled = shown
	if shown == _shown:
		return
	_shown = shown
	if shown:
		print("CUT frames %d-%d" % [_cut_from, _frame - 1])
	else:
		_cut_from = _frame


## The camera: beside the talon on take-off, behind it on the way, up over the ring while it
## circles, down in the field under the gun deck for the attack and up over the flock.
func _camera() -> void:
	var p := hero.global_position if is_instance_valid(hero) else CIRCLE_AT
	var fwd := -hero.global_basis.z if is_instance_valid(hero) else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var at: Vector3
	var look: Vector3
	match phase:
		"takeoff":
			at = TAKEOFF + Vector3(-10.0, 4.0, 22.0) + Vector3(-1.0, 0.0, 0.0) * _phase_t * 4.0
			look = p + Vector3.UP
		"cruise":
			at = p - fwd * 14.0 + right * 7.0 + Vector3.UP * 4.0
			look = p + fwd * 6.0
		"circle":
			if _phase_t < 9.0:
				at = CIRCLE_AT + Vector3(0.0, 36.0, 24.0)
				look = CIRCLE_AT + Vector3.UP * 14.0
			else:
				at = p - fwd * 12.0 + right * 5.0 + Vector3.UP * 3.0
				look = p + fwd * 8.0
		"attack":
			var deck := soldier.global_position
			at = Vector3(deck.x + 18.0, 3.5, deck.z + 36.0)
			look = deck.lerp(p, 0.6)
		_:
			at = FLOCK_AT + Vector3(-22.0, 30.0, 36.0)
			look = FLOCK_AT + Vector3.UP * 15.0
	var w := 1.0 if _phase_t < 0.1 else 0.08
	cam.position = cam.position.lerp(at, w)
	var target := cam.global_transform.looking_at(look, Vector3.UP)
	cam.global_transform = cam.global_transform.interpolate_with(target, w * 1.5 if w < 1.0 else 1.0)


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


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok    " if ok else "FAIL  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	var cruise_speed: float = UnitTypes.DATA.talon.speed
	var take: Dictionary = _log.takeoff
	_check(take.climbing > 1.0 and take.climb_flapping >= take.climbing * 0.9,
			"takeoff: beats its wings while it climbs (%.1f of %.1f s)" % [take.climb_flapping, take.climbing])
	var cruise: Dictionary = _log.cruise
	var share: float = cruise.flapping / cruise.time
	_check(share > 0.1 and share < 0.45 and cruise.bursts >= 2,
			"cruise: glides most of the time (beating %.0f%% of it, %d bursts)" % [share * 100.0, cruise.bursts])
	for p in ["circle", "attack"]:
		var e: Dictionary = _log[p]
		_check(e.slowest > cruise_speed * 0.8, "%s: never stops (slowest %.1f m/s)" % [p, e.slowest])
		_check(e.ring_max - e.ring_min < 6.0, "%s: keeps to a ring (%.1f to %.1f m out)" % [p, e.ring_min, e.ring_max])
		_check(e.bank > 15.0 and e.right < 0.5, "%s: banked left into a counterclockwise turn (bank %.0f°, %.1f s turning right)" % [p, e.bank, e.right])
		_check(e.left_of > (e.time - 12.0) * 0.8, "%s: the centre off its left wing (%.1f of %.1f s)" % [p, e.left_of, e.time - 12.0])
	var circle: Dictionary = _log.circle
	_check(circle.flapping / circle.time < 0.35, "circle: soars, few wing beats (%.0f%%)" % [circle.flapping / circle.time * 100.0])
	_check(soldier.hp < _soldier_hp, "attack: the rifleman hit from the ring (%.0f -> %.0f HP)" % [_soldier_hp, maxf(soldier.hp, 0.0)])
	_check(_closest_pair > 2.5, "flock: the rings keep the five apart (closest %.1f m)" % _closest_pair)
	for c in _checks:
		print("TALON CHECK ", c)
	print("TALON SHOWCASE %s" % ("FAIL" if _failed else "PASS"))
	if video:
		if not _shown:
			print("CUT frames %d-%d" % [_cut_from, _frame])
		print("VIDEO END frame %d" % _frame)
	get_tree().quit()


func _say(title: String, sub: String) -> void:
	_caption.text = "%s\n%s" % [title, sub]
	if test:
		print("TALON %5.1f s %s: %s" % [t, title, sub])


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_caption = UIKit.label("", 22, Color.WHITE)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y = 40
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
