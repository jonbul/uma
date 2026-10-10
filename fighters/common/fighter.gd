class_name Fighter
extends CharacterBody2D
## Base brawler shared by every fighter.
##
## The node's position is the fighter's spot on the bar floor: x is left/right
## and y is depth. Jumps are faked with `height`, which lifts Body off the
## floor while Shadow stays down. Timings are counted in physics ticks
## (60 per second) so they stay identical on every machine online.

signal health_changed(current: int, maximum: int)
signal knocked_out(fighter: Fighter)

# New states go at the end: online snapshots send states as numbers.
enum State { IDLE, WALK, JUMP, ATTACK, HURT, KNOCKDOWN, DOWN, GET_UP, KO, GRAB, GRABBED, RUN }

## Attacks only connect when both fighters are this close in depth.
const DEPTH_TOLERANCE := 15.0
const GRAVITY := 1350.0
const HITSTUN_TICKS := 18
const KNOCKBACK_FRICTION := 6.0
const KNOCKDOWN_LIFT := 270.0
const DOWN_TICKS := 40
const GET_UP_TICKS := 20

## Running: started by a double tap (FighterInput.run), kept while holding
## that direction. Running into an enemy is a charge (the "charge" attack);
## running into a wall or prop hurts the runner.
const RUN_SPEED := 320.0
## A run is stopped once the stick/keys point less than this much forward.
const RUN_HOLD_THRESHOLD := 0.3
const WALL_CRASH_DAMAGE := 5
const WALL_CRASH_BOUNCE := 150.0
## Running punches and kicks slide on, slowing by this much per tick.
const RUN_ATTACK_FRICTION := 12.0
## How lean the placeholder body is while running, in degrees.
const RUN_LEAN := 12.0

## Gap between a grabber and the fighter it holds.
const GRAB_DISTANCE := 24.0
## The victim breaks free if the grabber does nothing for this long.
const GRAB_HOLD_TICKS := 90
const KNEE_DAMAGE := 4
const KNEE_TICKS := 12
## The knee after this many becomes a throw.
const MAX_KNEES := 2
const THROW_DAMAGE := 12
const THROW_KNOCKBACK := 270.0

const CAN_BE_GRABBED: Array[State] = [State.IDLE, State.WALK, State.ATTACK, State.HURT]
const INVULNERABLE: Array[State] = [State.KNOCKDOWN, State.DOWN, State.GET_UP, State.KO]

## States only the host can put a fighter in (hits, grabs, knockouts). A
## guest predicting its own fighter follows the host exactly while in one.
const HOST_DRIVEN: Array[State] = [
	State.HURT, State.KNOCKDOWN, State.DOWN, State.GET_UP, State.KO, State.GRAB, State.GRABBED,
]
## A predicting guest pulls its fighter toward the host's position when
## they drift further apart than this while moving (the host lags by about
## one round trip, so small gaps are expected)...
const PREDICTION_TOLERANCE := 48.0
## ...and always eases toward it while standing still. Fraction per tick.
const SETTLE_RATE := 0.15
## How fast puppets glide to the latest snapshot; snaps beyond TELEPORT.
const PUPPET_SMOOTHING := 25.0
const PUPPET_TELEPORT := 64.0

