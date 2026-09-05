# The practice opponent. A bot goes wrong quietly - it sits on a full purse, it keeps
# asking for what the rules forbid, or it is simply no trouble to play against - so the
# tests here play whole matches headless and look at how they went.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func expect_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (got %s, expected %s)" % [message, actual, expected])

# --- The match driver -------------------------------------------------------------
#
# One brain per seat, each a Callable(state) that answers with the commands it wants.
# Commands go through apply_command, exactly as a tap or a network batch would, so a
# refusal here is a refusal in a real match.
func _play(state: GameState, brains: Array, ticks: int) -> Dictionary:
	var refused: Dictionary = {}
	for i in range(ticks):
		for player in range(brains.size()):
			var brain: Callable = brains[player]
			if brain.is_null():
				continue
			for cmd in brain.call(state):
				var reason: String = state.apply_command(player, cmd)
				if not reason.is_empty():
					refused[reason] = int(refused.get(reason, 0)) + 1
		state.tick()
		if state.finished:
			break
	return refused

func _bot_brain(bot: BotPlayer) -> Callable:
	return func(state: GameState) -> Array[Dictionary]: return bot.take_turn(state)

# The opener the self-play robot plays: houses, then factories, then push the border.
# It is the yardstick - a bot worth adding has to beat the simple greed we already had.
func _greedy_brain(player: int) -> Callable:
	return func(state: GameState) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		if state.tick_count % 6 != 0:
			return out
		var agg := state.aggregate(player)
		var empty := -1
		for i in range(state.owner_of.size()):
			if int(state.owner_of[i]) == player and int(state.building_at[i]) == Balance.Building.NONE:
				empty = i
				break
		if empty >= 0:
			if int(state.coins[player]) >= int(Balance.BUILDINGS[Balance.Building.HOUSE]["coin_cost"]) \
					and int(agg["people"]) < 6:
				out.append(GameState.make_command(GameState.Command.BUILD, empty, Balance.Building.HOUSE))
				return out
			if int(agg["free_people"]) > 0 \
					and int(state.coins[player]) >= int(Balance.BUILDINGS[Balance.Building.FACTORY]["coin_cost"]):
				out.append(GameState.make_command(GameState.Command.BUILD, empty, Balance.Building.FACTORY))
				return out
		if int(state.power[player]) >= Balance.CAPTURE_POWER_COST:
			for i in range(state.owner_of.size()):
				if state.is_land(i) and int(state.owner_of[i]) != player and state.touches_player(i, player):
					out.append(GameState.make_command(GameState.Command.CAPTURE, i))
					break
		return out

func _cells(state: GameState, player: int) -> int:
	return int(state.aggregate(player)["cells"])

func _buildings(state: GameState, player: int) -> int:
	var count := 0
	for i in range(state.building_at.size()):
		if int(state.owner_of[i]) == player and int(state.building_at[i]) != Balance.Building.NONE:
			count += 1
	return count

# --- Tests ------------------------------------------------------------------------

func test_bot_only_ever_plays_legal_moves() -> void:
	var state := GameState.create(4242)
	var bot := BotPlayer.new(1, BotPlayer.Level.HARD, 4242)
	var refused := _play(state, [_greedy_brain(0), _bot_brain(bot)], 120 * Balance.TICKS_PER_SECOND)
	expect(refused.is_empty(), "the bot had commands refused: %s" % refused)

func test_bot_develops_instead_of_hoarding() -> void:
	var state := GameState.create(77)
	var bot := BotPlayer.new(1, BotPlayer.Level.NORMAL, 77)
	_play(state, [Callable(), _bot_brain(bot)], 180 * Balance.TICKS_PER_SECOND)
	expect(_cells(state, 1) >= 10, "after three minutes the bot should hold ground, has %d cells" % _cells(state, 1))
	expect(_buildings(state, 1) >= 3, "the bot should have built something, has %d buildings" % _buildings(state, 1))
	# Income that hits the ceiling is income thrown away, and a bot with land to build on
	# has no excuse for it.
	var agg := state.aggregate(1)
	expect(int(state.coins[1]) < int(agg["coin_cap"]),
		"the bot is sitting on a full purse instead of spending it")
	expect(int(agg["power_per_tick"]) > Balance.BASE_POWER_PER_TICK,
		"the bot never raised its power income above the flat base rate")

func test_bot_beats_the_greedy_opener() -> void:
	for seed_value in [11, 909, 30001]:
		var state := GameState.create(seed_value)
		var bot := BotPlayer.new(1, BotPlayer.Level.HARD, seed_value)
		_play(state, [_greedy_brain(0), _bot_brain(bot)], 180 * Balance.TICKS_PER_SECOND)
		expect(_cells(state, 1) > _cells(state, 0),
			"on seed %d the bot took %d cells against greed's %d" % [
				seed_value, _cells(state, 1), _cells(state, 0)])

func test_an_easy_bot_is_easier_than_a_hard_one() -> void:
	var beaten := 0
	for seed_value in [5, 6, 7]:
		var state := GameState.create(seed_value)
		var easy := BotPlayer.new(0, BotPlayer.Level.EASY, seed_value)
		var hard := BotPlayer.new(1, BotPlayer.Level.HARD, seed_value)
		# Long enough for the two of them to actually meet: until the borders touch, both
		# are only racing the map.
		_play(state, [_bot_brain(easy), _bot_brain(hard)], 600 * Balance.TICKS_PER_SECOND)
		if _cells(state, 1) > _cells(state, 0):
			beaten += 1
	expect_eq(beaten, 3, "the hard bot should outgrow the easy one on every seed")

func test_bot_takes_to_the_water_when_the_land_runs_out() -> void:
	var state := _island_map()
	var bot := BotPlayer.new(1, BotPlayer.Level.HARD, 3)
	var sailed := false
	for i in range(300 * Balance.TICKS_PER_SECOND):
		for cmd in bot.take_turn(state):
			state.apply_command(1, cmd)
		state.tick()
		if not state.ships.is_empty():
			sailed = true
		if _far_island_cells(state) > 0:
			break
	expect(sailed, "boxed in on its island, the bot never built a port and sailed")
	expect(_far_island_cells(state) > 0, "the bot never landed on the far island")

func test_an_eliminated_bot_says_nothing() -> void:
	var state := GameState.create(9)
	state.alive[1] = 0
	var bot := BotPlayer.new(1, BotPlayer.Level.HARD, 9)
	expect(bot.take_turn(state).is_empty(), "a bot with no state left must stop playing")

# Two small islands and a rock. The bot starts alone on one island: it can grow to fill
# it, and then the only way on is by sea.
func _island_map() -> GameState:
	var state := GameState.create(31)
	state.terrain.fill(WorldGen.SEA)
	state.owner_of.fill(GameState.NEUTRAL)
	state.building_at.fill(Balance.Building.NONE)
	for y in range(8, 11):
		for x in range(8, 11):
			state.terrain[state.index_of(x, y)] = WorldGen.LAND
		for x in range(14, 17):
			state.terrain[state.index_of(x, y)] = WorldGen.LAND
	# The other player holds a corner of the far island: somebody has to be alive for the
	# match to continue, and putting them over there makes the water the only way to them.
	state.owner_of[state.index_of(16, 10)] = 0
	state.owner_of[state.index_of(9, 9)] = 1
	return state

func _far_island_cells(state: GameState) -> int:
	var count := 0
	for y in range(8, 11):
		for x in range(14, 17):
			if int(state.owner_of[state.index_of(x, y)]) == 1:
				count += 1
	return count
