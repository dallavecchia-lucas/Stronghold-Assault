class_name DefenderMachine
extends CharacterBody3D
## A defender post that is one machine the player flies or drives in third person: the Fighter Jet (DefenderJet) and the
## Hover Tank (DefenderTank). Bought with credits like a squad (DefenderArmory), it sits on the same roster (the hotbar:
## SquadHotbar; F1-F6 takes command) and is a station like the others (see DefenderController for the interface): the
## player's camera rides on it, the attackers shoot at it (it is a "defender_target"), and once it is down it is gone for
## good (wiped_out), however it went (shot, crashed).
##
## The machine itself is a body in the DEFENDERS layer so shots can hit it; whoever moves it just sets its transform.
## Subclasses fly or drive it (_control, _idle), and draw its HUD.

signal became_unavailable(station)
## Gone for good (the armory takes it off the roster).
signal wiped_out(squad)

## After going down, how long the player's camera stays on the wreck (s) before the post is given up.
const WRECK_VIEW := 3.2
const HURT_TIME := 0.5

var station_name := "Machine"
var station_kind := "machine"
var hud_title := "MACHINE"
var team := GameConfig.TEAM_DEFENDER
var possessed := false
## Once down, it doesn't come back.
var respawns := false
var squad_size := 1
## The post it was bought for (a gate spawn hall's frame, facing its ramp): where it deploys from.
var home := Transform3D.IDENTITY
var gates: Array = []
var number := 1
var hp := 500.0
var max_hp := 500.0
var target_radius := 3.0
## How high over its origin the attackers aim.
var aim_height := 2.0
## The map's half-width (m) and the middle of the stronghold (what a machine left alone keeps near).
var map_half := 800.0
var loiter_centre := Vector3.ZERO
## Showcase autopilot: an object with pilot_input(machine, delta) that fills `input` instead of the keyboard and mouse.
var pilot: Object = null
var input := {}
## Totals (the showcase and the autotest report them).
var stats := {}

var _cam: Camera3D
var _hud_layer: CanvasLayer
var _hud: Control
var _dead := false
var _death_t := 0.0
var _hurt := 0.0
var _notice := ""
var _notice_t := 0.0


## Names it after its purchase number.
func setup(n: int) -> void:
	number = n


# ---------------------------------------------------------------- the roster (SquadHotbar)

func roster_label() -> String:
	return station_name


func order_name() -> String:
	return ""


func order_color() -> Color:
	return UIKit.WARN


## The slot catches the eye while it is being hit.
func alert() -> bool:
	return _hurt > 0.0 and not possessed


func doing(_driving: bool) -> String:
	return ""


func cycle_order() -> void:
	pass


## Health pips for the hotbar: one fraction (0..1) each.
func pips() -> Array:
	return [clampf(hp / max_hp, 0.0, 1.0)]


# ---------------------------------------------------------------- a target

func is_alive() -> bool:
	return hp > 0.0 and not _dead


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * aim_height


func take_damage(amount: float, from_team: int) -> void:
	if not is_alive() or from_team == team:
		return
	hp -= amount
	_hurt = HURT_TIME
	if hp <= 0.0:
		hp = 0.0
		_go_down("shot")


## What the player is told when it goes down.
func down_message() -> String:
	return "%s is lost" % station_name


# ---------------------------------------------------------------- station interface

func can_possess() -> bool:
	return is_alive()


func possess() -> void:
	possessed = true
	if _cam:
		_cam.current = true
	if _hud_layer:
		_hud_layer.visible = true
	_on_possess()


func unpossess() -> void:
	possessed = false
	if _cam:
		_cam.current = false
	if _hud_layer:
		_hud_layer.visible = false


func wants_captured_mouse() -> bool:
	return true


func get_station_position() -> Vector3:
	return global_position


func get_camera() -> Camera3D:
	return _cam


func get_hud_info() -> Dictionary:
	return {"weapon": "", "status": "—", "hp": hp / max_hp, "hint": ""}


## A line in the middle of the screen now and then (a warning, what just happened).
func notice() -> String:
	return _notice if _notice_t > 0.0 else ""


func say(text: String, seconds := 2.0) -> void:
	_notice = text
	_notice_t = seconds


# ---------------------------------------------------------------- for the subclasses

## Builds the machine (its model, collider); called once, in _ready.
func _build() -> void:
	pass


## The control panel for the machine (a Control that fills the screen), or null.
func _make_hud() -> Control:
	return null


func _on_possess() -> void:
	pass


## The player flies or drives it (or the showcase's pilot).
func _control(_delta: float) -> void:
	pass


## Left alone: whatever it does by itself.
func _idle(_delta: float) -> void:
	pass


## It has just gone down (`reason`: "shot", "crashed"). The subclass puts on the show; the post is given up WRECK_VIEW later.
func _on_down(_reason: String) -> void:
	pass


func _chase_camera(_delta: float) -> void:
	pass


func _read_input() -> void:
	pass


# ---------------------------------------------------------------- the frame

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("defender_targets")
	collision_layer = GameConfig.LAYER_DEFENDERS
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_cam = Camera3D.new()
	_cam.near = 0.2
	_cam.far = 5000.0
	add_child(_cam)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 3
	_hud_layer.visible = false
	add_child(_hud_layer)
	_hud = _make_hud()
	if _hud:
		_hud_layer.add_child(_hud)
	_build()


func _physics_process(delta: float) -> void:
	_hurt = maxf(_hurt - delta, 0.0)
	_notice_t = maxf(_notice_t - delta, 0.0)
	if _dead:
		_death_t -= delta
		_wreck(delta)
		if _death_t <= 0.0:
			_give_up()
		return
	if possessed:
		if pilot != null:
			pilot.pilot_input(self, delta)
		else:
			_read_input()
		_control(delta)
	else:
		_idle(delta)


func _process(delta: float) -> void:
	if possessed or _dead:
		_chase_camera(delta)


## Going down: the subclass's show, then (after WRECK_VIEW if the player is on it) the post is given up.
func _go_down(reason: String) -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	_death_t = WRECK_VIEW if possessed else 0.5
	collision_layer = 0
	remove_from_group("defender_targets")
	_on_down(reason)


## While it lies a wreck (the player's camera still on it).
func _wreck(_delta: float) -> void:
	pass


func _give_up() -> void:
	set_physics_process(false)
	became_unavailable.emit(self)
	wiped_out.emit(self)
