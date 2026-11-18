class_name DefenderHUD
extends Control
## The defending player's HUD (DefenderController builds it), after the paper sketch, as lean as the attacker's: small
## islands, each on screen only while it has something to show, no text under FONT px.
##
##   top left      the squads on the roster (DefenderArmory, up to six): a portrait each with its key (F1-F6 takes command,
##                 Ctrl+F<n> its next auto order), its auto order, and a small health bar under it (its troopers' together);
##                 the one driven lit, one being hit blinking. Under them what the credits buy right now, with the key
##   top centre    the time to hold | the air vents standing; under it the gates and the credits (StatusBanner)
##   top right     the tactical view of the base (BaseView: each side's guns, the attackers close to it, the gates, the
##                 player's garrison spawn and BASE / FIELD), and the minimap (Minimap: LMB takes the post nearest there)
##   bottom left   the ammo counter: the post or squad driven, its weapon, its rounds (or heat, or pressure) big, the heat
##                 bar and its health
##   bottom centre the skills of what is driven, a tile each with its key (cooldowns swept, what is on lit), the drone
##                 swarm call (C, the drones ready on their docks) on every post; and over them the post's keys for a few seconds after taking it
##
## The squads' portraits are rendered from their troopers' and machines' models (UnitPortraits.DEFENDER_SUBJECTS).

const MARGIN := 10.0
const FONT := 11
const SQUAD_TILE := 48.0
const BUY_TILE := 36.0
const SKILL_TILE := 52.0
const MINIMAP := 200.0
const BASE_VIEW := 156.0
## The post's keys show this long after taking it, then fade.
const HINT_TIME := 8.0
## Attackers this close to the stronghold's footprint (m) count as close to its side.
const NEAR := 70.0
const CAPTION := Color(0.7, 0.75, 0.85)
## What the credits buy: [kind (DefenderArmory.COSTS), key, name, portrait].
const BUYS := [["aa", "B", "AA Squad", "d_aa"], ["flame", "N", "Flame Squad", "d_flame"],
		["infiltrator", "M", "Infiltrator Squad", "d_infiltrator"], ["sniper", "K", "Sniper", "d_sniper"],
		["jet", "J", "Fighter Jet", "d_jet"], ["tank", "H", "Hover Tank", "d_tank"]]

var controller: DefenderController

var minimap: Minimap
var base_view: BaseView
var portraits: UnitPortraits

var _banner: StatusBanner
var _squads_panel: Control
var _squad_cells: Array[Control] = []
var _squad_slots: Array[HudSlot] = []
var _squad_bars: Array[ProgressBar] = []
var _buy_row: Control
var _buy_slots := {}  # kind -> HudSlot
var _ammo_name: Label
var _ammo_weapon: Label
var _ammo_status: Label
var _ammo_heat: ProgressBar
var _ammo_hp: ProgressBar
var _skills_panel: Control
var _skill_slots: Array[HudSlot] = []
var _hint: Label
var _hint_left := 0.0
var _side_cd := 0.0
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portraits = UnitPortraits.new()
	portraits.subjects = UnitPortraits.DEFENDER_SUBJECTS.duplicate()
	add_child(portraits)
	_build_banner()
	_build_squads()
	_build_map()
	_build_ammo()
	_build_skills()


# ---------------------------------------------------------------- building

## A panel pinned to a corner of the screen by `preset`, MARGIN in, growing out of the corner with what it holds.
func _island(preset: int) -> PanelContainer:
	var p := UIKit.panel()
	p.set_anchors_preset(preset)
	var right := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var bottom := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH if preset == Control.PRESET_CENTER_BOTTOM \
			else Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	var x := 0.0 if preset == Control.PRESET_CENTER_BOTTOM else -MARGIN if right else MARGIN
	var y := -MARGIN if bottom else MARGIN
	p.offset_left = x
	p.offset_right = x
	p.offset_top = y
	p.offset_bottom = y
	add_child(p)
	return p


func _build_banner() -> void:
	_banner = StatusBanner.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_banner)


