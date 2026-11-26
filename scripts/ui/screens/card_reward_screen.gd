extends ScreenBase
## Post-combat card reward: pick one of the offered cards (added to its owner's deck) or skip.
## Tap a card to select it, then confirm with "Take Card".

var _reward: CardReward
var _views: Array[CardView] = []
var _selected_index: int = -1
var _take_button: Button
var _detail: Label
var _column: VBoxContainer

const CARD_SCALE := 1.35
const CARD_MIN_SCALE := 0.85
const BOTTOM_GAP := 8.0
var _fitting := false


func _build() -> void:
	# A boss first offers its relics on a page of their own (as a boss chest), then the cards.
	var relic_choices: Array = GameState.room_state.get("relic_choices", [])
	if not relic_choices.is_empty() and str(GameState.room_state.get("relic_taken", "")) == "" and not bool(GameState.room_state.get("relic_skipped", false)):
		_build_boss_relic_page(relic_choices)
		return
	_reward = GameState.pending_reward
	if _reward == null or _reward.resolved or _reward.options.is_empty():
		_finish.call_deferred()
		return
	var column := UIFactory.vbox(10)
	root.add_child(column)
	var epic := _reward.options.any(func(o: Dictionary) -> bool: return DataRegistry.get_card(str(o["card_id"])) != null and DataRegistry.get_card(str(o["card_id"])).rarity == "epic")
	var heading := SectionHeading.new()
	heading.setup("Choose an Epic Card" if epic else "Choose a Card Reward", true)
	heading.name = "RewardHeading"
	column.add_child(heading)
	if epic:
		var note := UIFactory.label("The final foe of this land is defeated. Epic cards are only found here.", &"", true, HORIZONTAL_ALIGNMENT_CENTER)
		note.add_theme_color_override("font_color", Color("e2b4ff"))
		column.add_child(note)
	column.add_child(UIFactory.label("The card joins its owner's deck and enters the shared party deck in future battles.", &"DimLabel", true))

	var row := UIFactory.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for i in _reward.options.size():
		row.add_child(_make_option(i))

	_detail = UIFactory.label("Tap a card to select it.", &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_detail)

	var loot: Array = GameState.room_state.get("loot", [])
	if not loot.is_empty():
		column.add_child(_make_loot_strip(loot))
	var relics_found: Array = GameState.room_state.get("relics", [])
	if not relics_found.is_empty():
		column.add_child(_make_relic_strip(relics_found))
	var footer := UIFactory.hbox()
	if not loot.is_empty():
		var gear := UIFactory.button("Equipment", false, Vector2(200, 56))
		gear.name = "RewardEquipment"
		gear.pressed.connect(func() -> void: SceneRouter.open_equipment(SceneRouter.Screen.REWARD))
		footer.add_child(gear)
	footer.add_child(UIFactory.expander())
	var skip := UIFactory.button("Skip Reward", false, Vector2(220, 56))
	skip.pressed.connect(_on_skip)
	footer.add_child(skip)
	_take_button = UIFactory.button("Take Card", true, Vector2(220, 56))
	_take_button.disabled = true
	_take_button.pressed.connect(_on_take)
	footer.add_child(_take_button)
	footer.name = "RewardFooter"
	column.add_child(footer)
	_column = column
	_fit_to_screen.call_deferred()
	if not root.resized.is_connected(_fit_to_screen):
		root.resized.connect(_fit_to_screen)


## Epic note + loot strip + large cards can be taller than the screen, which pushed the buttons off
## the bottom: shrink the cards (never below CARD_MIN_SCALE) until the whole column fits.
func _fit_to_screen() -> void:
	if _fitting or _column == null or not is_instance_valid(_column) or root.size.y <= 0.0:
		return
	_fitting = true
	var footer := _column.get_node_or_null("RewardFooter") as Control
	var factor := CARD_SCALE
	_apply_card_scale(factor)
	# Measure where the footer really lands (the screen root has margins), shrinking the cards one
	# step per laid-out frame until the buttons sit fully on screen.
	for step in 12:
		await get_tree().process_frame
		if footer == null or not is_instance_valid(footer):
			break
		if footer.get_global_rect().end.y <= get_viewport_rect().size.y - BOTTOM_GAP or factor <= CARD_MIN_SCALE:
			break
		factor = maxf(CARD_MIN_SCALE, factor - 0.05)
		_apply_card_scale(factor)
	_fitting = false


