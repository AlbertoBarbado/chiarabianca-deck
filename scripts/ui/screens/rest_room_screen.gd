extends ScreenBase
## Rest room: the party recovers a configurable fraction of max HP, and may upgrade one card.
## Upgrade logic lives in CardUpgrader; this screen only presents the choice.

var _rested: bool = false
var _upgraded: bool = false
var _members_box: HBoxContainer
var _rest_button: Button
var _upgrade_button: Button
var _remove_button: Button
var _removals_done: int = 0
var _result: Label
var _overlay: Control


func _build() -> void:
	var node := GameState.get_current_node()
	if GameState.in_room(node.id):  # Resumed after a reload: keep what was already done here.
		_rested = bool(GameState.room_state.get("rested", false))
		_upgraded = bool(GameState.room_state.get("upgraded", false))
		_removals_done = int(GameState.room_state.get("removed", 0))
	var column := UIFactory.vbox(14)
	root.add_child(column)
	var title_row := UIFactory.hbox(10)
	title_row.add_child(UIFactory.icon("rest", 36))
	title_row.add_child(UIFactory.label(node.display_name, &"HeaderLabel"))
	column.add_child(title_row)
	column.add_child(UIFactory.label("A quiet moment to recover — and to sharpen one card.", &"DimLabel"))

	_members_box = UIFactory.hbox(20)
	_members_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_members_box)
	_refresh_members()

	_result = UIFactory.label("", &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_result)

	var footer := UIFactory.hbox()
	footer.add_child(UIFactory.expander())
	_rest_button = UIFactory.button("Rest (+%d%% HP)" % roundi(_heal_fraction() * 100.0), true, Vector2(240, 56))
	_rest_button.pressed.connect(_on_rest)
	_rest_button.disabled = _rested
	footer.add_child(_rest_button)
	_upgrade_button = UIFactory.button("Upgrade a Card", true, Vector2(240, 56))
	_upgrade_button.pressed.connect(_open_upgrade_picker)
	_upgrade_button.disabled = _upgraded
	footer.add_child(_upgrade_button)
	if CardRemoval.is_enabled(node.raw):
		_remove_button = UIFactory.button("Remove a Card", true, Vector2(240, 56))
		_remove_button.name = "RemoveButton"
		_remove_button.pressed.connect(_open_removal_picker)
		_remove_button.disabled = _removals_done >= int(CardRemoval.rules(node.raw).get("uses_per_rest", 1))
		footer.add_child(_remove_button)
	var leave := UIFactory.button("Back to Town" if node.type == MapNodeData.TYPE_TOWN else "Return to Map", false, Vector2(220, 56))
	leave.pressed.connect(func() -> void: SceneRouter.leave_service())
	footer.add_child(leave)
	column.add_child(footer)


func _heal_fraction() -> float:
	return GameState.current_heal_fraction()


func _refresh_members() -> void:
	UIFactory.clear_children(_members_box)
	for member in GameState.party.members:
		var panel := CharacterPanel.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.setup(member.definition, {"specialization": member.specialization, "hp": member.current_hp, "max_hp": member.max_hp, "figure": true})
		_members_box.add_child(panel)


func _on_rest() -> void:
	if _rested:
		return
	_rested = true
	var restored := GameState.party.rest(_heal_fraction())
	var parts: Array[String] = []
	for character_id: String in restored:
		parts.append("%s +%d HP" % [GameState.party.get_member(character_id).definition.display_name, restored[character_id]])
	_result.text = "The party rests.  " + "   ".join(parts)
	_rest_button.disabled = true
	_refresh_members()
	GameState.update_room({"rested": true})


# --- Card upgrade picker -----------------------------------------------------

