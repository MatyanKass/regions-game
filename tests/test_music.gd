# The music loader. Cheap to test and easy to get wrong: the project folder lists both
# a track and its .import sidecar, so a naive loader plays everything twice.
extends RefCounted

var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func test_each_track_is_loaded_once() -> void:
	var music = load("res://src/ui/music.gd").new()
	for mood in ["calm", "combat"]:
		var path := "res://assets/music/%s" % mood
		var streams: Array = music.load_folder(path)
		expect(not streams.is_empty(), "no %s track was found in %s" % [mood, path])
		var paths: Dictionary = {}
		for stream in streams:
			var key := str(stream.resource_path)
			expect(not paths.has(key), "%s was loaded twice" % key)
			paths[key] = true
		for stream in streams:
			expect(stream is AudioStream, "a loaded %s track is not audio" % mood)
	music.free()

func test_missing_folder_is_silence_not_a_crash() -> void:
	var music = load("res://src/ui/music.gd").new()
	expect((music.load_folder("res://assets/music/nope") as Array).is_empty(),
		"a folder that does not exist must simply yield no tracks")
	music.free()
