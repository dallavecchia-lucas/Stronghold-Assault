class_name JungleLayout
extends RefCounted
## The Jungle Keep map's layout: where everything is, and the shape of the land (height()).
##
## A 1.6 km square of jungle (MAP_HALF), +z south as everywhere in the game. The stronghold (the
## Keep) stands in a wide clearing in the middle, its gates facing south, east and west. A river
## crosses the whole map south of it, west to east; a tributary comes down out of the north-west
## into a lake and on into it; another runs down the east side of the clearing from the north edge.
## Truss bridges cross them at the four bridge sites. The attackers come from the Mobile Command
## Citadel (the main spawn) at the south edge, across the river, or from the Quarry helipad west
## of the Keep and the Outpost helipad east of it, across the east river. The prison stands on a
## plateau to the north, behind a cliff that faces the Keep; the plateau slopes down to the jungle
## round the cliff's ends. Four wooded ridges rise near the corners and south-east of the Keep.

const MAP_HALF := 800.0
## The clearing round the stronghold: flat ground out to CLEARING_R, the jungle closing in by
## CLEARING_EDGE further out.
const CLEARING_R := 270.0
const CLEARING_EDGE := 70.0
## The water's surface, and how deep the beds are dug (m below 0).
const WATER_Y := -1.8
const RIVER_BED := -5.2
const LAKE_BED := -7.0
## A river's banks rise from the water's edge to the land over this far (m).
const BANK := 9.0

## Rivers as [name, width (m), centreline points (x, z)]: smoothed into curves (river_curve()).
const RIVERS := [
	["main", 42.0, [Vector2(-830, 470), Vector2(-700, 486), Vector2(-560, 484), Vector2(-420, 470), Vector2(-260, 460),
			Vector2(-110, 474), Vector2(0, 482), Vector2(130, 474), Vector2(260, 462), Vector2(372, 468), Vector2(480, 478),
			Vector2(600, 470), Vector2(720, 458), Vector2(830, 466)]],
	["northwest", 28.0, [Vector2(-830, -390), Vector2(-770, -290), Vector2(-712, -160), Vector2(-676, -20),
			Vector2(-652, 120), Vector2(-642, 200)]],
	["lake_outlet", 26.0, [Vector2(-628, 330), Vector2(-612, 400), Vector2(-596, 450), Vector2(-586, 490)]],
	["east", 30.0, [Vector2(430, -830), Vector2(404, -650), Vector2(388, -420), Vector2(378, -200), Vector2(372, 0),
			Vector2(368, 200), Vector2(370, 340), Vector2(372, 480)]],
]
## The lake the north-west river runs into: centre, radii (x, z).
const LAKE := [Vector2(-640, 262), Vector2(82, 108)]

## The ridges: [centre, radii (x, z), height (m), yaw (rad)], rounded hills with a little relief.
const RIDGES := [
	[Vector2(-520, -600), Vector2(150, 95), 44.0, 0.25],
	[Vector2(610, -610), Vector2(150, 92), 38.0, -0.2],
	[Vector2(180, 330), Vector2(120, 62), 22.0, 0.08],
	[Vector2(-600, 650), Vector2(140, 80), 32.0, -0.15],
]

## The prison's plateau: the core (centre, radii) is PLATEAU_Y up; it slopes down to the jungle over
## PLATEAU_RAMP, except along the cliff (CLIFF_A..CLIFF_B, a line facing south toward the Keep),
## where it drops sheer.
const PLATEAU := [Vector2(-30, -690), Vector2(260, 205)]
const PLATEAU_Y := 24.0
const PLATEAU_RAMP := 135.0
const CLIFF_A := Vector2(-175, -497)
const CLIFF_B := Vector2(95, -497)
## The cliff's ends fade into the ramps over this far (m).
const CLIFF_FADE := 40.0

