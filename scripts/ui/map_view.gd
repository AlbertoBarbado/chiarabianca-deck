class_name MapView
extends Control
## Renders any MapGraph + MapProgress, optionally over a background with a MapLayout.
##
## Data flow (nothing about a specific map is hardcoded here):
##   graph (data/maps/<map>.json)    -> nodes, connections, room types, progression
##   layout (data/maps/*_layout.json) -> normalised node positions, label sides, curve bends, background
##   progress (MapProgress)          -> node states and which paths are live / walked
## The background is a separate TextureRect that ignores input; it is shown whole (aspect kept,
## centred, never cropped) and normalised positions are measured on it, so nodes and paths stay
## aligned at any resolution. Without a layout the graph's own coordinates flow left to right.
## Taps emit `node_pressed`; the owner forwards them to MapProgress (invalid ones are rejected there).

signal node_pressed(node_id: String)

const MARGIN := Vector2(80, 70)
const LABEL_HEIGHT := 30.0
const LABEL_WIDTH := 170.0
const LABEL_GAP := 3.0
const CURVE_SAMPLES := 24
const DASH_LENGTH := 14.0
const DASH_GAP := 9.0
const DOT_SPACING := 15.0

# Path ink, tuned for a parchment background.
const COLOR_IDLE := Color(0.33, 0.22, 0.1, 0.55)
const COLOR_WALKED := Color(0.13, 0.22, 0.52, 0.95)
const COLOR_LIVE := Color(0.98, 0.78, 0.22, 1.0)
const COLOR_LIVE_OUTLINE := Color(0.22, 0.12, 0.02, 0.95)
const COLOR_LABEL := Color(0.08, 0.1, 0.25)
const COLOR_LABEL_OUTLINE := Color(0.99, 0.95, 0.82)

var _graph: MapGraph
var _progress: MapProgress
var _layout_data: MapLayout
var _buttons: Dictionary = {}  # node_id -> MapNodeButton
var _labels: Dictionary = {}   # node_id -> Label
var _background: TextureRect
var _line_layer: Control
var _art_rect: Rect2 = Rect2()
var _corner: Control = null
## Nodes, paths and name plates live in this clipped area. For a scrolling chart it is the inside of
## the picture frame; otherwise it is the whole view (positions are then the same as view positions).
var _clip: Control
var _scroll: float = 0.0
var _dragging: bool = false
var _drag_moved: float = 0.0
var _scroll_initialised: bool = false
## Tall picture under the paths that scrolls with a climbing chart (layout climb_asset), or null.
var _climb: TextureRect = null
## Altitude gauge at the left edge of a climbing chart (layout altitude), or null.
var _altimeter: Control = null

const FRAME_INSET := Vector2(0.045, 0.075)  # share of the picture covered by its painted frame
const WHEEL_STEP := 90.0
const DRAG_THRESHOLD := 8.0


func _init() -> void:
	clip_contents = true


## layout = null looks up the layout registered for the graph's id (none = plain layout).
func setup(progress: MapProgress, layout: MapLayout = null) -> void:
	_progress = progress
	_graph = progress.graph
	_layout_data = layout if layout != null else MapLayout.for_map(_graph.id)
	if _layout_data != null:
		var problems := _layout_data.validate(_graph)
		if not problems.is_empty():
			push_warning("MapView: invalid layout, using the plain layout: %s" % ", ".join(problems))
			_layout_data = null
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	refresh()


## Overlay for the top-right corner of the view (the node-type legend).
func set_corner_overlay(control: Control) -> void:
	_corner = control
	add_child(_corner)
	_layout()


func uses_layout() -> bool:
	return _layout_data != null


func has_background() -> bool:
	return _background != null


func get_layout() -> MapLayout:
	return _layout_data


## Rectangle (view coordinates) of the background picture; empty without one.
func get_art_rect() -> Rect2:
	return _art_rect if _background != null else Rect2()


func get_button(node_id: String) -> MapNodeButton:
	return _buttons.get(node_id) as MapNodeButton


