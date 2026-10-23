class_name HeavyGunner
extends SquadTrooper
## One trooper of a Gunner Squad (GunnerSquad): a minigunner in heavy armor. Walks and aims like
## every squad trooper (SquadTrooper); the squad says when to fire (trigger).
##
## The rigged model's clips come from tools/blender/rig_heavy_gunner.py. GunnerRig bends the spine
## onto the aim and spins the barrels.

const MODEL := "res://assets/defenders/heavy_gunner/heavy_gunner_rigged.glb"
const MAX_HP := 420.0
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

var trigger := false
## Damage per round is DAMAGE times this (the squad turns it down while nobody drives it).
var damage_scale := 1.0
var heat := 0.0

var _spin_up := 0.0
var _fire_cd := 0.0
var _since_shot := 1.0
var _overheat := 0.0
var _gun_tilt := 0.0
var _wisp_cd := 0.0
var _flash: MeshInstance3D
var _flash_t := 0.0


func _init() -> void:
	max_hp = MAX_HP
	hp = MAX_HP


func _model_path() -> String:
	return MODEL


func _new_rig() -> TrooperRig:
	return GunnerRig.new()


func _build_weapon() -> void:
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
	var g := _skel.get_bone_global_rest(_skel.find_bone("barrels")).basis.y.normalized()
	_gun_tilt = asin(clampf(g.y, -1.0, 1.0))


func _spine_pitch(pitch: float) -> float:
	return clampf(pitch - _gun_tilt, PITCH_MIN, PITCH_MAX)


func _weapon_down() -> void:
	trigger = false
	(_rig as GunnerRig).spin_speed = 0.0
	_flash.visible = false


func overheated() -> bool:
	return _overheat > 0.0


## True once the barrels are spinning fast enough to fire.
func spun_up() -> bool:
	return _spin_up >= SPIN_UP


func muzzle() -> Vector3:
	return (_rig as GunnerRig).muzzle().origin


func _weapon_tick(delta: float) -> void:
	var rig := _rig as GunnerRig
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
	rig.spin_speed = SPIN_SPEED * (_spin_up / SPIN_UP)
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


## True if no squad mate stands in the line of fire and the barrels are near the aim.
func _line_clear() -> bool:
	var from := muzzle()
	var to := aim_point
	var seg := to - from
	if seg.length() < 1.0:
		return false
	var barrel := (_rig as GunnerRig).muzzle().basis.y.normalized()
	if barrel.angle_to(seg) > AIM_TOLERANCE:
		return false
	for g in get_tree().get_nodes_in_group("troopers"):
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
	(_rig as GunnerRig).kick()
	_flash.global_position = from
	_flash.scale = Vector3.ONE * randf_range(0.7, 1.25)
	_flash.visible = true
	_flash_t = 0.035
	if squad and squad.get("possessed") and squad.get("leader") == self:
		Combat.spawn_muzzle_light(self, from)
