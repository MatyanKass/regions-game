# The lobby: host a room, or pick one of the rooms shouting on the local network.
# Typing an address stays available because some networks drop broadcast traffic.
class_name LobbyScreen
extends Control

# The chosen difficulty survives a language switch, which rebuilds this screen.
static var bot_level: int = BotPlayer.Level.NORMAL

var _status: Label
var _rooms_box: VBoxContainer
var _address: LineEdit
var _language_button: Button
var _level_button: OptionButton

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Ink.PAPER
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.add_theme_constant_override("separation", 14)
	centre.custom_minimum_size = Vector2(420, 0)
	add_child(centre)

	var title := Label.new()
	title.text = I18n.t("app_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Ink.INK)
	centre.add_child(title)

	# Practice comes first: it is the one thing a player alone with the phone can do.
	var practice_row := HBoxContainer.new()
	practice_row.add_theme_constant_override("separation", 8)
	var practice_button := Button.new()
	practice_button.text = I18n.t("practice")
	practice_button.custom_minimum_size.y = 48
	practice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_button.pressed.connect(_on_practice)
	practice_row.add_child(practice_button)
	_level_button = OptionButton.new()
	_level_button.tooltip_text = I18n.t("difficulty")
	for level in [BotPlayer.Level.EASY, BotPlayer.Level.NORMAL, BotPlayer.Level.HARD]:
		_level_button.add_item(I18n.bot_level_name(level), level)
	_level_button.select(_level_button.get_item_index(bot_level))
	_level_button.item_selected.connect(func(index: int): bot_level = _level_button.get_item_id(index))
	practice_row.add_child(_level_button)
	centre.add_child(practice_row)

	var host_button := Button.new()
	host_button.text = I18n.t("host_game")
	host_button.custom_minimum_size.y = 48
	host_button.pressed.connect(_on_host)
	centre.add_child(host_button)

	var rooms_title := Label.new()
	rooms_title.text = I18n.t("rooms")
	rooms_title.add_theme_color_override("font_color", Ink.INK_SOFT)
	centre.add_child(rooms_title)

	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	centre.add_child(_rooms_box)

	var manual := HBoxContainer.new()
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.0.10"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual.add_child(_address)
	var join := Button.new()
	join.text = I18n.t("join_by_ip")
	join.pressed.connect(func(): _join(_address.text.strip_edges()))
	manual.add_child(join)
	centre.add_child(manual)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Ink.INK_SOFT)
	centre.add_child(_status)

	_language_button = Button.new()
	_language_button.text = I18n.t("language")
	_language_button.pressed.connect(_on_language)
	centre.add_child(_language_button)

	Net.rooms_changed.connect(_refresh_rooms)
	Net.lobby_status.connect(func(text: String): _status.text = text)
	Net.connection_lost.connect(func(text: String): _status.text = text)
	Music.set_mood("calm")
	Net.browse_rooms()
	_refresh_rooms()

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
		var empty := Label.new()
		empty.text = I18n.t("searching")
		empty.add_theme_color_override("font_color", Ink.INK_SOFT)
		_rooms_box.add_child(empty)
		return
	# Sort by address so the list does not jump around between broadcasts.
	var addresses := Net.discovery.rooms.keys()
	addresses.sort()
	for ip in addresses:
		var room: Dictionary = Net.discovery.rooms[ip]
		var button := Button.new()
		button.text = "%s  -  %s" % [str(room["name"]), ip]
		button.custom_minimum_size.y = 40
		button.pressed.connect(func(): _join(str(ip)))
		_rooms_box.add_child(button)

func _on_language() -> void:
	I18n.toggle()
	# Rebuilding is simpler and safer than hunting down every label.
	var parent := get_parent()
	var replacement := LobbyScreen.new()
	parent.add_child(replacement)
	queue_free()
