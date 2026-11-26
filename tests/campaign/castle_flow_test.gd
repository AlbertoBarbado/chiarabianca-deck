extends Node
## Windowed walkthrough of the persistent campaign through the real screens: main menu, new
## campaign, castle hub, every service panel, world map, preparation, an expedition with the
## objective tracker, retreat and completion with results and discoveries, permanent upgrade,
## fusion, a generated mission map, and the main screens at phone size (844x390).
##   godot --path . res://tests/campaign/castle_flow_test.tscn -- <screenshot_dir>

const SAVE := "user://test_castle_flow.json"

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	get_window().size = Vector2i(1280, 720)
	GameState.save_path = SAVE
	for slot in [GameState.SLOT_CAMPAIGN, GameState.SLOT_QUICKPLAY]:
		GameState.use_slot(slot)
		GameState.delete_save()
	GameState.use_slot(GameState.SLOT_CAMPAIGN)
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.5)
	await _run()
	for slot in [GameState.SLOT_CAMPAIGN, GameState.SLOT_QUICKPLAY]:
		GameState.use_slot(slot)
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


func _screen() -> Node:
	return SceneRouter.current_screen


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _find(node_name: String) -> Node:
	return _screen().find_child(node_name, true, false) if _screen() != null else null


func _button(text_part: String, root: Node = null) -> Button:
	var stack: Array[Node] = [root if root != null else _screen()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text.contains(text_part) and (n as Button).is_visible_in_tree():
			return n
		stack.append_array(n.get_children())
	return null


func _press_node(node_name: String) -> bool:
	var b := _find(node_name) as Button
	if b == null or b.disabled:
		print("    cannot press ", node_name)
		return false
	b.pressed.emit()
	await _wait(0.4)
	return true


func _press(text_part: String) -> bool:
	var b := _button(text_part)
	if b == null or b.disabled:
		print("    cannot press '", text_part, "'")
		return false
	b.pressed.emit()
	await _wait(0.4)
	return true


## Presses the Confirm button of an open confirmation dialog.
func _confirm() -> bool:
	var dialog := _screen().find_child("ConfirmDialog", true, false)
	if dialog == null:
		return false
	(dialog.find_child("Confirm", true, false) as Button).pressed.emit()
	await _wait(0.4)
	return true


## Levels, Mastery cards, the Dual Specialization and region contracts through the real screens.
func _levels_and_contracts() -> void:
	var campaign := GameState.campaign
	# A finished expedition that levels the sisters up to 5: the results show it and offer Mastery.
	campaign.level_rewards.clear()
	for m in campaign.roster.members:
		campaign.levels[m.id] = Levels.threshold(4) + 5
	campaign.refresh_roster()
	check(ExpeditionService.start("castle_awakening", {}, 5) == "", "a castle run starts for the level-up")
	GameState.expedition.fight_xp = 200
	GameState.finish_expedition("completed")
	SceneRouter.go(SceneRouter.Screen.EXPEDITION_RESULTS)
	await _wait(0.6)
	check(_find("LevelUp") != null and Levels.level_of(campaign, "chiara") >= 5, "the results announce the level-up")
	check(_find("MasteryChoices") != null and _find("Mastery_0") != null and _find("MasteryCard_0") != null, "the results offer the Mastery card choice")
	await _shot("cf_30_level_up")
	var pending := campaign.level_rewards.size()
	var card := _find("MasteryCard_0") as CardView
	card.pressed.emit(card)
	await _wait(0.3)
	await _confirm()
	await _wait(0.3)
	check(campaign.level_rewards.size() == pending - 1, "tapping a Mastery card and confirming takes it")
	await _press_node("ReturnHomeButton")
	await _wait(0.5)
	if _find("ConfirmDialog") != null:
		await _confirm()
	check(GameState.in_castle(), "back at the castle after the level-up")
	if not campaign.level_rewards.is_empty():
		check(_find("Service_sisters") != null and _find("Service_sisters").find_child("Notice", true, false) != null, "the Sisters plaque shows the waiting Mastery card")
	# The Sisters panel: level bars, milestones, the remaining choice.
	SceneRouter.open_service("sisters")
	await _wait(0.6)
	check(_find("LevelSummary") != null and _find("Level_chiara") != null and _find("Milestones") != null, "the Sisters panel shows levels and milestones")
	await _shot("cf_31_sister_levels")
	# Level 10: the Training Hall offers the second specialization.
	for m in campaign.roster.members:
		campaign.levels[m.id] = Levels.threshold(10)
	campaign.refresh_roster()
	SceneRouter.open_service("training_hall")
	await _wait(0.6)
	check(_find("DualReady") != null, "the Training Hall announces the Dual Specialization")
	var row := _find("Training_bianca")
	var second: Button = null
	for button: Button in row.find_children("SetSecondary", "Button", true, false):
		if not button.disabled:
			second = button
			break
	check(second != null, "Bianca has a second-style button")
	if second != null:
		second.pressed.emit()
		await _wait(0.3)
		await _confirm()
		await _wait(0.3)
	check(campaign.member("bianca").secondary_specialization != null and campaign.member("bianca").specialization.id == "holy", "Bianca takes a second style and keeps Holy as her primary")
	await _shot("cf_32_dual_spec")
	# Contracts: every castle mission done -> a contract with its rank and level on the war table.
	campaign.mark_mission_completed("castle_gauntlet")
	campaign.refresh_roster()
	SceneRouter.go(SceneRouter.Screen.WORLD_MAP)
	await _wait(0.8)
	var contract_card := _find("Mission_contract_royal_castle_1")
	check(contract_card != null and contract_card.find_child("ContractRank", true, false) != null and contract_card.find_child("LevelReq", true, false) != null, "the war table shows the castle contract with its rank and level")
	await _shot("cf_33_contract")
	_fits("world map with a contract")
	await _press_node("Prepare_contract_royal_castle_1")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EXPEDITION_PREP and _find("LevelPill") != null, "a contract can be prepared; the sisters show their level")
	_fits("contract preparation")
	SceneRouter.go(SceneRouter.Screen.CASTLE_HUB)
	await _wait(0.4)


