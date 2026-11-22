class_name CardView
extends Control
## Reusable card widget (hand, rewards, shops, piles, rests, party overview).
##
## The card is drawn on a fixed 300 x 428 "face" laid out in absolute design coordinates and scaled
## to the control's size. The face is twice the usual on-screen size, so text and edges are
## supersampled: crisp in the hand, when a hovered card zooms in, and on large reward cards.
##
## Face, top to bottom:
##   cost orb (energy gem, overlapping the top-left corner; the number turns red when unaffordable)
##   name ribbon, coloured by rarity (stone / silver / teal / gold / violet)
##   illustration window whose silhouette shows the type (attack: blade point, spell: arch,
##     power: oval, other: rectangle) with a gold border
##   type plaque ("Attack", "Spell"...) in the type's colour
##   rules panel: keywords, damage types and numbers highlighted (green numbers when upgraded)
##   owner medallion: the owning princess's portrait in her colour
## The frame and body are a shader (bevelled metal, owner-coloured rim, graded body) with an outer
## glow for the hand states: playable (soft, breathing), hovered (bright) and selected (gold).
## Click / tap emits `pressed`. Works for runtime CardInstances and for plain definitions.

signal pressed(card_view: CardView)

const CARD_SIZE := Vector2(150, 214)
const FACE := Vector2(300, 428)
const GLOW_MARGIN := 26.0
const ART_RECT := Rect2(24, 80, 252, 146)
const TEXT_RECT := Rect2(24, 258, 252, 124)
const ORB_CENTER := Vector2(36, 36)
const ORB_RADIUS := 30.0
const MEDALLION_CENTER := Vector2(150, 404)
const MEDALLION_RADIUS := 21.0
const NAME_FONT := 30
const MIN_NAME_FONT := 19
const TEXT_FONT := 27
const MIN_TEXT_FONT := 19

const RARITY_RIBBON := {
	"basic": Color("4f5763"),
	"common": Color("6f7e92"),
	"uncommon": Color("23707c"),
	"rare": Color("a8761f"),
	"epic": Color("6b34a6"),
}
const TYPE_COLORS := {
	"attack": Color("e8664f"),
	"skill": Color("5cc49a"),
	"spell": Color("7f9bff"),
	"defense": Color("8fc2e8"),
	"support": Color("e9c75c"),
	"power": Color("c77dff"),
}
const ENERGY_LIGHT := Color("8fd6ff")
const ENERGY_DARK := Color("1d4f9e")
const COST_UNAFFORDABLE := Color("ff6a5c")
const GLOW_PLAYABLE := Color(0.3, 0.78, 1.0, 0.95)
const GLOW_HOVER := Color(1.0, 0.95, 0.75, 0.95)
const GLOW_SELECTED := Color(1.0, 0.78, 0.25, 1.0)

static var _frame_shader: Shader
static var _art_shader: Shader
static var _body_font: FontVariation
static var _body_bold: FontVariation

var card: CardInstance = null
## In combat: the damage this card would deal now (CardEffects.damage_preview), shown in place of the
## printed numbers. Set it before show_instance; empty = printed numbers.
var damage_preview: Array = []
var definition: CardDef = null
var owner_id: String = ""
## True when even the smallest readable font could not fit the card's text (hover shows it whole).
var text_clipped := false
## The hand turns this on: playable cards then glow softly (rewards and shops show no glow).
var show_playable_glow := false:
	set(value):
		show_playable_glow = value
		_refresh_state()

var _selected := false
var _playable := true
var _hovered := false
var _upgraded := false
var _face: Control
var _frame: ColorRect
var _frame_mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _name_label: Label
var _text_label: RichTextLabel
var _cost_label: Label
var _full_text := ""
var _fit_queued := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = CARD_SIZE
	resized.connect(_fit_face)


