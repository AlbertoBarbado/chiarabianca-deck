extends Node
## Logic tests of the persistent campaign (docs/PERSISTENT_RPG_DESIGN.md): campaign state, deck
## workshop rules, specialization mixing, permanent upgrades, refinement, fusion, potions, Sister Bond,
## expeditions (start, maps, objectives, save/load, retreat, victory, defeat, rewards once), world
## state and save migration. Runs as a scene because it uses the GameState autoload:
##   godot --headless --path . res://tests/campaign/campaign_logic_test.tscn

const SAVE := "user://test_campaign_logic.json"

var _failures := 0
var _checks := 0


func _ready() -> void:
	DataRegistry.ensure_loaded()
	GameState.save_path = SAVE
	GameState.delete_save()
	_test_data()
	_test_new_campaign()
	_test_deck_rules()
	_test_specialization_mixing()
	_test_upgrades_and_refinement()
	_test_potions()
	_test_fusion_and_bond()
	_test_generator()
	_test_expedition_lifecycle()
	_test_retreat_and_defeat()
	_test_objective_mission()
	_test_save_load()
	_test_world_state()
	_test_migration()
	_test_room_names()
	_test_levels()
	_test_dual_specialization()
	_test_contracts()
	_test_relic_tooltips()
	GameState.delete_save()
	GameState.save_path = GameConfig.SAVE_PATH
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _new_campaign(chiara := "fire", bianca := "holy") -> CampaignState:
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara)
	GameState.select_specialization("bianca", bianca)
	GameState.start_campaign()
	return GameState.campaign


## Every sister at the given level (missions and the dual specialization are level-gated).
func _set_level(campaign: CampaignState, level: int) -> void:
	for m in campaign.roster.members:
		campaign.levels[m.id] = Levels.threshold(level)
	campaign.refresh_roster()


## Plays the current expedition's map to its exit without fighting (rooms are skipped).
func _walk_to_exit() -> void:
	var progress := GameState.map_progress
	var guard := 0
	while progress.current_node_id != progress.graph.exit_node_id and guard < 64:
		guard += 1
		var options := progress.get_available_ids()
		if options.has(progress.graph.exit_node_id):
			progress.travel_to(progress.graph.exit_node_id)
		else:
			progress.travel_to(options[0])


func _test_data() -> void:
	var regions := ExpeditionService.regions()
	check(regions.size() == 5 and str(regions[0]["id"]) == "royal_castle" and ExpeditionService.missions_of("crystal_hollow").size() == 1, "five regions load (the castle grounds first; the Crystal Cave is a region of its own)")
	var problems: Array[String] = []
	for mission: Dictionary in DataRegistry.missions.values():
		if DataRegistry.get_region(str(mission.get("region_id", ""))).is_empty():
			problems.append(str(mission["id"]) + ": region")
		var spec: Dictionary = mission.get("map", {})
		var map_id := str(spec.get("map_id", spec.get("template", "")))
		if DataRegistry.get_map(map_id).is_empty():
			problems.append(str(mission["id"]) + ": map")
		if not Objectives.TYPES.has(str((mission.get("objective", {}) as Dictionary).get("type", ""))):
			problems.append(str(mission["id"]) + ": objective")
	for region: Dictionary in DataRegistry.regions.values():
		for mission_id: Variant in region.get("missions", []):
			if DataRegistry.get_mission(str(mission_id)).is_empty():
				problems.append(str(region["id"]) + ": " + str(mission_id))
	check(problems.is_empty(), "every mission names a known region, map and objective type (%s)" % ", ".join(problems))
	var old_maps := ["royal_castle_tutorial", "castle_elite_demo", "crystal_hollow_demo", "enchanted_forest", "sunlit_coast", "frostpeak"]
	check(old_maps.all(func(m: String) -> bool: return CampaignMigration.mission_for_map(m) != ""), "every existing map is played by a mission")
	var clear_target_types := DataRegistry.missions.values().filter(func(m: Dictionary) -> bool: return str(m["objective"]["type"]) == Objectives.TYPE_CLEAR_TARGETS).size()
	check(clear_target_types >= 3, "at least three missions use a non-boss objective (%d)" % clear_target_types)
	var recipe_problems: Array[String] = []
	for recipe in Fusion.all_recipes():
		var result := DataRegistry.get_card(str(recipe["result"]["card_id"]))
		if result == null or result.owner_character_id != str(recipe["result"]["owner"]) or result.rarity != "fusion":
			recipe_problems.append(str(recipe["id"]))
		for input: Dictionary in recipe["inputs"]:
			var def := DataRegistry.get_card(str(input["card_id"]))
			if def == null or def.owner_character_id != str(input["owner"]) or CardUpgrader.get_max_level(def) < int(input.get("min_upgrade", 0)):
				recipe_problems.append(str(recipe["id"]) + ":" + str(input["card_id"]))
	check(recipe_problems.is_empty() and Fusion.all_recipes().size() >= 3, "fusion recipes name real, upgradable inputs and a fusion result card (%s)" % ", ".join(recipe_problems))
	for service: Dictionary in DataRegistry.services.values():
		check(str(service.get("panel", service.get("screen", ""))) != "", "service %s opens something" % service["id"])
	var brews := DataRegistry.brew_recipes.values().all(func(r: Dictionary) -> bool: return str(DataRegistry.get_item(str(r["result"])).get("category", "")) == "potion")
	check(brews, "every brew makes a known potion")
	check(Bond.relics_all_known(), "every bond relic exists and is never rolled at random")


func _test_new_campaign() -> void:
	var campaign := _new_campaign()
	check(campaign != null and GameState.in_castle(), "a new campaign starts at the castle")
	check(GameState.party == campaign.roster and GameState.inventory == campaign.vault and GameState.map_progress == null, "at the castle the roster and vault are the active party and inventory")
	check(campaign.vault.gold == int(CampaignRules.block("start")["treasury"]) and campaign.potion_capacity == 3, "starting treasury and potion belt from the rules")
	check(campaign.prepared_uids("chiara").size() == 10 and campaign.prepared_uids("bianca").size() == 10, "each sister's prepared deck is her starting deck")
	check(DeckRules.validate_campaign(campaign).is_empty(), "the starting decks are valid")
	check(ExpeditionService.region_unlocked(campaign, "royal_castle") and not ExpeditionService.region_unlocked(campaign, "enchanted_forest"), "only the castle grounds are open at first")
	check(ExpeditionService.mission_lock_reason(campaign, "castle_awakening") == "" and ExpeditionService.mission_lock_reason(campaign, "castle_gauntlet") != "", "the first mission is open, the depths are locked")
	check(GameState.has_save(), "the castle autosaves")


