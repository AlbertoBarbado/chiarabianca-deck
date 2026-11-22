extends VBoxContainer
## Deck Workshop (castle Library): each sister's prepared deck built from her collection.
## Left: the prepared deck (tap a card to inspect / remove). Right: the collection copies not in the
## deck, filtered by specialization, type, rarity and synergy tag (tap to inspect / add). Deck rules
## (DeckRules) are checked live; presets save and load whole configurations.

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
var _collection_grid: HFlowContainer
var _filters: VBoxContainer
var _presets_row: HFlowContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	var top := UIFactory.hbox(12)
	top.add_child(CastleUI.chips([["chiara", "Chiara"], ["bianca", "Bianca"]], sister, _pick_sister, "Sister", false))
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
	deck_column.add_child(UIFactory.label("Prepared deck", &"", false))
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
	UIFactory.clear_children(_deck_grid)
	var cards := campaign.prepared_cards(sister)
	cards.sort_custom(func(a: OwnedCard, b: OwnedCard) -> bool: return _sort_key(a) < _sort_key(b))
	for owned in cards:
		var view := CastleUI.card(DataRegistry.get_card(owned.card_id), sister, owned.upgrade_level, CARD_SCALE)
		view.name = "Deck_" + owned.uid
		view.pressed.connect(func(_v: CardView) -> void: _inspect_deck_card(owned))
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
		view.pressed.connect(func(_v: CardView) -> void: _inspect_collection_card(first, copies.size(), reason))
		box.add_child(view)
		box.add_child(UIFactory.label("× %d" % copies.size(), &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
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
		load_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		load_button.tooltip_text = "Load this configuration for both sisters."
		load_button.pressed.connect(_load_preset.bind(preset_name))
		_presets_row.add_child(load_button)
		var delete := UIFactory.button("✕", false, Vector2(44, 44))
		delete.name = "DeletePreset_" + preset_name.replace(" ", "_")
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
	for chip in find_children("Sister_*", "Button", true, false):
		(chip as Button).button_pressed = str(chip.name) == "Sister_" + id


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
