class_name AttackerController
extends CanvasLayer
## Human RTS commander: camera, selection, orders, spawning and the RTS HUD.
## Turns mouse/keyboard input into commands for the AttackerCommander.
##
## LMB click/drag: select · Shift adds · RMB: attack-move / attack target
## Ctrl+RMB: move without stopping to fight · Ctrl+1-9 assign group · 1-9 recall (twice quickly: the camera goes to it)
## Backspace: select the base (the army's one base, the Mobile Command Citadel; the Forward Helipads are outposts:
##    AttackerBase) and look at it. With the base selected the HUD's card shows the units to build, and
## Z X C V B N M H J K L Y U I put one on the production line (AttackerCommander "produce": paid for now, built one at a
##    time, out at the base); PRODUCE_ANYWHERE lets them work without the base selected
## F1: the keys (HELP)
## The HUD (AttackerHUD): small islands, each on screen only while it has something to show: credits and vents top centre,
## the production line top left, the minimap top right (LMB looks, RMB orders), the command card bottom left (the selected
## units' skills, a tile each: use_skill; or the base's production) and the groups and warnings bottom right.
## F: aim the selected rhinos' cluster bombing (LMB fire, RMB/F cancel) · T: scout formation
##    with no rhino ready, the selected talons' strafe run: press LMB on the middle of the line,
##    drag the way to fly it, let go to fire (a click flies it from the talons; RMB/F cancel)
## G: aim the selected bisons' bombardment (LMB fire, RMB/G cancel), and the Mule Artillery's with their
##    guns set up; with no bison or mule ready, the selected talons' bomb strike (LMB fire, RMB/G cancel)
## R: aim a selected hippo's smoke screen (LMB fire, RMB/R cancel)
##    with no hippo ready, the selected kangaroos' flash grenades (LMB fire, RMB/R cancel)
## O: aim the selected elephants' missiles: LMB an enemy aircraft (RMB/O cancel)
## Space: the selected breaching rams ram (then RMB a gate to charge it)
## P: the selected giraffes ping
## F with no rhino or talon skill ready: the selected lionesses sneak (then RMB a defender: they pounce)
## G with no bison or talon skill ready: the selected lionesses' fire blast
## T with no rhino selected: lionesses moved together form firing lines, or don't (the HUD's toggle too)
## T with no rhino or lioness selected: the selected Wolf Medics switch between healing and minesweeping
##    (the HUD's button too)
## T with no rhino, lioness or dog selected: the selected Mule Artillery set their guns up, or pack them up
##    (the HUD's button too)
## F with no rhino, talon or lioness skill ready: the selected Serpent Snipers' sniper nest, LMB a tree (they
##    climb it and the trees round it; RMB/F cancel)
## G with no bison, talon or lioness skill ready: the selected Serpent Snipers' bush trap, LMB a bush (they coil
##    round it and the bushes round it; RMB/G cancel)
## Shift+B (or the HUD's BRIDGE button): drop a folding bridge across a river (the Jungle Keep): a cyan see-through
##    preview of it follows the cursor, snapped across the river nearest it (red where it can't go, and why); LMB
##    drops it (it comes down out of the sky and unfolds), RMB/Shift+B cancel. 30 a match (AttackerCommander).
## RMB a hippo or an elephant with riders selected: they climb onto the raft it tows (two to a raft, or a rhino
##    or a giraffe alone); sent across the water the riders get onto the rafts of the carriers moved with them by themselves. Space with no ram selected: the selected
##    carriers let their riders off.
## A defender on a bridge sets off its alarm: the banner at the top (click it to look) for as long as one is on it.
## The transport helicopters (HeloPanel, top right): RMB a helicopter with units selected sends the ones that can board to its
## ramp (as many as fit: HeloCargo); LMB a helicopter selects it, then RMB a helipad you hold sends it there with what it carries
## (its panel's buttons do the same). Units aboard can't be selected or ordered until it unloads them.
## The fog of war (AttackerVision) dims the land the army doesn't see (FogOverlay); defenders in it
## can't be ordered at.

const DRAG_THRESHOLD := 6.0
const CLUSTER_KEY := KEY_F
const SCOUT_KEY := KEY_T
const SMOKE_KEY := KEY_R
const BOMBARD_KEY := KEY_G
const MISSILE_KEY := KEY_O
const RAM_KEY := KEY_SPACE
const PING_KEY := KEY_P
## With Shift: the bridge.
const BRIDGE_KEY := KEY_B
const BRIDGE_OK := Color(0.25, 0.95, 1.0)
const SMOKE_FILL := Color(0.2, 0.9, 0.6, 0.35)
const SMOKE_LINE := Color(0.3, 1.0, 0.7)
const MISSILE_LINE := Color(1.0, 0.35, 0.3)
const HELP_KEY := KEY_F1
## Selects the base (select_base); the unit keys build there.
const BASE_KEY := KEY_BACKSPACE
## The unit keys build only with the base selected (Backspace) when false; any time when true.
const PRODUCE_ANYWHERE := false
## Unit groups (Ctrl+1-9), and how quickly a group's key pressed twice sends the camera to it (s).
const GROUPS := 9
const GROUP_DOUBLE_TAP := 0.35
## The same warning (not enough credits, the army full) no more often than this (s).
const WARN_REPEAT := 3.0
## The keys, on the F1 panel.
const HELP := "LMB select/drag · RMB attack-move / attack · Ctrl+RMB move · Ctrl+1-9 group, 1-9 select it (twice: look) · WASD/Q/E/wheel camera\nBackspace: select your base, the citadel · with it selected, a unit's key (or its tile) puts one on the production line, paid for now · click one on the line to take it off\nMinimap: LMB look there (drag to pan) · RMB send the selection there (Ctrl: move)\nSkills: the selected units' skills, a tile each (click to use that one); a key's badge is lit on the tile the key uses now · T switches modes\nRhinos: F cluster bombing (LMB fire, RMB cancel) · T scout formation · Hippos: R smoke screen (LMB fire, RMB cancel)\nBisons: G bombardment (LMB fire, RMB cancel), onto the gun decks and roofs too\nMule Artillery: T sets the gun up / disarms it (it can't move unless disarmed) · armed, G bombardment (LMB fire): further, harder and wider than the bisons'\nTalons: F strafe run (press LMB on the target, drag the way to fly, let go) · G bomb strike (LMB fire) · RMB cancels\nElephants: O missiles (LMB an enemy aircraft, RMB cancel) · Rams: Space ram, then RMB a gate to charge it\nGiraffes: see furthest through the fog · P ping: marks every defender it reaches, even under camo, and reveals infiltrators out of camo\nKangaroos: R flash grenade (LMB fire, RMB cancel) when no hippo's smoke is ready · they resupply units nearby\nLionesses: F sneak (then RMB a defender: they pounce) · G fire blast · T firing lines on/off when moved together\nSerpent Snipers: F sniper nest (LMB a tree: up it they see and shoot further; any move order climbs them down) · G bush trap (LMB a bush: coiled, they strike and crush a defender who comes close)\nWolf Medics: T healing (2 units each) / minesweeping (they find the hidden mines and dig them out; RMB sweeps on the way, Ctrl+RMB doesn't)\nChimps / Rams / Kangaroos: RMB next to a broken gate to send them in\nRivers: Shift+B drop a bridge (LMB, RMB cancel; 30 a match) · bears, snakes, hippos, elephants swim · the rest but mules and bisons ride the rafts hippos/elephants tow, 2 each or a rhino or giraffe alone (RMB one, or send them across with it; Space lets them off)\nBears: swimming, F dives under the water for 10 s, out of the defenders' sight (rounds that go in where it is still hit it)\nOutposts (the helipads): held, they see round themselves and the transport helicopters land there · sabotaged, stand ground units by one to retake it\nTransport helos (under the minimap): RMB one with units selected to board them (50 spaces; elephant/giraffe 5, rhino/hippo 2, bison 10, mule 15, rest 1) · LMB one, then RMB a helipad you hold to fly there · they land on the pad, put a unit down beside it every 0.25 s and fly home (helipad lost on the way: they bring them back)\nF1 closes this"

