extends Node3D
## Intro cinematic. Builds its sets in code and plays a fixed timeline of shots,
## title cards and lighting cues synced to the score (assets/audio/intro_theme.ogg).
##
## Any key or click skips to the main menu. Render to video with Godot's Movie Maker:
##   godot --path game --write-movie intro.avi --fixed-fps 30 res://scenes/intro.tscn
## Preview from a given time with `-- --intro-start=80`.

const LENGTH := 212.0
const THEME := "res://assets/audio/intro_theme.ogg"

const CITY := Vector3(0, 0, 0)
const MEMORIAL := Vector3(0, 0, 300)
const FOREST := Vector3(400, 0, 0)
const GALLERY := Vector3(-400, 0, 0)
const RIDGE := Vector3(0, 0, -400)
const CITADEL := Vector3(0, 0, -720)

## [model folder, caption]
const HEROES := [
	["cyber_bear_commando", "THE BEAR"],
	["war_elephant_sentinel", "THE ELEPHANT"],
	["kangaroo_commando", "THE KANGAROO"],
	["armored_lioness_unit", "THE LIONESS"],
	["armored_rhino_unit", "THE RHINO"],
	["night_ops_chimpanzee", "THE CHIMPANZEE"],
	["sky_talon_battalion", "THE EAGLE"],
	["battlefield_lifesaver", "THE WOLF"],
	["hippopotamus_heavy_gunner", "THE HIPPOPOTAMUS"],
	["savanna_signal_scout", "THE GIRAFFE"],
	["serpent_sniper", "THE SERPENT"],
	["war_ram", "THE RAM"],
	["cyber_mule_artillery", "THE MULES"],
	["semi_futuristic_pair", "THE BISON"],
]
const HERO_START := 84.0
const HERO_END := 124.0

## [start, end, text]
const CARDS := [
	[3.0, 9.0, "They came from beyond the stars."],
	[10.0, 15.5, "For a generation, humanity fought back."],
	[17.5, 23.0, "We lost our cities. We lost our children."],
	[24.0, 29.5, "We lost the war."],
	[31.0, 36.5, "Humanity stood at the edge of extinction."],
	[37.5, 41.5, "And we accepted our end."],
	[43.5, 49.0, "With our final breath, we made one last choice."],
	[50.0, 57.0, "We gave the key to our mind\nto the life of Earth."],
	[59.0, 64.0, "This was never only our fight."],
	[65.0, 69.5, "This is OUR planet."],
	[71.0, 77.5, "And life on Earth\nwill not go quietly."],
	[92.0, 96.0, "They took up our tools."],
	[104.0, 108.0, "They carry our reason."],
	[116.0, 120.5, "They fight as we always fought."],
	[126.0, 131.0, "We are them."],
	[132.0, 138.0, "They are OUR last hope."],
	[141.0, 145.5, "They came for our world one last time."],
	[147.0, 151.5, "Shoulder to shoulder.  No retreat."],
	[152.3, 155.8, "FOR EARTH!"],
	[175.0, 180.5, "We were never afraid."],
	[193.0, 197.5, "This is OUR planet."],
]
const TITLE_IN := 199.0

var t := 0.0
var _movie := false
var _shots: Array = []
var _shot_idx := -1
var _camera: Camera3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _ash: CPUParticles3D
var _motes: CPUParticles3D
var _music: AudioStreamPlayer
var _hero_nodes: Array = []
var _fires: Array = []
var _eyes: Array = []  # [node, open_time, material]
var _helix: Node3D
var _streams: CPUParticles3D
var _ground_ring: MeshInstance3D
var _ring: MeshInstance3D
var _ships: Array = []
var _talons: Array = []
var _army: Array = []  # [node, flying, charges] for the battle
var _battle: IntroBattle
var _particles: Array = []

var _black: ColorRect
var _white: ColorRect
var _card: Label
var _caption: Label
var _title: Label
var _subtitle: Label


