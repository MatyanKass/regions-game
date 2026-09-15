# Copyright (c) 2026 MatyanKass. All rights reserved.
# Who made the game. The line is drawn in the corner of every screen by AuthorMark, and
# its hash is folded into world generation and the state hash: a build with the name
# changed or taken out generates different maps from every genuine copy and cannot play
# a match against one.
class_name Authorship
extends RefCounted

const AUTHOR := "MatyanKass"

static var _salt := -1

# by MatyanKass
static func line() -> String:
	return "By: " + AUTHOR

# FNV-1a over the UTF-8 bytes of the line, 32 bits. Integer only, so it is the same on
# every device.
static func salt() -> int:
	if _salt < 0:
		var h := 0x811C9DC5
		for byte in line().to_utf8_buffer():
			h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
		_salt = h
	return _salt
