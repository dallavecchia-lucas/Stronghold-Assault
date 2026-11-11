class_name HeloPanel
extends PanelContainer
## The attacking player's transport helicopter panel (top right of the RTS view): one block for each of the fleet's helicopters
## (HeloFleet, TransportHelo) with the spaces used in its hold, what it is doing, its health, and the buttons:
##   Board     the selected units that can go aboard walk to its ramp and in, as many as it has room for
##   Fly > X   it takes off with what it has aboard for the helipad X, one the attackers hold; its only stop this trip
##   Look      the camera goes to it
## A helicopter shot down shows when its replacement arrives. It reads the fleet through the commander
## (AttackerCommander.fleet, helo_can_fly) and tells the controller what was pressed; the controller sends the commands.

signal board_pressed(helo_index: int)
signal fly_pressed(helo_index: int, spawn_index: int)
signal look_pressed(helo_index: int)

var commander: AttackerCommander
var level: LevelBuilder
## Returns how many of the selected units could board a helicopter right now.
var boardable_count := Callable()
## The helicopter selected in the world (-1: none): its block is lit.
var selected_slot := -1

var _rows: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UIKit.panel_style())
	custom_minimum_size.x = 250
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(UIKit.label("TRANSPORT HELICOPTERS", 12, Color(0.7, 0.75, 0.85)))
	for i in HeloCargo.FLEET_SIZE:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		col.add_child(box)
		var title := UIKit.label("", 15)
		box.add_child(title)
		var info := UIKit.label("", 12, Color(0.8, 0.85, 0.9))
		box.add_child(info)
		var bar := UIKit.bar(230, 8, UIKit.GOOD)
		box.add_child(bar)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 4)
		box.add_child(buttons)
		var board := UIKit.button("Board", 13)
		board.focus_mode = Control.FOCUS_NONE
		board.tooltip_text = "Select units, then Board (or RMB the helicopter): they walk to its ramp and go aboard, as many as it has room for.\nElephants and giraffes take 5 spaces, rhinos and hippos 2, bisons 10, mules 15, the rest 1 (of %d)." % HeloCargo.CAPACITY
		board.pressed.connect(_on_board.bind(i))
		buttons.add_child(board)
		var flies := {}
		for k in level.spawn_bases.size():
			if level.spawn_bases[k] == null:
				continue
			var fly := UIKit.button("Fly > %s" % level.spawn_names[k], 13)
			fly.focus_mode = Control.FOCUS_NONE
			fly.tooltip_text = "Fly what is aboard to %s, one the attackers hold: it lands on the pad, puts the units down beside the camp\n(one every %.2f s) and comes home. Its only stop; if the helipad is lost on the way it brings them back,\nand if it falls while it is on the pad it loses a fifth of its health lifting off." % [level.spawn_bases[k].display_name, HeloCargo.UNLOAD_TIME]
			fly.pressed.connect(_on_fly.bind(i, k))
			buttons.add_child(fly)
			flies[k] = fly
		var look := UIKit.button("Look", 13)
		look.focus_mode = Control.FOCUS_NONE
		look.pressed.connect(_on_look.bind(i))
		buttons.add_child(look)
		_rows.append({"title": title, "info": info, "bar": bar, "board": board, "fly": flies, "look": look})


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
		var title: Label = row["title"]
		title.add_theme_color_override("font_color", UIKit.ACCENT if selected_slot == i else Color.WHITE)
		if h == null:
			var wait := ceili(fleet.replace_in[i]) if i < fleet.replace_in.size() else 0
			title.text = "HELO %d · DESTROYED" % (i + 1)
			(row["info"] as Label).text = "A new one arrives in %d s" % wait if wait > 0 else "A new one is arriving"
			(row["bar"] as ProgressBar).value = 0.0
			(row["board"] as Button).disabled = true
			(row["look"] as Button).disabled = true
			for k in row["fly"]:
				(row["fly"][k] as Button).disabled = true
			continue
		title.text = "HELO %d · %d/%d spaces" % [i + 1, h.spaces_used(), HeloCargo.CAPACITY]
		(row["info"] as Label).text = h.status_text()
		var bar: ProgressBar = row["bar"]
		bar.value = h.health()
		# The same steps as the smoke it trails: grey at 60%, black at 40%, fire at 10%.
		var f := h.health()
		UIKit.set_bar_color(bar, UIKit.DANGER if f <= TransportHelo.BLACK_SMOKE_AT else UIKit.WARN if f <= TransportHelo.GREY_SMOKE_AT else UIKit.GOOD)
		var board: Button = row["board"]
		board.disabled = not h.can_board() or can_board_n == 0 or h.spaces_free() <= 0
		board.text = "Board %d" % can_board_n if can_board_n > 0 else "Board"
		(row["look"] as Button).disabled = false
		for k in row["fly"]:
			(row["fly"][k] as Button).disabled = not commander.helo_can_fly(i, k)
