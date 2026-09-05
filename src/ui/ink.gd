# The look of the game in one place: paper colours and the pen glyphs used for
# buildings. Everything is drawn with lines and arcs rather than sprites, which keeps
# the notebook style consistent and the repository free of binary art.
class_name Ink
extends RefCounted

const PAPER := Color("f4efe0")
const PAPER_DARK := Color("e6dfcb")
const GRID := Color("9db6d6")
const GRID_STRONG := Color("7f9bc0")
const SEA := Color("bcd9ee")
const SEA_LINE := Color("8fb8d6")
const INK := Color("22304d")
const INK_SOFT := Color("5a6a86")
const NEUTRAL_FILL := Color(0, 0, 0, 0)

# Player pen colours: blue biro and red biro, the two pens everyone had at school.
const PENS := [Color("1b4fa0"), Color("bd2f22")]

const PANEL := Color("2b3550")
const PANEL_LIGHT := Color("3d4a6b")
const PANEL_DARK := Color("1b2237")
const SLOT := Color("cfc6ad")
const SLOT_DARK := Color("a89c7e")
const DISABLED := Color(1, 1, 1, 0.35)

static func pen_of(player: int) -> Color:
	if player < 0 or player >= PENS.size():
		return INK_SOFT
	return PENS[player]

# --- Building glyphs -------------------------------------------------------------
# Each glyph draws inside `rect` in `color`. They are deliberately schematic: a house
# is a box with a roof, a factory is a shed with a chimney, and so on.

static func draw_building(ci: CanvasItem, type: int, rect: Rect2, color: Color, width: float) -> void:
	match type:
		Balance.Building.FACTORY:
			_factory(ci, rect, color, width)
		Balance.Building.HOUSE:
			_house(ci, rect, color, width)
		Balance.Building.BANK:
			_bank(ci, rect, color, width)
		Balance.Building.BARRACKS:
			_barracks(ci, rect, color, width)
		Balance.Building.MILITARY_BASE:
			_base(ci, rect, color, width)
		Balance.Building.PORT:
			_port(ci, rect, color, width)

static func _poly(ci: CanvasItem, points: PackedVector2Array, color: Color, width: float, closed: bool) -> void:
	if closed:
		var p := PackedVector2Array(points)
		p.append(points[0])
		ci.draw_polyline(p, color, width)
	else:
		ci.draw_polyline(points, color, width)

static func _factory(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	_poly(ci, PackedVector2Array([
		Vector2(x, y + sh), Vector2(x, y + sh * 0.55),
		Vector2(x + sw * 0.32, y + sh * 0.78), Vector2(x + sw * 0.32, y + sh * 0.55),
		Vector2(x + sw * 0.64, y + sh * 0.78), Vector2(x + sw * 0.64, y + sh * 0.35),
		Vector2(x + sw, y + sh * 0.35), Vector2(x + sw, y + sh),
	]), c, w, true)
	ci.draw_line(Vector2(x + sw * 0.78, y + sh * 0.35), Vector2(x + sw * 0.78, y), c, w)
	ci.draw_line(Vector2(x + sw * 0.78, y), Vector2(x + sw * 0.96, y), c, w)

static func _house(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	_poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.12, y + sh), Vector2(x + sw * 0.12, y + sh * 0.45),
		Vector2(x + sw * 0.5, y + sh * 0.1), Vector2(x + sw * 0.88, y + sh * 0.45),
		Vector2(x + sw * 0.88, y + sh),
	]), c, w, true)
	ci.draw_rect(Rect2(x + sw * 0.42, y + sh * 0.62, sw * 0.16, sh * 0.38), c, false, w)

static func _bank(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	_poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.06, y + sh * 0.42), Vector2(x + sw * 0.5, y + sh * 0.12),
		Vector2(x + sw * 0.94, y + sh * 0.42),
	]), c, w, false)
	ci.draw_line(Vector2(x + sw * 0.06, y + sh * 0.42), Vector2(x + sw * 0.94, y + sh * 0.42), c, w)
	for i in range(3):
		var cx := x + sw * (0.24 + 0.26 * i)
		ci.draw_line(Vector2(cx, y + sh * 0.46), Vector2(cx, y + sh * 0.84), c, w)
	ci.draw_line(Vector2(x + sw * 0.06, y + sh * 0.9), Vector2(x + sw * 0.94, y + sh * 0.9), c, w)

static func _barracks(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	ci.draw_rect(Rect2(x + sw * 0.1, y + sh * 0.45, sw * 0.8, sh * 0.5), c, false, w)
	ci.draw_line(Vector2(x + sw * 0.1, y + sh * 0.45), Vector2(x + sw * 0.9, y + sh * 0.45), c, w)
	ci.draw_line(Vector2(x + sw * 0.3, y + sh * 0.45), Vector2(x + sw * 0.3, y + sh * 0.12), c, w)
	_poly(ci, PackedVector2Array([
		Vector2(x + sw * 0.3, y + sh * 0.12), Vector2(x + sw * 0.68, y + sh * 0.2),
		Vector2(x + sw * 0.3, y + sh * 0.3),
	]), c, w, true)

static func _base(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var centre := r.position + r.size * 0.5
	var radius := minf(r.size.x, r.size.y) * 0.44
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI / 2.0 + PI * i / 5.0
		var rad := radius if i % 2 == 0 else radius * 0.45
		points.append(centre + Vector2(cos(angle), sin(angle)) * rad)
	_poly(ci, points, c, w, true)

static func _port(ci: CanvasItem, r: Rect2, c: Color, w: float) -> void:
	var x := r.position.x
	var y := r.position.y
	var sw := r.size.x
	var sh := r.size.y
	var cx := x + sw * 0.5
	ci.draw_line(Vector2(cx, y + sh * 0.22), Vector2(cx, y + sh * 0.86), c, w)
	ci.draw_line(Vector2(x + sw * 0.28, y + sh * 0.36), Vector2(x + sw * 0.72, y + sh * 0.36), c, w)
	ci.draw_arc(Vector2(cx, y + sh * 0.2), sw * 0.12, 0, TAU, 16, c, w)
	ci.draw_arc(Vector2(cx, y + sh * 0.55), sw * 0.34, deg_to_rad(20), deg_to_rad(160), 20, c, w)

static func draw_ship(ci: CanvasItem, centre: Vector2, size: float, c: Color, w: float) -> void:
	var half := size * 0.5
	_poly(ci, PackedVector2Array([
		Vector2(centre.x - half, centre.y + half * 0.2),
		Vector2(centre.x + half, centre.y + half * 0.2),
		Vector2(centre.x + half * 0.6, centre.y + half * 0.75),
		Vector2(centre.x - half * 0.6, centre.y + half * 0.75),
	]), c, w, true)
	ci.draw_line(Vector2(centre.x, centre.y + half * 0.2), Vector2(centre.x, centre.y - half * 0.8), c, w)
	_poly(ci, PackedVector2Array([
		Vector2(centre.x + w, centre.y - half * 0.8),
		Vector2(centre.x + half * 0.7, centre.y - half * 0.2),
		Vector2(centre.x + w, centre.y - half * 0.2),
	]), c, w, true)
