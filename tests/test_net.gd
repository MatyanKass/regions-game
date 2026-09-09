# Joining a game: the room code, and the parts of discovery that do not need a socket.
#
# This is exactly the code that is hard to test by playing - two phones, a router that
# may or may not pass broadcast traffic, and a code read out across a room - so all of it
# is written as plain functions over strings and tested here.
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

# --- The code -----------------------------------------------------------------------

func test_a_code_is_six_characters_and_a_dash() -> void:
	var code := RoomCode.encode("192.168.1.42")
	expect_eq(code.length(), RoomCode.LENGTH + 1, "a code is six characters with a dash in it")
	expect_eq(code[RoomCode.GROUP], RoomCode.SEPARATOR, "the dash sits in the middle")
	for i in range(code.length()):
		if i == RoomCode.GROUP:
			continue
		expect(RoomCode.ALPHABET.find(code[i]) >= 0,
			"'%s' is not a character the alphabet has" % code[i])

func test_every_address_on_a_home_network_survives_the_round_trip() -> void:
	var checked := 0
	for third in [0, 1, 8, 43, 100, 255]:
		for last in [1, 2, 42, 100, 200, 254]:
			var ip := "192.168.%d.%d" % [third, last]
			expect_eq(RoomCode.decode(RoomCode.encode(ip)), ip, "round trip of %s" % ip)
			checked += 1
	expect(checked >= 36, "the sweep should have covered the whole range")

func test_the_other_private_ranges_survive_it_too() -> void:
	for ip in ["10.0.0.5", "10.13.37.200", "172.16.0.9", "172.31.254.3",
			"169.254.7.11", "192.168.0.1"]:
		expect_eq(RoomCode.decode(RoomCode.encode(ip)), ip, "round trip of %s" % ip)

func test_two_addresses_never_share_a_code() -> void:
	var seen: Dictionary = {}
	for third in range(0, 40):
		for last in range(1, 40):
			for prefix in ["192.168", "10.0"]:
				var ip := "%s.%d.%d" % [prefix, third, last]
				var code := RoomCode.encode(ip)
				expect(not seen.has(code), "%s and %s share the code %s" % [ip, seen.get(code, ""), code])
				seen[code] = ip

# Two phones in the same room are on neighbouring addresses, and their codes must not be
# neighbours: a code is read aloud, and 000-4N7 next to 000-4N8 is a game joined by
# mistake.
func test_neighbouring_addresses_get_unlike_codes() -> void:
	var previous := RoomCode.normalise(RoomCode.encode("192.168.1.1"))
	for last in range(2, 60):
		var code := RoomCode.normalise(RoomCode.encode("192.168.1.%d" % last))
		var same := 0
		for i in range(code.length()):
			if code[i] == previous[i]:
				same += 1
		expect(same <= 3, "192.168.1.%d and the address before it share %d of six characters (%s, %s)"
			% [last, same, previous, code])
		previous = code

# The one written into the README and the specification. If the packing is ever retuned,
# this is what says so out loud rather than leaving the documents quietly wrong.
func test_the_documented_example_still_holds() -> void:
	expect_eq(RoomCode.encode("192.168.1.42"), "N50-7W3", "the example in the README")
	expect_eq(RoomCode.decode("N50-7W3"), "192.168.1.42", "and it reads back")

func test_an_address_no_code_can_carry_is_refused() -> void:
	# A public address, an address that is not a host, and things that are not addresses.
	for ip in ["8.8.8.8", "172.32.0.1", "192.168.1.0", "192.168.1.255", "127.0.0.1",
			"::1", "192.168.1", "192.168.1.999", "hello"]:
		expect_eq(RoomCode.encode(ip), "", "%s should have no code" % ip)

func test_a_code_read_out_wrong_still_works() -> void:
	var ip := "192.168.1.42"
	var code := RoomCode.encode(ip)
	var spoken := code.to_lower().replace(RoomCode.SEPARATOR, " ")
	expect_eq(RoomCode.decode(spoken), ip, "lower case with a space instead of the dash")
	expect_eq(RoomCode.decode(code.replace(RoomCode.SEPARATOR, "")), ip, "no dash at all")
	expect_eq(RoomCode.decode("  " + code + "  "), ip, "typed with spaces around it")
	# The characters the alphabet leaves out are the ones people substitute by eye.
	var mistyped := code.replace("1", "I").replace("0", "O").replace("V", "U")
	expect_eq(RoomCode.decode(mistyped), ip, "I for 1, O for 0 and U for V")

