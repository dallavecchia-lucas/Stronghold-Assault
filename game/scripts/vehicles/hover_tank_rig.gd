class_name HoverTankRig
extends VehicleRig
## The defenders' Iron Vanguard hover tank (assets_src/defenders/iron_vanguard, cut by tools/gltf/rig_vehicles.py):
## 10 m long with its gun forward, 6 m wide. It rides HOVER over the ground on four hover thrusters under the hull
## (thruster_FL/FR/RL/RR), their blue jets (jet_*) pushing down. The thrusters gimbal: they lean the jets back to
## speed it up, forward to brake, out to the side to slide it, and opposite ways front and rear to turn it; the two
## rear vents (booster_L/R) burn with the forward push. The hull rides the air: it bobs, sits back on its tail as it
## speeds up, dips its nose braking and rolls out of its turns.
##
## The turret turns onto the aim (aim(), traverse TRAVERSE) and the gun elevates onto it (ELEVATE, between DEPRESSION
## and ELEVATION). Like MuleGun, aimed() says when it is on the aim; muzzle() is where the shell leaves.
##
## fire() works the main gun like a real tank gun's: the blast (a flash, a light, a cloud of smoke out of the muzzle)
## drives the barrel back RECOIL into its cradle in RECOIL_TIME, hard at first and braking against the buffers; it
## holds there a moment (HOLD), then the recuperator runs it out again, slowly and smoothly, over RUN_OUT_TIME. The
## muzzle jumps up and settles (JUMP), and the whole tank takes the kick: the hull rocks back on its air cushion away
## from the shot and sways back and forth a few times (ROCK, a damped spring), jolted back and shaken for a moment.
##
## The two coaxial machine guns either side of the cannon (coax_L/R, on the gun: they point where it points) fire
## like mounted machine guns while `coax_firing` is on: COAX_RATE rounds a second each, the two in turn, every round a
## flash at the muzzle and a little kick, every TRACER_EVERY-th a tracer to the aim (coax_round reports each round).

const MODEL := "res://assets/defenders/iron_vanguard/iron_vanguard.glb"
## Ride height over the ground (m) and its bob (m).
const HOVER := 0.7
const BOB := 0.06
## Turret traverse and gun elevation rates (rad/s), the gun's limits (rad).
const TRAVERSE := deg_to_rad(40.0)
const ELEVATE := deg_to_rad(25.0)
const DEPRESSION := deg_to_rad(-8.0)
const ELEVATION := deg_to_rad(28.0)
## How close to its aim (rad) the gun must be to fire.
const AIMED := deg_to_rad(1.5)
## The main gun's recoil: how far the barrel goes back (m) and in how long (s), how long it holds there, how long the
## recuperator takes to run it out again; how far the muzzle jumps up (rad) and how fast that settles (1/s).
const RECOIL := 0.6
const RECOIL_TIME := 0.14
const HOLD := 0.12
const RUN_OUT_TIME := 1.5
const JUMP := deg_to_rad(2.2)
const JUMP_SETTLE := 5.0
## The tank taking the kick: how far it rocks back (rad), its sway (Hz) and damping (1/s); how far it is jolted back
## (m) and how long it shakes (s).
const ROCK := deg_to_rad(2.6)
const ROCK_HZ := 1.6
const ROCK_DAMP := 2.2
const JOLT := 0.18
const SHAKE_TIME := 0.35
## The coaxial machine guns: rounds a second each, the kick per round (m), every how many rounds a tracer, the spread
## (rad), and how far they reach with nothing to aim at (m).
const COAX_RATE := 9.0
const COAX_KICK := 0.035
const TRACER_EVERY := 3
const COAX_SPREAD := 0.006
const COAX_RANGE := 400.0
## Thruster gimbal: the most it leans (rad) and how fast (rad/s); the rig's acceleration that leans it all the way.
const GIMBAL := deg_to_rad(22.0)
const GIMBAL_RATE := deg_to_rad(90.0)
const FULL_ACCEL := 4.0
## How the hull rides its acceleration (rad per m/s²; most).
const PITCH_PER_ACCEL := 0.012
const ROLL_PER_ACCEL := 0.012
const TILT_MAX := deg_to_rad(5.0)

const PADS := ["FL", "FR", "RL", "RR"]

## Inputs (when not following its motion): the push (-1..1 in its own frame: x left, z forward), the turn (-1..1,
## left +) and the hover thrusters' power (0..1).
var drive := Vector2.ZERO
var turn := 0.0
var lift := 0.7
## The coaxial machine guns fire while this is on.
var coax_firing := false

