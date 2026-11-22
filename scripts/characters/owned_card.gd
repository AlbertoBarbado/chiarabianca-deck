class_name OwnedCard
extends RefCounted
## A card in a character's persistent (out-of-combat) deck.
## Holds permanent ownership and upgrade progress; combat copies it into a CardInstance.

var uid: String = ""
var card_id: String = ""
var owner_character_id: String = ""
var upgrade_level: int = 0


static func create(p_uid: String, p_card_id: String, p_owner_id: String) -> OwnedCard:
	var owned := OwnedCard.new()
	owned.uid = p_uid
	owned.card_id = p_card_id
	owned.owner_character_id = p_owner_id
	return owned
