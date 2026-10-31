class_name FlameSquad
extends DefenderSquad
## Flame Squad: five Flame Troopers (FlameTrooper: the Crimson Warden, twin fuel tanks on her back
## and a flame gun at her hip), a squad the defender buys (DefenderArmory) and can take over in
## third person like the Gunner Squad: it walks, follows, paths round trees and files through
## tunnels the same way (DefenderSquad). The troopers burn wherever the player aims and fires: a jet
## of flame FlameTrooper.REACH (6 m) ahead of each, that burns attackers in it (they burn on a moment
## after) and heats the trees it plays on (ForestTree).
##
## Left to itself the squad follows its order (V while driving it, Ctrl+F<n> from anywhere):
##   CLEAR  It clears the forests round the base (LevelBuilder.FORESTS; lone trees out in the field
##          are left standing), closest to the base first and working its way outwards: it walks in
##          formation to the standing forest tree nearest the base (one a little
##          further out but much nearer the squad goes first, so it finishes a stand of trees before
##          walking on). There the troopers spread out, each to a tree of its own (the nearest the
##          base within WORK_RADIUS of the leader), and hold the flame on its trunk until the canopy
##          catches (ForestTree.IGNITE_TIME, 8 s: a quick sweep isn't enough), then go on to the
##          next. With none left in reach it forms up and walks on. Burnt trees fall about 30 s
##          later, and never grow back. With nothing left standing it can get at, it goes back to
##          its post.
##   GUARD  It stays where it is.
## Either way, attackers that come within ENGAGE_RANGE come first: it forms up, walks at the nearest
## (on GUARD, no further than GUARD_STEP off its post) and burns it, then goes back to its order. A
## bought squad is gone for good once all five troopers are down (lost ones are replaced from the
## hall it deployed in until then).

enum Order { CLEAR, GUARD }
const ORDER_NAMES := ["CLEAR", "GUARD"]
const ORDER_KEY := KEY_V
## Left to itself the squad burns this much softer, like the other posts' crews.
const AI_DAMAGE_SCALE := 0.5
## Attackers this close to the squad (flat, m, in sight) come before its order; it walks at them
## until FIGHT_RANGE off and lets them go past LOSE_RANGE. On GUARD it steps at most GUARD_STEP off
## its post.
const ENGAGE_RANGE := 16.0
const LOSE_RANGE := 24.0
const FIGHT_RANGE := 3.8
const GUARD_STEP := 6.0
## Clearing: each trooper takes on trees within WORK_RADIUS of the leader, and burns one from a spot
## STAND off its trunk (on the navmesh, with a clear line to it: no closer than STAND_MIN, no further
## than STAND_MAX), once within SPOT_REACH of the spot.
const WORK_RADIUS := 14.0
const STAND := 3.4
const STAND_MIN := 2.2
const STAND_MAX := FlameTrooper.REACH - 1.4
const SPOT_REACH := 0.7
## Two troopers' spots are at least this far apart (m).
const SPOT_ROOM := 1.6
## A tree nearer the squad goes before one nearer the base when it is this much nearer per meter
## the other is nearer the base.
const WALK_COST := 0.5
## Left to itself the squad walks (its leader no faster than this, m/s), it doesn't hurry.
const AI_WALK := SquadTrooper.CLIP_FORWARD * 1.1
## Seconds between looks round for attackers, and (with nothing left to burn) for trees; physics
## frames before a trooper with no tree in reach looks for one again.
const SEARCH_EVERY := 0.4
const IDLE_SEARCH := 4.0
const LOOK_AGAIN := 10
const FLAME_COLOR := Color(1.0, 0.52, 0.16)

## Purchase number: "Flame Squad <number>".
var number := 1
var order := Order.CLEAR
## What the CLEAR order is doing: "seek" (walking to the next tree), "burn" (the troopers each
## burning a tree), "done" (nothing standing it can get at: back at its post).
var plan := "seek"
## Where the GUARD order holds.
var guard_post := Vector3.INF
## The tree the squad walks to (seek); each trooper's tree and the spot it burns it from (burn).
var anchor: ForestTree = null
var jobs := {}
var spots := {}
## The attacker the squad goes after (null: none).
var enemy: Node3D = null
## Every tree the squad has set alight, in order (the showcase checks them).
var burnt: Array[ForestTree] = []
var stats := {"trees": 0}

