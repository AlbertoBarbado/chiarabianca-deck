extends Node

const SimPolicy := preload("res://tests/combat/sim_policy.gd")
## Full-run balance simulation: plays whole runs (castle -> forest -> coast) with HP carried between
## rooms, route choices, card rewards, rests (heal or upgrade), shops (potions, gear), chests, loot
## and equipment, using the same greedy card policy as balance_simulation.gd. Reports, per
## specialization pairing, how often a run is won, how far it gets, the HP left before each boss and
## which fights end runs. A greedy bot plays worse than a person, so the targets are: runs are
## winnable (>= 40%) but not automatic (<= 85%), and the act bosses are where runs are decided.
##   godot --headless --path . res://tests/combat/run_simulation.tscn [-- runs_per_pair]

const CHIARA_SPECS := ["arcana", "fire", "frost", "wind"]
const BIANCA_SPECS := ["tanking", "holy", "ashveil", "venom"]
static var PAIRS: Array = _all_pairs()


static func _all_pairs() -> Array:
	var pairs: Array = []
	for chiara in CHIARA_SPECS:
		for bianca in BIANCA_SPECS:
			pairs.append([chiara, bianca])
	return pairs

const MAX_TURNS := 40
const POTION_USE_BELOW := 0.35
const TARGET_MIN_WIN := 0.4
const TARGET_MAX_WIN := 0.85

