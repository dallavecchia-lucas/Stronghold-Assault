class_name SerpentTrap
extends RefCounted
## A Serpent Sniper's bush trap (AttackerUnit, UnitTypes trap_*): where its body lies as it coils round a bush
## (progress 0, lying beside it as it came up, to 1, coiled round it) and as it strikes and constricts its prey,
## for SerpentRig. The body follows its snout's way, the rifle set down in the grass first (rifle_rest):
##   coiling     the snout curves in onto a ring round the foot of the bush, inside its foliage, and winds round
##               it, the body following it round, the last of it up on top of the first turn, the head resting
##               on top
##   striking    the snout darts out at the prey (STRIKE_TIME) and winds round its legs and body up to its chest
##               (WRAP_TIME), the coils sliding off the bush after it
##   squeezing   the coils round the prey tighten, in slow pulses
##   letting go  (the prey dead) the body slides back the way it came, round the bush again (LET_GO m/s)
## Uncoiling is the coil run backward. The prey (hold) can't move or fight while it is held (is_held: the
## defenders' soldiers, troopers and squads check it).

const BODY_R := 0.17
## The ring round the bush: this share of its footprint, no tighter or wider than RING_R (m), plus BODY_R.
const RING := 0.5
const RING_R := [0.25, 0.5]
## The strike: out to the prey in STRIKE_TIME, wound round it WRAP_TIME later; the coils round it start at
## WRAP_LOW up its legs, end at WRAP_HIGH round its chest, WRAP_TURNS round, PREY_R out from its middle.
const STRIKE_TIME := 0.35
const WRAP_TIME := 1.4
const WRAP_LOW := 0.6
const WRAP_HIGH := 1.45
const WRAP_TURNS := 1.3
const PREY_R := 0.3
## Squeezing: the coils close in by SQUEEZE (m) over SQUEEZE_TIME, and pulse PULSE tighter every PULSE_TIME.
const SQUEEZE := 0.05
const SQUEEZE_TIME := 5.0
const PULSE := 0.012
const PULSE_TIME := 1.25
const LET_GO := 3.0
## Several snakes sent at a bush take the free bushes nearest it, no further than this from it (m).
const SPREAD := 20.0
## What it strikes: the defenders' soldiers and squad troopers (station_kind), on the ground.
const PREY := ["soldier", "infiltrator", "sniper"]

var bush: Bush
var centre := Vector3.ZERO
## The snout's way: the body as it lay beside the bush, then round it.
var way: SerpentPath
## The prey, where it was struck, and which way the coils go round it.
var prey: Node3D = null
var prey_at := Vector3.ZERO
var _wrap_sign := 1.0
## Arcs along `way`: the snout beside the bush (progress 0), coiled (1).
var _u0 := 0.0
var _u_end := 0.0
var _ring := 0.4


## The coil round `p_bush` from `body` (SerpentRig.body_path: tail first, the snout last, as it lies now), on
## the ground at height `ground`.
func _init(p_bush: Bush, body: SerpentPath, ground: float) -> void:
	bush = p_bush
	centre = bush.global_position
	centre.y = ground
	way = SerpentPath.from(body.points, body.ups)
	_u0 = way.length()
	var snout := way.end()
	_ring = ring_radius(bush)
	var heading := _flat(way.tangent_at(_u0 - 0.05)).normalized()
	var off := _flat(snout - centre)
	# Round the way it already bears (angles run from +X toward +Z: bearing that way, the cross product's y
	# is negative).
	var turn_dir := -signf(off.cross(heading).y)
	var sign := turn_dir if turn_dir != 0.0 else 1.0
	# Curving in onto the ring a little way round it, then round and round.
	var a0 := atan2(off.z, off.x) + sign * 0.9
	var join := Vector3(cos(a0), 0.0, sin(a0))
	var low := centre.y + BODY_R
	way.bezier(heading, Vector3(centre.x, low, centre.z) + join * _ring, Vector3(-sin(a0), 0.0, cos(a0)) * sign, Vector3.UP, 0.4)
	var turns := (SerpentRig.SHOULDER + 2.4) / (TAU * _ring)
	var flat := minf(turns, 0.85)
	way.helix(centre, a0, sign * flat * TAU, _ring, _ring, low, low, 0.0)
	if turns > flat:
		way.helix(centre, a0 + sign * flat * TAU, sign * (turns - flat) * TAU, _ring, _ring - 0.04, low, low + BODY_R * 2.0, 0.0)
	# The head comes to rest up on the coil, raised a little.
	var last := way.tangent_at(way.length() - 0.02)
	way.add(way.end() + last * 0.25 + Vector3.UP * 0.08, Vector3.UP)
	_u_end = way.length()


## The ring a snake coils round `b` on (m from its middle, to the middle of the snake's body).
static func ring_radius(b: Bush) -> float:
	return clampf(b.radius * RING, RING_R[0], RING_R[1]) + BODY_R


## Coiling at progress `p` (0-1): [the way for SerpentRig.lay, where the snout is along it].
func pose(p: float) -> Array:
	var e := p * p * (3.0 - 2.0 * p)
	return [way, lerpf(_u0, _u_end, lerpf(p, e, 0.6))]


## Where the rifle lies set down in the grass, from where it rode (world): upright on the ground, level, slid
## back off the snake's front.
static func rifle_rest(rode: Transform3D, ground: float) -> Transform3D:
	var along := _flat(rode.basis.y).normalized()
	var at := rode.origin - along * 0.5
	at.y = ground + 0.42
	return Transform3D(Basis(along.cross(Vector3.UP), along, Vector3.UP), at)


