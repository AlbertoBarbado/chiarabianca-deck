extends VBoxContainer
## Deck Workshop (castle Library): each sister's prepared deck built from her collection.
## Left: the prepared deck. Right: the collection copies not in the deck, filtered by specialization,
## type, rarity and synergy tag. Drag a card from one side to the other to add or remove it (mouse or
## touch), or tap it to inspect it and use the buttons. Deck rules (DeckRules) are checked live and a
## refused drop says why; presets save and load whole configurations.

const CARD_SCALE := 0.62
const TYPES := [["all", "All types"], ["attack", "Attack"], ["spell", "Spell"], ["defense", "Defense"], ["skill", "Skill"], ["support", "Support"], ["power", "Power"]]
const RARITIES := [["all", "All rarities"], ["basic", "Basic"], ["common", "Common"], ["uncommon", "Uncommon"], ["rare", "Rare"], ["epic", "Epic"], ["fusion", "Fusion"]]

var shell: Node
var sister := "chiara"
var type_filter := "all"
var rarity_filter := "all"
var spec_filter := "usable"
var tag_filter := "all"

var _status: Label
var _deck_grid: HFlowContainer
var _deck_side: PanelContainer
var _collection_side: PanelContainer
const SIDE_DECK := "deck"
const SIDE_COLLECTION := "collection"
var _collection_grid: HFlowContainer
var _filters: VBoxContainer
var _presets_row: HFlowContainer
## Right column: the hovered card at a large size with its details, or the deck summary.
var _preview_panel: PanelContainer
const PREVIEW_SCALE := 1.3


