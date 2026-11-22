extends SceneTree
## Milestone 8 logic tests: Enchanted Forest map graph and layout, towns, events, treasure,
## encounters, poison, the Forest Serpent and multi-map saves. Run:
##   godot --headless --path . --script res://tests/progression/run_forest_tests.gd

const MAP_ID := "enchanted_forest"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	_test_map()
	_test_towns_and_shops()
	_test_events()
	_test_treasure()
	_test_encounters_and_assets()
	_test_poison_and_boss()
	_test_saves()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _party() -> Party:
	return Party.from_selection({"chiara": "fire", "bianca": "holy"})


func _graph() -> MapGraph:
	return MapGraph.from_dict(DataRegistry.get_map(MAP_ID))


# --- Map -------------------------------------------------------------------------------------

func _test_map() -> void:
	print("Forest map")
	var graph := _graph()
	check(graph.validate().is_empty(), "the forest graph is valid (%s)" % ", ".join(graph.validate()))
	check(graph.nodes.size() >= 40 and graph.nodes.size() <= 55, "it is a full-length act: 40-55 nodes (%d)" % graph.nodes.size())
	check(graph.act == 2 and graph.battle_backdrop != "" and not graph.completion.is_empty(), "act number, battle backdrop and completion text are data")
	var boss_id := ""
	var counts: Dictionary = {}
	for node: MapNodeData in graph.nodes.values():
		counts[node.type] = int(counts.get(node.type, 0)) + 1
		if node.type == MapNodeData.TYPE_BOSS:
			boss_id = node.id
	for type in ["combat", "elite", "town", "merchant", "rest", "event", "treasure", "boss", "start", "exit"]:
		check(int(counts.get(type, 0)) >= 1, "the map has at least one %s node (%d)" % [type, int(counts.get(type, 0))])
	check(int(counts.get("elite", 0)) >= 3 and int(counts.get("combat", 0)) >= 12 and int(counts.get("event", 0)) >= 6 and int(counts.get("town", 0)) >= 2 and int(counts.get("treasure", 0)) >= 2 and int(counts.get("boss", 0)) == 1, "two elites, two or more towns and treasures, exactly one boss")
	# Reachability and stages by depth from the entrance.
	var depth: Dictionary = {graph.start_node_id: 0}
	var queue: Array[String] = [graph.start_node_id]
	var acyclic := true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in graph.get_next_ids(current):
			if depth.has(next_id) and int(depth[next_id]) <= int(depth[current]) - 1:
				acyclic = false
			if not depth.has(next_id) or int(depth[next_id]) < int(depth[current]) + 1:
				depth[next_id] = int(depth[current]) + 1
				queue.append(next_id)
	check(depth.size() == graph.nodes.size(), "every node is reachable from the entrance (no disconnected nodes)")
	check(acyclic, "no route loops back")
	var all_reach_boss := true
	var dead_ends: Array[String] = []
	for node: MapNodeData in graph.nodes.values():
		if node.id == graph.exit_node_id:
			continue
		if node.next_ids.is_empty():
			dead_ends.append(node.id)
		if node.id != boss_id and not _reaches(graph, node.id, boss_id):
			all_reach_boss = false
	check(dead_ends.is_empty() and all_reach_boss, "every route eventually reaches the Forest Serpent (dead ends: %s)" % ", ".join(dead_ends))
	check(graph.get_next_ids(boss_id) == [graph.exit_node_id] and int(depth[boss_id]) == 12, "the boss is the last room before the exit, after eleven stages")
	var stage_sizes: Array[int] = []
	stage_sizes.resize(16)
	stage_sizes.fill(0)
	for node_id: String in depth:
		stage_sizes[int(depth[node_id])] += 1
	check(stage_sizes.slice(1, 12).all(func(n: int) -> bool: return n >= 3 and n <= 5), "each of the eleven stages offers three to five rooms %s" % str(stage_sizes.slice(1, 12)))
	check(_route_count(graph, graph.start_node_id, boss_id) >= 12, "many different routes lead to the boss (%d)" % _route_count(graph, graph.start_node_id, boss_id))
	var progress := MapProgress.new(graph)
	check(progress.get_available_ids().size() == 3, "three choices from the entrance")
	check(not progress.travel_to(boss_id) and not progress.travel_to("no_such_node") and progress.current_node_id == graph.start_node_id, "invalid transitions are rejected")
	check(progress.travel_to("wolf_trail") and not progress.travel_to("mossy_crossing"), "after choosing a branch the skipped siblings are closed")
	# Every node has what its type needs.
	var complete := true
	for node: MapNodeData in graph.nodes.values():
		match node.type:
			"combat", "elite", "boss":
				complete = complete and not DataRegistry.get_encounter(node.encounter_id).is_empty()
			"town":
				complete = complete and not DataRegistry.get_town(node.town_id).is_empty()
			"merchant":
				complete = complete and not DataRegistry.get_shop(node.shop_id).is_empty()
			"treasure":
				complete = complete and not DataRegistry.get_treasure(node.treasure_id).is_empty()
			"event":
				complete = complete and (not DataRegistry.get_event(node.event_id).is_empty() or EventResolver.pool_event_ids(node.event_pool).size() >= 3)
	check(complete, "every node resolves its encounter, town, shop, treasure or event pool")
	var layout := MapLayout.for_map(MAP_ID)
	check(layout != null and layout.validate(graph).is_empty(), "the forest layout matches the graph")
	check(layout.get_background() != null and layout.background_asset == "map_enchanted_forest", "the layout uses the illustrated forest map as a separate background")
	check(layout.canvas_height >= 3.0, "the route chart is several screens tall and scrolls (%.1f pictures)" % layout.canvas_height)
	var upward := true
	for node: MapNodeData in graph.nodes.values():
		for next_id in node.next_ids:
			if next_id != graph.exit_node_id and (layout.nodes[next_id] as Vector2).y >= (layout.nodes[node.id] as Vector2).y:
				upward = false
	check(upward, "routes climb upward from the entrance to the Serpent's Domain")
	for type in ["town", "boss", "elite", "treasure"]:
		check(MapNodeButton.TYPE_STYLE.has(type) and str(MapNodeButton.TYPE_STYLE[type]["emblem"]) != "", "%s nodes have their own emblem" % type)
	check(float(MapNodeButton.TYPE_STYLE["boss"]["factor"]) > float(MapNodeButton.TYPE_STYLE["elite"]["factor"]), "the boss node is the largest on the map")
	check(MapGraph.from_dict(DataRegistry.get_map("royal_castle_tutorial")).nodes.size() == 9, "the Royal Castle graph is unchanged (9 nodes)")
	var order: Array = RunRules.get_block("acts").get("order", [])
	check(order == ["royal_castle_tutorial", MAP_ID, "sunlit_coast"], "acts: the castle leads to the forest, the forest to the Sunlit Coast (data)")


