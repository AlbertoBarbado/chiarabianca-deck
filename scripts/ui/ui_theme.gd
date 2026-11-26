class_name UITheme
extends RefCounted
## Shared palette, fonts and the global Theme: midnight blue, antique gold and ivory, with the
## ornamental frame art from assets/ui (see UIAssets) for buttons and panels. If the art or the
## font is missing, flat styles with the same palette are used, so the UI always works.
## Sizes are tuned for touch: large default font and tall buttons.

const NAVY_DEEP := Color("0a1230")
const NAVY := Color("14224a")
const NAVY_LIGHT := Color("22377a")
const IVORY := Color("f4efe0")
const IVORY_DIM := Color("b9b4a4")
const GOLD := Color("d4a64a")
const GOLD_DARK := Color("8a6a26")
const SILVER := Color("c9d1dc")
const CRIMSON := Color("b23a48")
const GREEN := Color("4f9d6a")
const MAGIC_BLUE := Color("5aa0ff")
## Size of the kit's pointed button borders on ordinary buttons (OrnateButton menu buttons use 1.0).
const KIT_BUTTON_SCALE := 0.78
## Art direction palette additions (docs/ART_DIRECTION.md §2).
const VIOLET := Color("3a1f6e")
const VIOLET_LIGHT := Color("7a4fc4")
const LAVENDER := Color("b8b0d6")
const INK := Color("3b2a1a")
const INK_SOFT := Color("6b5236")
const BOND_PINK := Color("ff9fb8")

const FONT_SIZE_DEFAULT := 20
const FONT_SIZE_SMALL := 16
const FONT_SIZE_HEADER := 30
const FONT_SIZE_TITLE := 60
const FONT_SIZE_BUTTON := 20

const DISPLAY_FONT_PATH := "res://resources/fonts/Cinzel.ttf"  # SIL OFL 1.1, see docs/ASSET_LICENSES.md
const WEIGHT_TITLE := 800
const WEIGHT_HEADER := 650
const WEIGHT_BUTTON := 600

# Decorative frame art: source-pixel margins of the nine-patch cuts and on-screen scale factors.
const BUTTON_PLAIN := "buttons/button_plain"
const BUTTON_ORNATE := "buttons/button_ornate"
const PANEL_ORNATE := "panels/panel_rect_ornate"
const BUTTON_SCALE := 0.34
const PANEL_SCALE := 0.7

static var _theme: Theme = null


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 10, border_width: int = 2, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


## Display / heading font: Cinzel at a variable-font weight, or null (built-in font) if missing.
static func font(weight: int) -> Font:
	if not ResourceLoader.exists(DISPLAY_FONT_PATH):
		return null
	var variation := FontVariation.new()
	variation.base_font = load(DISPLAY_FONT_PATH) as Font
	variation.variation_opentype = {"wght": weight}
	return variation


## Ornate frame for a large panel (falls back to a flat navy box).
static func ornate_panel_style(tint: Color = Color.WHITE) -> StyleBox:
	var kit := _kit_panel("panel_navy", Vector4(36, 34, 36, 34), tint)
	if kit != null:
		return kit
	var style := UIAssets.nine_patch(PANEL_ORNATE, PANEL_SCALE, Vector4(62, 56, 62, 56), Vector4(36, 34, 36, 34), tint)
	return style if style != null else box(Color(NAVY, 0.92), GOLD_DARK, 12, 2, 14)


## The UI kit's navy enamel panel (docs/ART_DIRECTION.md) with the given content margins and tint, or
## null without the kit. Keeping the old content margins keeps every existing layout unchanged.
static func _kit_panel(piece: String, content: Vector4, tint: Color) -> StyleBox:
	var base := UIKit.style(piece)
	if base == null:
		return null
	var style := base.duplicate() as StyleBoxTexture
	style.content_margin_left = content.x
	style.content_margin_top = content.y
	style.content_margin_right = content.z
	style.content_margin_bottom = content.w
	style.modulate_color = tint
	return style


## Slim version of the ornate panel for bars, popups and tooltips (same art, smaller frame).
static func compact_panel_style(scale: float = 0.3, content: Vector4 = Vector4(16, 10, 16, 10), tint: Color = Color.WHITE) -> StyleBox:
	var kit := _kit_panel("panel_navy_small", content, tint)
	if kit != null:
		return kit
	var style := UIAssets.nine_patch(PANEL_ORNATE, scale, Vector4(62, 56, 62, 56), content, tint)
	return style if style != null else box(Color(NAVY, 0.92), GOLD_DARK, 10, 2, 8)


