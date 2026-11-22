class_name MapNodeButton
extends Button
## Visual for one map node, drawn as an ornate location medallion (board-game map sticker): the
## gold ring frame of the UI art, an emblem for the room type, a thin ring in the type colour and
## state overlays:
##   current   - ivory pulse, selectable look
##   available - warm gold glow that breathes, selectable
##   visited   - subdued with a gold check seal
##   locked    - desaturated and darker (tapping it only shows why it cannot be entered)
## Elite and boss nodes are larger (see `size_factor`). The start node shows both princesses.
## Everything is drawn by this control; nothing is baked into the map picture.

const NODE_SIZE := Vector2(96, 96)
const PULSE_TIME := 1.4
const BADGE_COLOR := Color("4f9d6a")
const HOVER_SCALE := 1.1
## Both start-node faces share this size so neither princess looks larger.
const FACE_SIZE := 34
const PRESSED_SCALE := 0.93
const SCALE_TIME := 0.1
const FRAME_ID := "panels/frame_circle"
const CHECK_ID := "icons/icon_check"

## color: type ring and legend colour; label: legend text; emblem: UI icon inside the medallion;
## tint: emblem modulate; factor: size relative to the layout's node size.
const TYPE_STYLE := {
	MapNodeData.TYPE_START: {"color": Color("3a6fd8"), "label": "Start", "emblem": ""},
	MapNodeData.TYPE_COMBAT: {"color": Color("b23a48"), "label": "Fight", "emblem": "icons/icon_combat"},
	MapNodeData.TYPE_REST: {"color": Color("4f9d6a"), "label": "Rest", "emblem": "icons/icon_flame"},
	MapNodeData.TYPE_MERCHANT: {"color": Color("d4a64a"), "label": "Shop", "emblem": "icons/icon_gold"},
	MapNodeData.TYPE_EVENT: {"color": Color("8a5fc8"), "label": "Event", "emblem": "icons/icon_rune"},
	MapNodeData.TYPE_EXIT: {"color": Color("e8e2cf"), "label": "Exit", "emblem": "icons/icon_star"},
	MapNodeData.TYPE_ELITE: {"color": Color("e0531f"), "label": "Elite", "emblem": "icons/icon_combat", "tint": Color(1.35, 0.62, 0.5), "factor": 1.14},
	MapNodeData.TYPE_TREASURE: {"color": Color("c9a227"), "label": "Chest", "emblem": "icons/icon_chest"},
	MapNodeData.TYPE_TOWN: {"color": Color("5fb0c8"), "label": "Town", "emblem": "icons/icon_shield"},
	MapNodeData.TYPE_BOSS: {"color": Color("d81f3a"), "label": "Boss", "emblem": "icons/icon_silhouette", "tint": Color(1.3, 0.55, 0.5), "factor": 1.5},
}

var node_data: MapNodeData
var state: MapProgress.NodeState = MapProgress.NodeState.UNAVAILABLE
## Legend text of the node type ("Fight", "Rest", ...).
var type_label: String = ""
## Emblem drawn inside the medallion (null for the start node, which shows the party).
var emblem: Texture2D = null
var size_factor: float = 1.0

var _type_color: Color = UITheme.SILVER
var _emblem_tint: Color = Color.WHITE
var _frame: Texture2D = null
var _pulse: float = 0.0
var _tween: Tween
var _time: float = 0.0


## terrain_hint: extra tooltip line for the room's terrain (MapGraph.terrain_hint), "" for none.
func setup(data: MapNodeData, p_state: MapProgress.NodeState, terrain_hint: String = "") -> void:
	node_data = data
	state = p_state
	var style: Dictionary = TYPE_STYLE.get(data.type, {"color": UITheme.SILVER, "label": "?", "emblem": ""})
	_type_color = style["color"]
	type_label = str(style["label"])
	size_factor = float(style.get("factor", 1.0))
	_emblem_tint = style.get("tint", Color.WHITE)
	emblem = UIAssets.texture(str(style.get("emblem", ""))) if str(style.get("emblem", "")) != "" else null
	_frame = UIAssets.texture(FRAME_ID)
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	size = NODE_SIZE  # no custom minimum: a cached minimum would block shrinking to the layout size
	tooltip_text = "%s (%s)" % [data.display_name, type_label]
	if terrain_hint != "":
		tooltip_text += "\n" + terrain_hint
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	if data.type == MapNodeData.TYPE_START:
		_add_start_faces()
	if p_state == MapProgress.NodeState.CURRENT:
		_start_pulse()
	if p_state == MapProgress.NodeState.AVAILABLE or p_state == MapProgress.NodeState.CURRENT:
		# Hover (desktop) and pressed (touch) feedback; locked and completed nodes stay still.
		mouse_entered.connect(_animate_scale.bind(HOVER_SCALE))
		mouse_exited.connect(_animate_scale.bind(1.0))
		button_down.connect(_animate_scale.bind(PRESSED_SCALE))
		button_up.connect(_animate_scale.bind(HOVER_SCALE if is_hovered() else 1.0))
	if p_state == MapProgress.NodeState.UNAVAILABLE:
		modulate = Color(1, 1, 1, 0.9)
	pivot_offset = size / 2.0
	set_process(p_state == MapProgress.NodeState.AVAILABLE or p_state == MapProgress.NodeState.CURRENT)


