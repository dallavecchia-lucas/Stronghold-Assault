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

## Asset layout

- `assets_src/` — raw exports from Meshy (untouched originals)
- `game/assets/` — processed, game-ready versions (Blender cleanup, rigging, texture resizing)
