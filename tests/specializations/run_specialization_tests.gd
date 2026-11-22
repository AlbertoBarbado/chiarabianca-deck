extends SceneTree
## Milestone 3 logic tests: Chiara Fire, Bianca Holy, Burn, passives. Run:
##   godot --headless --path . --script res://tests/specializations/run_specialization_tests.gd

var FIRE_POOL: Array = DataRegistry.get_specialization("fire").card_pool if DataRegistry.get_specialization("fire") != null else []
var HOLY_POOL: Array = DataRegistry.get_specialization("holy").card_pool if DataRegistry.get_specialization("holy") != null else []

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	_test_selection_and_decks()
	_test_reward_pools()
	_test_burn()
	_test_fire_passive()
	_test_fire_cards()
	_test_holy_passive()
	_test_holy_cards()
	_test_fallen()
	_test_cleanup()
	_test_upgrades()
	_test_save_load()
	_test_existing_specializations_unchanged()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


# --- Helpers -----------------------------------------------------------------

## Builds a combat. Every reward-pool card of the chosen specializations is added to the owners'
## decks so tests can pull any card into the hand.
func _combat(chiara_spec: String, bianca_spec: String, encounter: String = "castle_training_01", seed_value: int = 4) -> CombatManager:
	var party := Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})
	for spec_id in [chiara_spec, bianca_spec]:
		var spec := DataRegistry.get_specialization(spec_id)
		for card_id in spec.card_pool:
			party.get_member(spec.character_id).add_card(card_id)
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter(encounter), Inventory.new(), seed_value)
	cm.start()
	cm.energy = 20  # Tests focus on effects, not on the energy budget.
	return cm


## Moves a card of the given id into the hand (from any pile) and returns it.
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


# --- Selection, decks, ownership ---------------------------------------------

func _test_selection_and_decks() -> void:
	print("Selection and starting decks")
	var fire := DataRegistry.get_specialization("fire")
	var holy := DataRegistry.get_specialization("holy")
	check(fire.is_playable() and holy.is_playable(), "Fire and Holy are playable")
	check(fire.character_id == "chiara" and holy.character_id == "bianca", "owners are Chiara and Bianca")
	check(fire.display_name == "Fire" and holy.display_name == "Holy" and fire.description != "" and holy.description != "", "names and descriptions defined")
	check(fire.has_passive() and holy.has_passive(), "both define a passive")
	check(DataRegistry.counts()["specializations"] == 12 and DataRegistry.counts()["cards"] == 198, "12 specializations and 198 cards loaded (with Wind, Venom, Aether, cross-combo, expansion and 4 fusion cards)")
	check(DataRegistry.get_specialization("duelist") == null and DataRegistry.get_character("bianca").specialization_ids.has("ashveil"), "Ashveil replaces the Duelist")
	for other in ["earth", "lightning", "retribution", "commander"]:
		check(not DataRegistry.get_specialization(other).is_playable(), "%s still not playable" % other)

	for combo: Array in [["fire", "tanking"], ["arcana", "holy"], ["fire", "holy"]]:
		var party := Party.from_selection({"chiara": combo[0], "bianca": combo[1]})
		var chiara := party.get_member("chiara")
		var bianca := party.get_member("bianca")
		check(chiara != null and bianca != null and chiara.specialization.id == combo[0] and bianca.specialization.id == combo[1], "%s + %s party builds" % combo)
		check(chiara.deck.size() == 10 and bianca.deck.size() == 10, "%s + %s: 10 cards each" % combo)
		check(chiara.deck.all(func(o: OwnedCard) -> bool: return o.owner_character_id == "chiara" and DataRegistry.get_card(o.card_id).owner_character_id == "chiara"), "%s + %s: Chiara's cards owned by Chiara" % combo)
		check(bianca.deck.all(func(o: OwnedCard) -> bool: return o.owner_character_id == "bianca" and DataRegistry.get_card(o.card_id).owner_character_id == "bianca"), "%s + %s: Bianca's cards owned by Bianca" % combo)
	var fire_party := Party.from_selection({"chiara": "fire", "bianca": "holy"})
	var counts := {}
	for owned in fire_party.get_member("chiara").deck:
		counts[owned.card_id] = int(counts.get(owned.card_id, 0)) + 1
	check(counts == {"chiara_fire_ember": 4, "chiara_fire_cinderward": 3, "chiara_fire_kindle": 3}, "Fire starting deck: 4 Ember Bolt, 3 Cinder Ward, 3 Kindle")
	counts.clear()
	for owned in fire_party.get_member("bianca").deck:
		counts[owned.card_id] = int(counts.get(owned.card_id, 0)) + 1
	check(counts == {"bianca_holy_strike": 4, "bianca_holy_hymn": 1, "bianca_holy_shield": 3, "bianca_holy_touch": 2}, "Holy starting deck: 4 Radiant Strike, 1 Hymn of Dawn, 3 Blessed Shield, 2 Soothing Touch")
	var deck := PartyDeck.new()
	deck.build_from_party(fire_party)
	var ids := {}
	for card in deck.draw_pile:
		ids[card.instance_id] = true
	check(deck.draw_pile.size() == 20 and ids.size() == 20, "shared 20-card deck with unique instance ids")
	check(deck.draw_pile.all(func(c: CardInstance) -> bool: return c.owner_character_id == c.definition.owner_character_id), "every instance keeps its owner")
	var uids := {}
	for member in fire_party.members:
		for owned in member.deck:
			uids[owned.uid] = true
	check(uids.size() == 20, "owned-card uids unique across the party")
	for card_id in FIRE_POOL + HOLY_POOL:
		var def := DataRegistry.get_card(card_id)
		check(def != null and def.description != "", "%s defined with a description" % card_id)


