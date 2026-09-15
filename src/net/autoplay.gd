# Copyright (c) 2026 MatyanKass. All rights reserved.
# A robot player used only by tools/run_net_test.ps1. Headless instances host and join
# over the loopback, play a scripted match against each other and print their final state
# hash. Equal hashes mean the lockstep really holds end to end - the one thing the
# simulation tests cannot prove on their own.
#
# --autoplay-seats=N makes the host wait for N players before starting, which is how a
# room of three or more is tested with real sockets rather than argued about.
#
# Enabled only by a command line flag, so it can never affect a real match.
extends Node

const STOP_AT_TICK := 200
const ACT_EVERY_TICKS := 6

var joining := false
var seats := 2

var _retries := 0
var _retry_timer := 0.0
var _last_action_tick := 0
var _done := false
var _quit_timer := 0.0

# by MatyanKass
func _ready() -> void:
	if joining:
		_try_join()
	else:
		var world := WorldSettings.new()
		world.players = seats
		Net.host_room("autoplay-host", world)
	Net.match_advanced.connect(_on_advanced)
	Net.connection_lost.connect(func(reason: String):
		if _done:
			return
		print("AUTOPLAY lost connection: ", reason)
		get_tree().quit(2))

func _process(delta: float) -> void:
	if _done:
		# Leave the connection open for a moment so the last tick batches reach the
		# other side; quitting the instant we are finished would look like a desync.
		_quit_timer -= delta
		if _quit_timer <= 0.0:
			get_tree().quit(0)
		return
	# The host now waits for somebody to press start rather than beginning the moment a
	# phone knocks, so the robot presses it itself.
	if not joining and Net.mode == Net.Mode.HOSTING and Net.room_size() >= seats:
		Net.start_room()
		return
	if not joining or Net.mode == Net.Mode.PLAYING:
		return
	# The two processes start at whatever moment the shell gets to them, so the joiner
	# keeps knocking until the host is listening.
	_retry_timer -= delta
	if _retry_timer <= 0.0:
		_try_join()

# by MatyanKass
func _try_join() -> void:
	_retries += 1
	_retry_timer = 1.0
	if _retries > 20:
		print("AUTOPLAY could not reach the host")
		get_tree().quit(3)
		return
	Net.join_room("127.0.0.1")

func _on_advanced() -> void:
	var state := Net.state
	if state == null:
		return
	if _done:
		return
	if state.tick_count >= STOP_AT_TICK or state.finished:
		print("AUTOPLAY player=%d tick=%d hash=%d cells=%d" % [
			Net.local_player, state.tick_count, state.state_hash(),
			int(state.aggregate(Net.local_player)["cells"])])
		_done = true
		_quit_timer = 3.0
		return
	if state.tick_count - _last_action_tick < ACT_EVERY_TICKS:
		return
	_last_action_tick = state.tick_count
	_act(state)

# Deliberately simple greed: houses, then factories, then push the border outwards.
func _act(state: GameState) -> void:
	var me := Net.local_player
	var agg := state.aggregate(me)
	var empty := _own_empty_cell(state, me)
	if empty >= 0:
		if int(state.coins[me]) >= int(Balance.BUILDINGS[Balance.Building.HOUSE]["coin_cost"]) \
				and int(agg["people"]) < 6:
			Net.request(GameState.Command.BUILD, empty, Balance.Building.HOUSE)
			return
		if int(agg["free_people"]) > 0 \
				and int(state.coins[me]) >= int(Balance.BUILDINGS[Balance.Building.FACTORY]["coin_cost"]):
			Net.request(GameState.Command.BUILD, empty, Balance.Building.FACTORY)
			return
	if int(state.power[me]) >= Balance.CAPTURE_POWER_COST:
		var target := _capturable(state, me)
		if target >= 0:
			Net.request(GameState.Command.CAPTURE, target)

func _own_empty_cell(state: GameState, player: int) -> int:
	for i in range(state.owner_of.size()):
		if int(state.owner_of[i]) == player and int(state.building_at[i]) == Balance.Building.NONE:
			return i
	return -1

func _capturable(state: GameState, player: int) -> int:
	for i in range(state.owner_of.size()):
		if state.is_land(i) and int(state.owner_of[i]) != player and state.touches_player(i, player):
			return i
	return -1