## Shows a runtime card (combat).
func show_instance(instance: CardInstance) -> void:
	card = instance
	_show(instance.definition, instance.owner_character_id, instance.get_card_name(),
		instance.get_cost(), instance.get_description(), instance.is_upgraded())


## Shows a definition for a given owner (deck inspection outside combat). A temporary
## CardInstance is used so upgraded cards show their upgraded name, cost and text.
func show_owned(def: CardDef, p_owner_id: String, upgrade_level: int = 0) -> void:
	var preview := CardInstance.new()
	preview.definition = def
	preview.owner_character_id = p_owner_id
	preview.upgrade_level = upgrade_level
	show_instance(preview)
	card = null


## Scales the card (keeps the aspect ratio) for large previews such as rewards.
func set_scale_factor(factor: float) -> void:
	custom_minimum_size = CARD_SIZE * factor
	_fit_face()


func set_selected(value: bool) -> void:
	_selected = value
	_refresh_state()


func set_playable(value: bool) -> void:
	_playable = value
	_refresh_state()


## Pointer over the card (the hand calls this; it also enlarges the card).
func set_hovered(value: bool) -> void:
	_hovered = value
	_refresh_state()


func is_playable() -> bool:
	return _playable


# --- Building the face ----------------------------------------------------------------------------

func _show(def: CardDef, p_owner_id: String, card_name: String, cost: int, description: String, upgraded: bool) -> void:
	definition = def
	owner_id = p_owner_id
	_upgraded = upgraded
	_ensure_resources()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var owner_def := DataRegistry.get_character(p_owner_id)
	var owner_color: Color = owner_def.accent_color if owner_def != null else UITheme.SILVER
	var spec := DataRegistry.get_specialization(def.specialization_id)

	_face = Control.new()
	_face.name = "Face"
	_face.size = FACE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	# Frame, body and glow (one shader, drawn GLOW_MARGIN beyond the card on every side).
	_frame = ColorRect.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2(-GLOW_MARGIN, -GLOW_MARGIN)
	_frame.size = FACE + Vector2(GLOW_MARGIN, GLOW_MARGIN) * 2.0
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = _frame_shader
	_frame_mat.set_shader_parameter("rect_size", _frame.size)
	_frame_mat.set_shader_parameter("margin", GLOW_MARGIN)
	_frame_mat.set_shader_parameter("rim_color", owner_color)
	_frame_mat.set_shader_parameter("body_top", owner_color.darkened(0.6).lerp(Color("182238"), 0.35))
	_frame_mat.set_shader_parameter("body_bottom", owner_color.darkened(0.86).lerp(Color("070a12"), 0.4))
	_frame_mat.set_shader_parameter("shimmer", 1.0 if def.rarity == "epic" else 0.0)
	_frame.material = _frame_mat
	_face.add_child(_frame)

	_face.add_child(_make_ornaments(owner_color))
	_face.add_child(_make_art(def, spec, owner_color))
	_face.add_child(_make_ribbon(def, card_name, upgraded))
	_face.add_child(_make_cost_orb(cost))
	_face.add_child(_make_type_plaque(def))
	_face.add_child(_make_text_panel(description, upgraded))
	_face.add_child(_make_medallion(p_owner_id, owner_color, spec))
	_full_text = "%s\n%s" % [card_name, description]
	tooltip_text = ""
	_fit_face()
	_refresh_state()
	_queue_fit()


static func _ensure_resources() -> void:
	if _frame_shader == null:
		_frame_shader = load("res://resources/shaders/card_frame.gdshader") as Shader
		_art_shader = load("res://resources/shaders/card_art.gdshader") as Shader
	if _body_font == null:
		_body_font = FontVariation.new()
		_body_font.base_font = ThemeDB.fallback_font
		_body_font.variation_embolden = 0.25
		_body_bold = FontVariation.new()
		_body_bold.base_font = ThemeDB.fallback_font
		_body_bold.variation_embolden = 0.9


