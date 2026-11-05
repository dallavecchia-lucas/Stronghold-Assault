class_name TowPlatform
extends Node3D
## The pontoon raft every hippo and elephant carries (AttackerUnit can_carry), the riders' way across the Jungle
## Keep's water: a deck on six float drums (assets_src/structures/tow_platform, a Meshy "industrial amphibious"
## platform, cut by tools/gltf/split_raft.py into the pieces it folds and comes apart in), LENGTH long.
##
## Packed, it rides folded up on its carrier's back (UnitTypes pack): its three deck sections folded over one
## another, their frames folded flat, the railings laid down and the floats empty. Riders on their way to it have it
## put down (deploy(), every frame they come): it is tipped off over the carrier's rump onto the ground behind it,
## the deck sections swing open, the frames unfold, the railings come up and the floats blow up, all in DEPLOY_TIME.
## Then the riders climb on.
##
## Out, it trails the carrier on a tow line TOW behind its hitch (UnitTypes tows), like a trailer: its front is
## always TOW from the hitch, and it swings round to point at it, so it trails the carrier's way round corners. On
## land it slides along on its floats over the ground under it (over a bridge, along its deck); in the water it
## floats, the drums DRAFT deep, rocking a little.
##
## Once it is ashore and empty with nobody on the way to it (the crossing done, its riders off), the carrier has it
## come apart (spent(), break_up()): the floats go flat, the deck falls apart into its sections onto the ground, the
## floats beside them, and the lot fades away, in BREAK_TIME. By then the carrier has a fresh one packed on its back.
##
## On its deck: two animals (SEATS, one ahead of the other), or a Combat Rhino or a giraffe on its own (UnitTypes
## ride_alone, ALONE_SEAT): those only board an empty raft, and nobody joins one they are on (fits()). Its riders ride
## where it goes; it has no collision of its own (they do: they can be shot).

enum State { PACKED, DEPLOYING, OUT, BROKEN }

const MODEL := "res://assets/structures/tow_platform/tow_platform.glb"
const LENGTH := 6.0
## The deck's top over the drums' bottoms, and how deep the drums sit in the water.
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

## The pieces (split_raft.py) are in the model's frame: x along the raft (+x its front: the model is turned a
## quarter round to lie along the tow), y up from the drums' bottoms. The deck is cut across at x = +-CUT into its
## rear, middle and front sections (Deck_R/M/F, what stands on each: Top_R/M/F); its plate's top is DECK_TOP high,
## its frame reaches down to FRAME_BOTTOM; the floats are Float_<section><L|R>.
const CUT := 0.89
const DECK_TOP := 0.94
const FRAME_BOTTOM := 0.33
## Packed: the frames folded up to PACK_DEPTH of their depth, what stands on the deck laid down to GEAR_FLAT of its
## height, the floats empty (FLAT of their size each way, about the middle of their tops: tucked up into the frame);
## the front section folded back over the middle one (about a hinge HINGE_F high at its front edge), the rear one
## over both (HINGE_R high at its rear edge). The bundle's bottom is PACK_BOTTOM over the model's origin.
const PACK_DEPTH := 0.25
const GEAR_FLAT := 0.08
const FLAT := Vector3(0.9, 0.12, 0.6)
const HINGE_F := 1.0
const HINGE_R := 1.11
const PACK_BOTTOM := 0.79
## Put down: seconds it takes, and when each part of it happens ([start, end] s into it): tipped off the back
## onto the ground behind (TOSS, up ARC m on the way), the rear section swung open (R_OPEN), then the front one
## (F_OPEN), the frames unfolding (FRAMES), the railings coming up (GEAR_UP) and the floats blowing up (INFLATE).
const DEPLOY_TIME := 1.25
const TOSS := Vector2(0.0, 0.45)
const ARC := 1.2
const R_OPEN := Vector2(0.35, 0.7)
const F_OPEN := Vector2(0.55, 0.9)
const FRAMES := Vector2(0.55, 0.95)
const GEAR_UP := Vector2(0.8, 1.0)
const INFLATE := Vector2(0.85, 1.25)
## Coming apart: seconds it takes, the floats going flat (DEFLATE), the deck falling apart (APART: its sections
## DRIFT m apart, the floats FLOAT_OUT m out to the sides, all settling onto the ground) and the pieces fading away
## (FADE).
const BREAK_TIME := 2.6
const DEFLATE := Vector2(0.0, 0.45)
const APART := Vector2(0.12, 0.6)
const FADE := Vector2(1.8, 2.6)
const DRIFT := 0.45
const FLOAT_OUT := 0.45
## Out, ashore and empty, it comes apart AFTER_RIDE s after its riders got off, or IDLE s after the last one on the
## way to it stopped coming if nobody rode it.
const AFTER_RIDE := 0.7
const IDLE := 2.5
## A fresh pack shows on the carrier's back growing to its size over PACK_IN s.
const PACK_IN := 0.35