## Frame data per attack. The hitbox is live from startup + 1 to
## startup + active; recovery ticks follow before the fighter can act again.
## `hitbox` is a Rect2 relative to the fighter's feet, facing right.
## `next` chains a combo: pressing punch again continues it, but only if the
## current hit landed. `grab` turns the hit into a grab.
const ATTACKS := {
	&"punch_1": {
		"startup": 3, "active": 3, "recovery": 8,
		"damage": 5, "knockback": 45.0, "knockdown": false,
		"hitbox": Rect2(12, -69, 30, 15), "next": &"punch_2",
	},
	&"punch_2": {
		"startup": 3, "active": 3, "recovery": 8,
		"damage": 5, "knockback": 45.0, "knockdown": false,
		"hitbox": Rect2(12, -69, 30, 15), "next": &"punch_3",
	},
	&"punch_3": {
		"startup": 5, "active": 4, "recovery": 16,
		"damage": 9, "knockback": 195.0, "knockdown": true,
		"hitbox": Rect2(12, -72, 36, 21),
	},
	&"kick": {
		"startup": 7, "active": 4, "recovery": 14,
		"damage": 10, "knockback": 180.0, "knockdown": true,
		"hitbox": Rect2(15, -45, 39, 18),
	},
	&"jump_kick": {
		# Stays live until landing.
		"startup": 3, "active": 999, "recovery": 0,
		"damage": 8, "knockback": 180.0, "knockdown": true,
		"hitbox": Rect2(9, -51, 33, 24),
	},
	&"grab": {
		"startup": 2, "active": 3, "recovery": 12,
		"damage": 0, "knockback": 0.0, "knockdown": false,
		"hitbox": Rect2(6, -66, 27, 42), "grab": true,
	},
	&"charge": {
		# Live the whole run: the shoulder barges into whoever is in front.
		"startup": 0, "active": 0, "recovery": 0,
		"damage": 8, "knockback": 220.0, "knockdown": true,
		"hitbox": Rect2(8, -72, 24, 60),
	},
	&"run_punch": {
		"startup": 3, "active": 5, "recovery": 14,
		"damage": 8, "knockback": 160.0, "knockdown": false,
		"hitbox": Rect2(12, -70, 36, 18), "slide": true,
	},
	&"run_kick": {
		"startup": 4, "active": 6, "recovery": 18,
		"damage": 12, "knockback": 220.0, "knockdown": true,
		"hitbox": Rect2(14, -48, 44, 22), "slide": true,
	},
}

@export var max_health := 100
## Pixels per second; depth (y) is slower, as in classic beat 'em ups.
@export var walk_speed := Vector2(135.0, 75.0)
@export var jump_speed := 390.0
## Reads this machine's keyboard and gamepad. Online, only the local
## player's fighter has it on; the rest get `input` from the network.
@export var use_local_input := true
@export var player_name := ""
## The player's id on the server online; 1-based slot number offline.
@export var player_id := 0
## Tints the placeholder body until fighters have sprites.
@export var color := Color(0.85, 0.55, 0.3)

## Online roles. Only fighters with `authority` (offline, or on the host)
## deal damage and start grabs. On a guest, its own fighter is `predicted`
## (simulated locally, corrected by `reconcile_snapshot`) and every other
## fighter is a `puppet` (no physics, glides to `apply_snapshot` positions).
var authority := true
var predicted := false
var puppet := false
## The latest position the host reported for this fighter (guests only).
var net_position := Vector2.ZERO

var health := 0
var state := State.IDLE
var facing := 1
var height := 0.0
var height_velocity := 0.0
var input := FighterInput.new()

var _state_ticks := 0
var _attack: Dictionary = {}
var _attack_ticks := 0
var _hit_this_attack: Array[Fighter] = []
var _combo_queued := false
var _air_attack_used := false
var _knockback := 0.0
## Forward speed carried into a running punch or kick.
var _attack_slide := 0.0
var _grab_target: Fighter = null
var _grabbed_by: Fighter = null
var _knees := 0
var _grab_action_ticks := 0

@onready var _body: Node2D = $Body
@onready var _hitbox: Area2D = $Body/Hitbox
@onready var _hitbox_shape: CollisionShape2D = $Body/Hitbox/CollisionShape2D


func _ready() -> void:
	health = max_health
	# Every attack resizes the hitbox, so each fighter needs its own shape.
	_hitbox_shape.shape = _hitbox_shape.shape.duplicate() as Shape2D
	($Body/Placeholder as ColorRect).color = color
	net_position = position
	set_process(puppet)
	_update_visuals()


func _process(delta: float) -> void:
	# Only puppets process: smooth out bursty network updates.
	position = position.lerp(net_position, 1.0 - exp(-PUPPET_SMOOTHING * delta))


