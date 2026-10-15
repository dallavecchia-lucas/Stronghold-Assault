extends Control
## Title screen: pick a side and difficulty, then start an offline match vs the CPU.


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Engine.time_scale = 1.0

	if GameConfig.autotest != "":
		_start(GameConfig.PlayerSide.ATTACKER if GameConfig.autotest == "attacker" else GameConfig.PlayerSide.DEFENDER)
		return

	var bg := UIKit.full_rect(TextureRect.new()) as TextureRect
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.2, 0.28))
	grad.set_color(1, Color(0.04, 0.05, 0.07))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.3)
	gt.fill_to = Vector2(1.1, 1.1)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := UIKit.label("STRONGHOLD ASSAULT", 64, Color(0.92, 0.94, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UIKit.label("Offline skirmish vs CPU", 20, Color(0.6, 0.7, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())

	var defend := UIKit.button("DEFEND  —  first person, switch between posts", 22)
	defend.custom_minimum_size = Vector2(560, 60)
	defend.pressed.connect(_start.bind(GameConfig.PlayerSide.DEFENDER))
	box.add_child(defend)
	var attack := UIKit.button("ATTACK  —  command the siege army", 22)
	attack.custom_minimum_size = Vector2(560, 60)
	attack.pressed.connect(_start.bind(GameConfig.PlayerSide.ATTACKER))
	box.add_child(attack)

	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_child(UIKit.label("CPU difficulty  ", 18))
	var diff := OptionButton.new()
	for n in GameConfig.DIFFICULTY_NAMES:
		diff.add_item(n)
	diff.select(GameConfig.difficulty)
	diff.item_selected.connect(func(i): GameConfig.difficulty = i)
	diff.add_theme_font_size_override("font_size", 18)
	diff_row.add_child(diff)
	box.add_child(diff_row)

	var intro := UIKit.button("Watch Intro", 18)
	intro.custom_minimum_size = Vector2(560, 44)
	intro.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/intro.tscn"))
	box.add_child(intro)

	var quit := UIKit.button("Quit", 18)
	quit.custom_minimum_size = Vector2(560, 44)
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)


func _start(side: GameConfig.PlayerSide) -> void:
	GameConfig.player_side = side
	get_tree().change_scene_to_file.call_deferred("res://scenes/match.tscn")
