# Saving and loading a world.
#
# A save is the simulation's own snapshot - the same thing the host sends a client that
# has drifted - plus enough about the match to put it back the way it was. Reusing the
# snapshot means there is one definition of "the whole state" rather than two that can
# fall out of step.
#
# Only worlds with one player at the keyboard can be saved: free play and a match against
# the bot. Saving one side of a game against another phone would be saving half of it.
class_name SaveGame
extends RefCounted

const DIR := "user://saves"
const SUFFIX := ".save"
const VERSION := 1
const MAX_SLOTS := 12
const AUTOSAVE := "autosave"

# Writes the world under `slot`, replacing whatever was there. Returns "" on success or
# a reason the interface can show.
static func store(slot: String, label: String, state: GameState, bot_level: int) -> String:
	if state == null:
		return "nothing_to_save"
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(_path(slot), FileAccess.WRITE)
	if file == null:
		return "could_not_write"
	file.store_var({
		"version": VERSION,
		"label": label,
		"saved_at": int(Time.get_unix_time_from_system()),
		"bot_level": bot_level,
		"settings": state.settings.to_dict() if state.settings != null else {},
		"state": state.snapshot(),
	}, false)
	file.close()
	return ""

# Everything about a save except the world itself, for listing them without paying to
# read a million cells back.
static func describe(slot: String) -> Dictionary:
	var data := _read(slot)
	if data.is_empty():
		return {}
	var settings := WorldSettings.from_dict(data.get("settings", {}))
	var snapshot: Dictionary = data.get("state", {})
	return {
		"slot": slot,
		"label": str(data.get("label", slot)),
		"saved_at": int(data.get("saved_at", 0)),
		"bot_level": int(data.get("bot_level", -1)),
		"width": settings.width,
		"height": settings.height,
		"free_play": settings.mode == WorldSettings.Mode.FREE,
		"ticks": int(snapshot.get("tick", 0)),
	}

static func load_state(slot: String) -> GameState:
	var data := _read(slot)
	if data.is_empty():
		return null
	var snapshot: Dictionary = data.get("state", {})
	if snapshot.is_empty():
		return null
	return GameState.from_snapshot(snapshot)

static func bot_level_of(slot: String) -> int:
	var data := _read(slot)
	return int(data.get("bot_level", -1)) if not data.is_empty() else -1

# Newest first, which is the order somebody looking for "the one I was just playing"
# expects.
static func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(SUFFIX):
			continue
		var described := describe(file.trim_suffix(SUFFIX))
		if not described.is_empty():
			out.append(described)
	out.sort_custom(func(a, b): return int(a["saved_at"]) > int(b["saved_at"]))
	return out

static func erase(slot: String) -> void:
	DirAccess.remove_absolute(_path(slot))

static func exists(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))

# A file name that cannot escape the saves folder, whatever the player typed. Latin
# letters and digits survive so the file is recognisable; everything else - Cyrillic,
# spaces, anything a path would object to - becomes an underscore, and a hash of the
# original keeps two different names from landing in the same slot.
static func slot_for(label: String) -> String:
	var cleaned := label.strip_edges()
	if cleaned.is_empty():
		cleaned = "world"
	var slug := ""
	for character in cleaned.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slug += character
		else:
			slug += "_"
	return "%s_%d" % [slug.substr(0, 24), absi(hash(cleaned)) % 100000]

static func _path(slot: String) -> String:
	return "%s/%s%s" % [DIR, slot, SUFFIX]

static func _read(slot: String) -> Dictionary:
	var file := FileAccess.open(_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var data = file.get_var(false)
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if int((data as Dictionary).get("version", 0)) != VERSION:
		return {}
	return data
