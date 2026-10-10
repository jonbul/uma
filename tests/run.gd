extends SceneTree
## Test launcher. Scripts run with -s compile before autoloads are
## registered, so tests that touch game code (which uses the `Network`
## autoload) can't be -s scripts themselves. This loads the named test as a
## Node at runtime instead:
##   godot --headless --path <project> -s res://tests/run.gd -- match_check
## The test prints PASS or FAIL: <reason> and quits with 0 or 1.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("FAIL: name a test, e.g. -- match_check")
		quit(1)
		return
	var test: Node = load("res://tests/%s.gd" % args[0]).new()
	root.add_child.call_deferred(test)
