#!/usr/bin/env python3
"""Films a CPU-vs-CPU match (the film crew, game/scripts/sim/film_crew.gd): plays the match
windowed under Xvfb on the software renderer with the drawing off, films its best moments, and cuts them into .mp4s
with an index (film_cut.py). Holds one of the machine's match slots (tools/balance/run_match.py Slot) the whole time.

    python3 tools/balance/film_match.py --run final_s1 --atk siege_mass --def default --seed 1 --match-time 1500
    # with numbers changed (a variant of the game is made for them), rigged runs tagged:
    python3 tools/balance/film_match.py --run rig1 --tag rigged --set LevelBuilder.GATE_HP=3000 ...
    python3 tools/balance/film_match.py --run p1 --patch numbers.json ...

Clips go to /tmp/stronghold-balance/clips/<run>/ (index.json, the .mp4s, the match's telemetry and log).
"""
import argparse, json, os, subprocess, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import variant as variant_mod  # noqa: E402
from run_match import Slot  # noqa: E402
import film_cut  # noqa: E402

ROOT = Path(os.environ.get("BALANCE_ROOT", "/tmp/stronghold-balance"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", required=True, help="clips go to clips/<run>/")
    ap.add_argument("--atk", default="mass")
    ap.add_argument("--def", dest="deff", default="default")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--match-time", type=float, default=0.0)
    ap.add_argument("--variant", default="", help="film on this variant as it stands (it must have the film crew in)")
    ap.add_argument("--base", default="", help="build on this variant (its edits kept) instead of the game")
    ap.add_argument("--apply", action="append", default=[], help="more diffs to apply")
    ap.add_argument("--set", action="append", help="Class.CONST=value patches")
    ap.add_argument("--patch", action="append", default=[], help="a patch JSON file of numbers (variant.py)")
    ap.add_argument("--clips", type=int, default=10)
    ap.add_argument("--gap", type=float, default=45.0)
    ap.add_argument("--len", type=float, default=8.0)
    ap.add_argument("--start", type=float, default=25.0)
    ap.add_argument("--min-prio", type=int, default=15, help="no clip of a moment below this priority (film_crew.gd PRIO)")
    ap.add_argument("--per-kind", type=int, default=0, help="at most this many clips of one kind (0: no limit)")
    ap.add_argument("--tag", default="", help="'rigged' marks the clips as rigged in the index")
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--driver", default="vulkan", help="vulkan (lavapipe, Forward+) or opengl3")
    ap.add_argument("--lighting", default="standard", help="standard or raytraced")
    ap.add_argument("--crf", type=int, default=26)
    ap.add_argument("--fps", type=float, default=30.0, help="frames a second of the clips (fewer: cheaper to render)")
    ap.add_argument("--keep-frames", action="store_true")
    ap.add_argument("--extra", action="append", default=[], help="more game arguments (e.g. --film-bench)")
    a = ap.parse_args()

    out = ROOT / "clips" / a.run
    out.mkdir(parents=True, exist_ok=True)
    if a.variant:
        project = variant_mod.DEFAULT_ROOT / a.variant
    else:
        patch = {}
        for f in a.patch:
            patch.update(json.loads(Path(f).read_text()))
        patch.update(variant_mod.parse_sets(a.set))
        project = variant_mod.build(f"film_{a.run}", patch, base=a.base, diffs=a.apply) if (patch or a.base or a.apply) \
                else variant_mod.GAME
    w, h = a.res.split("x")
    sim_json = out / "match.json"
    cmd = ["xvfb-run", "-a", "-s", f"-screen 0 {w}x{h}x24", os.environ.get("GODOT", "godot"), "--path", str(project),
           "--resolution", a.res, "--fixed-fps", "10"]
    if a.driver == "opengl3":
        cmd += ["--rendering-driver", "opengl3"]
    cmd += ["--", f"--sim={sim_json}", f"--atk={a.atk}", f"--def={a.deff}", f"--seed={a.seed}", "--sim-ticks=30",
            f"--sim-label=film_{a.run}", f"--lighting={a.lighting}", "--no-msaa", f"--film={out}",
            f"--film-clips={a.clips}", f"--film-gap={a.gap}", f"--film-len={a.len}", f"--film-start={a.start}",
            f"--film-min-prio={a.min_prio}", f"--film-per-kind={a.per_kind}",
            f"--film-fps={a.fps}"]
    if a.match_time > 0:
        cmd.append(f"--match-time={a.match_time}")
    if a.tag:
        cmd.append(f"--film-tag={a.tag}")
    cmd += a.extra
    print("project:", project)
    print("command:", " ".join(cmd))
    t0 = time.time()
    with Slot():
        t1 = time.time()
        with open(out / "match.log", "w") as lf:
            subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, timeout=4 * 3600)
        t2 = time.time()
        idx = film_cut.cut(out, a.crf, a.keep_frames, {"atk": a.atk, "def": a.deff, "variant": str(project),
                                                         "sets": a.set or []})
    log = (out / "match.log").read_text(errors="replace")
    print(f"slot wait {t1 - t0:.0f} s, match+filming {t2 - t1:.0f} s, cutting {time.time() - t2:.0f} s; "
          f"{len(idx)} clips; script errors in log: {log.count('SCRIPT ERROR')}")
    print([l for l in log.splitlines() if l.startswith("SIM over")][-1:] or "match did not finish (see match.log)")


if __name__ == "__main__":
    main()
