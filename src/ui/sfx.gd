# Autoloaded as /root/Sfx. Every sound effect is synthesised at startup rather than
# shipped as a file: they are short blips, so a few lines of arithmetic beat a folder of
# WAVs that need licences, and retuning one is editing a number rather than finding a new
# recording.
#
# Everything is a sweep between two pitches with a decay envelope, in one of three
# voices. That is a narrow palette on purpose - it makes the whole set sound like it
# belongs to one game.
#
# A real recording always wins: drop "build.ogg" into assets/sfx and it replaces the
# synthesised build sound at startup, with no code change. The generated set is the
# floor, not the ceiling - see assets/sfx/README.md for the names.
extends Node

const RATE := 22050
const OVERRIDE_DIR := "res://assets/sfx"
const OVERRIDE_TYPES := [".ogg", ".wav", ".mp3"]
const VOICES := 8            # how many effects may overlap
const MASTER_DB := -7.0

enum Wave { SINE, SQUARE, NOISE, TRIANGLE }

# from_hz / to_hz  - the pitch sweep over the life of the sound
# ms               - length
# wave             - which voice
# gain             - relative loudness, before the master trim
# decay            - how sharply it dies away; higher is snappier
const RECIPES := {
	# A soft tick under every button, so the interface feels like it answers.
	"tap": [{"from_hz": 720.0, "to_hz": 680.0, "ms": 45, "wave": Wave.SINE, "gain": 0.25, "decay": 22.0}],
	# Something set down on paper: a knock with a little body under it.
	"build": [
		{"from_hz": 300.0, "to_hz": 180.0, "ms": 90, "wave": Wave.TRIANGLE, "gain": 0.5, "decay": 16.0},
		{"from_hz": 900.0, "to_hz": 900.0, "ms": 35, "wave": Wave.SINE, "gain": 0.3, "decay": 30.0},
	],
	# Three rising notes: the sound of something getting better.
	"upgrade": [
		{"from_hz": 523.0, "to_hz": 523.0, "ms": 70, "wave": Wave.SINE, "gain": 0.35, "decay": 14.0},
		{"from_hz": 659.0, "to_hz": 659.0, "ms": 70, "wave": Wave.SINE, "gain": 0.35, "decay": 14.0, "delay_ms": 70},
		{"from_hz": 880.0, "to_hz": 880.0, "ms": 130, "wave": Wave.SINE, "gain": 0.4, "decay": 10.0, "delay_ms": 140},
	],
	# Rubble: noise falling away.
	"demolish": [
		{"from_hz": 400.0, "to_hz": 90.0, "ms": 220, "wave": Wave.NOISE, "gain": 0.45, "decay": 9.0},
	],
	# Taking ground: a clipped, forward sound you can hear twice a second without tiring.
	"capture": [
		{"from_hz": 340.0, "to_hz": 520.0, "ms": 70, "wave": Wave.SQUARE, "gain": 0.3, "decay": 26.0},
	],
	# Losing ground: the same idea upside down, and lower, so it reads as bad news.
	"lost_cell": [
		{"from_hz": 420.0, "to_hz": 150.0, "ms": 260, "wave": Wave.SQUARE, "gain": 0.35, "decay": 8.0},
	],
	# The reload, or anything else the rules refuse. Deliberately dull and short.
	"denied": [
		{"from_hz": 150.0, "to_hz": 130.0, "ms": 90, "wave": Wave.SQUARE, "gain": 0.22, "decay": 18.0},
	],
	# A hull pushing off: noise swelling rather than snapping.
	"ship": [
		{"from_hz": 180.0, "to_hz": 320.0, "ms": 380, "wave": Wave.NOISE, "gain": 0.3, "decay": 3.5},
	],
	"victory": [
		{"from_hz": 523.0, "to_hz": 523.0, "ms": 140, "wave": Wave.TRIANGLE, "gain": 0.4, "decay": 7.0},
		{"from_hz": 659.0, "to_hz": 659.0, "ms": 140, "wave": Wave.TRIANGLE, "gain": 0.4, "decay": 7.0, "delay_ms": 130},
		{"from_hz": 1047.0, "to_hz": 1047.0, "ms": 420, "wave": Wave.TRIANGLE, "gain": 0.45, "decay": 3.5, "delay_ms": 260},
	],
	"defeat": [
		{"from_hz": 440.0, "to_hz": 440.0, "ms": 180, "wave": Wave.TRIANGLE, "gain": 0.4, "decay": 6.0},
		{"from_hz": 349.0, "to_hz": 349.0, "ms": 180, "wave": Wave.TRIANGLE, "gain": 0.4, "decay": 6.0, "delay_ms": 170},
		{"from_hz": 233.0, "to_hz": 220.0, "ms": 520, "wave": Wave.TRIANGLE, "gain": 0.45, "decay": 3.0, "delay_ms": 340},
	],
}

