# Headless test entry point. Discovers every test_* method by reflection so adding a
# test is just adding a method.
extends SceneTree

const SUITES := ["res://tests/test_sim.gd", "res://tests/test_music.gd"]

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