# --- Rewards -------------------------------------------------------------------

func _test_reward_pools() -> void:
	print("Reward pools")
	var party := Party.from_selection({"chiara": "fire", "bianca": "holy"})
	var rng := RandomNumberGenerator.new()
	var ok := true
	var seen := {}
	for seed_value in 400:
		rng.seed = seed_value
		var reward := CardReward.generate(party, rng)
		var ids: Array[String] = []
		ok = ok and reward.options.size() == 3
		for option in reward.options:
			var card_id := str(option["card_id"])
			var owner_id := str(option["owner_character_id"])
			var allowed: Array = FIRE_POOL if owner_id == "chiara" else HOLY_POOL
			ok = ok and allowed.has(card_id) and DataRegistry.get_card(card_id).owner_character_id == owner_id and not ids.has(card_id)
			ids.append(card_id)
			seen[card_id] = true
	check(ok, "400 seeds: options come only from the Fire/Holy pools with the right owner, no duplicates")
	check(seen.size() == FIRE_POOL.size() + HOLY_POOL.size(), "every pool card can be offered")
	var arcana_party := Party.from_selection({"chiara": "arcana", "bianca": "tanking"})
	var leak := false
	for seed_value in 40:
		rng.seed = seed_value
		for option in CardReward.generate(arcana_party, rng).options:
			leak = leak or FIRE_POOL.has(option["card_id"]) or HOLY_POOL.has(option["card_id"])
	check(not leak, "Arcana/Tanking parties never see Fire/Holy cards")

	rng.seed = 7
	var reward := CardReward.generate(party, rng)
	var option: Dictionary = reward.options[0]
	var owner := party.get_member(option["owner_character_id"])
	var other := party.get_member("bianca" if owner.id == "chiara" else "chiara")
	var added := reward.choose(0, party)
	check(added != null and owner.deck.size() == 11 and other.deck.size() == 10 and added.owner_character_id == owner.id, "taking a reward adds it to the owner's deck only")
	var twin := owner.add_card(added.card_id)
	check(twin.uid != added.uid, "duplicate reward copies get unique uids")
	var deck := PartyDeck.new()
	deck.build_from_party(party)
	var ids := {}
	for card in deck.draw_pile:
		ids[card.instance_id] = true
	check(deck.draw_pile.size() == 22 and ids.size() == 22, "next combat deck includes the reward with unique instance ids")


# --- Burn ------------------------------------------------------------------------

