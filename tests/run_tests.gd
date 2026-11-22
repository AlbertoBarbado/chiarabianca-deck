extends SceneTree
## Headless logic tests. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any check fails.

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	_test_data_loading()
	_test_party_and_decks()
	_test_party_deck_piles()
	_test_definitions_not_mutated()
	_test_card_rules()
	_test_combat_flow()
	_test_taunt()
	_test_map()
	_test_rest_and_merchant()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)


func _make_party() -> Party:
	return Party.from_selection({"chiara": "arcana", "bianca": "tanking"})


func _test_data_loading() -> void:
	print("Data loading")
	check(DataRegistry.counts()["characters"] == 2, "2 characters loaded")
	check(DataRegistry.counts()["specializations"] == 12, "12 specializations loaded")
	check(DataRegistry.counts()["cards"] == 198, "198 cards loaded: 122 + 72 from the card-pool expansion (9 per specialization) + 4 fusion cards (template skipped)")
	check(DataRegistry.get_specializations_for("chiara").size() == 6, "Chiara has 6 specializations")
	check(DataRegistry.get_specializations_for("bianca").size() == 6, "Bianca has 6 specializations")
	check(DataRegistry.get_specialization("arcana").is_playable(), "Arcana playable")
	check(DataRegistry.get_specialization("tanking").is_playable(), "Tanking playable")
	check(not DataRegistry.get_specialization("earth").is_playable(), "Earth is a design template")


func _test_party_and_decks() -> void:
	print("Individual decks")
	var party := _make_party()
	var chiara := party.get_member("chiara")
	var bianca := party.get_member("bianca")
	check(chiara.deck.size() == 10 and bianca.deck.size() == 10, "each owns 10 cards")
	check(chiara.deck.all(func(c: OwnedCard) -> bool: return c.owner_character_id == "chiara"), "Chiara's cards owned by Chiara")
	check(bianca.deck.all(func(c: OwnedCard) -> bool: return c.owner_character_id == "bianca"), "Bianca's cards owned by Bianca")
	check(chiara.max_hp == 60 and bianca.max_hp == 80, "base HP from data")
	var deck := PartyDeck.new()
	deck.build_from_party(party)
	check(deck.draw_pile.size() == 20, "party deck has 20 cards")
	var per_owner := {"chiara": 0, "bianca": 0}
	for card in deck.draw_pile:
		per_owner[card.owner_character_id] += 1
	check(per_owner["chiara"] == 10 and per_owner["bianca"] == 10, "party deck keeps ownership 10/10")
	check(chiara.deck.size() == 10, "building party deck leaves character decks intact")


func _test_party_deck_piles() -> void:
	print("Piles and reshuffle")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var deck := PartyDeck.new(rng)
	deck.build_from_party(_make_party())
	var drawn := deck.draw(5)
	check(drawn.size() == 5 and deck.hand.size() == 5 and deck.draw_pile.size() == 15, "draw 5")
	deck.discard_hand()
	check(deck.hand.is_empty() and deck.discard_pile.size() == 5, "discard hand")
	deck.draw(15)
	check(deck.draw_pile.is_empty(), "draw pile emptied")
	var reshuffled := [false]
	deck.reshuffled.connect(func() -> void: reshuffled[0] = true)
	deck.draw(1)
	check(reshuffled[0] and deck.hand.size() == 10, "reshuffle discard when draw pile empty (hand capped at 10)")
	check(deck.get_total_card_count() == 20, "no cards lost or duplicated")
	var card := deck.hand[0]
	deck.remove_from_hand(card)
	deck.send_to_exhaust(card)
	check(deck.exhaust_pile.has(card) and deck.get_total_card_count() == 20, "exhaust pile")


func _test_definitions_not_mutated() -> void:
	print("Definitions stay immutable")
	var before: Dictionary = {}
	var card_ids: Array[String] = ["chiara_arcana_bolt", "chiara_arcana_ward", "chiara_arcana_focus", "chiara_arcana_surge", "bianca_tanking_strike", "bianca_tanking_guard", "bianca_tanking_challenge", "bianca_tanking_rally"]
	for id in card_ids:
		before[id] = JSON.stringify(DataRegistry.get_card(id).raw)
	var party := _make_party()
	var deck := PartyDeck.new()
	deck.build_from_party(party)
	for i in 5:
		deck.draw(5)
		deck.discard_hand()
	for card in deck.discard_pile + deck.draw_pile:
		card.upgrade_level = 1
		card.cost_modifier = 2
	var unchanged := true
	for id in card_ids:
		unchanged = unchanged and before[id] == JSON.stringify(DataRegistry.get_card(id).raw)
	check(unchanged, "card definitions unchanged after shuffle/upgrade of instances")
	check(party.members.all(func(m: PartyMember) -> bool: return m.deck.all(func(o: OwnedCard) -> bool: return o.upgrade_level == 0)), "runtime upgrades do not alter owned cards")


