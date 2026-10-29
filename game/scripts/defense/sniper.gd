class_name Sniper
extends DefenderSquad
## The Sniper: one marksman, not a squad (a post of one: squad_size): the Grey Veil Warden in her ghillie
## cape with the Eclipse Longshot (SniperTrooper), bought by the defender (DefenderArmory). The player
## drives her in third person over her shoulder like a squad's leader (DefenderSquad: WASD, the camera,
## the blast doors opening for her):
##   - RMB, the scope: first person through the rifle's scope (it comes up in SCOPE_IN), magnified ZOOMS
##     times (the wheel steps through them), a scope's reticle round the aim (SniperScope); she walks no
##     faster than SCOPED_WALK with it up.
##   - LMB: a round where the crosshair is (DAMAGE), then she works the bolt; SniperTrooper.MAG rounds a
##     magazine, R reloads. Its long tracer and the white trail it leaves show on both sides (SniperTrail).
##   - T, thermal vision: THERMAL_TIME seconds of it, then THERMAL_RECHARGE to recharge (T again switches
##     it off early; the recharge starts then): the land goes dark and cold, the attackers glow white-hot
##     and the trees turn see-through, so she sees them inside forests too (SniperThermal). On the
##     player's screen only.
## Tags: an attacker her round hits is tagged for TAG_TIME seconds (AttackerUnit.tag): an aim icon hangs
## over it on both sides, defenders hit it 20% harder, and a tagged lioness can't sneak. She keeps up to
## TAG_LIMIT tags at a time: a hit on another unit while all of hers are out tags nothing, until one of
## her tagged units dies or its tag runs out (a hit on one she has tagged starts its TAG_TIME over).
##
## Left to herself (idle) she stays exactly where the player left her (where she deployed, if never
## driven). She picks one attacker in reach (AI_RANGE) and in sight that isn't inside a forest (without
## the player's thermal sight she can't make them out among the trees) and shoots it until it dies, a
## little softer than the player does (AI_DAMAGE), so she tags only it; then she picks the next. One that
## stays out of her sight (behind the mountain, in a forest, out of reach) for LOST_AFTER seconds she lets
## go. A bought Sniper is gone for good once she falls.

const THERMAL_KEY := KEY_T
const SCOPE_IN := 0.22
## Magnifications the scope steps through (the wheel), and the one it starts on.
const ZOOMS := [4.0, 8.0, 12.0]
const START_ZOOM := 1
const SCOPED_WALK := 1.0
## The scope's camera leaves her own body out once it is this far up (SniperTrooper.BODY_LAYER).
const SCOPE_MASK := 0xFFFFF & ~SniperTrooper.BODY_LAYER
## A round's damage, and how far it strays (rad) through the scope and from the hip (third person).
const DAMAGE := 140.0
const SCOPED_SPREAD := 0.0
const HIP_SPREAD := 0.025
## The scope's kick on a shot (rad, up) and how long the view takes to settle back.
const KICK := 0.022
const KICK_TIME := 0.35
const THERMAL_TIME := 15.0
const THERMAL_RECHARGE := 60.0
const TAG_TIME := 20.0
const TAG_LIMIT := 5
## Left to herself: how far she picks targets (m, flat), her rounds' damage and spread, how long she
## settles on her aim before each shot, and how long a target may stay out of her sight before she lets it go.
const AI_RANGE := 160.0
const AI_DAMAGE := 105.0
const AI_SPREAD := 0.002
const AI_SETTLE := 0.6
const LOST_AFTER := 8.0
const SCOPE_COLOR := Color(0.85, 0.3, 0.25)

## Purchase number: "Sniper <number>".
var number := 1
## Where she holds, left to herself.
var hold_at := Vector3.INF
## Left to herself: the attacker she has picked (null: none).
var target: AttackerUnit = null
## Thermal vision: seconds of it left, and until it can go on again.
var thermal_left := 0.0
var thermal_cd := 0.0
## Which of ZOOMS the scope is on.
var zoom := START_ZOOM
## Totals (the showcase and the autotest report them).
var stats := {"rounds": 0, "hits": 0, "tags": 0, "retags": 0, "untagged": 0, "kills": 0, "thermal": 0, "picks": 0}

