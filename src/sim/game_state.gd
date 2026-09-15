# Copyright (c) 2026 MatyanKass. All rights reserved.
# The whole game. Pure data plus a tick function - no nodes, no rendering, no networking.
#
# Both devices run this class over the same command stream and must end up with an
# identical state_hash() every tick. Rules for keeping that true:
#   * integers only, never float;
#   * never iterate a Dictionary whose insertion order could differ;
#   * the running totals below are the one cache, and tests hold them to a full
#     recount, because a cache that drifts is a desync waiting to happen.
#
# Those totals exist because a world may be a thousand cells across. Counting a player's
# income by walking the grid was honest and fine at 25 by 25; at a million cells it is a
# second of work per tick. Everything that changes the grid goes through _forget() and
# _remember(), which is also what keeps the rolling checksum the desync detector uses.
class_name GameState
extends RefCounted

enum Command { BUILD, DEMOLISH, CAPTURE, LAUNCH_SHIP, UPGRADE }

const NEUTRAL := 255
const NO_REGION := 255

var map_seed: int
var width: int
var height: int
var terrain: PackedByteArray      # WorldGen.LAND / WorldGen.SEA
var owner_of: PackedByteArray     # player index, or NEUTRAL
var building_at: PackedByteArray  # Balance.Building
var level_at: PackedByteArray     # 1..max_level where a building stands, 0 elsewhere
var coins: PackedInt64Array
var power: PackedInt64Array
var alive: PackedByteArray
# The tick from which each player may capture again. Attacking is a single tap, so
# the rate of fire is the only thing keeping it honest.
var capture_ready: PackedInt64Array
var ships: Array[Dictionary] = []
# Buildings that are going up. A site holds the cell while it is worked on but is not on
# the grid, so it contributes nothing and the running totals need not know about it. An
# array rather than a map from cells: it is walked in order every tick, and order is
# something lockstep cannot leave to chance.
var sites: Array[Dictionary] = []
var tick_count: int = 0
var finished: bool = false
var winner: int = -1
var settings: WorldSettings

# Who each player is playing as: the region they picked, and the colour that came out of
# its palette, packed as 0xRRGGBB. Cosmetic, and deliberately outside state_hash(): a
# colour cannot put two devices out of step. It lives here rather than in the networking
# because a snapshot, a save and a client being resynced all have to carry it, and this
# is the thing all three already copy.
var player_region: PackedByteArray
var player_tint: PackedInt32Array

# Running totals, per player. Maintained by _forget()/_remember(); verify_totals()
# recounts the slow way and is what the tests measure them against.
var _t_cells: PackedInt32Array
var _t_people: PackedInt32Array
var _t_coin_rate: PackedInt64Array    # from buildings that need nobody to work them
var _t_power_rate: PackedInt64Array
var _t_coin_cap: PackedInt64Array     # from buildings only; land is added on top
var _t_power_cap: PackedInt64Array
var _t_jobs: Array = []               # per player: cells of buildings that need staffing
# A rolling checksum of the whole grid, so the hash the two devices compare does not
# have to read a million cells to be computed.
var _grid_sum: int = 0

static func create(seed_value: int, player_count_or_settings = 2) -> GameState:
	# Callers that only care about the classic map still pass a player count.
	var config: WorldSettings
	if player_count_or_settings is WorldSettings:
		config = player_count_or_settings
	else:
		config = WorldSettings.new()
		if int(player_count_or_settings) == 1:
			config.mode = WorldSettings.Mode.FREE
	var s := GameState.new()
	var world := WorldGen.generate(seed_value, config)
	s.settings = config
	s.map_seed = seed_value
	s.width = config.width
	s.height = config.height
	s.terrain = world["terrain"]
	var total := s.width * s.height
	s.owner_of = PackedByteArray()
	s.owner_of.resize(total)
	s.owner_of.fill(NEUTRAL)
	s.building_at = PackedByteArray()
	s.building_at.resize(total)
	s.building_at.fill(Balance.Building.NONE)
	s.level_at = PackedByteArray()
	s.level_at.resize(total)
	s.level_at.fill(0)
	s.coins = PackedInt64Array()
	s.power = PackedInt64Array()
	s.alive = PackedByteArray()
	s.capture_ready = PackedInt64Array()
	var starts: PackedInt32Array = world["starts"]
	var count := config.player_count()
	s.player_region = PackedByteArray()
	s.player_region.resize(count)
	s.player_region.fill(NO_REGION)
	s.player_tint = PackedInt32Array()
	s.player_tint.resize(count)
	s.player_tint.fill(0)
	for p in range(count):
		s.coins.append(Balance.START_COINS)
		s.power.append(Balance.START_POWER)
		s.alive.append(1)
		s.capture_ready.append(0)
	for p in range(count):
		s.owner_of[starts[p]] = p
	s.recount()
	return s

