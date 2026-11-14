class_name MountedGun
extends StaticBody3D
## Gun emplacement on the walls. Faces its node's -Z axis at rest. Three kinds (`kind`):
##   "sentry"  the Orbital Sentry Gun on the gun decks: a gatling, fast and light.
##   "cannon"  the Arctic Sentinel Cannon on the gun decks: a shell every CANNON_INTERVAL (CannonShell) that flies flat
##             at first and then falls, so far targets need the barrel raised (the longest shot near 45 degrees), and
##             bursts where it lands (CANNON_BLAST): slow and hard-hitting. Its crew works out the elevation.
##   "bastion" the Sentinel Bastion on the roofs: a flak gun that runs itself (no seat, no crew, not a post). It goes
##             for aircraft first, then whatever is on the ground: a shell every FLAK_INTERVAL that bursts by its target.
## Crew-operated by AI unless the defending player takes it over. In a match with a garrison (Garrison) the sentries and
## cannons need a crew: one fires on its own only once a garrison soldier has walked up to it and sits in its seat
## (crew_spot: the model's own side seat, riding the turret as it turns), and falls silent again if that soldier
## dies; the player can still take it over, crewed or not.
##
## The gun's logic holds the aim (a traverse and an elevation); its model is shown by a TurretRig, which moves the
## model's parts each on its own: the turret on its ring, the gun on its trunnion, the barrels, the sensors. The gun
## is laid by servos (TurretRig.slew): it runs up, runs and brakes onto the aim rather than stopping dead. With a crew
## and nothing to shoot at it sweeps its arc; without one it is parked, straight ahead and a little up. The gatling's
## barrels are run up as soon as it has a target, and it fires once they are turning (GatlingRig); the cannon's barrel
## recoils round by round (CannonRig); the flak gun's four barrels fire in turn (BastionRig). Knocked out, the rig
## lets the barrel drop.

signal became_unavailable(station)

const YAW_LIMIT := deg_to_rad(75.0)
const PITCH_MIN := deg_to_rad(-40.0)
const PITCH_MAX := deg_to_rad(50.0)  # high enough to shoot down flyers
const PLAYER_DAMAGE := 17.0
const PLAYER_FIRE_INTERVAL := 0.075
const AI_DAMAGE := 8.0
const AI_FIRE_INTERVAL := 0.16
const AI_RANGE := 60.0
const HEAT_PER_SHOT := 0.032
## The cannon: a round every CANNON_INTERVAL (the player's every CANNON_PLAYER_INTERVAL), CANNON_DAMAGE to what it hits
## and CANNON_SPLASH within CANNON_BLAST (m) of where it lands, CANNON_HEAT a round.
const CANNON_INTERVAL := 1.5
const CANNON_PLAYER_INTERVAL := 0.9
const CANNON_DAMAGE := 55.0
const CANNON_PLAYER_DAMAGE := 80.0
const CANNON_SPLASH := 30.0
const CANNON_BLAST := 3.0
const CANNON_HEAT := 0.16
## The cannon is the stronghold's long gun too (there is none on the roofs): past AI_RANGE and out to CANNON_RANGE its
## crew lobs a shell every CANNON_LONG_INTERVAL, the barrel raised for the range.
const CANNON_RANGE := 150.0
const CANNON_LONG_INTERVAL := 6.0
## The bastion's flak: a shell every FLAK_INTERVAL, FLAK_DAMAGE where it bursts; how high it elevates (rad).
const FLAK_INTERVAL := 0.42
const FLAK_DAMAGE := 20.0
const FLAK_HEAT := 0.05
const FLAK_PITCH_MAX := deg_to_rad(78.0)
const REPAIR_TIME := 360.0  # 6 minutes
## How far behind the swivel a garrison crew stands (m), clear of the gun's navmesh plug.
const CREW_BACK := 1.45
## The laying servos: the most the gun traverses and elevates (rad/s) and how fast it picks up speed (rad/s²).
const TRAVERSE := 1.8
const TRAVERSE_ACCEL := 9.0
## Crewed with nothing to shoot at, it sweeps this far either way (rad) in SWEEP_TIME s, looking a little down.
const SWEEP_ARC := deg_to_rad(48.0)
const SWEEP_TIME := 13.0
const SWEEP_PITCH := deg_to_rad(-7.0)
const SWEEP_RATE := 0.45
## Uncrewed, it is parked: straight ahead, the barrel this far up (rad).
const PARK_PITCH := deg_to_rad(9.0)
const PARK_RATE := 0.6

