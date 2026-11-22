class_name Apothecary
extends RefCounted
## Castle potion service: buying, brewing, the potion belt (capacity) and the expedition loadout.
## Potions are the existing consumables (data/items, category "potion"); stock lives in the campaign
## vault (CampaignState.vault.items). Brew recipes: data/apothecary/*.json
##   {id, name, result, count, cost: {gold, essence}, unlock: <Requirements>}
## A recipe is known when it is in CampaignState.recipes or its unlock requirement is met.

const SHOP_POTIONS := ["minor_health_potion", "health_potion"]


static func potions() -> Array[String]:
	DataRegistry.ensure_loaded()
	var result: Array[String] = []
	for item_id: String in DataRegistry.items:
		if str((DataRegistry.items[item_id] as Dictionary).get("category", "")) == "potion":
			result.append(item_id)
	result.sort()
	return result


static func price(item_id: String) -> int:
	return int(DataRegistry.get_item(item_id).get("price", 0))


static func can_buy(campaign: CampaignState, item_id: String) -> String:
	if not SHOP_POTIONS.has(item_id) or price(item_id) <= 0:
		return "The apothecary does not sell that."
	if not campaign.vault.can_afford(price(item_id)):
		return "Not enough gold (%d needed)." % price(item_id)
	return ""


static func buy(campaign: CampaignState, item_id: String) -> String:
	var reason := can_buy(campaign, item_id)
	if reason == "":
		campaign.vault.spend_gold(price(item_id))
		campaign.vault.add_item(item_id)
	return reason


static func known_recipes(campaign: CampaignState) -> Array[Dictionary]:
	DataRegistry.ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe: Dictionary in DataRegistry.brew_recipes.values():
		if campaign.recipes.has(str(recipe["id"])) or (recipe.has("unlock") and Requirements.met(campaign, recipe["unlock"])):
			result.append(recipe)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return result


static func can_brew(campaign: CampaignState, recipe_id: String) -> String:
	var recipe := DataRegistry.get_brew_recipe(recipe_id)
	if recipe.is_empty() or not known_recipes(campaign).any(func(r: Dictionary) -> bool: return str(r["id"]) == recipe_id):
		return "You do not know that recipe."
	if DataRegistry.get_item(str(recipe.get("result", ""))).is_empty():
		return "The recipe's potion is missing."
	var cost: Dictionary = recipe.get("cost", {})
	if not campaign.vault.can_afford(int(cost.get("gold", 0))):
		return "Not enough gold (%d needed)." % int(cost.get("gold", 0))
	if campaign.essence < int(cost.get("essence", 0)):
		return "Not enough Starlight Essence (%d needed)." % int(cost.get("essence", 0))
	return ""


static func brew(campaign: CampaignState, recipe_id: String) -> String:
	var reason := can_brew(campaign, recipe_id)
	if reason != "":
		return reason
	var recipe := DataRegistry.get_brew_recipe(recipe_id)
	var cost: Dictionary = recipe.get("cost", {})
	campaign.vault.spend_gold(int(cost.get("gold", 0)))
	campaign.essence -= int(cost.get("essence", 0))
	campaign.vault.add_item(str(recipe["result"]), maxi(1, int(recipe.get("count", 1))))
	return ""


## The next belt upgrade {capacity, price}, or {} when none is left.
static func next_capacity_upgrade(campaign: CampaignState) -> Dictionary:
	var upgrades: Array = CampaignRules.block("apothecary").get("capacity_upgrades", [])
	return upgrades[campaign.capacity_upgrades_bought] if campaign.capacity_upgrades_bought < upgrades.size() else {}


static func buy_capacity(campaign: CampaignState) -> String:
	var next := next_capacity_upgrade(campaign)
	if next.is_empty():
		return "The belt cannot hold more."
	if not campaign.vault.can_afford(int(next.get("price", 0))):
		return "Not enough gold (%d needed)." % int(next.get("price", 0))
	campaign.vault.spend_gold(int(next.get("price", 0)))
	campaign.potion_capacity = int(next.get("capacity", campaign.potion_capacity + 1))
	campaign.capacity_upgrades_bought += 1
	return ""


static func stored_potions(campaign: CampaignState) -> Dictionary:
	var result := {}
	for item_id: String in campaign.vault.items:
		if str(DataRegistry.get_item(item_id).get("category", "")) == "potion":
			result[item_id] = campaign.vault.count_of(item_id)
	return result


## Problems with a chosen loadout {item_id: count} ([] = fine): stock and belt capacity.
static func validate_loadout(campaign: CampaignState, loadout: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var total := 0
	for item_id: String in loadout:
		var count := int(loadout[item_id])
		if count <= 0:
			continue
		total += count
		if campaign.vault.count_of(item_id) < count:
			problems.append("Only %d %s in the stores." % [campaign.vault.count_of(item_id), str(DataRegistry.get_item(item_id).get("name", item_id))])
	if total > campaign.potion_capacity:
		problems.append("The belt holds %d potions." % campaign.potion_capacity)
	return problems


## Default loadout: fill the belt from the stores, strongest healing first.
static func default_loadout(campaign: CampaignState) -> Dictionary:
	var loadout := {}
	var room := campaign.potion_capacity
	var stored := stored_potions(campaign)
	var ids: Array = stored.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return price(a) > price(b))
	for item_id: String in ids:
		var take := mini(room, int(stored[item_id]))
		if take > 0:
			loadout[item_id] = take
			room -= take
	return loadout
