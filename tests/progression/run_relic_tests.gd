extends SceneTree
## Relics: data, rolls, Max HP relics (and saves), boss relic stats (Energy, hand size, enemy damage),
## relic effects in battle (PassiveRunner relic entries), and relic rewards from elites and bosses. Run:
##   godot --headless --path . --script res://tests/progression/run_relic_tests.gd

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
	_test_rolls()
	_test_max_hp()
	_test_boss_stats()
	_test_effects()
	_test_rewards()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(relics: Array, chiara: String = "arcana", bianca: String = "tanking") -> CombatManager:
	var party := Party.from_selection({"chiara": chiara, "bianca": bianca})
	var inventory := Inventory.new()
	for relic_id: String in relics:
		RelicEffects.gain(relic_id, party, inventory)
	var cm := CombatManager.new()
	cm.setup(party, DataRegistry.get_encounter("castle_final_regular_01"), inventory, 3)
	for enemy in cm.enemies:
		enemy.max_hp = 500
		enemy.hp = 500
	return cm


func _give(cm: CombatManager, card_id: String) -> CardInstance:
	var def := DataRegistry.get_card(card_id)
	var card := CardInstance.new()
	card.definition = def
	card.owner_character_id = def.owner_character_id
	cm.deck.hand.append(card)
	return card


func _test_data() -> void:
	var ids := RelicEffects.all_relics()
	check(ids.size() >= 20, "at least 20 relics (%d)" % ids.size())
	var bad: Array[String] = []
	for relic_id in ids:
		var def := DataRegistry.get_item(relic_id)
		if not RelicEffects.RARITIES.has(str(def.get("rarity", ""))) or str(def.get("description", "")) == "":
			bad.append(relic_id + ": rarity/description")
		if not ResourceLoader.exists(str(def.get("icon", ""))):
			bad.append(relic_id + ": icon")
		if not def.has("effects") and not def.has("stats") and not def.has("effect"):
			bad.append(relic_id + ": does nothing")
		for effect: Dictionary in def.get("effects", []):
			if not TRIGGERS.has(str(effect.get("trigger", {}).get("event", ""))) or not EFFECTS.has(str(effect.get("effect", {}).get("effect", ""))):
				bad.append(relic_id + ": " + str(effect.get("text", "?")))
	check(bad.is_empty(), "every relic has a rarity, text, icon and known effects (%s)" % ", ".join(bad))
	check(RelicEffects.all_relics("boss").size() >= 3, "at least 3 boss relics for a boss's choice")


func _test_rolls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var inventory := Inventory.new()
	inventory.add_relic("sundial_shard")
	var seen: Dictionary = {}
	for i in 300:
		seen[RelicEffects.roll(rng, {"common": 5, "uncommon": 3, "rare": 1}, inventory)] = true
	check(not seen.has("sundial_shard") and not seen.has("runic_crown") and seen.size() >= 15, "rolls skip owned and boss relics and reach most others (%d)" % seen.size())
	var choices := RelicEffects.boss_choices(rng, inventory, 3)
	check(choices.size() == 3 and choices.all(func(r: String) -> bool: return str(DataRegistry.get_item(r).get("rarity", "")) == "boss") and choices[0] != choices[1] and choices[1] != choices[2], "a boss offers 3 different boss relics (%s)" % ", ".join(choices))


func _test_max_hp() -> void:
	var party := Party.from_selection({"chiara": "fire", "bianca": "holy"})
	var inventory := Inventory.new()
	var chiara := party.get_member("chiara")
	var base := chiara.max_hp
	check(RelicEffects.gain("royal_pear", party, inventory) and chiara.max_hp == base + 6 and chiara.current_hp == base + 6, "Royal Pear: +6 Max HP and HP (%d)" % chiara.max_hp)
	check(not RelicEffects.gain("royal_pear", party, inventory), "a relic cannot be owned twice")
	var data := SaveManager.serialize(party, inventory, MapProgress.new(MapGraph.from_dict(DataRegistry.get_map(GameConfig.DEFAULT_MAP_ID))))
	var restored := SaveManager.restore(JSON.parse_string(JSON.stringify(data)))
	var back: PartyMember = (restored["party"] as Party).get_member("chiara") if restored["party"] != null else null
	check(back != null and back.max_hp == base + 6 and back.current_hp == base + 6, "a save keeps the relic's Max HP and full HP (%s)" % ("%d / %d" % [back.current_hp, back.max_hp] if back != null else "no party"))
	RelicEffects.gain("crimson_chalice", party, inventory)
	check(chiara.max_hp == base - 2 and chiara.current_hp <= chiara.max_hp, "Crimson Chalice: -8 Max HP on top (%d)" % chiara.max_hp)


func _test_boss_stats() -> void:
	var plain := _combat([])
	plain.start()
	var crown := _combat(["runic_crown"])
	crown.start()
	check(crown.max_energy == plain.max_energy + 1 and crown.deck.hand.size() == plain.deck.hand.size() - 1, "Runic Crown: +1 Energy, 1 card fewer (%d energy, %d cards)" % [crown.max_energy, crown.deck.hand.size()])
	var halo := _combat(["twin_halo"])
	halo.start()
	check(halo.deck.hand.size() == plain.deck.hand.size() + 1 and halo.get_combatant("chiara").block >= 6, "Twin Halo: 1 card more and 6 Block at the start")
	var eclipse := _combat(["eclipse_orb"])
	check(eclipse.enemies.all(func(e: Combatant) -> bool: return is_equal_approx(e.damage_scale, plain.enemies[0].damage_scale * 1.1)), "Eclipse Orb: enemies hit 10% harder")


