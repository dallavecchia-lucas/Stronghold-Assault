class_name DefenderTank
extends DefenderMachine
## The defenders' Iron Vanguard hover tank (the model and its moving parts: HoverTankRig), driven in third person from
## over its right shoulder. Bought with credits (DefenderArmory); it deploys on the ground outside a gate and, once it is
## down, is gone for good.
##
## Driving (like the squads, relative to the camera): WASD to go where the camera looks, left, back or right; the hull turns
## round onto the way it is going (to back off, it reverses instead of turning right round, keeping its gun on the front).
## It hovers on its air cushion, so it skims over the rivers and the lake as it does the ground, but its hull is broad (trees,
## rocks, walls and the mountain stop it, and slopes steeper than it can climb).
##   Mouse: the turret and the gun follow the crosshair (as fast as the turret traverses: TRAVERSE in the rig).
##   LMB: the main gun, once the turret is on the crosshair (CANNON_RELOAD s between rounds): a fast flat-flying shell
##        (TankRound), a heavy blast. The barrel recoils and the hull rocks on its cushion.
##   RMB: hold for the twin machine guns in the sponsons on its sides (they turn onto the crosshair as far as their sponsons
##        allow, and are no good against what is far off to the rear).
## Left alone it holds where it stands and fights what comes within reach, the cannon and the machine guns.

const RigScript := preload("res://scripts/vehicles/hover_tank_rig.gd")

const HP := 1100.0
const MAX_SPEED := 15.0
const REVERSE_SPEED := 7.0
const ACCEL := 8.0
const BRAKE := 14.0
const TURN_RATE := deg_to_rad(95.0)
## Past this angle (rad) between the hull and the way the player wants to go, it reverses instead of turning round.
const REVERSE_ANGLE := deg_to_rad(120.0)
## How wide the hull is for what it bumps into (m), and how high over the ground the feelers sit.
const RADIUS := 3.4
const FEELER_HEIGHT := 1.8
## The slope it can't climb (rise over run), measured over SLOPE_SPAN m.
const SLOPE_MAX := 0.85
const SLOPE_SPAN := 4.0
const CANNON_RELOAD := 3.2
const CANNON_DAMAGE := 220.0
const CANNON_RADIUS := 7.0
## A machine gun round's damage; how far they reach (m).
const MG_DAMAGE := 8.0
const MG_REACH := 400.0
## Camera: the pivot over the hull, the arm out from it (right, up, back), the pitch's limits, the field of view.
const CAM_PIVOT := Vector3(0.0, 3.4, 0.0)
const CAM_ARM := Vector3(3.4, 1.4, 17.0)
const CAM_PITCH_MIN := deg_to_rad(-38.0)
const CAM_PITCH_MAX := deg_to_rad(32.0)
const CAM_FOV := 62.0
const AIM_RANGE := 700.0
## The gun's fire control: a round leaves toward the crosshair's point, not just along the barrel, when the barrel is
## within this many radians of it (the turret counts as on the aim well short of that), so what is under the crosshair is hit.
const FIRE_CONTROL := deg_to_rad(4.0)
## Left alone: how far it picks a target (m, flat), the machine guns' reach, and how often it looks round (s).
const AI_RANGE := 110.0
const AI_MG_RANGE := 65.0
const AI_LOOK := 0.4

var heading := 0.0
var speed := 0.0
var cam_yaw := 0.0
var cam_pitch := deg_to_rad(-9.0)
## What the crosshair is on.
var aim_point := Vector3.ZERO
var rig: RigScript
var cannon_cd := 0.0
## Left alone: what it is shooting at.
var target: Node3D = null
## Where its latest main gun rounds burst (the showcase's checks).
var bursts: Array[Vector3] = []

var _up := Vector3.UP
var _ground_y := 0.0
var _look_cd := 0.0
var _cam_shake := 0.0
var _mg_hits := 0


func _init() -> void:
	station_name = "Hover Tank"
	station_kind = "tank"
	hud_title = "HOVER TANK"
	hp = HP
	max_hp = HP
	target_radius = 3.4
	aim_height = 1.8
	input = {"move": Vector2.ZERO, "fire": false, "aim": false}
	stats = {"rounds": 0, "mg_rounds": 0, "hits": 0, "kills": 0}


func setup(n: int) -> void:
	number = n
	station_name = "Hover Tank" if n <= 1 else "Hover Tank %d" % n
	hud_title = station_name.to_upper()


func roster_label() -> String:
	return "TANK" if number <= 1 else "TANK %d" % number