func _build_squads() -> void:
	_squads_panel = _island(Control.PRESET_TOP_LEFT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_squads_panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for k in DefenderArmory.MAX_SQUADS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(SQUAD_TILE, SQUAD_TILE)
		slot.key_text = "F%d" % (k + 1)
		slot.clicked.connect(_on_squad_clicked.bind(k))
		cell.add_child(slot)
		var bar := UIKit.bar(SQUAD_TILE, 5, UIKit.GOOD)
		cell.add_child(bar)
		cell.visible = false
		row.add_child(cell)
		_squad_cells.append(cell)
		_squad_slots.append(slot)
		_squad_bars.append(bar)
	_buy_row = HBoxContainer.new()
	_buy_row.add_theme_constant_override("separation", 4)
	col.add_child(_buy_row)
	var buy := UIKit.label("BUY", FONT, CAPTION)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_buy_row.add_child(buy)
	for b in BUYS:
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(BUY_TILE, BUY_TILE)
		slot.key_text = b[1]
		slot.corner_text = str(DefenderArmory.COSTS[b[0]])
		slot.initials = String(b[2]).left(2).to_upper()
		slot.tooltip_text = "%s  [%s] · %d credits" % [b[2], b[1], DefenderArmory.COSTS[b[0]]]
		slot.clicked.connect(_on_buy_clicked.bind(b[0]))
		_buy_row.add_child(slot)
		_buy_slots[b[0]] = slot


func _build_map() -> void:
	var frame := _island(Control.PRESET_TOP_RIGHT)
	var sb := UIKit.panel_style(UIKit.PANEL_BG, 4)
	sb.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	frame.add_child(row)
	base_view = BaseView.new()
	base_view.custom_minimum_size = Vector2(BASE_VIEW, BASE_VIEW + BaseView.KEYS_H)
	base_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	base_view.side_pressed.connect(controller.move_spawn_to)
	base_view.centre_pressed.connect(controller.toggle_spawn_priority)
	row.add_child(base_view)
	minimap = Minimap.new()
	minimap.defender = controller
	minimap.level = controller.level
	minimap.commander = controller.commander
	minimap.custom_minimum_size = Vector2(MINIMAP, MINIMAP)
	minimap.tooltip_text = "LMB: take the post nearest there"
	row.add_child(minimap)


func _build_ammo() -> void:
	var panel := _island(Control.PRESET_BOTTOM_LEFT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size.x = 200
	panel.add_child(col)
	_ammo_name = UIKit.label("", 13)
	col.add_child(_ammo_name)
	_ammo_weapon = UIKit.label("", FONT, CAPTION)
	_ammo_weapon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_ammo_weapon)
	_ammo_status = UIKit.label("", 26)
	col.add_child(_ammo_status)
	_ammo_heat = UIKit.bar(200, 6, UIKit.WARN)
	col.add_child(_ammo_heat)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	col.add_child(hp_row)
	var hp_l := UIKit.label("HEALTH", FONT, CAPTION)
	hp_row.add_child(hp_l)
	_ammo_hp = UIKit.bar(142, 7, UIKit.GOOD)
	_ammo_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_ammo_hp)