func _physics_process(delta: float) -> void:
	if use_local_input:
		input = FighterInput.from_local()
	if predicted and state in HOST_DRIVEN:
		# The host decides how hits and grabs play out; just show it.
		_update_visuals()
		return
	_state_ticks += 1

	match state:
		State.IDLE, State.WALK:
			_process_ground()
		State.JUMP:
			_process_jump(delta)
		State.ATTACK:
			_process_attack()
		State.HURT:
			_process_hurt()
		State.KNOCKDOWN:
			_process_knockdown(delta)
		State.DOWN:
			if _state_ticks >= DOWN_TICKS:
				_set_state(State.GET_UP)
		State.GET_UP:
			if _state_ticks >= GET_UP_TICKS:
				_set_state(State.IDLE)
		State.GRAB:
			_process_grab()
		State.GRABBED:
			velocity = Vector2.ZERO
			if _grabbed_by == null:
				_set_state(State.IDLE)
		State.RUN:
			_process_run()

	move_and_slide()
	if state == State.RUN:
		_check_run_crash()
	_update_visuals()


## Returns true if the hit landed. Online, only the authority (server or
## host) should call this; clients will receive the result instead.
func take_hit(damage: int, knockback: float, knockdown: bool) -> bool:
	if state in INVULNERABLE:
		return false
	if state == State.GRAB:
		_release_grab()
	elif state == State.GRABBED and _grabbed_by != null:
		_grabbed_by._release_grab()

	_apply_damage(damage)
	if knockback != 0.0:
		facing = -1 if knockback > 0.0 else 1
	_knockback = knockback
	_attack = {}
	velocity = Vector2.ZERO
	if health == 0 or knockdown:
		height_velocity = KNOCKDOWN_LIFT
		_set_state(State.KNOCKDOWN)
	else:
		_set_state(State.HURT)
	return true


## Online guests, for puppets: copy what the host simulated. Fires the same
## health and KO signals the host's fighter fired, so the HUD works.
func apply_snapshot(new_position: Vector2, new_height: float, new_state: State,
		new_facing: int, new_health: int) -> void:
	net_position = new_position
	if position.distance_to(new_position) > PUPPET_TELEPORT:
		position = new_position
	height = new_height
	facing = new_facing
	_sync_health(new_health)
	_enter_snapshot_state(new_state)
	_update_visuals()


## Online guests, for their own predicted fighter: keep the local simulation
## (so controls feel instant) unless the host says otherwise. In a
## HOST_DRIVEN state the host's version wins outright; otherwise the local
## position is only pulled back if it drifts too far, or eased in while idle.
func reconcile_snapshot(new_position: Vector2, new_height: float, new_state: State,
		new_facing: int, new_health: int) -> void:
	net_position = new_position
	_sync_health(new_health)
	if new_state in HOST_DRIVEN:
		position = new_position
		height = new_height
		facing = new_facing
		velocity = Vector2.ZERO
		_attack = {}
		_enter_snapshot_state(new_state)
		_update_visuals()
		return
	if state in HOST_DRIVEN:
		# The host let go of us (got up, broke free): predict again from here.
		position = new_position
		height = 0.0
		height_velocity = 0.0
		_set_state(State.IDLE)
	elif position.distance_to(new_position) > PREDICTION_TOLERANCE \
			or (state == State.IDLE and input.move == Vector2.ZERO):
		position = position.lerp(new_position, SETTLE_RATE)


func _sync_health(new_health: int) -> void:
	if new_health != health:
		health = new_health
		health_changed.emit(health, max_health)


func _enter_snapshot_state(new_state: State) -> void:
	if new_state == state:
		return
	_set_state(new_state)
	if new_state == State.KO:
		knocked_out.emit(self)


## Online: the player left mid-match, so their fighter counts as knocked out.
func drop_out() -> void:
	if state == State.KO:
		return
	if state == State.GRAB:
		_release_grab()
	elif state == State.GRABBED and _grabbed_by != null:
		_grabbed_by._release_grab()
	health = 0
	health_changed.emit(health, max_health)
	velocity = Vector2.ZERO
	height = 0.0
	_set_state(State.KO)
	_update_visuals()
	knocked_out.emit(self)


func _apply_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)


