class_name MountedGun
extends StaticBody3D
## Gun emplacement on the walls. Faces its node's -Z axis at rest. Three kinds (`kind`):
##   "sentry"  the Orbital Sentry Gun on the gun decks: a gatling, fast and light.
##   "cannon"  the Arctic Sentinel Cannon on the gun decks: a heavy round every CANNON_INTERVAL that bursts where it
##             lands (CANNON_BLAST), slow and hard-hitting.
##   "bastion" the Sentinel Bastion on the roofs: a gatling that runs itself (no seat, no crew, not a post).
## Crew-operated by AI unless the defending player takes it over. In a match with a garrison (Garrison) the sentries and
## cannons need a crew: one fires on its own only once a garrison soldier has walked up to it and sits in its seat
## (crew_spot: the model's own side seat, Props.SEATS, turning with the gun), and falls silent again if that soldier
## dies; the player can still take it over, crewed or not.

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
const REPAIR_TIME := 360.0  # 6 minutes
## How far behind the swivel a garrison crew stands (m), clear of the gun's navmesh plug.
const CREW_BACK := 1.45
## The pedestal: the column's and the turntable's radii (m), and how far behind the column its ladder's foot is.
const PEDESTAL_R := 0.6
const TURNTABLE_R := 0.95
const LADDER_OUT := 0.45

## Turret model shown while the AI crews the gun (empty = sandbags + gunner capsule).
## The player always sees the simple first-person gun instead, so the model never blocks the view.
var model_path := ""
## How tall the turret model stands (m).
var model_height := 2.0
## The pedestal the turret stands on (m; 0: none, it stands on the floor). The gun decks' guns stand on one so their
## line of fire clears the parapet and the rock sloping away under the deck down to their lowest aim (PITCH_MIN): a
## concrete column with a steel turntable on top and a ladder up its back for the crew (boarding()).
var base_height := 0.0
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

var _yaw := 0.0
var _pitch := 0.0
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
var _smoke: WreckSmoke


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.6 + base_height, 1.4)
	shape.shape = box
	shape.position.y = (1.6 + base_height) * 0.5
	add_child(shape)
	if base_height > 0.0:
		_build_pedestal()

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
		# The turret swivels with the yaw pivot; its base sits on the walkway.
		_turret = Props.instance(model_path, model_height)
		_turret.position.y = -_yaw_pivot.position.y + base_height
		_yaw_pivot.add_child(_turret)
		_viewmodel.visible = false

	# Knocked out, it smokes and smoulders until it is repaired.
	_smoke = WreckSmoke.new()
	_smoke.position.y = base_height + 1.0
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
	# A garrison soldier mans it once it is in the seat (not while it climbs up to it).
	return not crew.has_method("at_post") or crew.at_post()


## The pedestal under the turret (base_height): a concrete column, a steel base plate and turntable, a hazard band under
## the turntable and a steel ladder up the back (the side toward the bunker, +Z) for the crew. It doesn't turn.
func _build_pedestal() -> void:
	var jungle := LevelBuilder.jungle
	var concrete: Material = StrongholdLook.material("Concrete", jungle)
	var steel: Material = StrongholdLook.material("Metal", jungle)
	var stripes: Material = StrongholdLook.material("HatchStripes", jungle)
	if concrete == null:
		concrete = Mats.flat(Color(0.46, 0.45, 0.43), 0.0, 0.95)
	if steel == null:
		steel = Mats.flat(Color(0.2, 0.21, 0.22), 0.8, 0.4)
	if stripes == null:
		stripes = Mats.flat(Color(0.8, 0.35, 0.08), 0.3, 0.6)
	var h := base_height
	add_child(Mats.cylinder_mesh(PEDESTAL_R + 0.15, 0.12, Vector3(0, 0.06, 0), steel, 8))
	add_child(Mats.cylinder_mesh(PEDESTAL_R, h - 0.3, Vector3(0, 0.12 + (h - 0.3) * 0.5, 0), concrete, 8))
	add_child(Mats.cylinder_mesh(PEDESTAL_R + 0.04, 0.18, Vector3(0, h - 0.27, 0), stripes, 8))
	add_child(Mats.cylinder_mesh(TURNTABLE_R, 0.14, Vector3(0, h - 0.07, 0), steel, 16))
	# The ladder: two rails and a rung every 0.3 m, standing off the column's back.
	var z := PEDESTAL_R + 0.12
	for x in [-0.22, 0.22]:
		add_child(Mats.box_mesh(Vector3(0.05, h + 0.9, 0.05), Vector3(x, (h + 0.9) * 0.5, z), steel))
	var y := 0.3
	while y < h + 0.05:
		add_child(Mats.box_mesh(Vector3(0.44, 0.04, 0.04), Vector3(0, y, z), steel))
		y += 0.3
	for c in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The crew's way up a pedestal, in world space: the ladder's foot on the floor, the same spot up at the turntable's
## height, and the turntable's back edge. Empty with no pedestal.
func boarding() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if base_height <= 0.0:
		return out
	var foot := Vector3(0.0, 0.0, PEDESTAL_R + LADDER_OUT)
	out.append(to_global(foot))
	out.append(to_global(foot + Vector3.UP * base_height))
	out.append(to_global(Vector3(0.0, base_height, PEDESTAL_R * 0.6)))
	return out


## Whether its crew sits (the model has a seat) or stands behind it.
func has_seat() -> bool:
	return _turret != null and Props.has_seat(model_path)


