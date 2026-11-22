extends Node
## Milestone 8 flow test through the real screens: Castle exit -> act transition -> Enchanted Forest
## map, forest combat, towns (rest / merchant), events (outcome saved once, ambush fight), elite,
## the Forest Serpent boss, its reward and the Forest Act completion. Uses a temporary save file.
##   godot --path . res://tests/progression/forest_flow_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_forest_flow.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.4)
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


func _press(node_name: String) -> void:
	var button := _find(node_name) as BaseButton
	if button != null and not button.disabled:
		button.pressed.emit()
	await _wait(0.35)


func _press_text(prefix: String) -> void:
	for button in SceneRouter.current_screen.find_children("*", "Button", true, false):
		var label_text := (button as ChoiceCard).get_title() if button is ChoiceCard else (button as Button).text
		if label_text.begins_with(prefix) and not (button as Button).disabled:
			(button as Button).pressed.emit()
			break
	await _wait(0.35)


func _new_run(map_id: String) -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.next_map_id = map_id
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID


## Travels to the last node of `path` along any valid route from the current position (rooms on the
## way are not opened), then enters it through the router.
func _go(path: Array) -> void:
	var target := str(path[-1])
	var progress := GameState.map_progress
	var route := _route(progress.graph, progress.current_node_id, target)
	for i in route.size() - 1:
		progress.travel_to(route[i])
	GameState.room_state = {}
	progress.travel_to(target)
	SceneRouter.go_to_room(GameState.get_current_node())
	await _wait(0.45)


## Node ids after `from_id` up to and including `to_id` (breadth-first, shortest route).
func _route(graph: MapGraph, from_id: String, to_id: String) -> Array[String]:
	var previous: Dictionary = {from_id: ""}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to_id:
			break
		for next_id in graph.get_next_ids(current):
			if not previous.has(next_id):
				previous[next_id] = current
				queue.append(next_id)
	var route: Array[String] = []
	var step := to_id
	while step != from_id and previous.has(step):
		route.push_front(step)
		step = str(previous[step])
	return route


func _win_current_fight() -> void:
	var screen := SceneRouter.current_screen
	GameState.record_combat_victory(screen.combat.gold_reward, screen._encounter)


func _reload() -> void:
	var error := GameState.load_game()
	check(error == "", "the saved run loads (%s)" % error)
	SceneRouter.resume_run()
	await _wait(0.45)


