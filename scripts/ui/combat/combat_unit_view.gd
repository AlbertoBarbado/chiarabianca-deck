class_name CombatUnitView
extends Control
## One combatant on the battlefield: pose art (persistent node, swapped by state), an info card
## (name, HP bar, Block, statuses, intent) and target highlighting. Base class of CombatEnemyView and
## CombatCharacterView. Pure presentation: it only shows values handed to it.
##
## States are art poses from CombatPresentation ("idle", "attack", "hit", "block", ...). play_state()
## shows one for a moment, plays the matching body motion and then returns to idle.
##
## Node tree:  self > shadow, art holder (layout box) > feet glow, float (bob / entrance) > pose box > ghosts, art
## Every pose of a unit keeps the idle pose's pixel scale and stands bottom-centred (wide attack
## poses reach out of the slot instead of shrinking and floating).
## The art uses resources/shaders/combat_sprite.gdshader: hit flash, glowing outline (targets, spells,
## blocks), rim light and ambient colour from the battle backdrop, grey when fallen, dissolve on death.
## Motion comes from a data profile (CombatPresentation.motion_profile: stand, caster, beast, heavy,
## hover, slither). Effects quality: full = everything, reduced = poses + body motion, off = no timing.

signal pressed(unit_id: String)
## The pointer entered (true) or left (false) this unit while it is a valid card target.
signal target_hover_changed(unit_id: String, on: bool)
## An attack with weight just landed (heavy creatures): the screen may shake by `strength` pixels.
signal impact(strength: float)

const SPRITE_SHADER := preload("res://resources/shaders/combat_sprite.gdshader")
const OUTLINE_SHADER := preload("res://resources/shaders/combat_outline.gdshader")
const OUTLINE_MARGIN := 10.0                    # screen pixels of room around the sprite for its outline
const DIM_COLOR := Color(0.5, 0.5, 0.56)       # units that cannot be targeted darken (never see-through)
const POSE_SECONDS := 0.5
const INFO_MIN_HEIGHT := 96.0
const HIGHLIGHT_COLOR := Color("ffe9a8")
const BLOCK_COLOR := Color("8fc4ff")
const OUTLINE_TARGET_PX := Vector2(2.0, 4.0)   # pulsing outline width (screen pixels) on a valid target
const OUTLINE_HOVER_PX := 6.0                   # the valid target under the pointer
const TARGET_HOVER_COLOR := Color("ffffff")
const ALLY_TARGET_COLOR := Color("7dffb0")      # allies to heal / give a potion glow green
const TARGET_HOVER_LIFT := 1.06
const RIM_PX := 3.0
const LOW_HEALTH := 0.3                         # below this share of HP the idle breathing quickens
const ENTRANCE_SHIFT := 120.0

var unit_id: String = ""
var _pointer_over := false
## Fixed height of the info card (rows wrap inside it); subclasses set it so layout never depends on text wrapping.
var info_height: float = INFO_MIN_HEIGHT
var is_enemy: bool = false
## Sprite size relative to the other units of its side (bosses and elites are larger).
var size_scale: float = 1.0

var _art: TextureRect
var _art_holder: Control
var _float: Control
var _pose_box: Control
var _glow: TextureRect
var _material: ShaderMaterial
var _outline: TextureRect
var _outline_mat: ShaderMaterial
var _info: PanelContainer
var _shadow: TextureRect
## Share of the sprite height the feet are pushed into the floor (art whose lowest pixels are claws or a tail tip).
var ground_sink: float = 0.0
var _state: String = "idle"
var _state_tween: Tween
var _pose_provider: Callable = Callable()
var _accent: Color = UITheme.SILVER
var _alive: bool = true
var _targetable: bool = false
var _dimmed: bool = false
var _selecting: bool = false  # a card is selected and the player is choosing a target
var _profile: Dictionary = CombatPresentation.DEFAULT_MOTION
var _px_scale: float = 1.0     # texture pixels per screen pixel (shader widths are in texture pixels)
var _health_ratio: float = 1.0
var _idle_tweens: Array[Tween] = []
var _motion: Tween
var _flash_tween: Tween
var _outline_tween: Tween
var _hover_glow: bool = false
var _entered: bool = false
## Status counters floating over the unit: one chip per status with its icon and remaining stacks.
var _status_row: HBoxContainer
var _status_seen: Dictionary = {}   # status id -> stacks at the last update (to animate changes)
var _status_tint: Color = Color.WHITE
var _base_tint: Color = Color.WHITE  # e.g. the elite tint; status tints multiply it
var _status_pulse: Tween

