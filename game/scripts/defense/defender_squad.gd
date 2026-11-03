class_name DefenderSquad
extends Node3D
## A defender post of five troopers (SquadTrooper) that the player takes over in third person: the
## Gunner Squad, the AA Squads, the Flame Squads and the Infiltrator Squads (the Sniper is a post of
## one: squad_size). The player drives the trooper in the middle of the formation; the other four
## follow it (SquadFormation: a wedge in the open, squeezing in and filing behind the leader through
## tunnels, around trees and rocks) and aim wherever the player aims. Blast doors open for the squad
## as it comes up to them (Structure.hold_open), so it can sally out through a standing gate. Left to
## itself the squad runs its own AI (_ai_control). Lost troopers are replaced one at a time from the
## post; when all five are down the squad is gone for RESPAWN_TIME (or for good, if it doesn't
## respawn). If the leader falls, the trooper nearest it takes the lead (and the player's camera and
## keys) and the others follow it as they did the old one, a column walking on down the same trail.
##
## What the troopers fight with, and the squad's AI, come from the subclass.
##
## Station interface: see DefenderController.

signal became_unavailable(station)
## Every trooper is down and the squad doesn't come back (respawns false).
signal wiped_out(squad)

const SIZE := 5
const RESPAWN_TIME := 30.0
const REINFORCE_TIME := 20.0
## Seconds between formation solves; in between, the spots ride along with the leader.
const SOLVE_INTERVAL := 0.15
## The formation turns to face the aim at up to this rate; standing still it ignores small turns.
const HEADING_RATE := deg_to_rad(110.0)
const HEADING_DEADZONE := deg_to_rad(20.0)
## Aim points closer than this are looked at side by side instead of converged on.
const CONVERGE_MIN := 8.0
## In a column the followers walk the leader's own trail instead of pathing: each steers for the
## point TRAIL_LOOKAHEAD further up it, at the leader's pace plus TRAIL_GAIN per meter it is behind
## its slot, slowing down to keep COLUMN_GAP from whoever is ahead of it. A follower takes to the
## trail within TRAIL_JOIN of it (if it can walk straight onto it) and leaves it (back to pathing)
## past TRAIL_LEAVE, or for TRAIL_REST after getting caught on something.
const TRAIL_LOOKAHEAD := 1.2
const TRAIL_GAIN := 1.2
const COLUMN_GAP := 1.5
const TRAIL_JOIN := 0.9
const TRAIL_LEAVE := 1.8
const TRAIL_REST := 1.5
## Blast doors open while a trooper is this close (m).
const GATE_REACH := 6.5
const HOME_REACH := 1.5
const AIM_RANGE := 220.0
## Third-person camera: pivot over the leader's shoulders, then the arm out behind its right
## shoulder; closer in and tighter while aiming (RMB).
const CAM_PIVOT := Vector3(0.0, 1.95, 0.0)
const CAM_ARM := Vector3(0.9, 0.35, 4.4)
const CAM_AIM_ARM := Vector3(1.05, 0.2, 2.6)
const CAM_FOV := 64.0
const CAM_AIM_FOV := 44.0
const CAM_PITCH_MIN := deg_to_rad(-60.0)
const CAM_PITCH_MAX := deg_to_rad(40.0)

var station_name := "Squad"
var station_kind := "squad"
## Name on the squad panel.
var hud_title := "SQUAD"
var team := GameConfig.TEAM_DEFENDER
var possessed := false
## Lost troopers come back; all five lost, the squad comes back after RESPAWN_TIME. Otherwise it
## is gone for good once all five are down (wiped_out).
var respawns := true
## Hit points of one trooper (for the squad's health bar).
var trooper_hp := 400.0
## How many troopers it fields (SIZE; one for the Sniper).
var squad_size := SIZE
## The squad's post: where it holds and respawns, facing its -Z.
var home := Transform3D.IDENTITY
## Gates the squad opens on its way through.
var gates: Array = []
var troopers: Array[SquadTrooper] = []
var leader: SquadTrooper = null
var formation := SquadFormation.new()
var aim_point := Vector3.ZERO
var firing := false
## Showcase autopilot: an object with pilot_input(squad, delta) that fills `input` (and may turn
## the camera with look_toward()) instead of the keyboard and mouse.
var pilot: Object = null
var input := {"move": Vector2.ZERO, "fire": false, "aim": false, "hustle": false}
## Yaw the formation faces.
var heading := 0.0
## Where each follower was sent (world), for the HUD map.
var goals := {}
## Followers off on work of their own (a Flame Squad's troopers each burning a tree), trooper ->
## world point: they walk there instead of to their place in the formation, and the subclass aims
## them. Taken out of it, a trooper falls back in.
var free := {}

