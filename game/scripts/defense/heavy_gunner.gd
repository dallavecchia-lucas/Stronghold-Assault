class_name HeavyGunner
extends CharacterBody3D
## One trooper of a Gunner Squad (GunnerSquad): a minigunner in heavy armor. The squad tells it
## where to stand (goal), where to aim (aim_point) and when to fire (trigger); the trooper walks
## there itself, around whatever is in the way, and faces its aim. The squad's leader is driven
## instead (drive()), from the player's keys or the squad's AI.
##
## Animation: the rigged model's eight walk clips sit around Idle in a 2D blend space, by where
## the trooper is going relative to where it faces, sped up past their natural speeds
## (tools/blender/rig_heavy_gunner.py). GunnerRig bends the spine onto the aim and spins the barrels.

signal died(gunner: HeavyGunner)

const MODEL := "res://assets/defenders/heavy_gunner/heavy_gunner_rigged.glb"
## Collision: slimmer than the navmesh's agent radius (0.5 m), so paths hugging the stronghold's
## inside corners don't snag; a little shorter than the model, for the bunker's low ramps.
const RADIUS := 0.42
const HEIGHT := 2.1
const MAX_HP := 420.0
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
## Ledges it steps up onto (m).
const STEP_HEIGHT := 0.45
## Body turn rate; the spine takes up to TWIST_LIMIT of the aim on its own, ahead of the legs.
const TURN_RATE := deg_to_rad(160.0)
const TWIST_LIMIT := deg_to_rad(35.0)
const PITCH_MIN := deg_to_rad(-32.0)
const PITCH_MAX := deg_to_rad(42.0)
## Minigun: spins up before it fires, then a round every FIRE_INTERVAL. Overheats after HEAT_TIME
## seconds of firing (resting cools it as fast) and stays silent for OVERHEAT_TIME.
const SPIN_UP := 0.45
const SPIN_SPEED := 38.0
const FIRE_INTERVAL := 0.075
const DAMAGE := 6.0
const SPREAD := 0.032
## Minigun tracers are heavier than the rifles'.
const TRACER_WIDTH := 0.06
const RANGE := 160.0
const HEAT_TIME := 7.0
const OVERHEAT_TIME := 2.5
## How far off its aim the barrels may point and still fire (rad).
const AIM_TOLERANCE := deg_to_rad(12.0)
## A squad mate this close to the line of fire holds the trooper's fire (m).
const FRIENDLY_CLEARANCE := 0.75
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
var hp := MAX_HP
var max_hp := MAX_HP
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
var trigger := false
## Shots never hit these (the squad's own bodies).
var exclude: Array[RID] = []
## Damage per round is DAMAGE times this (the squad turns it down while nobody drives it).
var damage_scale := 1.0
var heat := 0.0
var hustle := false

var _model: Node3D
var _rig: GunnerRig
var _tree: AnimationTree
var _agent: NavigationAgent3D
var _shape: CollisionShape3D
var _spin_up := 0.0
var _fire_cd := 0.0
var _since_shot := 1.0
var _overheat := 0.0
var _blend := Vector2.ZERO
var _drive := Vector3.ZERO
var _driven := false
## The velocity it is trying to reach this frame (before acceleration and avoidance).
var _want := Vector3.ZERO
var _repath_cd := 0.0
var _path_goal := Vector3.INF
var _blocked := 0.0
var _unstick := 0.0
var _wall_away := Vector3.ZERO
var _tossed := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _gun_tilt := 0.0
var _wisp_cd := 0.0
var _flash: MeshInstance3D
var _flash_t := 0.0

static var _scene: PackedScene
static var _faded: Array[BaseMaterial3D] = []
static var _close_fade := true


## Troopers right in front of the camera dither away (on by default, for the squad's own camera).
static func set_close_fade(on: bool) -> void:
	_close_fade = on
	for mat in _faded:
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER if on else BaseMaterial3D.DISTANCE_FADE_DISABLED


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	add_to_group("gunners")
	collision_layer = GameConfig.LAYER_DEFENDERS
	# Squad mates and the garrison don't block each other: avoidance keeps them apart.
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_ATTACKERS
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)

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
	exclude.append(get_rid())


func _build_model() -> void:
	if _scene == null:
		_scene = load(MODEL)
	_model = Node3D.new()
	add_child(_model)
	var m := _scene.instantiate() as Node3D
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
	var skel: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	_rig = GunnerRig.new()
	skel.add_child(_rig)
	# Muzzle flash: a blink of light at the barrel tips on every round.
	_flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.16
	ball.height = 0.26
	ball.radial_segments = 8
	ball.rings = 4
	_flash.mesh = ball
	_flash.material_override = Mats.glow(Color(1.0, 0.72, 0.3), 6.0)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	# How far below level the barrels point in the clips (the export's gun droops a little).
	var g := skel.get_bone_global_rest(skel.find_bone("barrels")).basis.y.normalized()
	_gun_tilt = asin(clampf(g.y, -1.0, 1.0))


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
	if hp <= 0.0:
		return
	velocity = v * 0.4
	_tossed = true


func _die() -> void:
	hp = 0.0
	trigger = false
	remove_from_group("damageable")
	remove_from_group("defender_targets")
	remove_from_group("gunners")
	collision_layer = 0
	collision_mask = GameConfig.LAYER_WORLD
	_agent.avoidance_enabled = false
	_rig.spin_speed = 0.0
	_flash.visible = false
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


