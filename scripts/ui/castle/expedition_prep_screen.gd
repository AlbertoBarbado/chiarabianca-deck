extends ScreenBase
## Expedition preparation for one mission (SceneRouter.mission_id): the sisters' specializations,
## prepared decks (and saved presets), worn gear, the potion belt, the heirloom relic and the bond
## relics they carry. "Set Out" starts the expedition (ExpeditionService.start) once nothing blocks it.

var _loadout: Dictionary = {}
var _problems_box: VBoxContainer
var _embark: Button
var _belt_label: Label
var _potion_rows: VBoxContainer


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.55


func _build() -> void:
	var campaign := GameState.campaign
	var mission := DataRegistry.get_mission(SceneRouter.mission_id)
	if campaign == null or mission.is_empty():
		SceneRouter.go.call_deferred(SceneRouter.Screen.CASTLE_HUB if campaign != null else SceneRouter.Screen.MAIN_MENU)
		return
	_loadout = Apothecary.default_loadout(campaign)
	var column := UIFactory.vbox(12)
	root.add_child(column)
	column.add_child(CastleUI.header("Prepare: " + str(mission["name"]), str(mission.get("description", "")), func() -> void: SceneRouter.go(SceneRouter.Screen.WORLD_MAP), "War Table"))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var content := UIFactory.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var objective := UIFactory.label("Objective: " + Objectives.describe(Objectives.create(mission, {"nodes": []})) if str(mission["objective"]["type"]) != Objectives.TYPE_CLEAR_TARGETS else "Objective: %s %d of %d %s, then head home." % [mission["objective"].get("verb", "Clear"), int(mission["objective"].get("required", 1)), int(mission["objective"].get("targets", 1)), mission["objective"].get("noun", "targets")], &"", true)
	objective.name = "ObjectiveText"
	content.add_child(objective)
	var sisters: BoxContainer = UIFactory.vbox(12) if CastleUI.is_narrow(self) else UIFactory.hbox(12)
	content.add_child(sisters)
	for member in campaign.roster.members:
		sisters.add_child(_sister_panel(member))
	var lower: BoxContainer = UIFactory.vbox(12) if CastleUI.is_narrow(self) else UIFactory.hbox(12)
	content.add_child(lower)
	lower.add_child(_potion_panel())
	lower.add_child(_relic_panel())
	_problems_box = UIFactory.vbox(4)
	_problems_box.name = "Problems"
	content.add_child(_problems_box)
	var footer := UIFactory.hbox(12)
	footer.add_child(UIFactory.expander())
	_embark = UIFactory.button("Set Out ›", true, Vector2(240, 60))
	_embark.name = "EmbarkButton"
	_embark.pressed.connect(_on_embark)
	footer.add_child(_embark)
	column.add_child(footer)
	_refresh_problems()


func _sister_panel(member: PartyMember) -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(8, member.definition.accent_color)
	panel.name = "Sister_" + member.id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	var top := UIFactory.hbox(12)
	var face := AvatarFrame.new()
	face.setup(member.id, 72.0, member.specialization.get_accent(member.definition.accent_color))
	top.add_child(face)
	var texts := UIFactory.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UIFactory.label(member.definition.display_name, &"HeaderLabel", false)
	name_label.add_theme_color_override("font_color", member.definition.accent_color)
	texts.add_child(name_label)
	var spec_text := member.specialization.display_name
	if member.secondary_specialization != null:
		spec_text += "  +  " + member.secondary_specialization.display_name + " (secondary)"
	texts.add_child(UIFactory.label(spec_text, &"", true))
	var cards := campaign.prepared_cards(member.id)
	var upgraded := cards.filter(func(o: OwnedCard) -> bool: return o.upgrade_level > 0).size()
	texts.add_child(UIFactory.label("Deck: %d cards (%d upgraded)   Gear: %d worn   HP %d" % [cards.size(), upgraded, member.equipment.size(), member.max_hp], &"DimLabel", true))
	top.add_child(texts)
	column.add_child(top)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	var deck := UIFactory.button("Deck Workshop", false, Vector2(0, 48))
	deck.name = "DeckButton_" + member.id
	deck.pressed.connect(func() -> void: SceneRouter.open_service("library"))
	buttons.add_child(deck)
	var gear := UIFactory.button("Armory", false, Vector2(0, 48))
	gear.pressed.connect(func() -> void: SceneRouter.open_equipment(SceneRouter.Screen.EXPEDITION_PREP))
	buttons.add_child(gear)
	if campaign.services.has("training_hall"):
		var training := UIFactory.button("Training Hall", false, Vector2(0, 48))
		training.pressed.connect(func() -> void: SceneRouter.open_service("training_hall"))
		buttons.add_child(training)
	column.add_child(buttons)
	if not campaign.presets.is_empty():
		var preset_row := UIFactory.hbox(8)
		preset_row.add_child(UIFactory.label("Deck preset:", &"DimLabel", false))
		var picker := OptionButton.new()
		picker.name = "PresetPicker_" + member.id
		picker.custom_minimum_size = Vector2(200, 44)
		picker.add_item("(current deck)")
		var names: Array = campaign.presets.keys()
		names.sort()
		for preset_name: String in names:
			picker.add_item(preset_name)
		picker.item_selected.connect(func(index: int) -> void:
			if index > 0:
				campaign.set_prepared(member.id, (campaign.presets[names[index - 1]] as Dictionary).get(member.id, []))
				GameState.save_game()
				SceneRouter.go(SceneRouter.Screen.EXPEDITION_PREP))
		preset_row.add_child(picker)
		column.add_child(preset_row)
	return panel


