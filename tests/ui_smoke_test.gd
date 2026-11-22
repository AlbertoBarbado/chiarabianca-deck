extends Node
## End-to-end UI walkthrough: menu -> selection -> party -> map -> rooms -> combat -> exit.
## Run (windowed so screenshots work; add --headless to skip screenshots):
##   godot --path . res://tests/ui_smoke_test.tscn -- <screenshot_dir>
## Exit code 1 on failure.

var _failures := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_ui_save.json"  # Never touch the player's real save.
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.4)
	await _run()
	print("UI smoke test: %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _wait(1.1)  # Menu screens fade in and their art slides in; capture the settled state.
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _screen() -> Node:
	return SceneRouter.current_screen


func _find_button(text_part: String) -> Button:
	var stack: Array[Node] = [_screen()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var label_text := (n as ChoiceCard).get_title() if n is ChoiceCard else ((n as Button).text if n is Button else "")
		if n is Button and label_text.contains(text_part) and (n as Button).is_visible_in_tree():
			return n
		stack.append_array(n.get_children())
	return null


func _press(text_part: String) -> bool:
	var b := _find_button(text_part)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	await _wait(0.35)
	return true


func _press_exact(text: String) -> bool:
	var stack: Array[Node] = [_screen()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			(n as Button).pressed.emit()
			await _wait(0.35)
			return true
		stack.append_array(n.get_children())
	return false


func _card_views() -> Array[CardView]:
	var views: Array[CardView] = []
	var stack: Array[Node] = [_screen()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CardView:
			views.push_front(n)
		stack.append_array(n.get_children())
	return views


func _find_map_view(node: Node) -> MapView:
	if node is MapView:
		return node
	for child in node.get_children():
		var found := _find_map_view(child)
		if found != null:
			return found
	return null


func _enter(node_id: String) -> void:
	var button := _find_map_view(_screen()).get_button(node_id)
	button.pressed.emit()
	await _wait(0.4)


func _play_card_once() -> void:
	var combat: CombatManager = _screen().combat
	for card in combat.deck.hand:
		if combat.can_play(card) == "" and not combat.needs_target_choice(card):
			_screen()._on_card_pressed(card)
			await _wait(0.2)
			return


## Plays real cards (via the UI handlers) until combat ends; enemies are weakened for speed.
func _win_combat() -> void:
	var screen := _screen()
	var combat: CombatManager = screen.combat
	for enemy in combat.enemies:
		enemy.hp = mini(enemy.hp, 4)
	var guard := 0
	while combat.state == CombatManager.State.PLAYER_TURN and guard < 40:
		guard += 1
		var played := false
		for card in combat.deck.hand:
			if card.definition.card_type in ["attack", "spell"] and combat.can_play(card) == "":
				screen._on_card_pressed(card)
				if screen._selected_card != null and not combat.get_living_enemies().is_empty():
					screen._on_enemy_pressed(combat.get_living_enemies()[0].id)
				played = true
				break
		if not played:
			screen._on_end_turn()
		await _wait(0.02)
	await _wait(0.4)
	check(combat.state == CombatManager.State.VICTORY, "combat won through the UI")


func _run() -> void:
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAIN_MENU, "boots into main menu")
	check(_find_button("Continue").disabled, "Continue disabled without save")
	for label in ["New Game", "Settings", "Exit"]:
		check(_find_button(label) != null, "menu has %s" % label)
	await _shot("01_main_menu")
	await _press("Settings")
	await _shot("02_settings")
	await _press("Back")
	await _press("New Game")
	await _shot("03_character_selection")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.CHARACTER_SELECTION, "character selection opened")
	await _press("Choose Specializations")
	check(_find_button("Confirm Party").disabled, "confirm disabled before choosing")
	await _press("Earth")
	await _press("Commander")
	check(_find_button("Confirm Party").disabled, "non-playable specializations cannot be confirmed")
	await _shot("04_spec_unplayable")
	await _press("Arcana")
	await _press("Tanking")
	check(not _find_button("Confirm Party").disabled, "confirm enabled with Arcana + Tanking")
	await _shot("05_spec_selected")
	await _press("Confirm Party")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.PARTY_OVERVIEW, "party overview opened")
	check(GameState.party.get_member("chiara").deck.size() == 10, "party decks created")
	await _shot("06_party_overview")
	await _press("Enter the Royal Castle")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "map opened")
	await _shot("07_map")
	var map_view := _find_map_view(_screen())
	map_view.get_button("throne_approach").pressed.emit()
	await _wait(0.2)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.map_progress.current_node_id == "royal_chambers", "invalid node rejected")
	await _enter("training_yard")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT, "combat opened")
	await _wait(0.2)
	await _shot("08_combat")
	await _play_card_once()
	await _shot("09_combat_after_card")
	await _win_combat()
	await _shot("10_combat_victory")
	await _press("Continue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REWARD, "reward screen after victory")
	check(_card_views().size() == 3, "three card options shown")
	await _shot("10b_card_reward")
	check(not _find_button("Take Card").disabled == false, "Take Card disabled until a card is selected")
	var reward_views := _card_views()
	var chosen_owner := reward_views[0].owner_id
	var chosen_card_id := reward_views[0].definition.id
	reward_views[0].pressed.emit(reward_views[0])
	await _wait(0.1)
	await _shot("10c_card_reward_selected")
	await _press("Take Card")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "back on map after victory")
	var rewarded := GameState.party.get_member(chosen_owner)
	check(GameState.party.get_total_deck_size() == 21 and rewarded.deck.any(func(o: OwnedCard) -> bool: return o.card_id == chosen_card_id), "chosen card added to its owner's deck")
	var gold_after_combat := GameState.inventory.gold
	check(gold_after_combat == GameConfig.STARTING_GOLD + 15, "gold reward granted")
	await _shot("11_map_progress")
	await _enter("east_armory")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MERCHANT, "merchant opened")
	await _shot("12_merchant")
	await _press("15g")
	check(GameState.inventory.count_of("minor_health_potion") == 1 and GameState.inventory.gold == gold_after_combat - 15, "potion purchased")
	await _press("Return to Map")
	await _enter("throne_approach")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT, "final combat opened")
	await _shot("13_final_combat")
	await _win_combat()
	var party_cards_before_deck := PartyDeck.new()
	party_cards_before_deck.build_from_party(GameState.party)
	check(party_cards_before_deck.draw_pile.size() == 21, "final combat deck included the rewarded card")
	await _press("Continue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REWARD, "reward after final combat")
	await _press("Skip Reward")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.party.get_total_deck_size() == 21, "skipping leaves decks unchanged")
	# Save / Continue round trip from the main menu.
	check(GameState.has_save(), "autosave exists on the map")
	var saved_node := GameState.map_progress.current_node_id
	var saved_gold := GameState.inventory.gold
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.4)
	check(not _find_button("Continue").disabled, "Continue enabled with a save")
	await _shot("14a_menu_continue")
	GameState.party = null
	await _press("Continue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.map_progress.current_node_id == saved_node, "Continue restores the map position")
	check(GameState.party.get_total_deck_size() == 21 and GameState.inventory.gold == saved_gold, "Continue restores decks and gold")
	await _enter("castle_exit")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.ACT_TRANSITION, "the castle exit shows the transition to the Enchanted Forest (Milestone 8)")
	await _shot("14_complete")
	# Rest and event rooms in a second run.
	GameState.reset_selection()
	GameState.select_specialization("chiara", "arcana")
	GameState.select_specialization("bianca", "tanking")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.party.get_member("chiara").current_hp = 20
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.3)
	await _enter("west_gallery")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REST, "rest room opened")
	await _press("Rest (")
	check(GameState.party.get_member("chiara").current_hp == 38, "rest healed 30% of 60 HP")
	await _shot("15_rest")
	await _press_exact("Upgrade a Card")
	await _shot("15a_upgrade_picker")
	var picker_views := _card_views()
	var picked := picker_views[0]
	var picked_owner := picked.owner_id
	var picked_card_id := picked.definition.id
	picked.pressed.emit(picked)
	await _wait(0.3)
	await _shot("15b_upgrade_preview")
	check(_card_views().size() == 2, "upgrade preview shows original and upgraded cards")
	await _press_exact("Upgrade")
	var upgraded_count := 0
	for owned in GameState.party.get_member(picked_owner).deck:
		if owned.card_id == picked_card_id and owned.upgrade_level == 1:
			upgraded_count += 1
	check(upgraded_count == 1, "exactly one copy upgraded on the owner's deck")
	check(_find_button("Upgrade a Card").disabled, "only one upgrade per rest")
	await _press("Return to Map")
	await _enter("central_courtyard")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EVENT, "event opened")
	await _shot("16_event")
	await _press("Collect the coins")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EVENT and GameState.inventory.gold == GameConfig.STARTING_GOLD + 25, "event applied once and its outcome is shown")
	await _press("Continue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.inventory.gold == GameConfig.STARTING_GOLD + 25, "Continue returns to the map")
	await _run_fire_holy()
	GameState.delete_save()


## Fire + Holy: selection screen details, a real combat showing Burn and both passives.
func _run_fire_holy() -> void:
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.4)
	await _press("New Game")
	await _press("Choose Specializations")
	await _press_exact("Fire")
	await _press_exact("Holy")
	check(not _find_button("Confirm Party").disabled, "confirm enabled with Fire + Holy")
	var texts := _label_texts(_screen())
	check(texts.any(func(t: String) -> bool: return t.contains("Kindled Spark")), "Fire passive shown on selection screen")
	check(texts.any(func(t: String) -> bool: return t.contains("Blessed Aegis")), "Holy passive shown on selection screen")
	check(texts.any(func(t: String) -> bool: return t.contains("4× Ember Bolt")) and texts.any(func(t: String) -> bool: return t.contains("3× Kindle")), "Fire starting deck listed with descriptions")
	check(texts.any(func(t: String) -> bool: return t.begins_with("Burn:")), "Burn keyword explained")
	await _shot("20_fire_holy_selection")
	await _press("Confirm Party")
	check(GameState.party.get_member("chiara").specialization.id == "fire" and GameState.party.get_member("bianca").specialization.id == "holy", "Fire/Holy party created")
	await _press("Enter the Royal Castle")
	await _enter("training_yard")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT, "Fire/Holy combat opened")
	var screen := _screen()
	var combat: CombatManager = screen.combat
	combat.energy = 9
	var kindle: CardInstance = null
	var shield: CardInstance = null
	for pile: Array[CardInstance] in [combat.deck.hand, combat.deck.draw_pile]:
		for card in pile:
			if kindle == null and card.definition.id == "chiara_fire_kindle":
				kindle = card
			if shield == null and card.definition.id == "bianca_holy_shield":
				shield = card
	for card in [kindle, shield]:
		if not combat.deck.hand.has(card):
			combat.deck.draw_pile.erase(card)
			combat.deck.hand.append(card)
	screen._refresh()
	screen._on_card_pressed(kindle)
	await _wait(0.2)
	screen._on_card_pressed(shield)
	await _wait(0.2)
	check(combat.enemies[0].has_status("burn") and combat.enemies[0].hp == 24, "Burn and Kindled Spark resolved through the UI")
	check(combat.get_combatant("bianca").block == int(DataRegistry.get_card("bianca_holy_shield").effects[0]["value"]) + int(DataRegistry.get_specialization("holy").passive["effect"]["value"]), "Blessed Aegis resolved through the UI")
	screen._battlefield.enemy_views.values()[0]._set_hover(true)  # enemy details appear on hover
	var all_text := _label_texts(screen)
	check(all_text.any(func(t: String) -> bool: return t.begins_with("Burn 2 (3 dmg")), "enemy details (on hover) show Burn with duration and damage")
	screen._battlefield.enemy_views.values()[0]._set_hover(false)
	var chip_tips := _chip_tooltips(screen)
	check(chip_tips.contains("Kindled Spark: used this turn") and chip_tips.contains("Blessed Aegis: used this turn"), "party chips (tooltip) show spent passives")
	check(all_text.any(func(t: String) -> bool: return t.contains("✦ Blessed Aegis")), "passive trigger announced in the combat log")
	await _shot("21_fire_holy_combat")
	screen._on_end_turn()
	await _wait(0.3)
	check(combat.enemies[0].hp <= 22 and combat.turn == 2, "Burn ticked on the enemy phase and a new turn began")
	check(_chip_tooltips(screen).contains("Kindled Spark: ready"), "passives show as ready again")
	await _shot("22_fire_holy_turn2")
	await _win_combat()
	await _press("Continue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REWARD, "Fire/Holy reward screen")
	var views := _card_views()
	var pool_ok := views.size() == 3
	for view in views:
		var allowed := (DataRegistry.get_specialization("fire") if view.owner_id == "chiara" else DataRegistry.get_specialization("holy")).card_pool
		pool_ok = pool_ok and allowed.has(view.definition.id)
	check(pool_ok, "rewards come from the Fire/Holy pools")
	await _shot("23_fire_holy_reward")
	views[0].pressed.emit(views[0])
	await _press("Take Card")
	check(GameState.party.get_total_deck_size() == 21, "Fire/Holy reward added")


func _label_texts(root_node: Node) -> Array[String]:
	var result: Array[String] = []
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).is_visible_in_tree():
			result.append((n as Label).text)
		stack.append_array(n.get_children())
	return result


func _chip_tooltips(screen: Node) -> String:
	var tips: Array[String] = []
	for chip in screen.find_children("Chip_*", "PanelContainer", true, false):
		tips.append((chip as Control).tooltip_text)
	return " | ".join(tips)
