class_name StrongholdInterior
extends RefCounted
## Dresses the inside of the stronghold (stronghold.glb's bare boolean-cut concrete): lights, steel, pipes,
## paint, signs and the deco models (game/assets/stronghold/deco, Meshy props: consoles, lockers, gas bottles,
## generators, crates, radios, conduit panels, blowers and machinery). Built once per bunker face, in the face's
## own frame (the model's Face_S/E/N/W nodes: x along the face, y up, z = -depth from the face's front), so the
## four faces are dressed alike but not the same (each face's props are shuffled by its own seed and it has its
## own colour: the bands along its corridors).
##
## - Floors: a concrete slab over the ground or the rock under every hall, corridor, ring and tunnel (the spawn halls'
##   a raised floor of its own, see HALL_TOP).
## - The spawn halls: steel A-frames up both slopes every 6 m with a collar tie each, a pendant lamp hanging from
##   every tie (and a fill under it), pipes along the slopes, conduit runs between the frames, handrails up the
##   spawn ramps, crates, gas bottles, generators and lockers along both walls, a console against the far end wall
##   under a blower, walkway lines and hazard stripes at the foot of every spawn ramp, the bays' numbers by the ramps.
## - The core corridors and the corridors from the lifts: steel portal frames, strip lights between them, pipes
##   along the ceiling, kick plates and the face's band along the walls, amber guide studs in the floor, signs.
## - The core hall: steel pilasters, a catwalk round its walls with lamps under it, consoles, lockers and bottles
##   below, blowers, machinery and conduit runs above it, pipes, a beam grid and hanging machinery on the
##   ceiling, floodlights; in the middle a holotable (a turning hologram of the mountain) with four consoles round
##   it.
## - The gun ring and the roof ring: portal frames, a caged lamp between every two, conduit runs on the ceiling,
##   pipes, the face's band, edge lines, striped door frames with a lit sign over every door (DECK / ROOF).
## - Every bay's junction, stair shaft and ground tunnel: a lamp each; a red beacon inside every gate.
##
## What stands on the floor where someone walks collides (a box round it, on the world layer, so the navmesh is
## baked round it); what hangs above head height, lies flat or is flush with a wall doesn't. The lamps cast no
## shadows (but the core hall's floodlights and ring lamp) and fade out with distance; they light the ray-traced GI
## (static, so it is lit once, not every frame): inside the mountain the sky lights nothing, their bounce is the
## only light off the floors and walls. Each part of the dressing is a few multimeshes and one mesh, drawn only from
## within its reach.

const DECO := "res://assets/stronghold/deco/%s.glb"
const FONT := "res://assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf"
## The deco models: [file, its longest side (m), its turn into the frame placement expects (degrees): front +Z,
## top +Y, and for what hangs on a wall its back toward -Z]. The conduit runs are the strips of pipes and wires cut
## out of wall_deco_1-4 (tools/gltf/chop_strip.py): long and low, their pipes already facing +Z, their backs flat.
const MODELS := {
	"console": ["deco_1", 2.0, Vector3.ZERO],
	"locker": ["deco_2", 1.9, Vector3.ZERO],
	"gas": ["misc_deco_1", 1.6, Vector3.ZERO],
	"generator": ["misc_deco_2", 1.3, Vector3.ZERO],
	"crates": ["misc_deco_3", 1.4, Vector3.ZERO],
	"radio": ["misc_deco_4", 0.85, Vector3.ZERO],
	"conduit_1": ["wall_deco_1", 2.2, Vector3.ZERO],
	"conduit_2": ["wall_deco_2", 2.2, Vector3.ZERO],
	"conduit_3": ["wall_deco_3", 2.2, Vector3.ZERO],
	"conduit_4": ["wall_deco_4", 2.2, Vector3.ZERO],
	"blower": ["wall_deco_5", 1.4, Vector3(0, 90, 0)],
	"pod": ["wall_deco_6", 1.5, Vector3(90, 0, 0)],
	"engine": ["wall_deco_7", 1.5, Vector3.ZERO],
}
const CONDUITS := ["conduit_1", "conduit_2", "conduit_3", "conduit_4"]
## What stands along the spawn halls' walls, a run picked at random for each stretch between two ramps.
const RUNS := [["crates", "gas"], ["generator", "crates"], ["gas", "gas", "crates"], ["locker", "gas"],
		["crates", "crates", "generator"], ["gas", "generator", "crates"], ["console", "gas"], ["crates", "locker"]]

const FACES := ["S", "E", "N", "W"]
## Each face's colour: the band along its corridors and rings.
const FACE_COLORS := [Color(0.85, 0.58, 0.05), Color(0.09, 0.3, 0.68), Color(0.68, 0.08, 0.05), Color(0.13, 0.46, 0.16)]
## Pipes: water, gas, fire main.
const BLUE := Color(0.09, 0.26, 0.58)
const YELLOW := Color(0.85, 0.6, 0.05)
const RED := Color(0.62, 0.07, 0.04)
const GREEN := Color(0.14, 0.42, 0.17)
const LINE := Color(0.88, 0.68, 0.08)
## Structural steel (frames, ties, pilasters, beams): painted dark grey.
const STEEL := Color(0.2, 0.21, 0.22)
## Lamps.
const WARM := Color(1.0, 0.78, 0.52)
const AMBER := Color(1.0, 0.7, 0.4)
const COOL := Color(0.82, 0.9, 1.0)
const CYAN := Color(0.25, 0.85, 1.0)
const SIGN_GREEN := Color(0.15, 1.0, 0.35)
const ALARM := Color(1.0, 0.08, 0.04)

## The bunker (tools/blender/build_stronghold.py), in metres, as (x along the face, height, depth from its front).
const BAY := 12.0
const HALL_X := 41.0
## How deep the spawn halls were cut: the foot of their slopes.
const HALL_FLOOR := -0.07
## The floors: the halls, corridors and tunnels at the ground's level stand on the ground itself (the bunker was cut
## down through its own slab), the rings and the core on the mountain's rock; every floor gets a concrete slab, its
## top this far over the floor it covers (what stands on it stands on the slab).
const FLOOR := 0.012
const SLAB := 0.08
## The spawn halls' floor is the mountain's rock, rising from about 0.15 m at their front to 0.28 m at their back (and
## the ground where there is none): their slab is a floor of its own, its top this high, that collides (and the navmesh
## is baked on it). It runs down to the core corridor's floor on a ramp HALL_RAMP long.
const HALL_TOP := 0.3
const HALL_RAMP := 3.0
const HALL_FRONT := 15.4
const HALL_BACK := 23.8
const HALL_APEX := Vector2(19.95, 5.95)
const RAMP_X := Vector2(3.5, 5.5)
const RAMP_FOOT := 20.5
const CORRIDOR_HALF := 2.0
const CORRIDOR_H := 3.5
const CORE_D := 78.0
const CORE_HALF := 14.0
const CORE_H := 9.0
const DECK_Z := 8.05
const ROOF_Z := 15.05
const RING_D := Vector2(16.0, 19.0)
const RING_H := 3.0
const RING_RUN := 44.0
const CORNER_B := Vector2(60.5, 34.0)
const LIFT := Vector2(49.35086, 28.64914)
const C_BAYS := [0, 3, 6]
const TUNNEL_X := Vector2(-5.5, -2.5)
const TUNNEL_H := 2.8
const JUNCTION_Z := 2.8
const DOOR_H := 2.2

## A lamp is drawn fully out to this far from the camera and gone this much further on.
const LIGHT_FADE := 45.0
const LIGHT_FADE_LENGTH := 15.0

