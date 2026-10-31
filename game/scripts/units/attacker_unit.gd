class_name AttackerUnit
extends CharacterBody3D
## One attacking unit. Driven entirely by its current order:
##   {"type": "idle"}
##   {"type": "move", "pos": Vector3}          go there, ignore enemies
##   {"type": "attack_move", "pos": Vector3}   go there, fight anything in range
##   {"type": "attack", "target": Node3D}      chase and destroy a specific target
##   {"type": "raid"}                          raider inside the stronghold, on its own (_raid_target)
## Behaviour differences per unit come from UnitTypes role (infantry, melee, artillery,
## healer, flying, anti_air).
##
## The Wolf Medic (the dog, role healer) has two modes, one always on (dog_mode, set_dog_mode):
##   "heal"   it heals up to heal_units hurt allies within heal_range at heal_rate HP/s each. It sticks to
##            the ones it took until they are full or out of its reach, then takes the next; no unit takes
##            two dogs' healing (AttackerCommander._update_heal hands them out, into patients).
##   "sweep"  it sniffs out the defenders' mines within sweep_range (hidden from the attacking player),
##            walks up to one (only by a way that keeps clear of every other: DogSweep), digs it out and
##            disarms it (disarm_time seconds, the Dig clip; the mine shows to the attacker while it digs),
##            then the next, the minefield's outer rim first. It sweeps while idle or attack-moving; a
##            plain move (or any new order) calls the digging off.
##
## The Serpent Sniper (UnitTypes nest_*, trap_*) has two skills, each an order of its own:
##   {"type": "nest", "tree": ForestTree}   it goes up to the tree and climbs it (SerpentNest), up into its crown:
##            perched, it sees and shoots further (sight(), reach()) and can't move; any order to go anywhere
##            climbs it down first (the order waits in _after), an attack order it fires from the tree.
##   {"type": "trap", "bush": Bush}   it goes up to the bush, sets its rifle down and coils round it (SerpentTrap):
##            coiled, it never shoots; a defender on the ground in its reach it strikes and constricts to death
##            (squeeze_time), and no order calls that off; any other order uncoils it first.
## Both run on its rig (SerpentRig), which lays the body along the skill's way; the clips take over again once
## it is down or uncoiled, where it stood when it began.

signal died(unit: AttackerUnit)
## A Sky Talon's strafe round landed / it dropped its bomb (for showcases and the HUD).
signal strafe_impact(at: Vector3)
signal bomb_dropped(bomb: TalonBomb, spot: Vector3)
## A kangaroo's flash grenade left its paw for `spot`.
signal flash_thrown(grenade: FlashGrenade, spot: Vector3)
## A giraffe's ping went out from its dish.
signal pinged(ping: GiraffePing)
## A lioness sprang at `prey` (her pounce), and lit her fire blast.
signal pounced(prey: Node3D)
signal blasted(blast: LionessBlast)
## A dog dug a mine out and disarmed it.
signal mine_disarmed(mine: GroundMine)
## A Serpent Sniper is perched up its tree, coiled round its bush, struck `prey`, and squeezed it to death.
signal nested(tree: ForestTree)
signal coiled(bush: Bush)
signal struck(prey: Node3D)
signal crushed(prey: Node3D)

const HEAL_COLOR := Color(0.35, 1.0, 0.45)
const AA_COLOR := Color(1.0, 0.9, 0.4)
## How close to a broken gate an order has to land to send infiltrators in.
const BREACH_REACH := 12.0
## Collision radius of infiltrators (the navmesh is baked for 0.5 m).
const INSIDE_RADIUS := 0.35
## Ledges infiltrators step up onto (the step between the stronghold's corridors and halls).
const STEP_HEIGHT := 0.4
## How far past its own radius a ramming unit runs enemy soldiers over.
const TRAMPLE_REACH := 0.7
## Seconds before a ram can run over the same soldier again.
const TRAMPLE_REPEAT := 1.0
## A raiding ram rams a soldier it hunts once it is this close (m), if its ram is ready.
const RAID_RAM_REACH := 16.0
## raid_keep raiders turn aside for defenders this close (m); the others don't hold them up.
const RAID_DETOUR := 18.0
## A raiding kangaroo throws a flash grenade at the defender it hunts once it is this close (m), no
## closer than RAID_FLASH_MIN and no more than RAID_FLASH_RISE above or below it (up a ramp, not a
## floor up), if it is ready and in sight.
const RAID_FLASH_REACH := 16.0
const RAID_FLASH_MIN := 4.0
const RAID_FLASH_RISE := 3.5
## Seconds into the throw the grenade shows in the paw (it pulls it as it rears up).
const FLASH_IN_PAW := 0.25
const SUPPLY_COLOR := Color(0.85, 0.8, 0.35, 0.8)
const PING_COLOR := Color(0.45, 1.0, 0.6, 0.7)
## Sight of a unit type with none set (m).
const SIGHT := 30.0
## A lioness pounces on prey no more than this far above or below her (m): not up on the gun decks.
const POUNCE_RISE := 2.5
## She lands this share of her reach short of the prey's middle, and the pounce hits if it is still
## within her reach and this much more (m) when she lands.
const POUNCE_SHORT := 0.6
const POUNCE_SLACK := 1.0
## A strike that lands with the prey this much further than her reach (m) still hits.
const STRIKE_SLACK := 0.6
## Tagged by a Sniper (tag): defenders hit it this much harder, and its aim icon blinks once the tag has
## this long left (s).
const TAG_BONUS := 0.2
const TAG_BLINK := 3.0
## The icons over a unit (the aim, the ammo box, the bush): their texel sizes on screen in the RTS view
## (its field of view's half-angle tangent: ICON_FOV_TAN); other views scale them to look the same.
const TAG_ICON_SIZE := 0.0019
const SUPPLY_ICON_SIZE := 0.0017
const BUSH_ICON_SIZE := 0.0019
const ICON_FOV_TAN := 0.5206  # tan(55 deg / 2)
## The healed units' icon (a medic's cross) and the dogs' rings: how far a dog heals, and sniffs out mines.
const HEAL_ICON_SIZE := 0.0017
const SWEEP_COLOR := Color(1.0, 0.72, 0.2, 0.75)
## Seconds between a sweeping dog's looks for its next mine (and checks that its way there is still clear).
const SWEEP_EVERY := 0.5
## How far ahead an attack-moving sweeping dog with no mine to go for looks for mines on its way (m).
const WAY_AHEAD := 1.2
## Serpent Sniper: its snout lies this far ahead of it in its clips (m); it starts a skill this close to where it
## was going (m), turned to within FACE_TO of the trunk or the bush; its rig blends into a skill's pose and back
## out over SERPENT_BLEND (s); perched, it turns round its trunk at NEST_TURN (rad/s) and tips its front onto its
## aim at TIP_RATE; coiled, it looks for prey every TRAP_EVERY (s); its icons' sizes on screen (see TAG_ICON_SIZE).
const SNOUT_AHEAD := 2.45
const SKILL_REACH := 1.6
const FACE_TO := 0.15
const SERPENT_BLEND := 0.3
const NEST_TURN := 1.4
const TIP_RATE := 1.5
const TRAP_EVERY := 0.15
const NEST_ICON_SIZE := 0.0019

static var _supply_tex: ImageTexture
static var _bush_tex: ImageTexture
static var _tag_tex: ImageTexture
static var _heal_tex: ImageTexture
static var _nest_tex: ImageTexture
static var _trap_tex: ImageTexture

static var _scenes := {}

var unit_id := 0
var type_id := "rifleman"
var stats: Dictionary
var role := "infantry"
var team := GameConfig.TEAM_ATTACKER
var hp := 100.0
var order := {"type": "idle"}
var target: Node3D = null
## Set by the commander for units that were moved together; rhinos sharing one aim as a formation.
var formation_id := 0
## Seconds until the cluster bombing ability can be used again.
var cluster_cd := 0.0
## Seconds until the smoke screen can be used again.
var smoke_cd := 0.0
## Seconds until the missile salvo can be fired again.
var missile_cd := 0.0
## Seconds of firing the guns have built up toward overheat_time.
var heat := 0.0
## Seconds until the ram can be used again.
var ram_cd := 0.0
## Seconds until the bombardment can be fired again.
var bombard_cd := 0.0
## Seconds until the strafe run and the bomb strike can be flown again.
var strafe_cd := 0.0
var bomb_cd := 0.0
## Seconds until the flash grenade can be thrown again.
var flash_cd := 0.0
## Seconds until the giraffe can ping again.
var ping_cd := 0.0
## Seconds until the lioness can sneak / light her fire blast again.
var sneak_cd := 0.0
var blast_cd := 0.0
## Share a kangaroo nearby cuts off its skills' cooldowns (the kangaroo's passive, handed out by
## AttackerCommander): 0 when none does.
var resupply := 0.0
## Wolf Medic: "heal" or "sweep" (see above); the units it is healing (AttackerCommander hands them out).
var dog_mode := "heal"
var patients: Array = []
## The dog healing this unit, or null.
var medic: AttackerUnit = null
## Sweeping: the mine it is going for or digging out, and how many it has disarmed.
var sweep_mine: GroundMine = null
var mines_disarmed := 0
## Gate this ram is charging (RamCharge), and its slot across the doorway.
var charge_gate: Structure = null:
	set(g):
		charge_gate = g
		if _agent:
			# Chargers run straight for their slots: avoidance would jam them in the doorway.
			_agent.avoidance_enabled = g == null and is_alive() and not is_flying()
var charge_slot := 0
## Raider inside the stronghold: fights on its own and takes no more orders.
var raiding := false
var selected := false:
	set(v):
		selected = v
		if _ring:
			_ring.visible = v
		if _aa_ring:
			_aa_ring.visible = v
		if _supply_ring:
			_supply_ring.visible = v
		if _ping_ring:
			_ping_ring.visible = v
		_dog_rings()
		_update_hp_bar()

var _agent: NavigationAgent3D
var _model: Node3D
var _anim: AnimationPlayer  # set when the model is rigged and carries clips
var _ring: MeshInstance3D
var _aa_ring: MeshInstance3D
var _aa_lock: Node3D = null
var _turrets: ElephantTurrets  # set when the model carries flak cannons (stats.flak)
var _flight: TalonFlight  # flyers: how they glide, beat their wings and circle
## Where a flyer with nowhere to go circles: where it was last sent, or the fight it was in.
var _circle_at := Vector3.ZERO
var _next_gun := 0
## Missile salvo under way: tubes still to fire, and at what.
var _salvo: Array[int] = []
var _salvo_target: Node3D
var _salvo_target_id := 0
var _salvo_cd := 0.0
var _cluster_left := 0.0
var _cluster_cd_shot := 0.0
var _cluster_aim := Vector3.ZERO
var _overheat_left := 0.0
## Bombardment under way: where the shell goes, seconds left standing (laying the gun, then
## holding after the shot), and whether it has fired.
var _bombard_aim := Vector3.ZERO
var _bombard_left := 0.0
var _bombard_fired := false
## The model's muzzle bone (bombardment), when it has one.
var _muzzle_skel: Skeleton3D
var _muzzle_bone := -1
var _ram_left := 0.0
## Seconds since the last move order (a lioness walks until gallop_after: _speed).
var _moving_for := 0.0
var _charge_pos := Vector3.ZERO
## Soldiers run over during this ram: instance id -> msec, so each is hit once per pass.
var _trampled := {}
var _dust_cd := 0.0
var _butt := 0.0
var _wisp_cd := 0.0
var _strafe_shots := 0
## Flash grenade being thrown: where to, seconds into the throw (-1: none) and whether it has left
## the paw.
var _flash_aim := Vector3.ZERO
var _flash_t := -1.0
var _flash_thrown := false
## SMG burst under way: rounds still to fire, at what, and which gun fires next.
var _burst_left := 0
var _burst_cd := 0.0
var _burst_target: Node3D
var _next_muzzle := 0
var _rig: KangarooRig  # set when the model carries the kangaroo's SMGs and throwing paw
var _held: MeshInstance3D  # the flash grenade in the paw while it winds up
## Ping under way: seconds into it (-1: none) and whether the pulse has gone out.
var _ping_t := -1.0
var _ping_sent := false
var _ping_ring: MeshInstance3D
## Sneaking: seconds of it left. How each side sees it (_sneak_look): 0 as ever, 1 see-through (the
## defender's view), 2 with the bush over her (the attacker's); the see-through materials per surface.
var _sneak_left := 0.0
var _look := 0
var _ghosts: Array = []  # [MeshInstance3D, surface, see-through material]
var _bush: Sprite3D
## Pounce under way: seconds into it (-1: none), the prey, where she springs from and lands, the arc's
## height and whether it has landed.
var _pounce_t := -1.0
var _pounce_prey: Node3D
var _pounce_from := Vector3.ZERO
var _pounce_to := Vector3.ZERO
var _pounce_high := 0.0
var _pounce_landed := false
## Strike (a melee blow with its own clip) under way: seconds into it (-1: none), at what, whether the
## blow has landed, and whether its clip has to start over.
var _strike_t := -1.0
var _strike_target: Node3D
var _strike_hit := false
var _clip_restart := false
var _blast: LionessBlast
var _lion: LionessRig  # set when the model carries the lioness's flamethrower nozzles
## Serpent Sniper: its rig; the climb up its tree (SerpentNest) or its coil round its bush (SerpentTrap), how far
## along (0 on the ground beside it, 1 perched or coiled) and which way it is going (+1 up or in, -1 down or
## out, 0 still); where it stood when it began (it is back there when it is done); the order it follows once it
## is down or uncoiled; perched, what it was ordered to shoot; the strike under way (seconds into it, -1: none),
## the prey's health then, the way out to the prey and how far along it the snout is, and whether it is letting
## go (sliding back into its coil); its icon perched (the bush trap's is _bush).
var _serpent: SerpentRig
var _nest: SerpentNest
var _trap: SerpentTrap
var _skill_p := 0.0
var _skill_dir := 0
var _skill_xf := Transform3D.IDENTITY
var _after = null
var _focus: Node3D = null
var _squeeze_t := -1.0
var _squeeze_hp := 0.0
var _strike_way: Array = []
var _strike_s := 0.0
var _letting_go := false
var _trap_cd := 0.0
var _nest_icon: Sprite3D
## Sweeping: the way to the spot it digs its mine from, that spot, seconds to its next look, seconds into
## the dig (-1: not digging) and the last throw of dirt (a quarter of the Dig clip).
var _sweep_path: Array[Vector3] = []
var _sweep_spot := Vector3.INF
var _sweep_cd := 0.0
var _dig_t := -1.0
var _spray_k := -1
## Healing: a beam to each unit it heals; the icon over a healed unit; the dog's rings (heal, sweep).
var _beams: Array[MeshInstance3D] = []
var _heal_icon: Sprite3D
var _heal_ring: MeshInstance3D
var _sweep_ring: MeshInstance3D
## Fighting what it has in range and sight this frame (it stands and faces it).
var _engaged := false
var _supply_ring: MeshInstance3D
var _supply_icon: Sprite3D
## Snipers' tags on it: the tagging Sniper's instance id -> seconds left (tag); its aim icon.
var _tags := {}
var _tag_icon: Sprite3D
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _fire_cd := 0.0
var _retarget_cd := 0.0
## False while the target is a buried structure out of sight, or (raiding) anything out of sight: keep
## closing in instead of firing.
var _sees_target := true
var _anim_t := 0.0
## Navigation link being crossed (LevelBuilder): points still to climb or walk through.
var _route: Array[Vector3] = []
var _route_breach_in := false
var _in_forest := false
var _recoil := 0.0
var _desired_velocity := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(p_type: String, p_id: int) -> void:
	type_id = p_type
	unit_id = p_id
	stats = UnitTypes.DATA[p_type]
	role = stats.role
	hp = stats.hp
	name = "Unit%d" % p_id


