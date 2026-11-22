extends SceneTree
## Twin combos: Wind (Chiara) and Venom (Bianca, replaces Vanguard), Gust tokens, Momentum, Blight,
## the twin reactions (Combustion, Miasma, Fanned Oil, Black Ice, Frostbite, Shatterlight, Purifying
## Flame, Searing Bash), the cross-combo cards in the other pools and the combo guide. Run:
##   godot --headless --path . --script res://tests/specializations/run_twin_combo_tests.gd

const CHIARA_SPECS := ["arcana", "fire", "frost", "wind"]
const BIANCA_SPECS := ["tanking", "holy", "ashveil", "venom"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	Reactions.reload()
	_test_specializations()
	_test_gusts_and_momentum()
	_test_venom_and_blight()
	_test_reactions()
	_test_cross_cards()
	_test_combo_guide()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(chiara_spec: String, bianca_spec: String, encounter: String = "castle_final_regular_01") -> CombatManager:
	var party := Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})
	for spec_id in [chiara_spec, bianca_spec]:
		var spec := DataRegistry.get_specialization(spec_id)
		for card_id in spec.card_pool + spec.epic_pool:
			party.get_member(spec.character_id).add_card(card_id)
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter(encounter), Inventory.new(), 11)
	cm.start()
	cm.energy = 40
	for enemy in cm.enemies:
		enemy.max_hp = 999
		enemy.hp = 999
		enemy.affinity.clear()  # plain numbers: no weakness or resistance
	return cm


func _card(cm: CombatManager, card_id: String) -> CardInstance:
	for pile: Array[CardInstance] in [cm.deck.hand, cm.deck.draw_pile, cm.deck.discard_pile]:
		for card in pile:
			if card.definition.id == card_id:
				if pile != cm.deck.hand:
					pile.erase(card)
					cm.deck.hand.append(card)
				return card
	# Not in the deck (another specialization's card): conjure an instance for the test.
	var def := DataRegistry.get_card(card_id)
	var made := CardInstance.new()
	made.definition = def
	made.owner_character_id = def.owner_character_id
	cm.deck.hand.append(made)
	return made


func _play(cm: CombatManager, card_id: String, target_id: String = "") -> bool:
	var card := _card(cm, card_id)
	return card != null and cm.play_card(card, target_id)


func _stacks(c: Combatant, status_id: String) -> int:
	return int(c.statuses.get(status_id, {}).get("stacks", 0))


func _gusts(cm: CombatManager) -> int:
	return cm.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.id == "chiara_wind_gust").size()


func _test_specializations() -> void:
	print("Wind and Venom")
	var wind := DataRegistry.get_specialization("wind")
	var venom := DataRegistry.get_specialization("venom")
	check(wind != null and wind.is_playable() and wind.character_id == "chiara" and wind.has_passive(), "Wind is Chiara's playable specialization with a passive (Tailwind)")
	check(venom != null and venom.is_playable() and venom.character_id == "bianca" and venom.has_passive(), "Venom is Bianca's playable specialization with a passive (Lingering Venom)")
	check(DataRegistry.get_specialization("vanguard") == null and DataRegistry.get_character("bianca").specialization_ids.has("venom"), "Venom replaces Vanguard")
	for spec in [wind, venom]:
		var ok: bool = spec.starting_deck_card_ids.size() == 10 and spec.card_pool.size() == 19 and spec.epic_pool.size() == 2
		for card_id: String in spec.starting_deck_card_ids + spec.card_pool + spec.epic_pool:
			var def := DataRegistry.get_card(card_id)
			ok = ok and def != null and def.owner_character_id == spec.character_id and def.specialization_id == spec.id and not def.upgrade.is_empty() and not def.token
		check(ok, "%s: 10-card starting deck, 19 rewards, 2 epics, all owned and upgradeable" % spec.display_name)
	var gust := DataRegistry.get_card("chiara_wind_gust")
	check(gust != null and gust.token and gust.cost == 0 and not wind.card_pool.has(gust.id), "Gust is a 0-cost token, never a reward")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/art_catalog.json"))
	var by_card: Dictionary = catalog["card_art"]["by_card"]
	var mapped := true
	for spec in [wind, venom]:
		for card_id: String in spec.starting_deck_card_ids + spec.card_pool + spec.epic_pool:
			mapped = mapped and by_card.has(card_id)
	check(mapped and by_card.has("chiara_wind_gust"), "every Wind and Venom card names its own picture")
	var venom_idle := CombatPresentation.character_state("bianca", "idle", "venom")
	check(venom_idle != null and venom_idle == CombatPresentation.character_state("bianca", "idle", "ashveil") and venom_idle != CombatPresentation.character_state("bianca", "idle"), "Venom Bianca wears the Ashveil gear")


