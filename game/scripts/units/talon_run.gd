class_name TalonRun
extends RefCounted
## One attack run by a Sky Talon: a strafe run along a line on the ground, firing ahead of itself
## so its rounds walk down the line like an A-10's, or a bombing pass over one spot.
##
##   POSITION  it flies round to a point behind the start of the line
##   LINE_UP   it turns onto its run-in, still at its cruising height
##   RUN       it dives in (RUN_IN before the line) and along the line, firing, or dropping its bomb
##   BREAK     it pulls up and turns away from the mountain
##
## The run-in comes straight along the line when the ground behind the line is open; where the
## mountain is in the way (a line along a face), it comes in at an angle from the open side and
## turns onto the line at its start. Its height along the whole pass is planned beforehand from
## the ground under it: low over the line itself, and never lower than it must be to climb over
## whatever is ahead (a gun deck, a roof, the mountain) at a slope it can fly, so it never flies
## into the stronghold. Past the line it breaks away from the mountain, climbing over what is
## ahead of it as it turns.

enum Phase {POSITION, LINE_UP, RUN, BREAK, DONE}

## Straight run-in before the line (m), and how much further back it gets into position.
const RUN_IN := 35.0
const SETUP := 15.0
## Past the line it keeps to the plan this much further before breaking away (m).
const RUN_OUT := 10.0
## Height over the ground along the line: strafing, bombing (m).
const STRAFE_ABOVE := 6.0
const BOMB_ABOVE := 14.0
## Least height over the ground it ever flies at on a run (m, the talon's origin; its body is
## TalonFlight.BODY_HEIGHT higher).
const CLEARANCE := 5.0
## Steepest it dives and climbs (rise over run).
const DIVE := 0.55
const CLIMB := 0.75
## Speed along the run, times its cruising speed.
const STRAFE_SPEED := 1.4
const BOMB_SPEED := 1.15
## Its rounds land at least LEAD_MIN ahead of it, coming down no steeper than FIRE_ANGLE.
const LEAD_MIN := 6.0
const FIRE_ANGLE := deg_to_rad(28.0)
## Rounds land up to this far either side of the line (m).
const SCATTER := 0.8
## Longest the break away lasts (s).
const BREAK_TIME := 3.5
## Plan step (m), and how far either side of the line the ground under its wings is looked at.
const STEP := 2.0
const WINGS := 3.5
## Angles off the line (degrees) a run-in may come in at, and how much higher than the line's
## start the ground under it may be.
const RUN_IN_ANGLES := [0.0, 20.0, 40.0, 60.0, 75.0]
const RUN_IN_ROOM := 6.0

var bomb := false
## The line on the ground (a bomb's spot is both ends), the way along it and its right-hand side,
## and the way the run-in comes in to its start.
var a: Vector3
var b: Vector3
var dir: Vector3
var side: Vector3
var dir_in: Vector3
var length := 0.0
var phase := Phase.POSITION
var dropped := false

var _unit: AttackerUnit
var _plan := PackedFloat32Array()  # height to fly at, every STEP from s = -RUN_IN
var _ground := PackedFloat32Array()
var _fire_cd := 0.0
var _break_t := 0.0


## A strafe run from `p_a` to `p_b`, or (p_bomb) a bombing pass over `p_a` heading `p_dir`.
## cruise_above: how high over the ground the talon cruises.
func _init(unit: AttackerUnit, p_a: Vector3, p_b: Vector3, p_dir: Vector3, p_bomb: bool, cruise_above: float) -> void:
	_unit = unit
	a = p_a
	b = p_b
	bomb = p_bomb
	dir = Vector3(p_dir.x, 0.0, p_dir.z).normalized()
	side = dir.cross(Vector3.UP)
	length = 0.0 if bomb else maxf((b - a).dot(dir), 0.0)
	dir_in = _run_in()
	_make_plan(cruise_above)


## Where to head (flat), what height to fly at and how fast (times cruising) this step, with the
## talon cruising at cruise_y on the way and moving at `speed`. Fires and drops as it goes.
func steer(cruise_y: float, speed: float, delta: float) -> Dictionary:
	var u := _unit
	var rel := u.global_position - a
	# Along the run-in (s < 0), then along the line; off: how far off to the right of it.
	var s := rel.dot(dir_in)
	var way := dir_in
	if s >= 0.0:
		s = rel.dot(dir)
		way = dir
	var off := rel.dot(way.cross(Vector3.UP))
	var want := Vector3.ZERO
	var y := cruise_y
	var fast := 1.0
	match phase:
		Phase.POSITION:
			want = a - dir_in * (RUN_IN + SETUP) - u.global_position
			if s < -RUN_IN - 8.0:
				phase = Phase.LINE_UP
		Phase.LINE_UP, Phase.RUN:
			want = way - way.cross(Vector3.UP) * clampf(off * 0.12, -2.0, 2.0)  # back onto it
			if s >= -RUN_IN:
				phase = Phase.RUN
				y = height_at(s + speed * 0.35)
				fast = BOMB_SPEED if bomb else STRAFE_SPEED
				if bomb:
					_drop(s, speed)
				else:
					_fire(s, delta)
			if s >= length + (0.0 if bomb else RUN_OUT) and (dropped or not bomb):
				phase = Phase.BREAK
		Phase.BREAK:
			_break_t += delta
			want = _away()
			y = maxf(height_at(s), _ahead(u) + CLEARANCE + 3.0)
			var fwd := -u.global_basis.z
			if _break_t > BREAK_TIME or (_break_t > 1.0 and fwd.dot(want) > 0.8):
				phase = Phase.DONE
	return {"want": Vector2(want.x, want.z), "y": y, "speed": fast}


