class_name AASquad
extends DefenderSquad
## AA Squad: five Missile Troopers (MissileTrooper: the Armored Sentinel with a six-missile pod on
## its shoulder), a squad the defender buys (DefenderArmory) and can take over in third person like
## the Gunner Squad (DefenderSquad: the same formation, following and camera). Its weapons:
##   - Seeking missiles at aircraft. Hold RMB with the crosshair close to an enemy aircraft (within
##     LOCK_CONE of it, it needn't be dead on) and keep it there for LOCK_TIME: the squad locks on.
##     LMB then launches as many missiles as it takes to bring it down, counting those already on
##     their way (ElephantMissiles), from whichever pods are loaded. Holding LMB keeps firing while
##     the lock holds; letting go of RMB, or losing the aircraft (past KEEP_CONE), drops it.
##   - Rocket strike on the ground. LMB with the crosshair on the ground (or a ground unit) and each
##     trooper fires STRIKE_ROCKETS rockets at a spot of its own around the aim point: the spots
##     cluster round it STRIKE_SPACING apart, like the rhinos' bombs (RhinoAim.cluster). Holding RMB
##     shows where each trooper's rockets will land.
##   - Mines (F, then LMB; RMB or F cancels). The troopers lob mines into a cone toward the aim,
##     landing sparsely over the band at its tip, like the Hippo's smoke curtain (MineAim). They are
##     ready again MINE_COOLDOWN later.
## Every missile or rocket empties a tube of its trooper's pod; the tubes reload one at a time.
##
## Left to itself the squad follows its order (V while driving it, Ctrl+F<n> from anywhere):
##   MINES  It lays mines where it is when the player hands it back, then walks back to the base
##          laying mines on the path behind it whenever they are ready; at the base it lays them
##          along the perimeter outside the gates, where the fewest are.
##   GUARD  It stays where it is and only watches the sky.
## Either way it locks on to (taking LOCK_TIME, like the player) and shoots down any enemy aircraft
## within AI_AA_RANGE, and never fires at ground units. A bought squad is gone for good once all
## five troopers are down (lost ones are replaced from the hall it deployed in until then).

enum Order { MINES, GUARD }
const ORDER_NAMES := ["MINES", "GUARD"]

const MINE_KEY := KEY_F
const ORDER_KEY := KEY_V
## Missiles: damage each, and seconds between one launch and the next in a volley.
const MISSILE_DAMAGE := 40.0
const MISSILE_STAGGER := 0.12
## Lock-on: seconds the crosshair has to stay within LOCK_CONE of an aircraft; a lock holds while
## it stays within KEEP_CONE. Off the aircraft, the lock drains LOCK_DECAY times faster than it
## builds.
const LOCK_TIME := 3.0
const LOCK_CONE := deg_to_rad(6.0)
const KEEP_CONE := deg_to_rad(13.0)
const LOCK_DECAY := 2.0
const LOCK_RANGE := 120.0
## Left to itself the squad goes after aircraft this close (flat distance, m).
const AI_AA_RANGE := 85.0
## Rocket strike: rockets per trooper, each hitting for STRIKE_DAMAGE within STRIKE_SPLASH, landing
## within STRIKE_SPREAD of the trooper's spot; seconds between one trooper's rockets.
const STRIKE_ROCKETS := 3
const STRIKE_DAMAGE := 60.0
const STRIKE_SPLASH := 4.5
const STRIKE_SPREAD := 2.0
const STRIKE_SPACING := 5.5
const STRIKE_RANGE := 90.0
const STRIKE_MIN := 10.0
const STRIKE_STAGGER := 0.16
## Mines: each trooper lobs MINES_PER_TROOPER; the squad keeps at most MAX_MINES down (the oldest
## are taken up).
const MINE_COOLDOWN := 15.0
const MINES_PER_TROOPER := 2
const MAX_MINES := 40
## The base's perimeter: spots in two rows, these far out from the foot of each gated face, across
## its lane. A squad keeps to the spots within PERIMETER_NEAR of it while there are any (its own face).
const PERIMETER_OUT := [18.0, 30.0]
const PERIMETER_ACROSS := [-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0]
const PERIMETER_NEAR := 70.0
## Walking back, the squad is at the base this close to a perimeter spot (m), and lays mines on the
## path PATH_BACK behind it; at a spot, it throws them PERIMETER_THROW further out.
const BASE_REACH := 14.0
const SPOT_REACH := 3.0
const PATH_BACK := 13.0
const PERIMETER_THROW := 12.0
## After a throw the squad keeps facing the mines this long (s).
const FACE_THROW := 1.4
## Left to itself the squad walks (its leader no faster than this, m/s), it doesn't hurry.
const AI_WALK := SquadTrooper.CLIP_FORWARD * 1.1
const STRIKE_COLOR := Color(1.0, 0.45, 0.2)
const MINE_FILL := Color(0.2, 0.9, 0.6, 0.3)
const MINE_LINE := Color(0.3, 1.0, 0.7)