func order_name() -> String:
	return "HOLD" if is_alive() else "LOST"


func order_color() -> Color:
	return UIKit.ACCENT if possessed else UIKit.WARN


func doing(_driving: bool) -> String:
	if not is_alive():
		return "destroyed"
	if target != null and not possessed:
		return "firing"
	return "%d m/s" % int(absf(speed))


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * aim_height


func _build() -> void:
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.6, 3.0, 9.6)
	box.shape = shape
	box.position.y = 2.0
	add_child(box)
	rig = RigScript.new()
	add_child(rig)
	rig.main_gun_fired.connect(_on_cannon_fired)
	rig.mg_round.connect(_on_mg_round)
	_cam.fov = CAM_FOV
	_place()


func _make_hud() -> Control:
	var hud := TankHud.new()
	hud.tank = self
	return hud


## On the ground where it was bought (DefenderArmory), facing out.
func _place() -> void:
	var at := home.origin
	var out := -home.basis.z
	heading = atan2(out.x, out.z)
	cam_yaw = wrapf(heading + PI, -PI, PI)
	global_position = Vector3(at.x, _hover_height(at), at.z)
	_ground_y = global_position.y
	_apply_pose(0.0)
	aim_point = global_position + _forward() * 50.0 + Vector3.UP * 2.0


## Puts the tank down at `at` facing `new_heading` (rad, 0 = +Z, left +), the camera behind it (for a showcase).
func stage(at: Vector3, new_heading: float) -> void:
	heading = new_heading
	speed = 0.0
	global_position = Vector3(at.x, _hover_height(at), at.z)
	_ground_y = global_position.y
	cam_yaw = wrapf(heading + PI, -PI, PI)
	_apply_pose(0.0)


func _on_possess() -> void:
	# The camera comes up behind the hull, looking where it points.
	cam_yaw = heading + PI
	cam_pitch = deg_to_rad(-9.0)
	_cam_shake = 0.0


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not possessed or pilot != null or _dead or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameConfig.mouse_sensitivity * (_cam.fov / 64.0)
		look(cam_yaw - event.relative.x * sens, cam_pitch - event.relative.y * sens)


func _read_input() -> void:
	input.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input.fire = Input.is_action_pressed("fire")
	input.aim = Input.is_action_pressed("aim")


## Turns the camera (and so the turret's aim) to a yaw and pitch (rad).
func look(yaw: float, pitch: float) -> void:
	cam_yaw = wrapf(yaw, -PI, PI)
	cam_pitch = clampf(pitch, CAM_PITCH_MIN, CAM_PITCH_MAX)


## Turns the camera toward a point in the world (for the showcase pilot).
func look_toward(point: Vector3, rate: float, delta: float) -> void:
	var d := point - _cam.global_position
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	cam_yaw = rotate_toward(cam_yaw, yaw, rate * delta)
	cam_pitch = clampf(rotate_toward(cam_pitch, pitch, rate * 0.6 * delta), CAM_PITCH_MIN, CAM_PITCH_MAX)


# ---------------------------------------------------------------- driving

func _forward() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))


func _control(delta: float) -> void:
	var move: Vector2 = input.move
	var want := Basis(Vector3.UP, cam_yaw) * Vector3(move.x, 0.0, move.y)
	_drive(delta, want)
	aim_point = _camera_aim()
	rig.aim(aim_point)
	_weapons(delta, bool(input.fire), bool(input.aim))


## Drives toward `want` (a flat vector in the world, length 0..1: how hard), turning the hull onto it.
func _drive(delta: float, want: Vector3) -> void:
	var mag := minf(want.length(), 1.0)
	var want_speed := 0.0
	if mag > 0.05:
		var goal := atan2(want.x, want.z)
		var diff := angle_difference(heading, goal)
		var reverse := absf(diff) > REVERSE_ANGLE
		if reverse:
			diff = angle_difference(heading, goal + PI)
		heading = wrapf(heading + clampf(diff, -TURN_RATE * delta, TURN_RATE * delta), -PI, PI)
		var align := clampf(cos(diff), 0.0, 1.0)
		want_speed = (-REVERSE_SPEED if reverse else MAX_SPEED) * mag * (0.25 + 0.75 * align)
	var rate := ACCEL if absf(want_speed) > absf(speed) else BRAKE
	speed = move_toward(speed, want_speed, rate * delta)
	_move(delta)


