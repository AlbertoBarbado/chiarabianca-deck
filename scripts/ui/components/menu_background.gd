class_name MenuBackground
extends Control
## Full-screen backdrop for the menu screens: the castle illustration (cover-fitted), a slow
## horizontal drift, a readability vignette and a few floating particles (sparkles, blue orbs,
## embers). It never takes input. The Settings "Combat effects" quality also scales the
## ambience: Full = drift + particles, Reduced = fewer particles, no drift, Off = static image.

const BACKGROUND_ASSET := "menu_background"
const DRIFT_PIXELS := 18.0
const DRIFT_TIME := 26.0
const OVERSCAN := 40.0

var _image: TextureRect
var _emitters: Array[CPUParticles2D] = []
var _additive: CanvasItemMaterial


## dim: extra darkness over the picture so text on top stays readable (0 = none).
func setup(dim: float = 0.28) -> void:
	UIFactory.clear_children(self)
	_emitters.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(self)
	clip_contents = true
	var quality := str(SettingsStore.load_values().get("effects_quality", "full"))

	_image = TextureRect.new()
	_image.texture = AssetCatalog.texture(BACKGROUND_ASSET)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _image.texture == null:  # Missing art: plain midnight gradient.
		_image.texture = _gradient_texture(UITheme.NAVY_DEEP, UITheme.NAVY)
		_image.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_image)
	_layout_image(0.0)

	_add_vignette(dim)
	if quality != "off":
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		var scale_amount := 1.0 if quality == "full" else 0.5
		_add_emitter("effects/fx_sparkle", int(16 * scale_amount), 9.0, Vector2(0.18, 0.32), Color(1, 0.92, 0.7, 0.9))
		_add_emitter("effects/fx_blue_orb", int(10 * scale_amount), 11.0, Vector2(0.16, 0.3), Color(0.7, 0.85, 1, 0.8))
		_add_emitter("effects/fx_ember", int(8 * scale_amount), 8.0, Vector2(0.3, 0.5), Color(1, 0.8, 0.5, 0.9))
	if quality == "full" and is_inside_tree():
		_start_drift()
	resized.connect(_on_resized)
	_on_resized()


func _layout_image(offset_x: float) -> void:
	_image.position = Vector2(-OVERSCAN + offset_x, 0)
	_image.size = size + Vector2(OVERSCAN * 2.0, 0)


func _on_resized() -> void:
	if _image == null:
		return
	_layout_image(_image.position.x + OVERSCAN)
	for emitter in _emitters:
		emitter.position = size / 2.0
		emitter.emission_rect_extents = size / 2.0


func _start_drift() -> void:
	var tween := create_tween().set_loops()
	tween.tween_method(_layout_image, -DRIFT_PIXELS, DRIFT_PIXELS, DRIFT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_layout_image, DRIFT_PIXELS, -DRIFT_PIXELS, DRIFT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _add_vignette(dim: float) -> void:
	var veil := ColorRect.new()
	veil.color = Color(UITheme.NAVY_DEEP, dim)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(veil)
	add_child(veil)
	# Darker top and bottom edges keep titles and footers readable.
	for edge in [0, 1]:
		var texture := _gradient_texture(Color(UITheme.NAVY_DEEP, 0.75), Color(UITheme.NAVY_DEEP, 0.0))
		var band := TextureRect.new()
		band.texture = texture
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.flip_v = edge == 1
		band.anchor_right = 1.0
		band.anchor_top = 0.0 if edge == 0 else 0.72
		band.anchor_bottom = 0.28 if edge == 0 else 1.0
		add_child(band)


func _gradient_texture(from: Color, to: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	return texture


## Slowly rising glow particles; one CPUParticles2D per family (cheap, no per-particle nodes).
func _add_emitter(sprite: String, amount: int, lifetime: float, scale_range: Vector2, tint: Color) -> void:
	var texture := UIAssets.texture(sprite)
	if texture == null or amount <= 0:
		return
	var emitter := CPUParticles2D.new()
	emitter.texture = texture
	emitter.material = _additive
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.preprocess = lifetime
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emitter.emission_rect_extents = Vector2(640, 360)
	emitter.direction = Vector2(0, -1)
	emitter.spread = 35.0
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity_min = 6.0
	emitter.initial_velocity_max = 22.0
	emitter.scale_amount_min = scale_range.x * 0.5
	emitter.scale_amount_max = scale_range.y * 0.5
	emitter.angular_velocity_min = -20.0
	emitter.angular_velocity_max = 20.0
	emitter.color = tint
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	emitter.color_ramp = ramp
	add_child(emitter)
	_emitters.append(emitter)
