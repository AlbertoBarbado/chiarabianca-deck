class_name DamageTypes
extends RefCounted
## Damage types (elements) from data/combat/damage_types.json and the one rule that combines them:
##
##   final damage = base x (100 + attacker bonus + target modifier + status vulnerability) / 100
##
## - attacker bonus: weapon "damage" stats (e.g. +15 fire), Combatant.damage_bonus
## - target modifier: enemy weaknesses (+) and resistances (-), armour resistances (-), Combatant.affinity
##   (resistance is capped at max_resistance, so nothing is fully immune unless the data says 100 elsewhere)
## - status vulnerability: e.g. Chill adds +10% physical damage taken per stack
## Rounded to the nearest whole number; a hit of at least 1 base damage never drops below 1.
## Pure logic: presentation reads names and colours from here too.

const PATH := "res://data/combat/damage_types.json"
const PHYSICAL := "physical"

static var _types: Dictionary = {}   # id -> {id, name, color, icon}
static var _order: Array[String] = []
static var _max_resistance: int = 75
static var _loaded: bool = false


static func reload() -> void:
	_types.clear()
	_order.clear()
	var parsed: Variant = DataRegistry.read_json(PATH)
	if parsed is Dictionary:
		_max_resistance = int((parsed as Dictionary).get("max_resistance", 75))
		for entry: Variant in (parsed as Dictionary).get("types", []):
			if entry is Dictionary:
				_types[str(entry["id"])] = entry
				_order.append(str(entry["id"]))
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		reload()


static func ids() -> Array[String]:
	_ensure()
	return _order.duplicate()


static func is_valid(element: String) -> bool:
	_ensure()
	return _types.has(element)


## Unknown or empty ids count as physical.
static func normalize(element: String) -> String:
	return element if is_valid(element) else PHYSICAL


static func display_name(element: String) -> String:
	_ensure()
	return str(_types.get(element, {}).get("name", element.capitalize()))


static func color(element: String) -> Color:
	_ensure()
	return Color.from_string(str(_types.get(element, {}).get("color", "")), Color("d8d2c4"))


static func icon(element: String) -> Texture2D:
	_ensure()
	var path := str(_types.get(element, {}).get("icon", ""))
	if path.begins_with("res://"):
		return load(path) as Texture2D if ResourceLoader.exists(path) else null
	return UIAssets.texture(path) if path != "" else null


static func max_resistance() -> int:
	_ensure()
	return _max_resistance


## Total percentage modifier of `target` against `element` from `source` (0 = unchanged).
static func modifier(element: String, source: Combatant, target: Combatant) -> int:
	var pct := 0
	if source != null:
		pct += int(source.damage_bonus.get(element, 0))
		pct += source.damage_dealt_pct()  # Sandblind
	if target != null:
		pct += maxi(-max_resistance(), int(target.affinity.get(element, 0)))
		pct += target.status_vulnerability(element)
	return pct


## Damage after the element rule (see the class comment).
static func apply(amount: int, element: String, source: Combatant, target: Combatant) -> int:
	if amount <= 0:
		return 0
	var pct := modifier(element, source, target)
	return maxi(1, roundi(amount * (100.0 + pct) / 100.0))


## Element of a card's damage: the effect's own "element", else its specialization's damage_element,
## else physical.
static func for_card_effect(effect: Dictionary, card_def: CardDef) -> String:
	var explicit := str(effect.get("element", ""))
	if explicit != "":
		return normalize(explicit)
	if card_def != null:
		var spec := DataRegistry.get_specialization(card_def.specialization_id)
		if spec != null and spec.damage_element != "":
			return normalize(spec.damage_element)
	return PHYSICAL


## "Weak to Fire +50%, Resists Holy -25%" style lines for an affinity dictionary.
static func describe_affinity(affinity: Dictionary) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for element in ids():
		var pct := int(affinity.get(element, 0))
		if pct != 0:
			lines.append({"element": element, "pct": pct, "text": "%s %s%d%%" % [display_name(element), "+" if pct > 0 else "", pct]})
	return lines
