# Copyright (c) 2026 MatyanKass. All rights reserved.
# The look of the game in one place: paper colours and the pen glyphs used for
# buildings. Everything is drawn with lines and arcs rather than sprites, which keeps
# the notebook style consistent and the repository free of binary art.
#
# Every stroke is drawn with a wobble, so a "straight" line is really four short segments
# that drift a fraction off true - the difference between a printed diagram and something
# biro'd into an exercise book. The wobble comes from a hash of the stroke's own
# position, so a shape shakes exactly the same way on every frame and on both phones: it
# looks hand drawn rather than animated.
#
# The printed squares of the paper are the one thing drawn dead straight. On a real
# notebook the grid is printed and only what the player adds is drawn by hand.
class_name Ink
extends RefCounted

const PAPER := Color("f4efe0")
const PAPER_DARK := Color("e6dfcb")
const GRID := Color("8aa8cd")
const GRID_STRONG := Color("7f9bc0")
const SEA := Color("bcd9ee")
const SEA_LINE := Color("8fb8d6")
const INK := Color("22304d")
const INK_SOFT := Color("5a6a86")
const NEUTRAL_FILL := Color(0, 0, 0, 0)
# The red rule down the left of a school exercise book.
const MARGIN := Color("d08a86")
# Warnings are a hotter red than either biro, so "this is broken" never reads as
# "this belongs to the red player".
const ALERT := Color("e0341c")

# Player pen colours: blue biro and red biro first, the two pens everyone had at school,
# then six more for a full room. These are the fallback - what a seat is drawn in when
# nobody picked a region for it. See Regions.
const PENS := [Color("1b4fa0"), Color("bd2f22"), Color("1f7a4d"), Color("c8961b"),
	Color("6b3fa0"), Color("0f7f8f"), Color("e2701e"), Color("55617a")]

# Panels are paper laid on paper rather than a dark HUD: the game is a notebook.
const PAPER_PANEL := Color("fbf7ea")
const PANEL := Color("2b3550")
const PANEL_LIGHT := Color("3d4a6b")
const PANEL_DARK := Color("1b2237")
const SLOT := Color("cfc6ad")
const SLOT_DARK := Color("a89c7e")
const DISABLED := Color(1, 1, 1, 0.35)

static func pen_of(player: int) -> Color:
	if player < 0:
		return INK_SOFT
	return PENS[player % PENS.size()]

# The pen a player is actually drawn in: the colour their region gave them, and the flat
# fallback above when there is no state to ask or nobody chose.
static func pen_for(state: GameState, player: int) -> Color:
	if player < 0:
		return INK_SOFT
	if state != null:
		var tint := state.tint_of(player)
		if tint != 0:
			return Regions.colour_to_ink(tint)
	return pen_of(player)

# --- Hand drawn strokes -----------------------------------------------------------

# Kept deliberately slight. The point is that the shapes look drawn rather than printed,
# not that they look shaky: at a glance a building has to be recognisable first and
# charming second, and a phone screen is small.
const SEGMENTS := 3
const WOBBLE := 0.016     # share of a stroke's length it may drift sideways
const WOBBLE_MAX := 1.0   # never more than this many pixels

# Repeatable noise in -1..1 from an integer. Deliberately not SimRng: this is decoration
# and must never be mistaken for something the simulation depends on.
static func noise_at(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7FFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(x % 2001) / 1000.0 - 1.0

# by MatyanKass
# A seed taken from where the stroke is, so the same shape in the same place always
# shakes the same way instead of shimmering every frame.
static func _seed_of(a: Vector2, b: Vector2) -> int:
	return int(a.x * 7.0) * 92837111 + int(a.y * 7.0) * 689287499 \
		+ int(b.x * 7.0) * 283923481 + int(b.y * 7.0)

static func line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, w: float) -> void:
	# A stroke with no length would become a polyline of identical points, which the
	# renderer cannot work out a direction for.
	if a.distance_squared_to(b) < 0.25:
		return
	ci.draw_polyline(_stroke(a, b), c, w)

# One pen stroke: the ends stay put so shapes still meet at their corners, and the middle
# is allowed to wander.
static func _stroke(a: Vector2, b: Vector2) -> PackedVector2Array:
	var delta := b - a
	var length := delta.length()
	if length < 0.001:
		return PackedVector2Array([a, b])
	var normal := Vector2(-delta.y, delta.x) / length
	var amount := minf(length * WOBBLE, WOBBLE_MAX)
	var seed_value := _seed_of(a, b)
	var points := PackedVector2Array()
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		# sin() pins both ends to zero drift and peaks in the middle of the stroke.
		var drift := noise_at(seed_value + i) * amount * sin(PI * t)
		points.append(a.lerp(b, t) + normal * drift)
	return points

