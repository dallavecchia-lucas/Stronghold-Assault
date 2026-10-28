class_name InfiltratorTrooper
extends SquadTrooper
## One trooper of an Infiltrator Squad (InfiltratorSquad): the Harpy Vanguard in her training kit, a
## recurve bow in her left hand. Walks and aims like every squad trooper (SquadTrooper); the squad says
## when to loose (trigger).
##
## The bow is silent (Arrow): no tracer and no flash, so the attacking player only sees their units'
## health running down. After each arrow she draws the next for DRAW_TIME.
##
## Low profile (passive): attackers never pick her out on their own (Combat.low_profile), only when
## the attacking player orders an attack on her. Under the squad's adaptive camo (set_camo) she is
## untargetable by basic attacks: she leaves the defenders' physics layer (shots pass through her,
## clicks don't find her) and orders to attack her lapse (Combat.targetable); on the attacker's side
## she, her bow and her arrow don't show at all. Splash damage still finds her (Combat.damage_area).
##
## The rigged model's clips come from tools/rig/rig_infiltrator.py: an archer's stance, the bow held
## out on the aim and the string drawn to the right cheek. InfiltratorRig finds the bow's grip (`bow`)
## and the string fingers (`nock`); the bow, its string and the nocked arrow are built here.

const MODEL := "res://assets/defenders/harpy_vanguard/infiltrator_rigged.glb"
const MAX_HP := 240.0
## Seconds to draw the next arrow, its damage, speed (m/s) and reach (m).
const DRAW_TIME := 1.3
const ARROW_DAMAGE := 34.0
const ARROW_SPEED := 70.0
const RANGE := 90.0
## She looses only with the bow within this of the way to the aim.
const AIM_TOLERANCE := deg_to_rad(25.0)
## The bow, in the `bow` bone's frame (Y up the bow, Z toward the target): half its length tip to
## tip, how far back its tips sweep, and its limbs' width and thickness at the grip and the tips.
const BOW_HALF := 0.66
const BOW_DEPTH := 0.15
const LIMB_WIDTH := Vector2(0.034, 0.014)
const LIMB_THICK := Vector2(0.026, 0.012)
var low_profile := true
var camouflaged := false
## Not drawn: under camo, on the attacker's side.
var hidden := false
var trigger := false
## 0 just after an arrow leaves, 1 drawn and ready.
var draw := 1.0
## Arrows loosed and hits (the showcase and the autotest count them).
var stats := {"arrows": 0, "hits": 0}

var _bow_node: MeshInstance3D
var _string: ImmediateMesh
var _string_mi: MeshInstance3D
var _held: MeshInstance3D

static var _bow_mesh: ArrayMesh


func _init() -> void:
	max_hp = MAX_HP
	hp = MAX_HP
	station_kind = "infiltrator"


func _model_path() -> String:
	return MODEL


func _new_rig() -> TrooperRig:
	return InfiltratorRig.new()


func _build_weapon() -> void:
	var rig := _rig as InfiltratorRig
	rig.on_posed = _string_bow
	_bow_node = MeshInstance3D.new()
	_bow_node.mesh = _make_bow()
	_bow_node.top_level = true
	_bow_node.visible = false
	add_child(_bow_node)
	_string = ImmediateMesh.new()
	_string_mi = MeshInstance3D.new()
	_string_mi.mesh = _string
	_string_mi.material_override = Mats.unshaded(Color(0.82, 0.8, 0.74))
	_string_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_string_mi.top_level = true
	add_child(_string_mi)
	_held = MeshInstance3D.new()
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.012, 0.012, Arrow.LENGTH)
	shaft.material = Mats.flat(Color(0.16, 0.13, 0.1), 0.0, 0.8)
	_held.mesh = shaft
	_held.top_level = true
	_held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held.visible = false
	add_child(_held)


func _weapon_down() -> void:
	trigger = false
	_held.visible = false


## The squad's adaptive camo: on, she can't be targeted by basic attacks (see the class notes);
## `unseen`: she isn't drawn at all, nor her shadow (the attacker's view; the defender sees her as ever).
func set_camo(on: bool, unseen: bool) -> void:
	camouflaged = on
	hidden = on and unseen
	if hp > 0.0:
		collision_layer = 0 if on else GameConfig.LAYER_DEFENDERS
	_model.visible = not hidden
	if hidden:
		_bow_node.visible = false
		_string_mi.visible = false
		_held.visible = false


## The bow's grip in the world (Z toward the target), once the rig has posed it.
func grip() -> Transform3D:
	return (_rig as InfiltratorRig).bow()