func _test_deck_rules() -> void:
	var campaign := _new_campaign()
	var chiara := campaign.member("chiara")
	var ids: Array = campaign.prepared_cards("chiara").map(func(o: OwnedCard) -> String: return o.card_id)
	check(DeckRules.validate(chiara, ids).is_empty(), "the starter deck passes the rules")
	check(DeckRules.card_allowed(chiara, "bianca_holy_strike") != "", "Chiara cannot take Bianca's cards (ownership)")
	check(DeckRules.card_allowed(chiara, "chiara_frost_bolt") != "", "Chiara cannot take Frost cards with Fire primary and no secondary")
	check(DeckRules.can_add(chiara, ids, "chiara_fire_ember") != "", "a fifth copy of a basic card is refused (max 4)")
	check(DeckRules.validate(chiara, ids.slice(0, 5)).size() > 0, "a deck under the minimum is invalid")
	var too_many := ids.duplicate()
	for i in 6:
		too_many.append("chiara_fire_cinderward")
	check(DeckRules.validate(chiara, too_many).size() > 0, "too many cards and too many copies are invalid")
	# Edit, save as a preset, reset.
	var extra := campaign.add_collection_card("chiara", "chiara_fire_kindle")
	var uids := campaign.prepared_uids("chiara")
	uids.append(extra.uid)
	campaign.set_prepared("chiara", uids)
	check(campaign.prepared_uids("chiara").size() == 11, "a collection card can be added to the prepared deck")
	campaign.set_prepared("chiara", uids + ["not_a_uid", extra.uid])
	check(campaign.prepared_uids("chiara").size() == 11, "unknown and duplicate uids are ignored")
	campaign.presets["Burn"] = {"chiara": campaign.prepared_uids("chiara"), "bianca": campaign.prepared_uids("bianca")}
	campaign.reset_prepared_to_starter("chiara")
	check(campaign.prepared_uids("chiara").size() == 10 and not campaign.prepared_uids("chiara").has(extra.uid), "reset restores the recommended starting deck")
	campaign.remove_collection_card("chiara", extra.uid)
	check(not (campaign.presets["Burn"]["chiara"] as Array).has(extra.uid), "removing a card drops it from presets too")
	var restored := _save_and_reload()
	check(restored != null and restored.presets.has("Burn") and restored.prepared_uids("chiara").size() == 10, "presets and prepared decks survive a save")


func _test_specialization_mixing() -> void:
	var campaign := _new_campaign("fire", "tanking")
	check(CastleWorkshop.set_secondary(campaign, "chiara", "arcana") != "", "no secondary before level %d" % Levels.dual_spec_level())
	campaign.services.append("training_hall")
	campaign.vault.gold = 1000
	check(CastleWorkshop.unlock_spec(campaign, "chiara", "arcana") == "" and campaign.unlocked_specializations("chiara").has("arcana"), "the Training Hall teaches Arcana for gold")
	check(campaign.vault.gold == 1000 - CastleWorkshop.spec_unlock_price() and campaign.count_owned("chiara", "chiara_arcana_bolt") >= 3, "learning costs gold and adds the starting cards to the collection")
	check(CastleWorkshop.unlock_spec(campaign, "chiara", "earth") != "", "unfinished specializations cannot be learned")
	_set_level(campaign, Levels.dual_spec_level())
	check(CastleWorkshop.set_secondary(campaign, "chiara", "fire") != "", "the primary cannot also be the secondary")
	check(CastleWorkshop.set_secondary(campaign, "chiara", "arcana") == "", "Arcana becomes Chiara's secondary")
	var chiara := campaign.member("chiara")
	var ids: Array = campaign.prepared_cards("chiara").map(func(o: OwnedCard) -> String: return o.card_id)
	check(DeckRules.card_allowed(chiara, "chiara_arcana_bolt") == "", "secondary cards are allowed")
	var hybrid := ids.slice(0, 6)
	for card_id in ["chiara_arcana_bolt", "chiara_arcana_bolt", "chiara_arcana_ward", "chiara_arcana_focus"]:
		hybrid.append(card_id)
	check(DeckRules.validate(chiara, hybrid).is_empty(), "a hybrid deck within the secondary limit is valid")
	for card_id in ["chiara_arcana_ward", "chiara_arcana_focus", "chiara_arcana_bolt"]:
		hybrid.append(card_id)  # 7 secondary cards: one over the limit of 6
	check(DeckRules.validate(chiara, hybrid).size() > 0, "more than the secondary limit (%d) is refused" % int(DeckRules.rules().get("secondary_card_limit", 6)))
	# Hybrid deck into combat: the primary passive only, both specializations' cards play.
	var uids: Array[String] = []
	var taken := {}
	for card_id: String in hybrid.slice(0, 10):
		for owned in campaign.collection("chiara"):
			if owned.card_id == card_id and not taken.has(owned.uid):
				taken[owned.uid] = true
				uids.append(owned.uid)
				break
	campaign.set_prepared("chiara", uids)
	check(DeckRules.validate_campaign(campaign).is_empty(), "the hybrid party is ready to depart")
	var copy := ExpeditionService.clone_member(chiara, campaign.prepared_cards("chiara"))
	var party := Party.new()
	party.add_member(copy)
	party.add_member(ExpeditionService.clone_member(campaign.member("bianca"), campaign.prepared_cards("bianca")))
	var combat := CombatManager.new()
	combat.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new())
	check(combat.passives.has_passive("chiara") and combat.passives._entries.filter(func(e: Dictionary) -> bool: return e["owner_id"] == "chiara" and e["source"] == "specialization").size() == 1, "only the primary specialization's passive runs")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var secondary_seen := false
	for i in 40:
		var reward := CardReward.generate(party, rng)
		for option: Dictionary in reward.options:
			if DataRegistry.get_card(str(option["card_id"])).specialization_id == "arcana":
				secondary_seen = true
	check(secondary_seen, "rewards can offer the secondary specialization's cards")
	var reward := CardReward.new()
	reward.options = [{"card_id": DataRegistry.get_specialization("arcana").card_pool[0], "owner_character_id": "chiara"}]
	check(reward.choose(0, party) != null, "a secondary card reward can be taken")
	check(CastleWorkshop.set_primary(campaign, "chiara", "arcana") == "" and campaign.member("chiara").secondary_specialization == null and campaign.prepared_cards("chiara")[0].card_id.begins_with("chiara_arcana"), "switching primary resets the deck and clears a matching secondary")
	var restored := _save_and_reload()
	check(restored.member("chiara").specialization.id == "arcana" and restored.unlocked_specializations("chiara").has("fire"), "specializations survive a save")


