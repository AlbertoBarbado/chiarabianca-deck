extends ScreenBase
## Cinematic title screen (docs/ART_DIRECTION.md): the painted twilight castle, the game logo, the
## two sisters and a menu with a clear hierarchy:
##   1. Continue (when a save exists) / New Campaign — violet enamel, the main actions
##   2. Quick Play — opens a submenu with the classic run and the direct starts (Elite Route,
##      Crystal Cave, Forest, Coast, Frostpeak): development and replay shortcuts, kept out of the way
##   3. Settings and Exit — a small row; Delete Save is a small link under it while a save exists
## All buttons are real controls; Continue resumes the campaign first, else a Quick Play run. Quick Play
## runs are classic runs without the castle, saved in their own slot. Layout is computed from the stage
## size, so any landscape window works.

const BUTTON_WIDTH := 360.0
const BUTTON_HEIGHT := 60.0
const LOGO_WIDTH_SHARE := 0.34
const LOGO_MIN_WIDTH := 320.0
const LOGO_MAX_WIDTH := 560.0
const CHARACTER_HEIGHT_SHARE := 0.74
const BIANCA_HEIGHT_SHARE := 0.74
const GLOW_PERIOD := 3.2
const SMALL_BUTTON_SHARE := 0.78
const MENU_BOTTOM_MARGIN_SHARE := 0.03
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
## The panel behind the menu (navy enamel) and the two stacks it switches between.
var _menu_panel: PanelContainer
var _main_stack: VBoxContainer
var _quick_stack: VBoxContainer
var _chiara: CharacterShowcase
var _bianca: CharacterShowcase


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.06


func _menu_background() -> String:
	return "bg_main_menu"


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

	# The buttons float over the painted sky on a soft dark glow (no boxy panel).
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "MenuPanel"
	var glow := StyleBoxTexture.new()
	glow.texture = _menu_glow()
	glow.content_margin_left = 24
	glow.content_margin_right = 24
	glow.content_margin_top = 22
	glow.content_margin_bottom = 22
	_menu_panel.add_theme_stylebox_override("panel", glow)
	_stage.add_child(_menu_panel)
	_menu = UIFactory.vbox(10)
	_menu.name = "Menu"
	_menu_panel.add_child(_menu)
	_main_stack = UIFactory.vbox(10)
	_main_stack.name = "MainStack"
	_menu.add_child(_main_stack)
	_quick_stack = UIFactory.vbox(8)
	_quick_stack.name = "QuickPlayStack"
	_quick_stack.visible = false
	_menu.add_child(_quick_stack)

	var has_save := _continue_slot() != ""
	continue_button = _menu_button("Continue", has_save, "icon_ui_continue", _main_stack)
	continue_button.name = "ContinueButton"
	continue_button.disabled = not has_save
	continue_button.tooltip_text = "Resume your campaign (or your Quick Play run)."
	continue_button.pressed.connect(_on_continue)
	var new_game := _menu_button("New Campaign", not has_save, "icon_ui_new_campaign", _main_stack)
	new_game.name = "NewCampaignButton"
	new_game.tooltip_text = "Start a campaign: the castle is your home between expeditions."
	new_game.pressed.connect(_on_new_game)
	if not has_save:
		# Without a save, New Campaign is the first choice.
		_main_stack.move_child(new_game, 0)
	var quick := _menu_button("Quick Play", false, "icon_ui_quickplay", _main_stack)
	quick.name = "QuickPlayButton"
	quick.tooltip_text = "Classic runs and direct starts, without the castle (separate save)."
	quick.pressed.connect(_show_quick_play.bind(true))
	_main_stack.add_child(_divider())
	var small_row := UIFactory.hbox(8)
	small_row.name = "SettingsRow"
	_main_stack.add_child(small_row)
	var settings := _small_menu_button("Settings", small_row)
	settings.name = "SettingsButton"
	settings.pressed.connect(func() -> void: SceneRouter.open_settings(SceneRouter.Screen.MAIN_MENU))
	var exit := _small_menu_button("Exit", small_row)
	exit.name = "ExitButton"
	exit.pressed.connect(func() -> void: get_tree().quit())
	if has_save:
		var delete_button := Button.new()
		delete_button.text = "Delete Save"
		delete_button.custom_minimum_size = Vector2(0, 40)
		delete_button.name = "DeleteSaveButton"
		delete_button.flat = true
		delete_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		delete_button.add_theme_color_override("font_color", UITheme.LAVENDER)
		delete_button.add_theme_color_override("font_hover_color", Color("ffb3a8"))
		for state in ["normal", "hover", "pressed", "focus"]:
			delete_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		delete_button.tooltip_text = "Delete the saved game (asks first)."
		delete_button.pressed.connect(_ask_delete_save)
		_main_stack.add_child(delete_button)
	_build_quick_play()
	notice = UIFactory.label("", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	notice.add_theme_color_override("font_outline_color", Color(UITheme.NAVY_DEEP, 0.9))
	notice.add_theme_constant_override("outline_size", 6)
	_menu.add_child(notice)

	_stage.resized.connect(_layout_stage)
	_layout_stage()
	(continue_button if has_save else new_game).grab_focus.call_deferred()


## The Quick Play submenu: classic run, demos and direct act starts, with a way back.
func _build_quick_play() -> void:
	var title := UIFactory.label("Quick Play", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_quick_stack.add_child(title)
	var hint := UIFactory.label("Classic runs without the castle. They use their own save and never touch your campaign.", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_quick_stack.add_child(hint)
	var demo_row := GridContainer.new()
	demo_row.columns = 2
	demo_row.add_theme_constant_override("h_separation", 8)
	demo_row.add_theme_constant_override("v_separation", 6)
	demo_row.name = "DemoRow"
	_quick_stack.add_child(demo_row)
	var classic := _small_menu_button("Classic Run", demo_row)
	classic.name = "ClassicRunButton"
	classic.tooltip_text = "The classic run from the Royal Castle through the Forest and the Coast, without the castle hub."
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
	var back := OrnateButton.create("‹ Back", "", false, Vector2(0, 50))
	back.name = "QuickPlayBack"
	back.pressed.connect(_show_quick_play.bind(false))
	_quick_stack.add_child(back)


## Switches the menu panel between the main actions and the Quick Play submenu.
func _show_quick_play(on: bool) -> void:
	_main_stack.visible = not on
	_quick_stack.visible = on
	_layout_stage()
	var focus_target: Control = _quick_stack.find_child("ClassicRunButton", true, false) if on else _main_stack.find_child("QuickPlayButton", true, false)
	if focus_target != null:
		focus_target.grab_focus.call_deferred()


func _divider() -> Control:
	var texture := UIKit.picture("orn_divider")
	if texture == null:
		return UIFactory.label("", &"", false)
	var divider := TextureRect.new()
	divider.texture = texture
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	divider.custom_minimum_size = Vector2(0, 20)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _small_menu_button(text: String, row: Container, icon_id: String = "") -> Button:
	var button := OrnateButton.create(text, icon_id, false, Vector2((BUTTON_WIDTH - 8.0) / 2.0, BUTTON_HEIGHT * SMALL_BUTTON_SHARE))
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	row.add_child(button)
	return button


func _menu_button(text: String, primary: bool, icon_id: String, parent: Container) -> Button:
	var button := OrnateButton.create(text, icon_id, primary, Vector2(BUTTON_WIDTH, BUTTON_HEIGHT))
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON + 3)
	parent.add_child(button)
	return button


static var _glow_texture: GradientTexture2D


## A soft dark radial glow that lets the menu read over the bright sky without a box.
static func _menu_glow() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.04, 0.03, 0.12, 0.62))
		gradient.set_color(1, Color(0.04, 0.03, 0.12, 0.0))
		gradient.add_point(0.62, Color(0.04, 0.03, 0.12, 0.45))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 256
		_glow_texture.height = 256
	return _glow_texture


