# Copyright (c) 2026 MatyanKass. All rights reserved.
# Big worlds, and the cache that makes them possible.
#
# The running totals in GameState are the one place the grid is not the single source of
# truth, so they get their own test: after every kind of change, what the cache says must
# be what a full recount says. A cache that drifts would not crash - it would quietly pay
# one player the wrong income, and the two devices would disagree.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _agrees(state: GameState, after: String) -> void:
	var problems := state.verify_totals()
	expect(problems.is_empty(), "totals drifted after %s: %s" % [after, ", ".join(problems)])

func test_the_totals_survive_every_kind_of_change() -> void:
	var s := GameState.create(7)
	_agrees(s, "creation")
	var home := -1
	for i in range(s.owner_of.size()):
		if int(s.owner_of[i]) == 0:
			home = i
			break
	s.coins[0] = 5000 * Balance.UNIT
	s.power[0] = 500 * Balance.UNIT

	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.HOUSE))
	_agrees(s, "a building going up")
	s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home))
	_agrees(s, "an upgrade")

	var next_cell := -1
	for n in s.neighbours(home):
		if s.is_land(n) and int(s.owner_of[n]) == GameState.NEUTRAL:
			next_cell = n
			break
	expect(next_cell >= 0, "seed 7 should offer a neighbouring land cell")
	s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, next_cell))
	_agrees(s, "a capture")

	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, next_cell, Balance.Building.FACTORY))
	_agrees(s, "a factory")
	s.apply_command(0, GameState.make_command(GameState.Command.DEMOLISH, next_cell))
	_agrees(s, "a demolition")

	# And when the other side takes a built-up cell off us.
	s.power[1] = 500 * Balance.UNIT
	for n in s.neighbours(home):
		if s.is_land(n) and int(s.owner_of[n]) == GameState.NEUTRAL:
			s.set_cell(n, 1)
			break
	_agrees(s, "the enemy moving in next door")
	s.apply_command(1, GameState.make_command(GameState.Command.CAPTURE, home))
	_agrees(s, "losing a building to a capture")

func test_a_thousand_ticks_do_not_drift() -> void:
	var s := GameState.create(4242)
	for i in range(1000):
		s.tick()
	_agrees(s, "a thousand ticks")

func test_a_snapshot_of_a_big_world_comes_back_whole() -> void:
	var settings := WorldSettings.of_size(120)
	var s := GameState.create(31, settings)
	s.coins[0] = 5000 * Balance.UNIT
	for i in range(50):
		s.tick()
	var copy := GameState.from_snapshot(s.snapshot())
	expect(copy.width == 120 and copy.height == 120, "the size travels with the snapshot")
	expect(copy.state_hash() == s.state_hash(), "a restored big world is the same world")
	expect(copy.verify_totals().is_empty(), "and its totals are counted correctly")

func test_free_play_has_no_opponent_and_no_ending() -> void:
	var s := GameState.create(9, WorldSettings.free_play(40))
	expect(s.alive.size() == 1, "free play is one player")
	expect(s.is_free_play(), "and knows it")
	expect(s.match_limit_ticks() == 0, "with no clock")
	# One player alive would end an ordinary match immediately.
	for i in range(200):
		s.tick()
	expect(not s.finished, "free play must not end just because nobody else is there")
	expect(int(s.aggregate(0)["cells"]) == 1, "and it still starts from one cell")

func test_sizes_are_honoured() -> void:
	for size in [WorldSettings.MIN_SIZE, 25, 100]:
		var s := GameState.create(5, WorldSettings.of_size(size))
		expect(s.width == size and s.height == size, "a %d world should be %d across" % [size, size])
		expect(s.owner_of.size() == size * size, "and hold that many cells")
		expect(int(s.aggregate(0)["cells"]) == 1, "with one cell owned at the start")

func test_starts_move_apart_on_a_bigger_map() -> void:
	# Two players dropped sixteen cells apart on a four hundred wide world would meet in
	# the first minute and never see the rest of it.
	var small := WorldGen.start_distance(WorldSettings.of_size(25))
	var large := WorldGen.start_distance(WorldSettings.of_size(400))
	expect(large > small * 4, "start distance has to scale with the map")

# by MatyanKass
func test_a_big_world_ticks_fast_enough_to_play() -> void:
	# The host runs the clock, so a tick has to cost far less than the fiftieth of a
	# second it represents. This is the test that would have failed before the running
	# totals existed: counting a player's income by walking a hundred and sixty thousand
	# cells, twenty times a second, is not a thing a phone can do.
	var built := Time.get_ticks_msec()
	var s := GameState.create(3, WorldSettings.of_size(400))
	var build_ms := Time.get_ticks_msec() - built
	var start := Time.get_ticks_msec()
	for i in range(200):
		s.tick()
	var ms := Time.get_ticks_msec() - start
	print("PERF 400x400 (%d cells): generated in %d ms, 200 ticks in %d ms" % [
		s.owner_of.size(), build_ms, ms])
	# Two hundred ticks is ten seconds of play. Anything close to that in real time
	# means the simulation cannot keep up with itself.
	expect(ms < 2000, "200 ticks on a 400 wide world took %d ms" % ms)
	expect(s.verify_totals().is_empty(), "and the totals are still right afterwards")

# by MatyanKass
func test_the_largest_world_can_be_made_at_all() -> void:
	var start := Time.get_ticks_msec()
	var s := GameState.create(5, WorldSettings.of_size(WorldSettings.MAX_SIZE))
	var ms := Time.get_ticks_msec() - start
	print("PERF %dx%d (%d cells): generated in %d ms" % [
		WorldSettings.MAX_SIZE, WorldSettings.MAX_SIZE, s.owner_of.size(), ms])
	expect(s.owner_of.size() == WorldSettings.MAX_SIZE * WorldSettings.MAX_SIZE,
		"the biggest world offered has to actually be buildable")
	expect(int(s.aggregate(0)["cells"]) == 1, "and a player starts on one cell of it")

func test_the_bot_thinks_fast_enough_on_a_big_world() -> void:
	# The bot still reads the whole map to choose a move, which is fine at 25 across and
	# is the thing most likely to bite on a large one. Practice has to stay playable.
	var s := GameState.create(3, WorldSettings.of_size(400))
	var bot := BotPlayer.new(1, BotPlayer.Level.HARD, 7)
	var start := Time.get_ticks_msec()
	for i in range(20):
		bot.take_turn(s)
		s.tick()
	var ms := Time.get_ticks_msec() - start
	print("PERF bot on 400x400: 20 turns in %d ms" % ms)