# ---------------------------------------------------------------- the strike

## Strikes `p_prey`: the coils will go round it the way the snout already turns toward it.
func strike(p_prey: Node3D) -> void:
	prey = p_prey
	prey_at = prey.global_position
	var snout := way.end()
	var heading := way.tangent_at(_u_end - 0.02)
	var to := _flat(prey_at - snout)
	var s := -signf(heading.cross(to).y)
	_wrap_sign = s if s != 0.0 else 1.0


## The way out of the coil to the prey and round it, the coils `squeeze` m tighter than they first close:
## [the way for SerpentRig.lay (the coil, then out), the arc where the strike starts, where the wrap starts,
## where it ends].
func strike_way(squeeze: float) -> Array:
	var out := SerpentPath.from(way.points, way.ups)
	var start := out.length()
	var heading := out.tangent_at(start - 0.02)
	var from := _flat(out.end() - prey_at)
	var a0 := atan2(from.z, from.x) + _wrap_sign * PI * 0.25
	var radial := Vector3(cos(a0), 0.0, sin(a0))
	var r := PREY_R + BODY_R - squeeze
	var rise := (WRAP_HIGH - WRAP_LOW) / (WRAP_TURNS * TAU * r)
	var along := (Vector3(-sin(a0), 0.0, cos(a0)) * _wrap_sign + Vector3.UP * rise).normalized()
	var low := Vector3(prey_at.x, centre.y + WRAP_LOW, prey_at.z) + radial * r
	out.bezier(heading, low, along, radial, 0.35)
	var wrap := out.length()
	out.helix(prey_at, a0, _wrap_sign * WRAP_TURNS * TAU, r, r, centre.y + WRAP_LOW, centre.y + WRAP_HIGH)
	return [out, start, wrap, out.length()]


## How far along strike_way the snout is `t` seconds into the strike (it darts out, then winds round).
static func strike_reach(t: float, start: float, wrap: float, end: float) -> float:
	if t < STRIKE_TIME:
		var u := t / STRIKE_TIME
		return lerpf(start, wrap, u * u * (3.0 - 2.0 * u))
	var w := clampf((t - STRIKE_TIME) / WRAP_TIME, 0.0, 1.0)
	return lerpf(wrap, end, 1.0 - (1.0 - w) * (1.0 - w))


## How much tighter the coils are `t` seconds into the strike.
static func squeeze_at(t: float) -> float:
	var held := t - STRIKE_TIME - WRAP_TIME
	if held <= 0.0:
		return 0.0
	var u := clampf(held / SQUEEZE_TIME, 0.0, 1.0)
	return SQUEEZE * u * u * (3.0 - 2.0 * u) + PULSE * (0.5 - 0.5 * cos(TAU * held / PULSE_TIME))


# ---------------------------------------------------------------- prey

## Holds `n` in a snake's coils: it can't move or fight until let go (release).
static func hold(n: Node, by: Node) -> void:
	n.set_meta("held_by", by.get_instance_id())


static func release(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.has_meta("held_by"):
		n.remove_meta("held_by")


static func is_held(n: Node) -> bool:
	return n != null and n.has_meta("held_by")


## The defender on the ground nearest the bush within `reach` of it (flat) that a snake coiled round it strikes:
## a live soldier or trooper the attackers can pick out (not under camo, not keeping a low profile), not on
## a gun deck, not held by another snake.
static func prey_near(ctx: Node, b: Bush, reach: float) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	for d in ctx.get_tree().get_nodes_in_group("defender_targets"):
		if not d.is_alive() or not Combat.targetable(d) or Combat.low_profile(d) or is_held(d):
			continue
		if d.get("station_kind") not in PREY:
			continue
		var to: Vector3 = d.global_position - b.global_position
		if absf(to.y) > 1.5:
			continue
		var dist := Vector2(to.x, to.z).length()
		if dist < best_d:
			best_d = dist
			best = d
	return best


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ---------------------------------------------------------------- picking bushes

## Bushes for `snakes` sent at the bush at `at`: that one for the snake nearest it, and for the others the free
## bushes nearest it within SPREAD, each to the snake nearest it, a bush to each: [[snake, bush], ...].
static func assign(snakes: Array, at: Vector3) -> Array:
	if snakes.is_empty():
		return []
	var first := bush_near(at, snakes)
	if first == null:
		return []
	var bushes := Bush.all.filter(func(b): return b.usable and _flat(b.global_position - first.global_position).length() <= SPREAD \
			and (b.coiled_by == null or not is_instance_valid(b.coiled_by) or b.coiled_by in snakes))
	bushes.sort_custom(func(a, b): return _flat(a.global_position - at).length() < _flat(b.global_position - at).length())
	var left := snakes.duplicate()
	var out := []
	for bush in bushes:
		if left.is_empty():
			break
		var near: AttackerUnit = left[0]
		for u in left:
			if _flat(u.global_position - bush.global_position).length() < _flat(near.global_position - bush.global_position).length():
				near = u
		left.erase(near)
		out.append([near, bush])
	return out


## The usable bush nearest `at` (flat) within a metre of its edge that one of `snakes` may coil round, or null.
static func bush_near(at: Vector3, snakes: Array = []) -> Bush:
	var best: Bush = null
	var best_d := 1.0
	for b in Bush.all:
		if not b.usable or not (b.coiled_by == null or not is_instance_valid(b.coiled_by) or b.coiled_by in snakes):
			continue
		var d := _flat(b.global_position - at).length() - b.radius
		if d < best_d:
			best_d = d
			best = b
	return best
