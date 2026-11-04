class_name FoldingBridge
extends Node3D
## A folding bridge the attackers drop across one of the Jungle Keep's rivers (AttackerCommander "bridge": 30 of
## them a match). The model (tools/gltf/fold_bridge.py) is a deck with railings and ramp flaps at both ends, cut at
## the hydraulic joints under it into the middle span and two end spans.
##
## Ordered (plan() picks the spot: across the river nearest the point, the deck's middle over the middle of the
## water, its ends on dry land both sides), it is airdropped: it comes down out of the sky folded (a Z-fold, the
## left span upside down on the deck, the right one under it), its four thrusters light BRAKE_AT m up and slow it to
## a hover HOVER m over its spot, it unfolds (the left span swinging up and over, the right one down and round), and
## it comes down the rest of the way onto the banks, the flaps' tips on the ground. The attacking player sees where
## it will land the whole way down (a faint cyan copy of it there).
##
## Down, it is a bridge (STANDING): solid (a body under the navigation region, baked into the navmesh, so everyone's
## paths cross it), the wall along the water's edge open under it (JungleTerrain.cut_water_edge). Anyone can cross:
## the defenders too. A defender on it sets off its alarm (red lights flashing along both rails, a siren) for as long
## as one is on it: the attacking player is warned (alarm signal). It is tough: MAX_HP, every hit ARMOR less (never
## below MIN_SHARE of it), so small arms barely scratch it and it takes shells and rockets to bring it down; no
## alarm goes off while it is shot at. Brought down it breaks at its joints and sinks: everyone on it falls in, and
## those that can't swim drown.

signal landed(bridge: FoldingBridge)
signal fallen(bridge: FoldingBridge)
signal alarm(bridge: FoldingBridge, on: bool)

enum State { DROPPING, BRAKING, UNFOLDING, LANDING, STANDING, FALLEN }

const MODEL := "res://assets/structures/folding_bridge/folding_bridge.glb"
## The model's size as tools/gltf/fold_bridge.py makes it (m): REF_LENGTH long, the deck's top at 0, its sides at
## +-HALF_WIDTH, the trusses TRUSS deep under it, the railings RAIL_H high; the flaps start FLAP_X out from the middle
## and their tips are TIP_DROP under the deck's top. The joints (hinges) are HINGE_X out; the left span folds over a
## hinge HINGE_TOP up (over the railings), the right one under a hinge HINGE_BOTTOM down. A bridge is stretched along
## its length to fit its river (plan()).
const REF_LENGTH := 72.0
const HALF_WIDTH := 5.45
const TRUSS := 3.2
const RAIL_H := 1.5
const FLAP_X := 27.0
const TIP_DROP := 0.92
const HINGE_X := 15.05
const HINGE_TOP := 1.65
const HINGE_BOTTOM := -3.3
## Curbs CURB_H high down the flaps' sides, ending CURB_SHORT short of their tips (m).
const CURB_H := 0.6
const CURB_SHORT := 1.5
## Spans: the water plus OVERHANG m either side, within MIN_LENGTH..MAX_LENGTH.
const OVERHANG := 10.5
const MIN_LENGTH := 50.0
const MAX_LENGTH := 84.0
## The cursor this close to a river (past its banks, m) points at it.
const REACH := 40.0
## Its ends may differ this much in height (rad of slope).
const MAX_PITCH := deg_to_rad(6.0)
## Bridges keep this far apart (m, between their decks' middle lines).
const SPACING := HALF_WIDTH * 2.0 + 5.0
## Toughness.
const MAX_HP := 6000.0
const ARMOR := 12.0
const MIN_SHARE := 0.1
## The drop: it starts DROP_FROM m over its spot falling at FALL_SPEED m/s, its thrusters light BRAKE_AT m up and
## brake it to a hover at HOVER m (higher than a span is long: the right one swings down under it), it unfolds in
## UNFOLD_TIME s and comes down in DESCEND_TIME s. It turns into line on the way down from SPIN rad off.
const DROP_FROM := 200.0
const FALL_SPEED := 52.0
const BRAKE_AT := 78.0
const HOVER := 30.0
const UNFOLD_TIME := 3.2
const DESCEND_TIME := 3.6
const SPIN := 0.7
## Thruster pods: along the deck's sides, POD_X out from the middle (at REF_LENGTH).
const POD_X := 10.5
const FLAME_LEN := 7.0
## Alarm: lamps along both railings, flashing ALARM_RATE times a second, the two sides by turns.
const ALARM_RATE := 2.5
const LAMP_X := [-31.0, -22.0, -9.0, 0.0, 9.0, 22.0, 31.0]
const CHECK_EVERY := 0.2
const HP_SHOW := 6.0
const GHOST_COLOR := Color(0.25, 0.95, 1.0, 0.35)

## Every bridge ordered (dropping or standing) and not yet fallen.
static var all: Array[FoldingBridge] = []
static var _parts := {}
static var _siren_wav: AudioStreamWAV
static var _roar_wav: AudioStreamWAV

var team := GameConfig.TEAM_ATTACKER
var hp := MAX_HP
var bridge_id := 0
var length := REF_LENGTH
var state := State.DROPPING
var alarm_on := false
## The defenders on it now (alarm_on while there are any).
var intruders: Array = []
var level: LevelBuilder
## How long it has been since it was ordered (s), and since it landed.
var age := 0.0

