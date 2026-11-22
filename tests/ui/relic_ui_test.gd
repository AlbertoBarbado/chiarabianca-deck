extends Node
## Windowed: relics on screen. The relic bar in battle (icons, tooltips, a pop when a relic fires),
## the "Relic found" strip after an elite and the boss relic choice after a boss.
##   godot --path . res://tests/ui/relic_ui_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_relic_ui.json"
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


func _start_run() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "wind")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	# 1. The relic bar in battle.
	_start_run()
	for relic_id in ["mercury_bell", "sisters_locket", "ley_crystal", "chime_of_echoes", "royal_pear"]:
		RelicEffects.gain(relic_id, GameState.party, GameState.inventory)
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "bone_clearing"
	GameState.get_current_node().encounter_id = "forest_bone_clearing"
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.6)
	var bar := _find("RelicBar") as Control
	check(bar != null and bar.get_child_count() == 5 and bar.is_visible_in_tree(), "the battle shows a relic bar with the 5 relics")
	var bell := bar.get_node_or_null("RelicIcon_mercury_bell") as RelicIcon if bar != null else null
	check(bell != null and bell.texture != null and bell.tooltip_text.contains("Mercury Bell") and bell.tooltip_text.contains("damage"), "each relic shows its picture, name and effect on hover")
	var screen := SceneRouter.current_screen
	var chime := bar.get_node_or_null("RelicIcon_chime_of_echoes") as RelicIcon
	screen.combat.energy = 10
	for i in 4:
		var def := DataRegistry.get_card("chiara_wind_gust")
		var card := CardInstance.new()
		card.definition = def
		card.owner_character_id = "chiara"
		screen.combat.deck.hand.append(card)
		screen.combat.play_card(card, screen.combat.get_living_enemies()[0].id)
	# The peak of the pop over the next frames (playing 4 cards at once can stall the first frame).
	var peak := 0.0
	for f in 12:
		await get_tree().process_frame
		peak = maxf(peak, chime.scale.x if chime != null else 0.0)
	check(chime != null and peak > 1.05, "Chime of Echoes pops when the 4th card fires it (peak scale %.2f)" % peak)
	await _shot("relic_01_bar")
	await _wait(0.6)

	# 2. An elite leaves a relic on the reward screen.
	var node := GameState.get_current_node()
	GameState.room_state = {"node_id": node.id, "kind": node.type}
	GameState.pending_reward = null
	GameState.record_combat_victory(20, {"id": "qa_elite", "elite": true, "enemies": []})
	SceneRouter.go(SceneRouter.Screen.REWARD)
	await _wait(0.8)
	var strip := _find("RelicStrip")
	check(strip != null and strip.is_visible_in_tree(), "the reward screen shows the relic the elite left (%s)" % ", ".join(GameState.room_state.get("relics", [])))
	await _shot("relic_02_elite_reward")

	# 3. A boss offers a choice of 3 boss relics.
	GameState.room_state = {"node_id": node.id, "kind": node.type}
	GameState.pending_reward = null
	GameState.record_combat_victory(20, {"id": "qa_boss", "boss": true, "enemies": []})
	SceneRouter.go(SceneRouter.Screen.REWARD)
	await _wait(0.8)
	var choice := _find("BossRelicChoice")
	var choices: Array = GameState.room_state.get("relic_choices", [])
	check(choice != null and choices.size() == 3, "the reward screen offers 3 boss relics")
	await _shot("relic_03_boss_choice")
	var owned := GameState.inventory.relics.size()
	var reward_screen := SceneRouter.current_screen
	check(reward_screen.take_boss_relic_option(str(choices[0])), "tapping a boss relic takes it")
	await _wait(0.3)
	check(not reward_screen.take_boss_relic_option(str(choices[1])) and GameState.inventory.relics.size() == owned + 1, "the other boss relics can no longer be taken")
	var second := _find("BossRelic_" + str(choices[1])) as Control
	check(second == null or second != null and second.modulate.a < 0.6, "the relics not taken are dimmed (or the page moved on)")
	await _wait(0.8)
	check(_find("BossRelicChoice") == null and _find("RewardHeading") != null and _find("RewardFooter") != null and (_find("RewardFooter") as Control).get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "after the relic the card reward follows, with its buttons on screen")
	await _shot("relic_05_cards_after_relic")
	await _shot("relic_04_boss_taken")
