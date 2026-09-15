# Copyright (c) 2026 MatyanKass. All rights reserved.
# Worlds are pinned: one seed and one size must come out as the exact same map in every
# build, or two copies of the game can no longer play each other.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

const PINNED_SEED := 20260905
const PINNED_TERRAIN := 947389921

static func terrain_hash(seed_value: int, size: int) -> int:
	var world := WorldGen.generate(seed_value, WorldSettings.of_size(size))
	var h := 0x811C9DC5
	for byte in world["terrain"]:
		h = ((h ^ int(byte)) * 0x01000193) & 0xFFFFFFFF
	for start in world["starts"]:
		h = ((h ^ (int(start) & 0xFFFF)) * 0x01000193) & 0xFFFFFFFF
	return h

func test_a_pinned_seed_still_makes_the_same_world() -> void:
	var h := terrain_hash(PINNED_SEED, 40)
	expect(h == PINNED_TERRAIN, "seed %d made a different world: %d" % [PINNED_SEED, h])

# by MatyanKass
func test_the_author_line_is_there() -> void:
	expect(Authorship.line().ends_with(Authorship.AUTHOR), "the author line lost its name")
	expect(Authorship.salt() != 0, "the author line hashes to nothing")
