class_name GroundMine
extends Area3D
## A mine the AA Squad throws (AASquad.throw_mines): lobbed onto its spot, it arms ARM_TIME after
## landing and goes off when an enemy ground unit comes within TRIGGER_RADIUS (aircraft pass over
## it), hurting everything round it (Combat.explode). A dark disc sunk into the ground, its cap
## showing, with a small light that blinks once it is armed.
##
## The attacking player never sees one (on the attacker's side it isn't drawn at all), though it goes
## off under their units all the same; only the Wolf Medic's nose finds them (DogSweep). A mine a dog digs
## at shows to them from then on (dug): the hole, the mine coming up out of it and, while the work goes on,
## a ring round it filling. It doesn't go off under the dog going for it (sweeper). After AttackerUnit
## disarm_time seconds of digging it is disarmed (disarm): the light goes out, the mine lies on the edge of
## its hole and is gone a little later.

const ARM_TIME := 1.2
const TRIGGER_RADIUS := 1.5
const DAMAGE := 160.0
const BLAST_RADIUS := 4.0
## Seconds in the air, and how high the lob goes per meter thrown.
const FLIGHT := 0.75
const ARC := 0.3
const BLINK := 0.9
## How deep it sits in the ground once it has landed (m): the cap shows.
const BURY := 0.06
## A disarmed mine lies by its hole this long (s), then sinks away.
const HUSK_TIME := 5.0
## The ring round a mine being dug out (attacker's side): radius (m) and colour.
const DIG_RING := 1.1
const DIG_COLOR := Color(1.0, 0.72, 0.2)
const DIRT := Color(0.33, 0.25, 0.16)

## Every live mine on the field (laid or still in the air; not the disarmed ones), and how many have
## gone off so far (the last where), how many were disarmed.
static var all: Array[GroundMine] = []
static var blasts := 0
static var last_blast := Vector3.INF
static var disarms := 0

var team := GameConfig.TEAM_DEFENDER
## The dog going for it, or digging it out: it doesn't go off under that one, and other dogs leave it
## to it (DogSweep).
var sweeper: Node3D = null
## How far the digging has got (0-1); 0 while nobody has dug at it.
var dug := 0.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _flying := true
var _arm := ARM_TIME
var _blink := 0.0
var _body: Node3D
var _light: MeshInstance3D
var _spin := Vector3.ZERO
var _gone := false
var _disarmed := false
var _husk := 0.0
var _hole: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mesh: ImmediateMesh
var _ring_drawn := -1.0


