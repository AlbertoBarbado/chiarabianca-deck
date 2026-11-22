class_name ShopServices
extends RefCounted
## Gold services a merchant offers besides its item stock: cards for sale (from the party's
## specialization pools), card removal and card upgrades. Prices and limits come from the
## "shop_services" block of data/progression/run_rules.json; a shop definition may override any of
## it with its own "shop_services" entry (e.g. a remote camp without upgrades). Removal and upgrade
## prices rise each time the service is used in the run, so gold keeps a purpose late in the run
## without making either service free to spam. Pure logic: the merchant screen only renders it.


static func rules(shop_def: Dictionary = {}) -> Dictionary:
	var merged := RunRules.get_block("shop_services")
	var own: Variant = shop_def.get("shop_services", {})
	if own is Dictionary:
		for key: String in own:
			if merged.get(key) is Dictionary and own[key] is Dictionary:
				(merged[key] as Dictionary).merge(own[key], true)
			else:
				merged[key] = own[key]
	return merged


static func service_enabled(service: String, shop_def: Dictionary = {}) -> bool:
	return bool((rules(shop_def).get(service, {}) as Dictionary).get("enabled", false))


# --- Cards for sale -------------------------------------------------------------------------------

## Rolls the cards this shop sells: {card_id, owner_character_id, price}. Same rng -> same offer,
## so the screen can rebuild it after a reload (the seed is saved in the room state).
static func card_offers(party: Party, rng: RandomNumberGenerator, shop_def: Dictionary = {}) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var card_rules: Dictionary = rules(shop_def).get("cards", {})
	if not bool(card_rules.get("enabled", false)) or party == null:
		return offers
	var reward := CardReward.generate(party, rng, int(card_rules.get("count", 4)), {"rarity_weights": card_rules.get("rarity_weights", {})})
	for option in reward.options:
		var def := DataRegistry.get_card(str(option["card_id"]))
		var base := float((card_rules.get("prices", {}) as Dictionary).get(def.rarity, 60))
		var jitter := rng.randf_range(-float(card_rules.get("price_jitter", 0.0)), float(card_rules.get("price_jitter", 0.0)))
		offers.append({"card_id": def.id, "owner_character_id": str(option["owner_character_id"]), "price": maxi(5, roundi(base * (1.0 + jitter) / 5.0) * 5)})
	return offers


## Buys one offered card into its owner's deck. Returns "" or the reason it failed.
static func buy_card(offer: Dictionary, party: Party, inventory: Inventory) -> String:
	var member := party.get_member(str(offer.get("owner_character_id", ""))) if party != null else null
	if member == null or not member.specialization.card_pool.has(str(offer.get("card_id", ""))):
		return "That card is not for sale."
	if not inventory.spend_gold(int(offer.get("price", 0))):
		return "Not enough gold."
	member.add_card(str(offer["card_id"]))
	party.changed.emit()
	return ""


# --- Card removal ---------------------------------------------------------------------------------

## Price of the next removal: base + step for every shop removal already bought this run.
static func removal_price(times_used: int, shop_def: Dictionary = {}) -> int:
	var r: Dictionary = rules(shop_def).get("removal", {})
	return int(r.get("price", 75)) + int(r.get("price_step", 25)) * times_used


## Removes a card for gold, with the usual minimum deck size (CardRemoval). used_here: removals
## already bought in this shop visit.
static func remove_card(party: Party, inventory: Inventory, character_id: String, uid: String, times_used: int, used_here: int, shop_def: Dictionary = {}) -> String:
	var r: Dictionary = rules(shop_def).get("removal", {})
	if not bool(r.get("enabled", false)):
		return "This merchant does not remove cards."
	var override := {"card_removal": {"enabled": true, "uses_per_rest": int(r.get("per_visit", 1)), "gold_cost": removal_price(times_used, shop_def)}}
	var reason := CardRemoval.remove(party, inventory, character_id, uid, used_here, override)
	return "You have already paid for a removal here." if reason == "You have already removed a card here." else reason


# --- Card upgrades --------------------------------------------------------------------------------

static func upgrade_price(times_used: int, shop_def: Dictionary = {}) -> int:
	var r: Dictionary = rules(shop_def).get("upgrade", {})
	return int(r.get("price", 60)) + int(r.get("price_step", 15)) * times_used


static func upgrade_card(party: Party, inventory: Inventory, character_id: String, uid: String, times_used: int, used_here: int, shop_def: Dictionary = {}) -> String:
	var r: Dictionary = rules(shop_def).get("upgrade", {})
	if not bool(r.get("enabled", false)):
		return "This merchant does not upgrade cards."
	if used_here >= int(r.get("per_visit", 2)):
		return "The smith has no more time today."
	var member := party.get_member(character_id) if party != null else null
	if member == null or member.find_card(uid) == null:
		return "That card is not in this character's deck."
	var reason := CardUpgrader.can_upgrade(member.find_card(uid))
	if reason != "":
		return reason
	var price := upgrade_price(times_used, shop_def)
	if not inventory.spend_gold(price):
		return "Not enough gold (%d needed)." % price
	CardUpgrader.upgrade(member, uid)
	party.changed.emit()
	return ""
