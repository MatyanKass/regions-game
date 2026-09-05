# The build menu: a grid of slots, the way an inventory chest looks. Each slot shows
# the pen glyph of the building, its price, and greys out with a reason when it cannot
# be built right now - so the player learns the rules from the menu itself.
class_name BuildMenu
extends PanelContainer

signal picked(type: int)
signal closed

const SLOT_SIZE := Vector2(104, 118)

var _grid: GridContainer
var _slots: Dictionary = {}   # building type -> Button

class GlyphIcon:
	extends Control
	var type := 0
	var color := Color.BLACK
	func _draw() -> void:
		Ink.draw_building(self, type, Rect2(Vector2.ZERO, size), color, 3.0)

func _init() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Ink.PANEL
	box.border_color = Ink.PANEL_DARK
	box.set_border_width_all(4)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(14)
	add_theme_stylebox_override("panel", box)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = I18n.t("build")
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(func(): emit_signal("closed"))
	header.add_child(close)
	column.add_child(header)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_grid)

	for type in [Balance.Building.HOUSE, Balance.Building.FACTORY, Balance.Building.BANK,
			Balance.Building.BARRACKS, Balance.Building.MILITARY_BASE, Balance.Building.PORT]:
		_grid.add_child(_make_slot(type))

# Slots are paper on a slate frame, the way an inventory grid reads: the glyph has to
# be dark ink on a light square or it disappears into the panel.
static func _slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	return box

func _make_slot(type: int) -> Button:
	var data: Dictionary = Balance.BUILDINGS[type]
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.add_theme_stylebox_override("normal", _slot_style(Ink.SLOT, Ink.SLOT_DARK))
	slot.add_theme_stylebox_override("hover", _slot_style(Ink.SLOT.lightened(0.08), Ink.INK))
	slot.add_theme_stylebox_override("pressed", _slot_style(Ink.SLOT.darkened(0.1), Ink.INK))
	slot.add_theme_stylebox_override("disabled", _slot_style(Ink.SLOT.darkened(0.05), Ink.SLOT_DARK))
	slot.tooltip_text = I18n.building_name(type)
	slot.pressed.connect(func(): emit_signal("picked", type))

	var icon := GlyphIcon.new()
	icon.type = type
	icon.color = Ink.INK
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 22
	icon.offset_right = -22
	icon.offset_top = 8
	icon.offset_bottom = -46
	slot.add_child(icon)

	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Ink.INK)
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -44
	caption.text = "%s\n%s" % [I18n.building_name(type), _price_text(data)]
	slot.add_child(caption)

	_slots[type] = slot
	return slot

static func _price_text(data: Dictionary) -> String:
	var coins := int(data["coin_cost"]) / Balance.UNIT
	var power := int(data["power_cost"]) / Balance.UNIT
	if power > 0:
		return "%d + %d" % [coins, power]
	return str(coins)

# Greys out whatever the player cannot afford or place on this particular cell.
func refresh(state: GameState, player: int, cell: int) -> void:
	var agg := state.aggregate(player)
	for type in _slots:
		var data: Dictionary = Balance.BUILDINGS[type]
		var slot: Button = _slots[type]
		var blocked := ""
		if int(state.coins[player]) < int(data["coin_cost"]):
			blocked = "not_enough_coins"
		elif int(state.power[player]) < int(data["power_cost"]):
			blocked = "not_enough_power"
		elif int(data["workers"]) > 0 and int(agg["free_people"]) < int(data["workers"]):
			blocked = "not_enough_people"
		elif bool(data["coastal"]) and not state.touches_sea(cell):
			blocked = "needs_coast"
		slot.disabled = not blocked.is_empty()
		slot.modulate = Ink.DISABLED if slot.disabled else Color.WHITE
		slot.tooltip_text = I18n.building_name(type)
		if not blocked.is_empty():
			slot.tooltip_text += " - " + I18n.reason(blocked)