# Set once, as a match starts, from what each player chose in the lobby.
func set_identity(player: int, region: int, tint: int) -> void:
	if player < 0 or player >= player_region.size():
		return
	player_region[player] = region if region >= 0 and region < NO_REGION else NO_REGION
	player_tint[player] = tint

func region_of(player: int) -> int:
	if player < 0 or player >= player_region.size():
		return NO_REGION
	return int(player_region[player])

# 0 when nobody chose, which is the interface's cue to fall back to its own pens.
func tint_of(player: int) -> int:
	if player < 0 or player >= player_tint.size():
		return 0
	return int(player_tint[player])

func player_count() -> int:
	return alive.size()

func match_limit_ticks() -> int:
	return settings.match_limit_ticks() if settings != null else Balance.MATCH_LIMIT_TICKS

func is_free_play() -> bool:
	return settings != null and settings.mode == WorldSettings.Mode.FREE

# --- Running totals -----------------------------------------------------------------

func _reset_totals() -> void:
	var count := alive.size()
	_t_cells = PackedInt32Array(); _t_cells.resize(count); _t_cells.fill(0)
	_t_people = PackedInt32Array(); _t_people.resize(count); _t_people.fill(0)
	_t_coin_rate = PackedInt64Array(); _t_coin_rate.resize(count); _t_coin_rate.fill(0)
	_t_power_rate = PackedInt64Array(); _t_power_rate.resize(count); _t_power_rate.fill(0)
	_t_coin_cap = PackedInt64Array(); _t_coin_cap.resize(count); _t_coin_cap.fill(0)
	_t_power_cap = PackedInt64Array(); _t_power_cap.resize(count); _t_power_cap.fill(0)
	_t_jobs = []
	for p in range(count):
		_t_jobs.append(PackedInt32Array())
	_grid_sum = 0

# Recounts everything from the grid. Used when a snapshot arrives and by the tests that
# hold the running totals honest.
func recount() -> void:
	_reset_totals()
	for i in range(owner_of.size()):
		_remember(i)

# by MatyanKass
# One cell's contribution to the checksum. Multiplying by the index means two cells
# swapping their contents changes the sum, which a plain total would not notice.
func _cell_signature(cell: int) -> int:
	var value := int(owner_of[cell]) * 131 + int(building_at[cell]) * 17 + int(level_at[cell]) * 7 + 1
	return value * (cell + 1)

# Every change to a cell is bracketed by these two: forget what it contributed, change
# it, remember what it contributes now. There is no third way to touch the grid.
func _forget(cell: int) -> void:
	_grid_sum -= _cell_signature(cell)
	_account(cell, -1)

func _remember(cell: int) -> void:
	_grid_sum += _cell_signature(cell)
	_account(cell, 1)

