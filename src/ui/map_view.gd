# Draws the world. Read-only: it never touches the simulation, it only renders whatever
# state it is handed, which keeps rendering incapable of causing a desync.
class_name MapView
extends Node2D

const CELL := 64.0

var state: GameState = null
var local_player := 0
var selected := -1
var ship_targets := PackedInt32Array()
var opponent_focus := -1

func map_size() -> Vector2:
	if state == null:
		return Vector2.ZERO
	return Vector2(state.width, state.height) * CELL

func cell_rect(cell: int) -> Rect2:
	return Rect2(Vector2(cell % state.width, cell / state.width) * CELL, Vector2(CELL, CELL))

func cell_at(world: Vector2) -> int:
	if state == null:
		return -1
	var x := int(floor(world.x / CELL))
	var y := int(floor(world.y / CELL))
	if not state.in_bounds(x, y):
		return -1
	return state.index_of(x, y)

func _draw() -> void:
	if state == null:
		return
	var w := state.width
	var h := state.height
	var full := Rect2(Vector2.ZERO, map_size())
	draw_rect(full, Ink.PAPER, true)

	for i in range(state.owner_of.size()):
		if state.terrain[i] != WorldGen.LAND:
			draw_rect(cell_rect(i), Ink.SEA, true)

	# Squared paper: every line thin, every fifth one darker, like a real notebook.
	for x in range(w + 1):
		var strong := x % 5 == 0
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, h * CELL),
			Ink.GRID_STRONG if strong else Ink.GRID, 2.0 if strong else 1.0)
	for y in range(h + 1):
		var strong := y % 5 == 0
		draw_line(Vector2(0, y * CELL), Vector2(w * CELL, y * CELL),
			Ink.GRID_STRONG if strong else Ink.GRID, 2.0 if strong else 1.0)

	_draw_territory()
	_draw_buildings()
	_draw_ships()

	if selected >= 0:
		var r := cell_rect(selected).grow(-3.0)
		draw_rect(r, Ink.INK, false, 3.0)

	for target in ship_targets:
		draw_rect(cell_rect(target).grow(-8.0), Ink.pen_of(local_player), false, 3.0)

	if opponent_focus >= 0:
		_draw_focus_marker(opponent_focus)

	draw_rect(full, Ink.INK, false, 4.0)

func _draw_territory() -> void:
	for i in range(state.owner_of.size()):
		var owner_id := int(state.owner_of[i])
		if owner_id == GameState.NEUTRAL:
			continue
		var pen := Ink.pen_of(owner_id)
		var tint := Color(pen.r, pen.g, pen.b, 0.22)
		draw_rect(cell_rect(i), tint, true)

	# Borders are drawn per edge so a territory reads as one outlined shape, the way a
	# fleet is outlined in battleship.
	for i in range(state.owner_of.size()):
		var owner_id := int(state.owner_of[i])
		if owner_id == GameState.NEUTRAL:
			continue
		var pen := Ink.pen_of(owner_id)
		var r := cell_rect(i)
		var x := i % state.width
		var y := i / state.width
		if x == 0 or state.owner_of[i - 1] != owner_id:
			draw_line(r.position, r.position + Vector2(0, CELL), pen, 4.0)
		if x == state.width - 1 or state.owner_of[i + 1] != owner_id:
			draw_line(r.position + Vector2(CELL, 0), r.position + Vector2(CELL, CELL), pen, 4.0)
		if y == 0 or state.owner_of[i - state.width] != owner_id:
			draw_line(r.position, r.position + Vector2(CELL, 0), pen, 4.0)
		if y == state.height - 1 or state.owner_of[i + state.width] != owner_id:
			draw_line(r.position + Vector2(0, CELL), r.position + Vector2(CELL, CELL), pen, 4.0)

func _draw_buildings() -> void:
	for i in range(state.building_at.size()):
		var type := int(state.building_at[i])
		if type == Balance.Building.NONE:
			continue
		var pen := Ink.pen_of(int(state.owner_of[i]))
		Ink.draw_building(self, type, cell_rect(i).grow(-CELL * 0.18), pen, 3.0)

func _draw_ships() -> void:
	for ship in state.ships:
		var path: PackedInt32Array = ship["path"]
		var step := int(ship["step"])
		if step >= path.size():
			continue
		var from_cell := int(ship["port"]) if step == 0 else path[step - 1]
		var to_cell := path[step]
		var progress := float(ship["ticks"]) / float(Balance.SHIP_TICKS_PER_CELL)
		var a := cell_rect(from_cell).get_center()
		var b := cell_rect(to_cell).get_center()
		var pen := Ink.pen_of(int(ship["owner"]))
		draw_line(a, cell_rect(int(ship["target"])).get_center(), Color(pen.r, pen.g, pen.b, 0.3), 2.0)
		Ink.draw_ship(self, a.lerp(b, progress), CELL * 0.5, pen, 3.0)

func _draw_focus_marker(cell: int) -> void:
	var pen := Ink.pen_of(1 - local_player)
	var r := cell_rect(cell)
	var centre := r.get_center()
	draw_arc(centre, CELL * 0.55, 0, TAU, 28, Color(pen.r, pen.g, pen.b, 0.55), 3.0)
	draw_arc(centre, CELL * 0.25, 0, TAU, 20, Color(pen.r, pen.g, pen.b, 0.35), 2.0)
