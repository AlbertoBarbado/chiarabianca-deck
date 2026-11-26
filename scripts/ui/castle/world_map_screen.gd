extends ScreenBase
## The war table: an illustrated atlas of the kingdom (catalog "bg_world_map") with each region from
## data/regions as a landmark medallion at its world position, linked by golden trails along the
## missions that open them. The selected region's details and missions sit on an enamel panel;
## choosing an open mission leads to the expedition preparation screen. Nothing here is hard-coded per
## region (positions, art, unlocks and missions are data). Without the atlas art the chart falls back to
## a plain panel with the same markers.

const ATLAS_ASPECT := 1536.0 / 864.0
const MARKER := 74.0
const REGION_ICONS := {
	"royal_castle": "icon_region_castle", "crystal_hollow": "icon_region_crystal", "enchanted_forest": "icon_region_forest",
	"sunlit_coast": "icon_region_coast", "frostpeak": "icon_region_frostpeak",
}

var _atlas: Control
var _detail: VBoxContainer
var _selected := ""
var _markers: Dictionary = {}
var _trail_phase := 0.0


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.35


func _menu_background() -> String:
	return "bg_library"


func _build() -> void:
	if GameState.campaign == null:
		SceneRouter.go.call_deferred(SceneRouter.Screen.MAIN_MENU)
		return
	var column := UIFactory.vbox(10)
	root.add_child(column)
	column.add_child(CastleUI.header("The War Table", "Choose where the sisters go next.", func() -> void: SceneRouter.go(SceneRouter.Screen.CASTLE_HUB)))
	var body: BoxContainer = UIFactory.vbox(10) if CastleUI.is_narrow(self) else UIFactory.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	# The atlas, framed in navy enamel and kept at its own aspect so markers sit on their landmarks.
	var frame := PanelContainer.new()
	frame.name = "AtlasFrame"
	var frame_style := UIKit.style("panel_navy_small")
	frame.add_theme_stylebox_override("panel", frame_style if frame_style != null else UITheme.box(Color(UITheme.NAVY_DEEP, 0.8), UITheme.GOLD_DARK, 12, 2, 8))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.9
	body.add_child(frame)
	# Cover: the atlas fills the frame (cropping a little at the sides on tall frames) and keeps its
	# aspect, so the markers placed in atlas coordinates stay on their landmarks.
	var ratio := AspectRatioContainer.new()
	ratio.ratio = ATLAS_ASPECT
	ratio.stretch_mode = AspectRatioContainer.STRETCH_COVER
	ratio.clip_contents = true
	frame.add_child(ratio)
	_atlas = Control.new()
	_atlas.name = "WorldChart"
	_atlas.clip_contents = true
	_atlas.custom_minimum_size = Vector2(360, 203)
	ratio.add_child(_atlas)
	var picture := UIKit.picture("bg_world_map")
	if picture != null:
		var map_rect := TextureRect.new()
		map_rect.name = "AtlasPicture"
		map_rect.texture = picture
		map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_rect.stretch_mode = TextureRect.STRETCH_SCALE
		map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIFactory.full_rect(map_rect)
		_atlas.add_child(map_rect)
	var trails := Control.new()
	trails.name = "Trails"
	trails.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(trails)
	trails.draw.connect(_draw_trails.bind(trails))
	_atlas.add_child(trails)
	for region in ExpeditionService.regions():
		var marker := _make_marker(region)
		_markers[str(region["id"])] = marker
		_atlas.add_child(marker)
	_atlas.resized.connect(_place_markers)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "DetailPanel"
	var detail_style := UIKit.style("panel_navy")
	detail_panel.add_theme_stylebox_override("panel", detail_style if detail_style != null else UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), UITheme.GOLD_DARK, 14, 2, 14))
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.custom_minimum_size = Vector2(380, 0)
	body.add_child(detail_panel)
	var detail_scroll := UIFactory.scroll()
	detail_panel.add_child(detail_scroll)
	_detail = UIFactory.vbox(10)
	_detail.name = "RegionDetail"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	_selected = SceneRouter.world_region_id if _markers.has(SceneRouter.world_region_id) else _first_open_region()
	_show_region(_selected)
	_place_markers.call_deferred()
	if SettingsStore.load_values().get("effects_quality", "full") == "full":
		# Light flowing along the open trails (cheap: one redraw of a few line segments per frame).
		var tween := create_tween().set_loops()
		tween.tween_method(func(v: float) -> void:
			_trail_phase = v
			trails.queue_redraw(), 0.0, 1.0, 2.4)


func _first_open_region() -> String:
	var open := ""
	for region in ExpeditionService.regions():
		if ExpeditionService.region_unlocked(GameState.campaign, str(region["id"])):
			open = str(region["id"])  # the newest open region
	return open


