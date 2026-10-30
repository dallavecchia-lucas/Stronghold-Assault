class_name AttackerController
extends CanvasLayer
## Human RTS commander: camera, selection, orders, spawning and the RTS HUD.
## Turns mouse/keyboard input into commands for the AttackerCommander.
##
## LMB click/drag: select · Shift adds · RMB: attack-move / attack target
## Ctrl+RMB: move without stopping to fight · Ctrl+1-5 assign group · 1-5 recall
## Z X C V B N M H J K L Y U I: spawn units · Tab: cycle spawn point (the map's edge, and the
##    Forward Helipads while the attackers hold them: AttackerBase)
## F: aim the selected rhinos' cluster bombing (LMB fire, RMB/F cancel) · T: scout formation
##    with no rhino ready, the selected talons' strafe run: press LMB on the middle of the line,
##    drag the way to fly it, let go to fire (a click flies it from the talons; RMB/F cancel)
## G: aim the selected bisons' bombardment (LMB fire, RMB/G cancel)
##    with no bison ready, the selected talons' bomb strike (LMB fire, RMB/G cancel)
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
## F with no rhino, talon or lioness skill ready: the selected Serpent Snipers' sniper nest, LMB a tree (they
##    climb it and the trees round it; RMB/F cancel)
## G with no bison, talon or lioness skill ready: the selected Serpent Snipers' bush trap, LMB a bush (they coil
##    round it and the bushes round it; RMB/G cancel)
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
const SMOKE_FILL := Color(0.2, 0.9, 0.6, 0.35)
const SMOKE_LINE := Color(0.3, 1.0, 0.7)
const MISSILE_LINE := Color(1.0, 0.35, 0.3)

var level: LevelBuilder
var commander: AttackerCommander
var camera_rig: RTSCamera
var selected: Array = []
var groups := {}
var spawn_index := 0

var _drag_start := Vector2.ZERO
var _mouse_down := false
var _dragging := false
var _select_rect: Panel
var _supply_label: Label
var _count_label: Label
var _selection_label: Label
var _spawn_buttons := {}
var _spawn_point_buttons: Array[Button] = []
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
var _line_button: Button
var _dog_button: Button
var _fog: FogOverlay


func _ready() -> void:
	layer = 2
	camera_rig = RTSCamera.new()
	camera_rig.bounds = LevelBuilder.MAP_HALF
	level.add_child(camera_rig)
	camera_rig.camera.current = true
	camera_rig.focus(commander.spawn_points[0] * 0.65)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	commander.unit_died.connect(func(u): selected.erase(u))
	_build_marker()
	_build_aim_preview()
	_build_smoke_preview()
	_build_missile_preview()
	_build_hud()
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
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_set_aiming("")
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_drag_start = event.position
			elif _mouse_down:
				_mouse_down = false
				if _dragging:
					_box_select(Rect2(_drag_start, Vector2.ZERO).expand(event.position), event.shift_pressed)
				else:
					_click_select(event.position, event.shift_pressed)
				_dragging = false
				_select_rect.visible = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_order(event.position, event.ctrl_pressed)
	elif event is InputEventMouseMotion and _mouse_down:
		if not _dragging and event.position.distance_to(_drag_start) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			var r := Rect2(_drag_start, Vector2.ZERO).expand(event.position)
			_select_rect.position = r.position
			_select_rect.size = r.size
			_select_rect.visible = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == CLUSTER_KEY:
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
			return
		if event.physical_keycode == BOMBARD_KEY:
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
			return
		if event.physical_keycode == SMOKE_KEY:
			# A ready hippo's smoke screen comes first, then the kangaroos' flash grenades.
			if _aiming in ["smoke", "flash"]:
				_set_aiming("")
			elif not _ready_hippos().is_empty():
				_set_aiming("smoke")
			else:
				_set_aiming("flash" if not _ready_kangaroos().is_empty() else "")
			return
		if event.physical_keycode == MISSILE_KEY:
			_set_aiming("missile" if _aiming != "missile" and not _ready_elephants().is_empty() else "")
			return
		if event.physical_keycode == RAM_KEY:
			_alive_selection()
			commander.submit({"type": "ram", "units": selected.map(func(u): return u.unit_id)})
			return
		if event.physical_keycode == PING_KEY:
			_alive_selection()
			commander.submit({"type": "ping", "units": selected.map(func(u): return u.unit_id)})
			return
		if event.physical_keycode == SCOUT_KEY:
			_alive_selection()
			if selected.any(func(u): return u.stats.get("line", false)) and not selected.any(func(u): return u.stats.get("scouts", false)):
				toggle_lines()
			elif not _dogs().is_empty() and not selected.any(func(u): return u.stats.get("scouts", false)):
				toggle_dog_mode()
			else:
				commander.submit({"type": "scout", "units": selected.map(func(u): return u.unit_id)})
			return
		for type_id in UnitTypes.ORDER:
			if event.physical_keycode == UnitTypes.DATA[type_id].hotkey:
				spawn(type_id)
				return
		if event.is_action_pressed("spawn_cycle"):
			set_spawn_point((spawn_index + 1) % commander.spawn_points.size())
			return
		for i in 5:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				if event.ctrl_pressed:
					groups[i] = selected.duplicate()
				else:
					_set_selection(groups.get(i, []).filter(func(u): return is_instance_valid(u) and u.is_controllable()))
				return


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


