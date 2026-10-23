#!/usr/bin/env python3
"""Cuts a showcase recording (Godot Movie Maker .avi) into the final .mp4, going by what the
showcase printed while it was recorded:

    VIDEO START frame N      the video's first frame (the ones before it are the level loading)
    VIDEO END frame N        its last frame
    FAST k frames A-B        frames A..B play k times faster (every k-th one is kept)

    godot --path game --rendering-driver opengl3 --resolution 1280x720 --write-movie aa.avi \
        --fixed-fps 30 res://scenes/dev/aa_squad_showcase.tscn -- --video > aa.log
    python3 tools/video/cut_showcase.py aa.avi aa.log media/aa_squad_showcase.mp4

Needs ffmpeg on the PATH. The video comes out H.264, 30 fps, without sound.
"""

import re
import subprocess
import sys

FPS = 30


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    avi, log, out = sys.argv[1:]
    text = open(log, encoding="utf-8", errors="replace").read()
    start = int(re.search(r"VIDEO START frame (\d+)", text).group(1))
    end = int(re.search(r"VIDEO END frame (\d+)", text).group(1))
    fast = [(int(k), int(a), int(b)) for k, a, b in re.findall(r"FAST (\d+) frames (\d+)-(\d+)", text)]
    # Keep the frames from the start to the end, and every k-th one of each fast stretch.
    keep = f"between(n\\,{start}\\,{end})"
    for k, a, b in fast:
        keep += f"*if(between(n\\,{a}\\,{b})\\,not(mod(n-{a}\\,{k}))\\,1)"
    kept = end - start + 1 - sum((b - a + 1) - len(range(a, b + 1, k)) for k, a, b in fast)
    print(f"frames {start}-{end}, {len(fast)} fast stretch(es): {kept} frames, {kept / FPS:.1f} s")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-stats", "-i", avi,
            "-vf", f"select='{keep}',setpts=N/{FPS}/TB", "-r", str(FPS), "-an",
            "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            out], check=True)


if __name__ == "__main__":
    main()
