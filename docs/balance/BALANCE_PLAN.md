# Stronghold Assault: balance plan

**Targets.** A match between evenly skilled players lasts 20 to 30 minutes, and each side wins half of them.

**Status of this document.** Everything in sections 1 and 2 is read off the code (files and constants are named). The win rates and match lengths quoted come from a model of the match written from those constants (`tools/balance/siege_model.py`), not from the engine: Godot could not be installed in the session that wrote this, so no real match was run. The model is good for orders of magnitude, for comparing rule sets and for showing the method; its absolute numbers are not measurements. Phase 0 of the plan replaces it with engine telemetry.

---

## 0. The short version

1. **The game cannot produce a 20 to 30 minute match today.** The clock is 10 minutes (Classic Field) or 15 (Jungle Keep), and an attacker who knows the shortcuts ends it far sooner: against the CPU's garrison the model puts a ram rush at 1.5 minutes on the classic field and 2.7 on the jungle.
2. **The cause is structural, not a matter of unit stats.** Three numbers decide every match: how fast a gate can die (1500 HP against 44 damage a second per ram), how fast the Keep can die (4000 HP against the same rams, and nothing else can hurt it), and the clock. None of the three is tied to what the defender can do about it in time.
3. **The fix is in six phases**, in this order: measure in the engine; close the shortcuts; set the pacing (clock, objective sizes, escalation); solve the two master knobs with bots; tune units against a cost curve; calibrate the two CPU players, then people.
4. **The key requirement, derived in 3.1:** for nine equal-skill matches in ten to end between 20:00 and 30:00 with a 50/50 split, the time at which the attackers break the Keep must have its median at the clock and a spread (coefficient of variation) of no more than about 20%. Everything in the plan serves that one sentence.
5. **Two knobs are enough to hit two targets**, once the shortcuts are closed: an objective scale (gate and Keep hit points) and a strength ratio (income or garrison scale). In the model, on the classic field, gate 2250 / Keep 4000 with the garrison at 0.93 gives 50.5% ± 6.9 attacker wins with 99.5% of matches ending between 20 and 30 minutes (CPU attacker against the CPU garrison, 200 matches). The same rules do not carry over to the jungle, nor to a human attacker: each map and each CPU player needs its own solve (Phases 3 and 5).

---

## 1. The game as built

### 1.1 How a match is won

`match.gd`: the attackers win when the Keep's hit points reach zero; the defenders win when the clock runs out (`GameConfig.match_duration` 600 s; `JungleLevel.JUNGLE_TIME` 900 s).

The Keep is the reactor under the peak, 79 m behind each gate (`stronghold.glb`: gates at 79 to 80 m from the centre, the Keep at the centre). `Structure.buried` means only something with a line of sight inside the mountain can hit it. The chain is therefore:

| Step | What does it | Code |
|---|---|---|
| 1. Reach a gate | Everyone walks: 108 m from a classic flag, 320 to 520 m on the jungle | `LevelBuilder`, `JungleLayout` |
| 2. Break one of three gates (1500 HP) | Anything with a basic attack, at its `structure_mult`; rams' charges (350 each, 3 at a time, every 60 s); bison and mule shells (×1.5); talon bombs | `UnitTypes`, `RamCharge` |
| 3. Get inside | Only Chimps, Kangaroos and Breaching Rams (`infiltrator`) | `AttackerUnit._on_link_reached` |
| 4. Kill the Keep (4000 HP) | **Only Breaching Rams** (`raid_keep`). Chimps and Kangaroos hunt soldiers, then the machine guns and the mortar; they never touch the Keep | `AttackerUnit._raid_target` |

So eleven of the fourteen attacker units exist to get rams to the reactor and keep them alive there.

### 1.2 The two economies

| | Attackers (`AttackerCommander`) | Defenders (`DefenderArmory`) |
|---|---|---|
| Start | 250 supply | 400 credits |
| Income | 12/s, +1.5/s per helipad held (3 on classic: 16.5/s; 2 on jungle: 15/s) | 6/s |
| Cap | 60 units alive | 6 roster slots |
| Losses | Bought again without limit | A bought squad or machine is gone for good |
| Free forces | None | The garrison: it respawns for ever |
| CPU version | Income ×0.75 / 1.0 / 1.4 by difficulty | **Buys nothing** (`match.gd`: the CPU defender has no armory), no difficulty setting |

The defender's six best purchases cost 2200 credits, which 400 + 6t reaches at t = 300 s. After minute 5 the defender's income has nothing to buy unless something dies. The attackers' income never idles.

### 1.3 The garrison (free, respawning)

