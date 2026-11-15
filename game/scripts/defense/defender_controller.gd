class_name DefenderController
extends CanvasLayer
## Human defender: jumps between stations (number keys / Tab) and shows the FPS HUD.
## Stations are duck-typed nodes with possess(), unpossess(), can_possess(),
## wants_captured_mouse(), get_hud_info(), get_station_position(), station_name, station_kind
## and a became_unavailable signal. G jumps to the Gunner Squad (station_kind "squad").
##
## The HUD (DefenderHUD) after the paper sketch, minimal like the attacker's: the squads top left, the time to hold and the
## vents top centre, the tactical view of the base and the minimap top right, the ammo counter bottom left, the skills of
## what the player drives bottom centre. The roster of bought squads (DefenderArmory): F1-F6 takes command of a squad, Ctrl+F1-F6 changes its auto order without leaving the post
## the player is on, B buys another AA Squad, N a Flame Squad, M an Infiltrator Squad, K a Sniper, J the Fighter
## Jet (DefenderJet) and H the Hover Tank (DefenderTank): machines (DefenderMachine) ride on the same roster.
##
## A kangaroo's flash grenade going off where the post the player is on sees it (FlashGrenade) turns
## the screen full white for as long as it blinds, then it clears.
##
## The garrison (Garrison): the player has one of the base's four spawn controls (player 0's, on the south side at the
## start). Y moves it to the next side round the base (south, east, north, west), U switches the soldiers it spawns
## between BASE (guns, then the decks, then the field) and FIELD (straight out). The HUD's tactical view shows it.

const THREAT_RADIUS := 45.0
const SWITCH_FADE := 0.18
## Eyes over a post's spot (m), and how long the white takes to clear once the blindness wears off.
const EYE_HEIGHT := 1.65
const FLASH_FADE := 0.8
const ROSTER_KEYS := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6]
const BUY_KEY := KEY_B
const BUY_FLAME_KEY := KEY_N
const BUY_INFILTRATOR_KEY := KEY_M
const BUY_SNIPER_KEY := KEY_K
## C calls a drone swarm to the post the player is on (DroneBay.call_swarm).
const CALL_DRONES_KEY := KEY_C
const BUY_JET_KEY := KEY_J
const BUY_TANK_KEY := KEY_H
## The garrison's spawn control: Y the next side, U BASE / FIELD.
const SPAWN_SIDE_KEY := KEY_Y
const SPAWN_PRIORITY_KEY := KEY_U

var level: LevelBuilder
## The defenders' credits and bought squads; null: no roster.
var armory: DefenderArmory
## The defenders' drone swarms; null: none in this match.
var drones: DroneBay
## The garrison and which of its spawn controls is the player's; null: none in this match.
var garrison: Garrison
var player_number := 0
var stations := []
var current = null
## The match's HUD (null in the showcases): its status bar gives way to this one's banner. The attackers' army, for the
## minimap.
var match_ui: MatchUI
var commander: AttackerCommander
var hud: DefenderHUD

var _overview_cam: Camera3D
var _fade: ColorRect
var _crosshair: Control
var _prompt: Label
var _threat := {}
var _switching := false
var _whiteout: ColorRect
var _whiteout_tw: Tween


func _ready() -> void:
	layer = 2
	add_to_group("flash_watchers")
	stations = level.stations
	for s in stations:
		s.became_unavailable.connect(_on_station_unavailable)

	_overview_cam = Camera3D.new()
	_overview_cam.far = 900.0
	level.add_child(_overview_cam)
	_overview_cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40.0), 0, 0)), Vector3(0, 150, 230))

	_build_hud()
	if match_ui:
		match_ui.attach_defender_hud(hud.alerts_top())
	if armory:
		armory.squad_bought.connect(_on_squad_bought)
		for s in armory.squads:
			_on_squad_bought(s)
	select_station(0, true)


