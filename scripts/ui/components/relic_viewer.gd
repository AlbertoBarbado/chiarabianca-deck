class_name RelicViewer
extends ColorRect
## Full-screen overlay listing the party's relics with what each one does. Closes with the Close
## button, a tap on the dim background or Escape. Touch and mouse alike; it only reads the inventory.
##   RelicViewer.open(screen, GameState.inventory)

const Z := 120  # above map markers and screen chrome

var _relic_ids: Array = []


static func open(parent: Node, inventory: Inventory) -> RelicViewer:
	var existing := parent.get_node_or_null("RelicViewer") as RelicViewer
	if existing != null:
		return existing
	var viewer := RelicViewer.new()
	viewer.name = "RelicViewer"
	viewer._relic_ids = inventory.relics.duplicate() if inventory != null else []
	parent.add_child(viewer)
	return viewer


func _ready() -> void:
	color = Color(UITheme.NAVY_DEEP, 0.9)
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIFactory.full_rect(self)
	gui_input.connect(_on_background_input)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(center)
	add_child(center)
	var panel := UIFactory.panel()
	var viewport := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(640.0, viewport.x - 40.0), 0)
	center.add_child(panel)
	var column := UIFactory.vbox(10)
	panel.add_child(column)

	var header := UIFactory.hbox(12)
	header.add_child(UIFactory.label("Relics", &"HeaderLabel"))
	header.add_child(UIFactory.expander())
	var close := UIFactory.button("Close", true, Vector2(140, 48))
	close.name = "CloseRelics"
	close.pressed.connect(queue_free)
	header.add_child(close)
	column.add_child(header)

	var list := UIFactory.vbox(8)
	list.name = "RelicList"
	column.add_child(list)
	if _relic_ids.is_empty():
		list.add_child(UIFactory.label("No relics yet. Treasure rooms hold them.", &"DimLabel", true))
	for relic_id: Variant in _relic_ids:
		list.add_child(_make_row(str(relic_id)))


func _make_row(relic_id: String) -> Control:
	var item := DataRegistry.get_item(relic_id)
	var row := UIFactory.hbox(12)
	row.name = "Relic_" + relic_id
	var icon := RelicIcon.create(relic_id, 48)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := UIFactory.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIFactory.label(str(item.get("name", relic_id)))
	title.add_theme_color_override("font_color", RelicIcon.rarity_color(str(item.get("rarity", "common"))))
	text.add_child(title)
	text.add_child(UIFactory.label(str(item.get("description", "")), &"", true))
	row.add_child(text)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		queue_free()