func _account(cell: int, sign: int) -> void:
	var player := int(owner_of[cell])
	if player == NEUTRAL or player >= _t_cells.size():
		return
	_t_cells[player] += sign
	var type := int(building_at[cell])
	if type == Balance.Building.NONE:
		return
	var d: Dictionary = Balance.BUILDINGS[type]
	# An upgrade multiplies what a building produces. The people it employs do not
	# change, which is what makes upgrading the answer once land runs out.
	var lvl := maxi(1, int(level_at[cell]))
	_t_power_rate[player] += sign * int(d["power_per_tick"]) * lvl
	_t_coin_cap[player] += sign * int(d["coin_cap"]) * lvl
	_t_power_cap[player] += sign * int(d["power_cap"]) * lvl
	_t_people[player] += sign * int(d["people"]) * lvl
	if int(d["workers"]) > 0:
		var jobs: PackedInt32Array = _t_jobs[player]
		if sign > 0:
			jobs.append(cell)
		else:
			var at := jobs.find(cell)
			if at >= 0:
				jobs.remove_at(at)
		_t_jobs[player] = jobs
	else:
		_t_coin_rate[player] += sign * int(d["coin_per_tick"]) * lvl

# --- Grid helpers ---

func index_of(x: int, y: int) -> int:
	return x + y * width

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

# by MatyanKass
func is_land(cell: int) -> bool:
	return terrain[cell] == WorldGen.LAND

func neighbours(cell: int) -> Array[int]:
	return WorldGen.neighbours(cell, width, height)

func touches_player(cell: int, player: int) -> bool:
	for n in neighbours(cell):
		if owner_of[n] == player:
			return true
	return false

func touches_sea(cell: int) -> bool:
	for n in neighbours(cell):
		if terrain[n] == WorldGen.SEA:
			return true
	return false

# --- Derived player figures. Recomputed from the grid on every call by design. ---

func aggregate(player: int) -> Dictionary:
	if player < 0 or player >= _t_cells.size():
		return {"cells": 0, "coin_per_tick": 0, "power_per_tick": 0,
			"coin_cap": Balance.BASE_COIN_CAP, "power_cap": Balance.BASE_POWER_CAP,
			"people": 0, "workers": 0, "free_people": 0, "idle_cells": PackedInt32Array()}
	var cells := int(_t_cells[player])
	var people := int(_t_people[player])
	var power_per_tick := int(_t_power_rate[player])
	# The flat base income is what keeps a one-cell player in the game, so it is tied to
	# owning territory at all rather than to any building. On top of it, every cell pays
	# a little and holds a little, which is what makes taking ground worth something in
	# its own right rather than only as a way to reach the enemy.
	var coin_per_tick := int(_t_coin_rate[player]) + cells * Balance.CELL_COIN_PER_TICK
	if cells > 0:
		coin_per_tick += Balance.BASE_COIN_PER_TICK
		power_per_tick += Balance.BASE_POWER_PER_TICK
	var coin_cap := Balance.BASE_COIN_CAP + int(_t_coin_cap[player]) \
		+ cells * Balance.CELL_COIN_CAP
	var power_cap := Balance.BASE_POWER_CAP + int(_t_power_cap[player]) \
		+ cells * Balance.CELL_POWER_CAP

	# Housing can vanish - losing a house to a capture takes its residents with it - so
	# there may be more factories than people to work them. Rather than let the surplus
	# keep producing out of nowhere, the workforce is handed out and whatever is left
	# over stands idle. The biggest factories are staffed first, which is what a player
	# would do, and ties break on cell index so both devices reach the same answer. Only
	# the buildings that need staff are sorted here, never the whole map.
	var jobs: Array = []
	for cell in (_t_jobs[player] as PackedInt32Array):
		jobs.append([maxi(1, int(level_at[cell])), int(cell)])
	jobs.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var spare := people
	var workers := 0
	var idle := PackedInt32Array()
	for job in jobs:
		var cell := int(job[1])
		var data: Dictionary = Balance.BUILDINGS[int(building_at[cell])]
		var needed := int(data["workers"])
		if spare < needed:
			idle.append(cell)
			continue
		spare -= needed
		workers += needed
		coin_per_tick += int(data["coin_per_tick"]) * int(job[0])

	return {
		"cells": cells,
		"coin_per_tick": coin_per_tick,
		"power_per_tick": power_per_tick,
		"coin_cap": coin_cap,
		"power_cap": power_cap,
		"people": people,
		"workers": workers,
		"free_people": spare,
		"idle_cells": idle,
	}

