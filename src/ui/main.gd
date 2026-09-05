# Entry point. Owns exactly one screen at a time: the lobby or a match.
extends Node

var _screen: Node = null
var _screenshot_path := ""
var _shot_countdown := 45
var _shot_attack := false

func _ready() -> void:
	I18n.detect_language()
	Net.match_started.connect(_open_match)
	var args := OS.get_cmdline_user_args()
	if args.has("--autoplay-host") or args.has("--autoplay-join"):
		_start_autoplay(args.has("--autoplay-join"))
		return
	for arg in args:
		if arg.begins_with("--shot="):
			_screenshot_path = arg.substr(7)
		if arg == "--shot-attack":
			_shot_attack = true
	if args.has("--preview") or not _screenshot_path.is_empty():
		Net.start_solo(20260905)
		_stock_preview()
		return
	# Straight into a practice match, for looking at the bot play without tapping through
	# the lobby first.
	if args.has("--practice"):
		Net.start_practice(BotPlayer.Level.HARD, 20260905)
		return
	_open_lobby()

# Preview mode only: hand the player a small built-up region so the screenshot shows
# what a match actually looks like instead of one empty cell.
func _stock_preview() -> void:
	var st := Net.state
	if st == null:
		return
	var home := 0
	for i in range(st.owner_of.size()):
		if int(st.owner_of[i]) == 0:
			home = i
			break
	var plan := [Balance.Building.HOUSE, Balance.Building.FACTORY, Balance.Building.BANK,
		Balance.Building.MILITARY_BASE, Balance.Building.BARRACKS, Balance.Building.HOUSE]
	var placed := 0
	for dy in range(-1, 3):
		for dx in range(-2, 3):
			var x := home % st.width + dx
			var y := home / st.width + dy
			if not st.in_bounds(x, y):
				continue
			var cell := st.index_of(x, y)
			if not st.is_land(cell):
				continue
			st.owner_of[cell] = 0
			if placed < plan.size():
				st.building_at[cell] = plan[placed]
				placed += 1
	st.coins[0] = 90 * Balance.UNIT
	st.power[0] = 45 * Balance.UNIT

# Headless self-play for tools/run_net_test.ps1. Never reached in a normal run.
func _start_autoplay(joining: bool) -> void:
	var robot: Node = load("res://src/net/autoplay.gd").new()
	robot.joining = joining
	add_child(robot)

func _open_lobby() -> void:
	_swap(LobbyScreen.new())

func _open_match() -> void:
	var match_screen := MatchScreen.new()
	match_screen.exit_requested.connect(_leave_match)
	_swap(match_screen)

func _leave_match() -> void:
	Net.leave()
	_open_lobby()

func _swap(screen: Node) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)

# Development helper: render a few frames, save a PNG and quit, so the look of the
# game can be checked without a person sitting in front of the window.
func _process(_delta: float) -> void:
	if _screenshot_path.is_empty():
		return
	_shot_countdown -= 1
	if _shot_countdown == 30 and _shot_attack and _screen is MatchScreen:
		(_screen as MatchScreen).set_mode(MatchScreen.Mode.ATTACK)
	if not _shot_attack and (_shot_countdown == 25 or _shot_countdown == 23):
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = get_viewport().get_visible_rect().size * 0.5
		touch.pressed = _shot_countdown == 25
		Input.parse_input_event(touch)
	if _shot_countdown > 0:
		return
	var image := get_viewport().get_texture().get_image()
	image.save_png(_screenshot_path)
	_screenshot_path = ""
	get_tree().quit(0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Net.leave()
