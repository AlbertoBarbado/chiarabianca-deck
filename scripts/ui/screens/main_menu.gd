extends ScreenBase
## Cinematic title screen: castle backdrop, the game logo, Chiara and Bianca on opposite sides
## and the menu in the centre: New Campaign, Continue, Settings, the Quick Play grid and Exit. All
## buttons are real controls; Continue is disabled unless a save exists (the campaign first, else a
## Quick Play run). Quick Play runs are classic runs without the castle, saved in their own slot so
## they never touch the campaign. Positions are computed from the stage size, so any landscape
## window works.

const BUTTON_WIDTH := 300.0
const BUTTON_HEIGHT := 62.0
const LOGO_WIDTH_SHARE := 0.42
const LOGO_MIN_WIDTH := 380.0
const LOGO_MAX_WIDTH := 640.0
const CHARACTER_HEIGHT_SHARE := 0.8
const BIANCA_HEIGHT_SHARE := 0.8
const GLOW_PERIOD := 3.2
const SMALL_BUTTON_SHARE := 0.7
const MENU_BOTTOM_MARGIN_SHARE := 0.02
## Direct starts at a later act of the normal run (the run continues to the following acts), and
## Frostpeak, a standalone adventure that is not part of the act order (its summit ends the run).
const ACT_STARTS := [
	{"label": "Start: Forest", "button": "ActForestButton", "map_id": "enchanted_forest",
		"tooltip": "Begin a run directly in Act II, the Enchanted Forest."},
	{"label": "Start: Coast", "button": "ActCoastButton", "map_id": "sunlit_coast",
		"tooltip": "Begin a run directly in Act III, the Sunlit Coast."},
	{"label": "Frostpeak", "button": "ActFrostpeakButton", "map_id": "frostpeak",
		"tooltip": "A standalone adventure: climb Frostpeak from its snowy foothills to the White Dragon's aerie."},
]

var continue_button: Button
var notice: Label

var _stage: Control
var _logo: TextureRect
var _menu: VBoxContainer
var _chiara: CharacterShowcase
var _bianca: CharacterShowcase


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.22


func _build() -> void:
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stage)

	_chiara = CharacterShowcase.new()
	_stage.add_child(_chiara)
	_chiara.setup("chiara", DataRegistry.get_character("chiara").accent_color, -1, 0.15)
	_bianca = CharacterShowcase.new()
	_stage.add_child(_bianca)
	_bianca.setup("bianca", DataRegistry.get_character("bianca").accent_color, 1, 0.3)

	_logo = TextureRect.new()
	_logo.texture = UIAssets.texture("processed/logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_logo)
	if _logo.texture == null:  # Missing art: text title.
		var title := UIFactory.label("VOIDFARER CHRONICLES", &"TitleLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
		_logo.add_child(title)
		UIFactory.full_rect(title)
	_start_logo_glow()

	_menu = UIFactory.vbox(12)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_menu)
	var new_game := _menu_button("New Campaign", true)
	new_game.name = "NewCampaignButton"
	new_game.tooltip_text = "Start a campaign: the castle is your home between expeditions."
	new_game.pressed.connect(_on_new_game)
	continue_button = _menu_button("Continue", false)
	continue_button.disabled = _continue_slot() == ""
	continue_button.pressed.connect(_on_continue)
	var settings := _menu_button("Settings", false)
	settings.name = "SettingsButton"
	settings.pressed.connect(func() -> void: SceneRouter.open_settings(SceneRouter.Screen.MAIN_MENU))
	if _continue_slot() != "":
		# Settings and Delete Save share a row so the menu still fits a 720p screen.
		var settings_row := UIFactory.hbox(8)
		settings_row.name = "SettingsRow"
		_menu.add_child(settings_row)
		settings.reparent(settings_row)
		settings.custom_minimum_size = Vector2((BUTTON_WIDTH - 8.0) / 2.0, BUTTON_HEIGHT)
		settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var delete_button := UIFactory.button("Delete Save", false, Vector2((BUTTON_WIDTH - 8.0) / 2.0, BUTTON_HEIGHT))
		delete_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON + 2)
		delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		delete_button.name = "DeleteSaveButton"
		delete_button.pressed.connect(_ask_delete_save)
		settings_row.add_child(delete_button)
	# Test areas and direct act starts share a grid of smaller buttons, so the menu fits short screens.
	var demo_row := GridContainer.new()
	demo_row.columns = 2
	demo_row.add_theme_constant_override("h_separation", 8)
	demo_row.add_theme_constant_override("v_separation", 6)
	demo_row.name = "DemoRow"
	_menu.add_child(demo_row)
	var classic := _small_menu_button("Classic Run", demo_row)
	classic.name = "ClassicRunButton"
	classic.tooltip_text = "Quick Play: the classic run from the Royal Castle through the Forest and the Coast, without the castle hub."
	classic.pressed.connect(_on_classic_run)
	if GameState.slot_has_save(GameState.SLOT_CAMPAIGN) and GameState.slot_has_save(GameState.SLOT_QUICKPLAY):
		var resume := _small_menu_button("Resume Quick Play", demo_row)
		resume.name = "ResumeQuickPlayButton"
		resume.pressed.connect(_resume_slot.bind(GameState.SLOT_QUICKPLAY))
	var demo_button := _small_menu_button("Elite Route", demo_row)
	demo_button.name = "DemoRouteButton"
	demo_button.tooltip_text = "Demo: a short castle route packed with elite fights."
	demo_button.pressed.connect(_on_demo_route)
	var ai_button := _small_menu_button("Crystal Cave", demo_row)
	ai_button.name = "DemoCrystalButton"
	ai_button.tooltip_text = "A short test area whose map, monsters and backgrounds were generated locally with ComfyUI."
	ai_button.pressed.connect(_on_demo_crystal)
	for act in ACT_STARTS:
		var act_button := _small_menu_button(act["label"], demo_row)
		act_button.name = act["button"]
		act_button.tooltip_text = act["tooltip"]
		act_button.pressed.connect(_on_act_start.bind(act["map_id"]))
	var exit := _menu_button("Exit", false)
	exit.pressed.connect(func() -> void: get_tree().quit())
	notice = UIFactory.label("", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	notice.add_theme_color_override("font_outline_color", Color(UITheme.NAVY_DEEP, 0.9))
	notice.add_theme_constant_override("outline_size", 6)
	_menu.add_child(notice)

	_stage.resized.connect(_layout_stage)
	_layout_stage()
	new_game.grab_focus.call_deferred()


func _small_menu_button(text: String, row: Container) -> Button:
	var button := UIFactory.button(text, false, Vector2((BUTTON_WIDTH - 8.0) / 2.0, BUTTON_HEIGHT * SMALL_BUTTON_SHARE))
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL - 1)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	row.add_child(button)
	return button


