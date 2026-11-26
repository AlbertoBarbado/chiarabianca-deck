class_name OrnateButton
extends Button
## A JRPG menu button (docs/ART_DIRECTION.md §8): pointed enamel bar with gold rims and filigree end
## caps (UIKit "btn_primary" violet / "btn_secondary" navy), an optional painted icon in a round gold
## socket on its left end, and Cinzel text with a soft shadow. Keyboard focus shows the gold hover rim
## instead of a rectangular ring. Without the kit it falls back to the theme's button styles, so it is
## always a normal, fully functional Button (mouse, touch, keyboard).

const SOCKET_SHARE := 0.86
const ICON_SHARE := 0.6

var _socket: Control
var _icon_rect: TextureRect
## Resting and lit (hover / keyboard focus) styles, after any icon padding.
var _rest: StyleBox
var _lit: StyleBox


## text, catalog icon id ("" = none), primary (violet) or secondary (navy), minimum size.
static func create(label: String, icon_id: String = "", primary: bool = false, min_size: Vector2 = Vector2(300, 60)) -> OrnateButton:
	var button := OrnateButton.new()
	button.text = label
	button.custom_minimum_size = min_size
	button._apply_style(primary)
	button._add_icon(icon_id)
	return button


func _apply_style(primary: bool) -> void:
	var piece := "btn_primary" if primary else "btn_secondary"
	if not UIKit.style_button(self, piece):
		theme_type_variation = &"PrimaryButton" if primary else &""
		return
	_rest = get_theme_stylebox("normal")
	_lit = get_theme_stylebox("hover")
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	focus_entered.connect(func() -> void: add_theme_stylebox_override("normal", _lit))
	focus_exited.connect(func() -> void: add_theme_stylebox_override("normal", _rest))
	add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_BUTTON))
	add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON + 2)
	add_theme_color_override("font_color", Color("f6ecd2"))
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_focus_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color("ffe6a8"))
	add_theme_color_override("font_disabled_color", Color(0.75, 0.72, 0.68, 0.55))
	add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.14, 0.85))
	add_theme_constant_override("outline_size", 5)


## The icon sits in a round gold socket over the button's left end (decoration only: no input).
func _add_icon(icon_id: String) -> void:
	var texture := UIKit.picture(icon_id) if icon_id != "" else null
	if texture == null:
		return
	_socket = Control.new()
	_socket.name = "IconSocket"
	_socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_socket)
	var frame_texture := UIKit.picture("frame_socket")
	if frame_texture != null:
		var frame := TextureRect.new()
		frame.texture = frame_texture
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIFactory.full_rect(frame)
		_socket.add_child(frame)
	_icon_rect = TextureRect.new()
	_icon_rect.texture = texture
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_socket.add_child(_icon_rect)
	# The text starts after the socket: every state's content margin grows by the socket width.
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var box := get_theme_stylebox(state)
		if box is StyleBoxTexture:
			var padded := (box as StyleBoxTexture).duplicate() as StyleBoxTexture
			padded.content_margin_left += custom_minimum_size.y * SOCKET_SHARE + 6.0
			padded.content_margin_right += 4.0
			add_theme_stylebox_override(state, padded)
			if state == "normal":
				_rest = padded
			elif state == "hover":
				_lit = padded
	resized.connect(_place_icon)
	_place_icon.call_deferred()


func _place_icon() -> void:
	if _socket == null:
		return
	var side := size.y * SOCKET_SHARE
	_socket.size = Vector2(side, side)
	_socket.position = Vector2(size.y * 0.58, (size.y - side) / 2.0)
	var inner := side * ICON_SHARE
	_icon_rect.position = Vector2.ONE * (side - inner) / 2.0
	_icon_rect.size = Vector2(inner, inner)
	_socket.modulate = Color(0.55, 0.55, 0.6) if disabled else Color.WHITE
