extends Control
## Settings screen: player name, server address, fullscreen, and control
## rebinding (one keyboard key and one gamepad button per action). Saves
## when leaving.

const MAIN_MENU_SCENE := "res://ui/menus/main_menu.tscn"
const ACTION_NAMES := {
	&"move_up": "Move up", &"move_down": "Move down",
	&"move_left": "Move left", &"move_right": "Move right",
	&"jump": "Jump", &"punch": "Punch", &"kick": "Kick", &"grab": "Grab",
	&"pause": "Pause",
}

## The binding button waiting for a key or gamepad button, if any.
var _waiting: Button = null
var _waiting_action := &""
var _waiting_kind := ""

@onready var _name_edit: LineEdit = %NameEdit
@onready var _server_edit: LineEdit = %ServerEdit
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _bindings: GridContainer = %Bindings
@onready var _reset_controls_button: Button = %ResetControlsButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	Settings.load_settings()
	_name_edit.text = Settings.player_name
	_server_edit.text = Settings.server_url
	_server_edit.placeholder_text = Network.DEFAULT_URL
	_fullscreen_check.button_pressed = Settings.fullscreen
	# Phones are always full screen.
	_fullscreen_check.visible = not OS.has_feature("mobile")
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_reset_controls_button.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_build_bindings()
	)
	_back_button.pressed.connect(_save_and_go_back)
	_build_bindings()
	SafeArea.fit($Center)
	MenuFx.intro(%Panel)
	_name_edit.grab_focus()


func _input(event: InputEvent) -> void:
	if _waiting == null or not event.is_pressed() or event.is_echo():
		return
	if _waiting_kind == "key" and event is InputEventKey:
		Settings.set_binding(_waiting_action, "key", event.physical_keycode)
	elif _waiting_kind == "joy" and event is InputEventJoypadButton:
		Settings.set_binding(_waiting_action, "joy", event.button_index)
	else:
		return
	get_viewport().set_input_as_handled()
	var button := _waiting
	_waiting = null
	_build_bindings()
	_focus_binding(button.name)


func _unhandled_input(event: InputEvent) -> void:
	if _waiting == null and event.is_action_pressed(&"ui_cancel"):
		_save_and_go_back()


func _build_bindings() -> void:
	_waiting = null
	for child in _bindings.get_children():
		_bindings.remove_child(child)
		child.queue_free()
	for header in ["", "Keyboard", "Gamepad"]:
		var label := Label.new()
		label.text = header
		label.add_theme_font_size_override(&"font_size", 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bindings.add_child(label)
	for action in Settings.REBINDABLE:
		var label := Label.new()
		label.text = ACTION_NAMES.get(action, action)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bindings.add_child(label)
		for kind in ["key", "joy"]:
			var button := Button.new()
			button.name = "%s_%s" % [action, kind]
			button.custom_minimum_size = Vector2(170, 0)
			button.add_theme_font_size_override(&"font_size", 20)
			_make_compact(button)
			button.text = Settings.event_label(Settings.binding_event(action, kind))
			button.pressed.connect(_start_waiting.bind(button, action, kind))
			MenuFx.pop_on_focus(button)
			_bindings.add_child(button)


## Slimmer binding buttons so every action fits without scrolling.
func _make_compact(button: Button) -> void:
	for style_name in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style := button.get_theme_stylebox(style_name).duplicate() as StyleBox
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		button.add_theme_stylebox_override(style_name, style)


func _start_waiting(button: Button, action: StringName, kind: String) -> void:
	if _waiting != null:
		_waiting.text = Settings.event_label(Settings.binding_event(_waiting_action, _waiting_kind))
	_waiting = button
	_waiting_action = action
	_waiting_kind = kind
	button.text = "Press a key…" if kind == "key" else "Press a button…"


func _focus_binding(button_name: String) -> void:
	var button := _bindings.get_node_or_null(button_name) as Button
	if button:
		button.grab_focus()


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.fullscreen = on
	Settings.save_settings()


func _save_and_go_back() -> void:
	Settings.player_name = _name_edit.text.strip_edges()
	Settings.server_url = _server_edit.text.strip_edges()
	Settings.save_settings()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
