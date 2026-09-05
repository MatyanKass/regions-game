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

# Buttons are paper tiles that press in: the border darkens and the fill sinks a shade,
# which is enough feedback on a phone without any animation.
static func button(node: Button, accent: Color = Ink.INK, filled: bool = false) -> void:
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
