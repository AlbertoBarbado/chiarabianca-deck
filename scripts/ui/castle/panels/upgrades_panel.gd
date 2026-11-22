extends VBoxContainer
## Upgrade Workshop (castle Blacksmith). Cards: pick a collection copy, see the current and the
## upgraded card side by side with the price, confirm to upgrade it for good. Equipment: refine an
## owned item (every copy of it) up to the maximum level; the panel shows its stats now and after.

const CARD_SCALE := 0.62

var shell: Node
var tab := "cards"
var sister := "chiara"
var _body: VBoxContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	add_child(CastleUI.chips([["cards", "Cards"], ["equipment", "Equipment"]], tab, func(id: String) -> void:
		tab = id
		refresh(), "Tab", false))
	_body = UIFactory.vbox(10)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	refresh()


func refresh() -> void:
	UIFactory.clear_children(_body)
	for chip in find_children("Tab_*", "Button", true, false):
		(chip as Button).button_pressed = str(chip.name) == "Tab_" + tab
	if tab == "cards":
		_build_cards()
	else:
		_build_equipment()


func _build_cards() -> void:
	var campaign := GameState.campaign
	_body.add_child(CastleUI.chips([["chiara", "Chiara"], ["bianca", "Bianca"]], sister, func(id: String) -> void:
		sister = id
		refresh(), "Sister", false))
	_body.add_child(UIFactory.label("A permanent upgrade improves one copy in the collection for every future expedition. Prices: %s." % _price_text(), &"DimLabel", true))
	var scroll := CastleUI.flow_scroll(8)
	var grid := CastleUI.grid_of(scroll)
	grid.name = "UpgradeGrid"
	_body.add_child(scroll)
	var prepared := campaign.prepared_uids(sister)
	var groups := {}
	var order: Array[String] = []
	for owned in campaign.collection(sister):
		if CardUpgrader.can_upgrade(owned) != "":
			continue
		var key := owned.card_id + ("*" if prepared.has(owned.uid) else "")
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(owned)
	order.sort()
	for key in order:
		var copies: Array = groups[key]
		var first: OwnedCard = copies[0]
		var box := UIFactory.vbox(2)
		box.name = "Upgradable_" + key.replace("*", "_deck")
		var view := CastleUI.card(DataRegistry.get_card(first.card_id), sister, 0, CARD_SCALE)
		view.pressed.connect(func(_v: CardView) -> void: _preview_card(first))
		box.add_child(view)
		var caption := UIFactory.label("%s×%d · %dg" % ["◆ " if key.ends_with("*") else "", copies.size(), CastleWorkshop.card_upgrade_price(first)], &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
		caption.tooltip_text = "◆ = copies in the prepared deck" if key.ends_with("*") else "Copies not in the prepared deck"
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(caption)
		grid.add_child(box)
	if order.is_empty():
		grid.add_child(UIFactory.label("Every card of %s's collection is already upgraded." % DataRegistry.get_character(sister).display_name, &"DimLabel", true))


static func _price_text() -> String:
	var prices: Dictionary = CampaignRules.block("card_upgrade").get("prices", {})
	var parts: Array[String] = []
	for rarity in ["basic", "common", "uncommon", "rare"]:
		parts.append("%s %d" % [rarity, int(prices.get(rarity, 0))])
	return ", ".join(parts)


## Current vs upgraded card, price and the confirm button.
func _preview_card(owned: OwnedCard) -> void:
	var campaign := GameState.campaign
	var def := DataRegistry.get_card(owned.card_id)
	var price := CastleWorkshop.card_upgrade_price(owned)
	var reason := CastleWorkshop.can_upgrade_card(campaign, sister, owned.uid)
	var dim := ColorRect.new()
	dim.name = "UpgradePreview"
	dim.color = Color(0, 0, 0, 0.74)
	UIFactory.full_rect(dim)
	shell.add_child(dim)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	dim.add_child(center)
	var panel := UIFactory.panel()
	center.add_child(panel)
	var column := UIFactory.vbox(12)
	panel.add_child(column)
	column.add_child(UIFactory.label("Upgrade %s?" % def.display_name, &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	var pair := UIFactory.hbox(16)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	for level in [0, 1]:
		var side := UIFactory.vbox(4)
		side.add_child(UIFactory.label("Now" if level == 0 else "Upgraded", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
		var view := CastleUI.card(def, sister, level, 1.2)
		view.name = "Before" if level == 0 else "After"
		side.add_child(view)
		pair.add_child(side)
		if level == 0:
			pair.add_child(UIFactory.label("›", &"TitleLabel", false))
	column.add_child(pair)
	var info := UIFactory.label("Cost: %d gold (treasury %d). The upgrade is permanent and applies to this copy only." % [price, campaign.vault.gold], &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	info.custom_minimum_size.x = 420
	column.add_child(info)
	if reason != "":
		var warn := UIFactory.label(reason, &"", true, HORIZONTAL_ALIGNMENT_CENTER)
		warn.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.3))
		column.add_child(warn)
	var buttons := UIFactory.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel := UIFactory.button("Cancel", false, Vector2(170, 56))
	cancel.name = "Cancel"
	cancel.pressed.connect(dim.queue_free)
	buttons.add_child(cancel)
	var ok := UIFactory.button("Upgrade (%dg)" % price, true, Vector2(220, 56))
	ok.name = "ConfirmUpgrade"
	ok.disabled = reason != ""
	ok.pressed.connect(func() -> void:
		dim.queue_free()
		var error := CastleWorkshop.upgrade_card(campaign, sister, owned.uid)
		if error != "":
			shell.toast(error, false)
			return
		shell.changed()
		shell.toast("%s upgraded for good." % def.display_name)
		refresh())
	buttons.add_child(ok)
	column.add_child(buttons)


func _build_equipment() -> void:
	var campaign := GameState.campaign
	var rules := CampaignRules.block("refinement")
	_body.add_child(UIFactory.label("Refining an item improves every copy of it, up to level %d: each stat it already has grows (+%d Max HP, +%d%% resistance or damage per level)." % [int(rules.get("max_level", 2)), int(rules["per_level"]["max_hp"]), int(rules["per_level"]["resist"])], &"DimLabel", true))
	var scroll := UIFactory.scroll()
	var list := UIFactory.vbox(8)
	list.name = "ItemList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_body.add_child(scroll)
	var items := CastleWorkshop.owned_items(campaign)
	items.sort_custom(func(a: String, b: String) -> bool: return str(Equipment.item(a).get("name", a)) < str(Equipment.item(b).get("name", b)))
	if items.is_empty():
		list.add_child(UIFactory.label("The armory is empty. Equipment found on expeditions comes home with the sisters.", &"DimLabel", true))
	for item_id in items:
		list.add_child(_item_row(item_id))


func _item_row(item_id: String) -> Control:
	var campaign := GameState.campaign
	var item := Equipment.item(item_id)
	var level := CastleWorkshop.refinement_level(campaign, item_id)
	var max_level := int(CampaignRules.block("refinement").get("max_level", 2))
	var panel := CastleUI.card_panel(4, Equipment.rarity_color(str(item.get("rarity", "common"))))
	panel.name = "Item_" + item_id
	var row := UIFactory.hbox(12)
	CastleUI.column_of(panel).add_child(row)
	var icon := TextureRect.new()
	icon.texture = Equipment.icon(item_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(56, 56)
	row.add_child(icon)
	var texts := UIFactory.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIFactory.label("%s  %s" % [str(item.get("name", item_id)), ("+%d" % level) if level > 0 else ""], &"", false)
	title.add_theme_color_override("font_color", Equipment.rarity_color(str(item.get("rarity", "common"))).lightened(0.2))
	texts.add_child(title)
	texts.add_child(UIFactory.label(", ".join(Equipment.stat_lines(item_id)) + _bonus_text(Equipment.refined_bonus(item_id, level)), &"DimLabel", true))
	if level < max_level and not Equipment.refined_bonus(item_id, 1).is_empty():
		var next := UIFactory.label("Next level: " + _bonus_text(Equipment.refined_bonus(item_id, level + 1)).trim_prefix(" · refined "), &"", true)
		next.add_theme_color_override("font_color", UITheme.GREEN.lightened(0.3))
		texts.add_child(next)
	row.add_child(texts)
	var reason := CastleWorkshop.can_refine(campaign, item_id)
	var button := UIFactory.button(("Refine (%dg)" % CastleWorkshop.refine_price(campaign, item_id)) if level < max_level else "Max level", reason == "", Vector2(190, 52))
	button.name = "Refine"
	button.disabled = reason != ""
	button.tooltip_text = reason
	button.pressed.connect(func() -> void:
		CastleUI.confirm(shell, "Refine %s?" % str(item.get("name", item_id)), "Level %d → %d for %d gold. Every copy of this item improves." % [level, level + 1, CastleWorkshop.refine_price(campaign, item_id)], "Refine", func() -> void:
			var error := CastleWorkshop.refine(campaign, item_id)
			if error != "":
				shell.toast(error, false)
				return
			shell.changed()
			shell.toast("%s refined." % str(item.get("name", item_id)))
			refresh()))
	row.add_child(button)
	return panel


static func _bonus_text(bonus: Dictionary) -> String:
	if bonus.is_empty():
		return ""
	var parts: Array[String] = []
	if int(bonus.get("max_hp", 0)) > 0:
		parts.append("+%d Max HP" % int(bonus["max_hp"]))
	for key in ["resist", "damage"]:
		var bucket: Dictionary = bonus.get(key, {})
		for element: String in bucket:
			parts.append(Equipment.describe_delta("%s:%s" % [key, element], int(bucket[element])))
	return " · refined " + ", ".join(parts)