var _scope_t := 0.0
## The panels show while she is driven (a showcase may hide them).
var _hud_shown := true
var _range := INF
var _kick := 0.0
var _fire_held := false
var _tagged: Array = []
var _lost := 0.0
var _settle := 0.0
var _pick_cd := 0.0
var _notice := ""
var _notice_t := 0.0
var _thermal: SniperThermal
var _sniper_hud: SniperHud
var _scope: SniperScope


func _init() -> void:
	station_kind = "sniper"
	respawns = false
	squad_size = 1
	trooper_hp = SniperTrooper.MAX_HP
	# One body to watch: the camera comes in close over her right shoulder.
	cam_arm = Vector3(0.85, -0.15, 2.6)
	cam_aim_arm = Vector3(0.7, -0.2, 1.9)
	setup(1)


## Names her after her purchase number.
func setup(n: int) -> void:
	number = n
	station_name = "Sniper %d" % n
	hud_title = "SNIPER %d" % n


func _new_trooper() -> SquadTrooper:
	return SniperTrooper.new()


func _ready() -> void:
	super()
	add_to_group("snipers")
	_thermal = SniperThermal.new()
	_thermal.camera = _cam
	add_child(_thermal)
	_sniper_hud = SniperHud.new()
	_sniper_hud.sniper = self
	_sniper_hud.visible = false
	_hud_layer.add_child(_sniper_hud)
	# The scope's mask goes under the defender's panels (DefenderController draws on layer 2).
	var scope_layer := CanvasLayer.new()
	scope_layer.layer = 1
	add_child(scope_layer)
	_scope = SniperScope.new()
	_scope.sniper = self
	_scope.visible = false
	scope_layer.add_child(_scope)


# ---------------------------------------------------------------- station interface

func possess() -> void:
	super()
	_hud.visible = false  # no formation to show
	_sniper_hud.visible = _hud_shown
	_scope_t = 0.0
	_fire_held = true  # the click that took command doesn't fire


func unpossess() -> void:
	super()
	_sniper_hud.visible = false
	_scope.visible = false
	_scope_t = 0.0
	_cam.cull_mask = 0xFFFFF
	_thermal.set_on(false)
	# Left to herself she holds right here.
	if leader:
		hold_at = leader.global_position
	target = null
	_lost = 0.0


func set_hud_visible(on: bool) -> void:
	super(on)
	_hud_shown = on
	_hud.visible = false
	_sniper_hud.visible = on and possessed
	_scope.visible = on and possessed and _scope_t > 0.0


func get_hud_info() -> Dictionary:
	var it := leader as SniperTrooper
	if it == null:
		return {"weapon": "Eclipse Longshot", "status": "—", "hp": 0.0, "hint": ""}
	var status := "READY"
	if it.reloading():
		status = "RELOADING"
	elif it.chamber() < 1.0:
		status = "BOLT"
	if scope_view():
		status += "  ·  %dx" % int(ZOOMS[zoom])
	return {"weapon": "Eclipse Longshot · %d/%d" % [it.ammo, SniperTrooper.MAG], "status": status,
			"heat": it.chamber(), "bar_color": UIKit.ACCENT, "hp": it.hp / it.max_hp, "crosshair": _scope_t <= 0.0,
			"hint": "WASD move · Mouse aim · RMB scope (wheel zoom) · LMB fire · R reload · T thermal · she holds where you leave her"}


func roster_label() -> String:
	return "SNIPER %d" % number


func order_name() -> String:
	return "HOLD"


func doing(driving: bool) -> String:
	if driving:
		return "YOU"
	if target != null and _lost <= 0.0:
		return "ON TARGET"
	return "WATCHING"


func alert() -> bool:
	return false


## She has no auto orders: left to herself she holds where the player left her.
func cycle_order() -> void:
	notify("SHE HOLDS WHERE YOU LEAVE HER")


## A line under the crosshair for a moment.
func notify(text: String) -> void:
	_notice = text
	_notice_t = 2.0


func notice() -> String:
	return _notice if _notice_t > 0.0 else ""


# ---------------------------------------------------------------- the scope

