class_name JungleFlora
extends Node3D
## The Jungle Keep's jungle: tens of thousands of plants (tools/gltf/build_jungle_flora.py), scattered
## over the ground by kind (KINDS), drawn in MultiMesh batches per CHUNK square so the engine draws
## each kind of a chunk at once and drops it past its visibility range. Trees swap to their `_far`
## model past FAR_AT.
##
## The trees are also ForestTree proxies under the navigation region (their trunks block the way and
## are baked into the navmesh; they burn, and Serpent Snipers nest in them): a proxy has no model of
## its own until it catches fire, when it hides its instances in the batches. The bushes are Bush
## proxies the same way (Serpent Snipers' traps). Undergrowth and ground cover (ferns, bananas,
## elephant ears, grass) is only drawn: units walk through it.
##
## In the jungle (in_jungle()) the whole jungle is one forest grove for the game (LevelBuilder).

const DIR := "res://assets/environment/jungle/"
const CHUNK := 150.0
## Trees switch to their far model at this distance (m), with this much overlap.
const FAR_AT := 300.0
const FAR_MARGIN := 25.0
## Plants are scattered over the map and out past its edge to OUTER (scenery only past MAP_HALF).
const OUTER := 870.0

## kind -> [model, far model ("": none), height range (m), grid cell (m), visibility end (m, 0: none),
## shadows, tree (a ForestTree proxy) and its trunk radius per metre of height and where a Serpent
## Sniper lies up it (share of its height)].
const KINDS := {
	"kapok": ["kapok", "kapok_far", Vector2(40, 56), 44.0, 0.0, true, true, 0.034, 0.8],
	"canopy_a": ["canopy_a", "canopy_a_far", Vector2(24, 34), 16.0, 0.0, true, true, 0.028, 0.9],
	"canopy_b": ["canopy_b", "canopy_a_far", Vector2(28, 38), 16.0, 0.0, true, true, 0.026, 0.9],
	"palm": ["palm", "palm_far", Vector2(11, 22), 15.0, 0.0, true, true, 0.02, 0.92],
	"bamboo": ["bamboo", "", Vector2(9, 14), 20.0, 0.0, true, true, 0.08, 0.85],
	"banana": ["banana", "", Vector2(3.0, 6.0), 9.0, 220.0, true, false, 0.0, 0.0],
	"tree_fern": ["tree_fern", "", Vector2(4.0, 7.5), 9.5, 240.0, true, false, 0.0, 0.0],
	"elephant_ear": ["elephant_ear", "", Vector2(1.4, 2.6), 6.0, 150.0, false, false, 0.0, 0.0],
	"fern": ["fern", "", Vector2(0.8, 1.7), 3.4, 130.0, false, false, 0.0, 0.0],
	"grass": ["grass", "", Vector2(0.5, 1.1), 2.6, 95.0, false, false, 0.0, 0.0],
}
## The Meshy bushes (Props.BUSHES) as ground-cover shrubs and Serpent Sniper traps (LevelBuilder.BUSH_WIDTH).
const BUSH_CELL := 13.0
const BUSH_VIS := 260.0

static var current: JungleFlora

var level: LevelBuilder
var terrain: JungleTerrain
var trees := 0
var plants := 0
var bushes := 0

var _rng := RandomNumberGenerator.new()
## [kind/model, chunk] -> {"parts": [[mesh, local xform], ...], "xforms": Array[Transform3D], "vis": .., "shadow": .., "far": bool}
var _batches := {}
## Per model path: [[mesh, local xform], ...] and its height as modelled.
var _parts := {}
var _patch := FastNoiseLite.new()
var _bamboo := FastNoiseLite.new()


