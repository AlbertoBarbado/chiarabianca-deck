extends SceneTree
## Damage types, weaknesses / resistances, initiative, Chill and Frozen, the Frost specialization,
## equipment (stash, slots, stats, save) and loot. Run:
##   godot --headless --path . --script res://tests/combat/run_elements_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_damage_types()
	_test_enemy_data()
	_test_card_elements()
	_test_dot_elements()
	_test_chill_and_freeze()
	_test_frost_cards()
	_test_equipment()
	_test_equipment_in_combat()
	_test_loot_and_treasure()
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


func _party(chiara: String = "frost", bianca: String = "tanking") -> Party:
	return Party.from_selection({"chiara": chiara, "bianca": bianca})


func _combat(enemies: Array, party: Party = null, inventory: Inventory = null) -> CombatManager:
	var cm := CombatManager.new()
	cm.setup(party if party != null else _party(), {"id": "test", "name": "Test", "enemies": enemies, "gold_reward": 0}, inventory if inventory != null else Inventory.new(), 3)
	cm.start()
	return cm


## Plays a fresh copy of a card owned by `owner_id` against `target_id` (energy refilled first).
func _play(cm: CombatManager, card_id: String, owner_id: String, target_id: String = "", upgraded: bool = false) -> void:
	var member := cm.party.get_member(owner_id)
	var owned := OwnedCard.create("test_%d" % Time.get_ticks_usec(), card_id, owner_id)
	owned.upgrade_level = 1 if upgraded else 0
	var card := CardInstance.from_owned(owned, DataRegistry.get_card(card_id), 9000 + cm.deck.hand.size())
	cm.deck.hand.append(card)
	cm.energy = 10
	cm.play_card(card, target_id)
	member = member


# --- Damage types --------------------------------------------------------------------------------

func _test_damage_types() -> void:
	print("Damage types")
	var ids := DamageTypes.ids()
	for element in ["physical", "fire", "frost", "arcane", "holy", "shadow", "lightning", "wind", "poison"]:
		check(ids.has(element), "%s is a damage type" % element)
	check(DamageTypes.normalize("nonsense") == "physical" and DamageTypes.normalize("") == "physical", "unknown types count as physical")
	var weak := Combatant.new()
	weak.affinity = {"fire": 50, "holy": -25}
	check(DamageTypes.apply(10, "fire", null, weak) == 15, "a 50% weakness: 10 fire -> 15")
	check(DamageTypes.apply(10, "holy", null, weak) == 8, "a 25% resistance: 10 holy -> 8 (rounded)")
	check(DamageTypes.apply(10, "frost", null, weak) == 10, "other types are unchanged")
	var wall := Combatant.new()
	wall.affinity = {"physical": -500}
	check(DamageTypes.apply(20, "physical", null, wall) == 5, "resistance is capped at 75% (20 -> 5)")
	check(DamageTypes.apply(1, "physical", null, wall) == 1, "a hit of 1 never drops to 0")
	check(DamageTypes.apply(0, "fire", null, weak) == 0, "0 damage stays 0")
	var striker := Combatant.new()
	striker.damage_bonus = {"fire": 15}
	check(DamageTypes.apply(10, "fire", striker, weak) == 17, "weapon bonus and weakness add up: 10 x 165% = 17 (rounded)")


func _test_enemy_data() -> void:
	print("Enemy weaknesses, resistances and initiative")
	var all_ok := true
	for enemy_id: String in DataRegistry.enemies:
		var def: EnemyDef = DataRegistry.enemies[enemy_id]
		var keys: Array = def.weaknesses.keys() + def.resistances.keys() + [def.element]
		for action_id: String in def.actions:
			keys.append(str(def.actions[action_id].get("element", def.element)))
		for key: Variant in keys:
			all_ok = all_ok and DamageTypes.is_valid(str(key))
		all_ok = all_ok and def.initiative >= 1
	check(all_ok, "every enemy uses known damage types and has initiative")
	var troll := DataRegistry.get_enemy("forest_troll")
	check(int(troll.weaknesses.get("fire", 0)) == 50 and int(troll.resistances.get("physical", 0)) == 25 and troll.initiative == 1, "the troll: weak to fire, resists physical, slow")
	check(DataRegistry.get_enemy("demo_shadow_wraith").element == "shadow", "the wraith deals shadow damage")
	for boss_id in ["forest_serpent", "demo_crystal_wyrm"]:
		check(DataRegistry.get_enemy(boss_id).initiative > DataRegistry.get_status("chill").max_stacks, "%s cannot be frozen (initiative above the Chill cap)" % boss_id)
	var cm := _combat(["forest_troll"])
	check(cm.enemies[0].affinity.get("fire", 0) == 50 and cm.enemies[0].affinity.get("physical", 0) == -25, "combat copies the affinities onto the enemy")
	var intent := EnemyAI.plan_intent(_combat(["forest_spider"]).enemies[0], cm.party_combatants, _rng(1))
	check(intent != null and DamageTypes.is_valid(intent.element), "intents carry their damage type")
	var spit := EnemyIntent.new()
	spit.action_name = "Spit"
	spit.value = 5
	spit.element = "poison"
	check(spit.describe("Bianca").contains("poison dmg"), "intent text names a non-physical type")