var _model := {}
var _rig: Node3D
var _ghost := {}
var _ghost_mat: StandardMaterial3D
var _pods: Array[Node3D] = []
var _flames: Array[MeshInstance3D] = []
var _exhaust: Array[CPUParticles3D] = []
var _pod_lights: Array[OmniLight3D] = []
var _spray: CPUParticles3D
var _lamp_mats: Array[StandardMaterial3D] = []
var _halos: Array[Sprite3D] = []
var _alarm_lights: Array[OmniLight3D] = []
var _body: StaticBody3D
var _area: Area3D
var _siren: AudioStreamPlayer3D
var _roar: AudioStreamPlayer3D
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _hp_shown := 0.0
var _alt := DROP_FROM
var _vel := -FALL_SPEED
var _t := 0.0
var _fold := 1.0
var _thrust := 0.0
var _check_cd := 0.0
var _flash_t := 0.0


# ---------------------------------------------------------------- placement

## Where a bridge ordered at `at` goes: across the river nearest it, over the middle of the water there, square to
## the river. {ok, reason, xform (the deck's top in the middle, x along the bridge), length, river, tips}. When it
## can't go there ok is false and reason says why; xform is still set when there is a river close enough to show it.
static func plan(at: Vector3, ignore: FoldingBridge = null) -> Dictionary:
	var out := {"ok": false, "reason": "", "length": REF_LENGTH}
	if not RiverCrossing.active():
		out.reason = "No river on this map"
		return out
	var river := RiverCrossing.nearest_river(Vector2(at.x, at.z))
	if river.is_empty() or river.dist > river.width * 0.5 + REACH:
		out.reason = "Point at a river"
		return out
	out.river = river.name
	var d: Vector2 = river.dir
	var n := Vector2(-d.y, d.x)
	var c: Vector2 = river.point
	var span := RiverCrossing.water_span(c, n, MAX_LENGTH * 0.5)
	var mid := c
	var water := MAX_LENGTH
	if not span.is_empty():
		mid = (span[0] + span[1]) * 0.5
		water = span[0].distance_to(span[1])
	var length := clampf(water + OVERHANG * 2.0, MIN_LENGTH, MAX_LENGTH)
	out.length = length
	var ta := mid - n * length * 0.5
	var tb := mid + n * length * 0.5
	# Each end rests on the lowest ground across its width: nowhere does its tip stand proud of the ground (a lip
	# to climb), where the bank slopes across the bridge the flap just goes into the ground.
	var ha := _low_ground(ta, d)
	var hb := _low_ground(tb, d)
	var pitch := atan2(hb - ha, length)
	var top := (ha + hb) * 0.5 + TIP_DROP * cos(pitch)
	var basis := Basis(Vector3.UP, atan2(-n.y, n.x)) * Basis(Vector3.BACK, pitch)
	out.xform = Transform3D(basis, Vector3(mid.x, top, mid.y))
	out.tips = [Vector3(ta.x, ha, ta.y), Vector3(tb.x, hb, tb.y)]
	if span.is_empty() or water + OVERHANG > MAX_LENGTH:
		out.reason = "Too wide to bridge here"
		return out
	if minf(ha, hb) < JungleLayout.WATER_Y + 0.8:
		out.reason = "No dry land for its ends"
		return out
	if absf(pitch) > MAX_PITCH:
		out.reason = "The banks are too uneven"
		return out
	# The deck clears the ground all along it (the banks may rise in the way); the flaps may go into the bank a little.
	var xf: Transform3D = out.xform
	var steps := int(length / 2.0)
	var flap := FLAP_X * length / REF_LENGTH
	for s in range(1, steps):
		var x := -length * 0.5 + length * s / steps
		var y := _deck_y(x, length)
		for z in [-HALF_WIDTH + 0.6, 0.0, HALF_WIDTH - 0.6]:
			var p := xf * Vector3(x, y, z)
			if RiverCrossing.ground(Vector2(p.x, p.z)) > p.y + (1.2 if absf(x) > flap else 0.15):
				out.reason = "Ground in the way"
				return out
	for b in all:
		if b == ignore or b.state == State.FALLEN:
			continue
		var a0 := xf * Vector3(-length * 0.5, 0, 0)
		var a1 := xf * Vector3(length * 0.5, 0, 0)
		var b0 := b.global_transform * Vector3(-b.length * 0.5, 0, 0)
		var b1 := b.global_transform * Vector3(b.length * 0.5, 0, 0)
		if _seg_dist(Vector2(a0.x, a0.z), Vector2(a1.x, a1.z), Vector2(b0.x, b0.z), Vector2(b1.x, b1.z)) < SPACING:
			out.reason = "Another bridge is in the way"
			return out
	out.ok = true
	return out


## The lowest ground across a bridge's end at `tip`, `across` (unit) along its width.
static func _low_ground(tip: Vector2, across: Vector2) -> float:
	var low := INF
	for k in 7:
		low = minf(low, RiverCrossing.ground(tip + across * lerpf(-HALF_WIDTH, HALF_WIDTH, k / 6.0)))
	return low


