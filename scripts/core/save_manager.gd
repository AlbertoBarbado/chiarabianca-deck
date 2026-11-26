class_name SaveManager
extends RefCounted
## Serialises and restores a run (party, decks, upgrades, inventory, map position) as JSON in
## user:// (Godot's per-user persistent storage; works on desktop and mobile).
##
## Static content (stats, card definitions) is NOT saved, only references to it by id, so
## balance changes apply to old saves. Restoring validates everything and never trusts the file:
## unknown ids are dropped with a warning, numbers are clamped, and unusable saves are rejected
## with an error message instead of crashing.
##
## Version 3 (persistent campaign, docs/PERSISTENT_RPG_DESIGN.md §7) keeps the run payload below at the
## top level (it is the expedition, or a Quick Play run) and adds:
##   "mode": "campaign" | "classic", "campaign": CampaignState.to_dict() (campaign mode only),
##   "expedition": ExpeditionState.to_dict() (while an expedition is under way).
## A campaign at the castle has no run payload ("party" is absent). The map block may carry
## "map_def" / "layout_def" for rerolled or generated expedition maps. GameState decides the mode;
## restore() below only rebuilds the run payload, exactly as before.

const SAVE_VERSION := 3
## Room kinds a save may resume (anything else is dropped and the run resumes on the map).
const ROOM_KINDS := ["combat", "elite", "rest", "merchant", "event", "treasure", "town", "boss"]


static func serialize(party: Party, inventory: Inventory, progress: MapProgress, room_state: Dictionary = {}, pending_reward: CardReward = null, flags: Dictionary = {}) -> Dictionary:
	var members: Array = []
	for member in party.members:
		members.append(serialize_member(member))
	var map_block := {
		"map_id": progress.graph.id,
		"current_node_id": progress.current_node_id,
		"visited": progress.visited_ids.duplicate(),
	}
	if not progress.graph.custom_def.is_empty():
		map_block["map_def"] = progress.graph.custom_def.duplicate(true)
		map_block["layout_def"] = progress.graph.custom_layout.duplicate(true)
	return {
		"version": SAVE_VERSION,
		"party": members,
		"inventory": serialize_inventory(inventory),
		"room": room_state.duplicate(true),
		"flags": flags.duplicate(true),
		"reward": pending_reward.to_dict() if pending_reward != null else {},
		"map": map_block,
	}


## One party member (also used for the campaign roster, whose deck is the card collection).
static func serialize_member(member: PartyMember) -> Dictionary:
	var deck: Array = []
	for owned in member.deck:
		deck.append({"uid": owned.uid, "card_id": owned.card_id, "upgrade_level": owned.upgrade_level})
	var entry := {
		"character_id": member.id,
		"specialization_id": member.specialization.id,
		"current_hp": member.current_hp,
		"next_card_serial": member.next_card_serial,
		"deck": deck,
		"equipment": member.equipment.duplicate(),
	}
	if member.level_max_hp > 0:
		entry["level_max_hp"] = member.level_max_hp
	if member.secondary_specialization != null:
		entry["secondary_specialization_id"] = member.secondary_specialization.id
	return entry


static func serialize_inventory(inventory: Inventory) -> Dictionary:
	return {"gold": inventory.gold, "items": inventory.items.duplicate(), "relics": inventory.relics.duplicate(), "equipment": inventory.equipment.duplicate()}