func get_label(node_id: String) -> Label:
	return _labels.get(node_id) as Label


## Centre of a node in view coordinates.
func get_node_center(node_id: String) -> Vector2:
	var node := _graph.get_node_data(node_id)
	return _node_center(node) if node != null else Vector2.ZERO


## "from>to" for every connection of the graph; this is exactly what gets drawn.
func get_edges() -> Array[String]:
	var edges: Array[String] = []
	for node: MapNodeData in _graph.nodes.values():
		for next_id in node.next_ids:
			if _graph.get_node_data(next_id) != null:
				edges.append("%s>%s" % [node.id, next_id])
	return edges


func refresh() -> void:
	if _corner != null and _corner.get_parent() == self:
		remove_child(_corner)
	UIFactory.clear_children(self)
	_buttons.clear()
	_labels.clear()
	_background = null
	if _layout_data != null and _layout_data.get_background() != null:
		_background = TextureRect.new()
		_background.texture = _layout_data.get_background()
		_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_background.stretch_mode = TextureRect.STRETCH_SCALE
		_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # The picture never takes input.
		add_child(_background)
	_clip = Control.new()
	_clip.name = "ChartArea"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS if is_scrollable() else Control.MOUSE_FILTER_IGNORE
	_clip.gui_input.connect(_on_chart_input)
	add_child(_clip)
	_climb = null
	if is_scrollable() and _layout_data.get_climb_texture() != null:
		_climb = TextureRect.new()
		_climb.name = "ClimbPicture"
		_climb.texture = _layout_data.get_climb_texture()
		_climb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_climb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_climb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clip.add_child(_climb)
	_line_layer = Control.new()  # Paths sit above the background and below the nodes.
	_line_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_layer.draw.connect(_draw_paths)
	_clip.add_child(_line_layer)
	for node: MapNodeData in _graph.nodes.values():
		var button := MapNodeButton.new()
		button.setup(node, _progress.get_node_state(node.id), _graph.terrain_hint(node))
		button.pressed.connect(func() -> void: node_pressed.emit(node.id))
		if _layout_data != null:
			button.set_node_size(_layout_data.node_size)
		_clip.add_child(button)
		_buttons[node.id] = button
		var label := UIFactory.label(node.display_name, &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _background != null:
			# Name plate in the UI frame art (same style as the menus), not loose text on the picture.
			label.add_theme_stylebox_override("normal", UITheme.compact_button_style(Color(0.95, 0.95, 1.0, 0.96)))
			label.add_theme_color_override("font_color", UITheme.IVORY)
			label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL - 2)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var plate_font := UITheme.font(UITheme.WEIGHT_BUTTON)
			if plate_font != null:
				label.add_theme_font_override("font", plate_font)
			if _progress.get_node_state(node.id) == MapProgress.NodeState.UNAVAILABLE:
				label.modulate = Color(0.8, 0.8, 0.8, 0.82)
		_clip.add_child(label)
		_labels[node.id] = label
	_altimeter = null
	if is_scrollable() and not _layout_data.altitude.is_empty():
		_altimeter = Control.new()
		_altimeter.name = "Altimeter"
		_altimeter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_altimeter.draw.connect(_draw_altimeter)
		add_child(_altimeter)
	if _corner != null:
		add_child(_corner)
	_layout()


## Node centre in view coordinates: normalised layout position on the picture, or the graph's own
## coordinates spread over the view when there is no layout.
func _node_center(node: MapNodeData) -> Vector2:
	if _layout_data != null and _layout_data.has_position(node.id):
		var spot: Vector2 = _layout_data.nodes[node.id]
		var area := _art_rect if _background != null else Rect2(Vector2.ZERO, size)
		if is_scrollable():
			var chart := _chart_rect()
			return chart.position + Vector2(spot.x * chart.size.x, spot.y * _content_height() - _scroll)
		return area.position + spot * area.size
	var bounds := _graph.get_bounds()
	var usable := size - MARGIN * 2.0
	var u := 0.5 if bounds.size.y == 0.0 else (node.position.y - bounds.position.y) / bounds.size.y
	var v := 0.5 if bounds.size.x == 0.0 else (node.position.x - bounds.position.x) / bounds.size.x
	return MARGIN + Vector2(u * usable.x, v * usable.y)


