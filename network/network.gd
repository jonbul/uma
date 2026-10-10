extends Node
## Connection to the Go lobby server, registered as the `Network` autoload.
##
## Wraps a WebSocketPeer, speaks the server's JSON protocol (see
## the uma-go repo's internal/lobby/messages.go) and turns messages
## into signals. Match traffic between players travels inside `relay`
## payloads; the match decides what goes in them.

## Fired once the server has accepted this build's version.
signal connected
## The server refuses this version; `info` is as in `update_info`.
signal update_required(info: Dictionary)
## This version may play but a newer one exists.
signal update_available(info: Dictionary)
## Fired when the connection closes or a connection attempt fails.
signal disconnected
signal error_received(message: String)
signal room_joined
signal players_changed
signal player_left(id: int)
signal host_changed
signal match_started
signal match_ended
signal relay_received(from: int, payload: Dictionary)

const DEFAULT_URL := "ws://127.0.0.1:8080/ws"

## Our id on the server, set by its welcome message; 0 when not connected.
var player_id := 0
var player_name := ""
var room_code := ""
var host_id := 0
## [{id, name}] in join order. The order gives spawn slots and colours, so
## every client must use it as received.
var players: Array[Dictionary] = []
## A message for the lobby to show after a match ends unexpectedly.
var notice := ""
## Set when the server reports a newer build: {required, min_version,
## latest_version, url}. Empty when up to date.
var update_info: Dictionary = {}

var _socket := WebSocketPeer.new()
var _active := false
var _hello_ok := false


func connect_to_server(url: String) -> Error:
	_socket.close()
	_socket = WebSocketPeer.new()
	_clear_room()
	player_id = 0
	_hello_ok = false
	var err := _socket.connect_to_url(url)
	_active = err == OK
	return err


func disconnect_from_server() -> void:
	_socket.close()


func is_connected_to_server() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and _hello_ok


func in_room() -> bool:
	return is_connected_to_server() and room_code != ""


func is_host() -> bool:
	return player_id != 0 and player_id == host_id


func create_room(name: String) -> void:
	player_name = name
	_send({"type": "create_room", "name": name})


func join_room(name: String, code: String) -> void:
	player_name = name
	_send({"type": "join_room", "name": name, "code": code})


## The server doesn't confirm leaving, so the room is forgotten right away.
func leave_room() -> void:
	_send({"type": "leave_room"})
	_clear_room()
	players_changed.emit()


func start_match() -> void:
	_send({"type": "start_match"})


## Host: reopens the room so new players can join before the next start.
func end_match() -> void:
	_send({"type": "end_match"})


## Sends `payload` to one player, or to everyone else in the room when `to`
## is 0.
func relay(payload: Dictionary, to: int = 0) -> void:
	var message := {"type": "relay", "payload": payload}
	if to != 0:
		message["to"] = to
	_send(message)


func _send(message: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))


# Polled on physics ticks so match messages arrive at tick granularity. As an
# autoload this runs before the match's own _physics_process.
func _physics_process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _socket.get_available_packet_count() > 0:
				var message: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
				if message is Dictionary:
					_handle(message)
		WebSocketPeer.STATE_CLOSED:
			if _active:
				_active = false
				player_id = 0
				_hello_ok = false
				_clear_room()
				disconnected.emit()


func _handle(message: Dictionary) -> void:
	match message.get("type", ""):
		"welcome":
			player_id = int(message["player_id"])
			_send({"type": "hello", "version": GameVersion.current(), "platform": GameVersion.platform()})
		"hello_ok":
			_hello_ok = true
			connected.emit()
			if message.has("latest_version"):
				update_info = _update_info(message, false)
				update_available.emit(update_info)
		"update_required":
			update_info = _update_info(message, true)
			update_required.emit(update_info)
		"room_joined":
			room_code = message["code"]
			host_id = int(message["host_id"])
			players = _parse_players(message["players"])
			room_joined.emit()
			players_changed.emit()
		"player_joined":
			players.append({"id": int(message["player_id"]), "name": str(message["name"])})
			players_changed.emit()
		"player_left":
			var id := int(message["player_id"])
			players.assign(players.filter(func(p: Dictionary) -> bool: return p["id"] != id))
			player_left.emit(id)
			players_changed.emit()
		"host_changed":
			host_id = int(message["host_id"])
			host_changed.emit()
			players_changed.emit()
		"match_started":
			players = _parse_players(message["players"])
			match_started.emit()
		"match_ended":
			match_ended.emit()
		"relay":
			var payload: Variant = message.get("payload")
			if payload is Dictionary:
				relay_received.emit(int(message["from"]), payload)
		"error":
			error_received.emit(str(message.get("error", "unknown error")))


func _update_info(message: Dictionary, required: bool) -> Dictionary:
	return {
		"required": required,
		"min_version": str(message.get("min_version", "")),
		"latest_version": str(message.get("latest_version", "")),
		"url": str(message.get("update_url", "")),
	}


func _parse_players(raw: Array) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	for p: Dictionary in raw:
		parsed.append({"id": int(p["id"]), "name": str(p["name"])})
	return parsed


func _clear_room() -> void:
	room_code = ""
	host_id = 0
	players.clear()
