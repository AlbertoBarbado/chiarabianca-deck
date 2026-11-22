extends SceneTree
## Milestone 4C tests: the data-driven illustrated map (layout validation, background, node and
## path rendering, states, aspect ratios, input). Run:
##   godot --path . --script res://tests/map/run_map_view_tests.gd      (windowed: real mouse + touch)
##   godot --headless --path . --script res://tests/map/run_map_view_tests.gd   (signal fallback)

const MAP_ID := "royal_castle_tutorial"
## Window sizes: desktop, 4:3 tablet, ultrawide and two phone landscape sizes. The project uses
## canvas_items stretch with "expand" (1280x720 design), so the map sees the window divided by
## min(w / 1280, h / 720): see _virtual_size.
const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1024, 768), Vector2(1920, 1080), Vector2(2560, 1080), Vector2(844, 390), Vector2(667, 375)]
const EXPECTED_EDGES: Array[String] = [
	"royal_chambers>west_gallery", "royal_chambers>training_yard", "west_gallery>west_training",
	"west_gallery>central_courtyard", "training_yard>central_courtyard", "training_yard>east_armory",
	"west_training>central_courtyard", "central_courtyard>royal_library", "central_courtyard>east_armory",
	"east_armory>throne_approach", "royal_library>throne_approach", "throne_approach>castle_exit",
]
const EXPECTED_TYPES := {
	"royal_chambers": "start", "west_gallery": "rest", "training_yard": "combat", "west_training": "combat",
	"central_courtyard": "event", "east_armory": "merchant", "royal_library": "rest", "throne_approach": "combat", "castle_exit": "exit",
}

var _failures: int = 0
var _checks: int = 0
var _view: MapView
var _progress: MapProgress
var _holder: Control


func _initialize() -> void:
	_run()


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _run() -> void:
	DataRegistry.reload()
	AssetCatalog.reload()
	_test_graph_untouched()
	_test_layout_validation()
	await _build_view(Vector2(1280, 720))
	_test_background()
	_test_nodes()
	_test_paths()
	await _test_aspect_ratios()
	await _test_reusable_renderer()
	await _test_states_and_interaction()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _virtual_size(window: Vector2) -> Vector2:
	return window / minf(window.x / 1280.0, window.y / 720.0)


func _graph() -> MapGraph:
	return MapGraph.from_dict(DataRegistry.get_map(MAP_ID))


func _build_view(size_value: Vector2) -> void:
	if _holder != null:
		_holder.queue_free()
	_holder = Control.new()
	root.add_child(_holder)
	_progress = MapProgress.new(_graph())
	_view = MapView.new()
	_holder.add_child(_view)
	_view.size = size_value
	_view.setup(_progress)
	await process_frame
	await process_frame


func _test_graph_untouched() -> void:
	print("Graph is unchanged")
	var map := DataRegistry.get_map(MAP_ID)
	var edges: Array[String] = []
	var types_ok := true
	for node: Dictionary in map["nodes"]:
		types_ok = types_ok and EXPECTED_TYPES.get(str(node["id"]), "") == str(node["type"])
		for next_id in node["next"]:
			edges.append("%s>%s" % [node["id"], next_id])
	edges.sort()
	var expected := EXPECTED_EDGES.duplicate()
	expected.sort()
	check(edges == expected, "the map JSON has exactly the 12 specified edges")
	check(types_ok and map["nodes"].size() == 9 and map["start_node_id"] == "royal_chambers" and map["exit_node_id"] == "castle_exit", "nine nodes with the specified ids and room types, no boss")
	check(DataRegistry.counts()["maps"] == 6 and DataRegistry.maps.has("frostpeak") and DataRegistry.maps.has("sunlit_coast") and DataRegistry.maps.has("crystal_hollow_demo") and DataRegistry.maps.has("castle_elite_demo") and DataRegistry.maps.has("enchanted_forest") and not DataRegistry.get_layout(MAP_ID).is_empty(), "the layout is registered as a layout, not as a map (6 maps: the castle, the elite demo route, the forest, the coast, the crystal cave and Frostpeak)")
	check(not map.has("layout_for"), "the graph JSON contains no layout data")


