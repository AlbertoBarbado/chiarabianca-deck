extends ScreenBase
## Tutorial completion / defeat screen: castle backdrop, both princesses at the sides and an ornate
## central panel with the result, the party status (HP per princess), gold and two actions.

const PANEL_WIDTH := 520.0
const CHIARA_HEIGHT_SHARE := 0.66
const BIANCA_HEIGHT_SHARE := 0.66

var _stage: Control
var _chiara: CharacterShowcase
var _bianca: CharacterShowcase


func _menu_screen() -> bool:
	return true


func _build() -> void:
	var won := GameState.run_result == GameState.RESULT_COMPLETED
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stage)
	_chiara = CharacterShowcase.new()
	_stage.add_child(_chiara)
	_chiara.setup("chiara", DataRegistry.get_character("chiara").accent_color, -1, 0.1)
	_bianca = CharacterShowcase.new()
	_stage.add_child(_bianca)
	_bianca.setup("bianca", DataRegistry.get_character("bianca").accent_color, 1, 0.2)
	if not won:  # The fallen princesses are shown subdued.
		_chiara.self_modulate = Color(0.55, 0.55, 0.62)
		_bianca.self_modulate = Color(0.55, 0.55, 0.62)
	_stage.resized.connect(_layout_characters)
	_layout_characters()

	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)
	var column := UIFactory.vbox(8)
	panel.add_child(column)

	var heading := SectionHeading.new()
	var completion: Dictionary = GameState.map_progress.graph.completion if GameState.map_progress != null else {}
	heading.setup(str(completion.get("title", "Tutorial Complete")) if won else "Defeated", true)
	column.add_child(heading)
	if won:
		column.add_child(UIFactory.label(str(completion.get("text", "Chiara and Bianca step through the Castle Gate together. The road beyond awaits...")), &"", true, HORIZONTAL_ALIGNMENT_CENTER))
		if GameState.inventory != null and not GameState.inventory.relics.is_empty():
			var relic_row := HFlowContainer.new()
			relic_row.name = "RunRelics"
			relic_row.alignment = FlowContainer.ALIGNMENT_CENTER
			relic_row.add_theme_constant_override("h_separation", 8)
			for relic_id in GameState.inventory.relics:
				relic_row.add_child(RelicIcon.create(relic_id, 40))  # hover: name and effect
			column.add_child(relic_row)
		column.add_child(UIFactory.label("Deck: %d cards" % GameState.party.get_total_deck_size(), &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
		for member in GameState.party.members:
			var status := CharacterStatusPanel.new()
			status.setup(member.definition, {"specialization": member.specialization, "hp": member.current_hp, "max_hp": member.max_hp})
			column.add_child(status)
		var gold := GoldDisplay.new()
		gold.setup(GameState.inventory.gold)
		gold.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(gold)
	else:
		column.add_child(UIFactory.label("Both princesses have fallen. Rest, regroup and try again.", &"", true, HORIZONTAL_ALIGNMENT_CENTER))

	var actions := UIFactory.hbox(12)
	column.add_child(actions)
	var again := UIFactory.button("New Game", true, Vector2(0, 56))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func() -> void:
		GameState.reset_selection()
		SceneRouter.go(SceneRouter.Screen.CHARACTER_SELECTION))
	actions.add_child(again)
	var menu := UIFactory.button("Main Menu", false, Vector2(0, 56))
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAIN_MENU))
	actions.add_child(menu)
	again.grab_focus.call_deferred()


func _layout_characters() -> void:
	var area := _stage.size
	for entry in [[_chiara, "chiara", CHIARA_HEIGHT_SHARE, 0], [_bianca, "bianca", BIANCA_HEIGHT_SHARE, 1]]:
		var showcase: CharacterShowcase = entry[0]
		var texture := AssetCatalog.figure(entry[1])
		var height := area.y * float(entry[2])
		var width := height * (texture.get_width() / float(texture.get_height()) if texture != null else 0.8)
		showcase.size = Vector2(width, height)
		showcase.position = Vector2(0.0 if entry[3] == 0 else area.x - width, area.y - height)