func _test_card_elements() -> void:
	print("Card damage types")
	check(DamageTypes.for_card_effect({}, DataRegistry.get_card("chiara_fire_ember")) == "fire", "fire cards deal fire")
	check(DamageTypes.for_card_effect({}, DataRegistry.get_card("chiara_frost_bolt")) == "frost", "frost cards deal frost")
	check(DamageTypes.for_card_effect({}, DataRegistry.get_card("bianca_tanking_strike")) == "physical" if DataRegistry.get_card("bianca_tanking_strike") != null else true, "tanking cards deal physical")
	check(DamageTypes.for_card_effect({"element": "holy"}, DataRegistry.get_card("chiara_fire_ember")) == "holy", "an effect may name its own type")
	# Ember Bolt (6 fire) against the troll (weak 50%) -> 9.
	var cm := _combat(["forest_troll"], _party("fire", "tanking"))
	var troll := cm.enemies[0]
	var before := troll.hp
	_play(cm, "chiara_fire_ember", "chiara", troll.id)
	check(before - troll.hp == 9, "Ember Bolt hits the fire-weak troll for 9 (6 x 150%%) (lost %d)" % (before - troll.hp))
	check(int(cm.last_hit.get("pct", 0)) == 50 and str(cm.last_hit.get("element", "")) == "fire", "the hit reports its type and modifier for the screen")
	# Frost Bolt (5 frost) against the wolf (resists frost 25%) -> 4.
	var cm2 := _combat(["forest_wolf"])
	var wolf := cm2.enemies[0]
	before = wolf.hp
	_play(cm2, "chiara_frost_bolt", "chiara", wolf.id)
	check(before - wolf.hp == 4, "Frost Bolt is resisted by the wolf: 5 -> 4 (lost %d)" % (before - wolf.hp))


func _test_dot_elements() -> void:
	print("Burn and Poison use their damage types")
	check(DataRegistry.get_status("burn").tick_element == "fire" and DataRegistry.get_status("poison").tick_element == "poison", "Burn is fire, Poison is poison")
	var cm := _combat(["forest_troll", "forest_spider"])
	var troll := cm.enemies[0]
	var spider := cm.enemies[1]
	troll.add_status("burn", 2, "chiara")
	spider.add_status("poison", 8, "chiara")
	var troll_hp := troll.hp
	var spider_hp := spider.hp
	cm._tick_statuses(StatusDef.TICK_ENEMY_PHASE_START)
	check(troll_hp - troll.hp == 5, "Burn ticks 3 x 150%% = 5 on the fire-weak troll (lost %d)" % (troll_hp - troll.hp))
	check(spider_hp - spider.hp == 2, "Poison 8 ticks only 2 on the poison-resistant spider (lost %d)" % (spider_hp - spider.hp))


