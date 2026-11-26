class_name CastleUI
extends RefCounted
## Shared building blocks of the castle screens (hub, world map, preparation, results and the
## service panels): the resource header, confirmation dialogs, toasts, filter chips, tiles and
## scrolling card grids. Everything is built from containers (no fixed pixel positions), with
## touch-sized controls, so the screens work on PC and phones.

const TILE_MIN := Vector2(220, 132)
const CHIP_HEIGHT := 44.0
const TOAST_TIME := 2.4
const ESSENCE_COLOR := Color("9fc8ff")


## "Treasury 120  ✦ Essence 2  ♥ Bond 2" for the current campaign.
static func resources(campaign: CampaignState) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Resources"
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := UIKit.style("panel_navy_small")
	panel.add_theme_stylebox_override("panel", style if style != null else UITheme.box(Color(UITheme.NAVY_DEEP, 0.85), UITheme.GOLD_DARK, 12, 2, 10))
	var row := UIFactory.hbox(16)
	panel.add_child(row)
	for entry in [["icon_res_gold", "Treasury", str(campaign.vault.gold), "Castle treasury: spent on upgrades, potions, training and fusion.", Color("f3d68a")],
			["icon_res_essence", "Essence", str(campaign.essence), "Starlight Essence: a rare material from completed missions, used for fusion and rare brews.", Color("bcd6ff")],
			["icon_res_bond", "BondLevel", "Bond %d" % campaign.bond_level(), "Sister Bond level.", UITheme.BOND_PINK],
			["", "PartyLevel", "Lv %d" % Levels.party_level(campaign), "Party level (the sisters' average level): missions and contracts open with it.", Color("f6e7c1")]]:
		var item := UIFactory.hbox(6)
		item.name = str(entry[1])
		item.tooltip_text = str(entry[3])
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		if str(entry[0]) != "":
			item.add_child(picture(str(entry[0]), 30.0, "◆"))
		var label := UIFactory.label(str(entry[2]), &"", false)
		label.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
		label.add_theme_color_override("font_color", entry[4])
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_child(label)
		row.add_child(item)
	return panel


## A painted UI picture by catalog id at a square size, or a glyph label when the art is missing.
static func picture(asset_id: String, side: float, fallback: String = "") -> Control:
	var texture := UIKit.picture(asset_id) if asset_id != "" else null
	if texture == null:
		var glyph := UIFactory.label(fallback, &"", false, HORIZONTAL_ALIGNMENT_CENTER)
		glyph.custom_minimum_size = Vector2(side, side)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return glyph
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Screen header: back button, title (+ subtitle) on a soft shadow, and the resource ribbon.
static func header(title: String, subtitle: String, back: Callable, back_label: String = "Castle") -> Control:
	var bar := UIFactory.hbox(16)
	bar.name = "Header"
	if back.is_valid():
		var back_button := OrnateButton.create("‹ " + back_label, "icon_ui_home" if back_label == "Castle" else "", false, Vector2(200, 54))
		back_button.name = "BackButton"
		back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back_button.pressed.connect(back)
		bar.add_child(back_button)
	var titles := UIFactory.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := UIFactory.label(title, &"HeaderLabel", false)
	heading.name = "Title"
	heading.clip_text = true
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER + 4)
	heading.add_theme_color_override("font_color", Color("f6e7c1"))
	heading.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.12, 0.9))
	heading.add_theme_constant_override("shadow_outline_size", 8)
	titles.add_child(heading)
	if subtitle != "":
		var sub := UIFactory.label(subtitle, &"", true)
		sub.name = "Subtitle"
		sub.add_theme_color_override("font_color", Color("e4dcf0"))
		sub.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.12, 0.85))
		sub.add_theme_constant_override("shadow_outline_size", 6)
		titles.add_child(sub)
	bar.add_child(titles)
	if GameState.campaign != null:
		bar.add_child(resources(GameState.campaign))
	return bar


