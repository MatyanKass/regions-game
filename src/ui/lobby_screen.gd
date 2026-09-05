# The lobby: play the bot, host a room, or join one of the rooms shouting on the local
# network. Typing an address stays available because some networks drop broadcast
# traffic.
#
# A CanvasLayer rather than a plain Control: a Control whose parent is an ordinary Node
# has no rectangle to anchor against, which is how this screen previously ended up piled
# into the top left corner at its minimum size.
class_name LobbyScreen
extends CanvasLayer

# These survive a language switch, which rebuilds this screen.
static var bot_level: int = BotPlayer.Level.NORMAL
static var map_size: int = 25
static var sea_choice: int = -1        # -1 leaves it to the seed
static var match_minutes: int = 40

const CARD_WIDTH := 470
const WIDE_ENOUGH := 980   # below this the decorative board is dropped

var _status: Label
var _rooms_box: VBoxContainer
var _address: LineEdit
var _level_button: OptionButton
var _size_note: Label

func _ready() -> void:
	var paper := UiKit.Paper.new()
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)

	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 28)
	add_child(frame)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 48)
	frame.add_child(columns)

	# The card grew a world section and no longer fits a short screen, so it scrolls. A
	# phone held sideways has very little height to spare.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(CARD_WIDTH + 16, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_column())
	columns.add_child(scroll)

	# The board on the right is the game's own icon art, blown up. It fills what was an
	# empty half of the screen with something that says what the game is.
	if get_viewport().get_visible_rect().size.x >= WIDE_ENOUGH:
		var art := IconArt.new()
		art.custom_minimum_size = Vector2(330, 330)
		art.transparent = false
		art.inset = 0.04
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		columns.add_child(art)

	Net.rooms_changed.connect(_refresh_rooms)
	Net.lobby_status.connect(func(text: String): _status.text = text)
	Net.connection_lost.connect(func(text: String): _status.text = text)
	Music.set_mood("calm")
	Net.browse_rooms()
	_refresh_rooms()

