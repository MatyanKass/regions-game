# Copyright (c) 2026 MatyanKass. All rights reserved.
# Two-language UI text. Small enough not to need Godot translation resources, and this
# way every string the player can see is visible in one file.
class_name I18n
extends RefCounted

static var language := "ru"

const STRINGS := {
	"app_title": {"ru": "Regions", "en": "Regions"},
	# The game is called "Regions :Beta Edition" - the second half sits under the title
	# as a badge rather than in it, because at 54 points the whole name is wider than a
	# phone held upright.
	"edition": {"ru": ":Beta Edition", "en": ":Beta Edition"},
	"host_game": {"ru": "Создать комнату", "en": "Host a room"},
	"free_play": {"ru": "Свободная игра", "en": "Free play"},
	"world": {"ru": "Мир", "en": "World"},
	"map_size": {"ru": "Размер карты", "en": "Map size"},
	"sea": {"ru": "Море", "en": "Sea"},
	"sea_random": {"ru": "как выйдет", "en": "as it comes"},
	"match_length": {"ru": "Длина партии", "en": "Match length"},
	"minutes": {"ru": "мин", "en": "min"},
	"cells_count": {"ru": "клеток", "en": "cells"},
	"free_play_hint": {"ru": "Открытый мир без противника: ни победы, ни поражения, ни таймера.",
		"en": "An open world with nobody in it: no winning, no losing, no clock."},
	"huge_world_hint": {"ru": "Большой мир: генерация займёт пару секунд, и бот на нём думает медленнее. Для свободной игры — то что надо.",
		"en": "A big world: it takes a couple of seconds to make, and the bot thinks more slowly on it. Ideal for free play."},
	"tagline": {"ru": "Клеточная стратегия на двоих. Строй, копи силу, забирай клетки.",
		"en": "A grid strategy for two. Build up, save power, take ground."},
	"rooms": {"ru": "Комнаты в сети", "en": "Rooms on the network"},
	"room_code": {"ru": "Код комнаты", "en": "Room code"},
	"players_in_room": {"ru": "Игроки", "en": "Players"},
	"room_size": {"ru": "Мест в комнате", "en": "Seats"},
	"start_match": {"ru": "Начать матч", "en": "Start the match"},
	"waiting_host": {"ru": "Ждём, пока хост начнёт", "en": "Waiting for the host to start"},
	"in_room": {"ru": "Вы в комнате", "en": "You are in the room"},
	"room_full": {"ru": "Комната уже заполнена", "en": "That room is full"},
	"need_two": {"ru": "Нужен хотя бы ещё один игрок", "en": "At least one more player is needed"},
	"player": {"ru": "Игрок", "en": "Player"},
	"player_gone": {"ru": "вышел из игры", "en": "has left the game"},
	"player_left_toast": {"ru": "%s вышел", "en": "%s has left"},
	"joining": {"ru": "заходит…", "en": "joining…"},
	"crowded_hint": {"ru": "Много игроков на маленькой карте — стартовые клетки будут рядом. Возьми карту побольше.",
		"en": "That many players on a small map start close together. Take a bigger one."},

	# Where a player is playing from. The choice is a palette, not a colour: which of a
	# region's colours you get is rolled when the match starts.
	"country": {"ru": "Страна", "en": "Country"},
	"pick_country": {"ru": "Откуда играешь?", "en": "Where are you playing from?"},
	"pick_country_hint": {"ru": "Цвет твоих клеток берётся из палитры региона",
		"en": "Your cells take their colour from the region's palette"},
	"region_any": {"ru": "Не выбрано", "en": "Not chosen"},
	"region_africa": {"ru": "Африка", "en": "Africa"},
	"region_europe": {"ru": "Европа", "en": "Europe"},
	"region_asia": {"ru": "Азия", "en": "Asia"},
	"region_middle_east": {"ru": "Ближний Восток", "en": "Middle East"},
	"region_latin_america": {"ru": "Латинская Америка", "en": "Latin America"},
	"region_north_america": {"ru": "Северная Америка", "en": "North America"},
	"region_nordic": {"ru": "Скандинавия", "en": "Nordics"},
	"region_oceania": {"ru": "Океания", "en": "Oceania"},
	"code_hint": {"ru": "Продиктуй его второму игроку — он вводит код ниже",
		"en": "Read it out to the other player; they type it in below"},
	"code_or_address": {"ru": "Код комнаты или адрес", "en": "Room code or address"},
	"bad_code": {"ru": "Неверный код — проверь символы", "en": "That code is not right - check the characters"},
	"no_answer": {"ru": "По этому коду никто не ответил", "en": "Nobody answered on that code"},
	"port_busy": {"ru": "Порт занят: закрой прошлую игру и попробуй снова",
		"en": "The port is busy: close the previous game and try again"},
	"no_address": {"ru": "Нет сети: подключись к Wi-Fi", "en": "No network: join a Wi-Fi first"},
	"stop_hosting": {"ru": "Отменить комнату", "en": "Stop hosting"},
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
	"practice": {"ru": "Игра с ботом", "en": "Play against a bot"},
	"difficulty": {"ru": "Сложность", "en": "Difficulty"},
	"bot_easy": {"ru": "Лёгкий", "en": "Easy"},
	"bot_normal": {"ru": "Обычный", "en": "Normal"},
	"bot_hard": {"ru": "Сложный", "en": "Hard"},
	"bot": {"ru": "Бот", "en": "Bot"},
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

	# Action modes: the three buttons along the bottom of the match screen
	"mode_build": {"ru": "Стройка", "en": "Build"},
	"mode_attack": {"ru": "Атака", "en": "Attack"},
	"mode_info": {"ru": "Инфо", "en": "Info"},
	"hint_build": {"ru": "Тап по своей клетке — построить, по зданию — улучшить или снести",
		"en": "Tap your cell to build, tap a building to upgrade or demolish"},
	"hint_attack": {"ru": "Тап по соседней клетке — захват за 10 силы",
		"en": "Tap a bordering cell to take it for 10 power"},
	"hint_info": {"ru": "Тап по клетке — кто ей владеет и как идут его дела",
		"en": "Tap a cell to see who owns it and how they are doing"},
	"level": {"ru": "Уровень", "en": "Level"},
	"upgrade_to": {"ru": "Улучшить до", "en": "Upgrade to"},
	"max_level_reached": {"ru": "Максимальный уровень", "en": "Fully upgraded"},
	"second": {"ru": "с", "en": "s"},
	"cap": {"ru": "к лимиту", "en": "storage"},
	"people": {"ru": "жителей", "en": "residents"},
	"barrier_stall": {"ru": "с задержки захвата у врага", "en": "s of stalled enemy captures"},
	"cooldown": {"ru": "Перезарядка", "en": "Cooldown"},
	"menu": {"ru": "Меню", "en": "Menu"},
	"nickname": {"ru": "Ник", "en": "Nickname"},
	"nickname_hint": {"ru": "Так вас увидят в списке комнат и в матче.",
		"en": "This is what others see in the room list and in a match."},
	"save_game": {"ru": "Сохранить", "en": "Save"},
	"saved": {"ru": "Сохранено", "en": "Saved"},
	"saves": {"ru": "Сохранённые миры", "en": "Saved worlds"},
	"no_saves": {"ru": "Пока ничего не сохранено", "en": "Nothing saved yet"},
	"delete": {"ru": "Удалить", "en": "Delete"},
	"save_name": {"ru": "Название мира", "en": "Name of the world"},
	"cannot_save_online": {"ru": "Сетевую партию сохранить нельзя",
		"en": "A match against another phone cannot be saved"},
	"e_nothing_to_save": {"ru": "Сохранять нечего", "en": "Nothing to save"},
	"e_could_not_write": {"ru": "Не удалось записать файл", "en": "Could not write the file"},
	"settings": {"ru": "Настройки", "en": "Settings"},
	"music_volume": {"ru": "Музыка", "en": "Music"},
	"sfx_volume": {"ru": "Звуки", "en": "Sound effects"},
	"language_label": {"ru": "Язык", "en": "Language"},
	"language_note": {"ru": "Выбор сохраняется и переживает перезапуск игры.",
		"en": "The choice is remembered and survives a restart."},
	"under_construction": {"ru": "Строится", "en": "Under construction"},
	"cancel_work": {"ru": "Отменить стройку", "en": "Call off the work"},
	"ready_in": {"ru": "готово через", "en": "ready in"},
	"idle": {"ru": "без рабочих", "en": "with no workers"},
	"overflowing": {"ru": "хранилище полно, теряется", "en": "storage full, losing"},
	"buildings": {"ru": "Здания", "en": "Buildings"},
	"played": {"ru": "Партия шла", "en": "Match lasted"},
	"ended_eliminated": {"ru": "Противник потерял последнюю клетку",
		"en": "The opponent lost their last cell"},
	"ended_time": {"ru": "Вышло время матча", "en": "The match ran out of time"},
	"idle_building": {"ru": "Стоит без рабочих", "en": "Standing idle: nobody to work it"},
	"neutral_land": {"ru": "Ничья земля", "en": "Open ground"},
	"empty_cell": {"ru": "Пусто", "en": "Empty"},
	"your_cell": {"ru": "Ваша клетка", "en": "Your cell"},
	"power_rate": {"ru": "Сила", "en": "Power"},
	"coin_rate": {"ru": "Монеты", "en": "Coins"},

	# Buildings
	"b_factory": {"ru": "Завод", "en": "Factory"},
	"b_house": {"ru": "Дом", "en": "House"},
	"b_bank": {"ru": "Банк", "en": "Bank"},
	"b_barracks": {"ru": "Казарма", "en": "Barracks"},
	"b_military_base": {"ru": "Военная база", "en": "Military base"},
	"b_port": {"ru": "Порт", "en": "Port"},
	"b_barrier": {"ru": "Барьер", "en": "Barrier"},

	# Refusal reasons produced by the simulation
	"e_not_enough_coins": {"ru": "Не хватает монет", "en": "Not enough coins"},
	"e_not_enough_power": {"ru": "Не хватает очков силы", "en": "Not enough power"},
	"e_not_enough_people": {"ru": "Не хватает людей", "en": "Not enough people"},
	"e_needs_coast": {"ru": "Порт строится только у моря", "en": "A port must touch the sea"},
	"e_cell_occupied": {"ru": "Клетка уже занята", "en": "The cell is already built up"},
	"e_not_your_cell": {"ru": "Это не ваша клетка", "en": "That is not your cell"},
	"e_not_adjacent": {"ru": "Клетка не граничит с вашей", "en": "That cell does not border yours"},
	"e_sea_cell": {"ru": "На море строить нельзя", "en": "You cannot build on water"},
	"e_no_sea_route": {"ru": "Нет морского пути", "en": "No sea route"},
	"e_port_busy": {"ru": "Корабль этого порта уже в пути", "en": "This port already has a ship at sea"},
	"e_already_yours": {"ru": "Клетка уже ваша", "en": "The cell is already yours"},
	"e_nothing_to_demolish": {"ru": "Сносить нечего", "en": "Nothing to demolish"},
	"e_match_finished": {"ru": "Матч окончен", "en": "The match is over"},
	"e_no_port": {"ru": "Здесь нет порта", "en": "There is no port here"},
	"e_on_cooldown": {"ru": "Захват ещё перезаряжается", "en": "The capture is still reloading"},
	"e_max_level": {"ru": "Уже максимальный уровень", "en": "Already fully upgraded"},
	"e_nothing_to_upgrade": {"ru": "Улучшать нечего", "en": "Nothing to upgrade"},
}

# by MatyanKass
static func detect_language() -> void:
	language = "ru" if OS.get_locale_language() == "ru" else "en"

static func toggle() -> void:
	language = "en" if language == "ru" else "ru"

static func t(key: String) -> String:
	if not STRINGS.has(key):
		return key
	return STRINGS[key].get(language, key)

static func bot_level_name(level: int) -> String:
	if not BotPlayer.LEVELS.has(level):
		return ""
	return t("bot_" + str(BotPlayer.LEVELS[level]["name"]))

static func building_name(type: int) -> String:
	if not Balance.BUILDINGS.has(type):
		return ""
	return t("b_" + str(Balance.BUILDINGS[type]["name"]))

# by MatyanKass
# Simulation refusals come back as bare codes so the sim never depends on the UI.
static func reason(code: String) -> String:
	if code.is_empty():
		return ""
	return t("e_" + code)
