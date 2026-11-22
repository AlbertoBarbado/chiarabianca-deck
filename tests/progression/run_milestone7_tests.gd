extends SceneTree
## Milestone 7 logic tests: Arcana / Tanking passives (and later: removal, elites, treasure, saves). Run:
##   godot --headless --path . --script res://tests/progression/run_milestone7_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	_test_arcana_passive()
	_test_tanking_passive()
	_test_fallen_owner_cards()
	_test_card_removal()
	_test_elites()
	_test_treasure_and_relics()
	_test_save_format()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(chiara_spec: String, bianca_spec: String, encounter: String = "castle_training_01", seed_value: int = 4) -> CombatManager:
	var party := Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})
	for spec_id in [chiara_spec, bianca_spec]:
		var spec := DataRegistry.get_specialization(spec_id)
		for card_id in spec.card_pool:
			party.get_member(spec.character_id).add_card(card_id)
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter(encounter), Inventory.new(), seed_value)
	cm.start()
	cm.energy = 20
	return cm


func _to_hand(cm: CombatManager, card_id: String) -> CardInstance:
	for pile: Array[CardInstance] in [cm.deck.hand, cm.deck.draw_pile, cm.deck.discard_pile]:
		for card in pile:
			if card.definition.id == card_id:
				if pile != cm.deck.hand:
					pile.erase(card)
					cm.deck.hand.append(card)
				return card
	return null


func _play(cm: CombatManager, card_id: String, target_id: String = "") -> bool:
	var card := _to_hand(cm, card_id)
	return card != null and cm.play_card(card, target_id)


func _counter(cm: CombatManager) -> Array[int]:
	var count: Array[int] = [0]
	cm.passives.triggered.connect(func(_o: String, _p: String, _t: String) -> void: count[0] += 1)
	return count


func _attack(cm: CombatManager, enemy: Combatant, target_id: String, damage: int) -> void:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.TYPE_ATTACK
	intent.value = damage
	intent.action_name = "Test Strike"
	intent.planned_target_id = target_id
	enemy.intent = intent
	cm._execute_intent(enemy)


func _test_arcana_passive() -> void:
	print("Arcana passive: Arcane Flow")
	var cm := _combat("arcana", "tanking")
	var count := _counter(cm)
	var events: Array[String] = []
	cm.visual_event.connect(func(e: Dictionary) -> void: events.append(str(e.get("kind", ""))))
	cm.enemies[0].max_hp = 500
	cm.enemies[0].hp = 500  # the fight must not end mid-test
	var enemy_id := cm.enemies[0].id
	_play(cm, "chiara_arcana_bolt", enemy_id)
	check(count[0] == 0, "Chiara first card of the turn: no trigger")
	_to_hand(cm, "bianca_tanking_strike")
	var hand_before := cm.deck.hand.size()
	_play(cm, "bianca_tanking_strike", enemy_id)
	check(count[0] == 0 and cm.deck.hand.size() == hand_before - 1, "Bianca's card never triggers it")
	_to_hand(cm, "chiara_arcana_bolt")
	hand_before = cm.deck.hand.size()
	_play(cm, "chiara_arcana_bolt", enemy_id)
	check(count[0] == 1 and cm.deck.hand.size() == hand_before, "Chiara after Bianca: one extra draw (card leaves the hand, one drawn)")
	check(events.has("draw"), "a draw visual event is emitted")
	_play(cm, "bianca_tanking_strike", enemy_id)
	_play(cm, "chiara_arcana_bolt", enemy_id)
	check(count[0] == 1, "limited to once per turn")
	cm.end_player_turn()
	_play(cm, "chiara_arcana_bolt", enemy_id)
	_play(cm, "chiara_arcana_bolt", enemy_id)
	check(count[0] == 1, "Chiara after Chiara never triggers")
	cm.passives.on_event({"type": "card_played", "source": cm.get_combatant("chiara"), "previous_owner_id": "bianca"})
	check(count[0] == 2, "the limit resets on the next turn and the order Bianca -> Chiara works again")

	var fallen := _combat("arcana", "tanking", "castle_training_01", 9)
	var fallen_count := _counter(fallen)
	_play(fallen, "bianca_tanking_strike", fallen.enemies[0].id)
	fallen.get_combatant("chiara").take_damage(999)
	fallen.passives.on_event({"type": "card_played", "source": fallen.get_combatant("chiara"), "previous_owner_id": "bianca"})
	check(fallen_count[0] == 0, "a fallen Chiara never triggers it")
	cm.passives.reset_turn()
	cm.passives.on_event({"type": "card_played", "source": cm.get_combatant("chiara"), "previous_owner_id": ""})
	check(count[0] == 2, "an event with no previous card is invalid for the trigger")
	var other := _combat("fire", "tanking", "castle_training_01", 5)
	check(not other.passives.has_passive("chiara") or other.passives.is_ready("chiara"), "other specializations are unaffected")


