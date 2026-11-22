class_name DollStage
extends Control
## The character on the equipment screen: her idle pose standing on a glowing pedestal, with a soft
## aura in her specialization colour behind her. It is also a drop target (an item dropped on her
## goes to the slot it fits): the screen sets `drop_check` / `drop_handler`, and set_drop_state
## lights the aura while a valid item is carried.

var accent: Color = UITheme.GOLD
var drop_check: Callable
var drop_handler: Callable

var _figure: TextureRect
var _highlight: bool = false
var _time: float = 0.0


func setup(texture: Texture2D, p_accent: Color) -> void:
	accent = p_accent
	mouse_filter = Control.MOUSE_FILTER_PASS
	_figure = TextureRect.new()
	_figure.name = "Figure"
	_figure.texture = texture
	_figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_figure.offset_top = 6
	_figure.offset_bottom = -18
	add_child(_figure)
	set_process(SettingsStore.load_values().get("effects_quality", "full") != "off")


func figure() -> TextureRect:
	return _figure


func set_drop_state(on: bool) -> void:
	_highlight = on
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var breathe := 0.5 + 0.5 * sin(_time * 1.6)
	var centre := Vector2(size.x / 2.0, size.y * 0.5)
	var strength := 1.6 if _highlight else 1.0
	# Aura: a smooth radial glow in the specialization colour.
	var r := minf(size.x, size.y) * 0.55
	draw_texture_rect(ItemTile.radial_glow(), Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), false,
		Color(accent, 0.32 * strength * (0.85 + 0.15 * breathe)))
	# Pedestal: a soft ellipse of light under her feet with a gold rim.
	var base := Vector2(size.x / 2.0, size.y - 20.0)
	var radii := Vector2(size.x * 0.32, 13.0)
	draw_texture_rect(ItemTile.radial_glow(), Rect2(base - radii * 1.3, radii * 2.6), false,
		Color(accent.lerp(UITheme.GOLD, 0.5), 0.55 * strength))
	_draw_ellipse_outline(base, radii, Color(UITheme.GOLD, 0.55 + 0.2 * breathe * (1.0 if _highlight else 0.4)))


func _draw_ellipse(c: Vector2, r: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		points.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(points, color)


func _draw_ellipse_outline(c: Vector2, r: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		points.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(points, color, 1.5, true)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and drop_check.is_valid() and bool(drop_check.call(data))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if drop_handler.is_valid():
		drop_handler.call(data)
