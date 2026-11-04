class_name JungleFlora
extends Node3D
## The Jungle Keep's forest, from the game's own scenery models (Props.TREES, BUSHES, ROCKS) at their
## real sizes: stands of oak, birch and conifer by turns (a noise picks the stand), young trees under
## them, shrubs, ground cover and mossy rocks; tens of thousands of them, drawn in MultiMesh batches per
## CHUNK square (each model of a chunk at once, the engine dropping to the meshes' lower LODs with the
## distance and the small ones past their visibility range).
##
## The trees are also ForestTree proxies (they block the way, burn, and Serpent Snipers nest in them): a
## proxy has no model of its own until it catches fire, when it hides its instance in the batch. Only the
## big trunks (BAKE_TRUNK) are baked into the navmesh, under the navigation region; the rest only collide
## (units slide round them): every hole cut in the navmesh costs every navmesh query on the map. The
## bushes are Bush proxies the same way (Serpent Snipers' traps); the rocks are bodies with collision.
## Young trees, shrubs and ground cover are only drawn: units walk through them.
##
## In the forest (in_jungle()) the whole forest is one forest grove for the game (LevelBuilder).

const OAK := "res://assets/environment/majestic_oak/majestic_oak.glb"
const BIRCHES := [
	"res://assets/environment/birch_tree/birch_tree.glb",
	"res://assets/environment/silver_birch/silver_birch.glb",
	"res://assets/environment/white_birch_majesty/white_birch_majesty.glb",
]
const EVERGREEN := "res://assets/environment/solitary_evergreen/solitary_evergreen.glb"
const SHRUBS := [
	"res://assets/environment/berry_woodland_miniature/berry_woodland_miniature.glb",
	"res://assets/environment/meadow_garden/meadow_garden.glb",
]
const COVER := [
	"res://assets/environment/meadow_tuft/meadow_tuft.glb",
	"res://assets/environment/wild_meadow_tangle/wild_meadow_tangle.glb",
]

const CHUNK := 100.0
## Plants are scattered over the map and out past its edge to OUTER (scenery only past MAP_HALF).
const OUTER := 870.0

## Real heights (m): an open-grown oak spreads wider than it is tall (the model's crown is 1.36 times its
## height), birches and conifers stand taller and narrower.
const OAK_H := Vector2(15.0, 23.0)
const BIRCH_H := Vector2(13.0, 22.0)
const EVERGREEN_H := Vector2(18.0, 32.0)
const YOUNG_H := Vector2(4.0, 9.0)
const SHRUB_H := Vector2(1.2, 2.6)
const COVER_H := Vector2(0.45, 1.1)
const CLEARING_COVER_H := Vector2(0.35, 0.7)
const ROCK_H := Vector2(1.2, 3.8)
## Grid cells (m) the kinds are scattered over, a plant at most per cell.
const OAK_CELL := 17.0
const BIRCH_CELL := 12.0
const EVERGREEN_CELL := 12.5
const YOUNG_CELL := 13.0
const SHRUB_CELL := 8.0
const COVER_CELL := 4.5
const ROCK_CELL := 42.0
## How far (m) a trunk keeps from another's foot (an oak's spreads further).
const TRUNK_GAP := 4.0
const OAK_GAP := 8.0
## Drawn this far out at most (m): the forest fades into the haze; the small things sooner.
const TREE_VIS := 2600.0
const YOUNG_VIS := 380.0
const SHRUB_VIS := 230.0
const COVER_VIS := 110.0
const ROCK_VIS := 600.0
## Trunks this thick (m) and over are baked into the navmesh: units path round them.
const BAKE_TRUNK := 0.75
## The Meshy bushes as Serpent Sniper traps (LevelBuilder.BUSH_WIDTH).
const BUSH_CELL := 13.0
const BUSH_VIS := 260.0
## The prison's grounds are cleared this far round it (m).
const PRISON_CLEAR := 115.0

static var current: JungleFlora

