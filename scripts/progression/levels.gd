class_name Levels
extends RefCounted
## Sister levels (data/progression/levels.json, docs/PERSISTENT_RPG_DESIGN.md §Levels). Pure rules
## on CampaignState.levels (character_id -> XP) and CampaignState.level_rewards (pending card
## choices). Screens only read these functions.
##
## Each level adds Max HP (applied by CampaignState.refresh_roster and expedition copies). Milestone
## levels grant treasury gold, Starlight Essence, a Mastery card choice (1 of 3 cards of her
## specializations) or, at the top level, the dual specialization. Missions are gated by the party
## level (Requirements "level").

const PATH := "res://data/progression/levels.json"
const RARITY_ORDER := ["basic", "common", "uncommon", "rare", "epic"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = DataRegistry.read_json(PATH)
		_data = parsed if parsed is Dictionary else {}
	return _data


static func table() -> Array:
	return data().get("levels", [])


static func max_level() -> int:
	return int(data().get("max_level", 10))


static func dual_spec_level() -> int:
	return int(data().get("dual_specialization_level", max_level()))


static func xp_rule(key: String) -> float:
	return float((data().get("xp", {}) as Dictionary).get(key, 0))


static func level_for(xp: int) -> int:
	var level := 1
	for entry: Dictionary in table():
		if xp >= int(entry.get("xp", 0)):
			level = maxi(level, int(entry.get("level", 1)))
	return mini(level, max_level())


static func entry(level: int) -> Dictionary:
	for row: Dictionary in table():
		if int(row.get("level", 0)) == level:
			return row
	return {}


static func threshold(level: int) -> int:
	return int(entry(level).get("xp", 0))


static func title(level: int) -> String:
	return str(entry(level).get("title", ""))


# --- Campaign queries -----------------------------------------------------------------------------

static func xp_of(campaign: CampaignState, character_id: String) -> int:
	return int(campaign.levels.get(character_id, 0)) if campaign != null else 0


static func level_of(campaign: CampaignState, character_id: String) -> int:
	return level_for(xp_of(campaign, character_id))


## The party level that gates missions: the rounded-down average of the sisters' levels.
static func party_level(campaign: CampaignState) -> int:
	if campaign == null or campaign.roster == null or campaign.roster.members.is_empty():
		return 1
	var total := 0
	for m in campaign.roster.members:
		total += level_of(campaign, m.id)
	return maxi(1, int(floor(float(total) / campaign.roster.members.size())))


## {level, xp, floor, next (-1 at max), progress 0..1} for bars.
static func progress(campaign: CampaignState, character_id: String) -> Dictionary:
	var xp := xp_of(campaign, character_id)
	var level := level_for(xp)
	var base := threshold(level)
	var next := threshold(level + 1) if level < max_level() else -1
	var share := 1.0 if next < 0 else clampf(float(xp - base) / float(maxi(1, next - base)), 0.0, 1.0)
	return {"level": level, "xp": xp, "floor": base, "next": next, "progress": share}


static func hp_bonus(campaign: CampaignState, character_id: String) -> int:
	return (level_of(campaign, character_id) - 1) * int(data().get("hp_per_level", 0))


static func can_dual_spec(campaign: CampaignState, character_id: String) -> bool:
	return level_of(campaign, character_id) >= dual_spec_level()


## The next level with a milestone reward, as {level, text} ({} at the top).
static func next_milestone(campaign: CampaignState, character_id: String) -> Dictionary:
	for level in range(level_of(campaign, character_id) + 1, max_level() + 1):
		var text := reward_text(entry(level).get("rewards", {}))
		if text != "":
			return {"level": level, "text": text}
	return {}


static func reward_text(rewards: Variant) -> String:
	if not rewards is Dictionary:
		return ""
	var parts: Array[String] = []
	var block: Dictionary = rewards
	if bool(block.get("dual_specialization", false)):
		parts.append("Dual Specialization")
	if block.get("card_choice", null) is Dictionary:
		var choice: Dictionary = block["card_choice"]
		parts.append("Mastery card (%s%s)" % [str(choice.get("rarity", "rare")), ", upgraded" if bool(choice.get("upgraded", false)) else ""])
	if int(block.get("essence", 0)) > 0:
		parts.append("+%d Essence" % int(block["essence"]))
	if int(block.get("gold", 0)) > 0:
		parts.append("+%d gold" % int(block["gold"]))
	return ", ".join(parts)


# --- Gaining XP -----------------------------------------------------------------------------------

## XP a won fight is worth, by its room ("elite") and encounter ("boss").
static func fight_xp(node_type: String, encounter: Dictionary) -> int:
	if bool(encounter.get("boss", false)) or node_type == "boss":
		return int(xp_rule("boss"))
	if node_type == "elite" or bool(encounter.get("elite", false)):
		return int(xp_rule("elite"))
	return int(xp_rule("combat"))


## XP the party takes home: fights won (scaled by the outcome) plus the mission bonus on completion.
static func expedition_xp(fight_xp_total: int, outcome: String, difficulty: int) -> int:
	var shares: Dictionary = (data().get("xp", {}) as Dictionary).get("outcome_share", {})
	var total := int(floor(fight_xp_total * float(shares.get(outcome, 1.0))))
	if outcome == ExpeditionState.OUTCOME_COMPLETED:
		total += maxi(1, difficulty) * int(xp_rule("mission_per_difficulty"))
	return total


## Adds XP to one sister and applies every milestone reached. Returns
## {from, to, lines: [texts], choices: n}. Never passes the top level.
static func add_xp(campaign: CampaignState, character_id: String, amount: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var before := level_of(campaign, character_id)
	var result := {"from": before, "to": before, "xp": maxi(0, amount), "lines": [], "choices": 0}
	if campaign == null or amount <= 0:
		return result
	var cap := threshold(max_level())
	campaign.levels[character_id] = mini(xp_of(campaign, character_id) + amount, maxi(cap, xp_of(campaign, character_id)))
	var after := level_of(campaign, character_id)
	result["to"] = after
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for level in range(before + 1, after + 1):
		_apply_rewards(campaign, character_id, level, result, rng)
	if after > before:
		campaign.refresh_roster()
	return result


static func _apply_rewards(campaign: CampaignState, character_id: String, level: int, result: Dictionary, rng: RandomNumberGenerator) -> void:
	var rewards: Dictionary = entry(level).get("rewards", {}) if entry(level).get("rewards", {}) is Dictionary else {}
	var lines: Array = result["lines"]
	var name := _name(campaign, character_id)
	lines.append("%s reached level %d — %s (+%d Max HP)" % [name, level, title(level), int(data().get("hp_per_level", 0))])
	if int(rewards.get("gold", 0)) > 0:
		campaign.vault.add_gold(int(rewards["gold"]))
		lines.append("Treasury +%d gold" % int(rewards["gold"]))
	if int(rewards.get("essence", 0)) > 0:
		campaign.essence += int(rewards["essence"])
		lines.append("Starlight Essence +%d" % int(rewards["essence"]))
	for service_id: Variant in rewards.get("services", []):
		if not campaign.services.has(str(service_id)):
			campaign.services.append(str(service_id))
			lines.append("Castle: the %s is open" % str(DataRegistry.get_service(str(service_id)).get("name", service_id)))
	if rewards.get("card_choice", null) is Dictionary:
		var choice := make_card_choice(campaign, character_id, level, rewards["card_choice"], rng)
		if not (choice.get("options", []) as Array).is_empty():
			campaign.level_rewards.append(choice)
			result["choices"] = int(result["choices"]) + 1
			lines.append("%s may choose a Mastery card" % name)
	if bool(rewards.get("dual_specialization", false)):
		lines.append("%s can now take a second specialization (Training Hall)" % name)


static func _name(campaign: CampaignState, character_id: String) -> String:
	var m := campaign.member(character_id)
	return m.definition.display_name if m != null else character_id


# --- Mastery card choices -------------------------------------------------------------------------

## A pending choice: {character_id, level, upgraded, options: [card ids]} from her primary (and
## secondary) specialization pools at the given rarity or better (falls back to lower rarities).
static func make_card_choice(campaign: CampaignState, character_id: String, level: int, rule: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var m := campaign.member(character_id)
	var choice := {"character_id": character_id, "level": level, "upgraded": bool(rule.get("upgraded", false)), "options": []}
	if m == null:
		return choice
	var pools: Array[String] = []
	for spec in [m.specialization, m.secondary_specialization]:
		if spec != null:
			for card_id in (spec as SpecializationDef).card_pool:
				if not pools.has(card_id):
					pools.append(card_id)
	var min_rank := RARITY_ORDER.find(str(rule.get("rarity", "rare")))
	var picked: Array = []
	for rank in range(min_rank, -1, -1):
		var candidates: Array = pools.filter(func(card_id: String) -> bool:
			var def := DataRegistry.get_card(card_id)
			return def != null and RARITY_ORDER.find(def.rarity) >= rank and not picked.has(card_id))
		ExpeditionGenerator._shuffle(candidates, rng)
		for card_id: String in candidates:
			if picked.size() >= CardReward.OPTION_COUNT:
				break
			picked.append(card_id)
		if picked.size() >= CardReward.OPTION_COUNT:
			break
	choice["options"] = picked
	return choice


## Takes option `option_index` of pending choice `choice_index` into the sister's collection.
## Returns the card's display name, or "" when the choice is invalid.
static func claim_choice(campaign: CampaignState, choice_index: int, option_index: int) -> String:
	if choice_index < 0 or choice_index >= campaign.level_rewards.size():
		return ""
	var choice: Dictionary = campaign.level_rewards[choice_index]
	var options: Array = choice.get("options", [])
	if option_index < 0 or option_index >= options.size():
		return ""
	var def := DataRegistry.get_card(str(options[option_index]))
	var owned := campaign.add_collection_card(str(choice["character_id"]), str(options[option_index]), 1 if bool(choice.get("upgraded", false)) else 0)
	if owned == null or def == null:
		return ""
	campaign.level_rewards.remove_at(choice_index)
	return def.display_name


## XP worth of the missions already completed (save migration: older campaigns start at the level
## their completed missions would have earned, with a typical number of fights per mission).
static func estimate_xp(completed: Array) -> int:
	var total := 0
	for mission_id: Variant in completed:
		var mission := DataRegistry.get_mission(str(mission_id))
		if mission.is_empty():
			continue
		var difficulty := int(mission.get("difficulty", 1))
		total += expedition_xp(int(xp_rule("combat")) * (3 + difficulty) + int(xp_rule("elite")) * mini(difficulty - 1, 2), ExpeditionState.OUTCOME_COMPLETED, difficulty)
	return total
