#!/usr/bin/env python3
"""Stronghold Assault: a stochastic model of one match, built from the game's own constants.

It is NOT the game. It is a lane-level abstraction used to reason about pacing and balance before the real
engine is instrumented (see docs/balance/BALANCE_PLAN.md, Phase 0). What it keeps exactly as coded:

  * the economy (AttackerCommander: 250 supply, 12/s, +1.5/s per helipad, 60 units; DefenderArmory: 400, 6/s, 6 slots)
  * the CPU attacker's wave planner (AIAttacker._plan_wave, with the drone-driven extra bears and rhinos)
  * unit stats (UnitTypes.DATA), post stats (MountedGun, DefenderSoldier, ArtilleryStation, AATurret, GunnerSquad,
    DefenderDrone), structure hit points (LevelBuilder.GATE_HP / KEEP_HP), respawn and repair timers
  * who can hurt what: only infiltrators get inside, only rams (raid_keep) go for the Keep, raiders hunt soldiers

What it abstracts: space is three lanes (travel time = distance / speed), a "wall fight" in front of each gate,
and an "inside" stage per breached gate. Hit chances come from the weapons' angular spread against the target's
silhouette at the lane's standing distance (p_hit). Area weapons use the blast falloff of Combat.damage_area.

Run:  python3 tools/balance/siege_model.py            (prints the experiments quoted in the plan)
      python3 tools/balance/siege_model.py --quick    (fewer matches)
"""
from __future__ import annotations

import math
import random
import statistics
import sys
from dataclasses import dataclass, field

# --------------------------------------------------------------------------------------- game constants
# UnitTypes.DATA (cost, hp, speed m/s, basic attack: range m, damage, interval s, spread rad, structure mult;
# silhouette width/height m). role: i infantry, m melee, h healer, f flyer, a anti-air, s siege.
UNITS = {
    "rifleman": dict(cost=50, hp=100, speed=4.6, rng=30, dmg=8, fi=0.55, spread=0.035, smult=0.5, w=1.0, h=1.9, role="i"),
    "kangaroo": dict(cost=75, hp=90, speed=7.2, rng=20, dmg=18, fi=0.85, spread=0.06, smult=0.4, w=1.1, h=2.0, role="i", inside=True),
    "medic": dict(cost=90, hp=110, speed=5.5, rng=0, dmg=0, fi=1, spread=0, smult=0, w=1.1, h=1.4, role="h"),
    "talon": dict(cost=120, hp=110, speed=8.0, rng=0, dmg=0, fi=1, spread=0, smult=0.3, w=1.6, h=2.1, role="f"),
    "elephant": dict(cost=320, hp=1400, speed=3.0, rng=0, dmg=0, fi=1, spread=0, smult=1.5, w=3.2, h=3.8, role="a"),
    "mule": dict(cost=280, hp=450, speed=1.0, rng=0, dmg=0, fi=1, spread=0, smult=1.5, w=3.2, h=2.2, role="s"),
    "breacher": dict(cost=150, hp=420, speed=5.0, rng=7, dmg=49, fi=1.1, spread=0.14, smult=1.0, w=1.2, h=1.6, role="i", inside=True, ram=True),
    "chimp": dict(cost=80, hp=160, speed=5.5, rng=1.8, dmg=30, fi=0.7, spread=0, smult=0.3, w=1.0, h=1.7, role="m", inside=True),
    "giraffe": dict(cost=100, hp=160, speed=4.2, rng=30, dmg=6, fi=0.6, spread=0.04, smult=0.3, w=1.6, h=4.5, role="i"),
    "bison_gun": dict(cost=260, hp=600, speed=3.0, rng=0, dmg=0, fi=1, spread=0, smult=1.5, w=3.2, h=2.4, role="s"),
    "lioness": dict(cost=120, hp=300, speed=6.0, rng=2.6, dmg=28, fi=0.75, spread=0, smult=0.3, w=1.2, h=1.6, role="m"),
    "serpent": dict(cost=130, hp=240, speed=3.5, rng=46, dmg=95, fi=4.0, spread=0.006, smult=0.4, w=1.2, h=0.9, role="i"),
    "rhino": dict(cost=280, hp=1500, speed=3.0, rng=0, dmg=0, fi=1, spread=0, smult=1.2, w=2.6, h=2.4, role="a"),
    "hippo": dict(cost=260, hp=1000, speed=3.2, rng=26, dmg=8, fi=0.12, spread=0.02, smult=1.0, w=2.8, h=2.6, role="i"),
}
FIRE_JITTER = 1.025  # AttackerUnit._fire_at: fire_interval * U(0.9, 1.15)