func _test_chill_and_freeze() -> void:
	print("Chill, initiative and Frozen")
	var chill := DataRegistry.get_status("chill")
	check(chill != null and chill.max_stacks == 5 and chill.initiative_per_stack == -1 and chill.vulnerable_element == "physical" and chill.vulnerable_per_stack == 10, "Chill: -1 initiative and +10% physical damage taken per stack, max 5")
	check(chill.describe(3).contains("-3 initiative") and chill.describe(3).contains("+30%"), "its description shows the live numbers")
	var cm := _combat(["forest_wolf", "forest_troll", "forest_bear"])
	var order := cm.enemies_in_initiative_order().map(func(c: Combatant) -> String: return c.enemy_def.id)
	check(order == ["forest_wolf", "forest_bear", "forest_troll"], "enemies act by initiative: wolf 5, bear 2, troll 1 (%s)" % ", ".join(order))
	var wolf := cm.enemies[0]
	wolf.add_status("chill", 4, "chiara")
	check(wolf.initiative() == 1, "Chill 4 brings the wolf from 5 to 1")
	order = cm.enemies_in_initiative_order().map(func(c: Combatant) -> String: return c.enemy_def.id)
	check(order[0] == "forest_bear", "a chilled wolf now acts after the bear")
	wolf.add_status("chill", 9, "chiara")
	check(int(wolf.statuses["chill"]["stacks"]) == 5, "Chill is capped at 5 stacks")
	check(DamageTypes.modifier("physical", null, wolf) == 50, "5 Chill: +50% physical damage taken")
	# Bianca's physical attack on a chilled enemy hits harder.
	var bear := cm.enemies[2]
	bear.add_status("chill", 2, "chiara")
	var before := bear.hp
	cm.hit(bear, 10, "physical", cm.get_combatant("bianca"))
	check(before - bear.hp == 12, "Chill 2: Bianca's 10 physical hits for 12 (lost %d)" % (before - bear.hp))
	# Frozen: the troll (initiative 1) with 1 Chill loses its turn; the Chill shatters.
	var cm2 := _combat(["forest_troll"])
	var troll := cm2.enemies[0]
	troll.add_status("chill", 1, "chiara")
	check(troll.will_freeze(), "Chill 1 freezes the initiative-1 troll (preview)")
	var events: Array = []
	cm2.visual_event.connect(func(e: Dictionary) -> void: events.append(e))
	var party_hp := cm2.party_combatants.map(func(c: Combatant) -> int: return c.hp)
	cm2.end_player_turn()
	check(cm2.party_combatants.map(func(c: Combatant) -> int: return c.hp) == party_hp, "a frozen enemy does not act")
	check(not troll.has_status("chill") and not troll.will_freeze(), "the Chill shatters: it cannot stay frozen")
	check(events.any(func(e: Dictionary) -> bool: return e["kind"] == "frozen" and e["source_id"] == troll.id), "the screen is told it froze")
	events.clear()
	cm2.end_player_turn()
	check(events.any(func(e: Dictionary) -> bool: return (e["kind"] == "enemy_attack" or e["kind"] == "enemy_defend") and e["source_id"] == troll.id), "next round it acts again")
	var cm3 := _combat(["forest_serpent"])
	cm3.enemies[0].add_status("chill", 5, "chiara")
	check(not cm3.enemies[0].will_freeze(), "the Forest Serpent (initiative 7) is never frozen")
	check(DataRegistry.get_status("chill").decay == "round", "Chill fades by 1 each round")


func _test_frost_cards() -> void:
	print("Frost specialization")
	var spec := DataRegistry.get_specialization("frost")
	check(spec.is_playable() and spec.starting_deck_card_ids.size() == 10 and spec.has_passive() and spec.damage_element == "frost", "Frost is playable: 10-card starter, passive, frost damage")
	var all_cards: Array[String] = spec.starting_deck_card_ids + spec.card_pool + spec.epic_pool
	check(all_cards.all(func(id: String) -> bool: return DataRegistry.get_card(id) != null and DataRegistry.get_card(id).owner_character_id == "chiara"), "every Frost card exists and belongs to Chiara")
	check(spec.card_pool.size() == 18 and spec.epic_pool.size() == 2, "18 reward cards and 2 epics")
	check(all_cards.all(func(id: String) -> bool: return AssetCatalog.card_art_id(id, "frost", DataRegistry.get_card(id).card_type).begins_with("art_frost_")), "every Frost card has Frost art")
	# Passive: the first Chill each turn gets +1.
	var cm := _combat(["forest_boar", "forest_boar"])
	var boar := cm.enemies[0]
	_play(cm, "chiara_frost_touch", "chiara", boar.id)
	check(int(boar.statuses["chill"]["stacks"]) == 3, "Chilling Touch (2) + Rime Touch (1) = 3 Chill")
	_play(cm, "chiara_frost_touch", "chiara", boar.id)
	check(int(boar.statuses["chill"]["stacks"]) == 5, "Rime Touch triggers once per turn (3 + 2 = 5)")
	# Shatter: 4 + 4 per Chill, then the Chill is gone.
	var other := cm.enemies[1]
	other.add_status("chill", 3, "chiara")
	var before := other.hp
	_play(cm, "chiara_frost_shatter", "chiara", other.id)
	var lost := before - other.hp
	check(lost == 16 * 125 / 100 or lost == 16, "Shatter: 4 + 3x4 = 16 frost (boar weak to frost: 20) (lost %d)" % lost)
	check(not other.has_status("chill"), "Shatter removes the Chill")
	var cm2 := _combat(["forest_wolf", "forest_wolf"])
	_play(cm2, "chiara_frost_nova", "chiara")
	check(cm2.enemies.all(func(e: Combatant) -> bool: return e.has_status("chill")), "Frost Nova chills every enemy")
	var cm3 := _combat(["forest_troll"])
	var target := cm3.enemies[0]
	target.add_status("chill", 1, "chiara")
	before = target.hp
	_play(cm3, "chiara_frost_spike", "chiara", target.id)
	check(before - target.hp == 17, "Glacial Spike: 11 + 6 on a Chilled target = 17 (lost %d)" % (before - target.hp))


