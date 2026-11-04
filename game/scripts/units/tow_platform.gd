class_name TowPlatform
extends Node3D
## The pontoon raft every hippo and elephant tows behind it (AttackerUnit can_carry), the riders' way across the
## Jungle Keep's water: a deck on six float drums (assets_src/structures/tow_platform, a Meshy "industrial
## amphibious" platform), LENGTH long, on a tow line TOW behind its carrier's hitch (UnitTypes tows).
##
## It follows like a trailer: its front is always TOW from the hitch, and it swings round to point at it, so it
## trails the carrier's way round corners. On land it slides along on its floats over the ground under it (over a
## bridge, along its deck); in the water it floats, the drums DRAFT deep, rocking a little.
##
## On its deck: two animals (SEATS, one ahead of the other), or a Combat Rhino or a giraffe on its own (UnitTypes
## ride_alone, ALONE_SEAT): those only board an empty raft, and nobody joins one they are on (fits()). Its riders ride where it
## goes; it has no collision of its own (they do: they can be shot).

const MODEL := "res://assets/structures/tow_platform/tow_platform.glb"
## The model's height (to the railings' top) at LENGTH long (it is 0.954 long by 0.248 high as modelled).
const LENGTH := 6.0
const MODEL_HEIGHT := LENGTH * 0.2476 / 0.9542
## The deck's top over the drums' bottoms (m), and how deep the drums sit in the water.
const DECK := 0.95
const DRAFT := 0.4
## Its half width (to the drums' outsides).
const HALF_WIDTH := LENGTH * 0.2678 / 0.9542
## Where riders stand on the deck (its frame, the front -Z toward the carrier): two, one ahead of the other, or a
## rhino or a giraffe alone in the middle.
const SEATS := [Vector3(0, DECK, -1.45), Vector3(0, DECK, 1.45)]
const ALONE_SEAT := Vector3(0, DECK, 0.15)
## The tow line from the carrier's hitch to the raft's front (m).
const TOW := 1.6
## Afloat, two rafts that come closer than this (m, deck edge to deck edge) bump: each swings away about its hitch.
const BUMP := 0.6

## Every raft there is (for the bumps).
static var all: Array[TowPlatform] = []

var carrier: AttackerUnit
## Out on the water (its drums afloat).
var afloat := false
var _model: Node3D
var _line: MeshInstance3D
var _y := 0.0
var _t := 0.0
var _placed := false


## True if `u` may get onto a raft with `aboard` on it (or on their way to it): never more than two, and a rhino or a
## giraffe only onto an empty one, and nobody onto one with a rhino or a giraffe.
static func fits(aboard: Array, u) -> bool:
	if aboard.any(func(o): return o != u and o.rides_alone()):
		return false
	var others := aboard.filter(func(o): return o != u)
	if u.rides_alone():
		return others.is_empty()
	return others.size() < SEATS.size()


func _ready() -> void:
	top_level = true
	name = "TowPlatform"
	all.append(self)
	_model = Props.instance(MODEL, MODEL_HEIGHT)
	_model.rotation.y = PI * 0.5  # its length (the model's x) along the tow
	add_child(_model)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_line = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.045
	c.bottom_radius = 0.045
	c.height = 1.0
	c.radial_segments = 6
	c.rings = 1
	_line.mesh = c
	_line.material_override = Mats.flat(Color(0.12, 0.11, 0.1), 0.4, 0.6)
	_line.top_level = true
	add_child(_line)
	follow(0.0)


func _exit_tree() -> void:
	all.erase(self)


## The carrier's hitch (world): on its rear (UnitTypes tows).
func hitch() -> Vector3:
	return carrier.global_transform * (carrier.stats.tows as Vector3)


