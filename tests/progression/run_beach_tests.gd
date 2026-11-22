extends SceneTree
## Act III, the Sunlit Coast: map graph and layout, enemies (types, weaknesses, initiative), encounters,
## towns, shops, chests and events, the water and earth statuses (Soaked, Sandblind, Quicksand),
## equipment immunities, shop equipment and attack effects. Run:
##   godot --headless --path . --script res://tests/progression/run_beach_tests.gd

const MAP_ID := "sunlit_coast"
const ENEMIES := ["beach_giant_crab", "beach_dire_albatross", "beach_triton_soldier", "beach_rock_spider",
	"beach_shark_knight", "beach_sand_scorpion", "elite_sand_giant", "elite_rock_giant", "elite_sea_snake", "boss_sandstorm_elemental"]
## Which monsters belong to which terrain: the shore has beach and rock creatures, the open sea
## has marine and sky ones.
const SHORE_FOES := ["beach_giant_crab", "beach_rock_spider", "beach_sand_scorpion", "elite_sand_giant", "elite_rock_giant"]
const SEA_FOES := ["beach_triton_soldier", "beach_dire_albatross", "beach_shark_knight", "elite_sea_snake"]
## Map column on the fixed picture: the middle is open sea, the sides are beach (left) and rocky shore (right).
const SEA_COLUMN := Vector2(0.4, 0.6)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_map()
	_test_enemies()
	_test_rooms()
	_test_terrain()
	_test_soaked()
	_test_sandblind()
	_test_quicksand()
	_test_immunity_and_items()
	_test_effects_and_acts()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _party(chiara: String = "frost", bianca: String = "tanking") -> Party:
	return Party.from_selection({"chiara": chiara, "bianca": bianca})


func _combat(enemies: Array, party: Party = null, seed_value: int = 3) -> CombatManager:
	var cm := CombatManager.new()
	cm.setup(party if party != null else _party(), {"id": "t", "name": "T", "enemies": enemies, "gold_reward": 0}, Inventory.new(), seed_value)
	cm.start()
	return cm


func _test_map() -> void:
	print("Sunlit Coast map")
	var graph := MapGraph.from_dict(DataRegistry.get_map(MAP_ID))
	check(graph.validate().is_empty(), "the coast graph is valid (%s)" % ", ".join(graph.validate()))
	check(graph.act == 3 and graph.battle_backdrop == "battle_beach" and not graph.completion.is_empty(), "act 3, beach backdrop and completion text")
	var counts: Dictionary = {}
	for node: MapNodeData in graph.nodes.values():
		counts[node.type] = int(counts.get(node.type, 0)) + 1
	check(graph.nodes.size() >= 35, "a full act: %d rooms" % graph.nodes.size())
	check(int(counts.get("combat", 0)) >= 12 and int(counts.get("elite", 0)) == 4 and int(counts.get("boss", 0)) == 1, "12+ fights, 4 elites, 1 boss (%s)" % str(counts))
	for type in ["event", "town", "treasure", "rest", "merchant", "start", "exit"]:
		check(int(counts.get(type, 0)) >= 1, "it has %s rooms" % type)
	# Every room is reachable from the start and every path ends at the exit through the boss.
	var reachable: Dictionary = {graph.start_node_id: true}
	var frontier: Array[String] = [graph.start_node_id]
	while not frontier.is_empty():
		var id: String = frontier.pop_back()
		for next_id: String in graph.get_node_data(id).next_ids:
			if not reachable.has(next_id):
				reachable[next_id] = true
				frontier.append(next_id)
	check(reachable.size() == graph.nodes.size(), "every room is reachable")
	var boss := graph.get_node_data("eye_of_the_storm")
	check(boss != null and boss.next_ids == ["coast_exit"], "the boss guards the exit")
	var into_boss := 0
	for node: MapNodeData in graph.nodes.values():
		if node.next_ids.has("eye_of_the_storm"):
			into_boss += 1
		if node.type != MapNodeData.TYPE_EXIT and node.next_ids.is_empty():
			check(false, "%s leads nowhere" % node.id)
	check(into_boss == 3, "all three last rooms lead to the boss")
	var layout := MapLayout.for_map(MAP_ID)
	check(layout != null and layout.background_asset == "map_sunlit_coast" and layout.canvas_height > 1.5 and layout.validate(graph).is_empty(), "the layout uses the coast picture, scrolls and is valid")
	var inside := true
	for node_id: String in graph.nodes:
		var pos: Vector2 = layout.nodes.get(node_id, Vector2(-1, -1)) if layout != null else Vector2(-1, -1)
		inside = inside and pos.x > 0.05 and pos.x < 0.95 and pos.y > 0.0 and pos.y < 1.0
	check(inside, "every room has a position on the chart")