@dataclass
class Rules:
    """Every number the plan proposes to touch. Defaults are the game as it stands."""
    map: str = "classic"            # "classic" | "jungle"
    timer: float = 600.0            # GameConfig.match_duration (JungleLevel.JUNGLE_TIME: 900)
    gate_hp: float = 1500.0         # LevelBuilder.GATE_HP
    keep_hp: float = 4000.0         # LevelBuilder.KEEP_HP
    start_supply: float = 250.0     # AttackerCommander.supply
    income: float = 12.0            # AttackerCommander.BASE_INCOME
    ai_income_mult: float = 1.0     # GameConfig.ai_income_mult(): 0.75 / 1.0 / 1.4
    pad_income: float = 1.5         # AttackerBase.INCOME
    unit_cap: int = 60              # AttackerCommander.UNIT_CAP
    # Garrison (the posts' AI crews).
    mg_dmg: float = 8.0             # MountedGun.AI_DAMAGE
    mg_interval: float = 0.16
    mg_spread: float = 0.035
    mg_hp: float = 300.0
    mg_repair: float = 25.0
    rifle_dmg: float = 11.0         # DefenderSoldier.AI_DAMAGE
    rifle_interval: float = 0.6
    rifle_spread: float = 0.05
    soldier_hp: float = 150.0
    soldier_respawn: float = 15.0
    mortar_dmg: float = 150.0       # ArtilleryStation
    mortar_radius: float = 7.0
    mortar_reload: float = 8.0      # AI_RELOAD_TIME
    mortar_hp: float = 400.0
    mortar_repair: float = 30.0
    aa_dmg: float = 18.0            # AATurret
    aa_reload: float = 3.0
    aa_hp: float = 150.0
    aa_repair: float = 75.0
    squad_hp: float = 420.0         # HeavyGunner
    squad_dps: float = 6.0 / 0.075  # per trooper, driven by the player
    squad_ai_scale: float = 0.3     # GunnerSquad.AI_DAMAGE_SCALE
    squad_reinforce: float = 20.0
    squad_respawn: float = 30.0
    drones: bool = True
    drone_hp: float = 70.0
    drone_dps: float = 2.0 * 0.9 / 0.65
    drone_rebuild: float = 385.0
    drone_sortie_duty: float = 0.5  # share of the time a called swarm is on station (fuel: DefenderDrone)
    # How much of a post the parapet hides from the ground (assumption, to be measured in the engine).
    cover: float = 0.4
    # Proposal hooks (all neutral by default).
    keep_dps_mult: float = 1.0      # rams' damage against the Keep
    keep_regen: float = 0.0         # Keep hit points mended per second while nobody is hitting it
    gate_armor: float = 0.0         # flat damage taken off every hit on a gate (like FoldingBridge's)
    gates_needed: int = 1           # (layered objective) gates that must fall before the Keep takes damage
    overtime: float = 0.0           # seconds the clock may run on while the Keep was hit in the last 10 s
    income_ramp: float = 0.0        # extra supply/s gained per minute of match (escalation)
    garrison_scale: float = 1.0     # multiplies the AI crews' damage (a CPU-defender difficulty)
    small_arms_gate: float = 1.0    # multiplies what rifles, SMGs, machine guns and shotguns do to a gate
    keep_slots: int = 0             # rams that can work on the Keep at once (0: no limit), like ram_gate_slots
    squad_guards_keep: bool = False # the Gunner Squad's AI falls back to the Keep's hall once a gate is down
    mule_range: float = 150.0       # UnitTypes mule bombard_range
    cpu_rams: int = 0               # CPU waves from the second on bring this many rams (0: AIAttacker as coded)


@dataclass
class Unit:
    type: str
    hp: float
    side: str
    arrive: float                   # when it reaches the wall fight
    state: str = "travel"           # travel | wall | inside | keep | dead
    cd: float = 0.0
    ram_cd: float = 0.0
    inside_at: float = 0.0
    skill_cd: float = 0.0
    setup_at: float = -1.0
    target: object = None

    @property
    def st(self):
        return UNITS[self.type]


@dataclass
class Post:
    kind: str                       # mg | soldier | mortar | aa
    side: str
    hp: float
    max_hp: float
    down_for: float = 0.0
    cd: float = 0.0
    target: object = None
    blind: float = 0.0

    def alive(self):
        return self.hp > 0.0


def p_hit(spread: float, dist: float, w: float, h: float) -> float:
    """Chance a round lands on a w x h silhouette: Combat.apply_spread puts it uniformly in a disc of radius
    spread * dist round the aim point (r = spread * sqrt(U))."""
    r = spread * dist
    if r <= 1e-6:
        return 1.0
    return min(1.0, min(w, 2 * r) * min(h, 2 * r) / (math.pi * r * r))


def blast_falloff(rng: random.Random) -> float:
    """Combat.damage_area for a target somewhere in the blast: linear falloff, never below 30%."""
    x = math.sqrt(rng.random())
    return max(1.0 - x, 0.3)


# Lanes. Distances (m) from where a wave gathers to its stand in front of the gate (LevelBuilder.FACE_DIST + 14),
# and the slant range from that stand to the posts on the gun deck above the gate (8.1 m up, 23 m back).
LANES = {
    "classic": {"edge": 41.0, "pad": 58.0, "spawn_edge": 94.0},
    "jungle": {"south": 520.0, "west": 320.0, "east": 400.0},
}
SLANT_MG = 24.4
SLANT_RIFLE = 27.0
GATE_TO_KEEP = 79.0
SIDES = ["south", "east", "west"]