func test_a_wrong_code_is_refused_rather_than_dialled() -> void:
	var bad := 0
	var code := RoomCode.encode("192.168.1.42")
	var raw := RoomCode.normalise(code)
	# Every single-character slip: most must fail the check digits outright, and none of
	# them may come back as the address that was meant.
	for i in range(raw.length()):
		for c in RoomCode.ALPHABET:
			if raw[i] == c:
				continue
			var typo := raw.substr(0, i) + c + raw.substr(i + 1)
			var address := RoomCode.decode(typo)
			expect(address != "192.168.1.42", "%s must not decode to the right address" % typo)
			if address.is_empty():
				bad += 1
	expect(bad > raw.length() * 20, "the check digits should catch most single-character slips, caught %d" % bad)
	expect_eq(RoomCode.decode(""), "", "an empty line is not a code")
	expect_eq(RoomCode.decode("92B"), "", "half a code is not a code")

func test_a_code_is_told_apart_from_an_address() -> void:
	expect(RoomCode.looks_like_code("92B-7UV"), "six characters and a dash is a code")
	expect(RoomCode.looks_like_code("92b7uv"), "so is the same thing typed carelessly")
	expect(not RoomCode.looks_like_code("192.168.1.42"), "an address is not a code")
	expect(not RoomCode.looks_like_code(""), "nothing is not a code")

# What the lobby does with whatever was typed into the one box it offers. The match
# script is loaded rather than reached through the /root/Net autoload, which a headless
# test run does not have.
func test_the_lobby_accepts_a_code_or_an_address() -> void:
	var net = load("res://src/net/net_match.gd")
	var code := RoomCode.encode("192.168.4.7")
	expect_eq(net.resolve(code), "192.168.4.7", "a code resolves to its address")
	expect_eq(net.resolve(" " + code.to_lower() + " "), "192.168.4.7", "and does so however it is typed")
	expect_eq(net.resolve("10.0.0.4"), "10.0.0.4", "an address is passed through")
	expect_eq(net.resolve("regions.local"), "regions.local", "so is a host name")
	expect_eq(net.resolve("zzzzzz"), "", "and nonsense is refused before anything is dialled")
	expect_eq(net.resolve("   "), "", "as is an empty box")

# --- Discovery ------------------------------------------------------------------------

func test_the_shout_goes_to_every_network_this_device_is_on() -> void:
	var targets := LanDiscovery.broadcast_targets(PackedStringArray([
		"192.168.1.5", "192.168.1.9", "10.0.0.2", "127.0.0.1", "not an address"]))
	expect(targets.has("192.168.1.255"), "the home network's own broadcast address")
	expect(targets.has("10.0.0.255"), "and the other network's")
	expect(targets.has(LanDiscovery.GLOBAL_BROADCAST), "with the catch-all last")
	expect(not targets.has("127.0.0.255"), "loopback is not a network to look for games on")
	expect_eq(targets.size(), 3, "two networks and the catch-all, each once")

func test_an_announcement_survives_the_wire() -> void:
	var text := LanDiscovery.announcement("Магда", 8910, "92B-7UV")
	var room := LanDiscovery.parse_announcement(text)
	expect_eq(str(room.get("name", "")), "Магда", "the room name comes back as it went")
	expect_eq(int(room.get("port", 0)), 8910, "and the port with it")
	expect_eq(str(room.get("code", "")), "92B-7UV", "and the code the lobby shows")

func test_anything_else_on_the_port_is_ignored() -> void:
	for text in ["", "hello", "[1,2,3]", '{"magic":"something-else","port":8910}',
			'{"magic":"%s"}' % LanDiscovery.MAGIC,
			'{"magic":"%s","port":0}' % LanDiscovery.MAGIC,
			'{"magic":"%s","port":99999}' % LanDiscovery.MAGIC]:
		expect(LanDiscovery.parse_announcement(text).is_empty(),
			"should not be taken for a room: %s" % text)

func test_an_address_is_recognised_for_what_it_is() -> void:
	for good in ["0.0.0.0", "192.168.1.1", "255.255.255.255"]:
		expect(LanDiscovery.is_ipv4(good), "%s is an address" % good)
	for bad in ["192.168.1", "192.168.1.1.1", "192.168.1.256", "", "abc", "::1"]:
		expect(not LanDiscovery.is_ipv4(bad), "%s is not an address" % bad)