# Places or clears a cell outright, keeping the books straight. Not part of playing the
# game - the rules are in apply_command - but tests and the development preview need to
# set a board up, and writing to the arrays by hand would leave the totals lying.
func set_cell(cell: int, owner: int, type: int = Balance.Building.NONE, level: int = 1) -> void:
	_forget(cell)
	owner_of[cell] = owner
	building_at[cell] = type
	level_at[cell] = 0 if type == Balance.Building.NONE else maxi(1, level)
	_remember(cell)

# Recounts from the grid and reports anything the running totals got wrong. Empty means
# the cache is telling the truth. The tests call this after every kind of change.
func verify_totals() -> Array:
	var cached := []
	for p in range(_t_cells.size()):
		cached.append(aggregate(p))
	var sum_before := _grid_sum
	recount()
	var problems: Array = []
	if sum_before != _grid_sum:
		problems.append("grid checksum drifted")
	for p in range(_t_cells.size()):
		var fresh: Dictionary = aggregate(p)
		for key in ["cells", "people", "coin_per_tick", "power_per_tick", "coin_cap",
				"power_cap", "workers", "free_people"]:
			if int((cached[p] as Dictionary)[key]) != int(fresh[key]):
				problems.append("player %d: %s was %d, should be %d" % [p, key,
					int((cached[p] as Dictionary)[key]), int(fresh[key])])
	return problems

# --- Commands ---

static func make_command(type: int, a: int, b: int = 0) -> Dictionary:
	return {"type": type, "a": a, "b": b}

# Returns an empty string on success, or a machine-readable reason for the UI to show.
func apply_command(player: int, cmd: Dictionary) -> String:
	if finished:
		return "match_finished"
	if player < 0 or player >= alive.size() or alive[player] == 0:
		return "not_playing"
	match int(cmd["type"]):
		Command.BUILD:
			return _do_build(player, int(cmd["a"]), int(cmd["b"]))
		Command.DEMOLISH:
			return _do_demolish(player, int(cmd["a"]))
		Command.CAPTURE:
			return _do_capture(player, int(cmd["a"]))
		Command.LAUNCH_SHIP:
			return _do_launch_ship(player, int(cmd["a"]), int(cmd["b"]))
		Command.UPGRADE:
			return _do_upgrade(player, int(cmd["a"]))
	return "unknown_command"

func _do_build(player: int, cell: int, type: int) -> String:
	if cell < 0 or cell >= owner_of.size():
		return "bad_cell"
	if not Balance.BUILDINGS.has(type):
		return "bad_building"
	if owner_of[cell] != player:
		return "not_your_cell"
	if not is_land(cell):
		return "sea_cell"
	if building_at[cell] != Balance.Building.NONE or site_index(cell) >= 0:
		return "cell_occupied"
	var d: Dictionary = Balance.BUILDINGS[type]
	if bool(d["coastal"]) and not touches_sea(cell):
		return "needs_coast"
	if coins[player] < int(d["coin_cost"]):
		return "not_enough_coins"
	if power[player] < int(d["power_cost"]):
		return "not_enough_power"
	# People already promised to work half-built factories are not free, or a player
	# could queue ten of them on the strength of one house.
	if int(d["workers"]) > 0 			and int(aggregate(player)["free_people"]) - promised_workers(player) < int(d["workers"]):
		return "not_enough_people"
	coins[player] -= int(d["coin_cost"])
	power[player] -= int(d["power_cost"])
	sites.append({
		"cell": cell,
		"owner": player,
		"type": type,
		"started": tick_count,
		"ready": tick_count + Balance.build_ticks(type),
	})
	return ""

# How many residents are already spoken for by work in progress.
func promised_workers(player: int) -> int:
	var total := 0
	for site in sites:
		if int(site["owner"]) == player:
			total += int(Balance.BUILDINGS[int(site["type"])]["workers"])
	return total