func _test_tanking_passive() -> void:
	print("Tanking passive: Bulwark Stance")
	var cm := _combat("arcana", "tanking")
	var count := _counter(cm)
	var bianca := cm.get_combatant("bianca")
	var chiara := cm.get_combatant("chiara")
	var enemy := cm.enemies[0]
	bianca.add_block(10)
	_attack(cm, enemy, "bianca", 6)
	check(bianca.block == 4 and count[0] == 1 and enemy.has_status("taunt"), "an attack fully absorbed by Block taunts the attacker")
	check(enemy.get_status_source("taunt") == "bianca", "the taunt points at Bianca")
	var other := cm.enemies[1] if cm.enemies.size() > 1 else null
	_attack(cm, enemy, "bianca", 2)
	check(count[0] == 1, "once per round")
	cm.passives.reset_turn()
	bianca.block = 3
	_attack(cm, enemy, "bianca", 8)
	check(count[0] == 1 and bianca.hp < bianca.max_hp, "damage that gets through Block does not trigger it")
	bianca.block = 0
	_attack(cm, enemy, "bianca", 4)
	check(count[0] == 1, "no Block, no trigger")
	chiara.add_block(20)
	_attack(cm, enemy, "chiara", 5)
	check(count[0] == 1, "an absorbed attack on Chiara does not trigger it")
	bianca.hp = bianca.max_hp
	bianca.block = 0
	cm.passives.reset_turn()
	cm.enemies[0].statuses.erase("taunt")
	bianca.add_block(10)
	bianca.take_damage(999, true)
	bianca.clear_combat_state()
	_attack(cm, enemy, "bianca", 3)
	check(count[0] == 1, "a fallen Bianca never triggers it")
	check(other == null or not other.has_status("taunt"), "other enemies are not taunted")


# --- Card removal ------------------------------------------------------------

func _party(chiara_spec: String = "fire", bianca_spec: String = "holy") -> Party:
	return Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})


func _test_card_removal() -> void:
	print("Card removal")
	var party := _party()
	var inventory := Inventory.new()
	var chiara := party.get_member("chiara")
	var bianca := party.get_member("bianca")
	check(CardRemoval.is_enabled(), "card removal is enabled by data (run_rules.json)")
	var target := chiara.deck[0]
	var other_uid := chiara.deck[1].uid
	chiara.deck[1].upgrade_level = 1
	var bianca_size := bianca.deck.size()
	check(CardRemoval.can_remove(party, inventory, "chiara", target.uid, 0) == "", "a normal removal is allowed")
	check(CardRemoval.remove(party, inventory, "chiara", target.uid, 0) == "", "removal succeeds")
	check(chiara.deck.size() == 9 and chiara.find_card(target.uid) == null, "only Chiara's deck loses that card")
	check(bianca.deck.size() == bianca_size, "Bianca's deck is untouched")
	check(chiara.find_card(other_uid) != null and chiara.find_card(other_uid).upgrade_level == 1, "other cards and their upgrades are preserved")
	var deck := PartyDeck.new()
	deck.build_from_party(party)
	check(deck.draw_pile.size() == 19, "the rebuilt party deck has one card less (19)")
	check(CardRemoval.remove(party, inventory, "chiara", chiara.deck[0].uid, 1) != "", "uses_per_rest limit: a second removal in the same visit is rejected")
	check(CardRemoval.remove(party, inventory, "chiara", "no_such_uid", 0) != "", "an unknown card is rejected")
	check(CardRemoval.remove(party, inventory, "bianca", chiara.deck[0].uid, 0) != "", "a card cannot be removed through the wrong owner")
	check(CardRemoval.remove(party, inventory, "nobody", "x", 0) != "", "an unknown character is rejected")
	while chiara.deck.size() > 6:
		chiara.remove_card(chiara.deck[0].uid)
	check(CardRemoval.remove(party, inventory, "chiara", chiara.deck[0].uid, 0) != "" and chiara.deck.size() == 6, "the minimum deck size per character (6) blocks further removal")
	var paid := {"card_removal": {"gold_cost": 25}}
	check(CardRemoval.remove(party, inventory, "bianca", bianca.deck[0].uid, 0, paid) != "", "a node-defined cost needs gold")
	inventory.gold = 30
	check(CardRemoval.remove(party, inventory, "bianca", bianca.deck[0].uid, 0, paid) == "" and inventory.gold == 5, "the cost is read from data and charged")
	check(not CardRemoval.is_enabled({"card_removal": {"enabled": false}}), "a node can disable removal")


