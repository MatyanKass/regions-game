# Copyright (c) 2026 MatyanKass. All rights reserved.
# The author's name in the bottom-right corner of every screen, on a layer above
# everything else the game draws. It notes the last moment it was actually drawn in
# plain sight, and the match clock only runs while that moment is recent - see
# Net._process and Net.request. main.gd puts it back if it ever goes missing.
class_name AuthorMark
extends CanvasLayer

const LAYER := 100
const FONT_SIZE := 13
const MIN_FONT_SIZE := 11
const MIN_ALPHA := 0.5
const MARGIN := Vector2(14, 10)
# How long the clock keeps running without a fresh sighting. Generous enough for a
# loading hitch; a removed or hidden name stops it within a second and a half.
const STALE_MS := 1500

static var _seen_at_ms := -1

var _label: _Line

# by MatyanKass
func _ready() -> void:
	layer = LAYER
	_label = _Line.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func _process(_delta: float) -> void:
	if _label != null:
		_label.queue_redraw()

# True when the name has been seen recently, or when there is nothing to see it on:
# a headless run (tests, tools/run_net_test.ps1) or a minimised window, which must never
# stop the clock for the other players in the room.
static func is_showing() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		return true
	return _seen_at_ms >= 0 and Time.get_ticks_msec() - _seen_at_ms <= STALE_MS

static func _note_seen() -> void:
	_seen_at_ms = Time.get_ticks_msec()

class _Line extends Control:
	var font_size := FONT_SIZE

	func _draw() -> void:
		var text := Authorship.line()
		var font := get_theme_default_font()
		var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var view := get_viewport_rect()
		var at := Vector2(view.size.x - MARGIN.x - extent.x,
			view.size.y - MARGIN.y - font.get_descent(font_size))
		var colour := Color(Ink.INK_SOFT, 0.85)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
		var box := Rect2(at - Vector2(0, font.get_ascent(font_size)), extent)
		if _in_plain_sight(box, colour, text):
			AuthorMark._note_seen()

	func _in_plain_sight(box: Rect2, colour: Color, text: String) -> bool:
		var host := get_parent() as CanvasLayer
		if host == null or not host.visible or host.layer < LAYER or not is_visible_in_tree():
			return false
		if text != Authorship.line() or font_size < MIN_FONT_SIZE:
			return false
		if colour.a * modulate.a * self_modulate.a < MIN_ALPHA:
			return false
		if host.scale != Vector2.ONE or host.offset != Vector2.ZERO:
			return false
		return get_viewport_rect().encloses(box)
