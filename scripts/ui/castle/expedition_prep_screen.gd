extends ScreenBase
## Expedition preparation for one mission (SceneRouter.mission_id), laid out like a war-table brief
## (docs/ART_DIRECTION.md): the mission on a parchment card with its region's painting, objective,
## danger and rewards; each sister's card with her figure, specializations, prepared deck (and saved
## presets) and gear; the loadout with the potion belt as gold sockets and the carried relics; and
## the screen's single violet action, "Begin Expedition", which starts the expedition
## (ExpeditionService.start) once nothing blocks it. Narrow screens stack the three columns.

const COLUMN_WIDTH := 300.0
const SOCKET_SIZE := 46.0

var _loadout: Dictionary = {}
var _problems_box: VBoxContainer
var _embark: Button
var _belt_label: Label
var _sockets: HFlowContainer
var _potion_rows: VBoxContainer
var _relic_slot: VBoxContainer


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.5


func _menu_background() -> String:
	return "bg_world_map"


func _build() -> void:
	var campaign := GameState.campaign
	var mission := DataRegistry.get_mission(SceneRouter.mission_id)
	if campaign == null or mission.is_empty():
		SceneRouter.go.call_deferred(SceneRouter.Screen.CASTLE_HUB if campaign != null else SceneRouter.Screen.MAIN_MENU)
		return
	_loadout = Apothecary.default_loadout(campaign)
	var narrow := CastleUI.is_narrow(self)
	var region := DataRegistry.get_region(str(mission.get("region_id", "")))
	var column := UIFactory.vbox(10)
	root.add_child(column)
	column.add_child(CastleUI.header("Prepare Your Expedition", str(region.get("name", "")), func() -> void: SceneRouter.go(SceneRouter.Screen.WORLD_MAP), "War Table"))
	var body: BoxContainer = UIFactory.vbox(10) if narrow else UIFactory.hbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if narrow:
		var scroll := UIFactory.scroll()
		column.add_child(scroll)
		scroll.add_child(body)
	else:
		column.add_child(body)
	var mission_card := _mission_card(mission, region)
	var sisters := UIFactory.vbox(10)
	sisters.name = "Sisters"
	sisters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for member in campaign.roster.members:
		sisters.add_child(_sister_panel(member, narrow))
	var loadout := UIFactory.vbox(10)
	loadout.name = "Loadout"
	loadout.add_child(_potion_panel())
	_relic_slot = UIFactory.vbox(0)
	loadout.add_child(_relic_slot)
	_relic_slot.add_child(_relic_panel())
	body.add_child(mission_card)
	if narrow:
		body.add_child(sisters)
		body.add_child(loadout)
		column.add_child(_footer(narrow))
	else:
		mission_card.custom_minimum_size.x = COLUMN_WIDTH
		loadout.custom_minimum_size.x = COLUMN_WIDTH
		var sister_scroll := UIFactory.scroll()
		sister_scroll.name = "SisterScroll"
		sister_scroll.add_child(sisters)
		body.add_child(sister_scroll)
		loadout.add_child(_spacer())
		loadout.add_child(_footer(narrow))
		body.add_child(loadout)
	_refresh_problems()


# --- Mission -------------------------------------------------------------------------------------

