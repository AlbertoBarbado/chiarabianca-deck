extends Node
## Art-direction tour (docs/ART_DIRECTION.md): opens every screen of the game once (menus, setup,
## every expedition room type, combat, rewards, the castle and each castle service) and checks that
## it opens; with a screenshot directory it saves one picture per screen for the UI review.
##   godot --path . res://tests/ui/ui_tour_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_ui_tour.json"
	GameState.use_slot(GameState.SLOT_QUICKPLAY)
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


## Opens a screen, checks it is the current one and takes its picture.
func _visit(screen: SceneRouter.Screen, shot_name: String) -> void:
	SceneRouter.go(screen)
	await _wait(0.6)
	check(SceneRouter.current_screen_id == screen and SceneRouter.current_screen != null, "%s opens" % shot_name)
	await _shot(shot_name)


func _run() -> void:
	await _visit(SceneRouter.Screen.MAIN_MENU, "t01_main_menu")
	await _visit(SceneRouter.Screen.SETTINGS, "t02_settings")
	GameState.new_game_mode = "classic"
	GameState.reset_selection()
	await _visit(SceneRouter.Screen.CHARACTER_SELECTION, "t03_character_selection")
	await _visit(SceneRouter.Screen.SPECIALIZATION_SELECTION, "t04_specialization_selection")
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	# A forest run: one room of every type.
	GameState.create_party_from_selection()
	await _visit(SceneRouter.Screen.PARTY_OVERVIEW, "t05_party_overview")
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	GameState.inventory.add_gold(300)
	GameState.inventory.add_item("minor_health_potion", 2)
	RelicEffects.gain("ley_crystal", GameState.party, GameState.inventory)
	await _visit(SceneRouter.Screen.MAP, "t06_map")
	SceneRouter.open_equipment(SceneRouter.Screen.MAP)
	await _wait(0.6)
	check(SceneRouter.current_screen_id == SceneRouter.Screen.EQUIPMENT, "the equipment screen opens")
	await _shot("t07_equipment")
	var graph := GameState.map_progress.graph
	var seen := {}
	for node: MapNodeData in graph.nodes.values():
		if seen.has(node.type) or node.type in ["start", "exit"]:
			continue
		seen[node.type] = true
		GameState.map_progress.current_node_id = node.id
		GameState.room_state = {}
		SceneRouter.go_to_room(node)
		await _wait(0.8)
		check(SceneRouter.current_screen != null, "the %s room opens" % node.type)
		await _shot("t10_room_%s" % node.type)
		if node.type == "combat":
			var screen := SceneRouter.current_screen
			GameState.record_combat_victory(screen.combat.gold_reward, screen._encounter)
			await _visit(SceneRouter.Screen.REWARD, "t11_card_reward")
	await _visit(SceneRouter.Screen.ACT_TRANSITION, "t12_act_transition")
	await _visit(SceneRouter.Screen.RUN_END, "t13_run_end")
	# The castle: hub, war table, preparation, results and every service.
	GameState.new_game_mode = "campaign"
	GameState.use_slot(GameState.SLOT_CAMPAIGN)
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.start_campaign()
	var campaign := GameState.campaign
	campaign.vault.gold = 800
	campaign.essence = 3
	for service in ["blacksmith", "enchanter", "training_hall"]:
		if not campaign.services.has(service):
			campaign.services.append(service)
	await _visit(SceneRouter.Screen.CASTLE_HUB, "t20_castle_hub")
	await _visit(SceneRouter.Screen.WORLD_MAP, "t21_world_map")
	SceneRouter.open_preparation("castle_awakening")
	await _wait(0.6)
	await _shot("t22_preparation")
	for service in ["library", "collection", "apothecary", "blacksmith", "enchanter", "training_hall", "sisters"]:
		SceneRouter.open_service(service)
		await _wait(0.6)
		check(SceneRouter.current_screen_id == SceneRouter.Screen.CASTLE_SERVICE, "the %s opens" % service)
		await _shot("t3_%s" % service)
	SceneRouter.open_equipment(SceneRouter.Screen.CASTLE_HUB)
	await _wait(0.6)
	await _shot("t40_armory")
	GameState.delete_save()
	GameState.use_slot(GameState.SLOT_QUICKPLAY)
