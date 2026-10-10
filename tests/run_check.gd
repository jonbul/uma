extends Node
## Headless check of running, in an offline match driven by simulated key
## presses for P1: a single tap doesn't run; a double tap does, at RUN_SPEED;
## running into the left wall hurts P1; a running jump keeps the run's speed
## and landing ends the run; a running kick slides and ends the run; and a
## charge into P2 knocks P2 down and stops P1.
## Run: godot --headless --path <project> -s res://tests/run.gd -- run_check

const TIMEOUT_TICKS := 600

var _m: Match
var _p1: Fighter
var _p2: Fighter


func _ready() -> void:
	_run()


func _run() -> void:
	_m = load("res://game/match.tscn").instantiate()
	get_tree().root.add_child(_m)
	if not await _wait_until(func() -> bool: return _m.phase == Match.Phase.FIGHT, "fight"):
		return
	_p1 = _m.fighters[0]
	_p2 = _m.fighters[1]

	# A single tap only walks.
	await _tap(&"move_right")
	await _ticks(20)
	if _p1.state == Fighter.State.RUN:
		return _fail("a single tap started a run")

	# Double tap left and hold: run into the left wall and crash.
	await _double_tap_and_hold(&"move_left")
	await _ticks(3)
	if _p1.state != Fighter.State.RUN or absf(_p1.velocity.x + Fighter.RUN_SPEED) > 1.0:
		return _fail("double tap didn't run left (state %d, velocity %s)" % [_p1.state, _p1.velocity])
	if not await _wait_until(func() -> bool: return _p1.state == Fighter.State.KNOCKDOWN, "wall crash"):
		return
	Input.action_release(&"move_left")
	if _p1.health != _p1.max_health - Fighter.WALL_CRASH_DAMAGE:
		return _fail("wall crash didn't hurt the runner (health %d)" % _p1.health)
	print("wall crash: P1 health ", _p1.health)
	if not await _wait_until(func() -> bool: return _p1.state == Fighter.State.IDLE, "getting up"):
		return

	# Running jump keeps the speed; landing ends the run.
	await _double_tap_and_hold(&"move_right")
	await _ticks(5)
	await _tap(&"jump")
	if _p1.state != Fighter.State.JUMP or _p1.velocity.x < Fighter.RUN_SPEED - 1.0:
		return _fail("running jump lost the run's speed (velocity %s)" % _p1.velocity)
	Input.action_release(&"move_right")
	if not await _wait_until(func() -> bool: return _p1.state != Fighter.State.JUMP, "landing"):
		return
	if _p1.state == Fighter.State.RUN:
		return _fail("still running after landing")

	# Running kick slides, then the run is over.
	await _double_tap_and_hold(&"move_right")
	await _ticks(5)
	await _tap(&"kick")
	if _p1.state != Fighter.State.ATTACK or _p1.velocity.x <= 0.0:
		return _fail("running kick didn't slide (state %d, velocity %s)" % [_p1.state, _p1.velocity])
	if not await _wait_until(func() -> bool: return _p1.state != Fighter.State.ATTACK, "kick to end"):
		return
	if _p1.state == Fighter.State.RUN:
		return _fail("still running after the running kick")
	Input.action_release(&"move_right")
	await _ticks(2)

	# Charge into P2 (same depth, to the right).
	_p1.position.y = _p2.position.y
	await _double_tap_and_hold(&"move_right")
	if not await _wait_until(func() -> bool: return _p2.state == Fighter.State.KNOCKDOWN, "charge to hit P2"):
		return
	await _ticks(2)
	Input.action_release(&"move_right")
	if _p2.health != _p2.max_health - int(Fighter.ATTACKS[&"charge"]["damage"]):
		return _fail("charge did %d damage" % (_p2.max_health - _p2.health))
	if _p1.state == Fighter.State.RUN:
		return _fail("runner kept running after the charge hit")
	print("charge: P2 health ", _p2.health)
	print("PASS")
	get_tree().quit(0)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _ticks(2)
	Input.action_release(action)
	await _ticks(1)


func _double_tap_and_hold(action: StringName) -> void:
	await _tap(action)
	await _ticks(2)
	Input.action_press(action)
	await _ticks(1)


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
	for action in [&"move_left", &"move_right", &"jump", &"kick"]:
		Input.action_release(action)
	print("FAIL: ", message)
	get_tree().quit(1)
