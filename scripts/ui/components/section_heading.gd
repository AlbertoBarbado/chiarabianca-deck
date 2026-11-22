class_name SectionHeading
extends VBoxContainer
## Heading in the display font with the gold ornamental divider underneath.
## `large = true` uses the title size (screen titles), otherwise the heading size.

const DIVIDER := "panels/divider"
const DIVIDER_WIDTH := 320.0

var label: Label


func setup(text: String, large: bool = false, align_center: bool = true) -> void:
	UIFactory.clear_children(self)
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = UIFactory.label(text, &"TitleLabel" if large else &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER if align_center else HORIZONTAL_ALIGNMENT_LEFT)
	if large:
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE - 16)
	label.add_theme_color_override("font_outline_color", Color(UITheme.NAVY_DEEP, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	var texture := UIAssets.texture(DIVIDER)
	if texture != null:
		var rule := TextureRect.new()
		rule.texture = texture
		rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var width := DIVIDER_WIDTH * (1.4 if large else 1.0)
		rule.custom_minimum_size = Vector2(width, width * texture.get_height() / texture.get_width())
		rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if align_center else Control.SIZE_SHRINK_BEGIN
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rule)
