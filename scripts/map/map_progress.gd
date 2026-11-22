class_name MapProgress
extends RefCounted
## Runtime map state: where the party is and which rooms were visited.
## Enforces that only connected, unvisited nodes can be entered.

signal node_entered(node_id: String)
signal move_rejected(node_id: String, reason: String)

enum NodeState { CURRENT, VISITED, AVAILABLE, UNAVAILABLE }

var graph: MapGraph
var current_node_id: String = ""
var visited_ids: Array[String] = []


func _init(p_graph: MapGraph) -> void:
	graph = p_graph
	current_node_id = graph.start_node_id
	visited_ids.append(graph.start_node_id)


## Restores a saved position. Returns false (leaving state untouched) if ids are invalid.
func restore(p_current_id: String, p_visited: Array[String]) -> bool:
	if graph.get_node_data(p_current_id) == null:
		return false
	var cleaned: Array[String] = []
	for node_id in p_visited:
		if graph.get_node_data(node_id) != null and not cleaned.has(node_id):
			cleaned.append(node_id)
	for required in [graph.start_node_id, p_current_id]:
		if not cleaned.has(required):
			cleaned.append(required)
	current_node_id = p_current_id
	visited_ids = cleaned
	return true


func get_available_ids() -> Array[String]:
	var result: Array[String] = []
	for next_id in graph.get_next_ids(current_node_id):
		if not visited_ids.has(next_id):
			result.append(next_id)
	return result


## Returns "" if the party may travel to the node, otherwise the reason it cannot.
func can_travel_to(node_id: String) -> String:
	if graph.get_node_data(node_id) == null:
		return "Unknown location."
	if node_id == current_node_id:
		return "You are already here."
	if visited_ids.has(node_id):
		return "You have already been there."
	if not graph.get_next_ids(current_node_id).has(node_id):
		return "That room is not connected to your current position."
	return ""


func travel_to(node_id: String) -> bool:
	var reason := can_travel_to(node_id)
	if reason != "":
		move_rejected.emit(node_id, reason)
		return false
	current_node_id = node_id
	visited_ids.append(node_id)
	node_entered.emit(node_id)
	return true


func get_node_state(node_id: String) -> NodeState:
	if node_id == current_node_id:
		return NodeState.CURRENT
	if visited_ids.has(node_id):
		return NodeState.VISITED
	if get_available_ids().has(node_id):
		return NodeState.AVAILABLE
	return NodeState.UNAVAILABLE


func is_at_exit() -> bool:
	return current_node_id == graph.exit_node_id
