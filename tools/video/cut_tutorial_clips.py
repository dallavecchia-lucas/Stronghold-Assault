#!/usr/bin/env python3
"""Cuts the Field Manual's video clips out of the showcase videos in media/.

The clips are listed in tools/video/tutorial_clips.json ({id: {source, start, end}}); each is cut from its source
.mp4 (seconds, start to end), scaled down and written as Ogg Theora (the format Godot plays) to
game/assets/tutorial/<id>.ogv, without sound. The Field Manual (game/scripts/ui/field_manual_data.gd) names
its clips by these ids.

    git lfs pull --include="media/*"        # the showcase videos are in LFS
    python3 tools/video/cut_tutorial_clips.py [id ...]   # all of them, or just these

Needs ffmpeg (with libtheora) on the PATH.
"""

import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(ROOT, "tools", "video", "tutorial_clips.json")
OUT_DIR = os.path.join(ROOT, "game", "assets", "tutorial")
FPS = 30


def cut(cid: str, clip: dict, width: int, quality: int) -> str:
    src = os.path.join(ROOT, clip["source"])
    out = os.path.join(OUT_DIR, cid + ".ogv")
    start, end = float(clip["start"]), float(clip["end"])
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.3f}", "-i", src, "-t", f"{end - start:.3f}",
            "-an", "-vf", f"scale={width}:-2,fps={FPS}", "-c:v", "libtheora", "-q:v", str(quality), out], check=True)
    return f"{cid}: {end - start:.1f} s, {os.path.getsize(out) / 1e6:.2f} MB"


def main() -> None:
    data = json.load(open(MANIFEST, encoding="utf-8"))
    clips = data["clips"]
    wanted = sys.argv[1:] or list(clips)
    unknown = [c for c in wanted if c not in clips]
    if unknown:
        sys.exit(f"unknown clip(s): {', '.join(unknown)}")
    for cid in wanted:
        src = os.path.join(ROOT, clips[cid]["source"])
        if os.path.getsize(src) < 1024:
            sys.exit(f"{clips[cid]['source']} is an LFS pointer: run git lfs pull --include=\"media/*\" first")
    os.makedirs(OUT_DIR, exist_ok=True)
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        for line in pool.map(lambda c: cut(c, clips[c], data["width"], data["quality"]), wanted):
            print(line)


if __name__ == "__main__":
    main()
