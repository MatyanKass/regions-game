# The practice opponent.
#
# One decision function over the shared GameState, with no nodes, no timers and no
# networking, so a test can drive it exactly the way the match clock does.
#
# The bot never touches the state: it answers with commands, and those go through
# apply_command like a tap on the screen. Whatever a player is not allowed to do, the
# bot cannot do either.
#
# Every choice is integer arithmetic over a seeded generator, so a practice match with
# the same seed plays out the same way twice - handy for a test, and it keeps the bot
# usable from the host of a lockstep match should a third player ever be a robot.
class_name BotPlayer
extends RefCounted

enum Level { EASY, NORMAL, HARD }

# act_every    - ticks between decisions; this is the bot's reaction time
# power_slack  - how much power over the price it wants before spending it on land
# invest       - whether it saves power for a building instead of spending it on land
# use_ships    - whether it ever thinks about the far shore
# pressure     - whether it pushes towards the enemy and takes built-up cells
# noise        - jitter added to every score, which is what makes an easy bot sloppy
#
# The difference that matters is invest: a bot that spends every point of power the
# moment it has ten of them expands quickly for two minutes and then stops growing,
# which is exactly the mistake a new player makes.
const LEVELS := {
	Level.EASY: {
		"name": "easy", "act_every": 25, "power_slack": 2, "invest": false,
		"use_ships": false, "pressure": false, "noise": 9,
	},
	Level.NORMAL: {
		"name": "normal", "act_every": 12, "power_slack": 1, "invest": true,
		"use_ships": true, "pressure": true, "noise": 3,
	},
	Level.HARD: {
		"name": "hard", "act_every": 6, "power_slack": 1, "invest": true,
		"use_ships": true, "pressure": true, "noise": 0,
	},
}

# What taking a cell away from the enemy is worth beyond the ground itself: capturing
# levels whatever stood there, so the expensive buildings are the ones worth hitting.
const BUILDING_VALUE := {
	Balance.Building.NONE: 0,
	Balance.Building.FACTORY: 8,
	Balance.Building.HOUSE: 6,
	Balance.Building.BANK: 12,
	Balance.Building.BARRACKS: 10,
	Balance.Building.MILITARY_BASE: 16,
	Balance.Building.PORT: 10,
}

# How long the answer to "is a port worth it here" is kept. The map does not change,
# only the borders do, and a breadth-first search per coastal cell is the one expensive
# question the bot asks.
const PORT_RECHECK_TICKS := 300

var player: int
var level: int
var focus_cell := -1   # where the bot last acted, so the interface can look over its shoulder

var _cfg: Dictionary
var _rng: SimRng
var _power_reserve := 0   # power held back this turn for a building the bot is saving for
var _keep_coast_free := false   # true while a port is still to be built somewhere
var _last_tick := -1000
var _port_wanted := false
var _port_checked_tick := -1000

func _init(player_index: int, difficulty: int = Level.NORMAL, seed_value: int = 1) -> void:
	player = player_index
	level = difficulty if LEVELS.has(difficulty) else Level.NORMAL
	_cfg = LEVELS[level]
	_rng = SimRng.new(seed_value ^ (0x5BF03 * (player_index + 1)))

func level_name() -> String:
	return str(_cfg["name"])

