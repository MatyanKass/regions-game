# The match: map, camera, HUD and every panel the player can open.
#
# Input is organised around three modes chosen on the bottom bar, so a tap on the map
# always means exactly one thing. Attacking is therefore a single tap, paced by a
# cooldown rather than by making the player tap twice.
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
const BAR_HEIGHT := 96

enum Mode { BUILD, ATTACK, INFO }

var map_view: MapView
var camera: Camera2D

var _hud: CanvasLayer
var _chips: Dictionary = {}         # name -> UiKit.Chip
var _clock: Label
var _toast: Label
var _hint: Label
var _mode_buttons: Dictionary = {}  # Mode -> Button
var _cooldown_bar: ProgressBar
var _cooldown_label: Label
var _info: PanelContainer
var _info_text: Label
var _build_menu: BuildMenu
var _cell_menu: CellMenu
var _overlay: PanelContainer
var _overlay_text: Label
var _overlay_actions: HBoxContainer

var _mode: int = Mode.BUILD
var _ship_port := -1
var _touches: Dictionary = {}
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _moved := false
var _pinch_distance := 0.0
var _toast_left := 0.0
var _mood_timer := 0.0
# Watched so that losing ground can be heard, however it was lost: an enemy capture
# and a ship landing both simply take a cell away.
var _known_cells := -1

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
	set_mode(Mode.BUILD)

	Net.match_advanced.connect(_on_advanced)
	Net.match_finished.connect(_on_finished)
	Net.command_refused.connect(_on_refused)
	Net.command_applied.connect(_on_command_applied)
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

# In a practice match the other seat is the bot, and saying so is the difference between
# "the opponent is quiet" and "the bot is thinking".
func _opponent_name() -> String:
	return I18n.t("bot") if Net.bot != null else I18n.t("opponent")

# --- HUD construction ------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_build_top_bar()
	_build_bottom_bar()
	_build_panels()

