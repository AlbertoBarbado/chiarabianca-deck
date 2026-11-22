class_name AssetCatalog
extends RefCounted
## Central lookup for presentation art (data/art/art_catalog.json).
## Every visual in the UI asks this class instead of hardcoding paths. An entry is either
## {"path": "res://..."} (a standalone production file) or {"source", "region"} (a region of
## a concept board, wrapped in an AtlasTexture). Missing files or ids return null, and the UI
## then draws its own fallback, so absent art never breaks gameplay.

const CATALOG_PATH := "res://data/art/art_catalog.json"

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _cache: Dictionary = {}


static func reload() -> void:
	_data = {}
	_cache.clear()
	if FileAccess.file_exists(CATALOG_PATH):
		var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_data = parsed
	if _data.is_empty():
		push_warning("AssetCatalog: no art catalog loaded; UI will use fallbacks")
	_loaded = true
	if OS.has_feature("release") and not release_blockers().is_empty():
		push_warning("AssetCatalog: release build contains art that is not cleared for commercial use")


static func _ensure() -> void:
	if not _loaded:
		reload()


## Texture for an asset id, or null when unknown or the file is missing.
static func texture(asset_id: String) -> Texture2D:
	_ensure()
	if asset_id == "":
		return null
	if _cache.has(asset_id):
		return _cache[asset_id] as Texture2D
	var result: Texture2D = _build_texture(asset_id)
	_cache[asset_id] = result
	return result


static func _build_texture(asset_id: String) -> Texture2D:
	var entry: Dictionary = _data.get("assets", {}).get(asset_id, {})
	if entry.is_empty():
		return null
	if entry.has("path"):
		var path := str(entry["path"])
		return load(path) as Texture2D if ResourceLoader.exists(path) else null
	var source_path := str(_data.get("sources", {}).get(str(entry.get("source", "")), ""))
	var region: Array = entry.get("region", [])
	if source_path == "" or region.size() != 4 or not ResourceLoader.exists(source_path):
		return null
	var base := load(source_path) as Texture2D
	if base == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = base
	atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	return atlas


static func asset_ids() -> Array[String]:
	_ensure()
	var ids: Array[String] = []
	ids.assign(_data.get("assets", {}).keys())
	return ids


static func get_entry(asset_id: String) -> Dictionary:
	_ensure()
	return _data.get("assets", {}).get(asset_id, {})


## Assets that are not cleared for a commercial release (see docs/ASSET_LICENSES.md).
static func release_blockers() -> Array[String]:
	var blockers: Array[String] = []
	for id in asset_ids():
		if not bool(get_entry(id).get("release_cleared", false)):
			blockers.append(id)
	return blockers


# --- Semantic helpers --------------------------------------------------------

static func icon(name: String) -> Texture2D:
	_ensure()
	return texture(str(_data.get("icons", {}).get(name, "")))


static func icon_by_id(asset_id: String) -> Texture2D:
	return texture(asset_id)


static func portrait(character_id: String) -> Texture2D:
	_ensure()
	return texture(str(_data.get("characters", {}).get(character_id, {}).get("portrait", "")))


## Avatar art: a face-centred crop from the catalog ("face"), else the top square of the portrait.
static func portrait_face(character_id: String) -> Texture2D:
	var key := "face:" + character_id
	if _cache.has(key):
		return _cache[key] as Texture2D
	var explicit := texture(str(_data.get("characters", {}).get(character_id, {}).get("face", "")))
	if explicit != null:
		_cache[key] = explicit
		return explicit
	var full := portrait(character_id)
	var result: Texture2D = full
	if full is AtlasTexture:
		var source := full as AtlasTexture
		var region := source.region
		var face := AtlasTexture.new()
		face.atlas = source.atlas
		face.region = Rect2(region.position.x, region.position.y + region.size.y * 0.04, region.size.x, minf(region.size.x, region.size.y))
		result = face
	_cache[key] = result
	return result


## Face crop with a circular alpha mask (for round avatar frames). Built once per character.
static func portrait_face_round(character_id: String) -> Texture2D:
	var key := "face_round:" + character_id
	if _cache.has(key):
		return _cache[key] as Texture2D
	var result: Texture2D = null
	var face := portrait_face(character_id)
	if face != null:
		var image := face.get_image()
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			var w := image.get_width()
			var h := image.get_height()
			var radius := minf(w, h) / 2.0
			var center := Vector2(w, h) / 2.0
			for y in h:
				for x in w:
					var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
					var c := image.get_pixel(x, y)
					c.a *= clampf((radius - d) / 1.5, 0.0, 1.0)
					image.set_pixel(x, y, c)
			result = ImageTexture.create_from_image(image)
	_cache[key] = result
	return result


static func figure(character_id: String) -> Texture2D:
	_ensure()
	return texture(str(_data.get("characters", {}).get(character_id, {}).get("figure", "")))


## {"texture": Texture2D or null, "tint": Color} for a map node's room.
## Room picture: the node's own (by_node), else the map's (by_map: the forest and the coast use their
## battle picture for every room), else the room type's default (castle interiors).
static func room_backdrop(node_id: String, node_type: String, map_id: String = "") -> Dictionary:
	_ensure()
	var rooms: Dictionary = _data.get("rooms", {})
	var fallback := str(rooms.get("by_map", {}).get(map_id, rooms.get("by_type", {}).get(node_type, "")))
	var asset_id := str(rooms.get("by_node", {}).get(node_id, fallback))
	var tint_hex := str(rooms.get("tint_by_node", {}).get(node_id, rooms.get("tints", {}).get(node_type, "")))
	return {"texture": texture(asset_id), "tint": Color.from_string(tint_hex, Color(0.3, 0.4, 0.8)), "asset_id": asset_id}


static func backdrop_by_asset(asset_id: String, tint: Color = Color(0.3, 0.4, 0.8), wash_alpha: float = 0.22) -> Dictionary:
	return {"texture": texture(asset_id), "tint": tint, "asset_id": asset_id, "wash_alpha": wash_alpha}


## Illustration for a card: per-card override, then type/specialization defaults. Null = fallback.
static func card_art_id(card_id: String, specialization_id: String, card_type: String) -> String:
	_ensure()
	var rules: Dictionary = _data.get("card_art", {})
	var by_card: Dictionary = rules.get("by_card", {})
	if by_card.has(card_id):
		return str(by_card[card_id])
	var spec_art := str(rules.get("by_specialization", {}).get(specialization_id, ""))
	var type_art := str(rules.get("by_type", {}).get(card_type, ""))
	# Defense cards of non-tanking specializations use the shared shield art.
	if spec_art != "" and not (card_type == "defense" and type_art != ""):
		return spec_art
	return type_art if type_art != "" else spec_art