## A dark rounded panel with a vertical column inside; returns the panel (column = get_child(0)).
## With the composed kit the panel is navy enamel with gold corners (the default tint); a custom
## tint (accents, locked states) keeps the flat style so its colour still reads.
static func card_panel(separation: int = 10, tint: Color = UITheme.GOLD_DARK) -> PanelContainer:
	var kit := UIKit.style("panel_navy")
	if kit != null and tint != UITheme.GOLD_DARK:
		# An accent (a sister's colour, a locked grey, success / danger) tints the enamel lightly.
		kit = kit.duplicate() as StyleBoxTexture
		kit.modulate_color = Color.WHITE.lerp(Color(tint.r, tint.g, tint.b, 1.0), 0.35)
	var panel := UIFactory.panel(kit if kit != null else UITheme.box(Color(UITheme.NAVY_DEEP, 0.88), tint, 14, 2, 16))
	panel.add_child(UIFactory.vbox(separation))
	return panel


static func column_of(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0) as VBoxContainer


## Modal confirmation: title, text, a confirm button (runs `on_confirm`) and Cancel. Nothing happens
## until the confirm button is pressed.
static func confirm(parent: Node, title: String, text: String, confirm_label: String, on_confirm: Callable, node_name: String = "ConfirmDialog") -> Control:
	var old := parent.get_node_or_null(node_name)
	if old != null:
		old.queue_free()
	var dim := ColorRect.new()
	dim.name = node_name
	dim.color = Color(0, 0, 0, 0.72)
	UIFactory.full_rect(dim)
	parent.add_child(dim)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	dim.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = 520
	center.add_child(panel)
	var column := UIFactory.vbox(14)
	panel.add_child(column)
	column.add_child(UIFactory.label(title, &"HeaderLabel", true, HORIZONTAL_ALIGNMENT_CENTER))
	var body := UIFactory.label(text, &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	body.name = "Body"
	column.add_child(body)
	var buttons := UIFactory.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel := UIFactory.button("Cancel", false, Vector2(190, 56))
	cancel.name = "Cancel"
	cancel.pressed.connect(dim.queue_free)
	buttons.add_child(cancel)
	var ok := UIFactory.button(confirm_label, true, Vector2(190, 56))
	ok.name = "Confirm"
	ok.pressed.connect(func() -> void:
		dim.queue_free()
		on_confirm.call())
	buttons.add_child(ok)
	column.add_child(buttons)
	ok.grab_focus.call_deferred()
	return dim


## A short message that fades out by itself (purchases, errors).
static func toast(parent: Control, text: String, good: bool = true) -> void:
	var old := parent.get_node_or_null("Toast")
	if old != null:
		old.queue_free()
	var pill := UIFactory.panel(UITheme.box(Color(UITheme.NAVY_DEEP, 0.94), UITheme.GOLD if good else UITheme.CRIMSON, 12, 2, 12))
	pill.name = "Toast"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UIFactory.label(text, &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	label.name = "ToastText"
	label.custom_minimum_size.x = 320
	pill.add_child(label)
	parent.add_child(pill)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_bottom = -24
	var tween := pill.create_tween()
	tween.tween_interval(TOAST_TIME)
	tween.tween_property(pill, "modulate:a", 0.0, 0.4)
	tween.tween_callback(pill.queue_free)


## A row of toggle chips (one selected). options: [[id, label], ...]. on_pick(id).
static func chips(options: Array, selected: String, on_pick: Callable, name_prefix: String = "Chip", wrap: bool = true) -> Container:
	var flow: Container = HFlowContainer.new() if wrap else HBoxContainer.new()
	flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for option: Array in options:
		var chip := UIFactory.button(str(option[1]), false, Vector2(0, CHIP_HEIGHT))
		chip.name = "%s_%s" % [name_prefix, str(option[0])]
		chip_style(chip)
		chip.toggle_mode = true
		chip.button_pressed = str(option[0]) == selected
		chip.pressed.connect(on_pick.bind(str(option[0])))
		flow.add_child(chip)
	return flow


## Choice chips (tabs, filters, sister pickers): the rectangular navy enamel, lit gold when selected
## (pressed). The pointed buttons stay for actions; short chip labels never touch an end cap.
static func chip_style(chip: Button) -> void:
	for entry in [["normal", Color.WHITE], ["hover", Color(1.3, 1.22, 1.08)], ["pressed", Color(1.65, 1.35, 0.75)], ["hover_pressed", Color(1.8, 1.5, 0.85)], ["disabled", Color(0.6, 0.6, 0.66, 0.7)]]:
		var box := UITheme.compact_button_style(entry[1])
		if box is StyleBoxTexture:
			box = box.duplicate()
			(box as StyleBoxTexture).content_margin_left = 14
			(box as StyleBoxTexture).content_margin_right = 14
		chip.add_theme_stylebox_override(str(entry[0]), box)
	chip.add_theme_stylebox_override("focus", UITheme.box(Color.TRANSPARENT, Color(UITheme.MAGIC_BLUE, 0.9), 8, 2, 4))
	chip.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	chip.add_theme_color_override("font_pressed_color", Color("fff0c8"))
	chip.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


## A compact drop-down filter (touch friendly). options: [[id, label], ...]. on_pick(id).
static func dropdown(options: Array, selected: String, on_pick: Callable, node_name: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name
	picker.custom_minimum_size = Vector2(170, CHIP_HEIGHT)
	picker.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	for i in options.size():
		picker.add_item(str(options[i][1]), i)
		if str(options[i][0]) == selected:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void: on_pick.call(str(options[index][0])))
	return picker


## A flowing grid inside a vertical scroll area (cards, tiles). Returns the scroll; the grid is its child.
static func flow_scroll(separation: int = 10) -> ScrollContainer:
	var scroll := UIFactory.scroll()
	var flow := HFlowContainer.new()
	flow.name = "Grid"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", separation)
	flow.add_theme_constant_override("v_separation", separation)
	scroll.add_child(flow)
	return scroll


static func grid_of(scroll: ScrollContainer) -> HFlowContainer:
	return scroll.get_node("Grid") as HFlowContainer


## A card face for a collection copy (or a definition), sized for grids.
static func card(def: CardDef, owner_id: String, upgrade_level: int, scale: float = 0.8) -> CardView:
	var view := CardView.new()
	view.show_owned(def, owner_id, upgrade_level)
	view.set_scale_factor(scale)
	return view


## A big clickable tile: icon, title, one line of text; greyed out with a hint when locked.
static func tile(title: String, text: String, icon_path: String, locked: bool, hint: String = "") -> Button:
	var button := Button.new()
	button.custom_minimum_size = TILE_MIN
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.NAVY_DEEP, 0.86), UITheme.GOLD_DARK if not locked else Color(0.4, 0.4, 0.45), 14, 2, 14))
	button.add_theme_stylebox_override("hover", UITheme.box(Color(UITheme.NAVY, 0.94), UITheme.GOLD, 14, 3, 14))
	button.add_theme_stylebox_override("pressed", UITheme.box(Color(UITheme.NAVY_LIGHT, 0.94), UITheme.GOLD, 14, 3, 14))
	button.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 14, 3, 14))
	button.add_theme_stylebox_override("disabled", UITheme.box(Color(UITheme.NAVY_DEEP, 0.7), Color(0.35, 0.35, 0.4), 14, 2, 14))
	var row := UIFactory.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(row)
	row.offset_left = 14
	row.offset_right = -14
	row.offset_top = 10
	row.offset_bottom = -10
	button.add_child(row)
	var texture := UIAssets.texture(icon_path) if icon_path != "" else null
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(52, 52)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color(1, 1, 1, 1) if not locked else Color(0.5, 0.5, 0.55)
		row.add_child(icon)
	var texts := UIFactory.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := UIFactory.label(("🔒 " if locked else "") + title, &"", false)
	heading.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	heading.add_theme_color_override("font_color", UITheme.GOLD if not locked else UITheme.IVORY_DIM)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(heading)
	var body := UIFactory.label(hint if locked and hint != "" else text, &"DimLabel", true)
	body.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(body)
	row.add_child(texts)
	button.disabled = locked
	return button


