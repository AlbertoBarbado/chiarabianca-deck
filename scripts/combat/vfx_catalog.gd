class_name VfxCatalog
extends RefCounted
## Data side of the combat visual effects (data/effects/combat_vfx.json): effect definitions,
## quality levels and the rules that map a gameplay event to an effect id. No scenes or nodes,
## so it can be tested headless. Presentation only: it never touches combat state.

const CATALOG_PATH := "res://data/effects/combat_vfx.json"
const SPRITE_ROOT := "res://assets/effects/sprites/"
const DEFAULT_QUALITY := "full"
const MATCH_KEYS: Array[String] = ["kind", "card_id", "specialization_id", "status_id", "target_group", "element", "action_id", "reaction_id"]

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _textures: Dictionary = {}


static func reload() -> void:
	_data = {}
	_textures.clear()
	if FileAccess.file_exists(CATALOG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.open(CATALOG_PATH, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			_data = parsed
	if _data.is_empty():
		push_warning("VfxCatalog: no VFX catalog loaded; combat effects are disabled")
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		reload()


static func effect_ids() -> Array[String]:
	_ensure()
	var ids: Array[String] = []
	ids.assign(_data.get("effects", {}).keys())
	return ids


static func effect(effect_id: String) -> Dictionary:
	_ensure()
	return _data.get("effects", {}).get(effect_id, {})


static func rules() -> Array:
	_ensure()
	return _data.get("rules", [])


static func reference_target_width() -> float:
	_ensure()
	return float(_data.get("reference_target_width", 210))


## Quality settings by name ("full", "reduced", "off"); unknown names fall back to full.
static func quality(quality_name: String) -> Dictionary:
	_ensure()
	var levels: Dictionary = _data.get("quality", {})
	return levels.get(quality_name, levels.get(DEFAULT_QUALITY, {"enabled": false}))


## Effect id for a gameplay event, or "" when no rule matches. First matching rule wins; a rule
## matches when every key it lists equals the event's value.
static func match_event(event: Dictionary) -> String:
	for rule: Dictionary in rules():
		var ok := true
		for key in MATCH_KEYS:
			if rule.has(key) and str(rule[key]) != str(event.get(key, "")):
				ok = false
				break
		if ok:
			return str(rule.get("vfx", ""))
	return ""


## "fire/fire_bolt" is under SPRITE_ROOT; a full "res://..." path (e.g. generated frost art) is used as is.
static func sprite_path(def: Dictionary) -> String:
	var sprite := str(def.get("sprite", ""))
	return (sprite if sprite.begins_with("res://") else SPRITE_ROOT + sprite) + ".png"


## Sprite texture for an effect definition, or null when the file is missing (caller draws a fallback).
static func sprite_texture(def: Dictionary) -> Texture2D:
	var path := sprite_path(def)
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[path] = texture
	return texture
