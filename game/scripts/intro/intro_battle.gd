class_name IntroBattle
extends Node3D
## The last-stand battle at the end of the intro: the alien horde marches out of the
## citadel, the animal army charges off the ridge, the lines clash, walkers fall and the
## citadel burns. Everything is a pure function of battle time `bt`, which runs slower
## than real time during the slow-motion beats, so any frame can be rendered on its own.

const TROOPER_ROWS := 10
const TROOPER_COLS := 18
const ALIEN_SPEED := 7.0
const CLASH := 160.0
const CHARGE := 152.0
# battle-time values for real-time beats (slow motion shifts them):
# surge at real 182 s, victory at real 192 s
const SURGE := 171.72
const VICTORY := 181.7
const EAGLE_HIT := 167.8
const TRACER_SLOTS := 90
const EARTH_TRACER := Color(1.0, 0.8, 0.35)
const ALIEN_TRACER := Color(1.0, 0.15, 0.25)

## Slow motion: [real start, real end, speed]
const WARPS := [[160.0, 166.0, 0.22], [174.0, 182.0, 0.3]]

var ridge_z := -400.0
var ridge_front := -435.0
var citadel: Vector3
var citadel_ring: Node3D

## [node, start Vector3, engage Vector3, speed, flying, charges]
var _army: Array = []
var _hero_bear: Node3D
var _troopers: Array = []  # dicts: start, engage, die
var _mm := {}  # part name -> MultiMesh
var _parts := {}  # part name -> local Transform3D
var _walkers: Array = []  # dicts: node, start, die
var _blasts: Array = []  # dicts: t, pos, size, nodes...
var _tracers: Array = []
var _shells: Array = []  # dicts: t, from, to, node
var _rng := RandomNumberGenerator.new()


static func battle_time(t: float) -> float:
	## Real time -> battle time, with slow-motion segments.
	var bt := t
	for w in WARPS:
		if t > w[0]:
			bt -= (minf(t, w[1]) - w[0]) * (1.0 - w[2])
	return bt


static func time_rate(t: float) -> float:
	for w in WARPS:
		if t >= w[0] and t < w[1]:
			return w[2]
	return 1.0


func terrain_y(z: float) -> float:
	if z > ridge_front:
		return 8.0
	return lerpf(0.0, 8.0, clampf((z - (ridge_front - 25.0)) / 25.0, 0.0, 1.0))


# ================================================================ setup

func setup(army: Array, p_citadel: Vector3, ring: Node3D) -> void:
	_rng.seed = 300
	citadel = p_citadel
	citadel_ring = ring
	_build_slope()
	for entry in army:
		var node: Node3D = entry[0]
		var flying: bool = entry[1]
		var charges: bool = entry[2]
		var start := node.position
		var lane := start.x
		var engage := Vector3(lane * 0.9, 0, -503.0 + (start.z - ridge_z) * 0.25 + _rng.randf_range(-3, 3))
		var speed := _rng.randf_range(12.0, 16.0)
		_army.append([node, start, engage, speed, flying, charges])
		if _hero_bear == null and node.has_meta("hero"):
			_hero_bear = node
	_build_troopers()
	_build_walkers()
	_build_blasts()
	_build_tracers()
	_build_shells()


func hero_position(bt: float) -> Vector3:
	for a in _army:
		if a[0] == _hero_bear:
			return _army_pos(a, bt)
	return Vector3(0, 0, -508)


func _build_slope() -> void:
	var run := 25.0
	var rise := 8.0
	var length := sqrt(run * run + rise * rise)
	var slope := Mats.box_mesh(Vector3(260, 1.0, length), Vector3(0, rise * 0.5 - 0.5, ridge_front - run * 0.5), Mats.dark_stone())
	slope.rotation.x = -atan2(rise, run)
	add_child(slope)


