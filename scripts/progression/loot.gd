class_name Loot
extends RefCounted
## Equipment drops (pure logic). Rules come from the "loot" block of data/progression/run_rules.json:
##   "<source>": {"chance": 0..1, "rarity_weights": {rarity: weight}}   sources: combat, elite, boss
## A drop is one equipment item that somebody in the party can use, rolled once and saved with the
## room (see GameState.record_combat_victory), so reloading never rerolls or duplicates it.


## Item ids dropped by a won fight of `source` ("combat", "elite" or "boss"). Usually 0 or 1 item.
static func roll(source: String, party: Party, rng: RandomNumberGenerator, rules: Dictionary = {}) -> Array[String]:
	if rules.is_empty():
		rules = RunRules.get_block("loot").get(source, {})
	var dropped: Array[String] = []
	if rules.is_empty() or rng.randf() >= float(rules.get("chance", 0.0)):
		return dropped
	var picked := pick(party, rng, rules.get("rarity_weights", {}))
	if picked != "":
		dropped.append(picked)
	return dropped


## One random item, weighted by rarity, usable by at least one party member as she is now (right
## princess and specialization: a Fire staff never drops for an Arcana Chiara). "" when none fits.
## `exclude`: item ids that must not be picked (a shop's other offers).
static func pick(party: Party, rng: RandomNumberGenerator, rarity_weights: Dictionary, exclude: Array[String] = []) -> String:
	var candidates: Array[String] = []
	var weights: Array[float] = []
	for entry in Equipment.all_items():
		var weight := float(rarity_weights.get(str(entry.get("rarity", "common")), 0.0))
		if weight <= 0.0 or exclude.has(str(entry["id"])) or not Equipment.usable_by_party(party, str(entry["id"])):
			continue
		candidates.append(str(entry["id"]))
		weights.append(weight)
	if candidates.is_empty():
		return ""
	var total := 0.0
	for w in weights:
		total += w
	var roll_value := rng.randf() * total
	for i in candidates.size():
		roll_value -= weights[i]
		if roll_value <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]