## Scales the face to the control (keeping the aspect ratio, centred).
func _fit_face() -> void:
	if _face == null:
		return
	var area := size if size.x > 0.0 and size.y > 0.0 else custom_minimum_size
	var s := minf(area.x / FACE.x, area.y / FACE.y)
	_face.scale = Vector2(s, s)
	_face.position = (area - FACE * s) / 2.0


func _make_art(def: CardDef, spec: SpecializationDef, owner_color: Color) -> Control:
	var art := CardArt.new()
	art.name = "Art"
	art.position = ART_RECT.position
	art.size = ART_RECT.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := def.get_art_texture()
	if texture == null:
		texture = AssetCatalog.texture(AssetCatalog.card_art_id(def.id, def.specialization_id, def.card_type))
	art.texture = texture if texture != null else _fallback_art(spec, owner_color)
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = _art_shader
	_art_mat.set_shader_parameter("rect_size", ART_RECT.size)
	_art_mat.set_shader_parameter("shape", _art_shape(def.card_type))
	art.material = _art_mat
	art.art_material = _art_mat
	return art


static func _art_shape(card_type: String) -> int:
	match card_type:
		"attack":
			return 1
		"spell":
			return 2
		"power":
			return 3
	return 0


## No illustration: a radial wash in the owner's colour with the specialization emblem baked in.
func _fallback_art(spec: SpecializationDef, owner_color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, owner_color.lightened(0.1))
	gradient.set_color(1, owner_color.darkened(0.8))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.45)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 256
	texture.height = 160
	var icon := AssetCatalog.icon_by_id(spec.icon_id) if spec != null and spec.icon_id != "" else null
	return icon if icon != null else texture


func _make_ribbon(def: CardDef, card_name: String, upgraded: bool) -> Control:
	var ribbon := CardRibbon.new()
	ribbon.name = "Ribbon"
	ribbon.position = Vector2(6, 34)
	ribbon.size = Vector2(288, 50)
	ribbon.color = RARITY_RIBBON.get(def.rarity, RARITY_RIBBON["common"])
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.name = "CardName"
	_name_label.text = card_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.position = Vector2(64, 0)
	_name_label.size = Vector2(206, 50)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_font := UITheme.font(UITheme.WEIGHT_HEADER)
	if title_font != null:
		_name_label.add_theme_font_override("font", title_font)
	_name_label.add_theme_font_size_override("font_size", NAME_FONT)
	_name_label.add_theme_color_override("font_color", UpgradeTint.name_color(upgraded))
	_name_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.95))
	_name_label.add_theme_constant_override("outline_size", 7)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	ribbon.add_child(_name_label)
	return ribbon


func _make_cost_orb(cost: int) -> Control:
	var orb := CostOrb.new()
	orb.name = "CostOrb"
	orb.position = ORB_CENTER - Vector2(ORB_RADIUS + 4, ORB_RADIUS + 4)
	orb.size = Vector2(ORB_RADIUS + 4, ORB_RADIUS + 4) * 2.0
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_label = Label.new()
	_cost_label.name = "Cost"
	_cost_label.text = "X" if definition != null and definition.x_cost else str(cost)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.size = orb.size
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := UITheme.font(UITheme.WEIGHT_TITLE)
	if font != null:
		_cost_label.add_theme_font_override("font", font)
	_cost_label.add_theme_font_size_override("font_size", 38)
	_cost_label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.16, 1.0))
	_cost_label.add_theme_constant_override("outline_size", 9)
	orb.add_child(_cost_label)
	return orb


func _make_type_plaque(def: CardDef) -> Control:
	var color: Color = TYPE_COLORS.get(def.card_type, UITheme.SILVER)
	var plaque := PanelContainer.new()
	plaque.name = "TypePlaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(13)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.anti_aliasing = true
	plaque.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "CardType"
	label.text = def.card_type.capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := UITheme.font(UITheme.WEIGHT_HEADER)
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", color.lightened(0.25))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(label)
	plaque.custom_minimum_size = Vector2(118, 30)
	plaque.size = Vector2(118, 30)
	plaque.position = Vector2((FACE.x - 118.0) / 2.0, ART_RECT.end.y - 2)
	return plaque


