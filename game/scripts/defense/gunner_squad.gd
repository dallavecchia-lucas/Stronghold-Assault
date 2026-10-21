class_name GunnerSquad
extends Node3D
## Gunner Squad: five minigunners in heavy armor (HeavyGunner), a defender post the player takes
## over in third person. The player drives the trooper in the middle of the formation; the other
## four follow it (SquadFormation: a wedge in the open, squeezing in and filing behind the leader
## through tunnels, around trees and rocks) and aim and fire wherever the player aims and fires.
## Blast doors open for the squad as it comes up to them (Structure.hold_open), so it can sally
## out through a standing gate. Left to itself the squad goes back to its post and holds it,
## shooting at any attacker it can see. Lost troopers are replaced one at a time from the post;
## when all five are down the squad is gone for RESPAWN_TIME.
##
## Station interface: see DefenderController.

signal became_unavailable(station)

const SIZE := 5
const RESPAWN_TIME := 30.0
const REINFORCE_TIME := 20.0
const AI_RANGE := 45.0
## Left to itself the squad hits this much softer, like the other posts' crews.
const AI_DAMAGE_SCALE := 0.3
## Seconds between formation solves; in between, the spots ride along with the leader.
const SOLVE_INTERVAL := 0.15
## The formation turns to face the aim at up to this rate; standing still it ignores small turns.
const HEADING_RATE := deg_to_rad(110.0)
const HEADING_DEADZONE := deg_to_rad(20.0)
## Aim points closer than this are looked at side by side instead of converged on.
const CONVERGE_MIN := 8.0
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

var station_name := "Gunner Squad"
var station_kind := "squad"
var team := GameConfig.TEAM_DEFENDER
var possessed := false
## The squad's post: where it holds and respawns, facing its -Z.
var home := Transform3D.IDENTITY
## Gates the squad opens on its way through.
var gates: Array = []
var troopers: Array[HeavyGunner] = []
var leader: HeavyGunner = null
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

var hp: float:
	get:
		var s := 0.0
		for t in troopers:
			s += maxf(t.hp, 0.0)
		return s
var max_hp: float:
	get:
		return SIZE * HeavyGunner.MAX_HP

var cam_yaw := 0.0
var cam_pitch := deg_to_rad(-12.0)
var _cam: Camera3D
var _cam_pivot := Vector3.ZERO
var _aim_t := 0.0
var _hud: SquadHud
var _solve_cd := 0.0
var _solve_at := Vector3.ZERO
var _spots: Array[Vector3] = []
var _respawn_cd := 0.0
var _reinforce_cd := 0.0
var _retarget_cd := 0.0
var _target: Node3D = null
var _nav_ready := false


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
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	layer.add_child(_hud)
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
	if leader == null:
		return {"weapon": "Minigun", "status": "—", "hp": 0.0, "hint": ""}
	var status := "HEAT %d%%" % int(leader.heat * 100.0)
	if leader.overheated():
		status = "OVERHEATED"
	elif firing and not leader.spun_up():
		status = "SPINNING UP"
	return {"weapon": "Minigun · %d/%d · %s" % [troopers.size(), SIZE, SquadFormation.MODE_NAMES[formation.mode]],
			"status": status, "heat": leader.heat, "hp": leader.hp / leader.max_hp,
			"hint": "WASD move · Shift hustle · Mouse aim · LMB fire · RMB aim · the squad follows your lead"}


# ---------------------------------------------------------------- troopers

func _spawn_all() -> void:
	# In a line behind the post until the navmesh is up and the formation can be worked out.
	for i in SIZE:
		_spawn(home.origin + home.basis.z * (float(i) * SquadFormation.TRAIL_SPACING))
	_pick_leader()


func _spawn(at: Vector3) -> HeavyGunner:
	var t := HeavyGunner.new()
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


func _on_trooper_died(t: HeavyGunner) -> void:
	troopers.erase(t)
	goals.erase(t)
	if t == leader:
		leader = null
		_pick_leader(t.global_position)
	if troopers.is_empty():
		_respawn_cd = RESPAWN_TIME
		firing = false
		became_unavailable.emit(self)
	elif _reinforce_cd <= 0.0:
		_reinforce_cd = REINFORCE_TIME


