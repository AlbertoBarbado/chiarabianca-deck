extends SceneTree
## Bianca's Ashveil specialization: the Oiled status (weaker attacks, more Fire damage taken, capped),
## every Ashveil card, the Slick Tricks passive, the Fire combo with Chiara (cards and Burn ticks),
## and the presentation (card art, cut-ins, effects, the Ashveil pose set). Run:
##   godot --headless --path . --script res://tests/specializations/run_ashveil_tests.gd

const POOL := ["bianca_ash_dagger", "bianca_ash_caltrops", "bianca_ash_shadow", "bianca_ash_smokebomb", "bianca_ash_snare",
	"bianca_ash_powder", "bianca_ash_shadowstep", "bianca_ash_ignite", "bianca_ash_greasefire", "bianca_ash_hexpowder"]
const EPICS := ["bianca_ash_epic_ashfall", "bianca_ash_epic_veil"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_specialization()
	_test_oiled()
	_test_cards()
	_test_passive()
	_test_fire_combo()
	_test_presentation()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(chiara_spec: String = "fire", encounter: String = "castle_training_01", seed_value: int = 5) -> CombatManager:
	var party := Party.from_selection({"chiara": chiara_spec, "bianca": "ashveil"})
	for spec_id in [chiara_spec, "ashveil"]:
		var spec := DataRegistry.get_specialization(spec_id)
		for card_id in spec.card_pool + spec.epic_pool:
			party.get_member(spec.character_id).add_card(card_id)
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter(encounter), Inventory.new(), seed_value)
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


func _oiled(c: Combatant) -> int:
	return int(c.statuses.get("oiled", {}).get("stacks", 0))


func _test_specialization() -> void:
	print("Ashveil")
	var spec := DataRegistry.get_specialization("ashveil")
	check(spec != null and spec.is_playable() and spec.character_id == "bianca" and spec.display_name == "Ashveil", "Ashveil is Bianca's playable specialization")
	check(DataRegistry.get_specialization("duelist") == null and DataRegistry.get_character("bianca").specialization_ids.has("ashveil"), "it replaces the Duelist")
	check(spec.has_passive() and spec.keywords == ["oiled"] and spec.description.contains("Fire"), "passive, Oiled keyword and the Fire combo in its description")
	var party := Party.from_selection({"chiara": "fire", "bianca": "ashveil"})
	var counts := {}
	for owned in party.get_member("bianca").deck:
		counts[owned.card_id] = int(counts.get(owned.card_id, 0)) + 1
	check(counts == {"bianca_ash_slash": 4, "bianca_ash_veil": 3, "bianca_ash_flask": 3}, "starting deck: 4 Ashen Slash, 3 Smoke Veil, 3 Oil Flask")
	check(spec.card_pool.slice(0, POOL.size()) == POOL and spec.card_pool.size() == 19 and spec.epic_pool == EPICS, "19 reward cards (the first 10 with Hexed Powder for Arcana, then the expansion) and 2 epics")
	var all_ok := true
	for card_id: String in spec.starting_deck_card_ids + POOL + EPICS:
		var def := DataRegistry.get_card(card_id)
		all_ok = all_ok and def != null and def.owner_character_id == "bianca" and def.specialization_id == "ashveil" and def.description.length() <= 60
		all_ok = all_ok and not def.upgrade.is_empty()
	check(all_ok, "every Ashveil card is Bianca's, upgradeable, with a short description")


func _test_oiled() -> void:
	print("Oiled")
	var oiled := DataRegistry.get_status("oiled")
	check(oiled != null and oiled.max_stacks == 3 and oiled.damage_dealt_pct == -15 and oiled.vulnerable_elements == ["fire"] and oiled.vulnerable_per_stack == 15, "Oiled: -15% attack damage, +15% Fire taken per stack, max 3")
	var enemy := Combatant.new()
	enemy.side = Combatant.SIDE_ENEMY
	enemy.max_hp = 100
	enemy.hp = 100
	enemy.add_status("oiled", 5, "bianca")
	check(_oiled(enemy) == 3, "stacks are capped at 3 (+45% Fire at most: strong, not broken)")
	check(DamageTypes.apply(20, "fire", null, enemy) == 29 and DamageTypes.apply(20, "physical", null, enemy) == 20, "fully Oiled: 20 Fire becomes 29, Physical stays 20")
	check(DamageTypes.apply(20, "physical", enemy, null) == 17, "an Oiled attacker deals 15% less (20 -> 17)")
	var cm := _combat()
	var target := cm.enemies[0]
	target.add_status("oiled", 2, "bianca")
	cm.end_player_turn()
	check(_oiled(target) == 1, "Oiled drops by 1 each round")


