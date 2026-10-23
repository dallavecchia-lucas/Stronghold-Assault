class_name SquadPilot
extends RefCounted
## Plays a squad's leader like a player would, for staged videos (DefenderSquad.pilot): the
## movement keys are worked out from the camera's yaw and the camera turns the way a player would
## look. Legs of the route, one after another:
##   {"to": Vector3}             walk there along the navmesh, looking down the way ahead
##   {"look": Vector3}           look there while walking (instead of down the way ahead)
##   {"fire": true}              look at the nearest attacker in sight and hold the trigger (with
##                               none in sight, look at "look" and hold fire)
##   {"hold": seconds}           stand there that long (after reaching "to", if any)
##   {"clear": seconds}          (with "fire") hold on up to this much longer while attackers are in
##                               sight
##   {"speed": 0..1}             how far the stick is pushed
##   {"strafe": Vector2}         push the stick this way instead of toward "to" (for "hold" seconds)

## How far down the path the leader steers for, and looks (m): a player looks where they're going,
## not round the next corner (walking half sideways is the troopers' slowest walk).
const LOOKAHEAD := 1.3
const LOOK_AHEAD := 4.5

## Leg in progress and seconds spent on it.
var leg := 0
var leg_t := 0.0
var route: Array = []
var done := false

var _path := PackedVector3Array()
var _path_i := 0
var _hold := 0.0


func _init(p_route: Array) -> void:
	route = p_route


func current() -> Dictionary:
	return route[leg] if leg < route.size() else {}


func pilot_input(squad: DefenderSquad, delta: float) -> void:
	var leader := squad.leader
	squad.input.move = Vector2.ZERO
	squad.input.fire = false
	squad.input.aim = false
	squad.input.hustle = false
	if leg >= route.size():
		done = true
		return
	leg_t += delta
	var r: Dictionary = route[leg]
	var look = r.get("look")
	var arrived := true
	if r.has("to"):
		if _path.is_empty():
			var map := squad.get_world_3d().navigation_map
			_path = NavigationServer3D.map_get_path(map, leader.global_position, r.to, true, 1 | LevelBuilder.NAV_SQUAD)
			_path_i = 1
			if _path.is_empty():
				return  # the navigation map isn't up yet
		arrived = _path.size() < 2 or _flat(leader.global_position, _path[-1]) < 0.6
		if not arrived:
			# Pure pursuit: steer for the point a little way down the path from where the leader is
			# on it, so corners are taken round instead of cut.
			var to := _chase(leader.global_position, LOOKAHEAD) - leader.global_position
			to.y = 0.0
			var dir := to.normalized()
			var yaw := squad.cam_yaw
			var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var right := Vector3(cos(yaw), 0.0, -sin(yaw))
			squad.input.move = Vector2(dir.dot(right), -dir.dot(fwd)) * float(r.get("speed", 1.0))
			if look == null:
				look = _ahead(leader.global_position, LOOK_AHEAD) + Vector3.UP * 1.2
	if r.has("strafe"):
		squad.input.move = r.strafe
		arrived = true
	if r.get("fire", false):
		var enemy := _nearest_enemy(squad)
		if enemy:
			look = Combat.aim_point(enemy)
		squad.input.fire = enemy != null
	if r.get("aim", false):
		squad.input.aim = true
	if look != null:
		squad.look_toward(look, float(r.get("turn", 2.2)), delta)
	if arrived:
		_hold += delta
		var hold := float(r.get("hold", 0.0))
		if _hold >= hold and not (squad.input.fire and _hold < hold + float(r.get("clear", 0.0))):
			_next()


func _next() -> void:
	leg += 1
	leg_t = 0.0
	_hold = 0.0
	_path = PackedVector3Array()


## The point `dist` meters down the path from the spot on it nearest `at`. Moves _path_i up to
## that spot's segment.
func _chase(at: Vector3, dist: float) -> Vector3:
	var best := _path_i
	var best_d := INF
	var best_p := _path[mini(_path_i, _path.size() - 1)]
	for i in range(maxi(_path_i, 1), _path.size()):
		var a := _path[i - 1]
		var b := _path[i]
		var ab := b - a
		var u := clampf((at - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var p := a + ab * u
		var d := _flat(p, at)
		if d < best_d:
			best_d = d
			best = i
			best_p = p
	_path_i = best
	return _walk(best_p, best, dist)


## A point `dist` meters on along the path from `p`, which lies on the segment ending at path[i].
func _walk(p: Vector3, i: int, dist: float) -> Vector3:
	var left := dist
	for k in range(i, _path.size()):
		var seg := p.distance_to(_path[k])
		if seg >= left:
			return p + (_path[k] - p).normalized() * left
		left -= seg
		p = _path[k]
	return p


## A point `dist` meters further along the path from `from`; past its end, on the way it runs.
func _ahead(from: Vector3, dist: float) -> Vector3:
	var p := from
	var left := dist
	for i in range(_path_i, _path.size()):
		var seg := p.distance_to(_path[i])
		if seg >= left:
			return p + (_path[i] - p).normalized() * left
		left -= seg
		p = _path[i]
	var run := _path[-1] - _path[-2] if _path.size() >= 2 else Vector3.FORWARD
	run.y = 0.0
	return p + run.normalized() * left


func _nearest_enemy(squad: DefenderSquad) -> Node3D:
	var best: Node3D = null
	var best_d := 70.0
	var eye := squad.leader.global_position + Vector3.UP * 1.8
	for u in squad.get_tree().get_nodes_in_group("attacker_units"):
		var d: float = squad.leader.global_position.distance_to(u.global_position)
		if d < best_d and Combat.has_line_of_sight(squad, eye, Combat.aim_point(u), u):
			best_d = d
			best = u
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
