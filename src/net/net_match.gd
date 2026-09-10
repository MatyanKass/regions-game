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
# The room while it fills up: who is in it, and who has just gone.
signal roster_changed
signal player_left(player: int)

const GAME_PORT := 8910
const HASH_EVERY := 50
const HASH_HISTORY := 400
# ENet keeps knocking at an address that is not answering, and on a phone that means the
# lobby says "connecting" until the player gives up. After this long, so do we.
const JOIN_TIMEOUT_MS := 8000

enum Mode { IDLE, HOSTING, JOINING, PLAYING }

var mode: int = Mode.IDLE
var state: GameState = null
var local_player := -1
var is_host := false
var paused := false

# While hosting: the address this device is reachable at, and that address written as the
# six characters the other player types. Both are empty when there is no network.
var host_address := ""
var room_code := ""

var discovery := LanDiscovery.new()

# Set only in a practice match. When it is there, the host plays the second seat itself:
# the bot hands over commands and they enter the very same batch a second phone would
# have filled, so nothing else in the match loop knows the difference.
var bot: BotPlayer = null
# The world the host chose. It travels to the joiner at match start, so both sides
# generate the same map from the same seed.
var settings := WorldSettings.new()
# Everyone in the room, in seat order: seat 0 is the host. Filled while the room waits
# and frozen when the match starts, at which point a seat's position in this list is the
# player index the simulation knows it by.
#
# Each seat is { "peer": int, "name": String, "region": int, "here": bool }. On a client
# it is what the host last sent; on the host it is the truth.
var seats: Array[Dictionary] = []
# Where each player is looking, for the marker on the map. One entry per seat, -1 when
# they have not said.
var focus_of: PackedInt32Array = PackedInt32Array()
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
var _join_deadline := 0
var _greeted := false      # a client says who it is once, when it gets through

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
	var err := peer.create_server(GAME_PORT, maxi(1, chosen.player_count() - 1))
	if err != OK:
		# The port is the only thing that ever stops this, and saying so matters: "could
		# not connect" sends people off to look at a router that is working fine, when the
		# answer is the previous match still holding the port for another second.
		var busy := err == ERR_ALREADY_IN_USE or err == ERR_CANT_CREATE
		emit_signal("lobby_status", I18n.t("port_busy" if busy else "connect_failed"))
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	mode = Mode.HOSTING
	seats = [_seat(1, Prefs.display_name(), Prefs.region())]
	emit_signal("roster_changed")
	var addresses := LanDiscovery.local_ipv4s()
	host_address = addresses[0] if addresses.size() > 0 else ""
	room_code = RoomCode.encode(host_address)
	discovery.start_broadcast(room_name, GAME_PORT, room_code)
	emit_signal("lobby_status", I18n.t("waiting_player") if not host_address.is_empty() else I18n.t("no_address"))
	return true

func browse_rooms() -> void:
	discovery.start_listen()

# A code or an address, whichever the player typed - the code is only the host address
# written short, so both roads end at the same place. Returns "" when it is neither.
static func resolve(target: String) -> String:
	var text := target.strip_edges()
	if text.is_empty():
		return ""
	if RoomCode.looks_like_code(text):
		return RoomCode.decode(text)
	if LanDiscovery.is_ipv4(text) or text.contains("."):
		return text
	return ""

func join_room(target: String) -> bool:
	var address := resolve(target)
	if address.is_empty():
		emit_signal("lobby_status", I18n.t("bad_code"))
		return false
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, GAME_PORT) != OK:
		emit_signal("lobby_status", I18n.t("connect_failed"))
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	mode = Mode.JOINING
	_greeted = false
	_join_deadline = Time.get_ticks_msec() + JOIN_TIMEOUT_MS
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
	host_address = ""
	room_code = ""
	seats = []
	focus_of = PackedInt32Array()
	_join_deadline = 0
	_greeted = false
	emit_signal("roster_changed")
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
	seats = [_seat(1, Prefs.display_name(), Prefs.region())]
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
	seats = [_seat(1, Prefs.display_name(), Prefs.region())]
	if bot_level >= 0 and state.alive.size() > 1:
		bot = BotPlayer.new(1, bot_level, state.map_seed ^ state.tick_count)
	self.state = state
	local_player = 0
	mode = Mode.PLAYING
	paused = false
	_accumulator = 0.0
	_hash_log.clear()
	focus_of = PackedInt32Array()
	focus_of.resize(state.player_count())
	focus_of.fill(-1)
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
	seats = [_seat(1, Prefs.display_name(), Prefs.region())]
	_start_local(int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF), 0)