## Purchase number: "AA Squad <number>".
var number := 1
var order := Order.MINES
## Aircraft being locked on to (or locked), and seconds of lock built up (LOCK_TIME: locked).
var lock_target: Node3D = null
var lock_progress := 0.0
var locked := false
## Seconds until the mines are ready again.
var mine_cd := 0.0
## The player is aiming the mines (F): the cone shows, LMB throws.
var mine_aiming := false
## This squad's mines on the field, oldest first.
var mines: Array[GroundMine] = []
## What the auto MINES order is doing: "here" (lay mines where it is), "return" (walk back to the
## base laying them on the way), "perimeter" (lay them along the base's perimeter).
var plan := "return"
## Where the auto GUARD order holds.
var guard_post := Vector3.INF
## Totals (the showcase checks them, the autotest reports them).
var stats := {"missiles": 0, "rockets": 0, "strikes": 0, "mines": 0, "throws": 0}

## Launches to make: [{"at": clock, "trooper", "kind": "missile"|"rocket", "target"/"point"}].
var _launches: Array = []
var _clock := 0.0
var _fire_was := false
var _aim_was := false
var _mine_seed := 1
## Perimeter spot the squad walks to (INF: pick one) and the way out from the base there.
var _spot := Vector3.INF
var _spot_out := Vector3.ZERO
## The squad faces this point until _face_t runs out (it just threw mines there).
var _face_at := Vector3.ZERO
var _face_t := 0.0
var _notice := ""
var _notice_t := 0.0
## Seconds until the squad, left alone, looks round the sky for an aircraft again.
var _search_cd := 0.0
var _aa_hud: AAHud
var _strike_mesh: ImmediateMesh
var _strike_preview: MeshInstance3D
var _mine_mesh: ImmediateMesh
var _mine_preview: MeshInstance3D


func _init() -> void:
	station_kind = "aa_squad"
	respawns = false
	trooper_hp = MissileTrooper.MAX_HP
	setup(1)


## Names the squad after its purchase number.
func setup(n: int) -> void:
	number = n
	station_name = "AA Squad %d" % n
	hud_title = "AA SQUAD %d" % n


func _new_trooper() -> SquadTrooper:
	return MissileTrooper.new()


func _ready() -> void:
	super()
	_aa_hud = AAHud.new()
	_aa_hud.squad = self
	_aa_hud.visible = false
	_hud_layer.add_child(_aa_hud)
	_strike_mesh = ImmediateMesh.new()
	_strike_preview = _preview(_strike_mesh)
	_mine_mesh = ImmediateMesh.new()
	_mine_preview = _preview(_mine_mesh)


