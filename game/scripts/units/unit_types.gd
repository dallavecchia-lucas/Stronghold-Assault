class_name UnitTypes
extends RefCounted
## Attacker unit stats. Tweak numbers here while playtesting.
##
## role:
##   "infantry"  shoots defenders, falls back to gates/keep when nothing else is in range
##   "artillery" lobs explosive shells, no line of sight needed, has a minimum range
##   "healer"    doesn't fight. The Wolf Medic (the dog): two modes, one always on (heal_*, sweep_*)
##   "flying"    ignores walls and pathfinding, cruises at FLY_HEIGHT and never stops: it circles
##               where it was sent (TalonFlight). The Sky Talon has no basic attack: it strafes and
##               bombs (strafe_*, bomb_*)
##   "melee"     strikes whatever is within reach (range), no line of sight needed
##   "anti_air"  no basic attack. Passive: locks onto one enemy flyer within aa_range and
##               chips at it (aa_dps) until it dies or leaves. Active: cluster bombing (rhino)
##               or a missile salvo (elephant).
##   "siege"     no basic attack and no passive. Active: bombardment (bison, mule).
## flak: the anti-air passive comes from the model's two flak cannons (ElephantTurrets): they
##   swing up at the flyer and take turns firing shells that burst around it, each only once
##   it is on target.
## cluster_*: cluster bombing ability. Fires a shell every cluster_interval for cluster_duration
##   seconds at a ground point within cluster_range, scattered over cluster_spread.
## bombard_*: bombardment ability (Bison Field Gun). The unit stops, lays its gun on a point
##   within bombard_range (flat distance) for bombard_aim_time seconds and fires one shell of
##   bombard_damage over bombard_splash, scattered by bombard_spread per metre of range, then stands
##   for bombard_hold seconds before carrying on. Reloads in bombard_cooldown. The point can be up
##   on the gun decks and roofs. shell_size: the shell's radius (m, default 0.4); muzzle_blast: the
##   flash's size at the muzzle (default 1.6).
## setup_*: the Mule Artillery's gun has to be set up to fire (setup_time seconds, its anim_setup clip)
##   and packed up again to move (setup_time again, the clip played backward). It can't move unless its
##   gun is packed: moving orders while it sets up or is set up are refused, and one given while it packs
##   up waits till it is packed. Set up (its anim_armed loop), it bombards like the bison (bombard_*),
##   its gun's turret swinging round onto the aim at `traverse` rad/s (MuleGun) instead of the unit turning.
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
## burst: side-mounted SMGs (Kangaroo). Each shot is a burst of this many rounds, burst_interval
##   apart, the two guns taking turns (from the model's muzzle_L / muzzle_R bones); fire_interval is
##   from one burst to the next.
## flash_*: flash grenade (Kangaroo). It stops, rears up like a boxer and throws a grenade at a spot
##   within flash_range (the Throw clip: the grenade leaves the paw flash_release seconds in, the
##   clip is done at flash_time). It bursts on landing: every defender within flash_radius that sees
##   it is blinded for flash_blind seconds (the defending player's screen goes white). Several
##   kangaroos' grenades cluster round the aim like the bisons' shells (KangarooFlash). Reused after
##   flash_cooldown.
## resupply_*: passive (Kangaroo). Each kangaroo resupplies up to resupply_units allies within
##   resupply_range whose skills are cooling down: their cooldowns run resupply_cdr shorter. It
##   doesn't stack: no unit takes more than one kangaroo's (AttackerCommander hands them out).
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
## sight: how far it sees through the fog of war (m, flat; AttackerVision). The giraffe sees furthest.
## ping_*: sonar ping (Giraffe). It stands, stretches its neck up and sweeps its dish (the Ping clip:
##   the pulse goes out ping_release seconds in, the clip is done at ping_time), and the pulse spreads
##   at ping_speed out to ping_radius. Every defender soldier and trooper it reaches is marked where it
##   stood then by a red blur, for ping_mark seconds, that doesn't follow it (GiraffePing). Even under
##   adaptive camo; an infiltrator caught out of camo is revealed (InfiltratorTrooper.revealed).
##   Reused after ping_cooldown.
## sneak_*: sneak (Armored Lioness). For sneak_duration seconds she stalks (no faster than sneak_speed,
##   her Sneak clip): on the defender's side she is see-through (sneak_alpha opaque, no shadow, no
##   health bar), on the attacker's a bush icon hangs over her. She picks no fights on her own while it
##   lasts. Ordered to attack a defender on the ground, she stalks up to within pounce_range and pounces
##   (it ends the sneak). Reused after sneak_cooldown.
## pounce_*: the pounce (the Pounce clip, pounce_time long): she crouches, springs pounce_launch seconds in
##   and flies an arc onto the prey (pounce_height high, plus pounce_arc per metre), lands at pounce_land and
##   it takes pounce_damage; then she mauls it with her basic attack.
## strike_hit: a melee basic attack with its own clip (anim_strike): the blow lands this long into it.
## blast_*: fire blast (Armored Lioness). The flamethrowers on her back burn a cone in front of her for
##   blast_duration seconds (blast_range out, blast_angle either side), always where her face looks: she can
##   move meanwhile. Defenders in it take blast_dps and burn on for blast_afterburn seconds at
##   blast_afterburn_dps (LionessBlast). It ends a sneak, and never sets trees alight. Reused after
##   blast_cooldown.
## line: moved together, these form up in firing lines as they go (LionessLine), unless the attacking
##   player has turned that off (AttackerCommander.line_formation).
## walk_speed / gallop_after: after each move order she walks (no faster than walk_speed) for
##   gallop_after seconds, then breaks into her gallop (anim_run); a new move order starts it over.
## heal_*: the dog's healing mode. It heals up to heal_units hurt allies within heal_range, heal_rate HP/s
##   each, sticking to each until it is full or out of reach; no unit takes two dogs' healing (handed out by
##   AttackerCommander).
## sweep_*: the dog's minesweeping mode. It sniffs out the defenders' mines within sweep_range (the attacking
##   player can't see them), walks up to one at sweep_speed by a way clear of every other (DogSweep: the
##   minefield's outer rim first), digs it out and disarms it in disarm_time seconds (its anim_dig clip,
##   throwing dirt dig_sprays times a loop of it, the first dig_spray_at of the way in).
## nest_*: sniper nest (Serpent Sniper). Sent at a tree, it goes up to it and climbs it (nest_time seconds:
##   SerpentNest), up into its crown, and lies out along a bough with its rifle: up there it sees nest_sight times
##   as far through the fog of war and its rifle reaches nest_range times as far. It can't move up there: a move
##   order climbs it down (nest_time again), then it goes. Ordered to attack from up there, it fires from the
##   tree. Perched, a tree-and-rifle icon hangs over it on the attacker's side. A tree that catches fire, it
##   climbs down.
## trap_*: bush trap (Serpent Sniper). Sent at a bush, it hides its rifle in the bush and coils round the
##   bush (trap_time seconds: SerpentTrap); coiled, it never shoots, and any order uncoils it (trap_time again)
##   and it picks the rifle up before it goes. A defender on the ground that comes within trap_reach of the bush:
##   it strikes and constricts it for squeeze_time seconds, and nothing calls it off. The prey can't move or fight
##   and its health runs down steadily to nothing; then the snake goes back round its bush. Killed meanwhile, the
##   prey goes free with what health it has left. Coiled round its bush, it is see-through on the defender's
##   side (sneak_alpha opaque, no shadow, no health bar), a grass-and-snake icon over it on the attacker's.
## forest_speed: movement speed multiplier inside a forest (LevelBuilder.FORESTS).
## climb_speed: m/s up and down stairs and ladders.
## structure_mult: damage multiplier against gates / the keep.
## anim: procedural animation style until models are rigged (walk, stomp, roll), "flight"
##   for the Sky Talon's glide and wing beats (TalonFlight), or "rigged" to play the model's own
##   clips: anim_move / anim_idle, with the move clip
##   sped up or slowed to match ground speed relative to anim_ref_speed (m/s), within anim_scale
##   ([slowest, fastest], default [0.6, 2.0]: a kangaroo hops at about the same rate whatever its
##   speed, lengthening its bounds instead). anim_run: a faster gait's clip (authored at anim_run_speed,
##   played within run_scale) taking over above run_above m/s; anim_sneak: the clip while sneaking
##   (authored at anim_sneak_speed).
## steer: only move where the model faces, turning at turn_rate (rad/s), no strafing.
## model: path to a processed GLB (front facing +Z, feet at origin).
## gun: a hand-held gun model (HeldGun) hung on the model's `rifle` bone; its rounds' tracers leave its muzzle.

