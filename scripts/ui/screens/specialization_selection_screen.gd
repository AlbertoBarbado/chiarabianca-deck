extends ScreenBase
## One specialization per character. Every specialization can be inspected; only those with
## a real starting deck ("playable") allow the party to be confirmed.

var _detail_boxes: Dictionary = {}  # character_id -> VBoxContainer
var _portraits: Dictionary = {}     # character_id -> AvatarFrame
var _spec_buttons: Dictionary = {}  # character_id -> {spec_id: Button}
var _confirm: Button
var _hint: Label
var _combo_banner: Label


func _build() -> void:
	var column := UIFactory.vbox(10)
	root.add_child(column)
	var heading := SectionHeading.new()
	heading.setup("Choose Specializations")
	column.add_child(heading)

	var row := UIFactory.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for character_id in GameConfig.INITIAL_PARTY_IDS:
		var char_def := DataRegistry.get_character(character_id)
		if char_def != null:
			row.add_child(_build_column(char_def))

	var footer := make_footer(SceneRouter.Screen.CHARACTER_SELECTION)
	_hint = UIFactory.label("", &"DimLabel")
	footer.add_child(_hint)
	# Twin combo of the chosen pair, e.g. "Twin combo ★★★ Combustion: ...".
	_combo_banner = UIFactory.label("", &"", true)
	_combo_banner.name = "ComboBanner"
	_combo_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combo_banner.add_theme_color_override("font_color", UITheme.GOLD)
	_combo_banner.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	footer.add_child(_combo_banner)
	_confirm = UIFactory.button("Confirm Party", true, Vector2(240, 56))
	_confirm.pressed.connect(_on_confirm)
	footer.add_child(_confirm)
	column.add_child(footer)
	_update_confirm()


func _build_column(char_def: CharacterDef) -> Control:
	var panel := UIFactory.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UIFactory.vbox(8)
	panel.add_child(column)
	var title_row := UIFactory.hbox(12)
	var portrait := AvatarFrame.new()
	portrait.setup(char_def.id, 84.0, char_def.accent_color)
	_portraits[char_def.id] = portrait
	title_row.add_child(portrait)
	var title := UIFactory.label("%s — %s" % [char_def.display_name, char_def.role.capitalize()], &"")
	title.add_theme_color_override("font_color", char_def.accent_color)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	column.add_child(title_row)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	var group := ButtonGroup.new()
	_spec_buttons[char_def.id] = {}
	for spec in DataRegistry.get_specializations_for(char_def.id):
		var button := UIFactory.button(spec.display_name, false, Vector2(110, 52))
		button.toggle_mode = true
		button.theme_type_variation = &"ToggleButton"
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		CastleUI.chip_style(button)  # rectangular enamel chips: six names fit in three columns
		button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON)
		var spec_icon := AssetCatalog.icon_by_id(spec.icon_id)
		if spec_icon != null:
			button.icon = spec_icon
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 28)
		button.pressed.connect(_on_spec_chosen.bind(char_def.id, spec.id))
		grid.add_child(button)
		_spec_buttons[char_def.id][spec.id] = button

	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var details := UIFactory.vbox(6)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	_detail_boxes[char_def.id] = details
	details.add_child(UIFactory.label("Select a specialization to see its identity and starting deck.", &"DimLabel", true))
	return panel


func _on_spec_chosen(character_id: String, spec_id: String) -> void:
	GameState.select_specialization(character_id, spec_id)
	_show_details(character_id, DataRegistry.get_specialization(spec_id))
	_update_confirm()


