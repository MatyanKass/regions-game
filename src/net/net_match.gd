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
# Emitted for every command the rules accepted, on both sides, so the interface can
# react to what really happened rather than to what was asked for.
signal command_applied(player: int, type: int, a: int, b: int)
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

# Set only in a practice match. When it is there, the host plays the second seat itself:
# the bot hands over commands and they enter the very same batch a second phone would
# have filled, so nothing else in the match loop knows the difference.
var bot: BotPlayer = null
# The world the host chose. It travels to the joiner at match start, so both sides
# generate the same map from the same seed.
var settings := WorldSettings.new()
# What the two sides call themselves. Exchanged when a match starts, so the panels
# can say who did something rather than "the opponent".
var opponent_name := ""
# The name this world is saved under, so saving again overwrites rather than piling
# up a new file every time.
var save_label := ""

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

func host_room(room_name: String, world: WorldSettings = null) -> bool:
	var chosen := world if world != null else WorldSettings.new()
	leave()
	settings = chosen
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
	if is_host and mode == Mode.PLAYING and multiplayer.has_multiplayer_peer():
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
	bot = null
	local_player = -1
	opponent_focus = -1
	opponent_name = ""
	save_label = ""
	_pending.clear()
	_hash_log.clear()
	_peer_of_player.clear()
	_accumulator = 0.0

# A match against nobody, for looking at the map while developing. It runs the very
# same tick loop; it simply has no peer to talk to.
func start_solo(seed_value: int, world: WorldSettings = null) -> void:
	var chosen := world if world != null else WorldSettings.new()
	leave()
	settings = chosen
	is_host = true
	_start_local(seed_value, 0)

# A world with nobody else in it: no opponent, no clock, no winning or losing. The same
# tick loop and the same rules, which is the whole point - it is somewhere to learn the
# game and somewhere to just build.
# Picks a world back up where it was left. The state is already made, so nothing is
# generated: the snapshot is the world.
func resume(state: GameState, bot_level: int) -> void:
	leave()
	settings = state.settings if state.settings != null else WorldSettings.new()
	is_host = true
	if bot_level >= 0 and state.alive.size() > 1:
		bot = BotPlayer.new(1, bot_level, state.map_seed ^ state.tick_count)
	self.state = state
	local_player = 0
	mode = Mode.PLAYING
	paused = false
	_accumulator = 0.0
	_hash_log.clear()
	emit_signal("match_started")

# Whether this world is one person's to save. Half of a match against another phone is
# not a world.
func can_save() -> bool:
	return mode == Mode.PLAYING and state != null \
		and not multiplayer.has_multiplayer_peer()

func start_free(world: WorldSettings) -> void:
	world.mode = WorldSettings.Mode.FREE
	leave()
	settings = world
	is_host = true
	_start_local(int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF), 0)

# Practice against the machine. Offline by design: there is no peer, no discovery and no
# hashing to do, only the local clock and a bot sitting in the second seat.
func start_practice(level: int, seed_value: int = 0, world: WorldSettings = null) -> void:
	var chosen := world if world != null else WorldSettings.new()
	chosen.mode = WorldSettings.Mode.MATCH
	leave()
	settings = chosen
	is_host = true
	var actual_seed := seed_value
	if actual_seed == 0:
		actual_seed = int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	bot = BotPlayer.new(1, level, actual_seed)
	_start_local(actual_seed, 0)

# --- Connection events -----------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_host or mode != Mode.HOSTING:
		return
	# Two-player match: the host is player 0, whoever knocks is player 1.
	_peer_of_player[0] = 1
	_peer_of_player[1] = id
	discovery.stop_broadcast()
	var seed_value := int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	_begin_match.rpc_id(id, seed_value, 1, settings.to_dict(), Prefs.display_name())
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
	state = GameState.create(seed_value, settings)
	local_player = player
	mode = Mode.PLAYING
	paused = false
	_accumulator = 0.0
	_hash_log.clear()
	emit_signal("match_started")

@rpc("authority", "call_remote", "reliable")
func _begin_match(seed_value: int, player: int, world: Dictionary, host_name: String) -> void:
	settings = WorldSettings.from_dict(world)
	opponent_name = host_name
	_start_local(seed_value, player)
	# The host does not know what to call us until we say so.
	_introduce.rpc_id(1, Prefs.display_name())

@rpc("any_peer", "call_remote", "reliable")
func _introduce(name: String) -> void:
	opponent_name = name

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
	_let_bot_play()
	var batch := PackedInt32Array(_pending)
	_pending.clear()
	_run_tick(batch, true)
	if multiplayer.has_multiplayer_peer():
		_advance.rpc(state.tick_count, batch)
	_hash_log[state.tick_count] = state.state_hash()
	if _hash_log.size() > HASH_HISTORY:
		var oldest: int = state.tick_count - HASH_HISTORY
		for key in _hash_log.keys():
			if int(key) < oldest:
				_hash_log.erase(key)

# The bot queues its commands like any other player, so they are stamped by the same
# tick, refused by the same rules and hashed into the same state. Its last move doubles
# as the focus marker, which is how the opponent panel shows where it is working.
func _let_bot_play() -> void:
	if bot == null or state == null:
		return
	for cmd in bot.take_turn(state):
		_queue(bot.player, int(cmd["type"]), int(cmd["a"]), int(cmd["b"]))
	opponent_focus = bot.focus_cell

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
		if reason.is_empty():
			emit_signal("command_applied", player, batch[i + 1], batch[i + 2], batch[i + 3])
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
	if multiplayer.has_multiplayer_peer():
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
	if mode != Mode.PLAYING or _local_focus < 0 or not multiplayer.has_multiplayer_peer():
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