func _test_enemies() -> void:
	print("Coast enemies")
	for enemy_id in ENEMIES:
		var def := DataRegistry.get_enemy(enemy_id)
		check(def != null and DamageTypes.is_valid(def.element) and def.initiative >= 1 and not def.pattern.is_empty(), "%s exists with type, initiative and a pattern" % enemy_id)
		check(CombatPresentation.enemy_state(enemy_id, "idle") != null, "%s has a sprite" % enemy_id)
	check(DataRegistry.get_enemy("beach_triton_soldier").element == "water" and DataRegistry.get_enemy("beach_rock_spider").element == "earth", "tritons strike with water, rock spiders with earth")
	check(DataRegistry.get_enemy("elite_sand_giant").elite and DataRegistry.get_enemy("elite_rock_giant").elite and DataRegistry.get_enemy("elite_sea_snake").elite, "three elites")
	var boss := DataRegistry.get_enemy("boss_sandstorm_elemental")
	check(boss.boss and boss.initiative > DataRegistry.get_status("chill").max_stacks and not boss.enraged_pattern.is_empty(), "the Sandstorm Elemental: a boss that cannot be frozen and enrages")
	check(int(boss.resistances.get("physical", 0)) == 25 and int(boss.resistances.get("holy", 0)) == 25 and int(boss.weaknesses.get("frost", 0)) == 50, "it resists blades and light but fears frost")
	check(int(DataRegistry.get_enemy("elite_rock_giant").weaknesses.get("arcane", 0)) == 50, "arcane cracks the Rock Giant")
	check(int(DataRegistry.get_enemy("elite_sea_snake").weaknesses.get("lightning", 0)) == 50, "the Sea Snake fears lightning")
	var every_spec_has_a_target := true
	for element in ["fire", "frost", "arcane", "holy", "physical"]:
		var weak_found := false
		for enemy_id in ENEMIES:
			weak_found = weak_found or int(DataRegistry.get_enemy(enemy_id).weaknesses.get(element, 0)) > 0
		every_spec_has_a_target = every_spec_has_a_target and (weak_found or element == "fire")
	check(every_spec_has_a_target, "frost, arcane, holy and physical each find a weak coast enemy (fire does not: the coast is wet)")
	for encounter_id: String in DataRegistry.encounters:
		if encounter_id.begins_with("beach_") or encounter_id in ["elite_sea_snake", "elite_rock_giant", "elite_sand_giant", "boss_sandstorm_elemental"]:
			var enc := DataRegistry.get_encounter(encounter_id)
			var ok := not (enc.get("enemies", []) as Array).is_empty()
			for enemy_id: Variant in enc.get("enemies", []):
				ok = ok and DataRegistry.get_enemy(str(enemy_id)) != null
			check(ok and (enc.get("enemies", []) as Array).size() <= 3, "%s has 1-3 known enemies" % encounter_id)
	check(DataRegistry.get_encounter("boss_sandstorm_elemental").get("reward", {}).get("pool", "") == "epic", "the boss rewards epic cards")


