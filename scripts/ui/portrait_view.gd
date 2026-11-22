class_name PortraitView
extends PanelContainer
## Character art tile. Shows the catalog portrait (or the full figure) with a frame in the
## specialization's accent colour, a soft accent tint and a small specialization badge.
## One component serves every character and specialization: only data differs.


## Falls back to an initial-letter tile when the character has no art.
func setup(char_def: CharacterDef, spec: SpecializationDef, tile_size: Vector2, use_figure: bool = false, show_badge: bool = true) -> void:
	UIFactory.clear_children(self)
	custom_minimum_size = tile_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent := spec.get_accent(char_def.accent_color) if spec != null else char_def.accent_color
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), accent, 12, 3, 0))

	var texture := AssetCatalog.figure(char_def.id) if use_figure else AssetCatalog.portrait_face(char_def.id)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
	else:
		var initial := UIFactory.label(char_def.display_name.left(1), &"", false, HORIZONTAL_ALIGNMENT_CENTER)
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", int(minf(tile_size.x, tile_size.y) * 0.55))
		initial.add_theme_color_override("font_color", accent)
		add_child(initial)
	if spec == null:
		return
	# Specialization identity: accent tint, a glow along the bottom edge and a badge.
	var tint := ColorRect.new()
	tint.color = Color(accent, 0.14)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	if use_figure:
		add_child(_bottom_glow(accent))
	if show_badge and spec.icon_id != "":
		var holder := MarginContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			holder.add_theme_constant_override("margin_" + side, 3)
		var badge_size := 36 if use_figure else clampi(int(minf(tile_size.x, tile_size.y) * 0.34), 18, 30)
		var badge := UIFactory.icon_by_id(spec.icon_id, badge_size)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		badge.size_flags_vertical = Control.SIZE_SHRINK_END
		holder.add_child(badge)
		add_child(holder)


func _bottom_glow(accent: Color) -> Control:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(accent, 0.0))
	gradient.set_color(1, Color(accent, 0.38))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0.55)
	texture.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
