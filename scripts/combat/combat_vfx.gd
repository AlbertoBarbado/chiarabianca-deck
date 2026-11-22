class_name CombatVfx
extends Control
## One combat visual effect: a sprite that plays a short animation at a target and then frees
## itself. Pure presentation: it ignores input, never reads combat state and can be created with
## or without its scene (scenes/combat/combat_vfx.tscn); the Sprite child is built on demand.
##
## Motions (data "motion"): projectile (travels from the source to the target, then emits
## `impact`), burst (expands, flashes, fades), pulse (pops in around the target, settles, fades),
## rise (floats up and fades: healing, Burn), sweep (slides across the target area).

signal impact(at: Vector2)
signal finished

const FADE_IN_TIME := 0.08
const FADE_OUT_START := 0.6
const FALLBACK_SIZE := 64
const BURST_START_SCALE := 0.55
const BURST_END_SCALE := 1.08

static var _additive_material: CanvasItemMaterial = null

var effect_id: String = ""
var used_fallback: bool = false
var motion: String = "burst"
var total_time: float = 0.0
var progress: float = 0.0

var _sprite: TextureRect
var _center: Vector2 = Vector2.ZERO
var _end_center: Vector2 = Vector2.ZERO
var _impact_fraction: float = 0.0
var _impact_sent: bool = false
var _opacity: float = 1.0
var _tween: Tween


## Layout of an effect in layer coordinates (testable without nodes).
## target_rects / source_rect are in the layer's local space; view_scale = layer height / 720.
## Returns {size, center, start, end, group}: `center` is where the sprite rests, `start` / `end`
## are the projectile path.
static func compute_geometry(def: Dictionary, texture_size: Vector2, target_rects: Array[Rect2], source_rect: Rect2, view_scale: float, reference_width: float) -> Dictionary:
	var union: Rect2 = target_rects[0]
	for rect in target_rects:
		union = union.merge(rect)
	var width := float(def.get("width", 120.0)) * view_scale
	var group := target_rects.size() > 1 and def.has("group_fit")
	if group:
		width = maxf(width, union.size.x * float(def.get("group_fit", 1.0)))
		if def.has("group_max"):
			width = minf(width, float(def["group_max"]) * view_scale)
	else:
		width *= clampf(union.size.x / reference_width, 0.75, 1.5)
	var aspect := texture_size.y / texture_size.x if texture_size.x > 0.0 else 1.0
	var size := Vector2(width, width * aspect)
	var center := union.get_center()
	if str(def.get("anchor", "center")) == "ground":
		center.y = union.end.y - size.y * 0.42
	var start := center
	if source_rect.has_area() and not source_rect.is_equal_approx(union):
		start = source_rect.get_center()
	else:
		start = center - Vector2(size.x * 0.9, size.y * 0.2)
	return {"size": size, "center": center, "start": start, "end": union.get_center(), "group": group}


static func make_fallback_texture(color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, 0.9))
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = FALLBACK_SIZE
	texture.height = FALLBACK_SIZE
	return texture


static func _get_additive_material() -> CanvasItemMaterial:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material


## Texture size an effect will be drawn with (the fallback when the sprite file is missing).
static func resolve_texture(def: Dictionary) -> Dictionary:
	var texture := VfxCatalog.sprite_texture(def)
	if texture != null:
		return {"texture": texture, "fallback": false}
	return {"texture": make_fallback_texture(Color.from_string(str(def.get("color", "")), Color.WHITE)), "fallback": true}


## Starts the effect. `quality` is a VfxCatalog quality dictionary; `delay` staggers effects
## that resolve together.
func play(p_effect_id: String, def: Dictionary, geometry: Dictionary, quality: Dictionary, delay: float = 0.0) -> void:
	effect_id = p_effect_id
	motion = str(def.get("motion", "burst"))
	_opacity = clampf(float(def.get("opacity", 1.0)), 0.0, 1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_sprite()
	var resolved := resolve_texture(def)
	used_fallback = resolved["fallback"]
	_sprite.texture = resolved["texture"]
	_sprite.material = _get_additive_material() if str(def.get("blend", "mix")) == "add" else null
	var size_value: Vector2 = geometry["size"]
	size = size_value
	pivot_offset = size_value / 2.0
	_center = geometry["start"] if motion == "projectile" else geometry["center"]
	_end_center = geometry["end"]
	position = _center - size_value / 2.0
	total_time = maxf(0.05, float(def.get("duration", 0.6)) * float(quality.get("duration_scale", 1.0)))
	_impact_fraction = clampf(float(def.get("travel", 0.5)) / maxf(0.05, float(def.get("duration", 0.6))), 0.05, 0.95)
	modulate.a = 0.0
	if motion == "projectile":
		rotation = (_end_center - _center).angle()
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_method(_apply, 0.0, 1.0, total_time)
	_tween.tween_callback(_finish)


## Evaluates the animation at normalised time t (0..1). Public so tests can sample it.
func _apply(t: float) -> void:
	progress = t
	var fade_in := minf(1.0, t * total_time / FADE_IN_TIME)
	var fade_out := 1.0 - smoothstep(FADE_OUT_START, 1.0, t)
	var s := 1.0
	var offset := Vector2.ZERO
	match motion:
		"projectile":
			var p := minf(1.0, t / _impact_fraction)
			position = _center.lerp(_end_center, p * p) - size / 2.0
			fade_out = 1.0 if p < 1.0 else 1.0 - smoothstep(0.0, 1.0, (t - _impact_fraction) / maxf(0.01, 1.0 - _impact_fraction))
			if p >= 1.0 and not _impact_sent:
				_impact_sent = true
				impact.emit(_end_center)
		"pulse":
			s = 0.65 + 0.45 * _ease_out(minf(1.0, t / 0.35)) if t < 0.35 else 1.1 - 0.1 * ((t - 0.35) / 0.65)
		"rise":
			s = lerpf(0.8, 1.0, _ease_out(t))
			offset = Vector2(0.0, -size.y * 0.22 * t)
		"sweep":
			offset = Vector2(lerpf(-size.x * 0.12, size.x * 0.12, t), 0.0)
		_:
			s = lerpf(BURST_START_SCALE, BURST_END_SCALE, _ease_out(t))
	scale = Vector2(s, s)
	if motion != "projectile":
		position = _center - size / 2.0 + offset
	modulate.a = fade_in * fade_out * _opacity


func _finish() -> void:
	finished.emit()
	queue_free()


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = get_node_or_null("Sprite") as TextureRect
	if _sprite == null:
		_sprite = TextureRect.new()
		_sprite.name = "Sprite"
		add_child(_sprite)
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
