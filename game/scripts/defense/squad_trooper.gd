class_name SquadTrooper
extends CharacterBody3D
## One trooper of a defender squad (DefenderSquad): a Gunner Squad's Heavy Gunner, an AA Squad's
## Missile Trooper or a Flame Squad's Flame Trooper. The squad tells it where to stand (goal) and
## where to aim (aim_point); the trooper walks there itself, around whatever is in the way, and
## faces its aim. The squad's leader is driven instead (drive()), from the player's keys or the
## squad's AI. What it fights with comes from the subclass (_build_weapon(), _weapon_tick()).
##
## Animation: the rigged model's eight walk clips sit around Idle in a 2D blend space, by where
## the trooper is going relative to where it faces, sped up past their natural speeds. The models'
## clips are all baked at the same speeds (tools/blender/rig_heavy_gunner.py, rig_missile_trooper.py,
## rig_flame_trooper.py).
## The rig (a TrooperRig) bends the spine onto the aim.

signal died(trooper: SquadTrooper)

## Collision: slimmer than the navmesh's agent radius (0.5 m), so paths hugging the stronghold's
## inside corners don't snag; a little shorter than the Heavy Gunner, for the bunker's low ramps.
const RADIUS := 0.42
const HEIGHT := 2.1
## Natural ground speeds of the walk clips (m/s): ahead, back, to the side.
const CLIP_FORWARD := 2.3
const CLIP_BACK := 1.6
const CLIP_SIDE := 1.1
## Walk clips by where they go (x right, y ahead), each at its natural speed.
const WALKS := {
	"F": Vector2(0, 1), "FR": Vector2(0.7071, 0.7071), "R": Vector2(1, 0), "BR": Vector2(0.7071, -0.7071),
	"B": Vector2(0, -1), "BL": Vector2(-0.7071, -0.7071), "L": Vector2(-1, 0), "FL": Vector2(-0.7071, 0.7071),
}
const ACCEL := 9.0
## Ledges it steps up onto (m), and higher ones (up to TALL_STEP) where the navmesh routes it up onto
## higher ground: LevelBuilder bakes a 0.5 m climb in 0.25 m cells, so a ledge up to 0.75 m can come
## out climbable, like the spawn ramp's low sides.
const STEP_HEIGHT := 0.45
const TALL_STEP := 0.75
## Body turn rate; the spine takes up to TWIST_LIMIT of the aim on its own, ahead of the legs.
const TURN_RATE := deg_to_rad(160.0)
const TWIST_LIMIT := deg_to_rad(35.0)
## Following: how hard it closes in on its spot, and how much faster than walking pace it may go
## to catch up: CATCH_UP, rising to FAR_CATCH_UP from 3 m off its spot to 8 m off it.
const FOLLOW_GAIN := 1.8
const CATCH_UP := 1.45
const FAR_CATCH_UP := 1.75
## Seconds between path updates while following.
const REPATH := 0.25
## Caught on a corner this long, a follower backs off the wall for UNSTICK_TIME and tries again.
const BLOCKED_TIME := 0.4
const UNSTICK_TIME := 0.35

var team := GameConfig.TEAM_DEFENDER
var station_kind := "soldier"
var max_hp := 400.0
var hp := 400.0
var target_radius := 0.3
var squad: Node = null
## Where the squad wants it (world). Followers walk there; the leader ignores it.
var goal := Vector3.ZERO
## The leader's velocity, so a follower in its spot keeps pace instead of lagging.
var pace := Vector3.ZERO
var following := false
## In a column: walk straight at this point on the leader's trail at trail_speed (the squad keeps
## it a little ahead of the trooper) instead of pathing to the goal. INF: path to the goal.
var trail_point := Vector3.INF
var trail_speed := 0.0
## World point the trooper aims at; INF-free: the squad always gives one.
var aim_point := Vector3.ZERO
## Look the way the aim points instead of at the point (when it is too close to converge on).
var aim_parallel := false
var aim_dir := Vector3.FORWARD
## Shots never hit these (the squad's own bodies).
var exclude: Array[RID] = []
var hustle := false
## Fastest it goes following its goal (m/s); a squad walking its leader home at a walk caps it.
var walk_limit := INF

