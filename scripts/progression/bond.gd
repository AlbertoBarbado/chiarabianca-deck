class_name Bond
extends RefCounted
## Sister Bond rules (data/progression/bond.json): XP, levels and what each level unlocks.
## XP sources with a cap (twin reactions, events) are counted per expedition in
## ExpeditionState.bond_counts so repeating an action cannot farm the bond.


static func levels() -> Array:
	return CampaignRules.bond().get("levels", [])


static func level_for(xp: int) -> int:
	var level := 1
	for entry: Dictionary in levels():
		if xp >= int(entry.get("xp", 0)):
			level = maxi(level, int(entry.get("level", 1)))
	return level


static func level_entry(level: int) -> Dictionary:
	for entry: Dictionary in levels():
		if int(entry.get("level", 0)) == level:
			return entry
	return {}


## XP needed for the next level (-1 at the top level).
static func next_threshold(xp: int) -> int:
	for entry: Dictionary in levels():
		if int(entry.get("xp", 0)) > xp:
			return int(entry["xp"])
	return -1


static func source_value(source: String) -> int:
	return int((CampaignRules.bond().get("sources", {}) as Dictionary).get(source, 0))


static func cap(source: String) -> int:
	return int((CampaignRules.bond().get("caps_per_expedition", {}) as Dictionary).get(source, -1))


## Everything unlocked at or below this level: {services: [], fusion: [], relics: []}.
static func unlocks_up_to(level: int) -> Dictionary:
	var result := {"services": [], "fusion": [], "relics": []}
	for entry: Dictionary in levels():
		if int(entry.get("level", 0)) > level:
			continue
		var unlocks: Dictionary = entry.get("unlocks", {})
		for key: String in result:
			for id: Variant in unlocks.get(key, []):
				if not (result[key] as Array).has(str(id)):
					(result[key] as Array).append(str(id))
	return result


## Adds XP to the campaign and opens newly unlocked services. Returns the levels gained ([] if none).
static func add_xp(campaign: CampaignState, amount: int) -> Array[int]:
	var gained: Array[int] = []
	if amount <= 0:
		return gained
	var before := campaign.bond_level()
	campaign.bond["xp"] = int(campaign.bond.get("xp", 0)) + amount
	var after := campaign.bond_level()
	for level in range(before + 1, after + 1):
		gained.append(level)
	apply_unlocks(campaign)
	return gained


## Opens the services the current level unlocks (idempotent; also used after loading a save).
static func apply_unlocks(campaign: CampaignState) -> void:
	for service_id: String in unlocks_up_to(campaign.bond_level())["services"]:
		if not campaign.services.has(service_id):
			campaign.services.append(service_id)


## Bond relics the sisters carry into every expedition at this level.
static func relics(campaign: CampaignState) -> Array[String]:
	var result: Array[String] = []
	result.assign(unlocks_up_to(campaign.bond_level())["relics"])
	return result


## Every bond relic named by the levels exists, has rarity "bond" (never rolled at random).
static func relics_all_known() -> bool:
	for relic_id: String in unlocks_up_to(99)["relics"]:
		if str(DataRegistry.get_item(relic_id).get("rarity", "")) != "bond":
			return false
	return not unlocks_up_to(99)["relics"].is_empty()


## Records a capped XP source during an expedition (counts: ExpeditionState.bond_counts).
## Returns the XP actually earned (0 once the cap is reached).
static func note(counts: Dictionary, source: String, times: int = 1) -> int:
	var limit := cap(source)
	var before := int(counts.get(source, 0))
	var after := before + times if limit < 0 else mini(limit, before + times)
	counts[source] = after
	return (after - before) * source_value(source)