# --- Elite encounters --------------------------------------------------------

func _test_elites() -> void:
	print("Elite encounters")
	for id in ["elite_commander_01", "elite_vanguard_01"]:
		var enc := DataRegistry.get_encounter(id)
		check(bool(enc.get("elite", false)) and not (enc.get("enemies", []) as Array).is_empty(), "%s is a data-defined elite encounter" % id)
		for enemy_id: String in enc["enemies"]:
			check(DataRegistry.get_enemy(enemy_id) != null, "  enemy %s exists" % enemy_id)
	var commander := DataRegistry.get_enemy("elite_knight_commander")
	check(commander.elite and commander.max_hp > DataRegistry.get_enemy("hall_captain").max_hp, "the elite commander is stronger than the regular captain")
	check(CombatPresentation.enemy_set("elite_knight_commander") == "knight_captain" and CombatPresentation.enemy_set("elite_vanguard_knight") == "knight_generic", "elites reuse the existing knight and captain art through data")
	var cm := _combat("fire", "holy", "elite_commander_01", 3)
	check(cm.is_elite and cm.intro_text != "" and cm.enemies.size() == 2, "the combat knows it is elite and has an intro")
	check(cm.enemies[0].intent != null and cm.enemies[0].intent.value > 0, "elite intents are announced like normal ones")
	cm.get_combatant("bianca").add_block(20)
	var before := cm.get_combatant("bianca").block
	_attack(cm, cm.enemies[0], "bianca", 11)
	check(cm.get_combatant("bianca").block == before - 11, "elite attacks use the normal Block rules")
	_play(cm, "chiara_fire_kindle", cm.enemies[0].id)
	check(cm.enemies[0].has_status("burn"), "statuses work on elites")
	var plain := CardReward.generate(_party(), _rng(1), 3, {})
	var elite := CardReward.generate(_party(), _rng(1), 3, RunRules.get_block("elite_defaults"))
	check(plain.options.size() == 3 and elite.options.size() == 4, "elite rewards offer more cards (4 vs 3)")
	var guaranteed := true
	for seed_value in 20:
		var reward := CardReward.generate(_party(), _rng(seed_value), 3, RunRules.get_block("elite_defaults"))
		var best := 0
		for option in reward.options:
			best = maxi(best, CardReward._rarity_rank(DataRegistry.get_card(option["card_id"]).rarity))
		guaranteed = guaranteed and best >= CardReward._rarity_rank("uncommon")
	check(guaranteed, "every elite reward has at least one uncommon or better card (20 seeds)")
	check(int(DataRegistry.get_encounter("elite_commander_01")["gold_reward"]) > int(DataRegistry.get_encounter("castle_final_regular_01")["gold_reward"]), "elite gold beats the regular final fight")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Treasure and relics -----------------------------------------------------

