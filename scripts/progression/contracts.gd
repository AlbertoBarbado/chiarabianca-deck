class_name Contracts
extends RefCounted
## Region contracts (docs/PERSISTENT_RPG_DESIGN.md §Contracts): once every authored mission of a
## region has been completed, the region always offers one more mission. Contracts are built from
## the region's "contracts" block (data/regions) and the campaign's contract state
## (CampaignState.contracts: region_id -> {tier, kind, seed}):
##   * the region's own map layout is kept; its fights and elites are re-rolled from the region's
##     encounter pools and the quest decides the marked rooms (ExpeditionGenerator.remix);
##   * the tier rises with every completed contract: higher party level needed, more elites,
##     tougher enemies (enemy_scale) and better rewards;
##   * kinds: "hunt" (slay one named elite), "purge" (clear marked lairs), "patrol" (reach the exit
##     through extra elites), "boss" (hunt the region's master again; maps with a boss only).
## Contract missions are ordinary mission dictionaries registered in DataRegistry.missions by sync()
## (a cache derived from data + campaign state, rebuilt on every load), so the expedition flow,
## objectives, saves and the war table treat them like authored missions.

const ID_PREFIX := "contract_"
const KINDS := ["hunt", "purge", "patrol", "boss"]


static func is_contract(mission: Dictionary) -> bool:
	return mission.get("contract", null) is Dictionary


static func mission_id(region_id: String, tier: int) -> String:
	return "%s%s_%d" % [ID_PREFIX, region_id, tier]


## Contracts are offered once the region is open and all its authored missions are completed.
static func region_ready(campaign: CampaignState, region: Dictionary) -> bool:
	if not region.get("contracts", null) is Dictionary or not ExpeditionService.region_unlocked(campaign, str(region.get("id", ""))):
		return false
	for id: Variant in region.get("missions", []):
		if not campaign.is_mission_completed(str(id)):
			return false
	return true


## Creates missing contract states, and (re)registers every current contract mission. Called by
## CampaignState.refresh_roster, so it runs after loading, creating and finishing expeditions.
static func sync(campaign: CampaignState) -> void:
	DataRegistry.ensure_loaded()
	for id: String in DataRegistry.missions.keys():
		if id.begins_with(ID_PREFIX):
			DataRegistry.missions.erase(id)
	if campaign == null:
		return
	for region: Dictionary in DataRegistry.regions.values():
		var region_id := str(region.get("id", ""))
		if not region_ready(campaign, region):
			continue
		if not campaign.contracts.get(region_id, null) is Dictionary:
			campaign.contracts[region_id] = roll(region, 1, "")
		var mission := build_mission(region, campaign.contracts[region_id])
		DataRegistry.missions[str(mission["id"])] = mission


## A fresh contract state for a tier: a kind different from the previous one when possible.
static func roll(region: Dictionary, tier: int, previous_kind: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var kinds := kinds_for(region)
	var options: Array = kinds.filter(func(k: String) -> bool: return k != previous_kind)
	if options.is_empty():
		options = kinds
	return {"tier": tier, "kind": str(options[rng.randi_range(0, options.size() - 1)]), "seed": int(rng.randi() & 0x7fffffff)}


static func kinds_for(region: Dictionary) -> Array:
	var block: Dictionary = region.get("contracts", {})
	var template := DataRegistry.get_map(str(block.get("map_id", "")))
	var has_boss := (template.get("nodes", []) as Array).any(func(n: Dictionary) -> bool: return str(n.get("type", "")) == "boss")
	var kinds: Array = (block.get("kinds", KINDS) as Array).filter(func(k: Variant) -> bool: return KINDS.has(str(k)) and (str(k) != "boss" or has_boss))
	return kinds if not kinds.is_empty() else ["patrol"]


## After a completed contract: the next tier with a new quest.
static func advance(campaign: CampaignState, region_id: String) -> void:
	var state: Dictionary = campaign.contracts.get(region_id, {})
	campaign.contracts[region_id] = roll(DataRegistry.get_region(region_id), int(state.get("tier", 1)) + 1, str(state.get("kind", "")))


# --- Mission dictionaries -------------------------------------------------------------------------

static func required_level(block: Dictionary, tier: int) -> int:
	return mini(Levels.max_level(), int(block.get("base_level", 1)) + tier - 1)


static func enemy_scale(block: Dictionary, tier: int) -> Dictionary:
	var steps := tier - 1
	return {
		"hp": minf(float(block.get("max_hp_scale", 1.8)), 1.0 + steps * float(block.get("hp_per_tier", 0.08))),
		"damage": minf(float(block.get("max_damage_scale", 1.5)), 1.0 + steps * float(block.get("damage_per_tier", 0.05))),
	}


## The quest's target elite (hunt) or boss (boss), chosen from the region's pools by the seed.
static func target_encounter(region: Dictionary, state: Dictionary) -> String:
	var block: Dictionary = region.get("contracts", {})
	var kind := str(state.get("kind", ""))
	var pools := ExpeditionGenerator.remix_pools(block)
	var list: Array = pools["bosses"] if kind == "boss" else pools["all_elites"]
	if list.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.get("seed", 0)) + 17
	return str(list[rng.randi_range(0, list.size() - 1)])


