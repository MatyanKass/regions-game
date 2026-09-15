# Copyright (c) 2026 MatyanKass. All rights reserved.
# The app icon, drawn rather than painted: a moment from a match on four by four cells.
#
# Two states meet down the middle. The blue one has thrown a barrier onto the front line
# and the red one has a military base behind its own, and red has already bitten a cell
# out of the top of blue's column - so the picture says "two countries, mid fight" rather
# than "a grid".
#
# It uses the same Ink strokes as the game, so the icon cannot drift away from how the
# game actually looks: change a glyph and the icon changes with it.
class_name IconArt
extends Control

const GRID_CELLS := 4
const BLUE := 0
const RED := 1

# Who owns what, row by row, and what stands on it. Red's cell at the top of column 1 is
# the bite it has taken out of blue.
const OWNERS := [
	[BLUE, RED, RED, RED],
	[BLUE, BLUE, RED, RED],
	[BLUE, BLUE, RED, RED],
	[BLUE, BLUE, RED, RED],
]

# Only two buildings are shown. At the size a launcher draws this, a third would be mush.
const BUILDINGS := {
	Vector2i(1, 2): Balance.Building.BARRIER,
	Vector2i(2, 1): Balance.Building.MILITARY_BASE,
}

# Set for the adaptive Android foreground, which is drawn over its own background layer.
var transparent := false
# The launcher crops adaptive icons hard, so the art shrinks into the middle for those.
var inset := 0.06

# by MatyanKass
func _draw() -> void:
	var side := minf(size.x, size.y)
	var pad := side * inset
	var board := Rect2(Vector2(pad, pad) + (size - Vector2(side, side)) * 0.5,
		Vector2(side - pad * 2.0, side - pad * 2.0))
	var cell := board.size.x / float(GRID_CELLS)
	var pen_width := maxf(2.0, cell * 0.055)

	if not transparent:
		draw_rect(Rect2(Vector2.ZERO, size), Ink.PAPER, true)

	# Territory tint first, so the pen work sits on top of it.
	for y in range(GRID_CELLS):
		for x in range(GRID_CELLS):
			var pen := Ink.pen_of(int(OWNERS[y][x]))
			draw_rect(_cell_rect(board, cell, x, y), Color(pen.r, pen.g, pen.b, 0.17), true)

	# The printed squares of the paper: straight, because a notebook grid is printed.
	for i in range(GRID_CELLS + 1):
		var offset := cell * i
		draw_line(board.position + Vector2(offset, 0),
			board.position + Vector2(offset, board.size.y), Ink.GRID, pen_width * 0.55)
		draw_line(board.position + Vector2(0, offset),
			board.position + Vector2(board.size.x, offset), Ink.GRID, pen_width * 0.55)

	_draw_borders(board, cell, pen_width)

	for coord in BUILDINGS:
		var c: Vector2i = coord
		var owner_id := int(OWNERS[c.y][c.x])
		var r := _cell_rect(board, cell, c.x, c.y).grow(-cell * 0.09)
		Ink.draw_building(self, int(BUILDINGS[coord]), r, Ink.pen_of(owner_id), pen_width * 1.15)

	Ink.rect(self, board, Ink.INK, pen_width * 1.1)

func _cell_rect(board: Rect2, cell: float, x: int, y: int) -> Rect2:
	return Rect2(board.position + Vector2(x, y) * cell, Vector2(cell, cell))

# Each territory is outlined as one shape, the way a fleet is ringed in battleship. The
# line down the middle therefore gets drawn twice, once in each pen, which is exactly
# what a contested border should look like.
func _draw_borders(board: Rect2, cell: float, pen_width: float) -> void:
	for y in range(GRID_CELLS):
		for x in range(GRID_CELLS):
			var owner_id := int(OWNERS[y][x])
			var pen := Ink.pen_of(owner_id)
			var r := _cell_rect(board, cell, x, y)
			if x == 0 or int(OWNERS[y][x - 1]) != owner_id:
				Ink.line(self, r.position, r.position + Vector2(0, cell), pen, pen_width * 1.6)
			if x == GRID_CELLS - 1 or int(OWNERS[y][x + 1]) != owner_id:
				Ink.line(self, r.position + Vector2(cell, 0), r.position + Vector2(cell, cell),
					pen, pen_width * 1.6)
			if y == 0 or int(OWNERS[y - 1][x]) != owner_id:
				Ink.line(self, r.position, r.position + Vector2(cell, 0), pen, pen_width * 1.6)
			if y == GRID_CELLS - 1 or int(OWNERS[y + 1][x]) != owner_id:
				Ink.line(self, r.position + Vector2(0, cell), r.position + Vector2(cell, cell),
					pen, pen_width * 1.6)
