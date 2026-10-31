class_name ForestTree
extends StaticBody3D
## A tree on the map (LevelBuilder: the forest groves and the lone trees out in the field). A
## flamethrower's flame on it heats it (scorch()). Held on it for IGNITE_TIME without letting up, it
## sets the canopy on fire, which destroys the tree; a fast swoop of the flame isn't enough: once
## the flame has been off it for COOL_GRACE, the heat drains away COOL_RATE times as fast as it
## built up. Burning, the canopy blazes for BURN_TIME and blackens, then crumbles away, leaving the
## charred trunk smouldering; about FALL_TIME after the tree caught fire the trunk falls to the
## ground. A burnt tree never grows back: once it lies on the ground it no longer blocks anyone and
## the navmesh is rebaked without it (LevelBuilder.clear_obstacle).

signal ignited(tree: ForestTree)
signal fell(tree: ForestTree)

enum State { STANDING, BURNING, FALLEN }

const IGNITE_TIME := 8.0
const COOL_GRACE := 0.35
const COOL_RATE := 1.5
const BURN_TIME := 15.0
## The canopy crumbles away over this long, starting CRUMBLE_AT into the burn (s).
const CRUMBLE_AT := 8.5
const CRUMBLE_TIME := 3.5
## Seconds from catching fire to lying on the ground (each tree a little sooner or later than this).
const FALL_TIME := 30.0
const FALL_SPREAD := 2.5
## How long the trunk takes to topple (s), and how far over it ends up (it lies on its branches).
const TOPPLE_TIME := 2.4
const TOPPLE_ANGLE := deg_to_rad(84.0)
const TRUNK_RADIUS := 0.4
## Flame puffs a second from a canopy at the height of the blaze (scaled by its size).
const BLAZE_RATE := 75.0
const CHAR := Color(0.06, 0.05, 0.045)
const EMBER := Color(1.0, 0.36, 0.08)
## The trunk left standing glows like coals under the blaze, darker than the burning crown.
const COALS := Color(0.75, 0.18, 0.04)
## The smoke drifts off this way (m/s).
const WIND := Vector3(0.9, 0.0, 0.35)

## Trees still standing (not on fire), and every tree on the map.
static var standing: Array[ForestTree] = []
static var all: Array[ForestTree] = []

var height := 8.0
var canopy_radius := 2.5
## The trunk as modelled (Props.TRUNKS): where its foot stands off the tree's position (world), how thick it is
## there and how high up it a Serpent Sniper lies out in its nest, on top of the crown (m; SerpentNest).
var trunk_offset := Vector3.ZERO
var trunk_r := 0.12
var perch := 4.0
## The Serpent Sniper nesting in it, or on its way up to it (one to a tree).
var nest_by: Node = null
## Index into LevelBuilder.FORESTS of the grove it stands in (-1: a lone tree).
var grove := -1
var heat := 0.0
var state := State.STANDING
## The trooper burning it (a Flame Squad hands each tree to one trooper).
var claimed_by: Node = null
## Seconds since it caught fire.
var burn_t := 0.0

var _model: Node3D
var _snag: Node3D
var _snag_mat: StandardMaterial3D
var _light: OmniLight3D
## [material, colour it started with] for every surface of the model, once it burns.
var _mats: Array = []
var _since_flame := INF
var _scorched_frame := -1
var _scorch_at := Vector3.ZERO
var _fall_at := FALL_TIME
var _fall_axis := Vector3.RIGHT
var _fallen := false
var _emit := 0.0
var _smoke := 0.0
var _flicker := 0.0
var _shape: CollisionShape3D


## Sets the tree up before it goes into the scene: `model` (scaled to `h`), the trunk's collision.
func setup(h: float, model: Node3D, canopy_r: float, grove_index: int) -> void:
	height = h
	canopy_radius = canopy_r
	grove = grove_index
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = TRUNK_RADIUS
	trunk.height = h * 0.5
	_shape.shape = trunk
	_shape.position.y = h * 0.25
	add_child(_shape)
	_model = model
	add_child(model)


