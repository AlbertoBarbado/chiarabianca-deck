class_name PartyMember
extends RefCounted
## Runtime state of one party character: health, chosen specialization and owned deck.

var definition: CharacterDef
var specialization: SpecializationDef
## Optional second specialization (campaign Training Hall): her deck may hold a few of its cards and
## its rewards appear at reduced weight. Only the primary specialization's passive runs. null = none.
var secondary_specialization: SpecializationDef = null
var current_hp: int = 1
var max_hp: int = 1
## Max HP from relics (RelicEffects.apply_stats); derived from the owned relics, never saved.
var extra_max_hp: int = 0
## The part of extra_max_hp that comes from the sister's campaign level (saved with the member).
var level_max_hp: int = 0
var deck: Array[OwnedCard] = []
## Counter used to mint unique owned-card uids (persisted by saves).
var next_card_serial: int = 1
## Worn equipment: slot (Equipment.SLOTS) -> item id. Max HP includes the worn items (Equipment.refresh_stats).
var equipment: Dictionary = {}

var id: String:
	get:
		return definition.id


static func create(char_def: CharacterDef, spec_def: SpecializationDef) -> PartyMember:
	var member := PartyMember.new()
	member.definition = char_def
	member.specialization = spec_def
	member.max_hp = char_def.max_hp
	member.current_hp = clampi(char_def.starting_hp, 0, char_def.max_hp)
	for card_id in spec_def.starting_deck_card_ids:
		member.add_card(card_id)
	return member


## Adds a new copy of a card to this character's deck. Every copy gets a unique uid, so
## several cards with the same card_id never conflict.
func add_card(card_id: String) -> OwnedCard:
	var uid := "%s_card_%d" % [id, next_card_serial]
	while find_card(uid) != null:
		next_card_serial += 1
		uid = "%s_card_%d" % [id, next_card_serial]
	next_card_serial += 1
	var owned := OwnedCard.create(uid, card_id, id)
	deck.append(owned)
	return owned


func find_card(uid: String) -> OwnedCard:
	for owned in deck:
		if owned.uid == uid:
			return owned
	return null


func remove_card(uid: String) -> bool:
	for i in deck.size():
		if deck[i].uid == uid:
			deck.remove_at(i)
			return true
	return false


func is_alive() -> bool:
	return current_hp > 0


func heal(amount: int) -> int:
	var before := current_hp
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	return current_hp - before


func revive(hp: int) -> void:
	if not is_alive():
		current_hp = clampi(hp, 1, max_hp)