static func build_mission(region: Dictionary, state: Dictionary) -> Dictionary:
	var block: Dictionary = region.get("contracts", {})
	var region_id := str(region["id"])
	var tier := maxi(1, int(state.get("tier", 1)))
	var kind := str(state.get("kind", "patrol"))
	if not kinds_for(region).has(kind):
		kind = str(kinds_for(region)[0])
	var difficulty := clampi(int(block.get("difficulty", 1)) + int((tier - 1) / 2), 1, 5)
	var target := target_encounter(region, {"kind": kind, "seed": state.get("seed", 0)})
	var target_name := str(DataRegistry.get_encounter(target).get("name", "the beast"))
	var nouns: Dictionary = block.get("nouns", {})
	var objective := {}
	var name := ""
	var text := ""
	match kind:
		"hunt":
			name = "Bounty: %s" % target_name
			objective = {"type": Objectives.TYPE_CLEAR_TARGETS, "required": 1, "verb": "Slay", "noun": target_name}
			text = "A bounty is posted on %s. Find its lair (marked on the route) and slay it; then head home or press on." % target_name
		"purge":
			var noun := str(nouns.get("purge", "infested lairs"))
			name = "Purge the %s" % str(block.get("place", region.get("name", "")))
			objective = {"type": Objectives.TYPE_CLEAR_TARGETS, "required": 3, "verb": "Clear", "noun": noun}
			text = "Monsters have dug in across the %s. Clear the three marked %s." % [str(block.get("place", region.get("name", ""))), noun]
		"boss":
			name = "The Return of %s" % target_name.trim_prefix("The ")
			objective = {"type": Objectives.TYPE_BOSS_HUNT, "text": "%s has returned. Defeat it and reach the way out." % target_name}
			text = "%s stirs again, stronger than before." % target_name
		_:
			kind = "patrol"
			name = "Patrol the %s" % str(block.get("place", region.get("name", "")))
			objective = {"type": Objectives.TYPE_REACH_EXIT, "text": "Cross the %s to the far side." % str(block.get("place", region.get("name", "")))}
			text = "Keep the roads safe: cross the %s and break the elite packs gathering on the way." % str(block.get("place", region.get("name", "")))
	var scale := enemy_scale(block, tier)
	if tier > 1:
		text += " Contract rank %d: foes are tougher (+%d%% health)." % [tier, roundi((float(scale["hp"]) - 1.0) * 100.0)]
	var gold := int(block.get("gold", 40)) + int(block.get("gold_per_tier", 12)) * (tier - 1)
	return {
		"id": mission_id(region_id, tier),
		"name": name,
		"region_id": region_id,
		"description": text,
		"objective": objective,
		"map": {"mode": "contract", "map_id": str(block.get("map_id", "")), "pools": block.get("pools", []), "kind": kind, "tier": tier, "target": target},
		"difficulty": difficulty,
		"repeatable": false,
		"unlock": {"level": required_level(block, tier)},
		"rewards": {"gold": gold, "essence": 1 + (1 if kind == "hunt" or kind == "boss" else 0) + int(tier / 3)},
		"enemy_scale": scale,
		"contract": {"tier": tier, "kind": kind, "region_id": region_id},
	}
