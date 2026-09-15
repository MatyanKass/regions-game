# Copyright (c) 2026 MatyanKass. All rights reserved.
# Saving and loading. A save is the simulation's own snapshot, so what this really tests
# is that a world put away and picked up again is the same world and keeps behaving like
# one - which is the only promise a save has to keep.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

const SLOT := "test_world"

func _cleanup() -> void:
	SaveGame.erase(SLOT)

# by MatyanKass
func test_a_saved_world_comes_back_the_same() -> void:
	_cleanup()
	var s := GameState.create(31, WorldSettings.free_play(40))
	s.coins[0] = 500 * Balance.UNIT
	var home := -1
	for i in range(s.owner_of.size()):
		if int(s.owner_of[i]) == 0:
			home = i
			break
	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.HOUSE))
	for i in range(40):
		s.tick()

	expect(SaveGame.store(SLOT, "Test world", s, -1).is_empty(), "saving should succeed")
	expect(SaveGame.exists(SLOT), "and leave a file behind")

	var back := SaveGame.load_state(SLOT)
	expect(back != null, "the world loads")
	if back == null:
		return
	expect(back.state_hash() == s.state_hash(), "a loaded world is the same world")
	expect(back.width == 40 and back.is_free_play(), "its settings came with it")
	expect(back.verify_totals().is_empty(), "and its totals are counted correctly")

	# The real promise: it does not merely look the same, it goes on the same way.
	for i in range(200):
		s.tick()
		back.tick()
	expect(back.state_hash() == s.state_hash(), "and it keeps running identically")
	_cleanup()

func test_work_in_progress_survives_being_saved() -> void:
	_cleanup()
	var s := GameState.create(7, WorldSettings.free_play(25))
	s.coins[0] = 500 * Balance.UNIT
	var home := -1
	for i in range(s.owner_of.size()):
		if int(s.owner_of[i]) == 0:
			home = i
			break
	s.apply_command(0, GameState.make_command(GameState.Command.BUILD, home, Balance.Building.BANK))
	for i in range(20):
		s.tick()
	SaveGame.store(SLOT, "Half built", s, -1)
	var back := SaveGame.load_state(SLOT)
	expect(back != null and back.site_index(home) >= 0, "the building site is still there")
	if back == null:
		return
	for i in range(Balance.build_ticks(Balance.Building.BANK)):
		s.tick()
		back.tick()
	expect(int(back.building_at[home]) == Balance.Building.BANK, "and finishes after loading")
	expect(back.state_hash() == s.state_hash(), "at the same moment as the world it came from")
	_cleanup()

func test_a_save_describes_itself_without_being_loaded() -> void:
	_cleanup()
	var s := GameState.create(5, WorldSettings.free_play(60))
	for i in range(100):
		s.tick()
	SaveGame.store(SLOT, "Мой мир", s, BotPlayer.Level.HARD)
	var described := SaveGame.describe(SLOT)
	expect(not described.is_empty(), "a save can be described")
	expect(str(described.get("label", "")) == "Мой мир", "the name is kept as typed")
	expect(int(described.get("width", 0)) == 60, "the size is in the description")
	expect(bool(described.get("free_play", false)), "so is the mode")
	expect(int(described.get("ticks", 0)) == 100, "and how far in it was")
	expect(int(described.get("bot_level", -1)) == BotPlayer.Level.HARD, "and the opponent")
	_cleanup()

func test_names_that_are_not_file_names_are_still_saved() -> void:
	# A name typed by a person can be Cyrillic, have spaces, or try to walk out of the
	# folder. None of that may reach the file system.
	var awkward := SaveGame.slot_for("../../мой мир!")
	expect(not awkward.contains("/") and not awkward.contains(".."),
		"a slot name must not be able to escape the folder: %s" % awkward)
	expect(SaveGame.slot_for("Мой мир") != SaveGame.slot_for("Другой мир"),
		"two different names must not collide in one slot")
	expect(SaveGame.slot_for("Alpha") == SaveGame.slot_for("Alpha"),
		"and the same name must always give the same slot")

# by MatyanKass
func test_listing_is_newest_first_and_deleting_works() -> void:
	SaveGame.erase("slot_a")
	SaveGame.erase("slot_b")
	var s := GameState.create(3, WorldSettings.free_play(25))
	SaveGame.store("slot_a", "A", s, -1)
	SaveGame.store("slot_b", "B", s, -1)
	var listed := SaveGame.list_saves()
	expect(listed.size() >= 2, "both saves are listed")
	for i in range(listed.size() - 1):
		expect(int(listed[i]["saved_at"]) >= int(listed[i + 1]["saved_at"]),
			"the list has to run newest first")
	SaveGame.erase("slot_a")
	expect(not SaveGame.exists("slot_a"), "deleting a save removes it")
	SaveGame.erase("slot_b")

func test_a_missing_save_is_nothing_rather_than_a_crash() -> void:
	expect(SaveGame.load_state("no_such_world") == null, "loading nothing gives nothing")
	expect(SaveGame.describe("no_such_world").is_empty(), "and describes as nothing")
