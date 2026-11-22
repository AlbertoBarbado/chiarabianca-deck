class_name EventResolver
extends RefCounted
## Applies the outcome effects of an event choice (data/events). Pure logic, no UI.
##
## Effect types ("type"):
##   gain_gold {value}            lose_gold {value} (never below 0)
##   heal_party {value}           every living member heals value HP
##   heal_party_fraction {fraction}
##   damage_party {value}         every living member loses value HP but is never killed by an event
##                                (HP stops at 1); fallen members are skipped
##   gain_item / lose_item {item_id, count}
##   gain_relic {pool: [ids], fallback_gold}   first relic of the pool not owned yet, else gold
##   gain_equipment {item_id}     the item goes into the party stash (see Equipment)
##   card_reward {}               the caller opens a card reward (reported in the result)
##   start_combat {encounter_id}  the caller starts that fight (reported in the result)
## Choice requirements ("requires"): {"gold": n} and/or {"item": item_id}.
## Event pools: an event lists "pools": [...]; rooms with "event_pool" roll one event of that pool.


## Returns {"card_reward": bool, "encounter_id": String, "log": Array[String]}.
static func apply(effects: Array, party: Party, inventory: Inventory) -> Dictionary:
	var result := {"card_reward": false, "encounter_id": "", "log": [] as Array[String]}
	var lines: Array[String] = result["log"]
	for effect: Dictionary in effects:
		var value := int(effect.get("value", 0))
		match str(effect.get("type", "")):
			"gain_gold":
				inventory.add_gold(maxi(0, value))
				lines.append("Gained %d gold." % maxi(0, value))
			"lose_gold":
				var paid := mini(inventory.gold, maxi(0, value))
				inventory.spend_gold(paid)
				lines.append("Lost %d gold." % paid)
			"heal_party":
				for member in party.get_living_members():
					var healed := member.heal(maxi(0, value))
					lines.append("%s heals %d HP." % [member.definition.display_name, healed])
			"heal_party_fraction":
				party.rest(float(effect.get("fraction", 0.0)))
			"damage_party":
				for member in party.get_living_members():
					var lost := mini(maxi(0, value), member.current_hp - 1)  # events never kill
					member.current_hp -= lost
					lines.append("%s loses %d HP." % [member.definition.display_name, lost])
			"gain_equipment":
				var gear_id := str(effect.get("item_id", ""))
				if inventory.add_equipment(gear_id):
					lines.append("Found %s (in the party stash)." % Equipment.item(gear_id).get("name", gear_id))
			"gain_item":
				if not DataRegistry.get_item(str(effect.get("item_id", ""))).is_empty():
					inventory.add_item(str(effect["item_id"]), maxi(1, int(effect.get("count", 1))))
					lines.append("Received %s." % DataRegistry.get_item(str(effect["item_id"])).get("name", "an item"))
			"lose_item":
				if inventory.remove_item(str(effect.get("item_id", "")), maxi(1, int(effect.get("count", 1)))):
					lines.append("Gave away %s." % DataRegistry.get_item(str(effect["item_id"])).get("name", "an item"))
			"gain_relic":
				var granted := ""
				for relic_id: Variant in effect.get("pool", []):
					if RelicEffects.gain(str(relic_id), party, inventory):
						granted = str(relic_id)
						break
				if granted != "":
					lines.append("Received the relic %s." % DataRegistry.get_item(granted).get("name", granted))
				else:
					var gold := maxi(0, int(effect.get("fallback_gold", 0)))
					inventory.add_gold(gold)
					lines.append("You already own those relics: gained %d gold instead." % gold)
			"card_reward":
				result["card_reward"] = true
			"start_combat":
				result["encounter_id"] = str(effect.get("encounter_id", ""))
			_:
				push_warning("EventResolver: unknown effect type '%s'" % effect.get("type", ""))
	return result


## "" when the choice can be taken, otherwise the reason it cannot.
static func blocked_reason(choice: Dictionary, inventory: Inventory) -> String:
	var requires: Dictionary = choice.get("requires", {}) if choice.get("requires", {}) is Dictionary else {}
	if requires.has("gold") and inventory.gold < int(requires["gold"]):
		return "Needs %d gold." % int(requires["gold"])
	if requires.has("item") and inventory.count_of(str(requires["item"])) <= 0:
		return "Needs %s." % DataRegistry.get_item(str(requires["item"])).get("name", "an item")
	return ""


## Ids of the events in a pool, in a stable order.
static func pool_event_ids(pool: String) -> Array[String]:
	var ids: Array[String] = []
	DataRegistry.ensure_loaded()
	for event_id: String in DataRegistry.events:
		if (DataRegistry.events[event_id].get("pools", []) as Array).has(pool):
			ids.append(event_id)
	ids.sort()
	return ids


## Picks an event of the pool that the run has not seen yet (all seen: any event of the pool).
static func pick_from_pool(pool: String, seen: Array, rng: RandomNumberGenerator) -> String:
	var ids := pool_event_ids(pool)
	if ids.is_empty():
		return ""
	var fresh := ids.filter(func(id: String) -> bool: return not seen.has(id))
	var candidates: Array[String] = fresh if not fresh.is_empty() else ids
	return candidates[rng.randi_range(0, candidates.size() - 1)]
