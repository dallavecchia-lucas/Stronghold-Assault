#!/usr/bin/env python3
"""Turns a filmed match's frames into clips: every <dir>/<moment>/ folder of JPEG frames (film_crew.gd) becomes
<dir>/<moment>.mp4 (H.264, yuv420p, 30 fps, 1280x720), and <dir>/index.json lists them (moment, match time, place, what
is in shot, rigged or not).

    python3 tools/balance/film_cut.py /tmp/stronghold-balance/clips/<run> [--crf 22] [--keep-frames]
"""
import argparse, json, shutil, subprocess, sys
from pathlib import Path


def cut(d: Path, crf: int = 22, keep: bool = False, extra: dict = None) -> list:
    index = []
    for m in sorted(p for p in d.iterdir() if p.is_dir()):
        meta_f = m / "meta.json"
        frames = sorted(m.glob("*.jpg"))
        if not meta_f.exists() or len(frames) < 15:
            print(f"skip {m.name}: {'no meta' if not meta_f.exists() else str(len(frames)) + ' frames'}")
            continue
        meta = json.loads(meta_f.read_text())
        out = d / f"{m.name}.mp4"
        fps = str(meta.get("fps", 30))
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", fps, "-i", str(m / "%05d.jpg"),
               "-vf", "scale=1280:720:flags=lanczos", "-c:v", "libx264", "-preset", "slow", "-crf", str(crf),
               "-pix_fmt", "yuv420p", "-r", "30", "-movflags", "+faststart", str(out)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"ffmpeg failed on {m.name}: {r.stderr[-300:]}")
            continue
        meta["file"] = str(out)
        meta["mb"] = round(out.stat().st_size / 1e6, 2)
        meta["seconds"] = round(len(frames) / float(meta.get("fps", 30)), 2)
        meta.update(extra or {})
        index.append(meta)
        if not keep:
            shutil.rmtree(m)
        print(f"{out.name}: {meta['seconds']} s, {meta['mb']} MB  {meta['desc']}{'  [RIGGED]' if meta.get('rigged') else ''}")
    old = d / "index.json"
    if old.exists():  # clips cut earlier (frames already gone) stay listed
        have = {i["name"] for i in index}
        index = [i for i in json.loads(old.read_text()) if i["name"] not in have and Path(i["file"]).exists()] + index
    index.sort(key=lambda i: i["t"])
    old.write_text(json.dumps(index, indent=1))
    return index


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir", type=Path)
    ap.add_argument("--crf", type=int, default=22)
    ap.add_argument("--keep-frames", action="store_true")
    a = ap.parse_args()
    if not a.dir.is_dir():
        sys.exit(f"no such dir {a.dir}")
    idx = cut(a.dir, a.crf, a.keep_frames)
    print(f"{len(idx)} clips -> {a.dir / 'index.json'}")


if __name__ == "__main__":
    main()