var _model: Node3D
var _skel: Skeleton3D
var _rig: TrooperRig
var _tree: AnimationTree
var _agent: NavigationAgent3D
var _shape: CollisionShape3D
var _blend := Vector2.ZERO
var _drive := Vector3.ZERO
var _driven := false
## The velocity it is trying to reach this frame (before acceleration and avoidance).
var _want := Vector3.ZERO
## Pathing on the navmesh (not driven, not walking the leader's trail): may take TALL_STEPs.
var _pathing := false
var _repath_cd := 0.0
var _path_goal := Vector3.INF
var _blocked := 0.0
var _unstick := 0.0
var _wall_away := Vector3.ZERO
var _tossed := false
## Held in a Serpent Sniper's coils last frame (it struggles: _in_coils).
var _was_held := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

static var _scenes := {}
static var _faded: Array[BaseMaterial3D] = []
static var _close_fade := true


## Troopers right in front of the camera dither away (on by default, for the squad's own camera).
static func set_close_fade(on: bool) -> void:
	_close_fade = on
	for mat in _faded:
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER if on else BaseMaterial3D.DISTANCE_FADE_DISABLED


## The rigged model (clips Idle and Walk_<dir>).
func _model_path() -> String:
	return ""


## The rig that poses the upper body and the weapon after the clips.
func _new_rig() -> TrooperRig:
	return TrooperRig.new()


## Weapon parts beyond the model (muzzle flashes and the like); the skeleton and rig are up.
func _build_weapon() -> void:
	pass


## Runs the weapon every physics frame, before the trooper moves.
func _weapon_tick(_delta: float) -> void:
	pass


## The weapon goes quiet: the trooper is down.
func _weapon_down() -> void:
	pass


## How far the spine bends up (+) or down onto an aim `pitch` above level (rad).
func _spine_pitch(pitch: float) -> float:
	return pitch


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	add_to_group("troopers")
	collision_layer = GameConfig.LAYER_DEFENDERS
	# Squad mates and the garrison don't block each other: avoidance keeps them apart.
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	# Up the spawn ramp at walking pace, not slowed by the slope.
	floor_constant_speed = true

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	_shape.shape = cap
	_shape.position.y = HEIGHT * 0.5
	add_child(_shape)

	_agent = NavigationAgent3D.new()
	_agent.radius = RADIUS + 0.15
	_agent.height = HEIGHT
	# Avoidance clamps to this: room for the fastest a follower goes (far off and hustling).
	_agent.max_speed = CLIP_FORWARD * FAR_CATCH_UP * 1.25
	# Path corners count as reached only close up, so troopers round the bunker's corners instead
	# of cutting them. The baked navmesh floats ~0.3-0.5 m over the floor: compare at foot height.
	_agent.path_desired_distance = 0.5
	_agent.target_desired_distance = 0.4
	_agent.path_height_offset = 0.4
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 6.0
	_agent.max_neighbors = 8
	_agent.time_horizon_agents = 0.8
	_agent.avoidance_priority = 0.5
	_agent.navigation_layers = 1 | LevelBuilder.NAV_SQUAD
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)

	_build_model()
	_build_weapon()
	exclude.append(get_rid())