## Turret model shown while the AI crews the gun (empty = sandbags + gunner capsule).
## The player always sees the simple first-person gun instead, so the model never blocks the view.
var model_path := ""
## How tall the turret model stands (m).
var model_height := 2.0
## "sentry", "cannon" or "bastion" (see the top).
var kind := "sentry"
## Height of the gun's swivel above the node; raised to fire over a tall parapet.
var pivot_height := 1.15
var station_name := "Machine Gun"
var station_kind := "mg"
var team := GameConfig.TEAM_DEFENDER
var max_hp := 300.0
var hp := 300.0
var target_radius := 0.5
var possessed := false
var heat := 0.0
var overheated := false
## Fires on its own only while crewed (the Garrison sets this); off: always crewed, as before there was a garrison.
var needs_crew := false
## The garrison soldier at its handles (GarrisonSoldier), or null.
var crew: Node3D = null
## Where its crew stands to step into its seat (world; a gun-deck gun: on the ramp in its bay's middle). INF: the
## garrison works it out (the floor beside the seat).
var crew_stand := Vector3.INF

var _yaw := 0.0
var _pitch := 0.0
## The servos' rates (rad/s), and the sweep's clock.
var _yaw_rate := 0.0
var _pitch_rate := 0.0
var _sweep := 0.0
var _fire_cd := 0.0
var _retarget_cd := 0.0
var _repair_cd := 0.0
var _target: Node3D
var _shake := 0.0

