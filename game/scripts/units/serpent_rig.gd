class_name SerpentRig
extends SkeletonModifier3D
## Poses the Serpent Sniper after its clips for its skills (AttackerUnit, SerpentNest, SerpentTrap). Bone
## names come from tools/gltf/rig_serpent.py: a chain from `head` down `spine_01` .. `spine_40` to the tail
## tip, each bone's Y axis along the body toward the tail and Z out of its back; `rifle` on its back,
## `muzzle` at the barrel's tip, `snout` at the tip of the snout.
##
## A skill lays the body along a path (SerpentPath, in world space, tail end first) with lay(): the snout at
## arc `front` along it, every bone at its own distance down the body behind it, so the body slides along
## the path without stretching (a snake's body follows where its head went). With a boom (the climb up a
## tree), the front of the body that carries the rifle (down to the shoulder, SHOULDER m from the snout)
## keeps its shape as it lies at rest, the head held up, and is held out from the shoulder along the boom's
## heading; the body behind it follows the path, easing into the boom's line over FILLET m. `weight` blends
## from the clip's pose (0) to the path's (1).
##
## The rifle rides its bone on the snake's back, or lies where it was set down (rifle_down, rifle_w: the bush
## trap); it kicks back along the barrel on every round (kick()). Dead (die()), a body laid along a path
## drops onto the ground where it lay and stays there.

## The front this far down the body from the snout carries the rifle (m): the boom.
const SHOULDER := 2.45
## The body behind the shoulder eases from the boom's line into the path over this much of it (m).
const FILLET := 0.5
## Recoil: how far the rifle kicks back along the barrel (m), and how fast it runs out again (m/s).
const RECOIL := 0.09
const RECOIL_BACK := 0.45
## How thick the body is down its length from the snout ([arc, radius], m: measured by rig_serpent.py).
const RADIUS := [[0.0, 0.09], [0.3, 0.15], [1.2, 0.19], [2.0, 0.19], [3.0, 0.15], [4.0, 0.11], [4.7, 0.06], [5.02, 0.02]]

var weight := 0.0
## The rifle: 0 riding the snake's back, 1 lying where it was set down (rifle_down, world).
var rifle_w := 0.0
var rifle_down := Transform3D.IDENTITY

var _path: SerpentPath
var _front := 0.0
var _boom := false
var _boom_xf := Transform3D.IDENTITY
var _chain: Array[int] = []
## Each bone of the chain: how far down the body from the snout it is (m), and (front bones) where it lies
## at rest in the boom's frame (the shoulder's, facing the snout).
var _bone_s: Array[float] = []
var _boom_rest: Array[Transform3D] = []
var _shoulder := 0
var _rifle := -1
var _muzzle := -1
var _snout := -1
var _snout_rest := Transform3D.IDENTITY
var _kick := 0.0
var _posed := false
var _muzzle_xf := Transform3D.IDENTITY
var _rifle_xf := Transform3D.IDENTITY
var _head_xf := Transform3D.IDENTITY
var _body := PackedVector3Array()
var _body_ups := PackedVector3Array()
## Dead on a path: seconds since, the ground under it, where its bones were (world) and the poses it settled
## into, and where its rifle lay then (skeleton space, so that it sinks into the ground with the body).
var _dead := -1.0
var _ground := 0.0
var _dead_at := PackedVector3Array()
var _dead_ups := PackedVector3Array()
var _settled: Array[Transform3D] = []
var _rifle_dead := Transform3D.IDENTITY


## Lays the body along `path` (world, tail end first) with the snout at arc `front`; with `boom` (a world
## transform at the shoulder: -Z toward the snout, Y out of the back) the front is held out along it.
func lay(path: SerpentPath, front: float, boom = null) -> void:
	_path = path
	_front = front
	_boom = boom != null
	if _boom:
		_boom_xf = boom


## The rifle kicks back (a round fired).
func kick() -> void:
	_kick = RECOIL


## Dead: a body laid along a path drops to the ground (at `ground` height) where it lay.
func die(ground: float) -> void:
	if weight <= 0.0 or _path == null or not _posed:
		return
	_dead = 0.0
	_ground = ground
	_dead_at = _body.slice(1)
	_dead_ups = _body_ups.slice(1)


