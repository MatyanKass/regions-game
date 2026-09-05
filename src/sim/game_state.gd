# The whole game. Pure data plus a tick function - no nodes, no rendering, no networking.
#
# Both devices run this class over the same command stream and must end up with an
# identical state_hash() every tick. Rules for keeping that true:
#   * integers only, never float;
#   * never iterate a Dictionary whose insertion order could differ;
#   * every value that can be derived from the grid is derived, never cached, so the
#     grid stays the single source of truth and caches cannot drift apart.
class_name GameState
extends RefCounted

enum Command { BUILD, DEMOLISH, CAPTURE, LAUNCH_SHIP }

const NEUTRAL := 255

var map_seed: int
var width: int
var height: int
var terrain: PackedByteArray      # WorldGen.LAND / WorldGen.SEA
var owner_of: PackedByteArray     # player index, or NEUTRAL
var building_at: PackedByteArray  # Balance.Building
var coins: PackedInt64Array
var power: PackedInt64Array
var alive: PackedByteArray
var ships: Array[Dictionary] = []
var tick_count: int = 0
var finished: bool = false
var winner: int = -1

static func create(seed_value: int, player_count: int = 2) -> GameState:
	var s := GameState.new()
	var world := WorldGen.generate(seed_value, player_count)
	s.map_seed = seed_value
	s.width = Balance.MAP_WIDTH
	s.height = Balance.MAP_HEIGHT
	s.terrain = world["terrain"]
	var total := s.width * s.height
	s.owner_of = PackedByteArray()
	s.owner_of.resize(total)
	s.owner_of.fill(NEUTRAL)
	s.building_at = PackedByteArray()
	s.building_at.resize(total)
	s.building_at.fill(Balance.Building.NONE)
	s.coins = PackedInt64Array()
	s.power = PackedInt64Array()
	s.alive = PackedByteArray()
	var starts: PackedInt32Array = world["starts"]
	for p in range(player_count):
		s.coins.append(Balance.START_COINS)
		s.power.append(Balance.START_POWER)
		s.alive.append(1)
		s.owner_of[starts[p]] = p
	return s

# --- Grid helpers ---

func index_of(x: int, y: int) -> int:
	return x + y * width

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func is_land(cell: int) -> bool:
	return terrain[cell] == WorldGen.LAND

func neighbours(cell: int) -> Array[int]:
	var x := cell % width
	var y := cell / width
	var out: Array[int] = []
	if x > 0:
		out.append(cell - 1)
	if x < width - 1:
		out.append(cell + 1)
	if y > 0:
		out.append(cell - width)
	if y < height - 1:
		out.append(cell + width)
	return out

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
	var cells := 0
	var coin_per_tick := 0
	var power_per_tick := 0
	var coin_cap := Balance.BASE_COIN_CAP
	var power_cap := Balance.BASE_POWER_CAP
	var people := 0
	var workers := 0
	for i in range(owner_of.size()):
		if owner_of[i] != player:
			continue
		cells += 1
		var b := int(building_at[i])
		if b == Balance.Building.NONE:
			continue
		var d: Dictionary = Balance.BUILDINGS[b]
		coin_per_tick += int(d["coin_per_tick"])
		power_per_tick += int(d["power_per_tick"])
		coin_cap += int(d["coin_cap"])
		power_cap += int(d["power_cap"])
		people += int(d["people"])
		workers += int(d["workers"])
	# The flat base income is what keeps a one-cell player in the game, so it is tied
	# to owning territory at all rather than to any building.
	if cells > 0:
		coin_per_tick += Balance.BASE_COIN_PER_TICK
		power_per_tick += Balance.BASE_POWER_PER_TICK
	return {
		"cells": cells,
		"coin_per_tick": coin_per_tick,
		"power_per_tick": power_per_tick,
		"coin_cap": coin_cap,
		"power_cap": power_cap,
		"people": people,
		"workers": workers,
		"free_people": people - workers,
	}

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
	if building_at[cell] != Balance.Building.NONE:
		return "cell_occupied"
	var d: Dictionary = Balance.BUILDINGS[type]
	if bool(d["coastal"]) and not touches_sea(cell):
		return "needs_coast"
	if coins[player] < int(d["coin_cost"]):
		return "not_enough_coins"
	if power[player] < int(d["power_cost"]):
		return "not_enough_power"
	if int(d["workers"]) > 0 and int(aggregate(player)["free_people"]) < int(d["workers"]):
		return "not_enough_people"
	coins[player] -= int(d["coin_cost"])
	power[player] -= int(d["power_cost"])
	building_at[cell] = type
	return ""

