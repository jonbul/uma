class_name InputFocus
extends Node
## Ignores gamepad input while the game window isn't focused. Godot sends
## gamepad events to every running copy of the game, so with several test
## windows open (Debug > Customize Run Instances) one controller drove them
## all; a game in the background shouldn't react to the pad either.
## Keyboard and mouse already only reach the focused window.
##
## `Settings.load_settings()` installs one under the root (not an autoload,
## so project.godot needn't change); it survives scene changes.

## Tests set this to pretend the window lost focus.
static var simulate_unfocused := false
static var _installed := false


static func install() -> void:
	if _installed:
		return
	_installed = true
	var guard := InputFocus.new()
	guard.name = "InputFocus"
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(guard)


static func window_focused() -> bool:
	if simulate_unfocused:
		return false
	if DisplayServer.get_name() == "headless":
		return true
	return (Engine.get_main_loop() as SceneTree).root.has_focus()


# Menus: stop gamepad events before the GUI sees them.
func _input(event: InputEvent) -> void:
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and not window_focused():
		get_viewport().set_input_as_handled()