func _weapon_tick(delta: float) -> void:
	draw = minf(draw + delta / DRAW_TIME, 1.0)
	if trigger and draw >= 1.0 and _on_aim():
		_loose()


## Where she aims: the aim point, or (looking the way the camera looks) far down that way; never
## past RANGE.
func _target(from: Vector3) -> Vector3:
	var to := aim_point if not aim_parallel else from + aim_dir.normalized() * RANGE
	return from + (to - from).limit_length(RANGE)


func _on_aim() -> bool:
	var rig := _rig as InfiltratorRig
	if not rig.posed():
		return false
	var xf := rig.bow()
	return xf.basis.z.normalized().angle_to(_target(xf.origin) - xf.origin) <= AIM_TOLERANCE


func _loose() -> void:
	draw = 0.0
	var xf := grip()
	var from := xf.origin + xf.basis.z.normalized() * 0.1
	var arrow := Arrow.new()
	arrow.team = team
	arrow.damage = ARROW_DAMAGE
	arrow.exclude = exclude
	arrow.on_hit = func(_u): stats.hits += 1
	get_tree().current_scene.add_child(arrow)
	arrow.launch(from, _target(from), ARROW_SPEED)
	stats.arrows += 1


## Every frame once the rig has posed the hands: the bow on the grip, the string from tip to tip
## through the string fingers (as far back as the draw has come), the next arrow on it.
func _string_bow() -> void:
	if hidden or hp <= 0.0 and _model.position.y < -0.5:
		_bow_node.visible = false
		_held.visible = false
		_string_mi.visible = false
		return
	var rig := _rig as InfiltratorRig
	var xf := rig.bow()
	_bow_node.global_transform = xf
	_bow_node.visible = true
	_string_mi.visible = true
	var top := xf * Vector3(0.0, BOW_HALF, -BOW_DEPTH)
	var bottom := xf * Vector3(0.0, -BOW_HALF, -BOW_DEPTH)
	var rest := (top + bottom) * 0.5
	var pull := smoothstep(0.0, 1.0, draw)
	var mid := rest.lerp(rig.nock().origin, pull)
	_string.clear_surfaces()
	_string.surface_begin(Mesh.PRIMITIVE_LINES)
	_string.surface_add_vertex(top)
	_string.surface_add_vertex(mid)
	_string.surface_add_vertex(mid)
	_string.surface_add_vertex(bottom)
	_string.surface_end()
	# The next arrow is on the string once it is a quarter drawn, its head out past the grip.
	_held.visible = draw > 0.25 and hp > 0.0
	if _held.visible:
		var way := xf.origin - mid
		if way.length() > 0.05:
			var up := Vector3.UP if absf(way.normalized().y) < 0.98 else Vector3.FORWARD
			_held.global_transform = Transform3D(Basis.looking_at(way, up), mid + way.normalized() * Arrow.LENGTH * 0.5)


## The bow, in its bone's frame: two limbs from the grip, tapering and sweeping back toward the archer
## (-Z) to the tips, a thicker grip between them. One mesh for every bow.
static func _make_bow() -> ArrayMesh:
	if _bow_mesh:
		return _bow_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 24
	var rings: Array = []
	for k in steps + 1:
		var s := -1.0 + 2.0 * k / steps
		var a := absf(s)
		var grip_f := 1.0 - smoothstep(0.08, 0.16, a)
		var w := lerpf(LIMB_WIDTH.x, LIMB_WIDTH.y, a) + grip_f * 0.012
		var t := lerpf(LIMB_THICK.x, LIMB_THICK.y, a) + grip_f * 0.022
		var c := Vector3(0.0, s * BOW_HALF, -BOW_DEPTH * s * s)
		# Across the limb (x) and through it (along the curve's normal in the y-z plane).
		var along := Vector3(0.0, BOW_HALF, -2.0 * BOW_DEPTH * s).normalized()
		var thru := Vector3(1, 0, 0).cross(along).normalized()
		rings.append([c + Vector3(w, 0, 0) * 0.5 + thru * t * 0.5, c - Vector3(w, 0, 0) * 0.5 + thru * t * 0.5,
				c - Vector3(w, 0, 0) * 0.5 - thru * t * 0.5, c + Vector3(w, 0, 0) * 0.5 - thru * t * 0.5])
	for k in steps:
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for f in 4:
			var g := (f + 1) % 4
			for v: Vector3 in [r0[f], r1[f], r1[g], r0[f], r1[g], r0[g]]:
				st.add_vertex(v)
	st.generate_normals()
	# Seen from both sides, whichever way the faces wind.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.11)
	mat.metallic = 0.3
	mat.roughness = 0.55
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	_bow_mesh = st.commit()
	return _bow_mesh