func _test_burn() -> void:
	print("Burn")
	var burn := DataRegistry.get_status("burn")
	check(burn != null and burn.tick_damage == 3 and burn.max_stacks == 4 and burn.tick_timing == StatusDef.TICK_ENEMY_PHASE_START and burn.tick_ignores_block, "Burn defined in data: 3 damage at enemy phase start, ignores Block, at most 4 turns")

	var cm := _combat("fire", "tanking")
	var enemy := cm.enemies[0]
	check(_play(cm, "chiara_fire_kindle"), "Kindle can be played")
	check(enemy.statuses["burn"]["stacks"] == 2 and enemy.get_status_source("burn") == "chiara", "Burn 2 applied by Chiara")
	check(enemy.hp == 26 - 2, "no tick during the player's turn (only the passive's 2)")
	enemy.block = 10
	cm.end_player_turn()
	check(enemy.hp == 26 - 2 - 3, "tick at enemy phase start deals 3 and ignores Block")
	check(enemy.statuses["burn"]["stacks"] == 1, "duration drops by one at the end of the round")
	cm.end_player_turn()
	check(enemy.hp == 26 - 2 - 6 and not enemy.has_status("burn"), "Burn 2 = exactly 2 ticks, then it expires")
	cm.end_player_turn()
	check(enemy.hp == 26 - 2 - 6, "no further damage after expiry")

	var stack := _combat("fire", "tanking", "castle_training_01", 5)
	_play(stack, "chiara_fire_kindle")
	check(stack.enemies[0].statuses["burn"]["stacks"] == 2, "one Kindle: Burn 2")
	_play(stack, "chiara_fire_kindle")
	check(stack.enemies[0].statuses["burn"]["stacks"] == 4, "Burn stacks add duration")
	_play(stack, "chiara_fire_kindle")
	check(stack.enemies[0].statuses["burn"]["stacks"] == 4, "Burn never exceeds 4 turns (short and hot)")

	var wave := _combat("fire", "tanking", "castle_training_02", 6)
	_play(wave, "chiara_fire_kindle", wave.enemies[0].id)
	check(wave.enemies[0].has_status("burn") and not wave.enemies[1].has_status("burn"), "single-target Burn only affects the chosen enemy")
	wave.end_player_turn()
	check(wave.enemies[0].hp == 16 - 2 - 3 and wave.enemies[1].hp == 16, "only the burning enemy takes tick damage")

	var taunt := _combat("fire", "tanking", "castle_training_01", 8)
	_play(taunt, "chiara_fire_kindle")
	_play(taunt, "bianca_tanking_challenge", taunt.enemies[0].id)
	check(taunt.get_intent_target(taunt.enemies[0]).id == "bianca", "Taunt still redirects while the enemy burns")
	var bianca := taunt.get_combatant("bianca")
	var before := bianca.hp + bianca.block
	taunt.end_player_turn()
	check(taunt.enemies[0].statuses["burn"]["stacks"] == 1 and bianca.hp + bianca.block <= before, "Taunt and Burn tick on the same schedule")


# --- Fire passive ----------------------------------------------------------------

func _test_fire_passive() -> void:
	print("Fire passive: Kindled Spark")
	var cm := _combat("fire", "tanking")
	var enemy := cm.enemies[0]
	var count := _counter(cm)
	check(cm.passives.is_ready("chiara"), "passive ready at the start of a turn")
	_play(cm, "chiara_fire_kindle")
	check(enemy.hp == 24 and count[0] == 1, "first Burn application: 2 bonus damage, one trigger")
	check(not cm.passives.is_ready("chiara"), "passive is spent for this turn")
	_play(cm, "chiara_fire_kindle")
	_play(cm, "chiara_fire_immolate")
	check(enemy.hp == 24 - 3 and count[0] == 1, "later Burn applications this turn do not trigger it (only Immolate's own 3 damage)")
	cm.end_player_turn()
	check(cm.passives.is_ready("chiara"), "passive resets on the next player turn")
	var hp_before := enemy.hp
	_play(cm, "chiara_fire_kindle")
	check(count[0] == 2 and enemy.hp == hp_before - 2, "triggers again next turn (once)")

	var other := _combat("fire", "tanking", "castle_training_01", 9)
	var other_count := _counter(other)
	_play(other, "chiara_fire_ember")
	_play(other, "chiara_fire_cinderward")
	_play(other, "bianca_tanking_challenge", other.enemies[0].id)
	check(other_count[0] == 0, "damage, Block and Taunt never trigger it")

	var ally := _combat("fire", "tanking", "castle_training_01", 10)
	var ally_count := _counter(ally)
	ally.passives.on_event({"type": "status_applied", "source": ally.get_combatant("bianca"), "target": ally.enemies[0], "status_id": "burn"})
	check(ally_count[0] == 0, "Burn applied by someone else does not trigger Chiara's passive")

	var arc := _combat("arcana", "tanking", "castle_training_01", 11)
	var arc_count := _counter(arc)
	arc.passives.on_event({"type": "status_applied", "source": arc.get_combatant("chiara"), "target": arc.enemies[0], "status_id": "burn"})
	check(arc_count[0] == 0, "Arcana passive ignores Burn events")

	var wave := _combat("fire", "tanking", "castle_training_02", 12)
	var wave_count := _counter(wave)
	var burn_effect := {"effect": "apply_status", "value": 2, "target": "all_enemies", "status_id": "burn"}
	var card := _to_hand(wave, "chiara_fire_kindle")
	CardEffects.resolve(burn_effect, EffectContext.new(wave, wave.get_combatant("chiara"), card, ""))
	check(wave_count[0] == 1 and wave.enemies[0].hp + wave.enemies[1].hp == 16 + 16 - 2, "Burn on several enemies at once triggers once, on the first target")