## Travels along a shortest valid route to the target node.
func _walk(progress: MapProgress, target_id: String) -> void:
	var previous: Dictionary = {progress.current_node_id: ""}
	var queue: Array[String] = [progress.current_node_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in progress.graph.get_next_ids(current):
			if not previous.has(next_id):
				previous[next_id] = current
				queue.append(next_id)
	var route: Array[String] = []
	var step := target_id
	while previous.has(step) and str(previous[step]) != "":
		route.push_front(step)
		step = str(previous[step])
	for node_id in route:
		progress.travel_to(node_id)


func _reaches(graph: MapGraph, from_id: String, target_id: String) -> bool:
	var seen: Array[String] = []
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_back()
		if current == target_id:
			return true
		if seen.has(current):
			continue
		seen.append(current)
		queue.append_array(graph.get_next_ids(current))
	return false


func _route_count(graph: MapGraph, from_id: String, target_id: String) -> int:
	if from_id == target_id:
		return 1
	var total := 0
	for next_id in graph.get_next_ids(from_id):
		total += _route_count(graph, next_id, target_id)
	return total


# --- Towns -----------------------------------------------------------------------------------

func _test_towns_and_shops() -> void:
	print("Towns")
	var camp := DataRegistry.get_town("brookside_camp")
	var village := DataRegistry.get_town("elderwood_village")
	var outpost := DataRegistry.get_town("last_trader_outpost")
	check(camp["services"] == ["rest"] and not camp.has("shop_id"), "small camp: rest only")
	check(village["services"] == ["merchant", "rest"] and not DataRegistry.get_shop(village["shop_id"]).is_empty(), "forest settlement: merchant and rest")
	check(outpost["services"] == ["merchant"] and not DataRegistry.get_shop(outpost["shop_id"]).is_empty(), "trading outpost: merchant only")
	var merchant := Merchant.from_definition(DataRegistry.get_shop(village["shop_id"]))
	var inventory := Inventory.new()
	inventory.gold = 20
	check(merchant.buy("minor_health_potion", inventory) == "" and inventory.count_of("minor_health_potion") == 1, "the town market sells through the existing Merchant logic")
	check(merchant.buy("health_potion", inventory) != "", "and still refuses a purchase without enough gold")
	var party := _party()
	party.get_member("chiara").current_hp = 10
	party.rest(float(camp["heal_percent"]) / 100.0)
	check(party.get_member("chiara").current_hp == 10 + ceili(60 * 0.25), "the camp's rest uses the existing rest rule with its own percentage")


# --- Events ----------------------------------------------------------------------------------

func _test_events() -> void:
	print("Forest events")
	var forest := EventResolver.pool_event_ids("forest")
	var danger := EventResolver.pool_event_ids("forest_danger")
	var all_ids: Array[String] = []
	for id in forest + danger:
		if not all_ids.has(id):
			all_ids.append(id)
	check(all_ids.size() >= 8, "at least 8 forest events (%d)" % all_ids.size())
	check(forest.size() >= 6 and danger.size() >= 3, "a general pool (%d) and a dangerous pool (%d)" % [forest.size(), danger.size()])
	var well_formed := true
	var signatures: Dictionary = {}
	for id in all_ids:
		var event := DataRegistry.get_event(id)
		well_formed = well_formed and str(event.get("title", "")) != "" and (event.get("choices", []) as Array).size() >= 2
		for choice: Dictionary in event["choices"]:
			well_formed = well_formed and str(choice.get("text", "")) != "" and str(choice.get("result", "")) != ""
		signatures[JSON.stringify(event["choices"])] = true
	check(well_formed, "every event has a title and at least two choices that state their consequences")
	check(signatures.size() == all_ids.size(), "no two events have identical choices")
	# Every effect of every choice applies without leaving invalid HP or gold.
	var valid := true
	for id in all_ids:
		for choice: Dictionary in DataRegistry.get_event(id)["choices"]:
			var party := _party()
			party.get_member("chiara").current_hp = 3
			party.get_member("bianca").current_hp = 0  # fallen: must be skipped safely
			var inventory := Inventory.new()
			inventory.gold = 5
			var result := EventResolver.apply(choice.get("effects", []), party, inventory)
			valid = valid and inventory.gold >= 0 and party.get_member("chiara").current_hp >= 1 and party.get_member("chiara").current_hp <= 60 and party.get_member("bianca").current_hp == 0
			valid = valid and result.has("card_reward") and result.has("encounter_id")
	check(valid, "all choices keep HP within 1..max for the living, leave the fallen alone and never make gold negative")
	var party := _party()
	var inventory := Inventory.new()
	inventory.gold = 10
	var herbalist := DataRegistry.get_event("forest_herbalist")
	check(EventResolver.blocked_reason(herbalist["choices"][1], inventory) != "" and EventResolver.blocked_reason(herbalist["choices"][0], inventory) == "", "a choice that costs gold is blocked without enough gold")
	party.get_member("chiara").current_hp = 30
	EventResolver.apply(herbalist["choices"][0]["effects"], party, inventory)
	check(party.get_member("chiara").current_hp == 40 and inventory.gold == 10, "the free poultice heals 10")
	inventory.gold = 50
	EventResolver.apply(herbalist["choices"][1]["effects"], party, inventory)
	check(party.get_member("chiara").current_hp == 60 and inventory.gold == 30, "the tonic costs 20 gold and heals up to max HP")
	var cache := DataRegistry.get_event("forest_supply_cache")
	party.get_member("bianca").current_hp = 5
	EventResolver.apply(cache["choices"][1]["effects"], party, inventory)
	check(inventory.gold == 95 and party.get_member("bianca").current_hp == 1, "trap damage stops at 1 HP (events never kill)")
	var traveller := DataRegistry.get_event("forest_wounded_traveller")
	check(EventResolver.blocked_reason(traveller["choices"][0], inventory) != "", "giving a potion needs a potion")
	inventory.add_item("health_potion")
	EventResolver.apply(traveller["choices"][0]["effects"], party, inventory)
	check(inventory.count_of("health_potion") == 0 and inventory.gold == 170, "the potion is given away and the reward is paid")
	var spirit := DataRegistry.get_event("forest_spirit")
	EventResolver.apply(spirit["choices"][0]["effects"], party, inventory)
	check(inventory.relics.size() == 1, "the spirit grants a relic")
	inventory.relics.assign(["guardian_locket", "scholars_satchel", "healers_pendant"])
	var gold_before := inventory.gold
	EventResolver.apply(spirit["choices"][0]["effects"], party, inventory)
	check(inventory.relics.size() == 3 and inventory.gold == gold_before + 50, "with every relic owned it pays gold instead (no duplicate relic)")
	check(bool(EventResolver.apply(DataRegistry.get_event("forest_shrine")["choices"][0]["effects"], party, inventory)["card_reward"]), "the shrine reports a card reward")
	check(EventResolver.apply(DataRegistry.get_event("forest_ambush")["choices"][0]["effects"], party, inventory)["encounter_id"] == "forest_spider_ambush", "the ambush reports its encounter")
	inventory.gold = 10
	EventResolver.apply(DataRegistry.get_event("forest_ambush")["choices"][1]["effects"], party, inventory)
	check(inventory.gold == 0, "losing gold never goes below zero")
	var first := EventResolver.pick_from_pool("forest", [], _rng(3))
	var seen: Array = [first]
	var repeats := false
	for i in forest.size() - 1:
		var next_event := EventResolver.pick_from_pool("forest", seen, _rng(3 + i))
		repeats = repeats or seen.has(next_event)
		seen.append(next_event)
	check(not repeats and seen.size() == forest.size(), "events already seen in the run are not rolled again while fresh ones remain")
	check(EventResolver.pick_from_pool("forest", seen, _rng(1)) != "" and EventResolver.pick_from_pool("no_pool", [], _rng(1)) == "", "an exhausted pool still yields an event; an unknown pool yields none")
	check(not DataRegistry.get_event("castle_fountain_intro").is_empty(), "the castle event still loads")


# --- Treasure ----------------------------------------------------------------------------------

func _test_treasure() -> void:
	print("Forest treasure")
	for id in ["forest_cache_01", "forest_shrine_hoard"]:
		var party := _party()
		var inventory := Inventory.new()
		var state := TreasureRoom.generate(id, party, inventory, _rng(4))
		check((state["choices"] as Array).size() == 5, "%s offers five choices (equipment included)" % id)
		check(TreasureRoom.claim(state, 0, party, inventory) == "" and inventory.gold >= 70, "%s: gold can be claimed" % id)
		check(TreasureRoom.claim(state, 1, party, inventory) != "", "%s: only one claim" % id)
	var rare_state := TreasureRoom.generate("forest_shrine_hoard", _party(), Inventory.new(), _rng(5))
	var rare_choice: Dictionary = (rare_state["choices"] as Array).filter(func(c: Dictionary) -> bool: return c["type"] == "card")[0]
	check(DataRegistry.get_card(rare_choice["card_id"]).rarity == "rare", "the shrine hoard offers a rare card")


# --- Encounters and assets ---------------------------------------------------------------------

func _test_encounters_and_assets() -> void:
	print("Forest encounters and assets")
	var ids := ["forest_wolves_01", "forest_boar_01", "forest_harpies_01", "forest_spider_ambush", "forest_wolf_harpy", "forest_bear_01", "forest_wisp_spiders", "forest_troll_01", "forest_drake_nest", "elite_alpha_pack", "elite_grove_warden", "elite_broodmother", "boss_forest_serpent"]
	var loaded := true
	var used_sets: Dictionary = {}
	for id in ids:
		var encounter := DataRegistry.get_encounter(id)
		loaded = loaded and not encounter.is_empty() and (encounter["enemies"] as Array).size() <= 6
		for enemy_id: String in encounter.get("enemies", []):
			loaded = loaded and DataRegistry.get_enemy(enemy_id) != null
			used_sets[CombatPresentation.enemy_set(enemy_id)] = true
	check(loaded, "all %d forest encounters and their enemies load (max 6 enemies each)" % ids.size())
	for set_id in ["wolf", "boar", "bear", "spider", "drake", "troll", "boss_serpent", "cliff_harpy", "will_o_wisp"]:
		check(used_sets.has(set_id), "the %s art is used by an encounter" % set_id)
	var art_ok := true
	for enemy_id in ["forest_wolf", "forest_boar", "forest_spider", "forest_bear", "forest_drake", "forest_troll", "elite_alpha_wolf", "elite_grove_warden", "elite_broodmother", "forest_serpent"]:
		for state in ["idle", "attack", "hit", "block"]:
			art_ok = art_ok and CombatPresentation.enemy_state(enemy_id, state) != null
	check(art_ok, "every forest enemy resolves idle, attack, hit and block art")
	check(CombatPresentation.enemy_scale("forest_serpent") > CombatPresentation.enemy_scale("forest_wolf"), "the boss is drawn larger than normal enemies")
	check(not bool(DataRegistry.get_encounter("boss_forest_serpent").get("elite", false)) and bool(DataRegistry.get_encounter("boss_forest_serpent")["boss"]), "the Forest Serpent is a boss, not an elite")
	var elite_count := 0
	for id in ids:
		if bool(DataRegistry.get_encounter(id).get("elite", false)):
			elite_count += 1
			check(int(DataRegistry.get_encounter(id)["gold_reward"]) > int(DataRegistry.get_encounter("forest_troll_01")["gold_reward"]), "%s pays more than the hardest normal fight" % id)
	check(elite_count >= 2, "at least two forest elites (%d)" % elite_count)
	check(VfxCatalog.match_event({"kind": "enemy_attack", "status_id": "poison"}) == "poison_burst" and VfxCatalog.match_event({"kind": "status_tick", "status_id": "poison"}) == "poison_tick", "poison attacks and ticks map to the poison sprite")
	check(VfxCatalog.match_event({"kind": "enemy_attack", "status_id": ""}) == "enemy_slash", "ordinary enemy attacks keep their slash effect")
	check(VfxCatalog.sprite_texture(VfxCatalog.effect("poison_burst")) != null, "the poison sprite file loads")
	check(AssetCatalog.texture("battle_forest") != null and AssetCatalog.texture("map_enchanted_forest") != null, "forest map and battle backdrops load")
	# A normal fight works with the existing engine.
	var cm := CombatManager.new()
	cm.setup(_party(), DataRegistry.get_encounter("forest_wolves_01"), Inventory.new(), 5)
	cm.start()
	check(cm.enemies.size() == 2 and cm.enemies[0].intent != null and not cm.is_elite and not cm.is_boss, "a wolf pack starts as a normal fight with visible intents")
	for enemy in cm.enemies:
		enemy.take_damage(999)
	var ended: Array[String] = []
	cm.ended.connect(func(result: String) -> void: ended.append(result))
	cm.end_player_turn()
	check(ended == [CombatManager.RESULT_VICTORY], "defeating every enemy wins the fight")
	var lost := CombatManager.new()
	lost.setup(_party(), DataRegistry.get_encounter("elite_grove_warden"), Inventory.new(), 5)
	lost.start()
	check(lost.is_elite and lost.intro_text != "", "the Grove Warden is an elite with an intro")
	for c in lost.party_combatants:
		c.hp = 1
	var lost_result: Array[String] = []
	lost.ended.connect(func(result: String) -> void: lost_result.append(result))
	for i in 6:
		if lost.state == CombatManager.State.PLAYER_TURN:
			lost.end_player_turn()
	check(lost_result == [CombatManager.RESULT_DEFEAT], "a party wipe is a defeat")


# --- Poison and the boss -------------------------------------------------------------------------

func _test_poison_and_boss() -> void:
	print("Poison and the Forest Serpent")
	var poison := DataRegistry.get_status("poison")
	check(poison != null and poison.tick_per_stack and poison.tick_ignores_block and poison.tick_amount(4) == 4, "Poison ticks for its stacks and ignores Block")
	check(DataRegistry.get_status("burn").tick_amount(3) == 3 and DataRegistry.get_status("burn").tick_amount(1) == 3, "Burn ticks for a fixed 3 whatever its duration")
	_test_bleed()
	var cm := CombatManager.new()
	cm.setup(_party(), DataRegistry.get_encounter("boss_forest_serpent"), Inventory.new(), 7)
	cm.start()
	var boss := cm.enemies[0]
	check(cm.is_boss and boss.enemy_def.boss and boss.max_hp >= 140, "the boss fight is flagged and the Serpent is far tougher than normal enemies")
	check(boss.intent != null and boss.intent.action_id == "venom_strike" and boss.intent.status_id == "poison", "its first intent is Venom Strike with a poison rider")
	var text := boss.intent.describe("Chiara")
	check(text.contains("dmg") and text.contains("Poison") and text.contains("Chiara"), "the intent text shows damage, poison and target (%s)" % text)
	var events: Array[Dictionary] = []
	cm.visual_event.connect(func(e: Dictionary) -> void: events.append(e))
	var target := cm.get_intent_target(boss)
	target.add_block(50)
	cm.end_player_turn()
	check(target.hp == target.max_hp and target.has_status("poison") and int(target.statuses["poison"]["stacks"]) == 2, "Venom Strike poisons even through Block (3 stacks, 2 left after the round)")
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "enemy_attack" and str(e.get("status_id", "")) == "poison"), "the attack announces its poison for the VFX")
	events.clear()
	var hp_before := target.hp
	target.add_block(50)
	cm.end_player_turn()
	check(target.hp == hp_before - 2, "Poison then deals damage equal to its stacks, ignoring Block (2)")
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "status_tick" and e["status_id"] == "poison"), "the tick is announced for the VFX")
	check(boss.block > 0, "Serpent Coil gave the boss Block (second action)")
	# Third action: Toxic Breath hits the whole party.
	check(boss.intent.action_id == "toxic_breath" and boss.intent.hits_all and boss.intent.describe("").contains("whole party"), "Toxic Breath is announced as a party-wide attack")
	var chiara := cm.get_combatant("chiara")
	var bianca := cm.get_combatant("bianca")
	var before := [chiara.hp, bianca.hp]
	cm.end_player_turn()
	check(chiara.hp < before[0] and bianca.hp < before[1] and chiara.has_status("poison") and bianca.has_status("poison"), "Toxic Breath damages and poisons both characters")
	var seen_actions: Dictionary = {}
	for i in 4:
		seen_actions[boss.intent.action_id] = true
		for c in cm.party_combatants:
			c.hp = c.max_hp
			c.statuses.clear()
		cm.end_player_turn()
	check(seen_actions.has("forest_quake"), "Forest Quake is part of the normal pattern")
	boss.hp = int(boss.max_hp * 0.5)
	for c in cm.party_combatants:
		c.hp = c.max_hp
	cm.end_player_turn()
	check(boss.enraged and boss.intent.action_id in ["ancient_venom", "forest_quake", "venom_strike", "coil"], "below half health the Serpent switches to its enraged pattern")
	var enraged_actions: Dictionary = {}
	for i in 4:
		enraged_actions[boss.intent.action_id] = true
		for c in cm.party_combatants:
			c.hp = c.max_hp
			c.statuses.clear()
		cm.end_player_turn()
	check(enraged_actions.has("ancient_venom"), "Ancient Venom appears in the enraged pattern")
	var rules: Dictionary = DataRegistry.get_encounter("boss_forest_serpent")["reward"]
	var reward := CardReward.generate(_party(), _rng(2), 3, rules)
	var all_epic := reward.options.all(func(o: Dictionary) -> bool: return DataRegistry.get_card(o["card_id"]).rarity == "epic")
	var party := _party()
	var owners_ok := reward.options.all(func(o: Dictionary) -> bool: return party.get_member(o["owner_character_id"]).specialization.epic_pool.has(o["card_id"]))
	check(reward.options.size() == 3 and all_epic and owners_ok, "the boss reward offers 3 epic cards from the party's own specializations")
	var normal_epic := false
	for seed_value in 40:
		for option in CardReward.generate(_party(), _rng(seed_value)).options:
			normal_epic = normal_epic or DataRegistry.get_card(option["card_id"]).rarity == "epic"
	check(not normal_epic, "normal rewards never offer epic cards (40 seeds)")
	check(DataRegistry.get_encounter("castle_final_regular_01")["reward"]["pool"] == "epic", "the castle's final fight also rewards an epic card")
	var picked := reward.choose(0, party)
	check(picked != null and DataRegistry.get_card(picked.card_id).rarity == "epic", "an epic card can be taken into its owner's deck")
	for spec_id in ["fire", "arcana", "holy", "tanking"]:
		var spec := DataRegistry.get_specialization(spec_id)
		var cards_ok := spec.epic_pool.size() >= 2 and spec.epic_pool.all(func(id: String) -> bool: return DataRegistry.get_card(id) != null and DataRegistry.get_card(id).specialization_id == spec_id and not spec.card_pool.has(id))
		check(cards_ok, "%s has its own epic cards, separate from its normal pool" % spec_id)
	check(int(DataRegistry.get_encounter("boss_forest_serpent")["gold_reward"]) >= 100, "and the largest gold reward of the act")
	# A fallen target is skipped by a party-wide attack without errors.
	var solo := CombatManager.new()
	solo.setup(_party(), DataRegistry.get_encounter("forest_troll_01"), Inventory.new(), 3)
	solo.start()
	solo.get_combatant("chiara").take_damage(999)
	for i in 3:
		if solo.state == CombatManager.State.PLAYER_TURN:
			solo.get_combatant("bianca").hp = 80
			solo.end_player_turn()
	check(solo.state == CombatManager.State.PLAYER_TURN and not solo.get_combatant("chiara").is_alive(), "party-wide attacks handle a fallen character safely")


