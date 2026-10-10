extends Node
## Headless end-to-end check of online play against a running Go server.
## Start one Godot process per role at the same time:
##   ROLE=<role> SCENARIO=<scenario> CODE_FILE=<path> [SERVER_URL=ws://...] \
##     godot --headless --path <project> -s res://tests/run.gd -- online_check
## Scenarios and their roles:
##   basic (host, guest, late): the guest walks right, which its own fighter
##     shows at once (prediction) and the host sees; the host KOs the guest
##     and both see "Host WINS!" and the host first in the results. During the result screen `late` joins, and
##     everyone checks the next round has 3 fighters at full health.
##   guest_leaves (host, guest): the guest disconnects mid-fight; the host
##     sees its fighter KO'd and wins.
##   host_leaves (host, guest): the host disconnects mid-fight; the guest is
##     sent back to the lobby.
## The host writes the room code to CODE_FILE, and CODE_FILE.result when the
## first round ends. Prints PASS or FAIL: <reason>, and exits 0 or 1.

const TIMEOUT_TICKS := 1200

var _role := OS.get_environment("ROLE")
var _scenario := OS.get_environment("SCENARIO") if OS.get_environment("SCENARIO") else "basic"
var _code_file := OS.get_environment("CODE_FILE")
var _match_started := false


func _ready() -> void:
	_run()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_until(condition: Callable, what: String) -> bool:
	for i in TIMEOUT_TICKS:
		if condition.call():
			return true
		await get_tree().physics_frame
	_fail("timed out waiting for " + what)
	return false


func _fail(message: String) -> void:
	print("[%s] FAIL: %s" % [_role, message])
	get_tree().quit(1)