var _runs := 30
## Maps a run plays (empty = the normal act order); set by the "map:<id>" experiment.
var _maps: Array = []
## Per-run shop counters (prices rise with use) and gold spent on services.
var _counters := {"removals": 0, "upgrades": 0, "gold_spent": 0}
var _failures := 0
var _checks := 0
## Aether cards played and the Aether they found (reset per pairing; shows whether the combo fires).
var _aether_stats := {"plays": 0, "aether": 0, "reactions": 0}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		_runs = int(args[0])
	var only := args[1] if args.size() > 1 else ""  # e.g. "fire+holy": simulate just that pairing
	DataRegistry.reload()
	_experiment(args[2] if args.size() > 2 else "")
	var all_wins := 0.0
	var simulated := 0
	var killers_total: Dictionary = {}
	var rows: Array[String] = []
	for pair: Array in PAIRS:
		if only != "" and only != "%s+%s" % pair:
			continue
		_aether_stats = {"plays": 0, "aether": 0, "reactions": 0}
		var stats := _simulate_pair(pair[0], pair[1])
		simulated += 1
		if int(_aether_stats["plays"]) > 0:
			print("  %s + %s: %d Aether card plays, %.1f Aether on average" % [pair[0], pair[1], _aether_stats["plays"], float(_aether_stats["aether"]) / _aether_stats["plays"]])
		if int(_aether_stats["reactions"]) > 0:
			print("  %s + %s: %.1f twin reactions per run" % [pair[0], pair[1], float(_aether_stats["reactions"]) / _runs])
		all_wins += stats["win_rate"]
		for key: String in stats["killers"]:
			killers_total[key] = int(killers_total.get(key, 0)) + int(stats["killers"][key])
		rows.append("  %-18s win %3d%%  reached castle/forest/coast %s  HP before bosses %s  deck %d  gold %d" % ["%s + %s" % pair,
			roundi(stats["win_rate"] * 100.0), stats["reached"], stats["boss_hp"], roundi(stats["deck"]), roundi(stats["gold"])])
		check(stats["win_rate"] >= TARGET_MIN_WIN, "%s + %s: runs are winnable (%d%%)" % [pair[0], pair[1], roundi(stats["win_rate"] * 100.0)])
		check(stats["win_rate"] <= TARGET_MAX_WIN, "%s + %s: runs are not automatic (%d%%)" % [pair[0], pair[1], roundi(stats["win_rate"] * 100.0)])
	print("\n== Full runs (%d per pairing, greedy bot) ==" % _runs)
	for row in rows:
		print(row)
	var killer_list := killers_total.keys()
	killer_list.sort_custom(func(a: String, b: String) -> bool: return int(killers_total[a]) > int(killers_total[b]))
	var parts: Array[String] = []
	for key: String in killer_list.slice(0, 12):
		parts.append("%s %d" % [key, int(killers_total[key])])
	print("  runs ended by: " + ", ".join(parts))
	print("  average run win rate: %d%%" % roundi(all_wins / maxi(1, simulated) * 100.0))
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Balance experiments (diagnostics only, data in memory): "no_passive_holy" drops Holy's passive,
## "no_heal" turns every heal into 0, "no_holy_element" makes Holy cards deal physical damage.
func _experiment(kind: String) -> void:
	match kind:
		"no_passive_holy":
			DataRegistry.get_specialization("holy").passive = {}
		"no_heal":
			for def: CardDef in DataRegistry.cards.values():
				for effect: Dictionary in def.effects:
					if str(effect.get("effect", "")) == "heal":
						effect["value"] = 0
		"no_holy_element":
			DataRegistry.get_specialization("holy").damage_element = "physical"
		"pre_aether", "old_arcana", "old_holy":  # the Arcana and/or Holy decks before the Aether cards
			if kind != "old_holy":
				var arcana := DataRegistry.get_specialization("arcana")
				arcana.starting_deck_card_ids[arcana.starting_deck_card_ids.find("chiara_arcana_siphon")] = "chiara_arcana_bolt"
				arcana.card_pool = arcana.card_pool.slice(0, 6)
			if kind != "old_arcana":
				var holy := DataRegistry.get_specialization("holy")
				holy.starting_deck_card_ids[holy.starting_deck_card_ids.find("bianca_holy_hymn")] = "bianca_holy_strike"
				holy.card_pool = holy.card_pool.slice(0, 6)
		"no_aether":  # Aether cards keep only their base values
			for def: CardDef in DataRegistry.cards.values():
				for effect: Dictionary in def.effects + (def.upgrade.get("effects", []) as Array):
					effect.erase("per_aether")
		"no_gear_effects":  # gear keeps its stats but does nothing in battle
			for item: Dictionary in Equipment.all_items():
				item.erase("effects")
		"no_new_gear":  # only the chest armour and weapons of before (no helmet ... boots items)
			for item: Dictionary in Equipment.all_items():
				if str(item.get("icon", "")).contains("/generated/gear/"):
					DataRegistry.items.erase(str(item["id"]))
	# "map:<id>": a standalone adventure, played alone from a fresh party (e.g. map:frostpeak).
	if kind.begins_with("map:"):
		_maps = [kind.trim_prefix("map:")]
	# "old_pool_<spec>": that specialization's reward pool without the 9 expansion cards.
	if kind.begins_with("old_pool_"):
		var spec := DataRegistry.get_specialization(kind.trim_prefix("old_pool_"))
		spec.card_pool = spec.card_pool.slice(0, spec.card_pool.size() - 9)
	if kind != "":
		print("EXPERIMENT: " + kind)


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _simulate_pair(chiara: String, bianca: String) -> Dictionary:
	var wins := 0
	var reached := [0, 0, 0]
	var boss_hp: Dictionary = {}
	var killers: Dictionary = {}
	var deck := 0.0
	var gold := 0.0
	for run in _runs:
		var result := _play_run(chiara, bianca, 1000 + run * 7)
		if result["won"]:
			wins += 1
		for i in mini(3, int(result["acts"])):
			reached[i] += 1
		for boss_id: String in result["boss_hp"]:
			var entry: Array = boss_hp.get(boss_id, [0.0, 0])
			boss_hp[boss_id] = [entry[0] + float(result["boss_hp"][boss_id]), entry[1] + 1]
		if str(result["killer"]) != "":
			killers[result["killer"]] = int(killers.get(result["killer"], 0)) + 1
		deck += float(result["deck"])
		gold += float(result["gold"])
	var boss_text: Array[String] = []
	for boss_id: String in boss_hp:
		boss_text.append("%s %d%%" % [boss_id.replace("boss_", "").replace("demo_", ""), roundi(boss_hp[boss_id][0] / boss_hp[boss_id][1] * 100.0)])
	return {"win_rate": float(wins) / _runs, "reached": "%d/%d/%d" % reached, "boss_hp": ", ".join(boss_text), "killers": killers,
		"deck": deck / _runs, "gold": gold / _runs}


# --- One run --------------------------------------------------------------------------------