| Post | Count | HP | Back after | Left to itself (AI) | With the player on it |
|---|---|---|---|---|---|
| Machine gun over each gate | 3 | 300 | 25 s | 8 per 0.16 s = 50 dps, 60 m, spread 0.035 | 17 per 0.075 s = 227 dps (about 150 sustained with the heat), spread 0.012 |
| Rifleman on the gun decks | 6 (S 2, E 2, W 1, N 1) | 150 | 15 s | 11 per 0.63 s = 16 dps with reloads, 50 m, spread 0.05 | 26 per 0.11 s = 236 dps (153 with reloads) |
| Mortar, south roof | 1 | 400 | 30 s | 150 within 7 m every 8 s, 20 to 150 m, only at 3+ units together | Every 3.5 s, placed by hand |
| AA turret | 8 | 150 | 75 s | 18 every 3 s, 45 m, aircraft only | Nobody takes it over |
| Gunner Squad, south hall | 5 × 420 | — | One per 20 s; all five 30 s | 30% damage: 24 dps each, sees 45 m from its post | 80 dps each (about 295 for the squad with the heat) |
| Drones | 30 (6 swarms) | 70 | 385 s | 2.8 dps each; only bears and AA units can hit them | `C` calls a swarm |

The player multiplies whatever post they sit on by 3 (machine gun), 10 (rifle) or 3.3 (Gunner Squad), and can sit on one at a time. **The defender's real strength is the player's attention**, and the attackers have three lanes to split it across.

### 1.4 The attackers' units

Cost efficiency against one gun-deck face (one machine gun and two riflemen, AI crews, shooting from 24 to 27 m; hit chances from the weapons' spread against each unit's silhouette, section 3.2):

| Unit | Cost | HP | HP per supply | dps | dps per 100 supply | Seconds alive under one face's fire | Role and scope |
|---|---|---|---|---|---|---|---|
| Bear Rifleman | 50 | 100 | 2.0 | 14 | 28 | 2.1 | Line infantry; the only non-AA unit that can shoot drones; swims, dives |
| Kangaroo Commando | 75 | 90 | 1.2 | 21 | 28 | 1.7 | Raider (soldiers only); flash grenade (2 s blind, 30 s); 15% faster skills for 3 neighbours. Its 20 m guns cannot reach the decks from the ground |
| Wolf Medic | 90 | 110 | 1.2 | — | — | 2.6 | Heals 2 units at 12 HP/s, or sweeps mines |
| Sky Talon | 120 | 110 | 0.9 | — | — | 1.6 | Bomb 260 within 7 m and a strafe run, 90 s each; the AA turrets fire at it as well |
| Night Ops Chimp | 80 | 160 | 2.0 | 42 | 52 | 3.4 | Raider: kills soldiers, then guns. Never the Keep. Useless until a gate is down |
| Savanna Signal Scout | 100 | 160 | 1.6 | 10 | 10 | 2.2 | 75 m sight (others 26 to 46); ping reveals troopers |
| Armored Lioness | 120 | 300 | 2.5 | 36 | 30 | 5.7 | Hunts defenders on the ground only (squads that sally out) |
| Serpent Sniper | 130 | 240 | 1.9 | 23 | 18 | 8.1 | 95 a round at 46 m (74 m from a tree), never misses a post; bush trap kills one trooper in 15 s |
| Breaching Ram | 150 | 420 | 2.8 | 44 | 29 | 8.0 | Gate charge 350; raider; **the only unit that damages the Keep** |
| Hippo Heavy Gunner | 260 | 1000 | 3.9 | 52 | 20 | 12 | Sprays (2.2 m wide): poor against posts, good against a gate; smoke screen; raft |
| Bison Field Gun | 260 | 600 | 2.3 | — | — | 7.3 | 240 within 6 m at 80 m, every 40 s |
| Mule Artillery | 280 | 450 | 1.6 | — | — | 5.5 | 480 within 11 m at 150 m, every 30 s; 1 m/s, 7 s to set up |
| Combat Rhino | 280 | 1500 | 5.4 | — | — | 18 | 6 dps AA; cluster bombing, 32 shells of 28 |
| War Elephant | 320 | 1400 | 4.4 | — | — | 17 | 30 dps flak, 8 missiles; raft; no ground attack |

### 1.5 The defender's roster (bought, permanent losses)

| Purchase | Cost | Body | What it adds |
|---|---|---|---|
| Sniper | 220 | 300 HP | 140 a round to 400 m; tags a unit for 20 s: every defender hits it 20% harder. AI: 105 a round to 160 m, not into forest |
| Infiltrator Squad | 280 | 5 × 240 | Silent arrows (131 dps), 20 s camo; sabotages a helipad in 45 s (the attackers lose its spawn and 1.5/s until 15 s of retaking) |
| Flame Squad | 300 | 5 × 340 | 450 dps at 6 m (AI 225); burns forest, which Chimps and Serpents use |
| AA Squad | 350 | 5 × 300 | Seeking missiles; rocket strike 900 a volley; mines 160 within 4 m, 10 every 15 s, 40 down at most. Its AI lays mines and watches the sky, never fires at ground units |
| Hover Tank | 450 | 1100 HP | 220 within 7 m every 3.2 s; twin machine guns |
| Fighter Jet | 600 | 700 HP | Bombs 380 within 11 m (4, one back every 8 s); 16 missiles of 30. AI: passive until it is hit |

