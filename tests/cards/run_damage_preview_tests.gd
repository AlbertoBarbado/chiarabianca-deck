extends SceneTree
## Damage preview on cards in hand (CardEffects.damage_preview + CardTextFormat): the number the card
## would really deal replaces the printed one. Run:
##   godot --headless --path . --script res://tests/cards/run_damage_preview_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	Reactions.reload()
	_test_numbers()
	_test_text()
	_test_matches_real_hits()
	_test_every_card_text()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(chiara_spec: String, bianca_spec: String) -> CombatManager:
	var party := Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter("castle_final_regular_01"), Inventory.new(), 11)
	cm.start()
	cm.energy = 40
	for enemy in cm.enemies:
		enemy.max_hp = 999
		enemy.hp = 999
		enemy.block = 0
		enemy.affinity.clear()
	for c in cm.party_combatants:
		c.damage_bonus.clear()
	return cm


func _make(cm: CombatManager, card_id: String, upgraded: bool = false) -> CardInstance:
	var def := DataRegistry.get_card(card_id)
	var card := CardInstance.new()
	card.definition = def
	card.owner_character_id = def.owner_character_id
	card.upgrade_level = 1 if upgraded else 0
	cm.deck.hand.append(card)
	return card


func _finals(preview: Array[Dictionary]) -> Array:
	return preview.map(func(e: Dictionary) -> int: return int(e["final"]))


func _test_numbers() -> void:
	var cm := _combat("fire", "holy")
	var foe: Combatant = cm.get_living_enemies()[0]
	var ember := _make(cm, "chiara_fire_ember")
	check(_finals(CardEffects.damage_preview(ember, cm)) == [6], "Ember Bolt previews its printed 6 with nothing in play")
	check(_finals(CardEffects.damage_preview(_make(cm, "chiara_fire_ember", true), cm)) == [9], "the upgraded copy previews its upgraded 9")
	cm.get_combatant("chiara").damage_bonus = {"fire": 50}
	check(_finals(CardEffects.damage_preview(ember, cm)) == [9], "a +50% fire weapon raises it to 9 without a target")
	cm.get_combatant("chiara").damage_bonus.clear()
	foe.affinity = {"fire": 50}
	check(_finals(CardEffects.damage_preview(ember, cm)) == [6] and _finals(CardEffects.damage_preview(ember, cm, foe)) == [9], "a fire weakness shows only against that target (6 -> 9)")
	foe.affinity.clear()
	var twin := _make(cm, "chiara_arcana_twinbolt")
	check(CardEffects.damage_preview(twin, cm).size() == 1, "Twin Bolt's two identical hits preview as one number")
	var hymn := _make(cm, "bianca_holy_hymn")
	cm.aether = 3
	check(_finals(CardEffects.damage_preview(hymn, cm)) == [7], "Hymn of Dawn counts the party's Aether (4 + 3)")
	cm.aether = 0
	var shadow := _make(cm, "bianca_ash_shadow")
	foe.add_status("oiled", 2, "bianca")
	check(_finals(CardEffects.damage_preview(shadow, cm)) == [6] and _finals(CardEffects.damage_preview(shadow, cm, foe)) == [11], "Shadow Thrust adds +5 against an Oiled target only")
	check(CardEffects.damage_preview(_make(cm, "chiara_fire_cinderward"), cm).is_empty(), "a Block card has no damage preview")


func _test_text() -> void:
	var plain := CardTextFormat.to_bbcode("Deal 6 damage.", false)
	check(CardTextFormat.to_bbcode("Deal 6 damage.", false, [{"base": 6, "final": 6}]) == plain, "an unchanged number keeps the normal text")
	var boosted := CardTextFormat.to_bbcode("Deal 6 damage.", false, [{"base": 6, "final": 9}])
	check(boosted.contains(CardTextFormat.BOOSTED_COLOR.to_html(false)) and boosted.contains("]9[") and not boosted.contains("]6["), "a raised number is swapped in, cyan (%s)" % boosted)
	var reduced := CardTextFormat.to_bbcode("Deal 8 Fire damage to ALL.", false, [{"base": 8, "final": 6}])
	check(reduced.contains(CardTextFormat.REDUCED_COLOR.to_html(false)) and reduced.contains("]6["), "a lowered number is red")
	var shatter := CardTextFormat.to_bbcode("Deal 4, +4 per Chill. Removes the Chill.", false, [{"base": 4, "final": 6}])
	check(shatter.contains("]6[") and shatter.contains("+4"), "only the damage number changes, not the bonus (+4 per Chill)")
	var zero := CardTextFormat.to_bbcode("Apply 4 Chill. Deal 8 Frost damage.", false, [{"base": 8, "final": 12}])
	check(zero.contains("]12[") and zero.contains("]4["), "the Chill count stays; the damage becomes 12")
	check(not boosted.contains(String.chr(CardTextFormat.PREVIEW_MARK)), "no marker character is left in the text")


## The preview against a target equals the hit that playing the card really lands.
func _test_matches_real_hits() -> void:
	var cm := _combat("frost", "tanking")
	var foe: Combatant = cm.get_living_enemies()[0]
	foe.affinity = {"shadow": 25}
	foe.add_status("oiled", 2, "bianca")
	var shadow := _make(cm, "bianca_ash_shadow")
	var expected: int = _finals(CardEffects.damage_preview(shadow, cm, foe))[0]
	cm.play_card(shadow, foe.id)
	check(int(cm.last_hit.get("final", -1)) == expected, "Shadow Thrust lands what it previewed (%d, hit %d)" % [expected, int(cm.last_hit.get("final", -1))])
	cm.get_combatant("bianca").damage_bonus = {"physical": 20}
	var strike_id := ""
	for card in cm.deck.hand + cm.deck.draw_pile:
		if card.owner_character_id == "bianca" and CardEffects.damage_preview(card, cm).size() == 1:
			strike_id = card.definition.id
			break
	if strike_id != "":
		var strike := _make(cm, strike_id)
		var want: int = _finals(CardEffects.damage_preview(strike, cm, foe))[0]
		cm.play_card(strike, foe.id)
		check(int(cm.last_hit.get("final", -1)) == want, "%s lands what it previewed with a weapon bonus (%d)" % [strike_id, want])


## Every damage card's text has a number the preview can swap: none is left unmarked.
func _test_every_card_text() -> void:
	var cm := _combat("arcana", "holy")
	var missing: Array[String] = []
	for card_id: String in DataRegistry.cards:
		for upgraded in [false, true]:
			var card := _make(cm, card_id, upgraded)
			var preview := CardEffects.damage_preview(card, cm)
			if preview.is_empty():
				continue
			var fake: Array = preview.map(func(e: Dictionary) -> Dictionary: return {"base": e["base"], "final": int(e["base"]) + 100})
			var text := CardTextFormat.to_bbcode(card.get_description(), upgraded, fake)
			for e: Dictionary in fake:
				if not text.contains("]%d[" % int(e["final"])):
					missing.append("%s%s" % [card_id, "+" if upgraded else ""])
					break
	check(missing.is_empty(), "every damage card's printed number can be swapped (%s)" % ", ".join(missing))