func _play_run(chiara: String, bianca: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_counters = {"removals": 0, "upgrades": 0, "gold_spent": 0}
	var party := Party.from_selection({"chiara": chiara, "bianca": bianca})
	var inventory := Inventory.new()
	inventory.gold = GameConfig.STARTING_GOLD
	var acts: Array = _maps if not _maps.is_empty() else RunRules.get_block("acts").get("order", [])
	var result := {"won": false, "acts": 0, "boss_hp": {}, "killer": "", "deck": 0, "gold": 0}
	for act_index in acts.size():
		result["acts"] = act_index + 1
		if act_index > 0:
			GameState.heal_between_acts(party)
		var graph := MapGraph.from_dict(DataRegistry.get_map(str(acts[act_index])))
		var node := graph.get_node_data(graph.start_node_id)
		while node != null and node.type != MapNodeData.TYPE_EXIT:
			var next := _choose_next(graph, node, party, rng)
			if next == null:
				break
			node = next
			var outcome := _enter(node, party, inventory, rng, result)
			if outcome == "defeat":
				result["deck"] = party.get_total_deck_size()
				result["gold"] = inventory.gold
				return result
	result["won"] = true
	result["spent"] = _counters["gold_spent"]
	result["deck"] = party.get_total_deck_size()
	result["gold"] = inventory.gold
	return result


## Route policy: hurt parties look for rest, healthy ones for fights and chests (a little randomness
## so different runs take different paths).
func _choose_next(graph: MapGraph, node: MapNodeData, party: Party, rng: RandomNumberGenerator) -> MapNodeData:
	var options: Array[MapNodeData] = []
	for next_id in node.next_ids:
		options.append(graph.get_node_data(next_id))
	if options.is_empty():
		return null
	var hp := _hp_ratio(party)
	var best: MapNodeData = null
	var best_score := -INF
	for option in options:
		var score := rng.randf() * 1.5
		match option.type:
			MapNodeData.TYPE_REST, MapNodeData.TYPE_TOWN:
				score += 4.0 * (1.0 - hp)
			MapNodeData.TYPE_COMBAT:
				score += 2.0 * hp
			MapNodeData.TYPE_ELITE:
				score += 4.0 * hp - 2.0
			MapNodeData.TYPE_TREASURE:
				score += 2.5
			MapNodeData.TYPE_MERCHANT:
				score += 1.0
			MapNodeData.TYPE_EVENT:
				score += 1.2
		if score > best_score:
			best_score = score
			best = option
	return best


func _hp_ratio(party: Party) -> float:
	var hp := 0.0
	var max_hp := 0.0
	for member in party.members:
		hp += member.current_hp
		max_hp += member.max_hp
	return hp / maxf(1.0, max_hp)


func _enter(node: MapNodeData, party: Party, inventory: Inventory, rng: RandomNumberGenerator, result: Dictionary) -> String:
	match node.type:
		MapNodeData.TYPE_COMBAT, MapNodeData.TYPE_ELITE, MapNodeData.TYPE_BOSS:
			var encounter := DataRegistry.get_encounter(node.encounter_id)
			if node.type == MapNodeData.TYPE_BOSS:
				result["boss_hp"][node.encounter_id] = _hp_ratio(party)
			if not _fight(encounter, party, inventory, rng):
				result["killer"] = node.encounter_id
				return "defeat"
			_after_victory(encounter, party, inventory, rng)
		MapNodeData.TYPE_REST:
			_rest(party, float(node.raw.get("heal_percent", GameConfig.DEFAULT_REST_HEAL_FRACTION * 100.0)) / 100.0)
		MapNodeData.TYPE_TOWN:
			var town := DataRegistry.get_town(node.town_id)
			if (town.get("services", []) as Array).has("rest"):
				_rest(party, float(town.get("heal_percent", 30)) / 100.0)
			if (town.get("services", []) as Array).has("merchant"):
				_shop(str(town.get("shop_id", "")), party, inventory)
		MapNodeData.TYPE_MERCHANT:
			_shop(node.shop_id, party, inventory)
		MapNodeData.TYPE_TREASURE:
			var state := TreasureRoom.generate(node.treasure_id, party, inventory, rng)
			var choices: Array = state.get("choices", [])
			var pick := 0
			for i in choices.size():
				if str((choices[i] as Dictionary).get("type", "")) == "equipment":
					pick = i
			if not choices.is_empty():
				TreasureRoom.claim(state, pick, party, inventory)
				_equip_all(party, inventory)
	return ""


func _rest(party: Party, fraction: float) -> void:
	if _hp_ratio(party) < 0.75:
		party.rest(fraction)
		return
	for member in party.members:  # healthy: upgrade a card instead (one per rest)
		var options := CardUpgrader.get_upgradable_cards(member)
		if not options.is_empty():
			CardUpgrader.upgrade(member, options[0].uid)
			return


func _shop(shop_id: String, party: Party, inventory: Inventory) -> void:
	var shop_def := DataRegistry.get_shop(shop_id)
	if shop_def.is_empty():
		return
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = hash(shop_id) + inventory.gold
	var shop := Merchant.from_definition(shop_def, party, gear_rng)  # as in the game: usable gear + offers
	_shop_services(shop_def, party, inventory)
	for entry: Dictionary in shop.stock.duplicate():
		var item_id := str(entry.get("item_id", ""))
		if item_id == "":
			continue
		var is_gear := Equipment.is_equipment(item_id)
		var wanted := (not is_gear and inventory.count_of(item_id) < 2) or (is_gear and _gear_useful(party, item_id))
		if wanted and inventory.can_afford(shop.get_price(item_id)):
			shop.buy(item_id, inventory)
	_equip_all(party, inventory)


## Gold services, like a sensible player: thin the deck of its weakest basic card, buy the rarest
## affordable card, then upgrade. A reserve is kept for potions.
func _shop_services(shop_def: Dictionary, party: Party, inventory: Inventory) -> void:
	var reserve := 20
	if ShopServices.service_enabled("removal", shop_def) and inventory.gold >= ShopServices.removal_price(_counters["removals"], shop_def) + reserve:
		var worst := _weakest_basic(party)
		if not worst.is_empty() and ShopServices.remove_card(party, inventory, worst[0], worst[1], _counters["removals"], 0, shop_def) == "":
			_counters["removals"] += 1
			_counters["gold_spent"] += ShopServices.removal_price(_counters["removals"] - 1, shop_def)
	var rng := RandomNumberGenerator.new()
	rng.seed = inventory.gold * 31 + party.get_total_deck_size()
	var offers := ShopServices.card_offers(party, rng, shop_def)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["price"]) > int(b["price"]))
	for offer in offers:
		if inventory.gold >= int(offer["price"]) + reserve and party.get_total_deck_size() < 34:
			if ShopServices.buy_card(offer, party, inventory) == "":
				_counters["gold_spent"] += int(offer["price"])
				break
	for i in 2:
		var price := ShopServices.upgrade_price(_counters["upgrades"], shop_def)
		if not ShopServices.service_enabled("upgrade", shop_def) or inventory.gold < price + reserve:
			break
		var done := false
		for member in party.members:
			var options := CardUpgrader.get_upgradable_cards(member)
			if not options.is_empty() and ShopServices.upgrade_card(party, inventory, member.id, options[0].uid, _counters["upgrades"], i, shop_def) == "":
				_counters["upgrades"] += 1
				_counters["gold_spent"] += price
				done = true
				break
		if not done:
			break


