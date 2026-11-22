class_name Equipment
extends RefCounted
## Equipment rules (pure logic). Item definitions live in data/items/equipment.json with
## "category": "equipment"; owned but unworn items sit in Inventory.equipment (the party stash) and
## worn ones in PartyMember.equipment (slot -> item id).
##
## Item fields: id, name, slot (helmet, amulet, chest, gauntlets, weapon, belt, ring, boots),
## wielder (character id or "" for anyone), rarity, icon (res:// path), stats:
##   max_hp: int                 added to the wearer's maximum HP
##   resist: {element: percent}  less damage taken of that type (armour)
##   damage: {element: percent}  more damage dealt of that type (weapons)
##   immune: [status ids]        the wearer never gets these statuses (e.g. Soaked)
## specializations: [ids]          only a wearer with one of these specializations can use it ([] = any)
## effects: [passive]              in-battle effects of the wearer, in the PassiveRunner passive format
##                                 ({id, name, text, trigger, effect, limit_per_turn, limit_per_combat})
## A ring fits either ring slot. Stats are read when a combat starts (see CombatManager.setup).
## Drops, chests and shops only offer items somebody in the party can use (usable_by_party).

const SLOTS: Array[String] = ["helmet", "amulet", "chest", "gauntlets", "weapon", "belt", "ring_1", "ring_2", "boots"]
const SLOT_NAMES := {
	"helmet": "Helmet", "amulet": "Amulet", "chest": "Chest", "gauntlets": "Gauntlets", "weapon": "Weapon",
	"belt": "Belt", "ring_1": "Ring", "ring_2": "Ring", "boots": "Boots",
}
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic"]

## Blacksmith refinement levels (item id -> level) of the loaded campaign, applied to every copy of
## the item (CampaignState.refresh_roster sets it; {} in Quick Play). See refined_bonus.
static var refinement: Dictionary = {}


## Extra stats of an item at a refinement level: every stat the item already has grows by the
## campaign rules' per_level amounts ({} when the item has no refinable stats or level is 0).
static func refined_bonus(item_id: String, level: int) -> Dictionary:
	var bonus := {}
	if level <= 0:
		return bonus
	var per: Dictionary = CampaignRules.block("refinement").get("per_level", {})
	var stats: Dictionary = item(item_id).get("stats", {})
	if int(stats.get("max_hp", 0)) > 0:
		bonus["max_hp"] = int(per.get("max_hp", 0)) * level
	for key in ["resist", "damage"]:
		var bucket: Dictionary = stats.get(key, {})
		if bucket.is_empty():
			continue
		var grown := {}
		for element: String in bucket:
			grown[element] = int(per.get(key, 0)) * level
		bonus[key] = grown
	return bonus


static func refinement_level(item_id: String) -> int:
	return int(refinement.get(item_id, 0))


static func is_equipment(item_id: String) -> bool:
	return str(DataRegistry.get_item(item_id).get("category", "")) == "equipment"


static func item(item_id: String) -> Dictionary:
	return DataRegistry.get_item(item_id) if is_equipment(item_id) else {}


## Every equipment definition, in data order.
static func all_items() -> Array[Dictionary]:
	DataRegistry.ensure_loaded()
	var result: Array[Dictionary] = []
	for item_id: String in DataRegistry.items:
		var entry: Dictionary = DataRegistry.items[item_id]
		if str(entry.get("category", "")) == "equipment":
			result.append(entry)
	return result


## Slots an item can go into ("ring" fits both ring slots).
static func slots_for(item_id: String) -> Array[String]:
	var slot := str(item(item_id).get("slot", ""))
	var result: Array[String] = []
	if slot == "ring":
		result.assign(["ring_1", "ring_2"])
	elif SLOTS.has(slot):
		result.append(slot)
	return result


## "" when the member may wear the item, otherwise the reason.
static func can_equip(member: PartyMember, item_id: String) -> String:
	var def := item(item_id)
	if def.is_empty():
		return "Unknown item."
	if slots_for(item_id).is_empty():
		return "This item has no slot."
	var wielder := str(def.get("wielder", ""))
	if wielder != "" and wielder != member.id:
		var owner_def := DataRegistry.get_character(wielder)
		return "Only %s can use %s." % [owner_def.display_name if owner_def != null else wielder, def.get("name", item_id)]
	var specs: Array = def.get("specializations", [])
	if not specs.is_empty() and (member.specialization == null or not specs.has(member.specialization.id)):
		return "%s needs %s." % [def.get("name", item_id), " or ".join(specialization_names(item_id))]
	return ""


