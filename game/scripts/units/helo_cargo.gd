class_name HeloCargo
extends RefCounted
## The attackers' transport helicopter's hold (TransportHelo): how many spaces it has, how many each kind of unit takes,
## and how long things take. Plain numbers and rules with nothing in the scene, so the showcase can check them directly
## and the balance lives in one place.
##
## The hold has CAPACITY spaces. The War Elephant and the Savanna Signal Scout (the giraffe) take 5, the Combat Rhino and the
## Hippo Heavy Gunner 2, the Bison Field Gun (the bison artillery) 10, the Mule Artillery (the donkey artillery: six
## donkeys towing a siege gun) 15; every other unit takes 1. Units are unloaded one at a time, a queue, UNLOAD_TIME each.
## A helicopter shot down is replaced REPLACE_TIME seconds later, FLEET_SIZE of them stand by the main base.

## Spaces in the hold.
const CAPACITY := 50
## Spaces a unit takes by its UnitTypes id; any other takes DEFAULT_SPACES.
const SPACES := {
	"elephant": 5,
	"giraffe": 5,
	"rhino": 2,
	"hippo": 2,
	"bison_gun": 10,
	"mule": 15,
}
const DEFAULT_SPACES := 1
## Seconds to unload one unit (they come out one after another, in the order they went in).
const UNLOAD_TIME := 0.25
## Seconds it takes the attackers to get a new helicopter once one has been destroyed.
const REPLACE_TIME := 500.0
## Helicopters the attackers have, stationed outside their main base.
const FLEET_SIZE := 2


## Spaces a unit of this type takes in the hold.
static func spaces(type_id: String) -> int:
	return int(SPACES.get(type_id, DEFAULT_SPACES))


## Spaces taken by units of these types (an array of UnitTypes ids).
static func used(types: Array) -> int:
	var n := 0
	for t in types:
		n += spaces(String(t))
	return n


## True if a unit of this type fits in a hold that already has `used_now` spaces taken.
static func fits(used_now: int, type_id: String) -> bool:
	return used_now + spaces(type_id) <= CAPACITY


## How many of this type one empty hold takes.
static func most_of(type_id: String) -> int:
	return floori(float(CAPACITY) / float(spaces(type_id)))


## Seconds it takes to unload `count` units in a queue.
static func unload_seconds(count: int) -> float:
	return UNLOAD_TIME * float(count)
