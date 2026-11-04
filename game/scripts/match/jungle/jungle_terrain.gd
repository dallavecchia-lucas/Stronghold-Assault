class_name JungleTerrain
extends Node3D
## The Jungle Keep map's ground (JungleLayout gives its shape): a height grid every CELL metres out
## to HALF (past the map's edge, so the rivers run off it), drawn as CHUNK-sized meshes with a
## splat-mapped shader (forest floor, the clearing's grass, mud by the water, rock on the steep faces
## and the quarry's benches), a HeightMapShape3D for collision and one water plane at
## JungleLayout.WATER_Y that only shows where the land dips under it (the rivers and the lake): opaque
## and glossy, so it mirrors the forest (screen-space reflections, Forward+).
##
## The water can't be waded: the navmesh gets the same ground with all of it cut out (nav_faces()),
## and an invisible wall stands along the water's edge (_build_water_edge(), LAYER_WATER_EDGE) that every
## walker collides with, the player's soldier too, and nothing else does (shots, rays and the navmesh
## bake go through it). Where a bridge stands (FoldingBridge) the wall has a gap under it (cut_water_edge()).

const CELL := 2.0
const HALF := 880.0
## Quads per mesh chunk side (CHUNK * CELL m).
const CHUNK := 50
## Ground under water (or less than NAV_WET above it) is cut out of the navmesh, and so is the bank
## within NAV_SHORE cells of it.
const NAV_WET := 0.15
const NAV_SHORE := 1
## The water's edge wall stands where the ground is EDGE_UP above the water, from EDGE_WALL[0] to
## EDGE_WALL[1] relative to the water (m): well over a giraffe's head.
const EDGE_UP := 0.2
const EDGE_WALL := [-3.0, 9.0]

static var current: JungleTerrain

var n := 0
var heights := PackedFloat32Array()
## Per grid point: distance to the nearest river's centre (m), and that river's half width.
var river_d := PackedFloat32Array()
var river_hw := PackedFloat32Array()
var splat: Image
var material: ShaderMaterial
var body: StaticBody3D
var edge_body: StaticBody3D
## The water's edge wall as segments (two points each, x z), and its shape (rebuilt round the bridges).
var _edge_segs := PackedVector2Array()
var _edge_shape: ConcavePolygonShape3D


func build() -> void:
	current = self
	n = int(HALF * 2.0 / CELL) + 1
	var t0 := Time.get_ticks_msec()
	river_d = _distance_field(_river_segments(), true)
	var t1 := Time.get_ticks_msec()
	_heights()
	var t2 := Time.get_ticks_msec()
	_build_meshes()
	_build_collision()
	_build_water_edge()
	_build_water()
	print("JungleTerrain: %dx%d grid, fields %d ms, heights %d ms, meshes %d ms" % [n, n, t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])


## The ground's height at (x, z), bilinear between the grid points (0 off the grid).
func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / CELL
	var fz := (z + HALF) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= n - 1 or fz >= n - 1:
		return 0.0
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * n + i
	return lerpf(lerpf(heights[k], heights[k + 1], tx), lerpf(heights[k + n], heights[k + n + 1], tx), tz)


## The ground's normal at (x, z).
func normal_at(x: float, z: float) -> Vector3:
	var e := CELL
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


## True if (x, z) is under water (no one goes there: the rivers and the lake are too deep).
func wet(x: float, z: float) -> bool:
	return height_at(x, z) < JungleLayout.WATER_Y + NAV_WET


## Distance to the nearest river's centre (m), from the grid.
func river_distance(x: float, z: float) -> float:
	var i := clampi(int(round((x + HALF) / CELL)), 0, n - 1)
	var j := clampi(int(round((z + HALF) / CELL)), 0, n - 1)
	return river_d[j * n + i] - river_hw[j * n + i]


# ---------------------------------------------------------------- fields

func _river_segments() -> Array:
	var segs := []
	for r in JungleLayout.RIVERS:
		var c := JungleLayout.river_curve(r[0])
		for i in c.size() - 1:
			segs.append([c[i], c[i + 1], r[1] * 0.5])
	return segs


## Distance from every grid point to the nearest segment, out to a band round each (farther points
## keep a big number). With `rivers`, river_hw gets the half width of the river that is nearest.
func _distance_field(segs: Array, rivers: bool) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(n * n)
	d.fill(1.0e6)
	if rivers:
		river_hw.resize(n * n)
		river_hw.fill(20.0)
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var band: float = s[2] + JungleLayout.BANK + 24.0
		var i0 := clampi(int(floor((minf(a.x, b.x) - band + HALF) / CELL)), 0, n - 1)
		var i1 := clampi(int(ceil((maxf(a.x, b.x) + band + HALF) / CELL)), 0, n - 1)
		var j0 := clampi(int(floor((minf(a.y, b.y) - band + HALF) / CELL)), 0, n - 1)
		var j1 := clampi(int(ceil((maxf(a.y, b.y) + band + HALF) / CELL)), 0, n - 1)
		var ab := b - a
		var inv := 1.0 / maxf(ab.length_squared(), 1e-6)
		for j in range(j0, j1 + 1):
			var z := -HALF + j * CELL
			for i in range(i0, i1 + 1):
				var p := Vector2(-HALF + i * CELL, z)
				var t := clampf((p - a).dot(ab) * inv, 0.0, 1.0)
				var dist := p.distance_to(a + ab * t)
				var k := j * n + i
				if dist < d[k]:
					d[k] = dist
					if rivers:
						river_hw[k] = s[2]
	return d


func _heights() -> void:
	heights.resize(n * n)
	_prepare()
	_rows.resize(n)
	var task := WorkerThreadPool.add_group_task(_height_row, n, -1, true, "JungleTerrain heights")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for j in n:
		var row: Array = _rows[j]
		var hr: PackedFloat32Array = row[0]
		var sr: PackedByteArray = row[1]
		for i in n:
			heights[j * n + i] = hr[i]
		for b in n * 4:
			bytes[j * n * 4 + b] = sr[b]
	_rows.clear()
	_noise_a = PackedByteArray()
	_noise_b = PackedByteArray()
	splat = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes)


var _rows: Array = []
var _noise_a := PackedByteArray()
var _noise_b := PackedByteArray()


## The jungle floor's roll as two noise images over the grid (made natively in one go each: the rows
## below read them instead of calling the noise per point).
func _prepare() -> void:
	var a := FastNoiseLite.new()
	a.seed = 4127
	a.frequency = 0.004 * CELL
	a.fractal_octaves = 3
	var b := FastNoiseLite.new()
	b.seed = 911
	b.frequency = 0.02 * CELL
	b.fractal_octaves = 3
	_noise_a = a.get_image(n, n, false, false, false).get_data()
	_noise_b = b.get_image(n, n, false, false, false).get_data()