## Slim plain-gold button for small controls (pile buttons).
static func compact_button_style(tint: Color = Color.WHITE) -> StyleBox:
	# Small controls (pile and potion buttons, map labels): the kit's navy enamel at a small scale.
	var kit := UIKit.style("button_navy", 0.55)
	if kit != null:
		var small := kit.duplicate() as StyleBoxTexture
		small.content_margin_left = 10
		small.content_margin_right = 10
		small.content_margin_top = 3
		small.content_margin_bottom = 3
		small.modulate_color = tint
		return small
	var style := UIAssets.nine_patch(BUTTON_PLAIN, 0.2, Vector4(70, 58, 70, 58), Vector4(10, 3, 10, 3), tint)
	return style if style != null else box(NAVY.lerp(tint, 0.1), GOLD_DARK, 8, 2, 4)


## Gold portrait frame for cards and compact combat holders (nine-patch from the decorative sheet).
static func card_frame_style(tint: Color = Color.WHITE, scale: float = 0.5, content: Vector4 = Vector4(14, 12, 14, 10)) -> StyleBox:
	var style := UIAssets.nine_patch("panels/frame_portrait", scale, Vector4(34, 34, 34, 34), content, tint)
	return style if style != null else box(NAVY_DEEP, GOLD_DARK, 10, 2, 8)


## Button frame: plain gold double frame (stretches cleanly). `tint` darkens or brightens a state.
static func button_style(tint: Color = Color.WHITE, ornate: bool = false) -> StyleBox:
	var id := BUTTON_ORNATE if ornate else BUTTON_PLAIN
	var margins := Vector4(78, 62, 78, 62) if ornate else Vector4(70, 58, 70, 58)
	var style := UIAssets.nine_patch(id, BUTTON_SCALE, margins, Vector4(18, 8, 18, 8), tint)
	if style != null:
		return style
	return box(NAVY_LIGHT.lerp(tint, 0.2), GOLD_DARK, 10, 2, 14)


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE_DEFAULT

	theme.set_color("font_color", "Label", IVORY)
	theme.set_constant("line_spacing", "Label", 2)

	theme.set_stylebox("panel", "PanelContainer", ornate_panel_style())
	theme.set_stylebox("panel", "Panel", ornate_panel_style())
	# Every tooltip (hover help) uses the same ornate frame and the game font.
	theme.set_stylebox("panel", "TooltipPanel", compact_panel_style(0.32, Vector4(18, 12, 18, 12)))
	theme.set_color("font_color", "TooltipLabel", IVORY)
	theme.set_font_size("font_size", "TooltipLabel", FONT_SIZE_SMALL)

	_style_button(theme, "Button", false)
	_style_button(theme, "PrimaryButton", true)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_type_variation("SecondaryButton", "Button")
	_style_button(theme, "SecondaryButton", false)

	theme.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.5), Color(GOLD_DARK, 0.6), 6, 1, 2))
	theme.set_stylebox("fill", "ProgressBar", box(GREEN, Color.TRANSPARENT, 6, 0, 2))
	theme.set_color("font_color", "ProgressBar", IVORY)

	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	theme.set_constant("h_separation", "HFlowContainer", 10)
	theme.set_constant("v_separation", "HFlowContainer", 10)

	var display := font(WEIGHT_TITLE)
	var heading := font(WEIGHT_HEADER)
	theme.add_type("TitleLabel")
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", FONT_SIZE_TITLE)
	theme.set_color("font_color", "TitleLabel", GOLD)
	if display != null:
		theme.set_font("font", "TitleLabel", display)

	theme.add_type("HeaderLabel")
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_font_size("font_size", "HeaderLabel", FONT_SIZE_HEADER)
	theme.set_color("font_color", "HeaderLabel", GOLD)
	if heading != null:
		theme.set_font("font", "HeaderLabel", heading)

	theme.add_type("DimLabel")
	theme.set_type_variation("DimLabel", "Label")
	theme.set_color("font_color", "DimLabel", IVORY_DIM)

	# Toggle buttons (specialization choice): the selected (pressed) state glows gold.
	_style_button(theme, "ToggleButton", false)
	theme.set_type_variation("ToggleButton", "Button")
	# Selected toggles turn violet (the primary enamel); without the kit they glow gold.
	theme.set_stylebox("pressed", "ToggleButton", UIKit.style("btn_primary", KIT_BUTTON_SCALE) if UIKit.has("btn_primary") else button_style(Color(1.5, 1.32, 0.78), false))
	theme.set_stylebox("hover_pressed", "ToggleButton", UIKit.style("btn_primary_hover", KIT_BUTTON_SCALE) if UIKit.has("btn_primary") else button_style(Color(1.62, 1.44, 0.88), false))
	theme.set_color("font_pressed_color", "ToggleButton", Color(1, 0.93, 0.7))
	theme.set_color("font_hover_pressed_color", "ToggleButton", Color.WHITE)

	# Settings controls share the button frame and gold accents.
	_style_button(theme, "OptionButton", false)
	_style_dropdown(theme)
	_style_button(theme, "CheckButton", false)
	theme.set_stylebox("panel", "PopupMenu", _kit_panel("panel_navy_small", Vector4(12, 10, 12, 10), Color.WHITE) if UIKit.has("panel_navy_small") else box(Color(NAVY_DEEP, 0.97), GOLD_DARK, 8, 2, 8))
	theme.set_stylebox("hover", "PopupMenu", box(Color(NAVY_LIGHT, 0.9), GOLD, 6, 1, 4))
	theme.set_color("font_color", "PopupMenu", IVORY)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_stylebox("slider", "HSlider", box(Color(0, 0, 0, 0.55), Color(GOLD_DARK, 0.8), 4, 1, 2))
	theme.set_stylebox("grabber_area", "HSlider", box(GOLD_DARK, Color.TRANSPARENT, 4, 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, Color.TRANSPARENT, 4, 0, 2))
	var on_icon := UIAssets.scaled("icons/icon_check", 0.12)
	var off_icon := UIAssets.scaled("icons/icon_close", 0.1)
	if on_icon != null and off_icon != null:
		for state_name in ["checked", "checked_disabled"]:
			theme.set_icon(state_name, "CheckButton", on_icon)
		for state_name in ["unchecked", "unchecked_disabled"]:
			theme.set_icon(state_name, "CheckButton", off_icon)
	var knob := UIAssets.scaled("icons/icon_star", 0.14)
	if knob != null:
		theme.set_icon("grabber", "HSlider", knob)
		theme.set_icon("grabber_highlight", "HSlider", knob)
		theme.set_icon("grabber_disabled", "HSlider", knob)
	return theme