func _build_model() -> void:
	var path := _model_path()
	if not _scenes.has(path):
		_scenes[path] = load(path)
	_model = Node3D.new()
	add_child(_model)
	var m := (_scenes[path] as PackedScene).instantiate() as Node3D
	m.rotation.y = PI  # model front is +Z, units look down -Z
	_model.add_child(m)
	# Seen up close (a squad mate between the camera and the leader), the armor dithers away.
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat and not mat.has_meta("faded"):
				mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER if _close_fade else BaseMaterial3D.DISTANCE_FADE_DISABLED
				mat.distance_fade_min_distance = 0.6
				mat.distance_fade_max_distance = 1.6
				mat.set_meta("faded", true)
				_faded.append(mat)
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	for clip in ap.get_animation_list():
		var a := ap.get_animation(clip)
		if not a.has_meta("looped"):
			# Baked loops end on a copy of the first frame: drop it so the wrap is seamless.
			a.length -= 1.0 / 30.0
			a.loop_mode = Animation.LOOP_LINEAR
			a.set_meta("looped", true)
	var space := AnimationNodeBlendSpace2D.new()
	space.sync = true
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	_add_clip(space, "Idle", Vector2.ZERO)
	for d in WALKS:
		_add_clip(space, "Walk_" + d, WALKS[d])
	var root := AnimationNodeBlendTree.new()
	root.add_node("move", space)
	root.add_node("speed", AnimationNodeTimeScale.new())
	root.connect_node("speed", 0, "move")
	root.connect_node("output", 0, "speed")
	_tree = AnimationTree.new()
	_tree.tree_root = root
	m.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.active = true
	_tree.advance(randf() * 0.8)  # don't step in lockstep
	_skel = m.find_children("*", "Skeleton3D", true, false)[0]
	_rig = _new_rig()
	_skel.add_child(_rig)


static func _add_clip(space: AnimationNodeBlendSpace2D, clip: String, at: Vector2) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	space.add_blend_point(node, at)


# ---------------------------------------------------------------- damage

func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * HEIGHT * 0.6


func get_approach_point() -> Vector3:
	return global_position


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	hp -= amount
	if hp <= 0.0:
		_die()


## Run over by a ram: the armor takes most of it, but it staggers.
func toss(v: Vector3) -> void:
	if hp <= 0.0 or SerpentTrap.is_held(self):
		return
	velocity = v * 0.4
	_tossed = true


func _die() -> void:
	hp = 0.0
	_weapon_down()
	remove_from_group("damageable")
	remove_from_group("defender_targets")
	remove_from_group("troopers")
	collision_layer = 0
	collision_mask = GameConfig.LAYER_WORLD
	_agent.avoidance_enabled = false
	Combat.spawn_impact(self, get_aim_point(), true)
	died.emit(self)
	_tree.active = false
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", -PI * 0.5, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "position:y", 0.25, 0.7)
	tw.tween_interval(4.0)
	tw.tween_property(_model, "position:y", -HEIGHT, 2.5)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- orders

## Leader: walk at `v` (world, m/s) this physics frame, clamped to what the trooper can do.
func drive(v: Vector3) -> void:
	_drive = v
	_driven = true


## The leader goes where it likes: the others give way to it.
func set_leader(on: bool) -> void:
	_agent.avoidance_priority = 1.0 if on else 0.5
	if on:
		following = false
		trail_point = Vector3.INF


## Who gives way to whom: a trooper steers round squad mates of higher priority and ignores lower
## ones (the squad ranks them front to back, so the back of a column never shoves the front).
func set_priority(p: float) -> void:
	_agent.avoidance_priority = p


## Fastest it walks in a direction (world), relative to where it faces: an ellipse between the
## clips' speeds.
func max_speed_toward(dir: Vector3) -> float:
	var local := global_basis.inverse() * dir
	var fwd := -local.z
	var a := CLIP_FORWARD if fwd >= 0.0 else CLIP_BACK
	var side := local.x
	var f := fwd / a
	var s := side / CLIP_SIDE
	var n := sqrt(f * f + s * s)
	return (1.0 / n if n > 0.001 else CLIP_FORWARD) * (1.35 if hustle else 1.1)


## Caught on a corner and backing off it right now.
func unsticking() -> bool:
	return _unstick > 0.0


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		if not is_on_floor():
			velocity = Vector3(0.0, velocity.y - _gravity * delta, 0.0)
			move_and_slide()
		return
	if _tossed:
		velocity.y -= _gravity * delta
		move_and_slide()
		_tossed = not (is_on_floor() and velocity.y <= 0.0)
		return
	if SerpentTrap.is_held(self):
		_in_coils(delta)
		return
	if _was_held:
		_was_held = false
		_model.rotation = Vector3.ZERO
	_face(delta)
	_weapon_tick(delta)
	_animate(delta)
	_pathing = false
	if _driven:
		_driven = false
		var want := _drive
		var limit := max_speed_toward(want.normalized()) if want.length() > 0.01 else 0.0
		want = want.limit_length(limit)
		_want = want
		var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, ACCEL * delta)
		_agent.velocity = flat  # so the others give way; the leader itself doesn't wait for them
		_move(flat, delta)
	elif following:
		_follow(delta)
	else:
		_want = Vector3.ZERO
		var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, ACCEL * delta)
		_agent.velocity = flat
		_move(flat, delta)