var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D
var _muzzle: Node3D
var _gunner: Node3D
var _viewmodel: Node3D
var _turret: Node3D
## The model's rig (null: no model, or one no rig knows, turned whole).
var _rig: TurretRig
var _smoke: WreckSmoke


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.6, 1.4)
	shape.shape = box
	shape.position.y = 0.8
	add_child(shape)

	var metal := Mats.flat(Color(0.16, 0.17, 0.18), 0.8, 0.35)
	if model_path == "":
		var sand := Mats.flat(Color(0.55, 0.5, 0.38), 0.0, 1.0)
		# Sandbag horseshoe in front of the gun.
		for i in 5:
			var a := lerpf(-1.1, 1.1, i / 4.0)
			var bag := Mats.box_mesh(Vector3(0.9, 0.45, 0.45), Vector3(sin(a) * 1.1, 0.22, -cos(a) * 1.1), sand)
			bag.rotation.y = -a
			add_child(bag)
		add_child(Mats.cylinder_mesh(0.08, 1.1, Vector3(0, 0.55, 0), metal, 8))

	_yaw_pivot = Node3D.new()
	_yaw_pivot.position.y = pivot_height
	add_child(_yaw_pivot)
	_pitch_pivot = Node3D.new()
	_yaw_pivot.add_child(_pitch_pivot)
	_viewmodel = Node3D.new()
	_pitch_pivot.add_child(_viewmodel)
	_viewmodel.add_child(Mats.box_mesh(Vector3(0.18, 0.2, 0.7), Vector3(0, 0, 0.05), metal))
	var barrel := Mats.cylinder_mesh(0.05, 1.1, Vector3(0, 0.02, -0.85), metal, 8)
	barrel.rotation.x = PI * 0.5
	_viewmodel.add_child(barrel)
	_viewmodel.add_child(Mats.box_mesh(Vector3(0.05, 0.12, 0.05), Vector3(0, 0.15, -0.6), metal))  # front sight
	for x in [-0.12, 0.12]:
		_viewmodel.add_child(Mats.box_mesh(Vector3(0.04, 0.14, 0.04), Vector3(x, -0.05, 0.45), metal))  # grips
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -2.0 if kind == "cannon" else -1.42)
	_pitch_pivot.add_child(_muzzle)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0.42, 1.25)
	_camera.near = 0.05
	_camera.fov = 70.0
	_camera.far = 800.0
	_pitch_pivot.add_child(_camera)

	_gunner = Node3D.new()
	_gunner.position = Vector3(0, 0, 0.9)
	_yaw_pivot.add_child(_gunner)
	if model_path == "":
		var gm := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.4
		gm.mesh = cm
		gm.material_override = Mats.flat(Color(0.18, 0.28, 0.5), 0.1, 0.8)
		gm.position.y = -0.45
		_gunner.add_child(gm)
	else:
		_rig = TurretRig.create(model_path, model_height)
		if _rig:
			# The rig turns its own turret on its base: it stands on the walkway under the gun, not on the swivel.
			_turret = _rig
			_pitch = PARK_PITCH if needs_crew else 0.0
			_rig.set_aim(_yaw, _pitch)
			add_child(_rig)
		else:
			# Any other model swivels whole with the yaw pivot; its base sits on the walkway.
			_turret = Props.instance(model_path, model_height)
			_turret.position.y = -_yaw_pivot.position.y
			_yaw_pivot.add_child(_turret)
		_viewmodel.visible = false
	_sweep = randf() * SWEEP_TIME

	# Knocked out, it smokes and smoulders until it is repaired.
	_smoke = WreckSmoke.new()
	_smoke.position.y = 1.0
	add_child(_smoke)


# ---------------------------------------------------------------- station interface

func can_possess() -> bool:
	return hp > 0.0


func possess() -> void:
	possessed = true
	_camera.current = true
	_gunner.visible = false
	_show_turret(false)


func unpossess() -> void:
	possessed = false
	_camera.current = false
	_camera.fov = 70.0
	_gunner.visible = hp > 0.0
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	_show_turret(true)


func _show_turret(show: bool) -> void:
	if _turret:
		_turret.visible = show
		_viewmodel.visible = not show


func wants_captured_mouse() -> bool:
	return true


func get_station_position() -> Vector3:
	return global_position


func get_camera() -> Camera3D:
	return _camera


## True if it can fire on its own: it needs no crew, or one stands at it (the player at it counts too).
func is_manned() -> bool:
	if not needs_crew or possessed:
		return true
	if crew == null or not is_instance_valid(crew) or not crew.is_alive():
		return false
	# A garrison soldier mans it once it is in the seat (not while it steps into it).
	return not crew.has_method("at_post") or crew.at_post()


## Whether its crew sits (the model has a seat) or stands behind it.
func has_seat() -> bool:
	return _rig != null and _rig.has_seat()


## The model's rig (null without one): for whoever wants to watch its parts.
func rig() -> TurretRig:
	return _rig


## Where the crew goes: the model's seat (the middle of the seat pan's top, -Z the way the one in it faces), riding the
## turret as it turns; with no seat, standing behind the swivel turned with the gun's aim.
func crew_spot() -> Transform3D:
	if has_seat():
		return _rig.seat()
	var yaw := global_rotation.y + _yaw
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	return Transform3D(Basis(Vector3.UP, yaw), global_position + back * CREW_BACK + Vector3.UP * 0.05)


func get_hud_info() -> Dictionary:
	var status := "OVERHEATED" if overheated else "HEAT %d%%" % int(heat * 100.0)
	var weapon: String = {"cannon": "Sentinel Cannon", "bastion": "Bastion Flak"}.get(kind, "Sentry Gatling")
	return {"weapon": weapon, "status": status, "heat": heat, "hp": hp / max_hp,
			"hint": "Mouse aim · LMB fire · RMB zoom · watch the heat"}