func _preview(mesh: ImmediateMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


# ---------------------------------------------------------------- station interface

func possess() -> void:
	super()
	_aa_hud.visible = true
	mine_aiming = false
	_drop_lock()
	# A trigger still held from before doesn't fire.
	_fire_was = true
	_aim_was = true


func unpossess() -> void:
	super()
	_aa_hud.visible = false
	_strike_preview.visible = false
	_mine_preview.visible = false
	mine_aiming = false
	_drop_lock()
	# Handed back: the order takes over from where the squad stands.
	plan = "here"
	guard_post = leader.global_position if leader else home.origin


func set_hud_visible(on: bool) -> void:
	super(on)
	_aa_hud.visible = on and possessed


func get_hud_info() -> Dictionary:
	if leader == null:
		return {"weapon": "Missiles", "status": "—", "hp": 0.0, "hint": ""}
	var full := 0
	for t in troopers:
		full += (t as MissileTrooper).loaded()
	var total := troopers.size() * MissileTrooper.TUBES
	var status := "READY" if full > 0 else "RELOADING"
	if mine_aiming:
		status = "MINES · LMB THROW"
	elif locked:
		status = "LOCKED · LMB FIRE"
	elif lock_target != null:
		status = "LOCKING %d%%" % int(lock_progress / LOCK_TIME * 100.0)
	return {"weapon": "Missiles %d/%d · %d/%d · %s" % [full, total, troopers.size(), SIZE, SquadFormation.MODE_NAMES[formation.mode]],
			"status": status, "heat": float(full) / maxf(total, 1.0), "bar_color": UIKit.ACCENT,
			"hp": leader.hp / leader.max_hp,
			"hint": "WASD move · RMB on an aircraft for 3 s: lock on · LMB missiles (locked) or rocket strike (ground) · F mines · V order (%s)" % ORDER_NAMES[order]}


## Next auto order (MINES -> GUARD -> MINES). Takes effect at once if nobody drives the squad.
func cycle_order() -> void:
	set_order(((order + 1) % ORDER_NAMES.size()) as Order)


func set_order(o: Order) -> void:
	order = o
	guard_post = leader.global_position if leader else home.origin
	if plan == "here":
		plan = "return"


## A line under the crosshair for a moment (why the squad didn't fire, and the like).
func notify(text: String) -> void:
	_notice = text
	_notice_t = 1.6


func notice() -> String:
	return _notice if _notice_t > 0.0 else ""


func lock_fraction() -> float:
	return lock_progress / LOCK_TIME


# ---------------------------------------------------------------- the player

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not possessed or pilot != null or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == MINE_KEY:
			toggle_mine_aim()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == ORDER_KEY:
			cycle_order()
			get_viewport().set_input_as_handled()


## F: aim the mines (the cone shows), or put them away again.
func toggle_mine_aim() -> void:
	if mine_aiming:
		mine_aiming = false
	elif mine_cd > 0.0:
		notify("MINES READY IN %ds" % ceili(mine_cd))
	else:
		mine_aiming = true


func _player_weapons(delta: float, hustle: bool) -> void:
	var fire_edge: bool = input.fire and not _fire_was
	var aim_edge: bool = input.aim and not _aim_was
	_fire_was = input.fire
	_aim_was = input.aim
	if mine_aiming:
		_lock_decay(delta)
		if fire_edge and not hustle:
			throw_mines(mine_toward())
		elif aim_edge:
			mine_aiming = false
		return
	var look := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3.FORWARD
	_update_lock(delta, _cam.global_position, look, input.aim)
	if hustle:
		return
	if locked and input.fire:
		fire_missiles(lock_target)
	elif fire_edge and lock_target == null:
		if crosshair_on_ground():
			strike(strike_point())
		else:
			notify("NO TARGET: AIM AT THE GROUND, OR LOCK ON (RMB)")


## RMB held: the aircraft nearest the crosshair within LOCK_CONE builds up the lock; locked, it
## holds while the crosshair stays within KEEP_CONE of it.
func _update_lock(delta: float, eye: Vector3, look: Vector3, aiming: bool) -> void:
	if not aiming:
		_lock_decay(delta)
		return
	if locked:
		if Combat.is_valid_target(lock_target) and _off_aim(eye, look, lock_target) < KEEP_CONE \
				and _flat(eye, lock_target.global_position) <= LOCK_RANGE:
			return
		notify("TARGET DOWN" if not Combat.is_valid_target(lock_target) else "LOCK LOST")
		_drop_lock()
		return
	var best := _aircraft_near_aim(eye, look)
	if best == null:
		_lock_decay(delta)
		return
	if best != lock_target:
		lock_target = best
		lock_progress = 0.0
	lock_progress += delta
	if lock_progress >= LOCK_TIME:
		lock_progress = LOCK_TIME
		locked = true


func _lock_decay(delta: float) -> void:
	locked = false
	lock_progress = maxf(lock_progress - delta * LOCK_DECAY, 0.0)
	if lock_progress <= 0.0 or not Combat.is_valid_target(lock_target):
		lock_target = null
		lock_progress = 0.0


func _drop_lock() -> void:
	locked = false
	lock_target = null
	lock_progress = 0.0


## Enemy aircraft within LOCK_RANGE and LOCK_CONE of the look direction, in sight; the one nearest
## the crosshair.
func _aircraft_near_aim(eye: Vector3, look: Vector3) -> Node3D:
	var best: Node3D = null
	var best_off := LOCK_CONE
	for a in get_tree().get_nodes_in_group("air_units"):
		if a.team == team or not a.is_alive() or _flat(eye, a.global_position) > LOCK_RANGE:
			continue
		var off := _off_aim(eye, look, a)
		if off < best_off and Combat.has_line_of_sight(self, eye, Combat.aim_point(a), a):
			best_off = off
			best = a
	return best


static func _off_aim(eye: Vector3, look: Vector3, a: Node3D) -> float:
	return look.angle_to(Combat.aim_point(a) - eye)


## True if the crosshair is on something on the ground (not the sky).
func crosshair_on_ground() -> bool:
	return _cam.global_position.distance_to(aim_point) < AIM_RANGE - 0.5


## The ground under the crosshair.
func strike_point() -> Vector3:
	return _ground(aim_point)


## Where the mines are aimed: the crosshair's spot on the ground, or straight ahead of the camera.
func mine_toward() -> Vector3:
	if crosshair_on_ground() and _flat(leader.global_position, aim_point) < MineAim.MAX_RANGE * 2.0:
		return aim_point
	return leader.global_position + Basis(Vector3.UP, cam_yaw) * Vector3.FORWARD * MineAim.MAX_RANGE


# ---------------------------------------------------------------- weapons

## Launches as many missiles at `t` as it takes to bring it down (counting those already on their
## way, and those about to leave), from the loaded pods nearest it, a volley shared round the squad.
## Returns how many it sent.
func fire_missiles(t: Node3D) -> int:
	if not Combat.is_valid_target(t):
		return 0
	var need := ElephantMissiles.still_needed(t)
	if need <= 0.0:
		return 0
	var count := ceili(need / MISSILE_DAMAGE)
	var shooters := troopers.filter(func(x): return _free_tubes(x) > 0)
	shooters.sort_custom(func(a, b): return a.global_position.distance_to(t.global_position) < b.global_position.distance_to(t.global_position))
	var free := {}
	for s in shooters:
		free[s] = _free_tubes(s)
	var plan_: Array = []
	while plan_.size() < count:
		var took := false
		for s in shooters:
			if plan_.size() < count and free[s] > 0:
				plan_.append(s)
				free[s] -= 1
				took = true
		if not took:
			break
	if plan_.is_empty():
		return 0
	var id := t.get_instance_id()
	ElephantMissiles.commit(id, plan_.size() * MISSILE_DAMAGE)
	for i in plan_.size():
		_launches.append({"at": _clock + i * MISSILE_STAGGER, "trooper": plan_[i], "kind": "missile", "target": t, "id": id})
	stats.missiles += plan_.size()
	return plan_.size()


## Rocket strike on the ground at `at`: each trooper with loaded tubes fires up to STRIKE_ROCKETS
## rockets at its own spot round it (strike_spots). False (with a notice) if nobody can.
func strike(at: Vector3) -> bool:
	var shooters := troopers.filter(func(x): return _free_tubes(x) > 0)
	if shooters.is_empty():
		notify("RELOADING")
		return false
	var d := _flat(leader.global_position, at)
	if d < STRIKE_MIN:
		notify("TOO CLOSE")
		return false
	if d > STRIKE_RANGE:
		notify("OUT OF RANGE")
		return false
	var spots := strike_spots(shooters, at)
	var fired := 0
	for i in shooters.size():
		var tr: MissileTrooper = shooters[i]
		for r in mini(STRIKE_ROCKETS, _free_tubes(tr)):
			# The first rocket on the spot itself, the others scattered round it.
			var a := randf() * TAU
			var off := Vector3(cos(a), 0.0, sin(a)) * STRIKE_SPREAD * sqrt(randf()) if r > 0 else Vector3.ZERO
			_launches.append({"at": _clock + i * 0.09 + r * STRIKE_STAGGER, "trooper": tr, "kind": "rocket",
					"point": _ground(spots[i] + off), "spot": spots[i]})
			fired += 1
	stats.strikes += 1
	stats.rockets += fired
	return true


## Each shooter's spot for a strike at `at`: clustered round it, STRIKE_SPACING apart, each within
## the shooter's reach (RhinoAim.cluster). Same order as `shooters`.
func strike_spots(shooters: Array, at: Vector3) -> Array[Vector3]:
	var from: Array[Vector3] = []
	var reach: Array[float] = []
	for s in shooters:
		from.append(s.global_position)
		reach.append(STRIKE_RANGE)
	var spots := RhinoAim.cluster(from, reach, STRIKE_SPACING, at)
	for i in spots.size():
		spots[i] = _ground(spots[i])
	return spots


## Throws the mines into the cone toward `toward` (MineAim): each trooper lobs MINES_PER_TROOPER
## onto the spots nearest it. False while they aren't ready.
func throw_mines(toward: Vector3) -> bool:
	if mine_cd > 0.0 or troopers.is_empty() or leader == null:
		return false
	var aim := MineAim.solve(leader.global_position, toward, troopers.size() * MINES_PER_TROOPER, get_world_3d(), _mine_seed)
	var spots: Array = aim.points.duplicate()
	if spots.is_empty():
		notify("NO ROOM FOR MINES THERE")
		return false
	_mine_seed += 1
	mine_cd = MINE_COOLDOWN
	mine_aiming = false
	for round_i in MINES_PER_TROOPER:
		for k in troopers.size():
			if spots.is_empty():
				break
			var tr: MissileTrooper = troopers[k]
			var best := 0
			for j in spots.size():
				if _flat(spots[j], tr.global_position) < _flat(spots[best], tr.global_position):
					best = j
			tr.throw_mine(spots[best], 0.35 + round_i * MissileRig.THROW_TIME + k * 0.06, self)
			spots.remove_at(best)
			stats.mines += 1
	stats.throws += 1
	_face_at = leader.global_position + (aim.dir as Vector3) * float(aim.dist) + Vector3.UP * 1.0
	_face_t = FACE_THROW
	return true


## A mine this squad threw has landed on the field (MissileTrooper calls it as the mine leaves the
## hand); past MAX_MINES the oldest is taken up.
func add_mine(m: GroundMine) -> void:
	mines.append(m)
	m.tree_exiting.connect(_on_mine_gone.bind(m))
	while mines.size() > MAX_MINES:
		var old: GroundMine = mines.pop_front()
		if is_instance_valid(old):
			old.fizzle()


func _on_mine_gone(m: GroundMine) -> void:
	mines.erase(m)


## Tubes a trooper still has for new launches (loaded, less those already promised).
func _free_tubes(t: SquadTrooper) -> int:
	var n := (t as MissileTrooper).loaded()
	for l in _launches:
		if l.trooper == t:
			n -= 1
	return n


func _arm_troopers(delta: float) -> void:
	_clock += delta
	mine_cd = maxf(mine_cd - delta, 0.0)
	_notice_t = maxf(_notice_t - delta, 0.0)
	_face_t = maxf(_face_t - delta, 0.0)
	# Launches that are due.
	var i := 0
	while i < _launches.size():
		var l: Dictionary = _launches[i]
		if l.at > _clock:
			i += 1
			continue
		_launches.remove_at(i)
		var tr = l.trooper
		var alive: bool = is_instance_valid(tr) and tr.is_alive()
		if l.kind == "missile":
			var ok: bool = alive and Combat.is_valid_target(l.target) \
					and tr.launch_missile(l.target, MISSILE_DAMAGE, ElephantMissiles.release.bind(l.id, MISSILE_DAMAGE))
			if not ok:
				ElephantMissiles.release(l.id, MISSILE_DAMAGE)
		elif alive:
			tr.launch_rocket(l.point, STRIKE_DAMAGE, STRIKE_SPLASH)
	# Pods: onto what each trooper is about to launch at, else the lock, else the aim.
	for t in troopers:
		var tr := t as MissileTrooper
		tr.pod_target = Combat.aim_point(lock_target) if Combat.is_valid_target(lock_target) else Vector3.INF
		for l in _launches:
			if l.trooper == tr:
				if l.kind == "missile" and Combat.is_valid_target(l.target):
					tr.pod_target = Combat.aim_point(l.target)
				elif l.kind == "rocket":
					# Up over the spot: the rockets climb before they dive.
					var spot: Vector3 = l.spot
					tr.pod_target = spot + Vector3.UP * maxf(_flat(tr.global_position, spot) * 0.9, 8.0)
				break


# ---------------------------------------------------------------- left alone

func _ai_control(delta: float) -> void:
	for t in troopers:
		t.hustle = false
		t.walk_limit = AI_WALK if t == leader else INF
	var engaged := _ai_air(delta)
	if order == Order.GUARD:
		if guard_post == Vector3.INF:
			guard_post = leader.global_position
		_walk_leader_to(guard_post, 2.0)
		if not engaged:
			aim_point = _look_out(leader.global_position)
		return
	_ai_mines()
	if engaged:
		return
	if _face_t > 0.0:
		aim_point = _face_at
	elif leader.velocity.length() > 0.5:
		aim_point = leader.global_position + Vector3.UP * 1.4 + Vector3(leader.velocity.x, 0.0, leader.velocity.z).normalized() * 30.0
	elif _spot != Vector3.INF and _flat(leader.global_position, _spot) < SPOT_REACH * 2.0:
		aim_point = _spot + _spot_out * 30.0 + Vector3.UP * 1.4
	else:
		aim_point = _look_out(leader.global_position)


## Locks on to the nearest enemy aircraft in range and sight (taking LOCK_TIME, like the player),
## then fires at it. True while it has one.
func _ai_air(delta: float) -> bool:
	var eye := leader.global_position + Vector3.UP * 1.8
	_search_cd -= delta
	if not (Combat.is_valid_target(lock_target) and _flat(eye, lock_target.global_position) <= AI_AA_RANGE
			and Combat.has_line_of_sight(self, eye, Combat.aim_point(lock_target), lock_target)):
		_drop_lock()
		if _search_cd > 0.0:
			return false
		_search_cd = 0.3
		var best_d := AI_AA_RANGE
		for a in get_tree().get_nodes_in_group("air_units"):
			if a.team == team or not a.is_alive():
				continue
			var d := _flat(eye, a.global_position)
			if d < best_d and Combat.has_line_of_sight(self, eye, Combat.aim_point(a), a):
				best_d = d
				lock_target = a
	if lock_target == null:
		return false
	aim_point = Combat.aim_point(lock_target)
	lock_progress = minf(lock_progress + delta, LOCK_TIME)
	locked = lock_progress >= LOCK_TIME
	if locked:
		fire_missiles(lock_target)
	return true


## The auto MINES order: mines where the squad was handed back, then home laying them on the path
## behind it, then along the perimeter where the fewest are.
func _ai_mines() -> void:
	if not _nav_ready:
		return
	var here := leader.global_position
	match plan:
		"here":
			if mine_cd <= 0.0 and not _inside_base(here):
				throw_mines(here + Basis(Vector3.UP, heading) * Vector3.FORWARD * 14.0)
			plan = "return"
		"return":
			var spot := _nearest_perimeter(here)
			if _flat(here, spot) <= BASE_REACH:
				plan = "perimeter"
				_spot = Vector3.INF
				return
			_walk_leader_to(spot, 1.0)
			# On the way, on the path behind (not inside the mountain).
			if mine_cd <= 0.0 and not _inside_base(here) and leader.velocity.length() > 0.5:
				throw_mines(formation.along(PATH_BACK, here)[0])
		"perimeter":
			if _spot == Vector3.INF:
				_pick_spot()
			if _spot == Vector3.INF:
				return
			if _walk_leader_to(_spot, SPOT_REACH) and mine_cd <= 0.0:
				if throw_mines(_spot + _spot_out * PERIMETER_THROW):
					_spot = Vector3.INF
				else:
					_pick_spot(true)


## The next perimeter spot: few mines round it and not far to walk, on the squad's own face while
## it has any (`elsewhere`: not this one).
func _pick_spot(elsewhere := false) -> void:
	var map := get_world_3d().navigation_map
	var here := leader.global_position
	var spots := perimeter_spots()
	var near_spots := spots.filter(func(s): return _flat(here, s[0]) <= PERIMETER_NEAR)
	var best := Vector3.INF
	var best_cost := INF
	for s in (near_spots if not near_spots.is_empty() else spots):
		var p := NavigationServer3D.map_get_closest_point(map, s[0] + Vector3.UP * 0.5)
		if _flat(p, s[0]) > 4.0 or (elsewhere and _spot != Vector3.INF and _flat(p, _spot) < 1.0):
			continue
		var mined := 0
		for m in GroundMine.all:
			if _flat(m.spot(), p + s[1] * PERIMETER_THROW) < 9.0:
				mined += 1
		var cost := mined * 10.0 + _flat(here, p) * 0.6 + randf() * 2.0
		if cost < best_cost:
			best_cost = cost
			best = p
			_spot_out = s[1]
	_spot = best


## Perimeter spots, [position, the way out from the base there]: across the lane outside every
## gated face.
static func perimeter_spots() -> Array:
	var out := []
	for side in LevelBuilder.SIDES:
		if not LevelBuilder.SIDES[side].gate:
			continue
		var dir: Vector3 = LevelBuilder.SIDES[side].dir
		var across := dir.cross(Vector3.UP)
		for o in PERIMETER_OUT:
			for a in PERIMETER_ACROSS:
				out.append([dir * (LevelBuilder.FACE_DIST + o) + across * a, dir])
	return out


func _nearest_perimeter(p: Vector3) -> Vector3:
	var best: Vector3 = perimeter_spots()[0][0]
	for s in perimeter_spots():
		if _flat(p, s[0]) < _flat(p, best):
			best = s[0]
	return best


static func _inside_base(p: Vector3) -> bool:
	return absf(p.x) < LevelBuilder.MOUNTAIN_HALF and absf(p.z) < LevelBuilder.MOUNTAIN_HALF


## A point to look at out from the base (the attackers come from there).
func _look_out(p: Vector3) -> Vector3:
	var out := Vector3(p.x, 0.0, p.z)
	out = out.normalized() if out.length() > 1.0 else Basis(Vector3.UP, heading) * Vector3.FORWARD
	return p + Vector3.UP * 1.6 + out * 30.0


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 6.0, p.z), Vector3(p.x, p.y - 60.0, p.z), GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3(p.x, 0.0, p.z)