## The mission brief on parchment: region painting, seal and name, objective, danger, threat, rewards.
func _mission_card(mission: Dictionary, region: Dictionary) -> Control:
	var campaign := GameState.campaign
	var mission_id := str(mission["id"])
	var kit := UIKit.has("plaque_parchment")
	var ink := UITheme.INK if kit else UITheme.IVORY
	var soft := UITheme.INK_SOFT if kit else UITheme.IVORY_DIM
	var panel := PanelContainer.new()
	panel.name = "MissionCard"
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", UIKit.style("plaque_parchment") if kit else UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), UITheme.GOLD_DARK, 12, 2, 12))
	var column := UIFactory.vbox(6)
	panel.add_child(column)
	var art := UIKit.picture(str(region.get("art", "")))
	if art != null:
		var banner := TextureRect.new()
		banner.name = "RegionArt"
		banner.texture = art
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		banner.custom_minimum_size = Vector2(0, 120)
		banner.clip_contents = true
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(banner)
	var top := UIFactory.hbox(8)
	top.add_child(CastleUI.picture("icon_ui_mission", 40.0, "✦"))
	var title := UIFactory.label(str(mission["name"]), &"", true)
	title.name = "MissionName"
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 3)
	title.add_theme_color_override("font_color", ink)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	column.add_child(top)
	var description := UIFactory.label(str(mission.get("description", "")), &"", true)
	description.add_theme_color_override("font_color", soft)
	description.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	column.add_child(description)
	column.add_child(_divider(soft))
	var objective := UIFactory.label(_objective_text(mission), &"", true)
	objective.name = "ObjectiveText"
	objective.add_theme_color_override("font_color", ink)
	column.add_child(objective)
	var stats := UIFactory.hbox(12)
	var danger := UIFactory.label("Danger " + "★".repeat(int(mission.get("difficulty", 1))), &"", false)
	danger.add_theme_color_override("font_color", Color("b23a48") if kit else Color("ff9a8a"))
	stats.add_child(danger)
	var threat_value := int(campaign.region_state(str(mission.get("region_id", ""))).get("threat", 0))
	var threat := UIFactory.label("Threat " + ("▲".repeat(threat_value) if threat_value > 0 else "calm"), &"", false)
	threat.name = "Threat"
	threat.add_theme_color_override("font_color", soft)
	stats.add_child(threat)
	if campaign.is_mission_completed(mission_id):
		stats.add_child(UIFactory.expander())
		stats.add_child(CastleUI.pill("Completed", UITheme.GREEN))
	column.add_child(stats)
	var rewards: Dictionary = mission.get("rewards", {})
	var first: Dictionary = rewards.get("first_time", {}) if not campaign.is_mission_completed(mission_id) else {}
	var row := UIFactory.hbox(8)
	row.name = "Rewards"
	var heading := UIFactory.label("Rewards", &"", false)
	heading.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	heading.add_theme_color_override("font_color", soft)
	row.add_child(heading)
	row.add_child(UIFactory.expander())
	_reward(row, "icon_res_gold", str(int(rewards.get("gold", 0)) + int(first.get("gold", 0))), ink)
	var essence := int(rewards.get("essence", 0)) + int(first.get("essence", 0))
	if essence > 0:
		_reward(row, "icon_res_essence", str(essence), ink)
	column.add_child(row)
	if not first.is_empty():
		var tag := UIFactory.label("includes the first-time bonus", &"", false)
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", soft)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		column.add_child(tag)
	return panel


func _objective_text(mission: Dictionary) -> String:
	var objective: Dictionary = mission["objective"]
	if str(objective["type"]) != Objectives.TYPE_CLEAR_TARGETS:
		return "Objective: " + Objectives.describe(Objectives.create(mission, {"nodes": []}))
	return "Objective: %s %d of %d %s, then head home." % [objective.get("verb", "Clear"), int(objective.get("required", 1)), int(objective.get("targets", 1)), objective.get("noun", "targets")]


func _reward(row: HBoxContainer, icon_id: String, text: String, color: Color) -> void:
	row.add_child(CastleUI.picture(icon_id, 26.0, "◆"))
	var label := UIFactory.label(text, &"", false)
	label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Small utility controls (sister shortcuts, − / +, pickers) use the compact navy enamel frame: the
## pointed kit is for the screen's real actions and clips short labels.
func _compact(button: Button) -> Button:
	for entry in [["normal", Color.WHITE], ["hover", Color(1.3, 1.22, 1.08)], ["pressed", Color(0.72, 0.74, 0.92)], ["focus", Color(1.2, 1.2, 1.4)], ["disabled", Color(0.6, 0.6, 0.66, 0.7)]]:
		button.add_theme_stylebox_override(str(entry[0]), UITheme.compact_button_style(entry[1]))
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL + 1)
	return button


func _divider(color: Color) -> Control:
	var line := ColorRect.new()
	line.color = Color(color, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _section_title(text: String, color: Color = Color("f6e7c1")) -> Label:
	var title := UIFactory.label(text, &"", false)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 1)
	title.add_theme_color_override("font_color", color)
	return title


# --- Sisters -------------------------------------------------------------------------------------

