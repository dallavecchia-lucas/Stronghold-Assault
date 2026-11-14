class_name HudGlyph
extends RefCounted
## Small line-art icons for the attacker's HUD, drawn with CanvasItem primitives (the game has no icon art yet): the
## skills (AttackerHUD.SKILLS), the bridges and outposts counters. draw() fits one into a rectangle.
##
##   reticle   an aimed strike on the ground (cluster bombing, bombardment, bomb strike)
##   strafe    a diving run along a line          burst    a flash grenade
##   cloud     a smoke screen                     missile  a missile salvo
##   rings     a sonar ping                       ram      a charge
##   eye       a sneak                            flame    a fire blast
##   tree      a sniper nest                      bush     a bush trap
##   wave      a dive under the water             unload   riders off the rafts
##   bridge    a folding bridge                   outpost  a forward helipad
##   lines     firing lines                       cross    the dogs' healing (and minesweeping)
##   gun       the mules' guns set up             ring     scout formation
##   base      the main base (the command citadel)


static func draw(ci: CanvasItem, kind: String, r: Rect2, col: Color, w := 2.0) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	match kind:
		"reticle":
			ci.draw_arc(c, s * 0.62, 0.0, TAU, 32, col, w, true)
			ci.draw_arc(c, s * 0.2, 0.0, TAU, 16, col, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * s * 0.38, c + d * s * 0.92, col, w, true)
		"strafe":
			var a := c + Vector2(-0.75, 0.55) * s
			var b := c + Vector2(0.7, -0.6) * s
			ci.draw_line(a, b, col, w, true)
			_head(ci, a, b, s * 0.38, col)
			for k in 3:
				ci.draw_circle(c + Vector2(-0.55 + 0.42 * k, 0.85 - 0.36 * k) * s + Vector2(0.18, 0.18) * s, s * 0.08, col)
		"burst":
			ci.draw_circle(c, s * 0.22, col)
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				ci.draw_line(c + d * s * 0.38, c + d * s * (0.92 if k % 2 == 0 else 0.7), col, w, true)
		"cloud":
			var fill := Color(col, col.a * 0.55)
			for p in [Vector2(-0.4, 0.2), Vector2(0.38, 0.22), Vector2(0.0, -0.2)]:
				ci.draw_circle(c + p * s, s * 0.42, fill)
				ci.draw_arc(c + p * s, s * 0.42, 0.0, TAU, 24, col, w * 0.6, true)
		"missile":
			var d := Vector2(1, -1).normalized()
			var n := Vector2(d.y, -d.x)
			var tail := c - d * s * 0.7
			var nose := c + d * s * 0.55
			ci.draw_line(tail, nose, col, w * 1.6, true)
			ci.draw_colored_polygon(PackedVector2Array([nose + d * s * 0.32, nose + n * s * 0.16, nose - n * s * 0.16]), col)
			ci.draw_colored_polygon(PackedVector2Array([tail, tail + n * s * 0.3 + d * s * 0.05, tail + d * s * 0.3]), col)
			ci.draw_colored_polygon(PackedVector2Array([tail, tail - n * s * 0.3 + d * s * 0.05, tail + d * s * 0.3]), col)
			ci.draw_line(tail - d * s * 0.1, tail - d * s * 0.35, Color(col, col.a * 0.6), w, true)
		"rings":
			var o := c + Vector2(-0.6, 0.6) * s
			ci.draw_circle(o, s * 0.14, col)
			for k in 3:
				ci.draw_arc(o, s * (0.48 + 0.42 * k), -PI * 0.5, 0.0, 16, col, w, true)
		"ram":
			for k in 2:
				var x := (-0.55 + 0.6 * k) * s
				ci.draw_polyline(PackedVector2Array([c + Vector2(x, -0.6 * s), c + Vector2(x + 0.5 * s, 0.0),
						c + Vector2(x, 0.6 * s)]), col, w * 1.4, true)
		"eye":
			var top := PackedVector2Array()
			var bottom := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				var x := (-0.9 + 1.8 * t) * s
				var y := sin(PI * t) * s * 0.42
				top.append(c + Vector2(x, -y))
				bottom.append(c + Vector2(x, y * 0.7))
			ci.draw_polyline(top, col, w, true)
			ci.draw_polyline(bottom, col, w, true)
			ci.draw_circle(c + Vector2(0, -0.04 * s), s * 0.2, col)
		"flame":
			var pts := PackedVector2Array()
			for k in 24:
				var th := TAU * k / 24.0
				pts.append(c + Vector2(sin(th) * sin(th * 0.5) * s * 0.62, (0.15 - cos(th)) * s * 0.72))
			ci.draw_colored_polygon(pts, Color(col, col.a * 0.45))
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w, true)
		"tree":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.9) * s, c + Vector2(0.62, 0.42) * s,
					c + Vector2(-0.62, 0.42) * s]), Color(col, col.a * 0.45))
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -0.9) * s, c + Vector2(0.62, 0.42) * s,
					c + Vector2(-0.62, 0.42) * s, c + Vector2(0, -0.9) * s]), col, w, true)
			ci.draw_line(c + Vector2(0, 0.42) * s, c + Vector2(0, 0.9) * s, col, w * 1.4, true)
		"bush":
			var fill := Color(col, col.a * 0.45)
			for p in [Vector2(-0.45, 0.3), Vector2(0.45, 0.3), Vector2(0.0, -0.05)]:
				ci.draw_circle(c + p * s, s * 0.38, fill)
			ci.draw_arc(c + Vector2(0, 0.25) * s, s * 0.82, PI * 1.08, PI * 1.92, 24, col, w, true)
			ci.draw_line(c + Vector2(-0.9, 0.62) * s, c + Vector2(0.9, 0.62) * s, col, w, true)
		"wave":
			for row in 2:
				var pts := PackedVector2Array()
				for k in 17:
					var t := k / 16.0
					pts.append(c + Vector2((-0.9 + 1.8 * t) * s, (-0.45 + 0.42 * row) * s + sin(t * TAU * 1.5) * s * 0.1))
				ci.draw_polyline(pts, col, w, true)
			var a := c + Vector2(0, 0.05) * s
			var b := c + Vector2(0, 0.9) * s
			ci.draw_line(a, b, col, w, true)
			_head(ci, a, b, s * 0.3, col)
		"unload":
			var a := c + Vector2(0, -0.85) * s
			var b := c + Vector2(0, 0.35) * s
			ci.draw_line(a, b, col, w * 1.3, true)
			_head(ci, a, b, s * 0.4, col)
			ci.draw_line(c + Vector2(-0.8, 0.75) * s, c + Vector2(0.8, 0.75) * s, col, w * 1.3, true)
		"bridge":
			var y := c.y + s * 0.1
			ci.draw_line(Vector2(c.x - s * 0.95, y), Vector2(c.x + s * 0.95, y), col, w * 1.3, true)
			ci.draw_arc(Vector2(c.x, y + s * 0.62), s * 0.85, PI * 1.18, PI * 1.82, 20, col, w, true)
			for k in 5:
				var x := c.x + (-0.6 + 0.3 * k) * s
				ci.draw_line(Vector2(x, y), Vector2(x, y - s * (0.22 + 0.2 * (1.0 - absf(k - 2) / 2.0))), col, w * 0.8, true)
			ci.draw_line(Vector2(c.x - s * 0.95, y + s * 0.55), Vector2(c.x + s * 0.95, y + s * 0.55), Color(col, col.a * 0.5), w * 0.7, true)
		"outpost":
			ci.draw_arc(c, s * 0.85, 0.0, TAU, 32, col, w, true)
			ci.draw_line(c + Vector2(-0.35, -0.45) * s, c + Vector2(-0.35, 0.45) * s, col, w * 1.3, true)
			ci.draw_line(c + Vector2(0.35, -0.45) * s, c + Vector2(0.35, 0.45) * s, col, w * 1.3, true)
			ci.draw_line(c + Vector2(-0.35, 0.0) * s, c + Vector2(0.35, 0.0) * s, col, w * 1.3, true)
		"lines":
			# Ranks: two lines of heads, the arrow they march along.
			for row in 2:
				for k in 4:
					ci.draw_circle(c + Vector2((-0.6 + 0.4 * k) * s, (-0.15 + 0.42 * row) * s), s * 0.11, col)
			var a := c + Vector2(-0.7, -0.62) * s
			var b := c + Vector2(0.75, -0.62) * s
			ci.draw_line(a, b, col, w, true)
			_head(ci, a, b, s * 0.3, col)
		"cross":
			var arm := s * 0.24
			ci.draw_rect(Rect2(c - Vector2(arm, s * 0.72), Vector2(arm * 2.0, s * 1.44)), Color(col, col.a * 0.5))
			ci.draw_rect(Rect2(c - Vector2(s * 0.72, arm), Vector2(s * 1.44, arm * 2.0)), Color(col, col.a * 0.5))
			ci.draw_polyline(PackedVector2Array([c + Vector2(-arm, -s * 0.72), c + Vector2(arm, -s * 0.72), c + Vector2(arm, -arm),
					c + Vector2(s * 0.72, -arm), c + Vector2(s * 0.72, arm), c + Vector2(arm, arm), c + Vector2(arm, s * 0.72),
					c + Vector2(-arm, s * 0.72), c + Vector2(-arm, arm), c + Vector2(-s * 0.72, arm), c + Vector2(-s * 0.72, -arm),
					c + Vector2(-arm, -arm), c + Vector2(-arm, -s * 0.72)]), col, w * 0.8, true)
		"gun":
			# A siege gun on its carriage, the barrel raised.
			ci.draw_rect(Rect2(c + Vector2(-0.75, 0.2) * s, Vector2(1.5, 0.32) * s), Color(col, col.a * 0.5))
			ci.draw_circle(c + Vector2(-0.45, 0.62) * s, s * 0.2, col)
			ci.draw_circle(c + Vector2(0.45, 0.62) * s, s * 0.2, col)
			ci.draw_line(c + Vector2(-0.15, 0.2) * s, c + Vector2(0.72, -0.78) * s, col, w * 2.0, true)
		"ring":
			ci.draw_arc(c, s * 0.68, 0.0, TAU, 32, Color(col, col.a * 0.6), w * 0.7, true)
			ci.draw_circle(c, s * 0.2, Color(col, col.a * 0.5))
			for k in 6:
				ci.draw_circle(c + Vector2.from_angle(TAU * k / 6.0) * s * 0.68, s * 0.13, col)
		"base":
			# The command citadel: a broad hull and two masts.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.9, 0.55) * s, c + Vector2(0.9, 0.55) * s,
					c + Vector2(0.72, 0.0) * s, c + Vector2(-0.72, 0.0) * s]), Color(col, col.a * 0.5))
			ci.draw_rect(Rect2(c + Vector2(-0.4, -0.35) * s, Vector2(0.8, 0.35) * s), Color(col, col.a * 0.7))
			ci.draw_line(c + Vector2(-0.22, -0.35) * s, c + Vector2(-0.22, -0.9) * s, col, w, true)
			ci.draw_line(c + Vector2(0.22, -0.35) * s, c + Vector2(0.22, -0.75) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.9, 0.55) * s, c + Vector2(0.9, 0.55) * s, col, w, true)
		_:
			ci.draw_arc(c, s * 0.6, 0.0, TAU, 24, col, w, true)


## An arrowhead at `b` on the line from `a`.
static func _head(ci: CanvasItem, a: Vector2, b: Vector2, size: float, col: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([b + d * size * 0.3, b - d * size * 0.7 + n * size * 0.5,
			b - d * size * 0.7 - n * size * 0.5]), col)
