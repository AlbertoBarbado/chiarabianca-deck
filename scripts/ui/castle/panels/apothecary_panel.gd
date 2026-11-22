extends VBoxContainer
## Apothecary: the potion stores, buying potions, brewing known recipes (Apothecary) and widening
## the potion belt. What an expedition carries is chosen on the preparation screen.

var shell: Node
var _body: VBoxContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
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
	var top: BoxContainer = UIFactory.vbox(10) if narrow else UIFactory.hbox(10)
	_body.add_child(top)
	top.add_child(_stores_panel(campaign))
	top.add_child(_shop_panel(campaign))
	_body.add_child(_brew_panel(campaign))


func _section(title: String, node_name: String) -> PanelContainer:
	var panel := CastleUI.card_panel(6)
	panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := UIFactory.label(title, &"", false)
	heading.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	CastleUI.column_of(panel).add_child(heading)
	return panel


func _stores_panel(campaign: CampaignState) -> Control:
	var panel := _section("Stores and belt", "Stores")
	var column := CastleUI.column_of(panel)
	var stored := Apothecary.stored_potions(campaign)
	if stored.is_empty():
		column.add_child(UIFactory.label("No potions stored.", &"DimLabel", true))
	for item_id: String in stored:
		var item := DataRegistry.get_item(item_id)
		var line := UIFactory.label("%s × %d — %s" % [str(item.get("name", item_id)), int(stored[item_id]), str(item.get("description", ""))], &"", true)
		line.name = "Stored_" + item_id
		column.add_child(line)
	column.add_child(UIFactory.label("Potion belt: carries %d potions into an expedition." % campaign.potion_capacity, &"", true))
	var next := Apothecary.next_capacity_upgrade(campaign)
	if not next.is_empty():
		var widen := UIFactory.button("Wider belt (%d) — %dg" % [int(next["capacity"]), int(next["price"])], false, Vector2(0, 50))
		widen.name = "BeltUpgrade"
		widen.disabled = not campaign.vault.can_afford(int(next["price"]))
		widen.pressed.connect(func() -> void:
			CastleUI.confirm(shell, "Buy a wider belt?", "Carry %d potions on every expedition from now on, for %d gold." % [int(next["capacity"]), int(next["price"])], "Buy", func() -> void:
				var error := Apothecary.buy_capacity(campaign)
				_done(error, "The belt now holds %d potions." % campaign.potion_capacity)))
		column.add_child(widen)
	return panel


func _shop_panel(campaign: CampaignState) -> Control:
	var panel := _section("Buy", "Shop")
	var column := CastleUI.column_of(panel)
	for item_id in Apothecary.SHOP_POTIONS:
		var item := DataRegistry.get_item(item_id)
		var row := UIFactory.hbox(8)
		row.name = "Buy_" + item_id
		var label := UIFactory.label("%s — %s" % [str(item.get("name", item_id)), str(item.get("description", ""))], &"", true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buy := UIFactory.button("%dg" % Apothecary.price(item_id), false, Vector2(96, 50))
		buy.name = "BuyButton"
		buy.disabled = Apothecary.can_buy(campaign, item_id) != ""
		buy.pressed.connect(func() -> void: _done(Apothecary.buy(campaign, item_id), "Bought %s." % str(item.get("name", item_id))))
		row.add_child(buy)
		column.add_child(row)
	return panel


func _brew_panel(campaign: CampaignState) -> Control:
	var panel := _section("Brew", "Brewing")
	var column := CastleUI.column_of(panel)
	var known := Apothecary.known_recipes(campaign)
	for recipe in known:
		var row := UIFactory.hbox(8)
		row.name = "Brew_" + str(recipe["id"])
		var potion := DataRegistry.get_item(str(recipe["result"]))
		var cost: Dictionary = recipe.get("cost", {})
		var cost_text := "%dg" % int(cost.get("gold", 0)) + (" + ✦%d" % int(cost["essence"]) if int(cost.get("essence", 0)) > 0 else "")
		var label := UIFactory.label("%s × %d — %s  %s" % [str(potion.get("name", recipe["result"])), int(recipe.get("count", 1)), str(potion.get("description", "")), str(recipe.get("text", ""))], &"", true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var brew := UIFactory.button("Brew " + cost_text, false, Vector2(150, 50))
		brew.name = "BrewButton"
		var reason := Apothecary.can_brew(campaign, str(recipe["id"]))
		brew.disabled = reason != ""
		brew.tooltip_text = reason
		brew.pressed.connect(func() -> void: _done(Apothecary.brew(campaign, str(recipe["id"])), "Brewed %s." % str(potion.get("name", ""))))
		row.add_child(brew)
		column.add_child(row)
	var unknown := DataRegistry.brew_recipes.size() - known.size()
	if unknown > 0:
		column.add_child(UIFactory.label("%d more recipe%s can be learned on expeditions." % [unknown, "" if unknown == 1 else "s"], &"DimLabel", true))
	return panel


func _done(error: String, success: String) -> void:
	if error != "":
		shell.toast(error, false)
		return
	shell.changed()
	shell.toast(success)
	refresh()