func _layout() -> void:
	if _graph == null:
		return
	if _background != null:
		_art_rect = _fit_background()
		_background.position = _art_rect.position
		_background.size = _art_rect.size
	var chart := _chart_rect()
	_clip.position = chart.position
	_clip.size = chart.size
	_line_layer.position = Vector2.ZERO
	_line_layer.size = chart.size
	if is_scrollable() and not _scroll_initialised and chart.size.y > 0.0:
		_scroll_initialised = true
		center_on(_progress.current_node_id)  # open on the party's position
		return
	_scroll = clampf(_scroll, 0.0, max_scroll())
	if _climb != null:
		_climb.position = Vector2(0.0, -_scroll)
		_climb.size = Vector2(chart.size.x, _content_height())
	if _altimeter != null:
		_altimeter.position = chart.position + Vector2(10.0, chart.size.y * 0.1)
		_altimeter.size = Vector2(ALTIMETER_WIDTH, chart.size.y * 0.8)
		_altimeter.queue_redraw()
	for node_id: String in _buttons:
		var center := _node_center(_graph.get_node_data(node_id)) - chart.position  # chart-area coordinates
		var button: MapNodeButton = _buttons[node_id]
		button.position = center - button.size / 2.0
		_place_label(node_id, center, button.size)
	_line_layer.queue_redraw()
	if _corner != null:
		_corner.size = _corner.get_combined_minimum_size()
		_corner.position = Vector2(size.x - _corner.size.x - 8.0, 8.0)


func _place_label(node_id: String, center: Vector2, node_size: Vector2) -> void:
	var label: Label = _labels[node_id]
	var plate_width := LABEL_WIDTH if _background == null else clampf(label.get_minimum_size().x + 4.0, 70.0, 230.0)
	label.size = Vector2(plate_width, LABEL_HEIGHT)
	var side := _layout_data.get_label_side(node_id) if _layout_data != null else "below"
	match side:
		"above":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.position = center + Vector2(-plate_width / 2.0, -node_size.y / 2.0 - LABEL_HEIGHT - LABEL_GAP)
		"left":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.position = center + Vector2(-node_size.x / 2.0 - plate_width - LABEL_GAP, -LABEL_HEIGHT / 2.0)
		"right":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label.position = center + Vector2(node_size.x / 2.0 + LABEL_GAP, -LABEL_HEIGHT / 2.0)
		_:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.position = center + Vector2(-plate_width / 2.0, node_size.y / 2.0 + LABEL_GAP)


# --- Scrolling chart --------------------------------------------------------------------------

const ALTIMETER_WIDTH := 92.0


## Party's height on the layout's altitude scale (-1 without one).
func current_altitude() -> int:
	return _layout_data.altitude_at(_progress.current_node_id) if _layout_data != null else -1


## The altitude gauge: a thin rope from the foot (bottom) to the summit (top) with a marker and the
## party's height in metres; drawn over the scrolling chart, so the climb reads at a glance.
func _draw_altimeter() -> void:
	var height := _altimeter.size.y
	var x := 14.0
	var font := ThemeDB.fallback_font
	var unit := str(_layout_data.altitude.get("unit", "m"))
	var shadow := Color(0.02, 0.05, 0.1, 0.55)
	_altimeter.draw_rect(Rect2(x - 4.0, -6.0, 8.0, height + 12.0), shadow)
	_altimeter.draw_line(Vector2(x, 0.0), Vector2(x, height), Color(0.92, 0.97, 1.0, 0.95), 3.0)
	for i in 5:
		var y := height * i / 4.0
		_altimeter.draw_line(Vector2(x - 5.0, y), Vector2(x + 5.0, y), Color(0.92, 0.97, 1.0, 0.8), 2.0)
	var share := _layout_data.climb_share(_progress.current_node_id)
	var marker := Vector2(x, height * (1.0 - share))
	_altimeter.draw_circle(marker, 9.0, Color(0.1, 0.16, 0.3, 0.95))
	_altimeter.draw_circle(marker, 6.5, Color(0.98, 0.82, 0.32))
	var text := "%s %s" % [_thousands(current_altitude()), unit]
	_altimeter.draw_string_outline(font, marker + Vector2(16.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, shadow)
	_altimeter.draw_string(font, marker + Vector2(16.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1.0, 0.97, 0.88))
	var summit := "%s %s" % [_thousands(int(_layout_data.altitude.get("summit", 0))), unit]
	_altimeter.draw_string_outline(font, Vector2(x + 10.0, -10.0), summit, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, shadow)
	_altimeter.draw_string(font, Vector2(x + 10.0, -10.0), summit, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.86, 0.94, 1.0))