## [character_id, uid] of the basic card with the least printed value (a Taunt or small Block first).
func _weakest_basic(party: Party) -> Array:
	var best: Array = []
	var best_value := INF
	for member in party.members:
		for owned in member.deck:
			var def := DataRegistry.get_card(owned.card_id)
			if def == null or def.rarity != "basic" or member.deck.size() <= 6:
				continue
			var value := 0.0
			for effect: Dictionary in def.effects:
				value += float(effect.get("value", 0))
			if value < best_value:
				best_value = value
				best = [member.id, owned.uid]
	return best


func _gear_useful(party: Party, item_id: String) -> bool:
	for member in party.members:
		for slot: String in Equipment.slots_for(item_id):
			if Equipment.can_equip(member, item_id) == "" and str(member.equipment.get(slot, "")) == "":
				return true
	return false


## Puts stash items into empty slots of whoever can wear them.
func _equip_all(party: Party, inventory: Inventory) -> void:
	for item_id: String in inventory.equipment.duplicate():
		for member in party.members:
			var placed := false
			for slot: String in Equipment.slots_for(item_id):
				if Equipment.can_equip(member, item_id) == "" and str(member.equipment.get(slot, "")) == "":
					placed = Equipment.equip(member, inventory, item_id, slot) == ""
					break
			if placed:
				break


