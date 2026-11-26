extends Node
## Crystal Hollow demo area (art generated locally with ComfyUI): menu entry, map with the generated
## picture, fights with the generated monsters and backdrop, Bleed / Poison / Burn on screen, boss.
##   godot --path . res://tests/progression/demo_area_test.tscn -- <screenshot_dir>

const MAP_ID := "crystal_hollow_demo"
const ART := ["map_crystal_hollow", "battle_crystal_hollow", "monster_crystal_golem", "monster_cave_bat",
	"monster_fungal_shambler", "monster_shadow_wraith", "boss_crystal_wyrm"]

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_demo_area.json"
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


func _fight(encounter_id: String, node_type: String = "combat") -> Node:
	GameState.room_state = {}
	var node := GameState.get_current_node()
	node.encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(0.6)
	return SceneRouter.current_screen


func _run() -> void:
	# Generated art is present and readable.
	var art_ok := true
	for id in ART:
		var path := "res://assets/generated/demo/%s.png" % id
		art_ok = art_ok and ResourceLoader.exists(path) and load(path) != null
	check(art_ok, "all generated demo pictures exist and load")
	var sprite := (load("res://assets/generated/demo/monster_cave_bat.png") as Texture2D).get_image()
	check(sprite.get_pixel(2, 2).a < 0.1 and sprite.get_pixel(sprite.get_width() / 2, sprite.get_height() / 2).a > 0.5, "monster sprites are cut out (transparent corners, solid body)")

	# Menu entry.
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.5)
	await _shot("demo_01_main_menu")
	(_find("QuickPlayButton") as Button).pressed.emit()  # demos live in the Quick Play submenu
	await _wait(0.3)
	var button := _find("DemoCrystalButton") as Button
	check(button != null and button.is_visible_in_tree(), "the main menu offers Demo: Crystal Hollow")
	button.pressed.emit()
	await _wait(0.4)
	check(GameState.next_map_id == MAP_ID and SceneRouter.current_screen_id == SceneRouter.Screen.CHARACTER_SELECTION, "it starts a new game on the demo map")
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "tanking")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	check(GameState.map_progress.graph.id == MAP_ID and GameState.map_progress.graph.validate().is_empty(), "the demo map is valid")
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.6)
	var view: MapView = SceneRouter.current_screen._map_view
	check(view.has_background() and view.get_layout().background_asset == "map_crystal_hollow", "the map shows the generated picture with its layout")
	await _shot("demo_02_map")

	# Fights with generated monsters.
	var screen := await _fight("demo_spores")
	check(str(screen._backdrop().get("asset_id", "")) == "battle_crystal_hollow", "demo fights use the generated cavern backdrop")
	var views: Array = screen._battlefield.enemy_views.values()
	check(views.size() == 2 and (views[0] as CombatUnitView).get_art_rect().size.y > 40.0, "the generated monsters are on the battlefield")
	screen.combat.end_player_turn()
	await _wait(1.0)
	var statuses := 0
	for c: Combatant in screen.combat.party_combatants:
		statuses += c.statuses.size()
	check(statuses > 0, "spores and fangs left Poison or Bleed on the party")
	await _shot("demo_03_fight_statuses")

	screen = await _fight("demo_boss_wyrm")
	check(screen.combat.is_boss and _find("EliteBanner") != null, "the Crystal Wyrm boss opens with its cinematic")
	await _wait(1.6)
	await _shot("demo_04_boss_intro")
	await _wait(3.5)
	var wyrm: Combatant = screen.combat.enemies[0]
	wyrm.add_status("burn", 3, "chiara")
	for c: Combatant in screen.combat.party_combatants:
		c.add_status("bleed", 2, wyrm.id)
		c.add_status("poison", 3, wyrm.id)
	screen._refresh()
	await _wait(0.5)
	var chiara_view: CombatUnitView = screen._battlefield.party_views["chiara"]
	var wyrm_view: CombatUnitView = screen._battlefield.enemy_views[wyrm.id]
	check(chiara_view.status_count("bleed") == 2 and chiara_view.status_count("poison") == 3 and wyrm_view.status_count("burn") == 3, "Bleed, Poison and Burn each show their own counter")
	await _shot("demo_05_boss_three_statuses")