var level: LevelBuilder
var commander: AttackerCommander
var camera_rig: RTSCamera
## The match's HUD (null in the showcases): its status bar gives way to this one's, its alerts come to the warnings panel.
var match_ui: MatchUI
var hud: AttackerHUD
var selected: Array = []
var groups := {}
## The base is selected: the HUD's card shows its production, the unit keys build there.
var base_selected := false

var _drag_start := Vector2.ZERO
var _mouse_down := false
var _dragging := false
var _select_rect: Panel
var _selection_label: Label
## The group key pressed last and when (Time msec), for the double tap.
var _last_group := -1
var _last_group_at := 0
## Warning key -> when it was last given (Time msec).
var _warned := {}
var _marker: MeshInstance3D
## Ability aim mode: "" (off), "cluster" (rhinos), "bombard" (bisons), "smoke" (hippos),
## "missile" (elephants), "strafe" or "bomb" (talons), "flash" (kangaroos), "nest" or "trap" (Serpent Snipers).
## Cluster: preview of every rhino's aim zone and where its bombs will land.
## Bombard: every ready bison's range and where its shell will land (its blast).
## Flash: every ready kangaroo's throw and where its grenade will go off (the flash's reach).
## Smoke: the firing hippo's aim cone, with the band where the curtain will stand.
## Missile: each ready elephant's missile range, the aircraft under the cursor and lines from
## the elephants that would fire at it.
## Strafe: every ready talon's circle and the lane it will strafe, with an arrow the way it flies.
## Bomb: every ready talon's circle and where its bomb will land (its blast).
## Nest: the tree under the cursor and the ones round it the snakes will take (a ring round each trunk, a line
## from each snake), and how far the first will see and shoot from up there.
## Trap: the bush under the cursor and the ones round it, each with the reach of its trap.
var _aiming := ""
## Strafe: where LMB went down (the middle of the line), INF before it does.
var _strafe_at := Vector3.INF
var _aim_preview: MeshInstance3D
var _aim_mesh: ImmediateMesh
var _smoke_preview: MeshInstance3D
var _smoke_mesh: ImmediateMesh
var _missile_preview: MeshInstance3D
var _missile_mesh: ImmediateMesh
var _aim_label: Label
var _fog: FogOverlay
## The bridge's preview (cyan where it can go, red where it can't), the plan under the cursor, the HUD's button,
## and the alarm banner (the bridges with defenders on them).
var _bridge_ghost := {}
var _bridge_ok_mat: StandardMaterial3D
var _bridge_bad_mat: StandardMaterial3D
var _bridge_plan := {}
var _alarm_banner: Button
var _alarms: Array = []
var _alarm_beep: AudioStreamPlayer
## The transport helicopter selected in the world (null: none) and the panel of them.
var selected_helo: TransportHelo = null
var helo_panel: HeloPanel


func _ready() -> void:
	layer = 2
	camera_rig = RTSCamera.new()
	camera_rig.bounds = LevelBuilder.map_half
	if LevelBuilder.jungle:
		camera_rig.max_zoom = 320.0
	level.add_child(camera_rig)
	if LevelBuilder.jungle:
		camera_rig.camera.far = 2400.0
	camera_rig.camera.current = true
	camera_rig.focus(level.camera_home())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	commander.unit_died.connect(func(u): selected.erase(u))
	if commander.fleet != null:
		commander.fleet.helo_lost.connect(_on_helo_lost)
	_build_marker()
	_build_aim_preview()
	_build_smoke_preview()
	_build_missile_preview()
	_build_bridge_preview()
	_build_hud()
	if match_ui:
		match_ui.attach_attacker_hud(hud.warn)
	commander.bridge_alarm.connect(_on_bridge_alarm)
	if AttackerVision.instance:
		_fog = FogOverlay.new()
		_fog.vision = AttackerVision.instance
		camera_rig.camera.add_child(_fog)


