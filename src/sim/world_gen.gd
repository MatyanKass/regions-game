# Deterministic map generation. Same seed on both devices == same map, byte for byte.
class_name WorldGen
extends RefCounted

const LAND := 0
const SEA := 1

# Returns { "terrain": PackedByteArray, "starts": PackedInt32Array, "sea_percent": int }
static func generate(seed_value: int, player_count: int = 2) -> Dictionary:
	var w := Balance.MAP_WIDTH
	var h := Balance.MAP_HEIGHT
	var total := w * h
	var rng := SimRng.new(seed_value)

	var span := Balance.SEA_PERCENT_MAX - Balance.SEA_PERCENT_MIN + 1
	var sea_percent := Balance.SEA_PERCENT_MIN + rng.next_range(span)
	var sea_target := total * sea_percent / 100

	var terrain := PackedByteArray()
	terrain.resize(total)
	terrain.fill(LAND)

	# Grow a handful of sea blobs cell by cell. Blob growth (rather than noise plus a
	# threshold) is what guarantees we hit the requested percentage exactly.
	var frontier: Array[int] = []
	var placed := 0
	var blobs := 2 + rng.next_range(3)
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
		for n in _neighbours(cell):
			if terrain[n] == LAND:
				free.append(n)
		if free.is_empty():
			frontier.remove_at(pick)
			continue
		var target: int = free[rng.next_range(free.size())]
		terrain[target] = SEA
		placed += 1
		frontier.append(target)

	var starts := _pick_starts(terrain, rng, player_count)
	return {"terrain": terrain, "starts": starts, "sea_percent": placed * 100 / total}

# Starting cells are mirrored around the map centre so neither player gets a better
# spot; the axis is rolled from the seed purely for variety.
static func _pick_starts(terrain: PackedByteArray, rng: SimRng, player_count: int) -> PackedInt32Array:
	var w := Balance.MAP_WIDTH
	var h := Balance.MAP_HEIGHT
	var cx := w / 2
	var cy := h / 2
	var half := Balance.START_DISTANCE / 2
	var diag := Balance.START_DISTANCE * 3 / 8

	var offsets: Array[Vector2i] = []
	match rng.next_range(4):
		0: offsets = [Vector2i(-half, 0), Vector2i(half, 0)]
		1: offsets = [Vector2i(0, -half), Vector2i(0, half)]
		2: offsets = [Vector2i(-diag, -diag), Vector2i(diag, diag)]
		_: offsets = [Vector2i(-diag, diag), Vector2i(diag, -diag)]

	var starts := PackedInt32Array()
	for i in range(player_count):
		var o: Vector2i = offsets[i % offsets.size()]
		var ideal := clampi(cx + o.x, 0, w - 1) + clampi(cy + o.y, 0, h - 1) * w
		starts.append(_nearest_free_land(terrain, ideal, starts))
	return starts

# Spiral outwards from the ideal spot until we land on a free land cell. Scanning by
# growing radius keeps the result stable regardless of how the sea came out.
static func _nearest_free_land(terrain: PackedByteArray, ideal: int, taken: PackedInt32Array) -> int:
	var w := Balance.MAP_WIDTH
	var h := Balance.MAP_HEIGHT
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

static func _neighbours(cell: int) -> Array[int]:
	var w := Balance.MAP_WIDTH
	var h := Balance.MAP_HEIGHT
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