## One row of the grid (on a worker thread): heights and splat (r mud by the water, g the clearing's
## grass, b unused, a rock). JungleLayout's shapes, worked out inline: only built-in functions
## here, which run side by side on the worker threads (calls into scripts or objects would not).
func _height_row(j: int) -> void:
	var L := JungleLayout
	var flat_c := [L.MAIN_SPAWN, L.QUARRY, L.OUTPOST]
	var flat_r := [110.0, 75.0, 75.0]
	var rg_c := PackedVector2Array()
	var rg_r := PackedVector2Array()
	var rg_h := PackedFloat32Array()
	var rg_y := PackedFloat32Array()
	for rg in L.RIDGES:
		rg_c.append(rg[0])
		rg_r.append(rg[1])
		rg_h.append(rg[2])
		rg_y.append(rg[3])
	var pl_c: Vector2 = L.PLATEAU[0]
	var pl_r: Vector2 = L.PLATEAU[1]
	var pl_min := minf(pl_r.x, pl_r.y)
	var pl_ext := pl_r + Vector2.ONE * L.PLATEAU_RAMP * 1.6
	var cl_a := L.CLIFF_A
	var cl_span := L.CLIFF_B.x - L.CLIFF_A.x
	var cl_fade := L.CLIFF_FADE / cl_span
	var qh_c: Vector2 = L.QUARRY_HILL[0]
	var qh_r: Vector2 = L.QUARRY_HILL[1]
	var qh_h: float = L.QUARRY_HILL[2]
	var qc_c: Vector2 = L.QUARRY_CUT[0]
	var qc_r: Vector2 = L.QUARRY_CUT[1]
	var lk_c: Vector2 = L.LAKE[0]
	var lk_r: Vector2 = L.LAKE[1]
	var bank := L.BANK
	var clr := L.CLEARING_R
	var cle := L.CLEARING_EDGE
	var hw_row := river_hw.slice(j * n, j * n + n)
	var dr_row := river_d.slice(j * n, j * n + n)
	var na := _noise_a.slice(j * n, j * n + n)
	var nb := _noise_b.slice(j * n, j * n + n)
	var z := -HALF + j * CELL
	var hr := PackedFloat32Array()
	hr.resize(n)
	var sr := PackedByteArray()
	sr.resize(n * 4)
	for i in n:
		var p := Vector2(-HALF + i * CELL, z)
		var plen := p.length()
		# Flattened: the clearing and the sites.
		var flat := 1.0 - smoothstep(clr, clr + cle, plen)
		var grass := 1.0 - smoothstep(clr - 30.0, clr + cle * 0.7, plen)
		for f in 3:
			var fd := p.distance_to(flat_c[f])
			var fr: float = flat_r[f]
			if fd < fr:
				flat = maxf(flat, 1.0 - smoothstep(fr * 0.6, fr, fd))
				grass = maxf(grass, (1.0 - smoothstep(fr * 0.45, fr * 0.9, fd)) * 0.8)
		var land := 0.0
		if flat < 1.0:
			var relief := na[i] / 255.0
			var fine := nb[i] / 255.0
			# Level ground under the prison and its yard.
			var roll := (relief * 2.8 + fine * 0.7) * smoothstep(70.0, 125.0, p.distance_to(L.PRISON))
			# Ridges.
			var hills := 0.0
			for r in rg_c.size():
				var dv := (p - rg_c[r]).rotated(-rg_y[r])
				var rr := rg_r[r]
				var e := Vector2(dv.x / rr.x, dv.y / rr.y).length()
				if e < 1.6:
					var t := 1.0 - e / 1.6
					hills = maxf(hills, rg_h[r] * t * t * (3.0 - 2.0 * t))
			if hills > 0.0:
				hills += (fine - 0.5) * 2.0 * minf(hills * 0.2, 3.0)
			# The plateau and its cliff.
			var plat := 0.0
			var pd := p - pl_c
			if absf(pd.x) < pl_ext.x and absf(pd.y) < pl_ext.y:
				var e := Vector2(pd.x / pl_r.x, pd.y / pl_r.y).length()
				plat = L.PLATEAU_Y * (1.0 - smoothstep(0.0, L.PLATEAU_RAMP, (e - 1.0) * pl_min))
				if plat > 0.0:
					var along := (p.x - cl_a.x) / cl_span
					var inside := smoothstep(-cl_fade, 0.0, along) * (1.0 - smoothstep(1.0, 1.0 + cl_fade, along))
					if inside > 0.0:
						plat *= 1.0 - inside * smoothstep(cl_a.y - 1.5, cl_a.y + 3.0, p.y)
			# The quarry's hill and its benches.
			var quar := 0.0
			var qd := p - qh_c
			var qe := Vector2(qd.x / qh_r.x, qd.y / qh_r.y).length()
			if qe < 1.0:
				quar = qh_h * pow(minf((1.0 - qe) * 2.2, 1.0), 0.7)
				var qcd := p - qc_c
				var c := Vector2(qcd.x / qc_r.x, qcd.y / qc_r.y).length()
				if c < 1.0:
					var step := floorf(c * 4.0)
					quar = minf(quar, L.QUARRY_BENCH * (step + smoothstep(0.82, 1.0, c * 4.0 - step)))
			land = (maxf(maxf(plat, hills), quar) + roll) * (1.0 - flat)
		# The water: rivers and the lake.
		var hw := hw_row[i]
		var dr := dr_row[i]
		var ld := p - lk_c
		var le := Vector2(ld.x / lk_r.x, ld.y / lk_r.y).length()
		var carve := 1.0 - smoothstep(hw - 3.0, hw + bank, dr)
		carve = maxf(carve, 1.0 - smoothstep(0.85, 1.0 + bank / lk_r.x, le))
		var h := land
		if carve > 0.0:
			var bed := lerpf(L.LAKE_BED, L.RIVER_BED, clampf(le, 0.0, 1.0)) if le < 1.0 else L.RIVER_BED
			h = lerpf(land, bed, carve)
		hr[i] = h
		var shore := maxf(1.0 - smoothstep(hw, hw + bank + 7.0, dr), 1.0 - smoothstep(0.9, 1.25, le))
		var qcd2 := p - qc_c
		var rock := 1.0 - smoothstep(0.95, 1.05, Vector2(qcd2.x / qc_r.x, qcd2.y / qc_r.y).length())
		sr[i * 4] = int(pow(shore, 0.6) * 255.0)
		sr[i * 4 + 1] = int(grass * 255.0)
		sr[i * 4 + 2] = 0
		sr[i * 4 + 3] = int(rock * 255.0)
	_rows[j] = [hr, sr]


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- meshes

