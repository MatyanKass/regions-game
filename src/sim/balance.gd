# Every tunable number in the game lives here. No other sim file hardcodes a value,
# so balancing the whole match is a single-file edit.
#
# Coins and power are stored as integer thousandths (1 displayed point == UNIT).
# The simulation must never use floating point: both clients run the same tick loop and
# any rounding difference desyncs the match.
class_name Balance
extends RefCounted

# 20 ticks a second, not 10, because the capture cooldowns are a quarter and four tenths
# of a second: at 10 Hz neither is a whole number of ticks, and the simulation is not
# allowed to round.
const TICKS_PER_SECOND := 20
# Coins and power are counted in thousandths of a point. Hundredths were enough until
# land started paying: a cell earns 0.02 a second, which is a fifth of a hundredth per
# tick and would have had to be rounded. Rounding is exactly what a lockstep simulation
# may not do, so the unit got finer instead.
const UNIT := 1000

# --- World ---
# The size of a map and how far apart the players start are chosen per world, in
# WorldSettings; what stays here is how much of any map is water.
const SEA_PERCENT_MIN := 5
const SEA_PERCENT_MAX := 15

# --- Match ---
# The default when nobody chose otherwise. A world carries its own limit.
const MATCH_LIMIT_TICKS := 40 * 60 * TICKS_PER_SECOND

# --- Base economy, granted only while a player still owns at least one cell ---
const BASE_COIN_PER_TICK := 50     # 1 coin a second
const BASE_POWER_PER_TICK := 50    # 1 power a second

# What one cell of territory is worth. Land used to be worth nothing at all: a country
# of five hundred cells earned exactly what it earned at twenty, so the second half of a
# match was painting empty squares. It is deliberately tiny per cell - a hundred cells
# earn two coins a second - so that it rewards holding ground without turning the first
# few captures into a runaway.
const CELL_COIN_PER_TICK := 1      # 0.02 coins a second per cell
const CELL_COIN_CAP := UNIT / 2    # and a little room to keep them in
const CELL_POWER_CAP := UNIT / 4
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
# build_seconds           - how long it takes to go up; nothing it gives counts until
#                           then, and the cell is a building site in the meantime
const BUILDINGS := {
	Building.FACTORY: {
		"name": "factory",
		"build_seconds": 9,
		"coin_cost": 40 * UNIT, "power_cost": 0,
		"workers": 1, "people": 0,
		"coin_per_tick": 10, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.HOUSE: {
		"name": "house",
		"build_seconds": 5,
		"coin_cost": 30 * UNIT, "power_cost": 0,
		"workers": 0, "people": 2,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.BANK: {
		"name": "bank",
		"build_seconds": 13,
		"coin_cost": 80 * UNIT, "power_cost": 0,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 10 * UNIT, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.BARRACKS: {
		"name": "barracks",
		"build_seconds": 8,
		"coin_cost": 40 * UNIT, "power_cost": 25 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 10 * UNIT,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.MILITARY_BASE: {
		"name": "military_base",
		"build_seconds": 12,
		"coin_cost": 60 * UNIT, "power_cost": 15 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 50,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false, "max_level": MAX_LEVEL,
	},
	Building.PORT: {
		"name": "port",
		"build_seconds": 15,
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
		"build_seconds": 6,
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

static func build_ticks(type: int) -> int:
	return int(BUILDINGS[type]["build_seconds"]) * TICKS_PER_SECOND

static func max_level_of(type: int) -> int:
	return int(BUILDINGS[type]["max_level"])
