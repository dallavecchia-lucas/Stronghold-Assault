#!/usr/bin/env python3
"""Plays one balance match, the CPU against the CPU (the game's `--sim=`: game/scripts/sim/sim_director.gd), and
prints how it went.

    python3 tools/balance/run_match.py --atk even --def default --seed 3
    python3 tools/balance/run_match.py --set UnitTypes.rifleman.hp=130 --set DefenderArmory.INCOME=5 --atk rush --def turtle
    python3 tools/balance/run_match.py --variant mine --keep --atk /path/atk.json --def clear --out /tmp/x

--atk / --def: a policy's name (AIAttacker.POLICIES, AIDefender.POLICIES) or a JSON file of the policy's keys (with
               {"base": name} to start from a named one).
--set / --patch: numbers to change for this match (tools/balance/variant.py); the match is then played on a variant of the
               game named after the patch. --variant NAME plays on that variant (--keep: as it stands, hand edits and all).
--fps / --ticks: how finely the match is played: frames and physics ticks a game second. The default (10 and 30) is
               about three times as fast as the game's own (30 and 60); use `--fine` for those.

Only BALANCE_SLOTS matches (3 by default) run on the machine at once, however many are started: the others wait their turn.
The result is written to <out>/<label>.json (the telemetry) and .log (the game's output).
"""
import argparse
import fcntl
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import variant as variant_mod  # noqa: E402

ROOT = Path(os.environ.get("BALANCE_ROOT", "/tmp/stronghold-balance"))
GODOT = os.environ.get("GODOT", "godot")
SLOTS = int(os.environ.get("BALANCE_SLOTS", "3"))


class Slot:
    """One of the machine's SLOTS places for a running match (a file lock), waited for."""

    def __enter__(self):
        d = ROOT / "slots"
        d.mkdir(parents=True, exist_ok=True)
        while True:
            for i in range(SLOTS):
                f = open(d / f"slot{i}.lock", "w")
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.f = f
                    return self
                except OSError:
                    f.close()
            time.sleep(1.0)

    def __exit__(self, *a):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def patch_name(patch: dict, base: str) -> str:
    return "p_" + hashlib.sha1(json.dumps([base, patch], sort_keys=True).encode()).hexdigest()[:12]


def resolve_project(variant: str, keep: bool, patch: dict, base: str = "") -> Path:
    """The Godot project a match is played on: the game itself, a named variant, or a variant made for `patch`."""
    if variant:
        if keep and (variant_mod.DEFAULT_ROOT / variant).exists():
            return variant_mod.DEFAULT_ROOT / variant
        return variant_mod.build(variant, patch, base=base)
    if patch or base:
        return variant_mod.build(patch_name(patch, base), patch, base=base)
    return variant_mod.GAME


def run(project: Path, atk: str, deff: str, seed: int, out: Path, label: str, match_time: float = 0.0, fps: int = 10,
        ticks: int = 30, sample: float = 10.0, timeout: float = 3600.0, extra: list = ()) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    result = out / f"{label}.json"
    log = out / f"{label}.log"
    if result.exists():
        result.unlink()
    cmd = [GODOT, "--path", str(project), "--headless", "--fixed-fps", str(fps), "--",
           f"--sim={result}", f"--atk={atk}", f"--def={deff}", f"--seed={seed}", f"--sim-ticks={ticks}",
           f"--sample={sample}", f"--sim-label={label}"]
    if match_time > 0:
        cmd.append(f"--match-time={match_time}")
    cmd += list(extra)
    t0 = time.time()
    with Slot():
        with open(log, "w") as lf:
            try:
                subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, timeout=timeout)
            except subprocess.TimeoutExpired:
                pass
    if not result.exists():
        tail = "".join(open(log, errors="replace").readlines()[-15:])
        return {"error": f"no result (see {log})", "log_tail": tail, "label": label, "wall": time.time() - t0}
    data = json.loads(result.read_text())
    data["_file"] = str(result)
    # Script errors in the log mean the match can't be trusted.
    text = open(log, errors="replace").read()
    data["_script_errors"] = text.count("SCRIPT ERROR")
    return data


def one_line(d: dict) -> str:
    if "error" in d:
        return f"{d.get('label', '?')}: ERROR {d['error']}"
    f = d["final"]
    first = d["totals"]["first"]
    gate = first.get("gate_down", "-")
    vent = first.get("vent_down", "-")
    return ("%-28s %-8s wins at %4.0fs (of %4.0f) | vents left %2d gates down %d (first %s) first vent %s | atk spent %5d lost %3d/%3d"
            " | def spent %5d squads lost %d garrison lost %3d | x%.1f%s" % (
                d["label"], d["winner"], d["duration"], d["match_time"], f["obj"]["vents"], d["totals"]["def"]["gates_lost"], gate, vent,
                f["atk"]["spent"], f["atk"]["lost"], f["atk"]["spawned"], f["def"]["spent"], d["totals"]["def"]["squads_lost"],
                f["def"]["garrison_lost"], d["speed"], "  SCRIPT ERRORS: %d" % d["_script_errors"] if d.get("_script_errors") else ""))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--atk", default="even")
    ap.add_argument("--def", dest="deff", default="default")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--variant", default="")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--base", default="", help="build the patch on this variant instead of on the game")
    ap.add_argument("--patch", action="append")
    ap.add_argument("--set", action="append")
    ap.add_argument("--match-time", type=float, default=0.0)
    ap.add_argument("--fps", type=int, default=10)
    ap.add_argument("--ticks", type=int, default=30)
    ap.add_argument("--fine", action="store_true", help="the game's own 30 frames and 60 ticks a second")
    ap.add_argument("--sample", type=float, default=10.0)
    ap.add_argument("--out", type=Path, default=ROOT / "results" / "single")
    ap.add_argument("--label", default="")
    ap.add_argument("--timeout", type=float, default=3600.0)
    a = ap.parse_args()
    patch = {}
    for p in a.patch or []:
        patch.update(json.loads(Path(p).read_text()))
    patch.update(variant_mod.parse_sets(a.set))
    try:
        project = resolve_project(a.variant, a.keep, patch, a.base)
    except KeyError as e:
        sys.exit(f"patch error: {e.args[0]}")
    if a.fine:
        a.fps, a.ticks = 30, 60
    label = a.label or f"{Path(a.atk).stem}_vs_{Path(a.deff).stem}_s{a.seed}"
    d = run(project, a.atk, a.deff, a.seed, a.out, label, a.match_time, a.fps, a.ticks, a.sample, a.timeout)
    print(one_line(d))
    if "error" in d:
        print(d.get("log_tail", ""))
        sys.exit(1)
    print("telemetry:", d["_file"])


if __name__ == "__main__":
    main()