static func poly(ci: CanvasItem, points: PackedVector2Array, c: Color, w: float,
		closed: bool) -> void:
	var count := points.size()
	if count < 2:
		return
	var last := count if closed else count - 1
	for i in range(last):
		line(ci, points[i], points[(i + 1) % count], c, w)

static func rect(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	poly(ci, PackedVector2Array([
		r.position,
		r.position + Vector2(r.size.x, 0),
		r.position + r.size,
		r.position + Vector2(0, r.size.y),
	]), c, w, true)

# A circle drawn as a ring of wobbly chords rather than a perfect arc.
static func circle(ci: CanvasItem, centre: Vector2, radius: float, c: Color, w: float,
		steps: int = 20) -> void:
	var points := PackedVector2Array()
	var seed_value := int(centre.x * 7.0) * 40503 + int(centre.y * 7.0) * 39119 + int(radius * 7.0)
	for i in range(steps):
		var angle := TAU * float(i) / float(steps)
		var wobble := 1.0 + noise_at(seed_value + i) * 0.02
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius * wobble)
	poly(ci, points, c, w, true)

# by MatyanKass
static func arc(ci: CanvasItem, centre: Vector2, radius: float, from_deg: float,
		to_deg: float, c: Color, w: float, steps: int = 10) -> void:
	var points := PackedVector2Array()
	var seed_value := int(centre.x * 7.0) * 15485863 + int(radius * 7.0)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := deg_to_rad(lerpf(from_deg, to_deg, t))
		var wobble := 1.0 + noise_at(seed_value + i) * 0.02
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius * wobble)
	poly(ci, points, c, w, false)

# --- Building glyphs -------------------------------------------------------------
# Each glyph draws inside `r` in `color`. They are schematic on purpose: this is what
# somebody doodles in a margin, not an illustration.

static func draw_building(ci: CanvasItem, type: int, r: Rect2, color: Color, width: float) -> void:
	match type:
		Balance.Building.FACTORY:
			_factory(ci, r, color, width)
		Balance.Building.HOUSE:
			_house(ci, r, color, width)
		Balance.Building.BANK:
			_bank(ci, r, color, width)
		Balance.Building.BARRACKS:
			_barracks(ci, r, color, width)
		Balance.Building.MILITARY_BASE:
			_base(ci, r, color, width)
		Balance.Building.PORT:
			_port(ci, r, color, width)
		Balance.Building.BARRIER:
			_barrier(ci, r, color, width)

# An L-shaped shed: a tall wing on the right, a low hall running off to the left, the
# inside scribbled in. Drawn from the reference sketch.
static func _factory(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	_scribble(ci, Rect2(x + sw * 0.10, y + sh * 0.54, sw * 0.80, sh * 0.30), c)
	_scribble(ci, Rect2(x + sw * 0.62, y + sh * 0.20, sw * 0.28, sh * 0.32), c)
	poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.08, y + sh * 0.52),
		Vector2(x + sw * 0.60, y + sh * 0.52),
		Vector2(x + sw * 0.60, y + sh * 0.18),
		Vector2(x + sw * 0.92, y + sh * 0.18),
		Vector2(x + sw * 0.92, y + sh * 0.86),
		Vector2(x + sw * 0.08, y + sh * 0.86),
	]), c, w, true)

# Loose diagonal shading, the way a shape gets filled in with a biro.
static func _scribble(ci: CanvasItem, area: Rect2, c: Color) -> void:
	var shade := Color(c.r, c.g, c.b, 0.32)
	var step := maxf(3.5, area.size.x * 0.15)
	var offset := step
	while offset < area.size.x + area.size.y:
		var from := Vector2(area.position.x + offset, area.end.y)
		var to := Vector2(area.position.x + offset - area.size.y, area.position.y)
		if from.x > area.end.x:
			from = Vector2(area.end.x, area.end.y - (from.x - area.end.x))
		if to.x < area.position.x:
			to = Vector2(area.position.x, area.position.y + (area.position.x - to.x))
		if from.distance_to(to) > 2.0:
			line(ci, from, to, shade, 1.6)
		offset += step

static func _house(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.12, y + sh * 0.92), Vector2(x + sw * 0.12, y + sh * 0.45),
		Vector2(x + sw * 0.5, y + sh * 0.1), Vector2(x + sw * 0.88, y + sh * 0.45),
		Vector2(x + sw * 0.88, y + sh * 0.92),
	]), c, w, true)
	rect(ci, Rect2(x + sw * 0.42, y + sh * 0.62, sw * 0.16, sh * 0.30), c, w)