func _open_upgrade_picker() -> void:
	if _upgraded:
		return
	_close_overlay()
	_overlay = _make_overlay()
	var panel := UIFactory.panel()
	panel.custom_minimum_size = Vector2(900, 560)
	_overlay.get_child(0).add_child(panel)
	var column := UIFactory.vbox(8)
	panel.add_child(column)
	column.add_child(UIFactory.label("Choose a card to upgrade", &"HeaderLabel"))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var rows := UIFactory.vbox(10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for member in GameState.party.members:
		var title := UIFactory.label(member.definition.display_name, &"")
		title.add_theme_color_override("font_color", member.definition.accent_color)
		rows.add_child(title)
		var flow := HFlowContainer.new()
		rows.add_child(flow)
		for owned in _unique_upgradable(member):
			var view := CardView.new()
			view.show_owned(DataRegistry.get_card(owned.card_id), member.id, owned.upgrade_level)
			view.pressed.connect(func(_v: CardView) -> void: _preview_upgrade(member, owned))
			flow.add_child(view)
		if flow.get_child_count() == 0:
			rows.add_child(UIFactory.label("No upgradable cards.", &"DimLabel"))
	var cancel := UIFactory.button("Cancel", false, Vector2(180, 52))
	cancel.pressed.connect(_close_overlay)
	column.add_child(cancel)


## One representative copy per (card id, level) so identical copies are not listed repeatedly.
func _unique_upgradable(member: PartyMember) -> Array[OwnedCard]:
	var seen: Dictionary = {}
	var result: Array[OwnedCard] = []
	for owned in CardUpgrader.get_upgradable_cards(member):
		var key := "%s|%d" % [owned.card_id, owned.upgrade_level]
		if not seen.has(key):
			seen[key] = true
			result.append(owned)
	return result


## Shows the current and upgraded versions side by side and asks for confirmation.
func _preview_upgrade(member: PartyMember, owned: OwnedCard) -> void:
	_close_overlay()
	_overlay = _make_overlay()
	var def := DataRegistry.get_card(owned.card_id)
	var panel := UIFactory.panel()
	_overlay.get_child(0).add_child(panel)
	var column := UIFactory.vbox(14)
	panel.add_child(column)
	column.add_child(UIFactory.label("Upgrade %s's %s?" % [member.definition.display_name, def.display_name], &"HeaderLabel"))
	var row := UIFactory.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var before := CardView.new()
	before.show_owned(def, member.id, owned.upgrade_level)
	before.set_scale_factor(1.3)
	row.add_child(before)
	row.add_child(UIFactory.label("→", &"TitleLabel"))
	var after := CardView.new()
	after.show_owned(def, member.id, owned.upgrade_level + 1)
	after.set_scale_factor(1.3)
	row.add_child(after)
	var buttons := UIFactory.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UIFactory.button("Back", false, Vector2(180, 52))
	back.pressed.connect(_open_upgrade_picker)
	buttons.add_child(back)
	var confirm := UIFactory.button("Upgrade", true, Vector2(180, 52))
	confirm.pressed.connect(func() -> void: _confirm_upgrade(member, owned))
	buttons.add_child(confirm)
	column.add_child(buttons)


func _confirm_upgrade(member: PartyMember, owned: OwnedCard) -> void:
	var error := CardUpgrader.upgrade(member, owned.uid)
	_close_overlay()
	if error != "":
		_result.text = error
		return
	_upgraded = true
	_upgrade_button.disabled = true
	GameState.update_room({"upgraded": true})
	var def := DataRegistry.get_card(owned.card_id)
	_result.text = "%s's %s was upgraded." % [member.definition.display_name, def.display_name]


# --- Card removal ------------------------------------------------------------

## Lists the whole party deck (grouped by owner) so one card can be picked for permanent removal.
func _open_removal_picker() -> void:
	var node := GameState.get_current_node()
	if _removals_done >= int(CardRemoval.rules(node.raw).get("uses_per_rest", 1)):
		return
	_close_overlay()
	_overlay = _make_overlay()
	var panel := UIFactory.panel()
	panel.custom_minimum_size = Vector2(900, 560)
	_overlay.get_child(0).add_child(panel)
	var column := UIFactory.vbox(8)
	panel.add_child(column)
	column.add_child(UIFactory.label("Choose a card to remove", &"HeaderLabel"))
	var cost := int(CardRemoval.rules(node.raw).get("gold_cost", 0))
	var note := "Removal is permanent for this run. The card leaves its owner's deck and the shared party deck."
	column.add_child(UIFactory.label(note + ("  Cost: %d gold." % cost if cost > 0 else ""), &"DimLabel", true))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var rows := UIFactory.vbox(10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for member in GameState.party.members:
		var title := UIFactory.label("%s  (%d cards)" % [member.definition.display_name, member.deck.size()], &"")
		title.add_theme_color_override("font_color", member.definition.accent_color)
		rows.add_child(title)
		var flow := HFlowContainer.new()
		rows.add_child(flow)
		for owned in member.deck:
			var view := CardView.new()
			view.show_owned(DataRegistry.get_card(owned.card_id), member.id, owned.upgrade_level)
			view.name = "Removable_" + owned.uid
			view.pressed.connect(func(_v: CardView) -> void: _confirm_removal(member, owned))
			flow.add_child(view)
	var cancel := UIFactory.button("Cancel", false, Vector2(180, 52))
	cancel.pressed.connect(_close_overlay)
	column.add_child(cancel)


func _confirm_removal(member: PartyMember, owned: OwnedCard) -> void:
	var node := GameState.get_current_node()
	var reason := CardRemoval.can_remove(GameState.party, GameState.inventory, member.id, owned.uid, _removals_done, node.raw)
	if reason != "":
		_result.text = reason
		_close_overlay()
		return
	_close_overlay()
	_overlay = _make_overlay()
	var def := DataRegistry.get_card(owned.card_id)
	var panel := UIFactory.panel()
	_overlay.get_child(0).add_child(panel)
	var column := UIFactory.vbox(14)
	panel.add_child(column)
	column.add_child(UIFactory.label("Remove %s's %s?" % [member.definition.display_name, def.display_name], &"HeaderLabel"))
	var view := CardView.new()
	view.show_owned(def, member.id, owned.upgrade_level)
	view.set_scale_factor(1.3)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(view)
	column.add_child(center)
	column.add_child(UIFactory.label("This is permanent for the current run and cannot be undone.", &"", true, HORIZONTAL_ALIGNMENT_CENTER))
	var buttons := UIFactory.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UIFactory.button("Back", false, Vector2(180, 52))
	back.pressed.connect(_open_removal_picker)
	buttons.add_child(back)
	var confirm := UIFactory.button("Remove Card", true, Vector2(200, 52))
	confirm.name = "ConfirmRemoval"
	confirm.pressed.connect(func() -> void: _do_removal(member, owned))
	buttons.add_child(confirm)
	column.add_child(buttons)


func _do_removal(member: PartyMember, owned: OwnedCard) -> void:
	var node := GameState.get_current_node()
	var def := DataRegistry.get_card(owned.card_id)
	var error := CardRemoval.remove(GameState.party, GameState.inventory, member.id, owned.uid, _removals_done, node.raw)
	_close_overlay()
	if error != "":
		_result.text = error
		return
	_removals_done += 1
	if _removals_done >= int(CardRemoval.rules(node.raw).get("uses_per_rest", 1)):
		_remove_button.disabled = true
	_result.text = "%s's %s was removed from the deck." % [member.definition.display_name, def.display_name]
	GameState.update_room({"removed": _removals_done})


func _make_overlay() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	UIFactory.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	dim.add_child(center)
	return dim


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _backdrop() -> Dictionary:
	return current_room_backdrop()