## Validates and rebuilds runtime objects from save data.
## Returns {ok, error, warnings, party, inventory, progress}.
static func restore(data: Variant) -> Dictionary:
	var result := {"ok": false, "error": "", "warnings": [] as Array[String], "party": null, "inventory": null, "progress": null, "room": {}, "reward": null, "flags": {}}
	if not data is Dictionary:
		result["error"] = "Save file is not valid."
		return result
	var save: Dictionary = _migrate(data)
	if int(save.get("version", 0)) > SAVE_VERSION:
		result["error"] = "Save was made by a newer version of the game."
		return result
	var warnings: Array[String] = result["warnings"]

	# Relic Max HP must be known before HP is restored (a saved 70 / 70 with the Royal Pear is not clamped to 64).
	var raw_inventory: Variant = save.get("inventory", {})
	var saved_relics: Array = (raw_inventory as Dictionary).get("relics", []) if raw_inventory is Dictionary and (raw_inventory as Dictionary).get("relics", []) is Array else []
	var party := restore_party(save.get("party", []), warnings, result, RelicEffects.stat_for(saved_relics, "max_hp"))
	if party == null:
		return result
	var inventory := restore_inventory(save.get("inventory", {}), warnings)
	var progress := _restore_map(save.get("map", {}), warnings, result)
	if progress == null:
		return result
	result["room"] = _restore_room(save.get("room", {}), progress, warnings)
	result["reward"] = _restore_reward(save.get("reward", {}), result["room"], party)
	result["flags"] = _restore_flags(save.get("flags", {}))
	result["ok"] = true
	result["party"] = party
	result["inventory"] = inventory
	result["progress"] = progress
	return result


## Upgrades older save layouts to the current one. Version 0 means the "version" field is
## missing; version 1 had no room state, relics or pending reward (they default to empty/none).
static func _migrate(save: Dictionary) -> Dictionary:
	var migrated := save.duplicate(true)
	if not migrated.has("version"):
		migrated["version"] = 0
	if int(migrated["version"]) < 1:
		migrated["version"] = 1
	if int(migrated["version"]) < 2:
		migrated["version"] = 2
		migrated["room"] = {}
		migrated["reward"] = {}
	if int(migrated["version"]) < 3:
		migrated["version"] = 3  # v3 only adds optional blocks (campaign, expedition, map_def).
	return migrated


static func restore_party(raw_members: Variant, warnings: Array[String], result: Dictionary, relic_max_hp: int = 0) -> Party:
	if not raw_members is Array or (raw_members as Array).is_empty():
		result["error"] = "Save has no party."
		return null
	var party := Party.new()
	for raw: Variant in raw_members:
		if not raw is Dictionary:
			warnings.append("Skipped a malformed party entry.")
			continue
		var entry: Dictionary = raw
		var char_def := DataRegistry.get_character(str(entry.get("character_id", "")))
		var spec_def := DataRegistry.get_specialization(str(entry.get("specialization_id", "")))
		if char_def == null:
			warnings.append("Skipped unknown character '%s'." % entry.get("character_id", ""))
			continue
		if spec_def == null or spec_def.character_id != char_def.id:
			result["error"] = "Save has an invalid specialization for %s." % char_def.display_name
			return null
		var member := PartyMember.new()
		member.definition = char_def
		member.specialization = spec_def
		member.next_card_serial = maxi(1, int(entry.get("next_card_serial", 1)))
		var secondary := DataRegistry.get_specialization(str(entry.get("secondary_specialization_id", "")))
		if secondary != null and secondary.character_id == char_def.id and secondary.id != spec_def.id and secondary.is_playable():
			member.secondary_specialization = secondary
		elif str(entry.get("secondary_specialization_id", "")) != "":
			warnings.append("Dropped an unusable secondary specialization of %s." % char_def.display_name)
		_restore_equipment(member, entry.get("equipment", {}), warnings)
		member.level_max_hp = maxi(0, int(entry.get("level_max_hp", 0)))
		member.extra_max_hp = relic_max_hp + member.level_max_hp
		member.max_hp = maxi(1, char_def.max_hp + int(Equipment.totals(member)["max_hp"]) + member.extra_max_hp)
		member.current_hp = clampi(int(entry.get("current_hp", member.max_hp)), 0, member.max_hp)
		_restore_deck(member, entry.get("deck", []), warnings)
		party.members.append(member)
	if party.members.is_empty():
		result["error"] = "Save contains no usable party members."
		return null
	return party


