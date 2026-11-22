class_name FramedArt
extends Control
## A scene illustration (town, merchant) cover-fitted into a gold frame with a soft inner shade.
## `focus` picks which part of the picture stays visible when it is cropped (0..1 on each axis;
## 0.5, 0.5 = centre), so a merchant standing at the left third stays in view in a tall frame.
## A missing texture draws nothing: the screen keeps working without the art.

const FRAME_WIDTH := 3.0
const CORNER_RADIUS := 3  # the picture itself is square-cornered

var texture: Texture2D
var focus: Vector2 = Vector2(0.5, 0.5)

var _frame: Panel


static func create(asset_id: String, min_size: Vector2, p_focus: Vector2 = Vector2(0.5, 0.5)) -> FramedArt:
	var art := FramedArt.new()
	art.texture = AssetCatalog.texture(asset_id)
	art.focus = p_focus
	art.custom_minimum_size = min_size
	art.name = "FramedArt"
	return art


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(int(FRAME_WIDTH))
	style.border_color = UITheme.GOLD
	style.set_corner_radius_all(CORNER_RADIUS)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	UIFactory.full_rect(_frame)
	resized.connect(queue_redraw)


func has_art() -> bool:
	return texture != null


func _draw() -> void:
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var tex_size := texture.get_size()
	# Cover: the largest region of the picture with the frame's aspect ratio, placed by `focus`.
	var aspect := size.x / size.y
	var region := Rect2(Vector2.ZERO, tex_size)
	if tex_size.x / tex_size.y > aspect:
		region.size.x = tex_size.y * aspect
		region.position.x = clampf(tex_size.x * focus.x - region.size.x / 2.0, 0.0, tex_size.x - region.size.x)
	else:
		region.size.y = tex_size.x / aspect
		region.position.y = clampf(tex_size.y * focus.y - region.size.y / 2.0, 0.0, tex_size.y - region.size.y)
	var inset := Rect2(Vector2.ONE * FRAME_WIDTH, size - Vector2.ONE * FRAME_WIDTH * 2.0)
	draw_texture_rect_region(texture, inset, region)
	# A gentle shade at the bottom so text placed under or over the picture stays readable.
	var shade_height := size.y * 0.28
	var top := Color(0, 0, 0, 0.0)
	var bottom := Color(0, 0, 0, 0.45)
	draw_polygon(
		PackedVector2Array([Vector2(inset.position.x, inset.end.y - shade_height), Vector2(inset.end.x, inset.end.y - shade_height), inset.end, Vector2(inset.position.x, inset.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
