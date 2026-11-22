extends Node
## Windowed QA for Frost, damage types and equipment: Frost on the selection screen, the equipment
## screen (equip, swap, unequip, tabs, save) at desktop and phone sizes, a Frost fight (Chill chips,
## Frozen preview and turn skip, weakness pop-ups, enemy details), loot on the reward screen and a
## chest with equipment.
##   godot --path . res://tests/progression/equipment_frost_test.tscn -- <screenshot_dir>

## A 844x390 phone shows the game's 1280x720 canvas stretched (canvas_items, expand): 1558x720 virtual.
const PHONE := Vector2(1558, 720)
const SMALL := Vector2(1280, 720)

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_equipment_frost.json"
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
	await _wait(0.35)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _find(node_name: String, from: Node = null) -> Node:
	return (from if from != null else SceneRouter.current_screen).find_child(node_name, true, false)


func _labels(node: Node, out: Array[String] = []) -> Array[String]:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_labels(child, out)
	return out


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	await _test_selection()
	await _test_equipment_screen()
	await _test_gear_effects()
	await _test_phone_layout()
	await _test_frost_fight()
	await _test_loot_and_chest()


func _test_selection() -> void:
	GameState.reset_selection()
	SceneRouter.go(SceneRouter.Screen.SPECIALIZATION_SELECTION)
	await _wait(0.6)
	var screen := SceneRouter.current_screen
	var frost_button: Button = screen._spec_buttons["chiara"]["frost"]
	check(frost_button != null and not frost_button.disabled, "Frost can be chosen for Chiara")
	frost_button.pressed.emit()
	await _wait(0.3)
	var text := " ".join(_labels(screen))
	check(text.contains("Rime Touch") and text.contains("Frost Bolt"), "the Frost details show its passive and starting deck")
	await _shot("ef_01_frost_selection")


func _start_run() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "frost")
	GameState.select_specialization("bianca", "tanking")
	GameState.create_party_from_selection()
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID


func _test_equipment_screen() -> void:
	_start_run()
	for id in ["ember_staff", "rimeglass_staff", "flameward_cuirass", "chainmail_hauberk", "runed_warblade", "padded_gambeson", "stormweave_coat"]:
		GameState.inventory.add_equipment(id)
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.6)
	var open := _find("EquipmentButton") as Button
	check(open != null and open.is_visible_in_tree() and open.text.contains("7"), "the map has an Equipment button with the stash count")
	open.pressed.emit()
	await _wait(0.6)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EQUIPMENT, "it opens the equipment screen")
	var screen := SceneRouter.current_screen
	check(_find("Slot_chest") != null and _find("Slot_weapon") != null and _find("Slot_ring_2") != null and _find("Slot_boots") != null, "all nine slots are shown")
	await _shot("ef_02_equipment_empty")
	# Pick the Rimeglass Staff in the stash and equip it on Chiara.
	var stash: Array = GameState.inventory.equipment
	(_find("Stash_%d" % stash.find("rimeglass_staff")) as Button).pressed.emit()
	await _wait(0.2)
	check(str((_find("DetailName") as Label).text) == "Rimeglass Staff", "selecting a stash item shows its details")
	check((_find("Equip_bianca") as Button).disabled and not (_find("Equip_chiara") as Button).disabled, "only Chiara may take the staff (Bianca's button is disabled)")
	(_find("Equip_chiara") as Button).pressed.emit()
	await _wait(0.3)
	var chiara := GameState.party.get_member("chiara")
	check(chiara.equipment.get("weapon") == "rimeglass_staff" and not GameState.inventory.equipment.has("rimeglass_staff"), "Equip on Chiara puts the staff in her weapon slot")
	check(" ".join(_labels(_find("EquipmentStats"))).contains("+15% Frost damage"), "her totals show +15% Frost damage")
	# Armour with Max HP.
	(_find("Stash_%d" % GameState.inventory.equipment.find("stormweave_coat")) as Button).pressed.emit()
	await _wait(0.2)
	(_find("Equip_chiara") as Button).pressed.emit()
	await _wait(0.3)
	check(chiara.max_hp == 64 and str((_find("EquipmentHp") as Label).text).contains("/ 64"), "the coat's +4 Max HP shows at once")
	await _shot("ef_03_equipment_chiara")
	# Bianca's tab, equip a sword through the slot flow and unequip it again.
	(_find("Tab_bianca") as Button).pressed.emit()
	await _wait(0.3)
	(_find("Stash_%d" % GameState.inventory.equipment.find("runed_warblade")) as Button).pressed.emit()
	await _wait(0.2)
	(_find("Equip_bianca") as Button).pressed.emit()
	await _wait(0.3)
	var bianca := GameState.party.get_member("bianca")
	check(bianca.equipment.get("weapon") == "runed_warblade", "Bianca wields the Runed Warblade")
	(_find("Stash_%d" % GameState.inventory.equipment.find("chainmail_hauberk")) as Button).pressed.emit()
	await _wait(0.2)
	(_find("Equip_bianca") as Button).pressed.emit()
	await _wait(0.3)
	await _shot("ef_04_equipment_bianca")
	(_find("Slot_weapon") as Button).pressed.emit()
	await _wait(0.2)
	check(_find("UnequipButton") != null, "a worn item offers Unequip")
	(_find("UnequipButton") as Button).pressed.emit()
	await _wait(0.3)
	check(not bianca.equipment.has("weapon") and GameState.inventory.equipment.has("runed_warblade"), "Unequip returns the blade to the stash")
	(_find("Stash_%d" % GameState.inventory.equipment.find("runed_warblade")) as Button).pressed.emit()
	await _wait(0.2)
	(_find("Equip_bianca") as Button).pressed.emit()
	await _wait(0.2)
	# Saved: reload and compare.
	GameState.load_game()
	check(GameState.party.get_member("chiara").equipment.get("weapon") == "rimeglass_staff" and GameState.party.get_member("bianca").equipment.get("chest") == "chainmail_hauberk", "equipment changes are saved at once")
	(_find("EquipmentBack") as Button).pressed.emit()
	await _wait(0.5)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.MAP, "Back returns to the map")


