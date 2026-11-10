class_name DefenderJet
extends DefenderMachine
## The defenders' Fighter Jet (the model and its moving surfaces: FighterJetRig), flown in third person from a chase camera.
## Bought with credits (DefenderArmory), it scrambles from the stronghold already at cruising speed and never lands: it
## flies until it is shot down or crashes, and then it is gone for good. Crash into the ground, the forest canopy, the
## mountain or any structure and you lose it, with a great fireball.
##
## Flying (mouse-aim, like an arcade flight game): the mouse steers where the nose is going (the ring on the HUD is what you
## aim at; the jet banks and turns onto it as fast as it can), W/S pitch down / up and A/D turn if you'd rather use the
## keys, Shift is the speed boost (the afterburners: a few seconds of it, then it has to recover), Space the airbrake.
## Diving gains speed and climbing sheds it. Out past the edge of the battlefield it is called back, and lost if it won't turn.
##
##   LMB  Bomb: one bomb from the bay (BOMBS carried, one comes back every BOMB_RECHARGE). A real bomb: it leaves with the
##        jet's own velocity and falls under gravity and drag (JetBomb), so it lands far ahead of where you let it go, and
##        the faster and the higher you are the farther ahead. The aim is a preview on the ground, like the Bisons'
##        bombardment's: the ring where the blast will land and the arc it will fall along, following the jet in real time
##        (JetBomb.predict flies the same fall ahead of time), and a mark on the screen over it.
##   RMB  Missile barrage: a salvo of SALVO missiles from the wing pylons, one every SALVO_INTERVAL. Each flies straight out
##        along where the nose points at the moment it leaves (and carries the jet's speed), unguided. Flying straight and
##        level they leave in a tight bunch up the same line; manoeuvring through the salvo, each goes where the nose is then,
##        so they scatter over the area the nose swept (and the more it is turning the wider each strays too). Each hits
##        lightly (MISSILE_DAMAGE, a small splash): the strength is in the numbers.
##
## Left alone (the player is on another post) it flies itself, a gunship's way (see _idle): it circles the spot where it was
## left (ORBIT: a left-hand pylon turn, IDLE_RADIUS round), and stays passive: it fires on nothing, until it is attacked (hurt, or
## an enemy has locked on to it). Then it bombs the attacker (SETUP out to the start of a run, RUN, let go the bomb where the
## forecast crosses it, EGRESS breaking away so it doesn't fly over it; up to MAX_PASSES passes while it lives and bombs last),
## and once it is destroyed, flies back to the spot where it was left (RETURN) and circles again until it is attacked again.

const RigScript := preload("res://scripts/vehicles/fighter_jet_rig.gd")

## Speeds (m/s): cruising, boosted, the slowest it will fly (the airbrake's).
const CRUISE := 120.0
const BOOST_SPEED := 200.0
const MIN_SPEED := 85.0
const ACCEL := 45.0
const BOOST_ACCEL := 85.0
## Diving gains and climbing sheds this much speed (m/s) at the steepest.
const CLIMB_BLEED := 42.0
## The turn (yaw) and pitch rates at cruising speed (rad/s), how fast the controls take hold (1/s), its steepest bank and
## how fast it rolls (rad/s), the steepest it pitches. The faster it flies the wider it turns (SPEED_TURN).
const MAX_TURN := 1.15
const MAX_PITCH_RATE := 1.0
const CONTROL_LAG := 6.0
const MAX_BANK := deg_to_rad(72.0)
const ROLL_RATE := deg_to_rad(210.0)
const PITCH_LIMIT := deg_to_rad(78.0)
const SPEED_TURN := 0.6
## The mouse's aim can lead the nose by this much at most (rad), sideways and up or down.
const AIM_LEAD := deg_to_rad(80.0)
const AIM_LEAD_PITCH := deg_to_rad(55.0)
## Keyboard: how fast A/D and W/S sweep the aim (rad/s).
const KEY_TURN := 1.5
const KEY_PITCH := 1.1
## The boost: seconds of it from full, seconds to come back from empty (after BOOST_DELAY), and the level a spent boost
## has to recover to before it works again.
const BOOST_TIME := 4.0
const BOOST_REGEN := 7.0
const BOOST_DELAY := 0.8
const BOOST_RELIGHT := 0.3
## Flying too low: how far ahead (s) it looks for the ground and the mountain, and the height over the ground below which
## it hits it (m, the jet's belly). In a forest the canopy is the ground (LevelBuilder.CANOPY_TOP, less CANOPY_SKIM).
const LOOK_AHEAD := 2.2
const BELLY := 1.4
const CANOPY_SKIM := 8.0
## Its steepest height over the ground it is allowed (m): above that it is pushed down.
const CEILING := 520.0
## Beyond this far in from the edge of the map it is called back, and has OUT_TIME seconds to be back before it is lost.
const EDGE_MARGIN := 60.0
const OUT_TIME := 7.0
## Bombs: carried, a new one every BOMB_RECHARGE s, at least BOMB_INTERVAL s apart; its blast and damage.
const BOMBS := 4
const BOMB_RECHARGE := 8.0
const BOMB_INTERVAL := 0.4
const BOMB_RADIUS := 11.0
const BOMB_DAMAGE := 380.0
## Where the bay lets go, from the jet's origin (the model's frame: +Z forward).
const BAY := Vector3(0.0, -0.4, -0.6)
## Missiles: a salvo of SALVO, one every SALVO_INTERVAL s, reloaded SALVO_RELOAD s after the last left. Each hits for
## MISSILE_DAMAGE and splashes MISSILE_SPLASH m. They stray MISSILE_SPREAD rad at the least, and up to MISSILE_SPREAD_TURN
## when the jet is turning flat out. Pylons: out along each wing, MISSILE_PYLONS each.
const SALVO := 16
const SALVO_INTERVAL := 0.06
const SALVO_RELOAD := 11.0
const MISSILE_DAMAGE := 30.0
const MISSILE_SPLASH := 4.5
const MISSILE_SPREAD := 0.006
const MISSILE_SPREAD_TURN := 0.09
const MISSILE_PYLONS := 3
## Chase camera: how far behind and above (m), the field of view (wider on the boost), how fast it follows the jet's
## heading (1/s: it lags a little round a turn), how far ahead it looks.
const CAM_BACK := 34.0
const CAM_UP := 8.5
const CAM_FOV := 70.0
const BOOST_FOV := 86.0
const CAM_LAG := 5.0
const CAM_LOOK := 70.0
## Left alone, orbiting: the circle's radius (m) and the speed (m/s) it flies it at, and the height over the ground it keeps (m,
## what it was at when it was left, between these).
const IDLE_RADIUS := 230.0
const IDLE_SPEED := 100.0
const IDLE_MIN_HEIGHT := 120.0
const IDLE_MAX_HEIGHT := 240.0
## A bomb run: the height it flies at (m), how far out from the attacker it starts (m), how close to that start it counts as
## lined up (m), how near to the attacker (as a share of how far a bomb carries) a run is abandoned for another try, the lateral
## error at the moment of release it will accept (m), how hard it breaks away after the drop (rad) and for how long at the
## least (s), and how many passes it makes.
const RUN_HEIGHT := 110.0
const RUN_START := 700.0
const RUN_CAPTURE := 140.0
const RUN_TOO_CLOSE := 0.85
const RUN_LATERAL := 9.0
const EGRESS_TURN := deg_to_rad(75.0)
const EGRESS_MIN := 3.0
const MAX_PASSES := 3
## Left alone: how often it looks to see if it is being attacked (s), and how far it looks for who is attacking it when it
## can't tell (m).
const SCAN_INTERVAL := 0.15
const ATTACKER_SEARCH := 160.0
## The stages of what it does left alone.
enum Idle { ORBIT, SETUP, RUN, EGRESS, RETURN }
const HP := 700.0
const IMPACTS_KEPT := 64
## How tall the preview's column of light is (m).
const BEAM_HEIGHT := 90.0

