extends ScreenBase
## Royal Castle map screen: graph view, party status, gold and path selection feedback.

## Width of the hint pill in the bottom-left corner of the illustrated map.
const HINT_WIDTH := 340.0

var _map_view: MapView
var _message: Label


func _build() -> void:
	var progress := GameState.map_progress
	GameState.end_room()  # Back on the map: no room is active; autosave the finished state.
	var has_art: bool = MapLayout.for_map(progress.graph.id) != null and MapLayout.for_map(progress.graph.id).get_background() != null
	_map_view = MapView.new()
	if has_art:
		# The illustration fills the whole screen behind the interface (immersive map).
		UIFactory.full_rect(_map_view)
		add_child(_map_view)
		move_child(_map_view, 1)  # Above the backdrop, below the accent line and the interface.
	var column := UIFactory.vbox(8)
	root.add_child(column)
	_message = UIFactory.label(_hint_text(), &"", true)
	if has_art:
		_build_art_layout(column, progress)
	else:
		_build_plain_layout(column, progress)
	if GameState.expedition != null:
		# Bottom-left, just above the hint pill, so it never covers rooms at the top of the chart.
		var bar := _make_expedition_bar()
		column.add_child(bar)
		column.move_child(bar, maxi(0, column.get_child_count() - 2) if has_art else 0)


## Campaign expeditions: the mission objective and the way home (retreat, or return in triumph once a
## clear-targets objective is met). Both ask for confirmation.
func _make_expedition_bar() -> Control:
	var expedition := GameState.expedition
	var pill := UIFactory.panel(UITheme.box(Color(UITheme.NAVY_DEEP, 0.88), UITheme.GOLD_DARK, 12, 2, 8))
	pill.name = "ExpeditionBar"
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := UIFactory.hbox(12)
	pill.add_child(row)
	var objective := UIFactory.label("◆ " + Objectives.describe(expedition.objective), &"", true)
	objective.name = "ObjectiveTracker"
	objective.custom_minimum_size.x = 260
	objective.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	objective.add_theme_color_override("font_color", UITheme.GOLD if Objectives.is_met(expedition.objective) else UITheme.IVORY)
	row.add_child(objective)
	var triumph := ExpeditionService.can_return_early()
	var home := UIFactory.button("Return Home" if triumph else "Retreat", triumph, Vector2(150, 44))
	home.name = "ReturnHomeButton" if triumph else "RetreatButton"
	home.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	home.pressed.connect(func() -> void:
		var title := "Return home in triumph?" if triumph else "Retreat to the castle?"
		var text := "The mission is done: the whole purse and the mission reward come home." if triumph else \
			"The mission stays unfinished. Half of the purse, everything found and one discovery come home."
		CastleUI.confirm(self, title, text, "Go Home", func() -> void:
			GameState.finish_expedition(ExpeditionState.OUTCOME_COMPLETED if triumph else ExpeditionState.OUTCOME_RETREATED)
			SceneRouter.go(SceneRouter.Screen.EXPEDITION_RESULTS)))
	row.add_child(home)
	return pill


## Map with a background (shown whole, never cropped): everything the interface needs sits in two dark pills in the bottom corners (over
## trees and walls) so the castle, its nodes and the baked title plate stay unobstructed.
func _build_art_layout(column: VBoxContainer, progress: MapProgress) -> void:
	# The interface layer lies over the map: containers must not take clicks, or the nodes behind
	# them would never be reached (PASS only forwards to parents, not to siblings underneath).
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(UIFactory.expander())
	_map_view.setup(progress)
	_map_view.node_pressed.connect(_on_node_pressed)
	progress.move_rejected.connect(_on_rejected)
	_map_view.set_corner_overlay(_make_legend_panel())  # Top-right of the art.
	var bottom := UIFactory.hbox(16)
	var message_pill := UIFactory.panel(UITheme.box(Color(UITheme.NAVY_DEEP, 0.85), UITheme.GOLD_DARK, 12, 2, 8))
	message_pill.custom_minimum_size.x = HINT_WIDTH
	message_pill.size_flags_vertical = Control.SIZE_SHRINK_END
	_message.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	message_pill.add_child(_message)
	bottom.add_child(message_pill)
	bottom.add_child(UIFactory.expander())
	var summary_pill := UIFactory.panel(UITheme.box(Color(UITheme.NAVY_DEEP, 0.85), UITheme.GOLD_DARK, 12, 2, 8))
	summary_pill.size_flags_vertical = Control.SIZE_SHRINK_END
	summary_pill.add_child(_make_party_summary())
	bottom.add_child(summary_pill)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)


func _build_plain_layout(column: VBoxContainer, progress: MapProgress) -> void:
	var top := UIFactory.hbox(16)
	var titles := UIFactory.vbox(0)
	titles.add_child(UIFactory.label(progress.graph.display_name, &"HeaderLabel"))
	titles.add_child(UIFactory.label(progress.graph.subtitle, &"DimLabel"))
	top.add_child(titles)
	top.add_child(UIFactory.expander())
	top.add_child(_make_party_summary())
	column.add_child(top)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_map_view)
	_map_view.setup(progress)
	_map_view.node_pressed.connect(_on_node_pressed)
	progress.move_rejected.connect(_on_rejected)
	column.add_child(_message)
	column.add_child(_make_legend())