func _show_details(character_id: String, spec: SpecializationDef) -> void:
	var box: VBoxContainer = _detail_boxes[character_id]
	UIFactory.clear_children(box)
	var char_def := DataRegistry.get_character(character_id)
	(_portraits[character_id] as AvatarFrame).setup(char_def.id, 84.0, spec.get_accent(char_def.accent_color))
	var name_row := UIFactory.hbox(8)
	if spec.icon_id != "":
		name_row.add_child(UIFactory.icon_by_id(spec.icon_id, 34))
	var name_label := UIFactory.label(spec.display_name, &"HeaderLabel")
	name_label.add_theme_color_override("font_color", spec.get_accent(char_def.accent_color))
	name_row.add_child(name_label)
	box.add_child(name_row)
	box.add_child(UIFactory.label(spec.description, &"", true))
	if spec.has_passive():
		var passive_label := UIFactory.label("Passive — %s: %s" % [spec.passive.get("name", ""), spec.passive.get("description", "")], &"", true)
		passive_label.add_theme_color_override("font_color", UITheme.GOLD)
		box.add_child(passive_label)
	else:
		box.add_child(UIFactory.label("Passive: to be designed", &"DimLabel", true))
	_add_combo_lines(box, character_id, spec)
	for keyword in spec.keywords:
		var status_def := DataRegistry.get_status(keyword)
		if status_def != null:
			box.add_child(UIFactory.label("%s: %s" % [status_def.display_name, status_def.describe(3)], &"DimLabel", true))
	if not spec.is_playable():
		box.add_child(UIFactory.label("Coming soon: this specialization's cards are not designed yet, so it cannot be taken into the castle.", &"DimLabel", true))
		return
	box.add_child(UIFactory.label("Starting deck (%d cards)" % spec.starting_deck_card_ids.size(), &""))
	for entry in spec.get_deck_summary():
		var card := DataRegistry.get_card(entry["card_id"])
		if card != null:
			var line := "%d× %s  [cost %d] — %s" % [entry["count"], card.display_name, card.cost, card.description]
			box.add_child(UIFactory.label(line, &"DimLabel", true))
	if not spec.card_pool.is_empty():
		var names: Array[String] = []
		for card_id in spec.card_pool:
			var pool_card := DataRegistry.get_card(card_id)
			if pool_card != null:
				names.append("%s (%d)" % [pool_card.display_name, pool_card.cost])
		box.add_child(UIFactory.label("Card rewards: " + ", ".join(names), &"DimLabel", true))


## "Twin combos": how this specialization works with each of the other princess's playable ones.
func _add_combo_lines(box: VBoxContainer, character_id: String, spec: SpecializationDef) -> void:
	var combos := TwinCombos.for_spec(spec.id)
	if combos.is_empty():
		return
	var other_id := "bianca" if character_id == "chiara" else "chiara"
	var other_name := DataRegistry.get_character(other_id).display_name
	var header := UIFactory.label("Twin combos with %s" % other_name, &"")
	header.add_theme_color_override("font_color", UITheme.GOLD)
	box.add_child(header)
	for combo: Dictionary in combos:
		var partner := DataRegistry.get_specialization(str(combo.get(other_id, "")))
		if partner == null:
			continue
		var line := UIFactory.label("%s  %s + %s — %s: %s" % [TwinCombos.stars(combo), spec.display_name, partner.display_name,
			combo.get("name", ""), combo.get("text", "")], &"DimLabel", true)
		line.name = "Combo_%s_%s" % [combo.get("chiara", ""), combo.get("bianca", "")]
		if int(combo.get("strength", 0)) >= 3:
			line.add_theme_color_override("font_color", UITheme.IVORY)
		box.add_child(line)


func _update_combo_banner() -> void:
	var chiara := str(GameState.selected_specializations.get("chiara", ""))
	var bianca := str(GameState.selected_specializations.get("bianca", ""))
	var combo := TwinCombos.for_pair(chiara, bianca)
	_combo_banner.text = "" if combo.is_empty() else "Twin combo %s %s — %s" % [TwinCombos.stars(combo), combo.get("name", ""), combo.get("text", "")]


func _update_confirm() -> void:
	_update_combo_banner()
	var ready := GameState.can_confirm_selection()
	_confirm.disabled = not ready
	if ready:
		_hint.text = ""
	elif GameState.selected_specializations.size() < GameConfig.INITIAL_PARTY_IDS.size():
		_hint.text = "Choose a specialization for each princess."
	else:
		_hint.text = "Pick a playable specialization for both princesses (some are still coming soon)."


func _on_confirm() -> void:
	if GameState.create_party_from_selection():
		SceneRouter.go(SceneRouter.Screen.PARTY_OVERVIEW)


func _menu_screen() -> bool:
	return true