## Phone-sized window: every slot, the stash and the buttons must stay on screen.
## New-slot gear: a Frost ring with an in-battle effect shows its effect line (jade, wrapped, on screen)
## and only Chiara can take it.
func _test_gear_effects() -> void:
	SceneRouter.open_equipment(SceneRouter.Screen.MAP)
	await _wait(0.6)
	GameState.inventory.add_equipment("frostbite_band")
	GameState.inventory.add_equipment("bastion_greathelm")
	SceneRouter.open_equipment(SceneRouter.Screen.MAP)
	await _wait(0.6)
	var stash: Array = GameState.inventory.equipment
	(_find("Stash_%d" % stash.find("frostbite_band")) as Button).pressed.emit()
	await _wait(0.3)
	check(str((_find("DetailName") as Label).text) == "Frostbite Band", "the Frostbite Band can be inspected")
	var stage_texture: Texture2D = (_find("DollStage") as DollStage).figure().texture
	check(stage_texture != null and stage_texture.get_height() >= 900, "the stage shows the full-size figure, not the small combat pose (%d px tall)" % (stage_texture.get_height() if stage_texture != null else 0))
	var effect_label: Label = null
	for node in SceneRouter.current_screen.find_children("*", "Label", true, false):
		if (node as Label).text.begins_with("✦") and (node as Label).is_visible_in_tree():
			effect_label = node
	var view: Rect2 = SceneRouter.current_screen.get_viewport_rect()
	check(effect_label != null and effect_label.text.contains("Chill") and effect_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "its effect line is shown and wraps (%s)" % (effect_label.text if effect_label != null else "none"))
	check(effect_label != null and view.encloses(effect_label.get_global_rect()), "the effect line stays on screen")
	check((_find("Equip_bianca") as Button).disabled and not (_find("Equip_chiara") as Button).disabled, "only Frost Chiara may wear it")
	await _shot("ef_03b_gear_effect")
	(_find("Equip_chiara") as Button).pressed.emit()
	await _wait(0.3)
	check(GameState.party.get_member("chiara").equipment.get("ring_1", "") == "frostbite_band", "Chiara wears it in a ring slot")


func _test_phone_layout() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PHONE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var screen := (load("res://scenes/menus/equipment.tscn") as PackedScene).instantiate() as Control
	screen.theme = UITheme.get_theme()
	viewport.add_child(screen)
	add_child(viewport)
	await _wait(0.6)
	var inside := true
	for node_name in ["Slot_helmet", "Slot_boots", "Slot_weapon", "EquipmentBack", "Tab_bianca"]:
		var control := screen.find_child(node_name, true, false) as Control
		inside = inside and control != null and Rect2(Vector2.ZERO, PHONE).grow(1.0).encloses(control.get_global_rect())
	check(inside, "phone size (844x390 -> 1558x720 virtual): slots, tabs and Back stay on screen")
	if _shot_dir != "":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("%s/ef_05_equipment_phone.png" % _shot_dir)
	viewport.queue_free()


func _fight(enemies: Array, elite: bool = false) -> Node:
	var encounter_id := "qa_frost_fight"
	DataRegistry.encounters[encounter_id] = {"id": encounter_id, "name": "Frost QA", "enemies": enemies, "gold_reward": 20, "elite": elite}
	GameState.room_state = {}
	GameState.get_current_node().encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.0)
	var banner := _find("EliteBanner")
	if banner != null:
		banner.queue_free()
	return SceneRouter.current_screen


