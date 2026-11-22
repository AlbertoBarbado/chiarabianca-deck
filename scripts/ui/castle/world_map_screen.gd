extends ScreenBase
## The war table: the world chart (regions from data/regions at their world positions, linked by
## the missions that open them), the selected region's details and its missions. Choosing an open
## mission leads to the expedition preparation screen. Nothing here is hard-coded per region.

const MARKER_SIZE := Vector2(168, 118)

var _chart: Control
var _detail: VBoxContainer
var _selected := ""
var _markers: Dictionary = {}


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.55


func _build() -> void:
	if GameState.campaign == null:
		SceneRouter.go.call_deferred(SceneRouter.Screen.MAIN_MENU)
		return
	var column := UIFactory.vbox(12)
	root.add_child(column)
	column.add_child(CastleUI.header("The War Table", "Choose where the sisters go next.", func() -> void: SceneRouter.go(SceneRouter.Screen.CASTLE_HUB)))
	var body: BoxContainer = UIFactory.vbox(12) if CastleUI.is_narrow(self) else UIFactory.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var chart_panel := UIFactory.panel(UITheme.box(Color(UITheme.NAVY_DEEP, 0.75), UITheme.GOLD_DARK, 16, 2, 10))
	chart_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart_panel.size_flags_stretch_ratio = 1.3
	chart_panel.custom_minimum_size = Vector2(0, 300)
	body.add_child(chart_panel)
	_chart = Control.new()
	_chart.name = "WorldChart"
	_chart.custom_minimum_size = Vector2(360, 280)
	_chart.draw.connect(_draw_links)
	_chart.resized.connect(_place_markers)
	chart_panel.add_child(_chart)
	var detail_scroll := UIFactory.scroll()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.custom_minimum_size = Vector2(380, 0)
	body.add_child(detail_scroll)
	_detail = UIFactory.vbox(10)
	_detail.name = "RegionDetail"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	for region in ExpeditionService.regions():
		var marker := _make_marker(region)
		_markers[str(region["id"])] = marker
		_chart.add_child(marker)
	_selected = SceneRouter.world_region_id if _markers.has(SceneRouter.world_region_id) else _first_open_region()
	_show_region(_selected)
	_place_markers.call_deferred()


func _first_open_region() -> String:
	var open := ""
	for region in ExpeditionService.regions():
		if ExpeditionService.region_unlocked(GameState.campaign, str(region["id"])):
			open = str(region["id"])  # the newest open region
	return open