static func _thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## True when the layout's chart is taller than the picture: nodes and paths scroll, the picture stays.
func is_scrollable() -> bool:
	return _layout_data != null and _background != null and _layout_data.canvas_height > 1.001


## View rectangle that shows nodes and paths: inside the picture frame for a scrolling chart.
func _chart_rect() -> Rect2:
	if not is_scrollable():
		return Rect2(Vector2.ZERO, size)
	var inset := _art_rect.size * FRAME_INSET
	return Rect2(_art_rect.position + inset, _art_rect.size - inset * 2.0)


func _content_height() -> float:
	return _chart_rect().size.y * (_layout_data.canvas_height if is_scrollable() else 1.0)


func max_scroll() -> float:
	return maxf(0.0, _content_height() - _chart_rect().size.y) if is_scrollable() else 0.0


func get_scroll() -> float:
	return _scroll


func scroll_to(offset: float) -> void:
	_scroll = clampf(offset, 0.0, max_scroll())
	_layout()


## Scrolls so the node sits a little below the middle of the chart (upcoming rooms are above it).
func center_on(node_id: String) -> void:
	var layout_spot: Variant = _layout_data.nodes.get(node_id) if _layout_data != null else null
	if layout_spot == null or not is_scrollable():
		return
	scroll_to((layout_spot as Vector2).y * _content_height() - _chart_rect().size.y * 0.62)


## True when the node's medallion is fully inside the visible chart area.
func is_node_visible(node_id: String) -> bool:
	var button := get_button(node_id)
	return button != null and Rect2(Vector2.ZERO, _clip.size).grow(1.0).encloses(Rect2(button.position, button.size))