const GLOW_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float energy = 6.0;
void fragment() {
	ALBEDO = COLOR.rgb * 0.12;
	ROUGHNESS = 0.35;
	EMISSION = COLOR.rgb * COLOR.a * energy;
}
"""
## The holotable's hologram: light added over what is behind it, bright at its edges, scan lines running up it, a
## flicker, turning slowly; the grid under it in lines.
const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.25, 0.85, 1.0);
uniform float spin = 0.12;
uniform float energy = 1.6;
varying vec3 lp;
void vertex() {
	float a = TIME * spin;
	mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xz = r * VERTEX.xz;
	NORMAL.xz = r * NORMAL.xz;
	lp = VERTEX;
}
void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float scan = 0.6 + 0.4 * sin(lp.y * 70.0 - TIME * 5.0);
	float grid = max(step(0.9, fract(lp.x * 3.0)), step(0.9, fract(lp.z * 3.0)));
	float flat_part = step(abs(lp.y), 0.02);
	float flicker = 0.92 + 0.08 * sin(TIME * 21.0) * sin(TIME * 6.7);
	float k = mix(0.18 + rim * 1.1, 0.06 + grid * 0.9, flat_part);
	ALBEDO = tint * k * scan * flicker * energy;
}
"""

var _jungle := false
var _rng := RandomNumberGenerator.new()
var _font: Font
var _mats := {}
var _mesh := {}
var _size := {}
var _floor_xf := {}
var _wall_xf := {}
## The face being dressed: its letter and colour.
var _key := "S"
var _color := Color.WHITE


## One part of a face's dressing: its node (at `origin`, face-local), the deco models placed in it, its own
## geometry by material, and the boxes that collide.
class Zone:
	var node: Node3D
	var origin := Vector3.ZERO
	var reach := 70.0
	var props := {}
	var geo := {}
	var solids := []


## Dresses the stronghold model `root` (its Face_* nodes).
static func build(root: Node3D, jungle: bool) -> void:
	var b := StrongholdInterior.new()
	b._jungle = jungle
	b._setup()
	for k in FACES.size():
		var face := root.find_child("Face_%s" % FACES[k], true, false) as Node3D
		if face:
			b._dress_face(face, k)


func _setup() -> void:
	_font = load(FONT)
	_mats["metal"] = StrongholdLook.material("Metal", _jungle)
	_mats["dark"] = StrongholdLook.material("ConcreteDark", _jungle)
	_mats["deck"] = StrongholdLook.material("Concrete", _jungle)
	_mats["stripes"] = StrongholdLook.material("HatchStripes", _jungle)
	_mats["paint"] = StrongholdLook.material("Paint", _jungle)
	var glow := ShaderMaterial.new()
	glow.shader = Shader.new()
	glow.shader.code = GLOW_SHADER
	_mats["glow"] = glow
	var holo := ShaderMaterial.new()
	holo.shader = Shader.new()
	holo.shader.code = HOLO_SHADER
	_mats["holo"] = holo
	for key in MODELS:
		var spec: Array = MODELS[key]
		var inst := (load(DECO % spec[0]) as PackedScene).instantiate() as Node3D
		var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != inst:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var raw := Transform3D(Basis.from_euler(spec[2] * PI / 180.0), Vector3.ZERO) * xf
		var box: AABB = raw * mi.mesh.get_aabb()
		var s: float = spec[1] / maxf(box.size.x, maxf(box.size.y, box.size.z))
		raw = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO) * raw
		box = raw * mi.mesh.get_aabb()
		var c := box.get_center()
		_mesh[key] = mi.mesh
		_size[key] = box.size
		_floor_xf[key] = Transform3D(Basis.IDENTITY, Vector3(-c.x, -box.position.y, -c.z)) * raw
		_wall_xf[key] = Transform3D(Basis.IDENTITY, Vector3(-c.x, -c.y, -box.position.z)) * raw
		inst.free()


func _dress_face(face: Node3D, k: int) -> void:
	_rng.seed = 7919 * (k + 1)
	_key = FACES[k]
	_color = FACE_COLORS[k]
	var z := _zone(face, "SpawnHall", P(0, 3, HALL_APEX.x), 75.0)
	_spawn_hall(z)
	_finish(z)
	z = _zone(face, "CoreCorridor", P(0, 1.75, 43), 55.0)
	_core_corridor(z)
	_finish(z)
	z = _zone(face, "CoreHall", P(0, 4.5, 70), 60.0)
	_core_wall(z)
	_finish(z)
	if k == 0:
		z = _zone(face, "CoreCentre", P(0, 4, CORE_D), 60.0)
		_core_centre(z)
		_finish(z)
	for ring in [[DECK_Z, "DECK", "GunRing"], [ROOF_Z, "ROOF", "RoofRing"]]:
		z = _zone(face, ring[2], P(8, ring[0] + 1.5, 20), 70.0)
		_ring(z, ring[0], ring[1])
		_finish(z)
	z = _zone(face, "Bays", P(0, 6, 8), 70.0)
	_bays(z, k)
	_finish(z)
	z = _zone(face, "LiftCorridor", P(31.7, 1.75, 46.3), 50.0)
	_lift_corridor(z)
	_finish(z)


# ---------------------------------------------------------------- the spaces

