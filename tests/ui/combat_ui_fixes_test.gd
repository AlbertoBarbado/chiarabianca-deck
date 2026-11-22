extends Node
## Windowed QA of the combat UI fixes: the enemy hover panel never sticks and uses compact text;
## status chips explain themselves; every card's text fits (or the card shows it on hover); potions
## ask who drinks them and highlight the choice; the reward screen fits with an epic note and loot;
## the pile viewer covers the whole battle; Ashveil Bianca is her own sprite with a new cloak.
##   godot --path . res://tests/ui/combat_ui_fixes_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_ui_fixes.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.5)
	await _run()
	get_window().size = Vector2i(1280, 720)
	GameState.delete_save()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(count: int = 3) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _wait(0.2)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _new_run(chiara: String, bianca: String, map_id: String) -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara)
	GameState.select_specialization("bianca", bianca)
	GameState.create_party_from_selection()
	GameState.next_map_id = map_id
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID


func _fight(node_id: String, encounter_id: String) -> Node:
	GameState.room_state = {}
	GameState.map_progress.current_node_id = node_id
	GameState.get_current_node().encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.1)
	var banner := SceneRouter.current_screen.find_child("EliteBanner", true, false)
	if banner != null:
		banner.queue_free()
	return SceneRouter.current_screen


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	_new_run("fire", "ashveil", "enchanted_forest")
	await _test_ashveil_look()
	await _test_hover_panel()
	await _test_status_tooltips()
	await _test_potion_choice()
	await _test_pile_viewer()
	await _test_cards_fit()
	await _test_reward_fits()
	_test_act_heal()


func _test_act_heal() -> void:
	print("Between acts")
	var party := Party.from_selection({"chiara": "fire", "bianca": "tanking"})
	party.get_member("chiara").current_hp = 10
	party.get_member("bianca").current_hp = 0
	GameState.heal_between_acts(party)
	var share := float(RunRules.get_block("acts").get("heal_between_acts", 0.0))
	check(share > 0.0 and party.get_member("chiara").current_hp == 10 + roundi(60 * share), "reaching the next act heals %d%% of max HP" % roundi(share * 100.0))
	check(party.get_member("bianca").is_alive() and party.get_member("bianca").current_hp == roundi(80 * share), "a fallen princess rises with it")


func _test_ashveil_look() -> void:
	print("Ashveil Bianca")
	# Her Ashveil look is the owner-provided pose sheet (assets/characters/bianca/ashveil_bianca.jpg),
	# cut into one sprite per combat state.
	var all_own := true
	var cut_clean := true
	for state in ["idle", "attack", "cast", "block", "hit", "down"]:
		var texture: Texture2D = CombatPresentation.character_state("bianca", state, "ashveil")
		all_own = all_own and texture != null and texture.resource_path.begins_with("res://assets/characters/bianca/ashveil/")
		if texture != null:
			var image := texture.get_image()
			cut_clean = cut_clean and image.get_pixel(1, 1).a < 0.1 and image.get_pixel(image.get_width() - 2, 1).a < 0.1
	check(all_own, "every combat state uses a pose from the Ashveil sheet")
	check(cut_clean, "the poses are cut out (transparent corners)")
	var idle: Texture2D = CombatPresentation.character_state("bianca", "idle", "ashveil")
	check(idle != null and idle.get_height() == CombatPresentation.character_state("bianca", "idle").get_height(), "the Ashveil idle is as tall as her paladin idle (same size in battle)")