var _sounds: Dictionary = {}   # name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _rng := SimRng.new(20260905)

func _ready() -> void:
	for name in RECIPES:
		var supplied := _load_override(str(name))
		_sounds[name] = supplied if supplied != null else _render(RECIPES[name])
	for i in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.volume_db = MASTER_DB
		add_child(player)
		_players.append(player)

# A hand-made file for this effect, if somebody has put one there. Returns null when
# there is nothing to load, which is the normal case and means "use the synthesiser".
func load_override(name: String) -> AudioStream:
	return _load_override(name)

func _load_override(name: String) -> AudioStream:
	var dir := DirAccess.open(OVERRIDE_DIR)
	if dir == null:
		return null
	# The project folder lists both "build.ogg" and "build.ogg.import"; the exported one
	# lists only the first. Stripping the sidecar suffix covers both.
	# Matched without regard to case: somebody dropping in "Build.ogg" means the build
	# sound, and having that quietly do nothing is a miserable way to lose an afternoon.
	for file in dir.get_files():
		var clean := file.trim_suffix(".import")
		for suffix in OVERRIDE_TYPES:
			if clean.to_lower() == name.to_lower() + suffix:
				var stream = load(OVERRIDE_DIR + "/" + clean)
				if stream is AudioStream:
					return stream
	return null

func play(name: String) -> void:
	if not _sounds.has(name):
		return
	# Round robin rather than hunting for a free player: the oldest voice is the one
	# most likely to have finished, and a stolen tail is inaudible at these lengths.
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = _sounds[name]
	player.play()

# --- Synthesis --------------------------------------------------------------------

func _render(parts: Array) -> AudioStreamWAV:
	var total_ms := 0
	for part in parts:
		total_ms = maxi(total_ms, int(part.get("delay_ms", 0)) + int(part["ms"]))
	var samples := RATE * total_ms / 1000 + 1
	var buffer := PackedFloat32Array()
	buffer.resize(samples)
	for part in parts:
		_mix(buffer, part)
	return _to_stream(buffer)

func _mix(buffer: PackedFloat32Array, part: Dictionary) -> void:
	var start := RATE * int(part.get("delay_ms", 0)) / 1000
	var length := RATE * int(part["ms"]) / 1000
	var from_hz := float(part["from_hz"])
	var to_hz := float(part["to_hz"])
	var gain := float(part["gain"])
	var decay := float(part["decay"])
	var wave := int(part["wave"])
	var phase := 0.0
	for i in range(length):
		var index := start + i
		if index >= buffer.size():
			break
		var t := float(i) / float(length)
		var hz := lerpf(from_hz, to_hz, t)
		phase += TAU * hz / float(RATE)
		var value := 0.0
		match wave:
			Wave.SINE:
				value = sin(phase)
			Wave.SQUARE:
				value = 1.0 if sin(phase) >= 0.0 else -1.0
			Wave.TRIANGLE:
				value = asin(sin(phase)) * 2.0 / PI
			Wave.NOISE:
				value = float(_rng.next_range(2001)) / 1000.0 - 1.0
		# Exponential decay, plus a couple of milliseconds of fade in so nothing clicks
		# at the start of a sample.
		var envelope := exp(-decay * t) * minf(1.0, float(i) / 64.0)
		buffer[index] = buffer[index] + value * gain * envelope

func _to_stream(buffer: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buffer.size() * 2)
	for i in range(buffer.size()):
		var sample := int(clampf(buffer[i], -1.0, 1.0) * 32000.0)
		# Little endian 16 bit, which is what FORMAT_16_BITS expects.
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