## Nothing on the screen needs more width than the window has, and every button outside a scroll
## area is fully on screen.
func _fits(label: String) -> void:
	var screen := _screen() as Control
	var area := screen.get_viewport_rect()
	var min_width := (screen.get_child(screen.get_child_count() - 1) as Control).get_combined_minimum_size().x
	var off: Array[String] = []
	for button: Button in screen.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree() or _in_scroll(button):
			continue
		if not area.grow(1.0).encloses(button.get_global_rect()):
			off.append(button.name)
	check(min_width <= area.size.x + 1.0 and off.is_empty(), "%s fits %dx%d (min width %d, off screen: %s)" % [label, get_window().size.x, get_window().size.y, int(min_width), ", ".join(off)])


func _mouse_button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)


func _motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	Input.warp_mouse(at)


func _tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	_mouse_button(at, true)
	await get_tree().process_frame
	_mouse_button(at, false)
	await _wait(0.35)


## Press on `from`, move in small steps to the middle of `to` and release there.
func _drag(from: Control, to: Control) -> void:
	var start := from.get_global_rect().get_center()
	var end := to.get_global_rect().get_center()
	_mouse_button(start, true)
	await get_tree().process_frame
	var previous := start
	for i in range(1, 13):
		var point := start.lerp(end, i / 12.0)
		_motion(point, point - previous)
		previous = point
		await get_tree().process_frame
	await _wait(0.1)
	_mouse_button(end, false)
	await _wait(0.4)