## Button states: normal / hover (brighter) / pressed (darker) / disabled (dim) / focus (blue glow).
## With the composed UI kit (UIKit) buttons are navy enamel and the primary button violet enamel,
## both with gold frames; without it the previous concept-board frames are used.
## Dropdowns (OptionButton) are fields, not actions: the rectangular navy enamel frame with room for
## the arrow on the right, so their text never runs into a pointed end cap.
static func _style_dropdown(theme: Theme) -> void:
	if not UIKit.has("button_navy"):
		return
	for entry in [["normal", Color.WHITE], ["hover", Color(1.3, 1.22, 1.08)], ["pressed", Color(0.72, 0.74, 0.92)], ["hover_pressed", Color(0.8, 0.82, 1.0)], ["focus", Color(1.2, 1.2, 1.4)], ["disabled", Color(0.6, 0.6, 0.66, 0.7)]]:
		var box := compact_button_style(entry[1]) as StyleBoxTexture
		box = box.duplicate() as StyleBoxTexture
		box.content_margin_left = 16
		box.content_margin_right = 34
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		theme.set_stylebox(str(entry[0]), "OptionButton", box)
	theme.set_constant("arrow_margin", "OptionButton", 12)
	theme.set_color("font_focus_color", "OptionButton", Color.WHITE)


static func _style_button(theme: Theme, type_name: String, ornate: bool) -> void:
	# Every button in the game uses the pointed JRPG shape of the UI kit (docs/ART_DIRECTION.md §13):
	# violet for primary actions, navy for the rest, drawn a little slimmer than the big OrnateButton
	# menu buttons. Keyboard focus lights the gold rim (drawn under the text) instead of a box.
	var piece := "btn_primary" if ornate else "btn_secondary"
	if UIKit.has(piece):
		var states := {"normal": "", "hover": "_hover", "pressed": "_pressed", "hover_pressed": "_pressed", "disabled": "_disabled", "focus": "_hover"}
		for state: String in states:
			theme.set_stylebox(state, type_name, UIKit.style(piece + str(states[state]), KIT_BUTTON_SCALE))
	else:
		theme.set_stylebox("normal", type_name, button_style(Color.WHITE, ornate))
		theme.set_stylebox("hover", type_name, button_style(Color(1.3, 1.22, 1.08), ornate))
		theme.set_stylebox("pressed", type_name, button_style(Color(0.72, 0.74, 0.92), ornate))
		theme.set_stylebox("disabled", type_name, button_style(Color(0.42, 0.42, 0.5, 0.85), ornate))
		theme.set_stylebox("focus", type_name, box(Color.TRANSPARENT, Color(MAGIC_BLUE, 0.9), 14, 2, 14))
	theme.set_color("font_color", type_name, IVORY)
	theme.set_color("font_hover_color", type_name, Color.WHITE)
	theme.set_color("font_pressed_color", type_name, Color(1, 0.95, 0.8))
	theme.set_color("font_disabled_color", type_name, Color(IVORY_DIM, 0.5))
	theme.set_font_size("font_size", type_name, FONT_SIZE_BUTTON)
	var button_font := font(WEIGHT_BUTTON)
	if button_font != null:
		theme.set_font("font", type_name, button_font)
