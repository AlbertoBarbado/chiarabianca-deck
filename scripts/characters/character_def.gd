class_name CharacterDef
extends RefCounted
## Static definition of a playable character (loaded from data/characters).

var id: String = ""
var display_name: String = ""
var title: String = ""
var role: String = ""
var story: String = ""
var hair: String = ""
var eyes: String = ""
var silhouette: String = ""
var palette: Array[String] = []
var max_hp: int = 1
var starting_hp: int = 1
var specialization_ids: Array[String] = []
var accent_color: Color = Color("c9d1dc")
var asset_paths: Dictionary = {}


static func from_dict(data: Dictionary) -> CharacterDef:
	var def := CharacterDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", def.id.capitalize()))
	def.title = str(data.get("title", ""))
	def.role = str(data.get("role", ""))
	def.story = str(data.get("story", ""))
	var appearance: Dictionary = data.get("appearance", {})
	def.hair = str(appearance.get("hair", ""))
	def.eyes = str(appearance.get("eyes", ""))
	def.silhouette = str(appearance.get("silhouette", ""))
	def.palette.assign(appearance.get("palette", []))
	var stats: Dictionary = data.get("base_stats", {})
	def.max_hp = int(stats.get("max_hp", 1))
	def.starting_hp = int(stats.get("starting_hp", def.max_hp))
	def.specialization_ids.assign(data.get("specializations", []))
	var ui: Dictionary = data.get("ui", {})
	def.accent_color = Color.from_string(str(ui.get("accent_color", "")), def.accent_color)
	def.asset_paths = data.get("asset_paths", {})
	return def


## Returns the portrait texture, or null while the production art does not exist yet.
func get_portrait_texture() -> Texture2D:
	var path := str(asset_paths.get("portrait", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