# The whole of the bot. Returns the commands it wants played this tick - at most one
# building and one move, so it develops and expands in the same breath the way a player
# does, and never dumps a burst of ten actions on the same second.
func take_turn(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or state.finished:
		return out
	if player < 0 or player >= state.alive.size() or state.alive[player] == 0:
		return out
	if state.tick_count - _last_tick < int(_cfg["act_every"]):
		return out
	_last_tick = state.tick_count

	var agg := state.aggregate(player)
	var coins := int(state.coins[player])
	var power := int(state.power[player])

	_power_reserve = 0
	var build := _plan_build(state, agg, coins, power)
	if not build.is_empty():
		var d: Dictionary = Balance.BUILDINGS[int(build["b"])]
		coins -= int(d["coin_cost"])
		power -= int(d["power_cost"])
		out.append(build)
	# Never hold back so much that expansion stops altogether: the whole point of the
	# saving is to capture faster afterwards.
	_power_reserve = clampi(_power_reserve, 0,
		int(agg["power_cap"]) - Balance.CAPTURE_POWER_COST)
	var move := _plan_move(state, power - _power_reserve)
	if not move.is_empty():
		out.append(move)

	if not out.is_empty():
		focus_cell = int(out[out.size() - 1]["a"])
	return out

# --- Building ---------------------------------------------------------------------

func _plan_build(state: GameState, agg: Dictionary, coins: int, power: int) -> Dictionary:
	for type in _build_order(state, agg, coins, power):
		if not _affordable(type, agg, coins, power):
			# The coins are there but the power is not. Without holding that power back
			# the bot would spend every point on land the moment it had ten of them, and
			# never afford the base that doubles the rate it earns them at - the greedy
			# trap, and the one thing that separates this from the self-play robot.
			if bool(_cfg["invest"]) and _power_reserve == 0 \
					and coins >= int(Balance.BUILDINGS[type]["coin_cost"]) \
					and power < int(Balance.BUILDINGS[type]["power_cost"]):
				_power_reserve = int(Balance.BUILDINGS[type]["power_cost"])
			continue
		var cell := _place_for(state, type)
		if cell < 0:
			continue
		return GameState.make_command(GameState.Command.BUILD, cell, type)
	return {}

# What the bot would like to own next, best first. Everything here is a want, not a
# purchase: whatever it cannot pay for is skipped, so it never sits on its coins waiting
# for the one building at the top of the list.
func _build_order(state: GameState, agg: Dictionary, coins: int, power: int) -> Array[int]:
	var cells := int(agg["cells"])
	var counts := _building_counts(state)
	var want: Array[int] = []

	var bases := int(counts[Balance.Building.MILITARY_BASE])
	var factories := int(counts[Balance.Building.FACTORY])

	# Power is what buys land, and a military base pays its own price back in fifteen
	# seconds, so the first coins of a match go here. One base per five cells keeps the
	# rate of expansion tied to how much there is to expand from - but never more bases
	# than factories, or the whole match is paid for out of the flat base income and the
	# bot stops growing the moment the map gets big.
	if bases < 1 + cells / 5 and bases <= factories:
		want.append(Balance.Building.MILITARY_BASE)

	# A factory needs somebody to work in it, and a house is only worth its coins when
	# a factory is waiting for the people it brings - so the pair is planned together.
	if factories < 1 + cells / 2:
		if int(agg["free_people"]) > 0:
			want.append(Balance.Building.FACTORY)
		elif coins >= int(Balance.BUILDINGS[Balance.Building.HOUSE]["coin_cost"]) \
				+ int(Balance.BUILDINGS[Balance.Building.FACTORY]["coin_cost"]):
			want.append(Balance.Building.HOUSE)

	# A port is only ever worth it when there is a shore out there that walking cannot
	# reach anyway. Until there is one, the last free cell on the coast is left alone:
	# a bot that builds a bank on it can fill its island and then never leave it.
	_keep_coast_free = bool(_cfg["use_ships"]) and int(counts[Balance.Building.PORT]) == 0
	if _keep_coast_free and _wants_port(state, coins):
		want.append(Balance.Building.PORT)

	# Storage is bought when income actually starts spilling over the edge, never before:
	# a bank that is not overflowing is eighty coins doing nothing.
	if coins >= int(agg["coin_cap"]):
		want.append(Balance.Building.BANK)
	# Barracks only raise the ceiling on power, so they are worth their coins when power
	# is spilling over and there is somewhere to spend it. Boxed in with nothing to take,
	# the answer is a port, not a bigger pile of unusable power.
	if power >= int(agg["power_cap"]) and _has_capture_target(state):
		want.append(Balance.Building.BARRACKS)
	return want

func _has_capture_target(state: GameState) -> bool:
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) == player or not state.is_land(i):
			continue
		if state.touches_player(i, player):
			return true
	return false

func _building_counts(state: GameState) -> Dictionary:
	var counts := {}
	for type in Balance.BUILDINGS:
		counts[type] = 0
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) != player:
			continue
		var b := int(state.building_at[i])
		if counts.has(b):
			counts[b] = int(counts[b]) + 1
	return counts

# Mirrors the simulation's own conditions. Being wrong here only costs a refused command,
# but a bot that keeps asking for what it cannot have would never get anything built.
func _affordable(type: int, agg: Dictionary, coins: int, power: int) -> bool:
	var d: Dictionary = Balance.BUILDINGS[type]
	if coins < int(d["coin_cost"]) or power < int(d["power_cost"]):
		return false
	if int(d["workers"]) > 0 and int(agg["free_people"]) < int(d["workers"]):
		return false
	return true

# Buildings are levelled by whoever takes the cell, so they go as far from the enemy as
# the territory allows: a bank on the front line is a gift.
func _place_for(state: GameState, type: int) -> int:
	var coastal := bool(Balance.BUILDINGS[type]["coastal"])
	var free_coast := 0
	if _keep_coast_free and not coastal:
		free_coast = _free_coastal_cells(state)
	var best := -1
	var best_score := -0x7FFFFFFF
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) != player:
			continue
		if int(state.building_at[i]) != Balance.Building.NONE or not state.is_land(i):
			continue
		if coastal and not state.touches_sea(i):
			continue
		# The last piece of coast belongs to the port that is not built yet.
		if free_coast == 1 and not coastal and state.touches_sea(i):
			continue
		var score := _cell_safety(state, i) + _noise()
		if score > best_score:
			best_score = score
			best = i
	return best

func _free_coastal_cells(state: GameState) -> int:
	var count := 0
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) != player or not state.is_land(i):
			continue
		if int(state.building_at[i]) == Balance.Building.NONE and state.touches_sea(i):
			count += 1
	return count

func _cell_safety(state: GameState, cell: int) -> int:
	var score := 0
	for n in state.neighbours(cell):
		var owner_id := int(state.owner_of[n])
		if owner_id == player:
			score += 3
		elif owner_id != GameState.NEUTRAL:
			score -= 8          # the enemy is one capture away from levelling this
		elif not state.is_land(n):
			score += 1          # a coastline can only be crossed by ship
	return score