func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UiKit.box(Ink.PAPER_PANEL, Ink.INK, 0, 0, 10))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 62
	_hud.add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	top.add_child(row)

	for entry in [["coins", Ink.Icon.COIN], ["power", Ink.Icon.POWER], ["people", Ink.Icon.PEOPLE]]:
		var chip := UiKit.chip(int(entry[1]), Ink.pen_of(Net.local_player))
		_chips[str(entry[0])] = chip
		row.add_child(chip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(UiKit.glyph_for_icon(Ink.Icon.CLOCK, 20, Ink.INK_SOFT))
	_clock = UiKit.heading("", 17, Ink.INK_SOFT)
	row.add_child(_clock)

	var menu_button := Button.new()
	menu_button.text = I18n.t("leave")
	UiKit.button(menu_button)
	menu_button.pressed.connect(func(): emit_signal("exit_requested"))
	row.add_child(menu_button)

# The three action modes. A tap on the map always means whatever is selected here, which
# is what lets attacking be one tap instead of two.
func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.box(Ink.PAPER_PANEL, Ink.INK, 0, 0, 8))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR_HEIGHT
	_hud.add_child(bar)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	bar.add_child(column)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	for entry in [
			[Mode.BUILD, Ink.Icon.BUILD, "mode_build"],
			[Mode.ATTACK, Ink.Icon.ATTACK, "mode_attack"],
			[Mode.INFO, Ink.Icon.INFO, "mode_info"]]:
		var mode := int(entry[0])
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 56)
		button.pressed.connect(set_mode.bind(mode))
		var content := HBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 8)
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(UiKit.glyph_for_icon(int(entry[1]), 26))
		var label := UiKit.heading(I18n.t(str(entry[2])), 17)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		button.add_child(content)
		row.add_child(button)
		_mode_buttons[mode] = button

	# The reload sits under the buttons, right where the thumb already is.
	var reload_row := HBoxContainer.new()
	reload_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reload_row.add_theme_constant_override("separation", 8)
	column.add_child(reload_row)
	_cooldown_label = UiKit.body("", 12, Ink.INK_SOFT)
	reload_row.add_child(_cooldown_label)
	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.custom_minimum_size = Vector2(300, 8)
	_cooldown_bar.show_percentage = false
	_cooldown_bar.max_value = 1.0
	_cooldown_bar.add_theme_stylebox_override("background",
		UiKit.box(Ink.PAPER_DARK, Ink.SLOT_DARK, 1, 4, 0))
	_cooldown_bar.add_theme_stylebox_override("fill",
		UiKit.box(Ink.pen_of(Net.local_player), Ink.pen_of(Net.local_player), 0, 4, 0))
	reload_row.add_child(_cooldown_bar)

	_hint = UiKit.body("", 13, Ink.INK_SOFT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -BAR_HEIGHT - 24
	_hud.add_child(_hint)

func _build_panels() -> void:
	_toast = UiKit.heading("", 16, Ink.PENS[1])
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 74
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	_hud.add_child(_toast)

	_info = PanelContainer.new()
	UiKit.panel(_info)
	_info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_info.offset_left = -300
	_info.offset_top = 74
	_info.offset_right = -14
	_info.visible = false
	_hud.add_child(_info)
	_info_text = UiKit.body("", 15)
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.custom_minimum_size.x = 262
	_info.add_child(_info_text)

	_build_menu = BuildMenu.new()
	_centre(_build_menu)
	_build_menu.picked.connect(_on_build_picked)
	_build_menu.closed.connect(func(): _build_menu.visible = false)
	_hud.add_child(_build_menu)

	_cell_menu = CellMenu.new()
	_centre(_cell_menu)
	_cell_menu.upgrade_requested.connect(_on_upgrade)
	_cell_menu.demolish_requested.connect(_on_demolish)
	_cell_menu.ship_requested.connect(_on_send_ship)
	_cell_menu.closed.connect(func(): _cell_menu.visible = false)
	_hud.add_child(_cell_menu)

	_overlay = PanelContainer.new()
	UiKit.panel(_overlay)
	_centre(_overlay)
	_hud.add_child(_overlay)
	var overlay_box := VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 14)
	_overlay.add_child(overlay_box)
	_overlay_text = UiKit.heading("", 24)
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(_overlay_text)
	_overlay_actions = HBoxContainer.new()
	_overlay_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_actions.add_theme_constant_override("separation", 10)
	overlay_box.add_child(_overlay_actions)

static func _centre(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_CENTER)
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = Control.GROW_DIRECTION_BOTH
	node.visible = false

# --- Modes -----------------------------------------------------------------------

func set_mode(mode: int) -> void:
	_mode = mode
	_ship_port = -1
	map_view.ship_targets = PackedInt32Array()
	_build_menu.visible = false
	_cell_menu.visible = false
	_info.visible = false
	for key in _mode_buttons:
		var button: Button = _mode_buttons[key]
		var selected := int(key) == mode
		UiKit.button(button, Ink.pen_of(Net.local_player) if selected else Ink.INK, selected)
		_tint(button, Ink.PAPER if selected else Ink.INK)
	match mode:
		Mode.BUILD:
			_hint.text = I18n.t("hint_build")
		Mode.ATTACK:
			_hint.text = I18n.t("hint_attack")
		_:
			_hint.text = I18n.t("hint_info")
	map_view.attack_mode = mode == Mode.ATTACK
	map_view.queue_redraw()

# Buttons carry their own icon and label as children, so switching a mode on has to
# recolour the contents as well as the frame.
func _tint(node: Node, colour: Color) -> void:
	if node is UiKit.Glyph:
		(node as UiKit.Glyph).set_colour(colour)
	elif node is Label:
		(node as Label).add_theme_color_override("font_color", colour)
	for child in node.get_children():
		_tint(child, colour)

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
	_update_cooldown()
	_update_mood(delta)

# The music turns tense the moment the two territories actually touch. Scanning the grid
# once a second is plenty for something that changes this rarely.
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