func _build_meshes() -> void:
	material = _make_material()
	var chunks := ceili(float(n - 1) / CHUNK)
	for cj in chunks:
		for ci in chunks:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(ci * CHUNK, cj * CHUNK, mini(CHUNK, n - 1 - ci * CHUNK), mini(CHUNK, n - 1 - cj * CHUNK))
			mi.material_override = material
			mi.name = "Ground_%d_%d" % [ci, cj]
			add_child(mi)


func _chunk_mesh(i0: int, j0: int, qi: int, qj: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var side := qi + 1
	verts.resize(side * (qj + 1))
	normals.resize(side * (qj + 1))
	for j in qj + 1:
		for i in side:
			var gi := i0 + i
			var gj := j0 + j
			var k := gj * n + gi
			var x := -HALF + gi * CELL
			var z := -HALF + gj * CELL
			verts[j * side + i] = Vector3(x, heights[k], z)
			var hl := heights[k - 1] if gi > 0 else heights[k]
			var hr := heights[k + 1] if gi < n - 1 else heights[k]
			var hd := heights[k - n] if gj > 0 else heights[k]
			var hu := heights[k + n] if gj < n - 1 else heights[k]
			normals[j * side + i] = Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
	idx.resize(qi * qj * 6)
	var w := 0
	for j in qj:
		for i in qi:
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = c
			idx[w + 3] = b
			idx[w + 4] = d
			idx[w + 5] = c
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	# Uniformly scaled by CELL: the heights go in divided by it.
	for k in n * n:
		data[k] = heights[k] / CELL
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * CELL
	body.add_child(cs)
	add_child(body)


## The ground for the navmesh as triangle faces (world space), the grid's cells under `rect`: the same
## ground, but every cell under water (or within NAV_SHORE cells of it) sunk far below the bake's
## floor, so nothing there is walkable.
func nav_faces(rect: Rect2) -> PackedVector3Array:
	var i0 := clampi(int(floor((rect.position.x + HALF) / CELL)), 0, n - 2)
	var i1 := clampi(int(ceil((rect.end.x + HALF) / CELL)), 1, n - 1)
	var j0 := clampi(int(floor((rect.position.y + HALF) / CELL)), 0, n - 2)
	var j1 := clampi(int(ceil((rect.end.y + HALF) / CELL)), 1, n - 1)
	var wet_y := JungleLayout.WATER_Y + NAV_WET
	var hgt := func(gi: int, gj: int) -> float:
		for dj in range(-NAV_SHORE, NAV_SHORE + 1):
			for di in range(-NAV_SHORE, NAV_SHORE + 1):
				var ii := clampi(gi + di, 0, n - 1)
				var jj := clampi(gj + dj, 0, n - 1)
				if heights[jj * n + ii] < wet_y:
					return -60.0
		return heights[gj * n + gi]
	var cols := i1 - i0 + 1
	var row_h := PackedFloat32Array()
	row_h.resize((j1 - j0 + 1) * cols)
	for gj in range(j0, j1 + 1):
		for gi in range(i0, i1 + 1):
			row_h[(gj - j0) * cols + gi - i0] = hgt.call(gi, gj)
	var faces := PackedVector3Array()
	faces.resize((j1 - j0) * (i1 - i0) * 6)
	var w := 0
	for gj in range(j0, j1):
		for gi in range(i0, i1):
			var x0 := -HALF + gi * CELL
			var z0 := -HALF + gj * CELL
			var a := Vector3(x0, row_h[(gj - j0) * cols + gi - i0], z0)
			var b := Vector3(x0 + CELL, row_h[(gj - j0) * cols + gi + 1 - i0], z0)
			var c := Vector3(x0, row_h[(gj + 1 - j0) * cols + gi - i0], z0 + CELL)
			var d := Vector3(x0 + CELL, row_h[(gj + 1 - j0) * cols + gi + 1 - i0], z0 + CELL)
			# Clockwise seen from above (Godot's navmesh source faces).
			faces[w] = a
			faces[w + 1] = b
			faces[w + 2] = c
			faces[w + 3] = b
			faces[w + 4] = d
			faces[w + 5] = c
			w += 6
	return faces


## The wall along the water's edge: the contour of the ground at EDGE_UP above the water (marching
## squares over the grid), stood up as a sheer, invisible collision surface. Only LAYER_WATER_EDGE is
## on it, which only walkers' masks have.
func _build_water_edge() -> void:
	var iso := JungleLayout.WATER_Y + EDGE_UP
	_edge_segs = PackedVector2Array()
	for j in n - 1:
		var z := -HALF + j * CELL
		var top := heights.slice(j * n, j * n + n)
		var bot := heights.slice(j * n + n, j * n + n + n)
		for i in n - 1:
			# Corners a (i, j), b (i + 1, j), c (i + 1, j + 1), d (i, j + 1); a bit set for each one under.
			var ha := top[i]
			var hb := top[i + 1]
			var hc := bot[i + 1]
			var hd := bot[i]
			var code := int(ha < iso) | int(hb < iso) << 1 | int(hc < iso) << 2 | int(hd < iso) << 3
			if code == 0 or code == 15:
				continue
			var x := -HALF + i * CELL
			# Where the contour crosses each side: 0 a-b, 1 b-c, 2 c-d, 3 d-a.
			var e := [
				Vector2(x + CELL * (iso - ha) / (hb - ha), z) if (ha < iso) != (hb < iso) else Vector2.ZERO,
				Vector2(x + CELL, z + CELL * (iso - hb) / (hc - hb)) if (hb < iso) != (hc < iso) else Vector2.ZERO,
				Vector2(x + CELL * (iso - hd) / (hc - hd), z + CELL) if (hc < iso) != (hd < iso) else Vector2.ZERO,
				Vector2(x, z + CELL * (iso - ha) / (hd - ha)) if (hd < iso) != (ha < iso) else Vector2.ZERO,
			]
			for seg in EDGE_SEGMENTS[code]:
				_edge_segs.append(e[seg[0]])
				_edge_segs.append(e[seg[1]])
	_edge_shape = ConcavePolygonShape3D.new()
	_edge_shape.backface_collision = true
	edge_body = StaticBody3D.new()
	edge_body.name = "WaterEdge"
	edge_body.collision_layer = GameConfig.LAYER_WATER_EDGE
	edge_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _edge_shape
	edge_body.add_child(cs)
	add_child(edge_body)
	cut_water_edge([])


## (Re)builds the wall along the water's edge, with a gap where each bridge stands: `cuts` are [middle (Vector2),
## along (Vector2, unit), half length, half width] (FoldingBridge.cut), and every bit of the wall inside one of
## those rectangles is left out.
func cut_water_edge(cuts: Array) -> void:
	var y0: float = JungleLayout.WATER_Y + EDGE_WALL[0]
	var y1: float = JungleLayout.WATER_Y + EDGE_WALL[1]
	var faces := PackedVector3Array()
	for k in range(0, _edge_segs.size(), 2):
		var pieces := [[_edge_segs[k], _edge_segs[k + 1]]]
		for c in cuts:
			var kept := []
			for piece in pieces:
				kept.append_array(_clip_out(piece[0], piece[1], c))
			pieces = kept
		for piece in pieces:
			var p: Vector2 = piece[0]
			var q: Vector2 = piece[1]
			faces.append_array([Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y),
					Vector3(p.x, y0, p.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y)])
	_edge_shape.set_faces(faces)


