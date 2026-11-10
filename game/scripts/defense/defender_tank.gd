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
##   LMB: the main gun, once the turret is on the crosshair (CANNON_RELOAD s between rounds): a shell that flies a gentle arc
##        (TankRound: gravity drags at it, so against a far target the crosshair has to be held above it), with a tracer
##        that leaves a trail along the arc to adjust by, and a heavy blast. The barrel recoils and the hull rocks on its cushion.
##   RMB: hold for the twin machine guns in the sponsons on its sides. They do not follow the crosshair: they fire straight
##        ahead along where the hull faces (a mark on the screen shows where), their tracers ending where each round hits.
##   Space: the jump, for a sticky situation: the thrusters charge (the hull squats, the jets flare and dust blows out), then throw
##        it up and along where the hull faces in an arc (JUMP_UP up, JUMP_SPEED along: about 12 m high and 55 m far, over
##        three seconds); coming down the jets fire again, a retro burn that sets it down softly, the hull squatting to take
##        the last of the shock. It can't be steered in the air, and fires its guns as ever. JUMP_COOLDOWN s before the next.
## Trees: it runs into a tree and stops, like a small crash (some damage, the hull rocks, the camera shakes), and the tree goes
## over (ForestTree.knock_down): its trunk still blocks until it is down, TOPPLE_TIME s later, and only then can the tank go on.
## Crossing woodland is possible, but it costs seconds and health tree after tree: no way to take a tank to the other side.
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
## The jump: the charge before it leaves the ground (s), its launch speed along the hull and up (m/s), the pull that brings it
## down (m/s², a little over a gun-metre's worth: it is a stylised arc), the cooldown (s), how long the landing takes to settle
## (s). Coming down it fires a retro burn from RETRO_HEIGHT m up: the descent is held to 3 m/s plus 1.4 m/s a metre up,
## braked at RETRO_ACCEL m/s². Down, it looks for clear ground to set down on (the stronghold's wall or a tree under where it
## would land puts it down in front of them instead).
const JUMP_CHARGE := 0.45
const JUMP_SPEED := 18.0
const JUMP_UP := 18.5
const JUMP_GRAVITY := 14.2
const JUMP_COOLDOWN := 10.0
const LAND_TIME := 0.5
const RETRO_HEIGHT := 8.0
const RETRO_ACCEL := 40.0
## Running into a tree: the damage (at a crawl, and at full speed), how long the tree takes to go over (s: the tank is held up
## against it that long), and how long after the crash the tank is stunned (s: it can't pull away forward).
const TREE_DAMAGE_MIN := 45.0
const TREE_DAMAGE_MAX := 95.0
const TREE_TOPPLE := 3.8
const TREE_STUN := 1.4
## The barrel must be this close (rad) to the line to the crosshair's point before the main gun fires: it is laid properly.
const LAYING := deg_to_rad(0.7)
## How far ahead of the hull the machine guns' mark is drawn (m), and every how many machine gun rounds a tracer.
const MG_MARK := HoverTankRig.MG_CONVERGE
const MG_TRACER_EVERY := 2
const MG_TRACER := Color(8.0, 5.2, 1.4)
## A machine gun tracer: how fast it streaks (m/s), how wide (m) and how long (m).
const MG_TRACER_SPEED := 300.0
const MG_TRACER_WIDTH := 0.3
const MG_TRACER_LENGTH := 8.0
## And the line it leaves: a glowing dot every MG_TRAIL_STEP metres along its path, laid down as the round passes and fading
## over MG_TRAIL_LIFE seconds, so the line the guns are firing along stays drawn on the air even when the round itself is a speck.
const MG_TRAIL_STEP := 2.2
const MG_TRAIL_LIFE := 0.5
const MG_TRAIL := Color(3.2, 1.9, 0.6)
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
enum Jump { NONE, CHARGE, AIR, LAND }