func _set_icon(button: Button, icon_id: String, width: int) -> void:
	var texture := UIKit.picture(icon_id) if icon_id != "" else null
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", width)


## Logo and menu panel in the open sky on the left; the castle stays visible on the right; Chiara and
## Bianca stand side by side on the terrace in the middle.
func _layout_stage() -> void:
	var area := _stage.size
	var logo_width := clampf(area.x * LOGO_WIDTH_SHARE, LOGO_MIN_WIDTH, LOGO_MAX_WIDTH)
	var logo_aspect := 549.0 / 1230.0
	if _logo.texture != null:
		logo_aspect = _logo.texture.get_height() / float(_logo.texture.get_width())
	var logo_height := logo_width * logo_aspect
	_menu_panel.custom_minimum_size.x = BUTTON_WIDTH + 48.0
	_menu_panel.size = Vector2(_menu_panel.custom_minimum_size.x, _menu_panel.get_combined_minimum_size().y)
	# The menu always fits: the logo gives up height when the menu needs it.
	var room_for_logo := area.y * (1.0 - MENU_BOTTOM_MARGIN_SHARE - 0.05) - _menu_panel.size.y
	if logo_height > room_for_logo:
		logo_height = maxf(room_for_logo, 0.0)
		logo_width = logo_height / logo_aspect
	var column_x := area.x * 0.27
	_logo.size = Vector2(logo_width, logo_height)
	_logo.position = Vector2(column_x - logo_width / 2.0, area.y * 0.01)
	_menu_panel.position = Vector2(clampf(column_x - _menu_panel.size.x / 2.0, 0.0, area.x - _menu_panel.size.x),
		minf(_logo.position.y + logo_height + area.y * 0.02, area.y - _menu_panel.size.y - area.y * MENU_BOTTOM_MARGIN_SHARE))
	for entry in [[_chiara, "chiara", 0], [_bianca, "bianca", 1]]:
		var character_height := area.y * (CHARACTER_HEIGHT_SHARE if entry[2] == 0 else BIANCA_HEIGHT_SHARE)
		var showcase: CharacterShowcase = entry[0]
		var texture := AssetCatalog.figure(entry[1])
		var aspect := texture.get_width() / float(texture.get_height()) if texture != null else 0.8
		var width := character_height * aspect
		showcase.size = Vector2(width, character_height)
		# Both sisters stand side by side on the terrace in the open middle of the picture, between the
		# menu (left) and the castle (right), looking out over the valley.
		var left := area.x * 0.47 + (0.0 if entry[2] == 0 else width * 0.62)
		showcase.position = Vector2(minf(left, area.x - width), area.y - character_height)


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
	continue_button.disabled = _continue_slot() == ""
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
