extends SceneTree
## Milestone 4 art-integration tests: art catalog integrity, graceful fallbacks and component
## construction for every card / character / specialization. Run:
##   godot --headless --path . --script res://tests/art/run_art_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	AssetCatalog.reload()
	_test_catalog()
	_test_content_coverage()
	_test_components()
	_test_missing_assets()
	_test_town_and_merchant_art()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Every town (data/towns) and every merchant (data/shops) has its own illustration.
func _test_town_and_merchant_art() -> void:
	print("Town and merchant art")
	for folder in ["res://data/towns", "res://data/shops"]:
		var missing: Array[String] = []
		var total := 0
		for file_name in DirAccess.get_files_at(folder):
			if not file_name.ends_with(".json"):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "/" + file_name))
			for entry: Dictionary in (parsed if parsed is Array else [parsed]):
				total += 1
				var art := str(entry.get("art", ""))
				if art == "" or AssetCatalog.texture(art) == null:
					missing.append(str(entry.get("id", "?")))
		check(total > 0 and missing.is_empty(), "%s: all %d have an illustration (missing: %s)" % [folder.get_file(), total, ", ".join(missing)])


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _test_catalog() -> void:
	print("Art catalog")
	var ids := AssetCatalog.asset_ids()
	check(ids.size() >= 30, "catalog lists its assets (%d)" % ids.size())
	var all_load := true
	var in_bounds := true
	for id in ids:
		var texture := AssetCatalog.texture(id)
		all_load = all_load and texture != null
		var entry := AssetCatalog.get_entry(id)
		if texture is AtlasTexture:
			var atlas := texture as AtlasTexture
			var board_size := atlas.atlas.get_size()
			in_bounds = in_bounds and atlas.region.position.x >= 0 and atlas.region.position.y >= 0 \
				and atlas.region.end.x <= board_size.x and atlas.region.end.y <= board_size.y
		if str(entry.get("status", "")) == "":
			all_load = false
	check(all_load, "every catalog entry resolves to a texture and declares a status")
	check(in_bounds, "every crop region lies inside its source image")
	check(AssetCatalog.texture("no_such_asset") == null and AssetCatalog.texture("") == null, "unknown ids return null, not an error")
	check(AssetCatalog.release_blockers().size() == ids.size(), "no asset is marked release-cleared (rights unverified)")
	var originals_untouched := FileAccess.get_sha256("res://assets/concept/voidfarer_detailed_asset_board.png") == FileAccess.get_sha256("res://assets_pack/visuals/voidfarer_detailed_asset_board.png")
	check(originals_untouched, "assets_pack concept board is byte-identical to the project copy")


func _test_content_coverage() -> void:
	print("Content coverage")
	var chars_ok := true
	for character_id in GameConfig.INITIAL_PARTY_IDS:
		chars_ok = chars_ok and AssetCatalog.portrait(character_id) != null and AssetCatalog.figure(character_id) != null \
			and AssetCatalog.portrait_face(character_id) != null
	check(chars_ok, "Chiara and Bianca have portrait, face crop and figure art")
	var face := AssetCatalog.portrait_face("chiara") as AtlasTexture
	check(face != null and face.region.size.x == face.region.size.y, "face crop is square")

	var map := DataRegistry.get_map(GameConfig.DEFAULT_MAP_ID)
	var rooms_ok := true
	var distinct: Dictionary = {}
	for node: Dictionary in map["nodes"]:
		var info := AssetCatalog.room_backdrop(str(node["id"]), str(node["type"]))
		rooms_ok = rooms_ok and info["texture"] != null
		distinct[str(info["asset_id"])] = true
	check(rooms_ok, "all %d Royal Castle rooms resolve a backdrop" % map["nodes"].size())
	check(distinct.size() >= 5, "backdrops cover at least five distinct artworks (%d)" % distinct.size())

	var layout := MapLayout.for_map(GameConfig.DEFAULT_MAP_ID)
	check(layout != null and layout.get_background() != null and layout.validate(MapGraph.from_dict(map)).is_empty(), "Royal Castle background and a valid layout exist for every node")

	var icons_ok := true
	for icon_name in ["health", "block", "energy", "burn", "gold", "potion", "rest", "merchant", "event", "combat", "exit"]:
		icons_ok = icons_ok and AssetCatalog.icon(icon_name) != null
	check(icons_ok, "all required UI icons resolve")

	var visual_ok := true
	for spec_id in ["arcana", "fire", "tanking", "holy"]:
		var spec := DataRegistry.get_specialization(spec_id)
		visual_ok = visual_ok and spec.accent_color.a > 0.0 and AssetCatalog.icon_by_id(spec.icon_id) != null
	check(visual_ok, "Arcana, Fire, Tanking and Holy define accent colour and icon in data")
	var accents: Dictionary = {}
	for spec_id in ["arcana", "fire", "tanking", "holy"]:
		accents[DataRegistry.get_specialization(spec_id).accent_color.to_html()] = true
	check(accents.size() == 4, "the four specializations have distinct accent colours")
	check(DataRegistry.get_specialization("earth").accent_color.a == 0.0 and DataRegistry.get_specialization("earth").get_accent(Color.RED) == Color.RED, "specializations without visual data fall back to the character colour")

	var with_art := 0
	for card: CardDef in DataRegistry.cards.values():
		if AssetCatalog.card_art_id(card.id, card.specialization_id, card.card_type) != "" and AssetCatalog.texture(AssetCatalog.card_art_id(card.id, card.specialization_id, card.card_type)) != null:
			with_art += 1
	check(with_art == DataRegistry.cards.size(), "all %d cards resolve catalog art (thematic reuse)" % DataRegistry.cards.size())