## The jump: what it is doing, seconds until the next, and the velocity in the air.
var jump_state := Jump.NONE
var jump_cd := 0.0
var air_velocity := Vector3.ZERO

var _jump_t := 0.0
var _dust_cd := 0.0
var _stunned := 0.0
var _hit_tree: ForestTree = null
var _cam_shake := 0.0
var _mg_hits := 0
var _mg_tracer_n := 0


func _init() -> void:
	station_name = "Hover Tank"
	station_kind = "tank"
	hud_title = "HOVER TANK"
	hp = HP
	max_hp = HP
	target_radius = 3.4
	aim_height = 1.8
	input = {"move": Vector2.ZERO, "fire": false, "aim": false, "jump": false}
	stats = {"rounds": 0, "mg_rounds": 0, "hits": 0, "kills": 0, "jumps": 0, "trees": 0, "tracers": 0}


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
	rig.gun_stabilised = true  # the barrel holds its line against the hull's sway: a far shot is a matter of aim, not of luck
	rig.mg_fixed = true  # the machine guns fire along the hull, not at the crosshair
	rig.mg_tracers = false  # their tracers are drawn here, to where each round ends
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
	input.jump = Input.is_action_just_pressed("jump")


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
	if bool(input.jump):
		try_jump()
	# Charging or in the air it can't be driven.
	if not _update_jump(delta):
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
	# Just run into a tree: it can't pull away forward until it has come to.
	if _stunned > 0.0 and want_speed > 0.0:
		want_speed = 0.0
	var rate := ACCEL if absf(want_speed) > absf(speed) else BRAKE
	speed = move_toward(speed, want_speed, rate * delta)
	_move(delta)


