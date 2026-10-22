class_name Structure
extends StaticBody3D
## Destructible defender building (gates, the keep). Blocks navigation while standing.

signal damaged(structure: Structure)
signal destroyed(structure: Structure)

## Seconds a gate's door stays up after the last hold_open(), and to open or shut it.
const OPEN_HOLD := 1.0
const OPEN_TIME := 0.9

var display_name := "Structure"
var max_hp := 1000.0
var hp := 1000.0
var team := GameConfig.TEAM_DEFENDER
## Extra reach for range checks: units attack the surface, not the center.
var target_radius := 4.0
var last_damaged_msec := -100000
## Visual node squashed into rubble on destruction; its half height keeps the rubble on the ground.
var visual: Node3D
var visual_half_height := 3.0
## Inside the mountain: attackers need line of sight to hit it, and flyers can't get at it.
var buried := false
## Gates open for the defenders' Gunner Squad: 0 shut, 1 fully up in the lintel.
var opened := 0.0

var _hold := 0.0


func setup(p_name: String, p_hp: float, p_radius: float) -> void:
	display_name = p_name
	max_hp = p_hp
	hp = p_hp
	target_radius = p_radius


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("structures")
	collision_layer = GameConfig.LAYER_STRUCTURES
	collision_mask = 0
	set_process(false)


## Keeps a gate's door up (the Gunner Squad calls it while its troopers are near): it slides up
## into the lintel, lets everything through while it is up and comes down OPEN_HOLD after the
## last call.
func hold_open() -> void:
	if hp <= 0.0 or visual == null:
		return
	_hold = OPEN_HOLD
	set_process(true)


func _process(delta: float) -> void:
	_hold -= delta
	opened = move_toward(opened, 1.0 if _hold > 0.0 else 0.0, delta / OPEN_TIME)
	visual.position.y = smoothstep(0.0, 1.0, opened) * (visual_half_height * 2.0 - 0.25)
	var through := opened > 0.5
	for c in get_children():
		if c is CollisionShape3D and c.disabled != through:
			c.disabled = through
	if opened <= 0.0 and _hold <= 0.0:
		set_process(false)


func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position


## Where attackers walk to: in front of a gate (it faces out along +Z), the keep itself.
func get_approach_point() -> Vector3:
	if buried:
		return global_position
	var p := global_position + global_basis.z * target_radius
	p.y = 0.0
	return p


func recently_damaged(seconds := 3.0) -> bool:
	return Time.get_ticks_msec() - last_damaged_msec < seconds * 1000.0


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp = maxf(hp - amount, 0.0)
	last_damaged_msec = Time.get_ticks_msec()
	damaged.emit(self)
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	set_process(false)
	opened = 0.0
	if visual:
		visual.position.y = 0.0
	collision_layer = 0
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	Combat.spawn_explosion(self, global_position, 6.0)
	if visual:
		var tw := visual.create_tween()
		tw.tween_property(visual, "scale:y", 0.12, 0.6).set_trans(Tween.TRANS_BOUNCE)
		tw.parallel().tween_property(visual, "position:y", visual.position.y - visual_half_height * 0.88, 0.6)
	destroyed.emit(self)
