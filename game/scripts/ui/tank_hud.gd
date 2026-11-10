class_name TankHud
extends Control
## The Hover Tank's panel while the player drives it (DefenderTank), over the crosshair the controller draws: under the
## crosshair a bar for the main gun's reload and whether the turret is on the aim (the gun fires only once it is), and in
## the corner the cannon, the machine guns and the speed.

const BLOCK := Vector2(250, 126)
const BLOCK_MARGIN := Vector2(16, 16)
const EMPTY := Color(0.2, 0.22, 0.26, 0.9)
const DIM := Color(0.7, 0.75, 0.85)

var tank: DefenderTank


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible and tank != null:
		queue_redraw()


func _draw() -> void:
	if tank == null:
		return
	var font := get_theme_default_font()
	var view := get_viewport_rect().size
	var c := view * 0.5
	var cam := tank.get_camera()
	if tank.is_alive() and cam != null:
		# Where the machine guns point (straight ahead along the hull, whatever the turret is on).
		var mg := tank.mg_point()
		if not cam.is_position_behind(mg):
			var p := cam.unproject_position(mg)
			var col := UIKit.WARN if tank.rig.mg_firing else Color(1.0, 0.78, 0.25, 0.75)
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_line(p + d * 4.0, p + d * 11.0, Color(0, 0, 0, 0.6), 4.0, true)
				draw_line(p + d * 4.0, p + d * 11.0, col, 2.0, true)
			draw_string(font, p + Vector2(14, 5), "MG", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	if tank.is_alive():
		# Under the crosshair: the reload, and whether the turret is on it.
		var ready := tank.cannon_cd <= 0.0
		var on := tank.on_aim()
		var f := 1.0 - tank.cannon_cd / DefenderTank.CANNON_RELOAD
		draw_rect(Rect2(c + Vector2(-40, 26), Vector2(80, 5)), EMPTY)
		draw_rect(Rect2(c + Vector2(-40, 26), Vector2(80.0 * clampf(f, 0.0, 1.0), 5)), UIKit.GOOD if ready else UIKit.WARN)
		var text := "FIRE" if ready and on else ("TRAVERSING" if ready else "RELOADING")
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
		draw_string(font, c + Vector2(-w * 0.5, 46), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.GOOD if ready and on else DIM)
	var origin := Vector2(BLOCK_MARGIN.x, view.y - BLOCK_MARGIN.y - BLOCK.y)
	draw_style_box(UIKit.panel_style(), Rect2(origin, BLOCK))
	draw_string(font, origin + Vector2(12, 24), "SPEED  %d m/s" % int(absf(tank.speed)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, origin + Vector2(12, 52), "CANNON [LMB]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD if tank.cannon_cd <= 0.0 else DIM)
	draw_rect(Rect2(origin + Vector2(124, 43), Vector2(114, 10)), EMPTY)
	draw_rect(Rect2(origin + Vector2(124, 43), Vector2(114.0 * clampf(1.0 - tank.cannon_cd / DefenderTank.CANNON_RELOAD, 0.0, 1.0), 10)),
			UIKit.GOOD if tank.cannon_cd <= 0.0 else UIKit.WARN)
	draw_string(font, origin + Vector2(12, 80), "MACHINE GUNS [hold RMB]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UIKit.WARN if tank.rig.mg_firing else DIM)
	# The jump: ready, or its cooldown running down.
	var airborne := tank.jump_state in [DefenderTank.Jump.CHARGE, DefenderTank.Jump.AIR]
	var jump_ready := tank.jump_cd <= 0.0 and not airborne
	draw_string(font, origin + Vector2(12, 108), "JUMP [Space]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UIKit.WARN if airborne else (UIKit.GOOD if jump_ready else DIM))
	draw_rect(Rect2(origin + Vector2(124, 99), Vector2(114, 10)), EMPTY)
	draw_rect(Rect2(origin + Vector2(124, 99), Vector2(114.0 * clampf(1.0 - tank.jump_cd / DefenderTank.JUMP_COOLDOWN, 0.0, 1.0), 10)),
			UIKit.GOOD if jump_ready else (UIKit.WARN if airborne else DIM))
	var n := tank.notice()
	if n != "":
		var w := font.get_string_size(n, HORIZONTAL_ALIGNMENT_CENTER, -1, 30).x
		draw_string(font, Vector2((view.x - w) * 0.5, view.y * 0.3), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UIKit.DANGER)
