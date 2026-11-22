class_name MapLayout
extends RefCounted
## Presentation layout of a map graph (data/maps/<name>_layout.json, "layout_for": map id).
## Positions are normalised (0..1) on the background picture, so the same graph can be drawn at
## any resolution; the graph itself (data/maps/<map>.json) never contains screen positions.
##
## JSON keys: layout_for, background_asset (AssetCatalog id), nodes {id: [x, y]},
## label_sides {id: above|below|left|right}, default_bend, bends {"from>to": float},
## node_size [w, h] (virtual px, sized for touch), climb_asset (AssetCatalog id of a tall picture that
## scrolls with a scrolling chart, e.g. a mountain to climb), altitude {base, summit, unit} (a gauge
## shows the party's height: base at the start room, summit at the boss room).

const DEFAULT_NODE_SIZE := Vector2(82, 82)
const DEFAULT_BEND := 0.0
const LABEL_SIDES: Array[String] = ["above", "below", "left", "right"]

var map_id: String = ""
var background_asset: String = ""
var nodes: Dictionary = {}        # node_id -> Vector2 (0..1)
var label_sides: Dictionary = {}  # node_id -> "above" | "below" | "left" | "right"
var default_bend: float = DEFAULT_BEND
var bends: Dictionary = {}        # "from>to" -> float (curve bulge as a share of the edge length)
var node_size: Vector2 = DEFAULT_NODE_SIZE
## Height of the route chart in multiples of the picture height. Above 1 the nodes and paths scroll
## vertically over the fixed picture (node y positions are normalised on the whole chart).
var canvas_height: float = 1.0
## Tall picture drawn under the paths that scrolls with the chart ("" = none).
var climb_asset: String = ""
## {base, summit, unit}: heights of the start and boss rooms for the altitude gauge (empty = no gauge).
var altitude: Dictionary = {}


static func from_dict(data: Dictionary) -> MapLayout:
	var layout := MapLayout.new()
	layout.map_id = str(data.get("layout_for", ""))
	layout.background_asset = str(data.get("background_asset", ""))
	for node_id: String in data.get("nodes", {}):
		var pair: Array = data["nodes"][node_id]
		if pair.size() == 2:
			layout.nodes[node_id] = Vector2(float(pair[0]), float(pair[1]))
	layout.label_sides = (data.get("label_sides", {}) as Dictionary).duplicate()
	layout.default_bend = float(data.get("default_bend", DEFAULT_BEND))
	layout.bends = (data.get("bends", {}) as Dictionary).duplicate()
	layout.canvas_height = maxf(1.0, float(data.get("canvas_height", 1.0)))
	layout.climb_asset = str(data.get("climb_asset", ""))
	layout.altitude = (data.get("altitude", {}) as Dictionary).duplicate()
	var size_pair: Array = data.get("node_size", [])
	if size_pair.size() == 2:
		layout.node_size = Vector2(float(size_pair[0]), float(size_pair[1]))
	return layout


## The layout registered for a map id, or null when the map has none (plain layout is used).
static func for_map(p_map_id: String) -> MapLayout:
	var data := DataRegistry.get_layout(p_map_id)
	return null if data.is_empty() else from_dict(data)


func get_background() -> Texture2D:
	return AssetCatalog.texture(background_asset)


func get_climb_texture() -> Texture2D:
	return AssetCatalog.texture(climb_asset) if climb_asset != "" else null


## Share of the climb (0 at the lowest room, 1 at the highest) for a node, from its chart height.
func climb_share(node_id: String) -> float:
	if not nodes.has(node_id):
		return 0.0
	var lowest := 0.0
	var highest := 1.0
	for spot: Vector2 in nodes.values():
		lowest = maxf(lowest, spot.y)
		highest = minf(highest, spot.y)
	return clampf((lowest - (nodes[node_id] as Vector2).y) / maxf(0.001, lowest - highest), 0.0, 1.0)


## Height of a node for the altitude gauge, rounded to 10 (-1 without an altitude block). The top
## room (the exit above the boss) counts as the summit too.
func altitude_at(node_id: String) -> int:
	if altitude.is_empty():
		return -1
	var base := float(altitude.get("base", 0))
	var summit := float(altitude.get("summit", 0))
	return roundi((base + (summit - base) * climb_share(node_id)) / 10.0) * 10


func has_position(node_id: String) -> bool:
	return nodes.has(node_id)


func get_bend(from_id: String, to_id: String) -> float:
	return float(bends.get("%s>%s" % [from_id, to_id], default_bend))


func get_label_side(node_id: String) -> String:
	var side := str(label_sides.get(node_id, "below"))
	return side if LABEL_SIDES.has(side) else "below"


## Problems that make the layout unusable for a graph (empty = valid): every graph node needs a
## position inside 0..1, and the layout must not describe nodes the graph does not have.
func validate(graph: MapGraph) -> Array[String]:
	var problems: Array[String] = []
	if map_id != graph.id:
		problems.append("layout is for '%s', graph is '%s'" % [map_id, graph.id])
	for node_id: String in graph.nodes:
		if not nodes.has(node_id):
			problems.append("node '%s' has no layout position" % node_id)
	for node_id: String in nodes:
		var spot: Vector2 = nodes[node_id]
		if not graph.nodes.has(node_id):
			problems.append("layout position for unknown node '%s'" % node_id)
		if spot.x < 0.0 or spot.x > 1.0 or spot.y < 0.0 or spot.y > 1.0:
			problems.append("node '%s' position %s is outside 0..1" % [node_id, spot])
	for key: String in bends:
		var ends := key.split(">")
		if ends.size() != 2 or not graph.nodes.has(ends[0]) or not graph.nodes.has(ends[1]) or not (graph.get_node_data(ends[0]).next_ids.has(ends[1])):
			problems.append("curve for '%s' does not match a graph edge" % key)
	return problems