var level: LevelBuilder
var terrain: JungleTerrain
var trees := 0
var plants := 0
var bushes := 0
var rocks := 0

var _rng := RandomNumberGenerator.new()
## [model path, chunk] -> {"path", "xforms": Array[Transform3D] (then the count), "vis", "shadow", "mms"}
var _batches := {}
## Per model path: [[mesh, local xform], ...], its height as modelled and its footprint (x, z).
var _parts := {}
## Which stand grows where (oak, birch or conifer), and patches in the undergrowth.
var _stand := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
## Trunks placed so far, by TRUNK_GRID square, to keep them apart.
const TRUNK_GRID := 8.0
var _trunks := {}


## True if `p` is in the forest: out past the clearing and off the sites (one forest grove for the game).
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
	_stand.seed = 5
	_stand.frequency = 0.0045
	_stand.fractal_octaves = 2
	_patch.seed = 9
	_patch.frequency = 0.02
	var t0 := Time.get_ticks_msec()
	_build_room()
	var records := []
	records.append_array(_scatter_trees("oak", OAK_CELL))
	records.append_array(_scatter_trees("evergreen", EVERGREEN_CELL))
	records.append_array(_scatter_trees("birch", BIRCH_CELL))
	_scatter_young()
	_scatter_shrubs()
	_scatter_cover()
	var bush_records := _scatter_bushes()
	var rock_records := _scatter_rocks()
	_build_batches()
	_make_proxies(records)
	_make_bushes(bush_records)
	_make_rocks(rock_records)
	print("JungleFlora: %d trees, %d plants, %d bushes, %d rocks in %d batches (%d ms)" % [trees, plants, bushes, rocks, _batches.size(), Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------- where things may grow

const ROOM_CELL := 4.0
var _room_n := 0
var _room_grid := PackedFloat32Array()


## How much of the forest's full density may grow, every ROOM_CELL metres (0 in the clearing, on the
## sites and in the quarry), worked out once.
func _build_room() -> void:
	_room_n = int(OUTER * 2.0 / ROOM_CELL) + 1
	_room_grid.resize(_room_n * _room_n)
	var flat_c := PackedVector2Array()
	var flat_r := PackedFloat32Array()
	for f in JungleLayout.FLATTEN:
		flat_c.append(f[0])
		flat_r.append(f[1])
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
				w *= smoothstep(PRISON_CLEAR, PRISON_CLEAR + 30.0, p.distance_to(prison))
				var q := p - qc
				if Vector2(q.x / qr.x, q.y / qr.y).length() < 1.08:
					w = 0.0
			_room_grid[j * _room_n + i] = w


## How much of the forest's full density grows at p (0 in the clearing and on the sites).
func _room(p: Vector2, _unused := 0.0) -> float:
	var i := clampi(int((p.x + OUTER) / ROOM_CELL + 0.5), 0, _room_n - 1)
	var j := clampi(int((p.y + OUTER) / ROOM_CELL + 0.5), 0, _room_n - 1)
	return _room_grid[j * _room_n + i]


## The ground under p is dry and gentle enough: [ok, height].
func _ground(p: Vector2, max_slope: float) -> Array:
	var h := terrain.height_at(p.x, p.y)
	if h < JungleLayout.WATER_Y + 0.5:
		return [false, h]
	return [terrain.normal_at(p.x, p.y).y >= cos(deg_to_rad(max_slope)), h]


func _jitter(cell: float, i: int, j: int) -> Vector2:
	return Vector2((i + _rng.randf()) * cell, (j + _rng.randf()) * cell) - Vector2.ONE * OUTER


## Near the forest's edge (the clearing's rim).
func _edge(p: Vector2) -> float:
	return 1.0 - smoothstep(0.0, 40.0, absf(p.length() - JungleLayout.CLEARING_R - JungleLayout.CLEARING_EDGE * 0.5))


## Clears the forest off a rectangle something came down on (a bridge: FoldingBridge): `xf` its middle, `half` its
## half size along its x and z. The trees in it are flattened (ForestTree.flatten), the rocks' bodies and the bushes
## taken away, and every plant drawn there hidden.
func clear_footprint(xf: Transform3D, half: Vector2) -> void:
	var inv := xf.affine_inverse()
	var inside := func(p: Vector3) -> bool:
		var l := inv * p
		return absf(l.x) <= half.x and absf(l.z) <= half.y
	var reach := half.length()
	var hidden := 0
	for tree in ForestTree.near(xf.origin, reach):
		if inside.call(tree.global_position) and tree.flatten():
			hidden += 1
	for parent_name in ["ForestRocks"]:
		var parent := level.nav_region.get_node_or_null(parent_name)
		if parent:
			for body: Node3D in parent.get_children():
				if body.global_position.distance_to(xf.origin) < reach + 4.0 and inside.call(body.global_position):
					parent.remove_child(body)
					body.queue_free()
	var bushes := get_node_or_null("ForestBushes")
	if bushes:
		for b: Node3D in bushes.get_children():
			if b.get("coiled_by") == null and b.global_position.distance_to(xf.origin) < reach + 4.0 and inside.call(b.global_position):
				b.queue_free()
	var box := AABB(xf.origin - Vector3(reach, 60, reach), Vector3(reach, 60, reach) * 2.0)
	for mmi: MultiMeshInstance3D in get_tree().get_nodes_in_group("flora_batches"):
		var mm := mmi.multimesh
		if mm == null or not mmi.get_aabb().intersects(box):
			continue
		for k in mm.instance_count:
			var t := mm.get_instance_transform(k)
			if t.basis.get_scale().x > 0.0 and inside.call(t.origin):
				mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
				hidden += 1
	print("JungleFlora: cleared %d under a bridge" % hidden)


## Off the sites' lots (for the clearing's ground cover).
func _site_free(p: Vector2) -> bool:
	for f in JungleLayout.FLATTEN:
		if p.distance_to(f[0]) < f[1] * 0.75:
			return false
	return true


## How much the stand at p is of `kind`: oak where the noise is low, conifer where it is high, birch
## between, blending at the edges (and a few of each everywhere).
func _stand_share(p: Vector2, kind: String) -> float:
	var n := _stand.get_noise_2dv(p)
	var oak := 1.0 - smoothstep(-0.32, -0.12, n)
	var conifer := smoothstep(0.12, 0.32, n)
	match kind:
		"oak":
			return 0.12 + 0.88 * oak
		"evergreen":
			return 0.1 + 0.9 * conifer
		_:
			return 0.15 + 0.85 * (1.0 - maxf(oak, conifer))


# ---------------------------------------------------------------- trees

func _trunk_free(p: Vector2, gap: float) -> bool:
	var c := Vector2i(floori(p.x / TRUNK_GRID), floori(p.y / TRUNK_GRID))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for t in _trunks.get(c + Vector2i(di, dj), []):
				if p.distance_to(t[0]) < maxf(gap, t[1]):
					return false
	return true


func _trunk_add(p: Vector2, gap: float) -> void:
	var c := Vector2i(floori(p.x / TRUNK_GRID), floori(p.y / TRUNK_GRID))
	if not _trunks.has(c):
		_trunks[c] = []
	_trunks[c].append([p, gap])


func _scatter_trees(kind: String, cell: float) -> Array:
	var cells := int(OUTER * 2.0 / cell)
	var out := []
	for j in cells:
		for i in cells:
			var p := _jitter(cell, i, j)
			var room := _room(p, 7.0)
			if room <= 0.0:
				continue
			var prob := room * _stand_share(p, kind) * (0.8 if kind == "oak" else 0.78)
			if _rng.randf() >= prob:
				continue
			var gap := OAK_GAP if kind == "oak" else TRUNK_GAP
			if not _trunk_free(p, gap):
				continue
			var g := _ground(p, 26.0)
			if not g[0]:
				continue
			var path: String = OAK if kind == "oak" else (EVERGREEN if kind == "evergreen" else BIRCHES[_rng.randi() % BIRCHES.size()])
			var hr: Vector2 = OAK_H if kind == "oak" else (EVERGREEN_H if kind == "evergreen" else BIRCH_H)
			var h := _rng.randf_range(hr.x, hr.y)
			var yaw := _rng.randf() * TAU
			# The trunk's foot as modelled (Props.TRUNKS) stands on p: the model is shifted back by it.
			var trunk: Array = Props.TRUNKS.get(path, [0.0, 0.0, 0.015, 0.9])
			var offset := Basis(Vector3.UP, yaw) * Vector3(trunk[0], 0.0, trunk[1]) * h
			var foot := Vector3(p.x, g[1] - 0.15, p.y)
			_trunk_add(p, gap)
			var at := _add_instance(path, foot - offset, h, yaw, TREE_VIS, true)
			if absf(p.x) < JungleLayout.MAP_HALF and absf(p.y) < JungleLayout.MAP_HALF:
				out.append({"path": path, "foot": foot, "offset": offset, "h": h, "yaw": yaw, "trunk": trunk, "at": at})
	return out


## Adds an instance of model `path` (scaled to `h`, turned by `yaw`, its origin at `pos`) to its batch for
## the chunk it stands in; returns [batch key, index].
func _add_instance(path: String, pos: Vector3, h: float, yaw: float, vis: float, shadow: bool) -> Array:
	var info := _model_parts(path)
	var chunk := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	var key := [path, chunk]
	if not _batches.has(key):
		_batches[key] = {"path": path, "xforms": [], "vis": vis, "shadow": shadow}
	var b: Dictionary = _batches[key]
	b.xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * (h / info[1])), pos))
	return [key, b.xforms.size() - 1]


