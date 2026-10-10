extends Node
## Headless check of the match flow: stage, countdown, overhead health bars,
## pause menu, win, results panel, rematch and draw.
## Run: godot --headless --path <project> -s res://tests/run.gd -- match_check
## Prints PASS or FAIL: <reason>.

var winner_seen = "unset"


func _ready() -> void:
	_run()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _fail(msg: String) -> void:
	print("FAIL: ", msg)
	get_tree().quit(1)


func _run() -> void:
	var m: Match = load("res://game/match.tscn").instantiate()
	get_tree().root.add_child(m)
	m.match_ended.connect(func(w): winner_seen = w)
	await _ticks(5)
	if m.phase != Match.Phase.COUNTDOWN: return _fail("not counting down")
	if m.fighters.size() != 2: return _fail("expected 2 fighters")
	print("countdown text: ", m.get_node("UI/Announcer").text)
	var p1 := m.fighters[0]
	var p2 := m.fighters[1]
	if p1.facing != 1 or p2.facing != -1: return _fail("facing wrong")
	await _ticks(185)
	if m.phase != Match.Phase.FIGHT: return _fail("fight did not start")
	# Offline, the pause action freezes the game until the menu closes.
	var pause := InputEventAction.new()
	pause.action = &"pause"
	pause.pressed = true
	Input.parse_input_event(pause)
	await _ticks(2)
	var pause_menu: PauseMenu = m.get_node("UI/PauseMenu")
	if not pause_menu.visible or not get_tree().paused: return _fail("pause didn't pause")
	pause_menu.close()
	if get_tree().paused or FighterInput.blocked: return _fail("closing the pause menu didn't resume")
	print("fight text: ", m.get_node("UI/Announcer").text)
	if m.stage == null or m.stage.get_spawn_points().size() < 10: return _fail("stage needs 10 spawn points")
	# The stage's back wall stops a fighter walking up.
	p2.input.move = Vector2.UP
	await _ticks(180)
	p2.input.move = Vector2.ZERO
	if p2.position.y < 280.0: return _fail("P2 walked through the back wall: %s" % p2.position)
	var p2_bar: ProgressBar = p2.get_node("OverheadBar/Bar")
	if (p2.get_node("OverheadBar/Name") as Label).text != "P2": return _fail("P2 name missing")
	p2.take_hit(10, 100.0, false)
	await _ticks(2)
	if p2_bar.value != 90: return _fail("P2 bar shows %s, want 90" % p2_bar.value)
	await _ticks(30)
	p2.take_hit(999, 100.0, false)
	await _ticks(120)
	if m.phase != Match.Phase.RESULT: return _fail("no result, p2 state %d" % p2.state)
	var p2_overhead: Node2D = p2.get_node("OverheadBar")
	if p2_overhead.position != OverheadBar.LYING_OFFSET: return _fail("KO bar not on the lying body: %s" % p2_overhead.position)
	if winner_seen != p1: return _fail("wrong winner")
	print("result text: ", m.get_node("UI/Announcer").text)
	var results := _results(m)
	print("results: ", results)
	if results != ["1.  P1|1 win", "2.  P2|0 wins"]: return _fail("wrong results panel")
	await _ticks(245)
	if m.phase != Match.Phase.COUNTDOWN: return _fail("no rematch")
	if m.fighters.size() != 2 or m.fighters[0] == p1: return _fail("fighters not respawned")
	if m.get_node("World/Fighters").get_child_count() != 2: return _fail("old fighters not freed")
	if (m.fighters[1].get_node("OverheadBar/Bar") as ProgressBar).value != 100: return _fail("bar not reset")
	# Draw: both KO'd in the same tick.
	await _ticks(185)
	m.fighters[0].take_hit(999, 100.0, false)
	m.fighters[1].take_hit(999, -100.0, false)
	await _ticks(120)
	print("draw text: ", m.get_node("UI/Announcer").text)
	# A draw adds no win; P2 went down last in the same tick, so ranks first.
	if _results(m) != ["1.  P2|0 wins", "2.  P1|1 win"]: return _fail("wrong draw results: %s" % [_results(m)])
	if winner_seen != null: return _fail("expected draw")
	print("PASS")
	get_tree().quit(0)


## The results panel rows as "name|wins" strings, or [] when hidden.
func _results(m: Node) -> Array:
	var panel: Control = m.get_node("UI/Results")
	if not panel.visible:
		return []
	var rows: Array = []
	for row in panel.get_node("%Rows").get_children():
		rows.append("%s|%s" % [row.get_child(0).text, row.get_child(1).text])
	return rows