# Where in `sites` the work on this cell is, or -1 if nothing is being built there.
func site_index(cell: int) -> int:
	for i in range(sites.size()):
		if int(sites[i]["cell"]) == cell:
			return i
	return -1

# How far along the work is, from 0 to 1000. Integers, because the interface is allowed
# to be approximate but the simulation is not.
func site_progress(cell: int) -> int:
	var at := site_index(cell)
	if at < 0:
		return 0
	var site: Dictionary = sites[at]
	var span := maxi(1, int(site["ready"]) - int(site["started"]))
	return clampi((tick_count - int(site["started"])) * 1000 / span, 0, 1000)

func _drop_site(cell: int) -> void:
	var at := site_index(cell)
	if at >= 0:
		sites.remove_at(at)

# Work that has finished this tick turns into buildings. Anything whose cell changed
# hands while it was going up is simply abandoned - it was never built.
func _advance_sites() -> void:
	var kept: Array[Dictionary] = []
	for site in sites:
		var cell := int(site["cell"])
		if int(owner_of[cell]) != int(site["owner"]) or building_at[cell] != Balance.Building.NONE:
			continue
		if tick_count < int(site["ready"]):
			kept.append(site)
			continue
		_forget(cell)
		building_at[cell] = int(site["type"])
		level_at[cell] = 1
		_remember(cell)
	sites = kept

func _do_upgrade(player: int, cell: int) -> String:
	if cell < 0 or cell >= owner_of.size():
		return "bad_cell"
	if owner_of[cell] != player:
		return "not_your_cell"
	var type := int(building_at[cell])
	if type == Balance.Building.NONE:
		return "nothing_to_upgrade"
	var next_level := int(level_at[cell]) + 1
	if next_level > Balance.max_level_of(type):
		return "max_level"
	var coin_cost := Balance.upgrade_coin_cost(type, next_level)
	var power_cost := Balance.upgrade_power_cost(type, next_level)
	if coins[player] < coin_cost:
		return "not_enough_coins"
	if power[player] < power_cost:
		return "not_enough_power"
	coins[player] -= coin_cost
	power[player] -= power_cost
	_forget(cell)
	level_at[cell] = next_level
	_remember(cell)
	return ""

func _do_demolish(player: int, cell: int) -> String:
	if cell < 0 or cell >= owner_of.size():
		return "bad_cell"
	if owner_of[cell] != player:
		return "not_your_cell"
	var pending := site_index(cell)
	if pending >= 0:
		# Calling off the work costs nothing: no bricks have been laid.
		var site: Dictionary = sites[pending]
		var d: Dictionary = Balance.BUILDINGS[int(site["type"])]
		coins[player] += int(d["coin_cost"])
		power[player] += int(d["power_cost"])
		sites.remove_at(pending)
		_clamp_player(player)
		return ""
	var type := int(building_at[cell])
	if type == Balance.Building.NONE:
		return "nothing_to_demolish"
	var invested := Balance.invested_coins(type, maxi(1, int(level_at[cell])))
	_forget(cell)
	building_at[cell] = Balance.Building.NONE
	level_at[cell] = 0
	_remember(cell)
	if type == Balance.Building.PORT:
		_drop_ships_from_port(cell)
	# Refund is applied after the building is gone, so the new (lower) storage cap clamps
	# it - demolishing a bank cannot leave a player over the limit. Upgrades are refunded
	# on the same terms, so levelling a building never traps coins.
	coins[player] += invested * Balance.DEMOLISH_REFUND_PERCENT / 100
	_clamp_player(player)
	return ""

