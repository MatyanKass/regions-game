# What opens when you tap one of your own buildings: what it is, what it gives at this
# level, and the two things you can do with it - upgrade or demolish. A port also gets
# its ship button here, because that is where a player looks for it.
class_name CellMenu
extends PanelContainer

signal upgrade_requested
signal demolish_requested
signal ship_requested
signal closed

var _icon: UiKit.Glyph
var _title: Label
var _detail: Label
var _upgrade: Button
var _demolish: Button
var _ship: Button

func _init() -> void:
	UiKit.panel(self)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_icon = UiKit.glyph_for_building(Balance.Building.HOUSE, 44)
	header.add_child(_icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = UiKit.heading("", 19)
	titles.add_child(_title)
	_detail = UiKit.body("", 13, Ink.INK_SOFT)
	titles.add_child(_detail)
	header.add_child(titles)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 32)
	UiKit.button(close)
	close.pressed.connect(func(): emit_signal("closed"))
	header.add_child(close)
	column.add_child(header)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)

	_ship = Button.new()
	_ship.custom_minimum_size.y = 42
	UiKit.button(_ship)
	_ship.pressed.connect(func(): emit_signal("ship_requested"))
	actions.add_child(_ship)

	_upgrade = Button.new()
	_upgrade.custom_minimum_size.y = 42
	UiKit.button(_upgrade, Ink.INK, true)
	_upgrade.pressed.connect(func(): emit_signal("upgrade_requested"))
	actions.add_child(_upgrade)

	_demolish = Button.new()
	_demolish.custom_minimum_size.y = 42
	UiKit.button(_demolish, Ink.PENS[1])
	_demolish.pressed.connect(func(): emit_signal("demolish_requested"))
	actions.add_child(_demolish)

func show_cell(state: GameState, player: int, cell: int) -> void:
	var type := int(state.building_at[cell])
	if type == Balance.Building.NONE:
		return
	var level := maxi(1, int(state.level_at[cell]))
	var max_level := Balance.max_level_of(type)

	_icon.building_type = type
	_icon.queue_redraw()
	_title.text = I18n.building_name(type)
	_detail.text = "%s %d/%d   %s" % [I18n.t("level"), level, max_level, _effect_text(type, level)]

	_ship.visible = type == Balance.Building.PORT
	_ship.text = I18n.t("send_ship")

	if level >= max_level:
		_upgrade.disabled = true
		_upgrade.text = I18n.t("max_level_reached")
	else:
		var next_level := level + 1
		var coin_cost := Balance.upgrade_coin_cost(type, next_level)
		var power_cost := Balance.upgrade_power_cost(type, next_level)
		_upgrade.disabled = int(state.coins[player]) < coin_cost \
			or int(state.power[player]) < power_cost
		_upgrade.text = "%s %d  ·  %s" % [
			I18n.t("upgrade_to"), next_level, BuildMenu.price_text(type, next_level)]

	var refund := Balance.invested_coins(type, level) * Balance.DEMOLISH_REFUND_PERCENT / 100
	_demolish.text = "%s  ·  +%d" % [I18n.t("demolish"), refund / Balance.UNIT]

# One line saying what this building is doing right now, at this level.
static func _effect_text(type: int, level: int) -> String:
	var d: Dictionary = Balance.BUILDINGS[type]
	var per_second := float(Balance.TICKS_PER_SECOND) / float(Balance.UNIT)
	var parts: Array[String] = []
	if int(d["coin_per_tick"]) > 0:
		parts.append("+%.1f/%s" % [int(d["coin_per_tick"]) * level * per_second, I18n.t("second")])
	if int(d["power_per_tick"]) > 0:
		parts.append("+%.1f/%s" % [int(d["power_per_tick"]) * level * per_second, I18n.t("second")])
	if int(d["coin_cap"]) > 0:
		parts.append("+%d %s" % [int(d["coin_cap"]) * level / Balance.UNIT, I18n.t("cap")])
	if int(d["power_cap"]) > 0:
		parts.append("+%d %s" % [int(d["power_cap"]) * level / Balance.UNIT, I18n.t("cap")])
	if int(d["people"]) > 0:
		parts.append("+%d %s" % [int(d["people"]) * level, I18n.t("people")])
	if type == Balance.Building.BARRIER:
		parts.append("%d %s" % [Balance.BARRIER_COOLDOWN_TICKS / Balance.TICKS_PER_SECOND,
			I18n.t("barrier_stall")])
	return "  ".join(parts)