func is_flying() -> bool:
	return role == "flying"


## Chimps and breaching rams are the only units that get inside the stronghold.
func fits_inside() -> bool:
	return stats.get("infiltrator", false)


## Raiders inside the stronghold are on their own.
func is_controllable() -> bool:
	return is_alive() and not raiding


## Medics, rhinos, elephants, bisons and talons never shoot at what they are ordered to attack.
func has_basic_attack() -> bool:
	return role != "healer" and role != "anti_air" and role != "siege" and stats.damage > 0.0


func has_cluster_bomb() -> bool:
	return stats.has("cluster_cooldown")


func cluster_ready() -> bool:
	return has_cluster_bomb() and cluster_cd <= 0.0


func has_smoke() -> bool:
	return stats.has("smoke_cooldown")


func smoke_ready() -> bool:
	return has_smoke() and smoke_cd <= 0.0


func is_overheated() -> bool:
	return _overheat_left > 0.0


func has_missiles() -> bool:
	return stats.has("missile_cooldown")


func missiles_ready() -> bool:
	return has_missiles() and missile_cd <= 0.0 and is_alive()


## Damage of one salvo if every missile hits.
func salvo_damage() -> float:
	return stats.missile_count * stats.missile_damage


func in_missile_range(t: Node3D) -> bool:
	var d := t.global_position - global_position
	return Vector2(d.x, d.z).length() <= stats.missile_range


func has_bombard() -> bool:
	return stats.has("bombard_cooldown")


func bombard_ready() -> bool:
	return has_bombard() and bombard_cd <= 0.0 and is_alive()


func has_strafe() -> bool:
	return stats.has("strafe_cooldown")


func strafe_ready() -> bool:
	return has_strafe() and strafe_cd <= 0.0 and is_alive() and not on_run()


func has_bomb() -> bool:
	return stats.has("bomb_cooldown")


func bomb_ready() -> bool:
	return has_bomb() and bomb_cd <= 0.0 and is_alive() and not on_run()


## Flying a strafe run or a bomb strike (TalonRun): it flies it through, whatever its orders.
func on_run() -> bool:
	return _flight != null and _flight.run != null


## Standing still to lay the gun or after the shot.
func is_bombarding() -> bool:
	return _bombard_left > 0.0


func has_ram() -> bool:
	return stats.has("ram_cooldown")


func ram_ready() -> bool:
	return has_ram() and ram_cd <= 0.0 and is_alive()


func is_ramming() -> bool:
	return _ram_left > 0.0


func ram_left() -> float:
	return _ram_left


## How far the ram still carries it: a charge at a gate further than this can't make it in time.
func ram_reach() -> float:
	return _ram_left * stats.speed * stats.ram_speed


func has_flash() -> bool:
	return stats.has("flash_cooldown")


func flash_ready() -> bool:
	return has_flash() and flash_cd <= 0.0 and is_alive() and not is_throwing()


## Up on its hind feet throwing a flash grenade: it stands until it is done.
func is_throwing() -> bool:
	return _flash_t >= 0.0


## Where the grenade in its paw is about to go (INF: none).
func flash_spot() -> Vector3:
	return _flash_aim if is_throwing() and not _flash_thrown else Vector3.INF


func has_ping() -> bool:
	return stats.has("ping_cooldown")


func ping_ready() -> bool:
	return has_ping() and ping_cd <= 0.0 and is_alive() and not is_pinging()


## Standing with its neck up and its dish sweeping, sending a ping: it stands until it is done.
func is_pinging() -> bool:
	return _ping_t >= 0.0


func has_sneak() -> bool:
	return stats.has("sneak_cooldown")


## A tagged lioness can't sneak (tag).
func sneak_ready() -> bool:
	return has_sneak() and sneak_cd <= 0.0 and is_alive() and not is_sneaking() and not is_pouncing() and not is_tagged()


## Stalking: see-through on the defender's side, a bush over her on the attacker's (_sneak_look).
func is_sneaking() -> bool:
	return _sneak_left > 0.0


func sneak_left() -> float:
	return _sneak_left


## Springing at her prey, or flying onto it: she pounces through, whatever her orders.
func is_pouncing() -> bool:
	return _pounce_t >= 0.0


func is_striking() -> bool:
	return _strike_t >= 0.0


func has_blast() -> bool:
	return stats.has("blast_cooldown")


func blast_ready() -> bool:
	return has_blast() and blast_cd <= 0.0 and is_alive() and not is_blasting()


## The flamethrowers on her back burning (LionessBlast).
func is_blasting() -> bool:
	return _blast != null and is_instance_valid(_blast) and _blast.left > 0.0


## How fast it can go now (a sneaking lioness stalks slower); LionessLine marches at a share of it.
func top_speed() -> float:
	return _speed()


## Standing and fighting what it has in range this frame.
func is_engaged() -> bool:
	return _engaged


## How far it sees through the fog of war (AttackerVision): a Serpent Sniper perched in its nest, further.
func sight() -> float:
	return stats.get("sight", SIGHT) * (stats.nest_sight if is_perched() else 1.0)


## How far its basic attack reaches: a Serpent Sniper perched in its nest, further.
func reach() -> float:
	return stats.range * (stats.nest_range if is_perched() else 1.0)


func has_nest() -> bool:
	return stats.has("nest_time")


func has_trap() -> bool:
	return stats.has("trap_time")


## Up its tree, or on its way up or down it (SerpentNest).
func in_tree() -> bool:
	return _nest != null


## Perched in its nest, all the way up: it sees and shoots further.
func is_perched() -> bool:
	return _nest != null and _skill_p >= 1.0 and _skill_dir == 0


## Round its bush, or on its way in or out of the coil (SerpentTrap), striking or letting go.
func in_bush() -> bool:
	return _trap != null


## Coiled round its bush, lying in wait: see-through on the defender's side, its icon on the attacker's.
func is_coiled() -> bool:
	return _trap != null and _skill_p >= 1.0 and _skill_dir == 0 and _squeeze_t < 0.0


## Striking and squeezing its prey: nothing calls it off.
func is_constricting() -> bool:
	return _trap != null and _squeeze_t >= 0.0 and not _letting_go


## Seconds of squeezing left.
func squeeze_left() -> float:
	return maxf(stats.squeeze_time - _squeeze_t, 0.0) if is_constricting() else 0.0


## How far up its tree or round its bush it is (0-1), and which way it is going (+1, -1, 0).
func skill_progress() -> float:
	return _skill_p if _nest != null or _trap != null else 0.0


func skill_dir() -> int:
	return _skill_dir


## The prey in its coils, or null.
func prey() -> Node3D:
	return _trap.prey if is_constricting() else null


## The tree it nests in (or is on its way to), the bush it coils round (or is on its way to).
func nest_tree() -> ForestTree:
	if _nest != null:
		return _nest.tree
	return order.tree if order.type == "nest" else null


func trap_bush() -> Bush:
	if _trap != null:
		return _trap.bush
	return order.bush if order.type == "trap" else null


## The Serpent Sniper's rig (null for the others).
func serpent_rig() -> SerpentRig:
	return _serpent


## Any of its skills cooling down: what a kangaroo's resupply speeds up.
func cooling_down() -> bool:
	return cluster_cd > 0.0 or smoke_cd > 0.0 or missile_cd > 0.0 or ram_cd > 0.0 or bombard_cd > 0.0 \
			or strafe_cd > 0.0 or bomb_cd > 0.0 or flash_cd > 0.0 or ping_cd > 0.0 or sneak_cd > 0.0 or blast_cd > 0.0


## Kangaroo passive: carries supplies for others (AttackerCommander hands them out).
func resupplies() -> bool:
	return stats.has("resupply_range")


## Wolf Medic: two modes, one always on (healing or minesweeping: dog_mode).
func has_dog_modes() -> bool:
	return stats.has("heal_units")


## Healing (dog_mode "heal"): it heals the units in patients.
func heals() -> bool:
	return has_dog_modes() and dog_mode == "heal" and is_alive()


## Minesweeping (dog_mode "sweep").
func sweeps() -> bool:
	return has_dog_modes() and dog_mode == "sweep" and is_alive()


## Switches the dog to `mode` ("heal" or "sweep"). Leaving healing it lets go of the units it heals;
## leaving sweeping, of the mine it was going for or digging out.
func set_dog_mode(mode: String) -> void:
	if not has_dog_modes() or mode == dog_mode or mode not in ["heal", "sweep"]:
		return
	dog_mode = mode
	patients.clear()
	_drop_mine()
	_sweep_cd = 0.0
	_dog_rings()


## Digging a mine out (the Dig clip): it stands until it is done.
func is_digging() -> bool:
	return _dig_t >= 0.0


## Where it digs its mine out from (INF: none).
func sweep_spot() -> Vector3:
	return _sweep_spot


## How far it has got digging its mine out (0-1; 0 when not digging).
func dig_progress() -> float:
	return clampf(_dig_t / stats.disarm_time, 0.0, 1.0) if is_digging() else 0.0


## A unit a healing dog may heal: a live, hurt ally (not itself) within heal_range.
func can_heal(u: AttackerUnit) -> bool:
	return u != self and is_instance_valid(u) and u.is_alive() and u.hp < u.stats.hp \
			and global_position.distance_to(u.global_position) <= stats.heal_range


## A Sniper's round hit it (Sniper): `by` tags it for `seconds` (tagged again, its time starts over).
## While it is tagged an aim icon hangs over it, on both sides; defenders hit it TAG_BONUS harder; and a
## lioness can't sneak (a sneak under way ends).
func tag(by: Object, seconds: float) -> void:
	if not is_alive():
		return
	_tags[by.get_instance_id()] = seconds
	end_sneak()


## Seconds left on `by`'s tag (0: it hasn't tagged it).
func tag_left(by: Object) -> float:
	return _tags.get(by.get_instance_id(), 0.0)


func is_tagged() -> bool:
	return not _tags.is_empty()


## The model's meshes (what a Sniper's thermal sight shows white-hot: SniperThermal).
func model_meshes() -> Array:
	return _model.find_children("*", "MeshInstance3D", true, false)


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("attacker_units")
	if is_flying():
		add_to_group("air_units")
	collision_layer = GameConfig.LAYER_ATTACKERS
	# Attackers don't collide with each other; avoidance keeps them apart instead.
	# Flyers don't collide with anything.
	collision_mask = 0 if is_flying() else GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES | GameConfig.LAYER_DEFENDERS
	floor_snap_length = 0.5

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = stats.radius
	if fits_inside():
		# Slimmer than the navmesh's agent radius, so paths hugging the stronghold's inside
		# corners don't snag on them.
		cap.radius = minf(stats.radius, INSIDE_RADIUS)
	cap.height = maxf(stats.height, stats.radius * 2.0 + 0.1)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)

	_agent = NavigationAgent3D.new()
	_agent.radius = stats.radius + 0.2
	_agent.height = stats.height
	_agent.max_speed = stats.speed
	_agent.path_desired_distance = 1.0
	_agent.target_desired_distance = 1.5
	_agent.avoidance_enabled = not is_flying()
	_agent.neighbor_distance = 6.0
	_agent.max_neighbors = 8
	_agent.time_horizon_agents = 1.0
	_agent.velocity_computed.connect(_on_velocity_computed)
	if fits_inside():
		_agent.navigation_layers |= LevelBuilder.NAV_INFILTRATORS
		_agent.link_reached.connect(_on_link_reached)
	add_child(_agent)

	_build_model()
	_build_ring()
	_build_hp_bar()
	_retarget_cd = randf() * 0.3
	_circle_at = global_position


# ---------------------------------------------------------------- orders

func set_order(o: Dictionary) -> void:
	if raiding:
		return
	if _serpent and not _serpent_order(o):
		return
	if has_dog_modes():
		_drop_mine()  # a new order calls the digging off (attack-moving, it sweeps again on the way)
		_sweep_cd = SWEEP_EVERY
	charge_gate = null  # a new order calls off a charge (RamCharge hands slots out after this)
	# Only infiltrators can reach the keep: the rest close in on the nearest broken gate.
	if o.type == "attack" and o.target.get("buried") and not fits_inside():
		var gate := _nearest_breach()
		o = {"type": "attack_move", "pos": gate.start_position} if gate else {"type": "idle"}
	# Medics and rhinos don't attack: follow the attack to its target instead.
	if not has_basic_attack() and o.type == "attack":
		o = {"type": "attack_move", "pos": _approach(o.target)}
	# Infiltrators sent to a broken gate go in: raiders as far as the tunnel (then they are on
	# their own), the others on to the keep.
	if fits_inside() and o.has("pos"):
		var breach := _breach_near(o.pos)
		if breach:
			var keep := _keep()
			if stats.get("raider", false) or keep == null:
				o = {"type": "move", "pos": breach.end_position}
			else:
				o = {"type": "attack", "target": keep}
	order = o
	if o.type in ["move", "attack_move", "nest", "trap"]:
		_moving_for = 0.0  # a new move order: walking again
		if _agent:
			_agent.max_speed = _speed()
	if o.type == "attack":
		target = o.target
	elif o.type == "move":
		target = null
	if o.has("pos") and not is_flying():
		_agent.target_position = o.pos


func is_idle() -> bool:
	return not raiding and order.type == "idle" and not Combat.is_valid_target(target) and sweep_mine == null


## Serpent Sniper: an order while up its tree or round its bush. Up the tree an attack order it fires from
## there; squeezing its prey it takes none; sent back up its own tree or round its own bush it goes back to it;
## anything else climbs it down or uncoils it first, and waits till then (_after). False when it has dealt with
## it. On the ground, a nest or trap order claims the tree or the bush for it.
func _serpent_order(o: Dictionary) -> bool:
	if _nest == null and _trap == null:
		_claim(o)
		return true
	if is_constricting() or o.type == "idle":
		return false
	if _nest != null and o.type == "attack" and _skill_dir >= 0:
		_focus = o.target
		return false
	if (o.type == "nest" and _nest != null and o.tree == _nest.tree) or (o.type == "trap" and _trap != null and o.bush == _trap.bush):
		_after = null
		if _skill_dir < 0:
			_skill_dir = 1
		return false
	_after = o
	_skill_dir = -1
	return false


## The tree or the bush a nest or trap order sends it to is its own (one snake to each), and where it goes to
## start from: its snout just short of the trunk or the bush, facing it. The one it was going to is free again.
func _claim(o: Dictionary) -> void:
	var tree = order.get("tree") if order.type == "nest" else null
	var bush = order.get("bush") if order.type == "trap" else null
	if tree != null and is_instance_valid(tree) and tree.nest_by == self and o.get("tree") != tree:
		tree.nest_by = null
	if bush != null and is_instance_valid(bush) and bush.coiled_by == self and o.get("bush") != bush:
		bush.coiled_by = null
	if o.type == "nest":
		o.tree.nest_by = self
		o.pos = _skill_approach(o.tree.trunk_centre(), o.tree.trunk_radius(0.0) + SerpentNest.BODY_R + 0.3)
	elif o.type == "trap":
		o.bush.coiled_by = self
		o.pos = _skill_approach(o.bush.global_position, SerpentTrap.ring_radius(o.bush) + 0.35)