func _test_cards() -> void:
	print("Cards")
	var cm := _combat("fire", "castle_training_02")
	var a := cm.enemies[0]
	var b := cm.enemies[1]
	var hp := a.hp
	check(_play(cm, "bianca_ash_flask", a.id) and _oiled(a) == 2 and a.hp == hp - 3, "Oil Flask: 3 damage and 2 Oiled")
	check(_play(cm, "bianca_ash_caltrops") and _oiled(a) == 3 and _oiled(b) == 1 and a.has_status("bleed") and b.has_status("bleed"), "Caltrops: Oiled and Bleed on everyone")
	# Damage checks on fresh foes (no Bleed adding its own HP loss).
	cm = _combat("fire", "castle_training_02")
	var bianca_c := cm.party_combatants[1]
	b = cm.enemies[1]
	b.add_status("oiled", 1, "bianca")
	hp = b.hp
	check(_play(cm, "bianca_ash_shadow", b.id) and hp - b.hp == mini(hp, DamageTypes.apply(11, "shadow", bianca_c, b)), "Shadow Thrust: Shadow damage, +5 on an Oiled foe")
	cm = _combat("fire", "castle_training_02")
	bianca_c = cm.party_combatants[1]
	a = cm.enemies[0]
	b = cm.enemies[1]
	a.add_status("oiled", 2, "bianca")
	var ha := a.hp
	var hb := b.hp
	check(_play(cm, "bianca_ash_powder"), "Blasting Powder plays")
	check(ha - a.hp == mini(ha, DamageTypes.apply(11, "fire", bianca_c, _ref_oiled(2))) and hb - b.hp == mini(hb, DamageTypes.apply(7, "fire", bianca_c, null)), "Blasting Powder: 7 Fire to all, 11 x1.30 to the Oiled one")
	cm = _combat("fire", "castle_training_01")
	var dummy := cm.enemies[0]
	dummy.add_status("oiled", 3, "bianca")
	hp = dummy.hp
	check(_play(cm, "bianca_ash_ignite", dummy.id), "Ignition Strike plays")
	var expected := mini(hp, DamageTypes.apply(9 + 4 * 3, "fire", cm.party_combatants[1], _ref_oiled(3)))
	check(hp - dummy.hp == expected and not dummy.has_status("oiled"), "Ignition Strike: 9 + 4 per Oiled, ignited (x1.45), then the oil is gone (%d)" % (hp - dummy.hp))
	cm = _combat("fire", "castle_training_02")
	check(_play(cm, "bianca_ash_greasefire") and cm.enemies.all(func(e: Combatant) -> bool: return _oiled(e) == 2 and e.has_status("burn")), "Greasefire Trap: Oiled and Burn on everyone")
	cm = _combat("fire", "castle_training_02")
	hp = cm.enemies[0].hp
	check(_play(cm, "bianca_ash_epic_ashfall") and (not cm.enemies[0].is_alive() or hp - cm.enemies[0].hp == DamageTypes.apply(10, "fire", cm.party_combatants[1], _ref_oiled(3))), "Ashfall oils everyone first, so its Fire lands at x1.45")
	cm = _combat()
	var bianca := cm.party_combatants[1]
	var chiara := cm.party_combatants[0]
	check(_play(cm, "bianca_ash_epic_veil") and chiara.block >= 8 and _oiled(cm.enemies[0]) == 2, "Veil of Ash: party Block, Oiled on all")
	var step := _to_hand(cm, "bianca_ash_shadowstep")
	var before := cm.deck.hand.size()
	var block_before := bianca.block
	var energy_before := cm.energy
	check(cm.play_card(step) and cm.deck.hand.size() == before and bianca.block == block_before + 4 and cm.energy == energy_before, "Shadowstep: 4 Block and a card back, for free")


## A throwaway target carrying n Oiled stacks, for expected damage.
func _ref_oiled(stacks: int) -> Combatant:
	var c := Combatant.new()
	c.side = Combatant.SIDE_ENEMY
	c.max_hp = 999
	c.hp = 999
	c.add_status("oiled", stacks, "bianca")
	return c


func _test_passive() -> void:
	print("Slick Tricks")
	var cm := _combat()
	var bianca := cm.party_combatants[1]
	var enemy := cm.enemies[0]
	bianca.block = 0
	_play(cm, "bianca_ash_dagger", enemy.id)
	check(bianca.block == 3, "the first Oiled of the turn gives Bianca 3 Block")
	_play(cm, "bianca_ash_dagger", enemy.id)
	_play(cm, "bianca_ash_flask", enemy.id)
	check(bianca.block == 3, "only once per turn")