func _test_upgrades_and_refinement() -> void:
	var campaign := _new_campaign()
	var owned := campaign.collection("chiara")[0]
	var price := CastleWorkshop.card_upgrade_price(owned)
	campaign.vault.gold = price - 1
	check(CastleWorkshop.upgrade_card(campaign, "chiara", owned.uid) != "" and owned.upgrade_level == 0, "not enough gold: nothing changes")
	campaign.vault.gold = price
	check(CastleWorkshop.upgrade_card(campaign, "chiara", owned.uid) == "" and owned.upgrade_level == 1 and campaign.vault.gold == 0, "a permanent upgrade costs treasury gold")
	campaign.vault.gold = 500
	check(CastleWorkshop.upgrade_card(campaign, "chiara", owned.uid) != "" and campaign.vault.gold == 500, "an upgraded card cannot be upgraded twice (max level)")
	check(CastleWorkshop.upgrade_card(campaign, "chiara", "nope") != "", "unknown cards are refused")
	# The upgrade reaches combat through the expedition copy.
	var copy := ExpeditionService.clone_member(campaign.member("chiara"), campaign.collection("chiara"))
	check(copy.find_card(owned.uid).upgrade_level == 1, "expedition copies carry permanent upgrades")
	copy.find_card(owned.uid).upgrade_level = 0
	check(owned.upgrade_level == 1, "changing the copy never touches the collection")
	# Refinement.
	campaign.vault.add_equipment("padded_gambeson")
	var bianca := campaign.member("bianca")
	Equipment.equip(bianca, campaign.vault, "padded_gambeson")
	campaign.refresh_roster()
	var before := bianca.max_hp
	var resist_before := int((Equipment.totals(bianca)["resist"] as Dictionary).get("physical", 0))
	var refine_price := CastleWorkshop.refine_price(campaign, "padded_gambeson")
	check(CastleWorkshop.refine(campaign, "padded_gambeson") == "" and CastleWorkshop.refinement_level(campaign, "padded_gambeson") == 1, "the blacksmith refines an owned item")
	check(bianca.max_hp == before + 2 and int((Equipment.totals(bianca)["resist"] as Dictionary).get("physical", 0)) == resist_before + 5, "refinement grows the item's own stats (+2 HP, +5% resist)")
	check(CastleWorkshop.refine_price(campaign, "padded_gambeson") > refine_price, "the next level costs more")
	CastleWorkshop.refine(campaign, "padded_gambeson")
	check(CastleWorkshop.can_refine(campaign, "padded_gambeson") != "", "refinement stops at the maximum level")
	check(CastleWorkshop.can_refine(campaign, "storm_crown") != "", "items you do not own cannot be refined")
	var restored := _save_and_reload()
	check(restored.refinement.get("padded_gambeson", 0) == 2 and restored.collection("chiara")[0].upgrade_level == 1, "upgrades and refinement persist")


func _test_potions() -> void:
	var campaign := _new_campaign()
	campaign.vault.gold = 200
	var stock := campaign.vault.count_of("health_potion")
	check(Apothecary.buy(campaign, "health_potion") == "" and campaign.vault.count_of("health_potion") == stock + 1, "the apothecary sells potions")
	check(Apothecary.buy(campaign, "guard_draught") != "", "brewed potions are not sold")
	check(Apothecary.brew(campaign, "brew_guard_draught") != "", "unknown recipes cannot be brewed")
	check(Apothecary.brew(campaign, "brew_minor_health_potion") == "" and campaign.vault.count_of("minor_health_potion") >= 4, "a known recipe brews potions")
	campaign.recipes.append("brew_clarity_elixir")
	check(Apothecary.brew(campaign, "brew_clarity_elixir") != "", "a recipe needing Essence fails without it")
	campaign.essence = 1
	check(Apothecary.brew(campaign, "brew_clarity_elixir") == "" and campaign.essence == 0, "with Essence it brews")
	var too_many := {"minor_health_potion": 4}
	check(not Apothecary.validate_loadout(campaign, too_many).is_empty(), "the belt holds only 3 potions")
	check(not Apothecary.validate_loadout(campaign, {"health_potion": 9}).is_empty(), "you cannot carry more than you have")
	campaign.vault.gold = 200
	check(Apothecary.buy_capacity(campaign) == "" and campaign.potion_capacity == 4 and Apothecary.buy_capacity(campaign) != "", "the belt can be widened once")
	check(Apothecary.validate_loadout(campaign, too_many).is_empty(), "a wider belt holds 4")
	# Brewed potions work in combat.
	var party := Party.from_selection({"chiara": "fire", "bianca": "holy"})
	var inventory := Inventory.new()
	inventory.add_item("guard_draught")
	inventory.add_item("focus_tonic")
	inventory.add_item("clarity_elixir")
	var combat := CombatManager.new()
	combat.setup(party, DataRegistry.get_encounter("castle_training_01"), inventory)
	combat.start()
	var energy := combat.energy
	check(combat.use_potion("guard_draught") == "" and combat.party_combatants.all(func(c: Combatant) -> bool: return c.block >= 8), "Guard Draught gives both sisters 8 Block")
	check(combat.use_potion("focus_tonic") == "" and combat.energy == energy + 1, "Focus Tonic gives 1 Energy")
	var hand := combat.deck.hand.size()
	var error := combat.use_potion("clarity_elixir")
	check(error == "" and combat.deck.hand.size() == mini(hand + 2, PartyDeck.MAX_HAND_SIZE), "Clarity Elixir draws 2 (%s, %d -> %d)" % [error, hand, combat.deck.hand.size()])
	check(inventory.items.is_empty(), "potions are used up")


func _test_fusion_and_bond() -> void:
	var campaign := _new_campaign("fire", "holy")
	check(Fusion.known_recipes(campaign).is_empty() and Fusion.can_fuse(campaign, "purifying_flame") != "", "no fusion at bond level 1")
	check(Bond.level_for(0) == 1 and Bond.level_for(5) == 2 and Bond.level_for(999) == 5, "bond levels from XP")
	var gained := Bond.add_xp(campaign, 5)
	check(gained == [2] and campaign.services.has("enchanter"), "bond level 2 opens the Enchanter")
	check(Fusion.known_recipes(campaign).size() == 2, "bond level 2 reveals two recipes")
	check(Fusion.can_fuse(campaign, "purifying_flame").contains("+"), "inputs must be upgraded copies")
	campaign.vault.gold = 1000
	CastleWorkshop.upgrade_card(campaign, "chiara", _uid_of(campaign, "chiara", "chiara_fire_ember"))
	CastleWorkshop.upgrade_card(campaign, "bianca", _uid_of(campaign, "bianca", "bianca_holy_strike"))
	check(Fusion.can_fuse(campaign, "purifying_flame").contains("Essence"), "fusion needs Starlight Essence")
	campaign.essence = 3
	var embers := campaign.count_owned("chiara", "chiara_fire_ember")
	var gold := campaign.vault.gold
	var result := Fusion.fuse(campaign, "purifying_flame")
	check(result["ok"] and (result["card"] as OwnedCard).owner_character_id == "chiara" and campaign.count_owned("chiara", "chiara_fusion_purifying_flame") == 1, "Purifying Flame is crafted for Chiara")
	check(campaign.count_owned("chiara", "chiara_fire_ember") == embers - 1 and campaign.essence == 2 and campaign.vault.gold == gold - 80, "inputs, gold and Essence are consumed")
	check(not Fusion.fuse(campaign, "purifying_flame")["ok"] and campaign.count_owned("chiara", "chiara_fusion_purifying_flame") == 1, "a recipe cannot be crafted twice")
	check(Fusion.can_fuse(campaign, "frozen_bastion").contains("must learn"), "a recipe needs both sisters' specializations")
	check(Fusion.can_fuse(campaign, "venom_cinder") != "", "higher recipes wait for a higher bond")
	var chiara := campaign.member("chiara")
	check(DeckRules.card_allowed(chiara, "chiara_fusion_purifying_flame") == "" and DeckRules.max_copies("chiara_fusion_purifying_flame") == 1, "the fusion card fits Chiara's deck, one copy")
	# The fusion card in combat: Holy damage, Burn after.
	var party := Party.from_selection({"chiara": "fire", "bianca": "holy"})
	var combat := CombatManager.new()
	combat.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new())
	combat.start()
	var card := CardInstance.new()
	card.definition = DataRegistry.get_card("chiara_fusion_purifying_flame")
	card.owner_character_id = "chiara"
	card.owned_uid = "test_fusion"
	combat.deck.hand.append(card)
	var enemy := combat.enemies[0]
	var hp := enemy.hp
	combat.energy = 3
	check(combat.play_card(card, enemy.id) and enemy.hp < hp and enemy.has_status("burn"), "the fusion card plays in combat (damage, then Burn)")
	# Bond XP from reactions is capped per expedition.
	var counts := {}
	var xp := Bond.note(counts, "twin_reaction", 10)
	check(xp == 3 and Bond.note(counts, "twin_reaction", 5) == 0, "twin reactions give at most 3 bond XP per expedition")
	Bond.add_xp(campaign, 30)
	check(Bond.relics(campaign).size() == 3, "bond relics unlock at levels 3, 4 and 5")
	var restored := _save_and_reload()
	check(restored.fusions_done.has("purifying_flame") and restored.bond_level() == 5 and restored.services.has("enchanter"), "fusion results and the bond persist")