func _ready() -> void:
	if GameConfig.autotest != "":
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return
	_movie = "--write-movie" in OS.get_cmdline_args()
	# `-- --intro-start=SECONDS` starts mid-way (for previewing a shot)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--intro-start="):
			t = arg.get_slice("=", 1).to_float()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_environment()
	_build_ground()
	_build_city()
	_build_memorial()
	_build_genome()
	_build_forest()
	_build_gallery()
	_build_ridge()
	_build_citadel()
	_battle = IntroBattle.new()
	add_child(_battle)
	_battle.setup(_army, CITADEL, _ring)
	_build_particles()
	_particles = [_ash, _motes]
	for n in find_children("*", "CPUParticles3D", true, false):
		if not n in _particles:
			_particles.append(n)
	_build_overlay()
	_build_shots()
	_camera = Camera3D.new()
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	_music = AudioStreamPlayer.new()
	_music.stream = load(THEME)
	add_child(_music)
	_music.play(t)
	_update(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _movie:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_finish()


func _finish() -> void:
	set_process(false)
	if _movie:
		get_tree().quit()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _process(delta: float) -> void:
	t += delta
	if t >= LENGTH:
		_finish()
		return
	_update(delta)


# ================================================================ timeline

func _update(delta: float) -> void:
	_battle.update(t)
	var rate: float = IntroBattle.time_rate(t)
	for p in _particles:
		p.speed_scale = rate
	_update_camera()
	_update_props(delta)
	_update_overlay()


func _update_camera() -> void:
	var idx := _shots.size() - 1
	for i in _shots.size():
		if t < _shots[i].end:
			idx = i
			break
	var s: Dictionary = _shots[idx]
	if idx != _shot_idx:
		_shot_idx = idx
		_apply_preset(s.preset)
	var u := clampf((t - s.start) / (s.end - s.start), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) if s.get("ease", true) else u
	var pos: Vector3 = s.from.lerp(s.to, u)
	var look: Vector3 = s.look_from.lerp(s.look_to, u)
	if s.hero:
		var h: Vector3 = _battle.hero_position(IntroBattle.battle_time(t))
		pos += h
		look += h
	_camera.fov = lerpf(s.get("fov_from", 50.0), s.get("fov_to", s.get("fov_from", 50.0)), u)
	# impact shake on the big hits
	var shake := 0.0
	for hit in [80.0, 112.0, 136.0, 160.0, 172.5, 189.4]:
		if t > hit and t < hit + 1.2:
			shake = maxf(shake, (1.0 - (t - hit) / 1.2) * 0.35)
	pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake
	_camera.global_position = pos
	_camera.look_at(look, Vector3.UP)


## `hero` shots are relative to the lead bear's position during the battle.
func _shot(start: float, end: float, from: Vector3, to: Vector3, look_from: Vector3, look_to: Vector3,
		preset: String, fov_from := 50.0, fov_to := -1.0, hero := false) -> void:
	_shots.append({"start": start, "end": end, "from": from, "to": to, "look_from": look_from,
			"look_to": look_to, "preset": preset, "fov_from": fov_from, "fov_to": fov_to if fov_to > 0 else fov_from,
			"hero": hero})


func _build_shots() -> void:
	var m := MEMORIAL
	# Act I: the fall
	_shot(0.0, 16.0, CITY + Vector3(0, 34, 170), CITY + Vector3(0, 24, 40),
			CITY + Vector3(0, 40, 0), CITY + Vector3(0, 70, -140), "night", 55.0, 48.0)
	_shot(16.0, 30.0, m + Vector3(-26, 1.3, -14), m + Vector3(14, 1.1, -14),
			m + Vector3(-12, 0.8, 10), m + Vector3(22, 0.8, 10), "memorial", 45.0)
	_shot(30.0, 42.0, m + Vector3(0.5, 1.7, -4.0), m + Vector3(0.15, 1.25, -1.6),
			m + Vector3(0, 0.9, 0), m + Vector3(0, 1.0, 0), "memorial", 40.0, 34.0)
	# Act II: the gift
	_shot(42.0, 58.0, m + Vector3(-10, 2.0, -9), m + Vector3(14, 11.0, -12),
			m + Vector3(0, 3.0, 0), m + Vector3(0, 8.0, 0), "genome", 50.0, 58.0)
	_shot(58.0, 70.0, FOREST + Vector3(0, 2.0, 62), FOREST + Vector3(0, 2.0, 42),
			FOREST + Vector3(0, 2.0, 0), FOREST + Vector3(0, 2.2, 0), "eyes", 50.0, 46.0)
	_shot(70.0, 80.0, FOREST + Vector3(0, 3.3, 30), FOREST + Vector3(0, 3.55, 9),
			FOREST + Vector3(0, 3.5, 0), FOREST + Vector3(0, 3.6, 0), "eyes", 45.0, 30.0)
	# Act III: the rise
	_shot(80.0, HERO_START, RIDGE + Vector3(10, 9.2, 42), RIDGE + Vector3(4, 10.5, 30),
			CITADEL + Vector3(0, 40, 0), CITADEL + Vector3(0, 55, 0), "dawn", 50.0, 44.0)
	var dt := (HERO_END - HERO_START) / HEROES.size()
	for i in HEROES.size():
		var node: Node3D = _hero_nodes[i]
		var size := _aabb_size(node)
		var base := node.global_position
		var focus := base + Vector3.UP * size.y * 0.55
		var r := maxf(maxf(size.y, size.x * 0.75), size.z * 0.6) * 1.6 + 1.2
		var side := 1.0 if i % 2 == 0 else -1.0
		var a0 := deg_to_rad(-28.0 * side)
		var a1 := deg_to_rad(14.0 * side)
		var h0 := size.y * 0.35
		var h1 := size.y * 0.6
		_shot(HERO_START + i * dt, HERO_START + (i + 1) * dt,
				base + Vector3(sin(a0) * r * 1.15, h0, cos(a0) * r * 1.15),
				base + Vector3(sin(a1) * r * 0.95, h1, cos(a1) * r * 0.95),
				focus, focus + Vector3.UP * size.y * 0.05, "dawn", 42.0, 38.0)
	_shot(HERO_END, 140.0, RIDGE + Vector3(0, 10.5, 48), RIDGE + Vector3(0, 48, 75),
			RIDGE + Vector3(0, 12, -80), CITADEL + Vector3(0, 70, 0), "dawn", 48.0, 55.0)
	# Act IV: the last stand
	_shot(140.0, 146.0, Vector3(22, 3.0, -585), Vector3(15, 2.4, -545),
			Vector3(0, 6, -660), Vector3(0, 3, -600), "battle", 38.0, 42.0)
	_shot(146.0, 152.0, Vector3(-30, 9.6, -431), Vector3(24, 9.4, -431),
			Vector3(-22, 9.8, -415), Vector3(30, 9.8, -415), "battle", 34.0)
	_shot(152.0, 156.0, Vector3(34, 3.0, -470), Vector3(30, 3.5, -478),
			Vector3(0, 9, -432), Vector3(0, 6, -450), "battle", 34.0, 40.0)
	_shot(156.0, 160.0, Vector3(44, 3.0, -455), Vector3(42, 3.0, -500),
			Vector3(4, 2.5, -465), Vector3(0, 2.5, -508), "battle", 42.0)
	_shot(160.0, 166.0, Vector3(-9, 2.0, -496), Vector3(-5, 2.4, -503),
			Vector3(0, 2.4, -512), Vector3(1, 2.6, -516), "battle", 32.0, 30.0)
	_shot(166.0, 170.0, Vector3(-40, 12.5, -378), Vector3(-36, 13.5, -386),
			Vector3(-25, 9, -430), Vector3(-10, 20, -520), "battle", 45.0)
	_shot(170.0, 174.0, Vector3(-4, 3.0, -518), Vector3(-8, 3.5, -522),
			Vector3(-42, 20, -562), Vector3(-42, 12, -566), "battle", 48.0)
	_shot(174.0, 182.0, Vector3(4.5, 1.5, 4.0), Vector3(-4.0, 2.2, 3.5),
			Vector3(0, 1.4, 0), Vector3(0, 1.5, 0), "battle", 36.0, 32.0, true)
	_shot(182.0, 188.0, Vector3(-62, 16, -478), Vector3(-36, 24, -540),
			Vector3(0, 3, -520), Vector3(0, 18, -640), "battle", 50.0)
	_shot(188.0, 192.0, Vector3(10, 18, -585), Vector3(6, 22, -592),
			CITADEL + Vector3(0, 110, 0), CITADEL + Vector3(0, 80, 0), "battle", 52.0)
	_shot(192.0, 198.0, Vector3(1.5, 0.9, -5.0), Vector3(0.8, 1.6, -4.0),
			Vector3(0, 1.7, 0), Vector3(0, 1.9, 0), "victory", 40.0, 36.0, true)
	_shot(198.0, LENGTH, Vector3(28, 12, -655), Vector3(40, 26, -680),
			Vector3(0, 4, -600), Vector3(0, 10, -600), "victory", 50.0, 55.0)


func _update_props(delta: float) -> void:
	# keep weather around the camera
	_ash.global_position = _camera.global_position
	_motes.global_position = _camera.global_position
	for f in _fires:
		f.light_energy = f.get_meta("base") * randf_range(0.7, 1.15)
	for s in _ships:
		s.visible = t < 190.0
		s.position.x += delta * s.get_meta("drift")
		for beam in s.get_meta("beams"):
			beam.scale.x = 1.0 + sin(t * 9.0 + s.position.x) * 0.25
			beam.scale.z = beam.scale.x
	_ring.rotation.y += delta * 0.08
	for tal in _talons:
		tal.position.y = tal.get_meta("y") + sin(t * 1.4 + tal.position.x) * 0.4

	# Act II genome: the helix rises from the memorial, then light pours out across the land.
	var rise := smoothstep(43.0, 50.0, t)
	_helix.visible = t > 42.5 and t < 60.0
	_helix.scale = Vector3(1, maxf(rise, 0.001), 1)
	_helix.rotation.y = t * 0.6
	_streams.emitting = t > 49.5 and t < 57.5
	var spread := smoothstep(50.0, 58.0, t)
	_ground_ring.visible = t > 49.5 and t < 60.0
	_ground_ring.scale = Vector3(1, 0.02, 1) * maxf(spread * 90.0, 0.01)
	_ground_ring.scale.y = 0.05

	# eyes open one by one in the dark, and blaze at the climax
	var flare := 1.0 + smoothstep(73.0, 78.4, t) * 3.0
	for e in _eyes:
		var open := smoothstep(e[1], e[1] + 0.35, t)
		e[0].scale = Vector3(1, maxf(open, 0.02), 1)
		e[0].visible = open > 0.0
		e[2].emission_energy_multiplier = 4.0 * flare * open


func _update_overlay() -> void:
	# black: fade in, dips between shots, silence before the reveal, title dim, fade out
	var a := 1.0 - smoothstep(0.0, 2.5, t)
	for c in [16.0, 30.0, 42.0, 58.0]:
		a = maxf(a, 1.0 - absf(t - c) / 0.5)
	if t > 78.5 and t < 80.0:
		a = 1.0
	a = maxf(a, 1.0 - absf(t - HERO_END) / 0.4)
	a = maxf(a, 0.5 * smoothstep(TITLE_IN - 1.0, TITLE_IN + 1.5, t))
	a = maxf(a, smoothstep(LENGTH - 2.5, LENGTH - 0.3, t))
	_black.color.a = clampf(a, 0.0, 1.0)
	var w := 0.0
	for f in [[80.0, 0.8], [160.0, 0.35], [189.4, 1.4]]:
		if t >= f[0]:
			w = maxf(w, 1.0 - (t - f[0]) / f[1])
	_white.color.a = clampf(w, 0.0, 1.0)

	var text := ""
	var alpha := 0.0
	for c in CARDS:
		if t >= c[0] and t < c[1]:
			text = c[2]
			alpha = minf(smoothstep(c[0], c[0] + 0.8, t), 1.0 - smoothstep(c[1] - 0.8, c[1], t))
	_card.text = text
	_card.modulate.a = alpha
	_card.add_theme_font_size_override("font_size", 72 if text == "FOR EARTH!" else 40)
	var hero_section := t >= HERO_START and t < HERO_END
	_card.anchor_top = 0.13 if hero_section else 0.62
	_card.anchor_bottom = 0.3 if hero_section else 0.86

	var cap := ""
	var cap_a := 0.0
	if t >= HERO_START and t < HERO_END:
		var dt := (HERO_END - HERO_START) / HEROES.size()
		var i := int((t - HERO_START) / dt)
		var s := HERO_START + i * dt
		cap = HEROES[i][1]
		cap_a = minf(smoothstep(s + 0.15, s + 0.6, t), 1.0 - smoothstep(s + dt - 0.4, s + dt - 0.05, t))
	_caption.text = cap
	_caption.modulate.a = cap_a

	_title.modulate.a = minf(smoothstep(TITLE_IN, TITLE_IN + 2.5, t), 1.0 - smoothstep(LENGTH - 3.0, LENGTH - 1.0, t))
	_subtitle.modulate.a = minf(smoothstep(TITLE_IN + 2.5, TITLE_IN + 4.5, t), 1.0 - smoothstep(LENGTH - 3.0, LENGTH - 1.0, t))


# ================================================================ lighting presets

func _apply_preset(p: String) -> void:
	var night := p in ["night", "memorial"]
	_ash.emitting = night or p == "genome"
	_motes.emitting = p in ["dawn", "battle", "victory"]
	_fill.visible = p in ["dawn", "battle", "victory"]
	_env.adjustment_saturation = 0.72 if p == "battle" else 1.05
	_env.adjustment_contrast = 1.32 if p == "battle" else 1.1
	match p:
		"night", "memorial":
			_sky.sky_top_color = Color(0.02, 0.012, 0.015)
			_sky.sky_horizon_color = Color(0.16, 0.06, 0.035)
			_sky.ground_horizon_color = Color(0.08, 0.035, 0.02)
			_sky.ground_bottom_color = Color(0.02, 0.01, 0.01)
			_sun.light_color = Color(1.0, 0.35, 0.18)
			_sun.light_energy = 0.35
			_sun.basis = Basis.looking_at(Vector3(0.3, -0.25, -1).normalized())
			_env.ambient_light_energy = 0.25
			_env.fog_light_color = Color(0.07, 0.04, 0.035)
			_env.fog_density = 0.006 if p == "night" else 0.012
			_env.tonemap_exposure = 1.0
		"genome":
			_sky.sky_top_color = Color(0.0, 0.005, 0.02)
			_sky.sky_horizon_color = Color(0.04, 0.06, 0.12)
			_sky.ground_horizon_color = Color(0.03, 0.04, 0.08)
			_sky.ground_bottom_color = Color(0, 0, 0)
			_sun.light_energy = 0.05
			_env.ambient_light_energy = 0.15
			_env.fog_light_color = Color(0.03, 0.04, 0.08)
			_env.fog_density = 0.02
		"eyes":
			_sky.sky_top_color = Color(0, 0, 0)
			_sky.sky_horizon_color = Color(0.01, 0.01, 0.015)
			_sky.ground_horizon_color = Color(0, 0, 0)
			_sky.ground_bottom_color = Color(0, 0, 0)
			_sun.light_energy = 0.0
			_env.ambient_light_energy = 0.02
			_env.fog_light_color = Color(0, 0, 0)
			_env.fog_density = 0.06
		"dawn", "battle", "victory":
			_sky.sky_top_color = Color(0.22, 0.38, 0.66)
			_sky.sky_horizon_color = Color(1.0, 0.6, 0.32)
			_sky.ground_horizon_color = Color(0.65, 0.42, 0.3)
			_sky.ground_bottom_color = Color(0.15, 0.12, 0.1)
			_sun.light_color = Color(1.0, 0.74, 0.48)
			_sun.light_energy = 1.5
			# low sun behind the citadel, so the army faces into the light
			_sun.basis = Basis.looking_at(Vector3(0.12, -0.11, 1).normalized())
			_env.ambient_light_energy = 0.4
			_env.fog_light_color = Color(0.72, 0.5, 0.36)
			_env.fog_density = 0.0022
			_env.tonemap_exposure = 0.8
			if p == "battle":  # dusty, bleached, high contrast
				_env.fog_light_color = Color(0.62, 0.46, 0.34)
				_env.fog_density = 0.0045
			elif p == "victory":
				_sun.light_energy = 1.9
				_env.tonemap_exposure = 0.9


# ================================================================ sets

func _build_environment() -> void:
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 8.0
	_sky.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 0.9
	_env.fog_enabled = true
	_env.fog_aerial_perspective = 0.5
	_env.ssao_enabled = true
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.1
	_env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.light_color = Color(0.75, 0.82, 1.0)
	_fill.light_energy = 0.7
	_fill.basis = Basis.looking_at(Vector3(-0.3, -0.4, -1).normalized())
	add_child(_fill)


func _build_ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	g.mesh = pm
	g.material_override = Mats.ground()
	add_child(g)


func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var concrete := Mats.dark_stone()
	for i in 170:
		var p := Vector3(rng.randf_range(-170, 170), 0, rng.randf_range(-220, 150)) + CITY
		if absf(p.x) < 14:
			continue  # flight corridor
		var h := rng.randf_range(12, 75)
		var w := rng.randf_range(8, 20)
		var b := Mats.box_mesh(Vector3(w, h, rng.randf_range(8, 20)), p + Vector3(0, h * 0.5, 0), concrete)
		b.rotation.y = rng.randf() * 0.2
		add_child(b)
		if rng.randf() < 0.45:  # broken top
			var slab := Mats.box_mesh(Vector3(w * 0.9, 1.5, w * 0.5), p + Vector3(0, h + 0.5, 0), concrete)
			slab.rotation = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			add_child(slab)
	for i in 16:
		_fire(CITY + Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-150, 120)), rng.randf_range(3, 7))
	for i in 6:
		var pos := CITY + Vector3(rng.randf_range(-110, 110), rng.randf_range(80, 120), rng.randf_range(-260, -40))
		_alien_ship(pos, rng.randf_range(1.0, 2.0), i < 3)
	_alien_ship(CITY + Vector3(0, 190, -420), 7.0, false)


