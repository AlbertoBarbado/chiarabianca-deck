extends ScreenBase
## The end of an expedition (completed, retreated or defeated): what came home, what opened up in
## the world, the Sister Bond, and the discovery choice (cards drafted on the way that may join the
## collection). Rewards were applied once by ExpeditionService.finish; this screen only shows them
## and records the discovery choice. "Return to the Castle" ends the expedition.

const TITLES := {"completed": "Mission Complete", "retreated": "Back Home Early", "defeated": "Carried Home"}

var _chosen: Array[int] = []
var _keep_button: Button
var _views: Array[CardView] = []


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.5


func _build() -> void:
	var expedition := GameState.expedition
	if GameState.campaign == null or expedition == null:
		SceneRouter.go.call_deferred(SceneRouter.Screen.CASTLE_HUB if GameState.campaign != null else SceneRouter.Screen.MAIN_MENU)
		return
	if not expedition.rewards_claimed:
		ExpeditionService.finish(ExpeditionState.OUTCOME_RETREATED)
	var results := expedition.results
	var outcome := str(results.get("outcome", expedition.outcome))
	var mission := expedition.mission()
	var column := UIFactory.vbox(12)
	root.add_child(column)
	var subtitle := str(mission.get("name", ""))
	column.add_child(CastleUI.header(str(TITLES.get(outcome, "Expedition Over")), subtitle, Callable()))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var content := UIFactory.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var story := CastleUI.card_panel(6, UITheme.GOLD if outcome == "completed" else UITheme.CRIMSON)
	story.name = "Story"
	CastleUI.column_of(story).add_child(UIFactory.label(_story_text(outcome), &"", true))
	content.add_child(story)
	if expedition.discoveries_allowed > 0 and not expedition.discoveries_claimed:
		content.add_child(_discovery_panel(expedition))  # the one decision on this screen comes first
	var parts: BoxContainer = UIFactory.vbox(12) if CastleUI.is_narrow(self) else UIFactory.hbox(12)
	content.add_child(parts)
	parts.add_child(_rewards_panel(results))
	parts.add_child(_world_panel(results))
	var footer := UIFactory.hbox(12)
	footer.add_child(UIFactory.expander())
	var home := UIFactory.button("Return to the Castle ›", true, Vector2(280, 60))
	home.name = "ReturnHomeButton"
	home.pressed.connect(_on_return)
	footer.add_child(home)
	column.add_child(footer)


func _story_text(outcome: String) -> String:
	var completion: Dictionary = GameState.map_progress.graph.completion if GameState.map_progress != null else {}
	match outcome:
		"completed":
			return str(completion.get("text", "The task is done. Chiara and Bianca turn for home."))
		"retreated":
			return "The sisters chose to turn back. They bring home half of their purse and what they found; the mission waits for another day."
		_:
			return "Both princesses fell. The castle guard carried them home: they are safe, their gear is too, but the purse and potions were lost on the way."


func _rewards_panel(results: Dictionary) -> Control:
	var panel := CastleUI.card_panel(4)
	panel.name = "Rewards"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label("Brought home", &"", false)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	column.add_child(title)
	column.add_child(UIFactory.label("Purse %d gold → treasury +%d" % [int(results.get("purse", 0)), int(results.get("gold_kept", 0))], &"", true))
	if int(results.get("mission_gold", 0)) > 0:
		column.add_child(UIFactory.label("Mission reward: +%d gold" % int(results["mission_gold"]), &"", true))
	if int(results.get("essence", 0)) > 0:
		var essence := UIFactory.label("✦ Starlight Essence +%d" % int(results["essence"]), &"", true)
		essence.add_theme_color_override("font_color", CastleUI.ESSENCE_COLOR)
		column.add_child(essence)
	if int(results.get("items", 0)) > 0:
		column.add_child(UIFactory.label("Equipment found: %d (now in the armory)" % int(results["items"]), &"", true))
	if int(results.get("potions_home", 0)) > 0:
		column.add_child(UIFactory.label("Potions back in the stores: %d" % int(results["potions_home"]), &"", true))
	for relic_id: Variant in results.get("relics", []):
		column.add_child(UIFactory.label("New heirloom choice: %s" % str(DataRegistry.get_item(str(relic_id)).get("name", relic_id)), &"", true))
	var bond := UIFactory.label("♥ Sister Bond +%d XP" % int(results.get("bond_xp", 0)), &"", true)
	bond.add_theme_color_override("font_color", Color("ff9fb8"))
	column.add_child(bond)
	for level: Variant in results.get("bond_levels", []):
		var entry := Bond.level_entry(int(level))
		var up := UIFactory.label("Bond level %d — %s! %s" % [int(level), str(entry.get("title", "")), str(entry.get("text", ""))], &"", true)
		up.add_theme_color_override("font_color", UITheme.GOLD)
		column.add_child(up)
	return panel