## Portrait tabs for the two sisters (avatar, name and specializations); the active one glows.
func _sister_tabs() -> Control:
	var row := UIFactory.hbox(8)
	row.name = "SisterTabs"
	for m in GameState.campaign.roster.members:
		var tab := Button.new()
		tab.name = "Sister_" + m.id
		tab.toggle_mode = true
		tab.button_pressed = m.id == sister
		tab.custom_minimum_size = Vector2(196, 64)
		tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Pointed kit tabs: navy, violet when selected (the theme's ToggleButton look).
		tab.theme_type_variation = &"ToggleButton"
		tab.custom_minimum_size = Vector2(250, 64)
		var content := UIFactory.hbox(8)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIFactory.full_rect(content)
		content.offset_left = 34
		content.offset_right = -30
		tab.add_child(content)
		var face := AvatarFrame.new()
		face.setup(m.id, 50.0, m.definition.accent_color)
		content.add_child(face)
		var texts := UIFactory.vbox(0)
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := UIFactory.label(m.definition.display_name, &"", false)
		name_label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
		name_label.add_theme_color_override("font_color", Color("f6e7c1"))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(name_label)
		var spec_text := m.specialization.display_name + ((" + " + m.secondary_specialization.display_name) if m.secondary_specialization != null else "")
		var spec_label := UIFactory.label(spec_text, &"", false)
		spec_label.add_theme_font_size_override("font_size", 13)
		spec_label.add_theme_color_override("font_color", UITheme.LAVENDER)
		spec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(spec_label)
		content.add_child(texts)
		tab.pressed.connect(_pick_sister.bind(m.id))
		row.add_child(tab)
	return row


## The card under the pointer, large, with owner, specialization, rarity, upgrade and synergy tags.
func _show_preview(owned: OwnedCard) -> void:
	if _preview_panel == null:
		return
	var column := CastleUI.column_of(_preview_panel)
	UIFactory.clear_children(column)
	var def := DataRegistry.get_card(owned.card_id)
	var holder := CenterContainer.new()
	column.add_child(holder)
	var view := CastleUI.card(def, sister, owned.upgrade_level, PREVIEW_SCALE)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(view)
	var spec := DataRegistry.get_specialization(def.specialization_id)
	var lines: Array[String] = ["%s · %s" % [DataRegistry.get_character(sister).display_name, spec.display_name if spec != null else "—"],
		"%s %s%s" % [def.rarity.capitalize(), def.card_type.capitalize(), "  · upgraded" if owned.upgrade_level > 0 else ""]]
	var tags := CastleUI.card_tags(def)
	if not tags.is_empty():
		lines.append("Works with: " + ", ".join(tags.map(func(t: String) -> String: return DataRegistry.get_status(t).display_name if DataRegistry.get_status(t) != null else t.capitalize())))
	if DeckRules.is_secondary_card(_member(), owned.card_id):
		lines.append("Secondary specialization card")
	var info := UIFactory.label("\n".join(lines), &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	info.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	info.add_theme_color_override("font_color", UITheme.LAVENDER)
	column.add_child(info)


## Without a hovered card: the deck at a glance (size, specializations, synergy tags, twin combo).
func _show_summary() -> void:
	if _preview_panel == null:
		return
	var column := CastleUI.column_of(_preview_panel)
	UIFactory.clear_children(column)
	var heading := UIFactory.label("Deck Summary", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 4)
	column.add_child(heading)
	var campaign := GameState.campaign
	for m in campaign.roster.members:
		var cards := campaign.prepared_cards(m.id)
		var by_spec := {}
		for owned in cards:
			var spec_id := DataRegistry.get_card(owned.card_id).specialization_id
			by_spec[spec_id] = int(by_spec.get(spec_id, 0)) + 1
		var parts: Array[String] = []
		for spec_id: String in by_spec:
			var spec := DataRegistry.get_specialization(spec_id)
			parts.append("%s %d" % [spec.display_name if spec != null else "Other", int(by_spec[spec_id])])
		var line := UIFactory.label("%s — %d cards\n%s" % [m.definition.display_name, cards.size(), ", ".join(parts)], &"", true)
		line.add_theme_color_override("font_color", m.definition.accent_color.lightened(0.25))
		column.add_child(line)
	var tags := {}
	for owned in campaign.prepared_cards(sister):
		for tag in CastleUI.card_tags(DataRegistry.get_card(owned.card_id)):
			tags[tag] = int(tags.get(tag, 0)) + 1
	if not tags.is_empty():
		var names: Array[String] = []
		for tag: String in tags:
			names.append("%s ×%d" % [DataRegistry.get_status(tag).display_name if DataRegistry.get_status(tag) != null else tag.capitalize(), int(tags[tag])])
		var synergy := UIFactory.label("Synergies: " + ", ".join(names), &"DimLabel", true)
		column.add_child(synergy)
	var combo := TwinCombos.for_pair(campaign.member("chiara").specialization.id, campaign.member("bianca").specialization.id)
	if not combo.is_empty():
		var combo_label := UIFactory.label("Twin combo: %s %s\n%s" % [str(combo.get("name", "")), TwinCombos.stars(combo), str(combo.get("text", ""))], &"", true)
		combo_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		combo_label.add_theme_color_override("font_color", UITheme.BOND_PINK)
		column.add_child(combo_label)
	column.add_child(UIFactory.label("Hover a card to look at it closely.", &"DimLabel", true))


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	var top := UIFactory.hbox(12)
	top.add_child(_sister_tabs())
	_status = UIFactory.label("", &"", true)
	_status.name = "DeckStatus"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	var reset := UIFactory.button("Starter Deck", false, Vector2(0, 48))
	reset.name = "ResetButton"
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.tooltip_text = "Replace this sister's deck with her primary specialization's recommended starting deck."
	reset.pressed.connect(_on_reset)
	top.add_child(reset)
	var save := UIFactory.button("Save Preset", false, Vector2(0, 48))
	save.name = "SavePresetButton"
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.pressed.connect(_on_save_preset)
	top.add_child(save)
	add_child(top)
	_presets_row = HFlowContainer.new()
	_presets_row.name = "Presets"
	_presets_row.add_theme_constant_override("h_separation", 6)
	add_child(_presets_row)
	var narrow := CastleUI.is_narrow(self)
	var body: BoxContainer = UIFactory.vbox(10) if narrow else UIFactory.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var deck_side := CastleUI.card_panel(6)
	deck_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var deck_column := CastleUI.column_of(deck_side)
	var deck_title := UIFactory.label("Prepared deck  ·  drag cards between the two sides, or tap one", &"", true)
	deck_title.name = "DeckHint"
	deck_column.add_child(deck_title)
	var deck_scroll := CastleUI.flow_scroll(8)
	deck_scroll.custom_minimum_size.y = 220
	_deck_grid = CastleUI.grid_of(deck_scroll)
	_deck_grid.name = "DeckGrid"
	deck_column.add_child(deck_scroll)
	body.add_child(deck_side)
	var collection_side := CastleUI.card_panel(6)
	collection_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	collection_side.size_flags_stretch_ratio = 1.25
	var collection_column := CastleUI.column_of(collection_side)
	collection_column.add_child(UIFactory.label("Collection", &"", false))
	_filters = UIFactory.vbox(4)
	collection_column.add_child(_filters)
	var collection_scroll := CastleUI.flow_scroll(8)
	collection_scroll.custom_minimum_size.y = 220
	_collection_grid = CastleUI.grid_of(collection_scroll)
	_collection_grid.name = "CollectionGrid"
	collection_column.add_child(collection_scroll)
	body.add_child(collection_side)
	if not narrow:
		_preview_panel = CastleUI.card_panel(6)
		_preview_panel.name = "CardPreview"
		_preview_panel.custom_minimum_size.x = CardView.CARD_SIZE.x * PREVIEW_SCALE + 40.0
		_preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(_preview_panel)
	_deck_side = deck_side
	_collection_side = collection_side
	for zone: Control in [deck_side, deck_column, deck_scroll, _deck_grid]:
		_drop_zone(zone, SIDE_DECK)
	for zone: Control in [collection_side, collection_column, collection_scroll, _collection_grid]:
		_drop_zone(zone, SIDE_COLLECTION)
	refresh()


func _member() -> PartyMember:
	return GameState.campaign.member(sister)


func refresh() -> void:
	var campaign := GameState.campaign
	var member := _member()
	var ids: Array = campaign.prepared_cards(sister).map(func(o: OwnedCard) -> String: return o.card_id)
	var problems := DeckRules.validate(member, ids)
	var rules := DeckRules.rules()
	_status.text = "%s · %s%s · %d / %d cards (min %d)%s" % [member.definition.display_name, member.specialization.display_name,
		(" + " + member.secondary_specialization.display_name) if member.secondary_specialization != null else "",
		ids.size(), int(rules.get("max_per_sister", 15)), int(rules.get("min_per_sister", 8)), ("  —  " + problems[0]) if not problems.is_empty() else "  ✓ ready"]
	_status.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.35) if not problems.is_empty() else UITheme.GREEN.lightened(0.3))
	_build_presets()
	_build_filters()
	_show_summary()
	UIFactory.clear_children(_deck_grid)
	var cards := campaign.prepared_cards(sister)
	cards.sort_custom(func(a: OwnedCard, b: OwnedCard) -> bool: return _sort_key(a) < _sort_key(b))
	for owned in cards:
		var view := CastleUI.card(DataRegistry.get_card(owned.card_id), sister, owned.upgrade_level, CARD_SCALE)
		view.name = "Deck_" + owned.uid
		_draggable(view, owned, SIDE_DECK, func() -> void: _inspect_deck_card(owned))
		_deck_grid.add_child(view)
	UIFactory.clear_children(_collection_grid)
	var in_deck := campaign.prepared_uids(sister)
	var groups := {}
	var order: Array[String] = []
	for owned in campaign.collection(sister):
		if in_deck.has(owned.uid):
			continue
		var def := DataRegistry.get_card(owned.card_id)
		if def == null or not _passes(member, def):
			continue
		var key := "%s#%d" % [owned.card_id, owned.upgrade_level]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(owned)
	order.sort_custom(func(a: String, b: String) -> bool: return _sort_key(groups[a][0]) < _sort_key(groups[b][0]))
	for key in order:
		var copies: Array = groups[key]
		var first: OwnedCard = copies[0]
		var box := UIFactory.vbox(2)
		box.name = "Owned_" + key.replace("#", "_")
		var view := CastleUI.card(DataRegistry.get_card(first.card_id), sister, first.upgrade_level, CARD_SCALE)
		var reason := DeckRules.can_add(member, ids, first.card_id)
		if DeckRules.card_allowed(member, first.card_id) != "":
			view.modulate = Color(0.55, 0.55, 0.6)
		_draggable(view, first, SIDE_COLLECTION, func() -> void: _inspect_collection_card(first, copies.size(), reason))
		box.add_child(view)
		CastleUI.badge_on(view, "×%d" % copies.size(), UITheme.GOLD)
		_collection_grid.add_child(box)
	if order.is_empty():
		var empty := UIFactory.label("No other cards match these filters. Cards found on expeditions and learned at the Training Hall appear here.", &"DimLabel", true)
		empty.custom_minimum_size.x = 320
		_collection_grid.add_child(empty)