## A landmark medallion (diamond frame + region emblem) with a name ribbon under it.
func _make_marker(region: Dictionary) -> Button:
	var region_id := str(region["id"])
	var unlocked := ExpeditionService.region_unlocked(GameState.campaign, region_id)
	var button := Button.new()
	button.name = "Region_" + region_id
	button.tooltip_text = str(region["name"]) + ("" if unlocked else " (locked)")
	button.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.custom_minimum_size = Vector2(150, MARKER + 30)
	button.size = button.custom_minimum_size
	button.pivot_offset = button.size / 2.0
	var medallion := Control.new()
	medallion.name = "Medallion"
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.position = Vector2((150 - MARKER) / 2.0, 0)
	medallion.size = Vector2(MARKER, MARKER)
	button.add_child(medallion)
	var glow := TextureRect.new()
	glow.name = "SelectGlow"
	glow.texture = _glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = -Vector2.ONE * MARKER * 0.3
	glow.size = Vector2.ONE * MARKER * 1.6
	glow.visible = false
	medallion.add_child(glow)
	for entry in [["frame_diamond", 1.0], [str(REGION_ICONS.get(region_id, "")), 0.62]]:
		var texture := UIKit.picture(str(entry[0]))
		if texture == null:
			continue
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side := MARKER * float(entry[1])
		rect.position = Vector2.ONE * (MARKER - side) / 2.0
		rect.size = Vector2(side, side)
		if not unlocked:
			rect.modulate = Color(0.45, 0.45, 0.52)
		medallion.add_child(rect)
	if not unlocked:
		var lock_texture := UIKit.picture("icon_ui_lock")
		if lock_texture != null:
			var lock := TextureRect.new()
			lock.texture = lock_texture
			lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock.position = Vector2(MARKER * 0.6, MARKER * 0.55)
			lock.size = Vector2.ONE * MARKER * 0.4
			medallion.add_child(lock)
	var ribbon := PanelContainer.new()
	ribbon.name = "NameRibbon"
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ribbon_style := UIKit.style("ribbon_navy") if UIKit.has("ribbon_navy") else UIKit.style("panel_navy_small", 0.6)
	ribbon.add_theme_stylebox_override("panel", ribbon_style if ribbon_style != null else UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), UITheme.GOLD_DARK, 8, 1, 4))
	var label := UIFactory.label(str(region["name"]), &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("f6e7c1") if unlocked else UITheme.IVORY_DIM)
	ribbon.add_child(label)
	button.add_child(ribbon)
	ribbon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ribbon.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.mouse_entered.connect(func() -> void: button.create_tween().tween_property(button, "scale", Vector2.ONE * 1.08, 0.12))
	button.mouse_exited.connect(func() -> void: button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.12))
	button.pressed.connect(_show_region.bind(region_id))
	return button


static var _glow: GradientTexture2D


static func _glow_texture() -> GradientTexture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.86, 0.45, 0.85))
		gradient.set_color(1, Color(1.0, 0.7, 0.3, 0.0))
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow


## Markers sit at the regions' world positions on the atlas (normalised 0..1), scaled with it.
func _place_markers() -> void:
	if _atlas == null:
		return
	var area := _atlas.size
	var scale := clampf(area.x / 900.0, 0.62, 1.15)
	for region_id: String in _markers:
		var marker: Button = _markers[region_id]
		var pos: Array = DataRegistry.get_region(region_id).get("world_position", [0.5, 0.5])
		marker.scale = Vector2.ONE * scale
		marker.pivot_offset = Vector2(75, MARKER / 2.0)
		var center := Vector2(float(pos[0]) * area.x, float(pos[1]) * area.y)
		marker.position = center - Vector2(75, MARKER / 2.0)
		# The atlas may be cropped at the sides (cover fit): keep the whole marker in the visible part.
		var visible := _visible_rect()
		var half := Vector2(75, MARKER / 2.0) * scale
		var lo := visible.position + half - Vector2(75, MARKER / 2.0) + Vector2(4, 4)
		var hi := visible.end - Vector2(150, MARKER + 30) * scale + (Vector2(75, MARKER / 2.0) * scale - Vector2(75, MARKER / 2.0)) - Vector2(4, 4)
		marker.position = marker.position.clamp(lo, hi.max(lo))
	var trails := _atlas.get_node_or_null("Trails") as Control
	if trails != null:
		trails.queue_redraw()


## The part of the atlas the frame shows (the AspectRatioContainer clips the covered atlas).
func _visible_rect() -> Rect2:
	var holder := _atlas.get_parent() as Control
	var offset := (_atlas.size - holder.size) / 2.0
	return Rect2(offset.max(Vector2.ZERO), holder.size.min(_atlas.size))


