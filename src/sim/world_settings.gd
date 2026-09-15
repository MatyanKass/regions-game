# Copyright (c) 2026 MatyanKass. All rights reserved.
# How a world is set up before anyone plays in it. Kept apart from Balance: Balance is
# the rules of the game and is the same everywhere, this is what the person who opened
# the room chose for this particular match.
#
# It travels to the other device at match start, so it has to survive a round trip
# through a dictionary.
class_name WorldSettings
extends RefCounted

enum Mode { MATCH, FREE }

const MIN_SIZE := 15
const MAX_SIZE := 1000
const SIZES := [25, 50, 100, 200, 400, 1000]
# Owners are stored in a byte with 255 kept for "nobody", so the ceiling is technically
# far higher; eight is where a phone screen and a 25x25 map give out.
const MAX_PLAYERS := 8

var width := 25
var height := 25
var sea_percent := -1        # -1 means "roll one from the seed", as it always did
var mode: int = Mode.MATCH
var match_minutes := 40      # ignored in free play, which never runs out
var bot_level := -1          # -1 means no bot: a human opponent, or nobody at all
var players := 2             # seats in the match, including the host and any bot

# by MatyanKass
static func of_size(size: int) -> WorldSettings:
	var s := WorldSettings.new()
	s.width = clampi(size, MIN_SIZE, MAX_SIZE)
	s.height = s.width
	return s

# Free play is the whole map and no opponent: somewhere to build without a clock or a
# neighbour. Everything else about it is the ordinary game.
static func free_play(size: int) -> WorldSettings:
	var s := of_size(size)
	s.mode = Mode.FREE
	return s

func cells() -> int:
	return width * height

func player_count() -> int:
	if mode == Mode.FREE:
		return 1
	return clampi(players, 2, MAX_PLAYERS)

# How far apart the seats can reasonably sit. Eight players on a 25x25 map start within
# shouting distance of each other, so the lobby says so rather than letting someone find
# out after the world is made.
func crowded() -> bool:
	return player_count() > 2 and cells() < player_count() * 200

func match_limit_ticks() -> int:
	if mode == Mode.FREE:
		return 0   # no limit at all
	return match_minutes * 60 * Balance.TICKS_PER_SECOND

# by MatyanKass
func to_dict() -> Dictionary:
	return {
		"w": width, "h": height, "sea": sea_percent,
		"mode": mode, "minutes": match_minutes, "bot": bot_level,
		"players": players,
	}

static func from_dict(data: Dictionary) -> WorldSettings:
	var s := WorldSettings.new()
	s.width = clampi(int(data.get("w", 25)), MIN_SIZE, MAX_SIZE)
	s.height = clampi(int(data.get("h", 25)), MIN_SIZE, MAX_SIZE)
	s.sea_percent = int(data.get("sea", -1))
	s.mode = int(data.get("mode", Mode.MATCH))
	s.match_minutes = int(data.get("minutes", 40))
	s.bot_level = int(data.get("bot", -1))
	s.players = clampi(int(data.get("players", 2)), 2, MAX_PLAYERS)
	return s