## Where it lies, facing `centre` from the side it comes from, with its snout `gap` m short of it.
func _skill_approach(centre: Vector3, gap: float) -> Vector3:
	var out := global_position - centre
	out.y = 0.0
	out = out.normalized() if out.length() > 0.1 else global_basis.z
	return Vector3(centre.x, global_position.y, centre.z) + out * (gap + SNOUT_AHEAD)


## Open breach link whose outside end is near `pos`, or null.
func _breach_near(pos: Vector3) -> NavigationLink3D:
	for link in get_tree().get_nodes_in_group("breaches"):
		if link.enabled and pos.distance_to(link.start_position) <= BREACH_REACH:
			return link
	return null


func _nearest_breach() -> NavigationLink3D:
	var best: NavigationLink3D = null
	for link in get_tree().get_nodes_in_group("breaches"):
		if link.enabled and (best == null or global_position.distance_to(link.start_position) < global_position.distance_to(best.start_position)):
			best = link
	return best


func _keep() -> Structure:
	for s in get_tree().get_nodes_in_group("structures"):
		if s.buried and s.is_alive():
			return s
	return null


# ---------------------------------------------------------------- combat

func is_alive() -> bool:
	return hp > 0.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * stats.height * 0.6


func take_damage(amount: float, from_team: int) -> void:
	if hp <= 0.0 or from_team == team:
		return
	if is_tagged():
		amount *= 1.0 + TAG_BONUS
	hp -= amount
	_update_hp_bar()
	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(hp + amount, stats.hp)
	_update_hp_bar()