## A model's meshes with their transforms (relative to its root, Props.FACING included), its height as
## modelled and its footprint (x, z).
func _model_parts(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var root := (load(path) as PackedScene).instantiate() as Node3D
	root.rotation.y = Props.FACING.get(path, 0.0)
	var parts := []
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent() if n != root else null
		parts.append([(mi as MeshInstance3D).mesh, xf])
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	root.free()
	_parts[path] = [parts, maxf(box.end.y, 0.01), Vector2(box.size.x, box.size.z)]
	return _parts[path]


# ---------------------------------------------------------------- undergrowth

## Young birches and conifers under the stands, thickest at the forest's edge.
func _scatter_young() -> void:
	var cells := int(OUTER * 2.0 / YOUNG_CELL)
	for j in cells:
		for i in cells:
			var p := _jitter(YOUNG_CELL, i, j)
			var room := _room(p, 5.0)
			if _rng.randf() >= 0.3 * room + 0.3 * _edge(p) * room:
				continue
			var g := _ground(p, 30.0)
			if not g[0]:
				continue
			var path: String = EVERGREEN if _stand_share(p, "evergreen") > 0.5 else BIRCHES[_rng.randi() % BIRCHES.size()]
			_add_instance(path, Vector3(p.x, g[1] - 0.1, p.y), _rng.randf_range(YOUNG_H.x, YOUNG_H.y), _rng.randf() * TAU, YOUNG_VIS, true)
			plants += 1


## Shrubs: berry bushes and flowering thickets, thickest along the forest's edge.
func _scatter_shrubs() -> void:
	var cells := int(OUTER * 2.0 / SHRUB_CELL)
	for j in cells:
		for i in cells:
			var p := _jitter(SHRUB_CELL, i, j)
			var room := _room(p, 3.5)
			if _rng.randf() >= (0.3 + 0.25 * _patch.get_noise_2dv(p)) * room + 0.35 * _edge(p) * room:
				continue
			var g := _ground(p, 32.0)
			if not g[0]:
				continue
			_add_instance(SHRUBS[_rng.randi() % SHRUBS.size()], Vector3(p.x, g[1] - 0.05, p.y), _rng.randf_range(SHRUB_H.x, SHRUB_H.y),
					_rng.randf() * TAU, SHRUB_VIS, true)
			plants += 1


## Ground cover: tufts and tangles all over the forest floor, and the clearing's rough grass, thicker
## toward its rim (off the mountain's foot and the sites).
func _scatter_cover() -> void:
	var cells := int(OUTER * 2.0 / COVER_CELL)
	for j in cells:
		for i in cells:
			var p := _jitter(COVER_CELL, i, j)
			var room := _room(p, 2.0)
			var clearing := 0.0
			if room < 0.6 and maxf(absf(p.x), absf(p.y)) > LevelBuilder.MOUNTAIN_HALF + 6.0 and _site_free(p):
				clearing = 0.12 + 0.4 * smoothstep(JungleLayout.CLEARING_R - 140.0, JungleLayout.CLEARING_R - 20.0, p.length())
			var prob := 0.42 * room * (0.7 + 0.3 * _patch.get_noise_2dv(p * 2.0)) + clearing
			if _rng.randf() >= prob:
				continue
			var g := _ground(p, 35.0)
			if not g[0]:
				continue
			var in_clearing := room < 0.3
			var path: String = COVER[0] if in_clearing else COVER[_rng.randi() % COVER.size()]
			var hr := CLEARING_COVER_H if in_clearing else COVER_H
			_add_instance(path, Vector3(p.x, g[1] - 0.05, p.y), _rng.randf_range(hr.x, hr.y), _rng.randf() * TAU, COVER_VIS, false)
			plants += 1


func _scatter_bushes() -> Array:
	var out := []
	var cells := int(OUTER * 2.0 / BUSH_CELL)
	for j in cells:
		for i in cells:
			var p := _jitter(BUSH_CELL, i, j)
			var prob := 0.3 * _room(p, 4.0) + 0.3 * _edge(p) * _room(p, 4.0)
			# A few out in the clearing's outer half, off the mountain's foot.
			if _room(p, 0.0) <= 0.0 and p.length() > JungleLayout.CLEARING_R * 0.55 and maxf(absf(p.x), absf(p.y)) > LevelBuilder.MOUNTAIN_HALF + 20.0 and _site_free(p):
				prob = 0.06
			if _rng.randf() >= prob:
				continue
			var g := _ground(p, 30.0)
			if not g[0]:
				continue
			var path: String = Props.BUSHES[_rng.randi() % Props.BUSHES.size()]
			var info := _model_parts(path)
			var aspect: float = maxf(info[2].x, info[2].y) / info[1]
			var h := minf(_rng.randf_range(LevelBuilder.BUSH_WIDTH[0], LevelBuilder.BUSH_WIDTH[1]) / aspect, LevelBuilder.BUSH_TALLEST)
			var pos := Vector3(p.x, g[1] - 0.05, p.y)
			_add_instance(path, pos, h, _rng.randf() * TAU, BUSH_VIS, true)
			if absf(p.x) < JungleLayout.MAP_HALF and absf(p.y) < JungleLayout.MAP_HALF:
				out.append([pos, path, h])
	return out


## Mossy rocks: along the foot and the top of the cliff, on the quarry's floor and out in the forest.
## [position, model, height, yaw] each.
func _scatter_rocks() -> Array:
	var out := []
	var a := JungleLayout.CLIFF_A
	var b := JungleLayout.CLIFF_B
	for k in 26:
		out.append(_rock_at(a.lerp(b, _rng.randf()) + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(4.0, 14.0)), Vector2(4.0, 9.0)))
	for k in 14:
		out.append(_rock_at(a.lerp(b, _rng.randf()) + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-12.0, -4.0)), Vector2(3.0, 6.0)))
	var qc: Vector2 = JungleLayout.QUARRY_CUT[0]
	for k in 12:
		var p := qc + Vector2(_rng.randf_range(-35, 25), _rng.randf_range(-45, 45))
		if JungleLayout.ellipse_d(p, qc, JungleLayout.QUARRY_CUT[1]) < 0.3:
			out.append(_rock_at(p, Vector2(1.5, 4.0)))
	var cells := int(JungleLayout.MAP_HALF * 2.0 / ROCK_CELL)
	for j in cells:
		for i in cells:
			var p := Vector2((i + _rng.randf()) * ROCK_CELL, (j + _rng.randf()) * ROCK_CELL) - Vector2.ONE * JungleLayout.MAP_HALF
			if _rng.randf() >= 0.32 * _room(p, 8.0):
				continue
			if terrain.height_at(p.x, p.y) < JungleLayout.WATER_Y + 0.6 or not _trunk_free(p, 3.0):
				continue
			out.append(_rock_at(p, ROCK_H))
	return out.filter(func(r): return not r.is_empty())