var hp: float:
	get:
		var s := 0.0
		for t in troopers:
			s += maxf(t.hp, 0.0)
		return s
var max_hp: float:
	get:
		return squad_size * trooper_hp

var cam_yaw := 0.0
var cam_pitch := deg_to_rad(-12.0)
## The camera's arm out from its pivot, and while aiming (CAM_ARM, CAM_AIM_ARM unless the squad says).
var cam_arm := CAM_ARM
var cam_aim_arm := CAM_AIM_ARM
var _cam: Camera3D
var _cam_pivot := Vector3.ZERO
## 1 when the lead has just changed hands, running down to 0 while the camera glides to the new one.
var _glide := 0.0
var _aim_t := 0.0
var _hud: SquadHud
var _hud_layer: CanvasLayer
var _solve_cd := 0.0
var _solve_at := Vector3.ZERO
var _spots: Array[Vector3] = []
var _respawn_cd := 0.0
var _reinforce_cd := 0.0
var _nav_ready := false
var _on_trail := {}
var _trail_rest := {}
var _walled := {}


## A new trooper of the squad's kind (not yet in the tree).
func _new_trooper() -> SquadTrooper:
	return null


## Names a bought squad after its purchase number (DefenderArmory).
func setup(_n: int) -> void:
	pass


## For the roster of bought squads (SquadHotbar): its name in a slot, its auto order (and the
## colour it is shown in), whether the slot should catch the eye, and a word on what it is up to.
func roster_label() -> String:
	return station_name


func order_name() -> String:
	return ""


func order_color() -> Color:
	return UIKit.WARN


func alert() -> bool:
	return false


func doing(_driving: bool) -> String:
	return ""


## Next auto order (Ctrl+F<n>, or V while driving the squad).
func cycle_order() -> void:
	pass


func _ready() -> void:
	formation.nav_layers = 1 | LevelBuilder.NAV_SQUAD
	heading = home.basis.get_euler().y
	cam_yaw = heading
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.05
	_cam.far = 800.0
	add_child(_cam)
	_hud = SquadHud.new()
	_hud.squad = self
	_hud.visible = false
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 3
	add_child(_hud_layer)
	_hud_layer.add_child(_hud)
	_spawn_all()


# ---------------------------------------------------------------- station interface

func can_possess() -> bool:
	return not troopers.is_empty()


func possess() -> void:
	possessed = true
	_cam.current = true
	_hud.visible = true
	if leader:
		cam_yaw = leader.rotation.y
		_cam_pivot = leader.global_position + CAM_PIVOT
	cam_pitch = deg_to_rad(-12.0)


func unpossess() -> void:
	possessed = false
	firing = false
	_cam.current = false
	_hud.visible = false


func wants_captured_mouse() -> bool:
	return true


func get_station_position() -> Vector3:
	return leader.global_position if leader else home.origin


func get_camera() -> Camera3D:
	return _cam


## The squad panel shows while the player drives the squad (and a showcase may hide it).
func set_hud_visible(on: bool) -> void:
	_hud.visible = on and possessed


func get_hud_info() -> Dictionary:
	return {"weapon": "", "status": "—", "hp": 0.0, "hint": ""}


# ---------------------------------------------------------------- troopers

func _spawn_all() -> void:
	# In a line behind the post until the navmesh is up and the formation can be worked out.
	for i in squad_size:
		_spawn(home.origin + home.basis.z * (float(i) * SquadFormation.TRAIL_SPACING))
	_pick_leader()


func _spawn(at: Vector3) -> SquadTrooper:
	var t := _new_trooper()
	t.squad = self
	add_child(t)
	t.global_position = at + Vector3.UP * 0.1
	t.rotation.y = heading
	t.aim_point = at + Basis(Vector3.UP, heading) * Vector3(0, 1.5, -30.0)
	t.died.connect(_on_trooper_died)
	troopers.append(t)
	_share_exclusions()
	return t


func _share_exclusions() -> void:
	var rids: Array[RID] = []
	for t in troopers:
		rids.append(t.get_rid())
	for t in troopers:
		t.exclude = rids.duplicate()