var _search_cd := 0.0
var _idle_cd := 0.0
## Where the leader burns the anchor from (seek).
var _anchor_spot := Vector3.INF
## Trees there is no spot to burn from (left standing).
var _skip := {}
## Per trooper with no tree in reach: the physics frame it looks for one again.
var _next_look := {}
## Left alone, per trooper: where it aims and whether it burns.
var _aims := {}
var _fires := {}
var _flame_hud: FlameHud


func _init() -> void:
	station_kind = "flame_squad"
	respawns = false
	trooper_hp = FlameTrooper.MAX_HP
	setup(1)


## Names the squad after its purchase number.
func setup(n: int) -> void:
	number = n
	station_name = "Flame Squad %d" % n
	hud_title = "FLAME SQUAD %d" % n


func _new_trooper() -> SquadTrooper:
	return FlameTrooper.new()


func _ready() -> void:
	super()
	add_to_group("flame_squads")
	_flame_hud = FlameHud.new()
	_flame_hud.squad = self
	_flame_hud.visible = false
	_hud_layer.add_child(_flame_hud)


# ---------------------------------------------------------------- station interface

func possess() -> void:
	super()
	_flame_hud.visible = true
	_release_all()


func unpossess() -> void:
	super()
	_flame_hud.visible = false
	# Handed back: the order takes over from where the squad stands.
	plan = "seek"
	anchor = null
	guard_post = leader.global_position if leader else home.origin


func set_hud_visible(on: bool) -> void:
	super(on)
	_flame_hud.visible = on and possessed


func get_hud_info() -> Dictionary:
	if leader == null:
		return {"weapon": "Flamer", "status": "—", "hp": 0.0, "hint": ""}
	var ft := leader as FlameTrooper
	var status := "PRESSURE %d%%" % int(ft.pressure * 100.0)
	if ft.venting():
		status = "VENTING"
	elif ft.flaming:
		status = "BURNING"
	return {"weapon": "Flamer · %d/%d · %s" % [troopers.size(), SIZE, SquadFormation.MODE_NAMES[formation.mode]],
			"status": status, "heat": ft.pressure, "bar_color": FLAME_COLOR, "hp": leader.hp / leader.max_hp,
			"hint": "WASD move · Shift hustle · Mouse aim · LMB flame (6 m) · hold it on a trunk 8 s to burn a tree · V order (%s)" % ORDER_NAMES[order]}


## For the roster (SquadHotbar): its name in a slot, its order, and what it is up to.
func roster_label() -> String:
	return "FLAME %d" % number


func order_name() -> String:
	return ORDER_NAMES[order]


func order_color() -> Color:
	return FLAME_COLOR if order == Order.CLEAR else UIKit.WARN


## True while the slot should catch the eye (fighting).
func alert() -> bool:
	return Combat.is_valid_target(enemy) and not possessed


func doing(driving: bool) -> String:
	if driving:
		return "YOU"
	if Combat.is_valid_target(enemy):
		return "FIGHTING"
	if order == Order.GUARD:
		return "HOLDING"
	return {"seek": "TO TREES", "burn": "BURNING", "done": "CLEARED"}.get(plan, "")


## Next auto order (CLEAR -> GUARD -> CLEAR). Takes effect at once if nobody drives the squad.
func cycle_order() -> void:
	set_order(((order + 1) % ORDER_NAMES.size()) as Order)


func set_order(o: Order) -> void:
	order = o
	guard_post = leader.global_position if leader else home.origin
	plan = "seek"
	anchor = null
	_release_all()


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not possessed or pilot != null or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == ORDER_KEY:
		cycle_order()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- weapons

func _arm_troopers(_delta: float) -> void:
	for t in troopers:
		var ft := t as FlameTrooper
		if possessed:
			ft.trigger = firing
			ft.damage_scale = 1.0
			continue
		ft.trigger = _fires.get(t, false) and not FlashGrenade.is_blind(t)  # flashed: holds its fire
		ft.damage_scale = AI_DAMAGE_SCALE
		var at: Vector3 = _aims.get(t, Vector3.INF)
		if at != Vector3.INF:
			t.aim_point = at
			t.aim_parallel = false


# ---------------------------------------------------------------- left alone

func _ai_control(delta: float) -> void:
	for t in troopers:
		t.hustle = false
		t.walk_limit = AI_WALK if t == leader or free.has(t) else INF
	_aims.clear()
	_fires.clear()
	_search_cd -= delta
	if _search_cd <= 0.0:
		_search_cd = SEARCH_EVERY
		enemy = _find_enemy()
	if Combat.is_valid_target(enemy):
		_fight()
		return
	enemy = null
	if order == Order.GUARD:
		_release_all()
		if guard_post == Vector3.INF:
			guard_post = leader.global_position
		_walk_leader_to(guard_post, 2.0)
		aim_point = _look_out(leader.global_position)
		return
	_clear(delta)


