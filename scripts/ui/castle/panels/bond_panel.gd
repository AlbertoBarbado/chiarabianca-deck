extends VBoxContainer
## The Sisters: each sister's level, XP and next milestone, pending Mastery card choices, then the
## Sister Bond level and progress, what each bond level unlocks (services, fusion recipes, bond
## relics), how the bond grows, and the twin combo of their current specializations.

var shell: Node
var _levels: VBoxContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	var campaign := GameState.campaign
	var scroll := UIFactory.scroll()
	var body := UIFactory.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	add_child(scroll)
	_levels = UIFactory.vbox(10)
	_levels.name = "SisterLevels"
	body.add_child(_levels)
	_fill_levels()
	var xp := int(campaign.bond.get("xp", 0))
	var level := campaign.bond_level()
	var entry := Bond.level_entry(level)
	var top := CastleUI.card_panel(6, Color("ff9fb8"))
	top.name = "BondSummary"
	var column := CastleUI.column_of(top)
	var faces := UIFactory.hbox(12)
	for m in campaign.roster.members:
		var face := AvatarFrame.new()
		face.setup(m.id, 116.0, m.definition.accent_color)
		faces.add_child(face)
	var texts := UIFactory.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIFactory.label("Bond level %d — %s" % [level, str(entry.get("title", ""))], &"HeaderLabel", false)
	title.name = "BondTitle"
	texts.add_child(title)
	texts.add_child(UIFactory.label(str(entry.get("text", "")), &"", true))
	var next := Bond.next_threshold(xp)
	var bar := ProgressBar.new()
	bar.name = "BondBar"
	bar.min_value = int(entry.get("xp", 0))
	bar.max_value = next if next > 0 else xp
	bar.value = xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	bar.add_theme_stylebox_override("fill", UITheme.box(Color("ff7fa0"), Color.TRANSPARENT, 6, 0, 2))
	texts.add_child(bar)
	texts.add_child(UIFactory.label(("%d / %d XP to the next level" % [xp, next]) if next > 0 else "%d XP — the bond is complete." % xp, &"DimLabel", false))
	faces.add_child(texts)
	column.add_child(faces)
	body.add_child(top)
	var how := CastleUI.card_panel(4)
	CastleUI.column_of(how).add_child(UIFactory.label("How the bond grows: completed expeditions (+%d), any return home (+%d), bosses defeated together (+%d), twin reactions in battle (+%d each, at most %d per expedition)." % [Bond.source_value("expedition_completed"), Bond.source_value("expedition_retreated"), Bond.source_value("boss_defeated"), Bond.source_value("twin_reaction"), Bond.cap("twin_reaction")], &"", true))
	body.add_child(how)
	for level_entry: Dictionary in Bond.levels():
		body.add_child(_level_row(level_entry, level))
	var combo := TwinCombos.for_pair(campaign.member("chiara").specialization.id, campaign.member("bianca").specialization.id)
	if not combo.is_empty():
		var panel := CastleUI.card_panel(4, UITheme.MAGIC_BLUE)
		CastleUI.column_of(panel).add_child(UIFactory.label("Their twin combo: %s %s — %s" % [str(combo.get("name", "")), TwinCombos.stars(combo), str(combo.get("text", ""))], &"", true))
		body.add_child(panel)


## Levels: both sisters' bars side by side, pending Mastery choices, and the milestone ladder.
func _fill_levels() -> void:
	UIFactory.clear_children(_levels)
	var campaign := GameState.campaign
	var panel := CastleUI.card_panel(8)
	panel.name = "LevelSummary"
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label("Levels · party level %d" % Levels.party_level(campaign), &"HeaderLabel", false)
	column.add_child(title)
	var row: BoxContainer = UIFactory.vbox(8) if CastleUI.is_narrow(self) else UIFactory.hbox(16)
	for m in campaign.roster.members:
		row.add_child(LevelUI.sister_bar(campaign, m))
	column.add_child(row)
	column.add_child(UIFactory.label("XP comes from every fight won (elites and bosses pay more) and from completed missions. Each level adds %d Max HP; missions and contracts open with the party level. At level %d a sister may take a second card specialization." % [int(Levels.data().get("hp_per_level", 0)), Levels.dual_spec_level()], &"DimLabel", true))
	var ladder := HFlowContainer.new()
	ladder.name = "Milestones"
	ladder.add_theme_constant_override("h_separation", 6)
	ladder.add_theme_constant_override("v_separation", 6)
	for entry: Dictionary in Levels.table():
		var text := Levels.reward_text(entry.get("rewards", {}))
		if text != "":
			var reached := Levels.party_level(campaign) >= int(entry.get("level", 0))
			var pill := CastleUI.pill("Lv %d · %s" % [int(entry.get("level", 0)), text], UITheme.GOLD if reached else UITheme.LAVENDER)
			pill.tooltip_text = "%s — %s" % [Levels.title(int(entry.get("level", 0))), text]
			pill.mouse_filter = Control.MOUSE_FILTER_PASS
			ladder.add_child(pill)
	column.add_child(ladder)
	_levels.add_child(panel)
	_levels.add_child(LevelUI.mastery_choices(self, func() -> void:
		shell.changed()
		_fill_levels.call_deferred()))


func _level_row(entry: Dictionary, current: int) -> Control:
	var reached := int(entry.get("level", 0)) <= current
	var panel := CastleUI.card_panel(2, UITheme.GOLD if reached else Color(0.4, 0.4, 0.45))
	panel.name = "Level_%d" % int(entry.get("level", 0))
	var column := CastleUI.column_of(panel)
	var head := UIFactory.label("%s Level %d · %s (%d XP)" % ["✓" if reached else "🔒", int(entry.get("level", 0)), str(entry.get("title", "")), int(entry.get("xp", 0))], &"", false)
	head.add_theme_color_override("font_color", UITheme.GOLD if reached else UITheme.IVORY_DIM)
	column.add_child(head)
	var unlocks: Dictionary = entry.get("unlocks", {})
	var parts: Array[String] = []
	for service_id: Variant in unlocks.get("services", []):
		parts.append("opens the %s" % str(DataRegistry.get_service(str(service_id)).get("name", service_id)))
	for recipe_id: Variant in unlocks.get("fusion", []):
		parts.append("fusion recipe %s" % str(DataRegistry.get_fusion_recipe(str(recipe_id)).get("name", recipe_id)))
	if not parts.is_empty():
		column.add_child(UIFactory.label("Unlocks: " + "; ".join(parts), &"DimLabel", true))
	# Bond relics: icon, name and effect, with the shared relic hover text.
	for relic_id: Variant in unlocks.get("relics", []):
		column.add_child(RelicIcon.row(str(relic_id), 32))
	return panel