## A coaxial machine gun fired a round: from its muzzle to where it goes (world). For hit tests and sound.
signal coax_round(from: Vector3, to: Vector3)
## The main gun fired: the muzzle's world transform.
signal main_gun_fired(muzzle: Transform3D)

var _aim := Vector3.INF
var _yaw := 0.0
var _pitch := 0.0
## Seconds since the main gun last fired (INF: never), the muzzle's jump (rad).
var _since_shot := INF
var _jump := 0.0
var _jump_v := 0.0
## The hull's rock (a rotation vector in the model's frame) and its rate, its jolt (m, model frame) and rate.
var _rock := Vector3.ZERO
var _rock_v := Vector3.ZERO
var _jolt := Vector3.ZERO
var _jolt_v := Vector3.ZERO
var _shake := 0.0
var _flash: ThrusterFlame
var _flash_t := INF
var _coax_flash: Array[ThrusterFlame] = []
var _coax_kick := [0.0, 0.0]
var _coax_clock := 0.0
var _coax_rounds := 0
var _coax_dir := [Vector3.BACK, Vector3.BACK]
var _gimbal := {}
var _tilt := Vector2.ZERO
var _jets: Array[ThrusterFlame] = []
var _boosters: Array[ThrusterFlame] = []
## The turret's pivot in the model's frame and the gun's trunnion in the turret's.
var _turret_pivot := Vector3.ZERO
var _gun_pivot := Vector3.ZERO
var _recoil_dir := Vector3.BACK


func _model_path() -> String:
	return MODEL


func _build() -> void:
	model.position.y = HOVER
	for pad in PADS:
		var f := ThrusterFlame.new()
		f.length = 1.3
		f.radius = 0.42
		f.color = Color(0.35, 0.9, 2.8)
		f.light_range = 3.5
		var jet := part("jet_" + pad)
		if jet:
			jet.add_child(f)
		_jets.append(f)
	for side in ["L", "R"]:
		var f := ThrusterFlame.new()
		f.length = 2.2
		f.radius = 0.28
		f.color = Color(0.4, 1.0, 2.8)
		var b := part("booster_" + side)
		if b:
			b.add_child(f)
		_boosters.append(f)
	_turret_pivot = rest_of("turret").origin
	# The trunnion in the turret's frame, and the way the barrel kicks (back along it, in the gun's frame).
	_gun_pivot = rest_of("gun").origin
	if has_part("muzzle"):
		_recoil_dir = -(rest_of("barrel").basis * rest_of("muzzle").basis.z).normalized()
		_flash = ThrusterFlame.new()
		_flash.length = 4.5
		_flash.radius = 0.9
		_flash.color = Color(2.6, 1.3, 0.45)
		_flash.burner_color = Color(2.8, 2.0, 1.0)
		_flash.light_range = 22.0
		part("muzzle").add_child(_flash)
	for i in 2:
		var side: String = ["L", "R"][i]
		var f := ThrusterFlame.new()
		f.length = 0.9
		f.radius = 0.15
		f.color = Color(2.8, 1.7, 0.6)
		f.light_range = 4.0
		var m := part("coax_muzzle_" + side)
		if m:
			m.add_child(f)
			_coax_dir[i] = -(rest_of("coax_" + side).basis * rest_of("coax_muzzle_" + side).basis.z).normalized()
		_coax_flash.append(f)


## Turns the turret and the gun onto `point` (world).
func aim(point: Vector3) -> void:
	_aim = point


## Turns the turret back to the front and the gun level.
func stow() -> void:
	_aim = Vector3.INF


## True once the gun is on its aim.
func aimed() -> bool:
	if _aim == Vector3.INF:
		return false
	var want := _want()
	return absf(angle_difference(_yaw, want.x)) < AIMED and absf(_pitch - want.y) < AIMED


## Fires the main gun: the blast, the barrel's recoil and run-out, the muzzle's jump and the tank rocking.
func fire() -> void:
	_since_shot = 0.0
	_flash_t = 0.0
	_jump_v += JUMP * JUMP_SETTLE * 2.2
	# The kick goes back along the barrel: the hull's top is pushed away from the shot (it rocks about the
	# horizontal axis across the barrel) and the whole tank is jolted back.
	var d := Vector3(sin(_yaw), 0.0, cos(_yaw))  # where the barrel points, flat (the model's front is +Z)
	_rock_v += d.cross(Vector3.UP).normalized() * ROCK * TAU * ROCK_HZ
	_jolt_v += -d * JOLT * 9.0
	_shake = SHAKE_TIME
	_smoke(muzzle())
	main_gun_fired.emit(muzzle())


