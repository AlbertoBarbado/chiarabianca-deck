class_name DeckRules
extends RefCounted
## Prepared-deck validation (data/progression/campaign_rules.json "deck"). Pure rules shared by the
## Deck Workshop, the expedition preparation screen and ExpeditionService.start.
##
## A sister may take a card when it is hers (owner) and of her primary or secondary specialization.
## Copies of one card are capped by rarity, secondary-specialization cards are capped per deck, and
## the deck size per sister stays within min..max (so draws stay consistent).


static func rules() -> Dictionary:
	return CampaignRules.block("deck")


## Why this card cannot go into this sister's deck ("" when it can).
static func card_allowed(member: PartyMember, card_id: String) -> String:
	var def := DataRegistry.get_card(card_id)
	if def == null:
		return "Unknown card."
	if def.token:
		return "Tokens never join a deck."
	if def.owner_character_id != member.id:
		return "%s cannot use %s's cards." % [member.definition.display_name, DataRegistry.get_character(def.owner_character_id).display_name if DataRegistry.get_character(def.owner_character_id) != null else def.owner_character_id]
	if def.specialization_id == "" or def.specialization_id == member.specialization.id:
		return ""
	if member.secondary_specialization != null and def.specialization_id == member.secondary_specialization.id:
		return ""
	var spec := DataRegistry.get_specialization(def.specialization_id)
	return "Needs %s as her primary or secondary specialization." % (spec.display_name if spec != null else def.specialization_id)


static func max_copies(card_id: String) -> int:
	var def := DataRegistry.get_card(card_id)
	var caps: Dictionary = rules().get("max_copies", {})
	return int(caps.get(def.rarity if def != null else "", 2))


static func is_secondary_card(member: PartyMember, card_id: String) -> bool:
	var def := DataRegistry.get_card(card_id)
	return def != null and member.secondary_specialization != null and def.specialization_id == member.secondary_specialization.id \
		and def.specialization_id != member.specialization.id


## Problems with one sister's prepared deck (card ids, in deck order). [] = valid.
static func validate(member: PartyMember, card_ids: Array) -> Array[String]:
	var problems: Array[String] = []
	var r := rules()
	var name := member.definition.display_name
	var low := int(r.get("min_per_sister", 8))
	var high := int(r.get("max_per_sister", 15))
	if card_ids.size() < low:
		problems.append("%s needs at least %d cards (has %d)." % [name, low, card_ids.size()])
	if card_ids.size() > high:
		problems.append("%s can take at most %d cards (has %d)." % [name, high, card_ids.size()])
	var counts := {}
	var secondary := 0
	for card_id: Variant in card_ids:
		var reason := card_allowed(member, str(card_id))
		if reason != "":
			problems.append("%s: %s" % [_card_name(str(card_id)), reason])
			continue
		counts[str(card_id)] = int(counts.get(str(card_id), 0)) + 1
		if is_secondary_card(member, str(card_id)):
			secondary += 1
	for card_id: String in counts:
		if int(counts[card_id]) > max_copies(card_id):
			problems.append("At most %d copies of %s." % [max_copies(card_id), _card_name(card_id)])
	var cap := int(r.get("secondary_card_limit", 4))
	if secondary > cap:
		problems.append("%s can take at most %d %s cards (has %d)." % [name, cap, member.secondary_specialization.display_name, secondary])
	return problems


## Why one more copy cannot be added to the current list ("" when it can).
static func can_add(member: PartyMember, card_ids: Array, card_id: String) -> String:
	var reason := card_allowed(member, card_id)
	if reason != "":
		return reason
	if card_ids.size() >= int(rules().get("max_per_sister", 15)):
		return "The deck is full (%d cards)." % int(rules().get("max_per_sister", 15))
	if card_ids.count(card_id) >= max_copies(card_id):
		return "At most %d copies of this card." % max_copies(card_id)
	if is_secondary_card(member, card_id):
		var secondary := card_ids.filter(func(id: Variant) -> bool: return is_secondary_card(member, str(id))).size()
		if secondary >= int(rules().get("secondary_card_limit", 4)):
			return "At most %d secondary-specialization cards." % int(rules().get("secondary_card_limit", 4))
	return ""


## Problems with a whole prepared party (campaign roster + prepared uids). [] = ready to depart.
static func validate_campaign(campaign: CampaignState) -> Array[String]:
	var problems: Array[String] = []
	for m in campaign.roster.members:
		var ids: Array = campaign.prepared_cards(m.id).map(func(o: OwnedCard) -> String: return o.card_id)
		problems.append_array(validate(m, ids))
	return problems


static func _card_name(card_id: String) -> String:
	var def := DataRegistry.get_card(card_id)
	return def.display_name if def != null else card_id