static func _sort_key(owned: OwnedCard) -> String:
	var def := DataRegistry.get_card(owned.card_id)
	var rarity := ["basic", "common", "uncommon", "rare", "epic", "fusion"].find(def.rarity if def != null else "")
	return "%s|%d|%s|%d" % [def.specialization_id if def != null else "", rarity, owned.card_id, 9 - owned.upgrade_level]


func _passes(member: PartyMember, def: CardDef) -> bool:
	if type_filter != "all" and def.card_type != type_filter:
		return false
	if rarity_filter != "all" and def.rarity != rarity_filter:
		return false
	if tag_filter != "all" and not CastleUI.card_tags(def).has(tag_filter):
		return false
	match spec_filter:
		"usable":
			return DeckRules.card_allowed(member, def.id) == ""
		"all":
			return true
		_:
			return def.specialization_id == spec_filter


func _build_filters() -> void:
	UIFactory.clear_children(_filters)
	var member := _member()
	var specs: Array = [["usable", "Usable now"], ["all", "All owned"]]
	for spec_id in GameState.campaign.unlocked_specializations(sister):
		specs.append([spec_id, DataRegistry.get_specialization(spec_id).display_name])
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	_filters.add_child(row)
	row.add_child(CastleUI.dropdown(specs, spec_filter, func(id: String) -> void:
		spec_filter = id
		refresh.call_deferred(), "SpecFilter"))
	row.add_child(CastleUI.dropdown(TYPES, type_filter, func(id: String) -> void:
		type_filter = id
		refresh.call_deferred(), "TypeFilter"))
	row.add_child(CastleUI.dropdown(RARITIES, rarity_filter, func(id: String) -> void:
		rarity_filter = id
		refresh.call_deferred(), "RarityFilter"))
	var tags: Array = [["all", "All tags"]]
	var seen := {}
	for owned in GameState.campaign.collection(sister):
		for tag in CastleUI.card_tags(DataRegistry.get_card(owned.card_id)):
			if not seen.has(tag):
				seen[tag] = true
				var status := DataRegistry.get_status(tag)
				tags.append([tag, status.display_name if status != null else tag.capitalize()])
	row.add_child(CastleUI.dropdown(tags, tag_filter, func(id: String) -> void:
		tag_filter = id
		refresh.call_deferred(), "TagFilter"))
	if member == null:
		return


