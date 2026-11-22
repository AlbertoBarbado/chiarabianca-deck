class_name RoomBackdrop
extends Control
## Full-screen room backdrop: catalog art (cover-fitted), a room-type colour wash and a dark
## veil so text and controls on top stay readable. Without art it is the plain navy gradient.


## Cover-fit art; when the screen is wider than the picture, this share of the cropped height is
## taken from the top (0.5 = centred). Battle backdrops crop mostly from the sky so the floor the
## units stand on stays in view (see combat_screen.gd).
var anchor_y: float = 0.5
## Extra scale on top of the cover fit (1 = none). With anchor_y 1 it crops sky and keeps the
## bottom: used for battle pictures whose floor starts too low for the units' feet line.
var zoom: float = 1.0
var _art: TextureRect


## info: {texture: Texture2D or null, tint: Color, anchor_y: float (optional)}. dim: veil opacity
## (0 = art at full strength).
func setup(info: Dictionary, dim: float = 0.62) -> void:
	UIFactory.clear_children(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(self)
	clip_contents = true
	var base := TextureRect.new()
	var texture: Texture2D = info.get("texture")
	anchor_y = clampf(float(info.get("anchor_y", 0.5)), 0.0, 1.0)
	zoom = maxf(1.0, float(info.get("zoom", 1.0)))
	_art = null
	if texture != null:
		base.texture = texture
		base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if not is_equal_approx(anchor_y, 0.5) or zoom > 1.0:
			_art = base  # sized by _fit_art: cover-fitted with the chosen vertical anchor
			base.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		var gradient := Gradient.new()
		gradient.set_color(0, UITheme.NAVY_DEEP)
		gradient.set_color(1, UITheme.NAVY)
		var gradient_texture := GradientTexture2D.new()
		gradient_texture.gradient = gradient
		gradient_texture.fill_from = Vector2(0, 0)
		gradient_texture.fill_to = Vector2(0, 1)
		base.texture = gradient_texture
		base.stretch_mode = TextureRect.STRETCH_SCALE
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	if _art != null:
		if not resized.is_connected(_fit_art):
			resized.connect(_fit_art)
		_fit_art()
	else:
		UIFactory.full_rect(base)
	if texture == null:
		return
	var wash := ColorRect.new()
	wash.color = Color(info.get("tint", Color(0.3, 0.4, 0.8)), float(info.get("wash_alpha", 0.22)))
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(wash)
	add_child(wash)
	var veil := ColorRect.new()
	veil.color = Color(UITheme.NAVY_DEEP, dim)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(veil)
	add_child(veil)


## The picture's rectangle on screen for a given area: cover-fitted, horizontally centred, the
## vertical overflow split by anchor_y. Shared by the layout and the floor checks in the tests.
static func cover_rect(area: Vector2, texture_size: Vector2, p_anchor_y: float, p_zoom: float = 1.0) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2(Vector2.ZERO, area)
	var scale := maxf(area.x / texture_size.x, area.y / texture_size.y) * maxf(1.0, p_zoom)
	var drawn := texture_size * scale
	return Rect2(Vector2((area.x - drawn.x) / 2.0, (area.y - drawn.y) * p_anchor_y), drawn)


func _fit_art() -> void:
	if _art == null or _art.texture == null:
		return
	var rect := cover_rect(size, _art.texture.get_size(), anchor_y, zoom)
	_art.position = rect.position
	_art.size = rect.size
