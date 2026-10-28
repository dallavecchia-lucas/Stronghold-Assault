class_name InfiltratorSquad
extends DefenderSquad
## Infiltrator Squad: five Infiltrators (InfiltratorTrooper: the Harpy Vanguard with a recurve bow),
## a deep infiltration squad for ambushes and sabotage that the defender buys (DefenderArmory). It
## walks, follows and files through tunnels like every squad (DefenderSquad). Driven by the player:
##   - LMB: every trooper looses an arrow at the aim, then draws the next. The bows are silent
##     (Arrow): no tracer, no flash, so the attacking player only sees their units' health going.
##   - Q, adaptive camo: CAMO_TIME of camouflage for the whole squad, ready again CAMO_COOLDOWN after
##     it went on. Basic attacks can't target the troopers (their shots pass through them, orders to
##     attack them lapse); area damage (bombs, shells, cluster bombs, rockets, strafing runs) still
##     hurts and kills them. On the attacker's side they vanish from sight; on the defender's
##     they look as ever and the squad's camera gets a vignette while it lasts (InfiltratorHud).
##     They can shoot under it, but the first arrow loosed gives them away: the camo comes off
##     (break_camo). Going under camo also hides troopers a giraffe's ping revealed
##     (InfiltratorTrooper.revealed).
##   - F, sabotage: next to an attacker building the attackers hold (AttackerBase: the leader within
##     AttackerBase.SABOTAGE_REACH of its deck), the squad sabotages it, AttackerBase.SABOTAGE_TIME
##     (45 s) with the leader staying that close. Done, the attackers lose control of it until they
##     retake it. The squad carries one sabotage kit: used, it has to go back into the fortress (behind
##     the faces, in_fortress) to restock it. F again calls it off.
## Passive, low profile (every trooper): attackers never pick an infiltrator out on their own, only
## when the attacking player orders an attack on one (Combat.low_profile).
##
## Left to itself the squad never shoots (it would give itself away) and follows its auto order (V
## while driving it, Ctrl+F<n> from anywhere, cycling through HOLD and the buildings the attackers
## hold):
##   HOLD   It stays where it was left.
##   OP <x> A sabotage operation against helipad <x>, its idle mode: out of the fortress, it heads for
##          the helipad by a route that keeps as far from the attackers as it can while still heading
##          there (SneakRoute, replanned every REPLAN seconds as they move), up to the spot round the
##          deck where the fewest are, sabotages it, and comes home (restocking its kit) to HOLD in
##          its hall. Out of kits it restocks first. It never puts its camo on by itself: that is the
##          player's call.
## A bought squad is gone for good once all five troopers are down (lost ones are replaced from the
## hall it deployed in until then).

const CAMO_KEY := KEY_Q
const SABOTAGE_KEY := KEY_F
const ORDER_KEY := KEY_V
const CAMO_TIME := 20.0
const CAMO_COOLDOWN := 60.0
## Left alone: seconds between route plans and sabotage spot picks, how far ahead along the route the
## leader makes for (m) and how fast it walks (m/s).
const REPLAN := 1.0
const SPOT_EVERY := 3.0
const LOOKAHEAD := 12.0
const AI_WALK := SquadTrooper.CLIP_FORWARD * 1.1
## The spots it sabotages a helipad from: this far off its deck (well inside SABOTAGE_REACH).
const SPOT_OUT := 2.2
## Out of the mountain through a gate: the leader makes for this far out in front of the door (m).
const GATE_OUT := 10.0
const CAMO_COLOR := Color(0.35, 0.9, 0.75)

