class_name UnitTypes
extends RefCounted
## Attacker unit stats. Tweak numbers here while playtesting.
##
## role:
##   "infantry"  shoots defenders, falls back to gates/keep when nothing else is in range
##   "artillery" lobs explosive shells, no line of sight needed, has a minimum range
##   "healer"    doesn't fight, heals the most damaged ally in range
##   "flying"    ignores walls and pathfinding, cruises at FLY_HEIGHT and never stops: it circles
##               where it was sent (TalonFlight). The Sky Talon has no basic attack: it strafes and
##               bombs (strafe_*, bomb_*)
##   "melee"     strikes whatever is within reach (range), no line of sight needed
##   "anti_air"  no basic attack. Passive: locks onto one enemy flyer within aa_range and
##               chips at it (aa_dps) until it dies or leaves. Active: cluster bombing (rhino)
##               or a missile salvo (elephant).
##   "siege"     no basic attack and no passive. Active: bombardment (bison).
## flak: the anti-air passive comes from the model's two flak cannons (ElephantTurrets): they
##   swing up at the flyer and take turns firing shells that burst around it, each only once
##   it is on target.
## cluster_*: cluster bombing ability. Fires a shell every cluster_interval for cluster_duration
##   seconds at a ground point within cluster_range, scattered over cluster_spread.
## bombard_*: bombardment ability (Bison Field Gun). The unit stops, lays its gun on a point
##   within bombard_range (flat distance) for bombard_aim_time seconds and fires one shell of
##   bombard_damage over bombard_splash, scattered by bombard_spread per metre of range, then stands
##   for bombard_hold seconds before carrying on. Reloads in bombard_cooldown. The point can be up
##   on the gun decks and roofs.
## scouts: rings the outside of the rest of the selection in scout formation (T).
## missile_*: missile salvo ability. missile_count homing missiles of missile_damage each, one
##   every missile_interval, at an enemy flyer within missile_range (flat distance). Reloads in
##   missile_cooldown. Selected elephants only fire as many salvos as the kill takes
##   (ElephantMissiles).
## suppress_radius: shots are aimed at a random point this far around the target, so the spray
##   can hit whatever stands next to it.
## overheat_*: the guns fire for overheat_time seconds in total (resting cools them at the same
##   rate), then overheat and stay silent for overheat_cooldown seconds.
## smoke_*: smoke screen ability. Three grenades land side by side, smoke_spacing apart, on an arc
##   smoke_min_range to smoke_range away. Each bursts at smoke_height, then drops and bursts twice
##   more on the way down, leaving a pillar of smoke_radius clouds. The curtain blocks line of
##   sight for smoke_duration seconds.
## strafe_*: strafe run (Sky Talon). It dives along a line strafe_length long anywhere inside
##   strafe_range of it, firing a round every strafe_interval that lands on the line ahead of it and
##   hits for strafe_damage within strafe_splash (TalonRun). Several talons fly parallel lanes
##   strafe_lane apart (TalonAim). Reused after strafe_cooldown.
## bomb_*: bomb strike (Sky Talon). It flies over a spot within bomb_range of it and drops one bomb,
##   bomb_damage within bomb_splash (times bomb_structure_mult against gates). Several talons' bombs
##   cluster round the aim like the bisons' shells. Reused after bomb_cooldown.
## pellets: shotgun. Each shot is this many pellets, spread over a cone of `spread` radians.
## ram_*: ram ability (Breaching Ram). A surge to ram_speed times its speed for ram_duration
##   seconds, reused after ram_cooldown. Enemy soldiers it runs over lose ram_trample_damage and are
##   tossed away at ram_toss m/s. Ordered at a ground gate while ramming, up to ram_gate_slots rams
##   charge it side by side and slam into it once each for ram_gate_damage; the others call their
##   ram off (RamCharge).
## infiltrator: one of the only units that can get inside the stronghold, through a broken gate.
##   Infiltrators also climb the stair shafts to the gun decks and the ladders to the roofs.
## raider: once inside, the player loses control of it. It hunts the defenders in the stronghold
##   and, when none are left standing, goes up to the gun decks and roofs to wreck the machines.
##   A raider with a ram rams the soldiers it hunts whenever it is ready (AttackerUnit.RAID_RAM_REACH).
## raid_keep: a raider that goes for the keep instead, fighting only the defenders it runs into on
##   the way (AttackerUnit.RAID_DETOUR).
## forest_speed: movement speed multiplier inside a forest (LevelBuilder.FORESTS).
## climb_speed: m/s up and down stairs and ladders.
## structure_mult: damage multiplier against gates / the keep.
## anim: procedural animation style until models are rigged (walk, hop, stomp, roll), "flight"
##   for the Sky Talon's glide and wing beats (TalonFlight), or "rigged" to play the model's own
##   clips: anim_move / anim_idle, with the move clip
##   sped up or slowed to match ground speed relative to anim_ref_speed (m/s).
## steer: only move where the model faces, turning at turn_rate (rad/s), no strafing.
## model: path to a processed GLB (front facing +Z, feet at origin).