func _test_gusts_and_momentum() -> void:
	print("Gusts and Momentum")
	var cm := _combat("wind", "tanking")
	var foe := cm.enemies[0]
	cm.deck.hand.clear()
	_play(cm, "chiara_wind_flurry")
	check(_gusts(cm) == 2 and cm.cards_played_this_turn == 1, "Flurry adds 2 Gusts; Momentum counts 1 card")
	var gust := cm.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.id == "chiara_wind_gust")[0] as CardInstance
	var hp := foe.hp
	cm.play_card(gust, foe.id)
	check(foe.hp == hp - 3 and not cm.deck.discard_pile.has(gust) and not cm.deck.exhaust_pile.has(gust), "a played Gust deals 3 and vanishes")
	var second := cm.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.id == "chiara_wind_gust")[0] as CardInstance
	cm.play_card(second, foe.id)
	check(_gusts(cm) == 1, "the third card of the turn (a Gust) sets off Tailwind: a new Gust")
	_play(cm, "chiara_wind_bolt", foe.id)
	check(_gusts(cm) == 1, "Tailwind fires only once per turn")
	var played := cm.cards_played_this_turn
	_play(cm, "chiara_wind_galeforce", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 6 + 3 * played, "Gale Force: 6 + 3 per card already played (%d played)" % played)
	cm.end_player_turn()
	var tokens_left := cm.deck.discard_pile.any(func(c: CardInstance) -> bool: return c.definition.token) or cm.deck.draw_pile.any(func(c: CardInstance) -> bool: return c.definition.token)
	check(not tokens_left and cm.cards_played_this_turn == 0, "unplayed Gusts fade at the end of the turn; Momentum resets")
	cm.energy = 40
	cm.deck.hand.clear()
	for i in 12:
		cm.deck.add_tokens(DataRegistry.get_card("chiara_wind_gust"), 1)
	check(cm.deck.hand.size() == PartyDeck.MAX_HAND_SIZE, "a full hand takes no more Gusts")
	# Scatter spreads Bianca's debuffs.
	var cm2 := _combat("wind", "venom")
	var a := cm2.enemies[0]
	a.add_status("poison", 6, "bianca")
	a.add_status("blight", 4, "bianca")
	_play(cm2, "chiara_wind_scatter", a.id)
	var others_ok := cm2.get_living_enemies().filter(func(e: Combatant) -> bool: return e != a).all(func(e: Combatant) -> bool: return _stacks(e, "poison") >= 3 and _stacks(e, "blight") == 2)
	check(cm2.enemies.size() > 1 and others_ok, "Scatter spreads half of each debuff (Poison and Blight) to the other enemies")


