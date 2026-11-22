class_name Fusion
extends RefCounted
## Card Fusion at the Enchanter (data/fusion/recipes.json). A recipe joins one card of each sister
## into a new fusion card that belongs to one of them:
##   {id, name, text, inputs: [{owner, card_id, min_upgrade}], specializations: {chiara: id, bianca: id},
##    bond_level, cost: {gold, essence}, result: {card_id, owner}, consume_inputs, repeatable}
## Specializations must be learned (primary, secondary or unlocked) by the matching sister.
## Inputs are collection copies (the best-upgraded fitting copy is used); with consume_inputs they
## leave the collection and every prepared deck. A non-repeatable recipe can be crafted once
## (CampaignState.fusions_done), so reloading or double-pressing never duplicates the result.


static func all_recipes() -> Array[Dictionary]:
	DataRegistry.ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe: Dictionary in DataRegistry.fusion_recipes.values():
		result.append(recipe)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("bond_level", 0)) < int(b.get("bond_level", 0)) or (int(a.get("bond_level", 0)) == int(b.get("bond_level", 0)) and str(a["id"]) < str(b["id"])))
	return result


## Recipes the bond has revealed (shown at the Enchanter, craftable or not).
static func known_recipes(campaign: CampaignState) -> Array[Dictionary]:
	var known: Array = Bond.unlocks_up_to(campaign.bond_level())["fusion"]
	return all_recipes().filter(func(r: Dictionary) -> bool: return known.has(str(r["id"])))


## The collection copy used for one input (best upgraded first), or null.
static func input_copy(campaign: CampaignState, input: Dictionary) -> OwnedCard:
	var best: OwnedCard = null
	for owned in campaign.collection(str(input.get("owner", ""))):
		if owned.card_id == str(input.get("card_id", "")) and owned.upgrade_level >= int(input.get("min_upgrade", 0)):
			if best == null or owned.upgrade_level > best.upgrade_level:
				best = owned
	return best


## "" when the recipe can be crafted now, else the first reason it cannot.
static func can_fuse(campaign: CampaignState, recipe_id: String) -> String:
	var recipe := DataRegistry.get_fusion_recipe(recipe_id)
	if recipe.is_empty():
		return "Unknown recipe."
	if not campaign.services.has("enchanter"):
		return "The Enchanter has not arrived yet."
	if int(recipe.get("bond_level", 0)) > campaign.bond_level():
		return "Needs Sister Bond level %d." % int(recipe["bond_level"])
	if not bool(recipe.get("repeatable", false)) and campaign.fusions_done.has(recipe_id):
		return "Already crafted."
	var specs: Dictionary = recipe.get("specializations", {})
	for character_id: String in specs:
		if not campaign.unlocked_specializations(character_id).has(str(specs[character_id])):
			var spec := DataRegistry.get_specialization(str(specs[character_id]))
			return "%s must learn %s." % [DataRegistry.get_character(character_id).display_name, spec.display_name if spec != null else specs[character_id]]
	for input: Dictionary in recipe.get("inputs", []):
		if input_copy(campaign, input) == null:
			var def := DataRegistry.get_card(str(input.get("card_id", "")))
			var name := def.display_name if def != null else str(input.get("card_id", ""))
			return "Needs %s%s in the collection." % [name, "+" if int(input.get("min_upgrade", 0)) > 0 else ""]
	var cost: Dictionary = recipe.get("cost", {})
	if not campaign.vault.can_afford(int(cost.get("gold", 0))):
		return "Not enough gold (%d needed)." % int(cost.get("gold", 0))
	if campaign.essence < int(cost.get("essence", 0)):
		return "Not enough Starlight Essence (%d needed)." % int(cost.get("essence", 0))
	var result: Dictionary = recipe.get("result", {})
	if DataRegistry.get_card(str(result.get("card_id", ""))) == null or campaign.member(str(result.get("owner", ""))) == null:
		return "The recipe's result is missing."
	return ""


## Crafts a recipe. Returns {ok, error, card: OwnedCard}.
static func fuse(campaign: CampaignState, recipe_id: String) -> Dictionary:
	var reason := can_fuse(campaign, recipe_id)
	if reason != "":
		return {"ok": false, "error": reason, "card": null}
	var recipe := DataRegistry.get_fusion_recipe(recipe_id)
	var cost: Dictionary = recipe.get("cost", {})
	if bool(recipe.get("consume_inputs", true)):
		for input: Dictionary in recipe.get("inputs", []):
			var copy := input_copy(campaign, input)
			campaign.remove_collection_card(str(input["owner"]), copy.uid)
	campaign.vault.spend_gold(int(cost.get("gold", 0)))
	campaign.essence -= int(cost.get("essence", 0))
	var result: Dictionary = recipe["result"]
	var card := campaign.add_collection_card(str(result["owner"]), str(result["card_id"]))
	if not campaign.fusions_done.has(recipe_id):
		campaign.fusions_done.append(recipe_id)
	campaign.add_stat("fusions")
	return {"ok": true, "error": "", "card": card}