## Where it is flying: heading (rad, 0 = +Z, left +), pitch (rad, up +), bank (rad, right wing down +), speed (m/s).
var heading := 0.0
var pitch := 0.0
var bank := 0.0
var speed := CRUISE
## What the pilot steers toward (heading, pitch), the rates it is turning at now (rad/s, left and up +).
var aim_heading := 0.0
var aim_pitch := 0.0
var turn_rate := 0.0
var pitch_rate := 0.0
var rig: RigScript
## The boost left (0..1), and whether it is lit.
var boost := 1.0
var boosting := false
## Bombs in the bay; seconds to the next one back.
var bombs := BOMBS
## Missiles left in the salvo being fired (0: none), and seconds until a new salvo can go.
var salvo_left := 0
var salvo_cd := 0.0
## Where a bomb let go now would land (JetBomb.predict's answer), flown each frame while the player has the jet.
var bomb_forecast := {}
## Where its bombs and missiles have burst (the latest IMPACTS_KEPT of each), for the showcase's checks.
var bomb_bursts: Array[Vector3] = []
var missile_bursts: Array[Vector3] = []
## The directions the latest missiles left along, and where the bomb let go last was forecast to land at that moment.
var missile_aims: Array[Vector3] = []
var last_drop_forecast := {}
## What the flight warns about now: "" , "PULL UP", "TURN BACK".
var warning := ""
## Seconds left to be back inside the map.
var out_left := OUT_TIME
var crashed_at := Vector3.INF

## Left alone: what it is doing; the spot where it was left (the orbit goes through it) and the circle's centre; the height it
## keeps (m); the attacker it is bombing (null: it is passive).
var idle_state := Idle.ORBIT
var anchor := Vector3.INF
var orbit_centre := Vector3.INF
var orbit_height := IDLE_MIN_HEIGHT
var attacker: Node3D = null

var _hurt_flag := false
var _scan_cd := 0.0
var _passes := 0
var _run_dir := Vector3.ZERO
var _run_bomb: JetBomb = null
var _egress_t := 0.0
var _egress_side := 1.0
var _settle_t := 0.0
var _cam_fwd := Vector3.BACK
var _cam_fov := CAM_FOV
var _bomb_cd := 0.0
var _bomb_regen := BOMB_RECHARGE
var _salvo_pylon := 0
var _salvo_timer := 0.0
var _boost_delay := 0.0
var _boost_spent := false
var _falling := false
var _fall_spin := 0.0
var _crashed := false
var _fire: WreckSmoke
var _path_mi: MeshInstance3D
var _ring_mi: MeshInstance3D
var _beam_mi: MeshInstance3D
var _disc_mi: MeshInstance3D
var _path_mesh := ImmediateMesh.new()
var _ring_mesh := ImmediateMesh.new()
var _cam_shake := 0.0
var _prev_samples: Array[Vector3] = []


func _init() -> void:
	station_name = "Fighter Jet"
	station_kind = "jet"
	hud_title = "FIGHTER JET"
	hp = HP
	max_hp = HP
	target_radius = 6.0
	aim_height = 2.0
	input = {"move": Vector2.ZERO, "bomb": false, "missiles": false, "boost": false, "brake": false}
	stats = {"bombs": 0, "salvos": 0, "missiles": 0, "boosts": 0, "crashes": 0, "bomb_kills": 0}


func setup(n: int) -> void:
	number = n
	station_name = "Fighter Jet" if n <= 1 else "Fighter Jet %d" % n
	hud_title = station_name.to_upper()


func roster_label() -> String:
	return "JET" if number <= 1 else "JET %d" % number


func order_name() -> String:
	if not is_alive():
		return "LOST"
	if possessed:
		return "FLYING"
	return {Idle.ORBIT: "ORBIT", Idle.SETUP: "BOMB RUN", Idle.RUN: "BOMB RUN", Idle.EGRESS: "BOMB RUN", Idle.RETURN: "RETURN"}[idle_state]