const ORDER := ["rifleman", "kangaroo", "medic", "talon", "elephant", "mule", "breacher",
		"giraffe", "chimp", "hippo", "bison_gun", "lioness", "serpent", "rhino"]
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
		"range": 0.0, "damage": 0.0, "fire_interval": 1.0, "spread": 0.0,
		"structure_mult": 0.3, "radius": 0.8, "height": 2.1,
		"role": "flying", "anim": "flight", "hotkey": KEY_V,
		"strafe_range": 80.0, "strafe_length": 26.0, "strafe_lane": 7.0, "strafe_damage": 18.0,
		"strafe_splash": 2.5, "strafe_interval": 0.08, "strafe_cooldown": 90.0,
		"bomb_range": 80.0, "bomb_damage": 260.0, "bomb_splash": 7.0, "bomb_structure_mult": 1.0,
		"bomb_cooldown": 90.0,
		"model": "res://assets/units/sky_talon_battalion/sky_talon_battalion_rigged.glb",
	},
	"elephant": {
		"name": "War Elephant", "cost": 320, "hp": 1400.0, "speed": 3.0,
		"range": 0.0, "damage": 0.0, "fire_interval": 0.2, "spread": 0.0,
		"structure_mult": 1.5, "radius": 1.6, "height": 3.8,
		"role": "anti_air", "anim": "rigged", "hotkey": KEY_B,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 2.2,
		# The real anti-air unit: one elephant's flak is worth about five rhinos.
		"aa_range": 26.0, "aa_dps": 30.0, "flak": true,
		"missile_cooldown": 25.0, "missile_range": 60.0, "missile_count": 8,
		"missile_damage": 18.0, "missile_interval": 0.12,
		"model": "res://assets/units/war_elephant_sentinel/war_elephant_sentinel_rigged.glb",
	},
	"mule": {
		"name": "Mule Artillery", "cost": 280, "hp": 450.0, "speed": 2.6,
		"range": 80.0, "min_range": 20.0, "damage": 110.0, "fire_interval": 5.0, "spread": 0.06,
		"splash": 5.0, "structure_mult": 2.5, "radius": 1.6, "height": 2.2,
		"role": "artillery", "anim": "roll", "hotkey": KEY_N,
		"model": "res://assets/units/cyber_mule_artillery/cyber_mule_artillery.glb",
	},
	"breacher": {
		"name": "Breaching Ram", "cost": 150, "hp": 420.0, "speed": 5.0,
		"range": 7.0, "damage": 7.0, "fire_interval": 1.1, "spread": 0.14,
		"structure_mult": 1.0, "radius": 0.6, "height": 1.6,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_M, "infiltrator": true,
		"raider": true, "raid_keep": true, "climb_speed": 3.0,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 3.0,
		# Big horn sheep with a shotgun: a blast of pellets into a small cone in front of it.
		"pellets": 7,
		"ram_duration": 6.0, "ram_cooldown": 60.0, "ram_speed": 2.2,
		"ram_trample_damage": 55.0, "ram_toss": 9.0, "ram_gate_damage": 350.0, "ram_gate_slots": 3,
		"model": "res://assets/units/war_ram/war_ram_rigged.glb",
	},
	"chimp": {
		"name": "Night Ops Chimp", "cost": 80, "hp": 160.0, "speed": 5.5,
		"range": 1.8, "damage": 30.0, "fire_interval": 0.7, "spread": 0.0,
		"structure_mult": 0.3, "radius": 0.5, "height": 1.7,
		"role": "melee", "anim": "rigged", "hotkey": KEY_J,
		"anim_move": "Running", "anim_idle": "Idle", "anim_ref_speed": 4.5,
		"infiltrator": true, "raider": true, "forest_speed": 1.6, "climb_speed": 4.0,
		"model": "res://assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb",
	},
	# ---- Placeholder stats: models are in, roles still to be designed.
	"giraffe": {
		"name": "Savanna Signal Scout", "cost": 100, "hp": 160.0, "speed": 5.0,
		"range": 30.0, "damage": 6.0, "fire_interval": 0.6, "spread": 0.04,
		"structure_mult": 0.3, "radius": 0.8, "height": 4.5,
		"role": "infantry", "anim": "stomp", "hotkey": KEY_H,
		"model": "res://assets/units/savanna_signal_scout/savanna_signal_scout_rigged.glb",
	},
	"bison_gun": {
		"name": "Bison Field Gun", "cost": 260, "hp": 600.0, "speed": 3.0,
		"range": 0.0, "damage": 0.0, "fire_interval": 1.0, "spread": 0.0,
		"structure_mult": 1.5, "radius": 1.6, "height": 2.4,
		"role": "siege", "anim": "rigged", "hotkey": KEY_L,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 1.85,
		# One heavy shell at a time, from twice the rhinos' reach: onto the gun decks and roofs.
		"bombard_range": 80.0, "bombard_cooldown": 40.0, "bombard_damage": 240.0,
		"bombard_splash": 6.0, "bombard_spread": 0.008, "bombard_aim_time": 1.5, "bombard_hold": 1.0,
		"model": "res://assets/units/semi_futuristic_pair/semi_futuristic_pair_rigged.glb",
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
		"name": "Combat Rhino", "cost": 280, "hp": 1500.0, "speed": 3.0,
		"range": 0.0, "damage": 0.0, "fire_interval": 0.25, "spread": 0.0,
		"structure_mult": 1.2, "radius": 1.3, "height": 2.4,
		"role": "anti_air", "anim": "rigged", "hotkey": KEY_I,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 2.6,
		# Weak on its own on purpose: it takes about five rhinos to bring a flyer down quickly.
		"aa_range": 18.0, "aa_dps": 6.0, "scouts": true,
		"cluster_range": 40.0, "cluster_duration": 8.0, "cluster_cooldown": 45.0,
		"cluster_interval": 0.25, "cluster_damage": 28.0, "cluster_splash": 3.5, "cluster_spread": 6.0,
		"model": "res://assets/units/armored_rhino_unit/armored_rhino_unit_rigged.glb",
	},
	"hippo": {
		"name": "Hippo Heavy Gunner", "cost": 260, "hp": 1000.0, "speed": 3.2,
		"range": 26.0, "damage": 8.0, "fire_interval": 0.12, "spread": 0.02,
		"structure_mult": 1.0, "radius": 1.4, "height": 2.6,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_K,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 2.4,
		# Mounted machine guns: inaccurate suppressive fire that sprays around the target.
		"suppress_radius": 2.2, "overheat_time": 8.0, "overheat_cooldown": 2.0,
		"smoke_cooldown": 90.0, "smoke_range": 32.0, "smoke_min_range": 10.0,
		"smoke_duration": 30.0, "smoke_spacing": 6.0, "smoke_radius": 3.5, "smoke_height": 10.0,
		"model": "res://assets/units/hippopotamus_heavy_gunner/hippopotamus_heavy_gunner_rigged.glb",
	},
}
