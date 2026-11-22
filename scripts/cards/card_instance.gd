class_name CardInstance
extends RefCounted
## Runtime card used during one combat. Points at an immutable CardDef and carries
## per-card state (owner, upgrade level, temporary modifiers). Shuffling or modifying an
## instance never touches the definition or the character's persistent OwnedCard.

var instance_id: int = 0
var owned_uid: String = ""
var definition: CardDef
var owner_character_id: String = ""
var upgrade_level: int = 0
## Temporary combat-only cost change (future card effects can set this).
var cost_modifier: int = 0


static func from_owned(owned: OwnedCard, def: CardDef, p_instance_id: int) -> CardInstance:
	var card := CardInstance.new()
	card.instance_id = p_instance_id
	card.owned_uid = owned.uid
	card.definition = def
	card.owner_character_id = owned.owner_character_id
	card.upgrade_level = owned.upgrade_level
	return card


func is_upgraded() -> bool:
	return upgrade_level > 0


func get_card_name() -> String:
	if is_upgraded() and definition.upgrade.has("name"):
		return str(definition.upgrade["name"])
	return definition.display_name


## X-cost cards always cost 0 to start: playing them spends whatever Energy is left.
func get_cost() -> int:
	if definition.x_cost:
		return 0
	var base := definition.cost
	if is_upgraded() and definition.upgrade.has("cost"):
		base = int(definition.upgrade["cost"])
	return maxi(0, base + cost_modifier)


## Keywords an upgrade may change ("retain": true, "exhaust": false in the upgrade block).
func retains() -> bool:
	if is_upgraded() and definition.upgrade.has("retain"):
		return bool(definition.upgrade["retain"])
	return definition.retain


func exhausts() -> bool:
	if definition.card_type == CardDef.TYPE_POWER:
		return true
	if is_upgraded() and definition.upgrade.has("exhaust"):
		return bool(definition.upgrade["exhaust"])
	return definition.exhausts


## Effects to resolve. Upgrades with no effect list yet fall back to the base effects.
func get_effects() -> Array:
	if is_upgraded():
		var upgraded: Array = definition.upgrade.get("effects", [])
		if not upgraded.is_empty():
			return upgraded.duplicate(true)
	return definition.effects.duplicate(true)


func get_description() -> String:
	if is_upgraded() and not (definition.upgrade.get("effects", []) as Array).is_empty():
		return str(definition.upgrade.get("description", definition.description))
	return definition.description