## The attacker to go after: the one it has while it is within LOSE_RANGE, else the nearest on the
## ground within ENGAGE_RANGE, in sight.
func _find_enemy() -> Node3D:
	var here := leader.global_position
	var eye := here + Vector3.UP * 1.8
	if Combat.is_valid_target(enemy) and _flat(here, enemy.global_position) < LOSE_RANGE:
		return enemy
	var best: Node3D = null
	var best_d := ENGAGE_RANGE
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if u.is_in_group("air_units") or not u.is_alive():
			continue
		var d := _flat(here, u.global_position)
		if d < best_d and Combat.has_line_of_sight(self, eye, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best


## Formed up, at the attacker: each trooper burns the nearest attacker in its reach.
func _fight() -> void:
	_release_all()
	var at := enemy.global_position
	if order == Order.GUARD:
		if guard_post == Vector3.INF:
			guard_post = leader.global_position
		var step := Vector3(at.x - guard_post.x, 0.0, at.z - guard_post.z).limit_length(GUARD_STEP)
		_walk_leader_to(guard_post + step, FIGHT_RANGE if step.length() < GUARD_STEP else 1.0)
	else:
		_walk_leader_to(at, FIGHT_RANGE)
	aim_point = Combat.aim_point(enemy)
	var units := get_tree().get_nodes_in_group("attacker_units")
	for t in troopers:
		var near: Node3D = enemy
		var near_d := _flat(t.global_position, enemy.global_position)
		for u in units:
			if u.is_in_group("air_units") or not u.is_alive():
				continue
			var d := _flat(t.global_position, u.global_position)
			if d < near_d:
				near_d = d
				near = u
		_aims[t] = Combat.aim_point(near)
		_fires[t] = near_d < FlameTrooper.REACH + 0.3


## The CLEAR order.
func _clear(delta: float) -> void:
	if not _nav_ready:
		return
	match plan:
		"done":
			_release_all()
			_walk_leader_to(home.origin, HOME_REACH)
			aim_point = _look_out(leader.global_position)
			_idle_cd -= delta
			if _idle_cd <= 0.0:
				_idle_cd = IDLE_SEARCH
				if _pick_anchor() != null:
					plan = "seek"
		"seek":
			_seek()
		"burn":
			_work()


## Walking in formation to the next tree; close enough, the troopers spread out to burn.
func _seek() -> void:
	_release_all()
	if not _claimable(anchor, leader):
		anchor = _pick_anchor()
		if anchor == null:
			plan = "done"
			_idle_cd = IDLE_SEARCH
			return
		_anchor_spot = _spot_for(leader, anchor)
	if _anchor_spot == Vector3.INF:
		_skip[anchor] = true
		anchor = null
		return
	var there := _walk_leader_to(_anchor_spot, SPOT_REACH)
	var v := Vector3(leader.velocity.x, 0.0, leader.velocity.z)
	aim_point = leader.global_position + Vector3.UP * 1.4 + (v.normalized() if v.length() > 0.3 else Vector3.FORWARD) * 20.0
	if v.length() <= 0.3:
		aim_point = anchor.aim_point()
	if there or _flat(leader.global_position, anchor.global_position) < WORK_RADIUS * 0.6:
		plan = "burn"


## Each trooper burns a tree of its own; done with it, it takes the next. With none left in reach
## of the leader, the squad forms up and walks on.
func _work() -> void:
	for t in jobs.keys():
		if not troopers.has(t):
			_drop(t)
	for t in troopers:
		var job: ForestTree = jobs.get(t)
		if job != null and is_instance_valid(job) and not job.is_standing() and not burnt.has(job):
			burnt.append(job)
			stats.trees += 1
		if not _claimable(job, t) or spots.get(t, Vector3.INF) == Vector3.INF:
			_drop(t)
			# Nothing it can get at: it looks again a moment later.
			if Engine.get_physics_frames() < _next_look.get(t, 0):
				continue
			var next := _next_tree(t)
			if next.is_empty():
				_next_look[t] = Engine.get_physics_frames() + LOOK_AGAIN
				continue
			jobs[t] = next[0]
			spots[t] = next[1]
			(next[0] as ForestTree).claimed_by = t
	if jobs.is_empty():
		plan = "seek"
		anchor = null
		_release_all()
		return
	free.clear()
	leader.following = false
	var lead_job: ForestTree = jobs.get(leader)
	for t in jobs:
		var tree: ForestTree = jobs[t]
		var spot: Vector3 = spots[t]
		var there := _flat(t.global_position, spot) < SPOT_REACH
		if t == leader:
			there = _walk_leader_to(spot, SPOT_REACH * 0.5) or there
		else:
			free[t] = spot
		_aims[t] = tree.aim_point()
		_fires[t] = there
	if lead_job:
		aim_point = lead_job.aim_point()
	else:
		# The leader has nothing in reach: it waits, watching the nearest trooper at work.
		var near: ForestTree = null
		for tree in jobs.values():
			if near == null or _flat(tree.global_position, leader.global_position) < _flat(near.global_position, leader.global_position):
				near = tree
		aim_point = near.aim_point()


## The tree the squad walks to next: the standing one nearest the base, unless one nearly as near
## is much nearer the squad (WALK_COST).
func _pick_anchor() -> ForestTree:
	var here := leader.global_position
	for tries in 6:
		var best: ForestTree = null
		var best_cost := INF
		for tree in ForestTree.standing:
			if tree.grove < 0 or not _claimable(tree, leader):
				continue
			var cost := LevelBuilder.base_distance(tree.global_position) + WALK_COST * _flat(here, tree.global_position)
			if cost < best_cost:
				best_cost = cost
				best = tree
		if best == null:
			return null
		if _spot_for(leader, best) != Vector3.INF:
			return best
		_skip[best] = true
	return null


## The next tree for trooper `t`, within WORK_RADIUS of the leader: [tree, spot], or [] if none.
func _next_tree(t: SquadTrooper) -> Array:
	var lpos := leader.global_position
	var cands: Array = []
	for tree in ForestTree.near(lpos, WORK_RADIUS + 1.0):
		if tree.grove < 0 or _flat(lpos, tree.global_position) > WORK_RADIUS or not _claimable(tree, t):
			continue
		cands.append([LevelBuilder.base_distance(tree.global_position) + WALK_COST * _flat(t.global_position, tree.global_position), tree])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands.slice(0, 4):
		var spot := _spot_for(t, c[1])
		if spot != Vector3.INF:
			return [c[1], spot]
	return []


## Where trooper `t` burns `tree` from: STAND off the trunk on its side (or round it), on the
## navmesh, clear of the other troopers' spots and with a clear line to the trunk. INF: nowhere.
func _spot_for(t: SquadTrooper, tree: ForestTree) -> Vector3:
	var map := get_world_3d().navigation_map
	var tp := tree.global_position
	var away := Vector3(t.global_position.x - tp.x, 0.0, t.global_position.z - tp.z)
	if away.length() < 0.5:
		away = Vector3(-tp.x, 0.0, -tp.z)
	away = away.normalized()
	var space := get_world_3d().direct_space_state
	for k in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5]:
		var d := away.rotated(Vector3.UP, k * 0.55)
		var p := LevelBuilder.nav_closest(map, tp + d * STAND + Vector3.UP * 0.5)
		var r := _flat(p, tp)
		if r < STAND_MIN or r > STAND_MAX or absf(p.y - tp.y) > 1.5:
			continue
		var crowded := false
		for o in spots:
			if o != t and _flat(spots[o], p) < SPOT_ROOM:
				crowded = true
				break
		if crowded:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.9, tree.aim_point(), GameConfig.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider != tree:
			continue
		return p
	return Vector3.INF


func _claimable(tree: ForestTree, by: Node) -> bool:
	if tree == null or not is_instance_valid(tree) or not tree.is_standing() or _skip.has(tree):
		return false
	var c := tree.claimed_by
	return c == null or c == by or not is_instance_valid(c) or not c.is_alive()


func _drop(t: Node) -> void:
	var job: ForestTree = jobs.get(t)
	if job != null and is_instance_valid(job) and job.claimed_by == t:
		job.claimed_by = null
	jobs.erase(t)
	spots.erase(t)
	free.erase(t)


func _release_all() -> void:
	for t in jobs.keys():
		_drop(t)
	jobs.clear()
	spots.clear()
	free.clear()


## A point to look at out from the base (the attackers come from there).
func _look_out(p: Vector3) -> Vector3:
	var out := Vector3(p.x, 0.0, p.z)
	out = out.normalized() if out.length() > 1.0 else Basis(Vector3.UP, heading) * Vector3.FORWARD
	return p + Vector3.UP * 1.6 + out * 30.0