## How far the barrel is back in its cradle as of now (m; 0 run out).
func recoil() -> float:
	return _recoil_at(_since_shot)


## The hull's rock as of now (rad).
func rock() -> float:
	return _rock.length()


## Rounds the coaxial machine guns have fired.
func coax_rounds() -> int:
	return _coax_rounds


## The muzzle's world transform as of now; basis.z points out of the barrel.
func muzzle() -> Transform3D:
	return marker("muzzle")


## The turret's yaw (rad, left +) and the gun's elevation (rad, up +) as of now.
func turret_yaw() -> float:
	return _yaw


func gun_elevation() -> float:
	return _pitch


## A hover thruster's gimbal as of now (rad: about its X, about its Z).
func gimbal(pad: String) -> Vector2:
	return _gimbal.get(pad, Vector2.ZERO)


func _process(delta: float) -> void:
	_track(delta, 0.3)
	if follow_motion:
		drive = Vector2(clampf(local_accel.x / FULL_ACCEL, -1.0, 1.0), clampf(local_accel.z / FULL_ACCEL, -1.0, 1.0))
		# Cruising, it keeps pushing a little against the drag.
		drive.y = clampf(drive.y + local_velocity.z * 0.04, -1.0, 1.0)
		turn = clampf(local_spin.y * 1.5, -1.0, 1.0)
		lift = clampf(0.65 + absf(local_accel.y) * 0.1 + drive.length() * 0.2, 0.0, 1.0)
	# The hull on its air cushion.
	var want_tilt := Vector2(clampf(-local_accel.z * PITCH_PER_ACCEL, -TILT_MAX, TILT_MAX),
			clampf(local_accel.x * ROLL_PER_ACCEL + local_spin.y * local_velocity.z * 0.01, -TILT_MAX, TILT_MAX))
	_tilt = _tilt.lerp(want_tilt, 1.0 - exp(-delta * 2.5))
	_take_the_kick(delta)
	var shake := Vector3.ZERO
	if _shake > 0.0:
		_shake -= delta
		var k := clampf(_shake / SHAKE_TIME, 0.0, 1.0)
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012 * k * k
	model.position = Vector3(0.0, HOVER + sin(_age * 1.6) * BOB + sin(_age * 2.9) * BOB * 0.3, 0.0) + _jolt
	var b := Basis.from_euler(Vector3(_tilt.x + sin(_age * 1.3) * 0.006, 0.0, _tilt.y + sin(_age * 1.1) * 0.006) + shake)
	if _rock.length() > 1e-6:
		b = Basis(_rock.normalized(), _rock.length()) * b
	model.basis = b
	# Thrusters: lean each jet against where the hull is to go. A jet points down its pad's -Y; leaning the pad about
	# its X by +a swings the jet back (-Z), about its Z by +b swings it to the left (+X).
	for i in PADS.size():
		var pad: String = PADS[i]
		var front := 1.0 if pad.begins_with("F") else -1.0
		var push := Vector2(drive.y, -drive.x - turn * front * 0.8)
		var want := Vector2(clampf(push.x, -1.0, 1.0), clampf(push.y, -1.0, 1.0)) * GIMBAL
		var g: Vector2 = _gimbal.get(pad, Vector2.ZERO)
		g = Vector2(servo(g.x, want.x, GIMBAL_RATE, delta), servo(g.y, want.y, GIMBAL_RATE, delta))
		_gimbal[pad] = g
		spin("thruster_" + pad, 0.0, g)
		_jets[i].power = clampf(lift + 0.15 * sin(_age * 9.0 + i * 1.7), 0.0, 1.0)
	for f in _boosters:
		f.power = clampf(drive.y * 1.2, 0.0, 1.0)
	# Turret and gun.
	var want := _want()
	_yaw = wrapf(rotate_toward(_yaw, want.x, TRAVERSE * delta), -PI, PI)
	_pitch = move_toward(_pitch, want.y, ELEVATE * delta)
	spin("turret", _yaw)
	# The muzzle's jump: a stiff, well damped spring.
	_jump_v += (-JUMP_SETTLE * JUMP_SETTLE * _jump - 2.0 * JUMP_SETTLE * 0.7 * _jump_v) * delta
	_jump += _jump_v * delta
	hinge("gun", _pitch + _jump)
	_since_shot += delta
	slide("barrel", _recoil_dir * _recoil_at(_since_shot))
	_flash_t += delta
	if _flash:
		# The blast: a burst of flame that is gone in a tenth of a second.
		_flash.power = 2.0 * clampf(1.0 - _flash_t / 0.12, 0.0, 1.0)
	_coax(delta)


