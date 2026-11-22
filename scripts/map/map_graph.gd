class_name MapGraph
extends RefCounted
## Static map layout: nodes and their connections. Independent of any visualization.

var id: String = ""
var display_name: String = ""
var subtitle: String = ""
var start_node_id: String = ""
var exit_node_id: String = ""
var nodes: Dictionary = {}  # id -> MapNodeData
var rules: Dictionary = {}
## Act number shown to the player (1 = first map of a run).
var act: int = 1
## AssetCatalog id of the battle backdrop used by fights on this map ("" = default).
var battle_backdrop: String = ""
## Terrain tag -> {name, hint, backdrop, foes}: rooms tagged with that terrain use its backdrop
## (fights and room screens), show its hint on the map, and their fights only use its foes
## (checked by the tests). A terrain without a backdrop keeps the map's own pictures.
var terrains: Dictionary = {}
## Terrain tag -> AssetCatalog id (from `terrains`), e.g. {"sea": "battle_ship_deck"} on the coast.
var terrain_backdrops: Dictionary = {}
## {title, text, badge} shown when the map is completed.
var completion: Dictionary = {}
## Expedition maps (rerolled or generated, see ExpeditionGenerator) keep their whole definition and
## presentation layout here so saves can rebuild them; {} for maps used exactly as in data/maps.
var custom_def: Dictionary = {}
var custom_layout: Dictionary = {}


static func from_dict(data: Dictionary) -> MapGraph:
	var graph := MapGraph.new()
	graph.id = str(data.get("id", ""))
	graph.display_name = str(data.get("name", graph.id))
	graph.subtitle = str(data.get("subtitle", ""))
	graph.start_node_id = str(data.get("start_node_id", ""))
	graph.exit_node_id = str(data.get("exit_node_id", ""))
	graph.rules = data.get("rules", {})
	graph.act = int(data.get("act", 1))
	graph.battle_backdrop = str(data.get("battle_backdrop", ""))
	graph.completion = data.get("completion", {}) if data.get("completion", {}) is Dictionary else {}
	graph.terrains = data.get("terrains", {}) if data.get("terrains", {}) is Dictionary else {}
	for terrain_id: String in graph.terrains:
		var backdrop := str((graph.terrains[terrain_id] as Dictionary).get("backdrop", "")) if graph.terrains[terrain_id] is Dictionary else ""
		if backdrop != "":
			graph.terrain_backdrops[terrain_id] = backdrop
	for entry: Dictionary in data.get("nodes", []):
		var node := MapNodeData.from_dict(entry)
		graph.nodes[node.id] = node
	return graph


func get_node_data(node_id: String) -> MapNodeData:
	return nodes.get(node_id) as MapNodeData


## Picture for a room on this map that depends on its terrain ("" when the terrain has none).
func terrain_backdrop(node: MapNodeData) -> String:
	if node == null or node.terrain == "":
		return ""
	return str(terrain_backdrops.get(node.terrain, ""))


## Map tooltip line for a room's terrain ("" when it has none).
func terrain_hint(node: MapNodeData) -> String:
	if node == null or not terrains.get(node.terrain) is Dictionary:
		return ""
	return str((terrains[node.terrain] as Dictionary).get("hint", ""))


func get_next_ids(node_id: String) -> Array[String]:
	var node := get_node_data(node_id)
	var result: Array[String] = []
	if node != null:
		result.assign(node.next_ids)
	return result


## Bounding box of node positions (used by visualizations to scale the layout).
func get_bounds() -> Rect2:
	var rect := Rect2()
	var first := true
	for node: MapNodeData in nodes.values():
		if first:
			rect = Rect2(node.position, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(node.position)
	return rect


## Returns a list of problems (empty when the graph is valid).
func validate() -> Array[String]:
	var errors: Array[String] = []
	if get_node_data(start_node_id) == null:
		errors.append("Missing start node '%s'" % start_node_id)
	if get_node_data(exit_node_id) == null:
		errors.append("Missing exit node '%s'" % exit_node_id)
	for node: MapNodeData in nodes.values():
		for next_id in node.next_ids:
			if get_node_data(next_id) == null:
				errors.append("Node '%s' links to unknown node '%s'" % [node.id, next_id])
	if errors.is_empty() and not _reachable_from(start_node_id).has(exit_node_id):
		errors.append("Exit is not reachable from the start")
	return errors


func _reachable_from(node_id: String) -> Array[String]:
	var seen: Array[String] = []
	var queue: Array[String] = [node_id]
	while not queue.is_empty():
		var current: String = queue.pop_back()
		if seen.has(current):
			continue
		seen.append(current)
		queue.append_array(get_next_ids(current))
	return seen