## Every raft there is (for the bumps).
static var all: Array[TowPlatform] = []

var carrier: AttackerUnit
## Out on the water (its drums afloat).
var afloat := false
var state := State.PACKED
## A fresh pack (the last one came apart): seconds before it shows on the carrier's back.
var hidden_for := 0.0
## The model (turned to lie along the tow), its pieces by name, and the middle of each float's top (model frame).
var _raft: Node3D
var _pieces := {}
var _float_tops := {}
var _line: MeshInstance3D
var _y := 0.0
var _t := 0.0
var _placed := false
## Seconds into being put down or coming apart; how far a fresh pack has grown in (0-1).
var _phase := 0.0
var _pop := 1.0
## Out: seconds it has been ashore and empty with nobody on the way to it (deploy() starts it over), and whether
## anyone has ridden it.
var _empty := 0.0
var _rode := false


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
	set_process(false)  # only while it comes apart (the carrier moves it otherwise: follow())
	_raft = Node3D.new()
	var m := (load(MODEL) as PackedScene).instantiate() as Node3D
	_raft.add_child(m)
	add_child(_raft)
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var piece := String(mi.name)
		_pieces[piece] = mi
		if piece.begins_with("Float"):
			var box := mi.get_aabb()
			_float_tops[piece] = mi.transform * (box.position + Vector3(box.size.x * 0.5, box.size.y, box.size.z * 0.5))
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
	_line.visible = false
	add_child(_line)
	_pose(1.0, 1.0, PACK_DEPTH, GEAR_FLAT, 0.0)
	if hidden_for > 0.0:
		_raft.visible = false
		_pop = 0.0
	follow(0.0)


func _exit_tree() -> void:
	all.erase(self)


## Out behind the carrier and ready to be boarded.
func is_ready() -> bool:
	return state == State.OUT


## Packed on the carrier's back (or not shown there yet).
func is_packed() -> bool:
	return state == State.PACKED


## A rider is on its way to it: put down behind the carrier if it is packed (on land: not while it swims), and kept
## out meanwhile.
func deploy() -> void:
	_empty = 0.0
	if state != State.PACKED or carrier == null or not is_instance_valid(carrier) or carrier.in_water() or carrier.is_swimming():
		return
	state = State.DEPLOYING
	_phase = 0.0
	# A spare, if the last one has only just come apart.
	hidden_for = 0.0
	_pop = 1.0
	_raft.visible = true


## Out, ashore and empty, and nobody wants it any more (its riders got off, or nobody came): time it came apart.
func spent() -> bool:
	return state == State.OUT and not afloat and _empty > (AFTER_RIDE if _rode else IDLE)


## The carrier's hitch (world): on its rear (UnitTypes tows).
func hitch() -> Vector3:
	return carrier.global_transform * (carrier.stats.tows as Vector3)