## The spawn hall: an A-frame hall the whole length of the face, its floor just under the ground, a ramp coming down
## into it from every bay's junction (through its front slope) and the corridor to the core leaving through the
## middle of its back slope.
func _spawn_hall(z: Zone) -> void:
	var front_n := Vector3(0, -0.6026, -0.798)
	var front_up := Vector3(0, 0.798, -0.6026)
	var back_n := Vector3(0, -0.5394, 0.842)
	var back_up := Vector3(0, 0.842, 0.5394)
	var tie_h := 4.7
	var tie_d := Vector2(_hall_front(tie_h), _hall_back(tie_h))
	var mid_d := (tie_d.x + tie_d.y) * 0.5
	var thick := HALL_TOP + 0.1
	_box(z, "deck", _at(P(0, HALL_TOP - thick * 0.5, (HALL_FRONT + HALL_BACK) * 0.5)), Vector3(HALL_X * 2.0, thick, HALL_BACK - HALL_FRONT),
			Color.WHITE, true)
	# Steel A-frames up both slopes every 6 m (clear of the ramps' openings), a collar tie across each, a pendant lamp
	# hanging from every tie.
	for i in 14:
		var x := -39.0 + 6.0 * i
		var foot_f := P(x, HALL_FLOOR, HALL_FRONT)
		var foot_b := P(x, HALL_FLOOR, HALL_BACK)
		var apex := P(x, HALL_APEX.y, HALL_APEX.x)
		_box(z, "paint", Transform3D(Basis(Vector3.RIGHT, front_up, Vector3.RIGHT.cross(front_up)),
				(foot_f + apex) * 0.5 + front_n * 0.11), Vector3(0.28, foot_f.distance_to(apex), 0.22), STEEL)
		_box(z, "paint", Transform3D(Basis(Vector3.RIGHT, back_up, Vector3.RIGHT.cross(back_up)),
				(foot_b + apex) * 0.5 + back_n * 0.11), Vector3(0.28, foot_b.distance_to(apex), 0.22), STEEL)
		_box(z, "paint", _at(P(x, tie_h, mid_d)), Vector3(0.22, 0.26, tie_d.y - tie_d.x), STEEL)
		_pipe(z, "metal", P(x, tie_h - 0.13, mid_d), P(x, 4.02, mid_d), 0.018, Color.WHITE, 6)
		_pipe(z, "metal", P(x, 3.84, mid_d), P(x, 4.04, mid_d), 0.3, Color.WHITE, 16)
		_pipe(z, "glow", P(x, 3.825, mid_d), P(x, 3.84, mid_d), 0.25, Color(WARM, 1.0), 16)
		_spot(z, P(x, 3.8, mid_d), Vector3.DOWN, WARM, 3.2, 7.5, 62.0, false, true)
		# The slopes face down: only light from below their top reaches them. A fill under the lamp lights them, the
		# frames and what stands along the walls.
		_omni(z, P(x, 3.0, mid_d), WARM, 0.9, 6.5)
	# Pipes along the back slope (on the frames) and one high up the front slope, over the ramps' openings.
	var runs := [[3.85, 0.13, BLUE], [4.15, 0.09, Color.WHITE], [4.45, 0.07, GREEN]]
	for r in runs:
		var off: float = 0.24 + r[1]
		var key := "metal" if r[2] == Color.WHITE else "paint"
		var a := P(-HALL_X, r[0], _hall_back(r[0])) + back_n * off
		_pipe(z, key, a, a + Vector3(HALL_X * 2.0, 0, 0), r[1], r[2])
	var fa := P(-HALL_X, 5.25, _hall_front(5.25)) + front_n * 0.34
	_pipe(z, "paint", fa, fa + Vector3(HALL_X * 2.0, 0, 0), 0.1, Color(0.8, 0.25, 0.03))
	# Handrails up both sides of every spawn ramp, where it stands out in the hall: the hall's floor comes within a step
	# of a ramp's side near its foot, and a ramp is walked onto from its foot only (they collide).
	var open_d := 16.8
	for i in 7:
		var cx := _bay(i)
		for side_x in [cx + RAMP_X.x - 0.04, cx + RAMP_X.y + 0.04]:
			if absf(side_x) > HALL_X - 0.2:
				continue
			var lo := P(side_x, _ramp_h(RAMP_FOOT - 0.1) + 1.0, RAMP_FOOT - 0.1)
			var hi := P(side_x, _ramp_h(open_d) + 1.0, open_d)
			_pipe(z, "paint", lo, hi, 0.035, YELLOW, 8)
			_pipe(z, "paint", lo - Vector3(0, 0.5, 0), hi - Vector3(0, 0.5, 0), 0.025, YELLOW, 8)
			for k in 4:
				var d := lerpf(RAMP_FOOT - 0.1, open_d, k / 3.0)
				_box(z, "paint", _at(P(side_x, (HALL_TOP + _ramp_h(d) + 1.0) * 0.5, d)), Vector3(0.05, _ramp_h(d) + 1.0 - HALL_TOP, 0.05), YELLOW)
			_solid_box(z, _at(P(side_x, (HALL_TOP + _ramp_h(open_d) + 1.0) * 0.5, (RAMP_FOOT + open_d) * 0.5)),
					Vector3(0.06, _ramp_h(open_d) + 1.0 - HALL_TOP, RAMP_FOOT - open_d))
	# Walkway lines down the hall, hazard stripes at the foot of every ramp, the bay's number beside it.
	for d in [17.55, 22.15]:
		_box(z, "paint", _at(P(0, HALL_TOP + 0.003, d)), Vector3(HALL_X * 2.0, 0.006, 0.09), LINE)
	for i in 7:
		var cx := _bay(i)
		_box(z, "stripes", _at(P(cx + 4.5, HALL_TOP + 0.003, RAMP_FOOT + 0.3)), Vector3(2.0, 0.006, 0.45))
		_label(z, "%s%d" % [_key, i + 1], P(cx + 6.5, 2.35, _hall_front(2.35)) + front_n * 0.02, front_n, front_up, 0.5)
		_label(z, "DECK ↑", P(cx + 6.5, 1.85, _hall_front(1.85)) + front_n * 0.02, front_n, front_up, 0.2)
	_label(z, "↓  CORE  ↓", P(0, 4.15, _hall_back(4.15)) + back_n * 0.02, back_n, back_up, 0.32)
	# Conduit runs high on both slopes, along the hall between the frames, their pipes facing out.
	for i in 7:
		var cx := _bay(i)
		var xb := cx - 1.5
		if absf(xb) > 3.0:
			_mount(z, _pick(CONDUITS), P(xb, 3.05, _hall_back(3.05)), back_n, back_up)
		if i < 6:
			_mount(z, _pick(CONDUITS), P(cx + 12.0, 3.25, _hall_front(3.25)), front_n, front_up)
	# What stands along the walls: a run of props on every stretch between two ramps (a metre clear of the ramps' sides:
	# whoever walks up one near its edge must not catch on what stands beside it; clear of where the ramps come down and
	# of the corridor to the core), each set into the slope as far as its top lets it.
	var front_spans := [Vector2(-HALL_X + 1.6, _bay(0) + RAMP_X.x - 1.0)]
	var back_spans := [Vector2(-HALL_X + 1.6, _bay(0) + 2.5)]
	for i in 6:
		var cx := _bay(i)
		front_spans.append(Vector2(cx + RAMP_X.y + 1.0, cx + BAY + RAMP_X.x - 1.0))
		# Everyone coming out of the corridor from the core fans out from its mouth to the ramps (past the squads
		# posted in the hall): the back wall stays clear for 6 m either side of it.
		var span := Vector2(cx + 6.5, cx + 14.5)
		if span.y > -6.0 and span.x < 6.0:
			if span.x < -6.0:
				back_spans.append(Vector2(span.x, -6.0))
			if span.y > 6.0:
				back_spans.append(Vector2(6.0, span.y))
		else:
			back_spans.append(span)
	for span in front_spans:
		_fill(z, span, true)
	for span in back_spans:
		_fill(z, span, false)
	# The end walls: the hall's name, a radio, a lamp on them; at the far end (x -) a console under the name and a
	# blower above it. The last bay's spawn ramp comes down against the near end's wall (x +): nothing stands there.
	for s in [-1.0, 1.0]:
		var wall_x: float = s * HALL_X
		var inward := Vector3(-s, 0, 0)
		if s < 0.0:
			var depth: float = _size["console"].z
			_stand(z, "console", P(wall_x - s * (depth * 0.5 + 0.05), HALL_TOP, 19.9), inward)
			_mount(z, "blower", P(wall_x, 3.65, 19.9), inward, Vector3.UP)
			_mount(z, "radio", P(wall_x, 1.45, 17.7), inward, Vector3.UP)
		_label(z, "SPAWN HALL %s" % _key, P(wall_x - s * 0.02, 2.3 if s < 0.0 else 4.6, 19.9), inward, Vector3.UP, 0.3)
		_mount(z, "radio", P(wall_x, 1.45, 22.1), inward, Vector3.UP)
		_spot(z, P(wall_x - s * 2.5, 4.3, 19.9), Vector3(s * 2.5, -2.3, 0), AMBER, 2.0, 6.0, 45.0)