func _test_terrain() -> void:
	print("Sea and shore")
	var graph := MapGraph.from_dict(DataRegistry.get_map(MAP_ID))
	var layout := MapLayout.for_map(MAP_ID)
	check(graph.terrain_backdrops.get("sea", "") == "battle_ship_deck" and AssetCatalog.texture("battle_ship_deck") != null, "sea rooms have the ship-deck picture")
	var sea_rooms := 0
	var sea_fights := 0
	var placement_ok := true
	var foes_ok := true
	for node: MapNodeData in graph.nodes.values():
		if node.terrain == "":
			check(node.type in [MapNodeData.TYPE_START, MapNodeData.TYPE_BOSS, MapNodeData.TYPE_EXIT], "%s: only start, boss and exit have no terrain" % node.id)
			continue
		var x: float = layout.nodes[node.id].x
		var in_sea_column := x >= SEA_COLUMN.x and x <= SEA_COLUMN.y
		placement_ok = placement_ok and (node.terrain == "sea") == in_sea_column
		if node.terrain == "sea":
			sea_rooms += 1
		if node.encounter_id == "":
			continue
		var allowed: Array = SEA_FOES if node.terrain == "sea" else SHORE_FOES
		var enc := DataRegistry.get_encounter(node.encounter_id)
		for enemy_id: Variant in enc.get("enemies", []):
			if not allowed.has(str(enemy_id)):
				foes_ok = false
				print("    %s (%s) has %s" % [node.id, node.terrain, enemy_id])
		foes_ok = foes_ok and str(enc.get("terrain", "")) == node.terrain
		if node.terrain == "sea":
			sea_fights += 1
	check(placement_ok, "every room in the middle of the picture is at sea, every room on the sides on the shore")
	check(sea_rooms >= 10 and sea_fights >= 5, "a full sea column: %d rooms, %d fights (incl. an elite)" % [sea_rooms, sea_fights])
	check(foes_ok, "sea fights only have marine and sky foes, shore fights only beach and rock foes")
	check(graph.get_node_data("sandy_ridge").encounter_id == "elite_sea_snake" and graph.get_node_data("sandy_ridge").terrain == "sea", "the Sea Snake is fought at sea (Serpent Deep)")
	var shark_rooms := 0
	for node: MapNodeData in graph.nodes.values():
		if node.encounter_id != "" and (DataRegistry.get_encounter(node.encounter_id).get("enemies", []) as Array).has("beach_shark_knight"):
			shark_rooms += 1
	check(shark_rooms >= 2, "the Shark Knight appears in %d sea fights" % shark_rooms)
	var scorpion_rooms := 0
	var shore_kinds: Dictionary = {}
	for node: MapNodeData in graph.nodes.values():
		if node.terrain == "shore" and node.type == MapNodeData.TYPE_COMBAT:
			var foes: Array = DataRegistry.get_encounter(node.encounter_id).get("enemies", [])
			for enemy_id: Variant in foes:
				shore_kinds[str(enemy_id)] = true
			if foes.has("beach_sand_scorpion"):
				scorpion_rooms += 1
	check(shore_kinds.size() == 3 and scorpion_rooms >= 3, "shore fights mix three monsters (%s); the Sand Scorpion is in %d rooms" % [", ".join(shore_kinds.keys()), scorpion_rooms])
	var scorpion := DataRegistry.get_enemy("beach_sand_scorpion")
	check(scorpion.element == "earth" and int(scorpion.weaknesses.get("arcane", 0)) == 50 and scorpion.actions.has("sand_spray") and scorpion.actions.has("venom_sting"), "the Sand Scorpion: earth attacker, weak to arcane, Sandblinds and poisons")
	var shark := DataRegistry.get_enemy("beach_shark_knight")
	check(shark.element == "water" and int(shark.weaknesses.get("lightning", 0)) == 50 and int(shark.resistances.get("water", 0)) == 50, "the Shark Knight: water attacker, weak to lightning, resists water")
	# Event pools follow the terrain.
	for node: MapNodeData in graph.nodes.values():
		if node.type == MapNodeData.TYPE_EVENT:
			check(node.event_pool == "beach_" + node.terrain and not EventResolver.pool_event_ids(node.event_pool).is_empty(), "%s rolls %s events" % [node.id, node.event_pool])
	check(EventResolver.pool_event_ids("beach_sea").has("beach_shipwreck") and not EventResolver.pool_event_ids("beach_sea").has("beach_sun_shrine"), "the sea pool has the wreck, not the dune shrine")
	# Backdrops: sea rooms (fights and others) use the ship, shore rooms the map's beach.
	var picks: Array[String] = []
	for node_id in ["crab_burrows", "fishers_hamlet", "lighthouse", "crab_shallows", "dune_village"]:
		picks.append(graph.terrain_backdrop(graph.get_node_data(node_id)))
	check(picks == ["battle_ship_deck", "battle_ship_deck", "battle_ship_deck", "battle_beach", "battle_beach"], "sea fight, town and rest rooms take the ship deck; shore rooms the beach (%s)" % str(picks))
	check(graph.terrain_backdrop(graph.get_node_data(graph.start_node_id)) == "" and graph.terrain_hint(graph.get_node_data("crab_burrows")).begins_with("At sea"), "untagged rooms keep the map's picture; sea rooms say so on the map")
	var plain := MapGraph.from_dict({"id": "plain", "nodes": [{"id": "a", "type": "start", "terrain": "sea"}]})
	check(plain.terrain_backdrop(plain.get_node_data("a")) == "", "a map without terrains ignores room tags")