## World transforms as of the last frame: the muzzle (Y out of the barrel), the rifle, the head.
func muzzle() -> Transform3D:
	return _muzzle_xf


func rifle() -> Transform3D:
	return _rifle_xf


func head() -> Transform3D:
	return _head_xf


## False until the skeleton has been posed once (the transforms above are still unset).
func posed() -> bool:
	return _posed


## The body as it lies (world, as of the last frame): the snout, then every bone of the chain down to the
## tail tip, and the way its back faces at each. A skill starts from it.
func body_path() -> SerpentPath:
	var path := SerpentPath.new()
	for k in range(_body.size() - 1, -1, -1):
		path.add(_body[k], _body_ups[k])
	return path


## How far down the body from the snout the tail tip is (m).
func length() -> float:
	return _bone_s[-1] if not _bone_s.is_empty() else 5.0


## How thick the body is `s` m down it from the snout.
static func radius(s: float) -> float:
	for k in range(1, RADIUS.size()):
		if s <= RADIUS[k][0]:
			return lerpf(RADIUS[k - 1][1], RADIUS[k][1], (s - RADIUS[k - 1][0]) / (RADIUS[k][0] - RADIUS[k - 1][0]))
	return RADIUS[-1][1]


func _find(skel: Skeleton3D) -> void:
	_chain.append(skel.find_bone("head"))
	var k := 1
	while skel.find_bone("spine_%02d" % k) >= 0:
		_chain.append(skel.find_bone("spine_%02d" % k))
		k += 1
	_rifle = skel.find_bone("rifle")
	_muzzle = skel.find_bone("muzzle")
	_snout = skel.find_bone("snout")
	var snout := skel.get_bone_global_rest(_snout)
	_snout_rest = skel.get_bone_rest(_snout)
	var s := snout.origin.distance_to(skel.get_bone_global_rest(_chain[0]).origin)
	for i in _chain.size():
		if i > 0:
			s += skel.get_bone_global_rest(_chain[i]).origin.distance_to(skel.get_bone_global_rest(_chain[i - 1]).origin)
		_bone_s.append(s)
	_shoulder = 0
	for i in _chain.size():
		if absf(_bone_s[i] - SHOULDER) < absf(_bone_s[_shoulder] - SHOULDER):
			_shoulder = i
	# The boom's frame at rest: at the shoulder, -Z toward the snout, Y up out of the back.
	var at := skel.get_bone_global_rest(_chain[_shoulder]).origin
	var fwd := (snout.origin - at).normalized()
	var frame := Transform3D(Basis.looking_at(fwd, Vector3.UP), at)
	for i in _shoulder + 1:
		_boom_rest.append(frame.affine_inverse() * skel.get_bone_global_rest(_chain[i]))


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _chain.is_empty():
		_find(skel)
	_kick = move_toward(_kick, 0.0, RECOIL_BACK * delta)
	if _dead >= 0.0:
		_pose_dead(skel, delta)
	elif weight > 0.0 and _path != null and _path.points.size() >= 2:
		_pose(skel, _targets(skel), weight)
	_pose_rifle(skel)
	_record(skel)


## Skeleton-space transforms for every bone of the chain, laid along the path (and the boom).
func _targets(skel: Skeleton3D) -> Array[Transform3D]:
	var inv := skel.global_transform.affine_inverse()
	var pts := PackedVector3Array()
	var ups := PackedVector3Array()
	var boom_y := _boom_xf.basis.y.normalized()
	for i in _chain.size():
		var p := _path.at(_front - _bone_s[i])
		var u := _path.up_at(_front - _bone_s[i])
		if _boom:
			if i <= _shoulder:
				pts.append(Vector3.ZERO)  # placed rigidly below
				ups.append(boom_y)
				continue
			# Easing out of the boom's line into the path.
			var past := _bone_s[i] - _bone_s[_shoulder]
			if past < FILLET:
				var t := past / FILLET
				t = t * t * (3.0 - 2.0 * t)
				var line := _boom_xf.origin + _boom_xf.basis.z.normalized() * past
				p = line.lerp(p, t)
				u = boom_y.slerp(u, t)
		pts.append(p)
		ups.append(u)
	var out: Array[Transform3D] = []
	for i in _chain.size():
		if _boom and i <= _shoulder:
			out.append(inv * (_boom_xf * _boom_rest[i]))
			continue
		var p := pts[i]
		var y := (pts[i + 1] - p) if i + 1 < pts.size() else (p - pts[i - 1])
		if y.length_squared() < 1e-8:
			y = -_path.tangent_at(_front - _bone_s[i])
		y = y.normalized()
		var z := ups[i] - y * ups[i].dot(y)
		z = z.normalized() if z.length_squared() > 1e-6 else y.cross(Vector3.RIGHT).normalized()
		out.append(inv * Transform3D(Basis(y.cross(z), y, z), p))
	return out


