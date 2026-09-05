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
var attack_mode := false
var cooldown_left := 0

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
			Ink.GRID_STRONG if strong else Ink.GRID, 2.6 if strong else 1.4)
	for y in range(h + 1):
		var strong := y % 5 == 0
		draw_line(Vector2(0, y * CELL), Vector2(w * CELL, y * CELL),
			Ink.GRID_STRONG if strong else Ink.GRID, 2.6 if strong else 1.4)

	var margin_x := 2 * CELL
	Ink.line(self, Vector2(margin_x, 0), Vector2(margin_x, h * CELL), Ink.MARGIN, 2.0)

	_draw_territory()
	_draw_buildings()
	_draw_ships()

	if attack_mode:
		_draw_attack_targets()

	if selected >= 0:
		Ink.rect(self, cell_rect(selected).grow(-3.0), Ink.INK, 3.0)

	for target in ship_targets:
		Ink.rect(self, cell_rect(target).grow(-8.0), Ink.pen_of(local_player), 3.0)

	if opponent_focus >= 0:
		_draw_focus_marker(opponent_focus)

	Ink.rect(self, full, Ink.INK, 4.0)

func _draw_territory() -> void:
	for i in range(state.owner_of.size()):
		var owner_id := int(state.owner_of[i])
		if owner_id == GameState.NEUTRAL:
			continue
		var pen := Ink.pen_of(owner_id)
		var tint := Color(pen.r, pen.g, pen.b, 0.15)
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
			Ink.line(self, r.position, r.position + Vector2(0, CELL), pen, 4.0)
		if x == state.width - 1 or state.owner_of[i + 1] != owner_id:
			Ink.line(self, r.position + Vector2(CELL, 0), r.position + Vector2(CELL, CELL), pen, 4.0)
		if y == 0 or state.owner_of[i - state.width] != owner_id:
			Ink.line(self, r.position, r.position + Vector2(CELL, 0), pen, 4.0)
		if y == state.height - 1 or state.owner_of[i + state.width] != owner_id:
			Ink.line(self, r.position + Vector2(0, CELL), r.position + Vector2(CELL, CELL), pen, 4.0)

func _draw_buildings() -> void:
	var idle := _idle_cells()
	for i in range(state.building_at.size()):
		var type := int(state.building_at[i])
		if type == Balance.Building.NONE:
			continue
		var pen := Ink.pen_of(int(state.owner_of[i]))
		var r := cell_rect(i)
		var stopped := idle.has(i)
		# A building with nobody in it is drawn faint: at a glance the working half of a
		# region is solid and the stalled half is washed out.
		var colour := Color(pen.r, pen.g, pen.b, 0.35) if stopped else pen
		Ink.draw_building(self, type, r.grow(-CELL * 0.18), colour, 3.0)
		Ink.draw_level_pips(self, r, int(state.level_at[i]), colour)
		if stopped:
			Ink.draw_idle_badge(self, r)

# Which buildings are standing idle, for every player on the board. The simulation
# decides; the map only asks, so what is greyed out and what actually earns can never
# disagree.
func _idle_cells() -> Dictionary:
	var found: Dictionary = {}
	for player in range(state.alive.size()):
		for cell in state.aggregate(player)["idle_cells"]:
			found[int(cell)] = true
	return found

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
		# The wake is the route still to sail, which now bends round headlands.
		var wake := PackedVector2Array([a])
		for i in range(step, path.size()):
			wake.append(cell_rect(path[i]).get_center())
		if wake.size() > 1:
			draw_polyline(wake, Color(pen.r, pen.g, pen.b, 0.3), 2.0)
		Ink.draw_ship(self, a.lerp(b, progress), CELL * 0.5, pen, 3.0)

# In attack mode every cell the player could take right now is ringed, so aiming is a
# matter of tapping a marked square rather than guessing what borders what. The ring
# fades while the capture is reloading, which is the cooldown made visible on the map.
func _draw_attack_targets() -> void:
	var pen := Ink.pen_of(local_player)
	var alpha := 0.25 if cooldown_left > 0 else 0.85
	for i in range(state.owner_of.size()):
		if not is_land(i) or int(state.owner_of[i]) == local_player:
			continue
		if not state.touches_player(i, local_player):
			continue
		var r := cell_rect(i).grow(-6.0)
		draw_rect(r, Color(pen.r, pen.g, pen.b, alpha * 0.16), true)
		Ink.rect(self, r, Color(pen.r, pen.g, pen.b, alpha), 3.0)

func is_land(cell: int) -> bool:
	return state.terrain[cell] == WorldGen.LAND

func _draw_focus_marker(cell: int) -> void:
	var pen := Ink.pen_of(1 - local_player)
	var r := cell_rect(cell)
	var centre := r.get_center()
	Ink.circle(self, centre, CELL * 0.55, Color(pen.r, pen.g, pen.b, 0.55), 3.0, 16)
	Ink.circle(self, centre, CELL * 0.25, Color(pen.r, pen.g, pen.b, 0.35), 2.0, 12)