static func _bank(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.06, y + sh * 0.42), Vector2(x + sw * 0.5, y + sh * 0.12),
		Vector2(x + sw * 0.94, y + sh * 0.42),
	]), c, w, false)
	line(ci, Vector2(x + sw * 0.06, y + sh * 0.42), Vector2(x + sw * 0.94, y + sh * 0.42), c, w)
	for i in range(3):
		var cx := x + sw * (0.24 + 0.26 * i)
		line(ci, Vector2(cx, y + sh * 0.46), Vector2(cx, y + sh * 0.84), c, w)
	line(ci, Vector2(x + sw * 0.06, y + sh * 0.9), Vector2(x + sw * 0.94, y + sh * 0.9), c, w)

static func _barracks(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	rect(ci, Rect2(x + sw * 0.1, y + sh * 0.45, sw * 0.8, sh * 0.5), c, w)
	line(ci, Vector2(x + sw * 0.3, y + sh * 0.45), Vector2(x + sw * 0.3, y + sh * 0.12), c, w)
	poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.3, y + sh * 0.12), Vector2(x + sw * 0.68, y + sh * 0.2),
		Vector2(x + sw * 0.3, y + sh * 0.3),
	]), c, w, true)

# A long hangar under a slanted awning, with two rows of shuttered bays. From the sketch.
static func _base(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.04, y + sh * 0.34),
		Vector2(x + sw * 0.94, y + sh * 0.10),
		Vector2(x + sw * 0.94, y + sh * 0.28),
		Vector2(x + sw * 0.12, y + sh * 0.34),
	]), c, w, true)
	poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.12, y + sh * 0.34),
		Vector2(x + sw * 0.86, y + sh * 0.34),
		Vector2(x + sw * 0.80, y + sh * 0.90),
		Vector2(x + sw * 0.16, y + sh * 0.90),
	]), c, w, true)
	for row in range(2):
		var ty := y + sh * (0.44 + 0.21 * row)
		for col in range(4):
			var tx := x + sw * (0.25 + 0.14 * col)
			line(ci, Vector2(tx, ty), Vector2(tx, ty + sh * 0.13), c, w * 0.85)
	line(ci, Vector2(x + sw * 0.08, y + sh * 0.90), Vector2(x + sw * 0.20, y + sh * 0.90), c, w)

