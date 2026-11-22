class_name CardRemoval
extends RefCounted
## Permanent card removal at rest sites. Rules (cost, uses per visit, minimum deck size) come from
## data/progression/run_rules.json and may be overridden per rest node. Pure logic: it edits one
## character's individual deck, so the shared party deck is rebuilt without the card in every
## later combat. Other copies and all upgrades stay untouched.


static func rules(node_raw: Dictionary = {}) -> Dictionary:
	return RunRules.get_block("card_removal", node_raw)


static func is_enabled(node_raw: Dictionary = {}) -> bool:
	var r := rules(node_raw)
	return bool(r.get("enabled", false)) and int(r.get("uses_per_rest", 0)) > 0


## "" when the card may be removed now, otherwise the reason it cannot. `uses_so_far` counts removals already done in this rest visit.
static func can_remove(party: Party, inventory: Inventory, character_id: String, uid: String, uses_so_far: int, node_raw: Dictionary = {}) -> String:
	var r := rules(node_raw)
	if not is_enabled(node_raw):
		return "Card removal is not available here."
	if uses_so_far >= int(r.get("uses_per_rest", 1)):
		return "You have already removed a card here."
	var member := party.get_member(character_id) if party != null else null
	if member == null:
		return "Unknown character."
	if member.find_card(uid) == null:
		return "That card is not in this character's deck."
	if member.deck.size() <= int(r.get("min_cards_per_character", 1)):
		return "%s's deck cannot go below %d cards." % [member.definition.display_name, int(r.get("min_cards_per_character", 1))]
	if not inventory.can_afford(int(r.get("gold_cost", 0))):
		return "Not enough gold (%d needed)." % int(r.get("gold_cost", 0))
	return ""


## Removes the card and charges the cost. Returns "" on success or the rejection reason.
static func remove(party: Party, inventory: Inventory, character_id: String, uid: String, uses_so_far: int, node_raw: Dictionary = {}) -> String:
	var reason := can_remove(party, inventory, character_id, uid, uses_so_far, node_raw)
	if reason != "":
		return reason
	var cost := int(rules(node_raw).get("gold_cost", 0))
	if cost > 0:
		inventory.spend_gold(cost)
	party.get_member(character_id).remove_card(uid)
	party.changed.emit()
	return ""
