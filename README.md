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

**The map.** The stronghold is a mountain with a bunker dug into each of its four faces (`game/assets/stronghold/stronghold.glb`). The Keep is the reactor in the core hall under the peak. Attackers come from the south, east and west. Each of those faces has a blast-door gate on its middle ground tunnel; every other tunnel is welded shut. Once a gate is down, only Chimps and Breaching Rams can get inside; everyone else fights from outside. Inside, they can also climb the stair shafts to the gun decks and the ladders to the roofs. Forest groves stand off to the sides of the attack lanes. The defenders hold the gun decks and roofs: a machine gun over each gate, riflemen along the decks and the mortar on the south roof. The guns can't fire into the doorway right below them; the mortar covers it.

**Defender (first person)**
- `1`–`9`: take over a post (machine guns, mortar, riflemen) · `G`: the Gunner Squad · `Tab`: jump to the post with the most enemies nearby · `B`: buy an AA Squad · `F1`–`F6`: take command of a bought squad
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
- Posts you aren't controlling keep fighting on their own; dead posts come back after a short delay

**Attacker (RTS)**
- `LMB` click/drag to select, `Shift` to add · `RMB` attack-move, or attack a gate/defender you click on · `Ctrl+RMB` move without stopping
- Spawn: `Z` Bear Rifleman · `X` Kangaroo Commando (fast) · `C` Wolf Medic (heals) · `N` Mule Artillery (long-range shells)
- `V` Sky Talon (the hawk): flies over the mountain, and flies like a hawk.
  - It glides most of the time and beats its wings only now and then, a few strokes every few seconds (gliding it sinks a little and the strokes lift it back up), and all the way up on take-off or climbing over the mountain. It banks into its turns.
  - It never hovers: wherever it has nowhere left to go, it circles. Sent somewhere, it circles the spot counterclockwise, the centre off its left wing, like a gunship flying a pylon turn. Sent at a target (or meeting one on an attack-move), it comes down and circles that instead, firing from the ring.
  - Rings stay level and clear of the ground: next to the mountain a ring moves out in front of the face (and tightens) until it is, while staying in range of its target. Each talon flies a ring of its own (up to 8 m wider) at a height of its own (spread over 10 m), so a flock sent to one spot stacks up instead of flying through itself.
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
- `M` Breaching Ram (big horn sheep): breaks gates, and with the Chimp the only unit that can get inside the stronghold.
  - Basic attack: shotgun. Each blast throws 7 pellets into a small cone in front of it (range 7 m).
  - `Space` ram: a surge of speed (2.2×) for 6 s. Cooldown is 60 s. Enemy soldiers it runs over lose health and are tossed out of its way.
  - Gate charge: `RMB` a ground gate while ramming, and the rams line up across its doorway and slam into it once each for a heavy hit (350). Only 3 fit in front of a doorway at a time: the nearest ones that can still get there before their ram runs out take the places (rams already charging it keep theirs). The rest call their ram off and go at the gate with their shotguns.
  - Infiltration: once a gate is down, `RMB` next to it sends selected rams in. Like the Chimps, inside you lose control of them. They make for the Keep on their own and fight every defender they run into on the way (within about 18 m, up the stairs to the gun decks too), ramming soldiers whenever the ram is ready and finishing them with the shotgun.
- `J` Night Ops Chimp: fast melee fighter, and with the Breaching Ram the only unit that can get inside the stronghold.
  - Basic attack: melee, it strikes whatever is within arm's reach.
  - Passive: moves 60% faster inside forests.
  - Infiltration: once a gate is down, `RMB` next to it sends selected Chimps in. Inside, you lose control of them. They hunt the defenders anywhere in the stronghold, climbing to the gun decks and up the ladders to the roofs. When no defender is left standing, they wreck the machines: the gate machine guns and the mortar. Respawned defenders draw them back.
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

`game/scenes/dev/talon_showcase.tscn` flies the Sky Talon on the real map: one takes off from the south field, beating its wings all the way up, then cruises west across it (long glides, a few wing beats now and then) and circles the spot it was sent to. Sent at a rifleman on the south gun deck, it circles him, firing down from a ring out in front of the face; he fires back (the talon gets the hit points to outlast him). Last, five talons sent to one spot each fly a ring of their own. The garrison's other posts hold fire.

```sh
godot --path game --headless --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --test  # prints and checks: TALON SHOWCASE PASS / FAIL
godot --path game --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 res://scenes/dev/talon_showcase.tscn -- --snap=12,33 --snap-out=/tmp/talon  # just those frames
godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie talon.avi --fixed-fps 30 res://scenes/dev/talon_showcase.tscn
```

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