## Purchase number: "Infiltrator Squad <number>".
var number := 1
## The auto order: the helipad of a sabotage operation, or null (HOLD).
var op: AttackerBase = null
## What the order is doing: "hold" (where it was left), "restock" (back to the fortress for a kit),
## "approach" (on its way to the helipad), "sabotage" (at it), "home" (back to its hall, done).
var plan := "hold"
var hold_at := Vector3.INF
## Sabotage kits it carries (one at most), and the building it is sabotaging (null: none).
var kits := 1
var sabotaging: AttackerBase = null
## Adaptive camo: seconds of it left, and until it can go on again.
var camo_left := 0.0
var camo_cd := 0.0
## The route it walks to its operation (world points), and the spot by the deck it makes for.
var route := PackedVector3Array()
var spot := Vector3.INF
## Totals (the autotest reports them).
var stats := {"sabotaged": 0, "camo": 0, "camo_broken": 0, "plans": 0}

var _replan_cd := 0.0
var _spot_cd := 0.0
var _notice := ""
var _notice_t := 0.0
var _infil_hud: InfiltratorHud


func _init() -> void:
	station_kind = "infiltrator_squad"
	respawns = false
	trooper_hp = InfiltratorTrooper.MAX_HP
	setup(1)


## Names the squad after its purchase number.
func setup(n: int) -> void:
	number = n
	station_name = "Infiltrator Squad %d" % n
	hud_title = "INFILTRATORS %d" % n


func _new_trooper() -> SquadTrooper:
	return InfiltratorTrooper.new()


func _ready() -> void:
	super()
	add_to_group("infiltrator_squads")
	_infil_hud = InfiltratorHud.new()
	_infil_hud.squad = self
	_infil_hud.visible = false
	_hud_layer.add_child(_infil_hud)
	_hud_layer.move_child(_infil_hud, 0)  # the camo vignette under the panels


## A reinforcement joining while the camo is on wears it too.
func _spawn(at: Vector3) -> SquadTrooper:
	var t := super(at)
	if camo_left > 0.0:
		(t as InfiltratorTrooper).set_camo(true, _camo_hidden())
	return t


# ---------------------------------------------------------------- station interface

func possess() -> void:
	super()
	_infil_hud.visible = true


func unpossess() -> void:
	super()
	_infil_hud.visible = false
	# Handed back mid-sabotage, it sees it through; otherwise the order takes over from here.
	if sabotaging != null and op == null:
		op = sabotaging
	_resume()


func set_hud_visible(on: bool) -> void:
	super(on)
	_infil_hud.visible = on and possessed


func get_hud_info() -> Dictionary:
	if leader == null:
		return {"weapon": "Bow", "status": "—", "hp": 0.0, "hint": ""}
	var it := leader as InfiltratorTrooper
	var status := "ARROW READY" if it.draw >= 1.0 else "DRAWING"
	if sabotaging != null:
		status = "SABOTAGE %d%%" % int(sabotaging.sabotage_fraction() * 100.0)
	elif camo_left > 0.0:
		status = "CAMO %ds" % ceili(camo_left)
	return {"weapon": "Bow · %d/%d · %s" % [troopers.size(), SIZE, SquadFormation.MODE_NAMES[formation.mode]],
			"status": status, "heat": it.draw, "bar_color": CAMO_COLOR, "hp": leader.hp / leader.max_hp,
			"hint": "WASD move · Mouse aim · LMB arrow (silent) · Q camo · F sabotage (next to an enemy helipad) · V order (%s)" % order_name()}


func roster_label() -> String:
	return "INFIL %d" % number


func order_name() -> String:
	return "HOLD" if op == null else "OP %s" % op.code


func order_color() -> Color:
	return UIKit.WARN if op == null else CAMO_COLOR


## True while the slot should catch the eye (sabotaging).
func alert() -> bool:
	return sabotaging != null and not possessed


func doing(driving: bool) -> String:
	if sabotaging != null:
		return "SABOT %d%%" % int(sabotaging.sabotage_fraction() * 100.0)
	if driving:
		return "YOU"
	match plan:
		"restock":
			return "RESTOCK"
		"approach":
			return "TO %s" % op.short_name.to_upper() if op != null else ""
		"home":
			return "HOME"
	return "HOLDING"


