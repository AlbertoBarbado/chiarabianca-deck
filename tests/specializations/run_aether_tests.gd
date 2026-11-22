extends SceneTree
## The Arcana + Holy combo: Aether (the party's surplus magic this turn). Chiara's extra draws and
## Energy fill it, Bianca's hymns read it ("per_aether") and spend it ("spend_aether"). Also the new
## cards, starting decks, presentation (art, effects, keyword colour) and the counter's limits. Run:
##   godot --headless --path . --script res://tests/specializations/run_aether_tests.gd

const ARCANA_NEW := ["chiara_arcana_siphon", "chiara_arcana_echo", "chiara_arcana_weave", "chiara_arcana_aetherlance"]
const HOLY_NEW := ["bianca_holy_hymn", "bianca_holy_lightfall", "bianca_holy_cascade", "bianca_holy_wellspring"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_data()
	_test_gaining()
	_test_payoffs()
	_test_limits()
	_test_presentation()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(chiara_spec: String = "arcana", bianca_spec: String = "holy") -> CombatManager:
	var party := Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})
	for spec_id in [chiara_spec, bianca_spec]:
		var spec := DataRegistry.get_specialization(spec_id)
		for card_id in spec.card_pool:
			party.get_member(spec.character_id).add_card(card_id)
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new(), 7)
	cm.start()
	cm.energy = 40
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


func _foe(cm: CombatManager) -> Combatant:
	var foe := cm.get_living_enemies()[0]
	foe.hp = 999
	foe.max_hp = 999
	foe.block = 0
	return foe


func _test_data() -> void:
	print("Cards and decks")
	var arcana := DataRegistry.get_specialization("arcana")
	var holy := DataRegistry.get_specialization("holy")
	check(ARCANA_NEW.all(func(id: String) -> bool: return arcana.card_pool.has(id)), "Arcana's pool has Ley Siphon, Arcane Echo, Leyline Weave and Aether Lance")
	check(HOLY_NEW.all(func(id: String) -> bool: return holy.card_pool.has(id)), "Holy's pool has Hymn of Dawn, Lightfall, Radiant Cascade and Wellspring Prayer")
	check(arcana.starting_deck_card_ids.count("chiara_arcana_siphon") == 1 and arcana.starting_deck_card_ids.count("chiara_arcana_bolt") == 3, "Arcana starts with 3 Arcane Bolts and a Ley Siphon")
	check(holy.starting_deck_card_ids.count("bianca_holy_hymn") == 1 and holy.starting_deck_card_ids.size() == 10, "Holy starts with a Hymn of Dawn (10 cards)")
	var all_ok := true
	for id: String in ARCANA_NEW + HOLY_NEW:
		var def := DataRegistry.get_card(id)
		all_ok = all_ok and def != null and not def.upgrade.is_empty() and def.description.length() <= 72
	check(all_ok, "every new card exists, upgrades and has a short description")
	check(HOLY_NEW.all(func(id: String) -> bool: return CardEffects.uses_aether(DataRegistry.get_card(id))), "every new Holy card uses Aether")
	check(not CardEffects.uses_aether(DataRegistry.get_card("chiara_arcana_echo")) and CardEffects.uses_aether(DataRegistry.get_card("chiara_arcana_aetherlance")), "generators do not count as Aether cards; Aether Lance does")


func _test_gaining() -> void:
	print("Gaining Aether")
	var cm := _combat()
	check(cm.aether == 0 and cm.deck.hand.size() >= 5, "the turn's normal draw gives no Aether")
	_play(cm, "chiara_arcana_focus")
	check(cm.aether == 1, "Gathering Focus (draw 1) gives 1 Aether (%d)" % cm.aether)
	_play(cm, "chiara_arcana_surge")
	check(cm.aether == 3, "Mana Surge (+2 Energy) gives 2 more (%d)" % cm.aether)
	var foe := _foe(cm)
	_play(cm, "chiara_arcana_siphon", foe.id)
	check(cm.aether == 4, "Ley Siphon's draw adds 1 (%d)" % cm.aether)
	# Arcane Flow: Bianca's card, then Chiara's, draws 1 for the party, which is also Aether.
	cm.end_player_turn()
	cm.energy = 40
	check(cm.aether == 0, "unused Aether fades when a new turn begins")
	_play(cm, "bianca_holy_shield")
	_play(cm, "chiara_arcana_ward")
	check(cm.aether == 1, "Arcane Flow's extra draw gives Aether too (%d)" % cm.aether)
	# Draws that find no card give nothing.
	var cm2 := _combat()
	cm2.deck.draw_pile.clear()
	cm2.deck.discard_pile.clear()
	_play(cm2, "chiara_arcana_focus")
	check(cm2.aether == 0, "a draw with no cards left gives no Aether")


