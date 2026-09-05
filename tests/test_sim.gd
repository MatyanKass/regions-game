# Simulation tests. Run headless with tools/run_tests.ps1 - no phone, no window, no editor.
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

# --- World generation ---

func test_world_generation_is_deterministic() -> void:
	var a := WorldGen.generate(12345, WorldSettings.new())
	var b := WorldGen.generate(12345, WorldSettings.new())
	expect(a["terrain"] == b["terrain"], "same seed must produce the same terrain")
	expect(a["starts"] == b["starts"], "same seed must produce the same start cells")

func test_different_seeds_differ() -> void:
	var same := 0
	for seed_value in range(1, 20):
		if WorldGen.generate(seed_value, WorldSettings.new())["terrain"] == WorldGen.generate(seed_value + 100, WorldSettings.new())["terrain"]:
			same += 1
	expect_eq(same, 0, "different seeds must produce different maps")

func test_sea_percentage_stays_in_range() -> void:
	var seen: Dictionary = {}
	for seed_value in range(1, 60):
		var world := WorldGen.generate(seed_value, WorldSettings.new())
		var pct := int(world["sea_percent"])
		seen[pct] = true
		expect(pct >= Balance.SEA_PERCENT_MIN - 1 and pct <= Balance.SEA_PERCENT_MAX,
			"sea share %d%% is outside the designed 5-15%%" % pct)
	expect(seen.size() > 3, "sea share should vary between seeds, not sit on one value")

func test_start_cells_are_land_and_apart() -> void:
	for seed_value in range(1, 60):
		var world := WorldGen.generate(seed_value, WorldSettings.new())
		var terrain: PackedByteArray = world["terrain"]
		var starts: PackedInt32Array = world["starts"]
		expect_eq(starts.size(), 2, "two players means two start cells")
		expect(starts[0] != starts[1], "players must not share a start cell")
		for c in starts:
			expect(c >= 0, "start cell must exist")
			expect_eq(terrain[c], WorldGen.LAND, "start cell must be land")
		var w := int(world["width"])
		var dist := absi(starts[0] % w - starts[1] % w) + absi(starts[0] / w - starts[1] / w)
		expect(dist >= 10, "start cells too close on seed %d (distance %d)" % [seed_value, dist])

# --- Economy ---

func test_base_income_and_cap() -> void:
	var s := GameState.create(7)
	expect_eq(s.coins[0], 0, "match starts with no coins")
	for i in range(Balance.TICKS_PER_SECOND):
		s.tick()
	# One cell: the flat base income plus what that single cell pays.
	expect_eq(s.coins[0],
		(Balance.BASE_COIN_PER_TICK + Balance.CELL_COIN_PER_TICK) * Balance.TICKS_PER_SECOND,
		"a second of income is one coin plus the cell's share")
	expect_eq(s.power[0], 1 * Balance.UNIT, "land pays no power, so this is just the base")
	# 100 coins at 1/s takes 100 seconds; run past that to prove the cap holds.
	for i in range(120 * Balance.TICKS_PER_SECOND):
		s.tick()
	expect_eq(s.coins[0], Balance.BASE_COIN_CAP + Balance.CELL_COIN_CAP,
		"coins must stop at the storage cap")
	expect_eq(s.power[0], Balance.BASE_POWER_CAP + Balance.CELL_POWER_CAP,
		"power must stop at the storage cap")

func test_bank_raises_the_coin_cap() -> void:
	var s := _state_with_coins(7, 200 * Balance.UNIT)
	var home := _home_of(s, 0)
	expect_eq(_build_now(s, 0, home, Balance.Building.BANK), "",
		"a bank should be buildable with enough coins")
	expect_eq(int(s.aggregate(0)["coin_cap"]), _expected_coin_cap(s, 0, 10 * Balance.UNIT),
		"a bank adds ten coins of storage on top of what the land holds")

func test_factory_needs_a_free_person() -> void:
	var s := _state_with_coins(7, 500 * Balance.UNIT)
	var home := _home_of(s, 0)
	var second := _grant_cell(s, 0, home)
	expect_eq(_build_now(s, 0, home, Balance.Building.FACTORY),
		"not_enough_people", "a factory without population must be refused")
	expect_eq(_build_now(s, 0, home, Balance.Building.HOUSE), "",
		"a house should be buildable")
	expect_eq(_build_now(s, 0, second, Balance.Building.FACTORY), "",
		"a factory should be buildable once a house exists")
	expect_eq(int(s.aggregate(0)["free_people"]), 1, "one of the two residents now works the factory")