## The barrel's travel back (m) `t` seconds after a shot: driven back hard, braking against the buffers; held; run out
## by the recuperator, slow and smooth.
func _recoil_at(t: float) -> float:
	if t < RECOIL_TIME:
		var u := t / RECOIL_TIME
		return RECOIL * (1.0 - pow(1.0 - u, 3.0))
	if t < RECOIL_TIME + HOLD:
		return RECOIL
	var u := (t - RECOIL_TIME - HOLD) / RUN_OUT_TIME
	if u >= 1.0:
		return 0.0
	return RECOIL * (1.0 - u * u * (3.0 - 2.0 * u))


## The rock and the jolt: damped springs back to rest.
func _take_the_kick(delta: float) -> void:
	var w := TAU * ROCK_HZ
	_rock_v += (-w * w * _rock - ROCK_DAMP * _rock_v) * delta
	_rock += _rock_v * delta
	var wj := TAU * 1.2
	_jolt_v += (-wj * wj * _jolt - 4.0 * _jolt_v) * delta
	_jolt += _jolt_v * delta


## The coaxial machine guns: while firing, a round from each in turn at COAX_RATE a gun.
func _coax(delta: float) -> void:
	for i in 2:
		_coax_kick[i] = move_toward(_coax_kick[i], 0.0, COAX_KICK / 0.06 * delta)
		slide("coax_" + ["L", "R"][i], _coax_dir[i] * _coax_kick[i])
		_coax_flash[i].power = maxf(_coax_flash[i].power - delta / 0.04, 0.0)
	if not coax_firing:
		_coax_clock = 0.0
		return
	_coax_clock -= delta
	while _coax_clock <= 0.0:
		_coax_clock += 1.0 / (COAX_RATE * 2.0)
		var i := _coax_rounds % 2
		_coax_rounds += 1
		var side: String = ["L", "R"][i]
		_coax_kick[i] = COAX_KICK
		_coax_flash[i].power = randf_range(0.8, 1.2)
		var m := marker("coax_muzzle_" + side)
		var to := _aim if _aim != Vector3.INF else m.origin + m.basis.z * COAX_RANGE
		var dir := Combat.apply_spread((to - m.origin).normalized(), COAX_SPREAD)
		to = m.origin + dir * m.origin.distance_to(to)
		if _coax_rounds % TRACER_EVERY == 0:
			Combat.spawn_tracer(self, m.origin, to, Color(1.0, 0.55, 0.2), 0.05)
		coax_round.emit(m.origin, to)


## The cloud of smoke a shot throws out of the muzzle: puffs blown out ahead and to the sides, growing and fading.
func _smoke(at: Transform3D) -> void:
	var root := Combat._scene_root(self)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = SmokeCloud.puff_texture()
	mat.albedo_color = Color(0.48, 0.46, 0.43, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fwd := at.basis.z
	var side := fwd.cross(Vector3.UP).normalized()
	for k in 14:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		# Most go out ahead; the muzzle brake throws some out to the sides.
		var out := fwd * randf_range(1.0, 7.0) if k < 8 else (side * (1.0 if k % 2 == 0 else -1.0) * randf_range(1.5, 3.5) + fwd * 0.6)
		mi.global_position = at.origin + fwd * 0.4
		mi.scale = Vector3.ONE * randf_range(1.4, 2.4)
		var life := randf_range(2.0, 3.2)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", at.origin + out + Vector3.UP * randf_range(0.5, 1.6), life) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * randf_range(5.0, 8.0), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 3.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)


## The turret yaw and gun elevation that put the barrel on the aim (or the front, stowed).
func _want() -> Vector2:
	if _aim == Vector3.INF:
		return Vector2.ZERO
	# In the hull's steady frame (not shaken by its own shots).
	var local := (global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, HOVER, 0.0))).affine_inverse() * _aim
	var d := local - _turret_pivot
	var yaw := atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.5 else _yaw
	var from := _turret_pivot + Basis(Vector3.UP, yaw) * _gun_pivot
	var flat := Vector2(local.x - from.x, local.z - from.z).length()
	var pitch := clampf(atan2(local.y - from.y, maxf(flat, 0.1)), DEPRESSION, ELEVATION)
	return Vector2(yaw, pitch)
