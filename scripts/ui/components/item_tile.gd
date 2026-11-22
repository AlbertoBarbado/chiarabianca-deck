class_name ItemTile
extends Button
## Touch-sized tile for one equipment item or an equipment slot. Drawn, not styled: a dark inset
## socket, a radial glow and a frame in the item's rarity colour, a rarity gem in the corner, the
## item picture, and for an empty slot a faint engraved glyph of what goes there.
##
## Tiles are drag sources and drop targets. The screen decides what is allowed through two
## callables (drop_check(data) -> bool, drop_handler(data)); while something is dragged the screen
## lights the tiles that would accept it (set_drop_state). Tap / click still works everywhere
## (`pressed`), so drag and drop is never required - important on touch screens.

signal drag_started(data: Dictionary)

const SIZE := Vector2(78, 78)
const GLYPH_DIR := "res://assets/generated/ui/"
const HOVER_SCALE := 1.06
const DRAG_TYPE := "equipment"

enum DropState { NONE, VALID, INVALID, TARGET }

var item_id: String = ""
var slot: String = ""
## "stash" or "slot": where a drag from this tile starts.
var source: String = "stash"
var character_id: String = ""
var drop_check: Callable
var drop_handler: Callable

var _picture: TextureRect
var _caption: Label
var _selected: bool = false
var _hovered: bool = false
var _drop_state: DropState = DropState.NONE
var _rarity_color: Color = UITheme.GOLD_DARK
var _glyph: Texture2D
var _pulse: float = 0.0
var _lift: Tween


## item_id may be "" (an empty slot: shows the slot's glyph and name instead).
static func create(p_item_id: String, p_slot: String = "", tile_size: Vector2 = SIZE) -> ItemTile:
	var tile := ItemTile.new()
	tile.item_id = p_item_id
	tile.slot = p_slot
	tile.custom_minimum_size = tile_size
	tile.focus_mode = Control.FOCUS_ALL
	tile._build()
	return tile


static var _radial: GradientTexture2D


## A soft white radial glow (opaque centre, transparent edge), shared; tint it when drawing.
static func radial_glow() -> GradientTexture2D:
	if _radial == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.45))
		_radial = GradientTexture2D.new()
		_radial.gradient = gradient
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 256
		_radial.height = 256
	return _radial


## Engraved silhouette for an empty slot ("ring_1" and "ring_2" share "ring"); null if absent.
static func slot_glyph(slot_id: String) -> Texture2D:
	var path := GLYPH_DIR + "slot_%s.png" % ("ring" if slot_id.begins_with("ring") else slot_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _build() -> void:
	var def := Equipment.item(item_id)
	_rarity_color = Equipment.rarity_color(str(def.get("rarity", "common"))) if not def.is_empty() else UITheme.GOLD_DARK
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		_picture.set_offset(side, 9)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		_picture.set_offset(side, -9)
	add_child(_picture)
	_caption = Label.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.offset_bottom = -4
	_caption.add_theme_font_size_override("font_size", 11)
	_caption.add_theme_color_override("font_color", Color(UITheme.IVORY_DIM, 0.6))
	add_child(_caption)
	if def.is_empty():
		_glyph = slot_glyph(slot) if slot != "" else null
		_caption.text = str(Equipment.SLOT_NAMES.get(slot, ""))
		if _glyph == null:
			_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_caption.add_theme_font_size_override("font_size", 13)
		tooltip_text = "%s (empty)" % _caption.text if slot != "" else ""
	else:
		var texture := Equipment.icon(item_id)
		_picture.texture = texture
		if texture == null:  # no picture yet: the item's name on its rarity colour
			_caption.text = str(def.get("name", item_id))
			_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_caption.add_theme_color_override("font_color", _rarity_color)
		tooltip_text = "%s\n%s" % [def.get("name", item_id), "\n".join(Equipment.stat_lines(item_id))]
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func _ready() -> void:
	set_process(false)  # only animates while it is a drop target
	pivot_offset = size / 2.0


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 3.0, TAU)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var radius := minf(12.0, size.x * 0.14)
	var has_item := item_id != ""
	var frame := _rarity_color if has_item else UITheme.GOLD_DARK
	var lit := _hovered or _selected or has_focus()
	# Socket: a dark inset with a soft radial glow in the rarity colour.
	var socket := StyleBoxFlat.new()
	socket.bg_color = Color(0.035, 0.05, 0.1, 0.94)
	socket.set_corner_radius_all(int(radius))
	socket.shadow_color = Color(frame, 0.45 if lit else 0.0)
	socket.shadow_size = 10 if lit else 0
	draw_style_box(socket, rect)
	if has_item:
		var glow_alpha := 0.55 if lit else 0.36
		draw_texture_rect(radial_glow(), rect.grow(-3.0), false, Color(frame, glow_alpha))
	elif _glyph != null:
		var glyph_rect := Rect2(size * 0.18, size * 0.56)
		draw_texture_rect(_glyph, glyph_rect, false, Color(0.75, 0.68, 0.5, 0.32 if not lit else 0.5))
	# Drop feedback while dragging.
	match _drop_state:
		DropState.VALID:
			var a := 0.16 + 0.1 * sin(_pulse)
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(UITheme.GOLD, a)
			fill.set_corner_radius_all(int(radius))
			draw_style_box(fill, rect)
		DropState.TARGET:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(0.45, 1.0, 0.6, 0.28)
			fill.set_corner_radius_all(int(radius))
			draw_style_box(fill, rect)
	# Frame: an outer rarity line and a fine inner gold hairline (bevel).
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.set_corner_radius_all(int(radius))
	var frame_color := frame.lightened(0.25) if lit else frame.darkened(0.1)
	if _drop_state == DropState.VALID or _drop_state == DropState.TARGET:
		frame_color = UITheme.GOLD.lightened(0.3 + 0.15 * sin(_pulse)) if _drop_state == DropState.VALID else Color(0.6, 1.0, 0.7)
	border.border_color = frame_color
	border.set_border_width_all(3 if lit or _drop_state != DropState.NONE else 2)
	draw_style_box(border, rect)
	var hair := StyleBoxFlat.new()
	hair.draw_center = false
	hair.set_corner_radius_all(int(maxf(2.0, radius - 4.0)))
	hair.border_color = Color(UITheme.GOLD, 0.22)
	hair.set_border_width_all(1)
	draw_style_box(hair, rect.grow(-5.0))
	# Rarity gem (uncommon and better) in the top-right corner.
	if has_item and str(Equipment.item(item_id).get("rarity", "common")) != "common":
		var gem := Vector2(size.x - 11.0, 11.0)
		draw_circle(gem, 5.5, Color(0, 0, 0, 0.6))
		draw_circle(gem, 4.0, _rarity_color)
		draw_circle(gem + Vector2(-1.2, -1.2), 1.4, Color(1, 1, 1, 0.75))