# ---------------------------------------------------------------- previews

func _process(delta: float) -> void:
	super(delta)
	if not possessed or leader == null:
		return
	_mine_preview.visible = mine_aiming
	_strike_preview.visible = false
	if mine_aiming:
		_mine_mesh.clear_surfaces()
		var aim := MineAim.solve(leader.global_position, mine_toward(), troopers.size() * MINES_PER_TROOPER, get_world_3d(), _mine_seed)
		MineAim.draw_preview(_mine_mesh, leader.global_position, aim, Mats.unshaded(MINE_FILL, true), Mats.unshaded(MINE_LINE, true))
	elif input.aim and lock_target == null and crosshair_on_ground():
		var at := strike_point()
		var d := _flat(leader.global_position, at)
		var shooters := troopers.filter(func(x): return _free_tubes(x) > 0)
		if d >= STRIKE_MIN and d <= STRIKE_RANGE and not shooters.is_empty():
			_strike_preview.visible = true
			_draw_strike(shooters, at)


## Each trooper's spot: a disc where its rockets land (dashed round its edge) with a post standing
## in it, to read from low down, and a dashed line to it.
func _draw_strike(shooters: Array, at: Vector3) -> void:
	var spots := strike_spots(shooters, at)
	var lift := Vector3.UP * 0.3
	var r := STRIKE_SPREAD + 0.6
	_strike_mesh.clear_surfaces()
	_strike_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, Mats.unshaded(Color(STRIKE_COLOR, 0.28), true))
	for p in spots:
		for k in 20:
			var a0 := TAU * k / 20.0
			var a1 := TAU * (k + 1) / 20.0
			_strike_mesh.surface_add_vertex(p + lift)
			_strike_mesh.surface_add_vertex(p + lift + Vector3(cos(a1), 0.0, sin(a1)) * r)
			_strike_mesh.surface_add_vertex(p + lift + Vector3(cos(a0), 0.0, sin(a0)) * r)
	_strike_mesh.surface_end()
	_strike_mesh.surface_begin(Mesh.PRIMITIVE_LINES, Mats.unshaded(STRIKE_COLOR, true))
	for i in shooters.size():
		RhinoAim.dashed_circle(_strike_mesh, spots[i] + lift, r, 20)
		_strike_mesh.surface_add_vertex(spots[i] + lift)
		_strike_mesh.surface_add_vertex(spots[i] + Vector3.UP * 3.0)
		var from: Vector3 = shooters[i].global_position + Vector3.UP * 1.8
		var to := spots[i] + lift
		var dashes := maxi(int(from.distance_to(to) / 1.6), 1)
		for k in dashes:
			_strike_mesh.surface_add_vertex(from.lerp(to, float(k) / dashes))
			_strike_mesh.surface_add_vertex(from.lerp(to, (k + 0.5) / dashes))
	_strike_mesh.surface_end()