func _enter_tree() -> void:
	all.append(self)
	if state == State.STANDING:
		standing.append(self)


func _exit_tree() -> void:
	all.erase(self)
	standing.erase(self)


func _ready() -> void:
	add_to_group("trees")
	set_physics_process(false)


func is_standing() -> bool:
	return state == State.STANDING


## The foot of the trunk as modelled (world).
func trunk_centre() -> Vector3:
	return global_position + trunk_offset


## How thick the trunk is `y` m up it (it thins toward the crown).
func trunk_radius(y: float) -> float:
	return trunk_r * clampf(1.0 - 0.45 * y / height, 0.45, 1.0)


## A Serpent Sniper may nest in it: standing, and no other snake's.
func nest_free(snake: Node) -> bool:
	return is_standing() and (nest_by == null or nest_by == snake or not is_instance_valid(nest_by))


## How far it is to catching fire (0..1).
func heat_fraction() -> float:
	return heat / IGNITE_TIME


## Where a flame should be aimed to set it alight: the trunk, under the canopy.
func aim_point() -> Vector3:
	return global_position + Vector3.UP * minf(1.7, height * 0.25)


## The flame is on the trunk this physics frame, at `at`: it heats up (once a frame, however many
## flames are on it: it takes IGNITE_TIME of flame all the same). True when that set the canopy on
## fire.
func scorch(delta: float, at: Vector3) -> bool:
	if state != State.STANDING:
		return false
	var frame := Engine.get_physics_frames()
	if frame == _scorched_frame:
		return false
	_scorched_frame = frame
	heat += delta
	_since_flame = 0.0
	_scorch_at = at
	set_physics_process(true)
	if heat >= IGNITE_TIME:
		_ignite()
		return true
	return false


func _ignite() -> void:
	state = State.BURNING
	heat = IGNITE_TIME
	burn_t = 0.0
	standing.erase(self)
	claimed_by = null
	var h := absi(hash(global_position))
	_fall_at = FALL_TIME + (float(h % 1000) / 1000.0 - 0.5) * 2.0 * FALL_SPREAD
	var a := float((h / 1000) % 628) / 100.0
	_fall_axis = Vector3(cos(a), 0.0, sin(a))
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.emission_enabled = true
			m.emission = EMBER
			m.emission_energy_multiplier = 0.0
			(mi as MeshInstance3D).set_surface_override_material(s, m)
			_mats.append([m, src.albedo_color])
	_build_snag()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 9.0 + canopy_radius * 2.5
	_light.light_energy = 0.0
	_light.position = Vector3.UP * height * 0.62
	add_child(_light)
	ignited.emit(self)


## The trunk left standing once the canopy has burnt away: charred, a few branch stubs, glowing
## at first. It stands inside the model until the canopy crumbles.
func _build_snag() -> void:
	_snag = Node3D.new()
	add_child(_snag)
	_snag_mat = StandardMaterial3D.new()
	_snag_mat.albedo_color = CHAR
	_snag_mat.roughness = 1.0
	_snag_mat.emission_enabled = true
	_snag_mat.emission = COALS
	_snag_mat.emission_energy_multiplier = 0.0
	var tall := height * 0.62
	var trunk := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.07
	c.bottom_radius = TRUNK_RADIUS * 0.75
	c.height = tall
	c.radial_segments = 7
	c.rings = 2
	trunk.mesh = c
	trunk.material_override = _snag_mat
	trunk.position.y = tall * 0.5
	_snag.add_child(trunk)
	var h := absi(hash(global_position + Vector3.ONE))
	for k in 3:
		var stub := MeshInstance3D.new()
		var b := CylinderMesh.new()
		b.top_radius = 0.03
		b.bottom_radius = 0.09
		b.height = 0.9 + 0.3 * k
		b.radial_segments = 5
		b.rings = 1
		stub.mesh = b
		stub.material_override = _snag_mat
		var yaw := float((h >> (k * 4)) % 628) / 100.0
		stub.position = Vector3(0.0, tall * (0.45 + 0.17 * k), 0.0)
		stub.rotation = Vector3(0.0, yaw, deg_to_rad(55.0))
		stub.position += Basis(Vector3.UP, yaw) * Vector3(-0.35, 0.2, 0.0)
		_snag.add_child(stub)