# --- Saves ---------------------------------------------------------------------------------------

func _test_saves() -> void:
	print("Multi-map saves")
	var party := _party()
	party.get_member("chiara").deck[0].upgrade_level = 1
	party.get_member("chiara").current_hp = 33
	var inventory := Inventory.new()
	inventory.gold = 123
	inventory.add_item("health_potion", 2)
	inventory.add_relic("guardian_locket")
	var progress := MapProgress.new(_graph())
	_walk(progress, "boar_thicket")
	_walk(progress, "brookside_camp")
	var room := {"node_id": "brookside_camp", "kind": "town", "rested": true}
	var flags := {"seen_events": ["forest_shrine"], "completed_maps": ["royal_castle_tutorial"]}
	var data: Variant = JSON.parse_string(JSON.stringify(SaveManager.serialize(party, inventory, progress, room, null, flags)))
	var restored := SaveManager.restore(data)
	check(restored["ok"] and (restored["progress"] as MapProgress).graph.id == MAP_ID and (restored["progress"] as MapProgress).current_node_id == "brookside_camp", "a forest save returns to the forest map and node")
	check((restored["progress"] as MapProgress).visited_ids.has("boar_thicket"), "visited forest nodes are kept")
	check(restored["room"]["kind"] == "town" and bool(restored["room"]["rested"]), "used town services are kept")
	check(restored["flags"]["seen_events"] == ["forest_shrine"] and restored["flags"]["completed_maps"] == ["royal_castle_tutorial"], "seen events and completed maps are kept")
	check((restored["party"] as Party).get_member("chiara").deck[0].upgrade_level == 1 and (restored["party"] as Party).get_member("chiara").current_hp == 33, "decks, upgrades and HP are kept")
	check((restored["inventory"] as Inventory).gold == 123 and (restored["inventory"] as Inventory).count_of("health_potion") == 2 and (restored["inventory"] as Inventory).has_relic("guardian_locket"), "gold, items and relics are kept")
	var boss_progress := MapProgress.new(_graph())
	_walk(boss_progress, "serpents_domain")
	var boss_room := {"node_id": "serpents_domain", "kind": "boss", "phase": "reward", "gold": 120, "boss": true}
	var reward := CardReward.generate(party, _rng(1), 3, DataRegistry.get_encounter("boss_forest_serpent")["reward"])
	var boss_save := SaveManager.restore(JSON.parse_string(JSON.stringify(SaveManager.serialize(party, inventory, boss_progress, boss_room, reward, flags))))
	check(boss_save["ok"] and boss_save["room"]["kind"] == "boss" and boss_save["reward"] != null and (boss_save["reward"] as CardReward).options.size() == 3, "the boss reward phase survives a save (no second reward roll)")
	var castle := {"version": 1, "party": (data as Dictionary)["party"], "inventory": {"gold": 12, "items": {}}, "map": {"map_id": "royal_castle_tutorial", "current_node_id": "royal_chambers", "visited": ["royal_chambers"]}}
	var old := SaveManager.restore(castle)
	check(old["ok"] and (old["progress"] as MapProgress).graph.id == "royal_castle_tutorial" and (old["flags"] as Dictionary).is_empty(), "an old castle save (version 1) still loads")
	var junk_flags := (data as Dictionary).duplicate(true)
	junk_flags["flags"] = {"seen_events": "oops", "hack": [1]}
	check((SaveManager.restore(junk_flags)["flags"] as Dictionary).is_empty(), "malformed flags are ignored, the save still loads")


