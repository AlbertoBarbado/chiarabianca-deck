extends Node
## Windowed: twin combos on screen. The selection screen's combo guide and pair banner, Wind's Gusts
## and Momentum counter, the Miasma and Combustion reactions (pop-ups and effects), and a Blight
## execution.
##   godot --path . res://tests/ui/twin_combo_ui_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_twin_combo_ui.json"
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
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _find(node_name: String) -> Node:
	return SceneRouter.current_screen.find_child(node_name, true, false)


func _start(chiara: String, bianca: String) -> Node:
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara)
	GameState.select_specialization("bianca", bianca)
	GameState.create_party_from_selection()
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "bone_clearing"
	GameState.get_current_node().encounter_id = "forest_bone_clearing"
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.6)
	var screen := SceneRouter.current_screen
	for enemy: Combatant in screen.combat.enemies:
		enemy.max_hp = 400
		enemy.hp = 400
	screen._refresh()
	return screen


func _give(screen: Node, card_id: String) -> CardInstance:
	var def := DataRegistry.get_card(card_id)
	var card := CardInstance.new()
	card.definition = def
	card.owner_character_id = def.owner_character_id
	card.owned_uid = "twin_" + card_id
	screen.combat.deck.hand.append(card)
	screen.combat.energy = 9
	screen._refresh()
	return card


