class_name CommandOctopus
extends Control
## Central command's tactical octopus, the attacking army's commander, on the HUD's warning panel (AttackerHUD): its
## portrait (PORTRAIT, cut to REGION: the head, the headset and the mic) comes up on screen while a warning is up and
## fades away once the warnings are old. Talking, its frame glows in the warning's colour, the ON AIR light blinks and the
## portrait leans in a little. Without the picture (its file missing) the panel shows COMMAND alone.

const PORTRAIT := "res://assets/ui/command_octopus.jpg"
## The square of the picture the portrait shows (px of the source image).
const REGION := Rect2(40, 10, 330, 330)
## How much closer the portrait leans while it talks (a share of REGION).
const LEAN := 0.05
const FADE := 0.6
const FONT := 11

## Talking: a warning is up.
var talking := false
## The colour of the warning it is giving (the frame).
var tone := UIKit.WARN

static var _texture: Texture2D
var _t := 0.0
var _lean := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	modulate.a = 0.0
	if _texture == null and ResourceLoader.exists(PORTRAIT):
		_texture = load(PORTRAIT) as Texture2D


func _process(delta: float) -> void:
	_t += delta
	modulate.a = move_toward(modulate.a, 1.0 if talking else 0.0, delta / FADE)
	_lean = move_toward(_lean, 1.0 if talking else 0.0, delta * 1.5)
	if modulate.a > 0.0:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.04, 0.05, 0.06, 0.95))
	if _texture:
		var src := REGION.grow(-REGION.size.x * LEAN * 0.5 * smoothstep(0.0, 1.0, _lean))
		draw_texture_rect_region(_texture, r, src)
	var font := get_theme_default_font()
	# A dark band at the bottom for the caption.
	var band := FONT + 6.0
	draw_rect(Rect2(0, size.y - band, size.x, band), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(0, size.y - 4.0), "COMMAND", HORIZONTAL_ALIGNMENT_CENTER, size.x, FONT, Color(0.85, 0.9, 0.85))
	# ON AIR: a red light blinking at the top left while it talks.
	var lit := talking and fmod(_t * 2.0, 1.0) < 0.6
	draw_circle(Vector2(7, 7), 3.5, UIKit.DANGER if lit else Color(0.3, 0.08, 0.08, 0.8))
	# The frame, glowing in the warning's colour while it talks.
	var glow := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 6.0)) if talking else 0.5
	draw_rect(r.grow(-1.0), Color(tone, glow), false, 2.0)