func _test_fire_cards() -> void:
	print("Fire cards")
	var cm := _combat("fire", "tanking")
	var enemy := cm.enemies[0]
	check(_play(cm, "chiara_fire_fuel"), "Fuel the Flames playable")
	check(enemy.hp == 26 - 5, "Fuel the Flames: 5 damage against a target without Burn")
	enemy.hp = 26
	enemy.add_status("burn", 2, "chiara")
	_play(cm, "chiara_fire_fuel")
	check(enemy.hp == 26 - 9, "Fuel the Flames: 5 + 4 against a Burning target")
	var big := _combat("fire", "tanking", "castle_training_01", 13)
	_play(big, "chiara_fire_inferno")
	check(big.enemies[0].hp == 26 - 18 - 2 and big.enemies[0].statuses["burn"]["stacks"] == 3, "Inferno: 18 damage, 3 Burn, passive 2")
	check(DataRegistry.get_card("chiara_fire_inferno").cost == 3, "Inferno costs 3")
	var aoe := _combat("fire", "tanking", "castle_training_02", 14)
	_play(aoe, "chiara_fire_wave")
	check(aoe.enemies.all(func(e: Combatant) -> bool: return e.hp == 12), "Flame Wave hits every enemy for 4")
	var util := _combat("fire", "tanking", "castle_training_01", 15)
	var chiara := util.get_combatant("chiara")
	var smoke := _to_hand(util, "chiara_fire_smokescreen")
	var hand_before := util.deck.hand.size()
	util.play_card(smoke)
	check(chiara.block == 7 and util.deck.hand.size() == hand_before, "Smoke Screen: 7 Block, and the card it draws replaces itself in hand")
	var fireball := _combat("fire", "tanking", "castle_training_01", 16)
	_play(fireball, "chiara_fire_fireball")
	check(fireball.enemies[0].hp == 16 and not fireball.enemies[0].has_status("burn"), "Fireball: 10 direct damage, no Burn")


# --- Holy passive ----------------------------------------------------------------

func _test_holy_passive() -> void:
	print("Holy passive: Blessed Aegis")
	var cm := _combat("fire", "holy")
	var bianca := cm.get_combatant("bianca")
	var count := _counter(cm)
	_play(cm, "bianca_holy_shield")
	check(bianca.block == 5 and count[0] == 1, "first card Block: 4 + 1 extra")
	_play(cm, "bianca_holy_shield")
	check(bianca.block == 9 and count[0] == 1, "second Block card this turn gets no bonus, and the bonus never re-triggers itself")
	cm.end_player_turn()
	check(bianca.block == 0, "Block resets at the start of each player turn")
	check(_play(cm, "bianca_holy_shield") and bianca.block == 5 and count[0] == 2, "triggers again on the next player turn")

	var benediction := _combat("fire", "holy", "castle_training_01", 21)
	var chiara := benediction.get_combatant("chiara")
	_play(benediction, "bianca_holy_benediction")
	check(benediction.get_combatant("bianca").block == 5 and chiara.block == 4, "party Block: Bianca gets +1 once, Chiara gets none")

	var ward := _combat("fire", "holy", "castle_training_01", 22)
	var ward_count := _counter(ward)
	_play(ward, "chiara_fire_cinderward")
	check(ward.get_combatant("bianca").block == 0 and ward_count[0] == 0, "Block Chiara gains for herself does not trigger Bianca's passive")
	var bianca2 := ward.get_combatant("bianca")
	ward.passives.on_event({"type": "block_gained", "source": ward.get_combatant("chiara"), "target": bianca2, "amount": 4, "origin": "card"})
	check(bianca2.block == 1 and ward_count[0] == 1, "Block an ally's card gives Bianca triggers it")
	ward.passives.reset_turn()
	ward.passives.on_event({"type": "block_gained", "source": bianca2, "target": bianca2, "amount": 2, "origin": "passive"})
	check(ward_count[0] == 1, "Block from non-card origins never triggers it")

	var tank := _combat("arcana", "tanking", "castle_training_01", 23)
	var tank_count := _counter(tank)
	_play(tank, "bianca_tanking_guard")
	check(tank.get_combatant("bianca").block == int(DataRegistry.get_card("bianca_tanking_guard").effects[0]["value"]), "Tanking Guard still gives plain Block")
	check(tank_count[0] == 0 and tank.passives.has_passive("bianca"), "Playing Block does not trigger Bulwark Stance (it reacts to enemy attacks)")


