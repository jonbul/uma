extends Node
## Headless check of the menus: settings and control bindings save and load
## (to a temporary file, not the player's), and the main menu, settings,
## lobby and pause menu scenes load with their buttons wired.
## Run: godot --headless --path <project> -s res://tests/run.gd -- menu_check

const TEST_SETTINGS := "user://test_settings.cfg"


func _ready() -> void:
	Settings.path = TEST_SETTINGS
	Settings.reset()
	Settings.player_name = "Tester"
	Settings.server_url = "ws://example.test:9000/ws"
	Settings.set_binding(&"jump", "key", KEY_X)
	Settings.set_binding(&"punch", "joy", JOY_BUTTON_RIGHT_SHOULDER)
	Settings.save_settings()
	Settings.reset()
	InputMap.load_from_project_settings()
	Settings.load_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	if Settings.player_name != "Tester" or Settings.server_url != "ws://example.test:9000/ws":
		return _fail("settings didn't round-trip")
	var jump_key := Settings.binding_event(&"jump", "key") as InputEventKey
	var punch_button := Settings.binding_event(&"punch", "joy") as InputEventJoypadButton
	if jump_key.physical_keycode != KEY_X or punch_button.button_index != JOY_BUTTON_RIGHT_SHOULDER:
		return _fail("bindings didn't round-trip")
	if Settings.event_label(punch_button) != "RB":
		return _fail("bad gamepad label")
	# Other default events stay (arrow keys for moving, the stick).
	if InputMap.action_get_events(&"move_left").size() != 4:
		return _fail("rebinding lost default events")
	Settings.reset_bindings()
	if (Settings.binding_event(&"jump", "key") as InputEventKey).physical_keycode != KEY_SPACE:
		return _fail("reset didn't restore defaults")
	for action: StringName in Settings.UI_GAMEPAD_BUTTONS:
		var joy := Settings.binding_event(action, "joy") as InputEventJoypadButton
		if joy == null or joy.button_index != Settings.UI_GAMEPAD_BUTTONS[action]:
			return _fail("%s has no gamepad button" % action)

	# With only a gamepad: A on a binding starts waiting, the next button binds.
	var settings_menu: Node = load("res://ui/menus/settings_menu.tscn").instantiate()
	add_child(settings_menu)
	await get_tree().process_frame
	var jump_pad := settings_menu.get_node("%Bindings/jump_joy") as Button
	jump_pad.grab_focus()
	await _press_joy(JOY_BUTTON_A)
	if jump_pad.text != "Press a button…":
		return _fail("gamepad A didn't start rebinding (text: %s)" % jump_pad.text)
	await _press_joy(JOY_BUTTON_RIGHT_SHOULDER)
	if (Settings.binding_event(&"jump", "joy") as InputEventJoypadButton).button_index != JOY_BUTTON_RIGHT_SHOULDER:
		return _fail("gamepad rebinding didn't take the new button")
	# An unfocused window ignores the gamepad: menus...
	InputFocus.simulate_unfocused = true
	var punch_pad := settings_menu.get_node("%Bindings/punch_joy") as Button
	punch_pad.grab_focus()
	await _press_joy(JOY_BUTTON_A)
	if punch_pad.text == "Press a button…":
		InputFocus.simulate_unfocused = false
		return _fail("an unfocused window reacted to the gamepad")
	# ...and fighters.
	Input.action_press(&"move_right")
	var unfocused_move := FighterInput.from_local().move
	InputFocus.simulate_unfocused = false
	var focused_move := FighterInput.from_local().move
	Input.action_release(&"move_right")
	if unfocused_move != Vector2.ZERO or focused_move.x < 0.9:
		return _fail("fighter input ignores focus (%s / %s)" % [unfocused_move, focused_move])
	Settings.reset_bindings()
	settings_menu.queue_free()
	await get_tree().process_frame

	for check: Array in [
		["res://ui/menus/main_menu.tscn", ["%PlayButton", "%PracticeButton", "%SettingsButton", "%QuitButton"]],
		["res://ui/menus/settings_menu.tscn", ["%NameEdit", "%ServerEdit", "%FullscreenCheck", "%BackButton"]],
		["res://ui/menus/lobby.tscn", ["%CreateButton", "%JoinButton", "%BackButton"]],
		["res://ui/menus/pause_menu.tscn", ["%ResumeButton", "%LeaveButton"]],
	]:
		var scene: Node = load(check[0]).instantiate()
		add_child(scene)
		await get_tree().process_frame
		for button_path: String in check[1]:
			var control := scene.get_node_or_null(button_path)
			if control == null:
				return _fail("%s has no %s" % [check[0], button_path])
			if control is BaseButton and control.pressed.get_connections().is_empty() \
					and control.toggled.get_connections().is_empty():
				return _fail("%s %s isn't connected" % [check[0], button_path])
		var grid := scene.get_node_or_null("%Bindings")
		# A header row plus a row per action: label, key, gamepad button.
		if grid and grid.get_child_count() != 3 * (Settings.REBINDABLE.size() + 1):
			return _fail("settings shows %d binding cells" % grid.get_child_count())
		if grid:
			# Gamepad players can't scroll by hand: everything must fit.
			await get_tree().process_frame
			var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			if not screen.encloses((scene.get_node("%Panel") as Control).get_global_rect()):
				return _fail("settings panel is bigger than the screen")
			var visible_area := (grid.get_parent() as Control).get_global_rect().grow(1.0)
			for cell in grid.get_children():
				if cell is Button and not visible_area.encloses((cell as Control).get_global_rect()):
					return _fail("binding %s is hidden until you scroll" % cell.name)
		var settings_name := scene.get_node_or_null("%NameEdit") as LineEdit
		if settings_name and settings_name.text != "Tester":
			return _fail("%s doesn't show the saved name" % check[0])
		scene.queue_free()
	print("PASS")
	get_tree().quit(0)


func _fail(message: String) -> void:
	print("FAIL: ", message)
	get_tree().quit(1)


func _press_joy(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame
