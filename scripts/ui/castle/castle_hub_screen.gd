extends ScreenBase
## The castle: the sisters' persistent home between expeditions (docs/PERSISTENT_RPG_DESIGN.md),
## drawn in the Celestial Royal Fantasy style (docs/ART_DIRECTION.md): the dusk castle terrace, a gold
## title crest, a resource ribbon, parchment service plaques with diamond medallions (built from
## data/castle/services.json), the war table emphasised and a violet "Set Out" seal as the one
## primary action. Locked services are greyed with a padlock and say how to open them. All art is
## optional: without the generated kit the screen falls back to the theme's styles. Autosaves on entry.

const PLAQUE_HEIGHT := 100.0
const MEDALLION := 78.0
## Room kept for the title block and the footer when the plaque area is sized.
const CHROME_HEIGHT := 330.0
const SERVICE_ICONS := {
	"expeditions": "icon_svc_expeditions", "library": "icon_svc_library", "collection": "icon_svc_collection",
	"armory": "icon_svc_armory", "blacksmith": "icon_svc_blacksmith", "enchanter": "icon_svc_enchanter",
	"apothecary": "icon_svc_apothecary", "training_hall": "icon_svc_training", "sisters": "icon_svc_sisters",
}

var _grid: GridContainer


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.08


func _menu_background() -> String:
	return "bg_castle_hub"


func _build() -> void:
	if GameState.campaign == null:
		SceneRouter.go.call_deferred(SceneRouter.Screen.MAIN_MENU)
		return
	if not GameState.in_castle():
		GameState.enter_castle()
	else:
		GameState.save_game()
	var campaign := GameState.campaign
	_add_lower_shade()
	var column := UIFactory.vbox(10)
	root.add_child(column)
	var top := UIFactory.hbox(16)
	top.add_child(_title_block())
	top.add_child(UIFactory.expander())
	var ribbon := _resource_ribbon(campaign)
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(ribbon)
	column.add_child(top)
	column.add_child(UIFactory.expander())
	var scroll := UIFactory.scroll()
	scroll.size_flags_vertical = Control.SIZE_SHRINK_END
	scroll.name = "ServiceScroll"
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "ServiceGrid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	for service in _services():
		var open := campaign.services.has(str(service["id"]))
		var plaque := _plaque(service, open)
		_grid.add_child(plaque)
	column.add_child(_footer())
	resized.connect(_fit)
	_fit.call_deferred()


