class_name UIKit
extends RefCounted
## The composed nine-patch UI kit (assets/generated/ui_kit, built by scripts/tools/compose_ui_kit.py
## from generated materials and ornaments; docs/ART_DIRECTION.md §4 and §8). Each piece becomes a
## StyleBoxTexture whose margins come from kit.json, so ornaments never stretch. Missing pieces return
## null and callers fall back to the previous styles, so the game always works without the art.
##
## Pieces: plaque_parchment(_hover/_pressed), plaque_locked, panel_navy, panel_navy_small,
## button_violet(_hover/_pressed/_disabled), button_navy(_hover/_pressed/_disabled).

const KIT_DIR := "res://assets/generated/ui_kit"
## On-screen size of the kit's texture pixels (the kit is drawn at ~2x for sharp corners on large screens).
const SCALE := 0.5

static var _kit: Dictionary = {}
static var _loaded := false
static var _styles: Dictionary = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var path := KIT_DIR + "/kit.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_kit = parsed if parsed is Dictionary else {}


static func has(piece: String) -> bool:
	_ensure()
	return _kit.has(piece) and ResourceLoader.exists("%s/%s.png" % [KIT_DIR, piece])


## A StyleBoxTexture for a kit piece, or null when the piece is missing. scale: on-screen size factor
## of the borders (1 = SCALE).
static func style(piece: String, scale: float = 1.0) -> StyleBoxTexture:
	var key := "%s@%s" % [piece, scale]
	if _styles.has(key):
		return _styles[key]
	if not has(piece):
		return null
	var entry: Dictionary = _kit[piece]
	var box := StyleBoxTexture.new()
	box.texture = load("%s/%s.png" % [KIT_DIR, piece]) as Texture2D
	var margins: Array = entry.get("texture_margin", [0, 0, 0, 0])
	var content: Array = entry.get("content_margin", [0, 0, 0, 0])
	box.texture_margin_left = float(margins[0])
	box.texture_margin_top = float(margins[1])
	box.texture_margin_right = float(margins[2])
	box.texture_margin_bottom = float(margins[3])
	# Draw the borders at a fraction of their texture size (the kit is composed at high resolution).
	var draw_scale := SCALE * scale
	box.content_margin_left = float(content[0]) * scale
	box.content_margin_top = float(content[1]) * scale
	box.content_margin_right = float(content[2]) * scale
	box.content_margin_bottom = float(content[3]) * scale
	box.set_meta("draw_scale", draw_scale)
	_scale_borders(box, draw_scale)
	_styles[key] = box
	return box


## StyleBoxTexture draws its borders at texture size; to draw them smaller the texture margins stay
## and the texture is shrunk through a scaled ImageTexture copy.
static func _scale_borders(box: StyleBoxTexture, draw_scale: float) -> void:
	if is_equal_approx(draw_scale, 1.0) or box.texture == null:
		return
	var image := box.texture.get_image()
	if image == null:
		return
	if image.is_compressed():
		image.decompress()
	var w := maxi(8, int(round(image.get_width() * draw_scale)))
	var h := maxi(8, int(round(image.get_height() * draw_scale)))
	image.resize(w, h, Image.INTERPOLATE_LANCZOS)
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left *= draw_scale
	box.texture_margin_top *= draw_scale
	box.texture_margin_right *= draw_scale
	box.texture_margin_bottom *= draw_scale


## A UI picture by art catalog id (data/art/art_catalog.json, category "ui"), or null when missing.
static func picture(asset_id: String) -> Texture2D:
	return AssetCatalog.texture(asset_id) if asset_id != "" else null


## Applies a family of states to a Button: base piece "<name>" and "<name>_hover/_pressed/_disabled".
## Returns false (and changes nothing) when the kit is missing.
static func style_button(button: Button, name: String, scale: float = 1.0) -> bool:
	var normal := style(name, scale)
	if normal == null:
		return false
	button.add_theme_stylebox_override("normal", normal)
	for state in ["hover", "pressed", "disabled"]:
		var box := style("%s_%s" % [name, state], scale)
		button.add_theme_stylebox_override(state, box if box != null else normal)
	button.add_theme_stylebox_override("hover_pressed", style(name + "_pressed", scale) if has(name + "_pressed") else normal)
	return true


static func clear_cache() -> void:
	_loaded = false
	_kit.clear()
	_styles.clear()