func _process_ground() -> void:
	if input.jump:
		height_velocity = jump_speed
		_attack = {}
		_air_attack_used = false
		_set_state(State.JUMP)
		return
	if input.punch:
		_start_attack(&"punch_1")
		return
	if input.kick:
		_start_attack(&"kick")
		return
	if input.grab:
		_start_attack(&"grab")
		return
	if input.run and input.move.x != 0.0:
		facing = 1 if input.move.x > 0.0 else -1
		_begin_attack(&"charge")
		_set_state(State.RUN)
		_process_run()
		return

	velocity = input.move * walk_speed
	if input.move.x != 0.0:
		facing = 1 if input.move.x > 0.0 else -1
	var next: State = State.WALK if velocity != Vector2.ZERO else State.IDLE
	if next != state:
		_set_state(next)


func _process_jump(delta: float) -> void:
	if not _air_attack_used and (input.punch or input.kick):
		_air_attack_used = true
		_begin_attack(&"jump_kick")

	if not _attack.is_empty():
		_attack_ticks += 1
		if _attack_ticks > _attack["startup"]:
			_check_hits()

	if _apply_height(delta):
		velocity = Vector2.ZERO
		_attack = {}
		_set_state(State.IDLE)


func _start_attack(attack_name: StringName) -> void:
	_begin_attack(attack_name)
	velocity = Vector2.ZERO
	_attack_slide = facing * RUN_SPEED if _attack.get("slide", false) else 0.0
	_set_state(State.ATTACK)


func _process_run() -> void:
	# Jumping keeps the run's speed (JUMP doesn't touch velocity); landing
	# ends the run, as does any attack.
	if input.jump:
		height_velocity = jump_speed
		_attack = {}
		_air_attack_used = false
		_set_state(State.JUMP)
		return
	if input.punch:
		_start_attack(&"run_punch")
		return
	if input.kick:
		_start_attack(&"run_kick")
		return
	if input.move.x * facing < RUN_HOLD_THRESHOLD:
		velocity = Vector2.ZERO
		_set_state(State.IDLE)
		return
	velocity = Vector2(facing * RUN_SPEED, input.move.y * walk_speed.y)
	_check_hits()
	if not _hit_this_attack.is_empty():
		# The charge landed: the runner stops dead.
		velocity = Vector2.ZERO
		_set_state(State.IDLE)


## Running face-first into a wall or prop knocks the runner down.
func _check_run_crash() -> void:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().x * facing > -0.7:
			continue
		if authority:
			take_hit(WALL_CRASH_DAMAGE, -facing * WALL_CRASH_BOUNCE, true)
		else:
			# A predicting guest just stops; the host's knockdown follows.
			velocity = Vector2.ZERO
			_set_state(State.IDLE)
		return


## Loads an attack's data and hitbox without changing state, so jump attacks
## can reuse it mid-air.
func _begin_attack(attack_name: StringName) -> void:
	_attack = ATTACKS[attack_name]
	_attack_ticks = 0
	_hit_this_attack.clear()
	_combo_queued = false
	var rect: Rect2 = _attack["hitbox"]
	(_hitbox_shape.shape as RectangleShape2D).size = rect.size
	_hitbox_shape.position = rect.get_center()


func _process_attack() -> void:
	_attack_ticks += 1
	velocity = Vector2(_attack_slide, 0.0)
	_attack_slide = move_toward(_attack_slide, 0.0, RUN_ATTACK_FRICTION)
	if input.punch and _attack.has("next"):
		_combo_queued = true

	var active_start: int = _attack["startup"] + 1
	var active_end: int = _attack["startup"] + _attack["active"]
	if _attack_ticks >= active_start and _attack_ticks <= active_end:
		_check_hits()
	elif _attack_ticks > active_end:
		if _combo_queued and not _hit_this_attack.is_empty():
			_start_attack(_attack["next"])
		elif _attack_ticks > active_end + _attack["recovery"]:
			_set_state(State.IDLE)


