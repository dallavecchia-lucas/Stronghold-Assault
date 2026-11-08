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
	var flat_r := [110.0, 75.0, 195.0]
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


## The water: one plane at JungleLayout.WATER_Y, showing only where the land dips under it (WATER_SHADER),
## flowing down the rivers (a flow map baked from their courses) and still on the lake.
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
	m.set_shader_parameter("wave_normal", load("res://assets/textures/water/water_normal.png"))
	m.set_shader_parameter("foam_tex", load("res://assets/textures/water/water_foam.png"))
	m.set_shader_parameter("flow_tex", ImageTexture.create_from_image(_flow_map()))
	m.set_shader_parameter("map_origin", Vector2(-HALF, -HALF))
	m.set_shader_parameter("map_size", HALF * 2.0)
	m.set_shader_parameter("water_y", JungleLayout.WATER_Y)
	mi.material_override = m
	add_child(mi)


## Which way and how fast the water runs (m/s) every FLOW_CELL m: down each river's course (the order its
## points are listed in), fading out across the lake. Encoded round 0.5 (FLOW_MAX either way).
const FLOW_CELL := 8.0
const FLOW_MAX := 1.5
const FLOW_SPEED := 0.9


func _flow_map() -> Image:
	var fn := int(HALF * 2.0 / FLOW_CELL) + 1
	var best := PackedFloat32Array()
	best.resize(fn * fn)
	best.fill(1.0e6)
	var data := PackedByteArray()
	data.resize(fn * fn * 2)
	data.fill(128)
	var lake_c: Vector2 = JungleLayout.LAKE[0]
	var lake_r: Vector2 = JungleLayout.LAKE[1]
	for seg in _river_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var band: float = seg[2] + JungleLayout.BANK + 8.0
		var ab := b - a
		var dir := ab.normalized()
		var inv := 1.0 / maxf(ab.length_squared(), 1e-6)
		var i0 := clampi(int(floor((minf(a.x, b.x) - band + HALF) / FLOW_CELL)), 0, fn - 1)
		var i1 := clampi(int(ceil((maxf(a.x, b.x) + band + HALF) / FLOW_CELL)), 0, fn - 1)
		var j0 := clampi(int(floor((minf(a.y, b.y) - band + HALF) / FLOW_CELL)), 0, fn - 1)
		var j1 := clampi(int(ceil((maxf(a.y, b.y) + band + HALF) / FLOW_CELL)), 0, fn - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(-HALF + i * FLOW_CELL, -HALF + j * FLOW_CELL)
				var t := clampf((p - a).dot(ab) * inv, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var k := j * fn + i
				if d < best[k] and d < band:
					best[k] = d
					# Fastest mid-stream, slack at the banks, still out on the lake.
					var lake := Vector2((p.x - lake_c.x) / lake_r.x, (p.y - lake_c.y) / lake_r.y).length()
					var speed := FLOW_SPEED * (1.0 - smoothstep(0.55, 1.0, d / maxf(seg[2], 1.0)) * 0.6) * smoothstep(0.7, 1.1, lake)
					var f := dir * speed / FLOW_MAX
					data[k * 2] = clampi(int((f.x * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
					data[k * 2 + 1] = clampi(int((f.y * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
	return Image.create_from_data(fn, fn, false, Image.FORMAT_RG8, data)


## The ground's material: photoscanned forest floor, grass, earth, mud, rock and river pebbles laid by the
## splat, the slope and the water (GroundMaterial).
func _make_material() -> ShaderMaterial:
	return GroundMaterial.jungle(ImageTexture.create_from_image(splat), Vector2(-HALF - CELL * 0.5, -HALF - CELL * 0.5),
			HALF * 2.0 + CELL, JungleLayout.WATER_Y)


## The water. A jungle river: murky, olive-brown in its depths, showing its bed in the shallows. Seen through,
## the bed (and anything swimming) is bent by the ripples and dimmed colour by colour with the depth of water
## the light comes through (read from the depth buffer). Its surface is calm: fine ripples and a broad slow
## swell (an FFT heightfield's normals) flowing down the rivers with the current (two-phase flow mapping,
## blended so the waves neither stretch nor pulse), rougher where the current runs fast, all but still on the
## lake, and smoothing out with distance. It is a mirror at a low angle (water's own Fresnel): reflections are
## ray-marched across the screen against the depth buffer, so the banks, the trees, the bridges and the rafts
## mirror in it; where a reflected ray finds nothing, the sky's reflection (its clouds, the sun's glint) is the
## engine's own, switched off where a ray does find something (the bank hides the sky there). It thins to a
## film where it laps on the bank, so it meets the bank without a seam. A little foam gathers along the shore
## and round anything standing in it (a bridge's piers, a swimmer, a raft), and in streaks down fast water.
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(-880.0);
uniform float map_size = 1760.0;
uniform float water_y = -1.8;
uniform float flow_max = 1.5;
// How fast the water swallows light (per metre, red green blue) and the colour of what is stirred up in it.
uniform vec3 absorption = vec3(0.95, 0.72, 1.15);
uniform vec3 murk = vec3(0.045, 0.06, 0.03);
// The ripples' and the swell's tiles (m), and how much they tilt the surface.
uniform float ripple_tile = 2.6;
uniform float swell_tile = 12.0;
uniform float wave_strength = 0.3;
uniform float refraction = 0.035;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scene_distance(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

vec3 scene_view(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

// The waves' normal map (tilt, -1..1) at `p` (m) on a `tile` m tile, carried along by `flow` (m/s): two
// phases half a cycle apart, crossfaded and rescaled so the blend keeps the waves' strength.
vec2 flowing(vec2 p, float tile, vec2 flow, float t, float period) {
	float p0 = fract(t / period);
	float p1 = fract(t / period + 0.5);
	float w = 1.0 - abs(2.0 * p0 - 1.0);
	vec2 uv = p / tile;
	vec2 a = texture(wave_normal, uv - flow * p0 * period / tile).rg * 2.0 - 1.0;
	vec2 b = texture(wave_normal, uv - flow * p1 * period / tile + vec2(0.37, 0.61)).rg * 2.0 - 1.0;
	return (a * w + b * (1.0 - w)) * inversesqrt(w * w + (1.0 - w) * (1.0 - w));
}

void fragment() {
	vec2 flow = (texture(flow_tex, (wpos.xz - map_origin) / map_size).rg * 2.0 - 1.0) * flow_max;
	float speed = length(flow);
	float dist = length(VERTEX);
	vec3 vdir = VERTEX / dist;
	// Fine ripples riding the current and a broad, slower swell; a breath of wind across the still water.
	vec2 drift = vec2(0.05, -0.03);
	vec2 ripples = flowing(wpos.xz, ripple_tile, flow + drift, TIME, 2.4);
	vec2 swell = flowing(wpos.xz + vec2(31.0, 17.0), swell_tile, flow * 0.85 + drift * 0.6, TIME + 1.1, 4.2);
	float far = smoothstep(15.0, 240.0, dist);
	float lively = mix(0.7, 1.3, smoothstep(0.15, 1.0, speed));
	float calm = wave_strength * lively * (1.0 - far * 0.65);
	vec2 tilt = (ripples * 0.5 + swell * 0.8) * calm;
	// On the water the texture's right is +x and its up is -z.
	vec3 nw = normalize(vec3(tilt.x, 1.0, -tilt.y));
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(up, nv, 0.85));
	// The mirror is bent by the swell; the fine ripples only blur it (each pixel spans many of them).
	vec2 rtilt = (ripples * 0.12 + swell * 0.7) * calm * 0.6;
	vec3 nr = normalize((VIEW_MATRIX * vec4(normalize(vec3(rtilt.x, 1.0, -rtilt.y)), 0.0)).xyz);

	// What is under the water, seen through it, bent by the waves (not where that would show something above
	// the surface).
	float surface = -VERTEX.z;
	vec2 ruv = SCREEN_UV + tilt * refraction * clamp(scene_distance(SCREEN_UV, INV_PROJECTION_MATRIX) - surface, 0.0, 1.5) / max(surface * 0.05, 1.0);
	if (scene_distance(ruv, INV_PROJECTION_MATRIX) < surface) {
		ruv = SCREEN_UV;
	}
	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 bed = scene_view(ruv, INV_PROJECTION_MATRIX);
	float through = max(-bed.z - surface, 0.0) * dist / max(surface, 0.001);
	vec3 transmit = exp(-absorption * through);
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed, 1.0)).xyz;
	float depth = max(water_y - bed_world.y, 0.0);
	// Where it laps on the bank it is a film: no mirror, no sheen.
	float edge = smoothstep(0.0, 0.18, depth);

	// Reflections: march the reflected ray across the screen; where it first passes behind something, narrow
	// the crossing down and take it if the ray is at that surface (not passing behind something thin).
	vec3 rd = reflect(vdir, nr);
	// Never into the water: off the back of a wave the ray would only meet the next one.
	rd = normalize(rd + up * max(0.015 - dot(rd, up), 0.0));
	float hit = 0.0;
	vec3 mirrored = vec3(0.0);
	// The first crossing that looked too far behind its surface, kept in case the ray finds nothing nearer.
	vec2 spare_uv = vec2(-1.0);
	float t = 0.25;
	vec3 last = VERTEX;
	bool in_front = true;
	for (int i = 0; i < 36; i++) {
		vec3 q = VERTEX + rd * t;
		vec4 c = PROJECTION_MATRIX * vec4(q, 1.0);
		if (c.w <= 0.0) {
			break;
		}
		vec2 quv = c.xy / c.w * 0.5 + 0.5;
		if (quv.x < 0.0 || quv.y < 0.0 || quv.x > 1.0 || quv.y > 1.0) {
			break;
		}
		bool behind = -q.z > scene_distance(quv, INV_PROJECTION_MATRIX);
		if (behind && in_front) {
			vec3 lo = last;
			vec3 hi = q;
			for (int k = 0; k < 6; k++) {
				vec3 mid = (lo + hi) * 0.5;
				vec4 mc = PROJECTION_MATRIX * vec4(mid, 1.0);
				if (-mid.z > scene_distance(mc.xy / mc.w * 0.5 + 0.5, INV_PROJECTION_MATRIX)) {
					hi = mid;
				} else {
					lo = mid;
				}
			}
			vec4 hc = PROJECTION_MATRIX * vec4(hi, 1.0);
			vec2 huv = hc.xy / hc.w * 0.5 + 0.5;
			float gap = -hi.z - scene_distance(huv, INV_PROJECTION_MATRIX);
			float thick = 0.5 + 0.08 * length(hi - VERTEX);
			if (gap < thick) {
				mirrored = textureLod(screen_tex, huv, 0.0).rgb;
				vec2 e = min(huv, 1.0 - huv);
				hit = smoothstep(0.0, 0.06, min(e.x, e.y)) * (1.0 - smoothstep(0.75, 1.0, float(i) / 36.0));
				break;
			}
			if (spare_uv.x < 0.0 && gap < thick * 4.0) {
				spare_uv = huv;
			}
		}
		in_front = !behind;
		last = q;
		t *= 1.22;
	}
	if (hit == 0.0 && spare_uv.x >= 0.0) {
		mirrored = textureLod(screen_tex, spare_uv, 0.0).rgb;
		vec2 e = min(spare_uv, 1.0 - spare_uv);
		hit = smoothstep(0.0, 0.06, min(e.x, e.y)) * 0.85;
	}
	float cosv = clamp(dot(nr, -vdir), 0.0, 1.0);
	float fresnel = (0.02 + 0.98 * pow(1.0 - cosv, 5.0)) * edge;

	// Foam: a ragged line along the shore and round whatever stands in the water, streaks down fast water.
	float p0 = fract(TIME / 2.4);
	float wa = 1.0 - abs(2.0 * p0 - 1.0);
	float f1 = texture(foam_tex, wpos.xz / 3.0 - flow * p0 * 2.4 / 3.0).r * wa
			+ texture(foam_tex, wpos.xz / 3.0 - flow * fract(TIME / 2.4 + 0.5) * 2.4 / 3.0 + vec2(0.5)).r * (1.0 - wa);
	float shore = (1.0 - smoothstep(0.02, 0.3, depth)) * edge * smoothstep(0.45, 0.7, texture(foam_tex, wpos.xz * 0.021).r);
	float streak = smoothstep(0.66, 0.92, texture(foam_tex, vec2(dot(wpos.xz, vec2(-flow.y, flow.x)) * 0.25, dot(wpos.xz, flow) * 0.02 - TIME * 0.1)).r)
			* smoothstep(0.5, 1.2, speed) * 0.3;
	float foam = clamp(smoothstep(0.45, 0.8, f1 * (shore * 1.3 + streak)), 0.0, 1.0);

	vec3 scatter = murk * (1.0 - transmit);
	ALBEDO = mix(scatter, vec3(0.75, 0.77, 0.72), foam);
	EMISSION = (below * transmit * (1.0 - fresnel) + mirrored * fresnel * hit) * (1.0 - foam);
	// The engine's own reflection (the sky, its clouds, the sun's glint) wherever the ray found nothing: water's
	// F0 of 0.02.
	SPECULAR = 0.354 * (1.0 - hit) * (1.0 - foam) * edge;
	// Not quite a perfect mirror: each pixel spans many ripples, and the sun's glint spreads over them.
	ROUGHNESS = mix(mix(0.1, 0.14, far), 0.8, foam);
	METALLIC = 0.0;
	// Drawn over the finished opaque scene (it reads it): everything behind is already in EMISSION.
	ALPHA = 1.0;
}
"""
