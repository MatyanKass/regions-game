# Every tunable number in the game lives here. No other sim file hardcodes a value,
# so balancing the whole match is a single-file edit.
#
# Coins and power are stored as integer "centi" units (1 displayed point == 100 units).
# The simulation must never use floating point: both clients run the same tick loop and
# any rounding difference desyncs the match.
class_name Balance
extends RefCounted

const TICKS_PER_SECOND := 10
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
const BASE_COIN_PER_TICK := 10
const BASE_POWER_PER_TICK := 10
const BASE_COIN_CAP := 100 * UNIT
const BASE_POWER_CAP := 50 * UNIT
const START_COINS := 0
const START_POWER := 0

# --- Capture ---
const CAPTURE_POWER_COST := 10 * UNIT

# --- Ships ---
const SHIP_TICKS_PER_CELL := 30
const SHIP_POWER_COST := 10 * UNIT

# --- Demolition: half the coin price back, power is never refunded ---
const DEMOLISH_REFUND_PERCENT := 50

enum Building { NONE, FACTORY, HOUSE, BANK, BARRACKS, MILITARY_BASE, PORT }

# coin_cost / power_cost  - price to build
# workers                 - population permanently occupied by this building
# people                  - population capacity added
# coin_per_tick           - income
# power_per_tick          - power income
# coin_cap / power_cap    - added storage limit
# coastal                 - may only be built on a cell orthogonally touching sea
const BUILDINGS := {
	Building.FACTORY: {
		"name": "factory",
		"coin_cost": 40 * UNIT, "power_cost": 0,
		"workers": 1, "people": 0,
		"coin_per_tick": 2, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false,
	},
	Building.HOUSE: {
		"name": "house",
		"coin_cost": 30 * UNIT, "power_cost": 0,
		"workers": 0, "people": 2,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false,
	},
	Building.BANK: {
		"name": "bank",
		"coin_cost": 80 * UNIT, "power_cost": 0,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 10 * UNIT, "power_cap": 0,
		"coastal": false,
	},
	Building.BARRACKS: {
		"name": "barracks",
		"coin_cost": 40 * UNIT, "power_cost": 25 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 10 * UNIT,
		"coastal": false,
	},
	Building.MILITARY_BASE: {
		"name": "military_base",
		"coin_cost": 60 * UNIT, "power_cost": 15 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 10,
		"coin_cap": 0, "power_cap": 0,
		"coastal": false,
	},
	Building.PORT: {
		"name": "port",
		"coin_cost": 60 * UNIT, "power_cost": 30 * UNIT,
		"workers": 0, "people": 0,
		"coin_per_tick": 0, "power_per_tick": 0,
		"coin_cap": 0, "power_cap": 0,
		"coastal": true,
	},
}