func _die() -> void:
	hp = 0.0
	remove_from_group("damageable")
	remove_from_group("attacker_units")
	remove_from_group("air_units")
	_cluster_left = 0.0
	_bombard_left = 0.0
	_flash_t = -1.0
	_ping_t = -1.0
	_burst_left = 0
	_sneak_left = 0.0
	_pounce_t = -1.0
	_strike_t = -1.0
	if is_blasting():
		_blast.left = 0.0
	var rolls := not (_serpent and _serpent_die())
	if has_sneak() or has_trap():
		_sneak_look()
	if _nest_icon:
		_nest_icon.visible = false
	resupply = 0.0
	patients.clear()
	medic = null
	_drop_mine()
	for b in _beams:
		b.visible = false
	if _heal_icon:
		_heal_icon.visible = false
	_dog_rings()
	_tags.clear()
	if _tag_icon:
		_tag_icon.visible = false
	if _held:
		_held.visible = false
	if _supply_icon:
		_supply_icon.visible = false
	if _supply_ring:
		_supply_ring.visible = false
	end_ram()
	_route.clear()
	_end_salvo()
	if _turrets:
		_turrets.target = null
	if _flight:
		_flight.die()
	collision_layer = 0
	collision_mask = GameConfig.LAYER_WORLD
	_agent.avoidance_enabled = false
	_ring.visible = false
	if _aa_ring:
		_aa_ring.visible = false
	if _ping_ring:
		_ping_ring.visible = false
	_hp_bar.visible = false
	died.emit(self)
	var tw := create_tween()
	if rolls:
		tw.tween_property(_model, "rotation:z", PI * 0.5, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(0.6)  # its rig drops the body where it lay (SerpentRig.die)
	tw.tween_interval(3.0)
	tw.tween_property(_model, "position:y", -stats.height, 2.0)
	tw.tween_callback(queue_free)


func _range_to(t: Node3D) -> float:
	var r = t.get("target_radius")
	return global_position.distance_to(t.global_position) - (r if r != null else 0.0)


func _in_range(t: Node3D) -> bool:
	var d := _range_to(t)
	return d <= reach() and d >= stats.get("min_range", 0.0)


func _eye() -> Vector3:
	return global_position + Vector3.UP * stats.height * 0.8


func _can_see(t: Node3D) -> bool:
	if role == "melee":
		return true  # within arm's reach
	if t.get("buried"):
		return not is_flying() and Combat.has_line_of_sight(self, _eye(), Combat.aim_point(t), t)
	if role == "artillery" or t.is_in_group("structures"):
		return true  # shells arc over walls; buildings are big enough to always hit
	return Combat.has_line_of_sight(self, _eye(), Combat.aim_point(t), t)


func _update_target() -> void:
	if not has_basic_attack():
		target = null
		return
	if raiding:
		target = _raid_target()
		return
	if order.type == "attack":
		# An infiltrator gone under adaptive camo is lost: the order lapses.
		if Combat.targetable(order.target):
			target = order.target
			return
		order = {"type": "idle"}
	# A Serpent Sniper on its way to a tree or a bush, climbing it or coiled round it picks no fights; perched, it
	# shoots what it was ordered to while it can, else whatever it can.
	if order.type in ["nest", "trap"] and not is_perched():
		target = null
		return
	if is_perched() and Combat.targetable(_focus) and AttackerVision.sees_node(_focus) and _in_range(_focus) and _can_see(_focus):
		target = _focus
		return
	# A sneaking lioness picks no fights on her own: only an attack order sends her (to pounce).
	if order.type == "move" or is_sneaking():
		target = null
		return
	if Combat.targetable(target) and _in_range(target) and _can_see(target) and not Combat.low_profile(target) \
			and AttackerVision.sees_node(target):
		return
	target = _find_enemy()


## The nearest defender in range and sight (else a gate or the keep in range). Infiltrators keep a
## low profile: a unit never picks one out on its own, only when ordered to attack it (or once a ping
## has revealed her). Defenders in the fog of war can't be picked out either (AttackerVision).
func _find_enemy() -> Node3D:
	var candidates := []
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if d.is_alive() and _in_range(d) and not Combat.low_profile(d) and AttackerVision.sees_node(d):
			candidates.append([global_position.distance_to(d.global_position), d])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for c in candidates.slice(0, 3):
		if _can_see(c[1]):
			return c[1]
	var best: Node3D = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("structures"):
		if s.is_alive() and s.team != team:
			var d := _range_to(s)
			if d <= reach() + 2.0 and d >= stats.get("min_range", 0.0) and d < best_d and _can_see(s):
				best_d = d
				best = s
	return best


## Raider: the nearest defender in the stronghold (the gun decks, the roofs, the player's soldier
## wherever they are). With all of them down, the nearest machine: the gate machine guns on the
## decks and the mortar on the roof. raid_keep raiders only fight the defenders near them and
## otherwise go for the keep. Sticks to its pick until something it prefers shows up.
func _raid_target() -> Node3D:
	var soldiers := []
	var machines := []
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if not d.is_alive() or Combat.low_profile(d):
			continue
		match d.get("station_kind"):
			"soldier": soldiers.append(d)
			"mg", "artillery": machines.append(d)
	if stats.get("raid_keep", false):
		# Only the defenders it runs into on the way: the rest of the time it makes for the keep.
		soldiers = soldiers.filter(func(d): return global_position.distance_to(d.global_position) <= RAID_DETOUR)
		var keep := _keep()
		machines = [keep] if keep else []
	var pool := soldiers if not soldiers.is_empty() else machines
	if target in pool:
		return target
	var best: Node3D = null
	var best_d := INF
	for d in pool:
		var dist := global_position.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _start_raid() -> void:
	raiding = true
	selected = false
	formation_id = 0
	order = {"type": "raid"}
	target = _raid_target()


func _fire_at(t: Node3D) -> void:
	_fire_cd = stats.fire_interval * randf_range(0.9, 1.15)
	_recoil = 1.0
	match role:
		"melee":
			if stats.has("anim_strike"):
				_start_strike(t)
				return
			_melee_hit(t)
		"artillery":
			var aim := Combat.aim_point(t)
			var scatter: float = global_position.distance_to(aim) * stats.spread
			aim += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * scatter
			var shell := Shell.new()
			shell.team = team
			shell.damage = stats.damage
			shell.radius = stats.splash
			shell.structure_mult = stats.structure_mult
			get_tree().current_scene.add_child(shell)
			var muzzle: Vector3 = global_position - global_basis.z * 3.5 + Vector3.UP * stats.height
			shell.launch(muzzle, aim)
			Combat.spawn_explosion(self, muzzle, 0.8)
		_:
			if stats.has("burst"):
				# Side-mounted SMGs: a burst, the guns taking turns (_burst_tick).
				_burst_left = stats.burst
				_burst_cd = 0.0
				_burst_target = t
				return
			if _serpent:
				_rifle_shot(t)
				return
			var aim := Combat.aim_point(t)
			if stats.has("suppress_radius"):
				# Spray: aim somewhere around the target, so neighbours catch rounds too.
				var r: float = stats.suppress_radius * sqrt(randf())
				var a := randf() * TAU
				aim += Vector3(cos(a) * r, randf_range(-0.4, 0.4) * stats.suppress_radius, sin(a) * r)
			# Shotguns fire a blast of pellets, each on its own line within the cone.
			for _pellet in stats.get("pellets", 1):
				Combat.fire_hitscan(self, _eye(), aim, stats.spread, stats.damage, team,
						stats.structure_mult, [get_rid()])


## Serpent Sniper: one heavy round from the rifle on its back, from its eyes at `t` (its tracer from the muzzle,
## and the white trail it leaves), the rifle kicking back, a flash and a puff of smoke at the muzzle.
func _rifle_shot(t: Node3D) -> void:
	var muzzle := _serpent.muzzle().origin if _serpent.posed() else _eye()
	var shot := Combat.fire_hitscan(self, _eye(), Combat.aim_point(t), stats.spread, stats.damage, team, stats.structure_mult,
			[get_rid()], muzzle, 0.07)
	# The white trail the round leaves hangs behind its tracer, like the defenders' Sniper's.
	SniperTrail.trail(self, muzzle, shot.position, Combat.BULLET_SPEED)
	Combat.spawn_impact(self, muzzle, true)
	SmokeCloud.wisp(self, muzzle, 1.0)
	_serpent.kick()


func _burst_tick(delta: float) -> void:
	_burst_cd -= delta
	while _burst_left > 0 and _burst_cd <= 0.0:
		_burst_cd += stats.burst_interval
		_burst_left -= 1
		if not Combat.targetable(_burst_target):
			_burst_left = 0
			return
		_smg_round(_burst_target)


## One round from the SMG whose turn it is: the shot goes from the eyes, the tracer from the muzzle.
func _smg_round(t: Node3D) -> void:
	var muzzle := smg_muzzle(_next_muzzle)
	_next_muzzle = 1 - _next_muzzle
	Combat.fire_hitscan(self, _eye(), Combat.aim_point(t), stats.spread, stats.damage, team,
			stats.structure_mult, [get_rid()], muzzle)
	Combat.spawn_impact(self, muzzle, false)  # muzzle flash


## Muzzle of SMG k (0 the left, 1 the right): the model's muzzle bone, or a guess beside the chest.
func smg_muzzle(k: int) -> Vector3:
	if _rig and _rig.posed():
		return _rig.muzzle(k).origin
	return global_position + Vector3.UP * stats.height * 0.6 + global_basis.x * (0.45 if k == 1 else -0.45) - global_basis.z * 1.0


## Kangaroo active: stand up and throw a flash grenade at `aim` (KangarooFlash.spots keeps it within
## flash_range). False while on cooldown.
func start_flash(aim: Vector3) -> bool:
	if not flash_ready():
		return false
	flash_cd = stats.flash_cooldown
	_flash_aim = aim
	_flash_t = 0.0
	_flash_thrown = false
	_burst_left = 0
	return true


func _flash_tick(delta: float) -> void:
	_flash_t += delta
	if not _flash_thrown and _flash_t >= stats.flash_release:
		_flash_thrown = true
		_throw_flash()
	if _flash_t >= stats.flash_time:
		_flash_t = -1.0


func _throw_flash() -> void:
	var from := grenade_position()
	var g := FlashGrenade.new()
	g.team = team
	g.radius = stats.flash_radius
	g.blind = stats.flash_blind
	get_tree().current_scene.add_child(g)
	# Inside the stronghold it skims along under the ceiling instead of lobbing high.
	var dist := from.distance_to(_flash_aim)
	g.launch(from, _flash_aim, 0.4 + dist * 0.05 if raiding else clampf(dist * 0.28, 1.5, 7.0))
	flash_thrown.emit(g, _flash_aim)


## The grenade in the throwing paw: the model's grenade bone, or a guess over the head.
func grenade_position() -> Vector3:
	if _rig and _rig.posed():
		return _rig.grenade()
	return global_position + Vector3.UP * stats.height * 1.2 - global_basis.z * 0.4


## Raiding kangaroo: throws a flash grenade at the defender it hunts, once in reach and in sight,
## unless it is blinded already or another kangaroo's grenade is on its way to it.
func _raid_flash() -> void:
	if not flash_ready() or not Combat.is_valid_target(target) or FlashGrenade.is_blind(target):
		return
	if FlashGrenade.coming(self, target.global_position, stats.flash_radius * 0.6):
		return
	var to := target.global_position - global_position
	if absf(to.y) < RAID_FLASH_RISE and to.length() <= minf(stats.flash_range, RAID_FLASH_REACH) \
			and to.length() >= RAID_FLASH_MIN and _can_see(target):
		start_flash(target.global_position)


## Giraffe active: stand, stretch its neck up and sweep the dish, and send a ping (GiraffePing) out
## from it. False while on cooldown.
func start_ping() -> bool:
	if not ping_ready():
		return false
	ping_cd = stats.ping_cooldown
	_ping_t = 0.0
	_ping_sent = false
	_burst_left = 0
	return true


func _ping_tick(delta: float) -> void:
	_ping_t += delta
	if not _ping_sent and _ping_t >= stats.ping_release:
		_ping_sent = true
		_send_ping()
	if _ping_t >= stats.ping_time:
		_ping_t = -1.0


func _send_ping() -> void:
	var p := GiraffePing.new()
	p.team = team
	p.radius = stats.ping_radius
	p.speed = stats.ping_speed
	p.mark = stats.ping_mark
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	pinged.emit(p)


## A melee blow landing on `t` (structures take structure_mult of it).
func _melee_hit(t: Node3D) -> void:
	var mult: float = stats.structure_mult if t.is_in_group("structures") else 1.0
	t.take_damage(stats.damage * mult, team)
	var to := t.global_position - global_position
	to.y = 0.0
	Combat.spawn_impact(self, global_position + to.normalized() * (stats.radius + 0.5) + Vector3.UP * stats.height * 0.6, true)


## Lioness: one blow of her melee attack (the Strike clip): it lands strike_hit seconds in, on `t` if it
## is still within reach. Striking gives a sneaking lioness away.
func _start_strike(t: Node3D) -> void:
	end_sneak()
	_strike_t = 0.0
	_strike_target = t
	_strike_hit = false
	_clip_restart = true


func _strike_tick(delta: float) -> void:
	_strike_t += delta
	if not _strike_hit and _strike_t >= stats.strike_hit:
		_strike_hit = true
		if Combat.targetable(_strike_target) and _range_to(_strike_target) <= stats.range + STRIKE_SLACK:
			_melee_hit(_strike_target)
	var length: float = _anim.get_animation(stats.anim_strike).length if _anim else stats.strike_hit * 2.0
	if _strike_t >= length:
		_strike_t = -1.0


## Lioness active: sneak for sneak_duration seconds (see UnitTypes). False while on cooldown.
func start_sneak() -> bool:
	if not sneak_ready():
		return false
	sneak_cd = stats.sneak_cooldown
	_sneak_left = stats.sneak_duration
	_agent.max_speed = _speed()
	_sneak_look()  # this frame, not the next
	return true


## The sneak is over (run out, or she struck, pounced or lit her flamethrowers): seen as ever again.
func end_sneak() -> void:
	if _sneak_left <= 0.0:
		return
	_sneak_left = 0.0
	if _agent:
		_agent.max_speed = _speed()
	_sneak_look()


## Sneaking, with an attack order on a defender on the ground: once it is within pounce_range and in
## sight, she pounces.
func _maybe_pounce() -> void:
	if not is_sneaking() or order.type != "attack" or not _pounceable(order.target):
		return
	var to: Vector3 = order.target.global_position - global_position
	if Vector2(to.x, to.z).length() <= stats.pounce_range and absf(to.y) < POUNCE_RISE \
			and Combat.has_line_of_sight(self, _eye(), Combat.aim_point(order.target), order.target):
		start_pounce(order.target)


## Prey she can spring at: a live defender (not a building, not one under camo).
func _pounceable(t) -> bool:
	return Combat.targetable(t) and t.team != team and not t.is_in_group("structures")


## The pounce (the Pounce clip): she crouches, springs at pounce_launch and flies onto `prey`, landing at
## pounce_land; it ends the sneak the moment she starts.
func start_pounce(prey: Node3D) -> void:
	end_sneak()
	_pounce_t = 0.0
	_pounce_prey = prey
	_pounce_landed = false
	_pounce_from = global_position
	_pounce_to = _pounce_landing(prey)
	_strike_t = -1.0
	velocity = Vector3.ZERO
	_agent.avoidance_enabled = false
	_clip_restart = true
	pounced.emit(prey)


## Where she lands, springing at `prey`: in front of it, a little short of its middle, on the ground.
func _pounce_landing(prey: Node3D) -> Vector3:
	var to := prey.global_position - global_position
	to.y = 0.0
	var at: Vector3 = prey.global_position - to.normalized() * stats.range * POUNCE_SHORT if to.length() > 0.1 else prey.global_position
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0, GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else at


func _pounce_tick(delta: float) -> void:
	_pounce_t += delta
	var launch: float = stats.pounce_launch
	var land: float = stats.pounce_land
	if _pounce_t < launch:
		# Crouched, eyes on the prey, gathering herself.
		velocity = Vector3.ZERO
		if Combat.is_valid_target(_pounce_prey):
			_face(_pounce_prey.global_position, delta)
			_pounce_to = _pounce_landing(_pounce_prey)
		_pounce_from = global_position
		_pounce_high = stats.pounce_height + stats.pounce_arc * _flat_to(_pounce_to)
		return
	if _pounce_t < land:
		var u := (_pounce_t - launch) / (land - launch)
		var p := _pounce_from.lerp(_pounce_to, u) + Vector3.UP * sin(u * PI) * _pounce_high
		velocity = (p - global_position) / delta
		global_position = p
		var d := _pounce_to - _pounce_from
		if Vector2(d.x, d.z).length() > 0.1:
			rotation.y = atan2(-d.x, -d.z)
		return
	if not _pounce_landed:
		_pounce_landed = true
		global_position = _pounce_to
		velocity = Vector3.ZERO
		_land_pounce()
	if _pounce_t >= stats.pounce_time:
		_pounce_t = -1.0
		_agent.avoidance_enabled = charge_gate == null
		_fire_cd = minf(_fire_cd, 0.05)  # straight into her claws


## She lands on her prey: it takes pounce_damage if it is still within her reach; dust either way.
func _land_pounce() -> void:
	for k in 4:
		SmokeCloud.wisp(self, global_position + Vector3(randf_range(-0.6, 0.6), 0.15, randf_range(-0.6, 0.6)), 1.1)
	if not Combat.targetable(_pounce_prey) or _range_to(_pounce_prey) > stats.range + POUNCE_SLACK:
		return
	_pounce_prey.take_damage(stats.pounce_damage, team)
	Combat.spawn_impact(self, Combat.aim_point(_pounce_prey), true)


func _flat_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Lioness active: the fire blast (LionessBlast), blast_duration seconds of flame from the barrels on
## her back. It gives a sneaking lioness away. False while on cooldown.
func start_blast() -> bool:
	if not blast_ready():
		return false
	blast_cd = stats.blast_cooldown
	end_sneak()
	_blast = LionessBlast.new()
	_blast.unit = self
	_blast.left = stats.blast_duration
	get_tree().current_scene.add_child(_blast)
	blasted.emit(_blast)
	return true


## Flamethrower nozzle k on her back (0 the lower barrel, 1 the upper), its Y axis out of the barrel: the
## model's nozzle bones, or a guess over her shoulders.
func nozzle(k: int) -> Transform3D:
	if _lion and _lion.posed():
		return _lion.nozzle(k)
	var at := global_position + Vector3.UP * (1.39 + 0.07 * k) - global_basis.z * (1.0 - 0.22 * k) + global_basis.x * 0.08 * k
	return Transform3D(Basis(global_basis.x, -global_basis.z, global_basis.y), at)


## Wolf Medic, every frame: healing, it heals the units it took; sweeping, it looks for its next mine, walks
## up to it and digs it out. True while the sweep moves it (or holds it digging): its order waits.
func _dog_tick(delta: float) -> bool:
	if heals():
		for u in patients:
			if can_heal(u):
				u.heal(stats.heal_rate * delta)
		return false
	if raiding or not sweeps():
		return false
	if sweep_mine != null and not (is_instance_valid(sweep_mine) and sweep_mine.is_laid()):
		_drop_mine()  # gone off under another unit, or taken up by its squad
	_sweep_cd -= delta
	if sweep_mine == null:
		if _sweep_cd <= 0.0 and order.type in ["idle", "attack_move"]:
			_sweep_cd = SWEEP_EVERY
			_take_mine(DogSweep.plan(self))
		if sweep_mine == null:
			# Attack-moving, it walks on only while its way keeps clear of the mines it knows are there; where
			# it doesn't, it waits for a way to one to open (the others clearing the ones in the way). A plain
			# move takes it on regardless.
			if order.type == "attack_move" and not _way_clear():
				_on_velocity_computed(Vector3.ZERO)
				return true
			return false
	if is_digging():
		_dig_tick(delta)
		return true
	if _sweep_cd <= 0.0:
		_sweep_cd = SWEEP_EVERY
		if DogSweep.blocked(self, _sweep_path, sweep_mine):
			# Another mine has landed on its way: it thinks again.
			_drop_mine()
			_take_mine(DogSweep.plan(self))
			if sweep_mine == null:
				return false
	_sweep_walk(delta)
	return true


## The next stretch of its order's way (WAY_AHEAD) keeps clear of every live mine within its sweep_range: no
## nearer to one than DogSweep.CLEAR, nor nearer than it stands now.
func _way_clear() -> bool:
	if _agent.is_navigation_finished():
		return true
	var to := _agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return true
	var ahead := global_position + to.normalized() * WAY_AHEAD
	for m in GroundMine.all:
		if not m.is_laid() or _flat_to(m.spot()) > stats.sweep_range:
			continue
		var d := Vector2(ahead.x - m.spot().x, ahead.z - m.spot().z).length()
		if d < DogSweep.CLEAR and d < _flat_to(m.spot()):
			return false
	return true


## While the sweep steers the dog it keeps to its own way, clear of the mines (avoidance would push it off
## it); otherwise it avoids the others like everyone. Turned back on, avoidance starts from a standstill: it
## carries on with the last velocity it was given until it gets a new one.
func _avoid(on: bool) -> void:
	if _agent.avoidance_enabled == on:
		return
	if on:
		_agent.velocity = Vector3.ZERO
	_agent.avoidance_enabled = on


func _take_mine(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	sweep_mine = plan.mine
	sweep_mine.sweeper = self
	_sweep_path = plan.path
	_sweep_spot = plan.spot


## Lets go of its mine (disarmed, gone, or called off). A mine half dug out stays as far dug as it got.
func _drop_mine() -> void:
	if sweep_mine != null and is_instance_valid(sweep_mine) and sweep_mine.sweeper == self:
		sweep_mine.sweeper = null
	var had := sweep_mine != null
	sweep_mine = null
	_sweep_path.clear()
	_sweep_spot = Vector3.INF
	_dig_t = -1.0
	if had and _agent and order.has("pos"):
		_agent.target_position = order.pos


## Walks its way to the dig spot (at sweep_speed), then turns to the mine and starts digging.
func _sweep_walk(delta: float) -> void:
	while not _sweep_path.is_empty() and _flat_to(_sweep_path[0]) < DogSweep.WAYPOINT:
		_sweep_path.pop_front()
	if _sweep_path.is_empty():
		_on_velocity_computed(Vector3.ZERO)
		_face(sweep_mine.spot(), delta)
		var to := sweep_mine.spot() - global_position
		var fwd := -global_basis.z
		if Vector2(to.x, to.z).normalized().dot(Vector2(fwd.x, fwd.z).normalized()) > 0.96:
			_dig_t = sweep_mine.dug * stats.disarm_time  # where a dog before it left off
			_spray_k = -1
		return
	var to := _sweep_path[0] - global_position
	to.y = 0.0
	var speed: float = stats.sweep_speed
	if _sweep_path.size() == 1:
		speed = minf(speed, maxf(to.length() * 2.5, 0.5))  # easing onto the spot
	_on_velocity_computed(to.normalized() * speed)


## Digging: the mine comes up out of the ground (GroundMine.dig) and the dirt flies back under the dog;
## after disarm_time seconds the mine is disarmed.
func _dig_tick(delta: float) -> void:
	_on_velocity_computed(Vector3.ZERO)
	_face(sweep_mine.spot(), delta)
	_dig_t += delta
	sweep_mine.dig(_dig_t / stats.disarm_time)
	_dig_spray()
	if _dig_t >= stats.disarm_time:
		var m := sweep_mine
		m.disarm()
		mines_disarmed += 1
		_drop_mine()
		_sweep_cd = 0.3
		mine_disarmed.emit(m)


## A throw of dirt each time a fore paw finishes its drag through the hole: dig_sprays a loop of the Dig
## clip, the first dig_spray_at of the way into it (tools/gltf/animate_dog.py).
func _dig_spray() -> void:
	var f := fmod(_dig_t, 1.0)
	if _anim and _anim.current_animation == stats.anim_dig and _anim.current_animation_length > 0.0:
		f = _anim.current_animation_position / _anim.current_animation_length
	var k := posmod(floori((f - stats.dig_spray_at) * stats.dig_sprays), stats.dig_sprays)
	if k == _spray_k:
		return
	_spray_k = k
	var fwd := -global_basis.z
	DogSweep.spray(self, global_position + fwd * 0.3 + Vector3.UP * 0.25, -fwd)


## Rhino and elephant passive: stay locked on one enemy flyer until it dies or leaves aa_range,
## then pick the nearest one in range.
func _aa_tick() -> void:
	_fire_cd = stats.fire_interval
	if not (Combat.is_valid_target(_aa_lock) and _in_aa_range(_aa_lock)):
		_aa_lock = null
		var best_d := INF
		for a in get_tree().get_nodes_in_group("air_units"):
			if a.team != team and a.is_alive() and _in_aa_range(a):
				var d := global_position.distance_to(a.global_position)
				if d < best_d:
					best_d = d
					_aa_lock = a
	if _turrets:
		_turrets.target = _aa_lock
		_turrets.radar_speed = 4.0 if _aa_lock else 0.9
		if _aa_lock:
			_fire_flak()
	elif _aa_lock:
		_aa_lock.take_damage(stats.aa_dps * stats.fire_interval, team)
		Combat.spawn_tracer(self, _eye(), Combat.aim_point(_aa_lock), AA_COLOR)


## Elephant: the flak cannons take turns, each firing only once it is on target.
func _fire_flak() -> void:
	for gun in [_next_gun, 1 - _next_gun]:
		if _turrets.aimed(gun):
			_next_gun = 1 - gun
			_turrets.kick(gun)
			Flak.fire(self, _turrets.muzzle(gun), _aa_lock, stats.aa_dps * stats.fire_interval, team)
			return


func _in_aa_range(a: Node3D) -> bool:
	var d := a.global_position - global_position
	return Vector2(d.x, d.z).length() <= stats.aa_range


## Rhino active: bomb a ground point for cluster_duration seconds. False while on cooldown.
func start_cluster(aim: Vector3) -> bool:
	if not cluster_ready() or not is_alive():
		return false
	cluster_cd = stats.cluster_cooldown
	_cluster_left = stats.cluster_duration
	_cluster_cd_shot = 0.0
	_cluster_aim = aim
	return true


func is_bombing() -> bool:
	return _cluster_left > 0.0


func _cluster_tick(delta: float) -> void:
	_cluster_left -= delta
	_cluster_cd_shot -= delta
	while _cluster_cd_shot <= 0.0 and _cluster_left > 0.0:
		_cluster_cd_shot += stats.cluster_interval
		var spread: float = stats.cluster_spread * sqrt(randf())
		var a := randf() * TAU
		var shell := Shell.new()
		shell.team = team
		shell.damage = stats.cluster_damage
		shell.radius = stats.cluster_splash
		shell.structure_mult = stats.structure_mult
		get_tree().current_scene.add_child(shell)
		var muzzle: Vector3 = global_position + Vector3.UP * (stats.height + 0.4) + global_basis.z * 0.6
		shell.launch(muzzle, _cluster_aim + Vector3(cos(a), 0.0, sin(a)) * spread)
		Combat.spawn_explosion(self, muzzle, 0.5)
		_recoil = 1.0


## Bison active: stand still, lay the gun on `aim` and fire one heavy shell at it, then carry on
## with the order. `aim` should be within bombard_range (RhinoAim.bombard). False while reloading.
func start_bombard(aim: Vector3) -> bool:
	if not bombard_ready():
		return false
	bombard_cd = stats.bombard_cooldown
	_bombard_aim = aim
	_bombard_left = stats.bombard_aim_time + stats.bombard_hold
	_bombard_fired = false
	return true


func _bombard_tick(delta: float) -> void:
	_bombard_left -= delta
	if not _bombard_fired and _bombard_left <= stats.bombard_hold:
		_bombard_fired = true
		_fire_bombard()


func _fire_bombard() -> void:
	var to := _bombard_aim - global_position
	var scatter: float = Vector2(to.x, to.z).length() * stats.bombard_spread * sqrt(randf())
	var a := randf() * TAU
	var shell := Shell.new()
	shell.team = team
	shell.damage = stats.bombard_damage
	shell.radius = stats.bombard_splash
	shell.structure_mult = stats.structure_mult
	shell.size = 0.4
	shell.trail = 0.04
	get_tree().current_scene.add_child(shell)
	var muzzle := muzzle_position()
	shell.launch(muzzle, _bombard_aim + Vector3(cos(a), 0.0, sin(a)) * scatter)
	Combat.spawn_explosion(self, muzzle, 1.6)
	SmokeCloud.wisp(self, muzzle, 2.0)
	_recoil = 1.0


## Tip of the barrel: the model's muzzle bone, or a guess in front of the unit.
func muzzle_position() -> Vector3:
	if _muzzle_skel:
		return _muzzle_skel.global_transform * _muzzle_skel.get_bone_global_pose(_muzzle_bone).origin
	return global_position - global_basis.z * 3.0 + Vector3.UP * stats.height


## Talon active: a strafe run from `a` to `b` (TalonRun), firing down the line as it dives along
## it. False while on cooldown or on another run.
func start_strafe(a: Vector3, b: Vector3) -> bool:
	if not strafe_ready():
		return false
	strafe_cd = stats.strafe_cooldown
	_flight.start(TalonRun.new(self, a, b, b - a, false, UnitTypes.FLY_HEIGHT + _flight.height))
	return true


## Talon active: a bomb strike, one bomb dropped on `spot` flying over it (TalonRun). False while
## on cooldown or on another run.
func start_bomb(spot: Vector3) -> bool:
	if not bomb_ready():
		return false
	bomb_cd = stats.bomb_cooldown
	_flight.start(TalonRun.new(self, spot, spot, TalonAim.bomb_dir(self, spot), true, UnitTypes.FLY_HEIGHT + _flight.height))
	return true


## One round of a strafe run, at `at` on the line (put down on what is there, coming down from
## `level`): from the talon's chest to there, or to whatever is in the way, and a small blast
## where it lands.
func strafe_shot(at: Vector3, level: float) -> void:
	var space := get_world_3d().direct_space_state
	var to := RhinoAim.settle(space, at, level)
	var muzzle := global_position + Vector3.UP * TalonFlight.BODY_HEIGHT - global_basis.z * 1.6
	var q := PhysicsRayQueryParameters3D.create(muzzle, to + (to - muzzle).normalized() * 0.5,
			GameConfig.LAYER_WORLD | GameConfig.LAYER_STRUCTURES, [get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		to = hit.position
	Combat.damage_area(self, to, stats.strafe_splash, stats.strafe_damage, team, stats.structure_mult)
	Combat.spawn_tracer(self, muzzle, to, Combat.ATTACKER_TRACER, 0.06)
	Combat.spawn_impact(self, to, false)
	_strafe_shots += 1
	if _strafe_shots % 3 == 0:
		Combat.spawn_explosion(self, to, 1.4)
	strafe_impact.emit(to)


## The bomb of a bomb strike, from the talon's belly onto `spot`.
func drop_bomb(spot: Vector3) -> void:
	var b := TalonBomb.new()
	b.team = team
	b.damage = stats.bomb_damage
	b.radius = stats.bomb_splash
	b.structure_mult = stats.bomb_structure_mult
	get_tree().current_scene.add_child(b)
	b.drop(global_position + Vector3.UP * (TalonFlight.BODY_HEIGHT - 0.6), spot)
	bomb_dropped.emit(b, spot)


## Hippo active: three smoke grenades into the cone toward `toward` (HippoSmoke). False while
## on cooldown.
func start_smoke(toward: Vector3) -> bool:
	if not smoke_ready() or not is_alive():
		return false
	smoke_cd = stats.smoke_cooldown
	var aim := HippoSmoke.solve(self, toward)
	var muzzle: Vector3 = global_position + Vector3.UP * (stats.height + 0.3)
	for p in aim.points:
		var g := SmokeGrenade.new()
		g.cloud_radius = stats.smoke_radius
		g.cloud_duration = stats.smoke_duration
		get_tree().current_scene.add_child(g)
		g.launch(muzzle, p, stats.smoke_height)
	Combat.spawn_explosion(self, muzzle, 0.5)
	_recoil = 1.0
	return true


## Elephant active: a salvo of homing missiles at one enemy flyer. The pods lift, then the
## missiles leave one tube at a time, alternating pods. False while reloading or out of range.
func start_missiles(t: Node3D) -> bool:
	if not missiles_ready() or not Combat.is_valid_target(t) or not in_missile_range(t):
		return false
	missile_cd = stats.missile_cooldown
	_salvo_target = t
	_salvo_target_id = t.get_instance_id()
	_salvo.clear()
	for k in stats.missile_count:
		_salvo.append(k)
	_salvo_cd = 0.0
	ElephantMissiles.commit(_salvo_target_id, salvo_damage())
	if _turrets:
		_turrets.raised = true
	return true


func _salvo_tick(delta: float) -> void:
	if not Combat.is_valid_target(_salvo_target):
		_end_salvo()  # already down: the rest stay in their tubes
		return
	if _turrets and not _turrets.pods_up():
		return
	_salvo_cd -= delta
	while _salvo_cd <= 0.0 and not _salvo.is_empty():
		_salvo_cd += stats.missile_interval
		_launch_missile(_salvo.pop_front())
	if _salvo.is_empty():
		_end_salvo()


func _launch_missile(k: int) -> void:
	var from: Vector3 = global_position + Vector3.UP * stats.height
	var dir := (Vector3.UP - global_basis.z).normalized()
	if _turrets and _turrets.tube_count() > 0:
		# Tubes are numbered pod by pod: alternate between the two pods.
		var half := maxi(_turrets.tube_count() / 2, 1)
		var tube := _turrets.tube(((k % 2) * half + k / 2) % _turrets.tube_count())
		from = tube.origin
		dir = tube.basis.y.normalized()
	var m := HomingMissile.new()
	m.team = team
	m.damage = stats.missile_damage
	m.on_spent = ElephantMissiles.release.bind(_salvo_target_id, stats.missile_damage)
	get_tree().current_scene.add_child(m)
	m.launch(from, dir, _salvo_target)
	SmokeCloud.wisp(self, from, 1.4)


## Missiles left in the tubes are no longer on their way; the pods come down.
func _end_salvo() -> void:
	if not _salvo.is_empty():
		ElephantMissiles.release(_salvo_target_id, _salvo.size() * stats.missile_damage)
		_salvo.clear()
	if _turrets:
		_turrets.raised = false


## Guns heat up while firing and cool at the same rate while resting. Past overheat_time they
## go silent for overheat_cooldown seconds and come back cold.
func _heat_tick(delta: float, firing: bool) -> void:
	if _overheat_left > 0.0:
		_overheat_left -= delta
		if _overheat_left <= 0.0:
			heat = 0.0
		# Smoke wisps off the gun mounts while they cool.
		_wisp_cd -= delta
		if _wisp_cd <= 0.0:
			_wisp_cd = 0.15
			var side: Vector3 = global_basis.x * stats.radius * 0.4 * (1.0 if randf() < 0.5 else -1.0)
			SmokeCloud.wisp(self, global_position + Vector3.UP * stats.height * 0.95 + side)
	elif firing:
		heat += delta
		if heat >= stats.overheat_time:
			_overheat_left = stats.overheat_cooldown
	else:
		heat = maxf(heat - delta, 0.0)


## Breaching Ram active: a surge of speed for ram_duration seconds. False while on cooldown.
func start_ram() -> bool:
	if not ram_ready():
		return false
	ram_cd = stats.ram_cooldown
	_ram_left = stats.ram_duration
	_trampled.clear()
	_agent.max_speed = _speed()
	return true


func end_ram() -> void:
	_ram_left = 0.0
	charge_gate = null
	if _agent:
		_agent.max_speed = _speed()


## Raiding ram: rams the soldier it hunts once it is close and in sight.
func _raid_ram() -> void:
	if not ram_ready() or not _is_soldier(target) or not _sees_target:
		return
	var to := target.global_position - global_position
	if absf(to.y) < stats.height and to.length() <= RAID_RAM_REACH:
		start_ram()


func _is_soldier(t: Node3D) -> bool:
	return Combat.is_valid_target(t) and t.get("station_kind") == "soldier"


## Charge `gate` from `slot` across its doorway (RamCharge.allocate).
func charge(gate: Structure, slot: int) -> void:
	charge_gate = gate
	charge_slot = slot
	_charge_pos = RamCharge.slot_position(gate, slot, stats.ram_gate_slots)


func _ram_tick(delta: float) -> void:
	_ram_left -= delta
	if _ram_left <= 0.0:
		end_ram()
		return
	if charge_gate:
		if not RamCharge.is_gate(charge_gate):
			charge_gate = null  # already down: keep running
		elif _range_to(charge_gate) <= RamCharge.REACH:
			_slam()
			return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < stats.speed:
		return  # only a running ram knocks anyone over
	_trample(flat.normalized())
	_dust_cd -= delta
	if _dust_cd <= 0.0:
		_dust_cd = 0.08
		SmokeCloud.wisp(self, global_position + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.4, 0.4)), 0.9)


## Enemy soldiers in the ram's way lose health and are tossed out of it, off to the side they
## stood on.
func _trample(fwd: Vector3) -> void:
	var now := Time.get_ticks_msec()
	for d in get_tree().get_nodes_in_group("defender_targets"):
		if d.team == team or not d.is_alive() or not d.has_method("toss"):
			continue
		var id: int = d.get_instance_id()
		if now - _trampled.get(id, -100000) < TRAMPLE_REPEAT * 1000.0:
			continue
		var to: Vector3 = d.global_position - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if absf(to.y) > stats.height or flat.length() > stats.radius + TRAMPLE_REACH or flat.dot(fwd) < 0.0:
			continue
		_trampled[id] = now
		# Out of the way, to the side it stood on (either side if dead ahead).
		var side := flat - fwd * flat.dot(fwd)
		if side.length() < 0.05:
			side = fwd.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		var away := (fwd * 0.6 + side.normalized()).normalized()
		d.take_damage(stats.ram_trample_damage, team)
		d.toss(away * stats.ram_toss + Vector3.UP * stats.ram_toss * 0.6)
		Combat.spawn_impact(self, Combat.aim_point(d), true)
		_butt = 0.6


## The one hit a charge buys: the ram is spent, and the sheep goes back to its shotgun.
func _slam() -> void:
	var gate := charge_gate
	var hit_at: Vector3 = global_position + (gate.global_position - global_position).normalized() * (stats.radius + 0.4) + Vector3.UP * stats.height * 0.5
	gate.take_damage(stats.ram_gate_damage, team)
	Combat.spawn_explosion(self, hit_at, 2.5)
	end_ram()
	_butt = 1.0
	_fire_cd = maxf(_fire_cd, 0.6)


# ---------------------------------------------------------------- Serpent Sniper

## Every physics frame: up its tree or round its bush the skill runs; come up to the tree or the bush it was
## sent to, it turns to face it and starts; done with one, it stands while its rig blends back into its clips.
## True while that holds it (no other movement this frame).
func _serpent_tick(delta: float) -> bool:
	if _nest != null:
		_nest_tick(delta)
		return true
	if _trap != null:
		_trap_tick(delta)
		return true
	if _serpent.weight > 0.0:
		_serpent.weight = move_toward(_serpent.weight, 0.0, delta / SERPENT_BLEND)
		_serpent.rifle_w = 0.0
		_on_velocity_computed(Vector3.ZERO)
		return true
	if order.type not in ["nest", "trap"]:
		return false
	var spot = order.tree if order.type == "nest" else order.bush
	if not is_instance_valid(spot) or not (spot.nest_free(self) if order.type == "nest" else spot.trap_free(self)):
		set_order({"type": "idle"})  # burnt down, or another snake's
		return false
	var to: Vector3 = order.pos - global_position
	var near := Vector2(to.x, to.z).length() < SKILL_REACH or (_agent.is_navigation_finished() and _moving_for > 0.5 and Vector2(to.x, to.z).length() < 4.0)
	if not near:
		return false
	var centre: Vector3 = spot.trunk_centre() if order.type == "nest" else spot.global_position
	_on_velocity_computed(Vector3.ZERO)
	_face(centre, delta)
	var fwd := -global_basis.z
	var want := Vector3(centre.x - global_position.x, 0.0, centre.z - global_position.z).normalized()
	if Vector2(fwd.x, fwd.z).normalized().dot(Vector2(want.x, want.z)) > cos(FACE_TO) and _serpent.posed():
		if order.type == "nest":
			_begin_nest(spot)
		else:
			_begin_trap(spot)
	return true


## Starts up `tree` from where it lies (its body as it lies now: SerpentRig.body_path), winding round the trunk
## one way or the other.
func _begin_nest(tree: ForestTree) -> void:
	tree.nest_by = self
	_nest = SerpentNest.new(tree, _serpent.body_path(), global_position.y, 1.0 if unit_id % 2 == 0 else -1.0)
	_skill_start()


func _begin_trap(bush: Bush) -> void:
	bush.coiled_by = self
	_trap = SerpentTrap.new(bush, _serpent.body_path(), global_position.y)
	_serpent.rifle_down = SerpentTrap.rifle_rest(_serpent.rifle(), bush, global_position.y)
	_skill_start()


func _skill_start() -> void:
	_skill_xf = global_transform
	_skill_p = 0.0
	_skill_dir = 1
	_after = null
	_focus = null
	_squeeze_t = -1.0
	_letting_go = false
	_engaged = false
	target = null
	velocity = Vector3.ZERO
	_agent.avoidance_enabled = false


## Climbing (nest_time up, nest_time down), or perched: shooting from the tree, the nest turning round the trunk
## to aim. A tree that catches fire, it climbs down.
func _nest_tick(delta: float) -> void:
	velocity = Vector3.ZERO
	_engaged = false
	if not _nest.tree.is_standing() and _skill_dir >= 0:
		_skill_dir = -1
	_skill_p = clampf(_skill_p + _skill_dir * delta / stats.nest_time, 0.0, 1.0)
	if _skill_p >= 1.0 and _skill_dir > 0:
		_skill_dir = 0
		rotation.y = _nest.heading()
		nested.emit(_nest.tree)
	if is_perched():
		_perch_aim(delta)
	var pose := _nest.pose(_skill_p)
	_serpent.lay(pose[0], pose[1], pose[2])
	_serpent.weight = move_toward(_serpent.weight, 1.0, delta / SERPENT_BLEND)
	global_position = _nest.anchor(pose[2])
	if _skill_p <= 0.0 and _skill_dir < 0:
		var turn := Basis(Vector3.UP, _nest.yaw)
		var axis := Vector3(_nest.axis.x, _skill_xf.origin.y, _nest.axis.z)
		global_transform = Transform3D(turn * _skill_xf.basis, axis + turn * (_skill_xf.origin - axis))
		if _nest.tree.nest_by == self:
			_nest.tree.nest_by = null
		_nest = null
		_skill_done()


## Perched: it turns round its trunk onto what it shoots at (or toward the stronghold), tips its front onto it
## and fires.
func _perch_aim(delta: float) -> void:
	var shoot := target if Combat.targetable(target) and _in_range(target) and _sees_target else null
	var tip := 0.0
	if shoot:
		_engaged = true
		var d := Combat.aim_point(shoot) - _eye()
		rotation.y = rotate_toward(rotation.y, atan2(-d.x, -d.z), NEST_TURN * delta)
		tip = atan2(d.y, Vector2(d.x, d.z).length())
		if _fire_cd <= 0.0 and absf(angle_difference(rotation.y, atan2(-d.x, -d.z))) < 0.05:
			_fire_at(shoot)
	_nest.aim(rotation.y, move_toward(_nest.pitch, tip, TIP_RATE * delta))


## Coiling round its bush (trap_time in, trap_time out), coiled and lying in wait, or striking.
func _trap_tick(delta: float) -> void:
	velocity = Vector3.ZERO
	_engaged = false
	_serpent.weight = move_toward(_serpent.weight, 1.0, delta / SERPENT_BLEND)
	if _squeeze_t >= 0.0:
		_squeeze_tick(delta)
		return
	_skill_p = clampf(_skill_p + _skill_dir * delta / stats.trap_time, 0.0, 1.0)
	# The rifle goes into the bush as it slides out from under it (and up onto its back as it slides back).
	var r := clampf(_skill_p / 0.15, 0.0, 1.0)
	_serpent.rifle_w = r * r * (3.0 - 2.0 * r)
	if _skill_p >= 1.0 and _skill_dir > 0:
		_skill_dir = 0
		_sneak_look()  # this frame, not the next
		coiled.emit(_trap.bush)
	var pose := _trap.pose(_skill_p)
	_serpent.lay(pose[0], pose[1])
	var e := _skill_p * _skill_p * (3.0 - 2.0 * _skill_p)
	global_position = _skill_xf.origin.lerp(Vector3(_trap.centre.x, _skill_xf.origin.y, _trap.centre.z), e)
	if is_coiled():
		_trap_cd -= delta
		if _trap_cd <= 0.0:
			_trap_cd = TRAP_EVERY
			var p := SerpentTrap.prey_near(self, _trap.bush, stats.trap_reach)
			if p:
				_strike(p)
	if _skill_p <= 0.0 and _skill_dir < 0:
		global_transform = _skill_xf
		if _trap.bush.coiled_by == self:
			_trap.bush.coiled_by = null
		_trap = null
		_skill_done()


## It strikes `p` and holds it: squeeze_time seconds to squeeze it to death.
func _strike(p: Node3D) -> void:
	_trap.strike(p)
	SerpentTrap.hold(p, self)
	_squeeze_t = 0.0
	_squeeze_hp = p.hp
	_letting_go = false
	_strike_way = _trap.strike_way(0.0)
	_strike_s = _strike_way[1]
	struck.emit(p)
	_sneak_look()  # it shows the moment it strikes


## Squeezing: the prey's health runs down steadily from what it had when struck to nothing at squeeze_time.
## Dead (or gone), it lets go and slides back round its bush.
func _squeeze_tick(delta: float) -> void:
	var prey_node := _trap.prey
	if _letting_go:
		_strike_s = move_toward(_strike_s, _strike_way[1], SerpentTrap.LET_GO * delta)
		_serpent.lay(_strike_way[0], _strike_s)
		var home := Vector3(_trap.centre.x, global_position.y, _trap.centre.z)
		global_position = global_position.move_toward(home, SerpentTrap.LET_GO * delta)
		if _strike_s <= _strike_way[1] + 0.001:
			_squeeze_t = -1.0
			_letting_go = false
			_trap.prey = null
			global_position = home
			if _skill_dir == 0:
				_sneak_look()
				coiled.emit(_trap.bush)
		return
	_squeeze_t += delta
	if Combat.is_valid_target(prey_node):
		if _squeeze_t >= stats.squeeze_time:
			prey_node.take_damage(prey_node.hp + 1000.0, team)
		else:
			var want: float = _squeeze_hp * (1.0 - _squeeze_t / stats.squeeze_time)
			if prey_node.hp > want:
				prey_node.take_damage(prey_node.hp - want, team)
	if not Combat.is_valid_target(prey_node):
		SerpentTrap.release(prey_node)
		if prey_node != null and is_instance_valid(prey_node):
			crushed.emit(prey_node)
		_letting_go = true
		return
	_strike_way = _trap.strike_way(SerpentTrap.squeeze_at(_squeeze_t))
	_strike_s = SerpentTrap.strike_reach(_squeeze_t, _strike_way[1], _strike_way[2], _strike_way[3])
	_serpent.lay(_strike_way[0], _strike_s)
	# It stands where its coils are, at the prey's side toward the bush (what shoots at it aims there).
	var side := Vector3(_trap.centre.x - _trap.prey_at.x, 0.0, _trap.centre.z - _trap.prey_at.z)
	side = side.normalized() if side.length() > 0.05 else Vector3.FORWARD
	var at := Vector3(_trap.prey_at.x, global_position.y, _trap.prey_at.z) + side * 0.6
	global_position = global_position.move_toward(at, 12.0 * delta)


## Down from its tree or out of its bush: back on its clips (the rig blends out), and on with the order it was
## given meanwhile.
func _skill_done() -> void:
	_skill_p = 0.0
	_skill_dir = 0
	_focus = null
	_serpent.rifle_w = 0.0
	_agent.avoidance_enabled = charge_gate == null
	var next = _after
	_after = null
	order = {"type": "idle"}
	set_order(next if next != null else {"type": "idle"})


## Dead up its tree or round its bush: the prey goes free, the tree or the bush is free again, the body drops.
## True if its rig takes the fall (the body laid along a skill's way).
func _serpent_die() -> bool:
	if _trap != null:
		SerpentTrap.release(_trap.prey)
		if _trap.bush.coiled_by == self:
			_trap.bush.coiled_by = null
	if _nest != null and _nest.tree.nest_by == self:
		_nest.tree.nest_by = null
	var tree = order.get("tree")
	if tree != null and is_instance_valid(tree) and tree.nest_by == self:
		tree.nest_by = null
	var bush = order.get("bush")
	if bush != null and is_instance_valid(bush) and bush.coiled_by == self:
		bush.coiled_by = null
	var laid := _serpent.weight > 0.0
	if laid:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 40.0, GameConfig.LAYER_WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		_serpent.die(hit.position.y if not hit.is_empty() else _skill_xf.origin.y)
	_nest = null
	_trap = null
	_squeeze_t = -1.0
	return laid


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		if not is_on_floor():
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y -= _gravity * delta
			move_and_slide()
		return
	for id in _tags.keys():
		_tags[id] -= delta
		if _tags[id] <= 0.0:
			_tags.erase(id)
	_fire_cd -= delta
	_retarget_cd -= delta
	if _retarget_cd <= 0.0:
		_retarget_cd = 0.3
		_update_target()
		# Inside, a raider's quarry is often round a corner or a floor up: it goes after it rather than
		# shooting the wall in between.
		_sees_target = not (Combat.is_valid_target(target) and (raiding or target.get("buried"))) or _can_see(target)
		if stats.has("forest_speed"):
			_in_forest = LevelBuilder.in_forest(global_position)
			_agent.max_speed = _speed()
	if not _route.is_empty():
		_follow_route(delta)
		return

	var move_to = null
	# Skills cool down faster while a kangaroo resupplies the unit.
	var cool := delta / (1.0 - resupply)
	if has_cluster_bomb():
		cluster_cd = maxf(cluster_cd - cool, 0.0)
		if _cluster_left > 0.0:
			_cluster_tick(delta)
	if has_smoke():
		smoke_cd = maxf(smoke_cd - cool, 0.0)
	if has_missiles():
		missile_cd = maxf(missile_cd - cool, 0.0)
		if not _salvo.is_empty():
			_salvo_tick(delta)
	if has_ram():
		ram_cd = maxf(ram_cd - cool, 0.0)
		if _ram_left > 0.0:
			_ram_tick(delta)
	if has_strafe():
		strafe_cd = maxf(strafe_cd - cool, 0.0)
	if has_bomb():
		bomb_cd = maxf(bomb_cd - cool, 0.0)
	if has_bombard():
		bombard_cd = maxf(bombard_cd - cool, 0.0)
		if _bombard_left > 0.0:
			_bombard_tick(delta)
	if has_flash():
		flash_cd = maxf(flash_cd - cool, 0.0)
		if is_throwing():
			_flash_tick(delta)
	if has_ping():
		ping_cd = maxf(ping_cd - cool, 0.0)
		if is_pinging():
			_ping_tick(delta)
	_moving_for += delta
	if stats.has("gallop_after") and _moving_for >= stats.gallop_after and _moving_for - delta < stats.gallop_after:
		_agent.max_speed = _speed()  # the walk is over: she may gallop
	if has_sneak():
		sneak_cd = maxf(sneak_cd - cool, 0.0)
		if _sneak_left > 0.0:
			_sneak_left -= delta
			if _sneak_left <= 0.0:
				_sneak_left = 0.0
				_agent.max_speed = _speed()
	if has_blast():
		blast_cd = maxf(blast_cd - cool, 0.0)
	if has_dog_modes():
		var swept := _dog_tick(delta)
		_avoid(not swept and charge_gate == null)
		if swept:
			return  # sweeping: walking up to its mine, digging it out, or waiting for a way in
	if _serpent and _serpent_tick(delta):
		return  # up its tree, round its bush, or turning to start on one
	if is_pouncing():
		_pounce_tick(delta)  # she flies on her own: no orders, no avoidance
		return
	if is_striking():
		_strike_tick(delta)
	if _burst_left > 0:
		_burst_tick(delta)
	if stats.has("aa_dps") and _fire_cd <= 0.0:
		_aa_tick()
	if raiding and has_ram():
		_raid_ram()
	if raiding and has_flash():
		_raid_flash()
	if has_sneak():
		_maybe_pounce()
		if is_pouncing():
			return
	# A charging ram doesn't stop to shoot: it runs for its slot in front of the gate, or, raiding,
	# into the soldier it hunts. A kangaroo throwing a grenade holds its fire.
	var running_over := raiding and is_ramming() and _is_soldier(target)
	var lined := false
	var engaged := charge_gate == null and not running_over and not is_throwing() and not is_pinging() \
			and Combat.targetable(target) and _in_range(target) and _sees_target
	_engaged = engaged
	if stats.has("overheat_time"):
		_heat_tick(delta, engaged and not is_overheated())
	if is_bombarding():
		_face(_bombard_aim, delta)  # stands still while it lays the gun and fires
	elif is_throwing():
		_face(_flash_aim, delta)  # stands up on the spot and throws
	elif is_pinging():
		pass  # stands on the spot while the dish sweeps
	elif engaged:
		_face(target.global_position, delta)
		if _fire_cd <= 0.0 and not is_overheated():
			_fire_at(target)
	elif charge_gate:
		move_to = _charge_pos
	elif order.has("line"):
		lined = true  # marching in a line: _line_step
	elif order.type in ["move", "attack_move", "nest", "trap"]:
		move_to = order.pos
	elif running_over:
		move_to = target.global_position
	elif (order.type == "attack" or order.type == "raid") and Combat.is_valid_target(target):
		move_to = _approach(target)
	elif order.has("face"):
		# A line that has arrived: each lioness stands facing the way it went.
		rotation.y = lerp_angle(rotation.y, atan2(-order.face.x, -order.face.z), minf(5.0 * delta, 1.0))

	if is_flying():
		_fly(move_to, delta)
		return

	_desired_velocity = Vector3.ZERO
	if lined:
		_line_step()
	elif move_to != null:
		if _agent.target_position.distance_to(move_to) > 1.5:
			_agent.target_position = move_to
		if _agent.is_navigation_finished():
			if order.type not in ["attack", "raid", "nest", "trap"]:
				order = {"type": "idle"}
			elif role == "melee" or charge_gate or running_over:
				# Close the last stretch to the target straight on.
				var dir: Vector3 = move_to - global_position
				dir.y = 0.0
				if dir.length_squared() > 0.01:
					_desired_velocity = dir.normalized() * _speed()
		else:
			var next := _agent.get_next_path_position()
			if not _route.is_empty():
				return  # just reached a link (_on_link_reached)
			var dir := next - global_position
			dir.y = 0.0
			if dir.length_squared() > 0.0001:
				_desired_velocity = dir.normalized() * _speed()
	if _agent.avoidance_enabled:
		_agent.velocity = _desired_velocity
	else:
		_on_velocity_computed(_desired_velocity)  # charging: no avoidance pass to wait for


## Where to walk to reach `t`. A gate from outside its doorway (its middle is closest to the
## tunnel's navmesh). A post on the decks or roofs from the ground in front of it, unless this
## is an infiltrator that can get up there: a raider, or anyone while a gate is down.
func _approach(t: Node3D) -> Vector3:
	if not t.has_method("get_approach_point"):
		return t.global_position
	if t.get("station_kind") != null and (raiding or (fits_inside() and _nearest_breach() != null)):
		return t.global_position
	return t.get_approach_point()


func _speed() -> float:
	var s: float = stats.speed * (stats.forest_speed if _in_forest else 1.0) * (stats.ram_speed if _ram_left > 0.0 else 1.0)
	if stats.has("gallop_after") and _moving_for < stats.gallop_after and order.type in ["move", "attack_move"]:
		s = minf(s, stats.walk_speed)  # sent somewhere, she walks a while before she gallops
	return minf(s, stats.sneak_speed) if is_sneaking() else s


## In a line (LionessLine): she makes for her spot in it as it marches, at its pace and faster where she
## is behind; once it has arrived she stands on her spot, facing the way it went.
func _line_step() -> void:
	var line: LionessLine = order.line
	# The spots keep the line apart: avoidance would only hold them back from their places, or push them
	# off them once they stand in line. The next order (set_order) turns it back on.
	_agent.avoidance_enabled = false
	if line.arrived() and _flat_to(line.final_spot(self)) < LionessLine.ON_SPOT:
		order = {"type": "idle", "face": line.dir}
		return
	var spot := line.spot(self)
	var off := _flat_to(spot)
	if _agent.target_position.distance_to(spot) > 0.4:
		_agent.target_position = spot
	var next := spot
	if not _agent.is_navigation_finished():
		next = _agent.get_next_path_position()
		if not _route.is_empty():
			return  # just reached a link (_on_link_reached)
	var dir := next - global_position
	dir.y = 0.0
	# Ahead of her spot she waits (stepping into her file) until the line comes up to her.
	var waiting := line.own(self) > line.progress + LionessLine.IN_STEP
	if (off > LionessLine.IN_STEP or line.arrived()) and dir.length_squared() > 0.0001:
		_desired_velocity = dir.normalized() * line.speed_for(self, off)
	elif not line.arrived() and not waiting:
		_desired_velocity = line.dir * line.pace  # in step: she marches with the line


## Infiltrators cross the stronghold's navigation links along the route each one carries:
## climbing a stair shaft or ladder, or slipping in through a broken gate.
func _on_link_reached(details: Dictionary) -> void:
	var link := details.get("owner") as NavigationLink3D
	if link == null or not link.has_meta("route") or not _route.is_empty():
		return
	var route: Array[Vector3] = link.get_meta("route").duplicate()
	var entry: Vector3 = details.link_entry_position
	var forward := entry.distance_to(route[0]) <= entry.distance_to(route[-1])
	if not forward:
		route.reverse()
	_route = route
	_route_breach_in = forward and link.has_meta("breach")


## Moves straight from point to point, through the stair steps and ladder rungs: no collisions.
func _follow_route(delta: float) -> void:
	var to := _route[0] - global_position
	var climbing := absf(to.y) > Vector2(to.x, to.z).length()
	var speed: float = stats.get("climb_speed", stats.speed * 0.5) if climbing else stats.speed * 0.8
	var step := speed * delta
	if to.length() <= step:
		global_position = _route.pop_front()
		if _route.is_empty():
			velocity = Vector3.ZERO
			if _route_breach_in and stats.get("raider", false):
				_start_raid()
		return
	velocity = to.normalized() * speed
	global_position += velocity * delta
	if not climbing:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(10.0 * delta, 1.0))


## Flyers never stop in the air (TalonFlight): they fly to where they are going and circle there
## (on an attack run, the run steers them instead).
func _fly(move_to, delta: float) -> void:
	var round_at := _flight.ring_round(move_to if move_to != null else _circle_at)
	if _flight.fly(round_at, delta) and move_to != null and order.type != "attack":
		order = {"type": "idle"}
		_circle_at = move_to


func _on_velocity_computed(safe: Vector3) -> void:
	if hp <= 0.0 or is_flying() or not _route.is_empty():
		return
	var dt := get_physics_process_delta_time()
	if stats.get("steer", false):
		_steer(safe, dt)
	else:
		velocity.x = safe.x
		velocity.z = safe.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * dt
	move_and_slide()
	if fits_inside() and is_on_wall() and Vector2(safe.x, safe.z).length() > 0.5:
		_step_up(Vector3(safe.x, 0.0, safe.z).normalized() * 0.3)
	var flat := Vector2(velocity.x, velocity.z)
	if not stats.get("steer", false) and flat.length() > 0.3 and not (Combat.is_valid_target(target) and _in_range(target)):
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 8.0 * dt)