func _test_components() -> void:
	print("Components")
	var built := 0
	var all_ok := true
	for card: CardDef in DataRegistry.cards.values():
		var view := CardView.new()
		view.show_owned(card, card.owner_character_id, 0)
		view.set_scale_factor(1.35)
		var upgraded := CardView.new()
		upgraded.show_owned(card, card.owner_character_id, 1)
		all_ok = all_ok and view.get_child_count() > 0 and upgraded.get_child_count() > 0 and view.custom_minimum_size.x > CardView.CARD_SIZE.x
		built += 1
		view.free()
		upgraded.free()
	check(all_ok and built == DataRegistry.cards.size(), "CardView builds (normal, scaled, upgraded) for all %d cards" % built)

	var card_view := CardView.new()
	card_view.show_owned(DataRegistry.get_card("chiara_fire_ember"), "chiara", 1)
	check(card_view.owner_id == "chiara" and card_view._upgraded and card_view.definition.rarity != "", "card view keeps owner, upgrade state and rarity")
	var pressed: Array[int] = [0]
	card_view.pressed.connect(func(_v: CardView) -> void: pressed[0] += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card_view._gui_input(click)
	check(pressed[0] == 1, "card view still emits pressed on click/tap")
	card_view.free()

	var portraits_ok := true
	for character_id in GameConfig.INITIAL_PARTY_IDS:
		var char_def := DataRegistry.get_character(character_id)
		for spec in DataRegistry.get_specializations_for(character_id):
			for use_figure in [false, true]:
				var portrait := PortraitView.new()
				portrait.setup(char_def, spec, Vector2(100, 100), use_figure)
				portraits_ok = portraits_ok and portrait.get_child_count() > 0
				portrait.free()
	check(portraits_ok, "PortraitView builds for every character x specialization (face and figure)")

	var panel := CharacterPanel.new()
	panel.setup(DataRegistry.get_character("bianca"), {"specialization": DataRegistry.get_specialization("holy"), "hp": 50, "max_hp": 80, "block": 4, "slim": true, "live_text": "Blessed Aegis: ready"})
	check(panel.get_child_count() > 0, "combat CharacterPanel builds with passive text, block and spec art")
	panel.free()

	var combatant := Combatant.new()
	combatant.id = "dummy"
	combatant.display_name = "Dummy"
	combatant.max_hp = 10
	combatant.hp = 10
	combatant.statuses["burn"] = {"stacks": 2, "source_id": "chiara"}
	var enemy_panel := EnemyPanel.new()
	enemy_panel.setup(combatant, "Strike: 5 dmg", false)
	check(enemy_panel.get_child_count() > 0, "EnemyPanel builds with Burn status and intent")
	enemy_panel.free()


func _test_missing_assets() -> void:
	print("Missing assets")
	# Simulate a build where the art catalog and files are gone.
	AssetCatalog._data = {}
	AssetCatalog._cache.clear()
	AssetCatalog._loaded = true
	check(AssetCatalog.icon("health") == null and AssetCatalog.portrait("chiara") == null, "empty catalog returns null for icons and portraits")
	check(AssetCatalog.room_backdrop("royal_chambers", "start")["texture"] == null, "empty catalog returns a texture-less backdrop")
	var backdrop := RoomBackdrop.new()
	backdrop.setup(AssetCatalog.room_backdrop("royal_chambers", "start"))
	check(backdrop.get_child_count() >= 1, "RoomBackdrop falls back to the plain gradient")
	backdrop.free()
	var card_view := CardView.new()
	card_view.show_owned(DataRegistry.get_card("bianca_holy_smite"), "bianca", 0)
	check(card_view.get_child_count() > 0, "CardView renders a themed fallback without any art")
	card_view.free()
	var portrait := PortraitView.new()
	portrait.setup(DataRegistry.get_character("chiara"), DataRegistry.get_specialization("fire"), Vector2(80, 80))
	check(portrait.get_child_count() > 0, "PortraitView renders an initial tile without art")
	portrait.free()
	var icon := UIFactory.icon("burn", 20)
	check(icon is Label, "missing icon becomes a glyph placeholder of the requested size")
	icon.free()
	AssetCatalog.reload()
	check(AssetCatalog.icon("health") != null, "catalog reloads normally afterwards")
