extends ScreenBase
## Shown when the party reaches the exit of a map that has a next act: summarises what carries over
## (party, HP, decks, gold) and leads into the next map. Nothing is reset here; GameState only
## swaps the map. Quitting on this screen and continuing later returns to it.


func _menu_screen() -> bool:
	return true


func _build() -> void:
	var graph := GameState.map_progress.graph
	var next_def := DataRegistry.get_map(GameState.next_map_after_current())
	var center := CenterContainer.new()
	root.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var column := UIFactory.vbox(10)
	panel.add_child(column)
	var heading := SectionHeading.new()
	heading.setup(str(graph.completion.get("title", "%s Complete" % graph.display_name)), true)
	column.add_child(heading)
	column.add_child(UIFactory.label(str(graph.completion.get("text", "The road leads onward.")), &"", true, HORIZONTAL_ALIGNMENT_CENTER))
	for member in GameState.party.members:
		var status := CharacterStatusPanel.new()
		status.setup(member.definition, {"specialization": member.specialization, "hp": member.current_hp, "max_hp": member.max_hp})
		column.add_child(status)
	var gold := GoldDisplay.new()
	gold.setup(GameState.inventory.gold)
	gold.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(gold)
	column.add_child(UIFactory.label("Your party, health, decks, upgrades, gold and items carry over.", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER))
	var next_name := str(next_def.get("name", "the next region"))
	var onward := UIFactory.button("Enter %s" % next_name, true, Vector2(0, 60))
	onward.name = "EnterNextAct"
	onward.pressed.connect(_on_enter)
	column.add_child(onward)
	var subtitle := str(next_def.get("subtitle", ""))
	if subtitle != "":
		column.add_child(UIFactory.label(subtitle, &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))


func _on_enter() -> void:
	if GameState.advance_to_next_map():
		SceneRouter.go(SceneRouter.Screen.MAP)