func _test_effects() -> void:
	# Sundial Shard: +1 Energy on turn 3.
	var cm := _combat(["sundial_shard"])
	cm.start()
	for c in cm.party_combatants:
		c.max_hp = 999
		c.hp = 999
	cm.end_player_turn()
	var turn_2 := cm.energy
	cm.end_player_turn()
	check(cm.turn == 3 and cm.energy == turn_2 + 1, "Sundial Shard: +1 Energy on turn 3")
	# Mercury Bell: 2 damage to every enemy at the start of each turn.
	cm = _combat(["mercury_bell"])
	cm.start()
	check(cm.enemies.all(func(e: Combatant) -> bool: return e.hp < 500), "Mercury Bell hurts every enemy at the turn start")
	# A relic that fells the last enemy at the start of a turn wins the fight there and then.
	var party_end := Party.from_selection({"chiara": "arcana", "bianca": "tanking"})
	var inv_end := Inventory.new()
	RelicEffects.gain("mercury_bell", party_end, inv_end)
	var end_cm := CombatManager.new()
	end_cm.setup(party_end, DataRegistry.get_encounter("castle_final_regular_01"), inv_end, 3)
	for enemy in end_cm.enemies:
		enemy.max_hp = 2
		enemy.hp = 2
	end_cm.start()
	check(end_cm.state == CombatManager.State.VICTORY, "Mercury Bell felling every enemy at the turn start ends the fight in victory")
	# Alchemist's Stone: the first debuff each turn gets one more stack.
	cm = _combat(["alchemists_stone"], "fire", "venom")
	cm.start()
	cm.energy = 10
	var foe: Combatant = cm.get_living_enemies()[0]
	cm.play_card(_give(cm, "chiara_fire_kindle"), foe.id)
	var burn_def := _give(cm, "chiara_fire_kindle")
	var first: int = int(foe.statuses.get("burn", {}).get("stacks", 0))
	cm.play_card(burn_def, foe.id)
	var second: int = int(foe.statuses.get("burn", {}).get("stacks", 0)) - first
	check(first > second, "Alchemist's Stone: +1 stack on the first debuff of the turn only (%d then +%d)" % [first, second])
	# Sisters' Locket: a card after the other sister's gives both 2 Block.
	cm = _combat(["sisters_locket"])
	cm.start()
	cm.energy = 10
	var bianca_c := cm.get_combatant("bianca")
	var block_before := bianca_c.block
	cm.play_card(_give(cm, "chiara_arcana_bolt"), cm.get_living_enemies()[0].id)
	cm.play_card(_give(cm, "bianca_tanking_strike"), cm.get_living_enemies()[0].id)
	check(bianca_c.block >= block_before + 2 and cm.get_combatant("chiara").block >= 2, "Sisters' Locket: alternating sisters shields both")
	# Raven Horn: a kill refunds 1 Energy.
	cm = _combat(["raven_horn"])
	cm.start()
	var victim: Combatant = cm.get_living_enemies()[0]
	victim.hp = 1
	victim.block = 0
	var energy_before := cm.energy
	cm.hit(victim, 5, DamageTypes.PHYSICAL, cm.get_combatant("chiara"))
	check(not victim.is_alive() and cm.energy == energy_before + 1, "Raven Horn: a kill gives 1 Energy")
	# Relic bar feedback: the runner names the relic that fired.
	cm = _combat(["chime_of_echoes"])
	var fired: Array[String] = []
	cm.passives.relic_triggered.connect(func(relic_id: String, _t: String) -> void: fired.append(relic_id))
	cm.start()
	cm.energy = 10
	for i in 4:
		cm.play_card(_give(cm, "chiara_arcana_ward"))
	check(fired.has("chime_of_echoes") and cm.enemies.all(func(e: Combatant) -> bool: return e.hp < 500), "Chime of Echoes: the 4th card hits every enemy and the relic reports it")


func _test_rewards() -> void:
	var gs: Node = root.get_node_or_null("GameState")  # autoloads are reached through the tree in script mode
	if gs == null:
		check(false, "GameState autoload is available")
		return
	gs.save_path = "user://test_relics.json"
	gs.reset_selection()
	gs.select_specialization("chiara", "arcana")
	gs.select_specialization("bianca", "holy")
	gs.create_party_from_selection()
	gs.begin_adventure()
	var node: MapNodeData = gs.get_current_node()
	gs.room_state = {"node_id": node.id, "kind": node.type}
	var before: int = gs.inventory.relics.size()
	gs.record_combat_victory(10, {"id": "qa", "elite": true, "enemies": []})
	var found: Array = gs.room_state.get("relics", [])
	check(found.size() == 1 and gs.inventory.relics.size() == before + 1, "an elite victory leaves a relic (%s)" % ", ".join(found))
	gs.room_state = {"node_id": node.id, "kind": node.type}
	gs.pending_reward = null
	gs.record_combat_victory(10, {"id": "qa", "boss": true, "enemies": []})
	var choices: Array = gs.room_state.get("relic_choices", [])
	check(choices.size() == 3, "a boss offers 3 boss relics")
	var owned: int = gs.inventory.relics.size()
	check(gs.take_boss_relic(str(choices[0])) and not gs.take_boss_relic(str(choices[1])) and gs.inventory.relics.size() == owned + 1, "only one boss relic can be taken")
	gs.delete_save()