## A soft dark fade over the lower part of the picture so the plaques and buttons sit on calm ground.
func _add_lower_shade() -> void:
	var shade := TextureRect.new()
	shade.name = "LowerShade"
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UITheme.NAVY_DEEP, 0.0))
	gradient.set_color(1, Color(UITheme.NAVY_DEEP, 0.62))
	gradient.add_point(0.45, Color(UITheme.NAVY_DEEP, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	UIFactory.full_rect(shade)
	add_child(shade)
	move_child(shade, 1)


func _title_block() -> Control:
	var block := UIFactory.vbox(0)
	block.name = "TitleBlock"
	block.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var crest_texture := UIKit.picture("orn_crest")
	if crest_texture != null:
		var crest := TextureRect.new()
		crest.texture = crest_texture
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest.custom_minimum_size = Vector2(300, 46)
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(crest)
	var title := UIFactory.label("The Royal Castle", &"TitleLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	title.add_theme_color_override("font_color", Color("f6e7c1"))
	title.add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.15, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 10)
	title.add_theme_font_size_override("font_size", 46)
	block.add_child(title)
	var subtitle := UIFactory.label(_status_text(GameState.campaign), &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.name = "StatusText"
	subtitle.custom_minimum_size.x = 470
	subtitle.add_theme_color_override("font_color", Color("f1e9d6"))
	subtitle.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.12, 0.9))
	subtitle.add_theme_constant_override("shadow_outline_size", 8)
	block.add_child(subtitle)
	var divider_texture := UIKit.picture("orn_divider")
	if divider_texture != null:
		var divider := TextureRect.new()
		divider.texture = divider_texture
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		divider.custom_minimum_size = Vector2(340, 30)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(divider)
	var problems := DeckRules.validate_campaign(GameState.campaign)
	if not problems.is_empty():
		var warn := UIFactory.label("Deck Workshop: " + problems[0], &"", true, HORIZONTAL_ALIGNMENT_CENTER)
		warn.name = "DeckWarning"
		warn.custom_minimum_size.x = 380
		warn.add_theme_color_override("font_color", Color("ffb3a8"))
		warn.add_theme_constant_override("outline_size", 6)
		warn.add_theme_color_override("font_outline_color", Color(UITheme.NAVY_DEEP, 0.9))
		block.add_child(warn)
	return block


## Welcome text on the first visit, then the campaign at a glance.
static func _status_text(campaign: CampaignState) -> String:
	if int(campaign.stats.get("expeditions_started", 0)) == 0:
		return "Home. Prepare the sisters, then set out from the war table — walk the castle halls first."
	var open_missions := 0
	for region in ExpeditionService.regions():
		if ExpeditionService.region_unlocked(campaign, str(region["id"])):
			open_missions += ExpeditionService.missions_of(str(region["id"])).filter(func(m: Dictionary) -> bool: return ExpeditionService.mission_lock_reason(campaign, str(m["id"])) == "").size()
	return "Home. %d missions await at the war table · %d journeys completed." % [open_missions, int(campaign.stats.get("expeditions_completed", 0))]


## Gold, Starlight Essence and Sister Bond on a navy enamel ribbon with painted icons (shared).
func _resource_ribbon(campaign: CampaignState) -> Control:
	return CastleUI.resources(campaign)


## A painted UI picture (generated art) or a small coloured glyph when the art is missing.
func _picture(asset_id: String, side: float) -> Control:
	var texture := UIKit.picture(asset_id)
	if texture == null:
		var glyph := UIFactory.label("◆", &"", false, HORIZONTAL_ALIGNMENT_CENTER)
		glyph.custom_minimum_size = Vector2(side, side)
		return glyph
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Diamond medallion: the shared navy/gold frame with the service icon inside (padlock when locked).
func _medallion(service_id: String, open: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(MEDALLION, MEDALLION)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := _picture("frame_diamond", MEDALLION)
	UIFactory.full_rect(frame)
	holder.add_child(frame)
	# A soft light halo inside the diamond so dark icons (navy cards, shield) still read on the enamel.
	var halo := TextureRect.new()
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.texture = _halo_texture()
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.position = Vector2.ONE * MEDALLION * 0.14
	halo.size = Vector2.ONE * MEDALLION * 0.72
	halo.modulate = Color(1, 1, 1, 1.0 if open else 0.4)
	holder.add_child(halo)
	var side := MEDALLION * 0.58
	var icon := _picture(str(SERVICE_ICONS.get(service_id, "")), side)
	icon.position = Vector2.ONE * (MEDALLION - side) / 2.0
	icon.size = Vector2(side, side)
	if not open:
		icon.modulate = Color(0.5, 0.5, 0.56)
		frame.modulate = Color(0.62, 0.62, 0.68)
	holder.add_child(icon)
	if not open:
		var lock := _picture("icon_ui_lock", MEDALLION * 0.36)
		lock.position = Vector2(MEDALLION * 0.62, MEDALLION * 0.62)
		lock.size = Vector2.ONE * MEDALLION * 0.36
		holder.add_child(lock)
	return holder


static var _halo: GradientTexture2D


static func _halo_texture() -> GradientTexture2D:
	if _halo == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.85, 0.82, 1.0, 0.5))
		gradient.set_color(1, Color(0.6, 0.65, 1.0, 0.0))
		_halo = GradientTexture2D.new()
		_halo.gradient = gradient
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
		_halo.width = 128
		_halo.height = 128
	return _halo


## One service as a parchment plaque button: medallion, name, one line of text and a chevron.
func _plaque(service: Dictionary, open: bool) -> Button:
	var service_id := str(service["id"])
	var button := Button.new()
	button.name = "Service_" + service_id
	button.custom_minimum_size = Vector2(300, PLAQUE_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not open
	button.tooltip_text = str(service.get("description", "")) if open else str(service.get("hint", ""))
	var kit := UIKit.has("plaque_parchment")
	if kit:
		button.add_theme_stylebox_override("normal", UIKit.style("plaque_parchment"))
		button.add_theme_stylebox_override("hover", UIKit.style("plaque_parchment_hover"))
		button.add_theme_stylebox_override("pressed", UIKit.style("plaque_parchment_pressed"))
		button.add_theme_stylebox_override("hover_pressed", UIKit.style("plaque_parchment_pressed"))
		button.add_theme_stylebox_override("disabled", UIKit.style("plaque_locked"))
		button.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color(UITheme.MAGIC_BLUE, 0.95), 10, 3, 4))
	var ink := UITheme.INK if kit else UITheme.GOLD
	var soft_ink := UITheme.INK_SOFT if kit else UITheme.IVORY_DIM
	if not open:
		ink = Color("d8d2c4") if kit else UITheme.IVORY_DIM
		soft_ink = Color("bdb6a6") if kit else UITheme.IVORY_DIM
	var row := UIFactory.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(row)
	row.offset_left = 22
	row.offset_right = -18
	row.offset_top = 8
	row.offset_bottom = -8
	button.add_child(row)
	row.add_child(_medallion(service_id, open))
	var texts := UIFactory.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := UIFactory.label(str(service["name"]), &"", false)
	heading.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_HEADER))
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 4)
	heading.add_theme_color_override("font_color", ink)
	heading.clip_text = true
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(heading)
	var body := UIFactory.label(str(service.get("description", "")) if open else "🔒 " + str(service.get("hint", "")), &"", true)
	body.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	body.add_theme_color_override("font_color", soft_ink)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.max_lines_visible = 2
	texts.add_child(body)
	row.add_child(texts)
	var chevron := UIFactory.label("›" if open else "", &"", false)
	chevron.add_theme_font_size_override("font_size", 34)
	chevron.add_theme_color_override("font_color", UITheme.INK_SOFT if kit else UITheme.GOLD)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chevron)
	if service_id == "expeditions" and open:
		_mark_war_table(button)
	var notice := _notice_for(service_id) if open else ""
	if notice != "":
		_corner_tag(button, notice, "Notice")
	button.pressed.connect(_open_service.bind(service))
	return button


