class_name TreasureRoom
extends RefCounted
## Treasure room logic: a data-driven set of choices of which exactly one may be taken. The room
## state is a plain Dictionary so it can be saved with the run:
##   {"treasure_id", "choices": [{type, text, ...resolved fields}], "taken": -1}
## All randomness (which relic, which card) is rolled ONCE when the room is created and stored,
## so reloading never rerolls the offer, and "taken" makes a second claim impossible.


static func generate(treasure_id: String, party: Party, inventory: Inventory, rng: RandomNumberGenerator) -> Dictionary:
	var def := DataRegistry.get_treasure(treasure_id)
	var choices: Array = []
	for raw: Variant in def.get("choices", []):
		if not raw is Dictionary:
			continue
		var choice := _resolve(raw as Dictionary, party, inventory, rng)
		if not choice.is_empty():
			choices.append(choice)
	return {"treasure_id": treasure_id, "choices": choices, "taken": -1}


static func _resolve(raw: Dictionary, party: Party, inventory: Inventory, rng: RandomNumberGenerator) -> Dictionary:
	var choice: Dictionary = {"type": str(raw.get("type", "")), "text": str(raw.get("text", ""))}
	match choice["type"]:
		"gold":
			choice["amount"] = maxi(0, int(raw.get("amount", 0)))
		"potion":
			if DataRegistry.get_item(str(raw.get("item_id", ""))).is_empty():
				return {}
			choice["item_id"] = str(raw["item_id"])
			choice["count"] = maxi(1, int(raw.get("count", 1)))
		"relic":
			# "rarity_weights": a random relic the party does not own yet (boss relics only from bosses);
			# "pool": one of a fixed list (older data).
			if raw.has("rarity_weights"):
				var rolled := RelicEffects.roll(rng, raw["rarity_weights"], inventory)
				if rolled == "":
					return {}
				choice["item_id"] = rolled
			else:
				var pool: Array[String] = []
				for relic_id: Variant in raw.get("pool", []):
					if not inventory.has_relic(str(relic_id)) and not DataRegistry.get_item(str(relic_id)).is_empty():
						pool.append(str(relic_id))
				if pool.is_empty():
					return {}  # Every relic of the pool is owned: the choice is not offered.
				choice["item_id"] = pool[rng.randi_range(0, pool.size() - 1)]
		"equipment":
			var weights: Dictionary = raw.get("rarity_weights", {str(raw.get("rarity", "uncommon")): 1.0})
			var item_id := Loot.pick(party, rng, weights)
			if item_id == "":
				return {}
			choice["item_id"] = item_id
		"card":
			var candidates: Array[Dictionary] = []
			for member in party.members:
				for card_id in member.specialization.card_pool:
					var def := DataRegistry.get_card(card_id)
					if def != null and def.rarity == str(raw.get("rarity", "uncommon")):
						candidates.append({"card_id": card_id, "owner_character_id": member.id})
			if candidates.is_empty():
				return {}
			var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
			choice["card_id"] = picked["card_id"]
			choice["owner_character_id"] = picked["owner_character_id"]
		_:
			return {}
	return choice


static func describe(choice: Dictionary) -> String:
	match str(choice.get("type", "")):
		"gold":
			return "%d gold" % int(choice.get("amount", 0))
		"potion":
			return "%d x %s" % [int(choice.get("count", 1)), str(DataRegistry.get_item(str(choice.get("item_id", ""))).get("name", "Potion"))]
		"relic":
			var relic := DataRegistry.get_item(str(choice.get("item_id", "")))
			return "%s: %s" % [relic.get("name", "Relic"), relic.get("description", "")]
		"equipment":
			var gear := Equipment.item(str(choice.get("item_id", "")))
			return "%s: %s" % [gear.get("name", "Equipment"), ", ".join(Equipment.stat_lines(str(choice.get("item_id", ""))))]
		"card":
			var def := DataRegistry.get_card(str(choice.get("card_id", "")))
			var owner_def := DataRegistry.get_character(str(choice.get("owner_character_id", "")))
			return "%s (%s's card)" % [def.display_name if def != null else "Card", owner_def.display_name if owner_def != null else "?"]
	return ""


## Claims one choice. Returns "" on success or the rejection reason; at most one claim per room.
static func claim(state: Dictionary, index: int, party: Party, inventory: Inventory) -> String:
	if int(state.get("taken", -1)) >= 0:
		return "The treasure was already claimed."
	var choices: Array = state.get("choices", [])
	if index < 0 or index >= choices.size():
		return "Invalid choice."
	var choice: Dictionary = choices[index]
	match str(choice.get("type", "")):
		"gold":
			inventory.add_gold(int(choice.get("amount", 0)))
		"potion":
			inventory.add_item(str(choice.get("item_id", "")), int(choice.get("count", 1)))
		"relic":
			if not RelicEffects.gain(str(choice.get("item_id", "")), party, inventory):
				return "You already own that relic."
		"equipment":
			if not inventory.add_equipment(str(choice.get("item_id", ""))):
				return "That item can no longer be received."
		"card":
			var member := party.get_member(str(choice.get("owner_character_id", "")))
			if member == null or DataRegistry.get_card(str(choice.get("card_id", ""))) == null:
				return "That card can no longer be received."
			member.add_card(str(choice["card_id"]))
		_:
			return "Invalid choice."
	state["taken"] = index
	return ""