func _menu_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)

	var title := UiKit.heading(I18n.t("app_title"), 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var underline := UiKit.Underline.new()
	underline.custom_minimum_size = Vector2(0, 18)
	underline.colour = Ink.PENS[0]
	column.add_child(underline)

	var subtitle := UiKit.body(I18n.t("tagline"), 14, Ink.INK_SOFT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	column.add_child(spacer)

	var card := PanelContainer.new()
	UiKit.panel(card)
	column.add_child(card)
	card.add_child(_card_contents())
	return column

func _card_contents() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	# Practice comes first: it is the one thing a player alone with a phone can do.
	var practice_row := HBoxContainer.new()
	practice_row.add_theme_constant_override("separation", 8)
	var practice := _big_button(I18n.t("practice"), Ink.PENS[0], true)
	practice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice.pressed.connect(_on_practice)
	practice_row.add_child(practice)

	_level_button = OptionButton.new()
	_level_button.custom_minimum_size = Vector2(140, 50)
	_level_button.tooltip_text = I18n.t("difficulty")
	for level in [BotPlayer.Level.EASY, BotPlayer.Level.NORMAL, BotPlayer.Level.HARD]:
		_level_button.add_item(I18n.bot_level_name(level), level)
	_level_button.select(_level_button.get_item_index(bot_level))
	_level_button.item_selected.connect(func(index: int): bot_level = _level_button.get_item_id(index))
	UiKit.option(_level_button)
	practice_row.add_child(_level_button)
	box.add_child(practice_row)

	var free := _big_button(I18n.t("free_play"))
	free.pressed.connect(_on_free_play)
	box.add_child(free)

	var host := _big_button(I18n.t("host_game"))
	host.pressed.connect(_on_host)
	box.add_child(host)

	box.add_child(_divider(I18n.t("world")))
	box.add_child(_world_settings())

	box.add_child(_divider(I18n.t("rooms")))

	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	box.add_child(_rooms_box)

	var manual := HBoxContainer.new()
	manual.add_theme_constant_override("separation", 8)
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.0.10"
	_address.custom_minimum_size.y = 42
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.line_edit(_address)
	_address.text_submitted.connect(func(text: String): _join(text.strip_edges()))
	manual.add_child(_address)
	var join := Button.new()
	join.text = I18n.t("join")
	join.custom_minimum_size = Vector2(110, 42)
	UiKit.button(join)
	join.pressed.connect(func(): _join(_address.text.strip_edges()))
	manual.add_child(join)
	box.add_child(manual)

	_status = UiKit.body("", 13, Ink.INK_SOFT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	var language := Button.new()
	language.text = I18n.t("language")
	language.custom_minimum_size = Vector2(120, 34)
	UiKit.button(language)
	language.pressed.connect(_on_language)
	footer.add_child(language)
	box.add_child(footer)
	return box

# The world is chosen before anyone plays in it: how big, how much of it is water, and
# how long a match may run. Free play ignores the clock.
func _world_settings() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)

	grid.add_child(UiKit.body(I18n.t("map_size"), 14, Ink.INK_SOFT))
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	var sizes := OptionButton.new()
	sizes.custom_minimum_size = Vector2(120, 38)
	for value in WorldSettings.SIZES:
		sizes.add_item("%d × %d" % [value, value], value)
	if sizes.get_item_index(map_size) < 0:
		sizes.add_item("%d × %d" % [map_size, map_size], map_size)
	sizes.select(sizes.get_item_index(map_size))
	UiKit.option(sizes)
	sizes.item_selected.connect(func(index: int):
		map_size = sizes.get_item_id(index)
		_update_world_note())
	size_row.add_child(sizes)
	_size_note = UiKit.body("", 12, Ink.INK_SOFT)
	_size_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_row.add_child(_size_note)
	grid.add_child(size_row)

	grid.add_child(UiKit.body(I18n.t("sea"), 14, Ink.INK_SOFT))
	var seas := OptionButton.new()
	seas.custom_minimum_size = Vector2(160, 38)
	seas.add_item(I18n.t("sea_random"), 100)
	for percent in [0, 5, 10, 20, 35]:
		seas.add_item("%d%%" % percent, percent)
	seas.select(seas.get_item_index(100 if sea_choice < 0 else sea_choice))
	UiKit.option(seas)
	seas.item_selected.connect(func(index: int):
		var id := seas.get_item_id(index)
		sea_choice = -1 if id == 100 else id)
	grid.add_child(seas)

	grid.add_child(UiKit.body(I18n.t("match_length"), 14, Ink.INK_SOFT))
	var lengths := OptionButton.new()
	lengths.custom_minimum_size = Vector2(160, 38)
	for value in [10, 20, 40, 90]:
		lengths.add_item("%d %s" % [value, I18n.t("minutes")], value)
	lengths.select(lengths.get_item_index(match_minutes))
	UiKit.option(lengths)
	lengths.item_selected.connect(func(index: int): match_minutes = lengths.get_item_id(index))
	grid.add_child(lengths)

	_update_world_note()
	return grid

func _update_world_note() -> void:
	if _size_note == null:
		return
	var cells := map_size * map_size
	var text := "%s %s" % [_thousands(cells), I18n.t("cells_count")]
	if cells >= 40000:
		text += "\n" + I18n.t("huge_world_hint")
	_size_note.text = text

static func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	for i in range(text.length()):
		if i > 0 and (text.length() - i) % 3 == 0:
			out += " "
		out += text[i]
	return out

func _chosen_world() -> WorldSettings:
	var world := WorldSettings.of_size(map_size)
	world.sea_percent = sea_choice
	world.match_minutes = match_minutes
	return world

func _big_button(text: String, accent: Color = Ink.INK, filled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", 17)
	UiKit.button(button, accent, filled)
	return button

# A caption with a rule running off to the right: it separates the sections without
# spending a whole line on a border.
func _divider(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiKit.body(text, 13, Ink.INK_SOFT))
	var rule := UiKit.Underline.new()
	rule.colour = Ink.SLOT_DARK
	rule.custom_minimum_size = Vector2(0, 8)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	return row

func _on_practice() -> void:
	Net.start_practice(bot_level, 0, _chosen_world())

func _on_free_play() -> void:
	Net.start_free(_chosen_world())

func _on_host() -> void:
	if Net.host_room(_default_room_name(), _chosen_world()):
		_status.text = I18n.t("waiting_player")

func _join(ip: String) -> void:
	if ip.is_empty():
		return
	Net.join_room(ip)

func _default_room_name() -> String:
	var name := OS.get_model_name()
	return name if not name.is_empty() else "Regions"

func _refresh_rooms() -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	if Net.discovery.rooms.is_empty():
		var empty := UiKit.body(I18n.t("searching"), 13, Ink.INK_SOFT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rooms_box.add_child(empty)
		return
	# Sort by address so the list does not jump about between broadcasts.
	var addresses := Net.discovery.rooms.keys()
	addresses.sort()
	for ip in addresses:
		var room: Dictionary = Net.discovery.rooms[ip]
		var button := Button.new()
		button.text = "%s   ·   %s" % [str(room["name"]), ip]
		button.custom_minimum_size.y = 44
		UiKit.button(button, Ink.PENS[0])
		button.pressed.connect(func(): _join(str(ip)))
		_rooms_box.add_child(button)

func _on_language() -> void:
	I18n.toggle()
	# Rebuilding is simpler and safer than hunting down every label.
	var parent := get_parent()
	var replacement := LobbyScreen.new()
	parent.add_child(replacement)
	queue_free()