func _do_capture(player: int, cell: int) -> String:
	if cell < 0 or cell >= owner_of.size():
		return "bad_cell"
	if not is_land(cell):
		return "sea_cell"
	if owner_of[cell] == player:
		return "already_yours"
	if not touches_player(cell, player):
		return "not_adjacent"
	if tick_count < capture_ready[player]:
		return "on_cooldown"
	if power[player] < Balance.CAPTURE_POWER_COST:
		return "not_enough_power"
	var defended := int(owner_of[cell]) != NEUTRAL
	var barrier := int(building_at[cell]) == Balance.Building.BARRIER
	power[player] -= Balance.CAPTURE_POWER_COST
	_take_cell(player, cell)
	var cooldown := Balance.CAPTURE_ENEMY_COOLDOWN_TICKS if defended else Balance.CAPTURE_COOLDOWN_TICKS
	# The barrier is bought for exactly this: it does not save the cell, it stalls the
	# advance that was coming through it.
	if barrier:
		cooldown = maxi(cooldown, Balance.BARRIER_COOLDOWN_TICKS)
	capture_ready[player] = tick_count + cooldown
	return ""

# Ticks the player must still wait before the next capture. Drawn by the interface.
func capture_cooldown_left(player: int) -> int:
	if player < 0 or player >= capture_ready.size():
		return 0
	return maxi(0, int(capture_ready[player]) - tick_count)

func _do_launch_ship(player: int, port_cell: int, target: int) -> String:
	if port_cell < 0 or port_cell >= owner_of.size():
		return "bad_cell"
	if target < 0 or target >= owner_of.size():
		return "bad_cell"
	if owner_of[port_cell] != player or building_at[port_cell] != Balance.Building.PORT:
		return "no_port"
	if owner_of[target] == player:
		return "already_yours"
	if not is_land(target):
		return "sea_cell"
	# One ship per port at a time: the port is the vessel, not a spawner.
	for ship in ships:
		if int(ship["port"]) == port_cell:
			return "port_busy"
	if power[player] < Balance.SHIP_POWER_COST:
		return "not_enough_power"
	var path := sea_path(port_cell, target)
	if path.is_empty():
		return "no_sea_route"
	power[player] -= Balance.SHIP_POWER_COST
	ships.append({
		"owner": player,
		"port": port_cell,
		"target": target,
		"path": path,
		"step": 0,
		"ticks": 0,
	})
	return ""

# Ships follow the water. A breadth-first search from the port over sea cells finds the
# shortest way round a headland, so a bay never blocks a landing that is obviously
# possible on the screen.
#
# Neighbours are always walked in the same order, which makes the shortest path a single
# defined answer rather than one of several - the sim would desync otherwise.
# Returns the cells from the port (exclusive) to the target (inclusive), empty if the
# target cannot be reached by sea.
func sea_path(from: int, to: int) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if from == to or not is_land(to):
		return empty
	var total := owner_of.size()
	var came_from := PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)
	var seen := PackedByteArray()
	seen.resize(total)
	seen.fill(0)
	seen[from] = 1
	var queue := PackedInt32Array([from])
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for n in neighbours(cell):
			if seen[n] == 1:
				continue
			# The target counts only when we arrive from open water: a ship has to
			# actually cross something, it is not a way to step onto the next cell.
			if n == to:
				if cell == from:
					continue
				came_from[n] = cell
				return _trace_path(came_from, from, to)
			if terrain[n] != WorldGen.SEA:
				continue
			seen[n] = 1
			came_from[n] = cell
			queue.append(n)
	return empty

func _trace_path(came_from: PackedInt32Array, from: int, to: int) -> PackedInt32Array:
	var reversed := PackedInt32Array()
	var cell := to
	while cell != from and cell >= 0:
		reversed.append(cell)
		cell = came_from[cell]
	var path := PackedInt32Array()
	for i in range(reversed.size() - 1, -1, -1):
		path.append(reversed[i])
	return path

# Every shore this port can put a ship on. One search answers it for the whole map, so
# the interface can highlight the real options instead of guessing at them.
#
# assume_port answers the same question for a cell that has no port yet, which is how the
# bot decides whether one is worth building - the same search either way, so what it
# plans for and what it later gets cannot disagree.
func reachable_shores(port_cell: int, assume_port: bool = false) -> PackedInt32Array:
	var found := PackedInt32Array()
	if not assume_port and building_at[port_cell] != Balance.Building.PORT:
		return found
	var total := owner_of.size()
	var seen := PackedByteArray()
	seen.resize(total)
	seen.fill(0)
	seen[port_cell] = 1
	var queue := PackedInt32Array()
	for n in neighbours(port_cell):
		if terrain[n] == WorldGen.SEA:
			seen[n] = 1
			queue.append(n)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for n in neighbours(cell):
			if seen[n] == 1:
				continue
			seen[n] = 1
			if terrain[n] == WorldGen.SEA:
				queue.append(n)
			else:
				found.append(n)
	return found