func test_demolish_refunds_half() -> void:
	var s := _state_with_coins(7, 100 * Balance.UNIT)
	var home := _home_of(s, 0)
	_build_now(s, 0, home, Balance.Building.HOUSE)
	expect_eq(s.coins[0], 70 * Balance.UNIT, "a house costs thirty coins")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.DEMOLISH, home)), "",
		"own building should be demolishable")
	expect_eq(s.coins[0], 85 * Balance.UNIT, "demolition refunds half the price")
	expect_eq(int(s.building_at[home]), Balance.Building.NONE, "the cell is empty again")

func test_demolishing_a_bank_clamps_the_purse() -> void:
	var s := _state_with_coins(7, 200 * Balance.UNIT)
	var home := _home_of(s, 0)
	_build_now(s, 0, home, Balance.Building.BANK)
	s.coins[0] = int(s.aggregate(0)["coin_cap"])
	s.apply_command(0, GameState.make_command(GameState.Command.DEMOLISH, home))
	expect_eq(s.coins[0], _expected_coin_cap(s, 0, 0),
		"losing the bank must clamp coins to the smaller cap")

# --- Capture ---

func test_capture_costs_power_and_needs_adjacency() -> void:
	var s := GameState.create(7)
	var home := _home_of(s, 0)
	var far := _far_land_cell(s, home)
	s.power[0] = 50 * Balance.UNIT
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, far)), "not_adjacent",
		"cells away from the border cannot be taken")
	var next_to_home := _land_neighbour(s, home)
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, next_to_home)), "",
		"a bordering cell should be capturable")
	expect_eq(s.power[0], 40 * Balance.UNIT, "a capture costs ten power")
	expect_eq(int(s.owner_of[next_to_home]), 0, "the cell changed hands")

func test_capture_is_refused_without_power() -> void:
	var s := GameState.create(7)
	var home := _home_of(s, 0)
	s.power[0] = 9 * Balance.UNIT
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, _land_neighbour(s, home))),
		"not_enough_power", "nine power is not enough for a capture")

func test_capture_razes_the_building_and_frees_the_worker() -> void:
	var s := _state_with_coins(7, 500 * Balance.UNIT)
	var victim_home := _home_of(s, 1)
	var victim_second := _grant_cell(s, 1, victim_home)
	s.coins[1] = 500 * Balance.UNIT
	_build_now(s, 1, victim_home, Balance.Building.HOUSE)
	_build_now(s, 1, victim_second, Balance.Building.FACTORY)
	expect_eq(int(s.aggregate(1)["free_people"]), 1, "the factory occupies one of the two residents")
	# Hand the attacker a cell next to the factory so the capture is legal.
	var beachhead := _grant_cell(s, 0, victim_second)
	s.power[0] = 50 * Balance.UNIT
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, victim_second)), "",
		"the factory cell should be capturable")
	expect_eq(int(s.building_at[victim_second]), Balance.Building.NONE, "the captured building is destroyed")
	expect_eq(int(s.aggregate(1)["free_people"]), 2, "losing the factory returns its worker to the pool")
	expect(beachhead >= 0, "the attacker had a staging cell")

func test_losing_the_last_cell_ends_the_match() -> void:
	var s := GameState.create(7)
	var victim_home := _home_of(s, 1)
	_grant_cell(s, 0, victim_home)
	s.power[0] = 50 * Balance.UNIT
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, victim_home)), "",
		"the last enemy cell should be capturable")
	expect_eq(int(s.alive[1]), 0, "a player with no cells is out")
	expect(s.finished, "the match is over")
	expect_eq(s.winner, 0, "the surviving player wins")

# --- Ports and ships ---