func _on_trooper_died(t: SquadTrooper) -> void:
	troopers.erase(t)
	goals.erase(t)
	free.erase(t)
	_on_trail.erase(t)
	_trail_rest.erase(t)
	_walled.erase(t)
	if t == leader:
		leader = null
		_pick_leader(t.global_position)
		if leader:
			_glide = 1.0
			_hud.flash("LEADER DOWN · NEW LEADER")
	if troopers.is_empty():
		_respawn_cd = RESPAWN_TIME
		firing = false
		became_unavailable.emit(self)
		if not respawns:
			wiped_out.emit(self)
	elif _reinforce_cd <= 0.0:
		_reinforce_cd = REINFORCE_TIME


## The trooper nearest `near` (the fallen leader, or the post) takes the lead.
func _pick_leader(near = null) -> void:
	if troopers.is_empty():
		return
	var at: Vector3 = near if near != null else home.origin
	var best: SquadTrooper = null
	for t in troopers:
		if best == null or t.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = t
	leader = best
	for t in troopers:
		t.set_leader(t == leader)
	if near != null:
		formation.handover(leader.global_position, at)
	else:
		formation.trail.clear()
	_spots.clear()


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if troopers.is_empty():
		if respawns:
			_respawn_cd -= delta
			if _respawn_cd <= 0.0:
				_spawn_all()
		return
	if leader == null or not leader.is_alive():
		_pick_leader()
	if not _nav_ready:
		var map := get_world_3d().navigation_map
		formation.nav_map = map
		_nav_ready = NavigationServer3D.map_get_iteration_id(map) > 0 \
				and LevelBuilder.nav_closest(map, home.origin + Vector3.UP) != Vector3.ZERO
	if possessed:
		_player_control(delta)
	else:
		_ai_control(delta)
	_update_heading(delta)
	formation.record(leader.global_position, leader.velocity)
	_update_followers(delta)
	_arm_troopers(delta)
	_open_gates()
	if troopers.size() < squad_size:
		_reinforce_cd -= delta
		if _reinforce_cd <= 0.0:
			_reinforce_cd = REINFORCE_TIME
			_spawn(home.origin)


func _process(delta: float) -> void:
	if possessed and leader:
		_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not possessed or pilot != null or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameConfig.mouse_sensitivity * (_cam.fov / CAM_FOV)
		cam_yaw = wrapf(cam_yaw - event.relative.x * sens, -PI, PI)
		cam_pitch = clampf(cam_pitch - event.relative.y * sens, CAM_PITCH_MIN, CAM_PITCH_MAX)


## Turns the camera toward `point` at up to `rate` rad/s (for the showcase autopilot).
func look_toward(point: Vector3, rate: float, delta: float) -> void:
	var from := _cam.global_position if _cam.is_inside_tree() else leader.global_position + CAM_PIVOT
	var d := point - from
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	cam_yaw = rotate_toward(cam_yaw, yaw, rate * delta)
	cam_pitch = clampf(rotate_toward(cam_pitch, pitch, rate * 0.6 * delta), CAM_PITCH_MIN, CAM_PITCH_MAX)


## The keyboard and mouse into `input` (a showcase pilot fills it instead).
func _read_input() -> void:
	input.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input.fire = Input.is_action_pressed("fire")
	input.aim = Input.is_action_pressed("aim")
	input.hustle = Input.is_action_pressed("sprint")


func _player_control(delta: float) -> void:
	if pilot != null:
		pilot.pilot_input(self, delta)
	else:
		_read_input()
	var hustle: bool = input.hustle and not input.fire
	for t in troopers:
		t.hustle = hustle
	var move: Vector2 = input.move
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(move.x, 0.0, move.y)
	var v := Vector3.ZERO
	if dir.length() > 0.05:
		v = dir.normalized() * leader.max_speed_toward(dir.normalized()) * minf(dir.length(), 1.0)
	leader.following = false
	leader.drive(v)
	aim_point = _camera_aim()
	_player_weapons(delta, hustle)


## The player's trigger and weapon keys, once the leader is driven and aim_point is set.
func _player_weapons(_delta: float, hustle: bool) -> void:
	firing = input.fire and not hustle


## Left alone (nobody drives the squad).
func _ai_control(_delta: float) -> void:
	for t in troopers:
		t.hustle = false
	leader.following = false
	firing = false


## Hands the squad's trigger and aim on to the troopers' weapons, every physics frame.
func _arm_troopers(_delta: float) -> void:
	pass


## Leader walks to `to` on the navmesh (the AI's way of moving it); true once it is there.
func _walk_leader_to(to: Vector3, reach := HOME_REACH) -> bool:
	var d := to - leader.global_position
	d.y = 0.0
	if d.length() > reach:
		leader.following = true
		leader.goal = to
		leader.pace = Vector3.ZERO
		return false
	leader.following = false
	return true


