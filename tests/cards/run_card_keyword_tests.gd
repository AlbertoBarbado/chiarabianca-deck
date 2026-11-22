extends SceneTree
## Card keywords and the card-pool expansion: real Powers (passives and stat bonuses for the rest
## of the combat), Retain, X cost, Exhaust triggers, thorns, end-of-turn powers and Entrench, plus
## data checks on every specialization pool. Run:
##   godot --headless --path . --script res://tests/cards/run_card_keyword_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_pools()
	_test_retain()
	_test_x_cost()
	_test_stat_power()
	_test_trigger_powers()
	_test_thorns_and_turn_end()
	_test_exhaust_event()
	_test_entrench()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(chiara: String = "fire", bianca: String = "tanking", enemies: Array = ["forest_troll"]) -> CombatManager:
	var cm := CombatManager.new()
	cm.setup(Party.from_selection({"chiara": chiara, "bianca": bianca}), {"id": "qa", "name": "QA", "enemies": enemies, "gold_reward": 0}, Inventory.new(), 11)
	cm.start()
	return cm


func _give(cm: CombatManager, card_id: String, upgraded: bool = false) -> CardInstance:
	var card := CardInstance.new()
	card.definition = DataRegistry.get_card(card_id)
	card.owner_character_id = card.definition.owner_character_id
	card.upgrade_level = 1 if upgraded else 0
	card.owned_uid = "qa_%s_%d" % [card_id, cm.deck.hand.size()]
	cm.deck.hand.append(card)
	return card


func _enemy(cm: CombatManager) -> Combatant:
	return cm.get_living_enemies()[0]


func _test_pools() -> void:
	var names: Dictionary = {}
	for spec_id in ["fire", "frost", "arcana", "wind", "holy", "tanking", "venom", "ashveil"]:
		var spec := DataRegistry.get_specialization(spec_id)
		check(spec != null and spec.card_pool.size() >= 18, "%s offers at least 18 reward cards (%d)" % [spec_id, spec.card_pool.size() if spec != null else 0])
		var missing := 0
		var powers := 0
		var keywords := {"retain": 0, "x": 0, "exhaust": 0}
		for card_id: String in spec.card_pool:
			var def := DataRegistry.get_card(card_id)
			if def == null:
				missing += 1
				continue
			if def.card_type == CardDef.TYPE_POWER and def.effects.any(func(e: Dictionary) -> bool: return str(e.get("effect", "")) == "power"):
				powers += 1
			keywords["retain"] += 1 if def.retain else 0
			keywords["x"] += 1 if def.x_cost else 0
			keywords["exhaust"] += 1 if def.exhausts and def.card_type != CardDef.TYPE_POWER else 0
			var art := AssetCatalog.card_art_id(def.id, def.specialization_id, def.card_type)
			check(AssetCatalog.texture(art) != null or not FileAccess.file_exists("res://assets/generated/cards/card_%s.png" % def.id.split("_", true, 1)[1]), "%s has its art or its file is not generated yet" % def.id)
			var key := "%s|%s" % [def.owner_character_id, def.display_name]
			check(not names.has(key), "%s's card name '%s' is unique" % [def.owner_character_id, def.display_name])
			names[key] = true
		check(missing == 0, "%s's pool has no unknown cards" % spec_id)
		check(powers >= 2, "%s has at least 2 real Powers (%d)" % [spec_id, powers])
		check(keywords["retain"] >= 1 and keywords["x"] >= 1 and keywords["exhaust"] >= 1, "%s has Retain, X-cost and Exhaust cards %s" % [spec_id, keywords])


func _test_retain() -> void:
	var cm := _combat()
	var kept := _give(cm, "chiara_fire_banked")
	var plain := _give(cm, "chiara_fire_fireball")
	cm.end_player_turn()
	check(cm.deck.hand.has(kept), "a Retain card stays in the hand at the end of the turn")
	check(not cm.deck.hand.has(plain), "a normal card is discarded")
	check(kept.retains() and not plain.retains(), "CardInstance.retains reads the keyword")


func _test_x_cost() -> void:
	var cm := _combat()
	var enemy := _enemy(cm)
	enemy.max_hp = 999
	enemy.hp = 999
	cm.energy = 3
	var storm := _give(cm, "chiara_fire_firestorm")
	check(storm.get_cost() == 0 and cm.can_play(storm) == "", "an X card is playable and shows cost 0 to the rules")
	var before := enemy.hp
	cm.play_card(storm, enemy.id)
	check(cm.energy == 0, "playing an X card spends all the Energy")
	var one_hit := DamageTypes.apply(5, "fire", cm.get_combatant("chiara"), enemy)
	check(before - enemy.hp == one_hit * 3, "Firestorm at X = 3 deals its 5 damage 3 times (%d = 3 x %d after the troll's fire weakness)" % [before - enemy.hp, one_hit])
	var gather := _give(cm, "chiara_wind_gather")
	cm.energy = 2
	var hand_before := cm.deck.hand.size()
	cm.play_card(gather, "")
	check(cm.deck.hand.size() == hand_before - 1 + 3, "Gather the Winds at X = 2 adds X+1 = 3 Gusts")


