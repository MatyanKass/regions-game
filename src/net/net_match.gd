# Autoloaded as /root/Net. Owns the connection, the match clock and the shared
# simulation.
#
# The host is the sequencer: it is the only side with a clock. Every tick it stamps the
# commands it has received, applies them, steps the simulation and broadcasts that exact
# command list. Clients never step on their own - they step when a batch arrives. Both
# sides therefore run identical input over identical code, and a client can never run
# ahead of what the host has agreed to.
#
# A client's own tap is not applied locally first: it goes to the host and comes back a
# few milliseconds later on a LAN. That costs nothing noticeable and removes the need
# for rollback entirely.
extends Node

signal rooms_changed
signal lobby_status(text: String)
signal match_started
signal match_advanced
signal match_finished
signal command_refused(reason: String)
signal opponent_disconnected
signal connection_lost(reason: String)
signal pause_changed(paused: bool)

const GAME_PORT := 8910
const HASH_EVERY := 50
const HASH_HISTORY := 400

enum Mode { IDLE, HOSTING, JOINING, PLAYING }

var mode: int = Mode.IDLE
var state: GameState = null
var local_player := -1
var is_host := false
var paused := false
var opponent_focus := -1

var discovery := LanDiscovery.new()

var _tick_seconds := 1.0 / float(Balance.TICKS_PER_SECOND)
var _accumulator := 0.0
var _pending: Array[int] = []          # flat [player, type, a, b] awaiting the next tick
var _hash_log: Dictionary = {}         # host only: tick -> hash
var _peer_of_player: Dictionary = {}   # player index -> multiplayer peer id
var _local_focus := -1
var _focus_timer := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Lobby -----------------------------------------------------------------------

