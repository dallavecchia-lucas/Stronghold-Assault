class_name SentryGunRig
extends "res://scripts/turrets/gatling_rig.gd"
## The Orbital Sentry Gun on the gun decks (tools/gltf/rig_turrets.py `sentry`): a ten-barrelled gatling in a yoke on a
## round base. The turret turns on the base ring and carries the crew's seat on its left (seat()), the ammunition
## drum on its right and a radar dome on its roof, which turns while the gun is crewed; the receiver elevates between
## the yoke's cheeks; the barrels spin (GatlingRig).

const MODEL := "res://assets/defenses/orbital_sentry_gun/orbital_sentry_gun.glb"
## As low as the barrels go before they foul the base ring and the parapet in front of it, and as high (rad).
const DEPRESSION := deg_to_rad(-38.0)
const ELEVATION := deg_to_rad(56.0)


func _model_path() -> String:
	return MODEL


func model_height() -> float:
	return 2.2


func min_pitch(_at_yaw: float) -> float:
	return DEPRESSION


func max_pitch() -> float:
	return ELEVATION