func _physics_process(delta: float) -> void:
	match state:
		State.STANDING:
			_heating(delta)
		State.BURNING:
			_burning(delta)
		State.FALLEN:
			_smouldering(delta)


## Heated but not alight: the heat drains away once the flame is off it, the canopy smokes more
## and more as it nears catching.
func _heating(delta: float) -> void:
	_since_flame += delta
	if _since_flame > COOL_GRACE:
		heat = maxf(heat - COOL_RATE * delta, 0.0)
	if heat <= 0.0:
		set_physics_process(false)
		return
	var f := heat_fraction()
	var fx := FireFX.of(self)
	_smoke += delta * (1.5 + 6.0 * f * f)
	while _smoke >= 1.0:
		_smoke -= 1.0
		if randf() < f:
			var p := _canopy_point(0.8)
			fx.smoke(p, Vector3(0.0, 1.6, 0.0) + WIND * 0.6, randf_range(2.5, 4.0), 0.8, 3.0 + 2.0 * f)
		else:
			fx.smoke(_scorch_at + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)),
					Vector3(0.0, 1.4, 0.0), randf_range(1.5, 2.5), 0.4, 1.6)
	# Close to catching, flames lick up from the trunk into the canopy.
	if f > 0.55:
		_emit += delta * 30.0 * (f - 0.55)
		while _emit >= 1.0:
			_emit -= 1.0
			var at := global_position + Vector3(randf_range(-0.3, 0.3), randf_range(1.0, height * 0.45), randf_range(-0.3, 0.3))
			fx.flame(at, Vector3(0.0, randf_range(2.0, 3.5), 0.0), randf_range(0.4, 0.7), 0.3, 0.9)


func _burning(delta: float) -> void:
	burn_t += delta
	var fx := FireFX.of(self)
	# The blaze: catches in a second and a half, roars, dies down by BURN_TIME.
	var blaze := clampf(burn_t / 1.5, 0.0, 1.0) * clampf((BURN_TIME - burn_t) / (BURN_TIME * 0.45), 0.0, 1.0)
	var size := clampf(canopy_radius / 2.5, 0.7, 1.6)
	_emit += delta * BLAZE_RATE * blaze * size
	while _emit >= 1.0:
		_emit -= 1.0
		var low := randf() < 0.18
		var p := _canopy_point(1.0) if not low else global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, height * 0.4), randf_range(-0.3, 0.3))
		var s := randf_range(0.9, 1.5) * size * (0.6 if low else 1.0)
		fx.flame(p, Vector3(randf_range(-0.4, 0.4), randf_range(2.2, 4.2), randf_range(-0.4, 0.4)), randf_range(0.6, 1.2),
				s, s * randf_range(1.8, 2.4), 2.5, 1.0)
	_smoke += delta * (1.2 + 7.0 * blaze) * size
	while _smoke >= 1.0:
		_smoke -= 1.0
		var top := global_position + Vector3.UP * height * (0.8 + 0.2 * blaze) + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * canopy_radius * 0.5
		var big := lerpf(2.0, 4.0, blaze) * size
		fx.smoke(top, Vector3(0.0, randf_range(2.0, 3.2), 0.0) + WIND, randf_range(5.0, 7.5), big, big * 2.6, 0.3, 0.25)
	_flicker = lerpf(_flicker, randf(), 0.35)
	_light.light_energy = (3.0 + 2.5 * _flicker) * blaze
	_light.position.y = height * lerpf(0.62, 0.35, clampf((burn_t - CRUMBLE_AT) / CRUMBLE_TIME, 0.0, 1.0))
	# The canopy blackens, glowing like coals at the height of the blaze, then crumbles away.
	var char_u := clampf(burn_t / CRUMBLE_AT, 0.0, 1.0)
	var crumble := clampf((burn_t - CRUMBLE_AT) / CRUMBLE_TIME, 0.0, 1.0)
	for e in _mats:
		var m: BaseMaterial3D = e[0]
		var c := (e[1] as Color).lerp(CHAR, char_u)
		c.a = 1.0 - crumble
		m.albedo_color = c
		m.emission_energy_multiplier = 0.9 * blaze * char_u
		if crumble > 0.0 and m.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	if crumble >= 1.0 and _model.visible:
		_model.visible = false
	# The trunk left standing glows under the blaze, and cools once the crown is gone.
	_snag_mat.emission_energy_multiplier = 0.45 * clampf(burn_t / 3.0, 0.0, 1.0) * clampf(1.0 - (burn_t - CRUMBLE_AT) / 6.0, 0.0, 1.0)
	if burn_t >= _fall_at - TOPPLE_TIME:
		_fall()