## What the crosshair is on: a ray from the camera through the middle of the screen, past the
## squad's own troopers.
func _camera_aim() -> Vector3:
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var from := _cam.global_position if _cam.is_inside_tree() else leader.global_position + CAM_PIVOT
	var dir := -basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * AIM_RANGE,
			GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS, leader.exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else from + dir * AIM_RANGE


## The formation faces the aim: the camera's yaw when the player drives, else where the squad aims.
func _update_heading(delta: float) -> void:
	var want := cam_yaw
	if not possessed:
		var to := aim_point - leader.global_position
		if Vector2(to.x, to.z).length() > 0.5:
			want = atan2(-to.x, -to.z)
	var off := angle_difference(heading, want)
	if leader.velocity.length() > 0.5 or absf(off) > HEADING_DEADZONE:
		heading = rotate_toward(heading, want, HEADING_RATE * delta)


func _update_followers(delta: float) -> void:
	var followers: Array[SquadTrooper] = []
	for t in troopers:
		if t != leader:
			followers.append(t)
	_solve_cd -= delta
	var solved := false
	if _nav_ready and (_solve_cd <= 0.0 or _spots.size() != followers.size()):
		_solve_cd = SOLVE_INTERVAL
		var at: Array = followers.map(func(f): return f.global_position)
		_spots = formation.solve(leader.global_position, heading, at, SOLVE_INTERVAL, leader.velocity)
		_solve_at = leader.global_position
		solved = true
	var lpos := leader.global_position
	var carry := lpos - _solve_at
	carry.y = 0.0
	# Aiming at something close (the ramp just ahead of the camera, a wall in the face), everyone
	# looks the way the camera looks: turned onto a point that close, the leader would face off its
	# way (and walk on sideways, the troopers' slowest walk).
	var aim_dir := aim_point - (lpos + Vector3.UP * 1.4)
	if possessed:
		aim_dir = Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3.FORWARD
	leader.aim_point = aim_point
	leader.aim_parallel = lpos.distance_to(aim_point) < CONVERGE_MIN
	leader.aim_dir = aim_dir
	var column := formation.column and _spots.size() == followers.size()
	var backs := {}
	for f in followers:
		backs[f] = formation.locate(f.global_position, lpos)
	goals.clear()
	for i in followers.size():
		var f := followers[i]
		if free.has(f):
			f.goal = free[f]
			goals[f] = f.goal
			f.trail_point = Vector3.INF
			_on_trail[f] = false
			f.pace = Vector3.ZERO
			f.following = true
			f.set_priority(0.6)
			continue
		var slot := formation.slot_of(i)
		var back_to := 0.0
		var side := 0.0
		if column:
			# The slot on the trail itself (the spots handed out are only checked against it).
			back_to = formation.slot_back(slot)
			side = formation.slot_side(slot)
			var at: Array = formation.along(back_to, lpos)
			f.goal = at[0] + at[1] * side
			f.set_priority(1.0 - 0.05 * back_to)
		else:
			f.goal = _spots[i] + carry if i < _spots.size() else f.global_position
			f.set_priority(0.85 - 0.05 * slot)
		goals[f] = f.goal
		# Followers walk the leader's trail in a column, and in the open too while a wall stands
		# between them and their spot (the last ones still in the tunnel when the wedge opens out):
		# they come out the way the leader did, then peel off to their spots.
		var walk := column
		if not column:
			if solved or not _walled.has(f):
				_walled[f] = backs[f][0] > 1.0 and backs[f][0] < INF and _walled_off(f, f.goal)
			walk = _walled[f]
		f.trail_point = Vector3.INF
		if _keep_on_trail(f, walk, backs[f], delta):
			_walk_trail(f, back_to, side, backs)
		f.pace = Vector3(leader.velocity.x, 0.0, leader.velocity.z)
		f.following = true
		f.aim_point = aim_point
		# Too close to converge on: look the way the camera looks instead.
		f.aim_parallel = f.global_position.distance_to(aim_point) < CONVERGE_MIN
		f.aim_dir = aim_dir


## Whether follower `f` walks the trail this frame (`want`: the squad would like it to), given
## where it is on it ([back, off]): it takes to the trail close to it and if it can walk straight
## onto it, leaves it when it strays too far, and rests off it a moment after getting caught.
func _keep_on_trail(f: SquadTrooper, want: bool, where: Array, delta: float) -> bool:
	var was: bool = _on_trail.get(f, false)
	_trail_rest[f] = _trail_rest.get(f, 0.0) - delta
	var on: bool = want and where[1] < (TRAIL_LEAVE if was else TRAIL_JOIN) and _trail_rest[f] <= 0.0
	if f.unsticking():
		on = false
		_trail_rest[f] = TRAIL_REST
	elif on and not was:
		on = _straight_onto(f, where[0])
	_on_trail[f] = on
	return on


