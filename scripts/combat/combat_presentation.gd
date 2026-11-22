class_name CombatPresentation
extends RefCounted
## Data side of the battlefield art (data/combat/combat_presentation.json): character pose states,
## enemy pose sets, attack cut-ins and the explicit per-card presentation tier. Art only: nothing
## here reads or changes combat state. A missing state falls back to "idle", then to null (the
## views then draw a token), so new characters, enemies and specializations only need data.

const PATH := "res://data/combat/combat_presentation.json"
const ASSET_ROOT := "res://assets/"

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _textures: Dictionary = {}


static func reload() -> void:
	_data = {}
	_textures.clear()
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.open(PATH, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			_data = parsed
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		reload()


static func texture(asset_id: String) -> Texture2D:
	if asset_id == "":
		return null
	var path := ASSET_ROOT + asset_id + ".png"
	if _textures.has(path):
		return _textures[path] as Texture2D
	var loaded: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[path] = loaded
	return loaded


## Pose texture of a party character ("idle", "attack", "cast", "block", "hit", "down").
## A specialization may have its own look ("character_variants": {character: {specialization: poses}},
## e.g. Bianca in Ashveil gear); otherwise the character's base poses are used.
static func character_state(character_id: String, state: String, specialization_id: String = "") -> Texture2D:
	_ensure()
	var states: Dictionary = _data.get("characters", {}).get(character_id, {})
	var variant: Dictionary = _data.get("character_variants", {}).get(character_id, {}).get(specialization_id, {})
	if not variant.is_empty():
		var own := texture(str(variant.get(state, variant.get("idle", ""))))
		if own != null:
			return own
	var tex := texture(str(states.get(state, "")))
	return tex if tex != null else texture(str(states.get("idle", "")))


## True if this specialization gives the character a look of her own (e.g. Bianca's Ashveil gear).
static func has_variant(character_id: String, specialization_id: String) -> bool:
	_ensure()
	return not (_data.get("character_variants", {}).get(character_id, {}).get(specialization_id, {}) as Dictionary).is_empty()


## Id of the pose set used by an enemy definition (e.g. "knight_captain").
static func enemy_set(enemy_def_id: String) -> String:
	_ensure()
	var enemies: Dictionary = _data.get("enemies", {})
	return str(enemies.get("assign", {}).get(enemy_def_id, enemies.get("default_set", "")))


static func enemy_state(enemy_def_id: String, state: String) -> Texture2D:
	_ensure()
	var set_id := enemy_set(enemy_def_id)
	var states: Dictionary = _data.get("enemies", {}).get("sets", {}).get(set_id, {})
	var tex := texture(str(states.get(state, "")))
	return tex if tex != null else texture(str(states.get("idle", "")))


## Sprite size factor of an enemy definition (bosses and elites are drawn larger; 1 = normal).
static func enemy_scale(enemy_def_id: String) -> float:
	_ensure()
	return float(_data.get("enemies", {}).get("scale", {}).get(enemy_def_id, 1.0))


## Body motion of a character id or an enemy pose set: the "motion_profiles" entry named in
## "motion" (default "stand"), always with every key filled in.
static func motion_profile(key: String) -> Dictionary:
	_ensure()
	var profiles: Dictionary = _data.get("motion_profiles", {})
	var profile_id := str(_data.get("motion", {}).get(key, "stand"))
	var profile: Dictionary = DEFAULT_MOTION.duplicate()
	profile.merge(profiles.get(profile_id, {}), true)
	profile["id"] = profile_id
	return profile


## How far an enemy's sprite is pushed into the floor (share of its height; "sink" by pose set).
static func enemy_sink(enemy_def_id: String) -> float:
	_ensure()
	return float(_data.get("enemies", {}).get("sink", {}).get(enemy_set(enemy_def_id), 0.0))


static func enemy_motion(enemy_def_id: String) -> Dictionary:
	return motion_profile(enemy_set(enemy_def_id))


const DEFAULT_MOTION := {"breath": [0.012, 0.022], "period": 2.8, "bob": 0.0, "sway": 0.0, "lunge": 0.24, "arc": 0.0,
	"windup": 0.14, "strike": 0.1, "recover": 0.28, "squash": 0.07, "knockback": 0.12, "impact": 0.0, "afterimages": 2}


## Sprite lighting for a battle backdrop asset: {ambient: Color, rim: Color, rim_amount: float, rim_from: String}.
## Floor of a battle backdrop: {top: share of the picture height where the walkable floor begins,
## anchor_y: how the screen crops a picture wider screens cut (RoomBackdrop.anchor_y)}. The
## battlefield's feet line must fall below `top` on every screen shape (tests check this).
static func floor_info(backdrop_asset_id: String) -> Dictionary:
	_ensure()
	var all: Dictionary = _data.get("floors", {})
	var entry: Dictionary = all.get(backdrop_asset_id, {})
	var defaults: Dictionary = all.get("default", {})
	return {
		"top": float(entry.get("top", defaults.get("top", 0.5))),
		"anchor_y": float(entry.get("anchor_y", defaults.get("anchor_y", 0.8))),
		"zoom": float(entry.get("zoom", defaults.get("zoom", 1.0))),
		"known": all.has(backdrop_asset_id),
	}


static func lighting(backdrop_asset_id: String) -> Dictionary:
	_ensure()
	var all: Dictionary = _data.get("lighting", {})
	var entry: Dictionary = all.get(backdrop_asset_id, all.get("default", {}))
	return {
		"ambient": Color(str(entry.get("ambient", "#ffffff"))),
		"rim": Color(str(entry.get("rim", "#ffffff"))),
		"rim_amount": float(entry.get("rim_amount", 0.0)),
		"rim_from": str(entry.get("rim_from", "top")),
	}


## Presentation tier (1-4) explicitly assigned to a card, or 0 when the card has none.
static func card_tier(card_id: String) -> int:
	_ensure()
	return int(_data.get("card_tiers", {}).get(card_id, 0))


## Cut-in artwork for a card: {texture, tier, seconds, width} or {} (tier 1, no art or no mapping).
static func cutin_for_card(card_id: String, specialization_id: String) -> Dictionary:
	_ensure()
	var tier := card_tier(card_id)
	if tier < 2:
		return {}
	var art := texture(str(_data.get("cutins", {}).get(specialization_id, {}).get(str(tier), "")))
	if art == null:
		return {}
	var style: Dictionary = _data.get("tier_style", {}).get(str(tier), {})
	return {"texture": art, "tier": tier, "seconds": float(style.get("seconds", 0.8)), "width": float(style.get("width", 320.0))}
