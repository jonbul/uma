class_name Match
extends Node2D
## Runs one match: spawns the fighters, counts down, watches for knockouts
## and declares the last one standing. Starts a rematch on its own after
## showing the result.
##
## The stage (walls, props, spawn points) comes from `stage_scene`.
##
## Offline (scene run directly): P1 uses this machine's controls and the
## rest are idle dummies.
## Online (started from the lobby): one fighter per room player, in the
## server's player order. The host simulates every fighter from all players'
## inputs and relays a snapshot each tick. Guests relay their input to the
## host, predict their own fighter locally (see Fighter.reconcile_snapshot)
## and show everyone else as smoothed puppets. When a round ends the host
## reopens the room (end_match) so new players can join, then starts the
## next round through the server (start_match), which respawns everyone.

signal match_started
## `winner` is null on a draw (the last fighters went down together).
signal match_ended(winner: Fighter)

enum Phase { COUNTDOWN, FIGHT, RESULT }

const LOBBY_SCENE := "res://ui/menus/lobby.tscn"
const MAIN_MENU_SCENE := "res://ui/menus/main_menu.tscn"
const COUNTDOWN_SECONDS := 3
## How long "FIGHT!" stays on screen.
const FIGHT_BANNER_SECONDS := 0.75
const RESULT_SECONDS := 4
const PLAYER_COLORS: Array[Color] = [
	Color(0.85, 0.55, 0.3),  # orange
	Color(0.35, 0.55, 0.9),  # blue
	Color(0.4, 0.8, 0.4),  # green
	Color(0.75, 0.45, 0.85),  # purple
	Color(0.9, 0.3, 0.3),  # red
	Color(0.95, 0.85, 0.3),  # yellow
	Color(0.3, 0.85, 0.85),  # cyan
	Color(0.95, 0.55, 0.75),  # pink
	Color(0.9, 0.9, 0.9),  # white
	Color(0.6, 0.45, 0.3),  # brown
]

@export var stage_scene: PackedScene = preload("res://stages/bar/bar.tscn")
@export var fighter_scene: PackedScene = preload("res://fighters/common/fighter.tscn")
@export var overhead_bar_scene: PackedScene = preload("res://ui/hud/overhead_bar.tscn")
## Offline only; online it is the number of players in the room.
@export_range(2, 10) var player_count := 2

var phase := Phase.COUNTDOWN
var stage: Stage
var fighters: Array[Fighter] = []
var online := false

var _alive: Array[Fighter] = []
var _phase_ticks := 0
var _winner: Fighter = null
var _spawn_points: Array[Marker2D] = []
var _is_host := true
## Host: start_match sent, waiting for the server to start the next round.
var _restart_requested := false
## Rounds won this session, by player id. Survives rematches; online the
## host's count is the one shown.
var _wins: Dictionary = {}
## Player ids in the order they were knocked out this round.
var _ko_order: Array[int] = []
## Guest: the results of this round are already on screen.
var _results_shown := false
var _fighters_by_id: Dictionary = {}  # player id -> Fighter
## Host only: inputs received from guests since their fighter last read one.
var _remote_inputs: Dictionary = {}  # player id -> FighterInput
## Guest only: the last input sent, to skip sending unchanged ones.
var _last_sent_input: Array = []

@onready var _world: Node2D = $World
@onready var _fighters_root: Node2D = $World/Fighters
@onready var _announcer: Label = $UI/Announcer
@onready var _results: ResultsPanel = $UI/Results
@onready var _pause_menu: PauseMenu = $UI/PauseMenu


func _ready() -> void:
	# Bindings and gamepad menu buttons, also when the match is run directly.
	Settings.load_settings()
	# Stage and fighters share the y-sorted World, so props and fighters
	# overlap correctly by depth.
	stage = stage_scene.instantiate()
	_world.add_child(stage)
	_world.move_child(stage, 0)
	_spawn_points = stage.get_spawn_points()
	_pause_menu.leave_requested.connect(_leave_match)
	$UI/HudSafeArea/PauseButton.pressed.connect(_open_pause_menu)
	SafeArea.fit($UI/HudSafeArea)

	online = Network.in_room()
	if online:
		_is_host = Network.is_host()
		Network.relay_received.connect(_on_relay_received)
		Network.match_started.connect(start)
		Network.player_left.connect(_on_player_left)
		Network.host_changed.connect(_return_to_lobby.bind("The host left the match."))
		Network.disconnected.connect(_return_to_lobby.bind("Lost connection to the server."))
	start()