## Sets the chain's poses from skeleton-space transforms, blended with the clip's by `w`.
func _pose(skel: Skeleton3D, targets: Array[Transform3D], w: float) -> void:
	for i in _chain.size():
		var local := targets[i] if i == 0 else targets[i - 1].affine_inverse() * targets[i]
		var bone := _chain[i]
		if w < 1.0:
			local = skel.get_bone_pose(bone).interpolate_with(local, w)
		skel.set_bone_pose_position(bone, local.origin)
		skel.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())


## Dead on a path: every bone falls straight down to the ground where it was, rolling onto its belly as it
## lands, then it lies as it settled.
func _pose_dead(skel: Skeleton3D, delta: float) -> void:
	if not _settled.is_empty():
		_pose(skel, _settled, 1.0)
		return
	_dead += delta
	var drop := 0.5 * 9.8 * _dead * _dead
	var floor_y := _ground + 0.12
	var pts := PackedVector3Array()
	var ups := PackedVector3Array()
	var down := true
	for i in _dead_at.size():
		var p := _dead_at[i]
		var y := maxf(p.y - drop, floor_y)
		down = down and y <= floor_y + 0.001
		pts.append(Vector3(p.x, y, p.z))
		ups.append(_dead_ups[i].slerp(Vector3.UP, clampf(drop / maxf(p.y - floor_y, 0.05), 0.0, 1.0)))
	var inv := skel.global_transform.affine_inverse()
	var targets: Array[Transform3D] = []
	for i in pts.size():
		var y := (pts[i + 1] - pts[i]) if i + 1 < pts.size() else (pts[i] - pts[i - 1])
		y = y.normalized() if y.length_squared() > 1e-8 else Vector3.FORWARD
		var z := ups[i] - y * ups[i].dot(y)
		z = z.normalized() if z.length_squared() > 1e-6 else y.cross(Vector3.RIGHT).normalized()
		targets.append(inv * Transform3D(Basis(y.cross(z), y, z), pts[i]))
	_pose(skel, targets, 1.0)
	if down or _dead > 2.0:
		_settled = targets
		_rifle_dead = inv * rifle_down


func _pose_rifle(skel: Skeleton3D) -> void:
	var rest := skel.get_bone_rest(_rifle)
	var local := Transform3D(rest.basis, rest.origin - rest.basis.y.normalized() * _kick)
	if rifle_w > 0.0:
		var parent := skel.get_bone_global_pose(skel.get_bone_parent(_rifle))
		var down := _rifle_dead if not _settled.is_empty() else skel.global_transform.affine_inverse() * rifle_down
		local = parent.affine_inverse() * (parent * local).interpolate_with(down, rifle_w)
	skel.set_bone_pose_position(_rifle, local.origin)
	skel.set_bone_pose_rotation(_rifle, local.basis.get_rotation_quaternion())


func _record(skel: Skeleton3D) -> void:
	var xf := skel.global_transform
	_muzzle_xf = xf * skel.get_bone_global_pose(_muzzle)
	_rifle_xf = xf * skel.get_bone_global_pose(_rifle)
	_head_xf = xf * skel.get_bone_global_pose(_chain[0])
	_body.resize(_chain.size() + 1)
	_body_ups.resize(_chain.size() + 1)
	var snout := xf * skel.get_bone_global_pose(_chain[0]) * _snout_rest
	_body[0] = snout.origin
	_body_ups[0] = snout.basis.z.normalized()
	for i in _chain.size():
		var b := xf * skel.get_bone_global_pose(_chain[i])
		_body[i + 1] = b.origin
		_body_ups[i + 1] = b.basis.z.normalized()
	_posed = true