func _build_presets() -> void:
	UIFactory.clear_children(_presets_row)
	var campaign := GameState.campaign
	if campaign.presets.is_empty():
		return
	_presets_row.add_child(UIFactory.label("Presets:", &"DimLabel", false))
	var names: Array = campaign.presets.keys()
	names.sort()
	for preset_name: String in names:
		var load_button := UIFactory.button(preset_name, false, Vector2(0, 44))
		load_button.name = "Preset_" + preset_name.replace(" ", "_")
		CastleUI.chip_style(load_button)
		load_button.tooltip_text = "Load this configuration for both sisters."
		load_button.pressed.connect(_load_preset.bind(preset_name))
		_presets_row.add_child(load_button)
		var delete := UIFactory.button("✕", false, Vector2(44, 44))
		delete.name = "DeletePreset_" + preset_name.replace(" ", "_")
		CastleUI.chip_style(delete)
		delete.tooltip_text = "Delete preset %s" % preset_name
		delete.pressed.connect(func() -> void:
			CastleUI.confirm(shell, "Delete preset?", "\"%s\" will be forgotten. The cards stay in the collection." % preset_name, "Delete", func() -> void:
				campaign.presets.erase(preset_name)
				shell.changed()
				refresh()))
		_presets_row.add_child(delete)


func _pick_sister(id: String) -> void:
	sister = id
	spec_filter = "usable"
	tag_filter = "all"
	SceneRouter.service_id = "library"
	refresh()
	for tab in find_children("Sister_*", "Button", true, false):
		(tab as Button).set_pressed_no_signal(str(tab.name) == "Sister_" + id)


func _inspect_deck_card(owned: OwnedCard) -> void:
	CastleUI.inspect_card(shell, DataRegistry.get_card(owned.card_id), sister, owned.upgrade_level, "In %s's prepared deck." % _member().definition.display_name,
		[["Remove", func() -> void: _remove(owned.uid), true]])


func _inspect_collection_card(owned: OwnedCard, copies: int, reason: String) -> void:
	var info := "%d cop%s not in the deck." % [copies, "y" if copies == 1 else "ies"]
	if reason != "":
		info += "\n" + reason
	var actions: Array = []
	if reason == "":
		actions.append(["Add to Deck", func() -> void: _add(owned.uid), true])
	CastleUI.inspect_card(shell, DataRegistry.get_card(owned.card_id), sister, owned.upgrade_level, info, actions)


# --- Drag and drop -----------------------------------------------------------------------------------