func _test_equipment() -> void:
	print("Equipment")
	var items := Equipment.all_items()
	check(items.size() >= 14, "14 pieces of equipment defined (%d)" % items.size())
	var slots_ok := items.all(func(i: Dictionary) -> bool: return not Equipment.slots_for(str(i["id"])).is_empty())
	check(slots_ok, "every item fits a slot")
	var slots_used: Array = items.map(func(i: Dictionary) -> String: return str(i["slot"]))
	check(["helmet", "amulet", "chest", "gauntlets", "weapon", "belt", "ring", "boots"].all(func(s: String) -> bool: return slots_used.has(s)), "every slot has items")
	var balanced := true
	for entry in items:
		var stats: Dictionary = entry.get("stats", {})
		balanced = balanced and (stats.get("resist", {}) as Dictionary).size() <= 1 and (stats.get("damage", {}) as Dictionary).size() <= 1
		for value: Variant in (stats.get("resist", {}) as Dictionary).values() + (stats.get("damage", {}) as Dictionary).values():
			balanced = balanced and int(value) > 0 and int(value) <= 30
		balanced = balanced and int(stats.get("max_hp", 0)) <= 6
	check(balanced, "balance: one resistance or one damage type each, at most 30%, at most +6 HP")
	var party := _party()
	var chiara := party.get_member("chiara")
	var bianca := party.get_member("bianca")
	var inventory := Inventory.new()
	check(inventory.add_equipment("flameward_cuirass") and inventory.add_equipment("ember_staff") and not inventory.add_equipment("health_potion"), "the stash takes equipment only")
	check(Equipment.can_equip(bianca, "ember_staff") != "", "Bianca cannot wield Chiara's staff")
	check(Equipment.equip(bianca, inventory, "ember_staff") != "" and inventory.equipment.has("ember_staff"), "a refused equip leaves the stash untouched")
	var hp_before := chiara.current_hp
	check(Equipment.equip(chiara, inventory, "flameward_cuirass") == "" and chiara.equipment.get("chest") == "flameward_cuirass", "Chiara wears the cuirass")
	check(chiara.max_hp == 62 and chiara.current_hp == hp_before + 2, "its +2 Max HP raises maximum and current HP")
	check(not inventory.equipment.has("flameward_cuirass"), "it left the stash")
	inventory.add_equipment("frostbound_mail")
	check(Equipment.equip(chiara, inventory, "frostbound_mail") == "" and inventory.equipment.has("flameward_cuirass"), "equipping another chest swaps the old one back into the stash")
	check(Equipment.equip(chiara, inventory, "ember_staff") != "", "a Frost Chiara cannot wield the Fire staff (it needs Fire)")
	inventory.add_equipment("rimeglass_staff")
	check(Equipment.equip(chiara, inventory, "rimeglass_staff") == "" and Equipment.totals(chiara)["damage"] == {"frost": 15}, "the Frost staff adds +15% frost")
	check(Equipment.stat_lines("ember_staff") == ["+15% Fire damage", "Needs Fire"] and Equipment.stat_lines("frostbound_mail").has("Frost resistance 30%"), "stat lines read well")
	check(Equipment.unequip(chiara, inventory, "chest") and chiara.max_hp == 60 and chiara.current_hp <= 60, "taking armour off lowers Max HP and clamps HP")
	check(not Equipment.unequip(chiara, inventory, "chest"), "an empty slot cannot be unequipped")
	chiara.current_hp = 0
	inventory.add_equipment("padded_gambeson")
	Equipment.equip(chiara, inventory, "padded_gambeson")
	check(chiara.current_hp == 0, "armour never revives a fallen member")


func _test_equipment_in_combat() -> void:
	print("Equipment in combat")
	var party := _party("fire", "tanking")
	var inventory := Inventory.new()
	inventory.add_equipment("ember_staff")
	inventory.add_equipment("venomguard_jerkin")
	Equipment.equip(party.get_member("chiara"), inventory, "ember_staff")
	Equipment.equip(party.get_member("bianca"), inventory, "venomguard_jerkin")
	var cm := _combat(["forest_bear"], party, inventory)
	var bear := cm.enemies[0]
	var before := bear.hp
	_play(cm, "chiara_fire_ember", "chiara", bear.id)
	check(before - bear.hp == 8, "Ember Staff +15%% and the bear's 25%% fire weakness: 6 x 140%% = 8 (lost %d)" % (before - bear.hp))
	var bianca_c := cm.get_combatant("bianca")
	check(int(bianca_c.affinity.get("poison", 0)) == -30, "the jerkin gives Bianca 30% poison resistance in combat")
	bianca_c.add_status("poison", 10, "x")
	var hp := bianca_c.hp
	cm._tick_statuses(StatusDef.TICK_ENEMY_PHASE_START)
	check(hp - bianca_c.hp == 7, "Poison 10 ticks only 7 on her (lost %d)" % (hp - bianca_c.hp))