# Practice against the machine. Offline by design: there is no peer, no discovery and no
# hashing to do, only the local clock and a bot sitting in the second seat.
func start_practice(level: int, seed_value: int = 0, world: WorldSettings = null) -> void:
	var chosen := world if world != null else WorldSettings.new()
	chosen.mode = WorldSettings.Mode.MATCH
	# One bot, so one opponent, whatever the room size in the lobby happens to be set to.
	chosen.players = 2
	leave()
	settings = chosen
	is_host = true
	seats = [_seat(1, Prefs.display_name(), Prefs.region())]
	var actual_seed := seed_value
	if actual_seed == 0:
		actual_seed = int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	bot = BotPlayer.new(1, level, actual_seed)
	_start_local(actual_seed, 0)

# --- The room ---------------------------------------------------------------------

static func _seat(peer: int, name: String, region: int) -> Dictionary:
	return {"peer": peer, "name": name, "region": region, "here": true}

# How many seats are filled, and how many the world was opened for.
func room_size() -> int:
	return seats.size()

func room_capacity() -> int:
	return settings.player_count() if settings != null else 2

func seat_of_peer(peer: int) -> int:
	for i in range(seats.size()):
		if int(seats[i]["peer"]) == peer:
			return i
	return -1

func name_of(player: int) -> String:
	if bot != null and player == bot.player:
		return "%s (%s)" % [I18n.t("bot"), I18n.bot_level_name(bot.level)]
	if player >= 0 and player < seats.size():
		var name := str(seats[player]["name"])
		if not name.is_empty():
			return name
	if player == local_player:
		return Prefs.display_name()
	return "%s %d" % [I18n.t("player"), player + 1]

# Whether that seat still has somebody behind it. A player who walks out leaves their
# country standing: it stops doing anything, but it does not vanish mid-match.
func is_here(player: int) -> bool:
	if player < 0 or player >= seats.size():
		return true
	return bool(seats[player]["here"])

func humans_here() -> int:
	var count := 0
	for seat in seats:
		if bool(seat["here"]):
			count += 1
	return count

# The host decides when the room is full enough to play. Everyone in it at that moment
# gets a seat, and the seat order is the player order for the rest of the match.
func start_room() -> bool:
	if not is_host or mode != Mode.HOSTING or seats.size() < 2:
		return false
	discovery.stop_broadcast()
	settings.players = seats.size()
	var seed_value := int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	var roster := _roster_wire()
	_peer_of_player.clear()
	for i in range(seats.size()):
		_peer_of_player[i] = int(seats[i]["peer"])
		if i > 0:
			_begin_match.rpc_id(int(seats[i]["peer"]), seed_value, i, settings.to_dict(), roster)
	_start_local(seed_value, 0)
	return true

func _roster_wire() -> Array:
	var out: Array = []
	for seat in seats:
		out.append({"name": str(seat["name"]), "region": int(seat["region"])})
	return out

func _adopt_roster(roster: Array) -> void:
	seats = []
	for entry in roster:
		var seat: Dictionary = entry
		seats.append(_seat(0, str(seat.get("name", "")), int(seat.get("region", Regions.NONE))))
	emit_signal("roster_changed")

