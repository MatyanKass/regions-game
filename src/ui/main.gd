# Entry point. Owns exactly one screen at a time: the lobby or a match.
extends Node

var _screen: Node = null

func _ready() -> void:
	I18n.detect_language()
	Net.match_started.connect(_open_match)
	var args := OS.get_cmdline_user_args()
	if args.has("--autoplay-host") or args.has("--autoplay-join"):
		_start_autoplay(args.has("--autoplay-join"))
		return
	_open_lobby()

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

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Net.leave()
