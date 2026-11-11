class_name HeloFleet
extends Node
## The attackers' transport helicopters (TransportHelo): HeloCargo.FLEET_SIZE of them stand outside the main base from the
## start of the match, one off to each side of where the army comes out. One shot down is replaced HeloCargo.REPLACE_TIME
## seconds later by a new one standing at the same spot (its slot is empty meanwhile: replace_in says how long is left).
## The attacking player (AttackerController) and the commander (AttackerCommander "helo_board", "helo_fly") reach them here.
##
## One per match (Match), for the CPU attacker too. The CPU doesn't use them.

## A helicopter appeared at the base (the start, or a replacement) / was destroyed.
signal helo_added(helo: TransportHelo)
signal helo_lost(helo: TransportHelo)

## How far to either side of the main spawn point they stand (m), and how far toward the stronghold from it: clear of the
## army coming out, of the citadel's hull, and (on the classic field) of the first helipad's deck and the groves.
const PARK_SIDE := 88.0
const PARK_FORWARD := 22.0

## The main spawn point: where the army comes out (set before the fleet enters the tree), and where units a helicopter
## brings back get out.
var base_position := Vector3.ZERO
## A showcase steps everything by hand and may leave the models out.
var manual := false
var with_rig := true
## The helicopter in each slot, or null; and the seconds until the empty slot's replacement arrives (0: none on its way).
var slots: Array = []
var replace_in: Array = []


func _ready() -> void:
	for i in HeloCargo.FLEET_SIZE:
		slots.append(null)
		replace_in.append(0.0)
		_spawn(i)


func _physics_process(delta: float) -> void:
	if not manual:
		step(delta)


## The replacements' clocks.
func step(delta: float) -> void:
	for i in slots.size():
		if slots[i] == null and replace_in[i] > 0.0:
			replace_in[i] = maxf(replace_in[i] - delta, 0.0)
			if replace_in[i] <= 0.0:
				_spawn(i)


## Where the `index`-th helicopter stands by a main base whose spawn point is `base`: off to one side, nose pointing away from
## the stronghold so the ramp at its tail faces the field. {"position": Vector3 (on the ground), "yaw": float}.
static func park_spot(base: Vector3, index: int) -> Dictionary:
	var fwd := Vector3(-base.x, 0.0, -base.z)
	fwd = fwd.normalized() if fwd.length() > 1.0 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var side := -1.0 if index % 2 == 0 else 1.0
	var p := base + right * (side * PARK_SIDE) + fwd * PARK_FORWARD
	p.y = LevelBuilder.ground_height(p)
	var nose := -fwd
	return {"position": p, "yaw": atan2(nose.x, nose.z)}


## The live helicopter in slot `i`, or null (none there yet, or shot down and not yet replaced).
func helo_at(i: int) -> TransportHelo:
	if i < 0 or i >= slots.size():
		return null
	var h = slots[i]
	return h if h != null and is_instance_valid(h) and h.is_alive() else null


## Live helicopters.
func alive_count() -> int:
	var n := 0
	for i in slots.size():
		if helo_at(i) != null:
			n += 1
	return n


func _spawn(i: int) -> void:
	var spot := park_spot(base_position, i)
	var h := TransportHelo.new()
	h.manual = manual
	h.with_rig = with_rig
	h.setup(i, spot.position, spot.yaw)
	h.home_drop = base_position
	add_child(h)
	h.destroyed.connect(_on_destroyed)
	slots[i] = h
	replace_in[i] = 0.0
	helo_added.emit(h)


func _on_destroyed(h: TransportHelo) -> void:
	if h.slot < 0 or h.slot >= slots.size() or slots[h.slot] != h:
		return
	slots[h.slot] = null
	replace_in[h.slot] = HeloCargo.REPLACE_TIME
	helo_lost.emit(h)