## Held in a Serpent Sniper's coils (SerpentTrap.hold): it can't move, turn or fight (the trigger stays off; the
## squad's orders wait), held where it is (nothing moves it, not even the snake round it), and struggles in them.
func _in_coils(delta: float) -> void:
	_was_held = true
	_driven = false
	_want = Vector3.ZERO
	_agent.velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	if get("trigger") != null:
		set("trigger", false)
	_weapon_tick(delta)
	_animate(delta)
	var t := Time.get_ticks_msec() * 0.001
	_model.rotation = Vector3(sin(t * 7.3) * 0.03, sin(t * 4.1) * 0.05, sin(t * 11.0) * 0.035)


func _move(flat: Vector3, delta: float) -> void:
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	# Against a wall the velocity starts from nothing every frame: go by what it is trying to do.
	if is_on_wall() and _want.length() > 0.5 and flat.length() > 0.05:
		if _step_up(flat.normalized() * 0.3, _pathing):
			# Over the ledge at the pace it came at, instead of from a standstill.
			velocity.x = flat.x
			velocity.z = flat.z


## move_and_slide stops dead at a ledge (the step between the stronghold's halls and ramps): step
## up onto it if it is low enough and there is room.
func _step_up(motion: Vector3, tall: bool) -> bool:
	for h: float in ([STEP_HEIGHT, TALL_STEP] if tall else [STEP_HEIGHT]):
		var up: Vector3 = Vector3.UP * h
		if test_move(global_transform, up) or test_move(global_transform.translated(up), motion):
			continue
		if h > STEP_HEIGHT:
			# Only up onto walkable ground: the navmesh just ahead is higher than here (a ramp's
			# low side), not the top of a railing or a wall end it doesn't cover.
			var map := get_world_3d().navigation_map
			var here := NavigationServer3D.map_get_closest_point(map, global_position + Vector3.UP * 0.5)
			var to := global_position + motion * 1.5 + up
			var there := NavigationServer3D.map_get_closest_point(map, to)
			if Vector2(there.x - to.x, there.z - to.z).length() > 0.35 or there.y < here.y + 0.2:
				return false
		global_position += up + motion
		apply_floor_snap()  # straight down onto the step, not a hop up and a fall
		return true
	return false


## Follower: walk to the goal. Far off, or with something in the way, along a navmesh path at a
## catch-up pace; close in, it keeps pace with the leader and eases into its spot.
func _follow(delta: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	var want := Vector3.ZERO
	var walk := CLIP_FORWARD * lerpf(CATCH_UP, FAR_CATCH_UP, clampf((dist - 3.0) / 5.0, 0.0, 1.0)) * (1.25 if hustle else 1.0)
	walk = minf(walk, walk_limit)
	_repath_cd -= delta
	if _repath_cd <= 0.0 or goal.distance_to(_path_goal) > 0.6:
		_repath_cd = REPATH
		_path_goal = goal
		_agent.target_position = goal
	var direct := dist < 2.5 and _agent.get_current_navigation_path().size() <= 2
	_pathing = trail_point == Vector3.INF
	if _unstick > 0.0:
		# Wedged on a corner: back off the wall and come at the path again.
		_unstick -= delta
		var next := _agent.get_next_path_position() - global_position
		next.y = 0.0
		want = (next.normalized() + _wall_away * 0.8).normalized() * CLIP_FORWARD
	elif trail_point != Vector3.INF:
		var on := trail_point - global_position
		on.y = 0.0
		if on.length() > 0.05:
			want = on.normalized() * trail_speed
	elif direct:
		want = pace + to * FOLLOW_GAIN
		if dist < 0.25 and pace.length() < 0.2:
			want = Vector3.ZERO
	elif not _agent.is_navigation_finished():
		var next := _next_corner() - global_position
		next.y = 0.0
		if next.length() > 0.01:
			# Slow down coming in, but never below the leader's pace.
			var speed := clampf(dist * FOLLOW_GAIN, pace.length(), walk)
			want = next.normalized() * speed
	want = want.limit_length(walk)
	_want = want
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, ACCEL * 1.4 * delta)
	_agent.velocity = flat