## True if `p` is in the jungle: out past the clearing and off the sites (one forest grove for the game).
static func in_jungle(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if q.length() < JungleLayout.CLEARING_R + 25.0:
		return false
	for f in JungleLayout.FLATTEN:
		if q.distance_to(f[0]) < f[1] * 0.7:
			return false
	return true


func build() -> void:
	current = self
	_rng.seed = 20261031
	_patch.seed = 5
	_patch.frequency = 0.012
	_bamboo.seed = 77
	_bamboo.frequency = 0.008
	var t0 := Time.get_ticks_msec()
	_build_room()
	var records := []
	for kind in ["kapok", "canopy_a", "palm", "bamboo"]:
		records.append_array(_scatter_trees(kind))
	for kind in ["banana", "tree_fern", "elephant_ear", "fern", "grass"]:
		_scatter_plants(kind)
	var bush_records := _scatter_bushes()
	_build_batches()
	_make_proxies(records)
	_make_bushes(bush_records)
	print("JungleFlora: %d trees, %d plants, %d bushes in %d batches (%d ms)" % [trees, plants, bushes, _batches.size(), Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------- where things may grow

const ROOM_CELL := 4.0
var _room_n := 0
var _room_grid := PackedFloat32Array()


## How much of the jungle's full density may grow, every ROOM_CELL metres (0 in the clearing, on the
## sites, by the bridges and in the quarry), worked out once.
func _build_room() -> void:
	_room_n = int(OUTER * 2.0 / ROOM_CELL) + 1
	_room_grid.resize(_room_n * _room_n)
	var flat_c := PackedVector2Array()
	var flat_r := PackedFloat32Array()
	for f in JungleLayout.FLATTEN:
		flat_c.append(f[0])
		flat_r.append(f[1])
	var br_a := PackedVector2Array()
	var br_b := PackedVector2Array()
	for b in JungleLayout.bridges():
		var half: float = b[2] * 0.5 + 10.0
		br_a.append(b[0] - b[1] * half)
		br_b.append(b[0] + b[1] * half)
	var r0 := JungleLayout.CLEARING_R - 10.0
	var r1 := JungleLayout.CLEARING_R + JungleLayout.CLEARING_EDGE
	var prison := JungleLayout.PRISON
	var qc: Vector2 = JungleLayout.QUARRY_CUT[0]
	var qr: Vector2 = JungleLayout.QUARRY_CUT[1]
	for j in _room_n:
		for i in _room_n:
			var p := Vector2(-OUTER + i * ROOM_CELL, -OUTER + j * ROOM_CELL)
			var w := smoothstep(r0, r1, p.length())
			if w > 0.0:
				for f in flat_c.size():
					w *= smoothstep(flat_r[f] * 0.75, flat_r[f] * 1.05, p.distance_to(flat_c[f]))
				w *= smoothstep(70.0, 95.0, p.distance_to(prison))
				for b in br_a.size():
					var ab := br_b[b] - br_a[b]
					var t := clampf((p - br_a[b]).dot(ab) / ab.length_squared(), 0.0, 1.0)
					w *= smoothstep(8.0, 16.0, p.distance_to(br_a[b] + ab * t))
				var q := p - qc
				if Vector2(q.x / qr.x, q.y / qr.y).length() < 1.08:
					w = 0.0
			_room_grid[j * _room_n + i] = w


## How much of the jungle's full density grows at p, for a plant needing `track_clear` metres off the
## tracks (0 in the clearing, on the sites, the tracks, the bridges).
func _room(p: Vector2, track_clear: float) -> float:
	var i := clampi(int((p.x + OUTER) / ROOM_CELL + 0.5), 0, _room_n - 1)
	var j := clampi(int((p.y + OUTER) / ROOM_CELL + 0.5), 0, _room_n - 1)
	var w := _room_grid[j * _room_n + i]
	if w <= 0.0 or track_clear <= 0.0:
		return w
	return w * smoothstep(track_clear, track_clear + 3.0, terrain.track_distance(p.x, p.y))


## The ground under p is dry and gentle enough: [ok, height, normal].
func _ground(p: Vector2, max_slope: float) -> Array:
	var h := terrain.height_at(p.x, p.y)
	if h < JungleLayout.WATER_Y + 0.5:
		return [false, h, Vector3.UP]
	var nrm := terrain.normal_at(p.x, p.y)
	return [nrm.y >= cos(deg_to_rad(max_slope)), h, nrm]


func _jitter(cell: float, i: int, j: int) -> Vector2:
	return Vector2((i + _rng.randf()) * cell, (j + _rng.randf()) * cell) - Vector2.ONE * OUTER


# ---------------------------------------------------------------- trees

func _scatter_trees(kind: String) -> Array:
	var spec: Array = KINDS[kind]
	var cell: float = spec[3]
	var cells := int(OUTER * 2.0 / cell)
	var out := []
	for j in cells:
		for i in cells:
			var p := _jitter(cell, i, j)
			var k := kind
			var prob := 0.0
			var room := _room(p, 7.5)
			match kind:
				"kapok":
					prob = 0.55 * room
				"canopy_a":
					prob = 0.82 * room * (0.7 + 0.3 * _patch.get_noise_2dv(p * 0.5))
					k = "canopy_a" if _patch.get_noise_2dv(p) > -0.1 else "canopy_b"
				"palm":
					# Along the rivers, round the clearing's edge, a few everywhere.
					var by_water := 1.0 - smoothstep(20.0, 60.0, terrain.river_distance(p.x, p.y))
					var edge := 1.0 - smoothstep(0.0, 45.0, absf(p.length() - JungleLayout.CLEARING_R - 15.0))
					prob = (0.1 + 0.55 * by_water) * room + 0.3 * edge * _room(p, 6.0)
				"bamboo":
					prob = 0.8 * room * smoothstep(0.25, 0.45, _bamboo.get_noise_2dv(p))
			if _rng.randf() >= prob:
				continue
			var g := _ground(p, 24.0)
			if not g[0]:
				continue
			# Keep the trunks apart: no tree within 5 m of another's foot.
			var s: Array = KINDS[k]
			var h := _rng.randf_range(s[2].x, s[2].y)
			var yaw := _rng.randf() * TAU
			var pos := Vector3(p.x, g[1] - 0.15, p.y)
			var rec := {"kind": k, "pos": pos, "h": h, "yaw": yaw, "proxies": []}
			rec.proxies.append(_add_instance(s[0], pos, h, yaw, s[4], s[5], false))
			if s[1] != "":
				rec.proxies.append(_add_instance(s[1], pos, h, yaw, 0.0, false, true))
			if absf(p.x) < JungleLayout.MAP_HALF and absf(p.y) < JungleLayout.MAP_HALF:
				out.append(rec)
	return out


## Adds an instance of model `name` to its batch for p's chunk; returns [batch key, index].
func _add_instance(name: String, pos: Vector3, h: float, yaw: float, vis: float, shadow: bool, far: bool) -> Array:
	var path := DIR + name + ".glb"
	return _add_path_instance(path, pos, h, yaw, vis, shadow, far)


func _add_path_instance(path: String, pos: Vector3, h: float, yaw: float, vis: float, shadow: bool, far: bool) -> Array:
	var info := _model_parts(path)
	var chunk := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	var key := [path, chunk]
	if not _batches.has(key):
		_batches[key] = {"path": path, "xforms": [], "vis": vis, "shadow": shadow, "far": far}
	var b: Dictionary = _batches[key]
	var s: float = h / info[1]
	b.xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
	return [key, b.xforms.size() - 1]


## A model's meshes with their transforms (relative to its root), and its height as modelled.
func _model_parts(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var parts := []
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		parts.append([(mi as MeshInstance3D).mesh, xf])
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	root.free()
	_parts[path] = [parts, maxf(box.end.y, 0.01), Vector2(box.size.x, box.size.z)]
	return _parts[path]


# ---------------------------------------------------------------- undergrowth

func _scatter_plants(kind: String) -> void:
	var spec: Array = KINDS[kind]
	var cell: float = spec[3]
	var cells := int(OUTER * 2.0 / cell)
	for j in cells:
		for i in cells:
			var p := _jitter(cell, i, j)
			var prob := 0.0
			match kind:
				"banana":
					var room := _room(p, 4.0)
					prob = 0.3 * room + 0.25 * _edge(p) * _room(p, 4.0)
				"tree_fern":
					prob = 0.32 * _room(p, 4.0)
				"elephant_ear":
					var by_water := 1.0 - smoothstep(15.0, 45.0, terrain.river_distance(p.x, p.y))
					prob = (0.2 + 0.4 * by_water) * _room(p, 3.0)
				"fern":
					prob = 0.55 * _room(p, 2.5) * (0.6 + 0.4 * _patch.get_noise_2dv(p * 2.0))
				"grass":
					# Thick in the clearing's rough edges and by the tracks and the water, thinner under the trees.
					var clearing := smoothstep(JungleLayout.CLEARING_R - 120.0, JungleLayout.CLEARING_R - 20.0, p.length())
					var mountain := maxf(absf(p.x), absf(p.y)) > LevelBuilder.MOUNTAIN_HALF + 12.0
					prob = 0.15 * _room(p, 1.5) + (0.55 * clearing if mountain and _room(p, 0.0) < 0.6 and _site_free(p) else 0.0)
			if _rng.randf() >= prob:
				continue
			var g := _ground(p, 35.0)
			if not g[0]:
				continue
			var h := _rng.randf_range(spec[2].x, spec[2].y)
			var pos := Vector3(p.x, g[1] - 0.05, p.y)
			_add_instance(spec[0], pos, h, _rng.randf() * TAU, spec[4], spec[5], false)
			plants += 1


## Near the jungle's edge (the clearing's rim).
func _edge(p: Vector2) -> float:
	return 1.0 - smoothstep(0.0, 40.0, absf(p.length() - JungleLayout.CLEARING_R - JungleLayout.CLEARING_EDGE * 0.5))


## Off the sites' lots and the tracks (for the clearing's grass).
func _site_free(p: Vector2) -> bool:
	for f in JungleLayout.FLATTEN:
		if p.distance_to(f[0]) < f[1] * 0.75:
			return false
	return terrain.track_distance(p.x, p.y) > 4.0


func _scatter_bushes() -> Array:
	var out := []
	var cells := int(OUTER * 2.0 / BUSH_CELL)
	for j in cells:
		for i in cells:
			var p := _jitter(BUSH_CELL, i, j)
			var prob := 0.42 * _room(p, 4.0) + 0.3 * _edge(p) * _room(p, 4.0)
			if _rng.randf() >= prob:
				continue
			var g := _ground(p, 30.0)
			if not g[0]:
				continue
			var path: String = Props.BUSHES[_rng.randi() % Props.BUSHES.size()]
			var info := _model_parts(path)
			var aspect: float = maxf(info[2].x, info[2].y) / info[1]
			var h := minf(_rng.randf_range(LevelBuilder.BUSH_WIDTH[0], LevelBuilder.BUSH_WIDTH[1]) / aspect, LevelBuilder.BUSH_TALLEST)
			var yaw := _rng.randf() * TAU
			var pos := Vector3(p.x, g[1] - 0.05, p.y)
			_add_path_instance(path, pos, h, yaw, BUSH_VIS, true, false)
			if absf(p.x) < JungleLayout.MAP_HALF and absf(p.y) < JungleLayout.MAP_HALF:
				out.append([pos, path, h])
	return out


# ---------------------------------------------------------------- batches and proxies

func _build_batches() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var info := _model_parts(b.path)
		var mms := []
		for part in info[0]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = b.xforms.size()
			var local: Transform3D = part[1]
			for k in b.xforms.size():
				mm.set_instance_transform(k, b.xforms[k] * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.add_to_group("flora_batches")
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if b.far:
				mmi.visibility_range_begin = FAR_AT
				mmi.visibility_range_begin_margin = FAR_MARGIN
			elif b.vis > 0.0:
				mmi.visibility_range_end = b.vis
				mmi.visibility_range_end_margin = b.vis * 0.1
			elif _is_tree_path(b.path):
				mmi.visibility_range_end = FAR_AT + FAR_MARGIN
				mmi.visibility_range_end_margin = FAR_MARGIN
			add_child(mmi)
			mms.append(mm)
		b["mms"] = mms
		# The transforms aren't needed once they are in the MultiMeshes (the parts' are kept apart).
		b.xforms = b.xforms.size()


func _is_tree_path(path: String) -> bool:
	for k in KINDS:
		if KINDS[k][6] and path == DIR + KINDS[k][0] + ".glb":
			return true
	return false


## The ForestTree proxies for the trees on the map (under the navigation region: their trunks are
## baked into the navmesh).
func _make_proxies(records: Array) -> void:
	var parent := Node3D.new()
	parent.name = "JungleTrees"
	level.nav_region.add_child(parent)
	for rec in records:
		var s: Array = KINDS[rec.kind]
		var h: float = rec.h
		var proxies := []
		for pr in rec.proxies:
			var b: Dictionary = _batches[pr[0]]
			for mm in b.mms:
				proxies.append([mm, pr[1]])
		var info := _model_parts(DIR + s[0] + ".glb")
		var canopy: float = maxf(info[2].x, info[2].y) * (h / info[1]) * 0.5
		var tree := ForestTree.new()
		tree.position = rec.pos
		tree.setup_proxy(h, DIR + s[0] + ".glb", rec.yaw, canopy, 0, maxf(s[7] * h, 0.3), proxies)
		tree.trunk_r = s[7] * h
		tree.perch = s[8] * h
		parent.add_child(tree)
		trees += 1


## The Bush proxies (Serpent Sniper traps), drawn by the batches.
func _make_bushes(records: Array) -> void:
	var parent := Node3D.new()
	parent.name = "JungleBushes"
	add_child(parent)
	for rec in records:
		var info := _model_parts(rec[1])
		var bush := Bush.new()
		bush.position = rec[0]
		bush.setup(null, info[2] * (rec[2] / info[1]), rec[2], 0.0)
		parent.add_child(bush)
		bushes += 1