## move_and_slide stops dead at a ledge: hop onto it if it is low enough and there is room.
func _step_up(motion: Vector3) -> void:
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up) or test_move(global_transform.translated(up), motion):
		return
	global_position += up + motion


## Vehicle-style movement (snakes): turn toward the wanted direction at a limited rate and
## only ever move the way the head points, slowing down while the turn is sharp.
func _steer(want: Vector3, dt: float) -> void:
	var flat := Vector2(want.x, want.z)
	if flat.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	rotation.y = rotate_toward(rotation.y, atan2(-want.x, -want.z), stats.get("turn_rate", 3.0) * dt)
	var fwd := Vector2(-sin(rotation.y), -cos(rotation.y))
	var along := maxf(fwd.dot(flat.normalized()), 0.0)
	var spd := flat.length() * along * along
	velocity.x = fwd.x * spd
	velocity.z = fwd.y * spd


func _face(point: Vector3, delta: float) -> void:
	var d := point - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), (3.0 if stats.radius > 1.0 else 10.0) * delta)


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	# Procedural animation until models are rigged.
	var spd := velocity.length() if not _route.is_empty() else Vector2(velocity.x, velocity.z).length()
	var moving := spd > 0.3
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_butt = maxf(_butt - delta * 3.0, 0.0)
	if moving:
		_anim_t += delta * spd
	if _anim:
		# Rigged model: play its clips, matching the move cycle to ground speed (within anim_scale).
		# A kangaroo throwing a flash grenade plays its throw, a giraffe pinging its ping; a lioness
		# runs above run_above (anim_run), stalks while she sneaks, pounces and strikes; a dog digs.
		var clip: String = stats.anim_move if moving else stats.anim_idle
		var ref: float = stats.get("anim_ref_speed", 1.0)
		var rate: Array = stats.get("anim_scale", [0.6, 2.0])
		if moving and is_sneaking() and stats.has("anim_sneak"):
			clip = stats.anim_sneak
			ref = stats.anim_sneak_speed
		elif moving and stats.has("anim_run") and spd > stats.run_above:
			clip = stats.anim_run
			ref = stats.anim_run_speed
			rate = stats.run_scale
		var skill := is_throwing() or is_pinging() or is_pouncing() or is_striking() or is_digging()
		if is_throwing():
			clip = "Throw"
		elif is_pinging():
			clip = "Ping"
		elif is_pouncing():
			clip = "Pounce"
		elif is_striking():
			clip = stats.anim_strike
		elif is_digging():
			clip = stats.anim_dig
		if _anim.current_animation != clip:
			_anim.play(clip, 0.15 if skill else 0.25)
		elif _clip_restart:
			_anim.seek(0.0, true)  # the next blow, from the start of its clip
		_clip_restart = false
		_anim.speed_scale = clampf(spd / ref, rate[0], 3.0 if is_ramming() else rate[1]) \
				if moving and not skill else 1.0
	if has_sneak() or has_trap():
		_sneak_look()
	if has_dog_modes():
		_heal_beams()
	if _rig:
		_pose_rig(delta)
	match stats.anim:
		"stomp":
			_model.position.y = absf(sin(_anim_t * 1.6)) * 0.06 if moving else lerpf(_model.position.y, 0.0, delta * 5.0)
			_model.rotation.z = sin(_anim_t * 1.6) * 0.025 if moving else lerpf(_model.rotation.z, 0.0, delta * 5.0)
		"flight":
			_flight.animate(_model, delta)
		"roll":
			_model.position.y = randf_range(0.0, 0.02) if moving else 0.0
		"rigged":
			if role == "melee" and not stats.has("anim_strike"):
				_model.position.z = -_recoil * 0.35  # lunge into the blow
			elif has_ram():
				_model.position.z = -sin(_butt * PI) * 0.5  # head-butt
			elif has_bombard():
				_model.position.z = _recoil * 0.25  # the gun kicks the pair back
		_:
			_model.position.y = absf(sin(_anim_t * 2.2)) * 0.08 if moving else lerpf(_model.position.y, 0.0, delta * 8.0)
			_model.rotation.z = sin(_anim_t * 2.2) * 0.06 if moving else lerpf(_model.rotation.z, 0.0, delta * 8.0)
	if stats.anim not in ["flight", "rigged"]:
		_model.rotation.x = _recoil * (0.08 if stats.radius < 1.0 else 0.015)
	var cam := get_viewport().get_camera_3d()
	if _hp_bar.visible:
		_hp_bar.global_position = global_position + Vector3.UP * (stats.height + 0.5)
		if cam:
			_hp_bar.global_basis = cam.global_basis
	# The icons over it keep their size on screen whatever the camera's field of view (a Sniper's scope
	# magnifies up to 12x): their sizes are for the RTS view's.
	var icon := tan(deg_to_rad(cam.fov) * 0.5) / ICON_FOV_TAN if cam else 1.0
	_tag_icon.pixel_size = TAG_ICON_SIZE * icon
	_supply_icon.pixel_size = SUPPLY_ICON_SIZE * icon
	_heal_icon.pixel_size = HEAL_ICON_SIZE * icon
	if _bush:
		_bush.pixel_size = BUSH_ICON_SIZE * icon
	if _nest_icon:
		# Perched in its nest: a tree-and-rifle icon over it, on the attacker's side only.
		_nest_icon.pixel_size = NEST_ICON_SIZE * icon
		_nest_icon.visible = is_perched() and GameConfig.player_side == GameConfig.PlayerSide.ATTACKER
		if _nest_icon.visible:
			_nest_icon.global_position = global_position + Vector3.UP * (stats.height + 1.3)
	# Tagged by a Sniper: the aim icon over it, blinking as the last tag runs out.
	_tag_icon.visible = is_tagged()
	if _tag_icon.visible:
		var left: float = _tags.values().max()
		_tag_icon.global_position = global_position + Vector3.UP * (stats.height + 1.0)
		_tag_icon.modulate.a = 1.0 if left > TAG_BLINK or fmod(left, 0.5) > 0.2 else 0.25
	# Resupplied by a kangaroo: an ammo box floats over it (over a sneaking lioness's bush, or the aim icon).
	var bush := (_bush != null and _bush.visible) or (_nest_icon != null and _nest_icon.visible)
	_supply_icon.visible = resupply > 0.0
	if _supply_icon.visible:
		_supply_icon.global_position = global_position + Vector3.UP * (stats.height + 1.0 + (0.95 if bush or _tag_icon.visible else 0.0) + 0.08 * sin(Time.get_ticks_msec() * 0.004))
	if _bush != null and _bush.visible:
		_bush.global_position = global_position + Vector3.UP * (stats.height + 1.3)
	# Healed by a dog: a medic's cross over it (over the other icons).
	_heal_icon.visible = medic != null and is_instance_valid(medic) and medic.heals()
	if _heal_icon.visible:
		var under := (0.95 if bush or _tag_icon.visible else 0.0) + (0.95 if _supply_icon.visible else 0.0)
		_heal_icon.global_position = global_position + Vector3.UP * (stats.height + 1.0 + under + 0.08 * sin(Time.get_ticks_msec() * 0.004 + 1.6))


