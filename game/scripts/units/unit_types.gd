class_name UnitTypes
extends RefCounted
## Attacker unit stats. Tweak numbers here while playtesting.
##
## structure_mult: damage multiplier against gates / the keep.
## structures_only: ignores soldiers and guns (siege equipment).

const ORDER := ["rifleman", "heavy", "breacher"]

const DATA := {
	"rifleman": {
		"name": "Bear Rifleman", "cost": 50, "hp": 100.0, "speed": 4.6,
		"range": 30.0, "damage": 8.0, "fire_interval": 0.55, "spread": 0.035,
		"structure_mult": 0.5, "radius": 0.5, "height": 1.9, "scale": 1.0,
		"model": "bear", "structures_only": false, "hotkey": KEY_Z,
	},
	"heavy": {
		"name": "Bear Gunner", "cost": 140, "hp": 320.0, "speed": 3.4,
		"range": 24.0, "damage": 5.0, "fire_interval": 0.12, "spread": 0.06,
		"structure_mult": 1.0, "radius": 0.7, "height": 2.5, "scale": 1.3,
		"model": "bear", "structures_only": false, "hotkey": KEY_X,
	},
	"breacher": {
		"name": "Breaching Ram", "cost": 220, "hp": 700.0, "speed": 2.8,
		"range": 3.5, "damage": 70.0, "fire_interval": 1.6, "spread": 0.0,
		"structure_mult": 4.0, "radius": 1.4, "height": 2.2, "scale": 1.0,
		"model": "ram", "structures_only": true, "hotkey": KEY_C,
	},
}