func _test_bleed() -> void:
	print("Bleed and the three damage-over-time statuses")
	var bleed := DataRegistry.get_status("bleed")
	check(bleed != null and bleed.on_hit == "stacks" and bleed.decay == "on_trigger" and not bleed.ticks_at(StatusDef.TICK_ENEMY_PHASE_START), "Bleed triggers on hits, never ticks and never fades on its own")
	var burn := DataRegistry.get_status("burn")
	var poison := DataRegistry.get_status("poison")
	check(burn.max_stacks == 4 and poison.max_stacks == 0 and burn.tick_amount(4) == 3 and poison.tick_amount(4) == 4, "Burn: fixed 3, at most 4 turns; Poison: damage = stacks, unlimited")
	var cm := CombatManager.new()
	cm.setup(_party(), DataRegistry.get_encounter("forest_wolves_01"), Inventory.new(), 3)
	cm.start()
	var wolf := cm.enemies[0]
	wolf.max_hp = 200
	wolf.hp = 200
	wolf.add_status("bleed", 3, "chiara")
	wolf.block = 0
	var lost := cm.hit(wolf, 5)
	check(lost == 8 and wolf.hp == 192 and int(wolf.statuses["bleed"]["stacks"]) == 2, "a hit on a bleeding enemy costs the hit (5) + Bleed (3), then Bleed drops to 2")
	wolf.block = 20
	lost = cm.hit(wolf, 6)
	check(lost == 0 and int(wolf.statuses["bleed"]["stacks"]) == 2, "a hit fully stopped by Block does not trigger Bleed")
	wolf.block = 0
	wolf.statuses["bleed"]["stacks"] = 1
	cm.hit(wolf, 2)
	check(not wolf.has_status("bleed"), "the last stack is used up and Bleed disappears")
	wolf.add_status("bleed", 2, "chiara")
	var hp := wolf.hp
	for i in 3:
		wolf.tick_statuses()
	check(int(wolf.statuses["bleed"]["stacks"]) == 2 and wolf.hp == hp, "rounds passing do not reduce or tick Bleed")
	wolf.add_status("poison", 3, "chiara")
	cm.end_player_turn()
	check(wolf.hp == hp - 3 and int(wolf.statuses["bleed"]["stacks"]) == 2, "Poison ticks do not trigger Bleed (only attacks do)")
	var rending: Dictionary = DataRegistry.get_enemy("forest_wolf").actions["lunge"]
	check(rending["status"]["id"] == "bleed" and int(rending["status"]["value"]) == 2, "the wolf's Rending Bite inflicts Bleed 2")
	var party_cm := CombatManager.new()
	party_cm.setup(_party(), DataRegistry.get_encounter("forest_wolves_01"), Inventory.new(), 3)
	party_cm.start()
	var victim := party_cm.get_combatant("chiara")
	victim.add_status("bleed", 2, "forest_wolf_0")
	var before := victim.hp
	party_cm.hit(victim, 4)
	check(victim.hp == before - 6, "Bleed also works on the party (enemy attacks go through the same rule)")
	check(DataRegistry.get_card("chiara_fire_kindle").effects[0]["value"] == 2, "Kindle applies 2 of the hotter Burn")
