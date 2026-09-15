# Copyright (c) 2026 MatyanKass. All rights reserved.
# Shared interface pieces, so every panel and button in the game is cut from the same
# cloth instead of each screen inventing its own look.
#
# The whole style is "ink on paper": warm paper panels, a dark ink outline, and icons
# drawn with the same line primitives as the buildings on the map.
class_name UiKit
extends RefCounted

const RADIUS := 8
const BORDER := 2

# A control that draws one Ink glyph and nothing else. Used for building icons in menus
# and for the icons on the mode buttons.
class Glyph:
	extends Control
	var building_type := -1
	var icon := -1
	var color := Ink.INK
	var line_width := 3.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if building_type >= 0:
			Ink.draw_building(self, building_type, r, color, line_width)
		elif icon >= 0:
			Ink.draw_icon(self, icon, r, color, line_width)

	func set_colour(value: Color) -> void:
		color = value
		queue_redraw()

static func glyph_for_building(type: int, px: float, colour: Color = Ink.INK) -> Glyph:
	var g := Glyph.new()
	g.building_type = type
	g.color = colour
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

static func glyph_for_icon(icon: int, px: float, colour: Color = Ink.INK) -> Glyph:
	var g := Glyph.new()
	g.icon = icon
	g.color = colour
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

# --- Boxes ------------------------------------------------------------------------

# by MatyanKass
static func box(bg: Color, border: Color, width: int = BORDER, radius: int = RADIUS,
		margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

static func panel(node: Control, bg: Color = Ink.PAPER_PANEL) -> void:
	node.add_theme_stylebox_override("panel", box(bg, Ink.INK))

# by MatyanKass
# Buttons are paper tiles that press in: the border darkens and the fill sinks a shade,
# which is enough feedback on a phone without any animation.
static func button(node: Button, accent: Color = Ink.INK, filled: bool = false) -> void:
	# Connected here rather than at every call site, so no button can be built without
	# its click. `button()` is also called again to restyle a button, hence the guard.
	if not node.pressed.is_connected(_click):
		node.pressed.connect(_click)
	var bg := accent if filled else Ink.PAPER_PANEL
	var fg := Ink.PAPER if filled else Ink.INK
	node.add_theme_stylebox_override("normal", box(bg, accent, BORDER, RADIUS, 10))
	node.add_theme_stylebox_override("hover", box(bg.lightened(0.06), accent, BORDER, RADIUS, 10))
	node.add_theme_stylebox_override("pressed", box(bg.darkened(0.12), accent, BORDER + 1, RADIUS, 10))
	node.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, RADIUS, 10))
	node.add_theme_stylebox_override("disabled",
		box(Ink.PAPER_DARK, Ink.SLOT_DARK, BORDER, RADIUS, 10))
	node.add_theme_color_override("font_color", fg)
	node.add_theme_color_override("font_hover_color", fg)
	node.add_theme_color_override("font_pressed_color", fg)
	node.add_theme_color_override("font_disabled_color", Ink.INK_SOFT)

static func _click() -> void:
	Sfx.play("tap")

# Text fields and dropdowns get the same paper treatment as buttons, or they stand out
# as the one part of the screen the engine styled instead of us.
static func line_edit(node: LineEdit) -> void:
	node.add_theme_stylebox_override("normal", box(Ink.PAPER_PANEL, Ink.SLOT_DARK, BORDER, RADIUS, 10))
	node.add_theme_stylebox_override("focus", box(Ink.PAPER_PANEL, Ink.INK, BORDER, RADIUS, 10))
	node.add_theme_color_override("font_color", Ink.INK)
	node.add_theme_color_override("font_placeholder_color", Ink.INK_SOFT)
	node.add_theme_color_override("caret_color", Ink.INK)

static func option(node: OptionButton) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		node.add_theme_stylebox_override(state, box(Ink.PAPER_PANEL, Ink.INK, BORDER, RADIUS, 10))
	node.add_theme_color_override("font_color", Ink.INK)
	node.add_theme_color_override("font_hover_color", Ink.INK)
	node.add_theme_color_override("font_pressed_color", Ink.INK)
	node.add_theme_color_override("font_focus_color", Ink.INK)
	var popup := node.get_popup()
	popup.add_theme_stylebox_override("panel", box(Ink.PAPER_PANEL, Ink.INK, BORDER, RADIUS, 6))
	popup.add_theme_color_override("font_color", Ink.INK)
	popup.add_theme_color_override("font_hover_color", Ink.PAPER)
	popup.add_theme_stylebox_override("hover", box(Ink.INK, Ink.INK, 0, 4, 4))

# The page the whole interface sits on: paper, printed squares and the red margin rule,
# so a menu looks like the same notebook the match is played in.
class Paper:
	extends Control
	const SQUARE := 34.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Ink.PAPER, true)
		var columns := int(size.x / SQUARE) + 1
		var rows := int(size.y / SQUARE) + 1
		for i in range(columns):
			var x := i * SQUARE
			draw_line(Vector2(x, 0), Vector2(x, size.y), Ink.GRID, 1.2)
		for i in range(rows):
			var y := i * SQUARE
			draw_line(Vector2(0, y), Vector2(size.x, y), Ink.GRID, 1.2)
		var margin_x := SQUARE * 2.0
		Ink.line(self, Vector2(margin_x, 0), Vector2(margin_x, size.y), Ink.MARGIN, 2.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

# A pen stroke under a heading, drawn rather than typed.
class Underline:
	extends Control
	var colour := Ink.INK

	func _draw() -> void:
		Ink.line(self, Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), colour, 3.0)

static func heading(text: String, px: int = 20, colour: Color = Ink.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", colour)
	return label

static func body(text: String, px: int = 15, colour: Color = Ink.INK) -> Label:
	return heading(text, px, colour)

# --- Resource chip: icon, then value, then the rate underneath ---------------------

class Chip:
	extends HBoxContainer
	var value_label: Label
	var rate_label: Label

	func setup(icon: int, colour: Color) -> void:
		add_theme_constant_override("separation", 7)
		add_child(UiKit.glyph_for_icon(icon, 22, colour))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		add_child(column)
		value_label = UiKit.heading("", 17)
		column.add_child(value_label)
		rate_label = UiKit.body("", 12, Ink.INK_SOFT)
		column.add_child(rate_label)

	func set_values(value: String, rate: String) -> void:
		value_label.text = value
		rate_label.text = rate

static func chip(icon: int, colour: Color = Ink.INK) -> Chip:
	var c := Chip.new()
	c.setup(icon, colour)
	return c