## Height to fly at `s` along the line (beyond the plan, its last height).
func height_at(s: float) -> float:
	var x := clampf((s + RUN_IN) / STEP, 0.0, _plan.size() - 1.0)
	var i := mini(int(x), _plan.size() - 2)
	return lerpf(_plan[i], _plan[i + 1], x - i)


## Ground under the line at `s` (the highest under its wings).
func ground_at(s: float) -> float:
	var x := clampf((s + RUN_IN) / STEP, 0.0, _ground.size() - 1.0)
	return _ground[int(round(x))]


## The plan: over the line STRAFE_ABOVE / BOMB_ABOVE the highest ground nearby; before it, from
## the talon's cruising height down (or up) to that at no steeper than DIVE (CLIMB); after it,
## climbing away. Never under CLEARANCE over the ground, nor so low that it can't climb over what
## is ahead in time.
func _make_plan(cruise_above: float) -> void:
	var space := _unit.get_world_3d().direct_space_state
	var n := int(ceil((RUN_IN + length + RUN_OUT) / STEP)) + 1
	_ground.resize(n)
	_plan.resize(n)
	for i in n:
		var d := -RUN_IN + i * STEP
		var way := dir_in if d < 0.0 else dir
		var p := a + way * d
		var w := way.cross(Vector3.UP) * WINGS
		_ground[i] = maxf(_top(space, p), maxf(_top(space, p + w), _top(space, p - w)))
	var above := BOMB_ABOVE if bomb else STRAFE_ABOVE
	var i0 := int(round(RUN_IN / STEP))
	var i1 := mini(i0 + int(round(length / STEP)), n - 1)
	for i in range(i0, i1 + 1):
		var g := 0.0
		for k in range(maxi(i - 2, 0), mini(i + 3, n)):
			g = maxf(g, _ground[k])
		_plan[i] = g + above
	var approach := _ground[0] + cruise_above
	for i in i0:
		var d := (i0 - i) * STEP
		_plan[i] = _plan[i0] + clampf(approach - _plan[i0], -CLIMB * d, DIVE * d)
	for i in range(i1 + 1, n):
		_plan[i] = _plan[i1] + CLIMB * (i - i1) * STEP
	# Never too low for what is ahead: high enough here to climb over it in time.
	var floor_y := _ground[n - 1] + CLEARANCE
	for i in range(n - 1, -1, -1):
		floor_y = maxf(_ground[i] + CLEARANCE, floor_y - CLIMB * STEP)
		_plan[i] = maxf(_plan[i], floor_y)
	# And no steeper a dive than DIVE after it.
	for i in range(1, n):
		_plan[i] = maxf(_plan[i], _plan[i - 1] - DIVE * STEP)


## The way it comes in to the line's start: straight along the line if the ground behind it is
## open, else the least angle off it (to the side away from the mountain first) that is.
func _run_in() -> Vector3:
	var space := _unit.get_world_3d().direct_space_state
	var out := Vector3(a.x, 0.0, a.z).normalized()
	var reach := RUN_IN + SETUP
	for deg in RUN_IN_ANGLES:
		var ways := [dir.rotated(Vector3.UP, deg_to_rad(deg)), dir.rotated(Vector3.UP, -deg_to_rad(deg))]
		# The one that starts further out from the mountain first.
		ways.sort_custom(func(p, q): return (-p).dot(out) > (-q).dot(out))
		for d in ways:
			var clear := true
			for k in range(2, int(reach / STEP)):
				if _top(space, a - d * (k * STEP)) > a.y + RUN_IN_ROOM:
					clear = false
					break
			if clear:
				return d
	return dir


## Strafing: the rounds land LEAD ahead of it (more the higher it is), walking down the line.
func _fire(s: float, delta: float) -> void:
	_fire_cd -= delta
	var over := _unit.global_position.y - ground_at(s)
	var at := s + maxf(LEAD_MIN, over / tan(FIRE_ANGLE))
	if at < 0.0 or at > length or _fire_cd > 0.0:
		return
	_fire_cd = _unit.stats.strafe_interval
	_unit.strafe_shot(a + dir * at + side * randf_range(-SCATTER, SCATTER), maxf(a.y, b.y))


## Bombing: lets go once the bomb, falling from here with its speed, would land on the spot.
func _drop(s: float, speed: float) -> void:
	if dropped:
		return
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var fall := sqrt(2.0 * maxf(_unit.global_position.y + TalonFlight.BODY_HEIGHT - 0.6 - a.y, 1.0) / g)
	if s >= -speed * fall:
		dropped = true
		_unit.drop_bomb(a)


## Away from the mountain (the middle of the map), or straight on if that is away already.
func _away() -> Vector3:
	var out := Vector3(_unit.global_position.x, 0.0, _unit.global_position.z)
	out = out.normalized() if out.length() > 1.0 else dir
	return dir if dir.dot(out) > 0.5 else out


## Highest ground under it and up to 16 m ahead.
func _ahead(u: AttackerUnit) -> float:
	var space := u.get_world_3d().direct_space_state
	var fwd := -u.global_basis.z
	var h := 0.0
	for d in [0.0, 8.0, 16.0]:
		h = maxf(h, _top(space, u.global_position + fwd * d))
	return h


static func _top(space: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var floor_y := LevelBuilder.flight_floor(p)
	if not is_nan(floor_y):
		return floor_y
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), GameConfig.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return maxf(hit.position.y, 0.0) if not hit.is_empty() else 0.0
