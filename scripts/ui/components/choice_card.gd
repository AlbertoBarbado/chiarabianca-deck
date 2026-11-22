class_name ChoiceCard
extends Button
## A large choice row for rooms that offer options (treasure, events, towns): an emblem on the left,
## a gold title and a wrapped description, in the ornate panel art, with hover and pressed looks.
## It is a real Button (pressed signal, disabled state, keyboard focus), so screens and tests use it
## like any other button.

const ICON_SIZE := 54.0

## The option the player took: stays bright with a gold frame even after the choice is locked.
var chosen: bool = false:
	set(value):
		chosen = value
		if value:
			add_theme_stylebox_override("disabled", UITheme.compact_panel_style(0.3, Vector4(18, 10, 18, 10), Color(1.5, 1.32, 0.78)))
		queue_redraw()

var _title: Label
var _description: Label
var _icon: TextureRect


## icon_id: a UIAssets id such as "icons/icon_chest" ("" = no emblem).
static func create(title: String, description: String, icon_id: String = "", accent: Color = UITheme.GOLD) -> ChoiceCard:
	var card := ChoiceCard.new()
	card._build(title, description, icon_id, accent)
	return card


func _build(title: String, description: String, icon_id: String, accent: Color) -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("normal", UITheme.compact_panel_style(0.3, Vector4(18, 10, 18, 10)))
	add_theme_stylebox_override("hover", UITheme.compact_panel_style(0.3, Vector4(18, 10, 18, 10), Color(1.35, 1.25, 1.05)))
	add_theme_stylebox_override("pressed", UITheme.compact_panel_style(0.3, Vector4(18, 10, 18, 10), Color(0.75, 0.78, 0.95)))
	add_theme_stylebox_override("disabled", UITheme.compact_panel_style(0.3, Vector4(18, 10, 18, 10), Color(0.5, 0.5, 0.56, 0.9)))
	add_theme_stylebox_override("focus", UITheme.box(Color.TRANSPARENT, Color(UITheme.MAGIC_BLUE, 0.9), 12, 2, 6))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var texture := UIAssets.texture(icon_id) if icon_id != "" else null
	if texture != null:
		_icon = TextureRect.new()
		_icon.texture = texture
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_icon)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)
	_title = UIFactory.label(title, &"HeaderLabel")
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 1)
	_title.add_theme_color_override("font_color", accent)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)
	_description = UIFactory.label(description, &"", true)
	_description.name = "Description"
	_description.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_description.add_theme_color_override("font_color", UITheme.IVORY)
	_description.custom_minimum_size.x = 0
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description.visible = description != ""
	column.add_child(_description)
	_row = row
	_place_row()
	resized.connect(_place_row)
	_place_row.call_deferred()


const PADDING := Vector2(22, 14)
var _row: HBoxContainer


## A Button does not lay out its children: the content row is placed inside the frame by hand, and
## the card asks for the height the row needs (wrapped descriptions grow it).
func _place_row() -> void:
	if _row == null:
		return
	var needed := _needed_size()
	if absf(custom_minimum_size.y - needed.y) > 1.0:
		custom_minimum_size.y = needed.y
	# Anchored to the card with fixed padding: the row follows every resize by itself, also when a
	# list of cards is rebuilt and laid out again (no stale positions).
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = PADDING.x
	_row.offset_top = PADDING.y
	_row.offset_right = -PADDING.x
	_row.offset_bottom = -PADDING.y


## Height the card needs (Button ignores a scripted _get_minimum_size, so this feeds custom_minimum_size).
func _needed_size() -> Vector2:
	if _row == null:
		return Vector2(0, 62)
	var inner := Vector2(0, 0)
	# Wrapped text reports one line until it has a width: estimate the lines for the current width.
	if _description != null and _description.visible and size.x > 0.0:
		var text_width := maxf(80.0, size.x - PADDING.x * 2.0 - (ICON_SIZE + 14.0 if _icon != null else 0.0))
		var font := _description.get_theme_font("font")
		var font_size := _description.get_theme_font_size("font_size")
		var line_w := font.get_string_size(_description.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var lines := maxi(1, ceili(line_w / text_width))
		var text_h := _title.get_combined_minimum_size().y + 2.0 + lines * font.get_height(font_size)
		inner.y = maxf(inner.y, text_h)
	inner.y = maxf(inner.y, ICON_SIZE if _icon != null else 0.0)
	if _title != null and not (_description != null and _description.visible and size.x > 0.0):
		inner.y = maxf(inner.y, _title.get_combined_minimum_size().y)
	return Vector2(inner.x + PADDING.x * 2.0, maxf(62.0, inner.y + PADDING.y * 2.0))


func set_texts(title: String, description: String) -> void:
	_title.text = title
	_description.text = description
	_description.visible = description != ""


func get_title() -> String:
	return _title.text


func get_description() -> String:
	return _description.text


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW or what == NOTIFICATION_ENABLED or what == NOTIFICATION_DISABLED:
		if _title != null:
			modulate = Color(1, 1, 1, 0.55) if disabled and not chosen else Color.WHITE
