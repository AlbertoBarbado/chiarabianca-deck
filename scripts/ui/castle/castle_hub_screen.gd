extends ScreenBase
## The castle: the sisters' persistent home between expeditions (docs/PERSISTENT_RPG_DESIGN.md).
## A grid of service tiles built from data/castle/services.json: open services lead to their
## screen or service panel; locked ones show how to open them. Autosaves on entry.

var _grid: GridContainer


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.45


func _build() -> void:
	if GameState.campaign == null:
		SceneRouter.go.call_deferred(SceneRouter.Screen.MAIN_MENU)
		return
	if not GameState.in_castle():
		GameState.enter_castle()
	else:
		GameState.save_game()
	var campaign := GameState.campaign
	var column := UIFactory.vbox(14)
	root.add_child(column)
	column.add_child(CastleUI.header("The Royal Castle", "Home. Prepare the sisters, then set out from the war table.", Callable()))
	column.add_child(_status_strip(campaign))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "ServiceGrid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	for service in _services():
		var open := campaign.services.has(str(service["id"]))
		var tile := CastleUI.tile(str(service["name"]), str(service["description"]), str(service.get("icon", "")), not open, str(service.get("hint", "")))
		tile.name = "Service_" + str(service["id"])
		tile.pressed.connect(_open_service.bind(service))
		_grid.add_child(tile)
	var footer := UIFactory.hbox(12)
	var menu := UIFactory.button("Main Menu", false, Vector2(190, 52))
	menu.name = "MainMenuButton"
	menu.tooltip_text = "The campaign is saved."
	menu.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAIN_MENU))
	footer.add_child(menu)
	var settings := UIFactory.button("Settings", false, Vector2(170, 52))
	settings.name = "SettingsButton"
	settings.pressed.connect(func() -> void: SceneRouter.open_settings(SceneRouter.Screen.CASTLE_HUB))
	footer.add_child(settings)
	footer.add_child(UIFactory.expander())
	var go := UIFactory.button("Set Out ›", true, Vector2(220, 56))
	go.name = "SetOutButton"
	go.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.WORLD_MAP))
	footer.add_child(go)
	column.add_child(footer)
	resized.connect(_fit_columns)
	_fit_columns()
	go.grab_focus.call_deferred()


func _services() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for service: Dictionary in DataRegistry.services.values():
		list.append(service)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return list


## Welcome text on the first visit, then what is new or suggested next.
func _status_strip(campaign: CampaignState) -> Control:
	var panel := CastleUI.card_panel(4)
	panel.name = "StatusStrip"
	var column := CastleUI.column_of(panel)
	var text := ""
	if int(campaign.stats.get("expeditions_started", 0)) == 0:
		text = "Welcome home, princesses. Your collection, gear and potions stay here between expeditions. When you are ready, open the war table (Expeditions) and walk the castle halls first."
	else:
		var open_missions := 0
		for region in ExpeditionService.regions():
			if ExpeditionService.region_unlocked(campaign, str(region["id"])):
				open_missions += ExpeditionService.missions_of(str(region["id"])).filter(func(m: Dictionary) -> bool: return ExpeditionService.mission_lock_reason(campaign, str(m["id"])) == "").size()
		text = "%d missions are open. Expeditions: %d completed, %d retreated, %d lost." % [open_missions,
			int(campaign.stats.get("expeditions_completed", 0)), int(campaign.stats.get("expeditions_retreated", 0)), int(campaign.stats.get("expeditions_defeated", 0))]
	var label := UIFactory.label(text, &"", true)
	label.name = "StatusText"
	column.add_child(label)
	var problems := DeckRules.validate_campaign(campaign)
	if not problems.is_empty():
		var warn := UIFactory.label("Deck Workshop: " + problems[0], &"", true)
		warn.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.3))
		column.add_child(warn)
	return panel


func _fit_columns() -> void:
	if _grid != null:
		_grid.columns = 1 if size.x < 700 else (2 if size.x < 1150 else 3)


func _open_service(service: Dictionary) -> void:
	match str(service.get("screen", "")):
		"world_map":
			SceneRouter.go(SceneRouter.Screen.WORLD_MAP)
		"equipment":
			SceneRouter.open_equipment(SceneRouter.Screen.CASTLE_HUB)
		_:
			SceneRouter.open_service(str(service["id"]))