# ---------------------------------------------------------------- damage

func is_alive() -> bool:
	return hp > 0.0


func get_approach_point() -> Vector3:
	return Combat.wall_approach(global_position)


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if possessed:
		_shake = 0.3
	if hp <= 0.0:
		hp = 0.0
		_repair_cd = REPAIR_TIME
		_gunner.visible = false
		_smoke.emitting = true
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		if _rig:
			_rig.wrecked = true
			_rig.watch = Vector3.INF
			if _rig is GatlingRig:
				(_rig as GatlingRig).spinning = false
		Combat.spawn_explosion(self, global_position + Vector3.UP, 2.0)
		became_unavailable.emit(self)


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		_repair_cd -= delta
		if _repair_cd <= 0.0:
			hp = max_hp
			heat = 0.0
			overheated = false
			_smoke.emitting = false
			_gunner.visible = not possessed
			if _rig:
				_rig.wrecked = false
		return
	_fire_cd -= delta
	var firing := false
	var manned := is_manned()
	if possessed:
		var zoom := Input.is_action_pressed("aim")
		_camera.fov = lerpf(_camera.fov, 40.0 if zoom else 70.0, delta * 10.0)
		var trigger := Input.is_action_pressed("fire")
		_spin_up(trigger and not overheated)
		if trigger:
			firing = _try_fire(true)
	elif manned:
		firing = _ai_update(delta)
	else:
		_park(delta)
	if _rig:
		_rig.powered = manned
		_rig.heat = heat
	heat = maxf(heat - delta * (0.22 if firing else 0.4), 0.0)
	if overheated and heat < 0.35:
		overheated = false
	_shake = maxf(_shake - delta, 0.0)
	_camera.h_offset = randf_range(-1, 1) * _shake * 0.05
	_camera.v_offset = randf_range(-1, 1) * _shake * 0.05
	_apply_aim()


func _unhandled_input(event: InputEvent) -> void:
	if not possessed or hp <= 0.0 or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := GameConfig.mouse_sensitivity * 0.8 * (_camera.fov / 70.0)
		_yaw = clampf(_yaw - event.relative.x * sens, -YAW_LIMIT, YAW_LIMIT)
		_pitch = clampf(_pitch - event.relative.y * sens, PITCH_MIN, _pitch_max())


func _apply_aim() -> void:
	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch
	if _rig:
		_rig.set_aim(_yaw, _pitch)


## Lays the gun toward (yaw, pitch) with its servos, no faster than `top` rad/s.
func _lay(to_yaw: float, to_pitch: float, top: float, delta: float) -> void:
	var y := TurretRig.slew(_yaw, _yaw_rate, to_yaw, top, TRAVERSE_ACCEL, delta)
	_yaw = y.x
	_yaw_rate = y.y
	var p := TurretRig.slew(_pitch, _pitch_rate, to_pitch, top, TRAVERSE_ACCEL, delta)
	_pitch = p.x
	_pitch_rate = p.y


## Nobody at it: it is turned straight ahead and left with its barrel up a little, the gatling run down.
func _park(delta: float) -> void:
	_target = null
	_spin_up(false)
	if _rig:
		_rig.watch = Vector3.INF
		_lay(0.0, PARK_PITCH, PARK_RATE, delta)


## A gatling's motor: on, its barrels are run up; off, they coast down.
func _spin_up(on: bool) -> void:
	if _rig is GatlingRig:
		(_rig as GatlingRig).spinning = on


## Where the round is seen to leave and the way it goes (+Z): the model's own muzzle while the model is shown, the
## simple gun's otherwise.
func _shown_muzzle() -> Transform3D:
	if _rig and _rig.visible:
		return _rig.muzzle()
	return Transform3D(Basis.looking_at(_pitch_pivot.global_basis.z, Vector3.UP), _muzzle.global_position)


