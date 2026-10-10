extends Node
## Headless check of the version check against a running Go server started
## with `-min-version 0.1.0 -latest-version 0.2.0 -android-url <url>`
## (tests/run_all.sh does this). Covers GameVersion.compare, the /version
## startup check, and the hello on connecting for a too-old build, an
## outdated-but-allowed build (this project, 0.1.0) and an up-to-date one.
## Run: SERVER_URL=ws://127.0.0.1:18080/ws godot --headless --path <project> \
##   -s res://tests/run.gd -- version_check

var _server_url := OS.get_environment("SERVER_URL")


func _ready() -> void:
	for case: Array in [
		["1.2.3", "1.2.3", 0], ["1.2", "1.2.0", 0], ["v1.10.0", "1.9.9", 1],
		["0.9.9", "1.0.0", -1], ["1.0.0-beta", "1.0.0", 0], ["garbage", "0.0.1", -1],
	]:
		if GameVersion.compare(case[0], case[1]) != case[2]:
			return _fail("compare(%s, %s) != %d" % case)
	if UpdateCheck.version_url("wss://uma.example/ws") != "https://uma.example/version" \
			or UpdateCheck.version_url("ws://127.0.0.1:18080/ws") != "http://127.0.0.1:18080/version":
		return _fail("bad /version URL")

	# Startup check (HTTP): this build is allowed but outdated...
	var info: Dictionary = await _startup_check()
	if info.get("required", true) or info.get("latest_version") != "0.2.0":
		return _fail("startup check for 0.1.0 gave %s" % info)
	# ...a too-old one must update...
	GameVersion.override = "0.0.9"
	info = await _startup_check()
	if not info.get("required", false):
		return _fail("startup check for 0.0.9 gave %s" % info)
	# ...and the latest one is fine.
	GameVersion.override = "0.2.0"
	if not (await _startup_check()).is_empty():
		return _fail("startup check for 0.2.0 wasn't empty")

	# Hello on connecting: a too-old build is refused.
	GameVersion.override = "0.0.9"
	Network.connect_to_server(_server_url)
	info = await Network.update_required
	if info.get("min_version") != "0.1.0" or Network.is_connected_to_server():
		return _fail("old build not refused properly: %s" % info)

	# An up-to-date build connects without an update notice.
	GameVersion.override = "0.2.0"
	Network.update_info = {}
	Network.connect_to_server(_server_url)
	await Network.connected
	if not Network.update_info.is_empty():
		return _fail("up-to-date build told to update")
	Network.disconnect_from_server()
	print("PASS")
	get_tree().quit(0)


func _startup_check() -> Dictionary:
	var check := UpdateCheck.new()
	add_child(check)
	check.run(_server_url)
	var info: Dictionary = await check.finished
	check.queue_free()
	return info


func _fail(message: String) -> void:
	print("FAIL: ", message)
	get_tree().quit(1)
