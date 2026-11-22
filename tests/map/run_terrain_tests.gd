extends SceneTree
## Terrains on every map: each terrain has a backdrop with a measured floor and lighting; every
## fight room has a terrain whose monsters it uses; the forest's terrains follow the columns of its
## fixed picture; the new monsters have sprites; room screens never fall back to castle rooms
## outside the castle. Run:
##   godot --headless --path . --script res://tests/map/run_terrain_tests.gd

## The battlefield's feet line as a share of the screen height (measured in the windowed test:
## 445 of 720 px). The windowed terrain test checks every sprite's actual feet.
const FEET_LINE := 0.615
## 16:9, landscape phone (1558x720 virtual) and ultrawide (1706x720 virtual).
const SCREENS := [Vector2(1280, 720), Vector2(1558, 720), Vector2(1706, 720)]
const MAPS := ["royal_castle_tutorial", "castle_elite_demo", "enchanted_forest", "crystal_hollow_demo", "sunlit_coast"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	for map_id in MAPS:
		_test_map(map_id)
	_test_forest_columns()
	_test_new_monsters()
	_test_room_pictures()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _test_map(map_id: String) -> void:
	print(map_id)
	var graph := MapGraph.from_dict(DataRegistry.get_map(map_id))
	check(not graph.terrains.is_empty(), "%s has terrains (%s)" % [map_id, ", ".join(graph.terrains.keys())])
	var backdrops: Array[String] = [graph.battle_backdrop if graph.battle_backdrop != "" else "battle_castle_generic"]
	for terrain_id: String in graph.terrains:
		var terrain: Dictionary = graph.terrains[terrain_id]
		check(str(terrain.get("hint", "")) != "" and not (terrain.get("foes", []) as Array).is_empty(), "%s: %s has a map hint and a monster list" % [map_id, terrain_id])
		for foe: Variant in terrain.get("foes", []):
			check(DataRegistry.get_enemy(str(foe)) != null, "%s: %s foe %s exists" % [map_id, terrain_id, foe])
		if graph.terrain_backdrops.has(terrain_id):
			backdrops.append(str(graph.terrain_backdrops[terrain_id]))
	for backdrop in backdrops:
		var floor := CombatPresentation.floor_info(backdrop)
		var texture := AssetCatalog.texture(backdrop)
		check(texture != null, "%s: backdrop %s loads" % [map_id, backdrop])
		# Where the feet line lands on the picture, on 16:9 and on the widest screen, with the
		# backdrop's crop anchor and zoom: it must be on the floor with a little margin.
		var lowest_ok := true
		var shares: Array[String] = []
		for area: Vector2 in SCREENS:
			var rect := RoomBackdrop.cover_rect(area, texture.get_size() if texture != null else area, float(floor["anchor_y"]), float(floor["zoom"]))
			var share := (area.y * FEET_LINE - rect.position.y) / rect.size.y
			shares.append("%.3f" % share)
			lowest_ok = lowest_ok and share >= float(floor["top"]) + 0.07
		check(bool(floor["known"]) and lowest_ok, "%s: %s floor starts at %.3f; the feet line lands at %s" % [map_id, backdrop, float(floor["top"]), ", ".join(shares)])
		check(CombatPresentation.lighting(backdrop) != CombatPresentation.lighting("__none__") or backdrop == "battle_castle_generic", "%s: %s has its own lighting" % [map_id, backdrop])
	var fights_per_terrain: Dictionary = {}
	for node: MapNodeData in graph.nodes.values():
		if node.encounter_id == "":
			continue
		var encounter := DataRegistry.get_encounter(node.encounter_id)
		if node.type == MapNodeData.TYPE_BOSS:
			check(node.terrain == "" or graph.terrains.has(node.terrain), "%s: the boss room keeps its own arena" % map_id)
			continue
		check(graph.terrains.has(node.terrain), "%s: %s has a known terrain (%s)" % [map_id, node.id, node.terrain])
		check(str(encounter.get("terrain", "")) == node.terrain, "%s: %s's encounter %s is tagged %s" % [map_id, node.id, node.encounter_id, node.terrain])
		var foes: Array = (graph.terrains.get(node.terrain, {}) as Dictionary).get("foes", [])
		var strangers: Array[String] = []
		for enemy_id: Variant in encounter.get("enemies", []):
			if not foes.has(str(enemy_id)):
				strangers.append(str(enemy_id))
		check(strangers.is_empty(), "%s: %s (%s) only has %s monsters%s" % [map_id, node.id, node.encounter_id, node.terrain, "" if strangers.is_empty() else ", not " + ", ".join(strangers)])
		fights_per_terrain[node.terrain] = int(fights_per_terrain.get(node.terrain, 0)) + 1
	for terrain_id: String in graph.terrains:
		check(int(fights_per_terrain.get(terrain_id, 0)) >= 1, "%s: the %s has fights (%d)" % [map_id, terrain_id, int(fights_per_terrain.get(terrain_id, 0))])


func _test_forest_columns() -> void:
	print("Forest columns")
	var graph := MapGraph.from_dict(DataRegistry.get_map("enchanted_forest"))
	var layout := MapLayout.for_map("enchanted_forest")
	var ok := true
	var names_ok := true
	for node: MapNodeData in graph.nodes.values():
		if node.terrain == "":
			continue
		var x: float = layout.nodes[node.id].x
		var expected := "mountain" if x < 0.2 else ("falls" if x > 0.8 else "deepwood")
		if node.terrain != expected:
			ok = false
			print("    %s at x=%.2f is %s, expected %s" % [node.id, x, node.terrain, expected])
		if node.terrain == "mountain" and (node.display_name.contains("Spider") or node.display_name.contains("Venom") or node.display_name.contains("Web")):
			names_ok = false
	check(ok, "mountain rooms on the left (mountains of the picture), deep wood in the middle (giant trees), falls on the right (waterfalls)")
	check(names_ok, "mountain rooms are not named after spiders or marshes any more")
	check(graph.get_node_data("webbed_hollow").display_name == "Harpy Roost" and graph.get_node_data("venom_marsh").display_name == "Eagle Crag", "renamed: Harpy Roost, Eagle Crag")


func _test_new_monsters() -> void:
	print("New monsters")
	for enemy_id in ["forest_cliff_harpy", "forest_wisp"]:
		var def := DataRegistry.get_enemy(enemy_id)
		check(def != null and not def.pattern.is_empty() and CombatPresentation.enemy_state(enemy_id, "idle") != null, "%s exists with a pattern and a sprite" % enemy_id)
		check(CombatPresentation.enemy_motion(enemy_id).get("id", "") == "hover", "%s hovers" % enemy_id)
	check(int(DataRegistry.get_enemy("forest_wisp").weaknesses.get("holy", 0)) == 50 and DataRegistry.get_enemy("forest_cliff_harpy").element == "wind", "the wisp fears light; the harpy strikes with wind")


func _test_room_pictures() -> void:
	print("Room pictures")
	check(str(AssetCatalog.room_backdrop("echo_pool", "event", "crystal_hollow_demo")["asset_id"]) == "battle_crystal_hollow", "Crystal Hollow rooms show the cave, not a castle room")
	var castle := MapGraph.from_dict(DataRegistry.get_map("royal_castle_tutorial"))
	check(castle.terrain_backdrop(castle.get_node_data("royal_library")) == "", "castle rooms outside the fights keep their own pictures")
