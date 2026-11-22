extends ScreenBase
## Treasure room: pick exactly one of the offered rewards (gold, potion, relic, card). The offer is
## rolled once and kept in the saved room state, so reloading shows the same choices and a claimed
## treasure can never be claimed again. Logic lives in TreasureRoom; this screen only presents it.

var _state: Dictionary = {}
var _message: Label
var _choice_box: VBoxContainer
var _leave: Button
var _scroll: ScrollContainer


func _build() -> void:
	var node := GameState.get_current_node()
	if GameState.room_matches(node.id, "treasure") and GameState.room_state.has("choices"):
		_state = GameState.room_state  # Resumed: same offer, same "taken" flag.
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_state = TreasureRoom.generate(node.treasure_id, GameState.party, GameState.inventory, rng)
		GameState.update_room(_state)
		_state = GameState.room_state
	var def := DataRegistry.get_treasure(node.treasure_id)
	# Layout: the panel (choices scroll inside it when the window is short) and, below it, a footer
	# that is ALWAYS on screen with the result line and the Continue / Leave button.
	var page := UIFactory.vbox(10)
	root.add_child(page)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = 760
	center.add_child(panel)
	var column := UIFactory.vbox(10)
	panel.add_child(column)
	var heading := SectionHeading.new()
	heading.setup(str(def.get("name", node.display_name)), true)
	column.add_child(heading)
	column.add_child(UIFactory.label(str(def.get("description", "Choose one reward.")), &"", true, HORIZONTAL_ALIGNMENT_CENTER))
	var hint := UIFactory.label("Choose one", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_color_override("font_color", UITheme.GOLD)
	column.add_child(hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 0)
	column.add_child(_scroll)
	_choice_box = UIFactory.vbox(8)
	_choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_choice_box)
	var footer := UIFactory.hbox(16)
	footer.name = "TreasureFooter"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(footer)
	_message = UIFactory.label("", &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	_message.name = "TreasureMessage"
	_message.add_theme_color_override("font_color", UITheme.GOLD)
	_message.custom_minimum_size.x = 420
	footer.add_child(_message)
	_leave = UIFactory.button("Return to Map", true, Vector2(300, 60))
	_leave.name = "TreasureLeave"
	_leave.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAP))
	footer.add_child(_leave)
	resized.connect(_fit_scroll)
	_fit_scroll.call_deferred()
	_refresh()


## The choice list gets the height that is left on screen; it scrolls only when it does not fit.
func _fit_scroll() -> void:
	if _scroll == null or _choice_box == null:
		return
	var wanted := _choice_box.get_combined_minimum_size().y
	var room := maxf(160.0, size.y - 420.0)
	_scroll.custom_minimum_size.y = minf(wanted, room)


func _refresh() -> void:
	UIFactory.clear_children(_choice_box)
	var taken := int(_state.get("taken", -1))
	var choices: Array = _state.get("choices", [])
	_leave.text = "Continue" if taken >= 0 else "Leave without taking anything"
	_leave.theme_type_variation = &"PrimaryButton" if taken >= 0 else &""
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var icons := {"gold": "icons/icon_gold", "potion": "icons/icon_potion", "relic": "icons/icon_star", "card": "icons/icon_rune", "equipment": "icons/icon_chest"}
		var button := ChoiceCard.create(str(choice.get("text", "")), TreasureRoom.describe(choice), str(icons.get(str(choice.get("type", "")), "icons/icon_chest")))
		button.name = "TreasureChoice%d" % i
		button.disabled = taken >= 0
		if taken == i:
			button.set_texts("✔ Taken: " + str(choice.get("text", "")), TreasureRoom.describe(choice))
			button.chosen = true
		button.pressed.connect(_on_choice.bind(i))
		_choice_box.add_child(button)
	if choices.is_empty():
		_choice_box.add_child(UIFactory.label("The chest is empty.", &"DimLabel"))


func _on_choice(index: int) -> void:
	var error := TreasureRoom.claim(_state, index, GameState.party, GameState.inventory)
	if error != "":
		_message.text = error
		return
	_message.text = "You took: " + TreasureRoom.describe((_state["choices"] as Array)[index])
	GameState.update_room({"taken": index})  # Saved immediately: gold/items/cards and the flag together.
	_refresh()
	_fit_scroll.call_deferred()
	_leave.grab_focus.call_deferred()  # Enter / A continues right away
	if SettingsStore.load_values().get("effects_quality", "full") != "off":
		_leave.pivot_offset = _leave.size / 2.0
		var pulse := _leave.create_tween()
		pulse.tween_property(_leave, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_leave, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


func _backdrop() -> Dictionary:
	return current_room_backdrop()