func _test_card_rules() -> void:
	print("Card playability")
	var cm := _new_combat("castle_training_01", 3)
	var chiara_card := _find_card(cm, "chiara", "chiara_arcana_bolt")
	cm.party_combatants[0].hp = 0
	check(cm.can_play(chiara_card) != "", "card of fallen owner cannot be played")
	cm.party_combatants[0].hp = 10
	cm.energy = 0
	check(cm.can_play(chiara_card) != "", "card unplayable without energy")


func _new_combat(encounter_id: String, seed_value: int) -> CombatManager:
	var cm := CombatManager.new()
	cm.setup(_make_party(), DataRegistry.get_encounter(encounter_id), Inventory.new(), seed_value)
	cm.start()
	# Put every card in hand for deterministic access.
	cm.deck.hand.append_array(cm.deck.draw_pile)
	cm.deck.draw_pile.clear()
	return cm


func _find_card(cm: CombatManager, owner_id: String, card_id: String) -> CardInstance:
	for card in cm.deck.hand:
		if card.owner_character_id == owner_id and card.definition.id == card_id:
			return card
	return null


func _test_combat_flow() -> void:
	print("Combat")
	var cm := _new_combat("castle_training_01", 5)
	var enemy := cm.enemies[0]
	check(enemy.intent != null and enemy.intent.value == 6, "enemy intent previewed")
	var bolt := _find_card(cm, "chiara", "chiara_arcana_bolt")
	var energy_before := cm.energy
	check(cm.play_card(bolt), "play Arcane Bolt")
	check(enemy.hp == 20 and cm.energy == energy_before - 1, "6 damage dealt, 1 energy spent")
	check(cm.deck.discard_pile.has(bolt) and not cm.deck.hand.has(bolt), "played card goes to discard")
	var ward := _find_card(cm, "chiara", "chiara_arcana_ward")
	cm.play_card(ward)
	check(cm.party_combatants[0].block == 5 and cm.party_combatants[1].block == 0, "Ward blocks only owner")
	var guard := _find_card(cm, "bianca", "bianca_tanking_guard")
	cm.energy = 3
	cm.play_card(guard)
	check(cm.party_combatants[0].block == 10 and cm.party_combatants[1].block == 5, "Hold the Line blocks whole party (5 each)")
	var surge := _find_card(cm, "chiara", "chiara_arcana_surge")
	cm.energy = 1
	cm.play_card(surge)
	check(cm.deck.exhaust_pile.has(surge), "power cards are exhausted")
	var hp_before := cm.party_combatants[0].hp + cm.party_combatants[1].hp
	cm.end_player_turn()
	check(cm.turn == 2 and cm.energy == 3, "enemy turn ran, new player turn begins")
	var hp_after := cm.party_combatants[0].hp + cm.party_combatants[1].hp
	check(hp_after >= hp_before - 6 and cm.deck.hand.size() >= 5, "enemy attack absorbed by block, hand redrawn")
	# Victory
	cm.enemies[0].hp = 1
	var bolt2 := _find_card(cm, "chiara", "chiara_arcana_bolt")
	var result := [""]
	cm.ended.connect(func(r: String) -> void: result[0] = r)
	cm.play_card(bolt2 if bolt2 != null else cm.deck.hand[0])
	if result[0] == "":
		for card in cm.deck.hand:
			if card.definition.id.ends_with("strike") or card.definition.id.ends_with("bolt"):
				cm.energy = 3
				cm.play_card(card)
				break
	check(result[0] == "victory", "combat ends in victory")
	# Defeat
	var cm2 := _new_combat("castle_final_regular_01", 9)
	var outcome := [""]
	cm2.ended.connect(func(r: String) -> void: outcome[0] = r)
	var guard_turns := 0
	while outcome[0] == "" and guard_turns < 30:
		cm2.end_player_turn()
		guard_turns += 1
	check(outcome[0] == "defeat" and cm2.party.is_wiped(), "passing every turn ends in defeat")
	var cm3 := _new_combat("castle_training_01", 1)
	cm3.party_combatants[0].hp = 0
	cm3.enemies[0].hp = 1
	cm3.play_card(_find_card(cm3, "bianca", "bianca_tanking_strike"))
	check(cm3.state == CombatManager.State.VICTORY and cm3.party.get_member("chiara").current_hp == GameConfig.FALLEN_REVIVE_HP, "fallen member revived at 1 HP after victory")