func _test_treasure_and_relics() -> void:
	print("Treasure and relics")
	var party := _party()
	var inventory := Inventory.new()
	var state := TreasureRoom.generate("castle_treasure_01", party, inventory, _rng(5))
	var types: Array = (state["choices"] as Array).map(func(c: Dictionary) -> String: return c["type"])
	check(types == ["gold", "potion", "relic", "card", "equipment"], "all five configured choices are offered (equipment included)")
	var again := TreasureRoom.generate("castle_treasure_01", party, inventory, _rng(5))
	check(again == state, "the offer is deterministic for the same roll (so a saved offer never rerolls)")
	check(TreasureRoom.claim(state, 9, party, inventory) != "" and int(state["taken"]) == -1, "an invalid index is rejected")
	check(TreasureRoom.claim(state, 0, party, inventory) == "" and inventory.gold == 60, "claiming gold adds it")
	check(TreasureRoom.claim(state, 1, party, inventory) != "" and inventory.count_of("health_potion") == 0, "a second claim in the same room is rejected (no duplicate exploit)")
	var relic_state := TreasureRoom.generate("castle_treasure_01", party, inventory, _rng(6))
	var relic_id: String = relic_state["choices"][2]["item_id"]
	check(TreasureRoom.claim(relic_state, 2, party, inventory) == "" and inventory.has_relic(relic_id), "claiming a relic adds it to the inventory")
	check(not inventory.add_relic(relic_id), "the same relic cannot be owned twice")
	var second := TreasureRoom.generate("castle_treasure_01", party, inventory, _rng(7))
	var second_relic: Array = (second["choices"] as Array).filter(func(c: Dictionary) -> bool: return c["type"] == "relic")
	check(second_relic.is_empty() or second_relic[0]["item_id"] != relic_id, "an owned relic is never offered again")
	inventory.relics.clear()
	for id in RelicEffects.all_relics():  # every relic a chest can offer (boss relics never come from chests)
		if str(DataRegistry.get_item(id).get("rarity", "common")) != "boss":
			inventory.add_relic(id)
	var none_left := TreasureRoom.generate("castle_treasure_01", party, inventory, _rng(8))
	check(not (none_left["choices"] as Array).any(func(c: Dictionary) -> bool: return c["type"] == "relic"), "with every relic owned the relic choice disappears")
	var card_state := TreasureRoom.generate("castle_treasure_01", party, Inventory.new(), _rng(9))
	var card_choice: Dictionary = card_state["choices"][3]
	var owner_deck := party.get_member(card_choice["owner_character_id"]).deck.size()
	check(TreasureRoom.claim(card_state, 3, party, Inventory.new()) == "" and party.get_member(card_choice["owner_character_id"]).deck.size() == owner_deck + 1, "a card choice adds the card to its owner's deck")
	# Relic effects in combat.
	var cm := CombatManager.new()
	var inv := Inventory.new()
	inv.add_relic("guardian_locket")
	inv.add_relic("scholars_satchel")
	cm.setup(_party(), DataRegistry.get_encounter("castle_training_01"), inv, 4)
	cm.start()
	check(cm.get_combatant("chiara").block == 4 and cm.get_combatant("bianca").block == 4, "Guardian's Locket gives 4 Block at the start of a battle")
	check(cm.deck.hand.size() == CombatManager.HAND_SIZE + 1, "Scholar's Satchel draws 1 extra card on the first turn")
	cm.end_player_turn()
	check(cm.deck.hand.size() == CombatManager.HAND_SIZE, "relic draw applies to the first turn only")
	check(RelicEffects.total(null, "combat_start_block") == 0, "no inventory, no relic effects")


# --- Save format -------------------------------------------------------------

