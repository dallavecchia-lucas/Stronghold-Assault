class_name FieldManualData
extends RefCounted
## The Field Manual's pages (FieldManual): every unit on each side, what it is for and its skills.
##
## A page: name, role (one line), meta ([label, value] pairs), about (a paragraph), clips ([clip id, caption]: the
## first plays first, then the rest in turn) and skills ({key, name, text, clip}: clip, optional, is the id of the
## clip that shows the skill; clicking the skill plays it). A clip id is a video in res://assets/tutorial/<id>.ogv,
## cut from the showcase videos in media/ by tools/video/cut_tutorial_clips.py (tools/video/tutorial_clips.json).
##
## The numbers are the game's (unit_types.gd, defender_armory.gd and the defense scripts); keep them in step.

const CLIP_DIR := "res://assets/tutorial/"


static func pages(attacker: bool) -> Array:
	return ATTACKERS if attacker else DEFENDERS


static func clip_path(id: String) -> String:
	return CLIP_DIR + id + ".ogv"


const DEFENDERS := [
	{
		"name": "How to Defend",
		"role": "First person  ·  switch between posts",
		"meta": [["Win", "hold 25 minutes"], ["Lose", "every air vent destroyed"], ["Credits", "30% of each kill's cost"]],
		"about": "You hold the stronghold, a mountain with a bunker dug into each face. The attackers win by destroying every air vent on the roofs; hold out for 25 minutes and you win. You start with no credits: every attacker that dies pays you 30% of what it cost. You fight from one post at a time (a rifleman, a deck gun, a squad, the Sniper, the jet or the tank); every post you aren't on fights by itself.",
		"clips": [["def_overview", "The garrison holding a gun deck"], ["rifle_view", "Through a deck rifleman's eyes"]],
		"skills": [
			{"key": "1 – 9", "name": "Take a post", "text": "Jump to a rifleman, machine gun or cannon post. Tab jumps to the post with the most enemies near it."},
			{"key": "G", "name": "Gunner Squad", "text": "Take command of the five Heavy Gunners posted in the south spawn hall. Free, and always there."},
			{"key": "B N M K J H", "name": "Buy", "text": "AA Squad (350), Flame Squad (300), Infiltrator Squad (280), Sniper (220), Fighter Jet (600), Hover Tank (450). Up to six on the roster."},
			{"key": "F1 – F6", "name": "Roster", "text": "Take command of a bought squad, the Sniper, the jet or the tank. Ctrl+F1–F6 changes its auto order without leaving your post."},
			{"key": "C", "name": "Drone swarm", "text": "Call the freshest drone swarm to the post you are on."},
			{"key": "Y  ·  U", "name": "Garrison spawn", "text": "Y moves your garrison spawn to the next side of the base; U sends its soldiers to the BASE (guns first) or the FIELD."},
			{"key": "Minimap", "name": "Base view", "text": "Top right: each side's guns, the attackers close to it and the gates. Click the minimap to take the post nearest there."},
		],
	},
	{
		"name": "Garrison Rifleman",
		"role": "Post  ·  the defenders' foot soldier",
		"meta": [["Spawns", "one every 12 s per side"], ["Sees", "34 m"], ["Fires at", "30 m"], ["Cost", "free"]],
		"about": "The Cyber Orc Sentinel with the Shadowline rifle, spawned all match long deep inside the base. Left to the CPU he crews the guns first, then fills the gun decks, then walks out through the gates to hold a perimeter round the mountain. Riflemen also hold the rifle posts on the decks, which you can take over.",
		"clips": [["rifle_view", "A deck rifleman: sneaking lionesses come up the field"], ["def_overview", "The garrison on a gun deck"], ["rifle_flash", "A Kangaroo's flash grenade blinds the post"]],
		"skills": [
			{"key": "WASD", "name": "Move", "text": "Shift sprints, Space jumps.", "clip": "rifle_view"},
			{"key": "LMB  ·  RMB", "name": "Fire and aim", "text": "Fire the rifle; hold RMB to aim down the sight. R reloads.", "clip": "rifle_view"},
			{"key": "Y", "name": "Spawn side", "text": "Moves your spawn control round the base: that side puts out two soldiers at a time, to answer an attack there.", "clip": "def_overview"},
			{"key": "U", "name": "BASE / FIELD", "text": "BASE (default) sends new soldiers to the guns, then the decks, then the field. FIELD sends them straight out to the perimeter.", "clip": "def_overview"},
			{"key": "Threat", "name": "Flash grenades", "text": "A Kangaroo's grenade blinds every post within 10 m that sees it for 2 s; your screen goes white.", "clip": "rifle_flash"},
		],
	},
	{
		"name": "Orbital Sentry Gun",
		"role": "Deck gun  ·  gatling",
		"meta": [["Where", "every bay of every gun deck"], ["Crew", "one garrison soldier"], ["Key", "1 – 9"]],
		"about": "A gatling on a low platform just over the parapet, one in every bay of the four gun decks. It fires on its own only once a garrison soldier sits in its side seat; you can take one over whether it is crewed or not. It can't fire into the doorway right below it.",
		"clips": [["sentry_gun", "Crewed, sweeping and firing; the barrels glow in a long fight"]],
		"skills": [
			{"key": "LMB", "name": "Fire", "text": "The barrels spin up first, then it hammers out rounds, throwing brass.", "clip": "sentry_gun"},
			{"key": "RMB", "name": "Zoom", "text": "Look closer down the gun."},
			{"key": "Heat", "name": "Overheat", "text": "Hold the trigger too long and it overheats and goes silent. Fire in bursts.", "clip": "sentry_gun"},
			{"key": "Crew", "name": "Knocked out", "text": "A knocked out gun frees its crew and comes back once repaired; it needs a crew again then."},
		],
	},
	{
		"name": "Arctic Sentinel Cannon",
		"role": "Deck gun  ·  the stronghold's long gun",
		"meta": [["Hit", "55 (80 yours)"], ["Splash", "30 within 3 m"], ["Reload", "1.5 s (0.9 s yours)"], ["Reach", "257 m"]],
		"about": "A heavy gun beside the sentry gun in every bay. Its shells burst where they land. A shell flies dead straight for 30 m, then falls: a near target is hit where the barrel points, a far one needs the barrel raised (10° lands it 126 m out, near 45° the longest shot, 257 m). The crews work the elevation out themselves and lob a shell every 12 s at targets out to 110 m.",
		"clips": [["cannon", "Crewed: recoil, the case thrown, shells lobbed far out"]],
		"skills": [
			{"key": "LMB", "name": "Fire", "text": "One shell; the barrel drives back into the mantlet and runs out again.", "clip": "cannon"},
			{"key": "RMB", "name": "Zoom", "text": "Look closer down the gun."},
			{"key": "Aim high", "name": "Range", "text": "Past 30 m the shell drops: raise the barrel over far targets and lead moving ones.", "clip": "cannon"},
		],
	},
	{
		"name": "Roof Defenses",
		"role": "Automatic  ·  Sentinel Bastion and Sentinel Spire",
		"meta": [["Where", "the roofs, over every bay"], ["Crew", "none: they run themselves"]],
		"about": "Up on the roofs, round the air vents, stand the Sentinel Bastions (flak guns) and the Sentinel Spires (anti-aircraft missiles). Nobody takes them over. They go for aircraft first, Sky Talons on their attack runs included. They never go after a transport helicopter: that is up to you.",
		"clips": [["bastion", "The Sentinel Bastion's flak"], ["spire", "The Sentinel Spire's missiles"]],
		"skills": [
			{"key": "Auto", "name": "Flak", "text": "The Bastion fires a shell every 0.42 s that bursts by its target, aircraft first (up to 78°), then ground targets at a quarter of the damage.", "clip": "bastion"},
			{"key": "Auto", "name": "Missiles", "text": "The Spire searches, swings onto an aircraft and fires homing missiles from its four cells, each reloaded 7 s later.", "clip": "spire"},
		],
	},
	{
		"name": "Gunner Squad",
		"role": "Squad  ·  five Heavy Gunners",
		"meta": [["Key", "G"], ["Cost", "free"], ["Post", "the south spawn hall"], ["Replaced", "one every 20 s"]],
		"about": "Five minigunners in heavy armour. You drive the trooper in the middle (third person); the other four follow and fire wherever you aim. The squad finds its own formation: a wedge in the open, pairs or single file through tight ways. Blast doors open for it, so it can sally out through any gate and back. Left alone it walks back to its post and holds it.",
		"clips": [["gunner_solo", "A lone Heavy Gunner"], ["gunner_file", "Up the spawn ramp in file"], ["gunner_wedge", "Out of the gate into a wedge"], ["gunner_fight", "A fight on two fronts"]],
		"skills": [
			{"key": "WASD", "name": "Move", "text": "Relative to the camera; the troopers walk any way while facing the aim.", "clip": "gunner_solo"},
			{"key": "LMB", "name": "Miniguns", "text": "The barrels spin up, then all five fire. The guns overheat after about 7 s.", "clip": "gunner_fight"},
			{"key": "RMB", "name": "Aim closer", "text": "Brings the camera in over the guns."},
			{"key": "Shift", "name": "Hustle", "text": "Move faster, without firing."},
			{"key": "Auto", "name": "Formation", "text": "Wedge in the open; pairs or single file in passages; it files into narrow ways before reaching them.", "clip": "gunner_file"},
			{"key": "Auto", "name": "New leader", "text": "If your trooper falls, the nearest takes the lead. All five down: the squad is back after 30 s.", "clip": "gunner_wedge"},
		],
	},
	{
		"name": "AA Squad",
		"role": "Squad  ·  five Missile Troopers",
		"meta": [["Key", "B"], ["Cost", "350"], ["Pods", "6 missiles each"], ["Lost", "when all five fall"]],
		"about": "Armoured Sentinels with a six-missile pod on the shoulder: the defenders' answer to Sky Talons and transport helicopters, with rockets and mines for the ground. It moves and files through tunnels like the Gunner Squad. It deploys in a gate spawn hall and joins the roster.",
		"clips": [["aa_lock", "Lock on, then seeking missiles"], ["aa_strike", "A rocket strike"], ["aa_mines", "Mines"], ["aa_auto", "Squads on their auto orders"]],
		"skills": [
			{"key": "RMB → LMB", "name": "Seeking missiles", "text": "Hold RMB with an aircraft near the crosshair (within 6°) for 3 s to lock on, then LMB fires as many missiles as the kill takes.", "clip": "aa_lock"},
			{"key": "LMB", "name": "Rocket strike", "text": "On the ground: every trooper fires three rockets round the aim, 5.5 m apart, 60 within 4.5 m each. Hold RMB to see the spots.", "clip": "aa_strike"},
			{"key": "F", "name": "Mines", "text": "Aim the cone, LMB: each trooper lobs two mines (160 within 4 m). The attacker can't see them. Ready again after 15 s.", "clip": "aa_mines"},
			{"key": "Reload", "name": "Pods", "text": "Each missile or rocket empties a tube; tubes reload one at a time, 2.5 s each."},
			{"key": "V", "name": "Auto order", "text": "MINES lays mines on the way home and round the gates; GUARD holds still. Either way it shoots down aircraft within 85 m.", "clip": "aa_auto"},
		],
	},
	{
		"name": "Flame Squad",
		"role": "Squad  ·  five Flame Troopers",
		"meta": [["Key", "N"], ["Cost", "300"], ["Flame", "90 per second, 6 m"], ["Lost", "when all five fall"]],
		"about": "Crimson Wardens with twin fuel tanks and a flame gun: they burn attackers up close and burn the forest down, taking away the cover Chimps, snakes and lionesses use. A burnt forest never grows back.",
		"clips": [["flame_solo", "A lone Flame Trooper"], ["flame_fight", "Chimps rush out of the trees and burn"], ["flame_tree", "Holding the flame on a trunk"], ["flame_clear", "The CLEAR order at work"]],
		"skills": [
			{"key": "LMB", "name": "Flame", "text": "Every trooper burns where you aim: 90 a second and burning for 2.5 s after. 14 s of pressure; it refills while you let go.", "clip": "flame_fight"},
			{"key": "Hold", "name": "Burn a tree", "text": "Hold the flame on a trunk for 8 s and the canopy catches. The tree falls 30 s later and the way is clear.", "clip": "flame_tree"},
			{"key": "V", "name": "Auto order", "text": "CLEAR burns the forests round the base, nearest first; GUARD holds still. Attackers within 16 m come first.", "clip": "flame_clear"},
		],
	},
	{
		"name": "Infiltrator Squad",
		"role": "Squad  ·  five Infiltrators",
		"meta": [["Key", "M"], ["Cost", "280"], ["Arrow", "34, silent"], ["Lost", "when all five fall"]],
		"about": "Harpy Vanguards with recurve bows: a deep infiltration squad for ambushes and sabotage. Attackers never pick an infiltrator out on their own; only an attack the attacking player orders goes after her. Their target is the attackers' Forward Helipads, the outposts their helicopters fly to.",
		"clips": [["inf_bow", "Low profile: ignored while she shoots"], ["inf_camo", "Adaptive camo"], ["inf_sabotage", "Sabotaging a helipad"], ["inf_op", "A sabotage operation, from above"]],
		"skills": [
			{"key": "Passive", "name": "Low profile", "text": "No attacker shoots her of its own accord. A Giraffe's ping that catches her out of camo reveals her until she goes under camo or out of sight.", "clip": "inf_bow"},
			{"key": "LMB", "name": "Silent arrows", "text": "Every trooper looses an arrow (34). No tracer, no flash: the attacker only sees health running down.", "clip": "inf_bow"},
			{"key": "Q", "name": "Adaptive camo", "text": "20 s, ready a minute after. Basic attacks can't target them; the first arrow breaks it. Blasts still hurt.", "clip": "inf_camo"},
			{"key": "F", "name": "Sabotage", "text": "Within 4 m of a helipad's deck for 45 s: the attackers lose it until they retake it. One kit, restocked inside the fortress.", "clip": "inf_sabotage"},
			{"key": "V", "name": "Operation", "text": "OP S / E / W: it sneaks out to that helipad by the safest way, sabotages it and comes home. HOLD stays put.", "clip": "inf_op"},
		],
	},
	{
		"name": "Sniper",
		"role": "Marksman  ·  the Grey Veil Warden",
		"meta": [["Key", "K"], ["Cost", "220"], ["Health", "300"], ["Round", "140, out to 400 m"]],
		"about": "One marksman in a ghillie cape with the Eclipse Longshot. Her rounds tag what they hit, so the whole garrison hits it harder. Left alone she holds where you left her and picks off one attacker at a time within 160 m, but not inside a forest.",
		"clips": [["sniper_walk", "Over her shoulder"], ["sniper_scope", "Through the scope"], ["sniper_tags", "Tags, as the attacker sees them"], ["sniper_thermal", "Thermal sight"]],
		"skills": [
			{"key": "RMB", "name": "Scope", "text": "First person through the scope at 8x; the wheel steps 4x, 8x, 12x. She walks slowly with it up.", "clip": "sniper_scope"},
			{"key": "LMB  ·  R", "name": "Fire", "text": "140 damage, then 1.5 s to work the bolt. Five rounds; R reloads (2.8 s). Tracers show where she shoots from.", "clip": "sniper_scope"},
			{"key": "Passive", "name": "Tag", "text": "A hit tags the unit for 20 s: every defender hits it 20% harder and a tagged Lioness can't sneak. Up to five tags out.", "clip": "sniper_tags"},
			{"key": "T", "name": "Thermal sight", "text": "15 s, then a minute to recharge: attackers glow white-hot and trees turn see-through.", "clip": "sniper_thermal"},
		],
	},
	{
		"name": "Fighter Jet",
		"role": "Machine  ·  chase camera",
		"meta": [["Key", "J"], ["Cost", "600"], ["Health", "700"], ["Speed", "120 m/s (200 boosted)"]],
		"about": "The defenders' fighter jet scrambles into the air in front of a gate and never lands. Crash it into the ground, the canopy, the mountain or a structure and it is lost for good. The War Elephants' flak and the Combat Rhinos shoot at it. Left alone it circles where you left it and fires only when attacked, then flies bomb runs on the attacker.",
		"clips": [["jet", "The fighter jet"]],
		"skills": [
			{"key": "Mouse", "name": "Fly", "text": "Steer at the ring; W/S pitch, A/D turn. Diving gains speed, climbing sheds it.", "clip": "jet"},
			{"key": "Shift  ·  Space", "name": "Boost and airbrake", "text": "Afterburners to 200 m/s (4 s from full); the airbrake slows to 85 m/s."},
			{"key": "LMB", "name": "Bomb", "text": "4 carried, one back every 25 s: 220 within 6 m. A ring on the ground shows where it would land if you let go now."},
			{"key": "RMB", "name": "Missile barrage", "text": "16 unguided missiles along the nose's line (30 each), then 11 s to reload. Turn through the salvo to spread it."},
			{"key": "Warning", "name": "PULL UP", "text": "Flashes ahead of a collision. Past the battlefield's edge you have 7 s to turn back."},
		],
	},
	{
		"name": "Hover Tank",
		"role": "Machine  ·  the Iron Vanguard",
		"meta": [["Key", "H"], ["Cost", "450"], ["Health", "1100"], ["Speed", "15 m/s"]],
		"about": "A hover tank that deploys outside a gate. It skims the rivers and the lake as it does the ground, but it is broad: trees, rocks and walls stop it. Left alone it holds where it stands and fights what comes within 110 m.",
		"clips": [["hover_tank", "The Iron Vanguard"]],
		"skills": [
			{"key": "WASD  ·  Mouse", "name": "Drive and aim", "text": "WASD goes where the camera looks; the turret follows the crosshair.", "clip": "hover_tank"},
			{"key": "LMB", "name": "Main gun", "text": "220 within 7 m, 3.2 s to reload. It fires once the barrel is laid. Straight for 200 m, then it drops: aim above far targets.", "clip": "hover_tank"},
			{"key": "RMB", "name": "Machine guns", "text": "Twin sponson guns fixed forward (20 rounds a second): aim them by turning the hull."},
			{"key": "Space", "name": "Jump", "text": "Thrusters throw it 12 m up and 55 m forward along the hull. 10 s cooldown."},
			{"key": "Careful", "name": "Trees", "text": "Running into a tree stops it dead: 45–95 damage and a short stun, and the tree goes over."},
		],
	},
	{
		"name": "Drone Swarms",
		"role": "Support  ·  six swarms of five drones",
		"meta": [["Key", "C"], ["Reach", "about 155 m on a full tank"], ["Hunts", "for 25 s, within 80 m"]],
		"about": "Small ducted-fan gunships docked on the roofs. Any defender can call a swarm to where it stands: you with C, and the garrison, squads and posts by themselves when attackers come within 40 m. Every call gets the freshest swarm that can make the trip. Only anti-air units and Bear Riflemen can hurt a drone.",
		"clips": [["drone", "A defender drone"]],
		"skills": [
			{"key": "C", "name": "Call a swarm", "text": "To the post you are on. The HUD shows how many drones are ready; a refused call says why.", "clip": "drone"},
			{"key": "Fuel", "name": "Recharge", "text": "Drones fly home to recharge on their docks; a swarm with under 65% of a tank can't go far."},
		],
	},
]


