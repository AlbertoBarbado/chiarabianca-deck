class_name CombatCharacterView
extends CombatUnitView
## Party member on the right side of the battlefield: basic pose art (idle / cast / block / hit /
## down from the presentation data). Its vitals live in the combat screen's top bar (rows_sink);
## without a sink the vitals show in an info card under the art. Fallen characters switch to their
## "down" pose and are greyed. Hovering (desktop) or tapping (touch) pops up the same detail panel
## as enemies: name, specialization, HP, Block, passives and every status explained.

## When valid, receives (rows, live_text) instead of the info card (Slay-the-Spire style top bar).
var rows_sink: Callable


func setup_character(combat_unit: Combatant) -> void:
	info_height = 78.0
	var char_def := DataRegistry.get_character(combat_unit.id)
	setup_unit(combat_unit.id, false, char_def.accent_color if char_def != null else UITheme.SILVER, func(state: String) -> Texture2D: return CombatPresentation.character_state(combat_unit.id, state, combat_unit.specialization_id))
	set_motion_profile(CombatPresentation.motion_profile(combat_unit.id))
	# The party stands on the right: the panel opens toward the middle of the battlefield.
	_init_detail_panel("CharacterDetail", true)


## live_text: passive readiness and statuses, built by the combat screen (it owns the passive runner).
## passive_text: the passive readiness alone, for the hover panel (it explains statuses itself).
func update_character(unit: Combatant, spec: SpecializationDef, live_text: String, passive_text: String = "") -> void:
	set_alive(unit.is_alive())
	set_health(unit.hp, unit.max_hp)
	var char_def := DataRegistry.get_character(unit.id)
	var accent := spec.get_accent(char_def.accent_color) if spec != null and char_def != null else _accent
	var rows: Array[Control] = []
	var head := UIFactory.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if spec != null and spec.icon_id != "":
		head.add_child(UIFactory.icon_by_id(spec.icon_id, 20))
	var name_label := UIFactory.label(unit.display_name, &"")
	name_label.add_theme_color_override("font_color", accent.lightened(0.25))
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	head.add_child(UIFactory.icon("health", 16))
	var hp_label := UIFactory.label("%d/%d%s" % [unit.hp, unit.max_hp, " (Fallen)" if not unit.is_alive() else ""], &"DimLabel")
	hp_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	head.add_child(hp_label)
	if unit.block > 0:
		head.add_child(UIFactory.icon("block", 16))
		var block_label := UIFactory.label("%d" % unit.block, &"DimLabel")
		block_label.add_theme_color_override("font_color", UITheme.SILVER)
		block_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		head.add_child(block_label)
	rows.append(head)
	var bar := UIFactory.hp_bar(unit.hp, unit.max_hp)
	bar.custom_minimum_size = Vector2(0, 9)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.append(bar)
	_update_detail(unit, spec, accent, passive_text)
	if rows_sink.is_valid():
		rows_sink.call(rows, live_text)
		return
	if live_text != "":
		var live := UIFactory.label(live_text, &"DimLabel", true)
		live.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		live.add_theme_color_override("font_color", UITheme.GOLD)
		live.custom_minimum_size.x = 0
		live.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.append(live)
	set_info_rows(rows)


func _update_detail(unit: Combatant, spec: SpecializationDef, accent: Color, passive_text: String) -> void:
	var column := _begin_detail()
	var title := unit.display_name + ((" — " + spec.display_name) if spec != null else "")
	column.add_child(_detail_title(title, accent.lightened(0.3)))
	column.add_child(_detail_line("HP %d / %d" % [unit.hp, unit.max_hp] + ("   Block %d" % unit.block if unit.block > 0 else "") + ("   (Fallen)" if not unit.is_alive() else ""), UITheme.SILVER))
	if passive_text != "":
		column.add_child(_detail_line(passive_text, UITheme.GOLD))
		var rule := str(spec.passive.get("description", "")) if spec != null else ""
		if rule != "":
			var rule_label := _detail_line(rule, UITheme.IVORY_DIM)
			rule_label.add_theme_font_size_override("font_size", DETAIL_FONT - 1)
			rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rule_label.custom_minimum_size.x = DETAIL_WRAP_WIDTH
			column.add_child(rule_label)
	if unit.statuses.is_empty():
		column.add_child(_detail_line("No statuses.", UITheme.IVORY_DIM))
	else:
		for row in CombatUnitView.status_rows(unit.statuses, DETAIL_FONT, true, DETAIL_WRAP_WIDTH):
			column.add_child(row)
	_end_detail()


## A fallen ally keeps its panel: hovering still says what happened to her.
func _detail_allowed() -> bool:
	return true
