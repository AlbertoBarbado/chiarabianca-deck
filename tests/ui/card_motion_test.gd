extends Node
## Windowed QA of the hand's motion: the fan (rotation per card), the hover pop (straight and
## enlarged), the draw from the deck, a played card rising and sweeping to the discard pile, an
## exhausted card burning away, and the end-of-turn discard. Mid-animation screenshots for review;
## checks that every leaving card is freed and the hand stays in sync with the deck.
##   godot --path . res://tests/ui/card_motion_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_card_motion.json"
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


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "ashveil")
	GameState.create_party_from_selection()
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "thorn_maze"
	GameState.get_current_node().encounter_id = "forest_spider_ambush"
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(0.12)
	await _shot("motion_01_drawing")
	await _wait(1.2)
	var screen: Node = SceneRouter.current_screen
	var hand: CombatHand = screen._hand
	var cm: CombatManager = screen.combat
	await _shot("motion_02_hand")
	var count := hand.card_count()
	var rotations: Array[float] = []
	for card in cm.deck.hand:
		rotations.append(hand.get_view(card).rotation)
	check(count == cm.deck.hand.size() and count >= 3, "the hand shows the %d drawn cards" % count)
	check(rotations[0] < 0.0 and rotations[rotations.size() - 1] > 0.0, "the hand fans out (left cards turn left, right cards right)")

	# Hover pop.
	var middle: CardInstance = cm.deck.hand[count / 2]
	hand.set_hovered(middle)
	await _wait(0.3)
	var view := hand.get_view(middle)
	check(is_zero_approx(view.rotation) and view.scale.x > hand.base_scale() * 1.15, "the hovered card stands straight and enlarged")
	await _shot("motion_03_hover")
	hand.set_hovered(null)

	# Select an attack (gold glow), then play it on an enemy and catch it mid-flight.
	var attack: CardInstance = null
	for card in cm.deck.hand:
		if card.definition.target == CardDef.TARGET_SINGLE_ENEMY and cm.can_play(card) == "":
			attack = card
			break
	if attack != null:
		screen._on_card_pressed(attack)
		await _wait(0.25)
		var selected_view := hand.get_view(attack)
		var others := cm.deck.hand.filter(func(c: CardInstance) -> bool: return c != attack)
		check(selected_view._selected and selected_view.position.y < hand.get_view(others[0]).position.y - 20.0, "the card waiting for a target is raised with a gold glow")
		await _shot("motion_04_selected")
		screen._on_unit_pressed(cm.enemies[0].id)
		await _wait(0.17)
		await _shot("motion_05_played")
		var flying := hand.get_children().filter(func(c: Node) -> bool: return c is CardView and (c as CardView).z_index == 200)
		check(flying.size() == 1, "the played card is in flight above the hand")
		await _wait(0.6)
		check(hand.get_children().filter(func(c: Node) -> bool: return c is CardView).size() == cm.deck.hand.size(), "the played card is gone once it reaches the discard pile")

	# An exhausting card burns away.
	var exhaust := CardInstance.new()
	exhaust.definition = DataRegistry.get_card("chiara_fire_epic_heart")
	exhaust.owner_character_id = "chiara"
	exhaust.owned_uid = "test_exhaust"
	cm.deck.hand.append(exhaust)
	cm.energy = 9
	screen._refresh()
	await _wait(0.5)
	screen._on_card_pressed(exhaust)
	await _wait(0.42)
	await _shot("motion_06_exhaust")
	var burning := hand.get_children().filter(func(c: Node) -> bool: return c is CardView and (c as CardView).definition == exhaust.definition)
	check(not burning.is_empty() and float((burning[0] as CardView).get_node("Face/Frame").material.get_shader_parameter("dissolve")) > 0.0, "an exhausted card burns away (dissolve)")
	await _wait(0.6)

	# End of turn: the hand sweeps to the discard pile.
	var before := hand.get_children().filter(func(c: Node) -> bool: return c is CardView).size()
	screen._on_end_turn()
	await _wait(0.12)
	await _shot("motion_07_discard")
	var waiting := hand.get_children().filter(func(c: Node) -> bool: return c is CardView and c.has_meta("drawing") and is_zero_approx((c as CardView).modulate.a))
	check(screen._animations.is_enemy_phase() and waiting.size() == cm.deck.hand.size(), "the next hand waits at the deck while the enemies act (%d cards)" % waiting.size())
	await _wait(2.5)
	var after := hand.get_children().filter(func(c: Node) -> bool: return c is CardView).size()
	check(before > 0 and after == cm.deck.hand.size(), "after the enemy turn the hand holds exactly the newly drawn cards (%d)" % after)
