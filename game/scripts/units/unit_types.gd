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
## anim: procedural animation style until models are rigged (walk, hop, stomp, hover, roll).
## model: path to a processed GLB (front facing +Z, feet at origin), or "ram" for the built-in mesh.

const ORDER := ["rifleman", "kangaroo", "medic", "talon", "elephant", "mule", "breacher"]
const FLY_HEIGHT := 16.0

const DATA := {
	"rifleman": {
		"name": "Bear Rifleman", "cost": 50, "hp": 100.0, "speed": 4.6,
		"range": 30.0, "damage": 8.0, "fire_interval": 0.55, "spread": 0.035,
		"structure_mult": 0.5, "radius": 0.5, "height": 1.9,
		"role": "infantry", "anim": "walk", "hotkey": KEY_Z, "carry_gun": true,
		"model": "res://assets/units/cyber_bear_commando/cyber_bear_commando.glb",
	},
	"kangaroo": {
		"name": "Kangaroo Commando", "cost": 75, "hp": 90.0, "speed": 7.2,
		"range": 20.0, "damage": 13.0, "fire_interval": 0.6, "spread": 0.05,
		"structure_mult": 0.4, "radius": 0.55, "height": 2.0,
		"role": "infantry", "anim": "hop", "hotkey": KEY_X,
		"model": "res://assets/units/kangaroo_commando/kangaroo_commando.glb",
	},
	"medic": {
		"name": "Wolf Medic", "cost": 90, "hp": 110.0, "speed": 5.5,
		"range": 10.0, "heal_rate": 14.0, "damage": 0.0, "fire_interval": 0.5, "spread": 0.0,
		"structure_mult": 0.0, "radius": 0.55, "height": 1.4,
		"role": "healer", "anim": "walk", "hotkey": KEY_C,
		"model": "res://assets/units/battlefield_lifesaver/battlefield_lifesaver.glb",
	},
	"talon": {
		"name": "Sky Talon", "cost": 120, "hp": 110.0, "speed": 8.0,
		"range": 26.0, "damage": 7.0, "fire_interval": 0.4, "spread": 0.05,
		"structure_mult": 0.15, "radius": 0.8, "height": 2.1,
		"role": "flying", "anim": "hover", "hotkey": KEY_V,
		"model": "res://assets/units/sky_talon_battalion/sky_talon_battalion.glb",
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
}