func _test_holy_cards() -> void:
	print("Holy cards")
	var cm := _combat("fire", "holy")
	var chiara := cm.get_combatant("chiara")
	var bianca := cm.get_combatant("bianca")
	chiara.hp = 30
	_play(cm, "bianca_holy_touch", "chiara")
	check(chiara.hp == 33 and chiara.block == 2, "Soothing Touch heals 3 and gives 2 Block")
	_play(cm, "bianca_holy_mending", "chiara")
	check(chiara.hp == 43 and cm.deck.exhaust_pile.any(func(c: CardInstance) -> bool: return c.definition.id == "bianca_holy_mending"), "Mending Light heals 10, then exhausts (once per fight)")
	chiara.hp = 59
	_play(cm, "bianca_holy_touch", "chiara")
	check(chiara.hp == chiara.max_hp, "healing never exceeds max HP")

	var bulwark := _combat("fire", "holy", "castle_training_01", 31)
	_play(bulwark, "bianca_holy_shield")
	_play(bulwark, "bianca_holy_bulwark")
	check(bulwark.enemies[0].hp == 26 - (3 + 3), "Radiant Bulwark: 3 + 75% of Block (5 incl. passive bonus -> 3)")
	check(bulwark.get_combatant("bianca").block == 5, "Radiant Bulwark does not consume Block")
	var none := _combat("fire", "holy", "castle_training_01", 32)
	_play(none, "bianca_holy_bulwark")
	check(none.enemies[0].hp == 26 - 3, "Radiant Bulwark with no Block deals only its base damage")
	var smite := _combat("fire", "holy", "castle_training_01", 33)
	_play(smite, "bianca_holy_smite")
	check(smite.enemies[0].hp == 26 - 7, "Smite deals 7")

	var judgment := _combat("fire", "holy", "castle_training_01", 34)
	judgment.get_combatant("chiara").hp = 20
	judgment.get_combatant("bianca").hp = 70
	check(judgment.can_play(_to_hand(judgment, "bianca_holy_judgment")) == "", "Divine Judgment (3 Energy) playable")
	_play(judgment, "bianca_holy_judgment")
	check(judgment.enemies[0].hp == 26 - 16 and judgment.get_combatant("chiara").hp == 23 and judgment.get_combatant("bianca").hp == 73, "Divine Judgment: 16 damage and heals the party for 3")
	var shield_t := _combat("fire", "holy", "castle_training_01", 35)
	_play(shield_t, "bianca_holy_ward")
	check(shield_t.get_combatant("bianca").block == 8, "Sanctified Ward: 7 + 1 passive")
	# Block absorbs enemy damage before HP, and Taunt still redirects.
	var tauntcheck := _combat("fire", "holy", "castle_training_01", 36)
	tauntcheck.enemies[0].add_status("taunt", 1, "bianca")
	check(tauntcheck.enemies[0].intent.type == EnemyIntent.TYPE_ATTACK and tauntcheck.get_intent_target(tauntcheck.enemies[0]).id == "bianca", "a taunted enemy still targets the taunter in a Holy party")
	var absorb := Combatant.new()
	absorb.hp = 20
	absorb.max_hp = 20
	absorb.add_block(7)
	check(absorb.take_damage(5) == 0 and absorb.block == 2 and absorb.take_damage(5) == 3, "Block absorbs damage before HP")
	check(bianca.hp > 0, "fixture sanity")


