# A room code: the host's address on the local network, written as six characters.
#
#     192.168.1.42  <->  N50-7W3
#
# Reading an IP address aloud across a room is how joining a game went wrong before.
# The code is not a lookup in a table somewhere - it *is* the address, packed, so no
# server has to remember anything and a code works the moment it is typed, even on a
# network that eats the broadcast traffic room discovery relies on.
#
# Thirty bits, six characters of five bits each:
#
#     [29..28] which private range          [27..4] the address inside it
#     [3..0]   check digits, so a mistyped code is refused rather than dialled
#
# The alphabet is Crockford's base32: no I, L, O or U, because those are the characters
# people get wrong when they read a code off someone else's screen. On the way back in,
# I and L are taken as 1, O as 0 and U as V, so a code read the wrong way still works.
class_name RoomCode
extends RefCounted

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const LENGTH := 6
const GROUP := 3          # where the dash goes: N50-7W3
const SEPARATOR := "-"
const BITS := 30
const MASK := (1 << BITS) - 1

# The bits as they come out are mostly zero - every home network is 192.168.something -
# so a plain packing would hand out 000-4N7 and 000-4N8 to two phones in the same room.
# Multiplying by an odd number modulo 2^30 is reversible and scatters them: neighbouring
# addresses get codes with nothing in common, which is what makes a code readable aloud
# without being confused for the one next to it. SCATTER_BACK is its inverse.
const SCATTER := 0x2F1B3C5
const SCATTER_BACK := 0x34BD530D

# The four ranges a phone or a laptop actually gets on a home network, a hotspot or a
# cable between two machines. Anything else has to be typed out as an address.
enum Kind { HOME, TEN, CARRIER, LINK_LOCAL }

# Returns "" when the address is not one a code can carry - a public address, IPv6, or
# something that cannot be a host.
static func encode(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var o := PackedInt32Array()
	for part in parts:
		if not part.is_valid_int():
			return ""
		var value := int(part)
		if value < 0 or value > 255:
			return ""
		o.append(value)
	# .0 is the network itself and .255 is everyone on it: neither can be a host.
	if o[3] == 0 or o[3] == 255:
		return ""

	var kind := -1
	var payload := 0
	if o[0] == 192 and o[1] == 168:
		kind = Kind.HOME
		payload = (o[2] << 8) | o[3]
	elif o[0] == 10:
		kind = Kind.TEN
		payload = (o[1] << 16) | (o[2] << 8) | o[3]
	elif o[0] == 172 and o[1] >= 16 and o[1] <= 31:
		kind = Kind.CARRIER
		payload = ((o[1] - 16) << 16) | (o[2] << 8) | o[3]
	elif o[0] == 169 and o[1] == 254:
		kind = Kind.LINK_LOCAL
		payload = (o[2] << 8) | o[3]
	else:
		return ""

	var body := (kind << 24) | payload
	var value := (((body << 4) | _check(body)) * SCATTER) & MASK
	var raw := ""
	for i in range(LENGTH - 1, -1, -1):
		raw += ALPHABET[(value >> (i * 5)) & 0x1F]
	return format(raw)

# Returns the address the code stands for, or "" if it is not a code at all or does not
# survive its own check digits.
static func decode(code: String) -> String:
	var raw := normalise(code)
	if raw.length() != LENGTH:
		return ""
	var value := 0
	for i in range(raw.length()):
		var digit := ALPHABET.find(raw[i])
		if digit < 0:
			return ""
		value = (value << 5) | digit
	value = (value * SCATTER_BACK) & MASK
	var body := value >> 4
	if (value & 0xF) != _check(body):
		return ""

	var kind := (body >> 24) & 0x3
	var payload := body & 0xFFFFFF
	var last := payload & 0xFF
	if last == 0 or last == 255:
		return ""
	match kind:
		Kind.HOME:
			if payload > 0xFFFF:
				return ""
			return "192.168.%d.%d" % [(payload >> 8) & 0xFF, last]
		Kind.TEN:
			return "10.%d.%d.%d" % [(payload >> 16) & 0xFF, (payload >> 8) & 0xFF, last]
		Kind.CARRIER:
			var high := (payload >> 16) & 0xFF
			if high > 15:
				return ""
			return "172.%d.%d.%d" % [16 + high, (payload >> 8) & 0xFF, last]
		Kind.LINK_LOCAL:
			if payload > 0xFFFF:
				return ""
			return "169.254.%d.%d" % [(payload >> 8) & 0xFF, last]
	return ""

# Whether a typed line is meant as a code rather than an address. An address has dots in
# it and a code does not, which is the whole of the distinction the lobby needs.
static func looks_like_code(text: String) -> bool:
	return not text.contains(".") and normalise(text).length() == LENGTH

# Everything that is not a letter or a digit is dropped, so spaces, dashes and a stray
# full stop all wash out; then the characters people confuse are folded onto the ones the
# alphabet actually has.
static func normalise(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text[i].to_upper()
		match c:
			"I", "L": c = "1"
			"O": c = "0"
			"U": c = "V"
		if ALPHABET.find(c) >= 0:
			out += c
	return out

static func format(raw: String) -> String:
	if raw.length() != LENGTH:
		return raw
	return raw.substr(0, GROUP) + SEPARATOR + raw.substr(GROUP)

# Four bits over the payload. It cannot correct a mistake, but it turns "the code you
# typed is one character out" from a connection attempt at a stranger's phone into a
# message saying the code is wrong.
static func _check(body: int) -> int:
	var sum := 0
	var value := body
	while value > 0:
		sum += value & 0xF
		value >>= 4
	return (sum ^ 0xA) & 0xF