## Clears the arena, spawns fresh fighters and starts the countdown.
func start() -> void:
	if online:
		if Network.players.size() < 2:
			_return_to_lobby("Not enough players left.")
			return
		player_count = mini(Network.players.size(), _spawn_points.size())

	for fighter in fighters:
		fighter.queue_free()
	fighters.clear()
	_fighters_by_id.clear()
	_remote_inputs.clear()
	_winner = null
	_restart_requested = false
	_ko_order.clear()
	_results_shown = false
	_results.hide()

	var center_x := get_viewport_rect().size.x / 2.0
	for i in player_count:
		var fighter: Fighter = fighter_scene.instantiate()
		var spawn := _spawn_points[i]
		fighter.position = spawn.position
		fighter.facing = 1 if spawn.position.x < center_x else -1
		fighter.color = PLAYER_COLORS[i]
		if online:
			var player: Dictionary = Network.players[i]
			fighter.player_id = player["id"]
			fighter.player_name = player["name"]
			var is_mine := fighter.player_id == Network.player_id
			fighter.use_local_input = is_mine
			fighter.authority = _is_host
			fighter.predicted = is_mine and not _is_host
			fighter.puppet = not is_mine and not _is_host
		else:
			fighter.player_id = i + 1
			fighter.player_name = "P%d" % (i + 1)
			fighter.use_local_input = i == 0
		fighter.knocked_out.connect(_on_fighter_knocked_out)
		_fighters_root.add_child(fighter)
		fighter.add_child(overhead_bar_scene.instantiate())
		# Frozen until the countdown ends (puppets stay frozen).
		fighter.set_physics_process(false)
		fighters.append(fighter)
		_fighters_by_id[fighter.player_id] = fighter

	_alive = fighters.duplicate()
	_set_phase(Phase.COUNTDOWN)
	_update_announcer()


func _physics_process(_delta: float) -> void:
	if online and not _is_host:
		_send_local_input()
		return
	if online:
		_feed_remote_inputs()

	_phase_ticks += 1
	match phase:
		Phase.COUNTDOWN:
			if _phase_ticks >= COUNTDOWN_SECONDS * Engine.physics_ticks_per_second:
				_begin_fight()
		Phase.RESULT:
			if _phase_ticks >= RESULT_SECONDS * Engine.physics_ticks_per_second:
				if not online:
					start()
					return
				if not _restart_requested:
					_request_next_round()
	_update_announcer()
	# After start_match, old-round snapshots could reach guests after they
	# respawn, so stop until the server starts the new round.
	if online and not _restart_requested:
		_broadcast_snapshot()


func _unhandled_input(event: InputEvent) -> void:
	# The open pause menu handles its own closing.
	if event.is_action_pressed(&"pause") and not _pause_menu.visible:
		_open_pause_menu()
		get_viewport().set_input_as_handled()


## Offline the game freezes; online everyone else keeps fighting.
func _open_pause_menu() -> void:
	_pause_menu.open(not online)


func _leave_match() -> void:
	if online:
		Network.leave_room()
		_return_to_lobby("")
	else:
		get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)


func _begin_fight() -> void:
	for fighter in fighters:
		fighter.set_physics_process(true)
	_set_phase(Phase.FIGHT)
	match_started.emit()


func _on_fighter_knocked_out(fighter: Fighter) -> void:
	_alive.erase(fighter)
	if not _ko_order.has(fighter.player_id):
		_ko_order.append(fighter.player_id)
	# Guests learn the result from the host's snapshots.
	if phase != Phase.FIGHT or (online and not _is_host):
		return
	# A fighter at 0 health still flying from the final blow can't win.
	var standing := _alive.filter(func(f: Fighter) -> bool: return f.health > 0)
	if standing.size() > 1:
		return
	_winner = standing[0] if standing.size() == 1 else null
	if _winner:
		_wins[_winner.player_id] = _wins.get(_winner.player_id, 0) + 1
	_set_phase(Phase.RESULT)
	_update_announcer()
	_show_results(_results_table())
	match_ended.emit(_winner)
	if online:
		# Open the room during the result screen so new players can join.
		Network.end_match()


func _update_announcer() -> void:
	var tps := Engine.physics_ticks_per_second
	match phase:
		Phase.COUNTDOWN:
			_announcer.text = str(ceili(float(COUNTDOWN_SECONDS * tps - _phase_ticks) / tps))
		Phase.FIGHT:
			_announcer.text = "FIGHT!" if _phase_ticks < roundi(FIGHT_BANNER_SECONDS * tps) else ""
		Phase.RESULT:
			_announcer.text = "%s WINS!" % _winner.player_name if _winner else "DRAW!"