func _marker_center(region_id: String) -> Vector2:
	var pos: Array = DataRegistry.get_region(region_id).get("world_position", [0.5, 0.5])
	return Vector2(float(pos[0]) * _atlas.size.x, float(pos[1]) * _atlas.size.y)


## Golden trails from the region of each mission that opens a region to that region: a soft dark
## underlay, a gold dotted path along a gentle curve, and (full effects) a light flowing along it.
## Trails to locked regions are faint.
func _draw_trails(canvas: Control) -> void:
	for region in ExpeditionService.regions():
		var to_id := str(region["id"])
		for mission_id: Variant in (region.get("unlock", {}) as Dictionary).get("missions", []):
			var from_id := str(DataRegistry.get_mission(str(mission_id)).get("region_id", ""))
			if not _markers.has(from_id) or not _markers.has(to_id) or from_id == to_id:
				continue
			var open := ExpeditionService.region_unlocked(GameState.campaign, to_id)
			var a := _marker_center(from_id)
			var b := _marker_center(to_id)
			var bend := (b - a).orthogonal().normalized() * (a.distance_to(b) * 0.12)
			var points := PackedVector2Array()
			for i in 25:
				var t := i / 24.0
				var mid := a.lerp(b, 0.5) + bend
				points.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
			canvas.draw_polyline(points, Color(0.08, 0.05, 0.15, 0.45 if open else 0.25), 7.0, true)
			for i in points.size():
				if i % 2 == 0:
					canvas.draw_circle(points[i], 3.2 if open else 2.4, Color(1.0, 0.84, 0.45, 0.95) if open else Color(0.85, 0.85, 0.95, 0.45))
			if open:
				var spot: Vector2 = points[int(_trail_phase * (points.size() - 1))]
				canvas.draw_circle(spot, 7.0, Color(1.0, 0.92, 0.6, 0.55))


func _show_region(region_id: String) -> void:
	_selected = region_id
	SceneRouter.world_region_id = region_id
	for id: String in _markers:
		var glow := (_markers[id] as Node).find_child("SelectGlow", true, false) as CanvasItem
		if glow != null:
			glow.visible = id == region_id
		var ribbon := (_markers[id] as Node).find_child("NameRibbon", true, false) as PanelContainer
		if ribbon != null and UIKit.has("ribbon_violet"):
			ribbon.add_theme_stylebox_override("panel", UIKit.style("ribbon_violet" if id == region_id else "ribbon_navy"))
	UIFactory.clear_children(_detail)
	var region := DataRegistry.get_region(region_id)
	if region.is_empty():
		return
	var campaign := GameState.campaign
	var unlocked := ExpeditionService.region_unlocked(campaign, region_id)
	var heading := SectionHeading.new()
	heading.setup(str(region["name"]), false, false)
	_detail.add_child(heading)
	var art := UIKit.picture(str(region.get("art", "")))
	if art != null:
		var banner := TextureRect.new()
		banner.name = "RegionArt"
		banner.texture = art
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		banner.custom_minimum_size = Vector2(0, 110)
		banner.clip_contents = true
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			banner.modulate = Color(0.5, 0.5, 0.58)
		_detail.add_child(banner)
	_detail.add_child(UIFactory.label(str(region.get("description", "")), &"", true))
	var state := campaign.region_state(region_id)
	var threat_value := int(state.get("threat", 0))
	var threat := UIFactory.label("Threat  %s" % ("▲".repeat(threat_value) if threat_value > 0 else "calm"), &"", false)
	threat.name = "Threat"
	threat.add_theme_color_override("font_color", Color("ff9a8a") if threat_value >= 3 else UITheme.LAVENDER)
	_detail.add_child(threat)
	if str(region.get("mechanics", "")) != "":
		_detail.add_child(UIFactory.label(str(region["mechanics"]), &"DimLabel", true))
	if not unlocked:
		var missing := Requirements.missing(campaign, region.get("unlock", {}))
		var lock := UIFactory.label("🔒 " + (missing[0] if not missing.is_empty() else "Not yet reachable"), &"", true)
		lock.add_theme_color_override("font_color", Color("ffb3a8"))
		_detail.add_child(lock)
		return
	for mission in ExpeditionService.missions_of(region_id):
		_detail.add_child(_mission_card(mission))


