class_name HeloPanel
extends PanelContainer
## The attacking player's transport helicopter panel (under the minimap): one line for each of the fleet's helicopters
## (HeloFleet, TransportHelo) with the spaces used in its hold and its health; click its name to select it (and look at it).
## What it is doing and its buttons show while it is the one selected (Board too while selected units could go aboard):
##   Board     the selected units that can go aboard walk to its ramp and in, as many as it has room for
##   Fly > X   it takes off with what it has aboard for the helipad X, one the attackers hold; its only stop this trip
##   Look      the camera goes to it
## A helicopter shot down shows when its replacement arrives. It reads the fleet through the commander
## (AttackerCommander.fleet, helo_can_fly) and tells the controller what was pressed; the controller sends the commands.

signal board_pressed(helo_index: int)
signal fly_pressed(helo_index: int, spawn_index: int)
signal look_pressed(helo_index: int)
signal select_pressed(helo_index: int)

var commander: AttackerCommander
var level: LevelBuilder
## Returns how many of the selected units could board a helicopter right now.
var boardable_count := Callable()
## The helicopter selected in the world (-1: none): its block is lit.
var selected_slot := -1

var _rows: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UIKit.panel_style())
	custom_minimum_size.x = AttackerHUD.MINIMAP + 6.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	add_child(col)
	for i in HeloCargo.FLEET_SIZE:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		col.add_child(box)
		var title := Button.new()
		title.flat = true
		title.focus_mode = Control.FOCUS_NONE
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_constant_override("h_separation", 0)
		for st in ["normal", "hover", "pressed"]:
			title.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		title.tooltip_text = "Select it and look at it"
		title.pressed.connect(func(): select_pressed.emit(i))
		box.add_child(title)
		var bar := UIKit.bar(AttackerHUD.MINIMAP - 14.0, 5, UIKit.GOOD)
		box.add_child(bar)
		var info := UIKit.label("", AttackerHUD.FONT, Color(0.8, 0.85, 0.9))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = AttackerHUD.MINIMAP - 14.0
		box.add_child(info)
		var buttons := HFlowContainer.new()
		buttons.add_theme_constant_override("h_separation", 3)
		buttons.add_theme_constant_override("v_separation", 3)
		box.add_child(buttons)
		var board := UIKit.button("Board", AttackerHUD.FONT)
		board.focus_mode = Control.FOCUS_NONE
		board.tooltip_text = "Select units, then Board (or RMB the helicopter): they walk to its ramp and go aboard, as many as it has room for.\nElephants and giraffes take 5 spaces, rhinos and hippos 2, bisons 10, mules 15, the rest 1 (of %d)." % HeloCargo.CAPACITY
		board.pressed.connect(_on_board.bind(i))
		buttons.add_child(board)
		var flies := {}
		for k in level.spawn_bases.size():
			if level.spawn_bases[k] == null:
				continue
			var fly := UIKit.button("Fly > %s" % level.spawn_names[k], AttackerHUD.FONT)
			fly.focus_mode = Control.FOCUS_NONE
			fly.tooltip_text = "Fly what is aboard to %s, one the attackers hold: it lands on the pad, puts the units down beside the camp\n(one every %.2f s) and comes home. Its only stop; if the helipad is lost on the way it brings them back,\nand if it falls while it is on the pad it loses a fifth of its health lifting off." % [level.spawn_bases[k].display_name, HeloCargo.UNLOAD_TIME]
			fly.pressed.connect(_on_fly.bind(i, k))
			buttons.add_child(fly)
			flies[k] = fly
		var look := UIKit.button("Look", AttackerHUD.FONT)
		look.focus_mode = Control.FOCUS_NONE
		look.pressed.connect(_on_look.bind(i))
		buttons.add_child(look)
		_rows.append({"title": title, "info": info, "bar": bar, "board": board, "fly": flies, "look": look, "buttons": buttons})


func _on_board(i: int) -> void:
	board_pressed.emit(i)


func _on_fly(i: int, k: int) -> void:
	fly_pressed.emit(i, k)


func _on_look(i: int) -> void:
	look_pressed.emit(i)


func _process(_delta: float) -> void:
	if commander == null or commander.fleet == null:
		return
	var fleet := commander.fleet
	var can_board_n := int(boardable_count.call()) if boardable_count.is_valid() else 0
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var h := fleet.helo_at(i)
		var title: Button = row["title"]
		var lit := UIKit.ACCENT if selected_slot == i else Color.WHITE
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			title.add_theme_color_override(c, lit)
		var info: Label = row["info"]
		info.visible = selected_slot == i or h == null
		(row["buttons"] as Control).visible = selected_slot == i
		if h == null:
			var wait := ceili(fleet.replace_in[i]) if i < fleet.replace_in.size() else 0
			title.text = "HELO %d · DESTROYED" % (i + 1)
			info.text = "A new one arrives in %d s" % wait if wait > 0 else "A new one is arriving"
			(row["bar"] as ProgressBar).value = 0.0
			(row["board"] as Button).disabled = true
			(row["look"] as Button).disabled = true
			for k in row["fly"]:
				(row["fly"][k] as Button).disabled = true
			continue
		title.text = "HELO %d · %d/%d spaces" % [i + 1, h.spaces_used(), HeloCargo.CAPACITY]
		info.text = h.status_text()
		var bar: ProgressBar = row["bar"]
		bar.value = h.health()
		# The same steps as the smoke it trails: grey at 60%, black at 40%, fire at 10%.
		var f := h.health()
		UIKit.set_bar_color(bar, UIKit.DANGER if f <= TransportHelo.BLACK_SMOKE_AT else UIKit.WARN if f <= TransportHelo.GREY_SMOKE_AT else UIKit.GOOD)
		var board: Button = row["board"]
		board.disabled = not h.can_board() or can_board_n == 0 or h.spaces_free() <= 0
		board.text = "Board %d" % can_board_n if can_board_n > 0 else "Board"
		# Units selected that could go aboard: the Board button shows on its own.
		if selected_slot != i and h.can_board() and can_board_n > 0:
			(row["buttons"] as Control).visible = true
			for k in row["fly"]:
				(row["fly"][k] as Button).visible = false
			(row["look"] as Button).visible = false
		else:
			for k in row["fly"]:
				(row["fly"][k] as Button).visible = true
			(row["look"] as Button).visible = true
		(row["look"] as Button).disabled = false
		for k in row["fly"]:
			(row["fly"][k] as Button).disabled = not commander.helo_can_fly(i, k)