func _box_select(rect: Rect2, add: bool) -> void:
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
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	selected = list
	for u in selected:
		u.selected = true


## Drops the dead, and raiders that have gone inside the stronghold.
func _alive_selection() -> void:
	selected = selected.filter(func(u): return is_instance_valid(u) and u.is_controllable())


func _issue_order(pos: Vector2, force_move: bool) -> void:
	_alive_selection()
	if selected.is_empty():
		return
	var ids := selected.map(func(u): return u.unit_id)
	var hit := _ray(pos, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS)
	if hit.is_empty():
		return
	var target = Combat.find_damageable(hit.collider)
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
	_aim_label.visible = mode in ["missile", "nest", "trap"]


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


## T (with no rhino selected) or the HUD's toggle: lionesses moved together form up in firing lines, or
## don't.
func toggle_lines() -> void:
	commander.submit({"type": "line", "on": not commander.line_formation})


# ---------------------------------------------------------------- Serpent Snipers

## The selected Serpent Snipers that can be sent up a tree (`skill` "nest") or round a bush ("trap"): all but
## those squeezing their prey (nothing calls that off).
func _serpents(skill: String) -> Array:
	_alive_selection()
	return selected.filter(func(u): return (u.has_nest() if skill == "nest" else u.has_trap()) and not u.is_constricting())


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


func spawn(type_id: String) -> void:
	commander.submit({"type": "spawn", "unit": type_id, "spawn": spawn_index})


func set_spawn_point(i: int) -> void:
	spawn_index = i
	for k in _spawn_point_buttons.size():
		_spawn_point_buttons[k].button_pressed = k == i