## Next auto order: HOLD, then each helipad the attackers hold. Takes effect at once if nobody
## drives the squad.
func cycle_order() -> void:
	var options: Array = [null]
	for b in get_tree().get_nodes_in_group("attacker_bases"):
		if b.controlled:
			options.append(b)
	var k := options.find(op)
	set_order(options[(k + 1) % options.size()])


func set_order(o: AttackerBase) -> void:
	op = o
	if possessed:
		notify("ORDER %s · LEAVE THE SQUAD TO SEND IT" % order_name() if op != null else "ORDER HOLD")
	else:
		_resume()


## Picks the order's plan up from where the squad is.
func _resume() -> void:
	if op != null and (not is_instance_valid(op) or not op.controlled):
		op = null
	route.clear()
	spot = Vector3.INF
	_replan_cd = 0.0
	_spot_cd = 0.0
	if op == null:
		plan = "hold"
		hold_at = leader.global_position if leader else home.origin
	elif sabotaging == op:
		plan = "sabotage"
	elif kits <= 0:
		plan = "restock"
	else:
		plan = "approach"


## A line under the crosshair for a moment.
func notify(text: String) -> void:
	_notice = text
	_notice_t = 2.0


func notice() -> String:
	return _notice if _notice_t > 0.0 else ""


# ---------------------------------------------------------------- the player

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not possessed or pilot != null or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			CAMO_KEY:
				start_camo()
			SABOTAGE_KEY:
				toggle_sabotage()
			ORDER_KEY:
				cycle_order()
			_:
				return
		get_viewport().set_input_as_handled()


## Q: the whole squad goes under adaptive camo for CAMO_TIME. False while it is cooling down.
func start_camo() -> bool:
	if camo_cd > 0.0:
		notify("CAMO READY IN %ds" % ceili(camo_cd))
		return false
	camo_left = CAMO_TIME
	camo_cd = CAMO_COOLDOWN
	stats.camo += 1
	for t in troopers:
		(t as InfiltratorTrooper).set_camo(true, _camo_hidden())
	return true


## An arrow loosed under camo: it comes off the whole squad at once (the cooldown runs on as it was).
func break_camo() -> void:
	if camo_left <= 0.0:
		return
	camo_left = 0.0
	for t in troopers:
		(t as InfiltratorTrooper).set_camo(false, _camo_hidden())
	stats.camo_broken += 1
	if possessed:
		notify("CAMO BROKEN: YOU FIRED")


## On the attacker's side the camo hides the troopers from sight; the defender sees them.
static func _camo_hidden() -> bool:
	return GameConfig.player_side == GameConfig.PlayerSide.ATTACKER


## F: starts sabotaging the attacker building in reach, or calls it off.
func toggle_sabotage() -> void:
	if sabotaging != null:
		sabotaging = null
		notify("SABOTAGE CALLED OFF")
		return
	if kits <= 0:
		notify("NO SABOTAGE KIT: RESTOCK IN THE FORTRESS")
		return
	var b := base_in_reach()
	if b == null:
		notify("NO ENEMY BUILDING IN REACH")
		return
	sabotaging = b
	notify("SABOTAGING %s · STAY CLOSE" % b.display_name.to_upper())


## The nearest building the attackers hold with the leader within reach to sabotage it, or null.
func base_in_reach() -> AttackerBase:
	if leader == null:
		return null
	var best: AttackerBase = null
	var best_d := AttackerBase.SABOTAGE_REACH
	for b in get_tree().get_nodes_in_group("attacker_bases"):
		var d: float = b.edge_distance(leader.global_position)
		if b.controlled and d <= best_d:
			best_d = d
			best = b
	return best


## The nearest building the attackers hold, and how far its deck is (for the panel): [base, m].
func nearest_base() -> Array:
	var best: AttackerBase = null
	var best_d := INF
	if leader:
		for b in get_tree().get_nodes_in_group("attacker_bases"):
			var d: float = b.edge_distance(leader.global_position)
			if b.controlled and d < best_d:
				best_d = d
				best = b
	return [best, best_d]