func _test_hover_panel() -> void:
	print("Enemy hover panel")
	var screen := await _fight("thorn_maze", "forest_spider_ambush")
	var enemy: Combatant = screen.combat.enemies[1]
	var view: CombatEnemyView = screen._battlefield.enemy_views[enemy.id]
	enemy.add_status("oiled", 2, "bianca")
	screen._refresh()
	var centre := view.get_global_rect().get_center()
	Input.warp_mouse(centre)
	view._set_hover(true)
	await _frames(2)
	check(view.is_detail_visible(), "hovering shows the panel")
	await _shot("ui_01_hover_panel")
	var biggest := 0
	for label in view.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree() and view._detail.is_ancestor_of(label):
			biggest = maxi(biggest, (label as Label).get_theme_font_size("font_size"))
	check(biggest > 0 and biggest <= CombatEnemyView.DETAIL_TITLE_FONT, "compact text (largest %d px)" % biggest)
	var rule := view._detail.find_child("StatusRule_oiled", true, false) as Label
	check(rule != null and rule.text.contains("Fire"), "the panel explains Oiled in full")
	# The pointer leaves without a mouse_exited (crossing chips, re-layout): the panel still closes.
	Input.warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 30))
	await _frames(4)
	check(not view.is_detail_visible(), "moving the pointer away closes it even without mouse_exited")
	view._on_detail_pressed(enemy.id)
	await _frames(4)
	check(not view.is_detail_visible(), "a click-pinned panel closes when the pointer is elsewhere")
	await _test_party_hover_panel(screen)


## Party members open the same panel: name, specialization, HP and every status explained.
func _test_party_hover_panel(screen: Node) -> void:
	print("Party hover panel")
	var chiara: Combatant = screen.combat.party_combatants[0]
	var view: CombatCharacterView = screen._battlefield.party_views[chiara.id]
	check(not view.is_detail_visible(), "a party member's panel is hidden by default")
	chiara.add_status("burn", 2, "")
	chiara.add_status("chill", 1, "")
	screen._refresh()
	Input.warp_mouse(view.get_global_rect().get_center())
	view._set_hover(true)
	await _frames(2)
	check(view.is_detail_visible(), "hovering Chiara shows her panel")
	var texts: Array[String] = []
	for label in view._detail.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	check(texts.any(func(t: String) -> bool: return t.begins_with("Chiara")), "the panel names her (%s)" % ", ".join(texts))
	check(view._detail.find_child("StatusRule_burn", true, false) != null and view._detail.find_child("StatusRule_chill", true, false) != null, "the panel explains each of her statuses")
	var rect: Rect2 = view._detail.get_global_rect()
	check(rect.position.x >= 0.0 and rect.end.x <= get_viewport().get_visible_rect().size.x, "the panel stays on screen")
	await _shot("ui_01b_party_hover_panel")
	Input.warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 30))
	await _frames(4)
	check(not view.is_detail_visible(), "moving away closes her panel")
	chiara.statuses.clear()
	screen._refresh()


func _test_status_tooltips() -> void:
	print("Status chips")
	var screen: Node = SceneRouter.current_screen
	var enemy: Combatant = screen.combat.enemies[1]
	var view: CombatEnemyView = screen._battlefield.enemy_views[enemy.id]
	var chip := view.find_child("Status_oiled", true, false) as Control
	check(chip != null and chip.mouse_filter != Control.MOUSE_FILTER_IGNORE and chip.tooltip_text.contains("Oiled") and chip.tooltip_text.contains("Fire"), "the Oiled chip explains itself on hover")
	var bianca_view: CombatCharacterView = screen._battlefield.party_views["bianca"]
	screen.combat.party_combatants[1].add_status("burn", 1, enemy.id)
	screen._refresh()
	await _frames(2)
	var burn_chip := bianca_view.find_child("Status_burn", true, false) as Control
	check(burn_chip != null and burn_chip.tooltip_text.contains("damage"), "party status chips explain themselves too")


func _test_potion_choice() -> void:
	print("Potion target")
	var screen: Node = SceneRouter.current_screen
	var cm: CombatManager = screen.combat
	GameState.inventory.add_item("minor_health_potion", 1)
	cm.party_combatants[0].hp = 30
	cm.party_combatants[1].hp = 40
	screen._refresh()
	await _frames(2)
	var button := screen.find_child("Potion_minor_health_potion", true, false) as Button
	check(button != null, "the potion button is shown")
	if button == null:
		return
	button.pressed.emit()
	await _frames(2)
	var chiara_view: CombatUnitView = screen._battlefield.party_views["chiara"]
	var bianca_view: CombatUnitView = screen._battlefield.party_views["bianca"]
	var enemy_view: CombatUnitView = screen._battlefield.enemy_views.values()[0]
	check(chiara_view.is_targetable() and bianca_view.is_targetable() and not enemy_view.is_targetable(), "arming the potion makes both princesses choosable (enemies are not)")
	bianca_view._set_pointer_over(true)
	await _frames(2)
	check(bianca_view.is_target_hovered() and not chiara_view.is_target_hovered(), "the ally under the pointer is the highlighted choice")
	await _shot("ui_02_potion_choice")
	screen._on_unit_pressed("bianca")
	await _frames(2)
	check(cm.party_combatants[1].hp > 40 and cm.party_combatants[0].hp == 30, "Bianca drinks it (Chiara, more wounded, is not chosen for her)")
	check(not bianca_view.is_targetable(), "the choice ends after drinking")
	bianca_view._set_pointer_over(false)


