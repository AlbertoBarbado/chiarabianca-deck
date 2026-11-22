class_name Party
extends RefCounted
## The player's party: an ordered list of PartyMember objects. Supports any party size.

signal changed

var members: Array[PartyMember] = []


## Builds a party from {character_id: specialization_id}. Skips unknown ids.
static func from_selection(selection: Dictionary, order: Array[String] = GameConfig.INITIAL_PARTY_IDS) -> Party:
	var party := Party.new()
	for character_id in order:
		var char_def := DataRegistry.get_character(character_id)
		var spec_def := DataRegistry.get_specialization(str(selection.get(character_id, "")))
		if char_def == null or spec_def == null or spec_def.character_id != character_id:
			push_warning("Party: invalid selection for '%s'" % character_id)
			continue
		party.add_member(PartyMember.create(char_def, spec_def))
	return party


func add_member(member: PartyMember) -> void:
	members.append(member)
	changed.emit()


func remove_member(character_id: String) -> void:
	var member := get_member(character_id)
	if member != null:
		members.erase(member)
		changed.emit()


func get_member(character_id: String) -> PartyMember:
	for member in members:
		if member.id == character_id:
			return member
	return null


func get_living_members() -> Array[PartyMember]:
	var living: Array[PartyMember] = []
	for member in members:
		if member.is_alive():
			living.append(member)
	return living


func is_wiped() -> bool:
	return get_living_members().is_empty()


func get_total_deck_size() -> int:
	var total := 0
	for member in members:
		total += member.deck.size()
	return total


## Heals every living member by a fraction of max HP. Returns {character_id: hp_restored}.
func rest(fraction: float) -> Dictionary:
	var restored: Dictionary = {}
	for member in members:
		if member.is_alive():
			restored[member.id] = member.heal(ceili(member.max_hp * fraction))
	changed.emit()
	return restored


func revive_fallen(hp: int) -> void:
	for member in members:
		member.revive(hp)
	changed.emit()
