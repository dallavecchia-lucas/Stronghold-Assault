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

**The map.** The stronghold is a mountain with a bunker dug into each of its four faces (`game/assets/stronghold/stronghold.glb`). The Keep is the reactor in the core hall under the peak. Attackers come from the south, east and west. Each of those faces has a blast-door gate on its middle ground tunnel; every other tunnel is welded shut. Once a gate is down, only Chimps, Breaching Rams and Kangaroo Commandos can get inside; everyone else fights from outside. Inside, they can also climb the stair shafts to the gun decks and the ladders to the roofs. Forest groves stand off to the sides of the attack lanes; they burn (the Flame Squads), and a burnt forest never grows back. The defenders hold the gun decks and roofs: a machine gun over each gate, riflemen along the decks, the mortar on the south roof and two AA turrets on every roof. The guns can't fire into the doorway right below them; the mortar covers it.

**Defender (first person)**
- `1`–`9`: take over a post (machine guns, mortar, riflemen) · `G`: the Gunner Squad · `Tab`: jump to the post with the most enemies nearby · `B`: buy an AA Squad · `N`: buy a Flame Squad · `F1`–`F6`: take command of a bought squad
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
  - `F` mines: aimed like the hippo's smoke screen, a cone toward the crosshair with a green band at its tip; `LMB` and every trooper lobs two mines that land sparsely over the band (`RMB` or `F` cancels). They arm after a moment, blink, and go off under enemy ground units (aircraft pass over), 160 within 4 m. Ready again after 15 s. A squad keeps 40 down at most (the oldest are taken up).
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
- Posts you aren't controlling keep fighting on their own; dead posts come back after a short delay
- Flash grenades (the Kangaroo Commandos'): a post or trooper within 10 m of the bang that has it in sight is blinded for 2 s, and left to itself it can't fight (the guns, the mortar and the riflemen hold their fire, a squad's troopers too, and an AA Squad drops its lock). If it catches the post you are on, your screen goes full white for 2 s, then clears.
- AA turrets: two on every roof, on their own (nobody takes them over). Each turns to the nearest enemy aircraft it can see within 45 m, locks on (1.2 s) and fires a homing missile at it every 3 s (18 damage), Sky Talons on their attack runs included. 150 HP: a bison's shell or a talon's bomb takes one out; it is rebuilt after 75 s.

**Attacker (RTS)**
- `LMB` click/drag to select, `Shift` to add · `RMB` attack-move, or attack a gate/defender you click on · `Ctrl+RMB` move without stopping
- Spawn: `Z` Bear Rifleman · `C` Wolf Medic (heals) · `N` Mule Artillery (long-range shells)
- `V` Sky Talon (the hawk): flies over the mountain, and flies like a hawk.
  - It glides most of the time and beats its wings only now and then, a few strokes every few seconds (gliding it sinks a little, less while it circles and soars, and the strokes lift it back up), and all the way up on take-off or climbing over the mountain. It banks into its turns.
  - It never hovers: wherever it has nowhere left to go, it circles. Sent somewhere (or at a target), it circles the spot counterclockwise, the centre off its left wing, like a gunship flying a pylon turn.
  - Rings stay level and clear of the ground: next to the mountain a ring moves out in front of the face (and tightens) until it is. Each talon flies a ring of its own (up to 8 m wider) at a height of its own (spread over 12 m), so a flock sent to one spot stacks up instead of flying through itself. Flying on, it looks ahead and climbs over the mountain in time.
  - No basic attack and no passive: it attacks with two skills, each reused after 90 s. `F` and `G` aim them when the selection has no ready rhinos (`F`) or bisons (`G`), whose skills come first.
  - `F` strafe run, like an A-10's: press `LMB` on the target and drag the way to fly, let go to fire (a click flies it from the talons to the target; `RMB` or `F` cancels). The line is 26 m long and has to lie inside the talon's circle (80 m round it). Several talons fly parallel lanes 7 m apart, side by side in the order they are in across the line; a lane that doesn't fit its talon's circle slides along itself until it does. Each talon flies round behind its lane, lines up, dives in along it firing ahead of itself, so its rounds walk down the lane (18 damage within 2.5 m each, about 40 of them), then pulls up and breaks away from the mountain.
  - `G` bomb strike: `LMB` a spot (`RMB` or `G` cancels). Each talon flies over its spot and drops one bomb (260 within 7 m, full damage against gates). Several talons' bombs land round the spot 10.5 m apart like the bisons' shells, up on the gun decks and roofs too. Against the mountain a talon slants in along the face instead of flying into it.
  - The runs fly round the stronghold, never into it: each plans its height along the whole pass from the ground under it, low over the target and always high enough to climb over the deck, the roof or the mountain ahead, and where the mountain blocks a straight run-in (a line along a face) it comes in at an angle from the open field and turns onto the line. Once on a run it flies it through, whatever its orders.
  - It is not invincible on a run: the AA turrets and the machine guns shoot at it. Take the turrets out first (bisons can, from beyond their reach).
- `B` War Elephant: the real anti-air unit. Heavy and slow, with no basic attack.
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
- `K` Hippo Heavy Gunner: heavy, slow, sprays suppressive fire from mounted machine guns.
  - The guns are inaccurate: rounds land around the target and can hit whatever stands next to it. They fire for 8 s in total (resting cools them at the same rate), then overheat and go silent for 2 s.
  - `R` smoke screen: aim, then `LMB` to fire (`RMB` or `R` cancels). The cone shows where the curtain will stand (the green band at its tip). The hippo fires three grenades at once. Each one bursts high up, then drops and bursts twice more on the way down, leaving a tall pillar. Together the pillars make a curtain that blocks line of sight for both sides for 30 s. Cooldown is 90 s. With several hippos selected, the one closest to the cursor fires.
- `M` Breaching Ram (big horn sheep): breaks gates, and with the Chimp and the Kangaroo Commando the only units that can get inside the stronghold.
  - Basic attack: shotgun. Each blast throws 7 pellets into a small cone in front of it (range 7 m).
  - `Space` ram: a surge of speed (2.2×) for 6 s. Cooldown is 60 s. Enemy soldiers it runs over lose health and are tossed out of its way.
  - Gate charge: `RMB` a ground gate while ramming, and the rams line up across its doorway and slam into it once each for a heavy hit (350). Only 3 fit in front of a doorway at a time: the nearest ones that can still get there before their ram runs out take the places (rams already charging it keep theirs). The rest call their ram off and go at the gate with their shotguns.
  - Infiltration: once a gate is down, `RMB` next to it sends selected rams in. Like the Chimps, inside you lose control of them. They make for the Keep on their own and fight every defender they run into on the way (within about 18 m, up the stairs to the gun decks too), ramming soldiers whenever the ram is ready and finishing them with the shotgun.
- `J` Night Ops Chimp: fast melee fighter, and with the Breaching Ram and the Kangaroo Commando the only units that can get inside the stronghold.
  - Basic attack: melee, it strikes whatever is within arm's reach.
  - Passive: moves 60% faster inside forests.
  - Infiltration: once a gate is down, `RMB` next to it sends selected Chimps in. Inside, you lose control of them. They hunt the defenders anywhere in the stronghold, climbing to the gun decks and up the ladders to the roofs. When no defender is left standing, they wreck the machines: the gate machine guns and the mortar. Respawned defenders draw them back.
- `X` Kangaroo Commando: fast, and with the Breaching Ram and the Chimp the only units that can get inside the stronghold.
  - It moves like a real kangaroo: it hops on both hind feet together, its tail swinging against the legs and its forepaws tucked in at the chest. Like a real one it hops at about the same rate whatever its speed, taking longer bounds instead.
  - Basic attack: the two SMGs mounted on either side of its chest fire short bursts (4 rounds), the guns taking turns. At a target above it (up on a gun deck) it rears its chest up to bring them onto it.
  - `R` flash grenade: aim, then `LMB` to throw (`RMB` or `R` cancels); with a selected hippo's smoke screen ready, `R` aims that first. Each kangaroo stops, stands up tall like a boxer (propped on its tail) and lobs a grenade up to 26 m. It goes off on landing in a white flash: every defender within 10 m that has it in sight is blinded for 2 s, and the defending player's screen goes full white if the post they are on is caught. Cooldown is 30 s. With several kangaroos selected, the grenades cluster round the cursor 15 m apart like the bisons' shells, instead of piling onto one spot, up on the gun decks and roofs too; the cursor on a defender up on a deck puts them at its feet. The preview shows each kangaroo's throw and where its flash will reach.
  - Passive, supplies: each kangaroo resupplies up to 3 units within 9 m whose skills are cooling down (other kangaroos included, itself not): their skills come back 15% sooner. A small ammo box floats over every unit it resupplies. It doesn't stack: a unit next to several kangaroos still gets 15%, and the kangaroos share out the units round them, each taking its nearest, so two kangaroos look after six.
  - Infiltration: once a gate is down, `RMB` next to it sends selected kangaroos in. Like the Chimps and Rams, inside you lose control of them: they hunt the defenders (up the stairs to the gun decks and the roofs too), shooting them with their SMGs and flashing them whenever a grenade is ready.
- Models in, roles still to be designed (placeholder stats): `H` Savanna Signal Scout · `Y` Armored Lioness · `U` Serpent Sniper
- `Tab` cycles spawn point · `Ctrl+1`–`5` save a group, `1`–`5` recall it
- Camera: `WASD`/arrows/screen edge to pan, `Q`/`E` or middle mouse to rotate, wheel to zoom
- `Esc` pauses (both sides)

Balance numbers live in `game/scripts/units/unit_types.gd` and the constants at the top of each defense script.

### Intro cinematic

The game opens with a ~3.5 minute intro (`game/scenes/intro.tscn`, built in `game/scripts/intro/intro.gd`); any key skips it, and the main menu has a **Watch Intro** button. Lore cards, shots and lighting cues are timed to the score in a table at the top of the script.

Render it to video with Godot's Movie Maker (use a real GPU for the full Forward+ look):

```sh
godot --path game --resolution 1920x1080 --write-movie intro.avi --fixed-fps 30 res://scenes/intro.tscn
ffmpeg -i intro.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 256k intro.mp4
```

Preview from a given moment with `-- --intro-start=80` (seconds).

The score (`game/assets/audio/intro_theme.ogg`) is original and synthesized by `tools/audio/compose_intro.py`; it is a temp track meant to be replaced by a real recording.

### Automated smoke test

Plays a scripted match at 4× speed with no window and prints a report (useful after changes):

```sh
godot --path game --headless -- --autotest=defender --duration=120
godot --path game --headless -- --autotest=attacker --duration=120
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

Static props (scenery, turrets) skip Blender: they go through [glTF-Transform](https://gltf-transform.dev) to put the pivot at the bottom center and shrink textures to 1024 px, and `game/scripts/match/props.gd` scales them to height at load time:

```sh
npx @gltf-transform/cli center assets_src/environment/trees/majestic_oak/majestic_oak_meshy.glb t1.glb --pivot below
npx @gltf-transform/cli resize t1.glb t2.glb --width 1024 --height 1024
npx @gltf-transform/cli jpeg t2.glb t3.glb --quality 85 --slots "{baseColorTexture,metallicRoughnessTexture,occlusionTexture}"
npx @gltf-transform/cli weld t3.glb game/assets/environment/majestic_oak/majestic_oak.glb
```

| Prop | Used for |
|---|---|
| birch_tree, silver_birch, white_birch_majesty, majestic_oak, solitary_evergreen | trees around the map |
| mossy_berry_rock, mossy_mountain_garden | rocks (with collision) |
| meadow_garden, meadow_tuft, wild_meadow_tangle, berry_woodland_miniature | ground cover (visual only) |
| sentinel_bastion | south gate machine gun; unmanned gun-deck mounts |
| orbital_sentry_gun | east/west gate machine guns; unmanned gun-deck mounts |
| arctic_sentinel_cannon | mortar on the south roof |
| sentinel_spire | roof (AA) mounts |

The stronghold itself is generated by `tools/blender/build_stronghold.py`. Rebuild it with Blender 5.2, or the `bpy` 5.2 pip package (Python 3.13):

```sh
python tools/blender/build_stronghold.py -- --output game/assets/stronghold/stronghold.glb
```

The game strips the placeholder weapons (`PH_*`) from its mounts and puts the turret models there, and hooks gates, stations and the Keep onto its markers (`EXIT_C_*`, `MOUNT_*`, `Reactor`).

## Asset layout

- `assets_src/` — raw exports from Meshy (untouched originals)
- `game/assets/` — processed, game-ready versions (Blender cleanup, rigging, texture resizing)
- `game/scripts/` — `match/` (level, rules), `attacker/` (RTS commander, CPU attacker), `defense/` (stations, defender controller), `units/`, `combat/`, `ui/`
- `tools/blender/` — asset processing scripts
