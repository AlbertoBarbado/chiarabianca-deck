extends ScreenBase
## Merchant room: cards for sale, gold services (remove or upgrade a card) and the item stock.
## Shop logic lives in Merchant (items) and ShopServices (cards, removal, upgrades); this screen only
## presents them. Per-visit state (the card offer seed, cards bought, services used here) is saved in
## the room state; the run-wide service counters that raise prices live in GameState.run_flags.

const CARD_SCALE := 1.0
const MERCHANT_ART_SIZE := Vector2(400, 300)  # 4:3: shows three quarters of the 16:9 picture
const MERCHANT_ART_FOCUS := Vector2(0.3, 0.45)

var _merchant: Merchant
var _shop_def: Dictionary
var _gold_label: Label
var _message: Label
var _stock_box: VBoxContainer
var _offers: Array[Dictionary] = []


func _build() -> void:
	var node := GameState.get_current_node()
	_shop_def = DataRegistry.get_shop(GameState.current_shop_id())
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = _visit_seed() + 7919  # same gear offers after a reload
	_merchant = Merchant.from_definition(_shop_def, GameState.party, gear_rng)
	if GameState.in_room(node.id):
		_merchant.apply_purchases(GameState.room_state.get("bought", {}))
	_roll_offers()
	# With art ("art" in the shop definition): a left column with the merchant's picture (a wide
	# frame cropped around them: "art_focus": [x, y] in 0..1), the shop's name, greeting, gold and
	# the way out; the stock fills the right. Without art: the stock page alone, as before.
	var layout := UIFactory.hbox(20)
	root.add_child(layout)
	var focus_data: Array = _shop_def.get("art_focus", [])
	var focus := Vector2(float(focus_data[0]), float(focus_data[1])) if focus_data.size() == 2 else MERCHANT_ART_FOCUS
	var art := FramedArt.create(str(_shop_def.get("art", "")), MERCHANT_ART_SIZE, focus)
	var has_art := art.has_art()
	var side := UIFactory.vbox(8)
	if has_art:
		side.custom_minimum_size.x = MERCHANT_ART_SIZE.x
		layout.add_child(side)
		art.name = "MerchantArt"
		side.add_child(art)
	else:
		art.free()
	var column := UIFactory.vbox(10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(column)

	var titles := UIFactory.vbox(2)
	titles.add_child(UIFactory.label(_merchant.display_name, &"HeaderLabel"))
	titles.add_child(UIFactory.label(_merchant.greeting, &"DimLabel", true))
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gold_row := UIFactory.hbox(6)
	gold_row.add_child(UIFactory.icon("gold", 30))
	_gold_label = UIFactory.label("")
	_gold_label.name = "ShopGold"
	_gold_label.add_theme_color_override("font_color", UITheme.GOLD)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_row.add_child(_gold_label)
	var leave := UIFactory.button("Back to Town" if node.type == MapNodeData.TYPE_TOWN else "Return to Map", false, Vector2(240, 56))
	leave.pressed.connect(func() -> void: SceneRouter.leave_service())
	if has_art:
		side.add_child(titles)
		side.add_child(gold_row)
		side.add_child(_vertical_spacer())
		leave.size_flags_horizontal = Control.SIZE_FILL
		side.add_child(leave)
	else:
		var top := UIFactory.hbox()
		top.add_child(titles)
		top.add_child(gold_row)
		column.add_child(top)

	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	_stock_box = UIFactory.vbox(12)
	_stock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock_box)

	_message = UIFactory.label("", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_message.name = "ShopMessage"
	column.add_child(_message)
	if not has_art:
		var footer := UIFactory.hbox()
		footer.add_child(UIFactory.expander())
		footer.add_child(leave)
		column.add_child(footer)
	_refresh()


func _vertical_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## This visit's saved seed (made on first use): card and gear offers roll from it, so a reload shows the same.
func _visit_seed() -> int:
	var seed_value := int(GameState.room_state.get("card_seed", 0))
	if seed_value == 0:
		seed_value = randi() % 2000000000 + 1
		GameState.update_room({"card_seed": seed_value})
	return seed_value


## The card offer is rolled once per visit from a saved seed, so a reload shows the same cards.
func _roll_offers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _visit_seed()
	_offers = ShopServices.card_offers(GameState.party, rng, _shop_def)


func _room_value(key: String, fallback: Variant) -> Variant:
	return GameState.room_state.get(key, fallback)


func _refresh() -> void:
	_gold_label.text = "Gold: %d" % GameState.inventory.gold
	UIFactory.clear_children(_stock_box)
	if not _offers.is_empty():
		_stock_box.add_child(_section("Cards for sale", "Each card joins its owner's deck."))
		_stock_box.add_child(_cards_row())
	if ShopServices.service_enabled("removal", _shop_def) or ShopServices.service_enabled("upgrade", _shop_def):
		_stock_box.add_child(_section("Services", "Prices rise each time you use a service during the run."))
		_stock_box.add_child(_services_row())
	if not _merchant.stock.is_empty():
		_stock_box.add_child(_section("Wares", ""))
	for entry in _merchant.stock:
		_stock_box.add_child(_item_row(entry))


func _section(title: String, hint: String) -> Control:
	var row := UIFactory.hbox(12)
	var heading := UIFactory.label(title, &"HeaderLabel")
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	row.add_child(heading)
	if hint != "":
		var dim := UIFactory.label(hint, &"DimLabel")
		dim.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		dim.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(dim)
	return row


func _cards_row() -> Control:
	var row := UIFactory.hbox(16)
	row.name = "ShopCards"
	var bought: Array = _room_value("cards_bought", [])
	for i in _offers.size():
		var offer := _offers[i]
		var box := UIFactory.vbox(4)
		var view := CardView.new()
		view.show_owned(DataRegistry.get_card(str(offer["card_id"])), str(offer["owner_character_id"]))
		view.set_scale_factor(CARD_SCALE)
		box.add_child(view)
		var sold := bought.has(i)
		var buy := UIFactory.button("Sold" if sold else "%dg" % int(offer["price"]), not sold, Vector2(140, 44))
		buy.name = "BuyCard%d" % i
		buy.disabled = sold or not GameState.inventory.can_afford(int(offer["price"]))
		buy.pressed.connect(_on_buy_card.bind(i))
		box.add_child(buy)
		if sold:
			view.modulate = Color(1, 1, 1, 0.4)
		row.add_child(box)
	return row


func _services_row() -> Control:
	var row := UIFactory.hbox(16)
	row.name = "ShopServices"
	if ShopServices.service_enabled("removal", _shop_def):
		var price := ShopServices.removal_price(int(GameState.run_flags.get("shop_removals", 0)), _shop_def)
		var used := int(_room_value("removed_here", 0)) >= int((ShopServices.rules(_shop_def)["removal"] as Dictionary).get("per_visit", 1))
		var remove := UIFactory.button("Remove a card · %dg" % price, false, Vector2(280, 56))
		remove.name = "ShopRemove"
		remove.tooltip_text = "Permanently remove one card from a princess's deck (her deck keeps at least the minimum size)."
		remove.disabled = used or not GameState.inventory.can_afford(price)
		remove.pressed.connect(_open_picker.bind("remove"))
		row.add_child(remove)
	if ShopServices.service_enabled("upgrade", _shop_def):
		var price := ShopServices.upgrade_price(int(GameState.run_flags.get("shop_upgrades", 0)), _shop_def)
		var used := int(_room_value("upgraded_here", 0)) >= int((ShopServices.rules(_shop_def)["upgrade"] as Dictionary).get("per_visit", 2))
		var upgrade := UIFactory.button("Upgrade a card · %dg" % price, false, Vector2(280, 56))
		upgrade.name = "ShopUpgrade"
		upgrade.tooltip_text = "Upgrade one card permanently, like at a rest site."
		upgrade.disabled = used or not GameState.inventory.can_afford(price)
		upgrade.pressed.connect(_open_picker.bind("upgrade"))
		row.add_child(upgrade)
	return row


func _item_row(entry: Dictionary) -> Control:
	var item := DataRegistry.get_item(entry["item_id"])
	var row := UIFactory.panel()
	var line := UIFactory.hbox(16)
	row.add_child(line)
	var gear := Equipment.is_equipment(entry["item_id"])
	if gear:  # equipment: its picture, rarity colour and stats
		line.add_child(ItemTile.create(entry["item_id"], "", Vector2(56, 56)))
	else:
		line.add_child(UIFactory.icon("potion", 40))
	var text := UIFactory.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var owned := GameState.inventory.equipment.count(entry["item_id"]) if gear else GameState.inventory.count_of(entry["item_id"])
	var title := UIFactory.label("%s   (owned: %d)" % [item.get("name", entry["item_id"]), owned])
	if gear:
		title.add_theme_color_override("font_color", Equipment.rarity_color(str(item.get("rarity", "common"))))
	text.add_child(title)
	var description := ", ".join(Equipment.stat_lines(entry["item_id"])) if gear else str(item.get("description", ""))
	text.add_child(UIFactory.label(description, &"DimLabel", true))
	line.add_child(text)
	var quantity: int = entry["quantity"]
	line.add_child(UIFactory.label("Stock: %s" % ("∞" if quantity < 0 else str(quantity)), &"DimLabel"))
	var buy := UIFactory.button("Buy · %dg" % entry["price"], true, Vector2(160, 56))
	buy.disabled = quantity == 0 or not GameState.inventory.can_afford(entry["price"])
	buy.pressed.connect(_on_buy.bind(entry["item_id"]))
	line.add_child(buy)
	return row


func _on_buy(item_id: String) -> void:
	var error := _merchant.buy(item_id, GameState.inventory)
	_message.text = error if error != "" else "Purchased %s." % DataRegistry.get_item(item_id).get("name", item_id)
	if error == "":
		var bought: Dictionary = (GameState.room_state.get("bought", {}) as Dictionary).duplicate()
		bought[item_id] = int(bought.get(item_id, 0)) + 1
		GameState.update_room({"bought": bought})  # Save inside the room: gold, stock and items stay in sync.
	_refresh()


func _on_buy_card(index: int) -> void:
	var bought: Array = (_room_value("cards_bought", []) as Array).duplicate()
	if bought.has(index):
		return
	var offer := _offers[index]
	var error := ShopServices.buy_card(offer, GameState.party, GameState.inventory)
	if error == "":
		bought.append(index)
		GameState.update_room({"cards_bought": bought})
		_message.text = "%s joins %s's deck." % [DataRegistry.get_card(str(offer["card_id"])).display_name, GameState.party.get_member(str(offer["owner_character_id"])).definition.display_name]
	else:
		_message.text = error
	_refresh()


# --- Card picker for removal / upgrade --------------------------------------------------------------

func _open_picker(mode: String) -> void:
	_close_picker()
	var dim := ColorRect.new()
	dim.name = "ShopPicker"
	dim.color = Color(UITheme.NAVY_DEEP, 0.94)
	dim.z_index = 50
	UIFactory.full_rect(dim)
	add_child(dim)
	var margin := MarginContainer.new()
	UIFactory.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	dim.add_child(margin)
	var column := UIFactory.vbox(10)
	margin.add_child(column)
	var price := ShopServices.removal_price(int(GameState.run_flags.get("shop_removals", 0)), _shop_def) if mode == "remove" else ShopServices.upgrade_price(int(GameState.run_flags.get("shop_upgrades", 0)), _shop_def)
	column.add_child(UIFactory.label(("Remove a card · %dg" if mode == "remove" else "Upgrade a card · %dg") % price, &"HeaderLabel"))
	column.add_child(UIFactory.label("Tap a card to %s it." % ("remove" if mode == "remove" else "upgrade"), &"DimLabel"))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(flow)
	for member in GameState.party.members:
		var seen: Dictionary = {}
		for owned in member.deck:
			var key := "%s@%d" % [owned.card_id, owned.upgrade_level]
			if seen.has(key) or (mode == "upgrade" and CardUpgrader.can_upgrade(owned) != ""):
				continue
			seen[key] = true
			var view := CardView.new()
			view.name = "Pick_%s_%s" % [member.id, owned.uid]
			view.show_owned(DataRegistry.get_card(owned.card_id), member.id, owned.upgrade_level)
			view.pressed.connect(func(_v: CardView) -> void: _confirm(mode, member, owned, price))
			flow.add_child(view)
	var footer := UIFactory.hbox()
	footer.add_child(UIFactory.expander())
	var cancel := UIFactory.button("Cancel", false, Vector2(200, 52))
	cancel.name = "PickerCancel"
	cancel.pressed.connect(_close_picker)
	footer.add_child(cancel)
	column.add_child(footer)


func _confirm(mode: String, member: PartyMember, owned: OwnedCard, price: int) -> void:
	_close_picker()
	var dim := ColorRect.new()
	dim.name = "ShopPicker"
	dim.color = Color(UITheme.NAVY_DEEP, 0.94)
	dim.z_index = 50
	UIFactory.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	dim.add_child(center)
	var column := UIFactory.vbox(14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)
	var def := DataRegistry.get_card(owned.card_id)
	column.add_child(UIFactory.label(("Remove %s from %s's deck for %dg?" if mode == "remove" else "Upgrade %s (%s) for %dg?") % [def.display_name, member.definition.display_name, price], &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	var cards := UIFactory.hbox(24)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	var before := CardView.new()
	before.show_owned(def, member.id, owned.upgrade_level)
	before.set_scale_factor(1.2)
	cards.add_child(before)
	if mode == "upgrade":
		cards.add_child(UIFactory.label("→", &"HeaderLabel"))
		var after := CardView.new()
		after.show_owned(def, member.id, owned.upgrade_level + 1)
		after.set_scale_factor(1.2)
		cards.add_child(after)
	column.add_child(cards)
	var buttons := UIFactory.hbox(16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UIFactory.button("Back", false, Vector2(180, 52))
	back.pressed.connect(_open_picker.bind(mode))
	buttons.add_child(back)
	var ok := UIFactory.button("Remove · %dg" % price if mode == "remove" else "Upgrade · %dg" % price, true, Vector2(220, 52))
	ok.name = "ConfirmService"
	ok.pressed.connect(_apply_service.bind(mode, member.id, owned.uid))
	buttons.add_child(ok)
	column.add_child(buttons)


func _apply_service(mode: String, character_id: String, uid: String) -> void:
	var error := ""
	var card_name := DataRegistry.get_card(GameState.party.get_member(character_id).find_card(uid).card_id).display_name
	if mode == "remove":
		error = ShopServices.remove_card(GameState.party, GameState.inventory, character_id, uid, int(GameState.run_flags.get("shop_removals", 0)), int(_room_value("removed_here", 0)), _shop_def)
		if error == "":
			GameState.run_flags["shop_removals"] = int(GameState.run_flags.get("shop_removals", 0)) + 1
			GameState.update_room({"removed_here": int(_room_value("removed_here", 0)) + 1})
	else:
		error = ShopServices.upgrade_card(GameState.party, GameState.inventory, character_id, uid, int(GameState.run_flags.get("shop_upgrades", 0)), int(_room_value("upgraded_here", 0)), _shop_def)
		if error == "":
			GameState.run_flags["shop_upgrades"] = int(GameState.run_flags.get("shop_upgrades", 0)) + 1
			GameState.update_room({"upgraded_here": int(_room_value("upgraded_here", 0)) + 1})
	_close_picker()
	_message.text = error if error != "" else ("%s was removed." % card_name if mode == "remove" else "%s was upgraded." % card_name)
	_refresh()


func _close_picker() -> void:
	var existing := get_node_or_null("ShopPicker")
	if existing != null:
		remove_child(existing)
		existing.queue_free()


## In a town: the town's scene. A merchant room of its own (the castle armoury): the shop's picture.
func _backdrop() -> Dictionary:
	var backdrop := current_room_backdrop()
	var shop_art := str(DataRegistry.get_shop(GameState.current_shop_id()).get("art", ""))
	if GameState.current_town().is_empty() and shop_art != "" and AssetCatalog.texture(shop_art) != null:
		return AssetCatalog.backdrop_by_asset(shop_art, backdrop.get("tint", UITheme.GOLD))
	return backdrop