const STATUS_STYLE := {
	"burn": {"icon": "", "sprite": "res://assets/effects/sprites/fire/burn_apply.png", "color": Color("ff8a3c"), "tint": Color(1.12, 0.9, 0.78), "icon_tint": Color.WHITE},
	"poison": {"icon": "", "sprite": "res://assets/effects/sprites/nature/poison_skull.png", "color": Color("8ee05a"), "tint": Color(0.82, 1.08, 0.78), "icon_tint": Color.WHITE},
	"bleed": {"icon": "", "sprite": "res://assets/generated/demo/icon_bleed.png", "fallback": "res://assets/effects/sprites/wind/wind_slash.png", "fallback_tint": Color(1.6, 0.25, 0.3), "color": Color("ff4a5c"), "tint": Color(1.1, 0.86, 0.86), "icon_tint": Color.WHITE},
	"taunt": {"icon": "icons/icon_shield", "color": Color("c9d1dc"), "tint": Color.WHITE},
	"soaked": {"icon": "", "sprite": "res://assets/generated/beach/icon_soaked.png", "fallback": "res://assets/effects/sprites/ice/ice_shards.png", "fallback_tint": Color(0.6, 0.9, 1.5), "color": Color("4fb4ff"), "tint": Color(0.86, 0.96, 1.12), "icon_tint": Color.WHITE},
	"sandblind": {"icon": "", "sprite": "res://assets/generated/beach/icon_sandblind.png", "fallback": "res://assets/effects/sprites/earth/earth_shatter.png", "fallback_tint": Color(1.3, 1.1, 0.7), "color": Color("d9b26a"), "tint": Color(1.06, 1.0, 0.86), "icon_tint": Color.WHITE},
	"quicksand": {"icon": "", "sprite": "res://assets/generated/beach/icon_quicksand.png", "fallback": "res://assets/effects/sprites/earth/earth_spike.png", "fallback_tint": Color(1.2, 1.0, 0.7), "color": Color("b08a50"), "tint": Color(1.0, 0.96, 0.86), "icon_tint": Color.WHITE},
	# Oiled: the body goes dark and glossy (a strong tint), the chip is the black oil drop.
	"oiled": {"icon": "", "sprite": "res://assets/generated/ashveil/icon_oiled.png", "fallback": "res://assets/effects/sprites/nature/poison_skull.png", "fallback_tint": Color(0.3, 0.26, 0.22), "color": Color("e08a3c"), "tint": Color(0.72, 0.66, 0.6), "icon_tint": Color.WHITE},
	"frostbitten": {"icon": "", "sprite": "res://assets/generated/mountain/icon_frostbitten.png", "fallback": "res://assets/effects/sprites/ice/ice_shards.png", "fallback_tint": Color(0.75, 0.95, 1.5), "color": Color("a8d8ff"), "tint": Color(0.88, 0.95, 1.12), "icon_tint": Color.WHITE},
	"chill": {"icon": "", "sprite": "res://assets/generated/frost/icon_chill.png", "fallback": "res://assets/effects/sprites/ice/ice_shards.png", "fallback_tint": Color(0.8, 1.1, 1.4), "color": Color("8fdcff"), "tint": Color(0.84, 0.95, 1.18), "icon_tint": Color.WHITE},
	# Blight: the crowned skull in violet mist; the number is the HP at which the foe perishes.
	"blight": {"icon": "", "sprite": "res://assets/generated/venom/icon_blight.png", "fallback": "res://assets/effects/sprites/nature/poison_skull.png", "fallback_tint": Color(0.75, 0.5, 1.2), "color": Color("b98cff"), "tint": Color(0.96, 0.9, 1.06), "icon_tint": Color.WHITE},
}
const STATUS_CHIP_HEIGHT := 26.0
const POWER_COLOR := Color("c77dff")  # the Power card type colour
const INFO_MAX_WIDTH := 168.0  # life bars stay compact under wide creatures


## pose_provider: Callable(state: String) -> Texture2D (or null for the token fallback).
func setup_unit(p_unit_id: String, p_is_enemy: bool, accent: Color, pose_provider: Callable) -> void:
	unit_id = p_unit_id
	is_enemy = p_is_enemy
	_accent = accent
	_pose_provider = pose_provider
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	mouse_entered.connect(_set_pointer_over.bind(true))
	mouse_exited.connect(_set_pointer_over.bind(false))
	_shadow = TextureRect.new()  # soft elliptical contact shadow centred on the feet (never a flat slab)
	_shadow.texture = _shadow_texture()
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)
	_art_holder = Control.new()
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_holder)
	_glow = TextureRect.new()  # light pool at the feet (spells, entrances)
	_glow.texture = _radial_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = additive
	_glow.modulate = Color(_accent.lightened(0.25), 0.0)
	_art_holder.add_child(_glow)
	_float = Control.new()
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_holder.add_child(_float)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED  # poses are cut-outs: never cropped (box matches the aspect)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SPRITE_SHADER
	_art.material = _material
	_outline = TextureRect.new()  # glowing silhouette behind the sprite (follows its motion as a child)
	_outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_outline.stretch_mode = TextureRect.STRETCH_SCALE
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.show_behind_parent = true
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OUTLINE_SHADER
	_outline.material = _outline_mat
	_art.add_child(_outline)
	for param: String in ["flash_amount", "dissolve"]:  # set explicitly so reads never return null
		_material.set_shader_parameter(param, 0.0)
	_material.set_shader_parameter("saturation", 1.0)
	_outline_mat.set_shader_parameter("outline_width", 0.0)
	_pose_box = Control.new()
	_pose_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float.add_child(_pose_box)
	_pose_box.add_child(_art)
	_status_row = HBoxContainer.new()
	_status_row.name = "StatusRow"
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.add_theme_constant_override("separation", 4)
	_status_row.z_index = 9  # above every sprite, also the front row of a two-row group
	add_child(_status_row)
	_info = PanelContainer.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.8), Color(UITheme.GOLD_DARK, 0.9), 8, 2, 4))
	add_child(_info)
	set_lighting(CombatPresentation.lighting(""))
	set_pose("idle")


## Body motion profile (see CombatPresentation.motion_profile).
func set_motion_profile(profile: Dictionary) -> void:
	_profile = profile
	if is_inside_tree() and (_motion == null or not _motion.is_valid()):
		_start_idle()


func motion_profile_id() -> String:
	return str(_profile.get("id", "stand"))


## Backdrop light: ambient colour and a rim on the edge facing the light ("top", "left", "right",
## or "centre" = toward the middle of the battlefield).
func set_lighting(light: Dictionary) -> void:
	_material.set_shader_parameter("ambient", light.get("ambient", Color.WHITE))
	_material.set_shader_parameter("rim_color", light.get("rim", Color.WHITE))
	_material.set_shader_parameter("rim_amount", float(light.get("rim_amount", 0.0)))
	var direction := Vector2(0.0, -1.0)
	match str(light.get("rim_from", "top")):
		"centre", "center":
			direction = Vector2(0.8 if is_enemy else -0.8, -0.6)
		"left":
			direction = Vector2(-0.8, -0.6)
		"right":
			direction = Vector2(0.8, -0.6)
	_material.set_shader_parameter("rim_direction", direction.normalized())


