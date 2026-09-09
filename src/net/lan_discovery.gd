# Finding a game on the local network. The host shouts its room over UDP once a second;
# everyone in the lobby listens and builds a list. No server, no internet.
#
# Three things this has to survive, because all three happen on real phones:
#
#   * 255.255.255.255 is dropped by plenty of routers and by most phone hotspots, so the
#     shout also goes to the broadcast address of every network this device is actually
#     on (192.168.1.255 and friends). One of them usually gets through.
#   * the listening port can be busy for a second or two after a previous match, so a
#     failed bind is retried instead of leaving the lobby deaf for good.
#   * the host hears its own shout, and a room that is yourself is not a room.
#
# When even that fails, the room code in the lobby is the way in: it needs no broadcast
# at all, only a phone that can reach the host directly.
class_name LanDiscovery
extends RefCounted

const PORT := 8911
const MAGIC := "regions-lan-2"
const BROADCAST_INTERVAL_MS := 1000
const ROOM_TIMEOUT_MS := 5000
const REBIND_INTERVAL_MS := 2000
const TARGET_REFRESH_MS := 5000
const GLOBAL_BROADCAST := "255.255.255.255"

# ip -> { "name": String, "port": int, "code": String, "seen_ms": int }
var rooms: Dictionary = {}

var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _targets := PackedStringArray()
var _own: Dictionary = {}
var _last_broadcast_ms := 0
var _last_targets_ms := 0
var _last_bind_ms := 0
var _want_listen := false
var _room_name := ""
var _room_code := ""
var _game_port := 0

# --- Hosting ----------------------------------------------------------------------

func start_broadcast(room_name: String, game_port: int, code: String = "") -> void:
	stop_broadcast()
	_room_name = room_name
	_room_code = code
	_game_port = game_port
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_refresh_targets()
	_last_broadcast_ms = 0

func stop_broadcast() -> void:
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null

# --- Browsing ---------------------------------------------------------------------

func start_listen() -> bool:
	stop_listen()
	_want_listen = true
	return _try_bind()

func stop_listen() -> void:
	_want_listen = false
	if _listener:
		_listener.close()
		_listener = null
	rooms.clear()

func listening() -> bool:
	return _listener != null

func _try_bind() -> bool:
	_last_bind_ms = Time.get_ticks_msec()
	var socket := PacketPeerUDP.new()
	socket.set_broadcast_enabled(true)
	if socket.bind(PORT) != OK:
		return false
	_listener = socket
	return true

# --- The pump: call every frame ---------------------------------------------------

# Returns true when the room list changed and the lobby should redraw itself.
func poll() -> bool:
	var now := Time.get_ticks_msec()
	_shout(now)
	if _want_listen and _listener == null and now - _last_bind_ms >= REBIND_INTERVAL_MS:
		_try_bind()
	var changed := _receive(now)
	return _forget_silent_rooms(now) or changed

func _shout(now: int) -> void:
	if _broadcaster == null or now - _last_broadcast_ms < BROADCAST_INTERVAL_MS:
		return
	_last_broadcast_ms = now
	# A phone changes network under us - it joins a hotspot, or Wi-Fi drops to mobile
	# data - and the addresses to shout at change with it.
	if now - _last_targets_ms >= TARGET_REFRESH_MS:
		_refresh_targets()
	var payload := announcement(_room_name, _game_port, _room_code).to_utf8_buffer()
	for target in _targets:
		_broadcaster.set_dest_address(target, PORT)
		_broadcaster.put_packet(payload)

func _receive(now: int) -> bool:
	if _listener == null:
		return false
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var ip := _listener.get_packet_ip()
		var room := parse_announcement(_listener.get_packet().get_string_from_utf8())
		if room.is_empty():
			continue
		# A broadcast packet does not always arrive with a sender to answer - it happens
		# on real networks, and a room with no address is a room nobody can join. The
		# shout carries the host's own code, which is that address written down, so it
		# says where it came from even when the packet does not.
		if not is_ipv4(ip):
			ip = RoomCode.decode(str(room.get("code", "")))
			if not is_ipv4(ip):
				continue
		if _own.has(ip):
			continue
		var before: Dictionary = rooms.get(ip, {})
		if str(before.get("name", "")) != str(room["name"]) or int(before.get("port", 0)) != int(room["port"]):
			changed = true
		room["seen_ms"] = now
		rooms[ip] = room
	return changed

func _forget_silent_rooms(now: int) -> bool:
	var changed := false
	for ip in rooms.keys():
		if now - int(rooms[ip]["seen_ms"]) > ROOM_TIMEOUT_MS:
			rooms.erase(ip)
			changed = true
	return changed

func _refresh_targets() -> void:
	_last_targets_ms = Time.get_ticks_msec()
	var addresses := local_ipv4s()
	_targets = broadcast_targets(addresses)
	_own = {}
	for address in addresses:
		_own[address] = true

# --- The parts with no socket in them, so a test can have them --------------------

# Every IPv4 address this device holds, loopback dropped, most likely LAN address first.
# The order is what decides which address becomes the room code.
static func local_ipv4s() -> PackedStringArray:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		var text := str(address)
		if not is_ipv4(text) or text.begins_with("127."):
			continue
		if not found.has(text):
			found.append(text)
	found.sort_custom(func(a: String, b: String) -> bool: return _rank(a) < _rank(b))
	var out := PackedStringArray()
	for address in found:
		out.append(address)
	return out

# Home networks first, then the ranges a big office or a hotspot hands out, then the
# address a device gives itself when nothing handed it one at all.
static func _rank(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	if ip.begins_with("172."):
		return 2
	if ip.begins_with("169.254."):
		return 4
	return 3

static func is_ipv4(text: String) -> bool:
	var parts := text.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return false
	return true

# Where the shout is sent: the broadcast address of each network this device is on,
# and 255.255.255.255 last as the fallback for anything not covered.
#
# Assuming a /24 is a simplification, and the right one: every network a phone joins by
# itself - home routers, hotspots, the cable between two laptops - is one.
static func broadcast_targets(addresses: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for address in addresses:
		if not is_ipv4(address) or address.begins_with("127."):
			continue
		var parts := address.split(".")
		var subnet := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not out.has(subnet):
			out.append(subnet)
	out.append(GLOBAL_BROADCAST)
	return out

static func announcement(room_name: String, game_port: int, code: String) -> String:
	return JSON.stringify({
		"magic": MAGIC,
		"name": room_name,
		"port": game_port,
		"code": code,
	})

# Returns { "name", "port", "code" } for one of our own announcements, or {} for anything
# else on the port - another game, an older version, or noise.
static func parse_announcement(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if str(parsed.get("magic", "")) != MAGIC:
		return {}
	var port := int(parsed.get("port", 0))
	if port <= 0 or port > 65535:
		return {}
	return {
		"name": str(parsed.get("name", "")),
		"port": port,
		"code": str(parsed.get("code", "")),
	}