func _menu_button(text: String, primary: bool) -> Button:
	var button := UIFactory.button(text, primary, Vector2(BUTTON_WIDTH, BUTTON_HEIGHT))
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON + 2)
	_menu.add_child(button)
	return button


## Logo top-centre, buttons below it, the two princesses at the lower corners.
func _layout_stage() -> void:
	var area := _stage.size
	var logo_width := clampf(area.x * LOGO_WIDTH_SHARE, LOGO_MIN_WIDTH, LOGO_MAX_WIDTH)
	var logo_height := logo_width * 549.0 / 1230.0
	var logo_aspect := 549.0 / 1230.0
	if _logo.texture != null:
		logo_aspect = _logo.texture.get_height() / float(_logo.texture.get_width())
	logo_height = logo_width * logo_aspect
	_menu.custom_minimum_size.x = BUTTON_WIDTH
	_menu.size = Vector2(BUTTON_WIDTH, _menu.get_combined_minimum_size().y)
	# The buttons always fit: the logo gives up height when the menu needs it.
	var room_for_logo := area.y * (1.0 - MENU_BOTTOM_MARGIN_SHARE - 0.04) - _menu.size.y
	if logo_height > room_for_logo:
		logo_height = maxf(room_for_logo, 0.0)
		logo_width = logo_height / logo_aspect
	_logo.size = Vector2(logo_width, logo_height)
	_logo.position = Vector2((area.x - logo_width) / 2.0, area.y * 0.01)
	_menu.position = Vector2((area.x - BUTTON_WIDTH) / 2.0, _logo.position.y + logo_height + area.y * 0.03)
	for entry in [[_chiara, "chiara", 0], [_bianca, "bianca", 1]]:
		var character_height := area.y * (CHARACTER_HEIGHT_SHARE if entry[2] == 0 else BIANCA_HEIGHT_SHARE)
		var showcase: CharacterShowcase = entry[0]
		var texture := AssetCatalog.figure(entry[1])
		var aspect := texture.get_width() / float(texture.get_height()) if texture != null else 0.8
		var width := character_height * aspect
		showcase.size = Vector2(width, character_height)
		showcase.position = Vector2(0.0 if entry[2] == 0 else area.x - width, area.y - character_height)