func _fire(pos: Vector3, size: float) -> void:
	var flames := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.5, 0.15)
	q.material = m
	flames.mesh = q
	flames.amount = 30
	flames.lifetime = 1.2
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = size * 0.4
	flames.direction = Vector3.UP
	flames.spread = 15.0
	flames.initial_velocity_min = size * 0.6
	flames.initial_velocity_max = size * 1.2
	flames.gravity = Vector3.ZERO
	flames.scale_amount_min = size * 0.6
	flames.scale_amount_max = size * 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.7, 0.3, 1.0))
	g.set_color(1, Color(0.6, 0.1, 0.02, 0.0))
	flames.color_ramp = g
	flames.position = pos
	add_child(flames)
	var smoke := CPUParticles3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(1, 1)
	sq.material = Combat._smoke_material()
	smoke.mesh = sq
	smoke.amount = 20
	smoke.lifetime = 6.0
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 5.0
	smoke.gravity = Vector3(0.6, 0.4, 0)
	smoke.scale_amount_min = size * 1.5
	smoke.scale_amount_max = size * 3.0
	var sg := Gradient.new()
	sg.set_color(0, Color(0.12, 0.1, 0.09, 0.6))
	sg.set_color(1, Color(0.12, 0.1, 0.09, 0.0))
	smoke.color_ramp = sg
	smoke.position = pos + Vector3.UP * size
	add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.omni_range = size * 7.0
	light.set_meta("base", 2.5)
	light.position = pos + Vector3.UP * size * 0.8
	add_child(light)
	_fires.append(light)