func _test_fire_combo() -> void:
	print("Fire combo with Chiara")
	var cm := _combat("fire")
	var enemy := cm.enemies[0]
	var hp := enemy.hp
	_play(cm, "chiara_fire_ember", enemy.id)
	var plain := hp - enemy.hp
	cm = _combat("fire")
	enemy = cm.enemies[0]
	enemy.add_status("oiled", 3, "bianca")
	hp = enemy.hp
	var events: Array[Dictionary] = []
	cm.visual_event.connect(func(e: Dictionary) -> void: events.append(e))
	_play(cm, "chiara_fire_ember", enemy.id)
	var oiled_hit := hp - enemy.hp
	check(oiled_hit > plain, "Chiara's Ember Bolt hits an Oiled foe harder (%d vs %d)" % [oiled_hit, plain])
	check(events.any(func(e: Dictionary) -> bool: return e.get("kind") == "status_exploit" and e.get("status_id") == "oiled"), "the hit sends a status_exploit event (the oil bursts into flame)")
	cm = _combat("fire")
	enemy = cm.enemies[0]
	enemy.add_status("burn", 1, "chiara")
	enemy.add_status("oiled", 3, "bianca")
	hp = enemy.hp
	cm.end_player_turn()
	check(hp - enemy.hp >= DamageTypes.apply(3, "fire", null, _ref_oiled(3)), "Burn ticks are Fire too: Oiled makes them hurt more")
	var frost_hits: Array[int] = []
	for stacks in [0, 3]:
		cm = _combat("frost")
		enemy = cm.enemies[0]
		if stacks > 0:
			enemy.add_status("oiled", stacks, "bianca")
		hp = enemy.hp
		_play(cm, "chiara_frost_bolt", enemy.id)
		frost_hits.append(hp - enemy.hp)
	check(frost_hits[0] == frost_hits[1], "Frost is not boosted by oil (%s)" % str(frost_hits))


func _test_presentation() -> void:
	print("Presentation")
	var spec := DataRegistry.get_specialization("ashveil")
	var art_ok := true
	for card_id: String in spec.starting_deck_card_ids + POOL + EPICS:
		var def := DataRegistry.get_card(card_id)
		var art := AssetCatalog.card_art_id(card_id, "ashveil", def.card_type)
		art_ok = art_ok and art.begins_with("art_ash_") and AssetCatalog.texture(art) != null
	check(art_ok, "every Ashveil card has its own generated art")
	check(AssetCatalog.texture(spec.icon_id) != null and AssetCatalog.texture("icon_oiled") != null, "the Ashveil emblem and the Oiled icon exist")
	for tier in ["2", "3", "4"]:
		check(CombatPresentation.texture("generated/ashveil/cutin_ash_t" + tier) != null, "cut-in tier %s exists" % tier)
	check(VfxCatalog.match_event({"kind": "apply_status", "status_id": "oiled", "card_id": "bianca_ash_flask", "specialization_id": "ashveil"}) == "oil_splash", "applying Oiled splashes black oil")
	check(VfxCatalog.match_event({"kind": "status_exploit", "status_id": "oiled", "element": "fire"}) == "oil_ignite", "a Fire hit on an Oiled foe bursts into flame")
	check(VfxCatalog.match_event({"kind": "damage", "card_id": "bianca_ash_powder", "specialization_id": "ashveil"}) == "powder_blast", "Blasting Powder explodes")
	check(VfxCatalog.match_event({"kind": "block", "card_id": "bianca_ash_veil", "specialization_id": "ashveil"}) == "smoke_veil", "Ashveil Block wraps the ally in a veil of smoke")
	check(VfxCatalog.match_event({"kind": "block", "card_id": "bianca_ash_smokebomb", "specialization_id": "ashveil", "target_group": "all_allies"}) == "smoke_burst", "a party-wide Ashveil Block is a burst of smoke")
	for vfx_id in ["oil_splash", "oil_ignite", "powder_blast", "smoke_burst", "caltrops"]:
		check(VfxCatalog.sprite_texture(VfxCatalog.effect(vfx_id)) != null, "%s has its sprite" % vfx_id)
	var poses_ok := true
	for state in ["idle", "attack", "cast", "block", "hit", "down"]:
		var own := CombatPresentation.character_state("bianca", state, "ashveil")
		poses_ok = poses_ok and own != null and own != CombatPresentation.character_state("bianca", state)
	check(poses_ok, "Bianca has her own Ashveil pose for every combat state")
	check(CombatPresentation.character_state("bianca", "idle", "holy") == CombatPresentation.character_state("bianca", "idle"), "other specializations keep the paladin look")