func _test_layout_validation() -> void:
	print("Layout validation")
	var graph := _graph()
	var layout := MapLayout.for_map(MAP_ID)
	check(layout != null and layout.validate(graph).is_empty(), "the Royal Castle layout is valid for its graph")
	var every_node := true
	for node_id: String in graph.nodes:
		every_node = every_node and layout.has_position(node_id)
	check(every_node and layout.nodes.size() == graph.nodes.size(), "every graph node has a layout position, and no extra ones")
	var in_bounds := true
	for spot: Vector2 in layout.nodes.values():
		in_bounds = in_bounds and spot.x >= 0.0 and spot.x <= 1.0 and spot.y >= 0.0 and spot.y <= 1.0
	check(in_bounds, "all node positions are normalised (0..1)")
	var data := DataRegistry.get_layout(MAP_ID).duplicate(true)
	data["nodes"].erase("castle_exit")
	check(MapLayout.from_dict(data).validate(graph).size() == 1, "a missing node position is reported")
	data = DataRegistry.get_layout(MAP_ID).duplicate(true)
	data["nodes"]["royal_library"] = [1.4, 0.2]
	data["nodes"]["ghost_room"] = [0.5, 0.5]
	check(MapLayout.from_dict(data).validate(graph).size() == 2, "out-of-range positions and unknown nodes are reported")
	data = DataRegistry.get_layout(MAP_ID).duplicate(true)
	data["bends"] = {"royal_chambers>castle_exit": 0.2}
	check(MapLayout.from_dict(data).validate(graph).size() == 1, "a curve for a connection that is not in the graph is reported")
	var texture := layout.get_background()
	check(texture != null and layout.background_asset == "map_royal_castle" and texture.get_size() == Vector2(1152, 648), "the illustrated castle map loads (1152x648)")
	check(AssetCatalog.get_entry("map_royal_castle").get("release_cleared", true) == false, "the map picture is registered as not release-cleared")
	check(AssetCatalog.texture("map_royal_castle_background") != null, "the older parchment picture is kept in the catalog")


