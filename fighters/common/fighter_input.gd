class_name FighterInput
extends RefCounted
## One physics tick of fighter input.
##
## Local play fills it from the InputMap. Online, guests send theirs to the
## host as arrays, so the fighter never reads devices directly.

## Two taps of the same direction within this many ticks start a run.
const DOUBLE_TAP_TICKS := 15

var move := Vector2.ZERO
var jump := false
var punch := false
var kick := false
var grab := false
## A double tap left or right this tick: start running. Detected here, on
## the player's own device, so network timing can't turn it into a single
## tap (or two taps into one) on the host.
var run := false

## While true (e.g. the pause menu is open) local input reads as nothing.
static var blocked := false

static var _last_tap_direction := 0
static var _last_tap_frame := -1000
## from_local() runs more than once a tick online (the match sends it, the
## predicted fighter uses it); every call that tick gets the same reading so
## a tap is only counted once.
static var _cached_frame := -1
static var _cached: FighterInput = null


static func from_local() -> FighterInput:
	# Fighters poll devices directly, so the window focus check is needed
	# here too, not only for menus (see InputFocus).
	if blocked or not InputFocus.window_focused():
		return FighterInput.new()
	var frame := Engine.get_physics_frames()
	if frame == _cached_frame and _cached != null:
		return _cached.copy()

	var input := FighterInput.new()
	input.move = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	input.jump = Input.is_action_just_pressed(&"jump")
	input.punch = Input.is_action_just_pressed(&"punch")
	input.kick = Input.is_action_just_pressed(&"kick")
	input.grab = Input.is_action_just_pressed(&"grab")

	var tap := 0
	if Input.is_action_just_pressed(&"move_right"):
		tap = 1
	elif Input.is_action_just_pressed(&"move_left"):
		tap = -1
	if tap != 0:
		input.run = tap == _last_tap_direction and frame - _last_tap_frame <= DOUBLE_TAP_TICKS
		# After a run starts, the next tap begins a new pair.
		_last_tap_direction = 0 if input.run else tap
		_last_tap_frame = frame

	_cached_frame = frame
	_cached = input
	return input.copy()


func copy() -> FighterInput:
	var other := FighterInput.new()
	other.move = move
	other.jump = jump
	other.punch = punch
	other.kick = kick
	other.grab = grab
	other.run = run
	return other


## Compact network form: [move_x, move_y, jump, punch, kick, grab, run].
func to_array() -> Array:
	return [snappedf(move.x, 0.01), snappedf(move.y, 0.01), jump, punch, kick, grab, run]


## Also accepts the 6-value form (no run) of builds before running existed.
static func from_array(data: Array) -> FighterInput:
	var input := FighterInput.new()
	if data.size() < 6:
		return input
	input.move = Vector2(float(data[0]), float(data[1])).limit_length(1.0)
	input.jump = bool(data[2])
	input.punch = bool(data[3])
	input.kick = bool(data[4])
	input.grab = bool(data[5])
	input.run = data.size() > 6 and bool(data[6])
	return input


func has_presses() -> bool:
	return jump or punch or kick or grab or run


## Folds a newer input into this one: the latest movement wins, and button
## presses are kept until the fighter consumes them.
func merge(newer: FighterInput) -> void:
	move = newer.move
	jump = jump or newer.jump
	punch = punch or newer.punch
	kick = kick or newer.kick
	grab = grab or newer.grab
	run = run or newer.run
