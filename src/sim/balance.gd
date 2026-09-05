# Every tunable number in the game lives here. No other sim file hardcodes a value,
# so balancing the whole match is a single-file edit.
#
# Coins and power are stored as integer "centi" units (1 displayed point == 100 units).
# The simulation must never use floating point: both clients run the same tick loop and
# any rounding difference desyncs the match.
class_name Balance
extends RefCounted

# 20 ticks a second, not 10, because the capture cooldowns are a quarter and four tenths
# of a second: at 10 Hz neither is a whole number of ticks, and the simulation is not
# allowed to round.
const TICKS_PER_SECOND := 20
const UNIT := 100

# --- World ---
const MAP_WIDTH := 25
const MAP_HEIGHT := 25
const SEA_PERCENT_MIN := 5
const SEA_PERCENT_MAX := 15
const START_DISTANCE := 16

# --- Match ---
const MATCH_LIMIT_TICKS := 40 * 60 * TICKS_PER_SECOND

# --- Base economy, granted only while a player still owns at least one cell ---
const BASE_COIN_PER_TICK := 5     # 1 coin a second
const BASE_POWER_PER_TICK := 5    # 1 power a second
const BASE_COIN_CAP := 100 * UNIT
const BASE_POWER_CAP := 50 * UNIT
const START_COINS := 0
const START_POWER := 0

# --- Capture ---
const CAPTURE_POWER_COST := 10 * UNIT
# Tapping is the whole attack, so the rate of fire is the balance. Taking open ground is
# quick; prising a cell out of the enemy takes longer.
const CAPTURE_COOLDOWN_TICKS := 5           # 0.25 s on neutral ground
const CAPTURE_ENEMY_COOLDOWN_TICKS := 8     # 0.40 s on an enemy cell
# A barrier does not stop the attack, it stalls the whole advance behind it.
const BARRIER_COOLDOWN_TICKS := 4 * TICKS_PER_SECOND

# --- Ships ---
const SHIP_TICKS_PER_CELL := 60   # about three seconds a cell
const SHIP_POWER_COST := 10 * UNIT

# --- Buildings ---
# Half the coins back, counted over everything sunk into the upgrades as well.
const DEMOLISH_REFUND_PERCENT := 50
const MAX_LEVEL := 5

enum Building { NONE, FACTORY, HOUSE, BANK, BARRACKS, MILITARY_BASE, PORT, BARRIER }

# coin_cost / power_cost  - price of level 1; an upgrade to level N costs N times that
# workers                 - population occupied; unchanged by upgrades
# people                  - population capacity added, per level
# coin_per_tick           - income, per level
# power_per_tick          - power income, per level
# coin_cap / power_cap    - added storage limit, per level
# coastal                 - may only be built on a cell orthogonally touching sea
# max_level               - how far it can be upgraded
const BUILDINGS := {
	Building.FACTORY: {
		"name": "factory",
		"coin_cost": 40 * UNIT, "power_cost": 0,
		"workers": 1, "people": 0,
		"coin_per_tick": 1, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.HOUSE: {
		"name": "house",
		"coin_cost": 30 * UNIT, "power_cost": 0,
		"workers": 0, "people": 2,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.BANK: {
		"name": "bank",
		"coin_cost": 80 * UNIT, "power_cost": 0,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 10 * UNIT, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.BARRACKS: {
		"name": "barracks",
		"coin_cost": 40 * UNIT, "power_cost": 25 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 10 * UNIT,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.MILITARY_BASE: {
		"name": "military_base",
		"coin_cost": 60 * UNIT, "power_cost": 15 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 5,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.PORT: {
		"name": "port",
		"coin_cost": 60 * UNIT, "power_cost": 30 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": true, "max_level": MAX_LEVEL,
	},
	# The barrier earns nothing. It is bought purely so that whoever takes this cell
	# cannot take the next one for four seconds. One level only: a wall is a wall.
	Building.BARRIER: {
		"name": "barrier",
		"coin_cost": 50 * UNIT, "power_cost": 20 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": 1,
	},
}

# What the next level costs. Levels are priced linearly, so a level 3 bank has cost
# 1 + 2 + 3 = six times the base price and gives three times the effect: upgrading is
# a way to save space, never a discount.
static func upgrade_coin_cost(type: int, to_level: int) -> int:
	return int(BUILDINGS[type]["coin_cost"]) * to_level

static func upgrade_power_cost(type: int, to_level: int) -> int:
	return int(BUILDINGS[type]["power_cost"]) * to_level

# Everything sunk into a building from level 1 up to its current level.
static func invested_coins(type: int, level: int) -> int:
	return int(BUILDINGS[type]["coin_cost"]) * level * (level + 1) / 2

static func max_level_of(type: int) -> int:
	return int(BUILDINGS[type]["max_level"])