## The sneak as each side sees it. The defending player sees her see-through (sneak_alpha opaque: the
## see-through materials, drawn after the depth so she reads as one ghostly shape), with no shadow and
## no health bar; the attacking player sees her as ever, with a bush over her. Follows
## GameConfig.player_side as it is now (the showcases switch sides). A Serpent Sniper coiled round its bush
## the same, a grass-and-snake icon over it instead of the bush.
func _sneak_look() -> void:
	var want := 0
	if (is_sneaking() or is_coiled()) and is_alive():
		want = 1 if GameConfig.player_side == GameConfig.PlayerSide.DEFENDER else 2
	if want == _look:
		return
	_look = want
	for g in _ghosts:
		var mi: MeshInstance3D = g[0]
		mi.set_surface_override_material(g[1], g[2] if want == 1 else null)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if want == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_bush.visible = want == 2
	_update_hp_bar()


## True while the defending player sees her see-through (sneaking).
func ghosted() -> bool:
	return _look == 1


## A healing dog: a beam from the medic pack on its back to each unit it heals.
func _heal_beams() -> void:
	var n := 0
	if heals():
		var from: Vector3 = global_position + Vector3.UP * stats.height * 0.62
		for u in patients:
			if n >= _beams.size() or not can_heal(u):
				continue
			var d: Vector3 = u.get_aim_point() - from
			var x := d.cross(Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT).normalized() * 0.045
			var b := _beams[n]
			b.global_transform = Transform3D(Basis(x, d, x.cross(d.normalized())), from + d * 0.5)
			b.transparency = 0.3 + 0.25 * sin(Time.get_ticks_msec() * 0.008 + n * 2.0)
			b.visible = true
			n += 1
	for k in range(n, _beams.size()):
		_beams[k].visible = false


