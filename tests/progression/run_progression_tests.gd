extends SceneTree
## Milestone 2 logic tests: card rewards, upgrades, save/load. Run:
##   godot --headless --path . --script res://tests/progression/run_progression_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	_test_card_rewards()
	_test_card_upgrades()
	_test_save_load()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _make_party() -> Party:
	return Party.from_selection({"chiara": "arcana", "bianca": "tanking"})


func _test_card_rewards() -> void:
	print("Card rewards")
	var party := _make_party()
	var rng := RandomNumberGenerator.new()
	var all_valid := true
	var owners := {}
	for seed_value in 50:
		rng.seed = seed_value
		var reward := CardReward.generate(party, rng)
		var ids: Array[String] = []
		for option in reward.options:
			var member := party.get_member(option["owner_character_id"])
			var def := DataRegistry.get_card(option["card_id"])
			all_valid = all_valid and member != null and member.specialization.card_pool.has(option["card_id"]) \
				and def.owner_character_id == member.id and not ids.has(option["card_id"])
			ids.append(option["card_id"])
			owners[member.id] = true
		all_valid = all_valid and reward.options.size() == 3
	check(all_valid, "50 seeds: 3 distinct options, each from its owner's specialization pool")
	check(owners.has("chiara") and owners.has("bianca"), "rewards offer cards for both characters")

	rng.seed = 1
	var reward := CardReward.generate(party, rng)
	var option: Dictionary = reward.options[0]
	var owner := party.get_member(option["owner_character_id"])
	var other := party.get_member("bianca" if owner.id == "chiara" else "chiara")
	var added := reward.choose(0, party)
	check(added != null and owner.deck.size() == 11 and other.deck.size() == 10, "choosing adds one card to the owner's deck only")
	check(added.owner_character_id == owner.id and added.card_id == option["card_id"] and added.upgrade_level == 0, "new card keeps ownership")
	check(reward.choose(1, party) == null and owner.deck.size() == 11, "a reward can only be claimed once")

	var skipped := CardReward.generate(party, rng)
	skipped.skip()
	check(skipped.choose(0, party) == null and party.get_total_deck_size() == 21, "skipping adds nothing and resolves the reward")

	var forged := CardReward.new()
	forged.options.append({"card_id": "bianca_tanking_slam", "owner_character_id": "chiara"})
	check(forged.choose(0, party) == null, "card outside the owner's pool is rejected")

	var deck := PartyDeck.new()
	deck.build_from_party(party)
	var found := deck.draw_pile.filter(func(c: CardInstance) -> bool: return c.owned_uid == added.uid)
	check(deck.draw_pile.size() == 21 and found.size() == 1 and found[0].owner_character_id == owner.id, "next combat's party deck contains the new card with its owner")

	var dup_a := owner.add_card(added.card_id)
	var dup_b := owner.add_card(added.card_id)
	var uids := {}
	for owned in owner.deck:
		uids[owned.uid] = true
	check(uids.size() == owner.deck.size() and dup_a.uid != dup_b.uid, "owned-card uids stay unique with duplicate card ids")
	var deck2 := PartyDeck.new()
	deck2.build_from_party(party)
	var instance_ids := {}
	for card in deck2.draw_pile:
		instance_ids[card.instance_id] = true
	check(instance_ids.size() == deck2.draw_pile.size() and deck2.draw_pile.size() == 23, "runtime instance ids are unique for duplicates")

	var small_party := Party.new()
	small_party.add_member(PartyMember.create(DataRegistry.get_character("chiara"), DataRegistry.get_specialization("arcana")))
	rng.seed = 2
	check(CardReward.generate(small_party, rng).options.all(func(o: Dictionary) -> bool: return o["owner_character_id"] == "chiara"), "rewards follow the active party members")