## Large view of one card with optional actions: [[label, callable, primary], ...]. Tapping outside
## or Close dismisses it (works the same with mouse and touch).
static func inspect_card(parent: Node, def: CardDef, owner_id: String, upgrade_level: int, info: String, actions: Array) -> Control:
	var old := parent.get_node_or_null("CardInspect")
	if old != null:
		old.free()
	var dim := ColorRect.new()
	dim.name = "CardInspect"
	dim.color = Color(0, 0, 0, 0.74)
	UIFactory.full_rect(dim)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			dim.queue_free())
	parent.add_child(dim)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := UIFactory.panel()
	center.add_child(panel)
	var column := UIFactory.vbox(10)
	panel.add_child(column)
	var view := card(def, owner_id, upgrade_level, 1.55)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(view)
	if info != "":
		var text := UIFactory.label(info, &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
		text.custom_minimum_size.x = 300
		column.add_child(text)
	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("h_separation", 8)
	for action: Array in actions:
		var button := UIFactory.button(str(action[0]), bool(action[2]) if action.size() > 2 else false, Vector2(170, 52))
		button.name = "Action_" + str(action[0]).replace(" ", "")
		var callback: Callable = action[1]
		button.pressed.connect(func() -> void:
			dim.queue_free()
			callback.call())
		buttons.add_child(button)
	var close := UIFactory.button("Close", false, Vector2(130, 52))
	close.name = "Close"
	close.pressed.connect(dim.queue_free)
	buttons.add_child(close)
	column.add_child(buttons)
	return dim


## Status keywords a card works with (its synergy tags): statuses it applies or reads.
static func card_tags(def: CardDef) -> Array[String]:
	var tags: Array[String] = []
	var effects: Array = def.effects.duplicate()
	for effect: Dictionary in effects:
		for key in ["status_id", "add_status_id"]:
			if effect.has(key) and not tags.has(str(effect[key])):
				tags.append(str(effect[key]))
		for key in ["bonus_if_status", "per_target_status", "from_target_status"]:
			if effect.get(key, {}) is Dictionary and str((effect.get(key, {}) as Dictionary).get("status_id", "")) != "":
				var status_id := str(effect[key]["status_id"])
				if not tags.has(status_id):
					tags.append(status_id)
		if effect.has("per_aether") or str(effect.get("effect", "")) == "spend_aether":
			if not tags.has("aether"):
				tags.append("aether")
	return tags


## A small badge laid over a card (copy count, "not found"): placed at the top-right corner, or
## centred on the art with `centered`. It never takes clicks, so the card stays tappable.
static func badge_on(view: Control, text: String, color: Color, centered: bool = false) -> PanelContainer:
	var badge := UIFactory.panel(UITheme.box(Color(UITheme.NAVY_DEEP, 0.92), color, 10, 2, 6))
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UIFactory.label(text, &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color.lightened(0.3))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	view.add_child(badge)
	if centered:
		badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
		badge.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		# Bottom-right corner, over the frame's foot: never on the card's name or cost.
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -2
		badge.offset_bottom = -2
	return badge


## "Learned" style small label pill.
## `on_light` (parchment cards): a darker ink so the pill reads on ivory.
static func pill(text: String, color: Color, on_light: bool = false) -> PanelContainer:
	var panel := UIFactory.panel(UITheme.box(Color(color, 0.16 if on_light else 0.22), color.darkened(0.2) if on_light else color, 10, 1, 6))
	var label := UIFactory.label(text, &"", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color.darkened(0.45) if on_light else color.lightened(0.35))
	panel.add_child(label)
	return panel


## Narrow screens (phones in landscape and small windows) use one column instead of two.
static func is_narrow(control: Control) -> bool:
	return control.get_viewport_rect().size.x < 1000.0
