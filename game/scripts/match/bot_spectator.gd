class_name BotSpectator
extends Node
## Stands in for the player's controller in a match nobody plays (GameConfig.bot_match()): the CPU attacker, or a scripted
## one (AttackerProbe), against the garrison's own crews. It takes over no post, so every post fights on its own, and reads
## no keys; it only puts a camera over the field (some effects ask the viewport for one).

var level: LevelBuilder

var _camera: Camera3D


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.far = 2000.0
	level.add_child(_camera)
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40.0), 0, 0)), Vector3(0, 150, 230))
	_camera.current = true


## (The pause menu hands the mouse back to the controller: there is nobody to hand it to.)
func restore_mouse() -> void:
	pass
