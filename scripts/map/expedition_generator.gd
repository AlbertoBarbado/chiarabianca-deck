class_name ExpeditionGenerator
extends RefCounted
## Procedural variation for expeditions (docs/PERSISTENT_RPG_DESIGN.md §6.10). Works on map
## DEFINITIONS (the JSON dictionaries of data/maps), never on the map view, and always returns a map
## that passes MapGraph.validate() with every room reachable from the start.
##
## Two modes, chosen by the mission's "map" block:
##  * "fixed" + "variation": "shuffle" — the template map keeps its rooms, layout and art, but fights
##    trade encounters with other fights of the same terrain and depth band, elites trade places with
##    fights of the same band, and some side links are pruned (connectivity is re-checked).
##    "variation": "none" keeps the map exactly as authored (the tutorial).
##  * "generated" — a new layered map (rows x lanes) built from the pools of the region's template
##    map: its terrains, encounters by depth band, elites, event pools, chests, towns and shops.
##    Objective rooms are placed in different lanes and depths. A presentation layout is synthesised
##    on the template's picture.

const BANDS := 3
const PRUNE_CHANCE := 0.3
const ELITE_SWAP_CHANCE := 0.5
const LANE_X := [0.2, 0.5, 0.8]
const MAX_ATTEMPTS := 20


# --- Shared helpers --------------------------------------------------------------------------------

static func _nodes_by_id(map_def: Dictionary) -> Dictionary:
	var by_id := {}
	for node: Dictionary in map_def.get("nodes", []):
		by_id[str(node.get("id", ""))] = node
	return by_id


## Shortest number of steps from the start to every node.
static func depths(map_def: Dictionary) -> Dictionary:
	var by_id := _nodes_by_id(map_def)
	var result := {}
	var start := str(map_def.get("start_node_id", ""))
	if not by_id.has(start):
		return result
	result[start] = 0
	var queue: Array = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id: Variant in (by_id[current] as Dictionary).get("next", []):
			if by_id.has(str(next_id)) and not result.has(str(next_id)):
				result[str(next_id)] = int(result[current]) + 1
				queue.append(str(next_id))
	return result


static func _band(depth: int, max_depth: int) -> int:
	return clampi(int(floor(float(depth) * BANDS / float(maxi(1, max_depth + 1)))), 0, BANDS - 1)


## Every node reachable from the start, and the exit reachable from every node.
static func is_fully_connected(map_def: Dictionary) -> bool:
	var graph := MapGraph.from_dict(map_def)
	if not graph.validate().is_empty():
		return false
	var from_start := graph._reachable_from(graph.start_node_id)
	for node_id: String in graph.nodes:
		if not from_start.has(node_id):
			return false
		if not graph._reachable_from(node_id).has(graph.exit_node_id):
			return false
	return true


# --- Fixed maps: shuffle contents ------------------------------------------------------------------