func test_port_requires_a_coast() -> void:
	var s := _state_with_coins(7, 500 * Balance.UNIT)
	s.power[0] = 100 * Balance.UNIT
	var inland := _inland_cell(s, 0)
	var coastal := _coastal_cell(s, 0)
	expect(inland >= 0 and coastal >= 0, "seed 7 should offer both an inland and a coastal cell")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.BUILD, inland, Balance.Building.PORT)),
		"needs_coast", "a port away from water must be refused")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.BUILD, coastal, Balance.Building.PORT)), "",
		"a port on the coast should be buildable")

func test_ship_crosses_the_sea_and_takes_the_cell() -> void:
	var s := _state_with_coins(7, 500 * Balance.UNIT)
	s.power[0] = 100 * Balance.UNIT
	var route := _find_sea_route(s, 0)
	expect(not route.is_empty(), "seed 7 should offer a port cell with land across the water")
	if route.is_empty():
		return
	var port_cell := int(route["port"])
	var target := int(route["target"])
	s.set_cell(port_cell, 0)
	_build_now(s, 0, port_cell, Balance.Building.PORT)
	var power_before := s.power[0]
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.LAUNCH_SHIP, port_cell, target)), "",
		"launching across open water should be allowed")
	expect_eq(s.power[0], power_before - Balance.SHIP_POWER_COST, "a launch costs ten power")
	expect_eq(s.ships.size(), 1, "the ship is at sea")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.LAUNCH_SHIP, port_cell, target)),
		"port_busy", "one port sails one ship at a time")
	var distance := int((s.ships[0]["path"] as PackedInt32Array).size())
	for i in range(distance * Balance.SHIP_TICKS_PER_CELL):
		s.tick()
	expect_eq(s.ships.size(), 0, "the ship is gone once it lands")
	expect_eq(int(s.owner_of[target]), 0, "the landing captured the target cell")

func test_ship_needs_water_not_just_a_neighbour() -> void:
	var s := GameState.create(7)
	var inland := -1
	for i in range(s.owner_of.size()):
		# A cell whose whole neighbourhood is dry can never be a landing site.
		if s.is_land(i) and not s.touches_sea(i):
			var dry := true
			for n in s.neighbours(i):
				if s.touches_sea(n):
					dry = false
			if dry:
				inland = i
				break
	expect(inland >= 0, "seed 7 should contain a cell well away from any water")
	if inland < 0:
		return
	var route := _find_sea_route(s, 0)
	if route.is_empty():
		return
	expect(s.sea_path(int(route["port"]), inland).is_empty(),
		"a landlocked cell cannot be reached by ship")

func test_ship_sails_round_a_headland() -> void:
	# A one-cell isthmus: the straight line between the two shores crosses dry land, so
	# only a route that follows the water can connect them.
	var s := GameState.create(7)
	s.terrain.fill(WorldGen.SEA)
	for y in range(s.height):
		s.terrain[s.index_of(5, y)] = WorldGen.LAND
	s.terrain[s.index_of(5, 0)] = WorldGen.SEA
	var port_cell := s.index_of(5, 6)
	var target := s.index_of(5, 10)
	s.set_cell(port_cell, 0, Balance.Building.PORT)
	var path := s.sea_path(port_cell, target)
	expect(not path.is_empty(), "the ship should find its way round the gap")
	expect(path.size() > 4, "the route has to be longer than the blocked straight line")
	expect_eq(path[path.size() - 1], target, "the route ends on the target")
	for i in range(path.size() - 1):
		expect_eq(int(s.terrain[path[i]]), WorldGen.SEA, "every step before the landing is water")

func test_reachable_shores_matches_what_is_allowed() -> void:
	var s := _state_with_coins(7, 500 * Balance.UNIT)
	var route := _find_sea_route(s, 0)
	if route.is_empty():
		return
	var port_cell := int(route["port"])
	s.set_cell(port_cell, 0, Balance.Building.PORT)
	var shores := s.reachable_shores(port_cell)
	expect(shores.size() > 0, "a port on open water reaches at least one shore")
	for cell in shores:
		expect(not s.sea_path(port_cell, cell).is_empty(),
			"every highlighted shore must really have a route")

# --- Cooldowns, levels and the barrier ---