func order_color() -> Color:
	if possessed:
		return UIKit.ACCENT
	return UIKit.DANGER if idle_state in [Idle.SETUP, Idle.RUN, Idle.EGRESS] else UIKit.WARN


func doing(_driving: bool) -> String:
	if not is_alive():
		return "crashed" if _crashed else "shot down"
	return "boost" if boosting else "%d m/s" % int(speed)


func down_message() -> String:
	return "%s crashed — it is lost for good" % station_name if _crashed else "%s was shot down" % station_name


func get_aim_point() -> Vector3:
	return global_position + global_basis.y * 1.0


## The pilot's chase camera.
func get_camera() -> Camera3D:
	return _cam


# ---------------------------------------------------------------- build

func _build() -> void:
	add_to_group("air_units")
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12.0, 3.0, 16.0)
	box.shape = shape
	box.position.y = 1.2
	add_child(box)
	rig = RigScript.new()
	add_child(rig)
	_fire = WreckSmoke.new()
	_fire.size = 2.2
	_fire.rate = 22.0
	_fire.position = Vector3(0, 0.6, -2.0)
	add_child(_fire)
	_cam.fov = CAM_FOV
	# The aim preview: the fall's path (dim) and the blast's ring and column (bright), drawn in world coordinates.
	_path_mi = _preview_mesh(_path_mesh, Color(1.0, 0.8, 0.45, 0.55))
	_ring_mi = _preview_mesh(_ring_mesh, Color(1.0, 0.55, 0.2))
	# And, so it reads from a long way off (the ring is small at 500 m): a faint disc on the ground the size of the blast
	# and a column of light over it.
	_disc_mi = _glow_mesh(BOMB_RADIUS, 0.2, 0.45)
	_beam_mi = _glow_mesh(BOMB_RADIUS * 0.8, BEAM_HEIGHT, 0.3)
	_deploy()