func _part_mesh(name: String, mesh: Mesh, mat: Material, local: Transform3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = TROOPER_ROWS * TROOPER_COLS
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	_mm[name] = mm
	_parts[name] = local


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_troopers() -> void:
	var chrome := Mats.flat(Color(0.09, 0.09, 0.11), 0.95, 0.22)
	var red := Mats.glow(Color(1.0, 0.1, 0.12), 7.0)
	_part_mesh("torso", _box(Vector3(0.62, 1.0, 0.38)), chrome, Transform3D(Basis(), Vector3(0, 1.75, 0)))
	_part_mesh("head", _box(Vector3(0.3, 0.42, 0.55)), chrome, Transform3D(Basis.from_euler(Vector3(0.25, 0, 0)), Vector3(0, 2.45, -0.05)))
	_part_mesh("visor", _box(Vector3(0.34, 0.07, 0.06)), red, Transform3D(Basis(), Vector3(0, 2.48, -0.32)))
	_part_mesh("gun", _box(Vector3(0.12, 0.14, 1.1)), chrome, Transform3D(Basis(), Vector3(0.38, 1.6, -0.45)))
	_part_mesh("core", _box(Vector3(0.2, 0.2, 0.05)), red, Transform3D(Basis(), Vector3(0, 1.85, -0.2)))
	_part_mesh("spikes", _box(Vector3(1.1, 0.12, 0.2)), chrome, Transform3D(Basis.from_euler(Vector3(0, 0, 0)), Vector3(0, 2.2, 0.05)))
	_part_mesh("leg_l", _box(Vector3(0.16, 1.3, 0.16)), chrome, Transform3D(Basis(), Vector3(-0.18, -0.65, 0)))
	_part_mesh("leg_r", _box(Vector3(0.16, 1.3, 0.16)), chrome, Transform3D(Basis(), Vector3(0.18, -0.65, 0)))
	for r in TROOPER_ROWS:
		for c in TROOPER_COLS:
			var x := (c - (TROOPER_COLS - 1) * 0.5) * 3.4 + _rng.randf_range(-0.6, 0.6)
			var z := -652.0 - r * 3.2 + _rng.randf_range(-0.5, 0.5)
			var engage_z := -514.0 - r * 2.6 + _rng.randf_range(-1.5, 1.5)
			var die := CLASH + 0.6 + r * 2.2 + _rng.randf_range(0.0, 5.0)
			if r >= TROOPER_ROWS - 3:
				die = SURGE + _rng.randf_range(0.5, 9.0)  # back ranks fall to the final surge
			_troopers.append({"start": Vector3(x, 0, z), "engage_z": engage_z, "die": die,
					"push": _rng.randf_range(2.5, 6.0), "phase": _rng.randf() * TAU})


func _trooper_xform(tr: Dictionary, bt: float) -> Array:
	## Returns [body transform, leg swing angle, alive]
	var start: Vector3 = tr.start
	var z: float = minf(start.z + ALIEN_SPEED * maxf(bt - 138.0, 0.0), tr.engage_z)
	if bt > SURGE:
		z = tr.engage_z  # hold the line until they fall
	var pos := Vector3(start.x, 0, z)
	var marching: bool = z < tr.engage_z - 0.01
	var swing := sin(bt * 7.0 + tr.phase) * 0.5 if marching else sin(bt * 2.0 + tr.phase) * 0.1
	var basis := Basis.from_euler(Vector3(0, PI, 0))  # face the animals (+Z)
	var alive: bool = bt < tr.die
	if not alive:
		var age: float = bt - tr.die
		var k := clampf(age / 0.6, 0.0, 1.0)
		pos.z -= tr.push * k
		pos.y = sin(k * PI) * 1.2 - clampf((age - 2.0) / 3.0, 0.0, 1.0) * 3.0
		basis = Basis.from_euler(Vector3(-k * 1.4, PI, k * 0.4))
		swing = 0.0
	else:
		pos.y = absf(sin(bt * 7.0 + tr.phase)) * 0.1 if marching else 0.0
	return [Transform3D(basis, pos), swing, alive]


func _build_walkers() -> void:
	var chrome := Mats.flat(Color(0.07, 0.07, 0.09), 0.95, 0.25)
	var red := Mats.glow(Color(1.0, 0.1, 0.1), 8.0)
	for spec in [[Vector3(-42, 0, -600), EAGLE_HIT], [Vector3(46, 0, -620), 175.7], [Vector3(5, 0, -690), 179.4]]:
		var w := Node3D.new()
		var body := Node3D.new()
		body.position.y = 17.0
		w.add_child(body)
		body.add_child(Mats.box_mesh(Vector3(9, 3.2, 13), Vector3.ZERO, chrome))
		body.add_child(Mats.box_mesh(Vector3(5, 2.2, 5), Vector3(0, 0.6, 7.5), chrome))
		body.add_child(Mats.box_mesh(Vector3(3.6, 0.5, 0.3), Vector3(0, 0.8, 10.1), red))
		body.add_child(Mats.box_mesh(Vector3(0.6, 0.6, 9), Vector3(-3.2, -1.6, 7.0), chrome))
		body.add_child(Mats.box_mesh(Vector3(0.6, 0.6, 9), Vector3(3.2, -1.6, 7.0), chrome))
		for k in 3:
			var a := k * TAU / 3.0 + 0.5
			var leg := Mats.cylinder_mesh(0.7, 20.0, Vector3(cos(a) * 6.0, -7.5, sin(a) * 6.0), chrome, 6)
			leg.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
			body.add_child(leg)
		w.position = spec[0]
		add_child(w)
		_walkers.append({"node": w, "body": body, "start": spec[0], "die": spec[1]})


func walker_pos(w: Dictionary, bt: float) -> Vector3:
	return w.start + Vector3(0, 0, minf(clampf(bt - 140.0, 0.0, 40.0) * 1.4, 45.0))


func _build_blasts() -> void:
	# scripted: shells, the eagle strike, walker kills, the citadel
	var list := []
	for i in 7:
		list.append([164.6 + i * 0.45, Vector3(_rng.randf_range(-40, 40), 1, _rng.randf_range(-560, -530)), 7.0])
	for w in _walkers:
		list.append([w.die, walker_pos(w, w.die) + Vector3(0, 17, 0), 14.0])
	# artillery muzzle flashes on the ridge (shells land 3 s later)
	for i in 7:
		list.append([164.6 + i * 0.45 - 3.0, _muzzle(i), 2.5])
	list.append([179.1, citadel + Vector3(0, 130, 0), 70.0])
	list.append([179.6, citadel + Vector3(-60, 90, 20), 40.0])
	list.append([180.1, citadel + Vector3(55, 70, 10), 45.0])
	# random battlefield blasts during the fight
	for i in 34:
		var bt := _rng.randf_range(CLASH, VICTORY)
		list.append([bt, Vector3(_rng.randf_range(-55, 55), 0.5, _rng.randf_range(-560, -505)), _rng.randf_range(3.0, 6.5)])
	var flash := StandardMaterial3D.new()
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.albedo_color = Color(0.85, 0.36, 0.1)
	for b in list:
		var fire := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 12
		sm.rings = 6
		fire.mesh = sm
		fire.material_override = flash
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.visible = false
		add_child(fire)
		var smoke := MeshInstance3D.new()
		smoke.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.16, 0.13, 0.11, 0.0)
		smoke.material_override = smat
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.visible = false
		add_child(smoke)
		var light: OmniLight3D = null
		if b[2] >= 7.0:
			light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.25)
			light.omni_range = b[2] * 4.0
			light.visible = false
			add_child(light)
		_blasts.append({"t": b[0], "pos": b[1], "size": b[2], "fire": fire, "smoke": smoke, "smat": smat, "light": light})


