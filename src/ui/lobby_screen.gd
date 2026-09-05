# The lobby: play the bot, host a room, or join one of the rooms shouting on the local
# network. Typing an address stays available because some networks drop broadcast
# traffic.
#
# A CanvasLayer rather than a plain Control: a Control whose parent is an ordinary Node
# has no rectangle to anchor against, which is how this screen previously ended up piled
# into the top left corner at its minimum size.
class_name LobbyScreen
extends CanvasLayer

# The chosen difficulty survives a language switch, which rebuilds this screen.
static var bot_level: int = BotPlayer.Level.NORMAL

const CARD_WIDTH := 470
const WIDE_ENOUGH := 980   # below this the decorative board is dropped

var _status: Label
var _rooms_box: VBoxContainer
var _address: LineEdit
var _level_button: OptionButton

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

	columns.add_child(_menu_column())

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
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

	var host := _big_button(I18n.t("host_game"))
	host.pressed.connect(_on_host)
	box.add_child(host)

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
	Net.start_practice(bot_level)

func _on_host() -> void:
	if Net.host_room(_default_room_name()):
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