func _set_hovered(on: bool) -> void:
	_hovered = on
	_update_lift()
	queue_redraw()


func _update_lift() -> void:
	if _lift != null:
		_lift.kill()
	var target := HOVER_SCALE if (_hovered or _selected) and item_id != "" else 1.0
	if not is_inside_tree():
		scale = Vector2.ONE * target
		return
	_lift = create_tween()
	_lift.tween_property(self, "scale", Vector2.ONE * target, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_selected(selected: bool) -> void:
	_selected = selected
	pivot_offset = size / 2.0
	_update_lift()
	queue_redraw()


func is_selected() -> bool:
	return _selected


## Drag feedback set by the screen: VALID = may be dropped here, TARGET = the pointer is over a
## valid tile, INVALID = cannot take it (dimmed).
func set_drop_state(state: DropState) -> void:
	_drop_state = state
	modulate = Color(1, 1, 1, 0.45) if state == DropState.INVALID else Color.WHITE
	set_process(state == DropState.VALID or state == DropState.TARGET)
	queue_redraw()


func drop_state() -> DropState:
	return _drop_state


# --- Drag and drop ----------------------------------------------------------------------------

func drag_data() -> Dictionary:
	return {"type": DRAG_TYPE, "item_id": item_id, "from": source, "slot": slot, "character_id": character_id}


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id == "" or disabled:
		return null
	var data := drag_data()
	set_drag_preview(_make_preview())
	modulate = Color(1, 1, 1, 0.35)  # the item "leaves" its socket while carried
	drag_started.emit(data)
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok := data is Dictionary and str((data as Dictionary).get("type", "")) == DRAG_TYPE and drop_check.is_valid() and bool(drop_check.call(data))
	if ok and _drop_state == DropState.VALID:
		set_drop_state(DropState.TARGET)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if drop_handler.is_valid():
		drop_handler.call(data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _drop_state == DropState.TARGET:
		set_drop_state(DropState.VALID)
	elif what == NOTIFICATION_DRAG_END:
		if item_id != "" and _drop_state != DropState.INVALID:
			modulate = Color.WHITE


## The carried item: its picture on a glowing socket, slightly tilted and enlarged.
func _make_preview() -> Control:
	var holder := Control.new()
	var tile := ItemTile.create(item_id, slot, custom_minimum_size * 1.1)
	tile.size = custom_minimum_size * 1.1
	tile.position = -tile.size / 2.0
	tile.rotation = deg_to_rad(-6.0)
	tile.pivot_offset = tile.size / 2.0
	tile._hovered = true
	tile.modulate = Color(1.1, 1.1, 1.1, 0.95)
	holder.add_child(tile)
	return holder
