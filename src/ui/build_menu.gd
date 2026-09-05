# The build menu: a grid of slots, the way an inventory chest looks. Each slot shows the
# pen glyph of the building, its price, and greys out with the reason when it cannot go
# on this particular cell - so the rules are learned from the menu itself.
class_name BuildMenu
extends PanelContainer

signal picked(type: int)
signal closed

const SLOT_SIZE := Vector2(108, 122)
const ORDER := [
	Balance.Building.HOUSE, Balance.Building.FACTORY, Balance.Building.BANK,
	Balance.Building.BARRACKS, Balance.Building.MILITARY_BASE, Balance.Building.PORT,
	Balance.Building.BARRIER,
]

var _slots: Dictionary = {}     # building type -> Button
var _captions: Dictionary = {}  # building type -> Label

func _init() -> void:
	UiKit.panel(self)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var header := HBoxContainer.new()
	var title := UiKit.heading(I18n.t("build"), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 32)
	UiKit.button(close)
	close.pressed.connect(func(): emit_signal("closed"))
	header.add_child(close)
	column.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for type in ORDER:
		grid.add_child(_make_slot(type))

func _make_slot(type: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.tooltip_text = I18n.building_name(type)
	UiKit.button(slot)
	slot.pressed.connect(func(): emit_signal("picked", type))

	var icon := UiKit.glyph_for_building(type, 48)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 26
	icon.offset_right = -26
	icon.offset_top = 10
	icon.offset_bottom = -46
	slot.add_child(icon)

	var caption := UiKit.body("", 13)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -44
	caption.text = "%s\n%s" % [I18n.building_name(type), price_text(type, 1)]
	slot.add_child(caption)

	_slots[type] = slot
	_captions[type] = caption
	return slot

static func price_text(type: int, level: int) -> String:
	var coins := Balance.upgrade_coin_cost(type, level) / Balance.UNIT
	var power := Balance.upgrade_power_cost(type, level) / Balance.UNIT
	if power > 0:
		return "%d / %d" % [coins, power]
	return str(coins)

# Greys out whatever the player cannot afford or place on this particular cell, and says
# why in the tooltip.
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
		slot.tooltip_text = I18n.building_name(type)
		if not blocked.is_empty():
			slot.tooltip_text += " — " + I18n.reason(blocked)
		(_captions[type] as Label).add_theme_color_override("font_color",
			Ink.INK_SOFT if slot.disabled else Ink.INK)
