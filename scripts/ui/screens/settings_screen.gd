extends ScreenBase
## Settings: master volume, fullscreen and the combat effects quality (Full / Reduced / Off).
## Applied and saved immediately.

const PANEL_WIDTH := 560.0
const QUALITY_LEVELS: Array[String] = ["full", "reduced", "off"]

var _values: Dictionary


func _menu_screen() -> bool:
	return true


func _build() -> void:
	_values = SettingsStore.load_values()
	var center := CenterContainer.new()
	root.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)
	var column := UIFactory.vbox(14)
	panel.add_child(column)
	var heading := SectionHeading.new()
	heading.setup("Settings")
	column.add_child(heading)

	column.add_child(_row_title("sound", "Master volume"))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _values["volume"]
	slider.custom_minimum_size = Vector2(0, 40)
	slider.value_changed.connect(func(v: float) -> void: _set_value("volume", v))
	column.add_child(slider)

	column.add_child(_row_title("settings", "Display"))
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = _values["fullscreen"]
	fullscreen.custom_minimum_size = Vector2(0, 52)
	fullscreen.toggled.connect(func(on: bool) -> void: _set_value("fullscreen", on))
	column.add_child(fullscreen)

	column.add_child(_row_title("flame", "Combat effects"))
	var quality := OptionButton.new()
	for level in QUALITY_LEVELS:
		quality.add_item(level.capitalize())
	quality.selected = maxi(0, QUALITY_LEVELS.find(str(_values.get("effects_quality", "full"))))
	quality.custom_minimum_size = Vector2(0, 52)
	quality.item_selected.connect(func(index: int) -> void: _set_value("effects_quality", QUALITY_LEVELS[index]))
	column.add_child(quality)
	column.add_child(UIFactory.label("Also scales the menu particles and slide-in animations.", &"DimLabel", true))

	var back := UIFactory.button("Back", false, Vector2(0, 56))
	back.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAIN_MENU))
	column.add_child(back)


## Row heading: extracted gold icon (sound, gear, flame) plus the setting name.
func _row_title(icon_name: String, text: String) -> Control:
	var row := UIFactory.hbox(10)
	var texture := UIAssets.icon(icon_name)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(32, 32)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var label := UIFactory.label(text, &"HeaderLabel")
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _set_value(key: String, value: Variant) -> void:
	_values[key] = value
	SettingsStore.apply(_values)
	SettingsStore.save_values(_values)