func restore_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _aiming == "strafe" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Press on the middle of the line, drag the way to fly it, let go to fire.
		if event.pressed:
			var hit := _ray(event.position, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
			_strafe_at = hit.position if not hit.is_empty() else Vector3.INF
		elif _strafe_at != Vector3.INF:
			_fire_strafe(event.position)
			_set_aiming("")
		return
	if _aiming != "" and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			match _aiming:
				"cluster":
					_fire_cluster(event.position)
				"bombard":
					_fire_bombard(event.position)
				"bomb":
					_fire_bomb(event.position)
				"smoke":
					_fire_smoke(event.position)
				"flash":
					_fire_flash(event.position)
				"nest":
					if not _fire_nest(event.position):
						return  # no tree there: still aiming
				"trap":
					if not _fire_trap(event.position):
						return  # no bush there: still aiming
				"missile":
					# Elephants that didn't fire stay ready for the next target: keep aiming.
					if _fire_missiles(event.position) and not _ready_elephants().is_empty():
						return
				"bridge":
					if not drop_bridge(event.position):
						return  # it can't go there: still placing
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_set_aiming("")
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_drag_start = event.position
			elif _mouse_down:
				_release_select(event.position, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_order(event.position, event.ctrl_pressed)
	elif event is InputEventMouseMotion and _mouse_down:
		_drag_to(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == HELP_KEY:
			hud.help_panel.visible = not hud.help_panel.visible
			return
		if event.physical_keycode == BASE_KEY:
			select_base()
			return
		if event.physical_keycode == BRIDGE_KEY and event.shift_pressed:
			toggle_bridge()
			return
		if event.physical_keycode in [CLUSTER_KEY, BOMBARD_KEY, SMOKE_KEY, MISSILE_KEY, RAM_KEY, PING_KEY, SCOUT_KEY]:
			skill_key(event.physical_keycode)
			return
		for type_id in UnitTypes.ORDER:
			if event.physical_keycode == UnitTypes.DATA[type_id].hotkey:
				if base_selected or PRODUCE_ANYWHERE:
					spawn(type_id)
				else:
					warn_once("base", "Backspace: select the base to build units", UIKit.ACCENT)
				return
		for i in GROUPS:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				if event.ctrl_pressed:
					assign_group(i)
				else:
					var again := _last_group == i and Time.get_ticks_msec() - _last_group_at < GROUP_DOUBLE_TAP * 1000.0
					recall_group(i, event.shift_pressed)
					if again:
						focus_group(i)
					_last_group = i
					_last_group_at = Time.get_ticks_msec()
				return


## Real mouse input, before the HUD takes it: a box dragged out of the world and let go (or moved) over the HUD still
## selects (the panels would swallow the release, and the box would stay up).
func _input(event: InputEvent) -> void:
	if not _mouse_down or get_tree().paused:
		return
	if event is InputEventMouseMotion:
		_drag_to(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_release_select(event.position, event.shift_pressed)
		get_viewport().set_input_as_handled()


func _drag_to(pos: Vector2) -> void:
	if not _dragging and pos.distance_to(_drag_start) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		var r := Rect2(_drag_start, Vector2.ZERO).expand(pos)
		_select_rect.position = r.position
		_select_rect.size = r.size
		_select_rect.visible = true


func _release_select(pos: Vector2, add: bool) -> void:
	_mouse_down = false
	if _dragging:
		_box_select(Rect2(_drag_start, Vector2.ZERO).expand(pos), add)
	else:
		_click_select(pos, add)
	_dragging = false
	_select_rect.visible = false


## What a skill key does for the selection (the keyboard, and the HUD's skill tiles and switches): each key tries its
## units' skills in turn, the first that has one ready going (AttackerHUD.SKILLS lists them in the same order).
func skill_key(key: int) -> void:
	match key:
		CLUSTER_KEY:
			if _aiming in ["cluster", "strafe", "nest"]:
				_set_aiming("")
			elif not _ready_rhinos().is_empty():
				_set_aiming("cluster")
			elif not _ready_talons("strafe").is_empty():
				_set_aiming("strafe")
			elif not _ready_lionesses("sneak").is_empty():
				commander.submit({"type": "sneak", "units": _ready_lionesses("sneak").map(func(u): return u.unit_id)})
			elif not _serpents("nest").is_empty():
				_set_aiming("nest")
			elif not _ready_divers().is_empty():
				dive()
		BOMBARD_KEY:
			if _aiming in ["bombard", "bomb", "trap"]:
				_set_aiming("")
			elif not _ready_bisons().is_empty():
				_set_aiming("bombard")
			elif not _ready_talons("bomb").is_empty():
				_set_aiming("bomb")
			elif not _ready_lionesses("blast").is_empty():
				commander.submit({"type": "blast", "units": _ready_lionesses("blast").map(func(u): return u.unit_id)})
			elif not _serpents("trap").is_empty():
				_set_aiming("trap")
		SMOKE_KEY:
			# A ready hippo's smoke screen comes first, then the kangaroos' flash grenades.
			if _aiming in ["smoke", "flash"]:
				_set_aiming("")
			elif not _ready_hippos().is_empty():
				_set_aiming("smoke")
			else:
				_set_aiming("flash" if not _ready_kangaroos().is_empty() else "")
		MISSILE_KEY:
			_set_aiming("missile" if _aiming != "missile" and not _ready_elephants().is_empty() else "")
		RAM_KEY:
			# Rams ready ram; else the carriers let their riders off.
			_alive_selection()
			if selected.any(func(u): return u.ram_ready()):
				commander.submit({"type": "ram", "units": selected.map(func(u): return u.unit_id)})
			else:
				commander.submit({"type": "unload", "units": selected.map(func(u): return u.unit_id)})
		PING_KEY:
			_alive_selection()
			commander.submit({"type": "ping", "units": selected.map(func(u): return u.unit_id)})
		SCOUT_KEY:
			_alive_selection()
			if selected.any(func(u): return u.stats.get("line", false)) and not selected.any(func(u): return u.stats.get("scouts", false)):
				toggle_lines()
			elif not _dogs().is_empty() and not selected.any(func(u): return u.stats.get("scouts", false)):
				toggle_dog_mode()
			elif not _mules().is_empty() and not selected.any(func(u): return u.stats.get("scouts", false)):
				toggle_guns()
			else:
				toggle_scout()


## The ability aim mode on now ("" off): the HUD lights the tile being aimed.
func aiming() -> String:
	return _aiming


## T with rhinos selected (or the HUD's switch): the selected rhinos ring the rest of the selection, or stop.
func toggle_scout() -> void:
	_alive_selection()
	commander.submit({"type": "scout", "units": selected.map(func(u): return u.unit_id)})


## A skill tile on the HUD: that skill for the selected units that have it (not the key's first choice: the one clicked).
func use_skill(id: String) -> void:
	_alive_selection()
	var ids := func(list: Array) -> Array: return list.map(func(u): return u.unit_id)
	match id:
		"cluster":
			_toggle_aim(id, _ready_rhinos())
		"strafe":
			_toggle_aim(id, _ready_talons("strafe"))
		"bomb":
			_toggle_aim(id, _ready_talons("bomb"))
		"bombard":
			_toggle_aim(id, _ready_bisons())
		"smoke":
			_toggle_aim(id, _ready_hippos())
		"flash":
			_toggle_aim(id, _ready_kangaroos())
		"missile":
			_toggle_aim(id, _ready_elephants())
		"nest":
			_toggle_aim(id, _serpents("nest"))
		"trap":
			_toggle_aim(id, _serpents("trap"))
		"sneak":
			commander.submit({"type": "sneak", "units": ids.call(_ready_lionesses("sneak"))})
		"blast":
			commander.submit({"type": "blast", "units": ids.call(_ready_lionesses("blast"))})
		"dive":
			dive()
		"ping":
			commander.submit({"type": "ping", "units": ids.call(selected)})
		"ram":
			commander.submit({"type": "ram", "units": ids.call(selected)})
		"unload":
			commander.submit({"type": "unload", "units": ids.call(selected)})
		"lines":
			toggle_lines()
		"dogs":
			toggle_dog_mode()
		"guns":
			toggle_guns()
		"scout":
			toggle_scout()


## Aims `mode` with `ready` units to fire it, or stops aiming it.
func _toggle_aim(mode: String, ready: Array) -> void:
	_set_aiming("" if _aiming == mode or ready.is_empty() else mode)


## The state of a mode switch (T) for the selection: "lines" and "scout" ON/OFF, "dogs" HEALING/MINESWEEPING/MIXED, "guns"
## PACKED/SETTING UP/ARMED/DISARMING/MIXED. "" if the selection has none of those units.
func mode_state(id: String) -> String:
	_alive_selection()
	match id:
		"lines":
			return "ON" if commander.line_formation else "OFF"
		"scout":
			return "ON" if selected.any(func(u): return commander.is_scouting(u)) else "OFF"
		"dogs":
			var dogs := _dogs()
			if dogs.is_empty():
				return ""
			var sweeping := dogs.filter(func(u): return u.dog_mode == "sweep").size()
			return "MINESWEEPING" if sweeping == dogs.size() else "HEALING" if sweeping == 0 else "MIXED"
		"guns":
			var mules := _mules()
			if mules.is_empty():
				return ""
			for s in [["is_armed", "ARMED"], ["setting_up", "SETTING UP"], ["packing_up", "DISARMING"], ["is_packed", "PACKED"]]:
				if mules.all(func(u): return u.call(s[0])):
					return s[1]
			return "MIXED"
	return ""


# ---------------------------------------------------------------- the base

## Selects the base (the army's one: the Mobile Command Citadel): the units are deselected, the HUD's card shows its
## production and the unit keys build there. `look`: the camera goes to it.
func select_base(look := true) -> void:
	_set_selection([])
	_select_helo(null)
	base_selected = true
	if look:
		camera_rig.focus(commander.spawn_points[0])


# ---------------------------------------------------------------- groups

## Ctrl+1-9 (or Ctrl+click its tile): group `i` is the selection.
func assign_group(i: int) -> void:
	_alive_selection()
	groups[i] = selected.duplicate()


## 1-9 (or a click on its tile): selects group `i` (`add`: adds it to the selection).
func recall_group(i: int, add := false) -> void:
	var list: Array = groups.get(i, []).filter(func(u): return is_instance_valid(u) and u.is_controllable())
	if add:
		for u in selected:
			if is_instance_valid(u) and u.is_controllable() and not u in list:
				list.append(u)
	_select_helo(null)
	_set_selection(list)


## The camera goes to group `i` (its key twice, a double click on its tile).
func focus_group(i: int) -> void:
	focus_units(groups.get(i, []))


## The camera goes to the middle of `list`.
func focus_units(list: Array) -> void:
	var alive := list.filter(func(u): return is_instance_valid(u) and u.is_controllable())
	if alive.is_empty():
		return
	var at := Vector3.ZERO
	for u in alive:
		at += u.global_position
	camera_rig.focus(at / alive.size())


## Only the selected units of `type_id` stay selected (Ctrl+click on the mugshot).
func select_type(type_id: String) -> void:
	_alive_selection()
	_set_selection(selected.filter(func(u): return u.type_id == type_id))


## The minimap's RMB: the selection goes to `pos` (attack-move; `force_move`: plain move).
func order_at(pos: Vector3, force_move := false) -> void:
	_alive_selection()
	if selected.is_empty():
		return
	commander.submit({"type": "move", "units": selected.map(func(u): return u.unit_id), "pos": pos, "attack": not force_move})
	_ping(pos, UIKit.GOOD if force_move else UIKit.WARN)


func _ray(screen_pos: Vector2, mask: int) -> Dictionary:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return cam.get_world_3d().direct_space_state.intersect_ray(q)


func _click_select(pos: Vector2, add: bool) -> void:
	var hit := _ray(pos, GameConfig.LAYER_ATTACKERS)
	var u = Combat.find_damageable(hit.collider) if not hit.is_empty() else null
	var list := selected.duplicate() if add else []
	if u is AttackerUnit and u.is_controllable():
		if u in list:
			list.erase(u)
		else:
			list.append(u)
	_set_selection(list)
	_select_helo(u if u is TransportHelo and u.is_alive() else null)


func _box_select(rect: Rect2, add: bool) -> void:
	_select_helo(null)
	var cam := camera_rig.camera
	var list := selected.duplicate() if add else []
	for u in commander.units.values():
		var p: Vector3 = u.global_position + Vector3.UP
		if cam.is_position_behind(p) or not u.is_controllable():
			continue
		if rect.has_point(cam.unproject_position(p)) and not u in list:
			list.append(u)
	_set_selection(list)


func _set_selection(list: Array) -> void:
	base_selected = false
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	selected = list
	for u in selected:
		u.selected = true


## Drops the dead, and raiders that have gone inside the stronghold.
func _alive_selection() -> void:
	selected = selected.filter(func(u): return is_instance_valid(u) and u.is_controllable())


# ---------------------------------------------------------------- transport helicopters

## Selects a transport helicopter (null: none): its ring and health bar show, its block in the panel is lit.
func _select_helo(h: TransportHelo) -> void:
	if is_instance_valid(selected_helo):
		selected_helo.selected = false
	selected_helo = h
	if h != null:
		h.selected = true
		base_selected = false
	if helo_panel:
		helo_panel.selected_slot = h.slot if h != null else -1


## A helicopter was shot down: no longer selected.
func _on_helo_lost(h: TransportHelo) -> void:
	if h == selected_helo:
		_select_helo(null)


## The panel's Board button: the selected units that can go aboard walk to helicopter `i`'s ramp.
func _on_helo_board(i: int) -> void:
	_alive_selection()
	var boarders := selected.filter(func(u): return u.can_board_helo())
	if boarders.is_empty():
		return
	if commander.submit({"type": "helo_board", "units": boarders.map(func(u): return u.unit_id), "helo": i}) > 0:
		var h := commander.fleet.helo_at(i)
		if h:
			_ping(h.ramp_point(), UIKit.GOOD)


## The panel's Fly button: helicopter `i` takes what it has aboard to the helipad at spawn point `k`.
func _on_helo_fly(i: int, k: int) -> void:
	commander.submit({"type": "helo_fly", "helo": i, "spawn": k})


## A helicopter's name on the panel: it is selected, and the camera goes to it.
func _on_helo_pick(i: int) -> void:
	var h := commander.fleet.helo_at(i)
	if h == null or not h.is_alive():
		return
	_set_selection([])
	_select_helo(h)
	camera_rig.focus(h.global_position)


## The panel's Look button: the camera goes to helicopter `i`.
func _on_helo_look(i: int) -> void:
	var h := commander.fleet.helo_at(i)
	if h:
		camera_rig.focus(h.global_position)


## RMB with a transport helicopter selected: on a helipad the attackers hold, it flies there with what it has aboard. True
## if the click was on a helipad (the order was given, or refused).
func _order_helo(screen_pos: Vector2) -> bool:
	if not is_instance_valid(selected_helo) or not selected_helo.is_alive():
		return false
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return false
	var n := hit.collider as Node
	while n != null and not (n is AttackerBase):
		n = n.get_parent()
	if n == null:
		return false
	var sent := commander.submit({"type": "helo_fly", "helo": selected_helo.slot, "spawn": commander.spawn_bases.find(n)}) > 0
	_ping(n.global_position, UIKit.GOOD if sent else UIKit.DANGER)
	return true


func _issue_order(pos: Vector2, force_move: bool) -> void:
	_alive_selection()
	if selected_helo != null and _order_helo(pos):
		return
	if selected.is_empty():
		return
	var ids := selected.map(func(u): return u.unit_id)
	var hit := _ray(pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS)
	if hit.is_empty():
		return
	var target = Combat.find_damageable(hit.collider)
	if target == null:
		# A friendly unit (on its own layer): a carrier the riders in the selection board.
		var own := _ray(pos, GameConfig.LAYER_ATTACKERS)
		target = Combat.find_damageable(own.collider) if not own.is_empty() else null
		# A transport helicopter: the units that can go aboard walk to its ramp (as many as it has room for).
		if target is TransportHelo:
			var boarders := selected.filter(func(u): return u.can_board_helo())
			if not boarders.is_empty() and target.can_board():
				commander.submit({"type": "helo_board", "units": boarders.map(func(u): return u.unit_id), "helo": target.slot})
				_ping(target.ramp_point(), UIKit.GOOD)
				return
			target = null
		if target is AttackerUnit and target.can_carry() and selected.any(func(u): return u != target and u.can_ride()):
			var riders := selected.filter(func(u): return u != target and u.can_ride())
			commander.submit({"type": "board", "units": riders.map(func(u): return u.unit_id), "carrier": target.get_path()})
			var rest := selected.filter(func(u): return u != target and not u.can_ride())
			if not rest.is_empty():
				commander.submit({"type": "move", "units": rest.map(func(u): return u.unit_id), "pos": target.global_position, "attack": not force_move})
			_ping(target.global_position, BRIDGE_OK)
			return
		target = Combat.find_damageable(hit.collider)
	if target and not AttackerVision.sees_node(target):
		target = null  # hidden in the fog of war: an attack-move there
	if target and target.team != GameConfig.TEAM_ATTACKER and target.is_alive() and not force_move:
		commander.submit({"type": "attack", "units": ids, "target": target.get_path()})
		_ping(target.global_position, UIKit.DANGER)
	else:
		commander.submit({"type": "move", "units": ids, "pos": hit.position, "attack": not force_move})
		_ping(hit.position, UIKit.GOOD if force_move else UIKit.WARN)


# ---------------------------------------------------------------- rhino cluster bombing

func _ready_rhinos() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.cluster_ready())


func _set_aiming(mode: String) -> void:
	_aiming = mode
	_strafe_at = Vector3.INF
	_aim_preview.visible = mode in ["cluster", "bombard", "strafe", "bomb", "flash", "nest", "trap"]
	_smoke_preview.visible = mode == "smoke"
	_missile_preview.visible = mode == "missile"
	_aim_label.visible = mode in ["missile", "nest", "trap", "bridge"]
	if _bridge_ghost.has("root"):
		_bridge_ghost.root.visible = mode == "bridge"


func _fire_cluster(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var rhinos := _ready_rhinos()
	if hit.is_empty() or rhinos.is_empty():
		return
	commander.submit({"type": "cluster", "units": rhinos.map(func(u): return u.unit_id), "pos": hit.position})
	_ping(hit.position, UIKit.DANGER)


func _build_aim_preview() -> void:
	_aim_mesh = ImmediateMesh.new()
	_aim_preview = MeshInstance3D.new()
	_aim_preview.mesh = _aim_mesh
	_aim_preview.material_override = Mats.unshaded(Color(1.0, 0.55, 0.2), true)
	_aim_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_preview.visible = false
	level.add_child(_aim_preview)


func _update_aim_preview() -> void:
	var rhinos := _ready_rhinos()
	if rhinos.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var hit := _ray(get_viewport().get_mouse_position(), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return
	var aims := RhinoAim.solve(rhinos, hit.position)
	var lift := Vector3.UP * 0.3
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in rhinos.size():
		var r: AttackerUnit = rhinos[i]
		RhinoAim.dashed_circle(_aim_mesh, r.global_position + lift, r.stats.cluster_range, 64)
		RhinoAim.dashed_circle(_aim_mesh, aims[i] + lift, r.stats.cluster_spread, 16)
		_aim_mesh.surface_add_vertex(r.global_position + lift)
		_aim_mesh.surface_add_vertex(aims[i] + lift)
	_aim_mesh.surface_end()


# ---------------------------------------------------------------- bison bombardment

func _ready_bisons() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.bombard_ready())


func _fire_bombard(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var bisons := _ready_bisons()
	if hit.is_empty() or bisons.is_empty():
		return
	commander.submit({"type": "bombard", "units": bisons.map(func(u): return u.unit_id), "pos": hit.position})
	_ping(hit.position, UIKit.DANGER)


func _update_bombard_preview() -> void:
	var bisons := _ready_bisons()
	if bisons.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var hit := _ray(get_viewport().get_mouse_position(), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return
	var aims := RhinoAim.bombard(bisons, hit.position)
	var lift := Vector3.UP * 0.3
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in bisons.size():
		var b: AttackerUnit = bisons[i]
		RhinoAim.dashed_circle(_aim_mesh, b.global_position + lift, b.stats.bombard_range, 96)
		RhinoAim.dashed_circle(_aim_mesh, aims[i] + lift, b.stats.bombard_splash, 20)
		_aim_mesh.surface_add_vertex(b.global_position + lift)
		_aim_mesh.surface_add_vertex(aims[i] + lift)
	_aim_mesh.surface_end()


# ---------------------------------------------------------------- talon strafe run and bomb strike

func _ready_talons(skill: String) -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.strafe_ready() if skill == "strafe" else u.bomb_ready())


## The strafe line being aimed: [middle, way to fly], or [] when the cursor is off the map.
func _strafe_line(talons: Array, screen_pos: Vector2) -> Array:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if _strafe_at == Vector3.INF:
		return [] if hit.is_empty() else [hit.position, TalonAim.default_dir(talons, hit.position)]
	var drag: Vector3 = (hit.position - _strafe_at) if not hit.is_empty() else Vector3.ZERO
	drag.y = 0.0
	return [_strafe_at, drag.normalized() if drag.length() > 2.0 else TalonAim.default_dir(talons, _strafe_at)]


func _fire_strafe(screen_pos: Vector2) -> void:
	var talons := _ready_talons("strafe")
	var line := _strafe_line(talons, screen_pos)
	if talons.is_empty() or line.is_empty():
		return
	commander.submit({"type": "strafe", "units": talons.map(func(u): return u.unit_id), "pos": line[0], "dir": line[1]})
	_ping(line[0], UIKit.DANGER)


func _update_strafe_preview() -> void:
	var talons := _ready_talons("strafe")
	if talons.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var line := _strafe_line(talons, get_viewport().get_mouse_position())
	if line.is_empty():
		return
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	TalonAim.draw_strafe(_aim_mesh, talons, TalonAim.strafe(talons, line[0], line[1]))
	_aim_mesh.surface_end()


func _fire_bomb(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var talons := _ready_talons("bomb")
	if hit.is_empty() or talons.is_empty():
		return
	commander.submit({"type": "bomb", "units": talons.map(func(u): return u.unit_id), "pos": hit.position})
	_ping(hit.position, UIKit.DANGER)


func _update_bomb_preview() -> void:
	var talons := _ready_talons("bomb")
	if talons.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var hit := _ray(get_viewport().get_mouse_position(), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	TalonAim.draw_bombs(_aim_mesh, talons, TalonAim.bombs(talons, hit.position))
	_aim_mesh.surface_end()


# ---------------------------------------------------------------- hippo smoke screen

func _ready_hippos() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.smoke_ready())


func _fire_smoke(screen_pos: Vector2) -> void:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hippos := _ready_hippos()
	if hit.is_empty() or hippos.is_empty():
		return
	commander.submit({"type": "smoke", "units": hippos.map(func(u): return u.unit_id), "pos": hit.position})
	_ping(hit.position, SMOKE_LINE)


func _build_smoke_preview() -> void:
	_smoke_mesh = ImmediateMesh.new()
	_smoke_preview = MeshInstance3D.new()
	_smoke_preview.mesh = _smoke_mesh
	_smoke_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke_preview.visible = false
	level.add_child(_smoke_preview)


func _update_smoke_preview() -> void:
	var hippos := _ready_hippos()
	if hippos.is_empty():
		_set_aiming("")
		return
	_smoke_mesh.clear_surfaces()
	var hit := _ray(get_viewport().get_mouse_position(), GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	if hit.is_empty():
		return
	var hippo := HippoSmoke.pick(hippos, hit.position)
	HippoSmoke.draw_preview(_smoke_mesh, hippo, HippoSmoke.solve(hippo, hit.position),
			Mats.unshaded(SMOKE_FILL, true), Mats.unshaded(SMOKE_LINE, true))


# ---------------------------------------------------------------- kangaroo flash grenades

func _ready_kangaroos() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.flash_ready())


## Where the cursor puts the flash grenades (null: off the map): on a defender under it, at its feet
## (up on the gun deck, not on the parapet in front of it); else the ground, deck or roof under it.
func _flash_target(screen_pos: Vector2):
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS)
	if hit.is_empty():
		return null
	var d = Combat.find_damageable(hit.collider)
	if d and d.team != GameConfig.TEAM_ATTACKER and not d.is_in_group("structures") and AttackerVision.sees_node(d):
		return d.global_position
	return hit.position


func _fire_flash(screen_pos: Vector2) -> void:
	var at = _flash_target(screen_pos)
	var kangaroos := _ready_kangaroos()
	if at == null or kangaroos.is_empty():
		return
	commander.submit({"type": "flash", "units": kangaroos.map(func(u): return u.unit_id), "pos": at})
	_ping(at, KangarooFlash.COLOR)


func _update_flash_preview() -> void:
	var kangaroos := _ready_kangaroos()
	if kangaroos.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var at = _flash_target(get_viewport().get_mouse_position())
	if at == null:
		return
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	KangarooFlash.draw(_aim_mesh, kangaroos, KangarooFlash.spots(kangaroos, at))
	_aim_mesh.surface_end()


# ---------------------------------------------------------------- lionesses

## The selected lionesses whose sneak (`skill` "sneak") or fire blast ("blast") is ready.
func _ready_lionesses(skill: String) -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.sneak_ready() if skill == "sneak" else u.blast_ready())


## The selected bears out swimming that can dive.
func _ready_divers() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.dive_ready())


## F (with none of the others' F skills ready: the others in the water can't use theirs) or the HUD's button: the
## selected bears out swimming dive under the water.
func dive() -> int:
	return commander.submit({"type": "dive", "units": _ready_divers().map(func(u): return u.unit_id)})


## T (with no rhino selected) or the HUD's toggle: lionesses moved together form up in firing lines, or
## don't.
func toggle_lines() -> void:
	commander.submit({"type": "line", "on": not commander.line_formation})


# ---------------------------------------------------------------- Serpent Snipers

## The selected Serpent Snipers that can be sent up a tree (`skill` "nest") or round a bush ("trap"): all but
## those squeezing their prey (nothing calls that off).
func _serpents(skill: String) -> Array:
	_alive_selection()
	return selected.filter(func(u): return (u.has_nest() if skill == "nest" else u.has_trap()) and not u.is_constricting() and not u.is_crossing())


func _tree_under(screen_pos: Vector2) -> ForestTree:
	var cam := camera_rig.camera
	return SerpentNest.tree_under(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _bush_under(screen_pos: Vector2, snakes: Array) -> Bush:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD)
	return SerpentTrap.bush_near(hit.position, snakes) if not hit.is_empty() else null


## LMB with the sniper nest aimed: the snakes go up the tree under the cursor and the ones round it. False if
## there is no tree there.
func _fire_nest(screen_pos: Vector2) -> bool:
	var tree := _tree_under(screen_pos)
	var snakes := _serpents("nest")
	if tree == null or snakes.is_empty():
		return false
	commander.submit({"type": "nest", "units": snakes.map(func(u): return u.unit_id), "pos": tree.trunk_centre()})
	_ping(tree.trunk_centre(), UIKit.GOOD)
	return true


## LMB with the bush trap aimed: the snakes coil round the bush under the cursor and the ones round it. False if
## there is no bush there.
func _fire_trap(screen_pos: Vector2) -> bool:
	var snakes := _serpents("trap")
	var bush := _bush_under(screen_pos, snakes)
	if bush == null or snakes.is_empty():
		return false
	commander.submit({"type": "trap", "units": snakes.map(func(u): return u.unit_id), "pos": bush.global_position})
	_ping(bush.global_position, UIKit.GOOD)
	return true


func _update_nest_preview() -> void:
	var snakes := _serpents("nest")
	if snakes.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var mouse := get_viewport().get_mouse_position()
	_aim_label.position = mouse + Vector2(22, 14)
	var tree := _tree_under(mouse)
	if tree == null:
		_aim_label.text = "Sniper nest: click a tree"
		return
	var picks := SerpentNest.assign(snakes, tree.trunk_centre())
	_aim_label.text = "Sniper nest: %d up %s" % [picks.size(), "this tree" if picks.size() == 1 else "these trees"]
	var lift := Vector3.UP * 0.3
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in picks.size():
		var u: AttackerUnit = picks[k][0]
		var t: ForestTree = picks[k][1]
		var foot := t.trunk_centre()
		foot.y = u.global_position.y
		RhinoAim.dashed_circle(_aim_mesh, foot + lift, t.trunk_radius(0.0) + 0.8, 16)
		_aim_mesh.surface_add_vertex(u.global_position + lift)
		_aim_mesh.surface_add_vertex(foot + lift)
		if k == 0:
			RhinoAim.dashed_circle(_aim_mesh, foot + lift, u.stats.range * u.stats.nest_range, 96)
	_aim_mesh.surface_end()


func _update_trap_preview() -> void:
	var snakes := _serpents("trap")
	if snakes.is_empty():
		_set_aiming("")
		return
	_aim_mesh.clear_surfaces()
	var mouse := get_viewport().get_mouse_position()
	_aim_label.position = mouse + Vector2(22, 14)
	var bush := _bush_under(mouse, snakes)
	if bush == null:
		_aim_label.text = "Bush trap: click a bush"
		return
	var picks := SerpentTrap.assign(snakes, bush.global_position)
	_aim_label.text = "Bush trap: %d round %s" % [picks.size(), "this bush" if picks.size() == 1 else "these bushes"]
	var lift := Vector3.UP * 0.3
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for pick in picks:
		var u: AttackerUnit = pick[0]
		var b: Bush = pick[1]
		var at := Vector3(b.global_position.x, u.global_position.y, b.global_position.z)
		RhinoAim.dashed_circle(_aim_mesh, at + lift, SerpentTrap.ring_radius(b), 12)
		RhinoAim.dashed_circle(_aim_mesh, at + lift, u.stats.trap_reach, 28)
		_aim_mesh.surface_add_vertex(u.global_position + lift)
		_aim_mesh.surface_add_vertex(at + lift)
	_aim_mesh.surface_end()


# ---------------------------------------------------------------- Wolf Medics

func _dogs() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.has_dog_modes())


## T (with no rhino or lioness selected) or the HUD's button: the selected dogs switch mode, all to
## minesweeping unless all of them sweep already (then all to healing).
func toggle_dog_mode() -> void:
	var dogs := _dogs()
	if dogs.is_empty():
		return
	var mode := "heal" if dogs.all(func(u): return u.dog_mode == "sweep") else "sweep"
	commander.submit({"type": "dog_mode", "units": dogs.map(func(u): return u.unit_id), "mode": mode})


# ---------------------------------------------------------------- Mule Artillery

func _mules() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.has_setup())


## T (with no rhino, lioness or dog selected) or the HUD's button: the selected Mule Artillery set their guns
## up, unless all of them are set up or setting up already: then they pack them up.
func toggle_guns() -> void:
	var mules := _mules()
	if mules.is_empty():
		return
	var up := not mules.all(func(u): return u.is_armed() or u.setting_up())
	commander.submit({"type": "setup", "units": mules.map(func(u): return u.unit_id), "on": up})


# ---------------------------------------------------------------- elephant missiles

func _ready_elephants() -> Array:
	_alive_selection()
	return selected.filter(func(u): return u.missiles_ready())


## Fires at the enemy aircraft under the cursor. False if there is none, or none of the ready
## elephants would fire at it (out of range, or enough is already on its way).
func _fire_missiles(screen_pos: Vector2) -> bool:
	var target := ElephantMissiles.pick(camera_rig.camera, screen_pos, GameConfig.TEAM_ATTACKER)
	var elephants := _ready_elephants()
	if target == null or ElephantMissiles.allocate(elephants, target).is_empty():
		return false
	commander.submit({"type": "missile", "units": elephants.map(func(u): return u.unit_id), "target": target.get_path()})
	_ping(target.global_position, MISSILE_LINE)
	return true


func _build_missile_preview() -> void:
	_missile_mesh = ImmediateMesh.new()
	_missile_preview = MeshInstance3D.new()
	_missile_preview.mesh = _missile_mesh
	_missile_preview.material_override = Mats.unshaded(MISSILE_LINE, true)
	_missile_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_missile_preview.visible = false
	level.add_child(_missile_preview)


func _update_missile_preview() -> void:
	var elephants := _ready_elephants()
	if elephants.is_empty():
		_set_aiming("")
		return
	var mouse := get_viewport().get_mouse_position()
	var target := ElephantMissiles.pick(camera_rig.camera, mouse, GameConfig.TEAM_ATTACKER)
	var firing := ElephantMissiles.allocate(elephants, target) if target else []
	_missile_mesh.clear_surfaces()
	ElephantMissiles.draw_preview(_missile_mesh, elephants, target, firing)
	_aim_label.position = mouse + Vector2(22, 14)
	if target == null:
		_aim_label.text = "Missiles: click an enemy aircraft"
	elif not firing.is_empty():
		_aim_label.text = "%d of %d elephants fire" % [firing.size(), elephants.size()]
		if firing.reduce(func(sum, e): return sum + e.salvo_damage(), 0.0) < ElephantMissiles.still_needed(target):
			_aim_label.text += " (not enough to bring it down)"
	elif elephants.any(func(e): return e.in_missile_range(target)):
		_aim_label.text = "Already going down"
	else:
		_aim_label.text = "Out of range"


# ---------------------------------------------------------------- folding bridges

func _build_bridge_preview() -> void:
	if not RiverCrossing.active():
		return
	_bridge_ok_mat = FoldingBridge.ghost_material(true)
	_bridge_bad_mat = FoldingBridge.ghost_material(false)
	_bridge_ghost = FoldingBridge.build_model(FoldingBridge.REF_LENGTH, _bridge_ok_mat)
	_bridge_ghost.root.visible = false
	level.add_child(_bridge_ghost.root)


## Bridge placing on or off (Shift+B, the HUD's button).
func toggle_bridge() -> void:
	if _aiming == "bridge" or commander.bridges_left <= 0 or not RiverCrossing.active():
		_set_aiming("")
	else:
		_set_aiming("bridge")


## The bridge under the cursor at `screen_pos`: FoldingBridge.plan of the ground there.
func bridge_plan(screen_pos: Vector2) -> Dictionary:
	var hit := _ray(screen_pos, GameConfig.LAYER_WORLD)
	if hit.is_empty():
		return {"ok": false, "reason": "Point at a river"}
	return FoldingBridge.plan(hit.position)


## Drops a bridge where the preview at `screen_pos` shows it; false if it can't go there.
func drop_bridge(screen_pos: Vector2) -> bool:
	var plan := bridge_plan(screen_pos)
	if not plan.ok:
		return false
	var id := commander.submit({"type": "bridge", "pos": plan.xform.origin})
	if id == 0:
		return false
	_ping(plan.xform.origin, BRIDGE_OK)
	return true


## The cyan preview at the bridge the cursor points at (red, and why, where it can't go).
func _update_bridge_preview() -> void:
	if commander.bridges_left <= 0:
		_set_aiming("")
		return
	var mouse := get_viewport().get_mouse_position()
	_bridge_plan = bridge_plan(mouse)
	_aim_label.position = mouse + Vector2(22, 14)
	var ghost: Node3D = _bridge_ghost.root
	ghost.visible = _bridge_plan.has("xform")
	if ghost.visible:
		ghost.global_transform = _bridge_plan.xform
		FoldingBridge.layout(_bridge_ghost, _bridge_plan.length, 0.0)
		var mat := _bridge_ok_mat if _bridge_plan.ok else _bridge_bad_mat
		for mi: MeshInstance3D in _bridge_ghost.meshes:
			mi.material_override = mat
	if _bridge_plan.ok:
		_aim_label.text = "Bridge (%d m): LMB to drop it · %d left" % [roundi(_bridge_plan.length), commander.bridges_left]
		_aim_label.add_theme_color_override("font_color", BRIDGE_OK)
	else:
		_aim_label.text = "Bridge: %s" % _bridge_plan.reason
		_aim_label.add_theme_color_override("font_color", UIKit.DANGER)


func _on_bridge_alarm(bridge: FoldingBridge, on: bool) -> void:
	_alarms.erase(bridge)
	if on:
		_alarms.append(bridge)
		_ping(bridge.global_position, UIKit.DANGER)
		warn_once("bridge_%d" % bridge.bridge_id, "Defenders crossing bridge %d!" % bridge.bridge_id, UIKit.DANGER, bridge.global_position)
		if not _alarm_beep.playing:
			_alarm_beep.play()
			get_tree().create_timer(1.6).timeout.connect(_alarm_beep.stop)


func _update_alarm_banner() -> void:
	_alarms = _alarms.filter(func(b): return is_instance_valid(b) and b.alarm_on)
	_alarm_banner.visible = not _alarms.is_empty()
	if _alarm_banner.visible:
		var b: FoldingBridge = _alarms[-1]
		var n: int = b.intruders.size()
		_alarm_banner.text = "  ALARM: %d %s CROSSING BRIDGE %d  " % [n, "ENEMY" if n == 1 else "ENEMIES", b.bridge_id]
		_alarm_banner.modulate.a = 1.0 if fmod(Time.get_ticks_msec() * 0.001 * FoldingBridge.ALARM_RATE, 1.0) < 0.6 else 0.7


func _look_at_alarm() -> void:
	if not _alarms.is_empty():
		camera_rig.focus(_alarms[-1].global_position)


## A unit's key (or its thumbnail): one on the production line, out at the spawn point picked now. Says why when it can't.
func spawn(type_id: String) -> void:
	if commander.submit({"type": "produce", "unit": type_id}) > 0:
		return
	if commander.units.size() + commander.production.size() >= AttackerCommander.UNIT_CAP:
		warn_once("cap", "The army is at its cap (%d, the production line included)" % AttackerCommander.UNIT_CAP, UIKit.DANGER)
	elif commander.supply < UnitTypes.DATA[type_id].cost:
		warn_once("credits", "Not enough spawn credits for a %s (%d)" % [UnitTypes.DATA[type_id].name, UnitTypes.DATA[type_id].cost], UIKit.DANGER)
		if hud:
			hud.flash_credits()


## Takes entry `index` off the production line, credits back.
func cancel_production(index: int) -> void:
	commander.submit({"type": "cancel", "index": index})


## RMB on a unit's thumbnail: the last of `type_id` on the production line comes off it.
func cancel_last(type_id: String) -> void:
	for i in range(commander.production.size() - 1, -1, -1):
		if commander.production[i].unit == type_id:
			cancel_production(i)
			return


## A warning on the HUD's panel (the squid says it), `at` where it happened.
func warn(text: String, col := UIKit.WARN, at := Vector3.INF) -> void:
	if hud:
		hud.warn(text, col, at)


## warn(), but the one under `key` no more often than WARN_REPEAT.
func warn_once(key: String, text: String, col := UIKit.WARN, at := Vector3.INF) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_warned.get(key, -100000)) < WARN_REPEAT * 1000.0:
		return
	_warned[key] = now
	warn(text, col, at)