func _alien_ship(pos: Vector3, s: float, beam: bool) -> void:
	var ship := Node3D.new()
	ship.position = pos
	ship.scale = Vector3.ONE * s
	ship.set_meta("drift", randf_range(-1.5, 1.5))
	var hull := Mats.flat(Color(0.05, 0.05, 0.06), 0.9, 0.3)
	var red := Mats.glow(Color(1.0, 0.12, 0.08), 6.0)
	ship.add_child(Mats.box_mesh(Vector3(10, 2.2, 26), Vector3.ZERO, hull))
	var w1 := Mats.box_mesh(Vector3(30, 0.8, 9), Vector3(0, -0.3, 4), hull)
	ship.add_child(w1)
	for x in [-14.0, 14.0]:
		ship.add_child(Mats.box_mesh(Vector3(2, 5, 7), Vector3(x, 1.5, 5), hull))
	ship.add_child(Mats.box_mesh(Vector3(28, 0.2, 0.4), Vector3(0, -0.8, 8.6), red))
	ship.add_child(Mats.box_mesh(Vector3(0.4, 0.3, 24), Vector3(0, 1.2, 0), red))
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 2.2
	core.mesh = sm
	core.material_override = red
	core.position = Vector3(0, -1.2, 0)
	ship.add_child(core)
	var beams := []
	if beam:
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bm.albedo_color = Color(1.0, 0.15, 0.08, 0.6)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var h := pos.y / s
		var b := Mats.cylinder_mesh(0.8, h, Vector3(0, -h * 0.5, 0), bm, 10)
		ship.add_child(b)
		beams.append(b)
		var hit := OmniLight3D.new()
		hit.light_color = Color(1, 0.2, 0.1)
		hit.light_energy = 6.0
		hit.omni_range = 40.0
		hit.position = Vector3(0, -h + 2.0 / s, 0)
		ship.add_child(hit)
	ship.set_meta("beams", beams)
	add_child(ship)
	_ships.append(ship)


