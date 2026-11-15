#!/usr/bin/env python3
"""Reads a batch of balance matches (tools/balance/batch.py) and prints what happened in them.

    python3 tools/balance/summarize.py /tmp/stronghold-balance/results/<name> [--phases] [--match LABEL]

The table: for each attacker policy against each defender policy, how often the attackers won, when the matches ended,
when the first gate and the first vent fell, and what each side spent and lost. --phases adds the matches' course in
five-minute phases (the design notes' "0-10, 10-15, 15-20, 20-25 minutes"): where the armies stood and what the
objectives' health was at the end of each. --match prints one match's timeline and events.
"""
import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

PHASES = [300, 600, 900, 1200, 1500]


def load(d: Path) -> list:
    out = []
    for f in sorted(d.glob("*.json")):
        if f.name in ("batch.json", "summary.json"):
            continue
        try:
            m = json.loads(f.read_text())
        except json.JSONDecodeError:
            continue
        if "winner" in m:
            m["_name"] = f.stem
            out.append(m)
    return out


def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else None


def fmt(x, spec="%.0f", none="  -"):
    return none if x is None else spec % x


def at_time(m: dict, t: float):
    """The timeline row at (or the last before) `t`; None if the match was over by then."""
    if m["duration"] < t - 5:
        return None
    best = None
    for row in m["timeline"]:
        if row["t"] <= t + 0.5:
            best = row
    return best


def report(d: Path, phases: bool = False) -> str:
    ms = load(d)
    if not ms:
        return f"no matches in {d}"
    groups = defaultdict(list)
    for m in ms:
        groups[(Path(m["atk_policy"]).stem, Path(m["def_policy"]).stem)].append(m)
    lines = []
    wins = sum(1 for m in ms if m["winner"] == "attacker")
    lines.append(f"{d.name}: {len(ms)} matches, attackers won {wins} ({100.0 * wins / len(ms):.0f}%), defenders {len(ms) - wins}")
    bj = d / "batch.json"
    if bj.exists():
        b = json.loads(bj.read_text())
        if b.get("patch"):
            lines.append("patch: " + json.dumps(b["patch"]))
    lines.append("%-14s %-14s %3s %8s %7s | %8s %8s %8s %6s | %7s %9s %7s | %7s %6s %8s | %5s" % (
        "attacker", "defender", "n", "atk wins", "end s", "1st gate", "1st vent", "1st in", "vents", "atk $", "atk lost", "walls", "def $", "sq lost", "gar lost", "errs"))
    for (atk, deff), g in sorted(groups.items()):
        w = sum(1 for m in g if m["winner"] == "attacker")
        first = lambda k: mean([m["totals"]["first"].get(k) for m in g])  # noqa: E731
        lines.append("%-14s %-14s %3d %7.0f%% %7.0f | %8s %8s %8s %6.1f | %7.0f %4.0f/%-4.0f %7.1f | %7.0f %6.1f %8.1f | %5d" % (
            atk[:14], deff[:14], len(g), 100.0 * w / len(g), mean([m["duration"] for m in g]),
            fmt(first("gate_down")), fmt(first("vent_down")), fmt(first("raider_inside")),
            mean([m["final"]["obj"]["vents"] for m in g]),
            mean([m["final"]["atk"]["spent"] for m in g]), mean([m["final"]["atk"]["lost"] for m in g]),
            mean([m["final"]["atk"]["spawned"] for m in g]),
            mean([max(r["atk"]["at_walls"] for r in m["timeline"]) for m in g]),
            mean([m["final"]["def"]["spent"] for m in g]), mean([m["totals"]["def"]["squads_lost"] for m in g]),
            mean([m["final"]["def"]["garrison_lost"] for m in g]),
            sum(m.get("_script_errors", 0) for m in g)))
    lines.append("(1st gate / vent / in: seconds to the first gate down, vent down and raider inside, over the matches where it happened;"
                 " walls: the most attackers at the walls at once; $: credits spent)")
    if phases:
        lines.append("")
        lines.append("course of the matches, at the end of each phase (means over the matches still going):")
        lines.append("%-14s %-14s %6s %3s | %5s %6s %6s %6s %6s | %6s %6s %6s %6s %6s | %7s %6s" % (
            "attacker", "defender", "at s", "n", "units", "value", "lost", "walls", "dist", "squads", "garr", "field", "guns", "trees-", "gate hp", "vents"))
        for (atk, deff), g in sorted(groups.items()):
            for t in PHASES:
                rows = [r for r in (at_time(m, t) for m in g) if r is not None]
                if not rows:
                    continue
                lines.append("%-14s %-14s %6d %3d | %5.1f %6.0f %6.1f %6.1f %6.0f | %6.1f %6.0f %6.0f %6.0f %6.0f | %7.0f %6.1f" % (
                    atk[:14], deff[:14], t, len(rows),
                    mean([r["atk"]["units"] for r in rows]), mean([r["atk"]["army_value"] for r in rows]),
                    mean([r["atk"]["lost"] for r in rows]), mean([r["atk"]["at_walls"] for r in rows]),
                    mean([r["atk"]["mean_dist"] for r in rows if r["atk"]["mean_dist"] >= 0]) or 0,
                    mean([sum(r["def"]["squads"].values()) for r in rows]), mean([r["def"]["garrison"] for r in rows]),
                    mean([r["def"]["garrison_field"] for r in rows]), mean([r["def"]["guns_alive"] for r in rows]),
                    mean([r["def"]["trees_gone"] for r in rows]),
                    mean([min(r["obj"]["gates"].values()) for r in rows]), mean([r["obj"]["vents"] for r in rows])))
    return "\n".join(lines)


