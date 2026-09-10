# Entry point. Owns exactly one screen at a time: the lobby or a match.
extends Node

var _screen: Node = null
var _screenshot_path := ""
var _shot_countdown := 45
var _shot_attack := false
var _shot_lobby := false
var _shot_end := false
var _shot_pause := false
var _shot_settings := false
var _icon_dir := ""

func _ready() -> void:
	I18n.detect_language()
	Net.match_started.connect(_open_match)
	var args := OS.get_cmdline_user_args()
	if args.has("--autoplay-host") or args.has("--autoplay-join"):
		var seats := 2
		for arg in args:
			if arg.begins_with("--autoplay-seats="):
				seats = maxi(2, int(arg.substr(17)))
		_start_autoplay(args.has("--autoplay-join"), seats)
		return
	for arg in args:
		if arg.begins_with("--shot="):
			_screenshot_path = arg.substr(7)
		if arg == "--shot-attack":
			_shot_attack = true
		if arg == "--shot-lobby":
			_shot_lobby = true
		if arg == "--shot-end":
			_shot_end = true
		if arg == "--shot-pause":
			_shot_pause = true
		if arg == "--shot-settings":
			_shot_pause = true
			_shot_settings = true
		if arg.begins_with("--icons="):
			_icon_dir = arg.substr(8)
	if not _icon_dir.is_empty():
		_render_icons()
		return
	if _shot_lobby:
		_open_lobby()
		return
	if args.has("--preview") or not _screenshot_path.is_empty():
		Net.start_solo(20260905, WorldSettings.of_size(60))
		_stock_preview()
		return
	# Straight into a practice match, for looking at the bot play without tapping through
	# the lobby first.
	if args.has("--practice"):
		Net.start_practice(BotPlayer.Level.HARD, 20260905)
		return
	_open_lobby()

# Renders the app icon from the same Ink strokes the game draws with, so the icon can
# never drift away from how the game actually looks. Run by tools/make_icons.ps1; a real
# window is needed because a headless renderer hands back an empty texture.
func _render_icons() -> void:
	DirAccess.make_dir_recursive_absolute(_icon_dir)
	# The launcher crops an adaptive icon to roughly the middle two thirds, so that one
	# is drawn smaller and over a transparent background.
	await _render_icon(512, "%s/icon.png" % _icon_dir, false, 0.06)
	await _render_icon(432, "%s/icon_adaptive_foreground.png" % _icon_dir, true, 0.24)
	await _render_icon(432, "%s/icon_adaptive_background.png" % _icon_dir, false, 0.5)
	_downscale("%s/icon.png" % _icon_dir, "%s/icon_192.png" % _icon_dir, 192)
	print("ICONS written to ", _icon_dir)
	get_tree().quit(0)

func _render_icon(px: int, path: String, transparent: bool, inset: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(px, px)
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var art := IconArt.new()
	art.size = Vector2(px, px)
	art.transparent = transparent
	art.inset = inset
	viewport.add_child(art)
	add_child(viewport)
	# Two frames: one to lay the control out, one to actually draw it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)
	viewport.queue_free()

func _downscale(from_path: String, to_path: String, px: int) -> void:
	var image := Image.load_from_file(from_path)
	if image == null:
		return
	image.resize(px, px, Image.INTERPOLATE_LANCZOS)
	image.save_png(to_path)

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
	# One house against three factories, so the preview shows a region that has outgrown
	# its housing: the third factory stands idle and is marked as such.
	var plan := [Balance.Building.HOUSE, Balance.Building.FACTORY, Balance.Building.FACTORY,
		Balance.Building.FACTORY, Balance.Building.BANK, Balance.Building.MILITARY_BASE,
		Balance.Building.BARRIER]
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
			if placed < plan.size():
				st.set_cell(cell, 0, plan[placed])
				placed += 1
			else:
				st.set_cell(cell, 0)
	# Filled to the brim, so the preview also shows what an overflowing purse looks like.
	st.coins[0] = int(st.aggregate(0)["coin_cap"])
	# And a couple of buildings actually going up, since that is the new thing to see.
	# A bank rather than a port: a port needs a coast and the preview cannot count on one.
	for cell in [home + 2, home + st.width + 1]:
		if cell < st.owner_of.size() and int(st.owner_of[cell]) == 0 				and int(st.building_at[cell]) == Balance.Building.NONE:
			st.apply_command(0, GameState.make_command(GameState.Command.BUILD, cell,
				Balance.Building.BANK))
	st.power[0] = 45 * Balance.UNIT
	# For the result screenshot: knock the other side out and let the next tick notice.
	if _shot_end:
		st.alive[1] = 0

# Headless self-play for tools/run_net_test.ps1. Never reached in a normal run.
func _start_autoplay(joining: bool, seats: int) -> void:
	var robot: Node = load("res://src/net/autoplay.gd").new()
	robot.seats = seats
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
	if _shot_countdown == 30 and _shot_pause and _screen is MatchScreen:
		(_screen as MatchScreen)._open_pause()
	if _shot_countdown == 25 and _shot_settings and _screen is MatchScreen:
		(_screen as MatchScreen)._show_settings()
	if not _shot_attack and not _shot_lobby \
			and (_shot_countdown == 25 or _shot_countdown == 23):
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