## The corridor from the spawn hall to the core hall, straight in under the mountain.
func _core_corridor(z: Zone) -> void:
	var d0 := 21.6
	var d1 := CORE_D - CORE_HALF
	var length := d1 - d0
	var mid := (d0 + d1) * 0.5
	# Down from the spawn hall's floor on a ramp (striped at its top), then a slab to the core hall.
	var rise := HALL_TOP - FLOOR
	var slope := atan2(rise, HALL_RAMP)
	var ramp_mid := P(0, FLOOR + rise * 0.5, HALL_BACK + HALL_RAMP * 0.5)
	var down := Basis(Vector3.RIGHT, -slope)
	_box(z, "deck", Transform3D(down, ramp_mid + down * Vector3(0, -0.15, 0)), Vector3(CORRIDOR_HALF * 2.0, 0.3, HALL_RAMP / cos(slope) + 0.02),
			Color.WHITE, true)
	_box(z, "stripes", Transform3D(down, ramp_mid + down * Vector3(0, 0.003, -HALL_RAMP * 0.5 + 0.25)), Vector3(CORRIDOR_HALF * 2.0, 0.006, 0.45))
	_slab(z, P(0, 0, (HALL_BACK + HALL_RAMP + d1) * 0.5), Vector2(CORRIDOR_HALF * 2.0, d1 - HALL_BACK - HALL_RAMP))
	for s in [-1.0, 1.0]:
		var wx: float = s * CORRIDOR_HALF
		_box(z, "metal", _at(P(wx - s * 0.015, 0.15, mid)), Vector3(0.03, 0.3, length))
		_box(z, "paint", _at(P(wx - s * 0.006, 1.15, mid)), Vector3(0.012, 0.16, length), _color)
		var d := d0 + 1.4
		while d < d1:
			_box(z, "glow", _at(P(wx - s * 0.2, FLOOR + 0.006, d)), Vector3(0.06, 0.012, 0.16), Color(1.0, 0.5, 0.08, 0.6))
			d += 2.0
	# Striped door frames at both ends.
	for d in [d0 + 0.25, d1 - 0.2]:
		_door_frame(z, P(0, FLOOR, d), Vector3.RIGHT, CORRIDOR_HALF * 2.0 - 0.2, CORRIDOR_H, 0.3)
	# Steel portal frames every 6 m, a strip light between every two.
	for i in 7:
		var d := 26.0 + 6.0 * i
		for s in [-1.0, 1.0]:
			_box(z, "paint", _at(P(s * (CORRIDOR_HALF - 0.07), CORRIDOR_H * 0.5, d)), Vector3(0.14, CORRIDOR_H, 0.3), STEEL, true)
		_box(z, "paint", _at(P(0, CORRIDOR_H - 0.11, d)), Vector3(CORRIDOR_HALF * 2.0, 0.22, 0.3), STEEL)
	for d in [23.3, 29.0, 35.0, 41.0, 47.0, 53.0, 59.0]:
		_strip_light(z, P(0, CORRIDOR_H, d), Vector3.FORWARD, 1.4, COOL, 2.8, 5.5)
	# Pipes along the ceiling: water and gas on one side, the fire main on the other.
	_pipe(z, "paint", P(1.5, 3.1, d0), P(1.5, 3.1, d1), 0.12, BLUE)
	_pipe(z, "metal", P(1.15, 3.22, d0), P(1.15, 3.22, d1), 0.07)
	_pipe(z, "paint", P(-1.55, 3.15, d0), P(-1.55, 3.15, d1), 0.1, RED)
	# Conduit runs high on the walls between the frames, on either wall in turn.
	for i in 6:
		var s := 1.0 if i % 2 == 0 else -1.0
		_mount(z, _pick(CONDUITS), P(s * CORRIDOR_HALF, 2.45, 29.0 + 6.0 * i), Vector3(-s, 0, 0), Vector3.UP, 2.0 / 2.2)
	# Signs both ways, radios on the walls, a few crates and bottles by the core end.
	for d in [30.0, 42.0, 54.0]:
		_label(z, "←  CORE   ·   SPAWN HALL %s  →" % _key, P(CORRIDOR_HALF - 0.01, 1.55, d), Vector3.LEFT, Vector3.UP, 0.16)
		_label(z, "←  SPAWN HALL %s   ·   CORE  →" % _key, P(-CORRIDOR_HALF + 0.01, 1.55, d), Vector3.RIGHT, Vector3.UP, 0.16)
	_mount(z, "radio", P(CORRIDOR_HALF, 1.5, 36.0), Vector3.LEFT, Vector3.UP)
	_mount(z, "radio", P(-CORRIDOR_HALF, 1.5, 48.0), Vector3.RIGHT, Vector3.UP)
	_stand(z, "crates", P(CORRIDOR_HALF - _size["crates"].z * 0.5 - 0.04, FLOOR, 59.2), Vector3.LEFT)
	_stand(z, "gas", P(CORRIDOR_HALF - _size["gas"].z * 0.5 - 0.04, FLOOR, 60.65), Vector3.LEFT)
	_stand(z, "generator", P(-CORRIDOR_HALF + _size["generator"].z * 0.5 + 0.04, FLOOR, 59.9), Vector3.RIGHT)


## The core hall's wall facing this face (the corridor from the spawn hall comes in through its middle; the
## corridors from the lifts cut its corners), and its quarter of the ceiling.
func _core_wall(z: Zone) -> void:
	var wd := CORE_D - CORE_HALF
	var edge := CORE_HALF - 2.15
	var into := Vector3.FORWARD
	# Pilasters and a beam along the top of the wall.
	for x in [-11.6, -7.25, -2.35, 2.35, 7.25, 11.6]:
		_box(z, "paint", _at(P(x, CORE_H * 0.5, wd + 0.175)), Vector3(0.4, CORE_H, 0.35), STEEL, true)
	_box(z, "paint", _at(P(0, CORE_H - 0.2, wd + 0.175)), Vector3(edge * 2.0, 0.4, 0.35), STEEL)
	# The catwalk along the wall, 4.5 m up: grating, a striped fascia, a railing, braces under it, lamps under it.
	var cw := 4.5
	var depth := 1.3
	_box(z, "metal", _at(P(0, cw, wd + depth * 0.5)), Vector3(edge * 2.0, 0.08, depth))
	_box(z, "stripes", _at(P(0, cw - 0.1, wd + depth)), Vector3(edge * 2.0, 0.25, 0.04))
	var rail_d := wd + depth - 0.05
	_pipe(z, "metal", P(-edge, cw + 1.05, rail_d), P(edge, cw + 1.05, rail_d), 0.03)
	_pipe(z, "metal", P(-edge, cw + 0.55, rail_d), P(edge, cw + 0.55, rail_d), 0.02)
	var x := -edge
	while x <= edge + 0.01:
		_box(z, "metal", _at(P(x, cw + 0.55, rail_d)), Vector3(0.05, 1.0, 0.05))
		x += 1.95
	for px in [-11.6, -7.25, -2.35, 2.35, 7.25, 11.6]:
		_pipe(z, "metal", P(px, cw - 0.9, wd + 0.35), P(px, cw - 0.05, wd + depth - 0.1), 0.05)
	for lx in [-9.6, -5.0, 5.0, 9.6]:
		_box(z, "glow", _at(P(lx, cw - 0.05, wd + 0.8)), Vector3(1.2, 0.02, 0.14), Color(WARM, 1.0))
		_spot(z, P(lx, cw - 0.1, wd + 0.8), Vector3(0, -1, -0.25), WARM, 3.0, 6.5, 62.0)
	# Below: consoles either side of the way in, then bottles, crates or a locker toward the corners.
	for s in [-1.0, 1.0]:
		_stand(z, "console", P(s * 5.0, FLOOR, wd + 0.05 + _size["console"].z * 0.5), into)
		if _rng.randf() < 0.5:
			_stand(z, "gas", P(s * 8.1, FLOOR, wd + 0.05 + _size["gas"].z * 0.5), into)
			_stand(z, "crates", P(s * 9.75, FLOOR, wd + 0.05 + _size["crates"].z * 0.5), into)
		else:
			_stand(z, "locker", P(s * 8.4, FLOOR, wd + 0.05 + _size["locker"].z * 0.5), into)
			_stand(z, "generator", P(s * 10.4, FLOOR, wd + 0.05 + _size["generator"].z * 0.5), into)
		_mount(z, "radio", P(s * 3.2, 1.5, wd), into, Vector3.UP)
	# Above the catwalk: blowers, machinery over the way in, conduit runs toward the corners.
	for s in [-1.0, 1.0]:
		_mount(z, "blower", P(s * 5.0, 6.9, wd), into, Vector3.UP)
		_mount(z, _pick(CONDUITS), P(s * 9.5, 7.0, wd), into, Vector3.UP, 2.6 / 2.2)
	_mount(z, "engine", P(0, 6.9, wd), into, Vector3.UP)
	_label(z, "SECTOR %s" % _key, P(0, 3.95, wd + 0.02), into, Vector3.UP, 0.42)
	_box(z, "stripes", _at(P(0, FLOOR + 0.003, wd + 0.45)), Vector3(CORRIDOR_HALF * 2.0, 0.006, 0.5))
	# Pipes along the top of the wall, two coming down beside the way in.
	_pipe(z, "paint", P(-edge, 8.3, wd + 0.52), P(edge, 8.3, wd + 0.52), 0.15, RED)
	_pipe(z, "paint", P(-edge, 8.0, wd + 0.47), P(edge, 8.0, wd + 0.47), 0.1, YELLOW)
	for s in [-1.0, 1.0]:
		_pipe(z, "paint", P(s * 3.2, 0, wd + 0.45), P(s * 3.2, 8.0, wd + 0.45), 0.1, BLUE)
		_pipe(z, "metal", P(s * 3.2, 0.9, wd + 0.45), P(s * 3.2, 1.05, wd + 0.45), 0.16)
	# The ceiling: a beam across (the four faces' beams make a square round the middle), machinery hanging either
	# side, a floodlight aimed at the holotable.
	_box(z, "paint", _at(P(0, CORE_H - 0.22, 71.0)), Vector3(CORE_HALF * 2.0, 0.45, 0.3), STEEL)
	_mount(z, "pod", P(-6.5, CORE_H, 68.5), Vector3.DOWN, Vector3.RIGHT)
	_mount(z, "engine", P(6.5, CORE_H, 68.5), Vector3.DOWN, Vector3.FORWARD)
	_box(z, "metal", _at(P(0, CORE_H - 0.55, 71.6)), Vector3(0.9, 0.3, 0.6))
	_box(z, "glow", Transform3D(Basis(Vector3.RIGHT, -0.8), P(0, CORE_H - 0.72, 71.85)), Vector3(0.75, 0.02, 0.45), Color(COOL, 1.0))
	_spot(z, P(0, CORE_H - 0.8, 72.0), P(0, 1.0, CORE_D) - P(0, CORE_H - 0.8, 72.0), COOL, 5.0, 16.0, 30.0, true)