func _test_stat_power() -> void:
	var cm := _combat("arcana")
	var enemy := _enemy(cm)
	enemy.max_hp = 999
	enemy.hp = 999
	cm.energy = 10
	cm.play_card(_give(cm, "chiara_arcana_mastery"), "")
	var chiara := cm.get_combatant("chiara")
	check(chiara.power_damage == 3 and chiara.powers.size() == 1, "Arcane Mastery adds +3 damage to Chiara as a lasting power")
	check(not cm.deck.discard_pile.any(func(c: CardInstance) -> bool: return c.definition.id == "chiara_arcana_mastery"), "a Power goes to the exhaust pile, never back to the deck")
	var lance := _give(cm, "chiara_arcana_prepared")
	var preview := CardEffects.damage_preview(lance, cm, enemy)
	var before := enemy.hp
	cm.play_card(lance, enemy.id)
	check(before - enemy.hp == 12 and int(preview[0]["final"]) == 12, "Prepared Spell deals 9 + 3, and the card text preview shows 12 (%d)" % (before - enemy.hp))
	cm.play_card(_give(cm, "chiara_arcana_mastery"), "")
	check(chiara.power_damage == 6 and chiara.powers.size() == 1 and int(chiara.powers[0]["count"]) == 2, "a second copy stacks on the same chip (x2)")


func _test_trigger_powers() -> void:
	var cm := _combat("fire")
	var enemy := _enemy(cm)
	enemy.max_hp = 999
	enemy.hp = 999
	cm.energy = 10
	cm.play_card(_give(cm, "chiara_fire_afterglow"), "")
	cm.end_player_turn()
	check(cm.state == CombatManager.State.PLAYER_TURN and enemy.has_status("burn"), "Afterglow burns every enemy at the start of the next turn")
	cm.energy = 10
	cm.play_card(_give(cm, "chiara_fire_pyromancy"), "")
	var before := enemy.hp
	cm.play_card(_give(cm, "chiara_fire_kindle"), enemy.id)
	check(before - enemy.hp >= 2, "Pyromancy hurts an enemy when Chiara applies Burn (%d)" % (before - enemy.hp))
	var wind := _combat("wind")
	wind.energy = 10
	wind.play_card(_give(wind, "chiara_wind_zephyr"), "")
	wind.end_player_turn()
	var gusts := wind.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.id == "chiara_wind_gust").size()
	check(gusts >= 1, "Zephyr Stance adds a Gust at the start of each turn (%d)" % gusts)


func _test_thorns_and_turn_end() -> void:
	var cm := _combat("fire", "tanking")
	var enemy := _enemy(cm)
	enemy.max_hp = 999
	enemy.hp = 999
	cm.energy = 10
	cm.play_card(_give(cm, "bianca_tanking_ironskin"), "")
	cm.play_card(_give(cm, "bianca_tanking_spikes"), "")
	var bianca := cm.get_combatant("bianca")
	bianca.block = 0
	cm.deck.hand.clear()
	cm.passives.on_event({"type": "turn_end", "turn": cm.turn})
	check(bianca.block == 3, "Iron Skin gives Bianca 3 Block at the end of the turn (%d)" % bianca.block)
	var before := enemy.hp
	cm.passives.on_event({"type": "attacked", "source": enemy, "target": bianca})
	check(before - enemy.hp == DamageTypes.apply(3, "physical", bianca, enemy) and before - enemy.hp > 0, "Spiked Bulwark hurts an enemy that attacks Bianca (%d)" % (before - enemy.hp))
	before = enemy.hp
	cm.passives.on_event({"type": "attacked", "source": enemy, "target": cm.get_combatant("chiara")})
	check(enemy.hp == before, "but not one that attacks Chiara")


func _test_exhaust_event() -> void:
	var cm := _combat()
	var seen: Array = []
	cm.passives.add_power("chiara", {"id": "qa_watch", "name": "QA", "trigger": {"event": "card_exhausted"}, "effect": {"effect": "gain_aether", "value": 1}, "limit_per_turn": 99})
	cm.energy = 10
	var aether_before := cm.aether
	cm.play_card(_give(cm, "chiara_fire_ignition"), "")
	check(cm.aether > aether_before + 1, "playing an Exhaust card sends a card_exhausted event to powers")
	check(cm.deck.exhaust_pile.any(func(c: CardInstance) -> bool: return c.definition.id == "chiara_fire_ignition"), "and the card is in the exhaust pile")


func _test_entrench() -> void:
	var cm := _combat("fire", "tanking")
	var bianca := cm.get_combatant("bianca")
	bianca.block = 9
	cm.energy = 10
	cm.play_card(_give(cm, "bianca_tanking_entrench"), "")
	check(bianca.block == 18, "Entrench doubles Bianca's Block (%d)" % bianca.block)
	cm.play_card(_give(cm, "bianca_tanking_unbreakable"), "")
	bianca.block = 0
	cm.play_card(_give(cm, "bianca_tanking_brace"), "")
	check(bianca.block == 12, "Unbreakable adds 3 Block to Bracing Stance's 9 (%d)" % bianca.block)