## One step of motion along the hull: stopped by what is in the way, sliding along it, riding the ground.
func _move(delta: float) -> void:
	var motion := _forward() * speed * delta
	if motion.length() > 0.0005:
		motion = _slide(motion)
		var p := global_position + motion
		if _slope(p, motion) > SLOPE_MAX:
			motion = Vector3.ZERO
			speed = 0.0
		var edge := map_half - 20.0
		var q := global_position + motion
		if absf(q.x) > edge or absf(q.z) > edge:
			motion = Vector3.ZERO
			speed = 0.0
		global_position += motion
	var want_y := _hover_height(global_position)
	_ground_y = lerpf(_ground_y, want_y, 1.0 - exp(-10.0 * delta))
	global_position.y = _ground_y
	_apply_pose(delta)
	velocity = _forward() * speed


## The ground it hovers over at `p` (the water's surface over a river: it skims it).
func _hover_height(p: Vector3) -> float:
	return maxf(LevelBuilder.ground_height(p), JungleLayout.WATER_Y)


## How steep the ground is ahead along `motion` (rise over run) at `p`.
func _slope(p: Vector3, motion: Vector3) -> float:
	var d := motion.normalized()
	var here := _hover_height(p)
	var ahead := _hover_height(p + d * SLOPE_SPAN)
	return (ahead - here) / SLOPE_SPAN


## `motion` (flat) cut short by what the hull would hit, the rest slid along the wall. Five feelers fan out across its front.
func _slide(motion: Vector3) -> Vector3:
	var length := motion.length()
	var dir := motion / length
	var side := dir.cross(Vector3.UP).normalized()
	var space := get_world_3d().direct_space_state
	var best := length
	var wall := Vector3.ZERO
	var y := global_position.y + FEELER_HEIGHT
	for off: float in [-RADIUS, -RADIUS * 0.5, 0.0, RADIUS * 0.5, RADIUS]:
		var from := Vector3(global_position.x, y, global_position.z) + side * off
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * (length + RADIUS), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var free := from.distance_to(hit.position) - RADIUS
		if free < best:
			best = maxf(free, 0.0)
			wall = hit.normal
	if best >= length:
		return motion
	var along := dir * best
	wall.y = 0.0
	if wall.length() < 0.01:
		speed = 0.0
		return along
	wall = wall.normalized()
	var rest := motion - along
	rest -= wall * minf(rest.dot(wall), 0.0)
	# Hit head on, it stops; clipping a wall, it slides along it.
	if absf(dir.dot(wall)) > 0.9:
		speed = 0.0
	return along + rest * 0.6


## The hull sits on the ground's slope: up along its normal, nose along the way it is going.
func _apply_pose(delta: float) -> void:
	var p := global_position
	var h := 3.5
	var dx := _hover_height(p + Vector3(h, 0, 0)) - _hover_height(p - Vector3(h, 0, 0))
	var dz := _hover_height(p + Vector3(0, 0, h)) - _hover_height(p - Vector3(0, 0, h))
	var normal := Vector3(-dx, 2.0 * h, -dz).normalized()
	_up = normal if delta <= 0.0 else _up.slerp(normal, 1.0 - exp(-6.0 * delta)).normalized()
	var z := (_forward() - _up * _forward().dot(_up)).normalized()
	var x := _up.cross(z).normalized()
	global_basis = Basis(x, _up, z)


## What the crosshair is on: a ray from the camera through the middle of the screen, past the tank itself.
func _camera_aim() -> Vector3:
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var from := _cam.global_position
	var dir := -basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * AIM_RANGE,
			GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else from + dir * AIM_RANGE


# ---------------------------------------------------------------- weapons

func _weapons(delta: float, fire: bool, mgs: bool) -> void:
	cannon_cd = maxf(cannon_cd - delta, 0.0)
	if fire and cannon_cd <= 0.0 and rig.aimed():
		fire_cannon()
	rig.mg_firing = mgs and not _dead


## Fires the main gun: false while it reloads.
func fire_cannon() -> bool:
	if cannon_cd > 0.0 or _dead:
		return false
	cannon_cd = CANNON_RELOAD
	rig.fire()
	return true


func _on_cannon_fired(muzzle: Transform3D) -> void:
	stats.rounds += 1
	var shell := TankRound.new()
	shell.team = team
	shell.damage = CANNON_DAMAGE
	shell.radius = CANNON_RADIUS
	get_tree().current_scene.add_child(shell)
	var dir := muzzle.basis.z
	var to := aim_point - muzzle.origin
	if to.length() > 5.0 and dir.angle_to(to) < FIRE_CONTROL:
		dir = to.normalized()
	shell.fire(muzzle.origin, dir)
	shell.burst.connect(func(at: Vector3):
		bursts.append(at)
		if bursts.size() > 16:
			bursts.pop_front())
	if possessed:
		_cam_shake = 0.35