func _try_fire(player: bool) -> bool:
	if overheated or _fire_cd > 0.0:
		return false
	if kind == "cannon":
		return _fire_cannon(player)
	if kind == "bastion":
		return _fire_flak()
	var gatling := _rig as GatlingRig
	if gatling and not player and not gatling.ready_to_fire():
		return false  # the barrels are still running up
	_fire_cd = PLAYER_FIRE_INTERVAL if player else AI_FIRE_INTERVAL
	heat += HEAT_PER_SHOT
	if heat >= 1.0:
		overheated = true
	if gatling:
		gatling.fire_round()
	var muzzle := _muzzle.global_position
	if player:
		var from := _camera.global_position
		Combat.fire_hitscan(self, from, from - _camera.global_basis.z * 100.0, 0.012, PLAYER_DAMAGE, team, 0.3, [get_rid()], muzzle)
		Combat.spawn_muzzle_flash(self, muzzle, -_camera.global_basis.z, 1.4, true)
		_shake = maxf(_shake, 0.12)
	else:
		# The round is worked out from the gun's own swivel; it is seen to leave the model's muzzle.
		var shown := _shown_muzzle()
		Combat.fire_hitscan(self, muzzle, muzzle - _pitch_pivot.global_basis.z * 100.0, 0.035, AI_DAMAGE, team, 0.3, [get_rid()],
				shown.origin)
		Combat.spawn_muzzle_flash(self, shown.origin, shown.basis.z, 1.4)
	return true


## The cannon's round: a hit where the aim is, and a burst there that hurts what stands round it.
func _fire_cannon(player: bool) -> bool:
	_fire_cd = CANNON_PLAYER_INTERVAL if player else CANNON_INTERVAL
	heat += CANNON_HEAT
	if heat >= 1.0:
		overheated = true
	if _rig is CannonRig:
		(_rig as CannonRig).fire()
	# The shell leaves the barrel the way it points and makes its own way from there (CannonShell).
	var shell := CannonShell.new()
	shell.team = team
	shell.damage = CANNON_PLAYER_DAMAGE if player else CANNON_DAMAGE
	shell.splash = CANNON_SPLASH
	shell.radius = CANNON_BLAST
	shell.exclude = [get_rid()]
	get_tree().current_scene.add_child(shell)
	var out := -_pitch_pivot.global_basis.z
	if player:
		shell.launch(_muzzle.global_position, Combat.apply_spread(out, 0.004))
		Combat.spawn_muzzle_blast(self, _muzzle.global_position, out, 1.3)
		_shake = maxf(_shake, 0.35)
	else:
		var shown := _shown_muzzle()
		shell.launch(_muzzle.global_position, Combat.apply_spread(out, 0.012))
		Combat.spawn_muzzle_blast(self, shown.origin, shown.basis.z, 1.3)
	return true


## The bastion's flak: a shell out of the next of its four barrels, bursting by the target.
func _fire_flak() -> bool:
	if not Combat.is_valid_target(_target):
		return false
	_fire_cd = FLAK_INTERVAL
	heat += FLAK_HEAT
	if heat >= 1.0:
		overheated = true
	if _rig is BastionRig:
		(_rig as BastionRig).fire_round()
	Flak.fire(self, _shown_muzzle().origin, _target, FLAK_DAMAGE, team)
	return true


func _pitch_max() -> float:
	return FLAK_PITCH_MAX if kind == "bastion" else PITCH_MAX