## Slow breathing glow on the logo (skipped when effects are off).
func _start_logo_glow() -> void:
	if SettingsStore.load_values().get("effects_quality", "full") == "off":
		return
	var tween := create_tween().set_loops()
	tween.tween_property(_logo, "self_modulate", Color(1.18, 1.12, 1.0), GLOW_PERIOD / 2.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_logo, "self_modulate", Color(0.94, 0.94, 0.94), GLOW_PERIOD / 2.0).set_trans(Tween.TRANS_SINE)


## Confirmation before the save is deleted; nothing is removed until "Delete" is pressed.
func _ask_delete_save() -> void:
	if get_node_or_null("DeleteConfirm") != null:
		return
	var dim := ColorRect.new()
	dim.name = "DeleteConfirm"
	dim.color = Color(0, 0, 0, 0.75)
	UIFactory.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	dim.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = 520
	center.add_child(panel)
	var column := UIFactory.vbox(14)
	panel.add_child(column)
	column.add_child(UIFactory.label("Delete the saved run?", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UIFactory.label("Your current adventure (party, decks, gold and map progress) will be lost. This cannot be undone.", &"", true, HORIZONTAL_ALIGNMENT_CENTER))
	var buttons := UIFactory.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel := UIFactory.button("Keep Save", true, Vector2(200, 56))
	cancel.name = "KeepSave"
	cancel.pressed.connect(dim.queue_free)
	buttons.add_child(cancel)
	var confirm := UIFactory.button("Delete", false, Vector2(200, 56))
	confirm.name = "ConfirmDelete"
	confirm.pressed.connect(func() -> void: _delete_save(dim))
	buttons.add_child(confirm)
	column.add_child(buttons)


func _delete_save(dialog: Control) -> void:
	GameState.use_slot(_continue_slot())
	GameState.delete_save()
	dialog.queue_free()
	continue_button.disabled = _continue_slot() == ""
	var delete_button := _menu.find_child("DeleteSaveButton", true, false)
	if delete_button != null:
		delete_button.queue_free()
	notice.text = "Saved run deleted."


## The save Continue resumes: the campaign first, else a Quick Play run ("" = none).
func _continue_slot() -> String:
	if GameState.slot_has_save(GameState.SLOT_CAMPAIGN):
		return GameState.SLOT_CAMPAIGN
	if GameState.slot_has_save(GameState.SLOT_QUICKPLAY):
		return GameState.SLOT_QUICKPLAY
	return ""


func _on_classic_run() -> void:
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	_on_new_game_keep_map()


func _on_demo_crystal() -> void:
	GameState.next_map_id = "crystal_hollow_demo"
	_on_new_game_keep_map()


func _on_demo_route() -> void:
	GameState.next_map_id = "castle_elite_demo"
	_on_new_game_keep_map()


func _on_act_start(map_id: String) -> void:
	GameState.next_map_id = map_id
	_on_new_game_keep_map()


## Quick Play: a classic run on the chosen map, in the Quick Play save slot.
func _on_new_game_keep_map() -> void:
	GameState.new_game_mode = "classic"
	GameState.use_slot(GameState.SLOT_QUICKPLAY)
	GameState.reset_selection()
	SceneRouter.go(SceneRouter.Screen.CHARACTER_SELECTION)


## A new campaign (the selection screens, then the castle). An existing campaign is replaced only
## after a confirmation.
func _on_new_game() -> void:
	if GameState.slot_has_save(GameState.SLOT_CAMPAIGN) and get_node_or_null("ReplaceConfirm") == null:
		CastleUI.confirm(self, "Start a new campaign?", "Your current campaign (collection, castle, progress) will be replaced when the new one begins.",
			"Start Anew", _start_new_campaign, "ReplaceConfirm")
		return
	_start_new_campaign()


func _start_new_campaign() -> void:
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	GameState.new_game_mode = "campaign"
	GameState.use_slot(GameState.SLOT_CAMPAIGN)
	GameState.reset_selection()
	SceneRouter.go(SceneRouter.Screen.CHARACTER_SELECTION)


func _on_continue() -> void:
	_resume_slot(_continue_slot())


func _resume_slot(slot: String) -> void:
	GameState.use_slot(slot)
	var error := GameState.load_game()
	if error != "":
		notice.text = "Cannot continue: " + error
		return
	SceneRouter.resume_run()
