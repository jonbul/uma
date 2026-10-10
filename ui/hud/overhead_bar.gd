class_name OverheadBar
extends Node2D
## Name and health bar floating above a fighter's head.
##
## Add it as a child of a Fighter that is already in the tree. It follows
## the fighter's jumps, drops onto the body while the fighter lies on the
## floor, and dims once the fighter is knocked out.

## Bar position relative to the fighter's feet; the body is 84 px tall.
const HEAD_OFFSET := -93.0
## Lying down, the body is rotated 90° around the feet: it spans 84 px to
## the right and 18 px up, so the bar sits centred just above it.
const LYING_OFFSET := Vector2(42.0, -27.0)
const LYING_STATES: Array[Fighter.State] = [Fighter.State.DOWN, Fighter.State.KO]
const KO_TINT := Color(1.0, 1.0, 1.0, 0.4)

var _fighter: Fighter

@onready var _name: Label = $Name
@onready var _bar: ProgressBar = $Bar


func _ready() -> void:
	_fighter = get_parent() as Fighter
	_name.text = _fighter.player_name
	_name.add_theme_color_override(&"font_color", _fighter.color)
	_bar.max_value = _fighter.max_health
	_bar.value = _fighter.health
	var fill := StyleBoxFlat.new()
	fill.bg_color = _fighter.color
	_bar.add_theme_stylebox_override(&"fill", fill)
	_fighter.health_changed.connect(_on_health_changed)
	_fighter.knocked_out.connect(_on_knocked_out)
	_follow_fighter()


func _process(_delta: float) -> void:
	_follow_fighter()


func _follow_fighter() -> void:
	if _fighter.state in LYING_STATES:
		position = LYING_OFFSET
	else:
		position = Vector2(0.0, HEAD_OFFSET - _fighter.height)


func _on_health_changed(current: int, maximum: int) -> void:
	_bar.max_value = maximum
	_bar.value = current


func _on_knocked_out(_fighter_out: Fighter) -> void:
	_name.text = "KO"
	modulate = KO_TINT