func _rock_at(p: Vector2, hr: Vector2) -> Array:
	var path: String = Props.ROCKS[_rng.randi() % Props.ROCKS.size()]
	var h := _rng.randf_range(hr.x, hr.y)
	var yaw := _rng.randf() * TAU
	var pos := Vector3(p.x, terrain.height_at(p.x, p.y) - h * 0.15, p.y)
	_add_instance(path, pos, h, yaw, ROCK_VIS, true)
	return [pos, path, h, yaw]


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
			mmi.visibility_range_end = b.vis
			mmi.visibility_range_end_margin = b.vis * 0.1
			add_child(mmi)
			mms.append(mm)
		b["mms"] = mms
		# The transforms aren't needed once they are in the MultiMeshes.
		b.xforms = b.xforms.size()


## The ForestTree proxies for the trees on the map: the thick trunks (BAKE_TRUNK) under the navigation
## region, baked into the navmesh, the rest outside it.
func _make_proxies(records: Array) -> void:
	var baked := Node3D.new()
	baked.name = "ForestTrees"
	level.nav_region.add_child(baked)
	var loose := Node3D.new()
	loose.name = "ForestTreesUnbaked"
	level.add_child(loose)
	for rec in records:
		var h: float = rec.h
		var trunk: Array = rec.trunk
		var proxies := []
		var b: Dictionary = _batches[rec.at[0]]
		for mm in b.mms:
			proxies.append([mm, rec.at[1]])
		var info := _model_parts(rec.path)
		var radius: float = trunk[2] * h
		var tree := ForestTree.new()
		tree.position = rec.foot
		tree.setup_proxy(h, rec.path, rec.yaw, maxf(info[2].x, info[2].y) * (h / info[1]) * 0.5, 0, maxf(radius, 0.25), proxies, -rec.offset)
		tree.trunk_r = radius
		tree.perch = trunk[3] * h
		(baked if radius >= BAKE_TRUNK else loose).add_child(tree)
		trees += 1