func _uid_of(campaign: CampaignState, character_id: String, card_id: String) -> String:
	for owned in campaign.collection(character_id):
		if owned.card_id == card_id:
			return owned.uid
	return ""


func _test_generator() -> void:
	var rng := RandomNumberGenerator.new()
	var all_ok := true
	var differs := false
	var template := DataRegistry.get_map("enchanted_forest")
	for seed in range(1, 30):
		rng.seed = seed
		var varied := ExpeditionGenerator.vary_fixed(template, rng)
		if not ExpeditionGenerator.is_fully_connected(varied) or varied["nodes"].size() != template["nodes"].size():
			all_ok = false
		if JSON.stringify(varied["nodes"]) != JSON.stringify(template["nodes"]):
			differs = true
		# Fights keep their terrain's foes (the backdrop matches the monsters).
		for node: Dictionary in varied["nodes"]:
			if str(node.get("type", "")) in ["combat", "elite"] and str(node.get("encounter_id", "")) != "":
				var original: Array = template["nodes"].filter(func(n: Dictionary) -> bool: return str(n.get("encounter_id", "")) == str(node["encounter_id"]))
				if original.is_empty() or str(original[0].get("terrain", "")) != str(node.get("terrain", "")):
					all_ok = false
	check(all_ok, "rerolled forest maps stay fully connected and keep terrain-true fights (29 seeds)")
	check(differs, "rerolled maps really differ from the template")
	var generated_ok := true
	var shapes := {}
	for mission_id in ["forest_rescue", "coast_reliquary", "frostpeak_beacons"]:
		for seed in range(1, 16):
			rng.seed = seed
			var built := ExpeditionGenerator.generate(DataRegistry.get_mission(mission_id), rng)
			var map_def: Dictionary = built["map_def"]
			if map_def.is_empty() or not ExpeditionGenerator.is_fully_connected(map_def):
				generated_ok = false
				continue
			var targets: Array = map_def["nodes"].filter(func(n: Dictionary) -> bool: return bool(n.get("objective", false)))
			if targets.size() != 3:
				generated_ok = false
			for node: Dictionary in map_def["nodes"]:
				if str(node.get("encounter_id", "")) != "" and DataRegistry.get_encounter(str(node["encounter_id"])).is_empty():
					generated_ok = false
			if (built["layout_def"] as Dictionary).get("nodes", {}).size() != map_def["nodes"].size():
				generated_ok = false
			shapes[JSON.stringify(map_def["nodes"].map(func(n: Dictionary) -> String: return str(n["type"])))] = true
	check(generated_ok, "generated maps (3 missions x 15 seeds) are connected, have 3 objective rooms, known encounters and a full layout")
	check(shapes.size() >= 30, "generated maps vary (%d different room layouts of 45)" % shapes.size())


func _test_expedition_lifecycle() -> void:
	var campaign := _new_campaign()
	check(ExpeditionService.start("forest_serpent", {}) != "", "a locked mission cannot start")
	var loadout := {"minor_health_potion": 2}
	var gold_before := campaign.vault.gold
	check(ExpeditionService.start("castle_awakening", loadout, 42) == "", "the castle mission starts")
	check(GameState.expedition != null and not GameState.in_castle() and GameState.party != campaign.roster, "an expedition has its own party copies")
	check(GameState.inventory.gold == int(CampaignRules.block("expedition")["purse"]) and GameState.inventory.count_of("minor_health_potion") == 2 and campaign.vault.count_of("minor_health_potion") == 0, "the purse and the chosen potions go along")
	check(ExpeditionService.start("castle_awakening", {}) != "", "only one expedition at a time")
	# Expedition changes do not leak into the campaign.
	var chiara_copy := GameState.party.get_member("chiara")
	chiara_copy.current_hp = 5
	chiara_copy.deck[0].upgrade_level = 1
	var drafted := chiara_copy.add_card("chiara_fire_kindle")
	GameState.inventory.add_gold(70)
	GameState.inventory.add_equipment("padded_gambeson")
	GameState.inventory.add_relic("sundial_shard")
	check(campaign.collection("chiara")[0].upgrade_level == 0 and campaign.member("chiara").current_hp == campaign.member("chiara").max_hp, "the castle collection and HP are untouched during the expedition")
	_walk_to_exit()
	var results := GameState.finish_expedition(Objectives.outcome_at_exit(GameState.expedition.objective))
	check(results["outcome"] == "completed" and campaign.is_mission_completed("castle_awakening"), "reaching the gate completes the mission")
	check(campaign.vault.gold == gold_before + 100 + int(results.get("mission_gold", 0)), "the whole purse (100) and the mission gold return to the treasury")
	check(campaign.essence == 1 and campaign.services.has("blacksmith"), "first completion: Essence and the Upgrade Workshop")
	check(campaign.vault.equipment.has("padded_gambeson") and campaign.relic_collection.has("sundial_shard"), "found equipment and relics come home")
	check(campaign.vault.count_of("minor_health_potion") == 2, "unused potions return to the stores")
	check(GameState.expedition.discoveries.size() == 1 and GameState.expedition.discoveries_allowed == 1, "the drafted card is offered as a discovery")
	var again := GameState.finish_expedition("completed")
	check(campaign.vault.gold == gold_before + 100 + int(results.get("mission_gold", 0)) and again == results, "finishing twice grants nothing twice")
	check(ExpeditionService.region_unlocked(campaign, "enchanted_forest") and (results["unlocked"] as Array).has("region:enchanted_forest"), "the forest opens and the results say so")
	check(int(results["bond_xp"]) >= 4, "a completed expedition strengthens the bond")
	var kindles := campaign.count_owned("chiara", "chiara_fire_kindle")
	var kept := ExpeditionService.claim_discoveries([0, 0])
	check(kept == ["chiara_fire_kindle"] and ExpeditionService.claim_discoveries([0]).is_empty(), "one discovery is kept, once")
	check(campaign.count_owned("chiara", "chiara_fire_kindle") == kindles + 1, "the discovery joins the collection")
	var reloaded := _save_and_reload(false)
	check(reloaded != null and GameState.expedition != null and GameState.expedition.rewards_claimed and GameState.expedition.discoveries_claimed, "results survive a reload until the party goes home")
	ExpeditionService.return_to_castle()
	check(GameState.in_castle() and GameState.expedition == null and GameState.party == GameState.campaign.roster, "back at the castle")
	check(GameState.campaign.vault.gold == campaign.vault.gold, "nothing was paid twice by the reload")
	check(drafted != null and GameState.campaign.count_owned("chiara", "chiara_fire_kindle") == kindles + 1, "the kept discovery is still in the collection after the reload")