func _test_payoffs() -> void:
	print("Holy payoffs")
	var cm := _combat()
	var foe := _foe(cm)
	cm.aether = 3
	_play(cm, "bianca_holy_hymn", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 4 + 1 * 3 and cm.aether == 3, "Hymn of Dawn: 4 + 1 per Aether (7), Aether kept")
	_play(cm, "bianca_holy_cascade")
	check(int(cm.last_hit.get("base", 0)) == 2 + 3, "Radiant Cascade: 2 + 1 per Aether to all")
	_play(cm, "chiara_arcana_aetherlance", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 6 + 2 * 3, "Aether Lance: 6 + 2 per Aether (Chiara's own payoff)")
	check(cm.aether == 4, "Chiara's card after Bianca's set off Arcane Flow: one more Aether (%d)" % cm.aether)
	_play(cm, "bianca_holy_lightfall", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 6 + 3 * 4 and cm.aether == 0, "Lightfall: 6 + 3 per Aether (18), then releases it all")
	_play(cm, "bianca_holy_lightfall", foe.id)
	check(int(cm.last_hit.get("base", 0)) == 6, "Lightfall with no Aether is a plain 6")
	var cm2 := _combat()
	var bianca := cm2.get_combatant("bianca")
	var chiara := cm2.get_combatant("chiara")
	bianca.hp = 10
	chiara.hp = 10
	bianca.block = 0
	chiara.block = 0
	cm2.aether = 4
	_play(cm2, "bianca_holy_wellspring")
	check(chiara.block == 3 + 2 * 4 and bianca.block >= 3 + 2 * 4 and cm2.aether == 0, "Wellspring Prayer: party Block 3 + 2 per Aether, Aether released")
	_play(cm2, "bianca_holy_wellspring")
	check(chiara.block == 11 + 3, "with no Aether it only gives its base Block")
	# The upgrade scales harder.
	var cm3 := _combat()
	var foe3 := _foe(cm3)
	var hymn := _to_hand(cm3, "bianca_holy_hymn")
	hymn.upgrade_level = 1
	cm3.aether = 2
	cm3.play_card(hymn, foe3.id)
	check(int(cm3.last_hit.get("base", 0)) == 5 + 2 * 2, "Hymn of Dawn+: 5 + 2 per Aether")


func _test_limits() -> void:
	print("Limits")
	var cm := _combat()
	cm.add_aether(20)
	check(cm.aether == CombatManager.MAX_AETHER, "Aether is capped at %d" % CombatManager.MAX_AETHER)
	cm.aether = 0
	cm.state = CombatManager.State.ENEMY_TURN
	cm.add_aether(2)
	check(cm.aether == 0, "nothing is gained outside the player's turn")
	cm.state = CombatManager.State.PLAYER_TURN
	var events: Array = []
	cm.visual_event.connect(func(e: Dictionary) -> void: events.append(e))
	cm.aether = 2
	_play(cm, "bianca_holy_lightfall", _foe(cm).id)
	check(events.any(func(e: Dictionary) -> bool: return e.kind == "aether_spent" and int(e.amount) == 2), "releasing Aether announces how much was spent")
	# Without Arcana the combo still works, only weaker: Fire + Holy has little Aether.
	var fire := _combat("fire", "holy")
	check(fire.aether == 0, "Fire + Holy starts with no Aether either")


func _test_presentation() -> void:
	print("Presentation")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/art_catalog.json"))
	var by_card: Dictionary = catalog["card_art"]["by_card"]
	var art_ok := true
	for id: String in ARCANA_NEW + HOLY_NEW:
		var asset_id := str(by_card.get(id, ""))
		var path := str(catalog["assets"].get(asset_id, {}).get("path", ""))
		art_ok = art_ok and asset_id != "" and ResourceLoader.exists(path)
	check(art_ok, "every new card has its own generated picture")
	check(str(catalog["icons"].get("aether", "")) == "icon_aether" and ResourceLoader.exists(str(catalog["assets"]["icon_aether"]["path"])), "Aether has its own icon")
	check(VfxCatalog.match_event({"kind": "aether_spent", "card_id": "bianca_holy_lightfall", "specialization_id": "holy"}) == "aether_release", "releasing Aether has its own visual effect")
	check(VfxCatalog.match_event({"kind": "damage", "card_id": "bianca_holy_lightfall", "specialization_id": "holy"}) == "lightfall", "Lightfall strikes with a pillar of light")
	var text := CardTextFormat.to_bbcode("Deal 4 damage, +2 per Aether.", false)
	check(text.contains(CardTextFormat.AETHER_COLOR.to_html(false)), "the word Aether is highlighted in violet on cards")