func _build_skills() -> void:
	_skills_panel = _island(Control.PRESET_CENTER_BOTTOM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_skills_panel.add_child(row)
	for k in 6:
		var slot := HudSlot.new()
		slot.custom_minimum_size = Vector2(SKILL_TILE, SKILL_TILE)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.visible = false
		row.add_child(slot)
		_skill_slots.append(slot)
	_hint = UIKit.label("", 12, Color(0.88, 0.9, 0.95))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -MARGIN - SKILL_TILE - 24.0
	_hint.offset_bottom = _hint.offset_top
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


## Where the alerts go: under the banner.
func alerts_top() -> float:
	return StatusBanner.HEIGHT + StatusBanner.STRIP_H + 10.0


# ---------------------------------------------------------------- input

func _on_squad_clicked(event: InputEventMouseButton, k: int) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.ctrl_pressed:
		controller.cycle_squad_order(k)
	else:
		controller.select_squad(k)


func _on_buy_clicked(event: InputEventMouseButton, kind: String) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		controller.buy_squad(kind)


## A new post taken: its keys show for HINT_TIME.
func on_switched() -> void:
	_hint_left = HINT_TIME


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	_clock += delta
	_update_banner()
	_update_squads()
	_update_ammo(delta)
	_update_skills()
	_side_cd -= delta
	if _side_cd <= 0.0:
		_side_cd = 0.25
		_update_base_view()


func _update_banner() -> void:
	var level := controller.level
	var m: Node = controller.match_ui.match_node if controller.match_ui else null
	var t := maxf(float(m.time_left), 0.0) if m != null else -1.0
	var clock := "%d:%02d" % [int(t) / 60, int(t) % 60] if t >= 0.0 else "—"
	_banner.left = ["HOLD FOR", clock, UIKit.DANGER if t >= 0.0 and t < 60.0 else Color.WHITE, "then the stronghold has held",
			StatusBanner.CAPTION]
	_banner.left_tip = "The defenders win when the clock runs out with an air vent still standing"
	var total := level.vents.size()
	var left := level.vents_left()
	_banner.right = ["VENTS STANDING", "%d / %d" % [left, total], BaseView.health_color(float(left) / maxf(total, 1.0)),
			"lose them all and it falls", StatusBanner.CAPTION]
	_banner.right_tip = "The air vents on the roofs: the attackers win once every one is destroyed"
	_banner.gates = []
	for side in level.gates:
		var g: Structure = level.gates[side]
		_banner.gates.append([String(side).left(1).to_upper(), g.hp / g.max_hp if g.is_alive() else 0.0, g.recently_damaged(1.0)])
	var armory := controller.armory
	if armory:
		_banner.strip_text = "CREDITS %d" % int(armory.credits) if armory.income <= 0.0 \
				else "CREDITS %d  +%.0f/s" % [int(armory.credits), armory.income]
		_banner.strip_tip = "Credits buy squads, the Sniper, the Fighter Jet and the Hover Tank (top left: what they buy now). " \
				+ "They are earned by killing attackers: each pays %d%% of what it cost them, a big unit a lot" % int(DefenderArmory.BOUNTY * 100.0)
	else:
		_banner.strip_text = ""


## The portrait of squad `s` (UnitPortraits.DEFENDER_SUBJECTS), "" for none.
static func _portrait_key(s) -> String:
	if s is AASquad:
		return "d_aa"
	if s is FlameSquad:
		return "d_flame"
	if s is InfiltratorSquad:
		return "d_infiltrator"
	if s is Sniper:
		return "d_sniper"
	if s is DefenderJet:
		return "d_jet"
	if s is DefenderTank:
		return "d_tank"
	return ""


## Squad `s`'s health as one fraction: its troopers' together, the fallen ones as nothing (a machine's own).
static func squad_health(s) -> float:
	var pips: Array = s.pips()
	var count := 1 if (s is DefenderMachine or s is Sniper) else DefenderSquad.SIZE
	var sum := 0.0
	for p in pips:
		sum += p
	return clampf(sum / maxf(maxi(count, pips.size()), 1), 0.0, 1.0)


func _update_squads() -> void:
	var armory := controller.armory
	if armory == null:
		_squads_panel.visible = false
		return
	var n := armory.squads.size()
	for k in DefenderArmory.MAX_SQUADS:
		_squad_cells[k].visible = k < n
		if k >= n:
			continue
		var s = armory.squads[k]
		var slot := _squad_slots[k]
		var key := _portrait_key(s)
		slot.texture = UnitPortraits.get_texture(key) if key != "" else null
		slot.initials = String(s.station_name).left(2).to_upper()
		slot.corner_text = s.order_name()
		var driving: bool = s == controller.current
		var hurt: bool = s.alert() and fmod(_clock * 3.0, 1.0) < 0.5
		slot.active = driving or hurt
		slot.accent = UIKit.DANGER if hurt and not driving else UIKit.ACCENT
		slot.disabled = not s.can_possess()
		slot.tooltip_text = "%s  [F%d]\n%s · %s\nF%d or click: take command · Ctrl+F%d (or Ctrl+click): next auto order" \
				% [s.station_name, k + 1, s.order_name(), s.doing(driving), k + 1, k + 1]
		slot.queue_redraw()
		var f := squad_health(s)
		_squad_bars[k].value = f
		UIKit.set_bar_color(_squad_bars[k], BaseView.health_color(f))
	# What the credits buy right now (nothing once the roster is full).
	var any := false
	for b in BUYS:
		var slot: HudSlot = _buy_slots[b[0]]
		slot.visible = n < DefenderArmory.MAX_SQUADS and armory.can_buy(b[0])
		any = any or slot.visible
		if slot.visible:
			slot.texture = UnitPortraits.get_texture(b[3])
			slot.queue_redraw()
	_buy_row.visible = any
	_squads_panel.visible = n > 0 or any


func _update_ammo(delta: float) -> void:
	var s = controller.current
	_hint_left = maxf(_hint_left - delta, 0.0)
	if s == null:
		_ammo_name.text = "No post"
		_ammo_weapon.text = "1-9 a post · Tab the hottest · G the Gunner Squad"
		_ammo_status.text = "—"
		_ammo_heat.visible = false
		_ammo_hp.value = 0.0
		_hint.text = "Number keys or Tab to take over a post · F1-F6 a squad"
		_hint.modulate.a = 1.0
		return
	var info: Dictionary = s.get_hud_info()
	_ammo_name.text = s.station_name
	_ammo_weapon.text = info.get("weapon", "")
	_ammo_weapon.visible = _ammo_weapon.text != ""
	_ammo_status.text = info.get("status", "—")
	_ammo_heat.visible = info.has("heat")
	if info.has("heat"):
		var heat: float = info.heat
		_ammo_heat.value = heat
		UIKit.set_bar_color(_ammo_heat, info.get("bar_color", UIKit.DANGER if heat > 0.75 else UIKit.WARN))
	var hp: float = info.get("hp", 0.0)
	_ammo_hp.value = hp
	UIKit.set_bar_color(_ammo_hp, BaseView.health_color(hp))
	_hint.text = info.get("hint", "")
	_hint.modulate.a = clampf(_hint_left / 1.5, 0.0, 1.0)


# ---------------------------------------------------------------- skills

## A skill tile's data.
static func _skill(title: String, glyph: String, key: String, cooldown := 0.0, left := 0.0, active := false, corner := "",
		disabled := false) -> Dictionary:
	return {"name": title, "glyph": glyph, "key": key, "cooldown": cooldown, "left": left, "active": active, "corner": corner,
			"disabled": disabled}


## The skills of what the player drives (its own: none for a gun or the Gunner Squad), then the drone call (every post).
func skills_of(s) -> Array:
	var out := []
	if s is AASquad:
		out.append(_skill("Mines", "mine", "F", s.mine_cd / AASquad.MINE_COOLDOWN, s.mine_cd, s.mine_aiming))
		out.append(_skill("Lock on (hold on an aircraft)", "reticle", "RMB", 0.0, 0.0, s.locked,
				"LOCK" if s.locked else ("%d%%" % roundi(s.lock_progress / AASquad.LOCK_TIME * 100.0) if s.lock_progress > 0.0 else "")))
		out.append(_order(s))
	elif s is FlameSquad:
		out.append(_order(s))
	elif s is InfiltratorSquad:
		var camo: float = s.camo_left
		out.append(_skill("Adaptive camo", "camo", "Q", s.camo_cd / InfiltratorSquad.CAMO_COOLDOWN if camo <= 0.0 else 0.0,
				s.camo_cd if camo <= 0.0 else 0.0, camo > 0.0, "%ds" % ceili(camo) if camo > 0.0 else ""))
		out.append(_skill("Sabotage (next to an enemy helipad)", "wrench", "F", 0.0, 0.0, s.sabotaging != null,
				"KIT %d" % s.kits, s.kits <= 0))
		out.append(_order(s))
	elif s is Sniper:
		var on: float = s.thermal_left
		out.append(_skill("Thermal sight", "thermal", "T", s.thermal_cd / Sniper.THERMAL_RECHARGE if on <= 0.0 else 0.0,
				s.thermal_cd if on <= 0.0 else 0.0, on > 0.0, "%ds" % ceili(on) if on > 0.0 else ""))
		var reloading: bool = s.leader != null and s.leader.has_method("reloading") and s.leader.reloading()
		out.append(_skill("Reload", "reload", "R", 0.0, 0.0, reloading))
	elif s is DefenderJet:
		out.append(_skill("Bomb", "bomb", "LMB", 0.0, 0.0, false, str(s.bombs), s.bombs <= 0))
		var salvo: float = s.salvo_cd
		out.append(_skill("Missile barrage", "missile", "RMB", salvo / DefenderJet.SALVO_RELOAD, salvo, s.salvo_left > 0))
		out.append(_skill("Boost", "ram", "Shift", 1.0 - s.boost, 0.0, false, "%d%%" % roundi(s.boost * 100.0), s.get("_boost_spent") == true))
		out.append(_skill("Airbrake", "brake", "Space"))
	elif s is DefenderTank:
		out.append(_skill("Cannon", "reticle", "LMB", s.cannon_cd / DefenderTank.CANNON_RELOAD, s.cannon_cd))
		out.append(_skill("Machine guns (along the hull)", "strafe", "RMB"))
		out.append(_skill("Jump", "up", "Space", s.jump_cd / DefenderTank.JUMP_COOLDOWN, s.jump_cd))
	elif s is DefenderSoldier:
		var r = s.get("_reloading")
		out.append(_skill("Reload", "reload", "R", 0.0, 0.0, r != null and float(r) > 0.0))
	var drones := controller.drones
	if drones:
		var ready := drones.ready_count()
		out.append(_skill("Call a drone swarm here (%d drones ready on their docks)" % ready, "drone", "C", 0.0, 0.0, false, str(ready),
				ready <= 0))
	return out


func _order(s) -> Dictionary:
	return _skill("Auto order for when you leave it", "flag", "V", 0.0, 0.0, false, s.order_name())


func _update_skills() -> void:
	var s = controller.current
	var list: Array = skills_of(s) if s != null else []
	for k in _skill_slots.size():
		var slot := _skill_slots[k]
		slot.visible = k < list.size()
		if not slot.visible:
			continue
		var d: Dictionary = list[k]
		slot.glyph = d.glyph
		slot.key_text = d.key
		slot.cooldown = d.cooldown
		slot.center_text = "%d" % ceili(d.left) if d.left > 0.0 else ""
		slot.corner_text = d.corner
		slot.active = d.active
		slot.disabled = d.disabled or d.left > 0.0
		slot.tooltip_text = "%s  [%s]" % [d.name, d.key]
		slot.queue_redraw()
	_skills_panel.visible = not list.is_empty()


# ---------------------------------------------------------------- the base

## The face of the stronghold `p` is on (north, east, south, west).
static func side_of(p: Vector3) -> String:
	var best := "south"
	var best_d := -INF
	for side in Garrison.SIDE_ORDER:
		var d: float = (LevelBuilder.SIDES[side].dir as Vector3).dot(Vector3(p.x, 0.0, p.z))
		if d > best_d:
			best_d = d
			best = side
	return best


func _update_base_view() -> void:
	var level := controller.level
	var sides := {}
	for side in Garrison.SIDE_ORDER:
		sides[side] = {"hp": 0.0, "max": 0.0, "alive": 0, "total": 0, "crewed": 0, "near": 0, "gate": -1.0}
	var guns: Array = level.stations.filter(func(st): return st is MountedGun)
	guns.append_array(level.aa_turrets)
	for g in guns:
		if not is_instance_valid(g):
			continue
		var d: Dictionary = sides[side_of(g.global_position)]
		d["hp"] += maxf(float(g.hp), 0.0)
		d["max"] += float(g.max_hp)
		d["total"] += 1
		if float(g.hp) > 0.0:
			d["alive"] += 1
			if not g.has_method("is_manned") or g.is_manned():
				d["crewed"] += 1
	for u in get_tree().get_nodes_in_group("attacker_units"):
		if not u.is_alive() or u.ghosted() or u.hidden_under():
			continue
		if LevelBuilder.base_distance(u.global_position) < NEAR:
			sides[side_of(u.global_position)]["near"] += 1
	for side in level.gates:
		var g: Structure = level.gates[side]
		sides[side]["gate"] = g.hp / g.max_hp if g.is_alive() else 0.0
	for side in sides:
		var d: Dictionary = sides[side]
		d["guns"] = d["hp"] / d["max"] if d["max"] > 0.0 else -1.0
	base_view.sides = sides
	var garrison := controller.garrison
	if garrison:
		var c := garrison.control_of(controller.player_number)
		if not c.is_empty():
			base_view.spawn_side = c.side
			base_view.priority = c.priority
		for side in Garrison.SIDE_ORDER:
			base_view.spawn_counts[side] = garrison.spawns_at(side)
		var g := garrison.summary()
		base_view.summary_text = "Guns crewed %d/%d · deck %d/%d · field %d · moving %d" % [g.guns, g.guns_alive, g.deck,
				g.deck_total, g.field, g.walking]
	base_view.visible = garrison != null or not guns.is_empty()