## A card that can be dragged to the other side. A tap (press and release without dragging) inspects it.
func _draggable(view: CardView, owned: OwnedCard, side: String, on_tap: Callable) -> void:
	var data := {"workshop_uid": owned.uid, "from": side, "sister": sister}
	view.mouse_entered.connect(_show_preview.bind(owned))
	var drop_check := func(_pos: Vector2, payload: Variant) -> bool: return _accepts(payload, side)
	var drop := func(_pos: Vector2, payload: Variant) -> void: _on_drop(payload, side)
	view.set_drag_forwarding(func(_pos: Vector2) -> Variant:
		var preview := CastleUI.card(DataRegistry.get_card(owned.card_id), sister, owned.upgrade_level, CARD_SCALE)
		preview.modulate.a = 0.85
		preview.position = -preview.custom_minimum_size / 2.0
		var holder := Control.new()
		holder.add_child(preview)
		view.set_drag_preview(holder)
		_highlight(SIDE_COLLECTION if side == SIDE_DECK else SIDE_DECK, true)
		return data, drop_check, drop)
	view.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed and Rect2(Vector2.ZERO, view.size).has_point((event as InputEventMouseButton).position) \
				and not view.get_viewport().gui_is_dragging():
			on_tap.call())


func _drop_zone(zone: Control, side: String) -> void:
	zone.set_drag_forwarding(Callable(), func(_pos: Vector2, payload: Variant) -> bool: return _accepts(payload, side),
		func(_pos: Vector2, payload: Variant) -> void: _on_drop(payload, side))


## A card from this sister's other side may be dropped here (deck rules are checked on drop, so a
## refused card can explain why).
func _accepts(payload: Variant, side: String) -> bool:
	return payload is Dictionary and (payload as Dictionary).has("workshop_uid") and str(payload["sister"]) == sister and str(payload["from"]) != side


func _on_drop(payload: Variant, side: String) -> void:
	_highlight(SIDE_DECK, false)
	_highlight(SIDE_COLLECTION, false)
	if not _accepts(payload, side):
		return
	if side == SIDE_DECK:
		_add(str(payload["workshop_uid"]))
	else:
		_remove(str(payload["workshop_uid"]))


## Gold border on the side a dragged card can go to.
func _highlight(side: String, on: bool) -> void:
	var panel := _deck_side if side == SIDE_DECK else _collection_side
	if panel != null:
		panel.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.88), UITheme.GOLD if on else UITheme.GOLD_DARK, 14, 3 if on else 2, 16))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_highlight(SIDE_DECK, false)
		_highlight(SIDE_COLLECTION, false)


func _add(uid: String) -> void:
	var campaign := GameState.campaign
	var uids := campaign.prepared_uids(sister)
	var owned := _member().find_card(uid)
	var ids: Array = campaign.prepared_cards(sister).map(func(o: OwnedCard) -> String: return o.card_id)
	var reason := DeckRules.can_add(_member(), ids, owned.card_id)
	if reason != "":
		shell.toast(reason, false)
		return
	uids.append(uid)
	campaign.set_prepared(sister, uids)
	shell.changed()
	refresh()


func _remove(uid: String) -> void:
	var campaign := GameState.campaign
	var uids := campaign.prepared_uids(sister)
	uids.erase(uid)
	campaign.set_prepared(sister, uids)
	shell.changed()
	refresh()


func _on_reset() -> void:
	CastleUI.confirm(shell, "Use the starter deck?", "%s's deck becomes the recommended %s starting deck (upgraded copies are used first)." % [_member().definition.display_name, _member().specialization.display_name], "Reset", func() -> void:
		GameState.campaign.reset_prepared_to_starter(sister)
		shell.changed()
		refresh())


func _on_save_preset() -> void:
	var campaign := GameState.campaign
	var limit := int(DeckRules.rules().get("presets_max", 6))
	var preset_name := "%s + %s" % [campaign.member("chiara").specialization.display_name, campaign.member("bianca").specialization.display_name]
	var n := 2
	var base := preset_name
	while campaign.presets.has(preset_name):
		preset_name = "%s %d" % [base, n]
		n += 1
	if campaign.presets.size() >= limit:
		shell.toast("At most %d presets: delete one first." % limit, false)
		return
	var preset := {}
	for m in campaign.roster.members:
		preset[m.id] = campaign.prepared_uids(m.id)
	campaign.presets[preset_name] = preset
	shell.changed()
	shell.toast("Saved preset \"%s\"." % preset_name)
	refresh()


func _load_preset(preset_name: String) -> void:
	var campaign := GameState.campaign
	var preset: Dictionary = campaign.presets.get(preset_name, {})
	for m in campaign.roster.members:
		campaign.set_prepared(m.id, preset.get(m.id, []))
	shell.changed()
	shell.toast("Loaded \"%s\"." % preset_name)
	refresh()