## One step of motion along the hull: stopped by what is in the way, sliding along it, riding the ground.
func _move(delta: float) -> void:
	var motion := _forward() * speed * delta
	if motion.length() > 0.0005:
		motion = _slide(motion)
		if _hit_tree != null:
			_hit_a_tree(_hit_tree, _forward() * signf(speed))
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
	var struck: Object = null
	_hit_tree = null
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
			struck = hit.collider
	if best >= length:
		return motion
	var along := dir * best
	# A tree stops it dead, however it is hit (it doesn't slide past a trunk).
	if struck is ForestTree and (struck as ForestTree).is_standing():
		_hit_tree = struck as ForestTree
		return along
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
	if jump_state == Jump.AIR:
		# In the air the nose follows the arc: up on the way up, down on the way down.
		var pitch := clampf(atan2(air_velocity.y, maxf(Vector2(air_velocity.x, air_velocity.z).length(), 4.0)) * 0.45, -0.4, 0.45)
		var f := _forward()
		var zz := (f * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
		var xx := Vector3.UP.cross(zz).normalized()
		_up = zz.cross(xx).normalized()
		global_basis = Basis(xx, _up, zz)
		return
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
	if fire and cannon_cd <= 0.0 and on_aim():
		fire_cannon()
	rig.mg_firing = mgs and not _dead


## Is the main gun laid on the crosshair's point: the turret on it and the barrel along the line to it to within LAYING.
func on_aim() -> bool:
	if not rig.aimed():
		return false
	var muzzle := rig.muzzle()
	var to := aim_point - muzzle.origin
	return to.length() < 6.0 or muzzle.basis.z.angle_to(to) < LAYING


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
	shell.fire(muzzle.origin, muzzle.basis.z)
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
	# A tracer every other round, out to where it ends: what it hits, or the end of its reach.
	_mg_tracer_n += 1
	if _mg_tracer_n % MG_TRACER_EVERY == 0:
		stats.tracers += 1
		var end: Vector3 = hit.position if not hit.is_empty() else from + dir * MG_REACH
		var span := from.distance_to(end)
		if span > 1.0:
			var fx := FX.of(self)
			fx.spark(from, dir * MG_TRACER_SPEED, span / MG_TRACER_SPEED, MG_TRACER_WIDTH, MG_TRACER_LENGTH, MG_TRACER, 0.0, 0.0,
					FX.NO_FLOOR, 0.0, 0.0, 2)
			for k in int(span / MG_TRAIL_STEP):
				var d := (k + 1) * MG_TRAIL_STEP
				fx.spark(from + dir * d, dir * 0.3, MG_TRAIL_LIFE, 0.2, 0.7, MG_TRAIL, 0.0, 0.0, FX.NO_FLOOR, 0.0, 1.0, 0, d / MG_TRACER_SPEED)
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


# ---------------------------------------------------------------- the jump

## Starts a jump along where the hull faces: false if it is still charging or in the air, on cooldown or down.
func try_jump() -> bool:
	if _dead or jump_state != Jump.NONE or jump_cd > 0.0:
		return false
	jump_state = Jump.CHARGE
	_jump_t = 0.0
	_dust_cd = 0.0
	return true


## The jump's stages, every frame; true while it has the tank (charging, in the air), so it isn't driven.
func _update_jump(delta: float) -> bool:
	jump_cd = maxf(jump_cd - delta, 0.0)
	_stunned = maxf(_stunned - delta, 0.0)
	match jump_state:
		Jump.CHARGE:
			_charge(delta)
			return true
		Jump.AIR:
			_fly_air(delta)
			return true
		Jump.LAND:
			_jump_t += delta
			rig.thrust_boost = move_toward(rig.thrust_boost, 0.0, 2.6 * delta)
			rig.crouch = move_toward(rig.crouch, 0.0, 2.8 * delta)
			rig.gimbal_hold = move_toward(rig.gimbal_hold, 0.0, 3.0 * delta)
			if _jump_t >= LAND_TIME:
				jump_state = Jump.NONE
			return false
	rig.thrust_boost = move_toward(rig.thrust_boost, 0.0, 3.0 * delta)
	rig.crouch = move_toward(rig.crouch, 0.0, 3.0 * delta)
	rig.gimbal_hold = move_toward(rig.gimbal_hold, 0.0, 3.0 * delta)
	return false


## Before it leaves the ground: the thrusters spool up, the jets flare, the hull squats, and dust blows out from under it.
func _charge(delta: float) -> void:
	_jump_t += delta
	var k := clampf(_jump_t / JUMP_CHARGE, 0.0, 1.0)
	rig.thrust_boost = k * 0.8
	rig.crouch = k
	rig.gimbal_hold = 1.0
	speed = move_toward(speed, 0.0, BRAKE * delta)
	_move(delta)
	_dust_cd -= delta
	if _dust_cd <= 0.0:
		_dust_cd = 0.07
		_kick_dust(0.25 + 0.6 * k)
	if possessed:
		_cam_shake = maxf(_cam_shake, 0.08 + 0.22 * k)
	if _jump_t >= JUMP_CHARGE:
		_launch()


## The burst: the thrusters throw the hull up and along where it faces (a little of any speed it had comes along).
func _launch() -> void:
	var carry := maxf(speed, 0.0) * 0.4
	air_velocity = _forward() * (JUMP_SPEED + carry) + Vector3.UP * JUMP_UP
	jump_state = Jump.AIR
	_jump_t = 0.0
	jump_cd = JUMP_COOLDOWN
	stats.jumps += 1
	rig.thrust_boost = 1.0
	rig.crouch = 0.0
	_kick_dust(1.0)
	_shock_ring(1.0)
	for pad in ["FL", "FR", "RL", "RR"]:
		FX.of(self).flare(rig.marker("jet_" + pad).origin, Color(2.5, 3.4, 6.0), 0.9, 4.0, 0.25, 0, 2.0)
	if possessed:
		_cam_shake = 0.7


## In the air: gravity, a retro burn set off on the way down to soften the landing, and the hull's motion along the arc stopped by
## whatever it flies into (a trunk, a wall). It can't be steered.
func _fly_air(delta: float) -> void:
	_jump_t += delta
	var ground := _hover_height(global_position)
	var height := global_position.y - ground
	air_velocity.y -= JUMP_GRAVITY * delta
	if air_velocity.y < 0.0 and height < RETRO_HEIGHT:
		# The retro burn: the jets fire down, the descent is braked.
		air_velocity.y = move_toward(air_velocity.y, -(3.0 + height * 1.4), RETRO_ACCEL * delta)
		rig.thrust_boost = move_toward(rig.thrust_boost, 0.9, 6.0 * delta)
		rig.gimbal_hold = move_toward(rig.gimbal_hold, 1.0, 6.0 * delta)
	else:
		rig.thrust_boost = move_toward(rig.thrust_boost, 0.15 if _jump_t > 0.4 else 1.0, 2.5 * delta)
		rig.gimbal_hold = move_toward(rig.gimbal_hold, 0.5, 4.0 * delta)
	var flat := Vector3(air_velocity.x, 0.0, air_velocity.z) * delta
	if flat.length() > 0.001:
		var moved := _slide(flat)
		if _hit_tree != null:
			_hit_a_tree(_hit_tree, flat)
		var edge := map_half - 20.0
		var q := global_position + moved
		if absf(q.x) > edge or absf(q.z) > edge:
			moved = Vector3.ZERO
		if moved.length() < flat.length() * 0.6:
			air_velocity.x = 0.0
			air_velocity.z = 0.0
		global_position += moved
	global_position.y += air_velocity.y * delta
	speed = Vector2(air_velocity.x, air_velocity.z).length()
	_apply_pose(delta)
	if air_velocity.y < 0.0 and global_position.y <= ground:
		_touch_down(ground)


## Is there something solid under the hull's footprint at `p` (the stronghold's wall or slope, a tree's trunk) that the ground
## it hovers over doesn't show?
func _solid_below(p: Vector3) -> bool:
	var ground := _hover_height(p)
	var side := _forward().cross(Vector3.UP).normalized()
	var space := get_world_3d().direct_space_state
	for off in [Vector3.ZERO, side * 2.6, -side * 2.6]:
		var at: Vector3 = p + off
		var from := Vector3(at.x, ground + 16.0, at.z)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 20.0, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.position.y > _hover_height(at) + 1.0:
			return true
	return false


## Down: the retro burn's last blast and a ring of dust, the hull squatting on its cushion to take the shock.
func _touch_down(ground: float) -> void:
	# Over a wall or a tree it would come down in: set down on clear ground in front of it instead.
	if _solid_below(global_position):
		var back := -Vector3(air_velocity.x, 0.0, air_velocity.z)
		back = back.normalized() if back.length() > 0.1 else -_forward()
		for k in range(1, 25):
			var p := global_position + back * 2.0 * k
			if not _solid_below(p):
				global_position = Vector3(p.x, global_position.y, p.z)
				ground = _hover_height(global_position)
				break
		air_velocity.x = 0.0
		air_velocity.z = 0.0
	global_position.y = ground
	_ground_y = ground
	speed = minf(Vector2(air_velocity.x, air_velocity.z).length() * 0.3, 7.0)
	air_velocity = Vector3.ZERO
	jump_state = Jump.LAND
	_jump_t = 0.0
	rig.thrust_boost = 1.0
	rig.crouch = 1.0
	rig.gimbal_hold = 1.0
	_up = Vector3.UP
	_apply_pose(0.0)
	_kick_dust(1.2)
	_shock_ring(0.8)
	if possessed:
		_cam_shake = 0.5


## Dust blown out from under each hover jet: `power` 1 is a launch's.
func _kick_dust(power: float) -> void:
	var fx := FX.of(self)
	var ground := _hover_height(global_position)
	for pad in ["FL", "FR", "RL", "RR"]:
		var m := rig.marker("jet_" + pad).origin
		var base := Vector3(m.x, ground + 0.25, m.z)
		for k in 3 + int(4.0 * power):
			var a := randf() * TAU
			var out := Vector3(cos(a), 0.0, sin(a))
			fx.smoke(base + out * 0.6, out * randf_range(3.0, 8.0) * power + Vector3.UP * randf_range(0.4, 1.6), randf_range(1.2, 2.2),
					0.7, randf_range(3.0, 5.5) * (0.6 + 0.5 * power), Color(0.55, 0.49, 0.4, 0.5), 0.25, 1.3, 0.0, 0.6)


## A ring of shock racing out along the ground from under the hull.
func _shock_ring(power: float) -> void:
	var ground := _hover_height(global_position)
	FX.of(self).warp(Vector3(global_position.x, ground + 0.3, global_position.z), 2.0, 14.0 * power, 0.45, 1, 0.05)


# ---------------------------------------------------------------- trees

## It has run into a standing tree (going `dir`): a small crash. The tree goes over, and its trunk blocks until it is down; the tank
## stops, is rocked and shaken, and loses a little health (more the faster it was going). Nothing happens twice for a tree that
## is already going over: it is just in the way.
func _hit_a_tree(tree: ForestTree, dir: Vector3) -> void:
	_hit_tree = null
	if not tree.is_standing() or tree.is_toppling():
		speed = 0.0
		return
	var impact := maxf(absf(speed), Vector2(air_velocity.x, air_velocity.z).length())
	var f := clampf(impact / MAX_SPEED, 0.2, 1.0)
	if not tree.knock_down(dir, TREE_TOPPLE):
		speed = 0.0
		return
	stats.trees += 1
	hurt_self(lerpf(TREE_DAMAGE_MIN, TREE_DAMAGE_MAX, f))
	rig.bump(f)
	speed = -minf(impact * 0.25, 3.5)
	_stunned = TREE_STUN
	if possessed:
		_cam_shake = 0.3 + 0.5 * f
	# Splinters, leaves and dust where it struck.
	var fx := FX.of(self)
	var at := tree.global_position + Vector3.UP * 1.5
	for k in 10:
		fx.smoke(at + Vector3(randf_range(-1, 1), randf_range(0, 2), randf_range(-1, 1)), Vector3(randf_range(-4, 4), randf_range(1, 4), randf_range(-4, 4)),
				randf_range(1.0, 2.0), 0.4, randf_range(1.5, 3.0), Color(0.36, 0.42, 0.22, 0.55), 0.2, 1.0, 0.0, 0.5)


# ---------------------------------------------------------------- left alone

func _idle(delta: float) -> void:
	# Holds where it stands (the hull settles on its cushion); a jump it was in carries on.
	if not _update_jump(delta):
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
	var dist := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	# Left to itself it holds the barrel above the target by what the shell will drop on the way.
	at += Vector3.UP * TankRound.drop_at(dist)
	aim_point = at
	rig.aim(at)
	if on_aim() and cannon_cd <= 0.0:
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
	# Destroyed in the air, it still comes down.
	if jump_state == Jump.AIR:
		_fly_air(delta)


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


## Where the machine guns are pointing: where their lines cross, MG_MARK m out from between their muzzles along the hull (world).
func mg_point() -> Vector3:
	var a := rig.marker("mg_muzzle_L1")
	var b := rig.marker("mg_muzzle_R1")
	var at := (a.origin + b.origin) * 0.5 + rig.global_basis.z * MG_MARK
	at.y = global_position.y + HoverTankRig.MG_ZERO_HEIGHT
	return at


func get_hud_info() -> Dictionary:
	var cannon := "CANNON READY" if cannon_cd <= 0.0 else "CANNON %.1fs" % cannon_cd
	return {"weapon": cannon, "status": "%d m/s" % int(absf(speed)), "hp": clampf(hp / max_hp, 0.0, 1.0),
			"hint": "WASD drive (camera-relative) · mouse aim the turret (aim above far targets) · LMB cannon · hold RMB machine guns (fire along the hull) · Space jump"}