const ATTACKERS := [
	{
		"name": "How to Attack",
		"role": "Real-time strategy  ·  command the siege army",
		"meta": [["Win", "every air vent destroyed"], ["War chest", "25,000 credits, no income"], ["Army", "up to 60 units"]],
		"about": "Destroy every air vent on the stronghold's roofs before 25 minutes are up. Your war chest is all you get: a unit that dies is credits gone. Every unit is built at the Mobile Command Citadel on the south edge. Break a gate down and only Chimps, Breaching Rams and Kangaroo Commandos can get inside. Your army only sees what is round it, so bring spotters.",
		"clips": [["att_overview", "The army on the march"]],
		"skills": [
			{"key": "Backspace", "name": "Build", "text": "Select the citadel, then a unit's key (or tile). Paid at once, built one at a time, out in front of the citadel."},
			{"key": "LMB", "name": "Select", "text": "Click or drag; Shift adds. Ctrl+1–9 saves a group, 1–9 recalls it (twice: the camera goes there)."},
			{"key": "RMB", "name": "Attack-move", "text": "Move and fight on the way, or attack the gate or defender clicked. Ctrl+RMB moves without stopping."},
			{"key": "WASD  ·  Q E", "name": "Camera", "text": "Pan with WASD, the arrows or the screen edge; Q/E or the middle mouse rotate; the wheel zooms."},
			{"key": "Fog", "name": "Fog of war", "text": "Nobody picks out a defender it can't see, and you can't order an attack on one: long-range units need a spotter."},
			{"key": "F1", "name": "Keys", "text": "Shows every key. Several skills share a key: the lit badge on the command card is the one it uses now."},
		],
	},
	{
		"name": "Bear Rifleman",
		"role": "Infantry  ·  the backbone of the army",
		"meta": [["Key", "Z"], ["Cost", "50"], ["Health", "100"], ["Range", "30 m"]],
		"about": "Cheap and quick to build, with a light machine gun. The bears are the one ground unit besides the anti-air that can shoot down the defenders' drones: a drone in sight within 30 m locks a bear onto it until it is gone. Bears swim the rivers.",
		"clips": [["hero_bear", "The Bear"], ["bear_swim", "Swimming the river"], ["bear_dive", "The dive, as the attacker sees it"]],
		"skills": [
			{"key": "Basic", "name": "Light machine gun", "text": "8 a round out to 30 m."},
			{"key": "Passive", "name": "Drone hunter", "text": "A drone in sight within 30 m: DRONE LOCK, it shoots it and takes no orders until none is left (the last order waits)."},
			{"key": "Passive", "name": "Swim", "text": "Crosses the rivers and the lake by itself, but can't fire while swimming.", "clip": "bear_swim"},
			{"key": "F", "name": "Dive", "text": "Out swimming: under the water for 10 s, out of the defenders' sight. Shots into the water still hit. 35 s cooldown.", "clip": "bear_dive"},
		],
	},
	{
		"name": "Wolf Medic",
		"role": "Support  ·  heals or sweeps for mines",
		"meta": [["Key", "C"], ["Cost", "90"], ["Health", "110"], ["Heals", "12 HP/s, 2 units"]],
		"about": "The dog has no attack. It is always in one of two modes: healing the units round it, or sniffing out the AA Squads' mines, which you otherwise can't see. Two dogs heal four units; no unit is healed by two at once.",
		"clips": [["hero_wolf", "The Wolf"], ["dog_heal", "Healing on the move"], ["dog_sweep", "A minefield found and swept"], ["dog_dig", "Digging a mine out"]],
		"skills": [
			{"key": "Mode", "name": "Healing", "text": "Up to 2 hurt units within 10 m, 12 HP/s each, on the move too; it sticks with them until they are full or leave.", "clip": "dog_heal"},
			{"key": "Mode", "name": "Minesweeping", "text": "Smells mines within 18 m, digs one out and disarms it in 6 s, taking a minefield from its outer rim inwards.", "clip": "dog_sweep"},
			{"key": "T", "name": "Switch mode", "text": "Switches the selected dogs between healing and minesweeping (or the Dogs: button).", "clip": "dog_dig"},
			{"key": "Ctrl+RMB", "name": "Plain move", "text": "A plain move calls the digging off; RMB (attack-move) keeps sweeping on the way."},
		],
	},
	{
		"name": "Mule Artillery",
		"role": "Siege  ·  six donkeys and a long gun",
		"meta": [["Key", "N"], ["Cost", "280"], ["Health", "1600"], ["Shell", "480 within 11 m, 150 m"]],
		"about": "Six donkeys in harness towing a tracked siege gun with a very long barrel. Super slow (1.6 m/s), and its gun has to be set up before it fires, but nothing else reaches as far or hits as hard. It crosses the rivers only by a bridge; the Heavy Lift Helicopter can fly it to an outpost.",
		"clips": [["hero_mule", "The Mules"]],
		"skills": [
			{"key": "T", "name": "Set up / pack up", "text": "The barrel rises to 40° (7 s). It can't move while setting up, armed or packing; T again packs it up."},
			{"key": "G", "name": "Bombardment", "text": "Armed: G, then LMB. One shell every 30 s out to 150 m, up on the decks and roofs too. Several mules spread their shells 16.5 m apart."},
		],
	},
	{
		"name": "Sky Talon",
		"role": "Flyer  ·  the hawk",
		"meta": [["Key", "V"], ["Cost", "120"], ["Health", "110"], ["Cooldowns", "90 s"]],
		"about": "Flies over the mountain and everything else. It glides, beating its wings now and then, and never hovers: wherever it is sent it circles. No basic attack: it strikes with two skills. The roofs' anti-air and the AA Squads shoot at it, so take those out first.",
		"clips": [["hero_talon", "The Eagle"], ["talon_fly", "Take-off and glide"], ["talon_strike", "Bombs and strafing runs on the south face"], ["talon_flock", "A flock, a ring each"]],
		"skills": [
			{"key": "F", "name": "Strafe run", "text": "Press LMB on the target and drag the way to fly: it dives along the 26 m line, about 40 rounds of 18 each.", "clip": "talon_strike"},
			{"key": "G", "name": "Bomb strike", "text": "LMB a spot: each talon drops one bomb, 260 within 7 m, full damage against gates. Several spread 10.5 m apart.", "clip": "talon_strike"},
			{"key": "Passive", "name": "Flight", "text": "Climbs over the mountain on its own and stacks up with others in rings of their own.", "clip": "talon_flock"},
		],
	},
	{
		"name": "War Elephant",
		"role": "Anti-air  ·  heavy and slow",
		"meta": [["Key", "B"], ["Cost", "320"], ["Health", "1400"], ["Flak ring", "26 m"]],
		"about": "The real anti-air unit, with no basic attack. Flak cannons on its flanks shoot at flyers in its ring; missile pods on its back bring them down. It swims, and tows a pontoon raft that two riders can cross the water on.",
		"clips": [["hero_elephant", "The Elephant"], ["elephant_raft", "Its raft folded on its rump"], ["raft_crossing", "Towing riders across the river"]],
		"skills": [
			{"key": "Passive", "name": "Flak", "text": "Swings onto one flyer in its ring and fires bursting shells until it dies or leaves. One elephant hits like five rhinos."},
			{"key": "O", "name": "Missiles", "text": "Then LMB an aircraft: eight homing missiles (60 m, 25 s reload). Only as many elephants fire as the kill takes."},
			{"key": "Passive", "name": "Swim and tow", "text": "Swims across, trunk up like a snorkel, towing its raft with two riders on it.", "clip": "raft_crossing"},
		],
	},
	{
		"name": "Combat Rhino",
		"role": "Anti-air  ·  tanky bombardier",
		"meta": [["Key", "I"], ["Cost", "280"], ["Health", "1500"], ["Zone", "40 m"]],
		"about": "Tanky and slow, with no basic attack. It locks onto enemy flyers on its own, though it takes about five rhinos to bring one down fast. Its cluster bombs pound a spot for 8 s. It crosses the water on a raft, alone.",
		"clips": [["hero_rhino", "The Rhino"], ["raft_crossing", "Riders crossing on the rafts"]],
		"skills": [
			{"key": "Passive", "name": "Anti-air", "text": "Locks onto one flyer in its dashed ring and stays on it until it dies or leaves."},
			{"key": "F", "name": "Cluster bombing", "text": "Aim, then LMB: each rhino shells a spot inside its 40 m zone for 8 s. 45 s cooldown. The preview shows each one's bombs."},
			{"key": "T", "name": "Scout formation", "text": "With other units selected, the rhinos ring the outside of the group so their anti-air covers it."},
		],
	},
	{
		"name": "Bison Field Gun",
		"role": "Siege  ·  two bisons and a gun",
		"meta": [["Key", "L"], ["Cost", "260"], ["Health", "600"], ["Shell", "240 within 6 m, 80 m"]],
		"about": "Two bisons with an artillery gun slung between them. Slow, with no basic attack: it stops, lays the gun and fires one heavy shell, then carries on with its order. Its shells reach the gun decks and roofs, so it can wreck the guns and AA from out in the field. It crosses the rivers only by a bridge.",
		"clips": [["hero_bison", "The Bison"]],
		"skills": [
			{"key": "G", "name": "Bombardment", "text": "Aim, then LMB: one shell up to 80 m away, 240 within 6 m, reloads in 40 s. Several bisons spread their shells 9 m apart along a deck."},
		],
	},
	{
		"name": "Hippo Heavy Gunner",
		"role": "Infantry  ·  suppressive fire",
		"meta": [["Key", "K"], ["Cost", "260"], ["Health", "1000"], ["Range", "26 m"]],
		"about": "Heavy and slow, spraying suppressive fire from mounted machine guns. It swims with its head out of the water and tows a pontoon raft for two riders.",
		"clips": [["hero_hippo", "The Hippopotamus"], ["hippo_raft", "The raft put down; the riders get off"], ["raft_crossing", "Across the river"]],
		"skills": [
			{"key": "Basic", "name": "Machine guns", "text": "Inaccurate: rounds land round the target and hit what stands near it. 8 s of fire, then 2 s to cool."},
			{"key": "R", "name": "Smoke screen", "text": "Aim the cone, LMB: three grenades raise a curtain that blocks sight for both sides for 30 s. 90 s cooldown."},
			{"key": "Space", "name": "Riders off", "text": "Lets the riders on its raft off on dry land; the raft comes apart behind it.", "clip": "hippo_raft"},
		],
	},
	{
		"name": "Breaching Ram",
		"role": "Breacher  ·  big horn sheep",
		"meta": [["Key", "M"], ["Cost", "150"], ["Health", "420"], ["Gate hit", "350"]],
		"about": "It breaks gates, and with the Chimp and the Kangaroo it is one of the only units that can get inside the stronghold. Once inside, it makes for the Keep on its own, ramming and blasting every defender it meets.",
		"clips": [["hero_ram", "The Ram"], ["ram_charge", "Charging the gate down"], ["ram_raid", "Loose inside the stronghold"]],
		"skills": [
			{"key": "Basic", "name": "Shotgun", "text": "Seven pellets in a small cone, out to 7 m."},
			{"key": "Space", "name": "Ram", "text": "2.2x speed for 6 s (60 s cooldown); soldiers run over are hurt and tossed aside.", "clip": "ram_charge"},
			{"key": "RMB gate", "name": "Gate charge", "text": "While ramming, RMB a gate: up to three line up across the doorway and slam into it for 350 each.", "clip": "ram_charge"},
			{"key": "RMB", "name": "Infiltrate", "text": "Next to a broken gate: in they go, out of your control, and fight their way to the Keep.", "clip": "ram_raid"},
		],
	},
	{
		"name": "Night Ops Chimp",
		"role": "Melee  ·  fast raider",
		"meta": [["Key", "J"], ["Cost", "80"], ["Health", "160"], ["Blow", "30"]],
		"about": "A fast melee fighter that swings through the forests and, once a gate is down, gets inside. Inside it hunts the defenders anywhere, up to the gun decks and the roofs, and wrecks the machines once nobody is left standing.",
		"clips": [["hero_chimp", "The Chimpanzee"], ["chimp_swing", "Swinging through the trees"], ["ram_raid", "Inside the stronghold"]],
		"skills": [
			{"key": "Basic", "name": "Melee", "text": "Strikes whatever is within arm's reach."},
			{"key": "Passive", "name": "Tree swing", "text": "60% faster through forests, up in the branches. It can be shot down out of the trees, and burnt forest gives no speed.", "clip": "chimp_swing"},
			{"key": "RMB", "name": "Infiltrate", "text": "Next to a broken gate: in they go, out of your control, hunting the garrison.", "clip": "ram_raid"},
		],
	},
	{
		"name": "Kangaroo Commando",
		"role": "Infantry  ·  fast, flashes, resupplies",
		"meta": [["Key", "X"], ["Cost", "75"], ["Health", "90"], ["Speed", "7.2 m/s"]],
		"about": "Fast, with two SMGs on its chest. Its flash grenades blind the defenders' posts, its supplies speed up the skills of the units round it, and it is one of the three units that can get inside the stronghold.",
		"clips": [["hero_kangaroo", "The Kangaroo"], ["kangaroo_hop", "Hopping down the lane"], ["kangaroo_flash", "Flash grenades onto the deck"], ["rifle_flash", "The flash, from the defender's side"], ["kangaroo_raid", "Storming the base"]],
		"skills": [
			{"key": "Basic", "name": "Twin SMGs", "text": "Short bursts out to 20 m; it rears up to fire at the decks.", "clip": "kangaroo_hop"},
			{"key": "R", "name": "Flash grenade", "text": "Aim, LMB: thrown up to 26 m, it blinds every defender within 10 m that sees it for 2 s. 30 s cooldown.", "clip": "kangaroo_flash"},
			{"key": "Passive", "name": "Supplies", "text": "Up to 3 units within 9 m get their skills back 15% sooner. It doesn't stack."},
			{"key": "RMB", "name": "Infiltrate", "text": "Next to a broken gate: in they go, hunting the defenders and flashing them.", "clip": "kangaroo_raid"},
		],
	},
	{
		"name": "Savanna Signal Scout",
		"role": "Scout  ·  the Giraffe",
		"meta": [["Key", "H"], ["Cost", "100"], ["Health", "160"], ["Sight", "75 m"]],
		"about": "A giraffe with a radar dish on its back. It sees further than any unit, deep into the fog of war: walk it ahead of the army to spot for the long-range units. Its ping finds defenders you can't see, Infiltrators under camo included.",
		"clips": [["hero_giraffe", "The Giraffe"], ["giraffe_ping", "The ping marks defenders in the fog"], ["raft_crossing", "Riding a raft across"]],
		"skills": [
			{"key": "Passive", "name": "Long sight", "text": "Sees 75 m, where most units see 26–50."},
			{"key": "Basic", "name": "Light fire", "text": "Out to 30 m."},
			{"key": "P", "name": "Ping", "text": "A pulse out to 60 m: every defender it reaches leaves a red blur for 7 s. An Infiltrator caught out of camo is revealed. 45 s cooldown.", "clip": "giraffe_ping"},
		],
	},
	{
		"name": "Armored Lioness",
		"role": "Melee  ·  stalker",
		"meta": [["Key", "Y"], ["Cost", "120"], ["Health", "300"], ["Gallop", "6 m/s"]],
		"about": "A lioness in armour with two flamethrowers on her back. She walks for 4 s, then breaks into a gallop. She stalks defenders half-hidden and pounces, and moved together lionesses march in firing lines.",
		"clips": [["hero_lioness", "The Lioness"], ["lioness_walk", "Walk, then gallop"], ["lioness_lines", "Firing lines"], ["lioness_sneak", "Sneak and pounce"], ["rifle_view", "Sneaking, as the defender sees it"], ["lioness_blast", "The fire blast"]],
		"skills": [
			{"key": "Basic", "name": "Claws", "text": "Rears up and swipes down, biting: 28 a blow within 2.6 m."},
			{"key": "F", "name": "Sneak", "text": "10 s of stalking, 70% see-through to the defender. RMB a defender: she stalks within 12 m and pounces (70). A Sniper's tag ends it. 50 s cooldown.", "clip": "lioness_sneak"},
			{"key": "G", "name": "Fire blast", "text": "Her flamethrowers burn a cone 8 m out for 3 s: 60 a second, burning on for 2 s. 45 s cooldown. Trees don't catch.", "clip": "lioness_blast"},
			{"key": "T", "name": "Firing lines", "text": "Two or more moved together form lines of up to 8 abreast as they go. T turns lines off and on.", "clip": "lioness_lines"},
		],
	},
	{
		"name": "Serpent Sniper",
		"role": "Sniper  ·  an anaconda with a rifle",
		"meta": [["Key", "U"], ["Cost", "130"], ["Health", "240"], ["Round", "95, out to 46 m"]],
		"about": "A 5 m anaconda in a helmet and vest, an anti-materiel rifle along its back. Slow and hard-hitting, it climbs trees to snipe from the crown, or coils round a bush and waits for a defender to walk past. It swims.",
		"clips": [["hero_serpent", "The Serpent"]],
		"skills": [
			{"key": "Basic", "name": "Rifle", "text": "One round every 4 s, 95 damage out to 46 m (40% of that against gates)."},
			{"key": "F", "name": "Sniper nest", "text": "LMB a tree: it climbs into the crown (8 s) and sees 83 m, its rifle reaching 74 m. Any move order climbs it down. A burning tree brings it down."},
			{"key": "G", "name": "Bush trap", "text": "LMB a bush: it coils round it (8 s), half-hidden. A defender within 4 m is seized and dies in 15 s, unless the snake is shot first."},
		],
	},
	{
		"name": "Heavy Lift Helicopter",
		"role": "Transport  ·  two stand by the citadel",
		"meta": [["Health", "6000"], ["Hold", "50 spaces"], ["Replaced", "500 s after it is lost"]],
		"about": "The quick way to an outpost: each one flies a load from the citadel to one Forward Helipad you hold, unloads it next to the camp and flies home. An elephant or giraffe takes 5 spaces, a rhino or hippo 2, a bison gun 10, a mule 15, everything else 1. The defenders' automatic guns leave it alone, but anything they drive can hurt it.",
		"clips": [["heavy_lift", "The Heavy Lift Helicopter"]],
		"skills": [
			{"key": "RMB heli", "name": "Board", "text": "With units selected, RMB a helicopter at the citadel: they walk up the ramp, nearest first."},
			{"key": "RMB pad", "name": "Fly", "text": "Select the helicopter, RMB a helipad you hold. It only goes loaded and mended."},
			{"key": "Passive", "name": "Mend", "text": "Hurt, it mends on the ground (2 minutes from nothing). Smoke shows the damage: grey, black, then fire."},
			{"key": "Danger", "name": "Sabotage", "text": "If Infiltrators take its helipad it turns back, or, caught on the pad, lifts off at once losing 20% of its health."},
		],
	},
	{
		"name": "Rivers and Bridges",
		"role": "Crossing the Jungle Keep's water",
		"meta": [["Bridges", "30 a match"], ["Bridge health", "6000"], ["Key", "Shift+B"]],
		"about": "The rivers are too deep to wade. Bears, Serpents, Hippos and Elephants swim; Hippos and Elephants tow rafts for two riders each (a Rhino or Giraffe rides alone); Sky Talons fly over. Mules and Bison guns cross by a bridge or not at all. Nobody can fire while swimming or riding.",
		"clips": [["bridge", "A folding bridge airdropped across the river"], ["raft_crossing", "Rafts towed across"], ["hippo_raft", "Riders getting off"]],
		"skills": [
			{"key": "Shift+B", "name": "Folding bridge", "text": "A preview snaps across the nearest river (red where it can't go). LMB orders it; it drops and unfolds in about 11 s.", "clip": "bridge"},
			{"key": "RMB", "name": "Ride a raft", "text": "Send riders across with the carriers, or RMB a Hippo or Elephant with riders selected.", "clip": "raft_crossing"},
			{"key": "Alarm", "name": "Defenders crossing", "text": "Defenders can use your bridges too: one on it sets off its alarm and a red banner. Shells, rockets and the Sniper can bring a bridge down, sinking whoever is on it."},
		],
	},
]