## Where the crew goes: the model's seat (the middle of the seat pan's top, -Z the way the one in it faces), turning with
## the gun; with no seat, standing behind the swivel turned with the gun's aim.
func crew_spot() -> Transform3D:
	if has_seat():
		return _turret.global_transform * Props.seat(model_path, model_height)
	var yaw := global_rotation.y + _yaw
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	return Transform3D(Basis(Vector3.UP, yaw), global_position + back * CREW_BACK + Vector3.UP * 0.05)


func get_hud_info() -> Dictionary:
	var status := "OVERHEATED" if overheated else "HEAT %d%%" % int(heat * 100.0)
	var weapon: String = {"cannon": "Sentinel Cannon", "bastion": "Bastion Gatling"}.get(kind, "Sentry Gatling")
	return {"weapon": weapon, "status": status, "heat": heat, "hp": hp / max_hp,
			"hint": "Mouse aim · LMB fire · RMB zoom · watch the heat"}


# ---------------------------------------------------------------- damage

func is_alive() -> bool:
	return hp > 0.0


func get_approach_point() -> Vector3:
	return Combat.wall_approach(global_position)


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * (base_height + 1.2)


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
		Combat.spawn_explosion(self, global_position + Vector3.UP * (base_height + 1.0), 2.0)
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
		return
	_fire_cd -= delta
	var firing := false
	if possessed:
		var zoom := Input.is_action_pressed("aim")
		_camera.fov = lerpf(_camera.fov, 40.0 if zoom else 70.0, delta * 10.0)
		if Input.is_action_pressed("fire"):
			firing = _try_fire(true)
	elif is_manned():
		firing = _ai_update(delta)
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
		_pitch = clampf(_pitch - event.relative.y * sens, PITCH_MIN, PITCH_MAX)


func _apply_aim() -> void:
	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch


func _try_fire(player: bool) -> bool:
	if overheated or _fire_cd > 0.0:
		return false
	if kind == "cannon":
		return _fire_cannon(player)
	_fire_cd = PLAYER_FIRE_INTERVAL if player else AI_FIRE_INTERVAL
	heat += HEAT_PER_SHOT
	if heat >= 1.0:
		overheated = true
	var muzzle := _muzzle.global_position
	if player:
		var from := _camera.global_position
		Combat.fire_hitscan(self, from, from - _camera.global_basis.z * 100.0, 0.012, PLAYER_DAMAGE, team, 0.3, [get_rid()], muzzle)
		Combat.spawn_muzzle_flash(self, muzzle, -_camera.global_basis.z, 1.4, true)
		_shake = maxf(_shake, 0.12)
	else:
		Combat.fire_hitscan(self, muzzle, muzzle - _pitch_pivot.global_basis.z * 100.0, 0.035, AI_DAMAGE, team, 0.3, [get_rid()])
		Combat.spawn_muzzle_flash(self, muzzle, -_pitch_pivot.global_basis.z, 1.4)
	return true


## The cannon's round: a hit where the aim is, and a burst there that hurts what stands round it.
func _fire_cannon(player: bool) -> bool:
	_fire_cd = CANNON_PLAYER_INTERVAL if player else CANNON_INTERVAL
	heat += CANNON_HEAT
	if heat >= 1.0:
		overheated = true
	var muzzle := _muzzle.global_position
	var hit: Dictionary
	if player:
		var from := _camera.global_position
		hit = Combat.fire_hitscan(self, from, from - _camera.global_basis.z * 100.0, 0.006, CANNON_PLAYER_DAMAGE, team, 1.0,
				[get_rid()], muzzle, 0.09)
		Combat.spawn_muzzle_blast(self, muzzle, -_camera.global_basis.z, 1.3)
		_shake = maxf(_shake, 0.35)
	else:
		hit = Combat.fire_hitscan(self, muzzle, muzzle - _pitch_pivot.global_basis.z * 100.0, 0.02, CANNON_DAMAGE, team, 1.0,
				[get_rid()], null, 0.09)
		Combat.spawn_muzzle_blast(self, muzzle, -_pitch_pivot.global_basis.z, 1.3)
	var at: Vector3 = hit.position
	if at.distance_to(muzzle) < 250.0:
		Combat.explode(self, at, CANNON_BLAST, CANNON_SPLASH, team)
	return true


## AI crew: track the nearest attacker in the firing arc and shoot in bursts.
func _ai_update(delta: float) -> bool:
	if FlashGrenade.is_blind(self):
		return false  # flashed: the crew can't see to shoot
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.4
		_target = _find_target()
	if not Combat.is_valid_target(_target):
		return false
	var ang := _angles_to(Combat.aim_point(_target))
	_yaw = move_toward(_yaw, clampf(ang.x, -YAW_LIMIT, YAW_LIMIT), delta * 1.8)
	_pitch = move_toward(_pitch, clampf(ang.y, PITCH_MIN, PITCH_MAX), delta * 1.8)
	if absf(ang.x - _yaw) < 0.06 and absf(ang.y - _pitch) < 0.06 and heat < 0.8:
		return _try_fire(false)
	return false


## Returns (yaw, pitch) needed to point the barrel at a world position.
func _angles_to(point: Vector3) -> Vector2:
	var local := to_local(point) - _yaw_pivot.position
	var yaw := atan2(-local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	return Vector2(yaw, pitch)


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := AI_RANGE
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var d := global_position.distance_to(u.global_position)
		if d >= best_d:
			continue
		var ang := _angles_to(Combat.aim_point(u))
		if absf(ang.x) > YAW_LIMIT or ang.y < PITCH_MIN or ang.y > PITCH_MAX:
			continue
		if Combat.has_line_of_sight(self, _muzzle.global_position, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best