## A selected dog's ring: how far it heals, or sniffs out mines (its mode's).
func _dog_rings() -> void:
	if _heal_ring:
		_heal_ring.visible = selected and heals()
		_sweep_ring.visible = selected and sweeps()


## Kangaroo: rears its chest up onto what it shoots at, so the SMGs strapped to its sides point at it,
## and holds the grenade in its paw while it winds up to throw.
func _pose_rig(delta: float) -> void:
	var want := 0.0
	if _engaged and Combat.is_valid_target(target):
		var d := Combat.aim_point(target) - _eye()
		want = clampf(atan2(d.y, Vector2(d.x, d.z).length()) + KangarooRig.GUN_DROOP, 0.0, KangarooRig.MAX_PITCH)
	_rig.pitch = lerpf(_rig.pitch, want, minf(delta * 6.0, 1.0))
	_held.visible = is_throwing() and not _flash_thrown and _flash_t > FLASH_IN_PAW
	if _held.visible:
		_held.global_position = grenade_position()


# ---------------------------------------------------------------- visuals

func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	if not _scenes.has(stats.model):
		_scenes[stats.model] = load(stats.model)
	var m := (_scenes[stats.model] as PackedScene).instantiate() as Node3D
	m.rotation.y = PI  # model front is +Z, units look down -Z
	_model.add_child(m)
	var players := m.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty() and stats.has("anim_move"):
		_anim = players[0]
		var loops := [stats.anim_move, stats.anim_idle]
		for k in ["anim_run", "anim_sneak", "anim_dig"]:
			if stats.has(k):
				loops.append(stats[k])
		for clip in loops:
			var a := _anim.get_animation(clip)
			if not a.has_meta("looped"):
				# Baked loops end on a copy of the first frame: drop it so the wrap is seamless.
				a.length -= 1.0 / 30.0
				a.loop_mode = Animation.LOOP_LINEAR
				a.set_meta("looped", true)
		_anim.play(stats.anim_idle)
		_anim.seek(randf() * _anim.current_animation_length)  # don't move in lockstep
	if stats.anim == "flight":
		_flight = TalonFlight.new(self, players[0])
		m.position.y = -TalonFlight.BODY_HEIGHT  # banks and pitches about the body's centre
	if has_bombard():
		for skel in m.find_children("*", "Skeleton3D", true, false):
			if skel.find_bone("muzzle") >= 0:
				_muzzle_skel = skel
				_muzzle_bone = skel.find_bone("muzzle")
	if stats.get("flak", false):
		var skeletons := m.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_turrets = ElephantTurrets.new()
			skeletons[0].add_child(_turrets)
	if has_flash():
		var skeletons := m.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_rig = KangarooRig.new()
			skeletons[0].add_child(_rig)
			# The flash grenade it pulls and holds up to throw.
			_held = Mats.cylinder_mesh(0.065, 0.18, Vector3.ZERO, Mats.flat(Color(0.25, 0.3, 0.2), 0.3, 0.6), 10)
			_held.top_level = true
			_held.visible = false
			add_child(_held)
	if has_blast():
		var skeletons := m.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_lion = LionessRig.new()
			skeletons[0].add_child(_lion)
	if has_nest():
		var skeletons := m.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_serpent = SerpentRig.new()
			skeletons[0].add_child(_serpent)
		_nest_icon = Sprite3D.new()
		_nest_icon.texture = _nest_texture()
		_nest_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_nest_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_nest_icon.shaded = false
		_nest_icon.no_depth_test = true
		_nest_icon.fixed_size = true  # the same size on screen however far out the camera is
		_nest_icon.pixel_size = NEST_ICON_SIZE
		_nest_icon.top_level = true
		_nest_icon.visible = false
		add_child(_nest_icon)
	if has_sneak() or has_trap():
		# See-through copies of her materials for the defender's view while she sneaks (_sneak_look), or the
		# snake's while it lies coiled round its bush.
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var src := mi.get_active_material(s) as BaseMaterial3D
				if src == null:
					continue
				var ghost := src.duplicate() as BaseMaterial3D
				ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ghost.albedo_color.a = stats.sneak_alpha
				ghost.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				_ghosts.append([mi, s, ghost])
		_bush = Sprite3D.new()
		_bush.texture = _trap_texture() if has_trap() else _bush_texture()
		_bush.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_bush.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bush.shaded = false
		_bush.no_depth_test = true
		_bush.fixed_size = true  # the same size on screen however far out the camera is
		_bush.pixel_size = BUSH_ICON_SIZE
		_bush.top_level = true
		_bush.visible = false
		add_child(_bush)
	if has_dog_modes():
		# The healing beams (_heal_beams): a thin cylinder each, stretched out to the unit it heals.
		var tube := CylinderMesh.new()
		tube.top_radius = 1.0
		tube.bottom_radius = 1.0
		tube.height = 1.0
		tube.radial_segments = 6
		tube.rings = 1
		for k in stats.heal_units:
			var b := MeshInstance3D.new()
			b.mesh = tube
			b.material_override = Mats.unshaded(Color(HEAL_COLOR, 0.7))
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.top_level = true
			b.visible = false
			add_child(b)
			_beams.append(b)
	if stats.get("carry_gun", false):
		# Carried weapon placeholder until weapons get modeled.
		_model.add_child(Mats.box_mesh(Vector3(0.12, 0.16, 0.9), Vector3(0.35, 1.15, -0.45),
				Mats.flat(Color(0.12, 0.12, 0.13), 0.6, 0.4)))


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = stats.radius + 0.25
	t.outer_radius = stats.radius + 0.4
	t.rings = 24
	t.ring_segments = 4
	_ring.mesh = t
	_ring.material_override = Mats.unshaded(Color(0.3, 1.0, 0.4))
	_ring.position.y = 0.06
	_ring.scale.y = 0.2
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	if stats.has("aa_range"):
		# Dashed circle showing how far the anti-air passive reaches.
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		RhinoAim.dashed_circle(im, Vector3.UP * 0.15, stats.aa_range, 48)
		im.surface_end()
		_aa_ring = MeshInstance3D.new()
		_aa_ring.mesh = im
		_aa_ring.material_override = Mats.unshaded(Color(0.55, 0.75, 1.0, 0.8))
		_aa_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aa_ring.visible = false
		add_child(_aa_ring)
	if resupplies():
		# Dashed circle showing how far the kangaroo's supplies reach.
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		RhinoAim.dashed_circle(im, Vector3.UP * 0.15, stats.resupply_range, 40)
		im.surface_end()
		_supply_ring = MeshInstance3D.new()
		_supply_ring.mesh = im
		_supply_ring.material_override = Mats.unshaded(SUPPLY_COLOR)
		_supply_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_supply_ring.visible = false
		add_child(_supply_ring)
	if has_dog_modes():
		# Dashed circles showing how far the dog heals, and sniffs out mines (the mode it is in: _dog_rings).
		_heal_ring = _dashed_ring(stats.heal_range, 40, Color(HEAL_COLOR, 0.75))
		_sweep_ring = _dashed_ring(stats.sweep_range, 64, SWEEP_COLOR)
	if has_ping():
		# Dashed circle showing how far the giraffe's ping reaches.
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		RhinoAim.dashed_circle(im, Vector3.UP * 0.15, stats.ping_radius, 96)
		im.surface_end()
		_ping_ring = MeshInstance3D.new()
		_ping_ring.mesh = im
		_ping_ring.material_override = Mats.unshaded(PING_COLOR)
		_ping_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ping_ring.visible = false
		add_child(_ping_ring)