func overheated() -> bool:
	return _overheat > 0.0


## True once the barrels are spinning fast enough to fire.
func spun_up() -> bool:
	return _spin_up >= SPIN_UP


func muzzle() -> Vector3:
	return _rig.muzzle().origin


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
	_face(delta)
	_gun_tick(delta)
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


func _move(flat: Vector3, delta: float) -> void:
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	# Against a wall the velocity starts from nothing every frame: go by what it is trying to do.
	if is_on_wall() and _want.length() > 0.5 and flat.length() > 0.05:
		_step_up(flat.normalized() * 0.3)


## move_and_slide stops dead at a ledge (the step between the stronghold's halls and ramps): step
## up onto it if it is low enough and there is room.
func _step_up(motion: Vector3) -> void:
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up) or test_move(global_transform.translated(up), motion):
		return
	global_position += up + motion


## Follower: walk to the goal. Far off, or with something in the way, along a navmesh path at a
## catch-up pace; close in, it keeps pace with the leader and eases into its spot.
func _follow(delta: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	var want := Vector3.ZERO
	var walk := CLIP_FORWARD * lerpf(CATCH_UP, FAR_CATCH_UP, clampf((dist - 3.0) / 5.0, 0.0, 1.0)) * (1.25 if hustle else 1.0)
	_repath_cd -= delta
	if _repath_cd <= 0.0 or goal.distance_to(_path_goal) > 0.6:
		_repath_cd = REPATH
		_path_goal = goal
		_agent.target_position = goal
	var direct := dist < 2.5 and _agent.get_current_navigation_path().size() <= 2
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
	if hp <= 0.0 or _tossed or not following:
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
## TURN_RATE. Then lean the barrels onto it.
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
	var pitch := atan2(d.y, Vector2(d.x, d.z).length()) - _gun_tilt
	_rig.pitch = lerp_angle(_rig.pitch, clampf(pitch, PITCH_MIN, PITCH_MAX), minf(delta * 10.0, 1.0))


func _gun_tick(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0
	if _overheat > 0.0:
		_overheat -= delta
		if _overheat <= 0.0:
			heat = 0.0
		_wisp_cd -= delta
		if _wisp_cd <= 0.0:
			_wisp_cd = 0.12
			SmokeCloud.wisp(self, muzzle(), 0.7)
	var want_spin := trigger and _overheat <= 0.0
	_spin_up = clampf(_spin_up + (delta if want_spin else -delta * 0.6), 0.0, SPIN_UP)
	_rig.spin_speed = SPIN_SPEED * (_spin_up / SPIN_UP)
	_fire_cd -= delta
	_since_shot += delta
	if want_spin and spun_up():
		while _fire_cd <= 0.0:
			_fire_cd += FIRE_INTERVAL
			if _line_clear():
				_fire()
				_since_shot = 0.0
				# Every round heats the barrels: HEAT_TIME of steady fire overheats them.
				heat += FIRE_INTERVAL / HEAT_TIME
	else:
		_fire_cd = maxf(_fire_cd, 0.0)
	if _overheat <= 0.0:
		if heat >= 1.0:
			heat = 1.0
			_overheat = OVERHEAT_TIME
		elif _since_shot > FIRE_INTERVAL * 2.0:
			heat = maxf(heat - delta / HEAT_TIME, 0.0)
	# Anim: walk clips by where it goes relative to where it faces, sped up past their speeds.
	var local := global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var fwd := -local.z
	var b := Vector2(local.x / CLIP_SIDE, fwd / (CLIP_FORWARD if fwd >= 0.0 else CLIP_BACK))
	var scale := maxf(b.length(), 1.0)
	_blend = _blend.lerp(b / scale, minf(delta * 10.0, 1.0))
	_tree.set("parameters/move/blend_position", _blend)
	_tree.set("parameters/speed/scale", scale)


## True if no squad mate stands in the line of fire and the barrels are near the aim.
func _line_clear() -> bool:
	var from := muzzle()
	var to := aim_point
	var seg := to - from
	if seg.length() < 1.0:
		return false
	var barrel := _rig.muzzle().basis.y.normalized()
	if barrel.angle_to(seg) > AIM_TOLERANCE:
		return false
	for g in get_tree().get_nodes_in_group("gunners"):
		if g == self:
			continue
		var p: Vector3 = g.global_position + Vector3.UP * HEIGHT * 0.55
		var t := clampf((p - from).dot(seg) / seg.length_squared(), 0.0, 1.0)
		if (from + seg * t).distance_to(p) < FRIENDLY_CLEARANCE:
			return false
	return true


func _fire() -> void:
	var from := muzzle()
	Combat.fire_hitscan(self, from, aim_point, SPREAD, DAMAGE * damage_scale, team, 0.3, exclude, null, TRACER_WIDTH)
	_rig.kick()
	_flash.global_position = from
	_flash.scale = Vector3.ONE * randf_range(0.7, 1.25)
	_flash.visible = true
	_flash_t = 0.035
	if squad and squad.get("possessed") and squad.get("leader") == self:
		Combat.spawn_muzzle_light(self, from)
