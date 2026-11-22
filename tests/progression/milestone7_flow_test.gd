extends Node
## Milestone 7 flow tests through the real autoloads and screens: room saves and resume, combat
## checkpoint and single reward, elite introduction, treasure claim, card removal at a rest site,
## save deletion. Uses a temporary save file. Run (windowed or headless):
##   godot --path . res://tests/progression/milestone7_flow_test.tscn

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_m7_flow.json"
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


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _new_run() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.next_map_id = "castle_elite_demo"
	GameState.begin_adventure()
	GameState.delete_save()


func _enter(node_id: String) -> void:
	GameState.map_progress.travel_to(node_id)
	SceneRouter.go_to_room(GameState.get_current_node())
	await _wait(0.4)


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _press(node_name: String) -> void:
	var button := _find(SceneRouter.current_screen, node_name) as BaseButton
	if button != null and not button.disabled:
		button.pressed.emit()
	await _wait(0.3)


func _reload() -> void:
	var error := GameState.load_game()
	check(error == "", "the saved run loads (%s)" % error)


func _run() -> void:
	_new_run()
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.3)
	check(GameState.has_save(), "arriving on the map saves the run")
	await _shot("m7_1_demo_map")

	# --- Combat room: checkpoint, victory recorded once, reward persisted -------------------
	await _enter("demo_fight")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT, "combat room opens")
	check(GameState.room_matches("demo_fight", "combat"), "entering the room records it in the room state")
	var gold_before := GameState.inventory.gold
	_reload()
	check(GameState.room_matches("demo_fight", "combat") and GameState.inventory.gold == gold_before, "a save made inside the fight restores the room at its entry checkpoint")
	SceneRouter.resume_run()
	await _wait(0.4)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT, "Continue resumes the fight room (the fight restarts from its checkpoint)")
	var encounter := DataRegistry.get_encounter("castle_training_02")
	GameState.record_combat_victory(20, encounter)
	GameState.record_combat_victory(20, encounter)
	check(GameState.inventory.gold == gold_before + 20, "victory gold is granted once even if recorded twice")
	check(GameState.pending_reward != null and str(GameState.room_state.get("phase", "")) == "reward", "the reward phase is recorded")
	var offered: Array = GameState.pending_reward.options.duplicate(true)
	_reload()
	check(GameState.inventory.gold == gold_before + 20 and GameState.pending_reward != null, "after loading, gold is not granted again and the reward is still pending")
	check(GameState.pending_reward.options == offered or GameState.pending_reward.options.size() == offered.size(), "the reloaded reward offers the same cards (no reroll)")
	SceneRouter.resume_run()
	await _wait(0.4)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REWARD, "Continue resumes on the reward screen")
	var deck_before := GameState.party.get_total_deck_size()
	var reward_screen := SceneRouter.current_screen
	GameState.pending_reward.choose(0, GameState.party)
	reward_screen.call("_finish")
	await _wait(0.4)
	check(GameState.party.get_total_deck_size() == deck_before + 1 and GameState.room_state.is_empty(), "taking the reward adds one card and leaves the room")
	_reload()
	check(GameState.party.get_total_deck_size() == deck_before + 1 and GameState.pending_reward == null and GameState.room_state.is_empty(), "after loading the card is still there exactly once and no reward is pending")

	# --- Elite room: introduction and flagged enemies --------------------------------------
	await _enter("demo_elite")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.COMBAT and GameState.room_matches("demo_elite", "elite"), "the elite room opens the combat screen and is recorded as elite")
	var screen := SceneRouter.current_screen
	check(screen.combat.is_elite and _find(screen, "EliteBanner") != null and _find(screen, "EliteTag") != null, "the elite introduction banner and tag are shown")
	await _wait(0.5)
	await _shot("m7_2_elite_intro")
	await _wait(3.2)
	await _shot("m7_3_elite_battlefield")
	var elite_views := 0
	for view: CombatUnitView in screen._battlefield.all_views():
		if view is CombatEnemyView and view.get_info_height() > 0 and (screen.combat.get_combatant(view.unit_id).enemy_def.elite):
			elite_views += 1
	check(elite_views == 1, "the elite enemy gets the elite treatment (the regular guard does not)")
	var elite_rules := RunRules.get_block("elite_defaults")
	GameState.record_combat_victory(45, DataRegistry.get_encounter("elite_commander_01"))
	check(GameState.pending_reward.options.size() == int(elite_rules["card_options"]), "an elite victory offers the larger reward")
	GameState.end_room()

	# --- Treasure room -----------------------------------------------------------------------
	await _enter("demo_treasure")
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TREASURE, "treasure room opens")
	check(_find(SceneRouter.current_screen, "TreasureChoice0") != null and _find(SceneRouter.current_screen, "TreasureChoice4") != null, "five treasure choices are shown (equipment included)")
	await _shot("m7_4_treasure")
	var gold_mid := GameState.inventory.gold
	_reload()
	SceneRouter.resume_run()
	await _wait(0.4)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.TREASURE and (GameState.room_state["choices"] as Array).size() == 5, "reloading inside the treasure room shows the same offer")
	await _press("TreasureChoice0")
	check(GameState.inventory.gold == gold_mid + 60 and int(GameState.room_state.get("taken", -1)) == 0, "choosing gold grants it and saves the choice")
	await _press("TreasureChoice0")
	await _press("TreasureChoice1")
	check(GameState.inventory.gold == gold_mid + 60 and GameState.inventory.count_of("health_potion") == 0, "pressing again or picking another choice grants nothing more")
	_reload()
	SceneRouter.resume_run()
	await _wait(0.4)
	var again := _find(SceneRouter.current_screen, "TreasureChoice1") as BaseButton
	check(GameState.inventory.gold == gold_mid + 60 and again != null and again.disabled, "after loading, the treasure is still claimed and cannot be claimed twice")
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.3)

	# --- Rest room: card removal ---------------------------------------------------------------
	_new_run()
	GameState.map_progress.travel_to("demo_fight")
	GameState.map_progress.travel_to("demo_rest")
	SceneRouter.go_to_room(GameState.get_current_node())
	await _wait(0.4)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REST, "rest room opens")
	var chiara_deck := GameState.party.get_member("chiara").deck.size()
	await _press("RemoveButton")
	await _shot("m7_5_removal_picker")
	var removable := SceneRouter.current_screen.find_children("Removable_*", "CardView", true, false)
	check(removable.size() == GameState.party.get_total_deck_size(), "the removal picker lists the whole party deck (%d cards)" % removable.size())
	var picked := removable[0] as CardView
	picked.pressed.emit(picked)
	await _wait(0.3)
	check(GameState.party.get_total_deck_size() == chiara_deck + GameState.party.get_member("bianca").deck.size(), "choosing a card only asks for confirmation (nothing removed yet)")
	await _shot("m7_6_removal_confirm")
	await _press("ConfirmRemoval")
	await _shot("m7_7_rest_after_removal")
	check(GameState.party.get_member("chiara").deck.size() == chiara_deck - 1, "confirming removes the card from its owner's deck")
	check(int(GameState.room_state.get("removed", 0)) == 1, "the removal is recorded in the saved room state")
	var remove_button := _find(SceneRouter.current_screen, "RemoveButton") as BaseButton
	check(remove_button != null and remove_button.disabled, "the removal option is used up for this visit")
	_reload()
	check(GameState.party.get_member("chiara").deck.size() == chiara_deck - 1, "save and load keep the card removed")
	SceneRouter.resume_run()
	await _wait(0.4)
	var resumed := _find(SceneRouter.current_screen, "RemoveButton") as BaseButton
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REST and resumed != null and resumed.disabled, "reloading inside the rest room keeps the removal used (no second removal)")

	# --- Save deletion ----------------------------------------------------------------------------
	GameState.save_game()
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.4)
	check(_find(SceneRouter.current_screen, "DeleteSaveButton") != null, "the menu offers Delete Save while a save exists")
	await _press("DeleteSaveButton")
	await _shot("m7_8_delete_confirm")
	check(_find(SceneRouter.current_screen, "DeleteConfirm") != null and GameState.has_save(), "a confirmation appears and nothing is deleted yet")
	await _press("KeepSave")
	check(GameState.has_save(), "Keep Save leaves the save untouched")
	await _press("DeleteSaveButton")
	await _press("ConfirmDelete")
	check(not GameState.has_save() and _find(SceneRouter.current_screen, "DeleteSaveButton") == null, "confirming deletes the save and updates the menu")

	# --- Corrupt save: error message, file kept ------------------------------------------------------
	var file := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	file.store_string("not a save")
	file.close()
	check(GameState.load_game() != "" and GameState.has_save(), "a corrupt save gives an error and is not silently deleted")
	GameState.delete_save()
	# Defeat removes the save.
	_new_run()
	GameState.save_game()
	GameState.finish_run(GameState.RESULT_DEFEATED)
	check(not GameState.has_save(), "defeat ends the run and removes the save")
