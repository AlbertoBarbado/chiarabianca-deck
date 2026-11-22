extends ScreenBase
## Town: a settlement that offers the services listed in its definition (data/towns): a merchant, a
## place to rest, or both. The services themselves are the existing merchant and rest rooms (same
## logic, same screens); this screen is only the hub. What was used is kept in the saved room
## state, and a town node cannot be re-entered once the party has left it.
## The town's illustration ("art" in its definition) fills the left half and is the backdrop; a
## town without art shows the panel alone, centred.

const ART_SIZE := Vector2(560, 0)
const PANEL_WIDTH := 600.0


func _build() -> void:
	var node := GameState.get_current_node()
	var town := DataRegistry.get_town(node.town_id)
	var services: Array = town.get("services", [])
	var layout := UIFactory.hbox(20)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(layout)
	var focus_data: Array = town.get("art_focus", [])  # optional [x, y]: what the tall crop keeps
	var focus := Vector2(float(focus_data[0]), float(focus_data[1])) if focus_data.size() == 2 else Vector2(0.5, 0.5)
	var art := FramedArt.create(str(town.get("art", "")), ART_SIZE, focus)
	if art.has_art():
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout.add_child(art)
	else:
		art.free()
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL if layout.get_child_count() > 0 else Control.SIZE_FILL
	layout.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)
	var column := UIFactory.vbox(12)
	panel.add_child(column)
	var heading := SectionHeading.new()
	heading.setup(str(town.get("name", node.display_name)), true)
	column.add_child(heading)
	column.add_child(UIFactory.label(str(town.get("description", "")), &"", true, HORIZONTAL_ALIGNMENT_CENTER))
	var summary := UIFactory.hbox(16)
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	for member in GameState.party.members:
		var label := UIFactory.label("%s  %d/%d" % [member.definition.display_name, member.current_hp, member.max_hp])
		label.add_theme_color_override("font_color", member.definition.accent_color.lightened(0.2))
		summary.add_child(label)
	var gold := GoldDisplay.new()
	gold.setup(GameState.inventory.gold)
	summary.add_child(gold)
	column.add_child(summary)
	if services.has("merchant"):
		var shop := DataRegistry.get_shop(str(town.get("shop_id", "")))
		var market := ChoiceCard.create("Visit the Merchant", "%s. %s" % [str(shop.get("name", "Market")), str(shop.get("greeting", ""))], "icons/icon_gold")
		market.name = "TownMerchant"
		market.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MERCHANT))
		column.add_child(market)
	if services.has("rest"):
		var rested := bool(GameState.room_state.get("rested", false))
		var percent := roundi(GameState.current_heal_fraction() * 100.0)
		var rest := ChoiceCard.create("Rest at the Fire", "Already rested here." if rested else "Recover %d%% HP. You may also upgrade or remove a card." % percent, "icons/icon_flame")
		rest.name = "TownRest"
		rest.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.REST))
		column.add_child(rest)
	if services.is_empty():
		column.add_child(UIFactory.label("Nobody here has anything to offer.", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	var gear := UIFactory.button("Equipment", false, Vector2(0, 52))
	gear.name = "TownEquipment"
	gear.pressed.connect(func() -> void: SceneRouter.open_equipment(SceneRouter.Screen.TOWN))
	column.add_child(gear)
	var leave := UIFactory.button("Leave Town", false, Vector2(0, 56))
	leave.name = "TownLeave"
	leave.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAP))
	column.add_child(leave)
	column.add_child(UIFactory.label("Once you leave, you cannot come back to this town.", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))


func _backdrop() -> Dictionary:
	return current_room_backdrop()