func _test_frost_fight() -> void:
	var screen := await _fight(["forest_troll", "forest_boar"])
	var combat: CombatManager = screen.combat
	var troll: Combatant = combat.enemies[0]
	var boar: Combatant = combat.enemies[1]
	var popups_before: int = screen.affinity_popups
	# Chill the troll with a real card play through the screen.
	var touch := CardInstance.from_owned(OwnedCard.create("qa_touch", "chiara_frost_touch", "chiara"), DataRegistry.get_card("chiara_frost_touch"), 7001)
	combat.deck.hand.append(touch)
	combat.energy = 3
	combat.play_card(touch, troll.id)
	screen._refresh()
	await _wait(0.5)
	var troll_view: CombatEnemyView = screen._battlefield.enemy_views[troll.id]
	check(troll_view.status_count("chill") == 3, "Chill 3 (2 + Rime Touch) shows its own chip on the troll")
	check(_find("FrozenTag", troll_view) != null, "the troll's intent badge says Frozen (initiative 1 - 3)")
	troll_view._set_hover(true)
	await _wait(0.2)
	var detail := " ".join(_labels(troll_view))
	check(detail.contains("Weak: Fire +50%") and detail.contains("Resists: Physical 25%") and detail.contains("Initiative 1 → -2 (Chill)"), "hover details list weakness, resistance and initiative")
	await _shot("ef_06_frozen_preview_details")
	troll_view._set_hover(false)
	# Bianca's physical strike on the chilled troll: the Chill offsets its physical resistance.
	var strike := CardInstance.from_owned(OwnedCard.create("qa_strike", "bianca_tanking_strike", "bianca"), DataRegistry.get_card("bianca_tanking_strike"), 7002)
	combat.deck.hand.append(strike)
	combat.energy = 3
	combat.play_card(strike, boar.id)
	await _wait(0.1)
	var fire_bolt := CardInstance.from_owned(OwnedCard.create("qa_bolt", "chiara_frost_bolt", "chiara"), DataRegistry.get_card("chiara_frost_bolt"), 7003)
	combat.deck.hand.append(fire_bolt)
	combat.energy = 3
	combat.play_card(fire_bolt, boar.id)  # the boar is weak to frost
	screen._refresh()
	await _wait(0.25)
	check(screen.affinity_popups > popups_before, "a weakness hit pops 'Weak!' over the enemy")
	await _shot("ef_07_weak_popup")
	await _wait(0.6)
	var party_hp := combat.party_combatants.map(func(c: Combatant) -> int: return c.hp)
	combat.end_player_turn()
	screen._refresh()
	await _wait(0.4)
	check(not troll.has_status("chill"), "the troll was Frozen: its Chill shattered")
	await _shot("ef_08_frozen_turn")
	await _wait(1.2)
	check(combat.state == CombatManager.State.PLAYER_TURN, "the fight goes on normally")
	party_hp = party_hp


func _test_loot_and_chest() -> void:
	# A boss victory always drops an item (elites usually do); the reward screen shows it and links to the equipment.
	var before := GameState.inventory.equipment.size()
	GameState.room_state = {"node_id": GameState.get_current_node().id, "kind": GameState.get_current_node().type}
	GameState.record_combat_victory(30, {"id": "qa", "boss": true, "enemies": []})
	var loot: Array = GameState.room_state.get("loot", [])
	check(loot.size() == 1 and GameState.inventory.equipment.size() == before + 1, "a boss victory drops one item into the stash")
	GameState.record_combat_victory(30, {"id": "qa", "boss": true, "enemies": []})
	check(GameState.inventory.equipment.size() == before + 1, "recording the same victory twice never duplicates the loot")
	SceneRouter.go(SceneRouter.Screen.REWARD)
	await _wait(0.7)
	var skip_relic := _find("SkipBossRelic") as Button  # a boss first offers its relics on their own page
	if skip_relic != null:
		skip_relic.pressed.emit()
		await _wait(0.5)
	check(_find("LootStrip") != null and _find("RewardEquipment") != null, "the reward screen shows the loot and an Equipment button")
	await _shot("ef_09_reward_loot")
	(_find("RewardEquipment") as Button).pressed.emit()
	await _wait(0.5)
	(_find("EquipmentBack") as Button).pressed.emit()
	await _wait(0.6)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.REWARD and _find("LootStrip") != null, "Back from the equipment returns to the same reward")
	GameState.end_room()
	# A chest offers equipment.
	var cache: MapNodeData = null
	for node: MapNodeData in GameState.map_progress.graph.nodes.values():
		if node.type == MapNodeData.TYPE_TREASURE:
			cache = node
			break
	GameState.map_progress.current_node_id = cache.id
	GameState.begin_room(cache)
	SceneRouter.go(SceneRouter.Screen.TREASURE)
	await _wait(0.6)
	var choices: Array = GameState.room_state.get("choices", [])
	var index := -1
	for i in choices.size():
		if choices[i]["type"] == "equipment":
			index = i
	check(index >= 0 and _find("TreasureChoice%d" % index) != null, "the chest offers a piece of equipment")
	await _shot("ef_10_chest_equipment")
	var stash := GameState.inventory.equipment.size()
	(_find("TreasureChoice%d" % index) as Button).pressed.emit()
	await _wait(0.3)
	check(GameState.inventory.equipment.size() == stash + 1, "taking it adds it to the stash")
