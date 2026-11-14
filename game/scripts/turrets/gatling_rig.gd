class_name GatlingRig
extends "res://scripts/turrets/turret_rig.gd"
## A rotary gun's rig (the Orbital Sentry Gun's and the Sentinel Bastion's): what a gatling does on top of TurretRig.
##
## The barrels (`barrels`) are driven by a motor. While the owner holds `spinning` on (it has a target, or the player
## has the trigger down) the motor runs them up to SPIN in SPIN_UP s, and the gun fires only once they are turning
## fast enough (ready_to_fire: a gatling that is not turning has no bolt in battery). The trigger let go, they coast
## down on their bearings over SPIN_DOWN s. Fast, the cluster blurs (a sleeve round it, thicker the faster it turns).
##
## fire_round() is one round going off: the gun is hammered back in its cradle and jumps a hair, the turret shivers
## on its ring, a spent case is thrown out of the port under the receiver and the ammunition drum (`drum`) is pulled
## round a step by the belt. The barrels heat as they fire (`barrel_heat`: every round warms them, the air cools them
## slowly, so a long fight shows and a short burst does not) and with the owner's `heat` (the gun run to its limit):
## warm they glow dull red, then orange, and hot they trail smoke from the muzzle, heaviest when the gun has just
## stopped.

## The barrels at full speed (rad/s), how long the motor takes to get them there and how long they coast down (s);
## how much of full speed the gun needs to fire.
const SPIN := TAU * 13.0
const SPIN_UP := 0.42
const SPIN_DOWN := 2.4
const READY := 0.7
## A round's kick: the jump on the trunnion and the turret's shiver (rad), how far the gun is driven back (m).
const JUMP := deg_to_rad(0.22)
const ROCK := deg_to_rad(0.12)
const BACK := 0.014
## How far a round turns the drum (rad), and how fast a case leaves (m/s).
const DRUM_STEP := deg_to_rad(11.0)
const CASE_SPEED := 2.6
## The heat the barrels start to glow at, and to smoke at; how much a round warms them and how fast they cool (1/s).
const GLOW_FROM := 0.35
const SMOKE_FROM := 0.6
const ROUND_HEAT := 0.016
const COOLING := 0.05

## The motor runs the barrels up while this is on (the owner: a target held, or the trigger down).
var spinning := false
## The barrels' speed (rad/s) and where they are (rad).
var spin_rate := 0.0
var spin_angle := 0.0
## Rounds fired so far.
var rounds := 0
## 0..1: how hot the barrels have fired themselves.
var barrel_heat := 0.0

var _blur: MeshInstance3D
var _blur_shown := 0.0
var _drum := 0.0
var _drum_to := 0.0
var _since_round := INF
var _smoke_cd := 0.0


## Each rig says how big its cases are: (radius, length) m.
func _case_size() -> Vector2:
	return Vector2(0.017, 0.085)


func _setup() -> void:
	_glowing(["barrels"])
	var b := part("barrels") as MeshInstance3D
	if b and b.mesh:
		# The blur: a sleeve round the cluster (the barrels' node has its Y along the bore).
		var box := b.mesh.get_aabb()
		var tube := CylinderMesh.new()
		tube.top_radius = maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z))) * 0.93
		tube.bottom_radius = tube.top_radius
		tube.height = box.size.y * 0.97
		tube.radial_segments = 20
		tube.rings = 1
		_blur = MeshInstance3D.new()
		_blur.mesh = tube
		_blur.position.y = box.get_center().y
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.07, 0.07, 0.075, 0.0)
		m.metallic = 0.6
		m.roughness = 0.45
		m.cull_mode = BaseMaterial3D.CULL_BACK
		_blur.material_override = m
		_blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blur.visible = false
		b.add_child(_blur)
	var size := _case_size()
	_cases(22, size.x, size.y)


## Turning fast enough to fire.
func ready_to_fire() -> bool:
	return spin_rate >= SPIN * READY


## One round goes off (see the top).
func fire_round() -> void:
	rounds += 1
	_since_round = 0.0
	barrel_heat = minf(barrel_heat + ROUND_HEAT, 1.0)
	_kick(JUMP * randf_range(0.7, 1.3), ROCK, BACK)
	_drum_to += DRUM_STEP
	_eject(CASE_SPEED)


func _animate(delta: float) -> void:
	_since_round += delta
	var motor := (spinning or _since_round < 0.2) and not wrecked
	if motor:
		spin_rate = move_toward(spin_rate, SPIN, SPIN / SPIN_UP * delta)
	else:
		# Coasting: the drag eases off as they slow, then the bearings stop them.
		spin_rate = maxf(spin_rate - SPIN / SPIN_DOWN * (0.35 + 0.9 * spin_rate / SPIN) * delta * (4.0 if wrecked else 1.0), 0.0)
	if spin_rate > 0.0 or _blur_shown > 0.0:
		spin_angle = fposmod(spin_angle + spin_rate * delta, TAU)
		spin("barrels", spin_angle)
		if _blur:
			var k := smoothstep(0.25, 0.9, spin_rate / SPIN)
			_blur_shown = k
			_blur.visible = k > 0.02
			(_blur.material_override as StandardMaterial3D).albedo_color.a = 0.5 * k
	if has_part("drum") and absf(_drum_to - _drum) > 0.0005:
		_drum = lerpf(_drum, _drum_to, 1.0 - exp(-delta * 18.0))
		spin("drum", _drum)
	barrel_heat = maxf(barrel_heat - COOLING * delta, 0.0)
	var hot := maxf(heat, barrel_heat)
	_set_glow(smoothstep(GLOW_FROM, 1.0, hot))
	# Hot barrels smoke: a trail while they turn, thicker for a moment after the firing stops.
	_smoke_cd -= delta
	if hot > SMOKE_FROM and _smoke_cd <= 0.0 and is_visible_in_tree():
		var resting := _since_round > 0.25
		_smoke_cd = lerpf(0.5, 0.16, smoothstep(SMOKE_FROM, 1.0, hot)) * (0.7 if resting else 1.4)
		var at := muzzle()
		SmokeCloud.wisp(self, at.origin + at.basis.z * randf_range(-0.5, 0.05), 0.35 + 0.5 * hot)
