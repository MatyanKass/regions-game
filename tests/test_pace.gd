# Copyright (c) 2026 MatyanKass. All rights reserved.
# Pacing. Land now pays, and income that grows with territory is exactly the shape that
# can turn a lead into a runaway, so the pace of a whole match is worth a test rather
# than a hope.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func test_two_hard_bots_play_a_whole_match_without_a_runaway() -> void:
	for seed_value in [4242, 7, 991]:
		_play_out(seed_value)

# by MatyanKass
func _play_out(seed_value: int) -> void:
	var state := GameState.create(seed_value)
	var bots := [BotPlayer.new(0, BotPlayer.Level.HARD, 11),
		BotPlayer.new(1, BotPlayer.Level.HARD, 22)]
	var land := _land_cells(state)
	var report: Array[String] = []
	var minute := 0
	for tick in range(state.match_limit_ticks()):
		for bot in bots:
			for cmd in (bot as BotPlayer).take_turn(state):
				state.apply_command((bot as BotPlayer).player, cmd)
		state.tick()
		if state.tick_count % (300 * Balance.TICKS_PER_SECOND) == 0:
			minute += 1
			var a := state.aggregate(0)
			var b := state.aggregate(1)
			report.append("  %2d min  cells %3d/%3d  coins/s %.1f/%.1f" % [minute * 5,
				int(a["cells"]), int(b["cells"]),
				float(a["coin_per_tick"]) * Balance.TICKS_PER_SECOND / Balance.UNIT,
				float(b["coin_per_tick"]) * Balance.TICKS_PER_SECOND / Balance.UNIT])
		if state.finished:
			break
	print("PACE seed %d, hard vs hard, land %d cells, ended at %d:%02d, winner %d" % [
		seed_value, land, state.tick_count / Balance.TICKS_PER_SECOND / 60,
		state.tick_count / Balance.TICKS_PER_SECOND % 60, state.winner])
	for line in report:
		print(line)

	# The guard that matters: land pays now, and income that grows with territory is the
	# shape that can snowball. If a match were ever decided inside three minutes it would
	# mean the leader had run away with it before the other side could answer.
	expect(state.tick_count > 3 * 60 * Balance.TICKS_PER_SECOND,
		"seed %d was decided in under three minutes" % seed_value)
	expect(int(state.aggregate(0)["cells"]) + int(state.aggregate(1)["cells"]) > 20,
		"seed %d never got going at all" % seed_value)
	expect(land > 0, "the map has land on it")

func _land_cells(state: GameState) -> int:
	var total := 0
	for i in range(state.terrain.size()):
		if state.is_land(i):
			total += 1
	return total