## Lobs the mine from `from` (a trooper's hand) onto `to` (on the ground).
func throw(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	global_position = from
	_spin = Vector3(randf_range(-9, 9), randf_range(-4, 4), randf_range(-9, 9))


## Lays the mine on `at` (on the ground) at once, armed (the showcases' minefields).
func lay(at: Vector3) -> void:
	_from = at
	_to = at
	_t = 1.0
	_arm = 0.0
	global_position = at


func is_armed() -> bool:
	return not _flying and _arm <= 0.0


## On the ground, not gone off nor disarmed: what a dog can find and dig out.
func is_laid() -> bool:
	return not _flying and not _gone and not _disarmed


func is_disarmed() -> bool:
	return _disarmed


## Ground spot the mine lies on (or is on its way to).
func spot() -> Vector3:
	return _to


## Drawn for the player on this side: always for the defender; for the attacker only once a dog digs at
## it.
func shown() -> bool:
	return GameConfig.player_side == GameConfig.PlayerSide.DEFENDER or dug > 0.0


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.LAYER_ATTACKERS
	monitoring = false
	monitorable = false
	var cs := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = TRIGGER_RADIUS
	cs.shape = ball
	cs.position.y = 0.7
	add_child(cs)
	body_entered.connect(_on_body_entered)
	_body = Node3D.new()
	add_child(_body)
	var casing := Mats.flat(Color(0.2, 0.23, 0.17), 0.6, 0.55)
	var disc := Mats.cylinder_mesh(0.3, 0.09, Vector3(0, 0.045, 0), casing, 12)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(disc)
	var cap := Mats.cylinder_mesh(0.12, 0.06, Vector3(0, 0.11, 0), Mats.flat(Color(0.12, 0.12, 0.11), 0.7, 0.4), 10)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(cap)
	_light = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.045
	s.height = 0.09
	s.radial_segments = 6
	s.rings = 3
	_light.mesh = s
	_light.material_override = Mats.glow(Color(1.0, 0.18, 0.1), 7.0)
	_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light.position = Vector3(0, 0.15, 0)
	_body.add_child(_light)
	_body.visible = shown()


func _process(_delta: float) -> void:
	# Follows GameConfig.player_side as it is now (the showcases switch sides).
	_body.visible = shown()
	if _ring:
		_ring.visible = dug > 0.0 and not _disarmed and GameConfig.player_side == GameConfig.PlayerSide.ATTACKER
		if _ring.visible and absf(dug - _ring_drawn) > 0.01:
			_draw_ring()


func _physics_process(delta: float) -> void:
	if _disarmed:
		_husk += delta
		if _husk > HUSK_TIME:
			_body.position.y -= delta * 0.12  # sinking away into the dirt
			if _husk > HUSK_TIME + 2.0:
				queue_free()
		return
	if _flying:
		_t += delta / FLIGHT
		if _t < 1.0:
			var arc := _from.distance_to(_to) * ARC
			global_position = _from.lerp(_to, _t) + Vector3.UP * arc * 4.0 * _t * (1.0 - _t)
			_body.rotation += _spin * delta
			return
		_flying = false
		global_position = _to
		_body.rotation = Vector3(0.0, randf() * TAU, 0.0)
		_body.position.y = -BURY
		if _arm > 0.0:
			SmokeCloud.wisp(self, _to + Vector3.UP * 0.2, 0.6)
	if _arm > 0.0:
		_arm -= delta
		_light.visible = fmod(_arm, 0.2) < 0.1  # quick flicker while it arms
		if _arm <= 0.0:
			monitoring = true
		return
	if not monitoring:
		monitoring = true  # laid armed (lay)
	_blink += delta
	_light.visible = fmod(_blink, BLINK) < 0.12


func _on_body_entered(body: Node3D) -> void:
	var u = Combat.find_damageable(body)
	if u == null or u.team == team or not u.is_alive() or u == sweeper:
		return
	if u.has_method("is_flying") and u.is_flying():
		return
	# Out of the physics callback: the blast kills units, which changes their collision layers.
	detonate.call_deferred()


## Goes off: everything within BLAST_RADIUS takes the damage.
func detonate() -> void:
	if _gone or _disarmed:
		return
	_gone = true
	blasts += 1
	last_blast = global_position
	set_deferred("monitoring", false)
	Combat.explode(self, global_position + Vector3.UP * 0.3, BLAST_RADIUS, DAMAGE, team)
	queue_free()


## Taken up quietly (its squad has too many down).
func fizzle() -> void:
	if _gone or _disarmed:
		return
	_gone = true
	SmokeCloud.wisp(self, global_position + Vector3.UP * 0.2, 0.5)
	queue_free()


## A dog digging it out has got `progress` (0-1) of the way: the hole widens round it and the mine comes
## up out of it, tilting as the dirt under it goes.
func dig(progress: float) -> void:
	if not is_laid():
		return
	dug = clampf(progress, 0.001, 1.0)
	_body.visible = shown()
	if _hole == null:
		_build_dig()
	var w := smoothstep(0.0, 1.0, dug)
	_hole.scale = Vector3(0.4 + 0.8 * w, 1.0, 0.4 + 0.8 * w)
	_body.position.y = lerpf(-BURY, 0.02, w)
	_body.rotation.x = 0.25 * w * sin(dug * 9.0)


## Dug out and disarmed: it can't go off any more. The light goes out and the mine lies tipped on the edge
## of its hole, then is gone a little later.
func disarm() -> void:
	if not is_laid():
		return
	dig(1.0)
	_disarmed = true
	disarms += 1
	all.erase(self)
	set_deferred("monitoring", false)
	_light.visible = false
	var tw := create_tween()
	tw.tween_property(_body, "position", Vector3(0.45, 0.08, 0.1), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_body, "rotation", Vector3(0.0, _body.rotation.y, 0.7), 0.35)
	SmokeCloud.wisp(self, global_position + Vector3.UP * 0.25, 0.5)


## The hole (a dark disc of dug earth, a rim of thrown-up dirt round it) and the attacker's ring.
func _build_dig() -> void:
	_hole = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.6
	disc.height = 0.03
	disc.radial_segments = 14
	_hole.mesh = disc
	_hole.material_override = Mats.flat(DIRT.darkened(0.35), 0.0, 1.0)
	_hole.position.y = 0.012
	_hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hole)
	var rim := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.5
	t.outer_radius = 0.78
	t.rings = 14
	t.ring_segments = 6
	rim.mesh = t
	rim.material_override = Mats.flat(DIRT, 0.0, 1.0)
	rim.scale = Vector3(1.0, 0.35, 1.0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hole.add_child(rim)
	_ring_mesh = ImmediateMesh.new()
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring.material_override = Mats.unshaded(DIG_COLOR, true)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


## The attacker's ring round the mine being dug out: dashed all round, solid as far as the work has got.
func _draw_ring() -> void:
	_ring_drawn = dug
	_ring_mesh.clear_surfaces()
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3.UP * 0.15
	RhinoAim.dashed_circle(_ring_mesh, lift, DIG_RING, 24)
	var n := 40
	var r := DIG_RING + 0.12
	for k in int(ceil(n * dug)):
		var a0 := TAU * k / n
		var a1 := TAU * minf(k + 1, n * dug) / n
		for dr in [0.0, 0.06]:
			_ring_mesh.surface_add_vertex(lift + Vector3(sin(a0), 0.0, -cos(a0)) * (r + dr))
			_ring_mesh.surface_add_vertex(lift + Vector3(sin(a1), 0.0, -cos(a1)) * (r + dr))
	_ring_mesh.surface_end()