func test_capture_has_a_cooldown() -> void:
	var s := GameState.create(7)
	var home := _home_of(s, 0)
	s.power[0] = 50 * Balance.UNIT
	var first := _land_neighbour(s, home)
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, first)), "",
		"the first capture goes through")
	var second := _first_capturable(s, 0)
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, second)),
		"on_cooldown", "a second capture in the same tick is refused")
	expect_eq(s.capture_cooldown_left(0), Balance.CAPTURE_COOLDOWN_TICKS,
		"open ground reloads in a quarter of a second")
	for i in range(Balance.CAPTURE_COOLDOWN_TICKS):
		s.tick()
	expect_eq(s.capture_cooldown_left(0), 0, "the cooldown runs out")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, second)), "",
		"and then the next cell can be taken")

func test_enemy_cells_reload_slower_than_open_ground() -> void:
	var s := GameState.create(7)
	var victim := _home_of(s, 1)
	_grant_cell(s, 1, victim)
	_grant_cell(s, 0, victim)
	s.power[0] = 50 * Balance.UNIT
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, victim)), "",
		"an enemy cell can be taken")
	expect_eq(s.capture_cooldown_left(0), Balance.CAPTURE_ENEMY_COOLDOWN_TICKS,
		"taking a defended cell costs more time than taking open ground")
	expect(Balance.CAPTURE_ENEMY_COOLDOWN_TICKS > Balance.CAPTURE_COOLDOWN_TICKS,
		"the two cooldowns must actually differ")

func test_barrier_stalls_the_attacker() -> void:
	var s := GameState.create(7)
	var victim_home := _home_of(s, 1)
	var wall := _grant_cell(s, 1, victim_home)
	s.coins[1] = 300 * Balance.UNIT
	s.power[1] = 100 * Balance.UNIT
	expect_eq(_build_now(s, 1, wall, Balance.Building.BARRIER), "",
		"a barrier should be buildable")
	_grant_cell(s, 0, wall)
	s.power[0] = 50 * Balance.UNIT
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, wall)), "",
		"a barrier does not stop the cell being taken")
	expect_eq(s.capture_cooldown_left(0), Balance.BARRIER_COOLDOWN_TICKS,
		"but the attacker is stalled for four seconds afterwards")
	expect_eq(int(s.building_at[wall]), Balance.Building.NONE, "the barrier itself is levelled")

func test_upgrade_scales_the_effect_and_the_price() -> void:
	var s := _state_with_coins(7, 1000 * Balance.UNIT)
	var home := _home_of(s, 0)
	_build_now(s, 0, home, Balance.Building.BANK)
	expect_eq(int(s.level_at[home]), 1, "a new building starts at level one")
	var before := int(s.coins[0])
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home)), "",
		"an upgrade should be possible with the coins for it")
	expect_eq(before - int(s.coins[0]), Balance.upgrade_coin_cost(Balance.Building.BANK, 2),
		"level two costs twice the base price")
	expect_eq(int(s.aggregate(0)["coin_cap"]), _expected_coin_cap(s, 0, 20 * Balance.UNIT),
		"a level two bank holds twice as much")

func test_upgrades_stop_at_the_ceiling() -> void:
	var s := _state_with_coins(7, 5000 * Balance.UNIT)
	var home := _home_of(s, 0)
	_build_now(s, 0, home, Balance.Building.HOUSE)
	for i in range(Balance.MAX_LEVEL - 1):
		expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home)), "",
			"upgrade %d should be allowed" % (i + 2))
	expect_eq(int(s.level_at[home]), Balance.MAX_LEVEL, "the house reaches the ceiling")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home)),
		"max_level", "and cannot go past it")
	expect_eq(int(s.aggregate(0)["people"]), 2 * Balance.MAX_LEVEL,
		"every level of the house houses another two residents")

func test_a_barrier_cannot_be_upgraded() -> void:
	var s := _state_with_coins(7, 1000 * Balance.UNIT)
	s.power[0] = 200 * Balance.UNIT
	var home := _home_of(s, 0)
	_build_now(s, 0, home, Balance.Building.BARRIER)
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home)),
		"max_level", "a wall is a wall: one level only")

