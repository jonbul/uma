class_name PauseMenu
extends Control
## In-match pause menu, opened with the pause action (Esc / gamepad Start)
## or the on-screen pause button. Offline it pauses the game; online the
## fight goes on for everyone else, so it only ignores this player's
## controls while open.

signal leave_requested

@onready var _panel: Control = %Panel
@onready var _resume_button: Button = %ResumeButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	hide()
	_resume_button.pressed.connect(close)
	_leave_button.pressed.connect(func() -> void:
		close()
		leave_requested.emit()
	)
	SafeArea.fit(%SafeArea)


func open(pause_game: bool) -> void:
	show()
	get_tree().paused = pause_game
	FighterInput.blocked = true
	MenuFx.intro(_panel)
	_resume_button.grab_focus()


func close() -> void:
	hide()
	get_tree().paused = false
	FighterInput.blocked = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