## Mouse wheel and drag (mouse or touch) scroll the chart. A press that does not move stays a tap.
func _on_chart_input(event: InputEvent) -> void:
	if not is_scrollable():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			scroll_to(_scroll - WHEEL_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			scroll_to(_scroll + WHEEL_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_drag_moved = 0.0
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += absf(event.relative.y)
		if _drag_moved >= DRAG_THRESHOLD:
			scroll_to(_scroll - event.relative.y)
	elif event is InputEventScreenDrag:
		scroll_to(_scroll - event.relative.y)


## Largest rectangle with the picture's aspect ratio that fits in this control, centred (no cropping).
func _fit_background() -> Rect2:
	var texture_size := _background.texture.get_size()
	var scale_factor := minf(size.x / texture_size.x, size.y / texture_size.y)
	var fitted := texture_size * scale_factor
	return Rect2((size - fitted) / 2.0, fitted)


## Points of the path for one graph edge: a gentle curve (quadratic Bezier) between the node centres.
func edge_points(from_id: String, to_id: String) -> PackedVector2Array:
	var a := get_node_center(from_id)
	var b := get_node_center(to_id)
	var bend := _layout_data.get_bend(from_id, to_id) if _layout_data != null else 0.0
	var control := (a + b) / 2.0 + (b - a).orthogonal() * bend
	var points := PackedVector2Array()
	for i in CURVE_SAMPLES + 1:
		var t := float(i) / CURVE_SAMPLES
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points


func _draw_paths() -> void:
	if _graph == null:
		return
	var offset := _clip.position  # edge_points are view coordinates; the layer draws in chart coordinates
	_line_layer.draw_set_transform(-offset)
	var walked_paths: Array[String] = []
	var idle_paths: Array[String] = []
	var live_paths: Array[String] = []
	for edge in get_edges():
		var ends := edge.split(">")
		if ends[0] == _progress.current_node_id and not _progress.visited_ids.has(ends[1]):
			live_paths.append(edge)
		elif _progress.visited_ids.has(ends[0]) and _progress.visited_ids.has(ends[1]):
			walked_paths.append(edge)
		else:
			idle_paths.append(edge)
	# Travel routes are trails of ink dots (board-game map style): faint for routes not open yet,
	# a solid blue trail where the party walked, bright gold beads for the choices open right now.
	for edge in idle_paths:
		var ends := edge.split(">")
		_draw_dots(edge_points(ends[0], ends[1]), COLOR_IDLE, 2.6, Color.TRANSPARENT)
	for edge in walked_paths:
		var ends := edge.split(">")
		var points := edge_points(ends[0], ends[1])
		_line_layer.draw_polyline(points, Color(COLOR_WALKED, 0.55), 3.0, true)
		_draw_dots(points, COLOR_WALKED, 3.6, Color(1, 1, 1, 0.5))
	for edge in live_paths:
		var ends := edge.split(">")
		_draw_dots(edge_points(ends[0], ends[1]), COLOR_LIVE, 4.6, COLOR_LIVE_OUTLINE)
	_draw_scroll_thumb()


## Thin gold thumb on the right edge of a scrolling chart: where the visible part sits in the whole route.
func _draw_scroll_thumb() -> void:
	if not is_scrollable() or max_scroll() <= 0.0:
		return
	var track_h := _clip.size.y - 16.0
	var thumb_h := maxf(28.0, track_h * _clip.size.y / _content_height())
	var top := 8.0 + (track_h - thumb_h) * (_scroll / max_scroll())
	var x := _clip.position.x + _clip.size.x - 7.0
	_line_layer.draw_line(Vector2(x, _clip.position.y + 8.0), Vector2(x, _clip.position.y + 8.0 + track_h), Color(0.1, 0.08, 0.05, 0.35), 4.0, true)
	_line_layer.draw_line(Vector2(x, _clip.position.y + top), Vector2(x, _clip.position.y + top + thumb_h), Color(0.95, 0.76, 0.3, 0.95), 4.0, true)


## Evenly spaced dots along a polyline (optional outline ring per dot).
func _draw_dots(points: PackedVector2Array, color: Color, radius: float, outline: Color) -> void:
	var carried := DOT_SPACING * 0.5
	for i in points.size() - 1:
		var from := points[i]
		var to := points[i + 1]
		var length := from.distance_to(to)
		var direction := (to - from) / maxf(length, 0.001)
		var at := carried
		while at <= length:
			var spot := from + direction * at
			if outline.a > 0.0:
				_line_layer.draw_circle(spot, radius + 1.8, outline)
			_line_layer.draw_circle(spot, radius, color)
			at += DOT_SPACING
		carried = at - length


## Dashed polyline (draw_dashed_line only handles single segments).
func _draw_dashed(points: PackedVector2Array, color: Color, width: float) -> void:
	var drawing := true
	var remaining := DASH_LENGTH
	for i in points.size() - 1:
		var from := points[i]
		var to := points[i + 1]
		var length := from.distance_to(to)
		var direction := (to - from) / maxf(length, 0.001)
		var travelled := 0.0
		while travelled < length:
			var step := minf(remaining, length - travelled)
			if drawing:
				_line_layer.draw_line(from + direction * travelled, from + direction * (travelled + step), color, width, true)
			travelled += step
			remaining -= step
			if remaining <= 0.001:
				drawing = not drawing
				remaining = DASH_LENGTH if drawing else DASH_GAP