# Only the local player's own actions are announced. Hearing every move the opponent
# makes across the whole map would be noise; losing a cell is the exception, and that is
# noticed by watching the count rather than by listening to their commands.
func _on_command_applied(player: int, type: int, _a: int, _b: int) -> void:
	if player != Net.local_player:
		return
	match type:
		GameState.Command.BUILD:
			Sfx.play("build")
		GameState.Command.UPGRADE:
			Sfx.play("upgrade")
		GameState.Command.DEMOLISH:
			Sfx.play("demolish")
		GameState.Command.CAPTURE:
			Sfx.play("capture")
		GameState.Command.LAUNCH_SHIP:
			Sfx.play("ship")

func _on_refused(text: String) -> void:
	Sfx.play("denied")
	_show_toast(text)

func _on_advanced() -> void:
	map_view.state = Net.state
	map_view.queue_redraw()
	_refresh_stats()
	_watch_for_losses()
	if _build_menu.visible and map_view.selected >= 0:
		_build_menu.refresh(Net.state, Net.local_player, map_view.selected)
	if _cell_menu.visible and map_view.selected >= 0:
		# The building can be taken or destroyed while its menu is open.
		if int(Net.state.building_at[map_view.selected]) == Balance.Building.NONE \
				or int(Net.state.owner_of[map_view.selected]) != Net.local_player:
			_cell_menu.visible = false
		else:
			_cell_menu.show_cell(Net.state, Net.local_player, map_view.selected)

func _watch_for_losses() -> void:
	var cells := int(Net.state.aggregate(Net.local_player)["cells"])
	if _known_cells >= 0 and cells < _known_cells:
		Sfx.play("lost_cell")
	_known_cells = cells

func _refresh_stats() -> void:
	var st := Net.state
	if st == null:
		return
	var me := Net.local_player
	var agg := st.aggregate(me)
	var per_second := float(Balance.TICKS_PER_SECOND) / float(Balance.UNIT)
	(_chips["coins"] as UiKit.Chip).set_values(
		"%d/%d" % [int(st.coins[me]) / Balance.UNIT, int(agg["coin_cap"]) / Balance.UNIT],
		"+%.1f/%s" % [float(agg["coin_per_tick"]) * per_second, I18n.t("second")])
	(_chips["power"] as UiKit.Chip).set_values(
		"%d/%d" % [int(st.power[me]) / Balance.UNIT, int(agg["power_cap"]) / Balance.UNIT],
		"+%.1f/%s" % [float(agg["power_per_tick"]) * per_second, I18n.t("second")])
	var idle := int((agg["idle_cells"] as PackedInt32Array).size())
	(_chips["people"] as UiKit.Chip).set_values(
		"%d/%d" % [int(agg["free_people"]), int(agg["people"])],
		"%s %d" % [I18n.t("cells"), int(agg["cells"])] if idle == 0
			else "%d %s" % [idle, I18n.t("idle")])
	# Idle factories are money the player thinks they are earning and is not, so the
	# figure turns the warning colour rather than sitting quietly in grey.
	(_chips["people"] as UiKit.Chip).rate_label.add_theme_color_override("font_color",
		Ink.ALERT if idle > 0 else Ink.INK_SOFT)

func _update_clock() -> void:
	var left := maxi(0, Balance.MATCH_LIMIT_TICKS - Net.state.tick_count) / Balance.TICKS_PER_SECOND
	_clock.text = "%d:%02d" % [left / 60, left % 60]