## The middle of the core hall: the holotable, the consoles round it and the ring lamp over it.
func _core_centre(z: Zone) -> void:
	var c := P(0, FLOOR, CORE_D)
	_slab(z, P(0, 0, CORE_D), Vector2(CORE_HALF * 2.0, CORE_HALF * 2.0))
	_ring_floor(z, c, 3.6, 0.12, LINE)
	_ring_floor(z, c, 6.2, 0.1, LINE)
	_pipe(z, "dark", c, c + Vector3(0, 0.95, 0), 2.2, Color.WHITE, 32)
	_pipe(z, "metal", c + Vector3(0, 0.95, 0), c + Vector3(0, 1.02, 0), 2.3, Color.WHITE, 32)
	_pipe(z, "glow", c + Vector3(0, 0.84, 0), c + Vector3(0, 0.9, 0), 2.23, Color(CYAN, 1.0), 32)
	_solid_box(z, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.5, 0)), Vector3(4.4, 1.0, 4.4))
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var out := Vector3(sin(a), 0, cos(a))
		_stand(z, "console", c + out * 4.4, -out)
	# The hologram: the mountain as a pyramid, a bunker on each face, a grid under it.
	var holo := Zone.new()
	holo.origin = Vector3.ZERO
	var top := Vector3(0, 1.25, 0)
	var base := [Vector3(1.3, 0, 0), Vector3(0, 0, 1.3), Vector3(-1.3, 0, 0), Vector3(0, 0, -1.3)]
	for k in 4:
		var a: Vector3 = base[k]
		var b: Vector3 = base[(k + 1) % 4]
		_tri(_tool(holo, "holo"), [a, b, top], [(a + b).normalized(), (a + b).normalized(), Vector3.UP], Color.WHITE)
	for k in 4:
		var dir: Vector3 = (base[k] + base[(k + 1) % 4]).normalized()
		_box(holo, "holo", Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), dir * 1.05 + Vector3(0, 0.12, 0)), Vector3(0.9, 0.24, 0.3))
	_box(holo, "holo", Transform3D.IDENTITY, Vector3(3.6, 0.002, 3.6))
	var mi := MeshInstance3D.new()
	mi.mesh = _commit(holo)
	mi.position = c + Vector3(0, 1.12, 0) - z.origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	z.node.add_child(mi)
	_omni(z, c + Vector3(0, 2.2, 0), CYAN, 2.4, 9.0)
	# Overhead: a ring lamp on four hangers round machinery on the ceiling, a spot down the middle.
	var ring_h := CORE_H - 0.6
	var seg := 32
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		_pipe(z, "glow", c + Vector3(sin(a0) * 2.8, ring_h, cos(a0) * 2.8), c + Vector3(sin(a1) * 2.8, ring_h, cos(a1) * 2.8),
				0.06, Color(COOL, 1.0), 6)
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var p := c + Vector3(sin(a) * 2.8, 0, cos(a) * 2.8)
		_pipe(z, "metal", p + Vector3(0, ring_h, 0), p + Vector3(0, CORE_H, 0), 0.025, Color.WHITE, 6)
	_mount(z, "engine", c + Vector3(0, CORE_H, 0), Vector3.DOWN, Vector3.FORWARD, 1.2)
	_spot(z, c + Vector3(0, ring_h - 0.2, 0), Vector3.DOWN, COOL, 3.0, 12.0, 48.0, true)


