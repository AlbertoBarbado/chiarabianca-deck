class_name CharacterStatusPanel
extends PanelContainer
## Compact party-status card: round avatar, name, specialization, heart + HP bar and "HP x / y".
## Used on the Tutorial Complete screen; reusable wherever a character summary is needed.


## options: {specialization: SpecializationDef, hp: int, max_hp: int, text_prefix: bool}
func setup(char_def: CharacterDef, options: Dictionary = {}) -> void:
	UIFactory.clear_children(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.55), Color(UITheme.GOLD_DARK, 0.55), 10, 1, 8))
	var spec: SpecializationDef = options.get("specialization")
	var accent := spec.get_accent(char_def.accent_color) if spec != null else char_def.accent_color
	var hp: int = options.get("hp", char_def.starting_hp)
	var max_hp: int = options.get("max_hp", char_def.max_hp)

	var row := UIFactory.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var avatar := AvatarFrame.new()
	avatar.setup(char_def.id, 66.0, accent)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)

	var info := UIFactory.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_label := UIFactory.label(char_def.display_name, &"HeaderLabel")
	name_label.add_theme_color_override("font_color", accent.lightened(0.25))
	info.add_child(name_label)
	if spec != null:
		info.add_child(UIFactory.label(spec.display_name, &"DimLabel"))
	var bar := UIFactory.hp_bar(hp, max_hp)
	bar.custom_minimum_size = Vector2(0, 16)
	info.add_child(bar)
	var hp_row := UIFactory.hbox(8)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heart := UIAssets.icon("heart")
	if heart != null:
		var rect := TextureRect.new()
		rect.texture = heart
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(28, 28)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_row.add_child(rect)
	var prefix := "%s: " % char_def.display_name if options.get("text_prefix", true) else ""
	var hp_label := UIFactory.label("%s%d / %d HP" % [prefix, hp, max_hp], &"")
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_row.add_child(hp_label)
	info.add_child(hp_row)
