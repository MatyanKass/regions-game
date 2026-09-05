# The settings, as one panel that both the lobby and the pause menu put on screen. There
# is exactly one of these so the two places cannot drift apart.
class_name SettingsPanel
extends PanelContainer

signal closed

func _init() -> void:
	UiKit.panel(self)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var header := HBoxContainer.new()
	var title := UiKit.heading(I18n.t("settings"), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 32)
	UiKit.button(close)
	close.pressed.connect(func(): emit_signal("closed"))
	header.add_child(close)
	column.add_child(header)

	column.add_child(_slider(I18n.t("music_volume"), Prefs.music_volume,
		func(value: float): Prefs.set_music_volume(value)))
	column.add_child(_slider(I18n.t("sfx_volume"), Prefs.sfx_volume,
		func(value: float): Prefs.set_sfx_volume(value)))

	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 10)
	var label := UiKit.body(I18n.t("language_label"), 14, Ink.INK_SOFT)
	label.custom_minimum_size.x = 150
	language_row.add_child(label)
	var language := Button.new()
	language.text = I18n.t("language")
	language.custom_minimum_size = Vector2(150, 38)
	UiKit.button(language)
	language.pressed.connect(func():
		Prefs.set_language("en" if I18n.language == "ru" else "ru"))
	language_row.add_child(language)
	column.add_child(language_row)

	var note := UiKit.body(I18n.t("language_note"), 12, Ink.INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 340
	column.add_child(note)

# A labelled slider that reports as it moves, so the volume can be heard while it is
# being set rather than only after letting go.
func _slider(text: String, value: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := UiKit.body(text, 14, Ink.INK_SOFT)
	label.custom_minimum_size.x = 150
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	# Set without notifying, so building the panel never counts as changing a setting.
	slider.set_value_no_signal(value)
	slider.custom_minimum_size = Vector2(190, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.add_theme_stylebox_override("slider", UiKit.box(Ink.PAPER_DARK, Ink.SLOT_DARK, 1, 4, 0))
	slider.add_theme_stylebox_override("grabber_area", UiKit.box(Ink.INK, Ink.INK, 0, 4, 0))
	slider.add_theme_stylebox_override("grabber_area_highlight", UiKit.box(Ink.INK, Ink.INK, 0, 4, 0))
	row.add_child(slider)

	var readout := UiKit.body("%d%%" % int(value * 100.0), 13, Ink.INK)
	readout.custom_minimum_size.x = 46
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)

	slider.value_changed.connect(func(v: float):
		readout.text = "%d%%" % int(v * 100.0)
		on_change.call(v))
	return row