func _run() -> void:
	# --- Castle -> Forest ------------------------------------------------------------------------
	_new_run(GameConfig.DEFAULT_MAP_ID)
	var chiara := GameState.party.get_member("chiara")
	chiara.current_hp = 41
	chiara.deck[0].upgrade_level = 1
	var extra_card := chiara.add_card("chiara_fire_fireball")
	GameState.inventory.gold = 87
	GameState.inventory.add_item("health_potion", 2)
	GameState.inventory.add_relic("scholars_satchel")
	var deck_size := GameState.party.get_total_deck_size()
	await _go(["training_yard", "central_courtyard", "royal_library", "throne_approach", "castle_exit"])
	check(SceneRouter.current_screen_id == SceneRouter.Screen.ACT_TRANSITION, "the castle exit leads to the act transition, not to the end of the run")
	check(GameState.run_result == "" and GameState.has_save(), "the run continues and is saved")
	await _shot("m8_01_act_transition")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.ACT_TRANSITION, "continuing a save made between the acts returns to the transition")
	await _press("EnterNextAct")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.map_progress.graph.id == "enchanted_forest", "the party enters the Enchanted Forest map")
	check(GameState.map_progress.current_node_id == "forest_entrance" and GameState.map_progress.visited_ids == ["forest_entrance"], "at the forest entrance, with a fresh map")
	chiara = GameState.party.get_member("chiara")
	var act_heal := float(RunRules.get_block("acts").get("heal_between_acts", 0.0))
	check(chiara.current_hp == mini(chiara.max_hp, 41 + roundi(chiara.max_hp * act_heal)) and GameState.party.get_member("bianca").current_hp == 80, "HP carries over, plus the between-act heal (%d%%)" % roundi(act_heal * 100.0))
	check(GameState.party.get_total_deck_size() == deck_size and chiara.find_card(extra_card.uid) != null and chiara.deck[0].upgrade_level == 1, "decks, card ownership and upgrades are preserved")
	check(GameState.inventory.gold == 87 and GameState.inventory.count_of("health_potion") == 2 and GameState.inventory.has_relic("scholars_satchel"), "gold, items and relics are preserved")
	check(chiara.specialization.id == "fire" and GameState.party.get_member("bianca").specialization.id == "holy", "specializations are preserved")
	check((GameState.run_flags.get("completed_maps", []) as Array).has("royal_castle_tutorial"), "the castle is recorded as completed")
	var map_view: MapView = SceneRouter.current_screen._map_view
	check(map_view.has_background() and map_view.uses_layout(), "the forest map uses its background picture and layout")
	var boss_button := map_view.get_button("serpents_domain")
	var normal_button := map_view.get_button("wolf_trail")
	check(boss_button.size.x > normal_button.size.x * 1.3, "the boss node is visually prominent")
	var touch_ok := true
	for node_id: String in GameState.map_progress.graph.nodes:
		touch_ok = touch_ok and map_view.get_button(node_id).size.x >= 64.0
	check(touch_ok, "every node is at least 64 px wide for touch")
	check(map_view.is_scrollable() and map_view.max_scroll() > 600.0, "the route chart is taller than the screen and scrolls (%d px)" % int(map_view.max_scroll()))
	check(map_view.is_node_visible("forest_entrance") and map_view.is_node_visible("boar_thicket") and not map_view.is_node_visible("serpents_domain"), "the map opens on the party: the entrance and the first choices are visible, the boss is not yet")
	var art := map_view.get_art_rect()
	check(art.size.x > 0.0 and absf(art.size.x / art.size.y - 1360.0 / 768.0) < 0.01, "the forest picture keeps its aspect ratio and is shown whole")
	await _shot("m8_02_forest_map")
	map_view.scroll_to(0.0)
	await _wait(0.2)
	check(map_view.is_node_visible("serpents_domain") and not map_view.is_node_visible("forest_entrance"), "scrolling to the top shows the Serpent's Domain")
	await _shot("m8_02b_forest_map_top")
	map_view.scroll_to(map_view.max_scroll() * 0.5)
	await _wait(0.2)
	await _shot("m8_02c_forest_map_middle")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	var before_scroll := map_view.get_scroll()
	map_view._on_chart_input(wheel)
	check(map_view.get_scroll() > before_scroll, "the mouse wheel scrolls the chart")
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(0, 120)
	map_view._on_chart_input(drag)
	check(map_view.get_scroll() < before_scroll + 90.0, "a touch drag scrolls it back")
	map_view.scroll_to(99999.0)
	check(map_view.get_scroll() == map_view.max_scroll(), "scrolling stops at the ends")
	map_view.center_on("forest_entrance")
	check(map_view.get_button("wolf_trail").state == MapProgress.NodeState.AVAILABLE and map_view.get_button("serpents_domain").state == MapProgress.NodeState.UNAVAILABLE, "available and locked states are shown")
	await _reload()
	check(GameState.map_progress.graph.id == "enchanted_forest" and SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "a forest save loads back into the forest")

	# --- Forest combat ------------------------------------------------------------------------------
	map_view = SceneRouter.current_screen._map_view
	map_view.get_button("boar_thicket").pressed.emit()
	await _wait(0.5)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT and GameState.map_progress.current_node_id == "boar_thicket", "tapping an available node enters its room")
	var screen := SceneRouter.current_screen
	check(screen.combat.enemies.size() == 1 and screen.combat.enemies[0].enemy_def.id == "forest_boar", "the Boar Thicket fight has the wild boar")
	check(str(screen._backdrop().get("asset_id", "")) == "battle_forest", "forest fights use the forest backdrop")
	await _shot("m8_03_forest_combat")
	var gold := GameState.inventory.gold
	_win_current_fight()
	_win_current_fight()
	check(GameState.inventory.gold == gold + 16, "the combat reward is granted once")
	GameState.end_room()

	# --- Town: rest only ------------------------------------------------------------------------------
	GameState.party.get_member("bianca").current_hp = 40
	await _go(["brookside_camp"])
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TOWN, "the camp opens the town screen")
	check(_find("TownRest") != null and _find("TownMerchant") == null, "a rest-only camp offers no merchant")
	await _shot("m8_04_town_camp")
	await _press("TownRest")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REST, "resting opens the existing rest room")
	await _press_text("Rest (")
	check(GameState.party.get_member("bianca").current_hp == 40 + ceili(80 * 0.25), "the camp heals its own percentage (25%)")
	await _press_text("Back to Town")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TOWN, "leaving the rest room returns to the town")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TOWN and bool(GameState.room_state.get("rested", false)), "reloading returns to the town with the rest already used")
	await _press("TownRest")
	var hp := GameState.party.get_member("bianca").current_hp
	await _press_text("Rest (")
	check(GameState.party.get_member("bianca").current_hp == hp, "the rest cannot be used twice")
	await _press_text("Back to Town")
	await _press("TownLeave")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "leaving the town returns to the map")
	check(GameState.map_progress.can_travel_to("brookside_camp") != "", "a town cannot be entered again")

	# --- Town: merchant and rest -------------------------------------------------------------------------
	GameState.inventory.gold = 100
	await _go(["wayfarers_rest", "elderwood_village"])
	check(_find("TownRest") != null and _find("TownMerchant") != null, "the village offers merchant and rest")
	await _shot("m8_05_town_village")
	await _press("TownMerchant")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MERCHANT, "the merchant is the existing shop screen")
	var potions := GameState.inventory.count_of("health_potion")
	await _press_text("Buy · 34g")
	check(GameState.inventory.count_of("health_potion") == potions + 1 and GameState.inventory.gold == 66, "buying works and costs gold")
	await _press_text("Back to Town")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TOWN and GameState.inventory.gold == 66 and int((GameState.room_state.get("bought", {}) as Dictionary).get("health_potion", 0)) == 1, "purchases survive a reload (no refund, no restock)")
	await _press("TownLeave")

	# --- Event: outcome applied and saved once ------------------------------------------------------------
	await _go(["cursed_hollow"])
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EVENT, "the Cursed Hollow opens an event")
	var event_id := str(GameState.room_state.get("event_id", ""))
	check(EventResolver.pool_event_ids("forest_danger").has(event_id), "the event is rolled from the dangerous pool (%s)" % event_id)
	await _shot("m8_06_event")
	await _reload()
	check(str(GameState.room_state.get("event_id", "")) == event_id, "reloading shows the same event (no reroll)")
	GameState.room_state["event_id"] = "forest_concealed_trap"  # a fixed event for exact numbers
	SceneRouter.open_room_screen(GameState.get_current_node())
	await _wait(0.4)
	for member in GameState.party.members:
		member.current_hp = member.max_hp
	var gold_before := GameState.inventory.gold
	await _press("EventChoice0")
	check(GameState.inventory.gold == gold_before + 70 and GameState.party.get_member("chiara").current_hp == 52, "the choice applies its stated outcome (+70 gold, 8 damage each)")
	check(_find("EventOutcome") != null and _find("EventChoice1") == null or (_find("EventChoice1") as Node).is_queued_for_deletion(), "the outcome is shown and the choices are gone")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EVENT and bool(GameState.room_state.get("resolved", false)) and _find("EventChoice0") == null, "after a reload the event is still resolved")
	check(GameState.inventory.gold == gold_before + 70 and GameState.party.get_member("chiara").current_hp == 52, "nothing is applied twice")
	check((GameState.run_flags.get("seen_events", []) as Array).has("forest_concealed_trap"), "the event is remembered as seen")
	await _press("EventContinue")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "Continue returns to the map")

	# --- Boss ------------------------------------------------------------------------------------------------
	await _go(["serpents_domain"])
	screen = SceneRouter.current_screen
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT and screen.combat.is_boss, "the Serpent's Domain starts the boss fight")
	check(_find("EliteBanner") != null and _find("FoePortrait") != null and (_find("EliteTag") as Label).text == "BOSS", "the boss has its own full-screen introduction with its portrait")
	var boss_view: CombatUnitView = screen._battlefield.enemy_views.values()[0]
	check(boss_view.size_scale > 1.4 and boss_view.get_art_rect().size.y > screen._battlefield.party_views["chiara"].get_art_rect().size.y, "the Serpent is drawn larger than the party")
	await _wait(0.5)
	await _wait(1.2)
	await _shot("m8_07_boss_intro")
	await _wait(3.0)
	screen.combat.end_player_turn()
	await _wait(0.9)
	await _shot("m8_08_boss_poison")
	check(screen.combat.party_combatants.any(func(c: Combatant) -> bool: return c.has_status("poison")), "the Serpent's first attack poisons a character")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT and SceneRouter.current_screen.combat.is_boss, "a save inside the boss fight resumes the boss fight (checkpoint)")
	gold = GameState.inventory.gold
	_win_current_fight()
	_win_current_fight()
	check(GameState.inventory.gold == gold + 120 and GameState.pending_reward.options.size() == 3 and DataRegistry.get_card(GameState.pending_reward.options[0]["card_id"]).rarity == "epic" and bool(GameState.room_state.get("boss", false)), "the boss reward is granted once: 120 gold and a choice of 3 epic cards")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REWARD and GameState.inventory.gold == gold + 120, "reloading after the kill returns to the reward without paying again")
	await _shot("m8_09_boss_reward")
	GameState.pending_reward.choose(0, GameState.party)
	SceneRouter.current_screen.call("_finish")
	await _wait(0.4)
	check(GameState.map_progress.get_available_ids() == ["forest_exit"], "after the boss only the exit remains")
	await _go(["forest_exit"])
	check(SceneRouter.current_screen_id == SceneRouter.Screen.ACT_TRANSITION and GameState.run_result == "", "leaving the forest leads on to Act III (the run continues)")
	var texts: Array[String] = []
	for label in SceneRouter.current_screen.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	check(texts.any(func(t: String) -> bool: return t.contains("Forest Act Complete")), "the act screen says the Forest Act is complete")
	check(GameState.has_save(), "the run is saved between the acts")
	await _shot("m8_10_forest_victory")
	await _press("EnterNextAct")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP and GameState.map_progress.graph.id == "sunlit_coast", "Enter leads onto the Sunlit Coast")

	# --- Elite, ambush event and boss defeat in a second run --------------------------------------------------
	_new_run("enchanted_forest")
	check(GameState.map_progress.graph.id == "enchanted_forest" and GameState.next_map_after_current() == "sunlit_coast", "the forest can also be started on its own (the Sunlit Coast follows it)")
	await _go(["wolf_trail", "webbed_hollow", "bears_den", "alphas_ground"])
	screen = SceneRouter.current_screen
	check(screen.combat.is_elite and screen.combat.enemies.size() == 3 and (_find("EliteTag") as Label).text == "ELITE ENCOUNTER", "the Alpha's Hunting Ground is an elite fight")
	await _wait(3.2)
	await _shot("m8_11_elite")
	_win_current_fight()
	check(GameState.pending_reward.options.size() == 4, "elite victory gives the larger reward")
	GameState.end_room()
	_new_run("enchanted_forest")
	await _go(["mossy_crossing"])
	GameState.room_state["event_id"] = "forest_ambush"
	SceneRouter.open_room_screen(GameState.get_current_node())
	await _wait(0.4)
	await _press("EventChoice0")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT and SceneRouter.current_screen.combat.enemies.size() == 3, "choosing to fight turns the event into the Spider Ambush")
	await _reload()
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT and SceneRouter.current_screen.combat.encounter_name == "Spider Ambush", "a reload resumes the ambush fight, not the event choice")
	gold = GameState.inventory.gold
	_win_current_fight()
	var ambush_gold := int(DataRegistry.get_encounter("forest_spider_ambush").get("gold_reward", 0))
	check(ambush_gold > 0 and GameState.inventory.gold == gold + ambush_gold and GameState.pending_reward != null, "winning the ambush pays its normal reward (%d gold)" % ambush_gold)
	GameState.end_room()
	await _go(["hidden_cache"])
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TREASURE and (GameState.room_state["choices"] as Array).size() == 5, "the Hidden Cache is a treasure room with five choices")
	await _press("TreasureChoice0")
	await _press("TreasureChoice1")
	check(int(GameState.room_state.get("taken", -1)) == 0, "one treasure only")
	var leave := _find("TreasureLeave") as Button
	await _wait(0.4)
	check(leave != null and leave.text == "Continue" and not leave.disabled and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(leave.get_global_rect()), "after taking a treasure, Continue is fully on screen and enabled")
	await _shot("m8_12_treasure_taken")
	await _press("TreasureLeave")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "Continue returns to the map")
	_new_run("enchanted_forest")
	GameState.save_game()
	await _go(["wolf_trail", "webbed_hollow", "bears_den", "alphas_ground", "serpents_threshold", "serpents_domain"])
	screen = SceneRouter.current_screen
	for c: Combatant in screen.combat.party_combatants:
		c.hp = 1
		c.block = 0
	for i in 4:
		if screen.combat.state == CombatManager.State.PLAYER_TURN:
			screen.combat.end_player_turn()
	await _wait(0.6)
	check(screen.combat.state == CombatManager.State.DEFEAT, "the Serpent can defeat the party")
	screen._on_continue(false)
	await _wait(0.4)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.RUN_END and GameState.run_result == GameState.RESULT_DEFEATED and not GameState.has_save(), "defeat ends the run and removes the save")