# --- Connection events -----------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_host or mode != Mode.HOSTING:
		return
	if seats.size() >= room_capacity():
		# The room is full. Saying so and closing the door is kinder than a silent
		# connection that never becomes a match.
		_room_full.rpc_id(id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# The name and the region arrive a moment later, in _hello; until then the seat is
	# taken but nameless, which is exactly what it looks like on the host's screen.
	seats.append(_seat(id, "", Regions.NONE))
	_broadcast_roster()
	emit_signal("lobby_status", I18n.t("waiting_player"))

# A client says who it is once, as soon as it is through the door.
@rpc("any_peer", "call_remote", "reliable")
func _hello(name: String, region: int) -> void:
	if not is_host:
		return
	var seat := seat_of_peer(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	seats[seat]["name"] = name
	seats[seat]["region"] = region if Regions.valid(region) else Regions.NONE
	_broadcast_roster()

@rpc("authority", "call_remote", "reliable")
func _roster(roster: Array) -> void:
	_adopt_roster(roster)

@rpc("authority", "call_remote", "reliable")
func _room_full() -> void:
	leave()
	emit_signal("connection_lost", I18n.t("room_full"))

func _broadcast_roster() -> void:
	emit_signal("roster_changed")
	if multiplayer.has_multiplayer_peer():
		_roster.rpc(_roster_wire())

func _on_peer_disconnected(id: int) -> void:
	var seat := seat_of_peer(id) if is_host else -1
	if mode == Mode.PLAYING:
		if seat >= 0:
			seats[seat]["here"] = false
			emit_signal("player_left", seat)
			if multiplayer.has_multiplayer_peer():
				_player_left.rpc(seat)
		# One person alone in what was a match is not a match. That is the case the
		# waiting overlay was written for, and it is still the only one worth stopping
		# the clock over: with four players, one leaving is just one fewer country.
		if humans_here() <= 1:
			paused = true
			emit_signal("pause_changed", true)
			emit_signal("opponent_disconnected")
		return
	if is_host and seat >= 0:
		seats.remove_at(seat)
		_broadcast_roster()
		emit_signal("lobby_status", I18n.t("waiting_player"))

@rpc("authority", "call_remote", "reliable")
func _player_left(player: int) -> void:
	if player >= 0 and player < seats.size():
		seats[player]["here"] = false
	emit_signal("player_left", player)

func _on_connected() -> void:
	# Through the door and into the room: the wait is now on the host, not the network,
	# so the join clock stops here.
	_join_deadline = 0
	emit_signal("lobby_status", I18n.t("in_room"))
	if not _greeted:
		_greeted = true
		_hello.rpc_id(1, Prefs.display_name(), Prefs.region())

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
	_dress_players(seed_value)
	focus_of = PackedInt32Array()
	focus_of.resize(state.player_count())
	focus_of.fill(-1)
	emit_signal("match_started")

# Every seat gets the colour its region rolls up. Worked out from the seed on each
# device rather than sent, so there is nothing to disagree about and a client that
# resyncs mid-match keeps the colours it already had.
func _dress_players(seed_value: int) -> void:
	var regions := PackedByteArray()
	for i in range(state.player_count()):
		regions.append(int(seats[i]["region"]) if i < seats.size() else Regions.NONE)
	Regions.assign_all(state, seed_value, regions)

@rpc("authority", "call_remote", "reliable")
func _begin_match(seed_value: int, player: int, world: Dictionary, roster: Array) -> void:
	settings = WorldSettings.from_dict(world)
	_adopt_roster(roster)
	_join_deadline = 0
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
	_check_join_timeout()
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

# ENet answers a wrong address with silence rather than a refusal, so the lobby needs a
# clock of its own: nobody home by now means nobody home.
func _check_join_timeout() -> void:
	if mode != Mode.JOINING or _join_deadline == 0:
		return
	if Time.get_ticks_msec() < _join_deadline:
		return
	leave()
	emit_signal("connection_lost", I18n.t("no_answer"))

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
	_note_focus(bot.player, bot.focus_cell)

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

# --- Camera sharing: the panels show where everyone else is looking ---------------
#
# Clients cannot talk to each other, so a look goes to the host and the host passes it
# on. It is one small unreliable packet every half second per player.

func set_local_focus(cell: int) -> void:
	_local_focus = cell

func focus_cell_of(player: int) -> int:
	if player < 0 or player >= focus_of.size():
		return -1
	return int(focus_of[player])

func _note_focus(player: int, cell: int) -> void:
	if player >= 0 and player < focus_of.size():
		focus_of[player] = cell

func _report_focus(delta: float) -> void:
	if mode != Mode.PLAYING or _local_focus < 0 or not multiplayer.has_multiplayer_peer():
		return
	_focus_timer -= delta
	if _focus_timer > 0.0:
		return
	_focus_timer = 0.5
	if is_host:
		_note_focus(local_player, _local_focus)
		_focus_set.rpc(local_player, _local_focus)
	else:
		_focus_report.rpc_id(1, _local_focus)

@rpc("any_peer", "call_remote", "unreliable")
func _focus_report(cell: int) -> void:
	if not is_host:
		return
	var player := seat_of_peer(multiplayer.get_remote_sender_id())
	if player < 0:
		return
	_note_focus(player, cell)
	_focus_set.rpc(player, cell)

@rpc("authority", "call_remote", "unreliable")
func _focus_set(player: int, cell: int) -> void:
	_note_focus(player, cell)

# Everyone in the match except whoever is holding this phone, in seat order.
func others() -> PackedInt32Array:
	var out := PackedInt32Array()
	if state == null:
		return out
	for p in range(state.player_count()):
		if p != local_player:
			out.append(p)
	return out

# The one other player, when there is only one - a match against the bot, or one phone
# against another. -1 in a crowd, where "the opponent" is not a person.
func opponent_index() -> int:
	var rest := others()
	return int(rest[0]) if rest.size() == 1 else -1
