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
- `1`–`9`: take over a post (machine guns, mortar, riflemen) · `G`: the Gunner Squad · `Tab`: jump to the post with the most enemies nearby
- Rifleman: `WASD` move, `Shift` sprint, `Space` jump, `LMB` fire, `RMB` aim, `R` reload
- Machine gun: mouse aim, `LMB` fire, `RMB` zoom; it overheats if you hold the trigger too long
- Mortar: `WASD` move the spotter view, `Q`/`E` rotate, wheel zoom, `LMB` fire on the ring
- Gunner Squad (third person): five Heavy Gunners, minigunners in heavy armor, posted in the south spawn hall. You drive the trooper in the middle; the other four follow it and aim and fire wherever you aim and fire. `WASD` move (relative to the camera; they walk any way while facing the aim), mouse aim, `LMB` fire (the barrels spin up first, and the guns overheat after about 7 s), `RMB` aim closer, `Shift` hustle (faster, no firing).
  - Formation: in the open a wedge with you in the middle, two troopers out ahead to either side and two wider behind, every gun with a clear line forward. Each spot is checked against the navmesh: inside a tree, a rock or a wall it slides to the nearest free ground, and it has to be reachable from you without a detour. When the spots don't fit the wedge squeezes in from the sides; in passages too tight for that the squad files along the way you came, two abreast where there is room (`PAIRS`) or in single file (`FILE`), and spreads out again once there is room. In a column the troopers walk in your footsteps in a fixed order, each keeping its distance from the one ahead, and the last ones out of a tunnel file out the way you came before peeling off to their spots in the wedge. The troopers walk round trees and rocks on the navmesh, never through them, and don't fire when a squad mate is in the line of fire. The squad panel (bottom left) shows the formation and a small map of the troopers and their spots.
  - Blast doors open for the squad as it comes up to them, so it can sally out through the south tunnel (or any gate) and back. Attackers still can't get in until a gate is broken.
  - If the trooper you drive falls, the one nearest it takes the lead (your camera glides over to it and the panel says so) and the others fall in on it just as they followed the first; a column keeps walking on down the same trail.
  - Coming up to a narrow way (the spawn ramp, a tunnel mouth) the squad checks for room just ahead of you and gets into file, in order, before it rather than crowding into it.
  - Left alone it walks back to its post and holds it (hitting softer, like the other posts' crews). Lost troopers are replaced one at a time from the post every 20 s; if all five fall, the squad is back after 30 s.
- Posts you aren't controlling keep fighting on their own; dead posts come back after a short delay

**Attacker (RTS)**
- `LMB` click/drag to select, `Shift` to add · `RMB` attack-move, or attack a gate/defender you click on · `Ctrl+RMB` move without stopping
- Spawn: `Z` Bear Rifleman · `X` Kangaroo Commando (fast) · `C` Wolf Medic (heals) · `V` Sky Talon (flies over the mountain) · `N` Mule Artillery (long-range shells)
- `B` War Elephant: the real anti-air unit. Heavy and slow, with no basic attack.
  - Passive flak: the cannons on its flanks swing up at one enemy flyer in its dashed ring (26 m) and stay on it until it dies or leaves. They take turns firing shells that burst around it. One elephant hits about as hard as five rhinos.
  - `O` missiles: then `LMB` an enemy aircraft (`RMB` or `O` cancels). The pods lift and eight homing missiles leave one after another (range 60 m, reload 25 s). With several elephants selected, only as many fire as it takes to bring the target down, counting missiles already on their way to it, nearest first. The rest stay ready and you keep aiming, so you can click the next target. If all of them together can't kill it, they all fire. The cursor says how many will fire.
- `I` Combat Rhino: tanky and slow, with no basic attack.
  - Passive anti-air: locks onto one enemy flyer in its dashed ring and stays on it until it dies or leaves. One rhino is weak; it takes about five to bring a flyer down fast.
  - `F` cluster bombing: aim, then `LMB` to fire (`RMB` or `F` cancels). Each rhino shells a spot inside its 40 m zone for 8 s. Cooldown is 45 s. With several rhinos selected, the preview shows where each one's bombs will land. Rhinos that were moved together keep their formation's shape. Scattered rhinos aim as close to the cursor as their zones allow and spread around it instead of piling onto one spot.
  - `T` scout formation: with rhinos and other units selected, the rhinos ring the outside of the group so their anti-air covers it. Orders to the whole group keep the ring. Ordering a rhino on its own takes it out of the ring, and `T` again turns it off.
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
- Models in, roles still to be designed (placeholder stats): `H` Savanna Signal Scout · `L` Bison Field Gun · `Y` Armored Lioness · `U` Serpent Sniper
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