## A sister's card: her figure (or portrait), name, specializations, prepared deck, gear and HP, the
## shortcuts to the Deck Workshop / Armory / Training Hall, and the deck preset picker.
func _sister_panel(member: PartyMember, narrow: bool) -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(6, member.definition.accent_color)
	panel.name = "Sister_" + member.id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UIFactory.hbox(12)
	var card := CastleUI.column_of(panel)
	card.add_child(row)
	row.add_child(_sister_figure(member, narrow))
	var texts := UIFactory.vbox(4)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var name_label := _section_title(member.definition.display_name, member.definition.accent_color.lightened(0.25))
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	texts.add_child(name_label)
	var specs := HFlowContainer.new()
	specs.add_theme_constant_override("h_separation", 6)
	specs.add_theme_constant_override("v_separation", 4)
	var level := Levels.level_of(campaign, member.id)
	var level_pill := CastleUI.pill("Lv %d" % level, UITheme.GOLD)
	level_pill.name = "LevelPill"
	level_pill.tooltip_text = "Level %d · %s" % [level, Levels.title(level)]
	level_pill.mouse_filter = Control.MOUSE_FILTER_PASS
	specs.add_child(level_pill)
	specs.add_child(CastleUI.pill(member.specialization.display_name, member.specialization.get_accent(member.definition.accent_color)))
	if member.secondary_specialization != null:
		specs.add_child(CastleUI.pill("+ " + member.secondary_specialization.display_name, UITheme.LAVENDER))
	texts.add_child(specs)
	var cards := campaign.prepared_cards(member.id)
	var upgraded := cards.filter(func(o: OwnedCard) -> bool: return o.upgrade_level > 0).size()
	var facts := UIFactory.label("Deck %d cards  ·  %d upgraded\nGear %d worn  ·  HP %d" % [cards.size(), upgraded, member.equipment.size(), member.max_hp], &"DimLabel", true)
	facts.name = "Facts"
	texts.add_child(facts)
	var buttons := HFlowContainer.new()
	buttons.name = "Shortcuts"
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	var deck := _compact(UIFactory.button("Deck Workshop", false, Vector2(0, 44)))
	deck.name = "DeckButton_" + member.id
	deck.pressed.connect(func() -> void: SceneRouter.open_service("library"))
	buttons.add_child(deck)
	var gear := _compact(UIFactory.button("Armory", false, Vector2(0, 44)))
	gear.pressed.connect(func() -> void: SceneRouter.open_equipment(SceneRouter.Screen.EXPEDITION_PREP))
	buttons.add_child(gear)
	if campaign.services.has("training_hall"):
		var training := _compact(UIFactory.button("Training Hall", false, Vector2(0, 44)))
		training.tooltip_text = "Training Hall"
		training.pressed.connect(func() -> void: SceneRouter.open_service("training_hall"))
		buttons.add_child(training)
	if not campaign.presets.is_empty():
		texts.add_child(_preset_picker(member))
	card.add_child(buttons)
	return panel


func _sister_figure(member: PartyMember, narrow: bool) -> Control:
	var figure := AssetCatalog.figure(member.id)
	if figure == null:
		var face := AvatarFrame.new()
		face.setup(member.id, 72.0, member.specialization.get_accent(member.definition.accent_color))
		return face
	var holder := Control.new()
	holder.name = "Figure"
	holder.custom_minimum_size = Vector2(96, 130) if narrow else Vector2(110, 150)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A soft accent glow behind the figure, like the war table's lamplight.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(member.definition.accent_color, 0.38))
	gradient.set_color(1, Color(member.definition.accent_color, 0.0))
	var light := GradientTexture2D.new()
	light.gradient = gradient
	light.fill = GradientTexture2D.FILL_RADIAL
	light.fill_from = Vector2(0.5, 0.55)
	light.fill_to = Vector2(0.5, 0.0)
	var glow := TextureRect.new()
	glow.texture = light
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(glow)
	holder.add_child(glow)
	var rect := TextureRect.new()
	rect.texture = figure
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(rect)
	holder.add_child(rect)
	return holder


func _preset_picker(member: PartyMember) -> Control:
	var campaign := GameState.campaign
	var preset_row := UIFactory.hbox(8)
	preset_row.add_child(UIFactory.label("Preset", &"DimLabel", false))
	var picker := OptionButton.new()
	_compact(picker)
	picker.name = "PresetPicker_" + member.id
	picker.custom_minimum_size = Vector2(180, 40)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("(current deck)")
	var names: Array = campaign.presets.keys()
	names.sort()
	for preset_name: String in names:
		picker.add_item(preset_name)
	picker.item_selected.connect(func(index: int) -> void:
		if index > 0:
			campaign.set_prepared(member.id, (campaign.presets[names[index - 1]] as Dictionary).get(member.id, []))
			GameState.save_game()
			SceneRouter.go(SceneRouter.Screen.EXPEDITION_PREP))
	preset_row.add_child(picker)
	return preset_row


