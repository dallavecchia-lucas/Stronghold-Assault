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

**The map.** The stronghold is a mountain with a bunker dug into each of its four faces (`game/assets/stronghold/stronghold.glb`). The Keep is the reactor in the core hall under the peak. Attackers come from the south, east and west. Each of those faces has a blast-door gate on its middle ground tunnel; every other tunnel is welded shut. Once a gate is down, units that fit the tunnels (2.8 m high, 2 m wide passages inside) can walk in to the reactor. Big units, flyers and artillery can't reach it, so they fight outside. The defenders hold the gun decks and roofs: a machine gun over each gate, riflemen along the decks and the mortar on the south roof. The guns can't fire into the doorway right below them; the mortar covers it.

**Defender (first person)**
- `1`–`9`: take over a post (machine guns, mortar, riflemen) · `Tab`: jump to the post with the most enemies nearby
- Rifleman: `WASD` move, `Shift` sprint, `Space` jump, `LMB` fire, `RMB` aim, `R` reload
- Machine gun: mouse aim, `LMB` fire, `RMB` zoom; it overheats if you hold the trigger too long
- Mortar: `WASD` move the spotter view, `Q`/`E` rotate, wheel zoom, `LMB` fire on the ring
- Posts you aren't controlling keep fighting on their own; dead posts come back after a short delay

**Attacker (RTS)**
- `LMB` click/drag to select, `Shift` to add · `RMB` attack-move, or attack a gate/defender you click on · `Ctrl+RMB` move without stopping
- Spawn: `Z` Bear Rifleman · `X` Kangaroo Commando (fast) · `C` Wolf Medic (heals) · `V` Sky Talon (flies over the mountain) · `B` War Elephant (heavy) · `N` Mule Artillery (long-range shells) · `M` Breaching Ram (gates only)
- `I` Combat Rhino: tanky and slow, with no basic attack.
  - Passive anti-air: locks onto one enemy flyer in its dashed ring and stays on it until it dies or leaves. One rhino is weak; it takes about five to bring a flyer down fast.
  - `F` cluster bombing: aim, then `LMB` to fire (`RMB` or `F` cancels). Each rhino shells a spot inside its 40 m zone for 8 s. Cooldown is 45 s. With several rhinos selected, the preview shows where each one's bombs will land. Rhinos that were moved together keep their formation's shape. Scattered rhinos aim as close to the cursor as their zones allow and spread around it instead of piling onto one spot.
  - `T` scout formation: with rhinos and other units selected, the rhinos ring the outside of the group so their anti-air covers it. Orders to the whole group keep the ring. Ordering a rhino on its own takes it out of the ring, and `T` again turns it off.
- `K` Hippo Heavy Gunner: heavy, slow, sprays suppressive fire from mounted machine guns.
  - The guns are inaccurate: rounds land around the target and can hit whatever stands next to it. They fire for 8 s in total (resting cools them at the same rate), then overheat and go silent for 2 s.
  - `R` smoke screen: aim, then `LMB` to fire (`RMB` or `R` cancels). The cone shows where the curtain will stand (the green band at its tip). The hippo fires three grenades at once. Each one bursts high up, then drops and bursts twice more on the way down, leaving a tall pillar. Together the pillars make a curtain that blocks line of sight for both sides for 30 s. Cooldown is 90 s. With several hippos selected, the one closest to the cursor fires.
- Models in, roles still to be designed (placeholder stats): `G` War Ram · `H` Savanna Signal Scout · `J` Night Ops Chimp · `L` Bison Field Gun · `Y` Armored Lioness · `U` Serpent Sniper
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