func _test_background() -> void:
	print("Background")
	check(_view.uses_layout() and _view.has_background(), "the map view shows the background through the layout")
	var background := _view.get_child(0) as TextureRect
	check(background != null and background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the background ignores mouse and touch input")
	var chart := _view.get_child(1)
	var button := _view.get_button("royal_chambers")
	check(chart.name == "ChartArea" and button.get_parent() == chart and chart.get_child(0).get_index() < button.get_index(), "paths are drawn above the background and behind the nodes (inside the chart area)")


func _test_nodes() -> void:
	print("Nodes")
	var all_visible := true
	for node_id: String in EXPECTED_TYPES:
		var button := _view.get_button(node_id)
		all_visible = all_visible and button != null and button.is_visible_in_tree() and Rect2(Vector2.ZERO, _view.size).encloses(Rect2(button.position, button.size))
	check(all_visible, "all nine nodes are visible and not clipped at the view edges")
	var chambers := _view.get_node_center("royal_chambers")
	var exit_center := _view.get_node_center("castle_exit")
	var art := _view.get_art_rect()
	check(chambers.y > art.position.y + art.size.y * 0.7 and exit_center.y < art.position.y + art.size.y * 0.3, "the start is in the lower part and the exit in the upper part of the map")
	var west := _view.get_node_center("west_gallery")
	var east := _view.get_node_center("training_yard")
	check(west.x < chambers.x - 60.0 and east.x > chambers.x + 60.0, "the two first branches are visually distinct (left and right)")
	var looks := {}
	for node_id: String in EXPECTED_TYPES:
		var button := _view.get_button(node_id)
		looks[button.node_data.type] = "%s|%s" % [button.type_label, button.emblem != null]
	check(looks.size() == 6, "all six room types are drawn with their own look")


func _test_paths() -> void:
	print("Paths")
	var drawn := _view.get_edges()
	drawn.sort()
	var expected := EXPECTED_EDGES.duplicate()
	expected.sort()
	check(drawn == expected, "exactly the graph's 12 connections are rendered")
	var graph := _graph()
	var real := true
	for edge in drawn:
		var ends := edge.split(">")
		real = real and graph.get_node_data(ends[0]) != null and graph.get_node_data(ends[0]).next_ids.has(ends[1])
	check(real, "every rendered connection exists in the graph")
	var crossings: Array[String] = []
	for edge in drawn:
		var ends := edge.split(">")
		var edge_pts := _view.edge_points(ends[0], ends[1])
		for other: String in EXPECTED_TYPES:
			if other == ends[0] or other == ends[1]:
				continue
			for point in edge_pts:
				if point.distance_to(_view.get_node_center(other)) < _view.get_layout().node_size.x * 0.5:
					crossings.append("%s through %s" % [edge, other])
					break
	check(crossings.is_empty(), "no path runs through an unrelated node (%s)" % "; ".join(crossings))
	var sample := _view.edge_points("royal_chambers", "training_yard")
	check(sample[0].distance_to(_view.get_node_center("royal_chambers")) < 0.5 and sample[sample.size() - 1].distance_to(_view.get_node_center("training_yard")) < 0.5, "a path starts and ends exactly on its two nodes")


func _label_rect(node_id: String) -> Rect2:
	var label := _view.get_label(node_id)
	var width := label.get_minimum_size().x
	var rect := Rect2(label.position, Vector2(width, label.size.y))
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			rect.position.x = label.position.x + (label.size.x - width) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			rect.position.x = label.position.x + label.size.x - width
	return rect


func _test_aspect_ratios() -> void:
	print("Desktop, tablet, ultrawide and phone aspect ratios")
	var ratio := 1672.0 / 941.0
	var layout := MapLayout.for_map(MAP_ID)
	for window in SIZES:
		var size_value := _virtual_size(window)
		await _build_view(size_value)
		var tag := "%dx%d window (%dx%d virtual)" % [window.x, window.y, size_value.x, size_value.y]
		var rect := _view.get_art_rect()
		check(absf(rect.size.x / rect.size.y - ratio) < 0.01 and Rect2(Vector2.ZERO, size_value).grow(0.5).encloses(rect) and rect.get_center().distance_to(size_value / 2.0) < 1.0, "%s: background keeps its aspect ratio, is centred and never cropped" % tag)
		var aligned := true
		var unclipped := true
		for node_id: String in EXPECTED_TYPES:
			var expected_centre := rect.position + (layout.nodes[node_id] as Vector2) * rect.size
			var button := _view.get_button(node_id)
			aligned = aligned and expected_centre.distance_to(button.position + button.size / 2.0) < 0.6
			unclipped = unclipped and Rect2(Vector2.ZERO, size_value).encloses(Rect2(button.position, button.size)) and Rect2(Vector2.ZERO, size_value).encloses(_label_rect(node_id))
		check(aligned, "%s: every node stays aligned with its normalised position" % tag)
		check(unclipped, "%s: no node or label is clipped at the screen edges" % tag)
		var path_ok := true
		for edge in EXPECTED_EDGES:
			var ends := edge.split(">")
			var pts := _view.edge_points(ends[0], ends[1])
			path_ok = path_ok and pts[0].distance_to(_view.get_node_center(ends[0])) < 0.6 and pts[pts.size() - 1].distance_to(_view.get_node_center(ends[1])) < 0.6
		check(path_ok, "%s: paths stay attached to their nodes" % tag)
		var overlaps: Array[String] = []
		for a: String in EXPECTED_TYPES:
			var label_rect := _label_rect(a)
			for b: String in EXPECTED_TYPES:
				var button_rect := Rect2(_view.get_button(b).position, _view.get_button(b).size)
				if label_rect.intersects(button_rect):
					overlaps.append("%s label over %s" % [a, b])
				if a < b and Rect2(_view.get_button(a).position, _view.get_button(a).size).intersects(button_rect):
					overlaps.append("%s node over %s" % [a, b])
		check(overlaps.is_empty(), "%s: no node or room name overlaps another node (%s)" % [tag, "; ".join(overlaps)])
	var phone_scale := minf(844.0 / 1280.0, 390.0 / 720.0)
	check(layout.node_size.x * phone_scale >= 44.0, "nodes stay at least 44 physical px wide on an 844x390 phone (%.1f)" % (layout.node_size.x * phone_scale))


## A different graph and layout drawn by the same MapView: no Royal Castle knowledge in the renderer.
func _test_reusable_renderer() -> void:
	print("Reusable renderer")
	var graph := MapGraph.from_dict({
		"id": "test_map", "name": "Test", "subtitle": "", "start_node_id": "a", "exit_node_id": "c",
		"nodes": [
			{"id": "a", "type": "start", "name": "A", "position": [0, 0], "next": ["b"]},
			{"id": "b", "type": "combat", "name": "B", "position": [0, 1], "encounter_id": "castle_training_01", "next": ["c"]},
			{"id": "c", "type": "exit", "name": "C", "position": [0, 2], "next": []},
		]})
	var layout := MapLayout.from_dict({"layout_for": "test_map", "background_asset": "map_royal_castle_background", "nodes": {"a": [0.2, 0.8], "b": [0.5, 0.5], "c": [0.8, 0.2]}})
	check(layout.validate(graph).is_empty(), "another map's layout validates against its own graph")
	var holder := Control.new()
	root.add_child(holder)
	var view := MapView.new()
	holder.add_child(view)
	view.size = Vector2(1000, 600)
	view.setup(MapProgress.new(graph), layout)
	await process_frame
	check(view.get_edges() == ["a>b", "b>c"] and view.get_button("b") != null and view.has_background(), "the same renderer draws a different graph with its own layout")
	var broken := MapLayout.from_dict({"layout_for": "test_map", "nodes": {"a": [0.2, 0.8]}})
	var plain := MapView.new()
	holder.add_child(plain)
	plain.size = Vector2(1000, 600)
	plain.setup(MapProgress.new(graph), broken)
	await process_frame
	check(not plain.uses_layout() and plain.get_button("c") != null, "an invalid layout falls back to the plain graph layout instead of breaking the map")
	holder.queue_free()


func _tap(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		_click(button.get_global_rect().get_center())


func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func _test_states_and_interaction() -> void:
	print("States and interaction")
	await _build_view(Vector2(1280, 720))
	var rejected: Array[String] = []
	_view.node_pressed.connect(func(id: String) -> void: _progress.travel_to(id))  # The map screen's call.
	_progress.move_rejected.connect(func(id: String, _why: String) -> void: rejected.append(id))
	check(_view.get_button("royal_chambers").state == MapProgress.NodeState.CURRENT, "the start node is shown as current")
	check(_view.get_button("west_gallery").state == MapProgress.NodeState.AVAILABLE and _view.get_button("training_yard").state == MapProgress.NodeState.AVAILABLE, "the two connected rooms are shown as available")
	var unavailable := _view.get_button("castle_exit")
	check(unavailable.state == MapProgress.NodeState.UNAVAILABLE and unavailable.modulate.a < 1.0, "unreachable rooms are shown dimmed")
	_tap(unavailable)
	await process_frame
	await process_frame
	check(_progress.current_node_id == "royal_chambers" and rejected.has("castle_exit"), "selecting an invalid (unconnected) node is rejected and the party does not move")
	_click(_view.get_art_rect().position + Vector2(40, 120))
	await process_frame
	check(_progress.current_node_id == "royal_chambers", "clicking the background does nothing")
	_tap(_view.get_button("training_yard"))
	await process_frame
	await process_frame
	check(_progress.current_node_id == "training_yard", "clicking an available node moves along the valid connection")
	_view.refresh()
	await process_frame
	var done := _view.get_button("royal_chambers")
	check(done.state == MapProgress.NodeState.VISITED and done.modulate.a == 1.0 and _view.get_button("training_yard").state == MapProgress.NodeState.CURRENT, "the finished room shows as completed and the new room as current")
	check(_view.get_button("central_courtyard").state == MapProgress.NodeState.AVAILABLE and _view.get_button("east_armory").state == MapProgress.NodeState.AVAILABLE and _view.get_button("west_gallery").state == MapProgress.NodeState.UNAVAILABLE, "the new choices are available and the branch not taken is locked")
	_tap(_view.get_button("west_gallery"))
	await process_frame
	await process_frame
	check(_progress.current_node_id == "training_yard", "going to a room on the other branch is rejected")
	if DisplayServer.get_name() == "headless":
		print("  skip touch tap check (needs a window: run without --headless)")
		return
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = _view.get_button("central_courtyard").get_global_rect().get_center()
	touch.pressed = true
	Input.parse_input_event(touch)
	var touch_up := touch.duplicate() as InputEventScreenTouch
	touch_up.pressed = false
	Input.parse_input_event(touch_up)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	check(_progress.current_node_id == "central_courtyard", "a touch tap on an available node moves there (touch emulated as mouse)")