static func vary_fixed(template: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var map_def: Dictionary = template.duplicate(true)
	var depth := depths(map_def)
	var max_depth := 0
	for value: Variant in depth.values():
		max_depth = maxi(max_depth, int(value))
	# Group fights and elites by terrain and depth band.
	var groups := {}
	for node: Dictionary in map_def.get("nodes", []):
		var type := str(node.get("type", ""))
		if (type != "combat" and type != "elite") or str(node.get("encounter_id", "")) == "" or bool(node.get("final_encounter", false)):
			continue
		var key := "%s|%d" % [str(node.get("terrain", "")), _band(int(depth.get(str(node["id"]), 0)), max_depth)]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(node)
	for key: String in groups:
		var members: Array = groups[key]
		_shuffle_field(members, "combat", rng)
		_shuffle_field(members, "elite", rng)
		_swap_elites(members, rng)
	_prune_links(map_def, rng)
	return map_def


## Shuffles the encounters among the nodes of one type in a group.
static func _shuffle_field(members: Array, type: String, rng: RandomNumberGenerator) -> void:
	var nodes: Array = members.filter(func(n: Dictionary) -> bool: return str(n.get("type", "")) == type)
	var encounters: Array = nodes.map(func(n: Dictionary) -> String: return str(n["encounter_id"]))
	_shuffle(encounters, rng)
	for i in nodes.size():
		(nodes[i] as Dictionary)["encounter_id"] = encounters[i]


## An elite may trade places (type and encounter) with a fight of the same terrain and band.
static func _swap_elites(members: Array, rng: RandomNumberGenerator) -> void:
	var fights: Array = members.filter(func(n: Dictionary) -> bool: return str(n.get("type", "")) == "combat")
	for elite: Dictionary in members.filter(func(n: Dictionary) -> bool: return str(n.get("type", "")) == "elite"):
		if fights.is_empty() or rng.randf() > ELITE_SWAP_CHANCE:
			continue
		var fight: Dictionary = fights[rng.randi_range(0, fights.size() - 1)]
		fights.erase(fight)
		for field in ["type", "encounter_id"]:
			var held: Variant = elite[field]
			elite[field] = fight[field]
			fight[field] = held


## Removes some side links where both ends keep other links; undone when connectivity breaks.
static func _prune_links(map_def: Dictionary, rng: RandomNumberGenerator) -> void:
	var by_id := _nodes_by_id(map_def)
	var incoming := {}
	for node: Dictionary in map_def.get("nodes", []):
		for next_id: Variant in node.get("next", []):
			incoming[str(next_id)] = int(incoming.get(str(next_id), 0)) + 1
	for node: Dictionary in map_def.get("nodes", []):
		var links: Array = node.get("next", [])
		if links.size() < 2 or rng.randf() > PRUNE_CHANCE:
			continue
		var candidates: Array = links.filter(func(id: Variant) -> bool:
			var target: Dictionary = by_id.get(str(id), {})
			return int(incoming.get(str(id), 0)) >= 2 and not ["boss", "exit"].has(str(target.get("type", ""))))
		if candidates.is_empty():
			continue
		var removed: String = str(candidates[rng.randi_range(0, candidates.size() - 1)])
		links.erase(removed)
		if is_fully_connected(map_def):
			incoming[removed] = int(incoming[removed]) - 1
		else:
			links.append(removed)


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var held: Variant = list[i]
		list[i] = list[j]
		list[j] = held


# --- Generated maps -------------------------------------------------------------------------------

## Content pools of a template map: {terrains: [ids in lane order], fights: {terrain: [[band0], [band1], [band2]]},
## elites: {terrain: [ids]}, events: {terrain: [pools]}, treasures: [ids], towns: [ids], shops: [ids], rest_heal}.
static func pools_from(template: Dictionary) -> Dictionary:
	var depth := depths(template)
	var max_depth := 0
	for value: Variant in depth.values():
		max_depth = maxi(max_depth, int(value))
	var pools := {"terrains": [], "fights": {}, "elites": {}, "events": {}, "treasures": [], "towns": [], "shops": []}
	for terrain_id: String in template.get("terrains", {}):
		(pools["terrains"] as Array).append(terrain_id)
		pools["fights"][terrain_id] = [[], [], []]
		pools["elites"][terrain_id] = []
		pools["events"][terrain_id] = []
	for node: Dictionary in template.get("nodes", []):
		var terrain := str(node.get("terrain", ""))
		var type := str(node.get("type", ""))
		if terrain != "" and not (pools["fights"] as Dictionary).has(terrain):
			continue
		match type:
			"combat":
				if terrain != "" and str(node.get("encounter_id", "")) != "" and not bool(node.get("final_encounter", false)):
					var band := _band(int(depth.get(str(node["id"]), 0)), max_depth)
					_add_unique(pools["fights"][terrain][band], str(node["encounter_id"]))
			"elite":
				if terrain != "":
					_add_unique(pools["elites"][terrain], str(node.get("encounter_id", "")))
			"event":
				if terrain != "" and str(node.get("event_pool", "")) != "":
					_add_unique(pools["events"][terrain], str(node["event_pool"]))
			"treasure":
				_add_unique(pools["treasures"], str(node.get("treasure_id", "")))
			"town":
				_add_unique(pools["towns"], str(node.get("town_id", "")))
			"merchant":
				_add_unique(pools["shops"], str(node.get("shop_id", "")))
	return pools


static func _add_unique(list: Array, value: String) -> void:
	if value != "" and not list.has(value):
		list.append(value)


## Builds a new map for a "generated" mission. Returns {map_def, layout_def} (both {} on failure).
## mission "map": {template, rows, lanes: [terrain ids], bands: [terrain ids], weights: {type: weight}}
## ("lanes" give each of the three columns a terrain, like the forest's trails; "bands" instead give
## each third of the climb a terrain, like Frostpeak's altitude bands); objective
## {type: "clear_targets", targets, target_name, target_terrain?}.
static func generate(mission: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = mission.get("map", {})
	var template := DataRegistry.get_map(str(spec.get("template", "")))
	if template.is_empty():
		return {"map_def": {}, "layout_def": {}}
	var pools := pools_from(template)
	for attempt in MAX_ATTEMPTS:
		var map_def := _build(mission, template, pools, rng)
		if is_fully_connected(map_def):
			return {"map_def": map_def, "layout_def": _layout_for(map_def, template, spec)}
	return {"map_def": {}, "layout_def": {}}


static func _build(mission: Dictionary, template: Dictionary, pools: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = mission.get("map", {})
	var rows := clampi(int(spec.get("rows", 9)), 4, 16)
	var lanes: Array = spec.get("lanes", (pools["terrains"] as Array).slice(0, 3))
	while lanes.size() < 3:
		lanes.append(lanes[lanes.size() - 1] if not lanes.is_empty() else "")
	var objective: Dictionary = mission.get("objective", {})
	var map_id := "%s__expedition" % str(mission.get("id", "mission"))
	var nodes: Array = []
	nodes.append({"id": "x_start", "type": "start", "name": str(spec.get("start_name", "Trailhead")), "position": [0, 1], "next": []})
	# Room types per row and lane.
	var grid := []
	for row in range(1, rows + 1):
		var line := []
		for lane in 3:
			line.append(_pick_type(spec, row, rows, rng))
		grid.append(line)
	_place_specials(grid, rows, objective, rng)
	# Nodes.
	var used := {}
	for row in range(1, rows + 1):
		for lane in 3:
			var cell: Dictionary = grid[row - 1][lane]
			var band := clampi(int(floor(float(row - 1) * BANDS / float(rows))), 0, BANDS - 1)
			var bands: Array = spec.get("bands", [])
			var terrain := str(lanes[lane]) if bands.is_empty() else str(bands[clampi(band, 0, bands.size() - 1)])
			var node := {"id": "x_%d_%d" % [row, lane], "type": cell["type"], "position": [row * 2, lane], "terrain": terrain, "next": []}
			_fill_room(node, cell, terrain, band, pools, objective, used, rng)
			nodes.append(node)
	var exit := {"id": "x_exit", "type": "exit", "name": str(spec.get("exit_name", "The Way Home")), "position": [rows * 2 + 2, 1], "next": []}
	nodes.append(exit)
	# Links: start -> every lane of row 1; each room -> its lane and one neighbour in the next row.
	var by_id := {}
	for node: Dictionary in nodes:
		by_id[node["id"]] = node
	for lane in 3:
		(by_id["x_start"]["next"] as Array).append("x_1_%d" % lane)
	for row in range(1, rows):
		for lane in 3:
			var links: Array = by_id["x_%d_%d" % [row, lane]]["next"]
			links.append("x_%d_%d" % [row + 1, lane])
			var side := lane + (1 if rng.randf() < 0.5 else -1)
			if side < 0 or side > 2:
				side = lane + (1 if lane == 0 else -1)
			if rng.randf() < 0.6:
				links.append("x_%d_%d" % [row + 1, side])
	for lane in 3:
		(by_id["x_%d_%d" % [rows, lane]]["next"] as Array).append("x_exit")
	return {
		"id": map_id,
		"name": str(mission.get("name", template.get("name", ""))),
		"subtitle": str(mission.get("subtitle", template.get("subtitle", ""))),
		"map_type": "generated_expedition",
		"act": int(template.get("act", 1)),
		"battle_backdrop": str(template.get("battle_backdrop", "")),
		"terrains": (template.get("terrains", {}) as Dictionary).duplicate(true),
		"start_node_id": "x_start",
		"exit_node_id": "x_exit",
		"completion": (mission.get("completion", template.get("completion", {})) as Dictionary).duplicate(true),
		"nodes": nodes,
	}


const DEFAULT_WEIGHTS := {"combat": 5.0, "event": 2.5, "rest": 1.0, "treasure": 0.8, "merchant": 0.6}


static func _pick_type(spec: Dictionary, row: int, rows: int, rng: RandomNumberGenerator) -> Dictionary:
	var weights: Dictionary = DEFAULT_WEIGHTS.duplicate()
	weights.merge(spec.get("weights", {}), true)
	if row <= 1:
		return {"type": "combat"}
	var total := 0.0
	for type: String in weights:
		total += float(weights[type])
	var roll := rng.randf() * total
	for type: String in weights:
		roll -= float(weights[type])
		if roll <= 0.0:
			return {"type": type}
	return {"type": "combat"}


## Objective rooms in different lanes at spread depths, one elite in the last third, a rest or
## town at the middle and a rest in the row before the exit.
static func _place_specials(grid: Array, rows: int, objective: Dictionary, rng: RandomNumberGenerator) -> void:
	var lanes := [0, 1, 2]
	_shuffle(lanes, rng)
	var targets := clampi(int(objective.get("targets", 0)), 0, 3)
	for i in targets:
		var row := clampi(int(round(rows * (0.3 + 0.25 * i))), 2, rows - 1)
		grid[row - 1][lanes[i]] = {"type": "elite" if i == targets - 1 and bool(objective.get("last_is_elite", true)) else "combat", "objective": true}
	var mid := clampi(rows / 2, 2, rows - 1)
	var mid_lane: int = lanes[2] if targets < 3 else lanes[0]
	if not bool((grid[mid - 1][mid_lane] as Dictionary).get("objective", false)):
		grid[mid - 1][mid_lane] = {"type": "rest"}
	var late := clampi(int(round(rows * 0.7)), 2, rows - 1)
	for lane in 3:
		if not bool((grid[late - 1][lane] as Dictionary).get("objective", false)) and str(grid[late - 1][lane]["type"]) == "combat":
			grid[late - 1][lane] = {"type": "elite"}
			break
	for lane in 3:
		if not bool((grid[rows - 1][lane] as Dictionary).get("objective", false)):
			grid[rows - 1][lane] = {"type": "rest" if lane == 1 else str(grid[rows - 1][lane]["type"])}


static func _fill_room(node: Dictionary, cell: Dictionary, terrain: String, band: int, pools: Dictionary, objective: Dictionary, used: Dictionary, rng: RandomNumberGenerator) -> void:
	var type := str(cell["type"])
	if bool(cell.get("objective", false)):
		node["objective"] = true
		node["name"] = str(objective.get("target_name", "Objective"))
		band = maxi(band, 1)
	match type:
		"combat":
			node["encounter_id"] = _pick_fight(pools, terrain, band, used, rng)
			node["name"] = node.get("name", "Ambush")
		"elite":
			var elites: Array = (pools["elites"] as Dictionary).get(terrain, [])
			if elites.is_empty():
				for list: Variant in (pools["elites"] as Dictionary).values():
					elites = elites + (list as Array)
			if elites.is_empty():
				node["type"] = "combat"
				node["encounter_id"] = _pick_fight(pools, terrain, 2, used, rng)
			else:
				node["encounter_id"] = str(elites[rng.randi_range(0, elites.size() - 1)])
			node["name"] = node.get("name", "Lair")
		"event":
			var events: Array = (pools["events"] as Dictionary).get(terrain, [])
			if events.is_empty():
				node["type"] = "combat"
				node["encounter_id"] = _pick_fight(pools, terrain, band, used, rng)
				node["name"] = "Ambush"
			else:
				node["event_pool"] = str(events[rng.randi_range(0, events.size() - 1)])
				node["name"] = "Strange Signs"
		"rest":
			node["name"] = "Campfire"
		"treasure":
			var chests: Array = pools["treasures"]
			if chests.is_empty():
				node["type"] = "rest"
				node["name"] = "Campfire"
			else:
				node["treasure_id"] = str(chests[rng.randi_range(0, chests.size() - 1)])
				node["name"] = "Hidden Cache"
		"merchant":
			var shops: Array = pools["shops"]
			var towns: Array = pools["towns"]
			if not towns.is_empty() and rng.randf() < 0.5:
				node["type"] = "town"
				node["town_id"] = str(towns[rng.randi_range(0, towns.size() - 1)])
				node["name"] = str(DataRegistry.get_town(node["town_id"]).get("name", "Village"))
			elif not shops.is_empty():
				node["shop_id"] = str(shops[rng.randi_range(0, shops.size() - 1)])
				node["name"] = "Travelling Merchant"
			else:
				node["type"] = "rest"
				node["name"] = "Campfire"


static func _pick_fight(pools: Dictionary, terrain: String, band: int, used: Dictionary, rng: RandomNumberGenerator) -> String:
	var by_band: Array = (pools["fights"] as Dictionary).get(terrain, [[], [], []])
	var options: Array = []
	for offset in [0, -1, 1, -2, 2]:
		var b: int = band + offset
		if b >= 0 and b < by_band.size() and not (by_band[b] as Array).is_empty():
			options = by_band[b]
			break
	if options.is_empty():
		for list: Variant in (pools["fights"] as Dictionary).values():
			for band_list: Variant in list:
				options = options + (band_list as Array)
	if options.is_empty():
		return ""
	var fresh: Array = options.filter(func(id: String) -> bool: return not used.has(id))
	var pick: String = str((fresh if not fresh.is_empty() else options)[rng.randi_range(0, (fresh if not fresh.is_empty() else options).size() - 1)])
	used[pick] = true
	return pick


## A layout on the template's picture: lanes across, rows from the bottom (start) to the top (exit).
static func _layout_for(map_def: Dictionary, template: Dictionary, spec: Dictionary) -> Dictionary:
	var template_layout := DataRegistry.get_layout(str(template.get("id", "")))
	var rows := 0
	for node: Dictionary in map_def["nodes"]:
		rows = maxi(rows, int((node["position"] as Array)[0]))
	var layout := {
		"id": "%s_layout" % map_def["id"],
		"layout_for": map_def["id"],
		"background_asset": str(template_layout.get("background_asset", "")),
		"climb_asset": str(template_layout.get("climb_asset", "")),
		"canvas_height": maxf(1.0, float(spec.get("canvas_height", rows * 0.16))),
		"node_size": template_layout.get("node_size", [72, 72]),
		"default_bend": 0.03,
		"nodes": {},
	}
	if template_layout.get("altitude", {}) is Dictionary and not (template_layout.get("altitude", {}) as Dictionary).is_empty():
		layout["altitude"] = (template_layout["altitude"] as Dictionary).duplicate()
	for node: Dictionary in map_def["nodes"]:
		var pos: Array = node["position"]
		var share := float(pos[0]) / float(maxi(1, rows))
		var x: float = LANE_X[clampi(int(pos[1]), 0, 2)]
		if str(node["type"]) != "start" and str(node["type"]) != "exit":
			x += (hash(str(node["id"])) % 7 - 3) * 0.012
		layout["nodes"][node["id"]] = [snappedf(x, 0.001), snappedf(0.95 - share * 0.9, 0.001)]
	return layout
