extends SceneTree
## Gear for every slot: item data, specialization-only drops, shop filtering and gear offers, and the
## in-battle item effects (PassiveRunner entries from Equipment.passives). Run:
##   godot --headless --path . --script res://tests/progression/run_gear_tests.gd

const SLOTS := ["helmet", "amulet", "chest", "gauntlets", "weapon", "belt", "ring", "boots"]
const TRIGGERS := ["status_applied", "block_gained", "card_played", "attack_absorbed", "turn_start", "enemy_killed"]
const EFFECTS := ["bonus_damage", "extra_status", "bonus_block", "draw_cards", "taunt_attacker", "create_card",
	"gain_energy", "gain_aether", "party_block", "heal_party", "apply_status_all", "damage_all", "status_to_target"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	Reactions.reload()
	_test_data()
	_test_drops()
	_test_shops()
	_test_effects()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _party(chiara: String, bianca: String) -> Party:
	return Party.from_selection({"chiara": chiara, "bianca": bianca})


func _combat(party: Party, seed_value: int = 5) -> CombatManager:
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter("castle_final_regular_01"), Inventory.new(), seed_value)
	return cm


func _wear(party: Party, member_id: String, item_id: String) -> void:
	var member := party.get_member(member_id)
	var slot: String = Equipment.slots_for(item_id)[0]
	if slot == "ring_1" and str(member.equipment.get("ring_1", "")) != "":
		slot = "ring_2"
	member.equipment[slot] = item_id


func _stacks(c: Combatant, status_id: String) -> int:
	return int(c.statuses.get(status_id, {}).get("stacks", 0))


func _gusts(cm: CombatManager) -> int:
	return cm.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.id == "chiara_wind_gust").size()


func _give(cm: CombatManager, card_id: String) -> CardInstance:
	var def := DataRegistry.get_card(card_id)
	var card := CardInstance.new()
	card.definition = def
	card.owner_character_id = def.owner_character_id
	cm.deck.hand.append(card)
	return card


func _test_data() -> void:
	var items := Equipment.all_items()
	var used: Array = items.map(func(i: Dictionary) -> String: return str(i["slot"]))
	check(SLOTS.all(func(s: String) -> bool: return used.has(s)), "every slot has items")
	var bad: Array[String] = []
	for entry in items:
		var item_id := str(entry["id"])
		for spec_id: Variant in entry.get("specializations", []):
			var spec := DataRegistry.get_specialization(str(spec_id))
			if spec == null or spec.status != "playable":
				bad.append("%s: spec %s" % [item_id, spec_id])
			elif str(entry.get("wielder", "")) != "" and spec.character_id != str(entry["wielder"]):
				bad.append("%s: %s is not %s's" % [item_id, spec_id, entry["wielder"]])
		for effect: Dictionary in entry.get("effects", []):
			if str(effect.get("text", "")) == "" or not TRIGGERS.has(str(effect.get("trigger", {}).get("event", ""))) or not EFFECTS.has(str(effect.get("effect", {}).get("effect", ""))):
				bad.append("%s: effect %s" % [item_id, effect.get("text", "?")])
			var status_id := str(effect.get("effect", {}).get("status_id", ""))
			if status_id != "" and DataRegistry.get_status(status_id) == null:
				bad.append("%s: status %s" % [item_id, status_id])
			var card_id := str(effect.get("effect", {}).get("card_id", ""))
			if card_id != "" and DataRegistry.get_card(card_id) == null:
				bad.append("%s: card %s" % [item_id, card_id])
		var icon := str(entry.get("icon", ""))
		if icon == "" or not ResourceLoader.exists(icon):
			bad.append("%s: icon %s" % [item_id, icon])
	check(bad.is_empty(), "every item names playable specializations, known effects and an existing icon (%s)" % ", ".join(bad))
	for spec_id in ["arcana", "fire", "frost", "wind", "tanking", "holy", "ashveil", "venom"]:
		var own := items.filter(func(i: Dictionary) -> bool: return (i.get("specializations", []) as Array).has(spec_id) and not (i.get("effects", []) as Array).is_empty())
		check(own.size() >= 3, "%s has at least 3 items with effects of its own (%d)" % [spec_id, own.size()])
	var effect_items := items.filter(func(i: Dictionary) -> bool: return not (i.get("effects", []) as Array).is_empty())
	check(effect_items.size() >= 25, "most new gear does more than raise numbers (%d items with effects)" % effect_items.size())


