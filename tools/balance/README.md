# Balance simulator

Plays whole matches with the CPU on both sides, headless, and writes each one up as JSON: for playtesting numbers and
strategies in bulk. The game side is `game/scripts/sim/sim_director.gd` (`--sim=`), `game/scripts/defense/ai_defender.gd`
(the CPU defender, with a policy) and the policies of `game/scripts/attacker/ai_attacker.gd`.

```sh
# One match (about 3-10 minutes of machine time for a 15-25 minute match):
python3 tools/balance/run_match.py --atk even --def default --seed 1

# A batch: every attacker policy against every defender policy, over the seeds. Prints the table.
python3 tools/balance/batch.py --name base --atk even,rush,siege,air --def default,turtle,clear --seeds 1-3

# The same with numbers changed (a "variant" of the game is made for the patch; the repository is not touched):
python3 tools/balance/batch.py --name gate20k --set LevelBuilder.GATE_HP=20000 --set UnitTypes.rifleman.hp=120 \
    --atk even --def default --seeds 1-6

# The table again, the matches' course phase by phase, one match minute by minute:
python3 tools/balance/summarize.py /tmp/stronghold-balance/results/base --phases
python3 tools/balance/summarize.py /tmp/stronghold-balance/results/base --match even_vs_default_s1
```

- **Policies** (`--atk`, `--def`): a name from `AIAttacker.POLICIES` / `AIDefender.POLICIES`, or a JSON file with the
  policy's keys (`{"base": "rush", "sides": "south", "wave_scale": 1.3}`). The keys are listed at the top of the two
  scripts.
- **Patches** (`--set Class.CONST=value`, `--patch file.json`): any `const` or `var` at the top of a script by its
  `class_name` (or `file.gd:NAME`), and any unit stat as `UnitTypes.<unit>.<stat>`. A key that matches nothing is an
  error. `tools/balance/variant.py NAME --keep` makes a variant to edit by hand (its scripts are plain copies);
  `variant.py NAME --diff` prints what was changed in it as a patch.
- **Speed**: matches are played at 10 frames and 30 physics ticks a game second by default (`--fine`: the game's own 30
  and 60). Only `BALANCE_SLOTS` (3) matches run at once on the machine; the others wait their turn.
- **Telemetry** (`<out>/<label>.json`): `winner`, `duration`, `events` (waves, gates, vents, squads bought and lost,
  helipads, bridges), `timeline` (every 10 s: both sides' credits, forces, losses, where the army stands, the gates' and
  vents' health) and `totals`.
