"""Fetches the photoscanned materials (CC0, Poly Haven: https://polyhaven.com) and packs them for the game.

    python3 tools/textures/fetch_and_pack.py [--raw DIR]

Downloads each set's colour, OpenGL normal, AO/roughness/metal and displacement maps (2K, 1K for the small
metal ones) into DIR (default /tmp/polyhaven_raw), then writes game/assets/textures:
- terrain/terrain_{albedo,normal,orh}.jpg: the ground's eight layers stacked into strips (2048 x 16384), imported
  as Texture2DArrays (their .import files say so): ORH is ambient occlusion, roughness and height (each layer's
  displacement stretched to 0-1, for height blending). The slice order is GroundMaterial's.
- stronghold/<set>_{albedo,normal,orh|arm}.jpg: the stronghold's rock macro, concrete and metal sets.
Needs numpy and Pillow; the downloads go through curl (the API refuses some user agents).
"""
import argparse
import json
import os
import subprocess

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'assets', 'textures')
# GroundMaterial's layers, in order: LITTER, MOSSY, GRASS, GRASS_DARK, DIRT, MUD, ROCK, PEBBLES.
TERRAIN = ['forest_leaves_02', 'brown_mud_leaves_01', 'leafy_grass', 'sparse_grass',
           'forest_ground_04', 'brown_mud_03', 'rock_face_03', 'ganges_river_pebbles']
# StrongholdLook's: [set, resolution, pack]
STRONGHOLD = [('aerial_rocks_02', '2k', 'orh'), ('concrete_layers_02', '2k', 'orh'), ('dirty_concrete', '2k', 'orh'),
              ('metal_plate_02', '1k', 'arm'), ('rusty_metal_02', '1k', 'arm')]
MAPS = {'Diffuse': 'albedo', 'nor_gl': 'normal', 'arm': 'arm', 'Displacement': 'height'}


def curl(url, out=None):
    cmd = ['curl', '-sSfL', '--max-time', '300', url] + (['-o', out] if out else [])
    return subprocess.run(cmd, check=True, capture_output=True).stdout


def fetch(raw, sid, res):
    files = json.loads(curl(f'https://api.polyhaven.com/files/{sid}'))
    os.makedirs(f'{raw}/{sid}', exist_ok=True)
    for key, short in MAPS.items():
        path = f'{raw}/{sid}/{short}.jpg'
        if not os.path.exists(path):
            curl(files[key][res]['jpg']['url'], path)


def load(path, size, mode='RGB'):
    im = Image.open(path).convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im)


def norm01(a):
    a = a.astype(np.float32)
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-3), 0, 1)


def orh(raw, sid, size):
    arm = load(f'{raw}/{sid}/arm.jpg', size).astype(np.float32) / 255.0
    return np.dstack([arm[..., 0], arm[..., 1], norm01(load(f'{raw}/{sid}/height.jpg', size, 'L'))])


def save(arr, path, q):
    a = arr if arr.dtype == np.uint8 else np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a).save(path, quality=q, subsampling=0 if q >= 90 else 2, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--raw', default='/tmp/polyhaven_raw')
    raw = ap.parse_args().raw
    for sid in TERRAIN:
        fetch(raw, sid, '2k')
    for sid, res, _ in STRONGHOLD:
        fetch(raw, sid, res)
    os.makedirs(f'{ROOT}/terrain', exist_ok=True)
    os.makedirs(f'{ROOT}/stronghold', exist_ok=True)
    s = 2048
    save(np.concatenate([load(f'{raw}/{t}/albedo.jpg', s) for t in TERRAIN], 0), f'{ROOT}/terrain/terrain_albedo.jpg', 90)
    save(np.concatenate([load(f'{raw}/{t}/normal.jpg', s) for t in TERRAIN], 0), f'{ROOT}/terrain/terrain_normal.jpg', 90)
    save(np.concatenate([orh(raw, t, s) for t in TERRAIN], 0), f'{ROOT}/terrain/terrain_orh.jpg', 92)
    for sid, res, pack in STRONGHOLD:
        size = 2048 if res == '2k' else 1024
        save(load(f'{raw}/{sid}/albedo.jpg', size), f'{ROOT}/stronghold/{sid}_albedo.jpg', 90)
        save(load(f'{raw}/{sid}/normal.jpg', size), f'{ROOT}/stronghold/{sid}_normal.jpg', 95)
        if pack == 'orh':
            save(orh(raw, sid, size), f'{ROOT}/stronghold/{sid}_orh.jpg', 92)
        else:
            save(load(f'{raw}/{sid}/arm.jpg', size), f'{ROOT}/stronghold/{sid}_arm.jpg', 92)


main()
