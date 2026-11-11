# Stronghold Assault

Asymmetric RTS vs FPS siege game built in Godot 4. One player commands the attacking army (RTS); the other defends the stronghold in first person, rotating between soldiers and mounted weapons.

## Getting the repo (Git LFS required)

Models, textures and audio are stored with [Git LFS](https://git-lfs.com). Install it once, then clone:

```sh
git lfs install
git clone https://github.com/dallavecchia-lucas/Stronghold-Assault
```

If you cloned before installing LFS, run `git lfs pull` to download the real asset files.

Tracked file types are listed in `.gitattributes` (glb, fbx, blend, png, wav, ogg, …). Check what is in LFS with `git lfs ls-files`.

## Playing (offline prototype)

Open `game/project.godot` in **Godot 4.5** and press Play (F5). Pick a side on the menu; the CPU plays the other one.

- **Attacker wins** by destroying the Keep. **Defender wins** by holding for 10 minutes.

**The map.** The stronghold is a mountain with a bunker dug into each of its four faces (`game/assets/stronghold/stronghold.glb`). The Keep is the reactor in the core hall under the peak. Attackers come from the south, east and west. Each of those faces has a blast-door gate on its middle ground tunnel; every other tunnel is welded shut. Once a gate is down, only Chimps, Breaching Rams and Kangaroo Commandos can get inside; everyone else fights from outside. Inside, they can also climb the stair shafts to the gun decks and the ladders to the roofs. Forest groves stand off to the sides of the attack lanes; they burn (the Flame Squads), and a burnt forest never grows back. Out by each lane stands one of the attackers' Forward Helipad Bases (south, east and west: see the Attacker section), the Infiltrator Squads' targets. The defenders hold the gun decks and roofs: a machine gun over each gate, riflemen along the decks, the mortar on the south roof and two AA turrets on every roof. The guns can't fire into the doorway right below them; the mortar covers it.

**Maps.** The menu has a map picker (`--map=jungle|classic` on the command line). Both have the same stronghold; around it:

- **Jungle Keep** (the default; `game/scripts/match/jungle/`). A 1.6 km square of forest (the concept's "jungle"), everything at its real size. The stronghold stands in a 270 m clearing in the middle. A 42 m river crosses the whole map south of it, west to east; a tributary comes down out of the north-west into a lake and on into it, and another river runs down the east side of the clearing from the north edge. The rivers (over 4 m deep) and the lake can't be waded: there is no ford. All the water is cut out of the navmesh, and an invisible wall along the water's edge stops every walker (the attackers' ground units, the garrison, the squads, the player's soldier). The attackers get across by swimming (bears, snakes, hippos, elephants), by riding on the pontoon rafts the hippos and elephants carry folded on their backs, put down and tow (two to a raft, or a rhino or a giraffe alone), by flying (the Sky Talons), or over the folding bridges they airdrop across the rivers (30 a match), which the defenders can cross and bring down too: see *Rivers and bridges* in the Attacker section. The attackers' main spawn is the **Mobile Command Citadel** at the south edge, a land carrier 50 m to the top of its masts and about 133 by 122 m, its hull modules in a cross on their outriggers, each arm about 40 m wide and 16 m tall (two vehicle decks, room for giraffes: the army rides in it); units come out in front of it; their forward spawns are the **Quarry** helipad west of the Keep (below a hillside quarry's benches) and the **Outpost** helipad east of it, across the east river: a giant one (`JungleLayout.OUTPOST_SCALE`, 5.2 times the standard base: its deck 204 by 158 m and 22 m up, 76 m to the mast tips), its pad's 70 by 63 m touchdown square big enough for the Heavy Lift Helicopter, rotors and all. The **prison** (a concrete fortress 42 m to the top of its watchtower, about 90 by 80 m) stands to the north on a plateau behind a 24 m cliff that faces the Keep; the plateau slopes down to the jungle round the cliff's ends. Four wooded ridges (22-44 m) rise near the corners and south-east of the Keep. The forest is the game's own scenery models at their real sizes: stands of oak (15-23 m, crowns spreading wider than they are tall), birch (13-22 m) and conifer (18-32 m) by turns, young trees under them, berry bushes and thickets, thickest along the forest's edge, tufts and tangles over the forest floor and the clearing's rough grass, and mossy rocks; about 70,000 in all. The whole forest counts as forest (Chimps swing through its trees, faster than they go on foot, the Sniper can't make units out in it without thermal sight, whose view sees through every plant), its 9,000 trees burn and Serpent Snipers nest in them; the bushes are bush traps. Units path round the big oaks' trunks and brush past the slimmer ones; they walk through the undergrowth. The army has a long way to go (550-650 m from the citadel to a gate), so the defenders hold for 15 minutes here. The RTS camera zooms out further, and flyers keep above the canopy.
- **Classic Field** (`LevelBuilder`): the 400 m open field described above, with its groves, lanes and the three edge spawns.

**Defender (first person)**
- `1`–`9`: take over a post (machine guns, mortar, riflemen) · `G`: the Gunner Squad · `Tab`: jump to the post with the most enemies nearby · `B`: buy an AA Squad · `N`: buy a Flame Squad · `M`: buy an Infiltrator Squad · `K`: buy a Sniper · `J`: buy the Fighter Jet · `H`: buy the Hover Tank · `F1`–`F6`: take command of a bought squad, Sniper, jet or tank · `C`: call a drone swarm to the post you're on (see *Defender drones*)
- Rifleman: `WASD` move, `Shift` sprint, `Space` jump, `LMB` fire, `RMB` aim, `R` reload
- Machine gun: mouse aim, `LMB` fire, `RMB` zoom; it overheats if you hold the trigger too long
- Mortar: `WASD` move the spotter view, `Q`/`E` rotate, wheel zoom, `LMB` fire on the ring
- Gunner Squad (third person): five Heavy Gunners, minigunners in heavy armor, posted in the south spawn hall. You drive the trooper in the middle; the other four follow it and aim and fire wherever you aim and fire. `WASD` move (relative to the camera; they walk any way while facing the aim), mouse aim, `LMB` fire (the barrels spin up first, and the guns overheat after about 7 s), `RMB` aim closer, `Shift` hustle (faster, no firing).
  - Formation: in the open a wedge with you in the middle, two troopers out ahead to either side and two wider behind, every gun with a clear line forward. Each spot is checked against the navmesh: inside a tree, a rock or a wall it slides to the nearest free ground, and it has to be reachable from you without a detour. When the spots don't fit the wedge squeezes in from the sides; in passages too tight for that the squad files along the way you came, two abreast where there is room (`PAIRS`) or in single file (`FILE`), and spreads out again once there is room. In a column the troopers walk in your footsteps in a fixed order, each keeping its distance from the one ahead, and the last ones out of a tunnel file out the way you came before peeling off to their spots in the wedge. The troopers walk round trees and rocks on the navmesh, never through them, and don't fire when a squad mate is in the line of fire. The squad panel (bottom left) shows the formation and a small map of the troopers and their spots.
  - Blast doors open for the squad as it comes up to them, so it can sally out through the south tunnel (or any gate) and back. Attackers still can't get in until a gate is broken.
  - If the trooper you drive falls, the one nearest it takes the lead (your camera glides over to it and the panel says so) and the others fall in on it just as they followed the first; a column keeps walking on down the same trail.
  - Coming up to a narrow way (the spawn ramp, a tunnel mouth) the squad checks for room just ahead of you and gets into file, in order, before it rather than crowding into it.
  - Left alone it walks back to its post and holds it (hitting softer, like the other posts' crews). Lost troopers are replaced one at a time from the post every 20 s; if all five fall, the squad is back after 30 s.
- AA Squads (third person): five Missile Troopers, Armored Sentinels with a six-missile pod on the left shoulder. They move, follow and file through tunnels exactly like the Gunner Squad (same keys, formation and camera); what differs is how they fight.
  - Buying: credits come in over time (400 to start, +6/s). `B` buys a squad for 350; it deploys in a gate spawn hall (east, west and south in turn) and joins the roster, the hotbar along the bottom of the screen, which shows each squad's troopers, its auto order and what it is doing. `F1`–`F6` takes command of a squad; `Ctrl+F1`–`F6` changes a squad's auto order without leaving the post you're on. Up to six squads. Lost troopers are replaced from the squad's hall, but once all five are down the squad is gone.
  - Air: hold `RMB` with the crosshair close to an enemy aircraft (within 6°, it needn't be dead on) and keep it there: after 3 s the box closing in on it turns red and the squad is locked on. `LMB` then launches seeking missiles from whichever pods are loaded, as many as the kill takes counting those already on their way (holding `LMB` keeps them coming while the lock holds). Letting go of `RMB` or losing the aircraft (past 13°) drops the lock.
  - Ground: `LMB` with the crosshair on the ground, or on ground units, is a rocket strike: every trooper fires three rockets at a spot of its own round the aim. The spots cluster round it 5.5 m apart, like the rhinos' bombs, instead of piling onto one spot; holding `RMB` shows them. Each rocket hits for 60 within 4.5 m.
  - Every missile or rocket empties a tube of its trooper's pod (six each); tubes reload one at a time, 2.5 s each, and the missiles reappear in the pod. The pods panel (above the weapon panel) has a pip per missile.
  - `F` mines: aimed like the hippo's smoke screen, a cone toward the crosshair with a green band at its tip; `LMB` and every trooper lobs two mines that land sparsely over the band (`RMB` or `F` cancels). They arm after a moment, blink, and go off under enemy ground units (aircraft pass over), 160 within 4 m. Ready again after 15 s. A squad keeps 40 down at most (the oldest are taken up). The attacking player never sees them (they aren't drawn on their side); only the Wolf Medics' noses find them, and a dog can dig one out and disarm it.
  - Auto orders (`V` while driving the squad, or `Ctrl+F<n>`), for when you aren't driving it:
    - MINES (a bought squad's first order): handed back out in the field, it lays mines where it is, then walks back to the base laying them on the path behind it whenever they are ready again; once at the base it lays them along the perimeter outside the gates, where the fewest are and away from the other squads.
    - GUARD: it stays where it is and only watches the sky.
    - Either way it locks on (3 s, like you) to any enemy aircraft within 85 m and shoots it down, and never fires at ground units.
- Flame Squads (third person): five Flame Troopers, the Crimson Warden with twin fuel tanks on her back and a flame gun at her hip. They move, follow, path round trees and file through tunnels exactly like the Gunner Squad (same keys, formation and camera).
  - Buying: `N` buys a squad for 300 credits (`B` an AA Squad for 350); like an AA Squad it deploys in a gate spawn hall, joins the roster (`F1`–`F6`, `Ctrl+F1`–`F6`) and is gone for good once all five are down.
  - `LMB`: every trooper burns where you aim, a jet of flame 6 m ahead (shorter where a wall, the ground or a trunk stops it). Attackers in it burn (90 a second) and keep burning for 2.5 s after. Burning runs the tanks' pressure down (14 s of flame from full); it comes back while you let go (6 s from empty). Run dry, the gun vents for 2 s. The pressure panel (above the weapon panel) has a bar per trooper.
  - Trees: hold the flame on a trunk for 8 s and the canopy catches, which destroys the tree. A quick sweep isn't enough: off the trunk for a moment, the heat drains away (the panel shows how close the tree under your flame is). A burning tree blazes, blackens and crumbles to a charred trunk, which falls about 30 s after the tree caught; then the way is clear (the navmesh is rebaked without it). Burnt trees never grow back, and a burnt-down part of a forest no longer counts as forest (Chimps lose their speed there).
  - Auto orders (`V` while driving the squad, or `Ctrl+F<n>`), for when you aren't driving it:
    - CLEAR (a bought squad's first order): it clears the forests round the base, closest to the base first and working its way outwards. It walks in formation to the standing forest tree nearest the base (one a little further out but much nearer the squad goes first, so it finishes a stand of trees before walking on). There the troopers spread out, each to a tree of its own nearest the base, and hold the flame on its trunk until it catches, then take the next. With none left in reach the squad forms up and walks on; with the whole forest done, on to the next forest. Lone trees out in the field are left standing. With nothing left to burn it goes back to its hall.
    - GUARD: it stays where it is.
    - Either way, attackers on the ground within 16 m come first: it forms up, walks at the nearest (on GUARD, no more than 6 m off its spot) and burns it, then goes back to its order.
- Infiltrator Squads (third person): five Infiltrators, the Harpy Vanguard in her training kit with a recurve bow, a deep infiltration squad for ambushes and sabotage. They move, follow and file through tunnels like the Gunner Squad (same keys, formation and camera).
  - Buying: `M` buys a squad for 280 credits; like the other bought squads it deploys in a gate spawn hall, joins the roster (`F1`–`F6`, `Ctrl+F1`–`F6`) and is gone for good once all five are down.
  - Passive, low profile: attackers never pick an infiltrator out on their own. Every other attacker with a basic attack shoots the defenders in its reach, never an infiltrator; only an attack the attacking player orders on one (`RMB` on it) goes after her. The CPU attacker never goes after them.
  - A Giraffe's ping (see the Attacker section) that catches an infiltrator out of camo reveals her: her low profile is gone and every attacker in reach goes after her on its own, the CPU's too. A radar icon hangs over her while it lasts (on your screen only, never the attacker's). It ends the moment the squad puts its camo on, or once she is back in the attackers' fog of war (out of sight of all their units). Caught under camo, she only leaves a blur on their radar.
  - `LMB`: every trooper looses an arrow at the aim (34 damage, then 1.3 s to draw the next). The bow is silent: no tracer, no flash where it lands, so the attacking player has to notice their units' health running down and react to the ambush.
  - `Q` adaptive camo: 20 s of camouflage for the whole squad, ready again a minute after it went on. Basic attacks can't target the troopers: shots pass through them and orders to attack them lapse (or are refused). They can still shoot, but the first arrow loosed gives them away: the camo comes off the whole squad (CAMO BROKEN), and the cooldown runs on as it was. Area damage still hurts and kills them: bombs, shells, cluster bombs, rockets and strafing runs aimed at the right spot. On the attacker's side they vanish (not drawn at all, no shadow); on the defender's they look as ever and the squad's camera gets a steady vignette while it lasts.
  - `F` sabotage: next to a Forward Helipad the attackers hold (within 4 m of its deck), the squad sabotages it. It takes 45 s with the leader staying that close (`F` again calls it off; walking away loses the work); then the attackers lose control of the helipad until they retake it. Each squad carries one sabotage kit: used, it has to go back into the fortress (in through a gate) to restock it. The panel above the weapon panel shows the bows' draw, the camo, the kit and the work under way.
  - Auto order (`V` while driving the squad, or `Ctrl+F<n>`): HOLD, or a sabotage operation against one of the helipads the attackers hold (`OP S`, `OP E`, `OP W`). Left to itself on HOLD it stays where it was left and does nothing. On an operation (its idle mode) it heads out through the gate nearest the helipad and makes for it by a route that keeps as far from the attackers as it can while still heading there, planned again every second as they move, up to the side of the deck where the fewest are; it sabotages it and comes home to its hall, restocking its kit (out of kits, it restocks first). It never shoots or puts its camo on by itself.
- Sniper (third person): one marksman, not a squad: the Grey Veil Warden in her ghillie cape with the Eclipse Longshot.
  - Buying: `K` buys her for 220 credits; like the bought squads she deploys in a gate spawn hall, joins the roster (`F1`–`F6`, a single pip on the hotbar) and is gone for good once she falls (300 HP).
  - Driving her: `WASD` move, mouse aim, the camera close over her right shoulder. `RMB` brings the scope up to her eye: first person through it at 8x, the wheel stepping through 4x, 8x and 12x, with a duplex reticle (a red dot where the round goes), the magnification and the range to what it is on either side of the lens. She walks slowly with it up.
  - `LMB`: one round (140 damage, dead on through the scope, a little loose from the hip, out to 400 m), then she works the bolt (1.5 s); five rounds a magazine, `R` reloads (2.8 s). Every round streaks out as a long bright tracer and leaves a white trail along its path that hangs for 1 s, then fades; both sides see them.
  - Tags: every attacker her rounds hit is tagged for 20 s. A red aim icon hangs over it, on the defender's screen and the attacking player's; every defender (posts and squads, not only her) hits it 20% harder; and a tagged Armored Lioness can't sneak (a tag also ends a sneak under way). She keeps up to five tags out at a time (the five slots in her panel, each running down): while all five are out, a hit on another unit tags nothing until one of her tagged units dies or its tag runs out. A hit on a unit she has already tagged starts its 20 s over.
  - `T` thermal vision: 15 s of it, then a minute to recharge (`T` again switches it off early). The land goes dark and cold, every attacker glows white-hot and the trees turn see-through, so she makes out attackers in among a forest's trees as clearly as in the open. It shows on her view only (third person or the scope).
  - Left alone (you take another post or squad), she holds the very spot where you left her (where she deployed, if never driven). She picks one attacker within 160 m that she can see and that isn't inside a forest (without your thermal sight she can't make them out among the trees) and shoots it until it falls (105 a round), however close another comes, so she tags only it; then she picks the next. One that stays out of her sight for 8 s (behind cover, into a forest, out of reach) she lets go.
- Fighter Jet (third person, chase camera): the defenders' **Defender fighter jet** (18 m long, 20 m span), one machine on the roster like a squad: it has a slot on the hotbar (`F1`-`F6`), the attackers shoot at it, and once it is gone it is gone for good.
  - Buying: `J` buys it for 600 credits (the roster's six slots are shared with the squads). It scrambles into the air out in front of a gate hall's face, at 130 m and already at cruising speed (120 m/s), and never lands.
  - Flying (mouse-aim, like an arcade flight game): the mouse steers where the nose is going (the ring on the screen is what you steer at; the jet banks and turns onto it as fast as it can, the faster it flies the wider it turns), `W`/`S` pitch (`W` dives) and `A`/`D` turn if you'd rather use the keys, `Space` the airbrake (down to 85 m/s). Diving gains speed and climbing sheds it. `Shift` is the speed boost: the afterburners take it to 200 m/s, the camera pulls back and the view widens; 4 s of boost from full, 7 s to come back once you let go (and a spent boost needs 30% before it lights again).
  - **Crash and you lose it**: into the ground, the forest canopy (over the jungle, below 20 m over the trees), the mountain or any structure and it blows up (240 within 12 m to whatever is under it) and is gone for good. Ahead of a collision the panel flashes PULL UP. Past the edge of the battlefield it is called back (TURN BACK, 7 s) and lost if it won't turn. The attackers' anti-aircraft (the War Elephants' flak, the Combat Rhinos) fire at it too: 700 health; shot down it spins out of the sky, burning, and crashes.
  - `LMB` bomb: one bomb from the bay (4 carried, one comes back every 8 s, 0.4 s apart at the least): 380 within 11 m, and it bursts on the first thing it meets (the ground, a structure, an attacker). Real bomb physics: it leaves with the jet's own velocity and falls under gravity and drag (a terminal speed of 210 m/s) with its nose swinging round into the airflow, so it lands far ahead of where you let it go (at 120 m/s and 110 m up, some 520 m ahead; at 200 m/s, 850 m; the faster and higher, the farther). **The aim is a preview on the ground**, like the Bisons' bombardment aim: a dashed ring the size of the blast where the bomb would land if you let go this instant, the arc it would fall along, and a column of light over the ring; it follows the jet in real time as it flies, and a diamond with the distance marks the spot on the screen (kept on the screen's edge, with an arrow, when it is off it). It is the same fall flown ahead of time (`JetBomb.predict`), so the bomb lands where the ring said, to the centimetre.
  - `RMB` missile barrage: a salvo of 16 missiles from the six wing pylons, one every 0.06 s, then 11 s to reload. Simple aim: each missile flies straight out along **where the nose points at the moment it leaves**, carrying the jet's own speed (unguided; the motor takes it to 270 m/s, a kilometre or so out). Flying straight and level the whole salvo goes up one line in a tight bunch (under a degree apart); **manoeuvring through the salvo each missile goes where the nose is by then**, so they scatter over the area the nose swept (and the harder the jet is turning the wider each one strays too). Each hits lightly (30, and a small splash of 4.5 m): the strength is in the numbers.
  - Left alone (you take another post, or it has just been bought) it flies itself, a gunship's way, and the roster slot says what it is doing:
    - ORBIT: it circles the spot where you left it, a left-hand pylon turn 230 m round at 100 m/s (a gentle bank), at the height you left it at (between 120 and 240 m). The circle goes through that spot, so it flies straight onto it. **Passive:** it fires on nothing, enemies nearby or not, until it is attacked.
    - Attacked means it is hurt, or an enemy has locked on to it (a War Elephant's or a Combat Rhino's anti-aircraft lock: the only ones that reach a jet up there; riflemen and the rest can't). It bombs the attacker; hurt with nobody locked on, the nearest anti-aircraft enemy within 160 m (else the nearest enemy within 130 m) that it can bomb: on the ground, not flying or in the water, not up inside the mountain.
    - BOMB RUN: out to the start of a run 700 m from the attacker (so it comes in pointed at it, level at 110 m, slowed to 85 m/s); a bomb carries a long way (375 m from there), so it lets one go when the live forecast of where it would land (the preview's own, `JetBomb.predict`) crosses the attacker's spot, led if it is moving, and only if it is lined up to within 9 m; then it breaks away 75° off the attacker, so it doesn't fly over its flak. Once the bomb has landed, if the attacker still stands and it has bombs, round for another run, up to 3 passes.
    - RETURN: with the attacker destroyed (or out of bombs and passes) it flies back to the spot where you left it, level, and circles there again, passive, until the next attack.
- Hover Tank (third person): the defenders' **Iron Vanguard** hover tank (10 m with its gun forward, 6 m wide), the other machine on the roster.
  - Buying: `H` buys it for 450 credits; it deploys on the ground outside a gate (a hover tank is too broad for the halls' ramps), 1100 health.
  - Driving, like the squads, relative to the camera: `WASD` goes where the camera looks (left, back, right), the hull turning round onto the way it goes (backing off, it reverses instead of turning right round, so the gun stays on the front). 15 m/s. It hovers on its air cushion, so it skims the rivers and the lake as it does the ground, but it is broad: trees, rocks, walls and the mountain stop it, and so do slopes steeper than it can climb.
  - Mouse: the turret and the gun follow the crosshair, as fast as the turret traverses (the gun is stabilised: the barrel holds its line against the hull's sway on its air cushion). `LMB` the main gun (3.2 s to reload): 220 within 7 m. It fires only once the barrel is laid on the crosshair's point to within 0.6 m *at that distance* (0.57° at 60 m, 0.08° at 420 m): far shots come down at a shallow angle, so a small error in the barrel is a long way on the ground, and the HUD says TRAVERSING until it is laid.
  - **The shell flies dead straight for its first 200 m, then gravity takes it.** It leaves at 240 m/s. Inside 200 m there is nothing to allow for: a target there is hit where the crosshair is (0.1 m off at 150 m in the checks). Past 200 m real gravity bends it down: 0.2 m under the barrel's line at 250 m, 0.9 m at 300, 4 m at 420, 14 m at 600, 31 m at 800. So for a far target the crosshair has to be held above it: aimed straight at a ground target 420 m out, the shell comes down about 115 m short; the barrel needs to be raised 0.56° (a few pixels) to hit. The left-alone AI works out the elevation itself (`TankRound.elevation_for`).
  - **The tracer is the shell and a short streak behind it**, like a real tank round's: a bright head, and a streak 14 m long that glows orange-hot at the shell and fades to nothing at its tail (the game's `ThrusterFlame` cone, as on the missiles). It is not drawn along the whole flight.
  - Hold `RMB` for the twin machine guns in the sponsons on its sides (8 a round, 20 rounds a second). **They don't follow the crosshair**: they fire straight ahead where the hull faces (toed in and down to cross 70 m out, 1 m over the ground, a mark on the screen shows where), so you aim them by turning the hull, and the turret can be on something else. Every other round is a tracer, a bright streak drawn out to what it hits, and it leaves a line of fading embers along its path (half a second), so the line the guns are firing along stays drawn on the air even when the round itself is a speck.
  - `Space` **jump**, for a sticky situation (10 s cooldown): the thrusters charge for 0.45 s (the hull squats, the hover jets flare into afterburners, dust blows out from under each), then throw the tank up and along where the hull faces in an arc, 12 m high and 55-57 m far, about 3 s in the air. It can't be steered, its guns work as ever. Coming down the jets fire again, a retro burn that slows the fall to about 3 m/s (18 without it) with another burst of dust, the hull squatting to take the shock. The landing looks for clear ground: over the stronghold's wall or a tree it would come down in, it sets down in front of them; a wall in the way in the air stops it.
  - **Trees stop it.** It runs into a tree and stops dead, like a small crash: 45 to 95 health (the faster, the more), the hull rocks, the camera shakes, and it is stunned for 1.4 s. The tree goes over (`ForestTree.knock_down`), taking 3.8 s, and its trunk blocks until it is down; then the way is clear (a felled tree lies where it fell, and the navmesh is rebaked without it, like a burnt one). It can be done, but not well: in the checks, 200 m of forest of median density took 33 s where open ground takes 15, and cost 376 of 1100 health. It stops at a tree however it hits it (no sliding past), in the air too.
  - Left alone it holds where it stands and fights what comes within 110 m on the ground, the cannon and (within 65 m) the machine guns.
- Posts you aren't controlling keep fighting on their own; dead posts come back after a short delay
- Flash grenades (the Kangaroo Commandos'): a post or trooper within 10 m of the bang that has it in sight is blinded for 2 s, and left to itself it can't fight (the guns, the mortar and the riflemen hold their fire, a squad's troopers too, and an AA Squad drops its lock). If it catches the post you are on, your screen goes full white for 2 s, then clears.
- Serpent Snipers (the attackers' snakes): one coiled round a bush is 70% see-through, with no shadow and no health bar, like a sneaking lioness. Come within 4 m of the bush and it strikes: caught in its coils you can't move or fire, and your health runs down until you die 15 s later, unless someone shoots the snake dead first (you go free with the health you have left). Up a tree it lies on top of the crown and snipes from further than it can on the ground.
- AA turrets: two on every roof, on their own (nobody takes them over). Each turns to the nearest enemy aircraft it can see within 45 m, locks on (1.2 s) and fires a homing missile at it every 3 s (18 damage), Sky Talons on their attack runs included. 150 HP: a bison's shell or a talon's bomb takes one out; it is rebuilt after 75 s.

**Attacker (RTS)**
- Fog of war: your army only sees what is round it (each unit as far as its sight, 26–50 m; the Giraffe 75 m; a Serpent Sniper up a tree 83 m; a helipad you hold 26 m round its deck). The stronghold and the land are known, but outside sight they are dimmed, and the defenders' soldiers and squads there aren't shown at all. Nobody picks out a defender in the fog, and you can't order an attack on one, even one in range (so long-range units need a spotter); the gate guns, the mortar and the AA turrets stay on the map. Raiders inside the stronghold hunt as ever. The CPU attacker plays by the same fog.
- `LMB` click/drag to select, `Shift` to add · `RMB` attack-move, or attack a gate/defender you click on · `Ctrl+RMB` move without stopping
- Spawn: `Z` Bear Rifleman · `C` Wolf Medic (heals, or sweeps for mines: see below) · `N` Mule Artillery (a siege gun that has to be set up: see below)
- `V` Sky Talon (the hawk): flies over the mountain, and flies like a hawk.
  - It glides most of the time and beats its wings only now and then, a few strokes every few seconds (gliding it sinks a little, less while it circles and soars, and the strokes lift it back up), and all the way up on take-off or climbing over the mountain. It banks into its turns.
  - It never hovers: wherever it has nowhere left to go, it circles. Sent somewhere (or at a target), it circles the spot counterclockwise, the centre off its left wing, like a gunship flying a pylon turn.
  - Rings stay level and clear of the ground: next to the mountain a ring moves out in front of the face (and tightens) until it is. Each talon flies a ring of its own (up to 8 m wider) at a height of its own (spread over 12 m), so a flock sent to one spot stacks up instead of flying through itself. Flying on, it looks ahead and climbs over the mountain in time.
  - No basic attack and no passive: it attacks with two skills, each reused after 90 s. `F` and `G` aim them when the selection has no ready rhinos (`F`) or bisons (`G`), whose skills come first.
  - `F` strafe run, like an A-10's: press `LMB` on the target and drag the way to fly, let go to fire (a click flies it from the talons to the target; `RMB` or `F` cancels). The line is 26 m long and has to lie inside the talon's circle (80 m round it). Several talons fly parallel lanes 7 m apart, side by side in the order they are in across the line; a lane that doesn't fit its talon's circle slides along itself until it does. Each talon flies round behind its lane, lines up, dives in along it firing ahead of itself, so its rounds walk down the lane (18 damage within 2.5 m each, about 40 of them), then pulls up and breaks away from the mountain.
  - `G` bomb strike: `LMB` a spot (`RMB` or `G` cancels). Each talon flies over its spot and drops one bomb (260 within 7 m, full damage against gates). Several talons' bombs land round the spot 10.5 m apart like the bisons' shells, up on the gun decks and roofs too. Against the mountain a talon slants in along the face instead of flying into it.
  - The runs fly round the stronghold, never into it: each plans its height along the whole pass from the ground under it, low over the target and always high enough to climb over the deck, the roof or the mountain ahead, and where the mountain blocks a straight run-in (a line along a face) it comes in at an angle from the open field and turns onto the line. Once on a run it flies it through, whatever its orders.
  - It is not invincible on a run: the AA turrets and the machine guns shoot at it. Take the turrets out first (bisons can, from beyond their reach).
- `B` War Elephant: the real anti-air unit. Heavy and slow, with no basic attack. On the Jungle Keep it tows a raft for riders (see *Rivers and bridges*).
  - Passive flak: the cannons on its flanks swing up at one enemy flyer in its dashed ring (26 m) and stay on it until it dies or leaves. They take turns firing shells that burst around it. One elephant hits about as hard as five rhinos.
  - `O` missiles: then `LMB` an enemy aircraft (`RMB` or `O` cancels). The pods lift and eight homing missiles leave one after another (range 60 m, reload 25 s). With several elephants selected, only as many fire as it takes to bring the target down, counting missiles already on their way to it, nearest first. The rest stay ready and you keep aiming, so you can click the next target. If all of them together can't kill it, they all fire. The cursor says how many will fire.
- `I` Combat Rhino: tanky and slow, with no basic attack.
  - Passive anti-air: locks onto one enemy flyer in its dashed ring and stays on it until it dies or leaves. One rhino is weak; it takes about five to bring a flyer down fast.
  - `F` cluster bombing: aim, then `LMB` to fire (`RMB` or `F` cancels). Each rhino shells a spot inside its 40 m zone for 8 s. Cooldown is 45 s. With several rhinos selected, the preview shows where each one's bombs will land. Rhinos that were moved together keep their formation's shape. Scattered rhinos aim as close to the cursor as their zones allow and spread around it instead of piling onto one spot.
  - `T` scout formation: with rhinos and other units selected, the rhinos ring the outside of the group so their anti-air covers it. Orders to the whole group keep the ring. Ordering a rhino on its own takes it out of the ring, and `T` again turns it off.
- `L` Bison Field Gun (two bisons with an artillery gun slung between them): slow, with no basic attack and no passive.
  - `G` bombardment: aim, then `LMB` to fire (`RMB` or `G` cancels). The bisons stop, lay the gun and fire one heavy shell at a spot up to 80 m away, twice the rhinos' reach. It hits for 240 within 6 m and reloads in 40 s. They carry on with their order once it has fired.
  - The shells come down where the cursor is, up on the gun decks and the roofs too, so the bisons can wreck the machines (the gate machine guns, the mortar) and the soldiers on them from out in the field. The preview shows each bison's range and the blast where its shell will land.
  - With several bisons selected, the shells cluster round the cursor 9 m apart like the rhinos' bombs, instead of piling onto one spot. Up on a deck or a roof, the spots on that level go first, so the shells spread along the deck instead of dropping off its edge.
- `N` Mule Artillery (six donkeys in harness, in three pairs, towing a tracked siege gun with a very long barrel): like the Bison Field Gun, no basic attack and no passive, but super slow (1 m/s; it turns like a wagon, the team walking round) and its gun has to be set up before it can fire.
  - `T` (with no rhino, lioness or dog selected) or the `Guns:` button sets the selected mules' guns up: the team halts and looks up while the barrel rises out of its travel position to 40° (7 s). `T` again disarms them (7 s, the same in reverse, the turret swinging back to the front). It can't move while it sets up, while it is armed or while it disarms: orders to move are refused, except one given while it disarms, which it carries out once disarmed. Changing your mind halfway (`T` again), it goes back the way it came from where it got to.
  - Armed (the donkeys graze), `G` bombardment as for the bisons (aim, then `LMB`; armed mules and ready bisons fire together): the turret swings round onto the aim (40°/s, any way round, the team standing as it is), and one shell leaves the raised muzzle. One shell every 30 s, out to 150 m (the bisons' 80), 480 within 11 m (the bisons' 240 within 6 m), up on the gun decks and roofs too. Several mules' shells cluster round the cursor 16.5 m apart.
  - The CPU brings a mule on odd waves from the third: it sets its gun up as soon as the stronghold is in reach and shells the gate guns and the mortar, then the defenders it sees, then the gate and the AA turrets; with nothing in reach for 20 s it disarms and moves on.
- `K` Hippo Heavy Gunner: heavy, slow, sprays suppressive fire from mounted machine guns. On the Jungle Keep it tows a raft for riders (see *Rivers and bridges*).
  - The guns are inaccurate: rounds land around the target and can hit whatever stands next to it. They fire for 8 s in total (resting cools them at the same rate), then overheat and go silent for 2 s.
  - `R` smoke screen: aim, then `LMB` to fire (`RMB` or `R` cancels). The cone shows where the curtain will stand (the green band at its tip). The hippo fires three grenades at once. Each one bursts high up, then drops and bursts twice more on the way down, leaving a tall pillar. Together the pillars make a curtain that blocks line of sight for both sides for 30 s. Cooldown is 90 s. With several hippos selected, the one closest to the cursor fires.
- `M` Breaching Ram (big horn sheep): breaks gates, and with the Chimp and the Kangaroo Commando the only units that can get inside the stronghold.
  - Basic attack: shotgun. Each blast throws 7 pellets into a small cone in front of it (range 7 m).
  - `Space` ram: a surge of speed (2.2×) for 6 s. Cooldown is 60 s. Enemy soldiers it runs over lose health and are tossed out of its way.
  - Gate charge: `RMB` a ground gate while ramming, and the rams line up across its doorway and slam into it once each for a heavy hit (350). Only 3 fit in front of a doorway at a time: the nearest ones that can still get there before their ram runs out take the places (rams already charging it keep theirs). The rest call their ram off and go at the gate with their shotguns.
  - Infiltration: once a gate is down, `RMB` next to it sends selected rams in. Like the Chimps, inside you lose control of them. They make for the Keep on their own and fight every defender they run into on the way (within about 18 m, up the stairs to the gun decks too), ramming soldiers whenever the ram is ready and finishing them with the shotgun.
- `J` Night Ops Chimp: fast melee fighter, and with the Breaching Ram and the Kangaroo Commando the only units that can get inside the stronghold.
  - Basic attack: melee, it strikes whatever is within arm's reach.
  - Passive: moves 60% faster inside forests, because it goes through them up in the trees: moving through a forest it leaps up into the branches and swings from hold to hold, hand over hand (the right hand hooking its axe over the branch), up under the canopy (about a third of the trees' height up, 3.4-6 m). Where the trees end, or when it stops (to fight, or once it is there), it drops back down to the ground and goes on foot, slower. Up there it is shot at where it is: its health bar, the defenders' aim and its hitbox go up with it. Shot down out of the trees, it falls.
  - Infiltration: once a gate is down, `RMB` next to it sends selected Chimps in. Inside, you lose control of them. They hunt the defenders anywhere in the stronghold, climbing to the gun decks and up the ladders to the roofs. When no defender is left standing, they wreck the machines: the gate machine guns and the mortar. Respawned defenders draw them back.
- `X` Kangaroo Commando: fast, and with the Breaching Ram and the Chimp the only units that can get inside the stronghold.
  - It moves like a real kangaroo: it hops on both hind feet together, its tail swinging against the legs and its forepaws tucked in at the chest. Like a real one it hops at about the same rate whatever its speed, taking longer bounds instead.
  - Basic attack: the two SMGs mounted on either side of its chest fire short bursts (4 rounds), the guns taking turns. At a target above it (up on a gun deck) it rears its chest up to bring them onto it.
  - `R` flash grenade: aim, then `LMB` to throw (`RMB` or `R` cancels); with a selected hippo's smoke screen ready, `R` aims that first. Each kangaroo stops, stands up tall like a boxer (propped on its tail) and lobs a grenade up to 26 m. It goes off on landing in a white flash: every defender within 10 m that has it in sight is blinded for 2 s, and the defending player's screen goes full white if the post they are on is caught. Cooldown is 30 s. With several kangaroos selected, the grenades cluster round the cursor 15 m apart like the bisons' shells, instead of piling onto one spot, up on the gun decks and roofs too; the cursor on a defender up on a deck puts them at its feet. The preview shows each kangaroo's throw and where its flash will reach.
  - Passive, supplies: each kangaroo resupplies up to 3 units within 9 m whose skills are cooling down (other kangaroos included, itself not): their skills come back 15% sooner. A small ammo box floats over every unit it resupplies. It doesn't stack: a unit next to several kangaroos still gets 15%, and the kangaroos share out the units round them, each taking its nearest, so two kangaroos look after six.
  - Infiltration: once a gate is down, `RMB` next to it sends selected kangaroos in. Like the Chimps and Rams, inside you lose control of them: they hunt the defenders (up the stairs to the gun decks and the roofs too), shooting them with their SMGs and flashing them whenever a grenade is ready.
- `H` Savanna Signal Scout (the Giraffe): a scout with a radar dish and antennas on its back. It walks like a giraffe, nearly pacing (each fore leg swinging just after the hind leg on its side), the body rolling over the side that is down, the neck pumping with every step.
  - Passive: none, but it sees furthest of any unit (75 m), deep into the fog of war: walk it ahead of the army to spot for it.
  - Basic attack: light fire out to 30 m.
  - `P` ping: it stands, stretches its neck up and sweeps its dish, and sends out a sonar pulse that spreads to 60 m round it (40 m/s). Every defender soldier and squad trooper the pulse reaches is marked by a red blur on the spot where it stood the moment the pulse got there, like a contact on a sonar screen: the blur stays put and fades over 7 s, it doesn't follow them. It finds infiltrators under adaptive camo too (a blur, no more). An infiltrator caught out of camo is revealed: she loses her low profile and your units go after her on their own like any defender, until she goes under camo or slips back into the fog of war. Cooldown is 45 s; a selected giraffe shows how far its ping reaches. The CPU's giraffes ping whenever they are out on the field.
- `Y` Armored Lioness: a lioness in armour with two flamethrowers mounted on her back. She walks like a cat (each fore paw lifting just after the hind paw on its side lands, the shoulders and hips rolling over the side that is down) Sent somewhere (any move order), she walks for 4 s, then breaks into a gallop (up to 6 m/s); every new move order starts the walk over.
  - Basic attack: melee, claws and teeth. She rears up and swipes down at whatever is within her reach (2.6 m), biting as she comes down (28 a blow).
  - `F` sneak (when the selection has no rhino or talon skill ready, which come first): 10 s of stalking, belly low, eyes on the prey, no faster than 2.6 m/s. On the defender's side she is 70% see-through, with no shadow and no health bar; on yours she looks as ever, with a bush icon over her. While it lasts she picks no fights on her own. `RMB` a defender on the ground: she stalks up to within 12 m of it and pounces, sinking onto her haunches, springing and landing on it (70 damage), then mauls it with her claws. The sneak ends the moment she springs (or strikes, or lights her flamethrowers, or is tagged by the defenders' Sniper): she shows again. A tagged lioness can't sneak at all until the tag is gone. Cooldown is 50 s.
  - `G` fire blast (when no bison or talon skill is ready): the flamethrowers on her back burn a cone in front of her for 3 s, 8 m out: 60 damage a second to every defender in it, and they burn on for 2 s. She can move while they burn, the cone always pointing where her face looks. It ends a sneak. Cooldown is 45 s. Her flames never set trees or any other vegetation alight.
  - Firing lines: two or more lionesses moved together (`RMB` or `Ctrl+RMB` on the ground) converge into line as they go, like the line infantry of the American Revolution and Napoleon's wars: up to 8 abreast, and more lines of up to 8 one behind another (18 make lines of 8, 8 and 2), each centred and facing the way they go. The line advances at 85% of its slowest lioness's speed (slower while they sneak); the ones behind run to catch up, the ones ahead hold back, and they come into line on the way without stopping to form up. At the end they stand on their spots facing the way they went. Other units moved with them gather behind the lines. `T` (with no rhino selected) or the `Firing lines` button (it shows while lionesses are selected) turns lines off and on: off, they go as a pack like any other units.
  - The CPU brings lionesses from its second wave on: they hunt the defenders on the ground the army sees within 32 m, sneaking up to pounce whenever the sneak is ready, and light the fire blast up close.
- `C` Wolf Medic (the dog): no basic attack and no passive. It has two modes and one of them is always on: `T` (with no rhino or lioness selected) or the `Dogs:` button switches the selected dogs between them, all to minesweeping unless they all sweep already. A new dog comes healing.
  - Healing: it heals up to 2 hurt units within 10 m at once, a little at a time (12 HP a second each), on the move too: a green beam runs to each and a medic's cross floats over it. It sticks to the units it took until they are full or leave its reach, however hurt another unit next to it is; only then does it take the next (the nearest hurt one). Like the kangaroos' supplies it never stacks: a unit is healed by one dog at a time, so two dogs heal four. A selected healing dog shows its reach (a dashed green ring).
  - Minesweeping: the AA Squads' mines are hidden from you, and they go off under your units all the same. A sweeping dog smells out every mine within 18 m (its dashed amber ring, selected), walks up to one and digs it out, disarming it in 6 s: it digs with its fore paws in turn, rump up and nose down, the dirt flying back under it. While it digs, that mine shows to you, with a ring round it filling as the work goes on; disarmed, it lies tipped on the edge of its hole. A dog never goes near a mine to get to another: it only takes a mine it can reach by a way that keeps clear of every other live one, so it can't get at one inside a minefield until the mines round it are out, and it takes the minefield's outer rim first (the edge of what is left, then the next ring in), never a mine deep inside it. Dogs sweeping together share the field out, a mine each, and dig side by side. A sweeping dog sweeps while idle or attack-moving (`RMB`): it stops for the mines it finds on the way, waits where its way would take it close to one the pack hasn't cleared yet, and walks on once the way is clear. A plain move (`Ctrl+RMB`) calls the digging off and takes it on regardless.
  - The CPU's dogs heal. It can't see the mines either, but one going off under its army tells it a minefield is there: the dogs within 40 m of the blast switch to minesweeping, and back to healing once they have found nothing to dig for 20 s.
- `U` Serpent Sniper: a 5 m anaconda in a helmet and a vest, an anti-materiel rifle strapped along its back. It slithers, a wave running down its body from the shoulders to the tail while the gun stays straight and level.
  - Basic attack: slow and hard-hitting. One rifle round every 4 s, 95 damage out to 46 m (40% of that against gates), the barrel kicking back with a long tracer and a puff of smoke; like the defenders' Sniper's rounds, each leaves a white trail along its path that hangs for 1 s, then fades.
  - `F` sniper nest (when the selection has no rhino, talon or lioness skill ready, which come first): `LMB` a tree (`RMB` or `F` cancels). It goes to the foot of the trunk, rears up the bark and winds its way up into the crown (8 s), then lies out on top of it, the rifle over the leaves, turning round the trunk to aim. Up there it sees 80% further (83 m) and its rifle reaches 60% further (74 m). A tree-and-rifle icon hangs over it once it is all the way up (on your screen only). It can't move while in the tree: any order to go somewhere starts the climb down (8 s), then it goes; `RMB` on a defender it shoots from up there. One snake to a tree: several sent at one take the free trees nearest it. A tree set alight brings it down.
  - `G` bush trap (when no bison, talon or lioness skill is ready): `LMB` a bush (`RMB` or `G` cancels). It pushes its rifle in under the bush, hidden there (the bushes are 2.8–3.3 m across), and coils round the bush (8 s), and lies in wait: it never shoots while coiled. A defender on the ground who comes within 4 m of the bush (a soldier or squad trooper, not an infiltrator keeping her low profile) it strikes, darting out and winding round its prey like an anaconda. Held in its coils, the defender can't move or fight and loses health steadily until it dies 15 s later. The squeeze can't be called off (the snake takes no orders until it is done); then it lets go and coils round its bush again. Meanwhile it can be shot: killed before the 15 s are up, it lets its prey go with the health it has left. Any order uncoils it (8 s), and it picks its rifle up before it goes. Coiled round a bush it is 70% see-through on the defender's side, with no shadow and no health bar, like a sneaking lioness; on yours it looks as ever, with a tall-grass-and-snake-head icon over it once it is all coiled.
  - The CPU brings Serpent Snipers from its third wave on. They climb a tree near their way from which the gate is in their reach and snipe from the crown; otherwise they lie in wait round a bush where the army saw the defenders out on the field lately. They come down (uncoil) and go on once nothing has come their way for a while.
- Sniper tags: a unit the defenders' Sniper hits is tagged for 20 s (she keeps up to five tagged at a time). A red aim icon hangs over it on your screen too; defenders hit it 20% harder; and a tagged lioness can't sneak (`F` leaves her out, and the selection panel says why). The tag runs out, or goes with the unit. Her rounds' tracers and white trails show where she is shooting from. A forest hides your units from her: left to herself she never picks one in among the trees, and the player driving her makes them out clearly only with her thermal sight (15 s of it, then a minute to recharge).
- Forward Helipad Bases (`S Pad`, `E Pad`, `W Pad` on the classic field; `Quarry` and `Outpost` on the Jungle Keep, whose main spawn is `Main`, the citadel): a deck on stilts with a helipad and the camp round it, one out by each attack lane. While you hold one it is a forward spawn point (its button on the spawn row) and brings in +1.5 supply/s. It can't be shot down, but the defenders' Infiltrator Squads sabotage it: then you lose control of it (no spawning there, no supply; it smokes and a dashed ring marks where to stand) until you retake it: ground units within 10 m of its deck for 15 s (sooner the more there are, up to four), with no defender that close (CONTESTED). The CPU attacker spawns its waves at the side's helipad while it holds it and sends the nearest units to retake a sabotaged one.
- Rivers and bridges (the Jungle Keep, `game/scripts/match/jungle/river_crossing.gd`, `folding_bridge.gd`): the water is too deep to wade and walled along its edge.
  - Swimming: Bear Riflemen, Serpent Snipers, Hippo Heavy Gunners and War Elephants swim across the rivers and the lake. Sent anywhere across the water they path over it by themselves: down the bank, out into the deep water with only their heads and backs showing (ripples spreading off them), and up the far bank (2-2.8 m/s in the water). A hippo swims with its whole head over the water; an elephant swims deeper, its trunk raised up out of the water like a snorkel so it can breathe, lowering it again on the far bank. Out in the water swimmers move aside to keep clear of one another and of the rafts, and come back onto their way by the far bank. A swim costs 2.5 times its length against walking, so a bridge close by is taken instead.
  - Bears swim like bears: a dog paddle, the body low in the water and the head held up out of it, the fore paws paddling by turns (the water churning in front of them, one paw and then the other), the hind legs kicking. Out in the water a bear slings its LMG across its backpack and takes it in its paws again on the far bank.
  - Diving: `F` (with none of the other units' `F` skills ready) dives the selected bears out swimming: down under the water for 10 s, still swimming on their way across (the Dive stroke, the body level), then up again (`F` again after 35 s). Down there a bear is out of the defenders' sight: none of them picks it out (no line of sight through the murky water), the ones that were firing at it lose it, it throws up no ripples, and on the defender's side of the screen nothing shows of it, not even its health bar. The attacking player sees it by its pale blue silhouette through the water. It isn't safe, though: a round that goes into the water where it is still hits it (a miss at something on the surface over it, or a shot at where it was), and so does a shell bursting close by. The CPU's bears dive when they are shot at out swimming. It is the one skill a unit can use while it crosses.
  - Rafts: every hippo and elephant carries a pontoon raft (a deck on six float drums, 6 m long, `game/scripts/units/tow_platform.gd`), folded up: on a hippo's back, hung on an elephant's rump (under its missile pods' hinge). Folded, its three deck sections lie one over another, their frames folded flat, its railings laid down and its floats empty. When riders come for it, the carrier puts it down: it is tipped off over its rump onto the ground behind it, the deck sections swing open (the rear one, then the front one), the frames unfold, the railings come up and the floats blow up full, in 1.25 s; then the riders climb on. Out, it trails the carrier on a tow line like a trailer round the corners, slides along on its floats on land and floats out on the water, rocking a little. Once the crossing is done and its riders are off (or nobody came for it after all), it comes apart on the bank: the floats go flat, the deck falls apart into its sections onto the ground with the empty floats beside them, and the pieces fade away, in 2.6 s. By then the carrier has a fresh raft folded on its back.
  - Riding: every other ground unit but the Mule Artillery and the Bison Field Gun climbs onto a raft to cross: two at most on each, one ahead of the other. A Combat Rhino or a Giraffe rides too, but alone: it only gets onto an empty raft, and nobody joins a raft with one on it. Send them across together with the carriers (`RMB` beyond the river) and the riders that can't walk there climb on by themselves, the nearest first, the carriers waiting for them; the ones left over with no place go as far as the bank. Or `RMB` a hippo or an elephant with riders selected and they board its raft. Out of the water on the far side the riders get off over the raft's sides and go on to their own spots; `Space` (with no ram selected) lets the selected carriers' riders off on dry land. A carrier killed out on the water takes its raft and its riders down with it: they can't swim. Killed on land, its riders get off and its raft comes apart where it is (a folded one goes down with the carrier).
  - Swimming or riding a unit can't attack or use its skills (the skill keys leave it out; but the bears' dive): it is completely vulnerable. The selection panel says how many are crossing, how many riders the selected carriers have, and the selected bears' dive.
  - The Mule Artillery and bisons cross by a bridge or not at all. Sky Talons fly over.
  - `Shift+B` (or the `BRIDGE` button, which counts what is left) folding bridge: a cyan see-through preview of the bridge follows the cursor, snapped square across the river nearest it, the middle of its deck over the middle of the water and its ramp flaps on dry land on both banks (56-84 m long, to fit the river there); it turns red where it can't go and says why (too wide, no dry land, the ground in the way, another bridge). `LMB` orders it; `RMB` or `Shift+B` cancels. It is airdropped: it comes down out of the sky folded in three (a Z-fold: the left span upside down on the deck, the right one under it), its four thruster pods light 78 m up and brake it to a hover 30 m over its spot (spray thrown up off the water), it unfolds (the left span swinging up and over, the right one down and round) and comes down onto the banks, about 11 s from the order. A faint cyan copy of it shows where it will land meanwhile. Down, it flattens the forest under its ends and everyone can cross it: the navmesh is rebaked under it and the wall at the water's edge opens there. 30 bridges a match; with none left the button greys out.
  - Defenders can cross it too: one on it sets off its alarm, red lamps flashing along both railings by turns, red light over the deck and a siren, and a red banner at the top of your screen says how many are crossing which bridge (click it to look) for as long as one is on it. An Infiltrator under adaptive camo slips over it unnoticed.
  - Bridges are tough: 6000 HP, and every hit takes 12 less (never below a tenth of it), so rifles and machine guns barely scratch it and it takes shells, rockets and the Sniper to bring one down; no alarm sounds while it is shot at (its health bar shows on both sides once it is hit). Brought down, it breaks at its joints and sinks: the way over and the gap in the wall close again, and everyone on it falls in (those that can't swim drown, swimmers make for the nearer bank).
  - The CPU keeps a bridge standing over the main river in front of the citadel and over the east river by the Outpost (two each), dropping another when one is brought down while it has any left, and sends its nearest ground units at defenders on one of its bridges.
- `Tab` cycles spawn point (a sabotaged helipad is skipped) · `Ctrl+1`–`5` save a group, `1`–`5` recall it
- Camera: `WASD`/arrows/screen edge to pan, `Q`/`E` or middle mouse to rotate, wheel to zoom
- `Esc` pauses (both sides)

Balance numbers live in `game/scripts/units/unit_types.gd` and the constants at the top of each defense script.

### Light and effects

**The light** (`game/scripts/fx/atmosphere.gd`, both maps). The sky is drawn by a shader: deep blue overhead paling to a bright haze at the horizon, the haze over the far land below it (the fog's colour, so the land fades into it), a warm glow round the sun and its disk blooming, and clouds lit from the sun's side and shadowed underneath, thinning into the haze. The sun is warm and its shadows soft, hardening where they touch, over four cascades. ACES tone mapping with a wide bloom: anything brighter than white (the sun, fire, flashes) glows. Ambient occlusion darkens the creases, screen-space indirect light bounces colour (and a blast's glare) onto what stands round it, and volumetric fog fills the air: shafts of sunlight through the canopy, a halo round every fire, muzzle flash and blast. The fog thins as the camera climbs (it follows the camera's height over the ground), so the strategy view stays clear. The volumetric fog, the indirect light and the warp below are Forward+ (and Mobile) only; the Compatibility renderer draws the rest.

**Ray-traced lighting** (the menu's **Lighting** option, `Ray-traced` by default; `Standard` is lighter on the GPU; `-- --lighting=standard` on the command line). Godot has no hardware ray tracing; these are its rays, marched in software:

- **Global illumination** (SDFGI, Forward+): the map's scenery is kept as a signed distance field round the camera, out to a few hundred metres in cascades, and rays are marched through it from probes, so light bounces. Sunlit ground lights the walls and the undersides of things, the canopy shuts the sky out of the forest floor, the tunnels and gun decks darken inside, and every blast's and fire's light bounces off what is round it (a light is caught every other frame). The volumetric fog is lit by the bounced light too. Only the scenery is in the field: whatever moves (units, the garrison, the guns, shells, bridges, effects) is lit by it but kept out of it, so it leaves no dark ghosts behind (`Atmosphere._classify`).
- **Contact shadows** (`game/scripts/fx/contact_shadows.gd`): from every pixel a ray is marched toward the sun through the depth buffer (in the camera's clip space, where the ray's depth runs linearly across the screen to the sun's vanishing point), and where something stands in its way the sun's share of the pixel's light is taken off: the crisp dark line where feet, wheels, rocks, sandbags and roots meet the ground, which the shadow maps blur at a distance. A full-screen pass drawn before the transparent effects, so it works with MSAA and under the smoke and fire.
- **Volumetric clouds**: ray-marched through a layer of 3D noise 900-2300 m up (22 steps, each lit by three more toward the sun): cumulus with dark bellies and bright tops, a silver lining against the sun, fading into the haze at the horizon. At half resolution; standard lighting paints flat clouds instead.
- **Reflections** ray-marched in screen space on both maps (wet ground, puddles, metal, wet stone; the rivers and the lake march their own), the rest from the distance field; the sun's soft shadows filtered finer, and the biggest blasts' lights cast soft shadows too.
- **No NaNs** (`game/scripts/fx/stop_nans.gd`, Forward+): a compute pass over each frame, after the transparent pass and before the bloom, gives any pixel whose colour came out NaN or infinite (a model's degenerate tangents behind its normal map, say) its neighbours' colour. Left alone, one such pixel became a glowing white ball: the bloom turns NaN into a blinding value and blurs it wide.

**The effects** (`game/scripts/fx/fx.gd`, the scene's `FX`; `Combat.spawn_*` go through it). Particles live in a few MultiMeshes, a draw call each, and move on the GPU: each is written once, when it is spawned, and the vertex shader works out where it is from its age (launched, dragged toward the wind, pulled down by gravity or lifted by its heat, in closed form), so thousands cost the CPU nothing frame to frame:

- **Smoke** billows, lit: the sun, the sky and the blasts' own lights fall on it (wrapping round each puff, shining through its thin edges against the light), it glows orange from the fire inside for its first moments, pales as it thins, drifts on the wind and fades softly where it meets the ground instead of cutting into it.
- **Fire** is premultiplied, glowing and sooty at once: each puff burns white-hot through yellow and orange to a dull red as it cools, hottest in its dense core, licked by noise rolling up through it, and what has cooled turns to soot.
- **Sparks**, shrapnel, embers and **tracers** are streaks smeared along their motion with a hot head; sparks fall, skid along the ground and cool to red; a tracer has a white-hot head and is never thinner than a pixel, however far off.
- **Flares** (glows, star-shaped flashes, rings) bloom; **warp** bends the scene behind it: the shock wave racing out over the ground, a shock bubble in the air, heat haze over the fire.
- **Debris**: chunks flung out on arcs, tumbling, trailing smoke (and fire while they glow), bouncing and coming to rest.
- **Lights**: a pool of flickering lights (a white-hot flash cooling to orange), the biggest blasts' casting shadows; **scorch marks** burnt into the ground with embers glowing in them at first, fading after 45 s; **camera shake** by how big and how close a blast is.

A blast (`FX.blast`, `Combat.explode`) is all of it: the flash and its light, a fireball rolling up into a column of dark smoke lit from inside, sparks and embers, burning debris, and on the ground a skirt of dust rolling out, dirt thrown up in columns that fall back, the shock wave and the scorch mark. Guns flash with tongues of flame out of the muzzle and a star of them round it (`FX.muzzle_flash`; the Heavy Gunner's and the Sniper's carry a `MuzzleFlash` of their own, on the Sniper's body layer so her scope doesn't see it); cannons, mortars and launchers go off in a gout of flame with a ring of smoke blown out round the muzzle (`FX.muzzle_blast`); rounds strike with sparks off the surface and a puff of its dust; flak bursts black with shrapnel; missiles and rockets fly on a jet of flame trailing thick white smoke; shells fly glowing with a wake of heat; a knocked-out gun or turret smoulders (`WreckSmoke`). The flamethrowers and the burning forest (`FireFX`) burn with the same fire and smoke.

**The ground, the stronghold and the water** are photoscanned materials (CC0, see *Texture credits* below), laid out in world space and blended by shaders:

- **The ground** (`game/scripts/fx/ground_material.gd`, both maps): eight layers (jungle leaf litter, mossy mud and leaves, grass, dark grass, bare earth, wet mud, rock, river pebbles), each a colour, a normal map and its ambient occlusion, roughness and height, in three texture arrays (`game/assets/textures/terrain`). Where a layer lies comes from the map (the Jungle Keep's splat: the clearing's grass, the banks, the quarry; the classic field's earth tracks worn up the attack lanes, with wheel ruts sunk in them, mud in the ruts and rain standing in puddles that mirror the sky, and the scree fallen at the mountain's foot), from the slope (rock on the steep faces, projected from three sides so it never stretches), from the water (soaked dark and glossy at its edge, pebbles and silt under it with the light's caustics playing over them) and from large-scale noise (moss, grass worn thin to the soil and its sprouts and, at the heart of a worn patch, to bare earth; dry and lush grass). Layers meet by their heights, so grass grows up between the stones rather than the two fading into each other, and every layer is sampled twice at offsets a slow noise moves, so its tiles never show in rows.
- **The grass** (`game/scripts/fx/grass_field.gd`): blades standing on the ground round the camera, where the ground is grass, placed and swayed on the GPU (the CPU only moves the grid): spread evenly over the ground, lit alike on both faces with rounded normals, lighter toward the tip, a few dead and straw-coloured, the light shining through them and a sheen on them; where the grass gives out (a worn patch, a track, the scree, a bank) it thins blade by blade. Half as thick with the standard lighting.
- **The stronghold** (`game/scripts/fx/stronghold_look.gd`): the model's flat colours are replaced at load, by its material names. The mountain is scanned rock up close under a scanned cliff's big shapes and colour, with faint strata, broad zones of lighter, darker and iron-stained rock, dark and pale weathering streaks down its steep faces, grass and soil on its ledges and gentler slopes (all but its cliffs in the jungle) and moss in its crevices (thick in the jungle); its normals are smooth now (the rock had been flat-shaded, every facet showing). The bunkers are board-formed concrete (level pour lines) with worn slab decks, every pour its own shade, rain streaks down the walls (dark where the water runs, pale lime where it dries), dust settled on what faces up, grime at their foot and moss and algae in the jungle; the steel is worn plate, the hatches hazard orange flaking off rust, the door frames and the gates' blast doors striped yellow and black.
- **The water** (`JungleTerrain.WATER_SHADER`): a calm, murky jungle river, olive-brown in its depths and showing its bed in the shallows, the bed and anything swimming seen through it bent by the ripples and dimmed colour by colour with the depth of water the light comes through. Fine ripples and a broad slow swell (an FFT wind-chop spectrum's normals) flow down each river with the current (a flow map baked from their courses; two phases crossfaded so the waves neither stretch nor pulse), livelier where the current runs fast, all but still on the lake, smoothing out with distance. At a low angle it is a mirror (water's own Fresnel) over a dark body (deep murky water gives back little of the light that goes in): reflections are ray-marched across the screen against the depth buffer, so the banks, the trees, the bridges and rafts mirror in it, bent by the swell; the sky's own reflection (its clouds) wherever the ray finds nothing. The sun glitters off the ripples from a lobe as wide as their unseen slopes, held under a ceiling so a glint never swells into a blob under the bloom. It thins to a film where it laps on the bank, so the two meet without a seam; a little foam gathers along the shore and round anything standing in it, and streaks down fast water.

The textures are made by `tools/textures/fetch_and_pack.py` (downloads the Poly Haven sets and packs them) and `tools/textures/gen_water.py` (the water's wave normals, caustics and foam, generated). `game/scenes/dev/look_showcase.tscn` takes stills of how the maps look from where players see them:

```sh
godot --path game --resolution 1600x900 res://scenes/dev/look_showcase.tscn -- --shots=/tmp/look [--jungle] [--only=field,bunker] [--frames=24]
```

On a software GPU (lavapipe) add `--no-msaa`: it leaves the multisampled depth the water reads empty, so the water would show neither its bed nor its reflections.

`game/scenes/dev/fx_showcase.tscn` plays them all on a loop on the classic field (`-- --jungle`: the Jungle Keep), a camera circling: a grenade's, a mine's and a heavy shell's blasts, an air burst, flak, a field gun firing a shell over, riflemen firing tracers into the ground, a rocket diving in, a salvo of shells and a burning wreck:

```sh
godot --path game res://scenes/dev/fx_showcase.tscn                              # to watch it
godot --path game --resolution 1600x900 res://scenes/dev/fx_showcase.tscn -- --shots=/tmp/fx   # its stills, then quits
godot --path game --headless res://scenes/dev/fx_showcase.tscn -- --test         # prints and checks: FX SHOWCASE PASS / FAIL
```

Add `--lighting=standard` after the `--` to see it without the ray-traced lighting.

### Intro cinematic

The game opens with a ~3.5 minute intro (`game/scenes/intro.tscn`, built in `game/scripts/intro/intro.gd`); any key skips it, and the main menu has a **Watch Intro** button. Lore cards, shots and lighting cues are timed to the score in a table at the top of the script.

Render it to video with Godot's Movie Maker (use a real GPU for the full Forward+ look):

```sh
godot --path game --resolution 1920x1080 --write-movie intro.avi --fixed-fps 30 res://scenes/intro.tscn
ffmpeg -i intro.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 256k intro.mp4
```

Preview from a given moment with `-- --intro-start=80` (seconds).

The score (`game/assets/audio/intro_theme.ogg`) is original and synthesized by `tools/audio/compose_intro.py`; it is a temp track meant to be replaced by a real recording.

### Defender drones

Swarms of the **Defender drone** (the small ducted-fan gunship, `DroneRig`) harass the attackers from the air: low damage, but constant. `game/scripts/defense/defender_drone.gd` is one drone (fuel, flight, guns), `drone_swarm.gd` five of them working as one, `drone_bay.gd` the docks on the roofs, the cap and the calls. `-- --drones=off` plays a match without them.

- **Swarms.** Five drones to a swarm and **six swarms**, no more and no fewer, all six whole from the first second. A drone that is shot down is **rebuilt in the hangar in 385 s**, every missing drone on a timer of its own and all at once (refuelling is concurrent too, each drone on its own dock), full of fuel and mended, on a dock. A whole swarm shot to pieces is back after one rebuild time (6.4 minutes), not five. Each single rebuild is still longer than filling an empty tank (350 s), let alone refuelling a drone that comes home (157 s from a landing at 50%, 238 s to 95% from 27%), so **refilling always beats rebuilding**. A swarm that lost drones is damaged until they are back, and the last to be called.\n- **Seeking.** A swarm on its own looks for attackers within about the fortress's size of the map's middle that its fuel can reach, flies out and stops 26 m out from its target and 12 m up (its guns reach 34 m), then shoots. Twin guns, two rounds of 0.9 every 0.65 s: about 2.8 damage a second a drone, 14 a swarm. That is nothing against an elephant (1400 health) and a few seconds for a medic.
- **One target.** A swarm has ONE focus and every drone of it shoots that one until it is dead, then it picks the next. It only lets go of it early if it can't be got at: it dives under the water, strays out of the drones' reach, or the drones have stood off it for 4 s without a line to it (inside the mountain, behind a hill, in smoke), when it is put aside for 12 s. Each drone still obeys its own fuel rule, so a swarm thins out as drones go home one by one and fills up again as they come back; its target is not forgotten while they recharge.
- **Whom it picks** (`DroneSwarm._score`) is where the annoyance is. Highest first: the units the army leans on (Wolf Medic 3.0, Giraffe 2.6: its eyes, Mule 2.2, Bison 2.0, Serpent 1.9, Kangaroo 1.7, then chimps, lionesses, rams, hippos), with the **bears, rhinos and elephants last** (0.5, 0.3, 0.25): they are the only things that shoot back. Helpless units count 4 times: nothing attacks while it swims or rides a raft, so a swimmer just gets shot. **A bear diving under the water is undetectable to drones**: never picked, dropped the moment it dives (the swarm goes for someone else, and takes it up again if it surfaces), and its body doesn't stop a drone's round; hurt ones up to 1.8 times; a target with a bear or AA unit within 32 m of it is worth less for each; one another swarm is already on, and one far from where it was sent, likewise. The drones hang on the side of the target that keeps them furthest out of the bears' and AA units' reach (checked every 1.2 s), so a target with its bears on one side gets shot from the other.

**Fuel** (a full tank is 1.0; `DefenderDrone` has the three rules as `trip_cost()` and `must_return()`)

| | |
|---|---|
| Flying | a third of a tank for every fortress size (172 m, the mountain's footprint) **flown**, in any direction |
| Standing still (shooting too) | 5% every 10 s. Moving never costs less than that |
| Turning for home | when the tank is down to **50%**, or when the way home from where it is would cost **half of the fuel it has left**, whichever comes first |
| Refuelling | on a roof dock, **1.75 s for every second of fuel spent** (a second of fuel is what hovering burns in a second, 0.5% of a tank): a sortie that took half a tank takes 175 s to refill, an empty tank 350 s. It mends separately, in 18 s. It leaves again on its own only once 95% full; a call can send one earlier (see *Calls*) |

So close to the fortress a drone turns at 50%; out at the end of its leash the second rule pulls it back much sooner (a full tank turns back 258 m out; one hovering 150 m out turns with 58% left); and one that has hovered over a fight until even a short way home is half of what it has left goes home too. It always lands with at least as much fuel as the trip home cost. Drones land on the nearest free dock, not their own: there are five pads on a ring round each AA turret on the roofs. Docked, a swarm is gone from the field: its drones are hidden in the roofs' hangars, in nothing the attackers' units look at, targeted or count, and can't be hurt.

**Calls.** Any defender can call a swarm to where it stands: you with **`C`** (to the post you're on), and the garrison, the squads and the posts on their own when attackers get within 40 m of them, through the same `DroneBay.call_swarm()`. A swarm can be called only if its drones can get there on the fuel they have, arriving 10% of a tank above their turning-back point (so a full-tanked swarm can be called to about 155 m from its docks, and one that has been out a while to less). **Every call gets the freshest swarm**: of the idle ones that can get there, the one in the best shape (`DroneSwarm.freshness()`: each drone's fuel times its health, over the five it should have, so a whole swarm with full tanks is 1.0, one with two drones shot down at most 0.6, an empty one 0). A damaged swarm is called only once the fresh ones are spent: out on a target, recharging, or already holding a call. A busy swarm comes last, and only for your `C`. **The garrison's automatic calls only ever take idle swarms**, so a swarm keeps the target it is on (only your `C` can re-task a busy one); a swarm that is about to kill (its target at 35% health or less) isn't pulled off it; a spot already covered by a swarm isn't called again, nor one called in the last 20 s. A called swarm takes the best target within 80 m of the spot for 25 s. **Called to nothing**, it flies out, looks round for 5 s, then stands down: every drone goes home, docks and stays there, the call forgotten. A docked swarm is nothing: not busy, holding nothing, still one of the six, and free to be called again (a swarm that came back from a short sortie is called again without waiting to fill up, as long as its fuel covers the trip; one with under 65% can't go anywhere worth going, which the call says is recharging). A call that never gets a drone off its dock lapses after 3 s the same way. Drones on their way home with no need to be (they stood down) turn round for a new target; ones going home on the fuel rule never do. The HUD (top right) shows the drones alive of the thirty, aloft and ready; a refused call says why (out of reach, already on it, every drone recharging or lost, every swarm about to make a kill).

**What can touch a drone.** Only anti-air damage and the bears: the **Bear Rifleman** (`hunts_drones` in `unit_types.gd`), the **Combat Rhino** and the **War Elephant** (the elephant's missile salvos too: a locked elephant fires one whenever it is ready and the drone still needs killing; you can also aim one at a drone with `O`). A drone is in `air_units` (what the AA finds) but not in `damageable`, and has no body, so blasts (shells, bombs, cluster bombing, flame), stray rounds and every other unit's guns pass it by. Nothing else can target it or be ordered to.

**Hyper-focus.** A bear or AA unit that has a drone in sight within 80 m (the attackers' fog of war counts: a drone nobody sees doesn't pull anyone) is **locked on**: it goes after the drone and shoots it, taking no orders, a red `DRONE LOCK` over it, until no drone is left in sight for it (it keeps a drone it has as far as 110 m). Its order is not lost: the last one you give it meanwhile is held and carried out the moment it is free, and the one it had before stays as it was. Drones docked on the roofs don't count, so a drone going home to recharge lets the army go back to its business; it is not locked for ever by a drone it can't reach. A unit that can't fight (swimming, on a raft, on a ladder) isn't pulled in. The CPU attacker builds more bears (+1 for every swarm with drones in it) and, from the third swarm on (and the second wave), Combat Rhinos.

**Where the brief left room, and the flaws I closed** (all the numbers are constants at the top of the three scripts)
- *"1/3 fuel per fortress size away from the fortress"*, taken as distance from the fortress, would let a drone circle at a constant radius for nothing, or drift slowly for free. Fuel is charged by the distance actually flown, with 5%/10 s as the floor.
- *"50% of available fuel"* read two ways: the fixed 50% mark, or a dynamic one of "the way home costs half of what's left". The table's rule takes both. Either alone leaves a hole: the fixed mark alone lets a drone 250 m out turn with 50% and reach its dock with under 2%; the dynamic one alone never turns a drone hovering at the dock.
- *"Return to recharge"* needed somewhere to land, and a rule against taking off at 51% and turning straight round: docks on the roofs, 95% to leave.
- *A swarm called "if any drone can't get there it can't be called"* would let one low-fuel straggler veto four fresh drones. Every drone that can go is sent; a swarm with none that can isn't called.
- *"Until no drones for them to destroy"*, with a drone sitting on its dock or a swarm anywhere on the map, would freeze every bear and AA unit for ever. Only airborne drones in sight within 80 m count. And orders given to a locked unit are held, not thrown away (the CPU gives each wave one order at launch; lose it and the wave stands at the spawn).
- *"Only AA damage and bears can attack them"*: as ordinary `damageable` things the bisons' shells, the talons' bombs, the lioness's flame and every stray rifle round would have hurt them. They are not.
- *A swarm that always focuses one enemy*, kept on a target it can't see or reach, would stand off a wall for ever: hence the line and reach checks above.
- *Drones that shoot swimmers* can't, on the Jungle Keep as the numbers stand: the east river is about 320 m from the roof docks, the main river the army swims about 430 m, the lake and the north-west river further, and a drone never gets more than about 258 m out (a swarm can be sent about 155 m). The rule is in (swimmers are the swarm's favourite prey, divers invisible) but there is no water inside the drones' reach to use it on. To change that: forward drone pads near the crossings, or a bigger "fortress size" for the Jungle Keep (`DefenderDrone.FORTRESS_SIZE` scales every fuel figure; about 470 m would put the main river just inside the leash), or leave the water to the bears' dive.
- *Refuelling slower than rebuilding* made losing a drone the faster way back to a full tank (a rebuild in 20 s against 175 s to refuel half a tank): the attackers' AA would have shortened a swarm's recovery. Inverted: `DefenderDrone.REBUILD_TIME` is `REFUEL_TIME` times `REBUILD_RATIO` (1.1, 385 s), longer than filling an empty tank (350 s). Because a lost drone now stays lost for most of a ten- or fifteen-minute match, AA and bears wear a swarm down for good; with the rebuild that slow, all six swarms start whole instead of filling up. To make losses cheaper, lower `REBUILD_RATIO` (at or below 1.0 a rebuild is no longer slower than an empty-to-full refill).
- *Six swarms that can't be topped up one drone at a time* could end as six lone drones, a slot held for ever by a drone that is untouchable on its dock. The six places are fixed and every missing drone is rebuilt (slowly), so no place is ever held: a swarm that has lost drones is weaker, and a call takes a fresher one first. Rebuilds run concurrently, each missing drone on its own timer (`DroneSwarm._rebuild_tick`).

### Automated smoke test

Plays a scripted match at 4× speed with no window and prints a report (useful after changes):

```sh
godot --path game --headless -- --autotest=defender --duration=120
godot --path game --headless -- --autotest=attacker --duration=120
godot --path game --headless -- --autotest=attacker --duration=120 --map=classic   # the classic field (default: the Jungle Keep)
```

### Sniper showcase

`game/scenes/dev/sniper_showcase.tscn` runs the Sniper through her kit on the real map, in the south field, the way the defending player uses her (her own camera and panels), with her rounds and their tags as the attacking player sees them in the RTS view (`media/sniper_showcase.mp4`). She stands (her idle, the rifle shouldered). Bought (`K`) and taken (`F1`), she is walked up, third person over her shoulder. `RMB`: the scope comes up to her eye, 8x, the wheel to 12x and back; `LMB` on a Bear Rifleman 74 m out and he drops; `R` reloads. Five rounds into five sturdy attackers (a lioness among them): each is tagged and the panel's slots fill; a sixth hit (a bison gun) tags nothing while all five are out; the giraffe she tagged first takes a second round and dies, its slot is free again and the bison gun's next hit tags it, for 20% more damage. The RTS view: an aim icon over each tagged unit; two lionesses are selected and `F`: the tagged one can't sneak, the other does. Back in the scope, on the forest west of the lane: chimps in among the trees, hard to make out; `T`: the land goes dark, the trees see-through, the chimps white-hot, and she tags two; after 15 s it goes off and `T` is refused while it recharges. The RTS view from the side of her line of fire: each round's long tracer and the white trail it leaves, hanging 1 s, then fading (one in slow motion). Last, the player takes a rifleman's post and leaves her: she holds her ground, passes over two chimps in the forest east of the lane (closer, but in among the trees), picks a ram out in the open and stays on it, a kangaroo coming up closer, until it falls, tagging only it; then the kangaroo. The garrison's posts and the AA turrets hold fire; the attackers in the field don't fight back.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/sniper_showcase.tscn -- --test  # prints and checks: SNIPER SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/sniper_showcase.tscn -- --video --snap=12.2,50,68.6 --snap-out=/tmp/sniper  # just those frames
```

`-- --video` cuts in cameras (round her standing, her own view and the scope, the RTS view), plays the waits faster, one round in slow motion, cuts the dead time and prints the frames to keep; `tools/video/cut_showcase.py` cuts the recording into the mp4:

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie sniper.avi --fixed-fps 30 res://scenes/dev/sniper_showcase.tscn -- --video > sniper.log
python3 tools/video/cut_showcase.py sniper.avi sniper.log media/sniper_showcase.mp4
```

### Lioness showcase

`game/scenes/dev/lioness_showcase.tscn` runs the Armored Lioness through her skills on the real map, in the south field, the way a player uses them in the RTS view, with a look through a defender's eyes (`media/lioness_showcase.mp4`). A lioness stands (her idle), walks and breaks into her gallop. Eighteen are box-selected and sent up the field: they converge into firing lines as they go, 8 abreast with a second line of 8 behind and the last 2 behind that, and stand facing the way they went; `T` turns lines off (sent on, they go as a pack) and back on. Three, `F`: a bush over each, they stalk past a Flame Trooper in their reach and leave it alone; `RMB` on a trooper up the field: they stalk up, pounce (the sneak ends as they spring) and maul it. Then the defender's side: through a rifleman's eyes two sneaking lionesses come up 70% see-through, without shadows or health bars, beside one that isn't sneaking; they pounce on the rifleman next to him and show again. Two lionesses, `G`: the flamethrowers burn a cone in front of them and, sent off to the side, they turn and go with the cone turning with them, burning the troopers in it. A sneaking lioness lights hers: the sneak is over. Last, one burns the edge of the forest east of the lane: no tree catches fire. The garrison's posts and the AA turrets hold fire; the troopers and riflemen in the field don't fight back.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/lioness_showcase.tscn -- --test  # prints and checks: LIONESS SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/lioness_showcase.tscn -- --video --snap=22,47 --snap-out=/tmp/lioness  # just those frames
```

`-- --video` cuts in cameras (round the lioness standing, beside the walker, low in front of the lines, beside the stalkers and, in slow motion, the pounce, by the flamethrowers, at the forest's edge), plays the lines' march faster, cuts the waits and prints the frames to keep; `tools/video/cut_showcase.py` cuts the recording into the mp4:

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie lioness.avi --fixed-fps 30 res://scenes/dev/lioness_showcase.tscn -- --video > lioness.log
python3 tools/video/cut_showcase.py lioness.avi lioness.log media/lioness_showcase.mp4
```

### Serpent showcase

`game/scenes/dev/serpent_showcase.tscn` runs the Serpent Sniper through its kit on the real map, in the south field, the way a player uses it in the RTS view, with a look through a defender's eyes. A snake lies still (its idle), slithers across the lane and fires at a Flame Trooper: a round every 4 s, 95 a hit. The sniper nest: a trooper 62 m up the lane is in the fog of war, out of its sight; the snake is clicked, `F`, `LMB` on a lone tree: it rears up the trunk, winds up it into the crown (8 s) and lies out on top of it, the tree-and-rifle icon over it; up there it sees the trooper and shoots it. `RMB` on the ground: it climbs down (8 s), then goes. The bush trap: `G`, `LMB` on a bush: it hides its rifle in the bush and coils round it (8 s), the grass-and-snake icon over it. A trooper standing in sight beyond its reach it leaves alone; one walking past it strikes, winds round and squeezes, the trooper's health running down to nothing over 15 s, and an `RMB` meanwhile changes nothing. Its prey dead, it coils round its bush again, and `RMB` uncoils it (8 s), the rifle back on its back. Then the defender's side: through a rifleman's eyes a snake coiled round a bush is 70% see-through, with no shadow, no health bar and no icon. Last, two riflemen shoot a squeezing snake dead: the trooper goes free with the health it had left and walks on. The garrison's posts and the AA turrets hold fire; the troopers in the field don't fight back (the riflemen of the rescue do).

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/serpent_showcase.tscn -- --test  # prints and checks: SERPENT SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/serpent_showcase.tscn -- --video --from=nest --snap=36,40 --snap-out=/tmp/serpent  # just those frames
```

`-- --from=nest` starts at that phase (`slither`, `fire`, `nest`, `trap`, `defender`, `rescue`); `-- --bare-tree` hides the nest tree's crown and stands a plain trunk in for it, to check the climb. `-- --video` cuts in cameras (round the snake lying still, beside it slithering, behind it firing, the whole tree as it climbs, over its head on top of the crown, low by the bush as it coils, side-on to the strike in slow motion and close by the squeeze), plays the climbs and the coiling faster, cuts the waits and prints the frames to keep; `tools/video/cut_showcase.py` cuts the recording into the mp4:

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie serpent.avi --fixed-fps 30 res://scenes/dev/serpent_showcase.tscn -- --video > serpent.log
python3 tools/video/cut_showcase.py serpent.avi serpent.log media/serpent_showcase.mp4
```

### Giraffe showcase

`game/scenes/dev/giraffe_showcase.tscn` checks the Giraffe, the fog of war and the ping on the real map, in the south field, from the attacker's side. A giraffe walks up from the west; a Flame Trooper stands in the fog 25 m from a Bear Rifleman whose sight is cut to 15 m: it isn't drawn, the rifleman leaves it alone though it is in range, and an order to attack it is refused. The giraffe comes within 75 m: the trooper shows and the rifleman shoots it. Three riflemen leave an infiltrator out of camo alone (low profile); the giraffe pings: the pulse marks her and an infiltrator under camo with red blurs (not a trooper beyond its reach), the blurs stay put when the one under camo walks off, she is revealed and the riflemen go after her on their own. Under camo she is lost again; pinged once more, she slips into the fog and her low profile is back. The radar icon over her shows on the defender's side only, and an Infiltrator Squad under camo that looses an arrow loses its camo. The garrison's posts and the AA turrets hold fire.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/giraffe_showcase.tscn -- --test  # prints and checks: GIRAFFE SHOWCASE PASS / FAIL
godot --path game --fixed-fps 30 res://scenes/dev/giraffe_showcase.tscn  # to watch it
```

`-- --snap=6,21 --snap-out=/tmp/giraffe` saves just those frames (seconds in). `-- --video` frames the field closer and prints the frames to keep (the squad check inside the mountain is cut), for the video (`media/giraffe_showcase.mp4`):

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie giraffe.avi --fixed-fps 30 res://scenes/dev/giraffe_showcase.tscn -- --video > giraffe.log
python3 tools/video/cut_showcase.py giraffe.avi giraffe.log media/giraffe_showcase.mp4
```

### Elephant showcase

`game/scenes/dev/elephant_showcase.tscn` stages the War Elephant on the real map, with the garrison holding fire: `walk` (the camera circles a walking elephant), `flak` (drones fly in and the cannons shoot them down) and `missiles` (the RTS view: five elephants, two drones, salvos aimed with `O`). The defenders have no aircraft yet, so `TargetDrone`s stand in for them. Record a shot with Movie Maker:

```sh
godot --path game --resolution 1280x720 --write-movie walk.avi --fixed-fps 30 res://scenes/dev/elephant_showcase.tscn -- --shot=walk
```

### Ram raid showcase

`game/scenes/dev/ram_raid_showcase.tscn` records a Breaching Ram assault on the south gate: three rams charge the gate down with Chimps behind them, then they all go in and fight the garrison on their own. Cameras set up inside the base (video-only, like the work lights and the extra guards it places inside) and chase shots follow the fight. The mortar and machine guns hold fire.

```sh
godot --path game --resolution 1280x720 --write-movie ram_raid.avi --fixed-fps 30 res://scenes/dev/ram_raid_showcase.tscn
```

### Gunner Squad showcase

`game/scenes/dev/squad_showcase.tscn` records the Gunner Squad (`media/gunner_squad_showcase.mp4`): a lone Heavy Gunner's walk, strafe and minigun, then the squad driven out of the south spawn hall the way a player would (`SquadPilot` works the keys and the camera): up the narrow spawn ramp and through the gate tunnel in file, out through the blast door into a wedge, where a shell kills the leader and the nearest trooper takes over, through a stand of birches and rocks, and into a fight with two waves, one ahead and one on the flank. Video-only: the grove, the work lights, the shell and the attackers; the other posts hold fire.

```sh
godot --path game --resolution 1280x720 --write-movie squad.avi --fixed-fps 30 res://scenes/dev/squad_showcase.tscn
godot --path game --headless --fixed-fps 60 res://scenes/dev/squad_showcase.tscn -- --test  # prints what the squad does
```

`-- --snap=30,45 --snap-out=/tmp/shot` saves just those frames (seconds in), for checking shots without recording it all.

### AA Squad showcase

`game/scenes/dev/aa_squad_showcase.tscn` stages three bought AA Squads in the south field and drives the first like a player would. Two Sky Talons cross in front of it: it holds `RMB` close to each until the lock closes (3 s), then fires seeking missiles. A group of attackers stands ahead: `RMB` shows each trooper's spot, `LMB` fires the strike. Then `F` and a throw of mines, which attackers walk into. `F2`, `F3`, `F1` go through the roster, `Ctrl+F1` swaps AA 1's order and back, and AA 1 walks on further out. Finally the player goes back to a rifleman on the south deck: AA 1 (MINES) lays mines where it was left, then on the path home, then along the perimeter; AA 3 (MINES) works the perimeter; AA 2 (GUARD) holds its ground and shoots down a Sky Talon while attackers walk past. The garrison's posts hold fire.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/aa_squad_showcase.tscn -- --test  # prints and checks: AA SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/aa_squad_showcase.tscn -- --shots=/tmp/aa  # + captioned screenshots
```

`-- --video` is the showcase video (`media/aa_squad_showcase.mp4`): a lone Missile Trooper's walk, strafe and rockets first, then the same run with cameras cut in (one rides behind a seeking missile, others sit low by the strike and the minefield or track the squad walking), captions and the keys the player presses. AA 1 walking to its spot at the perimeter and waiting for its mines plays 4× faster. The run prints which frames to keep and speed up, and `tools/video/cut_showcase.py` cuts the recording into the mp4 from that log:

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie aa.avi --fixed-fps 30 res://scenes/dev/aa_squad_showcase.tscn -- --video > aa.log
python3 tools/video/cut_showcase.py aa.avi aa.log media/aa_squad_showcase.mp4
```

### Bison showcase

`game/scenes/dev/bison_showcase.tscn` aims the Bison Field Gun's bombardment the way a player does, in the RTS view: a lone bison out in the south field is clicked, `G`, the view pans up to the south face, and the cursor goes onto the gate machine gun on the gun deck, `LMB`. After its reload (cut short here) it hits the mortar on the roof. Then four bisons are box-selected and shell the deck, their shells spread along it between the two riflemen, and then the roof. The garrison's posts hold fire, and their machines don't get repaired.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/bison_showcase.tscn -- --test  # prints and checks: BISON SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/bison_showcase.tscn -- --snap=9,24 --snap-out=/tmp/bison  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie bison.avi --fixed-fps 30 res://scenes/dev/bison_showcase.tscn
```

`-- --video --snap=30,45 --snap-out=/tmp/shot` saves just those frames (seconds into the video).

### Mule showcase

`game/scenes/dev/mule_showcase.tscn` works the Mule Artillery the way a player does, in the RTS view, in the south field. A mule walks up the lane, super slow. `T`: the barrel rises (7 s), and an order to move meanwhile changes nothing. `G` and a click on the gate machine gun on the south gun deck, about 90 m off: the turret lays the barrel and the shell leaves the raised muzzle and comes down on the gun. `G` again does nothing while the gun reloads (30 s, cut short here); then the mortar on the roof; then a spot in the field behind it, the turret swinging round while the team stands. Ordered to move while armed, it stays put. `T` disarms it (7 s), and the order to move given meanwhile it carries out once disarmed. The garrison's posts hold fire, and their machines don't get repaired.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/mule_showcase.tscn -- --test  # prints and checks: MULE SHOWCASE PASS / FAIL
godot --path game --fixed-fps 30 res://scenes/dev/mule_showcase.tscn  # to watch it
```

### Sky Talon showcase

`game/scenes/dev/talon_showcase.tscn` flies the Sky Talon on the real map (`media/talon_showcase.mp4`): one takes off from the south field, beating its wings all the way up, then cruises west across it (long glides, a few wing beats now and then) and circles the spot it was sent to. Last, five talons sent to one spot each fly a ring of their own. The garrison's posts and the AA turrets hold fire.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --test  # prints and checks: TALON SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --snap=12,33 --snap-out=/tmp/talon  # just those frames
```

`-- --video` draws only the stretches the video shows (the run is the same every time) and prints the frames to keep, so the recording renders in a fraction of the time; `tools/video/cut_showcase.py` cuts it into the mp4:

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie talon.avi --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --video > talon.log
python3 tools/video/cut_showcase.py talon.avi talon.log media/talon_showcase.mp4
```

### Flame Squad showcase

`game/scenes/dev/flame_squad_showcase.tscn` records the Flame Squad (`media/flame_squad_showcase.mp4`): a lone Flame Trooper's walk, strafe and flame (a ruler on the ground shows its 6 m), then a squad bought with `N` and driven out of the south spawn hall the way a player would: up the spawn ramp and through the gate tunnel in file, out through the blast door into a wedge and across the field to the forest east of the south lane. Chimps rush it out of the trees and burn. At the forest's edge a quick sweep of the flame across a trunk doesn't do it (the heat drains away again); held on it, the canopy catches after 8 s. Then the player goes back to a rifleman and the squad, on its CLEAR order, clears the forest on its own from the base outwards, each trooper burning a tree, the burnt trees falling 30 s later, and walks on to the next forest. The garrison's posts and the AA turrets hold fire; the Gunner Squad is left out (the Flame Squad deploys in its hall).

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/flame_squad_showcase.tscn -- --test  # prints and checks: FLAME SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/flame_squad_showcase.tscn -- --video --snap=64,96 --snap-out=/tmp/flame  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie flame.avi --fixed-fps 30 res://scenes/dev/flame_squad_showcase.tscn -- --video > flame.log
python3 tools/video/cut_showcase.py flame.avi flame.log media/flame_squad_showcase.mp4
```

`-- --video` cuts in the cameras, captions and the keys the player presses, and plays most of the clearing 4× to 6× faster (drawing only the frames it keeps).

### Sky Talon strike showcase

`game/scenes/dev/talon_strike_showcase.tscn` aims the Sky Talon's skills the way a player does, in the RTS view, against the south face (`media/talon_strike_showcase.mp4`). A talon sent over the face is shot down by the roof's AA turrets; a bison shells one turret from beyond their reach. One talon is clicked, `G`, `LMB` on the other turret: it slants in along the face, bombs it and breaks away while the turret fires at it. Three talons are box-selected, `G`, `LMB` on the mortar: their bombs land apart along the roof. One talon, `F`, `LMB` pressed on a rifleman on the gun deck and dragged along the deck: it comes in from the field and strafes down the deck. Three talons, `F`, pressed on the other rifleman and dragged up the mountain: three parallel lanes across the face, the talons climbing over the deck and the roof as they fire. The garrison's posts hold fire; the turrets don't (and stay down once destroyed).

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/talon_strike_showcase.tscn -- --test  # prints and checks: TALON STRIKE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/talon_strike_showcase.tscn -- --snap=31.5,88.6 --snap-out=/tmp/strike  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie strike.avi --fixed-fps 30 res://scenes/dev/talon_strike_showcase.tscn -- --video > strike.log
python3 tools/video/cut_showcase.py strike.avi strike.log media/talon_strike_showcase.mp4
```

The test also checks that no talon on a run ever goes into the ground or the stronghold. `-- --video` plays the waits and the flying into position at triple speed and cuts the time between strikes.

### Kangaroo showcase

`game/scenes/dev/kangaroo_showcase.tscn` runs the Kangaroo Commando through its paces on the real map, against the south face, the way a player uses it in the RTS view (`media/kangaroo_showcase.mp4`). A lone kangaroo hops down the south attack lane. Three are box-selected, `R`, the cursor on the gate machine gun, `LMB`: they rear up and throw, their grenades spread along the gun deck, and the bangs blind the gunner and both riflemen there. Then the defender's side: the player on a deck rifleman, a kangaroo flashes the post and the screen goes white. A kangaroo hops up to five units whose skills are cooling down: ammo boxes over the three nearest, their cooldowns running faster; a second kangaroo takes the other two (the cut never stacks). The three gun down a rifleman in front of the face with their SMGs, and last the south gate falls and they storm the base, hunting the guards inside and the riflemen on the deck on their own and flashing them. The garrison's posts hold fire until the storm, the AA turrets throughout.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/kangaroo_showcase.tscn -- --test  # prints and checks: KANGAROO SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/kangaroo_showcase.tscn -- --video --snap=18.5,66.8 --snap-out=/tmp/kangaroo  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie kangaroo.avi --fixed-fps 30 res://scenes/dev/kangaroo_showcase.tscn -- --video > kangaroo.log
python3 tools/video/cut_showcase.py kangaroo.avi kangaroo.log media/kangaroo_showcase.mp4
```

`-- --video` cuts in the cameras (beside the hopper, in slow motion as it bounds past, close by a kangaroo rearing up to throw, along the deck as the grenades go off, through the rifleman's eyes as the flash whites out the screen, and inside the base for the storm), plays the climb to the deck and the fight there 2× faster and cuts the waits.

### Wolf Medic showcase

`game/scenes/dev/dog_showcase.tscn` runs the Wolf Medic through its two modes on the real map, in the south field, the way a player uses it in the RTS view (`media/dog_showcase.mp4`). A dog stands (its idle). Healing: it is clicked and sent (`RMB`) up to four hurt units; it takes the first two it comes to, a ram and a kangaroo, healing them on the move (12 HP/s each, a beam and a cross over each). A chimp hurt worse runs up next to it: it sticks with its two. The kangaroo is full: it takes the chimp. The ram walks off out of its reach, not yet full: it lets it go and takes the hippo. A second dog comes up and takes the other two (no unit is healed by both). Then a minefield across the lane, 21 mines: on the attacker's side none is drawn, on the defender's (a low camera across the field) all of them; a rifleman walking across it is blown up. Four dogs are box-selected, `T` (the HUD says MINESWEEPING), `RMB` beyond the field: they find the mines on their way and dig them out one after another (a close-up of the first, the dirt flying), the mine being dug showing in its hole with its ring filling, the field cleared from the outside in, never across a live mine, and they walk on through. Riflemen walk across where it was. The garrison's posts and the AA turrets hold fire.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/dog_showcase.tscn -- --test  # prints and checks: DOG SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/dog_showcase.tscn -- --video --snap=7.5,60 --snap-out=/tmp/dog  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie dog.avi --fixed-fps 30 res://scenes/dev/dog_showcase.tscn -- --video > dog.log
python3 tools/video/cut_showcase.py dog.avi dog.log media/dog_showcase.mp4
```

The test checks that no dog ever comes within a mine's reach (2.05 m) of a live mine but the one it digs, that every dig takes 6 s, that the picks are on the edge of what is left of the field, and that only the mine being dug shows to the attacker. `-- --video` cuts in the cameras (round the dog standing, low across the field on the defender's side, close by the first dog to dig), marks the hidden mines for the viewer (red: the player never sees them) with a counter of how many are left, plays most of the sweep 4x faster and cuts the waits.

### Bridge showcase

`game/scenes/dev/bridge_showcase.tscn` runs the river crossings on the Jungle Keep's main river, west of the citadel's way north. With no bridge yet, an army is sent over: two bears and a Serpent Sniper swim; three hippos and an elephant swim too, each towing its raft (the rafts start folded up on their backs; each is put down behind its carrier as its riders come, swinging open and its floats blowing up, and nobody gets on before it is out). A kangaroo, a chimp, a lioness and a dog climb onto two of the rafts, two to a raft, a Combat Rhino onto the third on its own and a Giraffe onto the fourth on its own; a second kangaroo, the furthest from the rafts, finds no place left and stays on the bank. The carriers wait for them, swim over towing them (the hippos' heads over the water, the elephant's trunk raised to breathe; out on the water the rafts keep clear of one another) and let them off on the north bank, where the rafts come apart and fade away, the carriers with fresh ones folded on their backs; a Bison Field Gun goes only as far as the south bank; two Sky Talons fly over. A defender stands on the north bank in their reach: nobody fires at it, nor uses a skill, until out of the water. Then a bridge is dropped 120 m east (the preview, the drop, the thrusters, the unfolding, the landing), and the bison, a second giraffe, the Mule Artillery and a second rhino walk over it. Two Flame Troopers cross it the other way: the alarm goes off while they are on it, and stops. Shot at (rifle rounds, three shells) it sets no alarm off and barely loses any health. On the north bank (`--test` only) a chimp, a kangaroo and a dog are told to board a hippo's raft (as with `RMB` on the hippo): two climb on, the third has no place, a giraffe can't get on with them; a rhino can't either, boards another hippo's empty raft on its own, and neither a chimp nor the giraffe can join it there; the giraffe boards a third hippo's empty raft on its own, and the chimp can't join it there either; the riders stay on while the hippo walks on dry land, the raft trailing behind it, and `Space` (unload) lets them off beside it. Brought down, a chimp on it drowns, a bear on it swims to the bank, and the way over is gone again.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/bridge_showcase.tscn -- --test  # prints and checks: BRIDGE SHOWCASE PASS / FAIL
godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/bridge_showcase.tscn -- --shots=/tmp/bridge [--only=alarm,preview]
# raft_packed, raft_unfolding, raft_inflating, swim_bears, rafts_crossing, raft_riders, raft_rhino, raft_giraffe, hippo_head,
# elephant_trunk, left_behind, raft_apart, preview, preview_bad, drop_fall, drop_thrusters, drop_unfold, bridge_down,
# bridge_crossing, alarm, under_fire (.png)
```

Taking stills, only the frames saved are drawn (the run in between goes at full speed); without a GPU, Mesa's software Vulkan (`mesa-vulkan-drivers`, under `xvfb-run`) renders Forward+ at about 10 s a frame.

`-- --video` films the deployment (`media/bridge_deploy.mp4`, 18 s): the RTS view, `Shift+B`, the preview sliding along the river with the cursor and the click, then from over the water downstream the bridge coming out of the sky folded, its thrusters lighting, the unfolding in the hover and the landing (the run goes on to rise over it and back to the RTS view with one bridge fewer). The first frames are the map loading (nothing is drawn meanwhile): cut them at the first scene change:

```sh
godot --path game --resolution 1280x720 --write-movie bridge.avi --fixed-fps 30 res://scenes/dev/bridge_showcase.tscn -- --video
ffmpeg -i bridge.avi -vf "select='gt(scene,0.08)',showinfo" -frames:v 1 -an -f null - 2>&1 | grep pts_time   # where it starts
ffmpeg -ss <that time> -i bridge.avi -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac media/bridge_deploy.mp4
```

For the video every frame is drawn, the forest only out to 520 m and the sun's shadows to 220 m (the drop is seen from close by).

The bridge (`assets_src/structures/folding_bridge/folding_bridge_meshy.glb`, a Meshy "military loading ramp") is cut into the three spans it folds in by `tools/gltf/fold_bridge.py` (see the asset pipeline). The rafts are cut into the pieces they fold and come apart in by `tools/gltf/split_raft.py`.

### Bear showcase

`game/scenes/dev/bear_showcase.tscn` puts Bear Riflemen in the Jungle Keep's main river (the bridge showcase's stretch), with a defender rifleman on the north bank. On dry land `F` dives nobody. Out in the water a bear swims its dog paddle, its LMG slung across its back (the muzzle up over its head) and its head out of the water; the rifleman picks it out and hits it. `F` (the attacker's key, the bear selected): it dives, down under its swim depth, the Dive stroke, and the attacking player sees its silhouette; on the defender's side nothing shows of it (no silhouette, no health bar). The rifleman has no line of sight to it and loses it, and no rounds come at it while it is under, but a round fired into the water where it is hits it. After 10 s it comes up, swims at the surface again and is shot at again; it can't dive again until the cooldown is over. A second bear, the CPU's way: shot at out swimming, it dives. On the north bank the bear runs with its gun in its paws again.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/bear_showcase.tscn -- --test  # prints and checks: BEAR SHOWCASE PASS / FAIL
godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/bear_showcase.tscn -- --shots=/tmp/bear [--only=bear_swim,bear_under]
# bear_swim, bear_swim_side, bear_swim_back, bear_shot_at, bear_dive, bear_under, bear_under_rts, bear_under_defender,
# bear_hit_under, bear_up (.png)
godot --path game --resolution 1280x720 --write-movie bear.avi --fixed-fps 30 res://scenes/dev/bear_showcase.tscn -- --video
```

`-- --video` films a bear swimming out and diving (`media/bear_swim_dive.mp4`, 30 s): close by it on the south bank with its LMG in its paws, running down the bank and paddling out with it slung on its back, shot at from the north bank, `F`, the dive seen from over the water (its silhouette), a few rounds into the water where it is, and up again. The first 16 s are the map loading (nothing is drawn meanwhile): cut them (`ffmpeg -ss 16.2 -i bear.avi ...`, or find where the frames stop being frozen with `-vf freezedetect`).

### Chimp showcase

`game/scenes/dev/chimp_showcase.tscn` sends a Night Ops Chimp from the forest south of the Jungle Keep straight out into the Keep's clearing. Standing in the forest it is on the ground; sent off, it leaps up into the trees within a second and swings through them from branch to branch (its Swing clip, `tools/gltf/swing_chimp.py`) at its forest speed, up under the canopy; a round fired across at where the defenders aim at it up there hits it. Out of the trees it drops back down and runs on, slower. A second chimp sent a little way into the forest goes up into the trees and comes down again where it stops.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/chimp_showcase.tscn -- --test  # prints and checks: CHIMP SHOWCASE PASS / FAIL
godot --path game --resolution 1280x720 --fixed-fps 30 res://scenes/dev/chimp_showcase.tscn -- --shots=/tmp/chimp [--only=chimp_swing]
# chimp_standing, chimp_leap, chimp_swing, chimp_swing_front, chimp_drop, chimp_run (.png)
```

`game/scenes/dev/raft_chimp_video.tscn` films the chimps' swing and the rafts (`media/chimp_swing_rafts.mp4`, 47 s): a chimp leaping up into the trees and swinging through them, dropping down where they end; a hippo and an elephant with their rafts packed, the rafts put down for riders, the crossing (4x); then close by at half speed (`-- --close-up`), a hippo's raft put down for two riders, and `Space` letting them off and the raft coming apart, a fresh pack on its back. `-- --rafts-only` films just the rafts. The video was cut together from the three runs (the map's loading frames and a stretch where the camera went through the bank cut out):

```sh
godot --path game --resolution 1280x720 --write-movie video.avi --fixed-fps 30 res://scenes/dev/raft_chimp_video.tscn [-- --rafts-only | --close-up]
```

### Jungle Keep showcase

Checks that the Jungle Keep's water can't be crossed on foot: on the navmesh the citadel has no way to any gate (its paths end on the river's south bank), nor the Outpost helipad to the east gate, while the Quarry helipad has one to the west gate, none of them into the water; and walkers driven straight at the rivers by physics alone (no navmesh) stop at the water's edge. With `--shots` it then takes stills round the map, units standing about for scale (a War Elephant and a Night Ops Chimp by the citadel's hull), and first-person ones through the garrison rifleman's eyes from the gun decks and the roofs:

```sh
godot --path game --headless res://scenes/dev/jungle_showcase.tscn   # prints and checks: JUNGLE SHOWCASE PASS / FAIL
godot --path game --resolution 1600x900 res://scenes/dev/jungle_showcase.tscn -- --shots=/tmp/jungle [--only=citadel,fps_roof_south]
# map_top, map_oblique, keep_clearing, rts_view, rts_river, citadel, citadel_scale, river, outpost, quarry,
# prison_cliff, prison_close, lake, forest_floor, canopy, fps_deck_south, fps_deck_east, fps_roof_south,
# fps_roof_west, fps_scope_south (.png)
```

How it is built (`game/scripts/match/jungle/`):

- `JungleLayout`: where everything is (the rivers' centrelines, the lake, the ridges, the plateau and its cliff, the quarry, the sites).
- `JungleTerrain`: the ground as a height grid every 2 m out to 880 m (past the map's edge), worked out on the worker threads from the layout, drawn in 100 m chunks with a splat-mapped shader (forest floor, the clearing's grass, mud by the water, rock on the steep faces and the quarry), collided with as a `HeightMapShape3D`. One water plane at -1.8 m shows only where the land dips under it; along its edge (the ground's contour just above it) stands an invisible wall on its own physics layer (`GameConfig.LAYER_WATER_EDGE`), in the masks of the walkers only, so shots, rays and the navmesh bake go through it. The navmesh gets the ground with all the water cut out (`nav_faces`).
- `JungleFlora`: the forest, from `Props.TREES`, `BUSHES` and `ROCKS` (no models of its own): scattered by kind, the stand (oak, birch or conifer) picked by a noise, and drawn in `MultiMesh` batches per 100 m chunk, the engine dropping to the meshes' lower LODs with the distance and the small plants past their visibility ranges. The trees are `ForestTree` proxies (collision, burning, Serpent nests) with no model of their own until they catch fire; their trunks stand where `Props.TRUNKS` says the models' trunks are. Only the big oaks' trunks are baked into the navmesh. The Serpent traps' bushes are `Bush` proxies, the rocks bodies with collision.
- `JungleLevel` (a `LevelBuilder`): the environment, the sites and the navmesh, baked in 200 m tiles on the worker threads (the static colliders parsed once, the ground added with the lake cut out of it, only the big oaks' trunks cut out of it: every polygon costs every navmesh query); an oak that falls rebakes only its tile. The squads' navmesh queries go through `LevelBuilder.nav_closest` / `nav_path`, which on the tiles look only round the point asked about (Godot's map-wide closest-point query goes over every polygon on the map).

### Infiltrator showcase

`game/scenes/dev/infiltrator_showcase.tscn` checks the Infiltrator Squad and the Forward Helipads on the real map, in the south field. A lone infiltrator and a Flame Trooper (a decoy) stand in reach of three Bear Riflemen: the riflemen shoot the decoy and leave the infiltrator alone (low profile); ordered to attack her, they do; under adaptive camo the order lapses, shots pass through her and a fresh order is refused, while a blast still hurts her. She looses arrows at the riflemen. Then a squad is bought and sent on a sabotage operation against the South Helipad past four riflemen standing on the straight way there: it walks round them, sabotages the helipad (the attackers can no longer spawn there and lose its supply), and comes home to restock its kit. The player takes command and puts the camo on (the vignette; the troopers as ever on the defender's side, not shown at all on the attacker's), and last three riflemen retake the helipad. The garrison's posts and the AA turrets hold fire.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/infiltrator_showcase.tscn -- --test  # prints and checks: INFILTRATOR SHOWCASE PASS / FAIL
godot --path game --fixed-fps 30 res://scenes/dev/infiltrator_showcase.tscn  # to watch it
```

`game/scenes/dev/infiltrator_video.tscn` records the squad's video (`media/infiltrator_showcase.mp4`), from the defender's side (the squad's camera and HUD, driven like a player would) and the attacker's (the RTS view): arrows at a group of Bear Riflemen (in the RTS view no tracer, no flash, just their health going), adaptive camo (the defender's vignette; in the RTS view the troopers gone from sight, and a bison's shell still hurting them), a sabotage of the South Helipad (sped up) and the RTS view of it lost, the riflemen retaking it, and last a second squad's idle mode: sent on a sabotage operation, it walks round the riflemen standing on the straight way (its planned route drawn) to the helipad.

```sh
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie infil.avi --fixed-fps 30 res://scenes/dev/infiltrator_video.tscn > infil.log
python3 tools/video/cut_showcase.py infil.avi infil.log media/infiltrator_showcase.mp4
```

`-- --snap=t1,t2 --snap-out=/tmp/shot` saves just those frames (seconds into the run).

### Weapons showcase

The infantry's guns (`game/scripts/combat/held_gun.gd`) hang on a `rifle` bone in their models, which `tools/gltf/arm_rifle.py` adds and poses the arms round in the Idle and Running clips:

- The garrison's **Cyber Orc Sentinel** (the rifleman on the east deck, post 6) carries the **Shadowline** assault rifle (`game/assets/weapons/shadowline_rifle/`), butt in the shoulder. Taken over, it is the first-person view model too, held in the Orc Sentinel's own gauntlets (`cyber_orc_sentinel_fp_arms.glb`: its arms cut out of the model by `tools/gltf/fp_arms.py`, posed bladed with the rifle straight ahead and lined up on the view model's rifle every frame). `RMB` doesn't look down the sight: the rifle's smart scope sends its picture to the visor (`game/scripts/ui/rifle_scope.gd`). The view zooms in a little and the rifle drops out of sight; the feed is graded cool with fine scan lines, a rolling band, a vignette, grain and slight colour fringing. Over it, in thin glowing lines (JetBrains Mono for the text, `game/assets/fonts/jetbrains_mono/`, Apache-2.0): a ring-and-posts reticle with stadia ticks, a tick bezel and turning arc segments (the posts kick out on each shot; red corners close on a hostile under the dot and name it); top left, a compass ring turning with the heading, a red delta spinning in it, the heading and elevation; bottom left, signal bars, the link and the magazine (a reload bar while reloading); right, a 0-800 m rangefinder scale with a red sweep running up and down it and a marker on the range to whatever is under the dot. Opening it, the panels slide in, the text types out and a scan beam runs down the screen. The other riflemen are as before.
- The **Bear Rifleman** carries the **Prototype C** heavy LMG (`game/assets/weapons/prototype_c_lmg/`) at the hip, right paw on the grip and left over the carry handle. Swimming, it slings it across its backpack: `tools/gltf/swim_bear.py` bakes its `Swim` (a dog paddle, the head up out of the water) and `Dive` (under the water, the body level) clips into the armed model, the `rifle` bone keyed across the back:

```sh
python3 tools/gltf/swim_bear.py --input game/assets/units/cyber_bear_commando/cyber_bear_commando_armed.glb \
    --gun game/assets/weapons/prototype_c_lmg/prototype_c_lmg.glb \
    --output game/assets/units/cyber_bear_commando/cyber_bear_commando_armed.glb [--preview out.png]
```

  Run after `arm_rifle.py` (which rebuilds the armed model from the rigged one without them); run again, it replaces the clips it baked before. The water line is at `SWIM_WATER` over the unit's origin in the clips: the bear's `swim_sink` in `unit_types.gd`.

Their rounds' tracers and muzzle flashes come from the guns' muzzles.

```sh
godot --path game --headless res://scenes/dev/weapons_showcase.tscn  # prints and checks: WEAPONS SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1600x900 res://scenes/dev/weapons_showcase.tscn -- --shots=/tmp/guns  # defender_fps, defender_scope(_2), defender_infantry, bear_infantry (.png)
```

Rebuilding the guns and the armed models:

```sh
python3 tools/gltf/process_rifle.py --input assets_src/weapons/shadowline_rifle/shadowline_rifle_meshy.glb \
    --output game/assets/weapons/shadowline_rifle/shadowline_rifle.glb --muzzle=-x --length 0.9 --grip 0.15,-0.02,0 \
    --point muzzle=-0.48,0.06,0 --point eye=0.33,0.15,0 --point butt=0.47,0.0,0 --point support=-0.08,-0.01,0
python3 tools/gltf/process_rifle.py --input assets_src/weapons/prototype_c_lmg/prototype_c_lmg_meshy.glb \
    --output game/assets/weapons/prototype_c_lmg/prototype_c_lmg.glb --muzzle=-x --length 0.95 --grip 0.15,-0.02,0 \
    --point muzzle=-0.47,0.065,0 --point eye=0.32,0.14,0 --point butt=0.47,0.0,0 --point support=-0.1,-0.03,0 --point handle=-0.02,0.165,0
python3 tools/gltf/arm_rifle.py --input game/assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel.glb \
    --gun game/assets/weapons/shadowline_rifle/shadowline_rifle.glb \
    --output game/assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel_armed.glb --fit [--preview out.png]
python3 tools/gltf/arm_rifle.py --input game/assets/units/cyber_bear_commando/cyber_bear_commando_rigged.glb \
    --gun game/assets/weapons/prototype_c_lmg/prototype_c_lmg.glb \
    --output game/assets/units/cyber_bear_commando/cyber_bear_commando_armed.glb \
    --support handle --pocket 0.2,-0.3,0.05 --cant 14 --pitch 3,12 --fit
# The first-person arms: the rifle straight ahead, the chest bladed, the left hand on the fore-end's side.
python3 tools/gltf/arm_rifle.py --input game/assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel.glb \
    --gun game/assets/weapons/shadowline_rifle/shadowline_rifle.glb --output /tmp/orc_fp_pose.glb \
    --cant 0 --pitch 0,0 --pocket 0.08,-0.03,0.08 --chest-yaw 40 --support side --pole-l 0.9,-0.45,-0.2
python3 tools/gltf/fp_arms.py --input /tmp/orc_fp_pose.glb \
    --output game/assets/defenders/cyber_orc_sentinel/cyber_orc_sentinel_fp_arms.glb --from ForeArm --upper 0.1
```

`--view=x,y,z` on the showcase tries another hip place for the first-person rifle (`DefenderSoldier.VIEW_HIP`).

### Vehicle showcase

Four machines, rigged and animated: the defenders' **Defender fighter jet** (18 m long, 20 m span), **Defender drone** (a small ducted-fan gunship, 1.8 m long) and **Iron Vanguard** hover tank (10 m with its gun forward), and the attackers' **Heavy Lift Helicopter**, an immense tandem lifter (64 m long, its rear rotor 42 m across) whose hold takes war elephants. The jet and the tank are in the match, bought and driven by the defending player (see *Fighter Jet* and *Hover Tank* under the defender's controls, and the *Machines showcase* below); the drone and the helicopter are not yet. Each has a rig (`game/scripts/vehicles/`) that loads its model and moves its parts; whoever moves the rig about only has to move it, and the rig reads how it is flying or driving off its own motion (`VehicleRig.follow_motion`; off, the inputs are set by hand):

- `FighterJetRig`: ailerons (opposite ways to roll), flaps (down below 110 m/s), all-moving stabilators (together to pitch, helping the roll), rudders on the canted fins, vectoring nozzles, and the engines' flames on the throttle, lighting the afterburners above it.
- `DroneRig`: the wing-tip fan pods tilt like a tilt-rotor's (up to hover, forward to fly, back to brake, opposite ways to turn on the spot) and the fans spin in their ducts, opposite ways, a blur disc over them at speed; the rear engines burn with the push; it leans into its acceleration and bobs when it hovers. `muzzle_L/R` mark the twin guns.
- `HoverTankRig`: rides 0.7 m up on four gimballed hover thrusters (blue jets that lean against where it is going, opposite ways front and rear to turn it), rear booster vents, the hull sitting back, dipping and rolling on its air cushion; `aim()` swings the turret and elevates the gun onto a point, `muzzle()` is where the shell leaves. `fire()` works the main gun like a real tank gun's: a blast of flame, light and smoke, the barrel driven 0.6 m back into its cradle in 0.14 s, held there a moment, then run out slowly by the recuperator over 1.5 s, the muzzle jumping up and settling; the whole tank takes the kick, rocking back on its air cushion away from the shot and swaying a few times as it settles, jolted and shaken for a moment. Its machine guns are the twin-barrelled guns in the sponsons on the hull's sides (`mg_L/R`): each turns on its mount onto the aim, as far as its sponson lets it (45° out to its side, 10° in across the bow, 8° down to 30° up), and fires while `mg_firing` is on: 10 rounds a second each, its two barrels in turn, a flash and a kick on every round and a tracer every third (`mg_round` reports each round).
- `HeavyLiftRig`: `start()` / `stop()` spool the two counter-rotating rotors and the ducted tail fan up and down (blur discs come up with them); the rotor discs tilt with the cyclic and opposite ways across to turn it; the body follows slowly.

`game/scenes/dev/vehicle_showcase.tscn` flies and drives them on a plain field (`media/vehicle_showcase.mp4`): the tank speeds off, stops, turns, fires its main gun at a bunker on a rock, a burst from the machine guns in its side sponsons and the main gun again; the drone hovers, flies off, turns, brakes and hovers again; the jet rolls into a hard turn, rolls out and climbs away on afterburner; one helicopter spools up on the ground beside a war elephant, another flies by, speeds up and stops.

After pulling, fetch the models and let Godot import them before running it (opening the project in the editor does the import too); without them it says which models it can't load and quits:

```sh
git lfs pull
godot --path game --headless --import
godot --path game --headless --fixed-fps 30 res://scenes/dev/vehicle_showcase.tscn -- --test  # prints and checks: VEHICLE SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/vehicle_showcase.tscn -- --snap=10.1,30.5,52 --snap-out=/tmp/vehicles  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie vehicles.avi --fixed-fps 30 res://scenes/dev/vehicle_showcase.tscn
```

`-- --cam=tank|drone|jet|helo|lift` keeps the camera on one of them.

`-- --pad` stages the Jungle Keep's Outpost at its size with the Heavy Lift Helicopter parked on its pad, rotors turning, and a war elephant on the deck beside it; with `--test` it checks that the helicopter's whole footprint, the rotors' sweep included (64 by 45 m), lies inside the pad's touchdown square (70 by 63 m: 2.8 m clear at the nose and tail, 8.5 m at the sides):

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/vehicle_showcase.tscn -- --pad --test  # PAD CHECK PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1600x900 --fixed-fps 30 res://scenes/dev/vehicle_showcase.tscn -- --pad --snap=3.5,6,10 --snap-out=/tmp/pad
```

### Drone showcase

`game/scenes/dev/drone_showcase.tscn` puts the defenders' drones on a plain field with a ring of roof docks and a few attackers. Run plain, three swarms seek and shoot a medic, a kangaroo, a hippo and a giraffe. With `--test` it steps everything by hand at 1/30 s and checks: the fuel rules (a third of a tank per fortress size, 5% per 10 s hovering, the turn at 50%, the earlier turn far out, landing with fuel to spare, refuelling at 1.75 s per second of fuel spent: 35 s for 20 s of fuel, 350 s for an empty tank), the six swarms and the hangar (three drones down is a damaged swarm, still one of six; every missing drone is back after 385 s, all at once; a swarm shot to pieces stays one of the six and is whole again after one rebuild time; a returned drone is refilled faster than a lost one is rebuilt), every call getting the freshest swarm (a whole one, then one with tanks at 90%, then the damaged one), one focus per swarm (the medic first, then the kangaroo, never two targets, no drone out of fuel), who can touch a drone (a bear locks on and holds its orders, a kangaroo doesn't; blasts and rifle rounds pass through, a bear's round and an AA unit's guns hurt) the water (a swimming bear is the swarm's pick over a kangaroo on dry land, a diving one is never picked and is dropped the moment it dives, and a drone's round passes through it), a docked drone being hidden, the calls (a near spot, the same spot twice, a spot too far out, every drone recharging), a swarm called to nothing (it flies out, comes home, docks, is nothing again and can be called again; a call nobody can answer lapses) and the garrison's own calls (they can't take a busy swarm, yours can).

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/drone_showcase.tscn -- --test   # DRONE SHOWCASE PASS / FAIL
godot --path game res://scenes/dev/drone_showcase.tscn
```

### Machines showcase

`game/scenes/dev/machines_showcase.tscn` plays the defenders' two machines the way a player does, on the real map (the Jungle Keep): bought with `J` and `H`, taken over with `F1`/`F2`, flown and driven in their own chase cameras and panels, the showcase working the keys and the mouse as their pilot (`DefenderMachine.pilot`). It runs on the whole map, so the level takes a while to load. The run:

- `buy`: the jet and the tank on the roster (the hotbar), their 600 and 450 credits out of the chest.
- `cruise`: the jet in its chase camera; `Shift`, the boost (afterburners, the view widens, 200 m/s, the boost runs down and comes back); a hard turn banks it.
- `bomb`: a bombing run on a knot of attackers in the clearing: the ring, disc and column of the bomb preview on the ground follow the jet as it flies; a bomb is let go when the preview is on them, falls, and lands on the spot the preview showed (0.0 m off in the checks) and kills what it falls on; the bay refills.
- `salvo`: the missile barrage twice. Flying straight, the 16 missiles leave within a degree of each other (0.7° in the checks); through a hard turn they scatter over the 60° or so the nose swept (62° between the first and the last in the checks).
- `crash`: the jet flown into the ground blows up and is gone for good (off the roster); a second one is shot down (it spins out of the sky, then crashes); a War Elephant locks on to a jet flying low over it.
- `drive`: the tank driven off (15 m/s), turning onto the way it goes, stopped by the stronghold's wall, hovering out over the river and skimming the water.
- `guns`: the turret swings onto the crosshair and the main gun fires (the shell bursts on the crosshair's point, the blast takes the knot of attackers); the machine guns after it.
- `machine guns` / `ballistics` / `tank jump` / `trees`: the machine guns firing along the hull while the turret is on a target 90° off to the side (every round within 4° of the front, the sponson guns toed in, a target at the crossing point shot and the one under the crosshair not, a tracer every other round); the cannon: a target 150 m off with the crosshair on it hit 0.1 m from it, one 420 m off with the crosshair on it coming down 115 m short (305 m out, where the physics for the barrel as it was gives 306), and the crosshair raised landing it at 430 m; the jump (squat 100%, jets 80% in the charge and 100% at the burst, 11.9 m up, 57 m along, 3.1 s, touching down at 3.1 m/s with the jets at 100%, a second one refused for the cooldown, one flown at the stronghold's wall setting down in front of it); a tree struck (stops dead, 85 health, held 3.4 s, the tree down, the way clear) and a median stretch of forest driven through.
- `idle`: the player leaves the tank (takes a jet): it holds its ground and shoots what comes in reach.
- `idle` (the jet): a jet left alone circles the spot where it was left; a War Elephant 70 m off its path, and riflemen, are left alone; when the elephant is moved onto its path and locks on, it sets up and bombs it (the bomb lands 0.7 m from it in the checks), flies back to where it was left and circles again; a second elephant, one that has never locked on, is bombed after the jet is hurt. `--only=idle` plays just this.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/machines_showcase.tscn -- --test  # prints and checks: MACHINES SHOWCASE PASS / FAIL
godot --path game --headless --fixed-fps 30 res://scenes/dev/machines_showcase.tscn -- --test --only=tank  # just the tank (--only=jet: just the jet, --only=idle: just the jet left alone)
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/machines_showcase.tscn -- --snap=5.6,18.6,24.3 --snap-out=/tmp/machines/shot  # just those frames
```

`--snap=t1,t2,..` draws and saves only the frames at those times (seconds of the run: the run prints `MACHINES t=...` as each step starts); between them the render loop is off. The stills of a spectator's camera (the bomb's burst, the missiles' patterns) hide the panels. On a machine with no GPU (Mesa's software GL) the game's own sky shader can't compile, so the showcase puts a plain procedural sky in when it runs on the compatibility renderer, and draws the stills with a lighter shadow map and no multisampling.

The game's own scripted match buys both too (`--autotest=defender`: an unattended jet holds its course, a tank holds its ground).

## Asset pipeline

Meshy exports go in `assets_src/`, then get processed with Blender (headless):

```sh
blender -b --python tools/blender/process_meshy_model.py -- \
    --input assets_src/units/cyber_bear_commando/cyber_bear_commando_meshy.glb \
    --output game/assets/units/cyber_bear_commando/cyber_bear_commando.glb
```

This puts the pivot at the feet (or the bounding-box center with `--pivot bbox`, for long vehicles), rescales to a real height in meters (`--height`), turns the model to face forward (`--rotate-z`), and shrinks textures (`--tex`, `--orm-tex`). Settings used so far:

| Unit | `--height` | other |
|---|---|---|
| cyber_bear_commando | (as exported) | |
| kangaroo_commando | 2.0 | |
| sky_talon_battalion | 2.1 | |
| battlefield_lifesaver | 1.4 | |
| war_elephant_sentinel | 3.8 | `--pivot bbox` |
| cyber_mule_artillery | 2.2 | `--rotate-z 90 --pivot bbox` |
| war_ram | 1.6 | |
| night_ops_chimpanzee | 1.7 | |
| savanna_signal_scout | 4.5 | |
| hippopotamus_heavy_gunner | 2.6 | `--pivot bbox` |
| semi_futuristic_pair | 2.4 | `--pivot bbox` |
| armored_lioness_unit | 1.6 | |
| serpent_sniper | 0.9 | `--rotate-z 56 --pivot bbox` |
| armored_rhino_unit | 2.4 | `--pivot bbox` |

The Night Ops Chimp's export comes with Meshy's Mixamo-style rig and its `Idle` and `Running` clips. `tools/gltf/swing_chimp.py` bakes a third, `Swing`, into it (numpy on the glTF, no Blender, with `rig_infiltrator.py`'s rig helpers like `swim_bear.py`): swinging hand over hand through the trees, a 0.8 s loop of two swings at its forest speed (8.8 m/s, 3.5 m from hold to hold). Each hand takes a hold over its side (the right one hooks its axe over the branch), the body swings forward under it like a pendulum, leaning toward the hold, while the free arm swings down past its side and reaches on for the next; it lets go just past the bottom of the swing and flies on to the next hold, the legs hanging and swinging, the head looking ahead. The holds are 2.45 m over the unit's origin in the clip (`swing_hold` in `unit_types.gd`: the game lifts the model so they are up under the canopy); they slide back at the clip's speed, so played at the unit's speed the hands stay on them. The fingers and the axe keep the Running clip's first frame. `--preview` draws frames of the loop with the holds as bars; run again, it replaces the clip:

```sh
python3 tools/gltf/swing_chimp.py --input game/assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb \
    --output game/assets/units/night_ops_chimpanzee/night_ops_chimpanzee_rigged.glb [--preview out.png]
```

The War Elephant's export has no rig, so `tools/blender/rig_elephant.py` builds one and bakes its clips. It scales the model to 3.8 m, puts its origin between the four feet, skins it (legs, trunk, ears and tail as bone chains) and bakes a looping `Walk` (feet planted by IK, the trunk swinging and curling) and `Idle`. The cannons, missile pods and radar get bones of their own that the game drives (`ElephantTurrets`). Run it with Blender 5.2, or with the `bpy` 5.2 pip package; `--preview DIR` also renders the clips:

```sh
python tools/blender/rig_elephant.py -- \
    --input assets_src/units/war_elephant_sentinel/war_elephant_sentinel_meshy.glb \
    --output game/assets/units/war_elephant_sentinel/war_elephant_sentinel_rigged.glb
```

The Heavy Gunner (the minigun defender) comes with Meshy's auto-rig but no clips. `tools/blender/rig_heavy_gunner.py` keeps the auto-rig's skin weights for the body but rebuilds its bones with clean names, scales the model to 2.25 m with its origin under the hips, re-skins the minigun rigidly onto a `gun` bone (the barrel cluster onto `barrels`, which the game spins; `muzzle` marks the tips) and takes the left leg's pull off the ammo belt. Every clip twists the torso about 34° so the barrels point straight ahead. It bakes `Idle` and eight `Walk_<dir>` clips (F, FR, R, BR, B, BL, L, FL), all in step so the game blends them by direction (`HeavyGunner`), feet planted by IK; `GunnerRig` bends the spine onto the aim at run time. Same Blender/`bpy` 5.2 as above; `--preview DIR` renders the clips:

```sh
python tools/blender/rig_heavy_gunner.py -- \
    --input assets_src/defenders/heavy_gunner/heavy_gunner_meshy.glb \
    --output game/assets/defenders/heavy_gunner/heavy_gunner_rigged.glb
```

The Missile Trooper (the AA Squad's) is the Armored Sentinel, whose export has a Mixamo-style auto-rig in a T-pose and a Running clip. `tools/blender/rig_missile_trooper.py` rebuilds its bones with the Heavy Gunner's names (keeping the body's weights), scales it to 1.95 m and re-skins its shoulder pod rigidly: the housing onto `launcher` (which the game swings onto the aim, `MissileRig`), each of the six missiles onto its own `missile_<k>` bone, its head at the missile's nose and its Y axis along the tube (the game launches from there and hides a missile once it has left), the mount onto the chest; the cables from the pod lose their pull from the left leg. It bakes the same `Idle` and eight `Walk_<dir>` clips as the Heavy Gunner, at the same speeds and timing (the same leg IK), with both arms hanging and swinging:

```sh
python tools/blender/rig_missile_trooper.py -- \
    --input assets_src/defenders/armored_sentinel/armored_sentinel_meshy.glb \
    --output game/assets/defenders/armored_sentinel/missile_trooper_rigged.glb
```

The Flame Trooper (the Flame Squad's) is the Crimson Warden, who already wears twin fuel tanks and holds a flame gun at her right hip; her export has the same Mixamo-style auto-rig and a Running clip. `tools/blender/rig_flame_trooper.py` rebuilds the bones with the Heavy Gunner's names (keeping the body's weights; the auto-rig's right foot chain is off by one bone), scales her to 1.95 m and re-skins the gun rigidly onto a `gun` bone in the right hand (`nozzle` marks the muzzle, its Y axis along the barrel: the game lights the flame there, `FlameRig`), the tank pack rigidly onto the chest, and takes the hose's pull off the legs. The gun points about 29° off to her right, so every clip twists the torso that far to the left (like the Heavy Gunner's), the right arm stays on the gun and the left one swings; the feet, off-centre in the export, are planted evenly either side of the hips. It bakes the same `Idle` and eight `Walk_<dir>` clips as the Heavy Gunner:

```sh
python tools/blender/rig_flame_trooper.py -- \
    --input assets_src/defenders/crimson_warden/crimson_warden_meshy.glb \
    --output game/assets/defenders/crimson_warden/flame_trooper_rigged.glb
```

The Bison Field Gun (two bisons with a gun slung between them) has no rig either: `tools/blender/rig_bison_gun.py` builds one. It scales the model to 2.4 m with its origin between the eight hooves. The export has both bisons mid-stride, so the script first stands their legs the way they stand at mid-stance (moving them with their bones, then relaxing the skin where they join the body as rigidly as it can) and binds the rig there. Each bison gets its own bones (`L_` for the one on the pair's left, `R_` for the other) and both walk the elephant's lateral-sequence walk, R a little out of step with L: planted hooves stay put by IK and roll over the toe, the knees and hocks fold in the swing, the bodies ride and sway over their legs, the heads nod and the tails swing. The gun rides on a `carriage` bone that follows where the two bisons' flanks carry it; `muzzle` marks the barrel tip. It bakes `Walk` (authored at 1.85 m/s, the UnitTypes `anim_ref_speed`) and `Idle`. Same Blender/`bpy` 5.2 as above; `--preview DIR` renders the clips:

```sh
python tools/blender/rig_bison_gun.py -- \
    --input assets_src/units/semi_futuristic_pair/semi_futuristic_pair_meshy.glb \
    --output game/assets/units/semi_futuristic_pair/semi_futuristic_pair_rigged.glb
```

The Sky Talon (the hawk) comes with Meshy's SmartRig, standing with its wings folded down its flanks, and no clips. `tools/blender/rig_talon.py` keeps Meshy's bones and weights for the body, head, legs and tail, and re-skins each wing onto two new bones in place of Meshy's wing bones: `wing_L` / `wing_R` (the inner wing, hinged at the shoulder) and `hand_L` / `hand_R` (the outer wing and its long feathers, hinged at the wrist). The box strapped to the left wing rides rigidly on `wing_L`, like a pod. The model stands 2.1 m tall with its feet at the origin (the rest pose), and the script bakes two looping clips in a flight pose: the body levelled out, the legs tucked back under the tail and each wing lifted out level, its hand swept forward so the feathers point out along the span (spread, the wings grow to a hawk's span, about twice its length). `Glide` holds the wings out with a slight dihedral, flexing in the air, while the tail steers and the head looks round and down at the ground. `Flap` is one 0.8 s wing beat: up with the hand tucked in, a full downstroke, the hand lagging behind the arm and the body lifting with each stroke. The game crossfades between them (`TalonFlight`). Same Blender/`bpy` 5.2 as above; `--preview DIR` renders the pose and the clips:

```sh
python tools/blender/rig_talon.py -- \
    --input assets_src/units/sky_talon_battalion/sky_talon_battalion_rigged_meshy.glb \
    --output game/assets/units/sky_talon_battalion/sky_talon_battalion_rigged.glb
```

The Kangaroo Commando comes with Meshy's auto-rig and no clips, crouched the way a kangaroo stands before a hop. `tools/blender/rig_kangaroo.py` rebuilds the auto-rig's bones with clean names (keeping the weights of the body, head, tail and hind legs), replaces its arm chains, which sit in the side-mounted SMGs, with forelimb chains re-skinned along the real forelimbs, and binds the gear rigidly: the SMGs on the chest, the gun on its back on the spine, the supply pack on the hips, the goggles on the head. `muzzle_L` / `muzzle_R` mark the SMGs' muzzles and `grenade` the right paw's grip (the game fires and throws from there; `KangarooRig` rears the chest up onto the aim). It scales the model to 2 m with its origin between the hind feet and bakes three clips: `Idle` (crouched, breathing, the head looking round, the tail resting on the ground), `Hop` (one bound at 7.2 m/s: both feet land together ahead of the hips and sweep back planted by IK, push off from the toes and swing forward through a long flight, the tail swinging against the legs and the forepaws tucked in) and `Throw` (it rears up like a boxer, propped on its tail with its paws up in a guard, winds up with the right paw cocked by its ear, throws, follows through and drops back into its crouch). Same Blender/`bpy` 5.2 as above; `--preview DIR` renders the clips:

```sh
python tools/blender/rig_kangaroo.py -- \
    --input assets_src/units/kangaroo_commando/kangaroo_commando_rigged_meshy.glb \
    --output game/assets/units/kangaroo_commando/kangaroo_commando_rigged.glb
```

The Savanna Signal Scout (the Giraffe) comes with Meshy's auto-rig, but its bones are no good for walking (the antennas on its back got bone chains, the neck has gaps), so `tools/blender/rig_giraffe.py` builds a new skeleton along the giraffe, like the War Elephant's: the four legs (upper, lower and a cannon bone from the knee or hock down through the hoof), the neck in three bones, the head, the tail and the torso in three, skinned by region. The gear stays on: the helmet and goggles ride the head, the plates along the neck bend with it, everything on the back rides the torso where it sits, and the radar dish (disc, feed arm and strut) rides a `dish` bone that turns it about its mast. It scales the model to 4.5 m (to the tallest antenna) with its origin in the middle of the four hooves and bakes three clips: `Walk` (at 3 m/s, the UnitTypes `anim_ref_speed`: a lateral sequence close to a pace, hooves planted by IK and rolling over the toe, the cannons folding back through the swing, the body riding as high as the planted legs allow and rolling over the side that is down, the neck pumping with every step and the head level), `Idle` (breathing, weight shifts, the neck and head looking round the field) and `Ping` (not looped: the neck stretches up, the dish sweeps right round its mast and back, the pulse goes out 0.8 s in). Same Blender/`bpy` 5.2 as above; `--preview DIR` renders the clips:

```sh
python tools/blender/rig_giraffe.py -- \
    --input assets_src/units/savanna_signal_scout/savanna_signal_scout_rigged_meshy.glb \
    --output game/assets/units/savanna_signal_scout/savanna_signal_scout_rigged.glb
```

The Infiltrator (the Infiltrator Squad's trooper) is the Harpy Vanguard, rigged and animated without Blender: `tools/gltf/rig_infiltrator.py` runs on numpy alone, on the glTF itself. It takes the garrison's processed Harpy Vanguard (1.7 m, Meshy's Mixamo-style auto-rig in a T-pose), keeps its mesh and skin weights, renames the bones to the squad troopers' names (`pelvis`, `spine_1`, … `toe_R`; the fingers `index_1_L` and so on) and adds two marker bones with no weights: `bow` in the left hand (the grip; its Y axis up the bow, Z toward the target) and `nock` in the right (where the arrow's nock sits on the drawn string). The game builds the bow, its string and the arrows on them (`InfiltratorTrooper`). Every clip holds an archer's stance: side-on, the chest turned 78° to the right of where she faces, the head turned back to look down the arrow, the bow arm out on the aim and the string drawn to the right of her chin, the arms solved by IK every frame onto targets that ride the chest; the rest pose is this stance too. It bakes `Idle` and eight `Walk_<dir>` clips at the squad troopers' clip speeds (the same gait as `rig_heavy_gunner.py`: feet planted by IK, the hips riding as high as the planted legs allow), each cycle 20 frames. `--preview DIR` renders the rest pose and frames of each clip with a plain numpy rasterizer:

```sh
python3 tools/gltf/rig_infiltrator.py \
    --input game/assets/defenders/harpy_vanguard/harpy_vanguard.glb \
    --output game/assets/defenders/harpy_vanguard/infiltrator_rigged.glb
```

The Armored Lioness comes with Meshy's auto-rig and a walk, but the rig is no good for her (the flamethrower rig on her back is skinned mostly to the head and the tail, the neck has no bone, the hind legs' joints sit in the flanks), so `tools/gltf/rig_lioness.py`, on numpy alone like the Infiltrator's, keeps the mesh and builds a new skeleton along the lioness, skinned by region like the Giraffe's: the torso in three bones, the neck, the head and the jaw, each leg in four (a cat walks on its toes) and the tail in five. The gear stays on: the flamethrower rig (turret, barrels, fuel tanks and hoses) rides rigidly on the body, small pieces ride rigidly where they sit, straps bend with the skin. `nozzle_1` and `nozzle_2` mark the two barrels' mouths, their Y axis out of the barrel (the game lights the fire blast there, `LionessRig`). It bakes six clips: `Walk` (at 1.7 m/s, the UnitTypes `anim_ref_speed`: a lateral sequence, paws planted by IK, the fore paws folding back at the wrist through the swing), `Run` (a rotary gallop at 6 m/s), `Sneak` (the stalk at 2.2 m/s, belly low, the head low and still, each paw lifted high and set down slowly), `Idle`, `Pounce` (not looped: she sinks onto her haunches, wiggles her rump, springs and flies stretched out, claws out, landing on the prey) and `Strike` (not looped: she rears up and swipes down with the right paw, biting as the head lunges in). It runs on its own output too (the rig is rebuilt from the mesh each time); `--preview DIR` renders the rest pose and frames of each clip:

```sh
python3 tools/gltf/rig_lioness.py \
    --input game/assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb \
    --output game/assets/units/armored_lioness_unit/armored_lioness_unit_rigged.glb
```

The Serpent Sniper's Meshy auto-rig is no good for coiling (the helmet is skinned to a bone in the rifle's barrel, nearly a metre of the body to a single bone). `tools/blender/animate_serpent.py` turned the export to face forward and scaled it to 0.9 m; `tools/gltf/rig_serpent.py`, on numpy alone like the Lioness's, keeps the mesh and builds a new skeleton along the snake: `head` and 40 spine bones evenly down the body to the tail tip, one chain, each bone's Y axis along the body toward the tail and Z out of its back, so the game can lay the body along any curve (`SerpentRig`: up a trunk, round a bush or its prey). Every vertex of the skin and of the gear that hugs it (the vest, the straps) is weighted between the two bones either side of where it lies along the body; the helmet and goggles ride rigidly on the head. The rifle rides on a bone of its own (`rifle`, `muzzle` at the barrel's tip), so the game can hide it in a bush for the bush trap; `snout` marks the tip of the snout. It bakes `Slither` (lateral undulation at 2.4 m/s, the UnitTypes `anim_ref_speed`: a wave running down the body from the shoulders, the gun held straight and level) and `Idle` (breathing, the tail tip curling). It runs on its own output too (the rig is rebuilt from the mesh each time); `--preview DIR` renders the rest pose, frames of each clip and two of the skills' poses (wound round a trunk, coiled flat on the ground):

```sh
python3 tools/gltf/rig_serpent.py \
    --input game/assets/units/serpent_sniper/serpent_sniper_rigged.glb \
    --output game/assets/units/serpent_sniper/serpent_sniper_rigged.glb
```

The Sniper is the garrison's Grey Veil Warden (1.7 m, Meshy's Mixamo-style auto-rig) with the Eclipse Longshot shouldered. The rifle first goes through `tools/gltf/process_rifle.py` (numpy and Pillow, no Blender): it turns the export so the muzzle points +Z with its top up, scales it to 1.15 m muzzle to butt, puts its origin at the top of the pistol grip, shrinks its textures and adds marker nodes the rig and the game find by name (`muzzle`, `eye` on the scope's axis behind the eyepiece, `butt`, `support` under the fore-end, `scope`):

```sh
python3 tools/gltf/process_rifle.py \
    --input assets_src/defenders/grey_veil_warden/eclipse_longshot_meshy.glb \
    --output game/assets/defenders/grey_veil_warden/eclipse_longshot.glb \
    --muzzle=-x --length 1.15 --grip 0.225,-0.04,0 \
    --point muzzle=-0.479,0.022,0 --point eye=0.31,0.116,0 --point butt=0.479,-0.02,0 \
    --point support=-0.02,-0.045,0 --point scope=0.225,0.116,0
```

Then `tools/gltf/rig_sniper.py`, on numpy alone like the Infiltrator's (whose helpers it uses), keeps her mesh and skin weights, renames the bones to the squad troopers' names and adds a `rifle` marker bone on the chest at the rifle's own frame (the game hangs the rifle model there, `SniperTrooper`). Every clip holds a rifleman's standing stance: bladed, the butt in the right shoulder pocket, the rifle level and straight ahead, the head down on the stock with the right eye on the scope's axis (the cheek weld, solved by a small least-squares fit of the spine's lean and the neck's and head's nod and cant), the right hand on the pistol grip with the index finger along the trigger and the left under the fore-end, the arms solved by IK every frame onto targets that ride the chest. It bakes `Idle` (breathing, a slow weight shift, the eye never leaving the scope) and eight `Walk_<dir>` clips at the squad troopers' clip speeds (the legs walk like the Infiltrator's while the chest, the head and the rifle stay steady on the aim). `--preview DIR` renders the rest pose and frames of each clip, the rifle in her hands:

```sh
python3 tools/gltf/rig_sniper.py \
    --input game/assets/defenders/grey_veil_warden/grey_veil_warden.glb \
    --rifle game/assets/defenders/grey_veil_warden/eclipse_longshot.glb \
    --output game/assets/defenders/grey_veil_warden/sniper_rigged.glb
```

The Wolf Medic keeps Meshy's auto-rig and its `Walk` and `Idle`; `tools/gltf/animate_dog.py` (numpy alone, using the Infiltrator's rig and IK helpers) adds its `Dig` clip: the hind legs planted by IK, the body tipped forward and the chest lowered, the head low over the hole and nodding with each stroke, the fore paws scraping in turn (each lands at the front of the hole, drags back under the chest with the claws raking, then curls up and swings forward again, the wrist placed by IK and the elbow bending back), the tail up and wagging. One loop is 1 s, two strokes of each paw; the game throws the dirt from under the chest as each paw finishes its drag (UnitTypes `dig_sprays`, `dig_spray_at`). It replaces a `Dig` clip already there, so it runs on its own output; `--preview DIR` renders frames of it:

```sh
python3 tools/gltf/animate_dog.py \
    --input game/assets/units/battlefield_lifesaver/battlefield_lifesaver_rigged.glb \
    --output game/assets/units/battlefield_lifesaver/battlefield_lifesaver_rigged.glb
```

The Mule Artillery's export has no rig: six donkeys in three pairs, in harness, towing a tracked siege gun whose barrel reaches out over them, each part its own piece of the mesh. `tools/gltf/rig_mule.py` (numpy alone, using the Infiltrator's rig and IK helpers) keeps the processed static model's mesh and sorts its pieces out: each donkey gets a body, a neck and a head bone (its ears ride the head, its saddle pads the body) and a two-bone leg for every leg it has (the groups of its vertices below the belly: the fore legs are the two frontmost, the rest hind legs; the swing and wheel donkeys were generated with an extra one, which steps as a leg of its own). The harness (the traces along the flanks and between the pairs, the bars across them) goes with the donkey it lies over, the reins with the head, and is blended between the donkeys across the gaps (the last traces into the gun's hitch). The gun: the tracked chassis (`root`); the turret (`turret`, everything on the chassis deck), which the game turns about Y; the cradle (`cradle`: the mantlet, its trunnion hubs, the recuperators and the barrel), elevating about the hubs; and the front of the barrel (`tube`), which the game slides back on a shot (`MuleGun`); `muzzle` marks its tip. It bakes four clips: `Walk` (authored at 1 m/s, the UnitTypes `anim_ref_speed`: each donkey walks a lateral sequence in a step of its own, hooves planted by IK, the body riding as high as its planted legs allow and leaning into the collar, the head nodding with the fore legs), `Idle` (hitched, breathing, heads looking about), `Setup` (not looped, 7 s, the UnitTypes `setup_time`: the team halts and the heads come up, the barrel rises out of its travel position to 40°, overshoots a little and settles while the donkeys watch it go up, then they drop their heads to graze; the game plays it backward to disarm) and `Armed` (grazing under the raised barrel; it starts where `Setup` ends). `--preview DIR` renders the rest pose, frames of each clip and the set-up gun traversed round:

```sh
python3 tools/gltf/rig_mule.py \
    --input game/assets/units/cyber_mule_artillery/cyber_mule_artillery.glb \
    --output game/assets/units/cyber_mule_artillery/cyber_mule_artillery_rigged.glb
```

The machines (the fighter jet, the drone, the hover tank and the heavy lift helicopter) have no rig in Meshy's sense: their moving parts are pieces of the mesh. `tools/gltf/rig_vehicles.py` (numpy alone) turns each to face +Z at its game size, its origin on the ground under it, and cuts those parts out into nodes of their own at their pivots: whole where the mesh has them apart (rotor blades and hubs, fans, the turret, the gun, the sponson machine guns, the hover pads, the stabilators, the engine cans), cut out of it where it doesn't (each aileron and flap out of its wing along a hinge line at 72% of the chord, each rudder out of its fin), every triangle across a cut clipped exactly at it. Hinges turn about their node's local X (a positive angle: the trailing edge down, a rudder's to the left, a nozzle's exit down, the gun's muzzle up, a fan pod tilting forward), spinners (rotors, fans, the turret, the machine guns) about its local Y; markers (`exhaust_*`, `muzzle*`, `jet_*`, `booster_*`, `missile_*`, `mg_muzzle_*`) point their +Z out of the barrel or along the exhaust. `--preview` draws the parts in colours of their own, at rest and moved:

```sh
python3 tools/gltf/rig_vehicles.py --vehicle fighter_jet \
    --input assets_src/defenders/defender_fighter_jet/defender_fighter_jet_meshy.glb \
    --output game/assets/defenders/defender_fighter_jet/defender_fighter_jet.glb [--preview out.png]
python3 tools/gltf/rig_vehicles.py --vehicle drone \
    --input assets_src/defenders/defender_drone/defender_drone_meshy.glb \
    --output game/assets/defenders/defender_drone/defender_drone.glb
python3 tools/gltf/rig_vehicles.py --vehicle hover_tank \
    --input assets_src/defenders/iron_vanguard/iron_vanguard_meshy.glb \
    --output game/assets/defenders/iron_vanguard/iron_vanguard.glb
python3 tools/gltf/rig_vehicles.py --vehicle helicopter \
    --input assets_src/units/heavy_lift_helicopter/heavy_lift_helicopter_meshy.glb \
    --output game/assets/units/heavy_lift_helicopter/heavy_lift_helicopter.glb
```

Static props (scenery, turrets) skip Blender: they go through [glTF-Transform](https://gltf-transform.dev) to put the pivot at the bottom center and shrink textures to 1024 px, and `game/scripts/match/props.gd` scales them to height at load time:

```sh
npx @gltf-transform/cli center assets_src/environment/trees/majestic_oak/majestic_oak_meshy.glb t1.glb --pivot below
npx @gltf-transform/cli resize t1.glb t2.glb --width 1024 --height 1024
npx @gltf-transform/cli jpeg t2.glb t3.glb --quality 85 --slots "{baseColorTexture,metallicRoughnessTexture,occlusionTexture}"
npx @gltf-transform/cli weld t3.glb game/assets/environment/majestic_oak/majestic_oak.glb
```

| Prop | Used for |
|---|---|
| birch_tree, silver_birch, white_birch_majesty, majestic_oak, solitary_evergreen | trees around the map; the Jungle Keep's forest (`JungleFlora`) at real heights |
| mossy_berry_rock, mossy_mountain_garden | rocks (with collision); the Jungle Keep's cliff, quarry and forest rocks |
| meadow_garden, meadow_tuft, wild_meadow_tangle, berry_woodland_miniature | ground cover (visual only); the Jungle Keep's shrubs, ground cover and bush traps |
| sentinel_bastion | south gate machine gun; unmanned gun-deck mounts |
| orbital_sentry_gun | east/west gate machine guns; unmanned gun-deck mounts |
| arctic_sentinel_cannon | mortar on the south roof |
| sentinel_spire | roof (AA) mounts |
| forward_helipad_base | the attackers' Forward Helipad Bases (`AttackerBase`, 14.7 m to the mast tips: the deck 39 by 30 m, its pad's white touchdown square 13.4 by 12.2 m, room for a transport helicopter). A base can be bigger (`scale_factor`): the Jungle Keep's Outpost is 5.2 times it, its pad 70 by 63 m, room for the Heavy Lift Helicopter |
| violet_fortress | the Jungle Keep's prison (`JungleLevel`, 42 m to the top of the watchtower) |
| mobile_command_citadel | the Jungle Keep's main spawn, the Mobile Command Citadel (`JungleLevel`, 50 m to the top of its masts: a land carrier with the army aboard) |
| tow_platform | the pontoon raft every hippo and elephant carries on the Jungle Keep (`TowPlatform`, 6 m long: a deck on six float drums), cut into its pieces by `split_raft.py` (below) |

Without Node.js at hand, `tools/gltf/process_prop.py` does the same (pivot at the bottom centre, textures fitted to 1024 px and re-encoded as JPEG at 85) on numpy and Pillow; it is how the helipad, the prison, the citadel and the tow rafts were processed (the prison and the citadel with `--size 2048`: they are big):

```sh
python3 tools/gltf/process_prop.py --input assets_src/structures/forward_helipad_base/forward_helipad_base_meshy.glb \
    --output game/assets/structures/forward_helipad_base/forward_helipad_base.glb
```

```sh
python3 tools/gltf/process_prop.py --input assets_src/structures/violet_fortress/violet_fortress_meshy.glb \
    --output game/assets/structures/violet_fortress/violet_fortress.glb --size 2048
python3 tools/gltf/process_prop.py --input assets_src/structures/mobile_command_citadel/mobile_command_citadel_meshy.glb \
    --output game/assets/structures/mobile_command_citadel/mobile_command_citadel.glb --size 2048
```

The tow raft folds up, opens out and comes apart in pieces, so after `process_prop.py` it is cut up by `tools/gltf/split_raft.py`: the six float drums with their straps (told apart by how the Meshy mesh's parts are connected), and the deck cut across into its rear, middle and front sections (between the drums, every triangle across a cut clipped exactly at it), with what stands on each (railings, the control box, the hose) apart from its deck. The pieces stay in the raft's frame, in metres (6 m long, the drums' bottoms at 0); `TowPlatform` folds and inflates them about hinges and pivots of its own:

```sh
python3 tools/gltf/process_prop.py --input assets_src/structures/tow_platform/tow_platform_meshy.glb \
    --output /tmp/tow_platform.glb
python3 tools/gltf/split_raft.py --input /tmp/tow_platform.glb \
    --output game/assets/structures/tow_platform/tow_platform.glb [--preview out.png]
```

The folding bridge is cut into the three spans it folds in (through the hydraulic joints under its deck, every triangle across a cut clipped exactly at it) and scaled to metres (72 m long, 10.9 m wide, the deck's top at 0) by `tools/gltf/fold_bridge.py`, which also fits its textures like `process_prop.py`:

```sh
python3 tools/gltf/fold_bridge.py --input assets_src/structures/folding_bridge/folding_bridge_meshy.glb \
    --output game/assets/structures/folding_bridge/folding_bridge.glb
```
The stronghold itself is generated by `tools/blender/build_stronghold.py`. Rebuild it with Blender 5.2, or the `bpy` 5.2 pip package (Python 3.13):

```sh
python tools/blender/build_stronghold.py -- --output game/assets/stronghold/stronghold.glb
```

The game strips the placeholder weapons (`PH_*`) from its mounts and puts the turret models there, and hooks gates, stations and the Keep onto its markers (`EXIT_C_*`, `MOUNT_*`, `Reactor`).

## Texture credits

The ground's, the stronghold's and the water's photoscanned materials are from [Poly Haven](https://polyhaven.com), released under CC0 (public domain): `forest_leaves_02`, `brown_mud_leaves_01`, `leafy_grass`, `sparse_grass`, `forest_ground_04`, `brown_mud_03`, `rock_face_03`, `ganges_river_pebbles`, `aerial_rocks_02`, `concrete_layers_02`, `dirty_concrete`, `metal_plate_02`, `rusty_metal_02`. The water's wave normals, caustics and foam are generated (`tools/textures/gen_water.py`).

## Asset layout

- `assets_src/` — raw exports from Meshy (untouched originals)
- `game/assets/` — processed, game-ready versions (Blender cleanup, rigging, texture resizing)
- `game/scripts/` — `match/` (level, rules; `match/jungle/` the Jungle Keep), `attacker/` (RTS commander, CPU attacker), `defense/` (stations, defender controller), `units/`, `vehicles/` (the machines' rigs), `combat/`, `ui/`
- `tools/blender/` — asset processing scripts
- `tools/gltf/` — asset scripts that need no Blender (numpy on the glTF): static props, the Sniper's rifle, the Infiltrator's, the Lioness's, the Sniper's and the Mule Artillery's rigs, the Wolf Medic's Dig clip, the machines' moving parts (`rig_vehicles.py`)