func _test_retreat_and_defeat() -> void:
	var campaign := _new_campaign()
	campaign.mark_mission_completed("castle_awakening")
	_set_level(campaign, 2)
	var gold := campaign.vault.gold
	ExpeditionService.start("crystal_hollow", {"minor_health_potion": 1}, 7)
	GameState.inventory.add_gold(10)  # purse 40
	GameState.party.get_member("bianca").add_card("bianca_holy_touch")
	var results := GameState.finish_expedition("retreated")
	check(results["outcome"] == "retreated" and campaign.vault.gold == gold + 20 and not campaign.is_mission_completed("crystal_hollow"), "a retreat brings half the purse home and no mission reward")
	check(campaign.vault.count_of("minor_health_potion") == 2 and GameState.expedition.discoveries_allowed == 1, "a retreat keeps potions and one discovery")
	ExpeditionService.return_to_castle()
	gold = campaign.vault.gold
	var potions := campaign.vault.count_of("minor_health_potion")
	ExpeditionService.start("crystal_hollow", {"minor_health_potion": 1}, 8)
	GameState.inventory.add_gold(10)
	GameState.inventory.add_equipment("iron_sallet")
	GameState.finish_run(GameState.RESULT_DEFEATED)
	check(GameState.expedition.outcome == "defeated" and campaign.vault.gold == gold + 10, "defeat brings a quarter of the purse home")
	check(campaign.vault.count_of("minor_health_potion") == potions - 1 and GameState.expedition.discoveries_allowed == 0, "defeat loses carried potions and offers no discovery")
	check(campaign.vault.equipment.has("iron_sallet") and GameState.has_save(), "equipment is never lost; the save is kept")
	ExpeditionService.return_to_castle()
	check(int(campaign.stats.get("expeditions_retreated", 0)) == 1 and int(campaign.stats.get("expeditions_defeated", 0)) == 1, "outcomes are counted")
	# Return before the end counts as a retreat.
	ExpeditionService.start("crystal_hollow", {}, 9)
	ExpeditionService.return_to_castle()
	check(GameState.in_castle() and int(campaign.stats.get("expeditions_retreated", 0)) == 2, "leaving mid-expedition is a retreat")


func _test_objective_mission() -> void:
	var campaign := _new_campaign()
	campaign.mark_mission_completed("castle_awakening")
	check(ExpeditionService.start("forest_rescue", {}, 1234) != "", "the rescue mission waits for party level 3")
	_set_level(campaign, 3)
	check(ExpeditionService.start("forest_rescue", {}, 1234) == "", "the rescue mission starts on a generated map")
	var graph := GameState.map_progress.graph
	check(not graph.custom_def.is_empty() and MapLayout.for_map(graph.id) != null and MapLayout.for_map(graph.id).get_background() != null, "the generated map has a layout on the forest picture")
	var objective := GameState.expedition.objective
	check(int(objective["targets"]) == 3 and int(objective["required"]) == 2 and not Objectives.is_met(objective), "rescue 2 of 3 woodcutter camps")
	check(Objectives.outcome_at_exit(objective) == "retreated", "leaving without them is a retreat")
	var targets: Array = graph.nodes.values().filter(func(n: MapNodeData) -> bool: return bool(n.raw.get("objective", false)))
	GameState.room_state = {}
	GameState.map_progress.current_node_id = targets[0].id
	GameState.record_combat_victory(10, DataRegistry.get_encounter(targets[0].encounter_id), 2)
	check(int(objective["progress"]) == 1 and GameState.expedition.bond_xp == 2, "winning a target fight counts it; reactions add bond XP")
	GameState.record_combat_victory(10, DataRegistry.get_encounter(targets[0].encounter_id), 2)
	check(int(objective["progress"]) == 1, "the same fight is never counted twice")
	GameState.room_state = {}
	GameState.map_progress.current_node_id = targets[1].id
	GameState.record_combat_victory(10, DataRegistry.get_encounter(targets[1].encounter_id))
	check(Objectives.is_met(objective) and ExpeditionService.can_return_early(), "two rescues: the party may go home")
	check(Objectives.describe(objective).contains("2 / 2"), "the tracker reads 2 / 2")
	var results := GameState.finish_expedition("completed")
	check(results["outcome"] == "completed" and campaign.is_mission_completed("forest_rescue") and campaign.recipes.has("brew_focus_tonic") and campaign.get_flag("woodcutters_saved") == true, "the rescue completes, teaches a brew and changes the world")
	ExpeditionService.return_to_castle()


func _test_save_load() -> void:
	var campaign := _new_campaign()
	campaign.mark_mission_completed("castle_awakening")
	_set_level(campaign, 3)
	ExpeditionService.start("forest_rescue", {"minor_health_potion": 1}, 99)
	var graph_def := _shape(GameState.map_progress.graph.custom_def)
	var graph_id := GameState.map_progress.graph.id
	var first := GameState.map_progress.get_available_ids()[0]
	GameState.map_progress.travel_to(first)
	GameState.begin_room(GameState.get_current_node())
	GameState.expedition.objective["progress"] = 1
	GameState.expedition.objective["done_nodes"] = ["x_test"]
	var copy_hp := GameState.party.get_member("chiara").current_hp - 3
	GameState.party.get_member("chiara").current_hp = copy_hp
	GameState.save_game()
	GameState.campaign = null
	GameState.expedition = null
	DataRegistry.layouts.erase(graph_id)
	check(GameState.load_game() == "", "an expedition save loads")
	check(GameState.expedition != null and GameState.expedition.mission_id == "forest_rescue" and int(GameState.expedition.objective["progress"]) == 1, "mission and objective progress are restored")
	check(_shape(GameState.map_progress.graph.custom_def) == graph_def and GameState.map_progress.current_node_id == first, "the same generated map and position come back")
	check(MapLayout.for_map(GameState.map_progress.graph.id) != null, "its layout is registered again")
	check(GameState.party.get_member("chiara").current_hp == copy_hp and GameState.inventory.count_of("minor_health_potion") == 1, "expedition HP and potions are restored")
	check(GameState.campaign.vault.count_of("minor_health_potion") == 1, "the campaign stores are restored separately")
	# A damaged expedition never costs the campaign.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	(data["map"] as Dictionary)["map_def"]["nodes"] = [{"id": "x_start", "type": "start", "next": ["nowhere"]}]
	SaveManager.write_file(SAVE, data)
	check(GameState.load_game() == "" and GameState.in_castle() and GameState.load_warnings.size() > 0, "a broken expedition map sends the sisters home with a warning; the campaign loads")
	var bad := FileAccess.open(SAVE, FileAccess.WRITE)
	bad.store_string("{broken")
	bad.close()
	check(GameState.load_game() == "", "a corrupt main file falls back to the backup")
	SaveManager.write_file(SAVE, {"version": 3, "mode": "campaign", "campaign": "junk"})
	DirAccess.remove_absolute(SAVE + ".bak")
	check(GameState.load_game() != "", "an unusable campaign reports an error instead of crashing")


