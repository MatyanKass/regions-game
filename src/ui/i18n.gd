# Two-language UI text. Small enough not to need Godot translation resources, and this
# way every string the player can see is visible in one file.
class_name I18n
extends RefCounted

static var language := "ru"

const STRINGS := {
	"app_title": {"ru": "Regions", "en": "Regions"},
	"host_game": {"ru": "Создать комнату", "en": "Host a room"},
	"rooms": {"ru": "Комнаты в сети", "en": "Rooms on the network"},
	"searching": {"ru": "Идёт поиск комнат…", "en": "Looking for rooms…"},
	"no_rooms": {"ru": "Комнат не найдено", "en": "No rooms found"},
	"join": {"ru": "Войти", "en": "Join"},
	"join_by_ip": {"ru": "Подключиться по адресу", "en": "Connect by address"},
	"waiting_player": {"ru": "Ждём второго игрока…", "en": "Waiting for the second player…"},
	"cancel": {"ru": "Отмена", "en": "Cancel"},
	"language": {"ru": "English", "en": "Русский"},
	"connecting": {"ru": "Подключение…", "en": "Connecting…"},
	"connect_failed": {"ru": "Не удалось подключиться", "en": "Could not connect"},
	"host_closed": {"ru": "Хост закрыл соединение", "en": "The host closed the connection"},
	"opponent_lost": {"ru": "У игрока %s прервалось соединение", "en": "Player %s lost connection"},
	"keep_waiting": {"ru": "Подождать", "en": "Keep waiting"},
	"end_match": {"ru": "Завершить матч", "en": "End the match"},
	"paused": {"ru": "Пауза", "en": "Paused"},
	"resume": {"ru": "Продолжить", "en": "Resume"},
	"leave": {"ru": "Выйти", "en": "Leave"},
	"build": {"ru": "Построить", "en": "Build"},
	"demolish": {"ru": "Снести", "en": "Demolish"},
	"capture": {"ru": "Захватить", "en": "Capture"},
	"send_ship": {"ru": "Отправить корабль", "en": "Send a ship"},
	"pick_target": {"ru": "Выберите клетку на другом берегу", "en": "Pick a cell on the far shore"},
	"you": {"ru": "Вы", "en": "You"},
	"opponent": {"ru": "Противник", "en": "Opponent"},
	"cells": {"ru": "Клетки", "en": "Cells"},
	"income": {"ru": "Доход", "en": "Income"},
	"look_here": {"ru": "Смотрит сюда", "en": "Looking here"},
	"victory": {"ru": "Победа", "en": "Victory"},
	"defeat": {"ru": "Поражение", "en": "Defeat"},
	"draw": {"ru": "Ничья", "en": "Draw"},
	"back_to_menu": {"ru": "В меню", "en": "Back to menu"},
	"time_left": {"ru": "Осталось", "en": "Time left"},
	"hint_tap": {"ru": "Тап по своей клетке — постройка, двойной тап по соседней — захват",
		"en": "Tap your cell to build, double-tap a bordering cell to capture"},

	# Buildings
	"b_factory": {"ru": "Завод", "en": "Factory"},
	"b_house": {"ru": "Дом", "en": "House"},
	"b_bank": {"ru": "Банк", "en": "Bank"},
	"b_barracks": {"ru": "Казарма", "en": "Barracks"},
	"b_military_base": {"ru": "Военная база", "en": "Military base"},
	"b_port": {"ru": "Порт", "en": "Port"},

	# Refusal reasons produced by the simulation
	"e_not_enough_coins": {"ru": "Не хватает монет", "en": "Not enough coins"},
	"e_not_enough_power": {"ru": "Не хватает очков силы", "en": "Not enough power"},
	"e_not_enough_people": {"ru": "Не хватает людей", "en": "Not enough people"},
	"e_needs_coast": {"ru": "Порт строится только у моря", "en": "A port must touch the sea"},
	"e_cell_occupied": {"ru": "Клетка уже занята", "en": "The cell is already built up"},
	"e_not_your_cell": {"ru": "Это не ваша клетка", "en": "That is not your cell"},
	"e_not_adjacent": {"ru": "Клетка не граничит с вашей", "en": "That cell does not border yours"},
	"e_sea_cell": {"ru": "На море строить нельзя", "en": "You cannot build on water"},
	"e_no_sea_route": {"ru": "Нет прямого морского пути", "en": "No straight sea route"},
	"e_port_busy": {"ru": "Корабль этого порта уже в пути", "en": "This port already has a ship at sea"},
	"e_already_yours": {"ru": "Клетка уже ваша", "en": "The cell is already yours"},
	"e_nothing_to_demolish": {"ru": "Сносить нечего", "en": "Nothing to demolish"},
	"e_match_finished": {"ru": "Матч окончен", "en": "The match is over"},
	"e_no_port": {"ru": "Здесь нет порта", "en": "There is no port here"},
}

static func detect_language() -> void:
	language = "ru" if OS.get_locale_language() == "ru" else "en"

static func toggle() -> void:
	language = "en" if language == "ru" else "ru"

static func t(key: String) -> String:
	if not STRINGS.has(key):
		return key
	return STRINGS[key].get(language, key)

static func building_name(type: int) -> String:
	if not Balance.BUILDINGS.has(type):
		return ""
	return t("b_" + str(Balance.BUILDINGS[type]["name"]))

# Simulation refusals come back as bare codes so the sim never depends on the UI.
static func reason(code: String) -> String:
	if code.is_empty():
		return ""
	return t("e_" + code)