## Lays the unit out inside `area`: art above, info card below (info keeps its natural height).
func layout_in(area: Rect2) -> void:
	position = area.position
	size = area.size
	var art_height := maxf(40.0, size.y - info_height - (4.0 if info_height > 0.0 else 0.0))
	# The art holder hugs the idle picture and stands on the slot's floor (bottom-centre), so wide
	# animals never float in the middle of a tall slot and badges sit right above the head.
	var aspect := pose_aspect()
	var drawn := Vector2(size.x, size.x / maxf(0.1, aspect))
	if drawn.y > art_height:
		drawn = Vector2(art_height * aspect, art_height)
	_art_holder.position = Vector2((size.x - drawn.x) / 2.0, art_height - drawn.y + drawn.y * ground_sink)
	_art_holder.size = drawn
	var resized_now := _float.size != drawn
	_float.size = drawn
	var idle: Texture2D = _pose_provider.call("idle") if _pose_provider.is_valid() else null
	_px_scale = float(idle.get_height()) / maxf(1.0, drawn.y) if idle != null else 1.0
	_fit_pose()
	_material.set_shader_parameter("rim_width", RIM_PX * _px_scale)
	_glow.size = Vector2(drawn.x * 1.3, maxf(16.0, drawn.y * 0.3))
	_glow.position = Vector2((drawn.x - _glow.size.x) / 2.0, drawn.y - _glow.size.y * 0.6)
	_glow.pivot_offset = _glow.size / 2.0
	_shadow.size = Vector2(drawn.x * 0.92, maxf(12.0, minf(drawn.y * 0.16, drawn.x * 0.22)))
	_shadow.position = Vector2((size.x - _shadow.size.x) / 2.0, art_height - _shadow.size.y * 0.55)
	_shadow.pivot_offset = _shadow.size / 2.0
	if resized_now or _idle_tweens.is_empty():  # refreshes re-run the layout: never restart running motion
		if _motion == null or not _motion.is_valid():
			_art.position = Vector2.ZERO
			_start_idle()
	var info_w := minf(size.x, INFO_MAX_WIDTH)
	_info.position = Vector2((size.x - info_w) / 2.0, art_height + 4.0)
	_info.size = Vector2(info_w, size.y - art_height - 4.0)
	pivot_offset = size / 2.0
	_status_row.size = Vector2(size.x, STATUS_CHIP_HEIGHT)
	_status_row.position = Vector2(0.0, _art_holder.position.y - STATUS_CHIP_HEIGHT - status_row_gap())
	_after_layout()


## Back-row units are drawn behind the front row, but their life bar stays in front of it.
func set_back_row(back: bool) -> void:
	z_index = 0 if back else 1
	if _info != null:
		_info.z_index = 3 if back else 0


## Width / height of the idle pose (wide animals need wider slots than standing humanoids).
func pose_aspect() -> float:
	var texture: Texture2D = _pose_provider.call("idle") if _pose_provider.is_valid() else null
	return float(texture.get_width()) / maxf(1.0, float(texture.get_height())) if texture != null else 0.75


## Space between the top of the sprite and the status chips (enemies keep their intent badge there).
func status_row_gap() -> float:
	return 2.0


## Current HP share: below LOW_HEALTH the unit pants (faster idle).
func set_health(hp: int, max_hp: int) -> void:
	var ratio := float(hp) / maxf(1.0, float(max_hp))
	var was_low := _health_ratio < LOW_HEALTH
	_health_ratio = ratio
	if (ratio < LOW_HEALTH) != was_low and _alive and (_motion == null or not _motion.is_valid()):
		if _state == "idle":
			set_pose("idle")  # switches between the idle and the wounded picture
		_start_idle()


# --- Statuses ------------------------------------------------------------------------------------