## True if this party member could wear the item (right princess and specialization).
static func usable_by(member: PartyMember, item_id: String) -> bool:
	return member != null and can_equip(member, item_id) == ""


## True if somebody in the party could wear the item: the rule for drops, chests and shops.
static func usable_by_party(party: Party, item_id: String) -> bool:
	if party == null:
		return true
	for member in party.members:
		if usable_by(member, item_id):
			return true
	return false


## Display names of the specializations an item asks for ("Fire", "Ashveil"...); empty = any.
static func specialization_names(item_id: String) -> Array[String]:
	var names: Array[String] = []
	for spec_id: Variant in item(item_id).get("specializations", []):
		var spec := DataRegistry.get_specialization(str(spec_id))
		names.append(spec.display_name if spec != null else str(spec_id).capitalize())
	return names


## The in-battle passives of everything the member wears (see PassiveRunner). Each gets a unique id
## ("item_id#index") and the item's name, so its log lines read "Ember Crown: ...".
static func passives(member: PartyMember) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if member == null:
		return result
	for slot: String in SLOTS:
		var item_id := str(member.equipment.get(slot, ""))
		if item_id == "":
			continue
		var effects: Array = item(item_id).get("effects", [])
		for i in effects.size():
			var passive: Dictionary = (effects[i] as Dictionary).duplicate(true)
			if not passive.has("trigger") or not passive.has("effect"):
				continue
			passive["id"] = "%s@%s#%d" % [item_id, slot, i]
			passive["name"] = str(item(item_id).get("name", item_id))
			result.append(passive)
	return result


## Player-facing effect lines of an item ("At the start of each battle, draw 2 extra cards.").
static func effect_lines(item_id: String) -> Array[String]:
	var lines: Array[String] = []
	for effect: Variant in item(item_id).get("effects", []):
		var text := str((effect as Dictionary).get("text", ""))
		if text != "":
			lines.append(text)
	return lines


## Moves an item from the stash onto the member (into `slot`, or the first free / first fitting slot).
## Whatever was in that slot goes back to the stash. Returns "" or the reason it failed.
static func equip(member: PartyMember, inventory: Inventory, item_id: String, slot: String = "") -> String:
	var reason := can_equip(member, item_id)
	if reason != "":
		return reason
	if not inventory.equipment.has(item_id):
		return "That item is not in the stash."
	var fitting := slots_for(item_id)
	if slot == "":
		slot = fitting[0]
		for candidate in fitting:
			if str(member.equipment.get(candidate, "")) == "":
				slot = candidate
				break
	elif not fitting.has(slot):
		return "It does not fit that slot."
	inventory.equipment.erase(item_id)
	var previous := str(member.equipment.get(slot, ""))
	if previous != "":
		inventory.equipment.append(previous)
	member.equipment[slot] = item_id
	refresh_stats(member)
	inventory.changed.emit()
	return ""


static func unequip(member: PartyMember, inventory: Inventory, slot: String) -> bool:
	var item_id := str(member.equipment.get(slot, ""))
	if item_id == "":
		return false
	member.equipment.erase(slot)
	inventory.equipment.append(item_id)
	refresh_stats(member)
	inventory.changed.emit()
	return true


## Moves a worn item to another slot of the same member (only between slots it fits: the two ring
## slots). Whatever was in the target slot takes the source slot (a swap). Returns "" or the reason.
static func move_worn(member: PartyMember, from_slot: String, to_slot: String) -> String:
	var item_id := str(member.equipment.get(from_slot, ""))
	if item_id == "":
		return "That slot is empty."
	if from_slot == to_slot:
		return ""
	if not slots_for(item_id).has(to_slot):
		return "It does not fit that slot."
	var other := str(member.equipment.get(to_slot, ""))
	member.equipment[to_slot] = item_id
	if other != "":
		member.equipment[from_slot] = other
	else:
		member.equipment.erase(from_slot)
	return ""


## Stat change if `item_id` replaced what the member wears in `slot`: {key: delta} with keys like
## "max_hp", "damage:fire", "resist:frost" (only non-zero deltas). Used to compare items.
static func compare(member: PartyMember, item_id: String, slot: String) -> Dictionary:
	var result := {}
	var before := _flat_stats(str(member.equipment.get(slot, "")) if member != null else "")
	var after := _flat_stats(item_id)
	for key: String in before.keys() + after.keys():
		var delta := int(after.get(key, 0)) - int(before.get(key, 0))
		if delta != 0:
			result[key] = delta
	return result