## The deck's top at `x` along a bridge `length` long (0 over the middle span, sloping down the flaps).
static func _deck_y(x: float, length: float) -> float:
	var k := length / REF_LENGTH
	var ax := absf(x)
	if ax <= FLAP_X * k:
		return 0.0
	return -TIP_DROP * clampf((ax - FLAP_X * k) / (length * 0.5 - FLAP_X * k), 0.0, 1.0)


static func _seg_dist(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return minf(minf(JungleLayout.seg_dist(a0, b0, b1), JungleLayout.seg_dist(a1, b0, b1)),
			minf(JungleLayout.seg_dist(b0, a0, a1), JungleLayout.seg_dist(b1, a0, a1)))


# ---------------------------------------------------------------- the model

static func _meshes() -> Dictionary:
	if _parts.is_empty():
		var root := (load(MODEL) as PackedScene).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			_parts[String(mi.name)] = mi.mesh
		root.free()
	return _parts


## The bridge's three spans, hinged at its joints: {root, pivot_l, pivot_r, meshes}. `mat` overrides every
## material (the cyan preview). layout() fits it to a length and folds it.
static func build_model(p_length: float, mat: Material = null) -> Dictionary:
	var parts := _meshes()
	var root := Node3D.new()
	root.name = "Model"
	var m := {"root": root, "meshes": []}
	var deck := _span(parts["Deck"], mat)
	root.add_child(deck)
	var pl := Node3D.new()
	pl.name = "HingeL"
	root.add_child(pl)
	var wl := _span(parts["WingL"], mat)
	pl.add_child(wl)
	var pr := Node3D.new()
	pr.name = "HingeR"
	root.add_child(pr)
	var wr := _span(parts["WingR"], mat)
	pr.add_child(wr)
	m.deck = deck
	m.pivot_l = pl
	m.pivot_r = pr
	m.wing_l = wl
	m.wing_r = wr
	m.meshes = [deck, wl, wr]
	layout(m, p_length, 0.0)
	return m


## Stretches the model to `p_length` and folds it: 0 flat, 1 folded (the left span upside down on top of the deck,
## the right one under it), eased in between.
static func layout(m: Dictionary, p_length: float, fold: float) -> void:
	var k := p_length / REF_LENGTH
	m.deck.scale = Vector3(k, 1, 1)
	m.pivot_l.position = Vector3(-HINGE_X * k, HINGE_TOP, 0)
	m.wing_l.position = Vector3(HINGE_X * k, -HINGE_TOP, 0)
	m.wing_l.scale = Vector3(k, 1, 1)
	m.pivot_r.position = Vector3(HINGE_X * k, HINGE_BOTTOM, 0)
	m.wing_r.position = Vector3(-HINGE_X * k, -HINGE_BOTTOM, 0)
	m.wing_r.scale = Vector3(k, 1, 1)
	# The left span goes up and over, the right one down and round: both turn the same way.
	m.pivot_l.rotation.z = -PI * fold
	m.pivot_r.rotation.z = -PI * fold


static func _span(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The see-through preview's material: cyan, or red where the bridge can't go.
static func ghost_material(ok := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.albedo_color = GHOST_COLOR if ok else Color(1.0, 0.25, 0.2, 0.35)
	return m


# ---------------------------------------------------------------- setup

## Sets it up from a plan() that is ok, as bridge `id` of `p_level`. Add it to the tree after.
func setup(p_plan: Dictionary, id: int, p_level: LevelBuilder) -> void:
	bridge_id = id
	level = p_level
	length = p_plan.length
	transform = p_plan.xform
	name = "Bridge%d" % id


func _ready() -> void:
	add_to_group("bridges")
	all.append(self)
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_model = build_model(length)
	_rig.add_child(_model.root)
	layout(_model, length, 1.0)
	_build_pods()
	_build_lamps()
	_build_hp_bar()
	# Where it will land, for the attacking player: a faint cyan copy of it there, flat.
	if GameConfig.player_side == GameConfig.PlayerSide.ATTACKER:
		_ghost_mat = ghost_material()
		_ghost = build_model(length, _ghost_mat)
		add_child(_ghost.root)
	_roar = AudioStreamPlayer3D.new()
	_roar.stream = _roar_stream()
	_roar.unit_size = 45.0
	_roar.max_distance = 700.0
	_roar.volume_db = -6.0
	_rig.add_child(_roar)
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = _siren_stream()
	_siren.unit_size = 30.0
	_siren.max_distance = 500.0
	_siren.volume_db = -4.0
	add_child(_siren)
	_place_rig()


func _exit_tree() -> void:
	all.erase(self)


## True once it is down and can be crossed.
func is_standing() -> bool:
	return state == State.STANDING


func is_alive() -> bool:
	return hp > 0.0 and state != State.FALLEN


## A bridge's ends (world): where the flaps' tips rest.
func tips() -> Array[Vector3]:
	return [global_transform * Vector3(-length * 0.5, -TIP_DROP, 0), global_transform * Vector3(length * 0.5, -TIP_DROP, 0)]


## True if `p` is on it (over its deck, between its railings).
func carries(p: Vector3, margin := 0.5) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) <= length * 0.5 + margin and absf(l.z) <= HALF_WIDTH + margin and l.y > -TRUSS - 1.0 and l.y < RAIL_H + 4.0


## The gap it opens in the wall along the water's edge: [middle, along (unit), half its length, half its width].
func cut() -> Array:
	var a := global_transform.basis.x
	var along := Vector2(a.x, a.z).normalized()
	return [Vector2(global_position.x, global_position.z), along, length * 0.5 + 1.0, HALF_WIDTH]


## The ground it covers (flat, world), for the navmesh tiles to rebake.
func footprint() -> Rect2:
	var r := Rect2(Vector2(global_position.x, global_position.z), Vector2.ZERO)
	for x in [-length * 0.5, length * 0.5]:
		for z in [-HALF_WIDTH, HALF_WIDTH]:
			var p := global_transform * Vector3(x, 0, z)
			r = r.expand(Vector2(p.x, p.z))
	return r.grow(4.0)


# ---------------------------------------------------------------- damage

func get_aim_point() -> Vector3:
	return global_position + global_basis.y * 0.8


## How far `p` is from it (its deck, trusses and railings as one box), for blasts (Combat.damage_area).
func blast_distance(p: Vector3) -> float:
	var l := global_transform.affine_inverse() * p
	var q := Vector3(clampf(l.x, -length * 0.5, length * 0.5), clampf(l.y, -TRUSS, RAIL_H), clampf(l.z, -HALF_WIDTH, HALF_WIDTH))
	return l.distance_to(q)


## Hits the defenders land on it: ARMOR less each (never below MIN_SHARE of it). No alarm.
func take_damage(amount: float, from_team: int) -> void:
	if from_team == team or state != State.STANDING or hp <= 0.0:
		return
	hp -= maxf(amount - ARMOR, amount * MIN_SHARE)
	_hp_shown = HP_SHOW
	_update_hp_bar()
	if hp <= 0.0:
		_collapse()


# ---------------------------------------------------------------- the drop

func _process(delta: float) -> void:
	age += delta
	match state:
		State.DROPPING:
			_alt += _vel * delta
			if _alt <= BRAKE_AT:
				state = State.BRAKING
				_ignite()
		State.BRAKING:
			# Just hard enough to stop at the hover.
			var a := _vel * _vel / (2.0 * maxf(_alt - HOVER, 0.5))
			_vel = minf(_vel + a * delta, 0.0)
			_alt += _vel * delta
			_thrust = 1.0
			if _alt <= HOVER + 0.05 or _vel > -0.3:
				_alt = HOVER
				_vel = 0.0
				state = State.UNFOLDING
				_t = 0.0
		State.UNFOLDING:
			_t += delta
			_fold = 1.0 - smoothstep(0.0, UNFOLD_TIME, _t)
			_alt = HOVER + sin(_t * 2.2) * 0.25
			_thrust = lerpf(_thrust, 0.65, minf(delta * 3.0, 1.0))
			layout(_model, length, _fold)
			if _t >= UNFOLD_TIME + 0.4:
				state = State.LANDING
				_t = 0.0
		State.LANDING:
			_t += delta
			var e := clampf(_t / DESCEND_TIME, 0.0, 1.0)
			_alt = (HOVER + sin((UNFOLD_TIME + 0.4) * 2.2) * 0.25) * pow(1.0 - e, 2.2)
			_thrust = lerpf(0.65, 0.4, e)
			if e >= 1.0:
				_touchdown()
		State.STANDING:
			_standing(delta)
	if state != State.STANDING and state != State.FALLEN:
		_place_rig()
		_pods_fx(delta)
		if _ghost_mat:
			_ghost_mat.albedo_color.a = 0.2 + 0.1 * sin(age * 4.0)
	if _hp_bar.visible or _hp_shown > 0.0:
		_hp_shown -= delta
		_hp_bar.visible = _hp_shown > 0.0 and is_alive()
		var cam := get_viewport().get_camera_3d()
		if cam and _hp_bar.visible:
			_hp_bar.global_position = global_position + Vector3.UP * (RAIL_H + 3.0)
			_hp_bar.global_basis = cam.global_basis


## The rig over its spot: _alt up, swaying a little on the way down and turning into line.
func _place_rig() -> void:
	var sway := clampf((_alt - HOVER * 0.3) / (DROP_FROM - HOVER), 0.0, 1.0)
	_rig.position = Vector3(0, _alt, 0)
	_rig.rotation = Vector3(sin(age * 1.7) * 0.05 * sway + sin(age * 3.1) * 0.006 * _thrust,
			SPIN * clampf((_alt - HOVER) / (DROP_FROM - HOVER), 0.0, 1.0),
			sin(age * 1.1 + 1.0) * 0.04 * sway)


func _touchdown() -> void:
	state = State.STANDING
	_alt = 0.0
	_thrust = 0.0
	layout(_model, length, 0.0)
	_rig.rotation = Vector3.ZERO
	_rig.position = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_rig, "position:y", -0.18, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rig, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	for f in _flames:
		f.visible = false
	for e in _exhaust:
		e.emitting = false
	for l in _pod_lights:
		l.light_energy = 0.0
	_spray.emitting = false
	if _roar.playing:
		var fade := create_tween()
		fade.tween_property(_roar, "volume_db", -40.0, 1.2)
		fade.tween_callback(_roar.stop)
	# The pods tuck in under the deck.
	for p in _pods:
		var to: Vector3 = p.get_meta("stowed")
		create_tween().tween_property(p, "position", to, 1.6).set_trans(Tween.TRANS_SINE).set_delay(0.6)
	for tip in tips():
		_dust(tip)
	_splash(global_position + Vector3.DOWN * 2.0, 14.0)
	if _ghost.has("root"):
		_ghost.root.queue_free()
		_ghost = {}
		_ghost_mat = null
	_land()


## Down: solid, baked into the navmesh, the wall at the water's edge open under it, and the forest it came down on
## flattened.
func _land() -> void:
	add_to_group("damageable")
	_build_body()
	_build_area()
	if JungleFlora.current:
		JungleFlora.current.clear_footprint(global_transform, Vector2(length * 0.5 + 1.5, HALF_WIDTH + 1.0))
	_open_walls()
	if level and level.has_method("rebake_rect"):
		level.rebake_rect(footprint())
	landed.emit(self)


## The wall at the water's edge, with a gap under every bridge standing.
static func _open_walls() -> void:
	if JungleTerrain.current == null:
		return
	var cuts := []
	for b in all:
		if b.state == State.STANDING:
			cuts.append(b.cut())
	JungleTerrain.current.cut_water_edge(cuts)


func _build_body() -> void:
	_body = StaticBody3D.new()
	_body.name = "Bridge%dBody" % bridge_id
	_body.collision_layer = GameConfig.LAYER_WORLD
	_body.collision_mask = 0
	# Shots that hit it hurt the bridge (Combat.find_damageable).
	_body.set_meta("damageable", self)
	var k := length / REF_LENGTH
	var flap_x := FLAP_X * k
	var tip_x := length * 0.5
	_box(Vector3(flap_x * 2.0, TRUSS, HALF_WIDTH * 2.0), Vector3(0, -TRUSS * 0.5, 0), 0.0)
	for s in [-1.0, 1.0]:
		var a := Vector2(s * flap_x, 0.0)
		var b := Vector2(s * tip_x, -TIP_DROP)
		var ang := atan((b.y - a.y) / (b.x - a.x))
		var up := Vector2(-sin(ang), cos(ang))
		var c := (a + b) * 0.5 - up * 0.4
		_box(Vector3(a.distance_to(b) + 0.6, 0.8, HALF_WIDTH * 2.0), Vector3(c.x, c.y, 0), ang)
	# The railings along the deck, flush with low curbs on down the flaps' sides to just short of their tips: the way
	# on and off is over the tips only (the flaps' sides stand proud of a bank that slopes across the bridge).
	var rail_y := (RAIL_H - 0.6) * 0.5
	for s: float in [-1.0, 1.0]:
		var z := s * (HALF_WIDTH - 0.17)
		_box(Vector3(flap_x * 2.0, RAIL_H + 0.6, 0.35), Vector3(0, rail_y, z), 0.0)
		for e: float in [-1.0, 1.0]:
			var a := Vector2(e * flap_x, 0.0)
			var b := Vector2(e * (tip_x - CURB_SHORT), -TIP_DROP * (tip_x - CURB_SHORT - flap_x) / (tip_x - flap_x))
			var ang := atan((b.y - a.y) / (b.x - a.x))
			var c := (a + b) * 0.5
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(a.distance_to(b), CURB_H * 2.0, 0.35)
			cs.shape = shape
			cs.position = Vector3(c.x, c.y, z)
			cs.rotation.z = ang
			_body.add_child(cs)
	var parent: Node = level.nav_region if level and level.nav_region else get_parent()
	parent.add_child(_body)
	_body.global_transform = global_transform


func _box(size: Vector3, at: Vector3, roll: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = at
	cs.rotation.z = roll
	_body.add_child(cs)


## The defenders on the deck (the alarm).
func _build_area() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = GameConfig.LAYER_DEFENDERS
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, RAIL_H + 3.5, HALF_WIDTH * 2.0)
	cs.shape = shape
	cs.position.y = (RAIL_H + 3.5) * 0.5 - 1.0
	_area.add_child(cs)
	add_child(_area)


# ---------------------------------------------------------------- standing: the alarm

func _standing(delta: float) -> void:
	_check_cd -= delta
	if _check_cd <= 0.0:
		_check_cd = CHECK_EVERY
		intruders = []
		for b in _area.get_overlapping_bodies():
			var d = Combat.find_damageable(b)
			if d != null and d.get("team") == GameConfig.TEAM_DEFENDER and d.is_alive() and carries(d.global_position, 0.3):
				intruders.append(d)
		var on := not intruders.is_empty()
		if on != alarm_on:
			alarm_on = on
			if on:
				_siren.play()
				_flash_t = 0.0
			else:
				_siren.stop()
			alarm.emit(self, on)
	if alarm_on:
		_flash_t += delta
	var phase := fmod(_flash_t * ALARM_RATE, 1.0) < 0.5
	for k in _lamp_mats.size():
		var lit := alarm_on and (phase == (k % 2 == 0))
		_lamp_mats[k].emission_energy_multiplier = 16.0 if lit else 0.15
	for h in _halos:
		h.visible = alarm_on and (phase == (int(h.get_meta("side")) % 2 == 0))
	for k in _alarm_lights.size():
		_alarm_lights[k].light_energy = (12.0 if phase == (k % 2 == 0) else 0.0) if alarm_on else 0.0


## Red lamps on the railing posts, the two sides flashing by turns, and red lights over the deck.
func _build_lamps() -> void:
	var k := length / REF_LENGTH
	for side in 2:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.05, 0.04)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.08, 0.05)
		m.emission_energy_multiplier = 0.15
		m.roughness = 0.3
		_lamp_mats.append(m)
	var dome := SphereMesh.new()
	dome.radius = 0.34
	dome.height = 0.5
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 4
	var base := CylinderMesh.new()
	base.top_radius = 0.2
	base.bottom_radius = 0.24
	base.height = 0.16
	base.radial_segments = 10
	var base_mat := Mats.flat(Color(0.12, 0.12, 0.12), 0.6, 0.5)
	for x0 in LAMP_X:
		var x: float = x0 * k
		for side in 2:
			var z := (HALF_WIDTH - 0.2) * (1.0 if side == 0 else -1.0)
			var parent: Node3D = _model.root
			var at := Vector3(x, RAIL_H + 0.08, z)
			if x < -HINGE_X * k:
				parent = _model.wing_l
				at = Vector3(x0, RAIL_H + 0.08, z)
			elif x > HINGE_X * k:
				parent = _model.wing_r
				at = Vector3(x0, RAIL_H + 0.08, z)
			# On a span, in the span's own (unstretched) frame.
			if parent != _model.root:
				var lamp_base := MeshInstance3D.new()
				lamp_base.mesh = base
				lamp_base.material_override = base_mat
				lamp_base.position = at
				lamp_base.scale = Vector3(1.0 / k, 1, 1)
				parent.add_child(lamp_base)
				var lamp := MeshInstance3D.new()
				lamp.mesh = dome
				lamp.material_override = _lamp_mats[(LAMP_X.find(x0) + side) % 2]
				lamp.position = at + Vector3(0, 0.08, 0)
				lamp.scale = Vector3(1.0 / k, 1, 1)
				lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(lamp)
				_halo(parent, at + Vector3(0, 0.2, 0), (LAMP_X.find(x0) + side) % 2)
			else:
				var lamp_base := MeshInstance3D.new()
				lamp_base.mesh = base
				lamp_base.material_override = base_mat
				lamp_base.position = at
				_model.root.add_child(lamp_base)
				var lamp := MeshInstance3D.new()
				lamp.mesh = dome
				lamp.material_override = _lamp_mats[(LAMP_X.find(x0) + side) % 2]
				lamp.position = at + Vector3(0, 0.08, 0)
				lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_model.root.add_child(lamp)
				_halo(_model.root, at + Vector3(0, 0.2, 0), (LAMP_X.find(x0) + side) % 2)
	for x0 in [-24.0, -8.0, 8.0, 24.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.12, 0.08)
		l.light_energy = 0.0
		l.omni_range = 20.0
		l.omni_attenuation = 1.0
		l.shadow_enabled = false
		l.position = Vector3(x0 * k, RAIL_H + 1.2, 0)
		add_child(l)
		_alarm_lights.append(l)