func _test_save_format() -> void:
	print("Save format")
	var party := _party("arcana", "tanking")
	party.get_member("chiara").remove_card(party.get_member("chiara").deck[0].uid)
	party.get_member("bianca").deck[0].upgrade_level = 1
	var inventory := Inventory.new()
	inventory.gold = 77
	inventory.add_relic("healers_pendant")
	var graph := MapGraph.from_dict(DataRegistry.get_map("castle_elite_demo"))
	check(graph.validate().is_empty(), "the elite demo map is a valid graph")
	var progress := MapProgress.new(graph)
	progress.travel_to("demo_fight")
	progress.travel_to("demo_elite")
	var reward := CardReward.generate(party, _rng(2), 3, {})
	var room := {"node_id": "demo_elite", "kind": "elite", "phase": "reward", "gold": 45}
	var data := SaveManager.serialize(party, inventory, progress, room, reward)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var restored := SaveManager.restore(parsed)
	check(restored["ok"] and (restored["party"] as Party).get_member("chiara").deck.size() == 9, "round trip keeps the removed card removed")
	check((restored["party"] as Party).get_member("bianca").deck[0].upgrade_level == 1, "round trip keeps upgrades")
	check((restored["inventory"] as Inventory).gold == 77 and (restored["inventory"] as Inventory).has_relic("healers_pendant"), "round trip keeps gold and relics")
	check((restored["progress"] as MapProgress).current_node_id == "demo_elite", "round trip keeps the map position on the new node types")
	check(restored["room"]["node_id"] == "demo_elite" and restored["room"]["phase"] == "reward" and int(restored["room"]["gold"]) == 45 and restored["reward"] != null and (restored["reward"] as CardReward).options.size() == 3, "round trip keeps the room phase and the saved reward")
	var wrong_room := data.duplicate(true)
	wrong_room["room"] = {"node_id": "demo_fight", "kind": "combat"}
	var dropped := SaveManager.restore(JSON.parse_string(JSON.stringify(wrong_room)))
	check(dropped["ok"] and (dropped["room"] as Dictionary).is_empty() and dropped["reward"] == null, "a room that does not match the map position is dropped, the run still loads")
	var bad_kind := data.duplicate(true)
	bad_kind["room"] = {"node_id": "demo_elite", "kind": "banana"}
	check((SaveManager.restore(JSON.parse_string(JSON.stringify(bad_kind))) as Dictionary)["room"] == {}, "an unknown room kind is dropped")
	var legacy := {"version": 1, "party": data["party"], "inventory": {"gold": 12, "items": {"health_potion": 2}}, "map": {"map_id": "royal_castle_tutorial", "current_node_id": "royal_chambers", "visited": ["royal_chambers"]}}
	var old := SaveManager.restore(legacy)
	check(old["ok"] and (old["room"] as Dictionary).is_empty() and old["reward"] == null and (old["inventory"] as Inventory).relics.is_empty() and (old["inventory"] as Inventory).gold == 12, "a version 1 save still loads (no room, no relics)")
	check(not SaveManager.restore({"version": 99, "party": []})["ok"] and not SaveManager.restore("garbage")["ok"], "newer-version and invalid saves are rejected with an error, not a crash")
	var unknown_relic := data.duplicate(true)
	unknown_relic["inventory"]["relics"] = ["healers_pendant", "made_up_relic", "healers_pendant"]
	var cleaned := SaveManager.restore(JSON.parse_string(JSON.stringify(unknown_relic)))
	check((cleaned["inventory"] as Inventory).relics == ["healers_pendant"], "unknown and duplicate relics are dropped when loading")
	# Files: backup and corrupt handling.
	var path := "user://test_m7_save.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	check(SaveManager.write_file(path, data) and SaveManager.write_file(path, data), "saving twice works and leaves a backup")
	check(FileAccess.file_exists(path + ".bak"), "the previous good save is kept as .bak")
	var damaged := FileAccess.open(path, FileAccess.WRITE)
	damaged.store_string("{ not json")
	damaged.close()
	var read := SaveManager.read_file(path)
	check(read["ok"] and bool(read["from_backup"]), "a damaged main save is recovered from the backup")
	DirAccess.remove_absolute(path + ".bak")
	check(not SaveManager.read_file(path)["ok"] and FileAccess.file_exists(path), "with no backup a corrupt save gives an error and is NOT deleted")
	check(not SaveManager.read_file("user://does_not_exist.json")["ok"], "a missing save gives an error")
	DirAccess.remove_absolute(path)


# --- Fallen characters stop contributing cards ----------------------------------

func _test_fallen_owner_cards() -> void:
	print("Fallen owner's cards")
	var cm := _combat("fire", "holy", "castle_final_regular_01", 12)
	cm.enemies[0].max_hp = 500
	cm.enemies[0].hp = 500
	var total := cm.deck.get_total_card_count()
	cm.get_combatant("chiara").take_damage(999)
	_play(cm, "bianca_holy_shield")  # any action runs the end-of-action cleanup
	var chiara_cards := 0
	for pile: Array[CardInstance] in [cm.deck.draw_pile, cm.deck.hand, cm.deck.discard_pile]:
		for card in pile:
			if card.owner_character_id == "chiara":
				chiara_cards += 1
	check(chiara_cards == 0 and cm.deck.set_aside.size() > 0, "a fallen character's cards leave the draw pile, hand and discard pile")
	check(cm.deck.get_total_card_count() == total, "no card is lost: they are set aside for the rest of the combat")
	cm.end_player_turn()
	var only_bianca := cm.deck.hand.all(func(c: CardInstance) -> bool: return c.owner_character_id == "bianca")
	check(cm.state == CombatManager.State.PLAYER_TURN and cm.deck.hand.size() > 0 and only_bianca, "the next hand only contains the remaining character's cards")
	for i in 12:
		cm.deck.draw(5)
	check(cm.deck.hand.all(func(c: CardInstance) -> bool: return c.owner_character_id == "bianca"), "reshuffles never bring the fallen character's cards back")