## The path corner to walk to. Already out along the leg past the agent's next corner (in a gate,
## crossing the hole the door's plug leaves in the navmesh: every repath starts the path from the
## nearer edge of it, which half the way across is the one behind), it heads on for the corner
## after instead of turning back.
func _next_corner() -> Vector3:
	var next := _agent.get_next_path_position()
	var path := _agent.get_current_navigation_path()
	var k := _agent.get_current_navigation_path_index()
	if k + 1 < path.size():
		var ab := path[k + 1] - path[k]
		var ap := global_position - path[k]
		ab.y = 0.0
		ap.y = 0.0
		var u := ap.dot(ab) / maxf(ab.length_squared(), 0.0001)
		if u > 0.0 and u < 1.0 and (ap - ab * u).length() < 0.6:
			return path[k + 1]
	return next


func _on_velocity_computed(safe: Vector3) -> void:
	if hp <= 0.0 or _tossed or not following or SerpentTrap.is_held(self):
		return
	var dt := get_physics_process_delta_time()
	var was := global_position
	_move(Vector3(safe.x, 0.0, safe.z), dt)
	# Pushing on and getting nowhere for a moment means it is caught on a corner.
	var got := Vector2(global_position.x - was.x, global_position.z - was.z).length() / dt
	if _want.length() > 0.6 and got < _want.length() * 0.3 and is_on_wall():
		_blocked += dt
		if _blocked > BLOCKED_TIME:
			_blocked = 0.0
			_unstick = UNSTICK_TIME
			_wall_away = Vector3(get_wall_normal().x, 0.0, get_wall_normal().z).normalized()
			_repath_cd = 0.0
	else:
		_blocked = maxf(_blocked - dt, 0.0)


## Turns toward the aim: the spine takes the first TWIST_LIMIT at once, the legs follow at
## TURN_RATE. Then bends the spine onto it (as much as _spine_pitch says).
func _face(delta: float) -> void:
	var look := aim_dir if aim_parallel else aim_point - global_position
	var flat := Vector2(look.x, look.z)
	if flat.length() < 0.05:
		return
	var want := atan2(-look.x, -look.z)
	var off := angle_difference(rotation.y, want)
	if absf(off) > TWIST_LIMIT * 0.35 or velocity.length() > 0.3:
		rotation.y = rotate_toward(rotation.y, want, TURN_RATE * delta)
		off = angle_difference(rotation.y, want)
	_rig.twist = clampf(off, -TWIST_LIMIT, TWIST_LIMIT)
	var from := global_position + Vector3.UP * 1.25
	var d := aim_dir if aim_parallel else aim_point - from
	var pitch := _spine_pitch(atan2(d.y, Vector2(d.x, d.z).length()))
	_rig.pitch = lerp_angle(_rig.pitch, pitch, minf(delta * 10.0, 1.0))


## Walk clips by where it goes relative to where it faces, sped up past their speeds.
func _animate(delta: float) -> void:
	var local := global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var fwd := -local.z
	var b := Vector2(local.x / CLIP_SIDE, fwd / (CLIP_FORWARD if fwd >= 0.0 else CLIP_BACK))
	var scale := maxf(b.length(), 1.0)
	_blend = _blend.lerp(b / scale, minf(delta * 10.0, 1.0))
	_tree.set("parameters/move/blend_position", _blend)
	_tree.set("parameters/speed/scale", scale)