func test_demolition_refunds_the_upgrades_too() -> void:
	# Coins have to start inside the storage cap, or the refund would be clamped away
	# and the test would be measuring the cap rather than the refund.
	var s := _state_with_coins(7, Balance.BASE_COIN_CAP)
	var home := _home_of(s, 0)
	_build_now(s, 0, home, Balance.Building.HOUSE)
	s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home))
	var before := int(s.coins[0])
	s.apply_command(0, GameState.make_command(GameState.Command.DEMOLISH, home))
	# Level two cost 30 + 60 = 90 coins, so half of everything sunk in is 45.
	expect_eq(int(s.coins[0]) - before,
		Balance.invested_coins(Balance.Building.HOUSE, 2) * Balance.DEMOLISH_REFUND_PERCENT / 100,
		"the refund covers what the upgrades cost as well")

func test_levels_and_cooldowns_survive_a_snapshot() -> void:
	var s := _state_with_coins(7, 1000 * Balance.UNIT)
	var home := _home_of(s, 0)
	s.power[0] = 60 * Balance.UNIT
	_build_now(s, 0, home, Balance.Building.BANK)
	s.apply_command(0, GameState.make_command(GameState.Command.UPGRADE, home))
	s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, _land_neighbour(s, home)))
	var copy := GameState.from_snapshot(s.snapshot())
	expect_eq(copy.state_hash(), s.state_hash(),
		"a snapshot has to carry building levels and the reload clock")
	expect_eq(int(copy.level_at[home]), 2, "the level came across")
	expect_eq(copy.capture_cooldown_left(0), s.capture_cooldown_left(0),
		"so did the cooldown")

# --- Staffing: a factory with nobody in it earns nothing ---

func test_losing_housing_idles_a_factory_instead_of_going_negative() -> void:
	var s := _state_with_coins(7, 5000 * Balance.UNIT)
	var home := _home_of(s, 0)
	var second := _grant_cell(s, 0, home)
	var third := _grant_cell(s, 0, second)
	_build_now(s, 0, home, Balance.Building.HOUSE)
	_build_now(s, 0, second, Balance.Building.FACTORY)
	_build_now(s, 0, third, Balance.Building.FACTORY)
	var working := int(s.aggregate(0)["coin_per_tick"])
	expect_eq(int(s.aggregate(0)["free_people"]), 0, "both residents are at work")
	expect_eq(int((s.aggregate(0)["idle_cells"] as PackedInt32Array).size()), 0,
		"nothing is idle while the house stands")

	# The enemy takes the house. Its residents go with it, and one factory has to stop.
	var attacker := _grant_cell(s, 1, home)
	s.power[1] = 50 * Balance.UNIT
	expect_eq(s.apply_command(1, GameState.make_command(GameState.Command.CAPTURE, home)), "",
		"the house should be capturable")
	expect(attacker >= 0, "the attacker had a staging cell")

	var after := s.aggregate(0)
	expect_eq(int(after["people"]), 0, "the residents went with the house")
	expect(int(after["free_people"]) >= 0, "free people must never go negative")
	expect_eq(int((after["idle_cells"] as PackedInt32Array).size()), 2,
		"with nobody left, both factories stand idle")
	expect(int(after["coin_per_tick"]) < working,
		"an idle factory must stop earning, not keep paying out of nowhere")
	expect_eq(int(after["coin_per_tick"]),
		Balance.BASE_COIN_PER_TICK + int(after["cells"]) * Balance.CELL_COIN_PER_TICK,
		"only the base income and what the remaining land pays is left")

func test_the_biggest_factory_is_staffed_first() -> void:
	# One level one house holds two residents. Three factories therefore leave one idle,
	# and the one that stops must be a small one: staffing the biggest first is what a
	# player would do by hand.
	var s := GameState.create(7)
	var home := _home_of(s, 0)
	var small_a := _grant_cell(s, 0, home)
	var big := _grant_cell(s, 0, small_a)
	var small_b := _grant_cell(s, 0, big)
	expect(small_b >= 0, "seed 7 should offer four cells in a row")
	s.set_cell(home, 0, Balance.Building.HOUSE, 1)
	for cell in [small_a, big, small_b]:
		s.set_cell(cell, 0, Balance.Building.FACTORY, 1)
	s.set_cell(big, 0, Balance.Building.FACTORY, 3)

	var agg := s.aggregate(0)
	expect_eq(int(agg["people"]), 2, "one level one house holds two")
	var idle: PackedInt32Array = agg["idle_cells"]
	expect_eq(int(idle.size()), 1, "three factories and two residents leaves one idle")
	expect(not idle.has(big), "the level three factory is the one kept running")
	# Two staffed factories: the level three one and one of the level ones.
	# The level three factory and one level one factory are staffed: four levels in all.
	var expected := Balance.BASE_COIN_PER_TICK \
		+ int(agg["cells"]) * Balance.CELL_COIN_PER_TICK \
		+ int(Balance.BUILDINGS[Balance.Building.FACTORY]["coin_per_tick"]) * 4
	expect_eq(int(agg["coin_per_tick"]), expected, "only the staffed factories pay")