static func _flat_stats(item_id: String) -> Dictionary:
	var flat := {}
	var stats: Dictionary = item(item_id).get("stats", {})
	if int(stats.get("max_hp", 0)) != 0:
		flat["max_hp"] = int(stats["max_hp"])
	for key in ["damage", "resist"]:
		var bucket: Dictionary = stats.get(key, {})
		for element: String in bucket:
			flat["%s:%s" % [key, element]] = int(bucket[element])
	return flat


## Player-facing text for one compare() key, e.g. "+15% Fire damage".
static func describe_delta(key: String, delta: int) -> String:
	if key == "max_hp":
		return "%+d Max HP" % delta
	var parts := key.split(":")
	var element := DamageTypes.display_name(parts[1]) if parts.size() > 1 else key
	return ("%+d%% %s damage" if parts[0] == "damage" else "%+d%% %s resistance") % [delta, element]


## Sum of the worn items' stats: {max_hp: int, resist: {element: pct}, damage: {element: pct}}.
static func totals(member: PartyMember) -> Dictionary:
	var result := {"max_hp": 0, "resist": {}, "damage": {}, "immune": []}
	if member == null:
		return result
	for slot: String in member.equipment:
		var stats: Dictionary = item(str(member.equipment[slot])).get("stats", {})
		var bonus := refined_bonus(str(member.equipment[slot]), refinement_level(str(member.equipment[slot])))
		result["max_hp"] = int(result["max_hp"]) + int(stats.get("max_hp", 0)) + int(bonus.get("max_hp", 0))
		for key in ["resist", "damage"]:
			var extra: Dictionary = bonus.get(key, {})
			for element: String in extra:
				(result[key] as Dictionary)[element] = int((result[key] as Dictionary).get(element, 0)) + int(extra[element])
		for status_id: Variant in stats.get("immune", []):
			if not (result["immune"] as Array).has(str(status_id)):
				(result["immune"] as Array).append(str(status_id))
		for key in ["resist", "damage"]:
			var bucket: Dictionary = result[key]
			var add: Dictionary = stats.get(key, {})
			for element: String in add:
				bucket[element] = int(bucket.get(element, 0)) + int(add[element])
	return result


## Re-applies the worn items' Max HP: raising the maximum also raises current HP by the same amount;
## lowering it only clamps current HP (taking armour off never kills; a fallen member stays at 0).
static func refresh_stats(member: PartyMember) -> void:
	var new_max := member.definition.max_hp + int(totals(member)["max_hp"]) + member.extra_max_hp
	var difference := new_max - member.max_hp
	member.max_hp = maxi(1, new_max)
	if difference > 0 and member.current_hp > 0:
		member.current_hp += difference
	member.current_hp = clampi(member.current_hp, 0, member.max_hp)


## Player-facing stat lines, e.g. ["+15% Fire damage", "Fire resistance 25%", "+4 Max HP"].
static func stat_lines(item_id: String) -> Array[String]:
	var stats: Dictionary = item(item_id).get("stats", {})
	var lines: Array[String] = []
	for element: String in stats.get("damage", {}):
		lines.append("+%d%% %s damage" % [int(stats["damage"][element]), DamageTypes.display_name(element)])
	for element: String in stats.get("resist", {}):
		lines.append("%s resistance %d%%" % [DamageTypes.display_name(element), int(stats["resist"][element])])
	if int(stats.get("max_hp", 0)) != 0:
		lines.append("%+d Max HP" % int(stats["max_hp"]))
	for status_id: Variant in stats.get("immune", []):
		var status_def := DataRegistry.get_status(str(status_id))
		lines.append("Immune to %s" % (status_def.display_name if status_def != null else str(status_id).capitalize()))
	for text in effect_lines(item_id):
		lines.append("✦ " + text)
	var specs := specialization_names(item_id)
	if not specs.is_empty():
		lines.append("Needs %s" % " or ".join(specs))
	return lines


static func icon(item_id: String) -> Texture2D:
	var path := str(item(item_id).get("icon", ""))
	return load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null


static func rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return Color("6fd3ff")
		"rare":
			return Color("f2c14e")
		"epic":
			return Color("c58bff")
	return Color("d8d2c4")
