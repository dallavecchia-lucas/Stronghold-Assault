class_name SpireRig
extends "res://scripts/turrets/turret_rig.gd"
## The Sentinel Spire on the roofs (tools/gltf/rig_turrets.py `spire`): a four-cell missile pod between two tall arms.
## The arms turn on the base ring; the pod elevates between them (`pod`).
##
## Each of its four cells (`cell_1..4`) shows the missile in it. launch() fires the next loaded one: the missile is
## gone from its cell, flame stabs out of the cell and the back blast out of the vent behind the pod, with smoke at
## both ends; the pod is thrown back on its trunnion and settles, the arms rock. The emptied cell is reloaded RELOAD s
## later: a new missile is run up from inside the pod to its mouth.

const Flame := preload("res://scripts/vehicles/thruster_flame.gd")
const MODEL := "res://assets/defenses/sentinel_spire/sentinel_spire.glb"
const CELLS := 4
## How long a cell stays empty (s) and how long the new missile takes to run up (s), from how far inside (m).
const RELOAD := 7.0
const RUN_UP := 0.9
const RUN_UP_FROM := 0.45
## The pod's kick (rad, muzzle up: the blast leaves by the back, below the trunnion) and the arms' rock (rad).
const JUMP := deg_to_rad(1.6)
const ROCK := deg_to_rad(0.8)
## How long the launch's flames last (s).
const FLASH_TIME := 0.32
## The pod's travel (rad): it does not go below level, nor up into its own arms' feet.
const DEPRESSION := deg_to_rad(0.0)
const ELEVATION := deg_to_rad(58.0)
## The missile in a cell: its radius and length (m), how far its nose sits back from the cell's mouth.
const MISSILE_RADIUS := 0.048
const MISSILE_LENGTH := 0.62
const MISSILE_SET_BACK := 0.05

## Missiles launched so far.
var launched := 0

var _missiles: Array[Node3D] = []
## Per cell: seconds until it is loaded again (0: loaded).
var _empty: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _next := 0
var _flames: Array = []


func _model_path() -> String:
	return MODEL


func model_height() -> float:
	return 3.0


func _gun_part() -> String:
	return "pod"


func min_pitch(_at_yaw: float) -> float:
	return DEPRESSION


func max_pitch() -> float:
	return ELEVATION


func _setup() -> void:
	var body := Mats.flat(Color(0.2, 0.22, 0.2), 0.5, 0.5)
	var nose := Mats.flat(Color(0.75, 0.16, 0.1), 0.2, 0.5)
	for k in CELLS:
		var cell := part("cell_%d" % (k + 1))
		var m := Node3D.new()
		if cell:
			# The marker's +Z is out of the cell: the missile lies along it, its nose just inside the mouth.
			var tube := Mats.cylinder_mesh(MISSILE_RADIUS, MISSILE_LENGTH, Vector3(0, 0, -MISSILE_LENGTH * 0.5 - 0.12), body, 8)
			tube.rotation.x = PI * 0.5
			m.add_child(tube)
			var tip := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.004
			cone.bottom_radius = MISSILE_RADIUS
			cone.height = 0.12
			cone.radial_segments = 8
			tip.mesh = cone
			tip.material_override = nose
			tip.rotation.x = PI * 0.5
			tip.position.z = -0.06
			m.add_child(tip)
			m.position.z = -MISSILE_SET_BACK
			for mi in m.get_children():
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(mi as MeshInstance3D).visibility_range_end = 90.0
			cell.add_child(m)
		_missiles.append(m)


## How many cells hold a missile.
func loaded() -> int:
	var n := 0
	for e in _empty:
		if e <= 0.0:
			n += 1
	return n


## Launches the next loaded cell's missile (the next cell's, loaded or not, if all are empty: the pod never refuses):
## returns where it leaves, the cell's mouth, +Z along the pod's bore (world).
func launch() -> Transform3D:
	var k := _next
	for step in CELLS:
		var c := (_next + step) % CELLS
		if _empty[c] <= 0.0:
			k = c
			break
	_next = (k + 1) % CELLS
	_empty[k] = RELOAD
	_missiles[k].visible = false
	launched += 1
	_kick(JUMP, ROCK)
	var cell := "cell_%d" % (k + 1)
	var out := spot(cell)
	if is_visible_in_tree():
		_flash(cell, 1.5, 0.11, 1.3)
		_flash("vent", 2.6, 0.34, 1.6)
		var vent := spot("vent")
		SmokeCloud.wisp(self, out.origin + out.basis.z * 0.5, 1.0)
		SmokeCloud.wisp(self, vent.origin + vent.basis.z * 0.9, 1.6)
		SmokeCloud.wisp(self, vent.origin + vent.basis.z * 1.8, 2.0)
	return out


## A stab of flame out of a marker (along its +Z), dying away over FLASH_TIME.
func _flash(marker_name: String, length: float, radius: float, power: float) -> void:
	var at := part(marker_name)
	if at == null:
		return
	var f := Flame.new()
	f.length = length
	f.radius = radius
	f.color = Color(2.6, 1.5, 0.6)
	f.burner_color = Color(2.8, 2.2, 1.4)
	f.light_range = 7.0 if marker_name == "vent" else 0.0
	f.power = power
	at.add_child(f)
	_flames.append([f, FLASH_TIME, power])


func _animate(delta: float) -> void:
	for k in CELLS:
		if _empty[k] <= 0.0:
			continue
		_empty[k] = maxf(_empty[k] - delta, 0.0)
		if wrecked:
			_empty[k] = maxf(_empty[k], RUN_UP)  # nothing is loaded into a wreck
			continue
		if _empty[k] < RUN_UP:
			# The new missile runs up the cell to its mouth.
			var m := _missiles[k]
			m.visible = true
			var t := 1.0 - _empty[k] / RUN_UP
			m.position.z = -MISSILE_SET_BACK - RUN_UP_FROM * (1.0 - t * t * (3.0 - 2.0 * t))
	for i in range(_flames.size() - 1, -1, -1):
		var e: Array = _flames[i]
		e[1] -= delta
		var f: Node3D = e[0]
		if e[1] <= 0.0 or not is_instance_valid(f):
			if is_instance_valid(f):
				f.queue_free()
			_flames.remove_at(i)
		else:
			f.set("power", float(e[2]) * pow(float(e[1]) / FLASH_TIME, 1.5))