func test_idle_factories_do_not_break_the_lockstep() -> void:
	var a := GameState.create(77)
	var b := GameState.create(77)
	for state in [a, b]:
		var home := _home_of(state, 0)
		state.coins[0] = 5000 * Balance.UNIT
		var next := _grant_cell(state, 0, home)
		var third := _grant_cell(state, 0, next)
		state.set_cell(home, 0, Balance.Building.FACTORY, 2)
		state.set_cell(next, 0, Balance.Building.FACTORY, 2)
		state.set_cell(third, 0, Balance.Building.FACTORY, 1)
	for i in range(60):
		a.tick()
		b.tick()
	# Equal levels mean the tie is broken on cell index, which both sides must resolve
	# the same way or the income would drift apart.
	expect_eq(a.state_hash(), b.state_hash(), "staffing has to be decided identically")
	expect_eq(int(a.coins[0]), int(b.coins[0]), "and so does the income it produces")

# --- Determinism ---

func test_two_runs_of_the_same_commands_match() -> void:
	var a := GameState.create(4242)
	var b := GameState.create(4242)
	for step in range(400):
		a.tick()
		b.tick()
		if step % 37 == 0:
			var cell := _first_capturable(a, 0)
			if cell >= 0:
				var cmd := GameState.make_command(GameState.Command.CAPTURE, cell)
				a.apply_command(0, cmd)
				b.apply_command(0, cmd)
		expect_eq(a.state_hash(), b.state_hash(), "states diverged at tick %d" % step)
		if a.finished:
			break

func test_snapshot_round_trip() -> void:
	var s := _state_with_coins(31, 300 * Balance.UNIT)
	s.power[0] = 60 * Balance.UNIT
	var home := _home_of(s, 0)
	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.HOUSE))
	s.apply_command(0, GameState.make_command(GameState.Command.CAPTURE, _land_neighbour(s, home)))
	for i in range(25):
		s.tick()
	var copy := GameState.from_snapshot(s.snapshot())
	expect_eq(copy.state_hash(), s.state_hash(), "a restored snapshot must be the same state")
	# And it must keep behaving the same, not merely look the same right now.
	for i in range(50):
		s.tick()
		copy.tick()
	expect_eq(copy.state_hash(), s.state_hash(), "a restored snapshot must keep running in step")

func test_snapshot_carries_ships() -> void:
	var s := _state_with_coins(7, 500 * Balance.UNIT)
	s.power[0] = 100 * Balance.UNIT
	var route := _find_sea_route(s, 0)
	if route.is_empty():
		return
	var port_cell := int(route["port"])
	s.set_cell(port_cell, 0)
	_build_now(s, 0, port_cell, Balance.Building.PORT)
	s.apply_command(0, GameState.make_command(GameState.Command.LAUNCH_SHIP, port_cell, int(route["target"])))
	var copy := GameState.from_snapshot(s.snapshot())
	expect_eq(copy.ships.size(), 1, "the ship survives the snapshot")
	expect_eq(copy.state_hash(), s.state_hash(), "a state with a ship at sea round-trips")

func test_hash_notices_a_difference() -> void:
	var a := GameState.create(99)
	var b := GameState.create(99)
	b.coins[0] += 1
	expect(a.state_hash() != b.state_hash(), "the hash must catch a one-unit difference")

# --- Helpers ---

# Land pays and land holds, so almost every economy figure depends on how many cells the
# player owns. Saying so out loud beats sprinkling the constants around.
func _cells(s: GameState, player: int) -> int:
	return int(s.aggregate(player)["cells"])

