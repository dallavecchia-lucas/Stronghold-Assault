class_name AttackerBase
extends StaticBody3D
## A Forward Helipad Base: an attacker building out in the field, one by each attack lane
## (LevelBuilder.BASES), a deck on stilts with a helipad and the camp round it. While the attackers
## hold it, it is a forward spawn point (AttackerCommander.spawn_bases: its button on the RTS spawn
## row) and brings in INCOME supply a second on top of the commander's own. It can't be shot down:
## a defender Infiltrator Squad sabotages it (InfiltratorSquad, SABOTAGE_TIME with its leader within
## SABOTAGE_REACH of the deck), and the attackers lose control of it until they retake it: ground
## units within CAPTURE_REACH of the deck for CAPTURE_TIME (sooner the more of them there are), with
## no defender that close.
##
## The deck is solid down to the ground (baked into the navmesh): units walk round it.

signal sabotaged(base: AttackerBase)
signal retaken(base: AttackerBase)

const MODEL := "res://assets/structures/forward_helipad_base/forward_helipad_base.glb"
## Height the model is scaled to (m, to the mast tips): the deck then stands DECK_HEIGHT up on its
## stilts and spans SIZE (x along its length, z across).
const HEIGHT := 9.8
const DECK_HEIGHT := 2.85
const SIZE := Vector2(26.1, 20.2)
## Supply a second it brings in while the attackers hold it.
const INCOME := 1.5
## Retaking it: ground units within CAPTURE_REACH of the deck's edge, for CAPTURE_TIME; every unit
## past the first speeds it up by CAPTURE_BOOST, up to CAPTURE_CROWD of them. With nobody there it
## slips back at CAPTURE_DECAY times the rate.
const CAPTURE_REACH := 10.0
const CAPTURE_TIME := 15.0
const CAPTURE_BOOST := 0.25
const CAPTURE_CROWD := 4
const CAPTURE_DECAY := 0.5
## Sabotage: how close to the deck's edge the saboteur's leader stands (m), and how long it takes
## (s). Off it for SABOTAGE_GRACE, the work is lost.
const SABOTAGE_REACH := 4.0
const SABOTAGE_TIME := 45.0
const SABOTAGE_GRACE := 0.3
## Units it spawns appear this far out from the deck's long side facing the lane (m).
const SPAWN_OUT := 7.0
const HELD_COLOR := Color(0.75, 0.2, 0.15)
const LOST_COLOR := Color(0.55, 0.6, 0.65)
const RING_COLOR := Color(1.0, 0.8, 0.25, 0.85)
const SCAN_EVERY := 0.25

## "South Helipad"; `short_name` goes on the RTS spawn button ("S Pad") and `code` on the defender's
## roster ("S").
var display_name := "Forward Helipad"
var short_name := "Pad"
var code := ""
## The attack lane it is by ("south", "east", "west").
var side := ""
var team := GameConfig.TEAM_ATTACKER
## The attackers hold it: it spawns their units and brings in supply.
var controlled := true
## Retaking it: seconds of capture built up (CAPTURE_TIME: retaken), and whether a defender close by
## holds it up.
var capture := 0.0
var contested := false
## Where the units it spawns appear (on the ground between it and the lane).
var spawn_point := Vector3.ZERO
## The squad sabotaging it right now (null: nobody) and how far along it is (s).
var saboteur: Node = null
var sabotage := 0.0

var _since_work := 0.0
var _scan_cd := 0.0
var _attackers_near := 0
var _wisp_cd := 0.0
var _flag: MeshInstance3D
var _beacon: OmniLight3D
var _label: Label3D
var _ring: MeshInstance3D


## Names it after its side ("south").
func setup(p_side: String) -> void:
	side = p_side
	display_name = "%s Helipad" % side.capitalize()
	short_name = "%s Pad" % side.substr(0, 1).to_upper()
	code = side.substr(0, 1).to_upper()
	name = "Helipad_%s" % side


func _ready() -> void:
	add_to_group("attacker_bases")
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, DECK_HEIGHT, SIZE.y)
	cs.shape = box
	cs.position.y = DECK_HEIGHT * 0.5
	add_child(cs)
	add_child(Props.instance(MODEL, HEIGHT))
	_build_marks()
	_refresh()


## Flat distance from `p` to the deck's footprint (0 under it).
func edge_distance(p: Vector3) -> float:
	var l := global_transform.affine_inverse() * p
	return Vector2(maxf(absf(l.x) - SIZE.x * 0.5, 0.0), maxf(absf(l.z) - SIZE.y * 0.5, 0.0)).length()


## Spots `out` meters off the deck's edge all round it (the middle of each side and each corner),
## for a saboteur to walk up to.
func spots_around(out: float) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var hx := SIZE.x * 0.5 + out
	var hz := SIZE.y * 0.5 + out
	for l: Vector3 in [Vector3(hx, 0, 0), Vector3(-hx, 0, 0), Vector3(0, 0, hz), Vector3(0, 0, -hz),
			Vector3(hx * 0.8, 0, hz * 0.8), Vector3(-hx * 0.8, 0, hz * 0.8), Vector3(hx * 0.8, 0, -hz * 0.8), Vector3(-hx * 0.8, 0, -hz * 0.8)]:
		spots.append(global_transform * l)
	return spots


## A defender squad works on sabotaging it this physics frame (its leader within SABOTAGE_REACH).
## True the frame it is done: the attackers have lost it. One squad at a time; false while someone
## else is at it, or if the attackers don't hold it.
func work_sabotage(squad: Node, delta: float) -> bool:
	if not controlled or (saboteur != null and saboteur != squad and is_instance_valid(saboteur)):
		return false
	saboteur = squad
	_since_work = 0.0
	sabotage += delta
	if sabotage < SABOTAGE_TIME:
		return false
	_lose()
	return true


