class_name Reactions
extends RefCounted
## Twin reactions (data/combat/reactions.json): when a party member's hit of one element lands on an
## enemy carrying a status from the other sister, an extra effect follows (Fire + Poison =
## Combustion, Wind + Poison = Miasma...). Pure rules: CombatManager.hit calls try_react after the
## hit; the presentation reads the "reaction" visual event. Reaction damage never sets off another
## reaction, and status ticks never react (they do not go through CombatManager.hit).

const PATH := "res://data/combat/reactions.json"

static var _list: Array = []
static var _loaded: bool = false


static func all() -> Array:
	if not _loaded:
		reload()
	return _list


static func reload() -> void:
	_loaded = true
	_list = []
	if not FileAccess.file_exists(PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary:
		_list = (data as Dictionary).get("reactions", [])


static func get_reaction(reaction_id: String) -> Dictionary:
	for reaction: Dictionary in all():
		if str(reaction.get("id", "")) == reaction_id:
			return reaction
	return {}


## Reactions designed for one Chiara + Bianca pairing (for the combo guide).
static func for_pair(chiara_spec: String, bianca_spec: String) -> Array:
	return all().filter(func(r: Dictionary) -> bool:
		var pair: Array = r.get("pair", [])
		return pair.size() == 2 and str(pair[0]) == chiara_spec and str(pair[1]) == bianca_spec)


## Checks every reaction for a hit of `element` by `source` on `target` and resolves the matches.
## Returns how many reactions went off.
static func try_react(combat: CombatManager, source: Combatant, target: Combatant, element: String) -> int:
	if source == null or source.side != Combatant.SIDE_PARTY or target == null or not target.is_alive():
		return 0
	var fired := 0
	for reaction: Dictionary in all():
		if str(reaction.get("element", "")) != element:
			continue
		var status_id := str(reaction.get("status_id", ""))
		if not target.has_status(status_id):
			continue
		var stacks := int(target.statuses[status_id]["stacks"])
		if stacks <= 0:
			continue
		_resolve(combat, reaction, source, target, status_id, stacks)
		fired += 1
		if not target.is_alive():
			break
	return fired


static func _resolve(combat: CombatManager, reaction: Dictionary, source: Combatant, target: Combatant, status_id: String, stacks: int) -> void:
	var reaction_name := str(reaction.get("name", reaction.get("id", "")))
	var affected: Array[String] = [target.id]
	match str(reaction.get("effect", "")):
		"detonate":
			target.statuses.erase(status_id)
			var amount := stacks * int(reaction.get("per_stack", 1))
			var victims: Array[Combatant] = [target]
			if str(reaction.get("scope", "")) == "all_enemies":
				victims = combat.get_living_enemies()
			affected.clear()
			for victim in victims:
				var lost := combat.hit(victim, amount, str(reaction.get("damage_element", element_of(reaction))), source)
				affected.append(victim.id)
				combat.say("%s! %s takes %d (%d lost)." % [reaction_name, victim.display_name, amount, lost])
		"spread":
			var share := maxi(1, ceili(stacks * float(reaction.get("ratio", 0.5))))
			for other in combat.get_living_enemies():
				if other != target:
					other.add_status(status_id, share, source.id)
					affected.append(other.id)
			combat.say("%s! The %s spreads to every other enemy (+%d)." % [reaction_name, _status_name(status_id), share])
		"add_status":
			var add_id := str(reaction.get("add_status_id", status_id))
			var value := int(reaction.get("value", 1))
			target.add_status(add_id, value, source.id)
			combat.say("%s! %s gains %d %s." % [reaction_name, target.display_name, value, _status_name(add_id)])
		"shatter":
			target.statuses.erase(status_id)
			var shatter := stacks * int(reaction.get("per_stack", 1))
			var lost_hp := combat.hit(target, shatter, str(reaction.get("damage_element", element_of(reaction))), source)
			combat.say("%s! %s takes %d (%d lost)." % [reaction_name, target.display_name, shatter, lost_hp])
		"block_source":
			var block := stacks * int(reaction.get("per_stack", 1))
			source.add_block(block)
			affected = [source.id]
			combat.say("%s! %s gains %d Block." % [reaction_name, source.display_name, block])
	combat.reactions_fired += 1
	combat.visual_event.emit({"kind": "reaction", "card_id": "", "specialization_id": "", "source_id": source.id,
		"target_ids": affected, "target_group": "", "reaction_id": str(reaction.get("id", "")), "reaction_name": reaction_name,
		"status_id": status_id, "color": str(reaction.get("color", "#ffffff"))})


static func element_of(reaction: Dictionary) -> String:
	return str(reaction.get("element", DamageTypes.PHYSICAL))


static func _status_name(status_id: String) -> String:
	var def := DataRegistry.get_status(status_id)
	return def.display_name if def != null else status_id.capitalize()