func _test_world_state() -> void:
	var campaign := _new_campaign()
	campaign.mark_mission_completed("castle_awakening")
	check(Requirements.met(campaign, {"missions": ["castle_awakening"]}) and not Requirements.met(campaign, {"missions": ["forest_serpent"]}), "mission requirements")
	check(not Requirements.met(campaign, {"bond_level": 2}) and Requirements.missing(campaign, {"bond_level": 2})[0].contains("Bond"), "bond requirements explain themselves")
	check(not ExpeditionService.region_unlocked(campaign, "frostpeak") and not ExpeditionService.region_unlocked(campaign, "sunlit_coast"), "the coast and Frostpeak wait for the Serpent")
	_set_level(campaign, 4)
	ExpeditionService.start("forest_serpent", {}, 5)
	var threat_before := int(campaign.region_state("enchanted_forest")["threat"])
	var results := GameState.finish_expedition("completed")
	check(campaign.get_flag("forest_serpent_slain") == true and int(campaign.region_state("enchanted_forest")["threat"]) == threat_before - 2, "slaying the Serpent lowers the forest's threat and sets a world flag")
	check(campaign.services.has("training_hall") and campaign.recipes.has("brew_guard_draught"), "it opens the Training Hall and a brew")
	check(ExpeditionService.region_unlocked(campaign, "sunlit_coast") and ExpeditionService.region_unlocked(campaign, "frostpeak") and (results["unlocked"] as Array).has("region:frostpeak"), "the coast and Frostpeak open")
	check((results["lines"] as Array).size() >= 3, "the results list the world changes")
	ExpeditionService.return_to_castle()
	ExpeditionService.start("forest_serpent", {}, 6)
	var again := GameState.finish_expedition("completed")
	check(not (again["lines"] as Array).any(func(l: String) -> bool: return l.contains("Training Hall")), "first-time consequences happen once")
	ExpeditionService.return_to_castle()
	# Gated loot.
	Requirements.active_campaign = campaign
	var gated := {"unlock": {"flags": {"never_set": true}}}
	check(not Requirements.met(campaign, gated["unlock"]), "a flag requirement blocks until the flag is set")


func _test_migration() -> void:
	# A version-2 run in the middle of the forest, with an upgraded card, worn gear and a relic.
	var party := Party.from_selection({"chiara": "frost", "bianca": "tanking"})
	party.get_member("chiara").deck[0].upgrade_level = 1
	party.get_member("chiara").add_card("chiara_frost_touch")
	var inventory := Inventory.new()
	inventory.gold = 77
	inventory.add_relic("sundial_shard")
	inventory.add_equipment("iron_sallet")
	var progress := MapProgress.new(MapGraph.from_dict(DataRegistry.get_map("enchanted_forest")))
	var data := SaveManager.serialize(party, inventory, progress, {}, null, {"completed_maps": ["royal_castle_tutorial"]})
	data["version"] = 2
	GameState.campaign = null
	GameState.expedition = null
	GameState.delete_save()
	SaveManager.write_file(SAVE, data)
	var error := GameState.load_game()
	check(error == "" and GameState.campaign != null and GameState.expedition != null, "an old run save becomes a campaign with the run as an expedition")
	var campaign := GameState.campaign
	if campaign != null:
		check(GameState.expedition.mission_id == "forest_serpent" and GameState.map_progress.graph.id == "enchanted_forest" and GameState.inventory.gold == 77, "the run continues where it was, with its gold")
		check(campaign.member("chiara").specialization.id == "frost" and campaign.count_owned("chiara", "chiara_frost_touch") >= 3, "specializations and every card are kept")
		check(campaign.collection("chiara").any(func(o: OwnedCard) -> bool: return o.upgrade_level == 1), "card upgrades are kept")
		check(campaign.relic_collection.has("sundial_shard") and campaign.is_mission_completed("castle_awakening"), "relics and completed acts carry over")
		check(DeckRules.validate_campaign(campaign).is_empty(), "the migrated prepared decks are valid")
		var rewritten: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		check(str(rewritten.get("mode", "")) == "campaign" and rewritten.has("campaign"), "the save is rewritten as a campaign at once")
	var oldest := {"version": 1, "party": data["party"], "inventory": {"gold": 12, "items": {}}, "map": {"map_id": "royal_castle_tutorial", "current_node_id": "royal_chambers", "visited": ["royal_chambers"]}}
	SaveManager.write_file(SAVE, oldest)
	check(GameState.load_game() == "" and GameState.expedition != null and GameState.expedition.mission_id == "castle_awakening", "even a version-1 save migrates (castle mission)")
	# A Quick Play run never turns into a campaign.
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure("royal_castle_tutorial")
	GameState.save_game()
	check(GameState.load_game() == "" and GameState.campaign == null and GameState.expedition == null, "a Quick Play save stays a classic run")


## Node ids, types, encounters and links of a map definition (numbers are not compared: JSON turns
## integers into floats).
func _shape(map_def: Dictionary) -> String:
	return ",".join(map_def.get("nodes", []).map(func(n: Dictionary) -> String: return "%s/%s/%s>%s" % [n["id"], n["type"], n.get("encounter_id", ""), ";".join(n.get("next", []))]))


## Saves, forgets and reloads the campaign. Returns the reloaded campaign.
func _save_and_reload(back_to_castle: bool = true) -> CampaignState:
	GameState.save_game()
	GameState.campaign = null
	GameState.expedition = null
	var error := GameState.load_game()
	if error != "":
		print("    load error: ", error)
		return null
	if back_to_castle and GameState.expedition == null:
		check(GameState.in_castle(), "reloaded at the castle")
	return GameState.campaign


# --- Room names, levels, dual specialization, contracts ---------------------------------------