## Sabotage done, 0..1 (for the saboteur's panel).
func sabotage_fraction() -> float:
	return clampf(sabotage / SABOTAGE_TIME, 0.0, 1.0)


func capture_fraction() -> float:
	return clampf(capture / CAPTURE_TIME, 0.0, 1.0)


func _lose() -> void:
	controlled = false
	saboteur = null
	sabotage = 0.0
	capture = 0.0
	_refresh()
	sabotaged.emit(self)


func _retake() -> void:
	controlled = true
	capture = 0.0
	contested = false
	_refresh()
	retaken.emit(self)


func _physics_process(delta: float) -> void:
	if saboteur != null:
		_since_work += delta
		if _since_work > SABOTAGE_GRACE or not is_instance_valid(saboteur):
			saboteur = null
			sabotage = 0.0
	if controlled:
		return
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_EVERY
		_scan()
	if _attackers_near > 0 and not contested:
		capture += delta * (1.0 + CAPTURE_BOOST * (mini(_attackers_near, CAPTURE_CROWD) - 1))
		if capture >= CAPTURE_TIME:
			_retake()
			return
	elif _attackers_near == 0:
		capture = maxf(capture - delta * CAPTURE_DECAY, 0.0)
	_label.text = "%s\n%s" % [display_name.to_upper(), _status()]


## Who is round it: attacker ground units retaking it, and defenders holding them up.
func _scan() -> void:
	_attackers_near = 0
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if u.is_alive() and not (u.has_method("is_flying") and u.is_flying()) and edge_distance(u.global_position) <= CAPTURE_REACH:
			_attackers_near += 1
	contested = false
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if d.is_alive() and edge_distance(d.global_position) <= CAPTURE_REACH:
			contested = true
			break


func _status() -> String:
	if contested and _attackers_near > 0:
		return "CONTESTED"
	if capture > 0.0:
		return "RETAKING %d%%" % int(capture_fraction() * 100.0)
	return "SABOTAGED · RETAKE IT"


func _process(delta: float) -> void:
	if controlled:
		return
	# Smoke off the sabotaged camp.
	_wisp_cd -= delta
	if _wisp_cd <= 0.0:
		_wisp_cd = 0.35
		var l := Vector3(randf_range(-0.35, 0.35) * SIZE.x, DECK_HEIGHT + 0.5, randf_range(-0.3, 0.3) * SIZE.y)
		SmokeCloud.wisp(self, global_transform * l, 2.2)
	_beacon.light_energy = 0.4 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.004))


## The flag on its mast, the beacon, the name over it and the ring where units retake it.
func _build_marks() -> void:
	var corner := Vector3(SIZE.x * 0.5 - 1.0, DECK_HEIGHT, SIZE.y * 0.5 - 1.0)
	var pole := Mats.cylinder_mesh(0.1, 6.0, corner + Vector3(0, 3.0, 0), Mats.flat(Color(0.2, 0.2, 0.22), 0.6, 0.5), 6)
	add_child(pole)
	_flag = Mats.box_mesh(Vector3(2.0, 1.2, 0.05), corner + Vector3(-1.0, 5.3, 0), Mats.flat(HELD_COLOR))
	add_child(_flag)
	_beacon = OmniLight3D.new()
	_beacon.omni_range = 9.0
	_beacon.position = corner + Vector3(0, 6.2, 0)
	add_child(_beacon)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 26
	_label.outline_size = 8
	_label.position = Vector3(0, HEIGHT + 2.0, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	_dashed_outline(im, CAPTURE_REACH, 0.2)
	im.surface_end()
	_ring = MeshInstance3D.new()
	_ring.mesh = im
	_ring.material_override = Mats.unshaded(RING_COLOR)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## The deck's outline pushed `out` meters out (round corners), dashed, `y` over the ground.
func _dashed_outline(im: ImmediateMesh, out: float, y: float) -> void:
	var hx := SIZE.x * 0.5
	var hz := SIZE.y * 0.5
	var pts: Array[Vector3] = []
	var corners := [[Vector2(hx, hz), 0.0], [Vector2(-hx, hz), PI * 0.5], [Vector2(-hx, -hz), PI], [Vector2(hx, -hz), PI * 1.5]]
	for c in corners:
		var at: Vector2 = c[0]
		for k in 7:
			var a: float = c[1] + PI * 0.5 * k / 6.0
			pts.append(Vector3(at.x + cos(a) * out, y, at.y + sin(a) * out))
	pts.append(pts[0])
	var dash := 1.6
	var on := true
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var steps := maxi(int(a.distance_to(b) / dash), 1)
		for k in steps:
			if on:
				im.surface_add_vertex(a.lerp(b, float(k) / steps))
				im.surface_add_vertex(a.lerp(b, float(k + 1) / steps))
			on = not on


## Colours and labels for who holds it.
func _refresh() -> void:
	var color := HELD_COLOR if controlled else LOST_COLOR
	_flag.material_override = Mats.flat(color)
	_beacon.light_color = color
	_beacon.light_energy = 1.2 if controlled else 0.6
	_ring.visible = not controlled
	_label.modulate = Color(1.0, 0.75, 0.7) if controlled else Color(0.85, 0.9, 1.0)
	_label.text = display_name.to_upper() if controlled else "%s\n%s" % [display_name.to_upper(), _status()]