## A red glow round a lamp, showing while it flashes (`side`: which of the two that take turns).
func _halo(parent: Node3D, at: Vector3, side: int) -> void:
	var h := Sprite3D.new()
	h.texture = _halo_texture()
	h.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	h.shaded = false
	h.transparent = true
	h.modulate = Color(1.0, 0.15, 0.08, 0.9)
	h.pixel_size = 2.4 / 64.0
	h.position = at
	h.top_level = false
	h.visible = false
	h.set_meta("side", side)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(h)
	# Stays round on the stretched spans.
	h.scale = Vector3(1.0 / parent.global_transform.basis.get_scale().x if parent != _model.root else 1.0, 1, 1)
	_halos.append(h)


static var _halo_tex: GradientTexture2D


static func _halo_texture() -> GradientTexture2D:
	if _halo_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.25, Color(1, 1, 1, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_halo_tex = GradientTexture2D.new()
		_halo_tex.gradient = g
		_halo_tex.fill = GradientTexture2D.FILL_RADIAL
		_halo_tex.fill_from = Vector2(0.5, 0.5)
		_halo_tex.fill_to = Vector2(1.0, 0.5)
		_halo_tex.width = 64
		_halo_tex.height = 64
	return _halo_tex


# ---------------------------------------------------------------- thrusters

## Four thruster pods out along the deck's sides, their nozzles pointing down, tucked in under it once it is down.
func _build_pods() -> void:
	var k := length / REF_LENGTH
	var hull := Mats.flat(Color(0.2, 0.22, 0.2), 0.7, 0.45)
	var dark := Mats.flat(Color(0.07, 0.07, 0.07), 0.8, 0.35)
	var outer := _flame_material(Color(1.0, 0.55, 0.18), 5.0)
	var inner := _flame_material(Color(0.75, 0.85, 1.0), 9.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pod := Node3D.new()
			pod.position = Vector3(sx * POD_X * k, -1.3, sz * (HALF_WIDTH + 1.0))
			pod.set_meta("stowed", Vector3(sx * POD_X * k, -2.2, sz * (HALF_WIDTH - 2.2)))
			_model.root.add_child(pod)
			pod.add_child(Mats.cylinder_mesh(0.8, 2.8, Vector3(0, 0.2, 0), hull, 14))
			pod.add_child(Mats.box_mesh(Vector3(1.0, 0.5, 1.3), Vector3(0, 0.9, -sz * 0.9), hull))
			var nozzle := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.55
			cone.bottom_radius = 0.85
			cone.height = 0.9
			cone.radial_segments = 14
			nozzle.mesh = cone
			nozzle.material_override = dark
			nozzle.position = Vector3(0, -1.6, 0)
			pod.add_child(nozzle)
			for layer in [[outer, 0.75, 1.0], [inner, 0.38, 0.6]]:
				var f := MeshInstance3D.new()
				var c := CylinderMesh.new()
				c.top_radius = layer[1]
				c.bottom_radius = 0.05
				c.height = FLAME_LEN * layer[2]
				c.radial_segments = 12
				c.rings = 1
				c.cap_top = false
				c.cap_bottom = false
				f.mesh = c
				f.material_override = layer[0]
				f.position = Vector3(0, -2.0 - c.height * 0.5, 0)
				f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				f.visible = false
				f.set_meta("len", c.height)
				pod.add_child(f)
				_flames.append(f)
			var ex := CPUParticles3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(1.6, 1.6)
			quad.material = _puff_material()
			ex.mesh = quad
			ex.amount = 40
			ex.lifetime = 0.9
			ex.local_coords = false
			ex.direction = Vector3.DOWN
			ex.spread = 9.0
			ex.initial_velocity_min = 22.0
			ex.initial_velocity_max = 30.0
			ex.damping_min = 14.0
			ex.damping_max = 20.0
			ex.gravity = Vector3(0, 1.5, 0)
			ex.scale_amount_min = 1.2
			ex.scale_amount_max = 2.6
			var ramp := Gradient.new()
			ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
			ramp.add_point(0.25, Color(0.85, 0.45, 0.2, 0.6))
			ramp.set_color(ramp.get_point_count() - 1, Color(0.45, 0.42, 0.4, 0.0))
			ex.color_ramp = ramp
			ex.position = Vector3(0, -2.2, 0)
			ex.emitting = false
			pod.add_child(ex)
			_exhaust.append(ex)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 0.0
			l.omni_range = 22.0
			l.position = Vector3(0, -4.0, 0)
			pod.add_child(l)
			_pod_lights.append(l)
			_pods.append(pod)
	# Spray thrown up off the water under it as it comes down.
	_spray = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	var sm := _puff_material()
	q.material = sm
	_spray.mesh = q
	_spray.amount = 90
	_spray.lifetime = 2.0
	_spray.local_coords = false
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_spray.emission_box_extents = Vector3(length * 0.3, 0.2, HALF_WIDTH + 2.0)
	_spray.direction = Vector3(0, 1, 0)
	_spray.spread = 75.0
	_spray.initial_velocity_min = 4.0
	_spray.initial_velocity_max = 10.0
	_spray.damping_min = 2.0
	_spray.damping_max = 4.0
	_spray.gravity = Vector3(0, -3.0, 0)
	_spray.scale_amount_min = 1.5
	_spray.scale_amount_max = 4.0
	var sr := Gradient.new()
	sr.set_color(0, Color(0.92, 0.95, 0.95, 0.55))
	sr.set_color(1, Color(0.85, 0.88, 0.9, 0.0))
	_spray.color_ramp = sr
	_spray.emitting = false
	add_child(_spray)


func _ignite() -> void:
	for f in _flames:
		f.visible = true
	for e in _exhaust:
		e.emitting = true
	_roar.play()


## Flames flickering with the thrust, the lights with them, spray off the water once it is low enough.
func _pods_fx(_delta: float) -> void:
	if _thrust <= 0.0:
		return
	for k in _flames.size():
		var f := _flames[k]
		var flick := 0.85 + 0.15 * sin(age * 37.0 + k * 1.7) + randf_range(-0.06, 0.06)
		var s := maxf(_thrust * flick, 0.05)
		f.scale = Vector3(0.8 + 0.2 * s, s, 0.8 + 0.2 * s)
		var l: float = f.get_meta("len")
		f.position.y = -2.0 - l * 0.5 * s
	for k in _pod_lights.size():
		_pod_lights[k].light_energy = 7.0 * _thrust * (0.85 + 0.15 * sin(age * 29.0 + k))
	for e in _exhaust:
		e.initial_velocity_min = 16.0 + 14.0 * _thrust
		e.initial_velocity_max = 22.0 + 16.0 * _thrust
	# The water's surface under it: spray while the jets reach it.
	var over := global_position.y + _alt - 6.0 - JungleLayout.WATER_Y
	_spray.global_position = Vector3(global_position.x, JungleLayout.WATER_Y + 0.3, global_position.z)
	_spray.global_rotation = Vector3(0, global_rotation.y, 0)
	_spray.emitting = over < 40.0 and _thrust > 0.2
	_spray.initial_velocity_max = 4.0 + 10.0 * clampf(1.0 - over / 40.0, 0.2, 1.0) * _thrust
	_roar.volume_db = linear_to_db(maxf(_thrust, 0.05)) - 4.0


static func _flame_material(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c, 0.85)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func _puff_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = SmokeCloud.puff_texture()
	return m


func _dust(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.material = _puff_material()
	p.mesh = q
	p.amount = 30
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.0, 0.3, HALF_WIDTH)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var g := Gradient.new()
	g.set_color(0, Color(0.45, 0.38, 0.28, 0.8))
	g.set_color(1, Color(0.45, 0.38, 0.28, 0.0))
	p.color_ramp = g
	add_child(p)
	p.global_position = at + Vector3.UP * 0.4
	p.global_rotation = Vector3(0, global_rotation.y, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _splash(at: Vector3, size: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	q.material = _puff_material()
	p.mesh = q
	p.amount = 60
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size, 0.2, HALF_WIDTH + 1.0)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.97, 0.97, 0.8))
	g.set_color(1, Color(0.9, 0.93, 0.95, 0.0))
	p.color_ramp = g
	add_child(p)
	p.global_position = Vector3(at.x, JungleLayout.WATER_Y + 0.2, at.z)
	p.global_rotation = Vector3(0, global_rotation.y, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


# ---------------------------------------------------------------- brought down

## It breaks at its joints and goes down into the river: the wall at the water's edge closes again, the navmesh
## loses it, and everyone on it falls in (those that can't swim drown; swimmers make for the nearer bank).
func _collapse() -> void:
	hp = 0.0
	state = State.FALLEN
	remove_from_group("damageable")
	all.erase(self)
	if alarm_on:
		alarm_on = false
		_siren.stop()
		alarm.emit(self, false)
	for l in _alarm_lights:
		l.light_energy = 0.0
	_hp_bar.visible = false
	var on_it := []
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if u.is_alive() and not u.is_flying() and u.carrier == null and carries(u.global_position):
			on_it.append(u)
	var defenders := []
	for d in get_tree().get_nodes_in_group("damageable"):
		if d.get("team") == GameConfig.TEAM_DEFENDER and d.is_alive() and d is CharacterBody3D and carries(d.global_position):
			defenders.append(d)
	if _body:
		# Out of the tree now, before the tiles under it are rebaked.
		_body.get_parent().remove_child(_body)
		_body.queue_free()
		_body = null
	if _area:
		_area.queue_free()
		_area = null
	_open_walls()
	if level and level.has_method("rebake_rect"):
		level.rebake_rect(footprint())
	var ends := tips()
	for u in on_it:
		if u.swims():
			var near: Vector3 = ends[0] if u.global_position.distance_to(ends[0]) < u.global_position.distance_to(ends[1]) else ends[1]
			u.swim_to(near)
		else:
			u.drown()
	for d in defenders:
		d.take_damage(100000.0, GameConfig.TEAM_ATTACKER)
	fallen.emit(self)
	# Blasts along it, the spans breaking at the joints, and down it goes.
	for x in [-0.3, 0.0, 0.3]:
		Combat.spawn_explosion(self, global_transform * Vector3(length * x, 0.5, 0), 7.0)
	_splash(global_position, length * 0.45)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_model.pivot_l, "rotation:z", 0.55, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_model.pivot_r, "rotation:z", -0.55, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_rig, "position:y", -5.0, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_rig, "rotation:x", 0.08, 2.2)
	tw.chain().tween_property(_rig, "position:y", -14.0, 5.0)
	tw.chain().tween_callback(queue_free)


# ---------------------------------------------------------------- health bar

func _build_hp_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.top_level = true
	_hp_bar.visible = false
	add_child(_hp_bar)
	var bg := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(9.0, 0.7)
	bg.mesh = qm
	bg.material_override = Mats.unshaded(Color(0.05, 0.05, 0.05, 0.8))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(8.7, 0.45)
	_hp_fill.mesh = fm
	_hp_fill.material_override = Mats.unshaded(Color(0.95, 0.7, 0.25))
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_fill.position.z = 0.01
	_hp_bar.add_child(_hp_fill)


func _update_hp_bar() -> void:
	var f := clampf(hp / MAX_HP, 0.0, 1.0)
	_hp_fill.scale.x = maxf(f, 0.001)
	_hp_fill.position.x = -8.7 * (1.0 - f) * 0.5


# ---------------------------------------------------------------- sounds

## A wailing siren, made up here (1.6 s, looping).
static func _siren_stream() -> AudioStreamWAV:
	if _siren_wav:
		return _siren_wav
	var rate := 22050
	var n := int(rate * 1.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 640.0 + 460.0 * (0.5 - 0.5 * cos(TAU * t / 1.6))
		phase += TAU * f / rate
		var v := (sin(phase) * 0.55 + sin(phase * 2.0) * 0.18 + sin(phase * 3.0) * 0.08) * 0.8
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	_siren_wav = AudioStreamWAV.new()
	_siren_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_siren_wav.mix_rate = rate
	_siren_wav.data = data
	_siren_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_siren_wav.loop_end = n
	return _siren_wav


## The thrusters' roar: low, rumbling noise (2 s, looping).
static func _roar_stream() -> AudioStreamWAV:
	if _roar_wav:
		return _roar_wav
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lo := 0.0
	var lo2 := 0.0
	for i in n:
		var white := rng.randf_range(-1.0, 1.0)
		lo += (white - lo) * 0.09
		lo2 += (lo - lo2) * 0.2
		var t := float(i) / rate
		var v := lo2 * 2.6 + sin(TAU * 52.0 * t) * 0.12 + white * 0.05
		# Fade the loop's ends into each other.
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	_roar_wav = AudioStreamWAV.new()
	_roar_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_roar_wav.mix_rate = rate
	_roar_wav.data = data
	_roar_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_roar_wav.loop_end = n
	return _roar_wav
