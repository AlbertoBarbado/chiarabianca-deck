class_name SpecializationDef
extends RefCounted
## Static definition of a character specialization (loaded from data/specializations).

const STATUS_PLAYABLE := "playable"

var id: String = ""
var character_id: String = ""
var display_name: String = ""
var identity: String = ""
var description: String = ""
var passive: Dictionary = {}
## Status ids this specialization revolves around (explained on the selection screen).
var keywords: Array[String] = []
var starting_deck_card_ids: Array[String] = []
var card_pool: Array[String] = []
## Epic cards: offered only by the reward of a map's final fight (never by normal rewards).
var epic_pool: Array[String] = []
var skill_tree: Dictionary = {}
var status: String = "design_template"
## Presentation only (data "visual"): accent colour and catalog icon id. Empty = use the character's.
var accent_color: Color = Color.TRANSPARENT
var icon_id: String = ""
## Damage type of this specialization's cards unless an effect names its own ("element").
var damage_element: String = ""


static func from_dict(data: Dictionary) -> SpecializationDef:
	var def := SpecializationDef.new()
	def.id = str(data.get("id", ""))
	def.character_id = str(data.get("character_id", ""))
	def.display_name = str(data.get("display_name", def.id.capitalize()))
	def.identity = str(data.get("identity", ""))
	def.description = str(data.get("description", def.identity))
	def.passive = data.get("starting_passive", {})
	def.keywords.assign(data.get("keywords", []))
	def.starting_deck_card_ids.assign(data.get("starting_deck_card_ids", []))
	def.card_pool.assign(data.get("card_pool", []))
	def.epic_pool.assign(data.get("epic_pool", []))
	def.skill_tree = data.get("skill_tree", {})
	def.status = str(data.get("status", "design_template"))
	var visual: Dictionary = data.get("visual", {})
	def.accent_color = Color.from_string(str(visual.get("accent", "")), Color.TRANSPARENT)
	def.icon_id = str(visual.get("icon", ""))
	def.damage_element = str(data.get("damage_element", ""))
	return def


## True when the passive is real (not a TODO placeholder).
func has_passive() -> bool:
	var passive_name := str(passive.get("name", ""))
	return passive_name != "" and not passive_name.begins_with("TODO")


## A specialization can be taken into an adventure once it has a real starting deck.
func is_playable() -> bool:
	return status == STATUS_PLAYABLE and not starting_deck_card_ids.is_empty()


## Starting deck grouped by card id, preserving first-seen order: [{card_id, count}].
func get_deck_summary() -> Array[Dictionary]:
	var order: Array[String] = []
	var counts: Dictionary = {}
	for card_id in starting_deck_card_ids:
		if not counts.has(card_id):
			order.append(card_id)
			counts[card_id] = 0
		counts[card_id] += 1
	var summary: Array[Dictionary] = []
	for card_id in order:
		summary.append({"card_id": card_id, "count": counts[card_id]})
	return summary


## Specialization accent, falling back to the owning character's colour.
func get_accent(fallback: Color) -> Color:
	return accent_color if accent_color.a > 0.0 else fallback
