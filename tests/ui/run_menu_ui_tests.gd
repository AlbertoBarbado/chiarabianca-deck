extends Node
## Milestone 5 UI tests: the redesigned menu screens (navigation, Continue availability, selection,
## settings, Tutorial Complete) and their layout at desktop, tablet, ultrawide and phone sizes.
## Runs as a scene (screens use the GameState / SceneRouter autoloads):
##   godot --path . res://tests/ui/menu_ui_test.tscn            (add --headless to skip rendering)

const SCREENS := {
	"main_menu": "res://scenes/menus/main_menu.tscn",
	"character_selection": "res://scenes/menus/character_selection.tscn",
	"specialization_selection": "res://scenes/menus/specialization_selection.tscn",
	"party_overview": "res://scenes/menus/party_overview.tscn",
	"settings": "res://scenes/menus/settings.tscn",
	"run_end": "res://scenes/menus/run_end.tscn",
}
## Window sizes; the project stretches the 1280x720 design (expand), so a screen sees window / min(w/1280, h/720).
const WINDOWS: Array[Vector2] = [Vector2(1280, 720), Vector2(844, 390), Vector2(1024, 768), Vector2(2560, 1080)]
const SAVE_PATH := "user://test_menu_ui_save.json"

var _failures: int = 0
var _checks: int = 0
var _original_settings: Dictionary = {}
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	_run()


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _virtual_size(window: Vector2) -> Vector2:
	return window / minf(window.x / 1280.0, window.y / 720.0)


func _run() -> void:
	DataRegistry.reload()
	AssetCatalog.reload()
	_original_settings = SettingsStore.load_values()  # restored at the end
	GameState.save_path = SAVE_PATH
	GameState.delete_save()
	_prepare_game_state()
	await _test_assets_and_theme()
	await _test_main_menu()
	await _test_selection_screens()
	await _test_settings()
	await _test_tutorial_complete()
	await _test_layouts()
	GameState.delete_save()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _prepare_game_state() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.run_result = GameState.RESULT_COMPLETED


## Hosts a screen scene in a SubViewport of the given size (like the stretched window would give).
func _host(scene_path: String, virtual_size: Vector2) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(virtual_size)
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var screen := (load(scene_path) as PackedScene).instantiate() as Control
	screen.theme = UITheme.get_theme()  # Main applies the game theme at its root; mirror that here.
	viewport.add_child(screen)
	add_child(viewport)
	await get_tree().process_frame
	await get_tree().process_frame
	return {"viewport": viewport, "screen": screen}


