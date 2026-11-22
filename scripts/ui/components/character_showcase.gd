class_name CharacterShowcase
extends Control
## Large character illustration (transparent cutout) with a soft accent glow behind her and a
## gentle entrance (fade + short slide). The picture keeps its aspect ratio, is never cropped and
## never takes input. Used on the title screen, the Tutorial Complete screen and character selection.

const ENTRANCE_TIME := 0.7
const SLIDE_PIXELS := 36.0
const EDGE_FADE := 0.07
const FADE_SHADER := "shader_type canvas_item;
uniform float fade = 0.07;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = smoothstep(0.0, fade, UV.x) * smoothstep(0.0, fade, 1.0 - UV.x) * smoothstep(0.0, fade, 1.0 - UV.y);
	COLOR = vec4(c.rgb, c.a * a);
}
"

var _art: TextureRect
## How much wider than this control the picture may be (1 = never). A wide figure (Chiara's spread
## cape) then fills the height like a narrow one instead of shrinking; set clip_contents to cut the
## overflow at the edges.
var max_overflow: float = 1.0


## slide_from: -1 slides in from the left, 1 from the right, 0 only fades.
## fade_edges softens the left, right and bottom edges for art that is cut off by its canvas.
func setup(character_id: String, accent: Color, slide_from: int = 0, delay: float = 0.0, fade_edges: bool = false) -> void:
	UIFactory.clear_children(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(120, 160)
	var glow_texture := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(accent, 0.38))
	gradient.set_color(1, Color(accent, 0.0))
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.55)
	glow_texture.fill_to = Vector2(0.5, 0.0)
	var glow := TextureRect.new()
	glow.texture = glow_texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(glow)
	add_child(glow)
	_art = TextureRect.new()
	_art.texture = AssetCatalog.figure(character_id)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fade_edges:
		var shader := Shader.new()
		shader.code = FADE_SHADER
		var material := ShaderMaterial.new()
		material.shader = shader
		_art.material = material
	add_child(_art)
	if not resized.is_connected(_fit):
		resized.connect(_fit)
	_fit()
	if SettingsStore.load_values().get("effects_quality", "full") == "off":
		return
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(self, "modulate:a", 1.0, ENTRANCE_TIME).set_trans(Tween.TRANS_SINE)
	if slide_from != 0:
		_art.position.x = slide_from * SLIDE_PIXELS
		tween.parallel().tween_property(_art, "position:x", 0.0, ENTRANCE_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## Fits the picture inside this control keeping its aspect ratio, bottom-aligned and centred.
func _fit() -> void:
	if _art == null or _art.texture == null:
		return
	var source := _art.texture.get_size()
	var factor := minf(size.x * maxf(1.0, max_overflow) / source.x, size.y / source.y)
	var fitted := source * factor
	_art.size = fitted
	_art.position = Vector2((size.x - fitted.x) / 2.0 + _art.position.x * 0.0, size.y - fitted.y)
