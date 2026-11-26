class_name LevelUI
extends RefCounted
## Shared pieces for sister levels (Levels): the level badge and XP bar, the milestone ladder and the
## pending Mastery card choices. Used by the Sisters panel, the preparation screen and the results
## screen, so the level system looks the same everywhere.

const XP_FILL := Color("e8c26a")


## "Lv 4" seal plus an XP bar and the next milestone: one compact block per sister.
static func sister_bar(campaign: CampaignState, member: PartyMember, compact: bool = false) -> Control:
	var info := Levels.progress(campaign, member.id)
	var box := UIFactory.vbox(2)
	box.name = "Level_" + member.id
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UIFactory.hbox(8)
	var seal := level_seal(int(info["level"]), member.definition.accent_color)
	head.add_child(seal)
	var texts := UIFactory.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := UIFactory.label("%s · %s" % [member.definition.display_name, Levels.title(int(info["level"]))] if not compact else Levels.title(int(info["level"])), &"", false)
	name.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	name.add_theme_color_override("font_color", member.definition.accent_color.lightened(0.3))
	texts.add_child(name)
	texts.add_child(xp_bar(info))
	head.add_child(texts)
	box.add_child(head)
	if not compact:
		var milestone := Levels.next_milestone(campaign, member.id)
		var text := ("%d / %d XP" % [int(info["xp"]), int(info["next"])]) if int(info["next"]) > 0 else "Top level reached"
		if not milestone.is_empty():
			text += "   ·   Level %d: %s" % [int(milestone["level"]), str(milestone["text"])]
		box.add_child(UIFactory.label(text, &"DimLabel", true))
	return box


## One line for the levels gained on an expedition: "Level 4 → 7 · +9 Max HP · Mastery card (rare),
## +80 gold ..." ("" when no level was gained).
static func gain_summary(from_level: int, to_level: int) -> String:
	if to_level <= from_level:
		return ""
	var parts: Array[String] = ["Level %d → %d" % [from_level, to_level], "+%d Max HP" % ((to_level - from_level) * int(Levels.data().get("hp_per_level", 0)))]
	for level in range(from_level + 1, to_level + 1):
		var text := Levels.reward_text(Levels.entry(level).get("rewards", {}))
		if text != "":
			parts.append(text)
	return "  ·  ".join(parts)


## A round gold seal with the level number.
static func level_seal(level: int, accent: Color) -> Control:
	var seal := PanelContainer.new()
	seal.name = "LevelSeal"
	seal.custom_minimum_size = Vector2(46, 46)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.tooltip_text = "Level %d" % level
	seal.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.95), UITheme.GOLD, 23, 2, 2))
	var label := UIFactory.label(str(level), &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	label.add_theme_color_override("font_color", Color("f6e7c1"))
	label.add_theme_color_override("font_outline_color", Color(accent, 0.6))
	label.add_theme_constant_override("outline_size", 4)
	seal.add_child(label)
	return seal


static func xp_bar(info: Dictionary) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "XPBar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = float(info.get("progress", 0.0))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), UITheme.GOLD_DARK, 6, 1, 1))
	bar.add_theme_stylebox_override("fill", UITheme.box(XP_FILL, Color.TRANSPARENT, 6, 0, 1))
	bar.tooltip_text = ("%d / %d XP" % [int(info.get("xp", 0)), int(info.get("next", 0))]) if int(info.get("next", -1)) > 0 else "Top level"
	return bar


## Every pending Mastery choice as a panel of cards: tapping a card takes it (after a confirm).
## `on_claimed` runs after a card was taken (the caller saves / refreshes). Empty when none pending.
static func mastery_choices(owner: Control, on_claimed: Callable) -> Control:
	var campaign := GameState.campaign
	var box := UIFactory.vbox(10)
	box.name = "MasteryChoices"
	if campaign == null:
		return box
	for i in campaign.level_rewards.size():
		var choice: Dictionary = campaign.level_rewards[i]
		var member := campaign.member(str(choice.get("character_id", "")))
		if member == null:
			continue
		var panel := CastleUI.card_panel(8, UITheme.GOLD)
		panel.name = "Mastery_%d" % i
		var column := CastleUI.column_of(panel)
		var title := UIFactory.label("%s · Level %d Mastery — choose one card%s" % [member.definition.display_name, int(choice.get("level", 0)), " (upgraded)" if bool(choice.get("upgraded", false)) else ""], &"", true)
		title.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
		title.add_theme_color_override("font_color", Color("f6e7c1"))
		column.add_child(title)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		var options: Array = choice.get("options", [])
		for j in options.size():
			var def := DataRegistry.get_card(str(options[j]))
			if def == null:
				continue
			var view := CastleUI.card(def, member.id, 1 if bool(choice.get("upgraded", false)) else 0, 0.78)
			view.name = "MasteryCard_%d" % j
			var index := i
			var option := j
			view.pressed.connect(func(_v: CardView) -> void:
				CastleUI.confirm(owner, "Take %s?" % def.display_name, "%s adds %s to her collection for good. The other cards are left." % [member.definition.display_name, def.display_name], "Take Card", func() -> void:
					var taken := Levels.claim_choice(GameState.campaign, index, option)
					if taken != "":
						GameState.save_game()
						CastleUI.toast(owner, "%s learned %s." % [member.definition.display_name, taken])
						on_claimed.call()))
			flow.add_child(view)
		column.add_child(flow)
		box.add_child(panel)
	return box
