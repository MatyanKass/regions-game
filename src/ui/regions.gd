# Where a player is playing from, and the colour that comes out of it.
#
# Picking a region is picking a palette, not a colour: Africa is yellow, orange or red,
# and which of the three you get is rolled when the match starts. Two players who choose
# the same region still end up telling their territories apart, because a colour already
# taken is passed over.
#
# The list is ordered, and the order is what travels over the wire and into a save, so
# regions may be added to the end but never rearranged.
class_name Regions
extends RefCounted

const NONE := GameState.NO_REGION

# Colours are packed 0xRRGGBB. They have to read as ink on cream paper, which rules out
# white and anything pale: every one of these is a pen you could actually buy.
const LIST := [
	{"key": "africa", "colours": [0xD8A207, 0xE2701E, 0xC2281C]},
	{"key": "europe", "colours": [0x1B4FA0, 0x6B3FA0, 0x8C1F3F]},
	{"key": "asia", "colours": [0xBD2F22, 0xC8961B, 0x1F7A4D]},
	{"key": "middle_east", "colours": [0x0F6B45, 0xA8241B, 0x27354F]},
	{"key": "latin_america", "colours": [0x1F8A3D, 0xD4A017, 0x1F5FBF]},
	{"key": "north_america", "colours": [0x28418C, 0xB52A20, 0x55617A]},
	{"key": "nordic", "colours": [0x1B6FB5, 0x3A9FD6, 0x46607A]},
	{"key": "oceania", "colours": [0x0F7F8F, 0x2E8B57, 0x7A3FA0]},
]

# What a seat is coloured when nobody chose a region: a bot, free play, or a world saved
# before regions existed. Eight of them, so a full room never runs out.
const DEFAULT_PENS := [0x1B4FA0, 0xBD2F22, 0x1F7A4D, 0xC8961B,
	0x6B3FA0, 0x0F7F8F, 0xE2701E, 0x55617A]

static func count() -> int:
	return LIST.size()

static func valid(region: int) -> bool:
	return region >= 0 and region < LIST.size()

static func key_of(region: int) -> String:
	return str(LIST[region]["key"]) if valid(region) else ""

static func name_of(region: int) -> String:
	if not valid(region):
		return I18n.t("region_any")
	return I18n.t("region_" + key_of(region))

static func palette(region: int) -> Array:
	return LIST[region]["colours"] if valid(region) else []

# The colour this player ends up with. Rolled from the match seed, so every device works
# it out the same way, and stepped along the palette when the roll lands on a colour
# somebody already has. If the whole palette is spoken for - four players from the same
# region - the colour is shaded instead, which keeps them apart without inventing a
# colour from outside the palette they chose.
static func colour_for(region: int, seed_value: int, player: int, taken: PackedInt32Array) -> int:
	var choices := palette(region)
	if choices.is_empty():
		return fallback(player, taken)
	var rng := SimRng.new(seed_value ^ (0x9E37 * (player + 1)))
	var start := rng.next_range(choices.size())
	for i in range(choices.size()):
		var colour := int(choices[(start + i) % choices.size()])
		if not taken.has(colour):
			return colour
	var base := int(choices[start])
	for step in range(1, 5):
		for direction in [step, -step]:
			var shaded := shade(base, direction * 14)
			if not taken.has(shaded):
				return shaded
	return base

# Nobody chose - a bot, free play, or a save from before regions existed. The interface's
# own pens, in order, so the colours are at least always different from each other.
static func fallback(player: int, taken: PackedInt32Array = PackedInt32Array()) -> int:
	for i in range(DEFAULT_PENS.size()):
		var colour := int(DEFAULT_PENS[(player + i) % DEFAULT_PENS.size()])
		if not taken.has(colour):
			return colour
	return int(DEFAULT_PENS[player % DEFAULT_PENS.size()])

# Percent lighter or darker, staying inside the range a biro can be.
static func shade(rgb: int, percent: int) -> int:
	var out := 0
	for shift in [16, 8, 0]:
		var channel: int = (rgb >> int(shift)) & 0xFF
		channel = clampi(channel + channel * percent / 100 + percent / 2, 20, 235)
		out |= channel << int(shift)
	return out

static func colour_to_ink(rgb: int) -> Color:
	return Color(float((rgb >> 16) & 0xFF) / 255.0, float((rgb >> 8) & 0xFF) / 255.0,
		float(rgb & 0xFF) / 255.0)

static func rgb_of(colour: Color) -> int:
	return (int(round(colour.r * 255.0)) << 16) | (int(round(colour.g * 255.0)) << 8) \
		| int(round(colour.b * 255.0))

# Hands every seat in a match its colour at once, so the room is worked out in one place
# and every device gets the same answer from the same seed.
static func assign_all(state: GameState, seed_value: int, regions: PackedByteArray) -> void:
	if state == null:
		return
	var taken := PackedInt32Array()
	for player in range(state.player_count()):
		var region := int(regions[player]) if player < regions.size() else NONE
		var colour := colour_for(region, seed_value, player, taken)
		taken.append(colour)
		state.set_identity(player, region, colour)