## Resizes the node (art maps use a larger touch target); elite and boss nodes scale up from it.
func set_node_size(value: Vector2) -> void:
	var scaled := value * size_factor
	size = scaled
	pivot_offset = scaled / 2.0
	_relayout_faces()
	queue_redraw()


## Small emblem control for legends, matching the medallion on the map.
static func legend_icon(type: String, pixels: int) -> Control:
	var style: Dictionary = TYPE_STYLE.get(type, {})
	var texture := UIAssets.texture(str(style.get("emblem", ""))) if str(style.get("emblem", "")) != "" else null
	if texture == null:
		return UIFactory.icon(type, pixels, "●")
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(pixels, pixels)
	rect.modulate = style.get("tint", Color.WHITE)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _add_start_faces() -> void:
	var row := HBoxContainer.new()
	row.name = "StartFaces"
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for character_id in GameConfig.INITIAL_PARTY_IDS:
		var face := PortraitView.new()
		face.setup(DataRegistry.get_character(character_id), null, Vector2(FACE_SIZE, FACE_SIZE), false, false)
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(face)
	add_child(row)
	_relayout_faces()


func _relayout_faces() -> void:
	var row := get_node_or_null("StartFaces") as Control
	if row != null:
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _start_pulse() -> void:
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "_pulse", 1.0, PULSE_TIME)
	_tween.tween_property(self, "_pulse", 0.0, 0.0)
	_tween.tween_callback(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0
	var locked := state == MapProgress.NodeState.UNAVAILABLE
	var visited := state == MapProgress.NodeState.VISITED
	var shade := Color(0.5, 0.47, 0.44, 0.92) if locked else (Color(0.72, 0.72, 0.78) if visited else Color.WHITE)
	# Soft contact shadow so the medallion sits on the map instead of floating above it.
	draw_circle(center + Vector2(0, radius * 0.1), radius * 0.96, Color(0, 0, 0, 0.32))
	if state == MapProgress.NodeState.AVAILABLE:
		var breath := 0.5 + 0.5 * sin(_time * 3.0)
		draw_circle(center, radius * (1.06 + 0.05 * breath), Color(1.0, 0.82, 0.3, 0.2 + 0.18 * breath))
		draw_arc(center, radius * 1.03, 0.0, TAU, 56, Color(1.0, 0.86, 0.4, 0.95), 3.0, true)
	elif state == MapProgress.NodeState.CURRENT:
		draw_arc(center, radius + 4.0 + _pulse * 12.0, 0.0, TAU, 48, Color(UITheme.IVORY, 0.9 * (1.0 - _pulse)), 4.0, true)
		draw_arc(center, radius * 1.03, 0.0, TAU, 56, Color(UITheme.IVORY, 0.95), 3.0, true)
	if _frame != null:
		draw_texture_rect(_frame, Rect2(Vector2.ZERO, size), false, shade)
	else:
		draw_circle(center, radius * 0.94, UITheme.NAVY_DEEP)
		draw_arc(center, radius * 0.94, 0.0, TAU, 48, UITheme.GOLD_DARK, 4.0, true)
	# Thin ring in the room-type colour, just inside the gold frame.
	var ring := Color(_type_color.r, _type_color.g, _type_color.b, 0.55 if locked else 0.95)
	draw_arc(center, radius * 0.7, 0.0, TAU, 48, ring, maxf(2.0, radius * 0.07), true)
	if emblem != null:
		var extent := size * 0.56
		var tint := Color(_emblem_tint.r * shade.r, _emblem_tint.g * shade.g, _emblem_tint.b * shade.b, shade.a)
		draw_texture_rect(emblem, Rect2(center - extent / 2.0, extent), false, tint)
	if visited:
		_draw_seal(center, radius)


## Completion seal on a visited node: a small dark disc with the gold check mark.
func _draw_seal(center: Vector2, radius: float) -> void:
	var spot := center + Vector2(radius * 0.62, -radius * 0.62)
	var r := radius * 0.34
	draw_circle(spot, r, Color(UITheme.NAVY_DEEP, 0.95))
	draw_arc(spot, r, 0.0, TAU, 24, BADGE_COLOR, 2.5, true)
	var check := UIAssets.texture(CHECK_ID)
	if check != null:
		draw_texture_rect(check, Rect2(spot - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), false)
	else:
		draw_polyline(PackedVector2Array([spot + Vector2(-r * 0.45, 0.0), spot + Vector2(-r * 0.1, r * 0.4), spot + Vector2(r * 0.5, -r * 0.35)]), Color.WHITE, 3.0, true)


func _animate_scale(target: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(target, target), SCALE_TIME)
