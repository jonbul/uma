extends Control
## Title screen: online play, offline practice, settings and quit.

const LOBBY_SCENE := "res://ui/menus/lobby.tscn"
const MATCH_SCENE := "res://game/match.tscn"
const SETTINGS_SCENE := "res://ui/menus/settings_menu.tscn"

@onready var _play_button: Button = %PlayButton
@onready var _practice_button: Button = %PracticeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _update_banner: UpdateBanner = %UpdateBanner


func _ready() -> void:
	Settings.load_settings()
	_play_button.pressed.connect(get_tree().change_scene_to_file.bind(LOBBY_SCENE))
	# Not in a room, so the match runs offline: you against a dummy.
	_practice_button.pressed.connect(get_tree().change_scene_to_file.bind(MATCH_SCENE))
	_settings_button.pressed.connect(get_tree().change_scene_to_file.bind(SETTINGS_SCENE))
	_quit_button.pressed.connect(get_tree().quit)
	# Browsers and iOS apps don't quit themselves.
	_quit_button.visible = not (OS.has_feature("web") or OS.has_feature("ios"))
	_play_button.grab_focus()
	SafeArea.fit($Center)
	MenuFx.intro($Center/Panel)
	MenuFx.neon($Center/Panel/Margin/VBox/Title)

	_show_update_info(Network.update_info)
	var update_check := UpdateCheck.new()
	add_child(update_check)
	update_check.finished.connect(_show_update_info)
	update_check.run(Settings.server_url if Settings.server_url else Network.DEFAULT_URL)


## An outdated build can still practice, but not play online.
func _show_update_info(info: Dictionary) -> void:
	_update_banner.show_info(info)
	var required: bool = info.get("required", false)
	_play_button.disabled = required
	if required and _play_button.has_focus():
		_practice_button.grab_focus()
