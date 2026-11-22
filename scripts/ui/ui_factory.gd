class_name UIFactory
extends RefCounted
## Small helpers that build common Controls so screens stay short and consistent.

const TOUCH_BUTTON_SIZE := Vector2(180, 56)


static func full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func label(text: String, variation: StringName = &"", wrap: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if variation != &"":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120
	return l


static func button(text: String, primary: bool = false, min_size: Vector2 = TOUCH_BUTTON_SIZE) -> Button:
	var b := UIButton.new()
	b.text = text
	b.custom_minimum_size = min_size
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	return b


static func vbox(separation: int = -1) -> VBoxContainer:
	var box := VBoxContainer.new()
	if separation >= 0:
		box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = -1) -> HBoxContainer:
	var box := HBoxContainer.new()
	if separation >= 0:
		box.add_theme_constant_override("separation", separation)
	return box


static func expander() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE  # A spacer must never swallow clicks meant for what is behind it.
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func panel(style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	if style != null:
		p.add_theme_stylebox_override("panel", style)
	return p


static func scroll(horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not horizontal:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


static func hp_bar(current: int, maximum: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = current
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill_color := UITheme.GREEN if current > maximum * 0.35 else UITheme.CRIMSON
	bar.add_theme_stylebox_override("fill", UITheme.box(fill_color, Color.TRANSPARENT, 6, 0, 2))
	return bar


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Icon from the art catalog (semantic name such as "health" or "burn"). Falls back to a short
## glyph label of the same size so missing art never leaves a hole in the layout.
static func icon(icon_name: String, size: int = 24, fallback_glyph: String = "") -> Control:
	return _icon_control(AssetCatalog.icon(icon_name), size, fallback_glyph if fallback_glyph != "" else icon_name.left(1).to_upper())


## Same, but by catalog asset id (used for specialization icons).
static func icon_by_id(asset_id: String, size: int = 24, fallback_glyph: String = "*") -> Control:
	return _icon_control(AssetCatalog.icon_by_id(asset_id), size, fallback_glyph)


static func _icon_control(texture: Texture2D, size: int, glyph: String) -> Control:
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(size, size)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var l := label(glyph, &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(size, size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Icon followed by a text label, e.g. a gold or block counter.
static func icon_text(icon_name: String, text: String, size: int = 22, variation: StringName = &"") -> HBoxContainer:
	var row := hbox(4)
	row.add_child(icon(icon_name, size))
	var l := label(text, variation)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row
