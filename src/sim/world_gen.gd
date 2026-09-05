# Deterministic map generation. Same seed and the same settings on both devices produce
# the same map, byte for byte.
class_name WorldGen
extends RefCounted

const LAND := 0
const SEA := 1

# Two starts are placed this far apart on a small map. On a bigger one they scale with
# it, so a large world is not two players sitting in each other's laps with an ocean of
# unused space around them.
const START_DISTANCE := 16
const START_DISTANCE_SHARE := 40   # per cent of the shorter side, when that is larger

# Returns { "terrain": PackedByteArray, "starts": PackedInt32Array, "sea_percent": int }
static func generate(seed_value: int, settings: WorldSettings) -> Dictionary:
	var w := settings.width
	var h := settings.height
	var total := w * h
	var rng := SimRng.new(seed_value)

	var sea_percent := settings.sea_percent
	if sea_percent < 0:
		var span := Balance.SEA_PERCENT_MAX - Balance.SEA_PERCENT_MIN + 1
		sea_percent = Balance.SEA_PERCENT_MIN + rng.next_range(span)
	var sea_target := total * sea_percent / 100

	var terrain := PackedByteArray()
	terrain.resize(total)
	terrain.fill(LAND)

	# Grow sea blobs cell by cell. Blob growth, rather than noise plus a threshold, is
	# what guarantees the requested percentage exactly. The number of blobs scales with
	# the map: a handful of them stretched over a thousand cells would be one continent
	# and one ocean rather than a coastline.
	var frontier: Array[int] = []
	var placed := 0
	var blobs := 2 + rng.next_range(3) + total / 800
	for i in range(blobs):
		var c := rng.next_range(total)
		if terrain[c] == LAND:
			terrain[c] = SEA
			placed += 1
			frontier.append(c)

	while placed < sea_target:
		if frontier.is_empty():
			# All blobs are boxed in: start a new one on any remaining land cell.
			var c := _find_land(terrain, rng.next_range(total))
			if c < 0:
				break
			terrain[c] = SEA
			placed += 1
			frontier.append(c)
			continue
		var pick := rng.next_range(frontier.size())
		var cell: int = frontier[pick]
		var free: Array[int] = []
		for n in neighbours(cell, w, h):
			if terrain[n] == LAND:
				free.append(n)
		if free.is_empty():
			frontier.remove_at(pick)
			continue
		var target: int = free[rng.next_range(free.size())]
		terrain[target] = SEA
		placed += 1
		frontier.append(target)

	var starts := _pick_starts(terrain, rng, settings)
	return {"terrain": terrain, "starts": starts, "width": w, "height": h,
		"sea_percent": placed * 100 / total}

static func start_distance(settings: WorldSettings) -> int:
	var shorter := mini(settings.width, settings.height)
	return maxi(START_DISTANCE, shorter * START_DISTANCE_SHARE / 100)

# Starting cells are mirrored around the map centre so neither player gets a better
# spot; the axis is rolled from the seed purely for variety. In free play there is only
# one of them, and it goes in the middle so the whole world is within reach.
static func _pick_starts(terrain: PackedByteArray, rng: SimRng,
		settings: WorldSettings) -> PackedInt32Array:
	var w := settings.width
	var h := settings.height
	var cx := w / 2
	var cy := h / 2
	var count := settings.player_count()
	var starts := PackedInt32Array()
	if count == 1:
		starts.append(_nearest_free_land(terrain, cx + cy * w, starts, w, h))
		return starts

	var half := start_distance(settings) / 2
	var diag := start_distance(settings) * 3 / 8
	var offsets: Array[Vector2i] = []
	match rng.next_range(4):
		0: offsets = [Vector2i(-half, 0), Vector2i(half, 0)]
		1: offsets = [Vector2i(0, -half), Vector2i(0, half)]
		2: offsets = [Vector2i(-diag, -diag), Vector2i(diag, diag)]
		_: offsets = [Vector2i(-diag, diag), Vector2i(diag, -diag)]

	for i in range(count):
		var o: Vector2i = offsets[i % offsets.size()]
		var ideal := clampi(cx + o.x, 0, w - 1) + clampi(cy + o.y, 0, h - 1) * w
		starts.append(_nearest_free_land(terrain, ideal, starts, w, h))
	return starts

# Spiral outwards from the ideal spot until we land on a free land cell. Scanning by
# growing radius keeps the result stable regardless of how the sea came out.
static func _nearest_free_land(terrain: PackedByteArray, ideal: int,
		taken: PackedInt32Array, w: int, h: int) -> int:
	var ix := ideal % w
	var iy := ideal / w
	for radius in range(0, maxi(w, h)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var x := ix + dx
				var y := iy + dy
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var c := x + y * w
				if terrain[c] != LAND or taken.has(c):
					continue
				return c
	return -1

static func _find_land(terrain: PackedByteArray, from: int) -> int:
	var total := terrain.size()
	for i in range(total):
		var c := (from + i) % total
		if terrain[c] == LAND:
			return c
	return -1

static func neighbours(cell: int, w: int, h: int) -> Array[int]:
	var x := cell % w
	var y := cell / w
	var out: Array[int] = []
	if x > 0:
		out.append(cell - 1)
	if x < w - 1:
		out.append(cell + 1)
	if y > 0:
		out.append(cell - w)
	if y < h - 1:
		out.append(cell + w)
	return out