## The player has the scope up (or is bringing it up).
func scoped() -> bool:
	return possessed and leader != null and input.aim and not input.hustle


## How far up the scope is (0 down, 1 at her eye).
func scope_fraction() -> float:
	return _scope_t


## Looking through the scope (all the way up).
func scope_view() -> bool:
	return _scope_t >= 1.0


## The scope's field of view at the zoom it is on: the third-person view's, magnified.
func scope_fov() -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(CAM_FOV) * 0.5) / ZOOMS[zoom]))


func set_zoom(k: int) -> void:
	zoom = clampi(k, 0, ZOOMS.size() - 1)


## How far it is to what the scope's reticle is on (INF: nothing within the rifle's reach).
func scope_range() -> float:
	return _range


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not possessed or pilot != null or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and scoped():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom + 1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom - 1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == THERMAL_KEY:
			toggle_thermal()
			get_viewport().set_input_as_handled()
		elif event.is_action("reload"):
			(leader as SniperTrooper).reload()
			get_viewport().set_input_as_handled()


func _update_camera(delta: float) -> void:
	super(delta)
	_scope_t = move_toward(_scope_t, 1.0 if scoped() else 0.0, delta / SCOPE_IN)
	_kick = maxf(_kick - delta / KICK_TIME, 0.0)
	var w := smoothstep(0.0, 1.0, _scope_t)
	if w > 0.0:
		var it := leader as SniperTrooper
		_cam.global_position = _cam.global_position.lerp(it.eye_point(), w)
		_cam.fov = lerpf(_cam.fov, scope_fov(), w)
	if _kick > 0.0:
		_cam.global_basis = Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch + KICK * _kick * _kick)
	_cam.cull_mask = SCOPE_MASK if _scope_t >= 0.6 else 0xFFFFF
	_scope.visible = _scope_t > 0.0 and possessed and _hud_shown
	if _scope_t > 0.0:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - _cam.global_basis.z * SniperTrooper.RANGE,
				GameConfig.LAYER_ALL_SOLID, leader.exclude)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		_range = from.distance_to(hit.position) if not hit.is_empty() else INF


# ---------------------------------------------------------------- the player

func _player_weapons(_delta: float, hustle: bool) -> void:
	firing = false
	# Walking with the scope up, she goes slowly.
	if scoped():
		var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.move.x, 0.0, input.move.y)
		leader.drive(dir.limit_length(1.0) * SCOPED_WALK)
	var pressed: bool = input.fire and not _fire_held
	_fire_held = input.fire
	if pressed and not hustle:
		fire()


## LMB: a round where the crosshair is, if one is chambered. Through the scope it flies dead down the
## middle of the reticle; from the hip (third person) from her eye at what the crosshair is on, straying a
## little. True if she fired.
func fire() -> bool:
	var it := leader as SniperTrooper
	if it == null or not it.ready_to_fire():
		if it and it.reloading():
			notify("RELOADING")
		return false
	var shot: Dictionary
	if scope_view():
		var from := _cam.global_position
		var dir := -(Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)).z
		shot = it.shoot(from, from + dir * SniperTrooper.RANGE, DAMAGE, SCOPED_SPREAD)
		_kick = 1.0
	else:
		shot = it.shoot(it.eye_point(), aim_point, DAMAGE, HIP_SPREAD)
	_landed(shot)
	return true


## A round landed: what it hit is tagged (as far as her tags go), and the totals.
func _landed(shot: Dictionary) -> void:
	stats.rounds += 1
	var u = shot.unit
	if u == null:
		return
	stats.hits += 1
	if u is AttackerUnit:
		if not u.is_alive():
			stats.kills += 1
		else:
			tag(u)


## Tags `u` (see the class notes): a fresh tag if one of her TAG_LIMIT is free, its time started over if
## she has tagged it already, else nothing.
func tag(u: AttackerUnit) -> void:
	_prune_tags()
	if u in _tagged:
		u.tag(self, TAG_TIME)
		stats.retags += 1
		notify("TAG RENEWED  %d/%d" % [_tagged.size(), TAG_LIMIT])
	elif _tagged.size() < TAG_LIMIT:
		u.tag(self, TAG_TIME)
		_tagged.append(u)
		stats.tags += 1
		notify("TAGGED  %d/%d" % [_tagged.size(), TAG_LIMIT])
	else:
		stats.untagged += 1
		notify("ALL %d TAGS OUT: NO TAG" % TAG_LIMIT)