## A fight room's name is its encounter's name whenever the encounter was changed (or generated).
func _test_room_names() -> void:
	var rng := RandomNumberGenerator.new()
	var mismatches: Array[String] = []
	for map_id in ["enchanted_forest", "sunlit_coast", "frostpeak", "crystal_hollow_demo", "castle_elite_demo"]:
		var template := DataRegistry.get_map(map_id)
		var authored := {}
		for node: Dictionary in template["nodes"]:
			authored[str(node["id"])] = str(node.get("encounter_id", ""))
		for seed in range(1, 21):
			rng.seed = seed
			for node: Dictionary in ExpeditionGenerator.vary_fixed(template, rng)["nodes"]:
				var encounter_id := str(node.get("encounter_id", ""))
				if encounter_id != "" and encounter_id != str(authored.get(str(node["id"]), "")) and str(node.get("name", "")) != str(DataRegistry.get_encounter(encounter_id).get("name", "")):
					mismatches.append("%s/%s: %s holds %s" % [map_id, node["id"], node.get("name", ""), encounter_id])
	for mission_id in ["forest_rescue", "coast_reliquary", "frostpeak_beacons"]:
		for seed in range(1, 11):
			rng.seed = seed
			for node: Dictionary in ExpeditionGenerator.generate(DataRegistry.get_mission(mission_id), rng)["map_def"]["nodes"]:
				var encounter_id := str(node.get("encounter_id", ""))
				if encounter_id != "" and not bool(node.get("objective", false)) and str(node.get("name", "")) != str(DataRegistry.get_encounter(encounter_id).get("name", "")):
					mismatches.append("%s: %s holds %s" % [mission_id, node.get("name", ""), encounter_id])
	check(mismatches.is_empty(), "rerolled and generated rooms are named after the monsters inside (%s)" % ", ".join(mismatches.slice(0, 3)))


func _test_levels() -> void:
	var campaign := _new_campaign()
	check(Levels.level_of(campaign, "chiara") == 1 and Levels.party_level(campaign) == 1, "the sisters start at level 1")
	check(Levels.level_for(Levels.threshold(5)) == 5 and Levels.level_for(Levels.threshold(5) - 1) == 4 and Levels.max_level() == 10, "the level table has 10 levels")
	var base_hp := campaign.member("chiara").max_hp
	var gold := campaign.vault.gold
	var gained := Levels.add_xp(campaign, "chiara", Levels.threshold(3))
	check(int(gained["from"]) == 1 and int(gained["to"]) == 3 and (gained["lines"] as Array).size() >= 3, "XP raises Chiara to level 3 with level-up lines")
	check(campaign.vault.gold == gold + 40 and campaign.member("chiara").max_hp == base_hp + 2 * int(Levels.data()["hp_per_level"]), "level rewards: treasury gold and Max HP per level")
	check(campaign.level_rewards.size() == 1 and (campaign.level_rewards[0]["options"] as Array).size() == 3, "level 3 offers a Mastery card choice of three")
	var options: Array = campaign.level_rewards[0]["options"]
	var good_rarity := options.all(func(id: String) -> bool: return Levels.RARITY_ORDER.find(DataRegistry.get_card(id).rarity) >= Levels.RARITY_ORDER.find("uncommon"))
	var own_pool := options.all(func(id: String) -> bool: return campaign.member("chiara").specialization.card_pool.has(id))
	check(good_rarity and own_pool, "Mastery options are uncommon or better and from her own specialization")
	var owned_before := campaign.count_owned("chiara", str(options[0]))
	check(Levels.claim_choice(campaign, 0, 0) != "" and campaign.count_owned("chiara", str(options[0])) == owned_before + 1 and campaign.level_rewards.is_empty(), "claiming a Mastery card adds it to her collection")
	Levels.add_xp(campaign, "chiara", 100000)
	check(Levels.level_of(campaign, "chiara") == 10 and Levels.xp_of(campaign, "chiara") == Levels.threshold(10), "XP stops at the top level")
	check(Levels.can_dual_spec(campaign, "chiara") and campaign.services.has("training_hall"), "level 10 grants the Dual Specialization and opens the Training Hall")
	check(Levels.party_level(campaign) == 5, "the party level is the rounded-down average (10 and 1 -> 5)")
	# Missions are level-gated.
	var fresh := _new_campaign()
	fresh.mark_mission_completed("castle_awakening")
	check(ExpeditionService.mission_lock_reason(fresh, "castle_gauntlet").contains("Party level 2"), "the Castle Depths need party level 2")
	fresh.missions["completed"] = []
	# Expedition XP: every won fight pays, completion adds the mission bonus; both sisters gain it.
	check(ExpeditionService.start("castle_awakening", {}, 3) == "", "the castle mission starts")
	var level_hp := GameState.party.get_member("chiara").max_hp
	var fights := 0
	for node: MapNodeData in GameState.map_progress.graph.nodes.values():
		if node.type == "combat":
			ExpeditionService.on_combat_won(node, DataRegistry.get_encounter(node.encounter_id), 0)
			fights += 1
	var results := GameState.finish_expedition("completed")
	var expected := fights * int(Levels.xp_rule("combat")) + int(Levels.xp_rule("mission_per_difficulty"))
	check(int(results.get("xp", 0)) == expected and Levels.xp_of(fresh, "chiara") == expected and Levels.xp_of(fresh, "bianca") == expected, "the expedition pays %d XP to each sister (%d fights + mission bonus)" % [expected, fights])
	check(Levels.level_of(fresh, "chiara") == 2 and (results["level_lines"] as Array).size() >= 2, "the tutorial raises both sisters to level 2")
	check((results["unlocked"] as Array).has("mission:castle_gauntlet"), "reaching level 2 announces the Castle Depths")
	check(level_hp == fresh.member("chiara").definition.max_hp + int(Equipment.totals(GameState.party.get_member("chiara"))["max_hp"]), "the expedition copy starts with her level-1 Max HP")
	check(fresh.member("chiara").max_hp == level_hp + int(Levels.data()["hp_per_level"]), "back home, level 2 adds Max HP")
	ExpeditionService.return_to_castle()
	# Saves keep levels and pending choices; old saves get an estimate.
	fresh.level_rewards.append({"character_id": "bianca", "level": 3, "upgraded": false, "options": [str(fresh.member("bianca").specialization.card_pool[0])]})
	var reloaded := _save_and_reload()
	check(reloaded != null and Levels.xp_of(reloaded, "chiara") == expected and reloaded.level_rewards.size() == 1, "levels and pending Mastery choices survive a save")
	check(Levels.estimate_xp(["castle_awakening", "crystal_hollow"]) >= Levels.threshold(2), "older saves start at the level their completed missions earned")


