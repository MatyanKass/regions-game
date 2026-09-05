# The match: map, camera, HUD and every panel the player can open.
#
# Nothing here mutates the simulation. Taps turn into requests to Net, and the screen
# redraws from whatever state the shared tick loop produced.
class_name MatchScreen
extends Node2D

signal exit_requested

const ZOOM_MIN := 0.30
const ZOOM_MAX := 2.20
const TAP_SLOP := 18.0
const TAP_MS := 400
const DOUBLE_TAP_MS := 450

enum Tool { NONE, SHIP_TARGET }

var map_view: MapView
var camera: Camera2D

var _hud: CanvasLayer
var _stats: Label
var _clock: Label
var _toast: Label
var _hint: Label
var _side: PanelContainer
var _side_text: Label
var _side_actions: VBoxContainer
var _build_menu: BuildMenu
var _overlay: PanelContainer
var _overlay_text: Label
var _overlay_actions: HBoxContainer

var _tool: int = Tool.NONE
var _touches: Dictionary = {}
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _moved := false
var _pinch_distance := 0.0
var _last_tap_cell := -1
var _last_tap_ms := 0
var _toast_left := 0.0
var _mood_timer := 0.0

func _ready() -> void:
	map_view = MapView.new()
	map_view.state = Net.state
	map_view.local_player = Net.local_player
	add_child(map_view)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.75, 0.75)
	add_child(camera)
	camera.make_current()
	_centre_on_home()

	_build_hud()

	Net.match_advanced.connect(_on_advanced)
	Net.match_finished.connect(_on_finished)
	Net.command_refused.connect(_show_toast)
	Net.opponent_disconnected.connect(_on_opponent_disconnected)
	Net.connection_lost.connect(_on_connection_lost)
	Net.pause_changed.connect(_on_pause_changed)
	_refresh_stats()

func _centre_on_home() -> void:
	var st := Net.state
	if st == null:
		return
	for i in range(st.owner_of.size()):
		if int(st.owner_of[i]) == Net.local_player:
			camera.position = map_view.cell_rect(i).get_center()
			return
	camera.position = map_view.map_size() * 0.5

# --- HUD construction ------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.98, 0.96, 0.90, 0.92)))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 58
	_hud.add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)

	_stats = Label.new()
	_stats.add_theme_color_override("font_color", Ink.INK)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats)

	_clock = Label.new()
	_clock.add_theme_color_override("font_color", Ink.INK_SOFT)
	row.add_child(_clock)

	var menu_button := Button.new()
	menu_button.text = I18n.t("leave")
	menu_button.pressed.connect(func(): emit_signal("exit_requested"))
	row.add_child(menu_button)

	_hint = Label.new()
	_hint.text = I18n.t("hint_tap")
	_hint.add_theme_color_override("font_color", Ink.INK_SOFT)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -34
	_hud.add_child(_hint)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Ink.PENS[1])
	_toast.visible = false
	_hud.add_child(_toast)

	_side = PanelContainer.new()
	_side.add_theme_stylebox_override("panel", _panel_style(Color(0.98, 0.96, 0.90, 0.95)))
	_side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_side.offset_left = -280
	_side.offset_top = 70
	_side.offset_right = -12
	_side.visible = false
	_hud.add_child(_side)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	_side.add_child(side_box)
	_side_text = Label.new()
	_side_text.add_theme_color_override("font_color", Ink.INK)
	_side_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_text.custom_minimum_size.x = 248
	side_box.add_child(_side_text)
	_side_actions = VBoxContainer.new()
	_side_actions.add_theme_constant_override("separation", 6)
	side_box.add_child(_side_actions)

	_build_menu = BuildMenu.new()
	_build_menu.set_anchors_preset(Control.PRESET_CENTER)
	_build_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_build_menu.visible = false
	_build_menu.picked.connect(_on_build_picked)
	_build_menu.closed.connect(func(): _build_menu.visible = false)
	_hud.add_child(_build_menu)

	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", _panel_style(Color(0.98, 0.96, 0.90, 0.97)))
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	_overlay.visible = false
	_hud.add_child(_overlay)
	var overlay_box := VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 12)
	_overlay.add_child(overlay_box)
	_overlay_text = Label.new()
	_overlay_text.add_theme_color_override("font_color", Ink.INK)
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.add_theme_font_size_override("font_size", 22)
	overlay_box.add_child(_overlay_text)
	_overlay_actions = HBoxContainer.new()
	_overlay_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_actions.add_theme_constant_override("separation", 10)
	overlay_box.add_child(_overlay_actions)

