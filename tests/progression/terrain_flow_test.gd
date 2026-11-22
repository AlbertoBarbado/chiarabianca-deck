extends Node
## Windowed QA of terrain battles on every map: each terrain fight shows its own backdrop and its
## own monsters, and every unit stands on the floor of that picture on 16:9, ultrawide and phone
## screens. "Standing" is measured on the visible pixels: the lowest opaque row of each sprite must
## be on the walkable floor (below the backdrop's floor top) and, for grounded units, on the common
## ground line of the battlefield (no floating). Hovering creatures only need their shadow on floor.
##   godot --path . res://tests/progression/terrain_flow_test.tscn -- <screenshot_dir>

## [map id, room id, encounter id, expected backdrop]
const CASES := [
	["royal_castle_tutorial", "training_yard", "castle_training_01", "battle_castle_yard"],
	["royal_castle_tutorial", "west_training", "castle_training_02", "battle_castle_yard"],
	["royal_castle_tutorial", "throne_approach", "castle_final_regular_01", "battle_castle_generic"],
	["castle_elite_demo", "demo_vanguard", "elite_vanguard_01", "battle_castle_yard"],
	["castle_elite_demo", "demo_elite", "elite_commander_01", "battle_castle_generic"],
	["enchanted_forest", "fern_gully", "forest_wolf_harpy", "battle_forest_mountain"],
	["enchanted_forest", "venom_marsh", "forest_eagle_crag", "battle_forest_mountain"],
	["enchanted_forest", "thorn_maze", "forest_spider_ambush", "battle_forest_deepwood"],
	["enchanted_forest", "broodmothers_lair", "elite_broodmother", "battle_forest_deepwood"],
	["enchanted_forest", "bone_clearing", "forest_bone_clearing", "battle_forest"],
	["enchanted_forest", "drake_marsh", "elite_elder_drake", "battle_forest"],
	["enchanted_forest", "serpents_domain", "boss_forest_serpent", "battle_forest"],
	["crystal_hollow_demo", "bat_roost", "demo_bats", "battle_crystal_chasm"],
	["crystal_hollow_demo", "spore_grove", "demo_spores", "battle_crystal_hollow"],
	["crystal_hollow_demo", "glittering_deep", "demo_mixed", "battle_crystal_ruins"],
	["crystal_hollow_demo", "wyrm_lair", "demo_boss_wyrm", "battle_crystal_hollow"],
	["sunlit_coast", "storm_front", "beach_storm_vanguard", "battle_ship_deck"],
	["sunlit_coast", "sandy_ridge", "elite_sea_snake", "battle_ship_deck"],
	["sunlit_coast", "salt_flats", "beach_salt_flats", "battle_beach"],
	["sunlit_coast", "rockfall", "elite_sand_giant", "battle_beach"],
	["sunlit_coast", "eye_of_the_storm", "boss_sandstorm_elemental", "battle_beach"],
]
## Window sizes: 16:9, ultrawide (1706x720 virtual) and a landscape phone (1558x720 virtual).
const SCREENS := [Vector2i(1280, 720), Vector2i(2560, 1080), Vector2i(844, 390)]
## Visible feet must be at least this share of the picture height below the floor top, so a unit
## never stands on the horizon line.
const FLOOR_MARGIN := 0.07
## A grounded unit's visible feet may be this many pixels above the common ground line (thin legs,
## anti-aliased edges); more than that reads as floating.
const FLOAT_TOLERANCE := 6.0

var _failures := 0
var _checks := 0
var _shot_dir := ""
var _bottoms: Dictionary = {}  # texture rid -> lowest opaque row share (cached)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_terrain_flow.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.5)
	await _run()
	get_window().size = SCREENS[0]
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


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	var current_map := ""
	for entry: Array in CASES:
		var map_id: String = entry[0]
		if map_id != current_map:
			_new_run(map_id)
			current_map = map_id
		await _case(entry)


func _new_run(map_id: String) -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "frost")
	GameState.select_specialization("bianca", "tanking")
	GameState.create_party_from_selection()
	GameState.next_map_id = map_id
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID


func _case(entry: Array) -> void:
	var node_id: String = entry[1]
	var expected: String = entry[3]
	GameState.room_state = {}
	GameState.map_progress.current_node_id = node_id
	var node := GameState.get_current_node()
	node.encounter_id = entry[2]
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.1)
	var screen: Node = SceneRouter.current_screen
	var banner := screen.find_child("EliteBanner", true, false)
	if banner != null:
		banner.queue_free()
	var backdrop := str(screen._backdrop().get("asset_id", ""))
	check(backdrop == expected, "%s / %s fights on %s (got %s)" % [entry[0], node_id, expected, backdrop])
	var graph := GameState.map_progress.graph
	if node.terrain != "":
		var foes: Array = (graph.terrains.get(node.terrain, {}) as Dictionary).get("foes", [])
		var tailored := true
		for enemy: Combatant in screen.combat.enemies:
			tailored = tailored and foes.has(screen._battlefield._definition_id(enemy.id))
		check(tailored, "%s: every monster belongs to the %s" % [node_id, node.terrain])
	var tag := "%s_%s" % [entry[0].left(12), node_id]
	for window_size: Vector2i in SCREENS:
		get_window().size = window_size
		await _wait(0.35)
		_check_footing(screen, backdrop, "%s %dx%d" % [node_id, window_size.x, window_size.y])
		if window_size == SCREENS[0]:
			await _shot("terrain_" + tag)
		elif window_size == SCREENS[1] and entry == CASES[0] or window_size == SCREENS[1] and node_id in ["bone_clearing", "storm_front", "bat_roost"]:
			await _shot("terrain_%s_wide" % tag)
	get_window().size = SCREENS[0]
	await _wait(0.2)


## Lowest opaque row of a texture as a share of its height (cached per texture).
func _visible_bottom(texture: Texture2D) -> float:
	if texture == null:
		return 1.0
	var key := texture.get_rid().get_id()
	if _bottoms.has(key):
		return _bottoms[key]
	var image := texture.get_image()
	if image == null:
		return 1.0
	if image.is_compressed():
		image.decompress()
	var w := image.get_width()
	var h := image.get_height()
	var bottom := h
	for y in range(h - 1, -1, -1):
		var found := false
		for x in range(0, w, 3):
			if image.get_pixel(x, y).a > 0.35:
				found = true
				break
		if found:
			bottom = y + 1
			break
	_bottoms[key] = bottom / float(h)
	return _bottoms[key]


func _check_footing(screen: Node, backdrop: String, label: String) -> void:
	var floor := CombatPresentation.floor_info(backdrop)
	check(bool(floor["known"]), "%s: the floor of %s is measured" % [label, backdrop])
	var texture := AssetCatalog.texture(backdrop)
	var area: Vector2 = screen.get_viewport_rect().size
	var picture := RoomBackdrop.cover_rect(area, texture.get_size() if texture != null else area, float(floor["anchor_y"]), float(floor["zoom"]))
	var off_floor: Array[String] = []
	var floating: Array[String] = []
	var lowest_share := 0.0
	for view: CombatUnitView in screen._battlefield.all_views():
		if not view.visible:
			continue
		# The slot's floor: the bottom of the unit's box minus its info card. The sprite is drawn
		# in the art holder (sink included), so the visible feet are its lowest opaque row.
		var info := view.get_info_height()
		var slot_floor := view.global_position.y + view.size.y - info - (4.0 if info > 0.0 else 0.0)
		var art := view.get_art_rect()
		var feet := art.position.y + art.size.y * _visible_bottom(view._art.texture)
		var hovering := view.motion_profile_id() == "hover"
		# Hovering creatures cast their shadow on the slot floor; grounded ones stand on it.
		var contact := slot_floor if hovering else feet
		var share := (contact - picture.position.y) / picture.size.y
		lowest_share = maxf(lowest_share, share)
		if share < float(floor["top"]) + FLOOR_MARGIN or share > 0.995:
			off_floor.append("%s at %.3f" % [view.unit_id, share])
		if not hovering and feet < slot_floor - FLOAT_TOLERANCE:
			floating.append("%s (%d px)" % [view.unit_id, roundi(slot_floor - feet)])
	check(off_floor.is_empty(), "%s: every unit stands on the floor of %s (floor from %.2f)%s" % [label, backdrop, float(floor["top"]), "" if off_floor.is_empty() else ": " + ", ".join(off_floor)])
	check(floating.is_empty(), "%s: grounded units touch the ground%s" % [label, "" if floating.is_empty() else ": floating " + ", ".join(floating)])