## Follower on the trail: steer for a point a little further up it (`side` meters to the side of
## it) at a pace that closes on `back_to` meters behind the leader and keeps clear of whoever is
## ahead (the leader, or the next squad mate up the trail).
func _walk_trail(f: SquadTrooper, back_to: float, side: float, backs: Dictionary) -> void:
	var lpos := leader.global_position
	var back: float = backs[f][0]
	var pace := Vector2(leader.velocity.x, leader.velocity.z).length()
	var speed := maxf(pace + (back - back_to) * TRAIL_GAIN, 0.0)
	var room := _flat(f.global_position, lpos)
	for o in backs:
		if o != f and backs[o][0] < back - 0.3:
			room = minf(room, _flat(f.global_position, o.global_position))
	speed *= clampf((room - COLUMN_GAP) / 0.8, 0.0, 1.0)
	var at: Array = formation.along(maxf(back - TRAIL_LOOKAHEAD, 0.0), lpos)
	var p: Vector3 = at[0]
	if side != 0.0:
		# Two abreast: the offset point comes in off a wall onto the navmesh. The trail itself
		# needs no such check (the leader walked it), and mustn't get one: through a gate it runs
		# across the hole the door's plug leaves in the navmesh.
		var beside: Vector3 = p + at[1] * side
		var c := LevelBuilder.nav_closest(get_world_3d().navigation_map, beside + Vector3.UP * 0.5)
		p = c if _flat(c, beside) < 0.6 else p
	f.trail_point = p
	f.trail_speed = speed


## True if a wall (or a tree, a rock) stands between `f` and `spot`.
func _walled_off(f: SquadTrooper, spot: Vector3) -> bool:
	var from := f.global_position + Vector3.UP
	var to := spot + Vector3.UP
	if _flat(from, to) < 1.0:
		return false
	var ball := SphereShape3D.new()
	ball.radius = 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES
	var frac := get_world_3d().direct_space_state.cast_motion(q)
	return frac.size() > 0 and frac[0] < 0.97


## True if `f` can walk about straight onto the trail at `back` (no wall or ledge in between).
func _straight_onto(f: SquadTrooper, back: float) -> bool:
	var map := get_world_3d().navigation_map
	var from := LevelBuilder.nav_closest(map, f.global_position + Vector3.UP * 0.5)
	var at: Array = formation.along(back, leader.global_position)
	var to := LevelBuilder.nav_closest(map, at[0] + Vector3.UP * 0.5)
	var path := LevelBuilder.nav_path(map, from, to, true, formation.nav_layers)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	return not path.is_empty() and length < _flat(from, to) * 1.3 + 0.5


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _open_gates() -> void:
	for g in gates:
		if not is_instance_valid(g) or not g.is_alive():
			continue
		for t in troopers:
			var d: Vector3 = t.global_position - g.global_position
			if Vector2(d.x, d.z).length() < GATE_REACH:
				g.hold_open()
				break


func _update_camera(delta: float) -> void:
	_aim_t = move_toward(_aim_t, 1.0 if input.aim else 0.0, delta * 5.0)
	var target := leader.global_position + CAM_PIVOT
	# A new leader: glide over to it (snap only after a jump, e.g. back at the post).
	_glide = maxf(_glide - delta / 0.9, 0.0)
	var follow := lerpf(10.0, 2.5, _glide)
	if _cam_pivot.distance_to(target) > (25.0 if _glide > 0.0 else 6.0):
		_cam_pivot = target
	else:
		_cam_pivot = _cam_pivot.lerp(target, minf(delta * follow, 1.0))
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var arm := cam_arm.lerp(cam_aim_arm, _aim_t)
	var want := _cam_pivot + basis * arm
	# Pulled in wherever a wall or the tunnel roof is in the way.
	var ball := SphereShape3D.new()
	ball.radius = 0.25
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, _cam_pivot)
	q.motion = want - _cam_pivot
	q.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES
	var frac := get_world_3d().direct_space_state.cast_motion(q)
	var safe := frac[0] if frac.size() > 0 else 1.0
	_cam.global_position = _cam_pivot + (want - _cam_pivot) * safe
	_cam.global_basis = basis
	_cam.fov = lerpf(CAM_FOV, CAM_AIM_FOV, _aim_t)
