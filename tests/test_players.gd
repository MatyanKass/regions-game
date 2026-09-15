# Copyright (c) 2026 MatyanKass. All rights reserved.
# A room of more than two, and the colours everyone plays in.
#
# Two players was baked into the game in more places than it looked: the map put two
# starts on opposite sides of a line, the end of the match was "whoever is left", and the
# colours were the two biros. These tests are what says the seams have all been let out.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

# by MatyanKass
func expect_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (got %s, expected %s)" % [message, actual, expected])

func _world(size: int, players: int) -> WorldSettings:
	var world := WorldSettings.of_size(size)
	world.players = players
	return world

func _distance(a: int, b: int, width: int) -> int:
	return absi(a % width - b % width) + absi(a / width - b / width)

# --- The map ------------------------------------------------------------------------

func test_every_seat_gets_a_start_of_its_own() -> void:
	for players in range(2, WorldSettings.MAX_PLAYERS + 1):
		for seed_value in [3, 77, 2026]:
			var world := _world(50, players)
			var made := WorldGen.generate(seed_value, world)
			var starts: PackedInt32Array = made["starts"]
			var terrain: PackedByteArray = made["terrain"]
			expect_eq(starts.size(), players, "%d players want %d starts" % [players, players])
			var seen: Dictionary = {}
			for cell in starts:
				expect(cell >= 0, "a start that could not be placed at all")
				expect_eq(terrain[cell], WorldGen.LAND, "a start in the sea")
				expect(not seen.has(cell), "two players sharing one start cell")
				seen[cell] = true

func test_starts_are_spread_around_the_map_not_stacked() -> void:
	for players in [3, 5, 8]:
		var world := _world(100, players)
		var starts: PackedInt32Array = WorldGen.generate(9, world)["starts"]
		var closest := 1 << 30
		for i in range(starts.size()):
			for j in range(i + 1, starts.size()):
				closest = mini(closest, _distance(starts[i], starts[j], world.width))
		# A ring of eight on a hundred-cell map leaves plenty of room; what this is really
		# holding is that nobody opens the match already touching a neighbour.
		expect(closest >= 6, "with %d players the two closest starts are %d cells apart"
			% [players, closest])

func test_the_ring_stays_inside_a_small_map() -> void:
	var world := _world(15, 8)
	var starts: PackedInt32Array = WorldGen.generate(4, world)["starts"]
	expect_eq(starts.size(), 8, "eight seats on the smallest map still get eight starts")
	for cell in starts:
		expect(cell >= 0 and cell < world.cells(), "a start outside the map")

func test_a_full_room_is_a_crowd_on_a_small_map() -> void:
	expect(_world(25, 8).crowded(), "eight players on 25x25 is worth warning about")
	expect(not _world(25, 2).crowded(), "two players on 25x25 is the ordinary game")
	expect(not _world(200, 8).crowded(), "eight players have room on a big map")

# --- The match ----------------------------------------------------------------------

# by MatyanKass
func test_a_state_is_made_with_as_many_seats_as_the_room() -> void:
	var state := GameState.create(11, _world(50, 6))
	expect_eq(state.player_count(), 6, "six seats")
	expect_eq(state.coins.size(), 6, "six purses")
	var owned: Dictionary = {}
	for i in range(state.owner_of.size()):
		var owner_id := int(state.owner_of[i])
		if owner_id != GameState.NEUTRAL:
			owned[owner_id] = int(owned.get(owner_id, 0)) + 1
	expect_eq(owned.size(), 6, "every seat starts with ground")
	for player in range(6):
		expect_eq(int(state.aggregate(player)["cells"]), 1, "player %d opens with one cell" % player)

func test_losing_your_last_cell_does_not_end_a_crowded_match() -> void:
	var state := GameState.create(21, _world(50, 4))
	# A neighbour walks in and takes it: player 3 is out, the other three play on.
	_conquer(state, 0, 3)
	state.tick()
	expect_eq(int(state.alive[3]), 0, "the player who lost everything is out")
	expect(not state.finished, "three players left is still a match")
	for player in [0, 1, 2]:
		expect_eq(int(state.alive[player]), 1, "player %d is still in it" % player)

func test_the_match_ends_when_one_country_is_left() -> void:
	var state := GameState.create(22, _world(50, 4))
	for player in [1, 2, 3]:
		_conquer(state, 0, player)
	state.tick()
	expect(state.finished, "one player left ends it")
	expect_eq(state.winner, 0, "and they are the winner")

# by MatyanKass
func test_when_time_runs_out_the_biggest_country_wins() -> void:
	var world := _world(50, 5)
	world.match_minutes = 1
	var state := GameState.create(23, world)
	# Player 2 takes some empty ground; nobody else grows.
	var home := _home_of(state, 2)
	var given := 0
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) == GameState.NEUTRAL and state.is_land(i) and given < 5:
			state.set_cell(i, 2)
			given += 1
	expect(given > 0, "the test needs some free land to hand out")
	state.tick_count = state.match_limit_ticks()
	state.tick()
	expect(state.finished, "the clock ran out")
	expect_eq(state.winner, 2, "the biggest country wins on cells")
	expect(home >= 0, "player 2 had a home to grow from")