## A machine gun round left its muzzle for `to`: what it hits first takes MG_DAMAGE.
func _on_mg_round(from: Vector3, to: Vector3) -> void:
	stats.mg_rounds += 1
	var dir := (to - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * MG_REACH, GameConfig.LAYER_ALL_SOLID & ~GameConfig.LAYER_DEFENDERS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var d := Combat.find_damageable(hit.collider)
	var hurt := false
	if d != null and d.team != team and d.is_alive():
		d.take_damage(MG_DAMAGE * (0.5 if d.is_in_group("structures") else 1.0), team)
		hurt = true
		stats.hits += 1
	_mg_hits += 1
	if hurt or _mg_hits % 3 == 0:
		Combat.spawn_impact(self, hit.position, hurt, hit.normal)


# ---------------------------------------------------------------- left alone

func _idle(delta: float) -> void:
	# Holds where it stands (the hull settles on its cushion).
	speed = move_toward(speed, 0.0, BRAKE * delta)
	_move(delta)
	_look_cd -= delta
	if _look_cd <= 0.0:
		_look_cd = AI_LOOK
		target = _pick_target()
	cannon_cd = maxf(cannon_cd - delta, 0.0)
	if target == null or not Combat.is_valid_target(target):
		target = null
		rig.stow()
		rig.mg_firing = false
		return
	var at := Combat.aim_point(target)
	aim_point = at
	rig.aim(at)
	var dist := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if rig.aimed() and cannon_cd <= 0.0:
		fire_cannon()
	rig.mg_firing = dist < AI_MG_RANGE


## The nearest attacker on the ground in reach that it can see.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := AI_RANGE
	var from := global_position + Vector3.UP * 3.0
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if not u.is_alive() or u.is_flying() or u.is_submerged():
			continue
		var d := Vector2(u.global_position.x - global_position.x, u.global_position.z - global_position.z).length()
		if d < best_d and Combat.has_line_of_sight(self, from, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best


# ---------------------------------------------------------------- going down

func _on_down(_reason: String) -> void:
	rig.mg_firing = false
	_cam_shake = 0.8
	say("DESTROYED", 3.0)
	speed = 0.0
	var fx := FX.of(self)
	fx.blast(global_position + Vector3.UP * 2.0, 8.0)
	for n in 12:
		var d := Vector3(randf_range(-1, 1), randf_range(0.5, 1.6), randf_range(-1, 1)).normalized()
		fx.debris(global_position + Vector3.UP * 2.0, d * randf_range(6.0, 22.0), randf_range(0.5, 1.3), randf_range(3.0, 6.0),
				Color(0.32, 0.34, 0.36), 0.9, 0.35, global_position.y)
	var wreck := WreckSmoke.new()
	wreck.size = 2.2
	wreck.rate = 12.0
	wreck.emitting = true
	get_tree().current_scene.add_child(wreck)
	wreck.global_position = global_position + Vector3.UP * 1.5
	get_tree().create_timer(25.0).timeout.connect(wreck.queue_free)
	rig.visible = false


func _wreck(delta: float) -> void:
	_cam_shake = maxf(_cam_shake - delta, 0.0)


# ---------------------------------------------------------------- camera

func _chase_camera(delta: float) -> void:
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var pivot := global_position + CAM_PIVOT
	var want := pivot + basis * CAM_ARM
	var q := PhysicsRayQueryParameters3D.create(pivot, want, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_cam.global_position = want
	else:
		_cam.global_position = hit.position + hit.normal * 0.6
	if _cam_shake > 0.0:
		var s := _cam_shake * 0.35
		_cam.global_position += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
		_cam_shake = maxf(_cam_shake - delta * 2.5, 0.0)
	_cam.global_basis = basis


func get_hud_info() -> Dictionary:
	var cannon := "CANNON READY" if cannon_cd <= 0.0 else "CANNON %.1fs" % cannon_cd
	return {"weapon": cannon, "status": "%d m/s" % int(absf(speed)), "hp": clampf(hp / max_hp, 0.0, 1.0),
			"hint": "WASD drive (camera-relative) · mouse aim the turret · LMB cannon · hold RMB machine guns"}