func _in_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _run() -> void:
	# --- Main menu and a new campaign -----------------------------------------------------------
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.6)
	check(_button("New Campaign") != null and _button("Continue").disabled and _button("Quick Play") != null and _button("Classic Run") == null, "the menu offers New Campaign, a disabled Continue and Quick Play (its shortcuts tucked away)")
	await _press("Quick Play")
	check(_button("Classic Run") != null and _button("Frostpeak") != null and _button("New Campaign") == null, "Quick Play opens the classic run and the direct starts")
	await _press("Back")
	await _shot("cf_01_main_menu")
	await _press("New Campaign")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.CHARACTER_SELECTION and GameState.new_game_mode == "campaign", "New Campaign opens the selection in campaign mode")
	await _press("Choose Specializations")
	for spec in ["Fire", "Holy"]:
		for b in _screen().find_children("*", "Button", true, false):
			if (b is ChoiceCard and (b as ChoiceCard).get_title() == spec) or ((b as Button).text == spec):
				(b as Button).pressed.emit()
				await _wait(0.2)
				break
	await _press("Confirm Party")
	check(_button("Begin the Campaign") != null, "the party overview offers Begin the Campaign")
	await _press("Begin the Campaign")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.CASTLE_HUB and GameState.in_castle(), "the campaign begins at the castle")
	check(GameState.has_save() and GameState.active_slot() == GameState.SLOT_CAMPAIGN, "the castle is saved in the campaign slot")
	check(_find("Service_blacksmith") != null and (_find("Service_blacksmith") as Button).disabled and not (_find("Service_library") as Button).disabled, "open and locked services are shown")
	await _shot("cf_02_castle_hub")
	_fits("castle hub")
	# --- Deck Workshop ---------------------------------------------------------------------------
	await _press_node("Service_library")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.CASTLE_SERVICE and _find("DeckGrid") != null, "the Deck Workshop opens in the service shell")
	var deck_grid := _find("DeckGrid")
	check(deck_grid.get_child_count() == 10, "Chiara's prepared deck shows 10 cards")
	await _shot("cf_03_deck_workshop")
	var first := deck_grid.get_child(0) as CardView
	await _tap(first)  # workshop cards open on release, so a press can start a drag
	await _press_node("Action_Remove")
	check(GameState.campaign.prepared_uids("chiara").size() == 9, "a card is removed from the prepared deck")
	var owned := _find("CollectionGrid").get_child(0)
	var view := owned.get_child(0) as CardView
	await _tap(view)
	await _press_node("Action_AddtoDeck")
	check(GameState.campaign.prepared_uids("chiara").size() == 10, "a collection card is added back")
	var rarity := _find("RarityFilter") as OptionButton
	rarity.select(1)
	rarity.item_selected.emit(1)
	await _wait(0.4)
	check(_find("CollectionGrid").get_child_count() >= 1, "rarity filter applied")
	# Drag and drop with real pointer input: deck -> collection removes, collection -> deck adds, a tap inspects.
	var deck_card := _find("DeckGrid").get_child(0) as CardView
	var before_drag := GameState.campaign.prepared_uids("chiara").size()
	await _drag(deck_card, _find("CollectionGrid") as Control)
	check(GameState.campaign.prepared_uids("chiara").size() == before_drag - 1 and _screen().find_child("CardInspect", true, false) == null, "dragging a deck card onto the collection removes it (no details pop up)")
	await _shot("cf_03b_after_drag")
	var stored := _find("CollectionGrid").get_child(0).get_child(0) as CardView
	await _drag(stored, _find("DeckGrid") as Control)
	check(GameState.campaign.prepared_uids("chiara").size() == before_drag, "dragging a collection card onto the deck adds it back")
	await _tap(_find("DeckGrid").get_child(0) as Control)
	check(_screen().find_child("CardInspect", true, false) != null, "a tap still opens the card details")
	(_screen().find_child("CardInspect", true, false) as Node).queue_free()
	await _wait(0.2)
	await _press_node("SavePresetButton")
	check(GameState.campaign.presets.size() == 1, "a deck preset is saved")
	await _press_node("Sister_bianca")
	check((_find("DeckStatus") as Label).text.begins_with("Bianca"), "switching to Bianca's deck")
	await _press_node("BackButton")
	# --- Collection, Apothecary, Sisters ---------------------------------------------------------
	await _press_node("Service_collection")
	check(_find("CollectionGrid") != null and _find("CollectionGrid").get_child_count() > 20, "the collection lists found and missing cards")
	await _shot("cf_04_collection")
	await _press_node("BackButton")
	await _press_node("Service_apothecary")
	var potions := GameState.campaign.vault.count_of("minor_health_potion")
	var buy := _find("Buy_minor_health_potion").find_child("BuyButton", true, false) as Button
	buy.pressed.emit()
	await _wait(0.3)
	check(GameState.campaign.vault.count_of("minor_health_potion") == potions + 1, "a potion is bought with treasury gold")
	await _shot("cf_05_apothecary")
	await _press_node("BackButton")
	await _press_node("Service_sisters")
	check(_find("BondTitle") != null and (_find("BondTitle") as Label).text.contains("1"), "the Sisters panel shows Bond level 1")
	await _shot("cf_06_bond")
	await _press_node("BackButton")
	# --- World map, preparation, expedition, retreat ---------------------------------------------
	await _press_node("SetOutButton")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.WORLD_MAP and ["royal_castle", "crystal_hollow", "enchanted_forest", "sunlit_coast", "frostpeak"].all(func(r: String) -> bool: return _find("Region_" + r) != null), "the war table shows every region: castle, Crystal Cave, forest, coast and Frostpeak")
	check(_find("Prepare_castle_awakening") != null and not (_find("Prepare_castle_awakening") as Button).disabled, "the first mission can be prepared")
	await _shot("cf_07_world_map")
	_fits("world map")
	(_find("Region_enchanted_forest") as Button).pressed.emit()
	await _wait(0.3)
	check(_find("Mission_forest_serpent") == null and _screen().find_child("RegionDetail", true, false).get_child_count() >= 3, "a locked region shows why it is locked")
	(_find("Region_royal_castle") as Button).pressed.emit()
	await _wait(0.3)
	await _press_node("Prepare_castle_awakening")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EXPEDITION_PREP and _find("PotionBelt") != null, "the preparation screen opens")
	await _shot("cf_08_preparation")
	_fits("preparation")
	await _press_node("EmbarkButton")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.expedition != null and _find("ObjectiveTracker") != null, "the expedition starts on the map with an objective tracker")
	await _shot("cf_09_expedition_map")
	await _press_node("RetreatButton")
	await _confirm()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EXPEDITION_RESULTS and GameState.expedition.outcome == "retreated", "Retreat ends the expedition on the results screen")
	await _shot("cf_10_results_retreat")
	await _press_node("ReturnHomeButton")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.CASTLE_HUB and GameState.in_castle(), "back at the castle")
	# --- A completed expedition with a discovery -------------------------------------------------
	check(ExpeditionService.start("castle_awakening", {}, 3) == "", "a second expedition starts")
	GameState.party.get_member("bianca").add_card("bianca_holy_touch")
	GameState.inventory.add_gold(40)
	var exit := GameState.map_progress.graph.get_node_data(GameState.map_progress.graph.exit_node_id)
	GameState.map_progress.current_node_id = exit.id
	SceneRouter.go_to_room(exit)
	await _wait(0.6)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EXPEDITION_RESULTS and GameState.expedition.outcome == "completed", "reaching the gate completes the mission")
	check(_find("Discoveries") != null and _find("DiscoveryCards").get_child_count() == 1, "the drafted card is offered as a discovery")
	await _shot("cf_11_results_complete")
	var touches := GameState.campaign.count_owned("bianca", "bianca_holy_touch")
	var discovery := _find("Discovery_0") as CardView
	discovery.pressed.emit(discovery)
	await _wait(0.2)
	await _press_node("KeepButton")
	check(GameState.expedition.discoveries_claimed and GameState.campaign.count_owned("bianca", "bianca_holy_touch") == touches + 1, "the discovery is kept (%d -> %d)" % [touches, GameState.campaign.count_owned("bianca", "bianca_holy_touch")])
	await _press_node("ReturnHomeButton")
	check(not (_find("Service_blacksmith") as Button).disabled, "the Upgrade Workshop opened after the first completion")
	# --- Upgrade Workshop ------------------------------------------------------------------------
	GameState.campaign.vault.gold = 500
	await _press_node("Service_blacksmith")
	var grid := _find("UpgradeGrid")
	var card := grid.get_child(0).get_child(0) as CardView
	card.pressed.emit(card)
	await _wait(0.3)
	check(_screen().find_child("UpgradePreview", true, false) != null and _screen().find_child("After", true, false) != null, "the upgrade preview shows the card before and after")
	await _shot("cf_12_upgrade_preview")
	(_screen().find_child("ConfirmUpgrade", true, false) as Button).pressed.emit()
	await _wait(0.4)
	check(GameState.campaign.collection("chiara").any(func(o: OwnedCard) -> bool: return o.upgrade_level == 1) and GameState.campaign.vault.gold < 500, "a card is upgraded for good")
	await _press_node("Tab_equipment")
	check(_find("ItemList") != null, "the equipment refinement tab opens")
	await _press_node("BackButton")
	# --- Training Hall and Enchanter --------------------------------------------------------------
	GameState.campaign.services.append("training_hall")
	SceneRouter.open_service("training_hall")
	await _wait(0.5)
	check(_find("Training_chiara") != null and _find("Spec_arcana") != null, "the Training Hall lists each sister's specializations")
	await _shot("cf_13_training")
	Bond.add_xp(GameState.campaign, 5)
	GameState.campaign.essence = 2
	for pair in [["chiara", "chiara_fire_ember"], ["bianca", "bianca_holy_strike"]]:
		for o in GameState.campaign.collection(pair[0]):
			if o.card_id == pair[1] and o.upgrade_level == 0:
				o.upgrade_level = 1
				break
	SceneRouter.open_service("enchanter")
	await _wait(0.5)
	var fuse := _find("Recipe_purifying_flame").find_child("Fuse", true, false) as Button
	check(fuse != null and not fuse.disabled, "Purifying Flame can be fused")
	await _shot("cf_14_enchanter")
	fuse.pressed.emit()
	await _wait(0.3)
	await _confirm()
	check(GameState.campaign.count_owned("chiara", "chiara_fusion_purifying_flame") == 1 and GameState.campaign.fusions_done.has("purifying_flame"), "the fusion card joins the collection")
	# --- A generated mission map ------------------------------------------------------------------
	GameState.campaign.mark_mission_completed("castle_awakening")
	for m in GameState.campaign.roster.members:
		GameState.campaign.levels[m.id] = maxi(Levels.xp_of(GameState.campaign, m.id), Levels.threshold(3))
	GameState.campaign.refresh_roster()
	SceneRouter.go(SceneRouter.Screen.CASTLE_HUB)
	await _wait(0.4)
	check(ExpeditionService.start("forest_rescue", {}, 77) == "", "the rescue mission starts")
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.8)
	check(_find("ObjectiveTracker") != null and (_find("ObjectiveTracker") as Label).text.contains("0 / 2"), "the tracker shows the rescue objective")
	await _shot("cf_15_generated_map")
	# Continue from the main menu resumes the expedition.
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.5)
	GameState.campaign = null
	GameState.expedition = null
	await _press("Continue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.expedition != null and GameState.expedition.mission_id == "forest_rescue", "Continue resumes the expedition")
	ExpeditionService.return_to_castle()
	await _levels_and_contracts()
	# --- Phone size --------------------------------------------------------------------------------
	get_window().size = Vector2i(844, 390)
	await _wait(0.4)
	for entry in [[SceneRouter.Screen.CASTLE_HUB, "castle hub", "cf_20_phone_hub"], [SceneRouter.Screen.WORLD_MAP, "world map", "cf_21_phone_world"]]:
		SceneRouter.go(entry[0])
		await _wait(0.6)
		_fits(str(entry[1]))
		await _shot(str(entry[2]))
	SceneRouter.open_service("library")
	await _wait(0.6)
	_fits("deck workshop")
	await _shot("cf_22_phone_workshop")
	SceneRouter.open_preparation("castle_awakening")
	await _wait(0.6)
	_fits("preparation")
	await _shot("cf_23_phone_prep")
	get_window().size = Vector2i(1280, 720)
	await _wait(0.3)
	# Quick Play never touches the campaign save.
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.5)
	await _press("Quick Play")
	await _press("Classic Run")
	check(GameState.active_slot() == GameState.SLOT_QUICKPLAY and GameState.new_game_mode == "classic", "Classic Run uses the Quick Play slot")
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.save_game()
	check(GameState.slot_has_save(GameState.SLOT_CAMPAIGN) and GameState.slot_has_save(GameState.SLOT_QUICKPLAY), "the campaign and the Quick Play run are saved apart")
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.5)
	await _press("Quick Play")
	check(_button("Resume Quick Play") != null, "the menu offers to resume the Quick Play run")
	await _press("Back")
	await _press("Continue")
	check(GameState.in_castle(), "Continue opens the campaign first")
