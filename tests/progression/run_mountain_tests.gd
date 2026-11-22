extends SceneTree
## Frostpeak, the standalone mountain adventure (main menu only): a climbing map (rooms rise from
## the foothills to the dragon's aerie, three altitude bands, a tall scrolling mountain picture and an
## altitude gauge), varied monsters (not all afraid of fire), the White Dragon, towns, shops, chests,
## events, Frostbitten and the mountain gear. Run:
##   godot --headless --path . --script res://tests/progression/run_mountain_tests.gd

const MAP_ID := "frostpeak"
const ENEMIES := ["mountain_frost_wolf", "mountain_polar_bear", "mountain_yeti", "mountain_crystal_spider", "mountain_rime_wraith",
	"mountain_ice_drake", "mountain_storm_roc", "elite_woolly_mammoth", "elite_crystal_matriarch", "elite_ice_giant", "boss_white_dragon"]
## Altitude bands from the bottom of the chart: pine slopes, glacier, summit.
const BANDS := ["slopes", "glacier", "summit"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_map()
	_test_climb_layout()
	_test_enemies()
	_test_terrain()
	_test_rooms()
	_test_frostbitten()
	_test_menu_and_art()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _party(chiara: String = "frost", bianca: String = "tanking") -> Party:
	return Party.from_selection({"chiara": chiara, "bianca": bianca})


func _combat(enemies: Array, party: Party = null, inventory: Inventory = null) -> CombatManager:
	var cm := CombatManager.new()
	cm.setup(party if party != null else _party(), {"id": "t", "name": "T", "enemies": enemies, "gold_reward": 0}, inventory if inventory != null else Inventory.new(), 3)
	cm.start()
	return cm


func _graph() -> MapGraph:
	return MapGraph.from_dict(DataRegistry.get_map(MAP_ID))


func _test_map() -> void:
	print("Frostpeak map")
	var graph := _graph()
	check(graph.validate().is_empty(), "the Frostpeak graph is valid (%s)" % ", ".join(graph.validate()))
	check(graph.battle_backdrop == "battle_dragon_aerie" and not graph.completion.is_empty(), "the boss fights in the dragon's aerie; the summit has completion text")
	var forest_size := MapGraph.from_dict(DataRegistry.get_map("enchanted_forest")).nodes.size()
	var coast_size := MapGraph.from_dict(DataRegistry.get_map("sunlit_coast")).nodes.size()
	check(graph.nodes.size() > maxi(forest_size, coast_size), "a little larger than the forest and the coast (%d rooms against %d and %d)" % [graph.nodes.size(), forest_size, coast_size])
	var counts: Dictionary = {}
	for node: MapNodeData in graph.nodes.values():
		counts[node.type] = int(counts.get(node.type, 0)) + 1
	check(int(counts.get("combat", 0)) >= 16 and int(counts.get("elite", 0)) == 4 and int(counts.get("boss", 0)) == 1, "16+ fights, 4 elites, 1 boss (%s)" % str(counts))
	check(int(counts.get("town", 0)) == 4 and int(counts.get("merchant", 0)) >= 1, "four villages and outposts, plus a trading post")
	for type in ["event", "treasure", "rest", "start", "exit"]:
		check(int(counts.get(type, 0)) >= 1, "it has %s rooms" % type)
	var reachable: Dictionary = {graph.start_node_id: true}
	var frontier: Array[String] = [graph.start_node_id]
	while not frontier.is_empty():
		var id: String = frontier.pop_back()
		for next_id: String in graph.get_node_data(id).next_ids:
			if not reachable.has(next_id):
				reachable[next_id] = true
				frontier.append(next_id)
	check(reachable.size() == graph.nodes.size(), "every room is reachable")
	var into_boss := 0
	var branching := 0
	for node: MapNodeData in graph.nodes.values():
		into_boss += 1 if node.next_ids.has("dragons_aerie") else 0
		branching += 1 if node.next_ids.size() >= 2 else 0
		if node.type != MapNodeData.TYPE_EXIT and node.next_ids.is_empty():
			check(false, "%s leads nowhere" % node.id)
	check(graph.get_node_data("dragons_aerie").next_ids == ["frostpeak_summit"] and into_boss == 3, "the White Dragon guards the summit; all three last rooms lead to her")
	check(branching >= 20, "the trail keeps branching (%d rooms with a choice)" % branching)
	var order: Array = RunRules.get_block("acts").get("order", [])
	check(not order.has(MAP_ID) and order.size() == 3, "Frostpeak is not part of the normal run (its summit ends the run)")


## The climb: every path leads upward, the trail narrows toward the peak, and the tall picture and
## the altitude gauge scroll with the chart.
func _test_climb_layout() -> void:
	print("The climb")
	var graph := _graph()
	var layout := MapLayout.for_map(MAP_ID)
	check(layout != null and layout.validate(graph).is_empty() and layout.canvas_height >= 3.5, "the layout is valid and scrolls over 3.5+ screens")
	check(layout.background_asset == "map_frostpeak" and layout.climb_asset == "map_frostpeak_climb", "a misty frame and a tall mountain picture that scrolls with the rooms")
	var uphill := true
	for node: MapNodeData in graph.nodes.values():
		for next_id in node.next_ids:
			uphill = uphill and (layout.nodes[next_id] as Vector2).y < (layout.nodes[node.id] as Vector2).y
	check(uphill, "every path climbs (each next room is higher on the chart)")
	var low_spread := _row_spread(layout, ["pine_trailhead", "snowed_shrine", "bear_hollow"])
	var high_spread := _row_spread(layout, ["storm_ledge", "last_cairn", "dragons_shadow"])
	check(high_spread < low_spread * 0.75, "the trail narrows toward the peak (%.2f wide at the foot, %.2f below the summit)" % [low_spread, high_spread])
	check(layout.altitude_at("frostpeak_foothills") == 1400 and layout.altitude_at("frostpeak_summit") == 6100, "the gauge reads 1,400 m at the foot and 6,100 m on the summit")
	var town_alt := layout.altitude_at("pinefall_village")
	var monastery_alt := layout.altitude_at("cloud_monastery")
	check(town_alt > 1400 and monastery_alt > town_alt and layout.altitude_at("dragons_aerie") > monastery_alt, "Pinefall %d m < Cloud Monastery %d m < the aerie %d m" % [town_alt, monastery_alt, layout.altitude_at("dragons_aerie")])
	check(MapView._thousands(6100) == "6,100" and MapView._thousands(950) == "950", "heights read with a thousands comma")
	check(MapLayout.for_map("sunlit_coast").climb_asset == "" and MapLayout.for_map("sunlit_coast").altitude_at("coast_exit") == -1, "other maps have no climb picture or gauge")


func _row_spread(layout: MapLayout, ids: Array) -> float:
	var xs: Array = ids.map(func(id: String) -> float: return (layout.nodes[id] as Vector2).x)
	return float(xs.max()) - float(xs.min())


func _test_enemies() -> void:
	print("Mountain monsters")
	for enemy_id in ENEMIES:
		var def := DataRegistry.get_enemy(enemy_id)
		check(def != null and DamageTypes.is_valid(def.element) and def.initiative >= 1 and not def.pattern.is_empty(), "%s exists with type, initiative and a pattern" % enemy_id)
		check(CombatPresentation.enemy_state(enemy_id, "idle") != null, "%s has a sprite" % enemy_id)
	var fire_weak := 0
	var fire_resistant := 0
	var elements: Dictionary = {}
	for enemy_id in ENEMIES:
		var def := DataRegistry.get_enemy(enemy_id)
		fire_weak += 1 if int(def.weaknesses.get("fire", 0)) > 0 else 0
		fire_resistant += 1 if int(def.resistances.get("fire", 0)) > 0 else 0
		elements[def.element] = true
	check(fire_weak <= 3 and fire_resistant >= 2, "not everything fears fire: %d of %d monsters are weak to it, %d resist it" % [fire_weak, ENEMIES.size(), fire_resistant])
	check(elements.size() >= 5, "five or more attack types (%s)" % ", ".join(elements.keys()))
	for element in ["fire", "frost", "arcane", "holy", "physical", "poison", "lightning"]:
		var found := ENEMIES.any(func(id: String) -> bool: return int(DataRegistry.get_enemy(id).weaknesses.get(element, 0)) > 0)
		check(found, "some mountain monster is weak to %s" % element)
	check(int(DataRegistry.get_enemy("mountain_crystal_spider").weaknesses.get("physical", 0)) == 50, "blades shatter the crystal spiders")
	check(int(DataRegistry.get_enemy("mountain_ice_drake").resistances.get("fire", 0)) > 0 and int(DataRegistry.get_enemy("mountain_ice_drake").weaknesses.get("lightning", 0)) == 50, "ice drakes shrug off fire but fear lightning")
	check(DataRegistry.get_enemy("elite_woolly_mammoth").elite and DataRegistry.get_enemy("elite_crystal_matriarch").elite and DataRegistry.get_enemy("elite_ice_giant").elite, "three elites")
	var dragon := DataRegistry.get_enemy("boss_white_dragon")
	check(dragon.boss and dragon.initiative > DataRegistry.get_status("chill").max_stacks and not dragon.enraged_pattern.is_empty() and dragon.max_hp >= 180, "the White Dragon: a 180+ HP boss that cannot be frozen and enrages")
	check(int(dragon.resistances.get("frost", 0)) >= 50 and int(dragon.weaknesses.get("arcane", 0)) > 0 and int(dragon.weaknesses.get("poison", 0)) > 0, "frost only half bites her; arcane and venom find the seams")
	for encounter_id: String in DataRegistry.encounters:
		if encounter_id.begins_with("mountain_") or encounter_id in ["elite_woolly_mammoth", "elite_crystal_matriarch", "elite_ice_giant", "boss_white_dragon"]:
			var enc := DataRegistry.get_encounter(encounter_id)
			var ok := not (enc.get("enemies", []) as Array).is_empty()
			for enemy_id: Variant in enc.get("enemies", []):
				ok = ok and DataRegistry.get_enemy(str(enemy_id)) != null
			check(ok and (enc.get("enemies", []) as Array).size() <= 3, "%s has 1-3 known enemies" % encounter_id)
	check(DataRegistry.get_encounter("boss_white_dragon").get("reward", {}).get("pool", "") == "epic", "the dragon rewards epic cards")
	# Fights get harder as the party climbs.
	var graph := _graph()
	var low_hp := _encounter_hp(graph, "pine_trailhead") + _encounter_hp(graph, "bear_hollow")
	var high_hp := _encounter_hp(graph, "storm_ledge") + _encounter_hp(graph, "dragons_shadow")
	check(high_hp > low_hp * 1.5, "summit fights are much tougher than the foothills (%d HP against %d)" % [high_hp, low_hp])


func _encounter_hp(graph: MapGraph, node_id: String) -> int:
	var total := 0
	for enemy_id: Variant in DataRegistry.get_encounter(graph.get_node_data(node_id).encounter_id).get("enemies", []):
		total += DataRegistry.get_enemy(str(enemy_id)).max_hp
	return total


func _test_terrain() -> void:
	print("Altitude bands")
	var graph := _graph()
	var layout := MapLayout.for_map(MAP_ID)
	var band_y: Dictionary = {}
	var foes_ok := true
	for node: MapNodeData in graph.nodes.values():
		if node.terrain == "":
			check(node.type in [MapNodeData.TYPE_START, MapNodeData.TYPE_BOSS, MapNodeData.TYPE_EXIT], "%s: only start, boss and exit have no band" % node.id)
			continue
		check(BANDS.has(node.terrain), "%s is on a known band (%s)" % [node.id, node.terrain])
		var ys: Array = band_y.get(node.terrain, [])
		ys.append((layout.nodes[node.id] as Vector2).y)
		band_y[node.terrain] = ys
		if node.encounter_id != "":
			var enc := DataRegistry.get_encounter(node.encounter_id)
			var allowed: Array = graph.terrains[node.terrain].get("foes", [])
			for enemy_id: Variant in enc.get("enemies", []):
				if not allowed.has(str(enemy_id)):
					foes_ok = false
					print("    %s (%s) has %s" % [node.id, node.terrain, enemy_id])
			foes_ok = foes_ok and str(enc.get("terrain", "")) == node.terrain
		if node.type == MapNodeData.TYPE_EVENT:
			check(node.event_pool == "mountain_" + node.terrain and not EventResolver.pool_event_ids(node.event_pool).is_empty(), "%s rolls %s events" % [node.id, node.event_pool])
	check(foes_ok, "each band has its own monsters (wolves and bears below, crystal and drakes on the ice, rocs and giants on top)")
	check(float((band_y["slopes"] as Array).min()) > float((band_y["glacier"] as Array).max()) and float((band_y["glacier"] as Array).min()) > float((band_y["summit"] as Array).max()),
		"the bands stack: slopes at the foot, the glacier above, the summit on top")
	for band in BANDS:
		var backdrop := graph.terrain_backdrop(graph.get_node_data(_first_room(graph, band)))
		check(backdrop == "battle_mountain_" + band, "%s rooms fight on battle_mountain_%s" % [band, band])
	check(str(AssetCatalog.room_backdrop("frostpeak_foothills", "start", MAP_ID)["asset_id"]) == "battle_mountain_slopes", "the foothills show the pine slopes, not a castle")


func _first_room(graph: MapGraph, band: String) -> String:
	for node: MapNodeData in graph.nodes.values():
		if node.terrain == band:
			return node.id
	return ""


func _test_rooms() -> void:
	print("Villages, outposts, chests and events")
	var graph := _graph()
	for node: MapNodeData in graph.nodes.values():
		match node.type:
			MapNodeData.TYPE_COMBAT, MapNodeData.TYPE_ELITE, MapNodeData.TYPE_BOSS:
				check(not DataRegistry.get_encounter(node.encounter_id).is_empty(), "%s: encounter %s exists" % [node.id, node.encounter_id])
			MapNodeData.TYPE_TOWN:
				var town := DataRegistry.get_town(node.town_id)
				check(not town.is_empty() and (not (town.get("services", []) as Array).has("merchant") or not DataRegistry.get_shop(str(town.get("shop_id", ""))).is_empty()), "%s: town and its shop exist" % node.id)
			MapNodeData.TYPE_MERCHANT:
				check(not DataRegistry.get_shop(node.shop_id).is_empty(), "%s: shop exists" % node.id)
			MapNodeData.TYPE_TREASURE:
				var state := TreasureRoom.generate(node.treasure_id, _party(), Inventory.new(), RandomNumberGenerator.new())
				check((state["choices"] as Array).size() == 5, "%s: five chest choices incl. equipment" % node.id)
	var mountain_events := 0
	for event_id: String in DataRegistry.events:
		var event := DataRegistry.get_event(event_id)
		if (event.get("pools", []) as Array).has("mountain"):
			mountain_events += 1
			for choice: Dictionary in event["choices"]:
				for effect: Dictionary in choice["effects"]:
					if str(effect["type"]) == "start_combat":
						check(not DataRegistry.get_encounter(str(effect["encounter_id"])).is_empty(), "%s starts a known fight" % event_id)
	check(mountain_events >= 8, "eight or more mountain events (%d)" % mountain_events)
	var inventory := Inventory.new()
	var party := _party()
	var lodge: Dictionary = (DataRegistry.get_event("mountain_hunters_lodge")["choices"] as Array)[2]
	inventory.gold = 100
	EventResolver.apply(lodge["effects"], party, inventory)
	check(inventory.equipment == ["yetifur_mantle"] and inventory.gold == 40, "the hunters sell a Yeti-Fur Mantle for 60 gold")
	var shop := Merchant.from_definition(DataRegistry.get_shop("mountain_trading_post"))
	inventory.gold = 500
	check(shop.buy("glacier_plate", inventory) == "" and inventory.equipment.has("glacier_plate"), "the trading post sells Glacier Plate into the stash")


func _test_frostbitten() -> void:
	print("Frostbitten")
	var status := DataRegistry.get_status("frostbitten")
	check(status != null and status.vulnerable_elements == ["frost"] and status.vulnerable_per_stack == 15 and status.max_stacks == 3, "Frostbitten: +15% frost per stack, max 3")
	var cm := _combat(["mountain_yeti"])
	var bianca := cm.get_combatant("bianca")
	bianca.add_status("frostbitten", 2, "x")
	var hp := bianca.hp
	cm.hit(bianca, 10, "frost", cm.enemies[0])
	check(hp - bianca.hp == 13, "a Frostbitten 2 princess takes 10 frost as 13 (lost %d)" % (hp - bianca.hp))
	hp = bianca.hp
	cm.hit(bianca, 10, "physical", cm.enemies[0])
	check(hp - bianca.hp == 10, "other types are unaffected")
	var yeti := cm.enemies[0]
	check(yeti.intent.action_id == "snowball_barrage" and yeti.intent.hits_all and yeti.intent.status_id == "frostbitten", "the yeti opens with a Snowball Barrage on the whole party")
	cm.end_player_turn()
	check(cm.party_combatants.all(func(c: Combatant) -> bool: return c.has_status("frostbitten")), "both princesses are Frostbitten")
	# The Yeti-Fur Mantle keeps the cold out.
	var party := _party()
	var inventory := Inventory.new()
	inventory.add_equipment("yetifur_mantle")
	Equipment.equip(party.get_member("bianca"), inventory, "yetifur_mantle")
	var cm2 := _combat(["mountain_yeti"], party, inventory)
	cm2.get_combatant("bianca").add_status("frostbitten", 2, "x")
	check(not cm2.get_combatant("bianca").has_status("frostbitten") and int(cm2.get_combatant("bianca").affinity.get("frost", 0)) == -15, "the Yeti-Fur Mantle: never Frostbitten, 15% frost resistance")
	for item_id in ["yetifur_mantle", "glacier_plate"]:
		check(Equipment.is_equipment(item_id) and Equipment.stat_lines(item_id).size() >= 1, "%s is equipment with stat lines" % item_id)
	check(CombatUnitView.STATUS_STYLE.has("frostbitten"), "Frostbitten has its status chip style")


func _test_menu_and_art() -> void:
	print("Main menu and art")
	var menu: Script = load("res://scripts/ui/screens/main_menu.gd")
	var starts: Array = menu.get_script_constant_map().get("ACT_STARTS", [])
	check(starts.any(func(s: Dictionary) -> bool: return s["map_id"] == MAP_ID and s["button"] == "ActFrostpeakButton"), "the main menu has a Frostpeak button")
	var art_ids := ["map_frostpeak", "map_frostpeak_climb", "battle_mountain_slopes", "battle_mountain_glacier", "battle_mountain_summit", "battle_dragon_aerie",
		"town_pinefall_village", "town_ropebridge_outpost", "town_cloud_monastery", "town_last_cairn", "merchant_mountain_furrier", "merchant_mountain_monk"]
	for art_id in art_ids:
		check(AssetCatalog.texture(art_id) != null, "%s is in the art catalog with its picture" % art_id)
	for town_id in ["pinefall_village", "ropebridge_outpost", "cloud_monastery", "last_cairn"]:
		check(AssetCatalog.texture(str(DataRegistry.get_town(town_id).get("art", ""))) != null, "%s has its scene" % town_id)
	for backdrop in ["battle_mountain_slopes", "battle_mountain_glacier", "battle_mountain_summit", "battle_dragon_aerie"]:
		var floor: Dictionary = CombatPresentation.floor_info(backdrop)
		check(float(floor.get("top", 1.0)) <= 0.585, "%s: its floor starts high enough for the units" % backdrop)
