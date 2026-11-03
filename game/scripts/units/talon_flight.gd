class_name TalonFlight
extends RefCounted
## How the Sky Talon flies: like a hawk. It glides most of the time and only now and then beats
## its wings, a few strokes at a time; gliding it slowly sinks below its cruising height and the
## strokes lift it back up (taking off and climbing over the mountain it keeps beating). It never
## stops in the air: it banks into its turns, and wherever it has nowhere left to go it circles,
## counterclockwise seen from above with the centre off its left wing, like a gunship flying a
## pylon turn. It looks ahead as it flies and climbs over the mountain in time. On an attack run
## (TalonRun: a strafe run or a bomb strike) the run steers it instead, and it glides down into
## the dive without a wing beat.
## The Glide and Flap clips come from tools/blender/rig_talon.py.

## Circling radius (m). Each talon flies its own ring, up to ORBIT_SPREAD wider, and its own
## height, spread over HEIGHT_SPREAD, so a flock sent to one spot stacks up instead of flying
## through itself.
const ORBIT_RADIUS := 12.0
const ORBIT_SPREAD := 8.0
const HEIGHT_SPREAD := 12.0
## Rings are level, and at least CLEARANCE over all the ground under them: next to the mountain
## a ring moves out from it (away from the middle of the map), and tightens, until it is.
const CLEARANCE := 8.0
const MIN_RING := 7.0
## On the way it cruises FLY_HEIGHT over the highest ground under it and this far ahead (m).
const LOOK_AHEAD := 20.0
## Most it turns (rad/s), how fast it rolls into and out of a turn, and its steepest bank.
const TURN_RATE := 1.2
const TURN_ACCEL := 1.6
const MAX_BANK := deg_to_rad(55.0)
## Gliding, it sinks SINK_RATE m/s until it is SINK_MAX below its cruising height (circling, it
## soars: SOAR_RATE m/s down to SOAR_MAX below); beating its wings it climbs back at CLIMB_RATE
## m/s, up to RISE_MAX above.
const SINK_RATE := 0.2
const SINK_MAX := 1.5
const SOAR_RATE := 0.12
const SOAR_MAX := 0.8
const CLIMB_RATE := 1.0
const RISE_MAX := 0.4
## Seconds per wing beat in the Flap clip.
const BEAT := 0.8
## The body's centre above the model's origin (its feet when standing): the model banks and
## pitches about it.
const BODY_HEIGHT := 1.3

## This talon's ring (m) and its cruising height above the others' (m).
var ring := ORBIT_RADIUS
var height := 0.0
## The attack run it is on, if any.
var run: TalonRun = null

var _unit: AttackerUnit
var _anim: AnimationPlayer
var _speed := 0.0
var _turn := 0.0  # rad/s, left positive
var _bank := 0.0
var _pitch := 0.0
var _level := 0.0  # above (+) or below (-) its cruising height, from gliding and flapping
var _beats := 0.0  # wing beats left in this burst
var _glide := 0.0  # seconds of gliding left before the next burst
var _circling := false
## The last ring worked out (ring_round): the point it was for, and [centre, radius, height].
var _ring_for := Vector3.INF
var _ring: Array = []


func _init(unit: AttackerUnit, anim: AnimationPlayer) -> void:
	_unit = unit
	_anim = anim
	# The same talon always flies the same ring: spread by its id.
	var k := float((unit.unit_id * 7) % 5) / 4.0
	ring = ORBIT_RADIUS + ORBIT_SPREAD * k
	height = HEIGHT_SPREAD * (k - 0.5)
	_speed = unit.stats.speed * 0.6
	for clip in ["Glide", "Flap"]:
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Glide")
	_anim.seek(randf() * _anim.current_animation_length)  # don't glide in lockstep
	_glide = randf_range(0.5, 2.0)


## The ring to fly round `point`, FLY_HEIGHT over the ground there (or over the point itself,
## when it is up on the mountain): [centre, radius, height]. Rings stay level and clear of the
## ground; if there is no way to keep one so, it goes round the point itself, as high as it has to.
func ring_round(point: Vector3) -> Array:
	if _ring_for.distance_to(point) < 1.5:
		return _ring
	_ring_for = point
	var base := maxf(point.y, _ground_at(point))
	var top := base + UnitTypes.FLY_HEIGHT + height
	var out := Vector3(point.x, 0.0, point.z)
	out = out.normalized() if out.length() > 1.0 else Vector3.FORWARD
	var r := ring
	while r >= MIN_RING:
		for s in range(0, 31, 3):
			var c := point + out * s
			if _highest(c, r) <= top - CLEARANCE:
				_ring = [c, r, top]
				return _ring
		r *= 0.8
	_ring = [point, ring, maxf(top, _highest(point, ring) + CLEARANCE)]
	return _ring


## Starts an attack run; it flies it before anything else.
func start(p_run: TalonRun) -> void:
	run = p_run