func _apply_card_scale(factor: float) -> void:
	for view in _views:
		view.set_scale_factor(factor)
		view.reset_size()


## "Loot found" strip: every dropped item with its picture, name (rarity colour) and stats.
func _make_loot_strip(loot: Array) -> Control:
	var panel := UIFactory.panel(UITheme.compact_panel_style(0.3, Vector4(16, 8, 16, 8)))
	panel.name = "LootStrip"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := UIFactory.hbox(12)
	panel.add_child(row)
	var title := UIFactory.label("Loot found:", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	row.add_child(title)
	for item_id: Variant in loot:
		var def := Equipment.item(str(item_id))
		if def.is_empty():
			continue
		row.add_child(ItemTile.create(str(item_id), "", Vector2(56, 56)))
		var text := UIFactory.vbox(0)
		var item_name := UIFactory.label(str(def.get("name", item_id)), &"")
		item_name.add_theme_color_override("font_color", Equipment.rarity_color(str(def.get("rarity", "common"))))
		text.add_child(item_name)
		var stats := UIFactory.label(" · ".join(Equipment.stat_lines(str(item_id)).map(func(line: String) -> String: return line.trim_suffix("."))) + " — in the party stash", &"DimLabel")
		stats.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		text.add_child(stats)
		row.add_child(text)
	return panel


## "Relic found" strip (elites): the relic, its name in its rarity colour and what it does.
func _make_relic_strip(relic_ids: Array) -> Control:
	var panel := UIFactory.panel(UITheme.compact_panel_style(0.3, Vector4(16, 8, 16, 8)))
	panel.name = "RelicStrip"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := UIFactory.hbox(12)
	panel.add_child(row)
	var title := UIFactory.label("Relic found:", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	row.add_child(title)
	for relic_id: Variant in relic_ids:
		row.add_child(RelicIcon.create(str(relic_id), 52))
		row.add_child(_relic_text(str(relic_id)))
	return panel


## The boss relic page: three boss relics side by side, large, and Skip. Taking or skipping moves on
## to the card reward (the choice is saved in the room state, so a reload never offers it again).
func _build_boss_relic_page(relic_ids: Array) -> void:
	var column := UIFactory.vbox(16)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(column)
	var heading := SectionHeading.new()
	heading.setup("Choose a Boss Relic", true)
	heading.name = "BossRelicHeading"
	column.add_child(heading)
	column.add_child(UIFactory.label("Each is power with a price. Tap one to take it.", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UIFactory.expander())
	var choice := _make_boss_relic_choice(relic_ids, true)
	choice.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(choice)
	column.add_child(UIFactory.expander())
	var footer := UIFactory.hbox()
	footer.name = "BossRelicFooter"
	footer.add_child(UIFactory.expander())
	var skip := UIFactory.button("Skip Relic", false, Vector2(220, 56))
	skip.name = "SkipBossRelic"
	skip.pressed.connect(func() -> void:
		GameState.update_room({"relic_skipped": true})
		_show_card_page())
	footer.add_child(skip)
	column.add_child(footer)


func _show_card_page() -> void:
	UIFactory.clear_children(root)
	_views.clear()
	_selected_index = -1
	_build()


## A boss leaves a choice of boss relics: power with a price. Tapping (or clicking) one takes it,
## once, then the card reward follows. Each option is a panel that grows with its text.
func _make_boss_relic_choice(relic_ids: Array, large: bool = false) -> Control:
	var panel := UIFactory.panel(UITheme.compact_panel_style(0.3, Vector4(16, 8, 16, 8)))
	panel.name = "BossRelicChoice"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var column := UIFactory.vbox(6)
	panel.add_child(column)
	var title := UIFactory.label("", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	column.add_child(title)
	var row := UIFactory.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var options: Array[PanelContainer] = []
	var refresh := func() -> void:
		var taken := str(GameState.room_state.get("relic_taken", ""))
		title.text = "Choose a boss relic (power with a price):" if taken == "" else "Boss relic taken:"
		for option in options:
			var mine: bool = option.get_meta("relic_id") == taken
			option.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.92), UITheme.GOLD if mine else UITheme.GOLD_DARK, 10, 3 if mine else 1, 8))
			option.modulate = Color(1, 1, 1, 0.45) if taken != "" and not mine else Color.WHITE
			option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if taken == "" else Control.CURSOR_ARROW
	for relic_id: Variant in relic_ids:
		var option := PanelContainer.new()
		option.name = "BossRelic_" + str(relic_id)
		option.set_meta("relic_id", str(relic_id))
		option.custom_minimum_size = Vector2(250, 0)
		option.mouse_filter = Control.MOUSE_FILTER_STOP
		option.tooltip_text = RelicIcon.tooltip_for(str(relic_id))
		var content := UIFactory.hbox(8)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := RelicIcon.create(str(relic_id), 96 if large else 52)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if large:
			option.custom_minimum_size = Vector2(330, 150)
		content.add_child(icon)
		var text := _relic_text(str(relic_id))
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(text)
		option.add_child(content)
		option.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				if GameState.take_boss_relic(str(relic_id)):
					refresh.call()
					if large:
						get_tree().create_timer(0.5).timeout.connect(_show_card_page))
		options.append(option)
		row.add_child(option)
	refresh.call()
	return panel


