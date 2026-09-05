# Autoloaded as /root/Music. Plays a calm track while a player is building up and
# switches to a tense one the moment the two territories touch, crossfading between
# them so the change is felt rather than heard as a cut.
#
# Tracks are picked up from assets/music/calm and assets/music/combat at startup. With
# those folders empty the whole thing simply stays silent, which is why the game runs
# fine before any music has been chosen.
extends Node

const FADE_SECONDS := 1.6
const QUIET_DB := -40.0
const PLAY_DB := -8.0
const FOLDERS := {"calm": "res://assets/music/calm", "combat": "res://assets/music/combat"}

var _players: Dictionary = {}     # mood -> AudioStreamPlayer
var _tracks: Dictionary = {}      # mood -> Array[AudioStream]
var _mood := ""

func _ready() -> void:
	for mood in FOLDERS:
		_tracks[mood] = _load_folder(str(FOLDERS[mood]))
		var player := AudioStreamPlayer.new()
		player.volume_db = QUIET_DB
		player.bus = "Master"
		player.finished.connect(_on_finished.bind(str(mood)))
		add_child(player)
		_players[mood] = player

func _load_folder(path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	for file in dir.get_files():
		# Exported projects see the imported name, so the suffix has to be stripped.
		var clean := file.trim_suffix(".import")
		if not (clean.ends_with(".ogg") or clean.ends_with(".mp3") or clean.ends_with(".wav")):
			continue
		var stream = load(path + "/" + clean)
		if stream != null:
			found.append(stream)
	found.sort_custom(func(a, b): return str(a.resource_path) < str(b.resource_path))
	return found

func set_mood(mood: String) -> void:
	if mood == _mood or not _players.has(mood):
		return
	_mood = mood
	if (_tracks[mood] as Array).is_empty():
		return
	var player: AudioStreamPlayer = _players[mood]
	if not player.playing:
		player.stream = _pick(mood)
		player.play()

func stop() -> void:
	_mood = ""
	for mood in _players:
		(_players[mood] as AudioStreamPlayer).stop()

func _pick(mood: String) -> AudioStream:
	var list: Array = _tracks[mood]
	return list[randi() % list.size()]

func _on_finished(mood: String) -> void:
	if mood != _mood or (_tracks[mood] as Array).is_empty():
		return
	var player: AudioStreamPlayer = _players[mood]
	player.stream = _pick(mood)
	player.play()

func _process(delta: float) -> void:
	var step := (PLAY_DB - QUIET_DB) * delta / FADE_SECONDS
	for mood in _players:
		var player: AudioStreamPlayer = _players[mood]
		var target := PLAY_DB if mood == _mood else QUIET_DB
		if is_equal_approx(player.volume_db, target):
			continue
		player.volume_db = move_toward(player.volume_db, target, step)
		# A faded-out track is stopped so it does not keep a voice busy for nothing.
		if player.volume_db <= QUIET_DB and mood != _mood and player.playing:
			player.stop()