# --- Colours ------------------------------------------------------------------------

func test_a_region_offers_a_palette_and_a_name() -> void:
	expect(Regions.count() >= 6, "there should be a handful of regions to choose from")
	for region in range(Regions.count()):
		var palette := Regions.palette(region)
		expect(palette.size() >= 2, "region %d needs more than one colour" % region)
		for colour in palette:
			expect(int(colour) > 0 and int(colour) <= 0xFFFFFF, "a colour outside 24 bits")
		expect(not Regions.key_of(region).is_empty(), "region %d has no key" % region)
	expect(not Regions.valid(Regions.NONE), "'nobody chose' is not a region")

func test_everyone_in_a_room_gets_their_own_colour() -> void:
	# Eight players, all from the same continent: the palette runs out, and they still
	# have to be told apart on the map.
	var regions := PackedByteArray()
	for i in range(8):
		regions.append(0)
	var state := GameState.create(31, _world(100, 8))
	Regions.assign_all(state, 31, regions)
	var seen: Dictionary = {}
	for player in range(8):
		var tint := state.tint_of(player)
		expect(tint != 0, "player %d was left without a colour" % player)
		expect(not seen.has(tint), "players %s and %d share a colour" % [seen.get(tint, ""), player])
		seen[tint] = player

func test_a_colour_comes_out_of_the_region_that_was_chosen() -> void:
	var regions := PackedByteArray([2, 0])
	var state := GameState.create(41, _world(50, 2))
	Regions.assign_all(state, 41, regions)
	expect(Regions.palette(2).has(state.tint_of(0)), "player 0 is in an Asian colour")
	expect(Regions.palette(0).has(state.tint_of(1)), "player 1 is in an African one")
	expect_eq(state.region_of(0), 2, "and the state remembers where they are from")

func test_the_same_seed_dresses_the_room_the_same_way() -> void:
	var regions := PackedByteArray([0, 1, 2, 3])
	var first := GameState.create(51, _world(50, 4))
	var second := GameState.create(51, _world(50, 4))
	Regions.assign_all(first, 51, regions)
	Regions.assign_all(second, 51, regions)
	for player in range(4):
		expect_eq(first.tint_of(player), second.tint_of(player),
			"player %d must get the same colour on every device" % player)

func test_nobody_choosing_still_leaves_everyone_distinct() -> void:
	var state := GameState.create(61, _world(50, 8))
	Regions.assign_all(state, 61, PackedByteArray())
	var seen: Dictionary = {}
	for player in range(8):
		var tint := state.tint_of(player)
		expect(not seen.has(tint), "two undressed players share a colour")
		seen[tint] = true

func test_colours_survive_a_snapshot() -> void:
	var state := GameState.create(71, _world(50, 3))
	Regions.assign_all(state, 71, PackedByteArray([0, 4, 6]))
	var copy := GameState.from_snapshot(state.snapshot())
	for player in range(3):
		expect_eq(copy.tint_of(player), state.tint_of(player), "colour of player %d" % player)
		expect_eq(copy.region_of(player), state.region_of(player), "region of player %d" % player)

func test_a_world_from_before_regions_still_opens() -> void:
	var state := GameState.create(81, _world(50, 2))
	var old := state.snapshot()
	old.erase("region")
	old.erase("tint")
	var copy := GameState.from_snapshot(old)
	expect_eq(copy.tint_of(0), 0, "no colour recorded means none pretended")
	expect_eq(copy.region_of(0), GameState.NO_REGION, "and no region either")
	expect(Ink.pen_for(copy, 0) != Ink.pen_for(copy, 1),
		"the interface still has to draw them in different pens")

func test_the_pen_follows_the_state_when_there_is_one() -> void:
	var state := GameState.create(91, _world(50, 2))
	Regions.assign_all(state, 91, PackedByteArray([0, 0]))
	expect_eq(Ink.pen_for(state, 0), Regions.colour_to_ink(state.tint_of(0)),
		"a player is drawn in the colour their region gave them")
	expect_eq(Ink.pen_for(null, 1), Ink.pen_of(1), "and in the flat pens when there is no state")

# Player `attacker` walks into the last cell `victim` owns, through the rules rather than
# around them: standing next to it and paying the power, which is what eliminates anyone.
func _conquer(state: GameState, attacker: int, victim: int) -> void:
	var home := _home_of(state, victim)
	for side in state.neighbours(home):
		if not state.is_land(side):
			continue
		state.set_cell(side, attacker)
		state.power[attacker] = 100 * Balance.UNIT
		state.capture_ready[attacker] = 0
		var refused := state.apply_command(attacker,
			GameState.make_command(GameState.Command.CAPTURE, home))
		expect(refused.is_empty(), "taking the last cell of player %d: %s" % [victim, refused])
		return
	expect(false, "player %d has no land neighbour to be attacked from" % victim)

func _home_of(state: GameState, player: int) -> int:
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) == player:
			return i
	return -1
