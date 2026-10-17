class_name UnitTypes
extends RefCounted
## Attacker unit stats. Tweak numbers here while playtesting.
##
## role:
##   "infantry"  shoots defenders, falls back to gates/keep when nothing else is in range
##   "siege"     only attacks buildings, in melee (ram)
##   "artillery" lobs explosive shells, no line of sight needed, has a minimum range
##   "healer"    doesn't fight, heals the most damaged ally in range
##   "flying"    ignores walls and pathfinding, hovers at FLY_HEIGHT
## structure_mult: damage multiplier against gates / the keep.
## anim: procedural animation style until models are rigged (walk, hop, stomp, hover, roll),
##   or "rigged" to play the model's own clips: anim_move / anim_idle, with the move clip
##   sped up or slowed to match ground speed relative to anim_ref_speed (m/s).
## steer: only move where the model faces, turning at turn_rate (rad/s), no strafing.
## model: path to a processed GLB (front facing +Z, feet at origin), or "ram" for the built-in mesh.

const ORDER := ["rifleman", "kangaroo", "medic", "talon", "elephant", "mule", "breacher",
		"war_ram", "giraffe", "chimp", "hippo", "bison_gun", "lioness", "serpent", "rhino"]
const FLY_HEIGHT := 16.0

const DATA := {
	"rifleman": {
		"name": "Bear Rifleman", "cost": 50, "hp": 100.0, "speed": 4.6,
		"range": 30.0, "damage": 8.0, "fire_interval": 0.55, "spread": 0.035,
		"structure_mult": 0.5, "radius": 0.5, "height": 1.9,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_Z,
		"anim_move": "Running", "anim_idle": "Idle", "anim_ref_speed": 4.5,
		"model": "res://assets/units/cyber_bear_commando/cyber_bear_commando_rigged.glb",
	},
	"kangaroo": {
		"name": "Kangaroo Commando", "cost": 75, "hp": 90.0, "speed": 7.2,
		"range": 20.0, "damage": 13.0, "fire_interval": 0.6, "spread": 0.05,
		"structure_mult": 0.4, "radius": 0.55, "height": 2.0,
		"role": "infantry", "anim": "hop", "hotkey": KEY_X,
		"model": "res://assets/units/kangaroo_commando/kangaroo_commando_rigged.glb",
	},
	"medic": {
		"name": "Wolf Medic", "cost": 90, "hp": 110.0, "speed": 5.5,
		"range": 10.0, "heal_rate": 14.0, "damage": 0.0, "fire_interval": 0.5, "spread": 0.0,
		"structure_mult": 0.0, "radius": 0.55, "height": 1.4,
		"role": "healer", "anim": "rigged", "hotkey": KEY_C,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 3.0,
		"model": "res://assets/units/battlefield_lifesaver/battlefield_lifesaver_rigged.glb",
	},
	"talon": {
		"name": "Sky Talon", "cost": 120, "hp": 110.0, "speed": 8.0,
		"range": 26.0, "damage": 7.0, "fire_interval": 0.4, "spread": 0.05,
		"structure_mult": 0.15, "radius": 0.8, "height": 2.1,
		"role": "flying", "anim": "hover", "hotkey": KEY_V,
		"model": "res://assets/units/sky_talon_battalion/sky_talon_battalion_rigged.glb",
	},
	"elephant": {
		"name": "War Elephant", "cost": 320, "hp": 1400.0, "speed": 3.0,
		"range": 26.0, "damage": 9.0, "fire_interval": 0.15, "spread": 0.05,
		"structure_mult": 1.5, "radius": 1.6, "height": 3.8,
		"role": "infantry", "anim": "stomp", "hotkey": KEY_B,
		"model": "res://assets/units/war_elephant_sentinel/war_elephant_sentinel.glb",
	},
	"mule": {
		"name": "Mule Artillery", "cost": 280, "hp": 450.0, "speed": 2.6,
		"range": 80.0, "min_range": 20.0, "damage": 110.0, "fire_interval": 5.0, "spread": 0.06,
		"splash": 5.0, "structure_mult": 2.5, "radius": 1.6, "height": 2.2,
		"role": "artillery", "anim": "roll", "hotkey": KEY_N,
		"model": "res://assets/units/cyber_mule_artillery/cyber_mule_artillery.glb",
	},
	"breacher": {
		"name": "Breaching Ram", "cost": 220, "hp": 700.0, "speed": 2.8,
		"range": 3.5, "damage": 70.0, "fire_interval": 1.6, "spread": 0.0,
		"structure_mult": 4.0, "radius": 1.4, "height": 2.2,
		"role": "siege", "anim": "roll", "hotkey": KEY_M,
		"model": "ram",
	},
	# ---- Placeholder stats: models are in, roles still to be designed.
	"war_ram": {
		"name": "War Ram", "cost": 80, "hp": 150.0, "speed": 5.5,
		"range": 24.0, "damage": 9.0, "fire_interval": 0.5, "spread": 0.04,
		"structure_mult": 0.5, "radius": 0.6, "height": 1.6,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_G,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 3.0,
		"model": "res://assets/units/war_ram/war_ram_rigged.glb",
	},
	"giraffe": {
		"name": "Savanna Signal Scout", "cost": 100, "hp": 160.0, "speed": 5.0,
		"range": 30.0, "damage": 6.0, "fire_interval": 0.6, "spread": 0.04,
		"structure_mult": 0.3, "radius": 0.8, "height": 4.5,
		"role": "infantry", "anim": "stomp", "hotkey": KEY_H,
		"model": "res://assets/units/savanna_signal_scout/savanna_signal_scout_rigged.glb",
	},
	"chimp": {
		"name": "Night Ops Chimp", "cost": 70, "hp": 110.0, "speed": 5.5,
		"range": 24.0, "damage": 10.0, "fire_interval": 0.55, "spread": 0.04,
		"structure_mult": 0.5, "radius": 0.5, "height": 1.7,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_J,
		"anim_move": "Running", "anim_idle": "Idle", "anim_ref_speed": 4.5,
		"model": "res://assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb",
	},
	"hippo": {
		"name": "Hippo Heavy Gunner", "cost": 260, "hp": 1000.0, "speed": 3.2,
		"range": 26.0, "damage": 8.0, "fire_interval": 0.15, "spread": 0.05,
		"structure_mult": 1.0, "radius": 1.4, "height": 2.6,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_K,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 2.4,
		"model": "res://assets/units/hippopotamus_heavy_gunner/hippopotamus_heavy_gunner_rigged.glb",
	},
	"bison_gun": {
		"name": "Bison Field Gun", "cost": 260, "hp": 600.0, "speed": 3.0,
		"range": 40.0, "damage": 40.0, "fire_interval": 2.0, "spread": 0.02,
		"structure_mult": 1.5, "radius": 1.6, "height": 2.4,
		"role": "infantry", "anim": "stomp", "hotkey": KEY_L,
		"model": "res://assets/units/semi_futuristic_pair/semi_futuristic_pair.glb",
	},
	"lioness": {
		"name": "Armored Lioness", "cost": 90, "hp": 160.0, "speed": 6.5,
		"range": 22.0, "damage": 10.0, "fire_interval": 0.5, "spread": 0.04,
		"structure_mult": 0.5, "radius": 0.6, "height": 1.6,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_Y,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 3.0,
		"model": "res://assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb",
	},
	"serpent": {
		"name": "Serpent Sniper", "cost": 110, "hp": 80.0, "speed": 3.5,
		"range": 45.0, "damage": 35.0, "fire_interval": 2.5, "spread": 0.01,
		"structure_mult": 0.3, "radius": 0.6, "height": 0.9,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_U,
		"anim_move": "slither", "anim_idle": "idle", "anim_ref_speed": 2.4,
		"steer": true, "turn_rate": 2.5,
		"model": "res://assets/units/serpent_sniper/serpent_sniper_rigged.glb",
	},
	"rhino": {
		"name": "Armored Rhino", "cost": 280, "hp": 1100.0, "speed": 3.6,
		"range": 24.0, "damage": 8.0, "fire_interval": 0.2, "spread": 0.05,
		"structure_mult": 1.2, "radius": 1.3, "height": 2.4,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_I,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 2.6,
		"model": "res://assets/units/armored_rhino_unit/armored_rhino_unit_rigged.glb",
	},
}