func _make_text_panel(description: String, upgraded: bool) -> Control:
	var panel := Panel.new()
	panel.name = "RulesPanel"
	panel.position = TEXT_RECT.position
	panel.size = TEXT_RECT.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.72)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	_text_label = RichTextLabel.new()
	_text_label.name = "CardText"
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.fit_content = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_label.position = Vector2(10, 6)
	_text_label.size = TEXT_RECT.size - Vector2(20, 12)
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.add_theme_font_override("normal_font", _body_font)
	_text_label.add_theme_font_override("bold_font", _body_bold)
	_text_label.add_theme_color_override("default_color", Color("e9e4d8"))
	_text_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_text_label.add_theme_constant_override("outline_size", 4)
	_text_label.add_theme_constant_override("line_separation", 1)
	_set_text_size(TEXT_FONT)
	_text_label.text = CardTextFormat.to_bbcode(description, upgraded, damage_preview)
	panel.add_child(_text_label)
	return panel


func _set_text_size(font_size: int) -> void:
	_text_label.add_theme_font_size_override("normal_font_size", font_size)
	_text_label.add_theme_font_size_override("bold_font_size", font_size)


func _make_medallion(p_owner_id: String, owner_color: Color, spec: SpecializationDef) -> Control:
	var medallion := OwnerMedallion.new()
	medallion.name = "OwnerMedallion"
	medallion.position = MEDALLION_CENTER - Vector2(MEDALLION_RADIUS + 3, MEDALLION_RADIUS + 3)
	medallion.size = Vector2(MEDALLION_RADIUS + 3, MEDALLION_RADIUS + 3) * 2.0
	medallion.rim = owner_color
	medallion.portrait = AssetCatalog.portrait_face_round(p_owner_id)
	medallion.emblem = AssetCatalog.icon_by_id(spec.icon_id) if spec != null and spec.icon_id != "" else null
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return medallion


## Gold rivets in the frame corners and a fine gold filigree under the rules panel.
func _make_ornaments(owner_color: Color) -> Control:
	var ornaments := CardOrnaments.new()
	ornaments.name = "Ornaments"
	ornaments.size = FACE
	ornaments.accent = owner_color
	ornaments.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ornaments


# --- States ---------------------------------------------------------------------------------------

func _refresh_state() -> void:
	if _frame_mat == null:
		return
	var glow := 0.0
	var color := GLOW_PLAYABLE
	var pulse := 0.0
	if _selected:
		glow = 1.0
		color = GLOW_SELECTED
		pulse = 1.0
	elif _hovered and _playable:
		glow = 0.95
		color = GLOW_HOVER
	elif show_playable_glow and _playable:
		glow = 0.8
		pulse = 1.0
	_frame_mat.set_shader_parameter("glow", glow)
	_frame_mat.set_shader_parameter("glow_color", color)
	_frame_mat.set_shader_parameter("glow_pulse", pulse)
	var dim := not _playable
	_frame_mat.set_shader_parameter("desaturate", 0.55 if dim else 0.0)
	_frame_mat.set_shader_parameter("darken", 0.28 if dim else 0.0)
	if _art_mat != null:
		_art_mat.set_shader_parameter("desaturate", 0.6 if dim else 0.0)
		_art_mat.set_shader_parameter("darken", 0.3 if dim else 0.0)
	if _cost_label != null:
		_cost_label.add_theme_color_override("font_color", COST_UNAFFORDABLE if dim and show_playable_glow else Color.WHITE)
	if _text_label != null:
		_text_label.modulate = Color(0.78, 0.78, 0.78) if dim else Color.WHITE


