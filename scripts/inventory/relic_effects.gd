class_name RelicEffects
extends RefCounted
## Reads the effects of owned relics (data/items, category "relic"). Relics are permanent and
## data-driven: each has one effect {type, value}. Supported types:
##   combat_start_block  every party member starts each battle with N Block
##   first_turn_draw     draw N extra cards on the first turn of each battle
##   heal_after_victory  living party members heal N HP after a won battle
## Newer relics instead carry:
##   "effects": [passive]   in-battle effects in the PassiveRunner format (like worn equipment); they
##                          belong to the party: the sister who caused the event, else the first living one
##   "stats": {"energy": n, "hand_size": n, "max_hp": n, "enemy_damage_pct": n}
##   "rarity": common | uncommon | rare | boss | bond   (boss relics are offered as a choice of 3 by bosses;
##             bond relics are never rolled: the Sister Bond grants them, see Bond.relics)

const RARITIES := ["common", "uncommon", "rare", "boss", "bond"]


## Sum of one stat over the given relic ids ("energy", "hand_size", "max_hp", "enemy_damage_pct").
static func stat_for(relic_ids: Array, key: String) -> int:
	var sum := 0
	for relic_id: Variant in relic_ids:
		sum += int((DataRegistry.get_item(str(relic_id)).get("stats", {}) as Dictionary).get(key, 0))
	return sum


static func stat(inventory: Inventory, key: String) -> int:
	return stat_for(inventory.relics, key) if inventory != null else 0


## The in-battle passives of every owned relic, named after the relic ("relic:<id>#<n>").
static func passives(inventory: Inventory) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory == null:
		return result
	for relic_id in inventory.relics:
		var def := DataRegistry.get_item(relic_id)
		var effects: Array = def.get("effects", [])
		for i in effects.size():
			var passive: Dictionary = (effects[i] as Dictionary).duplicate(true)
			if not passive.has("trigger") or not passive.has("effect"):
				continue
			passive["id"] = "relic:%s#%d" % [relic_id, i]
			passive["name"] = str(def.get("name", relic_id))
			passive["relic_id"] = relic_id
			result.append(passive)
	return result


## Adds a relic and applies what it changes outside battle (Max HP). Use this, not Inventory.add_relic,
## whenever a relic is gained during a run.
static func gain(relic_id: String, party: Party, inventory: Inventory) -> bool:
	if not inventory.add_relic(relic_id):
		return false
	apply_stats(party, inventory)
	return true


## Re-applies relic Max HP to every party member (PartyMember.extra_max_hp, then Equipment.refresh_stats).
static func apply_stats(party: Party, inventory: Inventory) -> void:
	if party == null:
		return
	var bonus := stat(inventory, "max_hp")
	for member in party.members:
		member.extra_max_hp = bonus
		Equipment.refresh_stats(member)


static func all_relics(rarity: String = "") -> Array[String]:
	DataRegistry.ensure_loaded()
	var ids: Array[String] = []
	for item_id: String in DataRegistry.items:
		var entry: Dictionary = DataRegistry.items[item_id]
		if str(entry.get("category", "")) == "relic" and (rarity == "" or str(entry.get("rarity", "common")) == rarity):
			ids.append(item_id)
	return ids


## One random relic the party does not own, weighted by rarity ("" when none is left).
static func roll(rng: RandomNumberGenerator, rarity_weights: Dictionary, inventory: Inventory, exclude: Array = []) -> String:
	var candidates: Array[String] = []
	var weights: Array[float] = []
	for relic_id in all_relics():
		var weight := float(rarity_weights.get(str(DataRegistry.get_item(relic_id).get("rarity", "common")), 0.0))
		if weight <= 0.0 or (inventory != null and inventory.has_relic(relic_id)) or exclude.has(relic_id):
			continue
		candidates.append(relic_id)
		weights.append(weight)
	if candidates.is_empty():
		return ""
	var total_weight := 0.0
	for w in weights:
		total_weight += w
	var pick := rng.randf() * total_weight
	for i in candidates.size():
		pick -= weights[i]
		if pick <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]


## Up to `count` different boss relics the party does not own, for a boss's choice.
static func boss_choices(rng: RandomNumberGenerator, inventory: Inventory, count: int = 3) -> Array[String]:
	var picks: Array[String] = []
	for i in count:
		var relic_id := roll(rng, {"boss": 1.0}, inventory, picks)
		if relic_id == "":
			break
		picks.append(relic_id)
	return picks


static func total(inventory: Inventory, effect_type: String) -> int:
	if inventory == null:
		return 0
	var sum := 0
	for relic_id in inventory.relics:
		var effect: Dictionary = DataRegistry.get_item(relic_id).get("effect", {})
		if str(effect.get("type", "")) == effect_type:
			sum += int(effect.get("value", 0))
	return sum