## A ring (the gun ring at the gun deck's level, or the roof ring at the roof's) behind the face: its straight run
## and the diagonal round the corner to the next face, the landing off it to the corner's lift.
func _ring(z: Zone, h0: float, tag: String) -> void:
	var col := AMBER if tag == "DECK" else COOL
	var mid_d := (RING_D.x + RING_D.y) * 0.5
	var t := Vector3(0.7071, 0, -0.7071)
	var ca := Vector3(RING_RUN, 0, -mid_d)
	var cb := Vector3(CORNER_B.x, 0, -CORNER_B.y)
	var corner := (ca + cb) * 0.5
	var lift := Vector3(LIFT.x, 0, -LIFT.y)
	var inward := (lift - corner).normalized()
	var door_at := lift - inward * 2.0
	# Slabs over the floor (the straight run, the diagonal a hair lower where they overlap at the corner, the landing).
	_slab(z, P(0, h0, mid_d), Vector2(RING_RUN * 2.0 + 1.3, RING_D.y - RING_D.x))
	_slab(z, (ca + cb) * 0.5 + Vector3(0, h0 - 0.003, 0), Vector2(RING_D.y - RING_D.x, ca.distance_to(cb) + 1.3), atan2(t.x, t.z))
	_slab(z, corner.lerp(door_at, 0.5) + Vector3(0, h0 - 0.006, 0) - inward * 0.4, Vector2(2.5, corner.distance_to(door_at) + 0.8),
			atan2(inward.x, inward.z))
	# Lines along both edges of the floor, pipes along the inner wall's top.
	for o in [-1.38, 1.38]:
		_polyline(z, "paint", _ring_line(o, h0 + FLOOR + 0.003), Vector2(0.06, 0.006), LINE)
	_polyline_pipe(z, "paint", _ring_line(1.1, h0 + 2.72), 0.1, BLUE if tag == "DECK" else GREEN)
	_polyline_pipe(z, "metal", _ring_line(0.85, h0 + 2.82), 0.06, Color.WHITE)
	# The straight run: kick plates and the face's band, portal frames, a lamp between every two, conduit runs on
	# the ceiling.
	var doors := []
	for i in 7:
		var cx := _bay(i)
		doors.append(Vector2(cx + 4.1, cx + 5.5) if tag == "DECK" else Vector2(cx - 1.0, cx + 1.0))
	for s in [-1.0, 1.0]:
		var wd: float = mid_d + s * 1.5
		# The front wall's bands stop at its doors.
		var from := -RING_RUN
		for door in (doors if s < 0.0 else []) + [Vector2(RING_RUN, RING_RUN)]:
			var to: float = door.x - (0.16 if door.x < RING_RUN else 0.0)
			if to > from:
				_box(z, "metal", _at(P((from + to) * 0.5, h0 + 0.15, wd - s * 0.015)), Vector3(to - from, 0.3, 0.03))
				_box(z, "paint", _at(P((from + to) * 0.5, h0 + 1.15, wd - s * 0.006)), Vector3(to - from, 0.16, 0.012), _color)
			from = door.y + 0.16
	for i in 14:
		var x := -39.0 + 6.0 * i
		for s in [-1.0, 1.0]:
			_box(z, "paint", _at(P(x, h0 + RING_H * 0.5, mid_d + s * 1.43)), Vector3(0.3, RING_H, 0.14), STEEL, true)
		_box(z, "paint", _at(P(x, h0 + RING_H - 0.1, mid_d)), Vector3(0.3, 0.2, 3.0), STEEL)
	for i in 15:
		_strip_light(z, P(-42.0 + 6.0 * i, h0 + RING_H, mid_d), Vector3.RIGHT, 0.5, col, 2.8, 4.8)
	for i in 7:
		var cx := _bay(i)
		_mount(z, CONDUITS[(i + int(h0)) % 4], P(cx + 1.65, h0 + RING_H, RING_D.x + 0.65), Vector3.DOWN, Vector3.FORWARD, 0.6)
		# The doors through the front wall (from every bay's stair landing onto the gun ring; from the roof onto the roof
		# ring): a striped frame, a lit sign over it, the bay on the wall facing it.
		var door: Vector2 = doors[i]
		var dx := (door.x + door.y) * 0.5
		_door_frame(z, P(dx, h0, RING_D.x + 0.06), Vector3.RIGHT, door.y - door.x, DOOR_H, 0.12)
		_box(z, "glow", _at(P(dx, h0 + 2.55, RING_D.x + 0.03)), Vector3(0.6, 0.18, 0.04), Color(SIGN_GREEN, 0.7))
		_label(z, tag, P(dx, h0 + 2.55, RING_D.x + 0.055), Vector3.FORWARD, Vector3.UP, 0.12, Color(0.02, 0.08, 0.03))
		_label(z, "%s  %s%d" % [tag, _key, i + 1], P(dx, h0 + 1.7, RING_D.y - 0.01), Vector3.BACK, Vector3.UP, 0.2)
		if i % 2 == 0:
			_mount(z, "radio", P(cx - 1.6, h0 + 1.5, RING_D.y), Vector3.BACK, Vector3.UP)
	# The diagonal round the corner: lamps, and the landing off it to the lift.
	for s in [0.25, 0.75]:
		_strip_light(z, ca.lerp(cb, s) + Vector3(0, h0 + RING_H, 0), t, 0.5, col, 2.8, 4.8)
	_box(z, "stripes", Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), door_at + Vector3(0, h0 + FLOOR + 0.003, 0) - inward * 0.3),
			Vector3(2.4, 0.006, 0.45))
	_box(z, "glow", Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), corner.lerp(door_at, 0.5) + Vector3(0, h0 + DOOR_H - 0.02, 0)),
			Vector3(1.2, 0.02, 0.18), Color(AMBER, 1.0))
	_spot(z, corner.lerp(door_at, 0.5) + Vector3(0, h0 + DOOR_H - 0.06, 0), Vector3.DOWN, AMBER, 1.6, 3.2, 70.0)


## Every bay's ways up: the junction where its ramps meet, its stair shaft, and (in the bays that have one) its
## ground tunnel and the ramp up from it; a red beacon inside the gate.
func _bays(z: Zone, k: int) -> void:
	for i in 7:
		var cx := _bay(i)
		var jx := cx + (RAMP_X.x + RAMP_X.y) * 0.5
		_strip_light(z, P(jx, JUNCTION_Z + 3.0, 11.85), Vector3.RIGHT, 0.6, WARM, 1.8, 4.6)
		_omni(z, P(cx + 1.85, 11.0, 14.4), WARM, 1.1, 3.6)
		if i in C_BAYS:
			var tx := cx + (TUNNEL_X.x + TUNNEL_X.y) * 0.5
			# The rock under the tunnel rises to 0.1 m at its back: the slab rises with it, just over it (it doesn't
			# collide: the gate's links stay as they were).
			var rise := 0.106
			var run := 12.3
			var tilt := Basis(Vector3.RIGHT, atan2(rise, run))
			var top := P(tx, FLOOR + rise * 0.5, -0.8 + run * 0.5)
			_box(z, "deck", Transform3D(tilt, top + tilt * Vector3(0, -SLAB * 0.5, 0)), Vector3(TUNNEL_X.y - TUNNEL_X.x, SLAB, run))
			for d in [2.0, 6.5]:
				_strip_light(z, P(tx, TUNNEL_H, d), Vector3.FORWARD, 0.8, WARM, 1.6, 3.6)
			_strip_light(z, P(cx + 0.5, 4.4, 10.0), Vector3.RIGHT, 0.6, WARM, 1.6, 4.0)
			_box(z, "stripes", Transform3D(tilt, P(tx, FLOOR + rise * 1.25 / run + 0.004, 0.45)), Vector3(TUNNEL_X.y - TUNNEL_X.x, 0.006, 0.5))
			if i + 1 == LevelBuilder.GATE_BAY and _has_gate(FACES[k]):
				var at := P(tx + 1.2, TUNNEL_H - 0.2, 0.3)
				_box(z, "metal", _at(at + Vector3(0, 0.12, 0)), Vector3(0.24, 0.08, 0.24))
				_pipe(z, "glow", at - Vector3(0, 0.12, 0), at + Vector3(0, 0.08, 0), 0.09, Color(ALARM, 1.0), 10)
				_omni(z, at - Vector3(0, 0.3, 0), ALARM, 1.2, 4.0)
				_label(z, "GATE %s" % _key, P(cx + TUNNEL_X.x, 1.7, 1.6), Vector3.RIGHT, Vector3.UP, 0.22)


