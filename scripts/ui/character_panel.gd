class_name CharacterPanel
extends PanelContainer
## Reusable character presentation: portrait (PortraitView), name, role and optional
## specialization / HP / detail lines. Same component for selection, overview, rest and combat.

const FACE_SIZE_SLIM := 76
const FACE_SIZE_COMPACT := 76
const FACE_SIZE_FULL := 120
## Same proportions as the figure crops (about 0.6 width/height) so Bianca and Chiara are not trimmed.
const FIGURE_SIZE := Vector2(180, 300)

var _content: VBoxContainer


## options: {specialization: SpecializationDef, hp: int, max_hp: int, block: int,
##           details: bool, compact: bool, slim: bool, extra: String,
##           figure: bool (tall full-figure art beside the text),
##           live_text: String (combat: passive readiness and statuses)}
func setup(char_def: CharacterDef, options: Dictionary = {}) -> void:
	UIFactory.clear_children(self)
	var spec: SpecializationDef = options.get("specialization")
	var accent := spec.get_accent(char_def.accent_color) if spec != null else char_def.accent_color
	var slim: bool = options.get("slim", false)
	# Combat panels (slim) keep the compact flat style; menu panels use the ornate frame.
	if slim:
		add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY, 0.95), accent, 14, 3, 12))
	else:
		add_theme_stylebox_override("panel", UITheme.ornate_panel_style())
	var compact: bool = options.get("compact", false) or slim
	var figure: bool = options.get("figure", false)

	var outer := UIFactory.hbox(12)
	add_child(outer)
	if slim or figure:
		var portrait := PortraitView.new()
		if figure:
			portrait.setup(char_def, spec, FIGURE_SIZE, true)
		else:
			portrait.setup(char_def, spec, Vector2(FACE_SIZE_SLIM, FACE_SIZE_SLIM))
		portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		outer.add_child(portrait)
	else:
		var avatar := AvatarFrame.new()
		avatar.setup(char_def.id, 110.0 if not compact else 96.0, accent)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		outer.add_child(avatar)

	_content = UIFactory.vbox(2 if slim else (4 if compact else 8))
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_content)

	var name_label := UIFactory.label(char_def.display_name, &"HeaderLabel")
	name_label.add_theme_color_override("font_color", char_def.accent_color)
	if slim:
		name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 4)
	_content.add_child(name_label)
	if not compact:
		_content.add_child(UIFactory.label("%s · %s" % [char_def.title, char_def.role.capitalize()], &"DimLabel"))
	if spec != null and not slim:
		var spec_row := UIFactory.hbox(6)
		if spec.icon_id != "":
			spec_row.add_child(UIFactory.icon_by_id(spec.icon_id, 22))
		var spec_label := UIFactory.label("Specialization: %s" % spec.display_name)
		spec_label.add_theme_color_override("font_color", accent)
		spec_row.add_child(spec_label)
		_content.add_child(spec_row)

	if options.has("hp"):
		_add_vitals(char_def, options)

	if options.get("details", false):
		_content.add_child(UIFactory.label("Hair: %s" % char_def.hair.capitalize()))
		_content.add_child(UIFactory.label("Eyes: %s" % char_def.eyes.capitalize()))
		_content.add_child(UIFactory.label(char_def.story, &"DimLabel", true))

	var extra: String = options.get("extra", "")
	if extra != "":
		_content.add_child(UIFactory.label(extra, &"DimLabel", true))


func _add_vitals(char_def: CharacterDef, options: Dictionary) -> void:
	var hp: int = options["hp"]
	var max_hp: int = options.get("max_hp", char_def.max_hp)
	_content.add_child(UIFactory.hp_bar(hp, max_hp))
	var block: int = options.get("block", 0)
	var hp_row := UIFactory.hbox(6)
	hp_row.add_child(UIFactory.icon("health", 20))
	hp_row.add_child(UIFactory.label("HP %d / %d" % [hp, max_hp] + ("   (Fallen)" if hp <= 0 else ""), &"DimLabel"))
	if block > 0:
		hp_row.add_child(UIFactory.icon("block", 20))
		var block_label := UIFactory.label("Block %d" % block, &"DimLabel")
		block_label.add_theme_color_override("font_color", UITheme.SILVER)
		hp_row.add_child(block_label)
	var live_text: String = options.get("live_text", "")
	if live_text != "":
		# Same row as HP so combat panels keep their height on small screens.
		hp_row.add_child(UIFactory.expander())
		var spec: SpecializationDef = options.get("specialization")
		if spec != null and spec.icon_id != "" and spec.has_passive():
			hp_row.add_child(UIFactory.icon_by_id(spec.icon_id, 20))
		var live := UIFactory.label(live_text, &"DimLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
		live.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		live.add_theme_color_override("font_color", UITheme.GOLD)
		hp_row.add_child(live)
	_content.add_child(hp_row)