## Taps a boss relic option (tests and keyboard users): same as clicking it.
func take_boss_relic_option(relic_id: String) -> bool:
	var option := find_child("BossRelic_" + relic_id, true, false) as PanelContainer
	if option == null:
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	option.gui_input.emit(click)
	return GameState.room_state.get("relic_taken", "") == relic_id


func _relic_text(relic_id: String) -> Control:
	var def := DataRegistry.get_item(relic_id)
	var text := UIFactory.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var relic_name := UIFactory.label(str(def.get("name", relic_id)), &"")
	relic_name.add_theme_color_override("font_color", RelicIcon.rarity_color(str(def.get("rarity", "common"))))
	text.add_child(relic_name)
	var desc := UIFactory.label(str(def.get("description", "")), &"DimLabel", true)
	desc.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	desc.custom_minimum_size.x = 160
	text.add_child(desc)
	return text


func _make_option(index: int) -> Control:
	var option := _reward.options[index]
	var owner_def := DataRegistry.get_character(str(option["owner_character_id"]))
	var def := DataRegistry.get_card(str(option["card_id"]))
	var box := UIFactory.vbox(6)
	var view := CardView.new()
	view.show_owned(def, owner_def.id)
	view.set_scale_factor(CARD_SCALE)
	view.pressed.connect(func(_v: CardView) -> void: _select(index))
	box.add_child(view)
	_views.append(view)
	var owner_label := UIFactory.label("For %s (%s)" % [owner_def.display_name, DataRegistry.get_specialization(GameState.party.get_member(owner_def.id).specialization.id).display_name], &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	owner_label.add_theme_color_override("font_color", owner_def.accent_color)
	box.add_child(owner_label)
	return box


func _select(index: int) -> void:
	_selected_index = index
	for i in _views.size():
		_views[i].set_selected(i == index)
	var def := DataRegistry.get_card(str(_reward.options[index]["card_id"]))
	var owner_name := DataRegistry.get_character(str(_reward.options[index]["owner_character_id"])).display_name
	_detail.text = "%s — %s's card. Cost %d, %s." % [def.display_name, owner_name, def.cost, def.card_type.capitalize()]
	_take_button.disabled = false


func _on_take() -> void:
	if _reward.choose(_selected_index, GameState.party) != null:
		_finish()


func _on_skip() -> void:
	_reward.skip()
	_finish()


func _finish() -> void:
	GameState.end_room()  # Clears the reward and saves the deck change in one step (no double reward).
	SceneRouter.go(SceneRouter.Screen.MAP)


func _backdrop() -> Dictionary:
	return current_room_backdrop()