func _build_memorial() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var metal := Mats.flat(Color(0.12, 0.12, 0.12), 0.7, 0.5)
	var helmet_mat := Mats.flat(Color(0.22, 0.24, 0.2), 0.3, 0.7)
	for x in range(-36, 37, 3):
		for z in range(-4, 40, 4):
			if x == 0 and z == 0:
				continue
			var p := MEMORIAL + Vector3(x + rng.randf_range(-0.6, 0.6), 0, z + rng.randf_range(-0.6, 0.6))
			_grave(p, Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12)), metal, helmet_mat)
	_grave(MEMORIAL, Vector3(0, 0.3, 0), metal, helmet_mat)
	for i in 7:
		_fire(MEMORIAL + Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(45, 70)), rng.randf_range(3, 6))
	# broken walls framing the field
	for i in 10:
		var p := MEMORIAL + Vector3(rng.randf_range(-50, 50), 0, rng.randf_range(42, 60))
		var h := rng.randf_range(3, 9)
		add_child(Mats.box_mesh(Vector3(rng.randf_range(4, 10), h, 0.8), p + Vector3(0, h * 0.5, 0), Mats.dark_stone()))


func _grave(p: Vector3, rot: Vector3, metal: Material, helmet_mat: Material) -> void:
	var g := Node3D.new()
	g.position = p
	g.rotation = rot
	g.add_child(Mats.box_mesh(Vector3(0.06, 1.05, 0.09), Vector3(0, 0.45, 0), metal))  # rifle, muzzle down
	g.add_child(Mats.box_mesh(Vector3(0.1, 0.3, 0.06), Vector3(0, 0.85, 0.03), metal))  # stock
	g.add_child(Mats.box_mesh(Vector3(0.05, 0.12, 0.18), Vector3(0, 0.5, -0.08), metal))  # magazine
	var helmet := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	hm.height = 0.16
	hm.is_hemisphere = true
	helmet.mesh = hm
	helmet.material_override = helmet_mat
	helmet.position = Vector3(0, 1.0, 0)
	helmet.rotation.z = 0.15
	g.add_child(helmet)
	add_child(g)