func _test_rooms() -> void:
	print("Rooms")
	var graph := MapGraph.from_dict(DataRegistry.get_map(MAP_ID))
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
	var beach_events := 0
	for event_id: String in DataRegistry.events:
		if (DataRegistry.get_event(event_id).get("pools", []) as Array).has("beach"):
			beach_events += 1
	check(beach_events >= 6, "six coast events (%d)" % beach_events)
	# The shipwreck dive gives a Kelpwoven Coat.
	var inventory := Inventory.new()
	var party := _party()
	var dive: Dictionary = (DataRegistry.get_event("beach_shipwreck")["choices"] as Array)[1]
	EventResolver.apply(dive["effects"], party, inventory)
	check(inventory.equipment == ["kelpwoven_coat"] and party.get_member("chiara").current_hp == 52, "events can give equipment (and the dive costs 8 HP)")
	# Shops sell equipment straight into the stash.
	var shop := Merchant.from_definition(DataRegistry.get_shop("beach_dune_bazaar"))
	inventory.gold = 500
	check(shop.buy("sandstone_cuirass", inventory) == "" and inventory.equipment.has("sandstone_cuirass") and inventory.count_of("sandstone_cuirass") == 0, "buying armour puts it in the stash")
	check(shop.buy("sandstone_cuirass", inventory) == "Sold out.", "it is a single piece")


func _test_soaked() -> void:
	print("Soaked")
	var soaked := DataRegistry.get_status("soaked")
	check(soaked != null and soaked.vulnerable_elements == ["lightning", "frost"] and soaked.vulnerable_per_stack == 15 and soaked.max_stacks == 3, "Soaked: +15% lightning and frost per stack, max 3")
	var cm := _combat(["beach_dire_albatross"])
	var bianca := cm.get_combatant("bianca")
	bianca.add_status("soaked", 2, "x")
	var hp := bianca.hp
	cm.hit(bianca, 8, "lightning", cm.enemies[0])
	check(hp - bianca.hp == 10, "a Soaked 2 target takes 8 lightning as 10 (lost %d)" % (hp - bianca.hp))
	hp = bianca.hp
	cm.hit(bianca, 8, "earth", cm.enemies[0])
	check(hp - bianca.hp == 8, "other types are unaffected")
	# The triton's Tide Surge soaks its target.
	var cm2 := _combat(["beach_triton_soldier"])
	var triton := cm2.enemies[0]
	check(triton.intent.action_id == "tide_surge" and triton.intent.status_id == "soaked" and triton.intent.element == "water", "the triton opens with Tide Surge (water + Soaked)")
	cm2.end_player_turn()
	check(cm2.party_combatants.any(func(c: Combatant) -> bool: return c.has_status("soaked")), "its target is Soaked")


func _test_sandblind() -> void:
	print("Sandblind")
	var cm := _combat(["beach_giant_crab"])
	var bianca := cm.get_combatant("bianca")
	var crab := cm.enemies[0]
	bianca.add_status("sandblind", 2, "x")
	check(bianca.damage_dealt_pct() == -25, "Sandblind: -25% damage dealt")
	var hp := crab.hp
	cm.hit(crab, 12, "holy", bianca)
	check(hp - crab.hp == 9, "a Sandblind attack of 12 deals 9 (lost %d)" % (hp - crab.hp))
	var events: Array = []
	cm.visual_event.connect(func(e: Dictionary) -> void: events.append(e))
	cm.hit(crab, 12, "holy", bianca)
	check(not events.any(func(e: Dictionary) -> bool: return e["kind"] == "affinity"), "Sandblind does not show a 'Resist' pop-up on the target")
	var giant := _combat(["elite_sand_giant"])
	check(giant.enemies[0].intent.action_id == "blinding_gust" and giant.enemies[0].intent.hits_all, "the Sand Giant opens by blinding the whole party")
	giant.end_player_turn()
	check(giant.party_combatants.all(func(c: Combatant) -> bool: return c.has_status("sandblind")), "both princesses are Sandblind")


