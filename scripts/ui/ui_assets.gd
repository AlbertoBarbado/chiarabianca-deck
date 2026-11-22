class_name UIAssets
extends RefCounted
## Loader for the processed UI art (assets/ui/<group>/<name>.png, produced by
## scripts/tools/extract_ui_assets.py from the generated sheets in assets/ui/general/).
## Everything degrades gracefully: a missing file returns null and callers fall back to flat styles.

const ROOT := "res://assets/ui/"

static var _cache: Dictionary = {}


## id is "<group>/<name>", e.g. "buttons/button_plain" or "icons/icon_heart".
static func texture(id: String) -> Texture2D:
	var path := ROOT + id + ".png"
	if _cache.has(path):
		return _cache[path] as Texture2D
	var loaded: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_cache[path] = loaded
	return loaded


static func icon(name: String) -> Texture2D:
	return texture("icons/icon_" + name)


## Texture resized by `factor` (decorative frames are generated large; nine-patch margins are
## measured in texture pixels, so the frame is scaled to its on-screen size first).
static func scaled(id: String, factor: float) -> Texture2D:
	var key := "%s@%.3f" % [id, factor]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var source := texture(id)
	var result: Texture2D = null
	if source != null:
		var image := source.get_image()
		if image != null:
			image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
			result = ImageTexture.create_from_image(image)
	_cache[key] = result
	return result


## Nine-patch style from a decorative frame. `margins` = (left, top, right, bottom) in *source*
## pixels; `content` = inner padding in on-screen pixels. Null when the art is missing.
static func nine_patch(id: String, factor: float, margins: Vector4, content: Vector4, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var tex := scaled(id, factor)
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = margins.x * factor
	style.texture_margin_top = margins.y * factor
	style.texture_margin_right = margins.z * factor
	style.texture_margin_bottom = margins.w * factor
	style.content_margin_left = content.x
	style.content_margin_top = content.y
	style.content_margin_right = content.z
	style.content_margin_bottom = content.w
	style.modulate_color = tint
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style