### 1.6 Distances and travel times

| Lane | Distance to the wall | Bear (4.6 m/s) | Ram (5.0) | Elephant (3.0) | Mule (1.0) |
|---|---|---|---|---|---|
| Classic, flag to gate | 94 m | 20 s | 19 s | 31 s | In range of the gate from the flag (108 m against a 150 m gun) |
| Jungle, citadel to south gate | about 520 m, one river | 113 s | 104 s | 173 s | 6.3 min to come within range |
| Jungle, Quarry to west gate | about 320 m | 70 s | 64 s | 107 s | 3 min |
| Jungle, Outpost to east gate | about 400 m, one river | 87 s | 80 s | 133 s | 4.3 min |
| Gate to Keep (inside) | 79 m | — | about 20 s | — | — |

### 1.7 The two CPU players

**CPU attacker** (`AIAttacker`): builds a wave, gathers it, launches it at a **random** lane. Wave costs with the drones up: 665, 1960, 2870, 3105, 3625 supply. At 16.5/s on the classic field that is launches at about 0:25, 2:24, 5:18, 8:26 and 12:06, so four waves in a ten minute match. It brings **one ram every second wave** (waves 2 and 4; every wave from the sixth). It never uses rhino cluster bombing, bisons, smoke screens, elephant salvos on the jet, or the helicopters.

**CPU defender**: the posts' AI crews and the drones, nothing else. No purchases, no Gunner Squad movement (it holds the south hall; a ram that comes in by the east or west gate walks to the Keep 58 m from the squad's post and beyond its 45 m sight).

### 1.8 Feedback loops

- **Snowball for the attackers:** a gate down lets Chimps and Kangaroos in; they kill the deck crews; fewer crews means less fire on the next wave. Bought squads never come back. Helipads add income.
- **Brakes on the attackers:** the garrison respawns free in 15 to 30 s; travel time (long on the jungle); the 60-unit cap.
- **Nothing ties these to time.** Whether the attackers are over the threshold is settled in the first few minutes and then feeds itself, which is why matches are either very short or go to the clock.

---

## 2. Diagnosis

### 2.1 The clock rules out the target

10 and 15 minutes. No tuning of anything else produces a 20 minute match.

### 2.2 Six shortcuts

| # | Shortcut | Arithmetic |
|---|---|---|
| S1 | **A ram's shotgun is the best siege weapon in the game.** 7 pellets of 7 every 1.1 s at `structure_mult` 1.0 | 44 dps per 150 supply. Six rams (900 supply, affordable 39 s in): three charges (1050) and the gate's last 450 HP in 1.7 s; then the Keep in 4000 / (6 × 44.5) = 15 s |
| S2 | **Small arms open gates.** Bears at 0.5, hippos at 1.0 | Ten bears: 71 dps, a gate in 21 s once the face is suppressed |
| S3 | **Classic field: the Mule's gun reaches the gate from its own spawn flag** (150 m against 108 m) | Three mules (840 supply at 0:36) set up in 7 s and one volley does 3 × 480 × 1.5 = 2160 to a 1500 HP gate. The east and west flags are 203 m from the mortar (reach 150 m), beyond the machine guns (60 m) and rifles (50 m): the CPU garrison has no answer |
| S4 | **The Keep is undefended on two routes of three** against the CPU defender (1.7) | One ram alone kills it in 90 s |
| S5 | **Nothing limits how many rams work on the Keep**, and its whole life is one unit's damage figure | The Keep's time to die is 90 s divided by the number of rams |
| S6 | **The defender's economy stops at six purchases** (1.2) while the attackers' never does | From minute 5 the defender only declines |

### 2.3 No objective outlasts the defender's response time

The defender's slowest response is walking the Gunner Squad from its hall to the Keep: 58 m at about 2.5 m/s, 25 s. The Keep dies to six rams in 15 s; a gate, in under 5 s. **Both die faster than the defender can get there.** This is the single most important number in the diagnosis: skill cannot answer something that is over before it can be reached.

### 2.4 The outer defence is cheap to beat

From the square law (3.3): the number of bears that just beats an AI machine gun is √(0.373 / 0.028) ≈ 3.7; a whole face (gun, two rifles) about 6 bears, 300 supply, 18 seconds of income. Six bears then keep that face's posts dead indefinitely (each post is re-killed faster than its respawn timer). Against the CPU defender the wall is not a defence, only a delay.

