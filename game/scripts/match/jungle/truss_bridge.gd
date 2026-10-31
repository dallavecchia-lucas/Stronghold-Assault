class_name TrussBridge
extends StaticBody3D
## A steel through-truss road bridge over a river (the Jungle Keep's bridge sites): a deck between two
## Pratt trusses, braced overhead, on concrete abutments in the banks and, over a long span, a pier
## in mid-river. Real proportions: a panel every PANEL metres, the trusses about a ninth of the span
## tall (5.5-8 m: the War Elephant and the Giraffe walk under the bracing), the deck two lanes wide.
##
## Its length runs along local x, centred on its origin; the deck's top is DECK_TOP, flush with the
## flattened banks either end. Colliders: the deck, and a wall along each side so units stay on it.

const PANEL := 5.5
const DECK_TOP := 0.05
const DECK_THICK := 0.55
const STEEL := Color(0.31, 0.34, 0.27)

var length := 60.0
var width := 10.0


func setup(p_length: float, p_width: float) -> void:
	length = p_length
	width = p_width
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = 0
	name = "Bridge"
	_build()


func _build() -> void:
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var concrete := SurfaceTool.new()
	concrete.begin(Mesh.PRIMITIVE_TRIANGLES)

	var L := length
	var hz := width * 0.5 + 0.45
	var panels := maxi(int(round(L / PANEL)), 4)
	if panels % 2 == 1:
		panels += 1
	var p := L / panels
	var top := clampf(L / 9.0, 5.5, 8.0)
	var y0 := DECK_TOP + 0.35
	# The deck slab with a curb along each side, and the floor beams under it.
	_box(deck, Vector3(0, DECK_TOP - DECK_THICK * 0.5, 0), Vector3(L + 1.0, DECK_THICK, width + 1.4))
	for s in [-1.0, 1.0]:
		_box(concrete, Vector3(0, DECK_TOP + 0.12, s * (width * 0.5 - 0.2)), Vector3(L, 0.24, 0.4))
	for k in panels + 1:
		var x := -L * 0.5 + k * p
		_box(steel, Vector3(x, DECK_TOP - DECK_THICK - 0.35, 0), Vector3(0.4, 0.7, hz * 2.0 + 0.3))
	for s in [-1.0, 1.0]:
		var z: float = s * hz
		# Chords, end posts, verticals and diagonals.
		_box(steel, Vector3(0, y0, z), Vector3(L, 0.6, 0.5))
		_box(steel, Vector3(0, top, z), Vector3(L - 2.0 * p, 0.62, 0.62))
		_beam(steel, Vector3(-L * 0.5, y0, z), Vector3(-L * 0.5 + p, top, z), 0.6)
		_beam(steel, Vector3(L * 0.5, y0, z), Vector3(L * 0.5 - p, top, z), 0.6)
		for k in range(1, panels):
			var x := -L * 0.5 + k * p
			_beam(steel, Vector3(x, y0, z), Vector3(x, top, z), 0.34)
		for k in range(1, panels - 1):
			var xa := -L * 0.5 + k * p
			var xb := xa + p
			# Pratt: each diagonal slopes down toward the middle.
			if xb <= 0.001:
				_beam(steel, Vector3(xa, top, z), Vector3(xb, y0, z), 0.3)
			else:
				_beam(steel, Vector3(xa, y0, z), Vector3(xb, top, z), 0.3)
	# Overhead: struts across at every top panel point, X-bracing between them, portals at the ends.
	for k in range(1, panels):
		var x := -L * 0.5 + k * p
		_box(steel, Vector3(x, top, 0), Vector3(0.36, 0.45, hz * 2.0))
		if k < panels - 1:
			_beam(steel, Vector3(x, top + 0.1, -hz), Vector3(x + p, top + 0.1, hz), 0.16)
			_beam(steel, Vector3(x, top + 0.1, hz), Vector3(x + p, top + 0.1, -hz), 0.16)
	for e in [-1.0, 1.0]:
		var x: float = e * (L * 0.5 - p)
		_box(steel, Vector3(x, top - 0.9, 0), Vector3(0.4, 1.0, hz * 2.0))
		for s in [-1.0, 1.0]:
			_beam(steel, Vector3(x, top - 1.4, s * (hz - 1.6)), Vector3(x, top - 2.6, s * hz), 0.22)
	# Abutments in the banks, and a pier in the river under a long span.
	for e in [-1.0, 1.0]:
		_box(concrete, Vector3(e * (L * 0.5 - 1.0), -2.2, 0), Vector3(3.0, 4.6, width + 3.0))
		_box(concrete, Vector3(e * (L * 0.5 - 1.0), -1.0, 0), Vector3(3.6, 0.5, width + 3.6))
	if L > 50.0:
		_box(concrete, Vector3(0, -3.6, 0), Vector3(2.6, 6.0, width + 2.4))
		_box(concrete, Vector3(0, -0.9, 0), Vector3(3.2, 0.6, width + 3.0))

	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = STEEL
	steel_mat.metallic = 0.55
	steel_mat.roughness = 0.5
	for pair in [[steel, steel_mat], [deck, Mats.dark_stone()], [concrete, Mats.stone()]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = pair[1]
		add_child(mi)

	# Colliders: the deck, and a wall along each side (the trusses' bottom chords and the curbs).
	_collider(Vector3(0, DECK_TOP - DECK_THICK * 0.5, 0), Vector3(L + 1.0, DECK_THICK, width + 1.4))
	for s in [-1.0, 1.0]:
		_collider(Vector3(0, DECK_TOP + 0.9, s * hz), Vector3(L - 1.0, 1.8, 0.6))


func _collider(at: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = at
	add_child(cs)


## A box beam from a to b, `t` thick.
func _beam(st: SurfaceTool, a: Vector3, b: Vector3, t: float) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_box_xf(st, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(t, d.length(), t))


func _box(st: SurfaceTool, at: Vector3, size: Vector3) -> void:
	_box_xf(st, Transform3D(Basis.IDENTITY, at), size)


## A box (UVs in metres, for the triplanar-free materials' noise to keep its scale).
func _box_xf(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var su := absf(u.dot(h))
		var sv := absf(v.dot(h))
		var corners := [c - u * su - v * sv, c + u * su - v * sv, c + u * su + v * sv, c - u * su + v * sv]
		var uvs := [Vector2(0, sv * 2), Vector2(su * 2, sv * 2), Vector2(su * 2, 0), Vector2(0, 0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uvs[k])
			st.add_vertex(xf * corners[k])
