extends Node
## Windowed QA of the merchant's gold services: cards for sale (owner pools, prices by rarity, the
## same offer after reopening), card removal (price rises per use in the run, once per visit, deck
## minimum respected) and card upgrades (price rises per use, preview before paying).
##   godot --path . res://tests/progression/shop_flow_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_shop_flow.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.5)
	await _run()
	GameState.delete_save()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _wait(0.25)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _find(node_name: String) -> Node:
	return SceneRouter.current_screen.find_child(node_name, true, false)


func _open_shop() -> void:
	SceneRouter.go(SceneRouter.Screen.MERCHANT)
	await _wait(0.6)


func _run() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "ashveil")
	GameState.create_party_from_selection()
	GameState.next_map_id = "royal_castle_tutorial"
	GameState.begin_adventure()
	var graph := GameState.map_progress.graph
	GameState.map_progress.current_node_id = "east_armory"
	GameState.begin_room(graph.get_node_data("east_armory"))
	GameState.inventory.gold = 600
	await _open_shop()

	# Cards for sale.
	var cards := _find("ShopCards") as Control
	var offers: Array = SceneRouter.current_screen._offers
	check(cards != null and offers.size() == int((ShopServices.rules()["cards"] as Dictionary)["count"]), "the shop sells %d cards" % offers.size())
	var pools_ok := true
	for offer: Dictionary in offers:
		var member := GameState.party.get_member(str(offer["owner_character_id"]))
		pools_ok = pools_ok and member.specialization.card_pool.has(str(offer["card_id"])) and int(offer["price"]) >= 30
	check(pools_ok, "every offer comes from its owner's specialization pool, with a price")
	await _wait(0.2)
	var clipped := cards.find_children("*", "CardView", true, false).filter(func(v: CardView) -> bool: return v.text_clipped)
	check(clipped.is_empty(), "every card for sale shows its full text")
	await _shot("shop_01_cards_services")
	var first: Dictionary = offers[0]
	var owner := GameState.party.get_member(str(first["owner_character_id"]))
	var deck_before := owner.deck.size()
	var gold_before := GameState.inventory.gold
	(_find("BuyCard0") as Button).pressed.emit()
	await _wait(0.3)
	check(owner.deck.size() == deck_before + 1 and GameState.inventory.gold == gold_before - int(first["price"]), "buying a card adds it to its owner's deck and costs its price")
	check((_find("BuyCard0") as Button).disabled and (_find("BuyCard0") as Button).text == "Sold", "a bought card is marked Sold")
	var seed_before := int(GameState.room_state.get("card_seed", 0))
	await _open_shop()
	var reopened: Array = SceneRouter.current_screen._offers
	check(seed_before != 0 and reopened.size() == offers.size() and reopened[0]["card_id"] == first["card_id"] and (_find("BuyCard0") as Button).text == "Sold", "reopening the shop shows the same cards, still sold")

	# Card removal.
	var removal_price := ShopServices.removal_price(0)
	var remove := _find("ShopRemove") as Button
	check(remove != null and remove.text.contains(str(removal_price)), "removal costs %dg the first time" % removal_price)
	remove.pressed.emit()
	await _wait(0.4)
	await _shot("shop_02_removal_picker")
	var bianca := GameState.party.get_member("bianca")
	var target := bianca.deck[0]
	var pick := SceneRouter.current_screen.find_child("Pick_bianca_%s" % target.uid, true, false) as CardView
	var picked_uid := target.uid
	if pick == null:  # a duplicate copy is shown instead: use the copy the picker shows
		for view: CardView in SceneRouter.current_screen.find_children("Pick_bianca_*", "CardView", true, false):
			pick = view
			picked_uid = view.name.trim_prefix("Pick_bianca_")
			break
	pick.pressed.emit(pick)
	await _wait(0.3)
	await _shot("shop_03_removal_confirm")
	var size_before := bianca.deck.size()
	gold_before = GameState.inventory.gold
	(SceneRouter.current_screen.find_child("ConfirmService", true, false) as Button).pressed.emit()
	await _wait(0.3)
	check(bianca.deck.size() == size_before - 1 and bianca.find_card(picked_uid) == null and GameState.inventory.gold == gold_before - removal_price, "the card is removed for %dg" % removal_price)
	check((_find("ShopRemove") as Button).disabled, "only one removal per visit")
	check(int(GameState.run_flags.get("shop_removals", 0)) == 1 and ShopServices.removal_price(1) > removal_price, "the next removal costs more (%dg)" % ShopServices.removal_price(1))

	# Card upgrade.
	var upgrade_price := ShopServices.upgrade_price(0)
	(_find("ShopUpgrade") as Button).pressed.emit()
	await _wait(0.4)
	var view := SceneRouter.current_screen.find_children("Pick_*", "CardView", true, false)[0] as CardView
	var parts := view.name.trim_prefix("Pick_").split("_", false, 1)
	var member := GameState.party.get_member(parts[0])
	var owned := member.find_card(parts[1])
	var level_before := owned.upgrade_level
	view.pressed.emit(view)
	await _wait(0.3)
	await _shot("shop_04_upgrade_preview")
	gold_before = GameState.inventory.gold
	(SceneRouter.current_screen.find_child("ConfirmService", true, false) as Button).pressed.emit()
	await _wait(0.3)
	check(owned.upgrade_level == level_before + 1 and GameState.inventory.gold == gold_before - upgrade_price, "the card is upgraded for %dg" % upgrade_price)
	check((_find("ShopUpgrade") as Button).text.contains(str(ShopServices.upgrade_price(1))), "the next upgrade shows its higher price")

	# Limits and saving.
	GameState.inventory.gold = 10
	await _open_shop()
	check((_find("ShopUpgrade") as Button).disabled and (_find("BuyCard1") as Button).disabled, "without gold the services and cards cannot be bought")
	GameState.save_game()
	GameState.load_game()
	check(int(GameState.run_flags.get("shop_removals", 0)) == 1 and int(GameState.run_flags.get("shop_upgrades", 0)) == 1, "the service counters survive saving and loading")
	var poor := Party.from_selection({"chiara": "fire", "bianca": "ashveil"})
	var inventory := Inventory.new()
	inventory.gold = 999
	var keep := int(RunRules.get_block("card_removal").get("min_cards_per_character", 6))
	var guard := 0
	while poor.get_member("chiara").deck.size() > keep and guard < 20:
		ShopServices.remove_card(poor, inventory, "chiara", poor.get_member("chiara").deck[0].uid, guard, 0)
		guard += 1
	var blocked := ShopServices.remove_card(poor, inventory, "chiara", poor.get_member("chiara").deck[0].uid, guard, 0)
	check(poor.get_member("chiara").deck.size() == keep and blocked != "", "a deck never goes below %d cards (%s)" % [keep, blocked])