func _test_card_upgrades() -> void:
	print("Card upgrades")
	var party := _make_party()
	var chiara := party.get_member("chiara")
	var raw_before := JSON.stringify(DataRegistry.get_card("chiara_arcana_bolt").raw)
	var bolts := chiara.deck.filter(func(o: OwnedCard) -> bool: return o.card_id == "chiara_arcana_bolt")
	check(CardUpgrader.can_upgrade(bolts[0]) == "", "starter card is upgradable")
	check(CardUpgrader.upgrade(chiara, bolts[0].uid) == "", "upgrade succeeds")
	check(bolts[0].upgrade_level == 1 and bolts[1].upgrade_level == 0, "only the chosen copy is upgraded")
	check(CardUpgrader.upgrade(chiara, bolts[0].uid) != "", "cannot exceed max level")
	check(CardUpgrader.upgrade(party.get_member("bianca"), bolts[0].uid) != "", "cannot upgrade another character's card")
	check(JSON.stringify(DataRegistry.get_card("chiara_arcana_bolt").raw) == raw_before, "static definition unchanged by upgrading")
	check(CardUpgrader.get_upgradable_cards(chiara).size() == 9, "upgraded copy no longer offered again")

	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new(), 4)
	cm.start()
	cm.deck.hand.append_array(cm.deck.draw_pile)
	cm.deck.draw_pile.clear()
	var upgraded: CardInstance = cm.deck.hand.filter(func(c: CardInstance) -> bool: return c.owned_uid == bolts[0].uid)[0]
	check(upgraded.is_upgraded() and upgraded.get_card_name() == "Arcane Bolt+" and upgraded.owner_character_id == "chiara", "upgrade carries into the combat instance")
	cm.play_card(upgraded)
	check(cm.enemies[0].hp == 26 - 9, "upgraded effect applies (9 damage)")
	var plain: CardInstance = cm.deck.hand.filter(func(c: CardInstance) -> bool: return c.owned_uid == bolts[1].uid)[0]
	check(plain.get_effects()[0]["value"] == 6, "non-upgraded copy keeps base effect")
	var challenge := CardInstance.new()
	challenge.definition = DataRegistry.get_card("bianca_tanking_challenge")
	challenge.upgrade_level = 1
	check(challenge.get_cost() == 0, "upgrade data can change cost")
	check(CardUpgrader.get_max_level(DataRegistry.get_card("bianca_tanking_wall")) == 1, "pool cards define upgrades in data")