# --- Moves: capture on foot, or land on a shore ------------------------------------

func _plan_move(state: GameState, power: int) -> Dictionary:
	var best := -1
	var best_score := -0x7FFFFFFF
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) == player or not state.is_land(i):
			continue
		if not state.touches_player(i, player):
			continue
		var score := _capture_score(state, i)
		if score > best_score:
			best_score = score
			best = i
	if best >= 0 and power >= Balance.CAPTURE_POWER_COST * int(_cfg["power_slack"]):
		return GameState.make_command(GameState.Command.CAPTURE, best)
	if bool(_cfg["use_ships"]):
		return _plan_ship(state, power, best < 0)
	return {}

func _capture_score(state: GameState, cell: int) -> int:
	var owner_id := int(state.owner_of[cell])
	var mine := 0
	var open := 0
	var enemy_side := 0
	for n in state.neighbours(cell):
		var o := int(state.owner_of[n])
		if o == player:
			mine += 1
		elif o != GameState.NEUTRAL:
			enemy_side += 1
		elif state.is_land(n):
			open += 1
	# A cell held on several sides is a cell that is hard to take back, and one with open
	# ground behind it is the next few cells as well. A cell sticking into their half is
	# the opposite: it costs ten power, they take it straight back for ten of theirs, and
	# the bot that keeps buying those trades runs out of power and then out of country.
	var score := 10 + mine * 4 + open * 2 - enemy_side * 3
	if owner_id != GameState.NEUTRAL:
		# Taking built ground costs the other side the building as well as the cell, so
		# the border moves twice as far for the same ten power.
		score += 18 + int(BUILDING_VALUE.get(int(state.building_at[cell]), 0))
	if enemy_side > 0 and bool(_cfg["pressure"]):
		score += 6   # meet them at the border rather than growing the other way
	return score + _noise()

# Ships are for what walking cannot reach: a shore across a bay, or an island the border
# will never grow to. Landing costs the same power as a capture but takes time, so it is
# only worth it when the land route is out of options or power is piling up unspent.
func _plan_ship(state: GameState, power: int, urgent: bool) -> Dictionary:
	var need := Balance.SHIP_POWER_COST * (1 if urgent else 2)
	if power < need:
		return {}
	for port in range(state.owner_of.size()):
		if int(state.owner_of[port]) != player:
			continue
		if int(state.building_at[port]) != Balance.Building.PORT:
			continue
		if _port_busy(state, port):
			continue
		var best := -1
		var best_score := -0x7FFFFFFF
		for cell in state.reachable_shores(port):
			if int(state.owner_of[cell]) == player:
				continue
			# Anything the border already touches is cheaper to walk into.
			if not urgent and state.touches_player(cell, player):
				continue
			var score := _landing_score(state, cell)
			if score > best_score:
				best_score = score
				best = cell
		if best >= 0:
			return GameState.make_command(GameState.Command.LAUNCH_SHIP, port, best)
	return {}

func _landing_score(state: GameState, cell: int) -> int:
	var score := 10
	var open := 0
	for n in state.neighbours(cell):
		if int(state.owner_of[n]) == GameState.NEUTRAL and state.is_land(n):
			open += 1
	# A landing is worth what grows out of it, so the beach with a continent behind it
	# beats the rock in the middle of the water.
	score += open * 6
	if int(state.owner_of[cell]) != GameState.NEUTRAL:
		score += 20 + int(BUILDING_VALUE.get(int(state.building_at[cell]), 0))
	return score + _noise()

func _port_busy(state: GameState, port_cell: int) -> bool:
	for ship in state.ships:
		if int(ship["port"]) == port_cell:
			return true
	return false

# Is there anywhere out there a ship could take us that the border cannot? Asked of the
# cells a port could stand on, and only when one could be paid for; the answer is kept
# for a while because it is the one search in the bot that is not cheap.
func _wants_port(state: GameState, coins: int) -> bool:
	# Only the coins are asked about here: the power comes from the reserve above, which
	# only starts saving once the port is something the bot wants.
	if coins < int(Balance.BUILDINGS[Balance.Building.PORT]["coin_cost"]):
		return false
	if state.tick_count - _port_checked_tick < PORT_RECHECK_TICKS:
		return _port_wanted
	_port_checked_tick = state.tick_count
	_port_wanted = false
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) != player or not state.is_land(i):
			continue
		if int(state.building_at[i]) != Balance.Building.NONE or not state.touches_sea(i):
			continue
		for cell in state.reachable_shores(i, true):
			if int(state.owner_of[cell]) != player and not state.touches_player(cell, player):
				_port_wanted = true
				return true
		break   # one coastal cell answers for the whole coastline it sits on
	return false

# Jitter, so an easy bot picks the second-best cell often enough to be beatable and a
# hard one never does.
func _noise() -> int:
	var span := int(_cfg["noise"])
	if span <= 0:
		return 0
	return _rng.next_range(span * 2 + 1) - span