## The Bush proxies (Serpent Sniper traps), drawn by the batches.
func _make_bushes(records: Array) -> void:
	var parent := Node3D.new()
	parent.name = "ForestBushes"
	add_child(parent)
	for rec in records:
		var info := _model_parts(rec[1])
		var bush := Bush.new()
		bush.position = rec[0]
		bush.setup(null, info[2] * (rec[2] / info[1]), rec[2], 0.0)
		parent.add_child(bush)
		bushes += 1


## The rocks' bodies (drawn by the batches): a cylinder over the middle of each, under the navigation
## region (the navmesh goes round them).
func _make_rocks(records: Array) -> void:
	var parent := Node3D.new()
	parent.name = "ForestRocks"
	level.nav_region.add_child(parent)
	for rec in records:
		var info := _model_parts(rec[1])
		var h: float = rec[2]
		var fp: Vector2 = info[2] * (h / info[1])
		var body := StaticBody3D.new()
		body.collision_layer = GameConfig.LAYER_WORLD
		body.collision_mask = 0
		body.position = rec[0]
		body.rotation.y = rec[3]
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = minf(fp.x, fp.y) * 0.4
		shape.height = h * 0.8
		cs.shape = shape
		cs.position.y = h * 0.4
		body.add_child(cs)
		parent.add_child(body)
		rocks += 1