func _drop_ships_from_port(port_cell: int) -> void:
	var kept: Array[Dictionary] = []
	for ship in ships:
		if int(ship["port"]) != port_cell:
			kept.append(ship)
	ships = kept

# --- Tick ---

func tick() -> void:
	if finished:
		return
	_advance_ships()
	_accrue_income()
	tick_count += 1
	# Work is finished after the tick the clock has just moved to, so that ordering a
	# nine second building and waiting nine seconds gets you a building.
	_advance_sites()
	_check_end()

func _advance_ships() -> void:
	var kept: Array[Dictionary] = []
	for ship in ships:
		ship["ticks"] = int(ship["ticks"]) + 1
		if int(ship["ticks"]) < Balance.SHIP_TICKS_PER_CELL:
			kept.append(ship)
			continue
		ship["ticks"] = 0
		ship["step"] = int(ship["step"]) + 1
		var path: PackedInt32Array = ship["path"]
		if int(ship["step"]) < path.size():
			kept.append(ship)
			continue
		# Arrived. A landing takes the cell outright, exactly like an overland capture.
		var target := int(ship["target"])
		var owner_id := int(ship["owner"])
		if alive[owner_id] == 1 and is_land(target) and owner_of[target] != owner_id:
			_take_cell(owner_id, target)
	ships = kept

func _accrue_income() -> void:
	for p in range(alive.size()):
		if alive[p] == 0:
			continue
		var agg := aggregate(p)
		coins[p] = mini(coins[p] + int(agg["coin_per_tick"]), int(agg["coin_cap"]))
		power[p] = mini(power[p] + int(agg["power_per_tick"]), int(agg["power_cap"]))

func _take_cell(player: int, cell: int) -> void:
	var previous := int(owner_of[cell])
	if building_at[cell] == Balance.Building.PORT:
		_drop_ships_from_port(cell)
	# Whatever stood there is levelled, and any work in progress is abandoned; the
	# attacker gets bare ground.
	_drop_site(cell)
	_forget(cell)
	building_at[cell] = Balance.Building.NONE
	level_at[cell] = 0
	owner_of[cell] = player
	_remember(cell)
	if previous != NEUTRAL:
		_clamp_player(previous)
		if int(aggregate(previous)["cells"]) == 0:
			alive[previous] = 0
	_check_end()

# Losing buildings can push a player over a storage limit that just shrank.
func _clamp_player(player: int) -> void:
	var agg := aggregate(player)
	coins[player] = mini(coins[player], int(agg["coin_cap"]))
	power[player] = mini(power[player], int(agg["power_cap"]))

func _check_end() -> void:
	if finished:
		return
	# Free play is a world, not a match: nobody to eliminate and no clock to run out.
	if is_free_play():
		return
	var living: Array[int] = []
	for p in range(alive.size()):
		if alive[p] == 1:
			living.append(p)
	if living.size() <= 1:
		finished = true
		winner = living[0] if living.size() == 1 else -1
		return
	var limit := match_limit_ticks()
	if limit > 0 and tick_count >= limit:
		finished = true
		var best := -1
		var best_cells := -1
		var tied := false
		for p in living:
			var c := int(aggregate(p)["cells"])
			if c > best_cells:
				best_cells = c
				best = p
				tied = false
			elif c == best_cells:
				tied = true
		winner = -1 if tied else best

# --- Snapshots: the host's answer to a client that has drifted out of step. ---

func snapshot() -> Dictionary:
	var ship_copy: Array[Dictionary] = []
	for ship in ships:
		ship_copy.append(ship.duplicate(true))
	var site_copy: Array[Dictionary] = []
	for site in sites:
		site_copy.append(site.duplicate(true))
	return {
		"settings": settings.to_dict() if settings != null else {},
		"seed": map_seed,
		"terrain": terrain.duplicate(),
		"owner": owner_of.duplicate(),
		"building": building_at.duplicate(),
		"level": level_at.duplicate(),
		"coins": coins.duplicate(),
		"power": power.duplicate(),
		"alive": alive.duplicate(),
		"capture_ready": capture_ready.duplicate(),
		"region": player_region.duplicate(),
		"tint": player_tint.duplicate(),
		"ships": ship_copy,
		"sites": site_copy,
		"tick": tick_count,
		"finished": finished,
		"winner": winner,
	}

# by MatyanKass
static func from_snapshot(data: Dictionary) -> GameState:
	var s := GameState.new()
	s.settings = WorldSettings.from_dict(data.get("settings", {}))
	s.map_seed = int(data["seed"])
	s.width = s.settings.width
	s.height = s.settings.height
	s.terrain = data["terrain"]
	s.owner_of = data["owner"]
	s.building_at = data["building"]
	s.level_at = data["level"]
	s.coins = data["coins"]
	s.power = data["power"]
	s.alive = data["alive"]
	s.capture_ready = data["capture_ready"]
	# Saves written before players had faces carry no colours, and a world from one of
	# those opens with the interface's own pens rather than with nothing at all.
	s.player_region = data.get("region", PackedByteArray())
	s.player_tint = data.get("tint", PackedInt32Array())
	if s.player_region.size() != s.alive.size():
		s.player_region = PackedByteArray()
		s.player_region.resize(s.alive.size())
		s.player_region.fill(NO_REGION)
	if s.player_tint.size() != s.alive.size():
		s.player_tint = PackedInt32Array()
		s.player_tint.resize(s.alive.size())
		s.player_tint.fill(0)
	s.ships = []
	for ship in data["ships"]:
		s.ships.append((ship as Dictionary).duplicate(true))
	s.sites = []
	for site in data.get("sites", []):
		s.sites.append((site as Dictionary).duplicate(true))
	s.tick_count = int(data["tick"])
	s.finished = bool(data["finished"])
	s.winner = int(data["winner"])
	# A snapshot is the one place the totals are counted the slow way: it happens once,
	# when a client has drifted, and it is the cheapest way to be certain they are right.
	s.recount()
	return s

# --- Desync detection: FNV-1a over everything that defines the state. ---

func state_hash() -> int:
	# FNV-1a offset basis, trimmed to 63 bits: GDScript integers are signed 64-bit and
	# the textbook 0xCBF29CE484222325 does not fit. Every step is masked the same way.
	var h := 0x4BF29CE484222325
	h = _hash_int(h, Authorship.salt())
	h = _hash_int(h, tick_count)
	h = _hash_int(h, map_seed)
	# The grid goes in as its rolling checksum. Reading a million cells here would have
	# cost more than the tick that produced them.
	h = _hash_int(h, _grid_sum)
	for p in range(coins.size()):
		h = _hash_int(h, coins[p])
		h = _hash_int(h, power[p])
		h = _hash_int(h, alive[p])
		h = _hash_int(h, capture_ready[p])
	for site in sites:
		h = _hash_int(h, int(site["cell"]))
		h = _hash_int(h, int(site["type"]))
		h = _hash_int(h, int(site["ready"]))
	for ship in ships:
		h = _hash_int(h, int(ship["owner"]))
		h = _hash_int(h, int(ship["port"]))
		h = _hash_int(h, int(ship["target"]))
		h = _hash_int(h, int(ship["step"]))
		h = _hash_int(h, int(ship["ticks"]))
	return h

func _hash_int(h: int, value: int) -> int:
	for shift in [0, 8, 16, 24, 32, 40, 48, 56]:
		h = h ^ ((value >> shift) & 0xFF)
		h = (h * 0x100000001B3) & 0x7FFFFFFFFFFFFFFF
	return h
