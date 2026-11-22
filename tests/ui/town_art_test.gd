extends Node
## Windowed: every town shows its illustration (framed, and as the backdrop) and every merchant
## stands beside the stock; screenshots of a few for review.
##   godot --path . res://tests/ui/town_art_test.tscn -- <screenshot_dir>

## [map id, town id or "" for a plain merchant node, merchant node id (castle)]
const MAPS := {"enchanted_forest": "forest", "sunlit_coast": "beach"}
const SHOTS := ["elderwood_village", "fishers_hamlet", "dune_village", "last_trader_outpost"]

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_town_art.json"
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
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _art_shown(name_hint: String) -> bool:
	var art := SceneRouter.current_screen.find_child(name_hint, true, false) as FramedArt
	return art != null and art.has_art() and art.is_visible_in_tree() and art.size.x > 100.0


func _run() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "ashveil")
	GameState.create_party_from_selection()
	for map_id: String in MAPS:
		GameState.next_map_id = map_id
		GameState.begin_adventure()
		GameState.inventory.gold = 300
		for node: MapNodeData in GameState.map_progress.graph.nodes.values():
			if node.type != MapNodeData.TYPE_TOWN:
				continue
			GameState.room_state = {}
			GameState.map_progress.current_node_id = node.id
			SceneRouter.go(SceneRouter.Screen.TOWN)
			await _wait(0.5)
			check(_art_shown("FramedArt"), "%s: the town's picture is shown" % node.town_id)
			if SHOTS.has(node.town_id):
				await _shot("town_%s" % node.town_id)
			var town := DataRegistry.get_town(node.town_id)
			if (town.get("services", []) as Array).has("merchant"):
				SceneRouter.go(SceneRouter.Screen.MERCHANT)
				await _wait(0.5)
				check(_art_shown("MerchantArt"), "%s: the merchant stands beside the stock" % str(town.get("shop_id", "")))
				if SHOTS.has(node.town_id):
					await _shot("merchant_%s" % str(town.get("shop_id", "")))
	# The castle merchant (a merchant node, not a town): framed and as the backdrop.
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	GameState.begin_adventure()
	for node: MapNodeData in GameState.map_progress.graph.nodes.values():
		if node.type == MapNodeData.TYPE_MERCHANT:
			GameState.room_state = {}
			GameState.map_progress.current_node_id = node.id
			SceneRouter.go(SceneRouter.Screen.MERCHANT)
			await _wait(0.5)
			check(_art_shown("MerchantArt"), "castle merchant (%s) is shown" % node.id)
			await _shot("merchant_castle")
			break