func _test_save_load() -> void:
	print("Save / load")
	var path := "user://test_save.json"
	var party := _make_party()
	var chiara := party.get_member("chiara")
	chiara.add_card("chiara_arcana_lance")
	CardUpgrader.upgrade(chiara, chiara.deck[0].uid)
	chiara.current_hp = 33
	party.get_member("bianca").current_hp = 0
	var inventory := Inventory.new()
	inventory.gold = 77
	inventory.add_item("health_potion", 2)
	var progress := MapProgress.new(MapGraph.from_dict(DataRegistry.get_map("royal_castle_tutorial")))
	progress.travel_to("training_yard")
	progress.travel_to("east_armory")
	check(SaveManager.write_file(path, SaveManager.serialize(party, inventory, progress)), "save file written")
	var read := SaveManager.read_file(path)
	var restored := SaveManager.restore(read["data"])
	check(read["ok"] and restored["ok"], "save file read and validated")
	var p2: Party = restored["party"]
	var c2 := p2.get_member("chiara")
	check(c2.specialization.id == "arcana" and p2.get_member("bianca").specialization.id == "tanking", "specializations restored")
	check(c2.current_hp == 33 and p2.get_member("bianca").current_hp == 0, "health restored")
	check(c2.deck.size() == 11 and p2.get_member("bianca").deck.size() == 10, "individual decks restored")
	check(c2.deck[0].upgrade_level == 1 and c2.deck[0].uid == chiara.deck[0].uid, "upgrade and uid restored")
	check(c2.deck.any(func(o: OwnedCard) -> bool: return o.card_id == "chiara_arcana_lance" and o.owner_character_id == "chiara"), "reward card restored with owner")
	var inv2: Inventory = restored["inventory"]
	check(inv2.gold == 77 and inv2.count_of("health_potion") == 2, "inventory and gold restored")
	var map2: MapProgress = restored["progress"]
	check(map2.current_node_id == "east_armory" and map2.visited_ids == progress.visited_ids, "map position restored")
	check(map2.can_travel_to("training_yard") != "" and map2.can_travel_to("throne_approach") == "", "restored map keeps move rules")
	var again := c2.add_card("chiara_arcana_lance")
	check(c2.deck.filter(func(o: OwnedCard) -> bool: return o.uid == again.uid).size() == 1, "new cards after loading get unique uids")
	DirAccess.remove_absolute(path)
	check(not FileAccess.file_exists(path), "test save removed")

	var good := SaveManager.serialize(party, inventory, progress)
	check(not SaveManager.restore("garbage")["ok"], "non-dictionary save rejected")
	check(not SaveManager.restore({})["ok"], "empty save rejected")
	var future := good.duplicate(true)
	future["version"] = 99
	check(not SaveManager.restore(future)["ok"], "newer save version rejected")
	var old := good.duplicate(true)
	old.erase("version")
	check(SaveManager.restore(old)["ok"], "save without version migrates")
	var sparse := {"party": [{"character_id": "chiara", "specialization_id": "arcana"}], "map": {"current_node_id": "royal_chambers"}}
	var sparse_result := SaveManager.restore(sparse)
	check(sparse_result["ok"] and sparse_result["party"].get_member("chiara").deck.size() == 10 and sparse_result["party"].get_member("chiara").current_hp == 60 and sparse_result["inventory"].gold == 0, "missing fields fall back to safe defaults")
	var dirty := good.duplicate(true)
	dirty["party"][0]["deck"].append({"uid": "x", "card_id": "removed_card", "upgrade_level": 5})
	dirty["party"][0]["deck"][1]["upgrade_level"] = 9
	dirty["party"][0]["current_hp"] = 9999
	dirty["inventory"]["items"]["ghost_item"] = 3
	dirty["inventory"]["gold"] = -5
	var dirty_result := SaveManager.restore(dirty)
	var d_chiara: PartyMember = dirty_result["party"].get_member("chiara")
	check(dirty_result["ok"] and d_chiara.deck.size() == 11 and d_chiara.current_hp == 60, "unknown cards dropped, HP clamped")
	check(d_chiara.deck[1].upgrade_level == 1 and dirty_result["inventory"].gold == 0 and dirty_result["inventory"].count_of("ghost_item") == 0, "upgrade level, gold and items sanitised")
	check(dirty_result["warnings"].size() >= 2, "warnings reported for dropped data")
	var dup_uid := good.duplicate(true)
	dup_uid["party"][0]["deck"][1]["uid"] = dup_uid["party"][0]["deck"][0]["uid"]
	var dup_result := SaveManager.restore(dup_uid)
	var uid_set := {}
	for owned in dup_result["party"].get_member("chiara").deck:
		uid_set[owned.uid] = true
	check(dup_result["ok"] and uid_set.size() == 11, "duplicate uids in a save are repaired")
	var bad_spec := good.duplicate(true)
	bad_spec["party"][0]["specialization_id"] = "tanking"
	check(not SaveManager.restore(bad_spec)["ok"], "specialization of the wrong character rejected")
	var bad_node := good.duplicate(true)
	bad_node["map"]["current_node_id"] = "nowhere"
	check(not SaveManager.restore(bad_node)["ok"], "invalid map position rejected")
	var bad_map := good.duplicate(true)
	bad_map["map"]["map_id"] = "no_such_map"
	check(not SaveManager.restore(bad_map)["ok"], "unknown map rejected")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	check(not SaveManager.read_file(path)["ok"], "corrupt file reported")
	DirAccess.remove_absolute(path)
	check(not SaveManager.read_file(path)["ok"], "missing file reported")
