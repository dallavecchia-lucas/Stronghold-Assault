extends Node3D
## The chimps' swing through the trees and the rafts folding out and coming apart, as a video, on the Jungle Keep
## (media/chimp_swing_rafts.mp4).
##
##   godot --path game --resolution 1280x720 --write-movie video.avi --fixed-fps 30 res://scenes/dev/raft_chimp_video.tscn
##
## A Night Ops Chimp in the forest south of the Keep: standing, then sent north, it leaps up into the trees and swings
## through them, and drops back down where they end to run on into the clearing. Then on the main river's south bank
## (the bridge showcase's stretch): a hippo with its raft folded on its back and an elephant with its own hung on its
## rump; riders are sent across, and each raft is tipped off behind its carrier, swings open and blows up its floats;
## the riders climb on; over the river (4x); on the north bank they hop off and the hippo's raft comes apart, its
## floats going flat, and fades away, a fresh pack showing on the hippo's back.

## The chimp's way: from the forest north into the Keep's clearing (chimp_showcase's).
const FROM_Z := [400.0, 380.0, 360.0]
const TO_Z := 220.0
const XS := [-100.0, 100.0, -150.0, 150.0]
## The river (main): the south bank where the carriers stand, the north bank they go to.
const SOUTH := Vector3(-322.0, 0.0, 509.0)
const NORTH := Vector3(-322.0, 0.0, 420.0)

var level: JungleLevel
var commander: AttackerCommander
var controller: AttackerController
var cam: Camera3D
var _caption: Label
## The camera follows `_follow`: at `_eye`, looking at `_at` (in its frame, turned with it; the look-at lifted with a
## swinging chimp).
var _follow: Node3D
var _eye := Vector3(6.0, 2.0, 0.0)
var _at := Vector3(0.0, 1.0, 0.0)
var _look := Vector3.ZERO
var _snap := true


func _ready() -> void:
	seed(3)
	RenderingServer.render_loop_enabled = false  # nothing to see while the map loads
	GameConfig.map = "jungle"
	GameConfig.player_side = GameConfig.PlayerSide.ATTACKER
	level = JungleLevel.new()
	add_child(level)
	level.build()
	for s in level.stations + level.aa_turrets:
		if s is CollisionObject3D:
			s.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		s.process_mode = Node.PROCESS_MODE_DISABLED
	var units_root := Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	commander = AttackerCommander.new()
	commander.units_root = units_root
	commander.level = level
	commander.spawn_points = level.spawn_points
	commander.spawn_bases = level.spawn_bases
	commander.supply = 100000.0
	add_child(commander)
	controller = AttackerController.new()
	controller.level = level
	controller.commander = commander
	add_child(controller)
	controller.camera_rig.edge_scroll = false
	controller.visible = false
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 700.0
	cam.fov = 50.0
	add_child(cam)
	_build_overlay()
	level.navigation_ready.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	for sun: DirectionalLight3D in level.find_children("*", "DirectionalLight3D", false, false):
		sun.directional_shadow_max_distance = 120.0
	for mmi: MultiMeshInstance3D in get_tree().get_nodes_in_group("flora_batches"):
		if mmi.visibility_range_end > 400.0 or mmi.visibility_range_end == 0.0:
			mmi.visibility_range_end = 400.0
			mmi.visibility_range_end_margin = 40.0
	for l: Label3D in level.find_children("*", "Label3D", true, false):
		l.visible = false
	# The swim links go into the navigation map on its own thread.
	await _until(func(): return RiverCrossing.reaches(self, SOUTH, NORTH, 1 | RiverCrossing.NAV_SWIMMERS), 30.0)
	cam.current = true
	RenderingServer.render_loop_enabled = true
	await _chimp()
	await _rafts()
	_say("", "")
	await _hold(10)
	get_tree().quit()


# ---------------------------------------------------------------- the chimp

func _way() -> Array:
	for z in FROM_Z:
		for x in XS:
			var from := Vector3(x, 0.0, z)
			var to := Vector3(x, 0.0, TO_Z)
			var forest := true
			for k in 6:
				forest = forest and LevelBuilder.in_forest(from + Vector3(0.0, 0.0, -10.0 * k))
			if forest and not LevelBuilder.in_forest(to) and not RiverCrossing.wet(from) and RiverCrossing.reaches(self, from, to):
				return [from, to]
	return []


func _chimp() -> void:
	var way := _way()
	if way.is_empty():
		return
	var chimp := _unit("chimp", way[0])
	_aim(chimp, Vector3(3.2, 1.3, -2.8), Vector3(0.0, 0.9, 0.0))
	_say("Night Ops Chimp", "in the forest: faster than on open ground")
	await _hold(45)
	commander.submit({"type": "move", "units": [chimp.unit_id], "pos": way[1], "attack": false})
	_say("Into the trees", "it leaps up into the branches")
	cam.fov = 36.0
	await _to(Vector3(6.5, 0.8, 1.0), Vector3(0.0, 1.8, -0.8), 30)
	_say("Swinging through the trees", "hand over hand, branch to branch: that's why it's fast in a forest")
	await _hold(80)
	await _to(Vector3(4.0, 0.6, 5.0), Vector3(0.0, 1.9, -1.0), 50)
	await _hold(40)
	await _to(Vector3(-5.5, 0.8, -3.0), Vector3(0.0, 1.8, 0.0), 50)
	await _hold(40)
	await _to(Vector3(6.5, 0.8, 1.0), Vector3(0.0, 1.6, -0.8), 40)
	# On till it is out of the trees for good.
	var out := 0
	for k in 30 * 30:
		await get_tree().process_frame
		out = out + 1 if not LevelBuilder.in_forest(chimp.global_position) else 0
		if out == 1:
			_say("Out of the trees", "it drops down and goes on foot, slower")
		if out > 75:
			break
	_say("", "")
	cam.fov = 50.0
	commander.units.erase(chimp.unit_id)
	chimp.queue_free()