## A mission as a parchment card: seal, name, objective, danger, rewards with icons and the action.
func _mission_card(mission: Dictionary) -> Control:
	var campaign := GameState.campaign
	var mission_id := str(mission["id"])
	var reason := ExpeditionService.mission_lock_reason(campaign, mission_id)
	var kit := UIKit.has("plaque_parchment")
	var panel := PanelContainer.new()
	panel.name = "Mission_" + mission_id
	panel.add_theme_stylebox_override("panel", (UIKit.style("plaque_parchment") if reason == "" else UIKit.style("plaque_locked")) if kit else UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), UITheme.GOLD_DARK, 12, 2, 12))
	var column := UIFactory.vbox(4)
	panel.add_child(column)
	var ink := UITheme.INK if kit and reason == "" else UITheme.IVORY
	var soft := UITheme.INK_SOFT if kit and reason == "" else UITheme.IVORY_DIM
	var top := UIFactory.hbox(8)
	var seal := UIKit.picture("icon_ui_mission")
	if seal != null:
		var seal_rect := TextureRect.new()
		seal_rect.texture = seal
		seal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seal_rect.custom_minimum_size = Vector2(36, 36)
		seal_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(seal_rect)
	var title := UIFactory.label(str(mission["name"]), &"", true)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 1)
	title.add_theme_color_override("font_color", ink)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	column.add_child(top)
	# Level gate and contract rank.
	var tags := HFlowContainer.new()
	tags.name = "Tags"
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 4)
	tags.add_child(CastleUI.pill(_objective_label(mission), UITheme.VIOLET_LIGHT, kit and reason == ""))
	if campaign.is_mission_completed(mission_id):
		tags.add_child(CastleUI.pill("Completed", UITheme.GREEN, kit and reason == ""))
	var level := int((mission.get("unlock", {}) as Dictionary).get("level", 1))
	var level_ok := Levels.party_level(campaign) >= level
	var level_pill := CastleUI.pill("Level %d" % level, UITheme.GREEN if level_ok else UITheme.CRIMSON, kit and reason == "")
	level_pill.name = "LevelReq"
	level_pill.tooltip_text = "Needs party level %d (yours: %d)" % [level, Levels.party_level(campaign)]
	level_pill.mouse_filter = Control.MOUSE_FILTER_PASS
	tags.add_child(level_pill)
	if Contracts.is_contract(mission):
		var rank := CastleUI.pill("Contract · Rank %d" % int(mission["contract"]["tier"]), UITheme.GOLD_DARK, kit and reason == "")
		rank.name = "ContractRank"
		rank.tooltip_text = "A new contract is posted here after each one you complete: higher ranks need a higher level, field tougher foes and pay more."
		rank.mouse_filter = Control.MOUSE_FILTER_PASS
		tags.add_child(rank)
	column.add_child(tags)
	var description := UIFactory.label(str(mission.get("description", "")), &"", true)
	description.add_theme_color_override("font_color", soft)
	description.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	column.add_child(description)
	var rewards: Dictionary = mission.get("rewards", {})
	var first: Dictionary = rewards.get("first_time", {}) if not campaign.is_mission_completed(mission_id) else {}
	var row := UIFactory.hbox(10)
	row.name = "Rewards"
	var danger := UIFactory.label("Danger " + "★".repeat(int(mission.get("difficulty", 1))), &"", false)
	danger.add_theme_color_override("font_color", Color("b23a48") if kit and reason == "" else Color("ff9a8a"))
	row.add_child(danger)
	row.add_child(UIFactory.expander())
	_reward(row, "icon_res_gold", str(int(rewards.get("gold", 0)) + int(first.get("gold", 0))), ink)
	var essence := int(rewards.get("essence", 0)) + int(first.get("essence", 0))
	if essence > 0:
		_reward(row, "icon_res_essence", str(essence), ink)
	if not first.is_empty():
		var tag := UIFactory.label("first time", &"", false)
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", soft)
		row.add_child(tag)
	column.add_child(row)
	var go := UIFactory.button("Prepare ›" if reason == "" else reason, reason == "", Vector2(0, 50))
	go.name = "Prepare_" + mission_id
	go.disabled = reason != ""
	go.pressed.connect(func() -> void: SceneRouter.open_preparation(mission_id))
	column.add_child(go)
	return panel


func _reward(row: HBoxContainer, icon_id: String, text: String, color: Color) -> void:
	var texture := UIKit.picture(icon_id)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(24, 24)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rect)
	var label := UIFactory.label(text, &"", false)
	label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	label.add_theme_color_override("font_color", color)
	row.add_child(label)


static func _objective_label(mission: Dictionary) -> String:
	var objective: Dictionary = mission.get("objective", {})
	match str(objective.get("type", "")):
		Objectives.TYPE_BOSS_HUNT:
			return "Boss hunt"
		Objectives.TYPE_CLEAR_TARGETS:
			return "%s %d of %d" % [str(objective.get("verb", "Clear")), int(objective.get("required", 1)), int(objective.get("targets", 1))]
		_:
			return "Journey"
