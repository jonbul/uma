class_name SafeArea
extends Node
## Keeps UI clear of phone notches, camera holes and rounded corners.
## `SafeArea.fit(control)` turns a full-screen control's offsets into the
## screen's safe margins (in game pixels), and keeps them updated when the
## window changes for as long as the control exists. On desktop the safe
## area is the whole screen, so nothing changes.

var _target: Control


static func fit(control: Control) -> void:
	var watcher := SafeArea.new()
	watcher.name = "SafeAreaWatcher"
	watcher._target = control
	control.add_child(watcher)


func _ready() -> void:
	# Connected to this node, so it disconnects when the screen is freed.
	get_viewport().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area().intersection(window)
	if safe.size.x <= 0 or safe.size.y <= 0:
		return
	# Window pixels → game pixels (the game is stretched to fit the window).
	var to_game := _target.get_viewport_rect().size / Vector2(window.size)
	_target.offset_left = (safe.position.x - window.position.x) * to_game.x
	_target.offset_top = (safe.position.y - window.position.y) * to_game.y
	_target.offset_right = -(window.end.x - safe.end.x) * to_game.x
	_target.offset_bottom = -(window.end.y - safe.end.y) * to_game.y
