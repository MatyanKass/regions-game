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

# The window of cells the camera can actually see, with a one cell margin so nothing
# pops in at the edge. Everything drawn below walks this rather than the whole map: on a
# four hundred cell world the difference is between a hundred and sixty thousand cells a
# frame and about six hundred.
func visible_cells() -> Rect2i:
	if state == null:
		return Rect2i()
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var screen := get_viewport().get_visible_rect()
	var a := inverse * screen.position
	var b := inverse * (screen.position + screen.size)
	var x0 := clampi(int(floor(minf(a.x, b.x) / CELL)) - 1, 0, state.width - 1)
	var y0 := clampi(int(floor(minf(a.y, b.y) / CELL)) - 1, 0, state.height - 1)
	var x1 := clampi(int(ceil(maxf(a.x, b.x) / CELL)) + 1, 0, state.width - 1)
	var y1 := clampi(int(ceil(maxf(a.y, b.y) / CELL)) + 1, 0, state.height - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _draw() -> void:
	if state == null:
		return
	var view := visible_cells()
	if view.size.x <= 0 or view.size.y <= 0:
		return
	var full := Rect2(Vector2.ZERO, map_size())
	draw_rect(full, Ink.PAPER, true)

	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var i := state.index_of(x, y)
			if state.terrain[i] != WorldGen.LAND:
				draw_rect(cell_rect(i), Ink.SEA, true)

	# Squared paper: every line thin, every fifth one darker, like a real notebook. Only
	# the lines crossing the window are drawn.
	var top := view.position.y * CELL
	var bottom := view.end.y * CELL
	var left := view.position.x * CELL
	var right := view.end.x * CELL
	for x in range(view.position.x, view.end.x + 1):
		var strong := x % 5 == 0
		draw_line(Vector2(x * CELL, top), Vector2(x * CELL, bottom),
			Ink.GRID_STRONG if strong else Ink.GRID, 2.6 if strong else 1.4)
	for y in range(view.position.y, view.end.y + 1):
		var strong_row := y % 5 == 0
		draw_line(Vector2(left, y * CELL), Vector2(right, y * CELL),
			Ink.GRID_STRONG if strong_row else Ink.GRID, 2.6 if strong_row else 1.4)

	var margin_x := 2 * CELL
	if left <= margin_x and margin_x <= right:
		Ink.line(self, Vector2(margin_x, top), Vector2(margin_x, bottom), Ink.MARGIN, 2.0)

	_draw_territory(view)
	_draw_buildings(view)
	_draw_sites(view)
	_draw_ships()

	if attack_mode:
		_draw_attack_targets(view)

	if selected >= 0:
		Ink.rect(self, cell_rect(selected).grow(-3.0), Ink.INK, 3.0)

	for target in ship_targets:
		Ink.rect(self, cell_rect(target).grow(-8.0), Ink.pen_of(local_player), 3.0)

	if opponent_focus >= 0:
		_draw_focus_marker(opponent_focus)

	Ink.rect(self, full, Ink.INK, 4.0)

func _draw_territory(view: Rect2i) -> void:
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var i := state.index_of(x, y)
			var owner_id := int(state.owner_of[i])
			if owner_id == GameState.NEUTRAL:
				continue
			var pen := Ink.pen_of(owner_id)
			draw_rect(cell_rect(i), Color(pen.r, pen.g, pen.b, 0.15), true)

	# Borders are drawn per edge so a territory reads as one outlined shape, the way a
	# fleet is outlined in battleship.
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var i := state.index_of(x, y)
			var owner_id := int(state.owner_of[i])
			if owner_id == GameState.NEUTRAL:
				continue
			var pen := Ink.pen_of(owner_id)
			var r := cell_rect(i)
			if x == 0 or state.owner_of[i - 1] != owner_id:
				Ink.line(self, r.position, r.position + Vector2(0, CELL), pen, 4.0)
			if x == state.width - 1 or state.owner_of[i + 1] != owner_id:
				Ink.line(self, r.position + Vector2(CELL, 0), r.position + Vector2(CELL, CELL), pen, 4.0)
			if y == 0 or state.owner_of[i - state.width] != owner_id:
				Ink.line(self, r.position, r.position + Vector2(CELL, 0), pen, 4.0)
			if y == state.height - 1 or state.owner_of[i + state.width] != owner_id:
				Ink.line(self, r.position + Vector2(0, CELL), r.position + Vector2(CELL, CELL), pen, 4.0)

func _draw_buildings(view: Rect2i) -> void:
	var idle := _idle_cells()
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var i := state.index_of(x, y)
			var type := int(state.building_at[i])
			if type == Balance.Building.NONE:
				continue
			var pen := Ink.pen_of(int(state.owner_of[i]))
			var r := cell_rect(i)
			var stopped := idle.has(i)
			# A building with nobody in it is drawn faint: at a glance the working half
			# of a region is solid and the stalled half is washed out.
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

# Work in progress: the building it will be, sketched faintly, with a bar filling along
# the bottom of the cell. Drawn from the sites list, which is short, so the visible
# window is only used to skip what is off screen.
func _draw_sites(view: Rect2i) -> void:
	for site in state.sites:
		var cell := int(site["cell"])
		var x := cell % state.width
		var y := cell / state.width
		if x < view.position.x or x >= view.end.x or y < view.position.y or y >= view.end.y:
			continue
		var pen := Ink.pen_of(int(site["owner"]))
		var r := cell_rect(cell)
		Ink.draw_building(self, int(site["type"]), r.grow(-CELL * 0.22),
			Color(pen.r, pen.g, pen.b, 0.30), 2.0)
		var progress := float(state.site_progress(cell)) / 1000.0
		var bar := Rect2(r.position + Vector2(CELL * 0.12, CELL * 0.82),
			Vector2(CELL * 0.76, CELL * 0.08))
		draw_rect(bar, Color(pen.r, pen.g, pen.b, 0.18), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), pen, true)
		Ink.rect(self, bar, Color(pen.r, pen.g, pen.b, 0.55), 1.5)

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
		# The wake is the route still to sail, which bends round headlands.
		var wake := PackedVector2Array([a])
		for i in range(step, path.size()):
			wake.append(cell_rect(path[i]).get_center())
		if wake.size() > 1:
			draw_polyline(wake, Color(pen.r, pen.g, pen.b, 0.3), 2.0)
		Ink.draw_ship(self, a.lerp(b, progress), CELL * 0.5, pen, 3.0)

# In attack mode every cell the player could take right now is ringed, so aiming is a
# matter of tapping a marked square rather than guessing what borders what. The ring
# fades while the capture is reloading, which is the cooldown made visible on the map.
func _draw_attack_targets(view: Rect2i) -> void:
	var pen := Ink.pen_of(local_player)
	var alpha := 0.25 if cooldown_left > 0 else 0.85
	for y in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var i := state.index_of(x, y)
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