func _world_panel(results: Dictionary) -> Control:
	var panel := CastleUI.card_panel(4)
	panel.name = "WorldChanges"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label("The world", &"", false)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	column.add_child(title)
	var lines: Array = results.get("lines", [])
	for line: Variant in lines:
		column.add_child(UIFactory.label("• " + str(line), &"", true))
	for entry: Variant in results.get("unlocked", []):
		var text := _unlock_text(str(entry))
		if text != "":
			var label := UIFactory.label("★ " + text, &"", true)
			label.add_theme_color_override("font_color", UITheme.GOLD)
			column.add_child(label)
	if column.get_child_count() == 1:
		column.add_child(UIFactory.label("Nothing changed this time.", &"DimLabel", true))
	return panel


static func _unlock_text(entry: String) -> String:
	var parts := entry.split(":", true, 1)
	if parts.size() < 2:
		return ""
	match parts[0]:
		"region":
			return "New region: %s" % str(DataRegistry.get_region(parts[1]).get("name", parts[1]))
		"mission":
			return "New mission: %s" % str(DataRegistry.get_mission(parts[1]).get("name", parts[1]))
		"service":
			return "Castle: the %s is open" % str(DataRegistry.get_service(parts[1]).get("name", parts[1]))
	return ""


func _discovery_panel(expedition: ExpeditionState) -> Control:
	var panel := CastleUI.card_panel(8, UITheme.MAGIC_BLUE)
	panel.name = "Discoveries"
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label("Discoveries: keep up to %d card%s for the collection" % [expedition.discoveries_allowed, "" if expedition.discoveries_allowed == 1 else "s"], &"", true)
	title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	column.add_child(title)
	column.add_child(UIFactory.label("Cards drafted on this expedition. The ones you keep join the collection for good; the others are left behind.", &"DimLabel", true))
	var flow := HFlowContainer.new()
	flow.name = "DiscoveryCards"
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for i in expedition.discoveries.size():
		var entry: Dictionary = expedition.discoveries[i]
		var view := CastleUI.card(DataRegistry.get_card(str(entry["card_id"])), str(entry["owner_character_id"]), 0, 0.85)
		view.name = "Discovery_%d" % i
		view.pressed.connect(func(_v: CardView) -> void: _toggle(i))
		_views.append(view)
		flow.add_child(view)
	column.add_child(flow)
	_keep_button = UIFactory.button("Keep Selected", true, Vector2(220, 52))
	_keep_button.name = "KeepButton"
	_keep_button.disabled = true
	_keep_button.pressed.connect(_on_keep)
	column.add_child(_keep_button)
	return panel


func _toggle(index: int) -> void:
	if _chosen.has(index):
		_chosen.erase(index)
	elif _chosen.size() < GameState.expedition.discoveries_allowed:
		_chosen.append(index)
	else:
		CastleUI.toast(self, "You can keep %d." % GameState.expedition.discoveries_allowed, false)
	for i in _views.size():
		_views[i].set_selected(_chosen.has(i))
	_keep_button.disabled = _chosen.is_empty()


func _on_keep() -> void:
	var kept := ExpeditionService.claim_discoveries(_chosen)
	CastleUI.toast(self, "Added to the collection: %d card%s." % [kept.size(), "" if kept.size() == 1 else "s"])
	var panel := root.find_child("Discoveries", true, false)
	if panel != null:
		panel.queue_free()


func _on_return() -> void:
	var expedition := GameState.expedition
	if expedition != null and expedition.discoveries_allowed > 0 and not expedition.discoveries_claimed and get_node_or_null("ConfirmDialog") == null:
		CastleUI.confirm(self, "Leave the discoveries?", "You have not chosen which cards to keep. They will be left behind.", "Go Home", _go_home)
		return
	_go_home()


func _go_home() -> void:
	ExpeditionService.return_to_castle()
	SceneRouter.go(SceneRouter.Screen.CASTLE_HUB)