class Match:
    def __init__(self, rules: Rules, attacker: str = "cpu", defender: str = "garrison", seed: int = 0,
                 human_skill: float = 0.5):
        self.r = rules
        self.rng = random.Random(seed)
        self.attacker = attacker
        self.defender = defender
        self.skill = human_skill
        self.t = 0.0
        self.dt = 0.5
        self.supply = rules.start_supply
        self.units: list[Unit] = []
        self.gates = {s: rules.gate_hp for s in SIDES}
        self.keep = rules.keep_hp
        self.keep_hit_at = -1e9
        self.posts: list[Post] = []
        for s in SIDES:
            self.posts.append(Post("mg", s, rules.mg_hp, rules.mg_hp))
        for s in ["south", "south", "east", "east", "west", "north"]:  # LevelBuilder.RIFLE_POSTS
            self.posts.append(Post("soldier", s, rules.soldier_hp, rules.soldier_hp))
        self.mortar = Post("mortar", "south", rules.mortar_hp, rules.mortar_hp)
        self.posts.append(self.mortar)
        for s in SIDES + ["north"]:
            for _ in range(2):
                self.posts.append(Post("aa", s, rules.aa_hp, rules.aa_hp))
        self.squad = [rules.squad_hp] * 5        # the Gunner Squad's troopers (south spawn hall)
        self.squad_cd = 0.0
        self.squad_at = "south"                   # which route it covers
        self.drones = [rules.drone_hp] * 30 if rules.drones else []
        self.drone_back: list[float] = []         # rebuild times
        # CPU attacker (AIAttacker)
        self.wave = 0
        self.pending: list[str] = []
        self.staging: list[Unit] = []
        self.wave_side = "south"
        self.first_wave_delay = 15.0
        self.human_wave: list[str] = []
        # Defender purchases (human defender only)
        self.credits = 400.0
        self.bought: list[dict] = []
        self.log = {"gate": None, "gate_side": None, "keep_first": None, "end": None, "winner": None,
                    "spent": 0.0, "lost": 0.0, "waves": 0}

    # ------------------------------------------------------------------ economy and waves
    def income(self) -> float:
        base = self.r.income * (self.r.ai_income_mult if self.attacker == "cpu" else 1.0)
        pads = 3 if self.r.map == "classic" else 2
        return base + self.r.pad_income * pads + self.r.income_ramp * self.t / 60.0

    def alive_units(self):
        return [u for u in self.units if u.state != "dead"]

    def live_swarms(self) -> int:
        return math.ceil(len(self.drones) / 5.0)

    def plan_wave(self):
        """AIAttacker._plan_wave, as coded."""
        self.wave += 1
        w = self.wave
        self.wave_side = self.rng.choice(SIDES)
        counts = {
            "breacher": 1 if w >= 2 and (w % 2 == 0 or w > 5) else 0,
            "mule": 1 if w >= 3 and w % 2 == 1 else 0,
            "elephant": 0 if w < 3 else (1 if w < 7 else 2),
            "medic": 1 if w < 5 else 2,
            "rifleman": min(3 + w, 10),
            "kangaroo": min(1 + w // 2, 5),
            "talon": 0 if w < 2 else min(w - 1, 4),
            "chimp": 0 if w < 3 else min(1 + w // 3, 4),
            "giraffe": 1 if w >= 2 else 0,
            "lioness": 0 if w < 2 else min(1 + w // 2, 6),
            "serpent": 0 if w < 3 else min(1 + (w - 3) // 2, 3),
        }
        if self.r.cpu_rams > 0 and w >= 2:
            counts["breacher"] = self.r.cpu_rams
        swarms = self.live_swarms()
        if swarms > 0:
            counts["rifleman"] = min(counts["rifleman"] + swarms, 14)
            if swarms >= 3 and w >= 2:
                counts["rhino"] = 1 if swarms < 5 else 2
        remaining = True
        while remaining:
            remaining = False
            for k in list(counts):
                if counts[k] > 0:
                    self.pending.append(k)
                    counts[k] -= 1
                    remaining = True

    def lane_time(self, side: str, type_id: str) -> float:
        if self.r.map == "classic":
            d = LANES["classic"]["edge"] if self.attacker == "cpu" else LANES["classic"]["pad"]
        else:
            d = LANES["jungle"][side]
        return d / UNITS[type_id]["speed"]

    def spawn(self, type_id: str, side: str) -> Unit | None:
        st = UNITS[type_id]
        if self.supply < st["cost"] or len(self.alive_units()) >= self.r.unit_cap:
            return None
        self.supply -= st["cost"]
        self.log["spent"] += st["cost"]
        u = Unit(type_id, st["hp"], side, 1e18)
        self.units.append(u)
        return u

    def cpu_think(self):
        if self.t < self.first_wave_delay:
            return
        if not self.pending and not self.staging:
            self.plan_wave()
        while self.pending:
            u = self.spawn(self.pending[0], self.wave_side)
            if u is None:
                break
            self.pending.pop(0)
            self.staging.append(u)
        if not self.pending and self.staging:
            self.launch(self.staging, self.wave_side)
            self.staging = []
            self.log["waves"] += 1

    def launch(self, group: list[Unit], side: str):
        for u in group:
            if u.state == "dead":
                continue
            u.side = side
            t = self.lane_time(side, u.type)
            if u.type == "mule":
                # It sets up as soon as the stronghold is in its gun's reach (150 m * 0.95), 7 s to arm.
                reach = 0.95 * self.r.mule_range
                gate_from_spawn = 108.0 if self.r.map == "classic" else LANES["jungle"][side] + 14.0
                t = max(gate_from_spawn - reach, 0.0) / UNITS["mule"]["speed"] + 7.0
            u.arrive = self.t + t

    # A scripted "competent human" attacker: one lane, combined arms, rams held until the gate is nearly down.
    HUMAN_BUILD = ["rifleman"] * 6 + ["medic"] * 2 + ["breacher"] * 3 + ["hippo", "serpent", "serpent", "medic",
                                                                         "breacher", "breacher", "chimp", "chimp"]
    RUSH_BUILD = ["breacher"] * 6
    BATTERY_BUILD = ["mule"] * 3 + ["breacher"] * 6

    def human_think(self):
        build = {"rush": self.RUSH_BUILD, "battery": self.BATTERY_BUILD}.get(self.attacker, self.HUMAN_BUILD)
        side = "east"  # a human learns the Gunner Squad sits in the south hall
        if not self.pending:
            self.pending = list(build)
        while self.pending:
            u = self.spawn(self.pending[0], side)
            if u is None:
                break
            self.pending.pop(0)
            self.staging.append(u)
        group = {"rush": 6, "battery": 3}.get(self.attacker, 8)
        if len(self.staging) >= group or (self.staging and not self.pending):
            self.launch(self.staging, side)
            self.staging = []
            self.log["waves"] += 1

    # ------------------------------------------------------------------ helpers
    def at_wall(self, side: str):
        return [u for u in self.units if u.state == "wall" and u.side == side]

    def hurt(self, u: Unit, amount: float):
        if u.state == "dead":
            return
        u.hp -= amount
        if u.hp <= 0.0:
            u.state = "dead"
            self.log["lost"] += u.st["cost"]

    def hit_post(self, p: Post, amount: float):
        if not p.alive():
            return
        p.hp -= amount
        if p.hp <= 0.0:
            p.hp = 0.0
            p.down_for = {"mg": self.r.mg_repair, "soldier": self.r.soldier_respawn, "mortar": self.r.mortar_repair,
                          "aa": self.r.aa_repair}[p.kind]

    def hit_gate(self, side: str, amount: float):
        if self.gates[side] <= 0.0:
            return
        amount = max(amount - self.r.gate_armor, amount * 0.1)
        self.gates[side] -= amount
        if self.gates[side] <= 0.0:
            self.gates[side] = 0.0
            if self.log["gate"] is None:
                self.log["gate"] = self.t
                self.log["gate_side"] = side

    def breached(self) -> list[str]:
        return [s for s in SIDES if self.gates[s] <= 0.0]

    # ------------------------------------------------------------------ the wall fight
    def attackers_fire(self, side: str, crowd: list[Unit]):
        r = self.r
        dt = self.dt
        posts = [p for p in self.posts if p.side == side and p.alive() and p.kind in ("mg", "soldier")]
        mortar_reach = side == "south" and self.mortar.alive()
        drones_up = len(self.drones) > 0 and len(crowd) > 0
        for u in crowd:
            st = u.st
            if u.type == "medic" or st["role"] in ("a",):
                continue
            # Bears (and AA units) are pulled onto drones in sight: AttackerUnit._update_drone_prey.
            if drones_up and u.type == "rifleman" and self.drones_on_station(side) > 0:
                dps = st["dmg"] / (st["fi"] * FIRE_JITTER)
                self.shoot_drones(dps * dt)
                continue
            if st["role"] == "s":
                self.siege_fire(u, side, posts)
                continue
            if st["role"] == "f":
                continue  # talons: see talon_tick
            if st["role"] == "m":
                continue  # melee can't reach the decks from outside; it waits for the breach
            dps = st["dmg"] / (st["fi"] * FIRE_JITTER)
            if u.type == "hippo":
                dps *= 0.8  # overheat_time 8 s, overheat_cooldown 2 s
            if u.type == "breacher":
                # Rams go for the gate: the charge (350 once, every 60 s) and the shotgun.
                if self.gates[side] > 0.0:
                    if u.ram_cd <= 0.0 and len([x for x in crowd if x.type == "breacher" and x.ram_cd > 54.0]) < 3:
                        u.ram_cd = 60.0
                        self.hit_gate(side, 350.0)
                    self.hit_gate(side, dps * r.small_arms_gate * dt)
                continue
            targets = [p for p in posts if st["rng"] >= (SLANT_MG if p.kind == "mg" else SLANT_RIFLE)]
            if mortar_reach and st["rng"] >= 28.4:
                targets = targets + [self.mortar]
            if targets:
                if u.target not in targets:
                    u.target = self.rng.choice(targets)
                p = u.target
                if p.kind == "soldier":
                    w, h = 0.8, 1.8 * (1 - r.cover)
                elif p.kind == "mg":
                    w, h = 1.4, 1.6 * (1 - r.cover)
                else:
                    w, h = 2.6, 1.6 * (1 - r.cover)
                slant = SLANT_MG if p.kind == "mg" else SLANT_RIFLE
                if u.type == "hippo":
                    chance = min(1.0, w * h / (math.pi * 2.2 ** 2))  # suppress_radius: it sprays round the target
                else:
                    chance = p_hit(st["spread"], slant, w, h)
                self.hit_post(p, dps * chance * dt)
            elif self.gates[side] > 0.0 and st["rng"] + 2.0 >= 12.0:
                chance = 0.5 if u.type == "hippo" else 1.0
                self.hit_gate(side, dps * st["smult"] * chance * r.small_arms_gate * dt)

    def siege_fire(self, u: Unit, side: str, posts: list[Post]):
        """Mule Artillery as the CPU plays it (AIAttacker._mule_guns): machines first, then soldiers, the gate."""
        if u.type != "mule":
            return
        u.skill_cd -= self.dt
        if u.skill_cd > 0.0:
            return
        u.skill_cd = 30.0
        machines = [p for p in self.posts if p.alive() and p.kind in ("mg", "mortar")]
        if self.attacker == "battery" and self.gates[side] > 0.0:
            self.hit_gate(side, 480.0 * 1.5)
            return
        if machines:
            p = self.rng.choice(machines)
            self.hit_post(p, 480.0 * max(1.0 - self.rng.random() * 0.25, 0.3))
            for q in self.posts:
                if q is not p and q.side == p.side and q.kind == "soldier" and q.alive() and self.rng.random() < 0.5:
                    self.hit_post(q, 480.0 * blast_falloff(self.rng))
            return
        soldiers = [p for p in posts if p.kind == "soldier"]
        if soldiers:
            self.hit_post(self.rng.choice(soldiers), 480.0 * blast_falloff(self.rng))
        else:
            self.hit_gate(side, 480.0 * 1.5)

    def talon_tick(self, u: Unit, side: str):
        """A Sky Talon over the wall: one bomb and one strafe run on arrival (90 s each), under the AA turrets."""
        if u.skill_cd <= 0.0:
            u.skill_cd = 90.0
            aa = [p for p in self.posts if p.side == side and p.kind == "aa" and p.alive()]
            mgs = [p for p in self.posts if p.side == side and p.kind == "mg" and p.alive()]
            if aa:
                self.hit_post(aa[0], 260.0)
            elif mgs:
                self.hit_post(mgs[0], 260.0 * 0.8)
            else:
                self.hit_gate(side, 260.0)
            for p in self.posts:
                if p.side == side and p.kind == "soldier" and p.alive() and self.rng.random() < 0.6:
                    self.hit_post(p, 18.0 * 7.7 * 0.6)
        u.skill_cd -= self.dt
        live_aa = len([p for p in self.posts if p.side == side and p.kind == "aa" and p.alive()])
        self.hurt(u, live_aa * self.r.aa_dmg / self.r.aa_reload * self.r.garrison_scale * self.dt)

    def drones_on_station(self, side: str) -> int:
        return int(len(self.drones) * self.r.drone_sortie_duty)

    def shoot_drones(self, dmg: float):
        if not self.drones:
            return
        self.drones[-1] -= dmg
        if self.drones[-1] <= 0.0:
            self.drones.pop()
            self.drone_back.append(self.t + self.r.drone_rebuild)

    def defenders_fire(self, side: str, crowd: list[Unit]):
        r = self.r
        dt = self.dt
        if not crowd:
            return
        ground = [u for u in crowd if u.st["role"] != "f"]
        for p in self.posts:
            if p.side != side or not p.alive() or p.kind not in ("mg", "soldier"):
                continue
            if p.blind > 0.0:
                p.blind -= dt
                continue
            # (An armed Mule Artillery stands 100 m and more out: beyond the machine guns' 60 m and the rifles' 50 m.)
            near = [u for u in crowd if u.type != "mule"]
            if not near:
                continue
            if p.target is None or p.target.state != "wall" or p.target.side != side or p.target.type == "mule":
                p.target = self.rng.choice(near)
            u = p.target
            st = u.st
            if p.kind == "mg":
                dps = r.mg_dmg / r.mg_interval
                chance = p_hit(r.mg_spread, SLANT_MG, st["w"], st["h"])
            else:
                dps = r.rifle_dmg / (r.rifle_interval * 1.05) * (18.9 / 20.7)  # 30 rounds, 1.8 s reload
                chance = p_hit(r.rifle_spread, SLANT_RIFLE, st["w"], st["h"])
            if st["role"] == "f":
                chance *= 0.6
            self.hurt(u, dps * chance * r.garrison_scale * dt)
        # A human on the hottest gate's machine gun (MountedGun.PLAYER_*: 17 a round, 13.3 a second, 75% heat duty).
        if self.defender == "human" and side == self.hot_side and not self.breached():
            mg = [p for p in self.posts if p.side == side and p.kind == "mg" and p.alive()]
            if mg and ground:
                u = min(ground, key=lambda x: x.hp)
                self.hurt(u, 17.0 / 0.075 * 0.75 * self.skill * dt)
        # Drones: 2.8 damage a second each, on the units the army leans on (DroneSwarm.PREY).
        n = self.drones_on_station(side)
        if n > 0 and ground:
            order = ["medic", "giraffe", "mule", "serpent", "kangaroo", "chimp", "lioness", "breacher", "hippo", "rifleman"]
            prey = sorted(ground, key=lambda x: order.index(x.type) if x.type in order else 99)[0]
            self.hurt(prey, n * r.drone_dps * dt)

    def mortar_fire(self):
        m = self.mortar
        if not m.alive():
            return
        m.cd -= self.dt
        if m.cd > 0.0 or m.blind > 0.0:
            return
        best = max(SIDES, key=lambda s: len([u for u in self.at_wall(s) if u.st["role"] != "f" and u.type != "mule"]))
        crowd = [u for u in self.at_wall(best) if u.st["role"] != "f" and u.type != "mule"]
        if len(crowd) < 3:
            m.cd = 1.0
            return
        m.cd = self.r.mortar_reload
        # The wave stands on a 2.2 m grid: the shell (7 m, aimed 5 m wide of the densest spot) catches the units
        # within its radius of where it lands.
        span = 2.2 * math.sqrt(len(crowd))
        caught = min(1.0, (self.r.mortar_radius / max(span * 0.5 + 2.5, 1.0)) ** 2)
        for u in crowd:
            if self.rng.random() < caught:
                self.hurt(u, self.r.mortar_dmg * blast_falloff(self.rng) * self.r.garrison_scale)

    def heal(self, crowd: list[Unit]):
        hurt = sorted([u for u in crowd if u.hp < u.st["hp"] and u.type != "medic"], key=lambda x: x.hp)
        slots = 2 * len([u for u in crowd if u.type == "medic"])
        for u in hurt[:slots]:
            u.hp = min(u.hp + 12.0 * self.dt, u.st["hp"])

    # ------------------------------------------------------------------ inside the stronghold
    def inside_tick(self):
        r = self.r
        dt = self.dt
        inside = [u for u in self.units if u.state in ("inside", "keep")]
        if not inside:
            return
        squad_alive = [i for i, hp in enumerate(self.squad) if hp > 0.0]
        human_squad = self.defender == "human" or r.squad_guards_keep
        driven = self.defender == "human"
        # The Gunner Squad: left to itself it holds the south hall; a human walks it to the Keep's hall.
        for u in inside:
            covered = human_squad or u.side == self.squad_at
            if u.state == "inside" and self.t >= u.inside_at and not (covered and squad_alive and u.st.get("ram")):
                u.state = "keep" if u.st.get("ram") else "inside"
        engaged = [u for u in inside if (human_squad or u.side == self.squad_at)]
        if squad_alive and engaged:
            per = r.squad_dps * (self.skill * (7.0 / 9.5) if driven else r.squad_ai_scale * r.garrison_scale)
            target = min(engaged, key=lambda x: x.hp)
            self.hurt(target, per * len(squad_alive) * dt)
            for u in engaged:
                if u.state == "dead" or not squad_alive:
                    continue
                dps = u.st["dmg"] / (u.st["fi"] * FIRE_JITTER)
                i = squad_alive[0]
                self.squad[i] -= dps * dt
                if self.squad[i] <= 0.0:
                    squad_alive.pop(0)
        # Raiders (chimps, kangaroos) hunt the soldiers on the decks, then the machines.
        hunters = [u for u in inside if u.state == "inside" and not u.st.get("ram") and self.t >= u.inside_at + 15.0
                   and not (squad_alive and (human_squad or u.side == self.squad_at))]
        for u in hunters:
            dps = u.st["dmg"] / (u.st["fi"] * FIRE_JITTER)
            prey = [p for p in self.posts if p.alive() and p.kind == "soldier"] or \
                   [p for p in self.posts if p.alive() and p.kind in ("mg", "mortar")]
            if prey:
                self.hit_post(prey[0], dps * 0.6 * dt)
        # Rams on the Keep (shotgun: 7 pellets of 7 every 1.1 s).
        if len(self.breached()) >= r.gates_needed:
            at_keep = [u for u in inside if u.state == "keep"]
            if r.keep_slots > 0:
                at_keep = at_keep[:r.keep_slots]
            for u in at_keep:
                if u.state == "keep":
                    self.keep -= u.st["dmg"] / (u.st["fi"] * FIRE_JITTER) * r.keep_dps_mult * dt
                    self.keep_hit_at = self.t
                    if self.log["keep_first"] is None:
                        self.log["keep_first"] = self.t

    def squad_tick(self):
        self.squad_cd -= self.dt
        if self.squad_cd <= 0.0:
            dead = [i for i, hp in enumerate(self.squad) if hp <= 0.0]
            if len(dead) == 5:
                self.squad = [self.r.squad_hp] * 5
                self.squad_cd = self.r.squad_reinforce
            elif dead:
                self.squad[dead[0]] = self.r.squad_hp
                self.squad_cd = self.r.squad_reinforce
            else:
                self.squad_cd = 1.0
        elif all(hp <= 0.0 for hp in self.squad) and self.squad_cd > self.r.squad_respawn:
            self.squad_cd = self.r.squad_respawn

    # ------------------------------------------------------------------ one step
    def step(self):
        r = self.r
        dt = self.dt
        self.t += dt
        self.supply += self.income() * dt
        self.credits += 6.0 * dt
        if self.attacker == "cpu":
            if int(self.t / dt) % 2 == 0:
                self.cpu_think()
        else:
            self.human_think()
        # arrivals; infiltrators go in through a breach
        for u in self.units:
            if u.state == "travel" and self.t >= u.arrive:
                u.state = "wall"
            if u.state == "wall" and u.st.get("inside") and self.gates[u.side] <= 0.0:
                u.state = "inside"
                u.inside_at = self.t + GATE_TO_KEEP / (u.st["speed"] * 0.8)
            u.ram_cd -= dt
        # posts come back
        for p in self.posts:
            if not p.alive():
                p.down_for -= dt
                if p.down_for <= 0.0:
                    p.hp = p.max_hp
        while self.drone_back and self.drone_back[0] <= self.t:
            self.drone_back.pop(0)
            self.drones.append(r.drone_hp)
        crowds = {s: self.at_wall(s) for s in SIDES}
        self.hot_side = max(SIDES, key=lambda s: len(crowds[s]))
        for s in SIDES:
            crowd = crowds[s]
            if not crowd:
                continue
            # Kangaroos' flash grenades: 2 s of blindness for the face's posts every 30 s (thrown together).
            if any(u.type == "kangaroo" for u in crowd) and int(self.t / dt) % int(30 / dt) == 0:
                for p in self.posts:
                    if p.side == s and p.kind in ("mg", "soldier"):
                        p.blind = 2.0
            self.attackers_fire(s, crowd)
            for u in crowd:
                if u.type == "talon" and u.state == "wall":
                    self.talon_tick(u, s)
            self.defenders_fire(s, [u for u in crowd if u.state == "wall"])
            self.heal([u for u in crowd if u.state == "wall"])
        self.mortar_fire()
        self.inside_tick()
        self.squad_tick()
        if r.keep_regen > 0.0 and self.t - self.keep_hit_at > 10.0:
            self.keep = min(self.keep + r.keep_regen * dt, r.keep_hp)

    def run(self) -> dict:
        r = self.r
        limit = r.timer
        while True:
            self.step()
            if self.keep <= 0.0:
                self.log["winner"] = "attacker"
                break
            if self.t >= limit:
                if r.overtime > 0.0 and self.t - self.keep_hit_at < 10.0 and self.t < r.timer + r.overtime:
                    continue
                self.log["winner"] = "defender"
                break
        self.log["end"] = self.t
        self.log["keep_left"] = max(self.keep, 0.0)
        return self.log


# --------------------------------------------------------------------------------------- experiments
def _one(args) -> dict:
    rules, attacker, defender, seed, skill = args
    return Match(rules, attacker, defender, seed, skill).run()


_POOL = None


def batch(rules: Rules, n: int, attacker="cpu", defender="garrison", skill=0.5, seed0=0) -> dict:
    global _POOL
    jobs = [(rules, attacker, defender, seed0 + i, skill) for i in range(n)]
    if n >= 16:
        if _POOL is None:
            import multiprocessing
            _POOL = multiprocessing.Pool()
        logs = _POOL.map(_one, jobs)
    else:
        logs = [_one(j) for j in jobs]
    wins = [l for l in logs if l["winner"] == "attacker"]
    ends = sorted(l["end"] for l in logs)
    gates = [l["gate"] for l in logs if l["gate"] is not None]
    p = len(wins) / n
    se = math.sqrt(max(p * (1 - p), 1e-9) / n)
    q = lambda xs, f: xs[min(int(f * len(xs)), len(xs) - 1)] if xs else float("nan")
    return {
        "n": n, "p_att": p, "ci": 1.96 * se,
        "len_med": q(ends, 0.5) / 60, "len_p10": q(ends, 0.1) / 60, "len_p90": q(ends, 0.9) / 60,
        "in_window": sum(1 for e in ends if 1200 <= e <= 1800) / n,
        "gate_med": (statistics.median(gates) / 60) if gates else float("nan"), "gate_rate": len(gates) / n,
        "win_med": (statistics.median(l["end"] for l in wins) / 60) if wins else float("nan"),
        "win_p10": q(sorted(l["end"] for l in wins), 0.1) / 60 if wins else float("nan"),
    }


def show(label: str, s: dict):
    print(f"{label:<54} P(att)={s['p_att']*100:5.1f}% ±{s['ci']*100:4.1f} | length med {s['len_med']:5.1f} "
          f"[p10 {s['len_p10']:5.1f}, p90 {s['len_p90']:5.1f}] min | in 20-30: {s['in_window']*100:5.1f}% | "
          f"gate falls {s['gate_rate']*100:5.1f}% (med {s['gate_med']:5.1f}) | att-win med {s['win_med']:5.1f}", flush=True)


def v01(mp: str, **kw) -> Rules:
    """The plan's structural changes (Phase 1), before any pacing knob is turned."""
    base = dict(map=mp, timer=1560.0, overtime=240.0, small_arms_gate=0.1, keep_slots=4, squad_guards_keep=True, cpu_rams=3)
    base.update(kw)
    return Rules(**base)


def main():
    n = 40 if "--quick" in sys.argv else 200
    probes = 8
    print("== 1. The game as it stands: CPU attacker against the garrison's AI ==")
    for mp, timer in (("classic", 600.0), ("jungle", 900.0)):
        for diff, mult in (("Easy", 0.75), ("Normal", 1.0), ("Hard", 1.4)):
            show(f"{mp} {int(timer/60)} min · CPU {diff}", batch(Rules(map=mp, timer=timer, ai_income_mult=mult), n))
    print("\n== 2. The game as it stands: scripted exploit probes against the garrison's AI ==")
    for mp, timer in (("classic", 600.0), ("jungle", 900.0)):
        for att, name in (("rush", "ram rush"), ("battery", "3 mules then rams"), ("human", "combined arms, one lane")):
            show(f"{mp} · {name}", batch(Rules(map=mp, timer=timer), probes, attacker=att))
    print("\n== 3. Only the clock changed (26:00 + up to 4:00 overtime) ==")
    for mp in ("classic", "jungle"):
        show(f"{mp} · CPU Normal", batch(Rules(map=mp, timer=1560.0, overtime=240.0), n))
        show(f"{mp} · ram rush", batch(Rules(map=mp, timer=1560.0, overtime=240.0), probes, attacker="rush"))
    print("\n== 4. Phase 1 structure, then the two master knobs: objective scale H x garrison scale g ==")
    print("   (H = 1: gate 9000, Keep 16000; small arms at 10% against gates, 4 rams on the Keep at a time,")
    print("    the Gunner Squad guards the Keep, CPU waves bring 3 rams)")
    for mp in ("classic", "jungle"):
        for hs in (0.25, 0.5, 1.0):
            for g in (0.5, 1.0, 2.0):
                show(f"{mp} · H={hs:<4} g={g:<3} · CPU Normal", batch(v01(mp, gate_hp=9000 * hs, keep_hp=16000 * hs, garrison_scale=g), n))
    print("\n== 5. Phase 1 structure: the exploit probes' earliest wins (H = 1, g = 1) ==")
    for mp in ("classic", "jungle"):
        for att, name in (("rush", "ram rush"), ("battery", "3 mules then rams"), ("human", "combined arms, one lane")):
            show(f"{mp} · {name}", batch(v01(mp, gate_hp=9000, keep_hp=16000), probes, attacker=att))
    print("\n== 6. Solving for 50%: bisection on ln g at a fixed objective scale ==")
    for mp in ("classic", "jungle"):
        for hs in (0.25, 0.5):
            lo, hi = math.log(0.25), math.log(2.0)
            for _ in range(6):
                mid = 0.5 * (lo + hi)
                st = batch(v01(mp, gate_hp=9000 * hs, keep_hp=16000 * hs, garrison_scale=math.exp(mid)), max(n // 2, 40))
                if st["p_att"] > 0.5:
                    lo = mid
                else:
                    hi = mid
            g = math.exp(0.5 * (lo + hi))
            show(f"{mp} · H={hs:<4} g*={g:4.2f} · CPU Normal", batch(v01(mp, gate_hp=9000 * hs, keep_hp=16000 * hs, garrison_scale=g), n, seed0=5000))
            show(f"{mp} · H={hs:<4} g*={g:4.2f} · ram rush", batch(v01(mp, gate_hp=9000 * hs, keep_hp=16000 * hs, garrison_scale=g), probes, attacker="rush"))


if __name__ == "__main__":
    main()
