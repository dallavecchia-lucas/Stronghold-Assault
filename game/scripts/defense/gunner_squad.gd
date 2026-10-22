class_name GunnerSquad
extends DefenderSquad
## Gunner Squad: five minigunners in heavy armor (HeavyGunner), a defender post the player takes
## over in third person (DefenderSquad: formation, following, camera). The troopers fire wherever
## the player aims and fires. Left to itself the squad goes back to its post and holds it, shooting
## at any attacker it can see.

const AI_RANGE := 45.0
## Left to itself the squad hits this much softer, like the other posts' crews.
const AI_DAMAGE_SCALE := 0.3

var _retarget_cd := 0.0
var _target: Node3D = null


func _init() -> void:
	station_name = "Gunner Squad"
	station_kind = "squad"
	hud_title = "GUNNER SQUAD"
	trooper_hp = HeavyGunner.MAX_HP


func _new_trooper() -> SquadTrooper:
	return HeavyGunner.new()


func get_hud_info() -> Dictionary:
	if leader == null:
		return {"weapon": "Minigun", "status": "—", "hp": 0.0, "hint": ""}
	var gun := leader as HeavyGunner
	var status := "HEAT %d%%" % int(gun.heat * 100.0)
	if gun.overheated():
		status = "OVERHEATED"
	elif firing and not gun.spun_up():
		status = "SPINNING UP"
	return {"weapon": "Minigun · %d/%d · %s" % [troopers.size(), SIZE, SquadFormation.MODE_NAMES[formation.mode]],
			"status": status, "heat": gun.heat, "hp": leader.hp / leader.max_hp,
			"hint": "WASD move · Shift hustle · Mouse aim · LMB fire · RMB aim · the squad follows your lead"}


func _arm_troopers(_delta: float) -> void:
	for t in troopers:
		var gun := t as HeavyGunner
		gun.trigger = firing
		gun.damage_scale = 1.0 if possessed else AI_DAMAGE_SCALE


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