# ---------------------------------------------------------------- visuals / HUD

func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.2
	t.outer_radius = 1.5
	t.ring_segments = 4
	_marker.mesh = t
	_marker.scale.y = 0.2
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	level.add_child(_marker)


func _ping(pos: Vector3, color: Color) -> void:
	_marker.global_position = pos + Vector3.UP * 0.1
	_marker.material_override = Mats.unshaded(color)
	_marker.visible = true
	_marker.scale = Vector3(1.4, 0.2, 1.4)
	var tw := _marker.create_tween()
	tw.tween_property(_marker, "scale", Vector3(0.4, 0.2, 0.4), 0.35)
	tw.tween_callback(func(): _marker.visible = false)


func _build_hud() -> void:
	hud = AttackerHUD.new()
	hud.controller = self
	hud.commander = commander
	hud.level = level
	add_child(hud)
	# The widgets the controller drives (and the showcases read) live in the HUD.
	_select_rect = hud.select_rect
	_selection_label = hud.status_label
	_aim_label = hud.aim_label
	_alarm_banner = hud.alarm_banner
	_alarm_banner.pressed.connect(_look_at_alarm)
	_alarm_beep = AudioStreamPlayer.new()
	_alarm_beep.stream = FoldingBridge._siren_stream()
	_alarm_beep.volume_db = -14.0
	add_child(_alarm_beep)

	# The transport helicopters, under the minimap: spaces, status, health, and Board / Fly / Look.
	if commander.fleet != null:
		helo_panel = HeloPanel.new()
		helo_panel.commander = commander
		helo_panel.level = level
		helo_panel.boardable_count = func(): return selected.filter(func(u): return is_instance_valid(u) and u.can_board_helo()).size()
		helo_panel.board_pressed.connect(_on_helo_board)
		helo_panel.fly_pressed.connect(_on_helo_fly)
		helo_panel.look_pressed.connect(_on_helo_look)
		# Pinned under the minimap, 12 px in from the right; it grows down and to the left with what it holds.
		helo_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		helo_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		helo_panel.grow_vertical = Control.GROW_DIRECTION_END
		helo_panel.offset_right = -AttackerHUD.MARGIN
		helo_panel.offset_left = -AttackerHUD.MARGIN
		helo_panel.offset_top = hud.helo_panel_top()
		helo_panel.offset_bottom = hud.helo_panel_top()
		hud.add_child(helo_panel)
		helo_panel.select_pressed.connect(_on_helo_pick)
		# Under the keys' panel and the aim label (that one follows the mouse over everything).
		hud.move_child(helo_panel, hud.help_panel.get_index())