## The charred trunk topples over (accelerating, like a falling tree) and lies where it fell; the
## way is clear once it is down.
func _fall() -> void:
	state = State.FALLEN
	_light.queue_free()
	_shape.disabled = true
	collision_layer = 0
	remove_from_group("trees")
	var tw := create_tween()
	tw.tween_property(_snag, "quaternion", Quaternion(_fall_axis, TOPPLE_ANGLE), TOPPLE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_landed)
	tw.tween_property(_snag, "quaternion", Quaternion(_fall_axis, TOPPLE_ANGLE - deg_to_rad(5.0)), 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_snag, "quaternion", Quaternion(_fall_axis, TOPPLE_ANGLE), 0.25) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Dust and sparks along the trunk where it hits the ground.
func _landed() -> void:
	_fallen = true
	var fx := FireFX.of(self)
	var along := Quaternion(_fall_axis, TOPPLE_ANGLE) * Vector3.UP
	var tall := height * 0.62
	for k in 12:
		var p := global_position + along * tall * randf() + Vector3.UP * 0.3
		fx.smoke(p, Vector3(randf_range(-1.5, 1.5), randf_range(0.8, 2.0), randf_range(-1.5, 1.5)), randf_range(2.0, 3.5), 0.8, 3.2, 0.2, 1.2)
	for k in 10:
		var p := global_position + along * tall * randf() + Vector3.UP * 0.3
		fx.flame(p, Vector3(randf_range(-2, 2), randf_range(2.0, 4.5), randf_range(-2, 2)), randf_range(0.25, 0.5), 0.15, 0.35, -6.0, 0.5)
	fell.emit(self)
	var level := _level()
	if level:
		level.clear_obstacle()


## Lying on the ground, a thin smoke for a while.
func _smouldering(delta: float) -> void:
	burn_t += delta
	if not _fallen:
		return
	if burn_t > _fall_at + 25.0:
		set_physics_process(false)
		return
	_smoke += delta * 0.8
	while _smoke >= 1.0:
		_smoke -= 1.0
		var along := Quaternion(_fall_axis, TOPPLE_ANGLE) * Vector3.UP
		var p := global_position + along * height * 0.62 * randf() + Vector3.UP * 0.4
		FireFX.of(self).smoke(p, Vector3(0.0, 1.0, 0.0) + WIND * 0.5, randf_range(3.0, 5.0), 0.6, 2.4)


## A random point in the canopy (`spread`: share of its size).
func _canopy_point(spread: float) -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	while v.length_squared() > 1.0:
		v = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	v *= spread
	return global_position + Vector3(v.x * canopy_radius * 0.8, height * 0.66 + v.y * height * 0.24, v.z * canopy_radius * 0.8)


func _level() -> LevelBuilder:
	var n := get_parent()
	while n and not n is LevelBuilder:
		n = n.get_parent()
	return n as LevelBuilder