## [[player id, wins], …] in placement order: whoever is still standing,
## then fighters still falling from their final blow, then the knocked-out
## ones, last one down first.
func _results_table() -> Array:
	var ids: Array[int] = []
	for fighter in fighters:
		if fighter.health > 0:
			ids.append(fighter.player_id)
	for fighter in fighters:
		if fighter.health == 0 and not _ko_order.has(fighter.player_id):
			ids.append(fighter.player_id)
	for i in range(_ko_order.size() - 1, -1, -1):
		if not ids.has(_ko_order[i]):
			ids.append(_ko_order[i])
	for fighter in fighters:
		if not ids.has(fighter.player_id):
			ids.append(fighter.player_id)
	return ids.map(func(id: int) -> Array: return [id, _wins.get(id, 0)])


func _show_results(table: Array) -> void:
	var rows: Array[Dictionary] = []
	for entry: Array in table:
		var fighter: Fighter = _fighters_by_id.get(int(entry[0]))
		if fighter != null:
			rows.append({"name": fighter.player_name, "color": fighter.color, "wins": int(entry[1])})
	_results.show_results(rows)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	_phase_ticks = 0


# --- Online ---


func _on_relay_received(from: int, payload: Dictionary) -> void:
	match payload.get("t", ""):
		"input":
			if _is_host and payload.get("i") is Array:
				var input := FighterInput.from_array(payload["i"])
				if _remote_inputs.has(from):
					(_remote_inputs[from] as FighterInput).merge(input)
				else:
					_remote_inputs[from] = input
		"state":
			if not _is_host and from == Network.host_id:
				_apply_snapshot(payload)


## Host: asks the server for the next round; its match_started (to every
## player, including anyone who joined during the result) calls start().
func _request_next_round() -> void:
	_restart_requested = true
	if Network.players.size() < 2:
		_return_to_lobby("Not enough players left.")
		return
	Network.start_match()


## Host: gives each guest's fighter the input gathered since last tick.
## Movement carries over; button presses are used once.
func _feed_remote_inputs() -> void:
	for id: int in _remote_inputs:
		var fighter: Fighter = _fighters_by_id.get(id)
		if fighter == null:
			continue
		var pending: FighterInput = _remote_inputs[id]
		fighter.input = pending
		var next := FighterInput.new()
		next.move = pending.move
		_remote_inputs[id] = next


## Guest: sends this machine's input to the host when it changes.
func _send_local_input() -> void:
	if not _fighters_by_id.has(Network.player_id):
		return
	var input := FighterInput.from_local()
	var data := input.to_array()
	if data == _last_sent_input and not input.has_presses():
		return
	_last_sent_input = data
	Network.relay({"t": "input", "i": data}, Network.host_id)


func _broadcast_snapshot() -> void:
	var data: Array = []
	for fighter in fighters:
		data.append([
			fighter.player_id,
			snappedf(fighter.position.x, 0.1),
			snappedf(fighter.position.y, 0.1),
			snappedf(fighter.height, 0.1),
			fighter.state,
			fighter.facing,
			fighter.health,
		])
	var snapshot := {
		"t": "state",
		"ph": phase,
		"pt": _phase_ticks,
		"w": _winner.player_id if _winner else 0,
		"f": data,
	}
	if phase == Phase.RESULT:
		snapshot["r"] = _results_table()
	Network.relay(snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
	var new_phase := int(snapshot.get("ph", 0)) as Phase
	_phase_ticks = int(snapshot.get("pt", 0))
	_winner = _fighters_by_id.get(int(snapshot.get("w", 0)))
	for entry: Array in snapshot.get("f", []):
		var fighter: Fighter = _fighters_by_id.get(int(entry[0]))
		if fighter == null:
			continue
		var args := [Vector2(entry[1], entry[2]), float(entry[3]),
				int(entry[4]) as Fighter.State, int(entry[5]), int(entry[6])]
		if fighter.predicted:
			fighter.reconcile_snapshot.callv(args)
			# Our fighter moves locally once the host's countdown is over.
			fighter.set_physics_process(new_phase != Phase.COUNTDOWN)
		else:
			fighter.apply_snapshot.callv(args)
	if new_phase == Phase.FIGHT and phase == Phase.COUNTDOWN:
		match_started.emit()
	elif new_phase == Phase.RESULT and phase != Phase.RESULT:
		match_ended.emit(_winner)
	phase = new_phase
	_update_announcer()
	if phase == Phase.RESULT and not _results_shown and snapshot.get("r") is Array:
		_results_shown = true
		for entry: Array in snapshot["r"]:
			_wins[int(entry[0])] = int(entry[1])
		_show_results(snapshot["r"])


## Host: a player who leaves mid-match is knocked out.
func _on_player_left(id: int) -> void:
	_remote_inputs.erase(id)
	var fighter: Fighter = _fighters_by_id.get(id)
	if _is_host and fighter != null:
		fighter.drop_out()


func _return_to_lobby(reason: String) -> void:
	_pause_menu.close()
	Network.notice = reason
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