func _process(_delta: float) -> void:
	if selected.any(func(u): return is_instance_valid(u) and u.raiding):
		_alive_selection()
	_selection_label.text = status_text()
	if _aiming == "cluster":
		_update_aim_preview()
	elif _aiming == "bombard":
		_update_bombard_preview()
	elif _aiming == "strafe":
		_update_strafe_preview()
	elif _aiming == "bomb":
		_update_bomb_preview()
	elif _aiming == "smoke":
		_update_smoke_preview()
	elif _aiming == "flash":
		_update_flash_preview()
	elif _aiming == "missile":
		_update_missile_preview()
	elif _aiming == "nest":
		_update_nest_preview()
	elif _aiming == "trap":
		_update_trap_preview()
	elif _aiming == "bridge":
		_update_bridge_preview()
	_update_alarm_banner()


## What the selection is doing, for the HUD's mugshot: states only (crossing, tagged, sneaking, guns heat...), the skills'
## readiness and cooldowns being on their tiles.
func status_text() -> String:
	var out := PackedStringArray()
	if is_instance_valid(selected_helo) and selected_helo.is_alive():
		out.append(selected_helo.status_text())
		if selected_helo.can_board():
			out.append("RMB a helipad you hold: fly there with what is aboard")
	var live := selected.filter(func(u): return is_instance_valid(u) and u.is_alive())
	var mules := live.filter(func(u): return u.has_setup())
	if not mules.is_empty():
		var parts := PackedStringArray()
		var armed := mules.filter(func(u): return u.is_armed()).size()
		var rising := mules.filter(func(u): return u.setting_up())
		var packing := mules.filter(func(u): return u.packing_up())
		if armed > 0:
			parts.append("%d armed" % armed)
		if not rising.is_empty():
			parts.append("%d setting up %ds" % [rising.size(), ceili(rising.map(func(u): return u.setup_left()).max())])
		if not packing.is_empty():
			parts.append("%d disarming %ds" % [packing.size(), ceili(packing.map(func(u): return u.setup_left()).max())])
		if armed + rising.size() + packing.size() == 0:
			parts.append("packed: set them up to fire [T]")
		out.append("Guns: " + " · ".join(parts))
	var flying := live.filter(func(u): return u.has_strafe() and u.on_run()).size()
	if flying > 0:
		out.append("On an attack run %d" % flying)
	var hippos := live.filter(func(u): return u.has_smoke())
	if not hippos.is_empty():
		if hippos.any(func(u): return u.is_overheated()):
			out.append("Guns overheated")
		else:
			var hottest: float = hippos.map(func(u): return u.heat / u.stats.overheat_time).max()
			if hottest > 0.0:
				out.append("Guns heat %d%%" % int(hottest * 100.0))
	var carriers := live.filter(func(u): return u.can_carry())
	var aboard: int = carriers.reduce(func(n, u): return n + u.riders.size(), 0)
	if aboard > 0:
		out.append("On their rafts %d · Space lets them off" % aboard)
	var crossing := live.filter(func(u): return u.is_crossing())
	if not crossing.is_empty():
		var riding := crossing.filter(func(u): return u.is_riding()).size()
		out.append("Crossing %d (%d swimming, %d riding) · can't fight or use skills" % [crossing.size(), crossing.size() - riding, riding])
	var under := live.filter(func(u): return u.has_dive() and u.is_submerged())
	if not under.is_empty():
		out.append("Under the water %d (%.0fs) · out of the defenders' sight" % [under.size(), under.map(func(u): return u.dive_left()).max()])
	var tagged := live.filter(func(u): return u.is_tagged())
	if not tagged.is_empty():
		out.append("Tagged by a sniper %d · defenders hit them %d%% harder" % [tagged.size(), roundi(AttackerUnit.TAG_BONUS * 100.0)])
	var lionesses := live.filter(func(u): return u.has_sneak())
	var marked := lionesses.filter(func(u): return u.is_tagged()).size()
	if marked > 0:
		out.append("Lionesses: %d tagged: can't sneak" % marked)
	var sneaking := lionesses.filter(func(u): return u.is_sneaking())
	if not sneaking.is_empty():
		out.append("Sneaking %d  %ds · RMB a defender: pounce" % [sneaking.size(), ceili(sneaking.map(func(u): return u.sneak_left()).max())])
	var burning := lionesses.filter(func(u): return u.is_blasting()).size()
	if burning > 0:
		out.append("Flamethrowers burning %d" % burning)
	var snakes := live.filter(func(u): return u.has_nest())
	if not snakes.is_empty():
		var perched := snakes.filter(func(u): return u.is_perched()).size()
		var climbing := snakes.filter(func(u): return u.in_tree() and not u.is_perched()).size()
		var coiled := snakes.filter(func(u): return u.is_coiled()).size()
		var squeezing := snakes.filter(func(u): return u.is_constricting())
		if perched + climbing + coiled > 0:
			out.append("Snakes: %d up a tree%s · %d coiled" % [perched, " (%d climbing)" % climbing if climbing > 0 else "", coiled])
		if not squeezing.is_empty():
			out.append("Constricting %d  %ds (can't be called off)" % [squeezing.size(), ceili(squeezing.map(func(u): return u.squeeze_left()).max())])
	var dogs := live.filter(func(u): return u.has_dog_modes())
	var healers := dogs.filter(func(u): return u.dog_mode == "heal")
	if not healers.is_empty():
		var healed: int = healers.reduce(func(n, u): return n + u.patients.filter(func(p): return u.can_heal(p)).size(), 0)
		out.append("Healing %d · %d units healed" % [healers.size(), healed])
	var sweepers := dogs.filter(func(u): return u.dog_mode == "sweep")
	if not sweepers.is_empty():
		var digging := sweepers.filter(func(u): return u.is_digging()).size()
		out.append("Minesweeping %d · %d disarmed%s" % [sweepers.size(), sweepers.reduce(func(n, u): return n + u.mines_disarmed, 0),
				" · %d digging" % digging if digging > 0 else ""])
	var ramming := live.filter(func(u): return u.has_ram() and u.is_ramming())
	if not ramming.is_empty():
		var charging := ramming.filter(func(u): return u.charge_gate != null).size()
		out.append("Ramming %d  %ds%s" % [ramming.size(), ceili(ramming.map(func(u): return u.ram_left()).max()),
				" · %d charging the gate" % charging if charging > 0 else ""])
	var supplied := live.filter(func(u): return u.resupply > 0.0)
	if not supplied.is_empty():
		out.append("Resupplied %d · skills back %d%% sooner" % [supplied.size(), roundi(supplied[0].resupply * 100.0)])
	return "\n".join(out)