## Worn items: only known equipment the member may wear, in a slot it fits.
static func _restore_equipment(member: PartyMember, raw: Variant, warnings: Array[String]) -> void:
	if not raw is Dictionary:
		return
	for slot: Variant in raw:
		var item_id := str((raw as Dictionary)[slot])
		if Equipment.can_equip(member, item_id) != "" or not Equipment.slots_for(item_id).has(str(slot)):
			warnings.append("Dropped unusable equipment '%s' from %s." % [item_id, member.definition.display_name])
			continue
		member.equipment[str(slot)] = item_id


static func _restore_deck(member: PartyMember, raw_deck: Variant, warnings: Array[String]) -> void:
	if raw_deck is Array:
		for raw: Variant in raw_deck:
			if not raw is Dictionary:
				continue
			var card_id := str((raw as Dictionary).get("card_id", ""))
			var def := DataRegistry.get_card(card_id)
			if def == null:
				warnings.append("Dropped unknown card '%s'." % card_id)
				continue
			# Keep the saved uid when usable; otherwise mint a fresh unique one (add_card), so
			# missing or duplicated uids in the file cannot cause conflicts.
			var uid := str((raw as Dictionary).get("uid", ""))
			var owned: OwnedCard
			if uid != "" and member.find_card(uid) == null:
				owned = OwnedCard.create(uid, card_id, member.id)
				member.deck.append(owned)
			else:
				owned = member.add_card(card_id)
			owned.upgrade_level = clampi(int((raw as Dictionary).get("upgrade_level", 0)), 0, maxi(CardUpgrader.get_max_level(def), 0))
	if member.deck.is_empty():
		warnings.append("%s had no valid cards; starting deck restored." % member.definition.display_name)
		for card_id in member.specialization.starting_deck_card_ids:
			member.add_card(card_id)


static func restore_inventory(raw: Variant, warnings: Array[String]) -> Inventory:
	var inventory := Inventory.new()
	var data: Dictionary = raw if raw is Dictionary else {}
	inventory.gold = maxi(0, int(data.get("gold", 0)))
	var raw_relics: Variant = data.get("relics", [])
	if raw_relics is Array:
		for relic_id: Variant in raw_relics:
			if DataRegistry.get_item(str(relic_id)).is_empty():
				warnings.append("Dropped unknown relic '%s'." % relic_id)
			elif not inventory.relics.has(str(relic_id)):
				inventory.relics.append(str(relic_id))
	var raw_equipment: Variant = data.get("equipment", [])
	if raw_equipment is Array:
		for item_id: Variant in raw_equipment:
			if not inventory.add_equipment(str(item_id)):
				warnings.append("Dropped unknown equipment '%s'." % item_id)
	var items: Dictionary = data.get("items", {}) if data.get("items", {}) is Dictionary else {}
	for item_id: String in items:
		if DataRegistry.get_item(item_id).is_empty():
			warnings.append("Dropped unknown item '%s'." % item_id)
		elif int(items[item_id]) > 0:
			inventory.items[item_id] = int(items[item_id])
	return inventory


## Counters in the run flags (non-negative integers): shop services used this run, which set the
## rising prices of card removal and upgrades.
const COUNTER_FLAGS := ["shop_removals", "shop_upgrades"]


## Run flags: only known keys are kept (lists of strings, and the counters above).
static func _restore_flags(raw: Variant) -> Dictionary:
	var flags: Dictionary = {}
	if raw is Dictionary:
		for key: String in COUNTER_FLAGS:
			var value: Variant = (raw as Dictionary).get(key, 0)
			if (value is int or value is float) and int(value) > 0:
				flags[key] = int(value)
		for key in ["seen_events", "completed_maps"]:
			var cleaned: Array = []
			if (raw as Dictionary).get(key, []) is Array:
				for entry: Variant in (raw as Dictionary).get(key, []):
					if not cleaned.has(str(entry)):
						cleaned.append(str(entry))
			if not cleaned.is_empty():
				flags[key] = cleaned
	return flags