## Behind the stronghold's faces: inside the mountain, where a used kit is restocked.
static func in_fortress(p: Vector3) -> bool:
	return maxf(absf(p.x), absf(p.z)) < LevelBuilder.FACE_DIST - 2.0


# ---------------------------------------------------------------- every frame

func _arm_troopers(delta: float) -> void:
	_notice_t = maxf(_notice_t - delta, 0.0)
	camo_cd = maxf(camo_cd - delta, 0.0)
	if camo_left > 0.0:
		camo_left -= delta
		if camo_left <= 0.0:
			camo_left = 0.0
			for t in troopers:
				(t as InfiltratorTrooper).set_camo(false, _camo_hidden())
			if possessed:
				notify("CAMO OFF")
	for t in troopers:
		(t as InfiltratorTrooper).trigger = firing and possessed
	if sabotaging != null:
		_work_sabotage(delta)
	if kits < 1 and leader != null and in_fortress(leader.global_position):
		kits = 1
		notify("SABOTAGE KIT RESTOCKED")


func _work_sabotage(delta: float) -> void:
	var b := sabotaging
	if not is_instance_valid(b) or not b.controlled:
		sabotaging = null
		return
	if b.edge_distance(leader.global_position) > AttackerBase.SABOTAGE_REACH:
		sabotaging = null
		notify("TOO FAR: THE SABOTAGE IS LOST")
		return
	if b.saboteur != null and b.saboteur != self and is_instance_valid(b.saboteur):
		sabotaging = null
		notify("ANOTHER SQUAD IS ON IT")
		return
	if not b.work_sabotage(self, delta):
		return
	sabotaging = null
	kits = 0
	stats.sabotaged += 1
	notify("%s SABOTAGED" % b.display_name.to_upper())
	if op == b:
		op = null
		if not possessed:
			plan = "home"
			route.clear()


# ---------------------------------------------------------------- left alone

func _ai_control(delta: float) -> void:
	for t in troopers:
		t.hustle = false
		t.walk_limit = AI_WALK if t == leader else INF
	firing = false
	if op != null and (not is_instance_valid(op) or not op.controlled) and plan != "home":
		# Lost by the attackers some other way: nothing left to do there.
		op = null
		plan = "home"
		route.clear()
	match plan:
		"hold":
			if hold_at == Vector3.INF:
				hold_at = leader.global_position
			_walk_leader_to(hold_at, 2.0)
			aim_point = _look_out(leader.global_position)
		"restock":
			if kits > 0:
				plan = "approach" if op != null else "home"
				route.clear()
			else:
				_go_home(delta)
		"approach":
			_approach(delta)
		"sabotage":
			_hold_sabotage()
		"home":
			if _go_home(delta):
				plan = "hold"
				hold_at = home.origin


## On the way to the operation's helipad: to the least watched spot round its deck (picked again
## every SPOT_EVERY), by a route round the attackers; there, it starts the sabotage.
func _approach(delta: float) -> void:
	if op == null:
		plan = "home"
		return
	if kits <= 0:
		plan = "restock"
		route.clear()
		return
	if op.edge_distance(leader.global_position) <= AttackerBase.SABOTAGE_REACH * 0.8:
		plan = "sabotage"
		sabotaging = op
		leader.following = false
		return
	_spot_cd -= delta
	if spot == Vector3.INF or _spot_cd <= 0.0:
		_spot_cd = SPOT_EVERY
		spot = _pick_spot()
	if spot == Vector3.INF:
		return
	_sneak(spot, delta)


## At the helipad, sabotaging: the leader stays put, everyone watching the deck. Pushed out of reach
## it walks back up to its spot.
func _hold_sabotage() -> void:
	if op == null:
		plan = "home"
		return
	if sabotaging == null:
		if op.controlled and kits > 0:
			plan = "approach"
		return
	if spot != Vector3.INF:
		_walk_leader_to(spot, 0.8)
	else:
		leader.following = false
	aim_point = op.global_position + Vector3.UP * AttackerBase.DECK_HEIGHT


