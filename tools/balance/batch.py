#!/usr/bin/env python3
"""Plays a batch of balance matches (every attacker policy against every defender policy, over the seeds) and prints the
table: who wins how often, and how the matches went.

    python3 tools/balance/batch.py --name base --atk even,rush,siege --def default,turtle --seeds 1-3
    python3 tools/balance/batch.py --name gate20k --set LevelBuilder.GATE_HP=20000 --atk even --def default --seeds 1-6
    python3 tools/balance/batch.py --name mine --variant mine --keep --atk /tmp/a.json --def /tmp/d.json --seeds 1-4

Results go to $BALANCE_ROOT/results/<name>/ (one .json and .log a match, summary.json and summary.txt); a match already
there is not played again unless --redo. `python3 tools/balance/summarize.py <dir>` prints the table again, and the
matches' course phase by phase.
"""
import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_match  # noqa: E402
import summarize  # noqa: E402
import variant as variant_mod  # noqa: E402


def seeds_of(spec: str) -> list:
    out = []
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True)
    ap.add_argument("--atk", default="even")
    ap.add_argument("--def", dest="deff", default="default")
    ap.add_argument("--seeds", default="1-3")
    ap.add_argument("--variant", default="")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--base", default="")
    ap.add_argument("--apply", action="append", help="unified diffs of script changes to apply to the variant (variant.py --diff)")
    ap.add_argument("--patch", action="append")
    ap.add_argument("--set", action="append")
    ap.add_argument("--match-time", type=float, default=0.0)
    ap.add_argument("--fps", type=int, default=10)
    ap.add_argument("--ticks", type=int, default=30)
    ap.add_argument("--fine", action="store_true")
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--timeout", type=float, default=3600.0)
    a = ap.parse_args()
    patch = {}
    for p in a.patch or []:
        patch.update(json.loads(Path(p).read_text()))
    patch.update(variant_mod.parse_sets(a.set))
    try:
        project = run_match.resolve_project(a.variant, a.keep, patch, a.base, a.apply or [])
    except KeyError as e:
        sys.exit(f"patch error: {e.args[0]}")
    if a.fine:
        a.fps, a.ticks = 30, 60
    out = run_match.ROOT / "results" / a.name
    out.mkdir(parents=True, exist_ok=True)
    (out / "batch.json").write_text(json.dumps({"patch": patch, "variant": a.variant, "base": a.base, "project": str(project),
                                                "atk": a.atk, "def": a.deff, "seeds": a.seeds, "match_time": a.match_time,
                                                "fps": a.fps, "ticks": a.ticks}, indent=1))
    jobs = []
    for atk in a.atk.split(","):
        for deff in a.deff.split(","):
            for seed in seeds_of(a.seeds):
                label = f"{Path(atk).stem}_vs_{Path(deff).stem}_s{seed}"
                if not a.redo and (out / f"{label}.json").exists():
                    continue
                jobs.append((atk, deff, seed, label))
    print(f"batch {a.name}: {len(jobs)} matches to play on {project} -> {out}", flush=True)
    with ThreadPoolExecutor(max_workers=max(run_match.SLOTS, 1)) as pool:
        futs = {pool.submit(run_match.run, project, atk, deff, seed, out, label, a.match_time, a.fps, a.ticks, 10.0, a.timeout): label
                for atk, deff, seed, label in jobs}
        for f in as_completed(futs):
            print(run_match.one_line(f.result()), flush=True)
    text = summarize.report(out)
    (out / "summary.txt").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
