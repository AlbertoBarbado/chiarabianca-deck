class_name DataRegistry
extends RefCounted
## Loads and caches every static definition from res://data (JSON files).
## Definitions are read-only: runtime systems create instances from them and never edit them.
## Add content by dropping JSON files into the matching data/ subfolder.

const DATA_ROOT := "res://data"

static var _loaded: bool = false
static var characters: Dictionary = {}       # id -> CharacterDef
static var specializations: Dictionary = {}  # id -> SpecializationDef
static var cards: Dictionary = {}            # id -> CardDef
static var enemies: Dictionary = {}          # id -> EnemyDef
static var encounters: Dictionary = {}       # id -> Dictionary
static var items: Dictionary = {}            # id -> Dictionary
static var events: Dictionary = {}           # id -> Dictionary
static var shops: Dictionary = {}            # id -> Dictionary
static var maps: Dictionary = {}             # id -> Dictionary
static var layouts: Dictionary = {}          # map id -> Dictionary (presentation layouts, see MapLayout)
static var statuses: Dictionary = {}         # id -> StatusDef
static var treasures: Dictionary = {}        # id -> Dictionary (treasure room definitions)
static var towns: Dictionary = {}            # id -> Dictionary (town definitions: services, shop, rest)


static func ensure_loaded() -> void:
	if not _loaded:
		reload()


static func reload() -> void:
	for registry: Dictionary in [characters, specializations, cards, enemies, encounters, items, events, shops, maps, layouts, statuses, treasures, towns]:
		registry.clear()
	for entry in _read_entries("characters"):
		var char_def := CharacterDef.from_dict(entry)
		characters[char_def.id] = char_def
	for entry in _read_entries("specializations"):
		var spec_def := SpecializationDef.from_dict(entry)
		specializations[spec_def.id] = spec_def
	for entry in _read_entries("cards"):
		var card_def := CardDef.from_dict(entry)
		cards[card_def.id] = card_def
	for entry in _read_entries("enemies"):
		var enemy_def := EnemyDef.from_dict(entry)
		enemies[enemy_def.id] = enemy_def
	for entry in _read_entries("encounters"):
		encounters[str(entry["id"])] = entry
	for entry in _read_entries("items"):
		items[str(entry["id"])] = entry
	for entry in _read_entries("events"):
		events[str(entry["id"])] = entry
	for entry in _read_entries("shops"):
		shops[str(entry["id"])] = entry
	for entry in _read_entries("maps"):
		if entry.has("layout_for"):  # Presentation layout stored beside the graphs; not a map.
			layouts[str(entry["layout_for"])] = entry
		else:
			maps[str(entry["id"])] = entry
	for entry in _read_entries("towns"):
		towns[str(entry["id"])] = entry
	for entry in _read_entries("treasure"):
		treasures[str(entry["id"])] = entry
	for entry in _read_entries("statuses"):
		var status_def := StatusDef.from_dict(entry)
		statuses[status_def.id] = status_def
	_loaded = true


## Number of loaded definitions per category (used by tests and diagnostics).
static func counts() -> Dictionary:
	ensure_loaded()
	return {
		"characters": characters.size(), "specializations": specializations.size(),
		"cards": cards.size(), "enemies": enemies.size(), "encounters": encounters.size(),
		"items": items.size(), "events": events.size(), "shops": shops.size(), "maps": maps.size(), "statuses": statuses.size(),
	}


static func get_character(id: String) -> CharacterDef:
	ensure_loaded()
	return characters.get(id) as CharacterDef


static func get_specialization(id: String) -> SpecializationDef:
	ensure_loaded()
	return specializations.get(id) as SpecializationDef


static func get_card(id: String) -> CardDef:
	ensure_loaded()
	var def := cards.get(id) as CardDef
	if def == null:
		push_warning("DataRegistry: unknown card id '%s'" % id)
	return def


## Null for ids without a definition (callers fall back to the raw id).
static func get_status(id: String) -> StatusDef:
	ensure_loaded()
	return statuses.get(id) as StatusDef


static func get_enemy(id: String) -> EnemyDef:
	ensure_loaded()
	return enemies.get(id) as EnemyDef


static func get_encounter(id: String) -> Dictionary:
	ensure_loaded()
	return encounters.get(id, {})


static func get_item(id: String) -> Dictionary:
	ensure_loaded()
	return items.get(id, {})


static func get_event(id: String) -> Dictionary:
	ensure_loaded()
	return events.get(id, {})


static func get_town(id: String) -> Dictionary:
	ensure_loaded()
	return towns.get(id, {})


static func get_treasure(id: String) -> Dictionary:
	ensure_loaded()
	return treasures.get(id, {})


static func get_shop(id: String) -> Dictionary:
	ensure_loaded()
	return shops.get(id, {})


static func get_layout(map_id: String) -> Dictionary:
	ensure_loaded()
	return layouts.get(map_id, {})


static func get_map(id: String) -> Dictionary:
	ensure_loaded()
	return maps.get(id, {})


## Specializations of a character, in the order listed by the character definition.
static func get_specializations_for(character_id: String) -> Array[SpecializationDef]:
	ensure_loaded()
	var result: Array[SpecializationDef] = []
	var char_def := get_character(character_id)
	if char_def == null:
		return result
	for spec_id in char_def.specialization_ids:
		var spec := get_specialization(spec_id)
		if spec != null:
			result.append(spec)
	return result


static func read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataRegistry: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("DataRegistry: invalid JSON in %s" % path)
	return parsed


## Reads every *.json file of a data subfolder. Files may hold one object or an array.
## Schema templates (objects with "$schema_note") are skipped.
static func _read_entries(subdir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir_path := "%s/%s" % [DATA_ROOT, subdir]
	var files := DirAccess.get_files_at(dir_path)
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = read_json("%s/%s" % [dir_path, file_name])
		var entries: Array = parsed if parsed is Array else [parsed]
		for entry in entries:
			if entry is Dictionary and entry.has("id") and not entry.has("$schema_note"):
				result.append(entry)
	return result