static func _port(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	var cx := x + sw * 0.5
	line(ci, Vector2(cx, y + sh * 0.22), Vector2(cx, y + sh * 0.86), c, w)
	line(ci, Vector2(x + sw * 0.28, y + sh * 0.36), Vector2(x + sw * 0.72, y + sh * 0.36), c, w)
	circle(ci, Vector2(cx, y + sh * 0.2), sw * 0.12, c, w, 10)
	arc(ci, Vector2(cx, y + sh * 0.55), sw * 0.34, 20, 160, c, w, 8)

# by MatyanKass
# A hurdle fence: four upright posts with a panel hung between each pair, every panel at
# a slightly different height. Straight posts read far better at cell size than leaning
# ones did, and the staggered panels are what make it a fence and not a table.
static func _barrier(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	var columns := [0.14, 0.38, 0.62, 0.86]
	for column in columns:
		var cx: float = x + sw * float(column)
		line(ci, Vector2(cx, y + sh * 0.14), Vector2(cx, y + sh * 0.90), c, w)
	# Top and bottom rail of each panel, as a fraction of the height.
	var panels := [Vector2(0.32, 0.68), Vector2(0.22, 0.58), Vector2(0.36, 0.72)]
	for i in range(panels.size()):
		var panel: Vector2 = panels[i]
		var left: float = x + sw * float(columns[i])
		var right: float = x + sw * float(columns[i + 1])
		for edge in [panel.x, panel.y]:
			var ry: float = y + sh * float(edge)
			line(ci, Vector2(left, ry), Vector2(right, ry), c, w)

# --- Interface icons, drawn the same way, so nothing on screen looks imported -------

enum Icon { COIN, POWER, PEOPLE, BUILD, ATTACK, INFO, CLOCK, UPGRADE }

static func draw_icon(ci: CanvasItem, icon: int, r: Rect2, c: Color, w: float) -> void:
	var centre := r.position + r.size * 0.5
	var radius := minf(r.size.x, r.size.y) * 0.42
	match icon:
		Icon.COIN:
			circle(ci, centre, radius, c, w)
			circle(ci, centre, radius * 0.52, c, w, 10)
		Icon.POWER:
			poly(ci, PackedVector2Array([
				centre + Vector2(radius * 0.25, -radius),
				centre + Vector2(-radius * 0.55, radius * 0.12),
				centre + Vector2(-radius * 0.02, radius * 0.12),
				centre + Vector2(-radius * 0.3, radius),
				centre + Vector2(radius * 0.6, -radius * 0.15),
				centre + Vector2(radius * 0.05, -radius * 0.15),
			]), c, w, true)
		Icon.PEOPLE:
			circle(ci, centre + Vector2(0, -radius * 0.45), radius * 0.38, c, w, 9)
			arc(ci, centre + Vector2(0, radius * 1.15), radius * 0.85, 200, 340, c, w, 8)
		Icon.BUILD:
			# A trowel over a course of bricks: building, not fighting.
			poly(ci, PackedVector2Array([
				centre + Vector2(-radius * 0.9, radius * 0.1),
				centre + Vector2(0, -radius * 0.85),
				centre + Vector2(radius * 0.9, radius * 0.1),
			]), c, w, false)
			rect(ci, Rect2(centre + Vector2(-radius * 0.7, radius * 0.1),
				Vector2(radius * 1.4, radius * 0.8)), c, w)
		Icon.ATTACK:
			line(ci, centre + Vector2(-radius, radius), centre + Vector2(radius * 0.7, -radius), c, w)
			line(ci, centre + Vector2(radius, radius), centre + Vector2(-radius * 0.7, -radius), c, w)
			line(ci, centre + Vector2(-radius, radius * 0.45), centre + Vector2(-radius * 0.45, radius), c, w)
			line(ci, centre + Vector2(radius, radius * 0.45), centre + Vector2(radius * 0.45, radius), c, w)
		Icon.INFO:
			circle(ci, centre, radius, c, w)
			line(ci, centre + Vector2(0, -radius * 0.58), centre + Vector2(0, -radius * 0.42), c, w * 1.4)
			line(ci, centre + Vector2(0, -radius * 0.15), centre + Vector2(0, radius * 0.6), c, w)
		Icon.CLOCK:
			circle(ci, centre, radius, c, w)
			line(ci, centre, centre + Vector2(0, -radius * 0.65), c, w)
			line(ci, centre, centre + Vector2(radius * 0.45, 0), c, w)
		Icon.UPGRADE:
			poly(ci, PackedVector2Array([
				centre + Vector2(0, -radius),
				centre + Vector2(radius * 0.8, -radius * 0.1),
				centre + Vector2(radius * 0.3, -radius * 0.1),
				centre + Vector2(radius * 0.3, radius * 0.9),
				centre + Vector2(-radius * 0.3, radius * 0.9),
				centre + Vector2(-radius * 0.3, -radius * 0.1),
				centre + Vector2(-radius * 0.8, -radius * 0.1),
			]), c, w, true)

# Level pips: a building at level three carries three ticks in its corner, which reads
# faster on a small screen than a number would.
static func draw_level_pips(ci: CanvasItem, r: Rect2, level: int, c: Color) -> void:
	if level <= 1:
		return
	var size := r.size.x * 0.09
	var gap := size * 1.7
	var start := r.position + Vector2(r.size.x - size - gap * (level - 1), size * 1.4)
	for i in range(level):
		ci.draw_circle(start + Vector2(gap * i, 0), size * 0.48, c)

# A crossed-out circle in the corner of a building that has nobody to work it. Drawn
# in the alert red rather than in a player colour, and paired with the building being
# greyed out, so it reads the same for either side.
static func draw_idle_badge(ci: CanvasItem, r: Rect2) -> void:
	var radius := r.size.x * 0.17
	var centre := r.position + Vector2(radius * 1.25, radius * 1.25)
	var width := maxf(1.6, radius * 0.28)
	ci.draw_circle(centre, radius, Color(PAPER.r, PAPER.g, PAPER.b, 0.85))
	circle(ci, centre, radius, ALERT, width, 12)
	var reach := radius * 0.62
	line(ci, centre + Vector2(-reach, -reach), centre + Vector2(reach, reach), ALERT, width)

static func draw_ship(ci: CanvasItem, centre: Vector2, size: float, c: Color, w: float) -> void:
	var half := size * 0.5
	poly(ci, PackedVector2Array([
		Vector2(centre.x - half, centre.y + half * 0.2),
		Vector2(centre.x + half, centre.y + half * 0.2),
		Vector2(centre.x + half * 0.6, centre.y + half * 0.75),
		Vector2(centre.x - half * 0.6, centre.y + half * 0.75),
	]), c, w, true)
	line(ci, Vector2(centre.x, centre.y + half * 0.2), Vector2(centre.x, centre.y - half * 0.8), c, w)
	poly(ci, PackedVector2Array([
		Vector2(centre.x + w, centre.y - half * 0.8),
		Vector2(centre.x + half * 0.7, centre.y - half * 0.2),
		Vector2(centre.x + w, centre.y - half * 0.2),
	]), c, w, true)