func _expected_coin_cap(s: GameState, player: int, from_buildings: int) -> int:
	return Balance.BASE_COIN_CAP + _cells(s, player) * Balance.CELL_COIN_CAP + from_buildings

# Orders a building and lets the work run to the end. Most tests are about what a
# building does rather than about the time it takes, and waiting is now part of getting
# one. Coins are restored afterwards so a test that measures a price is not also
# measuring the income that accrued while the builders were busy.
func _build_now(s: GameState, player: int, cell: int, type: int) -> String:
	var coins_before := int(s.coins[player])
	var power_before := int(s.power[player])
	var cost_coins := int(Balance.BUILDINGS[type]["coin_cost"])
	var cost_power := int(Balance.BUILDINGS[type]["power_cost"])
	var reason := s.apply_command(player,
		GameState.make_command(GameState.Command.BUILD, cell, type))
	if not reason.is_empty():
		return reason
	var guard := Balance.build_ticks(type) + 5
	while s.site_index(cell) >= 0 and guard > 0:
		s.tick()
		guard -= 1
	s.coins[player] = coins_before - cost_coins
	s.power[player] = power_before - cost_power
	return ""

func _home_of(s: GameState, player: int) -> int:
	for i in range(s.owner_of.size()):
		if s.owner_of[i] == player:
			return i
	return -1

func _state_with_coins(seed_value: int, amount: int) -> GameState:
	var s := GameState.create(seed_value)
	s.coins[0] = amount
	return s

# Gives a player one more land cell next to `near`, bypassing the power cost.
func _grant_cell(s: GameState, player: int, near: int) -> int:
	for n in s.neighbours(near):
		if s.is_land(n) and s.owner_of[n] == GameState.NEUTRAL:
			s.set_cell(n, player)
			return n
	return -1

func _land_neighbour(s: GameState, cell: int) -> int:
	for n in s.neighbours(cell):
		if s.is_land(n):
			return n
	return -1

func _far_land_cell(s: GameState, from: int) -> int:
	var w := s.width
	for i in range(s.owner_of.size()):
		if not s.is_land(i) or s.owner_of[i] != GameState.NEUTRAL:
			continue
		if absi(i % w - from % w) + absi(i / w - from / w) > 3:
			return i
	return -1

func _inland_cell(s: GameState, player: int) -> int:
	var home := _home_of(s, player)
	for i in range(s.owner_of.size()):
		if s.is_land(i) and not s.touches_sea(i) and s.owner_of[i] == GameState.NEUTRAL:
			s.set_cell(i, player)
			return i
	return home

func _coastal_cell(s: GameState, player: int) -> int:
	for i in range(s.owner_of.size()):
		if s.is_land(i) and s.touches_sea(i) and s.owner_of[i] == GameState.NEUTRAL:
			s.set_cell(i, player)
			return i
	return -1

# Finds a coastal cell with somewhere to sail to, using the simulation's own routing.
func _find_sea_route(s: GameState, player: int) -> Dictionary:
	for from in range(s.owner_of.size()):
		if not s.is_land(from) or not s.touches_sea(from):
			continue
		var was := int(s.building_at[from])
		var was_owner := int(s.owner_of[from])
		var was_level := maxi(1, int(s.level_at[from]))
		s.set_cell(from, was_owner, Balance.Building.PORT)
		var shores := s.reachable_shores(from)
		s.set_cell(from, was_owner, was, was_level)
		for cell in shores:
			if s.owner_of[cell] == GameState.NEUTRAL and cell != from:
				return {"port": from, "target": cell}
	return {}

func _first_capturable(s: GameState, player: int) -> int:
	for i in range(s.owner_of.size()):
		if s.is_land(i) and s.owner_of[i] != player and s.touches_player(i, player):
			return i
	return -1

# --- Building takes time ---

