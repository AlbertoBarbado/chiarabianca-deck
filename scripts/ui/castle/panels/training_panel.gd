extends VBoxContainer
## Training Hall: learn new specializations (their starting cards join the collection) and choose
## each sister's primary and secondary specialization. Hybrid rules: only the primary
## specialization's passive runs; a deck may hold a limited number of secondary cards; rewards offer
## the secondary pool less often.

var shell: Node
var _body: VBoxContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	var rules := DeckRules.rules()
	add_child(UIFactory.label("Hybrid styles: a sister keeps her primary specialization's passive; her secondary adds up to %d of its cards to her deck, and its cards appear in rewards half as often. Changing the primary resets her prepared deck to the new starting deck." % int(rules.get("secondary_card_limit", 4)), &"DimLabel", true))
	var scroll := UIFactory.scroll()
	_body = UIFactory.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	add_child(scroll)
	refresh()


func refresh() -> void:
	UIFactory.clear_children(_body)
	var campaign := GameState.campaign
	var narrow := CastleUI.is_narrow(self)
	var row: BoxContainer = UIFactory.vbox(10) if narrow else UIFactory.hbox(10)
	_body.add_child(row)
	for member in campaign.roster.members:
		row.add_child(_sister_column(member))
	var combo := TwinCombos.for_pair(campaign.member("chiara").specialization.id, campaign.member("bianca").specialization.id)
	if not combo.is_empty():
		var panel := CastleUI.card_panel(4, UITheme.MAGIC_BLUE)
		panel.name = "PairCombo"
		CastleUI.column_of(panel).add_child(UIFactory.label("Twin combo of the primary pair: %s %s" % [str(combo.get("name", "")), TwinCombos.stars(combo)], &"", true))
		CastleUI.column_of(panel).add_child(UIFactory.label(str(combo.get("text", "")), &"DimLabel", true))
		_body.add_child(panel)


func _sister_column(member: PartyMember) -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(6, member.definition.accent_color)
	panel.name = "Training_" + member.id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label(member.definition.display_name, &"HeaderLabel", false)
	title.add_theme_color_override("font_color", member.definition.accent_color)
	column.add_child(title)
	for spec in DataRegistry.get_specializations_for(member.id):
		column.add_child(_spec_row(member, spec))
	return panel


func _spec_row(member: PartyMember, spec: SpecializationDef) -> Control:
	var campaign := GameState.campaign
	var learned := campaign.unlocked_specializations(member.id).has(spec.id)
	var is_primary := member.specialization.id == spec.id
	var is_secondary := member.secondary_specialization != null and member.secondary_specialization.id == spec.id
	var row := UIFactory.hbox(8)
	row.name = "Spec_" + spec.id
	var texts := UIFactory.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_text := spec.display_name + ("  · primary" if is_primary else ("  · secondary" if is_secondary else ""))
	var label := UIFactory.label(name_text, &"", false)
	label.add_theme_color_override("font_color", UITheme.GOLD if is_primary else (UITheme.MAGIC_BLUE.lightened(0.3) if is_secondary else (UITheme.IVORY if learned else UITheme.IVORY_DIM)))
	texts.add_child(label)
	var detail := spec.identity if spec.is_playable() else "Not ready yet (coming in a later update)."
	if spec.is_playable() and spec.has_passive():
		detail += " Passive: " + str(spec.passive.get("name", ""))
	texts.add_child(UIFactory.label(detail, &"DimLabel", true))
	row.add_child(texts)
	if not spec.is_playable():
		return row
	if not learned:
		var learn := UIFactory.button("Learn %dg" % CastleWorkshop.spec_unlock_price(), false, Vector2(130, 48))
		learn.name = "Learn"
		var reason := CastleWorkshop.can_unlock_spec(campaign, member.id, spec.id)
		learn.disabled = reason != ""
		learn.tooltip_text = reason
		learn.pressed.connect(func() -> void:
			CastleUI.confirm(shell, "Learn %s?" % spec.display_name, "%s learns %s for %d gold. Its %d starting cards join her collection." % [member.definition.display_name, spec.display_name, CastleWorkshop.spec_unlock_price(), spec.starting_deck_card_ids.size()], "Learn", func() -> void:
				_done(CastleWorkshop.unlock_spec(campaign, member.id, spec.id), "%s learned %s." % [member.definition.display_name, spec.display_name])))
		row.add_child(learn)
		return row
	if not is_primary:
		var primary := UIFactory.button("Primary", false, Vector2(110, 48))
		primary.name = "SetPrimary"
		primary.pressed.connect(func() -> void:
			CastleUI.confirm(shell, "Make %s primary?" % spec.display_name, "%s's passive becomes %s and her prepared deck resets to the %s starting deck." % [member.definition.display_name, str(spec.passive.get("name", spec.display_name)), spec.display_name], "Switch", func() -> void:
				_done(CastleWorkshop.set_primary(campaign, member.id, spec.id), "%s now fights as %s." % [member.definition.display_name, spec.display_name])))
		row.add_child(primary)
		var secondary := UIFactory.button("Clear secondary" if is_secondary else "Secondary", false, Vector2(150, 48))
		secondary.name = "SetSecondary"
		secondary.pressed.connect(func() -> void:
			_done(CastleWorkshop.set_secondary(campaign, member.id, "" if is_secondary else spec.id), "Secondary updated."))
		row.add_child(secondary)
	return row


func _done(error: String, success: String) -> void:
	if error != "":
		shell.toast(error, false)
		return
	shell.changed()
	shell.toast(success)
	refresh()
