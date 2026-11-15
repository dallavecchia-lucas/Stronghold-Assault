#!/usr/bin/env python3
"""Makes a variant of the game to play balance matches on: a copy of the project's scripts and scenes with numbers
patched, sharing the real project's assets and import cache through symlinks (a few MB a variant, made in a second).

    python3 tools/balance/variant.py NAME [--patch patch.json] [--set Class.CONST=value ...] [--base OTHER] [--keep]
    python3 tools/balance/variant.py NAME --diff

prints the variant's directory (a Godot project: `godot --path <dir> ...`). The same NAME is rebuilt from the game as it
is now each time, so a variant always is the current game plus its patch; `--keep` leaves one that is there alone (to
edit its scripts by hand and play on: `--diff` then prints what was changed, as a patch for the repository), and
`--base OTHER` starts from another variant, hand edits and all, instead of from the game.

A patch is a JSON object of what to change:

    {"UnitTypes.rifleman.hp": 120,              a unit's stat (game/scripts/units/unit_types.gd's DATA)
     "DefenderArmory.INCOME": 7.5,              a script's constant (or var), by its class_name
     "AttackerCommander.BASE_INCOME": 13,
     "LevelBuilder.GATE_HP": 24000,
     "garrison.gd:MAX_ALIVE": 240,              or by its file's name, for scripts without a class_name
     "AIAttacker.policy": ...}                  (not this: policies are passed to a match with --atk / --def)

Values are written as GDScript literals: numbers as they are (an int stays an int where the game has an int, a float
gets its ".0"), true/false, strings quoted, lists and objects as JSON. A key that matches nothing is an error: a patch
never silently does nothing.
"""
import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAME = REPO / "game"
DEFAULT_ROOT = Path(os.environ.get("BALANCE_ROOT", "/tmp/stronghold-balance")) / "variants"
# What a variant copies (small) and what it shares with the real project (big: the models, the import cache).
COPY = ["scripts", "scenes", "project.godot", "icon.svg", "icon.svg.import"]
LINK = ["assets"]


def class_files(root: Path) -> dict:
    """class_name -> script, and file name -> script."""
    out = {}
    for f in (root / "scripts").rglob("*.gd"):
        out[f.name] = f
        m = re.search(r"^class_name\s+(\w+)", f.read_text(), re.M)
        if m:
            out[m.group(1)] = f
    return out


