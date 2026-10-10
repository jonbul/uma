class_name MenuFx
extends RefCounted
## Small shared menu effects: panels fading in, buttons popping when they
## get focus (so keyboard and gamepad players see where they are), and a
## neon flicker for titles. Static; call from a menu's _ready().


## Fades and scales `panel` in, and makes every button under it pop on focus.
static func intro(panel: Control) -> void:
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	# Containers size the panel after this frame; scale from its centre.
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size / 2.0)
	var tween := panel.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.18)
	for button in panel.find_children("*", "BaseButton", true, false):
		pop_on_focus(button as Control)


static func pop_on_focus(control: Control) -> void:
	control.focus_entered.connect(func() -> void:
		control.pivot_offset = control.size / 2.0
		var tween := control.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		control.scale = Vector2(1.06, 1.06)
		tween.tween_property(control, "scale", Vector2.ONE, 0.15)
	)


## Neon sign look: pink glow, and every few seconds a quick flicker.
static func neon(label: Label) -> void:
	label.add_theme_color_override(&"font_color", Color(1.0, 0.45, 0.78))
	label.add_theme_color_override(&"font_outline_color", Color(0.45, 0.05, 0.28))
	label.add_theme_constant_override(&"outline_size", 4)
	label.add_theme_color_override(&"font_shadow_color", Color(1.0, 0.3, 0.7, 0.55))
	label.add_theme_constant_override(&"shadow_offset_x", 0)
	label.add_theme_constant_override(&"shadow_offset_y", 0)
	label.add_theme_constant_override(&"shadow_outline_size", 14)
	_flicker_later(label)


static func _flicker_later(label: Label) -> void:
	if not label.is_inside_tree():
		return
	label.get_tree().create_timer(randf_range(2.0, 5.0)).timeout.connect(func() -> void:
		if not is_instance_valid(label) or not label.is_inside_tree():
			return
		var tween := label.create_tween()
		for i in randi_range(1, 3):
			tween.tween_property(label, "modulate:a", 0.45, 0.04)
			tween.tween_property(label, "modulate:a", 1.0, 0.07)
		tween.finished.connect(_flicker_later.bind(label))
	)