# --- Fallen characters -------------------------------------------------------------

func _test_fallen() -> void:
	print("Fallen characters")
	var cm := _combat("fire", "holy")
	var chiara := cm.get_combatant("chiara")
	cm.enemies[0].add_status("burn", 3, "chiara")
	var kindle := _to_hand(cm, "chiara_fire_kindle")
	chiara.hp = 0
	check(cm.can_play(kindle) != "", "a fallen Chiara cannot play Fire cards")
	var count := _counter(cm)
	cm.passives.on_event({"type": "status_applied", "source": chiara, "target": cm.enemies[0], "status_id": "burn"})
	check(count[0] == 0 and not cm.passives.is_ready("chiara"), "a fallen owner's passive never triggers")
	var hp := cm.enemies[0].hp
	cm.end_player_turn()
	check(cm.enemies[0].hp == hp - 3, "Burn she applied keeps ticking after she falls")

	var holy := _combat("fire", "holy", "castle_training_01", 41)
	var bianca := holy.get_combatant("bianca")
	var shield := _to_hand(holy, "bianca_holy_shield")
	bianca.hp = 0
	check(holy.can_play(shield) != "", "a fallen Bianca cannot play Holy cards")
	var holy_count := _counter(holy)
	holy.passives.on_event({"type": "block_gained", "source": bianca, "target": bianca, "amount": 5, "origin": "card"})
	check(holy_count[0] == 0 and bianca.block == 0, "a fallen Bianca's passive never triggers")
	check(bianca.heal(10) == 0 and bianca.hp == 0, "healing does not revive the fallen")
	var touch := _to_hand(holy, "bianca_holy_touch")
	check(touch != null and holy.can_play(touch) != "", "Holy cards of a fallen owner are unplayable")
	var skip := _combat("fire", "holy", "castle_training_01", 42)
	skip.get_combatant("bianca").hp = 0
	_play(skip, "chiara_fire_smokescreen")
	check(skip.get_combatant("bianca").hp == 0 and skip.get_combatant("bianca").block == 0, "Block and heals skip the fallen")


# --- Cleanup ----------------------------------------------------------------------

func _test_cleanup() -> void:
	print("Cleanup")
	var cm := _combat("fire", "holy")
	var enemy := cm.enemies[0]
	var shielded := _combat("fire", "holy", "castle_training_01", 50)
	shielded.enemies[0].block = 3
	_play(shielded, "chiara_fire_kindle")
	check(shielded.enemies[0].hp == 26 and shielded.enemies[0].block == 1, "the passive's bonus damage is absorbed by Block like any damage")
	enemy.hp = 2
	var ended: Array[String] = []
	cm.ended.connect(func(result: String) -> void: ended.append(result))
	_play(cm, "chiara_fire_kindle")  # Passive kills the 2-HP enemy.
	check(not enemy.is_alive() and enemy.statuses.is_empty() and enemy.block == 0, "enemy killed by the passive loses its statuses")
	check(ended == [CombatManager.RESULT_VICTORY] and cm.state == CombatManager.State.VICTORY, "victory fires once")
	check(cm.party_combatants.all(func(c: Combatant) -> bool: return c.statuses.is_empty() and c.block == 0), "no effect outlives the combat")

	var tick := _combat("fire", "holy", "castle_training_02", 51)
	tick.enemies[0].hp = 3
	_play(tick, "chiara_fire_kindle", tick.enemies[0].id)  # 3 - 2 (passive) = 1 HP
	tick.end_player_turn()
	check(not tick.enemies[0].is_alive() and tick.enemies[0].statuses.is_empty() and tick.enemies[0].intent == null, "enemy killed by Burn is cleaned up and never acts")
	check(tick.state == CombatManager.State.PLAYER_TURN and tick.enemies[1].is_alive(), "combat continues while an enemy remains")
	tick.enemies[1].hp = 1
	tick.enemies[1].add_status("burn", 2, "chiara")
	tick.end_player_turn()
	check(tick.state == CombatManager.State.VICTORY and tick.enemies[1].statuses.is_empty(), "last enemy dying to a Burn tick ends the combat in victory")

	var lose := _combat("fire", "holy", "castle_training_01", 52)
	lose.get_combatant("chiara").hp = 1
	lose.get_combatant("bianca").hp = 1
	lose.get_combatant("chiara").add_status("burn", 3, "chiara")
	var lost_result: Array[String] = []
	lose.ended.connect(func(result: String) -> void: lost_result.append(result))
	lose.end_player_turn()
	check(lost_result == [CombatManager.RESULT_DEFEAT] and lose.state == CombatManager.State.DEFEAT, "defeat is reported (Burn on a party member can kill)")
	check(lose.party_combatants.all(func(c: Combatant) -> bool: return c.statuses.is_empty()), "defeat clears all statuses")
	var party := lose.party
	check(party.get_member("chiara").current_hp == 0, "fallen HP committed to the party")


