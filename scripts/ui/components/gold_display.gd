class_name GoldDisplay
extends HBoxContainer
## Gold coin icon plus "Gold: N" (the amount is also readable by tests and screen readers as text).

const ICON_SIZE := 34


func setup(amount: int, icon_size: int = ICON_SIZE) -> void:
	UIFactory.clear_children(self)
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := UIAssets.icon("gold")
	if coin != null:
		var rect := TextureRect.new()
		rect.texture = coin
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(icon_size, icon_size)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
	else:
		add_child(UIFactory.icon("gold", icon_size))
	var label := UIFactory.label("Gold: %d" % amount, &"")
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