## Something waiting in a service: a pending Mastery card (The Sisters) or an unused Dual
## Specialization (Training Hall).
static func _notice_for(service_id: String) -> String:
	var campaign := GameState.campaign
	if campaign == null:
		return ""
	match service_id:
		"sisters":
			return "Mastery card!" if not campaign.level_rewards.is_empty() else ""
		"training_hall":
			for m in campaign.roster.members:
				if Levels.can_dual_spec(campaign, m.id) and m.secondary_specialization == null:
					return "Dual Specialization!"
	return ""


func _corner_tag(button: Button, text_value: String, node_name: String) -> void:
	var tag := PanelContainer.new()
	tag.name = node_name
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", UITheme.box(Color("6a4a12"), UITheme.GOLD, 8, 1, 4))
	var text := UIFactory.label(text_value, &"", false)
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_BUTTON))
	text.add_theme_color_override("font_color", Color("ffe9b0"))
	tag.add_child(text)
	button.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tag.offset_right = -34
	tag.offset_top = 4


## The war table plaque stands out: a violet glow around it and a small "War Table" ribbon.
func _mark_war_table(button: Button) -> void:
	var glow := Panel.new()
	glow.name = "WarTableGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0), Color(UITheme.VIOLET_LIGHT, 0.9), 14, 3, 0))
	UIFactory.full_rect(glow)
	glow.offset_left = -4
	glow.offset_top = -4
	glow.offset_right = 4
	glow.offset_bottom = 4
	button.add_child(glow)
	var tag := PanelContainer.new()
	tag.name = "WarTableTag"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.VIOLET, 0.95), UITheme.GOLD, 8, 1, 4))
	var text := UIFactory.label("War Table", &"", false)
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_font_override("font", UITheme.font(UITheme.WEIGHT_BUTTON))
	text.add_theme_color_override("font_color", Color("f6e7c1"))
	tag.add_child(text)
	button.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tag.offset_right = -34
	tag.offset_top = 4


func _footer() -> Control:
	var footer := UIFactory.hbox(12)
	footer.name = "Footer"
	var menu := _icon_button("Main Menu", "icon_ui_home", "MainMenuButton")
	menu.tooltip_text = "The campaign is saved."
	menu.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAIN_MENU))
	footer.add_child(menu)
	var settings := _icon_button("Settings", "icon_ui_settings", "SettingsButton")
	settings.pressed.connect(func() -> void: SceneRouter.open_settings(SceneRouter.Screen.CASTLE_HUB))
	footer.add_child(settings)
	footer.add_child(UIFactory.expander())
	var go := OrnateButton.create("Set Out  ›", "icon_svc_expeditions", true, Vector2(290, 68))
	go.name = "SetOutButton"
	go.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON + 6)
	go.tooltip_text = "Open the war table and choose an expedition."
	go.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.WORLD_MAP))
	footer.add_child(go)
	return footer


func _icon_button(text: String, icon_id: String, node_name: String) -> Button:
	var button := OrnateButton.create(text, icon_id, false, Vector2(250, 56))
	button.name = node_name
	return button


func _services() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for service: Dictionary in DataRegistry.services.values():
		list.append(service)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return list


## Three plaque columns on wide screens, two on medium, one on narrow; the plaques keep their height.
func _fit() -> void:
	if _grid == null:
		return
	_grid.columns = 1 if size.x < 760 else (2 if size.x < 1180 else 3)
	var scroll := _grid.get_parent() as ScrollContainer
	var rows := ceili(float(_grid.get_child_count()) / _grid.columns)
	var wanted := rows * PLAQUE_HEIGHT + (rows - 1) * 12.0
	scroll.custom_minimum_size.y = minf(wanted, maxf(PLAQUE_HEIGHT, size.y - CHROME_HEIGHT))


func _open_service(service: Dictionary) -> void:
	match str(service.get("screen", "")):
		"world_map":
			SceneRouter.go(SceneRouter.Screen.WORLD_MAP)
		"equipment":
			SceneRouter.open_equipment(SceneRouter.Screen.CASTLE_HUB)
		_:
			SceneRouter.open_service(str(service["id"]))
