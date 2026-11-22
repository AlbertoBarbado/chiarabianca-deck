class_name CardReward
extends RefCounted
## One post-combat card reward: a set of owner-tagged options of which the player may take
## at most one (or skip). Pure logic; the reward screen only renders it.

const OPTION_COUNT := 3
## Higher weight = appears more often. Rarities not listed use DEFAULT_WEIGHT.
const RARITY_WEIGHTS := {"basic": 2.0, "common": 6.0, "uncommon": 3.0, "rare": 1.0}
const DEFAULT_WEIGHT := 2.0

## Each option: {card_id: String, owner_character_id: String}
var options: Array[Dictionary] = []
var resolved: bool = false
var chosen_card: OwnedCard = null


## Rolls distinct cards from the card pools of every party member's selected specialization.
## rules (optional, e.g. the elite block of data/progression/run_rules.json): card_options, rarity_weights,
## guaranteed_min_rarity (at least one option of that rarity or better, when such a card exists).
static func generate(party: Party, rng: RandomNumberGenerator, count: int = OPTION_COUNT, rules: Dictionary = {}) -> CardReward:
	var reward := CardReward.new()
	count = int(rules.get("card_options", count))
	var weights: Dictionary = RARITY_WEIGHTS.duplicate()
	weights.merge(rules.get("rarity_weights", {}), true)
	var candidates: Array[Dictionary] = []
	var epic := str(rules.get("pool", "")) == "epic"
	for member in party.members:
		# The secondary specialization (campaign hybrid builds) offers its pool at reduced weight.
		var sources: Array = [[member.specialization, 1.0]]
		if member.secondary_specialization != null:
			sources.append([member.secondary_specialization, float(CampaignRules.block("deck").get("secondary_reward_weight", 0.5))])
		for source: Array in sources:
			var spec: SpecializationDef = source[0]
			var pool: Array[String] = spec.epic_pool if epic else spec.card_pool
			for card_id in pool:
				var def := DataRegistry.get_card(card_id)
				if def != null and not candidates.any(func(c: Dictionary) -> bool: return c["card_id"] == card_id):
					candidates.append({
						"card_id": card_id,
						"owner_character_id": member.id,
						"weight": float(weights.get(def.rarity, DEFAULT_WEIGHT)) * float(source[1]),
					})
	while reward.options.size() < count and not candidates.is_empty():
		var index := _pick_weighted(candidates, rng)
		if reward.options.is_empty() and rules.has("guaranteed_min_rarity"):
			index = _guaranteed_index(candidates, str(rules["guaranteed_min_rarity"]), index, rng)
		var picked: Dictionary = candidates[index]
		reward.options.append({"card_id": picked["card_id"], "owner_character_id": picked["owner_character_id"]})
		# Remove every candidate with the same card id so options never repeat a card.
		candidates = candidates.filter(func(c: Dictionary) -> bool: return c["card_id"] != picked["card_id"])
	return reward


## Adds the option's card to its owner's individual deck. Returns the new OwnedCard, or null
## if the reward was already resolved or the option is invalid.
func choose(index: int, party: Party) -> OwnedCard:
	if resolved or index < 0 or index >= options.size():
		return null
	var option := options[index]
	var member := party.get_member(str(option["owner_character_id"]))
	if member == null or not _offered_by(member.specialization, str(option["card_id"])) \
			and not (member.secondary_specialization != null and _offered_by(member.secondary_specialization, str(option["card_id"]))):
		return null
	chosen_card = member.add_card(str(option["card_id"]))
	resolved = true
	return chosen_card


static func _offered_by(spec: SpecializationDef, card_id: String) -> bool:
	return spec.card_pool.has(card_id) or spec.epic_pool.has(card_id)


static func _rarity_rank(rarity: String) -> int:
	return ["basic", "common", "uncommon", "rare", "epic"].find(rarity)


static func _guaranteed_index(candidates: Array[Dictionary], min_rarity: String, fallback: int, rng: RandomNumberGenerator) -> int:
	var eligible: Array[int] = []
	for i in candidates.size():
		var def := DataRegistry.get_card(str(candidates[i]["card_id"]))
		if def != null and _rarity_rank(def.rarity) >= _rarity_rank(min_rarity):
			eligible.append(i)
	return eligible[rng.randi_range(0, eligible.size() - 1)] if not eligible.is_empty() else fallback


func to_dict() -> Dictionary:
	return {"options": options.duplicate(true), "resolved": resolved}


## Rebuilds a saved reward; unusable options (unknown card or owner) are dropped.
static func from_dict(data: Variant, party: Party) -> CardReward:
	var reward := CardReward.new()
	if not data is Dictionary:
		return reward
	for raw: Variant in (data as Dictionary).get("options", []):
		if raw is Dictionary and DataRegistry.get_card(str(raw.get("card_id", ""))) != null and party.get_member(str(raw.get("owner_character_id", ""))) != null:
			reward.options.append({"card_id": str(raw["card_id"]), "owner_character_id": str(raw["owner_character_id"])})
	reward.resolved = bool((data as Dictionary).get("resolved", false))
	return reward


func skip() -> void:
	resolved = true


static func _pick_weighted(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for c in candidates:
		total += c["weight"]
	var roll := rng.randf() * total
	for i in candidates.size():
		roll -= candidates[i]["weight"]
		if roll <= 0.0:
			return i
	return candidates.size() - 1