func _test_venom_and_blight() -> void:
	print("Venom and Blight")
	var cm := _combat("arcana", "venom")
	var foe := cm.enemies[0]
	_play(cm, "bianca_venom_envenom", foe.id)
	check(_stacks(foe, "poison") == 3, "Envenom applies 3 Poison")
	_play(cm, "bianca_venom_envenom", foe.id)
	check(_stacks(foe, "poison") == 3 + 3 + 2, "Lingering Venom: Poison on an already Poisoned foe gains 2 extra (8)")
	_play(cm, "bianca_venom_envenom", foe.id)
	check(_stacks(foe, "poison") == 11, "once per turn")
	_play(cm, "bianca_venom_catalyst", foe.id)
	check(_stacks(foe, "poison") == 22, "Catalyst doubles it (22)")
	_play(cm, "bianca_venom_reaping", foe.id)
	check(_stacks(foe, "blight") == 66, "Plague Reaping: Blight equal to 3x the Poison (66)")
	cm.aether = 2
	var other := cm.enemies[1] if cm.enemies.size() > 1 else foe
	var before := _stacks(other, "poison")
	_play(cm, "bianca_venom_distill", other.id)
	check(_stacks(other, "poison") - before >= 3 + 2, "Distilled Venom: 3 Poison + 1 per Aether")
	# Blight executes at the start of the enemy phase once HP is at or below it.
	var cm2 := _combat("fire", "venom")
	var low := cm2.enemies[0]
	low.hp = 30
	low.add_status("blight", 25, "bianca")
	low.add_status("poison", 6, "bianca")
	var high := cm2.enemies[1] if cm2.enemies.size() > 1 else null
	if high != null:
		high.hp = 100
		high.add_status("blight", 25, "bianca")
	cm2.end_player_turn()
	check(not low.is_alive(), "Poison brings it to 24 HP, then Blight 25 executes it")
	check(high == null or (high.is_alive() and _stacks(high, "blight") == 25), "a healthier foe survives and its Blight never fades")
	check(DataRegistry.get_status("blight").execute and DataRegistry.get_status("blight").short_text(10).contains("10 HP"), "Blight explains itself: dies at 10 HP or less")


func _test_reactions() -> void:
	print("Twin reactions")
	# Fire + Venom: Combustion.
	var cm := _combat("fire", "venom")
	var foe := cm.enemies[0]
	foe.add_status("poison", 8, "bianca")
	var others := cm.get_living_enemies().filter(func(e: Combatant) -> bool: return e != foe)
	var other_hp := (others[0] as Combatant).hp if not others.is_empty() else 0
	var hp := foe.hp
	_play(cm, "chiara_fire_ember", foe.id)
	check(not foe.has_status("poison") and foe.hp == hp - 6 - 24, "Combustion: Fire on 8 Poison deals 6 + 24 and burns the Poison away")
	check(others.is_empty() or (others[0] as Combatant).hp == other_hp - 24, "and the explosion hits every other enemy for 24")
	check(cm.reactions_fired == 1, "one reaction (its own damage does not react again)")
	# Wind + Venom: Miasma.
	cm = _combat("wind", "venom")
	foe = cm.enemies[0]
	foe.add_status("poison", 6, "bianca")
	_play(cm, "chiara_wind_bolt", foe.id)
	var spread_ok := cm.get_living_enemies().filter(func(e: Combatant) -> bool: return e != foe).all(func(e: Combatant) -> bool: return _stacks(e, "poison") == 3)
	check(cm.enemies.size() > 1 and spread_ok and _stacks(foe, "poison") == 6, "Miasma: a Wind hit blows half the Poison (3) onto every other enemy")
	# Wind + Ashveil: Fanned Oil.
	cm = _combat("wind", "ashveil")
	foe = cm.enemies[0]
	foe.add_status("oiled", 2, "bianca")
	_play(cm, "chiara_wind_bolt", foe.id)
	check(cm.get_living_enemies().filter(func(e: Combatant) -> bool: return e != foe).all(func(e: Combatant) -> bool: return _stacks(e, "oiled") == 1), "Fanned Oil: Wind sprays Oiled onto the others")
	# Frost + Ashveil: Black Ice. Frost + Venom: Frostbite.
	cm = _combat("frost", "ashveil")
	foe = cm.enemies[0]
	foe.add_status("oiled", 1, "bianca")
	_play(cm, "chiara_frost_bolt", foe.id)
	check(_stacks(foe, "chill") >= 1 + 1 + 1, "Black Ice: Frost on an Oiled foe adds 1 extra Chill (%d)" % _stacks(foe, "chill"))
	cm = _combat("frost", "venom")
	foe = cm.enemies[0]
	foe.add_status("poison", 3, "bianca")
	_play(cm, "chiara_frost_bolt", foe.id)
	check(_stacks(foe, "poison") == 5, "Frostbite: Frost on a Poisoned foe adds 2 Poison")
	# Frost + Holy: Shatterlight.
	cm = _combat("frost", "holy")
	foe = cm.enemies[0]
	foe.add_status("chill", 3, "chiara")
	hp = foe.hp
	_play(cm, "bianca_holy_strike", foe.id)
	check(not foe.has_status("chill") and foe.hp == hp - 5 - 6, "Shatterlight: Holy shatters 3 Chill for 6 more damage")
	# Fire + Holy: Purifying Flame. Fire + Tanking: Searing Bash.
	cm = _combat("fire", "holy")
	foe = cm.enemies[0]
	foe.add_status("burn", 3, "chiara")
	var bianca := cm.get_combatant("bianca")
	bianca.block = 0
	_play(cm, "bianca_holy_strike", foe.id)
	check(bianca.block == 3, "Purifying Flame: Bianca gains 1 Block per Burn (3)")
	cm = _combat("fire", "tanking")
	foe = cm.enemies[0]
	foe.add_status("burn", 2, "chiara")
	_play(cm, "bianca_tanking_strike", foe.id)
	check(_stacks(foe, "burn") == 3, "Searing Bash: a physical blow adds 1 Burn")
	# Enemy attacks never react; non-matching elements do nothing.
	cm = _combat("fire", "venom")
	var chiara := cm.get_combatant("chiara")
	chiara.add_status("poison", 5, "x")
	cm.hit(chiara, 4, "fire", cm.enemies[0])
	check(chiara.has_status("poison") and cm.reactions_fired == 0, "an enemy's Fire on a Poisoned princess sets nothing off")
	check(Reactions.all().size() == 8, "eight reactions in the table")