func _play(screen: Node, card: CardInstance, target_id: String = "") -> void:
	if card.definition.target == CardDef.TARGET_SINGLE_ENEMY:
		screen._selected_card = card
		screen._play_selected(target_id if target_id != "" else screen.combat.get_living_enemies()[0].id)
	else:
		screen._on_card_pressed(card)
	await _wait(0.35)


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	# 1. The combo guide on the selection screen.
	GameState.reset_selection()
	SceneRouter.go(SceneRouter.Screen.SPECIALIZATION_SELECTION)
	await _wait(0.5)
	var screen := SceneRouter.current_screen
	screen._on_spec_chosen("chiara", "wind")
	screen._on_spec_chosen("bianca", "venom")
	await _wait(0.3)
	var banner := _find("ComboBanner") as Label
	check(banner != null and banner.text.contains("Miasma") and banner.text.contains("★★★"), "the footer names the chosen pair's combo (%s)" % (banner.text.left(40) if banner != null else "none"))
	check(_find("Combo_wind_venom") != null and _find("Combo_wind_tanking") != null, "each specialization lists its combos with the other princess")
	check(_find("Combo_wind_venom") != null and (_find("Combo_wind_venom") as Label).is_visible_in_tree(), "the Wind panel shows Wind + Venom")
	await _shot("twin_00_selection")
	screen._on_spec_chosen("chiara", "fire")
	await _wait(0.2)
	check(banner.text.contains("Combustion"), "switching to Fire shows Combustion")

	# 2. Wind + Venom: Gusts, Momentum and Miasma.
	screen = await _start("wind", "venom")
	var box := _find("MomentumBox") as Control
	var label := _find("MomentumLabel") as Label
	check(box != null and box.is_visible_in_tree() and label.text == "0", "a Wind party shows the Momentum counter (0)")
	var foe: Combatant = screen.combat.get_living_enemies()[0]
	foe.add_status("poison", 6, "bianca")
	await _play(screen, _give(screen, "chiara_wind_flurry"))
	var gusts: Array = screen.combat.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.id == "chiara_wind_gust")
	check(gusts.size() == 2 and label.text == "1", "Flurry puts 2 Gusts in the hand; Momentum 1")
	var gust_view: CardView = null
	for view: Node in screen.find_children("*", "CardView", true, false):
		if (view as CardView).card != null and (view as CardView).card.definition.id == "chiara_wind_gust":
			gust_view = view
	check(gust_view != null and gust_view.is_visible_in_tree(), "Gusts are drawn as cards in the hand")
	await _shot("twin_01_gusts")
	var spawned: Array[String] = []
	var vfx: CombatVfxManager = screen._vfx
	vfx.effect_spawned.connect(func(effect_id: String, _node: CombatVfx) -> void: spawned.append(effect_id))
	var popups_before: int = screen.reaction_popups
	await _play(screen, gusts[0], foe.id)
	await _shot("twin_02_miasma")
	check(spawned.has("miasma") and screen.reaction_popups > popups_before, "a Gust on a Poisoned foe sets off Miasma: effect and pop-up (%s)" % ", ".join(spawned))
	var others: Array = screen.combat.get_living_enemies().filter(func(e: Combatant) -> bool: return e != foe)
	check(others.is_empty() or others.all(func(e: Combatant) -> bool: return e.has_status("poison")), "the Poison spread to the other enemies")
	await _wait(0.5)

	# 3. Fire + Venom: Combustion.
	screen = await _start("fire", "venom")
	spawned.clear()
	vfx = screen._vfx
	vfx.effect_spawned.connect(func(effect_id: String, _node: CombatVfx) -> void: spawned.append(effect_id))
	for enemy: Combatant in screen.combat.get_living_enemies():
		enemy.add_status("poison", 5, "bianca")
	screen._refresh()
	await _wait(0.3)
	await _shot("twin_03_poisoned")
	await _play(screen, _give(screen, "chiara_fire_ember"))
	await _shot("twin_04_combustion")
	check(spawned.has("combustion") and screen.combat.reactions_fired >= 1, "Fire on Poison: Combustion explodes (%s)" % ", ".join(spawned))
	await _wait(0.6)

	# 4. Blight executes a weakened foe at the start of the enemy phase.
	screen = await _start("arcana", "venom")
	spawned.clear()
	vfx = screen._vfx
	vfx.effect_spawned.connect(func(effect_id: String, _node: CombatVfx) -> void: spawned.append(effect_id))
	var victim: Combatant = screen.combat.get_living_enemies()[0]
	victim.hp = 9
	await _play(screen, _give(screen, "bianca_venom_mark"), victim.id)
	await _shot("twin_05_blight")
	check(victim.has_status("blight") and spawned.has("blight_apply"), "Mark of Blight brands the foe (violet mist)")
	check(victim.is_alive(), "Blight waits for the enemy phase")
	var victim_view: Node = screen._battlefield.enemy_views[victim.id]
	var blight_icon := victim_view.find_children("*", "TextureRect", true, false).any(func(t: Node) -> bool:
		return (t as TextureRect).texture != null and (t as TextureRect).texture.resource_path.ends_with("icon_blight.png") and (t as TextureRect).is_visible_in_tree())
	check(blight_icon, "the Blight chip shows the crowned skull icon, not a bare number")
	screen.combat.end_player_turn()
	screen._refresh()
	await _wait(0.4)
	await _shot("twin_06_executed")
	await _wait(0.8)
	check(not victim.is_alive() and spawned.has("blight_execute"), "a foe at 9 HP with 10 Blight perishes when the enemy phase starts (%s)" % ", ".join(spawned))

	# 5. Damage preview: hand numbers follow the weapon bonus, and a selected card follows the enemy
	# under the pointer (a weakness raises it).
	screen = await _start("fire", "tanking")
	var chiara_c: Combatant = screen.combat.get_combatant("chiara")
	chiara_c.damage_bonus = {"fire": 50}
	var ember := _give(screen, "chiara_fire_ember")
	await _wait(0.4)
	var ember_view: CardView = null
	for view: Node in screen.find_children("*", "CardView", true, false):
		if (view as CardView).card == ember:
			ember_view = view
	var ember_text: String = ember_view._text_label.text if ember_view != null else ""
	check(ember_text.contains("]9[") and ember_text.contains(CardTextFormat.BOOSTED_COLOR.to_html(false)), "a +50%% fire weapon shows Ember Bolt as 9 in cyan (%s)" % ember_text)
	var weak_foe: Combatant = screen.combat.get_living_enemies()[0]
	weak_foe.affinity = {"fire": 100}
	screen._selected_card = ember
	screen._battlefield.target_hovered.emit(weak_foe.id)
	await _wait(0.3)
	for view: Node in screen.find_children("*", "CardView", true, false):
		if (view as CardView).card == ember:
			ember_view = view
	ember_text = ember_view._text_label.text
	var alone: bool = screen.combat.get_living_enemies().size() == 1
	check(ember_text.contains("]15[") or alone, "hovering a fire-weak enemy (+100%%) with Ember Bolt selected shows 15 (6 x 250%%) (%s)" % ember_text)
	await _shot("twin_07_damage_preview")
	screen._battlefield.target_hovered.emit("")
	screen._selected_card = null
	screen._refresh()

	# 6. The top-bar counters explain themselves on hover (nothing above them swallows the pointer).
	screen = await _start("wind", "holy")
	screen.combat.aether = 1
	screen._refresh()
	await _wait(0.3)
	for box_name in ["EnergyBox", "MomentumBox", "AetherBox"]:
		var counter := _find(box_name) as Control
		var centre: Vector2 = counter.get_global_rect().get_center() if counter != null else Vector2.ZERO
		var motion := InputEventMouseMotion.new()
		motion.position = centre
		motion.global_position = centre
		get_viewport().push_input(motion)
		await _wait(0.1)
		var hovered := get_viewport().gui_get_hovered_control()
		var hovered_ok: bool = hovered != null and (hovered == counter or counter.is_ancestor_of(hovered)) and hovered.get_tooltip(hovered.get_local_mouse_position()) != ""
		check(counter != null and counter.is_visible_in_tree() and counter.tooltip_text != "" and hovered_ok, "hovering %s shows its explanation (pointer is over %s)" % [box_name, hovered.name if hovered != null else "nothing"])
	# Rest the pointer on the Momentum counter: a tooltip window must really open.
	var momentum_box := _find("MomentumBox") as Control
	var rest := InputEventMouseMotion.new()
	rest.position = momentum_box.get_global_rect().get_center()
	rest.global_position = rest.position
	Input.warp_mouse(rest.position)
	get_viewport().push_input(rest)
	await _wait(1.4)
	var popups: Array[Node] = []
	for node in get_tree().root.find_children("*", "Window", true, false):
		if node is PopupPanel and (node as Window).visible:
			popups.append(node)
	await _shot("twin_08_tooltip")
	check(not popups.is_empty(), "resting on the Momentum counter opens a tooltip (%d open)" % popups.size())