# ---------------------------------------------------------------- switching

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if drones and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == CALL_DRONES_KEY:
		call_drones()
		return
	if garrison and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == SPAWN_SIDE_KEY:
			cycle_spawn()
			return
		if event.physical_keycode == SPAWN_PRIORITY_KEY:
			toggle_spawn_priority()
			return
	if armory and event is InputEventKey and event.pressed and not event.echo:
		var k := ROSTER_KEYS.find(event.physical_keycode)
		if k >= 0:
			if event.ctrl_pressed:
				cycle_squad_order(k)
			else:
				select_squad(k)
			return
		if event.physical_keycode == BUY_KEY:
			buy_squad()
			return
		if event.physical_keycode == BUY_FLAME_KEY:
			buy_squad("flame")
			return
		if event.physical_keycode == BUY_INFILTRATOR_KEY:
			buy_squad("infiltrator")
			return
		if event.physical_keycode == BUY_SNIPER_KEY:
			buy_squad("sniper")
			return
		if event.physical_keycode == BUY_JET_KEY:
			buy_squad("jet")
			return
		if event.physical_keycode == BUY_TANK_KEY:
			buy_squad("tank")
			return
	for i in mini(stations.size(), 10):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select_station(i)
			return
	if event.is_action_pressed("station_next"):
		select_most_threatened()
	elif event.is_action_pressed("squad"):
		select_station(stations.find_custom(func(s): return s.station_kind == "squad"))
	elif event is InputEventMouseButton and event.pressed and current != null \
			and current.wants_captured_mouse() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func select_station(i: int, instant := false) -> void:
	if i < 0 or i >= stations.size():
		return
	_switch_to(stations[i], instant)


## Takes command of the k-th squad on the roster.
func select_squad(k: int, instant := false) -> void:
	if armory == null or k < 0 or k >= armory.squads.size():
		return
	_switch_to(armory.squads[k], instant)


## Ctrl+F<n>: the k-th squad's next auto order (MINES / GUARD, CLEAR / GUARD, HOLD / OP <helipad>),
## wherever the player is.
func cycle_squad_order(k: int) -> void:
	if armory == null or k < 0 or k >= armory.squads.size():
		return
	var s = armory.squads[k]
	s.cycle_order()
	_flash_prompt("%s: %s" % [s.station_name, s.order_name()])


## B: buys an AA Squad (N: a Flame Squad, `kind` "flame"; M: an Infiltrator Squad, "infiltrator"; K: a
## Sniper, "sniper"; J: the Fighter Jet, "jet"; H: the Hover Tank, "tank") if there are the credits and room on the roster.
func buy_squad(kind := "aa"):
	if armory == null:
		return null
	if armory.squads.size() >= DefenderArmory.MAX_SQUADS:
		_flash_prompt("The roster is full")
		return null
	if not armory.can_buy(kind):
		_flash_prompt("Not enough credits (%d of %d)" % [int(armory.credits), DefenderArmory.COSTS[kind]])
		return null
	var s = armory.buy(kind)
	_flash_prompt("%s deployed · F%d to take command" % [s.station_name, armory.squads.find(s) + 1])
	return s


func _on_squad_bought(s) -> void:
	s.became_unavailable.connect(_on_station_unavailable)


## The tactical view's click on a side: the player's garrison spawn goes there.
func move_spawn_to(side: String) -> void:
	if garrison == null:
		return
	garrison.move_spawn(player_number, side)
	_flash_prompt("Your spawn: %s · %s now spawns %d at a time" % [side.to_upper(), side.capitalize(), garrison.spawns_at(side)])


## The minimap's click: the post (or bought squad) nearest `pos` that can be taken.
func select_nearest_post(pos: Vector3) -> void:
	var all: Array = stations.duplicate()
	if armory:
		all.append_array(armory.squads)
	var best = null
	var best_d := INF
	for s in all:
		if not s.can_possess():
			continue
		var d: float = Vector2(s.get_station_position().x - pos.x, s.get_station_position().z - pos.z).length()
		if d < best_d:
			best_d = d
			best = s
	if best != null:
		_switch_to(best)


## Y: the player's garrison spawn to the next side round the base.
func cycle_spawn() -> void:
	if garrison == null:
		return
	var side := garrison.cycle_spawn(player_number)
	_flash_prompt("Your spawn: %s · %s now spawns %d at a time" % [side.to_upper(), side.capitalize(), garrison.spawns_at(side)])


## U: the player's garrison spawn between BASE (guns, decks, then the field) and FIELD (straight out to the field).
func toggle_spawn_priority() -> void:
	if garrison == null:
		return
	var p := garrison.toggle_priority(player_number)
	_flash_prompt("Your soldiers: %s" % ("BASE · guns, then the decks, then the field" if p == Garrison.Priority.BASE
			else "FIELD · straight out to the field"))


## C: calls a drone swarm to where the player's post stands. Refused if no swarm can get there on the fuel it has
## (too far out), if one is already on the spot or on its way, or every swarm is recharging or about to make a kill.
func call_drones() -> Dictionary:
	if drones == null or current == null:
		return {"ok": false, "reason": "no post"}
	var r := drones.call_swarm(current.get_station_position(), current)
	if r.ok:
		_flash_prompt("Drone swarm %d on its way" % (r.swarm as DroneSwarm).number)
	else:
		_flash_prompt("No drones: %s" % r.reason)
	return r


