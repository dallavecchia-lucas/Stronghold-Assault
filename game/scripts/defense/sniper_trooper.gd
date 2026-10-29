class_name SniperTrooper
extends SquadTrooper
## The Sniper's body (Sniper): the Grey Veil Warden in her ghillie cape, the Eclipse Longshot shouldered.
## She walks and aims like a squad trooper (SquadTrooper); the Sniper says when and where she fires
## (shoot).
##
## The rifle: a bolt action, MAG rounds a magazine. Each round flies straight (up to RANGE) and hurts the
## first thing in its way (the Sniper tags what it hits); everyone sees its long tracer and the white
## trail it leaves (SniperTrail). Then she works the bolt for BOLT_TIME; empty, she reloads (RELOAD_TIME).
##
## The rigged model's clips come from tools/gltf/rig_sniper.py: a rifleman's stance, the butt in her
## shoulder and her head down on the stock. SniperRig finds the rifle's bone; the rifle's model hangs on
## it, and its marker nodes (tools/gltf/process_rifle.py) give the muzzle and the eye behind the scope.
## Her meshes are on BODY_LAYER only, so the scope's camera can leave her out (Sniper).

const MODEL := "res://assets/defenders/grey_veil_warden/sniper_rigged.glb"
const RIFLE := "res://assets/defenders/grey_veil_warden/eclipse_longshot.glb"
const MAX_HP := 300.0
const MAG := 5
const BOLT_TIME := 1.5
const RELOAD_TIME := 2.8
const RANGE := 400.0
## The spine bends onto aims this far up or down at most (rad).
const PITCH_MIN := deg_to_rad(-40.0)
const PITCH_MAX := deg_to_rad(50.0)
## Render layer her meshes and the rifle's are on (and nothing else).
const BODY_LAYER := 1 << 19
## How far off the way to its aim the rifle may point and still count as on it (rad).
const AIM_TOLERANCE := deg_to_rad(4.0)

var ammo := MAG
## Rounds fired and hits (the showcase and the autotest count them).
var stats := {"rounds": 0, "hits": 0}

var _bolt := 0.0
var _reload := 0.0
var _rifle: Node3D
var _muzzle_mark: Node3D
var _eye_mark: Node3D
var _flash: MeshInstance3D
var _flash_t := 0.0

static var _rifle_scene: PackedScene


func _init() -> void:
	max_hp = MAX_HP
	hp = MAX_HP
	station_kind = "sniper"


func _model_path() -> String:
	return MODEL


func _new_rig() -> TrooperRig:
	return SniperRig.new()


func _build_weapon() -> void:
	if _rifle_scene == null:
		_rifle_scene = load(RIFLE)
	_rifle = _rifle_scene.instantiate() as Node3D
	_rifle.top_level = true
	add_child(_rifle)
	_muzzle_mark = _rifle.find_child("muzzle", true, false) as Node3D
	_eye_mark = _rifle.find_child("eye", true, false) as Node3D
	(_rig as SniperRig).on_posed = _hold_rifle
	# Muzzle flash: a blink of light at the muzzle brake on every round.
	_flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.14
	ball.height = 0.24
	ball.radial_segments = 8
	ball.rings = 4
	_flash.mesh = ball
	_flash.material_override = Mats.glow(Color(1.0, 0.8, 0.45), 7.0)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = BODY_LAYER


func _spine_pitch(pitch: float) -> float:
	return clampf(pitch, PITCH_MIN, PITCH_MAX)


func _weapon_down() -> void:
	_flash.visible = false


## The rifle on its bone, every frame once the rig has posed it.
func _hold_rifle() -> void:
	_rifle.global_transform = (_rig as SniperRig).rifle()


func _weapon_tick(delta: float) -> void:
	_bolt = maxf(_bolt - delta, 0.0)
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_reload = 0.0
			ammo = MAG
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	if _flash.visible:
		_flash.global_position = muzzle_point()


# ---------------------------------------------------------------- the rifle

## A round chambered and her rifle up: she can fire.
func ready_to_fire() -> bool:
	return hp > 0.0 and ammo > 0 and _bolt <= 0.0 and _reload <= 0.0


func reloading() -> bool:
	return _reload > 0.0


## How far the next round is from chambered (0 just fired or empty, 1 ready), for the panel.
func chamber() -> float:
	if _reload > 0.0:
		return 1.0 - _reload / RELOAD_TIME
	return 1.0 - _bolt / BOLT_TIME


## R: a fresh magazine (RELOAD_TIME), unless it is full.
func reload() -> void:
	if _reload <= 0.0 and ammo < MAG and hp > 0.0:
		_reload = RELOAD_TIME


## The muzzle brake's mouth (the tracer starts there).
func muzzle_point() -> Vector3:
	return _muzzle_mark.global_position if _muzzle_mark and (_rig as SniperRig).posed() else global_position + Vector3.UP * 1.45 - global_basis.z * 1.1


## Her eye behind the scope (the scope's view, and where her own aim starts).
func eye_point() -> Vector3:
	return _eye_mark.global_position if _eye_mark and (_rig as SniperRig).posed() else global_position + Vector3.UP * 1.55


## The way the rifle points.
func rifle_dir() -> Vector3:
	return (_rifle.global_basis.z).normalized()


## The rifle points at `point` (within AIM_TOLERANCE).
func on_aim(point: Vector3) -> bool:
	if not (_rig as SniperRig).posed():
		return false
	return rifle_dir().angle_to(point - eye_point()) <= AIM_TOLERANCE


## One round from `from` at `to` (spread `spread` rad about the line), `damage` to the first thing in its
## way. The tracer and the trail run from the muzzle to where it lands. Returns {"position", "unit"}: where
## it landed and the defender's enemy it hit (null: none).
func shoot(from: Vector3, to: Vector3, damage: float, spread: float) -> Dictionary:
	ammo -= 1
	_bolt = BOLT_TIME
	stats.rounds += 1
	var dir := (to - from).normalized()
	if spread > 0.0:
		dir = Combat.apply_spread(dir, spread)
	var end := from + dir * RANGE
	var q := PhysicsRayQueryParameters3D.create(from, end, GameConfig.LAYER_ALL_SOLID, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var struck: Node = null
	if not hit.is_empty():
		end = hit.position
		var d = Combat.find_damageable(hit.collider)
		if d and d.team != team and d.is_alive():
			var mult: float = 0.3 if d.is_in_group("structures") else 1.0
			d.take_damage(damage * mult, team)
			struck = d
			stats.hits += 1
		Combat.spawn_impact(self, end, struck != null)
		if struck == null:
			SmokeCloud.wisp(self, end, 0.7)
	var muzzle := muzzle_point()
	SniperTrail.fire(self, muzzle, end)
	_flash_t = 0.06
	Combat.spawn_muzzle_light(self, muzzle)
	# Her own scope doesn't see the smoke at the muzzle a metre in front of it (BODY_LAYER).
	SmokeCloud.wisp(self, muzzle, 0.6, BODY_LAYER)
	if ammo <= 0:
		reload()
	return {"position": end, "unit": struck}
