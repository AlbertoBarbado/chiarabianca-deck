extends Node
## Windowed QA of Bianca's Ashveil and the new castle and forest maps: choosing Ashveil on the
## specialization screen, Ashveil Bianca's own sprite in combat, Oil Flask leaving Oiled (chip and
## dark tint) on an enemy, Chiara's fire igniting the oil, the Ashveil hand, and the illustrated maps.
##   godot --path . res://tests/progression/ashveil_flow_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_ashveil_flow.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.5)
	await _run()
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


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _wait(0.25)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _buttons(node: Node, out: Array[Button] = []) -> Array[Button]:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_buttons(child, out)
	return out


func _button(text: String) -> Button:
	for button in _buttons(SceneRouter.current_screen):
		if button.text == text and button.is_visible_in_tree():
			return button
	return null


func _labels(node: Node, out: Array[String] = []) -> Array[String]:
	if node is Label:
		out.append((node as Label).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	for child in node.get_children():
		_labels(child, out)
	return out


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	# Specialization screen: Ashveil replaces the Duelist and can be chosen.
	GameState.reset_selection()
	SceneRouter.go(SceneRouter.Screen.SPECIALIZATION_SELECTION)
	await _wait(0.6)
	var fire := _button("Fire")
	if fire != null:
		fire.pressed.emit()
	await _wait(0.3)
	var ashveil := _button("Ashveil")
	check(ashveil != null and not ashveil.disabled and _button("Duelist") == null, "the screen offers Ashveil (and no Duelist)")
	if ashveil != null:
		ashveil.pressed.emit()
	await _wait(0.4)
	check(GameState.selected_specializations.get("bianca", "") == "ashveil", "choosing Ashveil selects it for Bianca")
	var text := " ".join(_labels(SceneRouter.current_screen))
	check(text.contains("Slick Tricks") or text.contains("Oiled") or text.contains("oil"), "its passive or Oiled is described")
	await _shot("ash_01_selection")

	# Combat: Ashveil Bianca, Oil Flask, then Chiara's fire on the Oiled foe.
	GameState.create_party_from_selection()
	GameState.next_map_id = "royal_castle_tutorial"
	GameState.begin_adventure()
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "west_training"
	GameState.get_current_node().encounter_id = "castle_training_02"
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.2)
	var screen: Node = SceneRouter.current_screen
	var cm: CombatManager = screen.combat
	var bianca_view: CombatUnitView = screen._battlefield.party_views["bianca"]
	var ashveil_idle := CombatPresentation.character_state("bianca", "idle", "ashveil")
	check(bianca_view._art.texture == ashveil_idle and ashveil_idle != CombatPresentation.character_state("bianca", "idle"), "Bianca fights in her Ashveil gear")
	var flask: CardInstance = null
	for pile: Array[CardInstance] in [cm.deck.hand, cm.deck.draw_pile, cm.deck.discard_pile]:
		for card in pile:
			if card.definition.id == "bianca_ash_flask" and flask == null:
				flask = card
				pile.erase(card)
	cm.deck.hand.append(flask)
	screen._refresh()
	await _wait(0.4)
	await _shot("ash_02_combat_hand")
	var target := cm.enemies[0]
	var target_view: CombatUnitView = screen._battlefield.enemy_views[target.id]
	cm.energy = 9
	check(cm.play_card(flask, target.id), "Oil Flask plays")
	screen._refresh()
	await _wait(0.5)
	check(target.has_status("oiled") and target_view.status_count("oiled") == 2, "the enemy shows 2 Oiled on its chip")
	await _shot("ash_03_oiled")
	var ember: CardInstance = null
	for pile: Array[CardInstance] in [cm.deck.hand, cm.deck.draw_pile, cm.deck.discard_pile]:
		for card in pile:
			if card.definition.id == "chiara_fire_ember" and ember == null:
				ember = card
				pile.erase(card)
	cm.deck.hand.append(ember)
	var events: Array[String] = []
	cm.visual_event.connect(func(e: Dictionary) -> void: events.append("%s/%s" % [e.get("kind", ""), e.get("status_id", "")]))
	var hp := target.hp
	check(cm.play_card(ember, target.id) and hp - target.hp > 6, "Ember Bolt on the Oiled foe hits harder than 6 (%d)" % (hp - target.hp))
	check(events.has("status_exploit/oiled"), "the oil bursts into flame (status_exploit)")
	screen._refresh()
	await _wait(0.15)
	await _shot("ash_04_ignite")

	# Equipment screen shows the Ashveil look too.
	SceneRouter.open_equipment(SceneRouter.Screen.MAP)
	await _wait(0.6)
	await _shot("ash_05_equipment")

	# The illustrated maps.
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.8)
	var view: MapView = SceneRouter.current_screen._map_view
	check(view.has_background() and view.get_layout().background_asset == "map_royal_castle", "the castle uses its illustrated map")
	await _shot("ash_06_castle_map")
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.8)
	view = SceneRouter.current_screen._map_view
	check(view.has_background() and view.get_layout().background_asset == "map_enchanted_forest", "the forest uses its illustrated map")
	await _shot("ash_07_forest_map")
