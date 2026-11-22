class_name CardDef
extends RefCounted
## Static card definition (loaded from data/cards). Never mutated at runtime:
## combat creates CardInstance objects that point at it.

const TARGET_SINGLE_ENEMY := "single_enemy"
const TARGET_ALL_ENEMIES := "all_enemies"
const TARGET_SELF := "self"
const TARGET_SINGLE_ALLY := "single_ally"
const TARGET_ALL_ALLIES := "all_allies"
const TARGET_NONE := "none"

const TYPE_POWER := "power"

var id: String = ""
var display_name: String = ""
var owner_character_id: String = ""
var specialization_id: String = ""
var cost: int = 0
var card_type: String = "skill"
var target: String = TARGET_NONE
var rarity: String = "basic"
var description: String = ""
var effects: Array = []
var upgrade: Dictionary = {}
var art_path: String = ""
## Played cards go to the exhaust pile (gone until the next combat) instead of the discard pile.
## Powers always exhaust; any other card can with "exhaust": true (e.g. one big heal per fight).
var exhausts: bool = false
## Token: a temporary card created during combat (a Gust). It never joins a deck: it vanishes when
## played or when the turn ends, and is never offered as a reward.
var token: bool = false
## Retain: the card stays in the hand at the end of the turn instead of being discarded.
var retain: bool = false
## X cost: playing it spends all the Energy left; its effects read that amount as X
## ("per_x": N adds N per point, "repeat_x": true resolves the effect X times).
var x_cost: bool = false
## Untouched copy of the source data, used to prove definitions are never mutated.
var raw: Dictionary = {}


static func from_dict(data: Dictionary) -> CardDef:
	var def := CardDef.new()
	def.raw = data.duplicate(true)
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("name", def.id))
	def.owner_character_id = str(data.get("owner_character_id", ""))
	def.specialization_id = str(data.get("specialization_id", ""))
	def.cost = int(data.get("cost", 0))
	def.card_type = str(data.get("card_type", "skill"))
	def.exhausts = bool(data.get("exhaust", false)) or def.card_type == TYPE_POWER
	def.token = bool(data.get("token", false))
	def.retain = bool(data.get("retain", false))
	def.x_cost = bool(data.get("x_cost", false))
	def.target = str(data.get("target", TARGET_NONE))
	def.rarity = str(data.get("rarity", "basic"))
	def.description = str(data.get("description", ""))
	def.effects = (data.get("effects", []) as Array).duplicate(true)
	def.upgrade = (data.get("upgrade", {}) as Dictionary).duplicate(true)
	def.art_path = str(data.get("art_path", ""))
	return def


func get_art_texture() -> Texture2D:
	if art_path != "" and ResourceLoader.exists(art_path):
		return load(art_path) as Texture2D
	return null