# --- Loadout -------------------------------------------------------------------------------------

## The potion belt: one gold socket per belt slot (filled sockets show the potion), then the stores
## with − / + to pack each potion.
func _potion_panel() -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(6)
	panel.name = "PotionBelt"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	_belt_label = _section_title("")
	column.add_child(_belt_label)
	_sockets = HFlowContainer.new()
	_sockets.name = "Sockets"
	_sockets.add_theme_constant_override("h_separation", 6)
	_sockets.add_theme_constant_override("v_separation", 6)
	column.add_child(_sockets)
	_potion_rows = UIFactory.vbox(4)
	column.add_child(_potion_rows)
	var stored := Apothecary.stored_potions(campaign)
	if stored.is_empty():
		_potion_rows.add_child(UIFactory.label("No potions in the stores. Visit the Apothecary.", &"DimLabel", true))
	for item_id: String in stored:
		_potion_rows.add_child(_potion_row(item_id, int(stored[item_id])))
	_refresh_belt()
	return panel


func _potion_row(item_id: String, stored: int) -> Control:
	var row := UIFactory.hbox(6)
	row.name = "Potion_" + item_id
	var item := DataRegistry.get_item(item_id)
	row.add_child(_potion_icon(28.0))
	var label := UIFactory.label("%s\n%d stored" % [str(item.get("name", item_id)), stored], &"", true)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = str(item.get("description", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var minus := _compact(UIFactory.button("−", false, Vector2(44, 44)))
	minus.name = "Less"
	minus.pressed.connect(_change_potion.bind(item_id, -1))
	row.add_child(minus)
	var count := UIFactory.label(str(int(_loadout.get(item_id, 0))), &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	count.name = "Count"
	count.custom_minimum_size.x = 26
	count.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	count.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(count)
	var plus := _compact(UIFactory.button("+", false, Vector2(44, 44)))
	plus.name = "More"
	plus.pressed.connect(_change_potion.bind(item_id, 1))
	row.add_child(plus)
	return row


func _potion_icon(side: float) -> Control:
	var texture := UIAssets.texture("icons/icon_potion")
	if texture == null:
		return CastleUI.picture("", side, "⚗")
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## One belt socket: the gold ring, with a potion inside when filled.
func _socket(filled_by: String) -> Control:
	var socket := Control.new()
	socket.custom_minimum_size = Vector2(SOCKET_SIZE, SOCKET_SIZE)
	socket.mouse_filter = Control.MOUSE_FILTER_PASS if filled_by != "" else Control.MOUSE_FILTER_IGNORE
	var ring := CastleUI.picture("frame_socket", SOCKET_SIZE, "○")
	UIFactory.full_rect(ring)
	socket.add_child(ring)
	if filled_by != "":
		socket.tooltip_text = str(DataRegistry.get_item(filled_by).get("name", filled_by))
		var potion := _potion_icon(SOCKET_SIZE * 0.6)
		potion.position = Vector2.ONE * SOCKET_SIZE * 0.2
		potion.size = Vector2.ONE * SOCKET_SIZE * 0.6
		socket.add_child(potion)
	else:
		ring.modulate = Color(1, 1, 1, 0.45)
	return socket


func _change_potion(item_id: String, delta: int) -> void:
	var campaign := GameState.campaign
	var next := clampi(int(_loadout.get(item_id, 0)) + delta, 0, campaign.vault.count_of(item_id))
	var total := 0
	for id: String in _loadout:
		total += int(_loadout[id]) if id != item_id else 0
	if total + next > campaign.potion_capacity:
		CastleUI.toast(self, "The belt holds %d potions." % campaign.potion_capacity, false)
		return
	_loadout[item_id] = next
	_refresh_belt()
	_refresh_problems()


func _refresh_belt() -> void:
	var packed: Array[String] = []
	for item_id: String in _loadout:
		for i in int(_loadout[item_id]):
			packed.append(item_id)
	var capacity := GameState.campaign.potion_capacity
	_belt_label.text = "Potion Belt  %d / %d" % [packed.size(), capacity]
	UIFactory.clear_children(_sockets)
	for i in maxi(capacity, packed.size()):
		_sockets.add_child(_socket(packed[i] if i < packed.size() else ""))
	for row in _potion_rows.get_children():
		if row.has_node("Count"):
			(row.get_node("Count") as Label).text = str(int(_loadout.get(str(row.name).trim_prefix("Potion_"), 0)))


## The heirloom relic carried from home (picker) and the bond relics that always come along.
func _relic_panel() -> Control:
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(6)
	panel.name = "Relics"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	column.add_child(_section_title("Heirloom Relic"))
	if campaign.relic_collection.is_empty():
		column.add_child(UIFactory.label("Relics found on expeditions can be carried from home, one at a time.", &"DimLabel", true))
	else:
		var row := UIFactory.hbox(8)
		if campaign.heirloom != "":
			row.add_child(RelicIcon.create(campaign.heirloom, 44))
		var picker := OptionButton.new()
		_compact(picker)
		picker.name = "HeirloomPicker"
		picker.custom_minimum_size = Vector2(180, 44)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_item("None")
		for i in campaign.relic_collection.size():
			var relic_id := campaign.relic_collection[i]
			picker.add_item(str(DataRegistry.get_item(relic_id).get("name", relic_id)))
			picker.set_item_tooltip(i + 1, RelicIcon.tooltip_for(relic_id))
			if relic_id == campaign.heirloom:
				picker.select(i + 1)
		picker.item_selected.connect(func(index: int) -> void:
			campaign.heirloom = "" if index == 0 else campaign.relic_collection[index - 1]
			GameState.save_game()
			_refresh_relics.call_deferred())
		row.add_child(picker)
		column.add_child(row)
		if campaign.heirloom != "":
			var text := UIFactory.label(str(DataRegistry.get_item(campaign.heirloom).get("description", "")), &"DimLabel", true)
			text.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
			column.add_child(text)
	var bond_relics := Bond.relics(campaign)
	if not bond_relics.is_empty():
		var bond := UIFactory.hbox(6)
		bond.name = "BondRelics"
		var label := UIFactory.label("Bond", &"", false)
		label.add_theme_color_override("font_color", UITheme.BOND_PINK)
		bond.add_child(label)
		for relic_id in bond_relics:
			var icon := RelicIcon.create(relic_id, 36)
			icon.tooltip_text = RelicIcon.tooltip_for(relic_id) + "\n(always carried)"
			bond.add_child(icon)
		column.add_child(bond)
	return panel


func _refresh_relics() -> void:
	UIFactory.clear_children(_relic_slot)
	_relic_slot.add_child(_relic_panel())


# --- Departure -----------------------------------------------------------------------------------

## What still blocks departure (left) and the violet Begin Expedition seal (right).
func _footer(narrow: bool) -> Control:
	var footer: BoxContainer = UIFactory.hbox(12) if narrow else UIFactory.vbox(6)
	footer.name = "Footer"
	_problems_box = UIFactory.vbox(2)
	_problems_box.name = "Problems"
	_problems_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problems_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_problems_box)
	_embark = OrnateButton.create("Begin Expedition ›", "icon_svc_expeditions", true, Vector2(300, 58) if narrow else Vector2(COLUMN_WIDTH, 66))
	_embark.name = "EmbarkButton"
	_embark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_embark.pressed.connect(_on_embark)
	footer.add_child(_embark)
	return footer


func _refresh_problems() -> void:
	UIFactory.clear_children(_problems_box)
	var problems := ExpeditionService.departure_problems(GameState.campaign, SceneRouter.mission_id, _loadout)
	for problem in problems:
		var label := UIFactory.label("• " + problem, &"", true)
		label.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.35))
		label.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.12, 0.9))
		label.add_theme_constant_override("shadow_outline_size", 6)
		_problems_box.add_child(label)
	if _embark != null:
		_embark.disabled = not problems.is_empty()


func _on_embark() -> void:
	var error := ExpeditionService.start(SceneRouter.mission_id, _loadout)
	if error != "":
		CastleUI.toast(self, error, false)
		return
	SceneRouter.go(SceneRouter.Screen.MAP)