## Exhaust / play-out effect: 0 = intact, 1 = burnt away (frame and contents fade together).
func set_dissolve(amount: float) -> void:
	if _frame_mat != null:
		_frame_mat.set_shader_parameter("dissolve", amount)


# --- Text fitting ---------------------------------------------------------------------------------

func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit_text.call_deferred()


## Shrinks the name to one line and the rules text until it fits its panel; if the text still does
## not fit at a readable size, hovering the card shows the whole text (tooltip). Never truncates silently.
func _fit_text() -> void:
	_fit_queued = false
	if _name_label == null or _text_label == null or not is_instance_valid(_text_label):
		return
	var name_size := NAME_FONT
	var font := _name_label.get_theme_font("font")
	while name_size > MIN_NAME_FONT and font != null and font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > _name_label.size.x - 4.0:
		name_size -= 1
	_name_label.add_theme_font_size_override("font_size", name_size)
	var name_fits := font == null or font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x <= _name_label.size.x - 4.0
	var text_size := TEXT_FONT
	_set_text_size(text_size)
	while _text_label.get_content_height() > _text_label.size.y and text_size > MIN_TEXT_FONT:
		text_size -= 1
		_set_text_size(text_size)
	var fits := _text_label.get_content_height() <= _text_label.size.y + 1.0
	text_clipped = not fits or not name_fits
	tooltip_text = _full_text if text_clipped else ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


# --- Drawn parts ----------------------------------------------------------------------------------

## Upgraded names are green with a "+" (the CardInstance already adds it).
class UpgradeTint:
	static func name_color(upgraded: bool) -> Color:
		return Color("9dff8a") if upgraded else Color("fbf3dc")


## The illustration, cover-fitted, drawn through the art shader (silhouette + gold border).
class CardArt extends Control:
	var texture: Texture2D
	var art_material: ShaderMaterial

	func _draw() -> void:
		if texture == null:
			return
		var tex_size := texture.get_size()
		var scale_factor := maxf(size.x / tex_size.x, size.y / tex_size.y)
		var region_size := size / scale_factor
		var region := Rect2((tex_size - region_size) / 2.0, region_size)
		if art_material != null:
			# Shader UVs refer to the underlying image: for an atlas (a picture cut from a sheet)
			# the visible region sits inside the sheet.
			var base_size := tex_size
			var offset := Vector2.ZERO
			if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
				base_size = (texture as AtlasTexture).atlas.get_size()
				offset = (texture as AtlasTexture).region.position
			art_material.set_shader_parameter("uv_min", (offset + region.position) / base_size)
			art_material.set_shader_parameter("uv_max", (offset + region.end) / base_size)
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), region)


## Name ribbon: a banner with folded tails, a lighter upper half and a dark outline.
class CardRibbon extends Control:
	var color := Color("6f7e92")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var tail := 16.0
		var fold := 9.0
		# Tails behind the band (darker), then the band itself.
		var dark := color.darkened(0.45)
		draw_colored_polygon(PackedVector2Array([Vector2(0, fold), Vector2(tail + 6, fold), Vector2(tail + 6, h + fold), Vector2(0, h + fold), Vector2(tail * 0.6, h * 0.5 + fold)]), dark)
		draw_colored_polygon(PackedVector2Array([Vector2(w, fold), Vector2(w - tail - 6, fold), Vector2(w - tail - 6, h + fold), Vector2(w, h + fold), Vector2(w - tail * 0.6, h * 0.5 + fold)]), dark)
		var band := PackedVector2Array([Vector2(tail, 0), Vector2(w - tail, 0), Vector2(w - tail, h), Vector2(tail, h)])
		draw_colored_polygon(band, color)
		draw_colored_polygon(PackedVector2Array([Vector2(tail, 0), Vector2(w - tail, 0), Vector2(w - tail, h * 0.45), Vector2(tail, h * 0.45)]), color.lightened(0.18))
		draw_line(Vector2(tail, h * 0.45), Vector2(w - tail, h * 0.45), Color(1, 1, 1, 0.08), 2.0, true)
		var outline := PackedVector2Array(band)
		outline.append(band[0])
		draw_polyline(outline, Color(0.05, 0.04, 0.03, 0.9), 3.0, true)
		draw_line(Vector2(tail + 4, 3), Vector2(w - tail - 4, 3), Color(1, 1, 1, 0.22), 1.5, true)


