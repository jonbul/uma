extends Control
## Online lobby: connect to the server, create a room or join one by code,
## wait for players, and (host only) start the match.

const MATCH_SCENE := "res://game/match.tscn"
const MAIN_MENU_SCENE := "res://ui/menus/main_menu.tscn"

## "create" or "join" while waiting for the server's welcome.
var _pending_action := ""

@onready var _connect_box: Control = %ConnectBox
@onready var _name_edit: LineEdit = %NameEdit
@onready var _server_edit: LineEdit = %ServerEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _create_button: Button = %CreateButton
@onready var _join_button: Button = %JoinButton
@onready var _back_button: Button = %BackButton
@onready var _room_box: Control = %RoomBox
@onready var _room_label: Label = %RoomLabel
@onready var _players_label: Label = %PlayersLabel
@onready var _hint_label: Label = %HintLabel
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _status_label: Label = %StatusLabel
@onready var _update_banner: UpdateBanner = %UpdateBanner


func _ready() -> void:
	Settings.load_settings()
	_server_edit.text = Settings.server_url if Settings.server_url else Network.DEFAULT_URL
	_name_edit.text = Settings.player_name if Settings.player_name else "Player%d" % randi_range(100, 999)
	_status_label.text = Network.notice
	Network.notice = ""

	_create_button.pressed.connect(_request.bind("create"))
	_join_button.pressed.connect(_request.bind("join"))
	_code_edit.text_submitted.connect(func(_text: String) -> void: _request("join"))
	_start_button.pressed.connect(Network.start_match)
	_leave_button.pressed.connect(Network.leave_room)
	_back_button.pressed.connect(_go_back)

	Network.connected.connect(_on_connected)
	Network.disconnected.connect(_on_disconnected)
	Network.error_received.connect(_show_status)
	Network.players_changed.connect(_refresh)
	Network.match_started.connect(_on_match_started)
	Network.update_available.connect(_update_banner.show_info)
	Network.update_required.connect(_on_update_required)
	_update_banner.show_info(Network.update_info)

	_refresh()
	_name_edit.grab_focus()
	SafeArea.fit($Center)
	MenuFx.intro($Center/Panel)
	MenuFx.neon($Center/Panel/Margin/VBox/Title)


func _request(action: String) -> void:
	if _name_edit.text.strip_edges().is_empty():
		_show_status("Enter a name first.")
		return
	if action == "join" and _code_edit.text.strip_edges().length() != 4:
		_show_status("Room codes have 4 letters.")
		return
	_remember_inputs()
	_pending_action = action
	_set_busy(true)
	if Network.is_connected_to_server():
		_send_pending_action()
		return
	_status_label.text = "Connecting…"
	if Network.connect_to_server(_server_edit.text.strip_edges()) != OK:
		_pending_action = ""
		_show_status("Invalid server address.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if Network.in_room():
			Network.leave_room()
		else:
			_go_back()


func _go_back() -> void:
	Network.disconnect_from_server()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Saves the name and server so they're filled in next time.
func _remember_inputs() -> void:
	Settings.player_name = _name_edit.text.strip_edges()
	var url := _server_edit.text.strip_edges()
	Settings.server_url = "" if url == Network.DEFAULT_URL else url
	Settings.save_settings()


func _on_connected() -> void:
	_status_label.text = ""
	_send_pending_action()


func _send_pending_action() -> void:
	var player_name := _name_edit.text.strip_edges()
	match _pending_action:
		"create":
			Network.create_room(player_name)
		"join":
			Network.join_room(player_name, _code_edit.text.strip_edges())
	_pending_action = ""


func _on_update_required(info: Dictionary) -> void:
	_pending_action = ""
	_update_banner.show_info(info)
	_show_status("Update the game to play online.")


func _on_disconnected() -> void:
	if _pending_action:
		_show_status("Could not connect to %s" % _server_edit.text)
	else:
		_show_status("Disconnected from the server.")
	_pending_action = ""
	_refresh()


func _on_match_started() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)


func _refresh() -> void:
	var in_room := Network.in_room()
	_connect_box.visible = not in_room
	_room_box.visible = in_room
	_set_busy(false)
	if not in_room:
		return
	_room_label.text = "Room %s" % Network.room_code
	var lines: PackedStringArray = []
	for player in Network.players:
		var line: String = player["name"]
		if player["id"] == Network.host_id:
			line += "  (host)"
		if player["id"] == Network.player_id:
			line += "  (you)"
		lines.append(line)
	_players_label.text = "\n".join(lines)

	var enough_players := Network.players.size() >= 2
	_start_button.visible = Network.is_host()
	_start_button.disabled = not enough_players
	if Network.is_host():
		_hint_label.text = "Share the code. Start when everyone is in." if enough_players \
				else "Share the code with your friends."
	else:
		_hint_label.text = "Waiting for the host to start…"
	if Network.is_host() and enough_players:
		_start_button.grab_focus()
	else:
		_leave_button.grab_focus()


func _show_status(message: String) -> void:
	if message == "match already started":
		message = "A match is in progress. Try again when it ends."
	_status_label.text = message
	_set_busy(false)


func _set_busy(busy: bool) -> void:
	_create_button.disabled = busy
	_join_button.disabled = busy