func _do_demolish(player: int, cell: int) -> String:
	if cell < 0 or cell >= owner_of.size():
		return "bad_cell"
	if owner_of[cell] != player:
		return "not_your_cell"
	var type := int(building_at[cell])
	if type == Balance.Building.NONE:
		return "nothing_to_demolish"
	var d: Dictionary = Balance.BUILDINGS[type]
	building_at[cell] = Balance.Building.NONE
	if type == Balance.Building.PORT:
		_drop_ships_from_port(cell)
	# Refund is applied after the building is gone, so the new (lower) storage cap
	# clamps it - demolishing a bank cannot leave a player over the limit.
	coins[player] += int(d["coin_cost"]) * Balance.DEMOLISH_REFUND_PERCENT / 100
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
	if power[player] < Balance.CAPTURE_POWER_COST:
		return "not_enough_power"
	power[player] -= Balance.CAPTURE_POWER_COST
	_take_cell(player, cell)
	return ""

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
	# Whatever stood there is levelled; the attacker gets bare ground.
	building_at[cell] = Balance.Building.NONE
	owner_of[cell] = player
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
	var living: Array[int] = []
	for p in range(alive.size()):
		if alive[p] == 1:
			living.append(p)
	if living.size() <= 1:
		finished = true
		winner = living[0] if living.size() == 1 else -1
		return
	if tick_count >= Balance.MATCH_LIMIT_TICKS:
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
	return {
		"seed": map_seed,
		"terrain": terrain.duplicate(),
		"owner": owner_of.duplicate(),
		"building": building_at.duplicate(),
		"coins": coins.duplicate(),
		"power": power.duplicate(),
		"alive": alive.duplicate(),
		"ships": ship_copy,
		"tick": tick_count,
		"finished": finished,
		"winner": winner,
	}

static func from_snapshot(data: Dictionary) -> GameState:
	var s := GameState.new()
	s.map_seed = int(data["seed"])
	s.width = Balance.MAP_WIDTH
	s.height = Balance.MAP_HEIGHT
	s.terrain = data["terrain"]
	s.owner_of = data["owner"]
	s.building_at = data["building"]
	s.coins = data["coins"]
	s.power = data["power"]
	s.alive = data["alive"]
	s.ships = []
	for ship in data["ships"]:
		s.ships.append((ship as Dictionary).duplicate(true))
	s.tick_count = int(data["tick"])
	s.finished = bool(data["finished"])
	s.winner = int(data["winner"])
	return s

# --- Desync detection: FNV-1a over everything that defines the state. ---

func state_hash() -> int:
	# FNV-1a offset basis, trimmed to 63 bits: GDScript integers are signed 64-bit and
	# the textbook 0xCBF29CE484222325 does not fit. Every step is masked the same way.
	var h := 0x4BF29CE484222325
	h = _hash_int(h, tick_count)
	h = _hash_int(h, map_seed)
	for i in range(owner_of.size()):
		h = _hash_int(h, owner_of[i])
		h = _hash_int(h, building_at[i])
	for p in range(coins.size()):
		h = _hash_int(h, coins[p])
		h = _hash_int(h, power[p])
		h = _hash_int(h, alive[p])
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