func _potion_panel() -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(6)
	panel.name = "PotionBelt"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	_belt_label = UIFactory.label("", &"", false)
	_belt_label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	column.add_child(_belt_label)
	_potion_rows = UIFactory.vbox(4)
	column.add_child(_potion_rows)
	var stored := Apothecary.stored_potions(campaign)
	if stored.is_empty():
		_potion_rows.add_child(UIFactory.label("No potions in the stores. Visit the Apothecary.", &"DimLabel", true))
	for item_id: String in stored:
		var row := UIFactory.hbox(8)
		row.name = "Potion_" + item_id
		var item := DataRegistry.get_item(item_id)
		var label := UIFactory.label("%s  (%d stored)" % [str(item.get("name", item_id)), int(stored[item_id])], &"", true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = str(item.get("description", ""))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		var minus := UIFactory.button("−", false, Vector2(52, 48))
		minus.name = "Less"
		minus.pressed.connect(_change_potion.bind(item_id, -1))
		row.add_child(minus)
		var count := UIFactory.label(str(int(_loadout.get(item_id, 0))), &"", false, HORIZONTAL_ALIGNMENT_CENTER)
		count.name = "Count"
		count.custom_minimum_size.x = 32
		row.add_child(count)
		var plus := UIFactory.button("+", false, Vector2(52, 48))
		plus.name = "More"
		plus.pressed.connect(_change_potion.bind(item_id, 1))
		row.add_child(plus)
		_potion_rows.add_child(row)
	_refresh_belt()
	return panel


func _change_potion(item_id: String, delta: int) -> void:
	var campaign := GameState.campaign
	var next := clampi(int(_loadout.get(item_id, 0)) + delta, 0, campaign.vault.count_of(item_id))
	var total := 0
	for id: String in _loadout:
		total += int(_loadout[id]) if id != item_id else 0
	if total + next > campaign.potion_capacity:
		CastleUI.toast(self, "The belt holds %d potions." % campaign.potion_capacity, false)
		return
	_loadout[item_id] = next
	_refresh_belt()
	_refresh_problems()


func _refresh_belt() -> void:
	var total := 0
	for item_id: String in _loadout:
		total += int(_loadout[item_id])
	_belt_label.text = "Potion belt: %d / %d" % [total, GameState.campaign.potion_capacity]
	for row in _potion_rows.get_children():
		if row.has_node("Count"):
			(row.get_node("Count") as Label).text = str(int(_loadout.get(str(row.name).trim_prefix("Potion_"), 0)))


func _relic_panel() -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(6)
	panel.name = "Relics"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label("Heirloom relic", &"", false)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	column.add_child(title)
	if campaign.relic_collection.is_empty():
		column.add_child(UIFactory.label("Relics found on expeditions can be carried from home, one at a time.", &"DimLabel", true))
	else:
		var picker := OptionButton.new()
		picker.name = "HeirloomPicker"
		picker.custom_minimum_size = Vector2(240, 44)
		picker.add_item("None")
		for i in campaign.relic_collection.size():
			var relic_id := campaign.relic_collection[i]
			picker.add_item(str(DataRegistry.get_item(relic_id).get("name", relic_id)))
			if relic_id == campaign.heirloom:
				picker.select(i + 1)
		picker.item_selected.connect(func(index: int) -> void:
			campaign.heirloom = "" if index == 0 else campaign.relic_collection[index - 1]
			GameState.save_game())
		column.add_child(picker)
		if campaign.heirloom != "":
			column.add_child(UIFactory.label(str(DataRegistry.get_item(campaign.heirloom).get("description", "")), &"DimLabel", true))
	var bond_relics := Bond.relics(campaign)
	if not bond_relics.is_empty():
		var names: Array[String] = []
		for relic_id in bond_relics:
			names.append(str(DataRegistry.get_item(relic_id).get("name", relic_id)))
		column.add_child(UIFactory.label("Bond relics (always carried): " + ", ".join(names), &"", true))
	return panel


func _refresh_problems() -> void:
	UIFactory.clear_children(_problems_box)
	var problems := ExpeditionService.departure_problems(GameState.campaign, SceneRouter.mission_id, _loadout)
	for problem in problems:
		var label := UIFactory.label("• " + problem, &"", true)
		label.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.3))
		_problems_box.add_child(label)
	if _embark != null:
		_embark.disabled = not problems.is_empty()


func _on_embark() -> void:
	var error := ExpeditionService.start(SceneRouter.mission_id, _loadout)
	if error != "":
		CastleUI.toast(self, error, false)
		return
	SceneRouter.go(SceneRouter.Screen.MAP)