func _test_drops() -> void:
	var party := _party("arcana", "holy")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var weights := {"common": 1.0, "uncommon": 1.0, "rare": 1.0}
	var seen: Dictionary = {}
	var unusable: Array[String] = []
	for i in 600:
		var item_id := Loot.pick(party, rng, weights)
		seen[item_id] = true
		if not Equipment.usable_by_party(party, item_id):
			unusable.append(item_id)
	check(unusable.is_empty(), "Arcana + Holy never gets an item they cannot use (%s)" % ", ".join(unusable))
	check(not seen.has("ember_staff") and not seen.has("plague_mask") and not seen.has("bastion_greathelm"), "no Fire staff, Venom mask or Tanking helm for Arcana + Holy")
	check(seen.has("seers_circlet") and seen.has("sunlit_reliquary") and seen.has("twinbond_ring"), "their own items and shared items do drop")
	var chiara := party.get_member("chiara")
	check(Equipment.can_equip(chiara, "ember_staff").contains("Fire"), "a Fire item explains it needs Fire (%s)" % Equipment.can_equip(chiara, "ember_staff"))
	check(Equipment.can_equip(chiara, "seers_circlet") == "" and Equipment.can_equip(party.get_member("bianca"), "seers_circlet") != "", "Seer's Circlet fits Arcana Chiara only")


func _test_shops() -> void:
	var party := _party("wind", "tanking")
	var shop := DataRegistry.get_shop("beach_dune_bazaar")
	var plain := Merchant.from_definition(shop)
	var filtered := Merchant.from_definition(shop, party, null)
	var ids: Array = filtered.stock.map(func(e: Dictionary) -> String: return str(e["item_id"]))
	check(plain.stock.any(func(e: Dictionary) -> bool: return e["item_id"] == "coralsteel_sabre") and not ids.has("coralsteel_sabre"), "a Holy sabre is not sold to a Tanking Bianca")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var offered := Merchant.from_definition(shop, party, rng)
	var extra: Array = offered.stock.slice(filtered.stock.size()).map(func(e: Dictionary) -> String: return str(e["item_id"]))
	check(extra.size() == 1 and extra.all(func(i: String) -> bool: return Equipment.usable_by_party(party, i)) , "the shop adds 1 gear offer the party can use (%s)" % ", ".join(extra))
	var again := RandomNumberGenerator.new()
	again.seed = 9
	var same: Array = Merchant.from_definition(shop, party, again).stock.map(func(e: Dictionary) -> String: return str(e["item_id"]))
	check(same == offered.stock.map(func(e: Dictionary) -> String: return str(e["item_id"])), "the same visit seed shows the same offers")