## The spawn point after `i` that is open (a helipad only while the attackers hold it).
func _next_open_spawn(i: int) -> int:
	var n := commander.spawn_points.size()
	for k in range(1, n + 1):
		if commander.spawn_open((i + k) % n):
			return (i + k) % n
	return 0


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
	var root := UIKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_select_rect = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 1.0, 0.4, 0.12)
	sb.border_color = Color(0.3, 1.0, 0.4, 0.9)
	sb.set_border_width_all(1)
	_select_rect.add_theme_stylebox_override("panel", sb)
	_select_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_rect.visible = false
	root.add_child(_select_rect)

	var bottom := UIKit.panel()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 12
	root.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bottom.add_child(row)

	var info := VBoxContainer.new()
	_supply_label = UIKit.label("", 26, UIKit.WARN)
	_count_label = UIKit.label("", 14, Color(0.8, 0.85, 0.9))
	_selection_label = UIKit.label("", 14, Color(0.8, 0.85, 0.9))
	info.add_child(_supply_label)
	info.add_child(_count_label)
	info.add_child(_selection_label)
	info.custom_minimum_size.x = 150
	row.add_child(info)
	# Lionesses moved together form up in firing lines: the toggle shows while any are selected.
	_line_button = UIKit.button("", 13)
	_line_button.focus_mode = Control.FOCUS_NONE
	_line_button.tooltip_text = "Lionesses moved together converge into firing lines, 8 abreast, more lines behind"
	_line_button.pressed.connect(toggle_lines)
	_line_button.visible = false
	info.add_child(_line_button)
	# Wolf Medics: their mode (healing or minesweeping) and the switch, while any are selected.
	_dog_button = UIKit.button("", 13)
	_dog_button.focus_mode = Control.FOCUS_NONE
	_dog_button.tooltip_text = "Healing: each dog heals up to 2 hurt units near it until they are full\nMinesweeping: each dog sniffs out the mines round it and digs them out, the minefield's outer rim first"
	_dog_button.pressed.connect(toggle_dog_mode)
	_dog_button.visible = false
	info.add_child(_dog_button)

	# Two rows of unit buttons and the spawn points three to a row: the panel fits the screen (1600 wide).
	var grid := GridContainer.new()
	grid.columns = ceili(UnitTypes.ORDER.size() / 2.0)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	for type_id in UnitTypes.ORDER:
		var d: Dictionary = UnitTypes.DATA[type_id]
		var key := OS.get_keycode_string(d.hotkey)
		var b := UIKit.button("%s\n%d  [%s]" % [d.name, d.cost, key], 14)
		b.custom_minimum_size = Vector2(132, 50)
		b.tooltip_text = "%s · %d HP · %s" % [d.name, int(d.hp), d.role]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spawn.bind(type_id))
		grid.add_child(b)
		_spawn_buttons[type_id] = b

	var sp := VBoxContainer.new()
	sp.add_child(UIKit.label("SPAWN AT  [Tab]", 12, Color(0.7, 0.75, 0.85)))
	var sp_row := GridContainer.new()
	sp_row.columns = 3
	var bg := ButtonGroup.new()
	for i in level.spawn_names.size():
		var b := UIKit.button(level.spawn_names[i], 15)
		b.toggle_mode = true
		b.button_group = bg
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 34)
		b.pressed.connect(set_spawn_point.bind(i))
		if i < level.spawn_bases.size() and level.spawn_bases[i] != null:
			b.tooltip_text = "%s: a forward spawn point while you hold it" % level.spawn_bases[i].display_name
		sp_row.add_child(b)
		_spawn_point_buttons.append(b)
	sp.add_child(sp_row)
	row.add_child(sp)
	set_spawn_point(0)

	var help := UIKit.label("LMB select/drag · RMB attack-move / attack · Ctrl+RMB move · Ctrl+1-5 group · WASD/Q/E/wheel camera\nRhinos: F cluster bombing (LMB fire, RMB cancel) · T scout formation · Hippos: R smoke screen (LMB fire, RMB cancel)\nBisons: G bombardment (LMB fire, RMB cancel), onto the gun decks and roofs too\nTalons: F strafe run (press LMB on the target, drag the way to fly, let go) · G bomb strike (LMB fire) · RMB cancels\nElephants: O missiles (LMB an enemy aircraft, RMB cancel) · Rams: Space ram, then RMB a gate to charge it\nGiraffes: see furthest through the fog · P ping: marks every defender it reaches, even under camo, and reveals infiltrators out of camo\nKangaroos: R flash grenade (LMB fire, RMB cancel) when no hippo's smoke is ready · they resupply units nearby\nLionesses: F sneak (then RMB a defender: they pounce) · G fire blast · T firing lines on/off when moved together\nSerpent Snipers: F sniper nest (LMB a tree: up it they see and shoot further; any move order climbs them down) · G bush trap (LMB a bush: coiled, they strike and crush a defender who comes close)\nWolf Medics: T healing (2 units each) / minesweeping (they find the hidden mines and dig them out; RMB sweeps on the way, Ctrl+RMB doesn't)\nChimps / Rams / Kangaroos: RMB next to a broken gate to send them in\nHelipads (S/E/W Pad): spawn there and +%.1f supply/s each while you hold them · sabotaged, stand ground units by one to retake it" % AttackerBase.INCOME,
			13, Color(0.85, 0.85, 0.85, 0.75))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position = Vector2(14, help.position.y - 240)
	root.add_child(help)

	_aim_label = UIKit.label("", 15, MISSILE_LINE)
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_label.visible = false
	root.add_child(_aim_label)