func _check_hits() -> void:
	for area in _hitbox.get_overlapping_areas():
		var target := area.owner as Fighter
		if target == null or target == self or target in _hit_this_attack:
			continue
		if absf(target.global_position.y - global_position.y) > DEPTH_TOLERANCE:
			continue
		if not authority:
			# A predicting guest: the host applies the real hit. Remember it
			# anyway so punch combos chain without waiting for the host.
			if not _attack.get("grab", false):
				_hit_this_attack.append(target)
			continue
		if _attack.get("grab", false):
			if target.state in CAN_BE_GRABBED and target.height == 0.0:
				_start_grab_hold(target)
				return
			continue
		if target.take_hit(_attack["damage"], facing * _attack["knockback"], _attack["knockdown"]):
			_hit_this_attack.append(target)


func _start_grab_hold(target: Fighter) -> void:
	_grab_target = target
	_knees = 0
	_grab_action_ticks = 0
	_attack = {}
	velocity = Vector2.ZERO
	_set_state(State.GRAB)
	target._grabbed_by = self
	target._attack = {}
	target.velocity = Vector2.ZERO
	target.facing = -facing
	target._set_state(State.GRABBED)


func _process_grab() -> void:
	velocity = Vector2.ZERO
	if _grab_target == null:
		_set_state(State.IDLE)
		return
	_grab_target.global_position = global_position + Vector2(facing * GRAB_DISTANCE, 0.0)

	if _grab_action_ticks > 0:
		_grab_action_ticks -= 1
		return
	if input.kick or input.grab:
		_throw()
	elif input.punch:
		_knee()
	elif _state_ticks >= GRAB_HOLD_TICKS:
		_release_grab()


func _knee() -> void:
	if _knees >= MAX_KNEES or _grab_target.health <= KNEE_DAMAGE:
		_throw()
		return
	_knees += 1
	_grab_action_ticks = KNEE_TICKS
	_state_ticks = 0
	_grab_target._apply_damage(KNEE_DAMAGE)


## Throws forward, or backwards if the player holds the opposite direction.
func _throw() -> void:
	var target := _grab_target
	var direction := facing
	if input.move.x != 0.0 and (input.move.x > 0.0) != (facing > 0):
		direction = -facing
	_release_grab()
	facing = direction
	target.take_hit(THROW_DAMAGE, direction * THROW_KNOCKBACK, true)


func _release_grab() -> void:
	var target := _grab_target
	_grab_target = null
	if state == State.GRAB:
		_set_state(State.IDLE)
	if target != null:
		target._grabbed_by = null
		if target.state == State.GRABBED:
			target._set_state(State.IDLE)


func _process_hurt() -> void:
	velocity = Vector2(_knockback, 0.0)
	_knockback = move_toward(_knockback, 0.0, KNOCKBACK_FRICTION)
	if _state_ticks >= HITSTUN_TICKS:
		_set_state(State.IDLE)


func _process_knockdown(delta: float) -> void:
	velocity = Vector2(_knockback, 0.0)
	if not _apply_height(delta):
		return
	velocity = Vector2.ZERO
	if health == 0:
		_set_state(State.KO)
		knocked_out.emit(self)
	else:
		_set_state(State.DOWN)


## Moves the fighter up or down off the floor. Returns true on landing.
func _apply_height(delta: float) -> bool:
	height_velocity -= GRAVITY * delta
	height = maxf(height + height_velocity * delta, 0.0)
	if height == 0.0 and height_velocity < 0.0:
		height_velocity = 0.0
		return true
	return false


func _set_state(new_state: State) -> void:
	state = new_state
	_state_ticks = 0


# Placeholder feedback until there are sprites and animations.
func _update_visuals() -> void:
	_body.position.y = -height
	_body.scale.x = facing
	if state in [State.DOWN, State.KO]:
		_body.rotation_degrees = 90.0
	elif state == State.RUN:
		_body.rotation_degrees = RUN_LEAN * facing
	else:
		_body.rotation_degrees = 0.0
	match state:
		State.HURT, State.KNOCKDOWN:
			_body.modulate = Color(1.0, 0.5, 0.5)
		State.GRABBED:
			_body.modulate = Color(1.0, 0.8, 0.6)
		State.KO:
			_body.modulate = Color(0.5, 0.5, 0.5)
		_:
			_body.modulate = Color.WHITE
