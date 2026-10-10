class_name Settings
extends RefCounted
## Player preferences kept between sessions in user://settings.cfg: name,
## server address, fullscreen and control bindings. Static: call
## `Settings.load_settings()` before reading (it only loads once) and
## `save_settings()` after changes.

## Overridable so tests don't touch the player's real settings.
static var path := "user://settings.cfg"
static var player_name := ""
## Empty means Network.DEFAULT_URL.
static var server_url := ""
static var fullscreen := false
## Custom controls: action → {"key": physical keycode, "joy": button index},
## either may be missing. Each replaces the action's first key / first
## gamepad button; other defaults (arrow keys, the stick) stay.
static var bindings: Dictionary = {}

## Actions players can rebind, in the order the settings screen lists them.
const REBINDABLE: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"jump", &"punch", &"kick", &"grab", &"pause",
]
## Godot's built-in ui_accept / ui_cancel have no gamepad buttons, so a
## controller could move through menus but not press or leave anything.
const UI_GAMEPAD_BUTTONS := {&"ui_accept": JOY_BUTTON_A, &"ui_cancel": JOY_BUTTON_B}
const JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	InputFocus.install()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		player_name = config.get_value("player", "name", "")
		server_url = config.get_value("network", "server_url", "")
		fullscreen = config.get_value("display", "fullscreen", false)
		for action in REBINDABLE:
			var binding: Variant = config.get_value("controls", action, {})
			if binding is Dictionary and not binding.is_empty():
				bindings[action] = binding
	apply()


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("network", "server_url", server_url)
	config.set_value("display", "fullscreen", fullscreen)
	for action: StringName in bindings:
		config.set_value("controls", action, bindings[action])
	config.save(path)
	apply()


## Forgets the loaded values so the next load reads the file again.
static func reset() -> void:
	_loaded = false
	player_name = ""
	server_url = ""
	fullscreen = false
	bindings = {}


static func apply() -> void:
	_apply_bindings()
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)



## kind is "key" (value: physical keycode) or "joy" (value: button index).
static func set_binding(action: StringName, kind: String, value: int) -> void:
	var binding: Dictionary = bindings.get(action, {})
	binding[kind] = value
	bindings[action] = binding
	_apply_bindings()


static func reset_bindings() -> void:
	bindings = {}
	_apply_bindings()


## The action's first keyboard key or gamepad button, or null.
static func binding_event(action: StringName, kind: String) -> InputEvent:
	for event in InputMap.action_get_events(action):
		if (kind == "key" and event is InputEventKey) or (kind == "joy" and event is InputEventJoypadButton):
			return event
	return null


static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var keycode: Key = event.physical_keycode
		# The key printed on the player's layout (headless has no keyboard).
		if DisplayServer.get_name() != "headless":
			keycode = DisplayServer.keyboard_get_keycode_from_physical(keycode)
		return OS.get_keycode_string(keycode if keycode else event.physical_keycode)
	if event is InputEventJoypadButton:
		return JOY_BUTTON_NAMES.get(event.button_index, "Button %d" % event.button_index)
	return "—"


static func _apply_bindings() -> void:
	InputMap.load_from_project_settings()
	_add_gamepad_ui_buttons()
	for action: StringName in bindings:
		if not InputMap.has_action(action):
			continue
		var binding: Dictionary = bindings[action]
		for kind: String in binding:
			_replace_first(action, kind, int(binding[kind]))


static func _add_gamepad_ui_buttons() -> void:
	for action: StringName in UI_GAMEPAD_BUTTONS:
		var button_index: int = UI_GAMEPAD_BUTTONS[action]
		var present := InputMap.action_get_events(action).any(func(event: InputEvent) -> bool:
			return event is InputEventJoypadButton and event.button_index == button_index)
		if not present:
			InputMap.action_add_event(action, _make_event("joy", button_index))


## Swaps the action's first event of `kind` for a new one, keeping the
## order (so `binding_event` finds it). New events only: the defaults may be
## shared with ProjectSettings and must stay intact for resets.
static func _replace_first(action: StringName, kind: String, value: int) -> void:
	var events := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	var replaced := false
	for event in events:
		var is_kind := (kind == "key" and event is InputEventKey) \
				or (kind == "joy" and event is InputEventJoypadButton)
		if is_kind and not replaced:
			event = _make_event(kind, value)
			replaced = true
		InputMap.action_add_event(action, event)
	if not replaced:
		InputMap.action_add_event(action, _make_event(kind, value))


static func _make_event(kind: String, value: int) -> InputEvent:
	if kind == "key":
		var key := InputEventKey.new()
		key.physical_keycode = value as Key
		return key
	var button := InputEventJoypadButton.new()
	button.button_index = value as JoyButton
	return button