## The corridor from the corner's lift down at ground level, in to the core hall's corner.
func _lift_corridor(z: Zone) -> void:
	var a := Vector3(LIFT.x, 0, -LIFT.y)
	var b := Vector3(CORE_HALF, 0, -(CORE_D - CORE_HALF))
	var u := (b - a).normalized()
	var side := Vector3(-u.z, 0, u.x)
	var yaw := atan2(u.x, u.z)
	var start := a + u * 2.05
	var length := start.distance_to(b)
	var basis := Basis(Vector3.UP, yaw)
	var half := 1.5
	_slab(z, a, Vector2(4.0, 4.0), PI * 0.25)
	var end := b - u * half
	_slab(z, (start + end) * 0.5, Vector2(half * 2.0, start.distance_to(end)), yaw)
	for s in [-1.0, 1.0]:
		var w: Vector3 = side * s * half
		_box(z, "metal", Transform3D(basis, (start + b) * 0.5 + w - side * s * 0.015 + Vector3(0, 0.15, 0)), Vector3(0.03, 0.3, length))
		_box(z, "paint", Transform3D(basis, (start + b) * 0.5 + w - side * s * 0.006 + Vector3(0, 1.15, 0)), Vector3(0.012, 0.16, length), _color)
		var t := 1.0
		while t < length:
			_box(z, "glow", Transform3D(basis, start + u * t + w - side * s * 0.2 + Vector3(0, FLOOR + 0.006, 0)), Vector3(0.06, 0.012, 0.16),
					Color(1.0, 0.5, 0.08, 0.6))
			t += 2.5
	for k in 7:
		var t := 3.0 + 7.0 * k
		_strip_light(z, start + u * t + Vector3(0, CORRIDOR_H, 0), u, 1.2, COOL, 2.0, 5.2)
		if k < 6:
			var f := start + u * (t + 3.5)
			for s in [-1.0, 1.0]:
				_box(z, "paint", Transform3D(basis, f + side * s * (half - 0.07) + Vector3(0, CORRIDOR_H * 0.5, 0)),
						Vector3(0.14, CORRIDOR_H, 0.3), STEEL, true)
			_box(z, "paint", Transform3D(basis, f + Vector3(0, CORRIDOR_H - 0.1, 0)), Vector3(half * 2.0, 0.2, 0.3), STEEL)
	_pipe(z, "paint", start + side * 1.1 + Vector3(0, 3.12, 0), b + side * 1.1 + Vector3(0, 3.12, 0), 0.1, GREEN)
	_pipe(z, "metal", start - side * 1.15 + Vector3(0, 3.22, 0), b - side * 1.15 + Vector3(0, 3.22, 0), 0.07)
	_door_frame(z, b - u * 0.6, side, half * 2.0 - 0.2, CORRIDOR_H, 0.3)
	_label(z, "LIFT %s  ↔  CORE" % _key, start + u * 6.0 + side * (half - 0.01) + Vector3(0, 1.55, 0), -side, Vector3.UP, 0.16)


# ---------------------------------------------------------------- pieces

## Fills a stretch of a spawn hall's wall (front or back) with a run of props, left to right, each set back into
## the slope as far as its height lets it.
func _fill(z: Zone, span: Vector2, front: bool) -> void:
	var run: Array = RUNS[_rng.randi() % RUNS.size()]
	var x := span.x + _rng.randf_range(0.1, 0.6)
	for model in run:
		var size: Vector3 = _size[model]
		if x + size.x > span.y:
			break
		var at := x + size.x * 0.5
		var depth: float
		var facing: Vector3
		if front:
			depth = _hall_front(HALL_TOP + size.y) + 0.05 + size.z * 0.5
			facing = Vector3.FORWARD
		else:
			depth = _hall_back(HALL_TOP + size.y) - 0.05 - size.z * 0.5
			facing = Vector3.BACK
		_stand(z, model, P(at, HALL_TOP, depth), facing.rotated(Vector3.UP, _rng.randf_range(-0.05, 0.05)))
		x += size.x + _rng.randf_range(0.15, 0.7)


## A ceiling lamp: a steel housing with a lit strip under it, `length` long along `along`, its top at `at`, and a
## spot shining down from it.
func _strip_light(z: Zone, at: Vector3, along: Vector3, length: float, col: Color, energy: float, reach: float) -> void:
	var basis := Basis(Vector3.UP, atan2(along.x, along.z))
	_box(z, "metal", Transform3D(basis, at - Vector3(0, 0.045, 0)), Vector3(0.3, 0.09, length + 0.1))
	_box(z, "glow", Transform3D(basis, at - Vector3(0, 0.1, 0)), Vector3(0.18, 0.02, length), Color(col, 1.0))
	_spot(z, at - Vector3(0, 0.13, 0), Vector3.DOWN, col, energy, reach, 72.0)


## A door frame striped in hazard paint round an opening `width` wide and `height` tall, its foot's middle at
## `at`, across `across`.
func _door_frame(z: Zone, at: Vector3, across: Vector3, width: float, height: float, depth: float) -> void:
	var basis := Basis(Vector3.UP, atan2(across.x, across.z) - PI * 0.5)
	for s in [-1.0, 1.0]:
		_box(z, "stripes", Transform3D(basis, at + across * s * (width * 0.5 + 0.08) + Vector3(0, height * 0.5, 0)),
				Vector3(0.16, height, depth), Color.WHITE, true)
	_box(z, "stripes", Transform3D(basis, at + Vector3(0, height + 0.08, 0)), Vector3(width + 0.32, 0.16, depth))


## A painted ring on the floor round `c`.
func _ring_floor(z: Zone, c: Vector3, r: float, w: float, col: Color) -> void:
	var seg := 48
	for k in seg:
		var a := TAU * (k + 0.5) / seg
		_box(z, "paint", Transform3D(Basis(Vector3.UP, a), c + Vector3(sin(a) * r, 0.003, cos(a) * r)),
				Vector3(TAU * r / seg + 0.02, 0.006, w), col)


## The ring's line `o` metres in from its middle (toward the core), at height `h`: the straight run and the diagonal,
## mitred at the corner.
func _ring_line(o: float, h: float) -> Array:
	var mid := (RING_D.x + RING_D.y) * 0.5
	var t := Vector2(0.7071, 0.7071)
	var n := Vector2(-0.7071, 0.7071)
	var c := CORNER_B + n * o - t * (0.4142 * o)
	return [P(-RING_RUN + 0.4142 * o, h, mid + o), P(RING_RUN - 0.4142 * o, h, mid + o), P(c.x, h, c.y)]


func _polyline(z: Zone, key: String, pts: Array, section: Vector2, col: Color) -> void:
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var u := (b - a).normalized()
		_box(z, key, Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), (a + b) * 0.5), Vector3(section.x, section.y, a.distance_to(b)), col)


func _polyline_pipe(z: Zone, key: String, pts: Array, r: float, col: Color) -> void:
	for k in pts.size() - 1:
		_pipe(z, key, pts[k], pts[k + 1], r, col)


## A concrete slab over a floor: `size` (across, along) round `at` (on the floor it covers), turned `yaw`.
func _slab(z: Zone, at: Vector3, size: Vector2, yaw := 0.0) -> void:
	_box(z, "deck", Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, FLOOR - SLAB * 0.5, 0)), Vector3(size.x, SLAB, size.y))


# ---------------------------------------------------------------- placing

## Stands `model` on the floor at `at`, its front toward `facing`, scaled by `k`; what stands where people walk
## collides (`solid`).
func _stand(z: Zone, model: String, at: Vector3, facing: Vector3, k := 1.0, solid := true) -> void:
	var basis := Basis(Vector3.UP, atan2(facing.x, facing.z))
	_add_prop(z, model, Transform3D(basis.scaled(Vector3.ONE * k), at) * _floor_xf[model])
	if solid:
		var size: Vector3 = _size[model] * k
		_solid_box(z, Transform3D(basis, at + Vector3(0, size.y * 0.5, 0)), size * Vector3(0.9, 1.0, 0.9))


## Hangs `model` with its back on a wall or ceiling at `at`, its front out along `normal` and its top toward `up`.
func _mount(z: Zone, model: String, at: Vector3, normal: Vector3, up: Vector3, k := 1.0) -> void:
	var zb := normal.normalized()
	var xb := up.cross(zb).normalized()
	var basis := Basis(xb, zb.cross(xb), zb)
	_add_prop(z, model, Transform3D(basis.scaled(Vector3.ONE * k), at) * _wall_xf[model])


func _add_prop(z: Zone, model: String, xf: Transform3D) -> void:
	if not z.props.has(model):
		z.props[model] = []
	xf.origin -= z.origin
	z.props[model].append(xf)


func _solid_box(z: Zone, xf: Transform3D, size: Vector3) -> void:
	xf.origin -= z.origin
	z.solids.append([xf, size])


## A spot light at `at` shining along `dir`. Only the big lamps (`fog`) light the volumetric fog: every light in it
## costs the fog pass, and the small ones' beams are too short to show in it.
func _spot(z: Zone, at: Vector3, dir: Vector3, col: Color, energy: float, reach: float, angle: float, shadow := false,
		fog := false) -> void:
	var l := SpotLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.spot_range = reach
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.shadow_enabled = shadow
	l.light_bake_mode = Light3D.BAKE_STATIC
	l.light_volumetric_fog_energy = 0.8 if fog or shadow else 0.0
	_fade(l)
	var d := dir.normalized()
	l.transform = Transform3D(Basis.looking_at(d, Vector3.FORWARD if absf(d.y) > 0.99 else Vector3.UP), at - z.origin)
	z.node.add_child(l)


func _omni(z: Zone, at: Vector3, col: Color, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	l.light_bake_mode = Light3D.BAKE_STATIC
	l.light_volumetric_fog_energy = 0.0
	_fade(l)
	l.position = at - z.origin
	z.node.add_child(l)


func _fade(l: Light3D) -> void:
	l.distance_fade_enabled = true
	l.distance_fade_begin = LIGHT_FADE
	l.distance_fade_length = LIGHT_FADE_LENGTH
	l.distance_fade_shadow = 30.0


## A painted sign on a surface at `at` facing `normal`, its letters `height` tall.
func _label(z: Zone, text: String, at: Vector3, normal: Vector3, up: Vector3, height: float, col := Color(0.9, 0.88, 0.8)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = 96
	l.pixel_size = height / 96.0
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	l.visibility_range_end = 40.0
	var zb := normal.normalized()
	var xb := up.cross(zb).normalized()
	l.transform = Transform3D(Basis(xb, zb.cross(xb), zb), at + zb * 0.01 - z.origin)
	z.node.add_child(l)


# ---------------------------------------------------------------- geometry

func _zone(face: Node3D, zone_name: String, origin: Vector3, reach: float) -> Zone:
	var z := Zone.new()
	z.node = Node3D.new()
	z.node.name = "Interior%s" % zone_name
	z.node.position = origin
	z.origin = origin
	z.reach = reach
	face.add_child(z.node)
	return z


func _finish(z: Zone) -> void:
	for model in z.props:
		var xfs: Array = z.props[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh[model]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Deco_%s" % model
		mmi.multimesh = mm
		_ranged(mmi, z.reach)
		z.node.add_child(mmi)
	if not z.geo.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Dressing"
		mi.mesh = _commit(z)
		_ranged(mi, z.reach)
		z.node.add_child(mi)
	if not z.solids.is_empty():
		var body := StaticBody3D.new()
		body.name = "Solids"
		body.collision_layer = GameConfig.LAYER_WORLD
		body.collision_mask = 0
		for s in z.solids:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = s[1]
			cs.shape = shape
			cs.transform = s[0]
			body.add_child(cs)
		z.node.add_child(body)


func _ranged(g: GeometryInstance3D, reach: float) -> void:
	g.visibility_range_end = reach
	g.visibility_range_end_margin = 8.0


func _commit(z: Zone) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in z.geo:
		var t: SurfaceTool = z.geo[key]
		t.set_material(_mats[key])
		t.commit(mesh)
	return mesh


func _tool(z: Zone, key: String) -> SurfaceTool:
	if not z.geo.has(key):
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		z.geo[key] = t
	return z.geo[key]


## A triangle facing the way its normals do (Godot's front faces wind clockwise).
func _tri(t: SurfaceTool, p: Array, n: Array, col: Color) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var order := [0, 1, 2]
	if (b - a).cross(c - a).dot(n[0] + n[1] + n[2]) > 0.0:
		order = [0, 2, 1]
	for i in order:
		t.set_color(col)
		t.set_normal(n[i])
		t.add_vertex(p[i])


## A box `size` big at `xf` (face-local; `xf` has no scale), in material `key`; `solid` also collides.
func _box(z: Zone, key: String, xf: Transform3D, size: Vector3, col := Color.WHITE, solid := false) -> void:
	var t := _tool(z, key)
	var h := size * 0.5
	var local := Transform3D(xf.basis, xf.origin - z.origin)
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var c := n * h[axis]
			var q := [local * (c - u - v), local * (c + u - v), local * (c + u + v), local * (c - u + v)]
			var wn := (local.basis * n).normalized()
			_tri(t, [q[0], q[1], q[2]], [wn, wn, wn], col)
			_tri(t, [q[0], q[2], q[3]], [wn, wn, wn], col)
	if solid:
		_solid_box(z, xf, size)


## A pipe (a capped cylinder) of radius `r` from `a` to `b`, face-local.
func _pipe(z: Zone, key: String, a: Vector3, b: Vector3, r: float, col := Color.WHITE, seg := 12) -> void:
	var t := _tool(z, key)
	a -= z.origin
	b -= z.origin
	var y := (b - a).normalized()
	var x := (Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).cross(y).normalized()
	var w := y.cross(x)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var n0 := x * cos(a0) + w * sin(a0)
		var n1 := x * cos(a1) + w * sin(a1)
		_tri(t, [a + n0 * r, a + n1 * r, b + n1 * r], [n0, n1, n1], col)
		_tri(t, [a + n0 * r, b + n1 * r, b + n0 * r], [n0, n1, n0], col)
		_tri(t, [a, a + n1 * r, a + n0 * r], [-y, -y, -y], col)
		_tri(t, [b, b + n0 * r, b + n1 * r], [y, y, y], col)


# ---------------------------------------------------------------- frames

## A point in the face's frame: `x` along the face, `h` up, `d` deep from its front.
static func P(x: float, h: float, d: float) -> Vector3:
	return Vector3(x, h, -d)


## A transform at `p` with no turn.
static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)


## The middle of bay `i` (0..6) along the face.
static func _bay(i: int) -> float:
	return (i - 3) * BAY


## How deep the spawn hall's front and back slopes stand at height `h`.
static func _hall_front(h: float) -> float:
	return HALL_FRONT + (h - HALL_FLOOR) * (HALL_APEX.x - HALL_FRONT) / (HALL_APEX.y - HALL_FLOOR)


## The height of a spawn ramp's top at depth `d` (it comes down from the junction to the hall's floor).
static func _ramp_h(d: float) -> float:
	return JUNCTION_Z * clampf((RAMP_FOOT - d) / (RAMP_FOOT - 14.5), 0.0, 1.0)


static func _hall_back(h: float) -> float:
	return HALL_BACK - (h - HALL_FLOOR) * (HALL_BACK - HALL_APEX.x) / (HALL_APEX.y - HALL_FLOOR)


## Whether face `face` ("S", "E", "N", "W") has a gate (LevelBuilder.SIDES).
static func _has_gate(face: String) -> bool:
	for side in LevelBuilder.SIDES:
		if LevelBuilder.SIDES[side].face == face:
			return LevelBuilder.SIDES[side].gate
	return false


func _pick(models: Array) -> String:
	return models[_rng.randi() % models.size()]