func _build_genome() -> void:
	_helix = Node3D.new()
	_helix.position = MEMORIAL
	add_child(_helix)
	var gold := Mats.glow(Color(1.0, 0.78, 0.35), 5.0)
	var cyan := Mats.glow(Color(0.4, 0.85, 1.0), 5.0)
	var rung := Mats.glow(Color(0.9, 0.95, 1.0), 2.0)
	var count := 46
	for i in count:
		var y := 1.0 + i * 0.32
		var a := i * 0.42
		for k in 2:
			var ang := a + k * PI
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.32
			sm.radial_segments = 8
			sm.rings = 4
			s.mesh = sm
			s.material_override = gold if k == 0 else cyan
			s.position = Vector3(cos(ang) * 1.3, y, sin(ang) * 1.3)
			_helix.add_child(s)
		if i % 2 == 0:
			var r := Mats.box_mesh(Vector3(2.6, 0.05, 0.05), Vector3(0, y, 0), rung)
			r.rotation.y = -a
			_helix.add_child(r)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.55)
	l.light_energy = 6.0
	l.omni_range = 30.0
	l.position = Vector3(0, 6, 0)
	_helix.add_child(l)

	_streams = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.8, 0.45)
	q.material = m
	_streams.mesh = q
	_streams.amount = 900
	_streams.lifetime = 6.0
	_streams.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_streams.emission_sphere_radius = 2.0
	_streams.direction = Vector3(1, 0.1, 0)
	_streams.spread = 180.0
	_streams.flatness = 0.85
	_streams.initial_velocity_min = 8.0
	_streams.initial_velocity_max = 22.0
	_streams.gravity = Vector3(0, -0.3, 0)
	_streams.position = MEMORIAL + Vector3(0, 4, 0)
	_streams.emitting = false
	add_child(_streams)

	_ground_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.96
	tm.outer_radius = 1.0
	tm.rings = 96
	tm.ring_segments = 3
	_ground_ring.mesh = tm
	_ground_ring.material_override = Mats.glow(Color(1.0, 0.8, 0.45), 5.0)
	_ground_ring.position = MEMORIAL + Vector3(0, 0.1, 0)
	_ground_ring.visible = false
	add_child(_ground_ring)


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var bark := Mats.flat(Color(0.03, 0.03, 0.03), 0.0, 1.0)
	for i in 140:
		var p := FOREST + Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-70, 30))
		if absf(p.x - FOREST.x) < 4 and p.z > FOREST.z - 5:
			continue
		var h := rng.randf_range(8, 18)
		add_child(Mats.cylinder_mesh(0.35, h, p + Vector3(0, h * 0.5, 0), bark, 6))
	# pairs of eyes: [offset, separation, size, open time]
	var eyes := []
	for i in 26:
		var y := rng.randf_range(0.5, 4.5)
		eyes.append([Vector3(rng.randf_range(-22, 22), y, rng.randf_range(-12, 18)),
				0.12 + y * 0.05, 0.035 + y * 0.008, 59.5 + i * 0.36])
	eyes.append([Vector3(0, 3.6, 0), 0.9, 0.12, 71.0])  # the elephant
	for e in eyes:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var warm := rng.randf() < 0.6
		mat.albedo_color = Color(1.0, 0.75, 0.3) if warm else Color(0.6, 0.95, 0.5)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		var pair := Node3D.new()
		pair.position = FOREST + e[0]
		pair.rotation.y = rng.randf_range(-0.3, 0.3)
		for side in [-0.5, 0.5]:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = e[2]
			sm.height = e[2] * 1.3
			s.mesh = sm
			s.material_override = mat
			s.position = Vector3(side * e[1], 0, 0)
			pair.add_child(s)
		pair.visible = false
		add_child(pair)
		_eyes.append([pair, e[3], mat])