func _test_quicksand() -> void:
	print("Quicksand")
	var cm := _combat(["beach_giant_crab"])  # the crab applies no Quicksand of its own
	check(cm.deck.hand.size() == 5, "a normal turn draws 5")
	cm.get_combatant("chiara").add_status("quicksand", 2, "x")
	cm.end_player_turn()
	check(cm.deck.hand.size() == 4, "Quicksand: the next turn draws 4 (%d)" % cm.deck.hand.size())
	var chiara := cm.get_combatant("chiara")
	check(int(chiara.statuses.get("quicksand", {}).get("stacks", 0)) >= 1, "one stack is used per turn")
	cm.get_combatant("bianca").add_status("quicksand", 3, "x")
	chiara.add_status("quicksand", 3, "x")
	cm.end_player_turn()
	check(cm.deck.hand.size() == 4, "two sinking members: still only 1 card fewer (draws 4, got %d)" % cm.deck.hand.size())
	check(DataRegistry.get_status("quicksand").decay == "on_trigger", "Quicksand only fades when it costs a card")


func _test_immunity_and_items() -> void:
	print("Coast equipment")
	for item_id in ["coral_mail", "sandstone_cuirass", "kelpwoven_coat", "dunewalker_wraps", "tidecaller_staff", "coralsteel_sabre"]:
		check(Equipment.is_equipment(item_id) and ResourceLoader.exists(str(Equipment.item(item_id).get("icon", ""))), "%s exists with an icon" % item_id)
	check(Equipment.stat_lines("kelpwoven_coat").has("Immune to Soaked") and Equipment.stat_lines("coral_mail").has("Water resistance 30%"), "stat lines show immunities and the new types")
	var party := _party()
	var inventory := Inventory.new()
	inventory.add_equipment("kelpwoven_coat")
	inventory.add_equipment("dunewalker_wraps")
	inventory.add_equipment("sandstone_cuirass")
	Equipment.equip(party.get_member("bianca"), inventory, "kelpwoven_coat")
	Equipment.equip(party.get_member("chiara"), inventory, "dunewalker_wraps")
	var cm := CombatManager.new()
	cm.setup(party, {"id": "t", "name": "T", "enemies": ["beach_triton_soldier"], "gold_reward": 0}, inventory, 1)
	cm.start()
	var bianca := cm.get_combatant("bianca")
	bianca.add_status("soaked", 2, "x")
	check(not bianca.has_status("soaked") and int(bianca.affinity.get("water", 0)) == -15, "the Kelpwoven Coat: never Soaked, 15% water resistance")
	cm.get_combatant("chiara").add_status("sandblind", 2, "x")
	check(not cm.get_combatant("chiara").has_status("sandblind"), "the Dunewalker Wraps prevent Sandblind")
	var balanced := true
	for entry in Equipment.all_items():
		var stats: Dictionary = entry.get("stats", {})
		balanced = balanced and (stats.get("resist", {}) as Dictionary).size() <= 1 and (stats.get("damage", {}) as Dictionary).size() <= 1 and (stats.get("immune", []) as Array).size() <= 1
	check(balanced, "every item still has at most one resistance, one damage type and one immunity")


func _test_effects_and_acts() -> void:
	print("Attack effects and acts")
	check(VfxCatalog.match_event({"kind": "enemy_attack", "element": "water", "action_id": "x"}) == "water_splash", "water attacks splash")
	check(VfxCatalog.match_event({"kind": "enemy_attack", "element": "earth", "action_id": "boulder_hurl"}) == "rock_hurl", "the Rock Giant hurls a boulder")
	check(VfxCatalog.match_event({"kind": "enemy_attack", "element": "water", "action_id": "brine_spray"}) == "tidal_wave", "the Sea Snake's Brine Spray is a wave")
	check(VfxCatalog.match_event({"kind": "enemy_attack", "element": "physical", "status_id": "poison"}) == "poison_burst", "older rules still win for poison bites")
	check(VfxCatalog.match_event({"kind": "enemy_attack", "element": "physical"}) == "enemy_slash", "plain attacks keep their slash")
	check(str(AssetCatalog.room_backdrop("fishers_hamlet", "town", MAP_ID)["asset_id"]) == "battle_beach", "coast rooms (towns, shops, events) show the beach, not a castle interior")
	check(str(AssetCatalog.room_backdrop("elderwood_village", "town", "enchanted_forest")["asset_id"]) == "battle_forest", "forest rooms show the forest")
	check(str(AssetCatalog.room_backdrop("royal_chambers", "start", "royal_castle_tutorial")["asset_id"]) == "bg_royal_chambers", "castle rooms keep their own pictures")
	var order: Array = RunRules.get_block("acts").get("order", [])
	check(order == ["royal_castle_tutorial", "enchanted_forest", "sunlit_coast"], "acts: castle, forest, coast")
	check(DataRegistry.get_map("enchanted_forest").get("completion", {}).get("text", "").contains("Coast"), "the forest's ending points to the coast")