func _test_taunt() -> void:
	print("Taunt")
	var cm := _new_combat("castle_training_02", 11)
	var challenge := _find_card(cm, "bianca", "bianca_tanking_challenge")
	check(cm.needs_target_choice(challenge), "2 enemies need explicit target")
	check(not cm.play_card(challenge, ""), "playing without target is rejected")
	check(cm.play_card(challenge, cm.enemies[0].id), "taunt with target")
	check(cm.enemies[0].has_status("taunt"), "enemy taunted")
	cm.enemies[0].intent.type = EnemyIntent.TYPE_ATTACK
	check(cm.get_intent_target(cm.enemies[0]).id == "bianca", "taunted enemy targets Bianca")


func _test_map() -> void:
	print("Map")
	var graph := MapGraph.from_dict(DataRegistry.get_map("royal_castle_tutorial"))
	check(graph.validate().is_empty(), "tutorial map valid")
	check(graph.nodes.size() == 9, "9 nodes")
	var progress := MapProgress.new(graph)
	check(progress.current_node_id == "royal_chambers", "starts in Royal Chambers")
	check(progress.get_available_ids().size() == 2, "2 routes from start")
	check(not progress.travel_to("throne_approach"), "unconnected node rejected")
	check(not progress.travel_to("royal_chambers"), "current node rejected")
	check(progress.travel_to("west_gallery"), "valid move")
	check(progress.get_node_state("west_gallery") == MapProgress.NodeState.CURRENT, "current state")
	check(progress.get_node_state("royal_chambers") == MapProgress.NodeState.VISITED, "visited state")
	check(not progress.travel_to("royal_chambers"), "cannot go back to visited")
	check(not progress.travel_to("training_yard"), "sibling branch not reachable from here")
	check(progress.travel_to("central_courtyard") and progress.travel_to("royal_library") and progress.travel_to("throne_approach") and progress.travel_to("castle_exit"), "route to exit")
	check(progress.is_at_exit(), "reached exit")
	var boss_found := false
	for node: MapNodeData in graph.nodes.values():
		boss_found = boss_found or node.type == "boss"
	check(not boss_found, "no boss node")
	var broken := DataRegistry.get_map("royal_castle_tutorial").duplicate(true)
	broken["nodes"][0]["next"] = ["nowhere"]
	check(not MapGraph.from_dict(broken).validate().is_empty(), "validation catches broken links")


func _test_rest_and_merchant() -> void:
	print("Rest and merchant")
	var party := _make_party()
	party.get_member("chiara").current_hp = 10
	party.get_member("bianca").current_hp = 0
	var restored := party.rest(0.5)
	check(party.get_member("chiara").current_hp == 40 and restored["chiara"] == 30, "rest heals 50% of max HP")
	check(not restored.has("bianca") and not party.get_member("bianca").is_alive(), "rest does not revive fallen")
	var inv := Inventory.new()
	inv.gold = 40
	var shop := Merchant.from_definition(DataRegistry.get_shop("castle_potions_01"))
	check(shop.buy("health_potion", inv) == "" and inv.gold == 10 and inv.count_of("health_potion") == 1, "purchase potion")
	check(shop.buy("health_potion", inv) != "", "cannot afford second potion")
	check(shop.buy("not_an_item", inv) != "", "unknown item rejected")
	inv.gold = 500
	shop.buy("health_potion", inv)
	check(shop.buy("health_potion", inv) != "" and shop.get_quantity("health_potion") == 0, "stock runs out")
	# Potion in combat
	var cm := _new_combat("castle_training_01", 2)
	cm.inventory.add_item("minor_health_potion")
	cm.party_combatants[0].hp = 20
	check(cm.use_potion("minor_health_potion") == "" and cm.party_combatants[0].hp == 35, "potion heals most wounded member")
	check(cm.use_potion("minor_health_potion") != "", "no potion left")
