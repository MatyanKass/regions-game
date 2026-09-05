# Finding a game on the local network. The host shouts its room over UDP broadcast
# once a second; joiners listen and build a room list. No server, no internet.
#
# Typing an address by hand stays available in the lobby, because some routers and
# some phone hotspots quietly drop broadcast traffic.
class_name LanDiscovery
extends RefCounted

const PORT := 8911
const MAGIC := "regions-lan-1"
const BROADCAST_INTERVAL_MS := 1000
const ROOM_TIMEOUT_MS := 4000

var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _last_broadcast_ms := 0
var _room_name := ""
var _game_port := 0

# ip -> { "name": String, "port": int, "seen_ms": int }
var rooms: Dictionary = {}

func start_broadcast(room_name: String, game_port: int) -> void:
	stop_broadcast()
	_room_name = room_name
	_game_port = game_port
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", PORT)
	_last_broadcast_ms = 0

func stop_broadcast() -> void:
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null

func start_listen() -> bool:
	stop_listen()
	_listener = PacketPeerUDP.new()
	if _listener.bind(PORT) != OK:
		_listener = null
		return false
	rooms.clear()
	return true

func stop_listen() -> void:
	if _listener:
		_listener.close()
		_listener = null
	rooms.clear()

# Call every frame. Returns true when the room list changed and the UI should redraw.
func poll() -> bool:
	var now := Time.get_ticks_msec()
	if _broadcaster and now - _last_broadcast_ms >= BROADCAST_INTERVAL_MS:
		_last_broadcast_ms = now
		var payload := JSON.stringify({"magic": MAGIC, "name": _room_name, "port": _game_port})
		_broadcaster.put_packet(payload.to_utf8_buffer())

	var changed := false
	if _listener:
		while _listener.get_available_packet_count() > 0:
			var ip := _listener.get_packet_ip()
			var text := _listener.get_packet().get_string_from_utf8()
			var parsed = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY or parsed.get("magic", "") != MAGIC:
				continue
			var known: bool = rooms.has(ip)
			rooms[ip] = {
				"name": str(parsed.get("name", ip)),
				"port": int(parsed.get("port", 0)),
				"seen_ms": now,
			}
			if not known:
				changed = true
		for ip in rooms.keys():
			if now - int(rooms[ip]["seen_ms"]) > ROOM_TIMEOUT_MS:
				rooms.erase(ip)
				changed = true
	return changed