func _test_pile_viewer() -> void:
	print("Pile viewer")
	var screen: Node = SceneRouter.current_screen
	screen._open_pile("draw")
	await _frames(3)
	var viewer := screen.get_node_or_null("PileViewer") as Control
	check(viewer != null and viewer.z_index >= 200, "the viewer is above every unit, chip and panel")
	check(not screen._battlefield.visible, "the battle is hidden while the pile is open")
	await _frames(4)
	var cut: Array[String] = []
	for view: CardView in viewer.find_children("*", "CardView", true, false):
		if view.text_clipped:
			cut.append(view.definition.id)
	check(cut.is_empty(), "every card in the pile shows its full name and text (%s)" % ", ".join(cut))
	await _shot("ui_03_pile_viewer")
	viewer.queue_free()
	await _frames(3)
	check(screen._battlefield.visible, "closing it brings the battle back")


func _test_cards_fit() -> void:
	print("Card text")
	var holder := HBoxContainer.new()
	SceneRouter.current_screen.add_child(holder)
	var clipped: Array[String] = []
	var views: Array[CardView] = []
	for card_id: String in DataRegistry.cards:
		var def: CardDef = DataRegistry.cards[card_id]
		for level in [0, 1] if not def.upgrade.is_empty() else [0]:
			var view := CardView.new()
			holder.add_child(view)
			view.show_owned(def, def.owner_character_id, level)
			views.append(view)
	await _frames(6)
	for view in views:
		if view.text_clipped:
			var name_label := view.find_child("CardName", true, false) as Label
			var text_label := view.find_child("CardText", true, false) as Label
			var font := name_label.get_theme_font("font")
			clipped.append("%s [name %s %.0f/%.0f px @%d, text box %.0fx%.0f @%d]" % [view.definition.id, name_label.text,
				font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x,
				name_label.size.x, name_label.get_theme_font_size("font_size"), text_label.size.x, text_label.size.y, text_label.get_theme_font_size("font_size")])
	check(clipped.is_empty(), "every card and upgrade fits its text on the card (%d cards; clipped: %s)" % [views.size(), ", ".join(clipped)])
	holder.queue_free()


func _test_reward_fits() -> void:
	print("Reward screen")
	_new_run("fire", "ashveil", "sunlit_coast")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	GameState.pending_reward = CardReward.generate(GameState.party, rng, 3, DataRegistry.get_encounter("boss_sandstorm_elemental")["reward"])
	GameState.room_state = {"loot": ["starlit_rod"]}
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1080), Vector2i(1920, 1080), Vector2i(844, 390)]:
		get_window().size = window_size
		SceneRouter.go(SceneRouter.Screen.REWARD)
		await _wait(0.5)
		var screen: Node = SceneRouter.current_screen
		var area: Rect2 = screen.get_viewport_rect()
		var all_in := true
		for button: Button in screen.find_children("*", "Button", true, false):
			if button.is_visible_in_tree():
				all_in = all_in and area.grow(0.5).encloses(button.get_global_rect())
		check(all_in, "%dx%d: every reward button is fully on screen (epic note + loot)" % [window_size.x, window_size.y])
		if not all_in:
			for button: Button in screen.find_children("*", "Button", true, false):
				if button.is_visible_in_tree() and not area.grow(0.5).encloses(button.get_global_rect()):
					print("    off screen: %s %s (area %s)" % [button.text, str(button.get_global_rect()), str(area)])
		await _shot("ui_04_reward_%dx%d" % [window_size.x, window_size.y])
	get_window().size = Vector2i(1280, 720)
