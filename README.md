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

**Defender (first person)**
- `1`–`9`: take over a post (machine guns, mortar, riflemen) · `Tab`: jump to the post with the most enemies nearby
- Rifleman: `WASD` move, `Shift` sprint, `Space` jump, `LMB` fire, `RMB` aim, `R` reload
- Machine gun: mouse aim, `LMB` fire, `RMB` zoom; it overheats if you hold the trigger too long
- Mortar: `WASD` move the spotter view, `Q`/`E` rotate, wheel zoom, `LMB` fire on the ring
- Posts you aren't controlling keep fighting on their own; dead posts come back after a short delay

**Attacker (RTS)**
- `LMB` click/drag to select, `Shift` to add · `RMB` attack-move, or attack a gate/defender you click on · `Ctrl+RMB` move without stopping
- Spawn: `Z` Bear Rifleman · `X` Kangaroo Commando (fast) · `C` Wolf Medic (heals) · `V` Sky Talon (flies over walls) · `B` War Elephant (heavy) · `N` Mule Artillery (long-range shells) · `M` Breaching Ram (gates only)
- `Tab` cycles spawn point · `Ctrl+1`–`5` save a group, `1`–`5` recall it
- Camera: `WASD`/arrows/screen edge to pan, `Q`/`E` or middle mouse to rotate, wheel to zoom
- `Esc` pauses (both sides)

Balance numbers live in `game/scripts/units/unit_types.gd` and the constants at the top of each defense script.

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

## Asset layout

- `assets_src/` — raw exports from Meshy (untouched originals)
- `game/assets/` — processed, game-ready versions (Blender cleanup, rigging, texture resizing)
- `game/scripts/` — `match/` (level, rules), `attacker/` (RTS commander, CPU attacker), `defense/` (stations, defender controller), `units/`, `combat/`, `ui/`
- `tools/blender/` — asset processing scripts