func _after_victory(encounter: Dictionary, party: Party, inventory: Inventory, rng: RandomNumberGenerator) -> void:
	inventory.add_gold(int(encounter.get("gold_reward", 0)))
	var rules: Dictionary = {}
	if bool(encounter.get("elite", false)):
		rules = RunRules.get_block("elite_defaults")
	if encounter.get("reward", {}) is Dictionary and not (encounter.get("reward", {}) as Dictionary).is_empty():
		rules = encounter["reward"]
	var reward := CardReward.generate(party, rng, CardReward.OPTION_COUNT, rules)
	var best := -1
	var best_rank := -1
	for i in reward.options.size():
		var rank := CardReward._rarity_rank(DataRegistry.get_card(str(reward.options[i]["card_id"])).rarity) * 10 + rng.randi_range(0, 5)
		if rank > best_rank:
			best_rank = rank
			best = i
	if best >= 0 and party.get_total_deck_size() < 34:
		reward.choose(best, party)
	var source := "boss" if bool(encounter.get("boss", false)) else ("elite" if bool(encounter.get("elite", false)) else "combat")
	for item_id in Loot.roll(source, party, rng):
		inventory.add_equipment(item_id)
	_equip_all(party, inventory)
	# Relics as in GameState.record_combat_victory: elites leave one, bosses offer boss relics (the bot
	# takes a random one of the three).
	var relic_rules: Dictionary = RunRules.get_block("relics")
	if source == "elite":
		RelicEffects.gain(RelicEffects.roll(rng, relic_rules.get("elite_weights", {}), inventory), party, inventory)
	elif source == "boss":
		var choices := RelicEffects.boss_choices(rng, inventory, int(relic_rules.get("boss_choices", 3)))
		if not choices.is_empty():
			RelicEffects.gain(choices[rng.randi_range(0, choices.size() - 1)], party, inventory)


# --- Combat (greedy, as in balance_simulation.gd, plus potions) ----------------------------------

func _fight(encounter: Dictionary, party: Party, inventory: Inventory, rng: RandomNumberGenerator) -> bool:
	var cm := CombatManager.new()
	cm.setup(party, encounter, inventory, rng.randi())
	cm.start()
	while cm.state == CombatManager.State.PLAYER_TURN and cm.turn < MAX_TURNS:
		_maybe_potion(cm, inventory)
		_play_turn(cm)
		if cm.state == CombatManager.State.PLAYER_TURN:
			cm.end_player_turn()
	var won := cm.state == CombatManager.State.VICTORY
	if won:
		cm.commit_to_party()
	return won


func _maybe_potion(cm: CombatManager, inventory: Inventory) -> void:
	for c in cm.get_living_party():
		if float(c.hp) / c.max_hp < POTION_USE_BELOW:
			for item_id: String in inventory.items:
				if cm.use_potion(item_id, c.id) == "":
					return


func _play_turn(cm: CombatManager) -> void:
	var guard := 0
	while cm.state == CombatManager.State.PLAYER_TURN and guard < SimPolicy.MAX_PLAYS_PER_TURN:
		guard += 1
		var best: CardInstance = null
		var best_score := -1.0
		for card in cm.deck.hand:
			if cm.can_play(card) != "":
				continue
			var score := SimPolicy.score(cm, card)
			if score > best_score:
				best_score = score
				best = card
		if best == null or best_score <= 0.0:
			return
		if CardEffects.uses_aether(best.definition):
			_aether_stats["plays"] += 1
			_aether_stats["aether"] += cm.aether
		var reactions_before := cm.reactions_fired
		cm.play_card(best, SimPolicy.target_for(cm, best))
		_aether_stats["reactions"] = int(_aether_stats.get("reactions", 0)) + cm.reactions_fired - reactions_before