## Flies one step: on its attack run if it is on one, else on toward `round_at` ([centre, radius,
## height], from ring_round) and on round it. On the way it cruises FLY_HEIGHT over the ground
## under it and ahead; on the ring, at the ring's height. True once it is circling.
func fly(round_at: Array, delta: float) -> bool:
	var u := _unit
	var cruise: float = u.stats.speed
	var cruising_y := _cruising() + height
	var want := Vector2(-sin(u.rotation.y), -cos(u.rotation.y))
	var turn := 0.0
	var y := cruising_y
	var fast := 1.0
	if run:
		var steer := run.steer(cruising_y, _speed, delta)
		if run.phase == TalonRun.Phase.DONE:
			run = null
		want = steer.want
		y = steer.y
		fast = steer.speed
		_circling = false
	else:
		var center: Vector3 = round_at[0]
		var radius: float = round_at[1]
		var r := Vector2(u.global_position.x - center.x, u.global_position.z - center.z)
		var d := r.length()
		_circling = d < radius * 1.3
		# A field that leads in toward the centre from far off and onto the ring close in
		# (counterclockwise: the tangent is the radius turned a quarter left).
		if d > 0.01:
			var rn := r / d
			var tangent := Vector2(rn.y, -rn.x)
			var d2 := d * d
			var r2 := radius * radius
			var along := 2.0 * d * radius / (d2 + r2)  # how much of the way is round the ring
			want = -rn * (d2 - r2) / (d2 + r2) + tangent * along
			turn = _speed / radius * along  # it turns steadily into the ring
		if _circling:
			y = round_at[2]
	turn += angle_difference(u.rotation.y, atan2(-want.x, -want.y)) * 2.0
	_turn = move_toward(_turn, clampf(turn, -TURN_RATE, TURN_RATE), TURN_ACCEL * delta)
	u.rotation.y = wrapf(u.rotation.y + _turn * delta, -PI, PI)

	_speed = move_toward(_speed, cruise * fast * (1.08 if _beats > 0.0 else 1.0), cruise * 0.25 * delta)
	var diving := run != null and run.phase == TalonRun.Phase.RUN
	if run:
		_level = move_toward(_level, 0.0, delta)  # on a run it keeps to its plan
	var climb := y + _level - u.global_position.y
	_wings(climb, delta, diving)
	var fwd := -u.global_basis.z
	# On a run it dives and pulls up harder than it climbs and sinks cruising.
	var vy := clampf(climb * 2.5, -12.0, 12.0) if run else clampf(climb * 1.2, -4.0, 6.0)
	u.velocity = Vector3(fwd.x * _speed, vy, fwd.z * _speed)
	u.global_position += u.velocity * delta
	return _circling


## Glide or beat the wings: bursts of a few beats every few seconds (further apart while circling,
## where it soars), and for as long as it has to climb; none while it dives on a run.
func _wings(climb: float, delta: float, diving: bool) -> void:
	var labouring := climb > 2.0 and not diving
	if diving and _beats > 0.0:
		_beats = 0.0
		_anim.play("Glide", 0.3)
		_anim.speed_scale = 1.0
	if _beats > 0.0:
		_level = minf(_level + CLIMB_RATE * delta, RISE_MAX)
		_beats -= delta * _anim.speed_scale / BEAT
		_anim.speed_scale = 1.2 if labouring else 1.0
		if labouring:
			_beats = maxf(_beats, 1.0)
		elif _beats <= 0.0:
			_anim.play("Glide", 0.5)
			_anim.speed_scale = 1.0
			_glide = randf_range(7.0, 11.0) if _circling else randf_range(4.0, 7.0)
		return
	var lowest := -SOAR_MAX if _circling else -SINK_MAX
	_level = maxf(_level - (SOAR_RATE if _circling else SINK_RATE) * delta, lowest)
	_glide -= delta
	if not diving and (_glide <= 0.0 or _level <= lowest or labouring):
		_beats = randi_range(2, 3)
		_anim.play("Flap", 0.3)


## Banks into the turn and pitches with the climb, the model turning about the body's centre.
func animate(model: Node3D, delta: float) -> void:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var bank := clampf(atan(_speed * _turn / g), -MAX_BANK, MAX_BANK)
	_bank = lerpf(_bank, bank, minf(delta * 4.0, 1.0))
	var pitch := clampf(atan2(_unit.velocity.y, maxf(_speed, 1.0)) * 0.8, -0.6, 0.5)
	_pitch = lerpf(_pitch, pitch, minf(delta * 3.0, 1.0))
	model.rotation = Vector3(_pitch, 0.0, _bank)
	model.position = Vector3.UP * BODY_HEIGHT


## Shot down: the wings flail as it falls.
func die() -> void:
	_anim.play("Flap", 0.15)
	_anim.speed_scale = 1.8


## Highest ground under it and up to LOOK_AHEAD ahead, plus FLY_HEIGHT.
func _cruising() -> float:
	var fwd := -_unit.global_basis.z
	var h := 0.0
	for d in [0.0, LOOK_AHEAD * 0.5, LOOK_AHEAD]:
		h = maxf(h, _ground_at(_unit.global_position + fwd * d))
	return h + UnitTypes.FLY_HEIGHT


## Highest ground under a ring (its centre and twelve points round it).
func _highest(c: Vector3, r: float) -> float:
	var h := _ground_at(c)
	for k in 12:
		var a := TAU * k / 12.0
		h = maxf(h, _ground_at(c + Vector3(cos(a), 0.0, sin(a)) * r))
	return h


func _ground_at(p: Vector3) -> float:
	var floor_y := LevelBuilder.flight_floor(p)
	if not is_nan(floor_y):
		return floor_y
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -5.0, p.z), GameConfig.LAYER_WORLD)
	var hit := _unit.get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(hit.position.y, 0.0) if not hit.is_empty() else 0.0
