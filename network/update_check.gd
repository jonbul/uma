class_name UpdateCheck
extends Node
## Asks the server's /version endpoint whether this build may still play
## online and whether a newer one exists, before the player tries to
## connect. Quietly reports nothing when the server can't be reached: the
## hello on connecting is the real gate.

## `info` has the shape of `Network.update_info`; empty when up to date or
## unknown.
signal finished(info: Dictionary)

var _http := HTTPRequest.new()


func _ready() -> void:
	_http.timeout = 5.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


## `server_url` is the WebSocket address, e.g. ws://host:8080/ws.
func run(server_url: String) -> void:
	if _http.request(version_url(server_url)) != OK:
		finished.emit({})


## ws://host:8080/ws → http://host:8080/version (wss → https).
static func version_url(server_url: String) -> String:
	var url := server_url.strip_edges()
	if url.begins_with("wss://"):
		url = "https://" + url.substr(6)
	elif url.begins_with("ws://"):
		url = "http://" + url.substr(5)
	var path_start := url.find("/", url.find("://") + 3)
	if path_start != -1:
		url = url.substr(0, path_start)
	return url + "/version"


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		finished.emit({})
		return
	var policy: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not policy is Dictionary:
		finished.emit({})
		return
	var version := GameVersion.current()
	var min_version := str(policy.get("min_version", ""))
	var latest_version := str(policy.get("latest_version", ""))
	var urls: Variant = policy.get("update_urls", {})
	var info := {
		"required": GameVersion.compare(version, min_version) < 0,
		"min_version": min_version,
		"latest_version": latest_version,
		"url": str(urls.get(GameVersion.platform(), "")) if urls is Dictionary else "",
	}
	if not info["required"] and GameVersion.compare(version, latest_version) >= 0:
		info = {}
	finished.emit(info)
