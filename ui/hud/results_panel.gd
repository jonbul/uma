class_name ResultsPanel
extends PanelContainer
## Round results shown during the match's result phase: placement, the
## player's name in their colour, and their wins so far this session.

@onready var _rows: VBoxContainer = %Rows


## `rows` is [{name, color, wins}] in placement order, winner first.
func show_results(rows: Array[Dictionary]) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 24)
		var player := Label.new()
		player.text = "%d.  %s" % [i + 1, row["name"]]
		player.add_theme_color_override(&"font_color", row["color"])
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var wins := Label.new()
		wins.text = "%d %s" % [row["wins"], "win" if row["wins"] == 1 else "wins"]
		line.add_child(player)
		line.add_child(wins)
		_rows.add_child(line)
	show()
	MenuFx.intro(self)