## The parts of the segment p-q outside the rectangle `cut` ([middle, along, half length, half width]).
static func _clip_out(p: Vector2, q: Vector2, cut: Array) -> Array:
	var c: Vector2 = cut[0]
	var u: Vector2 = cut[1]
	var v := Vector2(-u.y, u.x)
	var hl: float = cut[2]
	var hw: float = cut[3]
	# The segment's coordinates along and across the bridge, linear in t (0 at p, 1 at q).
	var pu := (p - c).dot(u)
	var qu := (q - c).dot(u)
	var pv := (p - c).dot(v)
	var qv := (q - c).dot(v)
	var t0 := 0.0
	var t1 := 1.0
	for lim in [[pu, qu, hl], [pv, qv, hw]]:
		var a: float = lim[0]
		var b: float = lim[1]
		var h: float = lim[2]
		if absf(b - a) < 1e-6:
			if absf(a) > h:
				return [[p, q]]
			continue
		var ta := (-h - a) / (b - a)
		var tb := (h - a) / (b - a)
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 >= t1:
		return [[p, q]]
	var out := []
	if t0 > 1e-4:
		out.append([p, p.lerp(q, t0)])
	if t1 < 1.0 - 1e-4:
		out.append([p.lerp(q, t1), q])
	return out


## Marching squares: for each corner code, the sides the contour runs between (see _build_water_edge).
const EDGE_SEGMENTS := [[], [[3, 0]], [[0, 1]], [[3, 1]], [[1, 2]], [[3, 0], [1, 2]], [[0, 2]], [[3, 2]],
		[[2, 3]], [[0, 2]], [[0, 1], [2, 3]], [[1, 2]], [[1, 3]], [[0, 1]], [[0, 3]], []]


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0, HALF * 2.0)
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	mi.mesh = pm
	mi.position.y = JungleLayout.WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("wave_a", _noise_tex(0.012, 71, true))
	m.set_shader_parameter("wave_b", _noise_tex(0.02, 93, true))
	mi.material_override = m
	add_child(mi)


