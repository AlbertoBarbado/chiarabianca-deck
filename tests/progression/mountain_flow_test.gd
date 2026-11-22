extends Node
## Windowed QA for Frostpeak: the main menu button, the climbing map (scrolling mountain picture and
## altitude gauge) at the foot and halfway up, a fight in each altitude band, the White Dragon and a
## mountain village.
##   godot --path . res://tests/progression/mountain_flow_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_mountain_flow.json"
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


func _find(node_name: String) -> Node:
	return SceneRouter.current_screen.find_child(node_name, true, false)


func _map_view(node: Node) -> MapView:
	if node is MapView:
		return node
	for child in node.get_children():
		var found := _map_view(child)
		if found != null:
			return found
	return null


func _fight(encounter_id: String, node_id: String) -> Node:
	GameState.room_state = {}
	GameState.map_progress.current_node_id = node_id
	GameState.get_current_node().encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.2)
	var banner := _find("EliteBanner")
	if banner != null:
		banner.queue_free()
	await _wait(0.4)
	return SceneRouter.current_screen


func _run() -> void:
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.8)
	var button := _find("ActFrostpeakButton") as Button
	check(button != null and not button.disabled, "the main menu offers Frostpeak")
	await _shot("mt_01_main_menu")
	# Start the adventure as the button does, with a Fire + Holy party.
	GameState.next_map_id = "frostpeak"
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	check(GameState.map_progress.graph.id == "frostpeak" and GameState.next_map_after_current() == "", "the run starts at the foothills and ends on the summit")
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(1.0)
	var view := _map_view(SceneRouter.current_screen)
	check(view != null and view.is_scrollable(), "the map scrolls")
	check(view != null and view.find_child("ClimbPicture", true, false) != null and view.find_child("Altimeter", true, false) != null, "the mountain picture and the altitude gauge are drawn")
	check(view != null and view.current_altitude() == 1400, "the gauge reads 1,400 m at the foot")
	await _shot("mt_02_map_foothills")
	# Halfway up: the party has reached the Ropebridge Outpost.
	GameState.map_progress.current_node_id = "ropebridge_outpost"
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(1.0)
	view = _map_view(SceneRouter.current_screen)
	check(view != null and view.current_altitude() > 3000 and view.get_scroll() < view.max_scroll() * 0.8, "halfway up the gauge reads %d m and the chart has scrolled up" % (view.current_altitude() if view != null else 0))
	await _shot("mt_03_map_glacier")
	GameState.map_progress.current_node_id = "last_cairn"
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(1.0)
	await _shot("mt_04_map_summit")
	# One fight per band, then the dragon.
	var screen: Node = await _fight("mountain_wolf_ridge", "wolf_ridge")
	check(screen.battle_backdrop_id() == "battle_mountain_slopes", "slope fights stand among snowy pines")
	await _shot("mt_05_fight_slopes")
	screen = await _fight("elite_crystal_matriarch", "crystal_nest")
	check(screen.battle_backdrop_id() == "battle_mountain_glacier", "glacier fights are in the ice cave")
	await _shot("mt_06_fight_glacier_elite")
	screen = await _fight("mountain_thunder_cliffs", "thunder_cliffs")
	check(screen.battle_backdrop_id() == "battle_mountain_summit", "summit fights are above the clouds")
	await _shot("mt_07_fight_summit")
	screen = await _fight("boss_white_dragon", "dragons_aerie")
	check(screen.battle_backdrop_id() == "battle_dragon_aerie" and screen.combat.enemies[0].enemy_def.id == "boss_white_dragon", "the White Dragon waits in her aerie")
	await _shot("mt_08_white_dragon")
	screen.combat.end_player_turn()
	await _wait(2.5)
	check(screen.combat.party_combatants.all(func(c: Combatant) -> bool: return c.has_status("frostbitten")), "her Frost Breath leaves both princesses Frostbitten")
	await _shot("mt_09_frostbitten")
	# A mountain village.
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "cloud_monastery"
	SceneRouter.go(SceneRouter.Screen.TOWN)
	await _wait(1.0)
	await _shot("mt_10_cloud_monastery")
	check(SceneRouter.current_screen != null, "the Cloud Monastery opens")