func _test_effects() -> void:
	# Seer's Circlet: +2 cards on turn 1 only (limit_per_combat), and the draw makes Aether.
	var party := _party("arcana", "holy")
	_wear(party, "chiara", "seers_circlet")
	var cm := _combat(party)
	cm.start()
	check(cm.deck.hand.size() == CombatManager.HAND_SIZE + 2 and cm.aether >= 2, "Seer's Circlet: 7 cards and Aether on turn 1 (%d cards, %d Aether)" % [cm.deck.hand.size(), cm.aether])
	check(cm.passives.has_passive("chiara") and cm.passives.is_ready("chiara"), "Chiara's own passive still reads as hers")
	cm.end_player_turn()
	check(cm.turn == 2 and cm.deck.hand.size() == CombatManager.HAND_SIZE, "no extra cards on turn 2")

	# Ember Crown and Plague Mask: debuffs on every enemy at the start; the mask's Poison immunity.
	party = _party("fire", "venom")
	_wear(party, "chiara", "ember_crown")
	_wear(party, "bianca", "plague_mask")
	cm = _combat(party)
	cm.start()
	var foes := cm.get_living_enemies()
	check(foes.all(func(e: Combatant) -> bool: return _stacks(e, "burn") >= 2 and _stacks(e, "poison") >= 3), "Ember Crown + Plague Mask: every enemy starts Burning and Poisoned")
	check(cm.get_combatant("bianca").immunities.has("poison"), "the Plague Mask makes Bianca immune to Poison")

	# Catalyst Locket: Bianca's first Poison each turn also brands 2 Blight.
	party = _party("fire", "venom")
	_wear(party, "bianca", "catalyst_locket")
	cm = _combat(party)
	cm.start()
	cm.energy = 20
	var foe: Combatant = cm.get_living_enemies()[0]
	cm.play_card(_give(cm, "bianca_venom_envenom"), foe.id)
	check(_stacks(foe, "blight") == 2, "Catalyst Locket: Poison also applies 2 Blight (%d)" % _stacks(foe, "blight"))
	cm.play_card(_give(cm, "bianca_venom_envenom"), foe.id)
	check(_stacks(foe, "blight") == 2, "only once per turn")

	# Venomfang Ring: Bianca fells an enemy -> 2 Poison on every other enemy.
	party = _party("fire", "venom")
	_wear(party, "bianca", "venomfang_ring")
	cm = _combat(party)
	cm.start()
	foes = cm.get_living_enemies()
	if foes.size() >= 2:
		foes[0].hp = 1
		foes[0].block = 0
		var before := _stacks(foes[1], "poison")
		cm.hit(foes[0], 5, DamageTypes.PHYSICAL, cm.get_combatant("bianca"))
		check(not foes[0].is_alive() and _stacks(foes[1], "poison") == before + 2, "Venomfang Ring: a kill spreads 2 Poison to the rest")
	# A Poison tick kill counts as Bianca's.
	cm.end_player_turn()  # let the enemy phase run once
	party = _party("fire", "venom")
	_wear(party, "bianca", "venomfang_ring")
	cm = _combat(party)
	cm.start()
	foes = cm.get_living_enemies()
	if foes.size() >= 2:
		foes[0].hp = 2
		foes[0].add_status("poison", 5, "bianca")
		var poison_before := _stacks(foes[1], "poison")
		cm.end_player_turn()
		check(not foes[0].is_alive() and _stacks(foes[1], "poison") >= poison_before + 1, "a Poison kill counts as Bianca's kill too")

	# Hourglass Amulet: +1 Energy on turn 3.
	party = _party("arcana", "tanking")
	_wear(party, "bianca", "hourglass_amulet")
	cm = _combat(party)
	cm.start()
	for enemy in cm.enemies:
		enemy.max_hp = 999
		enemy.hp = 999
	for c in cm.party_combatants:
		c.max_hp = 999
		c.hp = 999
	cm.end_player_turn()
	var energy_turn_2 := cm.energy
	cm.end_player_turn()
	check(cm.turn == 3 and cm.energy == energy_turn_2 + 1, "Hourglass Amulet: +1 Energy on the 3rd turn (%d vs %d)" % [cm.energy, energy_turn_2])

	# Bastion Greathelm and Windstep Boots: opening Block and Gusts.
	party = _party("wind", "tanking")
	_wear(party, "bianca", "bastion_greathelm")
	_wear(party, "chiara", "windstep_boots")
	cm = _combat(party)
	cm.start()
	check(cm.get_combatant("bianca").block >= 10, "Bastion Greathelm: Bianca opens with 10 Block")
	check(_gusts(cm) == 2, "Windstep Boots: 2 Gusts in the opening hand")

	# Storm Grips: the 5th card of the turn gives 1 Energy.
	party = _party("wind", "tanking")
	_wear(party, "chiara", "storm_grips")
	cm = _combat(party)
	cm.start()
	cm.energy = 10
	for i in 4:
		cm.play_card(_give(cm, "chiara_wind_gust"), cm.get_living_enemies()[0].id)
	var energy_before := cm.energy
	cm.play_card(_give(cm, "chiara_wind_gust"), cm.get_living_enemies()[0].id)
	check(cm.energy == energy_before + 1, "Storm Grips: the 5th card refunds 1 Energy")

	# Twinbond Ring: a card right after the other sister's draws 1.
	party = _party("arcana", "tanking")
	_wear(party, "bianca", "twinbond_ring")
	cm = _combat(party)
	cm.start()
	cm.energy = 10
	var target_id := cm.get_living_enemies()[0].id
	var bolt := _give(cm, "chiara_arcana_bolt")
	cm.play_card(bolt, target_id)
	var strike := _give(cm, "bianca_tanking_strike")
	var hand_before := cm.deck.hand.size()
	cm.play_card(strike, target_id)
	check(cm.deck.hand.size() == hand_before, "Twinbond Ring: Bianca's card after Chiara's draws 1 (hand %d -> %d)" % [hand_before, cm.deck.hand.size()])
