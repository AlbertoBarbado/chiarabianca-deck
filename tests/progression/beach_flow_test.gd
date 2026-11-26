extends Node
## Windowed QA for Act III, the Sunlit Coast: the scrolling map, beach fights with the generated
## monsters and backdrop, Soaked / Sandblind / Quicksand on screen, the three elites and the
## Sandstorm Elemental, a town, a shop selling equipment and an event that gives equipment.
##   godot --path . res://tests/progression/beach_flow_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_beach_flow.json"
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
	await _wait(0.3)
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


func _new_run(chiara: String = "frost", bianca: String = "tanking") -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara)
	GameState.select_specialization("bianca", bianca)
	GameState.create_party_from_selection()
	GameState.next_map_id = "sunlit_coast"
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID


func _fight(encounter_id: String, node_id: String = "") -> Node:
	GameState.room_state = {}
	if node_id != "":
		GameState.map_progress.current_node_id = node_id
	GameState.get_current_node().encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.0)
	return SceneRouter.current_screen


func _skip_intro() -> void:
	var banner := _find("EliteBanner")
	if banner != null:
		banner.queue_free()
		await _wait(0.2)


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	# The main menu offers a direct start on the coast (and in the forest).
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.5)
	await _shot("beach_00_main_menu")
	(_find("QuickPlayButton") as Button).pressed.emit()  # the direct starts live in the Quick Play submenu
	await _wait(0.3)
	var coast_button := _find("ActCoastButton") as Button
	check(_find("ActForestButton") != null and coast_button != null and coast_button.is_visible_in_tree(), "the main menu offers Start: Forest and Start: Coast")
	var lowest := 0.0
	for button: Control in SceneRouter.current_screen.find_children("*", "Button", true, false):
		lowest = maxf(lowest, button.get_global_rect().end.y)
	check(lowest <= get_viewport().get_visible_rect().size.y, "every menu button fits on the 720p screen (lowest edge %d)" % lowest)
	coast_button.pressed.emit()
	await _wait(0.4)
	check(GameState.next_map_id == "sunlit_coast" and SceneRouter.current_screen_id == SceneRouter.Screen.CHARACTER_SELECTION, "Start: Coast opens the party selection for a coast run")
	GameState.select_specialization("chiara", "frost")
	GameState.select_specialization("bianca", "tanking")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	check(GameState.map_progress.graph.id == "sunlit_coast", "the run begins on the Sunlit Coast")
	_new_run()
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.8)
	var view: MapView = SceneRouter.current_screen._map_view
	check(view.has_background() and view.get_layout().background_asset == "map_sunlit_coast", "the coast map shows its generated picture")
	check(GameState.map_progress.get_available_ids().size() == 3, "three paths leave the Shipwreck Landing")
	await _shot("beach_01_map")

	# A shore fight on the sand: two Sand Scorpions and a rock spider.
	var screen := await _fight("beach_salt_flats", "salt_flats")
	check(str(screen._backdrop().get("asset_id", "")) == "battle_beach", "shore fights use the beach backdrop")
	var shore_views: Array = screen._battlefield.enemy_views.values()
	check(shore_views.size() == 3 and shore_views.all(func(v: CombatUnitView) -> bool: return v.get_art_rect().size.y > 40.0), "the Sand Scorpions and the rock spider stand on the sand")
	screen.combat.end_player_turn()
	screen._refresh()
	await _wait(1.4)
	check(screen.combat.party_combatants.any(func(c: Combatant) -> bool: return c.has_status("sandblind")), "Sand Spray leaves a princess Sandblind")
	await _shot("beach_02a_shore_fight")
	# A sea fight aboard the ship: triton, Shark Knight and albatross.
	screen = await _fight("beach_storm_vanguard", "storm_front")
	check(str(screen._backdrop().get("asset_id", "")) == "battle_ship_deck", "sea fights are fought on the ship deck")
	var views: Array = screen._battlefield.enemy_views.values()
	check(views.size() == 3 and views.all(func(v: CombatUnitView) -> bool: return v.get_art_rect().size.y > 40.0), "the triton, Shark Knight and albatross stand on the deck")
	check((views[1] as CombatUnitView).get_art_rect().size.y > (views[0] as CombatUnitView).get_art_rect().size.y * 0.9, "the Shark Knight is at least as tall as a triton")
	check((views[2] as CombatUnitView).motion_profile_id() == "hover", "the albatross hovers")
	await _shot("beach_02_sea_fight")
	var triton: Combatant = screen.combat.enemies[0]
	var triton_view: CombatEnemyView = screen._battlefield.enemy_views[triton.id]
	triton_view._set_hover(true)
	await _wait(0.2)
	var detail := " ".join(_labels(triton_view))
	check(detail.contains("Weak: Lightning") and detail.contains("Resists: Water") and detail.contains("water dmg"), "the triton's details: weak to lightning, resists water, water attack")
	await _shot("beach_03_triton_details")
	triton_view._set_hover(false)
	screen.combat.end_player_turn()
	screen._refresh()
	await _wait(1.6)
	var soaked: Array = screen.combat.party_combatants.filter(func(c: Combatant) -> bool: return c.has_status("soaked"))
	check(soaked.size() == screen.combat.party_combatants.filter(func(c: Combatant) -> bool: return c.is_alive()).size(), "Tide Surge and the Shark Knight's Riptide Cleave soak the party")
	var soaked_view: CombatUnitView = screen._battlefield.party_views[soaked[0].id]
	check(soaked_view.status_count("soaked") >= 1, "Soaked shows its own chip")
	await _shot("beach_04_soaked_at_sea")
	# Rock spiders on the shore still drag the party into Quicksand.
	screen = await _fight("beach_spiders", "rocky_path")
	screen.combat.end_player_turn()
	screen._refresh()
	await _wait(1.4)
	check(screen.combat.party_combatants.any(func(c: Combatant) -> bool: return c.has_status("quicksand")) or screen.combat.deck.hand.size() < 5, "Sand Web drags someone into Quicksand")

	# The three elites.
	for elite in [["elite_sea_snake", "sandy_ridge"], ["elite_rock_giant", "sea_caves"], ["elite_sand_giant", "rockfall"]]:
		var elite_id: String = elite[0]
		screen = await _fight(elite_id, elite[1])
		check(str(screen._backdrop().get("asset_id", "")) == ("battle_ship_deck" if elite_id == "elite_sea_snake" else "battle_beach"), "%s is fought %s" % [elite_id, "aboard the ship" if elite_id == "elite_sea_snake" else "on the shore"])
		check(screen.combat.is_elite and _find("EliteBanner") != null, "%s opens with its introduction" % elite_id)
		await _wait(1.2)
		await _shot("beach_05_%s_intro" % elite_id)
		await _skip_intro()
		screen.combat.end_player_turn()
		screen._refresh()
		await _wait(1.4)
		await _shot("beach_06_%s_attack" % elite_id)
	check(screen.combat.party_combatants.all(func(c: Combatant) -> bool: return c.has_status("sandblind") or not c.is_alive()), "the Sand Giant's gust leaves the party Sandblind")

	# The boss.
	screen = await _fight("boss_sandstorm_elemental", "eye_of_the_storm")
	check(screen.combat.is_boss and _find("EliteBanner") != null, "the Sandstorm Elemental opens with its cinematic")
	await _wait(1.6)
	await _shot("beach_07_boss_intro")
	await _skip_intro()
	var boss: Combatant = screen.combat.enemies[0]
	var boss_view: CombatUnitView = screen._battlefield.enemy_views[boss.id]
	check(boss_view.size_scale >= 1.5 and boss_view.motion_profile_id() == "hover", "the boss is large and hovers")
	boss.add_status("chill", 5, "chiara")
	screen._refresh()
	check(not boss.will_freeze(), "it cannot be frozen")
	screen.combat.end_player_turn()  # Sandstorm: Sandblind on everyone
	screen.combat.end_player_turn()  # Scouring Lash
	screen.combat.end_player_turn()  # Sinking Sands: Quicksand
	screen._refresh()
	await _wait(1.5)
	await _shot("beach_08_boss_fight")
	check(screen.combat.state != CombatManager.State.VICTORY, "the boss fight goes on")

	# Town, shop and an event.
	_new_run()
	var graph := GameState.map_progress.graph
	GameState.map_progress.current_node_id = "fishers_hamlet"
	GameState.begin_room(graph.get_node_data("fishers_hamlet"))
	SceneRouter.go(SceneRouter.Screen.TOWN)
	await _wait(0.6)
	check(" ".join(_labels(SceneRouter.current_screen)).contains("Fishers' Flotilla"), "the Fishers' Flotilla opens")
	# A town's own scene wins over the terrain picture (the flotilla is painted at sea).
	check(str(SceneRouter.current_screen._backdrop().get("asset_id", "")) == "town_fishers_hamlet", "the floating town shows its own scene at sea")
	await _shot("beach_09_town")
	SceneRouter.go(SceneRouter.Screen.MERCHANT)
	await _wait(0.6)
	GameState.inventory.gold = 300
	SceneRouter.go(SceneRouter.Screen.MERCHANT)
	await _wait(0.6)
	var text := " ".join(_labels(SceneRouter.current_screen))
	check(text.contains("Coral Mail") and text.contains("Water resistance 30%"), "the fish market sells Coral Mail with its stats")
	await _shot("beach_10_shop_equipment")
	GameState.map_progress.current_node_id = "driftwood_cove"
	GameState.begin_room(graph.get_node_data("driftwood_cove"))
	GameState.room_state["event_id"] = "beach_shipwreck"
	SceneRouter.open_room_screen(graph.get_node_data("driftwood_cove"))
	await _wait(0.6)
	check(" ".join(_labels(SceneRouter.current_screen)).contains("Gilded Gull"), "the shipwreck event opens")
	await _shot("beach_11_event")
	var dive := _find("EventChoice1") as Button
	if dive != null:
		dive.pressed.emit()
		await _wait(0.5)
	check(GameState.inventory.equipment.has("kelpwoven_coat"), "diving into the wreck gives the Kelpwoven Coat")