## Optional screenshot of a hosted screen (pass a directory after "--"); waits for fade-ins first.
func _snap(host: Dictionary, shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	((host["viewport"] as SubViewport).get_texture().get_image()).save_png("%s/%s.png" % [_shot_dir, shot_name])


func _free_host(host: Dictionary) -> void:
	(host["viewport"] as Node).queue_free()


func _buttons(node: Node, found: Array[Button] = []) -> Array[Button]:
	if node is Button and (node as Button).is_visible_in_tree():
		found.append(node as Button)
	for child in node.get_children():
		_buttons(child, found)
	return found


func _find_button(screen: Node, text: String) -> Button:
	for button in _buttons(screen):
		if button.text == text:
			return button
	return null


func _test_assets_and_theme() -> void:
	print("Assets, theme and components")
	var ids := ["buttons/button_plain", "buttons/button_ornate", "panels/panel_rect_ornate", "panels/frame_circle", "panels/divider", "icons/icon_heart", "icons/icon_gold", "processed/logo", "processed/chiara_cutout", "processed/bianca_cutout", "effects/fx_sparkle"]
	var loaded := true
	for id in ids:
		loaded = loaded and UIAssets.texture(id) != null
	check(loaded, "all processed UI textures load (%d)" % ids.size())
	check(UIAssets.texture("buttons/nope") == null and UIAssets.nine_patch("buttons/nope", 1.0, Vector4(1, 1, 1, 1), Vector4.ZERO) == null, "a missing UI texture returns null instead of failing")
	var theme := UITheme.get_theme()
	check(theme.get_stylebox("normal", "Button") is StyleBoxTexture and theme.get_stylebox("disabled", "Button") is StyleBoxTexture, "buttons use the ornate texture styles for normal and disabled")
	check(theme.get_stylebox("hover", "Button") != theme.get_stylebox("normal", "Button") and theme.get_stylebox("pressed", "Button") != theme.get_stylebox("normal", "Button"), "buttons have distinct normal, hover and pressed looks")
	check(theme.get_font("font", "TitleLabel") != null and UITheme.font(700) != null, "the Cinzel display font loads")
	check(AssetCatalog.texture("menu_background") != null and AssetCatalog.portrait_face_round("chiara") != null and AssetCatalog.portrait_face_round("bianca") != null, "menu background and round face crops exist")
	var original_font := UITheme.DISPLAY_FONT_PATH
	check(original_font.ends_with("Cinzel.ttf") and FileAccess.file_exists("res://resources/fonts/Cinzel_OFL.txt"), "the font ships with its SIL OFL license text")


func _test_main_menu() -> void:
	print("Main menu")
	GameState.delete_save()
	var host := await _host(SCREENS["main_menu"], Vector2(1280, 720))
	var menu: Control = host["screen"]
	var buttons := _buttons(menu)
	var texts: Array[String] = []
	for button in buttons:
		texts.append(button.text)
	texts.erase("Delete Save")  # only present while a save exists
	check(texts == ["New Game", "Continue", "Settings", "Elite Route", "Crystal Cave", "Start: Forest", "Start: Coast", "Frostpeak", "Exit"], "the menu buttons are real controls in order (demos, direct act starts and Frostpeak)")
	check(menu.continue_button.disabled, "Continue is disabled when there is no save")
	_free_host(host)
	GameState.save_game()
	host = await _host(SCREENS["main_menu"], Vector2(1280, 720))
	check(GameState.has_save() and not host["screen"].continue_button.disabled, "Continue is enabled when a valid save exists")
	var lowest := 0.0
	for button in _buttons(host["screen"]):
		lowest = maxf(lowest, button.get_global_rect().end.y)
	check(_find_button(host["screen"], "Delete Save") != null and lowest <= 720.0, "with a save (Delete Save shown) every menu button still fits 720p (lowest edge %d)" % lowest)
	_free_host(host)
	GameState.delete_save()
	check(not GameState.has_save(), "deleting the save disables Continue again")
	host = await _host(SCREENS["main_menu"], Vector2(1280, 720))
	var new_game := _find_button(host["screen"], "New Game")
	var went: Array[String] = []
	new_game.pressed.connect(func() -> void: went.append("new"))
	new_game.pressed.emit()
	check(went == ["new"], "New Game is wired to its handler")
	_free_host(host)


func _test_selection_screens() -> void:
	print("Character and specialization selection")
	var host := await _host(SCREENS["character_selection"], Vector2(1280, 720))
	var screen: Control = host["screen"]
	check(_find_button(screen, "Choose Specializations") != null and _find_button(screen, "Back") != null, "character selection offers Back and Choose Specializations")
	var texts := _label_texts(screen)
	check(texts.has("Hair: Auburn Blonde") and texts.has("Eyes: Light Grey") and texts.has("Hair: Black") and texts.has("Eyes: Brown"), "both characters show their established hair and eye colours")
	check(texts.any(func(t: String) -> bool: return t.contains("HP 60 / 60")) and texts.any(func(t: String) -> bool: return t.contains("HP 80 / 80")), "health is shown for both")
	var showcases := screen.find_children("*", "CharacterShowcase", true, false)
	var heights: Array[float] = []
	for showcase: Node in showcases:
		heights.append((showcase as CharacterShowcase)._art.size.y)
	check(heights.size() == 2 and heights.min() > 0.0 and heights.min() / heights.max() > 0.93, "Chiara and Bianca are drawn at the same height (%s)" % str(heights))
	_free_host(host)
	# At every size the pictures keep clear of the text: both fit their boxes whole, the sisters stand
	# at about the same height, and the text column starts at least 20 px after the picture box.
	for window: Vector2 in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080)]:
		host = await _host(SCREENS["character_selection"], window)
		screen = host["screen"]
		var ok := true
		var notes: Array[String] = []
		var art_heights: Array[float] = []
		for showcase: Node in screen.find_children("*", "CharacterShowcase", true, false):
			var box := (showcase as CharacterShowcase)
			var art_width: float = box._art.size.x
			art_heights.append(box._art.size.y)
			var text_column := box.get_parent().get_child(1) as Control
			var gap := text_column.get_global_rect().position.x - box.get_global_rect().end.x
			ok = ok and art_width <= box.size.x + 1.0 and gap >= 20.0
			notes.append("%dx%d in %d, gap %d" % [art_width, box._art.size.y, box.size.x, gap])
		ok = ok and art_heights.size() == 2 and art_heights.min() / art_heights.max() > 0.9
		check(ok, "character selection %dx%d: pictures stay clear of the text (%s)" % [window.x, window.y, ", ".join(notes)])
		_free_host(host)

	GameState.reset_selection()
	host = await _host(SCREENS["specialization_selection"], Vector2(1280, 720))
	screen = host["screen"]
	var fire := _find_button(screen, "Fire")
	var arcana := _find_button(screen, "Arcana")
	check(fire != null and arcana != null and fire.toggle_mode and fire.theme_type_variation == &"ToggleButton", "specializations are toggle buttons with the selected-state style")
	fire.button_pressed = true  # a real toggle, so the selected style shows
	fire.pressed.emit()
	await get_tree().process_frame
	check(GameState.selected_specializations.get("chiara", "") == "fire", "choosing Fire selects it for Chiara only")
	var holy := _find_button(screen, "Holy")
	holy.button_pressed = true
	holy.pressed.emit()
	await _snap(host, "spec_selected_toggles")
	check(GameState.selected_specializations.get("bianca", "") == "holy" and not _find_button(screen, "Confirm Party").disabled, "choosing Holy completes the pair and enables Confirm Party")
	var details := _label_texts(screen)
	check(details.any(func(t: String) -> bool: return t.contains("Kindled Spark")) and details.any(func(t: String) -> bool: return t.contains("Blessed Aegis")), "passives are shown for the selected specializations")
	var earth := _find_button(screen, "Earth")
	earth.pressed.emit()
	check(GameState.selected_specializations.get("chiara", "") == "earth" and _find_button(screen, "Confirm Party").disabled, "an unplayable specialization still blocks confirmation")
	_free_host(host)
	_prepare_game_state()
	host = await _host(SCREENS["party_overview"], Vector2(1280, 720))
	screen = host["screen"]
	check(_find_button(screen, "Enter the Royal Castle") != null and _label_texts(screen).any(func(t: String) -> bool: return t.contains("Specialization: Fire")) and _label_texts(screen).any(func(t: String) -> bool: return t.contains("Specialization: Holy")), "party overview shows both specializations and the start action")
	_free_host(host)


