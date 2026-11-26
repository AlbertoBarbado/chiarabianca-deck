class_name ExpeditionService
extends RefCounted
## The expedition lifecycle (docs/PERSISTENT_RPG_DESIGN.md §2-3): start from the castle, track the
## objective, end it (completed / retreated / defeated), apply what returns home exactly once, let the
## player keep discoveries, and return to the castle. Pure rules on top of GameState; screens only
## call these functions.
##
## Regions (data/regions) and missions (data/missions) unlock through Requirements. Mission
## consequences change the world:
##   "consequences": {"on_complete" | "on_first_complete" | "on_retreat" | "on_defeat": {
##       set_flags: {flag: value}, threat: {region_id: delta}, services: [ids], recipes: [ids],
##       specializations: {character_id: [spec ids]}, messages: [texts]}}


# --- World map ------------------------------------------------------------------------------------

static func regions() -> Array[Dictionary]:
	DataRegistry.ensure_loaded()
	var result: Array[Dictionary] = []
	for region: Dictionary in DataRegistry.regions.values():
		result.append(region)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return result


static func region_unlocked(campaign: CampaignState, region_id: String) -> bool:
	var region := DataRegistry.get_region(region_id)
	return not region.is_empty() and Requirements.met(campaign, region.get("unlock", {}))