static func _panel_style(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = Ink.INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(12)
	return box

# --- Frame work ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false
	if Net.state == null:
		return
	map_view.opponent_focus = Net.opponent_focus
	Net.set_local_focus(map_view.cell_at(camera.position))
	_update_clock()
	_update_mood(delta)

# The music turns tense the moment the two territories actually touch. Scanning the
# grid once a second is plenty for something that changes this rarely.
func _update_mood(delta: float) -> void:
	_mood_timer -= delta
	if _mood_timer > 0.0:
		return
	_mood_timer = 1.0
	Music.set_mood("combat" if _in_contact() else "calm")

func _in_contact() -> bool:
	var st := Net.state
	var me := Net.local_player
	var foe := Net.opponent_index()
	for i in range(st.owner_of.size()):
		if int(st.owner_of[i]) != me:
			continue
		for n in st.neighbours(i):
			if int(st.owner_of[n]) == foe:
				return true
	return false

func _on_advanced() -> void:
	map_view.state = Net.state
	map_view.queue_redraw()
	_refresh_stats()
	if _build_menu.visible and map_view.selected >= 0:
		_build_menu.refresh(Net.state, Net.local_player, map_view.selected)

func _refresh_stats() -> void:
	var st := Net.state
	if st == null:
		return
	var me := Net.local_player
	var agg := st.aggregate(me)
	var per_second := float(Balance.TICKS_PER_SECOND) / float(Balance.UNIT)
	_stats.text = "%s  %d/%d (+%.1f/s)    %s  %d/%d (+%.1f/s)    %s  %d/%d    %s %d" % [
		"C", int(st.coins[me]) / Balance.UNIT, int(agg["coin_cap"]) / Balance.UNIT,
		float(agg["coin_per_tick"]) * per_second,
		"P", int(st.power[me]) / Balance.UNIT, int(agg["power_cap"]) / Balance.UNIT,
		float(agg["power_per_tick"]) * per_second,
		"L", int(agg["free_people"]), int(agg["people"]),
		I18n.t("cells"), int(agg["cells"]),
	]

func _update_clock() -> void:
	var left := maxi(0, Balance.MATCH_LIMIT_TICKS - Net.state.tick_count) / Balance.TICKS_PER_SECOND
	_clock.text = "%s %d:%02d" % [I18n.t("time_left"), left / 60, left % 60]

func _show_toast(text: String) -> void:
	if text.is_empty():
		return
	_toast.text = text
	_toast.visible = true
	_toast_left = 2.0

# --- Input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_press_pos = event.position
			_press_ms = Time.get_ticks_msec()
			_moved = false
		elif _touches.size() == 2:
			_pinch_distance = _touch_distance()
	else:
		var was_single := _touches.size() == 1
		_touches.erase(event.index)
		if was_single and not _moved and Time.get_ticks_msec() - _press_ms < TAP_MS:
			_on_tap(event.position)

func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		var distance := _touch_distance()
		if _pinch_distance > 1.0 and distance > 1.0:
			_zoom_by(distance / _pinch_distance)
		_pinch_distance = distance
		_moved = true
		return
	if event.position.distance_to(_press_pos) > TAP_SLOP:
		_moved = true
	camera.position -= event.relative / camera.zoom.x
	_clamp_camera()

func _touch_distance() -> float:
	var points: Array = _touches.values()
	if points.size() < 2:
		return 0.0
	return (points[0] as Vector2).distance_to(points[1] as Vector2)

func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	_clamp_camera()

# Keep the paper on screen: the camera may not wander off into empty space.
func _clamp_camera() -> void:
	var size := map_view.map_size()
	var margin := MapView.CELL * 2.0
	camera.position.x = clampf(camera.position.x, -margin, size.x + margin)
	camera.position.y = clampf(camera.position.y, -margin, size.y + margin)

func _on_tap(screen_pos: Vector2) -> void:
	var st := Net.state
	if st == null or st.finished:
		return
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var cell := map_view.cell_at(world)
	if cell < 0:
		_close_panels()
		return

	if _tool == Tool.SHIP_TARGET:
		Net.request(GameState.Command.LAUNCH_SHIP, map_view.selected, cell)
		_set_tool(Tool.NONE)
		return

	var now := Time.get_ticks_msec()
	var double_tap := cell == _last_tap_cell and now - _last_tap_ms < DOUBLE_TAP_MS
	_last_tap_cell = cell
	_last_tap_ms = now

	map_view.selected = cell
	map_view.queue_redraw()

	var me := Net.local_player
	if int(st.owner_of[cell]) == me:
		_build_menu.visible = false
		if int(st.building_at[cell]) == Balance.Building.NONE:
			_open_build_menu(cell)
		else:
			_show_own_cell(cell)
		return

	# Somebody else's cell, or open ground. Double tapping is the fast way to push the
	# border; the side panel keeps a button for players who prefer to aim.
	_show_foreign_cell(cell)
	if double_tap and st.is_land(cell) and st.touches_player(cell, me):
		Net.request(GameState.Command.CAPTURE, cell)

func _close_panels() -> void:
	_side.visible = false
	_build_menu.visible = false
	map_view.selected = -1
	_set_tool(Tool.NONE)
	map_view.queue_redraw()

# --- Panels ----------------------------------------------------------------------

func _open_build_menu(cell: int) -> void:
	_side.visible = false
	_build_menu.refresh(Net.state, Net.local_player, cell)
	_build_menu.visible = true

func _on_build_picked(type: int) -> void:
	if map_view.selected < 0:
		return
	Net.request(GameState.Command.BUILD, map_view.selected, type)
	_build_menu.visible = false

func _clear_actions() -> void:
	for child in _side_actions.get_children():
		child.queue_free()

func _add_action(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	_side_actions.add_child(button)

func _show_own_cell(cell: int) -> void:
	var st := Net.state
	var type := int(st.building_at[cell])
	_side_text.text = "%s\n%s" % [I18n.t("you"), I18n.building_name(type)]
	_clear_actions()
	if type == Balance.Building.PORT:
		_add_action(I18n.t("send_ship"), func(): _set_tool(Tool.SHIP_TARGET))
	_add_action(I18n.t("demolish"), func():
		Net.request(GameState.Command.DEMOLISH, cell)
		_side.visible = false)
	_side.visible = true

# In a practice match the other seat is the bot, and saying so is the difference between
# "the opponent is quiet" and "the bot is thinking".
func _opponent_name() -> String:
	return I18n.t("bot") if Net.bot != null else I18n.t("opponent")

func _show_foreign_cell(cell: int) -> void:
	var st := Net.state
	var me := Net.local_player
	var owner_id := int(st.owner_of[cell])
	var lines: Array[String] = []
	if owner_id == GameState.NEUTRAL:
		lines.append(I18n.t("capture") if st.is_land(cell) else I18n.t("e_sea_cell"))
	else:
		var agg := st.aggregate(owner_id)
		var per_second := float(Balance.TICKS_PER_SECOND) / float(Balance.UNIT)
		lines.append(_opponent_name())
		lines.append("%s: %d" % [I18n.t("cells"), int(agg["cells"])])
		lines.append("%s: %.1f C/s, %.1f P/s" % [I18n.t("income"),
			float(agg["coin_per_tick"]) * per_second, float(agg["power_per_tick"]) * per_second])
		if Net.opponent_focus >= 0:
			lines.append(I18n.t("look_here"))
	_side_text.text = "\n".join(lines)
	_clear_actions()
	if st.is_land(cell) and st.touches_player(cell, me):
		_add_action("%s (%d P)" % [I18n.t("capture"), Balance.CAPTURE_POWER_COST / Balance.UNIT],
			func(): Net.request(GameState.Command.CAPTURE, cell))
	_side.visible = true

# --- Ship targeting --------------------------------------------------------------

func _set_tool(tool: int) -> void:
	_tool = tool
	if tool == Tool.SHIP_TARGET and map_view.selected >= 0:
		map_view.ship_targets = _ship_targets(map_view.selected)
		_show_toast(I18n.t("pick_target"))
	else:
		map_view.ship_targets = PackedInt32Array()
	map_view.queue_redraw()

# Highlights every shore this port can reach. The simulation answers that question, so
# what is highlighted and what is allowed can never drift apart.
func _ship_targets(port_cell: int) -> PackedInt32Array:
	var st := Net.state
	if st == null:
		return PackedInt32Array()
	var found := PackedInt32Array()
	for cell in st.reachable_shores(port_cell):
		if int(st.owner_of[cell]) != Net.local_player:
			found.append(cell)
	return found

# --- Overlays --------------------------------------------------------------------

func _clear_overlay_actions() -> void:
	for child in _overlay_actions.get_children():
		child.queue_free()

func _add_overlay_action(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	_overlay_actions.add_child(button)

func _on_finished() -> void:
	var st := Net.state
	var text := I18n.t("draw")
	if st.winner == Net.local_player:
		text = I18n.t("victory")
	elif st.winner >= 0:
		text = I18n.t("defeat")
	_overlay_text.text = text
	_clear_overlay_actions()
	_add_overlay_action(I18n.t("back_to_menu"), func(): emit_signal("exit_requested"))
	_overlay.visible = true

func _on_opponent_disconnected() -> void:
	_overlay_text.text = I18n.t("opponent_lost") % _opponent_name()
	_clear_overlay_actions()
	_add_overlay_action(I18n.t("keep_waiting"), func(): _overlay.visible = false)
	_add_overlay_action(I18n.t("end_match"), func(): emit_signal("exit_requested"))
	_overlay.visible = true

func _on_connection_lost(reason: String) -> void:
	_overlay_text.text = reason
	_clear_overlay_actions()
	_add_overlay_action(I18n.t("back_to_menu"), func(): emit_signal("exit_requested"))
	_overlay.visible = true

func _on_pause_changed(is_paused: bool) -> void:
	if not is_paused:
		if _overlay_text.text == I18n.t("paused"):
			_overlay.visible = false
		return
	if _overlay.visible:
		return
	_overlay_text.text = I18n.t("paused")
	_clear_overlay_actions()
	if Net.is_host:
		_add_overlay_action(I18n.t("resume"), func(): Net.set_paused(false))
	_add_overlay_action(I18n.t("leave"), func(): emit_signal("exit_requested"))
	_overlay.visible = true