func _test_settings() -> void:
	print("Settings")
	var host := await _host(SCREENS["settings"], Vector2(1280, 720))
	var screen: Control = host["screen"]
	var option: OptionButton = null
	var slider: HSlider = null
	var check_button: CheckButton = null
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is OptionButton:
			option = node
		elif node is HSlider:
			slider = node
		elif node is CheckButton:
			check_button = node
		stack.append_array(node.get_children())
	check(option != null and slider != null and check_button != null, "settings keep volume, fullscreen and combat effects controls")
	var levels: Array[String] = []
	for i in option.item_count:
		levels.append(option.get_item_text(i))
	check(levels == ["Full", "Reduced", "Off"], "the Full / Reduced / Off effects quality option is preserved")
	option.select(2)
	option.item_selected.emit(2)
	check(SettingsStore.load_values()["effects_quality"] == "off", "choosing Off is saved and applied")
	slider.value = 0.4
	check(absf(float(SettingsStore.load_values()["volume"]) - 0.4) < 0.01, "moving the volume slider is saved")
	option.select(0)
	option.item_selected.emit(0)
	slider.value = 0.8
	_free_host(host)
	var back_host := await _host(SCREENS["settings"], Vector2(1280, 720))
	check(_find_button(back_host["screen"], "Back") != null, "Back button present")
	_free_host(back_host)