func _switch_to(s, instant := false) -> void:
	if _switching:
		return
	if s == current:
		return
	if not s.can_possess():
		_flash_prompt("%s is down" % s.station_name)
		return
	if instant:
		_possess(s)
		return
	_switching = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, SWITCH_FADE)
	tw.tween_callback(_possess.bind(s))
	tw.tween_property(_fade, "color:a", 0.0, SWITCH_FADE)
	tw.tween_callback(func(): _switching = false)


## Tab: jump to the available station with the most attackers nearby (skipping the
## current one), so the player can react to wherever the pressure is.
func select_most_threatened() -> void:
	_refresh_threat()
	var best := -1
	var best_score := -1
	var start := stations.find(current)
	for k in stations.size():
		var i := (start + 1 + k) % stations.size()
		var s = stations[i]
		if s == current or not s.can_possess():
			continue
		var score: int = _threat.get(s, 0)
		if score > best_score:
			best_score = score
			best = i
	if best >= 0:
		select_station(best)


func restore_mouse() -> void:
	if current != null and current.wants_captured_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _possess(s) -> void:
	if current != null:
		current.unpossess()
	current = s
	s.possess()
	restore_mouse()
	_prompt.visible = false
	_crosshair.visible = s.wants_captured_mouse()
	hud.on_switched()


func _on_station_unavailable(s) -> void:
	if s != current:
		return
	current.unpossess()
	current = null
	_overview_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_crosshair.visible = false
	var what: String = s.down_message() if s.has_method("down_message") else "%s is down!" % s.station_name
	_prompt.text = "%s.  Pick another post (1-%d) or press Tab" % [what, mini(stations.size(), 10)]
	_prompt.visible = true


## A flash grenade went off at `at` (FlashGrenade): if the post the player is on has it in sight within
## `radius`, the player is blinded: the screen goes white for `seconds`.
func on_flash(at: Vector3, radius: float, seconds: float) -> void:
	if current == null:
		return
	if FlashGrenade.sees(level, at, current.get_station_position() + Vector3.UP * EYE_HEIGHT, radius):
		flash_screen(seconds)


## Full white for `seconds` (a flash on top of a flash starts it over), then it clears.
func flash_screen(seconds: float) -> void:
	if _whiteout_tw:
		_whiteout_tw.kill()
	_whiteout.color.a = 1.0
	_whiteout_tw = create_tween()
	_whiteout_tw.tween_interval(seconds)
	_whiteout_tw.tween_property(_whiteout, "color:a", 0.0, FLASH_FADE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## How white the screen is (1: blinded by a flash).
func whiteout() -> float:
	return _whiteout.color.a


func _flash_prompt(text: String) -> void:
	if current == null:
		return
	_prompt.text = text
	_prompt.visible = true
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func(): _prompt.visible = current == null)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var root := UIKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = Control.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)
	for r in [Rect2(-12, -1, 8, 2), Rect2(4, -1, 8, 2), Rect2(-1, -12, 2, 8), Rect2(-1, 4, 2, 8), Rect2(-1, -1, 2, 2)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.85)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.add_child(c)

	# Everything else (the squads, the banner, the base and the map, the ammo counter, the skills) is the HUD's.
	hud = DefenderHUD.new()
	hud.controller = self
	root.add_child(hud)

	_prompt = UIKit.label("", 26, UIKit.WARN)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 60
	_prompt.visible = false
	root.add_child(_prompt)

	_fade = UIKit.full_rect(ColorRect.new()) as ColorRect
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	# A flash grenade's white, over every HUD (the squad panel's layer too), under the pause menu.
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 4
	add_child(flash_layer)
	_whiteout = UIKit.full_rect(ColorRect.new()) as ColorRect
	_whiteout.color = Color(1, 1, 1, 0)
	_whiteout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(_whiteout)


func _refresh_threat() -> void:
	_threat.clear()
	var units := get_tree().get_nodes_in_group("attacker_units")
	for s in stations:
		var n := 0
		var p: Vector3 = s.get_station_position()
		for u in units:
			if u.global_position.distance_squared_to(p) < THREAT_RADIUS * THREAT_RADIUS:
				n += 1
		_threat[s] = n


func _process(_delta: float) -> void:
	if current != null:
		# A scope up draws its own reticle.
		var info: Dictionary = current.get_hud_info()
		_crosshair.visible = current.wants_captured_mouse() and info.get("crosshair", true)