func host_room(room_name: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(GAME_PORT, 1) != OK:
		emit_signal("lobby_status", I18n.t("connect_failed"))
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	mode = Mode.HOSTING
	discovery.start_broadcast(room_name, GAME_PORT)
	emit_signal("lobby_status", I18n.t("waiting_player"))
	return true

func browse_rooms() -> void:
	discovery.start_listen()

func join_room(ip: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, GAME_PORT) != OK:
		emit_signal("lobby_status", I18n.t("connect_failed"))
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	mode = Mode.JOINING
	emit_signal("lobby_status", I18n.t("connecting"))
	return true

func leave() -> void:
	if is_host and mode == Mode.PLAYING:
		_host_closing.rpc()
	discovery.stop_broadcast()
	discovery.stop_listen()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.IDLE
	is_host = false
	paused = false
	state = null
	local_player = -1
	opponent_focus = -1
	_pending.clear()
	_hash_log.clear()
	_peer_of_player.clear()
	_accumulator = 0.0

# --- Connection events -----------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_host or mode != Mode.HOSTING:
		return
	# Two-player match: the host is player 0, whoever knocks is player 1.
	_peer_of_player[0] = 1
	_peer_of_player[1] = id
	discovery.stop_broadcast()
	var seed_value := int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	_begin_match.rpc_id(id, seed_value, 1)
	_start_local(seed_value, 0)

func _on_peer_disconnected(_id: int) -> void:
	if mode == Mode.PLAYING:
		paused = true
		emit_signal("pause_changed", true)
		emit_signal("opponent_disconnected")
	elif mode == Mode.HOSTING:
		emit_signal("lobby_status", I18n.t("waiting_player"))

func _on_connected() -> void:
	emit_signal("lobby_status", I18n.t("connecting"))

func _on_connect_failed() -> void:
	leave()
	emit_signal("connection_lost", I18n.t("connect_failed"))

func _on_server_disconnected() -> void:
	leave()
	emit_signal("connection_lost", I18n.t("host_closed"))

# --- Match start -----------------------------------------------------------------

func _start_local(seed_value: int, player: int) -> void:
	state = GameState.create(seed_value, 2)
	local_player = player
	mode = Mode.PLAYING
	paused = false
	_accumulator = 0.0
	_hash_log.clear()
	emit_signal("match_started")

@rpc("authority", "call_remote", "reliable")
func _begin_match(seed_value: int, player: int) -> void:
	_start_local(seed_value, player)

@rpc("authority", "call_remote", "reliable")
func _host_closing() -> void:
	leave()
	emit_signal("connection_lost", I18n.t("host_closed"))

# --- Commands --------------------------------------------------------------------

# Called by the UI. On the host the command waits for the next tick; on a client it
# travels to the host and comes back inside a tick batch.
func request(type: int, a: int, b: int = 0) -> void:
	if mode != Mode.PLAYING or state == null or state.finished:
		return
	if is_host:
		_queue(local_player, type, a, b)
	else:
		_submit.rpc_id(1, type, a, b)

@rpc("any_peer", "call_remote", "reliable")
func _submit(type: int, a: int, b: int) -> void:
	if not is_host or mode != Mode.PLAYING:
		return
	var sender := multiplayer.get_remote_sender_id()
	for player in _peer_of_player:
		if int(_peer_of_player[player]) == sender:
			_queue(int(player), type, a, b)
			return

func _queue(player: int, type: int, a: int, b: int) -> void:
	_pending.append(player)
	_pending.append(type)
	_pending.append(a)
	_pending.append(b)

@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	emit_signal("command_refused", I18n.reason(reason))

# --- The clock: host only --------------------------------------------------------

func _process(delta: float) -> void:
	if discovery.poll():
		emit_signal("rooms_changed")
	_report_focus(delta)
	if mode != Mode.PLAYING or not is_host or paused or state == null or state.finished:
		return
	_accumulator += delta
	# A long stall (app resumed from background) must not turn into a burst of ticks.
	var budget := 8
	while _accumulator >= _tick_seconds and budget > 0:
		_accumulator -= _tick_seconds
		budget -= 1
		_host_tick()
	if budget == 0:
		_accumulator = 0.0

func _host_tick() -> void:
	var batch := PackedInt32Array(_pending)
	_pending.clear()
	_run_tick(batch, true)
	_advance.rpc(state.tick_count, batch)
	_hash_log[state.tick_count] = state.state_hash()
	if _hash_log.size() > HASH_HISTORY:
		var oldest: int = state.tick_count - HASH_HISTORY
		for key in _hash_log.keys():
			if int(key) < oldest:
				_hash_log.erase(key)

@rpc("authority", "call_remote", "reliable")
func _advance(tick: int, batch: PackedInt32Array) -> void:
	if state == null:
		return
	_run_tick(batch, false)
	if tick % HASH_EVERY == 0:
		_hash_check.rpc_id(1, tick, state.state_hash())

func _run_tick(batch: PackedInt32Array, report_refusals: bool) -> void:
	var i := 0
	while i + 3 < batch.size():
		var player := batch[i]
		var cmd := GameState.make_command(batch[i + 1], batch[i + 2], batch[i + 3])
		var reason := state.apply_command(player, cmd)
		if report_refusals and not reason.is_empty():
			if player == local_player:
				emit_signal("command_refused", I18n.reason(reason))
			elif _peer_of_player.has(player):
				_refused.rpc_id(int(_peer_of_player[player]), reason)
		i += 4
	state.tick()
	emit_signal("match_advanced")
	if state.finished:
		emit_signal("match_finished")

# --- Desync detection ------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hash_check(tick: int, client_hash: int) -> void:
	if not is_host or not _hash_log.has(tick):
		return
	if int(_hash_log[tick]) == client_hash:
		return
	# The client drifted. Rather than argue about who is right, the host simply ships
	# its own state over; on a 25x25 map that is a few kilobytes.
	push_warning("Desync at tick %d, resyncing client" % tick)
	_resync.rpc_id(multiplayer.get_remote_sender_id(), state.snapshot())

@rpc("authority", "call_remote", "reliable")
func _resync(data: Dictionary) -> void:
	state = GameState.from_snapshot(data)
	emit_signal("match_advanced")

# --- Pause -----------------------------------------------------------------------

func set_paused(value: bool) -> void:
	if not is_host:
		return
	paused = value
	_set_paused.rpc(value)
	emit_signal("pause_changed", value)

@rpc("authority", "call_remote", "reliable")
func _set_paused(value: bool) -> void:
	paused = value
	emit_signal("pause_changed", value)

# --- Camera sharing: the opponent panel shows where the other player is looking ---

func set_local_focus(cell: int) -> void:
	_local_focus = cell

func _report_focus(delta: float) -> void:
	if mode != Mode.PLAYING or _local_focus < 0:
		return
	_focus_timer -= delta
	if _focus_timer > 0.0:
		return
	_focus_timer = 0.5
	if is_host:
		if _peer_of_player.has(1):
			_focus.rpc_id(int(_peer_of_player[1]), _local_focus)
	else:
		_focus.rpc_id(1, _local_focus)

@rpc("any_peer", "call_remote", "unreliable")
func _focus(cell: int) -> void:
	opponent_focus = cell

func opponent_index() -> int:
	return 1 - local_player