## Trails the carrier: its front TOW from the hitch, pointing at it, on the ground or afloat; packed, it rides on the
## carrier's back. Called by the carrier every frame once it has moved (before it places the riders).
func follow(delta: float) -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	_t += delta
	var out := state == State.OUT or state == State.DEPLOYING
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
	if out and _placed and RiverCrossing.active() and _floor(centre) < JungleLayout.WATER_Y - DRAFT:
		dir = _bumped(h, dir)
		centre = h - dir * (TOW + LENGTH * 0.5)
	var ground := _floor(centre)
	afloat = out and RiverCrossing.active() and ground < JungleLayout.WATER_Y - DRAFT
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
	match state:
		State.PACKED:
			_ride_packed(delta)
		State.DEPLOYING:
			_deploying(delta)
		State.OUT:
			if afloat or not carrier.riders.is_empty():
				_empty = 0.0
				_rode = _rode or not carrier.riders.is_empty()
			else:
				_empty += delta
	# The tow line, from the hitch to the front of the deck, once it is down behind the carrier.
	_line.visible = state == State.OUT or (state == State.DEPLOYING and _phase >= TOSS.y)
	var front := global_transform * Vector3(0, DECK * 0.8, -LENGTH * 0.5)
	var span := front - h
	if _line.visible and span.length() > 0.05:
		_line.global_transform = Transform3D(Basis.looking_at(span.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5),
				h + span * 0.5)
		_line.scale = Vector3(1.0, span.length(), 1.0)


## Packed on the carrier's back; a fresh pack shows once its wait is over, growing to its size.
func _ride_packed(delta: float) -> void:
	if hidden_for > 0.0:
		hidden_for -= delta
		if hidden_for > 0.0:
			return
		_raft.visible = true
	_pop = minf(_pop + delta / PACK_IN, 1.0)
	_raft.global_transform = _pack_transform(ease(_pop, 0.4))


## Being put down: off the carrier's back onto the ground behind it (where it trails it from), then it opens out.
func _deploying(delta: float) -> void:
	_phase += delta
	var s := smoothstep(TOSS.x, TOSS.y, _phase)
	var xf := _pack_transform(1.0).interpolate_with(global_transform * _laid(), s)
	xf.origin.y += sin(PI * s) * ARC
	_raft.global_transform = xf
	var full := clampf((_phase - INFLATE.x) / (INFLATE.y - INFLATE.x), 0.0, 1.0)
	_pose(1.0 - smoothstep(R_OPEN.x, R_OPEN.y, _phase), 1.0 - smoothstep(F_OPEN.x, F_OPEN.y, _phase),
			lerpf(PACK_DEPTH, 1.0, smoothstep(FRAMES.x, FRAMES.y, _phase)),
			lerpf(GEAR_FLAT, 1.0, smoothstep(GEAR_UP.x, GEAR_UP.y, _phase)), _back_out(full))
	if _phase >= DEPLOY_TIME:
		state = State.OUT
		_empty = 0.0
		_raft.transform = _laid()
		_pose(0.0, 0.0, 1.0, 1.0, 1.0)


## The model as it lies out behind the carrier (in its own frame): turned to lie along the tow.
static func _laid() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)


## Where the model rides packed (world): on the carrier's back, as UnitTypes pack has it ([the bundle's bottom
## middle in the carrier's frame, how far it is tipped up at the front (rad), its size]), `grown` of that size. It
## rides the body (AttackerUnit.model_root: it rolls over with it when it dies).
func _pack_transform(grown: float) -> Transform3D:
	var pk: Array = carrier.stats.pack
	var b := Basis(Vector3.RIGHT, pk[1]) * _laid().basis * Basis.from_scale(Vector3.ONE * (pk[2] * maxf(grown, 0.01)))
	return carrier.model_root().global_transform * Transform3D(b, (pk[0] as Vector3) - b * Vector3(0, PACK_BOTTOM, 0))