## Cost orb: a glossy energy gem in a gold-rimmed dark setting.
class CostOrb extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(c.x, c.y) - 4.0
		draw_circle(c + Vector2(0, 3), r + 4.0, Color(0, 0, 0, 0.45), true, -1.0, true)
		draw_circle(c, r + 4.0, Color("2a2216"), true, -1.0, true)
		draw_circle(c, r + 2.5, Color("d9b25e"), true, -1.0, true)
		draw_circle(c, r, CardView.ENERGY_DARK, true, -1.0, true)
		for i in 7:
			var t := float(i) / 7.0
			draw_circle(c + Vector2(-r * 0.12, -r * 0.14) * t, r * (1.0 - t * 0.78), CardView.ENERGY_DARK.lerp(CardView.ENERGY_LIGHT, t * 0.85), true, -1.0, true)
		draw_circle(c + Vector2(-r * 0.32, -r * 0.38), r * 0.26, Color(1, 1, 1, 0.38), true, -1.0, true)
		draw_arc(c, r + 2.5, 0.0, TAU, 48, Color("6b5320"), 1.5, true)


## Owner medallion: the owning princess's round portrait in a ring of her colour.
class OwnerMedallion extends Control:
	var rim := Color.WHITE
	var portrait: Texture2D
	var emblem: Texture2D

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(c.x, c.y) - 3.0
		draw_circle(c + Vector2(0, 2), r + 3.0, Color(0, 0, 0, 0.5), true, -1.0, true)
		draw_circle(c, r + 3.0, Color("1a1610"), true, -1.0, true)
		draw_circle(c, r + 1.5, rim, true, -1.0, true)
		var image := portrait if portrait != null else emblem
		if image != null:
			draw_texture_rect(image, Rect2(c - Vector2(r, r) * 0.92, Vector2(r, r) * 1.84), false)
		draw_arc(c, r + 1.5, 0.0, TAU, 40, rim.lightened(0.35), 1.5, true)


## Corner rivets and side filigree drawn over the frame.
class CardOrnaments extends Control:
	var accent := Color.WHITE

	func _draw() -> void:
		var gold := Color("d9b25e")
		for corner in [Vector2(size.x - 17, 17), Vector2(17, size.y - 17), Vector2(size.x - 17, size.y - 17)]:
			draw_circle(corner + Vector2(0, 1.5), 6.5, Color(0, 0, 0, 0.5), true, -1.0, true)
			draw_circle(corner, 6.0, gold.darkened(0.35), true, -1.0, true)
			draw_circle(corner, 4.2, gold, true, -1.0, true)
			draw_circle(corner + Vector2(-1.4, -1.4), 1.6, Color(1, 1, 1, 0.7), true, -1.0, true)
		# Short filigree strokes either side of the type plaque and the medallion.
		var y_plaque := CardView.ART_RECT.end.y + 13.0
		for side: float in [-1.0, 1.0]:
			var x0: float = size.x / 2.0 + side * 64.0
			draw_line(Vector2(x0, y_plaque), Vector2(x0 + side * 52.0, y_plaque), Color(gold, 0.7), 2.0, true)
			draw_circle(Vector2(x0 + side * 56.0, y_plaque), 2.6, gold, true, -1.0, true)
			var xm: float = size.x / 2.0 + side * 30.0
			draw_line(Vector2(xm, CardView.MEDALLION_CENTER.y), Vector2(xm + side * 70.0, CardView.MEDALLION_CENTER.y), Color(accent, 0.55), 2.0, true)