## Trails the carrier: its front TOW from the hitch, pointing at it, on the ground or afloat. Called by the carrier
## every frame once it has moved (before it places the riders).
func follow(delta: float) -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	_t += delta
	var h := hitch()
	var to := h - global_position
	to.y = 0.0
	# Far off its tow (the carrier was put down somewhere else): behind it again.
	if to.length() > TOW + LENGTH + 4.0:
		_placed = false
	var dir := to.normalized() if _placed and to.length() > 0.05 else -carrier.global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var centre := h - dir * (TOW + LENGTH * 0.5)
	if _placed and RiverCrossing.active() and _floor(centre) < JungleLayout.WATER_Y - DRAFT:
		dir = _bumped(h, dir)
		centre = h - dir * (TOW + LENGTH * 0.5)
	var ground := _floor(centre)
	afloat = RiverCrossing.active() and ground < JungleLayout.WATER_Y - DRAFT
	var want := JungleLayout.WATER_Y - DRAFT + sin(_t * 1.3) * 0.05 if afloat else ground
	_y = want if not _placed else lerpf(_y, want, minf(delta * 4.0, 1.0))
	_placed = true
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := 0.0
	var roll := 0.0
	if afloat:
		pitch = sin(_t * 1.1) * 0.025
		roll = sin(_t * 0.8 + 1.0) * 0.03
	else:
		# Along the ground's slope under it.
		var fwd := Vector3(dir.x, 0.0, dir.z)
		var side := fwd.cross(Vector3.UP)
		var hf := _floor(centre + fwd * LENGTH * 0.4)
		var hb := _floor(centre - fwd * LENGTH * 0.4)
		var hl := _floor(centre - side * HALF_WIDTH)
		var hr := _floor(centre + side * HALF_WIDTH)
		pitch = atan2(hf - hb, LENGTH * 0.8)
		roll = atan2(hl - hr, HALF_WIDTH * 2.0)
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll),
			Vector3(centre.x, _y, centre.z))
	# The tow line, from the hitch to the front of the deck.
	var front := global_transform * Vector3(0, DECK * 0.8, -LENGTH * 0.5)
	var span := front - h
	if span.length() > 0.05:
		_line.global_transform = Transform3D(Basis.looking_at(span.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5),
				h + span * 0.5)
		_line.scale = Vector3(1.0, span.length(), 1.0)


## What it slides along at `p`: a standing bridge's deck, or the ground.
static func _floor(p: Vector3) -> float:
	var deck := FoldingBridge.deck_at(p) if RiverCrossing.active() else NAN
	return deck if not is_nan(deck) else LevelBuilder.ground_height(p)


## Its way back from the hitch `h` (`dir` points at it), swung away from any other raft afloat it would come
## closer to than BUMP.
func _bumped(h: Vector3, dir: Vector3) -> Vector3:
	var reach := TOW + LENGTH * 0.5
	for o in all:
		if o == self or not o.afloat or o.global_position.distance_squared_to(h) > 400.0:
			continue
		var c := h - dir * reach
		var half := o.global_basis.z * (LENGTH * 0.5)
		var pair := AttackerUnit._closest(Vector2(c.x + dir.x * LENGTH * 0.5, c.z + dir.z * LENGTH * 0.5),
				Vector2(c.x - dir.x * LENGTH * 0.5, c.z - dir.z * LENGTH * 0.5),
				Vector2(o.global_position.x + half.x, o.global_position.z + half.z),
				Vector2(o.global_position.x - half.x, o.global_position.z - half.z))
		var off: Vector2 = pair[0] - pair[1]
		var gap := off.length() - HALF_WIDTH * 2.0
		if gap >= BUMP:
			continue
		# Swing its tail away (the centre moves off along the side of `dir` the other raft isn't on).
		var side := Vector3(dir.z, 0.0, -dir.x)
		var away := signf(Vector3(off.x, 0.0, off.y).dot(side))
		if away == 0.0:
			away = 1.0 if get_instance_id() > o.get_instance_id() else -1.0
		dir = (dir - side * away * clampf((BUMP - gap) / reach, 0.0, 0.5)).normalized()
	return dir


## Where rider `k` of the ones on it stands (world), facing ahead; a rhino or a giraffe in the middle.
func seat_transform(k: int, alone: bool) -> Transform3D:
	var at: Vector3 = ALONE_SEAT if alone else SEATS[clampi(k, 0, SEATS.size() - 1)]
	return global_transform * Transform3D(Basis.IDENTITY, at)


## Where a rider gets down: off its side, the way it is from the middle.
func drop_spot(k: int, r: Node3D) -> Vector3:
	var side := -1.0 if k % 2 == 0 else 1.0
	return global_transform * Vector3(side * (HALF_WIDTH + r.stats.radius + 0.6), 0.0, SEATS[clampi(k, 0, 1)].z)


## Its carrier is dead: out on the water it goes under, on land it is left behind and fades.
func abandon(wet: bool) -> void:
	# Off the carrier (it is freed once it has sunk out of sight), where it is.
	if carrier and is_instance_valid(carrier) and carrier.get_parent():
		reparent(carrier.get_parent())
	carrier = null
	var tw := create_tween()
	if wet:
		tw.tween_property(self, "position:y", position.y - 4.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(4.0)
		tw.tween_property(self, "position:y", position.y - 2.0, 2.0)
	tw.tween_callback(queue_free)
	_line.visible = false
