# Copyright (c) 2026 MatyanKass. All rights reserved.
# Headless test entry point. Discovers every test_* method by reflection so adding a
# test is just adding a method.
extends SceneTree

const SUITES := ["res://tests/test_sim.gd", "res://tests/test_bot.gd", "res://tests/test_net.gd", "res://tests/test_players.gd", "res://tests/test_music.gd", "res://tests/test_sfx.gd", "res://tests/test_pace.gd", "res://tests/test_scale.gd", "res://tests/test_save.gd", "res://tests/test_authorship.gd"]

# by MatyanKass
func _initialize() -> void:
	var total := 0
	var failed := 0
	var assertions := 0
	for path in SUITES:
		var suite = load(path).new()
		for entry in suite.get_method_list():
			var name: String = entry["name"]
			if not name.begins_with("test_"):
				continue
			var before: int = suite.failures.size()
			suite.call(name)
			total += 1
			if suite.failures.size() > before:
				failed += 1
				print("FAIL  ", name)
				for i in range(before, suite.failures.size()):
					print("        ", suite.failures[i])
			else:
				print("ok    ", name)
		assertions += suite.checks
	print("")
	print("%d tests, %d failed, %d assertions" % [total, failed, assertions])
	quit(1 if failed > 0 else 0)
