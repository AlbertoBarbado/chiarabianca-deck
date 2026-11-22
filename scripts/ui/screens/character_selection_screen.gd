extends ScreenBase
## Shows the two starting characters (the party is fixed at this stage): a large illustration in an
## ornate card with name, role, health, appearance, story and the specializations she can learn.


func _menu_screen() -> bool:
	return true


func _build() -> void:
	var column := UIFactory.vbox(10)
	root.add_child(column)
	var heading := SectionHeading.new()
	heading.setup("Your Party")
	column.add_child(heading)
	var intro := UIFactory.label("Twin princesses of the royal house. Both will fight together in a shared deck.", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	intro.add_theme_color_override("font_outline_color", Color(UITheme.NAVY_DEEP, 0.9))
	intro.add_theme_constant_override("outline_size", 6)
	column.add_child(intro)

	var row := UIFactory.hbox(22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var index := 0
	for character_id in GameConfig.INITIAL_PARTY_IDS:
		var char_def := DataRegistry.get_character(character_id)
		if char_def != null:
			row.add_child(_make_card(char_def, index))
			index += 1

	var footer := make_footer(SceneRouter.Screen.MAIN_MENU)
	var next := UIFactory.button("Choose Specializations", true, Vector2(340, 58))
	next.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.SPECIALIZATION_SELECTION))
	footer.add_child(next)
	column.add_child(footer)


func _make_card(char_def: CharacterDef, index: int) -> Control:
	var card := UIFactory.panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := UIFactory.hbox(24)  # clear space between the picture and the text
	card.add_child(content)

	var showcase := CharacterShowcase.new()
	showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The picture box widens with the window (half the card picture, half text) and both figures fit
	# it whole, so nothing is clipped against the text at any size.
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.custom_minimum_size = Vector2(230, 300)
	content.add_child(showcase)
	showcase.setup(char_def.id, char_def.accent_color, -1 if index == 0 else 1, 0.1 + 0.15 * index, false)

	var info := UIFactory.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(info)
	var name_label := UIFactory.label(char_def.display_name, &"HeaderLabel")
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER + 6)
	name_label.add_theme_color_override("font_color", char_def.accent_color.lightened(0.2))
	info.add_child(name_label)
	info.add_child(UIFactory.label("%s · %s" % [char_def.title, char_def.role.capitalize()], &"DimLabel", true))
	info.add_child(UIFactory.hp_bar(char_def.starting_hp, char_def.max_hp))
	var hp_row := UIFactory.hbox(6)
	hp_row.add_child(_heart(22))
	hp_row.add_child(UIFactory.label("HP %d / %d" % [char_def.starting_hp, char_def.max_hp], &"DimLabel"))
	info.add_child(hp_row)
	info.add_child(UIFactory.label("Hair: %s" % char_def.hair.capitalize()))
	info.add_child(UIFactory.label("Eyes: %s" % char_def.eyes.capitalize()))
	info.add_child(UIFactory.label(char_def.story, &"DimLabel", true))
	info.add_child(_make_specializations(char_def))
	return card


func _heart(icon_size: int) -> Control:
	var heart := UIAssets.icon("heart")
	if heart == null:
		return UIFactory.icon("health", icon_size)
	var rect := TextureRect.new()
	rect.texture = heart
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(icon_size, icon_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The specializations she can take into the castle, with their icons (data-driven).
func _make_specializations(char_def: CharacterDef) -> Control:
	var box := UIFactory.vbox(4)
	var title := UIFactory.label("Specializations in this adventure", &"DimLabel")
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	box.add_child(title)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	for spec in DataRegistry.get_specializations_for(char_def.id):
		if not spec.is_playable():
			continue
		var chip := UIFactory.hbox(6)
		if spec.icon_id != "":
			chip.add_child(UIFactory.icon_by_id(spec.icon_id, 26))
		var label := UIFactory.label(spec.display_name, &"")
		label.add_theme_color_override("font_color", spec.get_accent(char_def.accent_color).lightened(0.25))
		chip.add_child(label)
		flow.add_child(chip)
	box.add_child(flow)
	return box