## Back to its hall: out in the field, round the attackers to the gate nearest it, then in through the
## tunnels. True once it is there.
func _go_home(delta: float) -> bool:
	var here := leader.global_position
	if _in_mountain(here):
		var there := _walk_leader_to(home.origin, HOME_REACH * 2.0)
		_face_walk()
		return there
	var exit := _gate_exit(home.origin)
	if _flat(here, exit) <= GATE_OUT * 0.6:
		_walk_leader_to(home.origin, HOME_REACH * 2.0)
		_face_walk()
		return false
	_sneak(exit, delta)
	return false


## The leader walks for `dest` out in the field, along a route that keeps away from the attackers
## (SneakRoute), replanned every REPLAN seconds. Still inside the mountain, it first walks out through
## the gate nearest `dest`.
func _sneak(dest: Vector3, delta: float) -> void:
	var here := leader.global_position
	if _in_mountain(here):
		_walk_leader_to(_gate_exit(dest), 1.5)
		_face_walk()
		return
	_replan_cd -= delta
	if _replan_cd <= 0.0 or route.is_empty():
		_replan_cd = REPLAN
		route = SneakRoute.plan(get_world_3d(), here, dest, SneakRoute.attackers(self))
		stats.plans += 1
	_walk_leader_to(_route_point(here, dest), 0.6)
	_face_walk()


## The point on the route LOOKAHEAD on from where the leader is (`dest` once the route runs out).
func _route_point(here: Vector3, dest: Vector3) -> Vector3:
	if route.is_empty():
		return dest
	var k0 := 0
	var best := INF
	for k in route.size():
		var d := _flat(here, route[k])
		if d < best:
			best = d
			k0 = k
	for k in range(k0, route.size()):
		if _flat(here, route[k]) >= LOOKAHEAD:
			return route[k]
	return route[route.size() - 1]


## Where to sabotage the operation's helipad from: of the spots round its deck the navmesh reaches,
## the one with the fewest attackers near it (INF: none).
func _pick_spot() -> Vector3:
	var units := SneakRoute.attackers(self)
	var map := get_world_3d().navigation_map
	var best := Vector3.INF
	var best_cost := INF
	for s in op.spots_around(SPOT_OUT):
		var p := NavigationServer3D.map_get_closest_point(map, s + Vector3.UP * 0.5)
		if _flat(p, s) > 2.0 or op.edge_distance(p) > AttackerBase.SABOTAGE_REACH * 0.7:
			continue
		var cost := SneakRoute.threat_at(p, units) * 100.0 + _flat(leader.global_position, p) * 0.05
		if cost < best_cost:
			best_cost = cost
			best = p
	return best


## In the mountain (the tunnels, halls, decks and roofs, and the rock's foot): the way out is the
## navmesh's, through a gate.
static func _in_mountain(p: Vector3) -> bool:
	return LevelBuilder.base_distance(p) <= 0.0 or p.y > 1.5


## Out in front of the gate nearest `p`.
func _gate_exit(p: Vector3) -> Vector3:
	var best := Vector3.INF
	for g in gates:
		if not is_instance_valid(g):
			continue
		var out: Vector3 = g.global_basis.z.normalized()
		var at: Vector3 = g.global_position + out * GATE_OUT
		at.y = 0.0
		if best == Vector3.INF or _flat(at, p) < _flat(best, p):
			best = at
	return best if best != Vector3.INF else home.origin


## Walking: the troopers look the way they go.
func _face_walk() -> void:
	var v := Vector3(leader.velocity.x, 0.0, leader.velocity.z)
	if v.length() > 0.3:
		aim_point = leader.global_position + Vector3.UP * 1.4 + v.normalized() * 30.0


## A point to look at out from the base (the attackers come from there).
func _look_out(p: Vector3) -> Vector3:
	var out := Vector3(p.x, 0.0, p.z)
	out = out.normalized() if out.length() > 1.0 else Basis(Vector3.UP, heading) * Vector3.FORWARD
	return p + Vector3.UP * 1.6 + out * 30.0