func _load_model(folder: String) -> Node3D:
	return (load("res://assets/units/%s/%s.glb" % [folder, folder]) as PackedScene).instantiate()


func _build_gallery() -> void:
	for i in HEROES.size():
		var base := GALLERY + Vector3(-i * 60.0, 0, 0)
		add_child(Mats.box_mesh(Vector3(9, 1.0, 9), base + Vector3(0, 0.5, 0), Mats.dark_stone()))
		var m := _load_model(HEROES[i][0])
		m.position = base + Vector3(0, 1.0, 0)
		if HEROES[i][0] == "sky_talon_battalion":
			m.position.y += 2.5
			m.set_meta("y", m.position.y)
			_talons.append(m)
		add_child(m)
		_hero_nodes.append(m)
		var rim := OmniLight3D.new()
		rim.light_color = Color(1.0, 0.8, 0.55)
		rim.light_energy = 3.0
		rim.omni_range = 14.0
		rim.position = base + Vector3(2.5, 5.0, -5.0)
		add_child(rim)


func _build_ridge() -> void:
	add_child(Mats.box_mesh(Vector3(260, 8, 70), RIDGE + Vector3(0, 4, 0), Mats.dark_stone()))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var top := RIDGE.y + 8.0
	# heavies in the middle, infantry around them, flyers overhead
	var layout := [
		["war_elephant_sentinel", Vector3(0, 0, -6)], ["armored_rhino_unit", Vector3(-12, 0, -4)],
		["hippopotamus_heavy_gunner", Vector3(12, 0, -4)], ["cyber_mule_artillery", Vector3(-30, 0, 6)],
		["semi_futuristic_pair", Vector3(30, 0, 6)], ["savanna_signal_scout", Vector3(-22, 0, 2)],
	]
	var infantry := ["cyber_bear_commando", "kangaroo_commando", "armored_lioness_unit", "night_ops_chimpanzee",
			"battlefield_lifesaver", "war_ram", "serpent_sniper"]
	for i in 34:
		var x := rng.randf_range(-48, 48)
		var z := rng.randf_range(-16, -2)
		if absf(x) < 18 and z < -2:
			z = rng.randf_range(-22, -14)
		layout.append([infantry[i % infantry.size()], Vector3(x, 0, z)])
	layout.append(["cyber_bear_commando", Vector3(2, 0, -24), true])  # the lead bear, front and center
	for entry in layout:
		var m := _load_model(entry[0])
		m.position = RIDGE + entry[1] + Vector3(0, top, 0)
		m.rotation.y = PI + rng.randf_range(-0.15, 0.15)  # face the citadel
		if entry.size() > 2:
			m.set_meta("hero", true)
			m.rotation.y = PI
		add_child(m)
		_army.append([m, false, not entry[0] in ["cyber_mule_artillery", "semi_futuristic_pair"]])
	for i in 6:
		var m := _load_model("sky_talon_battalion")
		m.position = RIDGE + Vector3(rng.randf_range(-40, 40), top + rng.randf_range(10, 18), rng.randf_range(-20, 0))
		m.set_meta("y", m.position.y)
		m.rotation.y = PI
		add_child(m)
		_army.append([m, true, true])