## A saved room is only kept when it names the node the party stands on and a known kind.
static func _restore_room(raw: Variant, progress: MapProgress, warnings: Array[String]) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var room: Dictionary = (raw as Dictionary).duplicate(true)
	if str(room.get("node_id", "")) != progress.current_node_id or not ROOM_KINDS.has(str(room.get("kind", ""))):
		warnings.append("Dropped an unusable room state; resuming on the map.")
		return {}
	return room


## The pending reward only exists in the "reward" phase of a combat room.
static func _restore_reward(raw: Variant, room: Dictionary, party: Party) -> CardReward:
	if str(room.get("phase", "")) != "reward":
		return null
	var reward := CardReward.from_dict(raw, party)
	return reward if not reward.options.is_empty() and not reward.resolved else null


static func _restore_map(raw: Variant, warnings: Array[String], result: Dictionary) -> MapProgress:
	var data: Dictionary = raw if raw is Dictionary else {}
	var map_id := str(data.get("map_id", GameConfig.DEFAULT_MAP_ID))
	var map_def := DataRegistry.get_map(map_id)
	var custom: Dictionary = data.get("map_def", {}) if data.get("map_def", {}) is Dictionary else {}
	if not custom.is_empty():
		# An expedition map (rerolled or generated): rebuilt from the saved definition when it is sound.
		if not MapGraph.from_dict(custom).validate().is_empty() or _unknown_content(custom):
			result["error"] = "The saved expedition map is damaged."
			return null
		map_def = custom
	if map_def.is_empty():
		result["error"] = "Save refers to an unknown map '%s'." % map_id
		return null
	var graph := MapGraph.from_dict(map_def)
	if not custom.is_empty():
		graph.custom_def = custom
		graph.custom_layout = data.get("layout_def", {}) if data.get("layout_def", {}) is Dictionary else {}
		if not graph.custom_layout.is_empty():
			DataRegistry.layouts[graph.id] = graph.custom_layout
	var progress := MapProgress.new(graph)
	var visited: Array[String] = []
	var raw_visited: Variant = data.get("visited", [])
	if raw_visited is Array:
		for node_id: Variant in raw_visited:
			visited.append(str(node_id))
	if not progress.restore(str(data.get("current_node_id", "")), visited):
		result["error"] = "Save has an invalid map position."
		return null
	return progress


## A saved custom map naming encounters, towns, shops or chests that no longer exist.
static func _unknown_content(map_def: Dictionary) -> bool:
	for node: Variant in map_def.get("nodes", []):
		if not node is Dictionary:
			return true
		var n: Dictionary = node
		if str(n.get("encounter_id", "")) != "" and DataRegistry.get_encounter(str(n["encounter_id"])).is_empty():
			return true
		if str(n.get("town_id", "")) != "" and DataRegistry.get_town(str(n["town_id"])).is_empty():
			return true
		if str(n.get("shop_id", "")) != "" and DataRegistry.get_shop(str(n["shop_id"])).is_empty():
			return true
		if str(n.get("treasure_id", "")) != "" and DataRegistry.get_treasure(str(n["treasure_id"])).is_empty():
			return true
	return false


# --- File access -------------------------------------------------------------

## Writes via a temporary file so a crash mid-save cannot corrupt the existing save.
static func write_file(path: String, data: Dictionary) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % temp_path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		# Keep the previous good save as a backup, so a damaged main file can be recovered.
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK


## Returns {ok: bool, data: Variant, error: String}.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "No saved game found."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": null, "error": "Could not open the save file."}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		# Damaged main file: try the backup before giving up. The damaged file is left in place.
		var backup: Variant = _read_backup(path)
		if backup is Dictionary:
			return {"ok": true, "data": backup, "error": "", "from_backup": true}
		return {"ok": false, "data": null, "error": "Save file is corrupt."}
	return {"ok": true, "data": parsed, "error": "", "from_backup": false}


static func _read_backup(path: String) -> Variant:
	if not FileAccess.file_exists(path + ".bak"):
		return null
	var file := FileAccess.open(path + ".bak", FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else null