# --- Upgrades ---------------------------------------------------------------------

func _test_upgrades() -> void:
	print("Upgrades")
	var all_ids: Array[String] = ["chiara_fire_ember", "chiara_fire_cinderward", "chiara_fire_kindle", "bianca_holy_strike", "bianca_holy_shield", "bianca_holy_touch"]
	for pool_id: String in FIRE_POOL + HOLY_POOL:
		all_ids.append(pool_id)
	var good := true
	for card_id in all_ids:
		var def := DataRegistry.get_card(card_id)
		good = good and CardUpgrader.get_max_level(def) == 1 and not def.upgrade.get("effects", []).is_empty() and def.upgrade.has("description") and def.upgrade.has("name")
	check(good, "all 18 new cards define upgrades in data (max_level 1)")

	var party := Party.from_selection({"chiara": "fire", "bianca": "holy"})
	var chiara := party.get_member("chiara")
	var kindles := chiara.deck.filter(func(o: OwnedCard) -> bool: return o.card_id == "chiara_fire_kindle")
	var raw_before := JSON.stringify(DataRegistry.get_card("chiara_fire_kindle").raw)
	check(CardUpgrader.upgrade(chiara, kindles[0].uid) == "", "upgrade a Kindle")
	check(kindles[0].upgrade_level == 1 and kindles[1].upgrade_level == 0 and kindles[2].upgrade_level == 0, "only the selected copy is upgraded")
	check(CardUpgrader.upgrade(chiara, kindles[0].uid) != "", "max_level respected")
	check(JSON.stringify(DataRegistry.get_card("chiara_fire_kindle").raw) == raw_before, "definition untouched")
	var bianca := party.get_member("bianca")
	var bulwark := bianca.add_card("bianca_holy_bulwark")
	CardUpgrader.upgrade(bianca, bulwark.uid)

	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new(), 60)
	cm.start()
	cm.energy = 20
	var upgraded: CardInstance = null
	for pile: Array[CardInstance] in [cm.deck.hand, cm.deck.draw_pile]:
		for card in pile:
			if card.owned_uid == kindles[0].uid:
				upgraded = card
	cm.deck.draw_pile.erase(upgraded)
	cm.deck.hand.erase(upgraded)
	cm.deck.hand.append(upgraded)
	check(upgraded.is_upgraded() and upgraded.get_card_name() == "Kindle+", "upgrade reaches the combat instance")
	cm.play_card(upgraded)
	check(cm.enemies[0].statuses["burn"]["stacks"] == 3, "Kindle+ applies 3 Burn")
	var plain: CardInstance = _to_hand(cm, "chiara_fire_kindle")
	check(plain.get_effects()[0]["value"] == 2, "non-upgraded Kindle still applies 2")
	var bw := _find_instance(cm, bulwark.uid)
	cm.get_combatant("bianca").block = 6
	cm.play_card(bw)
	check(cm.enemies[0].hp == 26 - 2 - (5 + 6), "Radiant Bulwark+ uses its upgraded base damage")

	var path := "user://test_spec_save.json"
	var inventory := Inventory.new()
	var progress := MapProgress.new(MapGraph.from_dict(DataRegistry.get_map("royal_castle_tutorial")))
	check(SaveManager.write_file(path, SaveManager.serialize(party, inventory, progress)), "save written")
	var restored: Dictionary = SaveManager.restore(SaveManager.read_file(path)["data"])
	var kindles2: Array = restored["party"].get_member("chiara").deck.filter(func(o: OwnedCard) -> bool: return o.card_id == "chiara_fire_kindle")
	check(restored["ok"] and kindles2.filter(func(o: OwnedCard) -> bool: return o.upgrade_level == 1).size() == 1, "upgrade persists through save/load")
	DirAccess.remove_absolute(path)