func _test_dual_specialization() -> void:
	var campaign := _new_campaign("fire", "holy")
	var spec_id := ""
	for spec in DataRegistry.get_specializations_for("bianca"):
		if spec.is_playable() and spec.id != "holy" and not campaign.unlocked_specializations("bianca").has(spec.id):
			spec_id = spec.id
			break
	check(spec_id != "", "Bianca has an unlearned playable style (%s)" % spec_id)
	check(CastleWorkshop.set_secondary(campaign, "bianca", spec_id).contains("level"), "the second specialization waits for level 10")
	_set_level(campaign, 10)
	var collection := campaign.member("bianca").deck.size()
	check(CastleWorkshop.set_secondary(campaign, "bianca", spec_id) == "" and campaign.member("bianca").secondary_specialization.id == spec_id, "at level 10 Bianca takes %s as her second specialization" % spec_id)
	check(campaign.unlocked_specializations("bianca").has(spec_id) and campaign.member("bianca").deck.size() > collection, "the reward learns the style for free (its starting cards join her collection)")
	check(campaign.member("bianca").specialization.id == "holy", "her primary (look and passive) stays Holy")
	var party := Party.new()
	for m in campaign.roster.members:
		party.add_member(ExpeditionService.clone_member(m, campaign.prepared_cards(m.id)))
	var combat := CombatManager.new()
	combat.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new(), 1)
	check(combat.get_combatant("bianca").specialization_id == "holy", "in battle she keeps her Holy sprites")


func _test_contracts() -> void:
	var campaign := _new_campaign()
	check(ExpeditionService.missions_of("royal_castle").size() == 2, "no contract while the castle's own missions are open")
	campaign.mark_mission_completed("castle_awakening")
	campaign.mark_mission_completed("castle_gauntlet")
	campaign.refresh_roster()
	var missions := ExpeditionService.missions_of("royal_castle")
	check(missions.size() == 3 and Contracts.is_contract(missions[2]) and str(missions[2]["id"]) == "contract_royal_castle_1", "the castle offers a contract once its missions are done")
	var contract_id := str(missions[2]["id"])
	check(ExpeditionService.mission_lock_reason(campaign, contract_id).contains("Party level 2"), "contract rank 1 at the castle needs party level 2")
	# Every region, kind and many seeds: connected maps on the region's layout, known encounters,
	# the right marked rooms and room names that match the monsters.
	var problems: Array[String] = []
	var rng := RandomNumberGenerator.new()
	for region: Dictionary in DataRegistry.regions.values():
		var template := DataRegistry.get_map(str(region["contracts"]["map_id"]))
		for kind: String in Contracts.kinds_for(region):
			for seed in range(1, 9):
				var mission := Contracts.build_mission(region, {"tier": 1 + seed % 4, "kind": kind, "seed": seed})
				rng.seed = seed
				var map_def := ExpeditionGenerator.remix(mission, rng)
				var label := "%s/%s/%d" % [region["id"], kind, seed]
				if not ExpeditionGenerator.is_fully_connected(map_def) or map_def["nodes"].size() != template["nodes"].size():
					problems.append(label + " shape")
				var marked := 0
				for node: Dictionary in map_def["nodes"]:
					var encounter_id := str(node.get("encounter_id", ""))
					if str(node.get("type", "")) in ["combat", "elite", "boss"] and DataRegistry.get_encounter(encounter_id).is_empty():
						problems.append(label + " encounter " + encounter_id)
					if encounter_id != "" and str(node.get("name", "")) != str(DataRegistry.get_encounter(encounter_id).get("name", "")) and not bool(node.get("final_encounter", false)):
						problems.append(label + " name " + str(node.get("name", "")))
					if bool(node.get("objective", false)):
						marked += 1
				if (kind == "hunt" and marked != 1) or (kind == "purge" and (marked < 2 or marked > 3)) or (kind in ["patrol", "boss"] and marked != 0):
					problems.append(label + " marked %d" % marked)
				var objective := Objectives.create(mission, map_def)
				if kind == "hunt" and int(objective.get("targets", 0)) != 1:
					problems.append(label + " objective")
	check(problems.is_empty(), "contract maps for every region and quest are valid (%d issues: %s)" % [problems.size(), ", ".join(problems.slice(0, 4))])
	# Play rank 1: the next contract is harder and needs a higher level.
	_set_level(campaign, 2)
	check(ExpeditionService.start(contract_id, {}, 11) == "", "the castle contract starts")
	var expedition := GameState.expedition
	check(not expedition.mission_snapshot.is_empty() and GameState.map_progress.graph.id == "royal_castle_tutorial", "the contract keeps the castle layout and travels with the expedition")
	for node: MapNodeData in GameState.map_progress.graph.nodes.values():
		if node.type in ["combat", "elite"]:
			ExpeditionService.on_combat_won(node, DataRegistry.get_encounter(node.encounter_id), 0)
	var reloaded := _save_and_reload(false)
	check(reloaded != null and GameState.expedition != null and GameState.expedition.mission_id == contract_id and not GameState.expedition.mission().is_empty(), "a contract expedition survives a reload")
	var results := GameState.finish_expedition("completed")
	campaign = GameState.campaign
	check(str(results.get("outcome", "")) == "completed" and campaign.is_mission_completed(contract_id), "the contract completes")
	check(int(campaign.contracts["royal_castle"]["tier"]) == 2 and not DataRegistry.get_mission("contract_royal_castle_2").is_empty() and DataRegistry.get_mission(contract_id).is_empty(), "the castle rolls its rank 2 contract")
	check(not GameState.expedition.mission().is_empty(), "the finished contract is still known on the results screen")
	var next := DataRegistry.get_mission("contract_royal_castle_2")
	check(int(next["unlock"]["level"]) == 3 and float(next["enemy_scale"]["hp"]) > 1.0 and int(next["rewards"]["gold"]) > int(missions[2]["rewards"]["gold"]), "rank 2 needs level 3, has tougher foes and pays more")
	ExpeditionService.return_to_castle()
	var again := _save_and_reload()
	check(again != null and int(again.contracts["royal_castle"]["tier"]) == 2 and ExpeditionService.missions_of("royal_castle").size() == 3, "contract ranks survive a save")


## Every relic's hover text names it and says what it does; event relic choices preview their relic.
func _test_relic_tooltips() -> void:
	var missing: Array[String] = []
	for item_id: String in DataRegistry.items:
		var item := DataRegistry.get_item(item_id)
		if str(item.get("category", "")) != "relic":
			continue
		var tip := RelicIcon.tooltip_for(item_id)
		if not tip.contains(str(item.get("name", "?"))) or str(item.get("description", "")) == "" or not tip.contains(str(item["description"])):
			missing.append(item_id)
		var icon := RelicIcon.create(item_id, 32)
		if icon.tooltip_text != tip:
			missing.append(item_id + " (icon)")
		icon.free()
	check(missing.is_empty(), "every relic icon shows its name and effect on hover (%s)" % ", ".join(missing.slice(0, 4)))
	var inventory := Inventory.new()
	var choice := {"effects": [{"type": "gain_relic", "pool": ["ley_crystal", "nonexistent"]}]}
	check(EventResolver.relic_preview(choice, inventory) == "ley_crystal", "an event relic choice previews its relic")
	inventory.relics.append("ley_crystal")
	check(EventResolver.relic_preview(choice, inventory) == "", "an owned relic is not previewed again")
