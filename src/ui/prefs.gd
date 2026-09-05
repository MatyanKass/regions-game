# Autoloaded as /root/Prefs. What the player chose about the game itself, as opposed to
# what they chose about a particular world: volumes and language.
#
# Music and effects each get their own audio bus, created here if the project does not
# already have one. That way a volume is one number set in one place rather than every
# player in the game having to be told about it.
extends Node

signal changed

const PATH := "user://settings.cfg"
const MUSIC_BUS := "Music"
const SFX_BUS := "Sfx"

var music_volume := 0.7
var sfx_volume := 0.9
var language := ""   # empty means "follow the system"

func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	load_now()

func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) >= 0:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, name)
	AudioServer.set_bus_send(index, "Master")

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply()
	save()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply()
	save()

func set_language(code: String) -> void:
	language = code
	I18n.language = code
	save()
	emit_signal("changed")

func _apply() -> void:
	_set_bus_volume(MUSIC_BUS, music_volume)
	_set_bus_volume(SFX_BUS, sfx_volume)
	emit_signal("changed")

# A slider at zero means silence, not "very quiet": linear_to_db(0) is minus infinity,
# which some drivers dislike, so the bus is muted outright instead.
func _set_bus_volume(name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))

func load_now() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		music_volume = clampf(float(file.get_value("audio", "music", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(file.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
		language = str(file.get_value("ui", "language", ""))
	if language.is_empty():
		I18n.detect_language()
		language = I18n.language
	else:
		I18n.language = language
	_apply()

func save() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "music", music_volume)
	file.set_value("audio", "sfx", sfx_volume)
	file.set_value("ui", "language", language)
	file.save(PATH)
