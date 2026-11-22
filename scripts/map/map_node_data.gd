class_name MapNodeData
extends RefCounted
## Static definition of one map node (a room).

const TYPE_START := "start"
const TYPE_COMBAT := "combat"
const TYPE_REST := "rest"
const TYPE_MERCHANT := "merchant"
const TYPE_EVENT := "event"
const TYPE_EXIT := "exit"
const TYPE_ELITE := "elite"
const TYPE_TREASURE := "treasure"
const TYPE_TOWN := "town"
const TYPE_BOSS := "boss"

var id: String = ""
var type: String = TYPE_COMBAT
var display_name: String = ""
var position: Vector2 = Vector2.ZERO
var next_ids: Array[String] = []
var encounter_id: String = ""
var event_id: String = ""
var shop_id: String = ""
var treasure_id: String = ""
var town_id: String = ""
## Events may be rolled from a pool (data/events entries tagged with this pool) instead of a fixed event_id.
var event_pool: String = ""
var final_encounter: bool = false
## Optional terrain tag ("sea", "shore", ...). The map's terrain_backdrops pick the picture for it.
var terrain: String = ""
var raw: Dictionary = {}


static func from_dict(data: Dictionary) -> MapNodeData:
	var node := MapNodeData.new()
	node.raw = data.duplicate(true)
	node.id = str(data.get("id", ""))
	node.type = str(data.get("type", TYPE_COMBAT))
	node.display_name = str(data.get("name", node.id))
	var pos: Array = data.get("position", [0, 0])
	node.position = Vector2(float(pos[0]), float(pos[1]))
	node.next_ids.assign(data.get("next", []))
	node.encounter_id = str(data.get("encounter_id", ""))
	node.event_id = str(data.get("event_id", ""))
	node.shop_id = str(data.get("shop_id", ""))
	node.treasure_id = str(data.get("treasure_id", ""))
	node.town_id = str(data.get("town_id", ""))
	node.event_pool = str(data.get("event_pool", ""))
	node.final_encounter = bool(data.get("final_encounter", false))
	node.terrain = str(data.get("terrain", ""))
	return node