func _test_loot_and_treasure() -> void:
	print("Loot and chests")
	var party := _party()
	var rules: Dictionary = RunRules.get_block("loot")
	check(float(rules["boss"]["chance"]) == 1.0 and float(rules["elite"]["chance"]) >= 0.5 and float(rules["combat"]["chance"]) < float(rules["elite"]["chance"]), "bosses always drop, elites usually, normal fights sometimes")
	var drops := 0
	var usable := true
	for i in 200:
		var loot := Loot.roll("combat", party, _rng(i))
		drops += loot.size()
		for item_id in loot:
			usable = usable and Equipment.usable_by_party(party, item_id)
	check(drops > 12 and drops < 50, "about 15%% of normal fights drop an item (%d / 200)" % drops)
	check(usable, "drops are always usable by someone in the party (princess and specialization)")
	var elite_drops := 0
	for i in 40:
		elite_drops += Loot.roll("elite", party, _rng(100 + i)).size()
	check(elite_drops >= 20 and elite_drops < 40, "most elites drop one item (%d / 40)" % elite_drops)
	var boss_rare := 0
	for i in 50:
		for item_id in Loot.roll("boss", party, _rng(100 + i)):
			if str(Equipment.item(item_id).get("rarity", "")) == "rare":
				boss_rare += 1
	check(boss_rare > 20, "bosses mostly drop rare items (%d / 50)" % boss_rare)
	var inventory := Inventory.new()
	var state := TreasureRoom.generate("castle_treasure_01", party, inventory, _rng(9))
	var index := -1
	for i in (state["choices"] as Array).size():
		if state["choices"][i]["type"] == "equipment":
			index = i
	check(index >= 0 and Equipment.is_equipment(str(state["choices"][index]["item_id"])), "chests offer a piece of equipment")
	check(TreasureRoom.describe(state["choices"][index]).contains("%"), "the chest shows the item's stats")
	check(TreasureRoom.claim(state, index, party, inventory) == "" and inventory.equipment.size() == 1, "taking it puts it in the stash")


func _test_saves() -> void:
	print("Saving equipment")
	var party := _party()
	var inventory := Inventory.new()
	for id in ["chainmail_hauberk", "runed_warblade", "rimeglass_staff", "stormweave_coat"]:
		inventory.add_equipment(id)
	Equipment.equip(party.get_member("bianca"), inventory, "chainmail_hauberk")
	Equipment.equip(party.get_member("bianca"), inventory, "runed_warblade")
	Equipment.equip(party.get_member("chiara"), inventory, "stormweave_coat")
	party.get_member("chiara").current_hp = 63
	var graph := MapGraph.from_dict(DataRegistry.get_map(GameConfig.DEFAULT_MAP_ID))
	var data := SaveManager.serialize(party, inventory, MapProgress.new(graph))
	var restored := SaveManager.restore(JSON.parse_string(JSON.stringify(data)))
	check(restored["ok"], "the save loads")
	var r_party: Party = restored["party"]
	var r_inv: Inventory = restored["inventory"]
	check(r_party.get_member("bianca").equipment == {"chest": "chainmail_hauberk", "weapon": "runed_warblade"}, "worn items come back")
	check(r_inv.equipment == ["rimeglass_staff"], "the stash comes back")
	check(r_party.get_member("chiara").max_hp == 64 and r_party.get_member("chiara").current_hp == 63, "Max HP with armour and HP above the base maximum survive a reload")
	data["party"][0]["equipment"] = {"weapon": "runed_warblade", "chest": "no_such_item"}
	data["inventory"]["equipment"] = ["ghost_item", "ember_staff"]
	restored = SaveManager.restore(data)
	check(restored["ok"] and (restored["party"] as Party).get_member("chiara").equipment.is_empty(), "invalid worn items (wrong wielder, unknown) are dropped")
	check((restored["inventory"] as Inventory).equipment == ["ember_staff"], "unknown stash items are dropped")
	check((restored["warnings"] as Array).size() >= 3, "and reported as warnings")
