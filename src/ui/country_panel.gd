# Copyright (c) 2026 MatyanKass. All rights reserved.
# Where you are playing from. Asked once, on the first run, and changeable from the
# lobby afterwards.
#
# A region is a palette rather than a colour: Africa is yellow, orange and red, and which
# of them your cells end up in is rolled when the match starts - so two people from the
# same continent still get their own pen.
class_name CountryPanel
extends PanelContainer

signal chosen(region: int)
signal closed

const SWATCH := 14.0

# The three colours of a region, drawn as ink dots: the palette is the whole of what the
# choice means, so it has to be on the button rather than in a description of it.
class Swatch:
	extends Control
	var colours: Array = []
	func _init(palette: Array) -> void:
		colours = palette
		custom_minimum_size = Vector2(SWATCH * palette.size() + 6, SWATCH + 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in range(colours.size()):
			var centre := Vector2(SWATCH * 0.5 + i * SWATCH, size.y * 0.5)
			draw_circle(centre, SWATCH * 0.42, Regions.colour_to_ink(int(colours[i])))
			draw_arc(centre, SWATCH * 0.42, 0, TAU, 16, Ink.INK, 1.0)

func _init() -> void:
	UiKit.panel(self)
	custom_minimum_size = Vector2(430, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := UiKit.heading(I18n.t("pick_country"), 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var hint := UiKit.body(I18n.t("pick_country_hint"), 12, Ink.INK_SOFT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for region in range(Regions.count()):
		grid.add_child(_region_button(region))

	var close := Button.new()
	close.text = I18n.t("cancel")
	close.custom_minimum_size.y = 38
	UiKit.button(close)
	close.pressed.connect(func(): emit_signal("closed"))
	box.add_child(close)

# by MatyanKass
func _region_button(region: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The palette's first colour is the accent, so the row is in the ink it offers.
	var accent := Regions.colour_to_ink(int(Regions.palette(region)[0]))
	UiKit.button(button, accent, Prefs.region() == region)
	button.pressed.connect(func():
		Prefs.set_region(region)
		emit_signal("chosen", region))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.offset_left = 10
	row.offset_right = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UiKit.body(Regions.name_of(region), 15,
		Color.WHITE if Prefs.region() == region else Ink.INK)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var swatch := Swatch.new(Regions.palette(region))
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	button.add_child(row)
	return button