func _process(_delta: float) -> void:
	if selected.any(func(u): return is_instance_valid(u) and u.raiding):
		_alive_selection()
	_supply_label.text = "Supply %d" % int(commander.supply)
	_count_label.text = "Army %d / %d   (+%.0f/s)" % [commander.units.size(), AttackerCommander.UNIT_CAP, commander.income_rate()]
	_selection_label.text = "Selected %d" % selected.size()
	var rhinos := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_cluster_bomb())
	if not rhinos.is_empty():
		var ready := rhinos.filter(func(u): return u.cluster_ready()).size()
		_selection_label.text += "\nCluster bombs %d/%d [F]" % [ready, rhinos.size()]
		if ready == 0:
			var soonest: float = rhinos.map(func(u): return u.cluster_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
		if rhinos.any(func(u): return commander.is_scouting(u)):
			_selection_label.text += "\nScout formation [T]"
	var bisons := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_bombard())
	if not bisons.is_empty():
		var ready := bisons.filter(func(u): return u.bombard_ready()).size()
		_selection_label.text += "\nBombardment %d/%d [G]" % [ready, bisons.size()]
		if ready == 0:
			var soonest: float = bisons.map(func(u): return u.bombard_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
	var talons := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_strafe())
	if not talons.is_empty():
		for skill in [["Strafe run", "strafe_cd", "F"], ["Bomb strike", "bomb_cd", "G"]]:
			var ready := talons.filter(func(u): return u.get(skill[1]) <= 0.0 and not u.on_run()).size()
			_selection_label.text += "\n%s %d/%d [%s]" % [skill[0], ready, talons.size(), skill[2]]
			if ready == 0:
				var soonest: float = talons.map(func(u): return u.get(skill[1])).min()
				if soonest > 0.0:
					_selection_label.text += "  %ds" % ceili(soonest)
		var flying := talons.filter(func(u): return u.on_run()).size()
		if flying > 0:
			_selection_label.text += "\nOn an attack run %d" % flying
	var hippos := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_smoke())
	if not hippos.is_empty():
		var ready := hippos.filter(func(u): return u.smoke_ready()).size()
		_selection_label.text += "\nSmoke screen %d/%d [R]" % [ready, hippos.size()]
		if ready == 0:
			var soonest: float = hippos.map(func(u): return u.smoke_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
		if hippos.any(func(u): return u.is_overheated()):
			_selection_label.text += "\nGuns overheated"
		else:
			var hottest: float = hippos.map(func(u): return u.heat / u.stats.overheat_time).max()
			_selection_label.text += "\nGuns heat %d%%" % int(hottest * 100.0)
	var kangaroos := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_flash())
	if not kangaroos.is_empty():
		var ready := kangaroos.filter(func(u): return u.flash_ready()).size()
		_selection_label.text += "\nFlash grenade %d/%d [R]" % [ready, kangaroos.size()]
		if ready == 0:
			var soonest: float = kangaroos.map(func(u): return u.flash_cd).min()
			if soonest > 0.0:
				_selection_label.text += "  %ds" % ceili(soonest)
	var supplied := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.resupply > 0.0)
	if not supplied.is_empty():
		_selection_label.text += "\nResupplied %d · skills back %d%% sooner" % [supplied.size(), roundi(supplied[0].resupply * 100.0)]
	var tagged := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.is_tagged())
	if not tagged.is_empty():
		_selection_label.text += "\nTagged by a sniper %d · defenders hit them %d%% harder" % [tagged.size(), roundi(AttackerUnit.TAG_BONUS * 100.0)]
	var elephants := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_missiles())
	if not elephants.is_empty():
		var ready := elephants.filter(func(u): return u.missiles_ready()).size()
		_selection_label.text += "\nMissiles %d/%d [O]" % [ready, elephants.size()]
		if ready == 0:
			var soonest: float = elephants.map(func(u): return u.missile_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
	var giraffes := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_ping())
	if not giraffes.is_empty():
		var ready := giraffes.filter(func(u): return u.ping_ready()).size()
		_selection_label.text += "\nPing %d/%d [P]" % [ready, giraffes.size()]
		if ready == 0:
			var soonest: float = giraffes.map(func(u): return u.ping_cd).min()
			if soonest > 0.0:
				_selection_label.text += "  %ds" % ceili(soonest)
	var lionesses := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_sneak())
	_line_button.visible = not lionesses.is_empty()
	if not lionesses.is_empty():
		var ready := lionesses.filter(func(u): return u.sneak_ready()).size()
		_selection_label.text += "\nSneak %d/%d [F]" % [ready, lionesses.size()]
		var sneaking := lionesses.filter(func(u): return u.is_sneaking())
		var marked := lionesses.filter(func(u): return u.is_tagged()).size()
		if marked > 0:
			_selection_label.text += "  · %d tagged: can't sneak" % marked
		elif ready == 0 and sneaking.is_empty():
			var soonest: float = lionesses.map(func(u): return u.sneak_cd).min()
			if soonest > 0.0:
				_selection_label.text += "  %ds" % ceili(soonest)
		if not sneaking.is_empty():
			var left: float = sneaking.map(func(u): return u.sneak_left()).max()
			_selection_label.text += "\nSneaking %d  %ds · RMB a defender: pounce" % [sneaking.size(), ceili(left)]
		var lit := lionesses.filter(func(u): return u.blast_ready()).size()
		_selection_label.text += "\nFire blast %d/%d [G]" % [lit, lionesses.size()]
		var burning := lionesses.filter(func(u): return u.is_blasting()).size()
		if burning > 0:
			_selection_label.text += "\nFlamethrowers burning %d" % burning
		elif lit == 0:
			var soonest: float = lionesses.map(func(u): return u.blast_cd).min()
			if soonest > 0.0:
				_selection_label.text += "  %ds" % ceili(soonest)
		_line_button.text = "Firing lines: %s  [T]" % ("ON" if commander.line_formation else "OFF")
	var snakes := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_nest())
	if not snakes.is_empty():
		var perched := snakes.filter(func(u): return u.is_perched()).size()
		var climbing := snakes.filter(func(u): return u.in_tree() and not u.is_perched())
		_selection_label.text += "\nSniper nest [F] · %d up a tree" % perched
		if not climbing.is_empty():
			var up := climbing.filter(func(u): return u.skill_dir() > 0).size()
			_selection_label.text += " · %d climbing %s" % [climbing.size(), "up" if up == climbing.size() else "down" if up == 0 else "up and down"]
		var coiled := snakes.filter(func(u): return u.is_coiled()).size()
		var squeezing := snakes.filter(func(u): return u.is_constricting())
		var coiling := snakes.filter(func(u): return u.in_bush() and not u.is_coiled() and not u.is_constricting()).size()
		_selection_label.text += "\nBush trap [G] · %d coiled" % coiled
		if coiling > 0:
			_selection_label.text += " · %d coiling or uncoiling" % coiling
		if not squeezing.is_empty():
			var left: float = squeezing.map(func(u): return u.squeeze_left()).max()
			_selection_label.text += "\nConstricting %d  %ds (can't be called off)" % [squeezing.size(), ceili(left)]
	var dogs := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_dog_modes())
	_dog_button.visible = not dogs.is_empty()
	if not dogs.is_empty():
		var healers := dogs.filter(func(u): return u.dog_mode == "heal")
		var sweepers := dogs.filter(func(u): return u.dog_mode == "sweep")
		_dog_button.text = "Dogs: %s  [T]" % ("HEALING" if sweepers.is_empty() else "MINESWEEPING" if healers.is_empty() else "MIXED")
		if not healers.is_empty():
			var healed: int = healers.reduce(func(n, u): return n + u.patients.filter(func(p): return u.can_heal(p)).size(), 0)
			_selection_label.text += "\nHealing %d · %d units healed" % [healers.size(), healed]
		if not sweepers.is_empty():
			var digging := sweepers.filter(func(u): return u.is_digging()).size()
			var cleared: int = sweepers.reduce(func(n, u): return n + u.mines_disarmed, 0)
			_selection_label.text += "\nMinesweeping %d · %d disarmed" % [sweepers.size(), cleared]
			if digging > 0:
				_selection_label.text += " · %d digging" % digging
	var rams := selected.filter(func(u): return is_instance_valid(u) and u.is_alive() and u.has_ram())
	if not rams.is_empty():
		var ready := rams.filter(func(u): return u.ram_ready()).size()
		_selection_label.text += "\nRam %d/%d [Space]" % [ready, rams.size()]
		if ready == 0:
			var soonest: float = rams.map(func(u): return u.ram_cd).min()
			_selection_label.text += "  %ds" % ceili(soonest)
		var ramming := rams.filter(func(u): return u.is_ramming())
		if not ramming.is_empty():
			var charging := ramming.filter(func(u): return u.charge_gate != null).size()
			var left: float = ramming.map(func(u): return u.ram_left()).max()
			_selection_label.text += "\nRamming %d  %ds" % [ramming.size(), ceili(left)]
			if charging > 0:
				_selection_label.text += " · %d charging the gate" % charging
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
	for type_id in _spawn_buttons:
		_spawn_buttons[type_id].disabled = not commander.can_afford(type_id)
	# A sabotaged helipad spawns nothing until it is retaken.
	for k in _spawn_point_buttons.size():
		_spawn_point_buttons[k].disabled = not commander.spawn_open(k)
	if not commander.spawn_open(spawn_index):
		set_spawn_point(_next_open_spawn(spawn_index))