func _build_citadel() -> void:
	var hull := Mats.flat(Color(0.05, 0.05, 0.07), 0.9, 0.25)
	var red := Mats.glow(Color(1.0, 0.1, 0.06), 8.0)
	var c := CITADEL
	var spires := [[Vector3(0, 0, 0), 24.0, 190.0], [Vector3(-70, 0, 30), 12.0, 110.0], [Vector3(75, 0, 20), 14.0, 125.0],
			[Vector3(-140, 0, -20), 9.0, 80.0], [Vector3(150, 0, -30), 10.0, 90.0]]
	for s in spires:
		var cm := CylinderMesh.new()
		cm.bottom_radius = s[1]
		cm.top_radius = s[1] * 0.08
		cm.height = s[2]
		cm.radial_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = hull
		mi.position = c + s[0] + Vector3(0, s[2] * 0.5, 0)
		add_child(mi)
		for k in 4:
			var y: float = s[2] * (0.25 + k * 0.18)
			var rr: float = lerpf(s[1], s[1] * 0.08, y / s[2]) + 0.3
			var band := Mats.cylinder_mesh(rr, 1.2, c + s[0] + Vector3(0, y, 0), red, 6)
			add_child(band)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 55.0
	tm.outer_radius = 60.0
	tm.rings = 64
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.material_override = hull
	_ring.position = c + Vector3(0, 130, 0)
	_ring.rotation.x = 0.12
	add_child(_ring)
	for k in 6:
		var a := k * TAU / 6.0
		var light := Mats.box_mesh(Vector3(4, 2, 4), Vector3(cos(a) * 57.5, 0, sin(a) * 57.5), red)
		_ring.add_child(light)
	for i in 5:
		_alien_ship(c + Vector3(randf_range(-160, 160), randf_range(90, 170), randf_range(-60, 60)), randf_range(1.5, 3.0), false)


func _build_particles() -> void:
	_ash = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.6, 0.58, 0.55)
	q.material = m
	_ash.mesh = q
	_ash.amount = 700
	_ash.lifetime = 10.0
	_ash.preprocess = 10.0
	_ash.local_coords = false
	_ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ash.emission_box_extents = Vector3(30, 14, 30)
	_ash.direction = Vector3(0.3, -1, 0.1)
	_ash.spread = 25.0
	_ash.initial_velocity_min = 0.5
	_ash.initial_velocity_max = 1.4
	_ash.gravity = Vector3(0, -0.2, 0)
	add_child(_ash)

	_motes = _ash.duplicate() as CPUParticles3D
	var mq := QuadMesh.new()
	mq.size = Vector2(0.06, 0.06)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.albedo_color = Color(1.0, 0.8, 0.5)
	mq.material = mm
	_motes.mesh = mq
	_motes.amount = 300
	_motes.direction = Vector3(0.2, 0.3, 0)
	_motes.gravity = Vector3(0, 0.05, 0)
	add_child(_motes)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := UIKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.anchor_bottom = 0.11 if top else 1.0
		bar.anchor_top = 0.0 if top else 0.89
		bar.offset_top = 0
		bar.offset_bottom = 0
		root.add_child(bar)

	var spaced := FontVariation.new()
	spaced.base_font = ThemeDB.fallback_font
	spaced.spacing_glyph = 3
	var wide := FontVariation.new()
	wide.base_font = ThemeDB.fallback_font
	wide.spacing_glyph = 14
	wide.variation_embolden = 0.6

	_card = _overlay_label(root, spaced, 40, Color(0.95, 0.94, 0.9))
	_card.anchor_top = 0.62
	_card.anchor_bottom = 0.86

	_caption = _overlay_label(root, wide, 40, Color(1.0, 0.85, 0.55))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_caption.anchor_left = 0.07
	_caption.anchor_top = 0.74
	_caption.anchor_bottom = 0.86

	_title = _overlay_label(root, wide, 96, Color(1.0, 0.95, 0.85))
	_title.text = "STRONGHOLD ASSAULT"
	_title.anchor_top = 0.36
	_title.anchor_bottom = 0.52
	_subtitle = _overlay_label(root, spaced, 30, Color(1.0, 0.82, 0.55))
	_subtitle.text = "This is OUR Earth.  This is where we make our stand."
	_subtitle.anchor_top = 0.53
	_subtitle.anchor_bottom = 0.62

	_white = UIKit.full_rect(ColorRect.new()) as ColorRect
	_white.color = Color(1, 0.97, 0.9, 0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_white)
	_black = UIKit.full_rect(ColorRect.new()) as ColorRect
	_black.color = Color(0, 0, 0, 1)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)
	# keep text above the fades
	for l in [_card, _caption, _title, _subtitle]:
		root.move_child(l, -1)


func _overlay_label(root: Control, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_left = 0.05
	l.anchor_right = 0.95
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	root.add_child(l)
	return l


static func _aabb_size(node: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (node.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * b
		box = b if first else box.merge(b)
		first = false
	return box.size
