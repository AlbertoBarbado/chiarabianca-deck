class_name CastleWorkshop
extends RefCounted
## Permanent castle transactions paid from the treasury: card upgrades (Upgrade Workshop),
## equipment refinement (Blacksmith) and specialization unlocks (Training Hall). Each function
## checks everything first, then changes the campaign in one step, so a failed call changes nothing.
## Callers save right after a success (GameState.save_game).


# --- Card upgrades ---------------------------------------------------------------------------------

static func card_upgrade_price(owned: OwnedCard) -> int:
	var def := DataRegistry.get_card(owned.card_id)
	var prices: Dictionary = CampaignRules.block("card_upgrade").get("prices", {})
	return int(prices.get(def.rarity if def != null else "", 100))


## "" when this collection copy can be upgraded now, else the reason.
static func can_upgrade_card(campaign: CampaignState, character_id: String, uid: String) -> String:
	var m := campaign.member(character_id)
	var owned := m.find_card(uid) if m != null else null
	if owned == null:
		return "That card is not in the collection."
	var reason := CardUpgrader.can_upgrade(owned)
	if reason != "":
		return reason
	if not campaign.vault.can_afford(card_upgrade_price(owned)):
		return "Not enough gold (%d needed)." % card_upgrade_price(owned)
	return ""


static func upgrade_card(campaign: CampaignState, character_id: String, uid: String) -> String:
	var reason := can_upgrade_card(campaign, character_id, uid)
	if reason != "":
		return reason
	var m := campaign.member(character_id)
	var owned := m.find_card(uid)
	campaign.vault.spend_gold(card_upgrade_price(owned))
	CardUpgrader.upgrade(m, uid)
	campaign.add_stat("cards_upgraded")
	return ""


# --- Equipment refinement --------------------------------------------------------------------------

static func refinement_level(campaign: CampaignState, item_id: String) -> int:
	return int(campaign.refinement.get(item_id, 0))


static func refine_price(campaign: CampaignState, item_id: String) -> int:
	var rules := CampaignRules.block("refinement")
	var base := int((rules.get("prices", {}) as Dictionary).get(str(Equipment.item(item_id).get("rarity", "common")), 100))
	return int(round(base * pow(float(rules.get("price_step", 1.5)), refinement_level(campaign, item_id))))


## Items the party owns (worn or in the armory), each id once.
static func owned_items(campaign: CampaignState) -> Array[String]:
	var result: Array[String] = []
	for m in campaign.roster.members:
		for slot: String in m.equipment:
			if not result.has(str(m.equipment[slot])):
				result.append(str(m.equipment[slot]))
	for item_id in campaign.vault.equipment:
		if not result.has(item_id):
			result.append(item_id)
	return result


static func can_refine(campaign: CampaignState, item_id: String) -> String:
	if not owned_items(campaign).has(item_id):
		return "You do not own that item."
	if Equipment.refined_bonus(item_id, 1).is_empty():
		return "This item has no stats to refine."
	if refinement_level(campaign, item_id) >= int(CampaignRules.block("refinement").get("max_level", 2)):
		return "Already fully refined."
	if not campaign.vault.can_afford(refine_price(campaign, item_id)):
		return "Not enough gold (%d needed)." % refine_price(campaign, item_id)
	return ""


static func refine(campaign: CampaignState, item_id: String) -> String:
	var reason := can_refine(campaign, item_id)
	if reason != "":
		return reason
	campaign.vault.spend_gold(refine_price(campaign, item_id))
	campaign.refinement[item_id] = refinement_level(campaign, item_id) + 1
	campaign.refresh_roster()
	campaign.add_stat("items_refined")
	return ""


# --- Training Hall ---------------------------------------------------------------------------------

static func spec_unlock_price() -> int:
	return int(CampaignRules.block("specializations").get("unlock_price", 150))


static func can_unlock_spec(campaign: CampaignState, character_id: String, spec_id: String) -> String:
	var spec := DataRegistry.get_specialization(spec_id)
	if spec == null or spec.character_id != character_id:
		return "Unknown specialization."
	if not spec.is_playable():
		return "%s is not ready yet." % spec.display_name
	if campaign.unlocked_specializations(character_id).has(spec_id):
		return "Already learned."
	if not campaign.services.has("training_hall"):
		return "The Training Hall is closed."
	if not campaign.vault.can_afford(spec_unlock_price()):
		return "Not enough gold (%d needed)." % spec_unlock_price()
	return ""


static func unlock_spec(campaign: CampaignState, character_id: String, spec_id: String) -> String:
	var reason := can_unlock_spec(campaign, character_id, spec_id)
	if reason != "":
		return reason
	campaign.vault.spend_gold(spec_unlock_price())
	campaign.unlock_specialization(character_id, spec_id)
	return ""


## Sets a sister's primary specialization (must be learned). Her prepared deck resets to the new
## starting deck, and a secondary equal to the new primary is cleared.
static func set_primary(campaign: CampaignState, character_id: String, spec_id: String) -> String:
	var m := campaign.member(character_id)
	if m == null or not campaign.unlocked_specializations(character_id).has(spec_id):
		return "Learn that specialization first."
	if m.specialization.id == spec_id:
		return ""
	m.specialization = DataRegistry.get_specialization(spec_id)
	if m.secondary_specialization != null and m.secondary_specialization.id == spec_id:
		m.secondary_specialization = null
	_drop_unwearable(campaign, m)
	campaign.reset_prepared_to_starter(character_id)
	return ""


## Sets (or clears with "") the secondary specialization. Needs the Training Hall. Secondary cards
## that no longer fit are removed from the prepared deck.
static func set_secondary(campaign: CampaignState, character_id: String, spec_id: String) -> String:
	var m := campaign.member(character_id)
	if m == null:
		return "Unknown sister."
	if spec_id == "":
		m.secondary_specialization = null
	else:
		if not campaign.services.has("training_hall"):
			return "The Training Hall teaches hybrid styles."
		if not campaign.unlocked_specializations(character_id).has(spec_id):
			return "Learn that specialization first."
		if spec_id == m.specialization.id:
			return "That is already her primary specialization."
		m.secondary_specialization = DataRegistry.get_specialization(spec_id)
	var keep: Array[String] = []
	var ids: Array = []
	for owned in campaign.prepared_cards(character_id):
		if DeckRules.can_add(m, ids, owned.card_id) == "":
			keep.append(owned.uid)
			ids.append(owned.card_id)
	campaign.set_prepared(character_id, keep)
	return ""


## Items a sister can no longer wear after a change of specialization go back to the armory.
static func _drop_unwearable(campaign: CampaignState, m: PartyMember) -> void:
	for slot: String in m.equipment.keys():
		if Equipment.can_equip(m, str(m.equipment[slot])) != "":
			Equipment.unequip(m, campaign.vault, slot)
	campaign.refresh_roster()