func _build_tracers() -> void:
	for i in TRACER_SLOTS:
		var mi := MeshInstance3D.new()
		mi.mesh = _box(Vector3(0.06, 0.06, 3.0))
		var earth := i % 3 != 0
		mi.material_override = Mats.glow(EARTH_TRACER if earth else ALIEN_TRACER, 6.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append({"node": mi, "earth": earth, "period": _rng.randf_range(0.45, 0.9), "phase": _rng.randf(),
				"seed": _rng.randi()})


func _muzzle(i: int) -> Vector3:
	return Vector3(-30.0 if i % 2 == 0 else 30.0, 10.5, -400.0)


func _build_shells() -> void:
	var mat := Mats.glow(Color(1.0, 0.7, 0.3), 5.0)
	for i in 7:
		var land: Vector3 = _blasts[i].pos
		var from := _muzzle(i)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.1
		sm.height = 2.2
		mi.mesh = sm
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_shells.append({"t": _blasts[i].t, "from": from, "to": land, "node": mi})


# ================================================================ per frame

func update(t: float) -> void:
	var bt := battle_time(t)
	visible = t > 136.0
	_update_army(bt)
	_update_troopers(bt)
	_update_walkers(bt)
	_update_blasts(bt)
	_update_tracers(bt)
	_update_shells(bt)
	_update_citadel(bt)


func _army_pos(a: Array, bt: float) -> Vector3:
	var start: Vector3 = a[1]
	var engage: Vector3 = a[2]
	if not a[5]:
		return start  # artillery holds the ridge
	var pos := start
	if bt > CHARGE:
		var d: float = (bt - CHARGE) * a[3]
		var to := engage - Vector3(start.x, 0, start.z)
		var total := Vector2(to.x, to.z).length()
		var k := minf(d / maxf(total, 0.01), 1.0)
		pos = Vector3(lerpf(start.x, engage.x, k), 0, lerpf(start.z, engage.z, k))
	if bt > SURGE:
		pos.z -= minf((bt - SURGE) * 6.0, 80.0)
	pos.y = terrain_y(pos.z)
	if a[4]:
		pos.y = start.y
	return pos


func _update_army(bt: float) -> void:
	for a in _army:
		var node: Node3D = a[0]
		var pos := _army_pos(a, bt)
		var moving: bool = a[5] and ((bt > CHARGE and bt < CHARGE + 8.0) or (bt > SURGE and bt < SURGE + 13.0))
		if moving and not a[4]:
			pos.y += absf(sin(bt * 9.0 + pos.x)) * 0.25
		if a[4]:
			# eagles: circle, then dive on the first walker
			var w: Dictionary = _walkers[0]
			var target: Vector3 = walker_pos(w, EAGLE_HIT) + Vector3(0, 18, 0)
			var dive := smoothstep(EAGLE_HIT - 2.0, EAGLE_HIT, bt) * (1.0 - smoothstep(EAGLE_HIT + 0.2, EAGLE_HIT + 2.5, bt))
			var circle := Vector3(cos(bt * 0.8 + pos.x) * 8.0, sin(bt * 1.4 + pos.x) * 0.6, sin(bt * 0.8 + pos.x) * 8.0)
			var base := Vector3(pos.x * 0.6, pos.y + 6.0, lerpf(-420.0, -520.0, smoothstep(CHARGE, CLASH + 6.0, bt)))
			pos = (base + circle).lerp(target + Vector3(pos.x * 0.15, 0, 0), dive)
		node.position = pos
		node.rotation.x = -0.12 if moving else 0.0


func _update_troopers(bt: float) -> void:
	var idx := 0
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for tr in _troopers:
		var info := _trooper_xform(tr, bt)
		var body: Transform3D = info[0]
		var gone: bool = bt > tr.die + 5.0
		for part in _mm:
			var local: Transform3D = _parts[part]
			if part == "leg_l" or part == "leg_r":
				var sw: float = info[1] * (1.0 if part == "leg_l" else -1.0)
				local = Transform3D(Basis.from_euler(Vector3(sw, 0, 0)), Vector3(local.origin.x, 1.3, 0)) * Transform3D(Basis(), Vector3(0, -0.65, 0))
			_mm[part].set_instance_transform(idx, hidden if gone else body * local)
		idx += 1


func _update_walkers(bt: float) -> void:
	for w in _walkers:
		var node: Node3D = w.node
		var start: Vector3 = w.start
		node.position = walker_pos(w, minf(bt, w.die))
		var body: Node3D = w.body
		body.position.y = 17.0 + sin(bt * 1.6) * 0.4
		if bt > w.die:
			var k: float = clampf((bt - w.die) / 2.5, 0.0, 1.0)
			node.rotation = Vector3(-k * k * 1.3, 0, k * 0.3)
			node.position.y = -k * k * 6.0
		else:
			node.rotation = Vector3.ZERO
		node.visible = bt < w.die + 12.0


func _update_blasts(bt: float) -> void:
	for b in _blasts:
		var age: float = bt - b.t
		var on := age >= 0.0 and age < 6.0
		var fire: MeshInstance3D = b.fire
		var smoke: MeshInstance3D = b.smoke
		fire.visible = on and age < 0.9
		smoke.visible = on
		if b.light:
			b.light.visible = on and age < 1.2
		if not on:
			continue
		var s: float = b.size
		fire.global_position = b.pos
		fire.scale = Vector3.ONE * s * (0.3 + 0.7 * smoothstep(0.0, 0.25, age)) * (1.0 - smoothstep(0.4, 0.9, age) * 0.8)
		smoke.global_position = b.pos + Vector3.UP * age * s * 0.25
		smoke.scale = Vector3.ONE * s * (0.6 + age * 0.35)
		b.smat.albedo_color.a = 0.75 * smoothstep(0.1, 0.5, age) * (1.0 - smoothstep(3.0, 6.0, age))
		if b.light:
			b.light.global_position = b.pos + Vector3.UP * 2.0
			b.light.light_energy = 10.0 * (1.0 - age / 1.2)


func _update_tracers(bt: float) -> void:
	var fighting := bt > CLASH - 1.0 and bt < VICTORY - 1.0
	var live_aliens := []
	if fighting:
		for tr in _troopers:
			if bt < tr.die:
				live_aliens.append(tr)
	for s in _tracers:
		var node: MeshInstance3D = s.node
		if not fighting or live_aliens.is_empty():
			node.visible = false
			continue
		var cycle: float = (bt / s.period) + s.phase
		var n := int(floor(cycle))
		var k: float = cycle - n
		var flight: float = 0.18 / s.period
		if k > flight:
			node.visible = false
			continue
		var r := RandomNumberGenerator.new()
		r.seed = s.seed + n * 7919
		var a: Array = _army[r.randi() % _army.size()]
		var alien: Dictionary = live_aliens[r.randi() % live_aliens.size()]
		var ap: Vector3 = (a[0] as Node3D).position + Vector3.UP * 1.5
		var xp: Vector3 = (_trooper_xform(alien, bt)[0] as Transform3D).origin + Vector3.UP * 1.8
		var from := ap if s.earth else xp
		var to := xp if s.earth else ap
		var u: float = k / flight
		var dir := (to - from).normalized()
		node.visible = true
		node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from.lerp(to, u))


func _update_shells(bt: float) -> void:
	for sh in _shells:
		var node: MeshInstance3D = sh.node
		var flight := 3.0
		var u: float = (bt - (sh.t - flight)) / flight
		node.visible = u >= 0.0 and u < 1.0
		if node.visible:
			var from: Vector3 = sh.from
			var to: Vector3 = sh.to
			node.global_position = from.lerp(to, u) + Vector3.UP * 45.0 * 4.0 * u * (1.0 - u)


func _update_citadel(bt: float) -> void:
	if citadel_ring == null:
		return
	var k := clampf((bt - 179.1) / 4.0, 0.0, 1.0)
	citadel_ring.position = citadel + Vector3(0, 130.0 - k * k * 120.0, 0)
	citadel_ring.rotation.x = 0.12 + k * 0.9