def match_report(m: dict) -> str:
    lines = [f"{m['_name']}: {m['winner']} wins at {m['duration']:.0f}s of {m['match_time']:.0f}s  (atk={m['atk_policy']} def={m['def_policy']} seed={m['seed']})"]
    lines.append("%5s | %5s %6s %5s %5s %6s %5s %6s | %6s %6s %5s %5s %5s %5s | %-26s %5s %6s" % (
        "t", "units", "value", "lost", "walls", "inside", "wave", "dist", "credit", "squads", "garr", "g.lost", "guns", "drone", "gates", "vents", "v.hp"))
    for r in m["timeline"]:
        if int(round(r["t"])) % 60 != 0:
            continue
        a, dd, o = r["atk"], r["def"], r["obj"]
        lines.append("%5.0f | %5d %6d %5d %5d %6d %5d %6.0f | %6d %6d %5d %5d %5d %5d | %-26s %5d %6d" % (
            r["t"], a["units"], a["army_value"], a["lost"], a["at_walls"], a["inside"], a["wave"], a["mean_dist"],
            dd["credits"], sum(dd["squads"].values()), dd["garrison"], dd["garrison_lost"], dd["guns_alive"], dd["drones"],
            "/".join("%s %dk" % (k[0].upper(), v // 1000) for k, v in sorted(o["gates"].items())), o["vents"], o["vent_hp"]))
    lines.append("events: " + "; ".join("%.0f %s%s" % (e["t"], e["type"], "" if len(e) <= 2 else " " + ",".join(
        str(v) for k, v in e.items() if k not in ("t", "type"))) for e in m["events"]))
    t = m["totals"]
    lines.append("attackers spawned %s, lost %s" % (json.dumps(t["atk"]["spawned_by"]), json.dumps(t["atk"]["lost_by"])))
    if "deaths_at" in t["atk"]:
        lines.append("attackers died (by distance from the keep, m): %s; while crossing water: %d" % (json.dumps(t["atk"]["deaths_at"]), t["atk"].get("died_crossing", 0)))
    lines.append("defenders bought %s, lost %s; %s" % (json.dumps(t["def_bought"]), json.dumps(t["def_lost"]), json.dumps(t["def"])))
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir", type=Path)
    ap.add_argument("--phases", action="store_true")
    ap.add_argument("--match", default="")
    a = ap.parse_args()
    if a.match:
        for m in load(a.dir):
            if a.match in m["_name"]:
                print(match_report(m))
                print()
        return
    print(report(a.dir, a.phases))


if __name__ == "__main__":
    main()