## AI crew: track the nearest attacker in the firing arc and shoot in bursts; with none, sweep the arc.
func _ai_update(delta: float) -> bool:
	if FlashGrenade.is_blind(self):
		_spin_up(false)
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		return false  # flashed: the crew can't see to shoot
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.4
		_target = _find_target()
	if not Combat.is_valid_target(_target):
		_spin_up(false)
		if _rig:
			# Nothing in the arc: the sensors scan, and the gun is swept slowly from side to side.
			_rig.watch = Vector3.INF
			_sweep += delta
			_lay(sin(_sweep * TAU / SWEEP_TIME) * SWEEP_ARC, SWEEP_PITCH, SWEEP_RATE, delta)
		return false
	var aim := Combat.aim_point(_target)
	var ang := _angles_to(aim)
	if kind == "cannon":
		ang = _cannon_solution(aim)
	_lay(clampf(ang.x, -YAW_LIMIT, YAW_LIMIT), clampf(ang.y, PITCH_MIN, _pitch_max()), TRAVERSE, delta)
	if _rig:
		_rig.watch = aim
	# A gatling's barrels are run up while it comes onto its target (and left turning through a burst's pauses).
	_spin_up(not overheated)
	# (A shell that has to fall onto its mark wants the barrel laid closer than a round that flies straight.)
	var close := 0.012 if kind == "cannon" else 0.06
	if absf(ang.x - _yaw) < close and absf(ang.y - _pitch) < close and heat < 0.8:
		var fired := _try_fire(false)
		if fired and kind == "cannon" and global_position.distance_to(_target.global_position) > AI_RANGE:
			_fire_cd = CANNON_LONG_INTERVAL  # a long shot: laid with care, one at a time
		return fired
	return false


## The cannon's (yaw, pitch) for a shell to land on `aim` (world): led by where the target will be when it gets there,
## and raised for the shell's fall (CannonShell.elevation_for).
func _cannon_solution(aim: Vector3) -> Vector2:
	var pivot := to_global(_yaw_pivot.position)
	var v = _target.get("velocity")
	for _i in 2:
		var flat := Vector2(aim.x - pivot.x, aim.z - pivot.z).length()
		var e := CannonShell.elevation_for(flat, aim.y - pivot.y)
		if v is Vector3:
			aim = Combat.aim_point(_target) + (v as Vector3) * CannonShell.flight_time(flat, e)
	# The shell starts at the muzzle, a barrel's length out along the shot: the elevation is worked out from there.
	var reach := absf(_muzzle.position.z)
	var flat := Vector2(aim.x - pivot.x, aim.z - pivot.z).length()
	var e := CannonShell.elevation_for(flat, aim.y - pivot.y)
	for _i in 2:
		e = CannonShell.elevation_for(flat - reach * cos(e), aim.y - pivot.y - reach * sin(e))
	return Vector2(_angles_to(aim).x, e)


## Returns (yaw, pitch) needed to point the barrel at a world position.
func _angles_to(point: Vector3) -> Vector2:
	var local := to_local(point) - _yaw_pivot.position
	var yaw := atan2(-local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	return Vector2(yaw, pitch)


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := CANNON_RANGE if kind == "cannon" else AI_RANGE
	if kind == "bastion":
		# Flak: an aircraft before anything on the ground.
		for a in get_tree().get_nodes_in_group("air_units"):
			if a.team == team or not a.is_alive():
				continue
			var d := global_position.distance_to(a.global_position)
			var ang := _angles_to(Combat.aim_point(a))
			if d < best_d and absf(ang.x) <= YAW_LIMIT and ang.y <= FLAK_PITCH_MAX \
					and Combat.has_line_of_sight(self, _muzzle.global_position, Combat.aim_point(a), a):
				best_d = d
				best = a
		if best:
			return best
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var d := global_position.distance_to(u.global_position)
		if d >= best_d:
			continue
		var ang := _angles_to(Combat.aim_point(u))
		if absf(ang.x) > YAW_LIMIT or ang.y < PITCH_MIN or ang.y > _pitch_max():
			continue
		if Combat.has_line_of_sight(self, _muzzle.global_position, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best