func _preview_mesh(mesh: ImmediateMesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.unshaded(color, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.extra_cull_margin = 4000.0
	mi.visible = false
	add_child(mi)
	return mi


## A see-through cylinder of `radius` and `height` (the bomb preview's disc and column).
func _glow_mesh(radius: float, height: float, alpha: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 32
	c.rings = 1
	c.cap_top = height < 1.0
	c.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.55, 0.2, alpha)
	m.set_meta("alpha", alpha)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


func _make_hud() -> Control:
	var hud := JetHud.new()
	hud.jet = self
	return hud


## Where and how it starts: out in front of the stronghold's gate hall, at height, already at cruising speed and heading
## away from the middle of the map.
func _deploy() -> void:
	var from := Vector3(home.origin.x, 0.0, home.origin.z) - Vector3(loiter_centre.x, 0.0, loiter_centre.z)
	var out := from.normalized() if from.length() > 5.0 else Vector3.BACK
	var at := Vector3(loiter_centre.x, 0.0, loiter_centre.z) + out * (from.length() + 170.0)
	at.y = maxf(LevelBuilder.ground_height(at), 0.0) + 130.0
	heading = atan2(out.x, out.z)
	aim_heading = heading
	pitch = 0.0
	aim_pitch = 0.0
	bank = 0.0
	speed = CRUISE
	global_position = at
	_apply_pose()
	_cam_fwd = global_basis.z
	_prev_samples = _samples()
	_begin_idle()


## Puts the jet in the air at `at` (for a showcase): heading (rad, 0 = +Z, left +), pitch (rad), speed.
func stage(at: Vector3, new_heading: float, new_pitch := 0.0, new_speed := CRUISE) -> void:
	heading = new_heading
	pitch = new_pitch
	bank = 0.0
	speed = new_speed
	aim_heading = heading
	aim_pitch = pitch
	turn_rate = 0.0
	pitch_rate = 0.0
	global_position = at
	_apply_pose()
	_cam_fwd = forward()
	_prev_samples = _samples()
	if not possessed:
		_begin_idle()


func _on_possess() -> void:
	attacker = null
	aim_heading = heading
	aim_pitch = pitch
	_cam_fwd = global_basis.z
	_cam_fov = CAM_FOV
	_set_preview_visible(true)


func _set_preview_visible(on: bool) -> void:
	for mi in [_path_mi, _ring_mi, _disc_mi, _beam_mi]:
		mi.visible = on


func unpossess() -> void:
	super()
	_set_preview_visible(false)
	boosting = false
	rig.boost = 0.0
	# Left where it is: that is where it will circle, and come back to.
	if is_alive():
		_begin_idle()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not possessed or pilot != null or _dead or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameConfig.mouse_sensitivity * 1.35
		steer(aim_heading - event.relative.x * sens, aim_pitch - event.relative.y * sens)


func _read_input() -> void:
	input.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input.bomb = Input.is_action_just_pressed("fire")
	input.missiles = Input.is_action_just_pressed("aim")
	input.boost = Input.is_action_pressed("sprint")
	input.brake = Input.is_action_pressed("jump")


## Points the aim at a heading and pitch (rad), no more than AIM_LEAD off the nose.
func steer(new_heading: float, new_pitch: float) -> void:
	aim_heading = heading + clampf(wrapf(new_heading - heading, -PI, PI), -AIM_LEAD, AIM_LEAD)
	aim_pitch = pitch + clampf(new_pitch - pitch, -AIM_LEAD_PITCH, AIM_LEAD_PITCH)
	aim_pitch = clampf(aim_pitch, -PITCH_LIMIT, PITCH_LIMIT)


## Steers toward a point in the world.
func steer_toward(point: Vector3) -> void:
	var d := point - global_position
	steer(atan2(d.x, d.z), atan2(d.y, Vector2(d.x, d.z).length()))


## The aim as a direction in the world.
func aim_dir() -> Vector3:
	return Vector3(sin(aim_heading) * cos(aim_pitch), sin(aim_pitch), cos(aim_heading) * cos(aim_pitch))


func forward() -> Vector3:
	return global_basis.z


## The velocity a bomb let go now carries: the jet's own (a little pushed down by the release).
func bomb_velocity() -> Vector3:
	return forward() * speed + Vector3.DOWN * 2.0


## Where the bay lets go, in the world.
func bay_position() -> Vector3:
	return global_transform * BAY


# ---------------------------------------------------------------- the frame

func _control(delta: float) -> void:
	var move: Vector2 = input.move
	if move != Vector2.ZERO:
		steer(aim_heading - move.x * KEY_TURN * delta, aim_pitch + move.y * KEY_PITCH * delta)
	_fly(delta, bool(input.boost), bool(input.brake))
	_weapons(delta, bool(input.bomb), bool(input.missiles))
	_forecast()


func _idle(delta: float) -> void:
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_INTERVAL
		_look_for_attacker()
	var brake := false
	var cruise := IDLE_SPEED
	match idle_state:
		Idle.ORBIT:
			_fly_orbit()
		Idle.SETUP:
			cruise = CRUISE
			_set_up_run()
		Idle.RUN:
			brake = true
			_fly_run(delta)
		Idle.EGRESS:
			cruise = CRUISE
			_break_away(delta)
		Idle.RETURN:
			cruise = CRUISE
			_return_to_orbit()
	_stay_safe()
	_fly(delta, false, brake, cruise)
	_weapons(delta, false, false)


## Where it was left becomes where it circles: a left-hand circle through the jet's spot (so it flies straight onto it), kept
## inside the battlefield, at the height it was left at (within IDLE_MIN_HEIGHT..IDLE_MAX_HEIGHT).
func _begin_idle() -> void:
	idle_state = Idle.ORBIT
	attacker = null
	_passes = 0
	_hurt_flag = false
	_scan_cd = SCAN_INTERVAL
	anchor = global_position
	orbit_height = clampf(altitude(), IDLE_MIN_HEIGHT, IDLE_MAX_HEIGHT)
	var left := Vector3(cos(heading), 0.0, -sin(heading))
	var c := Vector3(anchor.x, 0.0, anchor.z) + left * IDLE_RADIUS
	var room := map_half - EDGE_MARGIN - IDLE_RADIUS - 20.0
	orbit_centre = Vector3(clampf(c.x, -room, room), 0.0, clampf(c.z, -room, room))


## The point of its circle nearest the spot where it was left.
func orbit_point() -> Vector3:
	var d := Vector3(anchor.x - orbit_centre.x, 0.0, anchor.z - orbit_centre.z)
	d = d.normalized() if d.length() > 1.0 else Vector3.RIGHT
	return orbit_centre + d * IDLE_RADIUS


## The point `height` over the surface (the ground, over a forest the canopy) under `p`.
static func _at_height(p: Vector3, height: float) -> Vector3:
	return Vector3(p.x, p.y - _clearance(p) + height, p.z)


## Round the circle: along the circle's tangent, bent in toward it when outside it and out when inside, so it settles on the
## circle (steering at a point on the circle would spiral in).
func _fly_orbit() -> void:
	var flat := Vector3(global_position.x - orbit_centre.x, 0.0, global_position.z - orbit_centre.z)
	var r := flat.length()
	var radial := flat / r if r > 1.0 else Vector3.RIGHT
	var tangent := Vector3(radial.z, 0.0, -radial.x)
	var bend := clampf((r - IDLE_RADIUS) / 70.0, -1.0, 1.0) * deg_to_rad(55.0)
	var d := tangent * cos(bend) - radial * sin(bend)
	var ahead := global_position + d * 400.0
	steer_toward(_at_height(ahead, orbit_height))


## Back to the spot where it was left, level at the orbit's height; once there it circles again.
func _return_to_orbit() -> void:
	var at := orbit_point()
	steer_toward(_at_height(at, orbit_height))
	if Vector2(global_position.x - at.x, global_position.z - at.z).length() < 110.0:
		idle_state = Idle.ORBIT


# ---------------------------------------------------------------- attacked, and the bomb run

## Is something attacking it? An enemy locked on to it (an anti-aircraft unit's lock, or what it is attacking), or it has been
## hurt: then the nearest enemy it can bomb that could have done it. Passive otherwise.
func _look_for_attacker() -> void:
	if idle_state in [Idle.RUN, Idle.SETUP, Idle.EGRESS]:
		_hurt_flag = false
		return
	if bombs <= 0:
		return
	var best: Node3D = null
	var best_d := INF
	var fallback: Node3D = null
	var fallback_d := INF
	var fallback_aa: Node3D = null
	var fallback_aa_d := INF
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if not _bombable(u):
			continue
		var d := Vector2(u.global_position.x - global_position.x, u.global_position.z - global_position.z).length()
		if u.get("_aa_lock") == self or u.get("target") == self:
			if d < best_d:
				best_d = d
				best = u
		elif _hurt_flag:
			if float(u.stats.get("aa_range", 0.0)) > 0.0 and d < ATTACKER_SEARCH and d < fallback_aa_d:
				fallback_aa_d = d
				fallback_aa = u
			elif d < ATTACKER_SEARCH * 0.8 and d < fallback_d:
				fallback_d = d
				fallback = u
	if best == null and _hurt_flag:
		best = fallback_aa if fallback_aa != null else fallback
	_hurt_flag = false
	if best != null:
		attacker = best
		_passes = 0
		_begin_setup()


## A ground attacker a bomb can get at: alive, on the ground (not flying or under water), not up inside the mountain.
func _bombable(u: Node3D) -> bool:
	if not Combat.is_valid_target(u) or u.is_flying() or u.is_submerged():
		return false
	return absf(u.global_position.x) > LevelBuilder.MOUNTAIN_HALF or absf(u.global_position.z) > LevelBuilder.MOUNTAIN_HALF


func _flat_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## How far ahead a bomb let go on the run lands (m).
func _drop_distance() -> float:
	return JetBomb.reach(RUN_HEIGHT, MIN_SPEED)


## Starts (or starts over) the approach: out to the start of a run, upwind of the attacker, 700 m back from it along the
## way the jet is coming from (or, if it is too close for that, from over its own side), inside the battlefield.
func _begin_setup() -> void:
	idle_state = Idle.SETUP
	var t := Vector3(attacker.global_position.x, 0.0, attacker.global_position.z)
	var me := Vector3(global_position.x, 0.0, global_position.z)
	var dir := me - t
	if dir.length() < 350.0:
		dir = Vector3(anchor.x, 0.0, anchor.z) - t
	if dir.length() < 350.0:
		dir = -Vector3(sin(heading), 0.0, cos(heading))
	# From that side if the way in is clear, else the nearest side that is (a wall, a mast or the mountain in the way).
	_run_dir = dir.normalized()
	for turn in [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0, 180.0]:
		var cand := dir.normalized().rotated(Vector3.UP, deg_to_rad(turn))
		if _clear_run(t, cand):
			_run_dir = cand
			break


## Is the way in along `dir` from the start of a run to the attacker at `t` clear of anything tall (checked 40 m under the
## run's height, for a margin)?
func _clear_run(t: Vector3, dir: Vector3) -> bool:
	var start := t + dir * RUN_START
	var lim := map_half - EDGE_MARGIN - 40.0
	start.x = clampf(start.x, -lim, lim)
	start.z = clampf(start.z, -lim, lim)
	var a := _at_height(start, RUN_HEIGHT - 40.0)
	var b := _at_height(t, RUN_HEIGHT - 40.0)
	var q := PhysicsRayQueryParameters3D.create(a, b, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	# And not over the attackers' bases (broad decks with tall masts).
	for base in get_tree().get_nodes_in_group("attacker_bases"):
		var reach: float = base.deck_size.length() * 0.6 + 60.0
		for k in 8:
			var p := start.lerp(t, k / 7.0)
			if Vector2(p.x - base.global_position.x, p.z - base.global_position.z).length() < reach:
				return false
	return true


func _run_start() -> Vector3:
	var t := Vector3(attacker.global_position.x, 0.0, attacker.global_position.z)
	var at := t + _run_dir * RUN_START
	var lim := map_half - EDGE_MARGIN - 40.0
	at.x = clampf(at.x, -lim, lim)
	at.z = clampf(at.z, -lim, lim)
	return _at_height(at, RUN_HEIGHT)


## Out to the start of the run; lined up (there, or already pointed at the attacker from far enough out), the run begins.
func _set_up_run() -> void:
	if not Combat.is_valid_target(attacker) or bombs <= 0:
		_give_up_run()
		return
	var start := _run_start()
	steer_toward(start)
	var to := Vector3(attacker.global_position.x - global_position.x, 0.0, attacker.global_position.z - global_position.z)
	var dist := to.length()
	var lined_up := absf(wrapf(atan2(to.x, to.z) - heading, -PI, PI)) < deg_to_rad(18.0) \
			and dist > _drop_distance() * 1.1 + 80.0 and dist < RUN_START * 2.0
	if _flat_to(start) < RUN_CAPTURE or lined_up:
		idle_state = Idle.RUN
		_run_bomb = null


## The run: at the attacker (led, if it is moving), level, slowed to bomb. Let go the bomb when the forecast of where it would
## land (the same fall the preview shows) crosses the attacker's spot: nearer than that and it would fall short, farther and
## beyond.
func _fly_run(_delta: float) -> void:
	if not Combat.is_valid_target(attacker):
		_give_up_run()
		return
	bomb_forecast = JetBomb.predict(get_world_3d().direct_space_state, bay_position(), bomb_velocity())
	var t: Vector3 = attacker.global_position
	var lead := Vector3(t.x, 0.0, t.z)
	var v = attacker.get("velocity")
	if v is Vector3:
		lead += Vector3(v.x, 0.0, v.z) * float(bomb_forecast.time) * 0.8
	steer_toward(_at_height(lead, RUN_HEIGHT))
	var fwd := Vector3(forward().x, 0.0, forward().z).normalized()
	var impact: Vector3 = bomb_forecast.impact
	var to := lead - Vector3(global_position.x, 0.0, global_position.z)
	var aligned := absf(wrapf(atan2(to.x, to.z) - heading, -PI, PI)) < deg_to_rad(25.0)
	var close := to.length() < _drop_distance() * RUN_TOO_CLOSE
	if not aligned:
		# Still coming round onto it (out at the start of the run it is pointing the wrong way): too near already, and it
		# won't be lined up in time.
		if close:
			_begin_egress()
		return
	var err := lead - Vector3(impact.x, 0.0, impact.z)
	var along := err.dot(fwd)
	var lateral := (err - fwd * along).length()
	if along <= speed * get_physics_process_delta_time() and along > -30.0:
		# Over the spot: let it go, if it is lined up; then break away.
		if lateral <= RUN_LATERAL and bomb_forecast.hit:
			_run_bomb = drop_bomb()
		_begin_egress()
	elif along <= -30.0:
		# Too close for it to land on the attacker: break away and come round again.
		_begin_egress()


func _begin_egress() -> void:
	idle_state = Idle.EGRESS
	_egress_t = 0.0
	_settle_t = 0.0
	if Combat.is_valid_target(attacker):
		var left := Vector3(cos(heading), 0.0, -sin(heading))
		var to := attacker.global_position - global_position
		# Away from the attacker's side, so it doesn't fly over it.
		_egress_side = -1.0 if to.dot(left) > 0.0 else 1.0
	else:
		_egress_side = 1.0


## Breaking away from the attacker (turned off it, climbing a little) until the bomb has landed; then, if the attacker is still
## there and there are bombs and passes left, round for another run; else home.
func _break_away(delta: float) -> void:
	_egress_t += delta
	steer(heading + _egress_side * EGRESS_TURN, deg_to_rad(8.0))
	var landed := _run_bomb == null or not is_instance_valid(_run_bomb)
	if _egress_t < EGRESS_MIN or not landed:
		return
	_settle_t += delta
	if _settle_t < 0.6:
		return
	_passes += 1
	if Combat.is_valid_target(attacker) and bombs > 0 and _passes < MAX_PASSES:
		_begin_setup()
	else:
		_give_up_run()


## Done with the attacker (destroyed, or out of bombs and passes): home.
func _give_up_run() -> void:
	attacker = null
	_run_bomb = null
	idle_state = Idle.RETURN


## Whatever it was doing, it does not fly into the ground, a wall, or out of the battlefield.
func _stay_safe() -> void:
	if warning == "PULL UP" or altitude() < 45.0:
		steer(heading, deg_to_rad(40.0))
	elif warning == "TURN BACK":
		steer_toward(_at_height(orbit_centre, orbit_height))


func _fly(delta: float, want_boost: bool, brake: bool, cruise := CRUISE) -> void:
	# The boost: lit while it is held and there is some; it runs down, and comes back once it has been let go.
	var was := boosting
	boosting = want_boost and boost > 0.0 and not _boost_spent and not _falling and not _dead
	if boosting:
		boost = maxf(boost - delta / BOOST_TIME, 0.0)
		_boost_delay = BOOST_DELAY
		if boost <= 0.0:
			_boost_spent = true
		if not was:
			stats.boosts += 1
	else:
		_boost_delay = maxf(_boost_delay - delta, 0.0)
		if _boost_delay <= 0.0:
			boost = minf(boost + delta / BOOST_REGEN, 1.0)
		if _boost_spent and boost >= BOOST_RELIGHT:
			_boost_spent = false

	var prev_xf := global_transform
	if _falling:
		_fall(delta)
	else:
		var agility := pow(CRUISE / maxf(speed, 40.0), SPEED_TURN)
		var herr := wrapf(aim_heading - heading, -PI, PI)
		var perr := aim_pitch - pitch
		var turn_cmd := clampf(herr * 2.4, -1.0, 1.0) * MAX_TURN * agility
		var pitch_cmd := clampf(perr * 2.6, -1.0, 1.0) * MAX_PITCH_RATE * agility
		# Too high: pushed back down.
		if altitude() > CEILING and pitch_cmd > -0.3:
			pitch_cmd = -0.3 * MAX_PITCH_RATE
		var k := 1.0 - exp(-CONTROL_LAG * delta)
		turn_rate = lerpf(turn_rate, turn_cmd, k)
		pitch_rate = lerpf(pitch_rate, pitch_cmd, k)
		heading = wrapf(heading + turn_rate * delta, -PI, PI)
		pitch = clampf(pitch + pitch_rate * delta, -PITCH_LIMIT, PITCH_LIMIT)
		bank = move_toward(bank, -clampf(turn_rate / (MAX_TURN * agility), -1.0, 1.0) * MAX_BANK, ROLL_RATE * delta)
		# Speed: the throttle's, less what the climb costs (or plus what a dive gives).
		var want := cruise
		if boosting:
			want = BOOST_SPEED
		elif brake:
			want = MIN_SPEED
		want = clampf(want - sin(pitch) * CLIMB_BLEED, MIN_SPEED * 0.85, BOOST_SPEED + 40.0)
		speed = move_toward(speed, want, (BOOST_ACCEL if boosting else ACCEL) * delta)
	var dir := _direction()
	velocity = dir * speed
	global_position += velocity * delta
	_apply_pose()
	rig.boost = 1.0 if boosting else 0.0
	_check_flight(prev_xf, delta)


func _direction() -> Vector3:
	return Vector3(sin(heading) * cos(pitch), sin(pitch), cos(heading) * cos(pitch))


func _apply_pose() -> void:
	global_basis = Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, bank)


## How high over what it would hit (the ground; over a forest, the canopy) the jet's belly is (m).
func altitude() -> float:
	return _clearance(global_position)


static func _clearance(p: Vector3) -> float:
	var ground := maxf(LevelBuilder.ground_height(p), 0.0)
	if LevelBuilder.terrain != null and JungleFlora.in_jungle(p):
		ground += LevelBuilder.CANOPY_TOP - CANOPY_SKIM
	return p.y - ground


## Points on the airframe (world): the nose, the wing tips, the tail and the belly.
func _samples() -> Array[Vector3]:
	var xf := global_transform
	return [xf * Vector3(0, 0.4, 9.0), xf * Vector3(-9.5, 0.2, -2.0), xf * Vector3(9.5, 0.2, -2.0), xf * Vector3(0, 0.6, -8.0),
			xf * Vector3(0, -BELLY, 0.0)]


## Did it hit something this frame; is it flying where it will? Sets `warning`.
func _check_flight(_prev_xf: Transform3D, delta: float) -> void:
	var now := _samples()
	var space := get_world_3d().direct_space_state
	if not _crashed:
		for i in now.size():
			if _prev_samples.size() == now.size():
				var q := PhysicsRayQueryParameters3D.create(_prev_samples[i], now[i], GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					_crash(hit.position, hit.normal)
					break
		if not _crashed and _clearance(now[4]) < 0.0:
			_crash(Vector3(now[4].x, maxf(LevelBuilder.ground_height(now[4]), 0.0), now[4].z), Vector3.UP)
	# Ahead: low ground or a wall in the way; and the edge of the battlefield.
	warning = ""
	if not _dead:
		var ahead := global_position + velocity * LOOK_AHEAD
		if _clearance(ahead) < 6.0 and pitch < deg_to_rad(20.0):
			warning = "PULL UP"
		else:
			var q := PhysicsRayQueryParameters3D.create(global_position, ahead, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
			if not space.intersect_ray(q).is_empty():
				warning = "PULL UP"
		var lim := map_half - EDGE_MARGIN
		if absf(global_position.x) > lim or absf(global_position.z) > lim:
			warning = "TURN BACK"
			out_left -= delta
			if out_left <= 0.0:
				say("LEFT THE BATTLEFIELD", 3.0)
				_go_down("lost")
		else:
			out_left = minf(out_left + delta * 2.0, OUT_TIME)
	_prev_samples = now


# ---------------------------------------------------------------- weapons

func _weapons(delta: float, bomb: bool, missiles: bool) -> void:
	_bomb_cd = maxf(_bomb_cd - delta, 0.0)
	if bombs < BOMBS:
		_bomb_regen -= delta
		if _bomb_regen <= 0.0:
			bombs += 1
			_bomb_regen = BOMB_RECHARGE
	else:
		_bomb_regen = BOMB_RECHARGE
	if bomb and bombs > 0 and _bomb_cd <= 0.0 and not _falling:
		drop_bomb()
	salvo_cd = maxf(salvo_cd - delta, 0.0)
	if missiles and salvo_left == 0 and salvo_cd <= 0.0 and not _falling:
		fire_salvo()
	if salvo_left > 0:
		_salvo_timer -= delta
		while salvo_left > 0 and _salvo_timer <= 0.0:
			_salvo_timer += SALVO_INTERVAL
			_launch_missile()
			salvo_left -= 1
			if salvo_left == 0:
				salvo_cd = SALVO_RELOAD



## Drops a bomb from the bay: false if there is none, or one has only just gone.
func drop_bomb() -> JetBomb:
	if bombs <= 0 or _bomb_cd > 0.0 or _dead:
		return null
	bombs -= 1
	_bomb_cd = BOMB_INTERVAL
	stats.bombs += 1
	last_drop_forecast = JetBomb.predict(get_world_3d().direct_space_state, bay_position(), bomb_velocity())
	var b := JetBomb.new()
	b.team = team
	b.damage = BOMB_DAMAGE
	b.radius = BOMB_RADIUS
	get_tree().current_scene.add_child(b)
	b.drop(bay_position(), bomb_velocity(), forward())
	b.burst.connect(func(at: Vector3): _keep(bomb_bursts, at))
	return b


## Starts a missile barrage: false if one is going, or the pylons are still reloading.
func fire_salvo() -> bool:
	if salvo_left > 0 or salvo_cd > 0.0 or _dead:
		return false
	salvo_left = SALVO
	_salvo_timer = 0.0
	_salvo_pylon = 0
	stats.salvos += 1
	return true


## How hard the jet is manoeuvring just now (0 flying straight, 1 flat out), which spreads the missiles' aim.
func maneuver() -> float:
	var m := absf(turn_rate) / MAX_TURN + absf(pitch_rate) / MAX_PITCH_RATE
	return clampf(m * 0.75, 0.0, 1.0)


## One missile of the salvo, along where the nose points just now.
func _launch_missile() -> void:
	var i := _salvo_pylon
	_salvo_pylon += 1
	var side := -1.0 if i % 2 == 0 else 1.0
	var row := (i / 2) % MISSILE_PYLONS
	var from := global_transform * Vector3(side * (3.4 + 1.5 * row), -0.9, 1.6)
	var dir := Combat.apply_spread(forward(), lerpf(MISSILE_SPREAD, MISSILE_SPREAD_TURN, maneuver()))
	var m := JetMissile.new()
	m.damage = MISSILE_DAMAGE
	m.splash = MISSILE_SPLASH
	m.size = 1.4
	get_tree().current_scene.add_child(m)
	m.fire(from, dir, velocity)
	m.on_spent = func(): _keep(missile_bursts, m.global_position)
	_keep(missile_aims, dir)
	stats.missiles += 1
	var fx := FX.of(self)
	fx.flare(from, Color(5.0, 3.0, 1.2), 0.6, 1.4, 0.12, 0, 2.0)


func _keep(list: Array[Vector3], at: Vector3) -> void:
	list.append(at)
	if list.size() > IMPACTS_KEPT:
		list.pop_front()


## Flies a bomb let go now ahead (JetBomb.predict) for the aim preview.
func _forecast() -> void:
	bomb_forecast = JetBomb.predict(get_world_3d().direct_space_state, bay_position(), bomb_velocity())
	_draw_preview()


## The preview on the ground, like the Bisons' bombardment aim: a dashed ring where the blast will land (its true radius),
## a smaller one in it, a cross and the arc the bomb will fall along, with a faint disc and a column of light over it.
func _draw_preview() -> void:
	_path_mesh.clear_surfaces()
	_ring_mesh.clear_surfaces()
	var f := bomb_forecast
	if f.is_empty() or _dead:
		return
	var pts: PackedVector3Array = f.points
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var k := 0
	while k + 1 < pts.size():
		_path_mesh.surface_add_vertex(pts[k])
		_path_mesh.surface_add_vertex(pts[k + 1])
		k += 2
	_path_mesh.surface_end()
	var at: Vector3 = f.impact + Vector3.UP * 0.4
	var armed := bombs > 0
	_ring_mi.material_override = Mats.unshaded(Color(1.0, 0.55, 0.2) if armed else Color(0.6, 0.6, 0.6, 0.7), true)
	_disc_mi.global_position = at
	_beam_mi.global_position = at + Vector3.UP * BEAM_HEIGHT * 0.5
	for mi in [_disc_mi, _beam_mi]:
		var m := mi.material_override as StandardMaterial3D
		var a: float = m.get_meta("alpha")
		m.albedo_color = Color(1.0, 0.55, 0.2, a) if armed else Color(0.6, 0.6, 0.6, a * 0.7)
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	RhinoAim.dashed_circle(_ring_mesh, at, BOMB_RADIUS, 40)
	RhinoAim.dashed_circle(_ring_mesh, at, BOMB_RADIUS * 0.45, 20)
	for a in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		_ring_mesh.surface_add_vertex(at - a * BOMB_RADIUS * 0.7)
		_ring_mesh.surface_add_vertex(at + a * BOMB_RADIUS * 0.7)
	_ring_mesh.surface_end()


# ---------------------------------------------------------------- going down

func take_damage(amount: float, from_team: int) -> void:
	var before := hp
	super(amount, from_team)
	if hp < before and from_team != team and not possessed:
		_hurt_flag = true
		_scan_cd = 0.0


func _on_down(reason: String) -> void:
	_cam_shake = 1.0
	if reason == "shot":
		# Out of control: nose down and spinning, burning, until it hits the ground.
		_falling = true
		_fall_spin = randf_range(2.5, 4.0) * (1.0 if randf() < 0.5 else -1.0)
		_fire.emitting = true
		_death_t = WRECK_VIEW + 3.0
		say("SHOT DOWN", 4.0)
		FX.of(self).blast(global_position, 4.0, NAN, true)
	elif reason == "lost":
		_crash(global_position, Vector3.UP, true)


## It has hit something: the airframe goes up. (Not a kill in the air: `quiet` skips the blast on the ground.)
func _crash(at: Vector3, _normal: Vector3, air := false) -> void:
	if _crashed:
		return
	_crashed = true
	crashed_at = at
	stats.crashes += 1
	if not _dead:
		_dead = true
		hp = 0.0
		_death_t = WRECK_VIEW if possessed else 0.5
		collision_layer = 0
		remove_from_group("defender_targets")
		say("CRASHED", 3.0)
	else:
		_death_t = minf(_death_t, WRECK_VIEW)
	_falling = false
	rig.visible = false
	boosting = false
	rig.boost = 0.0
	var fx := FX.of(self)
	Combat.explode(self, at, 12.0, 240.0, team, 1.0)
	fx.blast(at + Vector3.UP * 3.0, 9.0, NAN, air)
	for n in 16:
		var d := Vector3(randf_range(-1, 1), randf_range(0.4, 1.6), randf_range(-1, 1)).normalized()
		fx.debris(at + Vector3.UP, d * randf_range(8.0, 30.0) + velocity * 0.25, randf_range(0.5, 1.4), randf_range(3.0, 6.0),
				Color(0.34, 0.36, 0.4), 0.9, 0.35, at.y)
	# The wreck burns where it fell.
	var wreck := WreckSmoke.new()
	wreck.size = 2.6
	wreck.rate = 14.0
	wreck.emitting = true
	get_tree().current_scene.add_child(wreck)
	wreck.global_position = at + Vector3.UP * 0.5
	get_tree().create_timer(25.0).timeout.connect(wreck.queue_free)
	_fire.emitting = false
	global_position = at + Vector3.UP * 2.0
	_set_preview_visible(false)


## Out of control: nose over, spinning, picking up speed.
func _fall(delta: float) -> void:
	pitch = move_toward(pitch, -deg_to_rad(65.0), deg_to_rad(40.0) * delta)
	bank += _fall_spin * delta
	turn_rate = lerpf(turn_rate, 0.0, 0.1)
	speed = minf(speed + 30.0 * delta, BOOST_SPEED + 80.0)


func _wreck(delta: float) -> void:
	_cam_shake = maxf(_cam_shake - delta * 1.5, 0.0)
	if _falling and not _crashed:
		_fly(delta, false, false)


# ---------------------------------------------------------------- camera

func _chase_camera(delta: float) -> void:
	if _crashed:
		# On the wreck: a little way off, looking at it.
		var at := crashed_at if crashed_at != Vector3.INF else global_position
		var from := at + Vector3(-36.0, 20.0, 52.0)
		_cam.global_position = _cam.global_position.lerp(from, 1.0 - exp(-2.0 * delta))
		_cam.look_at(at + Vector3.UP * 2.0, Vector3.UP)
		return
	var fwd := forward()
	_cam_fwd = _cam_fwd.slerp(fwd, 1.0 - exp(-CAM_LAG * delta)).normalized()
	var pull := 1.0 + (0.14 if boosting else 0.0)
	var want := global_position - _cam_fwd * CAM_BACK * pull + Vector3.UP * CAM_UP
	# Never into the ground or a wall: pulled in to the first thing between it and the jet.
	var q := PhysicsRayQueryParameters3D.create(global_position, want, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = hit.position + hit.normal * 1.5
	if boosting or _cam_shake > 0.0:
		var s := (0.12 if boosting else 0.0) + _cam_shake * 1.2
		want += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
	_cam.global_position = want
	var look := global_position + _cam_fwd * CAM_LOOK
	var dir := (look - want).normalized()
	var up := (Vector3.UP * 0.75 + global_basis.y * 0.25).normalized()
	if dir.cross(up).length() < 0.05:
		up = global_basis.y
	_cam.global_basis = Basis.looking_at(dir, up)
	_cam_fov = lerpf(_cam_fov, BOOST_FOV if boosting else CAM_FOV, 1.0 - exp(-4.0 * delta))
	_cam.fov = _cam_fov


# ---------------------------------------------------------------- the panel (DefenderController)

func get_hud_info() -> Dictionary:
	var bombs_text := "BOMBS %d" % bombs
	var missiles_text := "MISSILES %d" % salvo_left if salvo_left > 0 else ("MISSILES %ds" % ceili(salvo_cd) if salvo_cd > 0.0 else "MISSILES READY")
	return {"weapon": "%s · %s" % [bombs_text, missiles_text], "status": "%d m/s" % int(speed), "hp": clampf(hp / max_hp, 0.0, 1.0),
			"heat": boost, "bar_color": UIKit.ACCENT if not _boost_spent else UIKit.DANGER, "crosshair": false,
			"hint": "Mouse steer · Shift boost · Space airbrake · W/S pitch · A/D turn · LMB bomb · RMB missile barrage"}