func _update_cooldown() -> void:
	var ticks := Net.state.capture_cooldown_left(Net.local_player)
	map_view.cooldown_left = ticks
	# The bar is scaled against the longest wait in the game, a barrier, so a four second
	# stall visibly dwarfs the quarter second of ordinary fire.
	_cooldown_bar.value = clampf(float(ticks) / float(Balance.BARRIER_COOLDOWN_TICKS), 0.0, 1.0)
	_cooldown_bar.visible = ticks > 0
	_cooldown_label.visible = ticks > 0
	if ticks > 0:
		_cooldown_label.text = "%s %.1f%s" % [I18n.t("cooldown"),
			float(ticks) / float(Balance.TICKS_PER_SECOND), I18n.t("second")]

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
		return

	# Aiming a ship overrides the mode until the target is chosen.
	if _ship_port >= 0:
		Net.request(GameState.Command.LAUNCH_SHIP, _ship_port, cell)
		_ship_port = -1
		map_view.ship_targets = PackedInt32Array()
		map_view.queue_redraw()
		return

	map_view.selected = cell
	map_view.queue_redraw()
	match _mode:
		Mode.BUILD:
			_tap_build(st, cell)
		Mode.ATTACK:
			Net.request(GameState.Command.CAPTURE, cell)
		_:
			_tap_info(st, cell)

func _tap_build(st: GameState, cell: int) -> void:
	if int(st.owner_of[cell]) != Net.local_player:
		_show_toast(I18n.reason("not_your_cell"))
		return
	if int(st.building_at[cell]) == Balance.Building.NONE:
		_cell_menu.visible = false
		_build_menu.refresh(st, Net.local_player, cell)
		_build_menu.visible = true
	else:
		_build_menu.visible = false
		_cell_menu.show_cell(st, Net.local_player, cell)
		_cell_menu.visible = true

func _tap_info(st: GameState, cell: int) -> void:
	var owner_id := int(st.owner_of[cell])
	var lines: Array[String] = []
	if owner_id == GameState.NEUTRAL:
		lines.append(I18n.t("neutral_land") if st.is_land(cell) else I18n.t("e_sea_cell"))
	else:
		var agg := st.aggregate(owner_id)
		var per_second := float(Balance.TICKS_PER_SECOND) / float(Balance.UNIT)
		lines.append(I18n.t("you") if owner_id == Net.local_player else _opponent_name())
		lines.append("%s: %d" % [I18n.t("cells"), int(agg["cells"])])
		lines.append("%s: +%.1f/%s" % [I18n.t("coin_rate"),
			float(agg["coin_per_tick"]) * per_second, I18n.t("second")])
		lines.append("%s: +%.1f/%s" % [I18n.t("power_rate"),
			float(agg["power_per_tick"]) * per_second, I18n.t("second")])
		lines.append("%s: %d/%d" % [I18n.t("people"), int(agg["free_people"]), int(agg["people"])])
		if owner_id != Net.local_player and Net.opponent_focus >= 0:
			lines.append(I18n.t("look_here"))
	var type := int(st.building_at[cell])
	if type != Balance.Building.NONE:
		lines.append("")
		lines.append("%s, %s %d" % [I18n.building_name(type), I18n.t("level"),
			maxi(1, int(st.level_at[cell]))])
	_info_text.text = "\n".join(lines)
	_info.visible = true

# --- Panel actions ---------------------------------------------------------------

func _on_build_picked(type: int) -> void:
	if map_view.selected < 0:
		return
	Net.request(GameState.Command.BUILD, map_view.selected, type)
	_build_menu.visible = false

func _on_upgrade() -> void:
	if map_view.selected >= 0:
		Net.request(GameState.Command.UPGRADE, map_view.selected)

func _on_demolish() -> void:
	if map_view.selected >= 0:
		Net.request(GameState.Command.DEMOLISH, map_view.selected)
	_cell_menu.visible = false

func _on_send_ship() -> void:
	_ship_port = map_view.selected
	_cell_menu.visible = false
	map_view.ship_targets = _ship_targets(_ship_port)
	map_view.queue_redraw()
	_show_toast(I18n.t("pick_target"))

# Highlights every shore this port can reach. The simulation answers that question, so
# what is highlighted and what is allowed can never drift apart.
func _ship_targets(port_cell: int) -> PackedInt32Array:
	var st := Net.state
	if st == null or port_cell < 0:
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
	button.custom_minimum_size = Vector2(160, 44)
	UiKit.button(button)
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
	Sfx.play("victory" if st.winner == Net.local_player else "defeat")
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