static func missions_of(region_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mission_id: Variant in DataRegistry.get_region(region_id).get("missions", []):
		var mission := DataRegistry.get_mission(str(mission_id))
		if not mission.is_empty():
			result.append(mission)
	# The region's current contract (Contracts.sync registers it once the authored missions are done).
	for mission: Dictionary in DataRegistry.missions.values():
		if Contracts.is_contract(mission) and str(mission.get("region_id", "")) == region_id:
			result.append(mission)
	return result


## "" when the mission can be started, else why not.
static func mission_lock_reason(campaign: CampaignState, mission_id: String) -> String:
	var mission := DataRegistry.get_mission(mission_id)
	if mission.is_empty():
		return "Unknown mission."
	if not region_unlocked(campaign, str(mission.get("region_id", ""))):
		return "The region is not open yet."
	var missing := Requirements.missing(campaign, mission.get("unlock", {}))
	if not missing.is_empty():
		return missing[0]
	if not bool(mission.get("repeatable", false)) and campaign.is_mission_completed(mission_id):
		return "Already completed."
	return ""


## Ids of every region and mission open right now (used to announce what an expedition unlocked).
static func open_content(campaign: CampaignState) -> Array[String]:
	var result: Array[String] = []
	for region in regions():
		if region_unlocked(campaign, str(region["id"])):
			result.append("region:" + str(region["id"]))
			for mission in missions_of(str(region["id"])):
				if mission_lock_reason(campaign, str(mission["id"])) == "":
					result.append("mission:" + str(mission["id"]))
	for service_id in campaign.services:
		result.append("service:" + service_id)
	return result


# --- Start ----------------------------------------------------------------------------------------

## Problems that block departure ([] = ready).
static func departure_problems(campaign: CampaignState, mission_id: String, loadout: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var lock := mission_lock_reason(campaign, mission_id)
	if lock != "":
		problems.append(lock)
	problems.append_array(DeckRules.validate_campaign(campaign))
	problems.append_array(Apothecary.validate_loadout(campaign, loadout))
	return problems


## The map definition for a mission: {map_def, layout_def} ({} map_def on failure).
static func build_map(mission: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = mission.get("map", {})
	if str(spec.get("mode", "fixed")) == "generated":
		return ExpeditionGenerator.generate(mission, rng)
	if str(spec.get("mode", "")) == "contract":
		var remixed := ExpeditionGenerator.remix(mission, rng)
		return {"map_def": remixed, "layout_def": {}}
	var template := DataRegistry.get_map(str(spec.get("map_id", "")))
	if template.is_empty():
		return {"map_def": {}, "layout_def": {}}
	if str(spec.get("variation", "shuffle")) == "none":
		return {"map_def": template.duplicate(true), "layout_def": {}}
	return {"map_def": ExpeditionGenerator.vary_fixed(template, rng), "layout_def": {}}


## Leaves the castle on a mission. Returns "" on success or the reason it cannot start.
## seed 0 = random. The expedition party is a copy of the roster with the prepared decks.
static func start(mission_id: String, loadout: Dictionary, seed: int = 0) -> String:
	var campaign := GameState.campaign
	if campaign == null:
		return "No campaign is loaded."
	if GameState.expedition != null:
		return "An expedition is already under way."
	var problems := departure_problems(campaign, mission_id, loadout)
	if not problems.is_empty():
		return problems[0]
	var mission := DataRegistry.get_mission(mission_id)
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
		seed = int(rng.randi())
	rng.seed = seed
	var built := build_map(mission, rng)
	var map_def: Dictionary = built["map_def"]
	if map_def.is_empty():
		return "The way there could not be found (map error)."
	var graph := MapGraph.from_dict(map_def)
	if not graph.validate().is_empty():
		return "The way there could not be found (map error)."
	graph.custom_def = map_def
	graph.custom_layout = built["layout_def"]
	if not graph.custom_layout.is_empty():
		DataRegistry.layouts[graph.id] = graph.custom_layout
	# The expedition party: copies of the sisters with their prepared decks and worn gear.
	var party := Party.new()
	var departure := {}
	for m in campaign.roster.members:
		var copy := clone_member(m, campaign.prepared_cards(m.id))
		party.add_member(copy)
		departure[m.id] = campaign.prepared_uids(m.id)
	var purse := Inventory.new()
	purse.gold = int(CampaignRules.block("expedition").get("purse", GameConfig.STARTING_GOLD))
	for item_id: String in loadout:
		var count := int(loadout[item_id])
		if count > 0 and campaign.vault.remove_item(item_id, count):
			purse.add_item(item_id, count)
	var relics: Array[String] = Bond.relics(campaign)
	if campaign.heirloom != "":
		relics.append(campaign.heirloom)
	for relic_id in relics:
		RelicEffects.gain(relic_id, party, purse)
	for m in party.members:
		m.current_hp = m.max_hp
	var expedition := ExpeditionState.new()
	expedition.mission_id = mission_id
	expedition.region_id = str(mission.get("region_id", ""))
	expedition.seed = seed
	expedition.objective = Objectives.create(mission, map_def)
	expedition.departure_uids = departure
	if Contracts.is_contract(mission):
		expedition.mission_snapshot = mission.duplicate(true)
	campaign.add_attempt(mission_id)
	campaign.add_stat("expeditions_started")
	GameState.party = party
	GameState.inventory = purse
	GameState.map_progress = MapProgress.new(graph)
	GameState.room_state = {}
	GameState.run_flags = {}
	GameState.pending_reward = null
	GameState.run_result = ""
	GameState.expedition = expedition
	GameState.save_game()
	GameState.run_started.emit()
	return ""


## A copy of a roster sister for one expedition: same specializations and gear, the given cards
## (same uids and upgrades; changes during the expedition never touch the collection), full HP.
static func clone_member(source: PartyMember, cards: Array[OwnedCard]) -> PartyMember:
	var copy := PartyMember.new()
	copy.definition = source.definition
	copy.specialization = source.specialization
	copy.secondary_specialization = source.secondary_specialization
	copy.equipment = source.equipment.duplicate()
	copy.next_card_serial = source.next_card_serial
	for owned in cards:
		var card := OwnedCard.create(owned.uid, owned.card_id, source.id)
		card.upgrade_level = owned.upgrade_level
		copy.deck.append(card)
	copy.max_hp = source.definition.max_hp
	copy.level_max_hp = source.level_max_hp  # the sister's level bonus
	copy.extra_max_hp = source.level_max_hp
	Equipment.refresh_stats(copy)
	copy.current_hp = copy.max_hp
	return copy


# --- During the expedition ------------------------------------------------------------------------

## A fight was won (called once per fight by GameState.record_combat_victory).
static func on_combat_won(node: MapNodeData, encounter: Dictionary, reactions: int) -> void:
	var expedition := GameState.expedition
	if expedition == null:
		return
	Objectives.on_room_cleared(expedition.objective, node)
	expedition.fight_xp += Levels.fight_xp(node.type if node != null else "", encounter)
	if bool(encounter.get("boss", false)):
		expedition.bosses_defeated += 1
	if reactions > 0:
		expedition.bond_xp += Bond.note(expedition.bond_counts, "twin_reaction", reactions)


## An event choice strengthened the sisters' bond (capped per expedition).
static func on_bond_event() -> void:
	if GameState.expedition != null:
		GameState.expedition.bond_xp += Bond.note(GameState.expedition.bond_counts, "event")


## Enemy multipliers of the current expedition's mission ({} outside expeditions / by default).
static func enemy_scale() -> Dictionary:
	if GameState.expedition == null:
		return {}
	var scale: Variant = GameState.expedition.mission().get("enemy_scale", {})
	return scale if scale is Dictionary else {}


static func can_return_early() -> bool:
	return GameState.expedition != null and not GameState.expedition.is_finished() and Objectives.is_met(GameState.expedition.objective)


# --- End ------------------------------------------------------------------------------------------

## Ends the expedition and applies what returns home, exactly once (a second call does nothing).
## Returns the results dictionary shown by the results screen.
static func finish(outcome: String) -> Dictionary:
	var campaign := GameState.campaign
	var expedition := GameState.expedition
	if campaign == null or expedition == null:
		return {}
	if expedition.rewards_claimed:
		return expedition.results
	if not ExpeditionState.OUTCOMES.has(outcome):
		outcome = ExpeditionState.OUTCOME_RETREATED
	var before := open_content(campaign)
	var rules := CampaignRules.outcome(outcome)
	var mission := expedition.mission()
	var results := {"outcome": outcome, "mission_id": expedition.mission_id, "lines": [], "unlocked": []}
	# Gold: the purse returns by share.
	var purse := GameState.inventory.gold if GameState.inventory != null else 0
	var kept := int(floor(purse * float(rules.get("gold_share", 0.0))))
	campaign.vault.add_gold(kept)
	results["purse"] = purse
	results["gold_kept"] = kept
	# Mission rewards and consequences.
	var first_time := outcome == ExpeditionState.OUTCOME_COMPLETED and not campaign.is_mission_completed(expedition.mission_id)
	var essence_gained := 0
	if bool(rules.get("mission_rewards", false)) and not mission.is_empty():
		var rewards: Dictionary = mission.get("rewards", {})
		var bonus: Dictionary = rewards.get("first_time", {}) if first_time else {}
		var gold := int(rewards.get("gold", 0)) + int(bonus.get("gold", 0))
		essence_gained = int(rewards.get("essence", 0)) + int(bonus.get("essence", 0))
		campaign.vault.add_gold(gold)
		campaign.essence += essence_gained
		results["mission_gold"] = gold
		for card: Dictionary in bonus.get("cards", []):
			if campaign.add_collection_card(str(card.get("owner", "")), str(card.get("card_id", ""))) != null:
				(results["lines"] as Array).append("New card: %s" % DataRegistry.get_card(str(card["card_id"])).display_name)
		campaign.mark_mission_completed(expedition.mission_id)
	results["essence"] = essence_gained
	var consequences: Dictionary = mission.get("consequences", {})
	var keys: Array[String] = ["on_" + outcome]
	if first_time:
		keys.append("on_first_complete")
	for key in keys:
		(results["lines"] as Array).append_array(apply_consequences(campaign, consequences.get(key, {})))
	# Equipment: worn gear and everything found go back to the castle (never lost).
	var found := 0
	for copy in GameState.party.members:
		var home := campaign.member(copy.id)
		if home != null:
			home.equipment = copy.equipment.duplicate()
	for item_id in GameState.inventory.equipment:
		campaign.vault.add_equipment(item_id)
		found += 1
	results["items"] = found
	# Potions.
	var potions_home := 0
	if bool(rules.get("keep_potions", false)):
		for item_id: String in GameState.inventory.items:
			if str(DataRegistry.get_item(item_id).get("category", "")) == "potion":
				campaign.vault.add_item(item_id, GameState.inventory.count_of(item_id))
				potions_home += GameState.inventory.count_of(item_id)
	results["potions_home"] = potions_home
	# Relics found join the relic collection (heirloom choices).
	var new_relics: Array = []
	for relic_id in GameState.inventory.relics:
		if str(DataRegistry.get_item(relic_id).get("rarity", "")) != "bond" and campaign.discover_relic(relic_id):
			new_relics.append(relic_id)
	results["relics"] = new_relics
	# Discoveries: cards drafted on the way, offered for the collection.
	expedition.discoveries = drafted_cards(expedition)
	expedition.discoveries_allowed = mini(int(rules.get("discoveries", 0)), expedition.discoveries.size())
	expedition.discoveries_claimed = expedition.discoveries_allowed == 0
	# Sister Bond.
	var bond_xp := expedition.bond_xp + Bond.source_value(str(rules.get("bond", ""))) + expedition.bosses_defeated * Bond.source_value("boss_defeated")
	var levels := Bond.add_xp(campaign, bond_xp)
	results["bond_xp"] = bond_xp
	results["bond_levels"] = levels
	# Sister levels: every sister on the roster earns the expedition's XP.
	var xp := Levels.expedition_xp(expedition.fight_xp, outcome, int(mission.get("difficulty", 1)))
	var level_lines: Array = []
	var level_ups := {}
	for m in campaign.roster.members:
		var gained := Levels.add_xp(campaign, m.id, xp)
		level_lines.append_array(gained["lines"])
		level_ups[m.id] = {"from": gained["from"], "to": gained["to"]}
	results["xp"] = xp
	results["level_ups"] = level_ups
	results["level_lines"] = level_lines
	# A completed contract rolls the region's next, harder contract.
	if outcome == ExpeditionState.OUTCOME_COMPLETED and Contracts.is_contract(mission):
		Contracts.advance(campaign, str(mission.get("region_id", "")))
	campaign.add_stat("expeditions_" + outcome)
	campaign.refresh_roster()
	# What opened up.
	for entry in open_content(campaign):
		if not before.has(entry):
			(results["unlocked"] as Array).append(entry)
	expedition.outcome = outcome
	expedition.results = results
	expedition.rewards_claimed = true
	GameState.room_state = {}
	GameState.pending_reward = null
	GameState.save_game()
	return results


static func apply_consequences(campaign: CampaignState, block: Variant) -> Array[String]:
	var lines: Array[String] = []
	if not block is Dictionary:
		return lines
	var c: Dictionary = block
	var flags: Dictionary = c.get("set_flags", {}) if c.get("set_flags", {}) is Dictionary else {}
	for flag: String in flags:
		campaign.set_flag(flag, flags[flag])
	var threat: Dictionary = c.get("threat", {}) if c.get("threat", {}) is Dictionary else {}
	for region_id: String in threat:
		var state := campaign.region_state(region_id)
		state["threat"] = maxi(0, int(state.get("threat", 0)) + int(threat[region_id]))
	for service_id: Variant in c.get("services", []):
		if not campaign.services.has(str(service_id)) and not DataRegistry.get_service(str(service_id)).is_empty():
			campaign.services.append(str(service_id))
	for recipe_id: Variant in c.get("recipes", []):
		if not campaign.recipes.has(str(recipe_id)):
			campaign.recipes.append(str(recipe_id))
			lines.append("New brew: %s" % str(DataRegistry.get_brew_recipe(str(recipe_id)).get("name", recipe_id)))
	var specs: Dictionary = c.get("specializations", {}) if c.get("specializations", {}) is Dictionary else {}
	for character_id: String in specs:
		for spec_id: Variant in specs[character_id]:
			if campaign.unlock_specialization(character_id, str(spec_id)):
				lines.append("%s learned %s." % [DataRegistry.get_character(character_id).display_name, DataRegistry.get_specialization(str(spec_id)).display_name])
	for message: Variant in c.get("messages", []):
		lines.append(str(message))
	return lines


## Cards in the expedition deck that were not taken from the castle (drafted, bought, event gifts),
## one entry per card and owner.
static func drafted_cards(expedition: ExpeditionState) -> Array:
	var result: Array = []
	var seen := {}
	for m in GameState.party.members:
		var left: Array = expedition.departure_uids.get(m.id, [])
		for owned in m.deck:
			var def := DataRegistry.get_card(owned.card_id)
			if left.has(owned.uid) or def == null or def.token:
				continue
			var key := m.id + ":" + owned.card_id
			if seen.has(key):
				continue
			seen[key] = true
			result.append({"card_id": owned.card_id, "owner_character_id": m.id})
	return result


## Keeps the chosen discoveries (indices into expedition.discoveries) in the collection, once.
static func claim_discoveries(indices: Array) -> Array[String]:
	var kept: Array[String] = []
	var expedition := GameState.expedition
	if GameState.campaign == null or expedition == null or expedition.discoveries_claimed:
		return kept
	for index: Variant in indices:
		if kept.size() >= expedition.discoveries_allowed:
			break
		var i := int(index)
		if i < 0 or i >= expedition.discoveries.size():
			continue
		var entry: Dictionary = expedition.discoveries[i]
		if GameState.campaign.add_collection_card(str(entry["owner_character_id"]), str(entry["card_id"])) != null:
			kept.append(str(entry["card_id"]))
	expedition.discoveries_claimed = true
	GameState.save_game()
	return kept


## Back home: the expedition state is dropped and the castle state (roster + vault) is active.
static func return_to_castle() -> void:
	var expedition := GameState.expedition
	if expedition != null and not expedition.rewards_claimed:
		finish(ExpeditionState.OUTCOME_RETREATED)
	GameState.enter_castle()