func _make_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("splat", ImageTexture.create_from_image(splat))
	m.set_shader_parameter("map_origin", Vector2(-HALF - CELL * 0.5, -HALF - CELL * 0.5))
	m.set_shader_parameter("map_size", HALF * 2.0 + CELL)
	m.set_shader_parameter("detail", _noise_tex(0.03, 11, false))
	m.set_shader_parameter("macro", _noise_tex(0.008, 12, false))
	m.set_shader_parameter("detail_normal", _noise_tex(0.06, 13, true))
	return m


static func _noise_tex(freq: float, seed_val: int, as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = freq
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.generate_mipmaps = true
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = 4.0
	return tex


const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 map_origin;
uniform float map_size;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(detail, p.yz * scale).r * w.x + texture(detail, p.xz * scale).r * w.y + texture(detail, p.xy * scale).r * w.z;
}

void fragment() {
	vec4 s = texture(splat, (wpos.xz - map_origin) / map_size);
	float n1 = texture(detail, wpos.xz * 0.09).r;
	float n0 = texture(detail, wpos.xz * 0.55 + vec2(0.37, 0.11)).r;
	float n2 = texture(detail, wpos.xz * 0.021).r;
	float m = texture(macro, wpos.xz * 0.0025).r;
	float m2 = texture(macro, wpos.xz * 0.011 + vec2(0.3, 0.7)).r;
	// Jungle floor: leaf litter, dark soil and moss.
	vec3 litter = mix(vec3(0.17, 0.12, 0.07), vec3(0.32, 0.24, 0.13), n1);
	vec3 moss = mix(vec3(0.12, 0.18, 0.06), vec3(0.24, 0.3, 0.1), n2);
	vec3 col = mix(litter, moss, smoothstep(0.35, 0.65, m2 * 0.7 + n2 * 0.3));
	// The clearing: cropped grass, patchy.
	vec3 grass = mix(vec3(0.19, 0.26, 0.09), vec3(0.33, 0.38, 0.15), n1 * 0.5 + n2 * 0.3 + n0 * 0.2);
	// Worn, sun-dried patches and bare earth here and there.
	grass = mix(grass, vec3(0.4, 0.36, 0.2), smoothstep(0.6, 0.78, m) * 0.6);
	grass = mix(grass, vec3(0.36, 0.27, 0.17), smoothstep(0.66, 0.74, m2 * 0.6 + n0 * 0.4) * 0.7);
	col = mix(col, grass, s.g);
	// Mud by the water, darker toward it.
	vec3 mud = mix(vec3(0.16, 0.12, 0.08), vec3(0.3, 0.24, 0.16), n1);
	float wet = smoothstep(-1.2, -2.4, wpos.y);
	mud *= 1.0 - wet * 0.35;
	col = mix(col, mud, s.r);
	// Rock: the steep faces, the quarry's benches.
	float slope = 1.0 - wnrm.y;
	float rockw = max(smoothstep(0.32, 0.5, slope), s.a * smoothstep(0.02, 0.12, slope + 0.05) );
	float rn = tri(wpos, wnrm, 0.12) * 0.6 + tri(wpos, wnrm, 0.5) * 0.4;
	vec3 rock = mix(vec3(0.24, 0.22, 0.19), vec3(0.46, 0.43, 0.38), rn);
	rock = mix(rock, vec3(0.62, 0.6, 0.54), s.a * 0.5);
	rock = mix(rock, vec3(0.2, 0.26, 0.1), smoothstep(0.55, 0.75, n2) * (1.0 - s.a) * 0.6);
	col = mix(col, rock, rockw);
	col *= (0.85 + 0.3 * m) * (0.9 + 0.2 * n0);
	// The colours above are picked in sRGB.
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = mix(0.95, 0.55, s.r * wet);
	NORMAL_MAP = texture(detail_normal, wpos.xz * 0.15).rgb;
	NORMAL_MAP_DEPTH = 0.6 + rockw;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 flow = vec2(0.012, 0.004) * TIME;
	vec3 na = texture(wave_a, wpos.xz * 0.03 + flow).rgb;
	vec3 nb = texture(wave_b, wpos.xz * 0.07 - flow * 1.7).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// A jungle river: dark, murky water (opaque, so it mirrors the banks and the sky: screen-space
	// reflections skip see-through surfaces), the sky's sheen at a glancing angle.
	ALBEDO = pow(mix(vec3(0.17, 0.17, 0.11), vec3(0.3, 0.34, 0.32), fres), vec3(2.2));
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""
