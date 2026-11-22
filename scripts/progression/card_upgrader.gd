class_name CardUpgrader
extends RefCounted
## Data-driven card upgrades. A card is upgradable when its definition's "upgrade" block has
## effects; "max_level" (default 1) caps repeated upgrades. The upgrade level is stored on the
## character's individual OwnedCard, so it persists across combats and saves while the static
## CardDef stays untouched.

const DEFAULT_MAX_LEVEL := 1


static func get_max_level(def: CardDef) -> int:
	if def == null or (def.upgrade.get("effects", []) as Array).is_empty():
		return 0
	return int(def.upgrade.get("max_level", DEFAULT_MAX_LEVEL))


## Returns "" if the card can be upgraded, otherwise the reason it cannot.
static func can_upgrade(owned: OwnedCard) -> String:
	var def := DataRegistry.get_card(owned.card_id)
	if def == null:
		return "Unknown card."
	var max_level := get_max_level(def)
	if max_level <= 0:
		return "This card has no upgrade."
	if owned.upgrade_level >= max_level:
		return "Already fully upgraded."
	return ""


static func get_upgradable_cards(member: PartyMember) -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	for owned in member.deck:
		if can_upgrade(owned) == "":
			result.append(owned)
	return result


## Upgrades one specific card copy of a member. Returns "" on success or an error text.
static func upgrade(member: PartyMember, uid: String) -> String:
	var owned := member.find_card(uid)
	if owned == null:
		return "That card is not in this character's deck."
	var reason := can_upgrade(owned)
	if reason == "":
		owned.upgrade_level += 1
	return reason