def literal(value, old: str) -> str:
    """`value` as a GDScript literal, shaped like the literal `old` it replaces."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        was_float = bool(re.fullmatch(r"-?\d*\.\d+(e-?\d+)?|-?\d+\.\d*", old.strip()))
        if was_float or isinstance(value, float) and not float(value).is_integer():
            return repr(float(value))
        return str(int(value))
    if isinstance(value, str):
        # A string that isn't one in the game is an expression (e.g. "deg_to_rad(8.0)").
        return json.dumps(value) if old.strip().startswith('"') else value
    return json.dumps(value)


def patch_unit(text: str, unit: str, stat: str, value) -> str:
    start = re.search(r'^\t"%s": \{' % re.escape(unit), text, re.M)
    if not start:
        raise KeyError(f"no unit '{unit}' in unit_types.gd")
    end = text.index("\n\t},", start.end())
    block = text[start.end():end]
    pat = re.compile(r'("%s":\s*)(\[[^\]]*\]|"[^"]*"|[^,\n}]+)' % re.escape(stat))
    m = pat.search(block)
    if not m:
        raise KeyError(f"unit '{unit}' has no stat '{stat}'")
    block = block[:m.start()] + m.group(1) + literal(value, m.group(2)) + block[m.end():]
    return text[:start.end()] + block + text[end:]


def patch_const(text: str, name: str, value, where: str) -> str:
    pat = re.compile(r"^((?:static\s+)?(?:const|var)\s+%s\s*(?::\s*[\w.\[\]]+\s*)?:?=\s*)([^\n#]+?)(\s*(?:#.*)?)$" % re.escape(name), re.M)
    m = pat.search(text)
    if not m:
        raise KeyError(f"no const or var '{name}' in {where}")
    return text[:m.start()] + m.group(1) + literal(value, m.group(2)) + m.group(3) + text[m.end():]


def apply_patch(root: Path, patch: dict) -> list:
    files = class_files(root)
    done = []
    for key, value in patch.items():
        if key.startswith("_") or key.startswith("#"):
            continue  # a comment
        if ":" in key:
            owner, name = key.split(":", 1)
            parts = [owner, name]
        else:
            parts = key.split(".")
        owner = parts[0]
        if owner not in files:
            raise KeyError(f"'{key}': no script with class_name or file name '{owner}'")
        f = files[owner]
        text = f.read_text()
        if owner == "UnitTypes" and len(parts) == 3:
            new = patch_unit(text, parts[1], parts[2], value)
        elif len(parts) == 2:
            new = patch_const(text, parts[1], value, f.name)
        else:
            raise KeyError(f"'{key}': expected Class.CONST or UnitTypes.unit.stat")
        f.write_text(new)
        done.append(key)
    return done


def build(name: str, patch: dict, root: Path = DEFAULT_ROOT, game: Path = GAME, base: str = "") -> Path:
    """Builds variant `name` from the game (or from the variant `base`, keeping its edits) plus `patch`."""
    v = root / name
    if v.exists():
        shutil.rmtree(v)
    v.mkdir(parents=True)
    src_root = root / base if base else game
    for item in COPY:
        src = src_root / item
        if src.is_dir():
            shutil.copytree(src, v / item)
        elif src.exists():
            shutil.copy2(src, v / item)
    for item in LINK:
        (v / item).symlink_to(game / item, target_is_directory=True)
    # The import cache: the imported files shared, the small indexes copied (Godot rewrites some of them).
    cache = game / ".godot"
    (v / ".godot").mkdir()
    for item in cache.iterdir():
        if item.name in ("imported", "shader_cache"):
            (v / ".godot" / item.name).symlink_to(item, target_is_directory=True)
        elif item.is_dir():
            shutil.copytree(item, v / ".godot" / item.name)
        else:
            shutil.copy2(item, v / ".godot" / item.name)
    apply_patch(v, patch)
    (v / "PATCH.json").write_text(json.dumps({"base": base, "patch": patch}, indent=1))
    return v


def diff(name: str, root: Path = DEFAULT_ROOT, game: Path = GAME) -> str:
    """The variant's scripts and scenes against the game's, as a unified diff (paths as in the repository)."""
    import subprocess
    v = root / name
    out = ""
    for item in ("scripts", "scenes", "project.godot"):
        r = subprocess.run(["diff", "-ruN", "--exclude=*.uid", str(game / item), str(v / item)], capture_output=True, text=True)
        out += r.stdout.replace(str(game) + "/", "a/game/").replace(str(v) + "/", "b/game/")
    return out


def parse_sets(sets: list) -> dict:
    out = {}
    for s in sets or []:
        k, _, val = s.partition("=")
        try:
            out[k] = json.loads(val)
        except json.JSONDecodeError:
            out[k] = val
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name")
    ap.add_argument("--patch", action="append", help="a patch JSON file (several are laid over one another in order)")
    ap.add_argument("--set", action="append", help="Class.CONST=value, over the patch files")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--base", default="", help="start from this variant (its edits kept) instead of from the game")
    ap.add_argument("--keep", action="store_true", help="if the variant is there already, leave it as it is")
    ap.add_argument("--diff", action="store_true", help="print the variant's scripts against the game's and stop")
    a = ap.parse_args()
    if a.diff:
        print(diff(a.name, a.root), end="")
        return
    if a.keep and (a.root / a.name).exists():
        print(a.root / a.name)
        return
    patch = {}
    for p in a.patch or []:
        patch.update(json.loads(Path(p).read_text()))
    patch.update(parse_sets(a.set))
    try:
        print(build(a.name, patch, a.root, base=a.base))
    except KeyError as e:
        sys.exit(f"patch error: {e.args[0]}")


if __name__ == "__main__":
    main()