## Sites (x, z) and how far round each the ground is flattened (m).
const PRISON := Vector2(-20, -650)
const MAIN_SPAWN := Vector2(0, 690)
const QUARRY := Vector2(-440, -40)
const OUTPOST := Vector2(560, -40)
## The quarry: a rocky hill west of the helipad, its east face cut back in benches (QUARRY_BENCH m
## each) down to the floor the helipad stands on.
const QUARRY_HILL := [Vector2(-560, -40), Vector2(105, 120), 17.0]
const QUARRY_CUT := [Vector2(-505, -40), Vector2(62, 78)]
const QUARRY_BENCH := 4.25
## The bridge sites: [river name, along the river's x (or z for "east"), deck width].
const BRIDGES := [["main", -480.0, 9.0], ["main", 0.0, 11.0], ["main", 590.0, 9.0], ["east", -10.0, 9.0]]
const FLATTEN := [
	[MAIN_SPAWN, 110.0],
	[QUARRY, 75.0],
	[OUTPOST, 75.0],
]

## Dirt tracks through the jungle, as points (x, z): kept clear of trees, drawn on the ground.
const TRACKS := [
	[Vector2(0, 640), Vector2(0, 560), Vector2(0, 482), Vector2(0, 400), Vector2(0, 260), Vector2(0, 100)],
	[Vector2(-50, 650), Vector2(-250, 610), Vector2(-420, 560), Vector2(-480, 510), Vector2(-480, 430), Vector2(-470, 260),
			Vector2(-450, 90), Vector2(-440, 0)],
	[Vector2(50, 650), Vector2(280, 615), Vector2(500, 560), Vector2(588, 510), Vector2(590, 430), Vector2(585, 250),
			Vector2(565, 90), Vector2(560, 0)],
	[Vector2(100, 0), Vector2(260, -6), Vector2(372, -10), Vector2(470, -24), Vector2(520, -40)],
	[Vector2(-100, 0), Vector2(-260, -18), Vector2(-390, -40)],
	[Vector2(40, -280), Vector2(150, -400), Vector2(200, -500), Vector2(170, -580), Vector2(80, -640), Vector2(40, -650)],
	[Vector2(-440, -100), Vector2(-390, -290), Vector2(-290, -460), Vector2(-190, -580), Vector2(-90, -650)],
]

static var _curves := {}
static var _bridges: Array = []


## The river `name` as a dense polyline (x, z): its points smoothed (Catmull-Rom), about every 6 m.
static func river_curve(name: String) -> PackedVector2Array:
	if _curves.has(name):
		return _curves[name]
	var pts: Array = []
	for r in RIVERS:
		if r[0] == name:
			pts = r[2]
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		var steps := maxi(int(p1.distance_to(p2) / 6.0), 2)
		for k in steps:
			var t := float(k) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[-1])
	_curves[name] = out
	return out


static func river_width(name: String) -> float:
	for r in RIVERS:
		if r[0] == name:
			return r[1]
	return 0.0


## The point of river `name` crossing the line x = `at` (z = `at` for the north-south "east" river),
## and the river's direction there (x, z).
static func river_crossing(name: String, at: float) -> Array:
	var c := river_curve(name)
	var along_z := name == "east"
	for i in c.size() - 1:
		var a := c[i].y if along_z else c[i].x
		var b := c[i + 1].y if along_z else c[i + 1].x
		if (a - at) * (b - at) <= 0.0 and a != b:
			var t := (at - a) / (b - a)
			return [c[i].lerp(c[i + 1], t), (c[i + 1] - c[i]).normalized()]
	return [c[0], (c[1] - c[0]).normalized()]


## The bridges as [centre (x, z), along (unit x, z, across the river), length, width].
static func bridges() -> Array:
	if not _bridges.is_empty():
		return _bridges
	var out := []
	for b in BRIDGES:
		var cross := river_crossing(b[0], b[1])
		var dir: Vector2 = cross[1]
		var along := Vector2(-dir.y, dir.x)
		out.append([cross[0], along, river_width(b[0]) + BANK * 2.0 + 6.0, b[2]])
	_bridges = out
	return out


## Distance from p to the nearest track (m).
static func track_dist(p: Vector2) -> float:
	var best := INF
	for t in TRACKS:
		for i in t.size() - 1:
			best = minf(best, seg_dist(p, t[i], t[i + 1]))
	return best


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Distance from p to the segment a-b.
static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Elliptical distance (1 on the rim) of p from an ellipse at c with radii r turned by yaw.
static func ellipse_d(p: Vector2, c: Vector2, r: Vector2, yaw := 0.0) -> float:
	var d := (p - c).rotated(-yaw)
	return Vector2(d.x / r.x, d.y / r.y).length()