func test_a_building_is_not_finished_the_moment_it_is_paid_for() -> void:
	var s := _state_with_coins(7, Balance.BASE_COIN_CAP)
	var home := _home_of(s, 0)
	var before := int(s.aggregate(0)["coin_cap"])
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home,
		Balance.Building.BANK)), "", "the order should be accepted")
	expect_eq(int(s.building_at[home]), Balance.Building.NONE,
		"nothing stands on the cell yet")
	expect(s.site_index(home) >= 0, "but there is work going on there")
	expect_eq(int(s.aggregate(0)["coin_cap"]), before,
		"and a half-built bank holds nothing")

	var ticks := Balance.build_ticks(Balance.Building.BANK)
	for i in range(ticks - 1):
		s.tick()
	expect_eq(int(s.building_at[home]), Balance.Building.NONE, "still not finished")
	s.tick()
	expect_eq(int(s.building_at[home]), Balance.Building.BANK, "and now it is")
	expect_eq(s.site_index(home), -1, "the site is cleared")
	expect_eq(int(s.aggregate(0)["coin_cap"]),
		before + 10 * Balance.UNIT, "the finished bank holds its ten coins")
	expect(s.verify_totals().is_empty(), "and the totals took it into account exactly once")

func test_each_building_takes_its_own_time() -> void:
	var seen: Dictionary = {}
	for type in Balance.BUILDINGS:
		var seconds := int(Balance.BUILDINGS[type]["build_seconds"])
		expect(seconds >= 5 and seconds <= 15,
			"%s takes %d seconds, outside the five to fifteen the design asks for"
				% [str(Balance.BUILDINGS[type]["name"]), seconds])
		seen[seconds] = true
	expect(seen.size() >= 4, "the times should differ between buildings, not all be one number")

func test_calling_off_the_work_costs_nothing() -> void:
	var s := _state_with_coins(7, Balance.BASE_COIN_CAP)
	var home := _home_of(s, 0)
	var before := int(s.coins[0])
	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.HOUSE))
	expect(int(s.coins[0]) < before, "the order is paid for up front")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.DEMOLISH, home)), "",
		"work in progress can be called off")
	expect_eq(int(s.coins[0]), before, "and every coin comes back, since nothing was built")
	expect_eq(s.site_index(home), -1, "the site is gone")

func test_a_captured_site_is_abandoned() -> void:
	var s := _state_with_coins(7, Balance.BASE_COIN_CAP)
	var home := _home_of(s, 0)
	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.HOUSE))
	_grant_cell(s, 1, home)
	s.power[1] = 50 * Balance.UNIT
	expect_eq(s.apply_command(1, GameState.make_command(GameState.Command.CAPTURE, home)), "",
		"the cell can be taken while it is a building site")
	expect_eq(s.site_index(home), -1, "and the work is abandoned with it")
	for i in range(Balance.build_ticks(Balance.Building.HOUSE) + 5):
		s.tick()
	expect_eq(int(s.building_at[home]), Balance.Building.NONE,
		"nothing appears on the captured cell later")
	expect(s.verify_totals().is_empty(), "the totals stay right")

func test_people_promised_to_a_site_are_not_free() -> void:
	var s := _state_with_coins(7, 5000 * Balance.UNIT)
	var home := _home_of(s, 0)
	var a := _grant_cell(s, 0, home)
	var b := _grant_cell(s, 0, a)
	s.set_cell(home, 0, Balance.Building.HOUSE, 1)   # two residents
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.BUILD, a,
		Balance.Building.FACTORY)), "", "the first factory is ordered")
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.BUILD, b,
		Balance.Building.FACTORY)), "", "and the second, since two people live here")
	var c := _grant_cell(s, 0, b)
	expect_eq(s.apply_command(0, GameState.make_command(GameState.Command.BUILD, c,
		Balance.Building.FACTORY)), "not_enough_people",
		"a third has nobody left to work it, even though none of them are built yet")

func test_sites_survive_a_snapshot() -> void:
	var s := _state_with_coins(7, Balance.BASE_COIN_CAP)
	var home := _home_of(s, 0)
	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.BANK))
	for i in range(10):
		s.tick()
	var copy := GameState.from_snapshot(s.snapshot())
	expect_eq(copy.state_hash(), s.state_hash(), "work in progress travels with a snapshot")
	expect(copy.site_index(home) >= 0, "the site is there")
	for i in range(Balance.build_ticks(Balance.Building.BANK)):
		s.tick()
		copy.tick()
	expect_eq(copy.state_hash(), s.state_hash(), "and finishes at the same moment on both")