func _make_party_summary() -> Control:
	var row := UIFactory.hbox(14)
	for member in GameState.party.members:
		var label := UIFactory.label("%s  %d/%d" % [member.definition.display_name, member.current_hp, member.max_hp])
		label.add_theme_color_override("font_color", member.definition.accent_color)
		row.add_child(label)
	row.add_child(UIFactory.icon("gold", 26))
	var gold := UIFactory.label("Gold: %d" % GameState.inventory.gold)
	gold.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(gold)
	var gear := UIFactory.button("Equipment" + (" (%d)" % GameState.inventory.equipment.size() if not GameState.inventory.equipment.is_empty() else ""), false, Vector2(0, 44))
	gear.name = "EquipmentButton"
	gear.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	gear.pressed.connect(func() -> void: SceneRouter.open_equipment(SceneRouter.Screen.MAP))
	row.add_child(gear)
	var deck := UIFactory.button("Deck (%d)" % GameState.party.get_total_deck_size(), false, Vector2(0, 44))
	deck.name = "DeckButton"
	deck.tooltip_text = "See every card of the party deck."
	deck.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	deck.pressed.connect(func() -> void: DeckViewer.open(self, GameState.party))
	row.add_child(deck)
	if not GameState.inventory.relics.is_empty():
		var relics := UIFactory.button("Relics (%d)" % GameState.inventory.relics.size(), false, Vector2(0, 44))
		relics.name = "RelicButton"
		relics.tooltip_text = "See the party's relics and what they do."
		relics.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		relics.pressed.connect(func() -> void: RelicViewer.open(self, GameState.inventory))
		row.add_child(relics)
	return row


## Legend entries: the five base types plus Elite / Chest only when the current map has such rooms.
func _legend_types() -> Array[String]:
	var types: Array[String] = [MapNodeData.TYPE_COMBAT, MapNodeData.TYPE_REST, MapNodeData.TYPE_MERCHANT, MapNodeData.TYPE_EVENT]
	for extra in [MapNodeData.TYPE_ELITE, MapNodeData.TYPE_TREASURE, MapNodeData.TYPE_TOWN, MapNodeData.TYPE_BOSS]:
		for node: MapNodeData in GameState.map_progress.graph.nodes.values():
			if node.type == extra:
				types.append(extra)
				break
	types.append(MapNodeData.TYPE_EXIT)
	var present: Array[String] = []
	for type in types:  # only list room types this map really has
		for node: MapNodeData in GameState.map_progress.graph.nodes.values():
			if node.type == type:
				present.append(type)
				break
	return present


func _make_legend() -> Control:
	var row := UIFactory.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for type in _legend_types():
		var style: Dictionary = MapNodeButton.TYPE_STYLE[type]
		var chip := UIFactory.hbox(4)
		chip.add_child(MapNodeButton.legend_icon(type, 24))
		var chip_label := UIFactory.label(str(style["label"]), &"DimLabel")
		chip_label.add_theme_color_override("font_color", style["color"])
		chip.add_child(chip_label)
		row.add_child(chip)
	return row


## Vertical legend card for the corner of the map art.
func _make_legend_panel() -> Control:
	var panel := UIFactory.panel(UITheme.compact_panel_style(0.3, Vector4(16, 12, 16, 12)))
	var column := UIFactory.vbox(2)
	panel.add_child(column)
	for type in _legend_types():
		var style: Dictionary = MapNodeButton.TYPE_STYLE[type]
		var chip := UIFactory.hbox(6)
		chip.add_child(MapNodeButton.legend_icon(type, 24))
		var chip_label := UIFactory.label(str(style["label"]), &"DimLabel")
		chip_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		chip_label.add_theme_color_override("font_color", style["color"])
		chip.add_child(chip_label)
		column.add_child(chip)
	return panel


func _hint_text() -> String:
	var progress := GameState.map_progress
	var chart := MapLayout.for_map(progress.graph.id)
	if chart != null and chart.canvas_height > 1.001:
		return "Gold-ringed rooms are your next options. Drag or scroll to see the whole route."
	if progress.visited_ids.size() == 1:
		return "Choose where to go next. Gold-ringed rooms connect to your position — tap one to enter."
	return "Gold-ringed rooms are your next options."


func _on_node_pressed(node_id: String) -> void:
	var progress := GameState.map_progress
	if progress.travel_to(node_id):
		SceneRouter.go_to_room(progress.graph.get_node_data(node_id))


func _on_rejected(_node_id: String, reason: String) -> void:
	_message.text = reason
	_message.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.3))


func _backdrop() -> Dictionary:
	# Art maps show the whole castle picture, so the letterbox is a plain dark gradient.
	var layout := MapLayout.for_map(GameState.map_progress.graph.id)
	if layout != null and layout.get_background() != null:
		return {}
	return current_room_backdrop()


func _backdrop_dim() -> float:
	return 0.7