func _pass() -> void:
	# Give the others time to see the end before this socket closes.
	await _ticks(60)
	print("[%s] PASS" % _role)
	get_tree().quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	Network.match_started.connect(func() -> void: _match_started = true)
	Network.error_received.connect(func(message: String) -> void: _fail("server error: " + message))
	var url := OS.get_environment("SERVER_URL")
	Network.connect_to_server(url if url else Network.DEFAULT_URL)
	if not await _wait_until(Network.is_connected_to_server, "connection"):
		return

	match _role:
		"host":
			Network.create_room("Host")
			if not await _wait_until(Network.in_room, "room"):
				return
			_write(_code_file, Network.room_code)
			if not await _wait_until(func() -> bool: return Network.players.size() == 2, "guest"):
				return
			Network.start_match()
		"guest":
			if not await _wait_until(func() -> bool: return FileAccess.file_exists(_code_file), "code file"):
				return
			Network.join_room("Guest", FileAccess.get_file_as_string(_code_file).strip_edges())
		"late":
			var result_file := _code_file + ".result"
			if not await _wait_until(func() -> bool: return FileAccess.file_exists(result_file), "first round result"):
				return
			Network.join_room("Late", FileAccess.get_file_as_string(_code_file).strip_edges())
			if not await _wait_until(Network.in_room, "room"):
				return
			await _check_late_round()
			return

	if not await _wait_until(func() -> bool: return _match_started, "match start"):
		return
	var m: Match = load("res://game/match.tscn").instantiate()
	get_tree().root.add_child(m)
	if not await _wait_until(func() -> bool: return m.phase == Match.Phase.FIGHT, "fight"):
		return
	if not m.online or m.fighters.size() != 2:
		return _fail("match not online with 2 fighters")
	var host_fighter: Fighter = m.fighters[0]
	var guest_fighter: Fighter = m.fighters[1]
	if host_fighter.player_name != "Host" or guest_fighter.player_name != "Guest":
		return _fail("wrong fighter names")

	match _scenario:
		"guest_leaves":
			if _role == "guest":
				Network.disconnect_from_server()
				await _pass()
				return
			if not await _wait_until(func() -> bool: return m.phase == Match.Phase.RESULT, "result"):
				return
			await _check_result(m, guest_fighter)
			return
		"host_leaves":
			if _role == "host":
				Network.disconnect_from_server()
				await _pass()
				return
			# The lobby shows (and clears) Network.notice, so check its screen.
			var back_in_lobby := func() -> bool:
				var scene := get_tree().current_scene
				return scene != null and scene.name == "Lobby" \
						and (scene.get_node("%StatusLabel") as Label).text == "The host left the match."
			if not await _wait_until(back_in_lobby, "return to lobby"):
				return
			print("[guest] back to lobby, now host: %s" % Network.is_host())
			await _pass()
			return

	# basic
	if _role == "host":
		var start_x := guest_fighter.position.x
		if not await _wait_until(func() -> bool: return guest_fighter.position.x > start_x + 40.0, "guest to walk right"):
			return
		print("[host] guest walked from %.1f to %.1f" % [start_x, guest_fighter.position.x])
		guest_fighter.take_hit(999, 100.0, false)
	else:
		if not guest_fighter.predicted or not host_fighter.puppet:
			return _fail("guest fighters have the wrong roles")
		var start_x := guest_fighter.position.x
		Input.action_press(&"move_right")
		await _ticks(3)
		# Predicted: our fighter moves before any round trip to the host.
		var early_x := guest_fighter.position.x
		await _ticks(57)
		Input.action_release(&"move_right")
		if early_x <= start_x:
			return _fail("own fighter didn't move at once (no prediction)")
		await _ticks(30)
		var drift := guest_fighter.position.distance_to(guest_fighter.net_position)
		print("[guest] walked %.1f -> %.1f (%.1f after 3 ticks), drift from host %.1f px"
				% [start_x, guest_fighter.position.x, early_x, drift])
		if drift > 4.0:
			return _fail("prediction drifted %.1f px from the host" % drift)

	if not await _wait_until(func() -> bool: return m.phase == Match.Phase.RESULT, "result"):
		return
	if not await _check_result(m, guest_fighter, false):
		return
	# Results arrive on guests through the host's snapshots.
	var rows := (m.get_node("UI/Results/%Rows") as Node).get_children()
	if rows.size() != 2 or (rows[0].get_child(0) as Label).text != "1.  Host" \
			or (rows[0].get_child(1) as Label).text != "1 win":
		return _fail("wrong results panel")
	if _role == "host":
		_write(_code_file + ".result", "1")
	if not await _wait_until(func() -> bool: return m.fighters.size() == 3, "next round with the late player"):
		return
	if not _check_new_round(m):
		return
	# Stay until the round is underway so the late player sees it too.
	if not await _wait_until(func() -> bool: return m.phase == Match.Phase.FIGHT, "next fight"):
		return
	await _pass()


func _check_result(m: Match, guest_fighter: Fighter, finish: bool = true) -> bool:
	var text: String = m.get_node("UI/Announcer").text
	print("[%s] announcer: %s" % [_role, text])
	if text != "Host WINS!":
		_fail("expected 'Host WINS!'")
		return false
	if guest_fighter.state != Fighter.State.KO:
		_fail("guest fighter not KO")
		return false
	if finish:
		await _pass()
	return true


func _check_new_round(m: Match) -> bool:
	var names: Array = m.fighters.map(func(f: Fighter) -> String: return f.player_name)
	if names != ["Host", "Guest", "Late"]:
		_fail("next round fighters are %s" % [names])
		return false
	for fighter in m.fighters:
		if fighter.health != fighter.max_health or fighter.state == Fighter.State.KO:
			_fail("%s didn't start the round fresh" % fighter.player_name)
			return false
	print("[%s] next round: %s" % [_role, names])
	return true


func _check_late_round() -> void:
	if not await _wait_until(func() -> bool: return _match_started, "match start"):
		return
	var m: Match = load("res://game/match.tscn").instantiate()
	get_tree().root.add_child(m)
	await _ticks(2)
	if not _check_new_round(m):
		return
	if not await _wait_until(func() -> bool: return m.phase == Match.Phase.FIGHT, "fight"):
		return
	await _pass()