## The attackers her tags are on now.
func tagged() -> Array:
	_prune_tags()
	return _tagged.duplicate()


func _prune_tags() -> void:
	_tagged = _tagged.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.tag_left(self) > 0.0)


## T: thermal vision on for THERMAL_TIME, or (on) off early. False if it is recharging.
func toggle_thermal() -> bool:
	if thermal_left > 0.0:
		thermal_left = 0.0
		thermal_cd = THERMAL_RECHARGE
		notify("THERMAL OFF · RECHARGING")
		return false
	if thermal_cd > 0.0:
		notify("THERMAL RECHARGING  %ds" % ceili(thermal_cd))
		return false
	thermal_left = THERMAL_TIME
	stats.thermal += 1
	notify("THERMAL VISION  %ds" % int(THERMAL_TIME))
	return true


# ---------------------------------------------------------------- every frame

func _arm_troopers(delta: float) -> void:
	_notice_t = maxf(_notice_t - delta, 0.0)
	if thermal_left > 0.0:
		thermal_left -= delta
		if thermal_left <= 0.0:
			thermal_left = 0.0
			thermal_cd = THERMAL_RECHARGE
			if possessed:
				notify("THERMAL OFF · RECHARGING")
	else:
		thermal_cd = maxf(thermal_cd - delta, 0.0)
	_thermal.set_on(possessed and thermal_left > 0.0)
	_prune_tags()


# ---------------------------------------------------------------- left alone

## She holds where she was left, picks one attacker she can shoot and shoots it until it dies.
func _ai_control(delta: float) -> void:
	firing = false
	var it := leader as SniperTrooper
	it.hustle = false
	if hold_at == Vector3.INF:
		hold_at = it.global_position
	_walk_leader_to(hold_at, 0.6)
	if target != null and not Combat.is_valid_target(target):
		target = null
	_pick_cd -= delta
	if target == null and _pick_cd <= 0.0:
		_pick_cd = 0.5
		target = _pick_target()
		_lost = 0.0
		_settle = 0.0
		if target:
			stats.picks += 1
	if target == null:
		aim_point = _look_out(it.global_position)
		return
	aim_point = Combat.aim_point(target)
	if not can_shoot(target):
		_settle = 0.0
		_lost += delta
		if _lost >= LOST_AFTER:
			target = null
		return
	_lost = 0.0
	if not it.on_aim(aim_point):
		_settle = 0.0
		return
	_settle += delta
	if _settle >= AI_SETTLE and it.ready_to_fire():
		_settle = 0.0
		_landed(it.shoot(it.eye_point(), aim_point, AI_DAMAGE, AI_SPREAD))


## Left to herself, she can shoot `u`: in reach, in sight (not blinded by a flash), not in among the trees
## of a forest (flyers over one she sees).
func can_shoot(u: AttackerUnit) -> bool:
	if leader == null or FlashGrenade.is_blind(leader):
		return false
	var eye := (leader as SniperTrooper).eye_point()
	if _flat(eye, u.global_position) > AI_RANGE:
		return false
	if not u.is_flying() and LevelBuilder.in_forest(u.global_position):
		return false
	return Combat.has_line_of_sight(self, eye, Combat.aim_point(u), u)


## The nearest attacker she can shoot, or null.
func _pick_target() -> AttackerUnit:
	var best: AttackerUnit = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("attacker_units"):
		var d := _flat(leader.global_position, u.global_position)
		if d < best_d and can_shoot(u):
			best_d = d
			best = u
	return best


## A point to look at out from the base (the attackers come from there).
func _look_out(p: Vector3) -> Vector3:
	var out := Vector3(p.x, 0.0, p.z)
	out = out.normalized() if out.length() > 1.0 else Basis(Vector3.UP, heading) * Vector3.FORWARD
	return p + Vector3.UP * 1.5 + out * 40.0