## The trooper nearest `near` (the fallen leader, or the post) takes the lead.
func _pick_leader(near = null) -> void:
	if troopers.is_empty():
		return
	var at: Vector3 = near if near != null else home.origin
	var best: HeavyGunner = null
	for t in troopers:
		if best == null or t.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = t
	leader = best
	for t in troopers:
		t.set_leader(t == leader)
	formation.trail.clear()


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if troopers.is_empty():
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
				and NavigationServer3D.map_get_closest_point(map, home.origin + Vector3.UP) != Vector3.ZERO
	if possessed:
		_player_control(delta)
	else:
		_ai_control(delta)
	_update_heading(delta)
	formation.record(leader.global_position, leader.velocity)
	_update_followers(delta)
	for t in troopers:
		t.trigger = firing
		t.damage_scale = 1.0 if possessed else AI_DAMAGE_SCALE
	_open_gates()
	if troopers.size() < SIZE:
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


func _player_control(delta: float) -> void:
	if pilot != null:
		pilot.pilot_input(self, delta)
	else:
		input.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		input.fire = Input.is_action_pressed("fire")
		input.aim = Input.is_action_pressed("aim")
		input.hustle = Input.is_action_pressed("sprint")
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
	firing = input.fire and not hustle
	aim_point = _camera_aim()


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


## Left alone: back to the post and hold it, shooting at the nearest attacker in sight.
func _ai_control(delta: float) -> void:
	for t in troopers:
		t.hustle = false
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.5
		_target = _find_target()
	var to_home := home.origin - leader.global_position
	to_home.y = 0.0
	if to_home.length() > HOME_REACH:
		leader.following = true
		leader.goal = home.origin
		leader.pace = Vector3.ZERO
	else:
		leader.following = false
	if Combat.is_valid_target(_target):
		aim_point = Combat.aim_point(_target)
		firing = true
	else:
		firing = false
		var ahead := Basis(Vector3.UP, heading) * Vector3.FORWARD
		var look := home.basis * Vector3.FORWARD if to_home.length() <= HOME_REACH else ahead
		if to_home.length() > HOME_REACH and leader.velocity.length() > 0.3:
			look = Vector3(leader.velocity.x, 0.0, leader.velocity.z).normalized()
		aim_point = leader.global_position + Vector3.UP * 1.4 + look * 30.0


func _find_target() -> Node3D:
	var eye := leader.global_position + Vector3.UP * 1.8
	var best: Node3D = null
	var best_d := AI_RANGE
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var d := leader.global_position.distance_to(u.global_position)
		if d < best_d and Combat.has_line_of_sight(self, eye, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best


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
	var followers: Array[HeavyGunner] = []
	for t in troopers:
		if t != leader:
			followers.append(t)
	_solve_cd -= delta
	if _nav_ready and (_solve_cd <= 0.0 or _spots.size() != followers.size()):
		_solve_cd = SOLVE_INTERVAL
		var at: Array = followers.map(func(f): return f.global_position)
		_spots = formation.solve(leader.global_position, heading, at, SOLVE_INTERVAL)
		_solve_at = leader.global_position
	var carry := leader.global_position - _solve_at
	carry.y = 0.0
	var aim_dir := aim_point - (leader.global_position + Vector3.UP * 1.4)
	leader.aim_point = aim_point
	leader.aim_parallel = false
	goals.clear()
	for i in followers.size():
		var f := followers[i]
		if i < _spots.size():
			f.goal = _spots[i] + carry
			goals[f] = f.goal
		else:
			f.goal = f.global_position
		f.pace = Vector3(leader.velocity.x, 0.0, leader.velocity.z)
		f.following = true
		f.aim_point = aim_point
		# Too close to converge on (a wall in the face): all look the leader's way instead.
		f.aim_parallel = f.global_position.distance_to(aim_point) < CONVERGE_MIN
		f.aim_dir = aim_dir


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
	_cam_pivot = target if _cam_pivot.distance_to(target) > 6.0 else _cam_pivot.lerp(target, minf(delta * 10.0, 1.0))
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var arm := CAM_ARM.lerp(CAM_AIM_ARM, _aim_t)
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
