class_name TwinCombos
extends RefCounted
## The combo guide (data/combat/twin_combos.json): what each Chiara x Bianca specialization pairing
## does together and how strong it is. Presentation and design reference only; the rules themselves
## live in cards, statuses, passives and data/combat/reactions.json.

const PATH := "res://data/combat/twin_combos.json"
const STAR := "★"

static var _list: Array = []
static var _loaded: bool = false


static func all() -> Array:
	if not _loaded:
		_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_list = (data as Dictionary).get("combos", []) if data is Dictionary else []
	return _list


static func for_pair(chiara_spec: String, bianca_spec: String) -> Dictionary:
	for combo: Dictionary in all():
		if str(combo.get("chiara", "")) == chiara_spec and str(combo.get("bianca", "")) == bianca_spec:
			return combo
	return {}


## Combos one specialization takes part in, strongest first.
static func for_spec(spec_id: String) -> Array:
	var found := all().filter(func(c: Dictionary) -> bool: return str(c.get("chiara", "")) == spec_id or str(c.get("bianca", "")) == spec_id)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("strength", 0)) > int(b.get("strength", 0)))
	return found


## "★★★" for strength 3 (padded with hollow stars to 3).
static func stars(combo: Dictionary) -> String:
	var n := clampi(int(combo.get("strength", 1)), 1, 3)
	return STAR.repeat(n) + "☆".repeat(3 - n)