# ---------------------------------------------------------------- the rafts

func _rafts() -> void:
	var hippo := _unit("hippo", SOUTH + Vector3(-4.0, 0, 6.0))
	var jumbo := _unit("elephant", SOUTH + Vector3(9.0, 0, 7.0))
	var riders := [_unit("kangaroo", SOUTH + Vector3(-9.0, 0, 20.0)), _unit("lioness", SOUTH + Vector3(-3.0, 0, 21.0)),
			_unit("giraffe", SOUTH + Vector3(10.0, 0, 21.0))]
	_aim(hippo, Vector3(3.6, 3.4, 4.6), Vector3(0.0, 1.6, 0.0))
	_say("Hippo Heavy Gunner", "its raft folded up on its back")
	await _hold(60)
	_aim(jumbo, Vector3(-4.2, 3.4, 6.5), Vector3(0.0, 2.0, 1.0))
	_say("War Elephant", "its raft hung folded on its rump")
	await _hold(60)
	commander.submit({"type": "move", "units": _ids([hippo, jumbo] + riders), "pos": NORTH, "attack": false})
	_aim(hippo, Vector3(9.0, 5.0, 9.0), Vector3(0.0, 0.5, 4.0))
	_say("Riders coming: the raft is put down", "tipped off behind, it swings open and its floats blow up")
	await _hold(70)
	await _to(Vector3(-8.0, 5.5, 13.0), Vector3(0.0, 0.5, 4.0), 40)
	_say("The riders climb on", "two to a raft, or a giraffe or a rhino alone")
	await _until(func(): return hippo.riders.size() == 2 and jumbo.riders.size() == 1, 20.0)
	await _hold(25)
	_say("Across the river (4x)", "")
	await _to(Vector3(11.0, 7.0, 9.0), Vector3(0.0, 0.0, 3.0), 30)
	Engine.time_scale = 4.0
	await _until(func(): return hippo.is_swimming(), 20.0)
	await _until(func(): return not hippo.is_swimming() and not hippo.in_water(), 60.0)
	Engine.time_scale = 1.0
	_aim(hippo, Vector3(-8.0, 5.0, 11.0), Vector3(0.0, 0.3, 5.0))
	_say("Across: the riders get off", "and the raft comes apart: the floats go flat, the deck falls to pieces")
	var raft: TowPlatform = hippo.platform()
	await _until(func(): return hippo.riders.is_empty(), 20.0)
	# Hold on the pieces where they lie (the hippo walks on).
	var spot := Node3D.new()
	add_child(spot)
	spot.global_transform = raft.global_transform
	_follow = spot
	await _until(func(): return not is_instance_valid(raft) or raft.state == TowPlatform.State.BROKEN, 5.0)
	await _hold(int(TowPlatform.BREAK_TIME * 30.0) + 10)
	_aim(hippo, Vector3(3.6, 3.4, 4.6), Vector3(0.0, 1.6, 0.0))
	_say("A fresh raft", "folded on its back again")
	await _hold(70)


# ---------------------------------------------------------------- camera and helpers

func _process(_delta: float) -> void:
	if not is_instance_valid(_follow):
		return
	var b := Basis(Vector3.UP, _follow.global_rotation.y)
	var lift: float = _follow.swing_lift() if _follow is AttackerUnit else 0.0
	# Up in the trees the camera stays low, looking up at it under the canopy (not up in the leaves with it).
	var want := _follow.global_position + b * _eye + Vector3.UP * lift * 0.3
	var look := _follow.global_position + b * _at + Vector3.UP * lift
	if _snap:
		cam.global_position = want
		_look = look
		_snap = false
	else:
		cam.global_position = cam.global_position.lerp(want, 0.08)
		_look = _look.lerp(look, 0.12)
	cam.look_at(_look)


## Cut to `node`: the camera at `eye`, looking at `at` (its frame).
func _aim(node: Node3D, eye: Vector3, at: Vector3) -> void:
	_follow = node
	_eye = eye
	_at = at
	_snap = true


## Over `frames` frames the camera moves to `eye`, looking at `at`.
func _to(eye: Vector3, at: Vector3, frames: int) -> void:
	var e0 := _eye
	var a0 := _at
	for f in frames:
		var k := smoothstep(0.0, 1.0, (f + 1.0) / frames)
		_eye = e0.lerp(eye, k)
		_at = a0.lerp(at, k)
		await get_tree().process_frame


func _hold(frames: int) -> void:
	for f in frames:
		await get_tree().process_frame


func _until(cond: Callable, seconds: float) -> bool:
	for k in int(seconds * 30.0):
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _unit(type: String, at: Vector3) -> AttackerUnit:
	var id := commander.submit({"type": "spawn", "unit": type, "spawn": 0})
	var u: AttackerUnit = commander.units[id]
	u.global_position = Vector3(at.x, LevelBuilder.ground_height(at) + 0.3, at.z)
	u.rotation.y = 0.0
	return u


func _ids(list: Array) -> Array:
	return list.map(func(u): return u.unit_id)


func _say(title: String, sub: String) -> void:
	_caption.text = title if sub == "" else "%s\n%s" % [title, sub]
	_caption.visible = title != ""


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_caption = UIKit.label("", 24, Color.WHITE)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y = 24
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	layer.add_child(_caption)