### 2.5 Unit outliers (for Phase 4)

- **Mule against Bison:** blast yield per second (3.2) 2517 against 281, nine times as much for 8% more supply. On the classic field the Mule's slowness costs nothing (S3), so the Bison is dominated there.
- **Breaching Ram:** best gate dps per supply, most hit points per supply of any raider, and the only Keep damage. Three roles, one unit.
- **Sky Talon:** 110 HP. A face's two AA turrets alone bring it down in about 9 s, a machine gun that turns on it in under 3; it usually delivers one bomb for 120 supply.
- **Kangaroo:** its guns (20 m) cannot reach the decks (24 m slant) from where the infantry stands.
- **Chimp, Lioness:** no target until a gate is down or a squad sallies; they count against the 60-unit cap meanwhile.
- **War Elephant, Combat Rhino:** 320 and 280 supply for anti-air; their value is zero unless the defender buys the jet or the drones are up.

### 2.6 The two maps are different games

Lanes are 3.4 to 5.5 times longer on the jungle. With identical constants the model's CPU attacker (Normal) wins 79.5% on the classic field and 22% on the jungle.

### 2.7 What the model says (200 matches per row; `docs/balance/model_results.txt`)

| Rules | Attacker | Map | Attacker wins | Length, median [10th, 90th] min | Ends in 20–30 |
|---|---|---|---|---|---|
| Today | CPU Easy / Normal / Hard | Classic | 34.5% / 79.5% / 80.0% | 10.0 / 9.6 / 7.9 | 0% |
| Today | CPU Easy / Normal / Hard | Jungle | 11.0% / 22.0% / 78.0% | 15.0 / 15.0 / 14.5 | 0% |
| Today | Ram rush (scripted) | Classic / Jungle | 100% / 100% | 1.5 / 2.7 | 0% |
| Today | Three mules, then rams | Classic / Jungle | 100% / 100% | 2.1 / 3.4 | 0% |
| Clock only (26:00 + 4:00) | CPU Normal | Classic | 93.5% | 9.6 [4.8, 16.4] | 9.5% |
| Clock only | CPU Normal | Jungle | 96.0% | 18.8 [11.9, 23.9] | 25.5% |
| Clock only | Ram rush | Classic / Jungle | 100% / 100% | 1.5 / 2.7 | 0% |

Lengthening the clock alone hands the match to the attackers and still leaves it short.

---

## 3. The mathematics

### 3.1 The targets, stated exactly

Let $\tau$ be the time the Keep falls ($\infty$ if it never does), $T$ the clock, $L=\min(\tau,T)$ the match length, and $F_s(t)=P(\tau\le t)$ for a skill gap $s$ between the players (0: equal).

- Fairness: $F_0(T)=\tfrac12$.
- Length: defender wins all end at $T$, so put $T$ inside the window. Attacker wins end at $\tau<T$, so the window holds if few of them come early: $F_0(20\text{ min})\le 0.10$.

Model $\tau$ as lognormal with median $m$ and log-spread $\sigma$. Fairness gives $m=T$. The length condition gives $T e^{-1.2816\,\sigma}\ge 20$, so with $T=26$:

$$\sigma \le \frac{\ln(26/20)}{1.2816} = 0.205 .$$

**The time to break the Keep must be centred on the clock with a coefficient of variation of about 20% or less.** Today it is centred nowhere: it is 2 minutes or infinity depending on the opening.

### 3.2 Effective firepower

*Aimed fire.* `Combat.apply_spread` puts a round uniformly in a disc of radius $R=\text{spread}\times d$ round the aim point. Against a silhouette $w\times h$:

$$p_\text{hit} \approx \min\!\Big(1,\ \frac{\min(w,2R)\,\min(h,2R)}{\pi R^2}\Big),\qquad \text{effective dps} = \frac{\text{damage}}{\text{interval}}\; p_\text{hit}.$$

An AI rifleman (spread 0.05) at 27 m has $R=1.35$ m and hits a bear 33% of the time: 5.3 effective dps out of 16. An AI machine gun hits it 75%: 37. The player's rifle (spread 0.003 aimed) hits every time. Accuracy, not damage, is most of the gap between the AI and the player.

*Area fire.* `Combat.damage_area` falls off linearly to a 30% floor. Averaged over a blast disc the factor is

$$\int_0^1 \max(1-x,\,0.3)\,2x\,dx = 0.414 ,$$

so a blast of damage $D$ and radius $r$ on units at density $\lambda$ per m² deals on average $0.414\,\pi r^2 D\,\lambda$. Call $Y=0.414\,\pi r^2 D$ the **blast yield**, and $Y/\text{cooldown}$ the yield rate:

| Weapon | Yield (damage·m²) | Per second |
|---|---|---|
| Mule shell (480, 11 m, 30 s) | 75,500 | 2,517 |
| Jet bomb (380, 11 m, 8 s) | 59,800 | 7,475 |
| Talon bomb (260, 7 m, 90 s) | 16,570 | 184 |
| Tank shell (220, 7 m, 3.2 s) | 14,020 | 4,381 |
| Bison shell (240, 6 m, 40 s) | 11,240 | 281 |
| Mortar (150, 7 m; AI 8 s, player 3.5 s) | 9,560 | 1,195 / 2,731 |
| Mine (160, 4 m) | 3,330 | 2,220 for a squad laying 10 every 15 s |

A wave standing on the game's 2.2 m formation grid has $\lambda=0.21$: the formation spacing is itself a balance constant, because every area weapon's value is proportional to it.

### 3.3 Attrition with reinforcement and respawn

Aimed fire follows Lanchester's square law. With $N$ attackers and $P$ posts, $\dot N=-\beta P$, $\dot P=-\alpha N$, the quantity $\beta P^2-\alpha N^2$ is conserved, and the attackers win a single clash if $N>P\sqrt{\beta/\alpha}$. For bears against an AI machine gun, $\beta=37.3/100$ bears per second and $\alpha=8.4/300$ guns per second per bear, giving the 3.7 bears of 2.4. With the player on the gun, $\beta=1.5$ and the threshold doubles to 7.3; but only on that face.

The match is not one clash: attackers arrive at rate $\rho=\text{income}/\bar c$ and posts come back after $r$ seconds. In fluid form:

$$\dot N = \rho - \frac{D(P)}{\bar h_N},\qquad \dot P = \frac{P_0-P}{r} - \frac{a\,N}{h_P}.$$

Its steady state gives the **suppression threshold**: a post stays dead when $N \ge h_P/(r\,a)$ per post. For a rifleman, $150/(15\times4.4)=2.3$ bears; for the machine gun, $300/(25\times8.4)=1.4$. Above the threshold the defence's fire collapses and the attackers' numbers grow at the full rate $\rho$; below it they are ground down. The system has two stable states and a tipping point between them. That is the mathematical reason matches are bimodal, and why arriving together (a wave) beats trickling in.

Two consequences for tuning: (a) respawn times and post hit points move the tipping point in direct proportion, so they are the clean knobs for the wall; (b) a design that wants long, contested matches has to move the tipping point *during* the match (3.5).

### 3.4 Objectives are integrators, and they must outlast the response

A structure of $H$ hit points under siege throughput $S$ takes $H/S$. The rule the game breaks today (2.3):

$$\frac{H}{S_\text{max}} \;\ge\; 1.5 \times t_\text{response}.$$

To bound $S_\text{max}$, the damage has to come from sources limited by cooldowns or by room, not by head count:

| Source | Throughput against a gate |
|---|---|
| Ram charges, 3 slots, 60 s | 17.5 dps (20.6 with a Kangaroo's supplies) |
| Mule | 24 dps each |
| Bison | 9 dps each |
| Rhino cluster (about 40% on the door) | about 10 dps each |
| Talon bomb | 2.9 dps each |

A realistic siege park (three rams, a mule, a bison, two talons) is about 60 dps. For the Keep, four rams at a time is 178 dps.

### 3.5 Escalation: why the strength ratio must grow, and how fast

Let the attackers' pressure be $a\,\varphi(t)$ against a defence $d$, with $s=a/d$ the players' relative strength. The crossover time $t_\times$ solves $s\,\varphi(t_\times)=1$.

- **No escalation** ($\varphi$ constant, today): $t_\times$ is 0 or never. Bimodal.
- **Linear** ($\varphi=t/t_0$): $t_\times=t_0/s$. A player 20% stronger moves the crossover from 25 minutes to 20.8; elasticity $-1$.
- **Exponential** ($\varphi=e^{kt}$): $t_\times=-\ln s/k$, so $\partial t_\times/\partial\ln s=-1/k$ whatever the time.

Requirement 3.1 allows $\sigma_\tau/\tau\le 0.2$, about ±6 minutes at the 10th and 90th percentiles. If play-to-play variation in effective strength is $\sigma_{\ln s}\approx0.2$ (to be measured in Phase 0), then $1.28\times0.2/k\le 6$ min needs $1/k\le 23$ min:

**the attackers' strength relative to the defence should double about every 16 minutes: roughly ×3 over the match.**

The game has the ingredients, uncontrolled: the CPU's waves grow, bought squads are permanent losses, gate damage is permanent. The plan makes the ramp explicit and tunable (income that rises with time) so that it, not the opening, decides when the crossover comes.

A mismatch is still decided by skill: a player 50% stronger ($\ln s=0.4$) brings the crossover forward by $0.4\times23\approx9$ minutes and wins at about 17:00. A stomp may be short. The window is a promise about even matches.

### 3.6 Phases reduce variance

If the break takes $k$ independent stages, $CV(\tau)=CV_\text{stage}/\sqrt k$ for equal stages. Wall, gate, tunnel fight and Keep already give four. Damage that stays (a gate does not heal) is what makes the stages add up; nothing in the plan lets objectives regenerate.

### 3.7 Two targets, two master knobs

Take $x=(\ln H,\ \ln g)$: the objective scale and a strength ratio (the garrison's scale, or equivalently the attackers' income), and $y=(\operatorname{logit}P,\ \text{median attacker-win time})$. Estimate the Jacobian by finite differences on the same random seeds and step $x\leftarrow x-J^{-1}(y-y^\ast)$. From the model's grid on the classic field:

$$J\approx\begin{pmatrix}-4.9 & -8.8\\ +5.3\text{ min} & +21.6\text{ min}\end{pmatrix},\qquad \det J\neq0 .$$

Both knobs move both targets, but not in the same proportion, so the pair can be solved. The win rate is steep: doubling the garrison's strength takes the model's attacker from 100% to 30% to 0%. Knobs are therefore always moved in log steps of 5 to 10%, by bisection, never by round numbers.

### 3.8 Fairness between sides, separated from skill

Model $P(i\text{ attacking beats }j)=\sigma(\beta+\gamma(s_i-s_j))$. $\beta$ is the side advantage the plan must drive to zero; $\gamma$ is how much skill decides. In a **mirrored pair** (the same two players play both sides) the expected number of attacker wins is

$$\sigma(\beta+d)+\sigma(\beta-d),\qquad d=\gamma(s_i-s_j),$$

which equals exactly 1 when $\beta=0$ **whatever the skill gap**, and increases with $\beta$. So counting attacker wins over mirrored pairs tests side balance without knowing anyone's skill. All human testing in Phase 6 is run in mirrored pairs for this reason.

### 3.9 Balance over strategies, not only over numbers

Take attacker plans $i$ (ram rush, siege park, air, three-lane split, …) and defender plans $j$ (hold the hot gun, forward squads, mines, helipad sabotage, jet, …), with $M_{ij}=P(\text{attacker wins})$ measured by bots. The game's value $v=\max_x\min_y x^\top M y$ comes from a small linear program. Targets: $v=0.5$; the optimal mixes $x^\ast,y^\ast$ put weight on several plans (no dominant line); the best pure reply to the intended play gains no more than about 5 points. Removing one unit and re-solving (restricted play, Jaffe et al. 2012) gives that unit's worth $\Delta v_k$: 0 means useless, very large means mandatory. Section 2.5's outliers are the candidates.

### 3.10 How many matches

For a win rate within $\pm\varepsilon$ at 95%: $n=0.96/\varepsilon^2$ at $p=0.5$: 385 matches for ±5 points, 1,068 for ±3. A sequential test of 50% against 56% (5% errors each way) needs about 380 on average and stops early when the answer is clear. Comparing two rule sets on the same seeds cuts the noise of the difference several times over, which is why the engine's random numbers must be seedable (Phase 0).

---

## 4. The plan

### Phase 0. Measure (before changing a single number)

1. **Seed the game.** One `--seed`, fed to a `RandomNumberGenerator` used by everything that calls `randf`/`randi` today (wave lanes, spread, scatter, spawn offsets).
2. **Bot against bot, headless.** `--autotest=bots`: `AIAttacker` against a new `AIDefender`, to the end of the match, at 4× or faster. Today's autotest presses keys on a timer and stops after a fixed time; it cannot answer who wins.
3. **`AIDefender` with a skill dial.** It plays as a person must: one post at a time, with a reaction delay, an aim error and a switch time, and it buys and orders the roster. The dial (reaction, aim, switches a minute) gives a ladder of defenders. The attacker gets the same: wave size, lane choice, use of skills.
4. **Telemetry.** One JSON per match: every spawn, death (by what), post down and back, gate and Keep HP every 5 s, purchases, idle credits and supply, the breach time, the winner and length.
5. **Scripted probes** kept as regression tests: the ram rush, the mule battery, the three-lane split. A balance patch is rejected if a probe wins before 15:00.
6. **Calibrate the model** in `tools/balance/siege_model.py` to the telemetry (the parapet's cover, hit chances, how many units a mortar shell catches, the drones' time on station), then use it as the fast inner loop and the engine as the judge.
7. **Baseline report.** Section 2.7 again, measured.

### Phase 1. Close the shortcuts

| # | Change | Where | Closes |
|---|---|---|---|
| 1.1 | Small arms at about a tenth against gates: rifles, SMGs, machine guns, claws; the ram's shotgun too, through a separate `gate_mult` (its `structure_mult` stays for the Keep). Charges, shells, bombs unchanged | `unit_types.gd`, `Combat.fire_hitscan` | S1, S2 |
| 1.2 | Four rams work on the Keep at a time (`KEEP_SLOTS`), as three fit a gate; the rest guard them | `AttackerUnit._raid_target`, `RamCharge` | S5 |
| 1.3 | The Gunner Squad's AI falls back to the Keep's hall once any gate is down | `GunnerSquad._ai_control` | S4 |
| 1.4 | Classic field: a mule may not shell from its spawn. Either no setting up within 70 m of an edge flag, or the mortar's AI answers an armed siege gun alone and reaches it. Pick after Phase 0 | `AttackerUnit.set_gun` or `ArtilleryStation._ai_fire` | S3 |
| 1.5 | The CPU defender gets an armory and a buying script (a Sniper first, then by what the attackers field), and a difficulty scale on its crews' damage | `match.gd`, new `AIDefender` | S4, 2.4 |
| 1.6 | The CPU attacker brings siege in every wave from the second, picks the gate with the least HP instead of a random one, and uses the skills it ignores (cluster bombing, bisons, smoke) | `AIAttacker._plan_wave`, `_launch_wave` | 1.7 |
| 1.7 | A use for the defender's credits after six slots: re-crew a wiped squad at a discount, at the least | `DefenderArmory` | S6 |

Model check with 1.1 to 1.3 in, at gate 9000 / Keep 16000: the ram rush's first win moves from 1.5 to 7.4 minutes (classic) and from 2.7 to 10.5 (jungle); the mule battery and the one-lane push no longer win at all against the CPU garrison. The rush is slowed but not stopped: that last part is 1.5's job, because the CPU defender still does not fight back.

### Phase 2. Pacing

| # | Change | Starting value | Reason |
|---|---|---|---|
| 2.1 | Clock, both maps | 26:00 | Defender wins end inside the window |
| 2.2 | Overtime: the clock holds at 0:00 while the Keep was hit in the last 10 s, to 30:00 at most | +4:00 | No match ends with rams on the reactor; hard stop at the top of the window |
| 2.3 | Gate hit points | 4,500, bracket 2,250 to 9,000 | 75 s under a 60 dps siege park: three times the response time (3.4) |
| 2.4 | Keep hit points | 8,000, bracket 4,000 to 16,000 | 45 s under four rams: 1.8 times the squad's 25 s walk |
| 2.5 | Attackers' income rises with time | 9/s + 0.4/s per minute (12 at 7:30, 19.4 at 26:00) in place of a flat 12 | The ×3 ramp of 3.5, with the defender's permanent losses supplying the rest |
| 2.6 | Per-map objective scale | Classic 1.0; jungle solved in Phase 3 (the model says about half) | 2.6 |

These are starting points for Phase 3, not final values.

### Phase 3. Solve the master knobs with bots

For each map: take bots at the middle of the skill ladder on both sides, and solve the two knobs of 3.7 (objective scale; income) for the two targets (50%; 90% of matches in the window) by bisection in log steps, 200 seeded matches a point, in the calibrated model first and confirmed in the engine. Then repeat at the low and high ends of the ladder: the side advantage $\beta$ must stay within ±3 points at each, or the fix is structural (something scales with skill on one side only), not numeric.

What the model shows this looks like (CPU attacker with three rams a wave against the CPU garrison, Phase 1 in):

| Map | Gate / Keep | Garrison scale | Attacker wins | Length [10th, 90th] | In 20–30 | Attacker-win median |
|---|---|---|---|---|---|---|
| Classic | 2,250 / 4,000 | 0.93 | 50.5% ± 6.9 | 26.0 [21.9, 26.0] | 99.5% | 24.9 |
| Classic | 4,500 / 8,000 | 0.74 | 60.0% ± 6.8 | 25.4 [20.9, 26.0] | 94.5% | 23.1 |
| Jungle | 4,500 / 8,000 | 0.43 | 50.0% ± 6.9 | 26.0 [15.5, 26.0] | 69.5% | 19.2 |
| Jungle | 2,250 / 4,000 | 0.52 | 42.0% ± 6.8 | 26.0 [15.1, 26.0] | 71.5% | 18.9 |

The classic field lands on both targets. The jungle reaches 50% but too many attacker wins come early: its long lanes make the result hang on which waves arrive together, so it needs a third lever of its own (shorter lanes through the helicopters and helipads, or a later clock), which is what the per-map solve is for. In the same rule sets the scripted ram rush still beats the CPU garrison in 3 to 4.5 minutes: the CPU attacker's balance and the CPU defender's are separate problems (Phase 5).

### Phase 4. Units and roster

1. **Cost curve.** Regress cost on hit points, effective dps, range, speed and the skills' yield rates across the fourteen units; anything more than 25% off the fit is reviewed. Expected first: Mule (cheap for its yield), Sky Talon (dear for one bomb), Breaching Ram (three roles).
2. **Spread the Keep's fate over more than one unit.** Either let Chimps place slow charges on the reactor, or leave it to rams and price them for it. A decision for the owner (5.3).
3. **Give the stranded units work:** Kangaroo range to 26 m so its guns reach the decks; a target for Lionesses and Chimps before the breach (the helipads' defence against Infiltrators is the natural one).
4. **Strategy matrix** (3.9) from bot matches, five plans a side; re-solve after every change; each unit's $\Delta v_k$ between 1 and 8 points.
5. **Defender roster** on the same footing: credits per unit of expected attacker supply destroyed, by purchase. The AA Squad's mines and the Sniper's 20% tag are the ones to watch.

One master knob or one unit per patch, in steps of 10% or less (3.7).

### Phase 5. Calibrate the two CPU players

With the core fixed, each CPU is a one-dimensional root-find against a mid-ladder bot, then against people: the CPU attacker's income multiplier (today 0.75 / 1.0 / 1.4) and the CPU defender's new scale, set so the human wins about 70% on Easy, 50% on Normal and 30% on Hard, on each map.

### Phase 6. People

1. Mirrored pairs only (3.8): the count of attacker wins per pair tests side balance free of skill.
2. Sequential test: about 380 matches settles 50% against 56%.
3. Keep the telemetry on in playtest builds; a dashboard of the acceptance figures below per map and per skill band; the probes of Phase 0 in CI.

### Acceptance

| Measure | Target |
|---|---|
| Attacker win rate, mirrored pairs, each map | 50% ± 3 (1,068 matches) |
| Matches ending between 20:00 and 30:00, even skill | 90% or more |
| Attacker wins before 20:00, even skill | 10% or fewer |
| Any scripted probe winning before 15:00 against the mid-ladder defender | Never |
| Side advantage at the low, middle and high skill bands | Within ±3 points each |
| Value of the strategy matrix | 0.50 ± 0.03, at least three plans a side in the optimal mix |
| Fastest possible gate and Keep kill | At least 1.5 times the defender's response time |
| Human against the CPU on Normal, each side, each map | 50% ± 5 |

---

## 5. Risks and open decisions

### 5.1 Risks

- **The model's assumptions.** How much of a deck post the parapet hides (assumed 40%), how many units a mortar shell catches, and the drones' time on station are guesses until Phase 0. They move the absolute numbers, not the diagnosis: the shortcuts of 2.2 are arithmetic on the code's constants.
- **A human defender is not modelled.** The model's defender is the garrison's AI. How much a person on the guns and a bought roster add is the first thing the bot ladder has to measure.
- **Long matches need things to do.** Twenty-six minutes on three gates may drag; if playtests say so, the lever is a staged objective (an outer line before the gates), which also helps 3.6.

### 5.2 What the session could not do

Run the game. Godot 4.5 was not installed and downloading it was blocked. Phase 0 starts by running the three existing autotest commands and the new bot match on a machine with the engine.

### 5.3 Decisions for the owner

1. **Which 50/50 comes first:** player against player (this plan's default: fix the core, then handicap each CPU), or the offline game against the CPU.
2. **Overtime** (2.2): acceptable, or a hard stop at 26:00.
3. **The Keep:** rams only with four work slots, or a second way to hurt it.
4. **The defender's late economy** (1.7): re-crewing squads only, or something larger such as repairing a gate.

---

## Appendix: the model

`tools/balance/siege_model.py` (Python 3, no dependencies; `--quick` for a fast pass). It keeps the economy, the CPU's wave planner, unit and post statistics, respawn timers and the rules of who can hurt what exactly as coded; it reduces space to three lanes, a fight in front of each gate and a stage inside. `Rules` holds every constant this plan proposes to touch, defaulting to the game as it stands, so a rule set is one line. Output of the full run: `docs/balance/model_results.txt`.

References: Jaffe et al., *Evaluating Competitive Game Balance with Restricted Play*, AIIDE 2012 (https://ojs.aaai.org/index.php/AIIDE/article/view/12513). Hernandez et al., *Metagame Autobalancing for Competitive Multiplayer Games*, IEEE CoG 2020 (https://arxiv.org/pdf/2006.04419). Uriarte and Ontañón, *Combat Models for RTS Games* (https://arxiv.org/pdf/1605.05305). Lanchester's laws: https://faculty.nps.edu/mpatkins/docs/lanchester.pdf.