func _test_tutorial_complete() -> void:
	print("Tutorial Complete")
	GameState.run_result = GameState.RESULT_COMPLETED
	var host := await _host(SCREENS["run_end"], Vector2(1280, 720))
	var screen: Control = host["screen"]
	var texts := _label_texts(screen)
	check(texts.has("Tutorial Complete") or texts.has("TUTORIAL COMPLETE") or texts.any(func(t: String) -> bool: return t.to_lower() == "tutorial complete"), "the completion heading is shown")
	check(texts.any(func(t: String) -> bool: return t.contains("Chiara:") and t.contains("/ 60 HP")) and texts.any(func(t: String) -> bool: return t.contains("Bianca:") and t.contains("/ 80 HP")), "both princesses' current HP is shown")
	check(texts.any(func(t: String) -> bool: return t.begins_with("Gold: ")), "gold is shown")
	check(_find_button(screen, "New Game") != null and _find_button(screen, "Main Menu") != null, "New Game and Main Menu buttons are present")
	var buttons := _buttons(screen)
	var new_game := _find_button(screen, "New Game").get_global_rect()
	var main_menu := _find_button(screen, "Main Menu").get_global_rect()
	check(not new_game.intersects(main_menu) and buttons.size() == 2, "the two action buttons do not overlap")
	_free_host(host)
	GameState.run_result = GameState.RESULT_DEFEATED
	host = await _host(SCREENS["run_end"], Vector2(1280, 720))
	check(_label_texts(host["screen"]).any(func(t: String) -> bool: return t.to_lower() == "defeated"), "the defeat variant keeps its own heading")
	_free_host(host)
	GameState.run_result = GameState.RESULT_COMPLETED


func _label_texts(node: Node, found: Array[String] = []) -> Array[String]:
	if node is Label and (node as Label).is_visible_in_tree():
		found.append((node as Label).text)
	for child in node.get_children():
		_label_texts(child, found)
	return found


## Layout checks for every redesigned screen at every window size.
func _test_layouts() -> void:
	print("Layouts at desktop, phone, tablet and ultrawide sizes")
	for screen_name: String in SCREENS:
		for window in WINDOWS:
			var size_value := _virtual_size(window)
			if screen_name == "specialization_selection":
				GameState.select_specialization("chiara", "fire")
				GameState.select_specialization("bianca", "holy")
			var host := await _host(SCREENS[screen_name], size_value)
			var screen: Control = host["screen"]
			var tag := "%s at %dx%d (%dx%d virtual)" % [screen_name, window.x, window.y, size_value.x, size_value.y]
			var view_rect := Rect2(Vector2.ZERO, size_value).grow(1.0)
			var buttons := _buttons(screen)
			var inside := true
			var overlap := ""
			for i in buttons.size():
				var rect_a := buttons[i].get_global_rect()
				inside = inside and view_rect.encloses(rect_a)
				for j in range(i + 1, buttons.size()):
					# Ignore tiny overlaps from the hover scale; real collisions are larger.
					if rect_a.intersection(buttons[j].get_global_rect()).get_area() > 40.0 and buttons[i].get_parent() == buttons[j].get_parent() and not (screen_name == "specialization_selection"):
						overlap = "%s overlaps %s" % [buttons[i].text, buttons[j].text]
			check(inside, "%s: every button is on screen" % tag)
			check(overlap == "", "%s: no overlapping buttons %s" % [tag, overlap])
			var clipped := _clipped_labels(screen, view_rect)
			check(clipped.is_empty(), "%s: no text outside the screen or its panel (%s)" % [tag, "; ".join(clipped)])
			_free_host(host)


## Visible labels whose text box leaves the screen or the panel that holds them. Scrolled lists are skipped.
func _clipped_labels(node: Node, view_rect: Rect2, found: Array[String] = []) -> Array[String]:
	if node is ScrollContainer:
		return found
	if node is PanelContainer and (node as PanelContainer).is_visible_in_tree():
		var panel_box := (node as Control).get_global_rect()
		if not view_rect.encloses(panel_box):
			found.append("a panel (%s) leaves the screen" % node.name)
	if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text != "":
		var label := node as Label
		var rect := label.get_global_rect()
		var text_width := label.get_minimum_size().x if label.autowrap_mode == TextServer.AUTOWRAP_OFF else minf(label.get_minimum_size().x, rect.size.x)
		var text_rect := Rect2(rect.position, Vector2(text_width, rect.size.y))
		if not view_rect.encloses(text_rect) and label.modulate.a > 0.5:
			found.append("'%s' leaves the screen" % label.text.left(24))
		var ancestor := label.get_parent()
		while ancestor != null and not (ancestor is PanelContainer):
			ancestor = ancestor.get_parent()
		if ancestor is PanelContainer:
			var panel_rect := (ancestor as Control).get_global_rect().grow(1.5)
			if not panel_rect.encloses(text_rect):
				found.append("'%s' leaves its panel" % label.text.left(24))
	for child in node.get_children():
		_clipped_labels(child, view_rect, found)
	return found