## Shows one chip per active status over the unit: icon + remaining stacks (= turns / ticks left).
## Chips pop when a status is new or its count changes; the sprite takes a soft tint while afflicted.
func set_statuses(statuses: Dictionary, block: int = 0, powers: Array[Dictionary] = []) -> void:
	if _status_row == null:
		return
	UIFactory.clear_children(_status_row)
	var tint := Color.WHITE
	var changed: Array[Control] = []
	if block > 0:  # Block first: a silver shield with the amount, like the enemies' block number
		var block_chip := _make_status_chip("block", block, {"icon": "icons/icon_shield", "color": Color("b9d4ff")})
		block_chip.tooltip_text = "Block %d: absorbs damage until the start of your next turn." % block
		_status_row.add_child(block_chip)
		if int(_status_seen.get("block", -1)) != block:
			changed.append(block_chip)
	for status_id: String in statuses:
		var stacks := int(statuses[status_id]["stacks"])
		var style: Dictionary = STATUS_STYLE.get(status_id, {"icon": "", "color": UITheme.SILVER, "tint": Color.WHITE})
		var chip := _make_status_chip(status_id, stacks, style)
		_status_row.add_child(chip)
		if int(_status_seen.get(status_id, -1)) != stacks:
			changed.append(chip)
		tint *= style.get("tint", Color.WHITE)
	# Powers last the whole combat: a violet star chip each, with the number of copies played.
	for power in powers:
		var power_key := "power_" + str(power["id"])
		var power_chip := _make_status_chip(power_key, int(power["count"]), {"icon": "icons/icon_star", "color": POWER_COLOR})
		power_chip.tooltip_text = "Power: %s%s\n%s" % [power["name"], " x%d" % int(power["count"]) if int(power["count"]) > 1 else "", power["description"]]
		_status_row.add_child(power_chip)
		if int(_status_seen.get(power_key, -1)) != int(power["count"]):
			changed.append(power_chip)
	_status_seen.clear()
	for power in powers:
		_status_seen["power_" + str(power["id"])] = int(power["count"])
	if block > 0:
		_status_seen["block"] = block
	for status_id: String in statuses:
		_status_seen[status_id] = int(statuses[status_id]["stacks"])
	_status_row.visible = _alive and (not statuses.is_empty() or block > 0 or not powers.is_empty())
	_apply_status_tint(tint)
	if _effects_level() != "off" and is_inside_tree():
		for chip in changed:
			chip.pivot_offset = Vector2(22, STATUS_CHIP_HEIGHT / 2.0)
			chip.scale = Vector2(1.5, 1.5)
			create_tween().tween_property(chip, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_status_chip(status_id: String, stacks: int, style: Dictionary) -> Control:
	var chip := PanelContainer.new()
	chip.name = "Status_" + status_id
	# PASS (not IGNORE) so hovering the chip shows what the status does (tooltip below); the hover
	# still reaches the unit underneath.
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var color: Color = style.get("color", UITheme.SILVER)
	chip.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.9), color, 12, 2, 3))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	chip.add_child(row)
	var texture := UIAssets.texture(str(style["icon"])) if status_id.begins_with("power_") else CombatUnitView.status_icon(status_id)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		icon.modulate = CombatUnitView.status_icon_tint(status_id)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var count := Label.new()
	count.name = "Count"
	count.text = str(stacks)
	count.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	count.add_theme_color_override("font_color", color.lightened(0.35))
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	count.add_theme_constant_override("outline_size", 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	var status_def := DataRegistry.get_status(status_id)
	if status_def != null:
		chip.tooltip_text = "%s %d\n%s" % [status_def.display_name, stacks, status_def.describe(stacks)]
	return chip


## Icon of a status: its UI icon, its sprite, or (when that file is missing) its fallback sprite.
static func status_icon(status_id: String) -> Texture2D:
	var style: Dictionary = STATUS_STYLE.get(status_id, {})
	if str(style.get("icon", "")) != "":
		return UIAssets.texture(str(style["icon"]))
	for key in ["sprite", "fallback"]:
		var path := str(style.get(key, ""))
		if path != "" and ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


static func status_icon_tint(status_id: String) -> Color:
	var style: Dictionary = STATUS_STYLE.get(status_id, {})
	if str(style.get("sprite", "")) != "" and not ResourceLoader.exists(str(style["sprite"])) and style.has("fallback_tint"):
		return style["fallback_tint"]
	return style.get("icon_tint", Color.WHITE)


## Number shown on the chip of a status (0 when the unit does not have it).
func status_count(status_id: String) -> int:
	var chip := _status_row.get_node_or_null("Status_" + status_id) if _status_row != null else null
	return int((chip.find_child("Count", true, false) as Label).text) if chip != null else 0


func _apply_status_tint(tint: Color) -> void:
	if tint == _status_tint:
		return
	_status_tint = tint
	if _status_pulse != null and _status_pulse.is_valid():
		_status_pulse.kill()
	_art.self_modulate = _base_tint * tint
	if tint != Color.WHITE and _effects_level() == "full" and is_inside_tree():
		# A slow pulse between the normal look and the afflicted tint.
		_status_pulse = create_tween().set_loops()
		_status_pulse.tween_property(_art, "self_modulate", _base_tint * tint, 0.7).set_trans(Tween.TRANS_SINE)
		_status_pulse.tween_property(_art, "self_modulate", _base_tint * tint.lerp(Color.WHITE, 0.6), 0.7).set_trans(Tween.TRANS_SINE)


## Hook for subclasses to place extra nodes (intent badge, detail popup) after a layout.
func _after_layout() -> void:
	_place_detail()


# --- Hover / tap detail panel (enemies and party members) -------------------------------------
## The panel is compact: small lines, a slightly larger name, statuses explained in full.
const DETAIL_FONT := 13
const DETAIL_TITLE_FONT := 16
const DETAIL_WRAP_WIDTH := 250.0
const DETAIL_Z := 40

var _detail: PanelContainer
var _hovered: bool = false
var _pinned: bool = false
var _detail_prefers_left: bool = false


## Creates the (hidden) detail panel and wires hover and tap. Subclasses fill it with
## _begin_detail() + _detail_line() / status rows.
func _init_detail_panel(panel_name: String, prefers_left: bool) -> void:
	_detail_prefers_left = prefers_left
	_detail = PanelContainer.new()
	_detail.name = panel_name
	_detail.visible = false
	_detail.z_index = DETAIL_Z
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_theme_stylebox_override("panel", UITheme.compact_panel_style(0.34, Vector4(20, 14, 20, 14)))
	add_child(_detail)
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	pressed.connect(_on_detail_pressed)


## Clears the panel and returns the column to fill.
func _begin_detail() -> VBoxContainer:
	UIFactory.clear_children(_detail)
	var column := UIFactory.vbox(2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(column)
	return column


func _end_detail() -> void:
	_detail.reset_size()
	_after_layout()


func _detail_line(text: String, color: Color) -> Label:
	var label := UIFactory.label(text, &"DimLabel")
	label.add_theme_font_size_override("font_size", DETAIL_FONT)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _detail_title(text: String, color: Color) -> Label:
	var label := UIFactory.label(text, &"")
	label.add_theme_font_size_override("font_size", DETAIL_TITLE_FONT)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Beside the sprite; flips to the other side when it would leave the screen.
func _place_detail() -> void:
	if _detail == null:
		return
	var art_height := maxf(40.0, size.y - info_height - (4.0 if info_height > 0.0 else 0.0))
	var right_x := size.x + 6.0
	var left_x := -_detail.size.x - 6.0
	_detail.position = Vector2(left_x if _detail_prefers_left else right_x, maxf(0.0, art_height * 0.25))
	var screen_width := get_viewport_rect().size.x
	var rect := _detail.get_global_rect()
	if rect.end.x > screen_width - 4.0:
		_detail.position.x = left_x
	elif rect.position.x < 4.0:
		_detail.position.x = right_x


func _set_hover(value: bool) -> void:
	_hovered = value
	if not value:
		_pinned = false  # leaving the unit (or tapping elsewhere on touch) closes a pinned panel too
	set_process(_hovered or _pinned)
	set_hover_glow(value and _alive)
	_refresh_detail_visibility()


## A tap / click shows or hides the details unless a card is waiting for a target.
func _on_detail_pressed(_id: String) -> void:
	if _selecting:
		_pinned = false
	else:
		_pinned = not _pinned
	set_process(_hovered or _pinned)
	_refresh_detail_visibility()


## Safety net while the panel is open: "mouse_exited" can be missed when the pointer crosses the
## status chips or the views are re-laid out, which left the panel stuck on screen.
func _process(_delta: float) -> void:
	if _detail == null or not (_hovered or _pinned):
		set_process(false)
		return
	if not get_global_rect().has_point(get_global_mouse_position()) and not _touch_pinned():
		_set_hover(false)


## On touch screens a tap pins the panel until the next tap elsewhere (no pointer hover exists).
func _touch_pinned() -> bool:
	return _pinned and DisplayServer.is_touchscreen_available() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _refresh_detail_visibility() -> void:
	if _detail == null:
		return
	_detail.visible = (_hovered or _pinned) and _detail_allowed() and not _selecting
	if _detail.visible:
		_after_layout()


## Enemies hide their panel once defeated; party members keep it (a fallen ally can be revived).
func _detail_allowed() -> bool:
	return _alive


func is_detail_visible() -> bool:
	return _detail != null and _detail.visible


## Rectangle (global) of the pose art: where hits, projectiles and numbers should point.
func get_art_rect() -> Rect2:
	return Rect2(_art_holder.global_position, _art_holder.size) if _art_holder != null else Rect2()


## Hides the info card (the combat screen shows this unit's vitals in its top bar instead).
func hide_info() -> void:
	info_height = 0.0
	_info.visible = false


func get_info_height() -> float:
	return info_height


func current_state() -> String:
	return _state


func is_targetable() -> bool:
	return _targetable


func set_pose(state: String) -> void:
	_state = state
	_show_picture(state)


## Shows the picture of a state without changing the logical state (the wind-up of an attack).
func _show_picture(state: String) -> void:
	if state == "idle" and _alive and _health_ratio < LOW_HEALTH and _has_distinct_pose("hurt"):
		state = "hurt"  # badly wounded units idle in their stagger pose
	var texture: Texture2D = _pose_provider.call(state) if _pose_provider.is_valid() else null
	_art.texture = texture
	if texture == null:
		_art.texture = _token_texture()
	_fit_pose()


## Sizes the pose box for the current picture at the idle pose's pixel scale, feet on the floor.
func _fit_pose() -> void:
	if _pose_box == null or _float.size.y <= 0.0:
		return
	var box := _float.size
	var texture := _art.texture
	var idle: Texture2D = _pose_provider.call("idle") if _pose_provider.is_valid() else null
	if texture != null and idle != null and texture != idle:
		box = Vector2(texture.get_width(), texture.get_height()) / _px_scale
		var cap := _float.size.y * 1.15 / maxf(1.0, box.y)  # a taller pose (rearing up) is capped a little
		if cap < 1.0:
			box *= cap
	_pose_box.size = box
	_pose_box.position = Vector2((_float.size.x - box.x) / 2.0, _float.size.y - box.y)
	_art.size = box
	_art.pivot_offset = Vector2(box.x / 2.0, box.y)  # squash, stretch and lean from the feet
	_outline.texture = _art.texture
	_outline.position = -Vector2(OUTLINE_MARGIN, OUTLINE_MARGIN)
	_outline.size = box + Vector2(OUTLINE_MARGIN, OUTLINE_MARGIN) * 2.0
	_outline_mat.set_shader_parameter("margin_uv", Vector2(OUTLINE_MARGIN, OUTLINE_MARGIN) / _outline.size)


## True when the presentation data has its own picture for `state` (missing states fall back to idle).
func _has_distinct_pose(state: String) -> bool:
	if not _pose_provider.is_valid():
		return false
	var texture: Texture2D = _pose_provider.call(state)
	return texture != null and texture != _pose_provider.call("idle")


func _effects_level() -> String:
	return str(SettingsStore.load_values().get("effects_quality", "full"))


# --- Idle -----------------------------------------------------------------------------------------

func _stop_idle() -> void:
	for tween in _idle_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_idle_tweens.clear()
	_art.scale = Vector2.ONE
	_art.rotation = 0.0
	_float.position.y = 0.0
	_shadow.scale = Vector2.ONE


## Idle life (full quality only), from the motion profile: breathing stretch from the feet, a hover
## bob with the shadow shrinking under it, a slow rock. Out of phase per unit; quicker when hurt.
func _start_idle() -> void:
	_stop_idle()
	if _effects_level() != "full" or not is_inside_tree() or not _alive:
		return
	var jitter := float(absi(unit_id.hash()) % 100) / 100.0
	var period := (float(_profile.get("period", 2.8)) + jitter * 0.6) * (0.6 if _health_ratio < LOW_HEALTH else 1.0)
	var breath: Array = _profile.get("breath", [0.012, 0.022])
	var breathe := create_tween().set_loops()
	breathe.tween_property(_art, "scale", Vector2(1.0 + float(breath[0]), 1.0 + float(breath[1])), period / 2.0).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(_art, "scale", Vector2.ONE, period / 2.0).set_trans(Tween.TRANS_SINE)
	_idle_tweens.append(breathe)
	var bob := float(_profile.get("bob", 0.0))
	if bob > 0.0:
		var hover := create_tween().set_loops()
		hover.tween_property(_float, "position:y", -bob, period * 0.5).set_trans(Tween.TRANS_SINE)
		hover.parallel().tween_property(_shadow, "scale", Vector2(0.8, 0.8), period * 0.5).set_trans(Tween.TRANS_SINE)
		hover.tween_property(_float, "position:y", 0.0, period * 0.5).set_trans(Tween.TRANS_SINE)
		hover.parallel().tween_property(_shadow, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE)
		_idle_tweens.append(hover)
	var sway := float(_profile.get("sway", 0.0))
	if sway > 0.0:
		var rock := create_tween().set_loops()
		rock.tween_property(_art, "rotation", sway, period * 0.75).set_trans(Tween.TRANS_SINE)
		rock.tween_property(_art, "rotation", -sway, period * 1.5).set_trans(Tween.TRANS_SINE)
		rock.tween_property(_art, "rotation", 0.0, period * 0.75).set_trans(Tween.TRANS_SINE)
		_idle_tweens.append(rock)


## Units step in from their side when the battle starts (full quality only).
func play_entrance(delay: float) -> void:
	if _entered or _effects_level() != "full" or not is_inside_tree():
		_entered = true
		return
	_entered = true
	var from := -ENTRANCE_SHIFT if is_enemy else ENTRANCE_SHIFT
	_float.position.x = from
	_float.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(_float, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(_float, "position:x", 0.0, 0.42).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _pulse_glow(0.55, 0.45))


# --- Actions ---------------------------------------------------------------------------------------

## Body motion that goes with a pose (attack: wind-up, lunge with afterimages, impact, recover; hit:
## white flash, knockback lean and shake; block: brace with a blue shield outline; cast: rise with a
## glow at the feet). Visual only; skipped when effects are off.
func _play_motion(state: String) -> void:
	if _effects_level() == "off" or not is_inside_tree() or _art == null:
		return
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_stop_idle()
	_art.position = Vector2.ZERO
	var toward := 1.0 if is_enemy else -1.0  # enemies face right, the party faces left
	var squash := float(_profile.get("squash", 0.07))
	_motion = create_tween()
	match state:
		"attack", "swing":
			var reach := size.x * float(_profile.get("lunge", 0.24))
			var windup := float(_profile.get("windup", 0.14))
			var strike := float(_profile.get("strike", 0.1))
			var arc := float(_profile.get("arc", 0.0))
			var strike_pose := _state
			if _has_distinct_pose("prep") and _pose_provider.call("prep") != _pose_provider.call(strike_pose):
				_show_picture("prep")  # wind-up picture first, the strike picture swaps in at the lunge
				_motion.tween_callback(_show_picture.bind(strike_pose)).set_delay(windup)
			_motion.parallel().tween_property(_art, "position:x", -toward * reach * 0.22, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2(1.0 + squash * 0.6, 1.0 - squash), windup).set_trans(Tween.TRANS_SINE)
			_motion.tween_callback(_spawn_afterimages.bind(int(_profile.get("afterimages", 2)), strike))
			_motion.tween_property(_art, "position:x", toward * reach, strike).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2(1.0 + squash, 1.0 - squash * 0.5), strike)
			if arc != 0.0:
				_motion.parallel().tween_property(_art, "position:y", -arc, strike * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				_motion.parallel().tween_property(_art, "position:y", 0.0, strike * 0.5).set_delay(strike * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_motion.tween_callback(_on_strike_landed)
			_motion.tween_property(_art, "scale", Vector2(1.0 - squash * 0.4, 1.0 + squash * 0.3), 0.06)
			_motion.tween_interval(0.05)
			_motion.tween_property(_art, "position:x", 0.0, float(_profile.get("recover", 0.28))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2.ONE, float(_profile.get("recover", 0.28))).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"hit":
			var knock := size.x * float(_profile.get("knockback", 0.12))
			_flash(Color.WHITE, 0.55, 0.22)
			_motion.tween_interval(0.04)  # hit-stop: the blow lands before the body reacts
			_motion.tween_property(_art, "position:x", -toward * knock, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2(1.0 - squash * 0.8, 1.0 + squash * 0.4), 0.07)
			_motion.parallel().tween_property(_art, "rotation", -toward * 0.07, 0.07)
			for i in 3:
				var amount := (5.0 - i * 1.6)
				_motion.tween_property(_art, "position:x", -toward * knock + amount, 0.04)
				_motion.tween_property(_art, "position:x", -toward * knock - amount, 0.04)
			_motion.tween_property(_art, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
		"block", "guard":
			_flash(BLOCK_COLOR, 0.45, 0.35)
			_outline_flash(BLOCK_COLOR, 5.0, 0.45)
			_motion.tween_property(_art, "position:x", -toward * size.x * 0.06, 0.07)
			_motion.parallel().tween_property(_art, "scale", Vector2(1.0 + squash * 0.5, 1.0 - squash * 0.5), 0.07)
			_motion.tween_interval(0.08)
			_motion.tween_property(_art, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
			_motion.parallel().tween_property(_art, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"cast", "charge":
			_pulse_glow(0.9, 0.55)
			_outline_flash(_accent.lightened(0.35), 4.0, 0.5)
			_flash(_accent.lightened(0.5), 0.3, 0.4)
			_motion.tween_property(_art, "position:y", -12.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2(1.0 - squash * 0.3, 1.0 + squash * 0.5), 0.16)
			_motion.tween_property(_art, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_motion.parallel().tween_property(_art, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_:
			_motion.kill()
			_start_idle()
			return
	_motion.tween_callback(_start_idle)


func _on_strike_landed() -> void:
	var strength := float(_profile.get("impact", 0.0))
	if strength > 0.0:
		impact.emit(strength)


## Fading copies of the current pose along the lunge (full quality only).
func _spawn_afterimages(count: int, over: float) -> void:
	if count <= 0 or _effects_level() != "full" or not is_inside_tree():
		return
	var spawner := create_tween()
	for i in count:
		spawner.tween_interval(over / float(count))
		spawner.tween_callback(_spawn_ghost)


func _spawn_ghost() -> void:
	if _art.texture == null:
		return
	var ghost := TextureRect.new()
	ghost.texture = _art.texture
	ghost.expand_mode = _art.expand_mode
	ghost.stretch_mode = _art.stretch_mode
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = _art.size
	ghost.pivot_offset = _art.pivot_offset
	ghost.position = _art.position
	ghost.scale = _art.scale
	ghost.rotation = _art.rotation
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = additive
	ghost.modulate = Color(_accent.lightened(0.2), 0.42)
	_pose_box.add_child(ghost)
	_pose_box.move_child(ghost, _art.get_index())  # behind the sprite
	var fade := ghost.create_tween()
	fade.tween_property(ghost, "modulate:a", 0.0, 0.24)
	fade.tween_callback(ghost.queue_free)


func _flash(color: Color, amount: float, seconds: float) -> void:
	if not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_material.set_shader_parameter("flash_color", color)
	_material.set_shader_parameter("flash_amount", amount)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "shader_parameter/flash_amount", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Brief glowing silhouette (block shield, spell charge); targeting keeps its own steady pulse.
func _outline_flash(color: Color, width_px: float, seconds: float) -> void:
	if _effects_level() != "full" or _targetable or not is_inside_tree():
		return
	if _outline_tween != null and _outline_tween.is_valid():
		_outline_tween.kill()
	_outline_mat.set_shader_parameter("outline_color", color)
	_outline_mat.set_shader_parameter("outline_width", width_px * _px_scale)
	_outline_tween = create_tween()
	_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_width", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_outline_tween.tween_callback(_refresh_outline)


func _pulse_glow(alpha: float, seconds: float) -> void:
	if _effects_level() != "full" or not is_inside_tree():
		return
	_glow.modulate = Color(_accent.lightened(0.25), alpha)
	_glow.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(_glow, "scale", Vector2(1.15, 1.15), seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_glow, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Shows a pose for `seconds` with its body motion, then returns to idle (or stays down when fallen).
func play_state(state: String, seconds: float = POSE_SECONDS) -> void:
	if not _alive and state != "down":
		return
	set_pose(state)
	_play_motion(state)
	if _state_tween != null and _state_tween.is_valid():
		_state_tween.kill()
	if _effects_level() == "off" or not is_inside_tree():
		return
	_state_tween = create_tween()
	_state_tween.tween_interval(seconds)
	_state_tween.tween_callback(func() -> void: set_pose("idle" if _alive else "down"))


func set_alive(alive: bool) -> void:
	if alive == _alive:
		return
	_alive = alive
	set_pose("idle" if alive else "down")
	if not alive and is_enemy:
		_vanish()
		return
	# A fallen party member turns grey and sinks a little; a revived one comes back to colour.
	_stop_idle()
	_material.set_shader_parameter("saturation", 1.0 if alive else 0.15)
	_art_holder.modulate = Color.WHITE if alive else Color(0.7, 0.7, 0.76)
	_float.position.y = 0.0 if alive else 6.0
	if alive:
		_start_idle()


## A defeated enemy burns away (dissolve with an ember edge) after a white hit moment, then its
## sprite, life bar and counters are hidden. Purely visual; the combat already resolved.
func _vanish() -> void:
	_stop_idle()
	_refresh_outline()
	var hide_all := func() -> void:
		_art_holder.visible = false
		_shadow.visible = false
		_status_row.visible = false
		_info.visible = false
		on_vanished()
	if _effects_level() == "off" or not is_inside_tree():
		hide_all.call()
		return
	_material.set_shader_parameter("dissolve_edge", _accent.lerp(Color("ffb050"), 0.6))
	_flash(Color.WHITE, 0.9, 0.3)
	var tween := create_tween()
	tween.tween_interval(0.2)
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_float, "position:y", -10.0, 0.75).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_info, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(_shadow, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(_status_row, "modulate:a", 0.0, 0.3)
	tween.tween_callback(hide_all)


## Hook: subclasses clear their extra nodes (intent badge, popup) when the unit has vanished.
func on_vanished() -> void:
	pass


func is_vanished() -> bool:
	return not _alive and is_enemy and _art_holder != null and not _art_holder.visible


## Highlights this unit as a valid target (a pulsing gold outline around the sprite) or dims it when
## a card is selected and it cannot be chosen.
func set_targeting(selecting: bool, valid: bool) -> void:
	var was_target := _targetable
	_selecting = selecting
	_targetable = selecting and valid
	_dimmed = selecting and not valid
	modulate = DIM_COLOR if _dimmed and _alive else Color.WHITE
	if was_target != _targetable:
		_set_pointer_over(_pointer_over)


## Soft white outline while the pointer is over the unit (enemies when no card is selected).
## The pointer is over this unit: a valid target under it gets the strong highlight and a lift.
func _set_pointer_over(on: bool) -> void:
	var was_hovered := is_target_hovered()
	_pointer_over = on
	if is_target_hovered() != was_hovered:
		target_hover_changed.emit(unit_id, is_target_hovered())
	if _art_holder != null:
		var lifted := on and _targetable and _alive
		_art_holder.pivot_offset = Vector2(_art_holder.size.x / 2.0, _art_holder.size.y)
		_art_holder.scale = Vector2.ONE * (TARGET_HOVER_LIFT if lifted else 1.0)
	_refresh_outline()


func is_target_hovered() -> bool:
	return _pointer_over and _targetable and _alive


func set_hover_glow(on: bool) -> void:
	if on == _hover_glow:
		return
	_hover_glow = on
	_refresh_outline()


func has_target_outline() -> bool:
	return _targetable and float(_outline_mat.get_shader_parameter("outline_width")) > 0.0


func _refresh_outline() -> void:
	if _outline_tween != null and _outline_tween.is_valid():
		_outline_tween.kill()
	if _targetable and _alive and _pointer_over:
		# The candidate under the pointer: thick, steady, bright, so the choice is unmistakable.
		_outline_mat.set_shader_parameter("outline_color", TARGET_HOVER_COLOR)
		_outline_mat.set_shader_parameter("outline_width", OUTLINE_HOVER_PX * _px_scale)
	elif _targetable and _alive:
		_outline_mat.set_shader_parameter("outline_color", HIGHLIGHT_COLOR if is_enemy else ALLY_TARGET_COLOR)
		_outline_mat.set_shader_parameter("outline_width", OUTLINE_TARGET_PX.y * _px_scale)
		if _effects_level() == "full" and is_inside_tree():
			_outline_tween = create_tween().set_loops()
			_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_width", OUTLINE_TARGET_PX.x * _px_scale, 0.45).set_trans(Tween.TRANS_SINE)
			_outline_tween.tween_property(_outline_mat, "shader_parameter/outline_width", OUTLINE_TARGET_PX.y * _px_scale, 0.45).set_trans(Tween.TRANS_SINE)
	elif _hover_glow and _alive:
		_outline_mat.set_shader_parameter("outline_color", Color(1, 1, 1, 0.7))
		_outline_mat.set_shader_parameter("outline_width", 2.0 * _px_scale)
	else:
		_outline_mat.set_shader_parameter("outline_width", 0.0)


## Damage / heal feedback from the combat screen: a white pop, then the colour, then back to normal.
func flash(color: Color) -> void:
	if _art == null or not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_material.set_shader_parameter("flash_color", Color.WHITE)
	_material.set_shader_parameter("flash_amount", 0.75)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.05)
	_flash_tween.tween_callback(func() -> void:
		_material.set_shader_parameter("flash_color", color)
		_material.set_shader_parameter("flash_amount", 0.45))
	_flash_tween.tween_property(_material, "shader_parameter/flash_amount", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Current flash strength of the sprite (0 = none); used by tests.
func flash_amount() -> float:
	return float(_material.get_shader_parameter("flash_amount"))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(unit_id)
		accept_event()


## Replaces the info card content with `rows` (Controls built by the subclass).
func set_info_rows(rows: Array[Control]) -> void:
	UIFactory.clear_children(_info)
	var column := UIFactory.vbox(2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(column)
	for row in rows:
		column.add_child(row)


static func _shadow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.62))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	gradient.add_point(0.55, Color(0, 0, 0, 0.36))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 32
	return texture


static func _radial_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 64
	return texture


## Coloured disc with the unit's initial, used when a pose texture is missing.
func _token_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, _accent.lightened(0.2))
	gradient.set_color(1, _accent.darkened(0.7))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.4)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 96
	texture.height = 96
	return texture


## HP bar + heart + "HP x / y" and optional Block (icon + number), as used by both unit kinds.
static func vitals_rows(hp: int, max_hp: int, block: int, fallen_text: String = "") -> Array[Control]:
	var rows: Array[Control] = []
	var bar := UIFactory.hp_bar(hp, max_hp)
	bar.custom_minimum_size = Vector2(0, 9)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.append(bar)
	var line := UIFactory.hbox(6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(UIFactory.icon("health", 18))
	var hp_label := UIFactory.label("HP %d / %d%s" % [hp, max_hp, fallen_text], &"DimLabel")
	hp_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	line.add_child(hp_label)
	if block > 0:
		line.add_child(UIFactory.icon("block", 18))
		var block_label := UIFactory.label("Block %d" % block, &"DimLabel")
		block_label.add_theme_color_override("font_color", UITheme.SILVER)
		line.add_child(block_label)
	rows.append(line)
	return rows


## Status rows with icon, "Burn 3 (2 dmg/turn)" text and a tooltip, from a Combatant.statuses dictionary.
## explain: also add the full rule text under each status (the enemy detail panel, so touch screens
## without hover tooltips can still read what a status does). font_size: label size.
static func status_rows(statuses: Dictionary, font_size: int = UITheme.FONT_SIZE_SMALL, explain: bool = false, wrap_width: float = 0.0) -> Array[Control]:
	var rows: Array[Control] = []
	for status_id: String in statuses:
		var stacks: int = statuses[status_id]["stacks"]
		var status_def := DataRegistry.get_status(status_id)
		var row := UIFactory.hbox(4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if AssetCatalog.icon(status_id) != null:
			row.add_child(UIFactory.icon(status_id, font_size + 2))
		elif CombatUnitView.status_icon(status_id) != null:
			var icon := TextureRect.new()
			icon.texture = CombatUnitView.status_icon(status_id)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(font_size + 2, font_size + 2)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
		var label := UIFactory.label(status_def.short_text(stacks) if status_def != null else "%s %d" % [status_id.capitalize(), stacks], &"DimLabel")
		label.add_theme_color_override("font_color", UITheme.GOLD.lerp(Color("e0663a"), 0.6) if status_id == "burn" else UITheme.SILVER)
		label.add_theme_font_size_override("font_size", font_size)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		if status_def != null:
			label.tooltip_text = status_def.describe(stacks)
		row.add_child(label)
		rows.append(row)
		if explain and status_def != null:
			var rule := UIFactory.label(status_def.describe(stacks), &"DimLabel", true)
			rule.name = "StatusRule_" + status_id
			rule.add_theme_font_size_override("font_size", maxi(10, font_size - 2))
			rule.add_theme_color_override("font_color", Color(UITheme.SILVER, 0.82))
			rule.custom_minimum_size.x = wrap_width
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.append(rule)
	return rows