func _dashed_ring(radius: float, dashes: int, color: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	RhinoAim.dashed_circle(im, Vector3.UP * 0.15, radius, dashes)
	im.surface_end()
	var ring := MeshInstance3D.new()
	ring.mesh = im
	ring.material_override = Mats.unshaded(color)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	return ring


func _build_hp_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.top_level = true
	add_child(_hp_bar)
	var w := clampf(stats.radius * 2.2, 1.2, 3.0)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, 0.14)
	bg.mesh = q
	bg.material_override = Mats.unshaded(Color(0, 0, 0, 0.6))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(w, 0.1)
	_hp_fill.mesh = qf
	_hp_fill.position.z = 0.01
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(_hp_fill)
	_hp_bar.visible = false
	_supply_icon = Sprite3D.new()
	_supply_icon.texture = _supply_texture()
	_supply_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_supply_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_supply_icon.shaded = false
	_supply_icon.no_depth_test = true
	_supply_icon.fixed_size = true  # the same size on screen however far out the camera is
	_supply_icon.pixel_size = SUPPLY_ICON_SIZE
	_supply_icon.top_level = true
	_supply_icon.visible = false
	add_child(_supply_icon)
	_tag_icon = Sprite3D.new()
	_tag_icon.texture = _tag_texture()
	_tag_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_tag_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag_icon.shaded = false
	_tag_icon.no_depth_test = true
	_tag_icon.fixed_size = true  # the same size on screen however far out the camera is
	_tag_icon.pixel_size = TAG_ICON_SIZE
	_tag_icon.top_level = true
	_tag_icon.visible = false
	add_child(_tag_icon)
	_heal_icon = Sprite3D.new()
	_heal_icon.texture = _heal_texture()
	_heal_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_heal_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_heal_icon.shaded = false
	_heal_icon.no_depth_test = true
	_heal_icon.fixed_size = true  # the same size on screen however far out the camera is
	_heal_icon.pixel_size = HEAL_ICON_SIZE
	_heal_icon.top_level = true
	_heal_icon.visible = false
	add_child(_heal_icon)


## The resupplied units' icon: a little ammo box, olive drab with a lid, a latch and a yellow
## stencil band, three brass rounds standing in it.
static func _supply_texture() -> ImageTexture:
	if _supply_tex:
		return _supply_tex
	var img := Image.create(24, 21, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.07, 0.08, 0.05)
	for x in [6, 10, 14]:
		img.fill_rect(Rect2i(x, 0, 4, 9), ink)
		img.fill_rect(Rect2i(x + 1, 3, 2, 6), Color(0.96, 0.76, 0.27))
		img.fill_rect(Rect2i(x + 1, 1, 2, 2), Color(0.8, 0.48, 0.22))
	img.fill_rect(Rect2i(1, 7, 22, 14), ink)
	img.fill_rect(Rect2i(2, 8, 20, 12), Color(0.44, 0.5, 0.23))
	img.fill_rect(Rect2i(2, 8, 20, 3), Color(0.31, 0.36, 0.15))
	img.fill_rect(Rect2i(10, 10, 4, 3), Color(0.82, 0.82, 0.76))
	img.fill_rect(Rect2i(4, 15, 16, 2), Color(0.98, 0.86, 0.3))
	_supply_tex = ImageTexture.create_from_image(img)
	return _supply_tex


## A tagged unit's icon, on both sides: a sniper's aim, a red ring with four ticks pointing in at a dot,
## outlined dark.
static func _tag_texture() -> ImageTexture:
	if _tag_tex:
		return _tag_tex
	var n := 27
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(13.0, 13.0)
	var red := Color(1.0, 0.22, 0.16)
	var ink := Color(0.08, 0.02, 0.02, 0.9)
	for y in n:
		for x in n:
			var p := Vector2(x, y) - c
			var r := p.length()
			var tick := (absf(p.x) <= 1.0 and absf(p.y) >= 3.5 and absf(p.y) <= 10.5) \
					or (absf(p.y) <= 1.0 and absf(p.x) >= 3.5 and absf(p.x) <= 10.5)
			var ring := absf(r - 8.6) <= 1.3
			if tick or ring or r <= 1.6:
				img.set_pixel(x, y, red)
			elif absf(r - 8.6) <= 2.3 or r <= 2.6 or (absf(p.x) <= 2.0 and absf(p.y) >= 2.5 and absf(p.y) <= 11.5) \
					or (absf(p.y) <= 2.0 and absf(p.x) >= 2.5 and absf(p.x) <= 11.5):
				img.set_pixel(x, y, ink)
	_tag_tex = ImageTexture.create_from_image(img)
	return _tag_tex


## A unit a dog heals: a medic's cross, red on a white disc, outlined dark, with a little shading on the
## disc's lower right.
static func _heal_texture() -> ImageTexture:
	if _heal_tex:
		return _heal_tex
	var n := 23
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(11.0, 11.0)
	var red := Color(0.86, 0.1, 0.1)
	for y in n:
		for x in n:
			var p := Vector2(x, y) - c
			var r := p.length()
			if r <= 9.6:
				var cross := (absf(p.x) <= 2.0 and absf(p.y) <= 6.5) or (absf(p.y) <= 2.0 and absf(p.x) <= 6.5)
				var shade := 0.88 if p.x + p.y > 9.0 else 1.0
				img.set_pixel(x, y, red if cross else Color(0.97, 0.97, 0.95) * shade)
			elif r <= 11.0:
				img.set_pixel(x, y, Color(0.06, 0.08, 0.06, 0.9))
	_heal_tex = ImageTexture.create_from_image(img)
	return _heal_tex


## A sneaking lioness's icon on the attacker's side: a leafy bush, four clumps of leaves in a dark
## outline, lit from the upper left, leaves picked out darker, on a strip of shadow.
static func _bush_texture() -> ImageTexture:
	if _bush_tex:
		return _bush_tex
	var w := 28
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var clumps := [Vector3(8.0, 13.5, 6.5), Vector3(14.0, 8.5, 7.5), Vector3(20.5, 12.5, 6.5), Vector3(14.0, 15.0, 6.5)]
	var ink := Color(0.04, 0.09, 0.03)
	var dark := Color(0.13, 0.34, 0.1)
	var lit := Color(0.47, 0.76, 0.26)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := -INF
			var n := Vector2.ZERO
			for c in clumps:
				var d := p - Vector2(c.x, c.y)
				if c.z - d.length() > inside:
					inside = c.z - d.length()
					n = d / c.z
			if inside > 0.0:
				var col := dark.lerp(lit, clampf(0.55 - n.x * 0.45 - n.y * 0.6, 0.0, 1.0))
				if (x * 7 + y * 13) % 11 == 0 or (x * 5 + y * 3) % 17 == 0:
					col = col.darkened(0.35)  # leaves picked out
				img.set_pixel(x, y, col)
			elif inside > -1.3:
				img.set_pixel(x, y, ink)
	img.fill_rect(Rect2i(4, h - 2, w - 8, 2), Color(0.0, 0.0, 0.0, 0.45))
	_bush_tex = ImageTexture.create_from_image(img)
	return _bush_tex


## A Serpent Sniper perched in its nest, on the attacker's side: a tree, a round crown of leaves on a brown
## trunk, with a sniper rifle across it (the scope on top, a muzzle brake, the stock to the left), outlined dark.
static func _nest_texture() -> ImageTexture:
	if _nest_tex:
		return _nest_tex
	var w := 30
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.04, 0.07, 0.03)
	var crown := [Vector3(9.5, 9.0, 6.0), Vector3(15.5, 6.5, 6.5), Vector3(21.0, 9.5, 5.5), Vector3(15.0, 12.0, 5.5)]
	var dark := Color(0.13, 0.34, 0.1)
	var lit := Color(0.47, 0.76, 0.26)
	var rifle := {}
	for y in range(16, 18):
		for x in range(8, 27):
			rifle[Vector2i(x, y)] = Color(0.22, 0.23, 0.25) if y == 16 else Color(0.14, 0.15, 0.16)  # the barrel
	for y in range(15, 19):
		for x in range(26, 29):
			rifle[Vector2i(x, y)] = Color(0.18, 0.19, 0.2)  # the muzzle brake
	for y in range(15, 20):
		for x in range(6, 14):
			rifle[Vector2i(x, y)] = Color(0.3, 0.3, 0.28) if y < 17 else Color(0.2, 0.2, 0.19)  # the receiver
	for y in range(16, 21):
		for x in range(1, 7):
			if x + (20 - y) >= 2:
				rifle[Vector2i(x, y)] = Color(0.36, 0.3, 0.2) if y < 18 else Color(0.27, 0.22, 0.15)  # the stock
	for x in range(8, 15):
		rifle[Vector2i(x, 13)] = Color(0.16, 0.17, 0.19)
		rifle[Vector2i(x, 14)] = Color(0.1, 0.1, 0.12)  # the scope
	rifle[Vector2i(14, 13)] = Color(0.55, 0.8, 0.95)
	rifle[Vector2i(8, 13)] = Color(0.55, 0.8, 0.95)
	for y in range(19, 22):
		rifle[Vector2i(11, y)] = Color(0.14, 0.15, 0.16)  # the magazine
		rifle[Vector2i(12, y)] = Color(0.14, 0.15, 0.16)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := -INF
			var n := Vector2.ZERO
			for c in crown:
				var d := p - Vector2(c.x, c.y)
				if c.z - d.length() > inside:
					inside = c.z - d.length()
					n = d / c.z
			var trunk := x >= 13 and x <= 16 and y >= 14 and y <= 24
			if inside > 0.0:
				var col := dark.lerp(lit, clampf(0.55 - n.x * 0.45 - n.y * 0.6, 0.0, 1.0))
				if (x * 7 + y * 13) % 11 == 0:
					col = col.darkened(0.35)
				img.set_pixel(x, y, col)
			elif trunk:
				img.set_pixel(x, y, Color(0.45, 0.3, 0.17) if x < 15 else Color(0.33, 0.21, 0.12))
			elif inside > -1.3 or (x >= 12 and x <= 17 and y >= 13 and y <= 25):
				img.set_pixel(x, y, ink)
	# The rifle over it, outlined.
	for k in rifle:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = k + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and not rifle.has(q):
					img.set_pixel(q.x, q.y, ink)
	for k in rifle:
		img.set_pixel(k.x, k.y, rifle[k])
	_nest_tex = ImageTexture.create_from_image(img)
	return _nest_tex


## A Serpent Sniper coiled round its bush, on the attacker's side: tall grass, a snake's head looking out of it
## (spotted, a yellow eye with a slit pupil, a red forked tongue), outlined dark.
static func _trap_texture() -> ImageTexture:
	if _trap_tex:
		return _trap_tex
	var w := 28
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.04, 0.07, 0.03)
	var col := {}
	# Blades of grass [base x, tip x, tip y, base width, in front of the head], shaded from the left.
	var blades := [[3.5, 1.5, 8.0, 3.0, false], [7.0, 6.0, 3.0, 3.2, false], [11.0, 13.0, 6.0, 3.0, false],
			[20.0, 23.0, 4.0, 3.0, false], [24.5, 26.5, 9.0, 2.8, false], [5.5, 9.0, 11.0, 3.0, true],
			[14.5, 12.5, 12.0, 3.4, true], [18.5, 21.0, 13.0, 3.0, true]]
	var snake := {}
	# The neck, then the head (snout to the right), spotted, a lighter jaw.
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var neck := Vector2(p.x - lerpf(12.0, 13.5, (p.y - 9.0) / 12.0), 0.0).length() < 2.6 and p.y > 9.0 and p.y < 22.0
			var e := Vector2((p.x - 15.0) / 6.0, (p.y - 8.5) / 3.6)
			var head := e.length() < 1.0 or (p.x > 19.0 and p.x < 21.6 and absf(p.y - 9.2) < 1.8 - (p.x - 19.0) * 0.35)
			if head or neck:
				var c := Color(0.66, 0.64, 0.3) if p.y < 9.5 or neck else Color(0.84, 0.8, 0.5)
				if (x * 5 + y * 3) % 7 == 0 and p.y < 10.0:
					c = Color(0.2, 0.18, 0.08)
				snake[Vector2i(x, y)] = c
	snake[Vector2i(17, 7)] = Color(0.98, 0.84, 0.15)
	snake[Vector2i(18, 7)] = Color(0.05, 0.04, 0.02)  # the eye, its slit pupil
	snake[Vector2i(17, 8)] = Color(0.9, 0.72, 0.1)
	for t in [Vector2i(22, 10), Vector2i(23, 10), Vector2i(24, 9), Vector2i(25, 8), Vector2i(24, 11), Vector2i(25, 12)]:
		snake[t] = Color(0.85, 0.08, 0.1)  # the forked tongue
	for front in [false, true]:
		for b in blades:
			if b[4] != front:
				continue
			for y in h:
				var u := clampf((25.5 - (y + 0.5)) / (25.5 - b[2]), 0.0, 1.0)
				if y + 0.5 < b[2]:
					continue
				var cx: float = lerpf(b[0], b[1], u * u)
				var half: float = b[3] * 0.5 * (1.0 - u)
				for x in w:
					var d := absf(x + 0.5 - cx)
					if d <= half + 0.35:
						col[Vector2i(x, y)] = Color(0.5, 0.78, 0.27) if x + 0.5 < cx else Color(0.2, 0.46, 0.12)
		if not front:
			for k in snake:
				col[k] = snake[k]
	for k in col:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = k + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and not col.has(q):
					img.set_pixel(q.x, q.y, ink)
	for k in col:
		img.set_pixel(k.x, k.y, col[k])
	_trap_tex = ImageTexture.create_from_image(img)
	return _trap_tex


func _update_hp_bar() -> void:
	if not _hp_bar:
		return
	var ratio := clampf(hp / stats.hp, 0.0, 1.0)
	# A sneaking lioness shows none on the defender's side: it would give her away.
	_hp_bar.visible = hp > 0.0 and (selected or ratio < 1.0) and _look != 1
	_hp_fill.scale.x = maxf(ratio, 0.001)
	_hp_fill.material_override = Mats.unshaded(Color(1.0, 0.25, 0.2) if ratio < 0.35 else Color(0.95, 0.8, 0.2) if ratio < 0.7 else Color(0.3, 1.0, 0.4))