const ORDER := ["rifleman", "kangaroo", "medic", "talon", "elephant", "mule", "breacher",
		"giraffe", "chimp", "hippo", "bison_gun", "lioness", "serpent", "rhino"]
const FLY_HEIGHT := 16.0

const DATA := {
	"rifleman": {
		"name": "Bear Rifleman", "cost": 50, "hp": 100.0, "speed": 4.6,
		"sight": 34.0,
		"range": 30.0, "damage": 8.0, "fire_interval": 0.55, "spread": 0.035,
		"structure_mult": 0.5, "radius": 0.5, "height": 1.9,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_Z,
		"anim_move": "Running", "anim_idle": "Idle", "anim_ref_speed": 4.5,
		# The Prototype C heavy LMG at the hip, on the model's `rifle` bone (tools/gltf/arm_rifle.py).
		"gun": "res://assets/weapons/prototype_c_lmg/prototype_c_lmg.glb",
		"model": "res://assets/units/cyber_bear_commando/cyber_bear_commando_armed.glb",
	},
	"kangaroo": {
		"name": "Kangaroo Commando", "cost": 75, "hp": 90.0, "speed": 7.2,
		"sight": 32.0,
		"range": 20.0, "damage": 4.5, "fire_interval": 0.85, "spread": 0.06,
		"structure_mult": 0.4, "radius": 0.55, "height": 2.0,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_X,
		"anim_move": "Hop", "anim_idle": "Idle", "anim_ref_speed": 7.2, "anim_scale": [0.8, 1.3],
		"infiltrator": true, "raider": true, "climb_speed": 3.5,
		# Side-mounted SMGs: short bursts, the two guns taking turns.
		"burst": 4, "burst_interval": 0.07,
		"flash_cooldown": 30.0, "flash_range": 26.0, "flash_radius": 10.0, "flash_blind": 2.0,
		"flash_release": 0.95, "flash_time": 1.62,
		# Carries the supplies: nearby units get their skills back sooner.
		"resupply_range": 9.0, "resupply_units": 3, "resupply_cdr": 0.15,
		"model": "res://assets/units/kangaroo_commando/kangaroo_commando_rigged.glb",
	},
	"medic": {
		"name": "Wolf Medic", "cost": 90, "hp": 110.0, "speed": 5.5,
		"sight": 28.0,
		"range": 0.0, "damage": 0.0, "fire_interval": 0.5, "spread": 0.0,
		"structure_mult": 0.0, "radius": 0.55, "height": 1.4,
		"role": "healer", "anim": "rigged", "hotkey": KEY_C,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 3.0,
		# Two modes, one always on (T switches): healing, or minesweeping.
		"heal_range": 10.0, "heal_units": 2, "heal_rate": 12.0,
		"sweep_range": 18.0, "sweep_speed": 2.6, "disarm_time": 6.0,
		"anim_dig": "Dig", "dig_sprays": 4, "dig_spray_at": 0.025,
		"model": "res://assets/units/battlefield_lifesaver/battlefield_lifesaver_rigged.glb",
	},
	"talon": {
		"name": "Sky Talon", "cost": 120, "hp": 110.0, "speed": 8.0,
		"sight": 42.0,
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
		"sight": 36.0,
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
		"name": "Mule Artillery", "cost": 280, "hp": 450.0, "speed": 1.0,
		"sight": 28.0,
		"range": 0.0, "damage": 0.0, "fire_interval": 1.0, "spread": 0.0,
		"structure_mult": 1.5, "radius": 1.6, "height": 2.2,
		"role": "siege", "anim": "rigged", "hotkey": KEY_N,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 1.0, "anim_scale": [0.5, 1.6],
		"anim_setup": "Setup", "anim_armed": "Armed",
		# Six donkeys towing a siege gun: super slow, and it turns like a wagon.
		"steer": true, "turn_rate": 0.45,
		# The gun is set up to fire and packed up to move; set up, one shell every bombard_cooldown, with
		# nearly twice the bison's reach, twice its punch and a much bigger blast.
		"setup_time": 7.0, "traverse": 0.7,
		"bombard_range": 150.0, "bombard_cooldown": 30.0, "bombard_damage": 480.0,
		"bombard_splash": 11.0, "bombard_spread": 0.008, "bombard_aim_time": 1.0, "bombard_hold": 1.5,
		"shell_size": 0.6, "muzzle_blast": 2.6,
		"model": "res://assets/units/cyber_mule_artillery/cyber_mule_artillery_rigged.glb",
	},
	"breacher": {
		"name": "Breaching Ram", "cost": 150, "hp": 420.0, "speed": 5.0,
		"sight": 26.0,
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
		"sight": 28.0,
		"range": 1.8, "damage": 30.0, "fire_interval": 0.7, "spread": 0.0,
		"structure_mult": 0.3, "radius": 0.5, "height": 1.7,
		"role": "melee", "anim": "rigged", "hotkey": KEY_J,
		"anim_move": "Running", "anim_idle": "Idle", "anim_ref_speed": 4.5,
		"infiltrator": true, "raider": true, "forest_speed": 1.6, "climb_speed": 4.0,
		"model": "res://assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb",
	},
	"giraffe": {
		"name": "Savanna Signal Scout", "cost": 100, "hp": 160.0, "speed": 4.2,
		"sight": 75.0,
		"range": 30.0, "damage": 6.0, "fire_interval": 0.6, "spread": 0.04,
		"structure_mult": 0.3, "radius": 0.8, "height": 4.5,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_H,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 3.0,
		# The radar dish on its back: a sonar ping round it (GiraffePing).
		"ping_cooldown": 45.0, "ping_radius": 60.0, "ping_speed": 40.0, "ping_mark": 7.0,
		"ping_release": 0.8, "ping_time": 2.2,
		"model": "res://assets/units/savanna_signal_scout/savanna_signal_scout_rigged.glb",
	},
	"bison_gun": {
		"name": "Bison Field Gun", "cost": 260, "hp": 600.0, "speed": 3.0,
		"sight": 30.0,
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
		"name": "Armored Lioness", "cost": 120, "hp": 300.0, "speed": 6.0,
		"sight": 32.0,
		# Claws and teeth: within reach of her head and fore paws.
		"range": 2.6, "damage": 28.0, "fire_interval": 0.75, "spread": 0.0,
		"structure_mult": 0.3, "radius": 0.6, "height": 1.6,
		"role": "melee", "anim": "rigged", "hotkey": KEY_Y,
		"anim_move": "Walk", "anim_idle": "Idle", "anim_ref_speed": 1.7, "anim_scale": [0.6, 2.0],
		"anim_run": "Run", "anim_run_speed": 6.0, "run_above": 3.4, "run_scale": [0.6, 1.3],
		"walk_speed": 2.4, "gallop_after": 4.0,
		"anim_sneak": "Sneak", "anim_sneak_speed": 2.2, "anim_strike": "Strike", "strike_hit": 0.36,
		"sneak_duration": 10.0, "sneak_cooldown": 50.0, "sneak_speed": 2.6, "sneak_alpha": 0.3,
		"pounce_range": 12.0, "pounce_damage": 70.0, "pounce_launch": 0.38, "pounce_land": 0.86,
		"pounce_time": 1.2, "pounce_height": 0.5, "pounce_arc": 0.08,
		# The two flamethrowers on her back.
		"blast_duration": 3.0, "blast_cooldown": 45.0, "blast_range": 8.0, "blast_angle": 0.42,
		"blast_dps": 60.0, "blast_afterburn": 2.0, "blast_afterburn_dps": 12.0,
		"line": true,
		"model": "res://assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb",
	},
	"serpent": {
		"name": "Serpent Sniper", "cost": 130, "hp": 240.0, "speed": 3.5,
		"sight": 46.0,
		# The anti-materiel rifle strapped along its back: slow to fire, hard hitting.
		"range": 46.0, "damage": 95.0, "fire_interval": 4.0, "spread": 0.006,
		"structure_mult": 0.4, "radius": 0.6, "height": 0.9,
		"role": "infantry", "anim": "rigged", "hotkey": KEY_U,
		"anim_move": "Slither", "anim_idle": "Idle", "anim_ref_speed": 2.4,
		"steer": true, "turn_rate": 2.5,
		"nest_time": 8.0, "nest_sight": 1.8, "nest_range": 1.6,
		"trap_time": 8.0, "trap_reach": 4.0, "squeeze_time": 15.0, "sneak_alpha": 0.3,
		"model": "res://assets/units/serpent_sniper/serpent_sniper_rigged.glb",
	},
	"rhino": {
		"name": "Combat Rhino", "cost": 280, "hp": 1500.0, "speed": 3.0,
		"sight": 32.0,
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
		"sight": 32.0,
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