## Poses the pieces: the rear and front sections folded over (1) or open (0), the frames' depth (1 unfolded), what
## stands on the deck (1 up), the floats (1 full, 0 flat, a little over 1 as they pop up) and how far it has come
## apart (0-1).
func _pose(fold_r: float, fold_f: float, depth: float, gear: float, full: float, apart := 0.0) -> void:
	var folded := _about(Vector3(0, DECK_TOP, 0), Basis.from_scale(Vector3(1.0, depth, 1.0)))
	var down := Vector3(0, -FRAME_BOTTOM * apart, 0)
	# Apart, each section settles onto the ground and tips a little; the front and rear ones drift off its ends.
	var sections := {
		"M": Transform3D(Basis(Vector3.RIGHT, 0.04 * apart), down) * folded,
		"F": Transform3D(Basis.IDENTITY, down + Vector3(DRIFT * apart, 0, 0)) * _about(Vector3(1.95, 0.5, 0), Basis(Vector3.BACK, -0.08 * apart))
				* _about(Vector3(CUT, HINGE_F, 0), Basis(Vector3.BACK, PI * fold_f)) * folded,
		"R": Transform3D(Basis.IDENTITY, down - Vector3(DRIFT * apart, 0, 0)) * _about(Vector3(-1.95, 0.5, 0), Basis(Vector3.BACK, 0.08 * apart))
				* _about(Vector3(-CUT, HINGE_R, 0), Basis(Vector3.BACK, -PI * fold_r)) * folded,
	}
	var laid := _about(Vector3(0, DECK_TOP, 0), Basis.from_scale(Vector3(1.0, gear, 1.0)))
	for s in sections:
		_set_piece("Deck_" + s, sections[s])
		_set_piece("Top_" + s, sections[s] * laid)
	var size := Vector3(lerpf(FLAT.x, 1.0, full), lerpf(FLAT.y, 1.0, full), lerpf(FLAT.z, 1.0, full))
	for piece in _float_tops:
		var top: Vector3 = _float_tops[piece]
		# Apart, the flat floats drop to the ground out beside the deck.
		var off := Vector3(0, -(top.y - FRAME_BOTTOM) * 0.75 * apart, signf(top.z) * FLOAT_OUT * apart)
		_set_piece(piece, Transform3D(Basis.IDENTITY, off) * sections[piece.substr(6, 1)] * _about(top, Basis.from_scale(size)))


func _set_piece(piece: String, xf: Transform3D) -> void:
	var mi: MeshInstance3D = _pieces.get(piece)
	if mi:
		mi.transform = xf


## `b` about `pivot` (the model's frame).
static func _about(pivot: Vector3, b: Basis) -> Transform3D:
	return Transform3D(b, pivot - b * pivot)


## Ease out with a little overshoot (the floats pop up full).
static func _back_out(x: float) -> float:
	var k := x - 1.0
	return 1.0 + 2.70158 * k * k * k + 1.70158 * k * k


## Comes apart where it is: the carrier's no more (it has a fresh one packed by now). Frees itself once it has faded.
func break_up() -> void:
	if state == State.BROKEN:
		return
	state = State.BROKEN
	_phase = 0.0
	afloat = false
	_line.visible = false
	if carrier and is_instance_valid(carrier) and carrier.get_parent():
		reparent(carrier.get_parent())
	carrier = null
	all.erase(self)
	set_process(true)


func _process(delta: float) -> void:
	if state != State.BROKEN:
		return
	_phase += delta
	var gone := clampf((_phase - DEFLATE.x) / (DEFLATE.y - DEFLATE.x), 0.0, 1.0)
	var apart := smoothstep(APART.x, APART.y, _phase)
	# The floats sag flat with a last wobble; what stands on the deck slumps as it falls apart.
	var full := (1.0 - gone) * (1.0 - gone) * (1.0 + 0.12 * sin(gone * 14.0))
	_pose(0.0, 0.0, 1.0, lerpf(1.0, 0.35, apart), full, apart)
	var fade := smoothstep(FADE.x, FADE.y, _phase)
	if fade > 0.0:
		for mi: MeshInstance3D in _pieces.values():
			mi.transparency = fade
		_raft.position.y = -0.25 * fade
	if _phase >= BREAK_TIME:
		queue_free()


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


## Its carrier is dead. Packed, it goes down with the body on its back. Out on the water it goes under (with the
## riders on it); out on land it comes apart.
func abandon(wet: bool) -> void:
	_line.visible = false
	if state == State.PACKED or (state == State.DEPLOYING and _phase < TOSS.y):
		if _raft.visible and carrier and is_instance_valid(carrier):
			_raft.reparent(carrier.model_root())
		queue_free()
		return
	if not wet:
		break_up()
		return
	# Off the carrier (it is freed once it has sunk out of sight), where it is.
	if carrier and is_instance_valid(carrier) and carrier.get_parent():
		reparent(carrier.get_parent())
	carrier = null
	afloat = false
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 4.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
