extends Node
## Windowed: the Arcana + Holy combo on the real combat screen. The Aether counter beside Energy
## (shown only for parties with Aether cards), Chiara's draws and Energy filling it, the violet
## keyword on cards, and Lightfall releasing it with its pillar of light and the release burst.
##   godot --path . res://tests/ui/aether_ui_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_aether_ui.json"
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
	return SceneRouter.current_screen


func _give(screen: Node, card_id: String) -> CardInstance:
	var def := DataRegistry.get_card(card_id)
	var card := CardInstance.new()
	card.definition = def
	card.owner_character_id = def.owner_character_id
	card.owned_uid = "aether_" + card_id
	screen.combat.deck.hand.append(card)
	screen.combat.energy = 9
	screen._refresh()
	return card


func _play(screen: Node, card: CardInstance) -> void:
	if card.definition.target == CardDef.TARGET_SINGLE_ENEMY:
		screen._selected_card = card
		screen._play_selected(screen.combat.get_living_enemies()[0].id)
	else:
		screen._on_card_pressed(card)
	await _wait(0.3)


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	var screen := await _start("arcana", "holy")
	var box := screen.find_child("AetherBox", true, false) as Control
	var label := screen.find_child("AetherLabel", true, false) as Label
	check(box != null and box.is_visible_in_tree() and label.text == "0", "Arcana + Holy shows the Aether counter beside Energy (0)")
	check(box != null and box.tooltip_text.contains("surplus"), "the counter explains itself on hover")
	await _shot("aether_01_start")

	await _play(screen, _give(screen, "chiara_arcana_focus"))
	await _play(screen, _give(screen, "chiara_arcana_surge"))
	check(label.text == "3" and screen.combat.aether == 3, "Gathering Focus and Mana Surge fill it to 3 (%s)" % label.text)
	_give(screen, "bianca_holy_hymn")
	var lightfall := _give(screen, "bianca_holy_lightfall")
	await _wait(0.6)
	await _shot("aether_02_charged")
	var hymn_view: Control = null
	for view: Node in screen.find_children("*", "CardView", true, false):
		if (view as CardView).card != null and (view as CardView).card.definition.id == "bianca_holy_hymn":
			hymn_view = view
	var rules := hymn_view.find_children("*", "RichTextLabel", true, false) if hymn_view != null else []
	var bbcode := " ".join(rules.map(func(r: RichTextLabel) -> String: return r.text))
	check(bbcode.contains(CardTextFormat.AETHER_COLOR.to_html(false)), "Hymn of Dawn's text shows Aether in violet")

	var spawned: Array[String] = []
	var vfx: CombatVfxManager = screen._vfx
	vfx.effect_spawned.connect(func(effect_id: String, _node: CombatVfx) -> void: spawned.append(effect_id))
	var foe: Combatant = screen.combat.get_living_enemies()[0]
	foe.hp = 999
	foe.max_hp = 999
	await _play(screen, lightfall)
	await _shot("aether_03_lightfall")
	await _wait(0.5)
	check(int(screen.combat.last_hit.get("base", 0)) == 6 + 3 * 3, "Lightfall hits for 6 + 3 per Aether (15)")
	check(label.text == "0", "and releases the Aether (counter back to 0)")
	check(spawned.has("lightfall") and spawned.has("aether_release"), "a pillar of light on the foe and a release burst on Bianca (%s)" % ", ".join(spawned))

	# A party with no Aether cards never sees the counter.
	screen = await _start("fire", "tanking")
	box = screen.find_child("AetherBox", true, false) as Control
	check(box != null and not box.is_visible_in_tree(), "Fire + Tanking has no Aether cards: the counter is hidden")