func _find_instance(cm: CombatManager, uid: String) -> CardInstance:
	for pile: Array[CardInstance] in [cm.deck.hand, cm.deck.draw_pile, cm.deck.discard_pile]:
		for card in pile:
			if card.owned_uid == uid:
				if pile != cm.deck.hand:
					pile.erase(card)
					cm.deck.hand.append(card)
				return card
	return null


# --- Save / load -------------------------------------------------------------------

func _test_save_load() -> void:
	print("Save / load")
	for combo: Array in [["fire", "holy"], ["fire", "tanking"], ["arcana", "holy"]]:
		var party := Party.from_selection({"chiara": combo[0], "bianca": combo[1]})
		party.get_member("chiara").add_card("chiara_%s_%s" % [combo[0], "fireball" if combo[0] == "fire" else "lance"])
		party.get_member("bianca").add_card("bianca_%s_%s" % [combo[1], "smite" if combo[1] == "holy" else "slam"])
		party.get_member("chiara").current_hp = 41
		var inventory := Inventory.new()
		inventory.gold = 12
		var progress := MapProgress.new(MapGraph.from_dict(DataRegistry.get_map("royal_castle_tutorial")))
		var path := "user://test_spec_save.json"
		SaveManager.write_file(path, SaveManager.serialize(party, inventory, progress))
		var read := SaveManager.read_file(path)
		var restored: Dictionary = SaveManager.restore(read["data"])
		DirAccess.remove_absolute(path)
		check(read["ok"] and restored["ok"] and restored["warnings"].is_empty(), "%s + %s round trip validates without warnings" % combo)
		var p2: Party = restored["party"]
		check(p2.get_member("chiara").specialization.id == combo[0] and p2.get_member("bianca").specialization.id == combo[1], "%s + %s specializations restored" % combo)
		check(p2.get_member("chiara").deck.size() == 11 and p2.get_member("bianca").deck.size() == 11 and p2.get_member("chiara").current_hp == 41, "%s + %s decks and HP restored" % combo)
		var uid_set := {}
		for member in p2.members:
			for owned in member.deck:
				uid_set[owned.uid] = true
		check(uid_set.size() == 22, "%s + %s card uids unique after restore" % combo)
	var swapped := {"version": 1, "party": [{"character_id": "chiara", "specialization_id": "holy"}], "map": {"current_node_id": "royal_chambers"}}
	check(not SaveManager.restore(swapped)["ok"], "Holy on Chiara is rejected")
	var legacy := {"party": [{"character_id": "chiara", "specialization_id": "arcana"}, {"character_id": "bianca", "specialization_id": "tanking"}], "map": {"current_node_id": "royal_chambers"}}
	var legacy_result := SaveManager.restore(legacy)
	check(legacy_result["ok"] and legacy_result["party"].get_member("bianca").deck.size() == 10, "pre-Milestone-3 style Arcana/Tanking save still loads")


# --- Regression ---------------------------------------------------------------------

func _test_existing_specializations_unchanged() -> void:
	print("Existing specializations unchanged")
	var arcana := DataRegistry.get_specialization("arcana")
	var tanking := DataRegistry.get_specialization("tanking")
	check(arcana.starting_deck_card_ids.size() == 10 and tanking.starting_deck_card_ids.size() == 10, "Arcana/Tanking starting decks are still 10 cards")
	check(arcana.card_pool.size() == 19 and tanking.card_pool.size() == 18 and arcana.has_passive() and tanking.has_passive(), "Arcana has 19 pool cards, Tanking 18 (with the expansion); both have a passive")
	var bolt := DataRegistry.get_card("chiara_arcana_bolt")
	check(bolt.cost == 1 and bolt.effects[0]["value"] == 6 and bolt.upgrade["effects"][0]["value"] == 9, "Arcane Bolt values unchanged")
	var cm := _combat("arcana", "tanking")
	_play(cm, "chiara_arcana_bolt")
	check(cm.enemies[0].hp == 20 and cm.enemies[0].statuses.is_empty(), "Arcane Bolt deals 6, no statuses")
	_play(cm, "bianca_tanking_challenge", cm.enemies[0].id)
	check(cm.enemies[0].has_status("taunt") and cm.enemies[0].statuses["taunt"]["stacks"] == 1, "Taunt applies as before")
	cm.end_player_turn()
	check(not cm.enemies[0].has_status("taunt"), "Taunt still expires after one round")