func _test_cross_cards() -> void:
	print("Cross-combo cards")
	var cm := _combat("arcana", "tanking")
	var bianca := cm.get_combatant("bianca")
	bianca.block = 0
	cm.aether = 3
	_play(cm, "bianca_tanking_runic")
	check(bianca.block >= 4 + 2 * 3, "Runic Bastion: 4 Block + 2 per Aether")
	cm = _combat("wind", "tanking")
	var foe := cm.enemies[0]
	_play(cm, "chiara_wind_ward")
	_play(cm, "chiara_wind_ward")
	_play(cm, "bianca_tanking_momentum", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 5 + 3 * 2, "Momentum Bash: 5 + 3 per card already played")
	foe.add_status("burn", 1, "chiara")
	_play(cm, "bianca_tanking_brand", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 7 + 4, "Branding Bash: +4 against a Burning foe")
	cm = _combat("frost", "holy")
	foe = cm.enemies[0]
	foe.add_status("chill", 1, "chiara")
	var sun_hp := foe.hp
	_play(cm, "bianca_holy_sunfire", foe.id)
	check(sun_hp - foe.hp == 6 + 3 + 2, "Sunfire Smite: +3 against a Chilled foe (and Shatterlight adds 2)")
	cm = _combat("arcana", "ashveil")
	cm.aether = 2
	_play(cm, "bianca_ash_hexpowder")
	check(int(cm.last_hit.get("base", 0)) == 3 + 2 and str(cm.last_hit.get("element", "")) == "fire", "Hexed Powder: 3 Fire + 1 per Aether to all")
	var pools_ok := true
	for spec_id in CHIARA_SPECS + BIANCA_SPECS:
		pools_ok = pools_ok and DataRegistry.get_specialization(spec_id).card_pool.size() >= 9
	check(pools_ok, "every playable specialization offers at least 9 reward cards")


func _test_combo_guide() -> void:
	print("Combo guide")
	var complete := true
	var strong := 0
	for chiara in CHIARA_SPECS:
		for bianca in BIANCA_SPECS:
			var combo := TwinCombos.for_pair(chiara, bianca)
			complete = complete and not combo.is_empty() and str(combo.get("text", "")) != ""
			if int(combo.get("strength", 0)) >= 3:
				strong += 1
	check(complete, "all 16 Chiara x Bianca pairings have a combo in the guide")
	check(strong == 5, "five signature (3-star) combos: Aether Hymns, Ignition, Combustion, Brittle, Miasma")
	var pairs_ok := Reactions.all().all(func(r: Dictionary) -> bool:
		var pair: Array = r.get("pair", [])
		return pair.size() == 2 and not TwinCombos.for_pair(str(pair[0]), str(pair[1])).is_empty())
	check(pairs_ok, "every reaction belongs to a pairing in the guide")
	check(TwinCombos.stars({"strength": 2}) == "★★☆", "stars read ★★☆ for a strong combo")
