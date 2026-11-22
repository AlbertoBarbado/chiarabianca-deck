extends Node
## Windowed: the Royal Castle's last fight (Throne Hall Guards) opens with the elite-style
## introduction ("Final Battle", led by the Hall Captain), and the Hall Captain stands with his sword.
##   godot --path . res://tests/ui/final_battle_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_final_battle.json"
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
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "throne_approach"
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.2)
	var screen := SceneRouter.current_screen
	check(screen.combat.encounter_name == "Throne Hall Guards", "the castle's last fight is the Throne Hall Guards")
	var banner := screen.find_child("EliteBanner", true, false)
	var texts: Array[String] = []
	if banner != null:
		for label in banner.find_children("*", "Label", true, false):
			texts.append((label as Label).text)
	check(banner != null and " ".join(texts).contains("FINAL BATTLE"), "it opens with the introduction, kicker 'Final Battle' (%s)" % " | ".join(texts))
	var tag := screen.find_child("EliteTag", true, false) as Label
	check(tag != null and tag.text == "FINAL BATTLE", "the header tags it as the final battle")
	await _shot("final_01_intro")
	await _wait(5.0)
	var captain_view: CombatUnitView = null
	for unit_id: String in screen._battlefield.enemy_views:
		if unit_id.begins_with("hall_captain"):
			captain_view = screen._battlefield.enemy_views[unit_id]
	var texture: Texture2D = captain_view._art.texture if captain_view != null else null
	check(texture != null and texture.resource_path.ends_with("knight_captain_idle_sword.png"), "the Hall Captain stands with his sword (%s)" % (texture.resource_path if texture != null else "none"))
	await _shot("final_02_captain")
	# Every card of the hand sits in the hand area (none is left stranded on the battlefield).
	var hand_rect: Rect2 = screen._hand.get_global_rect()
	var stray: Array[String] = []
	for view: Node in screen._hand.get_children():
		if view is CardView and (view as CardView).visible:
			var centre := (view as CardView).get_global_rect().get_center()
			if centre.y < hand_rect.position.y - 40.0:
				stray.append("%s at %s" % [(view as CardView).card.get_card_name() if (view as CardView).card != null else "?", centre])
	check(stray.is_empty() and screen._hand.get_children().filter(func(v: Node) -> bool: return v is CardView).size() == screen.combat.deck.hand.size(), "every hand card sits in the hand (%s; hand rect %s)" % [", ".join(stray), hand_rect])