func _make_marker(region: Dictionary) -> Button:
	var unlocked := ExpeditionService.region_unlocked(GameState.campaign, str(region["id"]))
	var button := Button.new()
	button.name = "Region_" + str(region["id"])
	button.custom_minimum_size = MARKER_SIZE
	button.size = MARKER_SIZE
	button.tooltip_text = str(region["name"])
	button.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), UITheme.GOLD_DARK if unlocked else Color(0.35, 0.35, 0.4), 12, 2, 4))
	button.add_theme_stylebox_override("hover", UITheme.box(Color(UITheme.NAVY, 0.95), UITheme.GOLD, 12, 3, 4))
	button.add_theme_stylebox_override("pressed", UITheme.box(Color(UITheme.NAVY_LIGHT, 0.95), UITheme.GOLD, 12, 3, 4))
	button.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 12, 3, 4))
	var art := TextureRect.new()
	art.texture = AssetCatalog.texture(str(region.get("art", "")))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(art)
	art.offset_left = 4
	art.offset_top = 4
	art.offset_right = -4
	art.offset_bottom = -30
	art.clip_contents = true
	art.modulate = Color.WHITE if unlocked else Color(0.35, 0.35, 0.42)
	button.add_child(art)
	var label := UIFactory.label(("" if unlocked else "🔒 ") + str(region["name"]), &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", UITheme.GOLD if unlocked else UITheme.IVORY_DIM)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -28
	label.offset_bottom = -4
	button.add_child(label)
	button.pressed.connect(_show_region.bind(str(region["id"])))
	return button


## Markers sit at the regions' world positions, kept inside the chart.
func _place_markers() -> void:
	if _chart == null:
		return
	var area := _chart.size
	var scale := clampf(minf(area.x / 760.0, area.y / 520.0), 0.62, 1.0)
	for region_id: String in _markers:
		var marker: Button = _markers[region_id]
		var pos: Array = DataRegistry.get_region(region_id).get("world_position", [0.5, 0.5])
		marker.size = MARKER_SIZE * scale
		marker.custom_minimum_size = marker.size
		var center := Vector2(float(pos[0]) * area.x, float(pos[1]) * area.y)
		marker.position = (center - marker.size / 2.0).clamp(Vector2.ZERO, (area - marker.size).max(Vector2.ZERO))
	_chart.queue_redraw()


## Roads between regions: from the region of each mission that opens a region to that region.
func _draw_links() -> void:
	for region in ExpeditionService.regions():
		var to_id := str(region["id"])
		for mission_id: Variant in (region.get("unlock", {}) as Dictionary).get("missions", []):
			var from_id := str(DataRegistry.get_mission(str(mission_id)).get("region_id", ""))
			if not _markers.has(from_id) or not _markers.has(to_id) or from_id == to_id:
				continue
			var a: Button = _markers[from_id]
			var b: Button = _markers[to_id]
			var open := ExpeditionService.region_unlocked(GameState.campaign, to_id)
			var color := Color(UITheme.GOLD, 0.85) if open else Color(0.6, 0.6, 0.7, 0.45)
			_chart.draw_dashed_line(a.position + a.size / 2.0, b.position + b.size / 2.0, color, 4.0 if open else 3.0, 14.0)


func _show_region(region_id: String) -> void:
	_selected = region_id
	SceneRouter.world_region_id = region_id
	UIFactory.clear_children(_detail)
	var region := DataRegistry.get_region(region_id)
	if region.is_empty():
		return
	var campaign := GameState.campaign
	var unlocked := ExpeditionService.region_unlocked(campaign, region_id)
	var heading := SectionHeading.new()
	heading.setup(str(region["name"]), false, false)
	_detail.add_child(heading)
	_detail.add_child(UIFactory.label(str(region.get("description", "")), &"", true))
	var state := campaign.region_state(region_id)
	var threat := UIFactory.label("Threat: %s  (%d)" % ["▲".repeat(int(state.get("threat", 0))) if int(state.get("threat", 0)) > 0 else "calm", int(state.get("threat", 0))], &"DimLabel", false)
	threat.name = "Threat"
	_detail.add_child(threat)
	if str(region.get("mechanics", "")) != "":
		_detail.add_child(UIFactory.label(str(region["mechanics"]), &"DimLabel", true))
	if not unlocked:
		var missing := Requirements.missing(campaign, region.get("unlock", {}))
		var lock := UIFactory.label("Locked: " + (missing[0] if not missing.is_empty() else "not yet reachable"), &"", true)
		lock.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.3))
		_detail.add_child(lock)
		return
	for mission in ExpeditionService.missions_of(region_id):
		_detail.add_child(_mission_card(mission))


func _mission_card(mission: Dictionary) -> Control:
	var campaign := GameState.campaign
	var mission_id := str(mission["id"])
	var reason := ExpeditionService.mission_lock_reason(campaign, mission_id)
	var panel := CastleUI.card_panel(6, UITheme.GOLD if reason == "" else Color(0.4, 0.4, 0.45))
	panel.name = "Mission_" + mission_id
	var column := CastleUI.column_of(panel)
	var top := UIFactory.hbox(8)
	var title := UIFactory.label(str(mission["name"]), &"", true)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	title.add_theme_color_override("font_color", UITheme.GOLD if reason == "" else UITheme.IVORY_DIM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if campaign.is_mission_completed(mission_id):
		top.add_child(CastleUI.pill("Completed", UITheme.GREEN))
	top.add_child(CastleUI.pill(_objective_label(mission), UITheme.MAGIC_BLUE))
	column.add_child(top)
	column.add_child(UIFactory.label(str(mission.get("description", "")), &"", true))
	var rewards: Dictionary = mission.get("rewards", {})
	var first: Dictionary = rewards.get("first_time", {}) if not campaign.is_mission_completed(mission_id) else {}
	var reward_text := "Danger %s   Reward: %d gold" % ["★".repeat(int(mission.get("difficulty", 1))), int(rewards.get("gold", 0)) + int(first.get("gold", 0))]
	var essence := int(rewards.get("essence", 0)) + int(first.get("essence", 0))
	if essence > 0:
		reward_text += ", ✦ %d Essence" % essence
	if not first.is_empty():
		reward_text += "  (first time)"
	column.add_child(UIFactory.label(reward_text, &"DimLabel", true))
	var go := UIFactory.button("Prepare ›" if reason == "" else reason, reason == "", Vector2(0, 52))
	go.name = "Prepare_" + mission_id
	go.disabled = reason != ""
	go.pressed.connect(func() -> void: SceneRouter.open_preparation(mission_id))
	column.add_child(go)
	return panel


static func _objective_label(mission: Dictionary) -> String:
	var objective: Dictionary = mission.get("objective", {})
	match str(objective.get("type", "")):
		Objectives.TYPE_BOSS_HUNT:
			return "Boss hunt"
		Objectives.TYPE_CLEAR_TARGETS:
			return "%s %d of %d" % [str(objective.get("verb", "Clear")), int(objective.get("required", 1)), int(objective.get("targets", 1))]
		_:
			return "Journey"
