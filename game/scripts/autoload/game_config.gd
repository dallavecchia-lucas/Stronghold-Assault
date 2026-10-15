extends Node
## Global settings shared between the main menu and the match, plus input setup.

enum PlayerSide { DEFENDER, ATTACKER }

const TEAM_DEFENDER := 0
const TEAM_ATTACKER := 1

# Physics layer bits (see project settings layer names).
const LAYER_WORLD := 1
const LAYER_ATTACKERS := 2
const LAYER_DEFENDERS := 4
const LAYER_STRUCTURES := 8
const LAYER_ALL_SOLID := LAYER_WORLD | LAYER_ATTACKERS | LAYER_DEFENDERS | LAYER_STRUCTURES

const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]

var player_side: PlayerSide = PlayerSide.DEFENDER
var difficulty := 1
var match_duration := 600.0
var mouse_sensitivity := 0.0025

# Test hooks, passed after `--` on the command line:
#   --autotest=defender|attacker   play a scripted match and quit
#   --screenshot=path.png          save a screenshot during the autotest
#   --duration=seconds             autotest length (game time)
var autotest := ""
var screenshot_path := ""
var autotest_duration := 90.0


func _ready() -> void:
	_setup_input()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			autotest = arg.get_slice("=", 1)
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--duration="):
			autotest_duration = arg.get_slice("=", 1).to_float()


## CPU attacker income multiplier for the chosen difficulty.
func ai_income_mult() -> float:
	return [0.75, 1.0, 1.4][difficulty]


func _setup_input() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("reload", [KEY_R])
	_add_action("fire", [], [MOUSE_BUTTON_LEFT])
	_add_action("aim", [], [MOUSE_BUTTON_RIGHT])
	_add_action("station_next", [KEY_TAB])
	_add_action("cam_rotate_left", [KEY_Q])
	_add_action("cam_rotate_right", [KEY_E])
	_add_action("pause", [KEY_ESCAPE])
	_add_action("spawn_cycle", [KEY_V])
	var digit_keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in digit_keys.size():
		_add_action("slot_%d" % (i + 1), [digit_keys[i]])


func _add_action(action: String, keys: Array, mouse_buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in mouse_buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)
