extends Node2D
## Placeholder art for the bar until there are sprites: wallpaper, mirror,
## shelves of bottles, the counter, a door, a neon sign and a wooden floor.
## Everything here is behind the fighters; things they can walk around are
## separate prop scenes.

const WIDTH := 1280.0
const HEIGHT := 720.0
## Where the floor starts; the stage's top wall keeps fighters below it.
const FLOOR_Y := 280.0

const WALLPAPER := Color(0.32, 0.12, 0.12)
const WALLPAPER_STRIPE := Color(0.36, 0.15, 0.14)
const WAINSCOT := Color(0.22, 0.13, 0.08)
const WAINSCOT_TRIM := Color(0.3, 0.19, 0.11)
const MIRROR := Color(0.45, 0.52, 0.55)
const MIRROR_FRAME := Color(0.55, 0.42, 0.2)
const SHELF := Color(0.4, 0.26, 0.14)
const BOTTLE_COLORS: Array[Color] = [
	Color(0.2, 0.45, 0.2), Color(0.55, 0.3, 0.1), Color(0.75, 0.75, 0.7),
	Color(0.15, 0.3, 0.5), Color(0.6, 0.15, 0.15), Color(0.8, 0.6, 0.2),
]
const COUNTER_TOP := Color(0.45, 0.28, 0.15)
const COUNTER_FRONT := Color(0.28, 0.16, 0.09)
const COUNTER_PANEL := Color(0.24, 0.13, 0.07)
const DOOR := Color(0.25, 0.15, 0.08)
const DOOR_PANEL := Color(0.2, 0.11, 0.06)
const KNOB := Color(0.8, 0.65, 0.25)
const NEON := Color(1.0, 0.35, 0.7)
const FLOOR := Color(0.36, 0.24, 0.14)
const FLOOR_LINE := Color(0.29, 0.19, 0.11)
const FLOOR_SHADOW := Color(0.0, 0.0, 0.0, 0.25)

const PLANK_HEIGHT := 40
const PLANK_LENGTH := 160

const COUNTER := Rect2(160, 190, 760, 90)
const MIRROR_RECT := Rect2(240, 24, 600, 120)
const DOOR_RECT := Rect2(1050, 60, 120, 220)


func _draw() -> void:
	_draw_wall()
	_draw_shelves()
	_draw_counter()
	_draw_door()
	_draw_sign()
	_draw_floor()


func _draw_wall() -> void:
	draw_rect(Rect2(0, 0, WIDTH, FLOOR_Y), WALLPAPER)
	for x in range(0, int(WIDTH), 48):
		draw_rect(Rect2(x, 0, 16, 180), WALLPAPER_STRIPE)
	draw_rect(Rect2(0, 180, WIDTH, FLOOR_Y - 180), WAINSCOT)
	draw_rect(Rect2(0, 180, WIDTH, 6), WAINSCOT_TRIM)
	draw_rect(MIRROR_RECT.grow(6), MIRROR_FRAME)
	draw_rect(MIRROR_RECT, MIRROR)


func _draw_shelves() -> void:
	for shelf_y: int in [80, 140]:
		draw_rect(Rect2(MIRROR_RECT.position.x, shelf_y, MIRROR_RECT.size.x, 6), SHELF)
		var i := 0
		for x in range(int(MIRROR_RECT.position.x) + 12, int(MIRROR_RECT.end.x) - 12, 22):
			# Varied but fixed heights, so the shelves look stocked.
			var bottle_height := 22 + (i * 7 + shelf_y) % 14
			var color := BOTTLE_COLORS[(i + shelf_y) % BOTTLE_COLORS.size()]
			draw_rect(Rect2(x, shelf_y - bottle_height, 10, bottle_height), color)
			draw_rect(Rect2(x + 3, shelf_y - bottle_height - 8, 4, 8), color)
			i += 1


func _draw_counter() -> void:
	draw_rect(Rect2(COUNTER.position, Vector2(COUNTER.size.x, 18)), COUNTER_TOP)
	var front := Rect2(COUNTER.position + Vector2(0, 18), COUNTER.size - Vector2(0, 18))
	draw_rect(front, COUNTER_FRONT)
	for x in range(int(front.position.x) + 12, int(front.end.x) - 60, 76):
		draw_rect(Rect2(x, front.position.y + 10, 60, front.size.y - 20), COUNTER_PANEL)


func _draw_door() -> void:
	draw_rect(DOOR_RECT, DOOR)
	draw_rect(Rect2(DOOR_RECT.position + Vector2(14, 14), Vector2(92, 80)), DOOR_PANEL)
	draw_rect(Rect2(DOOR_RECT.position + Vector2(14, 110), Vector2(92, 96)), DOOR_PANEL)
	draw_rect(Rect2(DOOR_RECT.position + Vector2(96, 112), Vector2(10, 10)), KNOB)


func _draw_sign() -> void:
	# The project theme's font (the pixel font), like the rest of the UI.
	var theme := ThemeDB.get_project_theme()
	var font: Font = theme.default_font if theme and theme.default_font else ThemeDB.fallback_font
	# Centred in the gap between the mirror and the door.
	draw_string(font, Vector2(850, 120), "AMURRIO", HORIZONTAL_ALIGNMENT_CENTER, 200, 32, NEON)
	draw_string(font, Vector2(850, 160), "BAR", HORIZONTAL_ALIGNMENT_CENTER, 200, 40, NEON)


func _draw_floor() -> void:
	draw_rect(Rect2(0, FLOOR_Y, WIDTH, HEIGHT - FLOOR_Y), FLOOR)
	var row := 0
	for y in range(int(FLOOR_Y), int(HEIGHT), PLANK_HEIGHT):
		draw_line(Vector2(0, y), Vector2(WIDTH, y), FLOOR_LINE, 2.0)
		# Stagger the plank joints row by row.
		var offset := (row % 3) * (PLANK_LENGTH / 3)
		for x in range(offset, int(WIDTH), PLANK_LENGTH):
			draw_line(Vector2(x, y), Vector2(x, y + PLANK_HEIGHT), FLOOR_LINE, 2.0)
		row += 1
	# Shade along the back wall.
	draw_rect(Rect2(0, FLOOR_Y, WIDTH, 12), FLOOR_SHADOW)
