#!/usr/bin/env python3
"""Runs seeded bot matches in the real engine and summarises them (docs/balance/BALANCE_PLAN.md, Phase 0).

Each match is one headless Godot process:

    godot --path game --headless -- --autotest=<mode> --map=<map> --seed=<k> [--difficulty=..] [--match-time=..]

and prints one line `BOTMATCH {json}` when it ends (MatchTelemetry.finish). This script starts them `--jobs` at a
time, collects those lines, and prints the attacker's win rate with its 95% interval, the match length's median and
10th/90th percentiles, the share of matches ending between 20 and 30 minutes and when the first gate fell: the same
figures tools/balance/siege_model.py prints, so the model can be checked against the engine.

    python3 tools/balance/run_matches.py --mode bots --map classic --n 40
    python3 tools/balance/run_matches.py --mode rush --map jungle --n 5 --keep runs/      # keeps each match's telemetry JSON
    python3 tools/balance/run_matches.py --selftest                                       # checks the summary without the engine

Modes: bots (CPU attacker against the CPU garrison), rush, battery (AttackerProbe's scripted shortcuts).
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import subprocess
import sys


def run_one(args, seed: int) -> dict | None:
    cmd = [args.godot, "--path", args.project, "--headless", "--", f"--autotest={args.mode}", f"--map={args.map}",
           f"--seed={seed}", f"--difficulty={args.difficulty}", f"--timescale={args.timescale}"]
    if args.match_time > 0:
        cmd.append(f"--match-time={args.match_time}")
    if not args.drones:
        cmd.append("--drones=off")
    if args.keep:
        os.makedirs(args.keep, exist_ok=True)
        cmd.append("--telemetry=" + os.path.abspath(os.path.join(args.keep, f"{args.mode}_{args.map}_{seed}.json")))
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=args.timeout).stdout
    except (subprocess.TimeoutExpired, OSError) as e:
        print(f"seed {seed}: {e}", file=sys.stderr)
        return None
    return parse(out)


def parse(stdout: str) -> dict | None:
    """The match's summary: the JSON after `BOTMATCH ` on its own line."""
    for line in stdout.splitlines():
        if line.startswith("BOTMATCH "):
            return json.loads(line[len("BOTMATCH "):])
    return None


def quantile(xs: list[float], f: float) -> float:
    return xs[min(int(f * len(xs)), len(xs) - 1)] if xs else float("nan")


def summarise(rows: list[dict]) -> dict:
    n = len(rows)
    wins = [r for r in rows if r["winner"] == "attacker"]
    ends = sorted(r["length"] for r in rows)
    gates = sorted(r["gate_time"] for r in rows if r["gate_time"] >= 0)
    p = len(wins) / n
    return {
        "n": n, "p_att": p, "ci": 1.96 * math.sqrt(max(p * (1 - p), 1e-9) / n),
        "len_med": quantile(ends, 0.5) / 60, "len_p10": quantile(ends, 0.1) / 60, "len_p90": quantile(ends, 0.9) / 60,
        "in_window": sum(1 for e in ends if 1200 <= e <= 1800) / n,
        "gate_rate": len(gates) / n, "gate_med": quantile(gates, 0.5) / 60,
        "win_med": quantile(sorted(r["length"] for r in wins), 0.5) / 60,
        "spent": sum(r["supply_spent"] for r in rows) / n, "lost": sum(r["supply_lost"] for r in rows) / n,
    }


def show(label: str, s: dict) -> None:
    print(f"{label:<40} n={s['n']:<4} P(att)={s['p_att']*100:5.1f}% ±{s['ci']*100:4.1f} | length med {s['len_med']:5.1f} "
          f"[p10 {s['len_p10']:5.1f}, p90 {s['len_p90']:5.1f}] min | in 20-30: {s['in_window']*100:5.1f}% | "
          f"gate falls {s['gate_rate']*100:5.1f}% (med {s['gate_med']:5.1f}) | att-win med {s['win_med']:5.1f} | "
          f"supply spent {s['spent']:.0f}, lost {s['lost']:.0f}")


def selftest() -> None:
    out = 'AUTOTEST start side=bots seed=3\nBOTMATCH {"winner":"attacker","length":1300.0,"gate_time":400.0,"supply_spent":9000.0,"supply_lost":7000.0}\n'
    a = parse(out)
    assert a is not None and a["winner"] == "attacker"
    assert parse("nothing here") is None
    b = {"winner": "defender", "length": 1560.0, "gate_time": -1.0, "supply_spent": 12000.0, "supply_lost": 11000.0}
    s = summarise([a, b, b, a])
    assert abs(s["p_att"] - 0.5) < 1e-9 and s["in_window"] == 1.0 and s["gate_rate"] == 0.5
    assert abs(s["win_med"] - 1300 / 60) < 1e-9 and abs(s["gate_med"] - 400 / 60) < 1e-9
    show("selftest", s)
    print("run_matches selftest: ok")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default="godot", help="the Godot 4.5 binary")
    ap.add_argument("--project", default="game")
    ap.add_argument("--mode", default="bots", choices=["bots", "rush", "battery"])
    ap.add_argument("--map", default="classic", choices=["classic", "jungle"])
    ap.add_argument("--n", type=int, default=20, help="matches (seeds seed0 .. seed0+n-1)")
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=max((os.cpu_count() or 2) // 2, 1))
    ap.add_argument("--difficulty", type=int, default=1, choices=[0, 1, 2])
    ap.add_argument("--match-time", type=float, default=0.0, help="seconds the defenders hold (0: the map's own)")
    ap.add_argument("--timescale", type=float, default=4.0)
    ap.add_argument("--no-drones", dest="drones", action="store_false")
    ap.add_argument("--timeout", type=float, default=3600.0, help="seconds of wall clock a match may take")
    ap.add_argument("--keep", default="", help="directory to keep each match's telemetry JSON in")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    seeds = range(args.seed0, args.seed0 + args.n)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = [r for r in pool.map(lambda k: run_one(args, k), seeds) if r is not None]
    if not rows:
        sys.exit("no match reported a result: is --godot a Godot 4.5 binary, and was the project imported once "
                 "(godot --path game --headless --import)?")
    if len(rows) < args.n:
        print(f"{args.n - len(rows)} of {args.n} matches gave no result", file=sys.stderr)
    show(f"{args.map} · {args.mode} · difficulty {args.difficulty}", summarise(rows))


if __name__ == "__main__":
    main()
