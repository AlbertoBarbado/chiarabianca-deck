extends ScreenBase
## Party overview: both characters, HP, specialization, deck size and an inspectable card list.

var _inspect_layer: Control


func _build() -> void:
	var column := UIFactory.vbox(10)
	root.add_child(column)
	var heading := SectionHeading.new()
	heading.setup("Party Overview")
	column.add_child(heading)
	var total := GameState.party.get_total_deck_size()
	column.add_child(UIFactory.label("Each princess owns her own cards. In battle all %d cards are shuffled into one shared party deck. Tap a card to inspect it." % total, &"DimLabel", true))

	var row := UIFactory.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for member in GameState.party.members:
		row.add_child(_build_member_column(member))

	var footer := make_footer(SceneRouter.Screen.SPECIALIZATION_SELECTION)
	var start := UIFactory.button("Enter the Royal Castle", true, Vector2(300, 56))
	start.pressed.connect(_on_start)
	footer.add_child(start)
	column.add_child(footer)


func _build_member_column(member: PartyMember) -> Control:
	var column := UIFactory.vbox(8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel := CharacterPanel.new()
	panel.setup(member.definition, {
		"specialization": member.specialization,
		"hp": member.current_hp,
		"max_hp": member.max_hp,
		"compact": true,
		"extra": "Individual deck: %d cards" % member.deck.size(),
	})
	column.add_child(panel)

	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	for entry in DeckViewer.group_deck(member):
		flow.add_child(_make_card_stack(member, entry))
	return column


func _make_card_stack(member: PartyMember, entry: Dictionary) -> Control:
	var owned: OwnedCard = entry["owned"]
	var box := UIFactory.vbox(2)
	var view := CardView.new()
	view.show_owned(DataRegistry.get_card(owned.card_id), member.id, owned.upgrade_level)
	view.pressed.connect(func(_v: CardView) -> void: _inspect(member, owned, entry["count"]))
	box.add_child(view)
	box.add_child(UIFactory.label("× %d" % entry["count"], &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	return box


func _inspect(member: PartyMember, owned: OwnedCard, count: int) -> void:
	if _inspect_layer != null:
		_inspect_layer.queue_free()
	var def := DataRegistry.get_card(owned.card_id)
	_inspect_layer = ColorRect.new()
	(_inspect_layer as ColorRect).color = Color(0, 0, 0, 0.7)
	UIFactory.full_rect(_inspect_layer)
	_inspect_layer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_inspect_layer.queue_free())
	add_child(_inspect_layer)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_layer.add_child(center)
	var row := UIFactory.hbox(24)
	center.add_child(row)
	var view := CardView.new()
	view.show_owned(def, member.id, owned.upgrade_level)
	view.set_scale_factor(1.6)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(view)
	var info := UIFactory.panel()
	info.custom_minimum_size.x = 320
	var details := UIFactory.vbox(6)
	info.add_child(details)
	details.add_child(UIFactory.label(def.display_name, &"HeaderLabel", true))
	details.add_child(UIFactory.label("Owner: %s (%s)" % [member.definition.display_name, member.specialization.display_name]))
	details.add_child(UIFactory.label("Type: %s · Cost: %d · Target: %s" % [def.card_type.capitalize(), def.cost, def.target.replace("_", " ")], &"DimLabel", true))
	details.add_child(UIFactory.label(def.description, &"", true))
	details.add_child(UIFactory.label("Upgrade level: %d · Copies in deck: %d" % [owned.upgrade_level, count], &"DimLabel", true))
	details.add_child(UIFactory.label("Tap anywhere to close.", &"DimLabel"))
	row.add_child(info)


func _on_start() -> void:
	if GameState.begin_adventure():
		SceneRouter.go(SceneRouter.Screen.MAP)


func _menu_screen() -> bool:
	return true
